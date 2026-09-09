//! Statement executor — the DATA step loop. Given a parsed statement stream
//! (M0.2) it drives the implied loop SAS wraps every DATA step in:
//!
//!   compile once:  scan for the declaratives — `retain` (which vars survive
//!                  the top-of-loop reset, plus their one-time inits), `drop`/
//!                  `keep` (output schema), and the input source (`set`, or
//!                  `input`+`datalines`).
//!   each iteration: reset non-retained cells to missing → read the next
//!                  observation → run the statements → implicit `output` at the
//!                  bottom (unless the step contains an explicit `output`).
//!   stop:          when the input source is exhausted. A step with no input
//!                  source runs exactly once (else it would spin forever).
//!
//! It reads/writes one PDV (M0.3), evaluates expressions through the B1
//! `Evaluator` (shared pdv/diags/arena), and reads/writes datasets through the
//! C2 io layer. `put` output is collected into `log` for the CLI (C3) to print.
//!
//! Scope is the DATA-step surface the AST names. Declaratives are read at the
//! top level only; `data a b …;` names several output datasets and a bare /
//! implicit `output` fans out to all of them (`extra_outs`, BUG-multioutput);
//! approximate `put` spacing — each marked `ponytail:` where it bites. Grow
//! with the corpus.

const std = @import("std");
const Io = std.Io;
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const Value = @import("value.zig").Value;
const pdv_mod = @import("pdv.zig");
const Pdv = pdv_mod.Pdv;
const missingOf = pdv_mod.missingOf;
const Dataset = @import("dataset.zig").Dataset;
const eval = @import("eval.zig");
const io = @import("io.zig");
const format = @import("format.zig");
const lex = @import("lexer.zig");
const dsfns = @import("dsfns.zig"); // SCL dataset access, for CALL LABEL
const prx = @import("prx.zig"); // regex engine, for the CALL PRX routines
const fns = @import("functions.zig"); // shared toInt guard (BUG-combcallcrash)

// diag.Error (OutOfMemory + Lex/Parse/ExecError) so a step can abort LOUD — e.g.
// output access to an ACCESS=READONLY libref (GH#15). A superset of the old
// Allocator.Error, so every existing `try` still type-checks.
pub const Error = diag.Error;

/// GAP guard (D-009): the construct is valid SAS 9.4 opensas doesn't implement —
/// an opensas gap, exit 2 ("file an opensas issue"), not rc 1 ("fix your SAS").
/// Flag the gap, then fail with the usual loud ERROR (parser.zig/proc.zig's
/// `failGap`, same shape — no fourth helper). ONLY for guards matching a
/// SPECIFIC recognised valid construct; a catch-all that also swallows a typo
/// stays a plain `fail` unless it is SPLIT first (audit-exitcodecontract.md §5c).
/// The `report(.err) catch {}; return error.ExecError` sites in this file call
/// `diag.markGap()` inline instead — same signal, but they must keep reporting
/// through the two-line shape (a `fail` would change their OOM path).
fn failGap(diags: *diag.Diagnostics, comptime fmt: []const u8, args: anytype) Error {
    diag.markGap();
    return diags.fail(error.ExecError, 0, fmt, args);
}

/// Every method/attribute the SAS 9.4 Component Objects reference's own
/// "Dictionary of Hash and Hash Iterator Object Language Elements" names
/// (printed p.23, the TOC of the dictionary itself) — so a hash method that is
/// real-but-unimplemented can be told from a typo'd one. Closed by the doc, not
/// by us; the same shape as proc.zig's `isUnsupportedFreqStat`.
fn isHashMethod(name: []const u8) bool {
    inline for (.{
        "add",        "check",      "clear",     "definedata", "definedone", "definekey",
        "delete",     "do_over",    "equals",    "find",       "find_next",  "find_prev",
        "first",      "has_next",   "has_prev",  "item_size",  "last",       "next",
        "num_items",  "output",     "prev",      "ref",        "remove",     "removedup",
        "replace",    "replacedup", "reset_dup", "setcur",     "sum",        "sumdup",
    }) |m| if (eqi(name, m)) return true;
    return false;
}

/// Every CALL routine the SAS 9.4 Functions and CALL Routines reference names
/// (its dictionary's `CALL <NAME> Routine` headings) — the closed set that
/// splits "a routine we have not written" (gap, rc 2) from "the user misspelled
/// one" (rc 1). Reaching the catch-all already means unimplemented, so this list
/// needs no maintenance when a routine lands.
fn isCallRoutine(name: []const u8) bool {
    inline for (.{
        "allcomb",   "allcombi",     "allperm",       "cats",    "catt",     "catx",
        "compcost",  "execute",      "graycode",      "is8601_convert",      "label",
        "lexcomb",   "lexcombi",     "lexperk",       "lexperm", "logistic", "missing",
        "module",    "poke",         "pokelong",      "prxchange",           "prxdebug",
        "prxfree",   "prxnext",      "prxposn",       "prxsubstr",           "ranbin",
        "rancau",    "rancomb",      "ranexp",        "rangam",  "rannor",   "ranperk",
        "ranperm",   "ranpoi",       "rantbl",        "rantri",  "ranuni",   "scan",
        "set",       "sleep",        "softmax",       "sort",    "sortc",    "sortn",
        "stdize",    "stream",       "streaminit",    "streamrewind",        "symput",
        "symputx",   "system",       "tanh",          "tso",     "vname",    "vnext",
        "wto",
    }) |r| if (eqi(name, r)) return true;
    return false;
}

/// CALL STDIZE's three documented option categories, kept SEPARATE rather than
/// as one flat set because the diagnostic has to name the right one
/// (BUG-callstdizeoptmsg): only a standardization-option is a *method*.
const StdizeOptKind = enum { standardization, vardef, miscellaneous };

/// The option keywords CALL STDIZE documents (Functions ref printed p.419-421),
/// in the reference's own three groups. Callers pass the bare keyword — any
/// `=value` tail already stripped — so `MEDIAN` and `MULT=2` both resolve here
/// while `MEDAIN` does not.
fn stdizeOptKind(kw: []const u8) ?StdizeOptKind {
    // "standardization-options: specifies how to compute the location and scale
    // measures" — the ones the Details section itself calls methods ("This
    // option affects only the methods AGK=, IQR, MAD, and SPACING=").
    inline for (.{
        "abw",    "agk",  "ahuber", "awave",    "euclen", "iqr",     "l",   "mad",
        "maxabs", "mean", "median", "midrange", "range",  "spacing", "std", "sum",
        "ustd",
    }) |o| if (eqi(kw, o)) return .standardization;
    // "VARDEF-options: specifies the divisor to be used in the calculation of
    // variances" — a divisor, not a method.
    inline for (.{ "df", "n" }) |o| if (eqi(kw, o)) return .vardef;
    inline for (.{ "add", "fuzz", "missing", "mult", "norm", "pstat", "replace", "snorm" }) |o|
        if (eqi(kw, o)) return .miscellaneous;
    return null;
}

/// BUG-putptroom: ceiling for a PUT `@n` column-pointer target (parser.zig's
/// max_put_ptr guards +n / #n) — fail loud instead of padding gigabytes.
const max_put_ptr: usize = 32767;

/// Set when an `abort abend [n]` / `abort return n` / `abort n` fires
/// (BUG-abortreturncode): the session is dead — main halts every later step
/// and exits the process with this code (ABEND without n → 1). Reset per run
/// in main.interpret (wasm runs many programs per load).
pub var g_abort_rc: ?u8 = null;

/// A named table store, so `set foo;` can find the dataset a prior step made.
/// The CLI (C3) owns one across a program and registers each step's output.
/// `names`/`sets` stay the ordered append-only store (write order, iterated by
/// main.writeLibOutputs / PROC CONTENTS / vtable); `index` maps the case-folded,
/// WORK-stripped name → slot for O(1) create/find/SET (PERF-libscan, was O(M²)).
pub const Library = struct {
    arena: std.mem.Allocator,
    names: std.ArrayList([]const u8),
    sets: std.ArrayList(*Dataset),
    /// Canonical(lowercased, WORK-stripped) member name → slot in names/sets. A
    /// verified cache: PROC DATASETS (proc.zig) mutates names/sets directly, so
    /// `slotOf` reindexes when the arrays shrink/grow (delete) and verifies every
    /// hit (an in-place rename swapped the slot's name), with a linear-scan ground
    /// truth behind it (PERF-libscan).
    index: std.StringHashMapUnmanaged(usize) = .empty,
    /// Macro variables written from the DATA step via CALL SYMPUT/SYMPUTX. Lives
    /// for the whole program (persists across steps), the DATA-step→macro bridge.
    /// ponytail: the upfront macro pass can't yet read these back into a later
    /// `&var` (needs per-step re-expansion); the store is populated + queryable.
    macro_vars: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Full program text queued by CALL EXECUTE, FIFO. exec.zig can't re-enter
    /// the step driver (it lives in main.zig — circular import), so CALL
    /// EXECUTE only appends here and main.zig's `runExpanded` drains the queue
    /// after the current step finishes (FEAT-callexecute — same exec-writes/
    /// main-drains split as macro_vars).
    execute_queue: std.ArrayList([]const u8) = .empty,
    /// Variable labels for the CURRENT DATA step (LABEL statement / ATTRIB label=),
    /// keyed by lowercased name. Reset at each step start; read by VLABEL/VLABELX
    /// (via functions.zig's g_lib) and stamped onto the output dataset's columns.
    var_labels: std.StringHashMapUnmanaged([]const u8) = .empty,
    /// Librefs bound `access=readonly` (libref names; matched case-insensitively).
    /// Wired from main.zig; empty for pure in-memory runs so unit-test puts are
    /// never blocked. Output access to a member on one of these fails loud (GH#15).
    readonly_refs: []const []const u8 = &.{},
    /// The run's reporter, so `put` can emit the SAS read-only ERROR. Set by main.
    diags: ?*diag.Diagnostics = null,

    pub fn init(arena: std.mem.Allocator) Library {
        return .{ .arena = arena, .names = .empty, .sets = .empty };
    }

    /// True if `name` is a two-level `libref.member` whose libref is read-only.
    pub fn readonlyOut(self: *const Library, name: []const u8) bool {
        const dot = std.mem.indexOfScalar(u8, name, '.') orelse return false;
        for (self.readonly_refs) |r| if (std.ascii.eqlIgnoreCase(r, name[0..dot])) return true;
        return false;
    }

    /// Report the SAS "read-only library" ERROR for `name` and hand back the abort
    /// error. Public so main.zig can guard PROC SORT's in-place path (which mutates
    /// the source directly, never through `put`) with the identical message.
    pub fn failReadonly(self: *Library, name: []const u8) Error {
        const dot = std.mem.indexOfScalar(u8, name, '.') orelse name.len;
        if (self.diags) |d| {
            const up = try std.ascii.allocUpperString(self.arena, name);
            try d.report(.err, 0, "You cannot open {s} for output access. Library {s} is a read-only library.", .{ up, up[0..dot] });
        }
        return error.ExecError;
    }

    /// Set a variable label (name lowercased; label copied into the arena).
    pub fn setVarLabel(self: *Library, name: []const u8, label: []const u8) !void {
        const key = try std.ascii.allocLowerString(self.arena, name);
        try self.var_labels.put(self.arena, key, try self.arena.dupe(u8, label));
    }

    /// A variable's label, or null if none is defined.
    pub fn varLabel(self: *const Library, name: []const u8) ?[]const u8 {
        var buf: [256]u8 = undefined;
        if (name.len == 0 or name.len > buf.len) return null;
        return self.var_labels.get(std.ascii.lowerString(buf[0..name.len], name));
    }

    /// Set a macro variable (name lowercased; value copied into the arena).
    pub fn setMacroVar(self: *Library, name: []const u8, value: []const u8) !void {
        const key = try std.ascii.allocLowerString(self.arena, name);
        try self.macro_vars.put(self.arena, key, try self.arena.dupe(u8, value));
    }

    /// A macro variable's value, or null.
    pub fn macroVar(self: *const Library, name: []const u8) ?[]const u8 {
        var buf: [256]u8 = undefined;
        if (name.len == 0 or name.len > buf.len) return null;
        return self.macro_vars.get(std.ascii.lowerString(buf[0..name.len], name));
    }

    /// Create or replace a member. Output access to a read-only libref fails loud
    /// (GH#15) — the choke point for the DATA-step member write, PROC OUT=, and
    /// every proc that materializes a result. The disk loader preloads read-only
    /// INPUTS (legal read access) via `putInput`, which skips the guard.
    pub fn put(self: *Library, name: []const u8, ds: *Dataset) Error!void {
        if (self.readonlyOut(name)) return self.failReadonly(name);
        try self.putInput(name, ds);
        // BUG-syslastrefresh: a member was just CREATED or REPLACED — refresh
        // &SYSLAST/&SYSNOBS. This is the one place to do it: every producer
        // routes here (272 call sites — the DATA-step output, all 151 proc.zig
        // OUT= writes, PROC SORT, SQL CREATE TABLE, IMPORT), so there is no
        // per-PROC rule to get wrong and no sibling producer to miss.
        //
        // It is deliberately NOT in putInput, which is the other half of the
        // split: putInput also serves the disk loader's read-only INPUT preload
        // (main.zig, GH#15), and merely READING a data set in must not make it
        // "the most recently created". Same reason this sits AFTER the readonly
        // guard rather than before it — a write that FAILS creates nothing, so
        // it must not advance the pair.
        //
        // `data _null_;` needs no special case and gets none: main.zig already
        // skips the commit for it, so it never reaches here and the pair stays
        // put — which is the correct SAS behaviour for a step that creates
        // nothing, not an oversight.
        //
        // main.zig's existing drain of `macro_vars` into the macro session runs
        // at the end of each step flush, so a `%put` immediately after `run;`
        // already sees these — verified against the code rather than assumed,
        // and it is the same channel &SYSERR/&SYSCC already refresh through.
        //
        // &SYSNOBS is tied to the CREATED data set here, and the volume
        // CONTRADICTS ITSELF on that point, so this is a choice and not a
        // reading: the dictionary entry (printed p.272) says "the number of
        // observations that exist in the last data set that was CLOSED by the
        // previous procedure or DATA step", while the summary table (printed
        // p.32) says "the last data set CREATED by a procedure or DATA step".
        // Created is the half a create choke point can serve, it is what the
        // clinical `%if &sysnobs = 0` guard means, and "closed" would also count
        // data sets a step only READ. Recorded so nobody mistakes it for settled.
        // The doc's `-1` sentinel ("If the number of observations … was not
        // calculated") never applies to us — rowCount() is always known.
        try self.setMacroVar("syslast", try qualifiedUpper(self.arena, name));
        try self.setMacroVar("sysnobs", try std.fmt.allocPrint(self.arena, "{d}", .{ds.rowCount()}));
    }

    pub fn putInput(self: *Library, name: []const u8, ds: *Dataset) Error!void {
        // Replace an existing member: `data x; … data x; …` re-creates x, and
        // MODIFY commits the edited master back over itself. Without this, put
        // appended a duplicate and find (first match) kept returning the stale one.
        if (self.slotOf(stripWork(name))) |i| {
            self.sets.items[i] = ds;
            return;
        }
        // Index miss → a genuinely new member: append and index it (O(1) create).
        // ponytail: an in-place PROC DATASETS rename that hid an existing name from
        // the index could, if that exact name is then re-created, leave a shadowed
        // duplicate — closed by routing the proc.zig rename through a Library method.
        const key = try std.ascii.allocLowerString(self.arena, stripWork(name));
        try self.names.append(self.arena, try self.arena.dupe(u8, name));
        try self.sets.append(self.arena, ds);
        self.index.put(self.arena, key, self.sets.items.len - 1) catch {};
    }

    pub fn find(self: *Library, name: []const u8) ?*Dataset {
        const s = stripWork(name);
        if (self.slotOf(s)) |i| return self.sets.items[i];
        // Index miss: genuinely absent, OR an in-place PROC DATASETS rename added a
        // name the index never saw. Fall back to the authoritative scan so a renamed
        // member stays findable (dd_change_delete). SET/JOIN/PROC inputs hit the
        // index, so this scan runs only for the rare absent/renamed lookup.
        if (self.scanSlot(s)) |i| return self.sets.items[i];
        return null;
    }

    /// Verified O(1) index probe against the WORK-stripped name `s`. Reindexes first
    /// if the store shrank/grew behind the index (a proc.zig delete), and rejects a
    /// hit whose slot no longer holds this name (an in-place rename). null = not in
    /// the index (caller decides: append, or scan-fallback).
    fn slotOf(self: *Library, s: []const u8) ?usize {
        if (self.index.count() != self.names.items.len) self.reindex() catch {};
        var buf: [256]u8 = undefined;
        if (s.len == 0 or s.len > buf.len) return null;
        const key = std.ascii.lowerString(buf[0..s.len], s);
        if (self.index.get(key)) |i|
            if (i < self.names.items.len and std.ascii.eqlIgnoreCase(stripWork(self.names.items[i]), s)) return i;
        return null;
    }

    /// Ground-truth linear scan for the WORK-stripped name `s` — the fallback that
    /// keeps `find` correct across proc.zig's direct renames/deletes (PERF-libscan).
    fn scanSlot(self: *const Library, s: []const u8) ?usize {
        for (self.names.items, 0..) |n, i| if (std.ascii.eqlIgnoreCase(stripWork(n), s)) return i;
        return null;
    }

    /// Rebuild the name→slot index from the ordered store (after a proc.zig delete
    /// shifted slots). O(members); only runs when the arrays changed length.
    fn reindex(self: *Library) Error!void {
        self.index.clearRetainingCapacity();
        for (self.names.items, 0..) |n, i| {
            const key = try std.ascii.allocLowerString(self.arena, stripWork(n));
            try self.index.put(self.arena, key, i);
        }
    }
};

/// One entry of a SET/MERGE/UPDATE/MODIFY source list, split into the parts it
/// actually has: the member NAME and its dataset-option text.
///
/// The parser deliberately serializes `a(where=(x>15))` into ONE string so the AST
/// can stay a plain name list (parser.serializeParens says so), which means every
/// consumer has to split it back apart. Until now FIVE sites in this file did that
/// with their own inline `indexOfScalar(name, '(')` — and the sixth consumer,
/// `assertModifyMasterIsOutput`, did not, so it compared `a(where = ( x > 15 ) )`
/// against the DATA statement's `a` and could never match. The documented spelling
/// of a subsetted MODIFY was therefore unusable (BUG-modifymasteroptname), which
/// matters because Statements ref printed p.240 hangs `(data-set-options)` off the
/// MODIFY statement in all four Syntax Forms and its Notes say to put them there
/// "and not in the DATA statement" — so that spelling is not merely one option, it
/// is the only documented one.
///
/// This is deliberately ONE OWNER replacing five copies rather than a sixth
/// stripper beside them: a helper that the existing consumers also route through
/// cannot drift from them, because it IS them.
///
/// ponytail: the real fix is for the PARSER to carry name and options as separate
/// fields so nothing ever has to re-split. That is a wider change than this
/// ticket — the four source lists are `[]const []const u8` in ast.zig and ~20
/// consumers index them as plain names — so the encoding stays and gains a single
/// decoder. Scope reported rather than papered.
const SourceRef = struct {
    name: []const u8, // bare member, `a` or `lib.a`
    opts: []const u8, // option text between the outer parens, "" when there are none
};

fn splitSourceRef(entry: []const u8) SourceRef {
    const paren = std.mem.indexOfScalar(u8, entry, '(') orelse return .{ .name = entry, .opts = "" };
    // A serialized entry always closes its parens (serializeParens balances them);
    // the guard keeps a hand-built or truncated entry from slicing backwards.
    const close = if (entry.len > paren + 1) entry.len - 1 else paren + 1;
    return .{ .name = entry[0..paren], .opts = entry[paren + 1 .. close] };
}

/// A member name in &SYSLAST's form: two-level and UPPERCASE (`one` → `WORK.ONE`,
/// `perm.x` → `PERM.X`). SAS reports the qualified name, so a one-level name gets
/// the default libref — the inverse of `stripWork` below, which removes it for
/// lookups (BUG-syslastrefresh).
///
/// Macro Language ref printed p.266 (marker `=== pdf 281 ===`, offset -15 and the
/// page's own footer verified), SYSLAST's Details: "The name is stored in the form
/// libref.dataset. … If no SAS data set has been created in the current program,
/// the value of SYSLAST is _NULL_, with no leading or trailing blanks." The
/// uppercasing and the period are shown by the printed p.267 example (mixed-case
/// input `FirstLib.SalesRpt` logs as `FIRSTLIB.SALESRPT`) rather than asserted in
/// prose. The one-level → `WORK.x` mapping is NOT stated anywhere — it follows
/// from Language Reference: Concepts printed p.694 ("Data sets with one-level names are automatically
/// assigned to one of two SAS libraries: Work or User") plus the documented
/// libref.dataset form, so it is an inference and is recorded as one.
///
/// ponytail: UNPADDED, deliberately. That same p.267 example shows SAS padding the
/// value with trailing blanks and recommending `%TRIM(&syslast)` — but SYSLAST's
/// FIELD WIDTH is doc-silent (the sibling SYSDSN entry states 8+`_NULL_`+26 for
/// itself; SYSLAST's is never given), so padding would mean inventing a number
/// that `%put *&syslast*` renders visibly wrong either way. Unpadded also matches
/// the one padding fact the doc DOES state — the `_NULL_` seed carries "no leading
/// or trailing blanks" — and is what the documented `%TRIM` idiom yields. Upgrade
/// if an oracle supplies the width.
fn qualifiedUpper(a: std.mem.Allocator, name: []const u8) ![]const u8 {
    const two = std.mem.indexOfScalar(u8, name, '.') != null;
    const out = if (two)
        try std.ascii.allocUpperString(a, name)
    else
        try std.fmt.allocPrint(a, "WORK.{s}", .{try std.ascii.allocUpperString(a, name)});
    return out;
}

/// Drop a leading `work.` from a (possibly two-level) dataset name.
fn stripWork(name: []const u8) []const u8 {
    return if (name.len >= 5 and std.ascii.eqlIgnoreCase(name[0..5], "work.")) name[5..] else name;
}

/// A `length`-declared variable, in declaration order, used to pre-seed the PDV
/// so output columns follow SAS variable order. `type` picks the missing kind.
pub const DeclVar = struct {
    name: []const u8,
    type: pdv_mod.VarType,
    len: usize = 0,
    // GH#70: this LENGTH statement is textually AFTER a SET/MERGE that already
    // brought the variable in — so a char LENGTH on a numeric source var is the
    // fatal "Character length cannot be used with numeric variable" conflict. A
    // LENGTH placed BEFORE the SET (false) is schema-pinning and coerces leniently.
    after_input: bool = false,
    // BUG-varorder: a RETAIN/FORMAT/INFORMAT/INPUT/assignment statement precedes
    // this LENGTH/ATTRIB in source (in a step with no SET/MERGE) — SAS establishes
    // those vars first, so this var is seeded AFTER declareVars, not in the
    // pre-pass. (main.lengthVars decides; SET steps keep the old pre-pass order
    // because seedColumnsOf's GH#69/#70 conflict checks need the pin in place.)
    late: bool = false,
};

/// How a false subsetting `if` unwinds the current iteration.
/// How a statement list unwound. `continue_`/`leave` target the nearest enclosing
/// DO loop (runDo consumes them); the others propagate to the step loop.
const Flow = enum { normal, deleted, stop, continue_, leave, returned, goto_, link_ };

const RetainInit = struct { name: []const u8, expr: *const ast.Expr };
/// A `retain _NUMERIC_ 0;`-style item: the kind of special name list plus its
/// optional seed, expanded against the PDV once declareVars completes it.
const SpecialRetain = struct { kind: ast.SpecialArr, init: ?*const ast.Expr };

/// Match-merge cursor. `by_cols[d][j]` is the column index of BY-var `j` in
/// dataset `d` (null if that dataset lacks it → its key reads missing). Each
/// `mergeNext` emits one combined observation: within a BY group it reads the
/// i-th row of every source that still has one (a shorter source retains its
/// last row; a source without the group contributes nothing → missing).
const MergeState = struct {
    dss: []*Dataset,
    by_cols: []const []const ?usize,
    cur: []usize, // next unread row per source
    group_start: []usize, // this group's first row per source
    group_count: []usize, // this group's row count per source (0 = absent)
    iter: usize = 0, // iteration within the current group
    iters: usize = 0, // group size = max group_count
    active: bool = false, // a group is loaded
    in_vars: []const ?[]const u8 = &.{}, // per-source `in=` flag variable (or null)
    // Per-BY-var truncation width for the group comparison (BUG-mergebyvarlen):
    // a CHAR BY var's output length is the first source's declared length (SAS
    // Language Reference: Concepts p.559), and SAS truncates every source's value to it BEFORE grouping
    // — so a longer value in a later source collides with the shorter prefix.
    // 0 = numeric or no declared width → compare raw. Length == nby.
    by_len: []const usize = &.{},
    prev_g: ?[]Value = null, // last group's BY key — detects unsorted input (BUG-mergeunsorted)
    slots: []const []usize = &.{}, // per-source column→PDV-slot maps for loadRow (PERF-loadrowdual)
    // first./last. BY-flag levels for the current group (BUG-mergefirstlast):
    // level >= first_level is 1 on the group's first obs (where the key first
    // differs from the previous group's), level >= last_level is 1 on its final
    // obs (vs the next group's key; 0 = every level when there is no neighbor).
    first_level: usize = 0,
    last_level: usize = 0,
};

/// A hash-object entry: the key value tuple and the data value tuple it maps to.
const HashEntry = struct { keyvals: []const Value, datavals: []const Value };

/// `ordered:` constructor option — the iteration/output order of a hash's
/// entries. `.none` keeps insertion order (SAS default).
const HashOrder = enum { none, asc, desc };

/// Hash + eql context for the key-tuple → slot index (PERF-hashscan). eql delegates
/// to `tupleEq` so map membership can never drift from the linear-scan semantics;
/// `hash` must agree with it: equal tuples hash equal. Canonicalizations to match
/// `cmpValueOrd`: missings bucket by special-missing rank (.A ≠ .,
/// BUG-execmissdistinct); -0.0 → +0.0; a char value's trailing blanks are
/// insignificant (SAS blank-pad compare).
/// A per-value type tag keeps a numeric key and a char key in different buckets.
const TupleCtx = struct {
    pub fn hash(_: TupleCtx, key: []const Value) u64 {
        var w = std.hash.Wyhash.init(0);
        for (key) |v| switch (v) {
            .num => |x| {
                w.update(&[_]u8{0}); // type tag: numeric
                if (std.math.isNan(x)) {
                    w.update(&[_]u8{Value.missingRank(x)}); // .A and . bucket apart
                } else {
                    const bits: u64 = @bitCast(if (x == 0) @as(f64, 0) else x);
                    w.update(std.mem.asBytes(&bits));
                }
            },
            .str => |s| {
                w.update(&[_]u8{1}); // type tag: char
                w.update(std.mem.trimEnd(u8, s, " ")); // trailing blanks insignificant
            },
        };
        return w.final();
    }
    pub fn eql(_: TupleCtx, a: []const Value, b: []const Value) bool {
        return tupleEq(a, b);
    }
};

const HashIndex = std.HashMapUnmanaged([]const Value, usize, TupleCtx, std.hash_map.default_max_load_percentage);

/// A DATA-step hash object (`declare hash h;`): the key/data variable names and
/// the stored entries. `entries` is the append-only ORDERED store (hiter / ordered:
/// output walk it in order); `index` maps the key tuple → the FIRST slot holding
/// it for O(1) add/find/check/replace/remove (PERF-hashscan). With multidata:'y'
/// several entries share one key: the index keeps the first, find_next() walks
/// the rest in insertion order (BUG-hashmultidata). Slots are stable across
/// appends, so the index only needs a rebuild after a reorder (remove or an
/// `ordered:` sort).
const HashDuplicate = enum { keep_first, replace, err };

const HashObject = struct {
    name: []const u8,
    keys: std.ArrayList([]const u8) = .empty, // defineKey variable names
    datas: std.ArrayList([]const u8) = .empty, // defineData variable names
    entries: std.ArrayList(HashEntry) = .empty,
    index: HashIndex = .empty, // key tuple → first entries slot (PERF-hashscan)
    src: ?[]const u8 = null, // `dataset:"name"` — loaded on defineDone
    done: bool = false,
    iter_of: ?[]const u8 = null, // `declare hiter hi("h")` — the hash this walks
    iter_pos: usize = 0, // current entry index for first()/next()
    iter_on: bool = false, // a first/last/next/prev has POSITIONED the cursor (p.621's "pointing to the key")
    ordered: HashOrder = .none, // `ordered:` — iteration/output key order (BUG-hashordered)
    multidata: bool = false, // `multidata:'y'` — allow many records per key (BUG-hashmultidata)
    duplicate: HashDuplicate = .keep_first, // `duplicate:` — dup-key add policy (BUG-hashduplicate)
    md_key: ?[]const Value = null, // key tuple of the last successful find (find_next cursor)
    md_slot: usize = 0, // entries slot of the last successful find/find_next
};

/// The per-iteration input source, resolved once from the program's
/// declaratives. `once` runs the body a single time (no read).
/// `set a b;` input. Plain SET reads the datasets end-to-end (concatenate) via
/// the `di`/`ri` cursor. `set a b; by x;` INTERLEAVES the pre-sorted sources by
/// the BY key (BUG-setinterleave): `by_cols` non-null switches on the per-dataset
/// `cursors`, and each read picks the dataset whose current row has the smallest
/// BY tuple (ties → lowest source index, i.e. `set a b` order).
const SetState = struct {
    dss: []*Dataset,
    di: usize = 0, // concatenate: current dataset
    ri: usize = 0, // concatenate: current row within `di`
    by_cols: ?[]const []const ?usize = null, // per-dataset BY column indices; null → concatenate
    cursors: []usize = &.{}, // interleave: per-dataset next-row index
    prev_by: ?[]Value = null, // last emitted BY key — detects unsorted input (BUG-setbyunsorted)
    last_contrib: ?usize = null, // source of the last read — a change resets SET vars (BUG-setsourcereset)
    in_vars: []const ?[]const u8 = &.{}, // per-source `in=` flag variable (or null)
    any_in: bool = false, // any non-null in_vars entry — gates the per-row scan (PERF-setinflagquad)
    slots: []const []usize = &.{}, // per-source column→PDV-slot maps for loadRow (PERF-loadrowdual)
};

/// `update master trans; by k;` input. Both sources are sorted by the BY key,
/// unique in the master. One output row per master BY group: the master values
/// with each matching transaction obs applied in order (a non-missing transaction
/// value overwrites; a missing one keeps master). A transaction key absent from
/// the master is added as a new obs; a master key with no transaction passes
/// through unchanged.
const UpdateState = struct {
    master: *Dataset,
    trans: *Dataset,
    m_by: []const ?usize, // master's BY column indices
    t_by: []const ?usize, // transaction's BY column indices
    mi: usize = 0, // master row cursor
    ti: usize = 0, // transaction row cursor
    prev_g: ?[]Value = null, // last group's BY key — detects unsorted input (BUG-setbyunsorted)
    m_slots: []const usize = &.{}, // master's column→PDV-slot map for loadRow (PERF-loadrowdual)
    t_slots: []const usize = &.{}, // transaction's, for the per-read reset (BUG-prefixmergewipe)
};

/// An ADDITIONAL SET statement beyond the driving one (MULTISET-impl). SAS makes
/// every SET executable with its OWN read position, so `set a; set b;` reads a[k]
/// and b[k] in parallel and `if _n_=1 then set summary;` reads summary once and
/// retains it. opensas drives the loop off the first SET (the `sets` Driver);
/// each extra SET is an executable node with this independent concatenate cursor,
/// read in runStmt. `node` is the AST identity used to match the statement.
const ExtraSet = struct {
    node: *const ast.Stmt,
    dss: []*Dataset,
    di: usize = 0, // current source dataset
    ri: usize = 0, // current row within `di`
    slots: []const []usize = &.{}, // per-source column→PDV-slot maps for loadRow (PERF-loadrowdual)
};

/// `modify master trans; by k;` input. TRANSACTION-driven (BUG-modifybymasterdriven):
/// one DATA-step iteration per TRANSACTION observation — Language Reference: Concepts p.596 counts exactly
/// 3 REPLACEs + 3 OUTPUTs = the 6 transaction rows of the p.595 program, and p.599
/// Table 23.4 has NO `_IORC_` code for "a master row with no transaction" because
/// that iteration does not exist. Each transaction obs is matched to its master
/// obs (duplicates match in order — Table 23.3 allows duplicate BY in both);
/// master obs no transaction names are never loaded and are re-emitted untouched
/// by the rebuild-commit (modifyFlush).
const ModifyState = struct {
    master: *Dataset,
    trans: *Dataset,
    m_by: []const ?usize, // master's BY column indices
    t_by: []const ?usize, // transaction's BY column indices
    ti: usize = 0, // transaction row cursor — THE driver
    m_hint: usize = 0, // master scan start (a repeated key continues past the last match)
    cur_m: ?usize = null, // master row of the current matched iteration (REPLACE/REMOVE target)
    prev_key: ?[]Value = null, // previous transaction's BY tuple (first./last. + _DSEMTR)
    prev_match: bool = false, // previous iteration matched a master obs
    m_slots: []const usize = &.{}, // master's column→PDV-slot map for loadRow (PERF-loadrowdual)
    t_slots: []const usize = &.{}, // transaction's, for the per-read reset (BUG-prefixmergewipe)
    // BUG-modifywhereopt: filtered-iteration row → MASTER row, 1-based, as
    // io's `obs_out` reports it. Empty when nothing filtered (iteration index IS
    // the master index). `master` is always the UNFILTERED member so the flush
    // re-emits every row, including the ones the filter hid.
    src_pos: []const usize = &.{},
    // GAP-modifywherestmt: the FILTERED copy the BY driver scans/matches/loads
    // (filter-then-match — Statements ref printed p.360 "SAS selects observations
    // from each input data set before it combines them"; printed p.245 "uses
    // dynamic WHERE processing to locate the matching observation"). Null =
    // nothing row-filtered the BY master: scan `master` directly, exactly as
    // before. `flush_slots` are the master's own column→PDV slots for the
    // flush's untouched-row loads — m_slots stays the SCANNED copy's (the two
    // differ only when a keep=/drop= rides along with a row filter).
    scan: ?*Dataset = null,
    flush_slots: []const usize = &.{},
    repl: std.AutoHashMapUnmanaged(usize, ?[]Value) = .empty, // master row → rebuilt obs (null = REMOVEd)
    appends: std.ArrayList([]Value) = .empty, // OUTPUT-added obs — land at the END (in-place semantics)
    flushed: bool = false,
};

const Driver = union(enum) {
    once: bool, // true after its one iteration is spent
    lines, // datalines/infile input — the cursor lives on `Executor.li`; the INPUT
    // statement reads at run time (execInput), so several INPUTs per iteration and a
    // trailing `@` line hold compose (PG-atptr). loadNext just gates the iteration.
    sets: SetState,
    merge: MergeState,
    update: UpdateState,
    modify: ModifyState,
};

const ModifyNomatch = enum { none, first, subsequent };

/// Line-input cursor shared by the `.lines` iteration gate and the run-time INPUT
/// executor. `hold_iter` is a single trailing `@` (the line is held for the next
/// INPUT in this iteration, released when control returns to the top of the step);
/// `hold_across` is `@@` (the hold survives the iteration boundary). Both keep the
/// byte cursor `pos` into record `cur` so the next INPUT resumes mid-line.
const LineInputState = struct {
    // Mutable element slice: `_infile_ = …` writes THROUGH to the held record
    // (BUG-infilevarnoop). Every backing array is arena-built (parser
    // toOwnedSlice / readInfileLines) — never static memory.
    lines: [][]const u8 = &.{},
    cur: usize = 0,
    pos: usize = 0,
    hold_iter: bool = false,
    hold_across: bool = false,
    eof: bool = false,
};

/// One INFILE statement as recorded by scan (BUG-multiinfilelastwins) —
/// `stmt` keys the run-time source switch (null only for a unit test's
/// directly-injected `x.infile`, which has no statement to key on).
/// `src` is filled by run(): the LineSource index this statement selects.
const InfileSpec = struct { stmt: ?*const ast.Stmt, spec: ast.Infile, src: usize = 0 };

/// One declared line-input source (BUG-multiinfilelastwins): every INFILE
/// statement declares its OWN source — its own records, read cursor, and
/// options — and EXECUTING the statement makes it current (SAS: an INPUT
/// reads the file of the most recently executed INFILE; Language Reference: Concepts Table 20.4
/// row 5 stops the step when EOF is first reached on ANY of them). With no
/// INFILE statement the datalines block is the single implicit source.
const LineSource = struct {
    spec: ast.Infile, // options (dlm/dsd/overflow/end_var…)
    lines: [][]const u8 = &.{}, // records (file content or the datalines block)
    li: LineInputState = .{}, // saved cursor — live in `Executor.li` while current
};

pub const Executor = struct {
    arena: std.mem.Allocator,
    pdv: *Pdv,
    diags: *diag.Diagnostics,
    ev: *eval.Evaluator,
    lib: *Library,
    log: std.ArrayList(u8) = .empty, // `put` output, for the CLI to print
    vnext_idx: usize = 0, // CALL VNEXT cursor over PDV variables

    // filled by `scan`
    retained: std.ArrayList([]const u8) = .empty,
    array_names: std.ArrayList([]const u8) = .empty, // every ARRAY name this step (bare-name misuse check, BUG-arrayinitvalidate)
    retain_inits: std.ArrayList(RetainInit) = .empty,
    special_retains: std.ArrayList(SpecialRetain) = .empty, // `retain _numeric_ 0;` — expanded post-declareVars
    keep_mode: bool = false, // a KEEP stmt was seen — stays on even if `_numeric_` expands to 0 names
    drops: std.ArrayList([]const u8) = .empty,
    keeps: std.ArrayList([]const u8) = .empty,
    // PERF-arraydeclquad: lowercased-name membership sets backing drops/keeps/
    // retained — a linear nameIn scan per PDV var per row is O(N²) for a
    // `_temporary_` array of N (and O(C²) for a wide RETAIN reset). Built once
    // by freezeNameLists after buildDriver (the last append site); a list with
    // a `pfx:` wildcard keeps the linear scan (a hash can't prefix-match).
    // Mirrors Pdv.index (folded keys, stack-fold lookup, oversized → linear).
    drops_set: std.StringHashMapUnmanaged(void) = .empty,
    keeps_set: std.StringHashMapUnmanaged(void) = .empty,
    retained_set: std.StringHashMapUnmanaged(void) = .empty,
    renames: std.ArrayList(ast.RenamePair) = .empty, // `rename a=b;` → output-var renames
    set_names: ?[]const []const u8 = null,
    extra_sets: std.ArrayList(ExtraSet) = .empty, // MULTISET-impl: 2nd/conditional SET nodes, each with its own cursor
    // BUG-nestedsetopts: non-driver SET nodes with their end=/point= sentinels
    // already pulled (extractSetOptions walk) — collectExtraSetsStmt resolves
    // THESE names, never the raw node list (which still holds the sentinel).
    extra_src_names: std.AutoHashMapUnmanaged(*const ast.Stmt, []const []const u8) = .empty,
    dow_set: ?*const ast.Stmt = null, // DOWLOOP-impl: the SET whose reads are driven by an enclosing DO loop
    driver_ptr: ?*Driver = null, // the live driver, so a DOW SET can advance it from runStmt
    // BUG-setstmtorder: the DIRECT top-level source statement each scan arm
    // registered (set keeps the first, merge/update/modify the last — mirroring
    // the name lists). Only a direct member of the top-level program slice can
    // split the iteration around its read; a source nested in an IF branch or
    // DO body stays null here and keeps read-first (BUG-nestedsetdriver /
    // BUG-setpoint depend on it).
    drv_set: ?*const ast.Stmt = null,
    drv_merge: ?*const ast.Stmt = null,
    drv_update: ?*const ast.Stmt = null,
    drv_modify: ?*const ast.Stmt = null,
    driver_stmt: ?*const ast.Stmt = null, // resolved post-scan by buildDriver's priority
    split_pc: ?usize = null, // op index where driver_stmt's ops begin (compileProgram)
    // BUG-linkacrossset: the LINK return stack is executor-wide (was local to
    // runProgramRange) so a LINK issued in one half of the split op stream can
    // run its label block in the OTHER half and RETURN — Language Reference: Concepts p.485 Table
    // 20.3: LINK "return[s] control of the program to the next statement
    // following the LINK statement", so it can never skip or re-run the read.
    link_stack: std.ArrayList(usize) = .empty,
    set_end_var: ?[]const u8 = null, // `set a end=e;` → 1 on the last obs (BUG-setend)
    set_point_var: ?[]const u8 = null, // `set a point=i;` → direct-access obs i (BUG-setpoint)
    // BUG-pointredefinesnobs: ALL the datasets point= reads from, in statement
    // order, addressed as ONE concatenation — `set a b point=p;` reaches obs
    // 1..a+b, not just a's. This used to be a single `*Dataset` bound to the
    // FIRST resolvable name, which is what silently shrank both the read set
    // and NOBS=.
    set_point_dss: []const *Dataset = &.{},
    set_point_slots: []const []const usize = &.{}, // per-source column→PDV-slot map (PERF-loadrowdual)
    // GAP-secondsetstmt: the SET node that CARRIES the point= option when the
    // direct-access lookup rides a SECOND SET beside a sequential driver
    // (Statements ref p.341 Example 6: `set revenue; … set expense point=_n_;`).
    // null = the point source is the driver list's own SET (a POINT=-only step,
    // or a lookup beside a MERGE/UPDATE/INPUT driver — BUG-pointmergelookup).
    set_point_node: ?*const ast.Stmt = null,
    // BUG-pointsuppressesalloutput: is POINT= what DRIVES this step, or does a
    // `set ds point=v;` merely READ alongside a MERGE/UPDATE/INPUT driver? Only
    // a POINT=-driven step lacks EOF detection (Language Reference: Concepts p.488) and drops its
    // implicit output; accompanied by a driver, the read is the documented
    // direct-access lookup (SAS 9.4 Statements ref, SET Example 6) and Language Reference: Concepts
    // p.477 step 5's automatic output stands. Set by buildDriver — the one
    // place that knows which driver won.
    point_driven: bool = false,
    // BUG-pointnoiterate (Language Reference: Concepts p.488): a POINT= step cannot detect EOF, so it
    // iterates until STOP/ABORT/an out-of-range read — each successful direct
    // read re-arms the .once driver for one more implicit iteration. This map
    // (obs → iteration first read) spots a read REPEATING an obs from an
    // EARLIER iteration: the step is re-reading with no progress, where SAS
    // loops forever (p.488's "usually requires a STOP") — stop it instead of
    // hanging. Reads are bounded by the obs count, so this always terminates.
    point_reads: std.AutoHashMapUnmanaged(usize, usize) = .empty,
    nobs_var: ?[]const u8 = null, // `set a nobs=n;` target — set before the loop (BUG-setpoint-doloop)
    obs_src: ?*const Dataset = null, // source `_setobs_` was last stamped for (PERF-loadrowdual)
    nobs_total: ?usize = null, // multi-source SET nobs= total (GAP-nobsmultisrc); null → current source's count
    nobs_phys: std.AutoHashMapUnmanaged(*const Dataset, usize) = .empty, // resolved copy → PHYSICAL pre-slice row count (BUG-pointnobs)
    // Runtime-populated vars the GH#75 uninit scan must not note (BUG-spuriousnote):
    // SET/MERGE in= flag vars (drivers set them per read) and hash-method
    // assignment targets (`rc = h.first();` — hashOp writes rc at run time).
    uninit_exempt: std.ArrayList([]const u8) = .empty,
    // BUG-declaredobjnamevalue: every name this step declares as a COMPONENT
    // OBJECT (`declare hash h;` / `declare hiter hi;` / `h = _new_ hash();`,
    // all one `.hash_decl`). Collected by the compile walk, not at run time:
    // Component Objects Ref printed p.12 — "The DECLARE statement tells the
    // compiler that the object reference myhash is of type hash" — so the name
    // is an object for the WHOLE step, before its declare has executed.
    // `run` hands the Evaluator a pointer to this list; a bare object name in
    // any expression then fails LOUD there instead of yielding missing.
    obj_names: std.ArrayList([]const u8) = .empty,
    merge_names: ?[]const []const u8 = null, // `merge a b;` match-merge sources
    update_names: ?[]const []const u8 = null, // `update master trans;` master + transaction
    update_nomissingcheck: bool = false, // UPDATEMODE=NOMISSINGCHECK (GAP-updatemode)
    modify_names: ?[]const []const u8 = null, // `modify master trans;` — transaction-driven stream, in place
    dl_lines: ?[][]const u8 = null,
    in_items: ?[]const ast.InputItem = null,
    li: LineInputState = .{}, // datalines/infile read cursor (run-time INPUT; PG-atptr)
    by_vars: ?[]const []const u8 = null, // `by …;` grouping vars (SET input assumed sorted)
    by_desc: []const bool = &.{}, // per-key descending flag, len == by_vars.len (BY DESCENDING, GAP-batch-qa107)
    by_notsorted: bool = false, // BY NOTSORTED: skip the sorted check; groups form on consecutive equal values
    first_names: []const []const u8 = &.{}, // precomputed "first.<var>" PDV names
    last_names: []const []const u8 = &.{}, // precomputed "last.<var>"  PDV names
    prev_by: ?[]Value = null, // previous obs's BY-values, for first. detection
    formats: std.ArrayList(ast.FormatItem) = .empty, // `format` stmt → column display formats
    // Variable attributes (FORMAT/INFORMAT/LABEL) to stamp on the PDV var eagerly
    // once it exists, so VFORMAT*/VINFORMAT*/VLABEL see them mid-step, not only at
    // output (EXEC-varattr). fmt encodes the kind: leading \x00 = label, \x01 =
    // informat, otherwise a display format.
    attrs: std.ArrayList(ast.FormatItem) = .empty,
    // PDV var count at the last applyAttrs run: re-stamping is idempotent, so it
    // only matters when a NEW var appeared (a previously-unmatched attr can now
    // match). Skipping when unchanged turns the per-statement stamp from
    // O(attrs×vars) into O(1), which is what made a large SDTM program time out (BUG-xohang).
    attrs_applied_at: usize = std.math.maxInt(usize),

    has_output: bool = false,
    // MODIFY REPLACE/REMOVE (FEAT-datamodify-rest): per-iteration flag — an explicit
    // REPLACE (re-emit) or REMOVE (drop) overrides the implicit end-of-obs REPLACE
    // for THIS obs only. Reset each iteration; unlike step-level has_output, an
    // untouched obs still gets the default implicit REPLACE (keeps the master row).
    obs_handled: bool = false,
    // MODIFY-BY `_IORC_` state: `.none` = matched (_SOK); `.first` = a
    // transaction key with no master obs (_DSENMR, BUG-modifybynomatch);
    // `.subsequent` = a CONSECUTIVE repeat of the same unmatched key (_DSEMTR,
    // p.599 Table 23.4 — NOTE-modifydsemtr). The loop top stamps _IORC_ +
    // _ERROR_=1 and suppresses the implicit REPLACE for a no-match obs; the
    // iteration end raises the Language Reference: Concepts p.600 ERROR unless the program cleared
    // _ERROR_ itself.
    modify_nomatch: ModifyNomatch = .none,
    modify_by: ?*ModifyState = null, // non-null while a MODIFY-BY step runs (routes REPLACE/REMOVE/OUTPUT)
    cur_out: ?*Dataset = null, // the step's output dataset, reachable from `output;`
    /// Non-primary outputs of `data a b …;` (DSMULTI), created and registered
    /// by main.zig before the step runs (so all named datasets EXIST even when
    /// zero observations are written). SAS 9.4 Language Reference: Concepts, DATA statement: when the
    /// DATA statement names multiple output data sets, the implicit output at
    /// the bottom of the step — and a bare `output;` — writes the current
    /// observation to EVERY one; only an explicit `output name;` routes a
    /// single target (BUG-multioutput).
    extra_outs: []const *Dataset = &.{},
    hashes: std.ArrayList(*HashObject) = .empty, // `declare hash …` objects, live for the step
    declared: []const DeclVar = &.{}, // `length` variables, in declaration order (fixes column order)
    n_iter: usize = 0, // `_N_` automatic iteration counter
    // `_INFILE_` was referenced this step (BUG-infilebufvar): maybeNoteUninit
    // defines it as a char automatic; execInput then publishes each record.
    refs_infile: bool = false,
    pending_label: []const u8 = "", // GOTO/LINK target, carried out to runProgram
    // Flattened step body (BUG-controlflownesting): the whole program compiled to
    // a linear op stream with resolved label offsets — labels at ANY nesting depth
    // are reachable and a LINK return resumes at the op after the link call site,
    // even mid-loop. Compiled once per step by compileProgram (called from run()).
    ops: []const Op = &.{},
    io: ?std.Io = null, // external file I/O for INFILE/FILE; null → no-op (unit tests stay IO-free)
    // BUG-multiinfilelastwins: the step's line sources — one spec per INFILE
    // statement (scan, program order), one built source per spec (run).
    // `infile`/`infile_end_var` cache the CURRENT source's options for
    // execInput / the .lines gate; `infile` also stays the unit-test
    // injection channel for a statement-less single infile.
    infile_specs: std.ArrayList(InfileSpec) = .empty,
    sources: std.ArrayList(LineSource) = .empty,
    src_of_stmt: std.AutoHashMapUnmanaged(*const ast.Stmt, usize) = .empty, // INFILE statement → infile_specs index
    cur_src: ?usize = null, // sources index owning the live cursor in `li`
    infile: ?ast.Infile = null, // current source's options (or test injection)
    infile_end_var: ?[]const u8 = null, // current source's END= target (FEAT-infileend)
    where_expr: ?*const ast.Expr = null, // `where expr;` — pre-read input filter (GAP-vtabledisk)
    file: ?ast.File = null, // `file "path" …;` — external `put` destination + DLM=/DSD options
    file_out: std.ArrayList(u8) = .empty, // buffered FILE output, flushed at step end

    pub fn init(arena: std.mem.Allocator, p: *Pdv, d: *diag.Diagnostics, ev: *eval.Evaluator, lib: *Library) Executor {
        p.diags = d; // wire the run's reporter so Pdv.set can NOTE char→num conversions (ISS-charnumassign)
        return .{ .arena = arena, .pdv = p, .diags = d, .ev = ev, .lib = lib };
    }

    /// Execute one DATA step, filling `out` with its observations.
    pub fn run(self: *Executor, program: ast.Program, out: *Dataset) Error!void {
        self.cur_out = out;
        self.lib.var_labels.clearRetainingCapacity(); // labels are per-step (like self.formats)
        // BUG-declaredobjnamevalue: register this step's component-object names
        // FIRST — before `retain` inits or anything else can evaluate an
        // expression — and point the Evaluator at the list. Both are per-step
        // (main.zig builds an Executor + Evaluator per DATA step), so a name
        // that is an object here is an ordinary variable in the next step.
        for (program) |*s| try self.collectObjectNames(s);
        self.ev.objects = &self.obj_names;
        try self.scan(program, false, true);

        // Unit tests inject a bare `x.infile` with no INFILE statement in the
        // program (ISS-infilemissing / PERF-infilecap) — treat it as the
        // step's one statement-less source spec.
        if (self.infile_specs.items.len == 0) if (self.infile) |inf|
            try self.infile_specs.append(self.arena, .{ .stmt = null, .spec = inf });

        // BUG-setstmtorder: the driving source statement, by buildDriver's
        // priority (update > modify > merge > set). Only DIRECT top-level
        // members were recorded by scan, so a nested/promoted driver (DOW,
        // POINT=, extractNestedSetOpts) leaves this null → no split below.
        self.driver_stmt = if (self.update_names != null) self.drv_update else if (self.modify_names != null) self.drv_modify else if (self.merge_names != null) self.drv_merge else self.drv_set;

        // BUG-controlflownesting: flatten the step body (labels/goto/link/do/if →
        // absolute-PC ops) BEFORE anything runs. An undefined GOTO/LINK target is
        // a SAS compile-time error — reported here, and the hasStepErrors() gate
        // below halts the step before a single observation is written (F3).
        try self.compileProgram(program);

        try self.expandPrefixLists(); // ISS-setdslist: `set a:;` → all a-prefixed members
        try self.extractSetOptions(program); // pull end=/point= sentinels out of every source list
        try self.assertModifyMasterIsOutput(); // BUG-modifyoutnamemismatch — before ANY row is written

        // DOWLOOP-impl (was BUG-dowloop guard): a SET nested in a DO until/while
        // loop is a "DOW loop" — SAS 9.4 reads the NEXT obs at the inner SET on
        // each DO iteration, accumulates across the group, and outputs once per
        // outer DATA-step pass (SAS Language Reference: "DO UNTIL/WHILE with SET").
        // detectDowSet marks that SET so its read fires at the node (runStmt) and
        // the outer loop only GATES on remaining rows; unsupported shapes (a DOW
        // SET inside an iterative DO, or a DOW mixed with another SET) fail LOUD.
        if (self.set_point_var == null) try self.detectDowSet(program);

        // SAS builds the PDV at compile time. Pre-declare the `length` variables
        // (define-only, so no value is wiped) so the output columns come out in
        // declaration order — SET columns and assignments then fill them in place,
        // and variables SET adds appear after. (main supplies this list.)
        // BUG-varorder: vars whose LENGTH/ATTRIB follows another declaring
        // statement (`.late`) are NOT seeded here — see the declareVars call below.
        for (self.declared) |dv| if (!dv.late) try self.seedDeclVar(dv);

        // GAP-varorder-assignset / BUG-varorder-setretain: every statement BEFORE
        // the step's input statement establishes its variables ahead of the input
        // dataset's columns — Language Reference: Concepts printed p.47, "position in observation is
        // determined by the order in which the variables are defined in the DATA
        // step". So the declare walk is SPLIT at the input statement rather than
        // run wholly after it: the prefix half here, the rest below in its old
        // place. Every statement is still declared exactly once, by the SAME
        // declareStmt that models what a statement defines — RETAIN, the sum
        // statement's injected `retain v 0;`, a plain assignment, LENGTH-less
        // FORMAT/INFORMAT, ARRAY, a DO index. The old raw-token scanRetainOrder
        // enumerated statement KINDS in the parser and so knew only RETAIN and the
        // sum statement (`y = 1; set a;` ordered y AFTER a's columns while the
        // equivalent `retain y 1; set a;` ordered it before); one walk cannot drift
        // from itself. `declare_split` is 0 with no input statement, leaving the
        // datalines/INPUT case exactly as it was.
        const declare_split = firstInputStmt(program) orelse 0;
        try self.declareVars(program[0..declare_split]);

        // Then the SET/MERGE input columns, in schema order — SAS orders output
        // variables by first appearance, and the input dataset (which SET names
        // before every statement that follows it) appears next (BUG-varorder).
        try self.seedInputColumns();

        // MULTISET-impl: register any SET beyond the driver (a 2nd `set b;` or an
        // if-guarded `set summary;`) as an executable node with its own cursor, and
        // seed its columns AFTER the driver's so output var order stays source order.
        try self.collectExtraSets(program);

        // A fatal error while seeding input columns halts the step before any row
        // runs — a char/numeric type conflict (GH#69/#70) or an INPUT-side
        // keep/drop/rename of a var that is never referenced (GH#71, DKRICOND=
        // ERROR). Finalize with 0 obs, keeping the compile-time columns
        // (BUG-emptycols parity). Gated HERE (before buildDriver) so a source-
        // option error is reported once, not again when the driver re-resolves.
        // Only this step's seeding errors reach here: main.zig skips a step once
        // any prior step errored, so hasStepErrors() is this step's alone.
        if (self.diags.hasStepErrors()) {
            if (out.columns.items.len == 0) try self.seedSchema(out);
            return;
        }

        if (self.by_vars) |bys| try self.buildByNames(bys);

        // SAS defines INPUT variables at compile time — pre-declare them (after
        // any retain_order/sum vars already seeded above, so those keep their lead)
        // so an empty datalines block (0 rows read) still yields a dataset with its
        // columns (BUG-emptycols). Define-only; the driver fills values per row.
        if (self.in_items) |items| for (items) |it| {
            // Pointer / position controls (`@n`, `+n`, `#n`, `/`, `@`, `@@`) carry an
            // empty name — they move the read cursor, they are NOT variables. Defining
            // them materialized a phantom blank-named column in the output dataset
            // (BUG-inputptrvar). Skip them; only real INPUT variables get a PDV slot.
            if (it.name.len == 0) continue;
            _ = try self.pdv.define(it.name, it.type);
        };
        // INFILE END= (FEAT-infileend): pre-declare EVERY infile's flag so a
        // 0-record step's drop-of-it still resolves (validateKeepDropRefs) and
        // the uninit scan sees it. Only the LAST infile's used to exist — a
        // referenced earlier END= var drew a factually false "never been
        // referenced" WARNING plus an uninitialized NOTE (BUG-multiinfilelastwins).
        for (self.infile_specs.items) |sp| {
            if (sp.spec.end_var) |ev| _ = try self.pdv.define(ev, .num);
        }

        // SAS builds the WHOLE PDV at compile time: every variable a statement
        // NAMES exists from iteration 1, even when its statement never executes —
        // a var assigned only in a dead branch, or named only by a bare FORMAT
        // statement, still reaches the output as missing (BUG-pdvcompilevars;
        // a real EPOCH-derivation macro's partial-date vars). Types are a static
        // guess (pdv.declare); the first runtime write corrects a guessed type, so
        // executed paths keep exact runtime typing.
        // The pre-input prefix was already walked above (see `declare_split`); this is the
        // remainder, so nothing is declared twice and no diagnostic is doubled.
        try self.declareVars(program[declare_split..]);

        // BUG-varorder: now seed the `.late` LENGTH/ATTRIB vars — SAS establishes a
        // variable at the first statement that mentions it, so a RETAIN/FORMAT/
        // INFORMAT/assignment BEFORE the LENGTH owns the earlier PDV slots
        // (`retain r1 r2; length l1 $3 l2 $3;` → r1 r2 l1 l2, not l1 l2 r1 r2).
        // Runs after declareVars so those earlier statements' vars exist first.
        for (self.declared) |dv| if (dv.late) try self.seedDeclVar(dv);

        // BUG-speciallistphantom (GH#79): FORMAT/INFORMAT statement and ATTRIB
        // items whose "name" is `_ALL_`/`_NUMERIC_`/`_CHARACTER_` apply to every
        // PDV member of that class (Statements Ref printed p.24), never to a
        // column of their own — expand them against the now-complete compile-time
        // PDV, exactly like expandSpecialVarLists does for RETAIN/KEEP/DROP below.
        // Placed BEFORE the gate so an expanded format's type conflict halts the
        // step like an explicitly-named one (NOTE-fmtnumoncharcoerce).
        try self.expandSpecialFormats();

        // The declare pass (declareVars, just above) may have reported a
        // compile-time ERROR — a mixed num/char ARRAY member list
        // (BUG-mixedtypearray). Gate like the seeding gate above: halt
        // before a single observation runs.
        if (self.diags.hasStepErrors()) {
            if (out.columns.items.len == 0) try self.seedSchema(out);
            return;
        }

        // `_ALL_`/`_NUMERIC_`/`_CHARACTER_` in RETAIN/KEEP/DROP lists — expand
        // against the now-complete compile-time PDV (BUG-retainspecial /
        // BUG-keepdropspecial).
        try self.expandSpecialVarLists();

        // one-time retain inits (`retain total 0;`), before the loop so they
        // are in place — and, being retained, survive the first reset. They run
        // HERE, after the declare pass: every init var is already declared at
        // its statement's textual position (declareStmt's .retain/.array arms),
        // so the set only writes the VALUE. Running it before declareVars let
        // pdv.set's define-if-missing steal the var's first-mention slot — a
        // sum statement after a second-SET POINT= lookup ordered the
        // accumulator AHEAD of the lookup's columns (QA tick377 F2).
        for (self.retain_inits.items) |ri| {
            try self.pdv.set(ri.name, try self.ev.eval(ri.expr));
        }

        // GH#75 ISS-uninitvar: with the PDV now fully seeded, any RHS variable
        // read that resolves to no slot (and is not an automatic) is genuinely
        // uninitialized — SAS logs the NOTE once per variable per step. Runs
        // here, after seedInputColumns + declareVars, so SET/MERGE/retained/
        // assigned/INPUT vars are all present and excluded by construction.
        try self.noteUninitVars(program);

        // Line sources (BUG-multiinfilelastwins): build one per declared
        // INFILE, or — with no INFILE at all — the single implicit datalines
        // source. Reading a file needs an Io (main supplies it); with none the
        // source is empty and the step reads no records from it.
        if (self.infile_specs.items.len == 0) {
            // GAP-optfirstobsraw: route the bare-DATALINES source (no INFILE
            // statement at all) through the SAME readInfileLines the INFILE path
            // uses, instead of handing dl_lines over untouched. It used to skip
            // that builder entirely, so the record-window rules lived on one of
            // two producers: `options firstobs=2;` over a plain `datalines`
            // block was ignored even after the INFILE path honoured it. Sharing
            // the builder is also what makes LINESIZE= reach this shape.
            if (self.dl_lines != null) {
                const spec: ast.Infile = .{ .path = "datalines", .inline_data = true };
                const lines = try self.readInfileLines(spec);
                try self.sources.append(self.arena, .{ .spec = spec, .lines = lines, .li = .{ .lines = lines } });
            }
        } else {
            // The DATALINES device is ONE physical instream — every
            // `infile datalines` in the step re-selects the SAME records and
            // cursor, it does not rewind them (Language Reference: Concepts Table 21.5 row 10, pinned
            // by raw_read_ch21_conformant). External paths are independent
            // opens — one source (and read cursor) each.
            // ponytail: a shared device carries the FIRST inline spec's
            // FIRSTOBS=/OBS=/LINESIZE=; a second inline spec with different
            // window options is not modelled — split the windows if a program
            // ever does that.
            var dl_dev: ?usize = null; // sources index of the shared datalines device
            for (self.infile_specs.items, 0..) |*sp, i| {
                if (sp.stmt) |st| try self.src_of_stmt.put(self.arena, st, i);
                if (sp.spec.inline_data and dl_dev != null) {
                    sp.src = dl_dev.?;
                } else {
                    const lines = try self.readInfileLines(sp.spec);
                    try self.sources.append(self.arena, .{ .spec = sp.spec, .lines = lines, .li = .{ .lines = lines } });
                    sp.src = self.sources.items.len - 1;
                    if (sp.spec.inline_data) dl_dev = sp.src;
                }
            }
        }

        // BUG-setinputinert: seed the current line source for ANY driver — a
        // SET/MERGE/UPDATE/MODIFY step with an INPUT reads records alongside
        // the driver (Language Reference: Concepts p.477 step 3 names INPUT a peer of the four
        // dataset readers; p.489 "a combination of some or all of the
        // sources"). Table 20.4's last row stops the step at the FIRST EOF of
        // any data-reading statement; execInput's .stop delivers it. The
        // first-declared source is current until an INFILE executes.
        if (self.sources.items.len > 0) try self.selectSource(0);

        var driver = try self.buildDriver();
        self.driver_ptr = &driver; // DOWLOOP-impl: a DOW SET advances this from runStmt
        if (driver == .modify) self.modify_by = &driver.modify; // REPLACE/OUTPUT routing (BUG-modifybymasterdriven)
        // BUG-setpointtemp: the SET point=/nobs= vars are temporary control vars —
        // SAS drops them from the output schema, like SET end= (stripSourceOpts).
        try self.dropSetControlTemp(self.set_point_var);
        try self.dropSetControlTemp(self.nobs_var);
        // BUG-prefixreadflags: the read-flag automatics — first./last. BY flags,
        // the end= var, the in= flags — are RETAINED across iterations, never
        // reset to missing (Language Reference: Concepts p.79: automatics are "retained from one
        // iteration of the DATA step to the next, rather than set to missing";
        // p.553: LAST. is 0 or 1), and they start at 0. Registering them here —
        // after buildDriver (the in= lists) and buildByNames (the flags), before
        // freezeNameLists hashes retained — lets the top-of-iteration reset skip
        // them, so the pre-read prefix sees the previous read's flags (initially
        // 0), not a wiped missing that flips back to 0 after the read.
        for (self.first_names) |nm| try self.keepReadFlag(nm);
        for (self.last_names) |nm| try self.keepReadFlag(nm);
        if (self.set_end_var) |ev| try self.keepReadFlag(ev);
        switch (driver) {
            .sets => |*sd| for (sd.in_vars) |iv| {
                if (iv) |v| try self.keepReadFlag(v);
            },
            .merge => |*md| for (md.in_vars) |iv| {
                if (iv) |v| try self.keepReadFlag(v);
            },
            else => {},
        }
        // drops/keeps/retained are complete here (scan, extractSetOptions,
        // expandSpecialVarLists, collectExtraSets, buildDriver and the read-flag
        // registration above all ran) — hash them.
        try self.freezeNameLists();
        // nobs= must be known BEFORE the step's loops run (BUG-setpoint-doloop) —
        // set it to the source row count up front, not at first read.
        if (self.nobs_var) |nv| {
            var n: usize = 0;
            if (self.nobs_total) |tot| {
                n = tot; // multi-source SET total, PHYSICAL counts (GAP-nobsmultisrc, BUG-pointnobs)
            } else if (if (self.set_point_node == null and self.set_point_dss.len > 0) self.set_point_dss[0] else null) |ds| {
                // NOBS= rides the point source only when point= IS the step's
                // source; beside a sequential driver (GAP-secondsetstmt,
                // Example 6) the set_names arm below counts the DRIVER's sources.
                n = self.physNobs(ds);
            } else if (self.set_names) |names| {
                for (names) |nm| if (try self.resolveDataset(nm, false, null)) |ds| {
                    n += self.physNobs(ds);
                };
            }
            try self.pdv.set(nv, .{ .num = @floatFromInt(n) });
        }

        // Per-iteration scratch (BUG-datastepoom): eval temporaries (every
        // upcase/strip/put/… result) went into the run arena and were never
        // freed — a wide row-mapping step over a 740k-row table grew past 19GB.
        // Evaluate each iteration in a scratch arena, reset at the row boundary.
        // Survivors are moved out first: retained char cells hop to the OTHER
        // scratch (double buffer — nothing accumulates), lag/RNG state lives in
        // ev.state_arena, hash entries dupe into the run arena at add/replace.
        var scratch: [2]std.heap.ArenaAllocator = .{
            std.heap.ArenaAllocator.init(std.heap.page_allocator),
            std.heap.ArenaAllocator.init(std.heap.page_allocator),
        };
        defer for (&scratch) |*s| s.deinit();
        var cur: usize = 0;
        const saved_arena = self.ev.arena;
        const saved_state = self.ev.state_arena;
        self.ev.state_arena = self.ev.stateArena(); // pin cross-row state to the stable arena
        self.ev.arena = scratch[cur].allocator();
        defer {
            self.ev.arena = saved_arena;
            self.ev.state_arena = saved_state;
        }

        // BUG-setstmtorder: statements textually BEFORE the driving SET/MERGE/
        // UPDATE/MODIFY execute BEFORE its read (Language Reference: Concepts Ch.24 — the read happens
        // where the statement sits; p.616 Example 2's hash priming is the
        // canonical victim). The flattened op stream splits at the driver's
        // statement index: each iteration runs the prefix, then loadNext, then
        // the suffix. Only a DIRECT top-level driver splits (driver_stmt/
        // split_pc stay null otherwise): a nested one — IF branch, DO body,
        // DOW, POINT= — keeps read-first (BUG-nestedsetdriver / BUG-setpoint /
        // DOWLOOP depend on it), and the .once/.lines drivers have no read to
        // split around. SET-source vars are auto-retained (buildDriver), so a
        // prefix sees missing on iteration 1 and the last-read values on later
        // ones, like SAS.
        const split: ?usize = if (self.split_pc != null and self.dow_set == null)
            switch (driver) {
                .sets, .merge, .update, .modify => self.split_pc,
                else => null,
            }
        else
            null;

        while (true) {
            for (self.pdv.vars.items) |*v| {
                if (!self.isRetained(v.name)) v.value = missingOf(v.type);
            }
            // The pre-driver prefix runs BEFORE the read, with `_N_`/`_ERROR_`
            // already live — `if _n_=1 then …` priming blocks are the point of
            // the prefix (p.613/p.616's hash boilerplate). STOP in the prefix
            // ends the step with no read and no output; DELETE/RETURN suppress
            // the suffix like an unsplit runProgramRange, but the read still
            // happens — SAS halts neither at DELETE/RETURN, and the driver
            // must advance or the loop never terminates.
            var prefix_flow: Flow = .normal;
            if (split) |sp| {
                self.n_iter += 1;
                try self.pdv.set("_n_", .{ .num = @floatFromInt(self.n_iter) });
                try self.pdv.set("_error_", .{ .num = 0 });
                self.obs_handled = false;
                prefix_flow = try self.runProgramRange(0, sp);
                if (prefix_flow == .stop) break;
            }
            if (!try self.loadNext(&driver)) break;
            // `_N_` — the automatic DATA-step iteration counter (1-based), set
            // after the reset so `if _n_=1 then …` (declare-once idioms) works.
            // (The split path bumped these before the prefix already.)
            if (split == null) {
                self.n_iter += 1;
                try self.pdv.set("_n_", .{ .num = @floatFromInt(self.n_iter) });
                // `_ERROR_` — automatic error flag, reset to 0 at the top of each
                // iteration (SAS); pdv.set raises it to 1 the moment an invalid
                // char→num conversion happens during the step (CHARNUM-errorvar).
                try self.pdv.set("_error_", .{ .num = 0 });
                self.obs_handled = false; // MODIFY REPLACE/REMOVE reset (FEAT-datamodify-rest)
            }
            // `_IORC_` (BUG-modifybynomatch / BUG-modifybymasterdriven): MODIFY
            // return-code automatic — 0 (_SOK) on a matched read, _DSENMR
            // (1230015) when modifyNext flagged this obs as a transaction with
            // no master match, and a DISTINCT non-SAS sentinel for _DSEMTR
            // (consecutive repeats of the same unmatched key, p.599 Table 23.4):
            // _DSEMTR's numeric value is oracle-blocked (NOTE-modifydsemtr —
            // %sysrc(_dsemtr) fails loud by design, GAP-sysrcmacro), so a
            // negative stand-in no %SYSRC comparison can silently match is used
            // rather than a guessed number (a wrong code compared against %SYSRC
            // silently takes the wrong branch — this ticket's failure class).
            // _ERROR_ is re-raised post-reset so the program sees the condition
            // and can clear it (Language Reference: Concepts p.601 revised program); obs_handled blocks
            // the implicit REPLACE from fabricating the unmatched row into the
            // rebuilt master.
            if (self.modify_names != null) {
                const iorc: f64 = switch (self.modify_nomatch) {
                    .none => 0,
                    .first => 1230015,
                    .subsequent => -1230015, // _DSEMTR sentinel — see above
                };
                try self.pdv.set("_iorc_", .{ .num = iorc });
                if (self.modify_nomatch != .none) {
                    try self.pdv.set("_error_", .{ .num = 1 });
                    self.obs_handled = true;
                }
            }
            // first./last. flags: peek-based applyBy for SET; MERGE sets its own
            // inside mergeNext from the group machinery (BUG-mergefirstlast). A DOW
            // SET computes first./last. at each inner read (dowRead), not here.
            if (self.by_vars) |bys| {
                if (driver == .sets and self.dow_set == null) try self.applyBy(&driver, bys);
            }

            const flow = if (prefix_flow != .normal) prefix_flow else try self.runProgramRange(if (split) |sp| sp else 0, self.ops.len);
            // BUG-modifybynomatch: an unhandled no-match (the program left _ERROR_
            // set) is the Language Reference: Concepts p.600 ERROR. Reported per iteration, but the step
            // CONTINUES: halting mid-rebuild would truncate the re-emitted master,
            // silent row loss SAS's in-place modify never has. The ERROR still
            // triggers syntax-check mode for LATER steps (BUG-errhalt), matching
            // the doc's "stopped processing this step because of errors".
            if (self.modify_nomatch != .none) {
                self.modify_nomatch = .none;
                if (self.pdv.get("_error_")) |ev| if (ev == .num and ev.num != 0) {
                    self.diags.report(.err, 0, "No matching observation was found in {s} data set.", .{self.modify_names.?[0]}) catch {};
                };
            }
            switch (flow) {
                .deleted => {}, // subsetting-if / DELETE dropped the obs: no output
                .stop => break, // STOP ends the step now; the current obs is not output
                // RETURN ends the iteration but still writes the obs (implicit output);
                // a stray CONTINUE/LEAVE outside a loop just falls through to output too.
                // GOTO/LINK are consumed inside runProgramRange, so they never reach here.
                // MODIFY: the implicit REPLACE is per-observation (stmtHasOutput)
                // — a real OUTPUT statement elsewhere in the step does NOT suppress
                // it, only handling THIS obs does; otherwise the rebuilt master
                // would silently drop every row the program didn't explicitly write.
                // BUG-pointautooutput: a POINT=-DRIVEN step has NO implicit
                // bottom-of-iteration OUTPUT — only an explicit OUTPUT statement
                // writes a row (the same p.488 direct-access rule that forces the
                // explicit STOP). Must not multiply the now-iterating step into a
                // fabricated row set (BUG-pointnoiterate's other half).
                // BUG-pointsuppressesalloutput: keyed on point_driven — POINT=
                // actually DRIVING — not on the step merely mentioning POINT=.
                // A MERGE/UPDATE/INPUT driver has normal EOF detection (Language Reference: Concepts
                // Table 20.4), so p.477 step 5's automatic output stands.
                .normal, .continue_, .leave, .returned, .goto_, .link_ => if ((!self.has_output or self.modify_names != null) and !self.obs_handled and !self.point_driven) {
                    // MODIFY-BY: the implicit REPLACE records a per-master-row
                    // override; the rebuilt master is emitted at driver
                    // exhaustion (modifyFlush), in original order.
                    if (self.modify_by) |md| try self.modifyReplace(md) else try self.outputAll();
                },
            }

            // Row boundary: the survivors of the top-of-loop reset are exactly
            // the retained vars — their char cells may point into the current
            // scratch, so move them to the other one, then drop this row's
            // temporaries. Everything else is reset to missing before any read.
            const nxt = 1 - cur;
            for (self.pdv.vars.items) |*v| {
                if (v.value == .str and self.isRetained(v.name))
                    v.value = .{ .str = try scratch[nxt].allocator().dupe(u8, v.value.str) };
            }
            _ = scratch[cur].reset(.retain_capacity);
            cur = nxt;
            self.ev.arena = scratch[cur].allocator();
        }

        // MODIFY-BY rebuild-commit (BUG-modifybymasterdriven): emit the rebuilt
        // master — the rows the transaction-driven driver never visited (untouched),
        // the recorded REPLACE overrides (REMOVE tombstones skipped), then the
        // OUTPUT-appended rows. Runs here too so a mid-step `stop;` still leaves a
        // complete master on disk.
        if (self.modify_by) |md| try self.modifyFlush(md);

        // The scratch dies with this call; anything a caller might still read
        // from the PDV (schema seeding, diagnostics) must not dangle — dupe the
        // remaining char cells into the run arena once.
        for (self.pdv.vars.items) |*v| {
            if (v.value == .str) v.value = .{ .str = try self.arena.dupe(u8, v.value.str) };
        }

        // ISS-keepdropnonexist: a KEEP/DROP/RENAME statement naming a variable
        // that exists NOWHERE in the step is a typo — SAS ERRORs and halts. The
        // PDV now holds every var the step ever created (never pruned mid-step),
        // so a var created LATER than the statement stays legal; only a true typo
        // resolves to no slot and fails loud.
        try self.validateKeepDropRefs();

        // A 0-row step never called output(), so the schema was never seeded —
        // SAS still defines the columns at compile time (BUG-emptycols). Seed now
        // so an empty dataset keeps its columns for PROC PRINT / SORT `by` / SET.
        // Same for every extra `data a b …;` output (BUG-multioutput): all named
        // datasets are created — with their columns — even at 0 observations.
        if (out.columns.items.len == 0) try self.seedSchema(out);
        for (self.extra_outs) |x| if (x.columns.items.len == 0) try self.seedSchema(x);

        // Statement-form RENAME (`rename a=b;`): relabel the output columns of EVERY
        // output dataset — Language Reference: Concepts Table 4.6 (p.72) "Statements: effect all output
        // data sets" and Table 4.7 (p.73) "RENAME / changes name of variables in
        // all output data sets", like the DROP/KEEP/LABEL/FORMAT siblings already
        // do (BUG-renamestmtmultiout: `data p q; rename a=z;` renamed only p's
        // column). Reuse the `rename=(…)` dataset-option path so we inherit its
        // rename-onto-existing guard (BUG-renamedup) for free (G-falsemarkers2).
        if (self.renames.items.len > 0) {
            var outs: std.ArrayList(*Dataset) = .empty;
            try outs.append(self.arena, out);
            try outs.appendSlice(self.arena, self.extra_outs);
            for (outs.items) |o| {
                // …except the MODIFY master, whose descriptor is frozen: renaming
                // a variable IS a descriptor change, which Table 23.3's "Scope of
                // changes" row rules out along with adding and deleting
                // (modifyFrozenMaster). This loop runs AFTER the rows are written,
                // so without the skip it relabelled columns in place and the
                // in-place update silently came back under a different name.
                if (self.modifyFrozenMaster(o) != null) continue;
                // Build `rename = ( old = new … )` option tokens directly (no lexing —
                // exec's Error set is OOM-only, so we can't `try` the lexer here).
                var toks: std.ArrayList(lex.Token) = .empty;
                try toks.appendSlice(self.arena, &.{
                    .{ .tag = .name, .text = "rename" }, .{ .tag = .eq }, .{ .tag = .lparen },
                });
                for (self.renames.items) |p| {
                    // Only hand renames whose OLD name is an actual output column —
                    // one dropped by a keep/drop statement is gone from this output
                    // but was still referenced (validateKeepDropRefs already vetted
                    // it against the PDV), so skipping it here keeps io's option
                    // validator from false-erroring on a name it can no longer see.
                    if (o.indexOf(p.old) == null) continue;
                    try toks.append(self.arena, .{ .tag = .name, .text = p.old });
                    try toks.append(self.arena, .{ .tag = .eq });
                    try toks.append(self.arena, .{ .tag = .name, .text = p.new });
                }
                try toks.append(self.arena, .{ .tag = .rparen });
                try io.applyDatasetOptions(self.arena, o, toks.items, self.diags, false); // OUTPUT: DKROCOND=WARN
            }
        }

        // FILE: flush the buffered `put` output to the external file. A
        // print/log keyword destination (GAP-fileprint) writes NO file — its
        // PUT output already went to the log via putBuf.
        if (self.file) |f| if (!f.print_log) if (self.io) |io_| {
            Io.Dir.cwd().writeFile(io_, .{ .sub_path = f.path, .data = self.file_out.items }) catch {};
        };
    }

    // ── compile-time scan ────────────────────────────────────────────────
    /// The first SET node in `s` (recursing IF branches and nested DO bodies), or
    /// null. Used to locate the DOW-loop's inner SET.
    fn findSetStmt(s: *const ast.Stmt) ?*const ast.Stmt {
        switch (s.*) {
            .set => return s,
            .if_ => |f| {
                if (f.then_branch) |b| if (findSetStmt(b)) |n| return n;
                if (f.else_branch) |b| if (findSetStmt(b)) |n| return n;
            },
            .do_ => |d| for (d.body) |*b| {
                if (findSetStmt(b)) |n| return n;
            },
            else => {},
        }
        return null;
    }

    /// The first MERGE/UPDATE/MODIFY node reachable from `s` (recursing IF/DO),
    /// or null — guardInertDow's counterpart to findSetStmt: those sources are
    /// runtime-inert, so one inside a DO UNTIL/WHILE can never drive the loop.
    fn findInertSourceStmt(s: *const ast.Stmt) ?*const ast.Stmt {
        switch (s.*) {
            .merge, .update, .modify => return s,
            .if_ => |f| {
                if (f.then_branch) |b| if (findInertSourceStmt(b)) |n| return n;
                if (f.else_branch) |b| if (findInertSourceStmt(b)) |n| return n;
            },
            .do_ => |d| for (d.body) |*b| {
                if (findInertSourceStmt(b)) |n| return n;
            },
            else => {},
        }
        return null;
    }

    /// Total number of SET nodes reachable from `s` (recursing IF/DO). A DOW loop
    /// opensas supports must hold EXACTLY one SET (the DOW read); more is unsupported.
    fn countSetsStmt(s: *const ast.Stmt) usize {
        return switch (s.*) {
            .set => 1,
            .if_ => |f| (if (f.then_branch) |b| countSetsStmt(b) else 0) +
                (if (f.else_branch) |b| countSetsStmt(b) else 0),
            .do_ => |d| blk: {
                var n: usize = 0;
                for (d.body) |*b| n += countSetsStmt(b);
                break :blk n;
            },
            else => 0,
        };
    }

    /// DOWLOOP-impl: mark the SET driven by an enclosing DO until/while loop. The
    /// DOW read fires at the SET node each DO iteration (dowRead), so the outer
    /// DATA-step loop only gates on remaining rows. Fail LOUD on shapes we do not
    /// model: a DOW SET inside an iterative/list DO (that is POINT=-territory, and
    /// point is filtered by the caller), or a DOW loop mixed with any other SET.
    fn detectDowSet(self: *Executor, program: ast.Program) Error!void {
        for (program) |*s| {
            // BUG-dowinsideifhang (QA tick307 F2): a DO UNTIL/WHILE whose body
            // holds a MERGE/UPDATE/MODIFY but no SET can NEVER terminate —
            // those sources are runtime-inert (needs-oracle, pinned in
            // BUG-nestedsourceschema), so nothing in the loop drives the end
            // condition and the step spins at 100% CPU growing memory without
            // bound (QA measured ~60 MB/s; an unattended batch OOMs the box).
            // A SET in that spot DOES drive the loop — its read fires at the
            // node via the extra-set cursor (BUG-doblocksourceinert's .do_ arm)
            // and EOF stops the step. Guarded at ANY nesting depth: wrapped in
            // a top-level IF the shape was invisible to the top-level walk
            // below and hung the same way. Fail LOUD per D-002 — never hang.
            try self.guardInertDow(s);
            switch (s.*) {
                .do_ => {
                    const inner = findSetStmt(s) orelse continue;
                    if (s.do_.header != .until_ and s.do_.header != .while_) {
                        diag.markGap(); // `do i=1 to n; set a; end;` is valid SAS — our gap, rc 2 (D-009)
                        self.diags.report(.err, 0, "a SET inside an iterative DO loop (without POINT=) is not supported; use DO UNTIL/WHILE (a DOW loop) or POINT=", .{}) catch {};
                        return error.ExecError;
                    }
                    var total: usize = 0;
                    for (program) |*ps| total += countSetsStmt(ps);
                    if (total != 1) {
                        diag.markGap(); // several SET statements in one step is valid SAS — our gap, rc 2
                        self.diags.report(.err, 0, "a DOW-loop mixed with another SET statement is not supported", .{}) catch {};
                        return error.ExecError;
                    }
                    // no early return: keep scanning so guardInertDow sees the
                    // rest of the program (total==1 makes a second DOW-shaped
                    // DO unreachable here).
                    self.dow_set = inner;
                },
                else => {},
            }
        }
    }

    /// The BUG-dowinsideifhang guard, one statement: find any DO UNTIL/WHILE
    /// reachable from `s` whose body holds a runtime-inert source (MERGE/
    /// UPDATE/MODIFY) and no SET to drive it, and fail LOUD on the first.
    fn guardInertDow(self: *Executor, s: *const ast.Stmt) Error!void {
        switch (s.*) {
            .do_ => |d| {
                if (d.header == .until_ or d.header == .while_) {
                    if (findSetStmt(s) == null and findInertSourceStmt(s) != null) {
                        // Valid SAS that real SAS accepts; we stop rather than spin,
                        // exactly macro.zig's iterative-%DO non-convergence gap → rc 2.
                        diag.markGap();
                        self.diags.report(.err, 0, "a MERGE/UPDATE/MODIFY inside a DO UNTIL/WHILE loop is not supported; only a SET can drive a DOW loop", .{}) catch {};
                        return error.ExecError;
                    }
                }
                for (d.body) |*b| try self.guardInertDow(b);
            },
            .if_ => |f| {
                if (f.then_branch) |b| try self.guardInertDow(b);
                if (f.else_branch) |b| try self.guardInertDow(b);
            },
            else => {},
        }
    }

    /// `direct` is true only for statements that are DIRECT members of the
    /// top-level program slice (BUG-setstmtorder records the driving statement
    /// for those — only a direct driver can split the iteration around its
    /// read). IF branches and DO bodies recurse with direct=false; `nested`
    /// itself passes through DO bodies unchanged (BUG-setpoint).
    fn scan(self: *Executor, program: ast.Program, nested: bool, direct: bool) Error!void {
        for (program) |*s| { // pointer loop: drv_* must alias the program slice (BUG-setstmtorder)
            switch (s.*) {
                .retain => |items| for (items) |it| {
                    // `_ALL_`/`_NUMERIC_`/`_CHARACTER_` are name lists, not var
                    // names — defer PDV expansion to expandSpecialVarLists.
                    if (specialVarList(it.name)) |kind| {
                        try self.special_retains.append(self.arena, .{ .kind = kind, .init = it.init });
                    } else {
                        try self.retained.append(self.arena, it.name);
                        if (it.init) |e| try self.retain_inits.append(self.arena, .{ .name = it.name, .expr = e });
                    }
                },
                .drop => |names| try self.drops.appendSlice(self.arena, names),
                .keep => |names| {
                    self.keep_mode = true;
                    try self.keeps.appendSlice(self.arena, names);
                },
                .rename => |pairs| try self.renames.appendSlice(self.arena, pairs),
                // The FIRST TOP-LEVEL SET drives the loop; any later SET is an
                // executable extra (collectExtraSets). Keep the first so `set a;
                // set b;` drives off a. A NESTED source (inside an IF branch) is a
                // compile-time declarative only — it must NEVER register as the
                // driver, or a conditional `if _n_=1 then set params;` placed
                // before the driving SET hijacks the loop and silently drops the
                // driver's observations (BUG-nestedsetdriver).
                .set => |names| if (self.set_names == null and !nested) {
                    self.set_names = names;
                    if (direct) self.drv_set = s;
                },
                // Declarative — position-independent, like SAS. But ONLY at the
                // step's top statement level: Language Reference: Concepts p.232 Table 11.6 reserves
                // "Execute the selection conditionally" for the subsetting IF, so
                // real SAS refuses `if x>10 then where x<3;` outright (ERROR
                // 180-322, same for a DO-block body). opensas used to HOIST the
                // nested statement and filter every row unconditionally
                // (BUG-whereconditional) — a silent wrong answer. `direct` is
                // exactly "top-level member": IF branches and DO bodies recurse
                // with direct=false (see scan's doc comment).
                .where_ => |e| {
                    if (!direct)
                        return self.diags.fail(error.ExecError, 0, "The WHERE statement is declarative and cannot appear inside an IF or DO block; use a subsetting IF for a conditional selection", .{});
                    self.where_expr = e;
                },
                .merge => |names| if (!nested) {
                    self.merge_names = names;
                    if (direct) self.drv_merge = s;
                },
                .update => |names| if (!nested) {
                    self.update_names = try self.pullUpdateOpts(names);
                    if (direct) self.drv_update = s;
                },
                .modify => |names| if (!nested) {
                    self.modify_names = names;
                    if (direct) self.drv_modify = s;
                },
                .by => |names| try self.decodeBy(names),
                // @constCast: the parser's datalines array is arena-owned
                // (toOwnedSlice) — writable, so `_infile_ = …` may edit a record.
                .datalines => |lines| self.dl_lines = @constCast(lines),
                // BUG-inputmultistmt: multiple INPUT statements in one step ACCUMULATE
                // their var lists — SAS establishes columns at first appearance, so
                // `input x y; input z;` schemas x y z, not just the last statement's z
                // (the pre-declare at line 583 reads self.in_items). Runtime value
                // reading is per-statement (execInput takes its own items), unaffected.
                // scan runs once per step-compile on a fresh Executor, so no double-count.
                .input => |items| self.in_items = if (self.in_items) |prev|
                    try std.mem.concat(self.arena, ast.InputItem, &.{ prev, items })
                else
                    items,
                // BUG-multiinfilelastwins: EVERY INFILE declares its own line
                // source — the last one used to blindly overwrite `self.infile`
                // (its two sibling arms knew better: `.set` is first-wins,
                // `.input` accumulates), so the first file was never opened and
                // every INPUT read the last file. Record each in program order;
                // run() builds a LineSource per statement and runStmt's `.infile`
                // arm switches the current source as each INFILE executes.
                .infile => |inf| {
                    try self.infile_specs.append(self.arena, .{ .stmt = s, .spec = inf });
                    if (inf.end_var) |ev| try self.drops.append(self.arena, ev); // END= var is temporary, like SET end= (FEAT-infileend)
                },
                .file => |f| self.file = f,
                .format => |items| for (items) |it| {
                    // A LABEL statement / ATTRIB label= rides the `.format` node with a
                    // NUL-prefixed fmt (parser sentinel) — route those to the label store.
                    if (it.fmt.len > 0 and it.fmt[0] == 0) {
                        try self.lib.setVarLabel(it.name, it.fmt[1..]);
                        try self.attrs.append(self.arena, .{ .name = it.name, .fmt = it.fmt });
                    } else if (it.fmt.len > 0 and it.fmt[0] == 1) {
                        // ATTRIB informat= riding the same node (BUG-attribinformat) —
                        // attrs only, exactly like the .informat handler below.
                        try self.attrs.append(self.arena, .{ .name = it.name, .fmt = it.fmt });
                    } else {
                        try self.formats.append(self.arena, it);
                        try self.attrs.append(self.arena, it);
                    }
                },
                // INFORMAT statement — read format; kept for VINFORMAT* + output metadata
                // (EXEC-varattr). Marked with a NUL sentinel so applyAttrs routes it.
                .informat => |items| for (items) |it| {
                    try self.attrs.append(self.arena, .{
                        .name = it.name,
                        .fmt = try std.fmt.allocPrint(self.arena, "\x01{s}", .{it.fmt}),
                    });
                },
                // `array a{n} … (inits)`: initialized members act like a retain —
                // set once before the loop and kept across iterations. Temporary
                // members are anonymous, so keep them out of the output dataset.
                .array => |decl| {
                    try self.array_names.append(self.arena, decl.name);
                    // BUG-arrayinitvalidate F1: MORE initial values than elements is a
                    // SAS ERROR ("The number of initial values ... exceeds the number
                    // of array elements") — the excess used to be silently dropped.
                    // FEWER stays legal (the rest default to missing/blank). A
                    // special-list array (`array v{*} _numeric_`) has no compile-time
                    // element count, so the check cannot apply there.
                    // BUG-arrayinitvalidate F2: a CHARACTER constant initializing a
                    // NUMERIC array element is a SAS ERROR — it used to be stored as
                    // a char, corrupting the element's type. (char literal + `$`
                    // array, numeric literal + numeric array: both stay legal.)
                    const too_many = decl.special == null and decl.inits.len > decl.elements.len;
                    var bad_char = false;
                    if (!too_many and decl.type == .num) for (decl.inits) |init_expr| {
                        if (init_expr.* == .str) {
                            bad_char = true;
                            break;
                        }
                    };
                    if (too_many) {
                        self.diags.report(.err, 0, "The number of initial values ({d}) exceeds the number of array elements ({d}) for array {s}.", .{ decl.inits.len, decl.elements.len, decl.name }) catch {};
                    } else if (bad_char) {
                        self.diags.report(.err, 0, "A character constant is not a valid initial value for the numeric array {s}.", .{decl.name}) catch {};
                    } else {
                        // A `$` array makes its members character — define them so an
                        // unassigned element reads/outputs as a blank char, not numeric.
                        if (decl.type == .char) for (decl.elements) |e| {
                            _ = try self.pdv.define(e, .char);
                        };
                        for (decl.inits, 0..) |init_expr, k| {
                            if (k >= decl.elements.len) break;
                            try self.retained.append(self.arena, decl.elements[k]);
                            try self.retain_inits.append(self.arena, .{ .name = decl.elements[k], .expr = init_expr });
                        }
                        if (decl.temporary) {
                            // SAS 9.4: _TEMPORARY_ elements are ALWAYS retained
                            // across iterations, initialized or not
                            // (BUG-temparray-noretain) — inits above already
                            // retained their own elements, so retain the rest.
                            for (decl.elements[@min(decl.inits.len, decl.elements.len)..]) |e|
                                try self.retained.append(self.arena, e);
                            try self.drops.appendSlice(self.arena, decl.elements);
                        }
                    } // an invalid decl seeds nothing; the
                    // hasStepErrors() gate in run() halts the step.
                },
                // recurse into a do-loop body so a nested declarative is still seen —
                // notably `do i=…; set ds point=i; …; end;` (BUG-setpoint), where the
                // SET is never top-level. SAS treats declaratives as compile-time
                // regardless of nesting. Pass `nested` through UNCHANGED: a SET in a
                // top-level DO still registers as the driver (BUG-setpoint depends on
                // it) — only the IF-branch path below suppresses driver registration.
                .do_ => |d| try self.scan(d.body, nested, false),
                // recurse into IF then/else branches too — RETAIN/KEEP/DROP and
                // the other declaratives are compile-time in SAS regardless of the
                // runtime branch that (never) executes them (BUG-nesteddeclarative).
                // Each branch is a single statement; slice it to a 1-elem program.
                // Nested DO/IF inside a branch are picked up by the recursion.
                // The branch body is NESTED: source statements there register
                // declarative effects only, never the step driver (see .set above).
                .if_ => |f| {
                    if (f.then_branch) |b| try self.scan(b[0..1], true, false);
                    if (f.else_branch) |b| try self.scan(b[0..1], true, false);
                },
                // `nobs=n` desugars to `n = _setobs_`; capture n so it can be set to
                // the row count BEFORE a `do k=1 to n; set … point=k;` loop evaluates
                // its bound — SAS makes nobs= available up front (BUG-setpoint-doloop).
                .assign => |aa| if (aa.value.* == .variable and eqi(aa.value.variable, "_setobs_")) {
                    self.nobs_var = aa.target;
                    try self.retained.append(self.arena, aa.target); // survive the per-iter reset
                    // PERF-loadrowdual: `_setobs_` itself is stamped once per
                    // source (stampObs), so it too must survive the reset.
                    try self.retained.append(self.arena, "_setobs_");
                },
                else => {},
            }
            if (stmtHasOutput(s.*)) self.has_output = true;
        }
        // SET variables are retained too, but `loadRow` rewrites them every
        // iteration, so the reset never observes them — no need to track.
        // ponytail: declaratives read at top level only; they are compile-time
        // in SAS regardless of nesting, but corpus programs keep them top-level.
    }

    /// Compile-time PDV construction (BUG-pdvcompilevars): declare every variable
    /// a statement NAMES, in source order, recursing into IF branches and DO
    /// bodies — SAS creates these at compile time, so a var assigned only in a
    /// never-executed branch still reaches the output (as missing). All declares
    /// go through `pdv.declare` (guessed type, corrected by the first runtime
    /// write), so nothing here can break an executed path's typing or column slot.
    /// ponytail: statement TARGETS only — a variable named only on the RHS
    /// (SAS: uninitialized-note + a column) is not declared until a program needs it.
    fn declareVars(self: *Executor, program: ast.Program) Error!void {
        for (program) |*s| try self.declareStmt(s);
    }

    /// Index of the TOP-LEVEL statement at or inside which the step's first input
    /// statement (SET/MERGE/UPDATE/MODIFY) sits, or null when the step reads no
    /// dataset. run() splits the declare walk here so the statements textually
    /// BEFORE the input source own the earlier PDV slots (Language Reference: Concepts printed p.47).
    /// A driver nested in a DO/IF (the DOW idiom) reports its enclosing top-level
    /// statement, so that whole statement — body included — stays on the input
    /// side of the split; the prefix is only ever complete statements that finish
    /// before the read.
    fn firstInputStmt(program: ast.Program) ?usize {
        for (program, 0..) |*s, i| if (hasInputStmt(s)) return i;
        return null;
    }

    fn hasInputStmt(s: *const ast.Stmt) bool {
        return switch (s.*) {
            .set, .merge, .update, .modify => true,
            .if_ => |f| (if (f.then_branch) |b| hasInputStmt(b) else false) or
                (if (f.else_branch) |b| hasInputStmt(b) else false),
            .do_ => |d| for (d.body) |*b| {
                if (hasInputStmt(b)) break true;
            } else false,
            else => false,
        };
    }

    fn declareStmt(self: *Executor, s: *const ast.Stmt) Error!void {
        switch (s.*) {
            // `_infile_ = …` (BUG-infilevarnoop): an automatic, not an ordinary
            // PDV var — route through the ONE recogniser so refs_infile is set
            // even when the assignment sits on a dead branch.
            .assign => |aa| {
                if (eqi(aa.target, "_infile_")) try self.useInfileVar() else _ = try self.pdv.declare(aa.target, self.staticType(aa.value));
            },
            .substr_assign => |sa| {
                if (eqi(sa.target, "_infile_")) try self.useInfileVar() else _ = try self.pdv.declare(sa.target, .char);
            },
            .if_ => |f| {
                if (f.then_branch) |b| try self.declareStmt(b);
                if (f.else_branch) |b| try self.declareStmt(b);
            },
            .do_ => |d| {
                switch (d.header) {
                    .iter => |it| _ = try self.pdv.declare(it.name, .num),
                    // a value-list DO index compiles to the FIRST value's type:
                    // `do a1="NONE"; …` is CHAR — hardcoding .num left a1 as
                    // numeric missing on dead-branch rows, so `"Z"||a1` rendered
                    // "Z." instead of "Z" (BUG-doindexchar, gen2 AE AEACNOTH).
                    .list => |l| _ = try self.pdv.declare(l.name, if (l.specs.len > 0) self.staticType(l.specs[0].start) else .num),
                    else => {},
                }
                try self.declareVars(d.body);
            },
            // FORMAT/INFORMAT name a variable into existence; `$…` marks it char.
            // LABEL items ride `.format` with a \x00-sentinel fmt — skipped (label
            // alone does not settle a type we'd want to guess from). ATTRIB informat=
            // items ride with a \x01 sentinel (BUG-attribinformat) — unwrap for `$`.
            .format, .informat => |items| for (items) |it| {
                // `_ALL_`/`_NUMERIC_`/`_CHARACTER_` are name lists, not variables
                // (BUG-speciallistphantom, GH#79) — the same guard the .retain arm
                // below runs, so no phantom column is declared for the keyword.
                // scan() kept the item; expandSpecialFormats maps it to the PDV
                // members once the compile-time PDV is complete.
                if (specialVarList(it.name) != null) continue;
                if (it.fmt.len > 0 and it.fmt[0] == 0) continue;
                const spec = if (it.fmt.len > 0 and it.fmt[0] == 1) it.fmt[1..] else it.fmt;
                const rides_informat = it.fmt.len > 0 and it.fmt[0] == 1; // ATTRIB informat= — read side, unchecked here
                // NOTE-fmtnumoncharcoerce: a display format whose type
                // disagrees with the variable's established type is a SAS
                // compile-time ERROR (Formats & Informats Ref printed p.7:
                // "The FORMAT statement permanently associates character
                // variables with character formats and numeric variables with
                // numeric formats"; p.5: an incompatible format ERRORs, it
                // never silently coerces). It used to slip through and render
                // the char cell as '.' at print time (exit 0). Checked here —
                // the step's compile pass — so the hasStepErrors() gate halts
                // the step BEFORE any observation is written. Covers the
                // FORMAT statement and ATTRIB format= (which rides `.format`);
                // both directions. A `length c $3; attrib c format=8.2;`
                // conflict was already reported by seedDeclVar ("defined as
                // both character and numeric") — don't double-report it. The
                // removal form `format x;` rides as "$." (BUG-formatremoval's
                // default-for-both-types sentinel) — not a real char format.
                if (s.* == .format and !rides_informat and spec.len > 0 and !eqi(spec, "$.") and !eqi(spec, ".")) if (self.pdv.indexOf(it.name)) |vi| {
                    const vr = self.pdv.vars.items[vi];
                    const fmt_char = format.specIsChar(spec); // `$` or a char-typed user format, $-less included
                    if (vr.type == .char and !fmt_char and !self.declaredNumTyped(it.name)) {
                        self.diags.report(.err, 0, "The numeric format {s} cannot be used with character variable {s}.", .{ spec, it.name }) catch {};
                    } else if (vr.type == .num and fmt_char) {
                        self.diags.report(.err, 0, "The character format {s} cannot be used with numeric variable {s}.", .{ spec, it.name }) catch {};
                    }
                };
                _ = try self.pdv.declare(it.name, if (spec.len > 0 and spec[0] == '$') .char else .num);
            },
            .retain => |items| for (items) |it| {
                // a special name LIST (`_numeric_` &c.) is not a variable —
                // expandSpecialVarLists maps it to PDV members (BUG-retainspecial).
                if (specialVarList(it.name) != null) continue;
                _ = try self.pdv.declare(it.name, if (it.init) |e| self.staticType(e) else .num);
            },
            // an ARRAY declares all its members (scan() already hard-defines the
            // `$` ones; declare is a no-op there and guesses num for the rest)
            .array => |decl| {
                try self.checkArrayTypes(decl);
                for (decl.elements) |e| {
                    _ = try self.pdv.declare(e, decl.type);
                }
            },
            // QA tick377 F2: a POINT= lookup's columns are first-mentioned at the
            // SET statement that CARRIES the option — seed them here, in program
            // order, at that node. 837590ea defined them at buildDriver (AFTER
            // this walk and after noteUninitVars): LAST under a sequential
            // driver (`set drv; set lk point=_n_; tot+b;` gave a tot b) and
            // behind a false "Variable b is uninitialized." NOTE; beside a
            // MERGE/MODIFY driver seedInputColumns' orelse chain put them FIRST
            // (b k p q). Two shapes: the claimed second-SET lookup
            // (set_point_node — plain define, mirroring buildDriver's
            // io.columnSlots) and the first-SET lookup beside a MERGE/UPDATE/
            // MODIFY driver (drv_set — seedColumnsOf, mirroring the old
            // seedInputColumns) — so only the POSITION moves, never a type/width.
            .set => {
                if (self.set_point_node == s) {
                    for (self.extra_src_names.get(s) orelse &.{}) |name| {
                        if (try self.resolvePointSource(name)) |ds| {
                            for (ds.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
                        }
                    }
                } else if (self.set_point_var != null and self.set_point_node == null and s == self.drv_set and
                    (self.merge_names != null or self.update_names != null or self.modify_names != null))
                {
                    for (self.set_names orelse &.{}) |name| {
                        if (try self.resolvePointSource(name)) |ds| try self.seedColumnsOf(ds);
                    }
                }
            },
            else => {},
        }
    }

    /// True when `name` has a numeric LENGTH/ATTRIB declaration in this step —
    /// the shape seedDeclVar already reports as "defined as both character and
    /// numeric" when the PDV var is char. declareStmt's format-type check
    /// consults it to avoid double-reporting that one overlapping conflict
    /// (NOTE-fmtnumoncharcoerce).
    fn declaredNumTyped(self: *Executor, name: []const u8) bool {
        for (self.declared) |dv| if (dv.type == .num and eqi(dv.name, name)) return true;
        return false;
    }

    /// BUG-mixedtypearray: an ARRAY's elements must be ALL numeric or ALL
    /// character — SAS 9.4 errors at compile time ("Variable X has been
    /// defined as both character and numeric."). A mixed member list used to
    /// be silently accepted: the mismatched member kept its own type and a
    /// subscripted write to it silently converted (or was dropped). Runs at
    /// array-DECLARE time — the declare pass is where member types first meet:
    /// a member already in the PDV carries a type from an earlier LENGTH/SET/
    /// INPUT/assignment; the array creates the REST with its own type. Without
    /// `$` the array is char ONLY when every member was previously defined
    /// character (GH#23 vname_array: `length a $4 b $10; array ch{*} a b;`);
    /// otherwise numeric — and any already-typed member of the other type is
    /// an ERROR. Special-list arrays are exempt: their members are a runtime
    /// PDV fact and `_all_` is heterogeneous by design (GH#48).
    fn checkArrayTypes(self: *Executor, decl: ast.ArrayDecl) Error!void {
        if (decl.special != null) return;
        var saw_char = false;
        var saw_num = false;
        var all_known = decl.elements.len > 0;
        for (decl.elements) |e| {
            if (self.pdv.indexOf(e)) |i| {
                if (self.pdv.vars.items[i].type == .char) saw_char = true else saw_num = true;
            } else all_known = false;
        }
        const resolved: pdv_mod.VarType = if (decl.type == .char or (saw_char and !saw_num and all_known)) .char else .num;
        for (decl.elements) |e| {
            const i = self.pdv.indexOf(e) orelse continue; // array-created member: takes the array's type
            if (self.pdv.vars.items[i].type != resolved)
                self.diags.report(.err, 0, "Variable {s} has been defined as both character and numeric.", .{e}) catch {};
        }
    }

    /// GH#75 ISS-uninitvar: emit `NOTE: Variable X is uninitialized.` once per
    /// RHS-read variable that never made it into the PDV (never assigned/INPUT/
    /// retained/SET/MERGE'd) and is not an automatic. NOTE-only — we do NOT add
    /// a phantom column (see the declareVars ponytail note); the read still
    /// yields missing. The `noted` list is the once-per-var dedup: a var read in
    /// a loop notes once, not per iteration.
    fn noteUninitVars(self: *Executor, program: ast.Program) Error!void {
        // Collect the runtime-populated classes first (BUG-spuriousnote): they are
        // never PDV-seeded at compile time, so the scan below would note them
        // spuriously. Order-independent, as SAS's whole-step compile is.
        for (self.set_names orelse &.{}) |nm| if (try self.inVarOf(nm)) |v|
            try self.uninit_exempt.append(self.arena, v);
        for (self.merge_names orelse &.{}) |nm| if (try self.inVarOf(nm)) |v|
            try self.uninit_exempt.append(self.arena, v);
        for (program) |*s| try self.collectHashTargets(s);
        for (program) |*s| try self.collectCallOutArgs(s);
        var noted: std.ArrayList([]const u8) = .empty;
        for (program) |*s| try self.uninitScanStmt(s, &noted);
    }

    /// BUG-declaredobjnamevalue: collect the step's COMPONENT-OBJECT names, so
    /// `evalVariable` can reject a bare one used as a value instead of handing
    /// back a fabricated missing at exit 0. Whole-step and order-independent,
    /// like `collectHashTargets` beside it (and for the same reason): DECLARE
    /// tells the COMPILER the reference's type, so `h` is an object throughout
    /// the step, not only after its declare has run. `declare hiter hi('h')`
    /// and `h = _new_ hash()` both desugar to `.hash_decl`, so one arm covers
    /// all three spellings.
    fn collectObjectNames(self: *Executor, s: *const ast.Stmt) Error!void {
        switch (s.*) {
            .hash_decl => |d| {
                for (self.obj_names.items) |n| if (eqi(n, d.name)) return; // re-declare in a loop
                try self.obj_names.append(self.arena, d.name);
            },
            .if_ => |f| {
                if (f.then_branch) |b| try self.collectObjectNames(b);
                if (f.else_branch) |b| try self.collectObjectNames(b);
            },
            .do_ => |d| for (d.body) |*b| try self.collectObjectNames(b),
            else => {},
        }
    }

    /// `rc = h.method(…);` targets — assigned by hashOp at run time, never seeded
    /// by declareStmt. Walks nested if_/do_ so the exemption is order-independent.
    fn collectHashTargets(self: *Executor, s: *const ast.Stmt) Error!void {
        switch (s.*) {
            .hash_op => |h| if (h.target) |tgt| try self.uninit_exempt.append(self.arena, tgt),
            .if_ => |f| {
                if (f.then_branch) |b| try self.collectHashTargets(b);
                if (f.else_branch) |b| try self.collectHashTargets(b);
            },
            .do_ => |d| for (d.body) |*b| try self.collectHashTargets(b),
            else => {},
        }
    }

    fn uninitScanStmt(self: *Executor, s: *const ast.Stmt, noted: *std.ArrayList([]const u8)) Error!void {
        switch (s.*) {
            .assign => |aa| try self.uninitScanExpr(aa.value, noted),
            // array element write: the subscript is a read; the target element is
            // an ARRAY-declared member (in the PDV), so only the index counts.
            .array_assign => |aa| {
                try self.uninitScanExpr(aa.array.index, noted);
                try self.uninitScanExpr(aa.value, noted);
            },
            // substr(target,…)=v: target is declared char by declareStmt, so it is
            // in the PDV; pos/len/value are reads.
            .substr_assign => |sa| {
                try self.uninitScanExpr(sa.pos, noted);
                if (sa.len) |l| try self.uninitScanExpr(l, noted);
                try self.uninitScanExpr(sa.value, noted);
            },
            .if_ => |f| {
                try self.uninitScanExpr(f.cond, noted);
                if (f.then_branch) |b| try self.uninitScanStmt(b, noted);
                if (f.else_branch) |b| try self.uninitScanStmt(b, noted);
            },
            .do_ => |d| {
                switch (d.header) {
                    .iter => |it| {
                        try self.uninitScanExpr(it.start, noted);
                        try self.uninitScanExpr(it.stop, noted);
                        if (it.by) |b| try self.uninitScanExpr(b, noted);
                    },
                    .while_, .until_ => |c| try self.uninitScanExpr(c, noted),
                    .list => |l| for (l.specs) |sp| {
                        try self.uninitScanExpr(sp.start, noted);
                        if (sp.stop) |e| try self.uninitScanExpr(e, noted);
                        if (sp.by) |e| try self.uninitScanExpr(e, noted);
                    },
                    .simple => {},
                }
                for (d.body) |*b| try self.uninitScanStmt(b, noted);
            },
            // BUG-infileput: scan `.variable`/`.named` names too — a `_INFILE_`
            // referenced ONLY in a PUT must still route through maybeNoteUninit
            // (sets refs_infile so the raw record is published at INPUT time).
            // BUG-putpagenote: skip the PUT directive/list pseudo-names
            // (_page_/_all_/_numeric_/_character_) — not PDV reads, no NOTE.
            .put => |items| for (items) |it| switch (it) {
                .variable => |v| if (specialPutList(v.name) == null and !eqi(v.name, "_page_"))
                    try self.maybeNoteUninit(v.name, noted),
                .named => |n| if (specialPutList(n.name) == null and !eqi(n.name, "_page_"))
                    try self.maybeNoteUninit(n.name, noted),
                .array_elem => |ae| if (ae.index) |ix| try self.uninitScanExpr(ix, noted),
                else => {},
            },
            .call_ => |c| for (c.args) |*a| try self.uninitScanExpr(a, noted),
            .hash_decl => |h| for (h.args) |a| try self.uninitScanExpr(a.value, noted),
            .hash_op => |h| for (h.args) |a| try self.uninitScanExpr(a.value, noted),
            .where_ => |e| try self.uninitScanExpr(e, noted),
            else => {},
        }
    }

    /// GAP-calloutarg-note: vars in PURE-output CALL-arg positions (CALL SCAN's
    /// pos/len, PRXPOSN's position/length, CALL LABEL's out, …) are initialized BY
    /// the routine, so SAS emits no uninitialized NOTE for them anywhere in the
    /// step — exempt them like the in=/hash-target vars above (whole-step compile,
    /// so order-independent: walks nested if_/do_). Args the routine also READS
    /// (PRXNEXT's start/stop, SORTN's items, RANUNI's seed) stay scannable.
    fn collectCallOutArgs(self: *Executor, s: *const ast.Stmt) Error!void {
        switch (s.*) {
            .call_ => |c| {
                const mask = callOutArgMask(c.name, c.args.len);
                for (c.args, 0..) |*a, i| {
                    if (i < 32 and (mask >> @intCast(i)) & 1 == 1 and a.* == .variable)
                        try self.uninit_exempt.append(self.arena, a.variable);
                }
            },
            .if_ => |f| {
                if (f.then_branch) |b| try self.collectCallOutArgs(b);
                if (f.else_branch) |b| try self.collectCallOutArgs(b);
            },
            .do_ => |d| for (d.body) |*b| try self.collectCallOutArgs(b),
            else => {},
        }
    }

    /// Bitmask of a CALL routine's pure-output argument positions (bit i set ⇒
    /// args[i] is written, not read). Used only by collectCallOutArgs.
    fn callOutArgMask(name: []const u8, argc: usize) u32 {
        if (eqi(name, "missing")) return 0xffff_ffff; // every variable arg is set to missing
        if (eqi(name, "scan") or eqi(name, "prxposn") or eqi(name, "prxsubstr")) return 0b1100; // position, length
        if (eqi(name, "prxnext")) return 0b11_0000; // position, length (start/stop are reads)
        if (eqi(name, "prxchange")) return 0b1_1000; // new-string, result-length
        // BUG-calloutuninit: cats/catt result is arg 0; catx/vname result is arg 1
        // (catx arg 0 = separator, vname arg 0 = the read var).
        if (eqi(name, "cats") or eqi(name, "catt")) return 0b1;
        if (eqi(name, "catx") or eqi(name, "vname")) return 0b10;
        // last arg = the out var: label (2-arg DATA form + 3-arg SCL form) and the
        // old seed-by-ref RNGs ran*/normal/uniform(seed, params…, x) — the seed is
        // read+written, so it stays scannable.
        if (eqi(name, "label") or eqi(name, "ranuni") or eqi(name, "rannor") or
            eqi(name, "ranexp") or eqi(name, "ranpoi") or eqi(name, "ranbin") or
            eqi(name, "rancau") or eqi(name, "rangam") or eqi(name, "rantbl") or
            eqi(name, "rantri") or eqi(name, "normal") or eqi(name, "uniform"))
            return if (argc > 0 and argc <= 32) @as(u32, 1) << @intCast(argc - 1) else 0;
        return 0;
    }

    fn uninitScanExpr(self: *Executor, e: *const ast.Expr, noted: *std.ArrayList([]const u8)) Error!void {
        switch (e.*) {
            .variable => |name| {
                // BUG-arrayinitvalidate F3: a bare array NAME where a scalar VALUE
                // is expected (arithmetic / assignment RHS / comparison) is a SAS
                // ERROR — it used to fabricate a phantom uninitialized scalar and
                // compute a wrong (missing) result. The legal bare uses never reach
                // this walk: dim/hbound/lbound fold the arg at parse time, OF-lists
                // and `do over` expand at token level, and a{i} is an .array_ref.
                for (self.array_names.items) |an| if (eqi(name, an))
                    return self.diags.fail(error.ExecError, 0, "Array {s} is used without a subscript where a scalar value is required.", .{name});
                try self.maybeNoteUninit(name, noted);
            },
            .unary => |u| try self.uninitScanExpr(u.operand, noted),
            .binary => |b| {
                try self.uninitScanExpr(b.lhs, noted);
                try self.uninitScanExpr(b.rhs, noted);
            },
            .call => |c| for (c.args) |*a| try self.uninitScanExpr(a, noted),
            // array_ref members are ARRAY-declared (in the PDV); only the runtime
            // subscript is a variable read that could be uninitialized.
            .array_ref => |ar| try self.uninitScanExpr(ar.index, noted),
            else => {}, // num / str / missing
        }
    }

    /// `_INFILE_` (BUG-infilebufvar / BUG-infilevarnoop): the raw current input
    /// record — a CHAR automatic, like `_N_`/`_ERROR_`. ONE place decides the
    /// step uses it, independently of PDV membership: the OLD discovery rode
    /// the uninitialised-variable NOTE pass, whose PDV-membership early-return
    /// fired whenever a compile-time `_infile_ = …` (even on a DEAD branch —
    /// declareVars declares it regardless) had already put the name in the PDV.
    /// `refs_infile` then stayed false, the INPUT-time publish never ran, and
    /// EVERY read in the step came back blank. In a step with no INPUT there
    /// is no input buffer at all — fail LOUD instead.
    fn useInfileVar(self: *Executor) Error!void {
        if (self.in_items == null) {
            self.diags.report(.err, 0, "_INFILE_ is only available in a DATA step with an INPUT statement", .{}) catch {};
            return error.ExecError;
        }
        self.refs_infile = true;
        _ = try self.pdv.define("_infile_", .char);
    }

    fn maybeNoteUninit(self: *Executor, name: []const u8, noted: *std.ArrayList([]const u8)) Error!void {
        // `_INFILE_` BEFORE the PDV-membership early-return (BUG-infilevarnoop):
        // defined here (blank until the first INPUT publishes the buffer) so a
        // read never fabricates a bogus NUMERIC `.` + this NOTE.
        if (eqi(name, "_infile_")) return self.useInfileVar();
        if (self.pdv.indexOf(name) != null) return; // assigned/INPUT/retained/SET/MERGE'd → known
        // Automatics never note: _N_, _ERROR_, _IORC_, the parser's _setobs_
        // helper, and the SET end=/point= option vars (populated at runtime, so
        // absent from the compile-time PDV this pass sees).
        if (eqi(name, "_n_") or eqi(name, "_error_") or eqi(name, "_iorc_") or eqi(name, "_setobs_")) return;
        // NOTE-ofvarlistuninit: the reserved variable-LIST names are never PDV
        // variables (Language Reference: Concepts ch.25: "SAS reserves the following three names for
        // use as variable list names") — `of _numeric_` reaches this pass as a
        // plain .variable because the parser's expandOf passes the list name
        // through for RUNTIME expansion (eval.zig). A list name can never be
        // an uninitialized variable: no NOTE (the PUT side already exempts
        // them — BUG-putpagenote).
        if (specialVarList(name) != null) return;
        // BUG-firstlastnotbyvar: a first./last. flag is an automatic ONLY when
        // its base variable is one of the step's BY variables (Language Reference: Concepts p.534: SAS
        // creates the two temporaries "for each BY variable"). Any other
        // first./last. reference names nothing — a typo'd flag reads missing
        // like any other uninitialized variable and gets the SAME NOTE (SAS's
        // wording, `Variable first.x is uninitialized.`; SAS CONTINUES — a
        // NOTE, never a hard ERROR). The wholesale exemption hid the typo:
        // Language Reference: Concepts p.540's payroll program with `first.Departmnt` for
        // `first.Department` silently reported DDG = 1,148,000 instead of
        // 448,000, and `if last.y;` on a non-BY var silently emptied the output.
        if (isByFlag(name)) {
            const base = if (startsWithI(name, "first.")) name[6..] else name[5..];
            if (self.by_vars) |bys| for (bys) |b| {
                if (eqi(b, base)) return; // genuine BY flag → automatic
            };
            // not a BY var's flag → fall through to the uninitialized NOTE
        }
        if (self.set_end_var) |ev| if (eqi(name, ev)) return;
        if (self.set_point_var) |pv| if (eqi(name, pv)) return;
        for (self.uninit_exempt.items) |x| if (eqi(name, x)) return; // in= flags + hash targets (BUG-spuriousnote)
        for (noted.items) |n| if (eqi(n, name)) return; // once per var
        try noted.append(self.arena, name);
        // SAS preserves the referenced case in this NOTE (line 0 → "NOTE: …").
        self.diags.note(0, "Variable {s} is uninitialized.", .{name}) catch {};
    }

    /// Best-effort COMPILE-time type of an expression, for `pdv.declare`. Wrong
    /// guesses on an executed path are self-healing (the first write corrects a
    /// guessed var); a never-executed path keeps the guess, so only its
    /// missing-flavor / column type ride on it. ponytail: `input(x, $…)` and
    /// exotic char functions type as num until a real program cares.
    fn staticType(self: *const Executor, e: *const ast.Expr) pdv_mod.VarType {
        return switch (e.*) {
            .str => .char,
            .num, .missing => .num,
            .unary => .num,
            .binary => |b| if (b.op == .concat) .char else .num,
            .variable => |nm| if (self.pdv.indexOf(nm)) |i| self.pdv.vars.items[i].type else .num,
            .array_ref => |ar| if (ar.elements.len > 0 and self.pdv.indexOf(ar.elements[0]) != null)
                self.pdv.vars.items[self.pdv.indexOf(ar.elements[0]).?].type
            else
                .num,
            .call => |c| if (isCharFn(c.name)) .char else .num,
        };
    }

    /// Expand every `\x00prefix=NAME` sentinel the parser emitted for a `set NAME:;`
    /// prefix-wildcard list (ISS-setdslist) into the matching library members, in
    /// library order. Runs before extractSetOptions so the sentinel is gone by the
    /// time end=/point= are pulled. Applies to all four source lists (shared parse).
    fn expandPrefixLists(self: *Executor) Error!void {
        self.set_names = try self.expandPrefixes(self.set_names);
        self.merge_names = try self.expandPrefixes(self.merge_names);
        self.update_names = try self.expandPrefixes(self.update_names);
        self.modify_names = try self.expandPrefixes(self.modify_names);
    }

    fn expandPrefixes(self: *Executor, maybe: ?[]const []const u8) Error!?[]const []const u8 {
        const names = maybe orelse return maybe;
        var any = false;
        for (names) |nm| if (std.mem.startsWith(u8, nm, "\x00prefix=")) {
            any = true;
            break;
        };
        if (!any) return names; // common case: no wildcard, keep the slice as-is
        var out: std.ArrayList([]const u8) = .empty;
        for (names) |nm| {
            if (std.mem.startsWith(u8, nm, "\x00prefix=")) {
                const pfx = stripWork(nm["\x00prefix=".len..]);
                for (self.lib.names.items) |m| {
                    const bare = stripWork(m);
                    if (bare.len >= pfx.len and eqi(bare[0..pfx.len], pfx))
                        try out.append(self.arena, m);
                }
            } else try out.append(self.arena, nm);
        }
        return out.items;
    }

    /// Pull the `\x00updatemode=…` sentinel the parser encoded into the UPDATE name
    /// list (GAP-updatemode) into update_nomissingcheck, leaving only real dataset
    /// names (must run before seedInputColumns/buildDriver resolve the list).
    fn pullUpdateOpts(self: *Executor, names: []const []const u8) Error![]const []const u8 {
        var has = false;
        for (names) |nm| if (std.mem.startsWith(u8, nm, "\x00updatemode=")) {
            has = true;
            break;
        };
        if (!has) return names; // common case: default MISSINGCHECK, slice as-is
        var real: std.ArrayList([]const u8) = .empty;
        for (names) |nm| {
            if (std.mem.startsWith(u8, nm, "\x00updatemode="))
                self.update_nomissingcheck = eqi(nm["\x00updatemode=".len..], "nomissingcheck")
            else
                try real.append(self.arena, nm);
        }
        return real.items;
    }

    /// Pre-declare the SET/MERGE/UPDATE input columns into the PDV, in schema
    /// order, so they take their SAS first-appearance position (ahead of any
    /// retained/sum variable). Define-only — the driver fills the values.
    /// Pull the `\x00end=…`/`\x00point=…` sentinels the parser encoded into the
    /// source lists into set_end_var/set_point_var, leaving only real datasets.
    /// SET/MERGE/UPDATE share the one end flag (they never stack in one step) —
    /// BUG-mergeupdateend: MERGE/UPDATE silently dropped END=, and MERGE warned
    /// about the sentinel as a phantom "dataset  end=e not found". POINT= is
    /// SET-only: on MERGE/UPDATE the sentinel stays in the list so it still
    /// fails loud downstream (POINT=+BY is not meaningful SAS).
    fn extractSetOptions(self: *Executor, program: ast.Program) Error!void {
        self.set_names = try self.stripSourceOpts(self.set_names, true);
        self.merge_names = try self.stripSourceOpts(self.merge_names, false);
        self.update_names = try self.stripSourceOpts(self.update_names, false);
        // BUG-nestedsetopts: a NESTED (IF-branch) source never registers in
        // set_names (BUG-nestedsetdriver), so its end=/point= sentinels were
        // never extracted — `do until(e); if 1 then set a end=e; end;` never
        // set e (an INFINITE LOOP on a 2-row input) and the raw \x00 sentinel
        // leaked into the user-visible "File  end=e does not exist". Walk the
        // whole step and give every non-driver SET node the same strip.
        var seen_driver = false;
        for (program) |*s| {
            const dow = s.* == .do_ and (s.do_.header == .until_ or s.do_.header == .while_);
            try self.extractNestedSetOpts(s, &seen_driver, false, dow);
        }
        // MODIFY: POINT=/END= direct-access is NOT implemented in the modify
        // driver. Without this guard the parser's `\x00opt=var` sentinel stayed
        // in modify_names, so `modify m point=p;` had len==2 and misrouted to
        // buildUpdate — a spurious "UPDATE needs a master and a transaction"
        // warning plus silent-wrong in-place output (the worst failure class for
        // an in-place update). Fail LOUD instead. ponytail: full POINT= modify
        // needs the REPLACE/REMOVE control statements too (unparsed today), so a
        // clean slice is out of scope here — upgrade once those land.
        if (self.modify_names) |names| for (names) |nm| {
            if (nm.len > 0 and nm[0] == 0) {
                const body = nm[1..];
                const eq = std.mem.indexOfScalar(u8, body, '=') orelse continue;
                // Only `end=`/`point=` sentinels can reach here (the parser rejects
                // any other `name=` at rc 1, and expandPrefixes above already ate
                // the `\x00prefix=` form) — both are documented MODIFY arguments
                // (Statements ref p.240-241, Forms 1-4), so this is our gap → rc 2.
                const opt = body[0..eq];
                // BUG-modifyendmsg: this used to call BOTH options "direct/keyed
                // access", and the Statements ref contradicts that twice over.
                // END= "creates and names a temporary variable that contains an
                // END-OF-FILE indicator" and rides Forms 1/2/4; the page then
                // adds the Restriction "Do not use this argument in the same
                // MODIFY statement with the POINT= argument", so END= is not
                // merely a different access mode from direct access, it is
                // FORBIDDEN alongside the direct-access form. And the ref
                // reserves the phrase "direct access" for KEY= ("For direct
                // access using KEY=") while calling Form 3 "random access using
                // POINT=" — KEY= never reaches here anyway, since the parser
                // gaps it out first. So neither label was right.
                const what = if (eqi(opt, "end")) "end-of-file indicator" else "random access";
                return failGap(self.diags, "MODIFY {s}= ({s}) is not supported yet", .{ opt, what });
            }
        };
    }

    /// MODIFY's MASTER must be one of the DATA statement's output data sets.
    /// DATA Step Statements ref printed p.241 (pdf 252 — the page's own footer
    /// reads "MODIFY Statement 241"), the `master-data-set` argument:
    ///
    ///   Restrictions  This data set must also appear in the DATA statement.
    ///
    /// and Language Reference: Concepts printed p.588 Table 23.3 "MODIFY with BY versus UPDATE", row
    /// "Where to specify the modified data set": "specify the updated data set
    /// in both the DATA and the MODIFY statements".
    ///
    /// BUG-modifyoutnamemismatch. opensas commits a MODIFY by RE-EMITTING the
    /// master through the step's output dataset (Library.putInput replaces the
    /// member), so both drivers write wherever the DATA statement points. With
    /// mismatched names that write landed on the wrong member and nothing said
    /// so: `data b; modify d;` degraded to `data b; set d;` — the edits appeared
    /// in a brand-new `b`, `d` stayed byte-identical, exit 0. BOTH drivers were
    /// wrong, not just the single-dataset one the ticket named: transaction-
    /// driven `data b; modify d t; by id;` merged into `b` and left `d` untouched
    /// too, because modifyFlush's rebuild-commit also goes through outputAll.
    /// One guard here, ahead of buildDriver, covers both.
    ///
    /// MEMBERSHIP, NOT EQUALITY — the D-014 half. Printed p.260 Example 8 is
    /// `data invty.stock invty.stock95 invty.stock97; modify invty.stock;`, so
    /// extra outputs BESIDE the master are legal SAS and must keep working; only
    /// the master is restricted (the TRANSACTION data set must NOT be an output).
    ///
    /// rc 1, not a gap: the program violates a documented Restriction, so real
    /// SAS rejects it too — this is "fix your SAS", not an opensas hole (D-009).
    /// The reference does not print the diagnostic TEXT for this condition, and
    /// it does not have to: `outputNamed`'s other caller already answers the very
    /// same relation ("this name is not one of the step's output data sets") with
    /// an ERROR at rc 1 for `output <undeclared>;`, so internal consistency
    /// decides it (D-009b). Hard error rather than report-and-continue so `b` is
    /// never registered — main.zig's "was not replaced" gate deliberately EXEMPTS
    /// MODIFY steps (the re-emitted master IS the edit), and that exemption's
    /// premise is exactly what is false here, so a soft error would have left an
    /// empty `b` clobbering a live member of that name.
    fn assertModifyMasterIsOutput(self: *Executor) Error!void {
        const names = self.modify_names orelse return;
        if (names.len == 0) return;
        // BUG-modifymasteroptname: compare the MEMBER NAME, not the serialized
        // name+options blob. `modify a(where=(x>15));` arrives as the single string
        // `a(where = ( x > 15 ) )`, so the raw comparison could never match the
        // DATA statement's `a` and the only documented way to subset a MODIFY was
        // rejected outright. The options themselves are none of this guard's
        // business — they say WHICH ROWS to update, not WHICH DATA SET.
        const master = splitSourceRef(names[0]);
        if (self.outputNamed(master.name) == null)
            return self.diags.fail(error.ExecError, 0, "MODIFY updates {s} in place, but the DATA statement names {s} — the MODIFY data set must also appear in the DATA statement", .{ master.name, if (self.cur_out) |co| co.name else "no data set" });
        // Row-subsetting on the master — the where=/obs=/firstobs= OPTIONS and
        // the WHERE STATEMENT alike — USED to be refused LOUDLY here, because
        // honouring either DESTROYED the unselected rows: the rebuild-commit
        // re-emitted the FILTERED copy resolveDataset hands back (`modify
        // a(where=(x>15));` committed 2 of 3; `modify m t; by k; where k>1;`
        // destroyed k=1 at rc 0). Both surfaces are implemented now
        // (BUG-modifywhereopt, GAP-modifywherestmt): the iteration reads the
        // filtered copy while the commit indexes the UNFILTERED member through
        // ModifyState.src_pos — filter-then-match (Statements ref printed
        // p.360/p.245), the statement filtering the transaction too (p.360's
        // WHERE-variable rule), WHEREUP='s default of not re-evaluating
        // written rows falling out of the flush (Language Reference: Concepts p.215). No refusal
        // remains in this guard.
    }

    /// BUG-nestedsetopts: the extractSetOptions walk over one statement. Strips
    /// end=/point= from every SET node that is NOT the step driver (the driver's
    /// list was already stripped via set_names). `nested`/`in_dow` mirror scan
    /// and detectDowSet exactly: .do_ bodies pass both through, .if_ branches
    /// are nested, and only a TOP-LEVEL DO UNTIL/WHILE makes in_dow. A nested
    /// source that must DRIVE the step — a SET inside a top-level DO
    /// UNTIL/WHILE (its read fires at the node via dowRead; the driver only
    /// gates) or a POINT= read (buildDriver's direct-access path) — is promoted
    /// to set_names when no top-level source exists, so both paths see it.
    /// Anything else is stashed in extra_src_names for collectExtraSetsStmt.
    fn extractNestedSetOpts(self: *Executor, s: *const ast.Stmt, seen_driver: *bool, nested: bool, in_dow: bool) Error!void {
        switch (s.*) {
            .set => |names| {
                if (!nested and !seen_driver.*) {
                    seen_driver.* = true; // the driver — already stripped via set_names
                    return;
                }
                const expanded = (try self.expandPrefixes(names)).?; // non-null in, non-null out
                // POINT= on a non-driver SET: opensas models ONE direct-access
                // source, so a SECOND POINT= source stays loud.
                var has_point = false;
                for (expanded) |nm| has_point = has_point or std.mem.startsWith(u8, nm, "\x00point=");
                if (has_point and self.set_point_var != null)
                    // Two POINT= SET sources in one step is valid SAS — our
                    // one-direct-access-source limit, so rc 2 (D-009).
                    return failGap(self.diags, "POINT= is not supported on a second or nested SET source", .{});
                // GAP-secondsetstmt — Statements ref p.341 Example 6, verbatim:
                //   data south; set revenue; if region=4; set expense point=_n_; run;
                // ONE sequential driver + a SECOND SET that is a direct-access
                // POINT= lookup is the documented table-lookup idiom: the lookup
                // does NOT drive — iteration, EOF and the implicit output all
                // follow the SEQUENTIAL driver (the example has no STOP). Claim
                // the node: buildDriver resolves its source and runStmt reads at
                // THIS node. END= on the SAME statement stays illegal (END=
                // entry: "END= cannot be used with POINT=.").
                if (has_point and self.set_names != null) {
                    for (expanded) |nm| if (std.mem.startsWith(u8, nm, "\x00end="))
                        return self.diags.fail(error.ExecError, 0, "END= cannot be used with POINT=", .{});
                    self.set_point_node = s;
                }
                const clean = (try self.stripSourceOpts(expanded, true)).?; // non-null in, non-null out
                if (self.set_names == null and (in_dow or self.set_point_var != null)) {
                    self.set_names = clean; // nested-only source that must drive
                    return;
                }
                try self.extra_src_names.put(self.arena, s, clean);
            },
            .if_ => |f| {
                if (f.then_branch) |b| try self.extractNestedSetOpts(b, seen_driver, true, in_dow);
                if (f.else_branch) |b| try self.extractNestedSetOpts(b, seen_driver, true, in_dow);
            },
            .do_ => |d| for (d.body) |*b| try self.extractNestedSetOpts(b, seen_driver, nested, in_dow),
            else => {},
        }
    }

    /// Drop a SET point=/nobs= control var from the output schema — SAS treats
    /// both as temporary, like SET end= (BUG-setpointtemp). NOT dropped when the
    /// name is also a genuine column of a SET source: then it is real input data
    /// and stays (`set have point=p;` where have really carries a p column).
    fn dropSetControlTemp(self: *Executor, maybe: ?[]const u8) Error!void {
        const name = maybe orelse return;
        if (self.set_names) |names| for (names) |nm| {
            if (try self.resolveDataset(nm, false, null)) |ds| {
                for (ds.columns.items) |c| if (eqi(c.name, name)) return;
            }
        };
        try self.drops.append(self.arena, name);
    }

    fn stripSourceOpts(self: *Executor, maybe: ?[]const []const u8, is_set: bool) Error!?[]const []const u8 {
        const names = maybe orelse return maybe;
        var real: std.ArrayList([]const u8) = .empty;
        for (names) |nm| {
            if (nm.len > 0 and nm[0] == 0) {
                const body = nm[1..]; // "end=e" or "point=i"
                const eq = std.mem.indexOfScalar(u8, body, '=') orelse continue;
                if (eqi(body[0..eq], "end")) {
                    self.set_end_var = body[eq + 1 ..];
                    try self.drops.append(self.arena, body[eq + 1 ..]); // end= var is temporary
                    continue;
                }
                if (is_set and eqi(body[0..eq], "point")) {
                    self.set_point_var = body[eq + 1 ..];
                    continue;
                }
            }
            try real.append(self.arena, nm);
        }
        return real.items;
    }

    /// Return `items` with each bare list-INPUT item's informat filled from an
    /// `informat name spec;` statement — so `informat a date9.; input a;` reads dates
    /// like the `input a :date9.;` modifier path (BUG-informatstmtdate). The INFORMAT
    /// statement's specs are collected into `self.attrs` (\x01-tagged) by scan();
    /// readNum then applies date/time/comma informats uniformly. Unchanged when
    /// nothing matches — the common no-INFORMAT-statement path allocates nothing.
    fn patchInformats(self: *Executor, items: []const ast.InputItem) Error![]const ast.InputItem {
        if (self.attrs.items.len == 0) return items;
        var patched: ?[]ast.InputItem = null;
        for (items, 0..) |it, idx| {
            if (it.informat != null or it.name.len == 0) continue;
            for (self.attrs.items) |a| {
                if (a.fmt.len > 1 and a.fmt[0] == 1 and eqi(a.name, it.name)) {
                    if (patched == null) patched = try self.arena.dupe(ast.InputItem, items);
                    patched.?[idx].informat = a.fmt[1..];
                    // BUG-informatlistinput: SAS's INFORMAT-statement spec behaves
                    // like the `:` modifier (modified LIST input — a whitespace
                    // token), NOT a fixed-width column read. Without list_mod the
                    // io.readList `$w.` branch consumed w columns; a record shorter
                    // than w spilled the NEXT dataline into the following var and
                    // swallowed a whole obs (`informat x $20.; input x $ y;` over
                    // 2 rows lost the 2nd). Char tokens ignore the width (dynamic
                    // strings); numeric informats (date/comma) apply as before.
                    patched.?[idx].list_mod = true;
                    break;
                }
            }
        }
        // ponytail: dups per read only when an INFORMAT statement actually matches a
        // bare INPUT var (rare, small datalines); the no-attr common path returns items.
        return patched orelse items;
    }

    /// `_INFILE_ = …` writes THROUGH to the input buffer (BUG-infilevarnoop) —
    /// SAS: the next INPUT re-parses the EDITED record (the Language Reference: Concepts p.517
    /// varying-record-layout look-ahead idiom: `input @;` inspect/edit the
    /// buffer, then a second INPUT parses it). Only a HELD record (trailing
    /// `@`/`@@`) is re-parsed; after a releasing INPUT the next INPUT reads a
    /// FRESH record and republishes, so editing `lines[cur]` then would corrupt
    /// an unread record (SAS: that write lands in the stale buffer, invisible).
    /// The PDV value itself is set by the callers.
    fn writeInfileBuffer(self: *Executor, text: []const u8) void {
        if ((self.li.hold_iter or self.li.hold_across) and self.li.cur < self.li.lines.len)
            self.li.lines[self.li.cur] = text;
    }

    /// Run one INPUT statement against the shared line cursor. Resumes mid-record
    /// when the line is being held (a prior `@`/`@@`), else starts at the current
    /// record. A trailing `@`/`@@` on THIS statement re-holds the line; otherwise
    /// the cursor steps to the next record. Reading past EOF stops the step without
    /// writing the partial obs (SAS semantics). Returns .normal or .stop (PG-atptr).
    /// ponytail: hold continuation tracks the whitespace-token cursor; `@col`/`+n`
    /// column reads don't advance it, so mixing a column read with a trailing-@ hold
    /// across statements can misalign — list/formatted input composes cleanly.
    fn execInput(self: *Executor, items: []const ast.InputItem) Error!Flow {
        const full = self.li.lines;
        if (full.len == 0) {
            // BUG-inputnosourcefabricates: NO INFILE and NO DATALINES at all —
            // INPUT has no source, and the step silently fabricated ONE
            // all-missing observation at exit 0. Every sibling missing-source
            // is loud (`set nosuchds`, `infile 'nosuch.txt'`, an unknown
            // fileref) — this one is too, per D-002 (SAS: "ERROR: No DATALINES
            // or INFILE statement."; wording needs-oracle, loudness settled
            // in-house — tick305 F2's own conclusion for this branch). Kept
            // distinct from BUG-setinputinert: a declared-but-EMPTY source
            // (0-record file / 0-line datalines, dl_lines non-null) still
            // reads 0 observations quietly.
            if (self.sources.items.len == 0) {
                self.diags.report(.err, 0, "No DATALINES or INFILE statement.", .{}) catch {};
                return error.ExecError;
            }
            return .normal; // declared source is empty: INPUT reads nothing
        }
        if (self.li.cur >= full.len) {
            self.li.eof = true;
            return .stop; // INPUT hit EOF (e.g. a 2nd INPUT past the last record)
        }
        const dlm = if (self.infile) |inf| inf.dlm else null;
        const dsd = if (self.infile) |inf| inf.dsd else false;
        const mode = if (self.infile) |inf| inf.overflow else .flowover;
        const patched = try self.patchInformats(items);
        const hold = inputHold(patched);
        // Resume mid-record only when the line is currently held; a fresh read starts
        // at column 0 (readList tokenizes lines[cur] from the start with pos = 0).
        const continuing = self.li.hold_iter or self.li.hold_across;
        var pos: usize = if (continuing) self.li.pos else 0;
        // Record-boundary control (BUG-infilemissover). SAS 9.4: MISSOVER/TRUNCOVER/
        // STOPOVER "control what happens when an INPUT statement reaches the end of
        // the current record." Default FLOWOVER pulls values from the next record —
        // a short record then silently misaligns all following data. Window the line
        // source to the current record so readList's list-mode spill onto the next
        // line can't fire; absent values read as missing instead. STOPOVER makes a
        // short record a hard error. (The formatted MISSOVER-vs-TRUNCOVER partial-
        // field distinction IS modelled: BUG-missovertruncover-partial threads
        // `mode == .missover` into readList.)
        // BUG-inputmultirecmode: the short-record modes govern SHORT-record handling
        // ONLY — an EXPLICIT record advance (`/`, `#n`) must still move to the
        // requested record (Language Reference: Concepts p.497 combines MISSOVER with 27 `/` advances).
        // Clipping the window to the current record blocked the advance, so every
        // obs re-read the SAME record (`b` duplicated `a`) and the obs count
        // doubled. Split the items at each advance and read each segment against
        // its own one-record window: the advance works and the no-spill short-record
        // rule still applies per record. ponytail: PAD under these modes is still
        // not modelled — add if the corpus hits it. An advance past EOF reads an
        // empty record (all missing); the SAS EOF-stop-on-advance is F6's.
        var last: usize = undefined;
        if (mode == .flowover or dlm != null or !hasRecordAdvance(patched)) {
            const lines = if (mode == .flowover) full else full[0 .. self.li.cur + 1];
            if (mode == .stopover and recordShort(full[self.li.cur], pos, patched, dlm)) {
                self.diags.report(.err, 0, "INPUT statement reached past the end of a record (STOPOVER)", .{}) catch {};
                return error.ExecError;
            }
            const r = try io.readList(self.pdv, patched, lines, self.li.cur, dlm, dsd, mode == .missover, &pos);
            // GAP-inputeofdegrade: the read wanted a record past the end. Under
            // FLOWOVER — which was handed the WHOLE file, so "no next record"
            // really is end-of-file — SAS ends the step here. Statements ref
            // printed p.178 (that page's own footer reads "178 Chapter 2 /
            // Dictionary of SAS DATA Step Statements"), the INPUT statement's
            // "End-of-File" section: "End-of-file occurs when an INPUT statement
            // reaches the end of the data. If a DATA step tries to read another
            // record after it reaches an end-of-file, then execution stops."
            // Both broken shapes ARE that sentence: a `/` asking for a record
            // that is not there, and a FLOWOVER spill needing one to finish the
            // observation.
            //
            // .stop (not a diagnostic) is the right flow: it ends the step with
            // the current observation UNWRITTEN, which is what the reference
            // shows happening. Printed p.323's RETAIN example puts a PUT on each
            // side of an INPUT over two data lines and reports "The first PUT
            // statement is executed three times, whereas the second PUT statement
            // is executed only twice. The DATA step ceases execution when the
            // INPUT statement executes for the third time and reaches the end of
            // the file." The trailing PUT running one time FEWER is the proof the
            // iteration aborts AT the INPUT, so the implicit OUTPUT never runs.
            //
            // MISSOVER/TRUNCOVER are deliberately excluded: they are handed a
            // one-record window (`full[0..cur+1]` above), so they reach the same
            // out-of-data condition on EVERY short record, and setting the
            // remaining variables to missing is their documented job — printed
            // p.133 MISSOVER "variables without any values assigned are set to
            // missing", against p.132 FLOWOVER "causes an INPUT statement to
            // continue to read the NEXT input data record". Applying the missing
            // rule under FLOWOVER was the bug: it silently gave FLOWOVER
            // MISSOVER's semantics.
            if (r.eof and mode == .flowover) {
                self.li.eof = true;
                return .stop;
            }
            last = r.hi;
        } else {
            const base = self.li.cur; // record this INPUT started on (`#n` is relative to it)
            var rec = base;
            // High-water record index — the SAME value readList returns as `hi`
            // (BUG-inputlinehighwater). A BACKWARD `#n` leaves rec < hi; releasing
            // rec + 1 collapsed the group to one record (sliding window + fabricated
            // EOF row, BUG-backwardhashnrec). A segment can't read past rec (its
            // window is clipped), so tracking the advance targets suffices.
            var hi = base;
            var seg: std.ArrayList(ast.InputItem) = .empty;
            var fresh = false; // an advance control resets the cursor (readList retokenizes)
            var i: usize = 0;
            while (i <= patched.len) : (i += 1) {
                var adv: ?usize = null;
                if (i < patched.len) {
                    const it = patched[i];
                    const inf = if (it.name.len == 0) (it.informat orelse "") else "";
                    if (inf.len >= 1 and inf[0] == '/') {
                        adv = rec + 1;
                    } else if (inf.len >= 1 and inf[0] == '#') {
                        const n = std.fmt.parseInt(usize, inf[1..], 10) catch 1; // mirror readList
                        adv = base + (if (n > 0) n - 1 else 0);
                    } else {
                        try seg.append(self.arena, it);
                    }
                }
                if (i == patched.len or adv != null) {
                    if (seg.items.len > 0) {
                        var spos: usize = if (fresh) 0 else pos; // first segment resumes a held cursor
                        if (mode == .stopover and rec < full.len and recordShort(full[rec], spos, seg.items, dlm)) {
                            self.diags.report(.err, 0, "INPUT statement reached past the end of a record (STOPOVER)", .{}) catch {};
                            return error.ExecError;
                        }
                        _ = try io.readList(self.pdv, seg.items, full[0..@min(rec + 1, full.len)], rec, dlm, dsd, mode == .missover, &spos);
                        pos = spos;
                        seg.clearRetainingCapacity();
                    }
                    fresh = true;
                    if (adv) |r| {
                        // GAP-inputeofdegrade, the FOURTH site and the one this
                        // file's own comment already flagged as "the SAS
                        // EOF-stop-on-advance is F6's": an advance target past
                        // the last record used to read an EMPTY record, so every
                        // remaining variable came back missing and the partial
                        // observation was written. Same p.178 rule — asking for a
                        // record after end-of-file stops execution. Reached only
                        // by MISSOVER/TRUNCOVER/STOPOVER with a record advance;
                        // the advance itself is not the short-record condition
                        // those options govern, so it stops here too.
                        if (r >= full.len) {
                            self.li.eof = true;
                            return .stop;
                        }
                        rec = r;
                        hi = @max(hi, rec);
                    }
                }
            }
            last = hi; // release past the HIGHEST record read (an advance past EOF counts)
        }
        // `_INFILE_` (BUG-infilebufvar): publish the raw record this INPUT just
        // consumed (`last` is the record index readList finished on). The slice
        // borrows the datalines/infile arena text — stable for the whole step.
        if (self.refs_infile and last < full.len) try self.pdv.set("_infile_", .{ .str = full[last] });
        // END= from the post-advance position (`last` is the shared high-water
        // value) — not the iteration-top guess, which went stale the moment
        // this INPUT consumed more than one record (BUG-infileendmultirec).
        try self.setInfileEnd(last);
        if (hold.single or hold.across) {
            self.li.cur = last; // keep the record for the next INPUT
            self.li.pos = pos;
            self.li.hold_iter = hold.single;
            self.li.hold_across = hold.across;
        } else {
            self.li.cur = last + 1; // release: the next INPUT reads a new record
            self.li.pos = 0;
            self.li.hold_iter = false;
            self.li.hold_across = false;
        }
        return .normal;
    }

    fn seedInputColumns(self: *Executor) Error!void {
        // QA tick377 F2: a POINT= lookup riding beside a MERGE/UPDATE/MODIFY
        // driver (its SET is the first top-level one, so set_names holds the
        // LOOKUP's list) is first-mentioned AFTER the driver statement — the
        // driver owns the early PDV slots and the lookup's columns seed at
        // their own node in declareStmt's program-order walk. Seed the driver
        // here with the SAME plain define buildMerge/slotsOf use today (order
        // moves; types/widths/diags don't). Without this the orelse chain
        // seeded the LOOKUP first (b k p q for `merge mA mB; set lk point=_n_;`).
        if (self.set_point_var != null and self.set_point_node == null and
            (self.merge_names != null or self.update_names != null or self.modify_names != null))
        {
            const drv = self.merge_names orelse self.update_names orelse self.modify_names.?;
            for (drv) |name| {
                if (try self.resolveDataset(name, false, null)) |ds| {
                    for (ds.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
                }
            }
            return;
        }
        const names = self.set_names orelse self.merge_names orelse
            self.update_names orelse self.modify_names orelse return;
        for (names) |name| {
            if (try self.resolveDataset(name, false, null)) |ds| try self.seedColumnsOf(ds);
        }
    }

    /// Define one LENGTH/ATTRIB-declared var in the PDV (define-only — no value is
    /// wiped) and stamp its declared char width (VLENGTH — BUG-vlength) / numeric
    /// truncate-on-store byte-length (GH#46). Called from run(): early vars before
    /// seedInputColumns, `.late` vars (BUG-varorder) after declareVars.
    fn seedDeclVar(self: *Executor, dv: DeclVar) Error!void {
        if (self.pdv.indexOf(dv.name)) |i| {
            const vr = self.pdv.vars.items[i];
            // GAP-typerespec (doc-finder tick272 F4): a numeric LENGTH/ATTRIB
            // naming a var already established CHARACTER (a char-literal
            // assignment, char RETAIN init, char FORMAT, or a prior char LENGTH)
            // is the fatal SAS conflict — "Variable X has been defined as both
            // character and numeric." The step halts 0 obs (gated after this
            // pass), the statement-side twin of the SET conflict (GH#69/#70,
            // seedColumnsOf). Only the char→num direction fires: a char TYPE
            // carries real evidence (staticType/declare returns char only for a
            // char literal/expr), whereas a num type is often just the default
            // guess — so a char LENGTH correcting a num-default guess
            // (`retain x; length x $8;`) is NOT a conflict and must not error.
            if (vr.type == .char and dv.type == .num) {
                self.diags.report(.err, 0, "Variable {s} has been defined as both character and numeric.", .{dv.name}) catch {};
                return;
            }
            // BUG-charlenrespec (F3): a second char-length spec for a var whose
            // char length is already set is IGNORED — SAS keeps the FIRST length
            // and warns. This matches the parser's first-wins assignment-truncation
            // width (char_lens), so the descriptor length and the stored value
            // length agree (case c used to disagree: descriptor 20, value 5).
            // GH#73 handles the assignment-first shape upstream (dropped in
            // lengthVars); this covers LENGTH↔LENGTH, LENGTH↔ATTRIB, ATTRIB↔LENGTH.
            if (dv.type == .char and dv.len > 0 and vr.type == .char and vr.len > 0) {
                self.diags.warn(0, "Length of character variable {s} has already been set. Use the LENGTH statement as the very first statement in the DATA STEP.", .{dv.name}) catch {};
                return;
            }
        }
        const di = try self.pdv.define(dv.name, dv.type);
        if (dv.type == .char and dv.len > 0) self.pdv.vars.items[di].len = dv.len;
        if (dv.type == .num and dv.len >= 3 and dv.len < 8) self.pdv.vars.items[di].numlen = dv.len;
    }

    /// Seed one source dataset's columns into the PDV (define + carry declared
    /// length / label / format / informat). Shared by the driver's seedInputColumns
    /// and MULTISET-impl's extra SETs; first source to define a column wins.
    /// The LENGTH/ATTRIB declaration of `name` this step (self.declared), or null.
    fn declaredOf(self: *Executor, name: []const u8) ?DeclVar {
        for (self.declared) |dv|
            if (std.ascii.eqlIgnoreCase(dv.name, name)) return dv;
        return null;
    }

    /// Per-source column→PDV-slot maps for the loadRow readback loop
    /// (PERF-loadrowdual, docs/findings/perf-findings-tick121.md): one name
    /// lookup per column HERE (build time), then loadRow writes by slot — zero
    /// `indexOf`/lowerString per cell per row on the hottest loop.
    fn slotsOf(self: *Executor, dss: []*Dataset) Error![]const []usize {
        const out = try self.arena.alloc([]usize, dss.len);
        for (dss, 0..) |ds, k| out[k] = try io.columnSlots(self.pdv, ds);
        return out;
    }

    /// Stamp `_setobs_` (the `nobs=` backing var) ONCE per distinct row source
    /// rather than per row, and only when the step requested nobs= at all
    /// (PERF-loadrowdual — io.loadRow used to define+set it on every row of
    /// every read). Retained via scan(), so the stamp survives the
    /// per-iteration reset; a run of rows from one source reuses it. SAS
    /// semantics: a multi-source SET stamps the a+b TOTAL (GAP-nobsmultisrc,
    /// nobs_total — the old per-source count was the documented ponytail);
    /// single-source stamps that source's obs count.
    fn stampObs(self: *Executor, ds: *const Dataset) Error!void {
        if (self.nobs_var == null) return;
        if (self.obs_src == ds) return;
        self.obs_src = ds;
        _ = try self.pdv.define("_setobs_", .num);
        const n = self.nobs_total orelse self.physNobs(ds);
        try self.pdv.set("_setobs_", .{ .num = @floatFromInt(n) });
    }

    fn seedColumnsOf(self: *Executor, ds: *Dataset) Error!void {
        for (ds.columns.items) |c| {
            // GH#69/#70: a variable stacked as CHARACTER in one place and NUMERIC
            // in another (two CERTAIN, differing types) is a fatal SAS error — the
            // step halts with 0 obs (gated in run() before the row loop). A GUESSED
            // type adopting a certain one stays benign (pdv.define / TRIAGE-gen2values).
            //
            // ONE deliberate exception (ponytail: opensas CSV-inference limitation,
            // not a SAS-semantics win): a char LENGTH placed BEFORE the SET (the
            // ubiquitous SDTM `length …; set src;` schema-pin) leniently coerces the
            // source value the way opensas always has. opensas infers a source
            // column's type from CSV data, so an all-integer ID column (AESPID
            // "1","2") reads as numeric though the study's real var is char $8;
            // halting there breaks correct programs (real SDTM AE/CM/MH). Only a
            // GENUINE conflict halts: two SET sources disagreeing (#69), or a char
            // LENGTH applied to a var ALREADY brought in numeric by a PRECEDING SET
            // (#70, after_input). Upgrade to strict once readers carry real types.
            if (self.pdv.indexOf(c.name)) |i| {
                const vr = self.pdv.vars.items[i];
                if (!vr.guessed and vr.type != c.type) {
                    const decl = self.declaredOf(c.name);
                    const lenient = if (decl) |d| (d.type == .char and !d.after_input) else false;
                    if (!lenient) {
                        if (decl != null and vr.type == .char and c.type == .num)
                            self.diags.report(.err, 0, "Character length cannot be used with numeric variable {s}.", .{c.name}) catch {}
                        else
                            self.diags.report(.err, 0, "Variable {s} has been defined as both character and numeric.", .{c.name}) catch {};
                        continue; // don't coerce/carry; the halt gate finalizes 0 obs
                    }
                }
            }
            const di = try self.pdv.define(c.name, c.type);
            // carry the source column's DECLARED char length into the PDV var so
            // VLENGTH/VLENGTHX see the storage length, not the value width, after a
            // SET/MERGE (BUG-vlength). First source wins; a same-step LENGTH stays.
            if (c.type == .char) if (c.len) |L| {
                if (L > 0 and self.pdv.vars.items[di].len == 0) {
                    self.pdv.vars.items[di].len = L;
                } else if (L > 0 and self.pdv.vars.items[di].len > 0 and L != self.pdv.vars.items[di].len) {
                    // GH#72: sources give the var DIFFERENT lengths — SAS keeps the
                    // FIRST (already carried, unchanged) and warns of possible
                    // truncation (default VARLENCHK=WARN, nonzero RC).
                    self.diags.warn(0, "Multiple lengths were specified for the variable {s} by input data set(s). This may cause truncation of data.", .{c.name}) catch {};
                }
            };
            // Same for a NUMERIC source column's declared byte-length (3..7):
            // carry it into the PDV var's numlen so #46's truncate-on-store
            // (pdv.truncNum) fires for a SET-inherited length — the 0-row
            // template idiom carrying SDTM var lengths (GH#59). First source
            // wins; a same-step LENGTH (seeded earlier) stays.
            if (c.type == .num) if (c.len) |L| {
                if (L >= 3 and L < 8 and self.pdv.vars.items[di].numlen == 0) {
                    self.pdv.vars.items[di].numlen = L;
                } else if (L >= 3 and L < 8 and self.pdv.vars.items[di].numlen > 0 and L != self.pdv.vars.items[di].numlen) {
                    self.diags.warn(0, "Multiple lengths were specified for the variable {s} by input data set(s). This may cause truncation of data.", .{c.name}) catch {}; // GH#72 numeric analogue
                }
            };
            // carry a source column's label into the step so it survives to
            // this step's output and is visible to VLABEL (BUG-labelspersist).
            // FIRST source wins (BUG-setlabellastwins) — the same rule as
            // length/format/informat below; a same-step LABEL statement still
            // overrides (its setVarLabel runs later, unconditional).
            if (c.label) |l| if (self.lib.varLabel(c.name) == null) try self.lib.setVarLabel(c.name, l);
            // carry the source column's attached FORMAT / INFORMAT onto the PDV
            // var so they survive to this step's output schema (proc contents
            // after SET) and feed VVALUE/format resolution (GH#31b). First
            // source wins; a same-step FORMAT/ATTRIB overrides it (applyAttrs
            // and the self.formats stamp both run later, at step finalize).
            if (c.format) |f| if (self.pdv.formatOf(c.name) == null) self.pdv.setFormat(c.name, f);
            if (c.informat) |inf| if (self.pdv.informatOf(c.name) == null) self.pdv.setInformat(c.name, inf);
        }
    }

    /// MULTISET-impl: find every SET beyond the driver — a 2nd top-level `set b;`
    /// or an if-guarded `if _n_=1 then set summary;` — and register it as an
    /// executable node with its own concatenate cursor (runExtraSet). SAS: each
    /// SET has an INDEPENDENT read position, and a SET'd variable is RETAINED
    /// until its next read, so the _n_=1 lookup value persists across iterations.
    /// The driver SET (self.set_names — the first TOP-LEVEL SET) is skipped. Only
    /// for a plain SET-driven step (a POINT= source of the driver list's own,
    /// MERGE / UPDATE / MODIFY keep the old single path; a second-SET POINT=
    /// lookup — GAP-secondsetstmt — registers extras like the plain case).
    fn collectExtraSets(self: *Executor, program: ast.Program) Error!void {
        // No set_names gate: when the ONLY source is a nested (conditional) SET
        // there is no driver at all, but its columns must still seed the PDV —
        // the `if 0 then set b; … stop;` schema idiom (BUG-nestedsetdriver).
        // A second-SET POINT= lookup (set_point_node — GAP-secondsetstmt)
        // leaves the SEQUENTIAL driver in place, so other extra SETs still
        // register below; the lookup's own node is skipped inside (it reads
        // via the direct-access path, not its own cursor).
        if (self.set_point_var != null and self.set_point_node == null) return;
        if (self.merge_names != null or self.update_names != null or self.modify_names != null) return;
        var seen_driver = false;
        for (program) |*s| try self.collectExtraSetsStmt(s, &seen_driver, false);
    }

    fn collectExtraSetsStmt(self: *Executor, s: *const ast.Stmt, seen_driver: *bool, nested: bool) Error!void {
        switch (s.*) {
            .set => |node_names| {
                // A top-level DO UNTIL/WHILE's inner SET is the DOW case:
                // detectDowSet already claimed it (its read fires at the node
                // via dowRead) and scan/extractSetOptions registered it as the
                // driver — registering it here too would double-count the one
                // source as both driver and extra.
                if (self.dow_set == s) return;
                // The claimed second-SET POINT= lookup (GAP-secondsetstmt):
                // read via buildDriver's direct-access path, not its own cursor.
                // Its PDV columns seed at the node in declareStmt's walk
                // (QA tick377 F2), not here.
                if (self.set_point_node == s) return;
                // The first TOP-LEVEL SET is the driver (loadNext reads it); skip
                // it. A NESTED set is never the driver — it is an executable extra
                // even when textually first (BUG-nestedsetdriver), so only a
                // non-nested SET may consume the skip.
                if (!nested and !seen_driver.*) {
                    seen_driver.* = true;
                    return;
                }
                // BUG-nestedsetopts: resolve the sentinel-stripped list from the
                // extractSetOptions walk — the raw node list still carries
                // `\x00end=e`, which leaked into "File  end=e does not exist".
                const names = self.extra_src_names.get(s) orelse node_names;
                var dss: std.ArrayList(*Dataset) = .empty;
                for (names) |name| {
                    if (try self.resolveDataset(name, true, null)) |src| {
                        try dss.append(self.arena, src);
                        try self.seedColumnsOf(src);
                        // SET'd vars are retained until the next read — keeps the
                        // conditional-lookup values alive across the per-iter reset.
                        for (src.columns.items) |c| try self.retained.append(self.arena, c.name);
                    } else {
                        self.diags.report(.err, 0, "File {s} does not exist", .{name}) catch {};
                        return error.ExecError;
                    }
                }
                try self.extra_sets.append(self.arena, .{ .node = s, .dss = dss.items, .slots = try self.slotsOf(dss.items) });
            },
            // Recurse into IF branches and DO bodies so a conditional SET is
            // found. A source inside a DO body is NESTED (never the driver),
            // so `nested = true` like the IF branches; the single DOW exception
            // is caught by the dow_set guard above. This arm was the ONLY
            // statement walker without one (BUG-doblocksourceinert, QA tick307
            // F1) — its old justification, "a SET inside a DO body is the DOW
            // case, already failed loud", is false for a NON-ITERATIVE block:
            // `if 1 then do; set a; end;` fell into `else`, read zero rows,
            // and fabricated one all-missing observation at exit 0.
            .if_ => |f| {
                if (f.then_branch) |b| try self.collectExtraSetsStmt(b, seen_driver, true);
                if (f.else_branch) |b| try self.collectExtraSetsStmt(b, seen_driver, true);
            },
            .do_ => |d| for (d.body) |*b| try self.collectExtraSetsStmt(b, seen_driver, true),
            // BUG-nestedsourceschema: a NESTED MERGE/UPDATE/MODIFY never
            // registers its name list (BUG-nestedsetdriver), and only SET got
            // the compensating schema seed — a nested one contributed NO PDV
            // columns, emitting "1 obs with 0 variables" at exit 0 (fabricated
            // output). Seed the compile-time schema like the nested SET; the
            // runtime semantics of a conditional MERGE/UPDATE stay needs-oracle.
            .merge, .update, .modify => if (nested) try self.seedNestedSource(s),
            else => {},
        }
    }

    /// BUG-nestedsourceschema: seed the PDV columns of a nested MERGE/UPDATE/
    /// MODIFY's sources (in statement order, like the drivers do). Also
    /// restores the fail-loud the nested cut-off lost: UPDATE (and MODIFY with
    /// a transaction) still requires BY, and a leftover sentinel that can
    /// never be a dataset (point= on MERGE/UPDATE/MODIFY) errors CLEAN — the
    /// raw \x00 must not reach a user-visible message.
    fn seedNestedSource(self: *Executor, s: *const ast.Stmt) Error!void {
        var names: []const []const u8 = switch (s.*) {
            .merge => |n| n,
            .update => |n| try self.pullUpdateOpts(n),
            .modify => |n| n,
            else => return,
        };
        names = (try self.stripSourceOpts(names, false)).?; // end= shares the one end flag
        const needs_by = s.* == .update or (s.* == .modify and names.len >= 2);
        if (needs_by and self.by_vars == null)
            return self.diags.fail(error.ExecError, 0, "The BY statement is required for the UPDATE statement", .{});
        for (names) |name| {
            if (name.len > 0 and name[0] == 0) {
                const body = name[1..];
                const eq = std.mem.indexOfScalar(u8, body, '=') orelse body.len;
                return self.diags.fail(error.ExecError, 0, "{s}= cannot be used with MERGE/UPDATE/MODIFY", .{body[0..eq]});
            }
            if (try self.resolveDataset(name, false, null)) |src| {
                try self.seedColumnsOf(src);
            } else {
                self.diags.report(.err, 0, "File {s} does not exist", .{name}) catch {};
                return error.ExecError;
            }
        }
    }

    /// Read the next observation from an executable (non-driver) SET into the PDV
    /// via its own cursor. Sources concatenate (di/ri). SAS: a SET hitting EOF
    /// ends the DATA step at once — the current obs is NOT output, so return .stop.
    fn runExtraSet(self: *Executor, es: *ExtraSet) Error!Flow {
        while (es.di < es.dss.len) {
            const ds = es.dss[es.di];
            if (es.ri < ds.rowCount()) {
                try io.loadRow(self.pdv, ds, es.ri, es.slots[es.di]);
                try self.stampObs(ds);
                es.ri += 1;
                // end= (BUG-nestedsetopts): 1 when this read was the last obs.
                if (self.set_end_var != null) try self.setEndFlag(!extraHasMore(es));
                // BUG-nestedsetopts: when the nested SET is the step's ONLY source
                // the driver is the single-pass .once — `if 1 then set d end=e;`
                // must iterate until d is exhausted (2 obs), while `if 0 then
                // set b;` still runs exactly once (no read → no continuation).
                // A successful node-driven read buys one more iteration; the
                // extra cursor is finite, so this always terminates.
                if (self.driver_ptr) |dp| switch (dp.*) {
                    .once => |*spent| spent.* = false,
                    else => {},
                };
                return .normal;
            }
            es.di += 1;
            es.ri = 0;
        }
        return .stop;
    }

    /// True while the extra SET's cursor still holds an observation past the one
    /// just read — end= is 1 exactly when the row just read was the last one.
    fn extraHasMore(es: *const ExtraSet) bool {
        if (es.di < es.dss.len and es.ri < es.dss[es.di].rowCount()) return true;
        var d = es.di + 1;
        while (d < es.dss.len) : (d += 1) if (es.dss[d].rowCount() > 0) return true;
        return false;
    }

    /// The extra-SET cursor state for a given `.set` AST node, or null if this is
    /// the driver SET (inert at run time — loadNext already read it).
    fn extraSetFor(self: *Executor, node: *const ast.Stmt) ?*ExtraSet {
        for (self.extra_sets.items) |*es| if (es.node == node) return es;
        return null;
    }

    /// Read one INFILE source's records (BUG-multiinfilelastwins — factored
    /// out of run()'s single-file reader, which wrote the one shared dl_lines).
    /// INFILE DATALINES/CARDS reads the embedded block; an external path
    /// streams line-by-line through a buffered reader (PERF-infilecap — no
    /// whole-file readFileAlloc, no size cap). FIRSTOBS= skips leading records;
    /// OBS=/LINESIZE= apply after (FEAT-infileobslinesize). An OPEN error is a
    /// HARD SAS error ("Physical file does not exist"), reported loud, never a
    /// silent 0-obs step (ISS-infilemissing). No Io (unit tests) → no records.
    fn readInfileLines(self: *Executor, inf: ast.Infile) Error![][]const u8 {
        var lines: [][]const u8 = &.{};
        if (inf.inline_data) {
            // INFILE DATALINES/CARDS: the block is already in dl_lines (set
            // from the `.datalines` stmt); don't read a file.
            lines = self.dl_lines orelse &.{};
        } else if (self.io) |io_| {
            // ponytail: lines still collect in the arena (the .lines driver and
            // io.readList's record-windowing want a slice; true pull-streaming
            // would have to cross io.zig). One record over the line-buffer size
            // fails LOUD (StreamTooLong), never truncated.
            const opened: ?Io.File = Io.Dir.cwd().openFile(io_, inf.path, .{}) catch null;
            if (opened) |file| {
                defer file.close(io_);
                var rbuf: [256 * 1024]u8 = undefined; // line buffer (SAS LRECL max is 1 MiB; 256 KiB covers the corpus)
                var fr = file.reader(io_, &rbuf);
                var list: std.ArrayList([]const u8) = .empty;
                // Buffer slices are transient → dupe each record into the arena.
                // null = EOF; "\n" never yields a phantom trailing "" and a blank
                // final record survives (no pop needed, unlike splitScalar).
                while (fr.interface.takeDelimiter('\n') catch |err| switch (err) {
                    error.StreamTooLong => {
                        self.diags.report(.err, 0, "INFILE record exceeds the {d} KiB line buffer, {s}", .{ rbuf.len / 1024, inf.path }) catch {};
                        return error.ExecError;
                    },
                    error.ReadFailed => {
                        self.diags.report(.err, 0, "I/O error reading INFILE file, {s}", .{inf.path}) catch {};
                        return error.ExecError;
                    },
                }) |ln| {
                    try list.append(self.arena, std.mem.trimEnd(u8, try self.arena.dupe(u8, ln), "\r"));
                }
                lines = list.items;
            } else {
                // AUDIT-errhaltclass: HALT, matching the two sibling arms just
                // above (StreamTooLong / ReadFailed) — three error arms in one
                // function, two of which already stopped the step. Reporting and
                // running on with an EMPTY record list is the doc's ERROR class
                // treated as its CONTINUING class (Language Reference: Concepts printed p.172 vs
                // p.174-175), and it did real damage two ways: a SET-driven step
                // (`set src; infile 'nope'; input v $;`) wrote every row with v
                // MISSING, and `data sc.keeper; infile 'nope'; input i;` REPLACED
                // an existing 3-obs permanent data set with an empty one — the
                // "WARNING: Data set … was not replaced because this step was
                // stopped" clause of Example Code 8.6, inverted into data loss.
                // Both verified on a clean-rebuilt binary at exit 1, then read
                // back by a separate run at exit 0. The 4 sibling "File {s} does
                // not exist" sites (SET/MERGE sources) have always halted.
                return self.diags.fail(error.ExecError, 0, "Physical file does not exist, {s}", .{inf.path});
            }
        }
        // FIRSTOBS= skips leading records; OBS=n is the last record number read
        // (absolute, 1-based) → cap the count; LINESIZE=n truncates each record
        // to n columns before INPUT parses it. Sub-slices only, no mutation.
        //
        // GAP-optfirstobsraw: the SYSTEM options `options firstobs=/obs=` supply
        // the DEFAULTS here, exactly as they already do for a DATA SET read
        // (io.applyObsSlice). Language Reference: Concepts printed p.517 (pdf index 534; that page's
        // own footer reads "Reading Raw Data with the INPUT Statement / 517"),
        // Table 21.5 "Additional Data-Reading Features", the row for reading
        // "some but not all records in the file":
        //
        //   FIRSTOBS=and OBS= options in an INFILE statement; FIRSTOBS= and
        //   OBS= system options; #n line pointer control.
        //
        // (the run-together "FIRSTOBS=and" is the volume's own typo). So the
        // system options are a documented mechanism for RAW input, not only for
        // data sets. They used to reach dataset reads ONLY, so a raw read
        // ignored them completely and the canonical header-skip idiom
        // `options firstobs=2;` silently parsed the HEADER AS DATA — measured:
        // the output carried a bogus `name=name age=.` observation at exit 0,
        // and only a downstream PROC re-sliced it away on ITS read, which is
        // what made the bug look from a PROC PRINT like it was working.
        //
        // PRECEDENCE WHEN BOTH ARE SET IS DOC-SILENT, SO IT IS NOT DECIDED HERE.
        // The INFILE dictionary entry's FIRSTOBS=/OBS= carry no Interaction or
        // Restriction block naming the system options (Statements ref printed
        // p.131 and p.135), Language Reference: Concepts has no precedence prose for the pair, and the
        // SAS System Options: Reference — where the system option's own entry
        // would live — is not among the volumes we hold. The nearest passage
        // points the OTHER way and is why no override rule is claimed here: SQL
        // procedure ref printed p.150 warns that for a VIEW, a system option's
        // limit "is applied first to the underlying table, and then next to the
        // view, effectively reducing the number of observations twice" — i.e.
        // COMPOSITION, not override. That is (system vs data set) on views, not
        // INFILE, so it does not transfer; it is recorded so nobody later
        // "restores" an override rule believing the doc backed one.
        //
        // What this change therefore does is the half the doc DOES settle: the
        // system option now reaches a raw read when the INFILE statement is
        // SILENT on that field. When BOTH are given, the INFILE option wins —
        // which is not a new invention but exactly TODAY'S behaviour preserved
        // (the system value is ignored outright right now), so the undecided
        // case moves not at all and stays available for an oracle.
        //
        // ponytail: `inf.firstobs` is a plain `usize` defaulting to 1, so an
        // EXPLICIT `firstobs=1` is indistinguishable from "unspecified" and a
        // global >1 still wins over it. Closing that needs `firstobs: ?usize` in
        // ast.zig + parser.zig, which another agent holds; the residue is one
        // rare shape (`options firstobs=5; infile f firstobs=1;`) and it is
        // strictly less wrong than ignoring the option outright, which is what
        // happens today. `obs` is already optional and has no such gap.
        const eff_firstobs = if (inf.firstobs > 1) inf.firstobs else io.global_firstobs;
        const eff_obs: ?usize = inf.obs orelse
            (if (io.global_obs != std.math.maxInt(usize)) io.global_obs else null);
        const skip = if (eff_firstobs > 0) eff_firstobs - 1 else 0;
        lines = if (skip < lines.len) lines[skip..] else &.{};
        if (eff_obs) |ob| {
            const take = if (ob > skip) ob - skip else 0;
            lines = if (take < lines.len) lines[0..take] else lines;
        }
        if (inf.linesize) |ls| {
            const capped = try self.arena.alloc([]const u8, lines.len);
            for (lines, 0..) |ln, i| capped[i] = ln[0..@min(ln.len, ls)];
            lines = capped;
        }
        return lines;
    }

    /// Make sources[idx] the current line source (BUG-multiinfilelastwins):
    /// the live cursor `li` swaps with the selected source's saved one (each
    /// file keeps its own read position for the whole step — selecting a
    /// source never rewinds it), the INPUT options and END= target follow,
    /// and the END= flag is preset exactly like the .lines gate does — BEFORE
    /// the next INPUT, 1 when no record remains past the one it will read.
    fn selectSource(self: *Executor, idx: usize) Error!void {
        if (self.cur_src) |old| self.sources.items[old].li = self.li;
        self.cur_src = idx;
        const src = self.sources.items[idx];
        self.li = src.li;
        self.infile = src.spec;
        self.infile_end_var = src.spec.end_var;
        try self.setInfileEnd(self.li.cur);
    }

    /// runStmt `.infile` arm: executing an INFILE selects its source (SAS: an
    /// INPUT reads the file of the most recently executed INFILE statement).
    /// The statement's OWN options (dlm/dsd/overflow/END=) apply even when its
    /// source is the shared datalines device.
    fn selectInfileStmt(self: *Executor, s: *const ast.Stmt) Error!void {
        const spi = self.src_of_stmt.get(s) orelse return; // scan registers every INFILE in the program
        const sp = self.infile_specs.items[spi];
        try self.selectSource(sp.src);
        self.infile = sp.spec;
        self.infile_end_var = sp.spec.end_var;
        try self.setInfileEnd(self.li.cur);
    }

    fn buildDriver(self: *Executor) Error!Driver {
        // BUG-pointmergelookup: the POINT= guards and the direct-read setup must
        // hold no matter which driver wins below — with a MERGE/UPDATE driver
        // they used to be skipped, and the `set ds point=v;` then silently never
        // read (QA tick357 F4 — quietly-missing lookup values, the clinical-
        // worst failure class). Statements ref, SET POINT= Restrictions: "You
        // cannot use POINT= with a BY statement, a WHERE statement, or a WHERE=
        // data set option" — flat, driver-independent. With neither present, a
        // POINT= SET beside a driver is the documented idiom (SET Example 6:
        // `set revenue; … set expense point=_n_;`) — resolve its source so the
        // executable .set performs the read and the lookup columns land.
        if (self.set_point_var != null) {
            if (self.by_vars != null) return self.diags.fail(error.ExecError, 0, "POINT= cannot be used with BY", .{});
            if (self.where_expr != null) {
                self.diags.report(.err, 0, "The WHERE statement cannot be used with the POINT= option", .{}) catch {};
                return .{ .once = true }; // spent driver: no iterations, no output
            }
            // GAP-secondsetstmt: when the lookup rides a SECOND SET (p.341
            // Example 6), its source names live with that NODE — set_names is
            // the SEQUENTIAL driver there. The p.335 WHERE= leg and the source
            // resolution below both scan the lookup's own list.
            const point_names: []const []const u8 = if (self.set_point_node) |pn|
                self.extra_src_names.get(pn) orelse &.{}
            else
                self.set_names orelse &.{};
            // The third leg of the same p.335 sentence (BUG-pointwheredsopt):
            // the where= data set OPTION — the WHERE statement's option twin,
            // so the same policy as the leg above: loud ERROR, spent driver.
            // It used to be silently DROPPED by resolvePointSource (the
            // BUG-pointnobsbase pin, made before this repo had the Statements
            // volume) while its statement twin already errored — two legs of
            // one rule enforced, the third ignored.
            for (point_names) |name| if (try self.hasWhereOpt(name)) {
                self.diags.report(.err, 0, "The WHERE= data set option cannot be used with the POINT= option", .{}) catch {};
                return .{ .once = true }; // spent driver: no iterations, no output
            };
            // BUG-pointredefinesnobs: bind EVERY named source, not just the first.
            // This loop used to `break` on the first that resolved, so
            // `set a b point=p;` silently became `set a point=p;` — and because
            // NOBS= then rode that single source, the canonical `do p = 1 to n;`
            // idiom read 3 of 5 observations and stopped, at exit 0, never
            // reaching the loud out-of-range guard that would have exposed it.
            //
            // The reference settles BOTH halves and needs no oracle. Statements
            // ref printed p.334 (that page's own footer reads "334 Chapter 2 /
            // Dictionary of SAS DATA Step Statements"), NOBS=: "creates and names
            // a temporary variable whose value is usually the total number of
            // observations in the input data set OR DATA SETS. If more than one
            // data set is listed in the SET statement, the value of the NOBS=
            // variable equals the total number of observations in the data sets
            // that are listed." No POINT= exception — and the same entry states
            // it outright: "Interaction  The NOBS= and POINT= options are
            // INDEPENDENT of each other." So POINT= may not redefine NOBS=, which
            // is exactly what it was doing.
            //
            // That the addressing spans all the sources (rather than POINT= being
            // single-source with NOBS= merely reporting more) is settled on the
            // same page by the OPEN=DEFER restriction: "When you specify the DEFER
            // option, you cannot use … the POINT= statement option … These
            // constructs imply either random processing or interleaving of
            // observations FROM THE DATA SETS, which is not possible unless ALL
            // DATA SETS ARE OPEN." POINT='s own Restrictions list (printed p.335)
            // bars BY, WHERE, WHERE=, KEY=, transport/sequential/view sources and
            // CAS — a multi-dataset list is NOT among them, so it is legal SAS.
            {
                var pdss: std.ArrayList(*Dataset) = .empty;
                var pslots: std.ArrayList([]const usize) = .empty;
                for (point_names) |name| if (try self.resolvePointSource(name)) |ds| {
                    try pdss.append(self.arena, ds);
                    // same compile-time schema rule as the sequential path below
                    // (define is idempotent — this also resolves the read slots)
                    try pslots.append(self.arena, try io.columnSlots(self.pdv, ds));
                    // SET-read vars auto-retain (Language Reference: Concepts p.495 step 5) — a POINT= read
                    // inside a conditional keeps its last value, like any SET.
                    for (ds.columns.items) |c| try self.retained.append(self.arena, c.name);
                };
                self.set_point_dss = pdss.items;
                self.set_point_slots = pslots.items;
                // NOBS= is the total across the listed sources, exactly as the
                // sequential multi-source path already computes it
                // (GAP-nobsmultisrc) — one rule, both spellings, which is the
                // internal consistency this ticket was filed on.
                if (self.nobs_var != null and pdss.items.len > 1) {
                    var total: usize = 0;
                    for (pdss.items) |ds| total += self.physNobs(ds);
                    self.nobs_total = total;
                }
            }
            // A POINT= source that resolves to nothing must fail loud like the
            // sequential path (BUG-setmissingquiet) — a silently-skipped direct
            // read leaves quietly-missing lookup values (BUG-pointmergelookup's
            // failure class), worse than no read at all.
            if (self.set_point_dss.len == 0) {
                const name = if (point_names.len > 0) point_names[0] else "?";
                self.diags.report(.err, 0, "File {s} does not exist", .{name}) catch {};
                return .{ .once = true }; // spent driver: no iterations, no output
            }
        }
        if (self.update_names) |names| return self.buildUpdate(names);
        if (self.modify_names) |names| {
            // `modify master trans; by k;` is TRANSACTION-driven (Language Reference: Concepts p.596:
            // 3 REPLACEs + 3 OUTPUTs = the 6 transaction rows; p.599 Table 23.4
            // has no _IORC_ code for "a master row with no transaction" because
            // that iteration does not exist). Routing it through UPDATE's
            // master-driven, group-collapsing driver gave every MASTER row a
            // _SOK iteration — the p.595 error-checking idiom then REPLACEd
            // every unmatched master row with stale/blank transaction values
            // and silently wiped 7 of 13 obs IN PLACE (BUG-modifybymasterdriven).
            // But single-dataset `modify master;` is a plain sequential in-place
            // rewrite of the master — each obs → PDV → statements → written back
            // (BUG-modifysingle).
            if (names.len >= 2) return self.buildModify(names);
            var dss: std.ArrayList(*Dataset) = .empty;
            // BUG-modifywhereopt: capture the surviving SOURCE positions so a
            // row-subsetting option can be honoured instead of refused. The ITERATION
            // runs over the filtered copy; the COMMIT must still index the unfiltered
            // master, or every hidden row is destroyed (measured last tick:
            // `where=(x>15)` committed 2 of 3 rows).
            // GAP-modifywherestmt: where_first=true now — the WHERE STATEMENT filters
            // the iterated copy through the same position channel (it was silently
            // IGNORED here before, updating rows the user excluded). Filter-then-
            // match, and WHEREUP='s default (Language Reference: Concepts p.215) falls out of the flush:
            // modified/appended rows are NOT re-evaluated against the WHERE.
            var msrc: ?[]const usize = null;
            for (names) |name| if (try self.resolveDataset(name, true, &msrc)) |ds| try dss.append(self.arena, ds);
            // BUG-modifystoptruncates: the sequential path keeps its own driver —
            // one iteration per MASTER obs — but it must COMMIT the way its
            // MODIFY-BY sibling already does: by re-emitting the WHOLE master with
            // per-row overrides applied, not by accumulating whatever rows the loop
            // happened to output. Without this the stored data set was only as
            // complete as the loop, so ANY early exit truncated the file — a
            // `stop;` on the first obs EMPTIED a 5-observation master at exit 0
            // with nothing in the log. Statements ref printed p.240 says MODIFY
            // works "in place but does not create an additional copy"; opensas was
            // creating a copy and substituting it, so observations the step never
            // reached were neither replaced, deleted nor appended and must still
            // be there.
            //
            // The FIX IS THE COMMIT, not the statements. QA's asymmetry localises
            // it: a real ERROR mid-step never truncated (rc 1, all rows present),
            // only the statements that end the loop early did — so a `stop`-shaped
            // branch and then an `abort`-shaped branch would have been two patches
            // for one root. Pointing `modify_by` at a state object routes this path
            // through the EXISTING modifyReplace/modifyFlush pair, so STOP, ABORT,
            // a subsetting DELETE and a mid-step ERROR all commit identically:
            // whatever the loop recorded is applied over the master, and every row
            // it never recorded is re-emitted untouched.
            //
            // ponytail: ModifyState is transaction-shaped, so `trans`/`t_by`/
            // `t_slots`/`ti`/`m_hint`/`prev_*` are INERT here — they are read only
            // by modifyNext, which belongs to the `.modify` driver this path does
            // not use. `trans` is aimed at the master because the field is not
            // optional; splitting the commit half out of ModifyState is the upgrade
            // if a third caller ever appears.
            if (dss.items.len == 1) {
                const iter = dss.items[0]; // possibly FILTERED — what the loop reads
                // The flush re-emits the MASTER, so it must be the whole member. With
                // no row filter these are the same object and src_pos stays empty.
                const m = self.lib.find(splitSourceRef(names[0]).name) orelse iter;
                const st = try self.arena.create(ModifyState);
                st.* = .{
                    .master = m,
                    .trans = m, // inert on this path — see above
                    .m_by = &.{},
                    .t_by = &.{},
                    .m_slots = try io.columnSlots(self.pdv, m),
                    .src_pos = if (iter == m) &.{} else (msrc orelse &.{}),
                };
                self.modify_by = st;
            }
            return .{ .sets = .{ .dss = dss.items, .slots = try self.slotsOf(dss.items) } };
        }
        if (self.merge_names) |names| return self.buildMerge(names);
        if (self.set_names) |names| point: {
            // `set ds point=i;` — no sequential driver: the executable `.set`
            // reads obs `i` directly, and each successful read re-arms this
            // single-pass driver so the step iterates until STOP/ABORT/an
            // out-of-range read (Language Reference: Concepts p.488: POINT= cannot detect EOF —
            // BUG-pointnoiterate). A re-read with no progress stops the step
            // (the .set arm) where SAS itself would loop forever. The BY/WHERE
            // guards and the source resolution live at the top of buildDriver
            // (BUG-pointmergelookup) — they hold for every driver, not just this
            // one. GAP-secondsetstmt: set_point_node set means the lookup rides
            // a SECOND SET — the sequential driver below WON (Example 6 has no
            // STOP: EOF, iteration and the implicit output are the driver's).
            if (self.set_point_var != null and self.set_point_node == null) {
                // BUG-pointsuppressesalloutput: an INPUT + line source reads
                // records alongside (Language Reference: Concepts p.477 step 3 names INPUT a peer of
                // the dataset readers) and its EOF ends the step (Table 20.4) —
                // POINT= does NOT drive here: fall through to the .lines driver,
                // keep the automatic output, skip the repeat-stop.
                if (self.cur_src != null and self.in_items != null) break :point;
                self.point_driven = true;
                return .{ .once = false };
            }
            var dss: std.ArrayList(*Dataset) = .empty;
            var invars: std.ArrayList(?[]const u8) = .empty;
            for (names) |name| {
                if (try self.resolveDataset(name, true, null)) |ds| {
                    try dss.append(self.arena, ds);
                    const iv = try self.inVarOf(name);
                    try invars.append(self.arena, iv);
                    if (iv) |v| try self.drops.append(self.arena, v); // in= flags are temporary
                } else {
                    // SET on a missing dataset is a hard error in SAS ("File X
                    // does not exist"), not a skip: a silently-absent input made
                    // the output dataset silently never exist, exit 0
                    // (BUG-setmissingquiet). errhalt (0db5a2c) poisons the rest.
                    self.diags.report(.err, 0, "File {s} does not exist", .{name}) catch {};
                    return .{ .once = true }; // spent driver: no iterations, no output
                }
            }
            // Pre-declare every column of every source into the PDV up front,
            // as MERGE/UPDATE do (SAS builds the PDV from all sources at
            // compile time). Without this a var living only in a ZERO-ROW
            // source (the EMPTY_* metadata idiom) never gets its CERTAIN type
            // — the compile pass's guess wins and gen2 EG's VISITNUM landed
            // char instead of numeric (BUG-setpdvschema).
            for (dss.items) |ds| {
                for (ds.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
                // SET'd vars are retained until the next read (SAS: SET/MERGE/
                // MODIFY/UPDATE auto-retain) — the extra-SET path already does
                // this; without it a concat/interleave source lacking a var
                // cleared the previous source's value to missing (BUG-setvarretain).
                for (ds.columns.items) |c| try self.retained.append(self.arena, c.name);
            }
            var any_in = false;
            for (invars.items) |iv| any_in = any_in or iv != null;
            var st: SetState = .{ .dss = dss.items, .in_vars = invars.items, .any_in = any_in, .slots = try self.slotsOf(dss.items) };
            // GAP-nobsmultisrc: `set a b … nobs=n;` — SAS sets nobs= to the SUM of
            // observations across ALL sources, known at compile time. stampObs reads
            // this; single-source stays per-source (null).
            if (self.nobs_var != null and dss.items.len > 1) {
                var total: usize = 0;
                for (dss.items) |ds| total += self.physNobs(ds);
                self.nobs_total = total;
            }
            // `set … ; by …;` interleaves by the BY key: precompute each source's
            // BY column indices and a per-source cursor. NOTSORTED has no sorted
            // order to interleave by — concatenate instead; applyBy's peek still
            // gives consecutive-group FIRST./LAST. (GAP-batch-qa107). byColsOf
            // still validates the BY vars exist on every source either way.
            if (self.by_vars) |bys| {
                const by_cols = try self.arena.alloc([]const ?usize, dss.items.len);
                for (dss.items, 0..) |ds, d| {
                    by_cols[d] = (try self.byColsOf(ds, bys)) orelse return .{ .once = true }; // spent driver: no iterations, no output
                }
                if (!self.by_notsorted) {
                    st.by_cols = by_cols;
                    st.cursors = try zeros(self.arena, dss.items.len);
                }
            }
            return .{ .sets = st };
        }
        // A declared line source (datalines or INFILE) + at least one INPUT
        // drives iterations off the read cursor — already seeded above. The
        // io-free path (unit tests, interpret's null io) cannot OPEN an
        // external INFILE: its source registered but read nothing, and the
        // phantom empty source must not drive a 0-iteration .lines step —
        // keep the pre-multiinfile inert-.once shape there (the FILENAME
        // binding still takes effect; the read is simply unobservable
        // without io — main.zig's mid-PROC fileref test pins this shape).
        // A datalines device, or any external file once io exists, drives.
        if (self.cur_src != null and self.in_items != null) {
            var readable = false;
            for (self.sources.items) |src|
                if (src.spec.inline_data or self.io != null) {
                    readable = true;
                    break;
                };
            if (readable) return .lines;
        }
        return .{ .once = false };
    }

    /// True if the SET sources still hold an observation past the current cursor —
    /// end= is 1 exactly when the row just read was the last one (BUG-setend).
    fn setsHasMore(sd: *const SetState) bool {
        if (sd.by_cols != null) {
            for (sd.dss, 0..) |ds, d| if (sd.cursors[d] < ds.rowCount()) return true;
            return false;
        }
        if (sd.di < sd.dss.len and sd.ri < sd.dss[sd.di].rowCount()) return true;
        var d = sd.di + 1;
        while (d < sd.dss.len) : (d += 1) if (sd.dss[d].rowCount() > 0) return true;
        return false;
    }

    /// Set the SET `end=` variable (if any) to 1 on the last obs, else 0.
    fn setEndFlag(self: *Executor, is_last: bool) Error!void {
        if (self.set_end_var) |ev| try self.pdv.set(ev, .{ .num = if (is_last) 1 else 0 });
    }

    /// INFILE END= (FEAT-infileend): publish the flag from ONE authoritative
    /// record position — 1 when no record remains past `last_rec`
    /// (BUG-infileendmultirec). Iteration-top / source-switch callers pass
    /// `li.cur` (the record the next INPUT will read); execInput passes the
    /// record it actually consumed, so `/`, `#n` and multi-INPUT iterations —
    /// every record-advance path — agree through this one predicate.
    /// REVERT-infileendmultirec: …EXCEPT where the reference forbids the flag
    /// entirely, in which case it stays 0 forever (infileEndRestricted).
    fn setInfileEnd(self: *Executor, last_rec: usize) Error!void {
        const ev = self.infile_end_var orelse return;
        const is_last = last_rec + 1 >= self.li.lines.len and !self.infileEndRestricted();
        try self.pdv.set(ev, .{ .num = if (is_last) 1 else 0 });
    }

    /// The INFILE END= cases SAS 9.4 forbids — the flag is never set to 1, and
    /// stays at its documented 0 (p.130: "Until SAS processes the last data
    /// record, the END= variable is set to 0"). NOT an error: the volume
    /// glosses its own "Restriction" wording as a flag that stays 0.
    ///
    /// DATA Step Statements ref printed p.130 (pdf 141; that page's own footer
    /// reads "130 Chapter 2 / Dictionary of SAS DATA Step Statements"), END=:
    ///
    ///   Restriction  You cannot use the END= option with the UNBUFFERED
    ///                option, the DATALINES statement, the DATALINES4
    ///                statement, or an INPUT statement that reads multiple
    ///                input data records.
    ///   Tip          Use the option EOF= on page 130 when END= is invalid.
    ///
    /// The DATALINES half is settled TWICE, because printed p.138 (pdf 149,
    /// footer "138 Chapter 2 / …") states the BEHAVIOUR rather than merely
    /// restricting it, and chains to instream data explicitly:
    ///
    ///   Interaction  When you use UNBUFFERED, SAS never sets the END=
    ///                variable to 1.
    ///   Tip          When you read instream data with a DATALINES statement,
    ///                UNBUFFERED is in effect.
    ///
    /// So DATALINES => UNBUFFERED in effect => END= never 1, for ANY input
    /// shape — which is why the instream test below is unconditional and does
    /// not care about the INPUT at all.
    ///
    /// "Restriction … cannot be used with" means a 0 flag and not a diagnostic:
    /// the SET statement uses the IDENTICAL construction for the IDENTICAL
    /// option at printed p.332 (footer "332 Chapter 2 / …") and then spells the
    /// consequence out — "Restriction END= cannot be used with POINT=. When
    /// random access is used, the END= variable is never set to 1." opensas
    /// already implements THAT half the never-set way, so the tree had voted
    /// one way on SET and the other on INFILE (D-009b).
    ///
    /// This REVERSES part of a green, gated landing (e7ac8ee7,
    /// BUG-infileendmultirec) whose premise came from a QA expectation of
    /// `TOTAL groups=2`, not from the volume. Its ENGINEERING is kept intact —
    /// the one-helper/one-predicate shape is exactly what makes this rule a
    /// single guard instead of four — and only the premise is corrected.
    ///
    /// D-015a checked, since this rests on an undated Restriction: the whole
    /// INFILE chapter contains NO dated feature sentence ("maintenance
    /// release" / "Beginning with SAS 9.4" / "9.4M"), though the volume does
    /// use that notation elsewhere. So p.130 is not superseded prose.
    ///
    /// ponytail: "multiple input data records" is read as a RECORD-ADVANCE
    /// (`/`, `#n`) anywhere in the step's INPUT items. Two SEPARATE
    /// single-record INPUT statements in one iteration are deliberately NOT
    /// restricted — p.130 says "an INPUT statement that reads multiple ...
    /// records", singular, and each such statement reads one. That is the one
    /// sub-case the wording leaves open; upgrade here if an oracle says
    /// otherwise.
    fn infileEndRestricted(self: *Executor) bool {
        if (self.infile) |inf| if (inf.inline_data) return true;
        if (self.in_items) |items| if (hasRecordAdvance(items)) return true;
        return false;
    }

    /// The SET `in=` flags: 1 on the source whose row was just read, 0 on the
    /// others (BUG-setinflag; mirrors mergeNext's in_vars wiring).
    fn setInFlags(self: *Executor, sd: *const SetState, contributor: usize) Error!void {
        // PERF-setinflagquad: no `in=` var anywhere → skip the O(#sources) scan.
        if (!sd.any_in) return;
        for (sd.in_vars, 0..) |iv, d| {
            if (iv) |v| try self.pdv.set(v, .{ .num = if (d == contributor) 1 else 0 });
        }
    }

    /// Load the next observation into the PDV; false when the source is spent.
    fn loadNext(self: *Executor, d: *Driver) Error!bool {
        // Line-source iteration-boundary housekeeping, whatever the driver
        // (BUG-setinputinert): a trailing `@` is released at the top of the
        // step — a SET/MERGE/UPDATE step with INPUTs is a hybrid (Language Reference: Concepts
        // p.477 step 3) and must not re-read one held record every iteration.
        // A consuming INPUT already cleared flag+cursor, so a released hold
        // never double-advances (BUG-atholdhang). `@@` keeps its hold across
        // the boundary, skipping records it exhausted.
        if (self.li.hold_iter) {
            self.li.hold_iter = false;
            self.li.cur += 1;
            self.li.pos = 0;
        }
        if (self.li.hold_across) {
            while (self.li.cur < self.li.lines.len and onlyWsFrom(self.li.lines[self.li.cur], self.li.pos)) {
                self.li.cur += 1;
                self.li.pos = 0;
            }
        }
        switch (d.*) {
            .once => |*spent| {
                if (spent.*) return false;
                spent.* = true;
                return true;
            },
            .lines => {
                // The read happens at run time in execInput; this only gates whether
                // another iteration runs.
                if (self.li.eof) return false;
                if (self.li.cur >= self.li.lines.len) {
                    // BUG-multiinfilelastwins (Language Reference: Concepts Table 20.4 row 5): the step
                    // stops when EOF is FIRST reached on ANY of the files — but
                    // an exhausted CURRENT source is not EOF while another source
                    // still holds records; the iteration may switch to it. Stop
                    // only once every source is spent.
                    for (self.sources.items, 0..) |src, i|
                        if (self.cur_src == null or i != self.cur_src.?)
                            if (src.li.cur < src.lines.len) return true;
                    self.li.eof = true;
                    return false;
                }
                // INFILE END= preset BEFORE the iteration's INPUT — 1 when no
                // record remains past the one this INPUT will read; execInput
                // re-publishes from the post-read position (BUG-infileendmultirec).
                try self.setInfileEnd(self.li.cur);
                return true;
            },
            // DOWLOOP-impl: a DOW SET reads at its node (dowRead) each DO iteration,
            // so the outer loop only GATES on remaining rows — never consume here.
            .sets => |*sd| {
                if (self.dow_set != null) return setsHasMore(sd);
                return self.setsConsume(sd);
            },
            .merge => |*md| return self.mergeNext(md),
            .update => |*u| return self.updateNext(u),
            .modify => |*md| return self.modifyNext(md),
        }
    }

    /// Consume the next SET observation into the PDV (advance the cursor, set end=);
    /// false when the sources are spent. Shared by the top-of-loop driver and the
    /// DOW inner read (dowRead).
    fn setsConsume(self: *Executor, sd: *SetState) Error!bool {
        // `set … by …;` — interleave the pre-sorted sources by the BY key.
        if (sd.by_cols) |bc| {
            const pick = (try self.pickInterleave(sd.dss, sd.cursors, bc)) orelse return false;
            // Sorted-input invariant: the emitted key sequence never goes
            // backwards (the pick is the min of the current rows, so a
            // backwards step means a source is unsorted). SAS errors; we
            // must not silently emit wrong order / wrong first./last.
            // (BUG-setbyunsorted, the mergeNext check's SET twin).
            const tup = try self.byTupleOfSet(sd.dss[pick], sd.cursors[pick], bc[pick]);
            self.truncBySet(tup); // compare/store the truncated key (BUG-setbyvarlen)
            if (sd.prev_by) |pb| if (self.cmpBy(tup, pb) == .lt) {
                self.diags.report(.err, 0, "BY variables are not properly sorted", .{}) catch {};
                return false;
            };
            // Language Reference: Concepts p.566 Step 1: PDV vars go missing each time a NEW data set
            // is read AND when the BY group changes (BUG-setsourcereset).
            const by_changed = if (sd.prev_by) |pb| self.cmpBy(tup, pb) != .eq else false;
            if (sd.last_contrib != pick or by_changed) self.resetSetVars(sd);
            sd.last_contrib = pick;
            sd.prev_by = tup;
            try io.loadRow(self.pdv, sd.dss[pick], sd.cursors[pick], sd.slots[pick]);
            try self.stampObs(sd.dss[pick]);
            sd.cursors[pick] += 1;
            try self.setInFlags(sd, pick); // in= 1 on the contributing source (BUG-setinflag)
            // end= (BUG-setend) — the hasMore scan only pays when an end= var exists
            if (self.set_end_var != null) try self.setEndFlag(!setsHasMore(sd));
            return true;
        }
        // plain `set a b;` — read the sources end-to-end (concatenate).
        while (sd.di < sd.dss.len) {
            const ds = sd.dss[sd.di];
            if (sd.ri < ds.rowCount()) {
                // Language Reference: Concepts p.562 Step 2: at end-of-file of a source the PDV vars are
                // set to missing before the next source is read (BUG-setsourcereset).
                if (sd.last_contrib != sd.di) self.resetSetVars(sd);
                sd.last_contrib = sd.di;
                try io.loadRow(self.pdv, ds, sd.ri, sd.slots[sd.di]);
                try self.stampObs(ds);
                // BUG-modifystoptruncates: a sequential MODIFY records its
                // overrides BY MASTER ROW, so the row this iteration is editing
                // has to be known. Only the single-dataset MODIFY reaches
                // setsConsume with modify_by set — its BY sibling drives off the
                // transaction and never uses this driver.
                if (self.modify_by) |md| md.cur_m = if (md.src_pos.len > 0)
                    (if (sd.ri < md.src_pos.len) md.src_pos[sd.ri] - 1 else sd.ri)
                else
                    sd.ri;
                sd.ri += 1;
                try self.setInFlags(sd, sd.di); // in= 1 on the contributing source (BUG-setinflag)
                // 1 on the last obs (BUG-setend) — the hasMore scan only pays when an end= var exists
                if (self.set_end_var != null) try self.setEndFlag(!setsHasMore(sd));
                return true;
            }
            sd.di += 1;
            sd.ri = 0;
        }
        return false;
    }

    /// Language Reference: Concepts p.562 Step 2 / p.566 Step 1: when the contributing source changes
    /// (concatenate: end-of-file of a source; interleave: a new data set OR a new
    /// BY group) the SET variables in the PDV go back to missing — a value from
    /// one source must never bleed onto another source's rows
    /// (BUG-setsourcereset). The retained-list registration stays: SET vars ARE
    /// retained WITHIN a source, and the ExtraSet `if _n_=1 then set` case needs
    /// it (BUG-setvarretain) — this reset narrows that retain to per-source.
    fn resetSetVars(self: *Executor, sd: *const SetState) void {
        for (sd.slots) |slots| {
            self.resetPdvSlots(slots);
        }
    }

    /// Reset one source's PDV cells to missing by slot — the per-read half of
    /// the BUG-prefixmergewipe move for MERGE/UPDATE/MODIFY (their columns are
    /// retained across the iteration top now, Language Reference: Concepts p.495 step 5, so the wipe
    /// they relied on lives at the read instead).
    fn resetPdvSlots(self: *Executor, slots: []const usize) void {
        for (slots) |slot| {
            const v = &self.pdv.vars.items[slot];
            v.value = missingOf(v.type);
        }
    }

    /// DOWLOOP-impl: the DOW SET's read, fired at the SET node on each DO-loop
    /// iteration. SAS 9.4: the inner SET reads the NEXT obs, and BY first./last.
    /// are computed here (so `do until(last.grp)` can terminate the group). EOF at
    /// the inner SET ends the DATA step at once — .stop, current obs not output.
    fn dowRead(self: *Executor) Error!Flow {
        const d = self.driver_ptr orelse return .normal;
        switch (d.*) {
            .sets => |*sd| {
                if (!try self.setsConsume(sd)) return .stop;
                if (self.by_vars) |bys| try self.applyBy(d, bys);
                return .normal;
            },
            else => return .normal,
        }
    }

    /// The BY column indices of `bys` in `ds`, or null (error reported) when a
    /// BY var is absent from the source: the absent key would read all-missing
    /// and silently garble the match — its rows emit first with everything else
    /// missing, exit 0. SAS hard-errors instead (BUG-mergebymissing /
    /// CLIN-failloud). Shared by MERGE, SET-BY interleave, and UPDATE.
    fn byColsOf(self: *Executor, ds: *Dataset, bys: []const []const u8) Error!?[]const ?usize {
        const cols = try self.arena.alloc(?usize, bys.len);
        for (bys, 0..) |bv, j| {
            cols[j] = ds.indexOf(bv) orelse {
                self.diags.report(.err, 0, "BY variable {s} is not on input data set {s}", .{ bv, ds.name }) catch {};
                return null;
            };
        }
        return cols;
    }

    // ── match-merge ──────────────────────────────────────────────────────
    fn buildMerge(self: *Executor, names: []const []const u8) Error!Driver {
        var list: std.ArrayList(*Dataset) = .empty;
        var invars: std.ArrayList(?[]const u8) = .empty;
        for (names) |name| {
            if (try self.resolveDataset(name, true, null)) |ds| {
                // a WHERE statement filters EVERY merge input, as in SAS
                // (BUG-wheremerge: it silently read unfiltered) — applied by
                // resolveDataset BEFORE firstobs=/obs= (BUG-wherestmtobsorder)
                try list.append(self.arena, ds);
                const iv = try self.inVarOf(name);
                try invars.append(self.arena, iv);
                if (iv) |v| try self.drops.append(self.arena, v); // in= flags are temporary
            } else {
                try self.diags.warn(0, "dataset {s} not found; MERGE skipped", .{name});
            }
        }
        const dss = list.items;

        // Pre-declare every column of every source into the PDV up front, in
        // merge order (SAS builds the PDV from all sources at compile time). This
        // is what fixes BUG-mergecols: the output schema is seeded from the PDV at
        // the first write, so a dataset absent from the first BY group would
        // otherwise contribute no columns and lose its variables everywhere.
        for (dss) |ds| {
            for (ds.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
            // BUG-prefixmergewipe: Language Reference: Concepts p.495 step 5 — MERGE vars are NOT reset
            // to missing at the top of the iteration, so retain them like SET's;
            // the per-read reset in mergeNext keeps an absent source's columns
            // missing for the groups it doesn't contribute to.
            for (ds.columns.items) |c| try self.retained.append(self.arena, c.name);
        }

        const bys = self.by_vars orelse &.{}; // no BY → one group = positional 1:1 merge
        // SAS restriction: NOTSORTED is not valid with MERGE — a match-merge
        // needs sorted groups. Fail loud rather than silently mis-group.
        if (self.by_notsorted and bys.len > 0) {
            self.diags.report(.err, 0, "BY NOTSORTED is not valid with the MERGE statement", .{}) catch {};
            return .{ .once = true }; // spent driver: no iterations, no output
        }
        const by_cols = try self.arena.alloc([]const ?usize, dss.len);
        for (dss, 0..) |ds, d| {
            by_cols[d] = (try self.byColsOf(ds, bys)) orelse return .{ .once = true }; // spent driver: no iterations, no output
        }
        // BUG-mergebyvarlen: the output width of each char BY var (seedInputColumns
        // already carried it, first-source-wins) is the length SAS truncates every
        // source's value to before grouping. 0 for numeric / no declared width.
        const by_len = try self.arena.alloc(usize, bys.len);
        for (bys, 0..) |bv, j| by_len[j] = if (self.pdv.indexOf(bv)) |i|
            (if (self.pdv.vars.items[i].type == .char) self.pdv.vars.items[i].len else 0)
        else
            0;
        return .{ .merge = .{
            .dss = dss,
            .by_cols = by_cols,
            .by_len = by_len,
            .cur = try zeros(self.arena, dss.len),
            .group_start = try zeros(self.arena, dss.len),
            .group_count = try zeros(self.arena, dss.len),
            .in_vars = invars.items,
            .slots = try self.slotsOf(dss),
        } };
    }

    // ── UPDATE ────────────────────────────────────────────────────────────
    /// `update master trans; by k;` — build the driver. Pre-declares every column
    /// of both sources so the output carries the master's schema (plus any new
    /// transaction columns), and precomputes the BY column indices per source.
    fn buildUpdate(self: *Executor, names: []const []const u8) Error!Driver {
        // a WHERE statement filters both UPDATE inputs, as MERGE/SET (BUG-wheremerge);
        // resolveDataset(…, true) filters BEFORE firstobs=/obs= (BUG-wherestmtobsorder)
        const master = if (names.len > 0) if (try self.resolveDataset(names[0], true, null)) |d| d else null else null;
        const trans = if (names.len > 1) if (try self.resolveDataset(names[1], true, null)) |d| d else null else null;
        if (master == null or trans == null) {
            try self.diags.warn(0, "UPDATE needs a master and a transaction dataset", .{});
            return .{ .once = false };
        }
        // PDV schema: master columns first, then any transaction-only columns.
        for (master.?.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
        for (trans.?.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
        // BUG-prefixmergewipe: retain like SET's (Language Reference: Concepts p.495 step 5 names
        // UPDATE explicitly); the per-read reset in updateNext does the wipe
        // the top-of-iteration reset used to do.
        for (master.?.columns.items) |c| try self.retained.append(self.arena, c.name);
        for (trans.?.columns.items) |c| try self.retained.append(self.arena, c.name);

        const bys = self.by_vars orelse &.{};
        // SAS 9.4 requires BY on UPDATE (and on MODIFY with a transaction
        // dataset, which shares this driver): without it every row collapsed
        // into one artificial group and transactions applied positionally —
        // silent-wrong output on a common user error (BUG-updatenoby).
        if (bys.len == 0) {
            self.diags.report(.err, 0, "The BY statement is required for the UPDATE statement", .{}) catch {};
            return .{ .once = true }; // spent driver: no iterations, no output
        }
        // SAS restriction: NOTSORTED is not valid with UPDATE (same as MERGE).
        if (self.by_notsorted and bys.len > 0) {
            self.diags.report(.err, 0, "BY NOTSORTED is not valid with the UPDATE statement", .{}) catch {};
            return .{ .once = true }; // spent driver: no iterations, no output
        }
        const m_by = (try self.byColsOf(master.?, bys)) orelse return .{ .once = true }; // spent driver: no iterations, no output
        const t_by = (try self.byColsOf(trans.?, bys)) orelse return .{ .once = true }; // spent driver: no iterations, no output
        return .{ .update = .{ .master = master.?, .trans = trans.?, .m_by = m_by, .t_by = t_by, .m_slots = try io.columnSlots(self.pdv, master.?), .t_slots = try io.columnSlots(self.pdv, trans.?) } };
    }

    /// Load one UPDATE output observation. Source columns were reset to missing
    /// at the top of this call (BUG-prefixmergewipe — the top-of-iteration reset
    /// no longer wipes retained UPDATE vars, Language Reference: Concepts p.495 step 5), so a master
    /// obs is loaded whole, then matching transaction obs are applied
    /// (non-missing overwrites); a transaction-only key becomes a new obs.
    fn updateNext(self: *Executor, u: *UpdateState) Error!bool {
        const m_left = u.mi < u.master.rowCount();
        const t_left = u.ti < u.trans.rowCount();
        if (!m_left and !t_left) return false;
        // Per-read reset (moved here from the top-of-iteration loop, which the
        // pre-read prefix made user-visible): a master-absent group's master
        // cols and this group's unapplied transaction cols stay missing.
        self.resetPdvSlots(u.m_slots);
        self.resetPdvSlots(u.t_slots);

        // The group to emit comes from whichever source is not past its key; when
        // both remain, the smaller BY tuple wins (a tie is a master group + updates).
        var use_master = m_left;
        if (m_left and t_left) {
            const mt = try self.byTupleOfSet(u.master, u.mi, u.m_by);
            const tt = try self.byTupleOfSet(u.trans, u.ti, u.t_by);
            use_master = self.cmpBy(mt, tt) != .gt; // master <= trans → master group
        }

        const gkey = if (use_master)
            try self.byTupleOfSet(u.master, u.mi, u.m_by)
        else
            try self.byTupleOfSet(u.trans, u.ti, u.t_by);

        // Sorted-input invariant, as in mergeNext/SET-BY: a backwards group key
        // means an unsorted source — fail loud, don't silently mis-apply
        // transactions (BUG-setbyunsorted).
        if (u.prev_g) |pg| if (self.cmpBy(gkey, pg) == .lt) {
            self.diags.report(.err, 0, "BY variables are not properly sorted", .{}) catch {};
            return false;
        };
        // first.<by k> turns on from the level where this group's key first
        // differs from the previous group's (BUG-updatefirstlast, as mergeNext).
        const first_level = if (u.prev_g) |pg| changeLevel(gkey, pg) else 0;
        u.prev_g = gkey;

        if (use_master) {
            try io.loadRow(self.pdv, u.master, u.mi, u.m_slots);
            try self.stampObs(u.master);
            u.mi += 1;
        }
        // (MODIFY no longer routes here — it is transaction-driven, see
        // modifyNext; the no-match _DSENMR/_DSEMTR flagging lives there.)
        // Apply every transaction obs sharing this key, in order (cumulative).
        while (u.ti < u.trans.rowCount() and
            cmpTuple(try self.byTupleOfSet(u.trans, u.ti, u.t_by), gkey) == .eq)
        {
            try self.applyTrans(u.trans, u.ti);
            u.ti += 1;
        }

        // first./last. BY flags (BUG-updatefirstlast): UPDATE emits ONE obs per
        // BY group, so each obs is its group's first AND last — gated per level
        // by where the key changes vs the neighbor groups (as mergeNext 91d30bd;
        // duplicate master keys yield equal neighbors → both flags 0, like SAS).
        const nby = u.m_by.len;
        if (nby > 0 and self.first_names.len == nby) {
            // next group's key: cursors are already past this group, so it is the
            // smaller of the two sources' current tuples (none left → all-last).
            var last_level: usize = 0;
            const mt = if (u.mi < u.master.rowCount()) try self.byTupleOfSet(u.master, u.mi, u.m_by) else null;
            const tt = if (u.ti < u.trans.rowCount()) try self.byTupleOfSet(u.trans, u.ti, u.t_by) else null;
            const nxt = if (mt != null and tt != null)
                (if (self.cmpBy(tt.?, mt.?) == .lt) tt.? else mt.?)
            else
                mt orelse tt;
            if (nxt) |nx| last_level = changeLevel(gkey, nx);
            for (0..nby) |k| {
                try self.pdv.set(self.first_names[k], .{ .num = if (k >= first_level) 1 else 0 });
                try self.pdv.set(self.last_names[k], .{ .num = if (k >= last_level) 1 else 0 });
            }
        }
        // UPDATE `end=e` (BUG-mergeupdateend): 1 when this group drained both
        // sources — cursors sit past the last master AND last transaction row.
        if (self.set_end_var != null)
            try self.setEndFlag(u.mi >= u.master.rowCount() and u.ti >= u.trans.rowCount());
        return true;
    }

    /// Overwrite the PDV with dataset `ds`'s row `row`, skipping missing values
    /// (SAS UPDATE default: a missing transaction value keeps the master's).
    fn applyTrans(self: *Executor, ds: *Dataset, row: usize) Error!void {
        for (ds.columns.items, 0..) |c, ci| {
            const v = ds.row(row)[ci];
            // GAP-updatemode: NOMISSINGCHECK applies EVERY value — an ordinary
            // missing overwrites the master too (special missings apply either
            // way, per isUpdateMissing's doc). Default MISSINGCHECK unchanged.
            if (self.update_nomissingcheck or !isUpdateMissing(v)) try self.pdv.set(c.name, v);
        }
    }

    // ── MODIFY master trans; BY k (transaction-driven) ─────────────────────
    fn buildModify(self: *Executor, names: []const []const u8) Error!Driver {
        // a WHERE statement filters both MODIFY inputs, as UPDATE (BUG-wheremerge);
        // resolveDataset(…, true) filters BEFORE firstobs=/obs= (BUG-wherestmtobsorder).
        // GAP-modifywherestmt: and the master's surviving positions are CAPTURED —
        // filter-then-match (Statements ref printed p.360: "SAS selects observations
        // from each input data set before it combines them"; printed p.245: "uses
        // dynamic WHERE processing to locate the matching observation"). The
        // scan/match below reads the FILTERED copy while the commit re-emits the
        // UNFILTERED member through src_pos — a master row the WHERE hid is never
        // matched AND never destroyed. Before this, `modify m t; by k; where k>1;`
        // (and its where= option twin) flushed the filtered copy: the hidden rows
        // were GONE at rc 0, the data-loss shape the rc-2 refusal guarded.
        var msrc: ?[]const usize = null;
        const master = if (try self.resolveDataset(names[0], true, &msrc)) |d| d else null;
        const trans = if (names.len > 1) if (try self.resolveDataset(names[1], true, null)) |d| d else null else null;
        if (master == null or trans == null) {
            try self.diags.warn(0, "MODIFY needs a master and a transaction dataset", .{});
            return .{ .once = true }; // spent driver: no iterations, no output
        }
        // PDV schema: master columns first, then any transaction-only columns
        // (SAS builds the PDV from all sources at compile time).
        for (master.?.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
        for (trans.?.columns.items) |c| _ = try self.pdv.define(c.name, c.type);
        // BUG-prefixmergewipe: retain like SET's (Language Reference: Concepts p.495 step 5 names
        // MODIFY explicitly); the per-read reset in modifyNext does the wipe
        // the top-of-iteration reset used to do.
        for (master.?.columns.items) |c| try self.retained.append(self.arena, c.name);
        for (trans.?.columns.items) |c| try self.retained.append(self.arena, c.name);
        const bys = self.by_vars orelse &.{};
        // MODIFY with a transaction dataset requires BY (same guard UPDATE has —
        // BUG-updatenoby; message shared with the nested-source path).
        if (bys.len == 0) {
            self.diags.report(.err, 0, "The BY statement is required for the UPDATE statement", .{}) catch {};
            return .{ .once = true }; // spent driver: no iterations, no output
        }
        // NOTE: no sorted-input requirement and no NOTSORTED rejection — "The
        // MODIFY statement does not require sorted files" (Language Reference: Concepts p.585/p.587
        // Notes, p.588 Table 23.3); the match below is a key lookup, not a merge.
        const m_by = (try self.byColsOf(master.?, bys)) orelse return .{ .once = true }; // spent driver: no iterations, no output
        const t_by = (try self.byColsOf(trans.?, bys)) orelse return .{ .once = true }; // spent driver: no iterations, no output
        // A row-filtered master commits against the UNFILTERED member (the
        // single-dataset path's invariant): scan the filtered copy, flush the
        // member. Positions existing at all IS the filter detector — column-only
        // options (keep=/drop=/rename=) keep today's resolved-copy commit.
        const member = self.lib.find(splitSourceRef(names[0]).name);
        const use_member = msrc != null and member != null and member.? != master.?;
        const flush_base = if (use_member) member.? else master.?;
        return .{ .modify = .{
            .master = flush_base,
            .trans = trans.?,
            .m_by = m_by,
            .t_by = t_by,
            .m_slots = try io.columnSlots(self.pdv, master.?),
            .t_slots = try io.columnSlots(self.pdv, trans.?),
            .src_pos = if (use_member) msrc.? else &.{},
            .scan = if (use_member) master.? else null,
            .flush_slots = try io.columnSlots(self.pdv, flush_base),
        } };
    }

    /// Load one MODIFY-BY iteration = one TRANSACTION observation
    /// (BUG-modifybymasterdriven). A matched key loads the master obs and
    /// overlays the WHOLE transaction obs (p.596: REPLACE "replac[es] its
    /// observation with the observation from the transaction data set" —
    /// UPDATE's MISSINGCHECK skip has no MODIFY analog); an unmatched key flags
    /// _DSENMR (first) or _DSEMTR (consecutive repeat, p.599 Table 23.4).
    fn modifyNext(self: *Executor, md: *ModifyState) Error!bool {
        if (md.ti >= md.trans.rowCount()) {
            try self.modifyFlush(md);
            return false;
        }
        // Per-read reset (moved here from the top-of-iteration loop —
        // BUG-prefixmergewipe): an unmatched iteration's master vars stay
        // missing, a matched one overlays master then transaction below.
        self.resetPdvSlots(md.m_slots);
        self.resetPdvSlots(md.t_slots);
        // GAP-modifywherestmt: match against the FILTERED copy when a row filter
        // (WHERE statement / where= / obs-window) selected the master —
        // filter-then-match, p.360/p.245; src_pos then maps a scan row back to
        // its physical master row for the commit. scan == master when unfiltered.
        const mscan = md.scan orelse md.master;
        const tt = try self.byTupleOfSet(md.trans, md.ti, md.t_by);
        const same_key = if (md.prev_key) |pk| self.cmpBy(tt, pk) == .eq else false;
        // Locate the master obs. Duplicate BY values match in order (p.588 Table
        // 23.3 allows them in BOTH sources): a repeated key continues the scan
        // past the last match; a new key scans from the top — MODIFY requires no
        // sorted input (p.585 Note). ponytail: O(master × transaction) worst
        // case (unsorted master); build an index only if real studies feel it.
        var found: ?usize = null;
        var r: usize = if (same_key and md.prev_match) md.m_hint else 0;
        while (r < mscan.rowCount()) : (r += 1) {
            if (rowKeyEq(mscan, r, md.m_by, tt)) {
                found = r;
                break;
            }
        }
        const trow = md.trans.row(md.ti);
        if (found) |mr| {
            md.cur_m = if (md.src_pos.len > 0)
                (if (mr < md.src_pos.len) md.src_pos[mr] - 1 else mr) // scan row → PHYSICAL master row
            else
                mr;
            md.m_hint = mr + 1; // scan coordinates: a repeated key continues here
            try io.loadRow(self.pdv, mscan, mr, md.m_slots);
            try self.stampObs(mscan);
            for (md.trans.columns.items, 0..) |c, ci| try self.pdv.set(c.name, trow[ci]);
            self.modify_nomatch = .none;
        } else {
            md.cur_m = null;
            // master vars stay missing (per-read reset above); load the transaction
            // obs so the program can build + OUTPUT the new row (p.601 idiom).
            for (md.trans.columns.items, 0..) |c, ci| try self.pdv.set(c.name, trow[ci]);
            self.modify_nomatch = if (same_key and !md.prev_match) .subsequent else .first;
        }
        // first./last. over the TRANSACTION stream (the iteration stream), same
        // level-gating as updateNext.
        const nby = md.t_by.len;
        if (nby > 0 and self.first_names.len == nby) {
            const first_level = if (md.prev_key) |pk| changeLevel(tt, pk) else 0;
            var last_level: usize = 0;
            if (md.ti + 1 < md.trans.rowCount()) {
                last_level = changeLevel(tt, try self.byTupleOfSet(md.trans, md.ti + 1, md.t_by));
            }
            for (0..nby) |k| {
                try self.pdv.set(self.first_names[k], .{ .num = if (k >= first_level) 1 else 0 });
                try self.pdv.set(self.last_names[k], .{ .num = if (k >= last_level) 1 else 0 });
            }
        }
        md.prev_match = found != null;
        md.prev_key = tt;
        md.ti += 1;
        return true;
    }

    /// The rebuild-commit (opensas commits a MODIFY by re-emitting the master,
    /// io.putInput replaces it): re-emit the master IN ORIGINAL ORDER — the obs
    /// the transaction-driven driver never visited go out untouched (SAS's
    /// in-place guarantee), recorded REPLACE overrides replace their row,
    /// REMOVE tombstones drop theirs — then the OUTPUT-added rows (appends land
    /// at the END of an in-place modify). Idempotent; also called post-loop so
    /// a mid-step `stop;` still leaves a complete master.
    fn modifyFlush(self: *Executor, md: *ModifyState) Error!void {
        if (md.flushed) return;
        md.flushed = true;
        var i: usize = 0;
        while (i < md.master.rowCount()) : (i += 1) {
            if (md.repl.get(i)) |maybe| {
                if (maybe) |row| {
                    try self.loadCapturedRow(row);
                    try self.outputAll();
                } // null = REMOVEd — absent from the rebuilt master
            } else {
                // untouched master obs: clear ALL iteration state first — the
                // transaction-only PDV vars must read missing, not the last
                // transaction's stale values (in-place = byte-identical to input).
                for (self.pdv.vars.items) |*v| v.value = missingOf(v.type);
                try io.loadRow(self.pdv, md.master, i, if (md.flush_slots.len > 0) md.flush_slots else md.m_slots);
                try self.outputAll();
            }
        }
        for (md.appends.items) |row| {
            try self.loadCapturedRow(row);
            try self.outputAll();
        }
    }

    /// MODIFY-BY REPLACE (explicit or implicit): record the current PDV as the
    /// rebuilt obs for THIS iteration's master row (cur_m). Null cur_m is
    /// unreachable — a no-match iteration sets obs_handled at the loop top.
    fn modifyReplace(self: *Executor, md: *ModifyState) Error!void {
        const r = md.cur_m orelse return;
        try md.repl.put(self.arena, r, try self.capturePdvRow());
    }

    /// A full copy of the current PDV values, char cells duped into the RUN
    /// arena (the per-iteration scratch is recycled at the row boundary).
    fn capturePdvRow(self: *Executor) Error![]Value {
        const vars = self.pdv.vars.items;
        const row = try self.arena.alloc(Value, vars.len);
        for (vars, 0..) |v, j| {
            row[j] = if (v.value == .str) .{ .str = try self.arena.dupe(u8, v.value.str) } else v.value;
        }
        return row;
    }

    /// Restore a captured row into the PDV (flush time): everything not captured
    /// goes missing first so no stale iteration state leaks into the rebuild.
    fn loadCapturedRow(self: *Executor, row: []Value) Error!void {
        for (self.pdv.vars.items) |*v| v.value = missingOf(v.type);
        for (row, 0..) |val, j| try self.pdv.setAt(j, val);
    }

    /// A `where expr;` STATEMENT filters the input BEFORE the step sees rows, so
    /// end=/first./last. reflect the FILTERED stream — real SAS engine WHERE. The
    /// old subsetting-if desugar mistimed `set … end=last; where c; if last then
    /// …` whenever the physically-last row failed the predicate: the flag row was
    /// discarded and the `if last` never ran (bit a real XPT-export
    /// macro's SYMPUT('nb') — GAP-vtabledisk fallout). Rows are evaluated on a THROWAWAY
    /// PDV (io.applyWhere's where=-option pattern), never the live one. Applied
    /// to every SET/MERGE/UPDATE source that does NOT carry its own where=
    /// option (BUG-wheremerge; the option takes precedence, Language Reference: Concepts p.215).
    /// NOBS= stays the PHYSICAL count (SAS reports unfiltered).
    /// `obs_out` (GAP-modifywherestmt): each surviving row's 1-based SOURCE
    /// position, composed through any earlier filter's list exactly like
    /// io.applyObsSlice — the MODIFY commit's filtered-row → master-row map.
    fn applyWhereStmt(self: *Executor, src: *Dataset, obs_out: ?*?[]const usize) Error!*Dataset {
        const e = self.where_expr orelse return src;
        const a = self.arena;
        // A WHERE variable must exist on the source — eval maps an unknown name
        // to missing, which silently filtered EVERY row; SAS errors
        // "Variable X is not on file" (BUG-wherevar). Error reported inside;
        // the empty filtered result then emits nothing, like a missing SET file.
        if (!try self.checkWhereVars(e, src)) {
            if (obs_out) |oo| oo.* = &.{};
            const empty = try a.create(Dataset);
            empty.* = Dataset.init(a, src.name);
            try empty.columns.appendSlice(a, src.columns.items);
            return empty;
        }
        var pdv = Pdv.init(a);
        // BUG-wherefunc: the PDV is throwaway, the DIAGS and CALL_FN must be the
        // REAL ones (borrowed from the live evaluator) — a junk sink with no
        // dispatch made `where upcase(x)="Y"` silently misfilter: the function
        // reported "not supported" into the discarded sink and returned missing,
        // so char compares passed EVERY row and numeric compares dropped all.
        var ev: eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = self.diags, .call_fn = self.ev.call_fn };
        const out = try a.create(Dataset);
        out.* = Dataset.init(a, src.name);
        try out.columns.appendSlice(a, src.columns.items);
        var kept_obs: std.ArrayList(usize) = .empty;
        for (src.rows.items, 0..) |row, ri| {
            for (src.columns.items, 0..) |col, j| {
                _ = try pdv.define(col.name, col.type);
                try pdv.set(col.name, row[j]);
            }
            // WHERE-context truthiness (Language Reference: Concepts p.216): a bare char var means
            // non-blank — whereTruthy, NOT the IF rule (BUG-wherebarechar).
            if ((try ev.eval(e)).whereTruthy()) {
                try out.rows.append(a, row);
                if (obs_out) |oo| try kept_obs.append(a, if (oo.*) |l| l[ri] else ri + 1);
            }
        }
        if (obs_out) |oo| oo.* = kept_obs.items;
        return out;
    }

    /// Every variable a WHERE expression references must be a column of the
    /// source dataset (BUG-wherevar) — fail loud like SAS, don't filter to zero.
    /// Reports the error itself; false = at least one variable is not on file.
    fn checkWhereVars(self: *Executor, e: *const ast.Expr, src: *Dataset) Error!bool {
        switch (e.*) {
            .variable => |name| {
                for (src.columns.items) |c| if (std.ascii.eqlIgnoreCase(c.name, name)) return true;
                self.diags.report(.err, 0, "Variable {s} is not on file {s}", .{ name, src.name }) catch {};
                return false;
            },
            .unary => |u| return self.checkWhereVars(u.operand, src),
            .binary => |b| return try self.checkWhereVars(b.lhs, src) and try self.checkWhereVars(b.rhs, src),
            .call => |c| {
                for (c.args) |*arg| if (!try self.checkWhereVars(arg, src)) return false;
                return true;
            },
            .array_ref => |ar| return self.checkWhereVars(ar.index, src),
            .num, .str, .missing => return true,
        }
    }

    /// Resolve a `set`/`merge` source name, applying any encoded input dataset
    /// options (`src(keep=… drop=… rename=(…))`) to a private copy so the source
    /// dataset is unchanged. A plain name resolves straight from the Library.
    /// `where=`/`firstobs=`/`obs=` are applied by io.applyDatasetOptions.
    ///
    /// `where_first` (SET/MERGE/UPDATE drivers): DEFER the firstobs=/obs= slice,
    /// apply the DATA-step WHERE STATEMENT, THEN slice — so positions count
    /// WITHIN the WHERE-selected subset (BUG-wherestmtobsorder), mirroring the
    /// where= OPTION twin (whereobsorder). Callers that pass true must NOT also
    /// call applyWhereStmt (finishResolve already did). Non-driver callers
    /// (nobs=, column seeding, MODIFY, POINT=) pass false: slice inline, no
    /// statement filter — unchanged behavior.
    fn resolveDataset(self: *Executor, name: []const u8, where_first: bool, srcobs: ?*?[]const usize) Error!?*Dataset {
        // `sashelp.vtable` — the dictionary view of the current library's members,
        // built fresh so it reflects datasets created earlier this run. Any dataset
        // options (`(where=…)`) still apply; a `where` STATEMENT is filtered by the
        // step (BUG-xptcreat-novtable).
        const ref0 = splitSourceRef(name);
        const base = ref0.name;
        // `sashelp.vtable` / `sashelp.vcolumn` — dictionary views built fresh so they
        // reflect datasets created earlier this run (ISS-dictviews). Any dataset
        // options (`(where=…)`) still apply; a `where` STATEMENT is filtered by the
        // step (BUG-xptcreat-novtable).
        const view: ?*Dataset =
            if (std.ascii.eqlIgnoreCase(base, "sashelp.vtable"))
                try io.buildVtable(self.arena, self.lib.names.items, self.lib.sets.items)
            else if (std.ascii.eqlIgnoreCase(base, "sashelp.vcolumn"))
                try io.buildVcolumn(self.arena, self.lib.names.items, self.lib.sets.items)
            else
                null;
        if (view) |vt| {
            const phys = vt.rows.items.len; // pre-options PHYSICAL count (BUG-pointnobs)
            var toks: []const lex.Token = &.{};
            if (ref0.opts.len > 0) {
                toks = self.lexOpts(ref0.opts) catch |e|
                    return if (e == error.OutOfMemory) error.OutOfMemory else vt;
                try io.applyDatasetOptionsObs(self.arena, vt, toks, self.diags, true, where_first, srcobs, &.{}); // INPUT: DKRICOND=ERROR
            }
            return self.stampPhys(try self.finishResolve(vt, toks, where_first, srcobs), phys);
        }
        if (ref0.opts.len == 0) {
            const ds = self.lib.find(name) orelse return null;
            // No per-dataset options: the global `options obs=/firstobs=` still
            // bound the read (BUG-globalobs). Slice a COPY — the library dataset
            // must stay whole for later reads.
            if (!io.globalObsActive()) return self.stampPhys(try self.finishResolve(ds, &.{}, where_first, srcobs), ds.rowCount());
            const copy = try self.arena.create(Dataset);
            copy.* = Dataset.init(self.arena, ds.name);
            try copy.columns.appendSlice(self.arena, ds.columns.items);
            try copy.rows.appendSlice(self.arena, ds.rows.items);
            try io.applyDatasetOptionsObs(self.arena, copy, &.{}, self.diags, true, where_first, srcobs, &.{}); // INPUT
            return self.stampPhys(try self.finishResolve(copy, &.{}, where_first, srcobs), ds.rowCount());
        }
        const src = self.lib.find(ref0.name) orelse return null;
        const opts = ref0.opts;
        const copy = try self.arena.create(Dataset);
        copy.* = Dataset.init(self.arena, src.name);
        try copy.columns.appendSlice(self.arena, src.columns.items);
        try copy.rows.appendSlice(self.arena, src.rows.items);
        const toks = self.lexOpts(opts) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else copy;
        try io.applyDatasetOptionsObs(self.arena, copy, toks, self.diags, true, where_first, srcobs, &.{}); // INPUT: DKRICOND=ERROR (GH#71)
        return self.stampPhys(try self.finishResolve(copy, toks, where_first, srcobs), src.rowCount());
    }

    /// Record a resolved source's PHYSICAL (pre-slice, pre-filter) row count
    /// for NOBS= (BUG-pointnobs) and pass the source through.
    fn stampPhys(self: *Executor, ds: *Dataset, phys: usize) Error!*Dataset {
        try self.nobs_phys.put(self.arena, ds, phys);
        return ds;
    }

    /// The POINT= direct-access source (BUG-pointnobsbase): the PHYSICAL
    /// dataset, unsliced. NOBS= is the physical descriptor count (BUG-pointnobs,
    /// doc-finder-tick283 F2: FIRSTOBS=/OBS=/WHERE window the READ, not the
    /// descriptor), and POINT= is documented absolute direct access — so the two
    /// must share the PHYSICAL base, or the canonical `do i=1 to n; set d
    /// point=i nobs=n;` loop contradicts itself inside one step (NOBS= said 5,
    /// the range check said "has 2 observations", and the out-of-range ERROR
    /// killed the run — `options obs=N;` at the top killed every POINT= loop).
    /// obs=/firstobs= (and global `options obs=`) window a SEQUENTIAL read
    /// only; they do not apply to direct access. where= never reaches here:
    /// buildDriver's guard rejects it loud (BUG-pointwheredsopt — Statements
    /// ref p.335 forbids WHERE= with POINT= outright); the token drop below
    /// stays as belt-and-braces, identical to obs=/firstobs=. Column options
    /// (keep=/drop=/rename=) still apply to the copy that is read.
    fn resolvePointSource(self: *Executor, name: []const u8) Error!?*Dataset {
        if (std.mem.indexOfScalar(u8, name, '(') == null) {
            // dictionary views are built, not library-found — keep the general path
            if (std.ascii.eqlIgnoreCase(name, "sashelp.vtable") or std.ascii.eqlIgnoreCase(name, "sashelp.vcolumn"))
                return self.resolveDataset(name, false, null);
            return self.lib.find(name);
        }
        const ref = splitSourceRef(name);
        const base = ref.name;
        if (std.ascii.eqlIgnoreCase(base, "sashelp.vtable") or std.ascii.eqlIgnoreCase(base, "sashelp.vcolumn"))
            return self.resolveDataset(name, false, null);
        const src = self.lib.find(base) orelse return null;
        const toks = self.lexOpts(ref.opts) catch |e|
            return if (e == error.OutOfMemory) error.OutOfMemory else src;
        // Drop the row-windowing options from the list — they must not slice the
        // direct-access read. keep=/drop=/rename= stay. skip_obs_slice=true
        // covers the global `options obs=/firstobs=` defaults.
        var kept: std.ArrayList(lex.Token) = .empty;
        var i: usize = 0;
        while (i < toks.len) {
            if (toks[i].tag == .name and i + 1 < toks.len and toks[i + 1].tag == .eq and
                (eqi(toks[i].text, "where") or eqi(toks[i].text, "obs") or eqi(toks[i].text, "firstobs")))
            {
                i += 2;
                if (i < toks.len and toks[i].tag == .lparen) { // where=(expr) — skip the balanced group
                    var depth: usize = 1;
                    i += 1;
                    while (i < toks.len and depth > 0) : (i += 1) {
                        if (toks[i].tag == .lparen) depth += 1;
                        if (toks[i].tag == .rparen) depth -= 1;
                    }
                } else i += 1; // obs=N / firstobs=N — a single value token
                continue;
            }
            try kept.append(self.arena, toks[i]);
            i += 1;
        }
        if (kept.items.len == 0) return src;
        const copy = try self.arena.create(Dataset);
        copy.* = Dataset.init(self.arena, src.name);
        try copy.columns.appendSlice(self.arena, src.columns.items);
        try copy.rows.appendSlice(self.arena, src.rows.items);
        try io.applyDatasetOptionsObs(self.arena, copy, kept.items, self.diags, true, true, null, &.{}); // INPUT, no obs slice
        return copy;
    }

    /// NOBS= count of a resolved source: the PHYSICAL pre-slice count when
    /// resolveDataset recorded one (BUG-pointnobs — FIRSTOBS=/OBS= window the
    /// READ, they do not shrink the descriptor-level NOBS=), else rowCount.
    fn physNobs(self: *Executor, ds: *const Dataset) usize {
        return self.nobs_phys.get(ds) orelse ds.rowCount();
    }

    /// The where-then-slice tail of resolveDataset (BUG-wherestmtobsorder). When
    /// `where_first`, the firstobs=/obs= slice was deferred: apply the WHERE
    /// STATEMENT, then the slice, so positions count WITHIN the filtered subset.
    /// `opt_toks` carry the firstobs=/obs= tokens (empty for a plain name — the
    /// global range still applies). applyWhereStmt returns a fresh copy when a
    /// WHERE is in effect, so slicing it never touches the library dataset.
    fn finishResolve(self: *Executor, ds: *Dataset, opt_toks: []const lex.Token, where_first: bool, srcobs: ?*?[]const usize) Error!*Dataset {
        if (!where_first) return ds;
        // BUG-whereoptvsstmt (Language Reference: Concepts p.215): "in the DATA step, if a WHERE
        // statement and a WHERE= data set option apply to the same data set,
        // the data set option takes precedence." A source carrying its own
        // top-level where= IGNORES the WHERE statement (which still filters
        // the step's other sources) — opensas used to AND the two.
        const filtered = if (toksHaveWhereOpt(opt_toks)) ds else try self.applyWhereStmt(ds, srcobs);
        // BUG-modifywhereopt: this used to pass `null` and DISCARD the surviving
        // positions, so the mapping stopped composing the moment a WHERE statement
        // was in play. Threaded now, matching proc.zig's prepInput which carries one
        // `srcobs` across all three stages.
        try io.applyObsSlice(self.arena, filtered, opt_toks, true, srcobs);
        return filtered;
    }

    /// Re-lex an encoded option string; propagates OOM, else the caller decides.
    fn lexOpts(self: *Executor, opts: []const u8) ![]lex.Token {
        return lex.tokenize(self.arena, opts, self.diags);
    }

    /// True if the source's encoded options carry a top-level `where=` (a
    /// `rename=(where=x)` nested one level down does NOT count). With POINT=
    /// that combination is ILLEGAL (Statements ref p.335), never a filter to
    /// drop quietly.
    fn hasWhereOpt(self: *Executor, name: []const u8) Error!bool {
        return (try self.optPresent(name, &.{"where"})) != null;
    }

    /// True when the lexed option list carries a top-level `where=` — the same
    /// depth rule as optPresent (a `rename=(where=x)` one level down does NOT
    /// count), but over tokens the caller already lexed.
    fn toksHaveWhereOpt(toks: []const lex.Token) bool {
        var depth: usize = 0;
        for (toks, 0..) |tk, i| {
            switch (tk.tag) {
                .lparen => depth += 1,
                .rparen => depth -|= 1,
                .name => if (depth == 0 and i + 1 < toks.len and toks[i + 1].tag == .eq and eqi(tk.text, "where")) return true,
                else => {},
            }
        }
        return false;
    }

    /// The first of `wanted` present as a TOP-LEVEL `opt=` in the source's encoded
    /// options, or null. One scanner for both askers — the POINT=/WHERE= legality
    /// guard above and the MODIFY row-subset refusal below — so "top level" cannot
    /// come to mean two different things (BUG-modifymasteroptname).
    fn optPresent(self: *Executor, name: []const u8, wanted: []const []const u8) Error!?[]const u8 {
        const ref = splitSourceRef(name);
        if (ref.opts.len == 0) return null;
        const toks = self.lexOpts(ref.opts) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else null;
        var depth: usize = 0;
        for (toks, 0..) |tk, i| {
            switch (tk.tag) {
                .lparen => depth += 1,
                .rparen => depth -|= 1,
                .name => if (depth == 0 and i + 1 < toks.len and toks[i + 1].tag == .eq) {
                    for (wanted) |w| if (eqi(tk.text, w)) return w;
                },
                else => {},
            }
        }
        return null;
    }

    /// The `in=` variable of a source's options (`src(… in=x)`), or null.
    fn inVarOf(self: *Executor, name: []const u8) Error!?[]const u8 {
        const ref = splitSourceRef(name);
        if (ref.opts.len == 0) return null;
        const toks = self.lexOpts(ref.opts) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else null;
        var i: usize = 0;
        while (i + 2 < toks.len) : (i += 1) {
            if (toks[i].tag == .name and eqi(toks[i].text, "in") and toks[i + 1].tag == .eq and toks[i + 2].tag == .name)
                return toks[i + 2].text;
        }
        return null;
    }

    /// Emit one merged observation; false when every source is spent.
    fn mergeNext(self: *Executor, md: *MergeState) Error!bool {
        if (md.dss.len == 0) return false;
        // Per-read reset (moved here from the top-of-iteration loop —
        // BUG-prefixmergewipe, Language Reference: Concepts p.495 step 5 keeps MERGE vars retained
        // across the iteration top): a source absent from this group loads
        // nothing below, so its columns stay missing exactly as before.
        for (md.slots) |ss| self.resetPdvSlots(ss);
        const nby = md.by_cols[0].len;

        if (!md.active or md.iter >= md.iters) {
            if (md.active) {
                for (md.dss, 0..) |_, d| md.cur[d] = md.group_start[d] + md.group_count[d];
            }
            var any = false;
            for (md.dss, 0..) |ds, d| {
                if (md.cur[d] < ds.rowCount()) any = true;
            }
            if (!any) return false;

            // group key G = the smallest BY tuple among sources still holding rows
            const g = try self.arena.alloc(Value, nby);
            const tmp = try self.arena.alloc(Value, nby);
            var have_g = false;
            for (md.dss, 0..) |ds, d| {
                if (md.cur[d] >= ds.rowCount()) continue;
                byTupleInto(md, d, md.cur[d], tmp);
                if (!have_g or self.cmpBy(tmp, g) == .lt) {
                    @memcpy(g, tmp);
                    have_g = true;
                }
            }

            // Sorted-input invariant: each group's BY key is >= the previous group's.
            // If it went backwards, a source is out of order — SAS errors "BY variables
            // are not properly sorted" rather than silently dropping the out-of-order
            // rows (which `if a and b` then filters away). Fail loud, don't truncate
            // (BUG-mergeunsorted / CLIN-failloud).
            if (md.prev_g) |pg| if (self.cmpBy(g, pg) == .lt) {
                self.diags.report(.err, 0, "BY variables are not properly sorted", .{}) catch {};
                return false;
            };
            // first.<by k> turns on from the level where this group's key first
            // differs from the previous group's (BUG-mergefirstlast).
            md.first_level = if (md.prev_g) |pg| changeLevel(g, pg) else 0;
            md.prev_g = g;

            var iters: usize = 0;
            for (md.dss, 0..) |ds, d| {
                md.group_start[d] = md.cur[d];
                var cnt: usize = 0;
                var r = md.cur[d];
                while (r < ds.rowCount()) : (r += 1) {
                    byTupleInto(md, d, r, tmp);
                    if (cmpTuple(tmp, g) != .eq) break;
                    cnt += 1;
                }
                md.group_count[d] = cnt;
                if (cnt > iters) iters = cnt;
            }
            md.iters = iters;
            md.iter = 0;
            md.active = true;

            // last.<by k> turns on from the level where the NEXT group's key (the
            // smallest tuple just past each source's current group) differs; no
            // next group → every level (BUG-mergefirstlast).
            const nxt = try self.arena.alloc(Value, nby);
            var have_n = false;
            for (md.dss, 0..) |ds, d| {
                const r = md.group_start[d] + md.group_count[d];
                if (r >= ds.rowCount()) continue;
                byTupleInto(md, d, r, tmp);
                if (!have_n or self.cmpBy(tmp, nxt) == .lt) {
                    @memcpy(nxt, tmp);
                    have_n = true;
                }
            }
            md.last_level = if (have_n) changeLevel(g, nxt) else 0;
        }

        // ISS-mergereset: within a BY group the sources can have unequal row
        // counts. A source exhausted this iteration (iter >= its count) stops
        // contributing FRESH values, but SAS holds its last row's values for the
        // rest of the group. The trap: a var COMMON to an exhausted and a live
        // source must take the LIVE source's fresh value, not the exhausted one's
        // held value. The old `@min(iter, count-1)` loaded the exhausted source's
        // LAST row in merge order, so a common var kept the stale value (e.g.
        // visitdy=22 held from the short source instead of `.` from the live one).
        // Fix: load exhausted sources' last row FIRST, then live sources at `iter`
        // — live values overwrite common columns; a column UNIQUE to an exhausted
        // source survives (nothing live rewrites it). Sources absent from the group
        // (count==0) load nothing and the per-read reset above leaves them missing.
        //
        // BUT only for a match-merge (nby>0). A one-to-one merge with NO BY
        // collapses everything into one group, so an exhausted short source would
        // hold its LAST row across the tail — wrong: Language Reference: Concepts p.110 says a no-BY merge
        // source, once exhausted, has its vars go MISSING (BUG-mergenobymissing).
        // The per-iter reset already left them missing, so just skip the hold.
        if (nby > 0) for (md.dss, 0..) |_, d| {
            if (md.group_count[d] > 0 and md.iter >= md.group_count[d]) {
                try io.loadRow(self.pdv, md.dss[d], md.group_start[d] + md.group_count[d] - 1, md.slots[d]);
                try self.stampObs(md.dss[d]);
            }
        };
        for (md.dss, 0..) |_, d| {
            if (md.iter < md.group_count[d]) {
                try io.loadRow(self.pdv, md.dss[d], md.group_start[d] + md.iter, md.slots[d]);
                try self.stampObs(md.dss[d]);
            }
            // `in=` flag: for a BY-merge, 1 when this source contributed to the
            // current BY group (holds past in-group exhaustion). A no-BY merge
            // collapses everything into ONE group, so gate per-iteration instead:
            // past the shorter source's exhaustion the flag drops to 0
            // (BUG-mergenobyinflag).
            const in_flag: f64 = if (if (nby > 0) md.group_count[d] > 0 else md.iter < md.group_count[d]) 1 else 0;
            if (d < md.in_vars.len) if (md.in_vars[d]) |iv|
                try self.pdv.set(iv, .{ .num = in_flag });
        }
        // first./last. BY flags — MERGE emits one obs per group iteration, so
        // "first" is the group's first iteration and "last" its final one, gated
        // per level by where the key changed vs the neighbor groups
        // (BUG-mergefirstlast; SET has its own peek-based applyBy).
        if (nby > 0 and self.first_names.len == nby) {
            const is_first = md.iter == 0;
            const is_last = md.iter + 1 == md.iters;
            for (0..nby) |k| {
                try self.pdv.set(self.first_names[k], .{ .num = if (is_first and k >= md.first_level) 1 else 0 });
                try self.pdv.set(self.last_names[k], .{ .num = if (is_last and k >= md.last_level) 1 else 0 });
            }
        }
        // MERGE `end=e` (BUG-mergeupdateend): 1 on the last obs the merge emits —
        // the final iteration of the final BY group (no rows past any group end).
        if (self.set_end_var != null) {
            var more = md.iter + 1 < md.iters;
            if (!more) for (md.dss, 0..) |ds, d| {
                if (md.group_start[d] + md.group_count[d] < ds.rowCount()) {
                    more = true;
                    break;
                }
            };
            try self.setEndFlag(!more);
        }
        md.iter += 1;
        return true;
    }

    // ── statements ───────────────────────────────────────────────────────

    /// Run the flattened step body (compileProgram) with a program counter.
    /// GOTO/LINK are absolute jumps; LINK pushes the return PC and a later RETURN
    /// pops it (an unmatched RETURN is the ordinary "output + top of step"). Since
    /// DO/IF bodies are inlined into the one op stream, a label at any nesting
    /// depth is reachable and a LINK return lands on the op right after the call
    /// site — even mid-loop (BUG-controlflownesting). Other flows (DELETE/STOP/…)
    /// propagate to the iteration loop.
    /// Run the flattened op stream over [first, end) — the whole stream in an
    /// unsplit step, or one half of the BUG-setstmtorder split around the
    /// driving read. Leaving the range at the stack's BASE depth means a GOTO
    /// jumped OUT of the range, crossing the driving read statement — SAS would
    /// skip or re-run the read, which the per-iteration split cannot model. Fail
    /// LOUD (D-002) instead of silently dropping the jump target. A LINK is
    /// exempt (BUG-linkacrossset): it always RETURNs to the statement after the
    /// LINK (Language Reference: Concepts p.485 Table 20.3), so the read still executes exactly once,
    /// in order — the depth > base detour below runs the subroutine wherever
    /// its label sits and only a pop may bring control back into the range (any
    /// other re-entry is a fall-through INTO the read — unmoldable, fail loud).
    fn runProgramRange(self: *Executor, first: usize, end: usize) Error!Flow {
        const ops = self.ops;
        var pc: usize = first;
        const base = self.link_stack.items.len;
        defer self.link_stack.shrinkRetainingCapacity(base);
        var on_detour = false;
        while (true) {
            // NOTE-linkimplicitreturn: falling off the END of the op stream is
            // the step's implied RETURN — "Every DATA step has an implied
            // RETURN as its last executable statement" (Statements p.325) —
            // and a RETURN after a LINK pops back to the statement following
            // the LINK (p.116, p.222; Language Reference: Concepts p.485 Table 20.3), it does NOT
            // end the iteration. Only a stack at base ends the range.
            if (pc >= ops.len) {
                if (self.link_stack.items.len > base) {
                    pc = self.link_stack.pop().?;
                    // Landing OUTSIDE the range resumes the detour; landing
                    // inside is an ordinary return, not a fall-through INTO
                    // the read (the on_detour break must not fire on it).
                    if (pc < first or pc >= end) on_detour = true;
                    continue;
                }
                break;
            }
            const in_range = pc >= first and pc < end;
            if (!in_range) {
                if (self.link_stack.items.len == base) break; // range done, or a GOTO crossed the read
                on_detour = true; // LINK detour into the other half — safe, it RETURNs
            } else if (on_detour) {
                if (self.link_stack.items.len == base) {
                    on_detour = false; // the subroutine RETURNed all the way back
                } else break; // fell INTO the range mid-subroutine (towards the read) — fail loud
            }
            switch (ops[pc]) {
                .stmt => |s| {
                    // stamp FORMAT/INFORMAT/LABEL onto vars defined so far (EXEC-varattr)
                    self.maybeApplyAttrs();
                    switch (try self.runStmt(s)) {
                        .normal => pc += 1,
                        .returned => {
                            if (self.link_stack.items.len > base) {
                                pc = self.link_stack.pop().?;
                            } else return .returned;
                        },
                        else => |f| return f, // .deleted / .stop / stray .continue_/.leave
                    }
                },
                .jmp => |to| pc = to,
                .link => |to| {
                    try self.link_stack.append(self.arena, pc + 1);
                    pc = to;
                },
                .jfalse => |j| pc = if ((try self.ev.eval(j.cond)).truthy()) pc + 1 else j.target,
                .do_enter => |e| {
                    const start = toF64(try self.ev.eval(e.start));
                    const stop = toF64(try self.ev.eval(e.stop));
                    const step = if (e.by) |by| toF64(try self.ev.eval(by)) else 1;
                    // BUG-doByZero: BY 0 would loop forever — SAS ERRORs, not a
                    // silent 0-iteration skip. A genuinely MISSING bound stays on
                    // the note path below (NaN never == 0).
                    if (step == 0) {
                        self.diags.report(.err, 0, "The DO loop has a zero increment (BY 0).", .{}) catch {};
                        return error.ExecError;
                    }
                    if (std.math.isNan(start) or std.math.isNan(stop) or std.math.isNan(step)) {
                        if (e.note_bad) self.diags.note(0, "DO loop bounds are missing; loop skipped", .{}) catch {};
                        pc = e.skip_pc;
                    } else {
                        e.st.* = .{ .x = start, .stop = stop, .step = step };
                        pc += 1;
                    }
                },
                .do_chk => |c| pc = if (if (c.st.step > 0) c.st.x <= c.st.stop else c.st.x >= c.st.stop) pc + 1 else c.fail_pc,
                .do_set => |d| {
                    try self.pdv.set(d.name, .{ .num = d.st.x });
                    pc += 1;
                },
                .do_incr => |d| {
                    // BUG-doindexreassign: an iterative DO lets the body reassign the
                    // index; SAS steps from that altered value and tests the `to` bound
                    // against it. Re-read it from the PDV before adding the step (was:
                    // driven off the hidden counter, ignoring the body's change). `name`
                    // is null for a value-list range, where the list is fixed and a body
                    // reassignment must NOT change which listed value comes next.
                    if (d.name) |nm| d.st.x = toF64(self.pdv.get(nm) orelse Value.missing);
                    d.st.x += d.st.step;
                    pc = d.chk_pc;
                },
                .do_final => |fd| {
                    try self.pdv.set(fd.name, .{ .num = fd.st.x });
                    pc += 1;
                },
                .do_setv => |v| {
                    try self.pdv.set(v.name, try self.ev.eval(v.value));
                    pc += 1;
                },
            }
        }
        if (pc != end) {
            diag.markGap(); // a GOTO over the driving source is valid SAS — our gap, rc 2
            self.diags.report(.err, 0, "a GOTO/LINK transfer crosses the driving SET/MERGE/UPDATE/MODIFY statement, which is not supported", .{}) catch {};
            return error.ExecError;
        }
        return .normal;
    }

    /// Compile the step body to the flat op stream (self.ops), resolving every
    /// GOTO/LINK target against the FULL label table (any nesting depth). An
    /// undefined target is a compile-time ERROR (F3 fail-loud) — reported here;
    /// run() gates on hasStepErrors() so the step never executes.
    fn compileProgram(self: *Executor, program: []const ast.Stmt) Error!void {
        var c: OpCompiler = .{ .a = self.arena };
        // Inline of compileStmts: compiling the driver statement records the op
        // index the iteration splits at (BUG-setstmtorder) — the ops BEFORE it
        // are the pre-read prefix, its own op onward the post-read suffix.
        for (program) |*s| {
            if (self.driver_stmt) |ds| if (s == ds) {
                self.split_pc = c.ops.items.len;
            };
            try c.compileStmt(s);
        }
        // BUG-leavecontinueopen: LEAVE/CONTINUE in open code is a SAS compile-time
        // ERROR (728-185) — the step must NOT run with the statements after it
        // silently dropped. Reported like an undefined label: the hasStepErrors()
        // gate in run() halts before a single observation is written.
        if (c.stray_lc) |kw|
            self.diags.report(.err, 0, "The {s} statement is not valid outside of a DO loop.", .{kw}) catch {};
        for (c.xfers.items) |xf| {
            const target = c.findLabel(xf.name) orelse {
                self.diags.report(.err, 0, "label {s} is not defined", .{xf.name}) catch {};
                continue;
            };
            c.patch(xf.op, target);
        }
        self.ops = c.ops.items;
    }

    fn runStmts(self: *Executor, stmts: []const ast.Stmt) Error!Flow {
        for (stmts) |*s| {
            // Stamp FORMAT/INFORMAT/LABEL onto vars defined so far, so a V-attribute
            // function reading them mid-step sees them (EXEC-varattr). Guarded so a
            // step with no attribute statements pays nothing.
            self.maybeApplyAttrs();
            const f = try self.runStmt(s);
            if (f != .normal) return f; // DELETE (.deleted) / STOP (.stop) halt the list
        }
        return .normal;
    }

    /// Apply each collected variable attribute to its PDV var, once the var
    /// exists. Set-only (never defines) so column order — SAS's source-appearance
    /// order — is untouched. The fmt's leading byte tags the kind: \x00 label,
    /// \x01 informat, else a display format.
    /// Stamp collected attributes onto the PDV — but only when a new variable has
    /// been defined since the last run (re-stamping is idempotent). Called before
    /// every statement, so the guard is what keeps a big deep-nested step from
    /// re-scanning attrs×vars per statement (BUG-xohang).
    fn maybeApplyAttrs(self: *Executor) void {
        if (self.attrs.items.len == 0) return;
        if (self.pdv.vars.items.len == self.attrs_applied_at) return;
        self.applyAttrs();
        self.attrs_applied_at = self.pdv.vars.items.len;
    }

    fn applyAttrs(self: *Executor) void {
        for (self.attrs.items) |a| {
            if (self.pdv.indexOf(a.name) == null) continue; // not defined yet
            if (a.fmt.len > 0 and a.fmt[0] == 0) {
                self.pdv.setLabel(a.name, a.fmt[1..]);
            } else if (a.fmt.len > 0 and a.fmt[0] == 1) {
                self.pdv.setInformat(a.name, a.fmt[1..]);
            } else self.pdv.setFormat(a.name, a.fmt);
        }
    }

    fn runStmt(self: *Executor, s: *const ast.Stmt) Error!Flow {
        switch (s.*) {
            .assign => |a| {
                // A combinatorics FUNCTION form (rc = allcomb(...)) mutates its variable
                // args like the CALL routine and returns a status — handle it before the
                // plain value assignment (Phase-F-final).
                if (!(a.value.* == .call and try self.runCombFunc(a.target, a.value.call))) {
                    try self.pdv.set(a.target, try self.ev.eval(a.value));
                    // `_infile_ = …` also writes through to the held record
                    // (BUG-infilevarnoop). Read the stored cell back so a numeric
                    // RHS applies the PDV's own num→char rendering (compact BEST).
                    if (eqi(a.target, "_infile_")) if (self.pdv.get(a.target)) |v| {
                        if (v == .str) self.writeInfileBuffer(v.str);
                    };
                }
            },
            .array_assign => |aa| try self.runArrayAssign(aa),
            .substr_assign => |sa| try self.runSubstrAssign(sa),
            .if_ => |iff| return try self.runIf(iff),
            .do_ => |d| return try self.runDo(d),
            // explicit `output [names];` writes now; `has_output` suppressed the implicit one.
            .output => |names| try self.runOutput(names),
            .put => |items| try self.runPut(items),
            // INPUT reads at run time (PG-atptr): several INPUTs per iteration compose,
            // and a trailing `@`/`@@` holds the record for the next one. EOF mid-step
            // stops the step without writing the half-built obs (like SAS).
            .input => |items| return try self.execInput(items),
            .hash_decl => |d| try self.hashDeclare(d),
            .hash_op => |op| try self.hashOp(op),
            .call_ => |c| try self.runCall(c),
            .null_stmt => return .normal, // the SAS null statement `;` — no-op (PARSE-nullstmt)
            .where_ => return .normal, // consumed at compile time (scan → driver filter)
            .delete => return .deleted, // drop the current obs, return to top of step
            .stop => return .stop, // terminate the DATA step
            .abort => |arg| return try self.runAbort(arg),
            .return_ => return .returned, // implicit output, then top of step
            .continue_ => return .continue_, // skip to the next DO-loop iteration
            .leave => return .leave, // exit the enclosing DO loop
            // Reached only when a selector SELECT falls through every WHEN and has no
            // OTHERWISE. SAS errors and stops the step here (BUG-selectnomatch) — a
            // silently-skipped no-match hides a mis-valued selector.
            .select_nomatch => {
                self.diags.report(.err, 0, "no WHEN condition was satisfied and there is no OTHERWISE statement in the SELECT group", .{}) catch {};
                return error.ExecError;
            },
            .label => {}, // a GOTO/LINK target marker — inert when reached in sequence
            .goto => |lbl| {
                self.pending_label = lbl;
                return .goto_;
            },
            .link => |lbl| {
                self.pending_label = lbl;
                return .link_;
            },
            // `set ds point=i;` is EXECUTABLE — it direct-reads obs `i` here each time
            // it is reached (BUG-setpoint). An EXTRA SET (MULTISET-impl: a 2nd or a
            // conditional SET) is also executable, reading via its own cursor. The
            // driver SET (the loop's first) is driver-based and stays inert.
            .set => {
                // GAP-secondsetstmt: the POINT= read fires only at the node that
                // CARRIES the option — null set_point_node is the driver list's
                // own SET (POINT=-only step / MERGE-side lookup); a second-SET
                // lookup (p.341 Example 6) reads at its OWN node, and the
                // sequential driver SET beside it stays inert here (loadNext
                // reads it).
                const point_here = self.set_point_node == null or self.set_point_node.? == s;
                if (if (point_here) self.set_point_var else null) |pv| {
                    if (self.set_point_dss.len > 0) {
                        // BUG-pointredefinesnobs: the addressable range is the
                        // CONCATENATION of every listed source, so the bound is
                        // their total — obs a.n+1 is b's first, not out of range.
                        var total: usize = 0;
                        for (self.set_point_dss) |d| total += d.rowCount();
                        const i = toF64(self.pdv.get(pv) orelse Value.missing); // 1-based obs number
                        // NOTE-pointoorhard: a missing/out-of-range POINT= must NOT halt
                        // the step. Statements Ref SET POINT=: "If SAS reads an invalid
                        // value of the POINT= variable, it sets the automatic variable
                        // _ERROR_ to 1" — and its CONTINUOUS-LOOP caution only makes
                        // sense if the step CONTINUES past the invalid value; Language Reference: Concepts
                        // p.488's documented idiom (`if _error_ then stop;`) is the user
                        // side of exactly that contract. So: _ERROR_=1, a loud NOTE, and
                        // the iteration runs on to the user's guard. (The old ERRHALT —
                        // e1d73fbf BUG-pointnobs, "halt like the array-OOR paths" — made
                        // the idiom unrunnable: rc 1 and the ERROR errhalt-poisoned every
                        // later step, suppressing the following PROC PRINT.)
                        // ponytail: three residuals are oracle-blocked; picked defensibly:
                        //   class = NOTE (not ERROR) — the doc says only "sets _ERROR_ to
                        //     1"; an ERROR would fail the exit code and errhalt-poison
                        //     later steps, which is the very halt behaviour being removed.
                        //   rc/SYSERR = 0 — a NOTE sets neither; the step ends via the
                        //     user's own STOP/loop, not via the invalid read.
                        //   stale PDV = re-output as coded — SET vars are retained and no
                        //     read happened, so an explicit OUTPUT writes the retained
                        //     values with _ERROR_=1 set (loud); suppressing it would
                        //     diverge from generic OUTPUT semantics.
                        if (std.math.isNan(i) or i < 1 or i > @as(f64, @floatFromInt(total))) {
                            self.ev.setError() catch {}; // _ERROR_=1; losing it to OOM doesn't soften the NOTE
                            // Single source keeps the message verbatim (it is pinned);
                            // a concatenation names the range it really addresses.
                            if (self.set_point_dss.len == 1) {
                                self.diags.report(.note, 0, "SET POINT= invalid observation number {d}: {s} has {d} observations", .{ i, self.set_point_dss[0].name, total }) catch {};
                            } else {
                                self.diags.report(.note, 0, "SET POINT= invalid observation number {d}: the {d} data sets have {d} observations", .{ i, self.set_point_dss.len, total }) catch {};
                            }
                        } else {
                            const obs: usize = @intFromFloat(i);
                            // BUG-pointnoiterate: a repeat of an obs read in an EARLIER
                            // iteration ends the step like STOP (current obs not
                            // output); a re-read WITHIN one iteration (a DO loop
                            // reading one obs twice) is fine. Both this and the
                            // re-arm apply only when POINT= DRIVES — alongside a
                            // MERGE/UPDATE/INPUT driver a re-read is an ordinary
                            // repeated lookup and the driver, not the read, ends the
                            // step (BUG-pointmergelookup).
                            if (self.point_driven) {
                                if (self.point_reads.get(obs)) |first_iter| {
                                    if (first_iter < self.n_iter) return .stop;
                                } else try self.point_reads.put(self.arena, obs, self.n_iter);
                                // …and the read re-arms the single-pass driver for one
                                // more implicit iteration (the runExtraSet trick). A
                                // FAILED read (the NOTE arm above) does NOT re-arm: a
                                // bare `set d point=_n_;` with no STOP then terminates
                                // at the first invalid read instead of spinning NOTEs
                                // forever — the deliberate bound DEC-pointrepeatstop
                                // already applies to no-progress re-reads, extended to
                                // no-progress invalid reads (SAS's own answer is the
                                // documented continuous-loop CAUTION: use STOP).
                                if (self.driver_ptr) |dp| switch (dp.*) {
                                    .once => |*spent| spent.* = false,
                                    else => {},
                                };
                            }
                            // Map the GLOBAL 1-based obs onto (source, local offset).
                            // `point_reads`' repeat-detection above deliberately keyed
                            // off the GLOBAL number, so it still sees one flat address
                            // space across the concatenation.
                            var si: usize = 0;
                            var local: usize = obs;
                            while (si + 1 < self.set_point_dss.len and local > self.set_point_dss[si].rowCount()) : (si += 1)
                                local -= self.set_point_dss[si].rowCount();
                            const ds = self.set_point_dss[si];
                            try io.loadRow(self.pdv, ds, local - 1, self.set_point_slots[si]);
                            try self.stampObs(ds);
                        }
                    }
                } else if (self.dow_set == s) {
                    return try self.dowRead(); // DOWLOOP-impl: read at the node, EOF → .stop
                } else if (self.extraSetFor(s)) |es| {
                    return try self.runExtraSet(es);
                }
            },
            // INFILE is not inert (BUG-multiinfilelastwins): executing it makes
            // its line source the current one for the following INPUTs.
            .infile => try self.selectInfileStmt(s),
            // declaratives: consumed by `scan`, inert at run time
            .drop, .keep, .rename, .retain, .merge, .by, .array, .datalines, .format, .informat, .file => {},
            // UPDATE/MODIFY parse today; their exec semantics are dev2's — this
            // inert stub only keeps the exhaustive switch compiling (G-update).
            .update, .modify => {},
        }
        return .normal;
    }

    /// ABORT (BUG-abortreturncode, Language Reference: Concepts p.485-486). Every form sets _ERROR_=1
    /// and ends the step like STOP (current obs not output). ABEND [n] /
    /// RETURN n / bare n additionally kill the SESSION: g_abort_rc carries the
    /// exit code to main, and the ERROR diagnostic poisons every later step
    /// (syntax-check mode, BUG-errhalt) — no downstream DATA/PROC runs.
    fn runAbort(self: *Executor, arg: ast.AbortArg) Error!Flow {
        try self.pdv.set("_error_", .{ .num = 1 });
        const rc: u8 = switch (arg) {
            .plain => return .stop,
            .abend => |n| n orelse 1, // ABEND is abnormal: never exit 0
            .n => |n| n,
        };
        g_abort_rc = rc;
        self.diags.report(.err, 0, "Execution terminated by an ABORT statement, return code {d}", .{rc}) catch {};
        return .stop;
    }

    /// Store a CALL SYMPUT/SYMPUTX variable in the symbol table SAS 9.4 puts it in
    /// (BUG-symputscope). SAS 9.4 Macro Language: Reference, Fifth Edition, printed
    /// p.77, "Special Cases of Scope with the CALL SYMPUT Routine", rule 1: the
    /// variable is created "in the current symbol table available while the DATA
    /// step is executing, provided that symbol table is not empty. If it is empty
    /// (contains no local macro variables), usually CALL SYMPUT creates the
    /// variable in the closest nonempty symbol table."
    ///
    /// The scope lives in macro.zig (this store has none — see `Library.macro_vars`),
    /// so ask it first: `symputLocal` files the variable in the owning macro frame
    /// and reports true, and the flat store must then NOT get a copy or a later
    /// step would resurrect the dead local through `bindStepVars`. False = no
    /// nonempty local table (open code, or a parameter-less macro whose frame is
    /// empty — the doc's ENV3) → global, i.e. exactly the previous behaviour.
    /// Routed here rather than inside `setMacroVar`, which is shared with PROC SQL's
    /// `INTO :mvar` and the SQLOBS/SQLRC automatics — the p.77 rule is about CALL
    /// SYMPUT only, and quietly rescoping SELECT INTO would be an invented semantic.
    fn setSymput(self: *Executor, name: []const u8, val: []const u8, tab: @import("macro.zig").SymTab) Error!void {
        if (try @import("macro.zig").symputLocal(name, val, tab)) return;
        return self.lib.setMacroVar(name, val);
    }

    /// CALL SYMPUTX's third argument, `symbol-table` (BUG-symputxsymtab). SAS 9.4
    /// Macro Language: Reference, Fifth Edition, printed p.307:
    ///   G — "stored in the global symbol table, even if a local symbol table exists"
    ///   L — "the most local symbol table that exists… If a local symbol table
    ///        does not exist… the global symbol table"
    ///   F — the DEFAULT: "if the macro variable exists in any symbol table, CALL
    ///        SYMPUTX uses the version in the most local symbol table in which it
    ///        exists. If the macro variable does not exist, CALL SYMPUTX stores
    ///        the variable in the most local symbol table that it finds."
    /// It was parsed and DISCARDED with no diagnostic — a silent no-op, which
    /// D-002 forbids outright. Absent (or absent-third-arg CALL SYMPUT) = F.
    /// Anything outside G/L/F is a LOUD user error (rc 1), never a silent
    /// fallback to the default: guessing there is how a `'g'` typo'd to `'q'`
    /// would quietly scope a clinical macro variable the wrong way.
    fn symputTab(self: *Executor, arg: *const ast.Expr) Error!@import("macro.zig").SymTab {
        const raw = switch (try self.ev.eval(arg)) {
            .str => |s| s,
            .num => return self.diags.fail(error.ExecError, 0, "CALL SYMPUTX symbol-table argument must be 'G', 'L' or 'F'", .{}),
        };
        const s = std.mem.trim(u8, raw, " ");
        if (s.len == 1) switch (std.ascii.toUpper(s[0])) {
            'G' => return .global,
            'L' => return .local,
            'F' => return .default,
            else => {},
        };
        return self.diags.fail(error.ExecError, 0, "CALL SYMPUTX symbol-table argument must be 'G', 'L' or 'F', got '{s}'", .{s});
    }

    /// A CALL statement. Dispatches the implemented call-by-reference routines,
    /// each mutating its argument variable(s) in place: MISSING, SYMPUT/SYMPUTX,
    /// SCAN, CATS/CATT/CATX, SORTN/SORTC/SORT, LABEL, STDIZE, the RAN*/perm/comb
    /// family, the PRX* family (PRXCHANGE/NEXT/POSN/SUBSTR/FREE), elementwise
    /// TANH/LOGISTIC/SOFTMAX, VNAME/VNEXT, and IS8601_CONVERT. An UNIMPLEMENTED
    /// routine is a hard ERROR (fail loud), never a silent no-op — a dropped
    /// mutation in a clinical pipeline is the worst failure class (CLIN-failloud).
    /// ponytail: CALL COMPRESS is NOT wired — its SAS signature (mutate-arg-1 vs
    /// result-var) is ambiguous enough that guessing risks silent-wrong output, so
    /// it stays fail-loud until a program pins the exact form.
    fn runCall(self: *Executor, c_in: ast.Call) Error!void {
        // BUG-callrefarray: an array-element argument `a{i}` — and `of a{*}`, which
        // the parser expands to `a{1}..a{n}` — reaches here as an `.array_ref` Expr,
        // which the by-reference handlers (they write back only through `.variable`)
        // treat as read-only. Resolve each to its underlying element VARIABLE first,
        // so the routine's mutation lands in the array slot.
        var c = c_in;
        var has_ref = false;
        for (c.args) |arg| if (arg == .array_ref) {
            has_ref = true;
            break;
        };
        if (has_ref) {
            const resolved = try self.arena.alloc(ast.Expr, c.args.len);
            for (c.args, 0..) |arg, i| resolved[i] = switch (arg) {
                .array_ref => |ar| blk: {
                    const xf = @floor(toF64(try self.ev.eval(ar.index)));
                    if (xf >= 1 and xf <= @as(f64, @floatFromInt(ar.elements.len)))
                        break :blk ast.Expr{ .variable = ar.elements[@as(usize, @intFromFloat(xf)) - 1] };
                    break :blk arg; // out of range → left as-is (reads give missing)
                },
                else => arg,
            };
            c.args = resolved;
        }
        if (std.ascii.eqlIgnoreCase(c.name, "missing")) {
            for (c.args) |arg| switch (arg) {
                .variable => |name| if (self.pdv.get(name)) |cur| {
                    try self.pdv.set(name, switch (cur) {
                        .str => .{ .str = "" },
                        .num => Value.missing,
                    });
                } else {
                    _ = try self.pdv.define(name, .num);
                    try self.pdv.set(name, Value.missing);
                },
                else => {}, // CALL MISSING only affects variable arguments
            };
            return;
        }
        // CALL SYMPUT('name', value) / SYMPUTX — write a macro variable from the
        // DATA step. SYMPUTX strips leading/trailing blanks from name and value.
        if (eqi(c.name, "symput") or eqi(c.name, "symputx")) {
            if (c.args.len >= 2) {
                const nm = try self.callArgStr(c.args[0]);
                if (eqi(c.name, "symputx")) {
                    // SYMPUTX numeric converts via BEST32. (BUG-symputxwidth):
                    // BEST12. loses precision/E-notation past 12 sig digits.
                    // `{d}` prints shortest round-trip digits — what SAS's
                    // BEST32. shows (bestNumW(32) over-pads to the width,
                    // e.g. pi → 3.1415926535897896). Missings/overflow keep
                    // bestNumW's '.'-letter rendering.
                    const val = switch (try self.ev.eval(&c.args[1])) {
                        .str => |s| s,
                        .num => |x| if (std.math.isNan(x) or !std.math.isFinite(x))
                            try format.bestNumW(self.arena, x, 32)
                        else
                            try std.fmt.allocPrint(self.arena, "{d}", .{x}),
                    };
                    const tab = if (c.args.len >= 3) try self.symputTab(&c.args[2]) else .default;
                    try self.setSymput(std.mem.trim(u8, nm, " "), std.mem.trim(u8, val, " "), tab);
                } else {
                    // SYMPUT (BUG-symputnumfmt): name trimmed TRAILING-only (a
                    // leading blank is an ERROR); a numeric value converts via
                    // BEST12. → right-justified 12-char field, stored UNtrimmed,
                    // with the num→char NOTE. SYMPUTX above trims both sides.
                    if (nm.len > 0 and nm[0] == ' ') {
                        self.diags.report(.err, 0, "CALL SYMPUT: macro-variable name has a leading blank", .{}) catch {};
                        return;
                    }
                    const val = switch (try self.ev.eval(&c.args[1])) {
                        .str => |s| s,
                        .num => |x| blk: {
                            self.diags.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{}) catch {};
                            const s = try format.bestNum(self.arena, x); // BEST12. → ≤ 12 cols
                            const buf = try self.arena.alloc(u8, 12);
                            @memset(buf, ' ');
                            @memcpy(buf[12 - s.len ..], s);
                            break :blk buf;
                        },
                    };
                    // CALL SYMPUT has NO symbol-table argument (printed p.301
                    // gives it exactly two) — a third one was silently dropped.
                    if (c.args.len >= 3)
                        return self.diags.fail(error.ExecError, 0, "CALL SYMPUT takes two arguments; the symbol-table argument belongs to CALL SYMPUTX", .{});
                    try self.setSymput(std.mem.trimEnd(u8, nm, " "), val, .default);
                }
            }
            return;
        }
        // CALL EXECUTE('program text') — queue full steps (often a PROC) to run
        // AFTER this step finishes. The step driver is main.zig's runExpanded,
        // unreachable from here (circular import), so we append to the library
        // queue and main drains it FIFO (FEAT-callexecute). Non-char argument
        // and %nrstr-style macro quoting fail LOUD (D-002): quoting functions
        // would need the macro facility at unqueue time, which is long gone.
        if (eqi(c.name, "execute")) {
            const text = if (c.args.len == 1) switch (try self.ev.eval(&c.args[0])) {
                .str => |s| s,
                .num => null,
            } else null;
            if (text == null) {
                // AUDIT-errhaltclass: HALT for the same reason as the %nrstr arm
                // below — no continuing-class reading exists (a routine that
                // queues a program has no value to make missing), so it takes
                // Language Reference: Concepts printed p.174-175's "stopped processing this step" +
                // "was not replaced". Pre-fix the step ran every row and replaced
                // a live permanent member with its output.
                //
                // ponytail: the HALT CLASS is settled here; the SEVERITY is not,
                // and this arm is deliberately left erroring rather than
                // converted. Two readings survive the volume. Macro Language:
                // Reference printed p.296 lists only CHARACTER forms for
                // `argument`, but CALL SYMPUT — its sibling in the same chapter,
                // printed p.306 — auto-converts a numeric expression to character
                // "and writes a message in the log", and the Functions Reference
                // entry (printed p.303) carries the generic CALL-routine note
                // "All argument types must be CHAR, VARCHAR, or NUMERIC. If the
                // argument types do not match, a WARNING is issued". So real SAS
                // may well queue "42" rather than error. Converting to a halt is
                // safe REGARDLESS: report(.err) already errhalt-kills the rest of
                // the run, so this only stops a bogus member being written. But
                // whether it should be an ERROR at all is ORACLE-callexecutenum —
                // one live-SAS run of `call execute(1);`. If SAS converts, this
                // whole arm becomes a num->char conversion + NOTE, not a halt.
                //
                // Note this arm also fires on wrong ARITY (0 or 2+ args), which
                // no conversion reading can rescue — that half is unambiguous.
                return self.diags.fail(error.ExecError, 0, "CALL EXECUTE requires a single character argument", .{});
            }
            if (hasMacroQuoting(text.?)) {
                // AUDIT-errhaltclass: HALT, do not report-and-run-on. This arm is
                // an UNSUPPORTED-FEATURE refusal, and %nrstr here is not a user
                // mistake — Macro Language: Reference printed p.296 TIPs this exact
                // call as the documented workaround ("call execute('%nrstr(%sales('
                // ||month||'))');"). We still cannot honour it, so CLAUDE.md's "an
                // unsupported feature must error visibly, NEVER no-op" governs: a
                // loud ERROR the step then ignores is still a no-op. There is no
                // continuing-class reading — Language Reference: Concepts printed p.172-174 defines that
                // class by assigning a MISSING VALUE and carrying on, and a routine
                // that queues a program has no value to make missing; the unit of
                // WORK simply does not happen. So it takes the p.174-175 Example
                // Code 8.6 path ("stopped processing this step" + "was not
                // replaced"), like runArrayAssign. Severity is UNCHANGED and was
                // already maximal: report(.err) sets hasStepErrors(), which
                // errhalt-skips every later step and every queued fragment
                // (main.zig:297), so the only delta is that the step no longer
                // writes an output member over a live one.
                // The reference TIPs this exact call as the documented workaround
                // (comment above) — valid SAS we can't honour, so rc 2 (D-009).
                return failGap(self.diags, "CALL EXECUTE with macro-quoting functions (%nrstr/%str/…) is not supported", .{});
            }
            try self.lib.execute_queue.append(self.arena, try self.arena.dupe(u8, text.?));
            return;
        }
        // ── SCL / utility CALL routines that update their argument variables ──
        if (eqi(c.name, "sortn") or eqi(c.name, "sortc")) return self.callSort(c, eqi(c.name, "sortc"));
        if (eqi(c.name, "scan")) return self.callScan(c);
        if (eqi(c.name, "cats") or eqi(c.name, "catt")) return self.callCats(c, eqi(c.name, "cats"));
        if (eqi(c.name, "catx")) return self.callCatx(c);
        if (eqi(c.name, "label")) { // CALL LABEL(dsid, var-num, out) → out = the variable's label
            if (c.args.len >= 3 and c.args[2] == .variable) {
                const dsid = toF64(try self.ev.eval(&c.args[0]));
                const vn = toF64(try self.ev.eval(&c.args[1]));
                try self.pdv.set(c.args[2].variable, .{ .str = try self.arena.dupe(u8, dsfns.varlabel(dsid, vn)) });
                return;
            }
            // BUG-calllabel2arg: DATA-step form CALL LABEL(var, out) → out = var's
            // declared label, or the variable NAME when it has none (SAS 9.4 F&C
            // Ref p.322: "If variable-1 does not have a label, the variable name
            // is assigned as the value of variable-2."). Used to skip the 3-arg
            // body and return having written NOTHING (silent blank).
            if (c.args.len == 2 and c.args[0] == .variable and c.args[1] == .variable) {
                const nm = c.args[0].variable;
                const lbl = self.lib.varLabel(nm) orelse self.pdv.labelOf(nm) orelse nm;
                try self.pdv.set(c.args[1].variable, .{ .str = try self.arena.dupe(u8, lbl) });
            }
            return;
        }
        if (eqi(c.name, "stdize")) return self.callStdize(c);
        if (eqi(c.name, "ranperm")) return self.callRanperm(c);
        if (eqi(c.name, "ranperk")) return self.callRankSelect(c, false);
        if (eqi(c.name, "rancomb")) return self.callRankSelect(c, true);
        if (eqi(c.name, "allcombi")) return self.callAllcombi(c);
        if (eqi(c.name, "streaminit")) return self.callStreamInit(c);
        if (eqi(c.name, "streamrewind")) return self.rewindRngStream();
        if (eqi(c.name, "stream")) return self.callStream(c);
        if (eqi(c.name, "lexperm")) return self.callLexperm(c);
        if (eqi(c.name, "lexperk")) return self.callLexperk(c);
        if (eqi(c.name, "lexcombi")) return self.callLexcombi(c);
        if (eqi(c.name, "graycode")) return self.callGraycode(c);
        if (eqi(c.name, "allperm")) return self.callAllperm(c);
        if (eqi(c.name, "allcomb")) return self.callAllcomb(c);
        if (eqi(c.name, "lexcomb")) return self.callLexcomb(c);
        // ── F-callplumbing proof: 3 more CALL routines wired through the same
        // call-by-reference mechanism (var args → writable PDV slots).
        if (eqi(c.name, "sort")) { // CALL SORT — like SORTN/SORTC; type from the first arg
            const fv = if (c.args.len > 0 and c.args[0] == .variable) self.pdv.get(c.args[0].variable) else null;
            const is_char = switch (fv orelse Value{ .num = 0 }) {
                .str => true,
                .num => false,
            };
            return self.callSort(c, is_char);
        }
        if (eqi(c.name, "ranuni")) { // CALL RANUNI(seed, x): x ~ U(0,1); seed updated in place
            if (c.args.len < 2) return;
            var st = seedState(toF64(try self.ev.eval(&c.args[0])));
            const u = lehmerNext(&st);
            if (c.args[1] == .variable) try self.pdv.set(c.args[1].variable, .{ .num = u });
            if (c.args[0] == .variable) try self.pdv.set(c.args[0].variable, .{ .num = @floatFromInt(st) });
            return;
        }
        if (eqi(c.name, "rannor") or eqi(c.name, "ranexp") or eqi(c.name, "rancau") or
            eqi(c.name, "rantri") or eqi(c.name, "ranpoi") or eqi(c.name, "ranbin") or
            eqi(c.name, "rangam") or eqi(c.name, "rantbl")) return self.callRanDist(c);
        if (eqi(c.name, "prxchange")) return self.callPrxchange(c);
        if (eqi(c.name, "prxnext")) return self.callPrxnext(c);
        if (eqi(c.name, "prxposn")) return self.callPrxposn(c);
        if (eqi(c.name, "prxsubstr")) return self.callPrxsubstr(c);
        if (eqi(c.name, "prxfree")) return self.callPrxfree(c);
        if (eqi(c.name, "tanh")) return self.callElementwise(c, .tanh);
        if (eqi(c.name, "logistic")) return self.callElementwise(c, .logistic);
        if (eqi(c.name, "softmax")) return self.callSoftmax(c);
        if (eqi(c.name, "vnext")) return self.callVnext(c);
        if (eqi(c.name, "vname")) { // CALL VNAME(var, out): out = the NAME of var
            if (c.args.len < 2) return;
            const nm = if (c.args[0] == .variable) c.args[0].variable else "";
            if (c.args[1] == .variable) try self.pdv.set(c.args[1].variable, .{ .str = try self.arena.dupe(u8, nm) });
            return;
        }
        if (eqi(c.name, "is8601_convert")) {
            // CALL IS8601_CONVERT(convert-from, convert-to, <from-vars>, <to-vars>).
            // ponytail: ONLY 'dt/dt'→'du' — two datetimes in, duration (seconds) out
            // = later−earlier. Any other from/to combo falls through to the hard error
            // below (never silently return seconds for an unimplemented form).
            // Upgrade path: full ISO-8601 interval/duration model (dun/intvl/du/dt/
            // start/end forms, $N8601B/E formats, calendar Y/M components).
            if (c.args.len >= 5) {
                const from = std.mem.trim(u8, try self.callArgStr(c.args[0]), " ");
                const to = std.mem.trim(u8, try self.callArgStr(c.args[1]), " ");
                if (eqi(from, "dt/dt") and eqi(to, "du")) {
                    const ds = toF64(try self.ev.eval(&c.args[2]));
                    const de = toF64(try self.ev.eval(&c.args[3]));
                    if (c.args[4] == .variable)
                        try self.pdv.set(c.args[4].variable, .{ .num = de - ds });
                    return;
                }
            }
        }
        // An unsupported CALL routine silently mutating nothing is dangerous for a
        // clinical pipeline — make it a hard ERROR, not a note (CLIN-failloud).
        // NOTE-callnohalt: SAS also ABORTS the step on that ERROR — returning
        // normally let the statements after the bad CALL run on a poisoned PDV.
        // Mirror the select_nomatch/array-oor path: ExecError out of runStmt.
        //
        // SPLIT (audit-exitcodecontract.md §5c): a name the Functions and CALL
        // Routines reference lists is valid SAS we have not written → gap, rc 2
        // ("file an opensas issue"). A misspelling (`call symptu(...)`) keeps
        // rc 1 — re-tagging the whole catch-all would send a typo to our tracker.
        if (isCallRoutine(c.name))
            return failGap(self.diags, "CALL {s}() is not supported", .{c.name});
        return self.diags.fail(error.ExecError, 0, "CALL {s}() is not supported", .{c.name});
    }

    /// CALL RANNOR/RANEXP/RANCAU/RANTRI/RANPOI/RANBIN/RANGAM/RANTBL(seed, <params,> x):
    /// draw one variate of the named distribution into the LAST variable argument and
    /// update the seed in place. Same transforms as the ranXXX functions, over SAS's
    /// Lehmer stream (BUG-ranseq). Params are the args between the seed and the output.
    fn callRanDist(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 2) return;
        var st = seedState(toF64(try self.ev.eval(&c.args[0])));
        var pbuf: [64]f64 = undefined;
        var np: usize = 0;
        for (c.args[1 .. c.args.len - 1]) |*a| {
            if (np >= pbuf.len) break;
            pbuf[np] = toF64(try self.ev.eval(a));
            np += 1;
        }
        const x = ranVariate(&st, c.name, pbuf[0..np]);
        const outv = c.args[c.args.len - 1];
        if (outv == .variable) try self.pdv.set(outv.variable, .{ .num = x });
        if (c.args[0] == .variable) try self.pdv.set(c.args[0].variable, .{ .num = @floatFromInt(st) });
    }

    /// Resolve a PRX argument to a compiled pattern id: a number is the id, a
    /// string is compiled on the spot.
    fn prxIdOf(v: Value) ?u32 {
        return switch (v) {
            .num => |x| if (!(x >= 1)) null else @intFromFloat(@trunc(x)),
            .str => |str| prx.parse(str),
        };
    }

    /// CALL PRXCHANGE(rx, times, source <, result <, resultlen>>): regex-substitute.
    /// 3-arg form edits `source` in place; 4+-arg writes the result into `result`.
    fn callPrxchange(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const id = prxIdOf(try self.ev.eval(&c.args[0])) orelse return;
        const times: i64 = @intFromFloat(@trunc(toF64(try self.ev.eval(&c.args[1]))));
        const src = try self.callArgStr(c.args[2]);
        const out = prx.change(self.arena, id, times, src) catch return;
        const dst = if (c.args.len >= 4) c.args[3] else c.args[2];
        if (dst == .variable) try self.pdv.set(dst.variable, .{ .str = out });
        if (c.args.len >= 5 and c.args[4] == .variable)
            try self.pdv.set(c.args[4].variable, .{ .num = @floatFromInt(out.len) });
    }

    /// CALL PRXNEXT(rx, start, stop, source, position, length): next match in
    /// source[start..stop] → position/length (0/0 if none); `start` advances past it.
    fn callPrxnext(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 6) return;
        const id = prxIdOf(try self.ev.eval(&c.args[0])) orelse return;
        const sv = toF64(try self.ev.eval(&c.args[1]));
        const start: usize = if (sv < 1) 1 else @intFromFloat(@trunc(sv));
        const tv = toF64(try self.ev.eval(&c.args[2]));
        const stop: usize = if (tv < 0) 0 else @intFromFloat(@trunc(tv));
        const src = try self.callArgStr(c.args[3]);
        const sp = prx.next(id, src, start, stop);
        if (c.args[4] == .variable) try self.pdv.set(c.args[4].variable, .{ .num = @floatFromInt(sp.pos) });
        if (c.args[5] == .variable) try self.pdv.set(c.args[5].variable, .{ .num = @floatFromInt(sp.len) });
        if (c.args[1] == .variable) {
            const nxt: usize = if (sp.pos > 0) sp.pos + sp.len else start;
            try self.pdv.set(c.args[1].variable, .{ .num = @floatFromInt(nxt) });
        }
    }

    /// CALL PRXPOSN(rx, n, position <, length>): position/length of capture group n
    /// from the last match (0/0 if it didn't match).
    fn callPrxposn(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const id = prxIdOf(try self.ev.eval(&c.args[0])) orelse return;
        const nv = toF64(try self.ev.eval(&c.args[1]));
        const n: usize = if (nv < 0) 0 else @intFromFloat(@trunc(nv));
        const sp = prx.posnSpan(id, n);
        if (c.args[2] == .variable) try self.pdv.set(c.args[2].variable, .{ .num = @floatFromInt(sp.pos) });
        if (c.args.len >= 4 and c.args[3] == .variable)
            try self.pdv.set(c.args[3].variable, .{ .num = @floatFromInt(sp.len) });
    }

    /// CALL PRXSUBSTR(rx, source, position <, length>): first match of rx in source
    /// → 1-based position (0 if none) and length.
    fn callPrxsubstr(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const id = prxIdOf(try self.ev.eval(&c.args[0])) orelse return;
        const src = try self.callArgStr(c.args[1]);
        const sp = prx.substr(id, src);
        if (c.args[2] == .variable) try self.pdv.set(c.args[2].variable, .{ .num = @floatFromInt(sp.pos) });
        if (c.args.len >= 4 and c.args[3] == .variable)
            try self.pdv.set(c.args[3].variable, .{ .num = @floatFromInt(sp.len) });
    }

    /// CALL PRXFREE(rx): release the compiled pattern and set the id variable missing.
    fn callPrxfree(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 1) return;
        if (prxIdOf(try self.ev.eval(&c.args[0]))) |id| prx.free(id);
        if (c.args[0] == .variable) try self.pdv.set(c.args[0].variable, Value.missing);
    }

    /// CALL LEXPERM(count, v1…vn): the count-th distinct permutation of the values
    /// in lexicographic order (factorial-number-system unrank of the sorted values).
    /// ponytail: exact for distinct values; a multiset over-counts identical values.
    fn callLexperm(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 2) return;
        const count = toF64(try self.ev.eval(&c.args[0]));
        const vals = try self.gatherVals(c.args[1..]);
        const n = vals.len;
        if (n == 0 or n > 19) return self.writeVals(c.args[1..], vals);
        const sorted = try self.arena.dupe(Value, vals);
        std.mem.sort(Value, sorted, {}, valLess);
        var fact: [20]u64 = undefined;
        fact[0] = 1;
        for (1..n + 1) |i| fact[i] = fact[i - 1] * i;
        var rank: u64 = combRank(u64, count, fact[n] - 1);
        const avail = try self.arena.dupe(Value, sorted);
        var alen = n;
        const out = try self.arena.alloc(Value, n);
        for (0..n) |i| {
            const f = fact[n - 1 - i];
            const pick = @min(@as(usize, @intCast(rank / f)), alen - 1);
            out[i] = avail[pick];
            for (pick..alen - 1) |j| avail[j] = avail[j + 1];
            alen -= 1;
            rank %= f;
        }
        try self.writeVals(c.args[1..], out);
    }

    /// CALL LEXPERK(count, k, v1…vn): the count-th distinct k-permutation of the
    /// values in lexicographic order; the chosen k land in the first k variables.
    fn callLexperk(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const count = toF64(try self.ev.eval(&c.args[0]));
        const kf = toF64(try self.ev.eval(&c.args[1]));
        const vals = try self.gatherVals(c.args[2..]);
        const n = vals.len;
        const k = @min(combN(kf), n);
        if (k == 0 or n > 19) return self.writeVals(c.args[2..], vals);
        const sorted = try self.arena.dupe(Value, vals);
        std.mem.sort(Value, sorted, {}, valLess);
        var pnk: u64 = 1; // P(n,k)
        for (0..k) |i| pnk *= (n - i);
        var rank: u64 = combRank(u64, count, pnk - 1);
        const avail = try self.arena.dupe(Value, sorted);
        var alen = n;
        const out = try self.arena.alloc(Value, n);
        for (0..k) |i| {
            var block: u64 = 1; // P(alen-1, k-1-i)
            for (0..k - 1 - i) |j| block *= (alen - 1 - j);
            const pick = @min(@as(usize, @intCast(rank / block)), alen - 1);
            out[i] = avail[pick];
            for (pick..alen - 1) |j| avail[j] = avail[j + 1];
            alen -= 1;
            rank %= block;
        }
        for (0..alen) |j| out[k + j] = avail[j]; // remaining values follow, sorted
        try self.writeVals(c.args[2..], out);
    }

    /// CALL LEXCOMBI(n, k, index-1, …, index-k): advance the k index variables to the
    /// next lexicographic combination of 1..n; if index-1 is 0/missing, initialize to
    /// 1..k.
    fn callLexcombi(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const nf = toF64(try self.ev.eval(&c.args[0]));
        const kf = toF64(try self.ev.eval(&c.args[1]));
        const n: usize = combN(nf);
        const k: usize = combN(kf);
        if (k == 0 or k > n or c.args.len < 2 + k) return;
        const idx = try self.arena.alloc(usize, k);
        const first = toF64(try self.ev.eval(&c.args[2]));
        if (first < 1) {
            for (0..k) |i| idx[i] = i + 1; // initialize to 1..k
        } else {
            for (0..k) |i| idx[i] = combN(toF64(try self.ev.eval(&c.args[2 + i])));
            // next combination: rightmost index that can still be raised
            var i = k;
            while (i > 0) {
                i -= 1;
                if (idx[i] < n - k + 1 + i) {
                    idx[i] += 1;
                    for (i + 1..k) |j| idx[j] = idx[j - 1] + 1;
                    break;
                }
            } else return; // exhausted → leave the last combination in place
        }
        for (0..k) |i| if (c.args[2 + i] == .variable)
            try self.pdv.set(c.args[2 + i].variable, .{ .num = @floatFromInt(idx[i]) });
    }

    /// CALL GRAYCODE(k, v1…vn): the n numeric variables are a 0/1 subset indicator;
    /// advance to the next subset in binary-reflected Gray-code (minimal-change)
    /// order — exactly one bit flips — and set k to the new subset size.
    fn callGraycode(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 2) return;
        const n = c.args.len - 1;
        if (n > 60) return;
        var bits: u64 = 0; // var-1 = bit 0
        for (0..n) |i| if (toF64(try self.ev.eval(&c.args[1 + i])) != 0) {
            bits |= (@as(u64, 1) << @intCast(i));
        };
        var rank = bits; // Gray → binary rank: XOR of all right shifts
        rank ^= rank >> 1;
        rank ^= rank >> 2;
        rank ^= rank >> 4;
        rank ^= rank >> 8;
        rank ^= rank >> 16;
        rank ^= rank >> 32;
        const nextg = (rank + 1) ^ ((rank + 1) >> 1); // rank+1 → Gray (one-bit change)
        for (0..n) |i| if (c.args[1 + i] == .variable) {
            const on = (nextg >> @intCast(i)) & 1;
            try self.pdv.set(c.args[1 + i].variable, .{ .num = @floatFromInt(on) });
        };
        if (c.args[0] == .variable)
            try self.pdv.set(c.args[0].variable, .{ .num = @floatFromInt(@popCount(nextg)) });
    }

    /// CALL TANH / CALL LOGISTIC(var-1, …, var-n): apply the function to each numeric
    /// arg in place (tanh(x) or the logistic 1/(1+e^-x)).
    fn callElementwise(self: *Executor, c: ast.Call, comptime kind: enum { tanh, logistic }) Error!void {
        if (c.args.len == 0) return;
        const vals = try self.gatherVals(c.args);
        const out = try self.arena.alloc(Value, vals.len);
        for (vals, 0..) |v, i| {
            const x = toF64(v);
            out[i] = .{ .num = switch (kind) {
                .tanh => std.math.tanh(x),
                .logistic => 1.0 / (1.0 + @exp(-x)),
            } };
        }
        try self.writeVals(c.args, out);
    }

    /// Combinatorics FUNCTION forms (rc = allcomb(count,k,v…), allperm/graycode/
    /// lexcomb/lexcombi/lexperk/lexperm/sort): run the CALL routine of the same name to
    /// permute the variable args, then return SAS's status — the leftmost-changed
    /// variable index (0 if none), the subset size for GRAYCODE, or 1 for SORT.
    /// Returns false if `name` is not a combinatorics function. (Phase-F-final)
    fn runCombFunc(self: *Executor, target: []const u8, c: ast.Call) Error!bool {
        const eq = std.ascii.eqlIgnoreCase;
        const voff: usize =
            if (eq(c.name, "allcomb") or eq(c.name, "lexcomb") or eq(c.name, "lexperk") or eq(c.name, "lexcombi")) 2 else if (eq(c.name, "allperm") or eq(c.name, "lexperm") or eq(c.name, "graycode")) 1 else if (eq(c.name, "sort")) 0 else return false;
        const vargs = c.args[@min(voff, c.args.len)..];
        const old = try self.arena.alloc(Value, vargs.len);
        for (vargs, 0..) |*a, i| old[i] = try self.ev.eval(a);
        try self.runCall(c); // mutation (+ array-element write-back) via the CALL routine
        var ret: f64 = 0;
        if (eq(c.name, "sort")) {
            ret = 1;
        } else if (eq(c.name, "graycode")) {
            ret = if (c.args.len > 0) toF64(try self.ev.eval(&c.args[0])) else 0; // subset size
        } else {
            for (vargs, 0..) |*a, i| {
                const nv = try self.ev.eval(a);
                const changed = switch (old[i]) {
                    .num => |x| nv != .num or x != nv.num,
                    .str => |str| nv != .str or !std.mem.eql(u8, str, nv.str),
                };
                if (changed) {
                    ret = @floatFromInt(i + 1);
                    break;
                }
            }
        }
        try self.pdv.set(target, .{ .num = ret });
        return true;
    }

    /// CALL ALLCOMBI(n, k, index-1, …, index-k): advance the k index variables to the
    /// next combination of 1..n in minimal-change (revolving-door) order; index-1 = 0/
    /// missing initializes to 1..k. Indices are written ascending.
    fn callAllcombi(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const nf = toF64(try self.ev.eval(&c.args[0]));
        const kf = toF64(try self.ev.eval(&c.args[1]));
        const n: usize = combN(nf);
        const k: usize = combN(kf);
        if (k == 0 or k > n or c.args.len < 2 + k) return;
        const seq = revolvingDoor(self.arena, n, k) catch return;
        const asc = comptime std.sort.asc(usize);
        var pos: usize = 0;
        if (toF64(try self.ev.eval(&c.args[2])) >= 1) {
            const cur = try self.arena.alloc(usize, k);
            for (0..k) |i| {
                const v = toF64(try self.ev.eval(&c.args[2 + i]));
                cur[i] = @max(1, combN(v)); // 1-based index; out-of-range → 1 (BUG-combcallcrash)
            }
            std.mem.sort(usize, cur, {}, asc);
            for (seq, 0..) |combo, si| {
                const sc = try self.arena.dupe(usize, combo);
                std.mem.sort(usize, sc, {}, asc);
                var match = true;
                for (sc, cur) |x, y| if (x + 1 != y) {
                    match = false;
                    break;
                };
                if (match) {
                    pos = (si + 1) % seq.len;
                    break;
                }
            }
        }
        const outc = try self.arena.dupe(usize, seq[pos]);
        std.mem.sort(usize, outc, {}, asc);
        for (0..k) |i| if (c.args[2 + i] == .variable)
            try self.pdv.set(c.args[2 + i].variable, .{ .num = @floatFromInt(outc[i] + 1) });
    }

    /// Reset the RAND/ranuni shared stream to `seed` (the key must match the
    /// nextUniform stream in functions.zig) and remember it for STREAMREWIND.
    fn setRngStream(self: *Executor, seed: i64) Error!void {
        const s0 = if (seed > 0 and seed < 2147483647) seed else 1;
        inline for (.{ "\x00rngstream", "\x00rnginit" }) |key| {
            const gop = try self.ev.lag.getOrPut(self.ev.stateArena(), key);
            gop.value_ptr.* = .empty;
            try gop.value_ptr.append(self.ev.stateArena(), .{ .num = @floatFromInt(s0) });
        }
        // Drop the MT19937 RAND stream so STREAMINIT/STREAM always restart it, even
        // when re-seeded with the SAME seed (reproducibility) (BUG-randmersenne).
        if (self.ev.lag.getPtr("\x00mtstream")) |mt| mt.* = .empty;
    }

    /// CALL STREAMINIT(<seed | RNG-name>): seed the RAND stream (a string RNG name is
    /// accepted but ignored — one generator).
    fn callStreamInit(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 1) return;
        const v = try self.ev.eval(&c.args[0]);
        if (v == .num and !std.math.isNan(v.num)) try self.setRngStream(@intFromFloat(@trunc(v.num)));
    }

    /// CALL STREAM(key): select a reproducible RAND stream identified by `key`
    /// (approximated by reseeding — a single MINSTD generator, not 2^63 substreams).
    fn callStream(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 1) return;
        try self.setRngStream(@intFromFloat(@trunc(toF64(try self.ev.eval(&c.args[0])))));
    }

    /// CALL STREAMREWIND: reset the RAND stream to its initial (STREAMINIT) seed.
    fn rewindRngStream(self: *Executor) Error!void {
        const iv = self.ev.lag.get("\x00rnginit") orelse return;
        if (iv.items.len == 0) return;
        const gop = try self.ev.lag.getOrPut(self.ev.stateArena(), "\x00rngstream");
        gop.value_ptr.* = .empty;
        try gop.value_ptr.append(self.ev.stateArena(), iv.items[0]);
        // Also drop the MT19937 RAND stream so the next RAND reseeds from the
        // unchanged rnginit seed and restarts the sequence (BUG-randmersenne).
        if (self.ev.lag.getPtr("\x00mtstream")) |mt| mt.* = .empty;
    }

    /// CALL SOFTMAX(var-1, …, var-n): replace each numeric arg with its softmax
    /// value exp(xi)/Σexp(xj), in place.
    fn callSoftmax(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len == 0) return;
        const vals = try self.gatherVals(c.args);
        var sum: f64 = 0;
        for (vals) |v| sum += @exp(toF64(v));
        if (!(sum > 0)) return;
        const out = try self.arena.alloc(Value, vals.len);
        for (vals, 0..) |v, i| out[i] = .{ .num = @exp(toF64(v)) / sum };
        try self.writeVals(c.args, out);
    }

    /// CALL VNEXT(name <, type <, length>>): on each successive call, return the
    /// next PDV variable's name (blank once the list is exhausted), and optionally
    /// its type ("N"/"C") and length. A cursor on the Executor tracks the position.
    fn callVnext(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len == 0 or c.args[0] != .variable) return;
        if (self.vnext_idx < self.pdv.vars.items.len) {
            const v = self.pdv.vars.items[self.vnext_idx];
            self.vnext_idx += 1;
            try self.pdv.set(c.args[0].variable, .{ .str = try self.arena.dupe(u8, v.name) });
            if (c.args.len >= 2 and c.args[1] == .variable)
                try self.pdv.set(c.args[1].variable, .{ .str = if (v.type == .num) "N" else "C" });
            if (c.args.len >= 3 and c.args[2] == .variable) {
                const len: usize = if (v.type == .num) 8 else if (v.len > 0) v.len else 8;
                try self.pdv.set(c.args[2].variable, .{ .num = @floatFromInt(len) });
            }
        } else {
            try self.pdv.set(c.args[0].variable, .{ .str = "" });
        }
    }

    /// CALL SORTN/SORTC: sort the (numeric/character) argument variables ascending
    /// and write them back in place — the i-th smallest value goes to the i-th arg.
    fn callSort(self: *Executor, c: ast.Call, char: bool) Error!void {
        var names: std.ArrayList([]const u8) = .empty;
        for (c.args) |arg| try names.append(self.arena, if (arg == .variable) arg.variable else "");
        if (char) {
            var vals: std.ArrayList([]const u8) = .empty;
            for (c.args) |arg| try vals.append(self.arena, try self.arena.dupe(u8, try self.callArgStr(arg)));
            std.mem.sort([]const u8, vals.items, {}, strLessThan);
            for (names.items, vals.items) |nm, v| if (nm.len > 0) try self.pdv.set(nm, .{ .str = v });
        } else {
            var vals: std.ArrayList(f64) = .empty;
            for (c.args) |arg| try vals.append(self.arena, toF64(try self.ev.eval(&arg)));
            std.mem.sort(f64, vals.items, {}, numLessMissingFirst);
            for (names.items, vals.items) |nm, v| if (nm.len > 0) try self.pdv.set(nm, .{ .num = v });
        }
    }

    /// CALL SCAN(string, n, position, length [, delims [, modifiers]]): set
    /// `position` (1-based) and `length` of the n-th word (0/0 if none).
    /// Routes through the SAME word machinery as the SCAN function (BUG-callscanstale)
    /// so CALL SCAN and SCAN() agree on the default delimiter set and honor the
    /// m/k/i/t modifiers; unsupported modifiers (q/r/…) fail loud via wordSpec.
    fn callScan(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 4) return;
        const s0 = try self.callArgStr(c.args[0]);
        const nf = toF64(try self.ev.eval(&c.args[1]));
        var pos: f64 = 0;
        var len: f64 = 0;
        if (!std.math.isNan(nf)) {
            const list = if (c.args.len >= 5) try self.callArgStr(c.args[4]) else fns.word_delims;
            const mods = if (c.args.len >= 6) try self.callArgStr(c.args[5]) else "";
            if (try fns.wordSpec(self.ev, "SCAN", list, mods)) |spec| {
                const s = if (spec.trim) std.mem.trimEnd(u8, s0, " ") else s0;
                const toks = try fns.wordTokens(self.arena, s, &spec.set, spec.keep_empty);
                const count = toks.items.len;
                const n: i64 = @intFromFloat(@trunc(nf));
                if (count > 0 and n != 0) {
                    const idx: ?usize = if (n > 0) @intCast(n - 1) else blk: {
                        const fe = @as(i64, @intCast(count)) + n; // n<0 counts from the right
                        break :blk if (fe < 0) null else @as(usize, @intCast(fe));
                    };
                    if (idx) |ix| if (ix < count) {
                        const w = toks.items[ix];
                        pos = @floatFromInt(@intFromPtr(w.ptr) - @intFromPtr(s.ptr) + 1);
                        len = @floatFromInt(w.len);
                    };
                }
            } // wordSpec null → unsupported modifier already reported (D-002); leave 0/0
        }
        if (c.args[2] == .variable) try self.pdv.set(c.args[2].variable, .{ .num = pos });
        if (c.args[3] == .variable) try self.pdv.set(c.args[3].variable, .{ .num = len });
    }

    /// CALL CATS/CATT(result, item …): append the stripped (CATS) / trailing-
    /// trimmed (CATT) items to the current value of `result`.
    fn callCats(self: *Executor, c: ast.Call, strip_both: bool) Error!void {
        if (c.args.len < 1 or c.args[0] != .variable) return;
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(self.arena, self.curText(c.args[0].variable));
        for (c.args[1..]) |arg| {
            const it = try self.callArgStr(arg);
            try buf.appendSlice(self.arena, if (strip_both) std.mem.trim(u8, it, " ") else std.mem.trimEnd(u8, it, " "));
        }
        try self.pdv.set(c.args[0].variable, .{ .str = buf.items });
    }

    /// CALL CATX(separator, result, item …): append the non-blank stripped items
    /// to `result`, inserting `separator` before each appended item.
    fn callCatx(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 2 or c.args[1] != .variable) return;
        const sep = try self.callArgStr(c.args[0]);
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(self.arena, self.curText(c.args[1].variable));
        for (c.args[2..]) |arg| {
            const piece = std.mem.trim(u8, try self.callArgStr(arg), " ");
            if (piece.len == 0) continue; // CATX skips blank items
            if (buf.items.len > 0) try buf.appendSlice(self.arena, sep);
            try buf.appendSlice(self.arena, piece);
        }
        try self.pdv.set(c.args[1].variable, .{ .str = buf.items });
    }

    /// The current character value of a variable (trailing blanks dropped), "" if
    /// unset or numeric — the accumulator the CAT* CALL routines append onto.
    fn curText(self: *Executor, name: []const u8) []const u8 {
        return switch (self.pdv.get(name) orelse Value{ .str = "" }) {
            .str => |s| std.mem.trimEnd(u8, s, " "),
            .num => "",
        };
    }

    /// Snapshot each argument's value (char bytes duped so they survive reordering).
    fn gatherVals(self: *Executor, args: []const ast.Expr) Error![]Value {
        const out = try self.arena.alloc(Value, args.len);
        for (args, 0..) |arg, i| out[i] = switch (try self.ev.eval(&arg)) {
            .num => |x| .{ .num = x },
            .str => |s| .{ .str = try self.arena.dupe(u8, s) },
        };
        return out;
    }

    /// Write values back to whichever args are variables (positional).
    fn writeVals(self: *Executor, args: []const ast.Expr, vals: []const Value) Error!void {
        for (args, vals) |arg, v| if (arg == .variable) try self.pdv.set(arg.variable, v);
    }

    /// CALL STDIZE(<'METHOD=…' | 'range'|'std',> var …): standardize the numeric
    /// argument variables in place. Default / STD → mean 0, unit std dev. RANGE →
    /// (x-min)/(max-min), scaled to 0..1. The method may be given as "method=X"
    /// or as a bare method name X (BUG-callstdizerange). Any other method fails
    /// LOUD (BUG-callstdizemethod) — never silently apply the wrong method.
    /// Missing values are left untouched.
    fn callStdize(self: *Executor, c: ast.Call) Error!void {
        var range = false;
        var names: std.ArrayList([]const u8) = .empty;
        var xs: std.ArrayList(f64) = .empty;
        for (c.args) |arg| {
            const v = try self.ev.eval(&arg);
            if (v == .str) { // a method/option token: "method=X" or a bare method name X
                const opt = std.mem.trim(u8, v.str, " ");
                const m = if (std.ascii.indexOfIgnoreCase(opt, "method=")) |i|
                    std.mem.trim(u8, opt[i + "method=".len ..], " ")
                else
                    opt;
                if (std.ascii.eqlIgnoreCase(m, "range")) {
                    range = true;
                } else if (!std.ascii.eqlIgnoreCase(m, "std")) {
                    // SPLIT (audit-exitcodecontract.md §5c): the Functions ref
                    // closes the option set (printed p.419-421), and an option
                    // may carry an `=value` tail (`MULT=2`, `L=1.5`), so match on
                    // the keyword before the '='. Documented → our gap, rc 2;
                    // `medain` → the user's typo, rc 1. Message unchanged.
                    const kw = m[0 .. std.mem.indexOfScalar(u8, m, '=') orelse m.len];
                    if (stdizeOptKind(kw)) |kind| {
                        diag.markGap();
                        // BUG-callstdizeoptmsg: the message used to call EVERY
                        // rejected option a METHOD, so `mult=2` rendered as the
                        // nonsense `CALL STDIZE METHOD=mult=2`. Two of the
                        // reference's three categories are not methods — a
                        // VARDEF-option is a variance DIVISOR (DF/N) and a
                        // miscellaneous-option is a post-scaling knob or flag
                        // (MULT=, FUZZ=, NORM, PSTAT, …) — so name the option
                        // instead of mislabelling it.
                        if (kind != .standardization) {
                            self.diags.report(.err, 0, "CALL STDIZE option {s} is not supported yet", .{m}) catch {};
                            return error.ExecError;
                        }
                    }
                    // A standardization-option, or an unrecognised token: a bare
                    // unknown keyword is most likely a mistyped method, and that
                    // stays the user's error (rc 1 — no markGap above).
                    self.diags.report(.err, 0, "CALL STDIZE METHOD={s} is not supported yet", .{m}) catch {};
                    return error.ExecError;
                }
                continue;
            }
            try names.append(self.arena, if (arg == .variable) arg.variable else "");
            try xs.append(self.arena, v.num);
        }
        if (range) return self.stdizeRange(names.items, xs.items);
        var sum: f64 = 0;
        var cnt: usize = 0;
        for (xs.items) |x| if (!std.math.isNan(x)) {
            sum += x;
            cnt += 1;
        };
        if (cnt == 0) return;
        const mean = sum / @as(f64, @floatFromInt(cnt));
        var ss: f64 = 0;
        for (xs.items) |x| if (!std.math.isNan(x)) {
            ss += (x - mean) * (x - mean);
        };
        const sd = if (cnt >= 2) @sqrt(ss / @as(f64, @floatFromInt(cnt - 1))) else 0;
        for (names.items, xs.items) |nm, x| if (nm.len > 0) {
            if (std.math.isNan(x)) continue; // missing stays missing
            try self.pdv.set(nm, .{ .num = if (sd != 0) (x - mean) / sd else 0 });
        };
    }

    /// METHOD=RANGE: (x-min)/(max-min) → 0..1; equal min/max → 0. Missing untouched.
    fn stdizeRange(self: *Executor, names: [][]const u8, xs: []const f64) Error!void {
        var lo: f64 = std.math.inf(f64);
        var hi: f64 = -std.math.inf(f64);
        for (xs) |x| if (!std.math.isNan(x)) {
            lo = @min(lo, x);
            hi = @max(hi, x);
        };
        if (lo > hi) return; // no non-missing values
        const span = hi - lo;
        for (names, xs) |nm, x| if (nm.len > 0) {
            if (std.math.isNan(x)) continue;
            try self.pdv.set(nm, .{ .num = if (span != 0) (x - lo) / span else 0 });
        };
    }

    /// CALL RANPERM(seed, var …): randomly permute the argument variables in place
    /// (Fisher-Yates over the SAS RANUNI stream); `seed` is updated to the new state.
    fn callRanperm(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 2) return;
        var st = seedState(toF64(try self.ev.eval(&c.args[0])));
        const vals = try self.gatherVals(c.args[1..]);
        var i = vals.len;
        while (i > 1) : (i -= 1) {
            const j = @min(i - 1, @as(usize, @intFromFloat(lehmerNext(&st) * @as(f64, @floatFromInt(i)))));
            std.mem.swap(Value, &vals[i - 1], &vals[j]);
        }
        try self.writeVals(c.args[1..], vals);
        if (c.args[0] == .variable) try self.pdv.set(c.args[0].variable, .{ .num = @floatFromInt(st) });
    }

    /// CALL RANPERK(seed,k,var …) / RANCOMB: a random k-permutation (or, for a
    /// combination, sorted) of the values lands in the first k variables.
    fn callRankSelect(self: *Executor, c: ast.Call, comb: bool) Error!void {
        if (c.args.len < 3) return;
        var st = seedState(toF64(try self.ev.eval(&c.args[0])));
        const kf = toF64(try self.ev.eval(&c.args[1]));
        const vals = try self.gatherVals(c.args[2..]);
        const n = vals.len;
        const kk = @min(combN(kf), n); // user k; out-of-range → 0 (BUG-combcallcrash)
        for (0..kk) |i| { // partial Fisher-Yates: choose the i-th of k
            // lehmerNext ∈ [0,1) so this product is internally bounded [0, n-i) — no toInt guard needed.
            const j = i + @as(usize, @intFromFloat(lehmerNext(&st) * @as(f64, @floatFromInt(n - i))));
            std.mem.swap(Value, &vals[i], &vals[@min(j, n - 1)]);
        }
        if (comb) std.mem.sort(Value, vals[0..kk], {}, valLess);
        try self.writeVals(c.args[2..], vals);
        if (c.args[0] == .variable) try self.pdv.set(c.args[0].variable, .{ .num = @floatFromInt(st) });
    }

    /// CALL ALLPERM(count, var …): the count-th permutation in SAS's minimal-change
    /// (Steinhaus-Johnson-Trotter) order — BUG-allpermorder. Stateless: the value
    /// set is recovered by sorting, then the rank is Trotter-Johnson-unranked.
    fn callAllperm(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 2) return;
        const count = toF64(try self.ev.eval(&c.args[0]));
        const vals = try self.gatherVals(c.args[1..]);
        const n = vals.len;
        if (n == 0 or n > 19) return self.writeVals(c.args[1..], vals);
        const sorted = try self.arena.dupe(Value, vals);
        std.mem.sort(Value, sorted, {}, valLess);
        var total: usize = 1;
        for (1..n + 1) |m| total *= m; // n! (n ≤ 19 fits u64)
        const rank = combRank(usize, count, total - 1);
        const idx = try self.arena.alloc(usize, n);
        tjUnrank(idx, n, rank);
        const out = try self.arena.alloc(Value, n);
        for (0..n) |i| out[i] = sorted[idx[i]];
        try self.writeVals(c.args[1..], out);
    }

    /// CALL ALLCOMB(count, k, var …): the count-th k-combination in SAS's
    /// revolving-door (minimal-change) order — BUG-allpermorder. Each successive
    /// combination differs from the previous by exactly one element.
    fn callAllcomb(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const cf = toF64(try self.ev.eval(&c.args[0]));
        const kf = toF64(try self.ev.eval(&c.args[1]));
        const vals = try self.gatherVals(c.args[2..]);
        const n = vals.len;
        const k = combN(kf);
        if (k == 0 or k > n or binom(n, k) > 100_000) return self.callLexcomb(c);
        const sorted = try self.arena.dupe(Value, vals);
        std.mem.sort(Value, sorted, {}, valLess);
        const seq = try revolvingDoor(self.arena, n, k);
        const rank = combRank(usize, cf, seq.len - 1);
        try self.placeCombo(c.args[2..], sorted, seq[rank]);
    }

    /// Write the combination `combo` (indices into `sorted`) into the first
    /// variables, the complement after — shared by ALLCOMB and LEXCOMB.
    fn placeCombo(self: *Executor, args: []const ast.Expr, sorted: []const Value, combo: []const usize) Error!void {
        const in_combo = try self.arena.alloc(bool, sorted.len);
        @memset(in_combo, false);
        for (combo) |ci| in_combo[ci] = true;
        const out = try self.arena.alloc(Value, sorted.len);
        var oi: usize = 0;
        for (combo) |ci| {
            out[oi] = sorted[ci];
            oi += 1;
        }
        for (0..sorted.len) |ci| if (!in_combo[ci]) {
            out[oi] = sorted[ci];
            oi += 1;
        };
        try self.writeVals(args, out);
    }

    /// CALL LEXCOMB(count, k, var …): put the count-th lexicographic k-combination
    /// of the values into the first k variables (the rest follow). Stateless: the
    /// value set is recovered by sorting, so it works across a loop.
    fn callLexcomb(self: *Executor, c: ast.Call) Error!void {
        if (c.args.len < 3) return;
        const cf = toF64(try self.ev.eval(&c.args[0]));
        const kf = toF64(try self.ev.eval(&c.args[1]));
        const vals = try self.gatherVals(c.args[2..]);
        const n = vals.len;
        const k = combN(kf);
        if (k == 0 or k > n) return self.writeVals(c.args[2..], vals);
        const sorted = try self.arena.dupe(Value, vals);
        std.mem.sort(Value, sorted, {}, valLess);
        const total = binom(n, k);
        const rank = combRank(usize, cf, if (total > 0) total - 1 else 0);
        // unrank the k-combination of indices at this lexicographic rank
        const combo = try self.arena.alloc(usize, k);
        var x: usize = 0;
        var r = rank;
        for (0..k) |i| {
            while (binom(n - 1 - x, k - 1 - i) <= r) {
                r -= binom(n - 1 - x, k - 1 - i);
                x += 1;
            }
            combo[i] = x;
            x += 1;
        }
        try self.placeCombo(c.args[2..], sorted, combo);
    }

    /// Evaluate a CALL argument to text: a char stays as-is; a numeric renders
    /// with the default (BEST) format, as SYMPUT does.
    fn callArgStr(self: *Executor, e: ast.Expr) Error![]const u8 {
        return switch (try self.ev.eval(&e)) {
            .str => |s| s,
            .num => |x| try format.bestNum(self.arena, x),
        };
    }

    /// `a{i} = expr;` — write the value into the i-th (1-based) member variable.
    /// An out-of-range subscript is an execution-time ERROR that sets _ERROR_=1
    /// and halts the step (BUG-arrwriteoor) — identical to the READ path
    /// (BUG-arrayoorerror, eval.zig subscriptOor); SAS 9.4 stops on both.
    fn runArrayAssign(self: *Executor, aa: ast.ArrayAssign) Error!void {
        // A special-list array (`array v{*} _numeric_;`) resolves its members from
        // the live PDV so writes bind to the real variables, not phantoms (GH#48).
        const elements = if (aa.array.special) |k| try eval.specialArrayNames(self.arena, self.pdv, k) else aa.array.elements;
        const x = toF64(try self.ev.eval(aa.array.index));
        const xf = @floor(x);
        // The parser folds `{lo:hi}` subscripts to 1-based offsets at parse time
        // (ARRAY-lobound), so the span is always 1..N — an in-span write via a
        // negative lower bound (b[-1] in b[-1:1]) never reaches this check.
        // A MISSING (NaN) subscript is out of range too (BUG-arraysubmissing): NaN
        // fails every `<`/`>` compare, so it slips past the span check unless caught
        // explicitly — a silent no-op write was the bug. Fail loud like the read path.
        if (std.math.isNan(x) or xf < 1 or xf > @as(f64, @floatFromInt(elements.len))) {
            self.ev.setError() catch {}; // _ERROR_=1; losing it to OOM doesn't soften the abort
            // aa.array.line = source line of the reference (NOTE-arrayoorlineno; 0 = unknown; tokens carry no column).
            return self.diags.fail(error.ExecError, aa.array.line, "Array subscript {d} out of range for {s} at line {d} column 0.", .{ xf, aa.array.name, aa.array.line });
        }
        const i: usize = @intFromFloat(xf);
        try self.pdv.set(elements[i - 1], try self.ev.eval(aa.value));
    }

    /// `substr(v, pos <, len>) = value;` — splice `value` into `v`'s char value at
    /// [pos, pos+len), leaving the rest untouched (BUG-substrlvalue). A position
    /// past the string, or a non-positive pos/len, is a no-op (as SAS, with a NOTE).
    fn runSubstrAssign(self: *Executor, sa: ast.SubstrAssign) Error!void {
        var cur = self.curText(sa.target);
        // An OMITTED-length SUBSTR lvalue spans to the target's DECLARED width, so
        // the splice window reaches the declared end (SAS) — pad the working copy to
        // `vr.len` first (BUG-substrlvalue-declared). Was: window limited to the
        // current (trimmed) length, so `substr(t $5, 2)='XXXX'` wrote only 1 char →
        // `aX` instead of `aXXXX` (data loss). An EXPLICIT length is untouched; a var
        // with no declared LENGTH (len==0) keeps current behavior. ponytail: local to
        // this path — global fixed-width char storage is the deferred EPIC-charfixedwidth.
        if (sa.len == null) {
            const declared = if (self.pdv.indexOf(sa.target)) |ix| self.pdv.vars.items[ix].len else 0;
            if (declared > cur.len) {
                const padded = try self.arena.alloc(u8, declared);
                @memcpy(padded[0..cur.len], cur);
                @memset(padded[cur.len..], ' ');
                cur = padded;
            }
        }
        const pf = toF64(try self.ev.eval(sa.pos));
        if (std.math.isNan(pf) or pf < 1) return;
        const p0 = @as(usize, @intFromFloat(@floor(pf))) - 1; // 0-based start
        if (p0 >= cur.len) {
            self.diags.note(0, "SUBSTR: position past the value of {s} — assignment ignored", .{sa.target}) catch {};
            return;
        }
        const avail = cur.len - p0; // can't extend the string
        const n: usize = if (sa.len) |le| blk: {
            const lf = toF64(try self.ev.eval(le));
            break :blk if (std.math.isNan(lf) or lf < 0) avail else @min(@as(usize, @intFromFloat(@floor(lf))), avail);
        } else avail;
        // the replacement text (char RHS; a numeric RHS is rendered compactly)
        const repl = switch (try self.ev.eval(sa.value)) {
            .str => |s| s,
            .num => |x| try std.fmt.allocPrint(self.arena, "{d}", .{x}),
        };
        const w = repl[0..@min(n, repl.len)]; // write min(len, value) chars, rest of window unchanged
        var buf: std.ArrayList(u8) = .empty;
        try buf.appendSlice(self.arena, cur[0..p0]);
        try buf.appendSlice(self.arena, w);
        try buf.appendSlice(self.arena, cur[p0 + w.len ..]);
        try self.pdv.set(sa.target, .{ .str = buf.items });
        // `substr(_infile_,…) =` edits the held record too (BUG-infilevarnoop).
        if (eqi(sa.target, "_infile_")) self.writeInfileBuffer(buf.items);
    }

    // ── hash objects ─────────────────────────────────────────────────────
    fn findHash(self: *Executor, name: []const u8) ?*HashObject {
        for (self.hashes.items) |h| if (std.ascii.eqlIgnoreCase(h.name, name)) return h;
        return null;
    }

    /// `declare hash h(...);` — register an empty object. ponytail: the `dataset:`
    /// argument (load a table on declare) is not honoured yet; the corpus builds
    /// its hash with `add`. Re-declaring each iteration just resets it (fine for
    /// the single-iteration steps the corpus uses).
    fn hashDeclare(self: *Executor, d: ast.HashDecl) Error!void {
        // A hash object persists across DATA-step iterations (SAS builds it once
        // and it lives for the whole step). `declare` re-executed on a later row
        // must NOT wipe it — keep the existing object so lookup-joins see the data
        // added on earlier rows (BUG-hashpersist). Constructor args still apply to
        // the existing object (idempotent), so `declare hash h;` followed by
        // `h = _new_ hash(ordered:'a');` picks the options up (GAP-hashnew).
        const h = self.findHash(d.name) orelse blk: {
            const nh = try self.arena.create(HashObject);
            nh.* = .{ .name = d.name };
            try self.hashes.append(self.arena, nh);
            break :blk nh;
        };
        // Whitelist the constructor tags SAS defines (BUG-hashunknownarg): a
        // misspelled tag (`odered:` for `ordered:`) used to be silently
        // IGNORED — the hash ran with default behavior and no hint.
        //
        // The list is the DOC'S, not a guess: SAS 9.4 Component Objects
        // Reference, "DECLARE Statement: Hash and Hash Iterator Objects"
        // (printed p.30-33) — "There are seven valid hash object argument and
        // value tags", then names them: dataset, duplicate, hashexp, keysum,
        // multidata, ordered, suminc. KEYSUM was MISSING from this list, so a
        // LEGAL `keysum:'v'` drew a factually WRONG "undefined argument tag"
        // ERROR. keysum is a real tag we do not IMPLEMENT — that is the
        // suminc: case below, not this one. hashexp: is a benign perf hint:
        // accepted, not honored (hash sizing is automatic here).
        //
        // AUDIT-errhaltclass: this HALTS rather than reporting and running on.
        // An undefined tag means the object is not the one the program asked
        // for, and it was then used anyway — the BUG-hashexprdeferredhalt shape,
        // and the ERROR class of Language Reference: Concepts printed p.174-175 (Example Code 8.6:
        // "stopped processing this step" + "was not replaced"). Two diags.fail
        // siblings already live in this very function (the hiter arms below).
        for (d.args) |arg| if (arg.name) |nm| {
            const known = eqi(nm, "dataset") or eqi(nm, "ordered") or eqi(nm, "duplicate") or
                eqi(nm, "multidata") or eqi(nm, "hashexp") or eqi(nm, "suminc") or eqi(nm, "keysum");
            if (!known)
                return self.diags.fail(error.ExecError, 0, "hash constructor: undefined argument tag '{s}:'", .{nm});
        };
        // `declare hiter hi("h")` — one positional string arg names the hash to
        // walk (the constructor's other forms all use `name:` arguments).
        // Language Reference: Concepts p.624: the name MUST be quoted, and the hash must be declared
        // BEFORE the iterator. Both used to be dropped on the floor (an unquoted
        // arg evaluates numeric; an unknown name found no hash), leaving an
        // UNBOUND iterator whose every first()/next() returned rc=1 with no
        // diagnostic — an empty walk and an empty dataset at exit 0
        // (BUG-hiterbadhash). Fail loud like the unknown-tag/unknown-method
        // paths of the same family.
        if (d.args.len == 1 and d.args[0].name == null) {
            const v = try self.ev.eval(d.args[0].value);
            if (v != .str)
                return self.diags.fail(error.ExecError, 0, "hash iterator {s}: the hash object name must be a quoted string — declare hiter {s}('hashname')", .{ d.name, d.name });
            if (self.findHash(v.str) == null)
                return self.diags.fail(error.ExecError, 0, "hash iterator {s}: hash object '{s}' is not declared (declare the hash before the iterator)", .{ d.name, v.str });
            h.iter_of = v.str;
        }
        // `declare hash h(dataset:"name")` — remember the source table; its rows
        // are loaded into the hash on defineDone (BUG-hashdataset).
        for (d.args) |arg| if (arg.name) |nm| if (eqi(nm, "dataset")) {
            const v = try self.ev.eval(arg.value);
            // NOTE-declarehashtrim: trim like hashOutput (BUG-hashoutputnametrim)
            // — the same computed-name idiom (`'w' || nm`, nm blank-padded) must
            // not miss an EXISTING member at the declare end: untrimmed it
            // errored 'hash dataset woo       not found' (loud but wrong).
            if (v == .str) h.src = std.mem.trim(u8, v.str, " ");
        };
        // `declare hash h(ordered:'a')` — keep entries in ascending/descending key
        // order for iteration and output (BUG-hashordered). SAS accepts a quoted
        // 'a'/'ascending'/'yes'/'y'/'d'/'descending'/'n'/'no' or a numeric boolean.
        for (d.args) |arg| if (arg.name) |nm| if (eqi(nm, "ordered")) {
            h.ordered = parseHashOrder(try self.ev.eval(arg.value));
        };
        // `declare hash h(multidata:'y')` — allow MULTIPLE data records per key:
        // add() always succeeds, find()/find_next() walk the key's records in
        // insertion order (BUG-hashmultidata — was parsed, then silently ignored,
        // dropping every duplicate-key record with no error). SAS takes 'y'/'yes'
        // (case-insensitive) or a numeric boolean.
        for (d.args) |arg| if (arg.name) |nm| if (eqi(nm, "multidata")) {
            h.multidata = switch (try self.ev.eval(arg.value)) {
                .str => |s| blk: {
                    const s2 = std.mem.trim(u8, s, " ");
                    break :blk eqi(s2, "y") or eqi(s2, "yes");
                },
                .num => |x| x != 0,
            };
        };
        // `declare hash h(duplicate:'r')` — a duplicate-key add REPLACES the
        // stored record ('r'/'replace', last wins) or logs an ERROR
        // ('e'/'error'); absent → keep the first, SAS's default
        // (BUG-hashduplicate — was parsed, then silently dropped).
        for (d.args) |arg| if (arg.name) |nm| if (eqi(nm, "duplicate")) {
            const v = try self.ev.eval(arg.value);
            if (v == .str) {
                const s = std.mem.trim(u8, v.str, " ");
                h.duplicate = if (eqi(s, "r") or eqi(s, "replace")) .replace else if (eqi(s, "e") or eqi(s, "error")) .err else .keep_first;
            }
        };
        // `declare hash h(suminc:'cnt')` / `(keysum:'v')` — per-key summaries
        // (SUM/SUMDUP, and the FIND-count keysum variable) are NOT supported,
        // and the tag used to be dropped SILENTLY: a program relying on the
        // maintained summary then computed garbage with no hint
        // (GAP-hashmethods).
        //
        // AUDIT-errhaltclass: reporting loud and then RUNNING ON is still a
        // no-op — the step computed that garbage and WROTE IT, and the nonzero
        // exit does not travel with the data set. CLAUDE.md's "an unsupported
        // feature must error visibly, never no-op" is only half-kept by an
        // ERROR the step ignores, so the step stops here (Language Reference: Concepts printed
        // p.174-175). keysum joins suminc: both name a key summary we do not
        // maintain, and both are LEGAL tags (component-objects ref printed
        // p.32-33) — so they must be rejected as UNSUPPORTED, not as undefined.
        for (d.args) |arg| if (arg.name) |nm| {
            // Both tags are LEGAL (component-objects ref printed p.32-33, as the
            // comment above says) — valid SAS we don't maintain, so rc 2 (D-009).
            if (eqi(nm, "suminc"))
                return failGap(self.diags, "hash suminc: key summaries (sum/sumdup) are not supported yet", .{});
            if (eqi(nm, "keysum"))
                return failGap(self.diags, "hash keysum: key summaries are not supported yet", .{});
        };
    }

    /// Dispatch a hash method; write the return code to `op.target` if present.
    ///
    /// Invariant (BUG-hashexprdeferredhalt, SUPERSEDES the GAP-hashmethods
    /// "defined non-zero rc" rule of 991ba598): a hash failure reported at ERROR
    /// severity STOPS THE STEP where it happens — it does not fabricate an rc and
    /// run on. GAP-hashmethods aimed at the right target ("wrong branch after a
    /// visible error") and missed: setting rc=1 makes the value DEFINED but still
    /// INVENTED, so `if h.find() = 1 then …` took the branch on the error code
    /// itself, ran the rest of the step, and wrote the observation — the ERROR only
    /// surfaced afterwards. The cure for a wrong branch is not to reach it.
    ///
    /// Language Reference: Concepts printed p.172 (Chapter 8, "Execution-Time Errors") splits the classes:
    /// "Most execution-time errors produce warning messages or notes in the SAS log
    /// but allow the program to continue executing", with footnote 1 — "more serious
    /// errors can cause SAS to enter syntax check mode and stop processing the
    /// program". Printed p.173-174 shows the continuing class (division by 0: "SAS
    /// executes the entire step, assigns a missing value"), and printed p.174-175
    /// Example Code 8.6 shows the ERROR class — the log reads "ERROR: Array subscript
    /// out of range", then "NOTE: The SAS System stopped processing this step because
    /// of errors" and "WARNING: Data set WORK.TEST was not replaced because this step
    /// was stopped". These are ERRORs, so they take the p.174-175 path. That exact
    /// example is already how opensas treats an out-of-range subscript (runArrayAssign
    /// `diags.fail`), so this only brings hash into line with the sibling the volume
    /// uses to DEFINE the class.
    fn hashOp(self: *Executor, op: ast.HashCall) Error!void {
        const h = self.findHash(op.obj) orelse
            return self.diags.fail(error.ExecError, 0, "hash object {s} is not declared", .{op.obj});
        var rc: f64 = 0;
        if (eqi(op.method, "defineKey")) {
            // ignore re-definition once the object is built (declare/define run
            // each iteration when not guarded by `if _n_=1`) — BUG-hashpersist.
            if (!h.done) try self.defineArgNames(h, &h.keys, true, op.args);
        } else if (eqi(op.method, "defineData")) {
            if (!h.done) try self.defineArgNames(h, &h.datas, false, op.args);
        } else if (eqi(op.method, "defineDone")) {
            if (!h.done) { // build once — load the dataset: source now that keys/data are known
                h.done = true;
                try self.hashDefineCheckNames(h);
                try self.hashLoadDataset(h);
            }
        } else if (eqi(op.method, "add")) {
            rc = try self.hashAdd(h, op.args);
        } else if (eqi(op.method, "replace")) {
            rc = try self.hashReplace(h, op.args);
        } else if (eqi(op.method, "find")) {
            rc = try self.hashFind(h, op.args);
        } else if (eqi(op.method, "find_next")) {
            rc = try self.hashFindNext(h);
        } else if (eqi(op.method, "check")) {
            rc = try self.hashCheck(h, op.args);
        } else if (eqi(op.method, "remove")) {
            rc = try self.hashRemove(h, op.args);
        } else if (eqi(op.method, "output")) {
            rc = try self.hashOutput(h, op.args);
        } else if (eqi(op.method, "first")) {
            rc = try self.hashIterMove(h, .first);
        } else if (eqi(op.method, "next")) {
            rc = try self.hashIterMove(h, .next);
        } else if (eqi(op.method, "last")) {
            rc = try self.hashIterMove(h, .last);
        } else if (eqi(op.method, "prev")) {
            rc = try self.hashIterMove(h, .prev); // GAP-hashitermethods
        } else if (eqi(op.method, "clear")) {
            // SAS CLEAR (GAP-hashitermethods): remove every item; the object
            // stays usable. A bound hiter's cursor is now out of range, so its
            // next move reports exhaustion — coherent, never a stale read.
            h.entries.clearRetainingCapacity();
            h.index.clearRetainingCapacity();
            h.md_key = null; // find_next after clear must not walk stale records
            // a bound hiter's cursor is off the (now empty) entries — not
            // positioned on any key, so p.621's remove-guard must not fire.
            for (self.hashes.items) |*it| if (it.*.iter_of) |b| {
                if (eqi(b, h.name)) it.*.iter_on = false;
            };
            rc = 0;
        } else if (eqi(op.method, "delete")) {
            // SAS DELETE (GAP-hashitermethods): retire the object. Entries live
            // in the arena, so "freeing" is unregistering: later ops on the name
            // hit the loud "hash object is not declared" path above; a re-declare
            // builds a fresh empty object.
            for (self.hashes.items, 0..) |x, i| if (x == h) {
                _ = self.hashes.orderedRemove(i);
                break;
            };
            rc = 0;
        } else if (eqi(op.method, "num_items") or eqi(op.method, "item_size")) {
            // Language Reference: Concepts p.623 hash ATTRIBUTES — reachable parenless (`n = h.num_items;`)
            // or as `h.num_items()`; both land here with an empty arg list
            // (GAP-hashnumitems).
            if (op.args.len != 0) {
                return self.diags.fail(error.ExecError, 0, "hash attribute {s} takes no arguments", .{op.method});
            } else if (eqi(op.method, "num_items")) {
                rc = @floatFromInt(h.entries.items.len); // live item count
            } else {
                rc = @floatFromInt(self.hashItemSize(h));
            }
        } else if (isHashMethod(op.method)) {
            // SPLIT (audit-exitcodecontract.md §5c): a method the Component
            // Objects reference's own dictionary NAMES is valid SAS we haven't
            // written → gap, rc 2. A typo'd method falls to the arm below and
            // stays rc 1 — re-tagging the whole catch-all would tell a user who
            // wrote `h.fnd()` to file an opensas issue.
            return failGap(self.diags, "hash method {s}() is not supported yet", .{op.method});
        } else {
            return self.diags.fail(error.ExecError, 0, "hash method {s}() is not supported yet", .{op.method});
        }
        if (op.target) |tgt| try self.pdv.set(tgt, .{ .num = rc });
    }

    /// Approximate per-item byte size for `h.item_size` (Language Reference: Concepts p.623): the sum
    /// of the key + data variable widths. ponytail: SAS's true ITEM_SIZE adds
    /// internal per-item overhead the doc doesn't pin down — doc-finder tick116
    /// F3 records "approx ok"; refine only if a program compares against SAS's.
    fn hashItemSize(self: *Executor, h: *HashObject) usize {
        var n: usize = 0;
        for (h.keys.items) |nm| n += self.hashVarWidth(nm);
        for (h.datas.items) |nm| n += self.hashVarWidth(nm);
        return n;
    }

    /// Storage width of one hash key/data variable: a char's declared length
    /// (undeclared → SAS's default 8), a numeric always 8.
    fn hashVarWidth(self: *Executor, name: []const u8) usize {
        if (self.pdv.indexOf(name)) |i| {
            const v = self.pdv.vars.items[i];
            if (v.type == .char and v.len > 0) return v.len;
        }
        return 8;
    }

    /// NOTE-hashofhash (tick164): a defineData'd name that IS a declared hash
    /// object (`inner = _new_ hash();` registers the object, never a PDV var)
    /// falls through to `orelse .missing` / an absent source column and stores a
    /// SILENT numeric missing, which a later find() hands back as `inner=.` at
    /// exit 0. Nested-hash storage is unsupported — fail loud instead of writing
    /// garbage into the entry. A hash of hashes IS documented SAS (Language Reference: Concepts), so
    /// this is our gap: rc 2, not a user error.
    ///
    /// BUG-hashofhashexplicit: ONE predicate, called from the two places a data
    /// tuple can be built, because they do not share a call path — defineDone
    /// (which covers the `dataset:` bulk load, every keyed method, and BOTH the
    /// implicit and explicit `data:` spellings) and collectArgs (which is all
    /// that is left when a program never calls defineDone). It used to live
    /// inside collectArgs' IMPLICIT-form branch alone, so `h.add(key: 1, data: x)`
    /// and the `dataset:` load both walked straight past it.
    fn hashRejectNestedData(self: *Executor, names: []const []const u8) Error!void {
        for (names) |nm| if (self.findHash(nm) != null)
            return failGap(self.diags, "hash-valued data items (nested hash) are not supported: {s}", .{nm});
    }

    /// Language Reference: Concepts p.613: "If you use a key or data variable without declaring or
    /// initializing that key or data variable outside the hash object, an error
    /// occurs." A typo'd defineKey/defineData name used to return rc=0, after
    /// which find() reported a HIT (rc=0) while restoring nothing — and pdv.set
    /// materialised a PHANTOM column of all-missing (BUG-hashdefinenovar — the
    /// bare-positional-name half of BUG-hashdefinetag's stated fix, which never
    /// landed). Checked at defineDone, not at the define* calls: the
    /// compile-time PDV already holds every LENGTH/assignment/SET/RETAIN/array
    /// name regardless of textual order (p.625's own example lengths the key
    /// inside the same block), and the `dataset:` source's columns are the
    /// second legal name universe (hashLoadDataset runs next).
    fn hashDefineCheckNames(self: *Executor, h: *HashObject) Error!void {
        for (h.keys.items) |nm| try self.hashDefineCheckOne(h, nm, "key");
        for (h.datas.items) |nm| try self.hashDefineCheckOne(h, nm, "data");
    }

    fn hashDefineCheckOne(self: *Executor, h: *HashObject, nm: []const u8, kind: []const u8) Error!void {
        if (self.pdv.indexOf(nm) != null) return;
        // A hash OBJECT named as data. This used to DEFER to the add-time
        // collectArgs path ("let it speak") — but that path only spoke for the
        // implicit `h.add()` spelling, so `h.add(key: 1, data: inner)` and the
        // `dataset:` bulk load (which never calls collectArgs at all) both
        // stored a silent missing at exit 0. Say it here, where every spelling
        // and every method must pass first (BUG-hashofhashexplicit).
        if (eqi(kind, "data")) try self.hashRejectNestedData(&.{nm});
        if (h.src) |src| if (self.lib.find(src)) |ds| {
            for (ds.columns.items) |c| if (eqi(c.name, nm)) return;
        };
        return self.diags.fail(error.ExecError, 0, "hash define: {s} variable '{s}' is not declared or initialized outside the hash object", .{ kind, nm });
    }

    /// Load every row of the `dataset:"name"` source into the hash: key tuple from
    /// the defineKey columns, data tuple from the defineData columns. Duplicate
    /// keys follow `duplicate:` — keep first (SAS default), replace (last wins),
    /// or log an ERROR (BUG-hashduplicate);
    /// with multidata:'y' every row loads (BUG-hashmultidata).
    fn hashLoadDataset(self: *Executor, h: *HashObject) Error!void {
        const src = h.src orelse return;
        // AUDIT-errhaltclass: a `dataset:` that names no table HALTS. Reporting
        // and returning left an EMPTY hash that the step then used: every
        // find() missed, every defineData variable stayed MISSING, and the step
        // wrote those fabricated missings to its output data set (verified: a
        // libname-backed step exited 1 and still left `k=1,v=.,flag=WROTE` on
        // disk, which a separate run reads back at exit 0). Same class as
        // BUG-hashexprdeferredhalt. The asymmetry was inside the hash family
        // itself: defineArgNames' `all:'y'` arm raises the IDENTICAL message
        // ("hash dataset {s} not found") via diags.fail and halts, so the same
        // missing table killed the step or not depending on whether the program
        // wrote `defineData(all:'y')` or named its columns.
        const ds = self.lib.find(src) orelse
            return self.diags.fail(error.ExecError, 0, "hash dataset {s} not found", .{src});
        for (0..ds.rowCount()) |ri| {
            const row = ds.row(ri);
            const kv = try self.arena.alloc(Value, h.keys.items.len);
            for (h.keys.items, 0..) |k, j| kv[j] = colVal(ds, row, k);
            const dup: ?usize = if (h.multidata) null else h.index.getContext(kv, .{});
            if (dup != null) switch (h.duplicate) {
                .keep_first => continue, // duplicate key → keep first
                .err => { // duplicate:'e' — log the documented ERROR, keep first
                    // SEV-rcbydesignerr: rcErr — recoverable. printed p.32:
                    // 'error'/'e' "reports an error to the log if a duplicate
                    // key is found"; the Note (pp.31-32) stores the first
                    // instance and ignores subsequent ones. A data condition
                    // the tag itself defines as report-and-continue must not
                    // errhalt-skip later steps.
                    self.diags.rcErr(0, "hash dataset {s}: duplicate key (duplicate:'e')", .{src}) catch {};
                    continue;
                },
                .replace => {}, // duplicate:'r' — fall through, overwrite below
            };
            const dv = try self.arena.alloc(Value, h.datas.items.len);
            for (h.datas.items, 0..) |dnm, j| dv[j] = colVal(ds, row, dnm);
            if (dup) |slot| { // duplicate:'r' → LAST record wins
                h.entries.items[slot].datavals = dv;
                continue;
            }
            try h.entries.append(self.arena, .{ .keyvals = kv, .datavals = dv });
            const gop = try h.index.getOrPutContext(self.arena, kv, .{});
            if (!gop.found_existing) gop.value_ptr.* = h.entries.items.len - 1; // keep FIRST slot per key
        }
    }

    /// Rebuild the key→slot index from the ordered entries — after any op that
    /// reorders slots (a `remove`'s orderedRemove shift, or an `ordered:` sort), so
    /// the index can never go stale (PERF-hashscan). ponytail: O(n); fine because
    /// only remove and ordered-iteration/output trigger it, both rare vs add/find.
    fn hashReindex(self: *Executor, h: *HashObject) Error!void {
        h.index.clearRetainingCapacity();
        for (h.entries.items, 0..) |e, i| {
            // multidata hashes hold several entries per key — keep the FIRST slot
            // so find() still returns the key's first record (BUG-hashmultidata).
            const gop = try h.index.getOrPutContext(self.arena, e.keyvals, .{});
            if (!gop.found_existing) gop.value_ptr.* = i;
        }
    }

    /// Append the variable names a defineKey/defineData argument denotes: a
    /// plain positional arg is one name; the `all:'y'` tag means EVERY
    /// variable of the input — for defineData, the KEY variables included (SAS:
    /// the keys are data too, the documented idiom for keeping the key column
    /// on .output() — BUG-hashdefinedataall; tick116 FINDING-2 pinned the wrong
    /// key-excluded form). With `dataset:` the variables are the DATASET's
    /// columns (the step needn't already carry them); otherwise the DATA step
    /// PDV. SAS DEFINEDATA/DEFINEKEY method dict (BUG-hashdefinetag — the tag
    /// value was taken as a literal var name, defining a phantom variable named
    /// 'yes').
    fn defineArgNames(self: *Executor, h: *HashObject, list: *std.ArrayList([]const u8), is_key: bool, args: []const ast.HashArg) Error!void {
        for (args) |arg| {
            if (arg.name) |nm| {
                if (!eqi(nm, "all")) return self.diags.fail(error.ExecError, 0, "hash define: unknown argument tag {s}: (use all:'y' or a plain variable name)", .{nm});
                const yes = switch (try self.ev.eval(arg.value)) {
                    .str => |s| blk: {
                        const s2 = std.mem.trim(u8, s, " ");
                        break :blk eqi(s2, "y") or eqi(s2, "yes");
                    },
                    .num => |x| x != 0,
                };
                if (!yes) continue;
                if (!is_key) if (h.src) |src| { // all:'y' + dataset: → the dataset's schema, keys included
                    const ds = self.lib.find(src) orelse
                        return self.diags.fail(error.ExecError, 0, "hash dataset {s} not found", .{src});
                    for (ds.columns.items) |c| {
                        var dup = false; // skip cols already defineData'd explicitly
                        for (list.items) |prev| if (eqi(prev, c.name)) {
                            dup = true;
                            break;
                        };
                        if (!dup) try list.append(self.arena, c.name);
                    }
                    continue;
                };
                for (self.pdv.vars.items) |v| {
                    if (isByFlag(v.name) or eqi(v.name, "_n_") or eqi(v.name, "_error_") or eqi(v.name, "_iorc_") or eqi(v.name, "_setobs_") or eqi(v.name, "_infile_")) continue;
                    try list.append(self.arena, v.name);
                }
                continue;
            }
            try list.append(self.arena, try self.argName(arg));
        }
    }

    /// A define* argument names a variable — evaluate it to its string value.
    fn argName(self: *Executor, arg: ast.HashArg) Error![]const u8 {
        return switch (try self.ev.eval(arg.value)) {
            .str => |s| s,
            .num => "",
        };
    }

    /// Collect the `key:`/`data:` argument values (or the current PDV values of
    /// the key/data variables when the explicit form is not used).
    fn collectArgs(self: *Executor, h: *const HashObject, vars: []const []const u8, args: []const ast.HashArg, want: []const u8) Error![]const Value {
        // NOTE-hashofhash / BUG-hashofhashexplicit: ABOVE the implicit/explicit
        // branch, because what is wrong is the defined data NAMES — a property of
        // the definition, identical under both spellings. Sitting inside the
        // `len == 0` arm made it an implicit-form-only guard, so the explicit
        // `h.add(key: 1, data: inner)` stored a silent missing at exit 0.
        // defineDone rejects this for any hash that was actually built; this is
        // the backstop for a program reaching add()/replace() without defineDone.
        //
        // BUG-declaredobjnamevalue moved it FURTHER up, above the arg-evaluation
        // loop, and the move follows from the sentence above: `vars` is the
        // definition, so nothing about the ARGS can change the verdict. It now
        // also decides a genuine collision — a nested hash IS documented SAS, so
        // this is our GAP (rc 2), whereas the new object-as-a-value guard in
        // eval.zig is a USER error (rc 1). Evaluating `data: inner` first let the
        // rc-1 guard preempt the rc-2 one and reclassify a documented feature.
        // With the same object supplied where the defined data variable is an
        // ORDINARY scalar, `vars` is clean, evaluation proceeds, and the rc-1
        // guard correctly speaks instead.
        if (eqi(want, "data")) try self.hashRejectNestedData(vars);
        var out: std.ArrayList(Value) = .empty;
        for (args) |arg| {
            if (arg.name) |nm| if (eqi(nm, want)) try out.append(self.arena, try self.ev.eval(arg.value));
        }
        // BUG-hashoutputkeys-crash: an explicit key:/data: tag list must match the
        // defined variable count. A SHORT list left trailing entry cells
        // uninitialized and crashed .output() reading garbage; SAS errors and
        // stops the step. (Zero explicit tags → the implicit form: PDV values of
        // every defined var — length always matches, so it's fine.)
        if (out.items.len != 0 and out.items.len != vars.len) {
            return self.diags.fail(error.ExecError, 0, "hash: the number of {s}: argument tags ({d}) must match the number of {s} variables ({d})", .{ want, out.items.len, want, vars.len });
        }
        // BUG-hashkeytypesilent (D-002): the Component Objects ref pins the SAME
        // normative sentence 18 times — on the KEY: argument of every keyed
        // method (ADD/CHECK/FIND/FIND_NEXT/FIND_PREV/REF/REMOVE/REPLACE) and on
        // the DATA: form: the value's "type must match the corresponding key
        // variable that is specified in a DEFINEKEY method call". A mismatched
        // key used to be just a lookup that misses — rc=160038, BYTE-IDENTICAL
        // to a legitimate miss, in both directions — so the reference's own
        // `if rc ne 0 then not found` idiom silently swallowed a bug in the
        // user's code. Only the EXPLICIT form is checked: the implicit form
        // reads the defined variables' own PDV values, matching by construction.
        if (out.items.len != 0) for (out.items, 0..) |v, i| try self.hashArgTypeCheck(h, vars[i], v, want);
        if (out.items.len == 0) {
            for (vars) |v| try out.append(self.arena, self.pdv.get(v) orelse Value.missing);
        }
        return out.items;
    }

    /// The declared type of a hash key/data variable: the PDV variable's type,
    /// else the `dataset:` source column's. null when the name is unknown —
    /// defineDone's hashDefineCheckNames already failed loud for that in a real
    /// program (hand-built test hashes carry no schema to check against).
    fn hashVarType(self: *Executor, h: *const HashObject, name: []const u8) ?pdv_mod.VarType {
        if (self.pdv.indexOf(name)) |i| return self.pdv.vars.items[i].type;
        if (h.src) |src| if (self.lib.find(src)) |ds| {
            for (ds.columns.items) |c| if (eqi(c.name, name)) return c.type;
        };
        return null;
    }

    /// One explicit key:/data: value against its defined variable's declared
    /// type (BUG-hashkeytypesilent): a mismatch is a malformed call — fail loud
    /// naming the variable and both types, never a silent "not found".
    fn hashArgTypeCheck(self: *Executor, h: *const HashObject, name: []const u8, v: Value, tag: []const u8) Error!void {
        const decl = self.hashVarType(h, name) orelse return;
        const ok: bool = if (decl == .num) v == .num else v == .str;
        if (!ok) return self.diags.fail(error.ExecError, 0, "hash {s} {s} is {s} but the {s}: argument is {s}", .{
            tag,
            name,
            if (decl == .num) "numeric" else "character",
            tag,
            if (v == .num) "numeric" else "character",
        });
    }

    /// `add(...)` — single-data: a duplicate key follows `duplicate:` — keep the
    /// first record and return non-zero (SAS default), replace it in place
    /// ('r'), or log an ERROR ('e') — BUG-hashduplicate. multidata:'y': always append and return 0 — every key may
    /// hold many records, walked by find()/find_next() (BUG-hashmultidata).
    fn hashAdd(self: *Executor, h: *HashObject, args: []const ast.HashArg) Error!f64 {
        const kv = try self.collectArgs(h, h.keys.items, args, "key");
        if (!h.multidata) if (h.index.getContext(kv, .{})) |slot| switch (h.duplicate) {
            .keep_first => return 1, // duplicate → not added
            .replace => { // duplicate:'r' → LAST added record wins
                h.entries.items[slot].datavals = try self.dupeVals(try self.collectArgs(h, h.datas.items, args, "data"));
                return 0;
            },
            .err => { // duplicate:'e' → documented log ERROR, keep first
                // SEV-rcbydesignerr: rcErr — ADD's documented contract is a
                // nonzero rc on an existing key (printed p.26); the log ERROR
                // is the fallback for an UNCHECKED rc (p.24). Recoverable.
                self.diags.rcErr(0, "hash add: duplicate key (duplicate:'e')", .{}) catch {};
                return 1;
            },
        };
        const dv = try self.collectArgs(h, h.datas.items, args, "data");
        const owned_kv = try self.dupeVals(kv); // index key must own its bytes (see dupeVals)
        try h.entries.append(self.arena, .{ .keyvals = owned_kv, .datavals = try self.dupeVals(dv) });
        // The index keeps the FIRST slot per key: find() returns the first record,
        // find_next() walks the later ones (single-data keys are unique anyway).
        const gop = try h.index.getOrPutContext(self.arena, owned_kv, .{});
        if (!gop.found_existing) gop.value_ptr.* = h.entries.items.len - 1;
        return 0;
    }

    /// A stored hash entry must OWN its char bytes: collectArgs hands back PDV
    /// cell slices, which live in the per-iteration scratch and are gone after
    /// the row boundary (BUG-datastepoom).
    fn dupeVals(self: *Executor, vals: []const Value) Error![]const Value {
        const out = try self.arena.alloc(Value, vals.len);
        for (vals, 0..) |v, i| out[i] = switch (v) {
            .num => v,
            .str => |s| .{ .str = try self.arena.dupe(u8, s) },
        };
        return out;
    }

    /// `replace(...)` — overwrite the data of an existing key *in place* (so a
    /// later `find` sees the new values), or insert it if the key is new.
    fn hashReplace(self: *Executor, h: *HashObject, args: []const ast.HashArg) Error!f64 {
        const kv = try self.collectArgs(h, h.keys.items, args, "key");
        const dv = try self.dupeVals(try self.collectArgs(h, h.datas.items, args, "data"));
        if (h.index.getContext(kv, .{})) |slot| {
            h.entries.items[slot].datavals = dv;
            return 0;
        }
        const owned_kv = try self.dupeVals(kv);
        try h.entries.append(self.arena, .{ .keyvals = owned_kv, .datavals = dv });
        try h.index.putContext(self.arena, owned_kv, h.entries.items.len - 1, .{});
        return 0;
    }

    /// Look up the key tuple; on a hit, load the FIRST record's data variables
    /// into the PDV, remember the find_next cursor, and return 0; else return a
    /// non-zero code (SAS's "not found").
    fn hashFind(self: *Executor, h: *HashObject, args: []const ast.HashArg) Error!f64 {
        const kv = try self.collectArgs(h, h.keys.items, args, "key");
        if (h.index.getContext(kv, .{})) |slot| {
            const e = h.entries.items[slot];
            for (h.datas.items, 0..) |dvar, i| {
                if (i < e.datavals.len) try self.pdv.set(dvar, e.datavals[i]);
            }
            h.md_key = e.keyvals; // cursor for find_next (BUG-hashmultidata)
            h.md_slot = slot;
            return 0;
        }
        h.md_key = null; // find_next after a miss is an error, as SAS
        return 160038; // SAS's hash "key not found" return code
    }

    /// `find_next()` — after a successful find()/find_next(), load the NEXT data
    /// record of the same key (insertion order) into the PDV and return 0; at the
    /// end of the key's records (always immediate for single-data hashes) return
    /// SAS's "not found". ponytail: linear scan from the cursor — O(n) per step;
    /// per-key slot chains if a profile ever shows this hot.
    fn hashFindNext(self: *Executor, h: *HashObject) Error!f64 {
        const key = h.md_key orelse {
            // SEV-rcbydesignerr: rcErr — a failed FIND_NEXT returns SAS's
            // nonzero rc; the ERROR is the documented unchecked-rc fallback
            // (printed p.53). Recoverable: the caller inspects the rc.
            self.diags.rcErr(0, "find_next() called without a successful find()", .{}) catch {};
            return 160038;
        };
        // ponytail: md_slot can point at a shifted entry after a remove(); the
        // bounds + key-tuple checks below keep the walk correct regardless.
        var i = h.md_slot + 1;
        while (i < h.entries.items.len) : (i += 1) {
            const e = h.entries.items[i];
            if (tupleEq(e.keyvals, key)) {
                for (h.datas.items, 0..) |dvar, j| {
                    if (j < e.datavals.len) try self.pdv.set(dvar, e.datavals[j]);
                }
                h.md_slot = i;
                return 0;
            }
        }
        return 160038;
    }

    /// `check(...)` — like `find` but does NOT load the data into the PDV; just
    /// reports whether the key is present (0 = found, non-zero = not).
    fn hashCheck(self: *Executor, h: *HashObject, args: []const ast.HashArg) Error!f64 {
        const kv = try self.collectArgs(h, h.keys.items, args, "key");
        if (h.index.getContext(kv, .{}) != null) return 0;
        return 160038;
    }

    /// `remove(...)` — delete the entry for the key (0 = removed, non-zero = not
    /// found). Order-preserving so an active iterator stays coherent. With
    /// multidata:'y' REMOVE deletes EVERY record of the key (SAS 9.4 —
    /// BUG-hashmultidataremove); REMOVEDUP is the separate cursor-only method
    /// (still unimplemented, fail-loud).
    fn hashRemove(self: *Executor, h: *HashObject, args: []const ast.HashArg) Error!f64 {
        const kv = try self.collectArgs(h, h.keys.items, args, "key");
        const slot = h.index.getContext(kv, .{}) orelse return 160038;
        // Language Reference: Concepts p.621 Note: while a bound hash ITERATOR is positioned on the
        // key, REMOVE must NOT remove it — an ERROR goes to the log and the
        // hash is left untouched. opensas removed it anyway AND corrupted the
        // walk: orderedRemove shifts later slots down while the iterator's
        // iter_pos still advanced, so a walk-and-delete loop visited every
        // OTHER record and left the rest behind at exit 0 (BUG-hashremoveiter).
        // Same protection the multidata cursor below already gives md_key.
        for (self.hashes.items) |it| {
            const bound = it.iter_of orelse continue;
            if (!it.iter_on or !eqi(bound, h.name)) continue;
            if (it.iter_pos < h.entries.items.len and tupleEq(h.entries.items[it.iter_pos].keyvals, kv)) {
                // SEV-rcbydesignerr: rcErr — printed p.82 Restriction: the key
                // is not removed and "an error message is issued"; the method
                // fails with a nonzero rc the caller checks. Recoverable.
                self.diags.rcErr(0, "hash remove: key not removed — hash iterator {s} is positioned on it", .{it.name}) catch {};
                return 1;
            }
        }
        if (h.multidata) {
            // one compaction pass: copy survivors forward, then shrink —
            // per-match orderedRemove was O(E) each → O(N·E) remove-all
            // (PERF-hashremovequad). Identical result: every record of the
            // key gone, survivor order preserved, one reindex below.
            var w: usize = 0;
            for (h.entries.items, 0..) |e, r| {
                if (tupleEq(e.keyvals, kv)) continue;
                if (w != r) h.entries.items[w] = e;
                w += 1;
            }
            h.entries.shrinkRetainingCapacity(w);
            if (h.md_key) |mk| { // the find_next cursor's key is gone — no stale walk
                if (tupleEq(mk, kv)) h.md_key = null;
            }
        } else {
            _ = h.entries.orderedRemove(slot); // keep insertion order; shifts later slots
        }
        try self.hashReindex(h); // slots after the removal moved — rebuild the index
        return 0;
    }

    /// `output(dataset:"name")` — write every entry to a new dataset: the key
    /// columns then the data columns (types from the stored values). Returns 0.
    fn hashOutput(self: *Executor, h: *HashObject, args: []const ast.HashArg) Error!f64 {
        var name: ?[]const u8 = null;
        for (args) |arg| if (arg.name) |nm| if (eqi(nm, "dataset")) {
            const v = try self.ev.eval(arg.value);
            if (v == .str) name = v.str;
        };
        var dsname = name orelse {
            // NOTE-hashoutputnods: no dataset: tag used to return rc=1 with NO
            // diagnostic — a silent no-op when the rc went unchecked. Fail loud.
            // SEV-rcbydesignerr: rcErr — a failed OUTPUT returns nonzero by
            // contract (printed p.73); loud but not a step-killer.
            self.diags.rcErr(0, "hash output: dataset: is required", .{}) catch {};
            return 1;
        };
        // BUG-hashoutputnametrim: a COMPUTED name (`dataset: 'w' || nm`, the
        // split-by-group idiom, with nm blank-padded) kept its trailing blanks
        // and created an UNREACHABLE member at rc=0 — while the options branch
        // below trimmed its half (two paths, one function, disagreeing). Trim
        // once up front, then the member must be a valid [lib.]name — both
        // SAS behaviours (trim, or error) beat a silent unreachable success.
        dsname = std.mem.trim(u8, dsname, " ");
        // dataset:'member(opts)' — split the trailing data-set options off the
        // member name (BUG-hashoutputdsopt): the parenthesized string used to
        // become the member name VERBATIM, so `out(where=(k>1))` wrote a table
        // literally named that and silently dropped the filter.
        var opt_src: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, dsname, '(')) |lp| {
            if (!std.mem.endsWith(u8, dsname, ")") or lp == 0) {
                self.diags.rcErr(0, "hash output dataset: malformed data-set options in '{s}'", .{dsname}) catch {}; // SEV-rcbydesignerr: printed p.73 rc contract
                return 1;
            }
            opt_src = dsname[lp + 1 .. dsname.len - 1];
            dsname = std.mem.trim(u8, dsname[0..lp], " "); // blanks before `(` too
        }
        { // [lib.]member — each part a V7 name (NVALID rules)
            var parts = std.mem.splitScalar(u8, dsname, '.');
            var np: usize = 0;
            var ok = true;
            while (parts.next()) |p| {
                np += 1;
                if (np > 2 or !fns.isValidName(p)) ok = false;
            }
            if (!ok) {
                self.diags.rcErr(0, "hash output dataset: '{s}' is not a valid SAS data set name", .{dsname}) catch {}; // SEV-rcbydesignerr: printed p.73 rc contract
                return 1;
            }
        }
        hashSortEntries(h); // ordered: hash writes rows in key order (BUG-hashordered)
        if (h.ordered != .none) try self.hashReindex(h); // sort moved slots (PERF-hashscan)
        const ds = try self.arena.create(Dataset);
        ds.* = Dataset.init(self.arena, dsname);
        const first = if (h.entries.items.len > 0) h.entries.items[0] else null;
        // SAS .output() writes ONLY the DEFINEDATA variables; a key is written only
        // when it is also defined as data (BUG-hashoutputkeys) — keys are not dumped
        // automatically (a documented gotcha: add the key to defineData to keep it).
        for (h.datas.items, 0..) |d, j| _ = try ds.addColumn(d, self.hashOutColType(first, d, j));
        for (h.entries.items) |e| {
            const cells = try self.arena.alloc(Value, h.datas.items.len);
            for (cells) |*c| c.* = Value.missing; // never read an uninitialized cell, matching hashFind/hashIterMove's `i < len` guard
            for (e.datavals, 0..) |v, i| {
                if (i >= cells.len) break;
                cells[i] = v;
            }
            try ds.appendRow(cells);
        }
        if (opt_src) |os| {
            const toks = try lex.tokenize(self.arena, os, self.diags);
            // An unknown option fails loud INSIDE applyDatasetOptions (io.zig,
            // since tick298) — the exec-side pre-check used to report the SAME
            // option a second time, two ERRORs for one mistake
            // (NOTE-dsoptdoublereport). Keep hashOutput's rc=1 contract by
            // watching the diagnostic count across the call.
            const nd = self.diags.count();
            try io.applyDatasetOptions(self.arena, ds, toks, self.diags, false); // OUTPUT: DKROCOND=WARN
            if (self.diags.count() != nd) return 1;
        }
        try self.lib.put(dsname, ds);
        return 0;
    }

    const IterMove = enum { first, next, prev, last };

    /// Output column type for one defineData variable: the DECLARED PDV type
    /// when the variable is certainly known (`length name $ n;` stays Char even
    /// with ZERO entries — NOTE-hashemptytype: first-entry inference defaulted
    /// an empty hash's columns to numeric, silently flipping char vars to Num).
    /// A compile-time-guessed or unknown name keeps the old first-entry
    /// inference (then numeric).
    fn hashOutColType(self: *Executor, first: ?HashEntry, name: []const u8, j: usize) pdv_mod.VarType {
        if (self.pdv.indexOf(name)) |i| {
            const v = self.pdv.vars.items[i];
            if (!v.guessed) return v.type;
        }
        return colTypeAt(first, j, false);
    }

    /// hiter `first()` / `next()` / `prev()` / `last()` — walk the entries of the
    /// hash this iterator is bound to, loading each entry's key+data variables
    /// into the PDV.
    /// Returns 0 while positioned on an entry, non-zero once past the end / empty
    /// (prev() before the first entry included — GAP-hashitermethods).
    fn hashIterMove(self: *Executor, h: *HashObject, move: IterMove) Error!f64 {
        // BUG-hiterbadhash: an unbound iterator (no/illegal constructor arg —
        // `declare hiter it;` carries no name exec can see) or one whose hash
        // has since been DELETE'd used to bail SILENTLY here — rc=1, no
        // diagnostic, empty walk at exit 0. Fail loud instead.
        const bound = h.iter_of orelse
            return self.diags.fail(error.ExecError, 0, "hash iterator {s} is not bound to a hash object — declare hiter {s}('hashname')", .{ h.name, h.name });
        const tgt = self.findHash(bound) orelse
            return self.diags.fail(error.ExecError, 0, "hash iterator {s}: hash object '{s}' is not declared", .{ h.name, bound });
        // A fresh walk (first/last) re-applies the ordered: key order (BUG-hashordered).
        if (move == .first or move == .last) {
            hashSortEntries(tgt);
            if (tgt.ordered != .none) try self.hashReindex(tgt); // sort moved slots (PERF-hashscan)
        }
        const n = tgt.entries.items.len;
        switch (move) {
            .first => h.iter_pos = 0,
            .next => h.iter_pos += 1,
            .prev => {
                if (h.iter_pos == 0) { // before the first entry, as SAS
                    h.iter_on = false;
                    return 1;
                }
                h.iter_pos -= 1;
            },
            .last => {
                if (n == 0) {
                    h.iter_on = false;
                    return 1;
                }
                h.iter_pos = n - 1;
            },
        }
        if (h.iter_pos >= n) { // exhausted — no longer pointing at a key
            h.iter_on = false;
            return 1;
        }
        h.iter_on = true; // positioned ON an entry (p.621's "pointing to the key")
        const e = tgt.entries.items[h.iter_pos];
        for (tgt.keys.items, 0..) |k, i| if (i < e.keyvals.len) try self.pdv.set(k, e.keyvals[i]);
        for (tgt.datas.items, 0..) |d, i| if (i < e.datavals.len) try self.pdv.set(d, e.datavals[i]);
        return 0;
    }

    fn runIf(self: *Executor, iff: ast.If) Error!Flow {
        const c = try self.ev.eval(iff.cond);
        // bare `if c;` — both branches null — is a subsetting filter.
        if (iff.then_branch == null and iff.else_branch == null) {
            return if (c.truthy()) .normal else .deleted;
        }
        if (c.truthy()) {
            if (iff.then_branch) |tb| return try self.runStmt(tb);
        } else {
            if (iff.else_branch) |eb| return try self.runStmt(eb);
        }
        return .normal;
    }

    fn runDo(self: *Executor, d: ast.Do) Error!Flow {
        switch (d.header) {
            .simple => return try self.runStmts(d.body),
            .while_ => |cond| {
                while ((try self.ev.eval(cond)).truthy()) {
                    switch (try self.runStmts(d.body)) {
                        .normal, .continue_ => {}, // CONTINUE → next iteration
                        .leave => break, // LEAVE → exit the loop
                        else => |f| return f, // DELETE/STOP propagate to the step
                    }
                }
            },
            .until_ => |cond| {
                while (true) {
                    switch (try self.runStmts(d.body)) {
                        .normal, .continue_ => {},
                        .leave => break,
                        else => |f| return f,
                    }
                    if ((try self.ev.eval(cond)).truthy()) break;
                }
            },
            .iter => |it| {
                var x = toF64(try self.ev.eval(it.start));
                const stop = toF64(try self.ev.eval(it.stop));
                const step = if (it.by) |by| toF64(try self.ev.eval(by)) else 1;
                // BUG-doByZero: zero increment is an ERROR (would loop forever).
                if (step == 0) {
                    self.diags.report(.err, 0, "The DO loop has a zero increment (BY 0).", .{}) catch {};
                    return error.ExecError;
                }
                if (std.math.isNan(x) or std.math.isNan(stop) or std.math.isNan(step)) {
                    self.diags.note(0, "DO loop bounds are missing; loop skipped", .{}) catch {};
                    return .normal;
                }
                while (if (step > 0) x <= stop else x >= stop) {
                    try self.pdv.set(it.name, .{ .num = x });
                    switch (try self.runStmts(d.body)) {
                        .normal, .continue_ => {},
                        .leave => break,
                        else => |f| return f,
                    }
                    // BUG-doindexreassign: SAS lets the body reassign the loop index;
                    // that altered value is what the bottom-of-loop increment steps from
                    // and what the `to` bound is tested against. Re-read it from the PDV
                    // before adding `by` (was: driven off the hidden counter, ignoring the
                    // body's change). A body that clears i to missing → NaN → loop exits.
                    x = toF64(self.pdv.get(it.name) orelse Value.missing);
                    x += step;
                }
                try self.pdv.set(it.name, .{ .num = x }); // SAS leaves index one past the end
            },
            .list => |lst| {
                // `do i = 1, 3, 5;` / mixed ranges — iterate each spec's values
                specs: for (lst.specs) |spec| {
                    const sv = try self.ev.eval(spec.start);
                    // A bare value with no `TO` range is exactly ONE iteration — assign
                    // it verbatim. Covers char values (`do c="a","b";` — G-dolist) AND a
                    // numeric-missing literal (`do s=10,.,30;`): `.` is a legitimate value,
                    // not a malformed range, so it must NOT hit the NaN guard below and be
                    // silently dropped (BUG-dolistmiss).
                    if (spec.stop == null) {
                        try self.pdv.set(lst.name, sv);
                        switch (try self.runStmts(d.body)) {
                            .normal, .continue_ => {},
                            .leave => break :specs,
                            else => |f| return f,
                        }
                        continue;
                    }
                    const start = toF64(sv);
                    const stop = toF64(try self.ev.eval(spec.stop.?));
                    const step = if (spec.by) |e| toF64(try self.ev.eval(e)) else 1;
                    // BUG-doByZero: zero increment is an ERROR (would loop forever).
                    if (step == 0) {
                        self.diags.report(.err, 0, "The DO loop has a zero increment (BY 0).", .{}) catch {};
                        return error.ExecError;
                    }
                    // A malformed RANGE (a missing/NaN bound) yields nothing.
                    if (std.math.isNan(start) or std.math.isNan(stop) or std.math.isNan(step)) continue;
                    var x = start;
                    while (if (step > 0) x <= stop else x >= stop) : (x += step) {
                        try self.pdv.set(lst.name, .{ .num = x });
                        switch (try self.runStmts(d.body)) {
                            .normal, .continue_ => {},
                            .leave => break :specs, // LEAVE exits the whole value-list DO
                            else => |f| return f,
                        }
                    }
                }
            },
        }
        return .normal;
    }

    /// Move the PUT output column pointer to 1-based column `n`: pad the current
    /// line with spaces so the next item starts there. The ONE landing site for
    /// both `@n` and `@(expression)` (GAP-atexpression-put) — a second copy would
    /// be a second ceiling to drift. ponytail: forward-only; a target before the
    /// current column can't rewind an append-only buffer, so it no-ops there
    /// (SAS would overwrite) — note if a program needs it.
    fn putColPtr(self: *Executor, n: usize) Error!void {
        // BUG-putptroom: an unbounded @n pads gigabytes (hang/OOM). The parser
        // rejects oversized literals; guard the alloc site too (same ceiling,
        // parser.zig max_put_ptr) — and `@(expr)` has no parse-time value at all,
        // so for that form THIS is the only guard.
        if (n > max_put_ptr)
            return self.diags.fail(error.ExecError, 0, "put: @{d} column pointer exceeds the {d} line-size ceiling", .{ n, max_put_ptr });
        const len = self.curLineLen();
        if (n > len + 1) try self.putBuf().appendNTimes(self.arena, ' ', n - 1 - len);
    }

    /// `put` writes a line to the log. ponytail: list style only, single space
    /// between values — SAS's column/format-driven spacing lands with B2 formats.
    fn runPut(self: *Executor, items: []const ast.PutItem) Error!void {
        var need_space = false;
        // BUG-putlistsep: a LIST-style value item (unformatted variable, named
        // `x=`, array element, _all_ list) leaves ONE trailing separator blank
        // for WHATEVER follows — Language Reference: Concepts p.621's own log renders
        // `put k 'removed from hash object'` as `Joyce removed from hash
        // object`. A FORMATTED item fills its own field and owes none
        // (`put '[' x 5. ']'` → `[    42]`, BUG-putfmtblank); a literal adds
        // none of its own (`put 'lit' n` → `lit42`). need_space alone cannot
        // carry this — it is set after formatted values too — so owe_blank
        // tracks "the previous item was list-style"; the literal arm is its
        // only new consumer (value arms keep their putfmtblank rules verbatim).
        var owe_blank = false;
        // FILE DLM=/DSD (BUG-fileopts): the list separator is the DLM char when a
        // `file … dlm=x;` is in effect; with an explicit DLM the delimiter
        // separates items even when one carries its own format (the fmt
        // blank-suppression is the space-list rule only).
        const sep = self.putSep();
        const dlm_on = self.file != null and self.file.?.dlm != null;
        for (items) |item| {
            switch (item) {
                .newline => {
                    try self.putBuf().append(self.arena, '\n');
                    need_space = false;
                    owe_blank = false;
                },
                .literal => |lit| {
                    // BUG-putlistsep: collect the blank a list-style value owes
                    // (Language Reference: Concepts p.621). DLM mode unchanged — literals stay
                    // undelimited there (the fileopts fixtures pin that).
                    if (owe_blank and !dlm_on) try self.putBuf().append(self.arena, sep);
                    try self.putBuf().appendSlice(self.arena, lit);
                    need_space = false;
                    owe_blank = false;
                },
                // `@n` — move the output column pointer to column n (1-based): pad the
                // current line with spaces so the next item starts at column n. ponytail:
                // forward-only; `@n` before the current column can't rewind an append-only
                // buffer, so it no-ops there (SAS would overwrite) — note if a program needs it.
                .col => |n| {
                    try self.putColPtr(n);
                    need_space = false; // @col sets spacing explicitly
                    owe_blank = false;
                },
                // GAP-atexpression-put: `@(expression)` — Statements printed p.269,
                // the PUT twin of INPUT's p.168 form. Evaluated PER PUT against the
                // live PDV (the doc's own example is `b=5; put @(b*3) name $10.;`),
                // clamped by io.clampCol — the SAME rule `@n`/`@var`/INPUT's
                // `@(expr)` route through — then the SAME putColPtr as `.col`.
                .col_expr => |e| {
                    switch (try self.ev.eval(e)) {
                        .num => |x| {
                            // The ceiling must see the RAW value, before clampCol.
                            // clampCol's out-of-range fallback is column 1, which for
                            // INPUT is a harmless short read but for PUT would
                            // SILENTLY write at column 1 — `put @(1e20) x;` must fail
                            // loud like `put @(40000) x;`, not quietly move to the
                            // left margin. NaN (a SAS missing value) fails this
                            // comparison and so still lands on column 1, matching how
                            // io.ptrCol treats a missing `@var`.
                            if (x > @as(f64, max_put_ptr))
                                return self.diags.fail(error.ExecError, 0, "put: @({d}) column pointer exceeds the {d} line-size ceiling", .{ x, max_put_ptr });
                            try self.putColPtr(io.clampCol(x));
                        },
                        // A CHARACTER result is SAS's OTHER parenthesised form, the
                        // `@(character-expression)` string search — unimplemented on
                        // the INPUT side too (io.evalColExpr), and identical here:
                        // landing on column 1 would silently write the WRONG column.
                        .str => return self.diags.fail(error.ExecError, 0, "put: @(character-expression) string-search pointer is not supported", .{}),
                    }
                    need_space = false;
                    owe_blank = false;
                },
                // `put a[i]` (runtime index) / `put a[*]` (every element) — BUG-putarrayref
                .array_elem => |ae| {
                    // special-list array members come from the live PDV (GH#48)
                    const elements = if (ae.special) |k| try eval.specialArrayNames(self.arena, self.pdv, k) else ae.elements;
                    if (ae.index) |ix| {
                        const xf = @floor(toF64(try self.ev.eval(ix)));
                        if (xf >= 1 and xf <= @as(f64, @floatFromInt(elements.len))) {
                            const nm = elements[@as(usize, @intFromFloat(xf)) - 1];
                            if (need_space) try self.putBuf().append(self.arena, sep);
                            // `put a[i]=;` — named output: the label is the RESOLVED
                            // element's own name (a[2] → a2=; array a[3] x y z → y=).
                            if (ae.named) {
                                // NOTE-temparraylabel: a _TEMPORARY_ element's PDV name
                                // is synthesized (`_temp_x_6`) — echoing it leaks an
                                // internal name. Label with the array-ref form instead
                                // (x[6]=). ponytail: flat subscript even for multidim
                                // (x[2,3] → x[6]=); the folded bounds aren't on the item.
                                if (std.ascii.startsWithIgnoreCase(nm, "_temp_")) {
                                    try self.putBuf().appendSlice(self.arena, ae.name);
                                    try self.putBuf().append(self.arena, '[');
                                    try self.putBuf().appendSlice(self.arena, try std.fmt.allocPrint(self.arena, "{d}", .{@as(u64, @intFromFloat(xf))}));
                                    try self.putBuf().append(self.arena, ']');
                                } else {
                                    try self.putBuf().appendSlice(self.arena, nm);
                                }
                                try self.putBuf().append(self.arena, '=');
                            }
                            try self.emitPutValue(self.pdv.get(nm) orelse Value.missing, null, .none);
                            need_space = true;
                            owe_blank = true;
                        } // out of range → SAS notes + missing; emit nothing
                    } else for (elements) |nm| {
                        if (need_space) try self.putBuf().append(self.arena, sep);
                        try self.emitPutValue(self.pdv.get(nm) orelse Value.missing, null, .none);
                        need_space = true;
                        owe_blank = true;
                    }
                },
                .variable => |v| {
                    // `put _page_;` — page eject (form-feed), not a PDV lookup
                    // (BUG-putpage: fell through to missing → printed ".").
                    if (eqi(v.name, "_page_")) {
                        try self.putBuf().append(self.arena, '\x0c');
                        need_space = false;
                        owe_blank = false;
                        // `put _all_;` / `_numeric_` / `_character_` list every matching PDV
                        // variable as `name=value` — char values via appendValue, not "."
                        // (BUG-putall-char).
                    } else if (specialPutList(v.name)) |kind| {
                        try self.putAllVars(kind, &need_space, &owe_blank);
                    } else {
                        const pa = peelAlign(v.fmt);
                        // GAP-putcolonformat: `put x : fmt.` is MODIFIED LIST
                        // OUTPUT, which spaces like a LIST item and not like a
                        // formatted one — so it is peeled before the separator
                        // rule below and re-joins it on the list side.
                        const ml = peelColon(pa.fmt);
                        // LIST output: an item with an explicit format fills its own
                        // field width — NO extra leading separator blank
                        // (BUG-putfmtblank); an unformatted list item keeps its one
                        // leading blank. (Named output below keeps its separator
                        // unconditionally — SAS spaces `x=` items even formatted.)
                        if (need_space and (ml.fmt == null or ml.colon or dlm_on)) try self.putBuf().append(self.arena, sep);
                        // BUG-declaredobjnamevalue: a PUT item is not an
                        // expression, so this read is the one place a bare name
                        // becomes a value WITHOUT passing eval's guard — `put h;`
                        // rendered a fabricated `.` at exit 0.
                        try self.ev.rejectObjectName(v.name);
                        const val = self.pdv.get(v.name) orelse Value.missing;
                        if (ml.colon) {
                            // Apply the format, then "All leading and trailing
                            // blanks are deleted" (printed p.298). Emitted as the
                            // resulting TEXT with no further format, so DSD
                            // quoting still sees the final field exactly as
                            // written; `-R`/`-L` justification within a field
                            // width is meaningless once the field is trimmed away.
                            const s = try format.apply(self.arena, val, ml.fmt.?);
                            try self.emitPutValue(.{ .str = std.mem.trim(u8, s, " ") }, null, .none);
                        } else {
                            // explicit `put x fmt.` wins; otherwise honour the variable's
                            // associated FORMAT/ATTRIB format, else the default.
                            try self.emitPutValue(val, ml.fmt orelse self.resolveFormat(v.name), pa.al);
                        }
                        need_space = true;
                        // LIST output: only an item with NO explicit format owes
                        // the next item a blank; a formatted item owes none
                        // (BUG-putlistsep / BUG-putfmtblank). A modified-list item
                        // DOES owe one — p.298: "each value is followed by a
                        // single blank" (p.283 leans on exactly that, using
                        // `+(-1)` to take the blank back before a period).
                        owe_blank = ml.fmt == null or ml.colon;
                    }
                },
                // `put x=;` — "name=" with no gap before the value, spaced from siblings
                .named => |n| {
                    if (specialPutList(n.name)) |kind| {
                        try self.putAllVars(kind, &need_space, &owe_blank);
                    } else {
                        if (need_space) try self.putBuf().append(self.arena, sep);
                        // GAP-putnamedcase: the label is the variable's DEFINED
                        // case, not the reference-site spelling (Language Reference: Concepts p.537's
                        // log renders `put _n_= … first.state=` as
                        // `_N_=1 FIRST.State=1`; p.539: `first.x=` → `FIRST.x=1`).
                        try self.ev.rejectObjectName(n.name); // `put h=;` — see the .variable arm above
                        try self.putBuf().appendSlice(self.arena, try self.putNamedLabel(n.name));
                        try self.putBuf().append(self.arena, '=');
                        const val = self.pdv.get(n.name) orelse Value.missing;
                        // explicit `put x= fmt.` wins; else the variable's attached
                        // FORMAT/ATTRIB format; else default (BUG-putnamedfmt).
                        const pa = peelAlign(n.fmt);
                        try self.emitPutValue(val, pa.fmt orelse self.resolveFormat(n.name), pa.al);
                        need_space = true;
                        owe_blank = true; // named output is list-style (spaced like `x` alone)
                    }
                },
            }
        }
        try self.putBuf().append(self.arena, '\n');
    }

    const PutAllKind = enum { all, numeric, character };

    fn specialPutList(name: []const u8) ?PutAllKind {
        if (eqi(name, "_all_")) return .all;
        if (eqi(name, "_numeric_")) return .numeric;
        if (eqi(name, "_character_")) return .character;
        return null;
    }

    /// `put _all_/_numeric_/_character_;` — emit each matching PDV variable as
    /// `name=value` (char values via appendValue → their text, not "."). The
    /// first./last. BY flags are internal and skipped (BUG-putall-char).
    fn putAllVars(self: *Executor, kind: PutAllKind, need_space: *bool, owe_blank: *bool) Error!void {
        // two passes: data variables first, then the automatics — SAS lists
        // `_all_` with the automatics at the end, in the order `_ERROR_ _N_`
        // (CHARNUM-errorvar). Storage order is _N_ first, so emit the autos from
        // a fixed ordered list rather than storage order.
        for (self.pdv.vars.items) |v| {
            if (isByFlag(v.name)) continue;
            // `_INFILE_` skipped too — an input-buffer echo, not a data var.
            // `_SETOBS_` as well: internal nobs= machinery (PERF-loadrowdual —
            // it's now defined only when nobs= is used; every other special
            // list already skips it via eval.isAutoVar).
            if (eqi(v.name, "_n_") or eqi(v.name, "_error_") or eqi(v.name, "_iorc_") or eqi(v.name, "_infile_") or eqi(v.name, "_setobs_")) continue;
            try self.putOneVar(kind, v, need_space, owe_blank);
        }
        for ([_][]const u8{ "_ERROR_", "_N_" }) |an| {
            if (self.pdv.indexOf(an)) |i| {
                // BUG-putallcase: SAS uppercases the automatics in `put _all_`
                // (`_ERROR_=0 _N_=1`); user variables keep their defined case.
                var v = self.pdv.vars.items[i];
                v.name = an;
                try self.putOneVar(kind, v, need_space, owe_blank);
            }
        }
    }

    /// The label SAS prints for a `put name=;` item: the variable's DEFINED case
    /// (GAP-putnamedcase — Language Reference: Concepts pp.537/538/539 logs). first./last. flags render
    /// the prefix uppercase + the base var's defined case (`FIRST.State=`); the
    /// automatics uppercase (`_N_=`); an unknown (uninitialized) name keeps its
    /// reference spelling.
    fn putNamedLabel(self: *Executor, name: []const u8) Error![]const u8 {
        if (isByFlag(name)) {
            const base = if (startsWithI(name, "first.")) name[6..] else name[5..];
            const bcase = if (self.pdv.indexOf(base)) |i| self.pdv.vars.items[i].name else base;
            const prefix: []const u8 = if (startsWithI(name, "first.")) "FIRST." else "LAST.";
            return try std.fmt.allocPrint(self.arena, "{s}{s}", .{ prefix, bcase });
        }
        if (eqi(name, "_n_")) return "_N_";
        if (eqi(name, "_error_")) return "_ERROR_";
        if (self.pdv.indexOf(name)) |i| return self.pdv.vars.items[i].name;
        return name;
    }

    fn putOneVar(self: *Executor, kind: PutAllKind, v: pdv_mod.Var, need_space: *bool, owe_blank: *bool) Error!void {
        const is_char = v.type == .char;
        const match = switch (kind) {
            .all => true,
            .numeric => !is_char,
            .character => is_char,
        };
        if (!match) return;
        if (need_space.*) try self.putBuf().append(self.arena, self.putSep());
        try self.putBuf().appendSlice(self.arena, v.name);
        try self.putBuf().append(self.arena, '=');
        try self.appendValue(v.value);
        need_space.* = true;
        owe_blank.* = true;
    }

    /// A variable's display format: the PDV var's own (fast path), else the
    /// step's collected FORMAT/ATTRIB list — cached onto the var once found.
    fn resolveFormat(self: *Executor, name: []const u8) ?[]const u8 {
        if (self.pdv.formatOf(name)) |f| return f;
        for (self.formats.items) |f| if (eqi(f.name, name)) {
            self.pdv.setFormat(name, f.fmt);
            return f.fmt;
        };
        return null;
    }

    /// Where `put` writes: the external FILE buffer when a `file "path";` is in
    /// effect, otherwise the SAS log (the CLI's stdout). `file print;`/`file log;`
    /// (GAP-fileprint) target the log too — opensas has one stdout stream for
    /// both listing and log (main.zig), so both keywords route there.
    fn putBuf(self: *Executor) *std.ArrayList(u8) {
        if (self.file) |f| return if (f.print_log) &self.log else &self.file_out;
        return &self.log;
    }

    /// Length of the line currently being built in the put buffer (bytes since the
    /// last '\n'), i.e. the 0-based column the next write lands on — for `@n`/PUT.
    fn curLineLen(self: *Executor) usize {
        const buf = self.putBuf().items;
        if (std.mem.lastIndexOfScalar(u8, buf, '\n')) |nl| return buf.len - nl - 1;
        return buf.len;
    }

    fn appendValue(self: *Executor, v: Value) Error!void {
        switch (v) {
            // List-PUT writes a char value's bytes verbatim — SAS preserves trailing
            // blanks here (e.g. `put x $char5.` → "ABC  "). So a GH#60 `''` blank
            // prints as a space; only CSV export drops an all-blank value (io.zig).
            .str => |s| try self.putBuf().appendSlice(self.arena, s),
            // SAS default numeric format (BEST12.) — trims f64 noise. A PLAIN
            // missing prints the OPTIONS MISSING= char (BUG-optmissing); special
            // missings (.A–.Z/._) keep their letter via bestNum.
            .num => |x| try self.putBuf().appendSlice(self.arena, if (std.math.isNan(x) and Value.missingChar(x) == '.')
                try std.fmt.allocPrint(self.arena, "{c}", .{io.global_missing})
            else
                try format.bestNum(self.arena, x)),
        }
    }

    /// List-item separator for PUT: the FILE DLM char when a `file … dlm=x;`
    /// is in effect (DSD implies comma), else the SAS default blank (BUG-fileopts).
    fn putSep(self: *Executor) u8 {
        return if (self.file) |f| f.dlm orelse ' ' else ' ';
    }

    /// DSD-aware PUT field emission (BUG-fileopts): emit via emitField, then
    /// when FILE DSD is on and the emitted text holds the delimiter or a quote,
    /// rewrap that slice in double quotes (doubling embedded quotes — CSV rules,
    /// SAS DSD semantics). Buffer-splice keeps emitField the single formatter.
    fn emitPutValue(self: *Executor, val: Value, fmt: ?[]const u8, al: PutAlign) Error!void {
        const f = self.file orelse return self.emitField(val, fmt, al);
        if (!f.dsd) return self.emitField(val, fmt, al);
        const buf = self.putBuf();
        const start = buf.items.len;
        try self.emitField(val, fmt, al);
        const s = buf.items[start..];
        const dlm = f.dlm orelse ',';
        // Quote-trigger mirrors appendCsvField (PROC EXPORT): delimiter, '"', \n, \r.
        // ponytail: no leading/trailing-blank trigger (export has one) — DSD char values
        // are length-padded, so blank-triggered quoting would quote every char field.
        if (std.mem.indexOfScalar(u8, s, dlm) == null and std.mem.indexOfAny(u8, s, "\"\n\r") == null) return;
        var q: std.ArrayList(u8) = .empty;
        try q.append(self.arena, '"');
        for (s) |c| {
            if (c == '"') try q.append(self.arena, '"');
            try q.append(self.arena, c);
        }
        try q.append(self.arena, '"');
        buf.shrinkRetainingCapacity(start);
        try buf.appendSlice(self.arena, q.items);
    }

    const PutAlign = enum { none, left, right };

    /// Peel a PUT alignment marker ('>' right / '<' left) that parsePut prepended to
    /// the explicit put format (GAP-putalign). Marker only ever rides an explicit put
    /// format; a variable's attached FORMAT/ATTRIB never carries one. Returns the
    /// real (marker-stripped) format, or null when the marker stood alone (`put x -R`).
    fn peelAlign(fmt: ?[]const u8) struct { fmt: ?[]const u8, al: PutAlign } {
        const f = fmt orelse return .{ .fmt = null, .al = .none };
        if (f.len == 0) return .{ .fmt = null, .al = .none };
        const al: PutAlign = switch (f[0]) {
            '>' => .right,
            '<' => .left,
            else => return .{ .fmt = fmt, .al = .none },
        };
        const rest = f[1..];
        return .{ .fmt = if (rest.len == 0) null else rest, .al = al };
    }

    /// Peel the ':' MODIFIED LIST OUTPUT marker the parser prefixes to a PUT
    /// item's format (GAP-putcolonformat, parser.tryModifiedList) — the same
    /// marker-byte convention as peelAlign's '>'/'<', which is peeled first
    /// because attachAlign prepends outside it.
    fn peelColon(fmt: ?[]const u8) struct { fmt: ?[]const u8, colon: bool } {
        const f = fmt orelse return .{ .fmt = null, .colon = false };
        if (f.len == 0 or f[0] != ':') return .{ .fmt = fmt, .colon = false };
        const rest = f[1..];
        return .{ .fmt = if (rest.len == 0) null else rest, .colon = rest.len != 0 };
    }

    /// Emit a PUT value: format it (explicit put format or the variable's own), then
    /// justify within the field width if `-R`/`-L` was given (GAP-putalign). With no
    /// format the field is the value's natural width, so alignment is a no-op there.
    fn emitField(self: *Executor, val: Value, fmt: ?[]const u8, al: PutAlign) Error!void {
        if (al == .none) {
            if (fmt) |f| try self.putBuf().appendSlice(self.arena, try format.apply(self.arena, val, f)) else try self.appendValue(val);
            return;
        }
        const s = if (fmt) |f| try format.apply(self.arena, val, f) else switch (val) {
            .str => |x| x,
            .num => |x| try format.bestNum(self.arena, x),
        };
        try self.putBuf().appendSlice(self.arena, justifyField(self.arena, s, al) catch s);
    }

    /// Re-justify a width-padded field: trim the blanks, repad on the requested side
    /// so the content sits right/left within the same total width.
    fn justifyField(arena: std.mem.Allocator, s: []const u8, al: PutAlign) Error![]const u8 {
        const trimmed = std.mem.trim(u8, s, " ");
        if (trimmed.len >= s.len) return s; // nothing to move (already full width)
        const out = try arena.alloc(u8, s.len);
        const pad = s.len - trimmed.len;
        if (al == .right) {
            @memset(out[0..pad], ' ');
            @memcpy(out[pad..], trimmed);
        } else {
            @memcpy(out[0..trimmed.len], trimmed);
            @memset(out[trimmed.len..], ' ');
        }
        return out;
    }

    // ── output ───────────────────────────────────────────────────────────

    /// `output [a b …];` — a bare `output;` writes to every dataset the DATA
    /// statement named; named targets route to one of those declared datasets.
    fn runOutput(self: *Executor, names: []const []const u8) Error!void {
        // MODIFY control statements REPLACE/REMOVE arrive as a \x00-sentinel OUTPUT
        // node (parser encodes them so no new AST variant is needed). They are valid
        // ONLY inside a MODIFY step — in-place obs control has no meaning elsewhere,
        // so fail loud (never silently rewrite/drop the wrong dataset).
        if (names.len == 1 and names[0].len > 1 and names[0][0] == 0) {
            const ctl = names[0][1..]; // "replace" | "remove"
            if (self.modify_names == null) {
                self.diags.report(.err, 0, "{s} is valid only in a DATA step with a MODIFY statement", .{ctl}) catch {};
                return error.ExecError;
            }
            // opensas commits a MODIFY by re-emitting the master (io.putInput replaces
            // it), so REPLACE = re-emit the current obs, REMOVE = emit nothing (the obs
            // is absent from the rebuilt master = deleted). No in-place storage mutation,
            // so REMOVE can't corrupt a partially-rewritten master. Both override the
            // implicit end-of-obs REPLACE for this iteration (obs_handled).
            // MODIFY-BY (transaction-driven): record into the driver's rebuild
            // tables instead — the whole master is emitted at exhaustion (modifyFlush).
            self.obs_handled = true;
            if (self.modify_by) |md| {
                if (eqi(ctl, "replace")) {
                    try self.modifyReplace(md);
                } else if (md.cur_m) |r| { // remove
                    try md.repl.put(self.arena, r, null);
                }
                return;
            }
            if (eqi(ctl, "replace")) try self.outputAll();
            return;
        }
        // Explicit OUTPUT in a single-dataset MODIFY step is a BAIL: the rebuild-commit
        // model re-emits the whole master, so emitting the modified PDV looks like
        // REPLACE and silently loses the untouched originals SAS would keep on disk.
        // MODIFY with a transaction (BY form) is different: OUTPUT is the Language Reference: Concepts p.601
        // revised-program idiom for ADDING a no-match row — append the PDV obs to the
        // rebuilt master and mark the obs handled so the implicit REPLACE doesn't
        // duplicate it this iteration.
        if (self.modify_names) |mn| {
            if (mn.len < 2) {
                // The MODIFY entry itself documents OUTPUT inside a MODIFY step
                // ("writes the current observation to the end of all data sets",
                // Statements ref p.240ff) — valid SAS we bail on, so rc 2.
                diag.markGap();
                self.diags.report(.err, 0, "OUTPUT is not supported in a DATA step with MODIFY; use REPLACE or REMOVE", .{}) catch {};
                return error.ExecError;
            }
            self.obs_handled = true;
            // MODIFY-BY: an explicit OUTPUT APPENDS the new obs (the p.601
            // no-match idiom) — buffered, emitted at the END of the rebuilt
            // master (in-place semantics; BUG-modifybymasterdriven).
            if (names.len == 0) {
                if (self.modify_by) |md| {
                    try md.appends.append(self.arena, try self.capturePdvRow());
                    return;
                }
                return self.outputAll();
            }
            for (names) |nm| try self.output(try self.outputTarget(nm));
            return;
        }
        if (names.len == 0) return self.outputAll();
        for (names) |nm| try self.output(try self.outputTarget(nm));
    }

    /// A bare `output;` or the implicit bottom-of-step output: write the
    /// current observation to the primary AND every extra dataset the DATA
    /// statement named (BUG-multioutput — Language Reference: Concepts DATA-statement semantics).
    fn outputAll(self: *Executor) Error!void {
        try self.output(self.cur_out.?);
        for (self.extra_outs) |x| try self.output(x);
    }

    /// The dataset a named `output` writes to: the primary, or one of the extra
    /// datasets the DATA statement declared. SAS 9.4 raises a compile-time ERROR
    /// ("The data set name is not in the list of output data sets") for any other
    /// name — lazily registering it instead filled a PHANTOM dataset, left the
    /// declared one empty, and diagnosed nothing, so a typo (`output rst;` for
    /// `output rest;`) was silent data loss (BUG-outputundeclared). Loud ERROR +
    /// halt at runtime — close enough to SAS's compile-time, never silent.
    fn outputTarget(self: *Executor, name: []const u8) Error!*Dataset {
        if (self.outputNamed(name)) |ds| return ds;
        self.diags.report(.err, 0, "The data set name {s} is not in the list of output data sets for the DATA statement", .{name}) catch {};
        return error.ExecError;
    }

    /// "Is this name one of the step's output data sets?" — the primary or one of
    /// the DATA statement's extras — answered in ONE place, because two callers
    /// ask it: a named `output <ds>;` (above) and MODIFY's master-membership
    /// restriction (assertModifyMasterIsOutput). `work.x` and `x` name the SAME
    /// member — Library.put/find both compare through stripWork — so this must
    /// strip it too, or the legal `data work.d; modify d;` reads as a mismatch.
    fn outputNamed(self: *Executor, name: []const u8) ?*Dataset {
        const want = stripWork(name);
        if (self.cur_out) |co| if (std.ascii.eqlIgnoreCase(stripWork(co.name), want)) return co;
        for (self.extra_outs) |x| if (std.ascii.eqlIgnoreCase(stripWork(x.name), want)) return x;
        return null;
    }

    fn output(self: *Executor, out: *Dataset) Error!void {
        if (out.columns.items.len == 0) try self.seedSchema(out);
        try io.snapshot(out, self.pdv);
    }

    /// Seed a fresh output dataset's columns from the PDV, honouring drop/keep and
    /// stamping format/label/declared-length. SAS defines the output schema at
    /// compile time, so a 0-row step (subsetting-if, all deletes, SET of empty)
    /// still carries its columns — call this at step finalize when nothing output.
    fn seedSchema(self: *Executor, out: *Dataset) Error!void {
        // GAP-ch23med-tick296 F3: a MODIFY master's descriptor is FROZEN — it is
        // the master's own, verbatim, never the PDV's. See modifyFrozenMaster.
        if (self.modifyFrozenMaster(out)) |m| {
            for (m.columns.items) |c| _ = try out.addColumnLike(c.name, c);
            return;
        }
        // ponytail: column order follows first-creation order, not SAS's
        // source-appearance order — cosmetic until PROC PRINT cares.
        for (self.pdv.vars.items) |v| {
            if (self.included(v.name)) _ = try out.addColumn(v.name, v.type);
        }
        self.applyAttrs(); // ensure PDV vars carry their attrs before stamping columns
        // PDV-var format first (a SET/MERGE source column's attached format,
        // carried in seedInputColumns), then explicit FORMAT statements so they
        // override the inherited one (GH#31b).
        for (out.columns.items) |c| if (self.pdv.formatOf(c.name)) |f| out.setFormat(c.name, f);
        for (self.formats.items) |f| out.setFormat(f.name, f.fmt);
        for (out.columns.items) |c| if (self.lib.varLabel(c.name)) |l| out.setLabel(c.name, l);
        // INFORMAT / LABEL carried on the PDV var → output column metadata (EXEC-varattr).
        for (out.columns.items) |c| if (self.pdv.informatOf(c.name)) |inf| out.setInformat(c.name, inf);
        for (out.columns.items) |c| if (self.pdv.labelOf(c.name)) |l| out.setLabel(c.name, l);
        // Declared char width → output column. The PDV var carries it from either a
        // LENGTH/ATTRIB statement (seeded at step start) or a SET/MERGE source column
        // (seedInputColumns), so stamping from the var covers both — a `set EMPTY`
        // shell dataset keeps its Char n, not Char 1 (BUG-contentsmeta, ISS-attriblength).
        for (out.columns.items) |c| if (c.type == .char and c.len == null)
            if (self.pdv.indexOf(c.name)) |i| {
                const L = self.pdv.vars.items[i].len;
                if (L > 0) out.setLen(c.name, L);
            };
        // BUG-informatwidth: a char var whose ONLY width source is an INFORMAT
        // statement (`informat c $15.;` — no LENGTH/ATTRIB, no $w. FORMAT) takes
        // the informat width as its declared length (Language Reference: Concepts p.72: a var created
        // in a FORMAT/INFORMAT statement gets the spec's width). The FORMAT twin
        // resolves at display time (contentsLen's charFormatWidth fallback);
        // stamping here puts the real width on the descriptor so CONTENTS/OUT=
        // and a read-back SET carry it. Descriptor-only — the PDV var's len
        // stays 0, so no storage truncation (EPIC-charfixedwidth's half).
        // ponytail: a conflicting $w. FORMAT + $v. INFORMAT on one var keeps
        // the FORMAT width regardless of statement order (SAS: first wins).
        for (out.columns.items) |c| if (c.type == .char and c.len == null) {
            const fspec = if (c.format) |f| format.parseSpec(f) else format.Spec{};
            if (fspec.is_char and fspec.w > 0) continue; // FORMAT pins the width
            if (c.informat) |inf| {
                const ispec = format.parseSpec(inf);
                if (ispec.is_char and ispec.w > 0) out.setLen(c.name, ispec.w);
            }
        };
        // Declared numeric byte-length (3..7) → output column, so a `length x 5;`
        // reaches the dataset descriptor: PROC CONTENTS shows Num 5 (not 8), and a
        // read-back SET re-inherits it via seedInputColumns (GH#59, NUMLEN-meta).
        // Length 8 stays full precision → column len null (default 8).
        for (out.columns.items) |c| if (c.type == .num and c.len == null)
            if (self.pdv.indexOf(c.name)) |i| {
                const L = self.pdv.vars.items[i].numlen;
                if (L >= 3 and L < 8) out.setLen(c.name, L);
            };
    }

    /// The MODIFY master's LIVE dataset when `out` is the step's re-emission of
    /// it — i.e. the one output whose descriptor MUST NOT CHANGE — else null.
    ///
    /// GAP-ch23med-tick296 F3. MODIFY updates in place, so the descriptor is not
    /// the step's to rewrite. DATA Step Statements ref printed p.240 (pdf 251,
    /// footer "240 Chapter 2 / Dictionary of SAS DATA Step Statements"), the
    /// statement's own Restrictions: "This statement cannot modify the descriptor
    /// portion of a SAS data set, such as adding a variable." Language Reference: Concepts printed p.585
    /// (running header "Combining SAS Data Sets: Methods 585") repeats it as a
    /// Note, and Language Reference: Concepts printed p.588 Table 23.3 row "Scope of changes" gives the
    /// FULL extent — MODIFY "cannot change the data set descriptor information,
    /// so changes such as ADDING OR DELETING variables, variable labels, and so
    /// on, are not valid" — which is why this freezes the whole descriptor and
    /// not just the add half.
    ///
    /// opensas rebuilt the schema from the PDV on every commit, so all three
    /// descriptor edits leaked into the master, at exit 0. The filed symptom is
    /// the MILDEST: `modify d; brandnew=99;` grew d from 2 columns to 3 (F3),
    /// but `modify d; drop y;` DELETED column y and every value in it, and
    /// `modify d; rename x=xx;` renamed a master column. The deletion is
    /// destruction of data the program never asked to lose, so the frozen-
    /// descriptor rule is the fix for all three rather than a guard on adds.
    ///
    /// NOT AN ERROR, and that is doc-settled rather than chosen: Statements ref
    /// printed p.253 (footer "MODIFY Statement 253"), the Example 3 discussion —
    /// "MODIFY does not add NWSTOCK to the INVTY.STOCK data set because that
    /// would modify the data set descriptor. Thus, it is not necessary to put
    /// NWSTOCK in a DROP statement." So a PDV variable outside the descriptor is
    /// simply not written, no diagnostic, and the reference states outright that
    /// a DROP is unnecessary. Failing loud here would have rejected the
    /// reference's OWN flagship Example 3, whose transaction variable NWSTOCK is
    /// deliberately left undropped (D-014). The value is not lost, either — the
    /// example USES it (`instock = instock + nwstock`) and only declines to store
    /// it, so this is a scratch variable, not a discarded answer.
    ///
    /// Only the MASTER is frozen. `data invty.stock invty.stock95 invty.stock97;
    /// modify invty.stock;` (printed p.260 Example 8) writes two BRAND-NEW data
    /// sets alongside it, and those take the ordinary full-PDV schema — hence the
    /// per-output test rather than a step-wide flag.
    fn modifyFrozenMaster(self: *Executor, out: *Dataset) ?*Dataset {
        const names = self.modify_names orelse return null;
        if (names.len == 0) return null;
        // BUG-modifymasteroptname: the same split the output guard needs. Without
        // it a subsetted `modify a(where=…)` matched no output and found no member,
        // so the descriptor freeze silently stopped protecting exactly the shape
        // that was hardest to get right — the sibling caller the ticket did not name.
        const master = splitSourceRef(names[0]);
        if (!std.ascii.eqlIgnoreCase(stripWork(out.name), stripWork(master.name))) return null;
        const m = self.lib.find(master.name) orelse return null;
        return if (m == out) null else m; // never freeze a dataset against itself
    }

    /// WARN (not halt) on a KEEP/DROP/RENAME statement name that resolves to no
    /// PDV var — the "never been referenced" case (GH#22 ISS-dkrocondwarn).
    /// DKROCOND= governs this and defaults to WARN in SAS 9.4: the step still
    /// runs and writes its output (keeping/dropping only the vars that exist),
    /// job RC=4. GH#19 wrongly escalated to ERROR+abort, blocking valid programs
    /// (it broke valid real-world SDTM programs). Validated at step finalize against the
    /// full PDV (superset of every var created), so a later-created var is legal;
    /// automatics are exempt. RENAME options are validated in
    /// io.applyDatasetOptions; only the statement OLD names come here.
    fn validateKeepDropRefs(self: *Executor) Error!void {
        for (self.keeps.items) |name| try self.assertReferenced(name);
        for (self.drops.items) |name| try self.assertReferenced(name);
        for (self.renames.items) |p| try self.assertReferenced(p.old);
    }

    fn assertReferenced(self: *Executor, name: []const u8) Error!void {
        // A `pfx:` name-prefix wildcard (GAP-dropcolon) is a pattern, not a
        // literal name — never a "never referenced" typo. Automatics and the
        // parser's `_setobs_`/`_error_` helpers aren't data vars either, and the
        // helper may not reach the PDV on a 0-row read (io defines it per row).
        if (name.len > 0 and name[name.len - 1] == ':') return;
        if (self.pdv.indexOf(name) != null) return;
        if (isByFlag(name) or eqi(name, "_n_") or eqi(name, "_error_") or eqi(name, "_iorc_") or eqi(name, "_setobs_") or eqi(name, "_infile_")) return;
        // SET point=/nobs= temps dropped by dropSetControlTemp may never reach
        // the PDV (an unassigned point var) — not a typo (BUG-setpointtemp).
        if (self.set_point_var) |pv| if (eqi(name, pv)) return;
        if (self.nobs_var) |nv| if (eqi(name, nv)) return;
        const up = try std.ascii.allocUpperString(self.arena, name);
        // DKROCOND=WARN default: WARN and continue, do NOT poison later steps.
        self.diags.report(.warning, 0, "The variable {s} in the DROP, KEEP, or RENAME list has never been referenced", .{up}) catch {};
    }

    /// `_ALL_`/`_NUMERIC_`/`_CHARACTER_` in a RETAIN/KEEP/DROP list are SAS name
    /// lists resolved against the PDV, not literal variable names — the parser
    /// passes them through as plain names, like `of _numeric_` (parser.zig:1755).
    /// Expand them here, right after declareVars completes the compile-time PDV,
    /// reusing the ARRAY special-list resolution (GH#48, eval.specialArrayNames).
    /// ponytail: membership uses declareVars' static type guesses (a later runtime
    /// write can correct a guess) — move to live resolution in included()/
    /// isRetained() if a program ever depends on runtime-typed membership.
    fn expandSpecialVarLists(self: *Executor) Error!void {
        try self.expandSpecialVarList(&self.keeps);
        try self.expandSpecialVarList(&self.drops);
        try self.expandSpecialVarList(&self.retained);
        for (self.special_retains.items) |sr| {
            for (try eval.specialArrayNames(self.arena, self.pdv, sr.kind)) |n| {
                try self.retained.append(self.arena, n);
                if (sr.init) |e| try self.pdv.set(n, try self.ev.eval(e));
            }
        }
    }

    fn expandSpecialVarList(self: *Executor, list: *std.ArrayList([]const u8)) Error!void {
        var special = false;
        for (list.items) |n| special = special or specialVarList(n) != null;
        if (!special) return; // common case: no special names, list untouched
        var out: std.ArrayList([]const u8) = .empty;
        for (list.items) |n| {
            if (specialVarList(n)) |kind| {
                try out.appendSlice(self.arena, try eval.specialArrayNames(self.arena, self.pdv, kind));
            } else try out.append(self.arena, n);
        }
        list.* = out;
    }

    /// `_ALL_`/`_NUMERIC_`/`_CHARACTER_` as a FORMAT/INFORMAT statement or ATTRIB
    /// format=/informat=/label= "variable": a name LIST (Statements Ref printed
    /// p.24 — "_NUMERIC_ specifies all numeric variables … _ALL_ specifies all
    /// variables"), applied per member, never a column of its own
    /// (BUG-speciallistphantom, GH#79). Both lists expand here, right after the
    /// compile-time PDV completes, reusing the ARRAY special-list resolution
    /// (eval.specialArrayNames, GH#48) like expandSpecialVarLists. The num/char
    /// format-type check declareStmt runs on an explicitly named variable runs
    /// per member here — `_all_` must not smuggle a numeric format onto a
    /// character variable past it (SAS errors that attach whichever way the
    /// variable was named; the `_numeric_`/`_character_` forms pre-filter by
    /// type, which is why SAS programs use THOSE for typed formats).
    fn expandSpecialFormats(self: *Executor) Error!void {
        // The type check is KEYED per list so each expanded member is validated
        // exactly once (BUG-informatallnotypecheck): scan appends a display
        // format to BOTH lists, so it is checked on the .formats pass only —
        // checking non-riders on both passes would report it twice (the dedup
        // the old `false` was for). But an informat (\x01 rider) lives on attrs
        // ONLY, so skipping the whole attrs pass let `informat _all_ 8.;`
        // smuggle a numeric informat onto character variables at rc 0 while the
        // sibling FORMAT arm errored. The attrs pass therefore checks the \x01
        // riders; \x00 label riders carry no format type and stay unchecked.
        try self.expandSpecialFormatList(&self.formats, .display);
        try self.expandSpecialFormatList(&self.attrs, .informat);
    }

    fn expandSpecialFormatList(self: *Executor, list: *std.ArrayList(ast.FormatItem), check: enum { display, informat }) Error!void {
        var special = false;
        for (list.items) |it| special = special or specialVarList(it.name) != null;
        if (!special) return; // common case: no special names, list untouched
        var out: std.ArrayList(ast.FormatItem) = .empty;
        for (list.items) |it| {
            if (specialVarList(it.name)) |kind| {
                // label (\x00) riders and the `format x;` removal sentinel ($.)
                // attach unchecked — like declareStmt's exclusions, they carry
                // no display-format type to conflict. The item class this pass
                // validates: display formats on the .formats pass, informat
                // (\x01) riders on the .attrs pass — never both, never neither.
                const rider = it.fmt.len > 0 and (it.fmt[0] == 0 or it.fmt[0] == 1);
                const spec = if (rider) it.fmt[1..] else it.fmt;
                const class_match = switch (check) {
                    .display => !rider,
                    .informat => it.fmt.len > 0 and it.fmt[0] == 1,
                };
                const typed = class_match and spec.len > 0 and !eqi(spec, "$.") and !eqi(spec, ".");
                const noun: []const u8 = if (check == .informat) "informat" else "format";
                for (try eval.specialArrayNames(self.arena, self.pdv, kind)) |n| {
                    if (typed) if (self.pdv.indexOf(n)) |vi| {
                        const vr = self.pdv.vars.items[vi];
                        const fmt_char = format.specIsChar(spec);
                        if (vr.type == .char and !fmt_char and !self.declaredNumTyped(n)) {
                            self.diags.report(.err, 0, "The numeric {s} {s} cannot be used with character variable {s}.", .{ noun, spec, n }) catch {};
                        } else if (vr.type == .num and fmt_char) {
                            self.diags.report(.err, 0, "The character {s} {s} cannot be used with numeric variable {s}.", .{ noun, spec, n }) catch {};
                        }
                    };
                    try out.append(self.arena, .{ .name = n, .fmt = it.fmt });
                }
            } else try out.append(self.arena, it);
        }
        list.* = out;
    }

    /// PERF-arraydeclquad: hash drops/keeps/retained once, now that every
    /// append site (scan, extractSetOptions, expandSpecialVarLists,
    /// collectExtraSets, buildDriver) has run. Called right after buildDriver.
    fn freezeNameLists(self: *Executor) Error!void {
        try freezeNameList(self.arena, &self.drops_set, self.drops.items);
        try freezeNameList(self.arena, &self.keeps_set, self.keeps.items);
        try freezeNameList(self.arena, &self.retained_set, self.retained.items);
    }

    fn included(self: *const Executor, name: []const u8) bool {
        // first./last., `_N_`, `_ERROR_`, `_IORC_` and `_INFILE_` are automatics — never written out.
        if (isByFlag(name) or eqi(name, "_n_") or eqi(name, "_error_") or eqi(name, "_iorc_") or eqi(name, "_infile_")) return false;
        if (self.keep_mode) return self.nameInFast(&self.keeps_set, self.keeps.items, name);
        return !self.nameInFast(&self.drops_set, self.drops.items, name);
    }

    fn isRetained(self: *const Executor, name: []const u8) bool {
        return self.nameInFast(&self.retained_set, self.retained.items, name);
    }

    /// BUG-prefixreadflags: define a read-flag automatic (first./last., end=,
    /// in=) with its SAS initial value 0 and mark it retained so the
    /// top-of-iteration reset skips it (Language Reference: Concepts p.79 — automatics are retained,
    /// never set to missing).
    fn keepReadFlag(self: *Executor, name: []const u8) Error!void {
        try self.pdv.set(name, .{ .num = 0 });
        try self.retained.append(self.arena, name);
    }

    /// O(1) nameIn: hash lookup when freezeNameLists populated `set` — an empty
    /// set means an empty list, a `pfx:` wildcard list, or pre-freeze, and the
    /// linear scan is right for all three (PERF-arraydeclquad).
    fn nameInFast(self: *const Executor, set: *const std.StringHashMapUnmanaged(void), list: []const []const u8, name: []const u8) bool {
        _ = self;
        // SAS names are ≤32 chars; stack-fold exactly like Pdv.indexOf.
        if (set.count() > 0) {
            var buf: [64]u8 = undefined;
            if (name.len <= buf.len) return set.contains(std.ascii.lowerString(&buf, name));
        }
        return nameIn(list, name);
    }

    // ── BY-group processing ──────────────────────────────────────────────
    /// Split the parser's BY sentinels back out of the name list: `"\x00D<var>"`
    /// marks a DESCENDING key, a `"\x00notsorted"` entry sets NOTSORTED mode
    /// (GAP-batch-qa107; the AST stays a plain name list). Plain names ascend.
    fn decodeBy(self: *Executor, names: []const []const u8) Error!void {
        var clean: std.ArrayList([]const u8) = .empty;
        var desc: std.ArrayList(bool) = .empty;
        for (names) |n| {
            if (n.len > 0 and n[0] == 0) {
                if (n.len >= 2 and n[1] == 'D') {
                    try clean.append(self.arena, n[2..]);
                    try desc.append(self.arena, true);
                } else self.by_notsorted = true; // "\x00notsorted"
            } else {
                try clean.append(self.arena, n);
                try desc.append(self.arena, false);
            }
        }
        self.by_vars = try clean.toOwnedSlice(self.arena);
        self.by_desc = try desc.toOwnedSlice(self.arena);
    }

    /// BY tuple compare honouring BY DESCENDING: a descending key compares
    /// inverted, so "smallest first" is exactly the SAS group order for mixed
    /// ascending/descending keys (GAP-batch-qa107). Equality is unaffected.
    fn cmpBy(self: *const Executor, a: []const Value, b: []const Value) std.math.Order {
        for (a, b, 0..) |x, y, k| {
            const o = cmpValueOrd(x, y);
            if (o != .eq) return if (k < self.by_desc.len and self.by_desc[k]) o.invert() else o;
        }
        return .eq;
    }

    fn buildByNames(self: *Executor, bys: []const []const u8) Error!void {
        const firsts = try self.arena.alloc([]const u8, bys.len);
        const lasts = try self.arena.alloc([]const u8, bys.len);
        for (bys, 0..) |bv, k| {
            firsts[k] = try std.fmt.allocPrint(self.arena, "first.{s}", .{bv});
            lasts[k] = try std.fmt.allocPrint(self.arena, "last.{s}", .{bv});
        }
        self.first_names = firsts;
        self.last_names = lasts;
    }

    /// Set `first.<var>` / `last.<var>` for the observation now in the PDV.
    /// `first.<var>[k]` is 1 from the first BY level that changed vs the previous
    /// obs on down; `last.<var>[k]` likewise vs the next obs (peeked). BY needs
    /// sorted SET input — only the `sets` driver can look ahead, so other drivers
    /// leave the flags unset. ponytail: no sortedness check (input assumed sorted).
    fn applyBy(self: *Executor, d: *Driver, bys: []const []const u8) Error!void {
        const cur = try self.arena.alloc(Value, bys.len);
        for (bys, 0..) |bv, k| cur[k] = self.pdv.get(bv) orelse Value.missing;

        var first_level: usize = 0; // no previous obs → every level is "first"
        if (self.prev_by) |prev| {
            first_level = bys.len;
            for (0..bys.len) |k| if (!valueEq(cur[k], prev[k])) {
                first_level = k;
                break;
            };
        }

        var last_level: usize = 0; // no next obs → every level is "last"
        if (try self.peekNextBy(d, bys)) |nxt| {
            last_level = bys.len;
            for (0..bys.len) |k| if (!valueEq(cur[k], nxt[k])) {
                last_level = k;
                break;
            };
        }

        for (0..bys.len) |k| {
            try self.pdv.set(self.first_names[k], .{ .num = if (k >= first_level) 1 else 0 });
            try self.pdv.set(self.last_names[k], .{ .num = if (k >= last_level) 1 else 0 });
        }
        self.prev_by = cur;
    }

    /// Interleaving SET+BY: pick the source whose current row has the smallest BY
    /// tuple. Ties keep the lower source index (only a strictly-smaller tuple
    /// wins), so equal keys read in `set a b` order. Null when every source is
    /// spent. Does not advance any cursor.
    fn pickInterleave(self: *Executor, dss: []*Dataset, cursors: []const usize, by_cols: []const []const ?usize) Error!?usize {
        var best: ?usize = null;
        var best_tuple: []Value = &.{};
        for (dss, 0..) |ds, d| {
            if (cursors[d] >= ds.rowCount()) continue;
            const tup = try self.byTupleOfSet(ds, cursors[d], by_cols[d]);
            self.truncBySet(tup); // interleave on the truncated key (BUG-setbyvarlen)
            if (best == null or self.cmpBy(tup, best_tuple) == .lt) {
                best = d;
                best_tuple = tup;
            }
        }
        return best;
    }

    /// The BY-values of `ds`'s row `row` (missing where a source lacks a BY column).
    fn byTupleOfSet(self: *Executor, ds: *Dataset, row: usize, cols: []const ?usize) Error![]Value {
        const out = try self.arena.alloc(Value, cols.len);
        for (cols, 0..) |c, j| out[j] = if (c) |ci| ds.row(row)[ci] else Value.missing;
        return out;
    }

    /// SET+BY: truncate a raw BY tuple in place to the PDV storage width so
    /// last./the sortedness check compare the SAME value first./PDV do — char
    /// LENGTH and numeric LENGTH<8 byte-truncation (GH#46). Twin of MERGE's
    /// byTupleInto/by_len (BUG-mergebyvarlen): without it a value differing only
    /// past the declared length splits a spurious group (wrong last.) or trips a
    /// spurious "not properly sorted" ERROR when the raw order inverts inside a
    /// truncated group (BUG-setbyvarlen). `bys[j]` aligns positionally with the
    /// BY columns / tuple slot.
    fn truncBySet(self: *const Executor, tup: []Value) void {
        const bys = self.by_vars orelse return;
        for (bys, 0..) |bv, j| {
            if (j >= tup.len) break;
            const vi = self.pdv.indexOf(bv) orelse continue;
            const vr = self.pdv.vars.items[vi];
            switch (tup[j]) {
                .str => |s| if (vr.type == .char and vr.len > 0 and s.len > vr.len) {
                    tup[j] = .{ .str = s[0..vr.len] };
                },
                // ponytail: mirrors pdv.setAt's GH#46 high-N-byte mask; kept local
                // (3 lines) so the fix stays in exec.zig — pdv.truncNum is the
                // source of truth if this ever needs to change.
                .num => |x| if (vr.type == .num and vr.numlen >= 3 and vr.numlen < 8 and std.math.isFinite(x)) {
                    const shift: u6 = @intCast(8 * (8 - vr.numlen));
                    tup[j] = .{ .num = @bitCast(@as(u64, @bitCast(x)) & (~@as(u64, 0) << shift)) };
                },
            }
        }
    }

    /// The next observation's BY-values without consuming it (SET only). null at
    /// end of data or for a non-SET driver.
    fn peekNextBy(self: *Executor, d: *Driver, bys: []const []const u8) Error!?[]Value {
        switch (d.*) {
            .sets => |sd| {
                // Interleave: cursors are already past the loaded obs, so the next
                // pick (unconsumed) is exactly the peek.
                if (sd.by_cols) |bc| {
                    const pick = (try self.pickInterleave(sd.dss, sd.cursors, bc)) orelse return null;
                    const nxt = try self.byTupleOfSet(sd.dss[pick], sd.cursors[pick], bc[pick]);
                    self.truncBySet(nxt); // last. compares the truncated key (BUG-setbyvarlen)
                    return nxt;
                }
                var di = sd.di;
                var ri = sd.ri;
                while (di < sd.dss.len) {
                    const ds = sd.dss[di];
                    if (ri < ds.rowCount()) {
                        const vals = try self.arena.alloc(Value, bys.len);
                        for (bys, 0..) |bv, k| {
                            vals[k] = if (ds.indexOf(bv)) |ci| ds.row(ri)[ci] else Value.missing;
                        }
                        self.truncBySet(vals); // last. compares the truncated key (BUG-setbyvarlen)
                        return vals;
                    }
                    di += 1;
                    ri = 0;
                }
                return null;
            },
            else => return null,
        }
    }
};

fn isByFlag(name: []const u8) bool {
    return startsWithI(name, "first.") or startsWithI(name, "last.");
}

/// First BY level at which two group keys differ (len when equal) — the level
/// from which first./last. flags turn on (BUG-mergefirstlast).
fn changeLevel(a: []const Value, b: []const Value) usize {
    for (a, 0..) |v, k| if (!valueEq(v, b[k])) return k;
    return a.len;
}

/// BY-key equality of a dataset row against a key tuple, without allocating a
/// tuple (the MODIFY-BY master scan calls this per row — BUG-modifybymasterdriven).
fn rowKeyEq(ds: *Dataset, row: usize, cols: []const ?usize, key: []const Value) bool {
    const cells = ds.row(row);
    for (cols, 0..) |c, j| {
        const v = if (c) |ci| cells[ci] else Value.missing;
        if (!valueEq(v, key[j])) return false;
    }
    return true;
}

fn startsWithI(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and std.ascii.eqlIgnoreCase(s[0..prefix.len], prefix);
}

/// Grouping equality: char blank-padded, numeric with missing == missing.
fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// True if CALL EXECUTE's queued text uses a macro-quoting function we'd have
/// to resolve when the queue drains (%str/%nrstr/%quote/%bquote/%nrbquote/
/// %unquote) — the macro facility is gone by then, so the caller fails LOUD
/// instead of running quoting syntax as literal source (FEAT-callexecute, D-002).
fn hasMacroQuoting(s: []const u8) bool {
    const forms = [_][]const u8{ "%str(", "%nrstr(", "%quote(", "%bquote(", "%nrbquote(", "%unquote(" };
    for (forms) |f| if (std.ascii.indexOfIgnoreCase(s, f) != null) return true;
    return false;
}

/// One op of the flattened step body (BUG-controlflownesting). Control
/// structures compile to jumps with absolute PCs; simple statements dispatch
/// back into runStmt unchanged. DO-loop state lives in a per-op DoState (rebuilt
/// at every loop entry, so the cached op stream is safe to reuse each iteration).
const Op = union(enum) {
    stmt: *const ast.Stmt, // a non-control statement, run via runStmt
    jmp: usize, // GOTO (compiled) — absolute PC
    link: usize, // LINK (compiled) — push pc+1, jump
    jfalse: struct { cond: *const ast.Expr, target: usize }, // eval cond; falsy → target (IF / DO WHILE-UNTIL)
    // `do i = start to stop by step;` — enter evaluates+validates the bounds
    // (bad → optional note + skip_pc, matching runDo's early return), else arms st.
    do_enter: struct { name: []const u8, start: *const ast.Expr, stop: *const ast.Expr, by: ?*const ast.Expr, st: *DoState, skip_pc: usize, note_bad: bool },
    do_chk: struct { st: *DoState, fail_pc: usize }, // in range → pc+1 (body), else fail_pc
    do_set: struct { name: []const u8, st: *DoState }, // body top: index var = st.x
    do_incr: struct { st: *DoState, chk_pc: usize, name: ?[]const u8 = null }, // x += step, back to chk (CONTINUE lands here); name set → re-read index from PDV first (iterative DO honors body reassignment)
    do_final: struct { name: []const u8, st: *DoState }, // iterative-DO exit: index one past (LEAVE lands here — pre-incr, like `break`)
    do_setv: struct { name: []const u8, value: *const ast.Expr }, // single-value list-DO spec: assign verbatim (char-safe)
};

const DoState = struct { x: f64 = 0, stop: f64 = 0, step: f64 = 0 };

/// CONTINUE/LEAVE patch sites gathered while compiling one loop body.
const LoopCtx = struct { cont: std.ArrayList(usize) = .empty, brk: std.ArrayList(usize) = .empty };

/// Flattens a statement list into ops. Labels record their PC (first definition
/// wins, like the old top-level scan); GOTO/LINK record a patch site; CONTINUE/
/// LEAVE become jumps patched to the enclosing loop's incr/exit (a stray one —
/// lexically outside any loop — stays a plain statement, preserving the old
/// fall-through-to-output behaviour).
const OpCompiler = struct {
    a: std.mem.Allocator,
    ops: std.ArrayList(Op) = .empty,
    labels: std.ArrayList(struct { name: []const u8, pc: usize }) = .empty,
    xfers: std.ArrayList(struct { op: usize, name: []const u8 }) = .empty,
    loops: std.ArrayList(LoopCtx) = .empty,
    // First stray LEAVE/CONTINUE keyword (outside every DO loop) — a SAS compile
    // ERROR (728-185), reported by compileProgram so the step never runs.
    stray_lc: ?[]const u8 = null,

    fn emit(c: *OpCompiler, op: Op) Error!usize {
        const i = c.ops.items.len;
        try c.ops.append(c.a, op);
        return i;
    }

    fn patch(c: *OpCompiler, idx: usize, target: usize) void {
        const op = &c.ops.items[idx];
        switch (op.*) {
            .jmp => op.jmp = target,
            .link => op.link = target,
            .jfalse => op.jfalse.target = target,
            .do_enter => op.do_enter.skip_pc = target,
            .do_chk => op.do_chk.fail_pc = target,
            else => unreachable,
        }
    }

    fn findLabel(c: *OpCompiler, name: []const u8) ?usize {
        for (c.labels.items) |l| if (eqi(l.name, name)) return l.pc;
        return null;
    }

    fn compileStmts(c: *OpCompiler, stmts: []const ast.Stmt) Error!void {
        for (stmts) |*s| try c.compileStmt(s);
    }

    /// Compile one loop body, collecting CONTINUE/LEAVE patch sites; the caller
    /// patches ctx.cont / ctx.brk to the loop's re-test / exit PCs.
    fn compileBody(c: *OpCompiler, body: []const ast.Stmt) Error!LoopCtx {
        try c.loops.append(c.a, .{});
        try c.compileStmts(body);
        return c.loops.pop().?;
    }

    fn compileStmt(c: *OpCompiler, s: *const ast.Stmt) Error!void {
        switch (s.*) {
            .label => |name| {
                if (c.findLabel(name) == null) try c.labels.append(c.a, .{ .name = name, .pc = c.ops.items.len });
            },
            .goto => |name| _ = try c.xfers.append(c.a, .{ .op = try c.emit(.{ .jmp = 0 }), .name = name }),
            .link => |name| _ = try c.xfers.append(c.a, .{ .op = try c.emit(.{ .link = 0 }), .name = name }),
            .if_ => |iff| {
                // bare `if c;` — both branches null — is a subsetting filter: keep
                // it a plain statement so runStmt returns .deleted as before.
                if (iff.then_branch == null and iff.else_branch == null) {
                    _ = try c.emit(.{ .stmt = s });
                    return;
                }
                const jf = try c.emit(.{ .jfalse = .{ .cond = iff.cond, .target = 0 } });
                if (iff.then_branch) |tb| try c.compileStmt(tb);
                const jend = try c.emit(.{ .jmp = 0 });
                c.patch(jf, c.ops.items.len);
                if (iff.else_branch) |eb| try c.compileStmt(eb);
                c.patch(jend, c.ops.items.len);
            },
            .do_ => |d| switch (d.header) {
                .simple => try c.compileStmts(d.body), // a do-group just inlines; labels inside stay reachable
                .while_ => |cond| {
                    const chk = try c.emit(.{ .jfalse = .{ .cond = cond, .target = 0 } });
                    const ctx = try c.compileBody(d.body);
                    _ = try c.emit(.{ .jmp = chk });
                    const end = c.ops.items.len;
                    c.patch(chk, end);
                    for (ctx.cont.items) |i| c.patch(i, chk);
                    for (ctx.brk.items) |i| c.patch(i, end);
                },
                .until_ => |cond| {
                    const start = c.ops.items.len;
                    const ctx = try c.compileBody(d.body);
                    const cnd = try c.emit(.{ .jfalse = .{ .cond = cond, .target = start } });
                    const end = c.ops.items.len;
                    for (ctx.cont.items) |i| c.patch(i, cnd); // CONTINUE still evaluates the UNTIL cond
                    for (ctx.brk.items) |i| c.patch(i, end);
                },
                .iter => |it| {
                    const st = try c.a.create(DoState);
                    st.* = .{};
                    const enter = try c.emit(.{ .do_enter = .{ .name = it.name, .start = it.start, .stop = it.stop, .by = it.by, .st = st, .skip_pc = 0, .note_bad = true } });
                    const chk = try c.emit(.{ .do_chk = .{ .st = st, .fail_pc = 0 } });
                    _ = try c.emit(.{ .do_set = .{ .name = it.name, .st = st } });
                    const ctx = try c.compileBody(d.body);
                    const cont_t = try c.emit(.{ .do_incr = .{ .st = st, .chk_pc = chk, .name = it.name } });
                    const brk_t = try c.emit(.{ .do_final = .{ .name = it.name, .st = st } });
                    c.patch(enter, c.ops.items.len); // bad bounds → skip loop AND the final set
                    c.patch(chk, brk_t);
                    for (ctx.cont.items) |i| c.patch(i, cont_t);
                    for (ctx.brk.items) |i| c.patch(i, brk_t);
                },
                .list => |lst| {
                    // `do i = v1, a to b, …;` — the body compiles once PER SPEC (a
                    // bad range silently yields nothing, no note; LEAVE exits all).
                    var brks: std.ArrayList(usize) = .empty;
                    for (lst.specs) |spec| {
                        if (spec.stop == null) {
                            _ = try c.emit(.{ .do_setv = .{ .name = lst.name, .value = spec.start } });
                            const ctx = try c.compileBody(d.body);
                            for (ctx.cont.items) |i| c.patch(i, c.ops.items.len); // → next spec
                            try brks.appendSlice(c.a, ctx.brk.items);
                        } else {
                            const st = try c.a.create(DoState);
                            st.* = .{};
                            const enter = try c.emit(.{ .do_enter = .{ .name = lst.name, .start = spec.start, .stop = spec.stop.?, .by = spec.by, .st = st, .skip_pc = 0, .note_bad = false } });
                            const chk = try c.emit(.{ .do_chk = .{ .st = st, .fail_pc = 0 } });
                            _ = try c.emit(.{ .do_set = .{ .name = lst.name, .st = st } });
                            const ctx = try c.compileBody(d.body);
                            const cont_t = try c.emit(.{ .do_incr = .{ .st = st, .chk_pc = chk } });
                            const next = c.ops.items.len; // exhausted/bad range → next spec, NO final set
                            c.patch(enter, next);
                            c.patch(chk, next);
                            for (ctx.cont.items) |i| c.patch(i, cont_t);
                            try brks.appendSlice(c.a, ctx.brk.items);
                        }
                    }
                    for (brks.items) |i| c.patch(i, c.ops.items.len); // LEAVE exits the whole value-list DO
                },
            },
            .continue_ => {
                if (c.loops.items.len == 0) {
                    if (c.stray_lc == null) c.stray_lc = "CONTINUE";
                    _ = try c.emit(.{ .stmt = s }); // unreachable: the hasStepErrors gate halts first
                } else {
                    try c.loops.items[c.loops.items.len - 1].cont.append(c.a, try c.emit(.{ .jmp = 0 }));
                }
            },
            .leave => {
                if (c.loops.items.len == 0) {
                    if (c.stray_lc == null) c.stray_lc = "LEAVE";
                    _ = try c.emit(.{ .stmt = s }); // unreachable: the hasStepErrors gate halts first
                } else {
                    try c.loops.items[c.loops.items.len - 1].brk.append(c.a, try c.emit(.{ .jmp = 0 }));
                }
            },
            else => _ = try c.emit(.{ .stmt = s }),
        }
    }
};

/// Equal length and element-wise equal (blank-padded/missing-aware) value tuples.
fn tupleEq(a: []const Value, b: []const Value) bool {
    if (a.len != b.len) return false;
    for (a, b) |x, y| if (!valueEq(x, y)) return false;
    return true;
}

/// Value of column `name` in `row` (missing if the dataset lacks that column).
fn colVal(ds: *Dataset, row: []const Value, name: []const u8) Value {
    return if (ds.indexOf(name)) |j| row[j] else Value.missing;
}

/// Column type for a hash `output`, inferred from the j-th key/data value of the
/// first entry (an empty hash defaults each column to numeric).
fn colTypeAt(first: ?HashEntry, j: usize, is_key: bool) pdv_mod.VarType {
    const e = first orelse return .num;
    const vals = if (is_key) e.keyvals else e.datavals;
    if (j >= vals.len) return .num;
    return switch (vals[j]) {
        .num => .num,
        .str => .char,
    };
}

fn valueEq(a: Value, b: Value) bool {
    return cmpValueOrd(a, b) == .eq;
}

/// UPDATE "no-change" test: only a PLAIN numeric missing (`.`) or an all-blank
/// character value in the transaction is skipped (keeps the master). A SPECIAL
/// missing (.A–.Z / ._) is a real value that MUST overwrite — it is the
/// doc-sanctioned way to blank a master value (Language Reference: Concepts p.586; BUG-updatespecialmiss).
/// Special missings ride in the NaN payload, so gate on missingRank==1 (plain)
/// rather than any-NaN, which swallowed .A/.Z/._ as no-change.
fn isUpdateMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x) and Value.missingRank(x) == 1,
        .str => |s| {
            for (s) |ch| if (ch != ' ') return false;
            return true;
        },
    };
}

/// SAS grouping/ordering compare: char blank-padded ASCII, numeric with missing
/// as the lowest value. Two missings are NOT automatically equal: special
/// missings (.A–.Z, ._) are distinct values that compare and sort by rank
/// (._ < . < .A < … < .Z < every number), mirroring the evaluator's cmpNum
/// (eval.zig) — the old any-NaN-equals-any-NaN collapse merged .A into . for
/// hash keys and MERGE BY (BUG-execmissdistinct).
fn cmpValueOrd(a: Value, b: Value) std.math.Order {
    if (a == .str and b == .str) {
        const n = @max(a.str.len, b.str.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            const ca = if (i < a.str.len) a.str[i] else ' ';
            const cb = if (i < b.str.len) b.str[i] else ' ';
            if (ca != cb) return std.math.order(ca, cb);
        }
        return .eq;
    }
    const x = toF64(a);
    const y = toF64(b);
    const xm = std.math.isNan(x);
    const ym = std.math.isNan(y);
    if (xm and ym) return std.math.order(Value.missingRank(x), Value.missingRank(y));
    if (xm) return .lt;
    if (ym) return .gt;
    return std.math.order(x, y);
}

/// Map an `ordered:` argument value to a HashOrder. 'a'/'ascending'/'yes'/'y' and
/// any non-zero number → ascending; 'd'/'descending' → descending; everything
/// else ('n'/'no'/0) → none (insertion order).
fn parseHashOrder(v: Value) HashOrder {
    switch (v) {
        .num => |x| return if (x != 0 and !std.math.isNan(x)) .asc else .none,
        .str => |s| {
            if (s.len == 0) return .none;
            return switch (std.ascii.toLower(s[0])) {
                'a', 'y' => .asc,
                'd' => .desc,
                else => .none,
            };
        },
    }
}

/// Sort a hash's entries by key tuple for an `ordered:` hash. ponytail: sorted
/// lazily at each iteration start / output, not maintained on every add — fine
/// for the build-then-walk pattern; move to insertion-sort if add-during-walk
/// order ever matters.
fn hashSortEntries(h: *HashObject) void {
    if (h.ordered == .none) return;
    const Ctx = struct {
        desc: bool,
        fn lt(ctx: @This(), a: HashEntry, b: HashEntry) bool {
            const o = cmpTuple(a.keyvals, b.keyvals);
            return if (ctx.desc) o == .gt else o == .lt;
        }
    };
    std.mem.sort(HashEntry, h.entries.items, Ctx{ .desc = h.ordered == .desc }, Ctx.lt);
}

/// Lexicographic compare of two equal-length BY tuples.
fn cmpTuple(a: []const Value, b: []const Value) std.math.Order {
    for (a, b) |x, y| {
        const o = cmpValueOrd(x, y);
        if (o != .eq) return o;
    }
    return .eq;
}

/// Fill `out` with dataset `d`'s BY-values at `row` (missing where a source
/// lacks the BY column).
fn byTupleInto(md: *const MergeState, d: usize, row: usize, out: []Value) void {
    for (md.by_cols[d], 0..) |c, j| {
        const v = if (c) |ci| md.dss[d].row(row)[ci] else Value.missing;
        // BUG-mergebyvarlen: truncate a char BY value to the merged (first-source)
        // width before comparing, so a longer value collides with the shorter
        // prefix's group instead of splitting off spurious unmatched rows.
        out[j] = if (j < md.by_len.len and md.by_len[j] > 0 and v == .str and v.str.len > md.by_len[j])
            .{ .str = v.str[0..md.by_len[j]] }
        else
            v;
    }
}

fn zeros(a: std.mem.Allocator, n: usize) Error![]usize {
    const z = try a.alloc(usize, n);
    @memset(z, 0);
    return z;
}

/// True when the INPUT items carry an explicit RECORD advance (`/` or `#n`) —
/// nameless pointer-control items whose informat starts with the control char.
/// Under MISSOVER/TRUNCOVER/STOPOVER these split the read into per-record
/// segments (BUG-inputmultirecmode); `@col`/`+n` are column moves, not advances.
fn hasRecordAdvance(items: []const ast.InputItem) bool {
    for (items) |it| {
        if (it.name.len != 0) continue;
        const inf = it.informat orelse "";
        if (inf.len >= 1 and (inf[0] == '/' or inf[0] == '#')) return true;
    }
    return false;
}

/// Which trailing line-hold an INPUT list carries: `single` for a lone trailing
/// `@`, `across` for `@@` (the parser emits both as nameless sentinel items with
/// informat "@" / "@@"). Both may not co-occur; a trailing sentinel is always last.
const InputHold = struct { single: bool, across: bool };
fn inputHold(items: []const ast.InputItem) InputHold {
    var r: InputHold = .{ .single = false, .across = false };
    for (items) |it| if (it.name.len == 0 and it.informat != null) {
        if (std.mem.eql(u8, it.informat.?, "@@")) r.across = true else if (std.mem.eql(u8, it.informat.?, "@")) r.single = true;
    };
    return r;
}

/// STOPOVER short-record test: does `line` (from byte `from`) hold fewer values
/// than the INPUT list needs? SAS STOPOVER errors when INPUT reaches end of record
/// before all variables are read (BUG-infilemissover). ponytail: counts list/DLM
/// fields against value-taking items; column/formatted-width STOPOVER isn't split out.
fn recordShort(line: []const u8, from: usize, items: []const ast.InputItem, dlm: ?[]const u8) bool {
    var need: usize = 0;
    for (items) |it| if (it.name.len > 0) {
        need += 1;
    };
    if (need == 0) return false;
    var avail: usize = 0;
    if (dlm) |d| {
        // BUG-dlmmultichar: `d` is a delimiter SET — count bytes that are members.
        const rest = if (from <= line.len) line[from..] else "";
        var seps: usize = 0;
        for (rest) |ch| if (std.mem.indexOfScalar(u8, d, ch) != null) {
            seps += 1;
        };
        avail = if (rest.len == 0) 0 else seps + 1;
    } else {
        var f = std.mem.tokenizeAny(u8, line, " \t");
        f.index = @min(from, line.len);
        while (f.next() != null) avail += 1;
    }
    return avail < need;
}

/// True if `line` from byte `pos` on is only whitespace — the held record is
/// spent and the driver should step to the next line.
fn onlyWsFrom(line: []const u8, pos: usize) bool {
    if (pos >= line.len) return true;
    return std.mem.indexOfNone(u8, line[pos..], " \t") == null;
}

/// `_ALL_`/`_NUMERIC_`/`_CHARACTER_` — the special variable name lists, or null
/// for an ordinary name (RETAIN/KEEP/DROP expansion; mirrors eval's ARRAY/`of`
/// specialList and the `put _all_` specialPutList).
fn specialVarList(name: []const u8) ?ast.SpecialArr {
    if (eqi(name, "_numeric_")) return .numeric;
    if (eqi(name, "_character_")) return .character;
    if (eqi(name, "_all_")) return .all;
    return null;
}

/// Insert `list`'s names (lowercased) into `set` for O(1) membership. A
/// `pfx:` wildcard entry (GAP-dropcolon) leaves the set EMPTY — checked before
/// any insert — so membership falls back to nameIn's prefix scan.
fn freezeNameList(arena: std.mem.Allocator, set: *std.StringHashMapUnmanaged(void), list: []const []const u8) Error!void {
    for (list) |n| if (n.len > 0 and n[n.len - 1] == ':') return;
    for (list) |n| try set.put(arena, try std.ascii.allocLowerString(arena, n), {});
}

fn nameIn(list: []const []const u8, name: []const u8) bool {
    for (list) |n| {
        // a trailing ':' is a name-prefix wildcard from DROP/KEEP `pfx:` (GAP-dropcolon)
        if (n.len > 0 and n[n.len - 1] == ':') {
            if (std.ascii.startsWithIgnoreCase(name, n[0 .. n.len - 1])) return true;
        } else if (std.ascii.eqlIgnoreCase(n, name)) return true;
    }
    return false;
}

/// The common char-RETURNING functions, for the compile-time type guess
/// (BUG-pdvcompilevars). Not exhaustive — a wrong num guess self-heals on an
/// executed path (pdv.declare/set), so only never-executed assignments of a
/// missing entry would mistype, as numeric missing instead of blank.
const char_fns = [_][]const u8{
    "put",       "putc",      "substr",  "trim",     "trimn",     "left",
    "right",     "strip",     "upcase",  "lowcase",  "propcase",  "compress",
    "compbl",    "cat",       "cats",    "catt",     "catx",      "catq",
    "scan",      "translate", "tranwrd", "transtrn", "repeat",    "reverse",
    "quote",     "dequote",   "byte",    "char",     "coalescec", "ifc",
    "choosec",   "symget",    "resolve", "vname",    "vtype",     "vformat",
    "vinformat", "vlabel",
    // `__assignc(rhs, n)` — the parser's own assignment-to-length-n-char-var
    // wrapper; its result is char by construction. Missing here, a var first
    // assigned a literal under a (late) LENGTH guessed NUMERIC in the PDV —
    // and NOTE-fmtnumoncharcoerce's format type check then false-fired on a
    // later legitimate char format (`length nm $8; nm="Ada"; format nm $char8.;`).
    "__assignc",
};

fn isCharFn(name: []const u8) bool {
    for (char_fns) |f| if (eqi(f, name)) return true;
    return false;
}

fn strLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

/// Ascending numeric order with SAS missing (NaN) sorting first.
fn numLessMissingFirst(_: void, a: f64, b: f64) bool {
    const na = std.math.isNan(a);
    const nb = std.math.isNan(b);
    if (na and nb) return false;
    if (na) return true;
    if (nb) return false;
    return a < b;
}

/// SAS RANUNI stream: the Lehmer generator (multiplier 397204094, modulus 2^31-1).
fn seedState(seed: f64) u64 {
    return if (seed > 0 and seed < 2147483647) @intFromFloat(@trunc(seed)) else 1;
}
fn lehmerNext(st: *u64) f64 {
    st.* = (16807 * st.*) % 2147483647; // SAS Lehmer/MINSTD (BUG-ranseq)
    return @as(f64, @floatFromInt(st.*)) / 2147483647.0;
}

/// One standard-normal draw (Box-Muller) from a Lehmer seed state.
fn normalVariate(st: *u64) f64 {
    const ua = lehmerNext(st);
    const ub = lehmerNext(st);
    return @sqrt(-2.0 * @log(ua)) * @cos(2.0 * std.math.pi * ub);
}

/// One Gamma(shape a, scale 1) draw (Marsaglia-Tsang 2000) from a Lehmer seed state.
fn gammaVariate(st: *u64, a: f64) f64 {
    var boost: f64 = 1;
    var aa = a;
    if (a < 1) {
        boost = std.math.pow(f64, lehmerNext(st), 1.0 / a);
        aa = a + 1;
    }
    const d = aa - 1.0 / 3.0;
    const cc = 1.0 / @sqrt(9.0 * d);
    while (true) {
        const z = normalVariate(st);
        const v3 = 1.0 + cc * z;
        if (v3 <= 0) continue;
        const v = v3 * v3 * v3;
        if (@log(lehmerNext(st)) < 0.5 * z * z + d - d * v + d * @log(v)) return d * v * boost;
    }
}

/// The variate for a CALL RANxxx routine given its seed state and evaluated params.
/// Mirrors the ranXXX function transforms (functions.zig) over the same Lehmer stream.
fn ranVariate(st: *u64, name: []const u8, p: []const f64) f64 {
    const eq = std.ascii.eqlIgnoreCase;
    if (eq(name, "ranexp")) return -@log(lehmerNext(st));
    if (eq(name, "rancau")) return @tan(std.math.pi * (lehmerNext(st) - 0.5));
    if (eq(name, "rannor")) return normalVariate(st);
    if (eq(name, "rantri")) {
        const h = if (p.len > 0) p[0] else 0.5;
        const u = lehmerNext(st);
        return if (u < h) @sqrt(u * h) else 1.0 - @sqrt((1.0 - u) * (1.0 - h));
    }
    if (eq(name, "ranpoi")) {
        const m = if (p.len > 0) p[0] else 0;
        const lim = @exp(-m);
        var k: f64 = 0;
        var pr: f64 = 1;
        while (true) {
            pr *= lehmerNext(st);
            if (pr <= lim) break;
            k += 1;
        }
        return k;
    }
    if (eq(name, "ranbin")) {
        const n: usize = if (p.len > 0 and p[0] > 0) @intFromFloat(@floor(p[0])) else 0;
        const pp = if (p.len > 1) p[1] else 0;
        var cnt: f64 = 0;
        var i: usize = 0;
        while (i < n) : (i += 1) if (lehmerNext(st) < pp) {
            cnt += 1;
        };
        return cnt;
    }
    if (eq(name, "rantbl")) {
        const u = lehmerNext(st);
        var cum: f64 = 0;
        for (p, 1..) |pv, idx| {
            cum += pv;
            if (u <= cum) return @floatFromInt(idx);
        }
        return @floatFromInt(p.len);
    }
    if (eq(name, "rangam")) return gammaVariate(st, if (p.len > 0) p[0] else 1);
    return 0;
}

/// Ascending order over a Value: numeric by value, character by bytes; a number
/// sorts before any string (so a homogeneous list orders naturally).
fn valLess(_: void, a: Value, b: Value) bool {
    return switch (a) {
        .num => |x| switch (b) {
            .num => |y| x < y,
            .str => true,
        },
        .str => |x| switch (b) {
            .num => false,
            .str => |y| std.mem.order(u8, x, y) == .lt,
        },
    };
}

/// BUG-combcallcrash: a user-supplied n/k CALL arg → nonneg integer. <1 or
/// out-of-range (NaN/±inf/huge — fns.toInt returns null) → 0, so the routine's
/// `k==0`/`k>n` guard no-ops instead of trapping `@intFromFloat`.
fn combN(x: f64) usize {
    const i = fns.toInt(x) orelse return 0;
    return if (i < 1) 0 else @intCast(i);
}

/// BUG-combcallcrash: a user-supplied 1-based "count" CALL arg → 0-based rank
/// clamped to [0, max]. Out-of-range (huge/NaN/inf) clamps to `max` — SAS: a
/// past-the-end count yields the last item — and never traps `@intFromFloat`.
fn combRank(comptime T: type, x: f64, max: T) T {
    const i = fns.toInt(x) orelse return max;
    return if (i < 1) 0 else @min(@as(T, @intCast(i)) - 1, max);
}

/// Binomial coefficient C(n,k) (0 when k>n); small args, no overflow concern.
fn binom(n: usize, k: usize) usize {
    if (k > n) return 0;
    var r: usize = 1;
    var i: usize = 0;
    while (i < k) : (i += 1) r = r * (n - i) / (i + 1);
    return r;
}

/// Fill `buf` (length n) with the 0-based index permutation at Trotter-Johnson
/// (Steinhaus-Johnson-Trotter, minimal-change) rank `rank` — SAS's ALLPERM order.
/// Kreher & Stinson, Combinatorial Algorithms, §2.4.
fn tjUnrank(buf: []usize, n: usize, rank: usize) void {
    if (n == 0) return;
    var pi: [20]usize = undefined; // 1-based pi[1..n]
    pi[1] = 1;
    var r2: usize = 0;
    var i: usize = 2;
    while (i <= n) : (i += 1) {
        var sf: usize = 1; // (n! / i!) = product of (i+1 .. n)
        var m: usize = i + 1;
        while (m <= n) : (m += 1) sf *= m;
        const r1 = rank / sf;
        const k = if (r1 >= i * r2) r1 - i * r2 else 0;
        if (r2 % 2 == 0) { // insert i from the right
            var j: usize = i - 1;
            while (j >= i - k) {
                pi[j + 1] = pi[j];
                if (j == i - k) break;
                j -= 1;
            }
            pi[i - k] = i;
        } else { // insert i from the left
            var j: usize = i - 1;
            while (j >= k + 1) {
                pi[j + 1] = pi[j];
                if (j == k + 1) break;
                j -= 1;
            }
            pi[k + 1] = i;
        }
        r2 = r1;
    }
    for (0..n) |idx| buf[idx] = pi[idx + 1] - 1;
}

/// The k-combinations of {0..n-1} in revolving-door (minimal-change) order — SAS's
/// ALLCOMB order. Recursive: A(n,k) = A(n-1,k), then reverse(A(n-1,k-1) with n-1).
fn revolvingDoor(a: std.mem.Allocator, n: usize, k: usize) error{OutOfMemory}![]const []const usize {
    if (k == 0) {
        const out = try a.alloc([]const usize, 1);
        out[0] = &.{};
        return out;
    }
    if (k == n) {
        const combo = try a.alloc(usize, n);
        for (0..n) |i| combo[i] = i;
        const out = try a.alloc([]const usize, 1);
        out[0] = combo;
        return out;
    }
    var list: std.ArrayList([]const usize) = .empty;
    for (try revolvingDoor(a, n - 1, k)) |cmb| try list.append(a, cmb);
    const with_n = try revolvingDoor(a, n - 1, k - 1);
    var i = with_n.len;
    while (i > 0) : (i -= 1) {
        const base = with_n[i - 1];
        const cmb = try a.alloc(usize, base.len + 1);
        @memcpy(cmb[0..base.len], base);
        cmb[base.len] = n - 1;
        try list.append(a, cmb);
    }
    return list.items;
}

fn toF64(v: Value) f64 {
    return switch (v) {
        .num => |x| x,
        .str => |s| blk: {
            const tr = std.mem.trim(u8, s, " ");
            break :blk if (tr.len == 0) std.math.nan(f64) else (std.fmt.parseFloat(f64, tr) catch std.math.nan(f64));
        },
    };
}

fn stmtHasOutput(s: ast.Stmt) bool {
    return switch (s) {
        // A real OUTPUT statement suppresses the implicit one; the \x00-sentinel
        // MODIFY REPLACE/REMOVE encoding does NOT (it only overrides per-obs, via
        // the run-time obs_handled flag — an untouched obs keeps its implicit REPLACE).
        .output => |names| !(names.len == 1 and names[0].len > 0 and names[0][0] == 0),
        .do_ => |d| for (d.body) |b| {
            if (stmtHasOutput(b)) break true;
        } else false,
        .if_ => |iff| (iff.then_branch != null and stmtHasOutput(iff.then_branch.?.*)) or
            (iff.else_branch != null and stmtHasOutput(iff.else_branch.?.*)),
        else => false,
    };
}

// ── tests ──────────────────────────────────────────────────────────────────

const t = std.testing;

/// True if any collected diagnostic is an ERROR whose message contains `needle`.
fn diagsHave(d: *const diag.Diagnostics, needle: []const u8) bool {
    for (d.list.items) |x| if (x.severity == .err and std.mem.indexOf(u8, x.message, needle) != null) return true;
    return false;
}

/// True if any collected diagnostic is a WARNING whose message contains `needle`.
fn diagsWarn(d: *const diag.Diagnostics, needle: []const u8) bool {
    for (d.list.items) |x| if (x.severity == .warning and std.mem.indexOf(u8, x.message, needle) != null) return true;
    return false;
}

test "GH#22 ISS-dkrocondwarn: KEEP statement of a never-referenced var WARNs and continues; a later-created var stays legal" {
    // typo — KEEP names YY, but the step only ever holds x → DKROCOND=WARN:
    // WARN, step still runs and writes its output, no syntax-check poison.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
        const lines = [_][]const u8{"1"};
        const keepn = [_][]const u8{"yy"};
        const prog = [_]ast.Stmt{ .{ .input = &items }, .{ .datalines = &lines }, .{ .keep = &keepn } };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(diagsWarn(&f.diags, "YY")); // uppercased, as SAS renders it
        try t.expect(diagsWarn(&f.diags, "never been referenced"));
        try t.expect(!diagsHave(&f.diags, "never been referenced")); // WARNING, not ERROR
        try t.expect(!f.diags.hasStepErrors()); // no abort / syntax-check poison
        try t.expect(out.rowCount() == 1); // step still produced its output
    }
    // nuance — KEEP names `later`, CREATED AFTER the keep statement → NO error,
    // and the var reaches the output (validated against the final PDV).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
        const lines = [_][]const u8{"1"};
        const keepn = [_][]const u8{"later"};
        const prog = [_]ast.Stmt{
            .{ .input = &items },
            .{ .datalines = &lines },
            .{ .keep = &keepn },
            .{ .assign = .{ .target = "later", .value = f.bin(.add, f.vbl("x"), f.num(1)) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!diagsHave(&f.diags, "never been referenced"));
        try t.expect(out.indexOf("later") != null);
    }
}

test "GH#75 ISS-uninitvar: a never-set RHS var NOTEs once; retained/assigned vars don't" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    // retain acc 0; acc = acc + 1; y = ghost + 1; z = ghost * 2;
    // `ghost` is read twice, never set → exactly ONE uninitialized NOTE.
    // `acc` is retained + assigned, `y`/`z` are assign targets → none note.
    const rets = [_]ast.RetainItem{.{ .name = "acc", .init = f.num(0) }};
    const prog = [_]ast.Stmt{
        .{ .retain = &rets },
        .{ .assign = .{ .target = "acc", .value = f.bin(.add, f.vbl("acc"), f.num(1)) } },
        .{ .assign = .{ .target = "y", .value = f.bin(.add, f.vbl("ghost"), f.num(1)) } },
        .{ .assign = .{ .target = "z", .value = f.bin(.mul, f.vbl("ghost"), f.num(2)) } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    var uninit_notes: usize = 0;
    for (f.diags.list.items) |d| {
        if (d.severity == .note and std.mem.indexOf(u8, d.message, "is uninitialized") != null) {
            uninit_notes += 1;
            try t.expect(std.mem.indexOf(u8, d.message, "ghost") != null); // only ghost, never acc/y/z
        }
    }
    try t.expectEqual(@as(usize, 1), uninit_notes); // once per var, not per read
    try t.expect(diagsNote(&f.diags, "Variable ghost is uninitialized.")); // exact SAS wording
}

test "NOTE-ofvarlistuninit: `sum(of _numeric_)`/`of _character_` emit NO spurious uninit NOTE; a real uninit var still notes" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    // The parser's expandOf passes the reserved list name through as a plain
    // .variable for RUNTIME expansion (eval.zig), so the uninit scan saw a
    // "variable" that can never be one (Language Reference: Concepts ch.25 reserves the three list
    // names) and noted it — the value was always correct, the NOTE spurious.
    // Dead-branch calls (the fixture evaluator wires no call_fn): the uninit
    // scan is compile-time and walks them anyway; live values are pinned end
    // to end by tests/corpus/of_varlist_uninit.
    const nargs = [_]ast.Expr{.{ .variable = "_numeric_" }};
    const cargs = [_]ast.Expr{.{ .variable = "_character_" }};
    const aargs = [_]ast.Expr{.{ .variable = "_all_" }};
    const dead_num = ast.Stmt{ .assign = .{ .target = "s", .value = f.e(.{ .call = .{ .name = "sum", .args = &nargs } }) } };
    const dead_chr = ast.Stmt{ .assign = .{ .target = "t", .value = f.e(.{ .call = .{ .name = "cats", .args = &cargs } }) } };
    const dead_all = ast.Stmt{ .assign = .{ .target = "u", .value = f.e(.{ .call = .{ .name = "n", .args = &aargs } }) } };
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "a", .value = f.num(1) } },
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &dead_num, .else_branch = null } },
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &dead_chr, .else_branch = null } },
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &dead_all, .else_branch = null } },
        .{ .assign = .{ .target = "g", .value = f.bin(.add, f.vbl("ghost"), f.num(1)) } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    var uninit_notes: usize = 0;
    for (f.diags.list.items) |d| {
        if (d.severity == .note and std.mem.indexOf(u8, d.message, "is uninitialized") != null) {
            uninit_notes += 1;
            try t.expect(std.mem.indexOf(u8, d.message, "ghost") != null); // only ghost
        }
    }
    try t.expectEqual(@as(usize, 1), uninit_notes);
}

test "BUG-putpagenote: put _page_/_all_/_numeric_/_character_ emit NO uninit NOTE; a real uninit var still notes" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    // The PUT directive/list pseudo-names are not PDV reads — no NOTE for them;
    // `ghost` is a genuine uninitialized read → exactly one NOTE, for ghost only.
    const items = [_]ast.PutItem{
        .{ .variable = .{ .name = "_page_" } },
        .{ .variable = .{ .name = "_all_" } },
        .{ .variable = .{ .name = "_numeric_" } },
        .{ .named = .{ .name = "_character_" } },
        .{ .variable = .{ .name = "ghost" } },
    };
    const prog = [_]ast.Stmt{.{ .put = &items }};
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    var uninit_notes: usize = 0;
    for (f.diags.list.items) |d| {
        if (d.severity == .note and std.mem.indexOf(u8, d.message, "is uninitialized") != null) {
            uninit_notes += 1;
            try t.expect(std.mem.indexOf(u8, d.message, "ghost") != null); // only ghost
        }
    }
    try t.expectEqual(@as(usize, 1), uninit_notes);
    try t.expect(diagsNote(&f.diags, "Variable ghost is uninitialized.")); // exact SAS wording
}

test "GAP-atexpression-put: PUT @(expr) clamps zero/negative to column 1 (p.269); a character result and an over-ceiling column both fail LOUD" {
    // The positive/truncating/computed arms are pinned by tests/corpus/
    // put_atexpression.sas; these three cannot be — two are hard ERRORs (the
    // corpus diffs stdout only) and the ceiling one would otherwise pad 40 KB.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        // @(0) and @(-4) → column 1 (io.clampCol, the ONE clamp @n/@var/INPUT's
        // @(expr) share). p.269 spells out only the zero case; its
        // @numeric-variable sibling and p.168 both say "zero or negative".
        const items = [_]ast.PutItem{
            .{ .col_expr = f.num(0) },  .{ .literal = "A" },
            .newline,                   .{ .col_expr = f.num(-4) },
            .{ .literal = "B" },
        };
        const prog = [_]ast.Stmt{.{ .put = &items }};
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expectEqualStrings("A\nB\n", x.log.items); // no leading pad on either line
    }
    {
        // A CHARACTER result is SAS's OTHER parenthesised form, the
        // @(character-expression) string search — unimplemented on INPUT
        // (io.evalColExpr) and identically loud here: silently landing on
        // column 1 would write the WRONG column (D-002/D-003).
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.PutItem{ .{ .col_expr = f.e(.{ .str = "wx" }) }, .{ .literal = "A" } };
        const prog = [_]ast.Stmt{.{ .put = &items }};
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expect(std.mem.indexOf(u8, f.diags.list.items[f.diags.list.items.len - 1].message, "@(character-expression)") != null);
    }
    {
        // BUG-putptroom's ceiling. The parser guards oversized @n LITERALS, but
        // @(expr) has no parse-time value at all, so putColPtr's runtime guard is
        // the ONLY thing between `put @(1e9) x;` and a gigabyte of padding.
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.PutItem{ .{ .col_expr = f.num(40000) }, .{ .literal = "A" } };
        const prog = [_]ast.Stmt{.{ .put = &items }};
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expect(std.mem.indexOf(u8, f.diags.list.items[f.diags.list.items.len - 1].message, "line-size ceiling") != null);
    }
    {
        // …and above clampCol's own 1e15 out-of-range cut-off, where the shared
        // clamp answers "column 1". For INPUT that is a harmless short read; for
        // PUT it would SILENTLY write at the left margin, so the ceiling is
        // checked on the RAW value and this is loud too, like 40000 above.
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.PutItem{ .{ .col_expr = f.num(1e20) }, .{ .literal = "A" } };
        const prog = [_]ast.Stmt{.{ .put = &items }};
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expect(std.mem.indexOf(u8, f.diags.list.items[f.diags.list.items.len - 1].message, "line-size ceiling") != null);
    }
    {
        // A MISSING pointer value (NaN) is not "out of range" — it lands on column
        // 1, exactly as io.ptrCol treats a missing `@var`. It must NOT trip the
        // ceiling guard above (NaN fails every comparison, deliberately).
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.PutItem{ .{ .col_expr = f.vbl("nosuch") }, .{ .literal = "A" } };
        const prog = [_]ast.Stmt{.{ .put = &items }};
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expectEqualStrings("A\n", x.log.items);
    }
}

test "BUG-firstlastnotbyvar: first./last. of a non-BY var gets the uninitialized NOTE (typo'd flag), a genuine BY flag stays silent" {
    // Language Reference: Concepts p.540's payroll program, one letter changed (`first.Departmnt` for
    // `first.Department`): the accumulator never resets, so DDG reports
    // 1,148,000 instead of 448,000 — SAS prints those same numbers AND logs
    // `NOTE: Variable first.Departmnt is uninitialized.` (a NOTE; SAS
    // CONTINUES, so this must never be a hard ERROR). `temp` below is the
    // chapter's salaries table already sorted by Department.
    const depts = [_][]const u8{ "BAD", "BAD", "DDG", "DDG" };
    const cats = [_][]const u8{ "Salaried", "Hourly", "Hourly", "Salaried" };
    const rates = [_]f64{ 20000, 230, 200, 4000 };

    // block 1 — the typo'd flag: the NOTE fires, values stay SAS-faithful.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const temp = f.newDs("temp");
        _ = try temp.addColumn("Department", .char);
        _ = try temp.addColumn("WageCategory", .char);
        _ = try temp.addColumn("WageRate", .num);
        for (depts, cats, rates) |d, c, r|
            try temp.appendRow(&.{ .{ .str = d }, .{ .str = c }, .{ .num = r } });
        try f.lib.put("temp", temp);

        const sets = [_][]const u8{"temp"};
        const bys = [_][]const u8{"Department"};
        const rets = [_]ast.RetainItem{.{ .name = "Payroll", .init = f.num(0) }};
        // if WageCategory="Salaried" then YearlyWage=WageRate*12; else if …="Hourly" then …*2000;
        const then_sal: ast.Stmt = .{ .assign = .{ .target = "YearlyWage", .value = f.bin(.mul, f.vbl("WageRate"), f.num(12)) } };
        const then_hr: ast.Stmt = .{ .assign = .{ .target = "YearlyWage", .value = f.bin(.mul, f.vbl("WageRate"), f.num(2000)) } };
        const else_hr: ast.Stmt = .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("WageCategory"), f.e(.{ .str = "Hourly" })), .then_branch = &then_hr, .else_branch = null } };
        // if first.Departmnt then Payroll=0;   ← the typo (never fires)
        const reset: ast.Stmt = .{ .assign = .{ .target = "Payroll", .value = f.num(0) } };
        // Payroll + YearlyWage;  (the sum statement — retain 0 above makes the
        // plain add exact; the fixture's evaluator wires no call_fn for sum())
        const prog = [_]ast.Stmt{
            .{ .set = &sets },
            .{ .by = &bys },
            .{ .retain = &rets },
            .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("WageCategory"), f.e(.{ .str = "Salaried" })), .then_branch = &then_sal, .else_branch = &else_hr } },
            .{ .if_ = .{ .cond = f.vbl("first.Departmnt"), .then_branch = &reset, .else_branch = null } },
            .{ .assign = .{ .target = "Payroll", .value = f.bin(.add, f.vbl("Payroll"), f.vbl("YearlyWage")) } },
            .{ .if_ = .{ .cond = f.vbl("last.Department"), .then_branch = null, .else_branch = null } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);

        // SAS's NOTE — once, reference case preserved, NOTE severity only.
        try t.expect(diagsNote(&f.diags, "Variable first.Departmnt is uninitialized."));
        try t.expect(!f.diags.hasStepErrors());
        // …and the numbers stay the SAS-faithful typo'd ones: BAD 700,000 and
        // DDG 1,148,000 (the NOTE is the only behavior change).
        try t.expectEqual(@as(usize, 2), out.rowCount());
        const pc = out.indexOf("Payroll").?;
        try t.expectEqualStrings("BAD", out.row(0)[out.indexOf("Department").?].str);
        try t.expectEqual(@as(f64, 700000), out.row(0)[pc].num);
        try t.expectEqualStrings("DDG", out.row(1)[out.indexOf("Department").?].str);
        try t.expectEqual(@as(f64, 1148000), out.row(1)[pc].num);
    }
    // block 2 — the CORRECT spelling: no NOTE, accumulator resets (DDG = 448,000).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const temp = f.newDs("temp");
        _ = try temp.addColumn("Department", .char);
        _ = try temp.addColumn("WageCategory", .char);
        _ = try temp.addColumn("WageRate", .num);
        for (depts, cats, rates) |d, c, r|
            try temp.appendRow(&.{ .{ .str = d }, .{ .str = c }, .{ .num = r } });
        try f.lib.put("temp", temp);

        const sets = [_][]const u8{"temp"};
        const bys = [_][]const u8{"Department"};
        const rets = [_]ast.RetainItem{.{ .name = "Payroll", .init = f.num(0) }};
        const then_sal: ast.Stmt = .{ .assign = .{ .target = "YearlyWage", .value = f.bin(.mul, f.vbl("WageRate"), f.num(12)) } };
        const then_hr: ast.Stmt = .{ .assign = .{ .target = "YearlyWage", .value = f.bin(.mul, f.vbl("WageRate"), f.num(2000)) } };
        const else_hr: ast.Stmt = .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("WageCategory"), f.e(.{ .str = "Hourly" })), .then_branch = &then_hr, .else_branch = null } };
        const reset: ast.Stmt = .{ .assign = .{ .target = "Payroll", .value = f.num(0) } };
        const prog = [_]ast.Stmt{
            .{ .set = &sets },
            .{ .by = &bys },
            .{ .retain = &rets },
            .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("WageCategory"), f.e(.{ .str = "Salaried" })), .then_branch = &then_sal, .else_branch = &else_hr } },
            .{ .if_ = .{ .cond = f.vbl("first.Department"), .then_branch = &reset, .else_branch = null } },
            .{ .assign = .{ .target = "Payroll", .value = f.bin(.add, f.vbl("Payroll"), f.vbl("YearlyWage")) } },
            .{ .if_ = .{ .cond = f.vbl("last.Department"), .then_branch = null, .else_branch = null } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);

        try t.expect(!diagsNote(&f.diags, "is uninitialized")); // genuine BY flags stay silent
        try t.expectEqual(@as(usize, 2), out.rowCount());
        const pc = out.indexOf("Payroll").?;
        try t.expectEqual(@as(f64, 700000), out.row(0)[pc].num);
        try t.expectEqual(@as(f64, 448000), out.row(1)[pc].num);
    }
}

test "BUG-spuriousnote: MERGE in= flags + hash-method targets note NO uninit NOTE; a real uninit var still notes" {
    // 1. `merge a(in=ina) b(in=inb); z = (ina = 1);` — ina/inb are set per read
    // by the merge driver, never PDV-seeded → no NOTE.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const aa = f.newDs("a");
        _ = try aa.addColumn("id", .num);
        try aa.appendRow(&.{.{ .num = 1 }});
        try f.lib.put("a", aa);
        const bb = f.newDs("b");
        _ = try bb.addColumn("id", .num);
        try bb.appendRow(&.{.{ .num = 1 }});
        try f.lib.put("b", bb);

        const names = [_][]const u8{ "a(in=ina)", "b(in=inb)" };
        const bys = [_][]const u8{"id"};
        const prog = [_]ast.Stmt{
            .{ .merge = &names },
            .{ .by = &bys },
            .{ .assign = .{ .target = "z", .value = f.bin(.eq, f.vbl("ina"), f.num(1)) } },
            // `if ina and inb;` — both flags read in a condition
            .{ .if_ = .{ .cond = f.bin(.@"and", f.vbl("ina"), f.vbl("inb")), .then_branch = null, .else_branch = null } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!diagsNote(&f.diags, "is uninitialized")); // no spurious NOTE
        try t.expectEqual(@as(usize, 1), out.rowCount()); // values still correct
    }
    // 2. `rc = it.first(); do while (rc = 0); rc = it.next(); end;` — rc is written
    // by the hash op at run time, never seeded by declareStmt → no NOTE.
    // (BUG-hiterbadhash: first()/next() on the bare HASH `h` — an unbound
    // iterator — is a loud ERROR now; the walk goes through a declared hiter.)
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        // p.613 (BUG-hashdefinenovar): key/data vars must exist outside the
        // hash — model the `length k 8;` a legal program carries.
        _ = try f.pdv.declare("k", .num);

        const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
        const iter_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "h" }) }};
        const body = [_]ast.Stmt{.{ .hash_op = .{ .target = "rc", .obj = "it", .method = "next", .args = &.{} } }};
        const prog = [_]ast.Stmt{
            .{ .hash_decl = .{ .name = "h", .args = &.{} } },
            .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
            .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
            .{ .hash_decl = .{ .name = "it", .args = &iter_arg } },
            .{ .hash_op = .{ .target = "rc", .obj = "it", .method = "first", .args = &.{} } },
            .{ .do_ = .{ .header = .{ .while_ = f.bin(.eq, f.vbl("rc"), f.num(0)) }, .body = &body } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!diagsNote(&f.diags, "is uninitialized")); // no spurious NOTE
    }
    // 3. control: same shapes but a genuinely never-assigned var STILL notes.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const aa = f.newDs("a");
        _ = try aa.addColumn("id", .num);
        try aa.appendRow(&.{.{ .num = 1 }});
        try f.lib.put("a", aa);
        const names = [_][]const u8{"a(in=ina)"};
        const prog = [_]ast.Stmt{
            .{ .merge = &names },
            .{ .assign = .{ .target = "z", .value = f.bin(.add, f.vbl("ghost"), f.num(1)) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(diagsNote(&f.diags, "Variable ghost is uninitialized.")); // GH#75 still fires
        try t.expect(!diagsNote(&f.diags, "Variable ina is uninitialized.")); // …but not for the flag
    }
}

test "PERF-arraydeclquad: a wide _temporary_ array declares O(N) — elements stay dropped, values intact" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // N=4000 temporary elements: the old linear nameIn made seeding the schema
    // O(N²) — 16M case-insensitive compares for a decl-only step.
    const N = 4000;
    const elems = try f.a().alloc([]const u8, N);
    for (elems, 0..) |*e, k| e.* = try std.fmt.allocPrint(f.a(), "t{d}", .{k + 1});
    const prog = [_]ast.Stmt{
        .{ .array = .{ .name = "t", .elements = elems, .inits = &.{}, .temporary = true } },
        .{ .assign = .{ .target = "t1", .value = f.num(41) } },
        .{ .assign = .{ .target = "total", .value = f.bin(.add, f.vbl("t1"), f.num(1)) } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    // every temporary element is dropped; only total reaches the output
    try t.expectEqual(@as(usize, 1), out.columns.items.len);
    try t.expectEqualStrings("total", out.columns.items[0].name);
    try t.expectEqual(@as(f64, 42), out.row(0)[0].num);
    // membership stays exact + case-insensitive through the hash
    try t.expect(!x.included("T4000"));
    try t.expect(x.included("TOTAL"));
}

test "PERF-arraydeclquad: a pfx: wildcard list keeps the linear prefix scan after freeze" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    try x.drops.appendSlice(f.a(), &.{ "dtm_:", "Gone" });
    try x.retained.appendSlice(f.a(), &.{ "KeepMe", "alSo" });
    try x.freezeNameLists();

    // wildcard entry → the drops list stays linear, prefix still matches
    try t.expect(!x.included("dtm_alpha"));
    try t.expect(!x.included("GONE")); // exact, case-insensitive
    try t.expect(x.included("other"));
    // no wildcard in retained → hashed, still case-insensitive
    try t.expect(x.isRetained("keepme"));
    try t.expect(x.isRetained("ALSO"));
    try t.expect(!x.isRetained("nope"));
}

fn diagsNote(d: *const diag.Diagnostics, needle: []const u8) bool {
    for (d.list.items) |x| if (x.severity == .note and std.mem.indexOf(u8, x.message, needle) != null) return true;
    return false;
}

/// Arena-backed AST builders + a wired executor, so tests read like the SAS
/// program they model.
const Fixture = struct {
    arena: std.heap.ArenaAllocator,
    pdv: Pdv = undefined,
    diags: diag.Diagnostics = undefined,
    ev: eval.Evaluator = undefined,
    lib: Library = undefined,

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
    }
    fn prime(self: *Fixture) void {
        const alloc = self.arena.allocator();
        self.pdv = Pdv.init(alloc);
        self.diags = diag.Diagnostics.init(alloc);
        self.lib = Library.init(alloc);
        self.ev = .{ .arena = alloc, .pdv = &self.pdv, .diags = &self.diags };
    }
    fn exec(self: *Fixture) Executor {
        return Executor.init(self.arena.allocator(), &self.pdv, &self.diags, &self.ev, &self.lib);
    }
    fn a(self: *Fixture) std.mem.Allocator {
        return self.arena.allocator();
    }
    fn e(self: *Fixture, x: ast.Expr) *const ast.Expr {
        const p = self.a().create(ast.Expr) catch unreachable;
        p.* = x;
        return p;
    }
    fn num(self: *Fixture, x: f64) *const ast.Expr {
        return self.e(.{ .num = x });
    }
    fn vbl(self: *Fixture, n: []const u8) *const ast.Expr {
        return self.e(.{ .variable = n });
    }
    fn bin(self: *Fixture, op: ast.BinOp, l: *const ast.Expr, r: *const ast.Expr) *const ast.Expr {
        return self.e(.{ .binary = .{ .op = op, .lhs = l, .rhs = r } });
    }
    fn newDs(self: *Fixture, name: []const u8) *Dataset {
        const ds = self.a().create(Dataset) catch unreachable;
        ds.* = Dataset.init(self.a(), name);
        return ds;
    }
};

fn fixture() Fixture {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

test "Library index: find/replace O(1), stays correct across proc-style rename + delete (PERF-libscan)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    const lib = &f.lib;

    // create d1..d5; find resolves each (WORK-stripped, case-insensitive)
    var i: usize = 1;
    while (i <= 5) : (i += 1) {
        const nm = try std.fmt.allocPrint(f.a(), "d{d}", .{i});
        try lib.putInput(nm, f.newDs(nm));
    }
    try t.expectEqual(@as(usize, 5), lib.names.items.len);
    try t.expect(lib.find("D3") != null); // case-insensitive
    try t.expect(lib.find("work.d5") != null); // work. stripped
    try t.expect(lib.find("d6") == null); // genuine miss

    // replace d3 in place (data d3; …) — same slot, no duplicate row
    const rep = f.newDs("d3");
    try lib.putInput("d3", rep);
    try t.expectEqual(@as(usize, 5), lib.names.items.len);
    try t.expectEqual(rep, lib.find("d3").?);

    // simulate PROC DATASETS `change d1=dm;` — proc.zig mutates names/sets DIRECTLY
    // (in place, no length change), so the index entry for d1 is now stale.
    lib.names.items[0] = "dm";
    lib.sets.items[0].name = "dm";
    try t.expect(lib.find("dm") != null); // scan-fallback keeps the renamed member findable
    try t.expect(lib.find("d1") == null); // old name is gone

    // simulate PROC DATASETS `delete d4;` — direct orderedRemove shrinks the arrays;
    // the next lookup detects count != len and rebuilds the index.
    _ = lib.names.orderedRemove(3); // d4 slot
    _ = lib.sets.orderedRemove(3);
    try t.expectEqual(@as(usize, 4), lib.names.items.len);
    try t.expect(lib.find("d4") == null); // deleted
    try t.expect(lib.find("d5") != null); // survivor still resolves after reindex/shift
    try t.expect(lib.find("dm") != null); // and the earlier rename target too
    try t.expectEqual(lib.index.count(), lib.names.items.len); // index rebuilt to match
}

test "GH#15 ISS-readonlyguard: output access to a read-only libref fails loud; reads allowed" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    f.lib.diags = &f.diags;
    f.lib.readonly_refs = &.{"src"};

    // readonlyOut keys on the LIBREF, case-insensitive; one-level names are WORK.
    try t.expect(f.lib.readonlyOut("src.ec"));
    try t.expect(f.lib.readonlyOut("SRC.EC"));
    try t.expect(!f.lib.readonlyOut("work.t"));
    try t.expect(!f.lib.readonlyOut("ec"));

    // OUTPUT access (create/replace) → ExecError + a captured SAS "read-only" ERROR.
    try t.expectError(error.ExecError, f.lib.put("src.ec", f.newDs("src.ec")));
    try t.expect(f.diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[0].message, "read-only library") != null);
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[0].message, "SRC.EC") != null);

    // Preloading the SAME member as an INPUT is a legal read → allowed, and readable.
    try f.lib.putInput("src.ec", f.newDs("src.ec"));
    try t.expect(f.lib.find("src.ec") != null);

    // A non-readonly (WORK) output — e.g. PROC SORT OUT=WORK.x — installs fine.
    try f.lib.put("work.t", f.newDs("work.t"));
    try t.expect(f.lib.find("work.t") != null);
}

test "MULTISET-impl: `set a; set b;` reads both in parallel (one-to-one), stops at the shorter" {
    // SAS 9.4: each SET is executable with its OWN read cursor; iteration k reads
    // a[k] and b[k]. The step ends when EITHER SET hits EOF (current obs not output),
    // so a 3-row a with a 2-row b yields 2 obs.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a1 = f.newDs("a");
    _ = try a1.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3 }) |v| try a1.appendRow(&.{.{ .num = v }});
    try f.lib.put("a", a1);
    const b1 = f.newDs("b");
    _ = try b1.addColumn("y", .num);
    for ([_]f64{ 10, 20 }) |v| try b1.appendRow(&.{.{ .num = v }});
    try f.lib.put("b", b1);

    const na = [_][]const u8{"a"};
    const nb = [_][]const u8{"b"};
    const prog = [_]ast.Stmt{ .{ .set = &na }, .{ .set = &nb } };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const xi = out.indexOf("x").?; // driver columns come first (source order)
    const yi = out.indexOf("y").?;
    try t.expectEqual(@as(usize, 2), out.rowCount()); // min(3, 2)
    try t.expectEqual(@as(f64, 1), out.row(0)[xi].num);
    try t.expectEqual(@as(f64, 10), out.row(0)[yi].num);
    try t.expectEqual(@as(f64, 2), out.row(1)[xi].num);
    try t.expectEqual(@as(f64, 20), out.row(1)[yi].num);
}

test "MULTISET-impl: `if _n_=1 then set summary;` reads the lookup once and RETAINS it" {
    // Classic SAS lookup idiom: the conditional SET fires only on _n_=1, and a
    // SET'd variable is retained until its next read — so the summary value sticks
    // to every obs of the driving dataset.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const big = f.newDs("big");
    _ = try big.addColumn("g", .num);
    for ([_]f64{ 1, 2, 3 }) |v| try big.appendRow(&.{.{ .num = v }});
    try f.lib.put("big", big);
    const sm = f.newDs("summary");
    _ = try sm.addColumn("s", .num);
    try sm.appendRow(&.{.{ .num = 99 }});
    try f.lib.put("summary", sm);

    const nbig = [_][]const u8{"big"};
    const nsm = [_][]const u8{"summary"};
    const setsm: ast.Stmt = .{ .set = &nsm };
    const prog = [_]ast.Stmt{
        .{ .set = &nbig },
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("_n_"), f.num(1)), .then_branch = &setsm, .else_branch = null } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const gi = out.indexOf("g").?;
    const si = out.indexOf("s").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    for ([_]f64{ 1, 2, 3 }, 0..) |wg, i| {
        try t.expectEqual(wg, out.row(i)[gi].num);
        try t.expectEqual(@as(f64, 99), out.row(i)[si].num); // retained across all obs
    }
}

test "DOWLOOP-impl: `do until(last.grp); set x; by grp; ...` sums per group, one obs per group" {
    // SAS 9.4 DOW loop: the inner SET reads the NEXT obs each DO iteration; the
    // body accumulates across the group; the outer pass outputs once. first./last.
    // computed at the inner read so `until(last.grp)` terminates the group.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const xd = f.newDs("x"); // grp, amt — sorted by grp
    _ = try xd.addColumn("grp", .num);
    _ = try xd.addColumn("amt", .num);
    try xd.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try xd.appendRow(&.{ .{ .num = 1 }, .{ .num = 20 } });
    try xd.appendRow(&.{ .{ .num = 2 }, .{ .num = 30 } });
    try f.lib.put("x", xd);

    const nx = [_][]const u8{"x"};
    const bygrp = [_][]const u8{"grp"};
    const reset: ast.Stmt = .{ .assign = .{ .target = "total", .value = f.num(0) } };
    const body = [_]ast.Stmt{
        .{ .set = &nx },
        .{ .by = &bygrp },
        .{ .if_ = .{ .cond = f.vbl("first.grp"), .then_branch = &reset, .else_branch = null } },
        .{ .assign = .{ .target = "total", .value = f.bin(.add, f.vbl("total"), f.vbl("amt")) } },
    };
    const ritems = [_]ast.RetainItem{.{ .name = "total", .init = f.num(0) }}; // sum var: retained
    const empty_out = [_][]const u8{};
    const prog = [_]ast.Stmt{
        .{ .retain = &ritems },
        .{ .do_ = .{ .header = .{ .until_ = f.vbl("last.grp") }, .body = &body } },
        .{ .output = &empty_out },
    };

    var out = Dataset.init(f.a(), "sums");
    try x.run(&prog, &out);

    const gi = out.indexOf("grp").?;
    const ti = out.indexOf("total").?;
    try t.expectEqual(@as(usize, 2), out.rowCount()); // one obs per group, no hang
    try t.expectEqual(@as(f64, 1), out.row(0)[gi].num);
    try t.expectEqual(@as(f64, 30), out.row(0)[ti].num); // 10+20
    try t.expectEqual(@as(f64, 2), out.row(1)[gi].num);
    try t.expectEqual(@as(f64, 30), out.row(1)[ti].num); // 30
}

test "DOWLOOP-impl: a SET in an ITERATIVE DO (no POINT=) still fails LOUD, not silent/hang" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const nx = [_][]const u8{"x"};
    const body = [_]ast.Stmt{.{ .set = &nx }};
    const prog = [_]ast.Stmt{.{ .do_ = .{
        .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(3), .by = null } },
        .body = &body,
    } }};
    var out = Dataset.init(f.a(), "work.out");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "iterative DO"));
}

test "BUG-dowinsideifhang: SET in an IF-wrapped DO UNTIL terminates (reads at the node, EOF stops the step)" {
    // data o; if 1 then do until(e); set a end=e; end; run; — was an
    // unbounded-memory infinite loop (QA tick307 F2: 100% CPU, ~60 MB/s,
    // never exits): detectDowSet's top-level walk could not see the
    // IF-wrapped DOW and the SET was inert, so e never fired. The .do_ arm of
    // collectExtraSetsStmt (BUG-doblocksourceinert) registers it as an
    // executable extra SET: reads fire at the node, e flags the last obs, EOF
    // at the next pass stops the step without output — the same 1-obs/last-row
    // result as the pinned `do until(e); if 1 then set a end=e; end;` sibling
    // (set_nested_opts F1). Termination verified under `timeout` before
    // pinning; a regression to the hang wedges this test, which is the point.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("v", .num);
    try a_ds.appendRow(&.{.{ .num = 10 }});
    try a_ds.appendRow(&.{.{ .num = 20 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{ "a", "\x00end=e" };
    const set_stmt = ast.Stmt{ .set = &names };
    const body = [_]ast.Stmt{set_stmt};
    const dow = ast.Stmt{ .do_ = .{ .header = .{ .until_ = f.vbl("e") }, .body = &body } };
    const prog = [_]ast.Stmt{.{ .if_ = .{ .cond = f.num(1), .then_branch = &dow, .else_branch = null } }};
    var out = Dataset.init(f.a(), "o");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 1), out.rowCount()); // one outer pass, last row
    try t.expectEqual(@as(f64, 20), out.row(0)[out.indexOf("v").?].num);
}

test "BUG-dowinsideifhang: MERGE/UPDATE/MODIFY in a DO UNTIL/WHILE fails LOUD — IF-wrapped and top-level agree" {
    // The same shape with a runtime-inert source can never terminate (nothing
    // drives the end condition; the source's read never fires). opensas drives
    // only a SET in a DOW loop, so both the IF-wrapped and the top-level form
    // ERROR at compile time (D-002) instead of spinning memory without bound.
    var f = fixture();
    defer f.deinit();
    f.prime();
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("k", .num);
    try b_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("b", b_ds);

    const mab = [_][]const u8{ "a", "b" };
    const byk = [_][]const u8{"k"};
    const body = [_]ast.Stmt{ .{ .merge = &mab }, .{ .by = &byk } };
    const dow = ast.Stmt{ .do_ = .{ .header = .{ .until_ = f.vbl("e") }, .body = &body } };

    var x1 = f.exec();
    const wrapped = [_]ast.Stmt{.{ .if_ = .{ .cond = f.num(1), .then_branch = &dow, .else_branch = null } }};
    var out1 = Dataset.init(f.a(), "o1");
    try t.expectError(error.ExecError, x1.run(&wrapped, &out1));
    try t.expect(diagsHave(&f.diags, "only a SET can drive a DOW loop"));
    try t.expectEqual(@as(usize, 0), out1.rowCount());

    var x2 = f.exec();
    const toplevel = [_]ast.Stmt{dow};
    var out2 = Dataset.init(f.a(), "o2");
    try t.expectError(error.ExecError, x2.run(&toplevel, &out2));
}

test "BUG-setstmtorder: statements BEFORE the driving SET run BEFORE its read (prefix sees missing then last-read values)" {
    // Language Reference: Concepts Ch.24: the read happens where the SET statement sits. Program:
    //   pre = k;        <- prefix: iter1 k missing, iter2 k=1 (SET vars are
    //   set a;              NOT reset per iteration — Language Reference: Concepts p.562)
    //   post = k;       <- suffix: the just-read value
    //   n = _n_;        <- _N_ is already live in the prefix (guardrail b)
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try a_ds.appendRow(&.{.{ .num = 2 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{"a"};
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "pre", .value = f.vbl("k") } },
        .{ .assign = .{ .target = "n", .value = f.vbl("_n_") } },
        .{ .set = &names },
        .{ .assign = .{ .target = "post", .value = f.vbl("k") } },
    };
    var out = Dataset.init(f.a(), "o");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), out.rowCount());
    const pi = out.indexOf("pre").?;
    const qi = out.indexOf("post").?;
    const ni = out.indexOf("n").?;
    try t.expect(out.row(0)[pi].num != out.row(0)[pi].num); // iter1 pre: missing
    try t.expectEqual(@as(f64, 1), out.row(0)[qi].num);
    try t.expectEqual(@as(f64, 1), out.row(0)[ni].num); // _N_ live in the prefix
    try t.expectEqual(@as(f64, 1), out.row(1)[pi].num); // iter2 pre: last-read value
    try t.expectEqual(@as(f64, 2), out.row(1)[qi].num);
    try t.expectEqual(@as(f64, 2), out.row(1)[ni].num);
}

test "BUG-setstmtorder: a nested driver (IF-branch SET) keeps read-first — no split" {
    // Guardrail (a): only a DIRECT top-level driver splits. `set a;` inside
    // `if _n_=1 then …` stays an executable extra whose node read fires where
    // it sits; the top-level `set b;` drives and still reads first.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("p", .num);
    try a_ds.appendRow(&.{.{ .num = 99 }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("k", .num);
    try b_ds.appendRow(&.{.{ .num = 1 }});
    try b_ds.appendRow(&.{.{ .num = 2 }});
    try f.lib.put("b", b_ds);

    const an = [_][]const u8{"a"};
    const bn = [_][]const u8{"b"};
    const set_a = ast.Stmt{ .set = &an };
    const prog = [_]ast.Stmt{
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("_n_"), f.num(1)), .then_branch = &set_a, .else_branch = null } },
        .{ .set = &bn },
    };
    var out = Dataset.init(f.a(), "o");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), out.rowCount()); // b drives; p=99 read once, retained
    try t.expectEqual(@as(f64, 99), out.row(1)[out.indexOf("p").?].num);
}

test "BUG-setstmtorder: a GOTO crossing the driving SET fails LOUD (no silent jump-drop)" {
    // The split cannot model a transfer over the read (SAS would skip/re-run
    // it) — D-002: a visible ERROR, never a silently truncated jump.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{"a"};
    const prog = [_]ast.Stmt{
        .{ .goto = "skid" },
        .{ .set = &names },
        .{ .label = "skid" },
        .{ .assign = .{ .target = "x", .value = f.num(1) } },
    };
    var out = Dataset.init(f.a(), "o");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "crosses the driving"));
}

test "BUG-controlflownesting: a LINK from INSIDE a DO loop resumes at the call site, not after the loop (F1)" {
    // retain total 0; do i=1 to 3; link addup; total=total+100; end; return;
    // addup: total=total+i; return;
    // Each RETURN must land back INSIDE the loop body: total = (1+100)+(2+100)+(3+100).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const body = [_]ast.Stmt{
        .{ .link = "addup" },
        .{ .assign = .{ .target = "total", .value = f.bin(.add, f.vbl("total"), f.num(100)) } },
    };
    const ritems = [_]ast.RetainItem{.{ .name = "total", .init = f.num(0) }};
    const prog = [_]ast.Stmt{
        .{ .retain = &ritems },
        .{ .do_ = .{ .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(3), .by = null } }, .body = &body } },
        .{ .return_ = {} },
        .{ .label = "addup" },
        .{ .assign = .{ .target = "total", .value = f.bin(.add, f.vbl("total"), f.vbl("i")) } },
        .{ .return_ = {} },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    try t.expectEqual(@as(usize, 1), out.rowCount());
    const ti = out.indexOf("total").?;
    try t.expectEqual(@as(f64, 306), out.row(0)[ti].num); // not 1 (F1's abandoned loop)
}

test "BUG-controlflownesting: GOTO/LINK to an UNDEFINED label fails LOUD at compile time (F3)" {
    // SAS errors at compile time and the step does not execute — no silent rc-0 stop.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const prog = [_]ast.Stmt{
        .{ .goto = "nowhere" },
        .{ .link = "alsonowhere" },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out); // reports both, halts before running — no ExecError throw
    try t.expect(diagsHave(&f.diags, "label nowhere is not defined"));
    try t.expect(diagsHave(&f.diags, "label alsonowhere is not defined"));
    try t.expectEqual(@as(usize, 0), out.rowCount());
}

test "CALL MISSING sets numeric args to . and char args to blank, leaving others" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // x=42 (num), s="abc" (char), other=7 (num) — CALL MISSING must touch only x, s
    try f.pdv.set("x", .{ .num = 42 });
    _ = try f.pdv.define("s", .char);
    try f.pdv.set("s", .{ .str = "abc" });
    try f.pdv.set("other", .{ .num = 7 });

    // call missing(x, s);
    const args = [_]ast.Expr{ .{ .variable = "x" }, .{ .variable = "s" } };
    const stmt: ast.Stmt = .{ .call_ = .{ .name = "missing", .args = &args } };
    _ = try x.runStmt(&stmt);

    try t.expect(f.pdv.get("x").?.isMissing()); // numeric → .
    try t.expectEqualStrings("", f.pdv.get("s").?.str); // char → blank
    try t.expectEqual(@as(f64, 7), f.pdv.get("other").?.num); // untouched

    // an unknown routine is a hard ERROR that ABORTS the step (NOTE-callnohalt)
    const noop: ast.Stmt = .{ .call_ = .{ .name = "nosuchroutine", .args = &.{} } };
    try t.expectError(error.ExecError, x.runStmt(&noop));
    try t.expect(diagsHave(&f.diags, "CALL nosuchroutine() is not supported"));
}

test "bare output fans out to every DATA-named dataset; named output routes single (BUG-multioutput)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // `data m1 m2; …` — main.zig registers the extra up front (0-obs creation)
    // and hands it to the executor via extra_outs.
    const primary = f.newDs("m1");
    const extra = f.newDs("m2");
    try f.lib.putInput("m2", extra);
    x.cur_out = primary;
    x.extra_outs = &.{extra};
    try f.pdv.set("a", .{ .num = 7 });

    // bare `output;` → BOTH datasets get the observation (SAS Language Reference: Concepts DATA stmt)
    _ = try x.runStmt(&.{ .output = &.{} });
    try t.expectEqual(@as(usize, 1), primary.rows.items.len);
    try t.expectEqual(@as(usize, 1), extra.rows.items.len);

    // `output m2;` → only m2 (explicit routing unchanged)
    const names = [_][]const u8{"m2"};
    _ = try x.runStmt(&.{ .output = &names });
    try t.expectEqual(@as(usize, 1), primary.rows.items.len);
    try t.expectEqual(@as(usize, 2), extra.rows.items.len);
}

test "BUG-outputundeclared: `output <undeclared>;` is a loud ERROR, no phantom dataset" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // `data rest; set x; output rst;` — rst is a typo, NOT the declared output.
    const primary = f.newDs("rest");
    x.cur_out = primary;
    try f.pdv.set("a", .{ .num = 1 });
    const bad = [_][]const u8{"rst"};
    try t.expectError(error.ExecError, x.runStmt(&.{ .output = &bad }));
    try t.expect(diagsHave(&f.diags, "not in the list of output data sets"));
    try t.expect(f.lib.find("rst") == null); // no phantom dataset registered
    try t.expectEqual(@as(usize, 0), primary.rows.items.len); // nothing half-written

    // `data a b; … output a; output b;` — declared names still route fine.
    const b = f.newDs("b");
    x.extra_outs = &.{b};
    const an = [_][]const u8{"rest"}; // primary by name (case-insensitive)
    _ = try x.runStmt(&.{ .output = &an });
    const bn = [_][]const u8{"B"};
    _ = try x.runStmt(&.{ .output = &bn });
    try t.expectEqual(@as(usize, 1), primary.rows.items.len);
    try t.expectEqual(@as(usize, 1), b.rows.items.len);
}

test "CALL EXECUTE queues program text FIFO; non-char and %nrstr forms fail LOUD (FEAT-callexecute)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // char argument → appended to the library queue, FIFO across invocations
    const a1 = [_]ast.Expr{.{ .str = "data _null_; put \"one\"; run;" }};
    _ = try x.runStmt(&.{ .call_ = .{ .name = "execute", .args = &a1 } });
    const a2 = [_]ast.Expr{.{ .str = "proc print data=d; run;" }};
    _ = try x.runStmt(&.{ .call_ = .{ .name = "execute", .args = &a2 } });
    try t.expectEqual(@as(usize, 2), f.lib.execute_queue.items.len);
    try t.expectEqualStrings("data _null_; put \"one\"; run;", f.lib.execute_queue.items[0]);
    try t.expectEqualStrings("proc print data=d; run;", f.lib.execute_queue.items[1]);
    try t.expect(!f.diags.hasErrors());

    // numeric argument → captured ERROR (D-003), nothing queued (D-002), and the
    // step STOPS (AUDIT-errhaltclass) so no output member is written over a live
    // one. Severity (error vs SAS's possible num->char conversion) is
    // ORACLE-callexecutenum; the halt class holds either way.
    const a3 = [_]ast.Expr{.{ .num = 42 }};
    try t.expectError(error.ExecError, x.runStmt(&.{ .call_ = .{ .name = "execute", .args = &a3 } }));
    try t.expect(f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), f.lib.execute_queue.items.len);

    // %nrstr-style macro quoting → captured ERROR, nothing queued, and the step
    // STOPS (AUDIT-errhaltclass): an unsupported feature must not no-op, and a
    // halt is what keeps main.zig's `lib.put(name, ds)` — which sits AFTER
    // `try ex.run(...)` — from replacing a live member with the step's output.
    const a4 = [_]ast.Expr{.{ .str = "%nrstr(data &x; run;)" }};
    try t.expectError(error.ExecError, x.runStmt(&.{ .call_ = .{ .name = "execute", .args = &a4 } }));
    try t.expect(diagsHave(&f.diags, "macro-quoting functions"));
    try t.expectEqual(@as(usize, 2), f.lib.execute_queue.items.len);

    // wrong arity → captured ERROR, nothing queued, step stops. Unlike the
    // numeric case this half is unambiguous: no num->char reading rescues a call
    // with 0 (or 2+) arguments when the syntax is CALL EXECUTE(argument).
    try t.expectError(error.ExecError, x.runStmt(&.{ .call_ = .{ .name = "execute", .args = &.{} } }));
    try t.expectEqual(@as(usize, 2), f.lib.execute_queue.items.len);
}

test "CALL SYMPUT/SYMPUTX write macro variables to the library store (G-callroutines)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    try f.pdv.set("v", .{ .num = 100 });
    // call symput('maxv', v); — numeric converts via BEST12.: right-justified
    // 12-char field (leading blanks), UNtrimmed, + the num→char NOTE
    // (BUG-symputnumfmt; SYMPUTX below is the one that trims)
    const a1 = [_]ast.Expr{ .{ .str = "maxv" }, .{ .variable = "v" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "symput", .args = &a1 } });
    try t.expectEqualStrings("         100", x.lib.macroVar("maxv").?);
    try t.expect(f.diags.list.items.len == 1);
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[0].message, "converted to character") != null);

    // call symputx('NM', '  hi  '); — SYMPUTX trims; the name is case-insensitive
    const a2 = [_]ast.Expr{ .{ .str = "NM" }, .{ .str = "  hi  " } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "symputx", .args = &a2 } });
    try t.expectEqualStrings("hi", x.lib.macroVar("nm").?);

    // SYMPUT name: trailing blanks trimmed; a LEADING blank is an ERROR
    const a3 = [_]ast.Expr{ .{ .str = "trail  " }, .{ .str = "ok" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "symput", .args = &a3 } });
    try t.expectEqualStrings("ok", x.lib.macroVar("trail").?);
    const a4 = [_]ast.Expr{ .{ .str = " bad" }, .{ .str = "x" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "symput", .args = &a4 } });
    try t.expect(f.diags.hasErrors());
    try t.expect(x.lib.macroVar("bad") == null);
}

test "CALL SORTN/SORTC/SCAN/CATS/CATT/CATX update argument variables in place" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // CALL SORTN(a,b,c): 30,10,20 → 10,20,30
    try f.pdv.set("a", .{ .num = 30 });
    try f.pdv.set("b", .{ .num = 10 });
    try f.pdv.set("c", .{ .num = 20 });
    const sn = [_]ast.Expr{ .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "sortn", .args = &sn } });
    try t.expectEqual(@as(f64, 10), f.pdv.get("a").?.num);
    try t.expectEqual(@as(f64, 20), f.pdv.get("b").?.num);
    try t.expectEqual(@as(f64, 30), f.pdv.get("c").?.num);

    // CALL SORTC(p,q): "cat","apple" → "apple","cat"
    _ = try f.pdv.define("p", .char);
    _ = try f.pdv.define("q", .char);
    try f.pdv.set("p", .{ .str = "cat" });
    try f.pdv.set("q", .{ .str = "apple" });
    const sc = [_]ast.Expr{ .{ .variable = "p" }, .{ .variable = "q" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "sortc", .args = &sc } });
    try t.expectEqualStrings("apple", f.pdv.get("p").?.str);
    try t.expectEqualStrings("cat", f.pdv.get("q").?.str);

    // CALL SCAN("the quick fox", 2, pos, len): word 2 = "quick" at 1-based pos 5, len 5
    _ = try f.pdv.define("pos", .num);
    _ = try f.pdv.define("len", .num);
    const scanargs = [_]ast.Expr{ .{ .str = "the quick fox" }, .{ .num = 2 }, .{ .variable = "pos" }, .{ .variable = "len" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "scan", .args = &scanargs } });
    try t.expectEqual(@as(f64, 5), f.pdv.get("pos").?.num);
    try t.expectEqual(@as(f64, 5), f.pdv.get("len").?.num);

    // CALL CATS(msg, "a", " b "): appends stripped items → "x=" + "a" + "b"
    _ = try f.pdv.define("msg", .char);
    try f.pdv.set("msg", .{ .str = "x=" });
    const catsargs = [_]ast.Expr{ .{ .variable = "msg" }, .{ .str = "a" }, .{ .str = " b " } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "cats", .args = &catsargs } });
    try t.expectEqualStrings("x=ab", f.pdv.get("msg").?.str);

    // CALL CATT(m2, "a ", "b"): trailing-trim each item → "ab"
    _ = try f.pdv.define("m2", .char);
    try f.pdv.set("m2", .{ .str = "" });
    const cattargs = [_]ast.Expr{ .{ .variable = "m2" }, .{ .str = "a " }, .{ .str = "b" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "catt", .args = &cattargs } });
    try t.expectEqualStrings("ab", f.pdv.get("m2").?.str);

    // CALL CATX("-", r, "a", "b", " ", "c"): blank item skipped → "a-b-c"
    _ = try f.pdv.define("r", .char);
    try f.pdv.set("r", .{ .str = "" });
    const catxargs = [_]ast.Expr{ .{ .str = "-" }, .{ .variable = "r" }, .{ .str = "a" }, .{ .str = "b" }, .{ .str = " " }, .{ .str = "c" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "catx", .args = &catxargs } });
    try t.expectEqualStrings("a-b-c", f.pdv.get("r").?.str);
}

test "CALL STDIZE / RANPERM / RANPERK / RANCOMB / ALLPERM / LEXCOMB (combinatorial)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // CALL STDIZE(a,b,c): {2,4,6} → mean 4, std 2 → {-1, 0, 1}
    try f.pdv.set("a", .{ .num = 2 });
    try f.pdv.set("b", .{ .num = 4 });
    try f.pdv.set("c", .{ .num = 6 });
    const sd = [_]ast.Expr{ .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "stdize", .args = &sd } });
    try t.expectEqual(@as(f64, -1), f.pdv.get("a").?.num);
    try t.expectEqual(@as(f64, 0), f.pdv.get("b").?.num);
    try t.expectEqual(@as(f64, 1), f.pdv.get("c").?.num);

    // CALL RANPERM(seed, p,q,r): a permutation of {10,20,30} — sum preserved,
    // all values present, and deterministic for a fixed seed.
    try f.pdv.set("seed", .{ .num = 7 });
    try f.pdv.set("p", .{ .num = 10 });
    try f.pdv.set("q", .{ .num = 20 });
    try f.pdv.set("r", .{ .num = 30 });
    const rp = [_]ast.Expr{ .{ .variable = "seed" }, .{ .variable = "p" }, .{ .variable = "q" }, .{ .variable = "r" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "ranperm", .args = &rp } });
    const p1 = f.pdv.get("p").?.num;
    const q1 = f.pdv.get("q").?.num;
    const r1 = f.pdv.get("r").?.num;
    try t.expectEqual(@as(f64, 60), p1 + q1 + r1); // multiset preserved
    try t.expect(p1 != q1 and q1 != r1 and p1 != r1); // all three still present
    try t.expect(f.pdv.get("seed").?.num != 7); // seed advanced

    // CALL RANCOMB(seed,2, w,x2,y2,z): the first two are a sorted 2-subset of {1..4}
    try f.pdv.set("seed", .{ .num = 3 });
    try f.pdv.set("w", .{ .num = 1 });
    try f.pdv.set("x2", .{ .num = 2 });
    try f.pdv.set("y2", .{ .num = 3 });
    try f.pdv.set("z", .{ .num = 4 });
    const rc = [_]ast.Expr{ .{ .variable = "seed" }, .{ .num = 2 }, .{ .variable = "w" }, .{ .variable = "x2" }, .{ .variable = "y2" }, .{ .variable = "z" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "rancomb", .args = &rc } });
    const cw = f.pdv.get("w").?.num;
    const cx = f.pdv.get("x2").?.num;
    try t.expect(cw >= 1 and cw <= 4 and cx >= 1 and cx <= 4 and cw < cx); // sorted subset

    // CALL ALLPERM over {1,2,3}: the EXACT SAS minimal-change (SJT) sequence
    // 123, 132, 312, 321, 231, 213 — each differs by one adjacent swap.
    try f.pdv.set("d1", .{ .num = 1 });
    try f.pdv.set("d2", .{ .num = 2 });
    try f.pdv.set("d3", .{ .num = 3 });
    const want_perm = [_][3]f64{ .{ 1, 2, 3 }, .{ 1, 3, 2 }, .{ 3, 1, 2 }, .{ 3, 2, 1 }, .{ 2, 3, 1 }, .{ 2, 1, 3 } };
    for (want_perm, 1..) |wp, cnt| {
        const ap = [_]ast.Expr{ .{ .num = @floatFromInt(cnt) }, .{ .variable = "d1" }, .{ .variable = "d2" }, .{ .variable = "d3" } };
        _ = try x.runStmt(&.{ .call_ = .{ .name = "allperm", .args = &ap } });
        try t.expectEqual(wp[0], f.pdv.get("d1").?.num);
        try t.expectEqual(wp[1], f.pdv.get("d2").?.num);
        try t.expectEqual(wp[2], f.pdv.get("d3").?.num);
    }

    // CALL ALLCOMB over {10,20,30,40} k=2: the EXACT revolving-door sequence
    // {10,20},{20,30},{10,30},{30,40},{20,40},{10,40} — one element changes each step.
    const want_comb = [_][2]f64{ .{ 10, 20 }, .{ 20, 30 }, .{ 10, 30 }, .{ 30, 40 }, .{ 20, 40 }, .{ 10, 40 } };
    for (want_comb, 1..) |wc, cnt| {
        try f.pdv.set("v1", .{ .num = 10 });
        try f.pdv.set("v2", .{ .num = 20 });
        try f.pdv.set("v3", .{ .num = 30 });
        try f.pdv.set("v4", .{ .num = 40 });
        const ac = [_]ast.Expr{ .{ .num = @floatFromInt(cnt) }, .{ .num = 2 }, .{ .variable = "v1" }, .{ .variable = "v2" }, .{ .variable = "v3" }, .{ .variable = "v4" } };
        _ = try x.runStmt(&.{ .call_ = .{ .name = "allcomb", .args = &ac } });
        const lo = @min(f.pdv.get("v1").?.num, f.pdv.get("v2").?.num);
        const hi = @max(f.pdv.get("v1").?.num, f.pdv.get("v2").?.num);
        try t.expectEqual(wc[0], lo);
        try t.expectEqual(wc[1], hi);
    }

    // CALL LEXCOMB over {10,20,30,40} k=2: lexicographic order (unchanged behavior)
    const want_lex = [_][2]f64{ .{ 10, 20 }, .{ 10, 30 }, .{ 10, 40 }, .{ 20, 30 }, .{ 20, 40 }, .{ 30, 40 } };
    for (want_lex, 1..) |wl, cnt| {
        try f.pdv.set("v1", .{ .num = 10 });
        try f.pdv.set("v2", .{ .num = 20 });
        try f.pdv.set("v3", .{ .num = 30 });
        try f.pdv.set("v4", .{ .num = 40 });
        const lc = [_]ast.Expr{ .{ .num = @floatFromInt(cnt) }, .{ .num = 2 }, .{ .variable = "v1" }, .{ .variable = "v2" }, .{ .variable = "v3" }, .{ .variable = "v4" } };
        _ = try x.runStmt(&.{ .call_ = .{ .name = "lexcomb", .args = &lc } });
        try t.expectEqual(wl[0], @min(f.pdv.get("v1").?.num, f.pdv.get("v2").?.num));
        try t.expectEqual(wl[1], @max(f.pdv.get("v1").?.num, f.pdv.get("v2").?.num));
    }
}

test "BUG-callscanstale: CALL SCAN routes through the SCAN machinery — modifiers + default delims agree with SCAN()" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    _ = try f.pdv.define("pos", .num);
    _ = try f.pdv.define("len", .num);

    // (a) 6th `m` modifier honored: 'a,,b,c' split on ',' with m keeps the empty
    // 2nd word → pos=3, len=0 (SCAN('a,,b,c',2,',','m') is also empty).
    const am = [_]ast.Expr{ .{ .str = "a,,b,c" }, .{ .num = 2 }, .{ .variable = "pos" }, .{ .variable = "len" }, .{ .str = "," }, .{ .str = "m" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "scan", .args = &am } });
    try t.expectEqual(@as(f64, 3), f.pdv.get("pos").?.num);
    try t.expectEqual(@as(f64, 0), f.pdv.get("len").?.num);

    // (b) default delim set matches SCAN()'s: '>' is NOT a delimiter, so 'aa>bb>cc'
    // is a single word → word 2 is out of range → 0/0 (old code split on '>').
    const gt = [_]ast.Expr{ .{ .str = "aa>bb>cc" }, .{ .num = 2 }, .{ .variable = "pos" }, .{ .variable = "len" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "scan", .args = &gt } });
    try t.expectEqual(@as(f64, 0), f.pdv.get("pos").?.num);
    try t.expectEqual(@as(f64, 0), f.pdv.get("len").?.num);

    // plain CALL SCAN unchanged: 'a b c' word 2 = "b" at pos 3, len 1.
    const pl = [_]ast.Expr{ .{ .str = "a b c" }, .{ .num = 2 }, .{ .variable = "pos" }, .{ .variable = "len" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "scan", .args = &pl } });
    try t.expectEqual(@as(f64, 3), f.pdv.get("pos").?.num);
    try t.expectEqual(@as(f64, 1), f.pdv.get("len").?.num);

    // unsupported modifier (q) fails LOUD via wordSpec (D-002), not silent.
    const qm = [_]ast.Expr{ .{ .str = "a b c" }, .{ .num = 1 }, .{ .variable = "pos" }, .{ .variable = "len" }, .{ .str = " " }, .{ .str = "q" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "scan", .args = &qm } });
    try t.expect(f.diags.hasErrors());
}

test "BUG-callstdizemethod: CALL STDIZE honors METHOD=RANGE and fails LOUD on any unimplemented method" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // METHOD=RANGE over {2,4,6}: (x-min)/(max-min) → {0, 0.5, 1}
    try f.pdv.set("a", .{ .num = 2 });
    try f.pdv.set("b", .{ .num = 4 });
    try f.pdv.set("c", .{ .num = 6 });
    const rg = [_]ast.Expr{ .{ .str = "method=range" }, .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "stdize", .args = &rg } });
    try t.expectEqual(@as(f64, 0), f.pdv.get("a").?.num);
    try t.expectEqual(@as(f64, 0.5), f.pdv.get("b").?.num);
    try t.expectEqual(@as(f64, 1), f.pdv.get("c").?.num);
    try t.expect(!f.diags.hasErrors());

    // an unimplemented METHOD= fails LOUD (captured ERROR), never silently STD.
    const mn = [_]ast.Expr{ .{ .str = "method=mean" }, .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    try t.expectError(error.ExecError, x.runStmt(&.{ .call_ = .{ .name = "stdize", .args = &mn } }));
    try t.expect(f.diags.hasErrors());
}

test "BUG-callstdizeoptmsg: a rejected VARDEF/miscellaneous option is named as an OPTION, not as METHOD=" {
    // Every rejected option used to be reported as `METHOD={s}`, so `mult=2`
    // rendered as the nonsense `CALL STDIZE METHOD=mult=2`. Functions ref
    // printed p.419-421 puts DF/N under VARDEF-options ("the divisor to be used
    // in the calculation of variances") and MULT=/FUZZ=/NORM/… under
    // miscellaneous-options; neither group is a standardization-option, and the
    // Details section reserves the word "methods" for that third group.
    // Message-only: the rc of each case is unchanged and is asserted here too.
    const Case = struct { opt: []const u8, want: []const u8, rc: u8 };
    for ([_]Case{
        .{ .opt = "mult=2", .want = "CALL STDIZE option mult=2 is not supported yet", .rc = 2 },
        .{ .opt = "df", .want = "CALL STDIZE option df is not supported yet", .rc = 2 },
        .{ .opt = "pstat", .want = "CALL STDIZE option pstat is not supported yet", .rc = 2 },
        // a standardization-option IS a method — this half must NOT move, or the
        // fix would have traded one wrong label for another.
        .{ .opt = "median", .want = "CALL STDIZE METHOD=median is not supported yet", .rc = 2 },
        .{ .opt = "method=euclen", .want = "CALL STDIZE METHOD=euclen is not supported yet", .rc = 2 },
        // an unrecognised token stays a mistyped METHOD and stays the user's error.
        .{ .opt = "medain", .want = "CALL STDIZE METHOD=medain is not supported yet", .rc = 1 },
    }) |c| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.Expr{ .{ .str = c.opt }, .{ .variable = "v" } };
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "v", .value = f.num(1) } },
            .{ .call_ = .{ .name = "stdize", .args = &args } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(c.rc, rcOf(&f));
        var found = false;
        for (f.diags.list.items) |d|
            if (d.severity == .err and std.mem.eql(u8, d.message, c.want)) {
                found = true;
            };
        try t.expect(found);
    }
}

test "BUG-callstdizerange: CALL STDIZE accepts a bare method name (range/std); unknown fails LOUD" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // bare 'range' over {2,4,6} behaves exactly like 'method=range' → {0, 0.5, 1}
    try f.pdv.set("a", .{ .num = 2 });
    try f.pdv.set("b", .{ .num = 4 });
    try f.pdv.set("c", .{ .num = 6 });
    const rg = [_]ast.Expr{ .{ .str = "range" }, .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "stdize", .args = &rg } });
    try t.expectEqual(@as(f64, 0), f.pdv.get("a").?.num);
    try t.expectEqual(@as(f64, 0.5), f.pdv.get("b").?.num);
    try t.expectEqual(@as(f64, 1), f.pdv.get("c").?.num);
    try t.expect(!f.diags.hasErrors());

    // bare 'std' over {2,4,6}: mean 4, std 2 → {-1, 0, 1} (same as no option)
    try f.pdv.set("a", .{ .num = 2 });
    try f.pdv.set("b", .{ .num = 4 });
    try f.pdv.set("c", .{ .num = 6 });
    const sd = [_]ast.Expr{ .{ .str = "std" }, .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "stdize", .args = &sd } });
    try t.expectEqual(@as(f64, -1), f.pdv.get("a").?.num);
    try t.expectEqual(@as(f64, 0), f.pdv.get("b").?.num);
    try t.expectEqual(@as(f64, 1), f.pdv.get("c").?.num);
    try t.expect(!f.diags.hasErrors());

    // a bare UNrecognized method name fails LOUD, never silently STD.
    const bg = [_]ast.Expr{ .{ .str = "bogus" }, .{ .variable = "a" }, .{ .variable = "b" }, .{ .variable = "c" } };
    try t.expectError(error.ExecError, x.runStmt(&.{ .call_ = .{ .name = "stdize", .args = &bg } }));
    try t.expect(f.diags.hasErrors());
}

test "CALL LABEL(dsid, n, out) writes the variable's label via the SCL registry" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const a = f.a();

    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("height", .num);
    try ds.appendRow(&.{.{ .num = 5 }});
    try f.lib.put("t", ds);
    dsfns.bind(&f.lib);
    const id = dsfns.open("work.t");
    try t.expect(id >= 1);

    _ = try f.pdv.define("lbl", .char);
    const args = [_]ast.Expr{ .{ .num = id }, .{ .num = 1 }, .{ .variable = "lbl" } };
    _ = try x.runStmt(&.{ .call_ = .{ .name = "label", .args = &args } });
    // no stored labels → the label falls back to the variable name (as SAS does)
    try t.expectEqualStrings("height", f.pdv.get("lbl").?.str);
}

test "BUG-calllabel2arg: DATA-step CALL LABEL(var, out) writes the label; unlabeled → the variable NAME (SAS p.322)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // label wt='Body Weight'; wt=70; ht=180; call label(wt, lb); call label(ht, lb2);
    const lbl_items = [_]ast.FormatItem{.{ .name = "wt", .fmt = "\x00Body Weight" }}; // parser's LABEL sentinel
    const a2 = [_]ast.Expr{ .{ .variable = "wt" }, .{ .variable = "lb" } };
    const a3 = [_]ast.Expr{ .{ .variable = "ht" }, .{ .variable = "lb2" } };
    const prog = [_]ast.Stmt{
        .{ .format = &lbl_items },
        .{ .assign = .{ .target = "wt", .value = f.num(70) } },
        .{ .assign = .{ .target = "ht", .value = f.num(180) } },
        .{ .call_ = .{ .name = "label", .args = &a2 } },
        .{ .call_ = .{ .name = "label", .args = &a3 } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);
    const r = out.row(0); // the PDV is reset after the final pass — assert the row
    try t.expectEqualStrings("Body Weight", r[out.indexOf("lb").?].str); // was: silent blank, no diagnostic
    try t.expectEqualStrings("ht", r[out.indexOf("lb2").?].str); // no label → variable name
}

test "GAP-calloutarg-note: pure-output CALL args (SCAN pos/len, PRXPOSN position/length, LABEL out) get NO uninitialized NOTE" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // pos/len/p/l/lb appear ONLY as CALL output args; ghost is a genuine read.
    // `w=pos+len` reads pos/len AFTER the call (the tick137 repro reads them in
    // substr — the fixture's evaluator wires no call_fn, so a binary read stands
    // in) — SAS's whole-step compile still emits no NOTE for them.
    const scan_args = [_]ast.Expr{ .{ .variable = "s" }, .{ .num = 2 }, .{ .variable = "pos" }, .{ .variable = "len" }, .{ .str = "," } };
    const posn_args = [_]ast.Expr{ .{ .variable = "rx" }, .{ .num = 1 }, .{ .variable = "p" }, .{ .variable = "l" } };
    const lbl_args = [_]ast.Expr{ .{ .variable = "s" }, .{ .variable = "lb" } };
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "s", .value = f.e(.{ .str = "a,b,c" }) } },
        .{ .assign = .{ .target = "rx", .value = f.num(1) } }, // uncompiled id → prxposn no-ops; the scan is static
        .{ .call_ = .{ .name = "scan", .args = &scan_args } },
        .{ .call_ = .{ .name = "prxposn", .args = &posn_args } },
        .{ .call_ = .{ .name = "label", .args = &lbl_args } },
        .{ .assign = .{ .target = "w", .value = f.bin(.add, f.vbl("pos"), f.vbl("len")) } },
        .{ .assign = .{ .target = "z", .value = f.bin(.add, f.vbl("ghost"), f.num(1)) } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);
    try t.expect(!diagsNote(&f.diags, "Variable pos is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable len is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable p is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable l is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable lb is uninitialized."));
    try t.expect(diagsNote(&f.diags, "Variable ghost is uninitialized.")); // control: real reads still note
    // values are unaffected (the GAP was log-noise only)
    const r = out.row(0); // the PDV is reset after the final pass — assert the row
    try t.expectEqual(@as(f64, 3), r[out.indexOf("pos").?].num);
    try t.expectEqual(@as(f64, 1), r[out.indexOf("len").?].num);
    try t.expectEqual(@as(f64, 4), r[out.indexOf("w").?].num);
}

test "BUG-calloutuninit: CALL CATS/CATX/CATT/VNAME/RAN* output args get NO uninitialized NOTE; real reads still note" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // c1/rx/nm/u appear ONLY as CALL output args; ghost is a genuine read.
    const cats_args = [_]ast.Expr{ .{ .variable = "c1" }, .{ .str = "a" }, .{ .str = "b" } };
    const catx_args = [_]ast.Expr{ .{ .str = "-" }, .{ .variable = "cx" }, .{ .str = "x" }, .{ .str = "y" } };
    const vname_args = [_]ast.Expr{ .{ .variable = "seed" }, .{ .variable = "nm" } };
    const ran_args = [_]ast.Expr{ .{ .variable = "seed" }, .{ .variable = "u" } };
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "seed", .value = f.num(42) } },
        .{ .call_ = .{ .name = "cats", .args = &cats_args } },
        .{ .call_ = .{ .name = "catx", .args = &catx_args } },
        .{ .call_ = .{ .name = "vname", .args = &vname_args } },
        .{ .call_ = .{ .name = "ranuni", .args = &ran_args } },
        .{ .assign = .{ .target = "z", .value = f.bin(.add, f.vbl("ghost"), f.num(1)) } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);
    try t.expect(!diagsNote(&f.diags, "Variable c1 is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable cx is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable nm is uninitialized."));
    try t.expect(!diagsNote(&f.diags, "Variable u is uninitialized."));
    try t.expect(diagsNote(&f.diags, "Variable ghost is uninitialized.")); // control: real reads still note
    // values are unaffected (the BUG was log-noise only)
    const r = out.row(0);
    try t.expectEqualStrings("ab", r[out.indexOf("c1").?].str);
    try t.expectEqualStrings("x-y", r[out.indexOf("cx").?].str);
    try t.expectEqualStrings("seed", r[out.indexOf("nm").?].str);
}

test "BUG-informatstmtdate: INFORMAT statement applies a date informat to list INPUT" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const infs = [_]ast.FormatItem{.{ .name = "a", .fmt = "date9." }};
    const items = [_]ast.InputItem{.{ .name = "a", .type = .num }};
    const lines = [_][]const u8{"15JAN2020"};
    const prog = [_]ast.Stmt{
        .{ .informat = &infs },
        .{ .input = &items },
        .{ .datalines = &lines },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    try t.expectEqual(@as(usize, 1), out.rowCount());
    // 15JAN2020 → SAS day 21929, read via the statement informat (not a :modifier)
    try t.expectEqual(@as(f64, 21929), out.row(0)[out.indexOf("a").?].num);
}

test "datalines + input + assignment, implicit output" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{
        .{ .name = "name", .type = .char },
        .{ .name = "x", .type = .num },
    };
    const lines = [_][]const u8{ "a 1", "b 2" };
    const prog = [_]ast.Stmt{
        .{ .input = &items },
        .{ .datalines = &lines },
        // y = x * 2;
        .{ .assign = .{ .target = "y", .value = f.bin(.mul, f.vbl("x"), f.num(2)) } },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    try t.expectEqual(@as(usize, 2), out.rowCount());
    const ni = out.indexOf("name").?;
    const yi = out.indexOf("y").?;
    try t.expectEqualStrings("a", out.row(0)[ni].str);
    try t.expectEqual(@as(f64, 2), out.row(0)[yi].num);
    try t.expectEqualStrings("b", out.row(1)[ni].str);
    try t.expectEqual(@as(f64, 4), out.row(1)[yi].num);
}

test "BUG-infilemissover: MISSOVER sets short-record vars missing, not flowing to the next line" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{
        .{ .name = "a", .type = .num },
        .{ .name = "b", .type = .num },
        .{ .name = "c", .type = .num },
    };
    const lines = [_][]const u8{ "1 2 3", "4 5", "6" };
    const inf: ast.Infile = .{ .path = "datalines", .inline_data = true, .overflow = .missover };
    const prog = [_]ast.Stmt{ .{ .infile = inf }, .{ .input = &items }, .{ .datalines = &lines } };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const ai = out.indexOf("a").?;
    const bi = out.indexOf("b").?;
    const ci = out.indexOf("c").?;
    // 3 rows (FLOWOVER would merge the short records into 2); short cells missing.
    try t.expectEqual(@as(usize, 3), out.rowCount());
    try t.expectEqual(@as(f64, 4), out.row(1)[ai].num);
    try t.expectEqual(@as(f64, 5), out.row(1)[bi].num);
    try t.expect(out.row(1)[ci].isMissing());
    try t.expectEqual(@as(f64, 6), out.row(2)[ai].num);
    try t.expect(out.row(2)[bi].isMissing());
    try t.expect(out.row(2)[ci].isMissing());
}

test "REVERT-infileendmultirec: INFILE END= over DATALINES never reaches 1 (0,0,0) and stays out of the output" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    const lines = [_][]const u8{ "10", "20", "30" };
    const inf: ast.Infile = .{ .path = "datalines", .inline_data = true, .end_var = "eof" };
    const prog = [_]ast.Stmt{
        .{ .infile = inf },
        .{ .input = &items },
        .{ .assign = .{ .target = "flag", .value = f.vbl("eof") } },
        .{ .datalines = &lines },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    try t.expectEqual(@as(usize, 3), out.rowCount());
    const fi = out.indexOf("flag").?;
    // REVERT-infileendmultirec: this test asked for (0,0,1) and so PINNED the
    // restricted case — the source is `inline_data = true`, i.e. DATALINES, and
    // Statements ref printed p.138 makes UNBUFFERED unconditionally in effect
    // for instream data, where "SAS never sets the END= variable to 1". The
    // flag stays at its documented 0 (p.130) for every record, including the
    // last. Not a diagnostic: p.332 glosses the same "Restriction" wording for
    // SET/POINT= as "the END= variable is never set to 1".
    try t.expectEqual(@as(f64, 0), out.row(0)[fi].num);
    try t.expectEqual(@as(f64, 0), out.row(1)[fi].num);
    try t.expectEqual(@as(f64, 0), out.row(2)[fi].num);
    // The OTHER half of this test's subject — that END= really does reach 1 on
    // the last record where it is LEGAL — cannot be exercised here: the unit
    // fixture is io-free, so DATALINES is the only source it can open, and
    // DATALINES is exactly the restricted case. It is pinned instead by
    // tests/corpus/infile_end.sas block 2, an EXTERNAL file with a single
    // INPUT (`seen` = 0,0,1), which this change deliberately leaves unmoved.
    // temporary, like _N_/SET end= — never an output column.
    try t.expect(out.indexOf("eof") == null);
    // …and still 0 rather than MISSING: a restricted END= is defined, not unset,
    // so no "uninitialized" NOTE may appear.
    try t.expect(!diagsHave(&f.diags, "uninitialized"));
}

test "FEAT-infileobslinesize: OBS= caps the records read; LINESIZE= truncates each record" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    const lines = [_][]const u8{ "10", "20", "30" };
    const inf: ast.Infile = .{ .path = "datalines", .inline_data = true, .obs = 2 };
    const prog = [_]ast.Stmt{
        .{ .infile = inf },
        .{ .input = &items },
        .{ .datalines = &lines },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);
    try t.expectEqual(@as(usize, 2), out.rowCount()); // record 3 never read
    const xi = out.indexOf("x").?;
    try t.expectEqual(@as(f64, 10), out.row(0)[xi].num);
    try t.expectEqual(@as(f64, 20), out.row(1)[xi].num);

    // LINESIZE=3 truncates a longer record: columns past 3 are not available to INPUT.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var x2 = f2.exec();
    const citems = [_]ast.InputItem{.{ .name = "s", .type = .char }};
    const clines = [_][]const u8{"abcdef"};
    const cinf: ast.Infile = .{ .path = "datalines", .inline_data = true, .linesize = 3 };
    const cprog = [_]ast.Stmt{
        .{ .infile = cinf },
        .{ .input = &citems },
        .{ .datalines = &clines },
    };
    var out2 = Dataset.init(f2.a(), "work.out");
    try x2.run(&cprog, &out2);
    try t.expectEqual(@as(usize, 1), out2.rowCount());
    try t.expectEqualStrings("abc", out2.row(0)[out2.indexOf("s").?].str);
}

test "BUG-multiinfilelastwins: two INFILEs keep independent cursors; EOF on the first stops the step (Language Reference: Concepts Table 20.4 row 5)" {
    // fa has 3 records, fb has 5. `infile fa; input a; infile fb; input b;`
    // reads ONE record from EACH per iteration and stops when fa is exhausted
    // → 3 obs (a1 1 b1 10 … a3 3 b3 30). The last-wins bug never opened fa:
    // 2 obs, all of it fb's data. END= on EACH infile tracks its own source,
    // and a REFERENCED earlier END= var draws no "never been referenced"
    // WARNING and no uninitialized NOTE (tick312 §8b(iii)).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const io_ = std.Io.Threaded.global_single_threaded.io();
    const fa = "/tmp/opensas_multiinfile_fa.txt";
    const fb = "/tmp/opensas_multiinfile_fb.txt";
    try Io.Dir.cwd().writeFile(io_, .{ .sub_path = fa, .data = "a1 1\na2 2\na3 3\n" });
    defer Io.Dir.cwd().deleteFile(io_, fa) catch {};
    try Io.Dir.cwd().writeFile(io_, .{ .sub_path = fb, .data = "b1 10\nb2 20\nb3 30\nb4 40\nb5 50\n" });
    defer Io.Dir.cwd().deleteFile(io_, fb) catch {};
    x.io = io_;

    const items_a = [_]ast.InputItem{ .{ .name = "aname", .type = .char }, .{ .name = "ax", .type = .num } };
    const items_b = [_]ast.InputItem{ .{ .name = "bname", .type = .char }, .{ .name = "bx", .type = .num } };
    const prog = [_]ast.Stmt{
        .{ .infile = .{ .path = fa, .end_var = "e1" } },
        .{ .input = &items_a },
        .{ .infile = .{ .path = fb, .end_var = "e2" } },
        .{ .input = &items_b },
        // reference both END= vars (they are auto-dropped temporaries)
        .{ .assign = .{ .target = "f1", .value = f.vbl("e1") } },
        .{ .assign = .{ .target = "f2", .value = f.vbl("e2") } },
    };
    var out = Dataset.init(f.a(), "work.both");
    try x.run(&prog, &out);

    try t.expectEqual(@as(usize, 3), out.rowCount()); // EOF on fa (3 < 5) stops the step
    const ani = out.indexOf("aname").?;
    const axi = out.indexOf("ax").?;
    const bni = out.indexOf("bname").?;
    const bxi = out.indexOf("bx").?;
    const f1i = out.indexOf("f1").?;
    const f2i = out.indexOf("f2").?;
    for ([_][]const u8{ "a1", "a2", "a3" }, [_]f64{ 1, 2, 3 }, [_][]const u8{ "b1", "b2", "b3" }, [_]f64{ 10, 20, 30 }, 0..) |an, axv, bn, bxv, k| {
        try t.expectEqualStrings(an, out.row(k)[ani].str);
        try t.expectEqual(axv, out.row(k)[axi].num);
        try t.expectEqualStrings(bn, out.row(k)[bni].str);
        try t.expectEqual(bxv, out.row(k)[bxi].num);
    }
    try t.expectEqual(@as(f64, 1), out.row(2)[f1i].num); // e1: last record of fa
    try t.expectEqual(@as(f64, 0), out.row(2)[f2i].num); // e2: fb not exhausted
    try t.expect(out.indexOf("e1") == null and out.indexOf("e2") == null); // temporaries
    try t.expect(!diagsWarn(&f.diags, "never been referenced"));
    try t.expect(!diagsHave(&f.diags, "uninitialized"));
}

test "BUG-multiinfilelastwins: two `infile datalines` share ONE instream cursor — no rewind (Language Reference: Concepts Table 21.5 row 10)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const ia = [_]ast.InputItem{.{ .name = "a", .type = .num }};
    const ib = [_]ast.InputItem{.{ .name = "b", .type = .num }};
    const lines = [_][]const u8{ "1", "2", "3", "4" };
    const prog = [_]ast.Stmt{
        .{ .infile = .{ .path = "datalines", .inline_data = true } },
        .{ .input = &ia },
        .{ .infile = .{ .path = "datalines", .inline_data = true } },
        .{ .input = &ib },
        .{ .datalines = &lines },
    };
    var out = Dataset.init(f.a(), "work.s");
    try x.run(&prog, &out);
    try t.expectEqual(@as(usize, 2), out.rowCount());
    const ai = out.indexOf("a").?;
    const bi = out.indexOf("b").?;
    try t.expectEqual(@as(f64, 1), out.row(0)[ai].num);
    try t.expectEqual(@as(f64, 2), out.row(0)[bi].num); // shared cursor: b reads record 2, not a rewound record 1
    try t.expectEqual(@as(f64, 3), out.row(1)[ai].num);
    try t.expectEqual(@as(f64, 4), out.row(1)[bi].num);
}

test "BUG-setinputinert: SET + INPUT reads the line source alongside the driver; no source stays LOUD" {
    // Language Reference: Concepts p.477 step 3 names INPUT a peer of SET/MERGE/UPDATE/MODIFY;
    // Table 20.4's last row stops the step at the first EOF of ANY
    // data-reading statement. `set a; input z; datalines;` used to make the
    // INPUT a total silent no-op — z missing on every row, exit 0.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const a = f.newDs("a");
    _ = try a.addColumn("i", .num);
    for ([_]f64{ 1, 2, 3 }) |v| try a.appendRow(&.{.{ .num = v }});
    try f.lib.put("a", a);
    const na = [_][]const u8{"a"};
    const iz = [_]ast.InputItem{.{ .name = "z", .type = .num }};
    const lines = [_][]const u8{ "7", "8", "9" };
    const prog = [_]ast.Stmt{ .{ .set = &na }, .{ .input = &iz }, .{ .datalines = &lines } };
    var out = Dataset.init(f.a(), "work.mix");
    try x.run(&prog, &out);
    try t.expectEqual(@as(usize, 3), out.rowCount());
    const zi = out.indexOf("z").?;
    for ([_]f64{ 7, 8, 9 }, 0..) |zv, k| try t.expectEqual(zv, out.row(k)[zi].num);

    // EOF on the INPUT (2 records) before EOF on the SET (3 obs) stops the
    // step: 2 obs, the partial third iteration not output.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var x2 = f2.exec();
    const a2 = f2.newDs("a");
    _ = try a2.addColumn("i", .num);
    for ([_]f64{ 1, 2, 3 }) |v| try a2.appendRow(&.{.{ .num = v }});
    try f2.lib.put("a", a2);
    const lines2 = [_][]const u8{ "7", "8" };
    const prog2 = [_]ast.Stmt{ .{ .set = &na }, .{ .input = &iz }, .{ .datalines = &lines2 } };
    var out2 = Dataset.init(f2.a(), "work.mix2");
    try x2.run(&prog2, &out2);
    try t.expectEqual(@as(usize, 2), out2.rowCount());

    // the sibling stays LOUD (BUG-inputnosourcefabricates): a SET driver does
    // not give INPUT a source — `set a; input x;` with no datalines/INFILE
    // errors instead of fabricating all-missing columns.
    var f3 = fixture();
    defer f3.deinit();
    f3.prime();
    var x3 = f3.exec();
    const a3 = f3.newDs("a");
    _ = try a3.addColumn("i", .num);
    try a3.appendRow(&.{.{ .num = 1 }});
    try f3.lib.put("a", a3);
    const prog3 = [_]ast.Stmt{ .{ .set = &na }, .{ .input = &iz } };
    var out3 = Dataset.init(f3.a(), "work.d");
    try t.expectError(error.ExecError, x3.run(&prog3, &out3));
    try t.expect(diagsHave(&f3.diags, "No DATALINES or INFILE statement.")); // captured diagnostic (D-003)
}

test "io-free external INFILE keeps the inert-.once shape (no phantom 0-iteration .lines step)" {
    // interpret's null io (unit tests, the pure-in-memory path) cannot OPEN
    // an external INFILE: the source registers but reads nothing. That
    // phantom empty source must NOT drive the .lines gate — the step keeps
    // the pre-multiinfile inert-.once shape: one iteration, INPUT inert,
    // the body runs, no diagnostics (main.zig's mid-PROC-fileref interpret
    // test reads through a hoisted FILENAME on exactly this path).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec(); // io stays null — the io-free path
    const inf: ast.Infile = .{ .path = "not-read-in-the-io-free-path.dat" };
    const iw = [_]ast.InputItem{.{ .name = "w", .type = .char }};
    const prog = [_]ast.Stmt{
        .{ .infile = inf },
        .{ .input = &iw },
        .{ .assign = .{ .target = "y", .value = f.num(1) } },
    };
    var out = Dataset.init(f.a(), "work.d");
    try x.run(&prog, &out);
    try t.expectEqual(@as(usize, 1), out.rowCount()); // .once: the phantom source did not zero the step
    try t.expect(!f.diags.hasErrors()); // declared-but-unreadable is NOT "No DATALINES or INFILE"
}

test "BUG-infilemissover: STOPOVER makes a short record a hard error (fail loud)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{
        .{ .name = "a", .type = .num },
        .{ .name = "b", .type = .num },
        .{ .name = "c", .type = .num },
    };
    const lines = [_][]const u8{ "1 2 3", "4 5" }; // 2nd record short → STOPOVER errors
    const inf: ast.Infile = .{ .path = "datalines", .inline_data = true, .overflow = .stopover };
    const prog = [_]ast.Stmt{ .{ .infile = inf }, .{ .input = &items }, .{ .datalines = &lines } };
    var out = Dataset.init(f.a(), "work.out");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "STOPOVER"));
}

test "subsetting if deletes observations" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    const lines = [_][]const u8{ "1", "2", "3" };
    const prog = [_]ast.Stmt{
        .{ .input = &items },
        .{ .datalines = &lines },
        // subsetting `if x > 1;`
        .{ .if_ = .{ .cond = f.bin(.gt, f.vbl("x"), f.num(1)), .then_branch = null, .else_branch = null } },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    try t.expectEqual(@as(usize, 2), out.rowCount()); // 1 dropped
    try t.expectEqual(@as(f64, 2), out.row(0)[0].num);
    try t.expectEqual(@as(f64, 3), out.row(1)[0].num);
}

test "retain accumulates across iterations, survives reset" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    const lines = [_][]const u8{ "1", "2", "3" };
    const ri = [_]ast.RetainItem{.{ .name = "total", .init = f.num(0) }};
    const prog = [_]ast.Stmt{
        .{ .input = &items },
        .{ .datalines = &lines },
        .{ .retain = &ri },
        // total = total + x;
        .{ .assign = .{ .target = "total", .value = f.bin(.add, f.vbl("total"), f.vbl("x")) } },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const ti = out.indexOf("total").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    try t.expectEqual(@as(f64, 1), out.row(0)[ti].num);
    try t.expectEqual(@as(f64, 3), out.row(1)[ti].num); // retained across reset
    try t.expectEqual(@as(f64, 6), out.row(2)[ti].num);
}

test "iterative DO with explicit output writes a row per pass" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const body = [_]ast.Stmt{
        // sq = i * i;
        .{ .assign = .{ .target = "sq", .value = f.bin(.mul, f.vbl("i"), f.vbl("i")) } },
        .{ .output = &.{} },
    };
    const prog = [_]ast.Stmt{
        .{ .do_ = .{
            .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(3), .by = null } },
            .body = &body,
        } },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out); // no input source → one pass of the outer loop

    const ii = out.indexOf("i").?;
    const si = out.indexOf("sq").?;
    try t.expectEqual(@as(usize, 3), out.rowCount()); // explicit output, 3 DO passes
    try t.expectEqual(@as(f64, 1), out.row(0)[ii].num);
    try t.expectEqual(@as(f64, 1), out.row(0)[si].num);
    try t.expectEqual(@as(f64, 3), out.row(2)[ii].num);
    try t.expectEqual(@as(f64, 9), out.row(2)[si].num);
}

test "output columns order by first appearance: SET before a retained/sum var (BUG-varorder)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a1 = f.newDs("a");
    _ = try a1.addColumn("id", .num);
    try a1.appendRow(&.{.{ .num = 1 }});
    try a1.appendRow(&.{.{ .num = 2 }});
    try f.lib.put("a", a1);

    // set a; retain cnt 0; cnt = cnt + 1;  — `cnt` has an init (like the `retain
    // cnt 0` the parser hoists from a `cnt + 1` sum statement), which used to land
    // in the PDV before the SET's `id`.
    const set_names = [_][]const u8{"a"};
    const ritems = [_]ast.RetainItem{.{ .name = "cnt", .init = f.num(0) }};
    const prog = [_]ast.Stmt{
        .{ .set = &set_names },
        .{ .retain = &ritems },
        .{ .assign = .{ .target = "cnt", .value = f.bin(.add, f.vbl("cnt"), f.num(1)) } },
    };

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    // SAS first-appearance order: `id` (named by SET) precedes `cnt`
    try t.expectEqual(@as(usize, 0), out.indexOf("id").?);
    try t.expectEqual(@as(usize, 1), out.indexOf("cnt").?);
    try t.expectEqual(@as(f64, 2), out.row(1)[out.indexOf("cnt").?].num); // cnt accumulated
}

test "SET reads a prior dataset" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // build work.grades: name(char), score(num)
    const grades = f.newDs("grades");
    _ = try grades.addColumn("name", .char);
    _ = try grades.addColumn("score", .num);
    try grades.appendRow(&.{ .{ .str = "a" }, .{ .num = 80 } });
    try grades.appendRow(&.{ .{ .str = "b" }, .{ .num = 50 } });
    try f.lib.put("grades", grades);

    const names = [_][]const u8{"grades"};
    const prog = [_]ast.Stmt{
        .{ .set = &names },
        // pass = score >= 60;
        .{ .assign = .{ .target = "pass", .value = f.bin(.ge, f.vbl("score"), f.num(60)) } },
    };

    var out = Dataset.init(f.a(), "work.pass");
    try x.run(&prog, &out);

    const pi = out.indexOf("pass").?;
    try t.expectEqual(@as(usize, 2), out.rowCount());
    try t.expectEqual(@as(f64, 1), out.row(0)[pi].num); // 80 >= 60
    try t.expectEqual(@as(f64, 0), out.row(1)[pi].num); // 50 <  60
}

test "BY groups: first./last. flags over a sorted SET; automatics stay out of output" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // work.have, pre-sorted by dept: A(10), A(20), B(30)
    const have = f.newDs("have");
    _ = try have.addColumn("dept", .char);
    _ = try have.addColumn("sales", .num);
    try have.appendRow(&.{ .{ .str = "A" }, .{ .num = 10 } });
    try have.appendRow(&.{ .{ .str = "A" }, .{ .num = 20 } });
    try have.appendRow(&.{ .{ .str = "B" }, .{ .num = 30 } });
    try f.lib.put("have", have);

    const set_names = [_][]const u8{"have"};
    const by_names = [_][]const u8{"dept"};
    const prog = [_]ast.Stmt{
        .{ .set = &set_names },
        .{ .by = &by_names },
        // fa = first.dept; la = last.dept;  (the parser coalesces those names;
        // here we reference the automatics directly)
        .{ .assign = .{ .target = "fa", .value = f.vbl("first.dept") } },
        .{ .assign = .{ .target = "la", .value = f.vbl("last.dept") } },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const fi = out.indexOf("fa").?;
    const li = out.indexOf("la").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    try t.expectEqual(@as(f64, 1), out.row(0)[fi].num); // A(10): first of group
    try t.expectEqual(@as(f64, 0), out.row(0)[li].num);
    try t.expectEqual(@as(f64, 0), out.row(1)[fi].num); // A(20): last of group
    try t.expectEqual(@as(f64, 1), out.row(1)[li].num);
    try t.expectEqual(@as(f64, 1), out.row(2)[fi].num); // B(30): singleton — first and last
    try t.expectEqual(@as(f64, 1), out.row(2)[li].num);

    // the first./last. automatics are not columns in the output dataset
    try t.expect(out.indexOf("first.dept") == null);
    try t.expect(out.indexOf("last.dept") == null);
}

test "SET a b; BY x interleaves pre-sorted sources by key, with first./last. (BUG-setinterleave)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // a: x=1(a1),1(a2),2(a3)   b: x=1(b1),3(b3)  — both sorted by x
    const a1 = f.newDs("a");
    _ = try a1.addColumn("x", .num);
    _ = try a1.addColumn("v", .char);
    try a1.appendRow(&.{ .{ .num = 1 }, .{ .str = "a1" } });
    try a1.appendRow(&.{ .{ .num = 1 }, .{ .str = "a2" } });
    try a1.appendRow(&.{ .{ .num = 2 }, .{ .str = "a3" } });
    try f.lib.put("a", a1);
    const b1 = f.newDs("b");
    _ = try b1.addColumn("x", .num);
    _ = try b1.addColumn("v", .char);
    try b1.appendRow(&.{ .{ .num = 1 }, .{ .str = "b1" } });
    try b1.appendRow(&.{ .{ .num = 3 }, .{ .str = "b3" } });
    try f.lib.put("b", b1);

    const set_names = [_][]const u8{ "a", "b" };
    const by_names = [_][]const u8{"x"};
    const prog = [_]ast.Stmt{
        .{ .set = &set_names },
        .{ .by = &by_names },
        .{ .assign = .{ .target = "fa", .value = f.vbl("first.x") } },
        .{ .assign = .{ .target = "la", .value = f.vbl("last.x") } },
    };

    var out = Dataset.init(f.a(), "c");
    try x.run(&prog, &out);

    // interleaved by key: group x=1 reads a before b on ties (a1,a2,b1), then 2,3
    const vi = out.indexOf("v").?;
    const xi = out.indexOf("x").?;
    const fi = out.indexOf("fa").?;
    const li = out.indexOf("la").?;
    const want_v = [_][]const u8{ "a1", "a2", "b1", "a3", "b3" };
    const want_x = [_]f64{ 1, 1, 1, 2, 3 };
    const want_f = [_]f64{ 1, 0, 0, 1, 1 };
    const want_l = [_]f64{ 0, 0, 1, 1, 1 };
    try t.expectEqual(@as(usize, 5), out.rowCount());
    for (0..5) |i| {
        try t.expectEqualStrings(want_v[i], out.row(i)[vi].str);
        try t.expectEqual(want_x[i], out.row(i)[xi].num);
        try t.expectEqual(want_f[i], out.row(i)[fi].num);
        try t.expectEqual(want_l[i], out.row(i)[li].num);
    }
}

test "plain SET a b; (no BY) concatenates the sources end-to-end" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a1 = f.newDs("a");
    _ = try a1.addColumn("x", .num);
    for ([_]f64{ 1, 3, 5 }) |v| try a1.appendRow(&.{.{ .num = v }});
    try f.lib.put("a", a1);
    const b1 = f.newDs("b");
    _ = try b1.addColumn("x", .num);
    for ([_]f64{ 2, 4, 6 }) |v| try b1.appendRow(&.{.{ .num = v }});
    try f.lib.put("b", b1);

    const set_names = [_][]const u8{ "a", "b" };
    const prog = [_]ast.Stmt{.{ .set = &set_names }}; // no `by` → concatenate

    var out = Dataset.init(f.a(), "c");
    try x.run(&prog, &out);

    const xi = out.indexOf("x").?;
    try t.expectEqual(@as(usize, 6), out.rowCount());
    for ([_]f64{ 1, 3, 5, 2, 4, 6 }, 0..) |want, i| // a's rows then b's
        try t.expectEqual(want, out.row(i)[xi].num);
}

test "MERGE match-merge: combine columns on the BY key" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const one = f.newDs("one"); // id, name — sorted by id
    _ = try one.addColumn("id", .num);
    _ = try one.addColumn("name", .char);
    try one.appendRow(&.{ .{ .num = 1 }, .{ .str = "Alice" } });
    try one.appendRow(&.{ .{ .num = 2 }, .{ .str = "Bob" } });
    try one.appendRow(&.{ .{ .num = 3 }, .{ .str = "Carol" } });
    try f.lib.put("one", one);

    const two = f.newDs("two"); // id, age — sorted by id
    _ = try two.addColumn("id", .num);
    _ = try two.addColumn("age", .num);
    try two.appendRow(&.{ .{ .num = 1 }, .{ .num = 30 } });
    try two.appendRow(&.{ .{ .num = 2 }, .{ .num = 25 } });
    try two.appendRow(&.{ .{ .num = 3 }, .{ .num = 40 } });
    try f.lib.put("two", two);

    const merge_names = [_][]const u8{ "one", "two" };
    const by_names = [_][]const u8{"id"};
    const prog = [_]ast.Stmt{
        .{ .merge = &merge_names },
        .{ .by = &by_names },
    };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const ii = out.indexOf("id").?;
    const ni = out.indexOf("name").?;
    const ai = out.indexOf("age").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    try t.expectEqual(@as(f64, 1), out.row(0)[ii].num);
    try t.expectEqualStrings("Alice", out.row(0)[ni].str);
    try t.expectEqual(@as(f64, 30), out.row(0)[ai].num);
    try t.expectEqualStrings("Carol", out.row(2)[ni].str);
    try t.expectEqual(@as(f64, 40), out.row(2)[ai].num);
}

test "MERGE fills missing when a source lacks the BY key" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const one = f.newDs("one");
    _ = try one.addColumn("id", .num);
    _ = try one.addColumn("name", .char);
    try one.appendRow(&.{ .{ .num = 1 }, .{ .str = "Alice" } });
    try one.appendRow(&.{ .{ .num = 2 }, .{ .str = "Bob" } });
    try f.lib.put("one", one);

    const two = f.newDs("two"); // only id=1
    _ = try two.addColumn("id", .num);
    _ = try two.addColumn("age", .num);
    try two.appendRow(&.{ .{ .num = 1 }, .{ .num = 30 } });
    try f.lib.put("two", two);

    const merge_names = [_][]const u8{ "one", "two" };
    const by_names = [_][]const u8{"id"};
    const prog = [_]ast.Stmt{ .{ .merge = &merge_names }, .{ .by = &by_names } };

    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);

    const ai = out.indexOf("age").?;
    try t.expectEqual(@as(usize, 2), out.rowCount());
    try t.expectEqual(@as(f64, 30), out.row(0)[ai].num); // id=1 matched
    try t.expect(out.row(1)[ai].isMissing()); // id=2 absent in `two` → age missing
}

test "multi-output: `output name` routes to named datasets in the Library" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "v", .type = .num }};
    const lines = [_][]const u8{ "5", "15", "8" };
    const lo_names = [_][]const u8{"lo"};
    const hi_names = [_][]const u8{"hi"};
    const out_lo = try f.a().create(ast.Stmt);
    out_lo.* = .{ .output = &lo_names };
    const out_hi = try f.a().create(ast.Stmt);
    out_hi.* = .{ .output = &hi_names };
    const prog = [_]ast.Stmt{
        .{ .input = &items },
        .{ .datalines = &lines },
        // if v < 10 then output lo; else output hi;
        .{ .if_ = .{ .cond = f.bin(.lt, f.vbl("v"), f.num(10)), .then_branch = out_lo, .else_branch = out_hi } },
    };

    // `data lo hi; …` — SAS requires every `output <name>;` target to be one of
    // the DATA statement's datasets (BUG-outputundeclared killed the lazy create).
    var lo = Dataset.init(f.a(), "lo"); // primary dataset is `lo`
    const hi = f.newDs("hi");
    x.extra_outs = &.{hi};
    try x.run(&prog, &lo);

    // lo ← 5, 8 (primary matched by name); hi ← 15 (declared extra)
    try t.expectEqual(@as(usize, 2), lo.rowCount());
    try t.expectEqual(@as(f64, 5), lo.row(0)[lo.indexOf("v").?].num);
    try t.expectEqual(@as(f64, 8), lo.row(1)[lo.indexOf("v").?].num);
    try t.expectEqual(@as(usize, 1), hi.rowCount());
    try t.expectEqual(@as(f64, 15), hi.row(0)[hi.indexOf("v").?].num);
}

test "N-way MERGE keeps every column when a source misses the first BY group (BUG-mergecols)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a"); // id, x  — has id 1, 2
    _ = try a_ds.addColumn("id", .num);
    _ = try a_ds.addColumn("x", .num);
    try a_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try a_ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
    try f.lib.put("a", a_ds);

    const b_ds = f.newDs("b"); // id, y  — has id 2, 3 (absent from first group id=1)
    _ = try b_ds.addColumn("id", .num);
    _ = try b_ds.addColumn("y", .num);
    try b_ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 200 } });
    try b_ds.appendRow(&.{ .{ .num = 3 }, .{ .num = 300 } });
    try f.lib.put("b", b_ds);

    const c_ds = f.newDs("c"); // id, z  — has id 1, 3
    _ = try c_ds.addColumn("id", .num);
    _ = try c_ds.addColumn("z", .num);
    try c_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1000 } });
    try c_ds.appendRow(&.{ .{ .num = 3 }, .{ .num = 3000 } });
    try f.lib.put("c", c_ds);

    const merge_names = [_][]const u8{ "a", "b", "c" };
    const by_names = [_][]const u8{"id"};
    const prog = [_]ast.Stmt{ .{ .merge = &merge_names }, .{ .by = &by_names } };

    var out = Dataset.init(f.a(), "m");
    try x.run(&prog, &out);

    // every source's unique variable survives, though b is absent from group id=1
    const xi = out.indexOf("x").?;
    const yi = out.indexOf("y").?;
    const zi = out.indexOf("z").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    // id=1: x=10, y missing (b absent), z=1000
    try t.expectEqual(@as(f64, 10), out.row(0)[xi].num);
    try t.expect(out.row(0)[yi].isMissing());
    try t.expectEqual(@as(f64, 1000), out.row(0)[zi].num);
    // id=2: y=200 present (would be dropped by the bug)
    try t.expectEqual(@as(f64, 200), out.row(1)[yi].num);
    try t.expect(out.row(1)[zi].isMissing());
}

// Build `big` (k,v) with the given key sequence, `look` (k,r) = 1,2,3, MERGE them
// BY k, and return the output row count + whether an error was raised. Shared by
// the sorted/unsorted BUG-mergeunsorted cases.
fn mergeBigLook(f: *Fixture, x: *Executor, big_keys: []const f64) !struct { rows: usize, err: bool } {
    const big = f.newDs("big");
    _ = try big.addColumn("k", .num);
    _ = try big.addColumn("v", .char);
    for (big_keys) |k| try big.appendRow(&.{ .{ .num = k }, .{ .str = "v" } });
    try f.lib.put("big", big);

    const look = f.newDs("look");
    _ = try look.addColumn("k", .num);
    _ = try look.addColumn("r", .char);
    for ([_]f64{ 1, 2, 3 }) |k| try look.appendRow(&.{ .{ .num = k }, .{ .str = "r" } });
    try f.lib.put("look", look);

    const merge_names = [_][]const u8{ "big", "look" };
    const by_names = [_][]const u8{"k"};
    const prog = [_]ast.Stmt{ .{ .merge = &merge_names }, .{ .by = &by_names } };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    return .{ .rows = out.rowCount(), .err = f.diags.hasErrors() };
}

test "MERGE sorted repeated BY key keeps all 6 rows (BUG-mergeunsorted control)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    // big sorted: 1,1,2,2,3,3 — two rows per key merged against one look row each.
    const r = try mergeBigLook(&f, &x, &.{ 1, 1, 2, 2, 3, 3 });
    try t.expect(!r.err);
    try t.expectEqual(@as(usize, 6), r.rows);
}

test "MERGE unsorted input fails loud, no silent drop (BUG-mergeunsorted)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    // big unsorted: 1,2,3,1,2,3 — the second 1/2/3 go backwards. SAS errors
    // "BY variables are not properly sorted"; we must NOT silently truncate.
    const r = try mergeBigLook(&f, &x, &.{ 1, 2, 3, 1, 2, 3 });
    try t.expect(r.err); // captured diagnostic, no aborting process (D-003)
}

test "SET-BY interleave on unsorted input fails loud (BUG-setbyunsorted)" {
    var f = fixture();
    defer f.deinit();
    f.prime();

    // a: k=1,3 (sorted); b: k=2,1 (UNSORTED) — the emitted sequence 1,2 then
    // b's trailing 1 goes backwards. Was: silent wrong order + wrong first./last.
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try a_ds.appendRow(&.{.{ .num = 3 }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("k", .num);
    try b_ds.appendRow(&.{.{ .num = 2 }});
    try b_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("b", b_ds);

    const names = [_][]const u8{ "a", "b" };
    const by_names = [_][]const u8{"k"};
    { // unsorted → captured error (D-003), truncated before the backwards row
        var x = f.exec();
        const prog = [_]ast.Stmt{ .{ .set = &names }, .{ .by = &by_names } };
        var out = Dataset.init(f.a(), "out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasErrors());
    }
    f.diags = diag.Diagnostics.init(f.a());
    { // control: a sorted b and the same step interleaves all 4 rows cleanly
        const b2 = f.newDs("b");
        _ = try b2.addColumn("k", .num);
        try b2.appendRow(&.{.{ .num = 1 }});
        try b2.appendRow(&.{.{ .num = 2 }});
        try f.lib.put("b", b2);
        var x = f.exec();
        const prog = [_]ast.Stmt{ .{ .set = &names }, .{ .by = &by_names } };
        var out = Dataset.init(f.a(), "out2");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 4), out.rowCount());
    }
}

test "UPDATE BY populates first./last. (BUG-updatefirstlast)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // qa repro: update m t; by k; f=first.k; l=last.k; — one obs per group,
    // so both flags are 1 on every row (values 99/20 already verified correct).
    const master = f.newDs("m");
    _ = try master.addColumn("k", .num);
    _ = try master.addColumn("x", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try master.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
    try f.lib.put("m", master);
    const trans = f.newDs("t");
    _ = try trans.addColumn("k", .num);
    _ = try trans.addColumn("x", .num);
    try trans.appendRow(&.{ .{ .num = 1 }, .{ .num = 99 } });
    try f.lib.put("t", trans);

    const names = [_][]const u8{ "m", "t" };
    const by_names = [_][]const u8{"k"};
    const prog = [_]ast.Stmt{
        .{ .update = &names },
        .{ .by = &by_names },
        .{ .assign = .{ .target = "fst", .value = f.vbl("first.k") } },
        .{ .assign = .{ .target = "lst", .value = f.vbl("last.k") } },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), out.rowCount());
    for (0..2) |r| {
        try t.expectEqual(@as(f64, 1), out.row(r)[out.indexOf("fst").?].num);
        try t.expectEqual(@as(f64, 1), out.row(r)[out.indexOf("lst").?].num);
    }
    // and the update semantics themselves still hold: 99 applied, 20 untouched
    try t.expectEqual(@as(f64, 99), out.row(0)[out.indexOf("x").?].num);
    try t.expectEqual(@as(f64, 20), out.row(1)[out.indexOf("x").?].num);
}

test "UPDATE BY two levels: first./last. gate per changed level (BUG-updatefirstlast)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // master groups (g,k) = (1,1),(1,2),(2,1) share g=1 across the first two.
    const master = f.newDs("m");
    _ = try master.addColumn("g", .num);
    _ = try master.addColumn("k", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 } });
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    try master.appendRow(&.{ .{ .num = 2 }, .{ .num = 1 } });
    try f.lib.put("m", master);
    const trans = f.newDs("t");
    _ = try trans.addColumn("g", .num);
    _ = try trans.addColumn("k", .num);
    try f.lib.put("t", trans); // empty transactions — pure pass-through

    const names = [_][]const u8{ "m", "t" };
    const by_names = [_][]const u8{ "g", "k" };
    const prog = [_]ast.Stmt{
        .{ .update = &names },
        .{ .by = &by_names },
        .{ .assign = .{ .target = "fg", .value = f.vbl("first.g") } },
        .{ .assign = .{ .target = "lg", .value = f.vbl("last.g") } },
        .{ .assign = .{ .target = "fk", .value = f.vbl("first.k") } },
        .{ .assign = .{ .target = "lk", .value = f.vbl("last.k") } },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 3), out.rowCount());
    // (1,1): fg=1 lg=0 fk=1 lk=1; (1,2): fg=0 lg=1 fk=1 lk=1; (2,1): all 1.
    const want = [3][4]f64{ .{ 1, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 1 } };
    const cols = [4][]const u8{ "fg", "lg", "fk", "lk" };
    for (0..3) |r| for (cols, 0..) |cn, c| {
        try t.expectEqual(want[r][c], out.row(r)[out.indexOf(cn).?].num);
    };
}

test "UPDATE on unsorted transactions fails loud (BUG-setbyunsorted)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("master");
    _ = try master.addColumn("k", .num);
    _ = try master.addColumn("x", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try master.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
    try f.lib.put("master", master);
    const trans = f.newDs("trans");
    _ = try trans.addColumn("k", .num);
    _ = try trans.addColumn("x", .num);
    try trans.appendRow(&.{ .{ .num = 2 }, .{ .num = 25 } }); // UNSORTED: 2 before 1
    try trans.appendRow(&.{ .{ .num = 1 }, .{ .num = 15 } });
    try f.lib.put("trans", trans);

    const names = [_][]const u8{ "master", "trans" };
    const by_names = [_][]const u8{"k"};
    const prog = [_]ast.Stmt{ .{ .update = &names }, .{ .by = &by_names } };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasErrors()); // captured diagnostic (D-003)
}

test "MERGE BY populates first./last. per group iteration (BUG-mergefirstlast)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // big: k=1,1,2 merged with look: k=1,2 → groups {1:2 rows} {2:1 row}.
    const big = f.newDs("big");
    _ = try big.addColumn("k", .num);
    _ = try big.addColumn("v", .num);
    try big.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try big.appendRow(&.{ .{ .num = 1 }, .{ .num = 11 } });
    try big.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
    try f.lib.put("big", big);
    const look = f.newDs("look");
    _ = try look.addColumn("k", .num);
    _ = try look.addColumn("r", .num);
    try look.appendRow(&.{ .{ .num = 1 }, .{ .num = 100 } });
    try look.appendRow(&.{ .{ .num = 2 }, .{ .num = 200 } });
    try f.lib.put("look", look);

    // data out; merge big look; by k; fst=first.k; lst=last.k; run;
    const merge_names = [_][]const u8{ "big", "look" };
    const by_names = [_][]const u8{"k"};
    const prog = [_]ast.Stmt{
        .{ .merge = &merge_names },
        .{ .by = &by_names },
        .{ .assign = .{ .target = "fst", .value = f.vbl("first.k") } },
        .{ .assign = .{ .target = "lst", .value = f.vbl("last.k") } },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 3), out.rowCount());
    const fi = out.indexOf("fst").?;
    const li = out.indexOf("lst").?;
    // group k=1 rows 0,1: first 1,0; last 0,1. group k=2 row 2: first=last=1.
    const want_f = [_]f64{ 1, 0, 1 };
    const want_l = [_]f64{ 0, 1, 1 };
    for (0..3) |r| {
        try t.expectEqual(want_f[r], out.row(r)[fi].num);
        try t.expectEqual(want_l[r], out.row(r)[li].num);
    }
}

test "MERGE BY two levels: first./last. gate per changed level (BUG-mergefirstlast)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // one source is enough to exercise the group walk: (g,k) = (1,1),(1,2),(2,1)
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("g", .num);
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 } });
    try a_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    try a_ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 1 } });
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("g", .num);
    _ = try b_ds.addColumn("k", .num);
    try b_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 } });
    try f.lib.put("b", b_ds);

    const merge_names = [_][]const u8{ "a", "b" };
    const by_names = [_][]const u8{ "g", "k" };
    const prog = [_]ast.Stmt{
        .{ .merge = &merge_names },
        .{ .by = &by_names },
        .{ .assign = .{ .target = "fg", .value = f.vbl("first.g") } },
        .{ .assign = .{ .target = "lg", .value = f.vbl("last.g") } },
        .{ .assign = .{ .target = "fk", .value = f.vbl("first.k") } },
        .{ .assign = .{ .target = "lk", .value = f.vbl("last.k") } },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 3), out.rowCount());
    // rows: (1,1) fg=1 lg=0 fk=1 lk=1; (1,2) fg=0 lg=1 fk=1 lk=1; (2,1) all 1.
    const want = [3][4]f64{ .{ 1, 0, 1, 1 }, .{ 0, 1, 1, 1 }, .{ 1, 1, 1, 1 } };
    const cols = [4][]const u8{ "fg", "lg", "fk", "lk" };
    for (0..3) |r| for (cols, 0..) |cn, c| {
        try t.expectEqual(want[r][c], out.row(r)[out.indexOf(cn).?].num);
    };
}

test "SET on a missing dataset fails loud, emits nothing (BUG-setmissingquiet)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data back; set nosuch; run; — was a warning + skipped step + exit 0,
    // silently never creating `back`. SAS: "ERROR: File NOSUCH does not exist".
    const names = [_][]const u8{"nosuch"};
    const prog = [_]ast.Stmt{.{ .set = &names }};
    var out = Dataset.init(f.a(), "back");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasErrors()); // captured diagnostic (D-003)
    try t.expectEqual(@as(usize, 0), out.rowCount());
}

test "INFILE of a non-existent file fails loud, does not silently read 0 obs (ISS-infilemissing GH#45)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // infile "…nonexistent…"; input x; — was `readFileAlloc(...) catch ""`, so a
    // missing physical file produced a silent 0-obs dataset at exit 0. SAS hard-
    // errors "Physical file does not exist". Needs a real Io (the null unit-test
    // branch must NOT fire) → the global single-threaded io reaches the disk.
    x.io = std.Io.Threaded.global_single_threaded.io();
    x.infile = .{ .path = "/tmp/opensas_no_such_file_iss_infilemissing.dat" };
    const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    const prog = [_]ast.Stmt{.{ .input = &items }};
    var out = Dataset.init(f.a(), "w");
    // AUDIT-errhaltclass finishes what this test's title always claimed: the
    // step now STOPS at the open failure instead of reporting and reading an
    // empty source, so run() errors and main.zig's `lib.put(name, ds)` (which
    // sits AFTER `try ex.run(...)`) never registers the data set. Without the
    // halt, `data sc.keeper; infile 'nope'; input i;` replaced a live 3-obs
    // permanent member with an empty one at exit 1, readable at exit 0.
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "Physical file does not exist")); // captured diagnostic
    try t.expectEqual(@as(usize, 0), out.rowCount()); // and no row was fabricated
}

test "PERF-infilecap: INFILE streams a >1 MiB external file — no size cap, every row read" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // ~3 MB CSV — over the old 1 MiB readFileAlloc cap, which failed the step,
    // and (bonus bug) its catch mislabeled error.FileTooBig as "Physical file
    // does not exist" for a file that EXISTS.
    const io_ = std.Io.Threaded.global_single_threaded.io();
    const n_rows: usize = 200_000;
    const path = "/tmp/opensas_perf_infilecap_big.csv";
    {
        var w: std.Io.Writer.Allocating = .init(f.a());
        var i: usize = 1;
        while (i <= n_rows) : (i += 1) try w.writer.print("{d},{d}\n", .{ i, i * 10 });
        try Io.Dir.cwd().writeFile(io_, .{ .sub_path = path, .data = w.written() });
    }
    defer Io.Dir.cwd().deleteFile(io_, path) catch {};

    x.io = io_;
    x.infile = .{ .path = path, .dlm = ",", .dsd = true, .overflow = .truncover };
    const items = [_]ast.InputItem{
        .{ .name = "id", .type = .num },
        .{ .name = "v", .type = .num },
    };
    const prog = [_]ast.Stmt{.{ .input = &items }};
    var out = Dataset.init(f.a(), "w");
    try x.run(&prog, &out);

    try t.expect(!diagsHave(&f.diags, "Physical file does not exist")); // the phantom-path bug
    try t.expect(!f.diags.hasStepErrors());
    try t.expectEqual(n_rows, out.rowCount());
    // the tail wasn't truncated: last row carries the last line's values
    const idi = out.indexOf("id").?;
    const vi = out.indexOf("v").?;
    try t.expectEqual(@as(f64, @floatFromInt(n_rows)), out.row(n_rows - 1)[idi].num);
    try t.expectEqual(@as(f64, @floatFromInt(n_rows * 10)), out.row(n_rows - 1)[vi].num);
}

test "MERGE with a BY variable absent from one source fails loud, emits nothing (BUG-mergebymissing)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // a(k,v) sorted by k; b(x,w) has NO k — real SAS hard-errors; we silently
    // interleaved b's rows first (all-missing key) then a's (BUG-mergebymissing).
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    _ = try a_ds.addColumn("v", .num);
    try a_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try a_ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("x", .num);
    _ = try b_ds.addColumn("w", .num);
    try b_ds.appendRow(&.{ .{ .num = 7 }, .{ .num = 70 } });
    try f.lib.put("b", b_ds);

    const merge_names = [_][]const u8{ "a", "b" };
    const by_names = [_][]const u8{"k"};
    const prog = [_]ast.Stmt{ .{ .merge = &merge_names }, .{ .by = &by_names } };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasErrors()); // captured diagnostic (D-003)
    try t.expectEqual(@as(usize, 0), out.rowCount()); // no garbage output
}

test "SET-BY / UPDATE with a BY variable absent from a source fail loud (BUG-mergebymissing)" {
    var f = fixture();
    defer f.deinit();
    f.prime();

    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("x", .num);
    try b_ds.appendRow(&.{.{ .num = 7 }});
    try f.lib.put("b", b_ds);

    const names = [_][]const u8{ "a", "b" };
    const by_names = [_][]const u8{"k"};
    { // set a b; by k;
        var x = f.exec();
        const prog = [_]ast.Stmt{ .{ .set = &names }, .{ .by = &by_names } };
        var out = Dataset.init(f.a(), "out1");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasErrors());
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    f.diags = diag.Diagnostics.init(f.a()); // reset for the UPDATE half
    { // update a b; by k;
        var x = f.exec();
        const prog = [_]ast.Stmt{ .{ .update = &names }, .{ .by = &by_names } };
        var out = Dataset.init(f.a(), "out2");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasErrors());
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
}

test "UPDATE applies transaction rows to master by BY key (BUG-updatebroken)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // master: (id,x,y) keyed+sorted by id, unique
    const master = f.newDs("master");
    _ = try master.addColumn("id", .num);
    _ = try master.addColumn("x", .num);
    _ = try master.addColumn("y", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 }, .{ .num = 100 } });
    try master.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 }, .{ .num = 200 } });
    try master.appendRow(&.{ .{ .num = 3 }, .{ .num = 30 }, .{ .num = 300 } });
    try f.lib.put("master", master);
    // trans: id=2 x missing (keep) y=250; id=3 x=35 y missing (keep); id=4 new
    const trans = f.newDs("trans");
    _ = try trans.addColumn("id", .num);
    _ = try trans.addColumn("x", .num);
    _ = try trans.addColumn("y", .num);
    try trans.appendRow(&.{ .{ .num = 2 }, Value.missing, .{ .num = 250 } });
    try trans.appendRow(&.{ .{ .num = 3 }, .{ .num = 35 }, Value.missing });
    try trans.appendRow(&.{ .{ .num = 4 }, .{ .num = 40 }, .{ .num = 400 } });
    try f.lib.put("trans", trans);

    const up_names = [_][]const u8{ "master", "trans" };
    const by_names = [_][]const u8{"id"};
    const prog = [_]ast.Stmt{ .{ .update = &up_names }, .{ .by = &by_names } };

    var out = Dataset.init(f.a(), "master2");
    try x.run(&prog, &out);

    const xi = out.indexOf("x").?;
    const yi = out.indexOf("y").?;
    // one row per BY group: 1 (untouched), 2 (x kept, y updated), 3 (x updated,
    // y kept), 4 (new key from the transaction)
    try t.expectEqual(@as(usize, 4), out.rowCount());
    try t.expectEqual(@as(f64, 10), out.row(0)[xi].num);
    try t.expectEqual(@as(f64, 100), out.row(0)[yi].num);
    try t.expectEqual(@as(f64, 20), out.row(1)[xi].num); // missing trans x kept master 20
    try t.expectEqual(@as(f64, 250), out.row(1)[yi].num); // trans y overwrote
    try t.expectEqual(@as(f64, 35), out.row(2)[xi].num); // trans x overwrote
    try t.expectEqual(@as(f64, 300), out.row(2)[yi].num); // missing trans y kept master 300
    try t.expectEqual(@as(f64, 40), out.row(3)[xi].num); // new key
    try t.expectEqual(@as(f64, 400), out.row(3)[yi].num);
}

test "MODIFY-BY no-match: ERROR + _IORC_=_DSENMR, unmatched row NOT fabricated (BUG-modifybynomatch)" {
    // Language Reference: Concepts p.599 Table 23.4 (_DSENMR) + p.600 worked example: a MODIFY … BY
    // transaction obs with no master match is an ERROR — "No matching
    // observation was found in <master> data set.", _ERROR_=1, _IORC_=1230015,
    // and "0 observations added" (appending unmatched keys is UPDATE's job).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("master");
    _ = try master.addColumn("id", .num);
    _ = try master.addColumn("v", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try master.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
    try f.lib.put("master", master);
    const trans = f.newDs("trans");
    _ = try trans.addColumn("id", .num);
    _ = try trans.addColumn("v", .num);
    try trans.appendRow(&.{ .{ .num = 2 }, .{ .num = 999 } }); // overwrite id=2
    try trans.appendRow(&.{ .{ .num = 3 }, .{ .num = 30 } }); // no master match
    try f.lib.put("trans", trans);

    const mod_names = [_][]const u8{ "master", "trans" };
    const by_names = [_][]const u8{"id"};
    const prog = [_]ast.Stmt{ .{ .modify = &mod_names }, .{ .by = &by_names } };

    var out = Dataset.init(f.a(), "master"); // in place: output shares the master name
    try x.run(&prog, &out);
    try f.lib.put("master", &out); // main's commit — put replaces the master

    // Matched obs rewritten, unmatched NOT added; the step ran to completion.
    const m2 = f.lib.find("master").?;
    const vi = m2.indexOf("v").?;
    try t.expectEqual(@as(usize, 2), m2.rowCount());
    try t.expectEqual(@as(f64, 10), m2.row(0)[vi].num); // untouched
    try t.expectEqual(@as(f64, 999), m2.row(1)[vi].num); // transaction overwrote
    try t.expect(m2.indexOf("_iorc_") == null); // automatic, never written out
    // The unhandled no-match reported the Language Reference: Concepts p.600 ERROR (captured reporter).
    try t.expect(f.diags.hasStepErrors());
    const msg = f.diags.list.items[f.diags.list.items.len - 1].message;
    try t.expectEqualStrings("No matching observation was found in master data set.", msg);
}

test "MODIFY-BY revised program: test _IORC_, OUTPUT the unmatched row, clear _ERROR_ (BUG-modifybynomatch)" {
    // Language Reference: Concepts p.601 revised program: `if _iorc_ = <_DSENMR> then do; output;
    // _error_ = 0; end; else replace;` — the program handles the no-match
    // itself, so the row IS added and NO error is raised (the step and every
    // later step run clean; a matched read sees _IORC_=0).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("master");
    _ = try master.addColumn("id", .num);
    _ = try master.addColumn("v", .num);
    // GAP-ch23med-tick296 F3: `seen` is DECLARED ON THE MASTER. It used to be a
    // step-created variable, and this test asserted it came back as a column of
    // the master — i.e. it PINNED the descriptor-growth bug, because MODIFY
    // "cannot modify the descriptor portion of a SAS data set, such as adding a
    // variable" (Statements ref printed p.240). The variable is only this test's
    // recorder for per-observation `_IORC_`, so declaring it up front keeps every
    // assertion below testing exactly what it tested — and makes the program
    // legal SAS as well.
    _ = try master.addColumn("seen", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 }, missingOf(.num) });
    try master.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 }, missingOf(.num) });
    try f.lib.put("master", master);
    const trans = f.newDs("trans");
    _ = try trans.addColumn("id", .num);
    _ = try trans.addColumn("v", .num);
    try trans.appendRow(&.{ .{ .num = 2 }, .{ .num = 999 } });
    try trans.appendRow(&.{ .{ .num = 3 }, .{ .num = 30 } });
    try f.lib.put("trans", trans);

    const mod_names = [_][]const u8{ "master", "trans" };
    const by_names = [_][]const u8{"id"};
    const no_output = [_][]const u8{};
    const add_row: ast.Stmt = .{ .output = &no_output };
    const clr: ast.Stmt = .{ .assign = .{ .target = "_error_", .value = f.num(0) } };
    const seen: ast.Stmt = .{ .assign = .{ .target = "seen", .value = f.vbl("_iorc_") } };
    const do_body = [_]ast.Stmt{ add_row, clr };
    const then_do: ast.Stmt = .{ .do_ = .{ .header = .simple, .body = &do_body } };
    const repl_name = [_][]const u8{"\x00replace"};
    const repl: ast.Stmt = .{ .output = &repl_name };
    const prog = [_]ast.Stmt{
        .{ .modify = &mod_names },
        .{ .by = &by_names },
        seen, // capture _IORC_ per obs: 0 on a match, 1230015 on the no-match
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("_iorc_"), f.num(1230015)), .then_branch = &then_do, .else_branch = &repl } },
    };

    var out = Dataset.init(f.a(), "master");
    try x.run(&prog, &out);
    try f.lib.put("master", &out);

    const m2 = f.lib.find("master").?;
    const vi = m2.indexOf("v").?;
    const si = m2.indexOf("seen").?;
    try t.expectEqual(@as(usize, 3), m2.rowCount()); // program added the new key
    try t.expectEqual(@as(f64, 999), m2.row(1)[vi].num); // matched: replaced
    try t.expectEqual(@as(f64, 30), m2.row(2)[vi].num); // no-match: OUTPUT added
    // the id=1 master row has NO transaction — it is never read into the PDV
    // (BUG-modifybymasterdriven: no _SOK iteration exists for it), so `seen`
    // was never assigned there: missing, and the row is re-emitted untouched.
    try t.expect(std.math.isNan(m2.row(0)[si].num));
    try t.expectEqual(@as(f64, 10), m2.row(0)[vi].num); // untouched, byte-identical
    try t.expectEqual(@as(f64, 1230015), m2.row(2)[si].num); // _DSENMR
    try t.expect(m2.indexOf("_iorc_") == null);
    try t.expect(!f.diags.hasStepErrors()); // handled → no error, no errhalt
    // `_iorc_` is an automatic: referencing it notes NO "uninitialized".
    for (f.diags.list.items) |d| try t.expect(std.mem.indexOf(u8, d.message, "uninitialized") == null);
}

test "MODIFY POINT= fails LOUD, not silent-wrong via buildUpdate (FEAT-datamodify)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("m");
    _ = try master.addColumn("id", .num);
    _ = try master.addColumn("v", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try f.lib.put("m", master);

    // parser encodes `modify m point=p;` as the name list ["m", "\x00point=p"];
    // the sentinel must fail loud, never inflate the list into a phantom UPDATE.
    const mod_names = [_][]const u8{ "m", "\x00point=p" };
    const prog = [_]ast.Stmt{.{ .modify = &mod_names }};

    var out = Dataset.init(f.a(), "m");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    // BUG-modifyendmsg: Form 3 is "random access using POINT=" (Statements ref
    // printed p.240-241); "direct access" is the ref's phrase for KEY=, which
    // the parser gaps out before exec sees it.
    try t.expectEqualStrings("MODIFY point= (random access) is not supported yet", f.diags.list.items[f.diags.list.items.len - 1].message);
}

test "BUG-modifyendmsg: MODIFY END= is reported as the EOF flag it is, not as direct/keyed access" {
    // END= was reported as "(direct/keyed access)". Statements ref printed
    // p.240-241: END= "creates and names a temporary variable that contains an
    // end-of-file indicator", appears on Forms 1/2/4 (the sequential, matching
    // and KEY= forms) and carries the Restriction "Do not use this argument in
    // the same MODIFY statement with the POINT= argument" — so it is not the
    // direct-access form, it is barred from co-occurring with it. Message-only:
    // the gap and its rc 2 are unchanged, and pinned here alongside the wording.
    diag.resetGap();
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("m");
    _ = try master.addColumn("id", .num);
    try master.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("m", master);

    const mod_names = [_][]const u8{ "m", "\x00end=e" };
    const prog = [_]ast.Stmt{.{ .modify = &mod_names }};

    var out = Dataset.init(f.a(), "m");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expectEqualStrings("MODIFY end= (end-of-file indicator) is not supported yet", f.diags.list.items[f.diags.list.items.len - 1].message);
    try t.expectEqual(@as(u8, 2), rcOf(&f)); // still a documented-argument GAP
}

test "GAP-modifywherestmt: a WHERE statement filters-then-matches in BOTH MODIFY shapes, no row loss" {
    // Statements ref printed p.360: "SAS selects observations from each input
    // data set before it combines them"; printed p.245: "uses dynamic WHERE
    // processing to locate the matching observation" — filter-then-match, the
    // only reading consistent with the described mechanism (the exact
    // WHERE-excluded-master-row case is genuinely doc-silent; the doc-finder
    // verdict is not re-derived here). Both shapes previously failed in
    // OPPOSITE silently-wrong ways — the single-dataset shape IGNORED the
    // statement (wrong values), the BY shape flushed the filtered copy
    // (destroyed rows) — then both refused at rc 2. Now implemented: the
    // iteration reads/matches the filtered copy, the commit re-emits the
    // UNFILTERED member through src_pos.

    // 1. BY shape: data m; modify m t; by k; where k>1; — k=1 is hidden from
    //    the match AND from the transaction (p.360: the bare statement filters
    //    every input), must survive the commit EXACTLY as stored; k=2 is
    //    overlaid by the transaction. (The old destroy shape, flipped.)
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const m = f.newDs("m");
        _ = try m.addColumn("k", .num);
        _ = try m.addColumn("v", .num);
        try m.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
        try m.appendRow(&.{ .{ .num = 2 }, .{ .num = 20 } });
        try m.appendRow(&.{ .{ .num = 3 }, .{ .num = 30 } });
        try f.lib.put("m", m);
        const tr = f.newDs("t");
        _ = try tr.addColumn("k", .num);
        _ = try tr.addColumn("v", .num);
        try tr.appendRow(&.{ .{ .num = 2 }, .{ .num = 999 } });
        try f.lib.put("t", tr);

        const two = [_][]const u8{ "m", "t" };
        const bys = [_][]const u8{"k"};
        const prog = [_]ast.Stmt{
            .{ .modify = &two },
            .{ .by = &bys },
            .{ .where_ = f.bin(.gt, f.vbl("k"), f.num(1)) },
        };
        var out = Dataset.init(f.a(), "m");
        try x.run(&prog, &out); // no ExecError, no rc-2 gap refusal
        try t.expect(!f.diags.hasErrors());
        const stored = &out; // the rebuilt master (main.zig puts it back in real runs)
        try t.expectEqual(@as(usize, 3), stored.rowCount()); // NOTHING destroyed
        const kc = stored.indexOf("k").?;
        const vc = stored.indexOf("v").?;
        try t.expectEqual(@as(f64, 1), stored.row(0)[kc].num); // hidden from the match,
        try t.expectEqual(@as(f64, 10), stored.row(0)[vc].num); // re-emitted untouched
        try t.expectEqual(@as(f64, 2), stored.row(1)[kc].num);
        try t.expectEqual(@as(f64, 999), stored.row(1)[vc].num); // transaction overlay
        try t.expectEqual(@as(f64, 3), stored.row(2)[kc].num);
        try t.expectEqual(@as(f64, 30), stored.row(2)[vc].num); // selected, never matched
    }

    // 2. Single-dataset shape: data m; modify m; where k>2; v=v+1; — only the
    //    selected rows are read and updated; k=1/2 come back byte-identical.
    //    (Was silently IGNORED: all four rows were bumped.)
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const m = f.newDs("m");
        _ = try m.addColumn("k", .num);
        _ = try m.addColumn("v", .num);
        for ([_]f64{ 1, 2, 3, 4 }) |k| try m.appendRow(&.{ .{ .num = k }, .{ .num = k * 10 } });
        try f.lib.put("m", m);

        const one = [_][]const u8{"m"};
        const prog = [_]ast.Stmt{
            .{ .modify = &one },
            .{ .where_ = f.bin(.gt, f.vbl("k"), f.num(2)) },
            .{ .assign = .{ .target = "v", .value = f.bin(.add, f.vbl("v"), f.num(1)) } },
        };
        var out = Dataset.init(f.a(), "m");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        const stored = &out;
        try t.expectEqual(@as(usize, 4), stored.rowCount());
        const vc = stored.indexOf("v").?;
        try t.expectEqual(@as(f64, 10), stored.row(0)[vc].num); // excluded: untouched
        try t.expectEqual(@as(f64, 20), stored.row(1)[vc].num); // excluded: untouched
        try t.expectEqual(@as(f64, 31), stored.row(2)[vc].num); // selected: updated
        try t.expectEqual(@as(f64, 41), stored.row(3)[vc].num); // selected: updated
    }
}

test "GAP-modifywherestmt: filter-then-match's doc-silent case — a surviving transaction naming a WHERE-excluded master key is a NO-MATCH" {
    // The exact case the doc-finder found GENUINELY DOC-SILENT (Table 23.3 has
    // no subsetting row; _DSENMR does not distinguish physically-absent from
    // WHERE-excluded): master (k=1,x=5) fails `where x>10`, transaction (k=1,
    // x=20) passes it (x rides BOTH inputs, p.360's rule). Filter-then-match —
    // the only reading consistent with p.360/p.245 — says the transaction is
    // UNMATCHED: _IORC_=_DSENMR, the p.601 idiom OUTPUTs a NEW row, and the
    // excluded master row is re-emitted untouched, so the master ends with
    // BOTH k=1 rows. Match-then-filter would instead have updated the hidden
    // row; nothing in the volumes supports it.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();
    const m = f.newDs("m");
    _ = try m.addColumn("k", .num);
    _ = try m.addColumn("x", .num);
    try m.appendRow(&.{ .{ .num = 1 }, .{ .num = 5 } });
    try m.appendRow(&.{ .{ .num = 2 }, .{ .num = 15 } });
    try f.lib.put("m", m);
    const tr = f.newDs("t");
    _ = try tr.addColumn("k", .num);
    _ = try tr.addColumn("x", .num);
    try tr.appendRow(&.{ .{ .num = 1 }, .{ .num = 20 } });
    try tr.appendRow(&.{ .{ .num = 2 }, .{ .num = 25 } });
    try f.lib.put("t", tr);

    const two = [_][]const u8{ "m", "t" };
    const bys = [_][]const u8{"k"};
    const empty_out = [_][]const u8{};
    const inner = [_]ast.Stmt{
        .{ .assign = .{ .target = "_error_", .value = f.num(0) } },
        .{ .output = &empty_out },
    };
    const do_blk = ast.Stmt{ .do_ = .{ .header = .simple, .body = &inner } };
    const prog = [_]ast.Stmt{
        .{ .modify = &two },
        .{ .by = &bys },
        .{ .where_ = f.bin(.gt, f.vbl("x"), f.num(10)) },
        // the Language Reference: Concepts p.601 revised-program idiom: handle _DSENMR, add the row
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("_iorc_"), f.num(1230015)), .then_branch = &do_blk, .else_branch = null } },
    };
    var out = Dataset.init(f.a(), "m");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors()); // the idiom cleared _ERROR_; no p.600 ERROR
    const stored = &out;
    try t.expectEqual(@as(usize, 3), stored.rowCount());
    const kc = stored.indexOf("k").?;
    const xc = stored.indexOf("x").?;
    try t.expectEqual(@as(f64, 1), stored.row(0)[kc].num); // the WHERE-excluded master row,
    try t.expectEqual(@as(f64, 5), stored.row(0)[xc].num); // re-emitted UNTOUCHED (no loss)
    try t.expectEqual(@as(f64, 2), stored.row(1)[kc].num); // matched (survives the filter):
    try t.expectEqual(@as(f64, 25), stored.row(1)[xc].num); // transaction overlay
    try t.expectEqual(@as(f64, 1), stored.row(2)[kc].num); // the p.601 OUTPUT — a NEW row
    try t.expectEqual(@as(f64, 20), stored.row(2)[xc].num); // appended at the END
}

test "BUG-modifymasteroptname: a master's dataset OPTIONS are not part of its name — same rc-1 mismatch text with and without them" {
    // The mismatch guard used to compare the SERIALIZED name+options blob, so
    // `modify a(keep=x)` reported "MODIFY updates a(keep = x ) in place, …" and
    // could never match any DATA statement name. Both spellings must now produce
    // the IDENTICAL diagnostic naming the bare member `a` — that identity is the
    // point, so a future change cannot fix one spelling and drift on the other.
    for ([_][]const u8{ "a", "a(keep = x )" }) |master| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const src = f.newDs("a");
        _ = try src.addColumn("x", .num);
        try src.appendRow(&.{.{ .num = 1 }});
        try f.lib.put("a", src);

        const mod_names = [_][]const u8{master};
        const prog = [_]ast.Stmt{.{ .modify = &mod_names }};

        var out = Dataset.init(f.a(), "b"); // the DATA statement names `b`, not `a`
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqualStrings(
            "MODIFY updates a in place, but the DATA statement names b — the MODIFY data set must also appear in the DATA statement",
            f.diags.list.items[f.diags.list.items.len - 1].message,
        );
        try t.expectEqual(@as(u8, 1), rcOf(&f)); // user error, not a gap
    }
}

test "BUG-modifyoutnamemismatch: MODIFY's master must be an output data set — rc 1, master untouched, wrong output never written" {
    // `data b; modify d;` degraded SILENTLY to `data b; set d;` at exit 0. The
    // corpus fixtures pin the rc and the values that come back on a revert; this
    // pins what they cannot show from outside the process — that the master is
    // left ALONE and the wrongly-named output receives NOTHING, so there is no
    // half-written state behind the diagnostic.
    diag.resetGap();
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("d");
    _ = try master.addColumn("id", .num);
    _ = try master.addColumn("v", .num);
    try master.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try f.lib.put("d", master);

    const mod_names = [_][]const u8{"d"};
    const prog = [_]ast.Stmt{.{ .modify = &mod_names }};

    var out = Dataset.init(f.a(), "b"); // the DATA statement names `b`, not `d`
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expectEqualStrings(
        "MODIFY updates d in place, but the DATA statement names b — the MODIFY data set must also appear in the DATA statement",
        f.diags.list.items[f.diags.list.items.len - 1].message,
    );
    // rc 1, NOT 2: the program breaks a documented Restriction (Statements ref
    // printed p.241, master-data-set), so real SAS rejects it too — "fix your
    // SAS", not an opensas hole (D-009). No markGap anywhere on this path.
    try t.expectEqual(@as(u8, 1), rcOf(&f));
    // The master is byte-identical: the step never ran a row.
    try t.expectEqual(@as(usize, 1), f.lib.find("d").?.rowCount());
    try t.expectEqual(@as(f64, 10), f.lib.find("d").?.row(0)[1].num);
    // …and nothing was written into the wrongly-named output either.
    try t.expectEqual(@as(usize, 0), out.rowCount());
}

test "BUG-modifyoutnamemismatch D-014 control: the master may be an EXTRA output, and `work.d` names `d`" {
    // Statements ref printed p.260 Example 8 — `data invty.stock invty.stock95
    // invty.stock97; modify invty.stock;` — makes the rule MEMBERSHIP, not
    // equality. An over-strict `==` here would reject legal SAS, which is its
    // own shipped regression (D-014). Both loopholes the guard must leave open
    // are pinned: the master sitting among `extra_outs` rather than as the
    // primary, and `work.d`/`d` being one member (Library.put/find already
    // compare through stripWork, so the membership test must too).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("d");
    _ = try master.addColumn("v", .num);
    try master.appendRow(&.{.{ .num = 10 }});
    try f.lib.put("d", master);

    const mod_names = [_][]const u8{"work.d"};
    const prog = [_]ast.Stmt{.{ .modify = &mod_names }};

    var extra = Dataset.init(f.a(), "d");
    var extras = [_]*Dataset{&extra};
    x.extra_outs = &extras;

    var out = Dataset.init(f.a(), "other"); // primary is NOT the master…
    try x.run(&prog, &out); // …but `d` is an extra output, so this is legal
    try t.expectEqual(@as(usize, 1), extra.rowCount());
}

test "REMOVE outside a MODIFY step fails LOUD (FEAT-datamodify-rest)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const src = f.newDs("s");
    _ = try src.addColumn("a", .num);
    try src.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("s", src);

    // `remove;` encodes as OUTPUT of the \x00remove sentinel; with no MODIFY in the
    // step it is meaningless in-place control — fail loud, never drop the wrong obs.
    const set_names = [_][]const u8{"s"};
    const rm = [_][]const u8{"\x00remove"};
    const prog = [_]ast.Stmt{ .{ .set = &set_names }, .{ .output = &rm } };

    var out = Dataset.init(f.a(), "out");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expectEqualStrings("remove is valid only in a DATA step with a MODIFY statement", f.diags.list.items[f.diags.list.items.len - 1].message);
}

test "OUTPUT inside a MODIFY step fails LOUD, not silent-wrong (FEAT-datamodify-rest)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const master = f.newDs("m");
    _ = try master.addColumn("a", .num);
    try master.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("m", master);

    // The rebuild-commit model can't append-preserving-original (OUTPUT's real
    // semantics), so an explicit OUTPUT in a MODIFY step fails loud (BAIL).
    const mod_names = [_][]const u8{"m"};
    const empty = [_][]const u8{};
    const prog = [_]ast.Stmt{ .{ .modify = &mod_names }, .{ .output = &empty } };

    var out = Dataset.init(f.a(), "m");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expectEqualStrings("OUTPUT is not supported in a DATA step with MODIFY; use REPLACE or REMOVE", f.diags.list.items[f.diags.list.items.len - 1].message);
}
// Happy path (REMOVE drops, REPLACE rewrites, untouched obs kept via implicit
// REPLACE) is covered end-to-end by tests/corpus/modify_remove.sas.

test "SET input dataset option keep= filters columns on read (SETOPT)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const src = f.newDs("src");
    _ = try src.addColumn("x", .num);
    _ = try src.addColumn("y", .num);
    try src.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    try f.lib.put("src", src);

    // the parser encodes options into the name string: `src(keep=x)`
    const set_names = [_][]const u8{"src(keep = x )"};
    const prog = [_]ast.Stmt{.{ .set = &set_names }};

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    try t.expect(out.indexOf("x") != null);
    try t.expect(out.indexOf("y") == null); // keep=x dropped y
    try t.expectEqual(@as(f64, 1), out.row(0)[out.indexOf("x").?].num);
    // the source dataset is unchanged (options applied to a copy)
    try t.expectEqual(@as(usize, 2), src.columns.items.len);
}

test "hash add rejects duplicate keys; replace overwrites in place (BUG-hashreplace)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;

    const put100 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(100) } };
    const put999 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(999) } };
    const put200 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(200) } };
    const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};

    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &put100)); // inserted
    try t.expectEqual(@as(f64, 1), try ex.hashAdd(h, &put999)); // duplicate key → rejected, non-zero
    try t.expectEqual(@as(usize, 1), h.entries.items.len); // no duplicate row created

    try t.expectEqual(@as(f64, 0), try ex.hashReplace(h, &put200)); // overwrite in place
    try t.expectEqual(@as(usize, 1), h.entries.items.len); // still exactly one row

    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &key1)); // hit
    try t.expectEqual(@as(f64, 200), f.pdv.get("v").?.num); // the replaced data, not the stale 100
}

test "SEV-rcbydesignerr: the seven rc-by-design hash conditions report a RECOVERABLE error — loud and exit-relevant, but later steps are not poisoned" {
    // Component Objects Reference: every hash method entry carries the same rc
    // contract — "A return code of zero indicates success; a nonzero value
    // indicates failure. If you do not supply a return code variable for the
    // method call and the method fails, then an appropriate error message is
    // written to the log." (ADD printed p.24, FIND_NEXT p.53, OUTPUT p.73,
    // REMOVE p.82; duplicate:'e' itself printed p.32.) The ERROR is the
    // documented fallback for an UNCHECKED rc — a program that checks the rc
    // has handled the condition BY DESIGN, so the report must stay an ERROR
    // (non-zero exit) yet must not errhalt-skip later steps (the D-014
    // shape). Each arm below asserts the rc, the captured message (D-003),
    // and hasErrors() && !hasStepErrors(); each revert of one site turns
    // exactly its arm red.

    // 1. dataset-load duplicate:'e' — report, keep first, continue (p.32).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const ds = f.newDs("src");
        _ = try ds.addColumn("k", .num);
        try ds.appendRow(&.{.{ .num = 1 }});
        try ds.appendRow(&.{.{ .num = 1 }}); // the duplicate
        try f.lib.putInput("src", ds);
        const h = try f.a().create(HashObject);
        h.* = .{ .name = "h", .src = "src", .done = true, .duplicate = .err };
        try h.keys.append(f.a(), "k");
        try h.datas.append(f.a(), "k");
        try x.hashLoadDataset(h);
        try t.expectEqual(@as(usize, 1), h.entries.items.len); // first kept, dup ignored
        try t.expect(diagsHave(&f.diags, "hash dataset src: duplicate key (duplicate:'e')"));
        try t.expect(f.diags.hasErrors());
        try t.expect(!f.diags.hasStepErrors());
    }

    // 2. add() duplicate:'e' → rc=1 (p.24/p.26).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const h = try f.a().create(HashObject);
        h.* = .{ .name = "h", .done = true, .duplicate = .err };
        try h.keys.append(f.a(), "k");
        try h.datas.append(f.a(), "v");
        const put = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(10) } };
        try t.expectEqual(@as(f64, 0), try x.hashAdd(h, &put));
        try t.expectEqual(@as(f64, 1), try x.hashAdd(h, &put)); // duplicate → rc=1
        try t.expect(diagsHave(&f.diags, "hash add: duplicate key (duplicate:'e')"));
        try t.expect(f.diags.hasErrors());
        try t.expect(!f.diags.hasStepErrors());
    }

    // 3. find_next() without a successful find() → SAS's 160038 (p.53).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const h = try f.a().create(HashObject);
        h.* = .{ .name = "h", .done = true };
        try t.expectEqual(@as(f64, 160038), try x.hashFindNext(h));
        try t.expect(diagsHave(&f.diags, "find_next() called without a successful find()"));
        try t.expect(f.diags.hasErrors());
        try t.expect(!f.diags.hasStepErrors());
    }

    // 4. remove() while a bound iterator is positioned on the key → rc=1 (p.82).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const h = try f.a().create(HashObject);
        h.* = .{ .name = "h", .done = true };
        try h.keys.append(f.a(), "k");
        try h.datas.append(f.a(), "v");
        const put = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(10) } };
        try t.expectEqual(@as(f64, 0), try x.hashAdd(h, &put));
        const it = try f.a().create(HashObject);
        it.* = .{ .name = "it", .iter_of = "h", .iter_on = true, .iter_pos = 0 };
        try x.hashes.append(f.a(), it);
        const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
        try t.expectEqual(@as(f64, 1), try x.hashRemove(h, &key1)); // not removed
        try t.expectEqual(@as(usize, 1), h.entries.items.len); // hash untouched
        try t.expect(diagsHave(&f.diags, "hash iterator it is positioned on it"));
        try t.expect(f.diags.hasErrors());
        try t.expect(!f.diags.hasStepErrors());
    }

    // 5-7. output() with no dataset: tag / malformed options / invalid name
    // → rc=1 (p.73).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const h = try f.a().create(HashObject);
        h.* = .{ .name = "h", .done = true };
        try h.keys.append(f.a(), "k");
        try h.datas.append(f.a(), "k");
        try t.expectEqual(@as(f64, 1), try x.hashOutput(h, &.{}));
        try t.expect(diagsHave(&f.diags, "hash output: dataset: is required"));
        const malformed = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "out(bad" }) }};
        try t.expectEqual(@as(f64, 1), try x.hashOutput(h, &malformed));
        try t.expect(diagsHave(&f.diags, "malformed data-set options"));
        const bad = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "9bad" }) }};
        try t.expectEqual(@as(f64, 1), try x.hashOutput(h, &bad));
        try t.expect(diagsHave(&f.diags, "'9bad' is not a valid SAS data set name"));
        try t.expect(f.diags.hasErrors());
        try t.expect(!f.diags.hasStepErrors());
        try t.expect(x.lib.find("out") == null and x.lib.find("9bad") == null); // nothing created
    }
}

test "BUG-hashkeytypesilent: a type-mismatched KEY:/DATA: argument fails LOUD on every keyed method; a real miss still returns 160038" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    // numeric key k, char data d — declared outside the hash (Language Reference: Concepts p.613).
    _ = try f.pdv.define("k", .num);
    _ = try f.pdv.define("d", .char);
    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "d");
    h.done = true;
    try ex.hashes.append(f.a(), h);

    const str_one = f.e(.{ .str = "one" });
    const seed = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = str_one } };
    const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
    const key9 = [_]ast.HashArg{.{ .name = "key", .value = f.num(9) }};
    const keyS = [_]ast.HashArg{.{ .name = "key", .value = f.e(.{ .str = "abc" }) }};

    // CONTROLS — unchanged: type-matched calls behave exactly as before, and a
    // legitimate miss still returns the plain not-found rc with NO diagnostic
    // (that distinction IS the fix).
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &seed));
    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &key1)); // hit
    try t.expectEqualStrings("one", f.pdv.get("d").?.str);
    try t.expectEqual(@as(f64, 160038), try ex.hashFind(h, &key9)); // real miss
    try t.expectEqual(@as(f64, 0), try ex.hashCheck(h, &key1));
    try t.expectEqual(@as(f64, 160038), try ex.hashCheck(h, &key9));
    try t.expectEqual(@as(f64, 160038), try ex.hashRemove(h, &key9)); // absent
    try t.expect(!f.diags.hasErrors()); // misses are quiet — only mismatches are loud

    // LOUD — a char value against the numeric key on EVERY keyed method: a
    // malformed call (Component Objects ref: the type-match sentence appears
    // 18 times), not a miss. Loud via captured diagnostics (D-003).
    const putS = [_]ast.HashArg{ .{ .name = "key", .value = f.e(.{ .str = "abc" }) }, .{ .name = "data", .value = str_one } };
    try t.expectError(error.ExecError, ex.hashFind(h, &keyS));
    try t.expectError(error.ExecError, ex.hashCheck(h, &keyS));
    try t.expectError(error.ExecError, ex.hashRemove(h, &keyS));
    try t.expectError(error.ExecError, ex.hashAdd(h, &putS));
    try t.expectError(error.ExecError, ex.hashReplace(h, &putS));
    try t.expect(f.diags.hasErrors());
    for (f.diags.list.items) |dg|
        try t.expect(std.mem.indexOf(u8, dg.message, "key k is numeric but the key: argument is character") != null);

    // DATA: form — the same sentence covers it: numeric value into char data d.
    const nd = f.diags.count();
    const badData = [_]ast.HashArg{ .{ .name = "key", .value = f.num(2) }, .{ .name = "data", .value = f.num(5) } };
    try t.expectError(error.ExecError, ex.hashAdd(h, &badData));
    try t.expectError(error.ExecError, ex.hashReplace(h, &badData));
    try t.expectEqual(nd + 2, f.diags.count());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[nd].message, "data d is character but the data: argument is numeric") != null);

    // SYMMETRIC — a numeric value against a CHAR-keyed hash fails loud too,
    // while a char key that simply misses stays a plain 160038.
    _ = try f.pdv.define("c", .char);
    const hc = try f.a().create(HashObject);
    hc.* = .{ .name = "hc" };
    try hc.keys.append(f.a(), "c");
    try hc.datas.append(f.a(), "d");
    hc.done = true;
    try t.expectError(error.ExecError, ex.hashFind(hc, &key1));
    const keyCx = [_]ast.HashArg{.{ .name = "key", .value = f.e(.{ .str = "x" }) }};
    try t.expectEqual(@as(f64, 160038), try ex.hashFind(hc, &keyCx)); // real miss on a char key
    try t.expectEqual(@as(usize, 1), h.entries.items.len); // no failed call stored anything
}

test "hash attributes: num_items live count, item_size width sum, unknown/args fail loud (GAP-hashnumitems)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;
    try ex.hashes.append(f.a(), h);

    const put1 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(100) } };
    const put2 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(2) }, .{ .name = "data", .value = f.num(200) } };
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &put1));
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &put2));

    // the parenless attribute form (Language Reference: Concepts p.623) lands in hashOp with no args.
    try ex.hashOp(.{ .target = "n", .obj = "h", .method = "num_items", .args = &.{} });
    try t.expectEqual(@as(f64, 2), f.pdv.get("n").?.num); // live entry count
    try ex.hashOp(.{ .target = "s", .obj = "h", .method = "item_size", .args = &.{} });
    try t.expectEqual(@as(f64, 16), f.pdv.get("s").?.num); // num key 8 + data 8

    // the count is live — a remove shrinks it.
    const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
    try t.expectEqual(@as(f64, 0), try ex.hashRemove(h, &key1));
    try ex.hashOp(.{ .target = "n2", .obj = "h", .method = "num_items", .args = &.{} });
    try t.expectEqual(@as(f64, 1), f.pdv.get("n2").?.num);
    try t.expect(!f.diags.hasErrors()); // all of the above stays quiet

    // an unknown `.attr` and an attribute-with-arguments both fail LOUD — and now
    // HALT the step (BUG-hashexprdeferredhalt) rather than fabricating an rc.
    try t.expectError(error.ExecError, ex.hashOp(.{ .target = "x", .obj = "h", .method = "bogus_attr", .args = &.{} }));
    try t.expectError(error.ExecError, ex.hashOp(.{ .target = "y", .obj = "h", .method = "num_items", .args = &key1 }));
    try t.expect(f.diags.hasErrors()); // captured diagnostics, not a process abort (D-003)
    // no invented value reached the PDV, so nothing downstream can branch on one.
    try t.expect(f.pdv.get("x") == null);
    try t.expect(f.pdv.get("y") == null);
}

test "unsupported hash methods fail loud AND HALT the step, fabricating no rc; suminc: tag loud (GAP-hashmethods + BUG-hashexprdeferredhalt)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;
    try ex.hashes.append(f.a(), h);

    // Every currently-unsupported method/operation (ref/equals/sum/sumdup/
    // find_prev/has_next/has_prev/do_over — clear/delete/hiter prev are
    // supported now, GAP-hashitermethods): a loud captured ERROR that STOPS THE
    // STEP. BUG-hashexprdeferredhalt supersedes the original "defined non-zero rc"
    // rule here: rc=1 was defined but INVENTED, and `if h.ref() = 1 then …` duly
    // took the branch, wrote its output, and only then surfaced the ERROR. The rc
    // target must stay UNSET — there is no value to branch on because there is no
    // more step (Language Reference: Concepts printed p.174-175, Example Code 8.6).
    const unsupported = [_][]const u8{ "ref", "equals", "sum", "sumdup", "find_prev", "has_next", "has_prev", "do_over" };
    for (unsupported, 0..) |m, i| {
        const tgt = try std.fmt.allocPrint(f.a(), "rc{d}", .{i});
        try t.expectError(error.ExecError, ex.hashOp(.{ .target = tgt, .obj = "h", .method = m, .args = &.{} }));
        try t.expect(f.pdv.get(tgt) == null); // no fabricated rc reached the PDV
    }
    try t.expect(f.diags.hasErrors()); // captured diagnostics, not a process abort (D-003)
    var loud: usize = 0;
    for (f.diags.list.items) |d| {
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "is not supported yet") != null) loud += 1;
    }
    try t.expectEqual(unsupported.len, loud); // exactly one loud ERROR per unsupported call

    // A call on an UNDECLARED object errors AND halts, leaving no rc behind
    // (the ticket's own shape: `if nolib.foo = 1 then put …` must never run the PUT).
    try t.expectError(error.ExecError, ex.hashOp(.{ .target = "rcu", .obj = "nope", .method = "find", .args = &.{} }));
    try t.expect(f.pdv.get("rcu") == null);

    // `declare hash h2(suminc:'cnt')` — the silent no-op fails loud AND halts
    // (AUDIT-errhaltclass): a loud ERROR the step then ignores is still a no-op.
    const before = f.diags.count();
    const suminc_arg = [_]ast.HashArg{.{ .name = "suminc", .value = f.e(.{ .str = "cnt" }) }};
    try t.expectError(error.ExecError, ex.hashDeclare(.{ .name = "h2", .args = &suminc_arg }));
    try t.expectEqual(before + 1, f.diags.count());
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[f.diags.count() - 1].message, "suminc") != null);
    try t.expect(f.diags.list.items[f.diags.count() - 1].severity == .err);
}

test "hash duplicate: 'r' replaces on add, 'e' logs an error, default keeps first (BUG-hashduplicate)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const put111 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(111) } };
    const put999 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(999) } };
    const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};

    // duplicate:'r' — the LAST added record wins.
    const hr = try f.a().create(HashObject);
    hr.* = .{ .name = "hr", .duplicate = .replace };
    try hr.keys.append(f.a(), "k");
    try hr.datas.append(f.a(), "v");
    hr.done = true;
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(hr, &put111));
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(hr, &put999)); // duplicate → replace
    try t.expectEqual(@as(usize, 1), hr.entries.items.len); // still one row
    try t.expectEqual(@as(f64, 0), try ex.hashFind(hr, &key1));
    try t.expectEqual(@as(f64, 999), f.pdv.get("v").?.num); // last wins

    // duplicate:'e' — captured ERROR, first record kept, non-zero rc.
    const he = try f.a().create(HashObject);
    he.* = .{ .name = "he", .duplicate = .err };
    try he.keys.append(f.a(), "k");
    try he.datas.append(f.a(), "v");
    he.done = true;
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(he, &put111));
    try t.expectEqual(@as(f64, 1), try ex.hashAdd(he, &put999)); // duplicate → error rc
    try t.expect(f.diags.hasErrors()); // the documented log ERROR (captured, D-003)
    try t.expectEqual(@as(usize, 1), he.entries.items.len);
    try t.expectEqual(@as(f64, 0), try ex.hashFind(he, &key1));
    try t.expectEqual(@as(f64, 111), f.pdv.get("v").?.num); // first kept
}

test "BUG-hashunknownarg: a misspelled constructor tag fails LOUD; known tags stay quiet" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    // `declare hash h(odered:'a')` — typo of ordered: SAS rejects an undefined
    // argument tag; it must ERROR, never silently leave a default hash — and
    // (AUDIT-errhaltclass) it must HALT, never leave the default hash in place
    // for the rest of the step to use.
    const bad = [_]ast.HashArg{.{ .name = "odered", .value = f.e(.{ .str = "a" }) }};
    try t.expectError(error.ExecError, ex.hashDeclare(.{ .name = "h", .args = &bad }));
    try t.expect(f.diags.hasErrors()); // captured diagnostic, not a process abort (D-003)
    try t.expect(std.mem.indexOf(u8, f.diags.list.items[f.diags.count() - 1].message, "undefined argument tag") != null);

    // Every KNOWN tag is accepted quietly. The list is the component-objects
    // ref's "seven valid hash object argument and value tags" (printed p.30-33)
    // MINUS the two key-summary tags, which have their own unsupported-and-halt
    // arm: dataset, duplicate, hashexp, multidata, ordered here; suminc and
    // keysum below.
    const before = f.diags.count();
    const good = [_]ast.HashArg{
        .{ .name = "dataset", .value = f.e(.{ .str = "src" }) },
        .{ .name = "ordered", .value = f.e(.{ .str = "a" }) },
        .{ .name = "duplicate", .value = f.e(.{ .str = "r" }) },
        .{ .name = "multidata", .value = f.e(.{ .str = "y" }) },
        .{ .name = "hashexp", .value = f.num(8) },
    };
    try ex.hashDeclare(.{ .name = "h2", .args = &good });
    try t.expectEqual(before, f.diags.count()); // no new diagnostics

    // AUDIT-errhaltclass, the KEYSUM half: `keysum:` is one of the seven LEGAL
    // tags and was missing from the whitelist, so it drew the WRONG diagnostic
    // ("undefined argument tag") — a factually false message about a tag the
    // volume defines. It is UNSUPPORTED here (we maintain no key summary), so
    // it must fail as unsupported, and halt, exactly like suminc:.
    const ks = [_]ast.HashArg{.{ .name = "keysum", .value = f.e(.{ .str = "cnt" }) }};
    try t.expectError(error.ExecError, ex.hashDeclare(.{ .name = "h3", .args = &ks }));
    const last = f.diags.list.items[f.diags.count() - 1].message;
    try t.expect(std.mem.indexOf(u8, last, "keysum") != null);
    try t.expect(std.mem.indexOf(u8, last, "undefined argument tag") == null); // not the wrong message
}

test "AUDIT-errhaltclass: dataset: naming no table HALTS the step — no empty hash, no fabricated missing, no output row" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    // `declare hash bad(dataset:'no_such_table'); defineKey('k'); defineData('v');
    //  defineDone(); k=1; rc=bad.find(); flag='WROTE'; output;`
    // Pre-fix: the ERROR was reported, hashLoadDataset RETURNED, and the step ran
    // to completion against an EMPTY hash — find() missed, v stayed MISSING, and
    // the row was written. On a libname-backed run that data set landed on disk at
    // exit 1 and read back at exit 0. The load path is reached from defineDone.
    const src_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "no_such_table" }) }};
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "v" }) }};
    const noargs: []const ast.HashArg = &.{};
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "k", .value = f.num(1) } },
        .{ .assign = .{ .target = "v", .value = f.num(0) } },
        .{ .hash_decl = .{ .name = "bad", .args = &src_arg } },
        .{ .hash_op = .{ .target = null, .obj = "bad", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "bad", .method = "defineData", .args = &data_arg } },
        .{ .hash_op = .{ .target = null, .obj = "bad", .method = "defineDone", .args = noargs } },
        .{ .hash_op = .{ .target = "rc", .obj = "bad", .method = "find", .args = noargs } },
        .{ .assign = .{ .target = "flag", .value = f.e(.{ .str = "WROTE" }) } },
    };
    var out = Dataset.init(f.a(), "work.out_never");
    try t.expectError(error.ExecError, ex.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "hash dataset no_such_table not found")); // captured (D-003)
    // NO row: run() erroring is what keeps main.zig's `lib.put(name, ds)` — which
    // sits AFTER `try ex.run(…)` — from registering the data set at all.
    try t.expectEqual(@as(usize, 0), out.rowCount());
    // `flag` and `rc` exist as compile-time PDV slots (SAS builds the whole PDV
    // up front, BUG-pdvcompilevars) — what must not exist is a VALUE in them:
    // the step stopped before the find() and before the assignment, so no
    // fabricated rc and no 'WROTE' ever reached a slot.
    if (f.pdv.get("flag")) |fv| try t.expect(fv != .str or fv.str.len == 0 or std.mem.trim(u8, fv.str, " ").len == 0);
    if (f.pdv.get("rc")) |rv| try t.expect(rv == .num and std.math.isNan(rv.num));

    // Control: the SAME construct over a table that EXISTS loads and looks up, and
    // stays quiet — the halt is keyed on the missing table, not on `dataset:`.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var ex2 = f2.exec();
    const ref = f2.newDs("ref");
    _ = try ref.addColumn("k", .num);
    _ = try ref.addColumn("v", .num);
    try ref.appendRow(&.{ .{ .num = 1 }, .{ .num = 100 } });
    try f2.lib.put("ref", ref);
    const ok_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f2.e(.{ .str = "ref" }) }};
    const key2 = [_]ast.HashArg{.{ .name = null, .value = f2.e(.{ .str = "k" }) }};
    const data2 = [_]ast.HashArg{.{ .name = null, .value = f2.e(.{ .str = "v" }) }};
    const prog2 = [_]ast.Stmt{
        .{ .assign = .{ .target = "k", .value = f2.num(1) } },
        .{ .assign = .{ .target = "v", .value = f2.num(0) } },
        .{ .hash_decl = .{ .name = "ok", .args = &ok_arg } },
        .{ .hash_op = .{ .target = null, .obj = "ok", .method = "defineKey", .args = &key2 } },
        .{ .hash_op = .{ .target = null, .obj = "ok", .method = "defineData", .args = &data2 } },
        .{ .hash_op = .{ .target = null, .obj = "ok", .method = "defineDone", .args = noargs } },
        .{ .hash_op = .{ .target = "rc", .obj = "ok", .method = "find", .args = noargs } },
    };
    var out2 = Dataset.init(f2.a(), "work.ok");
    try ex2.run(&prog2, &out2);
    try t.expect(!f2.diags.hasErrors());
    // Read the OUTPUT row, not the PDV: the PDV is reset at the iteration
    // boundary, so a post-run pdv.get is missing even on the happy path.
    try t.expectEqual(@as(usize, 1), out2.rowCount());
    try t.expectEqual(@as(f64, 0), out2.row(0)[out2.indexOf("rc").?].num); // hit
    try t.expectEqual(@as(f64, 100), out2.row(0)[out2.indexOf("v").?].num); // the real value
}

test "BUG-symputxsymtab: a symbol-table argument outside G/L/F fails LOUD, never silently reverts to the default" {
    // SAS 9.4 Macro Language: Reference, Fifth Edition, printed p.307 defines
    // exactly three values for CALL SYMPUTX's third argument. It was PARSED AND
    // DISCARDED with no diagnostic at all — the silent no-op D-002 forbids
    // outright, and the reason `call symputx('gv','val','G')` inside a macro left
    // `&gv` unresolved at exit 0.
    //
    // The invalid-value arm is asserted HERE rather than in a corpus fixture
    // because CLAUDE.md wants fail-loud checked on the CAPTURED reporter; the
    // three VALID values are value-observable and live in the fixture
    // (macroedge_symputx_symtab).
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    // `call symputx('a', 'v', 'Q');` — HALTS the step (AUDIT-errhaltclass): a
    // wrongly scoped macro variable is exactly as dangerous as no variable, so
    // the statements after it must not run on the wrong assumption.
    const bad = [_]ast.Expr{ .{ .str = "a" }, .{ .str = "v" }, .{ .str = "Q" } };
    const prog = [_]ast.Stmt{
        .{ .call_ = .{ .name = "symputx", .args = &bad } },
        .{ .assign = .{ .target = "after", .value = f.e(.{ .str = "RAN" }) } },
    };
    var out = Dataset.init(f.a(), "work.never");
    try t.expectError(error.ExecError, ex.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "must be 'G', 'L' or 'F'")); // captured (D-003)
    try t.expectEqual(@as(usize, 0), out.rowCount());

    // A NUMERIC third argument is the same class — there is no numeric reading of
    // a symbol-table name to fall back on.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var ex2 = f2.exec();
    const numtab = [_]ast.Expr{ .{ .str = "a" }, .{ .str = "v" }, .{ .num = 1 } };
    const prog2 = [_]ast.Stmt{.{ .call_ = .{ .name = "symputx", .args = &numtab } }};
    var out2 = Dataset.init(f2.a(), "work.never2");
    try t.expectError(error.ExecError, ex2.run(&prog2, &out2));
    try t.expect(diagsHave(&f2.diags, "must be 'G', 'L' or 'F'"));

    // CALL SYMPUT has only TWO arguments (printed p.301) — a third one was also
    // dropped in silence, and it is a real user mistake (SYMPUTX was meant).
    var f3 = fixture();
    defer f3.deinit();
    f3.prime();
    var ex3 = f3.exec();
    const three = [_]ast.Expr{ .{ .str = "a" }, .{ .str = "v" }, .{ .str = "G" } };
    const prog3 = [_]ast.Stmt{.{ .call_ = .{ .name = "symput", .args = &three } }};
    var out3 = Dataset.init(f3.a(), "work.never3");
    try t.expectError(error.ExecError, ex3.run(&prog3, &out3));
    try t.expect(diagsHave(&f3.diags, "belongs to CALL SYMPUTX"));

    // Control: the three LEGAL values (and lowercase, and blank-padded) are
    // accepted quietly. No macro Session is live in a unit test, so `symputLocal`
    // reports false for every one of them and the value lands in the flat
    // exec->macro store — which is all this arm needs to prove: the argument is
    // READ and validated, not discarded.
    for ([_][]const u8{ "G", "l", " F " }) |tabv| {
        var fo = fixture();
        defer fo.deinit();
        fo.prime();
        var exo = fo.exec();
        const ok = [_]ast.Expr{ .{ .str = "a" }, .{ .str = "v" }, .{ .str = tabv } };
        const progo = [_]ast.Stmt{.{ .call_ = .{ .name = "symputx", .args = &ok } }};
        var outo = Dataset.init(fo.a(), "work.ok");
        try exo.run(&progo, &outo);
        try t.expect(!fo.diags.hasErrors());
        try t.expectEqualStrings("v", fo.lib.macro_vars.get("a").?);
    }
}

test "BUG-hiterbadhash: a hiter bound to an undeclared/typo'd hash fails LOUD — declare-time and first-use agree" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    // Repro A (Language Reference: Concepts p.624 Note: the hash must be declared BEFORE the
    // iterator): `declare hiter it('hh')` with only `h` declared — one typo
    // used to bind nothing; every first()/next() then returned rc=1 with NO
    // diagnostic, so the canonical do-while walk emitted an EMPTY dataset at
    // exit 0. Now a captured ERROR at declare (D-003, no aborting process).
    const noargs: []const ast.HashArg = &.{};
    try ex.hashDeclare(.{ .name = "h", .args = noargs });
    const typo = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "hh" }) }};
    try t.expectError(error.ExecError, ex.hashDeclare(.{ .name = "it", .args = &typo }));
    try t.expect(diagsHave(&f.diags, "hash object 'hh' is not declared"));

    // Repro B (p.624: the name MUST be quoted): `declare hiter it2(h)` — the
    // bare h evaluates numeric and used to be dropped on the floor.
    const unq = [_]ast.HashArg{.{ .name = null, .value = f.vbl("h") }};
    try t.expectError(error.ExecError, ex.hashDeclare(.{ .name = "it2", .args = &unq }));
    try t.expect(diagsHave(&f.diags, "must be a quoted string"));

    // First-use fallback: `declare hiter it3;` (no arg — indistinguishable
    // from `declare hash` at the AST level) stays silent at declare, but the
    // FIRST move on the unbound iterator fails loud instead of rc=1-quiet.
    try ex.hashDeclare(.{ .name = "it3", .args = noargs });
    const it3 = ex.findHash("it3").?;
    try t.expectError(error.ExecError, ex.hashIterMove(it3, .first));
    try t.expect(diagsHave(&f.diags, "not bound to a hash object"));

    // Bound, then the hash DELETE'd under it — first move fails loud too.
    const good = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "h" }) }};
    try ex.hashDeclare(.{ .name = "it4", .args = &good });
    try ex.hashOp(.{ .target = null, .obj = "h", .method = "delete", .args = noargs });
    const it4 = ex.findHash("it4").?;
    try t.expectError(error.ExecError, ex.hashIterMove(it4, .first));
    try t.expect(diagsHave(&f.diags, "hash object 'h' is not declared"));

    // A correctly bound iterator over an EMPTY hash keeps the rc contract:
    // first() returns 1 with NO diagnostic (hash_ch24_bounds pins this).
    const before = f.diags.count();
    try ex.hashDeclare(.{ .name = "h5", .args = noargs });
    const good5 = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "h5" }) }};
    try ex.hashDeclare(.{ .name = "it5", .args = &good5 });
    const it5 = ex.findHash("it5").?;
    try t.expectEqual(@as(f64, 1), try ex.hashIterMove(it5, .first));
    try t.expectEqual(before, f.diags.count()); // silence preserved
}

test "BUG-hashremoveiter: REMOVE while a bound iterator points at the key errors per Language Reference: Concepts p.621 — hash untouched, walk visits every record" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const noargs: []const ast.HashArg = &.{};
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_args = [_]ast.HashArg{
        .{ .name = null, .value = f.e(.{ .str = "k" }) },
        .{ .name = null, .value = f.e(.{ .str = "d" }) },
    };
    const iter_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "h" }) }};
    const A = f.a();
    var stmts: std.ArrayList(ast.Stmt) = .empty;
    try stmts.append(A, .{ .hash_decl = .{ .name = "h", .args = noargs } });
    try stmts.append(A, .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } });
    try stmts.append(A, .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_args } });
    try stmts.append(A, .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = noargs } });
    var i: usize = 1;
    while (i <= 5) : (i += 1) {
        const xf: f64 = @floatFromInt(i);
        try stmts.append(A, .{ .assign = .{ .target = "k", .value = f.num(xf) } });
        try stmts.append(A, .{ .assign = .{ .target = "d", .value = f.num(xf * 10) } });
        try stmts.append(A, .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = noargs } });
    }
    try stmts.append(A, .{ .hash_decl = .{ .name = "it", .args = &iter_arg } });
    try stmts.append(A, .{ .assign = .{ .target = "visited", .value = f.num(0) } });
    try stmts.append(A, .{ .hash_op = .{ .target = "rc", .obj = "it", .method = "first", .args = noargs } });
    // walk-and-delete: p.621 blocks every remove (iterator positioned), so all
    // five records are visited and the hash keeps all five. Pre-fix the cursor
    // corrupted: visited k=1,3,5 and left 2,4 behind at exit 0. (Results read
    // from the OUTPUT rows — the PDV is wiped at end of step.)
    const body = [_]ast.Stmt{
        .{ .hash_op = .{ .target = "junk", .obj = "h", .method = "remove", .args = noargs } },
        .{ .assign = .{ .target = "visited", .value = f.bin(.add, f.vbl("visited"), f.vbl("k")) } },
        .{ .output = &.{} },
        .{ .hash_op = .{ .target = "rc", .obj = "it", .method = "next", .args = noargs } },
    };
    try stmts.append(A, .{ .do_ = .{ .header = .{ .while_ = f.bin(.eq, f.vbl("rc"), f.num(0)) }, .body = &body } });
    var out = Dataset.init(A, "work.out");
    try x.run(stmts.items, &out);
    try t.expect(diagsHave(&f.diags, "hash iterator it is positioned on it")); // captured ERROR (D-003)
    try t.expectEqual(@as(usize, 5), out.rowCount()); // every record visited — no skip
    const ki = out.indexOf("k").?;
    const vi = out.indexOf("visited").?;
    var r: usize = 0;
    var expect_k: f64 = 1;
    var expect_v: f64 = 0;
    while (r < 5) : (r += 1) {
        expect_v += expect_k;
        try t.expectEqual(expect_k, out.row(r)[ki].num); // 1,2,3,4,5 in order
        try t.expectEqual(expect_v, out.row(r)[vi].num); // cumulative 1,3,6,10,15
        expect_k += 1;
    }
    try t.expectEqual(@as(usize, 5), x.findHash("h").?.entries.items.len); // nothing removed

    // Control 1 (clean fixture — keeps the control independent of the ERROR
    // the walk above recorded): an iterator walked to EXHAUSTION is no longer
    // positioned — a later remove succeeds.
    var f1 = fixture();
    defer f1.deinit();
    f1.prime();
    var x1 = f1.exec();
    const p1 = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = noargs } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_args } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = noargs } },
        .{ .assign = .{ .target = "k", .value = f1.num(1) } },
        .{ .assign = .{ .target = "d", .value = f1.num(10) } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = noargs } },
        .{ .hash_decl = .{ .name = "it", .args = &iter_arg } },
        .{ .hash_op = .{ .target = "rc", .obj = "it", .method = "first", .args = noargs } },
        .{ .hash_op = .{ .target = "rc", .obj = "it", .method = "next", .args = noargs } }, // exhausted (1 entry)
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "remove", .args = noargs } },
    };
    var out1 = Dataset.init(f1.a(), "work.out1");
    try x1.run(&p1, &out1);
    try t.expect(!f1.diags.hasErrors());
    try t.expectEqual(@as(usize, 0), x1.findHash("h").?.entries.items.len); // removed

    // Control 2: a DECLARED but never-walked iterator is not "pointing to the
    // key" (iter_on=false) — remove is NOT blocked, no diagnostic.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var x2 = f2.exec();
    const p2 = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = noargs } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_args } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = noargs } },
        .{ .assign = .{ .target = "k", .value = f2.num(1) } },
        .{ .assign = .{ .target = "d", .value = f2.num(10) } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = noargs } },
        .{ .hash_decl = .{ .name = "it", .args = &iter_arg } },
        .{ .assign = .{ .target = "k", .value = f2.num(1) } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "remove", .args = noargs } },
    };
    var out3 = Dataset.init(f2.a(), "work.out3");
    try x2.run(&p2, &out3);
    try t.expect(!f2.diags.hasErrors()); // no false positive
    try t.expectEqual(@as(usize, 0), x2.findHash("h").?.entries.items.len); // removed
}

test "BUG-hashdefinenovar: defineKey/defineData naming a variable that exists nowhere fails LOUD at defineDone (Language Reference: Concepts p.613)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // `length v 8; declare hash h(dataset:'ref'); defineKey('k'); defineData('vv')`
    // — the one-character typo. k is legal via the SECOND universe (a ref
    // column, though not a PDV var); vv is in NEITHER. Pre-fix: rc=0, find()
    // reported a HIT restoring nothing, and a phantom vv column materialised.
    const ref = f.newDs("ref");
    _ = try ref.addColumn("k", .num);
    _ = try ref.addColumn("v", .num);
    try ref.appendRow(&.{ .{ .num = 1 }, .{ .num = 100 } });
    try f.lib.put("ref", ref);
    _ = try f.pdv.declare("v", .num); // `length v 8;`
    const ds_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "ref" }) }};
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const typo_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "vv" }) }};
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &ds_arg } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "defineData", .args = &typo_arg } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "defineDone", .args = &.{} } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try t.expectError(error.ExecError, x.run(&prog, &out)); // captured, no abort (D-003)
    try t.expect(diagsHave(&f.diags, "data variable 'vv' is not declared or initialized"));

    // key side, no dataset: source — same rule.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var x2 = f2.exec();
    const bad_key = [_]ast.HashArg{.{ .name = null, .value = f2.e(.{ .str = "nosuchvar" }) }};
    const prog2 = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "defineKey", .args = &bad_key } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "defineDone", .args = &.{} } },
    };
    var out2 = Dataset.init(f2.a(), "work.out2");
    try t.expectError(error.ExecError, x2.run(&prog2, &out2));
    try t.expect(diagsHave(&f2.diags, "key variable 'nosuchvar' is not declared or initialized"));
}

test "NOTE-declarehashtrim: declare hash dataset: trims the computed name, like h.output (BUG-hashoutputnametrim)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const woo = f.newDs("woo");
    _ = try woo.addColumn("x", .num);
    try woo.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("woo", woo);
    // `declare hash h(dataset: 'w' || nm)` with nm $8 = 'oo' — the value
    // arrives blank-padded; untrimmed it missed the EXISTING member
    // ('hash dataset woo       not found', loud but wrong).
    _ = try f.pdv.declare("x", .num);
    const decl_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "woo     " }) }};
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "x" }) }};
    const find_arg = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &decl_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "find", .args = &find_arg } },
    };
    var out = Dataset.init(f.a(), "work.out");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    // Read the OUTPUT row, not the PDV: the PDV is reset at the iteration
    // boundary, so a post-run pdv.get is missing even on the happy path.
    try t.expectEqual(@as(usize, 1), out.rowCount());
    try t.expectEqual(@as(f64, 0), colVal(&out, out.rows.items[0], "rc").num); // found via the trimmed name
    try t.expectEqual(@as(f64, 1), colVal(&out, out.rows.items[0], "x").num);
}

test "BUG-hashoutputnametrim: output(dataset:<expr>) trims the computed name; an invalid member name fails loud" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    try x.hashDeclare(.{ .name = "h", .args = &.{} });
    const obj = x.findHash("h").?;
    // `'w' || nm` with nm $8 holding 'oo' — the value arrives blank-padded.
    // Pre-fix the member was literally 'woo     ' — created at rc=0, unreachable.
    const padded = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "woo     " }) }};
    try t.expectEqual(@as(f64, 0), try x.hashOutput(obj, &padded));
    try t.expect(x.lib.find("woo") != null); // trimmed — reachable
    try t.expect(!f.diags.hasErrors());

    // a name that is not [lib.]member (V7 rules) — loud, rc=1, nothing created.
    const bad = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "9bad" }) }};
    try t.expectEqual(@as(f64, 1), try x.hashOutput(obj, &bad));
    try t.expect(diagsHave(&f.diags, "'9bad' is not a valid SAS data set name"));
    try t.expect(x.lib.find("9bad") == null);
}

test "BUG-hashoutputdsopt: output(dataset:'m(where=…)') applies the options; unknown option loud" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;
    var k: f64 = 1;
    while (k <= 3) : (k += 1) {
        const put = [_]ast.HashArg{ .{ .name = "key", .value = f.num(k) }, .{ .name = "data", .value = f.num(k) }, .{ .name = "data", .value = f.num(k * 10) } };
        try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &put));
    }

    // the filter applies: only k=2,3 land in the output table.
    const out_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "out(where=(k>1))" }) }};
    try t.expectEqual(@as(f64, 0), try ex.hashOutput(h, &out_arg));
    const ds = f.lib.find("out").?;
    try t.expectEqual(@as(usize, 2), ds.rows.items.len);
    try t.expectEqual(@as(f64, 2), ds.rows.items[0][0].num);
    try t.expect(!f.diags.hasErrors());

    // a plain dataset:'x' with no parens still works unchanged.
    const plain = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "plain" }) }};
    try t.expectEqual(@as(f64, 0), try ex.hashOutput(h, &plain));
    try t.expectEqual(@as(usize, 3), f.lib.find("plain").?.rows.items.len);

    // an option the normal path can't apply fails LOUD (non-zero rc, ERROR).
    const badopt = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "bad(pw=secret)" }) }};
    try t.expectEqual(@as(f64, 1), try ex.hashOutput(h, &badopt));
    try t.expect(f.diags.hasErrors()); // captured diagnostic, not a process abort (D-003)
    // NOTE-dsoptdoublereport: EXACTLY ONE diagnostic for the one bad option —
    // io.zig's unknown-option error; the exec-side pre-check that doubled it is
    // gone. (The where= option inside parens must NOT be misread as an option
    // name either: the earlier out(where=(k>1)) call above stayed silent.)
    var pw_errs: usize = 0;
    for (f.diags.list.items) |d| {
        try t.expect(d.severity != .err or std.mem.indexOf(u8, d.message, "pw") != null); // no other ERRORs this test
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "pw") != null) {
            pw_errs += 1;
            try t.expectEqualStrings("dataset option pw= is not supported", d.message);
        }
    }
    try t.expectEqual(@as(usize, 1), pw_errs);
}

test "NOTE-hashemptytype/hashoutputnods: empty hash keeps declared col types; output() without dataset: fails loud" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    // A declared CHAR defineData var survives an EMPTY hash's output as Char
    // (was: first-entry inference defaulted every column to Num with no entries).
    _ = try f.pdv.define("name", .char);
    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "name");
    h.done = true;
    const out_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "empty_out" }) }};
    try t.expectEqual(@as(f64, 0), try ex.hashOutput(h, &out_arg));
    const ds = f.lib.find("empty_out").?;
    try t.expectEqual(@as(usize, 0), ds.rows.items.len);
    try t.expectEqual(pdv_mod.VarType.char, ds.columns.items[0].type);
    try t.expect(!f.diags.hasErrors());

    // output() with NO dataset: tag — loud ERROR + rc=1 (was a silent no-op).
    try t.expectEqual(@as(f64, 1), try ex.hashOutput(h, &.{}));
    try t.expect(f.diags.hasErrors()); // captured diagnostic, not a process abort (D-003)
}

test "hash multidata: add keeps duplicate keys, find/find_next walk all records (BUG-hashmultidata)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h", .multidata = true };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;

    // the ticket repro: (1,10)(1,20)(2,30)(1,40) — every add must succeed
    const adds = [_][2]f64{ .{ 1, 10 }, .{ 1, 20 }, .{ 2, 30 }, .{ 1, 40 } };
    for (adds) |kv| {
        const a = [_]ast.HashArg{ .{ .name = "key", .value = f.num(kv[0]) }, .{ .name = "data", .value = f.num(kv[1]) } };
        try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &a));
    }
    try t.expectEqual(@as(usize, 4), h.entries.items.len); // NOTHING silently dropped

    // find returns the FIRST record of k=1; find_next walks the rest in insertion order
    const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &key1));
    try t.expectEqual(@as(f64, 10), f.pdv.get("v").?.num);
    try t.expectEqual(@as(f64, 0), try ex.hashFindNext(h));
    try t.expectEqual(@as(f64, 20), f.pdv.get("v").?.num);
    try t.expectEqual(@as(f64, 0), try ex.hashFindNext(h));
    try t.expectEqual(@as(f64, 40), f.pdv.get("v").?.num);
    try t.expectEqual(@as(f64, 160038), try ex.hashFindNext(h)); // chain exhausted

    // k=2 holds a single record — find_next ends immediately
    const key2 = [_]ast.HashArg{.{ .name = "key", .value = f.num(2) }};
    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &key2));
    try t.expectEqual(@as(f64, 30), f.pdv.get("v").?.num);
    try t.expectEqual(@as(f64, 160038), try ex.hashFindNext(h));

    // a miss clears the cursor: find_next without a hit is an error, as SAS
    const key9 = [_]ast.HashArg{.{ .name = "key", .value = f.num(9) }};
    try t.expectEqual(@as(f64, 160038), try ex.hashFind(h, &key9));
    try t.expectEqual(@as(f64, 160038), try ex.hashFindNext(h));
}

test "hash multidata remove-all: single pass removes every record, survivors keep order (PERF-hashremovequad)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h", .multidata = true };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;

    // 200 doomed records (k=1) interleaved with 100 survivors (k=2)
    var i: usize = 0;
    while (i < 100) : (i += 1) {
        const x: f64 = @floatFromInt(i);
        const d1 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(1) }, .{ .name = "data", .value = f.num(x) } };
        try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &d1));
        const d2 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(2) }, .{ .name = "data", .value = f.num(x) } };
        try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &d2));
        try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &d1));
    }
    try t.expectEqual(@as(usize, 300), h.entries.items.len);

    // set the find_next cursor on the doomed key — remove must invalidate it
    const key1 = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &key1));

    try t.expectEqual(@as(f64, 0), try ex.hashRemove(h, &key1)); // rc 0: something removed
    try t.expectEqual(@as(usize, 100), h.entries.items.len); // ALL 200 gone, survivors intact
    try t.expectEqual(@as(f64, 160038), try ex.hashFind(h, &key1)); // key fully gone
    try t.expectEqual(@as(f64, 160038), try ex.hashFindNext(h)); // stale cursor cleared
    try t.expectEqual(@as(f64, 160038), try ex.hashRemove(h, &key1)); // rc contract: nothing left

    // survivors kept their insertion order (0..99, all k=2)
    for (h.entries.items, 0..) |e, j| {
        try t.expectEqual(@as(f64, 2), e.keyvals[0].num);
        try t.expectEqual(@as(f64, @floatFromInt(j)), e.datavals[0].num);
    }
}

test "special missings stay distinct in hash keys, valueEq, TupleCtx (BUG-execmissdistinct)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const A = Value.specialMissing('A');
    const U = Value.specialMissing('_');

    // cmpValueOrd: special missings compare/sort by rank, not one NaN bucket
    // (._ < . < .A < … < .Z < every number — Language Reference: Concepts Table 5.1)
    try t.expect(cmpValueOrd(A, Value.missing) != .eq);
    try t.expect(cmpValueOrd(A, A) == .eq);
    try t.expect(cmpValueOrd(U, Value.missing) == .lt); // ._ < .
    try t.expect(cmpValueOrd(Value.missing, A) == .lt); // . < .A
    try t.expect(cmpValueOrd(A, .{ .num = -1 }) == .lt); // any missing < any number
    try t.expect(!valueEq(A, Value.missing));

    // TupleCtx hash/eql agreement: .A and . bucket apart, same-rank keys agree
    const ctx = TupleCtx{};
    const ka = [_]Value{A};
    const km = [_]Value{Value.missing};
    const ka2 = [_]Value{Value.specialMissing('A')};
    try t.expect(!ctx.eql(&ka, &km));
    try t.expect(ctx.hash(&ka) != ctx.hash(&km));
    try t.expect(ctx.eql(&ka, &ka2));
    try t.expectEqual(ctx.hash(&ka), ctx.hash(&ka2)); // equal keys hash equal

    // hash object end-to-end: add .A, then . must NOT match its key
    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;
    const addA = [_]ast.HashArg{ .{ .name = "key", .value = f.num(A.num) }, .{ .name = "data", .value = f.num(1) } };
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &addA));
    const chkM = [_]ast.HashArg{.{ .name = "key", .value = f.num(Value.missing.num) }};
    const chkA = [_]ast.HashArg{.{ .name = "key", .value = f.num(A.num) }};
    try t.expectEqual(@as(f64, 160038), try ex.hashCheck(h, &chkM)); // . ≠ .A → not found
    try t.expectEqual(@as(f64, 0), try ex.hashCheck(h, &chkA)); // .A found
    // . is a DISTINCT key, not a duplicate of .A — both survive (ordered-hash 5-key case)
    const addM = [_]ast.HashArg{ .{ .name = "key", .value = f.num(Value.missing.num) }, .{ .name = "data", .value = f.num(2) } };
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &addM));
    try t.expectEqual(@as(usize, 2), h.entries.items.len);
}

test "hash index: remove keeps order, removed key gone, re-add works (PERF-hashscan)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var ex = f.exec();

    const h = try f.a().create(HashObject);
    h.* = .{ .name = "h" };
    try h.keys.append(f.a(), "k");
    try h.datas.append(f.a(), "v");
    h.done = true;

    // add 10,20,30,40,50 (data = key*10) in order
    var i: usize = 1;
    while (i <= 5) : (i += 1) {
        const kd = [_]ast.HashArg{ .{ .name = "key", .value = f.num(@floatFromInt(i * 10)) }, .{ .name = "data", .value = f.num(@floatFromInt(i * 100)) } };
        try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &kd));
    }
    try t.expectEqual(@as(usize, 5), h.entries.items.len);

    // remove the middle key (30)
    const rm30 = [_]ast.HashArg{.{ .name = "key", .value = f.num(30) }};
    try t.expectEqual(@as(f64, 0), try ex.hashRemove(h, &rm30));
    try t.expectEqual(@as(f64, 160038), try ex.hashRemove(h, &rm30)); // already gone

    // insertion order preserved in the ordered store: 10,20,40,50
    const want = [_]f64{ 10, 20, 40, 50 };
    try t.expectEqual(@as(usize, 4), h.entries.items.len);
    for (h.entries.items, 0..) |e, j| try t.expectEqual(want[j], e.keyvals[0].num);

    // index still coherent after the reindex: find surviving keys, miss the removed one
    const find30 = [_]ast.HashArg{.{ .name = "key", .value = f.num(30) }};
    const find40 = [_]ast.HashArg{.{ .name = "key", .value = f.num(40) }};
    try t.expectEqual(@as(f64, 160038), try ex.hashFind(h, &find30)); // removed → not found
    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &find40)); // survivor still found
    try t.expectEqual(@as(f64, 400), f.pdv.get("v").?.num);

    // re-adding the removed key succeeds and lands at the end (append-only order)
    const readd30 = [_]ast.HashArg{ .{ .name = "key", .value = f.num(30) }, .{ .name = "data", .value = f.num(303) } };
    try t.expectEqual(@as(f64, 0), try ex.hashAdd(h, &readd30));
    try t.expectEqual(@as(f64, 1), try ex.hashAdd(h, &readd30)); // now a dup
    try t.expectEqual(@as(f64, 30), h.entries.items[4].keyvals[0].num);
    try t.expectEqual(@as(f64, 0), try ex.hashFind(h, &find30));
    try t.expectEqual(@as(f64, 303), f.pdv.get("v").?.num);
}

test "hash object persists across DATA-step iterations (BUG-hashpersist)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "k", .type = .num }};
    const lines = [_][]const u8{ "1", "2", "3" };
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "kk" }) }};
    const data_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "v" }) }};
    const add_args = [_]ast.HashArg{
        .{ .name = "key", .value = f.vbl("k") },
        .{ .name = "data", .value = f.bin(.mul, f.vbl("k"), f.num(10)) },
    };
    const find_args = [_]ast.HashArg{.{ .name = "key", .value = f.num(1) }};
    // p.613 (BUG-hashdefinenovar): kk/v must exist outside the hash — model the
    // `length kk v 8;` a legal program carries (k comes from the INPUT).
    _ = try f.pdv.declare("kk", .num);
    _ = try f.pdv.declare("v", .num);
    const prog = [_]ast.Stmt{
        .{ .input = &items },
        .{ .datalines = &lines },
        // declare/define run every iteration (no `if _n_=1` guard)
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = &add_args } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "find", .args = &find_args } },
    };

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    // key 1 → data 10 was added on iteration 1; iterations 2 & 3 must still find it.
    const vi = out.indexOf("v").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    try t.expectEqual(@as(f64, 10), out.row(0)[vi].num);
    try t.expectEqual(@as(f64, 10), out.row(1)[vi].num); // persisted, not re-declared
    try t.expectEqual(@as(f64, 10), out.row(2)[vi].num);
}

test "BUG-hashoutputkeys-crash: a data: tag-count mismatch fails loud instead of crashing .output()" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // defineData names TWO vars but add() gives ONE data: tag — the repro that
    // left a short datavals and crashed .output() reading an uninitialized cell.
    // (k/v declared up front — p.613 requires them outside the hash.)
    _ = try f.pdv.declare("k", .num);
    _ = try f.pdv.declare("v", .num);
    const key_def = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_def = [_]ast.HashArg{ .{ .name = null, .value = f.e(.{ .str = "k" }) }, .{ .name = null, .value = f.e(.{ .str = "v" }) } };
    const bad_add = [_]ast.HashArg{ .{ .name = "key", .value = f.num(5) }, .{ .name = "data", .value = f.e(.{ .str = "e" }) } };
    const out_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "byd" }) }};
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_def } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_def } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = &bad_add } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "output", .args = &out_arg } },
    };

    var out = Dataset.init(f.a(), "out");
    x.run(&prog, &out) catch {}; // step aborts loud; reaching here (no panic) is half the proof
    try t.expect(f.diags.hasErrors());
    var found = false;
    for (f.diags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "must match the number of data variables") != null) {
            found = true;
        };
    try t.expect(found);
}

test "NOTE-hashofhash: a hash-valued data item (nested hash) fails loud instead of storing silent missing (tick164)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // `inner = _new_ hash();` desugars to the second hash_decl below — it
    // registers the object but never a PDV var, so defineData("inner") + add()
    // used to store a SILENT numeric missing (exit 0, no diagnostic).
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "inner" }) }};
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .hash_decl = .{ .name = "inner", .args = &.{} } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
        .{ .assign = .{ .target = "k", .value = f.num(1) } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = &.{} } },
    };

    var out = Dataset.init(f.a(), "out");
    x.run(&prog, &out) catch {}; // step aborts loud — reaching here is half the proof
    var found = false;
    for (f.diags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "hash-valued data items (nested hash) are not supported") != null) {
            found = true;
        };
    try t.expect(found);
}

// The guard above used to live inside collectArgs' `out.items.len == 0` arm,
// so ONLY the implicit `h.add()` spelling reached it. These two pin the two
// paths that walked past it, and neither can be pinned by the corpus fixture:
// a `.sas` file may hold exactly one error (BUG-errhalt), and each of these
// two conditions is caught by a DIFFERENT one of the two guard sites, so each
// stays green when the other site is reverted.
test "BUG-hashofhashexplicit: the EXPLICIT key:/data: spelling reaches the nested-hash guard (collectArgs backstop)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // No defineDone — so the define-time guard never runs and collectArgs is
    // the only thing standing between an explicit `data:` tag and a silently
    // stored missing. Pre-fix this returned rc 0 and appended an entry.
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "inner" }) }};
    const explicit = [_]ast.HashArg{
        .{ .name = "key", .value = f.num(1) },
        .{ .name = "data", .value = f.e(.{ .variable = "inner" }) },
    };
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .hash_decl = .{ .name = "inner", .args = &.{} } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_arg } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = &explicit } },
    };

    var out = Dataset.init(f.a(), "out");
    x.run(&prog, &out) catch {};
    var found = false;
    for (f.diags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "hash-valued data items (nested hash) are not supported") != null) {
            found = true;
        };
    try t.expect(found);
    // The DIAGNOSTIC IS HALF THE ASSERTION. What made this the worst class is
    // the fabricated value, so pin that nothing was stored.
    try t.expectEqual(@as(usize, 0), x.findHash("h").?.entries.items.len);
}

test "BUG-hashofhashexplicit: the dataset: bulk load reaches the nested-hash guard (it never calls collectArgs)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // `declare hash h(dataset:'ref'); defineData('inner')` — no add() anywhere,
    // so no collectArgs call exists to catch this. Pre-fix, defineDone loaded
    // the row with `inner` fabricated as missing (there is no such column) and
    // a later find() reported a HIT handing back `inner=.` at exit 0.
    const ref = f.newDs("ref");
    _ = try ref.addColumn("k", .num);
    try ref.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("ref", ref);
    _ = try f.pdv.declare("k", .num);
    const ds_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "ref" }) }};
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "inner" }) }};
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "inner", .args = &.{} } },
        .{ .hash_decl = .{ .name = "h", .args = &ds_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
    };

    var out = Dataset.init(f.a(), "out");
    x.run(&prog, &out) catch {};
    var found = false;
    for (f.diags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "hash-valued data items (nested hash) are not supported") != null) {
            found = true;
        };
    try t.expect(found);
    try t.expectEqual(@as(usize, 0), x.findHash("h").?.entries.items.len); // the row must NOT have loaded
}

// BUG-declaredobjnamevalue. The corpus fixture (obj_name_as_value.sas) pins the
// GENERAL shape `x = inner + 1;`, and a `.sas` file may hold exactly one error
// (BUG-errhalt), so the two remaining entry classes live here. Each is caught by
// a DIFFERENT site, so neither can stand in for the other:
//   - the `data:` slot — the symptom that surfaced the bug — reaches the guard
//     via eval's `.variable` arm, but ONLY once the nested-hash gap guard above
//     it has declined (see collectArgs: `vars` is clean here, because the
//     defineData'd name is an ordinary variable and the OBJECT is merely the
//     supplied value; that is what separates this rc-1 user error from the rc-2
//     documented-nested-hash gap);
//   - a PUT item is not an `ast.Expr` at all and never reaches eval.
test "BUG-declaredobjnamevalue: an object supplied as a data: VALUE errors instead of storing a fabricated missing" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // defineData's name is the ORDINARY variable `v`, so the nested-hash gap
    // guard has nothing to say; `data: inner` is an object reference standing
    // where a scalar value belongs. Pre-fix it evaluated to numeric missing and
    // the add SUCCEEDED at rc 0, destroying the distinction between "stored a
    // hash object" and "stored a missing".
    _ = try f.pdv.declare("k", .num);
    _ = try f.pdv.declare("v", .num);
    const key_def = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
    const data_def = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "v" }) }};
    const explicit = [_]ast.HashArg{
        .{ .name = "key", .value = f.num(1) },
        .{ .name = "data", .value = f.e(.{ .variable = "inner" }) },
    };
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .hash_decl = .{ .name = "inner", .args = &.{} } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_def } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_def } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = &explicit } },
    };

    var out = Dataset.init(f.a(), "out");
    x.run(&prog, &out) catch {}; // step aborts loud — reaching here is half the proof
    var found = false;
    for (f.diags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "Object inner cannot be used as a value") != null) {
            found = true;
        };
    try t.expect(found);
    // THE DIAGNOSTIC IS HALF THE ASSERTION — the fabricated value is what made
    // this the worst class, so pin that nothing was stored.
    try t.expectEqual(@as(usize, 0), x.findHash("h").?.entries.items.len);
    // and that the rc-2 nested-hash GAP was not reclassified as this rc-1 user
    // error: with `vars` clean, that guard must stay silent.
    for (f.diags.list.items) |d|
        try t.expect(std.mem.indexOf(u8, d.message, "nested hash") == null);
}

test "BUG-declaredobjnamevalue: `put h;` errors instead of rendering a fabricated missing (PUT bypasses eval)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // A PUT item reads the PDV directly, so this never routes through eval's
    // `.variable` arm — pre-fix `put h; put h=;` printed ". h=." at rc 0.
    const items = [_]ast.PutItem{
        .{ .variable = .{ .name = "h" } },
        .{ .named = .{ .name = "h" } },
    };
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &.{} } },
        .{ .put = &items },
    };

    var out = Dataset.init(f.a(), "out");
    x.run(&prog, &out) catch {};
    var found = false;
    for (f.diags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "Object h cannot be used as a value") != null) {
            found = true;
        };
    try t.expect(found);
    // The VALUE again: pre-fix the log held ". h=." — nothing may reach it now.
    try t.expectEqualStrings("", x.log.items);
}

test "_N_ counts iterations and stays out of the output (BUG-hashpersist)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const items = [_]ast.InputItem{.{ .name = "v", .type = .num }};
    const lines = [_][]const u8{ "10", "20", "30" };
    const prog = [_]ast.Stmt{
        .{ .input = &items },
        .{ .datalines = &lines },
        .{ .assign = .{ .target = "n", .value = f.vbl("_n_") } }, // n = _N_
    };

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    const ni = out.indexOf("n").?;
    try t.expectEqual(@as(usize, 3), out.rowCount());
    try t.expectEqual(@as(f64, 1), out.row(0)[ni].num);
    try t.expectEqual(@as(f64, 2), out.row(1)[ni].num);
    try t.expectEqual(@as(f64, 3), out.row(2)[ni].num);
    try t.expect(out.indexOf("_n_") == null); // automatic, not written out
}

test "PDV vars exist at COMPILE time: dead-branch assign + bare FORMAT reach the output (BUG-pdvcompilevars)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data out; x='2023-05-01'; if 0 then ev2=1; if 0 then s2=cats('a');
    //           format ev3 8.; run;   — the EPOCH-derivation shape (full dates →
    // the partial-date branches never run, yet those columns must still exist).
    const dead_num = ast.Stmt{ .assign = .{ .target = "ev2", .value = f.num(1) } };
    const cats_args = [_]ast.Expr{.{ .str = "a" }};
    const dead_char = ast.Stmt{ .assign = .{ .target = "s2", .value = f.e(.{ .call = .{ .name = "cats", .args = &cats_args } }) } };
    const fmt_items = [_]ast.FormatItem{.{ .name = "ev3", .fmt = "8." }};
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "x", .value = f.e(.{ .str = "2023-05-01" }) } },
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &dead_num, .else_branch = null } },
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &dead_char, .else_branch = null } },
        .{ .format = &fmt_items },
    };

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    // every named var is a column, with the SAS type: executed x → char (real
    // write), dead ev2 → num guess, dead s2 → char (cats), format-only ev3 → num
    try t.expectEqual(@as(usize, 1), out.rowCount());
    try t.expect(out.columns.items[out.indexOf("x").?].type == .char);
    try t.expect(out.columns.items[out.indexOf("ev2").?].type == .num);
    try t.expect(out.columns.items[out.indexOf("s2").?].type == .char);
    try t.expect(out.columns.items[out.indexOf("ev3").?].type == .num);
    // the dead-branch cells are missing-of-type
    try t.expect(out.row(0)[out.indexOf("ev2").?].isMissing());
    try t.expectEqualStrings("2023-05-01", out.row(0)[out.indexOf("x").?].str);
}

test "DELETE drops the current obs; STOP ends the DATA step (CTLSTMT)" {
    const items = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    const lines = [_][]const u8{ "1", "2", "3", "4", "5" };

    // DELETE: `if x=3 then delete;` → obs 3 dropped, loop continues → 1,2,4,5
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const del: ast.Stmt = .delete;
        const prog = [_]ast.Stmt{
            .{ .input = &items },
            .{ .datalines = &lines },
            .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("x"), f.num(3)), .then_branch = &del, .else_branch = null } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expectEqual(@as(usize, 4), out.rowCount());
        try t.expectEqual(@as(f64, 1), out.row(0)[0].num);
        try t.expectEqual(@as(f64, 4), out.row(2)[0].num);
        try t.expectEqual(@as(f64, 5), out.row(3)[0].num);
    }

    // STOP: `if x=3 then stop;` → step ends at obs 3, only 1,2 output
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const stp: ast.Stmt = .stop;
        const prog = [_]ast.Stmt{
            .{ .input = &items },
            .{ .datalines = &lines },
            .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("x"), f.num(3)), .then_branch = &stp, .else_branch = null } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expectEqual(@as(usize, 2), out.rowCount());
        try t.expectEqual(@as(f64, 1), out.row(0)[0].num);
        try t.expectEqual(@as(f64, 2), out.row(1)[0].num);
    }
}

test "abort: RETURN n sets the session rc + poisons later steps; plain only ends the step (BUG-abortreturncode)" {
    // ABORT RETURN 8: step ends now (0 obs), _ERROR_=1, session rc handed to
    // main via g_abort_rc; the ERROR diagnostic is the session-halt poison
    // (captured reporter, D-003 — no spawned process exit).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        defer g_abort_rc = null; // don't leak into sibling tests
        const prog = [_]ast.Stmt{.{ .abort = .{ .n = 8 } }};
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expectEqual(@as(?u8, 8), g_abort_rc);
        try t.expect(f.diags.hasStepErrors()); // poisons every later step
        try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
        try t.expectEqual(@as(usize, 0), out.rowCount()); // current obs not output
    }
    // plain ABORT: ends the step, _ERROR_=1, no session rc, no poison.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        g_abort_rc = null;
        const prog = [_]ast.Stmt{.{ .abort = .plain }};
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expectEqual(@as(?u8, null), g_abort_rc);
        try t.expect(!f.diags.hasStepErrors());
        try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
    }
}

test "array write: out-of-range subscript is a SAS ERROR that halts the step (BUG-arrwriteoor)" {
    // OOB write: ERROR (captured reporter, no spawned abort), _ERROR_=1, ExecError
    // aborts the step — the statement after the bad write never runs, no obs out.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "x1", "x2", "x3" };
        const prog = [_]ast.Stmt{
            .{ .array_assign = .{ .array = .{ .name = "a", .elements = elems, .index = f.num(5), .line = 7 }, .value = f.num(9) } },
            .{ .assign = .{ .target = "after", .value = f.num(2) } }, // past the halt: must never run
        };
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "Array subscript 5 out of range for a") != null) {
            found = true;
            // NOTE-arrayoorlineno: the node's source line is reported, not a hard-coded 0
            try t.expectEqual(@as(usize, 7), d.line);
            try t.expect(std.mem.indexOf(u8, d.message, "at line 7 column 0.") != null);
        };
        try t.expect(found); // same message as the read path (eval.zig subscriptOor)
        try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
        const after = f.pdv.get("after");
        try t.expect(after == null or after.?.num != 2); // step stopped AT the bad write
        try t.expectEqual(@as(usize, 0), out.rowCount()); // current obs not output
    }
    // a MISSING (.) subscript is out of range too — the write fails loud, not a
    // silent no-op (BUG-arraysubmissing). NaN slips past the `<`/`>` span check,
    // so it must be caught explicitly; same halt/message as any OOR write.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "x1", "x2", "x3" };
        const prog = [_]ast.Stmt{
            .{ .array_assign = .{ .array = .{ .name = "a", .elements = elems, .index = f.e(.{ .num = std.math.nan(f64) }), .line = 4 }, .value = f.num(99) } },
            .{ .assign = .{ .target = "after", .value = f.num(2) } }, // past the halt: must never run
        };
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "out of range for a") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
        const after = f.pdv.get("after");
        try t.expect(after == null or after.?.num != 2); // step stopped AT the bad write
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    // in-range writes are unchanged: value lands, no diagnostic, step completes.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "x1", "x2", "x3" };
        const prog = [_]ast.Stmt{
            .{ .array_assign = .{ .array = .{ .name = "a", .elements = elems, .index = f.num(2) }, .value = f.num(9) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 1), out.rowCount());
        try t.expectEqual(@as(f64, 9), out.row(0)[out.indexOf("x2").?].num);
    }
}

test "array multidim write: per-dimension OOR subscript fails LOUD, valid folds row-major (BUG-arraymultidimoor)" {
    // The parser emits a `__dimchk` index for a multi-dim ref (eval.zig resolves
    // it): each subscript is checked against ITS dimension's bounds BEFORE the
    // row-major fold. `__dimchk(name, line, {idx,lo,size}…)` — build it here the
    // way parser_expr.arraySubscript does, then drive the write path.
    const mkDimchk = struct {
        // dims: list of {idx_expr, lo, size}; returns the __dimchk index expr.
        fn f(fx: *Fixture, name: []const u8, line: f64, triples: []const struct { idx: *const ast.Expr, lo: f64, size: f64 }) *const ast.Expr {
            const args = fx.a().alloc(ast.Expr, 2 + 3 * triples.len) catch unreachable;
            args[0] = .{ .str = name };
            args[1] = .{ .num = line };
            for (triples, 0..) |tr, m| {
                args[2 + m * 3] = tr.idx.*;
                args[2 + m * 3 + 1] = .{ .num = tr.lo };
                args[2 + m * 3 + 2] = .{ .num = tr.size };
            }
            return fx.e(.{ .call = .{ .name = "__dimchk", .args = args } });
        }
    }.f;
    const elems: []const []const u8 = &.{ "a1", "a2", "a3", "a4" }; // array a{2,2}

    // WRITE a{1,3}=9 — col 3 doesn't exist; the raw fold would land in a valid
    // flat slot (a3) and corrupt it silently. Per-dim check fails loud + halts.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const idx = mkDimchk(&f, "a", 7, &.{ .{ .idx = f.num(1), .lo = 1, .size = 2 }, .{ .idx = f.num(3), .lo = 1, .size = 2 } });
        const prog = [_]ast.Stmt{
            .{ .array_assign = .{ .array = .{ .name = "a", .elements = elems, .index = idx, .line = 7 }, .value = f.num(9) } },
            .{ .assign = .{ .target = "after", .value = f.num(2) } }, // past the halt: must never run
        };
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "out of range for a") != null) {
            found = true;
        };
        try t.expect(found); // same message as the flat-index guard (BUG-arrayoorerror)
        try t.expectEqual(@as(f64, 1), f.pdv.get("_error_").?.num);
        const after = f.pdv.get("after");
        try t.expect(after == null or after.?.num != 2); // step stopped AT the bad write
    }

    // VALID a{2,1}=9 — row 2, col 1 folds row-major to flat 3 (a3), NOT a2/a4.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const idx = mkDimchk(&f, "a", 3, &.{ .{ .idx = f.num(2), .lo = 1, .size = 2 }, .{ .idx = f.num(1), .lo = 1, .size = 2 } });
        const prog = [_]ast.Stmt{
            .{ .array_assign = .{ .array = .{ .name = "a", .elements = elems, .index = idx }, .value = f.num(9) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(f64, 9), out.row(0)[out.indexOf("a3").?].num); // landed in a3
    }
}

test "array decl validation: excess inits, char init for numeric array, bare array name — fail LOUD (BUG-arrayinitvalidate)" {
    // F1: 3 initial values for 2 elements — SAS ERROR; the excess used to be
    // silently dropped. Compile-time: the gate halts the step, no obs out.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "a1", "a2" };
        const inits = [_]*const ast.Expr{ f.num(1), f.num(2), f.num(3) };
        const prog = [_]ast.Stmt{
            .{ .array = .{ .name = "a", .elements = elems, .inits = &inits } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out); // gate, not a propagated error — like a bad label
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "exceeds the number of array elements") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.rowCount()); // step never ran
    }
    // F2: a CHARACTER constant initializing a NUMERIC array element — SAS ERROR;
    // it used to be stored as a char, corrupting the element's type.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "n1", "n2" };
        const inits = [_]*const ast.Expr{ f.e(.{ .str = "a" }), f.e(.{ .str = "b" }) };
        const prog = [_]ast.Stmt{
            .{ .array = .{ .name = "n", .elements = elems, .inits = &inits } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "not a valid initial value for the numeric array n") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    // F3: a bare array NAME in a scalar expression (`s = a + 1`) — SAS ERROR
    // ("array subscript required"); it used to fabricate a phantom uninitialized
    // scalar and compute a wrong (missing) result.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "x1", "x2", "x3" };
        const prog = [_]ast.Stmt{
            .{ .array = .{ .name = "a", .elements = elems, .inits = &.{} } },
            .{ .assign = .{ .target = "s", .value = f.bin(.add, f.vbl("a"), f.num(1)) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "used without a subscript") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    // The VALID shapes stay byte-identical: exact-count inits, FEWER inits than
    // elements (rest default to missing — legal in SAS), a char literal into a
    // `$` array, subscripted access, and an array name inside an a{i} read.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const ea: []const []const u8 = &.{ "x1", "x2", "x3" };
        const eb: []const []const u8 = &.{ "y1", "y2", "y3" };
        const ec: []const []const u8 = &.{ "c1", "c2" };
        const ia = [_]*const ast.Expr{ f.num(1), f.num(2), f.num(3) };
        const ib = [_]*const ast.Expr{ f.num(1), f.num(2) }; // fewer — legal
        const ic = [_]*const ast.Expr{ f.e(.{ .str = "x" }), f.e(.{ .str = "y" }) };
        const prog = [_]ast.Stmt{
            .{ .array = .{ .name = "a", .elements = ea, .inits = &ia } },
            .{ .array = .{ .name = "b", .elements = eb, .inits = &ib } },
            .{ .array = .{ .name = "c", .elements = ec, .inits = &ic, .type = .char } },
            .{ .array_assign = .{ .array = .{ .name = "a", .elements = ea, .index = f.num(2) }, .value = f.num(9) } },
            // bare array-name CHECK must not fire on element names or array_ref
            .{ .assign = .{ .target = "s", .value = f.bin(.add, f.e(.{ .array_ref = .{ .name = "a", .elements = ea, .index = f.num(1) } }), f.vbl("y1")) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 1), out.rowCount());
        try t.expectEqual(@as(f64, 9), out.row(0)[out.indexOf("x2").?].num); // subscripted write landed
        try t.expectEqual(@as(f64, 2), out.row(0)[out.indexOf("s").?].num); // a{1}+y1 = 1+1
        try t.expect(out.row(0)[out.indexOf("y3").?].isMissing()); // fewer inits → missing, no error
        try t.expectEqualStrings("x", out.row(0)[out.indexOf("c1").?].str); // char array char init
    }
}

test "array with a mixed num/char member list fails LOUD at bind time (BUG-mixedtypearray)" {
    // A char member (`x2='ab'` types it char) in a NUMERIC array — SAS 9.4
    // compile-time ERROR. It used to be silently accepted: x2 kept its char
    // type and `mix{2}=2;` silently converted. Gate, not a propagated error.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const elems: []const []const u8 = &.{ "x1", "x2" };
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "x1", .value = f.num(1) } },
            .{ .assign = .{ .target = "x2", .value = f.e(.{ .str = "ab" }) } },
            .{ .array = .{ .name = "mix", .elements = elems, .inits = &.{} } },
            .{ .array_assign = .{ .array = .{ .name = "mix", .elements = elems, .index = f.num(2) }, .value = f.num(2) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "Variable x2 has been defined as both character and numeric.") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.rowCount()); // step never ran
    }
    // The VALID shapes stay clean: all-numeric, all-char (`$`), and a
    // special-list array (`_all_` is heterogeneous by design — exempt).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const en: []const []const u8 = &.{ "n1", "n2" };
        const ec: []const []const u8 = &.{ "c1", "c2" };
        const inits = [_]*const ast.Expr{ f.num(10), f.num(20) };
        const prog = [_]ast.Stmt{
            .{ .array = .{ .name = "n", .elements = en, .inits = &inits } },
            .{ .array = .{ .name = "c", .elements = ec, .inits = &.{}, .type = .char } },
            .{ .assign = .{ .target = "s", .value = f.e(.{ .str = "a" }) } },
            .{ .array = .{ .name = "v", .elements = &.{}, .inits = &.{}, .special = .all } },
            .{ .array_assign = .{ .array = .{ .name = "n", .elements = en, .index = f.num(2) }, .value = f.num(21) } },
            .{ .array_assign = .{ .array = .{ .name = "c", .elements = ec, .index = f.num(2) }, .value = f.e(.{ .str = "z" }) } },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 1), out.rowCount());
        try t.expectEqual(@as(f64, 21), out.row(0)[out.indexOf("n2").?].num);
        try t.expectEqualStrings("z", out.row(0)[out.indexOf("c2").?].str);
    }
}

test "NOTE-fmtnumoncharcoerce: a format whose type disagrees with the variable is a compile-time ERROR, both directions + ATTRIB" {
    // SAS 9.4: the FORMAT statement associates char vars with char formats and
    // numeric vars with numeric formats (Formats & Informats Ref printed p.7);
    // an incompatible format ERRORs (p.5) — it never silently coerces. The
    // check runs in declareStmt so the hasStepErrors() gate halts the step
    // BEFORE an observation is written (no output is produced first).

    // 1. numeric format on a char variable (`length c $3; format c 8.2;`).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        x.declared = &[_]DeclVar{.{ .name = "c", .type = .char, .len = 3 }};
        const items = [_]ast.FormatItem{.{ .name = "c", .fmt = "8.2" }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "c", .value = f.e(.{ .str = "abc" }) } },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "The numeric format 8.2 cannot be used with character variable c.") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.rowCount()); // halted before output
    }
    // 2. the mirror: char format on a numeric variable (`n=5; format n $8.;`).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.FormatItem{.{ .name = "n", .fmt = "$8." }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "n", .value = f.num(5) } },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var found = false;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "The character format $8. cannot be used with numeric variable n.") != null) {
            found = true;
        };
        try t.expect(found);
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    // 3. ATTRIB spelling (rides the same .format node): `attrib n format=$8.;`
    //    on a numeric var errors at compile time too — the shape that used to
    //    slip to a per-cell runtime error.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        x.declared = &[_]DeclVar{.{ .name = "n", .type = .num }};
        const items = [_]ast.FormatItem{.{ .name = "n", .fmt = "$8." }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "n", .value = f.num(5) } },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
    }
    // 4. `length c $3; attrib c format=8.2;` — the seedDeclVar "defined as
    //    both" conflict already reports it; the format check must NOT double.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        x.declared = &[_]DeclVar{ .{ .name = "c", .type = .char, .len = 3 }, .{ .name = "c", .type = .num } };
        const items = [_]ast.FormatItem{.{ .name = "c", .fmt = "8.2" }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "c", .value = f.e(.{ .str = "abc" }) } },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var errs: usize = 0;
        for (f.diags.list.items) |d| if (d.severity == .err) {
            errs += 1;
        };
        try t.expectEqual(@as(usize, 1), errs); // one root cause, one ERROR
    }
    // 5. controls must not move: numeric format on numeric, `$` format on
    //    char, and the removal sentinel `format x;` on either type — all clean.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.FormatItem{
            .{ .name = "n", .fmt = "8.2" },
            .{ .name = "c", .fmt = "$8." },
            .{ .name = "n2", .fmt = "$." }, // `format n2;` removal rides "$.", any type
        };
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "n", .value = f.num(5) } },
            .{ .assign = .{ .target = "c", .value = f.e(.{ .str = "abc" }) } },
            .{ .assign = .{ .target = "n2", .value = f.num(7) } },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 1), out.rowCount());
    }
}

test "BUG-informatallnotypecheck: a special-list format/informat type conflict fires EXACTLY ONCE per arm" {
    // The expanded item rides exec's attribute lists by class: a display
    // format rides BOTH self.formats and self.attrs (the dedup bb2de8d4's
    // `false` was for), an informat (\x01 rider) rides attrs ONLY. The keyed
    // check (display on the .formats pass, informat on the .attrs pass)
    // validates each member exactly once: the format arm must not fire TWICE
    // (the old double-report) and the informat arm must not fire ZERO times
    // (the shipped regression — rc 0 with the bad informat attached).

    // 1. informat arm: `informat _all_ 8.;` over a char var — exactly one ERROR.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.FormatItem{.{ .name = "_all_", .fmt = "8." }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "a", .value = f.e(.{ .str = "x" }) } },
            .{ .assign = .{ .target = "b", .value = f.num(1) } },
            .{ .informat = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var hits: usize = 0;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "The numeric informat 8. cannot be used with character variable a.") != null) {
            hits += 1;
        };
        try t.expectEqual(@as(usize, 1), hits); // once — not zero (the bug), not two
        try t.expectEqual(@as(usize, 0), out.rowCount()); // halted before output
    }
    // 2. format arm: `format _all_ 8.;` rides BOTH lists — still exactly one
    //    ERROR (the double-report the keyed check exists to prevent).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.FormatItem{.{ .name = "_all_", .fmt = "8." }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "a", .value = f.e(.{ .str = "x" }) } },
            .{ .assign = .{ .target = "b", .value = f.num(1) } },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        var hits: usize = 0;
        for (f.diags.list.items) |d| if (d.severity == .err and std.mem.indexOf(u8, d.message, "The numeric format 8. cannot be used with character variable a.") != null) {
            hits += 1;
        };
        try t.expectEqual(@as(usize, 1), hits); // once — not two (rides both lists)
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    // 3. control: the same statements on an all-numeric PDV stay legal (the
    //    informat ATTACHES — the check only gates type conflicts).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const items = [_]ast.FormatItem{.{ .name = "_all_", .fmt = "8." }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "p", .value = f.num(1) } },
            .{ .assign = .{ .target = "q", .value = f.num(2) } },
            .{ .informat = &items },
            .{ .format = &items },
        };
        var out = Dataset.init(f.a(), "work.out");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 1), out.rowCount());
    }
}

test "declare hash h(dataset:) loads the named table on defineDone (BUG-hashdataset)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // a lookup table in the library
    const lookup = f.newDs("lookup");
    _ = try lookup.addColumn("id", .num);
    _ = try lookup.addColumn("nm", .char);
    try lookup.appendRow(&.{ .{ .num = 1 }, .{ .str = "Alice" } });
    try lookup.appendRow(&.{ .{ .num = 2 }, .{ .str = "Bob" } });
    try f.lib.put("lookup", lookup);

    const ds_arg = [_]ast.HashArg{.{ .name = "dataset", .value = f.e(.{ .str = "lookup" }) }};
    const key_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "id" }) }};
    const data_arg = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "nm" }) }};
    const find_args = [_]ast.HashArg{.{ .name = "key", .value = f.num(2) }};
    const prog = [_]ast.Stmt{
        .{ .hash_decl = .{ .name = "h", .args = &ds_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &data_arg } },
        .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &.{} } },
        .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "find", .args = &find_args } },
    };

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    // find(key:2) pulled "Bob" from the dataset-loaded hash (rc 0 = found)
    try t.expectEqualStrings("Bob", out.row(0)[out.indexOf("nm").?].str);
    try t.expectEqual(@as(f64, 0), out.row(0)[out.indexOf("rc").?].num);
}

test "DO-loop CONTINUE skips the rest of the iteration (DO-cl)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // do i = 1 to 4; if i = 2 then continue; output; end;
    const cont: ast.Stmt = .continue_;
    const body = [_]ast.Stmt{
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("i"), f.num(2)), .then_branch = &cont, .else_branch = null } },
        .{ .output = &.{} },
    };
    const prog = [_]ast.Stmt{.{ .do_ = .{
        .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(4), .by = null } },
        .body = &body,
    } }};

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    const ii = out.indexOf("i").?;
    try t.expectEqual(@as(usize, 3), out.rowCount()); // i=2 skipped, not output
    try t.expectEqual(@as(f64, 1), out.row(0)[ii].num);
    try t.expectEqual(@as(f64, 3), out.row(1)[ii].num);
    try t.expectEqual(@as(f64, 4), out.row(2)[ii].num);
}

test "DO-loop LEAVE exits the loop early (DO-cl)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // do i = 1 to 5; if i = 3 then leave; output; end;
    const lv: ast.Stmt = .leave;
    const body = [_]ast.Stmt{
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("i"), f.num(3)), .then_branch = &lv, .else_branch = null } },
        .{ .output = &.{} },
    };
    const prog = [_]ast.Stmt{.{ .do_ = .{
        .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(5), .by = null } },
        .body = &body,
    } }};

    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);

    const ii = out.indexOf("i").?;
    try t.expectEqual(@as(usize, 2), out.rowCount()); // stops at i=3
    try t.expectEqual(@as(f64, 1), out.row(0)[ii].num);
    try t.expectEqual(@as(f64, 2), out.row(1)[ii].num);
}

test "stray LEAVE/CONTINUE in open code is a compile ERROR, step never runs (BUG-leavecontinueopen)" {
    var f = fixture();
    defer f.deinit();
    f.prime();

    // data out; x=1; leave; y=2; run; — SAS 728-185: compile ERROR, nothing runs.
    // Was: silently dropped y=2 and still wrote the truncated obs.
    var x = f.exec();
    const prog = [_]ast.Stmt{
        .{ .assign = .{ .target = "x", .value = f.num(1) } },
        .leave,
        .{ .assign = .{ .target = "y", .value = f.num(2) } },
    };
    var out = Dataset.init(f.a(), "out");
    try x.run(&prog, &out);
    try t.expect(diagsHave(&f.diags, "The LEAVE statement is not valid outside of a DO loop"));
    try t.expectEqual(@as(usize, 0), out.rowCount()); // no truncated obs

    // CONTINUE in open code → same compile ERROR.
    f.prime();
    var x2 = f.exec();
    const prog2 = [_]ast.Stmt{
        .{ .assign = .{ .target = "x", .value = f.num(1) } },
        .continue_,
        .{ .assign = .{ .target = "y", .value = f.num(2) } },
    };
    var out2 = Dataset.init(f.a(), "out2");
    try x2.run(&prog2, &out2);
    try t.expect(diagsHave(&f.diags, "The CONTINUE statement is not valid outside of a DO loop"));
    try t.expectEqual(@as(usize, 0), out2.rowCount());

    // control: LEAVE inside a DO loop (nested → innermost) stays legal.
    f.prime();
    var x3 = f.exec();
    const lv: ast.Stmt = .leave;
    const inner = [_]ast.Stmt{.{ .if_ = .{ .cond = f.bin(.eq, f.vbl("j"), f.num(2)), .then_branch = &lv, .else_branch = null } }};
    const body = [_]ast.Stmt{.{ .do_ = .{
        .header = .{ .iter = .{ .name = "j", .start = f.num(1), .stop = f.num(5), .by = null } },
        .body = &inner,
    } }};
    const prog3 = [_]ast.Stmt{.{ .do_ = .{
        .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(2), .by = null } },
        .body = &body,
    } }};
    var out3 = Dataset.init(f.a(), "out3");
    try x3.run(&prog3, &out3);
    try t.expect(!f.diags.hasErrors());
}

test "DO loop BY 0 is an ERROR; BY 2 / BY -1 unchanged (BUG-doByZero)" {
    var f = fixture();
    defer f.deinit();
    f.prime();

    // do i=1 to 10 by 0; — would loop forever; SAS ERRORs (was: NOTE + 0 iters).
    var x = f.exec();
    const prog = [_]ast.Stmt{.{ .do_ = .{
        .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(10), .by = f.num(0) } },
        .body = &.{},
    } }};
    var out = Dataset.init(f.a(), "out");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expect(diagsHave(&f.diags, "zero increment"));

    // controls: ascending BY 2 → terminal 11; descending BY -1 → terminal 0
    // (the overshoot past the bound, evaluated once).
    f.prime();
    var x2 = f.exec();
    const prog2 = [_]ast.Stmt{
        .{ .do_ = .{ .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(10), .by = f.num(2) } }, .body = &.{} } },
        .{ .do_ = .{ .header = .{ .iter = .{ .name = "j", .start = f.num(5), .stop = f.num(1), .by = f.num(-1) } }, .body = &.{} } },
    };
    var out2 = Dataset.init(f.a(), "out2");
    try x2.run(&prog2, &out2);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(f64, 11), out2.row(0)[out2.indexOf("i").?].num);
    try t.expectEqual(@as(f64, 0), out2.row(0)[out2.indexOf("j").?].num);
}

test "WHERE referencing a variable absent from the source fails loud, emits nothing (BUG-wherevar)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data b; set a; where zzz > 1; run; — eval mapped the unknown var to
    // missing, so the filter silently kept ZERO rows, exit 0. SAS:
    // "ERROR: Variable ZZZ is not on file WORK.A".
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{"a"};
    const prog = [_]ast.Stmt{ .{ .set = &names }, .{ .where_ = f.bin(.gt, f.vbl("zzz"), f.num(1)) } };
    var out = Dataset.init(f.a(), "b");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasErrors()); // captured diagnostic — never a silent empty set
    try t.expectEqual(@as(usize, 0), out.rowCount());
}

test "a second plain WHERE replaces the first — last wins (BUG-whereplacelast)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data b; set a; where k > 1; where k > 5; run; — SAS 9.4: a later plain
    // WHERE supersedes the earlier one (only WHERE ALSO ANDs). Keeping the
    // first silently mis-filters.
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    for ([_]f64{ 1, 3, 6, 8 }) |v| try a_ds.appendRow(&.{.{ .num = v }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{"a"};
    const prog = [_]ast.Stmt{
        .{ .set = &names },
        .{ .where_ = f.bin(.gt, f.vbl("k"), f.num(1)) },
        .{ .where_ = f.bin(.gt, f.vbl("k"), f.num(5)) },
    };
    var out = Dataset.init(f.a(), "b");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), out.rowCount()); // k > 5: 6 and 8
    try t.expectEqual(@as(f64, 6), out.row(0)[0].num);
    try t.expectEqual(@as(f64, 8), out.row(1)[0].num);
}

test "WHERE with POINT= fails loud, emits nothing (QA-audit42)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data b; do i=1 to 2; set a point=i; output; end; stop; where k > 1; run;
    // — SAS rejects WHERE+POINT=; we silently ignored the WHERE (wrong rows).
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try a_ds.appendRow(&.{.{ .num = 2 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{ "a", "\x00point=i" };
    const prog = [_]ast.Stmt{ .{ .set = &names }, .{ .where_ = f.bin(.gt, f.vbl("k"), f.num(1)) } };
    var out = Dataset.init(f.a(), "b");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasErrors());
    try t.expectEqual(@as(usize, 0), out.rowCount());
}

test "POINT= with BY fails loud (BUG-setpointtemp)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data b; set a point=p; by k; run; — SAS: POINT= cannot be used with BY.
    // It silently emitted a bogus all-missing row, exit 0.
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{ "a", "\x00point=p" };
    const bys = [_][]const u8{"k"};
    const prog = [_]ast.Stmt{ .{ .set = &names }, .{ .by = &bys } };
    var out = Dataset.init(f.a(), "b");
    try t.expectError(error.ExecError, x.run(&prog, &out));
    try t.expectEqualStrings("POINT= cannot be used with BY", f.diags.list.items[f.diags.list.items.len - 1].message);
}

test "POINT= beside a MERGE/INPUT driver: BY fails loud for ANY driver; no-BY merge + INPUT read and keep the automatic output (BUG-pointsuppressesalloutput + BUG-pointmergelookup)" {
    // 1. MERGE + BY + POINT= — Statements ref, SET POINT= Restrictions: "You
    //    cannot use POINT= with a BY statement, a WHERE statement, or a WHERE=
    //    data set option" — flat, driver-independent. The merge driver used to
    //    win buildDriver first, skip this guard, and silently emit merge rows
    //    with the lookup columns MISSING (QA tick357 F4).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const dd = f.newDs("d");
        _ = try dd.addColumn("v", .num);
        try dd.appendRow(&.{.{ .num = 10 }});
        try f.lib.put("d", dd);
        const ee = f.newDs("e");
        _ = try ee.addColumn("v", .num);
        try ee.appendRow(&.{.{ .num = 10 }});
        try f.lib.put("e", ee);

        const mnames = [_][]const u8{ "d", "e" };
        const snames = [_][]const u8{ "d", "\x00point=p" };
        const bys = [_][]const u8{"v"};
        const prog = [_]ast.Stmt{ .{ .merge = &mnames }, .{ .set = &snames }, .{ .by = &bys } };
        var out = Dataset.init(f.a(), "w");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqualStrings("POINT= cannot be used with BY", f.diags.list.items[f.diags.list.items.len - 1].message);
    }
    // 2. MERGE (no BY) + POINT= — the documented direct-access lookup beside a
    //    driver (Statements ref, SET Example 6: `set revenue; … set expense
    //    point=_n_;`). The merge driver's 4 rows must ALL appear — Language Reference: Concepts p.477
    //    step 5's automatic output is unconditional here (the 1736df6d
    //    regression keyed on the MENTION of POINT= and wrote ZERO rows, exit 0)
    //    — and lv must be POPULATED by the direct read (the pre-existing hole
    //    parsed the SET and then never performed the read).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const dd = f.newDs("d");
        _ = try dd.addColumn("v", .num);
        for ([_]f64{ 10, 20, 30, 40 }) |v| try dd.appendRow(&.{.{ .num = v }});
        try f.lib.put("d", dd);
        const ee = f.newDs("e");
        _ = try ee.addColumn("z", .num);
        for ([_]f64{ 1, 2, 3, 4 }) |v| try ee.appendRow(&.{.{ .num = v }});
        try f.lib.put("e", ee);

        const mnames = [_][]const u8{ "d", "e" };
        const snames = [_][]const u8{ "d(rename=(v=lv))", "\x00point=p" };
        const prog = [_]ast.Stmt{
            .{ .merge = &mnames },
            .{ .assign = .{ .target = "p", .value = f.num(2) } },
            .{ .set = &snames },
        };
        var out = Dataset.init(f.a(), "w");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 4), out.rowCount()); // every merge row
        const lvc = out.indexOf("lv").?;
        const vc = out.indexOf("v").?;
        for (0..4) |r| {
            try t.expectEqual(@as(f64, 20), out.row(r)[lvc].num); // obs 2, every row
            try t.expectEqual(@as(f64, @floatFromInt(10 * (r + 1))), out.row(r)[vc].num); // merge sequence
        }
    }
    // 3. INPUT + POINT= — INPUT is a peer reader with its own EOF (Language Reference: Concepts p.477
    //    step 3; Table 20.4), so the step is INPUT-DRIVEN: one iteration per
    //    record, automatic output intact, direct read of obs p each time.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();

        const dd = f.newDs("d");
        _ = try dd.addColumn("v", .num);
        for ([_]f64{ 10, 20, 30 }) |v| try dd.appendRow(&.{.{ .num = v }});
        try f.lib.put("d", dd);

        const items = [_]ast.InputItem{.{ .name = "p", .type = .num }};
        const lines = [_][]const u8{ "1", "3" };
        const snames = [_][]const u8{ "d", "\x00point=p" };
        const prog = [_]ast.Stmt{ .{ .input = &items }, .{ .set = &snames }, .{ .datalines = &lines } };
        var out = Dataset.init(f.a(), "w");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expectEqual(@as(usize, 2), out.rowCount()); // one per datalines record
        try t.expectEqual(@as(f64, 10), out.row(0)[0].num); // obs 1
        try t.expectEqual(@as(f64, 30), out.row(1)[0].num); // obs 3
    }
}

test "POINT= out-of-range obs is a NOTE + _ERROR_=1 and the step CONTINUES (NOTE-pointoorhard)" {
    // Statements Ref SET POINT=: an invalid POINT= value "sets the automatic
    // variable _ERROR_ to 1" — and its continuous-loop caution only makes sense
    // if the step CONTINUES; Language Reference: Concepts p.488's `if _error_ then stop;` idiom is the
    // user side of that contract. No halt, no errhalt poison. This test
    // deliberately INVERTS e1d73fbf's pin (BUG-pointnobs, "halt like the
    // array-OOR paths"): the halt made the documented idiom unrunnable (rc 1,
    // later steps suppressed). _ERROR_ is asserted BEHAVIOURALLY — the guard
    // firing and a captured copy — because the loop-top PDV reset makes the
    // post-run value unobservable.
    const mk = struct {
        fn a(fx: anytype) !void {
            const a_ds = fx.newDs("a");
            _ = try a_ds.addColumn("k", .num);
            try a_ds.appendRow(&.{.{ .num = 10 }});
            try a_ds.appendRow(&.{.{ .num = 20 }});
            try a_ds.appendRow(&.{.{ .num = 30 }});
            try fx.lib.put("a", a_ds);
        }
    }.a;

    // 1. THE IDIOM: data b; do i=1 to 5; set a point=i; if _error_ then stop;
    //    output; end; stop; run; — the guard must SEE _ERROR_=1 at i=4 and end
    //    the step: exactly the 3 real rows, no stale re-output, NOTE in the log,
    //    and NO error class anywhere (rc stays 0, later steps run — a following
    //    PROC PRINT is no longer suppressed).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        try mk(&f);
        const names = [_][]const u8{ "a", "\x00point=i" };
        const empty_out = [_][]const u8{};
        const stop_stmt = ast.Stmt{ .stop = {} };
        const body = [_]ast.Stmt{
            .{ .set = &names },
            .{ .if_ = .{ .cond = f.vbl("_error_"), .then_branch = &stop_stmt, .else_branch = null } },
            .{ .output = &empty_out },
        };
        const prog = [_]ast.Stmt{.{ .do_ = .{
            .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(5), .by = null } },
            .body = &body,
        } }};
        var out = Dataset.init(f.a(), "b");
        try x.run(&prog, &out); // NO ExecError — the step continues to the guard
        try t.expect(!f.diags.hasErrors()); // NOTE only: rc stays 0 …
        try t.expect(!f.diags.hasStepErrors()); // … and no errhalt poison for later steps
        try t.expectEqual(@as(usize, 3), out.rowCount()); // guard fired at i=4: the 3 real rows ONLY
        const last = f.diags.list.items[f.diags.list.items.len - 1];
        try t.expectEqual(diag.Severity.note, last.severity);
        try t.expectEqualStrings("SET POINT= invalid observation number 4: a has 3 observations", last.message);
    }

    // 2. UNGUARDED: data b; do i=1 to 5; set a point=i; output; end; run; — the
    //    loop runs to its end. Each failing iteration's explicit OUTPUT writes
    //    the retained (stale) PDV with _ERROR_=1 loud — the oracle-blocked
    //    stale-PDV pick (SAS retention semantics), ponytail-marked at the .set
    //    arm. The trailing iteration-2 repeat-stop (DEC-pointrepeatstop) still
    //    terminates the re-armed driver.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        try mk(&f);
        const names = [_][]const u8{ "a", "\x00point=i" };
        const empty_out = [_][]const u8{};
        const body = [_]ast.Stmt{ .{ .set = &names }, .{ .output = &empty_out } };
        const prog = [_]ast.Stmt{.{ .do_ = .{
            .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(5), .by = null } },
            .body = &body,
        } }};
        var out = Dataset.init(f.a(), "b");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasErrors());
        try t.expect(!f.diags.hasStepErrors());
        try t.expectEqual(@as(usize, 5), out.rowCount()); // 3 real + 2 stale, all loud via NOTEs
        const kc = out.indexOf("k").?;
        for (0..5) |r| try t.expectEqual(@as(f64, @floatFromInt(@as(usize, 10) * @min(r + 1, 3))), out.row(r)[kc].num);
        const last = f.diags.list.items[f.diags.list.items.len - 1];
        try t.expectEqual(diag.Severity.note, last.severity);
        try t.expectEqualStrings("SET POINT= invalid observation number 5: a has 3 observations", last.message);
    }
}

test "POINT= with a missing obs number is a NOTE + _ERROR_=1, step CONTINUES (NOTE-pointoorhard)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data b; set a point=p; e=_error_; output; stop; run; — p never assigned
    // (missing): same "invalid value of the POINT= variable" path as
    // out-of-range: NOTE, _ERROR_=1 (captured into e INSIDE the step, before the
    // loop-top reset), continue — the explicit OUTPUT writes the never-loaded
    // (all-missing) PDV and STOP ends the step. No ExecError, rc 0, no poison.
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 7 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{ "a", "\x00point=p" };
    const empty_out = [_][]const u8{};
    const prog = [_]ast.Stmt{
        .{ .set = &names },
        .{ .assign = .{ .target = "e", .value = f.vbl("_error_") } },
        .{ .output = &empty_out },
        .{ .stop = {} },
    };
    var out = Dataset.init(f.a(), "b");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expect(!f.diags.hasStepErrors());
    const last = f.diags.list.items[f.diags.list.items.len - 1];
    try t.expectEqual(diag.Severity.note, last.severity);
    try t.expectEqualStrings("SET POINT= invalid observation number nan: a has 1 observations", last.message);
    try t.expectEqual(@as(usize, 1), out.rowCount()); // the never-loaded (all-missing) row the user's OUTPUT asked for
    try t.expectEqual(@as(f64, 1), out.row(0)[out.indexOf("e").?].num); // _ERROR_ was 1 at the guard point
    try t.expect(std.math.isNan(out.row(0)[out.indexOf("k").?].num));
}

test "nested-only SET keeps END= and reads to EOF (BUG-nestedsetopts)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data w; if 1 then set d end=e; f=e; run; — the nested SET is the step's
    // ONLY source, so its \x00end= sentinel was never extracted (BUG-
    // nestedsetdriver keeps nested sources out of set_names): e never fired —
    // a DO UNTIL on it hung forever — and "File  end=e does not exist" leaked
    // the raw \x00. Correct: 2 obs, f = 0 then 1 (QA tick290 F1+F2).
    const d_ds = f.newDs("d");
    _ = try d_ds.addColumn("v", .num);
    try d_ds.appendRow(&.{.{ .num = 10 }});
    try d_ds.appendRow(&.{.{ .num = 20 }});
    try f.lib.put("d", d_ds);

    const names = [_][]const u8{ "d", "\x00end=e" };
    const set_stmt = ast.Stmt{ .set = &names };
    const prog = [_]ast.Stmt{
        .{ .if_ = .{ .cond = f.num(1), .then_branch = &set_stmt, .else_branch = null } },
        .{ .assign = .{ .target = "f", .value = f.vbl("e") } },
    };
    var out = Dataset.init(f.a(), "w");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), out.rowCount());
    try t.expectEqual(@as(f64, 0), out.row(0)[out.indexOf("f").?].num);
    try t.expectEqual(@as(f64, 1), out.row(1)[out.indexOf("f").?].num);
}

test "conditional POINT= lookup beside a driving SET reads (GAP-secondsetstmt); a SECOND POINT= source fails clean — no raw sentinel (BUG-nestedsetopts)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // Statements ref p.341 Example 6 makes ONE sequential driver + a second
    // SET that is a direct-access POINT= lookup the documented idiom — the
    // conditional form `data o; set a; if _n_=1 then set b point=k; run;`
    // (which BUG-nestedsetopts' pin had LOUD) is the same family and must RUN:
    // the lookup reads b obs k on iteration 1, then the value RETAINS (SET vars
    // auto-retain) while the driver finishes.
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try a_ds.appendRow(&.{.{ .num = 2 }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("w", .num);
    try b_ds.appendRow(&.{.{ .num = 100 }});
    try f.lib.put("b", b_ds);

    const drv = [_][]const u8{"a"};
    const nested = [_][]const u8{ "b", "\x00point=k" };
    const nested_stmt = ast.Stmt{ .set = &nested };
    const prog = [_]ast.Stmt{
        .{ .set = &drv },
        .{ .if_ = .{ .cond = f.bin(.eq, f.vbl("_n_"), f.num(1)), .then_branch = &nested_stmt, .else_branch = null } },
    };
    var out = Dataset.init(f.a(), "o");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 2), out.rowCount()); // the SEQUENTIAL driver bounds the step
    try t.expectEqual(@as(f64, 100), out.row(0)[out.indexOf("w").?].num); // looked up at _n_=1
    try t.expectEqual(@as(f64, 100), out.row(1)[out.indexOf("w").?].num); // retained on iter 2
    try t.expectEqual(@as(f64, 2), out.row(1)[out.indexOf("k").?].num); // driver column intact

    // …but TWO direct-access sources stay loud (opensas models ONE), with no
    // raw \x00 sentinel in the message: `set a point=k; set b point=j;`.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var x2 = f2.exec();
    const a2 = f2.newDs("a");
    _ = try a2.addColumn("k", .num);
    try a2.appendRow(&.{.{ .num = 1 }});
    try f2.lib.put("a", a2);
    const b2 = f2.newDs("b");
    _ = try b2.addColumn("w", .num);
    try b2.appendRow(&.{.{ .num = 100 }});
    try f2.lib.put("b", b2);
    const p1 = [_][]const u8{ "a", "\x00point=k" };
    const p2 = [_][]const u8{ "b", "\x00point=j" };
    const prog2 = [_]ast.Stmt{ .{ .set = &p1 }, .{ .set = &p2 } };
    var out2 = Dataset.init(f2.a(), "o");
    try t.expectError(error.ExecError, x2.run(&prog2, &out2));
    const msg = f2.diags.list.items[f2.diags.list.items.len - 1].message;
    try t.expectEqualStrings("POINT= is not supported on a second or nested SET source", msg);
    try t.expect(std.mem.indexOfScalar(u8, msg, 0) == null); // no raw \x00 in a user-visible message

    // …and END= on the SAME statement as the second-SET POINT= stays loud
    // (END= entry: "END= cannot be used with POINT=.").
    var f3 = fixture();
    defer f3.deinit();
    f3.prime();
    var x3 = f3.exec();
    const a3 = f3.newDs("a");
    _ = try a3.addColumn("k", .num);
    try a3.appendRow(&.{.{ .num = 1 }});
    try f3.lib.put("a", a3);
    const b3 = f3.newDs("b");
    _ = try b3.addColumn("w", .num);
    try b3.appendRow(&.{.{ .num = 100 }});
    try f3.lib.put("b", b3);
    const d3 = [_][]const u8{"a"};
    const pe = [_][]const u8{ "b", "\x00point=j", "\x00end=e" };
    const prog3 = [_]ast.Stmt{ .{ .set = &d3 }, .{ .set = &pe } };
    var out3 = Dataset.init(f3.a(), "o");
    try t.expectError(error.ExecError, x3.run(&prog3, &out3));
    try t.expectEqualStrings("END= cannot be used with POINT=", f3.diags.list.items[f3.diags.list.items.len - 1].message);

    // …and the p.335 third leg fires for the CLAIMED second-SET path too: a
    // where= option riding the lookup source (BUG-pointwheredsopt's scanner
    // re-scoped to the lookup's own list — GAP-secondsetstmt).
    var f4 = fixture();
    defer f4.deinit();
    f4.prime();
    var x4 = f4.exec();
    const a4 = f4.newDs("a");
    _ = try a4.addColumn("k", .num);
    try a4.appendRow(&.{.{ .num = 1 }});
    try f4.lib.put("a", a4);
    const b4 = f4.newDs("b");
    _ = try b4.addColumn("w", .num);
    try b4.appendRow(&.{.{ .num = 100 }});
    try f4.lib.put("b", b4);
    const d4 = [_][]const u8{"a"};
    const pw = [_][]const u8{ "b(where=(w>0))", "\x00point=j" };
    const prog4 = [_]ast.Stmt{ .{ .set = &d4 }, .{ .set = &pw } };
    var out4 = Dataset.init(f4.a(), "o");
    try x4.run(&prog4, &out4); // spent driver: the ERROR halts output, not the run
    try t.expect(f4.diags.hasErrors());
    try t.expectEqual(@as(usize, 0), out4.rowCount());
    try t.expectEqualStrings("The WHERE= data set option cannot be used with the POINT= option", f4.diags.list.items[f4.diags.list.items.len - 1].message);
}

test "QA tick377 F2: the second-SET POINT= lookup's columns land at the carrying node — no false uninitialized NOTE; a genuine uninit read still notes" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // Repro A shape: `set drv; set lk point=_n_; x = b * 2; y = ghost + 1;` —
    // b is first-mentioned at the SET that CARRIES POINT= (before x's
    // assignment), so the PDV order is a b x y and reading b notes NOTHING;
    // ghost is genuinely uninitialized and must still note, once.
    const drv_ds = f.newDs("drv");
    _ = try drv_ds.addColumn("a", .num);
    try drv_ds.appendRow(&.{.{ .num = 1 }});
    try drv_ds.appendRow(&.{.{ .num = 2 }});
    try f.lib.put("drv", drv_ds);
    const lk_ds = f.newDs("lk");
    _ = try lk_ds.addColumn("b", .num);
    try lk_ds.appendRow(&.{.{ .num = 10 }});
    try lk_ds.appendRow(&.{.{ .num = 20 }});
    try f.lib.put("lk", lk_ds);

    const drv = [_][]const u8{"drv"};
    const lkp = [_][]const u8{ "lk", "\x00point=_n_" };
    const prog = [_]ast.Stmt{
        .{ .set = &drv },
        .{ .set = &lkp },
        .{ .assign = .{ .target = "x", .value = f.bin(.mul, f.vbl("b"), f.num(2)) } },
        .{ .assign = .{ .target = "y", .value = f.bin(.add, f.vbl("ghost"), f.num(1)) } },
    };
    var out = Dataset.init(f.a(), "o");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());

    var uninit_notes: usize = 0;
    for (f.diags.list.items) |d| {
        if (d.severity == .note and std.mem.indexOf(u8, d.message, "is uninitialized") != null) {
            uninit_notes += 1;
            try t.expect(std.mem.indexOf(u8, d.message, "ghost") != null); // only ghost — never b
        }
    }
    try t.expectEqual(@as(usize, 1), uninit_notes);
    try t.expect(diagsNote(&f.diags, "Variable ghost is uninitialized.")); // exact SAS wording

    // first-mention PDV order: driver col, lookup col at its node, then the assigns
    try t.expect(out.indexOf("a").? < out.indexOf("b").?);
    try t.expect(out.indexOf("b").? < out.indexOf("x").?);
    try t.expectEqual(@as(f64, 20), out.row(0)[out.indexOf("x").?].num); // lookup value intact
    try t.expectEqual(@as(f64, 40), out.row(1)[out.indexOf("x").?].num);

    // Repro B shape: `merge mA mB; set lk point=_n_;` — the MERGE driver owns
    // the early slots and the FIRST top-level SET (the lookup) seeds its
    // column at its own node: k p q b, not b k p q.
    var f2 = fixture();
    defer f2.deinit();
    f2.prime();
    var x2 = f2.exec();
    const ma = f2.newDs("ma");
    _ = try ma.addColumn("k", .num);
    _ = try ma.addColumn("p", .num);
    try ma.appendRow(&.{ .{ .num = 1 }, .{ .num = 9 } });
    try f2.lib.put("ma", ma);
    const mb = f2.newDs("mb");
    _ = try mb.addColumn("k", .num);
    _ = try mb.addColumn("q", .num);
    try mb.appendRow(&.{ .{ .num = 1 }, .{ .num = 7 } });
    try f2.lib.put("mb", mb);
    const lk2 = f2.newDs("lk");
    _ = try lk2.addColumn("b", .num);
    try lk2.appendRow(&.{.{ .num = 10 }});
    try f2.lib.put("lk", lk2);
    const mm = [_][]const u8{ "ma", "mb" };
    const lkp2 = [_][]const u8{ "lk", "\x00point=_n_" };
    const prog2 = [_]ast.Stmt{ .{ .merge = &mm }, .{ .set = &lkp2 } };
    var out2 = Dataset.init(f2.a(), "r1");
    try x2.run(&prog2, &out2);
    try t.expect(!f2.diags.hasErrors());
    try t.expect(!diagsHave(&f2.diags, "is uninitialized"));
    try t.expect(out2.indexOf("q").? < out2.indexOf("b").?); // driver cols first
    try t.expectEqual(@as(f64, 10), out2.row(0)[out2.indexOf("b").?].num);
}

test "nested MERGE/UPDATE seed the PDV schema; nested UPDATE without BY fails loud (BUG-nestedsourceschema)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data w; if 0 then merge b; stop; run; — the nested cut-off contributed
    // NO PDV columns (a nested SET still did): "0 variables" at exit 0, and
    // `if _n_=1 then merge a b;` fabricated "1 obs with 0 variables".
    const b_ds = f.newDs("b");
    _ = try b_ds.addColumn("k", .num);
    _ = try b_ds.addColumn("v", .num);
    try b_ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 } });
    try f.lib.put("b", b_ds);

    const mnames = [_][]const u8{"b"};
    const merge_stmt = ast.Stmt{ .merge = &mnames };
    const prog = [_]ast.Stmt{
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &merge_stmt, .else_branch = null } },
        .stop,
    };
    var out = Dataset.init(f.a(), "w");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 0), out.rowCount());
    try t.expectEqual(@as(usize, 2), out.columns.items.len); // k v — the schema a nested SET always seeded

    // data w2; if 0 then update b b; stop; run; — PRE errored "The BY
    // statement is required for the UPDATE statement"; the cut-off silently
    // emitted a 0-variable dataset instead. Fail loud restored.
    var x2 = f.exec();
    const unames = [_][]const u8{ "b", "b" };
    const upd_stmt = ast.Stmt{ .update = &unames };
    const prog2 = [_]ast.Stmt{
        .{ .if_ = .{ .cond = f.num(0), .then_branch = &upd_stmt, .else_branch = null } },
        .stop,
    };
    var out2 = Dataset.init(f.a(), "w2");
    try t.expectError(error.ExecError, x2.run(&prog2, &out2));
    const msg = f.diags.list.items[f.diags.list.items.len - 1].message;
    try t.expectEqualStrings("The BY statement is required for the UPDATE statement", msg);
    try t.expect(std.mem.indexOfScalar(u8, msg, 0) == null); // no raw \x00 in a user-visible message
}

test "NOBS= is the PHYSICAL obs count, not the firstobs=/obs= window (BUG-pointnobs)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // data b; set a(firstobs=2 obs=2) nobs=n; run; — the window reads 1 row,
    // but NOBS= is descriptor-level: the physical 3. Both producers (pre-loop
    // init and per-read stampObs) counted the SLICED copy before the fix.
    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("k", .num);
    try a_ds.appendRow(&.{.{ .num = 10 }});
    try a_ds.appendRow(&.{.{ .num = 20 }});
    try a_ds.appendRow(&.{.{ .num = 30 }});
    try f.lib.put("a", a_ds);

    const names = [_][]const u8{"a(firstobs=2 obs=2)"};
    const drop_helper = [_][]const u8{"_setobs_"}; // the parser injects `drop _setobs_;` on any SET step
    const prog = [_]ast.Stmt{
        .{ .drop = &drop_helper },
        .{ .set = &names },
        .{ .assign = .{ .target = "n", .value = f.vbl("_setobs_") } }, // parser's nobs=n desugar
    };
    var out = Dataset.init(f.a(), "b");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 1), out.rowCount()); // the window: 1 row read
    try t.expectEqual(@as(f64, 20), out.row(0)[out.indexOf("k").?].num);
    try t.expectEqual(@as(f64, 3), x.pdv.get("n").?.num); // PHYSICAL count
}

test "POINT= + WHERE= dsopt fails LOUD (BUG-pointwheredsopt); POINT=/NOBS= keep the PHYSICAL base under obs= (BUG-pointnobsbase)" {
    // Statements ref, SET POINT= Restrictions (printed p.335): "You cannot use
    // POINT= with a BY statement, a WHERE statement, or a WHERE= data set
    // option." The first two legs already failed loud; the THIRD was silently
    // accepted — the BUG-pointnobsbase pin below was made BEFORE this repo had
    // the Statements volume and encoded a semantic (where= silently dropped,
    // read the PHYSICAL base) for a combination the doc forbids outright.
    // RETIRED: that where=-drop semantic. KEPT: NOBS= physical + POINT=
    // physical under obs= — obs= is not in the restriction.
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const d_ds = f.newDs("d");
    _ = try d_ds.addColumn("v", .num);
    for (1..6) |k| try d_ds.appendRow(&.{.{ .num = @floatFromInt(k) }});
    try f.lib.put("d", d_ds);

    const drop_helper = [_][]const u8{"_setobs_"}; // the parser injects `drop _setobs_;` on any SET step
    const empty_out = [_][]const u8{};

    // LEGAL, unchanged (FIRST — the run-level errhalt gates any step compiled
    // after an ERROR, so the loud arm cannot precede this on one fixture):
    // `set d(obs=2) point=i nobs=n;` — obs= is NOT in the p.335 restriction.
    // NOBS= reports the physical 5 and POINT= reads PHYSICAL obs 3 (v=3 — the
    // obs=-sliced copy holds only v=1,2): one base, no contradiction (the
    // still-legal half of the BUG-pointnobsbase pin).
    const names_ok = [_][]const u8{ "d(obs=2)", "\x00point=i" };
    const prog_ok = [_]ast.Stmt{
        .{ .drop = &drop_helper },
        .{ .assign = .{ .target = "i", .value = f.num(3) } },
        .{ .set = &names_ok },
        .{ .output = &empty_out },
        .{ .assign = .{ .target = "n", .value = f.vbl("_setobs_") } }, // parser's nobs=n desugar
    };
    var out = Dataset.init(f.a(), "w2");
    try x.run(&prog_ok, &out);
    try t.expect(!f.diags.hasErrors());
    try t.expectEqual(@as(usize, 1), out.rowCount());
    try t.expectEqual(@as(f64, 3), out.row(0)[out.indexOf("v").?].num); // PHYSICAL obs 3, not the obs=-sliced copy
    try t.expectEqual(@as(f64, 5), x.pdv.get("n").?.num); // NOBS= physical — the SAME base

    // data w; i=3; set d(where=(v>3)) point=i nobs=n; output; run; — ILLEGAL:
    // loud captured ERROR (D-003), spent driver, no rows — the same policy as
    // the WHERE-statement leg above it, never a silent physical read.
    var x2 = f.exec();
    const names_bad = [_][]const u8{ "d(where=(v>3))", "\x00point=i" };
    const prog_bad = [_]ast.Stmt{
        .{ .drop = &drop_helper },
        .{ .assign = .{ .target = "i", .value = f.num(3) } },
        .{ .set = &names_bad },
        .{ .output = &empty_out },
        .{ .assign = .{ .target = "n", .value = f.vbl("_setobs_") } }, // parser's nobs=n desugar
    };
    var out_bad = Dataset.init(f.a(), "w");
    try x2.run(&prog_bad, &out_bad); // report + spent driver: run completes
    try t.expect(f.diags.hasErrors()); // captured ERROR, not a process abort
    try t.expectEqualStrings("The WHERE= data set option cannot be used with the POINT= option", f.diags.list.items[f.diags.list.items.len - 1].message);
    try t.expectEqual(@as(usize, 0), out_bad.rowCount()); // no silent rows
}

test "SET point=/nobs= temp vars drop from the output schema (BUG-setpointtemp)" {
    // Pure control temps: `p = 1; set a point=p nobs=n; output;` — p/n are SAS-
    // temporary, b carries a's columns only; the direct read still lands.
    // (Explicit OUTPUT: with POINT= there is no implicit one —
    // BUG-pointautooutput.)
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const a_ds = f.newDs("a");
        _ = try a_ds.addColumn("k", .num);
        try a_ds.appendRow(&.{.{ .num = 7 }});
        try f.lib.put("a", a_ds);

        const names = [_][]const u8{ "a", "\x00point=p" };
        const drop_helper = [_][]const u8{"_setobs_"}; // the parser injects `drop _setobs_;` on any SET step
        const empty_out = [_][]const u8{};
        const prog = [_]ast.Stmt{
            .{ .drop = &drop_helper },
            .{ .assign = .{ .target = "p", .value = f.num(1) } },
            .{ .set = &names },
            .{ .output = &empty_out },
            .{ .assign = .{ .target = "n", .value = f.vbl("_setobs_") } }, // parser's nobs=n desugar
        };
        var out = Dataset.init(f.a(), "b");
        try x.run(&prog, &out);
        try t.expectEqual(@as(usize, 1), out.rowCount()); // point read of obs p=1
        try t.expectEqual(@as(usize, 1), out.columns.items.len); // k only — p/n dropped
        try t.expectEqualStrings("k", out.columns.items[0].name);
        try t.expectEqual(@as(f64, 7), out.row(0)[0].num);
    }
    // Collision: the point var is ALSO a genuine input column → NOT dropped.
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const a_ds = f.newDs("a");
        _ = try a_ds.addColumn("p", .num); // real data var sharing the point= name
        try a_ds.appendRow(&.{.{ .num = 1 }});
        try f.lib.put("a", a_ds);

        const names = [_][]const u8{ "a", "\x00point=p" };
        const drop_helper = [_][]const u8{"_setobs_"};
        const empty_out = [_][]const u8{};
        const prog = [_]ast.Stmt{
            .{ .drop = &drop_helper },
            .{ .assign = .{ .target = "p", .value = f.num(1) } },
            .{ .set = &names },
            .{ .output = &empty_out }, // no implicit output with POINT= (BUG-pointautooutput)
            .{ .assign = .{ .target = "n", .value = f.vbl("_setobs_") } },
        };
        var out = Dataset.init(f.a(), "b");
        try x.run(&prog, &out);
        try t.expectEqual(@as(usize, 1), out.rowCount());
        try t.expectEqual(@as(usize, 1), out.columns.items.len); // p stays (real data); n dropped
        try t.expectEqualStrings("p", out.columns.items[0].name);
    }
}

fn countWarnings(d: *const diag.Diagnostics) usize {
    var n: usize = 0;
    for (d.list.items) |x| if (x.severity == .warning) {
        n += 1;
    };
    return n;
}

test "GH#69 SET stacks char+numeric var → fatal, 0 obs (captured reporter, D-003)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a"); // a.x is CHARACTER
    _ = try a_ds.addColumn("x", .char);
    try a_ds.appendRow(&.{.{ .str = "abc" }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b"); // b.x is NUMERIC — conflict
    _ = try b_ds.addColumn("x", .num);
    try b_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("b", b_ds);

    const names = [_][]const u8{ "a", "b" };
    const prog = [_]ast.Stmt{.{ .set = &names }};
    var out = Dataset.init(f.a(), "c");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasStepErrors()); // halts the step, no spawned abort
    try t.expectEqual(@as(usize, 0), out.rowCount()); // finalized with 0 obs
}

test "GH#70 char LENGTH after SET on a numeric var → fatal; before SET is lenient" {
    // FATAL: `set tmpl; length CMROUTE $24;` — LENGTH follows the SET (after_input).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const tmpl = f.newDs("tmpl"); // CMROUTE numeric
        _ = try tmpl.addColumn("CMROUTE", .num);
        try tmpl.appendRow(&.{.{ .num = 0 }});
        try f.lib.put("tmpl", tmpl);
        x.declared = &[_]DeclVar{.{ .name = "CMROUTE", .type = .char, .len = 24, .after_input = true }};
        const names = [_][]const u8{"tmpl"};
        const prog = [_]ast.Stmt{.{ .set = &names }};
        var out = Dataset.init(f.a(), "a");
        try x.run(&prog, &out);
        try t.expect(f.diags.hasStepErrors());
        try t.expectEqual(@as(usize, 0), out.rowCount());
    }
    // LENIENT: `length CMROUTE $24; set tmpl;` — schema-pin before the SET. opensas
    // coerces (CSV type inference makes source types unreliable — real SDTM domains).
    {
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const tmpl = f.newDs("tmpl");
        _ = try tmpl.addColumn("CMROUTE", .num);
        try tmpl.appendRow(&.{.{ .num = 0 }});
        try f.lib.put("tmpl", tmpl);
        x.declared = &[_]DeclVar{.{ .name = "CMROUTE", .type = .char, .len = 24, .after_input = false }};
        const names = [_][]const u8{"tmpl"};
        const prog = [_]ast.Stmt{.{ .set = &names }};
        var out = Dataset.init(f.a(), "a");
        try x.run(&prog, &out);
        try t.expect(!f.diags.hasStepErrors()); // no halt
        try t.expectEqual(@as(usize, 1), out.rowCount()); // row survives
    }
}

test "GH#72 SET sources with different char lengths → WARNING, first length kept" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a"); // x Char 5
    _ = try a_ds.addColumn("x", .char);
    a_ds.setLen("x", 5);
    try a_ds.appendRow(&.{.{ .str = "abcde" }});
    try f.lib.put("a", a_ds);
    const b_ds = f.newDs("b"); // x Char 20 — differing length
    _ = try b_ds.addColumn("x", .char);
    b_ds.setLen("x", 20);
    try b_ds.appendRow(&.{.{ .str = "abcdefghij" }});
    try f.lib.put("b", b_ds);

    const names = [_][]const u8{ "a", "b" };
    const prog = [_]ast.Stmt{.{ .set = &names }};
    var out = Dataset.init(f.a(), "c");
    try x.run(&prog, &out);
    try t.expect(!f.diags.hasStepErrors()); // WARNING, not fatal
    try t.expect(countWarnings(&f.diags) >= 1);
    try t.expectEqual(@as(usize, 2), out.rowCount());
    // FIRST length wins: the PDV var x keeps length 5 (b's row truncates on load)
    try t.expectEqual(@as(usize, 5), f.pdv.vars.items[f.pdv.indexOf("x").?].len);
}

test "GH#71 input-side drop= of a never-referenced var is fatal (DKRICOND=ERROR), 0 obs" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    const a_ds = f.newDs("a");
    _ = try a_ds.addColumn("x", .num);
    try a_ds.appendRow(&.{.{ .num = 1 }});
    try f.lib.put("a", a_ds);

    // `set a (drop=NOTHERE)` — NOTHERE is on no column of an INPUT dataset.
    const names = [_][]const u8{"a(drop=NOTHERE)"};
    const prog = [_]ast.Stmt{.{ .set = &names }};
    var out = Dataset.init(f.a(), "b");
    try x.run(&prog, &out);
    try t.expect(f.diags.hasStepErrors()); // captured, not a spawned abort (D-003)
    try t.expectEqual(@as(usize, 0), out.rowCount()); // step aborted, 0 obs
}

test "hash ordered: parse + key-sort (BUG-hashordered)" {
    try t.expectEqual(HashOrder.asc, parseHashOrder(.{ .str = "a" }));
    try t.expectEqual(HashOrder.asc, parseHashOrder(.{ .str = "yes" }));
    try t.expectEqual(HashOrder.desc, parseHashOrder(.{ .str = "d" }));
    try t.expectEqual(HashOrder.none, parseHashOrder(.{ .str = "no" }));
    try t.expectEqual(HashOrder.none, parseHashOrder(.{ .num = 0 }));
    try t.expectEqual(HashOrder.asc, parseHashOrder(.{ .num = 1 }));

    // entries inserted 30,10,20 must iterate ascending / descending, not by insert
    var h = HashObject{ .name = "h", .ordered = .asc };
    for ([_]f64{ 30, 10, 20 }) |x| {
        const kv = try t.allocator.alloc(Value, 1); // distinct storage per entry
        kv[0] = .{ .num = x };
        try h.entries.append(t.allocator, .{ .keyvals = kv, .datavals = &.{} });
    }
    defer {
        for (h.entries.items) |e| t.allocator.free(e.keyvals);
        h.entries.deinit(t.allocator);
    }
    hashSortEntries(&h);
    try t.expectEqual(@as(f64, 10), h.entries.items[0].keyvals[0].num);
    try t.expectEqual(@as(f64, 30), h.entries.items[2].keyvals[0].num);
    h.ordered = .desc;
    hashSortEntries(&h);
    try t.expectEqual(@as(f64, 30), h.entries.items[0].keyvals[0].num);
    try t.expectEqual(@as(f64, 10), h.entries.items[2].keyvals[0].num);
}

test "SELECT with no OTHERWISE and no matching WHEN fails LOUD via captured reporter (BUG-selectnomatch)" {
    var f = fixture();
    defer f.deinit();
    f.prime();
    var x = f.exec();

    // The parser desugars a no-match/no-OTHERWISE SELECT's terminal else to this node.
    const prog = [_]ast.Stmt{.select_nomatch};
    var out = Dataset.init(f.a(), "work.out");
    try t.expectError(error.ExecError, x.run(&prog, &out)); // aborts the step
    try t.expect(f.diags.hasStepErrors()); // captured diagnostic, not a spawned abort (D-003)
}

// ── D-009 exit-code contract, exec.zig's slice (GAP-gapsexitingone §5c) ──────
//
// Every arm below is pinned against `diag.exitCode(gapHit, hasErrors)` — the
// two signals main.zig:89-90 actually read — through the D-003 CAPTURED
// reporter, never a spawned process. `tests/corpus/rc_*.sas` pin the same
// verdicts end-to-end through main's exit path so the two surfaces can't drift.

/// The rc a finished step would produce, from the run's two D-009 signals.
fn rcOf(f: *Fixture) u8 {
    return diag.exitCode(diag.gapHit(), f.diags.hasErrors());
}

test "D-009 §5c: the closed doc lists that SPLIT a gap from a typo are exactly the reference's own" {
    // isHashMethod — Component Objects ref, the dictionary's own TOC (p.23).
    // Documented but unimplemented → the gap arm.
    for ([_][]const u8{ "do_over", "equals", "find_prev", "has_next", "has_prev", "ref", "removedup", "replacedup", "reset_dup", "setcur", "sum", "sumdup" }) |m|
        try t.expect(isHashMethod(m));
    try t.expect(isHashMethod("ADD")); // case-insensitive, like every SAS name
    // …and the typo arm STAYS reachable: near-misses of real method names.
    for ([_][]const u8{ "fnd", "find_nxt", "reset_dupe", "num_item", "" }) |m|
        try t.expect(!isHashMethod(m));

    // isCallRoutine — Functions ref `CALL <NAME> Routine` headings.
    for ([_][]const u8{ "compcost", "module", "poke", "pokelong", "prxdebug", "sleep", "system", "tso", "wto", "set", "is8601_convert" }) |r|
        try t.expect(isCallRoutine(r));
    try t.expect(isCallRoutine("SYMPUT"));
    for ([_][]const u8{ "symptu", "misssing", "sortnn", "" }) |r|
        try t.expect(!isCallRoutine(r));

    // stdizeOptKind — Functions ref p.419-421, all three option categories, and
    // (BUG-callstdizeoptmsg) which category each lands in: only the first is a
    // METHOD, and the split is what keeps `mult=2` from being called one.
    for ([_][]const u8{ "mean", "median", "euclen", "iqr", "mad", "maxabs", "midrange", "range", "std", "sum", "ustd", "abw", "agk", "ahuber", "awave", "l", "spacing" }) |o|
        try t.expectEqual(StdizeOptKind.standardization, stdizeOptKind(o).?);
    for ([_][]const u8{ "df", "n" }) |o|
        try t.expectEqual(StdizeOptKind.vardef, stdizeOptKind(o).?);
    for ([_][]const u8{ "add", "fuzz", "missing", "mult", "norm", "pstat", "replace", "snorm" }) |o|
        try t.expectEqual(StdizeOptKind.miscellaneous, stdizeOptKind(o).?);
    for ([_][]const u8{ "medain", "rnage", "stdd", "" }) |o|
        try t.expect(stdizeOptKind(o) == null);
}

test "D-009 §5c: a valid-SAS DATA-step shape exec.zig doesn't model exits 2, not 1" {
    // `do i=1 to 3; set a; end;` — real SAS reads one obs per iteration.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const nx = [_][]const u8{"a"};
        const body = [_]ast.Stmt{.{ .set = &nx }};
        const prog = [_]ast.Stmt{.{ .do_ = .{
            .header = .{ .iter = .{ .name = "i", .start = f.num(1), .stop = f.num(3), .by = null } },
            .body = &body,
        } }};
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // A DOW loop plus a second SET — several SET statements in one step is
    // ordinary SAS; opensas models exactly one DOW read.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const nx = [_][]const u8{"a"};
        const body = [_]ast.Stmt{.{ .set = &nx }};
        const prog = [_]ast.Stmt{
            .{ .do_ = .{ .header = .{ .until_ = f.vbl("eof") }, .body = &body } },
            .{ .set = &nx },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // A MERGE driving a DOW loop: real SAS accepts it, so stopping rather than
    // spinning is OUR limit — macro.zig's iterative-%DO gap, exactly (D-009b i).
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const nm = [_][]const u8{ "a", "b" };
        const body = [_]ast.Stmt{.{ .merge = &nm }};
        const prog = [_]ast.Stmt{.{ .do_ = .{ .header = .{ .until_ = f.vbl("z") }, .body = &body } }};
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // `modify a point=p;` — Statements ref p.240-241 Form 3. Only end=/point=
    // sentinels can reach the guard (the parser rejects any other name= at rc 1).
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        try f.lib.put("a", f.newDs("a"));
        const nm = [_][]const u8{ "a", "\x00point=p" };
        const prog = [_]ast.Stmt{.{ .modify = &nm }};
        var out = Dataset.init(f.a(), "a");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // A second POINT= source: valid SAS, one direct-access source is our limit.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        try f.lib.put("a", f.newDs("a"));
        try f.lib.put("b", f.newDs("b"));
        const n1 = [_][]const u8{ "a", "\x00point=p" };
        const n2 = [_][]const u8{ "b", "\x00point=q" };
        const prog = [_]ast.Stmt{ .{ .set = &n1 }, .{ .set = &n2 } };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // A GOTO that jumps over the driving SET — legal SAS control flow.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const a_ds = f.newDs("a");
        _ = try a_ds.addColumn("k", .num);
        try a_ds.appendRow(&.{.{ .num = 1 }});
        try f.lib.put("a", a_ds);
        const nx = [_][]const u8{"a"};
        const prog = [_]ast.Stmt{
            .{ .goto = "skip" },
            .{ .set = &nx },
            .{ .label = "skip" },
            .{ .assign = .{ .target = "y", .value = f.num(1) } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // OUTPUT inside a MODIFY step — the MODIFY entry itself documents it
    // ("writes the current observation to the end of all data sets").
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const a_ds = f.newDs("a");
        _ = try a_ds.addColumn("k", .num);
        try a_ds.appendRow(&.{.{ .num = 1 }});
        try f.lib.putInput("a", a_ds);
        const nm = [_][]const u8{"a"};
        const empty_out = [_][]const u8{};
        const prog = [_]ast.Stmt{ .{ .modify = &nm }, .{ .output = &empty_out } };
        var out = Dataset.init(f.a(), "a");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
}

test "D-009 §5c: hash gaps exit 2; a typo'd hash method still exits 1" {
    // `suminc:` / `keysum:` are LEGAL declaration tags (component-objects ref
    // p.32-33) whose summaries we don't maintain → gap.
    for ([_][]const u8{ "suminc", "keysum" }) |tag| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.HashArg{.{ .name = tag, .value = f.e(.{ .str = "s" }) }};
        const prog = [_]ast.Stmt{.{ .hash_decl = .{ .name = "h", .args = &args } }};
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // SPLIT, gap arm: a method the reference's dictionary NAMES.
    for ([_][]const u8{ "setcur", "reset_dup", "removedup", "ref" }) |m| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const no_args = [_]ast.HashArg{};
        const prog = [_]ast.Stmt{
            .{ .hash_decl = .{ .name = "h", .args = &no_args } },
            .{ .hash_op = .{ .target = "rc", .obj = "h", .method = m, .args = &no_args } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // SPLIT, typo arm: NOT a documented method → the user's error, rc 1. This
    // is the half a wholesale re-tag would have broken.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const no_args = [_]ast.HashArg{};
        const prog = [_]ast.Stmt{
            .{ .hash_decl = .{ .name = "h", .args = &no_args } },
            .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "fnd", .args = &no_args } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 1), rcOf(&f));
    }
    // A hash of hashes is documented SAS; storing one as a data item is our gap.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const no_args = [_]ast.HashArg{};
        const key = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "k" }) }};
        const dat = [_]ast.HashArg{.{ .name = null, .value = f.e(.{ .str = "inner" }) }};
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "k", .value = f.num(1) } },
            .{ .hash_decl = .{ .name = "inner", .args = &no_args } },
            .{ .hash_decl = .{ .name = "h", .args = &no_args } },
            .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineKey", .args = &key } },
            .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineData", .args = &dat } },
            .{ .hash_op = .{ .target = null, .obj = "h", .method = "defineDone", .args = &no_args } },
            .{ .hash_op = .{ .target = "rc", .obj = "h", .method = "add", .args = &no_args } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
}

test "D-009 §5c: an unwritten CALL routine exits 2; a misspelled one still exits 1" {
    // SPLIT, gap arm: names the Functions ref's dictionary lists.
    for ([_][]const u8{ "compcost", "module", "wto", "sleep", "is8601_convert" }) |r| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.Expr{.{ .num = 1 }};
        const prog = [_]ast.Stmt{.{ .call_ = .{ .name = r, .args = &args } }};
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // SPLIT, typo arm: a misspelling must NOT be told to file an opensas issue.
    for ([_][]const u8{ "symptu", "misssing" }) |r| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.Expr{.{ .num = 1 }};
        const prog = [_]ast.Stmt{.{ .call_ = .{ .name = r, .args = &args } }};
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 1), rcOf(&f));
    }
    // CALL EXECUTE with %nrstr — the reference TIPs this exact call as the
    // documented workaround, so refusing it is our gap.
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.Expr{.{ .str = "%nrstr(%foo)" }};
        const prog = [_]ast.Stmt{.{ .call_ = .{ .name = "execute", .args = &args } }};
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    // CALL STDIZE SPLIT — a documented option (bare, `method=`-prefixed, or
    // carrying an `=value` tail) is a gap; a misspelling stays the user's error.
    for ([_][]const u8{ "median", "method=median", "euclen", "mult=2", "df" }) |opt| {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.Expr{ .{ .str = opt }, .{ .variable = "v" } };
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "v", .value = f.num(1) } },
            .{ .call_ = .{ .name = "stdize", .args = &args } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 2), rcOf(&f));
    }
    {
        diag.resetGap();
        var f = fixture();
        defer f.deinit();
        f.prime();
        var x = f.exec();
        const args = [_]ast.Expr{ .{ .str = "medain" }, .{ .variable = "v" } };
        const prog = [_]ast.Stmt{
            .{ .assign = .{ .target = "v", .value = f.num(1) } },
            .{ .call_ = .{ .name = "stdize", .args = &args } },
        };
        var out = Dataset.init(f.a(), "o");
        try t.expectError(error.ExecError, x.run(&prog, &out));
        try t.expectEqual(@as(u8, 1), rcOf(&f));
    }
    diag.resetGap(); // leave the process-global clean for whatever test runs next
}
