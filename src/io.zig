//! Dataset I/O — the bytes-in/rows-out layer the executor (C1) drives.
//!
//! Three jobs, all mechanism (the executor owns the *policy* — the DATA-step
//! loop, drop/keep, `_ERROR_`):
//!
//!   readList   raw `datalines` text + an `input` list → PDV cells (list input)
//!   loadRow    a prior `Dataset` observation → PDV cells (`set`)
//!   snapshot   the current PDV → one `Dataset` row (implicit/explicit output)
//!
//! plus `seedColumns`, which stamps a Dataset's schema from a PDV. Char bytes:
//! `readList` *borrows* its tokens from the caller's line (valid while that line
//! lives — `datalines` are arena-long-lived); `snapshot` is where they get duped
//! into the output dataset, via `Dataset.appendRow`. So the PDV never owns char
//! bytes — it points at whatever fed it, and the copy happens at the write.

const std = @import("std");
const ast = @import("ast.zig");
const lex = @import("lexer.zig");
const diag = @import("diag.zig");
const eval = @import("eval.zig");
const format = @import("format.zig");
const pe = @import("parser_expr.zig");
const sql = @import("sql.zig"); // GH#35: reuse the SQL predicate desugaring for where=
const functions = @import("functions.zig"); // BUG-wherefunc: where= predicates dispatch real functions
const Value = @import("value.zig").Value;
const dsfns = @import("dsfns.zig"); // bound librefs, for the VTABLE disk sweep
const Pdv = @import("pdv.zig").Pdv;
const missingOf = @import("pdv.zig").missingOf;
const Dataset = @import("dataset.zig").Dataset;
const xport = @import("xport.zig");

// ── global OBS=/FIRSTOBS= system options (BUG-globalobs) ─────────────────────
// `options obs=N;` / `options firstobs=N;` set the DEFAULT last/first obs for
// EVERY subsequent input read until reset (`options obs=max;` restores all-obs;
// Language Reference: Concepts p.247 — they exist as system options, not just dataset options). A
// per-dataset (obs=)/(firstobs=) still overrides, field by field. Module state
// like format.noFmtErr: one program run = one options state. main.zig's OPTIONS
// handler writes these; applyDatasetOptions reads them on `input` reads.
pub var global_firstobs: usize = 1;
pub var global_obs: usize = std.math.maxInt(usize);

/// True when a global OBS=/FIRSTOBS= bound is in effect (anything to apply).
pub fn globalObsActive() bool {
    return global_firstobs > 1 or global_obs != std.math.maxInt(usize);
}

// ── global MISSING=/LINESIZE=/PAGESIZE= system options ───────────────────────
/// `options missing='X';` — the display char for a PLAIN missing numeric
/// (Language Reference: Concepts p.209/234; BUG-optmissing: parsed then DROPPED → every listing kept
/// printing `.` = silent wrong display). `missing='.'` resets to the default
/// `.`; `missing=' '` (and `''`, which the lexer maps to " " per GH#60) sets a
/// blank. Special missings (.A–.Z/._) keep their own letter — the render sites
/// (main.zig fmtValue for PROC PRINT, exec.zig appendValue for PUT) only
/// substitute when Value.missingChar is '.'. Module state like global_obs
/// above. ponytail: explicit-format renders (`format x 8.2;`) still print `.` —
/// that path is format.zig's renderNum, wire it there if a study sets MISSING=
/// together with explicit formats.
pub var global_missing: u8 = '.';

/// `options linesize=N pagesize=N;` — captured + validated (GAP-listingwidth).
/// INERT: no listing proc wraps/paginates to them yet (accepted, not an error —
/// output is data-correct, just unpaginated). 0 = unset. Read these when a
/// PROC PRINT panel-split lands.
pub var global_linesize: usize = 0;
pub var global_pagesize: usize = 0;

// ── global DKRICOND=/DKROCOND= system options (BUG-optionsstmtswallow) ──────
/// Severity when a DROP=/KEEP=/RENAME= names a variable missing from an INPUT
/// (DKRICOND=, Language Reference: Concepts p.184) vs OUTPUT (DKROCOND=, Language Reference: Concepts p.185) dataset. SAS 9.4
/// defaults ERROR / WARN respectively (GH#71). Read by reportUnreferenced.
pub const CondLevel = enum { err, warn, nowarn };
pub var global_dkricond: CondLevel = .err;
pub var global_dkrocond: CondLevel = .warn;

// ── global BYLINE/NOBYLINE + SORTSEQ= system options (BUG-optionsstmtswallow) ─
/// NOBYLINE suppresses the BY line atop each BY group's listing. Read by the
/// BY-line stampers (main.zig printByLine, proc.zig appendByLine).
pub var global_nobyline: bool = false;
/// SORTSEQ=LINGUISTIC supplies the DEFAULT collation for PROC SORT (Language Reference: Concepts
/// p.533; proc.zig BUG-sortseq). ASCII (byte order) is the default.
pub var global_sortseq_linguistic: bool = false;

/// An OBS=/FIRSTOBS= value at toks[j]: an integer, optionally with a K/M/G
/// suffix (×1024ⁿ — `obs=2k` is 2048, never 2), MAX (all observations), or MIN
/// (1). null on anything else — the caller fails LOUD naming the option
/// (BUG-optionsstmtswallow / BUG-dsobsvaluenovalidate: `obs=abc` silently read
/// EVERY row on both the system and the dataset-option path).
pub const ObsValue = struct { val: usize, consumed: usize };
pub fn parseObsValue(toks: []const lex.Token, j: usize) ?ObsValue {
    if (j >= toks.len) return null;
    const t = toks[j];
    if (t.tag == .name) {
        if (eqiTok(t.text, "max")) return .{ .val = std.math.maxInt(usize), .consumed = 1 };
        if (eqiTok(t.text, "min")) return .{ .val = 1, .consumed = 1 };
        return null;
    }
    if (t.tag != .number) return null;
    var val = std.fmt.parseInt(usize, t.text, 10) catch return null;
    var consumed: usize = 1;
    // A K/M/G suffix lexes as a SEPARATE one-char name token (`2k` → `2` `k`).
    if (j + 1 < toks.len and toks[j + 1].tag == .name and toks[j + 1].text.len == 1) {
        const mult: usize = switch (std.ascii.toLower(toks[j + 1].text[0])) {
            'k' => 1024,
            'm' => 1024 * 1024,
            'g' => 1024 * 1024 * 1024,
            else => 0,
        };
        if (mult != 0) {
            val = std.math.mul(usize, val, mult) catch return null;
            consumed = 2;
        }
    }
    return .{ .val = val, .consumed = consumed };
}
const sas7bdat = @import("sas7bdat.zig");

/// LIBNAME engine hook: read an XPORT (`.xpt`) file's bytes as a Dataset. The
/// reader lives in `xport.zig`; this is the io-layer entry the loader calls.
pub fn readXport(a: std.mem.Allocator, bytes: []const u8, name: []const u8) xport.Error!*Dataset {
    return xport.read(a, bytes, name);
}

/// LIBNAME engine hook: serialize a Dataset to XPORT v5 (`.xpt`) bytes — the write
/// side of readXport, for `libname o xport "f.xpt"; data o.x; …` (CLIN-xptwrite).
pub fn writeXport(a: std.mem.Allocator, ds: *const Dataset) xport.Error![]const u8 {
    return xport.write(a, ds);
}

/// LIBNAME engine hook: read a native sas7bdat (`.sas7bdat`) file as a Dataset.
/// The reader lives in `sas7bdat.zig`; this is the io-layer entry the loader calls.
pub fn readSas7bdat(a: std.mem.Allocator, bytes: []const u8, name: []const u8) sas7bdat.Error!*Dataset {
    return sas7bdat.read(a, bytes, name);
}

/// LIBNAME engine hook: serialize a Dataset to native sas7bdat bytes — the write
/// side of readSas7bdat, now the DEFAULT directory-LIBNAME output format so
/// variable type/length survive a TARGET reload (E-sas7write-hookup: CSV carried
/// no metadata, so all-digit char like '007' was re-typed Num on reload).
pub fn writeSas7bdat(a: std.mem.Allocator, ds: *const Dataset) sas7bdat.Error![]const u8 {
    return sas7bdat.write(a, ds);
}

/// Extensions a directory LIBNAME probes for a member, binary (metadata-carrying)
/// engines FIRST so a `.sas7bdat`/`.xpt` TARGET is preferred over a legacy/staging
/// `.csv` when both exist (E-sas7write-hookup); `.csv` remains for staging inputs.
pub const member_exts = [_][]const u8{ ".sas7bdat", ".xpt", ".csv" };

/// Pick a dataset reader by `path`'s extension and parse `bytes` into a Dataset
/// named `name`: `.csv` → CSV, `.xpt` → XPORT, `.sas7bdat` → sas7bdat. Returns
/// null for any other extension. This is the single place that maps a filename
/// to an engine, for both directory members (`dir/member.ext`) and a libref
/// pointed straight at one file.
pub fn readByExt(a: std.mem.Allocator, path: []const u8, bytes: []const u8, name: []const u8) (sas7bdat.Error || xport.Error || diag.Error)!?*Dataset {
    if (endsWithIgnoreCase(path, ".csv")) return try readCsv(a, bytes, name);
    if (endsWithIgnoreCase(path, ".xpt")) return try xport.read(a, bytes, name);
    if (endsWithIgnoreCase(path, ".sas7bdat")) return try sas7bdat.read(a, bytes, name);
    return null;
}

/// True if `s` ends with `suffix`, case-insensitively (file extensions).
pub fn endsWithIgnoreCase(s: []const u8, suffix: []const u8) bool {
    return s.len >= suffix.len and eqi(s[s.len - suffix.len ..], suffix);
}

/// The ONE member name a FILE-libref file actually holds. An XPORT v5 file
/// stamps it in the first DSCRPTR record — fixed layout: LIBRARY hdr + 2 recs
/// (240), MEMBER hdr (80), DSCRPTR hdr (80), then a descriptor record whose
/// bytes 8..16 are the ≤8-char blank-padded member name (xport.zig writes it).
/// A `.sas7bdat` exposes no cheap stamped name to this reader (our writer
/// doesn't stamp one), so fall back to the filename stem — SAS names the file
/// `<member>.sas7bdat`, so the stem IS the member name in practice. Lets a
/// FILE libref refuse a typo'd member name (BUG-filelibrefmember) instead of
/// silently serving the one file under any alias.
/// The member name stamped in an XPORT v5 file's first DSCRPTR record, or
/// null when `bytes` carry none (too short / no MEMBER header / blank stamp).
/// Fixed layout: LIBRARY hdr + 2 recs (240), MEMBER hdr (80), DSCRPTR hdr
/// (80), then a descriptor record whose bytes 8..16 are the ≤8-char
/// blank-padded member name (xport.zig writes it).
pub fn xptStampedMember(bytes: []const u8) ?[]const u8 {
    if (bytes.len >= 416 and std.mem.startsWith(u8, bytes[240..], "HEADER RECORD*******MEMBER")) {
        const mem = std.mem.trimEnd(u8, bytes[408..416], " ");
        if (mem.len > 0) return mem;
    }
    return null;
}

pub fn stampedMemberName(path: []const u8, bytes: []const u8) []const u8 {
    if (endsWithIgnoreCase(path, ".xpt")) {
        if (xptStampedMember(bytes)) |mem| return mem;
    }
    const base = std.fs.path.basename(path);
    return if (std.mem.lastIndexOfScalar(u8, base, '.')) |dot| base[0..dot] else base;
}

/// SAS list input, reading one field per `input` item (in order) from the
/// whitespace-delimited tokens of `lines[start]`. When a line runs dry before
/// every item is filled, reading *spills onto the next line* — SAS's default
/// (not MISSOVER). A `$` item takes the token verbatim; a numeric item parses
/// as `f64` (`.`/junk → missing); running out of lines too → missing.
///
/// Returns the HIGH-WATER index of the lines read from (a backward `#n` leaves
/// the cursor earlier). The caller advances past it so the next observation
/// starts on a fresh record — leftover tokens on that line are dropped, as SAS
/// does without a trailing `@@`.
///
/// `missover` rejects a PARTIAL formatted/column field: a `w.`/range read the
/// record ends inside of yields missing (SAS 9.4 MISSOVER), while TRUNCOVER
/// (`missover = false`) keeps the truncated partial (BUG-missovertruncover-
/// partial). The record-windowing that makes short-record values read missing
/// at all lives in the caller (exec.zig, BUG-infilemissover).
///
/// ponytail: invalid numeric list-input data should raise a NOTE + set `_ERROR_`
///   — silent until the log is under test. (Char length now honoured:
///   see `listCharValue`, BUG-inputlistlen / BUG-coloninformatwidth.)
/// Length + truncation for a list / DSD CHARACTER read, returning the value to
/// store:
/// - explicit informat width `w>0` (colon-modified `:$w.`): the var takes length
///   `w` (if undeclared) and the token is truncated to `w` — the informat governs
///   how many chars are read (BUG-coloninformatwidth). A declared LENGTH stays as
///   storage; `setAt` truncates the store to it, but the read still stops at w.
/// - no informat width, undeclared: SAS's default char length of 8, so `setAt`
///   truncates this and every later value to 8 (BUG-inputlistlen).
/// - declared width (LENGTH/ATTRIB → `vr.len>0`, no informat): left untouched.
fn listCharValue(pdv: *Pdv, slot: usize, informat: ?[]const u8, tok: []const u8) []const u8 {
    const vr = &pdv.vars.items[slot];
    // BUG-charinformatloud: a list/delim char read with an unknown $-informat
    // fails loud instead of copying the token verbatim (D-002).
    format.checkCharInformat(informatName(informat orelse ""));
    const w = format.parseSpec(informat orelse "").w;
    if (w > 0) {
        if (vr.len == 0) vr.len = w;
        return if (tok.len > w) tok[0..w] else tok;
    }
    if (vr.len == 0) vr.len = 8; // BUG-inputlistlen default
    return tok;
}

/// Language Reference: Concepts p.171: "NOTE: SAS went to a new line when INPUT statement reached past
/// the end of a line." — written when FLOWOVER moves a read onto the next record
/// (any input style). pdv.diags is null in standalone/unit uses.
/// PERF-flownoteperrecord: one NOTE per flow EVENT is one allocPrint into the
/// never-freed run arena + one Diagnostic append per event — measured ~385 ns
/// and ~259 retained bytes per flow; a 2M-record flowing file paid 2.45x wall
/// and 2.05x RSS for a million byte-identical NOTEs. Real SAS caps repeated
/// log messages, so cap this one at FLOW_NOTE_MAX per input stream and say so
/// once with a closing suppression NOTE — bounded but never silent (the NOTE
/// exists because a flow means INPUT ran off a record, which a user must see).
/// io.zig owns no step boundary, so the stream is identified by its line
/// buffer and monotonic record index: a new DATA step / INFILE gets a fresh
/// arena buffer or rewinds the index, and either re-arms the budget.
/// ponytail: a step ALTERNATING two infiles re-arms per switch (each switch
/// looks like a new stream); a run-wide ceiling would live in diag.zig — add
/// it there if a real program ever hits that shape.
var flow_note_count: usize = 0;
var flow_note_lines: ?[*]const []const u8 = null;
var flow_note_li: usize = 0;

const FLOW_NOTE_MAX = 20;

fn flowNote(pdv: *Pdv, lines: []const []const u8, li: usize) void {
    const d = pdv.diags orelse return;
    if (lines.ptr != flow_note_lines or li < flow_note_li) {
        flow_note_count = 0;
        flow_note_lines = lines.ptr;
    }
    flow_note_li = li;
    if (flow_note_count >= FLOW_NOTE_MAX) return;
    flow_note_count += 1;
    d.report(.note, 0, "SAS went to a new line when INPUT statement reached past the end of a line.", .{}) catch {};
    if (flow_note_count == FLOW_NOTE_MAX)
        d.report(.note, 0, "Further 'SAS went to a new line' notes are suppressed for this input.", .{}) catch {};
}

/// FLOWOVER's record advance — the ONE place that decides what "go to the next
/// input data record" means, shared by the whitespace reader (readList) and the
/// delimited reader (readDelim). Steps `li` on when a record is available, keeping
/// the high-water index and the flow-over NOTE in step; returns false at
/// end-of-file, which the caller turns into `ListRead.eof`.
///
/// GAP-inputdlmnoflow: readDelim had NO spill at all, so the two readers did not
/// merely disagree about the EOF edge — one implemented FLOWOVER and the other
/// silently did not. Sharing the decision here (rather than writing a second copy
/// beside the first) is what keeps them from drifting again; each caller only
/// re-seats its OWN cursor, which is the part that genuinely differs — a
/// tokenizer for whitespace, a byte offset for delimited.
///
/// MISSOVER/TRUNCOVER need no flag here: exec hands those modes a ONE-RECORD
/// window, so `li + 1 >= lines.len` is already true and no advance can happen.
fn flowToNextRecord(pdv: *Pdv, lines: []const []const u8, li: *usize, hi: *usize) bool {
    if (li.* + 1 >= lines.len) return false;
    li.* += 1;
    hi.* = @max(hi.*, li.*);
    flowNote(pdv, lines, li.*); // Language Reference: Concepts p.171 / Statements p.171 flow-over NOTE
    return true;
}

/// BUG-informatnotfoundcontinues (Language Reference: Concepts p.518, "How SAS Handles Invalid Data"):
/// an INPUT item naming an informat that does not exist makes its field
/// UNREADABLE — the value is invalid by definition ("requires an informat that
/// is not specified") — yet the ERROR printed and the step RAN ANYWAY, a
/// substituted standard read landing wrong DATA in a populated data set (a
/// plausible typo like `mmdyy10.` is the dangerous shape). On the WRITE side
/// the same fallback only mis-renders, so it stays (BUG-unknownfmtsilent's
/// design); on the READ side the step must not produce data it could not read.
/// Report through the captured reporter (D-003) and fail the step before any
/// value is read. `options nofmterr` keeps the historical substituted read
/// (SAS substitutes the default informat; its NOTE wording is needs-oracle).
/// Runs once per readList call — halts at the first record, so exactly one
/// ERROR where the old fallback printed one per record.
fn checkInputInformats(pdv: *Pdv, items: []const ast.InputItem) diag.Error!void {
    if (format.nofmterr()) return;
    for (items) |item| {
        if (item.name.len == 0 and item.arr_index == null) continue; // pointer/hold sentinels carry no spec
        const spec = item.informat orelse continue;
        if (spec.len > 0 and spec[0] == '@') continue; // `@s-e` column-range encoding
        // parseSpec's name split (not io's alphabetic informatName): digit-bearing
        // names keep their digits — `b8601da8.` is name "b8601da" + w 8, not "b".
        const nm = format.parseSpec(spec).name;
        const known = if (item.type == .char) format.isKnownCharInformat(nm) else format.isKnownInformat(nm);
        if (!known) {
            // D-009 §5f: a documented-but-unimplemented informat is an opensas
            // gap (rc 2, "file an opensas issue"); a name the 9.4 dictionary
            // does not name is the user's typo and stays rc 1 — same message.
            if (format.isDocumentedInformat(nm, item.type == .char)) diag.markGap();
            if (pdv.diags) |d| try d.report(.err, 0, "The informat {s} was not found or could not be loaded.", .{nm});
            return error.ExecError;
        }
    }
}

/// NOTE-inputinvalidnote (Language Reference: Concepts p.518 "How SAS Handles Invalid Data"): a
/// non-blank, non-`.`-coded NUMERIC field that read back missing is INVALID —
/// it does not conform to the informat or to the input style. This lands two
/// of p.518's four mandated actions on the INPUT-statement path: the
/// invalid-data NOTE (with the REAL record line + column — the house text's
/// hardcoded 0/0 belongs to the no-span expression path, not this one) and
/// _ERROR_=1 for the current observation (the `if _error_ then …` validation
/// idiom works on INPUT again). The value is already missing (action 1, long
/// conformant); action 4's record-echo + printed scale are NOT implemented
/// (reported in the ticket). `?` suppresses the NOTE, `??` also suppresses
/// _ERROR_ (item.suppress, GAP-inputstmtqq).
fn noteInvalidNum(pdv: *Pdv, field: []const u8, suppress: u2, line: usize, colno: usize) diag.Error!void {
    const t = std.mem.trim(u8, field, " \t");
    if (t.len == 0) return; // a blank field is a legitimate, silent missing
    if (std.mem.eql(u8, t, ".") or Value.parseSpecialMissing(t) != null) return; // coded missing
    // one NOTE per invalid value: readNumeric may already have emitted its own
    // for this exact field (the plain-w.d embedded-blank path, read_noted) —
    // still set _ERROR_, which that path never did.
    if (!format.read_noted and suppress < 1) if (pdv.diags) |d|
        try d.note(0, "Invalid numeric data, '{s}', at line {d} column {d}.", .{ t, line, colno });
    if (suppress < 2) try pdv.set("_error_", .{ .num = 1 });
}

/// What one INPUT read consumed: the high-water record index, plus whether the
/// read WANTED a record past the end of `lines` and could not have it.
///
/// GAP-inputeofdegrade: that second fact had nowhere to go, so three sites in
/// this file all wrote `if (li + 1 < lines.len) li += 1;` — silently declining to
/// advance and then reading on. The caller could not tell a satisfied read from
/// one that ran out, and the shortfall came back as FABRICATED data.
/// `eof` is "I needed another record"; only the CALLER knows whether that means
/// end-of-FILE (FLOWOVER, which was handed the whole file) or merely
/// end-of-RECORD (MISSOVER/TRUNCOVER, handed a one-record window on purpose).
pub const ListRead = struct { hi: usize, eof: bool = false };

pub fn readList(pdv: *Pdv, items: []const ast.InputItem, lines: []const []const u8, start: usize, dlm: ?[]const u8, dsd: bool, missover: bool, pos: ?*usize) diag.Error!ListRead {
    try checkInputInformats(pdv, items);
    if (dlm) |d| return readDelim(pdv, items, lines, start, d, dsd, pos);
    var eof = false;
    var li = start;
    // High-water record index: a BACKWARD `#n` leaves li < hi, and the caller
    // releases hi + 1 records. Returning the final li collapsed a backward-#n
    // record group to ONE record — a sliding window of 2-3x too many
    // observations plus a fabricated EOF row (BUG-inputlinehighwater).
    var hi = start;
    var col: usize = 1; // 1-based column cursor (formatted / column input)
    var colmode = false; // a @/+/# pointer switches width informats to column reads
    var fields = std.mem.tokenizeAny(u8, if (li < lines.len) lines[li] else "", " \t");
    if (pos) |p| fields.index = p.*; // `@@` hold: resume where the last read stopped
    var idx: usize = 0;
    while (idx < items.len) : (idx += 1) {
        var item = items[idx];
        // ── array-element target `input v{i}` (GAP-inputarrayelem): resolve the
        // flat subscript to its element var per read — a DO-loop index changes
        // every iteration — then read the element as a plain item. An
        // out-of-range index is a loud execution ERROR (resolver, mirroring
        // eval.zig's subscriptOor), never a silent record desync.
        if (item.arr_index) |ixe| item.name = try resolveArrElem(pdv, item, ixe);
        // ── pointer / position controls (no variable) ────────────────────────
        if (item.name.len == 0) {
            // GAP-atexpression: `@(expr)` — value per read, the SAME clampCol
            // as `@n`/`@var`; col >= 1 by construction, no underflow possible.
            if (item.col_expr) |e| {
                col = try evalColExpr(pdv, e);
                colmode = true;
                const line = if (li < lines.len) lines[li] else "";
                fields.index = @min(col - 1, line.len);
                continue;
            }
            const inf = item.informat orelse "";
            if (std.mem.eql(u8, inf, "@@")) continue; // @@ hold sentinel — executor-level, no read
            if (std.mem.eql(u8, inf, "@")) continue; // single-@ hold sentinel — executor-level, no read
            if (inf.len >= 1 and inf[0] == '/') { // next input record
                // GAP-inputeofdegrade: no next record → record it and STOP
                // re-reading the current one. Falling through re-tokenized the
                // SAME record, so `input x $ / y $;` over an odd record count
                // handed y the value already in x — a fabricated value at exit 0.
                if (li + 1 >= lines.len) {
                    eof = true;
                    break;
                }
                li += 1;
                hi = @max(hi, li);
                col = 1;
                fields = std.mem.tokenizeAny(u8, lines[li], " \t");
            } else if (inf.len >= 1 and inf[0] == '@') { // @col — move to a column
                if (inf.len > 2 and inf[1] == '\'') {
                    // GAP-inputatstring: `@'string'` — search the current record from
                    // the cursor for the literal; found → cursor lands just after the
                    // match, NOT found → end of line (a following read gets missing,
                    // MISSOVER-style — never an error).
                    const line = if (li < lines.len) lines[li] else "";
                    const needle = inf[2 .. inf.len - 1];
                    const hit = std.mem.indexOfPos(u8, line, @min(fields.index, line.len), needle);
                    fields.index = if (hit) |h| h + needle.len else line.len;
                    col = fields.index + 1;
                    colmode = true;
                } else {
                    // SAS clamps a column pointer < 1 to column 1 (@0 must not crash).
                    // BUG-inputatvarptr: `@var` takes the column from the variable's
                    // PDV value (the parser emits `@name`); bad pointer → column 1.
                    col = @max(std.fmt.parseInt(usize, inf[1..], 10) catch ptrCol(pdv, inf[1..]), 1);
                    colmode = true;
                    // BUG-inputrelcol: byte cursor tracks col (col-1, 0-based).
                    // BUG-colonatoob: clamp to line.len so an `@n` past end-of-line
                    // (followed by a colon read → fields.next()) doesn't index OOB.
                    const line = if (li < lines.len) lines[li] else "";
                    fields.index = @min(col - 1, line.len);
                }
            } else if (inf.len >= 1 and inf[0] == '+') { // +n — skip n columns
                // BUG-inputrelcol: `col` must reflect the CURRENT position, which a
                // prior token/fixed read advanced via the byte cursor (not `col`).
                // Re-sync from `fields.index` before the relative skip, then move both.
                col = fields.index + 1 + (std.fmt.parseInt(usize, inf[1..], 10) catch 0);
                colmode = true;
                // BUG-inputplusncol: clamp to line.len so a `+n` skip PAST end-of-line
                // (followed by a list/colon read → fields.next()) doesn't index OOB —
                // SAS yields missing, not a crash. Mirror of the @n/@s-e clamps.
                const line = if (li < lines.len) lines[li] else "";
                fields.index = @min(col - 1, line.len);
            } else if (inf.len >= 1 and inf[0] == '#') { // #n — go to line n of the record
                const n = std.fmt.parseInt(usize, inf[1..], 10) catch 1;
                const target = start + (if (n > 0) n - 1 else 0);
                // GAP-inputeofdegrade: `#n` is a record advance too, and asking
                // for a record past the end is the same p.178 end-of-file stop as
                // `/`. It used to fall through and tokenize the EMPTY string, so
                // every variable after the pointer read missing and the partial
                // observation went out.
                if (target >= lines.len) {
                    eof = true;
                    break;
                }
                li = target;
                hi = @max(hi, li);
                col = 1;
                colmode = true;
                fields = std.mem.tokenizeAny(u8, lines[li], " \t");
            }
            continue;
        }
        // ── column range `var s-e` (encoded `@s-e` by the parser) ─────────────
        if (item.informat) |inf| if (inf.len > 1 and inf[0] == '@') {
            var line = if (li < lines.len) lines[li] else "";
            const dash = std.mem.indexOfScalar(u8, inf[1..], '-');
            const rend = if (dash) |d| std.fmt.parseInt(usize, inf[1..][d + 1 ..], 10) catch 0 else 0;
            const rstart = std.fmt.parseInt(usize, if (dash) |d| inf[1..][0..d] else inf[1..], 10) catch 0;
            // FLOWOVER (Language Reference: Concepts p.171, BUG-flowovercolumn): the range STARTS past
            // this record's end — there is nothing to read, so flow to the next
            // record and read the SAME absolute columns there. (A range that
            // starts inside the record but ends past it reads SHORT, no flow —
            // datalines_char_informat pins SAS's short-field rule.) The caller's
            // record window spans >1 record ONLY under FLOWOVER (the short-record
            // modes clip it), so those modes never reach this and their
            // partial-field rules below are untouched.
            // ponytail: resume column = the absolute range — needs-oracle
            //   (doc-finder-tick287 F5), UNVERIFIED against a real SAS.
            while (rstart > line.len and li + 1 < lines.len) {
                li += 1;
                hi = @max(hi, li);
                flowNote(pdv, lines, li);
                line = lines[li];
                fields = std.mem.tokenizeAny(u8, line, " \t");
                col = 1;
            }
            const raw = colSlice(line, inf[1..]);
            const val = std.mem.trim(u8, raw, " \t");
            // BUG-missovertruncover-partial: MISSOVER rejects a range the record
            // ends inside of (raw non-empty but the range end is past the line);
            // TRUNCOVER keeps the truncated partial.
            const partial = missover and raw.len > 0 and rend > line.len;
            // BUG-inputcolrangecursor: advance the cursor past the range so a
            // following list / +n / w. read resumes after it (mirror of the
            // colmode branch). `raw` is a subslice of `line`; its end is the
            // 0-based byte cursor. Empty range (past line end) leaves the cursor.
            if (raw.len > 0) {
                col = (@intFromPtr(raw.ptr) - @intFromPtr(line.ptr)) + raw.len + 1;
                fields.index = col - 1;
                colmode = true;
            }
            if (item.type == .char) {
                _ = try pdv.define(item.name, .char);
                try pdv.set(item.name, .{ .str = if (partial) "" else val });
            } else {
                _ = try pdv.define(item.name, .num);
                const rval = if (partial) Value.missing else parseNum(val);
                if (!partial and rval.isMissing()) try noteInvalidNum(pdv, val, item.suppress, li + 1, rstart);
                try pdv.set(item.name, rval);
            }
            continue;
        };
        // ── $VARYINGw. — the NEXT input item is not a variable, it is the
        // length-variable OPERAND: read its (already-assigned) numeric value and
        // read that many columns (0..w) for THIS var from the cursor, then skip it.
        // BUG-varyinginformat. SAS: len<0 / missing → read no data; w is the max.
        if (item.type == .char and eqi(informatName(item.informat orelse ""), "varying")) {
            const w = format.parseSpec(item.informat orelse "").w;
            // length-variable value → column count, clamped to 0..w.
            const raw_len: usize = blk: {
                if (idx + 1 >= items.len) break :blk 0; // ponytail: absent operand → 0 (no diags handle to fail loud here)
                const lv = pdv.get(items[idx + 1].name) orelse break :blk 0;
                const n = switch (lv) {
                    .num => |x| x,
                    .str => break :blk 0,
                };
                if (std.math.isNan(n) or n < 0) break :blk 0;
                break :blk @intFromFloat(@floor(n));
            };
            const n = @min(raw_len, w);
            const line = if (li < lines.len) lines[li] else "";
            const s = @min(fields.index, line.len);
            const seg = line[s..@min(s + n, line.len)];
            fields.index = @min(s + n, line.len);
            col = fields.index + 1; // BUG-inputrelcol: col follows the byte cursor
            _ = try pdv.define(item.name, .char);
            try pdv.set(item.name, .{ .str = seg }); // $VARYING reads verbatim, no trim
            if (idx + 1 < items.len) idx += 1; // consume the length-variable operand
            continue;
        }
        // ── column-mode formatted read: `w` columns from the cursor ───────────
        // BUG-coloninformatat: a colon-modified informat (`:$w.`) stays list-style
        // even after an `@n`/`+n` pointer — the pointer sets the START column
        // (`fields.index`), then the read scans to the next delimiter (list mode
        // below), truncating to `w`. Only NON-colon items take the fixed-width grab.
        if (colmode and !item.list_mod) {
            const w = format.parseSpec(item.informat orelse "").w;
            if (w > 0) {
                var line = if (li < lines.len) lines[li] else "";
                var s = col - 1;
                // FLOWOVER (Language Reference: Concepts p.171, BUG-flowovercolumn): the field STARTS
                // at/past this record's end — nothing to read, so flow and
                // resume at column 1 (a field that merely extends past the end
                // reads short, no flow). Window-gated to FLOWOVER like the
                // column-range branch above.
                // ponytail: resume column 1 — needs-oracle (F5), UNVERIFIED.
                while (s >= line.len and li + 1 < lines.len) {
                    li += 1;
                    hi = @max(hi, li);
                    flowNote(pdv, lines, li);
                    line = lines[li];
                    fields = std.mem.tokenizeAny(u8, line, " \t");
                    col = 1;
                    s = 0;
                }
                const seg = if (s < line.len) line[s..@min(s + w, line.len)] else "";
                col += w;
                fields.index = @min(col - 1, line.len); // BUG-inputrelcol: keep cursor == col
                // BUG-missovertruncover-partial: the record ends MID-FIELD (seg
                // starts inside the line but is shorter than w) — MISSOVER reads
                // missing; TRUNCOVER keeps the truncated partial.
                const partial = missover and seg.len > 0 and seg.len < w;
                if (item.type == .char) {
                    _ = try pdv.define(item.name, .char);
                    // BUG-charinformatloud: an unknown $-informat fails loud on
                    // the column read too (this path skips charInformat).
                    format.checkCharInformat(informatName(item.informat orelse ""));
                    // BUG-charwleadblank: leading blanks follow the informat —
                    // $CHARw. KEEPS them, plain $w. strips (left-aligns).
                    try pdv.set(item.name, .{ .str = if (partial) "" else charField(item.informat, seg, " ") });
                } else {
                    _ = try pdv.define(item.name, .num);
                    // BUG-bzstmtcolumn: BZ reads field blanks as zeros, so it must
                    // see the untrimmed field (`12  ` bz4. → 1200, all-blank → 0).
                    // readNumeric trims plain w.d itself, so only BZ needs the raw seg.
                    const numf = if (eqi(informatName(item.informat orelse ""), "bz")) seg else std.mem.trim(u8, seg, " ");
                    const cval = if (partial) Value.missing else readNum(item.informat, numf);
                    if (!partial and cval.isMissing()) try noteInvalidNum(pdv, numf, item.suppress, li + 1, s + 1);
                    try pdv.set(item.name, cval);
                }
                continue;
            }
        }
        // ── formatted char read: `$w.` (non-colon) takes the full w columns from
        // the cursor, embedded blanks included — NOT a whitespace token
        // (DATALINES-informat). The colon form (`:$w.`, list_mod) still tokenizes.
        // Shares the tokenizer's byte cursor so it composes with prior list reads:
        // after `input a $ b $12.`, `b` reads 12 cols from just past `a`'s token.
        if (item.type == .char and !item.list_mod) {
            const w = format.parseSpec(item.informat orelse "").w;
            if (w > 0) {
                var line = if (li < lines.len) lines[li] else "";
                var s = @min(fields.index, line.len);
                // FLOWOVER (Language Reference: Concepts p.171) — field starts past the record end,
                // as the colmode branch above.
                while (s >= line.len and li + 1 < lines.len) {
                    li += 1;
                    hi = @max(hi, li);
                    flowNote(pdv, lines, li);
                    line = lines[li];
                    fields = std.mem.tokenizeAny(u8, line, " \t");
                    s = 0;
                }
                const seg = line[s..@min(s + w, line.len)];
                fields.index = @min(s + w, line.len);
                col = fields.index + 1; // BUG-inputrelcol: col follows the byte cursor
                _ = try pdv.define(item.name, .char);
                // BUG-missovertruncover-partial: record ends mid-field — MISSOVER
                // reads missing, TRUNCOVER keeps the truncated partial.
                if (missover and seg.len > 0 and seg.len < w) {
                    try pdv.set(item.name, .{ .str = "" });
                    continue;
                }
                // BUG-charwleadblank: $CHARw. keeps leading blanks (trim end
                // only); plain $w. left-aligns. Mirror of the INPUT() fn path.
                const trimmed = charField(item.informat, seg, " \t");
                // Named `$` informats post-process (BUG-upcaseinformat /
                // BUG-quoteinformat): $UPCASE/$LOWCASE case-fold, $QUOTE strips
                // quotes, $HEX decodes hex pairs; any other reads verbatim. Shared
                // with the INPUT() function path (functions.zig).
                const nm = informatName(item.informat orelse "");
                const out = try format.charInformat(pdv.arena, nm, trimmed);
                try pdv.set(item.name, .{ .str = out });
                continue;
            }
        }
        // ── formatted numeric read: any `w.d` informat (non-colon) takes the
        // full w columns from the cursor — the numeric mirror of the char branch
        // above (Language Reference: Concepts p.515: formatted input "combines the flexibility of using
        // informats with many of the features of column input").
        // BUG-inputfmtseq: sequential `x 2. y 2.` must advance the byte cursor by
        // the field width like char does, NOT tokenize; without a @/+/# pointer
        // colmode is off, so the colmode grab above never fires for these.
        // BUG-dateblanksep: `input d date11.;` (informat INLINE, no colon) is a
        // formatted read of w columns in SAS, and the DATE/MMDDYY/DDMMYY/YYMMDD
        // informats accept blank separators (`16 mar 2012`) — so those four skip
        // leading blanks below. The `:`/INFORMAT-statement forms carry
        // list_mod=true and still tokenize (BUG-informatlistinput).
        // BUG-inputfmtnamedtoken: EVERY other named numeric informat (comma5.,
        // time8., bz4., percent5., hex4.) is a formatted w-column read too —
        // gating columns on the informat NAME tokenized them instead, so
        // adjacent fields MERGED (`1,1321,187` → score1=11321187, score2 lost)
        // and the byte cursor desynced every following variable (hex4. even
        // read the right VALUE off the wrong columns). The w-column slice goes
        // to readNum raw for BZ (its blanks are ZEROS — Table 21.2 rows 1-2:
        // `23  ` bz4. → 2300; the colmode branch's BUG-bzstmtcolumn twin),
        // trimmed otherwise; embedded-blank rules are per-informat in
        // format.readNumeric (plain w.d: invalid; COMMA family: strip).
        const numnm = informatName(item.informat orelse "");
        const datecol = eqi(numnm, "date") or eqi(numnm, "mmddyy") or
            eqi(numnm, "ddmmyy") or eqi(numnm, "yymmdd");
        if (item.type == .num and !item.list_mod) {
            const w = format.parseSpec(item.informat orelse "").w;
            if (w > 0) {
                var line = if (li < lines.len) lines[li] else "";
                var s = @min(fields.index, line.len);
                // FLOWOVER (Language Reference: Concepts p.171) — field starts past the record end,
                // as the colmode branch above.
                while (s >= line.len and li + 1 < lines.len) {
                    li += 1;
                    hi = @max(hi, li);
                    flowNote(pdv, lines, li);
                    line = lines[li];
                    fields = std.mem.tokenizeAny(u8, line, " \t");
                    s = 0;
                }
                // After a list token the cursor rests ON the delimiter — skip
                // blanks so `input id $ d date9.` lands on the date columns
                // (cf_import_raw). ponytail: skips ALL blanks; a blanks-only
                // missing date eats the next field's lead-in, same failure
                // class as the old token read.
                if (datecol) {
                    while (s < line.len and line[s] == ' ') s += 1;
                }
                const seg = line[s..@min(s + w, line.len)];
                fields.index = @min(s + w, line.len);
                col = fields.index + 1; // BUG-inputrelcol: col follows the byte cursor
                _ = try pdv.define(item.name, .num);
                // BUG-missovertruncover-partial: record ends mid-field — MISSOVER
                // reads missing, TRUNCOVER keeps the truncated partial.
                const partial = missover and seg.len > 0 and seg.len < w;
                // BZ gets the raw field (blanks→zeros, see branch comment);
                // everything else trims leading/trailing blanks.
                const numf = if (eqi(numnm, "bz")) seg else std.mem.trim(u8, seg, " ");
                const nval = if (partial) Value.missing else readNum(item.informat, numf);
                // NOTE-inputinvalidnote: the informat-nonconformance case too
                // (`notadate!!` under mmddyy10.) — p.518's second definition.
                if (!partial and nval.isMissing()) try noteInvalidNum(pdv, numf, item.suppress, li + 1, s + 1);
                try pdv.set(item.name, nval);
                continue;
            }
        }
        // ── list mode: next whitespace token, spilling onto later lines ───────
        var tok = fields.next();
        while (tok == null and flowToNextRecord(pdv, lines, &li, &hi)) {
            fields = std.mem.tokenizeAny(u8, lines[li], " \t");
            tok = fields.next();
        }
        // GAP-inputeofdegrade: still out of data with no record left to spill
        // onto. Under FLOWOVER that is end-of-FILE and the caller must end the
        // step; assigning missing here is MISSOVER's documented job, not
        // FLOWOVER's, and doing it anyway wrote a PARTIAL observation. The
        // caller distinguishes the two — MISSOVER/TRUNCOVER are handed a
        // one-record window, so they reach this line normally and must keep
        // their missing-value behaviour.
        if (tok == null) eof = true;
        col = fields.index + 1; // BUG-inputrelcol: a following +n/@n reads from just past this token
        if (listReadsChar(pdv, item)) {
            const slot = try pdv.define(item.name, .char);
            const val = listCharValue(pdv, slot, item.informat, tok orelse ""); // BUG-inputlistlen / BUG-coloninformatwidth
            try pdv.setAt(slot, .{ .str = val });
        } else {
            _ = try pdv.define(item.name, .num);
            const v: Value = if (tok) |t| readNum(item.informat, t) else Value.missing;
            // NOTE-inputinvalidnote (p.518): invalid numeric token → NOTE + _ERROR_
            if (tok) |t| if (v.isMissing())
                try noteInvalidNum(pdv, t, item.suppress, li + 1, fields.index - t.len + 1);
            try pdv.set(item.name, v);
        }
    }
    if (pos) |p| p.* = fields.index; // report where this record ended (for `@@` hold)
    return .{ .hi = hi, .eof = eof };
}

/// GAP-inputarrayelem: evaluate an INPUT array-element subscript to the element
/// var it names — per read, since a DO-loop index changes every iteration — or
/// null for an out-of-range/missing/character index (PUT's array_elem parity:
/// no read). The Evaluator wants pdv.diags; a standalone readList caller
/// without one cannot eval → null (only hand-built unit-test items hit that).
/// GAP-inputarrayelem: evaluate an INPUT array-element subscript to the element
/// var it names — per read, since a DO-loop index changes every iteration. An
/// out-of-range/missing/character subscript is a SAS execution ERROR that sets
/// _ERROR_=1 and halts the step, mirroring the array-READ and assignment paths
/// (eval.zig subscriptOor / BUG-arrayoorerror / BUG-arrwriteoor) — a silent
/// skip would desync the record stream, the worst failure class here. The
/// Evaluator wants pdv.diags; a standalone readList caller without one cannot
/// eval a subscript at all (only hand-built unit-test items hit that).
fn resolveArrElem(pdv: *Pdv, item: ast.InputItem, ixe: *const ast.Expr) diag.Error![]const u8 {
    const d = pdv.diags orelse return error.ExecError;
    var ev: eval.Evaluator = .{ .arena = pdv.arena, .pdv = pdv, .diags = d, .call_fn = &functions.dispatch };
    const x = switch (try ev.eval(ixe)) {
        .num => |n| n,
        .str => std.math.nan(f64),
    };
    const i = @floor(x);
    if (std.math.isNan(i) or i < 1 or i > @as(f64, @floatFromInt(item.arr_elements.len))) {
        pdv.set("_error_", .{ .num = 1 }) catch {}; // SAS sets _ERROR_=1 on the way out
        return d.fail(error.ExecError, 0, "Array subscript {d} out of range for {s} in INPUT.", .{ i, item.arr_name });
    }
    return item.arr_elements[@as(usize, @intFromFloat(i)) - 1];
}

/// Read type for LIST input: an explicit `$` / char informat wins, but a BARE
/// `input nm;` takes the var's ALREADY-DECLARED PDV type — a LENGTH/ATTRIB char
/// var reads a char token without needing `$` (BUG-inputcharnodollar); only an
/// undeclared var falls through to the numeric read.
fn listReadsChar(pdv: *const Pdv, item: ast.InputItem) bool {
    if (item.type == .char) return true;
    if (item.informat != null or item.name.len == 0) return false;
    return if (pdv.indexOf(item.name)) |i| pdv.vars.items[i].type == .char else false;
}

/// Delimited (DLM=/DSD) infile input: one line is one record, split on `d`. With
/// DSD, a quoted field may contain the delimiter, and consecutive delimiters read
/// as missing. Pointer controls mirror readList (Language Reference: Concepts Table 21.5: controls and
/// delimiter options combine freely): `/`/`#n` move the record, `@n`/`+n`/`@'str'`
/// move the byte cursor the next field scans from, `@`/`@@` are executor-level
/// holds reported through `pos`. BUG-inputdlmpointer: with no pointer-item guard
/// every control fell into a variable read — eating a field and defining a
/// NAMELESS PDV slot (a phantom column in the output dataset) — and the dropped
/// `pos` left an `@@` hold on the same record forever (an infinite loop).
/// Returns the high-water record index read from (BUG-inputlinehighwater).
/// ponytail: `@n`/`+n` land the cursor mid-record and the field scanner resumes
///   there — landing exactly ON a delimiter reads an empty field under DSD; SAS's
///   exact landing semantics for that edge are unpinned (no oracle).
fn readDelim(pdv: *Pdv, items: []const ast.InputItem, lines: []const []const u8, start: usize, d: []const u8, dsd: bool, pos: ?*usize) !ListRead {
    var eof = false;
    var li = start;
    var hi = start; // high-water mark — a backward #n leaves li < hi (BUG-inputlinehighwater)
    var line = if (li < lines.len) lines[li] else "";
    var fpos: usize = if (pos) |p| p.* else 0; // `@`/`@@` hold: resume mid-record
    for (items) |item_| {
        var item = item_;
        // array-element target (GAP-inputarrayelem) — same resolution as readList
        if (item.arr_index) |ixe| item.name = try resolveArrElem(pdv, item, ixe);
        // ── pointer / position controls (no variable) ────────────────────────
        if (item.name.len == 0) {
            if (item.col_expr) |e| { // GAP-atexpression — same arm as readList
                const c = try evalColExpr(pdv, e);
                fpos = @min(c - 1, line.len);
                continue;
            }
            const inf = item.informat orelse "";
            if (std.mem.eql(u8, inf, "@@")) continue; // @@ hold sentinel — executor-level, no read
            if (std.mem.eql(u8, inf, "@")) continue; // single-@ hold sentinel — executor-level, no read
            if (inf.len >= 1 and inf[0] == '/') { // next input record
                // GAP-inputeofdegrade: the THIRD copy of this pattern, and the
                // one the ticket did not name — a DLM=/DSD read advancing past
                // EOF re-read the current record exactly as readList did.
                if (li + 1 >= lines.len) {
                    eof = true;
                    break;
                }
                li += 1;
                hi = @max(hi, li);
                line = if (li < lines.len) lines[li] else "";
                fpos = 0;
            } else if (inf.len >= 1 and inf[0] == '#') { // #n — line n of the record group
                const n = std.fmt.parseInt(usize, inf[1..], 10) catch 1;
                const target = start + (if (n > 0) n - 1 else 0);
                if (target >= lines.len) { // same p.178 stop as `/` above
                    eof = true;
                    break;
                }
                li = target;
                hi = @max(hi, li);
                line = lines[li];
                fpos = 0;
            } else if (inf.len >= 1 and inf[0] == '@') { // @col — move the byte cursor
                if (inf.len > 2 and inf[1] == '\'') {
                    // @'string' — search from the cursor; miss → end of record.
                    const needle = inf[2 .. inf.len - 1];
                    fpos = if (std.mem.indexOfPos(u8, line, @min(fpos, line.len), needle)) |h| h + needle.len else line.len;
                } else {
                    // SAS clamps a column pointer < 1 to column 1; `@var` takes the
                    // column from the PDV value (BUG-inputatvarptr), bad → column 1.
                    fpos = @min((std.fmt.parseInt(usize, inf[1..], 10) catch ptrCol(pdv, inf[1..])) -| 1, line.len);
                }
            } else if (inf.len >= 1 and inf[0] == '+') { // +n — skip n columns
                fpos = @min(fpos + (std.fmt.parseInt(usize, inf[1..], 10) catch 0), line.len);
            }
            continue;
        }
        // GAP-inputdlmnoflow: FLOWOVER for the DELIMITED reader, which had none —
        // it read missing off the end of the record instead of taking the next
        // one, so Statements ref printed p.145's OWN example came back with THREE
        // observations where the volume prints TWO and its second observation lost
        // the value that should have flowed in.
        //
        // EXHAUSTION, NOT EMPTINESS, is the trigger, and the distinction matters:
        // nextDelimField sets `pos = line.len + 1` only when the record is spent,
        // while an EMPTY field mid-record (`a,,b` under DSD) is a legitimate
        // missing value and leaves pos <= line.len. Spilling on emptiness would
        // have silently eaten DSD's missing-value semantics.
        while (fpos > line.len and flowToNextRecord(pdv, lines, &li, &hi)) {
            line = lines[li];
            fpos = 0;
        }
        if (fpos > line.len) eof = true; // no record left — caller ends the step (p.178)
        const fstart = fpos;
        const field = try nextDelimField(pdv.arena, line, &fpos, d, dsd);
        if (listReadsChar(pdv, item)) {
            const slot = try pdv.define(item.name, .char);
            const val = listCharValue(pdv, slot, item.informat, field); // BUG-inputlistlen / BUG-coloninformatwidth
            try pdv.setAt(slot, .{ .str = val });
        } else {
            _ = try pdv.define(item.name, .num);
            const dv = if (field.len > 0) readNum(item.informat, field) else Value.missing;
            if (field.len > 0 and dv.isMissing()) try noteInvalidNum(pdv, field, item.suppress, li + 1, fstart + 1);
            try pdv.set(item.name, dv);
        }
    }
    if (pos) |p| p.* = fpos; // report where this record ended (for `@@` hold)
    return .{ .hi = hi, .eof = eof };
}

/// Extract the next delimited field from `line`, advancing `pos` past it (and
/// its trailing delimiter). Past the last field → "". With DSD, a leading `"`
/// starts a quoted field that ends at the next `"` — and a DOUBLED `""` inside
/// it is one escaped quote (BUG-dsddoublequote, Language Reference: Concepts Table 21.4 p.509: the DSD
/// writer and the PROC IMPORT reader both already use this rule — the file
/// opensas writes, opensas must read back). `d` is a delimiter SET —
/// a byte splits iff it is a MEMBER of `d` (BUG-dlmmultichar).
fn nextDelimField(a: std.mem.Allocator, line: []const u8, pos: *usize, d: []const u8, dsd: bool) ![]const u8 {
    if (pos.* > line.len) return ""; // no fields left
    var start = pos.*;
    if (dsd and start < line.len and line[start] == '"') {
        var i = start + 1;
        var esc = false; // saw a "" escape — the value needs unescaping below
        while (i < line.len) {
            if (line[i] != '"') {
                i += 1;
                continue;
            }
            if (i + 1 < line.len and line[i + 1] == '"') { // "" = one escaped quote
                esc = true;
                i += 2;
                continue;
            }
            break; // the real closing quote
        }
        var field = line[start + 1 .. @min(i, line.len)];
        if (esc) { // collapse each "" pair to a single " (rare path — else borrow)
            const buf = try a.alloc(u8, field.len);
            var n: usize = 0;
            var j: usize = 0;
            while (j < field.len) {
                buf[n] = field[j];
                n += 1;
                j += if (field[j] == '"') 2 else 1;
            }
            field = buf[0..n];
        }
        i += 1; // past the closing quote
        if (i < line.len and std.mem.indexOfScalar(u8, d, line[i]) != null) i += 1; // past the delimiter
        pos.* = if (i <= line.len) i else line.len + 1;
        return field;
    }
    // Non-DSD list input (BUG-dlmcollapse): a RUN of consecutive delimiters counts
    // as ONE separator, so skip a leading run before reading the field. Under DSD,
    // consecutive delimiters delimit missing fields, so this collapse is skipped.
    if (!dsd) {
        while (start < line.len and std.mem.indexOfScalar(u8, d, line[start]) != null) start += 1;
    }
    var i = start;
    while (i < line.len and std.mem.indexOfScalar(u8, d, line[i]) == null) i += 1;
    const field = line[start..i];
    pos.* = if (i < line.len) i + 1 else line.len + 1;
    return field;
}

/// Convert one numeric field, honouring a `:informat.` if present. DATE reads
/// `ddMMMyyyy`; everything else parses plainly. A `.` or unparseable text
/// lands as missing.
fn readNum(informat: ?[]const u8, field: []const u8) Value {
    format.read_noted = false; // per-field: NOTE-inputinvalidnote dedupe (format.zig)
    const name = informatName(informat orelse "");
    if (eqi(name, "date")) return parseDate(field);
    // Date/time informats on the INPUT statement (BUG-inputdatestmt): these read
    // to a SAS day / seconds-of-day, same as the INPUT() function does.
    if (eqi(name, "mmddyy")) return parseDateParts(field, .mdy);
    if (eqi(name, "ddmmyy")) return parseDateParts(field, .dmy);
    if (eqi(name, "yymmdd")) return parseDateParts(field, .ymd);
    // TIMEw./HHMMSSw.: the shared format.zig parsers (AM/PM, `.` separator,
    // fraction, packed digits) — the local copy below was that code gone stale
    // (BUG-timeinformat / BUG-hhmmssinformat).
    if (eqi(name, "time")) return if (format.parseTimeSecs(field)) |sc| .{ .num = sc } else Value.missing;
    if (eqi(name, "hhmmss")) return if (format.parseHhmmss(field)) |sc| .{ .num = sc } else Value.missing;
    // Plain `w.d` (implied decimal), PERCENTw. and the COMMA/DOLLAR family live
    // in format.readNumeric, so the numeric informat rules stay in one place
    // (BUG-informatdec, BUG-percentinformat). COMMA/DOLLAR's local copy was that
    // code gone stale — no interior-hyphen removal, no implied decimals
    // (NOTE-informatlow-tick245 #13); parens-negative and the strip rules are
    // readNumeric's commalike branch.
    // readNumericStmt, NOT readNumeric: the statement list/colon path hands over
    // the WHOLE token and `w` is NOT a truncation point for a numeric (Language Reference: Concepts
    // p.513: the length limit is "(character only)"); column reads above arrive
    // pre-sliced to w. The fn path's w-slice is INPUT()-function semantics.
    return format.readNumericStmt(informat orelse "", field);
}

const DateOrder = enum { mdy, dmy, ymd };

/// Read a numeric date field (`mm/dd/yyyy`, `dd/mm/yyyy`, `yyyy-mm-dd`, or the
/// packed digit-only forms) under the given part order → a SAS day number.
/// Separators may be `/ - .` blank or none (BUG-inputdatestmtblank). A 2-digit
/// year is expanded into the YEARCUTOFF span (OPTIONS YEARCUTOFF=, default 1920).
/// Unparseable → missing.
fn parseDateParts(field: []const u8, order: DateOrder) Value {
    const s = std.mem.trim(u8, field, " ");
    if (s.len == 0) return Value.missing;
    var p: [3]i64 = .{ 0, 0, 0 };
    if (std.mem.indexOfAny(u8, s, "/-. ") != null) {
        var it = std.mem.tokenizeAny(u8, s, "/-. "); // tokenize collapses a blank run
        var n: usize = 0;
        while (it.next()) |tok| : (n += 1) {
            if (n >= 3) return Value.missing;
            p[n] = std.fmt.parseInt(i64, tok, 10) catch return Value.missing;
        }
        if (n != 3) return Value.missing;
    } else {
        // packed digits: yyyymmdd (ymd) or mmddyyyy/ddmmyyyy — 8 digits, or a
        // 6-digit form with a 2-digit year.
        for (s) |c| if (!std.ascii.isDigit(c)) return Value.missing;
        const yw: usize = if (s.len >= 8) 4 else 2; // year field width
        const seg = struct {
            fn at(str: []const u8, a: usize, b: usize) i64 {
                return std.fmt.parseInt(i64, str[a..b], 10) catch -1;
            }
        }.at;
        if (order == .ymd) {
            if (s.len < yw + 4) return Value.missing;
            p = .{ seg(s, 0, yw), seg(s, yw, yw + 2), seg(s, yw + 2, yw + 4) };
        } else {
            if (s.len < yw + 4) return Value.missing;
            p = .{ seg(s, 0, 2), seg(s, 2, 4), seg(s, 4, 4 + yw) };
        }
    }
    var y: i64 = undefined;
    var m: i64 = undefined;
    var d: i64 = undefined;
    switch (order) {
        .mdy => {
            m = p[0];
            d = p[1];
            y = p[2];
        },
        .dmy => {
            d = p[0];
            m = p[1];
            y = p[2];
        },
        .ymd => {
            y = p[0];
            m = p[1];
            d = p[2];
        },
    }
    if (y < 0 or m < 1 or m > 12 or d < 1 or d > 31) return Value.missing;
    y = format.expandYear(y); // 2-digit year → the YEARCUTOFF span (BUG-yearcutoff)
    // reject a rolled-over day (e.g. 2020-02-31) → missing (BUG-infdate-stmt)
    return if (format.sasDayChecked(y, m, d)) |day| .{ .num = @floatFromInt(day) } else Value.missing;
}

fn parseNum(s: []const u8) Value {
    const tr = std.mem.trim(u8, s, " ");
    if (tr.len == 0) return Value.missing;
    if (Value.parseSpecialMissing(tr)) |sm| return sm; // .A–.Z, ._ (ISS-specialmissing)
    return if (std.fmt.parseFloat(f64, tr)) |x| .{ .num = x } else |_| Value.missing;
}

/// The ONE SAS column-pointer clamp (Statements printed p.168 — the same Tip
/// is printed under `@n`, `@numeric-variable` AND `@(expression)`: 'If it is
/// zero or negative, the pointer moves to column 1', non-integers truncated to
/// the integer value). ptrCol and the `@(expr)` arm BOTH route through this —
/// one rule, one place; do not grow a second clamp.
///
/// GAP-atexpression-put: `pub` because PUT's `@(expression)` (exec.zig runPut,
/// Statements printed p.269) is the FOURTH caller of this same rule. p.269's
/// `@(expression)` Tip drops the word "negative" that its own `@numeric-variable`
/// sibling one entry above carries ('If n is zero or negative, the pointer moves
/// to column 1') and that INPUT's p.168 entry carries — an omission, not a
/// different rule: both PUT entries declare 'Range a positive integer', and every
/// pointer control on p.269-270 floors at column 1 (even `+numeric-variable`,
/// which moves BACKWARD, says 'If the current column position becomes less than
/// 1, the pointer moves to column 1'). So: one clamp, four callers.
pub fn clampCol(x: f64) usize {
    return if (x >= 1 and x < 1e15) @intFromFloat(x) else 1;
}

/// `@var` column-pointer operand: the variable's PDV value as a 1-based column.
/// Missing/undefined/character/out-of-range → 1 (SAS falls back to column 1 on a
/// non-positive or undetermined pointer).
fn ptrCol(pdv: *Pdv, name: []const u8) usize {
    const v = pdv.get(name) orelse return 1;
    return switch (v) {
        .num => |x| clampCol(x),
        .str => 1,
    };
}

/// `@(expression)` column pointer (GAP-atexpression, Statements printed p.168):
/// evaluate the expression PER READ against the PDV — a variable computed
/// earlier in the same step moves the pointer (`b=5; input @(b*3) name $10.;`
/// is the doc's own example) — then the SAME clampCol as `@n`/`@var`.
/// A CHARACTER result is SAS's OTHER parenthesised form, the
/// `@(character-expression)` string search, which is not implemented — fail
/// loud (D-002); landing on column 1 would silently read the wrong column.
fn evalColExpr(pdv: *Pdv, e: *const ast.Expr) diag.Error!usize {
    const d = pdv.diags orelse return error.ExecError;
    var ev: eval.Evaluator = .{ .arena = pdv.arena, .pdv = pdv, .diags = d, .call_fn = &functions.dispatch };
    const v = try ev.eval(e);
    return switch (v) {
        .num => |x| clampCol(x),
        .str => return d.fail(error.ExecError, 0, "input: @(character-expression) string-search pointer is not supported", .{}),
    };
}

/// Columns `s-e` (1-based, inclusive; `s` alone = one column) of `line`, from a
/// `@s-e` column-input spec. Ends past the line clamp to its length.
fn colSlice(line: []const u8, spec: []const u8) []const u8 {
    const dash = std.mem.indexOfScalar(u8, spec, '-');
    const s = std.fmt.parseInt(usize, if (dash) |d| spec[0..d] else spec, 10) catch return "";
    const e = if (dash) |d| (std.fmt.parseInt(usize, spec[d + 1 ..], 10) catch s) else s;
    if (s == 0 or s > line.len) return "";
    const end = @min(e, line.len);
    return if (s - 1 < end) line[s - 1 .. end] else "";
}

/// `ddMMMyy[yy]` (e.g. `01JAN1960`, `01JAN26`). Hyphens, slashes and blanks
/// between the parts are separators, not data: `15-MAR-2020` via DATE11.
/// (GAP-date11informat), `16 mar 2012` / `16/mar/2012` (BUG-dateblanksep).
/// A 2-digit year (DATE7) is expanded into the YEARCUTOFF span (BUG-yearcutoff).
fn parseDate(field: []const u8) Value {
    const s = std.mem.trim(u8, field, " ");
    var buf: [32]u8 = undefined;
    var p = s;
    if (std.mem.indexOfAny(u8, s, "-/ ") != null) { // separated → strip, then packed read
        var n: usize = 0;
        for (s) |c| {
            if (c == '-' or c == '/' or c == ' ') continue;
            if (n >= buf.len) return Value.missing;
            buf[n] = c;
            n += 1;
        }
        p = buf[0..n];
    }
    if (p.len < 7) return Value.missing;
    const day = std.fmt.parseInt(i64, p[0..2], 10) catch return Value.missing;
    const mon = monthNum(p[2..5]) orelse return Value.missing;
    const year = format.expandYear(std.fmt.parseInt(i64, p[5..], 10) catch return Value.missing);
    return if (format.sasDayChecked(year, mon, day)) |dn| .{ .num = @floatFromInt(dn) } else Value.missing; // BUG-infdate-stmt
}

const sas_epoch_days: i64 = 3653; // 1970-01-01 is SAS day 3653

fn monthNum(abbr: []const u8) ?i64 {
    const names = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
    for (names, 0..) |m, i| if (eqi(abbr, m)) return @intCast(i + 1);
    return null;
}

/// Days from 1970-01-01 for a proleptic-Gregorian date (Hinnant's algorithm).
fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe = y - era * 400; // [0, 399]
    const mp = if (m > 2) m - 3 else m + 9; // [0, 11]
    const doy = @divTrunc(153 * mp + 2, 5) + d - 1; // [0, 365]
    const doe = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy; // [0, 146096]
    return era * 146097 + doe - 719468;
}

/// Read-side char-field blank rule (BUG-charwleadblank), mirroring the INPUT()
/// function path: $CHARw. KEEPS leading blanks (trailing trimmed only); plain
/// $w. and the other $ informats strip them (left-align). `ws` is the trailing
/// cutset — the column-pointer path trims spaces only, the cursor path " \t".
fn charField(informat: ?[]const u8, seg: []const u8, ws: []const u8) []const u8 {
    if (eqi(informatName(informat orelse ""), "char")) return std.mem.trimEnd(u8, seg, ws);
    return std.mem.trim(u8, seg, ws);
}

fn informatName(spec: []const u8) []const u8 {
    var i: usize = 0;
    if (i < spec.len and spec[i] == '$') i += 1;
    const start = i;
    while (i < spec.len and std.ascii.isAlphabetic(spec[i])) i += 1;
    return spec[start..i];
}

fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Stamp `ds`'s schema from `pdv`, one column per variable in PDV order. Call
/// once before snapshotting rows. drop/keep is the executor's: it seeds only
/// the columns it wants, or adds them by hand — this is the all-variables case.
pub fn seedColumns(ds: *Dataset, pdv: *const Pdv) std.mem.Allocator.Error!void {
    for (pdv.vars.items) |v| _ = try ds.addColumn(v.name, v.type);
}

/// Append the current PDV as one observation of `ds`, pulling each column's
/// value from the PDV by name (missing-of-type if the variable is absent).
/// `appendRow` dupes any char bytes, so the row outlives this PDV state.
pub fn snapshot(ds: *Dataset, pdv: *const Pdv) std.mem.Allocator.Error!void {
    const cells = try ds.arena.alloc(Value, ds.columns.items.len);
    for (ds.columns.items, 0..) |col, i| {
        cells[i] = pdv.get(col.name) orelse missingOf(col.type);
    }
    try ds.appendRow(cells);
}

/// Resolve each column of `ds` to its PDV slot, ONCE per source
/// (PERF-loadrowdual, docs/findings/perf-findings-tick121.md). `define` is
/// idempotent, so for columns already seeded (exec.seedColumnsOf) this is a
/// pure lookup; the slots stay valid — `Pdv.vars` is append-only.
pub fn columnSlots(pdv: *Pdv, ds: *const Dataset) std.mem.Allocator.Error![]usize {
    const slots = try pdv.arena.alloc(usize, ds.columns.items.len);
    for (ds.columns.items, 0..) |col, j| slots[j] = try pdv.define(col.name, col.type);
    return slots;
}

/// `set`: load observation `i` of `ds` into the PDV, writing each column's
/// cell straight to its pre-resolved slot (`columnSlots`) — zero name lookups
/// on the per-row path (PERF-loadrowdual). The PDV borrows the dataset's char
/// bytes — both live in the run arena and the dataset is immutable, so the
/// alias is safe until the next reset/write overwrites it.
/// `_setobs_` (the nobs= backing var) is no longer stamped here per row: the
/// executor sets it once per distinct source, and only when nobs= was
/// requested (Executor.stampObs).
pub fn loadRow(pdv: *Pdv, ds: *const Dataset, i: usize, slots: []const usize) std.mem.Allocator.Error!void {
    std.debug.assert(slots.len == ds.columns.items.len);
    const cells = ds.row(i);
    for (slots, 0..) |slot, j| try pdv.setAt(slot, cells[j]);
}

// ── raw file I/O for PROC EXPORT/IMPORT ──────────────────────────────────────
// The PROC layer carries no `Io`, so these use the hardcoded single-threaded
// blocking `Io` (std.Io.Threaded.global_single_threaded) via the portable
// std.Io.Dir API — CWD-relative, cross-platform (posix.openat's AT.FDCWD doesn't
// exist on Windows: BUILD-windows). Return values degrade to a bool/optional so
// callers surface a NOTE.

/// A process-wide blocking Io for the no-`Io` leaf paths (PROC EXPORT/IMPORT here,
/// `%include` in macro.zig). Sync file ops only — no async/concurrency.
fn rawIo() std.Io {
    return std.Io.Threaded.global_single_threaded.io();
}

/// Write `data` to `path`, creating/truncating it. False on any open/write error.
pub fn writeFileRaw(path: []const u8, data: []const u8) bool {
    std.Io.Dir.cwd().writeFile(rawIo(), .{ .sub_path = path, .data = data }) catch return false;
    return true;
}

/// Read the whole file at `path`. Null on any open/read error.
pub fn readFileRaw(a: std.mem.Allocator, path: []const u8) ?[]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(rawIo(), path, a, .limited(1 << 31)) catch null;
}

/// Whether a file exists at `path` (existence probe only, nothing is opened).
/// For the no-`Io` leaf paths (EXIST's disk probe, BUG-existdisk).
pub fn fileExistsRaw(path: []const u8) bool {
    std.Io.Dir.cwd().access(rawIo(), path, .{}) catch return false;
    return true;
}

/// Unlink a member's on-disk files under a directory libname: any
/// `stem.{sas7bdat,xpt,csv}` plus the `.labels` sidecar, stem matched
/// case-insensitively (with `prefix` set, every member whose name starts with
/// `stem` — the DELETE `pfx:` wildcard / KILL sweep; empty stem = all members).
/// PROC DATASETS DELETE must remove the files too, else the EXIST disk probe
/// finds the member and a later SET resurrects the deleted data
/// (BUG-datasetsdeletedisk). Returns the number of files removed; a
/// missing/unreadable dir is 0 (nothing to delete).
pub fn deleteMemberFiles(a: std.mem.Allocator, dir_path: []const u8, stem: []const u8, prefix: bool) usize {
    const io = rawIo();
    var dir = std.Io.Dir.cwd().openDir(io, dir_path, .{ .iterate = true }) catch return 0;
    defer dir.close(io);
    // collect first, delete after — unlinking mid-iteration may skip entries
    var victims: std.ArrayList([]const u8) = .empty;
    var it = dir.iterate();
    while (it.next(io) catch null) |e| {
        if (e.kind != .file) continue;
        const dot = std.mem.lastIndexOfScalar(u8, e.name, '.') orelse continue;
        const known = for (member_exts ++ [_][]const u8{label_ext}) |x| {
            if (std.ascii.eqlIgnoreCase(e.name[dot..], x)) break true;
        } else false;
        const hit = known and if (prefix)
            std.ascii.startsWithIgnoreCase(e.name[0..dot], stem)
        else
            std.ascii.eqlIgnoreCase(e.name[0..dot], stem);
        if (hit) victims.append(a, a.dupe(u8, e.name) catch continue) catch continue;
    }
    var removed: usize = 0;
    for (victims.items) |v| {
        dir.deleteFile(io, v) catch continue;
        removed += 1;
    }
    return removed;
}

// ── CSV serialization (CSV-backed LIBNAME datasets) ──────────────────────────

/// Serialize a dataset to CSV text: row 1 = column names, then one row per
/// observation. Char missing → empty field; numeric missing → `.`. A field is
/// quoted when it has a comma, quote, newline, or leading/trailing space (so the
/// deliberate padding in the corpus survives the round trip).
/// The INTERNAL libname/target CSV: a missing numeric writes "." — round-trips
/// through readCsv and matches every real-SAS golden (BUG-csvregress). The data CSV
/// stays CLEAN (header + rows); labels persist in a `.labels` sidecar.
pub fn writeCsv(a: std.mem.Allocator, ds: *const Dataset) diag.Error![]const u8 {
    return writeCsvImpl(a, ds, false);
}

/// PROC EXPORT (dbms=csv): a missing numeric writes an EMPTY field (`,,`), matching
/// SAS's exported CSV — a "." there would be read back as data by a strict reader
/// (BUG-exportmissing). This variant is ONLY for the EXPORT code path.
pub fn writeCsvExport(a: std.mem.Allocator, ds: *const Dataset) diag.Error![]const u8 {
    return writeCsvImpl(a, ds, true);
}

// ── BUG-csvzerocolphantom: a 0-VARIABLE data set has NO CSV encoding ─────────
// Neither writeCsv nor readCsv has a `*diag.Diagnostics` handle (both are called
// from paths that don't thread one), so they fail loud the way prx.zig already
// does for the same shape: mark the D-009 gap (→ the run exits 2) and print
// UNSUPPORTED:, captured in-process under `zig build test` so a negative test
// never spawns an aborting/stderr-noisy child (D-003).
pub var g_test_last_unsup: []const u8 = "";
var g_unsup_buf: [512]u8 = undefined;

fn loudUnsup(comptime fmt: []const u8, args: anytype) void {
    diag.markGap(); // opensas gap → the run exits 2 (D-009 / FLY-exitcodes)
    if (@import("builtin").is_test) {
        g_test_last_unsup = std.fmt.bufPrint(&g_unsup_buf, fmt, args) catch "io: message too long";
    } else {
        std.debug.print("UNSUPPORTED: " ++ fmt ++ "\n", args);
    }
}

fn writeCsvImpl(a: std.mem.Allocator, ds: *const Dataset, missing_empty: bool) diag.Error![]const u8 {
    // BUG-csvzerocolphantom. CSV CANNOT EXPRESS A 0-VARIABLE DATA SET, on two
    // independent grounds, so writing one produces a file that is a lie:
    //
    //  (1) THE HEADER. A record of k fields is k-1 delimiters, and the fewest
    //      fields any line can yield is ONE (possibly empty) — there is no line
    //      that yields zero. So a 0-column header row is inexpressible: the
    //      empty line we used to emit says "one column whose name is empty",
    //      which every CSV reader must then invent a name for (ours made VAR1;
    //      Excel/R make "" or "X1"). A variable is FABRICATED.
    //  (2) THE OBSERVATIONS. Even granting a convention that an empty header
    //      means 0 columns, each observation is then a ZERO-LENGTH record — so
    //      N obs and N+1 obs differ by exactly one trailing '\n', which is also
    //      exactly what "the file ends with a newline" looks like. The obs count
    //      would ride entirely on trailing whitespace that editors, git and
    //      every CSV tool are entitled to normalise. That is not an encoding.
    //
    // So this is INHERENT, not a bug we can code around, and per house rules
    // (an unsupported case errors visibly, never no-ops) the write REFUSES.
    // Same conclusion and same rc as the sibling native writer, which returns
    // error.Unsupported for ncol==0 (sas7bdat.zig; GAP-xport0colskip,
    // SEV-zerocolrefusal) — a gap is 2 under D-009.
    //
    // The guard is in the SHARED impl deliberately, and that does NOT violate
    // D-001: D-001 forbids changing the writer's behaviour FOR ONE CALLER
    // (BUG-csvregress). The format's inability to hold 0 columns is identical
    // for both callers, and BOTH were probed writing the same 2-byte lie —
    // the libname TARGET path (main.writeMember) and PROC EXPORT (proc.runExport,
    // which was SILENT at rc=0). Guarding only the ticket's path would leave the
    // sibling caller broken.
    //
    // Returns EMPTY rather than an error so the signature stays diag.Error and
    // one bad member does not abort writeLibOutputs' remaining (good) members;
    // main.writeMember skips a zero-length body exactly as it already does for
    // the .sas7bdat one. ponytail: PROC EXPORT still creates a 0-BYTE outfile
    // (proc.zig writes the body unconditionally) — loud and rc=2, and 0 bytes
    // reads back as nothing rather than a phantom column, so it is honest but
    // untidy. Upgrade path: the same `len > 0` guard at proc.zig's writeFileRaw.
    if (ds.columns.items.len == 0) {
        // The message states only what is true on BOTH paths: no CSV BODY. The
        // libname path writes no file at all; PROC EXPORT still creates an empty
        // one (see the ponytail note above). Over-claiming here is the exact
        // defect SEV-zerocolrefusal had to correct in the sibling message.
        loudUnsup("CSV: {s} has 0 variables and CANNOT be written as CSV — an empty header row reads back as one phantom column, and a 0-column observation is a zero-length record indistinguishable from a trailing newline; no CSV body is produced and this data set does NOT survive the run", .{ds.name});
        return "";
    }
    var buf: std.ArrayList(u8) = .empty;
    for (ds.columns.items, 0..) |c, i| {
        if (i > 0) try buf.append(a, ',');
        try appendCsvField(a, &buf, c.name);
    }
    try buf.append(a, '\n');
    for (ds.rows.items) |row| {
        for (row, 0..) |v, i| {
            if (i > 0) try buf.append(a, ',');
            switch (v) {
                // An all-blank char value is character-missing → empty field (SDTM
                // convention). GH#60 makes a quoted `''` a single blank, so `x=""`
                // must still export empty, not " ". Values with content are written
                // verbatim (padding like " A " is preserved for round-trip fidelity).
                .str => |s| if (std.mem.trim(u8, s, " ").len != 0) try appendCsvField(a, &buf, s),
                .num => |x| if (!std.math.isNan(x))
                    try buf.appendSlice(a, try fmtCsvNum(a, x))
                else if (!missing_empty)
                    try buf.append(a, '.') // internal libname: missing → "."
                else if (Value.missingChar(x) != '.') {
                    // NOTE-exportspecialmiss: EXPORT keeps the special-missing
                    // letter (.A–.Z, ._) — an empty field erased the "missing
                    // because A" vs "just missing" distinction. Plain missing
                    // stays empty (BUG-exportmissing). The internal path above
                    // keeps ".": readDelimited can't round-trip a letter back.
                    try buf.appendSlice(a, &[2]u8{ '.', Value.missingChar(x) });
                },
            }
        }
        try buf.append(a, '\n');
    }
    return buf.items;
}

/// Extension of the label sidecar written next to a member's data file.
pub const label_ext = ".labels";

/// The `.labels` sidecar body for `ds`: one CSV-encoded `name,label,format,informat`
/// record per column that carries ANY of those attrs (empty field = attr absent),
/// or null when the dataset has none. These attributes are NOT in the data CSV /
/// sas7bdat, so they'd be lost on reload — the sidecar carries them (F-varlabels;
/// extends BUG-labelspersist from labels to format/informat). The DATASET label
/// (PROC DATASETS MODIFY (LABEL=), SDTM domain descriptions) rides as a record
/// whose name field is the reserved marker `*` — never a legal SAS column name,
/// so old readers can't misapply it to a column (F8: without it the dataset
/// label had NO persistence path and a fresh session could never recover it).
/// Backward-compatible: an old 2-field `name,label` sidecar still applies its label.
pub fn labelSidecar(a: std.mem.Allocator, ds: *const Dataset) diag.Error!?[]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    if (ds.label) |l| {
        try buf.append(a, '*');
        try buf.append(a, ',');
        try appendCsvField(a, &buf, l);
        try buf.append(a, '\n');
    }
    for (ds.columns.items) |c| {
        if (c.label == null and c.format == null and c.informat == null) continue;
        try appendCsvField(a, &buf, c.name);
        try buf.append(a, ',');
        try appendCsvField(a, &buf, c.label orelse "");
        try buf.append(a, ',');
        try appendCsvField(a, &buf, c.format orelse "");
        try buf.append(a, ',');
        try appendCsvField(a, &buf, c.informat orelse "");
        try buf.append(a, '\n');
    }
    return if (buf.items.len == 0) null else buf.items;
}

/// Apply a `.labels` sidecar's bytes to a just-read dataset's columns (no-op for a
/// missing/empty sidecar or a name the dataset doesn't have). Fields after the
/// name — label, format, informat — are each applied only when non-empty, so an
/// old 2-field `name,label` sidecar still works (F-varlabels).
pub fn applyLabelSidecar(a: std.mem.Allocator, ds: *Dataset, bytes: []const u8) diag.Error!void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trimEnd(u8, raw, "\r");
        if (line.len == 0) continue;
        const f = try parseCsvLine(a, line, ',');
        if (f.items.len < 2) continue;
        if (std.mem.eql(u8, f.items[0], "*")) { // F8: dataset-level label record
            if (f.items[1].len > 0) ds.label = f.items[1];
            continue;
        }
        if (f.items[1].len > 0) ds.setLabel(f.items[0], f.items[1]);
        if (f.items.len >= 3 and f.items[2].len > 0) ds.setFormat(f.items[0], f.items[2]);
        if (f.items.len >= 4 and f.items[3].len > 0) ds.setInformat(f.items[0], f.items[3]);
    }
}

/// Parse CSV text into a dataset (the `.csv` libname engine). Row 1 names the
/// columns; numeric columns are inferred from the whole column
/// (BUG-csvnumtype). Date/time detection is PROC IMPORT-only
/// (`detect_dates=false` here) — the `.csv` member engine is an opensas
/// convenience with no SAS counterpart, so its date-shaped columns stay char
/// (GAP-importtypes).
pub fn readCsv(a: std.mem.Allocator, text: []const u8, name: []const u8) diag.Error!*Dataset {
    return readDelimited(a, text, name, ',', true, 2, false);
}

/// Build the `sashelp.vtable` dictionary view: one row per in-memory library
/// member — LIBNAME (the libref, WORK when the name is one-level), MEMNAME (the
/// member), MEMTYPE ("DATA"), NOBS, NVAR. Char values are upper-cased per SAS's
/// dictionary convention so `where libname="TARGET"` matches. Called fresh at each
/// reference (exec.resolveDataset) so it reflects the current library state —
/// %XPT_CREAT enumerates TARGET members from it to drive its XPORT copy loop, and
/// any dataset-listing program can read it (BUG-xptcreat-novtable).
pub fn buildVtable(a: std.mem.Allocator, names: []const []const u8, datasets: []const *Dataset) std.mem.Allocator.Error!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "vtable");
    _ = try ds.addColumn("libname", .char);
    _ = try ds.addColumn("memname", .char);
    _ = try ds.addColumn("memtype", .char);
    _ = try ds.addColumn("nobs", .num);
    _ = try ds.addColumn("nvar", .num);
    for (names, datasets) |nm, d| {
        var libn: []const u8 = "WORK";
        var memn = nm;
        if (std.mem.indexOfScalar(u8, nm, '.')) |dot| {
            libn = nm[0..dot];
            memn = nm[dot + 1 ..];
        }
        try ds.appendRow(&.{
            .{ .str = try upperDup(a, libn) },
            .{ .str = try upperDup(a, memn) },
            .{ .str = "DATA" },
            .{ .num = @floatFromInt(d.rowCount()) },
            .{ .num = @floatFromInt(d.columns.items.len) },
        });
    }

    // GAP-vtabledisk: a libref's DISK-ONLY (never-loaded) members belong in the
    // dictionary view too — a real XPT-export macro discovers its export list
    // from VTABLE, and lazy loading means most members were never SET. Dedupe
    // against loaded members and across engine extensions (dm.sas7bdat + dm.csv
    // = one member DM). ponytail: disk-only rows carry MISSING nobs/nvar —
    // counting means parsing every member file; add when a program reads them.
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    for (ds.rows.items) |r| { // in-memory rows, already upper-cased
        try seen.put(a, try std.fmt.allocPrint(a, "{s}.{s}", .{ r[0].str, r[1].str }), {});
    }
    const rio = rawIo();
    for (dsfns.boundLibrefs()) |lr| {
        // a libref pointed straight at a dataset FILE has no dir to walk
        if (endsWithIgnoreCase(lr.dir, ".sas7bdat") or endsWithIgnoreCase(lr.dir, ".xpt")) continue;
        var dir = std.Io.Dir.cwd().openDir(rio, lr.dir, .{ .iterate = true }) catch continue;
        defer dir.close(rio);
        var it = dir.iterate();
        while (it.next(rio) catch null) |entry| {
            if (entry.kind != .file) continue;
            const stem = for (member_exts) |ext| {
                if (endsWithIgnoreCase(entry.name, ext)) break entry.name[0 .. entry.name.len - ext.len];
            } else continue;
            // a dotted stem can't be a SAS member name (also skips odd sidecars)
            if (std.mem.indexOfScalar(u8, stem, '.') != null) continue;
            const key = try upperDup(a, try std.fmt.allocPrint(a, "{s}.{s}", .{ lr.name, stem }));
            const gop = try seen.getOrPut(a, key);
            if (gop.found_existing) continue;
            const dot = std.mem.indexOfScalar(u8, key, '.').?;
            try ds.appendRow(&.{
                .{ .str = key[0..dot] },
                .{ .str = key[dot + 1 ..] },
                .{ .str = "DATA" },
                Value.missing,
                Value.missing,
            });
        }
    }
    return ds;
}

/// Build the `dictionary.columns` / `sashelp.vcolumn` dictionary view: one row per
/// column of every in-memory library member — LIBNAME (libref, WORK when one-level),
/// MEMNAME (member), NAME (the variable, case preserved as SAS does), TYPE ("char"/
/// "num"), LENGTH, LABEL, VARNUM (1-based). LIBNAME/MEMNAME upper-cased per the
/// dictionary convention so `where libname="WORK"` matches. Built fresh at each
/// reference so it reflects the current library state (ISS-dictviews). ponytail:
/// only in-memory members (no disk-only sweep — that needs parsing each member's
/// schema; add when a program reads columns of an unloaded member).
pub fn buildVcolumn(a: std.mem.Allocator, names: []const []const u8, datasets: []const *Dataset) std.mem.Allocator.Error!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "vcolumn");
    _ = try ds.addColumn("libname", .char);
    _ = try ds.addColumn("memname", .char);
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("type", .char);
    _ = try ds.addColumn("length", .num);
    _ = try ds.addColumn("label", .char);
    _ = try ds.addColumn("varnum", .num);
    for (names, datasets) |nm, d| {
        var libn: []const u8 = "WORK";
        var memn = nm;
        if (std.mem.indexOfScalar(u8, nm, '.')) |dot| {
            libn = nm[0..dot];
            memn = nm[dot + 1 ..];
        }
        const lib_u = try upperDup(a, libn);
        const mem_u = try upperDup(a, memn);
        for (d.columns.items, 0..) |c, j| {
            const is_char = c.type == .char;
            try ds.appendRow(&.{
                .{ .str = lib_u },
                .{ .str = mem_u },
                .{ .str = try a.dupe(u8, c.name) }, // name keeps its stored case
                .{ .str = if (is_char) "char" else "num" },
                .{ .num = @floatFromInt(c.len orelse 8) }, // declared length, else default 8
                .{ .str = try a.dupe(u8, c.label orelse "") },
                .{ .num = @floatFromInt(j + 1) }, // varnum is 1-based
            });
        }
    }
    return ds;
}

fn upperDup(a: std.mem.Allocator, s: []const u8) std.mem.Allocator.Error![]const u8 {
    const buf = try a.alloc(u8, s.len);
    for (s, 0..) |c, i| buf[i] = std.ascii.toUpper(c);
    return buf;
}

/// General delimited-text reader for PROC IMPORT DBMS=CSV/DLM (BUG-importdlm):
/// `delim` is the field separator, `getnames` = row 1 holds the column names
/// (else VAR1.. generated), `datarow` = the 1-based physical line where data
/// begins (SAS default 2 with names). `detect_dates` enables PROC IMPORT's EFI
/// date/time guessing (GAP-importtypes; off for the `.csv` libname engine).
/// `readCsv` is the `,`/getnames/datarow=2/no-dates case.
pub fn readDelimited(a: std.mem.Allocator, text: []const u8, name: []const u8, delim: u8, getnames: bool, datarow: usize, detect_dates: bool) diag.Error!*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);

    // Collect records (CR-trimmed) so DATAROW can index them. The split is
    // QUOTE-AWARE (BUG-importdelimread): under DSD a '\n' (or '\r\n') inside an
    // open double-quoted field is field data — clinical AE verbatim/comment
    // text spans lines — not a record boundary; only an unquoted line break
    // ends the record. Quote state opens only at a field start (record start /
    // just past the delimiter), matching parseCsvLine, and "" is one escaped
    // quote. An embedded break keeps its raw bytes inside the field value.
    var all: std.ArrayList([]const u8) = .empty;
    var in_q = false;
    var field_start = true;
    var rec_start: usize = 0;
    var p: usize = 0;
    while (p < text.len) : (p += 1) {
        const c = text[p];
        if (in_q) {
            if (c == '"') {
                if (p + 1 < text.len and text[p + 1] == '"') p += 1 else in_q = false;
            }
        } else if (c == '"' and field_start) {
            in_q = true;
            field_start = false;
        } else if (c == '\n') {
            try all.append(a, std.mem.trimEnd(u8, text[rec_start..p], "\r"));
            rec_start = p + 1;
            field_start = true;
        } else {
            field_start = c == delim;
        }
    }
    if (rec_start < text.len) try all.append(a, std.mem.trimEnd(u8, text[rec_start..], "\r"));
    if (all.items.len == 0) return ds;

    // Column names: from row 1 when GETNAMES=YES, else VAR1.. sized to the first
    // data line. Data begins at DATAROW (1-based; default 2 with names, 1 without).
    const start = if (datarow > 0) datarow - 1 else if (getnames) @as(usize, 1) else 0;
    var ncol: usize = 0;
    if (getnames) {
        // BUG-csvzerocolphantom: an EMPTY header record declares no columns, so
        // there is nothing to name — inventing `VAR1` here fabricated a variable
        // nobody declared, and it was SILENT (rc=0). Probed on the 2-byte
        // `"\n\n"` a 0-variable member used to write: reload reported
        // `Observations 0, Variables 1`, i.e. the observation lost AND a column
        // invented, in opposite directions. writeCsvImpl now refuses to create
        // such a file, but files already on disk (and foreign CSVs that open
        // with a blank line) still reach here, so the reader refuses too: no
        // columns, no rows, and LOUD (rc=2) rather than a quietly wrong dataset.
        // Narrow on purpose — only a ZERO-LENGTH record. A header like `a,,c`
        // (or `,,`) declares real, merely unnamed columns and keeps the normal
        // VAR-n naming, which is what PROC IMPORT does.
        if (all.items[0].len == 0) {
            loudUnsup("CSV: {s} — the header row declares NO columns (empty first record); a 0-variable data set has no CSV encoding, so nothing is loaded", .{name});
            return ds;
        }
        const hfields = try parseCsvLine(a, all.items[0], delim);
        // Header text → valid V7 names, deduped — the same mangling the XLSX
        // path uses (GH#62), so `First Name`/`Age (yrs)`/`2nd` →
        // `First_Name`/`Age__yrs_`/`_2nd` and duplicate `age,age` →
        // `age`,`age0`. Raw headers were unreferenceable downstream
        // (BUG-importdelimread). GETNAMES=NO still generates VAR1.. below.
        var names: NameSet = .{}; // O(C) dedup (PERF-importhdrquad), uniqueName's exact policy
        for (hfields.items, 0..) |h, c|
            _ = try ds.addColumn(try names.unique(a, validName(a, h, c)), .char);
        ncol = hfields.items.len;
    } else {
        var k = start;
        while (k < all.items.len and all.items[k].len == 0) k += 1;
        if (k < all.items.len) {
            const ff = try parseCsvLine(a, all.items[k], delim);
            ncol = ff.items.len;
            for (0..ncol) |c| _ = try ds.addColumn(try std.fmt.allocPrint(a, "VAR{d}", .{c + 1}), .char);
        }
    }

    // Read all rows as raw string fields first, so a column's type can be
    // inferred from the whole column before the cells are built.
    var srows: std.ArrayList([]const []const u8) = .empty;
    for (all.items[@min(start, all.items.len)..]) |line| {
        if (line.len == 0) continue;
        const fields = try parseCsvLine(a, line, delim);
        const rowf = try a.alloc([]const u8, ncol);
        for (0..ncol) |i| rowf[i] = if (i < fields.items.len) fields.items[i] else "";
        try srows.append(a, rowf);
    }

    // Infer type: a column becomes numeric when it has at least one non-missing
    // value and every non-missing value parses as a number — so a numeric column
    // sorts/compares numerically, not lexically (BUG-csvnumtype). ponytail: a
    // value with a significant leading zero (`007`, `01`) keeps the column
    // character, so zero-padded ids/codes aren't silently renumbered.
    for (0..ncol) |ci| {
        var any = false;
        var all_num = true;
        for (srows.items) |rowf| {
            const f = rowf[ci];
            if (isCsvMissing(f)) continue;
            any = true;
            if (parseF64(f) == null or hasLeadingZero(f)) {
                all_num = false;
                break;
            }
        }
        if (any and all_num) ds.columns.items[ci].type = .num;
    }

    // EFI date/time guessing (GAP-importtypes), PROC IMPORT only: a
    // still-character column whose EVERY non-missing value fits the SAME
    // recognised date/time pattern becomes NUMERIC with that format attached —
    // Procedures Guide p. 1330 (see format.importDateGuess for the recognised
    // set + citations). A MIXED column stays character: one informat must fit
    // every value, else "the type remains character". ponytail: field quoting
    // is lost by parseCsvLine, so a QUOTED date is detected too — SAS's EFI
    // default keeps quoted values character (p. 1325 EFI_QUOTED_NUMERICS);
    // the numeric inference above has always had that ceiling. Upgrade path:
    // thread per-field quoted flags through parseCsvLine.
    const col_date = try a.alloc(?format.ImportDateKind, ncol);
    for (col_date) |*cd| cd.* = null;
    if (detect_dates) {
        for (0..ncol) |ci| {
            if (ds.columns.items[ci].type == .num) continue; // numeric already won
            var kind: ?format.ImportDateKind = null;
            var any = false;
            var maxw: usize = 0;
            var uniform = true;
            for (srows.items) |rowf| {
                const f = std.mem.trim(u8, rowf[ci], " ");
                if (isCsvMissing(f)) continue;
                any = true;
                maxw = @max(maxw, f.len);
                const g = format.importDateGuess(f) orelse {
                    uniform = false;
                    break;
                };
                if (kind == null) {
                    kind = g.kind;
                } else if (kind.? != g.kind) {
                    uniform = false;
                    break;
                }
            }
            if (any and uniform) if (kind) |k| {
                const spec = try std.fmt.allocPrint(a, "{s}{d}.", .{ format.importDateFormatName(k), maxw });
                ds.columns.items[ci].type = .num;
                ds.columns.items[ci].format = spec;
                ds.columns.items[ci].informat = spec;
                col_date[ci] = k;
            };
        }
    }

    for (srows.items) |rowf| {
        const cells = try a.alloc(Value, ncol);
        for (0..ncol) |ci| {
            if (col_date[ci] != null) {
                // detection passed every value → the re-guess cannot fail
                cells[ci] = if (isCsvMissing(rowf[ci])) Value.missing else .{ .num = format.importDateGuess(rowf[ci]).?.value };
            } else if (ds.columns.items[ci].type == .num) {
                cells[ci] = if (isCsvMissing(rowf[ci])) Value.missing else .{ .num = parseF64(rowf[ci]).? };
            } else cells[ci] = .{ .str = rowf[ci] };
        }
        try ds.rows.append(a, cells);
    }
    return ds;
}

/// A CSV field that counts as missing for type inference / numeric loading: an
/// empty (or all-blank) field, or the SAS numeric-missing marker `.`.
fn isCsvMissing(f: []const u8) bool {
    const t = std.mem.trim(u8, f, " ");
    return t.len == 0 or std.mem.eql(u8, t, ".");
}

fn parseF64(f: []const u8) ?f64 {
    return std.fmt.parseFloat(f64, std.mem.trim(u8, f, " ")) catch null;
}

/// True for a zero-padded token like `007`/`01` (a leading `0` before another
/// digit) — kept character so ids/codes aren't renumbered. `0`, `0.5`, `0e3`
/// are ordinary numbers and return false.
fn hasLeadingZero(f: []const u8) bool {
    const t = std.mem.trim(u8, f, " ");
    const s = if (t.len > 0 and (t[0] == '+' or t[0] == '-')) t[1..] else t;
    return s.len >= 2 and s[0] == '0' and std.ascii.isDigit(s[1]);
}

/// A SAS-valid variable name from a header cell per VALIDVARNAME=V7 (the SAS 9.4
/// default): trim, every char that is not a letter/digit/`_` → one `_` (runs are
/// NOT collapsed and trailing `_` is KEPT), prepend `_` if empty or starting with
/// a digit, truncate to 32 bytes, empty → VAR{col}. Duplicate-name dedup is the
/// caller's job (it needs the sibling set). Shared by the CSV/DLM (readDelimited)
/// and XLSX (proc.zig GH#62) import paths.
pub fn validName(arena: std.mem.Allocator, raw: []const u8, col: usize) []const u8 {
    const tr = std.mem.trim(u8, raw, " \t\r\n");
    var buf: std.ArrayList(u8) = .empty;
    for (tr) |ch| {
        buf.append(arena, if (std.ascii.isAlphanumeric(ch) or ch == '_') ch else '_') catch break;
    }
    if (buf.items.len == 0) return std.fmt.allocPrint(arena, "VAR{d}", .{col + 1}) catch "VAR";
    if (std.ascii.isDigit(buf.items[0])) buf.insert(arena, 0, '_') catch {};
    if (buf.items.len > 32) buf.shrinkRetainingCapacity(32);
    return buf.items;
}

/// Ensure `name` is unique (case-insensitively) among `used`, appending it.
/// SAS PROC IMPORT dedups collided names by appending an increasing integer
/// (Foo, Foo0, Foo1, …), truncating the base so the result stays ≤32 bytes.
/// ponytail: append-0,1,2 with 32-byte cap — Language Reference: Concepts documents V7 but not the
/// import dedup scheme; this matches observed SAS behavior. Revisit if a corpus
/// case shows a different suffix start.
pub fn uniqueName(arena: std.mem.Allocator, used: *std.ArrayList([]const u8), name: []const u8) ![]const u8 {
    if (!nameTaken(used.items, name)) {
        try used.append(arena, name);
        return name;
    }
    var n: usize = 0;
    while (true) : (n += 1) {
        var sbuf: [16]u8 = undefined;
        const suffix = std.fmt.bufPrint(&sbuf, "{d}", .{n}) catch unreachable;
        const base_len = @min(name.len, 32 - suffix.len);
        const cand = try std.fmt.allocPrint(arena, "{s}{s}", .{ name[0..base_len], suffix });
        if (!nameTaken(used.items, cand)) {
            try used.append(arena, cand);
            return cand;
        }
    }
}

fn nameTaken(used: []const []const u8, name: []const u8) bool {
    for (used) |u| if (eqi(u, name)) return true;
    return false;
}

/// O(C) accepted-name set for GETNAMES header dedup (PERF-importhdrquad):
/// uniqueName's naming policy byte-identically (first wins unchanged; else
/// base+0,1,2,… truncated to ≤32 bytes; case-insensitive membership), but the
/// membership test is a lowercase-keyed hash set — the same pattern as
/// exec.zig's freezeNameList — instead of nameTaken's O(C) rescan per column,
/// which made a C-column import O(C²). ponytail: the XLSX path still uses
/// uniqueName (quadratic) because its call site is proc.zig, another dev's
/// file; switch it to NameSet when that lock clears.
pub const NameSet = struct {
    taken: std.StringHashMapUnmanaged(void) = .empty, // lowercase folded keys

    pub fn unique(self: *NameSet, arena: std.mem.Allocator, name: []const u8) ![]const u8 {
        if (!try self.has(arena, name)) {
            try self.taken.put(arena, try std.ascii.allocLowerString(arena, name), {});
            return name;
        }
        var n: usize = 0;
        while (true) : (n += 1) {
            var sbuf: [16]u8 = undefined;
            const suffix = std.fmt.bufPrint(&sbuf, "{d}", .{n}) catch unreachable;
            const base_len = @min(name.len, 32 - suffix.len);
            const cand = try std.fmt.allocPrint(arena, "{s}{s}", .{ name[0..base_len], suffix });
            if (!try self.has(arena, cand)) {
                try self.taken.put(arena, try std.ascii.allocLowerString(arena, cand), {});
                return cand;
            }
        }
    }

    fn has(self: *NameSet, arena: std.mem.Allocator, name: []const u8) !bool {
        // validName caps at 32 bytes; stack-fold like Pdv.indexOf, heap-fold an
        // over-long name out of caution.
        var buf: [64]u8 = undefined;
        const key = if (name.len <= buf.len) std.ascii.lowerString(&buf, name) else try std.ascii.allocLowerString(arena, name);
        return self.taken.contains(key);
    }
};

fn appendCsvField(a: std.mem.Allocator, buf: *std.ArrayList(u8), s: []const u8) !void {
    const quote = s.len > 0 and (s[0] == ' ' or s[s.len - 1] == ' ' or
        std.mem.indexOfAny(u8, s, ",\"\n") != null);
    if (!quote) return buf.appendSlice(a, s);
    try buf.append(a, '"');
    for (s) |c| {
        if (c == '"') try buf.append(a, '"'); // double an embedded quote
        try buf.append(a, c);
    }
    try buf.append(a, '"');
}

/// Split one CSV line into fields, honouring `"…"` quoting (with `""` escapes).
fn parseCsvLine(a: std.mem.Allocator, line: []const u8, delim: u8) !std.ArrayList([]const u8) {
    var fields: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (true) {
        var cell: std.ArrayList(u8) = .empty;
        if (i < line.len and line[i] == '"') {
            i += 1;
            while (i < line.len) : (i += 1) {
                if (line[i] == '"') {
                    if (i + 1 < line.len and line[i + 1] == '"') {
                        try cell.append(a, '"');
                        i += 1;
                    } else {
                        i += 1;
                        break;
                    }
                } else try cell.append(a, line[i]);
            }
        } else {
            const start = i;
            while (i < line.len and line[i] != delim) i += 1;
            try cell.appendSlice(a, line[start..i]);
        }
        try fields.append(a, cell.items);
        if (i >= line.len or line[i] != delim) break;
        i += 1; // past the delimiter
    }
    return fields;
}

fn fmtCsvNum(a: std.mem.Allocator, x: f64) ![]const u8 {
    return format.bestNum(a, x); // SAS default numeric format (BEST12.)
}

// ── dataset options: keep= / drop= / rename= ────────────────────────────────

/// Apply the options inside a `dataset(...)` spec to an already-built dataset.
/// `opt_toks` are the tokens between the outer parens, e.g. `keep = x` or
/// `rename = ( x = z )`. keep/drop restrict the columns; rename relabels them.
/// The parse is deliberately here (io owns the dataset shape); the CLI just
/// hands over the token slice. ponytail: no WHERE=/FIRSTOBS=/OBS= yet, and
/// keep/drop use original names (applied before rename) — SAS's exact
/// keep-vs-rename ordering can wait for a corpus fixture that pins it.
/// `input` selects DKRICOND (input datasets: SET/MERGE/UPDATE source, PROC SQL
/// FROM) vs DKROCOND (output datasets + DROP/KEEP/RENAME statement). SAS 9.4
/// defaults DKRICOND=ERROR (fatal, step aborts) and DKROCOND=WARN — so a
/// keep/drop/rename of a nonexistent variable is fatal on INPUT, a warning on
/// OUTPUT (GH#71 corrects GH#22's "both WARN" premise).
pub fn applyDatasetOptions(a: std.mem.Allocator, ds: *Dataset, opt_toks: []const lex.Token, diags: *diag.Diagnostics, input: bool) diag.Error!void {
    return applyDatasetOptionsObs(a, ds, opt_toks, diags, input, false, null, &.{});
}

/// applyDatasetOptions plus the producing step's full PDV name set
/// (BUG-dropoptfalsewarn). The OUTPUT-option "never been referenced" check
/// runs against the FINALIZED dataset, whose schema the executor already
/// stripped of temporary PDV vars (SET end=/in= temps, statement-dropped
/// vars) — `data b(drop=e); set a end=e;` false-warned though `e` was plainly
/// referenced. The STATEMENT path validates against the PDV
/// (exec.assertReferenced); handing the same set in makes both spellings of
/// DROP/KEEP/RENAME reach the SAME answer (D-009b's corollary).
pub fn applyDatasetOptionsRefs(a: std.mem.Allocator, ds: *Dataset, opt_toks: []const lex.Token, diags: *diag.Diagnostics, input: bool, pdv_refs: []const []const u8) diag.Error!void {
    return applyDatasetOptionsObs(a, ds, opt_toks, diags, input, false, null, pdv_refs);
}

/// firstobs=/obs= slice: keep 1-based POSITIONS firstobs..obs of the rows AS
/// THEY CURRENTLY STAND (i.e. after any WHERE filter already applied). INPUT
/// only; on OUTPUT SAS ignores the range. Global `options firstobs=/obs=`
/// supply the defaults. Split out of applyDatasetOptionsObs (BUG-wherestmtobsorder)
/// so the DATA-step WHERE STATEMENT can filter BEFORE this counts positions —
/// mirroring the where= OPTION, which already filters first within one call.
pub fn applyObsSlice(a: std.mem.Allocator, ds: *Dataset, opt_toks: []const lex.Token, input: bool, obs_out: ?*?[]const usize) diag.Error!void {
    if (!input) return;
    var firstobs: usize = global_firstobs;
    var last: usize = global_obs;
    var i: usize = 0;
    while (i + 2 < opt_toks.len) : (i += 1) {
        if (opt_toks[i].tag == .name and opt_toks[i + 1].tag == .eq) {
            // parseObsValue honours integers, the K/M/G suffix (`obs=2k` is
            // 2048), MAX and MIN. A value it REJECTS (`obs=abc`, `firstobs=-1`)
            // is not applied here and is diagnosed LOUD by the option walk in
            // applyDatasetOptionsObs (BUG-dsobsvaluenovalidate) — this fn has
            // no diags of its own (exec.zig calls it directly).
            if (eqiTok(opt_toks[i].text, "firstobs")) {
                if (parseObsValue(opt_toks, i + 2)) |pv| firstobs = pv.val;
            } else if (eqiTok(opt_toks[i].text, "obs")) {
                if (parseObsValue(opt_toks, i + 2)) |pv| last = pv.val;
            }
        }
    }
    if (firstobs > 1 or last != std.math.maxInt(usize)) {
        const n = ds.rows.items.len;
        // FIRSTOBS=MAX starts at the LAST observation (BUG-dsobsvaluenovalidate
        // — it used to fall off the parse and silently return ALL rows).
        const lo = @min(if (firstobs == std.math.maxInt(usize)) n -| 1 else if (firstobs > 0) firstobs - 1 else 0, n);
        const hi = @min(last, n); // rows[lo..hi] = obs firstobs..obs (1-based)
        if (obs_out) |t| { // surviving range = source obs lo+1..hi (or a re-slice of the prior list)
            const kept = if (lo >= hi) 0 else hi - lo;
            const nl = try a.alloc(usize, kept);
            for (nl, 0..) |*v, k| v.* = if (t.*) |l| l[lo + k] else lo + k + 1;
            t.* = nl;
        }
        if (lo >= hi) {
            ds.rows.items.len = 0;
        } else {
            const kept = hi - lo;
            if (lo > 0) std.mem.copyForwards([]const Value, ds.rows.items[0..kept], ds.rows.items[lo..hi]);
            ds.rows.items.len = kept;
        }
    }
}

/// applyDatasetOptions + source-observation tracking (BUG-printobsnum): when
/// `obs_out` is non-null it receives, for every row that survives the where=
/// filter and the firstobs=/obs= slice, that row's 1-based physical
/// observation number in the dataset as it stood BEFORE this call chain
/// filtered. Thread the same `obs_out` across successive calls on one copy
/// (procInput: range options, then the WHERE statement) so a later WHERE
/// sub-selects the numbers an earlier FIRSTOBS= established. PROC PRINT reads
/// the list for its Obs column; every other caller passes null.
pub fn applyDatasetOptionsObs(a: std.mem.Allocator, ds: *Dataset, opt_toks: []const lex.Token, diags: *diag.Diagnostics, input: bool, skip_obs_slice: bool, obs_out: ?*?[]const usize, pdv_refs: []const []const u8) diag.Error!void {
    // `where=(expr)` filters rows FIRST (BUG-whereobsorder): SAS applies WHERE
    // before firstobs=/obs= count POSITIONS within the WHERE-selected subset —
    // slicing first kept the wrong rows. The WHERE also runs while the original
    // columns are still present (a `keep=`/`rename=` might otherwise remove a
    // column it references), and SAS applies `rename=` BEFORE evaluating the
    // WHERE, so a WHERE that references the RENAMED (new) name must resolve —
    // pass the rename map so applyWhere also exposes each new name
    // (BUG-setwhererename).
    var wr_old: std.ArrayList([]const u8) = .empty;
    var wr_new: std.ArrayList([]const u8) = .empty;
    try extractRenames(a, opt_toks, &wr_old, &wr_new);
    try applyWhere(a, ds, opt_toks, wr_old.items, wr_new.items, diags, obs_out);

    // `firstobs=`/`obs=`: the observation range to read, counted as 1-based
    // POSITIONS WITHIN the WHERE-selected rows above (`obs=k` is the LAST
    // position — an upper bound, not a count). With no where= this is the raw
    // physical range, unchanged (G-dsopt: these were parsed but silently
    // ignored → wrong data). On an INPUT read the global `options
    // obs=/firstobs=` supply the DEFAULT range; a per-dataset option below
    // overrides it field by field (BUG-globalobs). obs=/firstobs= are
    // INPUT-ONLY options: on an OUTPUT dataset SAS ignores them and writes ALL
    // rows — applying the slice there silently drops output rows
    // (BUG-outdsobsslice). where= stays honored on output (applied above).
    // skip_obs_slice: the DATA-step WHERE STATEMENT path defers this slice to
    // after applyWhereStmt so firstobs=/obs= count positions within the
    // WHERE-selected subset (BUG-wherestmtobsorder); resolveDataset re-runs
    // applyObsSlice once the statement filter is in.
    if (!skip_obs_slice) try applyObsSlice(a, ds, opt_toks, input, obs_out);

    var keep: std.ArrayList([]const u8) = .empty;
    var drop: std.ArrayList([]const u8) = .empty;
    var rn_old: std.ArrayList([]const u8) = .empty;
    var rn_new: std.ArrayList([]const u8) = .empty;

    var i: usize = 0;
    while (i < opt_toks.len) {
        // an option is `key = …`; anything else we skip past
        if (!(opt_toks[i].tag == .name and i + 1 < opt_toks.len and opt_toks[i + 1].tag == .eq)) {
            i += 1;
            continue;
        }
        const key = opt_toks[i].text;
        i += 2; // past `key =`
        if (eqiTok(key, "keep")) {
            try collectNames(a, opt_toks, &i, &keep);
        } else if (eqiTok(key, "drop")) {
            try collectNames(a, opt_toks, &i, &drop);
        } else if (eqiTok(key, "rename")) {
            if (i < opt_toks.len and opt_toks[i].tag == .lparen) {
                i += 1;
                while (i < opt_toks.len and opt_toks[i].tag != .rparen) {
                    if (opt_toks[i].tag == .name and i + 2 < opt_toks.len and opt_toks[i + 1].tag == .eq and opt_toks[i + 2].tag == .name) {
                        try rn_old.append(a, opt_toks[i].text);
                        try rn_new.append(a, opt_toks[i + 2].text);
                        i += 3;
                    } else i += 1;
                }
                if (i < opt_toks.len) i += 1; // past `)`
            }
        } else if (eqiTok(key, "where")) {
            // Consumed by applyWhere above — skip the balanced (…) so a
            // `name =` INSIDE the predicate never reaches the unknown-option
            // error below (over-strictness guard, D-014's lesson).
            if (i < opt_toks.len and opt_toks[i].tag == .lparen) {
                var depth: usize = 0;
                while (i < opt_toks.len) : (i += 1) {
                    if (opt_toks[i].tag == .lparen) depth += 1 else if (opt_toks[i].tag == .rparen) {
                        depth -= 1;
                        if (depth == 0) {
                            i += 1; // past `)`
                            break;
                        }
                    }
                }
            }
        } else if (eqiTok(key, "firstobs") or eqiTok(key, "obs")) {
            // BUG-dsobsvaluenovalidate (F5): the VALUE is validated on INPUT —
            // the system-option and INFILE-option paths both fail loud on
            // `obs=abc` / `firstobs=0` / `firstobs=-1` while this path silently
            // read EVERY row (and `obs=2k` silently sliced 2). Same wording as
            // the OPTIONS handler; on INPUT mirror the unknown-option arm —
            // 0 rows, never the unbounded superset. On OUTPUT the range is
            // ignored entirely (settled, BUG-outdsobsslice) → nothing to
            // validate, consume loosely.
            if (input) {
                const pv = parseObsValue(opt_toks, i);
                if (pv == null or (eqiTok(key, "firstobs") and pv.?.val == 0)) {
                    // name the bad value; a sign lexes as its own empty-text token
                    const bad = if (i < opt_toks.len and (opt_toks[i].tag == .minus or opt_toks[i].tag == .plus) and
                        i + 1 < opt_toks.len and opt_toks[i + 1].tag == .number)
                        try std.fmt.allocPrint(a, "{s}{s}", .{ if (opt_toks[i].tag == .minus) "-" else "+", opt_toks[i + 1].text })
                    else if (i < opt_toks.len)
                        opt_toks[i].text
                    else
                        "";
                    try diags.report(.err, 0, "Invalid value {s} for the {s} option.", .{ bad, if (eqiTok(key, "firstobs")) "FIRSTOBS" else "OBS" });
                    ds.rows = .empty;
                    if (obs_out) |t| t.* = &.{};
                    return;
                }
                i += pv.?.consumed;
            } else if (i < opt_toks.len) i += 1;
        } else if (eqiTok(key, "in")) {
            // Single-token value, consumed by exec.inVarOf.
            if (i < opt_toks.len) i += 1;
        } else {
            // BUG-wheredsoptswallow: a misspelled or unimplemented option used
            // to fall through this chain and vanish — `set d(wehre=(x>2))`
            // then ran UNFILTERED at exit 0, a silent superset of the intended
            // rows (a typo in a filter silently DISABLES it). Fail loud
            // (D-002), naming the option so the typo is obvious; on INPUT
            // mirror whereoptunknownvar — 0 rows, never the superset.
            // NOTE-typoarmgapwording: the WORDING splits on who is wrong
            // (macro.zig's STORE/STROE split). A DOCUMENTED option opensas has
            // not implemented (pw=/whereup=/… — every word in
            // documentedDsoptGap) is valid SAS 9.4, an opensas gap, so it says
            // "is not supported" (its rc stays 1 here — exec.zig's hash pw=
            // test pins it; making every gap path exit 2 is DEC-abortrcvsD009).
            // Anything else is a TYPO — the user's own SAS, rc 1 (D-009) — so
            // it says "Unrecognized", never the gap vocabulary a downstream
            // agent routes on.
            if (documentedDsoptGap(key)) {
                try diags.report(.err, 0, "dataset option {s}= is not supported", .{key});
            } else {
                try diags.report(.err, 0, "Unrecognized dataset option {s}=", .{key});
            }
            if (input) {
                ds.rows = .empty;
                if (obs_out) |t| t.* = &.{};
            }
            return;
        }
    }

    // GH#22 ISS-dkrocondwarn / GH#71: a keep/drop name — or a rename OLD name —
    // that matches NO column is a typo. Severity follows the DKRICOND=/DKROCOND=
    // system options (SAS 9.4 defaults: ERROR on INPUT, WARN on OUTPUT — a warn
    // still runs the step, RC=4). Nonexistent names are simply ignored, never a
    // halt of their own. GH#19 wrongly ERRORed+aborted unconditionally here.
    // `ds` is the right set at each call site: input opts run against the
    // source dataset, output opts against the finalized one. (Statement RENAME
    // is validated in exec; the tokens it hands here only name present columns.)
    try reportUnreferenced(a, ds, keep.items, diags, input, pdv_refs);
    try reportUnreferenced(a, ds, drop.items, diags, input, pdv_refs);
    try reportUnreferenced(a, ds, rn_old.items, diags, input, pdv_refs);

    // keep/drop: build a column mask, then rebuild the schema + every row.
    if (keep.items.len > 0 or drop.items.len > 0) {
        const mask = try a.alloc(bool, ds.columns.items.len);
        for (ds.columns.items, 0..) |c, ci| {
            // keep-then-drop (BUG-whereobsorder): a var survives iff it is in
            // keep= (when keep= is given) AND not in drop= — a var explicitly
            // kept then dropped is dropped; keep= no longer disables drop=.
            mask[ci] = (keep.items.len == 0 or nameIn(keep.items, c.name)) and !nameIn(drop.items, c.name);
        }
        try filterColumns(a, ds, mask);
    }

    // rename: relabel columns (original names still valid here). If the target
    // name is already taken by a *different* column, renaming would create two
    // identically-named columns — data loss when a later `set` collapses them.
    // SAS WARNS ("Variable … already exists") and leaves the column unrenamed;
    // we do the same (BUG-renamedup). Severity matters since BUG-errhalt: an
    // .err here would wrongly poison every downstream step into syntax-check
    // mode, where real SAS carries on.
    for (rn_old.items, rn_new.items) |o, n| {
        const ci = ds.indexOf(o) orelse continue;
        if (ds.indexOf(n)) |taken| if (taken != ci) {
            // Route through Diagnostics (rendered by the CLI after the run), NOT a
            // raw std.debug.print — printing to stderr *during* a unit test corrupts
            // `zig build test`'s --listen= IPC and fails the run intermittently
            // (BUG-transposedup). The rename is still refused, as SAS does.
            diags.report(.warning, 0, "Variable {s} already exists on dataset {s}", .{ n, ds.name }) catch {};
            continue;
        };
        ds.columns.items[ci].name = try a.dupe(u8, n);
    }
}

/// Report every `names` entry that resolves to no column of `ds` — the "never
/// been referenced" case shared by keep=/drop= and the rename OLD names. SAS
/// uppercases the name here. Severity follows the DKRICOND=/DKROCOND= system
/// options (Language Reference: Concepts pp.184-185; io.global_dkricond/global_dkrocond, SAS 9.4
/// defaults ERROR on INPUT / WARN on OUTPUT, GH#71). This is NOT the
/// rename-onto-an-existing-target case (always WARNs, BUG-renamedup).
fn reportUnreferenced(a: std.mem.Allocator, ds: *const Dataset, names: []const []const u8, diags: *diag.Diagnostics, input: bool, pdv_refs: []const []const u8) std.mem.Allocator.Error!void {
    const lvl = if (input) global_dkricond else global_dkrocond;
    if (lvl == .nowarn) return;
    for (names) |name| {
        // `pfx:` name-prefix wildcard is a pattern, not a literal name — skip it.
        if (name.len > 0 and name[name.len - 1] == ':') continue;
        if (ds.indexOf(name) != null) continue;
        // A var the producing step held in its PDV but excluded from the
        // output schema (end=/in= temp, statement-dropped) WAS referenced —
        // the statement path's PDV check (exec.assertReferenced) says so.
        const in_pdv = for (pdv_refs) |r| {
            if (eqi(r, name)) break true;
        } else false;
        if (in_pdv) continue;
        const up = try std.ascii.allocUpperString(a, name);
        try diags.report(if (lvl == .err) .err else .warning, 0, "The variable {s} in the DROP, KEEP, or RENAME list has never been referenced", .{up});
    }
}

/// Apply a `where=(expr)` input dataset option: keep only rows for which the
/// predicate is true. The predicate is parsed and evaluated per row against a
/// throwaway PDV, so no executor state is involved. BUG-wherefunc: the PDV is
/// throwaway, the diags and call_fn must be REAL — a local sink with no
/// dispatch made `where=(upcase(x)="Y")` silently misfilter (function →
/// unsupported → missing, error invisible; fail-loud violated).
fn applyWhere(a: std.mem.Allocator, ds: *Dataset, opt_toks: []const lex.Token, rn_old: []const []const u8, rn_new: []const []const u8, diags: *diag.Diagnostics, obs_out: ?*?[]const usize) !void {
    const wtoks = try extractWhere(a, opt_toks) orelse return;

    // Desugar SQL-style infix predicates (IS [NOT] NULL/MISSING, BETWEEN, LIKE,
    // CONTAINS) to ordinary expressions BEFORE parsing — the exact path PROC SQL
    // takes — so where=(nd is null) agrees with missing()/PROC SQL instead of
    // silently dropping the `is null` tokens and inverting (GH#35 ISS-wherenull).
    // desugarPredicates reports its own specifics (BUG-wherebetweenexpr); the
    // old generic "unable to parse" catch would double-report.
    const dtoks = sql.desugarPredicates(a, diags, wtoks) catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else {};

    var pp = pe.Parser.init(a, dtoks, diags);
    pp.where_ctx = true; // `<>` means NE in a where= expression (BUG-wherene)
    const cond = pp.parseExpr() catch |e| return if (e == error.OutOfMemory) error.OutOfMemory else {};
    // Fail LOUD on leftover tokens: an unrecognized predicate leaves tokens the
    // parser never consumed. Reporting beats silently ignoring them and keeping
    // the wrong rows (GH#35).
    if (pp.peek().tag != .eof)
        return diags.report(.err, pp.peek().line, "unexpected token '{s}' in WHERE= dataset-option predicate", .{pp.peek().text}) catch {};

    // Every variable the predicate names must be a column of the source (or a
    // rename= NEW name it's evaluated against) — an unknown name evals to missing
    // and silently filtered EVERY row (BUG-whereoptunknownvar). Fail loud like
    // the WHERE STATEMENT path (exec.checkWhereVars): report, drop all rows, stop.
    if (!whereVarOnDataset(cond, ds, rn_new, diags)) {
        ds.rows = .empty;
        if (obs_out) |t| t.* = &.{};
        return;
    }

    var pdv = Pdv.init(a);
    var ev: eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = diags, .call_fn = &functions.dispatch };

    var kept: std.ArrayList([]const Value) = .empty;
    var kept_obs: std.ArrayList(usize) = .empty;
    for (ds.rows.items, 0..) |row, ri| {
        for (ds.columns.items, 0..) |col, j| {
            _ = try pdv.define(col.name, col.type);
            try pdv.set(col.name, row[j]);
            // SAS renames before the WHERE, so a where= on the NEW name resolves;
            // also keep the OLD name defined so a where= on it still works (the
            // existing control) — BUG-setwhererename.
            for (rn_old, rn_new) |o, n| if (eqiTok(o, col.name)) {
                _ = try pdv.define(n, col.type);
                try pdv.set(n, row[j]);
            };
        }
        // WHERE-context truthiness (Language Reference: Concepts p.216): a bare char var means
        // non-blank — whereTruthy, NOT the IF rule (BUG-wherebarechar).
        if ((try ev.eval(cond)).whereTruthy()) {
            try kept.append(a, row);
            if (obs_out) |t| try kept_obs.append(a, if (t.*) |l| l[ri] else ri + 1);
        }
    }
    ds.rows = kept;
    if (obs_out) |t| t.* = kept_obs.items;
}

/// Every variable a where=(…) predicate references must be a column of `ds` (or a
/// rename= NEW name, which applyWhere exposes to the PDV). Mirrors
/// exec.checkWhereVars for the dataset-OPTION path (BUG-whereoptunknownvar):
/// reports "Variable X is not on file DS" on the first miss and returns false.
fn whereVarOnDataset(e: *const ast.Expr, ds: *const Dataset, rn_new: []const []const u8, diags: *diag.Diagnostics) bool {
    return switch (e.*) {
        .variable => |name| {
            for (ds.columns.items) |c| if (eqiTok(c.name, name)) return true;
            for (rn_new) |n| if (eqiTok(n, name)) return true;
            diags.report(.err, 0, "Variable {s} is not on file {s}", .{ name, ds.name }) catch {};
            return false;
        },
        .unary => |u| whereVarOnDataset(u.operand, ds, rn_new, diags),
        .binary => |b| whereVarOnDataset(b.lhs, ds, rn_new, diags) and whereVarOnDataset(b.rhs, ds, rn_new, diags),
        .call => |c| {
            for (c.args) |*arg| if (!whereVarOnDataset(arg, ds, rn_new, diags)) return false;
            return true;
        },
        .array_ref => |ar| whereVarOnDataset(ar.index, ds, rn_new, diags),
        .num, .str, .missing => true,
    };
}

/// Collect the `rename=(old=new …)` pairs from a dataset-option token slice, so a
/// WHERE that references a renamed name can be evaluated against it. Mirrors the
/// rename parse in applyDatasetOptions (kept separate so the WHERE runs first).
fn extractRenames(a: std.mem.Allocator, opt_toks: []const lex.Token, rn_old: *std.ArrayList([]const u8), rn_new: *std.ArrayList([]const u8)) !void {
    var i: usize = 0;
    while (i < opt_toks.len) {
        if (!(opt_toks[i].tag == .name and eqiTok(opt_toks[i].text, "rename") and
            i + 1 < opt_toks.len and opt_toks[i + 1].tag == .eq and
            i + 2 < opt_toks.len and opt_toks[i + 2].tag == .lparen))
        {
            i += 1;
            continue;
        }
        i += 3; // past `rename = (`
        while (i < opt_toks.len and opt_toks[i].tag != .rparen) {
            if (opt_toks[i].tag == .name and i + 2 < opt_toks.len and opt_toks[i + 1].tag == .eq and opt_toks[i + 2].tag == .name) {
                try rn_old.append(a, opt_toks[i].text);
                try rn_new.append(a, opt_toks[i + 2].text);
                i += 3;
            } else i += 1;
        }
    }
}

/// Extract the tokens inside `where=(…)` (with a trailing `.eof` so the
/// expression parser can peek past the end), or null if there's no where= option.
fn extractWhere(a: std.mem.Allocator, toks: []const lex.Token) !?[]lex.Token {
    var i: usize = 0;
    while (i + 2 < toks.len) : (i += 1) {
        if (!(toks[i].tag == .name and eqiTok(toks[i].text, "where") and
            toks[i + 1].tag == .eq and toks[i + 2].tag == .lparen)) continue;
        var depth: usize = 1;
        var j = i + 3;
        while (j < toks.len) : (j += 1) {
            if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        const inner = toks[i + 3 .. j];
        const out = try a.alloc(lex.Token, inner.len + 1);
        @memcpy(out[0..inner.len], inner);
        out[inner.len] = .{ .tag = .eof };
        return out;
    }
    return null;
}

/// Collect bare variable names for a keep/drop list, stopping at the next option
/// (a `name =`) or the end of the option tokens.
fn collectNames(a: std.mem.Allocator, toks: []const lex.Token, i: *usize, out: *std.ArrayList([]const u8)) !void {
    while (i.* < toks.len and toks[i.*].tag == .name) {
        if (i.* + 1 < toks.len and toks[i.* + 1].tag == .eq) break; // next option key
        // `a1-a3` numbered range: stopping at the `-` silently kept only `a1`
        // and DROPPED the rest, no diagnostic (QA-dsoptrange). Expand it here.
        if (i.* + 2 < toks.len and toks[i.* + 1].tag == .minus and toks[i.* + 2].tag == .name) {
            try @import("parser.zig").expandRange(a, out, toks[i.*].text, toks[i.* + 2].text);
            i.* += 3;
            continue;
        }
        try out.append(a, toks[i.*].text);
        i.* += 1;
    }
}

/// Keep only the columns whose mask bit is set, rebuilding each row to match.
fn filterColumns(a: std.mem.Allocator, ds: *Dataset, mask: []const bool) !void {
    var kept: std.ArrayList(usize) = .empty;
    for (mask, 0..) |m, ci| if (m) try kept.append(a, ci);

    for (ds.rows.items, 0..) |row, r| {
        const nr = try a.alloc(Value, kept.items.len);
        for (kept.items, 0..) |ci, k| nr[k] = row[ci];
        ds.rows.items[r] = nr;
    }
    var cols: std.ArrayList(@TypeOf(ds.columns.items[0])) = .empty;
    for (kept.items) |ci| try cols.append(a, ds.columns.items[ci]);
    ds.columns = cols;
}

fn nameIn(list: []const []const u8, name: []const u8) bool {
    for (list) |n| if (std.ascii.eqlIgnoreCase(n, name)) return true;
    return false;
}

/// SAS 9.4 dataset options that are DOCUMENTED but unimplemented here — the
/// "SAS Data Set Options" chapter of Language Reference: Concepts (the whereup= cite at printed
/// p.215 is one entry) minus the seven this file honours
/// (where/keep/drop/rename/firstobs/obs/in). The unknown-option arm uses it to
/// tell a real opensas gap ("is not supported") from a user typo
/// ("Unrecognized") — NOTE-typoarmgapwording, macro.zig's STORE/STROE split.
fn documentedDsoptGap(name: []const u8) bool {
    const words = [_][]const u8{
        "alter",   "bufno",      "bufsize",          "cntllev",   "compress", "dldmgaction",
        "encrypt", "encryptkey", "extendobscounter", "fileclose", "genmax",   "gennum",
        "idxname", "idxwhere",   "label",             "obsbuf",    "outrep",   "pw",
        "pwreq",   "read",       "repempty",          "replace",   "reuse",    "sortedby",
        "sortseq", "spill",      "tobsno",            "type",      "whereup",  "write",
    };
    for (words) |w| if (eqiTok(name, w)) return true;
    return false;
}

fn eqiTok(x: []const u8, y: []const u8) bool {
    return std.ascii.eqlIgnoreCase(x, y);
}

test "CSV round-trip: header, quoting, char/num missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("age", .num);
    try ds.appendRow(&.{ .{ .str = " A " }, .{ .num = 40 } }); // padded → quoted
    try ds.appendRow(&.{ .{ .str = "" }, Value.missing }); // both missings → empty fields

    // INTERNAL libname CSV: a missing numeric writes "." (BUG-csvregress) so the
    // real-SAS goldens and readCsv round-trip hold; PROC EXPORT writes empty.
    const text = try writeCsv(a, &ds);
    try std.testing.expectEqualStrings("name,age\n\" A \",40\n,.\n", text); // missing num → "."
    const exp = try writeCsvExport(a, &ds);
    try std.testing.expectEqualStrings("name,age\n\" A \",40\n,\n", exp); // EXPORT → empty (,,)

    // parse it back: `name` stays character, `age` is inferred numeric (BUG-csvnumtype)
    const back = try readCsv(a, text, "d2");
    try std.testing.expectEqual(@as(usize, 2), back.columns.items.len);
    try std.testing.expectEqualStrings("name", back.columns.items[0].name);
    try std.testing.expect(back.columns.items[0].type == .char); // "A"/"" → character
    try std.testing.expect(back.columns.items[1].type == .num); // 40/. → numeric
    try std.testing.expectEqual(@as(usize, 2), back.rowCount());
    try std.testing.expectEqualStrings(" A ", back.row(0)[0].str); // padding preserved
    try std.testing.expectEqual(@as(f64, 40), back.row(0)[1].num); // loaded as a number
    try std.testing.expectEqualStrings("", back.row(1)[0].str); // char missing empty
    try std.testing.expect(back.row(1)[1].isMissing()); // numeric missing (.)
}

test "BUG-csvzerocolphantom: a 0-variable set has NO CSV encoding — write refuses, read never fabricates VAR1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The documented shape (Macro Language Ref, SYSDATASTEPPHASE ex. 2, printed
    // p.246: "has 1 observations and 0 variables") — `data x; y=1; drop y; run;`.
    var ds = Dataset.init(a, "work.zed");
    try ds.appendRow(&.{});
    try std.testing.expectEqual(@as(usize, 1), ds.rowCount());
    try std.testing.expectEqual(@as(usize, 0), ds.columns.items.len);

    // WRITE half. Both surfaces refuse — the internal libname writer and PROC
    // EXPORT's — since the inability is the format's, not the caller's (D-001
    // scopes CALLER behaviour; this is neither caller's choice). Empty body, so
    // main.writeMember's `len > 0` guard writes no file at all; LOUD + D-009 gap.
    diag.resetGap();
    g_test_last_unsup = "";
    try std.testing.expectEqualStrings("", try writeCsv(a, &ds)); // was "\n\n"
    try std.testing.expect(diag.gapHit()); // → exit 2, never a silent rc=0
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_unsup, "0 variables") != null);

    diag.resetGap();
    g_test_last_unsup = "";
    try std.testing.expectEqualStrings("", try writeCsvExport(a, &ds)); // PROC EXPORT was SILENT at rc=0
    try std.testing.expect(diag.gapHit());

    // READ half, pinned SEPARATELY because a file written before this fix is
    // still on disk: the exact 2 bytes the old writer produced must not come
    // back as a phantom column. Old behaviour was 1 column `VAR1` + 0 rows —
    // observation LOST, variable FABRICATED, both silent.
    diag.resetGap();
    g_test_last_unsup = "";
    const back = try readCsv(a, "\n\n", "work.reload");
    try std.testing.expectEqual(@as(usize, 0), back.columns.items.len); // no phantom VAR1
    try std.testing.expectEqual(@as(usize, 0), back.rowCount());
    try std.testing.expect(diag.gapHit()); // and it is LOUD, not a quiet empty set
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_unsup, "NO columns") != null);
    diag.resetGap();

    // ROUND TRIP, the thing the ticket is actually about: the member does not
    // survive, and BOTH directions now say so loudly instead of disagreeing.
    // (1 obs/0 vars → nothing on disk → nothing back, rather than 0 obs/1 var.)

    // CONTROLS — the guard is narrow. A normal set is untouched...
    var ok = Dataset.init(a, "work.ok");
    _ = try ok.addColumn("x", .num);
    try ok.appendRow(&.{.{ .num = 1 }});
    diag.resetGap();
    try std.testing.expectEqualStrings("x\n1\n", try writeCsv(a, &ok));
    try std.testing.expect(!diag.gapHit());

    // ...a 0-ROW set with columns still writes its header and round-trips...
    var hdr = Dataset.init(a, "work.hdr");
    _ = try hdr.addColumn("x", .num);
    try std.testing.expectEqualStrings("x\n", try writeCsv(a, &hdr));
    const hback = try readCsv(a, "x\n", "work.hdr2");
    try std.testing.expectEqual(@as(usize, 1), hback.columns.items.len);
    try std.testing.expectEqual(@as(usize, 0), hback.rowCount());
    try std.testing.expect(!diag.gapHit());

    // ...and an UNNAMED-but-real column keeps PROC IMPORT's VAR-n naming: `,,`
    // declares three columns that genuinely exist, unlike a zero-length record.
    const unnamed = try readCsv(a, ",,\n1,2,3\n", "work.u");
    try std.testing.expectEqual(@as(usize, 3), unnamed.columns.items.len);
    try std.testing.expectEqualStrings("VAR1", unnamed.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), unnamed.rowCount());
    try std.testing.expect(!diag.gapHit());

    // GETNAMES=NO is unaffected: no header is read, so a leading blank line is
    // just skipped and the column count comes from the first data record.
    const nogn = try readDelimited(a, "\n1,2\n", "work.n", ',', false, 1, false);
    try std.testing.expectEqual(@as(usize, 2), nogn.columns.items.len);
    try std.testing.expectEqual(@as(usize, 1), nogn.rowCount());
    try std.testing.expect(!diag.gapHit());
}

test "writeSas7bdat → read preserves char type/length: '007' stays Char, not Num (E-sas7write-hookup)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The META-fidelity case: an all-digit CHAR value round-trips as char (CSV
    // persistence re-typed it Num). A declared LENGTH $3 sets the stored width.
    var ds = Dataset.init(a, "work.a");
    _ = try ds.addColumn("SITE", .char);
    ds.columns.items[0].len = 3;
    _ = try ds.addColumn("AMT", .num);
    try ds.appendRow(&.{ .{ .str = "007" }, .{ .num = 42.5 } });
    try ds.appendRow(&.{ .{ .str = "012" }, Value.missing });

    const back = try readSas7bdat(a, try writeSas7bdat(a, &ds), "work.b");
    try std.testing.expectEqual(@as(usize, 2), back.columns.items.len);
    try std.testing.expect(back.columns.items[0].type == .char); // NOT re-typed Num
    try std.testing.expect(back.columns.items[1].type == .num);
    try std.testing.expectEqualStrings("007", back.row(0)[0].str); // value + width intact
    try std.testing.expectEqual(@as(f64, 42.5), back.row(0)[1].num);
    try std.testing.expectEqualStrings("012", back.row(1)[0].str);
    try std.testing.expect(back.row(1)[1].isMissing());
}

test "readCsv infers numeric columns; text and zero-padded codes stay char (BUG-csvnumtype)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // id: all numeric → numeric (loads as f64, so it sorts/compares numerically);
    // code: zero-padded → char; name: text → char; a `.`/empty is missing.
    const ds = try readCsv(a, "id,code,name\n10,007,ann\n2,001,bob\n1,.,\n", "d");
    try std.testing.expectEqual(@as(usize, 3), ds.rowCount());
    try std.testing.expect(ds.columns.items[0].type == .num); // id
    try std.testing.expect(ds.columns.items[1].type == .char); // code (leading zeros)
    try std.testing.expect(ds.columns.items[2].type == .char); // name (text)

    try std.testing.expectEqual(@as(f64, 10), ds.row(0)[0].num);
    try std.testing.expectEqual(@as(f64, 1), ds.row(2)[0].num);
    try std.testing.expectEqualStrings("007", ds.row(0)[1].str); // zero-pad preserved
    try std.testing.expectEqualStrings(".", ds.row(2)[1].str); // `.` literal in a char column
    try std.testing.expectEqualStrings("", ds.row(2)[2].str); // empty char field

    // a numeric column with a `.` reads that cell as numeric missing
    const ds2 = try readCsv(a, "n\n5\n.\n7\n", "d2");
    try std.testing.expect(ds2.columns.items[0].type == .num);
    try std.testing.expectEqual(@as(f64, 5), ds2.row(0)[0].num);
    try std.testing.expect(ds2.row(1)[0].isMissing());
}

test "readDelimited: DBMS=DLM semicolon, GETNAMES, DATAROW, GETNAMES=NO (BUG-importdlm)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `;`-delimited with names on row 1: numeric age, zero-padded code stays char.
    const ds = try readDelimited(a, "name;age;code\nAnn;30;007\nBob;25;010\n", "d", ';', true, 2, true);
    try std.testing.expectEqual(@as(usize, 3), ds.columns.items.len);
    try std.testing.expectEqualStrings("name", ds.columns.items[0].name);
    try std.testing.expect(ds.columns.items[1].type == .num); // age
    try std.testing.expectEqual(@as(f64, 30), ds.row(0)[1].num);
    try std.testing.expectEqualStrings("007", ds.row(0)[2].str);

    // GETNAMES=NO → VAR1.. names, data from row 1 (datarow=0 → default).
    const ds2 = try readDelimited(a, "Ann;30\nBob;25\n", "d2", ';', false, 0, true);
    try std.testing.expectEqualStrings("VAR1", ds2.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 2), ds2.rowCount());
    try std.testing.expectEqualStrings("Ann", ds2.row(0)[0].str);

    // DATAROW=3 skips a comment line between the header and the data.
    const ds3 = try readDelimited(a, "a;b\nignore this\n1;2\n3;4\n", "d3", ';', true, 3, true);
    try std.testing.expectEqual(@as(usize, 2), ds3.rowCount());
    try std.testing.expectEqual(@as(f64, 1), ds3.row(0)[0].num);
}

test "readDelimited: quoted embedded newline stays ONE record; headers V7-normalized + deduped (BUG-importdelimread)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A DSD quoted free-text field spanning a physical line is ONE record —
    // columns to its right stay aligned (a torn record would split note's
    // second line into a bogus row and mistype/misalign everything right).
    const ds = try readDelimited(a, "subjid,aetext,age\n001,\"Rash on arm\nspreading to back\",34\n002,\"Nausea\",28\n", "d", ',', true, 2, true);
    try std.testing.expectEqual(@as(usize, 2), ds.rowCount()); // TWO records, not three
    try std.testing.expectEqualStrings("Rash on arm\nspreading to back", ds.row(0)[1].str);
    try std.testing.expect(ds.columns.items[2].type == .num); // age still numeric
    try std.testing.expectEqual(@as(f64, 34), ds.row(0)[2].num); // …and on the right row
    try std.testing.expectEqualStrings("Nausea", ds.row(1)[1].str);
    try std.testing.expectEqual(@as(f64, 28), ds.row(1)[2].num);

    // CRLF file: unquoted \r\n still ends the record; quoted \r\n is data.
    const ds_crlf = try readDelimited(a, "a,b\r\n\"x\r\ny\",1\r\nz,2\r\n", "dc", ',', true, 2, true);
    try std.testing.expectEqual(@as(usize, 2), ds_crlf.rowCount());
    try std.testing.expectEqualStrings("x\r\ny", ds_crlf.row(0)[0].str);
    try std.testing.expectEqual(@as(f64, 1), ds_crlf.row(0)[1].num);

    // Headers mangled per VALIDVARNAME=V7 and deduped — same as the XLSX path.
    const ds2 = try readDelimited(a, "First Name,Age (yrs),2nd,age,age\nAnn,30,x,1,2\n", "d2", ',', true, 2, true);
    try std.testing.expectEqualStrings("First_Name", ds2.columns.items[0].name);
    try std.testing.expectEqualStrings("Age__yrs_", ds2.columns.items[1].name);
    try std.testing.expectEqualStrings("_2nd", ds2.columns.items[2].name);
    try std.testing.expectEqualStrings("age", ds2.columns.items[3].name);
    try std.testing.expectEqualStrings("age0", ds2.columns.items[4].name);
}

test "readDelimited: EFI date/time detection (GAP-importtypes) — uniform column typed NUMERIC + format; mixed and DOC-SILENT stay char" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ISO dates → NUMERIC, YYMMDD10. attached, SAS-day values (2024-03-05 = 23440).
    const ds = try readDelimited(a, "id,dt\n1,2024-03-05\n2,2024-12-31\n", "d", ',', true, 2, true);
    try std.testing.expect(ds.columns.items[0].type == .num); // id: numeric as before
    try std.testing.expect(ds.columns.items[1].type == .num); // dt: detected date
    try std.testing.expectEqualStrings("YYMMDD10.", ds.columns.items[1].format.?);
    try std.testing.expectEqualStrings("YYMMDD10.", ds.columns.items[1].informat.?);
    try std.testing.expectEqual(@as(f64, 23440), ds.row(0)[1].num);
    try std.testing.expectEqual(@as(f64, 23741), ds.row(1)[1].num);

    // The other recognised families — DATE/MONYY/DATETIME/TIME (Procedures
    // Guide p. 1324/1326/1341 + the p. 1330 category rule). Width = widest value.
    const ds2 = try readDelimited(a, "d,m,dtm,tm\n05MAR2024,MAR2024,06JAN2016:10:04:26,10:30:00\n10MAY14,JAN2001,07FEB2017:23:59:59,9:05\n", "f", ',', true, 2, true);
    try std.testing.expectEqualStrings("DATE9.", ds2.columns.items[0].format.?);
    try std.testing.expectEqualStrings("MONYY7.", ds2.columns.items[1].format.?);
    try std.testing.expectEqualStrings("DATETIME18.", ds2.columns.items[2].format.?);
    try std.testing.expectEqualStrings("TIME8.", ds2.columns.items[3].format.?);
    try std.testing.expectEqual(@as(f64, 23436), ds2.row(0)[1].num); // MAR2024 → 1st of month
    try std.testing.expectEqual(@as(f64, 10 * 3600 + 30 * 60), ds2.row(0)[3].num);
    // missing values in a detected column stay missing, don't block detection
    const ds3 = try readDelimited(a, "dt\n2024-03-05\n\n.\n", "m", ',', true, 2, true);
    try std.testing.expectEqualStrings("YYMMDD10.", ds3.columns.items[0].format.?);
    try std.testing.expect(ds3.row(1)[0].isMissing());

    // MIXED column (some values date, some not) → character, text preserved.
    const mx = try readDelimited(a, "v\n2024-03-05\nnot a date\n", "mx", ',', true, 2, true);
    try std.testing.expect(mx.columns.items[0].type == .char);
    try std.testing.expect(mx.columns.items[0].format == null);
    try std.testing.expectEqualStrings("2024-03-05", mx.row(0)[0].str);
    // mixed date FAMILIES (ISO + DATE) — one informat must fit every value.
    const mx2 = try readDelimited(a, "v\n2024-03-05\n05MAR2024\n", "mx2", ',', true, 2, true);
    try std.testing.expect(mx2.columns.items[0].type == .char);
    // DOC-SILENT patterns stay character: ambiguous slash dates, ISO-T
    // datetimes, separator MONYY, a bare hour, a bogus time.
    const silent = try readDelimited(a, "a,b,c,d,e\n03/05/2024,2024-03-05T10:04:26,MAR-2024,10,10:99\n", "s", ',', true, 2, true);
    try std.testing.expect(silent.columns.items[0].type == .char); // mm/dd vs dd/mm
    try std.testing.expect(silent.columns.items[1].type == .char); // ISO-8601 T
    try std.testing.expect(silent.columns.items[2].type == .char); // MON-YYYY
    try std.testing.expect(silent.columns.items[3].type == .num); // 10 is a NUMBER
    try std.testing.expect(silent.columns.items[4].type == .char); // 10:99 invalid
    // packed 8-digit `20240305` is a plain number to EFI, never a date.
    const packed_ = try readDelimited(a, "n\n20240305\n20241031\n", "p", ',', true, 2, true);
    try std.testing.expect(packed_.columns.items[0].type == .num);
    try std.testing.expect(packed_.columns.items[0].format == null);
    try std.testing.expectEqual(@as(f64, 20240305), packed_.row(0)[0].num);

    // detect_dates=false (the .csv libname engine): dates stay char, unchanged.
    const off = try readDelimited(a, "id,dt\n1,2024-03-05\n", "o", ',', true, 2, false);
    try std.testing.expect(off.columns.items[1].type == .char);
    try std.testing.expectEqualStrings("2024-03-05", off.row(0)[1].str);
}

test "applyDatasetOptions: keep restricts columns; rename relabels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "out");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    var diags = diag.Diagnostics.init(a);

    // keep = x  → only column x survives
    const keep_toks = [_]lex.Token{ .{ .tag = .name, .text = "keep" }, .{ .tag = .eq }, .{ .tag = .name, .text = "x" } };
    try applyDatasetOptions(a, &ds, &keep_toks, &diags, false);
    try std.testing.expectEqual(@as(usize, 1), ds.columns.items.len);
    try std.testing.expectEqualStrings("x", ds.columns.items[0].name);
    try std.testing.expectEqual(@as(f64, 1), ds.row(0)[0].num); // row rebuilt to match

    // rename = ( x = z )
    const rn_toks = [_]lex.Token{
        .{ .tag = .name, .text = "rename" }, .{ .tag = .eq },  .{ .tag = .lparen },
        .{ .tag = .name, .text = "x" },      .{ .tag = .eq },  .{ .tag = .name, .text = "z" },
        .{ .tag = .rparen },
    };
    try applyDatasetOptions(a, &ds, &rn_toks, &diags, false);
    try std.testing.expectEqualStrings("z", ds.columns.items[0].name);
    try std.testing.expect(ds.indexOf("z") != null and ds.indexOf("x") == null);
}

test "applyDatasetOptions: where= filters rows on read (BUG-setwhere)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "src");
    _ = try ds.addColumn("v", .num);
    for ([_]f64{ 1, 5, 2, 9 }) |x| try ds.appendRow(&.{.{ .num = x }});

    // where = ( v > 3 )  → only 5 and 9 survive
    const toks = [_]lex.Token{
        .{ .tag = .name, .text = "where" }, .{ .tag = .eq },     .{ .tag = .lparen },
        .{ .tag = .name, .text = "v" },     .{ .tag = .gt },     .{ .tag = .number, .text = "3" },
        .{ .tag = .rparen },
    };
    var diags = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &ds, &toks, &diags, false);

    try std.testing.expectEqual(@as(usize, 2), ds.rowCount());
    try std.testing.expectEqual(@as(f64, 5), ds.row(0)[0].num);
    try std.testing.expectEqual(@as(f64, 9), ds.row(1)[0].num);
}

test "applyDatasetOptions: firstobs=/obs= slice the read range (G-dsopt)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "src");
    _ = try ds.addColumn("v", .num);
    for ([_]f64{ 10, 20, 30, 40 }) |x| try ds.appendRow(&.{.{ .num = x }});

    // firstobs=2 obs=3 → obs 2 and 3 (20, 30) on an INPUT read
    const toks = [_]lex.Token{
        .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .number, .text = "2" },
        .{ .tag = .name, .text = "obs" },      .{ .tag = .eq }, .{ .tag = .number, .text = "3" },
    };
    var diags = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &ds, &toks, &diags, true);

    try std.testing.expectEqual(@as(usize, 2), ds.rowCount());
    try std.testing.expectEqual(@as(f64, 20), ds.row(0)[0].num);
    try std.testing.expectEqual(@as(f64, 30), ds.row(1)[0].num);

    // Same options on an OUTPUT dataset are ignored: all rows written
    // (BUG-outdsobsslice — SAS treats obs=/firstobs= as input-only).
    var out_ds = Dataset.init(a, "out");
    _ = try out_ds.addColumn("v", .num);
    for ([_]f64{ 10, 20, 30, 40 }) |x| try out_ds.appendRow(&.{.{ .num = x }});
    try applyDatasetOptions(a, &out_ds, &toks, &diags, false);
    try std.testing.expectEqual(@as(usize, 4), out_ds.rowCount());
}

test "applyDatasetOptionsObs: surviving rows carry their physical source obs number (BUG-printobsnum)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "src");
    _ = try ds.addColumn("v", .num);
    for ([_]f64{ 10, 21, 30, 41, 50 }) |x| try ds.appendRow(&.{.{ .num = x }});

    // Chain like procInput: firstobs=2 slice, then a where=(…) filter. The
    // slice starts numbering at 2; the WHERE must sub-select those numbers,
    // not renumber 1..n (PROC PRINT's Obs column).
    const fo_toks = [_]lex.Token{
        .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .number, .text = "2" },
    };
    const w_toks = [_]lex.Token{
        .{ .tag = .name, .text = "where" }, .{ .tag = .eq },     .{ .tag = .lparen },
        .{ .tag = .name, .text = "v" },     .{ .tag = .gt },     .{ .tag = .number, .text = "25" },
        .{ .tag = .rparen },
    };
    var diags = diag.Diagnostics.init(a);
    var srcobs: ?[]const usize = null;
    try applyDatasetOptionsObs(a, &ds, &fo_toks, &diags, true, false, &srcobs, &.{});
    try std.testing.expectEqualSlices(usize, &.{ 2, 3, 4, 5 }, srcobs.?);
    try applyDatasetOptionsObs(a, &ds, &w_toks, &diags, false, false, &srcobs, &.{});
    try std.testing.expectEqual(@as(usize, 3), ds.rowCount()); // 30, 41, 50 survive
    try std.testing.expectEqualSlices(usize, &.{ 3, 4, 5 }, srcobs.?); // source numbers, not 1..3

    // Untracked wrapper still compiles/runs and leaves no list behind.
    var ds2 = Dataset.init(a, "src2");
    _ = try ds2.addColumn("v", .num);
    try ds2.appendRow(&.{.{ .num = 1 }});
    try applyDatasetOptions(a, &ds2, &w_toks, &diags, false);
    try std.testing.expectEqual(@as(usize, 0), ds2.rowCount());
}

test "GH#22 ISS-dkrocondwarn: keep=/drop=/rename= of a never-referenced var WARNs and continues (option form)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // A source (or output) dataset with just SUBJID; ECTRT is a typo for ECTT.
    var ds = Dataset.init(a, "src");
    _ = try ds.addColumn("subjid", .num);
    try ds.appendRow(&.{.{ .num = 1 }});
    var diags = diag.Diagnostics.init(a);

    // keep = subjid ectrt  → ECTRT is on no column. On an OUTPUT dataset (input=
    // false) DKROCOND=WARN: WARN and keep only the vars that DO exist (SUBJID);
    // the step still runs. (Input datasets are fatal — DKRICOND=ERROR, GH#71.)
    const toks = [_]lex.Token{
        .{ .tag = .name, .text = "keep" },   .{ .tag = .eq },
        .{ .tag = .name, .text = "subjid" }, .{ .tag = .name, .text = "ectrt" },
    };
    try applyDatasetOptions(a, &ds, &toks, &diags, false);

    var hit = false;
    for (diags.list.items) |d| {
        if (d.severity == .warning and
            std.mem.indexOf(u8, d.message, "ECTRT") != null and
            std.mem.indexOf(u8, d.message, "never been referenced") != null) hit = true;
    }
    try std.testing.expect(hit); // WARNING emitted (visible), not silent
    try std.testing.expect(!diags.hasStepErrors()); // no ERROR / abort
    // Output still produced: the existing var SUBJID survives keep=, ECTRT ignored.
    try std.testing.expect(ds.indexOf("subjid") != null);
    try std.testing.expect(ds.columns.items.len == 1);
}

test "applyDatasetOptions: rename onto an existing name is refused, not duplicated (BUG-renamedup)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "out");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });

    // rename = ( a = b )  — b already exists, so the rename is skipped (no dup)
    const rn_toks = [_]lex.Token{
        .{ .tag = .name, .text = "rename" }, .{ .tag = .eq }, .{ .tag = .lparen },
        .{ .tag = .name, .text = "a" },      .{ .tag = .eq }, .{ .tag = .name, .text = "b" },
        .{ .tag = .rparen },
    };
    var diags = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &ds, &rn_toks, &diags, false);

    try std.testing.expectEqual(@as(usize, 2), ds.columns.items.len); // still two columns
    try std.testing.expectEqualStrings("a", ds.columns.items[0].name); // a kept its name
    try std.testing.expectEqualStrings("b", ds.columns.items[1].name);
    try std.testing.expectEqual(@as(f64, 1), ds.row(0)[ds.indexOf("a").?].num); // a's value survives
}

/// BUG-wheredsoptswallow helper: one .err diagnostic naming `opt`, in the
/// wording class `kind` — "is not supported" for a documented gap,
/// "Unrecognized" for a typo (NOTE-typoarmgapwording).
fn expectOptErr(diags: *const diag.Diagnostics, opt: []const u8, kind: []const u8) !void {
    var hit = false;
    for (diags.list.items) |d| {
        if (d.severity == .err and std.mem.indexOf(u8, d.message, kind) != null and
            std.mem.indexOf(u8, d.message, opt) != null) hit = true;
    }
    try std.testing.expect(hit);
}

test "BUG-wheredsoptswallow: unknown dataset option fails LOUD naming it; supported set still accepted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ── negative: misspelled where= (a filter that silently DISABLED itself)
    var ds = Dataset.init(a, "src");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3 }) |x| try ds.appendRow(&.{.{ .num = x }});
    const typo = [_]lex.Token{
        .{ .tag = .name, .text = "wehre" }, .{ .tag = .eq },     .{ .tag = .lparen },
        .{ .tag = .name, .text = "x" },    .{ .tag = .gt },     .{ .tag = .number, .text = "2" },
        .{ .tag = .rparen },
    };
    var diags = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &ds, &typo, &diags, true);
    try expectOptErr(&diags, "wehre", "Unrecognized"); // a typo is the user's own SAS (rc 1), never gap vocabulary
    try std.testing.expectEqual(@as(usize, 0), ds.rowCount()); // INPUT: 0 rows, never the unfiltered superset

    // ── negative: whereup= is REAL SAS (Language Reference: Concepts p.215) but unimplemented — loud, not inert
    var ds2 = Dataset.init(a, "src");
    _ = try ds2.addColumn("x", .num);
    try ds2.appendRow(&.{.{ .num = 1 }});
    const whereup = [_]lex.Token{
        .{ .tag = .name, .text = "whereup" }, .{ .tag = .eq }, .{ .tag = .name, .text = "yes" },
    };
    var diags2 = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &ds2, &whereup, &diags2, true);
    try expectOptErr(&diags2, "whereup", "is not supported"); // documented but unimplemented: a gap, gap wording

    // ── positive control: every supported option in ONE stream, including a
    // `name =` INSIDE the where parens (must NOT trip the unknown-option arm)
    var ds3 = Dataset.init(a, "src");
    _ = try ds3.addColumn("x", .num);
    _ = try ds3.addColumn("y", .num);
    for ([_]f64{ 1, 2, 3, 4, 5 }) |x| try ds3.appendRow(&.{ .{ .num = x }, .{ .num = x * 10 } });
    const good = [_]lex.Token{
        .{ .tag = .name, .text = "where" },    .{ .tag = .eq },                .{ .tag = .lparen },
        .{ .tag = .name, .text = "x" },       .{ .tag = .eq },                .{ .tag = .number, .text = "2" },
        .{ .tag = .rparen }, // where=(x=2)
        .{ .tag = .name, .text = "keep" },     .{ .tag = .eq }, .{ .tag = .name, .text = "x" },
        .{ .tag = .name, .text = "rename" },   .{ .tag = .eq }, .{ .tag = .lparen },
        .{ .tag = .name, .text = "x" },       .{ .tag = .eq }, .{ .tag = .name, .text = "z" },
        .{ .tag = .rparen },
        .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .number, .text = "1" },
        .{ .tag = .name, .text = "obs" },      .{ .tag = .eq }, .{ .tag = .number, .text = "5" },
        .{ .tag = .name, .text = "in" },       .{ .tag = .eq }, .{ .tag = .name, .text = "srcflag" },
    };
    var diags3 = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &ds3, &good, &diags3, true);
    try std.testing.expect(!diags3.hasErrors()); // NOTHING in the supported set errors
    try std.testing.expectEqual(@as(usize, 1), ds3.rowCount()); // where=(x=2) kept row 2
    try std.testing.expectEqual(@as(usize, 1), ds3.columns.items.len); // keep=x
    try std.testing.expectEqualStrings("z", ds3.columns.items[0].name); // rename=(x=z)
    try std.testing.expectEqual(@as(f64, 2), ds3.row(0)[0].num);
}

/// BUG-dsobsvaluenovalidate helper: one .err diagnostic naming `needle`.
fn expectObsValErr(diags: *const diag.Diagnostics, needle: []const u8) !void {
    var hit = false;
    for (diags.list.items) |d| {
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "Invalid value") != null and
            std.mem.indexOf(u8, d.message, needle) != null) hit = true;
    }
    try std.testing.expect(hit);
}

test "BUG-dsobsvaluenovalidate: garbage obs=/firstobs= VALUES fail LOUD naming option+value; documented values honoured" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const mk = struct {
        fn f(al: std.mem.Allocator) !Dataset {
            var d = Dataset.init(al, "src");
            _ = try d.addColumn("x", .num);
            for ([_]f64{ 1, 2, 3, 4, 5 }) |x| try d.appendRow(&.{.{ .num = x }});
            return d;
        }
    }.f;

    // ── negatives (INPUT): each silently read ALL FIVE rows before this fix
    const bad = [_]struct { toks: []const lex.Token, opt: []const u8, val: []const u8 }{
        .{ .toks = &.{ .{ .tag = .name, .text = "obs" }, .{ .tag = .eq }, .{ .tag = .name, .text = "abc" } }, .opt = "OBS", .val = "abc" },
        .{ .toks = &.{ .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .name, .text = "abc" } }, .opt = "FIRSTOBS", .val = "abc" },
        .{ .toks = &.{ .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .number, .text = "0" } }, .opt = "FIRSTOBS", .val = "0" },
        .{ .toks = &.{ .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .minus }, .{ .tag = .number, .text = "1" } }, .opt = "FIRSTOBS", .val = "-1" },
    };
    for (bad) |c| {
        var d = try mk(a);
        var diags = diag.Diagnostics.init(a);
        try applyDatasetOptions(a, &d, c.toks, &diags, true);
        try expectObsValErr(&diags, c.opt);
        try expectObsValErr(&diags, c.val);
        try std.testing.expectEqual(@as(usize, 0), d.rowCount()); // 0 rows, never the superset
    }

    // ── honoured values: the K suffix, MAX, MIN
    var d1 = try mk(a);
    const k_suffix = [_]lex.Token{ .{ .tag = .name, .text = "obs" }, .{ .tag = .eq }, .{ .tag = .number, .text = "2" }, .{ .tag = .name, .text = "k" } };
    var g1 = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &d1, &k_suffix, &g1, true);
    try std.testing.expect(!g1.hasErrors());
    try std.testing.expectEqual(@as(usize, 5), d1.rowCount()); // obs=2k = 2048 ≥ 5, NOT 2

    var d2 = try mk(a);
    const fo_max = [_]lex.Token{ .{ .tag = .name, .text = "firstobs" }, .{ .tag = .eq }, .{ .tag = .name, .text = "max" } };
    var g2 = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &d2, &fo_max, &g2, true);
    try std.testing.expect(!g2.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), d2.rowCount()); // FIRSTOBS=MAX starts at the LAST obs
    try std.testing.expectEqual(@as(f64, 5), d2.row(0)[0].num);

    var d3 = try mk(a);
    const obs_min = [_]lex.Token{ .{ .tag = .name, .text = "obs" }, .{ .tag = .eq }, .{ .tag = .name, .text = "min" } };
    var g3 = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &d3, &obs_min, &g3, true);
    try std.testing.expectEqual(@as(usize, 1), d3.rowCount()); // OBS=MIN = 1

    // ── OUTPUT: the range is ignored wholesale (settled, BUG-outdsobsslice) —
    //    even a garbage value is consumed without a diagnostic there
    var d4 = try mk(a);
    var g4 = diag.Diagnostics.init(a);
    try applyDatasetOptions(a, &d4, &.{ .{ .tag = .name, .text = "obs" }, .{ .tag = .eq }, .{ .tag = .name, .text = "abc" } }, &g4, false);
    try std.testing.expect(!g4.hasErrors());
    try std.testing.expectEqual(@as(usize, 5), d4.rowCount());
}

test "list input with :informat modifiers (comma, date)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // `input n :comma8. d :date9.;` — the COLON (list_mod) form: tokenize, then
    // apply (BUG-inputfmtnamedtoken made the non-colon form a true w-column read,
    // so list_mod is what makes this test's name true).
    const items = [_]ast.InputItem{
        .{ .name = "n", .type = .num, .informat = "comma8.", .list_mod = true },
        .{ .name = "d", .type = .num, .informat = "date9.", .list_mod = true },
    };
    _ = try readList(&pdv, &items, &[_][]const u8{"1,234 01JAN1960"}, 0, null, false, false, null);
    try std.testing.expectEqual(@as(f64, 1234), pdv.get("n").?.num); // commas stripped
    try std.testing.expectEqual(@as(f64, 0), pdv.get("d").?.num); // 1960-01-01 = SAS day 0

    // a couple more date points to exercise daysFromCivil
    const d2 = [_]ast.InputItem{.{ .name = "x", .type = .num, .informat = "date9." }};
    _ = try readList(&pdv, &d2, &[_][]const u8{"01JAN2000"}, 0, null, false, false, null);
    try std.testing.expectEqual(@as(f64, 14610), pdv.get("x").?.num);
}

test "BUG-informatnotfoundcontinues: an unknown informat in INPUT halts the read (captured ERROR), no substituted data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pdv = Pdv.init(a);
    var diags = diag.Diagnostics.init(a);
    pdv.diags = &diags;
    const items = [_]ast.InputItem{.{ .name = "x", .type = .num, .informat = "nosuchfmt5." }};
    try std.testing.expectError(error.ExecError, readList(&pdv, &items, &[_][]const u8{"12345"}, 0, null, false, false, null));
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "The informat nosuchfmt was not found or could not be loaded.") != null);
    try std.testing.expect(pdv.get("x") == null); // the field was never read

    // char twin: an unknown $-informat halts the same way
    var pdv2 = Pdv.init(a);
    var diags2 = diag.Diagnostics.init(a);
    pdv2.diags = &diags2;
    const citems = [_]ast.InputItem{.{ .name = "c", .type = .char, .informat = "$zzz5." }};
    try std.testing.expectError(error.ExecError, readList(&pdv2, &citems, &[_][]const u8{"abcde"}, 0, null, false, false, null));
    try std.testing.expect(std.mem.indexOf(u8, try diags2.render(), "The informat zzz was not found") != null);

    // controls: a column-range `@s-e` item and a known informat pass the check
    var pdv3 = Pdv.init(a);
    var diags3 = diag.Diagnostics.init(a);
    pdv3.diags = &diags3;
    const oitems = [_]ast.InputItem{
        .{ .name = "r", .type = .num, .informat = "@1-3" },
        .{ .name = "k", .type = .num, .informat = "comma5." },
    };
    _ = try readList(&pdv3, &oitems, &[_][]const u8{"1234,567"}, 0, null, false, false, null);
    try std.testing.expect(!diags3.hasErrors());
    try std.testing.expectEqual(@as(f64, 123), pdv3.get("r").?.num);
    try std.testing.expectEqual(@as(f64, 4567), pdv3.get("k").?.num);
}

test "NOTE-inputinvalidnote: invalid numeric INPUT notes with real record/column and sets _ERROR_; ?/?? suppress" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pdv = Pdv.init(a);
    var diags = diag.Diagnostics.init(a);
    pdv.diags = &diags;
    const items = [_]ast.InputItem{
        .{ .name = "x", .type = .num },
        .{ .name = "y", .type = .num },
    };
    _ = try readList(&pdv, &items, &[_][]const u8{"J23 5"}, 0, null, false, false, null);
    try std.testing.expect(pdv.get("x").?.isMissing()); // p.518 action 1: value → missing
    try std.testing.expectEqual(@as(f64, 5), pdv.get("y").?.num);
    try std.testing.expectEqual(@as(f64, 1), pdv.get("_error_").?.num); // action 3: _ERROR_=1
    // actions 2+4: the invalid-data NOTE with the REAL record line + column
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "Invalid numeric data, 'J23', at line 1 column 1.") != null);

    // `??` suppresses BOTH the note and _ERROR_; `?` suppresses the note only
    var pdv2 = Pdv.init(a);
    var d2 = diag.Diagnostics.init(a);
    pdv2.diags = &d2;
    const qq = [_]ast.InputItem{.{ .name = "x", .type = .num, .suppress = 2 }};
    _ = try readList(&pdv2, &qq, &[_][]const u8{"J23"}, 0, null, false, false, null);
    try std.testing.expect(std.mem.indexOf(u8, try d2.render(), "Invalid numeric data") == null);
    try std.testing.expect(pdv2.get("_error_") == null); // never raised
    var pdv3 = Pdv.init(a);
    var d3 = diag.Diagnostics.init(a);
    pdv3.diags = &d3;
    const q = [_]ast.InputItem{.{ .name = "x", .type = .num, .suppress = 1 }};
    _ = try readList(&pdv3, &q, &[_][]const u8{"J23"}, 0, null, false, false, null);
    try std.testing.expect(std.mem.indexOf(u8, try d3.render(), "Invalid numeric data") == null);
    try std.testing.expectEqual(@as(f64, 1), pdv3.get("_error_").?.num);

    // a blank field and a coded-missing token stay silent (legitimate missings)
    var pdv4 = Pdv.init(a);
    var d4 = diag.Diagnostics.init(a);
    pdv4.diags = &d4;
    const plain = [_]ast.InputItem{.{ .name = "x", .type = .num }};
    _ = try readList(&pdv4, &plain, &[_][]const u8{""}, 0, null, false, false, null);
    _ = try readList(&pdv4, &plain, &[_][]const u8{"."}, 0, null, false, false, null);
    try std.testing.expect(std.mem.indexOf(u8, try d4.render(), "Invalid") == null);
    try std.testing.expect(pdv4.get("_error_") == null);
}

test "GAP-inputarrayelem: input v{i} resolves the subscript per read; out-of-range is a loud ERROR + _ERROR_" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pdv = Pdv.init(a);
    var diags = diag.Diagnostics.init(a);
    pdv.diags = &diags;
    _ = try pdv.define("i", .num);
    try pdv.set("i", .{ .num = 2 });
    const ixe: *ast.Expr = try a.create(ast.Expr);
    ixe.* = .{ .variable = "i" };
    const items = [_]ast.InputItem{.{ .name = "", .type = .num, .arr_index = ixe, .arr_elements = &.{ "v1", "v2", "v3" }, .arr_name = "v" }};
    _ = try readList(&pdv, &items, &[_][]const u8{"99"}, 0, null, false, false, null);
    try std.testing.expectEqual(@as(f64, 99), pdv.get("v2").?.num); // i=2 → v2
    try std.testing.expect(pdv.get("v") == null); // the array's own name never becomes a column
    // a moving index re-resolves on the next read (the DO-loop shape)
    try pdv.set("i", .{ .num = 1 });
    _ = try readList(&pdv, &items, &[_][]const u8{"77"}, 0, null, false, false, null);
    try std.testing.expectEqual(@as(f64, 77), pdv.get("v1").?.num);
    // out-of-range → loud ExecError, _ERROR_=1, message naming the array
    try pdv.set("i", .{ .num = 7 });
    try std.testing.expectError(error.ExecError, readList(&pdv, &items, &[_][]const u8{"1"}, 0, null, false, false, null));
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "Array subscript 7 out of range for v in INPUT.") != null);
    try std.testing.expectEqual(@as(f64, 1), pdv.get("_error_").?.num);
}

test "INPUT statement date/time informats read to SAS day/seconds (BUG-inputdatestmt)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // `input a mmddyy10. b yymmdd10. c ddmmyy10. t time8.;` — all previously
    // dropped to missing; 2024-12-25 is SAS day 23735, 13:30:00 is 48600s.
    const items = [_]ast.InputItem{
        .{ .name = "a", .type = .num, .informat = "mmddyy10." },
        .{ .name = "b", .type = .num, .informat = "yymmdd10." },
        .{ .name = "c", .type = .num, .informat = "ddmmyy10." },
        .{ .name = "t", .type = .num, .informat = "time8." },
    };
    _ = try readList(&pdv, &items, &[_][]const u8{"12/25/2024 2024-12-25 25/12/2024 13:30:00"}, 0, null, false, false, null);
    try std.testing.expectEqual(@as(f64, 23735), pdv.get("a").?.num); // mm/dd/yyyy
    try std.testing.expectEqual(@as(f64, 23735), pdv.get("b").?.num); // yyyy-mm-dd
    try std.testing.expectEqual(@as(f64, 23735), pdv.get("c").?.num); // dd/mm/yyyy
    try std.testing.expectEqual(@as(f64, 48600), pdv.get("t").?.num); // 13*3600+30*60

    // packed forms + a 2-digit year (SAS 9.4 YEARCUTOFF=1926: 24 → 2024)
    const items2 = [_]ast.InputItem{
        .{ .name = "p", .type = .num, .informat = "yymmdd8." }, // 20241225 packed
        .{ .name = "q", .type = .num, .informat = "mmddyy6." }, // 122524 → 12/25/2024
    };
    _ = try readList(&pdv, &items2, &[_][]const u8{"20241225 122524"}, 0, null, false, false, null);
    try std.testing.expectEqual(@as(f64, 23735), pdv.get("p").?.num);
    // 12/25/2024 (YEARCUTOFF 1926: 24 is in [1926,2025]'s wrap → 2024)
    try std.testing.expectEqual(@as(f64, 23735), pdv.get("q").?.num);
}

test "list input from datalines into the PDV" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // `input name $ age height;`
    const items = [_]ast.InputItem{
        .{ .name = "name", .type = .char },
        .{ .name = "age", .type = .num },
        .{ .name = "height", .type = .num },
    };
    _ = try readList(&pdv, &items, &[_][]const u8{"  Ann   30   5.5 "}, 0, null, false, false, null);

    try std.testing.expectEqualStrings("Ann", pdv.get("name").?.str);
    try std.testing.expectEqual(@as(f64, 30), pdv.get("age").?.num);
    try std.testing.expectEqual(@as(f64, 5.5), pdv.get("height").?.num);

    // too-few fields AND no more lines → trailing vars missing
    _ = try readList(&pdv, &items, &[_][]const u8{"Bo ."}, 0, null, false, false, null);
    try std.testing.expectEqualStrings("Bo", pdv.get("name").?.str);
    try std.testing.expect(pdv.get("age").?.isMissing());
    try std.testing.expect(pdv.get("height").?.isMissing());
}

test "delimited (DLM/DSD) infile input (G-infile)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    const items = [_]ast.InputItem{
        .{ .name = "a", .type = .char },
        .{ .name = "b", .type = .char },
        .{ .name = "c", .type = .num },
    };
    // DLM="," — one line, three comma fields
    _ = try readList(&pdv, &items, &[_][]const u8{"Ann,Smith,30"}, 0, ",", false, false, null);
    try std.testing.expectEqualStrings("Ann", pdv.get("a").?.str);
    try std.testing.expectEqualStrings("Smith", pdv.get("b").?.str);
    try std.testing.expectEqual(@as(f64, 30), pdv.get("c").?.num);

    // BUG-dlmmultichar: DLM="|;" is a SET — EACH byte is a delimiter. The record
    // splits on '|' AND ';', not just the first char.
    _ = try readList(&pdv, &items, &[_][]const u8{"Ann|Smith;30"}, 0, "|;", false, false, null);
    try std.testing.expectEqualStrings("Ann", pdv.get("a").?.str);
    try std.testing.expectEqualStrings("Smith", pdv.get("b").?.str);
    try std.testing.expectEqual(@as(f64, 30), pdv.get("c").?.num);

    // DSD — a quoted field keeps its comma; consecutive delimiters → missing.
    // `a` is an undeclared list-input char var → SAS default length 8, so the
    // 9-char "hi, there" truncates to "hi, ther" (BUG-inputlistlen; was asserting
    // the un-truncated bug value).
    _ = try readList(&pdv, &items, &[_][]const u8{"\"hi, there\",,7"}, 0, ",", true, false, null);
    try std.testing.expectEqualStrings("hi, ther", pdv.get("a").?.str);
    try std.testing.expectEqualStrings("", pdv.get("b").?.str); // empty field
    try std.testing.expectEqual(@as(f64, 7), pdv.get("c").?.num);
}

test "column pointers + implied-decimal informats (G-input-full)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    // input @1 name $5. @7 age 3. +1 score 5.2;  over "Alice 042 12345"
    const items = [_]ast.InputItem{
        .{ .name = "", .type = .num, .informat = "@1" },
        .{ .name = "name", .type = .char, .informat = "$5." },
        .{ .name = "", .type = .num, .informat = "@7" },
        .{ .name = "age", .type = .num, .informat = "3." },
        .{ .name = "", .type = .num, .informat = "+1" },
        .{ .name = "score", .type = .num, .informat = "5.2" },
    };
    _ = try readList(&pdv, &items, &[_][]const u8{"Alice 042 12345"}, 0, null, false, false, null);
    try std.testing.expectEqualStrings("Alice", pdv.get("name").?.str);
    try std.testing.expectEqual(@as(f64, 42), pdv.get("age").?.num);
    try std.testing.expectEqual(@as(f64, 123.45), pdv.get("score").?.num); // 5.2 implied decimals
}

test "GAP-atexpression: @(expr) clamps zero/negative to column 1 (p.168); a character result errors loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = diag.Diagnostics.init(arena.allocator());
    var pdv = Pdv.init(arena.allocator());
    pdv.diags = &diags;
    const zero: ast.Expr = .{ .num = 0 };
    const neg: ast.Expr = .{ .num = -4 };
    const items = [_]ast.InputItem{
        .{ .name = "", .type = .num, .col_expr = &zero },
        .{ .name = "a", .type = .char, .informat = "$2." },
        .{ .name = "", .type = .num, .col_expr = &neg },
        .{ .name = "b", .type = .char, .informat = "$2." },
    };
    _ = try readList(&pdv, &items, &[_][]const u8{"wxyz"}, 0, null, false, false, null);
    try std.testing.expectEqualStrings("wx", pdv.get("a").?.str); // @(0) → column 1
    try std.testing.expectEqualStrings("wx", pdv.get("b").?.str); // @(-4) → column 1
    // A CHARACTER result is SAS's other parenthesised form (the string search) —
    // unimplemented → loud ERROR via the captured reporter (D-002/D-003).
    const s: ast.Expr = .{ .str = "wx" };
    const citems = [_]ast.InputItem{
        .{ .name = "", .type = .num, .col_expr = &s },
        .{ .name = "c", .type = .char, .informat = "$2." },
    };
    try std.testing.expectError(error.ExecError, readList(&pdv, &citems, &[_][]const u8{"wxyz"}, 0, null, false, false, null));
    try std.testing.expect(std.mem.indexOf(u8, diags.list.items[diags.list.items.len - 1].message, "@(character-expression)") != null);
}

test "BUG-missovertruncover-partial: MISSOVER blanks a mid-field-truncated read; TRUNCOVER keeps it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    const items = [_]ast.InputItem{
        .{ .name = "", .type = .num, .informat = "@1" },
        .{ .name = "id", .type = .num, .informat = "2." },
        .{ .name = "name", .type = .char, .informat = "$8." }, // record ends at col 7 — mid-field
    };
    const lines = [_][]const u8{"42ALICE"}; // 7 cols; $8. wants 8 → partial

    _ = try readList(&pdv, &items, &lines, 0, null, false, true, null); // MISSOVER
    try std.testing.expectEqual(@as(f64, 42), pdv.get("id").?.num); // full field untouched
    try std.testing.expectEqualStrings("", pdv.get("name").?.str); // partial → missing

    var pdv2 = Pdv.init(arena.allocator());
    _ = try readList(&pdv2, &items, &lines, 0, null, false, false, null); // TRUNCOVER
    try std.testing.expectEqualStrings("ALICE", pdv2.get("name").?.str); // partial kept
}

test "@@ hold: readList resumes from the byte cursor across records (G-atat)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    const items = [_]ast.InputItem{
        .{ .name = "x", .type = .num },
        .{ .name = "", .type = .num, .informat = "@@" }, // hold sentinel
    };
    const lines = [_][]const u8{"10 20 30"};
    var pos: usize = 0;
    for ([_]f64{ 10, 20, 30 }) |want| {
        _ = try readList(&pdv, &items, &lines, 0, null, false, false, &pos);
        try std.testing.expectEqual(want, pdv.get("x").?.num);
    }
    try std.testing.expect(pos >= lines[0].len); // line consumed → driver steps on
}

test "list input spills onto the next line when a record is short (BUG-inputcrossline)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    const items = [_]ast.InputItem{
        .{ .name = "a", .type = .num },
        .{ .name = "b", .type = .num },
        .{ .name = "c", .type = .num },
    };
    // `input a b c;` over "1 2" / "3" / "4 5 6": obs 1 flows across lines 0-1.
    const lines = [_][]const u8{ "1 2", "3", "4 5 6" };

    const last = (try readList(&pdv, &items, &lines, 0, null, false, false, null)).hi;
    try std.testing.expectEqual(@as(usize, 1), last); // read through line 1
    try std.testing.expectEqual(@as(f64, 1), pdv.get("a").?.num);
    try std.testing.expectEqual(@as(f64, 2), pdv.get("b").?.num);
    try std.testing.expectEqual(@as(f64, 3), pdv.get("c").?.num); // spilled from line 1

    const last2 = (try readList(&pdv, &items, &lines, last + 1, null, false, false, null)).hi;
    try std.testing.expectEqual(@as(usize, 2), last2);
    try std.testing.expectEqual(@as(f64, 4), pdv.get("a").?.num);
    try std.testing.expectEqual(@as(f64, 6), pdv.get("c").?.num);
}

test "flow-over NOTE is capped per input stream (PERF-flownoteperrecord)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pdv = Pdv.init(a);
    var diags = diag.Diagnostics.init(a);
    pdv.diags = &diags;

    // The budget is module-global (it must survive readList calls, like the
    // stream it caps); reset it so the counts below are test-order independent.
    flow_note_count = 0;
    flow_note_lines = null;
    flow_note_li = 0;

    const items = [_]ast.InputItem{
        .{ .name = "a", .type = .num },
        .{ .name = "b", .type = .num },
    };
    // One token per record: reading b flows to the next record EVERY obs —
    // 60 records = 30 obs = 30 flow events on one stream, 10 past the cap.
    const lines = [_][]const u8{"1"} ** 60;
    var start: usize = 0;
    var obs: usize = 0;
    while (start + 1 < lines.len) {
        start = (try readList(&pdv, &items, &lines, start, null, false, false, null)).hi + 1;
        obs += 1;
    }
    try std.testing.expectEqual(@as(usize, 30), obs); // the flows still FLOW
    // 20 verbatim NOTEs + exactly one suppression notice — bounded, never silent.
    try std.testing.expectEqual(@as(usize, FLOW_NOTE_MAX + 1), diags.list.items.len);
    for (diags.list.items[0..FLOW_NOTE_MAX]) |d| {
        try std.testing.expectEqual(diag.Severity.note, d.severity);
        try std.testing.expectEqualStrings("SAS went to a new line when INPUT statement reached past the end of a line.", d.message);
    }
    try std.testing.expectEqualStrings("Further 'SAS went to a new line' notes are suppressed for this input.", diags.list.items[FLOW_NOTE_MAX].message);

    // A new stream (fresh buffer) re-arms the budget: one flow → one more NOTE.
    const lines2 = [_][]const u8{ "7", "8" };
    _ = try readList(&pdv, &items, &lines2, 0, null, false, false, null);
    try std.testing.expectEqual(@as(usize, FLOW_NOTE_MAX + 2), diags.list.items.len);
    try std.testing.expectEqualStrings("SAS went to a new line when INPUT statement reached past the end of a line.", diags.list.items[FLOW_NOTE_MAX + 1].message);
}

test "round trip: PDV → snapshot → Dataset → loadRow → fresh PDV" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var src = Pdv.init(a);
    try src.set("name", .{ .str = "Ann" });
    try src.set("age", .{ .num = 30 });

    var ds = Dataset.init(a, "work.people");
    try seedColumns(&ds, &src); // schema from the PDV, in order
    try snapshot(&ds, &src); // row 0

    src.reset(); // clobber the source — the dataset must be independent
    try snapshot(&ds, &src); // row 1: all missing

    try std.testing.expectEqual(@as(usize, 2), ds.rowCount());

    // `set` reads row 0 back into a fresh PDV
    var dst = Pdv.init(a);
    const slots = try columnSlots(&dst, &ds); // once per source, not per row
    try loadRow(&dst, &ds, 0, slots);
    try std.testing.expectEqualStrings("Ann", dst.get("name").?.str);
    try std.testing.expectEqual(@as(f64, 30), dst.get("age").?.num);

    try loadRow(&dst, &ds, 1, slots);
    try std.testing.expect(dst.get("age").?.isMissing());
    try std.testing.expectEqualStrings("", dst.get("name").?.str);
}

test "BUG-dateblanksep/inputdatestmtblank: DATE/MMDDYY/DDMMYY/YYMMDD informats accept blank separators" {
    // 15MAR2012 = 19067, 16MAR2012 = 19068 (days since 01JAN1960)
    try std.testing.expectEqual(@as(f64, 19067), parseDateParts("03 15 2012", .mdy).num);
    try std.testing.expectEqual(@as(f64, 19067), parseDateParts("15 03 2012", .dmy).num);
    try std.testing.expectEqual(@as(f64, 19067), parseDateParts("2012 03 15", .ymd).num);
    try std.testing.expectEqual(@as(f64, 19067), parseDateParts("03  15  12", .mdy).num); // blank run, 2-digit year
    try std.testing.expectEqual(@as(f64, 19068), parseDate("16 mar 2012").num); // case-insensitive mon
    try std.testing.expectEqual(@as(f64, 19068), parseDate("16  MAR  12").num); // 12 → 2012 via YEARCUTOFF
    try std.testing.expectEqual(@as(f64, 19068), parseDate("16/mar/2012").num); // slash separators
    // packed + existing separator forms unchanged
    try std.testing.expectEqual(@as(f64, 19067), parseDateParts("03/15/2012", .mdy).num);
    try std.testing.expectEqual(@as(f64, 19067), parseDateParts("03152012", .mdy).num);
    try std.testing.expectEqual(@as(f64, 19068), parseDate("16mar2012").num);
    try std.testing.expectEqual(@as(f64, 19068), parseDate("16-mar-2012").num);
}

test "NOTE-informatlow-tick245: statement readNum routes COMMA/DOLLAR to format.readNumeric" {
    const t = std.testing;
    // #13: the deleted local COMMA/DOLLAR copy kept interior hyphens ("12-34" →
    // missing) and ignored implied decimals; readNumeric carries both rules.
    try t.expectEqual(@as(f64, 1234), readNum("comma10.", "12-34").num);
    try t.expectEqual(@as(f64, -500), readNum("comma10.", "-500").num);
    try t.expectEqual(@as(f64, -23), readNum("comma4.", "- 23").num);
    try t.expectEqual(@as(f64, 0.001), readNum("comma10.", "1E-3").num);
    try t.expectEqual(@as(f64, 12.34), readNum("comma5.2", "1234").num); // implied decimals now honored
    // staples unchanged: parens-negative, $/, strips, documented blank-drop
    try t.expectEqual(@as(f64, -1234), readNum("comma8.", "(1,234)").num);
    try t.expectEqual(@as(f64, 1500.5), readNum("dollar12.", "$1,500.50").num);
    try t.expectEqual(@as(f64, 23), readNum("comma3.", "2 3").num);
    // #14: NEGPAREN informat fails loud on this path too (D-002, captured) — the
    // statement-prep whitelist check (above) hard-ERRORs first in a real run.
    format.g_fmt_error = false;
    format.setNoFmtErr(false);
    format.g_test_last_err = "";
    try t.expect(readNum("negparen10.", "(1,234)").isMissing());
    try t.expect(format.formatErrored());
    try t.expect(std.mem.indexOf(u8, format.g_test_last_err, "negparen") != null);
    format.g_fmt_error = false; // reset module state for other tests
}

test "REVIEW-tick344: statement readNum does NOT slice a numeric token to w (Language Reference: Concepts p.513)" {
    const t = std.testing;
    // The colon/list path hands readNum the WHOLE token; p.513 "Modified List
    // Input" limits length "(character only)", so a numeric `:comma5.` reads to
    // the blank/EOL — `5,678,999` → 5678999, NOT 5678 (qa_tick336 fixture S3).
    try t.expectEqual(@as(f64, 5678999), readNum("comma5.", "5,678,999").num);
    try t.expectEqual(@as(f64, 12345), readNum("3.", "12345").num); // :3. tokenizes too
    // …but the informat's d still implies a decimal on the token (`:5.2`).
    try t.expectEqual(@as(f64, 123.45), readNum("5.2", "12345").num);
    // The INPUT()-fn entry keeps formatted-read semantics: field sliced to w.
    try t.expectEqual(@as(f64, 123), format.readNumeric("3.", "12345").num);
    try t.expectEqual(@as(f64, 5678), format.readNumeric("comma5.", "5,678,999").num);
}

test "BUG-yearcutoff: 2-digit years honor YEARCUTOFF (SAS 9.4 default 1926)" {
    defer format.setYearCutoff(1926); // restore the SAS 9.4 default for other tests
    // default 1926 span [1926,2025]: 20–25 → 2020s, 26–99 → 1900s
    try std.testing.expectEqual(@as(f64, 23735), parseDateParts("12/25/24", .mdy).num); // 24 → 2024
    try std.testing.expectEqual(@as(f64, 0), parseDateParts("01/01/60", .mdy).num); // 60 → 1960 = day 0
    try std.testing.expectEqual(@as(f64, 0), parseDate("01JAN60").num); // DATE7 → 1960
    const d26_default = parseDateParts("01/01/26", .mdy).num; // → 1926 (start of the span)

    // OPTIONS YEARCUTOFF=2000: the span moves to [2000,2099]
    format.setYearCutoff(2000);
    try std.testing.expect(parseDateParts("01/01/60", .mdy).num != 0); // now 2060, not 1960
    const d26_2000 = parseDateParts("01/01/26", .mdy).num; // → 2026
    try std.testing.expectEqual(@as(f64, 36525), d26_2000 - d26_default); // exactly 100 years apart
}

test "label sidecar is SEPARATE from a clean data CSV (BUG-labelspersist)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("nm", .char);
    ds.setLabel("x", "The X Value");
    ds.setLabel("nm", "The Name, quoted"); // comma → CSV-quoted on the sidecar line
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .str = "abc" } });

    // the data CSV is CLEAN: header + rows only, no label line
    const text = try writeCsv(a, &ds);
    try std.testing.expectEqualStrings("x,nm\n1,abc\n", text);

    // the labels live in a separate sidecar body
    const meta = (try labelSidecar(a, &ds)).?;
    const back = try readCsv(a, text, "d2");
    try std.testing.expect(back.columns.items[0].label == null); // clean CSV → no labels yet
    try applyLabelSidecar(a, back, meta); // libname input applies the sidecar
    try std.testing.expectEqualStrings("The X Value", back.columns.items[0].label.?);
    try std.testing.expectEqualStrings("The Name, quoted", back.columns.items[1].label.?);

    // no labels → no sidecar file at all
    var plain = Dataset.init(a, "p");
    _ = try plain.addColumn("z", .num);
    try std.testing.expect((try labelSidecar(a, &plain)) == null);

    // F8: the DATASET label round-trips as a reserved `*`-named record — set
    // alone it still produces a sidecar, and it never lands on a column.
    var dl = Dataset.init(a, "dl");
    _ = try dl.addColumn("x", .num);
    dl.label = "Round Trip DS";
    const meta2 = (try labelSidecar(a, &dl)).?; // dataset label only → file written
    var back2 = Dataset.init(a, "dl2");
    _ = try back2.addColumn("x", .num);
    try applyLabelSidecar(a, &back2, meta2);
    try std.testing.expectEqualStrings("Round Trip DS", back2.label.?);
    try std.testing.expect(back2.columns.items[0].label == null); // not a column attr

    // …and alongside column entries; an OLD sidecar (no `*` record) leaves
    // the dataset label unset.
    dl.setLabel("x", "Column Label");
    const meta3 = (try labelSidecar(a, &dl)).?;
    var back3 = Dataset.init(a, "dl3");
    _ = try back3.addColumn("x", .num);
    try applyLabelSidecar(a, &back3, meta3);
    try std.testing.expectEqualStrings("Round Trip DS", back3.label.?);
    try std.testing.expectEqualStrings("Column Label", back3.columns.items[0].label.?);
    var back4 = Dataset.init(a, "dl4");
    _ = try back4.addColumn("x", .num);
    try applyLabelSidecar(a, &back4, "x,Column Label\n"); // pre-F8 shape
    try std.testing.expect(back4.label == null);
    try std.testing.expectEqualStrings("Column Label", back4.columns.items[0].label.?);
}

test "sidecar carries label + format + informat through a reload (F-varlabels)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("amt", .num);
    _ = try ds.addColumn("code", .char);
    ds.setLabel("amt", "The Amount");
    ds.setFormat("amt", "dollar10.2");
    ds.setInformat("amt", "comma8.");
    ds.setFormat("code", "$3."); // format-only column (no label) still persists

    const meta = (try labelSidecar(a, &ds)).?;
    const back = try readCsv(a, "amt,code\n1,abc\n", "d2");
    try applyLabelSidecar(a, back, meta);
    try std.testing.expectEqualStrings("The Amount", back.columns.items[0].label.?);
    try std.testing.expectEqualStrings("dollar10.2", back.columns.items[0].format.?);
    try std.testing.expectEqualStrings("comma8.", back.columns.items[0].informat.?);
    try std.testing.expect(back.columns.items[1].label == null); // format-only col: no label
    try std.testing.expectEqualStrings("$3.", back.columns.items[1].format.?);

    // backward-compat: an OLD 2-field `name,label` sidecar still applies the label.
    const old = try readCsv(a, "amt,code\n1,abc\n", "d3");
    try applyLabelSidecar(a, old, "amt,Legacy Label\n");
    try std.testing.expectEqualStrings("Legacy Label", old.columns.items[0].label.?);
    try std.testing.expect(old.columns.items[0].format == null);
}

test "PERF-importhdrquad: NameSet.unique is byte-identical to uniqueName on colliding headers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // duplicates, case variants, pre-suffixed decoys, >32-byte names colliding
    // after truncation, and headers that mangle to the same V7 name.
    const headers = [_][]const u8{
        "x",          "x",         "X",           "x1",          "x 1",
        "age",        "Age",       "AGE0",        "age",         "First Name",
        "First_Name", "first name", "2nd",        "2nd",
        "abcdefghijklmnopqrstuvwxyzabcdef", // 32
        "abcdefghijklmnopqrstuvwxyzabcdeff", // differs past the 32-cap
        "abcdefghijklmnopqrstuvwxyzabcdefg",
        "abcdefghijklmnopqrstuvwxyzabcdef0",
    };
    var set: NameSet = .{};
    var used: std.ArrayList([]const u8) = .empty;
    for (headers, 0..) |h, c| {
        const want = try uniqueName(a, &used, validName(a, h, c)); // linear-scan oracle
        const got = try set.unique(a, validName(a, h, c));
        try std.testing.expectEqualStrings(want, got);
    }
    // the exact pinned sequence (hand-verified against the oracle: X1 collides
    // with x1, Age0 with AGE0, and suffixes truncate the base to <=32 bytes):
    const want_names = [_][]const u8{
        "x", "x0", "X1", "x10", "x_1",
        "age", "Age0", "AGE00", "age1", "First_Name",
        "First_Name0", "first_name1", "_2nd", "_2nd0",
        "abcdefghijklmnopqrstuvwxyzabcdef",
        "abcdefghijklmnopqrstuvwxyzabcde0",
        "abcdefghijklmnopqrstuvwxyzabcde1",
        "abcdefghijklmnopqrstuvwxyzabcde2",
    };
    var set3: NameSet = .{};
    for (headers, 0..) |h, c|
        try std.testing.expectEqualStrings(want_names[c], try set3.unique(a, validName(a, h, c)));
}

test "NOTE-exportspecialmiss: EXPORT writes the special-missing letter; plain missing stays empty; internal stays '.'" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("n", .num);
    try ds.appendRow(&.{Value.specialMissing('A')});
    try ds.appendRow(&.{Value.specialMissing('Z')});
    try ds.appendRow(&.{Value.specialMissing('_')});
    try ds.appendRow(&.{Value.missing});
    try ds.appendRow(&.{.{ .num = 5 }});

    const exp = try writeCsvExport(a, &ds);
    try std.testing.expectEqualStrings("n\n.A\n.Z\n._\n\n5\n", exp);
    // internal libname CSV unchanged: every missing is "." (round-trip path).
    const internal = try writeCsv(a, &ds);
    try std.testing.expectEqualStrings("n\n.\n.\n.\n.\n5\n", internal);
}
