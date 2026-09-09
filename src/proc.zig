//! PROC steps beyond the DATA step. Each PROC hand-parses its own token slice —
//! the DATA-step parser (A2, parser.zig) is off-limits here — and operates on
//! datasets already sitting in the `Library`. The CLI (main.zig) dispatches a
//! `proc <name> …; … run;` step here by name.
//!
//! SORT. `proc sort data=IN [out=OUT]; by [descending] var …; run;`
//! Sorts IN in place, or, with OUT=, writes a sorted copy and leaves IN alone.
//! Order is SAS-default: numeric with missing lowest, char blank-padded ASCII;
//! a stable sort, so ties keep input order.
//!
//! MEANS/SUMMARY. `proc means data=IN; [var …;] [by …;] run;` — N, Mean, Std
//! Dev, Minimum, Maximum for each numeric analysis variable (all numerics, or
//! the `var` list), rendered as SAS's listing table. Optional BY groups (input
//! assumed already sorted by the BY vars, as SAS requires).
//!
//! Stat keywords (N MEAN STD MIN MAX SUM NMISS MEDIAN Q1 Q3) select which stats
//! and their order; none named → the 5 defaults. A single analysis var renders
//! the "Analysis Variable" block, multiple vars the combined "Variable" table.
//!
//! ponytail: NODUPKEY dedups; no NODUPRECS, no KEY=/collate options, single BY
//! statement. MAXDEC=n sets the decimals shown for the stat columns (default 7).

const std = @import("std");
const assert = std.debug.assert;
const lex = @import("lexer.zig");
const diag = @import("diag.zig");
const Value = @import("value.zig").Value;
const Dataset = @import("dataset.zig").Dataset;
const Column = @import("dataset.zig").Column;
const Library = @import("exec.zig").Library;
const format = @import("format.zig");
const missingOf = @import("pdv.zig").missingOf;
const VarType = @import("pdv.zig").VarType;
const Pdv = @import("pdv.zig").Pdv;
const pe = @import("parser_expr.zig"); // reuse the DATA-step expression parser (PROC REPORT COMPUTE)
const eval = @import("eval.zig"); // …and its evaluator, for per-row computed columns
const ast = @import("ast.zig");
const io = @import("io.zig"); // reuse the DATA-step WHERE / dataset-option evaluator
const dsfns = @import("dsfns.zig"); // libref→dir map for on-disk member deletes

const Token = lex.Token;

/// The three deps every PROC handler needs (QL-B, taste #5): one bundle instead
/// of `(arena, lib, diags)` threaded through all 15 run* signatures. `out` stays
/// an explicit param on the listing PROCs — its presence self-documents "this
/// PROC emits listing text".
pub const ProcCtx = struct { arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics };

const SortKey = struct { idx: usize, desc: bool };

// A PROC REPORT `compute <col>; … endcomp;` block: the target column name and
// the raw tokens between the opening `;` and `endcomp` (parsed at eval time).
const Compute = struct { col: []const u8, body: []const Token };

// A `compute after|before [<var>]; … endcomp;` block (compute-at-break): `bvar`
// is the BREAK variable it attaches to (null = the RBREAK grand total); `before`
// distinguishes BEFORE- from AFTER-break placement. The body fills the computed
// columns ON that SUMMARIZE line from the row's aggregated values (and may hold
// LINE statements). Raw tokens parsed at eval time, like `Compute`.
const AfterSrc = struct { bvar: ?[]const u8, before: bool = false, body: []const Token };

// A parsed PROC REPORT LINE statement (basic): an ordered list of items rendered
// into one free-text line at summary-row position. Scope: literal text, a numeric
// variable ref (optional format), and `@n` column pointers; advanced forms
// (`#n`, repeated-char, pointer expressions) fail loud (procreport rest3).
const LineItem = union(enum) {
    lit: []const u8, // a quoted literal
    at: usize, // `@n` — move the cursor to column n (1-based)
    var_ref: struct { name: []const u8, fmt: ?[]const u8 }, // a numeric var, optional format
};
const LineSpec = []const LineItem;

// An emitted report row: normal formatted cells, or a raw free-text LINE line.
const Row = union(enum) { cells: []const []const u8, line: []const u8 };

// ── proc input filtering: WHERE statement + data=NAME(...) dataset options ────
//
// A PROC step's row subset comes from two places SAS honours but that we used to
// ignore (BUG-procwhere): a `where <expr>;` statement, and `where=`/`keep=`/… in
// a `data=NAME(opts)` reference. Both reuse the DATA-step evaluator in io.zig;
// we apply them to a COPY so the library table is unchanged for later steps.

/// The resolved input for a proc, filtered by its WHERE statement and/or its
/// `data=NAME(...)` dataset options, and bounded by the global `options
/// obs=/firstobs=` default range (BUG-globalobsproc). Returns `ds` untouched
/// when there's nothing to apply (no copy), else a filtered copy.
pub fn procInput(arena: std.mem.Allocator, ds: *Dataset, toks: []const Token, diags: *diag.Diagnostics) diag.Error!*Dataset {
    return (try procInputObs(arena, ds, toks, diags)).ds;
}

pub const ProcInput = struct { ds: *Dataset, srcobs: ?[]const usize = null };

/// procInput + the physical SOURCE observation number (1-based) of each
/// surviving row (BUG-printobsnum): PROC PRINT's Obs column must show a row's
/// position in the input dataset, not its index among the printed rows.
/// `srcobs` is null when nothing filtered (Obs = 1..n, byte-identical).
pub fn procInputObs(arena: std.mem.Allocator, ds: *Dataset, toks: []const Token, diags: *diag.Diagnostics) diag.Error!ProcInput {
    const opts = dataOptionToks(toks);
    const wstmt = try whereStmtToks(arena, toks);
    if (opts.len == 0 and wstmt == null and !io.globalObsActive()) return .{ .ds = ds };
    const copy = try dupDataset(arena, ds);
    var optdiags = diag.Diagnostics.init(arena); // local: PROC dataset-option WARNINGS drop here (.err promoted below)
    // ponytail: PROC data= is INPUT, but dataset-option WARNINGS are dropped
    // here (local `optdiags`), so DKRICOND-vs-DKROCOND severity is moot for
    // them — what input=true buys is the global `options obs=/firstobs=`
    // default range
    // (BUG-globalobsproc); a per-dataset (obs=)/(firstobs=) overrides field by
    // field. The slice is DEFERRED (skip_obs_slice) to below the WHERE-statement
    // filter (BUG-procwherestmtorder): Language Reference: Concepts p.229 — FIRSTOBS=/OBS= count
    // positions WITHIN the WHERE-selected subset, for the WHERE statement and
    // the where= option alike (the where= option already filters first inside
    // applyDatasetOptionsObs, BUG-whereobsorder; mirrors the DATA-step
    // finishResolve, BUG-wherestmtobsorder).
    var srcobs: ?[]const usize = null;
    if (opts.len > 0)
        try io.applyDatasetOptionsObs(arena, copy, opts, &optdiags, true, true, &srcobs, &.{});
    // BUG-procwhereoptswallow: a where= dataset OPTION whose predicate fails to
    // parse or names an unknown variable records an `.err` into `optdiags` — and
    // used to die in that sink (unknown var → silently 0 rows, malformed →
    // silently the FULL table, both exit 0; SAS 9.4 ERRORs and prints nothing).
    // Promote the first option `.err` to the real diags and abort the step,
    // mirroring the WHERE-statement path below — EXCEPT the intentional
    // DKRICOND drop: an unknown keep=/drop=/rename= name on a PROC input option
    // ("…never been referenced", .err because input=true) stays silent.
    // ponytail: message-text filter — the only other `.err` this sink can hold;
    // a severity/sink split in io.zig would touch exec.zig's paths for no gain.
    for (optdiags.list.items) |d|
        if (d.severity == .err and std.mem.indexOf(u8, d.message, "never been referenced") == null) {
            try diags.report(.err, d.line, "{s}", .{d.message});
            return error.ParseError;
        };
    // WHERE STATEMENT (BUG-procwherestmtsilent): a malformed predicate must fail
    // LOUD and ABORT the step, never silently run on the full table. io.applyWhere
    // records the parse error but swallows the Zig error, so we route it through
    // the REAL `diags` and propagate error.ParseError when it fires — mirroring the
    // DATA-step WHERE, which uses the real diags too (exec.applyWhereStmt).
    if (wstmt) |w| {
        const before = diags.count();
        try io.applyDatasetOptionsObs(arena, copy, w, diags, false, false, &srcobs, &.{});
        var k = before;
        while (k < diags.count()) : (k += 1)
            if (diags.list.items[k].severity == .err) return error.ParseError;
    }
    // The deferred firstobs=/obs= slice, LAST: positions count within the
    // fully WHERE-filtered subset (Language Reference: Concepts p.229's worked program: subset 91-100,
    // firstobs=2 obs=4 → observations 92, 93, 94). Empty opts = the global
    // `options obs=/firstobs=` default range, which a per-dataset option
    // overrides field by field inside applyObsSlice.
    if (opts.len > 0 or io.globalObsActive())
        try io.applyObsSlice(arena, copy, opts, true, &srcobs);
    return .{ .ds = copy, .srcobs = srcobs };
}

/// A shallow copy: independent column/row lists, but the row cells (arena-owned,
/// immutable) are shared. `applyDatasetOptions` only drops rows / rebuilds the
/// lists, so the source dataset is never disturbed.
fn dupDataset(arena: std.mem.Allocator, src: *const Dataset) !*Dataset {
    const ds = try arena.create(Dataset);
    ds.* = Dataset.init(arena, src.name);
    for (src.columns.items) |c| try ds.columns.append(arena, c);
    for (src.rows.items) |r| try ds.rows.append(arena, r);
    return ds;
}

/// Tokens inside a `data=NAME(...)` dataset-option list (`keep=`/`where=`/…), or
/// empty if the data= reference is unparenthesised. Scans the proc header only.
fn dataOptionToks(toks: []const Token) []const Token {
    var i: usize = 2; // past `proc <name>`
    while (i + 1 < toks.len and toks[i].tag != .semicolon) : (i += 1) {
        if (!(tkKw(toks[i], "data") and toks[i + 1].tag == .eq)) continue;
        var j = i + 3; // past `data = NAME`
        if (j >= toks.len or toks[j].tag != .lparen) return &.{};
        const start = j + 1;
        var depth: usize = 1;
        j += 1;
        while (j < toks.len) : (j += 1) {
            if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
                depth -= 1;
                if (depth == 0) return toks[start..j];
            }
        }
        return &.{};
    }
    return &.{};
}

/// Tokens inside an output dataset's option list `out=NAME(...)` (`keep=`/`drop=`/
/// `rename=`/`where=`), scanned anywhere in the step — the proc header (SORT/
/// CONTENTS/TRANSPOSE) or an `output out=…` sub-statement (MEANS/UNIVARIATE).
/// Empty if the first `out=` is unparenthesised (BUG-procoutkeep).
/// `kw` selects the option keyword — "out", or "dupout" for PROC SORT's
/// DUPOUT=NAME(...) (BUG-sortdupoutfamily).
fn outOptionToks(toks: []const Token, kw: []const u8) []const Token {
    var i: usize = 0;
    while (i + 1 < toks.len) : (i += 1) {
        if (!(tkKw(toks[i], kw) and toks[i + 1].tag == .eq)) continue;
        var j = i + 3; // past `out = NAME`
        if (j >= toks.len or toks[j].tag != .lparen) continue; // unparenthesised — keep scanning
        const start = j + 1;
        var depth: usize = 1;
        j += 1;
        while (j < toks.len) : (j += 1) {
            if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
                depth -= 1;
                if (depth == 0) return toks[start..j];
            }
        }
        return &.{};
    }
    return &.{};
}

/// Apply an `out=NAME(keep=/drop=/rename=/where=)` option list to a freshly
/// materialized PROC output dataset, reusing the DATA-step filter (BUG-procoutkeep).
/// ponytail: single-out= procs scan the raw step tokens; PROC MEANS captures the
/// option slice per OUTPUT statement instead (BUG-meansoutmultistmt).
fn applyOutOptions(arena: std.mem.Allocator, ds: *Dataset, toks: []const Token, diags: *diag.Diagnostics, kw: []const u8) !void {
    const opts = outOptionToks(toks, kw);
    if (opts.len > 0) try io.applyDatasetOptions(arena, ds, opts, diags, false); // out= is OUTPUT: DKROCOND=WARN
}

/// A `where <expr>;` proc statement rewritten as `where=(<expr>)` option tokens,
/// so `io.applyDatasetOptions` can filter with the same evaluator. Null if the
/// step has no WHERE statement.
fn whereStmtToks(arena: std.mem.Allocator, toks: []const Token) !?[]const Token {
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) i += 1; // skip the header
    // BUG-whereproc-half: SAS 9.4 last-wins — a second plain WHERE replaces the
    // first, so keep scanning and build from the LAST one (qa-findings-tick147;
    // mirrors the DATA-step half in exec.zig, 09c9583).
    var start: usize = 0;
    var end: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag != .semicolon) continue; // WHERE begins a statement
        if (!(atKw(toks, i + 1, "where"))) continue;
        start = i + 2;
        end = start;
        while (end < toks.len and toks[end].tag != .semicolon) end += 1;
    }
    if (end == 0) return null; // no WHERE statement
    if (end == start) return null; // trailing bare `where;` cancels (SAS behavior)
    const out = try arena.alloc(Token, end - start + 4);
    out[0] = .{ .tag = .name, .text = "where" };
    out[1] = .{ .tag = .eq };
    out[2] = .{ .tag = .lparen };
    @memcpy(out[3 .. 3 + (end - start)], toks[start..end]);
    out[out.len - 1] = .{ .tag = .rparen };
    return out;
}

/// Run a `proc sort …; by …; run;` step. `toks` is the whole step, starting at
/// the `proc` token (no trailing `.eof` required — we walk with bounds checks).
pub fn runSort(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    // ── header options, up to the first ';'  (proc sort data=… out=… ;)
    var in_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var nodupkey = false;
    var noduprec = false; // NODUPREC/NODUP/NODUPRECS: drop fully-identical rows
    var dupout_name: ?[]const u8 = null; // DUPOUT=: the removed duplicates
    var linguistic = io.global_sortseq_linguistic; // SORTSEQ=LINGUISTIC: case-folded dictionary collation (the system option supplies the default, BUG-optionsstmtswallow; the PROC option below overrides)
    var i: usize = 2; // past `proc sort`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
        } else if (optAt(toks, i, "dupout")) |v| {
            dupout_name = v;
            i += 3;
        } else if (optAt(toks, i, "sortseq")) |v| {
            // BUG-sortseq: LINGUISTIC changes output order — never drop it silently.
            // ASCII is exactly our byte order; anything else we can't collate.
            if (eqi(v, "linguistic")) {
                linguistic = true;
                // LINGUISTIC(...) sub-options (NUMERIC_COLLATION=, STRENGTH=, …)
                // tune the collation — skipping the parens would silently collate
                // differently than explicitly requested. Fail loud (D-002, F7).
                if (i + 3 < toks.len and toks[i + 3].tag == .lparen) {
                    unsupported("PROC SORT: SORTSEQ=LINGUISTIC(...) sub-options are not supported");
                    return;
                }
            } else if (eqi(v, "ascii")) {
                linguistic = false; // explicit ASCII overrides a system SORTSEQ=LINGUISTIC
            } else {
                unsupported("PROC SORT: SORTSEQ= collation other than ASCII/LINGUISTIC");
                return;
            }
            i += 3;
        } else if (tkKw(toks[i], "nodupkey")) {
            nodupkey = true;
            i += 1;
        } else if (tkKw(toks[i], "noduprec") or tkKw(toks[i], "nodup") or tkKw(toks[i], "noduprecs")) {
            noduprec = true;
            i += 1;
        } else if (tkKw(toks[i], "tagsort") or tkKw(toks[i], "equals") or tkKw(toks[i], "noequals") or
            tkKw(toks[i], "threads") or tkKw(toks[i], "nothreads") or tkKw(toks[i], "overwrite") or
            tkKw(toks[i], "datecopy"))
        {
            // benign: perf/tie-stability/data-stamping hints — none can change the
            // sort RESULT (THREADS is the SAS default; OVERWRITE/DATECOPY are moot
            // for our replace-always OUT=). Keep this list closed (D-002).
            i += 1;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // dataset options, e.g. data=d(keep=x) — applied elsewhere
        } else {
            // D-002 fail-loud (BUG-procoptswallow): an unknown header option must
            // error visibly, not vanish — a typo'd option changes expected output.
            // BUG-proctypoexits2: split — a documented option we don't implement
            // is a gap (rc 2, byte-identical UNSUPPORTED message); any other
            // name is the user's typo (rc 1, same message body via diags).
            if (toks[i].tag == .name) {
                if (isSortGapOption(toks[i].text)) {
                    unsupported(try std.fmt.allocPrint(arena, "PROC SORT: unknown option {s}", .{toks[i].text}));
                    return;
                }
                return diags.fail(error.ParseError, toks[i].line, "PROC SORT: unknown option {s}", .{toks[i].text});
            }
            i += 1; // stray punctuation
        }
    }

    // DUPOUT= names the removed duplicates — meaningless without a dedup pass, so
    // SAS errors when it appears alone. Fail loud, don't silently create nothing.
    if (dupout_name != null and !nodupkey and !noduprec) {
        unsupported("PROC SORT: DUPOUT= requires the NODUPKEY or NODUPRECS option");
        return;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        // Absent input: warn+skip like the DATA-step SET does, not a fail-loud
        // "UNSUPPORTED" — PROC SORT IS supported; the table just isn't there
        // (usually a cross-step/cross-program dataset a standalone run hasn't
        // produced). SORT-emptytol.
        diags.warn(if (toks.len > 1) toks[1].line else 0, "dataset {s} not found; PROC SORT skipped", .{in_name orelse "?"}) catch {};
        return;
    };

    // D-002 fail-loud (BUG-sortdupoutfamily): DUPOUT= naming the member the
    // sorted result lands in — the in-place input, or OUT= — lets the dups-only
    // residue overwrite the sorted data (silent data loss, exit 0 today). A
    // collision is a user mistake with no sane silent outcome, so ERROR + stop.
    if (dupout_name) |dn| {
        const sorted_member = if (out_name != null and !eqi(out_name.?, raw.name)) out_name.? else raw.name;
        if (eqi(dn, sorted_member)) {
            diags.report(.err, if (toks.len > 1) toks[1].line else 0, "PROC SORT: DUPOUT= dataset {s} is also the sorted output (DATA=/OUT=) — the duplicates would overwrite the sorted result", .{dn}) catch {};
            return;
        }
    }

    // Input dataset options + WHERE statement (BUG-sortinputopts): route the input
    // through the SAME procInput helper every other PROC uses, so
    // data=x(where=/keep=/drop=/rename=) and a `where …;` statement filter rows/cols
    // BEFORE sorting instead of being skipped. Returns `raw` itself when nothing
    // filters (byte-identical path). A WHERE may sit before OR after BY.
    const src = try procInput(arena, raw, toks, diags);

    // OUT= produces a sorted copy (sharing the immutable row slices) and leaves the
    // source untouched; otherwise we sort in place — and if input options produced a
    // filtered copy, commit it back over the source so the in-place result persists.
    // OUT=_NULL_ is the SAS discard idiom: the sort AND the dedup still run (so
    // `out=_null_ nodupkey dupout=g` still extracts dups) — only the final put of
    // the sorted result is skipped (F5).
    const out_null = out_name != null and eqi(out_name.?, "_null_");
    const target = if (out_name != null and !eqi(out_name.?, src.name)) blk: {
        const o = try arena.create(Dataset);
        o.* = Dataset.init(arena, out_name.?);
        for (src.columns.items) |c| try o.columns.append(arena, c); // full struct: keep format/informat/label (GH#49)
        try o.rows.appendSlice(arena, src.rows.items);
        if (!out_null) try lib.put(out_name.?, o);
        break :blk o;
    } else blk: {
        if (src != raw) try lib.put(raw.name, src); // filtered copy → persist in place
        break :blk src;
    };

    // SAS validates the BY statement (missing BY, bad BY var, empty BY list)
    // regardless of row count, so we DON'T short-circuit past validation for a
    // 0-obs input anymore (NOTE-sort0obsvalidation). Exception: a truly SCHEMALESS
    // empty dataset (0 rows AND 0 columns — e.g. a `set` of an absent table
    // produced no rows and no columns) has no columns to check a BY var against,
    // so it stays tolerant (SORT-emptytol). A 0-obs input WITH a schema falls
    // through to BY parsing/validation, then returns before the no-op sort.
    if (target.rows.items.len == 0 and target.columns.items.len == 0) return;

    // ── the `by` statement:  by [descending] name … ;  — find it past the header,
    // skipping any WHERE / other statements that precede it (any statement order).
    if (atTag(toks, i, .semicolon)) i += 1; // past the header ';'
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit") or tkKw(toks[i], "by")) break;
        if (tkKw(toks[i], "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1; // procInput applies it
        } else if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            // D-014a mid-step globals: skip exactly what the top level HANDLES
            // mid-step — hoisted TITLE/FOOTNOTE/OPTIONS and (since
            // BUG-filenamemidstep) FILENAME/ODS, the inert batch-unobservables,
            // LIBNAME via the parseLibnames pre-pass.
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (toks[i].tag == .name) {
            // D-002 fail-loud (GAP-procsubstmtswallow): an unknown sub-statement
            // used to be token-swallowed here while this PROC's own OPTION loop
            // already errored — one PROC, two policies.
            return diags.fail(error.ParseError, toks[i].line, "PROC SORT statement {s} is not supported", .{toks[i].text});
        } else i += 1; // stray punctuation (incl. a null statement's `;`)
        // BUG-sortstraysemi: GUARDED like the four sibling loops — the else arm
        // already consumed the stray token, so an UNCONDITIONAL advance ate the
        // NEXT token too (the `by`), and the loop then failed loud on the BY
        // variable. Exactly one token per path.
        if (atTag(toks, i, .semicolon)) i += 1; // past its ';'
    }
    if (i >= toks.len or !tkKw(toks[i], "by")) {
        unsupported("PROC SORT without a BY statement");
        return;
    }
    i += 1;

    var keys: std.ArrayList(SortKey) = .empty;
    var desc = false;
    while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
        if (toks[i].tag != .name) continue;
        if (eqi(toks[i].text, "descending")) {
            desc = true;
            continue;
        }
        // SAS variable-list keywords in a BY statement expand to columns in
        // dataset order, each honouring the pending `descending` (SORT-bykeyword):
        // _ALL_ = every column, _NUMERIC_/_CHARACTER_ = that type only.
        if (eqi(toks[i].text, "_all_") or eqi(toks[i].text, "_numeric_") or eqi(toks[i].text, "_character_")) {
            const only_num = eqi(toks[i].text, "_numeric_");
            const only_char = eqi(toks[i].text, "_character_");
            for (target.columns.items, 0..) |c, k| {
                if (only_num and c.type != .num) continue;
                if (only_char and c.type != .char) continue;
                try keys.append(arena, .{ .idx = k, .desc = desc });
            }
            desc = false;
            continue;
        }
        // GROUPFORMAT is a real SAS SORT BY option (sort/group by the
        // FORMATTED values) — result-changing, never a variable name. Naming
        // it beats the misleading "BY variable groupformat is not in dataset"
        // below (GAP-dsmgmt-tick262 F6); honoring it needs format-aware keys.
        if (eqi(toks[i].text, "groupformat")) {
            unsupported("PROC SORT: BY GROUPFORMAT (sort by formatted values) is not supported");
            return;
        }
        // NOTSORTED is flatly illegal here — "You cannot use the NOTSORTED
        // option in a PROC SORT step" (Base SAS Procedures Guide p.75). SAS
        // ERRORs, so we error too; only the old phantom "BY variable notsorted
        // is not in dataset" message was wrong (NOTE-sortnotsortedmsg).
        if (eqi(toks[i].text, "notsorted"))
            return diags.fail(error.ParseError, toks[i].line, "PROC SORT: the NOTSORTED option cannot be used in a PROC SORT step", .{});
        const idx = target.indexOf(toks[i].text) orelse {
            diags.report(.err, toks[i].line, "BY variable {s} is not in dataset {s}", .{ toks[i].text, target.name }) catch {};
            continue;
        };
        try keys.append(arena, .{ .idx = idx, .desc = desc });
        desc = false;
    }
    // GAP-procsubstmtswallow: statements AFTER the BY list get the identical
    // policy — WHERE (procInput already applied it) and the D-014a mid-step
    // globals skip honestly; any other statement fails loud. One PROC, one
    // policy.
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "where") or (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text))) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (toks[i].tag == .name) {
            return diags.fail(error.ParseError, toks[i].line, "PROC SORT statement {s} is not supported", .{toks[i].text});
        } else i += 1; // stray punctuation (incl. the BY list's own ';')
        if (atTag(toks, i, .semicolon)) i += 1;
    }
    if (keys.items.len == 0) {
        unsupported("PROC SORT: empty BY list");
        return;
    }

    // BY validated. A 0-observation (with-schema) input sorts to itself — nothing
    // to reorder — so return before the no-op sort/dedup (NOTE-sort0obsvalidation).
    if (target.rows.items.len == 0) return;

    // every sort key indexes a real column of the target (indexOf guaranteed it);
    // sortRows reads row[key.idx] on each row, so an out-of-range key = wrong sort.
    for (keys.items) |k| assert(k.idx < target.columns.items.len);
    sortRowsColl(target.rows.items, keys.items, linguistic);

    // NODUPKEY drops a row whose BY key repeats the previous kept row; NODUPREC
    // drops a row identical (EVERY column) to the previous kept row. The stable
    // sort keeps the first of each run (matches SAS). Removed rows optionally go to
    // DUPOUT= (BUG-sortnoduprec).
    if (nodupkey or noduprec) {
        var dups: std.ArrayList([]const Value) = .empty;
        if (target.rows.items.len > 1) {
            const rows = target.rows.items;
            var w: usize = 1; // row 0 is always kept
            var r: usize = 1;
            while (r < rows.len) : (r += 1) {
                const is_dup = if (noduprec)
                    fullEqual(rows[w - 1], rows[r])
                else
                    sameKey(rows[w - 1], rows[r], keys.items);
                if (is_dup) {
                    if (dupout_name != null) try dups.append(arena, rows[r]);
                } else {
                    rows[w] = rows[r];
                    w += 1;
                }
            }
            target.rows.shrinkRetainingCapacity(w);
        }
        // DUPOUT=: materialize the removed duplicate rows into their own dataset.
        // Outside the len>1 guard (BUG-sortdupoutfamily): SAS creates DUPOUT
        // (0 obs, full schema) whenever NODUP*/DUPOUT= is given — a 1-obs input
        // has no possible dups but the dataset must still exist.
        if (dupout_name) |dn| {
            const d = try arena.create(Dataset);
            d.* = Dataset.init(arena, dn);
            for (target.columns.items) |c| try d.columns.append(arena, c); // full struct: keep format/informat/label
            try d.rows.appendSlice(arena, dups.items);
            try lib.put(dn, d);
            // dupout=X(keep=/drop=/rename=) — same option path as out= (F4).
            try applyOutOptions(arena, d, toks, diags, "dupout");
        }
    }

    // OUT=X(keep=/drop=/rename=) applied AFTER the sort, so a BY variable that
    // keep= excludes is still present while sorting (BUG-procoutkeep).
    if (out_name != null) try applyOutOptions(arena, target, toks, diags, "out");
}

/// Equal on EVERY column — the NODUPREC "exact duplicate row" test.
fn fullEqual(l: []const Value, r: []const Value) bool {
    if (l.len != r.len) return false;
    for (l, r) |lv, rv| if (cmpValue(lv, rv) != .eq) return false;
    return true;
}

/// Equal on every BY key column (companion to `Ctx.less`).
fn sameKey(l: []const Value, r: []const Value, keys: []const SortKey) bool {
    for (keys) |k| if (cmpValue(l[k.idx], r[k.idx]) != .eq) return false;
    return true;
}

/// Stable sort of observation rows by the given keys (in place). MUST be
/// std.sort.block (stable), not std.mem.sort (pdq, UNSTABLE at real-data
/// sizes). SAS 9.4 actually defaults to NOEQUALS (tie order unspecified), so
/// an always-stable sort is a VALID SAS outcome — and downstream SEQ
/// numbering locks tie order into the output, so stability is required to
/// match golden: an unstable sort made gen2 AE's value-identical rows land
/// in a different order than golden (qa tick-37 / TRIAGE-gen2values).
pub fn sortRows(rows: [][]const Value, keys: []const SortKey) void {
    sortRowsColl(rows, keys, false);
}

/// sortRows with a collation choice: `ling` folds case on character keys
/// (SORTSEQ=LINGUISTIC, BUG-sortseq).
fn sortRowsColl(rows: [][]const Value, keys: []const SortKey, ling: bool) void {
    std.sort.block([]const Value, rows, Ctx{ .keys = keys, .ling = ling }, Ctx.less);
}

const Ctx = struct {
    keys: []const SortKey,
    ling: bool = false,
    fn less(ctx: Ctx, l: []const Value, r: []const Value) bool {
        for (ctx.keys) |k| switch (cmpColl(l[k.idx], r[k.idx], ctx.ling)) {
            .lt => return !k.desc,
            .gt => return k.desc,
            .eq => {},
        };
        return false; // equal on all keys → keep input order (stable)
    }
};

// ── comparison (SAS default order) ───────────────────────────────────────────

fn cmpValue(x: Value, y: Value) std.math.Order {
    return cmpColl(x, y, false);
}

/// cmpValue with a collation: `ling` compares character values case-folded.
/// pub: THE one collation-aware Value compare — sql.zig delegates here
/// (NOTE-collationduplicated landed in 2362f653: its private `cmpValColl`
/// copy was verified byte-equivalent and deleted). This decides SORT ORDER
/// (PROC SORT/BY merges here; DISTINCT/GROUP BY/ORDER BY there), so the body
/// is behaviour-frozen: any semantic change moves row order in goldens and
/// must audit every caller in both files in the same commit.
pub fn cmpColl(x: Value, y: Value, ling: bool) std.math.Order {
    // A column is single-typed, so both sides match; two chars compare as
    // blank-padded strings, everything else numerically (missing lowest).
    if (x == .str and y == .str) return if (ling) cmpStrLing(x.str, y.str) else cmpStr(x.str, y.str);
    return cmpNum(toNum(x), toNum(y));
}

fn cmpNum(a: f64, b: f64) std.math.Order {
    const am = std.math.isNan(a);
    const bm = std.math.isNan(b);
    if (am and bm) return std.math.order(Value.missingRank(a), Value.missingRank(b)); // BUG-sortspecialmiss: ._ < . < .A < … < .Z
    if (am) return .lt; // missing sorts below every real number
    if (bm) return .gt;
    return std.math.order(a, b);
}

fn cmpStr(a: []const u8, b: []const u8) std.math.Order {
    const n = @max(a.len, b.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ca = if (i < a.len) a[i] else ' '; // shorter side blank-padded
        const cb = if (i < b.len) b[i] else ' ';
        if (ca != cb) return std.math.order(ca, cb);
    }
    return .eq;
}

/// SORTSEQ=LINGUISTIC dictionary order: letters compare case-folded, so `apple`
/// sorts before `Banana` (BUG-sortseq). ponytail: ASCII case-fold only, no
/// locale weights/ICU — add when a study needs locale-specific collation.
fn cmpStrLing(a: []const u8, b: []const u8) std.math.Order {
    const n = @max(a.len, b.len);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        const ca = std.ascii.toLower(if (i < a.len) a[i] else ' '); // blank-pad like cmpStr
        const cb = std.ascii.toLower(if (i < b.len) b[i] else ' ');
        if (ca != cb) return std.math.order(ca, cb);
    }
    return .eq;
}

fn toNum(v: Value) f64 {
    return switch (v) {
        .num => |x| x,
        .str => |s| blk: {
            const tr = std.mem.trim(u8, s, " ");
            break :blk if (tr.len == 0) std.math.nan(f64) else (std.fmt.parseFloat(f64, tr) catch std.math.nan(f64));
        },
    };
}

// ── PROC MEANS / SUMMARY ─────────────────────────────────────────────────────

// The listing table is 76 columns wide: N in a right-justified width-12 field,
// then Mean / Std Dev / Minimum / Maximum each right-justified in width 16.
const MEANS_TITLE = (" " ** 39) ++ "The MEANS Procedure\n";
const SUMMARY_TITLE = (" " ** 37) ++ "The SUMMARY Procedure\n";
const MEANS_COMBINED_TITLE = (" " ** 26) ++ "The MEANS Procedure\n";
const default_stats = [_]StatKind{ .n, .mean, .std, .min, .max };

const Stats = struct {
    n: usize,
    sumw: f64 = std.math.nan(f64), // Σ wᵢ (== n unweighted); stderr/t/probt/lclm/uclm divide by this, not n (BUG-meanswstderr)
    mean: f64,
    std: f64,
    min: f64,
    max: f64,
    sum: f64,
    median: f64,
    q1: f64,
    q3: f64,
    // BUG-meanspctlmore: extra percentiles, mode, and the (un)corrected sums of squares.
    p1: f64 = std.math.nan(f64),
    p5: f64 = std.math.nan(f64),
    p10: f64 = std.math.nan(f64),
    // GAP-meanspctlkeywords: the rest of the documented percentile keyword set
    // (pp.1491–1492) — P20/P30/P40/P60/P70/P80.
    p20: f64 = std.math.nan(f64),
    p30: f64 = std.math.nan(f64),
    p40: f64 = std.math.nan(f64),
    p60: f64 = std.math.nan(f64),
    p70: f64 = std.math.nan(f64),
    p80: f64 = std.math.nan(f64),
    p90: f64 = std.math.nan(f64),
    p95: f64 = std.math.nan(f64),
    p99: f64 = std.math.nan(f64),
    mode: f64 = std.math.nan(f64),
    css: f64 = std.math.nan(f64),
    uss: f64 = std.math.nan(f64),
    // GAP-meansskewkurt: SAS g1/g2 sample moments (VARDEF=DF forms only).
    skew: f64 = std.math.nan(f64),
    kurt: f64 = std.math.nan(f64),
};

/// VARDEF= divisor for variance/std/CV/stderr (BUG-statvardef): DF = n−1
/// (default), N = n, WEIGHT/WGT = Σwᵢ, WDF = Σwᵢ−1. Unweighted Σwᵢ == n, so
/// WGT↔N and WDF↔DF coincide without a WEIGHT statement.
const VarDef = enum { df, n, wgt, wdf };

fn varDefFromName(v: []const u8) ?VarDef {
    if (eqi(v, "df")) return .df;
    if (eqi(v, "n")) return .n;
    if (eqi(v, "weight") or eqi(v, "wgt")) return .wgt;
    if (eqi(v, "wdf")) return .wdf;
    return null;
}

/// The statistics a MEANS request can name, in SAS's listing order. SAS exposes a
/// FIXED percentile keyword set — arbitrary `Pnn` is not a MEANS keyword, so it is
/// intentionally not accepted (BUG-meanspctlmore). The documented quantile set
/// (Base SAS 9.4 Procedures Guide, PROC MEANS statement, printed pp.1491–1492) is
/// P1/P5/P10/P20/P25(Q1)/P30/P40/P50(MEDIAN)/P60/P70/P75(Q3)/P80/P90/P95/P99 plus
/// QRANGE — all decoded below (GAP-meanspctlkeywords added the middle six).
const StatKind = enum { n, mean, std, min, max, sum, sumwgt, nmiss, median, q1, q3, var_, cv, stderr, range, p1, p5, p10, p20, p30, p40, p60, p70, p80, p90, p95, p99, qrange, mode, css, uss, lclm, uclm, t, probt, skewness, kurtosis };

fn statFromKw(text: []const u8) ?StatKind {
    if (eqi(text, "n")) return .n;
    if (eqi(text, "mean")) return .mean;
    if (eqi(text, "std") or eqi(text, "stddev")) return .std;
    if (eqi(text, "min")) return .min;
    if (eqi(text, "max")) return .max;
    if (eqi(text, "sum")) return .sum;
    // SUMWGT (GAP-sumwgtkeyword): a DOCUMENTED PROC MEANS statistic-keyword —
    // printed p.1491 lists it under "Descriptive statistic keywords", and Table 2.1
    // p.70 scopes it to "MEANS or SUMMARY, REPORT, SQL, TABULATE, UNIVARIATE". It
    // was absent here, so `proc means sumwgt` WARNED "statistic-keyword sumwgt is
    // not recognized and is ignored" — a false statement about a real keyword, and
    // a silently dropped column — while UNIVARIATE's `output out= sumwgt=` failed
    // loud through the same decoder. Both surfaces route through statFromKw, so one
    // entry fixes both. The value already existed on Stats (Σwᵢ, p.2745 "SUMWGT is
    // the sum of the weights, W, computed as Σwᵢ").
    if (eqi(text, "sumwgt")) return .sumwgt;
    if (eqi(text, "nmiss")) return .nmiss;
    if (eqi(text, "median") or eqi(text, "p50")) return .median;
    if (eqi(text, "q1") or eqi(text, "p25")) return .q1;
    if (eqi(text, "q3") or eqi(text, "p75")) return .q3;
    if (eqi(text, "var")) return .var_; // BUG-meansstatsmore
    if (eqi(text, "cv")) return .cv;
    if (eqi(text, "stderr") or eqi(text, "stdmean")) return .stderr;
    if (eqi(text, "range")) return .range;
    // BUG-meanspctlmore: the rest of SAS's percentile keyword set + qrange/mode/css/uss
    if (eqi(text, "p1")) return .p1;
    if (eqi(text, "p5")) return .p5;
    if (eqi(text, "p10")) return .p10;
    // GAP-meanspctlkeywords: P20–P80, documented at printed pp.1491–1492 (MEANS),
    // p.1504 (MEANS OUTPUT), p.2178 (REPORT), p.2556 (TABULATE). NOT in
    // UNIVARIATE's OUTPUT table (Table 4.14, printed p.354) — see
    // univariateRejectsStatKw.
    if (eqi(text, "p20")) return .p20;
    if (eqi(text, "p30")) return .p30;
    if (eqi(text, "p40")) return .p40;
    if (eqi(text, "p60")) return .p60;
    if (eqi(text, "p70")) return .p70;
    if (eqi(text, "p80")) return .p80;
    if (eqi(text, "p90")) return .p90;
    if (eqi(text, "p95")) return .p95;
    if (eqi(text, "p99")) return .p99;
    if (eqi(text, "qrange")) return .qrange;
    if (eqi(text, "mode")) return .mode;
    if (eqi(text, "css")) return .css;
    if (eqi(text, "uss")) return .uss;
    // MEANS-cistat: t-test / confidence-limit stats. `clm` is handled upstream
    // (expands to lclm+uclm, two columns); the rest are single columns.
    if (eqi(text, "lclm")) return .lclm;
    if (eqi(text, "uclm")) return .uclm;
    if (eqi(text, "t")) return .t;
    // PRT is a documented ALIAS of PROBT everywhere in the MEANS family — the
    // hypothesis-testing keyword line reads "PROBT | PRT   T" in the PROC MEANS
    // statement (printed p.1492), REPORT (p.2178) and TABULATE (p.2556). It was
    // absent here, so `proc means prt` hit the warn-and-ignore arm and dropped the
    // column (GAP-meanspctlkeywords). NOT accepted by UNIVARIATE's OUTPUT — see
    // univariateRejectsStatKw.
    if (eqi(text, "probt") or eqi(text, "prt")) return .probt;
    // GAP-meansskewkurt: SKEWNESS/KURTOSIS (SAS abbreviations SKEW/KURT).
    if (eqi(text, "skewness") or eqi(text, "skew")) return .skewness;
    if (eqi(text, "kurtosis") or eqi(text, "kurt")) return .kurtosis;
    return null; // MAXDEC=, etc. → not a column we render
}

/// Statistic SPELLINGS the MEANS family accepts that UNIVARIATE's OUTPUT statement
/// does NOT (GAP-meanspctlkeywords). statFromKw is shared by MEANS, MEANS OUTPUT,
/// TABULATE, REPORT and UNIVARIATE OUTPUT, but the doc does NOT give them one
/// keyword set: UNIVARIATE's own OUTPUT keyword table (Table 4.14, Statistical
/// Procedures printed p.354) lists PROBT with NO PRT alias — and it does spell
/// aliases out elsewhere in the same table ("KURTOSIS | KURT", "Q1 | P25"), so the
/// omission is meaningful. The MEANS family carries the wider set: "PROBT | PRT"
/// at printed p.1492 (MEANS), p.2178 (REPORT), p.2556 (TABULATE).
///
/// Matching on TEXT rather than StatKind is not a shortcut — it is required. PRT
/// decodes to .probt, which UNIVARIATE *does* support, so the alias is invisible
/// once decoded and only the spelling can tell `prt=` from `probt=`.
///
/// This guard is STATUS-QUO-PRESERVING for UNIVARIATE: every spelling listed here
/// already failed loud there (none of them decoded at all), so widening the MEANS
/// family cannot regress UNIVARIATE.
fn univariateRejectsStatKw(text: []const u8) bool {
    return eqi(text, "prt") or
        eqi(text, "p20") or eqi(text, "p30") or eqi(text, "p40") or
        eqi(text, "p60") or eqi(text, "p70") or eqi(text, "p80");
}

/// Bare-name PROC MEANS/SUMMARY options that carry no `=` and are not statistics,
/// so they must not trip the unrecognized-keyword warning (BUG-meanspctlmore).
fn isMeansOptionFlag(kw: []const u8) bool {
    // DESCENDING/COMPLETETYPES were dropped from this whitelist (BUG-meansoptnoop):
    // DESCENDING is implemented, COMPLETETYPES fails loud — both handled upstream.
    // THREADS/NOTHREADS (GAP-procopts): SAS 9.4 PROC MEANS statement doc —
    // parallelization toggles; opensas's aggregation is single-threaded and
    // result-identical either way → genuinely inert, so no warning.
    inline for (.{ "missing", "nonobs", "noprint", "nway", "print", "chartype", "exclnpwgt", "threads", "nothreads" }) |o| {
        if (eqi(kw, o)) return true;
    }
    return false;
}

/// Documented bare-name PROC MEANS/SUMMARY flags opensas does NOT honour —
/// the doc-truth arm of the bare-keyword warning (BUG-meansflagmsg). The
/// catch-all warn called these "not recognized", a false statement about
/// options the Summary of Optional Arguments itself enumerates as bare flags
/// (printed pp. 1482-1484, === pdf 1531/1532/1533 ===). Message-only: still
/// warns and continues (rc 0), now naming an option we know and skip rather
/// than a keyword we don't.
fn isMeansDocFlag(kw: []const u8) bool {
    inline for (.{ "printalltypes", "printidvars", "stackodsoutput", "descendtypes", "idmin", "exclusive", "notrap" }) |o|
        if (eqi(kw, o)) return true;
    return false;
}

/// Documented SAS 9.4 PROC MEANS `name = value` options opensas does NOT
/// implement — the catch-all's gap arm (rc 2); anything else landing there is
/// the user's typo (rc 1). The set is CLOSED: the PROC MEANS statement's
/// "Summary of Optional Arguments" (Base SAS 9.4 Procedures Guide, 7th ed.,
/// printed pp. 1482-1484, === pdf 1531/1532/1533 ===) enumerates every
/// option in one place, and the rest of that list is already handled upstream
/// (DATA=/VARDEF=/MAXDEC=/ALPHA=/ORDER=/SUMSIZE=) or is a bare flag this arm
/// never sees (audit-exitcodecontract.md §5b re-verdict).
fn isMeansGapOption(kw: []const u8) bool {
    inline for (.{ "fw", "qmethod", "qntldf", "qmarkers", "classdata", "incas" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// The two valid-in-MEANS statements opensas doesn't implement — ATTRIB and
/// LABEL, named by the Syntax section's own Tip ("You can use the ATTRIB,
/// FORMAT, LABEL, and WHERE statements", printed p. 1481, === pdf 1530 ===);
/// every other statement the section lists is handled. Gap arm of the
/// statement catch-all (rc 2); a typo'd keyword stays rc 1.
fn isMeansGapStmt(kw: []const u8) bool {
    return eqi(kw, "attrib") or eqi(kw, "label");
}

/// Documented PROC MEANS OUTPUT `/` options opensas doesn't implement — the
/// OUTPUT statement dictionary closes the set (printed pp. 1503-1511,
/// === pdf 1552…1560 ===): OUT=/AUTONAME are handled, leaving AUTOLABEL,
/// KEEPLEN, LEVELS, NOINHERIT, WAYS. Gap arm (rc 2); a typo stays rc 1.
fn isMeansOutGapOption(kw: []const u8) bool {
    inline for (.{ "autolabel", "keeplen", "levels", "noinherit", "ways" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

fn statHeader(k: StatKind) []const u8 {
    return switch (k) {
        .n => "N",
        .mean => "Mean",
        .std => "Std Dev",
        .min => "Minimum",
        .max => "Maximum",
        .sum => "Sum",
        // ponytail: the doc's own DESCRIPTION text ("Sum of weights", Table 2.1
        // printed p.70; "SUMWGT is the sum of the weights" p.2745). SAS's actual
        // listing abbreviation for this column is printed in NONE of the nine
        // acquired volumes — there is no worked example with a SUMWGT column — so
        // this label is doc-described rather than doc-quoted. Swap it if a printed
        // weighted-MEANS listing ever turns up. Same standing as the neighbouring
        // "Coeff of Variation"/"Lower Quartile", which are also absent from the docs.
        .sumwgt => "Sum of Weights",
        .nmiss => "N Miss",
        .median => "Median",
        .q1 => "Lower Quartile",
        .q3 => "Upper Quartile",
        .var_ => "Variance",
        .cv => "Coeff of Variation",
        .stderr => "Std Error",
        .range => "Range",
        .p1 => "1st Pctl",
        .p5 => "5th Pctl",
        .p10 => "10th Pctl",
        .p20 => "20th Pctl",
        .p30 => "30th Pctl",
        .p40 => "40th Pctl",
        .p60 => "60th Pctl",
        .p70 => "70th Pctl",
        .p80 => "80th Pctl",
        .p90 => "90th Pctl",
        .p95 => "95th Pctl",
        .p99 => "99th Pctl",
        .qrange => "Quartile Range",
        .mode => "Mode",
        .css => "Corrected SS",
        .uss => "Uncorrected SS",
        .lclm => "Lower 95% CL for Mean",
        .uclm => "Upper 95% CL for Mean",
        .t => "t Value",
        .probt => "Pr > |t|",
        .skewness => "Skewness",
        .kurtosis => "Kurtosis",
    };
}

/// CLM confidence-percent text for the column header: 100·(1−ALPHA) with no
/// trailing zeros — "95" for the 0.05 default, "90" for ALPHA=0.1 (BUG-meansoptnoop).
fn clmPct(arena: std.mem.Allocator, alpha: f64) ![]const u8 {
    const p = 100.0 * (1.0 - alpha);
    return if (p == @trunc(p))
        try std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(p))})
    else
        try std.fmt.allocPrint(arena, "{d}", .{p});
}

/// statHeader with the ALPHA-aware CLM labels (BUG-meansoptnoop): ALPHA=0.1
/// labels the CLM columns "Lower 90% CL for Mean" / "Upper 90% CL for Mean".
fn statHeaderA(arena: std.mem.Allocator, k: StatKind, alpha: f64) ![]const u8 {
    if (k == .lclm) return try std.fmt.allocPrint(arena, "Lower {s}% CL for Mean", .{try clmPct(arena, alpha)});
    if (k == .uclm) return try std.fmt.allocPrint(arena, "Upper {s}% CL for Mean", .{try clmPct(arena, alpha)});
    return statHeader(k);
}

/// Column width per statistic in the combined table: counts are narrow, the
/// decimal stats use the 16.7 field. ponytail: widths tuned to the SAS listing
/// the corpus pins (proc_means_var); a value wider than the field is not re-fit.
/// `hdr` is the (ALPHA-aware) header text — a longer label widens the column.
fn statWidth(k: StatKind, hdr: []const u8) usize {
    return switch (k) {
        .n, .nmiss => 6,
        else => @max(16, hdr.len + 1), // widen for long headers (CV=18) + a 1-col gap
    };
}

/// Width of a statistic's column in the single-var "Analysis Variable" block
/// (N is wider here than in the combined table).
fn blockWidth(k: StatKind, hdr: []const u8) usize {
    return switch (k) {
        .n, .nmiss => 12,
        else => @max(16, hdr.len + 1),
    };
}

fn statValue(k: StatKind, s: Stats) f64 {
    return switch (k) {
        .n => @floatFromInt(s.n),
        .mean => s.mean,
        .std => s.std,
        .min => s.min,
        .max => s.max,
        .sum => s.sum,
        .sumwgt => s.sumw, // Σwᵢ (== n unweighted); 0, not missing, at n==0 (NOTE-univallmiss)
        .median => s.median,
        .q1 => s.q1,
        .q3 => s.q3,
        .var_ => s.std * s.std, // variance = Std² (weighted when WEIGHT is set)
        .cv => 100.0 * s.std / s.mean, // coefficient of variation, percent
        .stderr => s.std / @sqrt(s.sumw), // standard error of the mean: √(s²/Σw) (Σw==n unweighted)
        .range => s.max - s.min,
        .p1 => s.p1,
        .p5 => s.p5,
        .p10 => s.p10,
        .p20 => s.p20,
        .p30 => s.p30,
        .p40 => s.p40,
        .p60 => s.p60,
        .p70 => s.p70,
        .p80 => s.p80,
        .p90 => s.p90,
        .p95 => s.p95,
        .p99 => s.p99,
        .qrange => s.q3 - s.q1, // inter-quartile range
        .mode => s.mode,
        .css => s.css, // Σ w(x−mean)²
        .uss => s.uss, // Σ w·x²
        .skewness => s.skew, // g1 sample skewness (missing if n<3, sd=0, or VARDEF≠DF)
        .kurtosis => s.kurt, // g2 sample kurtosis (missing if n<4, sd=0, or VARDEF≠DF)
        .nmiss => std.math.nan(f64), // filled by the caller (needs the row total)
        // MEANS-cistat: t-test / 95% CI of the mean (df = n−1). Undefined for n<2.
        .t, .probt, .lclm, .uclm => blk: {
            if (s.n < 2) break :blk std.math.nan(f64);
            const nf: f64 = @floatFromInt(s.n);
            const df = nf - 1; // df stays n−1 even weighted
            const se = s.std / @sqrt(s.sumw); // √(s²/Σw)
            switch (k) {
                .t => break :blk s.mean / se,
                .probt => break :blk 2.0 * (1.0 - studentTcdf(@abs(s.mean / se), df)),
                .lclm => break :blk s.mean - tQuantile(0.975, df) * se,
                .uclm => break :blk s.mean + tQuantile(0.975, df) * se,
                else => unreachable,
            }
        },
    };
}

/// statValue with ALPHA-aware CLM limits (BUG-meansoptnoop): mean ± t(1−α/2, n−1)·SE.
/// alpha == 0.05 (the default) reproduces statValue's hard-coded 95% exactly.
fn statValueA(k: StatKind, s: Stats, alpha: f64) f64 {
    if (k != .lclm and k != .uclm) return statValue(k, s);
    if (s.n < 2) return std.math.nan(f64);
    const df = @as(f64, @floatFromInt(s.n)) - 1; // df stays n−1 even weighted
    const se = s.std / @sqrt(s.sumw);
    const q = tQuantile(1.0 - alpha / 2.0, df);
    return if (k == .lclm) s.mean - q * se else s.mean + q * se;
}

// ── Student-t distribution (MEANS-cistat) ────────────────────────────────────
// A compact CDF via the regularized incomplete beta function (Numerical Recipes
// betacf/betai) plus a bisection inverse — enough for PROC MEANS CLM/T/PROBT.
// ponytail: kept local to proc.zig rather than exposing functions.zig internals;
// ~1e-10 accurate, which the corpus fixtures (tinv 0.975,df=n−1) confirm.

fn lgamma(x: f64) f64 {
    return std.math.lgamma(f64, x);
}

/// Regularized incomplete beta I_x(a,b).
fn betai(a: f64, b: f64, x: f64) f64 {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const bt = @exp(lgamma(a + b) - lgamma(a) - lgamma(b) + a * @log(x) + b * @log(1 - x));
    if (x < (a + 1) / (a + b + 2)) return bt * betacf(a, b, x) / a;
    return 1 - bt * betacf(b, a, 1 - x) / b;
}

fn betacf(a: f64, b: f64, x: f64) f64 {
    const eps = 3.0e-14;
    const fpmin = 1.0e-300;
    const qab = a + b;
    const qap = a + 1;
    const qam = a - 1;
    var c: f64 = 1;
    var d: f64 = 1 - qab * x / qap;
    if (@abs(d) < fpmin) d = fpmin;
    d = 1 / d;
    var h = d;
    var m: usize = 1;
    while (m <= 200) : (m += 1) {
        const mf: f64 = @floatFromInt(m);
        const m2 = 2 * mf;
        var aa = mf * (b - mf) * x / ((qam + m2) * (a + m2));
        d = 1 + aa * d;
        if (@abs(d) < fpmin) d = fpmin;
        c = 1 + aa / c;
        if (@abs(c) < fpmin) c = fpmin;
        d = 1 / d;
        h *= d * c;
        aa = -(a + mf) * (qab + mf) * x / ((a + m2) * (qap + m2));
        d = 1 + aa * d;
        if (@abs(d) < fpmin) d = fpmin;
        c = 1 + aa / c;
        if (@abs(c) < fpmin) c = fpmin;
        d = 1 / d;
        const del = d * c;
        h *= del;
        if (@abs(del - 1) < eps) break;
    }
    return h;
}

/// P(T ≤ tv) for Student-t with `df` degrees of freedom.
fn studentTcdf(tv: f64, df: f64) f64 {
    const x = df / (df + tv * tv);
    const ib = 0.5 * betai(df / 2.0, 0.5, x);
    return if (tv >= 0) 1 - ib else ib;
}

/// Inverse Student-t: the value q with studentTcdf(q, df) = p (0<p<1). Bisection.
fn tQuantile(p: f64, df: f64) f64 {
    var lo: f64 = -1e6;
    var hi: f64 = 1e6;
    var it: usize = 0;
    while (it < 200) : (it += 1) {
        const mid = (lo + hi) / 2;
        if (studentTcdf(mid, df) < p) lo = mid else hi = mid;
        if (hi - lo < 1e-11) break;
    }
    return (lo + hi) / 2;
}

/// Emit one TYPES crossing term: the cartesian product of its factors' names
/// (a paren group is ONE factor, so `(a b)` alone expands to the singles a and
/// b, and `(a b)*(c d)` to a*c a*d b*c b*d). `()` alone is the overall
/// (_TYPE_=0) table; an empty factor mixed into a crossing (`()*a`) is not a
/// valid request — fail loud, never guess.
fn flushTypesTerm(arena: std.mem.Allocator, diags: *diag.Diagnostics, line_no: usize, factors: *std.ArrayList([]const []const u8), combos: *std.ArrayList([]const []const u8)) diag.Error!void {
    defer factors.clearRetainingCapacity();
    if (factors.items.len == 0) return;
    var acc: std.ArrayList([]const []const u8) = .empty;
    try acc.append(arena, &.{});
    for (factors.items) |f| {
        if (f.len == 0) {
            if (factors.items.len > 1)
                return diags.fail(error.ParseError, line_no, "PROC MEANS: unsupported TYPES syntax", .{});
            try combos.append(arena, &.{}); // `()` = overall (_TYPE_=0)
            return;
        }
        var next: std.ArrayList([]const []const u8) = .empty;
        for (acc.items) |partial| for (f) |nm| {
            const combo = try arena.alloc([]const u8, partial.len + 1);
            @memcpy(combo[0..partial.len], partial);
            combo[partial.len] = nm;
            try next.append(arena, combo);
        };
        acc = next;
    }
    for (acc.items) |combo| try combos.append(arena, combo);
}

/// Parse a TYPES statement body (BUG-meanstypescross): `i` just past `types`,
/// left at the `;`. Each request is a crossing term — factors joined by `*`,
/// a factor being one class-var name or a parenthesized name group — expanded
/// per the doc (Base SAS 9.4 Procedures Guide, 7th ed., printed p. 1512:
/// `types (A B)*(C D);` = `types A*C A*D B*C B*D;`, `types A*(B C);` =
/// `types A*B A*C;`; `()` requests the overall total). The loop this replaces
/// treated ANY `(` as the overall combo and any name-after-name as a new
/// combo, so `(a b)*(c d)` silently emitted spurious _TYPE_=0 tables plus
/// unrequested singles — valid SAS, wrong output (the silent-wrong class).
fn parseTypesReqs(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, i: *usize, combos: *std.ArrayList([]const []const u8)) diag.Error!void {
    var factors: std.ArrayList([]const []const u8) = .empty; // the open term's factors
    var closed = false; // a factor just closed — only `*` may continue the term
    while (i.* < toks.len and toks[i.*].tag != .semicolon) {
        const tk = toks[i.*];
        switch (tk.tag) {
            .name => {
                if (closed) try flushTypesTerm(arena, diags, tk.line, &factors, combos); // name after a closed factor: next request
                try factors.append(arena, try arena.dupe([]const u8, &.{tk.text}));
                closed = true;
            },
            .lparen => {
                if (closed) try flushTypesTerm(arena, diags, tk.line, &factors, combos);
                i.* += 1;
                var group: std.ArrayList([]const u8) = .empty;
                while (i.* < toks.len and toks[i.*].tag == .name) : (i.* += 1)
                    try group.append(arena, toks[i.*].text);
                if (i.* >= toks.len or toks[i.*].tag != .rparen)
                    return diags.fail(error.ParseError, tk.line, "PROC MEANS: unsupported TYPES syntax", .{});
                try factors.append(arena, group.items); // empty group = `()`
                closed = true;
            },
            .star => {
                if (!closed) // `*` with no left factor (`*a`, `a**b`)
                    return diags.fail(error.ParseError, tk.line, "PROC MEANS: unsupported TYPES syntax", .{});
                closed = false;
            },
            .comma => {},
            else => return diags.fail(error.ParseError, tk.line, "PROC MEANS: unsupported TYPES syntax", .{}),
        }
        i.* += 1;
    }
    if (!closed and factors.items.len > 0) // trailing `*`
        return diags.fail(error.ParseError, if (i.* > 0) toks[i.* - 1].line else 0, "PROC MEANS: unsupported TYPES syntax", .{});
    try flushTypesTerm(arena, diags, 0, &factors, combos);
}

pub fn runMeans(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    // ── header: `proc means data=NAME [NOPRINT] <stat-keywords>;`
    var in_name: ?[]const u8 = null;
    var stats: std.ArrayList(StatKind) = .empty;
    // SUMMARY inverts MEANS' default: silent unless PRINT given (BUG-summarydefaultprint).
    const is_summary = eqi(toks[1].text, "summary");
    const title: []const u8 = if (is_summary) SUMMARY_TITLE else MEANS_TITLE;
    var noprint = is_summary;
    var nway = false; // NWAY: keep only the finest _TYPE_, drop the overall row
    var vardef: VarDef = .df; // VARDEF= variance divisor (BUG-statvardef)
    var missing_opt = false; // MISSING: re-include obs with a missing CLASS value (BUG-meansclassmiss)
    var exclnpwgt = false; // EXCLNPWGT: also drop nonpositive-weight obs (BUG-meanszeroweight)
    var maxdec: ?u8 = null; // MAXDEC=n: decimals shown for the stat columns (GAP-meansmaxdec)
    var alpha: f64 = 0.05; // ALPHA=p: the CLM confidence level is (1−p)·100% (BUG-meansoptnoop)
    var descending = false; // DESCENDING: reverse the CLASS level order (BUG-meansoptnoop)
    var class_order: GroupOrder = .internal; // ORDER=INTERNAL|DATA|FREQ (BUG-meansoptnoop)
    var i: usize = 2; // past `proc means`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "vardef")) |v| {
            // VARDEF= selects the variance divisor (BUG-statvardef) — fail loud
            // on a bad value rather than silently defaulting to DF.
            vardef = varDefFromName(v) orelse
                return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: VARDEF={s} is not valid — expected DF, N, WDF, or WEIGHT", .{v});
            i += 3;
        } else if (i + 2 < toks.len and tkKw(toks[i], "maxdec") and
            toks[i + 1].tag == .eq and toks[i + 2].tag == .number)
        {
            // MAXDEC=n — decimals for the printed stats (GAP-meansmaxdec). SAS range 0–8.
            maxdec = std.fmt.parseInt(u8, toks[i + 2].text, 10) catch null;
            if (maxdec == null or maxdec.? > 8)
                return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: MAXDEC={s} is not valid — expected 0 to 8", .{toks[i + 2].text});
            i += 3;
        } else if (tkKw(toks[i], "alpha") and i + 2 < toks.len and toks[i + 1].tag == .eq) {
            // ALPHA=p — confidence level for CLM is (1−p)·100% (BUG-meansoptnoop). SAS: 0<p<1.
            const a = if (toks[i + 2].tag == .number) std.fmt.parseFloat(f64, toks[i + 2].text) catch -1 else -1;
            if (!(a > 0 and a < 1))
                return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: ALPHA={s} is not valid — expected a value between 0 and 1", .{toks[i + 2].text});
            alpha = a;
            i += 3;
        } else if (tkKw(toks[i], "order") and i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
            // ORDER=INTERNAL|DATA|FREQ — the CLASS level order (BUG-meansoptnoop).
            const v = toks[i + 2].text;
            if (eqi(v, "internal")) class_order = .internal //
            else if (eqi(v, "data")) class_order = .data //
            else if (eqi(v, "freq")) class_order = .freq //
            else if (eqi(v, "formatted") or eqi(v, "external"))
                // ORDER=FORMATTED/EXTERNAL are valid SAS 9.4 — a gap (rc 2);
                // the else below is the typo arm and stays the user's rc 1.
                return failGap(diags, toks[i].line, "PROC MEANS: ORDER={s} is not supported yet", .{v})
            else
                return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: ORDER={s} is not valid — expected INTERNAL, DATA, or FREQ", .{v});
            i += 3;
        } else if (toks[i].tag == .lparen) {
            // data=d(keep=/where=…) dataset options — applied via procInput.
            // Must be SKIPPED as a group: the old walk-through read `keep`
            // inside the parens as a stat keyword and even WARNED
            // "statistic-keyword keep is not recognized" on legal input —
            // and with the fail-loud arm below it would error outright.
            i = skipParen(toks, i);
        } else {
            if (toks[i].tag == .name) {
                const kw = toks[i].text;
                // An `opt = value` form (maxdec=, alpha=, order=…) is an option,
                // not a statistic. A bare unrecognized keyword is a stat request we
                // can't honor: WARN rather than silently defaulting to
                // N/Mean/Std/Min/Max (fail-loud, BUG-meanspctlmore).
                const is_opt = atTag(toks, i + 1, .eq);
                if (eqi(kw, "noprint")) noprint = true // suppress the listing
                else if (eqi(kw, "print")) noprint = false // SUMMARY: PRINT asks for the listing
                else if (eqi(kw, "nway")) nway = true
                else if (eqi(kw, "missing")) missing_opt = true // keep missing CLASS levels
                else if (eqi(kw, "exclnpwgt")) exclnpwgt = true // also exclude ≤0-weight obs
                else if (eqi(kw, "descending")) descending = true // reverse the CLASS level order
                else if (eqi(kw, "completetypes")) // absent CLASS combos are not wired (BUG-meansoptnoop)
                    // a named, valid SAS 9.4 option → gap (rc 2), never a typo arm
                    return failGap(diags, toks[i].line, "PROC MEANS: COMPLETETYPES is not supported yet", .{})
                else if (eqi(kw, "clm")) { // two-sided CI → two columns (MEANS-cistat)
                    try stats.append(arena, .lclm);
                    try stats.append(arena, .uclm);
                } else if (statFromKw(kw)) |sk| try stats.append(arena, sk)
                else if (is_opt) {
                    // SUMSIZE= is a memory-allowance tuning knob (SAS 9.4 PROC
                    // MEANS statement doc) — opensas's aggregation has no memory
                    // budget to tune → genuinely inert. Every OTHER `name = value`
                    // here is UNKNOWN: a typo (`maxddec=2` — MAXDEC= silently
                    // unapplied) or a real option nobody honours (FW=, IDMIN,
                    // QMETHOD= — percentile-method, result-changing). PROC PRINT
                    // failed loud on this exact class while MEANS silently
                    // skipped it (GAP-procopts internal inconsistency, D-002) —
                    // converge on loud, naming the option.
                    if (eqi(kw, "sumsize")) {
                        i += 3;
                        continue;
                    }
                    // SPLIT (the 342b8305 shape): a name in the doc's closed
                    // PROC MEANS option set is a recognized gap (rc 2); any
                    // other name (`maxddec=2`) is the user's typo (rc 1) —
                    // same message body, only the rc signal differs.
                    if (isMeansGapOption(kw))
                        return failGap(diags, toks[i].line, "PROC MEANS: option {s} is not supported", .{kw});
                    return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: option {s} is not supported", .{kw});
                } else if (isMeansDocFlag(kw))
                    diags.warn(toks[i].line, "PROC MEANS: option {s} is not supported and is ignored", .{kw}) catch {}
                else if (!isMeansOptionFlag(kw))
                    diags.warn(toks[i].line, "statistic-keyword {s} is not recognized and is ignored", .{kw}) catch {};
            }
            i += 1;
        }
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    // ── sub-statements: `var`, `by`, `class`, `output out=…`, up to `run;`
    var vars: std.ArrayList([]const u8) = .empty;
    var bys: std.ArrayList([]const u8) = .empty;
    var classes: std.ArrayList([]const u8) = .empty;
    var weight_var: ?[]const u8 = null; // `weight w;` — weighted stats (BUG-meansweight)
    var freq_var: ?[]const u8 = null; // `freq f;` — each obs counts f times (BUG-meansfreqstmt)
    var fmt_specs: std.ArrayList(VarSpec) = .empty; // `format v spec;` — CLASS groups by formatted value (NOTE-freqtablesfmt)
    // One record PER OUTPUT statement — each builds its OWN dataset with its
    // OWN stat list (BUG-meansoutmultistmt); SAS never merges two OUTPUT statements.
    var out_stmts: std.ArrayList(OutStmt) = .empty;
    var id_names: std.ArrayList([]const u8) = .empty; // `id v …;` vars carried into OUTPUT (BUG-meansidnoop)
    var type_combos: std.ArrayList([]const []const u8) = .empty; // TYPES class-name combos (BUG-meanstypes)
    var ways_degs: std.ArrayList(usize) = .empty; // WAYS combination degrees (BUG-meansways)
    var types_seen = false;
    var ways_seen = false;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run")) break;
        if (tkKw(toks[i], "var")) {
            i += 1;
            // A repeated VAR statement REPLACES the prior list — SAS last-wins
            // (BUG-meansstmtreplace); the old append kept both → extra analysis vars.
            vars.clearRetainingCapacity();
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try appendVarListName(arena, toks, &i, &vars); // GAP-varcolonprefix-procs: keep `pfx:`
        } else if (tkKw(toks[i], "by")) {
            bys.clearRetainingCapacity(); // repeated BY replaces (BUG-meansstmtreplace)
            try parseProcBy(arena, diags, toks, &i, &bys);
        } else if (tkKw(toks[i], "class")) {
            i += 1;
            classes.clearRetainingCapacity(); // repeated CLASS replaces (BUG-meansstmtreplace)
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .slash) {
                    // `class v / missing …` — the MISSING option re-includes the
                    // missing CLASS level (BUG-meansclassmiss); other options ignored.
                    while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                        if (toks[i].tag == .name and eqi(toks[i].text, "missing")) missing_opt = true;
                    }
                    break;
                }
                if (toks[i].tag == .name) try appendVarListName(arena, toks, &i, &classes); // GAP-varcolonprefix-procs: keep `pfx:`
            }
        } else if (tkKw(toks[i], "weight")) {
            i += 1; // `weight w;` — the (single) weight variable
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) weight_var = toks[i].text;
            }
        } else if (tkKw(toks[i], "freq")) {
            i += 1; // `freq f;` — the frequency-count variable (BUG-meansfreqstmt)
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) freq_var = toks[i].text;
            }
        } else if (tkKw(toks[i], "id")) {
            i += 1; // `id v …;` — carry each id var's within-group MAX into OUTPUT (BUG-meansidnoop)
            id_names.clearRetainingCapacity(); // repeated ID replaces (BUG-meansstmtreplace)
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try appendVarListName(arena, toks, &i, &id_names); // GAP-varcolonprefix-procs: keep `pfx:`
        } else if (tkKw(toks[i], "output")) {
            // `output out=NAME  stat [(varlist)] = name1 name2 … ;` — one output col
            // per name, each mapping to its own analysis var (BUG-meansoutmulti).
            i += 1;
            var oname: ?[]const u8 = null;
            var oautoname = false; // `/ autoname` — name omitted stats var_Stat (BUG-meansautoname)
            var ogroups: std.ArrayList(OutGroup) = .empty; // raw specs, resolved after acols
            var oopts: []const Token = &.{}; // `out=NAME(keep=/…)` option tokens
            while (i < toks.len and toks[i].tag != .semicolon) {
                if (tkKw(toks[i], "out") and i + 2 < toks.len and toks[i + 1].tag == .eq) {
                    oname = toks[i + 2].text;
                    i += 3;
                    if (atTag(toks, i, .lparen)) {
                        // `out=NAME(keep=/drop=/…)` — applied post-build via oopts;
                        // skip the parens here so option names aren't misread as
                        // stat keywords (po_means_out_keep).
                        const start = i + 1;
                        var depth: usize = 1;
                        i += 1;
                        while (i < toks.len) : (i += 1) {
                            if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                                depth -= 1;
                                if (depth == 0) break;
                            }
                        }
                        oopts = if (i < toks.len) toks[start..i] else &.{};
                        if (i < toks.len) i += 1; // past ')'
                    }
                } else if (toks[i].tag == .slash) {
                    // `/ autoname` — omitted stat names become var_Stat (BUG-meansautoname).
                    i += 1;
                    while (i < toks.len and toks[i].tag == .name and
                        statFromKw(toks[i].text) == null and !tkKw(toks[i], "out")) : (i += 1)
                    {
                        if (eqi(toks[i].text, "autoname")) oautoname = true //
                        else if (isMeansOutGapOption(toks[i].text))
                            // a documented OUTPUT option we don't honor — gap (rc 2)
                            return failGap(diags, toks[i].line, "PROC MEANS: OUTPUT / {s} is not yet supported", .{toks[i].text})
                        else return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: OUTPUT / {s} is not yet supported", .{toks[i].text});
                    }
                } else if (toks[i].tag == .name) {
                    if (statFromKw(toks[i].text)) |sk| {
                        i += 1;
                        var evars: std.ArrayList([]const u8) = .empty; // `(v1 v2)` explicit vars
                        if (atTag(toks, i, .lparen)) {
                            i += 1;
                            while (i < toks.len and toks[i].tag != .rparen) : (i += 1)
                                if (toks[i].tag == .name) try evars.append(arena, toks[i].text);
                            if (i < toks.len) i += 1; // past ')'
                        }
                        if (atTag(toks, i, .eq)) i += 1; // past '='
                        var names: std.ArrayList([]const u8) = .empty;
                        while (atTag(toks, i, .name)) {
                            // a stat-keyword followed by `=`/`(` starts the NEXT spec
                            if (statFromKw(toks[i].text) != null and i + 1 < toks.len and
                                (toks[i + 1].tag == .eq or toks[i + 1].tag == .lparen)) break;
                            try names.append(arena, toks[i].text);
                            i += 1;
                        }
                        try ogroups.append(arena, .{ .stat = sk, .evars = evars.items, .names = names.items });
                    } else if (tkKw(toks[i], "out")) {
                        i += 1; // a bare `out` without `=` — lenient skip, as before
                    } else {
                        // An unrecognized stat keyword was silently DROPPED, and an
                        // all-invalid spec list then fell through to the default
                        // long form — SAS errors instead (BUG-meansoutmultistmt).
                        return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: OUTPUT statistic-keyword {s} is not recognized", .{toks[i].text});
                    }
                } else i += 1;
            }
            try out_stmts.append(arena, .{ .name = oname, .autoname = oautoname, .groups = ogroups, .stats = .empty, .opts = oopts });
        } else if (tkKw(toks[i], "types")) {
            // `types () a a*b (a b)*(c d) …;` — the requested _TYPE_ combos
            // (BUG-meanstypes); paren-group crossing expands per the doc
            // (BUG-meanstypescross).
            types_seen = true;
            i += 1;
            try parseTypesReqs(arena, diags, toks, &i, &type_combos);
        } else if (tkKw(toks[i], "ways")) {
            // `ways 1 …;` — every combination of the named degree(s) (BUG-meansways).
            ways_seen = true;
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                switch (toks[i].tag) {
                    .number => {
                        const k = std.fmt.parseInt(usize, toks[i].text, 10) catch
                            return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: invalid WAYS value {s}", .{toks[i].text});
                        try ways_degs.append(arena, k);
                    },
                    .comma => {},
                    else => return diags.fail(error.ParseError, toks[i].line, "PROC MEANS: unsupported WAYS syntax", .{}),
                }
            }
        } else if (tkKw(toks[i], "format")) {
            try parseProcFormat(arena, toks, &i, &fmt_specs); // leaves i at the `;`
        } else if (tkKw(toks[i], "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1; // procInput applies it
        } else if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            // D-014a mid-step globals: skip exactly what the top level HANDLES
            // mid-step (see runSort's arm for the full note).
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (toks[i].tag == .name) {
            // D-002 fail-loud (GAP-procsubstmtswallow): an unknown sub-statement
            // used to vanish via `else i += 1` while PRINT/TRANSPOSE/SQL error.
            // SPLIT: ATTRIB/LABEL are valid-in-MEANS (rc 2); a typo stays rc 1.
            if (isMeansGapStmt(toks[i].text))
                return failGap(diags, toks[i].line, "PROC MEANS statement {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC MEANS statement {s} is not supported", .{toks[i].text});
        } else i += 1;
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC MEANS: no input dataset");
        return;
    };
    var ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)

    // GAP-varcolonprefix-procs: expand `pfx:` entries now that the dataset is
    // known (PDV order — see expandVarPrefixes). ONE point, ahead of every
    // ds.indexOf consumer below (groupFormats' CLASS scan included); a prefix
    // matching nothing is a loud rc 1 here, never a silently absent variable.
    try expandVarListPrefixes(arena, ds, &vars, diags, toks[0].line, "PROC MEANS");
    try expandVarListPrefixes(arena, ds, &classes, diags, toks[0].line, "PROC MEANS");
    try expandVarListPrefixes(arena, ds, &id_names, diags, toks[0].line, "PROC MEANS");

    // FREQ f: each obs counts trunc(f) times (missing/<1 → dropped). Expand the
    // rows once so every path (listing, CLASS, OUTPUT, _FREQ_) sees the
    // effective sample (BUG-meansfreqstmt).
    if (freq_var) |fv| {
        const fcol = ds.indexOf(fv) orelse
            return diags.fail(error.ParseError, 0, "PROC MEANS: FREQ variable {s} not in {s}", .{ fv, ds.name });
        ds = try expandFreq(arena, diags, ds, fcol);
    }

    // WEIGHT column: Mean/Sum/Std/Var become weighted (BUG-meansweight). A
    // named-but-absent weight var errors (BUG-weightvarcheck).
    const wcol: ?usize = try resolveWeightCol(ds, weight_var, diags, toks[0].line);

    // EXCLNPWGT: drop nonpositive-weight obs from the WHOLE analysis (the opt-in
    // that overrides the default of counting ≤0-weight obs in N / MIN/MAX). Done
    // once here so every path — listing, CLASS, OUTPUT, _FREQ_ — sees the reduced
    // sample; the default (no EXCLNPWGT) keeps them via weightAt (BUG-meanszeroweight).
    if (exclnpwgt) if (wcol) |wc| {
        ds = try dropNonpositiveWeight(arena, ds, wc);
    };

    // FORMAT on a CLASS var → group + display by the formatted value
    // (NOTE-freqtablesfmt, tick167:176). Before the default analysis-var scan
    // so a formatted numeric CLASS var drops out of it (SAS excludes CLASS
    // vars from the default VAR set); an explicit VAR naming that same var is
    // the ponytail edge noted at groupFormats.
    var fmt_levels: std.ArrayList(FmtLevels) = .empty; // raw-value order per format-grouped CLASS col (BUG-freqfmtorder)
    if (classes.items.len > 0) ds = try groupFormats(arena, ds, classes.items, fmt_specs.items, &fmt_levels, diags);

    // BY: decode scanByList's wire encoding ONCE — clean names for every
    // indexOf below, per-key directions + NOTSORTED for the sortedness guard
    // (GAP-procbydescending).
    const pb = try decodeProcBy(arena, bys.items);

    // analysis columns: the `var` list, else every numeric column NOT named in
    // CLASS/BY/FREQ/WEIGHT/ID (REOPEN-meansdefvar — SAS's default analysis set
    // excludes any var another statement claimed).
    var acols: std.ArrayList(usize) = .empty;
    if (vars.items.len > 0) {
        for (vars.items) |vn| {
            const idx = ds.indexOf(vn) orelse {
                diags.report(.err, 0, "VAR variable {s} not in {s}", .{ vn, ds.name }) catch {};
                continue;
            };
            // A char var in the analysis list is a SAS type ERROR, not a column to
            // fabricate stats for (REOPEN-meansdefvar) — same message as main.zig.
            if (ds.columns.items[idx].type != .num)
                return diags.fail(error.ParseError, 0, "Variable {s} in list does not match type prescribed for this list.", .{std.ascii.allocUpperString(arena, vn) catch vn});
            try acols.append(arena, idx);
        }
    } else {
        var excl: std.ArrayList(usize) = .empty;
        for (classes.items) |nm| if (ds.indexOf(nm)) |idx| try excl.append(arena, idx);
        for (pb.names) |nm| if (ds.indexOf(nm)) |idx| try excl.append(arena, idx);
        for (id_names.items) |nm| if (ds.indexOf(nm)) |idx| try excl.append(arena, idx);
        if (weight_var) |nm| if (ds.indexOf(nm)) |idx| try excl.append(arena, idx);
        if (freq_var) |nm| if (ds.indexOf(nm)) |idx| try excl.append(arena, idx);
        for (ds.columns.items, 0..) |c, idx|
            if (c.type == .num and std.mem.indexOfScalar(usize, excl.items, idx) == null)
                try acols.append(arena, idx);
    }
    if (acols.items.len == 0) {
        unsupported("PROC MEANS: no numeric analysis variable");
        return;
    }

    // The requested statistics (default 5 when none named) — honored by both the
    // single-var block and the multi-var combined table.
    const chosen: []const StatKind = if (stats.items.len > 0) stats.items else &default_stats;

    // CLASS variable column indices (order = declaration order).
    var ccols: std.ArrayList(usize) = .empty;
    for (classes.items) |cn| if (ds.indexOf(cn)) |idx| try ccols.append(arena, idx);
    // BY variable column indices — OUTPUT OUT= emits one row per BY group.
    var obcols: std.ArrayList(usize) = .empty;
    var obdesc: std.ArrayList(bool) = .empty; // BY direction per obcols entry (BUG-meansoutbydescending)
    for (pb.names, 0..) |bn, k| if (ds.indexOf(bn)) |idx| {
        try obcols.append(arena, idx);
        try obdesc.append(arena, pb.desc[k]);
    };
    // BUG-meansbyunsorted: BY demands sorted data. A backward step between
    // contiguous groups (which any repeated non-adjacent key forces) ERRORs
    // like SAS — mirrors the TABULATE/TRANSPOSE guard. Without it an unsorted
    // BY silently POOLED the out-of-order groups in OUT= and printed duplicate
    // sections in the listing. BY DESCENDING flips the check per key
    // (byOrderViolation; GAP-procbydescending); NOTSORTED drops it (Statements
    // ref p.41: groups form on consecutive equal values, order unchecked).
    if (obcols.items.len > 0 and !pb.notsorted) {
        const rows = ds.rows.items;
        var s: usize = 0;
        while (s < rows.len) {
            var e = s + 1;
            while (e < rows.len and byEqual(rows[s], rows[e], obcols.items)) e += 1;
            if (e < rows.len) if (byOrderViolation(rows[e], rows[s], obcols.items, pb.desc)) |k|
                return diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (pb.desc[k]) "descending" else "ascending" });
            s = e;
        }
    }
    // ID variable column indices — carried into OUTPUT (BUG-meansidnoop).
    var icols: std.ArrayList(usize) = .empty;
    for (id_names.items) |nm| {
        const idx = ds.indexOf(nm) orelse
            return diags.fail(error.ParseError, 0, "PROC MEANS: ID variable {s} not in {s}", .{ nm, ds.name });
        try icols.append(arena, idx);
    }

    // BUG-meansclassmiss: SAS excludes obs with a missing CLASS value from the
    // WHOLE analysis (grand total, every _TYPE_, the listing) — the MISSING option
    // re-includes them. Filter once, before any grouping, so all paths (listing +
    // OUTPUT) see the same rows. BY is unaffected (missing BY groups are real).
    if (ccols.items.len > 0 and !missing_opt) ds = try dropMissingClass(arena, ds, ccols.items);

    // TYPES/WAYS: resolve the requested sub-types to class column-index sets
    // (BUG-meanstypes/BUG-meansways) — before OUTPUT so both paths see them.
    var combos: std.ArrayList([]const usize) = .empty;
    const combos_req = types_seen or ways_seen;
    if (combos_req) {
        if (types_seen and ways_seen)
            return diags.fail(error.ParseError, 0, "PROC MEANS: TYPES and WAYS together are not yet supported", .{});
        if (classes.items.len == 0)
            return diags.fail(error.ParseError, 0, "PROC MEANS: TYPES/WAYS require a CLASS statement", .{});
        if (types_seen) {
            if (type_combos.items.len == 0)
                return diags.fail(error.ParseError, 0, "PROC MEANS: empty TYPES statement", .{});
            for (type_combos.items) |combo| {
                var cols: std.ArrayList(usize) = .empty;
                for (combo) |nm| {
                    var in_class = false;
                    for (classes.items) |cn| if (eqi(cn, nm)) {
                        in_class = true;
                        break;
                    };
                    if (!in_class)
                        return diags.fail(error.ParseError, 0, "PROC MEANS: TYPES variable {s} is not a CLASS variable", .{nm});
                    const ci = ds.indexOf(nm) orelse
                        return diags.fail(error.ParseError, 0, "PROC MEANS: TYPES variable {s} not in {s}", .{ nm, ds.name });
                    try cols.append(arena, ci);
                }
                try combos.append(arena, cols.items);
            }
        } else {
            if (ways_degs.items.len == 0)
                return diags.fail(error.ParseError, 0, "PROC MEANS: empty WAYS statement", .{});
            const n = ccols.items.len;
            for (ways_degs.items) |k| {
                if (k > n)
                    return diags.fail(error.ParseError, 0, "PROC MEANS: WAYS {d} exceeds the number of CLASS variables", .{k});
                // ponytail: bitmask enumeration — 2^n masks, n = #CLASS vars (tiny).
                var mask: usize = 0;
                while (mask < (@as(usize, 1) << @intCast(n))) : (mask += 1) {
                    if (@popCount(mask) != k) continue;
                    var cols: std.ArrayList(usize) = .empty;
                    for (0..n) |j| if (((mask >> @intCast(j)) & 1) == 1) try cols.append(arena, ccols.items[j]);
                    try combos.append(arena, cols.items);
                }
            }
        }
    }

    // Resolve each OUTPUT group to (stat, name, acol) triples: the k-th name maps
    // to the k-th explicit `(varlist)` var, else the k-th analysis var (the VAR
    // list order). Each output column then computes from its OWN var (BUG-meansoutmulti).
    // Per OUTPUT statement — each builds from its OWN spec list (BUG-meansoutmultistmt).
    for (out_stmts.items) |*os| {
        for (os.groups.items) |g| {
            if (g.names.len == 0) {
                // Omitted name(s): SAS uses the analysis-variable name(s) — one
                // column per var (the explicit (varlist), else every VAR var).
                // /AUTONAME names them var_Stat instead
                // (BUG-meansoutemptyname / BUG-meansautoname).
                if (g.evars.len > 0) {
                    for (g.evars) |ev| {
                        // Unknown (varlist) name → loud ERROR (SAS 9.4), never the
                        // old silent remap to the first analysis var
                        // (BUG-meansoutevarunknown). A dataset var NOT in the VAR
                        // statement stays legal — only absence from the dataset fails.
                        const acol = ds.indexOf(ev) orelse
                            return diags.fail(error.ParseError, 0, "PROC MEANS: OUTPUT variable {s} not in {s}", .{ ev, ds.name });
                        try os.stats.append(arena, .{ .stat = g.stat, .name = try outStatName(arena, ds.columns.items[acol].name, g.stat, os.autoname), .acol = acol });
                    }
                } else {
                    for (acols.items) |acol|
                        try os.stats.append(arena, .{ .stat = g.stat, .name = try outStatName(arena, ds.columns.items[acol].name, g.stat, os.autoname), .acol = acol });
                }
                continue;
            }
            // SAS errors when the name count ≠ the analysis-var count (the explicit
            // (varlist), else every VAR var) — the old @min clamp silently dropped
            // vars / cloned values into duplicate columns (BUG-meansoutnamecount).
            const nvars: usize = if (g.evars.len > 0) g.evars.len else acols.items.len;
            if (g.names.len != nvars)
                return diags.fail(error.ParseError, 0, "PROC MEANS: OUTPUT: {d} name(s) given for {d} analysis variable(s)", .{ g.names.len, nvars });
            for (g.names, 0..) |nm, k| {
                const acol: usize = if (g.evars.len > 0)
                    (ds.indexOf(g.evars[k]) orelse
                        return diags.fail(error.ParseError, 0, "PROC MEANS: OUTPUT variable {s} not in {s}", .{ g.evars[k], ds.name }))
                else
                    acols.items[k];
                try os.stats.append(arena, .{ .stat = g.stat, .name = nm, .acol = acol });
            }
        }
    }

    // OUTPUT OUT=ds — one dataset PER OUTPUT statement, each with its OWN stat
    // columns (per BY group, per CLASS group, or one row) (BUG-meansoutmultistmt).
    for (out_stmts.items) |os| {
        const oname = os.name orelse continue; // no OUT= → nothing to build (as before)
        // Restricting the OUTPUT dataset to the requested _TYPE_s isn't wired —
        // emit nothing rather than a silently unfiltered dataset.
        if (combos_req)
            return diags.fail(error.ParseError, 0, "PROC MEANS: TYPES/WAYS with OUTPUT OUT= is not yet supported", .{});
        if (os.stats.items.len == 0) {
            // No statistic named → SAS emits the default 5 stats in long form,
            // keyed by a _STAT_ char variable (BUG-meansoutnostat). buildMeansOutputDefault
            // has no CLASS path: with CLASS present it would drop the `g` column and the
            // _TYPE_ bitmask rows and emit a misleading overall-only dataset. Fail loud
            // until the CLASS default-output is implemented (GAP-meansoutguards).
            if (ccols.items.len > 0)
                return diags.fail(error.ParseError, 0, "PROC MEANS: OUTPUT OUT= with CLASS and no explicit statistic list is not yet supported", .{});
            if (icols.items.len > 0)
                return diags.fail(error.ParseError, 0, "PROC MEANS: ID statement with OUTPUT OUT= and no explicit statistic list is not yet supported", .{});
            try buildMeansOutputDefault(arena, lib, oname, ds, obcols.items, obdesc.items, acols.items, wcol, vardef);
        } else
            try buildMeansOutput(arena, diags, lib, oname, ds, ccols.items, obcols.items, obdesc.items, wcol, icols.items, os.stats.items, nway, true, vardef, class_order, descending, alpha, fmt_levels.items);
        if (os.opts.len > 0) if (lib.find(oname)) |od|
            try io.applyDatasetOptions(arena, od, os.opts, diags, false); // out=X(keep=/drop=) — BUG-procoutkeep
    }

    // NOPRINT suppresses the listing (but OUTPUT above still ran).
    if (noprint) return;

    // The listing prints one table set PER BY GROUP (BUG-meansbypooled: the
    // multi-var and CLASS paths used to return one pooled table over ALL obs).
    // Without BY, bySlices yields one null-rep slice = the whole dataset, so the
    // pooled paths below stay byte-identical. obcols doubles as the listing's BY key.
    const slices = try bySlices(arena, ds.rows.items, obcols.items);

    // CLASS / TYPES / WAYS — one stats table per class level, per BY group
    // (levels collected within the group, no sort of the input required;
    // emitted in ascending order).
    if (combos_req or ccols.items.len > 0) {
        try out.appendSlice(arena, title);
        // TYPES/WAYS: the requested combos (an empty combo = the overall);
        // plain CLASS: the single full combo.
        const plain = [_][]const usize{ccols.items};
        const sets: []const []const usize = if (combos_req) combos.items else &plain;
        for (slices) |bs| {
            if (bs.rep) |r| try appendByLine(arena, out, ds, r, obcols.items);
            for (sets) |cols| {
                const groups = try collectGroupsRows(arena, bs.rows, cols, class_order);
                if (class_order == .internal) reorderGroupsFmt(groups, cols, fmt_levels.items); // VALUE.-format CLASS bands → raw-value order (BUG-freqfmtorder)
                if (descending) std.mem.reverse(MeansGroup, groups); // DESCENDING reverses the CLASS levels (BUG-meansoptnoop)
                for (acols.items) |ci|
                    try emitMeansClassTable(arena, out, ds, cols, groups, ci, wcol, chosen, vardef, maxdec, alpha);
            }
        }
        return;
    }

    // Multiple analysis variables → the combined "Variable" table (one row each,
    // columns = the requested stats), per BY group. A single variable keeps the
    // "Analysis Variable :" block below.
    if (acols.items.len > 1) {
        try out.appendSlice(arena, MEANS_COMBINED_TITLE);
        for (slices) |bs| {
            if (bs.rep) |r| try appendByLine(arena, out, ds, r, obcols.items);
            try out.append(arena, '\n'); // the blank after the title / BY line
            try emitMeansCombined(arena, out, ds, bs.rows, acols.items, wcol, chosen, vardef, maxdec, alpha);
        }
        return;
    }

    try out.appendSlice(arena, title);

    // Single analysis variable — the "Analysis Variable :" block per BY group
    // (input assumed already sorted by the BY vars, as SAS requires).
    for (slices) |bs| {
        if (bs.rep) |r| try appendByLine(arena, out, ds, r, obcols.items);
        for (acols.items) |ci|
            try emitMeansBlock(arena, out, ds.columns.items[ci].name, bs.rows, ci, wcol, chosen, vardef, maxdec, alpha);
    }
}

/// The single-var "Analysis Variable" block, honoring the requested `stats`
/// (the default 5 reproduce proc_means.sas exactly). N sits in a 12-wide field,
/// the decimal stats in 16-wide; the rule is 5 spaces then dashes to the width.
fn emitMeansBlock(arena: std.mem.Allocator, out: *std.ArrayList(u8), name: []const u8, rows: []const []const Value, col: usize, wcol: ?usize, stats: []const StatKind, vardef: VarDef, maxdec: ?u8, alpha: f64) !void {
    const s = computeStatsV(rows, col, wcol, vardef);
    const hdrs = try arena.alloc([]const u8, stats.len); // ALPHA-aware headers (BUG-meansoptnoop)
    for (stats, 0..) |sk, j| hdrs[j] = try statHeaderA(arena, sk, alpha);
    var content: usize = 0;
    for (stats, 0..) |sk, j| content += blockWidth(sk, hdrs[j]);

    try out.append(arena, '\n');
    try appendCentered(arena, out, try std.fmt.allocPrint(arena, "Analysis Variable : {s}", .{name}));
    try out.append(arena, '\n');
    for (stats, 0..) |sk, j| try out.appendSlice(arena, try rjust(arena, hdrs[j], blockWidth(sk, hdrs[j])));
    try out.append(arena, '\n');
    try appendBlockRule(arena, out, content);
    for (stats, 0..) |sk, j| {
        const w = blockWidth(sk, hdrs[j]);
        const val: f64 = switch (sk) {
            .n => @floatFromInt(s.n),
            .nmiss => @floatFromInt(nmissCount(rows, col)),
            else => statValueA(sk, s, alpha),
        };
        const spec = if (sk == .n or sk == .nmiss)
            try std.fmt.allocPrint(arena, "{d}.", .{w})
        else
            try std.fmt.allocPrint(arena, "{d}.{d}", .{ w, maxdec orelse 7 });
        // non-finite (±inf, e.g. from x=1e400) is a SAS missing → "." (BUG-procinf)
        try out.appendSlice(arena, if (std.math.isFinite(val)) try format.apply(arena, .{ .num = val }, spec) else try rjust(arena, ".", w));
    }
    try out.append(arena, '\n');
    try appendBlockRule(arena, out, content);
}

/// The block's underline: 5 leading spaces, then dashes filling the rest of the
/// data width (the default 5 stats → 5 + 71 dashes = 76, as SAS pins).
fn appendBlockRule(arena: std.mem.Allocator, out: *std.ArrayList(u8), content: usize) !void {
    for (0..5) |_| try out.append(arena, ' ');
    const dashes = if (content > 5) content - 5 else 0;
    for (0..dashes) |_| try out.append(arena, '-');
    try out.append(arena, '\n');
}

/// The combined MEANS table: a left-justified `Variable` column then one
/// right-justified field per requested statistic, a row per analysis variable.
/// `rows` is one BY group's slice (the whole dataset without BY); the caller
/// prints the title + BY line (BUG-meansbypooled). Column widths + the
/// underline length are tuned to the SAS listing proc_means_var pins.
fn emitMeansCombined(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, rows: []const []const Value, acols: []const usize, wcol: ?usize, stats: []const StatKind, vardef: VarDef, maxdec: ?u8, alpha: f64) !void {
    var wname: usize = "Variable".len;
    for (acols) |ci| wname = @max(wname, ds.columns.items[ci].name.len);

    const hdrs = try arena.alloc([]const u8, stats.len); // ALPHA-aware headers (BUG-meansoptnoop)
    for (stats, 0..) |sk, j| hdrs[j] = try statHeaderA(arena, sk, alpha);
    var content: usize = wname;
    for (stats, 0..) |sk, j| content += statWidth(sk, hdrs[j]);
    const rule_len = content + wname; // SAS draws the underline wider than the data

    // header
    try out.appendSlice(arena, try ljust(arena, "Variable", wname));
    for (stats, 0..) |sk, j| try out.appendSlice(arena, try rjust(arena, hdrs[j], statWidth(sk, hdrs[j])));
    try out.append(arena, '\n');
    try appendRule(arena, out, rule_len);

    // one row per analysis variable
    for (acols) |ci| {
        const s = computeStatsV(rows, ci, wcol, vardef);
        try out.appendSlice(arena, try ljust(arena, ds.columns.items[ci].name, wname));
        for (stats, 0..) |sk, j| {
            const w = statWidth(sk, hdrs[j]);
            if (sk == .n) {
                try out.appendSlice(arena, try format.apply(arena, .{ .num = @floatFromInt(s.n) }, try std.fmt.allocPrint(arena, "{d}.", .{w})));
            } else if (sk == .nmiss) {
                try out.appendSlice(arena, try format.apply(arena, .{ .num = @floatFromInt(nmissCount(rows, ci)) }, try std.fmt.allocPrint(arena, "{d}.", .{w})));
            } else {
                const val = statValueA(sk, s, alpha);
                try out.appendSlice(arena, if (std.math.isFinite(val)) // ±inf → "." (BUG-procinf)
                    try format.apply(arena, .{ .num = val }, try std.fmt.allocPrint(arena, "{d}.{d}", .{ w, maxdec orelse 7 }))
                else
                    try rjust(arena, ".", w));
            }
        }
        try out.append(arena, '\n');
    }
    try appendRule(arena, out, rule_len);
}

fn appendRule(arena: std.mem.Allocator, out: *std.ArrayList(u8), n: usize) !void {
    const rule = try arena.alloc(u8, n);
    @memset(rule, '-');
    try out.appendSlice(arena, rule);
    try out.append(arena, '\n');
}

/// PROC MEANS with CLASS → one combined table: a left-justified column per class
/// var (its value per level), then the requested stats, ONE row per class level —
/// SAS's layout, replacing the old per-level "Analysis Variable" blocks
/// (BUG-meansclass-layout). ponytail: SAS's separate "N Obs" column is dropped
/// (the requested N stat carries the count); one analysis var per table, so a
/// multi-var CLASS run prints one table per variable rather than SAS's merged one.
fn emitMeansClassTable(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, ccols: []const usize, groups: []MeansGroup, acol: usize, wcol: ?usize, stats: []const StatKind, vardef: VarDef, maxdec: ?u8, alpha: f64) !void {
    // class column widths: header (var name) vs the widest level value, + a 2-col gutter
    const wc = try arena.alloc(usize, ccols.len);
    for (ccols, 0..) |ci, i| {
        wc[i] = ds.columns.items[ci].name.len;
        for (groups) |g| wc[i] = @max(wc[i], (try classCell(arena, g.rep[ci])).len);
    }
    const hdrs = try arena.alloc([]const u8, stats.len); // ALPHA-aware headers (BUG-meansoptnoop)
    for (stats, 0..) |sk, j| hdrs[j] = try statHeaderA(arena, sk, alpha);
    var content: usize = 0;
    for (wc) |w| content += w + 2;
    for (stats, 0..) |sk, j| content += statWidth(sk, hdrs[j]);

    try out.append(arena, '\n');
    try appendCentered(arena, out, try std.fmt.allocPrint(arena, "Analysis Variable : {s}", .{ds.columns.items[acol].name}));
    try out.append(arena, '\n');
    for (ccols, 0..) |ci, i| try out.appendSlice(arena, try ljust(arena, ds.columns.items[ci].name, wc[i] + 2));
    for (stats, 0..) |sk, j| try out.appendSlice(arena, try rjust(arena, hdrs[j], statWidth(sk, hdrs[j])));
    try out.append(arena, '\n');
    try appendRule(arena, out, content);
    for (groups) |g| {
        for (ccols, 0..) |ci, i| try out.appendSlice(arena, try ljust(arena, try classCell(arena, g.rep[ci]), wc[i] + 2));
        const s = computeStatsV(g.rows, acol, wcol, vardef);
        for (stats, 0..) |sk, j| {
            const w = statWidth(sk, hdrs[j]);
            if (sk == .n) {
                try out.appendSlice(arena, try format.apply(arena, .{ .num = @floatFromInt(s.n) }, try std.fmt.allocPrint(arena, "{d}.", .{w})));
            } else if (sk == .nmiss) {
                try out.appendSlice(arena, try format.apply(arena, .{ .num = @floatFromInt(nmissCount(g.rows, acol)) }, try std.fmt.allocPrint(arena, "{d}.", .{w})));
            } else {
                const val = statValueA(sk, s, alpha);
                try out.appendSlice(arena, if (std.math.isFinite(val))
                    try format.apply(arena, .{ .num = val }, try std.fmt.allocPrint(arena, "{d}.{d}", .{ w, maxdec orelse 7 }))
                else
                    try rjust(arena, ".", w));
            }
        }
        try out.append(arena, '\n');
    }
    try appendRule(arena, out, content);
}

/// A CLASS level's value as display text: char trimmed, integer plain, else BEST.
fn classCell(arena: std.mem.Allocator, v: Value) ![]const u8 {
    return switch (v) {
        .str => |s| std.mem.trim(u8, s, " "),
        .num => |x| if (std.math.isFinite(x) and x == @trunc(x) and @abs(x) < 1e15)
            try std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))})
        else
            try format.bestNum(arena, x),
    };
}

fn ljust(arena: std.mem.Allocator, text: []const u8, w: usize) ![]const u8 {
    if (text.len >= w) return text;
    const out = try arena.alloc(u8, w);
    @memcpy(out[0..text.len], text);
    @memset(out[text.len..], ' ');
    return out;
}

fn rjust(arena: std.mem.Allocator, text: []const u8, w: usize) ![]const u8 {
    if (text.len >= w) return text;
    const out = try arena.alloc(u8, w);
    @memset(out[0 .. w - text.len], ' ');
    @memcpy(out[w - text.len ..], text);
    return out;
}

/// N / mean / sample-std / min / max over one column, skipping missing. Std is
/// the sample standard deviation (CSS over the VARDEF divisor, n−1 for the DF
/// default); missing when the divisor is not positive.
/// `wcol` names a WEIGHT column (BUG-meansweight): Mean = Σwᵢxᵢ/Σwᵢ, Sum = Σwᵢxᵢ,
/// weighted Std/Var (CSS = Σwᵢ(xᵢ−x̄w)² over the VARDEF divisor), N = the non-
/// missing-weight obs count. With `wcol == null` every weight is 1, so the math is
/// identical to the unweighted case. Min/Max/median/quantiles ignore weights (SAS).
/// Resolve the WEIGHT column index. A named-but-absent weight var is an ERROR
/// (BUG-weightvarcheck): `ds.indexOf` returning null is indistinguishable from
/// "no WEIGHT statement", so a typo'd weight var silently produced UNWEIGHTED
/// stats (wrong mean/std/every percentile, exit 0). No WEIGHT statement
/// (`weight_var == null`) → null, unweighted, fine. Shared by MEANS/SUMMARY,
/// FREQ, and UNIVARIATE.
fn resolveWeightCol(ds: *const Dataset, weight_var: ?[]const u8, diags: *diag.Diagnostics, err_line: usize) diag.Error!?usize {
    const wv = weight_var orelse return null;
    return ds.indexOf(wv) orelse diags.fail(error.ParseError, err_line, "Variable {s} in the WEIGHT statement is not on the input data set", .{wv});
}

/// A row's analysis weight for a WEIGHT statement: the weight cell when nonmissing.
/// Missing weight → null (SAS ALWAYS drops missing-weight obs from N). A nonpositive
/// weight (≤0) → 0, NOT null: SAS 9.4's DEFAULT (no EXCLNPWGT) COUNTS the obs in N
/// and uses its value for MIN/MAX/median, while the zero weight makes it contribute
/// nothing to the weighted Sum/Mean/Std. EXCLNPWGT (the opt-in that also excludes
/// nonpositive weights) is handled upstream by pre-filtering those rows out in
/// runMeans, so weightAt itself never sees them under EXCLNPWGT (BUG-meanszeroweight).
/// No WEIGHT column (`wc == null`) → every obs weighs 1. Shared by computeStats
/// (MEANS) and the weighted UNIVARIATE moments/quantiles (WEIGHT-uni-impl).
fn weightAt(r: []const Value, wc: ?usize) ?f64 {
    const wc_i = wc orelse return 1;
    const w = toNum(r[wc_i]);
    if (std.math.isNan(w)) return null; // missing weight → excluded from N (always)
    return if (w <= 0) 0 else w; // ≤0 → counted in N/MIN/MAX, zero contribution to sums
}

/// SAS 9.4 skewness/kurtosis, VARDEF=DF forms (Base Procedures Guide,
/// "Descriptive Statistics"; n = # nonmissing obs, x̄w the weighted mean, s the
/// weighted std):
///   skewness = n/((n−1)(n−2)) · m3/s³          where m3 = Σ wᵢ^{3/2}(xᵢ−x̄w)³
///   kurtosis = n(n+1)/((n−1)(n−2)(n−3)) · m4/s⁴ − 3(n−1)²/((n−2)(n−3))
///              where m4 = Σ wᵢ²(xᵢ−x̄w)⁴
/// With every wᵢ=1 the weight factors are 1 and these collapse to the unweighted
/// g1/g2. Missing unless n≥3 (skew) / n≥4 (kurt) and s>0. Shared by PROC
/// UNIVARIATE's Moments table and PROC MEANS SKEWNESS/KURTOSIS (GAP-meansskewkurt).
const SkewKurt = struct { skew: f64, kurt: f64 };
fn skewKurtDf(n: usize, sd: f64, m3: f64, m4: f64) SkewKurt {
    const nan = std.math.nan(f64);
    const nf: f64 = @floatFromInt(n);
    const v = sd * sd;
    return .{
        .skew = if (n >= 3 and sd > 0)
            (nf / ((nf - 1) * (nf - 2))) * (m3 / (sd * v))
        else
            nan,
        .kurt = if (n >= 4 and sd > 0)
            (nf * (nf + 1) / ((nf - 1) * (nf - 2) * (nf - 3))) * (m4 / (v * v)) -
                3 * (nf - 1) * (nf - 1) / ((nf - 2) * (nf - 3))
        else
            nan,
    };
}

/// NMISS on the p.408 list-2 BASIS (BUG-univnmissweightbasis): the delivered
/// rows with a MISSING analysis value — NOT rows.len − s.n. N (list 1) also
/// excludes a PRESENT value whose WEIGHT is missing; the missing-count basis
/// does not. The basis's own pre-exclusions are already gone from `rows`:
/// nonpositive FREQ via expandFreq, and missing/nonpositive WEIGHT — only
/// under EXCLNPWGT — via dropNonpositiveWeight. So the two formulas differ
/// exactly on a missing-weight/present-value obs, and counting the missing
/// cells directly is list 2 in every case. Statistical Procedures p.408,
/// === pdf 411 ===. (TABULATE's tabCellValue keeps obs − n: it has no WEIGHT
/// statement, so there the two are identical.)
fn nmissCount(rows: []const []const Value, col: usize) usize {
    var m: usize = 0;
    for (rows) |r| {
        if (std.math.isNan(toNum(r[col]))) m += 1;
    }
    return m;
}

fn computeStats(rows: []const []const Value, col: usize, wcol: ?usize) Stats {
    return computeStatsV(rows, col, wcol, .df); // VARDEF=DF is the SAS default
}

fn computeStatsV(rows: []const []const Value, col: usize, wcol: ?usize, vardef: VarDef) Stats {
    if (rows.len > 0) assert(col < rows[0].len); // analysis column aligns with the row schema
    // WEIGHT column too — a bad weight index reads a wrong cell per row and every
    // weighted Mean/Sum/Std comes out silently wrong (TASTE-asserts).
    if (rows.len > 0) if (wcol) |wc| assert(wc < rows[0].len);
    const nan = std.math.nan(f64);
    const weightOf = weightAt;
    var n: usize = 0;
    var sumwx: f64 = 0; // Σ wᵢ xᵢ  (the weighted SUM)
    var sumw: f64 = 0; // Σ wᵢ
    var uss: f64 = 0; // Σ wᵢ xᵢ²  (uncorrected sum of squares, BUG-meanspctlmore)
    var lo: f64 = std.math.inf(f64);
    var hi: f64 = -std.math.inf(f64);
    for (rows) |r| {
        const x = toNum(r[col]);
        if (std.math.isNan(x)) continue;
        const w = weightOf(r, wcol) orelse continue;
        n += 1;
        sumwx += w * x;
        sumw += w;
        uss += w * x * x;
        if (x < lo) lo = x;
        if (x > hi) hi = x;
    }
    // Zero nonmissing values: every DATA-derived statistic is missing, but the SUM
    // OF THE WEIGHTS is not derived from the data — Statistical Procedures p.410
    // defines it as Σwᵢ and states "If there is no WEIGHT variable, the sum of the
    // weights is n", and n itself is computed regardless of missingness
    // (Procedures Guide p.72: "N and NMISS do not require any nonmissing
    // observations"). n==0 ⇒ Σwᵢ==0, so Sum Weights prints 0 next to N 0.
    // SUM/USS/CSS stay MISSING and that is CONFORMANT, not an oversight: p.72 and
    // p.2749 both name them — "SUM, MEAN, MAX, MIN, RANGE, USS, and CSS require at
    // least one nonmissing observation" — and SUMWGT is in neither list
    // (NOTE-univallmiss).
    if (n == 0) return .{ .n = 0, .sumw = 0, .mean = nan, .std = nan, .min = nan, .max = nan, .sum = nan, .median = nan, .q1 = nan, .q3 = nan };
    const mean = sumwx / sumw;
    var css: f64 = 0;
    var m3: f64 = 0; // Σ wᵢ^{3/2}(xᵢ−x̄)³ (skewness input)
    var m4: f64 = 0; // Σ wᵢ²(xᵢ−x̄)⁴    (kurtosis input)
    for (rows) |r| {
        const x = toNum(r[col]);
        if (std.math.isNan(x)) continue;
        const w = weightOf(r, wcol) orelse continue;
        const dv = x - mean;
        const d2 = dv * dv;
        css += w * d2;
        if (wcol == null) { // unweighted: w-factors are 1, skip the pow
            m3 += d2 * dv;
            m4 += d2 * d2;
        } else {
            m3 += std.math.pow(f64, w, 1.5) * d2 * dv;
            m4 += (w * w) * d2 * d2;
        }
    }
    // VARDEF divisor (BUG-statvardef): std = √(CSS/d). A non-positive d (DF
    // with n<2, WDF with Σw≤1) leaves the variance undefined → missing.
    const nf: f64 = @floatFromInt(n);
    const divisor: f64 = switch (vardef) {
        .df => nf - 1,
        .n => nf,
        .wgt => sumw,
        .wdf => sumw - 1,
    };
    const sd = if (divisor > 0) @sqrt(css / divisor) else nan;
    // GAP-meansskewkurt: skew/kurt are the VARDEF=DF forms only (SAS uses other
    // coefficients per divisor) → missing under another VARDEF, as UNIVARIATE does.
    const sk = if (vardef == .df) skewKurtDf(n, sd, m3, m4) else SkewKurt{ .skew = nan, .kurt = nan };

    // median: sort the non-missing values. A stack buffer handles the common
    // (small) group; larger groups spill to a short-lived heap buffer so median/
    // quantiles/mode don't silently vanish on clinical-scale data (BUG-meanspctl4k
    // — the old fixed [4096] cap returned missing above 4096 obs). All results are
    // scalars copied into Stats, so the buffer is freed before return.
    var median: f64 = nan;
    var q1: f64 = nan;
    var q3: f64 = nan;
    var pc = [_]f64{nan} ** 12; // p1,p5,p10,p20,p30,p40,p60,p70,p80,p90,p95,p99
    var mode: f64 = nan;
    var mbuf: [4096]f64 = undefined;
    const heap: ?[]f64 = if (n > mbuf.len) (std.heap.page_allocator.alloc(f64, n) catch null) else null;
    defer if (heap) |h| std.heap.page_allocator.free(h);
    const buf: []f64 = heap orelse mbuf[0..]; // ponytail: page_allocator — no arena threaded here; short-lived
    if (n <= buf.len) {
        var k: usize = 0;
        for (rows) |r| {
            const x = toNum(r[col]);
            if (std.math.isNan(x)) continue;
            if (weightOf(r, wcol) == null) continue;
            buf[k] = x;
            k += 1;
        }
        std.mem.sort(f64, buf[0..n], {}, std.sort.asc(f64));
        median = if (n % 2 == 1) buf[n / 2] else (buf[n / 2 - 1] + buf[n / 2]) / 2;
        q1 = percentile(buf[0..n], 25);
        q3 = percentile(buf[0..n], 75);
        inline for (.{ 1, 5, 10, 20, 30, 40, 60, 70, 80, 90, 95, 99 }, 0..) |p, pi| pc[pi] = percentile(buf[0..n], p);
        mode = modeOf(buf[0..n]);
    }
    return .{
        .n = n,      .sumw = sumw, .mean = mean, .std = sd,  .min = lo,     .max = hi,     .sum = sumwx,
        .median = median, .q1 = q1, .q3 = q3, .p1 = pc[0],   .p5 = pc[1],   .p10 = pc[2],
        .p20 = pc[3],  .p30 = pc[4],  .p40 = pc[5], .p60 = pc[6],  .p70 = pc[7],   .p80 = pc[8],
        .p90 = pc[9], .p95 = pc[10], .p99 = pc[11], .mode = mode, .css = css,  .uss = uss,
        .skew = sk.skew, .kurt = sk.kurt,
    };
}

/// The longest run of equal values over ascending `sorted`: `mode` is the SMALLEST
/// value attaining it, `count` is its length, `nmodes` how many distinct values
/// attain it. `count < 2` means nothing repeats, so there is no mode at all.
/// UNIVARIATE needs `nmodes`/`count` for its multimodal note (NOTE-univallmiss);
/// MEANS needs only the value, so `modeOf` is the one-line projection.
const ModeInfo = struct { mode: f64, nmodes: usize, count: usize };
fn modeInfo(sorted: []const f64) ModeInfo {
    var best = ModeInfo{ .mode = std.math.nan(f64), .nmodes = 0, .count = 0 };
    var i: usize = 0;
    while (i < sorted.len) {
        var j = i; // [i..j] is the run of values equal to sorted[i]
        while (j + 1 < sorted.len and sorted[j + 1] == sorted[i]) j += 1;
        const run = j - i + 1;
        if (run > best.count) {
            best = .{ .mode = sorted[i], .nmodes = 1, .count = run };
        } else if (run == best.count) {
            best.nmodes += 1; // ascending, so the first run to attain it is the smallest
        }
        i = j + 1;
    }
    return best;
}

/// SAS MODE: the most frequent value; ties resolve to the SMALLEST such value, and
/// when every value is unique (no repeat) the mode is missing. `sorted` is ascending
/// (so the first-seen longest run is already the smallest) (BUG-meanspctlmore).
fn modeOf(sorted: []const f64) f64 {
    const m = modeInfo(sorted);
    return if (m.count < 2) std.math.nan(f64) else m.mode;
}

/// SAS default percentile (PCTLDEF=5): with position np/100 = j + g over the
/// sorted non-missing values, g==0 averages x[j],x[j+1] (1-based), else takes
/// x[j+1]. Matches the existing even-n median = P50. `sorted` must be ascending.
fn percentile(sorted: []const f64, p: f64) f64 {
    const n = sorted.len;
    if (n == 0) return std.math.nan(f64);
    if (n == 1) return sorted[0];
    const np = p / 100.0 * @as(f64, @floatFromInt(n));
    const j = @floor(np);
    const ji: usize = @intFromFloat(j);
    if (np - j == 0) { // integer position → average the two straddling values
        if (ji == 0) return sorted[0];
        if (ji >= n) return sorted[n - 1];
        return (sorted[ji - 1] + sorted[ji]) / 2.0;
    }
    return if (ji >= n) sorted[n - 1] else sorted[ji]; // x[j+1], 1-based → sorted[ji]
}

fn appendCentered(arena: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    // centered over the 71-wide table region (cols 6–76): a 5-col left margin
    // plus half the slack.
    const inner: usize = if (text.len < 71) (71 - text.len) / 2 else 0;
    for (0..5 + inner) |_| try out.append(arena, ' ');
    try out.appendSlice(arena, text);
    try out.append(arena, '\n');
}

fn byEqual(l: []const Value, r: []const Value, bcols: []const usize) bool {
    for (bcols) |ci| if (cmpValue(l[ci], r[ci]) != .eq) return false;
    return true;
}

/// Is row `l`'s BY key strictly below row `r`'s? Mirrors main.zig:1862 byRowLess
/// (SAS order: missing lowest, char blank-padded) via the same cmpValue used for
/// grouping, so the sortedness check and the grouping stay consistent.
fn byLess(l: []const Value, r: []const Value, bcols: []const usize) bool {
    for (bcols) |ci| switch (cmpValue(l[ci], r[ci])) {
        .lt => return true,
        .gt => return false,
        .eq => {},
    };
    return false;
}

/// The BY-key index where group `nxt` steps BACKWARD from group `cur` in the
/// BY-specified order — ascending per key by default, inverted where BY
/// DESCENDING applies (GAP-procbydescending; the same inversion rule as
/// exec.cmpBy, so DATA-step and PROC sortedness checks cannot disagree) —
/// else null. Equality cannot occur: the two rows head DIFFERENT groups.
/// With no descending keys this is exactly `byLess(nxt, cur)` made
/// index-returning (Statements ref p.40: DESCENDING means the data set is
/// sorted descending BY THAT VARIABLE, so the check flips per key).
fn byOrderViolation(nxt: []const Value, cur: []const Value, bcols: []const usize, descs: []const bool) ?usize {
    for (bcols, 0..) |ci, k| switch (cmpValue(nxt[ci], cur[ci])) {
        .lt => return if (k < descs.len and descs[k]) null else k,
        .gt => return if (k < descs.len and descs[k]) k else null,
        .eq => {},
    };
    return null;
}

/// One listing table-set's row slice: `rep` is the BY group's representative
/// row (null without BY → no BY line, the pooled table).
const BySlice = struct { rep: ?[]const Value, rows: []const []const Value };

/// Contiguous BY-group slices of (sorted) rows, as SAS requires. No BY columns
/// → a single null-rep slice over all rows (empty input included, so the pooled
/// table still prints); BY over an empty dataset → no slices (title only).
fn bySlices(arena: std.mem.Allocator, rows: []const []const Value, bcols: []const usize) ![]BySlice {
    var slices: std.ArrayList(BySlice) = .empty;
    if (bcols.len == 0) {
        try slices.append(arena, .{ .rep = null, .rows = rows });
        return slices.items;
    }
    var start: usize = 0;
    while (start < rows.len) {
        var end = start + 1;
        while (end < rows.len and byEqual(rows[start], rows[end], bcols)) end += 1;
        try slices.append(arena, .{ .rep = rows[start], .rows = rows[start..end] });
        start = end;
    }
    return slices.items;
}

fn appendByLine(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, row: []const Value, bcols: []const usize) !void {
    if (io.global_nobyline) return; // `options nobyline;` (BUG-optionsstmtswallow)
    var label: std.ArrayList(u8) = .empty;
    for (bcols, 0..) |ci, k| {
        assert(ci < row.len); // BY column indexes a real cell before cellText(row[ci])
        if (k > 0) try label.append(arena, ' ');
        try label.appendSlice(arena, ds.columns.items[ci].name);
        try label.append(arena, '=');
        try label.appendSlice(arena, try cellText(arena, row[ci]));
    }
    try out.append(arena, '\n');
    try appendCentered(arena, out, label.items);
}

fn cellText(arena: std.mem.Allocator, v: Value) ![]const u8 {
    return switch (v) {
        .str => |s| std.mem.trimEnd(u8, s, " "),
        // non-finite (NaN or ±inf, e.g. `x=1e400`) is a SAS missing → "."/"A"-"Z"/"_"
        .num => |x| if (std.math.isNan(x))
            try arena.dupe(u8, &[_]u8{Value.missingChar(x)})
        else if (!std.math.isFinite(x))
            "."
        else if (x == @trunc(x) and @abs(x) < 1e15)
            try std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))})
        else
            try std.fmt.allocPrint(arena, "{d}", .{x}),
    };
}

// ── CLASS grouping + OUTPUT OUT= (BUG-meansclass / BUG-meansoutput) ───────────

/// One output column: a statistic of analysis column `acol`, written under `name`
/// (BUG-meansoutmulti — each output var computes from its OWN analysis variable).
const OutStat = struct { stat: StatKind, name: []const u8, acol: usize = 0 };

/// Output-column name for an omitted `stat=` name: the analysis-var name, or
/// `var_Stat` under /AUTONAME (BUG-meansoutemptyname / BUG-meansautoname).
fn outStatName(arena: std.mem.Allocator, var_name: []const u8, stat: StatKind, autoname: bool) ![]const u8 {
    if (!autoname) return var_name;
    return std.fmt.allocPrint(arena, "{s}_{s}", .{ var_name, statSasName(stat) });
}

/// SAS's spelling of a statistic keyword in AUTONAME output vars (`x_Mean`).
/// The rule is only "the combination of the analysis variable name and the
/// statistic-keyword" (Procedures Guide, OUTPUT statement, printed p.1506); no
/// volume prints a worked AUTONAME data set, so the CASE of each suffix below is
/// house convention, not doc-quoted. `SumWgt` follows its neighbours.
fn statSasName(k: StatKind) []const u8 {
    return switch (k) {
        .n => "N",           .nmiss => "NMiss", .mean => "Mean", .std => "StdDev",
        .sumwgt => "SumWgt",
        .min => "Min",       .max => "Max",     .sum => "Sum",   .median => "Median",
        .q1 => "Q1",         .q3 => "Q3",       .var_ => "Var",  .cv => "CV",
        .stderr => "StdErr", .range => "Range", .p1 => "P1",     .p5 => "P5",
        .p10 => "P10",       .p20 => "P20",     .p30 => "P30",   .p40 => "P40",
        .p60 => "P60",       .p70 => "P70",     .p80 => "P80",   .p90 => "P90",
        .p95 => "P95",       .p99 => "P99",
        .qrange => "QRange", .mode => "Mode",   .css => "CSS",   .uss => "USS",
        .lclm => "LCLM",     .uclm => "UCLM",   .t => "T",       .probt => "Probt",
        .skewness => "Skewness", .kurtosis => "Kurtosis",
    };
}

/// FREQ expansion (BUG-meansfreqstmt): a dataset shallow-copy where each obs
/// appears trunc(f) times (rows are shared cell slices — only the pointers
/// repeat). A missing or <1 count drops the obs, as SAS does.
/// ponytail: O(Σf) row pointers, capped below — a weight-based path if
/// frequencies get huge.
fn expandFreq(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, fcol: usize) diag.Error!*Dataset {
    const copy = try arena.create(Dataset);
    copy.* = Dataset.init(arena, ds.name);
    for (ds.columns.items) |c| try copy.columns.append(arena, c);
    for (ds.rows.items) |r| {
        const f = toNum(r[fcol]);
        if (!std.math.isFinite(f) or f < 1) continue;
        if (f > 10_000_000)
            return diags.fail(error.ParseError, 0, "PROC MEANS: FREQ value {d} is too large to expand", .{f});
        const k: usize = @intFromFloat(@trunc(f));
        for (0..k) |_| try copy.rows.append(arena, r);
    }
    return copy;
}

/// A parsed `stat [(varlist)] = name1 name2 …` group from an OUTPUT statement,
/// before analysis-var resolution. `evars` is the explicit `(varlist)` (empty →
/// map names positionally to the VAR list); `names` are the output-column names.
const OutGroup = struct { stat: StatKind, evars: []const []const u8, names: []const []const u8 };

/// One parsed OUTPUT statement: its own OUT= name, /AUTONAME flag, raw groups →
/// resolved stats, and out=(…) option tokens. EACH statement builds its OWN
/// output dataset — two OUTPUT statements never share a stat list
/// (BUG-meansoutmultistmt).
const OutStmt = struct {
    name: ?[]const u8,
    autoname: bool,
    groups: std.ArrayList(OutGroup),
    stats: std.ArrayList(OutStat),
    opts: []const Token,
};

/// A CLASS group: a representative row (for the level values) + its member rows.
const MeansGroup = struct { rep: []const Value, rows: []const []const Value };

/// Drop rows with a missing value in any CLASS column (BUG-meansclassmiss). Returns
/// a shallow copy (columns + row *pointers* shared, cells untouched) so the source
/// dataset in the library is never disturbed — procInput may hand back the original.
fn dropMissingClass(arena: std.mem.Allocator, ds: *Dataset, ccols: []const usize) !*Dataset {
    const copy = try arena.create(Dataset);
    copy.* = Dataset.init(arena, ds.name);
    for (ds.columns.items) |c| try copy.columns.append(arena, c);
    next_row: for (ds.rows.items) |r| {
        for (ccols) |ci| if (isFreqMissing(r[ci])) continue :next_row;
        try copy.rows.append(arena, r);
    }
    return copy;
}

/// EXCLNPWGT: shallow copy of `ds` with every ≤0-or-missing-weight row dropped
/// (BUG-meanszeroweight). Row pointers shared, cells untouched, source library
/// dataset undisturbed — mirrors dropMissingClass. Only reached under EXCLNPWGT;
/// the default counts nonpositive-weight obs (see weightAt).
fn dropNonpositiveWeight(arena: std.mem.Allocator, ds: *Dataset, wcol: usize) !*Dataset {
    const copy = try arena.create(Dataset);
    copy.* = Dataset.init(arena, ds.name);
    for (ds.columns.items) |c| try copy.columns.append(arena, c);
    for (ds.rows.items) |r| {
        const w = toNum(r[wcol]);
        if (std.math.isNan(w) or w <= 0) continue;
        try copy.rows.append(arena, r);
    }
    return copy;
}

/// Group `ds`'s rows by the CLASS columns — one group per distinct level
/// combination, in ascending key order. Unlike BY, CLASS collects across the
/// whole dataset, so the input need not be sorted (BUG-meansclass).
fn collectGroups(arena: std.mem.Allocator, ds: *Dataset, ccols: []const usize) ![]MeansGroup {
    return collectGroupsRows(arena, ds.rows.items, ccols, .internal);
}

/// Hash/eql context for grouping rows by a set of class columns. `eql` reuses
/// `byEqual` verbatim so grouping semantics can't drift from the comparison the
/// rest of proc uses (numeric with all-missing/NaN equal and -0=+0; char
/// blank-padded ⇒ trailing-blank-insensitive). `hash` MUST agree: canonicalize
/// every NaN (all missing group together, incl. special missings) and +0/-0,
/// and right-trim char blanks. Keys are whole rows; only `ccols` participate.
const GroupKeyCtx = struct {
    ccols: []const usize,
    pub fn hash(self: GroupKeyCtx, row: []const Value) u64 {
        var h = std.hash.Wyhash.init(0);
        for (self.ccols) |ci| switch (row[ci]) {
            .str => |s| {
                h.update(std.mem.trimEnd(u8, s, " "));
                h.update(&[_]u8{0}); // field separator: ["a","b"] ≠ ["ab",""]
            },
            .num => |x| {
                const canon: f64 = if (std.math.isNan(x)) std.math.nan(f64) else if (x == 0) 0.0 else x;
                const bits: u64 = @bitCast(canon);
                h.update(std.mem.asBytes(&bits));
            },
        };
        return h.final();
    }
    pub fn eql(self: GroupKeyCtx, a: []const Value, b: []const Value) bool {
        return byEqual(a, b, self.ccols);
    }
};

const GroupIndex = std.HashMapUnmanaged([]const Value, usize, GroupKeyCtx, std.hash_map.default_max_load_percentage);

/// As `collectGroups`, but over an arbitrary row slice — lets OUTPUT OUT= group a
/// single BY group's rows by CLASS (BUG-meansoutputby). O(rows) via a hash index
/// on the class-key tuple (PERF-groupscan); the ordered `reps`/`buckets` lists
/// stay the store so output order is unchanged (append order, then sorted below).
/// CLASS-group ordering for PROC MEANS (ORDER= option, BUG-meansoptnoop):
/// INTERNAL = ascending value (SAS default), DATA = first appearance in the
/// input, FREQ = descending group size (the sort is stable, so ties keep the
/// appearance order). Callers with no ORDER= notion pass .internal.
const GroupOrder = enum { internal, formatted, data, freq };

fn collectGroupsRows(arena: std.mem.Allocator, rows: []const []const Value, ccols: []const usize, order: GroupOrder) ![]MeansGroup {
    var reps: std.ArrayList([]const Value) = .empty;
    var buckets: std.ArrayList(std.ArrayList([]const Value)) = .empty;
    var index: GroupIndex = .empty;
    const ctx = GroupKeyCtx{ .ccols = ccols };
    for (rows) |row| {
        const gop = try index.getOrPutContext(arena, row, ctx);
        if (gop.found_existing) {
            try buckets.items[gop.value_ptr.*].append(arena, row);
        } else {
            gop.value_ptr.* = reps.items.len;
            try reps.append(arena, row);
            var b: std.ArrayList([]const Value) = .empty;
            try b.append(arena, row);
            try buckets.append(arena, b);
        }
    }
    const groups = try arena.alloc(MeansGroup, reps.items.len);
    for (reps.items, 0..) |rep, k| groups[k] = .{ .rep = rep, .rows = buckets.items[k].items };
    switch (order) {
        .internal => std.mem.sort(MeansGroup, groups, ccols, groupLess),
        .formatted => unreachable, // MEANS rejects ORDER=FORMATTED at parse (BUG-meansoptnoop); TABULATE-only (GAP-tabulateopts)
        .data => {}, // reps/buckets were appended in first-appearance order
        .freq => std.mem.sort(MeansGroup, groups, {}, groupFreqDesc), // stable → ties keep appearance order
    }
    return groups;
}

fn groupFreqDesc(_: void, l: MeansGroup, r: MeansGroup) bool {
    return l.rows.len > r.rows.len;
}

fn groupLess(ccols: []const usize, l: MeansGroup, r: MeansGroup) bool {
    for (ccols) |ci| {
        const o = cmpValue(l.rep[ci], r.rep[ci]);
        if (o != .eq) return o == .lt;
    }
    return false;
}

/// groupLess with a per-key direction (BUG-meansoutbydescending) — desc[k]
/// flips key k's comparison, so mixed-direction BY lists sort per key exactly
/// like the DATA-step guard (exec.cmpBy's inversion rule).
const GroupDirCtx = struct { ccols: []const usize, desc: []const bool };
fn groupLessDir(ctx: GroupDirCtx, l: MeansGroup, r: MeansGroup) bool {
    for (ctx.ccols, 0..) |ci, k| {
        const o = cmpValue(l.rep[ci], r.rep[ci]);
        if (o != .eq) return (o == .lt) != ctx.desc[k];
    }
    return false;
}

/// collectGroups sorts ascending, but OUT= rows must go out in the BY's OWN
/// order: a descending key emits its groups descending, else the dataset we
/// write is one our own next step (`data z; set s; by descending g;`) refuses
/// to read (BUG-meansoutbydescending). DOC-SILENT in the Procedures Guide —
/// consistency-driven: the listing/PRINT/TRANSPOSE already emit the BY order
/// (p.74 "Orders the output according to the BY groups"). Re-sort only when
/// some key descends, so ascending/no-BY output stays byte-identical.
fn sortByGroupsByDir(bygroups: []MeansGroup, bycols: []const usize, by_desc: []const bool) void {
    if (std.mem.indexOfScalar(bool, by_desc, true) != null)
        std.mem.sort(MeansGroup, bygroups, GroupDirCtx{ .ccols = bycols, .desc = by_desc }, groupLessDir);
}

/// Re-order ORDER=INTERNAL CLASS groups so a VALUE.-format band sorts by its
/// smallest raw value, not label text (BUG-freqfmtorder). A formatted class col
/// compares by fmtRank; a non-formatted one falls back to cmpValue — so mixed
/// formatted/plain CLASS lists stay multi-key correct. No-op when no col is
/// format-grouped.
fn reorderGroupsFmt(groups: []MeansGroup, ccols: []const usize, levels: []const FmtLevels) void {
    if (levels.len == 0) return;
    const FCtx = struct { ccols: []const usize, levels: []const FmtLevels };
    std.mem.sort(MeansGroup, groups, FCtx{ .ccols = ccols, .levels = levels }, struct {
        fn less(c: FCtx, l: MeansGroup, r: MeansGroup) bool {
            for (c.ccols) |ci| {
                if (fmtLevelsFor(c.levels, ci)) |fl| {
                    const lr = fmtRank(fl, valStr(l.rep[ci]));
                    const rr = fmtRank(fl, valStr(r.rep[ci]));
                    if (lr != rr) return lr < rr;
                } else {
                    const o = cmpValue(l.rep[ci], r.rep[ci]);
                    if (o != .eq) return o == .lt;
                }
            }
            return false;
        }
    }.less);
}

/// A proc-level FORMAT statement pair (`format age agf.;` → {"age", "agf."}).
/// An empty spec is SAS's removal form (`format age;` strips the association).
const VarSpec = struct { name: []const u8, spec: []const u8 };

/// Parse a FORMAT statement inside a proc (FREQ/MEANS), filling `specs`.
/// Vars accumulate until a spec run (`[$]name.` / `[$]w[.d]`) assigns them all;
/// names still pending at `;` strip their format (BUG-formatremoval's form).
/// Leaves `i` AT the `;` (the caller's loop tail consumes it). ponytail: no
/// `d1-d3` var ranges (a `-` falls through and both endpoints get the spec) —
/// add when a proc-level fixture uses one.
fn parseProcFormat(arena: std.mem.Allocator, toks: []const Token, i: *usize, specs: *std.ArrayList(VarSpec)) !void {
    i.* += 1; // past `format`
    var pending: std.ArrayList([]const u8) = .empty;
    while (i.* < toks.len and toks[i.*].tag != .semicolon) {
        const tk = toks[i.*];
        // spec shape: optional `$`, a name/number, `.`, optional decimals —
        // `agf.` `8.` `comma10.2` `$sex.` `$3.` (a var name is never followed
        // by `.` in this statement, so name+dot unambiguously starts a spec).
        if (tk.tag == .dollar or tk.tag == .number or
            (tk.tag == .name and atTag(toks, i.* + 1, .dot)))
        {
            var n: usize = if (tk.tag == .dollar) 2 else 1;
            if (atTag(toks, i.* + n, .dot)) n += 1;
            if (atTag(toks, i.* + n, .number)) n += 1;
            const spec = try joinFmt(arena, toks[i.* .. i.* + n]);
            for (pending.items) |vn| try specs.append(arena, .{ .name = vn, .spec = spec });
            pending.clearRetainingCapacity();
            i.* += n;
        } else if (tk.tag == .name) {
            try pending.append(arena, tk.text);
            i.* += 1;
        } else i.* += 1;
    }
    for (pending.items) |vn| try specs.append(arena, .{ .name = vn, .spec = "" });
}

/// NOTE-freqtablesfmt (tick185 + tick167:176): a format associated with a
/// grouping var — a FORMAT statement in the proc (wins), else the column's
/// DATA-step-persisted format — makes SAS group by the FORMATTED value: raw
/// values sharing a label collapse into ONE level, displayed as the label.
/// Rewrite each such column's cells to their formatted text in a FRESH row set
/// (proc input rows are shared with the library dataset — never mutate in
/// place), flip the column to .str, and clear the stored spec so nothing
/// formats twice. Missing stays missing (blank str) so the default missing
/// exclusion still bites. Returns `ds` unchanged when nothing applies.
/// ponytail: level ORDER follows the formatted text (SAS's ORDER=INTERNAL
/// orders by the smallest raw value per collapsed group — switch the sort if a
/// live-SAS golden disagrees); OUT= datasets carry the formatted text (SAS
/// stores a raw value + the attached format there); a var in BOTH VAR and
/// CLASS with a format sees its stats count as nmiss (split raw/formatted
/// copies if a golden ever needs that).
fn groupFormats(arena: std.mem.Allocator, ds: *Dataset, varnames: []const []const u8, stmt_specs: []const VarSpec, levels_out: *std.ArrayList(FmtLevels), diags: *diag.Diagnostics) diag.Error!*Dataset {
    const Target = struct { ci: usize, spec: []const u8 };
    var targets: std.ArrayList(Target) = .empty;
    for (varnames) |vn| {
        const ci = ds.indexOf(vn) orelse continue; // unknown var: no TABLES/CLASS use → no effect
        var spec: ?[]const u8 = ds.columns.items[ci].format;
        for (stmt_specs) |ss| if (eqi(ss.name, vn)) {
            spec = if (ss.spec.len == 0) null else ss.spec;
            break;
        };
        const s = spec orelse continue;
        // NOTE-fmtnumoncharcoerce: the grouping rewrite formats every cell — a
        // numeric format on a char column (or `$` on numeric) silently turned
        // the level into '.'. Same compile-time type check as PROC PRINT's
        // FORMAT statement, before a single row is rewritten.
        const col_char = ds.columns.items[ci].type == .char;
        if (col_char != format.specIsChar(s)) {
            if (col_char)
                return diags.fail(error.ExecError, 0, "The numeric format {s} cannot be used with character variable {s}.", .{ s, vn });
            return diags.fail(error.ExecError, 0, "The character format {s} cannot be used with numeric variable {s}.", .{ s, vn });
        }
        var seen = false;
        for (targets.items) |tg| if (tg.ci == ci) {
            seen = true;
            break;
        };
        if (!seen) try targets.append(arena, .{ .ci = ci, .spec = s });
    }
    if (targets.items.len == 0) return ds;
    const copy = try dupDataset(arena, ds);
    for (targets.items) |tg| {
        // BUG-freqfmtorder: capture each label's ORDER=INTERNAL rank (ascending
        // underlying raw value) from the RAW column BEFORE the rewrite, so
        // consumers order collapsed groups by smallest raw value, not label text.
        // NOTE-freqfmtoutraw: keep the RAW type + applied spec + each label's
        // lowest raw alongside the labels, so OUT= builders can store the raw
        // value with the format attached instead of the label string.
        const lr = try fmtLabelsByRaw(arena, ds, tg.ci, tg.spec);
        try levels_out.append(arena, .{ .col = tg.ci, .labels = lr.labels, .raws = lr.raws, .ty = ds.columns.items[tg.ci].type, .spec = tg.spec });
        copy.columns.items[tg.ci].type = .char;
        copy.columns.items[tg.ci].format = null;
        for (copy.rows.items) |*r| {
            const old = r.*[tg.ci];
            const nv = try arena.alloc(Value, r.*.len);
            @memcpy(nv, r.*);
            nv[tg.ci] = if (isFreqMissing(old)) .{ .str = "" } else .{ .str = try format.apply(arena, old, tg.spec) };
            r.* = nv;
        }
    }
    return copy;
}

/// Distinct formatted labels of column `ci`, in ASCENDING underlying-raw order
/// (ORDER=INTERNAL, BUG-freqfmtorder). Missing raws are skipped: they collapse
/// to a blank label that ranks first, matching SAS missing-first. Labels use the
/// SAME `format.apply` groupFormats uses, so the byte strings match the rewritten
/// cells exactly (padding and all).
fn fmtLabelsByRaw(arena: std.mem.Allocator, ds: *Dataset, ci: usize, spec: []const u8) !FmtLabelsRaws {
    var raws: std.ArrayList(Value) = .empty;
    for (ds.rows.items) |r| {
        const v = r[ci];
        if (isFreqMissing(v)) continue;
        var seen = false;
        for (raws.items) |x| if (cmpValue(x, v) == .eq) {
            seen = true;
            break;
        };
        if (!seen) try raws.append(arena, v);
    }
    std.mem.sort(Value, raws.items, {}, struct {
        fn less(_: void, l: Value, r: Value) bool {
            return cmpValue(l, r) == .lt;
        }
    }.less);
    var labels: std.ArrayList([]const u8) = .empty;
    var lowests: std.ArrayList(Value) = .empty; // lowest raw per label (raws ascending ⇒ first hit)
    for (raws.items) |rv| {
        const lbl = try format.apply(arena, rv, spec);
        var dup = false;
        for (labels.items) |l| if (std.mem.eql(u8, l, lbl)) {
            dup = true;
            break;
        };
        if (!dup) {
            try labels.append(arena, lbl);
            try lowests.append(arena, rv);
        }
    }
    return .{ .labels = labels.items, .raws = lowests.items };
}

/// Raw-value ORDER=INTERNAL for one FORMAT-grouped column (BUG-freqfmtorder):
/// its distinct labels in ascending underlying-raw order. Consumers re-order
/// their level list by this rank instead of the lexical label compare.
/// One FORMAT-grouped column's raw-ordered distinct labels, plus — for OUT=
/// builders (NOTE-freqfmtoutraw) — `raws`: the LOWEST raw value mapping to each
/// label (parallel to `labels`; SAS stores the lowest internal value of a
/// format-collapsed group, MEANS CLASS stmt Tip, Procedures Guide printed
/// p.1497 — the Tip sits under `=== pdf 1546 ===` and the volume's offset is
/// +49 exactly as its provenance header states; the `1496 Chapter 40` footer
/// just ABOVE that marker belongs to the PRECEDING page, which is the trap),
/// `ty`: the column's type BEFORE the label-string rewrite, and
/// `spec`: the format applied (attach it to the OUT= column so the raw value
/// still renders as its label).
const FmtLevels = struct { col: usize, labels: []const []const u8, raws: []const Value, ty: VarType, spec: []const u8 };
const FmtLabelsRaws = struct { labels: []const []const u8, raws: []const Value };

fn fmtLevelsFor(list: []const FmtLevels, col: usize) ?FmtLevels {
    for (list) |fl| if (fl.col == col) return fl;
    return null;
}

/// Rank of a formatted `label` in raw-ascending order; an unlisted label
/// (missing → blank) ranks first (-1), matching SAS ORDER=INTERNAL missing-first.
fn fmtRank(fl: FmtLevels, label: []const u8) i64 {
    for (fl.labels, 0..) |l, i| if (std.mem.eql(u8, l, label)) return @intCast(i);
    return -1;
}

/// The raw value an OUT= dataset stores for a format-collapsed group showing
/// `label`: the LOWEST internal value (doc cite on FmtLevels). null ⇒ no raw
/// produced this label — the blank missing group (missing raws never enter
/// fmtLabelsByRaw), so the caller stores a missing of the ORIGINAL type.
/// ponytail: a real raw formatting to a label byte-equal to another's is
/// impossible here (labels are deduped); a blank-LABELLED raw and a missing
/// share the blank group and the raw wins — split them if a golden ever needs it.
fn fmtRawFor(fl: FmtLevels, label: []const u8) ?Value {
    for (fl.labels, 0..) |l, i| if (std.mem.eql(u8, l, label)) return fl.raws[i];
    return null;
}

fn valStr(v: Value) []const u8 {
    return switch (v) {
        .str => |s| s,
        .num => "",
    };
}

/// Re-order a FREQ level list into raw-value order for a format-grouped column,
/// only under ORDER=INTERNAL (the default); FREQ/DATA keep their own order.
/// No-op when the column wasn't format-grouped (`fl` null).
fn applyFmtOrder(cats: []Value, fl: ?FmtLevels, order: FreqOrder) void {
    if (order != .internal) return;
    const f = fl orelse return;
    std.mem.sort(Value, cats, f, struct {
        fn less(c: FmtLevels, l: Value, r: Value) bool {
            return fmtRank(c, valStr(l)) < fmtRank(c, valStr(r));
        }
    }.less);
}

/// OUTPUT OUT=ds — the summary dataset. With a CLASS, SAS adds the automatic
/// `_TYPE_` (0 = overall, all-classes = the finest grouping) and `_FREQ_` (obs
/// per group) variables and, unless NWAY, emits every `_TYPE_` level 0…2^k-1
/// (overall … full cross, in _TYPE_ order — BUG-meansouttype-multiclass). Each
/// output stat column computes from its OWN analysis var (BUG-meansoutmulti).
fn buildMeansOutput(arena: std.mem.Allocator, diags: *diag.Diagnostics, lib: *Library, oname: []const u8, ds: *Dataset, ccols: []const usize, bycols: []const usize, by_desc: []const bool, wcol: ?usize, icols: []const usize, out_stats: []const OutStat, nway: bool, emit_meta: bool, vardef: VarDef, order: GroupOrder, descending: bool, alpha: f64, fmt_levels: []const FmtLevels) !void {
    const o = try arena.create(Dataset);
    o.* = Dataset.init(arena, oname);
    for (bycols) |ci| try meansOutCol(diags, o, oname, ds.columns.items[ci].name, ds.columns.items[ci].type);
    // NOTE-freqfmtoutraw: a FORMAT-grouped class col arrives REWRITTEN to label
    // strings (groupFormats). SAS stores the RAW value with the format ATTACHED
    // (the proc must not change the column's TYPE because it carries a format —
    // a downstream read-back/merge sees the descriptor, not the rendering), so
    // declare the ORIGINAL type and attach the format; cells map label→lowest
    // raw at fill time below. An unrewritten col keeps its own type + format.
    const cty = try arena.alloc(VarType, ccols.len);
    for (ccols, 0..) |ci, k| {
        const src = ds.columns.items[ci];
        const fl = fmtLevelsFor(fmt_levels, ci);
        cty[k] = if (fl) |f| f.ty else src.type;
        try meansOutCol(diags, o, oname, src.name, cty[k]);
        const spec = if (fl) |f| f.spec else src.format;
        if (spec) |s| o.columns.items[o.columns.items.len - 1].format = s;
    }
    for (icols) |ci| try meansOutCol(diags, o, oname, ds.columns.items[ci].name, ds.columns.items[ci].type);
    const has_class = ccols.len > 0;
    // MEANS/SUMMARY ALWAYS add _TYPE_/_FREQ_ (0 / obs-per-group with no CLASS) so a
    // downstream _FREQ_/merge finds them (BUG-meansbytypefreq); UNIVARIATE does not.
    if (emit_meta) {
        try meansOutCol(diags, o, oname, "_TYPE_", .num);
        try meansOutCol(diags, o, oname, "_FREQ_", .num);
    }
    for (out_stats) |os| try meansOutCol(diags, o, oname, os.name, .num);
    const meta: usize = if (emit_meta) 2 else 0;
    const nid = icols.len;
    const ncol = bycols.len + ccols.len + nid + meta + out_stats.len;
    const fillStats = struct {
        // each output column computes from its OWN analysis var (os.acol) — a
        // multi-var `output mean=a b` maps a→var1, b→var2 (BUG-meansoutmulti).
        fn f(cells: []Value, base: usize, rows: []const []const Value, wc: ?usize, oss: []const OutStat, vd: VarDef, al: f64) void {
            for (oss, 0..) |os, k| {
                const s = computeStatsV(rows, os.acol, wc, vd);
                const v = if (os.stat == .nmiss) @as(f64, @floatFromInt(nmissCount(rows, os.acol))) else statValueA(os.stat, s, al);
                cells[base + k] = .{ .num = v };
            }
        }
    }.f;
    const bygroups = if (bycols.len > 0) try collectGroups(arena, ds, bycols) else blk: {
        const one = try arena.alloc(MeansGroup, 1);
        one[0] = .{ .rep = if (ds.rows.items.len > 0) ds.rows.items[0] else &.{}, .rows = ds.rows.items };
        break :blk one;
    };
    sortByGroupsByDir(bygroups, bycols, by_desc);
    for (bygroups) |bg| {
        if (!has_class) {
            const cells = try arena.alloc(Value, ncol);
            for (bycols, 0..) |ci, k| cells[k] = bg.rep[ci];
            for (icols, 0..) |ci, k| cells[bycols.len + k] = idMax(ds, bg.rows, ci);
            if (emit_meta) {
                cells[bycols.len + nid] = .{ .num = 0 }; // _TYPE_ = 0 (no CLASS)
                cells[bycols.len + nid + 1] = .{ .num = @floatFromInt(bg.rows.len) }; // _FREQ_
            }
            fillStats(cells, bycols.len + nid + meta, bg.rows, wcol, out_stats, vardef, alpha);
            try o.appendRow(cells);
            continue;
        }
        // One _TYPE_ level per SUBSET of the CLASS vars: _TYPE_ is a bitmask with
        // the LEFTMOST class var as the high bit (so 2 vars g h → 1=by h, 2=by g,
        // 3=g*h). Default emits all 2^k levels (0=overall … 2^k-1=full cross), in
        // _TYPE_ order; NWAY keeps only the full cross (BUG-meansouttype-multiclass).
        const kbits: usize = ccols.len;
        const type_all: u64 = (@as(u64, 1) << @intCast(kbits)) - 1;
        var tp: u64 = if (nway) type_all else 0;
        while (tp <= type_all) : (tp += 1) {
            var subcols: std.ArrayList(usize) = .empty; // the class vars active at this level
            for (ccols, 0..) |ci, j| {
                if ((tp >> @intCast(kbits - 1 - j)) & 1 == 1) try subcols.append(arena, ci);
            }
            const groups = try collectGroupsRows(arena, bg.rows, subcols.items, order);
            if (descending) std.mem.reverse(MeansGroup, groups); // DESCENDING reverses the CLASS levels (BUG-meansoptnoop)
            for (groups) |g| {
                const cells = try arena.alloc(Value, ncol);
                for (bycols, 0..) |ci, k| cells[k] = bg.rep[ci];
                for (ccols, 0..) |ci, k| {
                    const active = (tp >> @intCast(kbits - 1 - k)) & 1 == 1;
                    cells[bycols.len + k] = if (!active) missingOf(cty[k]) else if (fmtLevelsFor(fmt_levels, ci)) |f|
                        (fmtRawFor(f, g.rep[ci].str) orelse missingOf(f.ty)) // label → lowest raw; blank group = missing
                    else
                        g.rep[ci];
                }
                for (icols, 0..) |ci, k| cells[bycols.len + ccols.len + k] = idMax(ds, g.rows, ci);
                if (emit_meta) { // UNIVARIATE passes false: no _TYPE_/_FREQ_ columns (BUG-univclass)
                    cells[bycols.len + ccols.len + nid] = .{ .num = @floatFromInt(tp) };
                    cells[bycols.len + ccols.len + nid + 1] = .{ .num = @floatFromInt(g.rows.len) };
                }
                fillStats(cells, bycols.len + ccols.len + nid + meta, g.rows, wcol, out_stats, vardef, alpha);
                try o.appendRow(cells);
            }
        }
    }
    try lib.put(oname, o);
}

/// Add one OUTPUT column, failing LOUD on a duplicate name — a second same-named
/// column builds a structurally broken dataset (BUG-meansoutdupname; mirrors the
/// PROC SQL CREATE TABLE dup guard).
fn meansOutCol(diags: *diag.Diagnostics, o: *Dataset, oname: []const u8, name: []const u8, ty: VarType) !void {
    if (o.indexOf(name) != null)
        return diags.fail(error.ParseError, 0, "PROC MEANS: duplicate column name {s} in OUTPUT OUT={s}", .{ name, oname });
    _ = try o.addColumn(name, ty);
}

/// The ID value for one output group: SAS carries the MAX the id var attains
/// over the group's obs (a numeric missing never wins) (BUG-meansidnoop).
fn idMax(ds: *const Dataset, rows: []const []const Value, ci: usize) Value {
    var best: ?Value = null;
    for (rows) |r| {
        const v = r[ci];
        if (v.isMissing()) continue;
        if (best == null or cmpValue(best.?, v) == .lt) best = v;
    }
    return best orelse missingOf(ds.columns.items[ci].type);
}

/// OUTPUT OUT= with NO statistics named → SAS's default long-form dataset: the 5
/// default stats (N MIN MAX MEAN STD) as rows keyed by a `_STAT_` char variable,
/// one column per analysis var, `_TYPE_`/`_FREQ_` present (BUG-meansoutnostat).
/// ponytail: no CLASS in this path (the corpus/study use the plain / BY-group
/// form); a CLASS default-output would need the _TYPE_ bitmask rows too.
fn buildMeansOutputDefault(arena: std.mem.Allocator, lib: *Library, oname: []const u8, ds: *Dataset, bycols: []const usize, by_desc: []const bool, acols: []const usize, wcol: ?usize, vardef: VarDef) !void {
    const defs = [_]struct { k: StatKind, nm: []const u8 }{
        .{ .k = .n, .nm = "N" }, .{ .k = .min, .nm = "MIN" }, .{ .k = .max, .nm = "MAX" },
        .{ .k = .mean, .nm = "MEAN" }, .{ .k = .std, .nm = "STD" },
    };
    const o = try arena.create(Dataset);
    o.* = Dataset.init(arena, oname);
    for (bycols) |ci| _ = try o.addColumn(ds.columns.items[ci].name, ds.columns.items[ci].type);
    _ = try o.addColumn("_TYPE_", .num);
    _ = try o.addColumn("_FREQ_", .num);
    _ = try o.addColumn("_STAT_", .char);
    for (acols) |ci| _ = try o.addColumn(ds.columns.items[ci].name, .num);
    const ncol = bycols.len + 3 + acols.len;

    const bygroups = if (bycols.len > 0) try collectGroups(arena, ds, bycols) else blk: {
        const one = try arena.alloc(MeansGroup, 1);
        one[0] = .{ .rep = if (ds.rows.items.len > 0) ds.rows.items[0] else &.{}, .rows = ds.rows.items };
        break :blk one;
    };
    sortByGroupsByDir(bygroups, bycols, by_desc);
    for (bygroups) |bg| {
        for (defs) |d| {
            const cells = try arena.alloc(Value, ncol);
            for (bycols, 0..) |ci, k| cells[k] = bg.rep[ci];
            cells[bycols.len] = .{ .num = 0 }; // _TYPE_
            cells[bycols.len + 1] = .{ .num = @floatFromInt(bg.rows.len) }; // _FREQ_
            cells[bycols.len + 2] = .{ .str = d.nm }; // _STAT_
            for (acols, 0..) |ci, j| {
                const s = computeStatsV(bg.rows, ci, wcol, vardef);
                cells[bycols.len + 3 + j] = .{ .num = statValue(d.k, s) };
            }
            try o.appendRow(cells);
        }
    }
    try lib.put(oname, o);
}

// ── PROC FREQ ────────────────────────────────────────────────────────────────
//
// One-way and two-way frequency tables, reproducing SAS's listing layout by
// absolute column placement (each line is a space-filled buffer we stamp fields
// into, then trim). ponytail: the column geometry is fixed for the default
// widths — small counts, ≤"100.00" percents, short category values (the corpus
// fixtures); a very wide count/value would need SAS's width-growth logic. Title
// centering is hard-set per table shape rather than derived from LINESIZE.

// Titles are centered over each table's own width (SAS varies it by shape), so
// the lead differs: full one-way is widest, the `nocum` table (no cumulative
// columns) is narrowest, two-way in between. ponytail: hard-set per shape rather
// than derived — a wider table (bigger counts) would shift these.
const ONEWAY_TITLE = (" " ** 38) ++ "The FREQ Procedure\n";
const ONEWAY_NOCUM_TITLE = (" " ** 22) ++ "The FREQ Procedure\n";
const TWOWAY_TITLE = (" " ** 24) ++ "The FREQ Procedure\n";
const NLEVELS_TITLE = (" " ** 21) ++ "The FREQ Procedure\n"; // narrow NLEVELS table (BUG-freqnlevels)

/// A PROC FREQ TABLES `/` option that requests an association test, exact test,
/// measure of association, or extra cell statistic we do not compute. These MUST
/// fail loud rather than silently print a table without the requested numbers
/// (FREQ-hardening). Display options we currently tolerate as no-ops (list,
/// nopercent, norow, nocol, nofreq) are deliberately NOT here — ponytail: they
/// change layout only, add them (or honor them) when a fixture needs it.
fn isUnsupportedFreqStat(kw: []const u8) bool {
    inline for (.{
        // association / independence tests
        "chisq", "exact",   "fisher",  "measures", "cmh",      "cmh1",     "cmh2",
        "mhchi", "trend",   "jt",      "all",      "cochran",  "binomial", "plcorr",
        "gamma", "kentb",   "stutc",   "lambda",   "pcorr",    "scorr",    "tsymm",
        // agreement
        "agree", "kappa",   "wtkap",   "mcnem",    "bowker",
        // risk / relative risk
        "relrisk", "riskdiff", "riskdiff1", "riskdiff2",
        // extra cell statistics / output columns we don't render
        "expected", "cellchi2", "deviation", "cumcol", "totpct",
        "crosslist", "sparse",  "outexpect", "outpct", "scores", "testp", "testf",
        "gailsimon",
    }) |o| {
        if (eqi(kw, o)) return true;
    }
    return false;
}

/// The REMAINING documented SAS 9.4 TABLES-statement options beyond
/// isUnsupportedFreqStat's association/exact/cell list — Table 3.9 closes the
/// whole TABLES option set in one place (Base SAS 9.4 Procedures Guide:
/// Statistical Procedures, printed pp. 104-106, === pdf 107/108/109 ===), and
/// NOCUM/MISSING/NOPRINT/NOFREQ/NOPERCENT/NOROW/NOCOL/OUTCUM/LIST/OUT= are
/// handled upstream. Every name here is a recognized gap (rc 2); anything
/// else reaching the catch-all is the user's typo (rc 1), never a false rc 2.
fn isFreqTablesGapOption(kw: []const u8) bool {
    inline for (.{ "alpha", "bin", "cl", "commonriskdiff", "or", "senspec", "missprint", "pearsonres", "printkwts", "scorout", "stdres", "contents", "format", "maxlevels", "nosparse", "nowarn", "plots" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

pub fn runFreq(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var in_name: ?[]const u8 = null;
    var order: FreqOrder = .internal; // ORDER=FREQ|DATA|INTERNAL|FORMATTED (BUG-freqorder)
    var noprint = false; // proc-level or TABLES `/ noprint` — suppress the listing
    var nlevels = false; // proc-level NLEVELS — emit the "Number of Variable Levels" table (BUG-freqnlevels)
    var i: usize = 2; // past `proc freq`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "order")) |v| {
            // ORDER=FREQ|DATA|INTERNAL|FORMATTED — an invalid value must not
            // silently become INTERNAL (BUG-freqweightorder F3; mirrors the
            // PROC MEANS ORDER= validation).
            order = if (eqi(v, "freq")) .freq //
            else if (eqi(v, "data")) .data //
            else if (eqi(v, "internal")) .internal //
            else if (eqi(v, "formatted")) .formatted //
            else return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: ORDER={s} is not valid — expected FREQ, DATA, INTERNAL, or FORMATTED", .{v});
            i += 3;
        } else if (tkKw(toks[i], "noprint")) {
            noprint = true;
            i += 1;
        } else if (tkKw(toks[i], "nlevels")) {
            nlevels = true; // BUG-freqnlevels: was swallowed by the old else's `i += 1`
            i += 1;
        } else if (tkKw(toks[i], "compress") or tkKw(toks[i], "page")) {
            // INERT pagination (SAS 9.4 Proc Guide, PROC FREQ statement):
            // COMPRESS packs one-way tables onto a shared page, PAGE forces a
            // new page per table — a non-paginating batch listing observes
            // neither. Enumerated explicitly so the chain ends in a real else.
            i += 1;
        } else if (optAny(toks, i, "formchar")) |_| {
            i += 3; // INERT: crosstab outline characters — the grid geometry is hard-set.
        } else {
            // GAP-freqlow-tick276 F6 (residual of tick255 F1): the old final
            // else `i += 1`'d ANY token — a typo'd option (`odrer=freq`) or an
            // unsupported real one silently ran with defaults, while the TABLES
            // `/` loop below already failed loud on the same situation
            // (GAP-freqignoreopt). Name the option (D-002).
            // ALREADY-CORRECT at rc 1 (§5b re-verdict): Table 3.4 (Statistical
            // Procedures printed p. 78, === pdf 81 ===) closes the PROC FREQ
            // statement option set at seven — COMPRESS/DATA=/FORMCHAR=/
            // NLEVELS/NOPRINT/ORDER=/PAGE — and every one is handled above,
            // so only invalid SAS (a typo) can reach this arm.
            return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: option {s} is not supported", .{toks[i].text});
        }
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    // `tables v1[*v2*…] [/ nocum missing noprint out=DS];` — 1 var = one-way,
    // 2 = crosstab, ≥3 = per-stratum crosstabs (GAP-freqnway); `weight w;`
    // BUG-freqmultitables: EACH TABLES statement is an independent request —
    // `tables g; tables h;` renders TWO one-way tables, never a merged g*h
    // crosstab. Only `*` WITHIN one statement is a genuine crosstab.
    const FreqRequest = struct {
        vars: std.ArrayList([]const u8) = .empty,
        nocum: bool = false,
        disp: FreqDisp = .{}, // nofreq/nopercent/norow/nocol (FREQ-crosstabpct)
        missing: bool = false, // `/ missing` — include the missing level as a category (BUG-freqmissing)
        out_name: ?[]const u8 = null, // `/ out=DS` — COUNT/PERCENT dataset (GAP-freqnway)
        out_opts: []const Token = &.{}, // out=DS(rename=/keep=…) paren list, applied per request
        outcum: bool = false, // `/ outcum` — CUM_FREQ/CUM_PCT columns in a one-way OUT= (GAP-freqignoreopt)
        list: bool = false, // `/ list` — no-op on one-way (already list form); n-way fails loud (NOTE-freqlistfmt)
        noprint: bool = false, // TABLES `/ noprint` — suppress THIS statement's table
    };
    var requests: std.ArrayList(FreqRequest) = .empty;
    var weight_var: ?[]const u8 = null; // `weight w;` — Frequency = Σweight (BUG-freqweight)
    var weight_zeros = false; // `weight w / zeros;` — re-include zero-weight levels (BUG-freqweightorder F2)
    var fmt_specs: std.ArrayList(VarSpec) = .empty; // `format v spec;` — group by formatted value (NOTE-freqtablesfmt)
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run")) break;
        if (tkKw(toks[i], "tables") or tkKw(toks[i], "table")) {
            i += 1;
            // BUG-freqtablesparen: a TABLES statement holds space-separated
            // REQUESTS (`tables a b;` = a one-way for a AND one for b); each
            // request crosses FACTORS with `*`, and a factor may be a
            // parenthesized variable list that DISTRIBUTES over the crossing
            // (`(a b)*c` = `a*c b*c`; bare `(a b)` = `a b`). Was: the `(` fell
            // through to the out= options branch and the group was silently
            // dropped, rc=0. Crossings INSIDE the parens are refused below.
            var combos: std.ArrayList([]const []const u8) = .empty;
            while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .slash) {
                var factors: std.ArrayList([]const []const u8) = .empty;
                while (true) { // one factor: a name, or a `(` name+ `)` list
                    var names: std.ArrayList([]const u8) = .empty;
                    if (atTag(toks, i, .name)) {
                        // GAP-varcolonprefix-procs: keep a `pfx:` factor as ONE
                        // wire entry — it expands below once the dataset is
                        // known (one-way requests; a `*` crossing stays loud).
                        try appendVarListName(arena, toks, &i, &names);
                        i += 1;
                    } else if (atTag(toks, i, .lparen)) {
                        i += 1;
                        while (atTag(toks, i, .name)) {
                            try names.append(arena, toks[i].text);
                            i += 1;
                        }
                        if (names.items.len == 0 or !atTag(toks, i, .rparen))
                            return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: only a plain variable list is supported inside '()' in the TABLES statement", .{});
                        i += 1; // past `)`
                    } else return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: expected a variable in the TABLES statement", .{});
                    try factors.append(arena, names.items);
                    if (atTag(toks, i, .star)) {
                        // NOTE-freqdanglingcross: `tables g*;` / `g* / opt;` — a
                        // dangling crosstab operator. SAS errors; silently degrading
                        // to a one-way table on g is the clinical worst class.
                        if (!atTag(toks, i + 1, .name) and !atTag(toks, i + 1, .lparen))
                            return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: expected a variable after '*' in the TABLES statement", .{});
                        i += 1;
                    } else break;
                }
                // Distribute the factors: one crossing per combination.
                var expanded: std.ArrayList([]const []const u8) = .empty;
                try expanded.append(arena, &.{});
                for (factors.items) |names| {
                    var next: std.ArrayList([]const []const u8) = .empty;
                    for (expanded.items) |c|
                        for (names) |n| {
                            const nc = try arena.alloc([]const u8, c.len + 1);
                            @memcpy(nc[0..c.len], c);
                            nc[c.len] = n;
                            try next.append(arena, nc);
                        };
                    expanded = next;
                }
                try combos.appendSlice(arena, expanded.items);
            }
            var req = FreqRequest{};
            // options after `/`
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .lparen) {
                    req.out_opts = toks[i + 1 .. skipParen(toks, i) - 1]; // out=X(rename=…)
                    i = skipParen(toks, i) - 1;
                    continue;
                }
                if (toks[i].tag != .name) continue; // the `/` itself
                if (tkKw(toks[i], "nocum")) { req.nocum = true; continue; }
                if (tkKw(toks[i], "missing")) { req.missing = true; continue; }
                if (tkKw(toks[i], "noprint")) { req.noprint = true; continue; }
                if (tkKw(toks[i], "nofreq")) { req.disp.nofreq = true; continue; }
                if (tkKw(toks[i], "nopercent")) { req.disp.nopercent = true; continue; }
                if (tkKw(toks[i], "norow")) { req.disp.norow = true; continue; }
                if (tkKw(toks[i], "nocol")) { req.disp.nocol = true; continue; }
                if (tkKw(toks[i], "outcum")) { req.outcum = true; continue; }
                // LIST: a DOCUMENTED no-op on a ONE-way table — the SAS 9.4
                // PROC FREQ TABLES-statement doc scopes LIST to "two-way to
                // n-way tables" (a one-way table is list-form already), so
                // there is no layout to change (GAP-tableopt; the audit's
                // "accepted but INERT" is the doc's own semantics, cited).
                // On an n-way request the listing would have to switch from
                // the grid to the one-row-per-cell list layout — not modeled,
                // so the render loop fails loud instead of silently
                // substituting the grid (NOTE-freqlistfmt, tick221 F4's fix).
                if (tkKw(toks[i], "list")) { req.list = true; continue; }
                if (optAt(toks, i, "out")) |v| {
                    req.out_name = v;
                    i += 2; // past `= NAME`; a trailing `(rename=…)` is the lparen branch's
                } else if (isUnsupportedFreqStat(toks[i].text)) {
                    // Association / exact / cell-statistic options aren't computed.
                    // Silently ignoring `/ chisq` (etc.) emits a table WITHOUT the
                    // requested statistics — a silent drop of requested analysis, the
                    // clinical worst class. Fail loud (FREQ-hardening). The guard is
                    // a closed list of documented SAS 9.4 TABLES options, so every
                    // hit is a recognized gap (rc 2) — a typo can't be in the list.
                    return failGap(diags, toks[i].line, "PROC FREQ: TABLES option {s} (association/exact/cell statistics) is not yet supported — refusing to emit a table without the requested statistics", .{toks[i].text});
                } else if (isFreqTablesGapOption(toks[i].text)) {
                    // The rest of Table 3.9's closed set (MISSPRINT, NOSPARSE,
                    // PLOTS=, ALPHA=, …) — documented but unimplemented, so a
                    // recognized gap (rc 2); the message stays byte-identical.
                    return failGap(diags, toks[i].line, "PROC FREQ: TABLES option {s} is not supported", .{toks[i].text});
                } else {
                    // GAP-freqignoreopt: an unrecognized TABLES option is a typo or a
                    // real-but-unsupported option — silently dropping it hid both.
                    // Fail loud (house rule), like PROC PRINT's option scan (F4).
                    return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: TABLES option {s} is not supported", .{toks[i].text});
                }
            }
            for (combos.items) |vars| { // one independent request per expansion
                var r = req; // share the statement's `/` options
                try r.vars.appendSlice(arena, vars);
                try requests.append(arena, r);
            }
        } else if (tkKw(toks[i], "weight")) {
            i += 1; // `weight w;` — the (single) weight variable
            if (atTag(toks, i, .name)) {
                weight_var = toks[i].text;
                i += 1;
            }
            // `weight w / zeros;` — ZEROS re-includes zero-weight levels (SAS
            // drops them by default). Any other WEIGHT option is a typo or
            // unsupported: fail loud like the TABLES option scan
            // (BUG-freqweightorder F2) — silently swallowing it hid both.
            if (atTag(toks, i, .slash)) {
                i += 1;
                while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                    if (toks[i].tag != .name) continue;
                    if (tkKw(toks[i], "zeros")) {
                        weight_zeros = true;
                        continue;
                    }
                    return diags.fail(error.ParseError, toks[i].line, "PROC FREQ: WEIGHT option {s} is not supported — expected ZEROS", .{toks[i].text});
                }
            }
        } else if (tkKw(toks[i], "format")) {
            try parseProcFormat(arena, toks, &i, &fmt_specs); // leaves i at the `;`
        } else if (tkKw(toks[i], "by")) {
            // BY-group FREQ isn't modeled (per-group tables); silently ignoring
            // it emitted ONE global table — silent wrong output
            // (PROCBY-printfreq). FAIL LOUD until per-group tables exist. BY is a
            // valid SAS 9.4 PROC FREQ statement → a gap (rc 2), not the user's 1.
            return failGap(diags, toks[i].line, "PROC FREQ: BY-group processing is not yet supported", .{});
        } else if (tkKw(toks[i], "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1; // procInput applies it
        } else if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            // D-014a mid-step globals: skip exactly what the top level HANDLES
            // mid-step (see runSort's arm for the full note).
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (tkKw(toks[i], "exact") or tkKw(toks[i], "output") or tkKw(toks[i], "test")) {
            // EXACT/OUTPUT/TEST are valid SAS 9.4 PROC FREQ statements we don't
            // model — an opensas gap (rc 2), never lumped with a typo'd name.
            return failGap(diags, toks[i].line, "PROC FREQ statement {s} is not supported", .{toks[i].text});
        } else if (toks[i].tag == .name) {
            // D-002 fail-loud (GAP-procsubstmtswallow): an unknown sub-statement
            // used to vanish via `else i += 1` while this PROC's TABLES `/`
            // option scan already errored on the same class (GAP-freqignoreopt).
            return diags.fail(error.ParseError, toks[i].line, "PROC FREQ statement {s} is not supported", .{toks[i].text});
        } else i += 1;
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC FREQ: no input dataset");
        return;
    };
    var ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)
    // GAP-varcolonprefix-procs: expand `pfx:` factors now that the dataset is
    // known (PDV order — see expandVarPrefixes). A ONE-WAY request position is
    // an ordinary variable list (`tables x:` ≡ `tables x1 x2;`, one table
    // each) — the unambiguous case. A prefix inside a `*` crossing (the
    // request's vars.len > 1 here: only `*` joins factors into one request) is
    // NOT settled by the doc — Statistical Procedures 6th ed. printed p.103
    // (TABLES requests) and its Table 3.8 document grouping syntax
    // distributing PARENTHESIZED and NAME-RANGE lists over crossings, never
    // the name-prefix form — so the crossing stays LOUD (rc 2 gap), never
    // guessed.
    var exreqs: std.ArrayList(FreqRequest) = .empty;
    for (requests.items) |r| {
        var has_pfx = false;
        for (r.vars.items) |vn| {
            if (vn.len > 0 and vn[vn.len - 1] == ':') {
                has_pfx = true;
                break;
            }
        }
        if (!has_pfx) {
            try exreqs.append(arena, r);
            continue;
        }
        if (r.vars.items.len > 1)
            return failGap(diags, toks[0].line, "PROC FREQ: a name prefix (x:) inside a TABLES '*' crossing is not supported — the doc settles grouping for '(a b)' and name-range lists only (Statistical Procedures 6th ed. p.103 Table 3.8)", .{});
        const expanded = try expandVarPrefixes(arena, ds, r.vars.items, diags, toks[0].line, "PROC FREQ");
        for (expanded) |vn| { // one independent one-way request per match
            var nr = r; // shares the statement's `/` options
            const one = try arena.alloc([]const u8, 1);
            one[0] = vn;
            nr.vars = .{ .items = one, .capacity = 1 };
            try exreqs.append(arena, nr);
        }
    }
    requests = exreqs;
    var n_vars: usize = 0;
    for (requests.items) |r| n_vars += r.vars.items.len;
    if (n_vars == 0) {
        unsupported("PROC FREQ without a TABLES statement");
        return;
    }
    var fmt_levels: std.ArrayList(FmtLevels) = .empty; // raw-value order per format-grouped col (BUG-freqfmtorder)
    { // FORMAT on a TABLES var → group + display by the formatted value
        var tvars: std.ArrayList([]const u8) = .empty;
        for (requests.items) |r| for (r.vars.items) |vn| try tvars.append(arena, vn);
        ds = try groupFormats(arena, ds, tvars.items, fmt_specs.items, &fmt_levels, diags);
    }
    // A named-but-absent weight var errors (BUG-weightvarcheck).
    const wcol: ?usize = try resolveWeightCol(ds, weight_var, diags, toks[0].line);
    var rendered = false; // blank line between successive tables (nWayFreq's separator)
    if (nlevels and !noprint) {
        // NLEVELS prints BEFORE the frequency tables (SAS ordering). Each TABLES
        // variable appears once, in first-appearance order, even across multiple
        // or crossed (`a*b`) requests.
        var nlvars: std.ArrayList([]const u8) = .empty;
        for (requests.items) |r| for (r.vars.items) |vn| {
            for (nlvars.items) |e| {
                if (eqi(e, vn)) break;
            } else try nlvars.append(arena, vn);
        };
        if (nlvars.items.len > 0) {
            try freqNLevels(arena, out, ds, nlvars.items, order, wcol, weight_zeros, fmt_levels.items);
            rendered = true;
        }
    }
    for (requests.items) |*req| {
        if (req.vars.items.len == 0) continue; // a bare `tables;` contributes nothing (merged-list behavior)
        const vcols = try arena.alloc(usize, req.vars.items.len);
        for (req.vars.items, 0..) |vn, k| vcols[k] = ds.indexOf(vn) orelse {
            unsupported("PROC FREQ: TABLES variable not found");
            return;
        };
        if (req.out_name) |on| {
            try buildFreqOutput(arena, lib, on, ds, vcols, wcol, weight_zeros, req.missing, req.outcum, fmt_levels.items);
            // out=X(rename=/keep=…) — SDTM PC programs rename COUNT; the paren list was
            // captured from THIS statement's `/` options (applyDatasetOptions's)
            if (lib.find(on)) |od| if (req.out_opts.len > 0) try io.applyDatasetOptions(arena, od, req.out_opts, diags, false);
        }
        if (noprint or req.noprint) continue;
        // NOTE-freqlistfmt: `/ list` on an n-way table must render SAS's
        // one-row-per-cell list layout; we only have the grid. Fail loud (house
        // rule) rather than silently emit the wrong layout. One-way is already
        // list form; OUT= datasets are unaffected by LIST either way.
        // GAP-ebnfrcwrongclass: LIST is a DOCUMENTED TABLES option — Table 3.9
        // (Base SAS 9.4 Procedures Guide: Statistical Procedures, printed
        // p.105, === pdf 108 ===: "LIST Displays two-way to n-way tables in
        // list format") — so refusing it is OUR gap, rc 2 (D-009/D-009b(i)),
        // not rc 1 "your SAS is broken"; the message already NAMES list.
        if (req.list and req.vars.items.len > 1)
            return failGap(diags, 0, "PROC FREQ: TABLES option list (n-way list layout) is not yet supported — refusing to emit the crosstab grid in its place", .{});
        if (rendered) try out.append(arena, '\n');
        switch (req.vars.items.len) {
            1 => try oneWayFreq(arena, out, ds, req.vars.items[0], req.nocum, wcol, weight_zeros, req.missing, order, req.disp.nopercent, fmt_levels.items),
            2 => try twoWayFreq(arena, out, ds, req.vars.items[0], req.vars.items[1], order, wcol, weight_zeros, 0, null, req.disp, req.missing, fmt_levels.items),
            else => try nWayFreq(arena, out, ds, req.vars.items, vcols, order, wcol, weight_zeros, req.disp, req.missing, fmt_levels.items),
        }
        rendered = true;
    }
}

/// PROC FREQ `NLEVELS` (proc-statement option, BUG-freqnlevels): the "Number of
/// Variable Levels" table — one row per analysis variable, `Levels` = the count
/// of DISTINCT non-missing values (SAS default: a missing value is NOT counted as
/// a level unless the MISSING option is set). Reuses oneWayLevels so the count is
/// exactly what the frequency table lists. Printed BEFORE the frequency tables.
/// ponytail: layout follows the tick255 doc reference (title/subtitle centering,
/// Variable left @col12 | Levels right-edge @col29, no header rule); exact
/// LINESIZE-derived centering and any header rule are best-effort pending live SAS.
fn freqNLevels(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, vars: []const []const u8, order: FreqOrder, wcol: ?usize, zeros: bool, fmt_levels: []const FmtLevels) !void {
    try out.appendSlice(arena, NLEVELS_TITLE);
    try out.append(arena, '\n');
    { // "Number of Variable Levels" subtitle
        const b = try line(arena, 45);
        putLeft(b, 17, "Number of Variable Levels");
        try flush(arena, out, b);
    }
    try out.append(arena, '\n');
    { // column headers: Variable (left @col 12) | Levels (right edge @col 29)
        const b = try line(arena, 45);
        putLeft(b, 12, "Variable");
        putRight(b, 29, "Levels");
        try flush(arena, out, b);
    }
    for (vars) |vn| {
        const col = ds.indexOf(vn) orelse continue; // the render loop reports a missing var
        const cats = try oneWayLevels(arena, ds, col, false, order, wcol, zeros, fmtLevelsFor(fmt_levels, col));
        const b = try line(arena, 45);
        putLeft(b, 12, vn);
        putRight(b, 29, try std.fmt.allocPrint(arena, "{d}", .{cats.len}));
        try flush(arena, out, b);
    }
}

/// PROC FREQ crosstab display-suppression options (FREQ-crosstabpct). Each is an
/// independent SAS TABLES option: NOFREQ drops cell frequencies, NOPERCENT drops
/// the cell percent (of the whole table), NOROW drops row percents, NOCOL drops
/// column percents. (Real SAS: NOPERCENT suppresses only the cell percent, not
/// row/col — those have their own options.)
const FreqDisp = struct {
    nofreq: bool = false,
    nopercent: bool = false,
    norow: bool = false,
    nocol: bool = false,
};

/// `tables a*…*y*z` (n ≥ 3): SAS prints one y×z crosstab per distinct level
/// combination of the leading n-2 variables, headed `Table N of y by z` and
/// `Controlling for a=… …`. Strata honor the proc's ORDER= (BUG-freqstrataorder);
/// an obs missing in a controlling variable belongs to no stratum (SAS default).
fn nWayFreq(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, vars: []const []const u8, vcols: []const usize, order: FreqOrder, wcol: ?usize, zeros: bool, disp: FreqDisp, keep_missing: bool, fmt_levels: []const FmtLevels) !void {
    const scols = vcols[0 .. vcols.len - 2];
    // Strata walk in the requested ORDER= (FREQ → descending stratum size, DATA
    // → first appearance); FORMATTED folds to ascending as in oneWayLevels (the
    // cells already hold label text). ponytail: FREQ counts ROWS per stratum,
    // not weights — switch to a weighted sort if a weighted golden needs it.
    const strata_order: GroupOrder = switch (order) {
        .internal, .formatted => .internal,
        .data => .data,
        .freq => .freq,
    };
    const strata = try collectGroupsRows(arena, ds.rows.items, scols, strata_order);
    var tno: usize = 0;
    next_stratum: for (strata) |st| {
        // BUG-freqmissingstrata: under /MISSING a missing control value is its
        // own stratum (SAS prints "Controlling for a=."); default still drops it.
        if (!keep_missing) for (scols) |ci| if (isFreqMissing(st.rep[ci])) continue :next_stratum;
        // GAP-freqlow-tick276 F5: a stratum whose obs ALL have zero weight has
        // NO observations (zero-weight obs are excluded by default — the same
        // weightKeepsRow rule the cells/levels apply), so SAS prints no table
        // for it. Rendering one anyway produced a phantom empty grid with a
        // nonsensical "Total 0 / 100.00" a reader cannot tell from a real
        // result. Skip the stratum; `weight w / zeros` re-includes it.
        if (wcol != null and !zeros) {
            var any = false;
            for (st.rows) |r| if (weightKeepsRow(r, wcol, false)) {
                any = true;
                break;
            };
            if (!any) continue :next_stratum;
        }
        tno += 1;
        if (tno > 1) try out.append(arena, '\n');
        // stratum view: same schema, only this stratum's rows (cells are arena-
        // owned and immutable, so sharing them is safe — the dupDataset precedent)
        const sub = try arena.create(Dataset);
        sub.* = Dataset.init(arena, ds.name);
        for (ds.columns.items) |c| try sub.columns.append(arena, c);
        for (st.rows) |r| try sub.rows.append(arena, r);
        var ctl: std.ArrayList(u8) = .empty;
        try ctl.appendSlice(arena, "Controlling for");
        for (scols, 0..) |ci, k| try ctl.appendSlice(arena, try std.fmt.allocPrint(arena, " {s}={s}", .{ vars[k], try cellText(arena, st.rep[ci]) }));
        try twoWayFreq(arena, out, sub, vars[vars.len - 2], vars[vars.len - 1], order, wcol, zeros, tno, ctl.items, disp, keep_missing, fmt_levels);
    }
}

/// TABLES `/ OUT=` — the frequency dataset: the TABLES variables (in request
/// order), then COUNT and PERCENT (SAS's column order). One observation per
/// OBSERVED level combination, ascending — zero cells are absent (no SPARSE),
/// and a combination seen ONLY on zero-weight obs is absent too unless
/// `weight w / zeros` re-includes it (BUG-freqoutzerocount; same weightKeepsRow
/// filter the listing applies, so listing and OUT= agree). PERCENT is of the
/// whole table for one/two-way requests and of the stratum's two-way table for
/// n-way, mirroring the printed percents. ponytail: OUT= rows are always
/// value-ordered; ORDER=FREQ/DATA reordering of OUT= isn't wired.
fn buildFreqOutput(arena: std.mem.Allocator, lib: *Library, oname: []const u8, ds: *Dataset, vcols: []const usize, wcol: ?usize, zeros: bool, keep_missing: bool, outcum: bool, fmt_levels: []const FmtLevels) !void {
    const o = try arena.create(Dataset);
    o.* = Dataset.init(arena, oname);
    // NOTE-freqfmtoutraw: same raw-value+attached-format rule as MEANS — a
    // format-grouped TABLES col is declared with its ORIGINAL type and the
    // format attached; cells map label→lowest raw at fill time below.
    for (vcols) |ci| {
        const src = ds.columns.items[ci];
        _ = try o.addColumn(src.name, if (fmtLevelsFor(fmt_levels, ci)) |f| f.ty else src.type);
        if (fmtLevelsFor(fmt_levels, ci)) |f| o.columns.items[o.columns.items.len - 1].format = f.spec;
    }
    _ = try o.addColumn("COUNT", .num);
    _ = try o.addColumn("PERCENT", .num);
    // `/ outcum` (GAP-freqignoreopt): CUM_FREQ/CUM_PCT running totals. SAS scopes
    // OUTCUM to one-way OUT= datasets — an n-way table ignores it there too.
    const cum = outcum and vcols.len == 1;
    if (cum) {
        _ = try o.addColumn("CUM_FREQ", .num);
        _ = try o.addColumn("CUM_PCT", .num);
    }

    // SAS default: an obs missing in ANY tables variable is excluded from the
    // cells and the percent base; `/ missing` re-includes those levels.
    var rows: std.ArrayList([]const Value) = .empty;
    next_row: for (ds.rows.items) |r| {
        if (!keep_missing) for (vcols) |ci| if (isFreqMissing(r[ci])) continue :next_row;
        if (!weightKeepsRow(r, wcol, zeros)) continue; // zero-weight-only combos form no OUT= row (BUG-freqoutzerocount)
        try rows.append(arena, r);
    }
    const groups = try collectGroupsRows(arena, rows.items, vcols, .internal);
    const counts = try arena.alloc(f64, groups.len);
    for (groups, 0..) |g, k| {
        var c: f64 = 0;
        for (g.rows) |r| c += rowWeight(r, wcol);
        counts[k] = c;
    }
    const scols = if (vcols.len > 2) vcols[0 .. vcols.len - 2] else vcols[0..0];
    // percent base = the group's stratum total. Sum per stratum once (PERF-groupscan)
    // instead of re-scanning every group per group. Empty scols (1-/2-way tables) ⇒
    // all groups hash to one key ⇒ denom = grand total, uniformly.
    var strata: std.HashMapUnmanaged([]const Value, f64, GroupKeyCtx, std.hash_map.default_max_load_percentage) = .empty;
    const sctx = GroupKeyCtx{ .ccols = scols };
    for (groups, 0..) |g, k| {
        const e = try strata.getOrPutContext(arena, g.rep, sctx);
        e.value_ptr.* = (if (e.found_existing) e.value_ptr.* else 0) + counts[k];
    }
    var cum_freq: f64 = 0;
    for (groups, 0..) |g, k| {
        const denom = strata.getContext(g.rep, sctx).?;
        const cells = try arena.alloc(Value, vcols.len + 2 + 2 * @as(usize, @intFromBool(cum)));
        for (vcols, 0..) |ci, j| cells[j] = if (fmtLevelsFor(fmt_levels, ci)) |f|
            (fmtRawFor(f, g.rep[ci].str) orelse missingOf(f.ty)) // label → lowest raw; blank group = missing
        else
            g.rep[ci];
        cells[vcols.len] = .{ .num = counts[k] };
        cells[vcols.len + 1] = .{ .num = ratioF(counts[k], denom) };
        if (cum) {
            cum_freq += counts[k];
            cells[vcols.len + 2] = .{ .num = cum_freq };
            cells[vcols.len + 3] = .{ .num = ratioF(cum_freq, denom) };
        }
        try o.appendRow(cells);
    }
    try lib.put(oname, o);
}

/// Weighted frequency of `cat` in `col`: the sum of the WEIGHT column over rows
/// equal to `cat` (each row counts 1 when `wcol` is null). Non-positive/missing
/// weights are excluded, as SAS PROC FREQ does (BUG-freqweight).
/// A FREQ level plus its one-pass accumulated weighted count (PERF-freqoneway).
const LevelCount = struct { v: Value, w: f64 };

/// Hash/eql on a single FREQ cell, kept consistent with `cmpValue == .eq`:
/// chars hash right-trimmed (cmpStr blank-pads), numerics canonicalize -0/+0
/// and hash a NaN by its missingRank (._ < . < .A < … groups like cmpNum).
const LevelValueCtx = struct {
    pub fn hash(_: LevelValueCtx, v: Value) u64 {
        var h = std.hash.Wyhash.init(0);
        switch (v) {
            .str => |s| h.update(std.mem.trimEnd(u8, s, " ")),
            .num => |x| {
                if (std.math.isNan(x)) {
                    h.update(&[_]u8{Value.missingRank(x)});
                } else {
                    const canon: f64 = if (x == 0) 0.0 else x;
                    const bits: u64 = @bitCast(canon);
                    h.update(std.mem.asBytes(&bits));
                }
            },
        }
        return h.final();
    }
    pub fn eql(_: LevelValueCtx, a: Value, b: Value) bool {
        return cmpValue(a, b) == .eq;
    }
};

/// PERF-freqoneway: ONE pass over the rows — each kept cell is hashed once, a
/// new level appended on first sight, its weighted count accumulated (the sum
/// catWeight used to rescan the whole table for). The old distinctSorted
/// (linear dedup scan per row) + per-level catWeight (full rescan per level)
/// was O(N·L) — measured 5.2× time per 2× N. The count for a level adds the
/// same row weights in the same row order as catWeight did, and the sorts are
/// the old comparators verbatim, so output (totals/cumulatives included) is
/// byte-identical.
fn oneWayLevels(arena: std.mem.Allocator, ds: *Dataset, col: usize, keep_missing: bool, order: FreqOrder, wcol: ?usize, zeros: bool, fl: ?FmtLevels) ![]LevelCount {
    var list: std.ArrayList(LevelCount) = .empty;
    var idx: std.HashMapUnmanaged(Value, usize, LevelValueCtx, std.hash_map.default_max_load_percentage) = .empty;
    for (ds.rows.items) |r| {
        const v = r[col];
        if (!keep_missing and isFreqMissing(v)) continue; // missing is not a category (unless `/ missing`)
        if (!weightKeepsRow(r, wcol, zeros)) continue; // zero-weight obs form no level by default (BUG-freqweightorder F2)
        const gop = try idx.getOrPut(arena, v);
        if (!gop.found_existing) {
            gop.value_ptr.* = list.items.len;
            try list.append(arena, .{ .v = v, .w = 0 });
        }
        list.items[gop.value_ptr.*].w += rowWeight(r, wcol);
    }
    const cats = list.items;
    switch (order) {
        .data => {}, // keep first-appearance order — no sort
        .internal, .formatted => std.mem.sort(LevelCount, cats, {}, struct {
            fn less(_: void, l: LevelCount, r: LevelCount) bool {
                return cmpValue(l.v, r.v) == .lt;
            }
        }.less),
        .freq => {
            // descending weighted count; ties break by ascending value (SAS), or
            // by raw-value rank for a VALUE.-format group (BUG-freqfmtorderfreqtie).
            const FreqCtx = struct {
                fl: ?FmtLevels,
                fn less(self: @This(), l: LevelCount, r: LevelCount) bool {
                    if (l.w != r.w) return l.w > r.w;
                    if (self.fl) |f| return fmtRank(f, valStr(l.v)) < fmtRank(f, valStr(r.v));
                    return cmpValue(l.v, r.v) == .lt;
                }
            };
            std.mem.sort(LevelCount, cats, FreqCtx{ .fl = fl }, FreqCtx.less);
        },
    }
    return cats;
}

/// catWeight re-scans the whole table per level — only the n-way path still
/// uses it. One-way levels carry their count from oneWayLevels (PERF-freqoneway).
fn catWeight(ds: *Dataset, col: usize, cat: Value, wcol: ?usize) f64 {
    // both indices read a cell on every row — out-of-range = a silently wrong
    // frequency count, not a crash (TASTE-asserts).
    assert(col < ds.columns.items.len);
    if (wcol) |wc| assert(wc < ds.columns.items.len);
    var sum: f64 = 0;
    for (ds.rows.items) |r| {
        if (cmpValue(r[col], cat) != .eq) continue;
        sum += rowWeight(r, wcol);
    }
    return sum;
}

/// A row's weight: the WEIGHT column value if positive, else 0 (excluded); 1 when
/// there is no WEIGHT statement.
fn rowWeight(r: []const Value, wcol: ?usize) f64 {
    const wc = wcol orelse return 1;
    const w = switch (r[wc]) {
        .num => |x| x,
        .str => std.math.nan(f64),
    };
    return if (!std.math.isNan(w) and w > 0) w else 0;
}

fn ratioF(part: f64, whole: f64) f64 {
    return if (whole == 0) 0 else part / whole * 100.0;
}

/// Frequency text: a whole weighted count renders as an integer (the usual case,
/// including unweighted); a fractional weight sum renders via BEST12.
fn freqText(arena: std.mem.Allocator, x: f64) ![]const u8 {
    if (x == @trunc(x) and @abs(x) < 1e15) return std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))});
    return format.bestNum(arena, x);
}

fn oneWayFreq(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, varname: []const u8, nocum: bool, wcol: ?usize, zeros: bool, keep_missing: bool, order: FreqOrder, nopercent: bool, fmt_levels: []const FmtLevels) !void {
    const col = ds.indexOf(varname) orelse {
        unsupported("PROC FREQ: TABLES variable not found");
        return;
    };
    // Default: missing is not a category (percents over non-missing, a
    // `Frequency Missing = n` line below). `/ missing` re-includes it as a level
    // (percents over the full total, no trailing line) — BUG-freqmissing.
    const cats = try oneWayLevels(arena, ds, col, keep_missing, order, wcol, zeros, fmtLevelsFor(fmt_levels, col));
    // raw-value order for VALUE.-format groups (BUG-freqfmtorder)
    if (order == .internal) if (fmtLevelsFor(fmt_levels, col)) |f| {
        std.mem.sort(LevelCount, cats, f, struct {
            fn less(c: FmtLevels, l: LevelCount, r: LevelCount) bool {
                return fmtRank(c, valStr(l.v)) < fmtRank(c, valStr(r.v));
            }
        }.less);
    };
    var total: f64 = 0;
    for (cats) |c| total += c.w;
    // All-missing TABLES variable: no levels to list, but SAS still "displays
    // the number of missing observations following each table" (Base SAS 9.4
    // Procedures Guide: Statistical Procedures, FREQ "Missing Values", p.156) —
    // the count line prints even when the table itself is empty (NOTE-
    // freqallmissnone). An empty or all-zero-weight table has no missing obs →
    // the line is a no-op. Whether SAS also prints the table SHELL here is not
    // settled by the chapter — we print no shell, matching the zero-weight "no
    // phantom empty table" call (GAP-freqlow-tick276 F5).
    //
    // NOTE-freqallmissnoheader, searched and still DOC-SILENT: the bare
    // `Frequency Missing = n` line also carries NO "The FREQ Procedure" heading,
    // which looks like an omission but is the SAME unsettled question, not a new
    // one — that heading is emitted from inside the table body below (ONEWAY_TITLE),
    // so there is no header without a shell to hang it on. No volume prints an
    // all-missing FREQ output: the chapter's only Missing Values example (Figure
    // 3.12, printed pp.156–157) has two nonmissing levels, and "displays the number
    // of missing observations following each table" (p.156) says where the count
    // goes relative to a table, not what happens when there is none. Deliberately
    // NOT pinned by a test — asserting the heading's absence would freeze a
    // doc-silent guess and make a future correct fix look like a regression.
    if (total == 0) {
        if (!keep_missing) try appendFreqMissing(arena, out, freqMissingWeight(ds, &.{col}, wcol));
        return;
    }

    // NOPERCENT drops the Percent columns (and, with NOCUM, everything but
    // Frequency). ponytail: column geometry for these variants is best-effort SAS
    // — the common default/NOCUM paths are unchanged (FREQ-crosstabpct/displayopts).
    if (nopercent) return oneWayFreqNoPercent(arena, out, ds, col, varname, cats, keep_missing, nocum, wcol);
    if (nocum) return oneWayFreqNoCum(arena, out, ds, col, varname, cats, total, keep_missing, wcol);

    try out.appendSlice(arena, ONEWAY_TITLE);
    try out.append(arena, '\n');
    { // "Cumulative   Cumulative" super-header
        const b = try line(arena, 72);
        putLeft(b, 43, "Cumulative");
        putLeft(b, 57, "Cumulative");
        try flush(arena, out, b);
    }
    { // column headers
        const b = try line(arena, 72);
        putLeft(b, 15, varname);
        putLeft(b, 22, "Frequency");
        putLeft(b, 36, "Percent");
        putLeft(b, 48, "Frequency");
        putLeft(b, 63, "Percent");
        try flush(arena, out, b);
    }
    { // rule: cols 15–69
        const b = try line(arena, 72);
        for (14..69) |k| b[k] = '-';
        try flush(arena, out, b);
    }
    var cum: f64 = 0;
    for (cats) |c| {
        const cnt = c.w;
        cum += cnt;
        const pct = ratioF(cnt, total);
        const cpct = ratioF(cum, total);
        const b = try line(arena, 72);
        putLeft(b, 15, try cellText(arena, c.v));
        putRight(b, 30, try freqText(arena, cnt));
        putRight(b, 42, try pctText(arena, pct));
        putRight(b, 57, try freqText(arena, cum));
        putRight(b, 70, try pctText(arena, cpct));
        try flush(arena, out, b);
    }
    if (!keep_missing) try appendFreqMissing(arena, out, freqMissingWeight(ds, &.{col}, wcol));
}

/// SAS prints `Frequency Missing = N` after the table when the TABLES
/// variable(s) had any missing values (a no-op when there were none). N is the
/// WEIGHTED frequency under a WEIGHT statement — the chapter's own worked
/// example counts one missing obs with Freq=2 as `Frequency Missing = 2`
/// (Figure 3.12, p.157).
fn appendFreqMissing(arena: std.mem.Allocator, out: *std.ArrayList(u8), miss: f64) !void {
    if (miss == 0) return;
    try out.append(arena, '\n');
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "{s}Frequency Missing = {s}\n", .{ " " ** 6, try freqText(arena, miss) }));
}

/// `tables v / nocum;` — Frequency + Percent only (no cumulative pair, no super-
/// header). The narrower table shifts the title and the column headers.
fn oneWayFreqNoCum(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, col: usize, varname: []const u8, cats: []const LevelCount, total: f64, keep_missing: bool, wcol: ?usize) !void {
    try out.appendSlice(arena, ONEWAY_NOCUM_TITLE);
    try out.append(arena, '\n');
    { // column headers
        const b = try line(arena, 52);
        putLeft(b, 15, varname);
        putLeft(b, 24, "Frequency");
        putLeft(b, 38, "Percent");
        try flush(arena, out, b);
    }
    { // rule: cols 15–47
        const b = try line(arena, 52);
        for (14..47) |k| b[k] = '-';
        try flush(arena, out, b);
    }
    for (cats) |c| {
        const b = try line(arena, 52);
        putLeft(b, 15, try cellText(arena, c.v));
        putRight(b, 30, try freqText(arena, c.w));
        putRight(b, 42, try pctText(arena, ratioF(c.w, total)));
        try flush(arena, out, b);
    }
    if (!keep_missing) try appendFreqMissing(arena, out, freqMissingWeight(ds, &.{col}, wcol));
}

/// `tables v / nopercent;` — Frequency (+ Cumulative Frequency unless NOCUM), no
/// Percent columns. ponytail: geometry is best-effort SAS (Cumulative Frequency
/// placed compactly beside Frequency) pending gate verification against real SAS.
fn oneWayFreqNoPercent(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, col: usize, varname: []const u8, cats: []const LevelCount, keep_missing: bool, nocum: bool, wcol: ?usize) !void {
    try out.appendSlice(arena, ONEWAY_NOCUM_TITLE);
    try out.append(arena, '\n');
    if (!nocum) { // "Cumulative" super-header over the Cumulative Frequency column
        const b = try line(arena, 52);
        putLeft(b, 36, "Cumulative");
        try flush(arena, out, b);
    }
    { // column headers
        const b = try line(arena, 52);
        putLeft(b, 15, varname);
        putLeft(b, 22, "Frequency");
        if (!nocum) putLeft(b, 36, "Frequency");
        try flush(arena, out, b);
    }
    { // rule
        const b = try line(arena, 52);
        const end: usize = if (nocum) 30 else 45;
        for (14..end) |k| b[k] = '-';
        try flush(arena, out, b);
    }
    var cum: f64 = 0;
    for (cats) |c| {
        cum += c.w;
        const b = try line(arena, 52);
        putLeft(b, 15, try cellText(arena, c.v));
        putRight(b, 30, try freqText(arena, c.w));
        if (!nocum) putRight(b, 45, try freqText(arena, cum));
        try flush(arena, out, b);
    }
    if (!keep_missing) try appendFreqMissing(arena, out, freqMissingWeight(ds, &.{col}, wcol));
}

/// One crosstab. `table_no`/`control` are the n-way stratum headers: table_no 0
/// prints the plain `Table of v1 by v2`; N > 0 prints `Table N of v1 by v2` plus
/// the `Controlling for …` line (GAP-freqnway). Each cell shows the SAS-default
/// stack — Frequency, Percent (of grand total), Row Pct, Col Pct — trimmed by the
/// `disp` suppression options, with a legend box and marginal totals
/// (FREQ-crosstabpct). Row/Col percents are blank in the Total column, and the
/// marginal Total row carries only Frequency + Percent (SAS layout).
fn twoWayFreq(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, v1: []const u8, v2: []const u8, order: FreqOrder, wcol: ?usize, zeros: bool, table_no: usize, control: ?[]const u8, disp: FreqDisp, keep_missing: bool, fmt_levels: []const FmtLevels) !void {
    const c1 = ds.indexOf(v1) orelse {
        unsupported("PROC FREQ: TABLES row variable not found");
        return;
    };
    const c2 = ds.indexOf(v2) orelse {
        unsupported("PROC FREQ: TABLES column variable not found");
        return;
    };
    // SAS default excludes any obs missing in EITHER variable; `/ missing` keeps
    // the missing levels as categories (FREQ-crosstabpct).
    // PERF-freq2waymem: per-dim levels via the same one-pass hashing the one-way
    // path uses (was distinctSorted's O(N·L) dedup scan + an O(N) catWeight
    // rescan per level-pair under ORDER=FREQ) — identical filters/comparators, so
    // the level sets and orders are unchanged.
    const rlevels = try oneWayLevels(arena, ds, c1, keep_missing, order, wcol, zeros, fmtLevelsFor(fmt_levels, c1));
    const clevels = try oneWayLevels(arena, ds, c2, keep_missing, order, wcol, zeros, fmtLevelsFor(fmt_levels, c2));
    const nr = rlevels.len;
    const nc = clevels.len;
    const rows = try arena.alloc(Value, nr);
    for (rlevels, 0..) |l, i| rows[i] = l.v;
    const cols = try arena.alloc(Value, nc);
    for (clevels, 0..) |l, i| cols[i] = l.v;
    applyFmtOrder(rows, fmtLevelsFor(fmt_levels, c1), order); // each dim's VALUE.-format groups order by raw value (BUG-freqfmtorder)
    applyFmtOrder(cols, fmtLevelsFor(fmt_levels, c2), order);
    // Value -> final level index, hashed once (was catIndex's O(L) linear scan
    // per row per dim — O(N·L) total). Built AFTER applyFmtOrder reorders.
    var ridx: std.HashMapUnmanaged(Value, usize, LevelValueCtx, std.hash_map.default_max_load_percentage) = .empty;
    var cidx: std.HashMapUnmanaged(Value, usize, LevelValueCtx, std.hash_map.default_max_load_percentage) = .empty;
    for (rows, 0..) |v, i| try ridx.put(arena, v, i);
    for (cols, 0..) |v, i| try cidx.put(arena, v, i);

    // Weighted counts (BUG-freqweight2way): each cell is Σweight, 1/obs without
    // a WEIGHT statement — the one-way path already did this, this path silently
    // dropped the weight (clinical worst class: wrong counts, no diagnostic).
    // PERF-freq2waymem: cells live in a sparse (ri,ci) -> count hash — only
    // populated cells are stored; the old dense nr*nc matrix OOMed on
    // high-cardinality crosses (20k×20k). An absent cell reads back as the 0 the
    // dense matrix held, so printing (incl. empty cells) is unchanged; weights
    // accumulate per cell in the same row order, so sums are bit-identical too.
    var cells: std.AutoHashMapUnmanaged(u64, f64) = .empty;
    const rowTot = try arena.alloc(f64, nr);
    @memset(rowTot, 0);
    const colTot = try arena.alloc(f64, nc);
    @memset(colTot, 0);
    var grand: f64 = 0;
    // both TABLES variables index real columns (indexOf guaranteed it); the loop
    // reads r[c1]/r[c2] on every row, so an out-of-range index = wrong crosstab.
    // Two simple asserts, not one compound — a failure names the guilty index.
    assert(c1 < ds.columns.items.len);
    assert(c2 < ds.columns.items.len);
    if (wcol) |wc| assert(wc < ds.columns.items.len);
    for (ds.rows.items) |r| {
        const w = rowWeight(r, wcol);
        if (w == 0) continue; // adding 0 changes no cell or total — skip the hashing
        const ri = ridx.get(r[c1]) orelse continue;
        const ci = cidx.get(r[c2]) orelse continue;
        const gop = try cells.getOrPut(arena, (@as(u64, @intCast(ri)) << 32) | @as(u64, @intCast(ci)));
        if (!gop.found_existing) gop.value_ptr.* = 0;
        gop.value_ptr.* += w;
        rowTot[ri] += w;
        colTot[ci] += w;
        grand += w;
    }

    const sep = struct { // "|" position before column c (c in 0..=nc)
        fn at(c: usize) usize {
            return 24 + 9 * c;
        }
    }.at;
    const rightOf = struct { // value right-edge for data column c (or total at c==nc)
        fn at(c: usize) usize {
            return 31 + 9 * c;
        }
    }.at;
    // Buffer width grows with the number of column levels: the Total column's
    // right edge is rightOf(nc) = 31 + 9*nc and the rule underline reaches
    // 24 + 9*nc, so a fixed 60 overflows once nc >= 5 (BUG-freqcrash) and clips
    // the Total column from nc >= 4. Size to the widest write, floored at 60 so
    // narrow tables keep their old layout.
    const width = @max(60, 32 + 9 * nc);

    // Active cell statistics, in SAS's stacked order; each suppression option
    // drops one line.
    const Stat = enum { freq, pct, row, col };
    var sbuf: [4]Stat = undefined;
    var ns: usize = 0;
    if (!disp.nofreq) {
        sbuf[ns] = .freq;
        ns += 1;
    }
    if (!disp.nopercent) {
        sbuf[ns] = .pct;
        ns += 1;
    }
    if (!disp.norow) {
        sbuf[ns] = .row;
        ns += 1;
    }
    if (!disp.nocol) {
        sbuf[ns] = .col;
        ns += 1;
    }
    const stats = sbuf[0..ns];
    const legendLabel = struct {
        fn f(s: Stat) []const u8 {
            return switch (s) {
                .freq => "Frequency",
                .pct => "Percent",
                .row => "Row Pct",
                .col => "Col Pct",
            };
        }
    }.f;

    try out.appendSlice(arena, TWOWAY_TITLE);
    try out.append(arena, '\n');
    try flush(arena, out, blk: {
        const title = if (table_no == 0)
            try std.fmt.allocPrint(arena, "Table of {s} by {s}", .{ v1, v2 })
        else
            try std.fmt.allocPrint(arena, "Table {d} of {s} by {s}", .{ table_no, v1, v2 });
        const b = try line(arena, @max(60, 24 + title.len));
        putLeft(b, 25, title);
        break :blk b;
    });
    if (control) |ctl| try flush(arena, out, blk: {
        const b = try line(arena, @max(60, 24 + ctl.len));
        putLeft(b, 25, ctl);
        break :blk b;
    });
    try out.append(arena, '\n');
    try flush(arena, out, blk: { // "v1        v2"
        const b = try line(arena, 40);
        putLeft(b, 15, v1);
        putLeft(b, 25, v2);
        break :blk b;
    });
    try out.append(arena, '\n');
    // Legend box: one line per active stat; only the LAST line carries the column
    // category headers and the Total header (SAS crosstab layout).
    for (stats, 0..) |s, li| {
        const b = try line(arena, width);
        putLeft(b, 15, legendLabel(s));
        putLeft(b, sep(0), "|");
        if (li == stats.len - 1) {
            for (0..nc + 1) |c| putLeft(b, sep(c), "|");
            for (cols, 0..) |cv, c| putLeft(b, 25 + 9 * c, try cellText(arena, cv));
            putRight(b, rightOf(nc), "Total");
        }
        try flush(arena, out, b);
    }
    try emitFreqRule(arena, out, nc);
    for (0..nr) |ri| {
        for (stats, 0..) |s, li| {
            const b = try line(arena, width);
            if (li == 0) putLeft(b, 15, try cellText(arena, rows[ri]));
            for (0..nc + 1) |c| putLeft(b, sep(c), "|");
            for (0..nc) |c| {
                const cnt = cells.get((@as(u64, @intCast(ri)) << 32) | @as(u64, @intCast(c))) orelse 0;
                const txt = switch (s) {
                    .freq => try freqText(arena, cnt),
                    .pct => try pctText(arena, ratioF(cnt, grand)),
                    .row => try pctText(arena, ratioF(cnt, rowTot[ri])),
                    .col => try pctText(arena, ratioF(cnt, colTot[c])),
                };
                putRight(b, rightOf(c), txt);
            }
            // Total column: Frequency → row total; Percent → row total's % of the
            // grand total; Row/Col Pct are left blank there (SAS).
            switch (s) {
                .freq => putRight(b, rightOf(nc), try freqText(arena, rowTot[ri])),
                .pct => putRight(b, rightOf(nc), try pctText(arena, ratioF(rowTot[ri], grand))),
                .row, .col => {},
            }
            try flush(arena, out, b);
        }
        try emitFreqRule(arena, out, nc);
    }
    // Marginal Total row: Frequency + Percent only, no vertical separators. The
    // first active line carries the "Total" label; the corner cell is grand/100%.
    if (!disp.nofreq) {
        const b = try line(arena, width);
        putLeft(b, 15, "Total");
        for (0..nc) |c| putRight(b, rightOf(c), try freqText(arena, colTot[c]));
        putRight(b, rightOf(nc), try freqText(arena, grand));
        try flush(arena, out, b);
    }
    if (!disp.nopercent) {
        const b = try line(arena, width);
        if (disp.nofreq) putLeft(b, 15, "Total");
        for (0..nc) |c| putRight(b, rightOf(c), try pctText(arena, ratioF(colTot[c], grand)));
        putRight(b, rightOf(nc), try pctText(arena, 100.0));
        try flush(arena, out, b);
    }
    if (!keep_missing) {
        // obs missing in EITHER variable were excluded — report the (weighted)
        // count, the same rule as the one-way line (SAS).
        try appendFreqMissing(arena, out, freqMissingWeight(ds, &.{ c1, c2 }, wcol));
    }
}

fn emitFreqRule(arena: std.mem.Allocator, out: *std.ArrayList(u8), nc: usize) !void {
    // Same width formula as the two-way table: the last '+' lands at 24 + 9*nc - 1,
    // so a fixed 60 panicked here (BUG-freqcrash) once nc >= 5.
    const b = try line(arena, @max(60, 32 + 9 * nc));
    for (14..23) |k| b[k] = '-'; // row-label underline, cols 15–23
    for (0..nc) |c| {
        b[24 + 9 * c - 1] = '+';
        for (24 + 9 * c..32 + 9 * c) |k| b[k] = '-'; // 8 dashes after the '+'
    }
    b[24 + 9 * nc - 1] = '+';
    try flush(arena, out, b);
}

// ── freq helpers ────────────────────────────────────────────────────────────

/// A value FREQ excludes from its counts: numeric missing (`.`) or blank char.
/// SAS's default TABLES behaviour drops these from categories and percents.
fn isFreqMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}

/// Σweight over the observations missing in ANY of `cols` (1/obs unweighted) —
/// the weighted `Frequency Missing` count (see appendFreqMissing).
fn freqMissingWeight(ds: *Dataset, cols: []const usize, wcol: ?usize) f64 {
    var sum: f64 = 0;
    next_row: for (ds.rows.items) |r| {
        for (cols) |ci| if (isFreqMissing(r[ci])) {
            sum += rowWeight(r, wcol);
            continue :next_row;
        };
    }
    return sum;
}

/// PROC FREQ level ordering (ORDER= option). INTERNAL → ascending value (the
/// default); FORMATTED → ascending FORMATTED (decode) value — for a
/// format-grouped col the cells already hold the label text, so the ascending
/// sort IS the label order (BUG-freqweightorder F1); FREQ → descending count;
/// DATA → first-appearance order.
/// ponytail: FORMATTED on an ungrouped (no-format) numeric col sorts by value,
/// not by right-justified BEST12 text — differs from SAS only for negative or
/// fractional values with no format; switch the comparator if a golden needs
/// the text sort.
const FreqOrder = enum { internal, freq, data, formatted };

/// FREQ level membership under a WEIGHT: SAS drops an obs whose weight is
/// non-positive or missing, so a level seen ONLY on such obs never appears;
/// `/ zeros` re-includes exactly-zero weights (negative/missing stay excluded).
fn weightKeepsRow(r: []const Value, wcol: ?usize, zeros: bool) bool {
    const wc = wcol orelse return true;
    return switch (r[wc]) {
        .num => |x| x > 0 or (zeros and x == 0),
        .str => false, // missing weight — excluded either way, as SAS does
    };
}

fn catCount(ds: *Dataset, col: usize, cat: Value) usize {
    var n: usize = 0;
    for (ds.rows.items) |r| if (cmpValue(r[col], cat) == .eq) {
        n += 1;
    };
    return n;
}

fn ratio(part: usize, whole: usize) f64 {
    return @as(f64, @floatFromInt(part)) / @as(f64, @floatFromInt(whole)) * 100.0;
}

fn pctText(arena: std.mem.Allocator, p: f64) ![]const u8 {
    return format.apply(arena, .{ .num = p }, ".2"); // bare "40.00"
}

fn line(arena: std.mem.Allocator, w: usize) ![]u8 {
    const b = try arena.alloc(u8, w);
    @memset(b, ' ');
    return b;
}

fn putLeft(b: []u8, col: usize, text: []const u8) void {
    const s = col - 1;
    for (text, 0..) |c, k| if (s + k < b.len) {
        b[s + k] = c;
    };
}

fn putRight(b: []u8, right_col: usize, text: []const u8) void {
    if (text.len > right_col) return;
    const s = right_col - text.len; // 0-based start; last char lands at right_col-1
    for (text, 0..) |c, k| if (s + k < b.len) {
        b[s + k] = c;
    };
}

fn flush(arena: std.mem.Allocator, out: *std.ArrayList(u8), b: []u8) !void {
    try out.appendSlice(arena, std.mem.trimEnd(u8, b, " "));
    try out.append(arena, '\n');
}

// ── PROC TRANSPOSE ───────────────────────────────────────────────────────────
//
// `proc transpose data=IN out=OUT [prefix=P] [name=N]; [var …;] [id v;] [by …;]`.
// Each VAR variable becomes one output row; each input observation (within a BY
// group) becomes one output column — named by the ID value if `id` is given,
// else `prefix`+1,2,… (default prefix "COL"); SUFFIX= is appended to every
// generated name. LET suppresses the duplicate-ID error and keeps the LAST
// value, as SAS does. The `name=` column (default
// `_NAME_`) holds the transposed variable's name. Input is assumed sorted by the
// BY vars, as SAS requires.
// ponytail: single-type VAR list (columns take the first VAR's type).

pub fn runTranspose(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var in_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var prefix: []const u8 = "COL";
    var prefix_set = false; // explicit PREFIX= also applies to ID values (QA-transprefixid)
    var suffix: []const u8 = "";
    var let_last = false; // LET: dup ID in a BY group keeps the LAST value, no error
    var name_col: []const u8 = "_NAME_";
    var label_col: []const u8 = "_LABEL_"; // renamable via LABEL= (GAP-transposelabel)
    var delimiter: []const u8 = "_"; // joins multiple ID values into one column name (SAS default `_`, BUG-transposemultiid)
    var i: usize = 2; // past `proc transpose`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
            // OUT= dataset options (`out=OUT(drop=/keep=/rename=/where=)`) are
            // applied once by applyOutOptions after the transpose builds; just skip
            // past the (possibly nested, e.g. rename=(…)) paren group here. A former
            // second drop/keep pass re-validated a name whose column was already
            // removed and false-errored (ISS-keepdropnonexist).
            if (atTag(toks, i, .lparen)) {
                var depth: usize = 0;
                while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) : (i += 1) {
                    if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                        depth -= 1;
                        if (depth == 0) {
                            i += 1;
                            break;
                        }
                    }
                }
            }
        } else if (optAny(toks, i, "prefix")) |v| { // optAny: quoted value, like suffix=/label=/delimiter= (BUG-transposeoptquoted)
            prefix = v;
            prefix_set = true;
            i += 3;
        } else if (optAny(toks, i, "suffix")) |v| {
            suffix = v;
            i += 3;
        } else if (optAny(toks, i, "name")) |v| { // quoted value too (BUG-transposeoptquoted)
            name_col = v;
            i += 3;
        } else if (optAny(toks, i, "delimiter") orelse optAny(toks, i, "delim")) |v| {
            delimiter = v;
            i += 3;
        } else if (tkKw(toks[i], "let")) {
            let_last = true;
            i += 1;
        } else if (optAny(toks, i, "label")) |v| {
            label_col = v; // LABEL=name renames the _LABEL_ output column (GAP-transposelabel)
            i += 3;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // data=d(where=/keep=/…) dataset options — applied via procInput
        } else {
            // D-002 fail-loud (BUG-transposeoptswallow): an unknown header option
            // must error visibly, not vanish — a typo'd `prefx=` changes output.
            // BUG-proctypoexits2: split — INDB= is the one documented option we
            // don't implement (gap, rc 2); any other name is the user's typo (rc 1).
            if (toks[i].tag == .name) {
                if (isTransposeGapOption(toks[i].text)) {
                    unsupported(try std.fmt.allocPrint(arena, "PROC TRANSPOSE: unknown option {s}", .{toks[i].text}));
                    return;
                }
                return diags.fail(error.ParseError, toks[i].line, "PROC TRANSPOSE: unknown option {s}", .{toks[i].text});
            }
            i += 1; // stray punctuation
        }
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    var vars: std.ArrayList([]const u8) = .empty;
    var bys: std.ArrayList([]const u8) = .empty;
    var ids: std.ArrayList([]const u8) = .empty; // ID accepts MULTIPLE vars (BUG-transposemultiid)
    var copys: std.ArrayList([]const u8) = .empty; // COPY vars pass through unchanged (BUG-transposecopy)
    var idlabel_name: ?[]const u8 = null; // IDLABEL var — labels each ID-named column (GAP-transposeidlabel)
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "var")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) {
                if (toks[i].tag != .name) {
                    i += 1;
                    continue;
                }
                // `v1-v5` numbered range: stopping at the `-` kept only the
                // endpoints v1/v5 and SILENTLY dropped v2..v4 (BUG-transposevarrange).
                // Expand it via the shared helper SET/KEEP/LENGTH already use.
                if (i + 2 < toks.len and toks[i + 1].tag == .minus and toks[i + 2].tag == .name) {
                    try @import("parser.zig").expandRange(arena, &vars, toks[i].text, toks[i + 2].text);
                    i += 3;
                    continue;
                }
                try vars.append(arena, toks[i].text);
                i += 1;
            }
        } else if (tkKw(toks[i], "id")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) try ids.append(arena, toks[i].text);
            }
        } else if (tkKw(toks[i], "copy")) {
            // COPY <vars>: carried straight through to OUT=, value from the FIRST
            // obs of each BY group (SAS 9.4). Formerly fell through the trailing
            // `else i += 1` and the variable vanished silently (BUG-transposecopy).
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) try copys.append(arena, toks[i].text);
            }
        } else if (tkKw(toks[i], "by")) {
            try parseProcBy(arena, diags, toks, &i, &bys);
        } else if (tkKw(toks[i], "idlabel")) {
            // IDLABEL <var>: that var's value (from the same row that supplies
            // the ID column NAME) becomes the generated column's LABEL —
            // captured here, applied when the out columns are built below.
            i += 1;
            if (i < toks.len and toks[i].tag == .name) {
                idlabel_name = toks[i].text;
                i += 1;
            }
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (tkKw(toks[i], "label")) {
            // LABEL <var="text" …> — cosmetic metadata we don't carry through
            // the transpose build; parsed and skipped, never an error.
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (tkKw(toks[i], "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1; // procInput applies it
        } else if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            // D-014a mid-step globals: skip exactly what the top level HANDLES
            // here — a hoisted TITLE/FOOTNOTE/OPTIONS (main.zig hoists it to
            // its own global segment; its tokens STAY in the step) and the
            // batch-unobservable inert set (GOPTIONS/DM/SASFILE/PAGE/…).
            // LIBNAME executed in the up-front parseLibnames pre-pass, so its
            // skip is honest. Unhoisted ODS/FILENAME are NOT skipped — never
            // executed mid-step, so a skip would be a silent no-op; they fail
            // loud below (BUG-transposeglobalstmt: one legal TITLE errored and
            // errhalt then killed every later step).
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (toks[i].tag == .name) {
            // D-002 fail-loud (BUG-transposeoptswallow): an unknown sub-statement
            // errors visibly instead of being token-swallowed one token at a time.
            return diags.fail(error.ParseError, toks[i].line, "PROC TRANSPOSE statement {s} is not recognized", .{toks[i].text});
        } else i += 1;
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC TRANSPOSE: no input dataset");
        return;
    };
    const ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-transposeinputopts)
    const oname = out_name orelse {
        unsupported("PROC TRANSPOSE: OUT= required");
        return;
    };

    var byIdx: std.ArrayList(usize) = .empty;
    const pb = try decodeProcBy(arena, bys.items); // GAP-procbydescending: clean names + directions
    for (pb.names) |b| {
        const bix = ds.indexOf(b) orelse
            return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: BY variable {s} not found in the input data set.", .{b});
        try byIdx.append(arena, bix);
    }
    var idIdx: std.ArrayList(usize) = .empty;
    for (ids.items) |idv| {
        const iix = ds.indexOf(idv) orelse
            return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: ID variable {s} not found in the input data set.", .{idv});
        try idIdx.append(arena, iix);
    }
    const has_id = idIdx.items.len > 0;
    // IDLABEL without ID is a SAS no-op (no ID-named columns to label); with ID,
    // an unknown var fails loud like ID/BY/COPY above.
    var idlabel_idx: ?usize = null;
    if (idlabel_name) |iln| if (has_id) {
        idlabel_idx = ds.indexOf(iln) orelse
            return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: IDLABEL variable {s} not found in the input data set.", .{iln});
    };
    var copyIdx: std.ArrayList(usize) = .empty;
    for (copys.items) |cv| {
        const cix = ds.indexOf(cv) orelse
            return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: COPY variable {s} not found in the input data set.", .{cv});
        try copyIdx.append(arena, cix);
    }

    // VAR columns: the `var` list, else every numeric column not used as BY/ID
    var varIdx: std.ArrayList(usize) = .empty;
    if (vars.items.len > 0) {
        for (vars.items) |v| {
            const vix = ds.indexOf(v) orelse
                return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: VAR variable {s} not found in the input data set.", .{v});
            try varIdx.append(arena, vix);
        }
    } else {
        for (ds.columns.items, 0..) |c, ix| {
            if (c.type != .num) continue;
            if (idxIn(byIdx.items, ix) or idxIn(idIdx.items, ix) or idxIn(copyIdx.items, ix)) continue;
            try varIdx.append(arena, ix);
        }
    }
    if (varIdx.items.len == 0) {
        unsupported("PROC TRANSPOSE: no variables to transpose");
        return;
    }
    const val_type = ds.columns.items[varIdx.items[0]].type;
    // SAS 9.4 ERRORs on a mixed char/num VAR list; giving every value column
    // the FIRST var's type silently corrupted the other-typed vars to missing
    // (BUG-transposemixedvar). A single-type list (all num or all char) is fine.
    for (varIdx.items[1..]) |vx|
        if (ds.columns.items[vx].type != val_type)
            return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: VAR list has both character and numeric variables", .{});

    // BY groups (consecutive-equal on the BY key); no BY → one group over all rows
    const rows = ds.rows.items;
    var groups: std.ArrayList([2]usize) = .empty;
    if (byIdx.items.len == 0) {
        try groups.append(arena, .{ 0, rows.len });
    } else {
        var s: usize = 0;
        while (s < rows.len) {
            var e = s + 1;
            while (e < rows.len and byEqual(rows[s], rows[e], byIdx.items)) e += 1;
            // BUG-transposebyorder: BY demands sorted data. A new group whose
            // key steps backward (which any repeated non-adjacent key forces)
            // ERRORs like SAS's SET/BY guard (main.zig:1713) instead of emitting
            // a duplicate/wrong BY group at exit 0. Per-key under BY DESCENDING
            // (GAP-procbydescending); BY NOTSORTED drops the check.
            if (e < rows.len and !pb.notsorted) if (byOrderViolation(rows[e], rows[s], byIdx.items, pb.desc)) |k|
                return diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (pb.desc[k]) "descending" else "ascending" });
            try groups.append(arena, .{ s, e });
            s = e;
        }
    }

    // value-column names: ID values (appearance order), else prefix+1..maxgroup.
    // name_index maps the case-folded output-column name → its position, built ONCE
    // so dedup here + the fill-loop lookup below are O(1), not a linear scan of the
    // accumulated names per row (PERF-transposewide; mirrors exec.zig's folded sets).
    var val_names: std.ArrayList([]const u8) = .empty;
    var val_labels: std.ArrayList([]const u8) = .empty; // IDLABEL text per ID column, parallel to val_names (empty without IDLABEL)
    var name_index: std.StringHashMapUnmanaged(usize) = .empty;
    if (has_id) {
        // ID columns name every transposed output column — a bad index would
        // mislabel the whole transpose, silently (TASTE-asserts).
        for (idIdx.items) |ii| assert(ii < ds.columns.items.len);
        for (rows) |r| {
            const txt = try transIdName(arena, prefix, prefix_set, suffix, delimiter, ds.columns.items, r, idIdx.items);
            const key = try std.ascii.allocLowerString(arena, txt);
            if (name_index.contains(key)) continue;
            try name_index.put(arena, key, val_names.items.len);
            try val_names.append(arena, txt);
            if (idlabel_idx) |ilx| try val_labels.append(arena, try cellText(arena, r[ilx]));
        }
    } else {
        var maxg: usize = 0;
        for (groups.items) |g| maxg = @max(maxg, g[1] - g[0]);
        for (0..maxg) |k| try val_names.append(arena, try std.fmt.allocPrint(arena, "{s}{d}{s}", .{ prefix, k + 1, suffix }));
    }

    // SAS adds a `_LABEL_` char column holding each VAR's label, right after
    // _NAME_ — but ONLY when at least one transposed var carries a label; with
    // none, the column is absent entirely (GAP-transposelabel).
    var any_label = false;
    for (varIdx.items) |vx| {
        const l = ds.columns.items[vx].label;
        if (l != null and l.?.len > 0) {
            any_label = true;
            break;
        }
    }

    const out = try arena.create(Dataset);
    out.* = Dataset.init(arena, oname);
    for (byIdx.items) |bx| _ = try out.addColumn(ds.columns.items[bx].name, ds.columns.items[bx].type);
    _ = try out.addColumn(name_col, .char);
    if (any_label) _ = try out.addColumn(label_col, .char);
    for (val_names.items, 0..) |vn, k| {
        const ci = try out.addColumn(vn, val_type);
        if (k < val_labels.items.len) out.columns.items[ci].label = val_labels.items[k];
    }
    for (copyIdx.items) |cix| _ = try out.addColumn(ds.columns.items[cix].name, ds.columns.items[cix].type);

    const nby = byIdx.items.len;
    const ncopy = copyIdx.items.len;
    const ncol = val_names.items.len;
    const nlabel: usize = @intFromBool(any_label);
    for (groups.items) |g| {
        // SAS errors when an ID value repeats within a BY group: two rows would map
        // to the same output column, silently keeping only the last (data loss,
        // BUG-transposedupid). Fail loud instead — unless LET is given, which is
        // SAS's explicit "keep the LAST value, no error" (GAP-transposelet); the
        // fill loop's later write already wins, so LET just skips this check.
        // A per-group folded seen-set makes this O(group), not the former O(group²)
        // pairwise scan (PERF-transposewide); keyed on the composed column name so
        // multi-ID collisions (BUG-transposemultiid) are detected together.
        if (has_id and !let_last) {
            var seen: std.StringHashMapUnmanaged(void) = .empty;
            for (g[0]..g[1]) |ra| {
                const txt = try transIdName(arena, prefix, prefix_set, suffix, delimiter, ds.columns.items, rows[ra], idIdx.items);
                const gop = try seen.getOrPut(arena, try std.ascii.allocLowerString(arena, txt));
                if (gop.found_existing)
                    return diags.fail(error.ParseError, 0, "PROC TRANSPOSE: The ID value \"{s}\" occurs twice in the same BY group.", .{txt});
            }
        }
        for (varIdx.items) |vi| {
            const cells = try arena.alloc(Value, nby + 1 + nlabel + ncol + ncopy);
            // A 0-row input (e.g. a where= that matched nothing) is one empty
            // group [0,0): there is no first obs to source BY/COPY values from.
            // Emit missings — the same row the no-COPY empty case already emits —
            // never index row 0 of an empty table (BUG-transposecopyempty).
            const first: ?usize = if (g[0] < g[1]) g[0] else null;
            for (byIdx.items, 0..) |bx, bi| cells[bi] = if (first) |f| rows[f][bx] else missingOf(ds.columns.items[bx].type);
            cells[nby] = .{ .str = ds.columns.items[vi].name }; // _NAME_
            if (any_label) cells[nby + 1] = if (ds.columns.items[vi].label) |l| .{ .str = l } else missingOf(.char); // _LABEL_ (blank when that var has none)
            for (0..ncol) |k| cells[nby + 1 + nlabel + k] = missingOf(val_type);
            // COPY value: first obs of the BY group, same on every output row.
            for (copyIdx.items, 0..) |cix, ci| cells[nby + 1 + nlabel + ncol + ci] = if (first) |f| rows[f][cix] else missingOf(ds.columns.items[cix].type);
            var r = g[0];
            while (r < g[1]) : (r += 1) {
                // The lookup name must be decorated EXACTLY as in val_names above —
                // the former raw-value lookup silently fell back to the positional
                // index for any PREFIX=/_ name, which maps a LET-deduped row to the
                // WRONG column (or past the cells) once dupes collapse val_names.
                // O(1) via the folded name_index built once (PERF-transposewide).
                const pos: usize = if (has_id)
                    name_index.get(try std.ascii.allocLowerString(arena, try transIdName(arena, prefix, prefix_set, suffix, delimiter, ds.columns.items, rows[r], idIdx.items))) orelse (r - g[0])
                else
                    (r - g[0]);
                cells[nby + 1 + nlabel + pos] = rows[r][vi];
            }
            try out.appendRow(cells);
        }
    }
    // out=X(drop=/keep=/rename=/where=) — applied once, on the full output while
    // _NAME_ + all value columns are present (BUG-procoutkeep; no more double-apply).
    try applyOutOptions(arena, out, toks, diags, "out");
    try lib.put(oname, out);
}

fn idxIn(list: []const usize, x: usize) bool {
    for (list) |v| if (v == x) return true;
    return false;
}

/// The TRANSPOSE output-column name for one ID value: an explicit PREFIX= is
/// ATTACHED to the ID value (`prefix=dt_ id obsid` → dt_1) — that's SAS's way of
/// making numeric IDs valid names; a real EPOCH macro's six transposes are
/// distinguished ONLY by it (QA-transprefixid). Without PREFIX=, a numeric ID
/// value ("1") isn't a valid SAS name — SAS prepends `_` (`_1`, BUG-transnumid).
/// SUFFIX= is appended last (BUG-transposesuffix). Name generation and the fill
/// loop MUST agree on this — hence one helper.
fn idColName(arena: std.mem.Allocator, prefix: []const u8, prefix_set: bool, suffix: []const u8, raw: []const u8) ![]const u8 {
    var txt = raw;
    if (prefix_set) {
        txt = try std.fmt.allocPrint(arena, "{s}{s}", .{ prefix, txt });
    } else if (txt.len == 0 or !(std.ascii.isAlphabetic(txt[0]) or txt[0] == '_')) {
        txt = try std.fmt.allocPrint(arena, "_{s}", .{txt});
    }
    if (suffix.len > 0) txt = try std.fmt.allocPrint(arena, "{s}{s}", .{ txt, suffix });
    // BUG-transposeidmangle: the decorated name must be a VALID V7 name — route
    // through the same mangling PROC IMPORT uses (validName): non-alnum/_ chars
    // → `_`, leading digit → `_` prefix, ≤32 bytes. Two ID values that mangle to
    // the same name collapse onto one column via the val_names/name_index dedup
    // above — SAS's reuse-the-same-column behavior, no duplicate/illegal column.
    return io.validName(arena, txt, 0);
}

/// The ID-value text a column is named from: SAS 9.4 names transposed columns
/// from the ID var's FORMATTED value (BUG-transposeidfmt — `id dt` with
/// `format dt date9.` names `_01JAN2020`, not the raw `_21915`). Unformatted
/// keeps the compact cellText rendering (tick208-verified). Width-padded
/// formatted text is blank-trimmed before idColName mangles it.
fn idValueText(arena: std.mem.Allocator, cols: []const Column, ci: usize, v: Value) ![]const u8 {
    if (cols[ci].format) |spec| return std.mem.trim(u8, try format.apply(arena, v, spec), " ");
    return cellText(arena, v);
}

/// The output-column name for one row's ID value(s): SAS joins MULTIPLE ID vars'
/// formatted values with DELIMITER= (default `_`), then decorates the whole with
/// idColName (BUG-transposemultiid). One ID var → just its decorated value.
fn transIdName(arena: std.mem.Allocator, prefix: []const u8, prefix_set: bool, suffix: []const u8, delimiter: []const u8, cols: []const Column, row: []const Value, id_idx: []const usize) ![]const u8 {
    if (id_idx.len == 1) return idColName(arena, prefix, prefix_set, suffix, try idValueText(arena, cols, id_idx[0], row[id_idx[0]]));
    var raw: std.ArrayList(u8) = .empty;
    for (id_idx, 0..) |ix, k| {
        if (k > 0) try raw.appendSlice(arena, delimiter);
        try raw.appendSlice(arena, try idValueText(arena, cols, ix, row[ix]));
    }
    return idColName(arena, prefix, prefix_set, suffix, raw.items);
}

fn nameIn(list: []const []const u8, name: []const u8) bool {
    return nameIndex(list, name) != null;
}

fn nameIndex(list: []const []const u8, name: []const u8) ?usize {
    for (list, 0..) |n, i| if (eqi(n, name)) return i;
    return null;
}

// ── PROC REPORT ──────────────────────────────────────────────────────────────
//
// `proc report data=IN [nowd]; columns c1 c2 …; [define v / <usage> 'label';]`.
// A plain detail listing (one line per observation): char columns left-justified
// at width max(header, widest value); numeric columns right-justified at that
// width + 2; SPACING = 2 between columns; a blank line under the header. A
// `define`'s quoted string is used as the column header; WIDTH= fixes the column
// width, FORMAT= the cell format, ORDER sorts the rows and blanks repeats.
// ponytail: the numeric width `+2` matches SAS's default here but is a heuristic,
// not its exact format-driven width; ACROSS/COMPUTED/BREAK/RBREAK/BY and proc options
// beyond NOWD fail loud (D-002) until their increments land.

/// One `define VAR / …;` — its header label and REPORT usage (GROUP collapses to
/// one row per level; a stat marks an analysis column aggregated over the group).
/// SAS 9.4 PROC REPORT doc, DEFINE statement: ORDER "orders the rows of the
/// report according to the values" of the ORDER vars (left to right) and a
/// repeated ORDER value prints blank; WIDTH= sets the column width; FORMAT= the
/// cell format. `desc` is DESCENDING on an ORDER var.
const Define = struct {
    name: []const u8,
    label: ?[]const u8 = null,
    group: bool = false,
    order: bool = false,
    desc: bool = false,
    display: bool = false, // explicit DISPLAY usage — keeps the report a detail listing (BUG-reportanalysis)
    computed: bool = false, // COMPUTED usage — value comes from a `compute` block, not a source column (FEAT-procreport-2)
    noprint: bool = false, // NOPRINT — column is computed/grouped/ordered but omitted from output (tick240 F4)
    order_mode: GroupOrder = .internal, // ORDER=INTERNAL|DATA|FREQ|FORMATTED sub-ordering (tick240 F3)
    stat: ?StatKind = null,
    width: ?usize = null,
    format: ?[]const u8 = null,
};

/// A GROUP-usage source column plus how its levels sequence (tick240 F1/F3).
const GCol = struct { ix: usize, desc: bool = false, mode: GroupOrder = .internal };

pub fn runReport(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags; // COMPUTE reuses the DATA-step expr parser/evaluator, which report through this
    var in_name: ?[]const u8 = null;
    var i: usize = 2; // past `proc report`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (tkKw(toks[i], "nowd") or tkKw(toks[i], "nowindows")) {
            i += 1; // the windowing toggle is meaningless under this harness — the one accepted no-op
        } else if (toks[i].tag == .name) {
            // HEADLINE/HEADSKIP/NOCENTER/… change the page layout we don't model —
            // fail loud (D-002), never silently emit the plain layout (FEAT-procreport-1).
            unsupported("PROC REPORT: proc-statement options (HEADLINE/HEADSKIP/NOCENTER/…)");
            return;
        } else i += 1; // parens of data=(where=…) options etc.
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    var cols: std.ArrayList([]const u8) = .empty;
    var defs: std.ArrayList(Define) = .empty;
    // ACROSS crossing (`define x / across;`) and comma-nested columns
    // (`column reg prod,sales;`) build a crosstab we don't implement — fail loud
    // rather than emit a plausible-but-wrong collapsed table (BUG-reportacross).
    var across = false;
    var break_after: ?[]const u8 = null; // BREAK AFTER <var> / SUMMARIZE subtotal target (FEAT-procreport-2)
    var rbreak_after = false; // RBREAK AFTER / SUMMARIZE grand-total line
    var break_before: ?[]const u8 = null; // BREAK BEFORE <var> / SUMMARIZE — subtotal BEFORE each group (procreport rest3)
    var rbreak_before = false; // RBREAK BEFORE / SUMMARIZE grand-total line, before all rows
    var computes: std.ArrayList(Compute) = .empty; // `compute <col>; … endcomp;` blocks (FEAT-procreport-2)
    var after_computes: std.ArrayList(AfterSrc) = .empty; // `compute after [<var>]; … endcomp;` break-attached (compute-at-break)
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "break") or tkKw(toks[i], "rbreak")) {
            // `break before|after <var> / summarize;` + `rbreak before|after / summarize;`
            // — subtotal + grand-total lines (FEAT-procreport-2, BEFORE added in rest3).
            // Everything else in the break family (OL/UL/SKIP/PAGE/SUPPRESS, no SUMMARIZE)
            // is a later increment — fail loud (D-002), never a silently-dropped break.
            const is_r = tkKw(toks[i], "rbreak");
            i += 1;
            const is_before = i < toks.len and tkKw(toks[i], "before");
            if (!(i < toks.len and (tkKw(toks[i], "after") or is_before))) {
                unsupported("PROC REPORT BREAK/RBREAK requires BEFORE or AFTER");
                return;
            }
            i += 1;
            var bvar: ?[]const u8 = null;
            if (!is_r) {
                if (atTag(toks, i, .name)) {
                    bvar = toks[i].text;
                    i += 1;
                } else {
                    unsupported("PROC REPORT BREAK AFTER without a variable");
                    return;
                }
            }
            if (!atTag(toks, i, .slash)) {
                unsupported("PROC REPORT BREAK/RBREAK without / SUMMARIZE (LINE / bare break unsupported)");
                return;
            }
            i += 1;
            var saw_sum = false;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name and eqi(toks[i].text, "summarize")) saw_sum = true else {
                    unsupported("PROC REPORT BREAK/RBREAK options beyond SUMMARIZE (OL/DOL/UL/DUL/SKIP/PAGE/SUPPRESS/…)");
                    return;
                }
            }
            if (!saw_sum) {
                unsupported("PROC REPORT BREAK/RBREAK without SUMMARIZE");
                return;
            }
            if (is_r) {
                if (is_before) rbreak_before = true else rbreak_after = true;
            } else if (is_before) break_before = bvar else break_after = bvar;
            if (atTag(toks, i, .semicolon)) i += 1;
            continue;
        }
        if (tkKw(toks[i], "by")) {
            // BY-group reporting (one report per group) is FEAT-procreport-2 — fail
            // loud (D-002), never silently emit one merged report (BUG-procreportby).
            unsupported("PROC REPORT BY-group processing is not supported");
            return;
        }
        // `where <expr>;` is applied by procInput below; skip its tokens here so a
        // by/break/rbreak-named COLUMN inside the predicate isn't mistaken for a
        // sub-statement (BUG-reportwherekw, qa-findings-tick143; cf. printwherekw).
        if (tkKw(toks[i], "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
            if (atTag(toks, i, .semicolon)) i += 1;
            continue;
        }
        if (tkKw(toks[i], "columns") or tkKw(toks[i], "column")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .comma) across = true; // col1,col2 crossing
                if (toks[i].tag == .name) try cols.append(arena, toks[i].text);
            }
        } else if (tkKw(toks[i], "compute")) {
            i += 1;
            // `compute after|before [<var>]` fills computed columns ON a break/rbreak
            // SUMMARIZE line (compute-at-break; BEFORE added in rest3); a plain
            // `compute <col>` fills the computed column per detail row (FEAT-procreport-2).
            const is_cb = i < toks.len and tkKw(toks[i], "before");
            const is_after = is_cb or (i < toks.len and tkKw(toks[i], "after"));
            var after_var: ?[]const u8 = null;
            var cname: []const u8 = "";
            if (is_after) {
                i += 1;
                if (atTag(toks, i, .name)) {
                    after_var = toks[i].text;
                    i += 1;
                }
            } else {
                cname = if (atTag(toks, i, .name)) toks[i].text else {
                    unsupported("PROC REPORT COMPUTE without a column name");
                    return;
                };
                i += 1;
            }
            if (atTag(toks, i, .semicolon)) i += 1;
            const bstart = i;
            while (i < toks.len and toks[i].tag != .eof and !tkKw(toks[i], "endcomp") and !tkKw(toks[i], "run") and !tkKw(toks[i], "quit")) i += 1;
            if (is_after)
                try after_computes.append(arena, .{ .bvar = after_var, .before = is_cb, .body = toks[bstart..i] })
            else
                try computes.append(arena, .{ .col = cname, .body = toks[bstart..i] });
            if (i < toks.len and tkKw(toks[i], "endcomp")) i += 1; // consume endcomp; its trailing `;` eaten by the loop tail
        } else if (tkKw(toks[i], "define")) {
            // `define VAR / [group|order|display|analysis] [sum|mean|…] 'label';`
            i += 1;
            var d = Define{ .name = if (atTag(toks, i, .name)) toks[i].text else "" };
            if (d.name.len > 0) i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .string) {
                    d.label = toks[i].text; // quoted header
                    continue;
                }
                if (toks[i].tag != .name) continue; // `=`/numbers are consumed by their option below
                const kw = toks[i].text;
                if (eqi(kw, "group")) d.group = true // GROUP collapses to one row per level
                else if (eqi(kw, "order") and atTag(toks, i + 1, .eq) and atTag(toks, i + 2, .name)) {
                    // ORDER=INTERNAL|DATA|FREQ|FORMATTED is the level-sequencing OPTION
                    // (valid with GROUP/ORDER/ACROSS usage); it does NOT itself confer
                    // ORDER usage — that's the bare `order` keyword below (tick240 F3).
                    const v = toks[i + 2].text;
                    d.order_mode = if (eqi(v, "internal")) .internal //
                        else if (eqi(v, "data")) .data //
                        else if (eqi(v, "freq")) .freq //
                        else if (eqi(v, "formatted")) .formatted //
                        else {
                            unsupported("PROC REPORT: unrecognized DEFINE ORDER= value");
                            return;
                        };
                    i += 2;
                } else if (eqi(kw, "order")) d.order = true // bare ORDER usage: sorts rows, blanks repeats
                else if (eqi(kw, "descending")) d.desc = true // DESCENDING on an ORDER/GROUP var
                else if (eqi(kw, "across")) across = true // crosstab dimension — unsupported
                else if (eqi(kw, "computed")) d.computed = true // derived col — value from a compute block (FEAT-procreport-2)
                else if (eqi(kw, "analysis")) {} // usage marker; the stat word carries the stat (bare = SUM default)
                else if (eqi(kw, "noprint")) d.noprint = true // omit column from output (tick240 F4)
                else if (eqi(kw, "width") and atTag(toks, i + 1, .eq) and atTag(toks, i + 2, .number)) {
                    d.width = std.fmt.parseInt(usize, toks[i + 2].text, 10) catch null;
                    i += 2;
                } else if (eqi(kw, "format") and atTag(toks, i + 1, .eq)) {
                    const end = fmtSpecEnd(toks, i + 2);
                    if (end > i + 2) d.format = try joinFmt(arena, toks[i + 2 .. end]);
                    i = end - 1; // the loop's own += 1 lands on the next attribute
                } else if (eqi(kw, "spacing") and atTag(toks, i + 1, .eq) and atTag(toks, i + 2, .number)) {
                    i += 2; // page-layout knob we don't model — accept + skip (was already a no-op)
                } else if (eqi(kw, "display")) d.display = true // explicit DISPLAY usage (BUG-reportanalysis)
                else if (statFromKw(kw)) |sk| d.stat = sk // sum/mean/min/max/n → analysis stat
                else {
                    // tick240 F2/F5 (shared root): the DEFINE-option scan used to DROP
                    // any unrecognized token — a garbage option (`zonk`) OR an analysis
                    // STATISTIC we don't render (PCTSUM/PCTN/PCT) both fell through and
                    // the report silently defaulted to SUM. Fail loud instead.
                    unsupported("PROC REPORT: unsupported DEFINE option/statistic");
                    return;
                }
            }
            if (d.name.len > 0) try defs.append(arena, d);
        } else i += 1;
        if (atTag(toks, i, .semicolon)) i += 1;
    }
    if (across) {
        unsupported("PROC REPORT ACROSS");
        return;
    }
    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC REPORT: no input dataset");
        return;
    };
    const ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)

    // Output columns in COLUMN order. `src[j]` is the source ds index, or null for
    // a COMPUTED column (`define / computed`, or the target of a `compute` block) —
    // its value is filled per row from the compute expression below (FEAT-procreport-2).
    var src: std.ArrayList(?usize) = .empty;
    var onames: std.ArrayList([]const u8) = .empty; // output column name (headers + compute refs)
    if (cols.items.len > 0) {
        for (cols.items) |c| {
            if (defFor(defs.items, c).computed or isComputeTarget(computes.items, c)) {
                try src.append(arena, null);
                try onames.append(arena, c);
            } else if (ds.indexOf(c)) |ix| {
                try src.append(arena, ix);
                try onames.append(arena, c);
            }
            // else: a COLUMN name that is neither a source var nor computed is
            // dropped (unchanged pre-existing behavior).
        }
    } else {
        for (ds.columns.items, 0..) |col, ix| {
            try src.append(arena, ix);
            try onames.append(arena, col.name);
        }
    }
    if (src.items.len == 0) {
        unsupported("PROC REPORT: no columns");
        return;
    }

    // tick240 F5: a DEFINE for a variable that is not an output column was a silent
    // no-op (SAS: "Variable X not found"). Fail loud.
    for (defs.items) |d| {
        var found = false;
        for (onames.items) |on| if (eqi(on, d.name)) {
            found = true;
            break;
        };
        if (!found) {
            unsupported("PROC REPORT: DEFINE names a variable not in the COLUMN list");
            return;
        }
    }

    const n = src.items.len;
    // each source column indexes a real column; the width scan and row loop below
    // read row[ix] on every row, so an out-of-range index = wrong report column.
    for (src.items) |maybe_ix| if (maybe_ix) |ix| assert(ix < ds.columns.items.len);

    var has_computed = false;
    for (src.items) |maybe_ix| {
        if (maybe_ix == null) has_computed = true;
    }
    // A compute block that ASSIGNS a computed column not in the COLUMN list would
    // be a silent no-op — fail loud. A `compute after|before` that only holds LINE
    // statements (no `=` assignment) needs no computed column, so it is allowed.
    var assigns_a_col = computes.items.len > 0;
    for (after_computes.items) |ac| {
        for (ac.body) |tok| if (tok.tag == .eq) {
            assigns_a_col = true;
            break;
        };
    }
    if (assigns_a_col and !has_computed) {
        unsupported("PROC REPORT COMPUTE names a column not in the COLUMN list");
        return;
    }

    // per-column metadata: header label, numeric?, and its define (GROUP / stat).
    const headers = try arena.alloc([]const u8, n);
    const is_num = try arena.alloc(bool, n);
    const meta = try arena.alloc(Define, n);
    for (src.items, 0..) |maybe_ix, j| {
        if (maybe_ix) |ix| {
            const col = ds.columns.items[ix];
            meta[j] = defFor(defs.items, col.name);
            headers[j] = meta[j].label orelse col.name;
            is_num[j] = col.type == .num;
        } else {
            // COMPUTED column: numeric-only in increment-1.
            meta[j] = defFor(defs.items, onames.items[j]);
            headers[j] = meta[j].label orelse onames.items[j];
            is_num[j] = true;
        }
    }

    // GROUP variables collapse the listing to one summarized row per level; each
    // analysis column shows its stat (SUM by default for a numeric) over the group,
    // a non-group char column shows the level's value (BUG-reportgroup).
    var gcols: std.ArrayList(GCol) = .empty;
    for (src.items, 0..) |maybe_ix, j| if (maybe_ix) |ix| {
        if (meta[j].group) try gcols.append(arena, .{ .ix = ix, .desc = meta[j].desc, .mode = meta[j].order_mode });
    };
    // A GROUP report with a PLAIN per-row COMPUTE (or a computed column with no
    // break to attach a summary line to) runs the compute over aggregated rows — a
    // later increment (fail loud). A break-attached `compute after` is allowed: it
    // fills the SUMMARIZE rows only, handled below (compute-at-break).
    const any_break = break_after != null or rbreak_after or break_before != null or rbreak_before;
    if (has_computed and gcols.items.len > 0 and (computes.items.len > 0 or !any_break)) {
        unsupported("PROC REPORT COMPUTE with GROUP");
        return;
    }

    // ORDER usage: stable-sort a COPY of the rows by the ORDER columns (left to
    // right in the COLUMN list) — a REPORT never reorders its input dataset.
    var okeys: std.ArrayList(SortKey) = .empty;
    for (src.items, 0..) |maybe_ix, j| if (maybe_ix) |ix| {
        if (meta[j].order) {
            // ORDER=FREQ/DATA/FORMATTED sequences by frequency/appearance/label — the
            // ORDER-usage detail path only knows value sort. Honored on GROUP vars
            // (collectGroupsRows) but fail loud here rather than silently value-sort.
            // ponytail: ORDER-usage FREQ/DATA needs per-value counts; deferred.
            if (meta[j].order_mode != .internal) {
                unsupported("PROC REPORT: ORDER=FREQ/DATA/FORMATTED is only supported on a GROUP variable");
                return;
            }
            try okeys.append(arena, .{ .idx = ix, .desc = meta[j].desc });
        }
    };
    var rows = ds.rows.items;
    if (okeys.items.len > 0) {
        rows = try arena.dupe([]const Value, rows);
        sortRows(rows, okeys.items);
    }

    // BREAK/RBREAK AFTER / SUMMARIZE (FEAT-procreport-2): validate the break target
    // is a displayed GROUP/ORDER column and that there are detail rows to aggregate.
    // Summary rows are interleaved into `body` after it is built (below).
    const needs_break = any_break;
    // compute-at-break: a `compute after|before` block with no matching break to
    // attach to would be a silent no-op — fail loud, and pin each block to a break.
    if (after_computes.items.len > 0 and !needs_break) {
        unsupported("PROC REPORT COMPUTE AFTER/BEFORE without a matching BREAK/RBREAK");
        return;
    }
    for (after_computes.items) |ac| {
        const brk_var = if (ac.before) break_before else break_after;
        const has_rbreak = if (ac.before) rbreak_before else rbreak_after;
        const ok = if (ac.bvar) |bv| (brk_var != null and eqi(brk_var.?, bv)) else has_rbreak;
        if (!ok) {
            unsupported("PROC REPORT COMPUTE AFTER/BEFORE a break/rbreak that is not declared");
            return;
        }
    }
    if (needs_break and has_computed) {
        // compute-at-break: a computed column on a break/rbreak report is supported
        // ONLY via `compute after|before` blocks that fill the SUMMARIZE rows. A
        // plain per-row COMPUTE alongside a break, or a computed column with no
        // `compute after|before` to drive it, is a later increment — fail loud.
        if (computes.items.len > 0 or after_computes.items.len == 0) {
            unsupported("PROC REPORT BREAK/RBREAK with a plain COMPUTE or an undriven computed column");
            return;
        }
    }
    if (needs_break and gcols.items.len == 0 and okeys.items.len == 0) {
        unsupported("PROC REPORT BREAK/RBREAK requires a GROUP or ORDER column");
        return;
    }
    // Resolve each declared BREAK var to its column index + break-boundary key
    // (group/order src cols at/left of it); RBREAK has no var. `after_bk`/`before_bk`
    // stay null when that placement isn't used, so the interleave skips it.
    const after_bk = if (break_after) |bv| (try breakKey(arena, onames.items, meta, src.items, n, bv)) orelse return else null;
    const before_bk = if (break_before) |bv| (try breakKey(arena, onames.items, meta, src.items, n, bv)) orelse return else null;

    var body: std.ArrayList(Row) = .empty; // each detail/group row = .cells; LINE rows added to `final` on interleave
    var body_under: std.ArrayList([]const []const Value) = .empty; // raw rows behind each body row (break sums)
    var body_rep: std.ArrayList([]const Value) = .empty; // representative row per body row (break-boundary compare)
    if (gcols.items.len > 0) {
        // BUG-reportordergroupmix: ORDER-usage columns join the GROUP key so each
        // distinct (order…, group…) tuple is its own summarized row, ordered by the
        // ORDER columns (DESCENDING-aware) then the GROUP columns. Without this the
        // grouping key was GROUP-only, collapsing rows across ORDER values, dropping
        // later ORDER levels and mislabelling the survivors. Group-only (no ORDER)
        // keeps the exact .internal sort on the group cols — byte-identical.
        const gidx = try arena.alloc(usize, gcols.items.len);
        for (gcols.items, 0..) |g, k| gidx[k] = g.ix;
        const groups = if (okeys.items.len > 0) blk: {
            var kk: std.ArrayList(usize) = .empty; // hash/eq key: order cols then group cols
            var sk: std.ArrayList(SortKey) = .empty; // order cols (with desc) then group cols (DESCENDING-aware, tick240 F1)
            for (okeys.items) |k| {
                try kk.append(arena, k.idx);
                try sk.append(arena, k);
            }
            for (gcols.items) |g| {
                // FREQ/DATA group sequencing can't compose with the ORDER value sort
                // here — fail loud rather than emit a wrong table (ponytail: deferred).
                if (g.mode != .internal) {
                    unsupported("PROC REPORT: GROUP ORDER=FREQ/DATA with an ORDER column is unsupported");
                    return;
                }
                try kk.append(arena, g.ix);
                try sk.append(arena, .{ .idx = g.ix, .desc = g.desc });
            }
            sortRows(rows, sk.items); // rows is the ORDER-sorted dupe; re-sort adds the group secondary keys
            break :blk try collectGroupsRows(arena, rows, kk.items, .data); // .data → first-appearance = fully sorted order
        } else grp: {
            // Group-only sequencing (tick240 F1/F3). Default INTERNAL-ascending is the
            // historical .internal sort (byte-identical). FREQ/DATA sequence the whole
            // group set; INTERNAL+DESCENDING pre-sorts rows by the group keys (desc-aware)
            // then keeps that order via .data. FORMATTED needs format bands — fail loud.
            var freq = false;
            var data = false;
            var any_desc = false;
            for (gcols.items) |g| {
                switch (g.mode) {
                    .freq => freq = true,
                    .data => data = true,
                    .formatted => {
                        unsupported("PROC REPORT: GROUP ORDER=FORMATTED is unsupported");
                        return;
                    },
                    .internal => {},
                }
                if (g.desc) any_desc = true;
            }
            if (freq) break :grp try collectGroupsRows(arena, rows, gidx, .freq);
            if (data) break :grp try collectGroupsRows(arena, rows, gidx, .data);
            if (any_desc) {
                var sk: std.ArrayList(SortKey) = .empty;
                for (gcols.items) |g| try sk.append(arena, .{ .idx = g.ix, .desc = g.desc });
                rows = try arena.dupe([]const Value, rows);
                sortRows(rows, sk.items);
                break :grp try collectGroupsRows(arena, rows, gidx, .data); // sorted → first-appearance = desc order
            }
            break :grp try collectGroupsRows(arena, rows, gidx, .internal); // byte-identical to the old path
        };
        var prev_rep: ?[]const Value = null; // for blanking repeated ORDER/GROUP values (SAS listing)
        for (groups) |g| {
            const texts = try arena.alloc([]const u8, n);
            var order_changed = prev_rep == null;
            var group_changed = prev_rep == null; // GROUP repeat-blanking tracks GROUP cols only
            for (src.items, 0..) |maybe_ix, j| {
                const ix = maybe_ix orelse {
                    // COMPUTED column on a GROUP body row: blank — only the break's
                    // `compute after` fills it, on the SUMMARIZE line (compute-at-break).
                    texts[j] = "";
                    continue;
                };
                if (meta[j].order) {
                    // ORDER value prints only when it or an ORDER col to its LEFT
                    // changed vs the previous row; else SAS blanks the repeat.
                    if (!order_changed and cmpValue(g.rep[ix], prev_rep.?[ix]) != .eq) order_changed = true;
                    texts[j] = if (!order_changed) "" else try rptCell(arena, g.rep[ix], meta[j], ds.columns.items[ix]);
                } else if (meta[j].group) {
                    // GROUP value prints only when it or a GROUP col to its LEFT
                    // changed vs the previous row; else SAS blanks the repeat —
                    // Procedures Guide 7th ed printed p.2094: "PROC REPORT does not
                    // repeat the values of a group variable from one row to the next
                    // if the value does not change, unless a group variable to its
                    // left changes values" (NOTE-reportgroupblank).
                    if (!group_changed and cmpValue(g.rep[ix], prev_rep.?[ix]) != .eq) group_changed = true;
                    texts[j] = if (!group_changed) "" else try rptCell(arena, g.rep[ix], meta[j], ds.columns.items[ix]);
                } else texts[j] = if (!is_num[j])
                    try rptCell(arena, g.rep[ix], meta[j], ds.columns.items[ix]) // a char display column prints every row
                else
                    try rptCell(arena, .{ .num = statValue(meta[j].stat orelse .sum, computeStats(g.rows, ix, null)) }, meta[j], ds.columns.items[ix]);
            }
            prev_rep = g.rep;
            try body.append(arena, .{ .cells = texts });
            if (needs_break) {
                try body_under.append(arena, g.rows);
                try body_rep.append(arena, g.rep);
            }
        }
    } else {
        // ALL-analysis report — no GROUP/ORDER column and no DISPLAY column, i.e.
        // every column an analysis variable: SAS 9.4 collapses the listing to ONE
        // summary row, default statistic SUM ("a report that contains only analysis
        // variables has one row") (BUG-reportanalysis). A char column defaults to
        // DISPLAY usage and keeps the detail report, as does `define x / display`.
        var all_analysis = okeys.items.len == 0;
        if (all_analysis) for (0..n) |j| {
            // a computed column keeps the detail report (its value is per-row)
            if (src.items[j] == null or meta[j].display or (!is_num[j] and meta[j].stat == null)) {
                all_analysis = false;
                break;
            }
        };
        if (all_analysis) {
            const texts = try arena.alloc([]const u8, n);
            for (src.items, 0..) |maybe_ix, j| {
                const ix = maybe_ix.?; // computed forces all_analysis = false above
                texts[j] = try rptCell(arena, .{ .num = statValue(meta[j].stat orelse .sum, computeStats(rows, ix, null)) }, meta[j], ds.columns.items[ix]);
            }
            try body.append(arena, .{ .cells = texts });
        } else {
            // Detail listing — the one path that carries COMPUTED columns. Parse the
            // compute blocks ONCE (arithmetic over displayed numeric columns), then
            // per row bind the source values into a PDV and evaluate (FEAT-procreport-2).
            var pdv = Pdv.init(arena);
            var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags };
            const assigns = if (has_computed)
                (try parseComputes(arena, diags, &pdv, computes.items, src.items, onames.items, ds)) orelse return // null → unsupported already reported
            else
                &[_]Assign{};

            var prev: ?[]const Value = null;
            for (rows) |row| {
                const texts = try arena.alloc([]const u8, n);
                // An ORDER column's value prints only when it or an ORDER column to
                // its LEFT changes — SAS listing blanks the repeats (doc, above).
                var changed = prev == null;
                if (has_computed) {
                    // bind this row's source columns, then run each `col = expr;`
                    for (src.items, 0..) |maybe_ix, j| if (maybe_ix) |ix| {
                        if (is_num[j]) try pdv.set(ds.columns.items[ix].name, row[ix]);
                    };
                    for (assigns) |asg| try pdv.set(asg.lhs, try ev.eval(asg.expr));
                }
                for (src.items, 0..) |maybe_ix, j| {
                    if (maybe_ix) |ix| {
                        if (meta[j].order and !changed and cmpValue(row[ix], prev.?[ix]) != .eq) changed = true;
                        texts[j] = if (meta[j].order and !changed) "" else try rptCell(arena, row[ix], meta[j], ds.columns.items[ix]);
                    } else {
                        // COMPUTED column: its bound value (numeric-only) through the define's FORMAT=
                        texts[j] = try rptCell(arena, pdv.get(onames.items[j]) orelse Value.missing, meta[j], .{ .name = onames.items[j], .type = .num });
                    }
                }
                prev = row;
                try body.append(arena, .{ .cells = texts });
                if (needs_break) {
                    const one = try arena.alloc([]const Value, 1);
                    one[0] = row;
                    try body_under.append(arena, one);
                    try body_rep.append(arena, row);
                }
            }
        }
    }

    // Interleave BREAK/RBREAK SUMMARIZE lines. An AFTER break line falls after the
    // last detail row of each run sharing the break's boundary key; a BEFORE break
    // line falls before the run's first detail row; the grand total sums the whole
    // report (FEAT-procreport-2; BEFORE + LINE added in rest3).
    if (needs_break) {
        // compute-at-break: parse the `compute after` blocks ONCE against a PDV of
        // the referenceable numeric names, then evaluate them on each SUMMARIZE row
        // (below) over that row's aggregated values. Null pdv/ev = a plain break
        // with no computes → reportSummary skips all compute work (byte-identical).
        var s_pdv = Pdv.init(arena);
        var s_ev: eval.Evaluator = .{ .arena = arena, .pdv = &s_pdv, .diags = diags };
        const after_blocks: []const AfterBlock = if (after_computes.items.len > 0)
            (try parseAfterComputes(arena, diags, &s_pdv, after_computes.items, src.items, onames.items, ds)) orelse return
        else
            &[_]AfterBlock{};
        const pdv_p: ?*Pdv = if (after_computes.items.len > 0) &s_pdv else null;
        const ev_p: ?*eval.Evaluator = if (after_computes.items.len > 0) &s_ev else null;

        var final: std.ArrayList(Row) = .empty;
        var accum: std.ArrayList([]const Value) = .empty; // raw rows since the last break line
        // RBREAK BEFORE: grand total (and its LINE lines) before all detail rows.
        if (rbreak_before and body.items.len > 0) {
            try final.append(arena, .{ .cells = try reportSummary(arena, src.items, meta, onames.items, is_num, ds, rows, null, null, afterAssigns(after_blocks, null, true), pdv_p, ev_p) });
            for (afterLines(after_blocks, null, true)) |ls| try final.append(arena, .{ .line = try renderLine(arena, ls, pdv_p.?) });
        }
        for (body.items, 0..) |texts, a| {
            // BREAK BEFORE <var>: at the START of a run, summarize the whole run first.
            if (before_bk) |bk| {
                const run_start = a == 0 or !byEqual(body_rep.items[a - 1], body_rep.items[a], bk.key);
                if (run_start) {
                    var run_rows: std.ArrayList([]const Value) = .empty;
                    var b = a;
                    while (b < body.items.len and byEqual(body_rep.items[a], body_rep.items[b], bk.key)) : (b += 1)
                        try run_rows.appendSlice(arena, body_under.items[b]);
                    try final.append(arena, .{ .cells = try reportSummary(arena, src.items, meta, onames.items, is_num, ds, run_rows.items, src.items[bk.j].?, body_rep.items[a], afterAssigns(after_blocks, break_before, true), pdv_p, ev_p) });
                    for (afterLines(after_blocks, break_before, true)) |ls| try final.append(arena, .{ .line = try renderLine(arena, ls, pdv_p.?) });
                }
            }
            try final.append(arena, texts);
            try accum.appendSlice(arena, body_under.items[a]);
            if (after_bk) |bk| {
                const boundary = a + 1 == body.items.len or !byEqual(body_rep.items[a], body_rep.items[a + 1], bk.key);
                if (boundary) {
                    try final.append(arena, .{ .cells = try reportSummary(arena, src.items, meta, onames.items, is_num, ds, accum.items, src.items[bk.j].?, body_rep.items[a], afterAssigns(after_blocks, break_after, false), pdv_p, ev_p) });
                    for (afterLines(after_blocks, break_after, false)) |ls| try final.append(arena, .{ .line = try renderLine(arena, ls, pdv_p.?) });
                    accum.clearRetainingCapacity();
                }
            }
        }
        // grand total over ALL detail rows — SUM/MEAN over raw obs, not over subtotals.
        // rbreakemptybody: an empty (zero-obs / WHERE-filtered) report is header-only —
        // skip the grand total rather than emit a spurious line of missings.
        if (rbreak_after and body.items.len > 0) {
            try final.append(arena, .{ .cells = try reportSummary(arena, src.items, meta, onames.items, is_num, ds, rows, null, null, afterAssigns(after_blocks, null, false), pdv_p, ev_p) });
            for (afterLines(after_blocks, null, false)) |ls| try final.append(arena, .{ .line = try renderLine(arena, ls, pdv_p.?) });
        }
        body = final;
    }

    // NOPRINT (tick240 F4): a `/ noprint` column is still computed and used for
    // grouping/ordering above, but omitted from the printed table. `show` is the
    // displayed projection; with no NOPRINT it is all n columns → byte-identical.
    var show: std.ArrayList(usize) = .empty;
    for (0..n) |j| if (!meta[j].noprint) try show.append(arena, j);
    const sh = show.items;
    if (sh.len == 0) return; // every column suppressed → nothing to print

    // widths from the actual output (grouped sums can be wider than any raw value);
    // a raw LINE row lays out free-form and never constrains a column width.
    const headers_s = try arena.alloc([]const u8, sh.len);
    const is_num_s = try arena.alloc(bool, sh.len);
    const widths = try arena.alloc(usize, sh.len);
    for (sh, 0..) |j, k| {
        var w = headers[j].len;
        for (body.items) |row| if (row == .cells) {
            w = @max(w, row.cells[j].len);
        };
        // A numeric column WITHOUT a format gets SAS's wider default (+2); a column
        // with an explicit FORMAT= renders at exactly the format width — the same
        // width PROC PRINT uses (BUG-reportnumwidth). rptCell already padded the cell
        // to the format width, so dropping the +2 leaves the SAS-correct width; the
        // 2-blank inter-column gutter is separate (emitReportLine, SPACING=2).
        const has_fmt = meta[j].format != null or (src.items[j] != null and ds.columns.items[src.items[j].?].format != null);
        if (is_num[j] and !has_fmt) w += 2;
        // WIDTH= fixes the column width. ponytail: SAS would WRAP a longer
        // header over several lines; we just never go narrower than it.
        if (meta[j].width) |dw| w = @max(dw, headers[j].len);
        headers_s[k] = headers[j];
        is_num_s[k] = is_num[j];
        widths[k] = w;
    }

    try emitReportLine(arena, out, headers_s, is_num_s, widths);
    try out.append(arena, '\n'); // blank line under the header
    for (body.items) |row| switch (row) {
        .cells => |texts| {
            const proj = try arena.alloc([]const u8, sh.len);
            for (sh, 0..) |j, k| proj[k] = texts[j];
            try emitReportLine(arena, out, proj, is_num_s, widths);
        },
        .line => |ln| {
            try out.appendSlice(arena, std.mem.trimEnd(u8, ln, " "));
            try out.append(arena, '\n');
        },
    };
}

/// One BREAK/RBREAK SUMMARIZE line: numeric ANALYSIS columns show their stat
/// (SUM default, or the DEFINE's `analysis <stat>`) over `accum` (the break group's
/// raw detail rows, or the whole report for a grand total); the break variable
/// shows its value (`bix`/`rep`, both null for RBREAK); every other column is blank
/// — SAS's summary-line layout (FEAT-procreport-2).
fn reportSummary(arena: std.mem.Allocator, src: []const ?usize, meta: []const Define, onames: []const []const u8, is_num: []const bool, ds: *Dataset, accum: []const []const Value, bix: ?usize, rep: ?[]const Value, assigns: []const Assign, pdv: ?*Pdv, ev: ?*eval.Evaluator) diag.Error![]const []const u8 {
    const texts = try arena.alloc([]const u8, src.len);
    // Reset the compute PDV so a numeric column absent from THIS summary row
    // (blank cell) can't leak its prior row's value into a `compute after` expr.
    if (pdv) |p| for (src, 0..) |maybe_ix, j| {
        if (maybe_ix) |ix| {
            if (ds.columns.items[ix].type == .num) try p.set(ds.columns.items[ix].name, Value.missing);
        } else try p.set(onames[j], Value.missing);
    };
    for (src, 0..) |maybe_ix, j| {
        const ix = maybe_ix orelse {
            texts[j] = ""; // COMPUTED column: filled by the compute-after eval below (else blank)
            continue;
        };
        if (is_num[j] and !meta[j].group and !meta[j].order and !meta[j].display) {
            const v = Value{ .num = statValue(meta[j].stat orelse .sum, computeStats(accum, ix, null)) };
            texts[j] = try rptCell(arena, v, meta[j], ds.columns.items[ix]);
            if (pdv) |p| if (ds.columns.items[ix].type == .num) try p.set(ds.columns.items[ix].name, v);
        } else if (bix != null and ix == bix.? and rep != null) {
            texts[j] = try rptCell(arena, rep.?[ix], meta[j], ds.columns.items[ix]);
            if (pdv) |p| if (ds.columns.items[ix].type == .num) try p.set(ds.columns.items[ix].name, rep.?[ix]);
        } else texts[j] = "";
    }
    // compute-at-break: eval each `col = <arithmetic>;` over the aggregated summary
    // values just bound, then fill the computed columns ON this SUMMARIZE line.
    if (assigns.len > 0) {
        const p = pdv.?;
        for (assigns) |asg| try p.set(asg.lhs, try ev.?.eval(asg.expr));
        for (src, 0..) |maybe_ix, j| if (maybe_ix == null) {
            texts[j] = try rptCell(arena, p.get(onames[j]) orelse Value.missing, meta[j], .{ .name = onames[j], .type = .num });
        };
    }
    return texts;
}

/// The `define` for column `name` (default usage when none given).
fn defFor(defs: []const Define, name: []const u8) Define {
    for (defs) |d| if (eqi(d.name, name)) return d;
    return .{ .name = name };
}

/// True when a `compute <col>;` block targets `name` (FEAT-procreport-2).
fn isComputeTarget(computes: []const Compute, name: []const u8) bool {
    for (computes) |c| if (eqi(c.col, name)) return true;
    return false;
}

/// Position of column `name` in the report's COLUMN list (`onames` order); a
/// name not in the list sorts last. Orders COMPUTE evaluation by column, not by
/// source text (BUG-reportcomputeorder).
fn colPosReport(onames: []const []const u8, name: []const u8) usize {
    for (onames, 0..) |nm, j| if (eqi(nm, name)) return j;
    return onames.len;
}

/// The PDV name each COLUMN-list position is referenceable by: a source numeric
/// column by its stored name, a computed column by its output name, "" for a
/// char/unavailable column (not addressable in an arithmetic compute). Parallel
/// to `src`; used to resolve `_c<n>_` absolute column refs (FEAT-procreport rest4).
fn pdvColNames(arena: std.mem.Allocator, src: []const ?usize, onames: []const []const u8, ds: *Dataset) ![]const []const u8 {
    const names = try arena.alloc([]const u8, src.len);
    for (src, 0..) |maybe_ix, j| {
        if (maybe_ix) |ix| {
            names[j] = if (ds.columns.items[ix].type == .num) ds.columns.items[ix].name else "";
        } else names[j] = onames[j]; // computed columns are numeric in this increment
    }
    return names;
}

/// Resolve a `_c<n>_` absolute column reference to the PDV name of the Nth
/// COLUMN-list column (1-based). Returns null when `text` is not the `_cN_` form,
/// N is out of range, or that column is not a referenceable numeric column
/// (char/unavailable) — the caller then fails loud (FEAT-procreport rest4).
fn resolveCn(text: []const u8, pdvNames: []const []const u8) ?[]const u8 {
    if (text.len < 4 or text[0] != '_' or text[text.len - 1] != '_') return null;
    if (!(text[1] == 'c' or text[1] == 'C')) return null;
    const digits = text[2 .. text.len - 1];
    if (digits.len == 0) return null;
    for (digits) |ch| if (!std.ascii.isDigit(ch)) return null;
    const n = std.fmt.parseInt(usize, digits, 10) catch return null;
    if (n < 1 or n > pdvNames.len) return null;
    const nm = pdvNames[n - 1];
    return if (nm.len == 0) null else nm;
}

// A parsed compute assignment: `lhs = <arithmetic expr>` (FEAT-procreport-2).
const Assign = struct { lhs: []const u8, expr: *const ast.Expr };

// A parsed `compute after|before [<var>]` block (compute-at-break): the break
// variable it attaches to (null = RBREAK grand total), whether it is a BEFORE
// block, its assignments, and any LINE statements to render on the summary row.
const AfterBlock = struct { bvar: ?[]const u8, before: bool, assigns: []const Assign, lines: []const LineSpec };

/// Column position + break-boundary key of a resolved BREAK variable.
const BreakKey = struct { j: usize, key: []const usize };

/// Resolve BREAK var `bvar` to its COLUMN position and break-boundary key (the
/// group/order source columns at or left of it — a run shares these values). Fails
/// LOUD + returns null when `bvar` is not a displayed GROUP/ORDER column.
fn breakKey(arena: std.mem.Allocator, onames: []const []const u8, meta: []const Define, src: []const ?usize, n: usize, bvar: []const u8) diag.Error!?BreakKey {
    const bj = colPosReport(onames, bvar);
    if (bj >= n or !(meta[bj].group or meta[bj].order)) {
        unsupported("PROC REPORT BREAK a non-GROUP/non-ORDER (or undisplayed) column");
        return null;
    }
    var key: std.ArrayList(usize) = .empty;
    for (src, 0..) |maybe_ix, j| if (maybe_ix) |ix| {
        if ((meta[j].group or meta[j].order) and j <= bj) try key.append(arena, ix);
    };
    return .{ .j = bj, .key = key.items };
}

/// Pre-load `pdv` with a numeric slot for every referenceable name: each source
/// numeric column by its stored name + every computed column. Shared by plain
/// COMPUTE and compute-after so a compute expression can `set`/`eval` by name.
fn loadComputePdv(pdv: *Pdv, src: []const ?usize, onames: []const []const u8, ds: *Dataset) !void {
    for (src, 0..) |maybe_ix, j| {
        if (maybe_ix) |ix| {
            if (ds.columns.items[ix].type == .num) _ = try pdv.define(ds.columns.items[ix].name, .num);
        } else _ = try pdv.define(onames[j], .num);
    }
}

/// Parse one compute block body into `col = <arithmetic>;` assignments (appended
/// to `out`). Supports simple arithmetic (`+ - * / ( )`, numeric literals),
/// referenceable column names, and `_c<n>_` absolute column refs (rewritten to
/// the Nth column's PDV name via `pdvNames`; FEAT-procreport rest4). Anything
/// else — IF/THEN, CALL DEFINE, functions, character ops, a `.stat` aggregate
/// ref, an unresolvable reference — fails LOUD via `unsupported()` and returns
/// false (no partial/wrong report). LINE is allowed only in after/before blocks
/// (out_lines non-null). The parser/evaluator are the shared DATA-step stack.
fn parseComputeBody(arena: std.mem.Allocator, diags: *diag.Diagnostics, pdv: *Pdv, pdvNames: []const []const u8, body: []const Token, out: *std.ArrayList(Assign), out_lines: ?*std.ArrayList(LineSpec)) diag.Error!bool {
    var k: usize = 0;
    while (k < body.len) {
        if (body[k].tag == .semicolon) {
            k += 1;
            continue;
        }
        // LINE statement (basic) — only in a `compute after|before` break block
        // (out_lines non-null); a LINE in a plain per-row `compute <col>` has no
        // summary position and fails loud below via the assignment guard.
        if (body[k].tag == .name and eqi(body[k].text, "line") and out_lines != null) {
            k += 1;
            const spec = (try parseLine(arena, pdv, body, &k)) orelse return false;
            try out_lines.?.append(arena, spec);
            continue;
        }
        // Every compute statement in increment-1 must be `name = <expr>;`.
        if (body[k].tag != .name or !atTag(body, k + 1, .eq)) {
            unsupported("PROC REPORT COMPUTE: only simple `col = <arithmetic>;` assignments (no IF/CALL DEFINE, only LINE in after/before)");
            return false;
        }
        const lhs = body[k].text;
        k += 2; // past `name =`
        const estart = k;
        while (k < body.len and body[k].tag != .semicolon) k += 1;
        if (k == estart) {
            unsupported("PROC REPORT COMPUTE: empty right-hand side");
            return false;
        }
        // Mutable copy so `_c<n>_` refs can be rewritten to the real column name
        // in place before parsing (the shared evaluator has no notion of _cN_).
        const etoks = try arena.dupe(Token, body[estart..k]);
        // Arithmetic-only guard: reject anything that isn't a number, a
        // + - * / ( ) operator, or a name that resolves to a referenceable
        // numeric column — this is what makes an unresolvable reference or an
        // unsupported form fail LOUD rather than bind to silent missing.
        for (etoks) |*tok| switch (tok.tag) {
            .number, .plus, .minus, .star, .slash, .lparen, .rparen => {},
            .name => if (pdv.indexOf(tok.text) == null) {
                // `_c<n>_` absolute column ref → the Nth COLUMN's numeric value
                // (FEAT-procreport rest4). Rewrite to that column's PDV name so
                // the shared evaluator resolves it like any other column.
                if (resolveCn(tok.text, pdvNames)) |nm| {
                    tok.text = nm;
                } else {
                    unsupported("PROC REPORT COMPUTE: expression references a name that is not a displayed numeric column");
                    return false;
                }
            },
            else => {
                unsupported("PROC REPORT COMPUTE: only arithmetic (+ - * / parens, numeric literals, _cN_) over displayed numeric columns");
                return false;
            },
        };
        var p = pe.Parser.init(arena, try withReportEof(arena, etoks), diags);
        const e = p.parseExpr() catch {
            unsupported("PROC REPORT COMPUTE: could not parse the arithmetic expression");
            return false;
        };
        try out.append(arena, .{ .lhs = lhs, .expr = e });
    }
    return true;
}

/// Parse every plain `compute <col>` block into a flat, ordered list of `col = expr;`
/// assignments over the report's displayed numeric columns. `pdv` is pre-loaded
/// here with the referenceable names (see loadComputePdv), so the row loop can
/// `set`/`eval` against it. Returns null (unsupported already reported) on any
/// non-arithmetic form.
fn parseComputes(arena: std.mem.Allocator, diags: *diag.Diagnostics, pdv: *Pdv, computes: []const Compute, src: []const ?usize, onames: []const []const u8, ds: *Dataset) diag.Error!?[]const Assign {
    try loadComputePdv(pdv, src, onames, ds);
    const pdv_names = try pdvColNames(arena, src, onames, ds);
    // SAS 9.4 runs COMPUTE blocks in COLUMN order (left-to-right in the COLUMN
    // statement), NOT source-text order — a block for a later column can be
    // physically written before the block it depends on and must still see that
    // earlier column's just-computed value (BUG-reportcomputeorder). Stable-sort
    // the blocks by their target column's position in the column list; a genuine
    // forward/circular ref that column order still can't resolve stays unresolved
    // (missing + the usual NOTE), never masked.
    const ordered = try arena.dupe(Compute, computes);
    std.sort.block(Compute, ordered, onames, struct {
        fn less(names: []const []const u8, a: Compute, b: Compute) bool {
            return colPosReport(names, a.col) < colPosReport(names, b.col);
        }
    }.less);
    var assigns: std.ArrayList(Assign) = .empty;
    for (ordered) |cb| if (!try parseComputeBody(arena, diags, pdv, pdv_names, cb.body, &assigns, null)) return null;
    return assigns.items;
}

/// Parse each `compute after [<var>]` block into an AfterBlock keyed by its break
/// variable (compute-at-break). Same PDV/arithmetic rules as parseComputes; the
/// summary-row evaluator (reportSummary) binds the aggregated values, then runs
/// these assignments to fill the computed columns on that SUMMARIZE line.
fn parseAfterComputes(arena: std.mem.Allocator, diags: *diag.Diagnostics, pdv: *Pdv, blocks: []const AfterSrc, src: []const ?usize, onames: []const []const u8, ds: *Dataset) diag.Error!?[]const AfterBlock {
    try loadComputePdv(pdv, src, onames, ds);
    const pdv_names = try pdvColNames(arena, src, onames, ds);
    var out: std.ArrayList(AfterBlock) = .empty;
    for (blocks) |b| {
        var assigns: std.ArrayList(Assign) = .empty;
        var lines: std.ArrayList(LineSpec) = .empty;
        if (!try parseComputeBody(arena, diags, pdv, pdv_names, b.body, &assigns, &lines)) return null;
        try out.append(arena, .{ .bvar = b.bvar, .before = b.before, .assigns = assigns.items, .lines = lines.items });
    }
    return out.items;
}

/// True when block `b` attaches to the break identified by `bvar`
/// (null = RBREAK grand total) at the requested BEFORE/AFTER placement.
fn afterMatch(b: AfterBlock, bvar: ?[]const u8, before: bool) bool {
    if (b.before != before) return false;
    return if (bvar) |v| (b.bvar != null and eqi(b.bvar.?, v)) else b.bvar == null;
}

/// The assignments for a given break placement; empty when no block matches —
/// its computed cells stay blank.
fn afterAssigns(blocks: []const AfterBlock, bvar: ?[]const u8, before: bool) []const Assign {
    for (blocks) |b| if (afterMatch(b, bvar, before)) return b.assigns;
    return &[_]Assign{};
}

/// The LINE templates for a given break placement (empty when none).
fn afterLines(blocks: []const AfterBlock, bvar: ?[]const u8, before: bool) []const LineSpec {
    for (blocks) |b| if (afterMatch(b, bvar, before)) return b.lines;
    return &[_]LineSpec{};
}

/// Parse a LINE statement's items (from just past `line` to its `;`), validating
/// each var ref resolves to a displayed numeric column in `pdv`. Advances `k` past
/// the terminating `;`. Fails LOUD + returns null on an advanced/unbounded form
/// (`#n` line pointer, repeated-char `'x' * n`, pointer expr, unknown var).
fn parseLine(arena: std.mem.Allocator, pdv: *Pdv, body: []const Token, k: *usize) diag.Error!?LineSpec {
    var items: std.ArrayList(LineItem) = .empty;
    while (k.* < body.len and body[k.*].tag != .semicolon) {
        const tk = body[k.*];
        switch (tk.tag) {
            .string => {
                try items.append(arena, .{ .lit = tk.text });
                k.* += 1;
            },
            .at => {
                k.* += 1;
                if (!(k.* < body.len and body[k.*].tag == .number)) {
                    unsupported("PROC REPORT LINE: @ pointer must be @<column-number>");
                    return null;
                }
                const col = std.fmt.parseInt(usize, body[k.*].text, 10) catch {
                    unsupported("PROC REPORT LINE: @ pointer is not an integer column");
                    return null;
                };
                try items.append(arena, .{ .at = col });
                k.* += 1;
            },
            .name => {
                const nm = tk.text;
                if (pdv.indexOf(nm) == null) {
                    unsupported("PROC REPORT LINE: variable is not a displayed numeric column (char/unknown refs unsupported)");
                    return null;
                }
                k.* += 1;
                // Optional format spec, recognized only when it ends in a `.`
                // (a bare following name is a second variable, not a format).
                const fend = lineFmtEnd(body, k.*);
                var fmt: ?[]const u8 = null;
                if (fend > k.*) {
                    fmt = try joinFmt(arena, body[k.*..fend]);
                    k.* = fend;
                }
                try items.append(arena, .{ .var_ref = .{ .name = nm, .fmt = fmt } });
            },
            .hash => {
                unsupported("PROC REPORT LINE: #<n> line pointer unsupported");
                return null;
            },
            else => {
                unsupported("PROC REPORT LINE: only literal text, a numeric var (+format), and @<col> pointers (no repeated-char/pointer exprs)");
                return null;
            },
        }
    }
    if (k.* < body.len) k.* += 1; // consume the `;`
    return items.items;
}

/// End of a LINE format spec `[$]name[.d] | number` that ENDS in a period; returns
/// `start` (no format) when there's no trailing dot — so `line a b;` reads two vars
/// while `line a dollar8.;` reads var `a` formatted (rest3). Mirrors fmtSpecEnd but
/// requires the dot that disambiguates a format from a following variable.
fn lineFmtEnd(body: []const Token, start: usize) usize {
    var i = start;
    if (atTag(body, i, .dollar)) i += 1;
    if (atTag(body, i, .name)) {
        i += 1;
        // named format's `.d` rides a number token (`comma10.2` = name + `.2`)
        if (atTag(body, i, .number) and body[i].text.len > 0 and body[i].text[0] == '.') return i + 1;
    } else if (atTag(body, i, .number)) i += 1;
    if (atTag(body, i, .dot)) { // an explicit `.` (optionally `.d`) closes the format
        i += 1;
        if (atTag(body, i, .number)) i += 1;
        return i;
    }
    return start; // no trailing dot → not a format
}

/// Render one LINE template into a free-text line: literals verbatim, `@n` pads the
/// cursor to column n (1-based), a var ref through its format (else compact). Values
/// come from `pdv`, which the summary-row eval just bound to the aggregated values.
fn renderLine(arena: std.mem.Allocator, spec: LineSpec, pdv: *Pdv) diag.Error![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (spec) |it| switch (it) {
        .lit => |s| try buf.appendSlice(arena, s),
        // NOTE-lineoobcol: clamp @col to the default LINESIZE (132) so an
        // out-of-range pointer (e.g. `line @9999 'x';`) caps at the line-size
        // instead of padding thousands of spaces. ponytail: fixed 132 (SAS
        // batch default); wire io.global_linesize here if a study sets LS=.
        .at => |col| while (buf.items.len + 1 < @min(col, 132)) try buf.append(arena, ' '),
        .var_ref => |vr| {
            const v = pdv.get(vr.name) orelse Value.missing;
            try buf.appendSlice(arena, if (vr.fmt) |f| try format.apply(arena, v, f) else try cellText(arena, v));
        },
    };
    return buf.items;
}

/// parser_expr expects an eof-terminated token slice (mirrors sql.zig's withEof).
fn withReportEof(arena: std.mem.Allocator, toks: []const Token) ![]Token {
    const out = try arena.alloc(Token, toks.len + 1);
    @memcpy(out[0..toks.len], toks);
    out[toks.len] = .{ .tag = .eof };
    return out;
}

/// A REPORT body cell: the define's FORMAT= (else the column's stored format,
/// as PROC PRINT honors it) through format.apply, else the compact default.
fn rptCell(arena: std.mem.Allocator, v: Value, d: Define, col: Column) ![]const u8 {
    if (d.format orelse col.format) |spec| return format.apply(arena, v, spec);
    return cellText(arena, v);
}

/// End of a FORMAT= spec value in a DEFINE: `[$]name[w][.[d]]` — mirrors
/// main.zig's skipFormatValue so the define scan stays aligned with the next
/// attribute. Never advances past `start` on an odd token (caller guards).
fn fmtSpecEnd(toks: []const Token, start: usize) usize {
    var i = start;
    if (atTag(toks, i, .dollar)) i += 1;
    if (atTag(toks, i, .name)) {
        i += 1;
        // Named format's `.d`: the lexer emits `comma10.2` as name(`comma10`) +
        // number(`.2`) — the decimals ride the number token (BUG-reportfmtdec).
        // A bare `8.2` is a single number token, handled by the else branch.
        if (atTag(toks, i, .number) and toks[i].text.len > 0 and toks[i].text[0] == '.') i += 1;
    } else if (atTag(toks, i, .number)) i += 1;
    while (atTag(toks, i, .dot)) {
        i += 1;
        if (atTag(toks, i, .number)) i += 1;
    }
    return i;
}

fn emitReportLine(arena: std.mem.Allocator, out: *std.ArrayList(u8), texts: []const []const u8, is_num: []const bool, widths: []const usize) !void {
    var buf: std.ArrayList(u8) = .empty;
    for (texts, 0..) |txt, j| {
        if (j > 0) try buf.appendSlice(arena, "  "); // SPACING=2
        // WIDTH= clips an over-wide value at the column width (SAS clips display
        // values); with computed widths txt.len <= widths[j] always, so a no-op there.
        const cell = if (txt.len > widths[j]) txt[0..widths[j]] else txt;
        if (is_num[j]) {
            for (cell.len..widths[j]) |_| try buf.append(arena, ' ');
            try buf.appendSlice(arena, cell);
        } else {
            try buf.appendSlice(arena, cell);
            for (cell.len..widths[j]) |_| try buf.append(arena, ' ');
        }
    }
    try out.appendSlice(arena, std.mem.trimEnd(u8, buf.items, " "));
    try out.append(arena, '\n');
}

// ── PROC UNIVARIATE ─────────────────────────────────────────────────────────
//
// `proc univariate data=IN; var v1 v2 …; run;` — SAS 9.4's default report per
// analysis variable, in order: Moments (N, Mean, Std Dev, Variance, Skewness,
// Kurtosis, USS/CSS, Coeff Variation, Std Error Mean), Basic Statistical
// Measures (Location: Mean/Median/Mode; Variability: Std Dev/Variance/Range/
// IQR), Tests for Location: Mu0=0 (Student t / sign / signed-rank, statistic +
// p-value), Quantiles (100% Max / 99 / 95 / 75 Q3 / 50 Median / 25 Q1 / 5 / 1 /
// 0% Min, PCTLDEF=5), and Extreme Observations (5 lowest + 5 highest values
// with obs numbers). BUG-univreport: the middle/end sections were previously
// omitted SILENTLY — the report stopped after Quantiles.
// ponytail: no plots or BY; values match SAS, column widths are house-clean.

/// Documented SAS 9.4 PROC UNIVARIATE statement options opensas does NOT
/// implement — the catch-all's gap arm (rc 2); anything else is the user's
/// typo (rc 1). The set is CLOSED by the PROC UNIVARIATE Statement dictionary
/// (Base SAS 9.4 Procedures Guide: Statistical Procedures, printed
/// pp. 300-306, === pdf 303…309 ===); DATA=/VARDEF=/PCTLDEF=/MU0=/NOPRINT are
/// handled upstream (their aliases LOCATION=/DEF= are not → gap).
fn isUnivGapOption(kw: []const u8) bool {
    inline for (.{ "all", "alpha", "annotate", "anno", "cibasic", "cipctldf", "ciquantdf", "cipctlnormal", "ciquantnormal", "exclnpwgt", "exclnpwgts", "forceqn", "forcesn", "freq", "gout", "idout", "loccount", "modes", "mode", "location", "nextrobs", "nextrval", "nobyplot", "normal", "normaltest", "notabcontents", "novarcontents", "outtable", "def", "plots", "plot", "plotsize", "robustscale", "round", "summarycontents", "trimmed", "trim", "winsorized", "winsor" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// Documented PROC UNIVARIATE OUTPUT keywords opensas doesn't implement,
/// two doc-closed sets (Statistical Procedures): the percentile-options
/// (printed pp. 356-358, === pdf 359…361 ===) and the Table 4.14 statistical
/// keywords statFromKw doesn't decode (printed pp. 354-356,
/// === pdf 357/358/359 ===) — GEOMEAN/HARMEAN/NOBS/Q2/the robust QN…STD_SN/
/// hypothesis-testing MSIGN…PROBS families. Gap arm (rc 2); a typo stays rc 1.
fn isUnivOutGapOption(kw: []const u8) bool {
    inline for (.{ "cipctldf", "ciquantdf", "cipctlnormal", "ciquantnormal", "pctlgroup", "pctlname", "pctlndec", "pctlpre", "pctlpts", "geomean", "harmean", "nobs", "q2", "gini", "mad", "qn", "sn", "std_gini", "std_mad", "std_qn", "std_qrange", "std_sn", "msign", "normaltest", "signrank", "probm", "probn", "probs" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

pub fn runUnivariate(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var in_name: ?[]const u8 = null;
    var noprint = false;
    var vardef: VarDef = .df; // VARDEF= variance divisor (BUG-statvardef)
    var pctldef: u8 = 5; // PCTLDEF= quantile definition 1–5 (BUG-univpctldef)
    var mu0: f64 = 0; // MU0= reference for Tests for Location (F1); default 0
    var i: usize = 2; // past `proc univariate`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "vardef")) |v| {
            vardef = varDefFromName(v) orelse
                return diags.fail(error.ParseError, toks[i].line, "PROC UNIVARIATE: VARDEF={s} is not valid — expected DF, N, WDF, or WEIGHT", .{v});
            i += 3;
        } else if (i + 2 < toks.len and tkKw(toks[i], "pctldef") and toks[i + 1].tag == .eq) {
            // the value is a .number token (optAt only takes names)
            const v = toks[i + 2];
            const pd: u8 = if (v.tag == .number) std.fmt.parseInt(u8, v.text, 10) catch 0 else 0;
            if (pd < 1 or pd > 5)
                return diags.fail(error.ParseError, v.line, "PROC UNIVARIATE: PCTLDEF={s} is not valid — expected an integer 1-5", .{v.text});
            pctldef = pd;
            i += 3;
        } else if (i + 2 < toks.len and tkKw(toks[i], "mu0") and toks[i + 1].tag == .eq) {
            // MU0= reference value for all three Tests for Location (F1). It is a
            // numeric literal (optionally negative → a leading `.minus` token).
            var j = i + 2;
            const neg = toks[j].tag == .minus;
            if (neg) j += 1;
            if (j >= toks.len or toks[j].tag != .number)
                return diags.fail(error.ParseError, toks[i].line, "PROC UNIVARIATE: MU0= requires a numeric value", .{});
            mu0 = std.fmt.parseFloat(f64, toks[j].text) catch
                return diags.fail(error.ParseError, toks[j].line, "PROC UNIVARIATE: MU0={s} is not a valid number", .{toks[j].text});
            if (neg) mu0 = -mu0;
            i = j + 1;
        } else if (tkKw(toks[i], "noprint")) {
            noprint = true;
            i += 1;
        } else if (toks[i].tag == .lparen) {
            // data=d(keep=/where=…) dataset options — applied via procInput.
            // Skip as a group (MEANS' arm verbatim): the fall-through errored
            // rc 1 with a DEGENERATE empty name (the lparen token's text) on
            // valid SAS.
            i = skipParen(toks, i);
        } else {
            // ROOT-CAUSE: silently dropping an unrecognized option (NORMAL,
            // ROBUSTSCALE, TRIMMED=, WINSORIZED=, CIBASIC, ALPHA=, ROUND=, …)
            // no-op'd a requested computation. Fail loud, as VAR/ID/HISTOGRAM do.
            // SPLIT: the doc's closed option dictionary names every valid one
            // (rc 2); any other name is the user's typo (rc 1).
            if (isUnivGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC UNIVARIATE: option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC UNIVARIATE: option {s} is not supported", .{toks[i].text});
        }
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    var vars: std.ArrayList([]const u8) = .empty;
    var bys: std.ArrayList([]const u8) = .empty; // BY groups -> one OUTPUT row each (BUG-meansoutputby)
    var classes: std.ArrayList([]const u8) = .empty; // CLASS: per-level stats, not pooled (BUG-univclass)
    var class_missing = false; // `class v / missing` re-includes the missing level
    var out_name: ?[]const u8 = null; // OUTPUT OUT= target (BUG-univoutput)
    var out_stats: std.ArrayList(OutStat) = .empty;
    var weight_var: ?[]const u8 = null; // `weight w;` — weighted moments/quantiles (WEIGHT-uni-impl)
    var freq_var: ?[]const u8 = null; // `freq f;` — each obs counts trunc(f) times (F2)
    var fmt_specs: std.ArrayList(VarSpec) = .empty; // `format v spec;` — CLASS groups by formatted value (NOTE-freqtablesfmt)
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "var")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try appendVarListName(arena, toks, &i, &vars); // GAP-varcolonprefix-procs: keep `pfx:`
        } else if (tkKw(toks[i], "by")) {
            try parseProcBy(arena, diags, toks, &i, &bys);
        } else if (tkKw(toks[i], "weight")) {
            i += 1; // `weight w;` — the (single) weight variable (WEIGHT-uni-impl)
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) weight_var = toks[i].text;
            }
        } else if (tkKw(toks[i], "freq")) {
            i += 1; // `freq f;` — frequency var; expanded like PROC MEANS (F2)
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) freq_var = toks[i].text;
            }
        } else if (tkKw(toks[i], "output")) {
            // `output out=NAME <stat = var> …;` — one summary row of the requested stats
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) {
                if (toks[i].tag == .name and i + 2 < toks.len and toks[i + 1].tag == .eq) {
                    const key = toks[i].text;
                    const val = toks[i + 2].text;
                    if (eqi(key, "out")) out_name = val else if (statFromKw(key)) |sk| {
                        // Decodes for the MEANS family but is NOT a UNIVARIATE OUTPUT
                        // keyword (Table 4.14, printed p.354) — SAS rejects it here too,
                        // so accepting it would be worse than the old error: we would
                        // silently honour syntax SAS refuses (GAP-meanspctlkeywords).
                        if (univariateRejectsStatKw(key))
                            return diags.fail(error.ParseError, toks[i].line, "PROC UNIVARIATE: OUTPUT keyword {s}= is not a UNIVARIATE statistic — Table 4.14 lists PROBT (no PRT alias) and stops at P1/P5/P10/P25/P50/P75/P90/P95/P99; use PCTLPTS= for other percentiles", .{key});
                        try out_stats.append(arena, .{ .stat = sk, .name = val });
                    }
                    // Any other OUTPUT option (pctlpts=/pctlpre= and friends) is unimplemented;
                    // skipping it would silently drop the requested percentile variables (a
                    // downstream read of P33/P66 then hits a missing var). Fail loud instead
                    // (GAP-meansoutguards). SPLIT: the doc closes the keyword set, so a
                    // documented name is the recognized gap (rc 2); a typo stays rc 1.
                    else if (isUnivOutGapOption(key))
                        return failGap(diags, toks[i].line, "PROC UNIVARIATE: OUTPUT OUT= option {s}= is not yet supported — refusing to silently drop requested output (e.g. pctlpts/pctlpre percentiles)", .{key})
                    else return diags.fail(error.ParseError, toks[i].line, "PROC UNIVARIATE: OUTPUT OUT= option {s}= is not yet supported — refusing to silently drop requested output (e.g. pctlpts/pctlpre percentiles)", .{key});
                    i += 3;
                } else i += 1;
            }
        } else if (tkKw(toks[i], "format")) {
            try parseProcFormat(arena, toks, &i, &fmt_specs); // leaves i at the `;` (as MEANS)
        } else if (tkKw(toks[i], "class")) {
            // per-level analysis (BUG-univclass) — swallowing CLASS pooled the stats.
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .slash) {
                    // as MEANS (BUG-meansclassmiss): only MISSING is modeled
                    while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                        if (toks[i].tag == .name and eqi(toks[i].text, "missing")) class_missing = true;
                    }
                    break;
                }
                if (toks[i].tag == .name) try appendVarListName(arena, toks, &i, &classes); // GAP-varcolonprefix-procs: keep `pfx:`
            }
        } else if (tkKw(toks[i], "id")) {
            // ID labels extreme observations — a table we never print, so honoring
            // it silently is impossible; fail loud instead of swallowing (BUG-univclass).
            // ID is a valid SAS 9.4 PROC UNIVARIATE statement → a gap (rc 2).
            return failGap(diags, toks[i].line, "PROC UNIVARIATE: ID statement is not yet supported (extreme-observation labeling) — refusing to silently ignore it", .{});
        } else if (tkKw(toks[i], "histogram") or tkKw(toks[i], "cdfplot") or tkKw(toks[i], "qqplot") or tkKw(toks[i], "ppplot") or tkKw(toks[i], "probplot")) {
            // Plot statements produce graphics we never render; swallowing them
            // silently no-op'd a requested plot (BUG-univplotnoop). Fail loud, as
            // ID/OUTPUT-pctlpts beside them already do. Five named, valid SAS 9.4
            // statements → gap (rc 2); the catch-all below keeps the typos at rc 1.
            return failGap(diags, toks[i].line, "PROC UNIVARIATE: {s} statement is not supported yet", .{toks[i].text});
        } else if (tkKw(toks[i], "inset")) {
            // INSET is a valid SAS 9.4 PROC UNIVARIATE statement (the Syntax
            // block's own list, Statistical Procedures printed p. 298,
            // === pdf 301 ===) — a gap (rc 2); the catch-all keeps typos at rc 1.
            return failGap(diags, toks[i].line, "PROC UNIVARIATE: {s} statement is not supported", .{toks[i].text});
        } else if (tkKw(toks[i], "where")) {
            // WHERE is documented WITH UNIVARIATE ("Procedures That Support
            // the WHERE Statement", printed p. 89, === pdf 138 ===, lists it)
            // — MEANS' arm verbatim: skip to `;`, procInput applies it. Was
            // rc 1 on a universal statement.
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            // D-014 arm this loop never had: skip exactly the mid-step globals
            // the top level handles (hoisted TITLE/FOOTNOTE/OPTIONS + the
            // inert set) — `proc univariate; title "t"; var x; run;` errored
            // at exit 1 on the legal TITLE and errhalt killed every later
            // step. LIBNAME ran in the pre-pass; unhoisted ODS/FILENAME fail
            // loud below.
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else {
            // ROOT-CAUSE: an unmodeled statement was silently swallowed. Fail
            // loud naming it, as ID/HISTOGRAM/nonexistent-VAR already do.
            return diags.fail(error.ParseError, toks[i].line, "PROC UNIVARIATE: {s} statement is not supported", .{toks[i].text});
        }
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC UNIVARIATE: no input dataset");
        return;
    };
    var ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)
    // GAP-varcolonprefix-procs: expand `pfx:` entries now that the dataset is
    // known (PDV order — see expandVarPrefixes). ONE point, ahead of every
    // ds.indexOf consumer below (groupFormats' CLASS scan included).
    try expandVarListPrefixes(arena, ds, &vars, diags, toks[0].line, "PROC UNIVARIATE");
    try expandVarListPrefixes(arena, ds, &classes, diags, toks[0].line, "PROC UNIVARIATE");
    // FREQ f; — expand each obs to trunc(f) copies so N=Σf and every moment /
    // quantile / test is over the frequency-weighted sample (F2, mirrors MEANS).
    if (freq_var) |fv| {
        const fcol = ds.indexOf(fv) orelse
            return diags.fail(error.ParseError, toks[0].line, "PROC UNIVARIATE: FREQ variable {s} is not on the input data set", .{fv});
        ds = try expandFreq(arena, diags, ds, fcol);
    }

    // A format on a CLASS var groups by the FORMATTED value — the SAME
    // groupFormats rewrite MEANS/SUMMARY/FREQ run, not a parallel grouping
    // (BUG-univclassrawgroup: grouping by the RAW value split one formatted
    // level into several, printing the same label twice with per-raw n;
    // Procedures Guide MEANS CLASS stmt Tip, printed p.1497 — a collapsing
    // format REDUCES the number of levels).
    var fmt_levels: std.ArrayList(FmtLevels) = .empty; // raw-value order per format-grouped CLASS col (BUG-freqfmtorder)
    if (classes.items.len > 0) ds = try groupFormats(arena, ds, classes.items, fmt_specs.items, &fmt_levels, diags);

    // CLASS columns (BUG-univclass). Obs with a missing CLASS value are excluded
    // unless / MISSING (as MEANS, BUG-meansclassmiss); `cds` is the analysis view.
    var ccols: std.ArrayList(usize) = .empty;
    for (classes.items) |cn| if (ds.indexOf(cn)) |idx| try ccols.append(arena, idx);
    const cds = if (ccols.items.len > 0 and !class_missing) try dropMissingClass(arena, ds, ccols.items) else ds;

    // the VAR list, else every numeric column (as MEANS does) — but never a CLASS
    // variable: SAS excludes CLASS vars from the default analysis list.
    var acols: std.ArrayList(usize) = .empty;
    if (vars.items.len > 0) {
        // An unknown VAR name was silently dropped (BUG-univvarnosuch); fail loud
        // naming it, as PROC FREQ does for a missing TABLES variable.
        for (vars.items) |vn| {
            const ix = ds.indexOf(vn) orelse return diags.fail(error.ParseError, toks[0].line, "PROC UNIVARIATE: VAR variable {s} is not on the input data set", .{vn});
            try acols.append(arena, ix);
        }
    } else {
        var_loop: for (ds.columns.items, 0..) |c, ix| {
            if (c.type != .num) continue;
            for (ccols.items) |ci| if (ci == ix) continue :var_loop;
            try acols.append(arena, ix);
        }
    }
    if (acols.items.len == 0) return unsupported("PROC UNIVARIATE: no numeric analysis variable");

    // WEIGHT column (WEIGHT-uni-impl): weighted moments/quantiles when set. A
    // named-but-absent weight var errors (BUG-weightvarcheck).
    const wcol: ?usize = try resolveWeightCol(ds, weight_var, diags, toks[0].line);

    // SAS computes weighted percentiles with definition 5 only — say so rather
    // than silently honoring PCTLDEF= on the weighted path (BUG-univpctldef).
    if (wcol != null and pctldef != 5)
        diags.warn(toks[0].line, "PROC UNIVARIATE: PCTLDEF= is ignored with a WEIGHT statement — weighted percentiles use Definition 5", .{}) catch {};
    if (vardef != .df)
        diags.warn(toks[0].line, "PROC UNIVARIATE: Skewness/Kurtosis are implemented for VARDEF=DF only — printed as missing under VARDEF={s}", .{@tagName(vardef)}) catch {};

    // BY: decode scanByList's wire encoding ONCE — clean names + per-key
    // directions + NOTSORTED (GAP-procbydescending) — shared by OUTPUT OUT=
    // (one row per group, BUG-meansoutputby) and the listing (one block set
    // per group, BUG-univignoresby), so the two surfaces cannot disagree.
    const pb = try decodeProcBy(arena, bys.items);
    var obcols: std.ArrayList(usize) = .empty;
    var obdesc: std.ArrayList(bool) = .empty; // BY direction per obcols entry (BUG-meansoutbydescending)
    for (pb.names, 0..) |bn, k| if (ds.indexOf(bn)) |idx| {
        try obcols.append(arena, idx);
        try obdesc.append(arena, pb.desc[k]);
    };
    // BY demands sorted data: a backward step between contiguous groups ERRORs
    // like SAS — the same guard MEANS/TRANSPOSE run (BUG-meansbyunsorted),
    // joined here per NOTE-procsortguards. Without it an unsorted BY silently
    // POOLED out-of-order groups (listing) and emitted duplicate OUT= rows.
    // DESCENDING flips the check per key; NOTSORTED drops it.
    if (obcols.items.len > 0 and !pb.notsorted) {
        const rows = ds.rows.items;
        var s: usize = 0;
        while (s < rows.len) {
            var e = s + 1;
            while (e < rows.len and byEqual(rows[s], rows[e], obcols.items)) e += 1;
            if (e < rows.len) if (byOrderViolation(rows[e], rows[s], obcols.items, pb.desc)) |k|
                return diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (pb.desc[k]) "descending" else "ascending" });
            s = e;
        }
    }

    // OUTPUT OUT= — the requested stats of the first analysis variable, one row
    // total or one per BY group (BUG-univoutput / BUG-meansoutputby); with a CLASS,
    // one row per level with the CLASS var retained (BUG-univclass — SAS UNIVARIATE
    // emits only the full cross, no _TYPE_=0 overall row, so nway=has_class).
    if (out_name) |on| {
        // The shared MEANS output builder computes quantiles UNWEIGHTED (SAS MEANS
        // ignores weights for percentiles); UNIVARIATE weights them, so a weighted
        // OUTPUT percentile via this path would be silently wrong — fail loud instead.
        if (wcol != null) for (out_stats.items) |os| if (isQuantileStat(os.stat))
            return diags.fail(error.ParseError, toks[0].line, "PROC UNIVARIATE: weighted OUTPUT percentile/quantile statistics are not yet supported — refusing to emit unweighted percentiles silently", .{});
        // UNIVARIATE is single-analysis-var: every requested stat is of acols[0].
        for (out_stats.items) |*os| os.acol = acols.items[0];
        try buildMeansOutput(arena, diags, lib, on, cds, ccols.items, obcols.items, obdesc.items, wcol, &.{}, out_stats.items, ccols.items.len > 0, false, vardef, .internal, false, 0.05, fmt_levels.items); // UNIVARIATE: no _TYPE_/_FREQ_ (BUG-univclass); fmt_levels stores a collapsed group's LOWEST raw + attaches the format (NOTE-freqfmtoutraw)
        if (lib.find(on)) |od| try applyOutOptions(arena, od, toks, diags, "out"); // out=X(keep=/drop=) — BUG-procoutkeep
    }

    if (noprint) return; // NOPRINT suppresses the Moments/Quantiles listing
    try out.appendSlice(arena, (" " ** 33) ++ "The UNIVARIATE Procedure\n");
    // One block set PER BY GROUP (BUG-univignoresby: BY was parsed and then
    // ignored — the listing printed ONE pooled Moments block over ALL obs, the
    // number formatted exactly like the per-group answer asked for). bySlices
    // yields one null-rep slice without BY, so the pooled path is byte-identical.
    for (try bySlices(arena, cds.rows.items, obcols.items)) |bs| {
        if (bs.rep) |r| try appendByLine(arena, out, ds, r, obcols.items);
        // Shallow per-group view (columns shared, rows = the slice's) — the same
        // idiom the CLASS arm uses per level below.
        const bd = try arena.create(Dataset);
        bd.* = Dataset.init(arena, ds.name);
        for (ds.columns.items) |c| try bd.columns.append(arena, c);
        for (bs.rows) |r| try bd.rows.append(arena, r);
        if (ccols.items.len == 0) {
            for (acols.items) |ix| try emitUnivariate(arena, out, bd, ix, wcol, vardef, pctldef, mu0);
        } else {
            // CLASS: one Moments/Quantiles block per level (BUG-univclass), headed by
            // `classvar=formatted-level` as SAS does — levels collected WITHIN the
            // BY group.
            const groups = try collectGroups(arena, bd, ccols.items);
            reorderGroupsFmt(groups, ccols.items, fmt_levels.items); // collapsed bands in raw-value order, as the MEANS listing (BUG-freqfmtorder)
            for (groups) |g| {
                var hdr: std.ArrayList(u8) = .empty;
                for (ccols.items, 0..) |ci, k| {
                    if (k > 0) try hdr.appendSlice(arena, " ");
                    const col = bd.columns.items[ci];
                    const lv = if (col.format) |spec| try format.apply(arena, g.rep[ci], spec) else try classCell(arena, g.rep[ci]);
                    try hdr.appendSlice(arena, try std.fmt.allocPrint(arena, "{s}={s}", .{ col.name, lv }));
                }
                try out.append(arena, '\n');
                try out.appendSlice(arena, hdr.items);
                // shallow per-level view (columns shared, rows = the group's)
                const gd = try arena.create(Dataset);
                gd.* = Dataset.init(arena, bd.name);
                for (bd.columns.items) |c| try gd.columns.append(arena, c);
                for (g.rows) |r| try gd.rows.append(arena, r);
                for (acols.items) |ix| try emitUnivariate(arena, out, gd, ix, wcol, vardef, pctldef, mu0);
            }
        }
    }
}

/// A percentile-family statistic whose value the shared MEANS output builder
/// derives from an UNWEIGHTED sorted buffer (WEIGHT-uni-impl guard).
fn isQuantileStat(k: StatKind) bool {
    return switch (k) {
        .median, .q1, .q3, .qrange, .p1, .p5, .p10, .p90, .p95, .p99, .mode => true,
        else => false,
    };
}

/// One variable's Moments + Quantiles block. `wcol` names a WEIGHT column
/// (WEIGHT-uni-impl); null → every obs weighs 1 (identical to the unweighted case).
fn emitUnivariate(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, col: usize, wcol: ?usize, vardef: VarDef, pctldef: u8, mu0: f64) !void {
    // computeStatsV already carries the weighted N / Sum Weights (Σwᵢ) / weighted
    // Mean (Σwᵢxᵢ/Σwᵢ) / weighted Std (CSS over the VARDEF divisor, BUG-statvardef)
    // / weighted CSS (Σwᵢ(xᵢ−x̄w)²) / weighted USS (Σwᵢxᵢ²) / weighted Sum (Σwᵢxᵢ).
    const s = computeStatsV(ds.rows.items, col, wcol, vardef);
    const nf: f64 = @floatFromInt(s.n);
    const nan = std.math.nan(f64);

    // Weighted 3rd/4th central moments for SAS 9.4 skewness/kurtosis. SAS Base
    // Procedures Guide, "Descriptive Statistics" (VARDEF=DF, n = # nonmissing obs):
    //   skewness = n/((n−1)(n−2)) · Σ wᵢ^{3/2}·((xᵢ−x̄w)/s)³            (n>2)
    //   kurtosis = n(n+1)/((n−1)(n−2)(n−3)) · Σ wᵢ²·((xᵢ−x̄w)/s)⁴
    //              − 3(n−1)²/((n−2)(n−3))                               (n>3)
    // where x̄w is the weighted mean and s the weighted std. With every wᵢ=1 the
    // weight factors are 1 and these collapse to the unweighted formulas.
    var m3: f64 = 0; // Σ wᵢ^{3/2}(xᵢ−x̄w)³
    var m4: f64 = 0; // Σ wᵢ²(xᵢ−x̄w)⁴
    // Arena-sized to the row count — a fixed [4096] cap silently computed the
    // quantiles over only the first 4096 obs while moments used all of them, so
    // any group >4096 got wrong percentiles/median/Q1/Q3 (BUG-univarpctl4k).
    const xw = try arena.alloc(XW, ds.rows.items.len);
    var k: usize = 0;
    for (ds.rows.items, 0..) |r, ri| {
        const x = toNum(r[col]);
        if (std.math.isNan(x)) continue;
        const w = weightAt(r, wcol) orelse continue;
        const d = x - s.mean;
        m3 += std.math.pow(f64, w, 1.5) * d * d * d;
        m4 += (w * w) * d * d * d * d;
        xw[k] = .{ .x = x, .w = w, .obs = ri + 1 }; // 1-based obs number (Extreme Obs)
        k += 1;
    }
    const variance = s.std * s.std;
    const skew = if (s.n >= 3 and s.std > 0)
        (nf / ((nf - 1) * (nf - 2))) * (m3 / (s.std * s.std * s.std))
    else
        nan;
    const kurt = if (s.n >= 4 and s.std > 0)
        (nf * (nf + 1) / ((nf - 1) * (nf - 2) * (nf - 3))) * (m4 / (variance * variance)) -
            3 * (nf - 1) * (nf - 1) / ((nf - 2) * (nf - 3))
    else
        nan;
    const cv = if (s.mean != 0) 100 * s.std / s.mean else nan;
    // The skew/kurt formulas above are the VARDEF=DF forms; SAS uses different
    // coefficients per divisor, so under another VARDEF our values would not
    // match SAS — emit missing (warned once in runUnivariate) instead of
    // silent-wrong stats (BUG-statvardef).
    const skew_out = if (vardef == .df) skew else nan;
    const kurt_out = if (vardef == .df) kurt else nan;
    // SAS weighted std error of the mean = √(s²/Σw): divisor is the sum of weights,
    // matching PROC MEANS (BUG-meanswstderr). Unweighted Σw==n → s/√n.
    const sem = if (s.sumw > 0) s.std / @sqrt(s.sumw) else nan;

    // Weighted quantiles (SAS UNIVARIATE computes them; MEANS does not). PCTLDEF=5
    // is weight-aware; definitions 1–4 use the sorted values only (SAS restricts
    // them to unweighted data — a WEIGHT statement forces 5) (BUG-univpctldef).
    const edef: u8 = if (wcol != null) 5 else pctldef;
    const pairs = xw[0..k];
    std.mem.sort(XW, pairs, {}, struct {
        fn lt(_: void, a: XW, b: XW) bool {
            return a.x < b.x;
        }
    }.lt);
    const p1 = univPercentile(pairs, 1, edef);
    const p5 = univPercentile(pairs, 5, edef);
    const p95 = univPercentile(pairs, 95, edef);
    const p99 = univPercentile(pairs, 99, edef);
    const p10 = univPercentile(pairs, 10, edef);
    const p90 = univPercentile(pairs, 90, edef);
    const q1 = univPercentile(pairs, 25, edef);
    const med = univPercentile(pairs, 50, edef);
    const q3 = univPercentile(pairs, 75, edef);

    try out.append(arena, '\n');
    // A LABELLED analysis variable carries its label in parentheses after the name:
    // "Variable: Score (Exam Score)" (Output 4.2.1, printed p.473) and "Variable:
    // LoanToValueRatio (Loan to Value Ratio)" (Getting Started, printed p.291) — the
    // rule holds across 20+ printed Variable: lines in the chapter, and an UNLABELLED
    // variable prints the bare name ("Variable: Systolic", Output 4.1.1 p.471), which
    // is the control (NOTE-univvarlabel). PROC PRINT already resolves the same label,
    // so the value was on the column all along; only this heading ignored it.
    // ponytail: the two spaces after the colon are DELIBERATELY unchanged. The text
    // extraction collapses runs of spaces (the Moments rows come out single-spaced
    // too), so it cannot settle 1-vs-2 and moving it would churn ~20 goldens to chase
    // a guess. A BLANK label counts as absent: `label y = '';` stores a single SPACE
    // (not null, not ""), so a plain null/len check still printed "Variable:  y ( )".
    // trimEnd, not trim: a SAS label is stored blank-padded, so TRAILING blanks are
    // padding and insignificant, while a LEADING blank the user typed is theirs to
    // keep. An all-blank label trims away entirely and falls through to the bare name.
    const vname = ds.columns.items[col].name;
    const vlabel = std.mem.trimEnd(u8, ds.columns.items[col].label orelse "", " ");
    try out.appendSlice(arena, if (vlabel.len > 0)
        try std.fmt.allocPrint(arena, "Variable:  {s} ({s})\n\n", .{ vname, vlabel })
    else
        try std.fmt.allocPrint(arena, "Variable:  {s}\n\n", .{vname}));
    try out.appendSlice(arena, (" " ** 27) ++ "Moments\n\n");
    try momentLine(arena, out, "N", nf, "Sum Weights", s.sumw);
    try momentLine(arena, out, "Mean", s.mean, "Sum Observations", s.sum);
    try momentLine(arena, out, "Std Deviation", s.std, "Variance", variance);
    try momentLine(arena, out, "Skewness", skew_out, "Kurtosis", kurt_out);
    try momentLine(arena, out, "Uncorrected SS", s.uss, "Corrected SS", s.css);
    try momentLine(arena, out, "Coeff Variation", cv, "Std Error Mean", sem);

    // ── Basic Statistical Measures (BUG-univreport) ──────────────────────────
    // Location: Mean/Median/Mode; Variability: Std Dev/Variance/Range/IQR. Mode
    // reuses the MEANS modeOf over the sorted values (most frequent, ties →
    // smallest, all-unique → missing).
    const vals = try arena.alloc(f64, k);
    for (pairs, 0..) |q, j| vals[j] = q.x;
    try out.appendSlice(arena, "\n" ++ (" " ** 20) ++ "Basic Statistical Measures\n\n");
    try out.appendSlice(arena, (" " ** 6) ++ "Location" ++ (" " ** 20) ++ "Variability\n\n");
    try momentLine(arena, out, "Mean", s.mean, "Std Deviation", s.std);
    try momentLine(arena, out, "Median", med, "Variance", variance);
    const mi = modeInfo(vals);
    try momentLine(arena, out, "Mode", if (mi.count < 2) nan else mi.mode, "Range", s.max - s.min);
    try out.appendSlice(arena, " " ** 34); // no fourth Location stat — blank pair
    try uPair(arena, out, "Interquartile Range", q3 - q1);
    try out.append(arena, '\n');
    // A TIE for the most frequent value: SAS displays the smallest mode and says so
    // immediately below this table. Exact wording and placement from three printed
    // outputs in Base SAS 9.4 Procedures Guide: Statistical Procedures — Output
    // 4.1.1 p.471 ("smallest of 2 modes with a count of 4"), Output 4.2.2 p.473
    // ("of 3 modes with a count of 4") and Output 4.13.1 p.491 ("of 2 modes with a
    // count of 2"); the tie rule itself is "Calculating the Mode", p.413. The note
    // is NOT gated on the MODES option — p.473's is the *default* output.
    // count < 2 must stay suppressed: with every value unique, every run is length
    // 1 and nmodes is the number of distinct values, but p.413 says "When no
    // repetitions occur in the data ... the procedure does not report the mode".
    if (mi.count >= 2 and mi.nmodes >= 2)
        try out.appendSlice(arena, try std.fmt.allocPrint(
            arena,
            "\nNote: The mode displayed is the smallest of {d} modes with a count of {d}.\n",
            .{ mi.nmodes, mi.count },
        ));

    // ── Tests for Location: Mu0=0 (BUG-univreport) ───────────────────────────
    // Student's t = mean/(std/√Σw), df = n−1 — the MEANS T/PROBT convention.
    // Sign & Wilcoxon signed-rank are count/rank tests SAS does not compute
    // under WEIGHT, so the weighted path prints the t row only.
    var tstat = nan;
    var tp = nan;
    if (s.n >= 2 and s.std > 0 and s.sumw > 0) {
        tstat = (s.mean - mu0) / (s.std / @sqrt(s.sumw)); // F1: test against MU0=
        tp = 2.0 * (1.0 - studentTcdf(@abs(tstat), nf - 1));
    }
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "\n" ++ (" " ** 20) ++ "Tests for Location: Mu0={d}\n\n", .{mu0}));
    try out.appendSlice(arena, "Test           -Statistic-    -----p Value------\n\n");
    try testLine(arena, out, "Student's t", "t", tstat, "Pr > |t|", tp);
    if (wcol == null) {
        // Observations equal to Mu0 are dropped (SAS); the sign of (x−Mu0) feeds
        // the sign test, average ranks of |x−Mu0| the signed-rank test (F1).
        const NZ = struct { ax: f64, pos: bool };
        var nz: std.ArrayList(NZ) = .empty;
        for (ds.rows.items) |r| {
            const x = toNum(r[col]);
            if (std.math.isNan(x)) continue;
            const dv = x - mu0;
            if (dv == 0) continue;
            try nz.append(arena, .{ .ax = @abs(dv), .pos = dv > 0 });
        }
        const nstar = nz.items.len;
        var nplus: usize = 0;
        for (nz.items) |e| {
            if (e.pos) nplus += 1;
        }
        // M = (n⁺−n⁻)/2 = n⁺−n*/2; p = 2·P(Bin(n*,½) ≥ max(n⁺,n⁻))
        //   = 2·I_½(max, n*−max+1) (binomial tail via incomplete beta), capped at 1.
        const mstat = @as(f64, @floatFromInt(nplus)) - @as(f64, @floatFromInt(nstar)) / 2.0;
        var mp = nan;
        if (nstar > 0) {
            const hc = @max(nplus, nstar - nplus);
            mp = @min(1.0, 2.0 * betai(@floatFromInt(hc), @floatFromInt(nstar - hc + 1), 0.5));
        }
        // Average ranks of |x| — a tie run covering sorted positions [lo..hi]
        // (0-based) has rank (lo+hi)/2+1, so 2·rank = lo+hi+2 is always integral
        // (the exact signed-rank DP below stays in integers).
        std.mem.sort(NZ, nz.items, {}, struct {
            fn lt(_: void, a: NZ, b: NZ) bool {
                return a.ax < b.ax;
            }
        }.lt);
        const dranks = try arena.alloc(i64, nstar);
        var tiecorr: f64 = 0; // Σ t(t−1)(2t+5) over tie runs (asymptotic variance)
        {
            var lo: usize = 0;
            while (lo < nstar) {
                var hi = lo;
                while (hi + 1 < nstar and nz.items[hi + 1].ax == nz.items[lo].ax) hi += 1;
                const d2: i64 = @intCast(lo + hi + 2);
                const tsz: f64 = @floatFromInt(hi - lo + 1);
                tiecorr += tsz * (tsz - 1) * (2 * tsz + 5);
                for (lo..hi + 1) |j| dranks[j] = d2;
                lo = hi + 1;
            }
        }
        // SAS S = Σr⁺ − n(n+1)/4 = (2·Σ(2r⁺) − Σ(2r))/4 — a quarter-integer.
        var dsum: i64 = 0;
        var dpos: i64 = 0;
        for (dranks, 0..) |d2, j| {
            dsum += d2;
            if (nz.items[j].pos) dpos += d2;
        }
        const sstat = @as(f64, @floatFromInt(2 * dpos - dsum)) / 4.0;
        const sp = if (nstar == 0) nan else try signedRankP(arena, dranks, 2 * dpos - dsum, tiecorr);
        try testLine(arena, out, "Sign", "M", mstat, "Pr >= |M|", mp);
        try testLine(arena, out, "Signed Rank", "S", sstat, "Pr >= |S|", sp);
    }

    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "\n" ++ (" " ** 20) ++ "Quantiles (Definition {d})\n\n", .{edef}));
    try quantLine(arena, out, "100% Max", s.max);
    try quantLine(arena, out, "99%", p99);
    try quantLine(arena, out, "95%", p95);
    try quantLine(arena, out, "90%", p90);
    try quantLine(arena, out, "75% Q3", q3);
    try quantLine(arena, out, "50% Median", med);
    try quantLine(arena, out, "25% Q1", q1);
    try quantLine(arena, out, "10%", p10);
    try quantLine(arena, out, "5%", p5);
    try quantLine(arena, out, "1%", p1);
    try quantLine(arena, out, "0% Min", s.min);

    // ── Extreme Observations (BUG-univreport) ────────────────────────────────
    // The 5 lowest/highest nonmissing values with 1-based observation numbers.
    // ponytail: lowest ties keep data order (stable sort); highest ties list
    // latest-obs-first (the sorted buffer walked back) — SAS's tie order here is
    // undocumented.
    const m = @min(5, k);
    try out.appendSlice(arena, "\n" ++ (" " ** 23) ++ "Extreme Observations\n\n");
    try out.appendSlice(arena, (" " ** 11) ++ "----Lowest----" ++ (" " ** 8) ++ "---Highest---\n\n");
    try out.appendSlice(arena, (" " ** 11) ++ "Value      Obs" ++ (" " ** 8) ++ "Value      Obs\n\n");
    for (0..m) |j| {
        const h = pairs[k - 1 - j];
        try out.appendSlice(arena, " " ** 11);
        try out.appendSlice(arena, try rjust(arena, try uNum(arena, pairs[j].x), 9));
        try out.appendSlice(arena, try rjust(arena, try std.fmt.allocPrint(arena, "{d}", .{pairs[j].obs}), 5));
        try out.appendSlice(arena, " " ** 8);
        try out.appendSlice(arena, try rjust(arena, try uNum(arena, h.x), 9));
        try out.appendSlice(arena, try rjust(arena, try std.fmt.allocPrint(arena, "{d}", .{h.obs}), 5));
        try out.append(arena, '\n');
    }
}

/// A value paired with its analysis weight, for weighted quantiles (WEIGHT-uni-impl)
/// and its 1-based observation number, for Extreme Observations (BUG-univreport).
const XW = struct { x: f64, w: f64, obs: usize = 0 };

/// A Tests-for-Location row in the SAS 9.4 column layout: label(15) symbol,
/// statistic right-justified ending col 26, 4 spaces, p-label, p-value
/// right-justified ending col 46 (≥1 space after the 9-char "Pr >= |M|").
fn testLine(arena: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, sym: []const u8, stat: f64, plabel: []const u8, p: f64) !void {
    try out.appendSlice(arena, label);
    for (0..(15 -| label.len)) |_| try out.append(arena, ' ');
    try out.appendSlice(arena, sym);
    try out.append(arena, ' ');
    try out.appendSlice(arena, try rjust(arena, try uNum(arena, stat), 9));
    try out.appendSlice(arena, "    ");
    try out.appendSlice(arena, plabel);
    const pv = try pNum(arena, p);
    for (0..(46 -| (15 + 1 + 1 + 9 + 4 + plabel.len + pv.len))) |_| try out.append(arena, ' ');
    try out.appendSlice(arena, pv);
    try out.append(arena, '\n');
}

/// A SAS listing p-value: missing → ".", below 0.0001 → "<.0001", else 4 decimals.
fn pNum(arena: std.mem.Allocator, p: f64) ![]const u8 {
    if (!std.math.isFinite(p)) return ".";
    if (p < 0.0001) return "<.0001";
    return std.fmt.allocPrint(arena, "{d:.4}", .{p});
}

/// Wilcoxon signed-rank two-sided p-value Pr(|S| ≥ |Sobs|) (BUG-univreport).
/// `d` holds the doubled average ranks (2·rᵢ, always integral) of the nonzero
/// observations, `tobs` = 4·Sobs = 2·Σd⁺ − Σd, `tiecorr` = Σ t(t−1)(2t+5) over
/// tie runs. n ≤ 20 → exact enumeration of the 2ⁿ sign assignments (integer DP
/// on subset sums); n > 20 → normal approximation with the tie-corrected
/// variance and a 0.5 continuity correction (SAS 9.4, "Tests for Location").
fn signedRankP(arena: std.mem.Allocator, d: []const i64, tobs: i64, tiecorr: f64) !f64 {
    if (d.len <= 20) {
        var total: i64 = 0;
        for (d) |v| total += v;
        const width: usize = @intCast(2 * total + 1);
        var dp = try arena.alloc(u64, width);
        @memset(dp, 0);
        dp[@intCast(total)] = 1;
        for (d) |v| {
            const uv: usize = @intCast(v);
            const nd = try arena.alloc(u64, width);
            @memset(nd, 0);
            for (dp, 0..) |c, j| {
                if (c == 0) continue;
                nd[j - uv] += c; // reachable sums stay within ±Σd, so j±uv is in range
                nd[j + uv] += c;
            }
            dp = nd;
        }
        const thr = @abs(tobs);
        var cnt: u64 = 0;
        for (dp, 0..) |c, j| {
            if (@abs(@as(i64, @intCast(j)) - total) >= thr) cnt += c;
        }
        const combos = @as(f64, @floatFromInt(@as(u64, 1) << @intCast(d.len)));
        return @as(f64, @floatFromInt(cnt)) / combos;
    }
    const nf: f64 = @floatFromInt(d.len);
    const s = @as(f64, @floatFromInt(tobs)) / 4.0;
    const var_s = (nf * (nf + 1) * (2 * nf + 1) - tiecorr / 2.0) / 24.0;
    const z = (@abs(s) - 0.5) / @sqrt(var_s);
    return 2.0 * (1.0 - normCdf(z));
}

/// Standard normal CDF — Abramowitz–Stegun 7.1.26 (|ε| ≤ 1.5e-7). Only the
/// signed-rank asymptotic p-value uses it, printed to 4 decimals — far inside
/// the error bound.
fn normCdf(z: f64) f64 {
    if (z < 0) return 1 - normCdf(-z);
    const u = 1.0 / (1.0 + 0.2316419 * z);
    const poly = u * (0.319381530 + u * (-0.356563782 + u * (1.781477937 + u * (-1.821255978 + u * 1.330274429))));
    return 1.0 - @exp(-z * z / 2.0) / @sqrt(2.0 * std.math.pi) * poly;
}

test "UNIVARIATE tests-for-location: exact signed-rank DP + p-value formatting (BUG-univreport)" {
    var arena_inst = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_inst.deinit();
    const arena = arena_inst.allocator();
    // Hand case (pinned in univ_report_full.sas): |x| = 2,3,3,4,5,7,8,9,10 →
    // doubled ranks d = 2,5,5,8,10,12,14,16,18; the sole negative is |−4| (d=8),
    // so S = (2·82−90)/4 = 18.5 and 4S = 74. Exact: |T| ≥ 74 needs one sign side
    // summing ≤ 8 — subsets {},2,5,5,8,2+5,2+5 = 7 per tail → p = 14/512.
    const d = [_]i64{ 2, 5, 5, 8, 10, 12, 14, 16, 18 };
    try std.testing.expectApproxEqAbs(14.0 / 512.0, try signedRankP(arena, &d, 74, 18), 1e-12);
    // Sign-test tail identity: 2·P(Bin(9,½) ≥ 8) = 2·I_½(8,2) = 20/512.
    try std.testing.expectApproxEqAbs(20.0 / 512.0, 2.0 * betai(8, 2, 0.5), 1e-12);
    try std.testing.expectApproxEqAbs(0.975, normCdf(1.959964), 1e-5);
    try std.testing.expectEqualStrings("0.0391", try pNum(arena, 20.0 / 512.0));
    try std.testing.expectEqualStrings("<.0001", try pNum(arena, 0.00005));
    try std.testing.expectEqualStrings(".", try pNum(arena, std.math.nan(f64)));
}

/// SAS weighted percentile, PCTLDEF=5 (empirical distribution with averaging).
/// `pairs` must be sorted ascending by `.x`. With W = Σwᵢ and threshold t = (p/100)·W,
/// take the smallest i whose cumulative weight ≥ t; if it equals t exactly, average
/// xᵢ and xᵢ₊₁, else take xᵢ. Every wᵢ=1 reduces to the unweighted definition 5
/// (cumₙ = n, t = p·n/100) so this matches `percentile()` on unweighted data.
fn weightedPercentile(pairs: []const XW, p: f64) f64 {
    if (pairs.len == 0) return std.math.nan(f64);
    if (pairs.len == 1) return pairs[0].x;
    var total: f64 = 0;
    for (pairs) |q| total += q.w;
    const thr = p / 100.0 * total;
    var cum: f64 = 0;
    for (pairs, 0..) |q, idx| {
        cum += q.w;
        if (cum >= thr) {
            if (cum == thr and idx + 1 < pairs.len) return (pairs[idx].x + pairs[idx + 1].x) / 2.0;
            return pairs[idx].x;
        }
    }
    return pairs[pairs.len - 1].x;
}

/// UNIVARIATE quantile dispatch (BUG-univpctldef): definition 5 stays on the
/// weight-aware path; definitions 1–4 use the sorted values only.
fn univPercentile(pairs: []const XW, p: f64, pctldef: u8) f64 {
    if (pctldef == 5) return weightedPercentile(pairs, p);
    return pctldefPercentile(pairs, p, pctldef);
}

/// SAS PCTLDEF=1–4 quantiles over the sorted values, `pairs` ascending by `.x`
/// (weights ignored — SAS restricts these definitions to unweighted data). With
/// t = p/100, n = # values, and 1-based x₁…xₙ (indexes clamp at the extremes,
/// x₀≡x₁ and x_{n+1}≡xₙ, so 0%/100% stay Min/Max):
///   1 — linear interpolation at position n·t:        Q = (1−g)xⱼ + g·xⱼ₊₁
///   2 — the observation closest to n·t (ties to the EVEN index)
///   3 — empirical distribution:                      Q = xⱼ if n·t integer else xⱼ₊₁
///   4 — linear interpolation at position (n+1)·t
/// (SAS 9.4 UNIVARIATE, "Calculating Percentiles".)
fn pctldefPercentile(pairs: []const XW, p: f64, def: u8) f64 {
    const n = pairs.len;
    if (n == 0) return std.math.nan(f64);
    if (n == 1) return pairs[0].x;
    const at = struct {
        fn f(ps: []const XW, j1: i64) f64 { // 1-based index, clamped to the extremes
            if (j1 < 1) return ps[0].x;
            if (j1 > @as(i64, @intCast(ps.len))) return ps[ps.len - 1].x;
            return ps[@intCast(j1 - 1)].x;
        }
    }.f;
    const nf: f64 = @floatFromInt(n);
    const tf = p / 100.0;
    return switch (def) {
        1, 4 => blk: { // weighted average at n·t (def 1) or (n+1)·t (def 4)
            const h = (if (def == 1) nf else nf + 1) * tf;
            const fl = @floor(h);
            const j: i64 = @intFromFloat(fl);
            const g = h - fl;
            break :blk (1 - g) * at(pairs, j) + g * at(pairs, j + 1);
        },
        2 => blk: { // nearest integer to n·t; an exact .5 tie rounds to the EVEN index
            const h = nf * tf;
            const fl = @floor(h);
            const frac = h - fl;
            var j: i64 = @intFromFloat(fl);
            if (frac > 0.5 or (frac == 0.5 and @mod(j, 2) != 0)) j += 1;
            break :blk at(pairs, j);
        },
        3 => blk: { // empirical distribution function
            const h = nf * tf;
            const fl = @floor(h);
            const j: i64 = @intFromFloat(fl);
            break :blk at(pairs, if (h == fl) j else j + 1);
        },
        else => unreachable, // only 1–4 routed here; 5 stays in weightedPercentile
    };
}

/// A two-pair Moments row: `label1(20) value1(12)  label2(20) value2(12)`.
fn momentLine(arena: std.mem.Allocator, out: *std.ArrayList(u8), l1: []const u8, v1: f64, l2: []const u8, v2: f64) !void {
    try uPair(arena, out, l1, v1);
    try out.appendSlice(arena, "  ");
    try uPair(arena, out, l2, v2);
    try out.append(arena, '\n');
}

fn uPair(arena: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, v: f64) !void {
    try out.appendSlice(arena, label);
    // saturating pad: a value wider than its column just widens the field instead
    // of underflowing `len..width` into an integer-overflow panic (BUG-univarpad).
    for (0..(20 -| label.len)) |_| try out.append(arena, ' ');
    const txt = try uNum(arena, v);
    for (0..(12 -| txt.len)) |_| try out.append(arena, ' ');
    try out.appendSlice(arena, txt);
}

/// A quantile row: `label(12) value(12)`, indented 14.
fn quantLine(arena: std.mem.Allocator, out: *std.ArrayList(u8), label: []const u8, v: f64) !void {
    try out.appendSlice(arena, " " ** 14);
    try out.appendSlice(arena, label);
    for (0..(12 -| label.len)) |_| try out.append(arena, ' ');
    const txt = try uNum(arena, v);
    for (0..(12 -| txt.len)) |_| try out.append(arena, ' ');
    try out.appendSlice(arena, txt);
    try out.append(arena, '\n');
}

/// A moment/quantile value: missing → ".", an integer prints plainly, else round
/// to 8 significant figures (trailing zeros trimmed) — enough to match SAS's
/// listing precision without its exact format-driven width.
fn uNum(arena: std.mem.Allocator, x: f64) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    if (x == @trunc(x) and @abs(x) < 1e15)
        return std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))});
    const s = try std.fmt.allocPrint(arena, "{d:.8}", .{x});
    const trimmed = std.mem.trimEnd(u8, s, "0");
    return std.mem.trimEnd(u8, trimmed, ".");
}

// ── PROC RANK ────────────────────────────────────────────────────────────────
//
// `proc rank data=IN out=OUT [descending] [groups=k] [ties=mean|low|high|dense];
//    [by b…;] var v1 v2 …; [ranks r1 r2 …;] run;`
// Ranks each VAR variable across observations (within BY groups), writing the
// rank to the matching RANKS variable — or replacing the VAR value in-place when
// no RANKS statement is given. GROUPS=k buckets into quantile groups 0..k-1
// (deciles/quartiles). ponytail: no PARTIAL, no per-var DESCENDING — the common
// quantile-grouping shape. The unimplemented score options (FRACTION/PERCENT/
// NPLUS1/NORMAL=/SAVAGE) and an unrecognized TIES= ParseError instead of silently
// emitting ordinal ranks (GAP-rankguards); add scores when a study needs them.

const TiesKind = enum { mean, low, high, dense };

/// null = an unrecognized TIES= value — the caller must fail LOUD rather than
/// silently defaulting to MEAN and shipping the wrong tie handling (GAP-rankguards).
fn tiesFromKw(text: []const u8) ?TiesKind {
    if (eqi(text, "mean")) return .mean;
    if (eqi(text, "low")) return .low;
    if (eqi(text, "high")) return .high;
    if (eqi(text, "dense")) return .dense;
    return null;
}

/// PROC RANK score-transform options we do NOT implement. They must ParseError,
/// never fall through and emit plain ordinal ranks where a fraction/percent/
/// normal score was requested (silent wrong numbers — GAP-rankguards).
/// BLOM/TUKEY/VW are the three documented NORMAL= score names (Base SAS 9.4
/// Procedures Guide, 7th ed., printed p. 2048, === pdf 2097 ===): the SAS form
/// is NORMAL=BLOM (the `normal` entry already gaps that), but a BARE score name
/// can only be a score request — never a typo of anything else — so it takes
/// the same recognized-keyword arm (BUG-proctypoexits2 follow-on, §5b).
fn isUnimplRankScore(text: []const u8) bool {
    return eqi(text, "fraction") or eqi(text, "percent") or
        eqi(text, "nplus1") or eqi(text, "normal") or eqi(text, "savage") or
        eqi(text, "blom") or eqi(text, "tukey") or eqi(text, "vw");
}

/// PRESERVERAWBYVALUES — the one documented SAS 9.4 PROC RANK option neither
/// implemented nor already gap-guarded above (Base SAS 9.4 Procedures Guide,
/// 7th ed., printed p. 2047, === pdf 2096 ===; the full set is DATA=/OUT=/
/// TIES=/GROUPS=/DESCENDING + the score transforms). Gap arm (rc 2).
fn isRankGapOption(kw: []const u8) bool {
    return eqi(kw, "preserverawbyvalues");
}

pub fn runRank(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    _ = out;
    var in_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var descending = false;
    var groups: ?usize = null;
    var ties: TiesKind = .mean;
    var i: usize = 2; // past `proc rank`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
        } else if (optAt(toks, i, "ties")) |v| {
            ties = tiesFromKw(v) orelse return diags.fail(error.ParseError, toks[i].line, "PROC RANK TIES={s} is not recognized (use MEAN|LOW|HIGH|DENSE)", .{v});
            i += 3;
        } else if (toks[i].tag == .name and isUnimplRankScore(toks[i].text)) {
            return failGap(diags, toks[i].line, "PROC RANK {s} is not yet supported — refusing to emit plain ordinal ranks where a score was requested (GAP-rankguards)", .{toks[i].text});
        } else if (tkKw(toks[i], "groups") and i + 2 < toks.len and
            toks[i + 1].tag == .eq and toks[i + 2].tag == .number)
        {
            groups = std.fmt.parseInt(usize, toks[i + 2].text, 10) catch null;
            i += 3;
        } else if (tkKw(toks[i], "descending")) {
            descending = true;
            i += 1;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // out=x(keep=…) — applied by applyOutOptions
        } else if (toks[i].tag == .name) {
            // GAP-procopts: an unknown header option (a typo like `grups=4`,
            // or a BLOM/TUKEY/VW score request outside the guard list) used to
            // be silently skipped — RANK's whole output is the rank values, so
            // a swallowed option IS the wrong result. Name it (D-002).
            // SPLIT: PRESERVERAWBYVALUES is documented (rc 2); a typo stays rc 1.
            if (isRankGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC RANK: option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC RANK: option {s} is not supported", .{toks[i].text});
        } else i += 1;
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    var vars: std.ArrayList([]const u8) = .empty;
    var ranks: std.ArrayList([]const u8) = .empty;
    var bys: std.ArrayList([]const u8) = .empty;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "var")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try vars.append(arena, toks[i].text);
        } else if (tkKw(toks[i], "ranks")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try ranks.append(arena, toks[i].text);
        } else if (tkKw(toks[i], "by")) {
            try parseProcBy(arena, diags, toks, &i, &bys);
        } else i += 1;
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC RANK: no input dataset");
        return;
    };
    const ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)
    if (vars.items.len == 0) return unsupported("PROC RANK: no VAR variable");

    // output = a copy of the input, plus a RANKS column per ranks name (else the
    // rank replaces the VAR value in place).
    const use_ranks = ranks.items.len > 0;
    const oname = out_name orelse ds.name;
    const o = try arena.create(Dataset);
    o.* = Dataset.init(arena, oname);
    const ncin = ds.columns.items.len;
    for (ds.columns.items) |c| _ = try o.addColumn(c.name, c.type);
    if (use_ranks) {
        for (ranks.items) |rn| _ = try o.addColumn(rn, .num);
    }
    const ncout = ncin + (if (use_ranks) ranks.items.len else 0);

    const cells = try arena.alloc([]Value, ds.rows.items.len);
    for (ds.rows.items, 0..) |row, r| {
        cells[r] = try arena.alloc(Value, ncout);
        for (0..ncin) |k| cells[r][k] = row[k];
        for (ncin..ncout) |k| cells[r][k] = Value.missing;
    }

    // BY column indices (input assumed sorted by them, as SAS requires)
    const pb = try decodeProcBy(arena, bys.items);
    var bcols: std.ArrayList(usize) = .empty;
    var bdesc: std.ArrayList(bool) = .empty; // BY direction per bcols entry — this decode SKIPS missing names, so pb.desc alone would misalign
    for (pb.names, 0..) |bn, k| if (ds.indexOf(bn)) |ix| {
        try bcols.append(arena, ix);
        try bdesc.append(arena, pb.desc[k]);
    }; // GAP-procbydescending: clean names (contiguous-run grouping is direction-neutral)
    // BY demands sorted data: a backward step between contiguous groups ERRORs
    // like SAS — the same guard MEANS/TRANSPOSE/UNIVARIATE run
    // (BUG-meansbyunsorted), joined here per NOTE-procsortguards. Without it an
    // unsorted BY silently split a repeated key into two contiguous runs and
    // ranked within each run — plausible-looking WRONG ranks at exit 0.
    // DESCENDING flips the check per key; NOTSORTED drops it.
    if (bcols.items.len > 0 and !pb.notsorted) {
        const rows = ds.rows.items;
        var s: usize = 0;
        while (s < rows.len) {
            var e = s + 1;
            while (e < rows.len and byEqual(rows[s], rows[e], bcols.items)) e += 1;
            if (e < rows.len) if (byOrderViolation(rows[e], rows[s], bcols.items, bdesc.items)) |k|
                return diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (bdesc.items[k]) "descending" else "ascending" });
            s = e;
        }
    }

    const nvar = if (use_ranks) @min(vars.items.len, ranks.items.len) else vars.items.len;
    const rows = ds.rows.items;
    var start: usize = 0;
    while (start < rows.len) {
        var end = start + 1;
        while (end < rows.len and byEqual(rows[start], rows[end], bcols.items)) end += 1;
        for (0..nvar) |k| {
            const vidx = ds.indexOf(vars.items[k]) orelse continue;
            const tidx = if (use_ranks) ncin + k else vidx;
            try rankRange(arena, ds, start, end, vidx, descending, ties, groups, cells, tidx);
        }
        start = end;
    }

    for (cells) |row| try o.appendRow(row);
    try applyOutOptions(arena, o, toks, diags, "out"); // out=X(keep=/drop=) — BUG-procoutkeep
    try lib.put(oname, o);
}

/// Rank the rows `[start,end)` of `ds` on column `vidx`, writing each row's rank
/// (or GROUPS bucket) into `cells[row][tidx]`; missing values stay missing.
fn rankRange(arena: std.mem.Allocator, ds: *Dataset, start: usize, end: usize, vidx: usize, descending: bool, ties: TiesKind, groups: ?usize, cells: [][]Value, tidx: usize) !void {
    const RV = struct { idx: usize, v: f64 };
    var ent: std.ArrayList(RV) = .empty;
    for (start..end) |r| {
        const x = toNum(ds.row(r)[vidx]);
        if (std.math.isNan(x)) continue; // missing → no rank (cell already missing)
        try ent.append(arena, .{ .idx = r, .v = x });
    }
    const n = ent.items.len;
    if (n == 0) return;
    std.mem.sort(RV, ent.items, descending, struct {
        fn lt(desc: bool, x: RV, y: RV) bool {
            return if (desc) x.v > y.v else x.v < y.v;
        }
    }.lt);

    const nf: f64 = @floatFromInt(n);
    var i: usize = 0;
    var dense: f64 = 0;
    while (i < n) {
        var j = i + 1;
        while (j < n and ent.items[j].v == ent.items[i].v) j += 1; // a run of equal values
        dense += 1;
        const lo: f64 = @floatFromInt(i + 1); // 1-based ordinal span of the tie run
        const hi: f64 = @floatFromInt(j);
        const rank: f64 = switch (ties) {
            .mean => (lo + hi) / 2,
            .low => lo,
            .high => hi,
            .dense => dense,
        };
        const val: f64 = if (groups) |g| @floor(rank * @as(f64, @floatFromInt(g)) / (nf + 1)) else rank;
        for (i..j) |m| cells[ent.items[m].idx][tidx] = .{ .num = val };
        i = j;
    }
}

// ── PROC STANDARD ────────────────────────────────────────────────────────────
//
// `proc standard data=IN [out=OUT] [mean=M] [std=S] [replace]; [var …;] [by …;] run;`
// Standardizes each VAR variable (default: every numeric non-BY column) within
// each BY group to the target MEAN=/STD=:
//     new = (x − groupMean)/groupStd × S + M        (groupStd = n−1 sample std)
// Defaults: OMITTED MEAN= / STD= leave that moment UNSET — the target is the
// BY group's SAMPLE mean/std, so both unset → output == input and REPLACE
// imputes the sample mean (the clinical mean-imputation idiom, BUG-stdnodefault).
// Explicit MEAN=0 STD=1 → z-scores (GAP-procstandard). REPLACE
// fills a missing cell with the target mean; without it missing stays missing
// (special missings preserved). No OUT= → replace the input dataset (the RANK
// convention). A BY group whose sample std is 0 or undefined (constant column /
// n<2) maps every non-missing value to the target mean — (x−μ)=0 for all of them.
// ponytail: VARDEF=/FREQ/WEIGHT/PRINT and unknown options/statements fail LOUD
// at parse rather than being silently swallowed.

pub fn runStandard(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var in_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var target_mean: f64 = 0;
    var target_std: f64 = 1;
    // BUG-stdnodefault: MEAN=/STD= OMITTED leaves that moment UNSET — the target
    // falls back to the BY group's SAMPLE mean/std (so both unset = identity,
    // and REPLACE imputes the sample mean), never 0/1.
    var mean_set = false;
    var std_set = false;
    var replace = false;
    var i: usize = 2; // past `proc standard`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
        } else if (tkKw(toks[i], "mean") or tkKw(toks[i], "std")) {
            const is_mean = toks[i].text.len == 4; // "mean" vs "std"
            var j = i + 1;
            if (!atTag(toks, j, .eq)) return diags.fail(error.ParseError, toks[i].line, "PROC STANDARD {s} expects {s}=<number>", .{ toks[i].text, toks[i].text });
            j += 1;
            var neg = false;
            if (atTag(toks, j, .minus)) {
                neg = true;
                j += 1;
            }
            if (!atTag(toks, j, .number)) return diags.fail(error.ParseError, toks[i].line, "PROC STANDARD {s}= expects a number", .{toks[i].text});
            const v = std.fmt.parseFloat(f64, toks[j].text) catch
                return diags.fail(error.ParseError, toks[j].line, "PROC STANDARD {s}= value {s} is not a number", .{ toks[i].text, toks[j].text });
            if (is_mean) {
                target_mean = if (neg) -v else v;
                mean_set = true;
            } else {
                target_std = if (neg) -v else v;
                std_set = true;
            }
            i = j + 1;
        } else if (tkKw(toks[i], "replace")) {
            replace = true;
            i += 1;
        } else if (toks[i].tag == .lparen) {
            // data=X(…) / out=X(…) dataset-option group — applyOutOptions and
            // dataOptionToks read them from the token slice; just step over.
            var depth: usize = 0;
            while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) {
                        i += 1;
                        break;
                    }
                }
            }
        } else if (toks[i].tag == .name) {
            return diags.fail(error.ParseError, toks[i].line, "PROC STANDARD option {s} is not yet supported", .{toks[i].text});
        } else i += 1;
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    var vars: std.ArrayList([]const u8) = .empty;
    var bys: std.ArrayList([]const u8) = .empty;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "var")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try vars.append(arena, toks[i].text);
        } else if (tkKw(toks[i], "by")) {
            try parseProcBy(arena, diags, toks, &i, &bys);
        } else if (tkKw(toks[i], "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1; // procInput applies it
        } else if (toks[i].tag == .name) {
            return diags.fail(error.ParseError, toks[i].line, "PROC STANDARD statement {s} is not yet supported", .{toks[i].text});
        } else i += 1;
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC STANDARD: no input dataset");
        return;
    };
    const ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)

    // BY column indices (input assumed sorted by them, as SAS requires)
    const pb = try decodeProcBy(arena, bys.items);
    var bcols: std.ArrayList(usize) = .empty;
    for (pb.names) |bn| { // GAP-procbydescending: clean names (contiguous-run grouping is direction-neutral)
        const ix = ds.indexOf(bn) orelse
            return diags.fail(error.ParseError, toks[0].line, "PROC STANDARD: BY variable {s} is not in the dataset", .{bn});
        try bcols.append(arena, ix);
    }
    // BY demands sorted data — the same guard MEANS/TRANSPOSE/UNIVARIATE run
    // (BUG-meansbyunsorted), joined here per NOTE-procsortguards. Without it an
    // unsorted BY silently standardized within each contiguous run: a repeated
    // key got TWO different group means — plausible-looking WRONG values at
    // exit 0. DESCENDING flips the check per key; NOTSORTED drops it.
    if (bcols.items.len > 0 and !pb.notsorted) {
        const rows = ds.rows.items;
        var s: usize = 0;
        while (s < rows.len) {
            var e = s + 1;
            while (e < rows.len and byEqual(rows[s], rows[e], bcols.items)) e += 1;
            if (e < rows.len) if (byOrderViolation(rows[e], rows[s], bcols.items, pb.desc)) |k|
                return diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (pb.desc[k]) "descending" else "ascending" });
            s = e;
        }
    }

    // VAR columns: the `var` list, else every numeric column not used as BY
    var vcols: std.ArrayList(usize) = .empty;
    if (vars.items.len > 0) {
        for (vars.items) |v| {
            const ix = ds.indexOf(v) orelse
                return diags.fail(error.ParseError, toks[0].line, "PROC STANDARD: variable {s} is not in the dataset", .{v});
            if (ds.columns.items[ix].type != .num)
                return diags.fail(error.ParseError, toks[0].line, "PROC STANDARD: variable {s} is not numeric", .{v});
            try vcols.append(arena, ix);
        }
    } else {
        for (ds.columns.items, 0..) |c, ix| {
            if (c.type != .num) continue;
            if (idxIn(bcols.items, ix)) continue;
            try vcols.append(arena, ix);
        }
    }
    if (vcols.items.len == 0) {
        unsupported("PROC STANDARD: no numeric variable to standardize");
        return;
    }

    const oname = out_name orelse ds.name;
    const o = try dupDataset(arena, ds);
    o.name = oname;
    // mutable row copies — the dup shares ds's const row slices
    const cells = try arena.alloc([]Value, o.rows.items.len);
    for (o.rows.items, 0..) |row, r| {
        cells[r] = try arena.dupe(Value, row);
        o.rows.items[r] = cells[r];
    }

    const rows = ds.rows.items;
    var start: usize = 0;
    while (start < rows.len) {
        var end = start + 1;
        while (end < rows.len and byEqual(rows[start], rows[end], bcols.items)) end += 1;
        for (vcols.items) |vidx| {
            const s = computeStats(rows[start..end], vidx, null); // n−1 sample std (VARDEF=DF)
            if (s.n == 0) continue; // all missing — no mean to standardize or REPLACE with
            // unset moment -> keep the group's sample moment (BUG-stdnodefault)
            const tm = if (mean_set) target_mean else s.mean;
            const ts = if (std_set) target_std else s.std;
            for (start..end) |r| {
                const x = toNum(cells[r][vidx]);
                if (std.math.isNan(x)) {
                    if (replace) cells[r][vidx] = .{ .num = tm };
                } else {
                    // std 0/undefined (constant group, n<2) → the target mean
                    cells[r][vidx] = .{ .num = if (s.std > 0) (x - s.mean) / s.std * ts + tm else tm };
                }
            }
        }
        start = end;
    }

    try applyOutOptions(arena, o, toks, diags, "out"); // out=X(keep=/drop=) — BUG-procoutkeep
    try lib.put(oname, o);
}

// ── PROC CONTENTS ────────────────────────────────────────────────────────────
//
// `proc contents data=IN [out=OUT] [noprint]; run;` — the dataset's metadata:
// observation and variable counts, then the alphabetic variable table (position,
// name, type, length, format, informat, label). OUT= writes one row per variable.
// ponytail: length is 8 for a numeric and the widest stored value for a char (we
// don't persist declared lengths); label is unavailable → blank. No engine/
// created/modified/index detail lines.

/// A numeric is stored in 8 bytes. A character's length is its declared length
/// when a `$w.` character format pins it (the only place the declared length
/// survives on the dataset — BUG-contentsmeta); otherwise the widest value seen.
fn contentsLen(ds: *Dataset, ci: usize, is_num: bool) usize {
    // a declared numeric LENGTH<8 (3..7) reaches the descriptor as col.len (GH#59
    // NUMLEN-meta); no declared len → the full 8-byte double.
    if (is_num) {
        if (ds.columns.items[ci].len) |l| if (l >= 3 and l < 8) return l;
        return 8;
    }
    if (ds.columns.items[ci].len) |l| return l; // LENGTH-statement declared width (BUG-contentsmeta)
    if (ds.columns.items[ci].format) |f| if (charFormatWidth(f)) |w| return w;
    var m: usize = 1;
    for (ds.rows.items) |row| switch (row[ci]) {
        .str => |s| m = @max(m, s.len),
        .num => {},
    };
    return m;
}

/// The declared width `w` of a character format `$[name]w[.d]` (e.g. `$8.` → 8,
/// `$char20.` → 20), or null when the format carries no width (e.g. `$yn.`).
fn charFormatWidth(fmt: []const u8) ?usize {
    if (fmt.len == 0 or fmt[0] != '$') return null; // only character formats give a length
    const end = std.mem.indexOfScalar(u8, fmt, '.') orelse fmt.len;
    var j = end; // the digit run immediately before the '.' (or end) is the width
    while (j > 0 and std.ascii.isDigit(fmt[j - 1])) j -= 1;
    if (j == end) return null;
    const w = std.fmt.parseInt(usize, fmt[j..end], 10) catch return null;
    return if (w > 0) w else null;
}

pub fn runContents(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var in_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var noprint = false;
    var varnum = false; // VARNUM: variables listed in creation order, not alphabetic
    var short = false; // SHORT: compact variable-name list, no attribute table
    var i: usize = 2; // past `proc contents`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (optAt(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
        } else if (tkKw(toks[i], "noprint")) {
            noprint = true;
            i += 1;
        } else if (optAt(toks, i, "order")) |v| {
            // ORDER=VARNUM lists in creation order; COLLATE/CASECOLLATE/
            // IGNORECASE are collation variants of the alphabetic default —
            // accept, listing stays alphabetic. ponytail: case-insensitive
            // collation only, add locale collation if a study ever needs it.
            if (eqi(v, "varnum")) varnum = true;
            i += 3;
        } else if (tkKw(toks[i], "position")) {
            varnum = true; // POSITION: the position-ordered listing
            i += 1;
        } else if (tkKw(toks[i], "varnum")) {
            varnum = true;
            i += 1;
        } else if (tkKw(toks[i], "short")) {
            short = true;
            i += 1;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // out=x(keep=…) — applied by applyOutOptions
        } else {
            // D-002 fail-loud (BUG-procoptswallow): unknown options error visibly.
            // BUG-proctypoexits2: split — a documented option we don't implement
            // is a gap (rc 2, byte-identical UNSUPPORTED message); any other
            // name is the user's typo (rc 1, same message body via diags).
            if (toks[i].tag == .name) {
                if (isContentsGapOption(toks[i].text)) {
                    unsupported(try std.fmt.allocPrint(arena, "PROC CONTENTS: unknown option {s}", .{toks[i].text}));
                    return;
                }
                return diags.fail(error.ParseError, toks[i].line, "PROC CONTENTS: unknown option {s}", .{toks[i].text});
            }
            i += 1;
        }
    }

    // SAS PROC CONTENTS has NO sub-statements — so anything between the header
    // and `run;` other than a D-014a mid-step global (skip exactly what the
    // top level handles) is an unknown statement and fails loud
    // (GAP-procsubstmtswallow); it used to be silently ignored because no loop
    // ever scanned it. No WHERE arm: CONTENTS takes none, and no procInput runs
    // here, so a skip would be a silent no-op (the sin D-014a was amended for).
    if (atTag(toks, i, .semicolon)) i += 1; // past the header ';'
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else if (toks[i].tag == .name) {
            return diags.fail(error.ParseError, toks[i].line, "PROC CONTENTS statement {s} is not supported", .{toks[i].text});
        } else i += 1; // stray punctuation
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    // `data=[libref.]_ALL_` — a CONTENTS section per member of the library
    // (BUG-contents-all). ponytail: the printed listing only; OUT= over _ALL_
    // (a combined member×variable table) is not built.
    if (in_name) |n| if (contentsAllLib(n)) |prefix| {
        if (noprint) return;
        var any = false;
        for (lib.names.items, 0..) |nm, k| if (memberInLib(nm, prefix)) {
            try printOneContents(arena, out, lib.sets.items[k], varnum, short);
            any = true;
        };
        if (!any) unsupported("PROC CONTENTS: no members in the library");
        return;
    };

    const ds = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC CONTENTS: no input dataset");
        return;
    };

    // OUT= — one observation per variable (NAME, TYPE, LENGTH, VARNUM, FORMAT, LABEL)
    if (out_name) |on| {
        const o = try arena.create(Dataset);
        o.* = Dataset.init(arena, on);
        _ = try o.addColumn("NAME", .char);
        _ = try o.addColumn("TYPE", .num); // 1 = numeric, 2 = character (SAS codes)
        _ = try o.addColumn("LENGTH", .num);
        _ = try o.addColumn("VARNUM", .num);
        // FORMAT holds the uppercase format NAME only ($ kept for char formats),
        // with the width/decimals split out into FORMATL/FORMATD, as SAS emits
        // (BUG-contentsfmtcol). INFORMAT/INFORML/INFORMD are the read-side twins,
        // built the same way from the column's informat (NOTE-contentsinformat).
        _ = try o.addColumn("FORMAT", .char);
        _ = try o.addColumn("FORMATL", .num);
        _ = try o.addColumn("FORMATD", .num);
        _ = try o.addColumn("INFORMAT", .char);
        _ = try o.addColumn("INFORML", .num);
        _ = try o.addColumn("INFORMD", .num);
        _ = try o.addColumn("LABEL", .char);
        for (ds.columns.items, 0..) |c, ci| {
            const is_num = c.type == .num;
            const spec = if (c.format) |f| format.parseSpec(f) else format.Spec{};
            const fmt_name = if (c.format == null) "" else try std.fmt.allocPrint(arena, "{s}{s}", .{
                if (spec.is_char) "$" else "",
                try std.ascii.allocUpperString(arena, spec.name),
            });
            const inspec = if (c.informat) |f| format.parseSpec(f) else format.Spec{};
            const inf_name = if (c.informat == null) "" else try std.fmt.allocPrint(arena, "{s}{s}", .{
                if (inspec.is_char) "$" else "",
                try std.ascii.allocUpperString(arena, inspec.name),
            });
            try o.appendRow(&.{
                .{ .str = c.name },
                .{ .num = if (is_num) 1 else 2 },
                .{ .num = @floatFromInt(contentsLen(ds, ci, is_num)) },
                .{ .num = @floatFromInt(ci + 1) },
                .{ .str = fmt_name },
                .{ .num = @floatFromInt(spec.w) },
                .{ .num = @floatFromInt(spec.d) },
                .{ .str = inf_name },
                .{ .num = @floatFromInt(inspec.w) },
                .{ .num = @floatFromInt(inspec.d) },
                .{ .str = c.label orelse "" }, // BUG-contentsmeta: labels now persist
            });
        }
        try applyOutOptions(arena, o, toks, diags, "out"); // out=X(keep=/drop=) — BUG-procoutkeep
        try lib.put(on, o);
    }

    if (noprint) return;
    try printOneContents(arena, out, ds, varnum, short);
}

/// True if `name` is `_ALL_`, optionally `libref.`-qualified; the optional's
/// payload is the member-name prefix to match ("mylib." or "" for WORK/one-level).
fn contentsAllLib(name: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, name, '.')) |dot| {
        return if (eqi(name[dot + 1 ..], "_all_")) name[0 .. dot + 1] else null;
    }
    return if (eqi(name, "_all_")) "" else null;
}

/// Whether a library member `name` belongs to the library named by `prefix`
/// ("mylib." → prefix match; "" → WORK, i.e. a one-level name or a `work.` member).
fn memberInLib(name: []const u8, prefix: []const u8) bool {
    if (prefix.len == 0)
        return std.mem.indexOfScalar(u8, name, '.') == null or std.ascii.startsWithIgnoreCase(name, "work.");
    return std.ascii.startsWithIgnoreCase(name, prefix);
}

/// Print one dataset's CONTENTS section (header + variable table). Alphabetic
/// order is the SAS default; VARNUM lists creation order; SHORT prints only the
/// compact space-separated name list (BUG-procoptswallow).
fn printOneContents(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, varnum: bool, short: bool) !void {
    const nvar = ds.columns.items.len;
    try out.appendSlice(arena, (" " ** 26) ++ "The CONTENTS Procedure\n\n");
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "Data Set Name  {s}\n", .{ds.name}));
    if (ds.label) |lbl| try out.appendSlice(arena, try std.fmt.allocPrint(arena, "Label          {s}\n", .{lbl}));
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "Observations   {d}\n", .{ds.rows.items.len}));
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "Variables      {d}\n\n", .{nvar}));

    // display order: creation order under VARNUM, else alphabetic by name (SAS
    // default); `#` = creation position either way.
    const order = try arena.alloc(usize, nvar);
    for (order, 0..) |*p, k| p.* = k;
    if (!varnum) std.mem.sort(usize, order, ds.columns.items, struct {
        fn lt(cols: []const Column, x: usize, y: usize) bool {
            return std.ascii.orderIgnoreCase(cols[x].name, cols[y].name) == .lt;
        }
    }.lt);

    // SHORT: just the names, space-separated — no attribute table.
    if (short) {
        for (order, 0..) |ci, j| {
            if (j > 0) try out.append(arena, ' ');
            try out.appendSlice(arena, ds.columns.items[ci].name);
        }
        try out.append(arena, '\n');
        return;
    }

    try out.appendSlice(arena, " " ** 14);
    try out.appendSlice(arena, if (varnum) "Variables in Creation Order\n\n" else "Alphabetic List of Variables and Attributes\n\n");

    // build cell texts, then size each column to its widest entry. SAS's column
    // order puts Informat between Format and Label (NOTE-contentsinformat); a var
    // with no informat prints blank (we never invent one).
    const hdr = [_][]const u8{ "#", "Variable", "Type", "Len", "Format", "Informat", "Label" };
    const right = [_]bool{ true, false, false, true, false, false, false };
    var body: std.ArrayList([7][]const u8) = .empty;
    for (order) |ci| {
        const c = ds.columns.items[ci];
        const is_num = c.type == .num;
        try body.append(arena, .{
            try std.fmt.allocPrint(arena, "{d}", .{ci + 1}),
            c.name,
            if (is_num) "Num" else "Char",
            try std.fmt.allocPrint(arena, "{d}", .{contentsLen(ds, ci, is_num)}),
            // SAS uppercases the format name; digits/./$ are unaffected, so an
            // uppercase of the whole spec uppercases exactly the name (BUG-contentsfmtcol).
            try std.ascii.allocUpperString(arena, c.format orelse ""),
            try std.ascii.allocUpperString(arena, c.informat orelse ""),
            c.label orelse "", // BUG-contentsmeta: variable label
        });
    }
    var w = [_]usize{0} ** 7;
    for (0..7) |j| {
        w[j] = hdr[j].len;
        for (body.items) |cells| w[j] = @max(w[j], cells[j].len);
    }
    try contentsRow(arena, out, hdr, w, right);
    for (body.items) |cells| try contentsRow(arena, out, cells, w, right);
}

/// One CONTENTS table row: seven cells, 2-blank gutter, right/left per column.
fn contentsRow(arena: std.mem.Allocator, out: *std.ArrayList(u8), cells: [7][]const u8, w: [7]usize, right: [7]bool) !void {
    var buf: std.ArrayList(u8) = .empty;
    for (cells, 0..) |txt, j| {
        if (j > 0) try buf.appendSlice(arena, "  ");
        const pad = w[j] -| txt.len;
        if (right[j]) {
            for (0..pad) |_| try buf.append(arena, ' ');
            try buf.appendSlice(arena, txt);
        } else {
            try buf.appendSlice(arena, txt);
            for (0..pad) |_| try buf.append(arena, ' ');
        }
    }
    try out.appendSlice(arena, std.mem.trimEnd(u8, buf.items, " "));
    try out.append(arena, '\n');
}

// ── PROC DATASETS ──────────────────────────────────────────────────────────

/// Rename a library member in place (CHANGE old=new; / RENAME at member level):
/// the same Dataset keeps its slot under the new name; the old name disappears.
fn dsRename(lib: *Library, old: []const u8, new: []const u8) bool {
    for (lib.names.items, 0..) |n, i| if (eqi(n, old)) {
        lib.names.items[i] = new; // token text is program-arena-lived
        lib.sets.items[i].name = new;
        return true;
    };
    return false;
}

/// Drop a library member (DELETE ds …;). Returns false if it wasn't present.
/// PROC DATASETS ... KILL — remove every member of `libname` (default WORK).
/// WORK members are unqualified names; a named library's members are `lib.member`
/// (as coalesceLibrefs folds them), so kill by that prefix.
/// Qualify a PROC DATASETS member with the LIB= libname: a directory libname keys
/// its members `<libname>.<member>` (as `data lib.m` / SET / PRINT do), so MODIFY/
/// DELETE/CHANGE/APPEND must look them up qualified — not just in WORK
/// (GAP-datasetsmodifylib). WORK (or no LIB=) uses the bare, unqualified name.
fn dsQualify(arena: std.mem.Allocator, libname: ?[]const u8, member: []const u8) diag.Error![]const u8 {
    // An already-two-level member (`data TGT.DM` keys as `TGT.DM`) must not be
    // re-qualified into `TGT.TGT.DM` (ISS-datasetstwolevel). find() strips a
    // leading `work.` on both sides (exec.zig:102), so `WORK.X` passed through
    // as-is still resolves to the WORK member.
    if (std.mem.indexOfScalar(u8, member, '.') != null) return member;
    if (libname) |ln| if (!eqi(ln, "work"))
        return std.fmt.allocPrint(arena, "{s}.{s}", .{ ln, member });
    return member;
}

/// True if `name` is the `_ALL_` delete/kill wildcard — bare `_all_` or
/// `libref._all_` (case-insensitive). SAS 9.4: DELETE _ALL_ / PROC DELETE
/// DATA=_all_ removes every member of the (target) library, not a literal
/// member named "_all_" (BUG-datasetsdeleteall — a silent no-op before).
fn isAllWildcard(name: []const u8) bool {
    const dot = std.mem.indexOfScalar(u8, name, '.');
    return eqi(if (dot) |d| name[d + 1 ..] else name, "_all_");
}

/// The libref of an `_ALL_` wildcard (`lib` from `lib._all_`), or null for a
/// bare `_all_` (→ the caller's default: WORK, or PROC DATASETS' LIB= scope).
fn allWildcardLib(name: []const u8) ?[]const u8 {
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return null;
    return name[0..dot];
}

fn dsKill(arena: std.mem.Allocator, lib: *Library, libname: ?[]const u8) void {
    const work = libname == null or eqi(libname.?, "work");
    var i: usize = 0;
    while (i < lib.names.items.len) {
        const nm = lib.names.items[i];
        const dot = std.mem.indexOfScalar(u8, nm, '.');
        const hit = if (work)
            dot == null // an unqualified (WORK) member
        else
            dot != null and eqi(nm[0..dot.?], libname.?);
        if (hit) {
            _ = lib.names.orderedRemove(i);
            _ = lib.sets.orderedRemove(i);
        } else i += 1;
    }
    // KILL sweeps the on-disk members of a directory libname too
    // (BUG-datasetsdeletedisk); the empty stem prefix-matches every member.
    if (!work) {
        const all = std.fmt.allocPrint(arena, "{s}.", .{libname.?}) catch return;
        _ = unlinkDisk(arena, all, true);
    }
}

fn dsDelete(arena: std.mem.Allocator, lib: *Library, name: []const u8) bool {
    // Match the way Library.find resolves: WORK is the default library, so
    // `work.x` and one-level `x` name the same table (strip a leading `work.`).
    const q = stripWorkPrefix(name);
    var found = false;
    for (lib.names.items, 0..) |n, i| if (eqi(stripWorkPrefix(n), q)) {
        _ = lib.names.orderedRemove(i);
        _ = lib.sets.orderedRemove(i);
        found = true;
        break;
    };
    // The on-disk member file too — else the EXIST disk probe (84242c4) still
    // finds it and a later SET resurrects the deleted data (BUG-datasetsdeletedisk).
    if (unlinkDisk(arena, name, false) > 0) found = true;
    return found;
}

/// Unlink `lr.member`'s files under a directory libname (`prefix` = the DELETE
/// `pfx:` wildcard / KILL sweep). One-level/WORK names have no disk side.
/// ponytail: a single-file libname (path ends .sas7bdat/.xpt) is skipped —
/// deleting a member of a file-libname waits for a real program to need it.
fn unlinkDisk(arena: std.mem.Allocator, name: []const u8, prefix: bool) usize {
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return 0;
    if (eqi(name[0..dot], "work")) return 0;
    const dir = dsfns.librefDir(name[0..dot]) orelse return 0;
    if (io.endsWithIgnoreCase(dir, ".sas7bdat") or io.endsWithIgnoreCase(dir, ".xpt")) return 0;
    return io.deleteMemberFiles(arena, dir, name[dot + 1 ..], prefix);
}

/// Delete every member whose (WORK-stripped) name starts with `pfx` — the
/// `DELETE tmp_:;` wildcard (GAP-datasetsdeletecolon), in memory AND on disk
/// (BUG-datasetsdeletedisk). Returns how many members/files went.
fn dsDeletePrefix(arena: std.mem.Allocator, lib: *Library, pfx: []const u8) usize {
    const q = stripWorkPrefix(pfx);
    var removed: usize = 0;
    var i: usize = 0;
    while (i < lib.names.items.len) {
        if (std.ascii.startsWithIgnoreCase(stripWorkPrefix(lib.names.items[i]), q)) {
            _ = lib.names.orderedRemove(i);
            _ = lib.sets.orderedRemove(i);
            removed += 1;
        } else i += 1;
    }
    return removed + unlinkDisk(arena, pfx, true);
}

/// Drop a leading `work.` from a (possibly two-level) dataset name — mirrors
/// exec.Library's own WORK-default resolution.
fn stripWorkPrefix(name: []const u8) []const u8 {
    return if (name.len >= 5 and eqi(name[0..5], "work.")) name[5..] else name;
}

/// Documented SAS 9.4 PROC DELETE statement options opensas does NOT
/// implement — the gap arm of the option catch-all (rc 2); anything else is
/// the user's typo (rc 1). Closed set from the PROC DELETE Statement
/// dictionary (printed pp. 786-787, === pdf 835/836 ===); LIB= is the doc's
/// own alias of LIBRARY=.
fn isDeleteGapOption(kw: []const u8) bool {
    inline for (.{ "library", "lib", "gennum", "memtype", "encryptkey", "alter" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// The options the doc puts IN PARENS after each file name (a subset of the
/// statement set — LIBRARY=/LIB= are statement-level only): "You use the
/// option in parentheses after the name of each SAS file" (GENNUM= entry,
/// printed p. 787, === pdf 837 ===). A name in this set is a documented,
/// unimplemented option → failGap (rc 2); anything else in the parens keeps
/// the old silent skip — the doc names nothing else there, and D-018's
/// stay-put direction keeps a possibly-legal spelling from a false rc.
fn isDeleteParenGapOption(kw: []const u8) bool {
    inline for (.{ "gennum", "memtype", "encryptkey", "alter" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// `proc delete data=ds1 ds2 …;` — drop each named dataset from the library
/// (SAS's between-step cleanup). Absent members warn (not fail-loud): the study
/// deletes scratch tables that may never have been created (PROC-delete).
pub fn runDelete(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var i: usize = 2; // past `proc delete`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (tkKw(toks[i], "data") and atTag(toks, i + 1, .eq)) {
            i += 2;
            while (atTag(toks, i, .name)) {
                // A name FOLLOWED BY `=` is a statement option (MEMTYPE=,
                // LIB=, …), not another dataset — stop the file list so the
                // option reaches the catch-all's split guard below (was:
                // eaten as a dataset, warned 'not found', and the VALUE hit
                // the catch-all at rc 1 with a nonsense name).
                if (atTag(toks, i + 1, .eq)) break;
                var name = toks[i].text;
                i += 1;
                // undeclared two-level `libref . member` stays three tokens; fold it
                // (declared librefs are already one token via coalesceLibrefs).
                if (atTag(toks, i, .dot) and atTag(toks, i + 1, .name)) {
                    name = try std.fmt.allocPrint(arena, "{s}.{s}", .{ name, toks[i + 1].text });
                    i += 2;
                }
                // `name(GENNUM=/MEMTYPE=/ENCRYPTKEY=/ALTER=)` — the doc's OWN
                // spelling (the syntax diagram closes that paren set at those
                // four, printed pp. 786-787, === pdf 835/836/837 ===). The old
                // lparen-skip ate the group whole: `data=x(gennum=all)` ran
                // rc 0 with no diagnostic while x vanished — a silent drop on
                // a DESTRUCTIVE request (BUG-deletegennumsilent, D-002's worst
                // case; opensas has no generation model, so honouring
                // GENNUM=ALL is out of scope and failing loud is the answer).
                // Scan BEFORE the delete: a documented name failGaps (rc 2,
                // byte-identical message) with the file left untouched.
                if (atTag(toks, i, .lparen)) {
                    var j = i + 1;
                    var depth: usize = 1;
                    while (j < toks.len and depth > 0) : (j += 1) {
                        if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) depth -= 1 else if (toks[j].tag == .name and atTag(toks, j + 1, .eq) and isDeleteParenGapOption(toks[j].text))
                            return failGap(diags, toks[j].line, "PROC DELETE: option {s} is not supported (only DATA=)", .{toks[j].text});
                    }
                    i = j;
                }
                // `data=_all_` (or `lib._all_`) — sweep every member of that
                // library like KILL (BUG-datasetsdeleteall); bare _all_ = WORK.
                if (isAllWildcard(name)) {
                    dsKill(arena, lib, allWildcardLib(name));
                } else if (!dsDelete(arena, lib, name))
                    diags.warn(toks[i - 1].line, "PROC DELETE: dataset {s} not found", .{name}) catch {};
            }
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // data=x(…) — never read back, but don't false-fire on `keep`
        } else if (toks[i].tag == .name) {
            // GAP-procopts: LIB=/MEMTYPE= or a typo'd option used to vanish
            // here — name it (D-002), mirroring PROC APPEND.
            // SPLIT: the PROC DELETE statement dictionary closes the option
            // set (Base SAS 9.4 Procedures Guide, 7th ed., printed
            // pp. 786-787, === pdf 835/836 ===): DATA= is handled, so
            // LIBRARY=/LIB= (LIB= is the doc's own alias), GENNUM=, MEMTYPE=,
            // ENCRYPTKEY= and ALTER= are the recognized gaps (rc 2); any
            // other name is the user's typo (rc 1).
            if (isDeleteGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC DELETE: option {s} is not supported (only DATA=)", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC DELETE: option {s} is not supported (only DATA=)", .{toks[i].text});
        } else i += 1;
    }
}

/// Rename a column in place (MODIFY ds; RENAME oldvar=newvar;).
fn colRename(ds: *Dataset, old: []const u8, new: []const u8) void {
    if (ds.indexOf(old)) |idx| ds.columns.items[idx].name = new;
}

/// APPEND's BASE=: the existing member, or — when it doesn't exist — a fresh
/// empty dataset with DATA='s schema, which appendRows then fills: SAS
/// auto-creates BASE= as a copy of DATA= (append-to-nothing = create)
/// (BUG-datasetschange F3). Column attributes ride along via addColumnLike.
fn appendTarget(cx: ProcCtx, bn: []const u8, data: *const Dataset) diag.Error!*Dataset {
    if (cx.lib.find(bn)) |b| return b;
    const fresh = try cx.arena.create(Dataset);
    fresh.* = Dataset.init(cx.arena, bn);
    for (data.columns.items) |c| _ = try fresh.addColumnLike(c.name, c);
    return fresh;
}

/// APPEND BASE=b DATA=d: add each DATA row to BASE, matching by variable NAME
/// (a BASE column absent from DATA gets a type-appropriate missing).
/// Shared APPEND body for PROC APPEND and PROC DATASETS' APPEND (one statement
/// in SAS 9.4 — BUG-datasetsappendtype: DATASETS used to copy columns by name
/// with no type check, landing char values in numeric columns silently).
/// Structural reconciliation (Base SAS 9.4 Procedures Guide, DATASETS APPEND
/// Statement — FORCE on printed p.588 [pdf 637]: a DATA= variable "not in the
/// BASE= data set", of a different type, or "longer than the variables in the
/// BASE= data set"; and "Appending to Data Sets That Contain Variables with
/// Different Attributes" printed pp.594-595 [pdf 643-644]: "The length of the
/// variables in the BASE= data set takes precedence. SAS truncates values from
/// the DATA= data set to fit them into the length that is specified in the
/// BASE= data set."): without FORCE any of the three ERRORs and nothing is
/// appended; FORCE reconciles — incompatible values take missing, extra DATA=
/// vars drop, over-length values truncate to the BASE= length — each with a
/// warning. A BASE= var with no DATA= match takes missing values either way.
/// A SHORTER DATA= var needs nothing: char storage is dynamic, so the doc's
/// "pad" is a no-op (GAP-sqldatatypewidth). `proc` labels the messages.
/// Char/numeric width IS tracked now (Column.len) — an earlier ponytail here
/// claimed it wasn't and declared the LENGTH case unreachable; it wasn't,
/// and PROC APPEND stored 8 bytes under a Char 3 descriptor with no diagnostic
/// (BUG-appendcharwidth). The declared-length check catches descriptor-vs-
/// descriptor; the store below additionally clips any wider cell (a DATA=
/// column can carry len null), so a stored value never disagrees with its own
/// descriptor (2a4a2b6a) and PRINT/EXPORT/ODS/read-back are right by
/// construction, like the SQL twin 1ab28654.
fn appendRows(cx: ProcCtx, proc: []const u8, bn: []const u8, base: *Dataset, data: *const Dataset, force: bool, ln: usize) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    // map[k]/compat[k]: for each BASE column, the DATA column feeding it and
    // whether the value may cross (same type).
    const map = try arena.alloc(?usize, base.columns.items.len);
    const compat = try arena.alloc(bool, base.columns.items.len);
    for (base.columns.items, 0..) |bc, k| {
        map[k] = data.indexOf(bc.name);
        compat[k] = false;
        if (map[k]) |di| {
            const dc = data.columns.items[di];
            if (dc.type == bc.type) {
                compat[k] = true;
                // LENGTH — the third FORCE criterion (doc p.588): DATA= longer
                // than BASE=. char: both sides' declared widths; num: len
                // null = full 8 bytes. BASE= len null declares no width, so
                // there is nothing to violate.
                const longer = switch (bc.type) {
                    .char => bc.len != null and dc.len != null and dc.len.? > bc.len.?,
                    .num => bc.len != null and (dc.len orelse 8) > bc.len.?,
                };
                if (longer) {
                    if (!force)
                        return diags.fail(error.ExecError, ln, "{s}: variable {s} length differs between BASE= and DATA= (use FORCE to append with the BASE= length)", .{ proc, bc.name });
                    diags.warn(ln, "{s}: length mismatch on {s}; values truncated to the BASE= length (FORCE)", .{ proc, bc.name }) catch {};
                }
            } else if (!force) {
                return diags.fail(error.ExecError, ln, "{s}: variable {s} type differs between BASE= and DATA= (use FORCE to append with missing values)", .{ proc, bc.name });
            } else {
                diags.warn(ln, "{s}: type mismatch on {s}; values set to missing (FORCE)", .{ proc, bc.name }) catch {};
            }
        }
    }
    for (data.columns.items) |dc| if (base.indexOf(dc.name) == null) {
        if (!force)
            return diags.fail(error.ExecError, ln, "{s}: variable {s} is in DATA= but not in BASE= (use FORCE to drop it)", .{ proc, dc.name });
        diags.warn(ln, "{s}: variable {s} not in BASE= dropped (FORCE)", .{ proc, dc.name }) catch {};
    };

    // BASE is mutated in place like PROC SORT's no-OUT= target — guard the
    // read-only libref BEFORE touching rows (GH#15 pattern, main.zig runSort).
    if (lib.readonlyOut(bn)) return lib.failReadonly(bn);
    for (data.rows.items) |dr| {
        const row = try arena.alloc(Value, base.columns.items.len);
        for (base.columns.items, 0..) |bc, k| {
            var v: Value = if (map[k] != null and compat[k]) dr[map[k].?] else if (bc.type == .char) .{ .str = "" } else Value.missing;
            // The BASE= declared length prevails AT THE STORE (doc p.595):
            // char clips to len bytes; num keeps only the high len bytes of
            // the double (pdv.truncNum, GH#46). Declared mismatches already
            // warned/errored above; this also clips a wider cell from an
            // untracked-width DATA= column (len null) — a stored cell wider
            // than its own descriptor is the failure class itself (2a4a2b6a),
            // so clip here and every reader agrees by construction.
            if (bc.len) |n| {
                switch (v) {
                    .str => |s| if (s.len > n) {
                        v = .{ .str = s[0..n] };
                    },
                    .num => |x| if (n >= 3 and n < 8 and std.math.isFinite(x)) {
                        v = .{ .num = Pdv.truncNum(x, n) };
                    },
                }
            }
            row[k] = v;
        }
        try base.rows.append(base.arena, row);
    }
    // Re-install BASE as a FRESH object: the end-of-run writer skips a
    // disk-loaded input by pointer identity, so re-saving under the same
    // pointer would silently drop the appended rows on reload.
    const saved = try arena.create(Dataset);
    saved.* = base.*;
    try lib.put(bn, saved);
}

/// Documented SAS 9.4 PROC APPEND options opensas does NOT implement — the
/// gap arm of the option catch-all (rc 2); anything else is the user's typo
/// (rc 1). Closed set from the APPEND syntax diagram (printed p. 110,
/// === pdf 159 ===): BASE=/DATA=/FORCE are handled.
fn isAppendGapOption(kw: []const u8) bool {
    inline for (.{ "appendver", "encryptkey", "getsort", "nowarn" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// PROC APPEND BASE=b DATA=d [FORCE]; — add DATA='s rows to BASE= IN PLACE; the
/// step itself lists nothing (FEAT-procappend). SAS 9.4 "PROC APPEND" doc:
/// without FORCE a DATA= variable absent from BASE=, or type-incompatible with
/// its BASE= match, ERRORs and nothing is appended; FORCE reconciles — extra
/// DATA= vars are dropped and incompatible vars take missing values, each with
/// a warning. A BASE= var with no DATA= match takes missing values either way
/// (the doc needs no FORCE for that). DATA= defaults to the last-created
/// dataset, as with the other procs. The LENGTH case the old ponytail here
/// declared unreachable is live (width is tracked): DATA= longer than BASE=
/// ERRORs without FORCE and truncates with FORCE — see appendRows
/// (BUG-appendcharwidth).
pub fn runAppend(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var base_name: ?[]const u8 = null;
    var data_name: ?[]const u8 = null;
    var force = false;
    var i: usize = 2; // past `proc append`
    while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
        if (tkKw(toks[i], "force")) {
            force = true;
        } else if ((tkKw(toks[i], "base") or tkKw(toks[i], "data")) and
            atTag(toks, i + 1, .eq) and atTag(toks, i + 2, .name))
        {
            const is_base = tkKw(toks[i], "base");
            var v = toks[i + 2].text;
            // undeclared two-level `libref . member` stays three tokens; fold it
            // (declared librefs are already one token via coalesceLibrefs).
            if (atTag(toks, i + 3, .dot) and atTag(toks, i + 4, .name)) {
                v = try std.fmt.allocPrint(arena, "{s}.{s}", .{ v, toks[i + 4].text });
                i += 2;
            }
            if (is_base) base_name = v else data_name = v;
            i += 2;
        } else if (toks[i].tag == .name) {
            // SPLIT: the PROC APPEND syntax diagram closes the option set at
            // seven (printed p. 110, === pdf 159 ===): BASE=/DATA=/FORCE are
            // handled, so APPENDVER=/ENCRYPTKEY=/GETSORT/NOWARN are the
            // recognized gaps (rc 2); any other name is the user's typo (rc 1).
            if (isAppendGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC APPEND option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ExecError, toks[i].line, "PROC APPEND option {s} is not supported", .{toks[i].text});
        }
    }
    const bn = base_name orelse
        return diags.fail(error.ExecError, toks[1].line, "PROC APPEND requires BASE= (the table that gains the rows)", .{});
    const data = if (data_name) |dn| lib.find(dn) orelse
        return diags.fail(error.ExecError, toks[1].line, "PROC APPEND: DATA= dataset {s} not found", .{dn}) else lastDataset(lib) orelse
        return diags.fail(error.ExecError, toks[1].line, "PROC APPEND: no DATA= dataset to append", .{});
    // BASE= absent → SAS auto-creates it as a copy of DATA= (BUG-datasetschange F3).
    const base = try appendTarget(cx, bn, data);

    try appendRows(cx, "PROC APPEND", bn, base, data, force, toks[1].line);
}

/// Join a format-spec token run (`8` `.` → "8.", `date9` `.` → "date9.") into one
/// string, so it can be stored on the column as a display format.
fn joinFmt(arena: std.mem.Allocator, toks: []const Token) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (toks) |tk| switch (tk.tag) {
        .dot => try buf.append(arena, '.'),
        .dollar => try buf.append(arena, '$'),
        else => try buf.appendSlice(arena, tk.text),
    };
    return buf.items;
}

/// `proc datasets [library=L] [nolist];` then member/attribute sub-statements to
/// `quit;`: CHANGE (rename member), DELETE, MODIFY ds; {RENAME var=var, FORMAT,
/// INFORMAT, LABEL, LENGTH}, APPEND BASE=/DATA=. Fails loud on anything not yet covered
/// (CLIN-datasets). ponytail: char columns aren't width-tracked, so LENGTH on
/// MODIFY is accepted but has no stored effect.
/// Documented SAS 9.4 PROC DATASETS statement options opensas does NOT
/// implement — the gap arm of the header catch-all (rc 2); anything else is
/// the user's typo (rc 1). Closed set from the "Summary of Optional
/// Arguments" (printed pp. 578-579, === pdf 627/628 ===).
fn isDatasetsGapOption(kw: []const u8) bool {
    inline for (.{ "alter", "encryptkey", "force", "gennum", "noprint", "nowarn", "pw", "read" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

pub fn runDatasets(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var i: usize = 2; // past `proc datasets`
    var kill = false;
    var libname: ?[]const u8 = null;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (tkKw(toks[i], "kill")) {
            kill = true;
            i += 1;
        } else if ((tkKw(toks[i], "library") or tkKw(toks[i], "lib")) and
            i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name)
        {
            libname = toks[i + 2].text;
            i += 3;
        } else if (tkKw(toks[i], "nolist") or tkKw(toks[i], "details") or tkKw(toks[i], "nodetails")) {
            // INERT (SAS 9.4 PROC DATASETS statement doc): NOLIST suppresses
            // the automatic library directory listing, DETAILS/NODETAILS only
            // decorates it — opensas's DATASETS never prints that listing
            // (the CONTENTS sub-statement is the only printer), so all three
            // are unobservable. Enumerated (real clinical idioms) so the chain
            // ends in a real else.
            i += 1;
        } else if (tkKw(toks[i], "memtype") and i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
            // MEMTYPE=DATA is inert — data is the only member type opensas
            // stores, so the filter matches everything it would anyway. Any
            // OTHER type scopes the step's DELETE/CHANGE to member kinds we
            // can't distinguish (a MEMTYPE=CATALOG DELETE must touch nothing)
            // → LOUD, never silently mis-scope a delete (GAP-procopts).
            if (!eqi(toks[i + 2].text, "data")) {
                // ALL/CATALOG/VIEW are documented SAS 9.4 member types we can't
                // scope to — a gap (rc 2); anything else is the user's typo (rc 1).
                if (isDatasetMemberType(toks[i + 2].text))
                    return failGap(diags, toks[i].line, "PROC DATASETS: MEMTYPE={s} is not supported (only DATA)", .{toks[i + 2].text});
                return diags.fail(error.ParseError, toks[i].line, "PROC DATASETS: MEMTYPE={s} is not a valid member type (expected DATA)", .{toks[i + 2].text});
            }
            i += 3;
        } else if (toks[i].tag == .name) {
            // GAP-procopts: the header loop's `: (i += 1)` postlude silently
            // skipped every other token — a typo'd `kll` or an unhonoured
            // ALTER= vanished while the sub-statement chain below fails loud.
            // SPLIT: the PROC DATASETS statement's "Summary of Optional
            // Arguments" closes the set (printed pp. 578-579,
            // === pdf 627/628 ===): KILL/LIBRARY=/NOLIST/DETAILS/NODETAILS/
            // MEMTYPE= are handled, so ALTER=/ENCRYPTKEY=/FORCE/GENNUM=/
            // NOPRINT/NOWARN/PW=/READ= are the recognized gaps (rc 2); any
            // other name is the user's typo (rc 1).
            if (isDatasetsGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC DATASETS: option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC DATASETS: option {s} is not supported", .{toks[i].text});
        } else i += 1;
    }
    if (i < toks.len) i += 1; // past ';'
    // KILL: delete every member of the target library (BUG-datasetskill — the
    // end-of-program WORK-clear idiom, 80 of 164 real programs).
    if (kill) dsKill(arena, lib, libname);

    var cur: ?*Dataset = null; // the MODIFY target, if any
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "quit")) break;
        // slice this sub-statement up to its ';'
        var j = i;
        while (j < toks.len and toks[j].tag != .semicolon) j += 1;
        const stmt = toks[i..j];
        i = if (j < toks.len) j + 1 else j; // past ';'
        if (stmt.len == 0) continue;
        const kw = stmt[0];

        if (tkKw(kw, "run")) {
            cur = null; // RUN commits a batch; MODIFY context ends
        } else if (tkKw(kw, "modify")) {
            cur = if (stmt.len >= 2 and stmt[1].tag == .name) lib.find(try dsQualify(arena, libname, stmt[1].text)) else null;
            if (cur == null) {
                unsupported("PROC DATASETS: MODIFY member not found");
            } else {
                // `modify d (label='…')` — set the dataset label (BUG-datasetsstrip)
                for (stmt[2..], 2..) |tk, k| {
                    if (tkKw(tk, "label") and k + 2 < stmt.len and stmt[k + 1].tag == .eq and stmt[k + 2].tag == .string) {
                        cur.?.label = try arena.dupe(u8, stmt[k + 2].text);
                        break;
                    }
                }
            }
        } else if (tkKw(kw, "attrib")) {
            // `attrib _all_ format=;` / `attrib _all_ informat=;` — the SDTM XPORT
            // clean-up idiom. An empty FORMAT strips every column's display format
            // and an empty INFORMAT strips every column's read informat
            // (BUG-datasetsstrip, BUG-datasetsinformatstrip).
            const ds = cur orelse {
                unsupported("PROC DATASETS: ATTRIB outside MODIFY");
                continue;
            };
            try applyAttrib(arena, ds, stmt[1..], diags);
        } else if (tkKw(kw, "delete")) {
            var k: usize = 1;
            while (k < stmt.len) : (k += 1) {
                if (stmt[k].tag != .name) continue;
                // `delete _all_;` (or `lib._all_`) — every member of the target
                // library, like KILL (BUG-datasetsdeleteall). Bare _all_ honors
                // the LIB= scope; before, a literal member "_all_" lookup found
                // none and silently succeeded, leaving stale datasets.
                if (isAllWildcard(stmt[k].text)) {
                    dsKill(arena, lib, allWildcardLib(stmt[k].text) orelse libname);
                    continue;
                }
                if (k + 1 < stmt.len and stmt[k + 1].tag == .colon) {
                    // `delete pfx:;` — every member with the name prefix
                    // (GAP-datasetsdeletecolon). Zero matches warns, not fails:
                    // the idiom clears scratch families that may never exist.
                    if (dsDeletePrefix(arena, lib, try dsQualify(arena, libname, stmt[k].text)) == 0)
                        diags.warn(stmt[k].line, "PROC DATASETS: DELETE {s}: matched no members", .{stmt[k].text}) catch {};
                    k += 1; // past ':'
                } else if (!dsDelete(arena, lib, try dsQualify(arena, libname, stmt[k].text))) {
                    // Real SAS notes a never-existed member on DELETE and moves on
                    // ("...was not found, but appears on a DELETE statement") — the
                    // member is provably absent everywhere (memory + disk, dsDelete
                    // checks both), so nothing silent is lost. UNSUPPORTED here
                    // exit-2-polluted count-equal domains (GAP-vtabledisk #2).
                    diags.warn(stmt[k].line, "PROC DATASETS: DELETE {s}: member not found", .{stmt[k].text}) catch {};
                }
            }
        } else if (tkKw(kw, "change")) {
            var k: usize = 1;
            while (k + 2 < stmt.len + 1 and k + 2 <= stmt.len) : (k += 3) {
                if (stmt[k].tag == .name and stmt[k + 1].tag == .eq and stmt[k + 2].tag == .name) {
                    const newq = try dsQualify(arena, libname, stmt[k + 2].text);
                    // BUG-datasetschange F1: SAS errors when the target name is
                    // already taken — renaming anyway produced two same-named
                    // members (one shadowed/destroyed). A free target renames as before.
                    if (lib.find(newq) != null)
                        return diags.fail(error.ExecError, stmt[k].line, "PROC DATASETS: cannot CHANGE {s} to {s}: a member named {s} already exists", .{ stmt[k].text, stmt[k + 2].text, stmt[k + 2].text });
                    if (!dsRename(lib, try dsQualify(arena, libname, stmt[k].text), newq))
                        unsupported("PROC DATASETS: CHANGE member not found");
                } else break;
            }
        } else if (tkKw(kw, "append")) {
            var base: ?[]const u8 = null;
            var data: ?[]const u8 = null;
            var force = false;
            var k: usize = 1;
            while (k < stmt.len) : (k += 1) {
                if (tkKw(stmt[k], "force")) {
                    force = true;
                } else if (k + 2 < stmt.len and stmt[k].tag == .name and stmt[k + 1].tag == .eq and stmt[k + 2].tag == .name) {
                    if (eqi(stmt[k].text, "base")) base = stmt[k + 2].text;
                    if (eqi(stmt[k].text, "data")) data = stmt[k + 2].text;
                }
            }
            if (base == null or data == null) {
                unsupported("PROC DATASETS: APPEND needs BASE= and DATA=");
                continue;
            }
            // BUG-datasetsappendtype: same body as PROC APPEND — type check +
            // FORCE gate; the old dsAppend copied by name, silent corruption.
            const bn = try dsQualify(arena, libname, base.?);
            const dn = try dsQualify(arena, libname, data.?);
            const d = lib.find(dn) orelse
                return diags.fail(error.ExecError, stmt[0].line, "PROC DATASETS: APPEND DATA= dataset {s} not found", .{dn});
            // BASE= absent → SAS auto-creates it as a copy of DATA= (BUG-datasetschange F3).
            const b = try appendTarget(cx, bn, d);
            try appendRows(cx, "PROC DATASETS", bn, b, d, force, stmt[0].line);
        } else if (tkKw(kw, "rename") or tkKw(kw, "format") or tkKw(kw, "informat") or tkKw(kw, "label")) {
            const ds = cur orelse {
                unsupported("PROC DATASETS: attribute statement outside MODIFY");
                continue;
            };
            if (tkKw(kw, "rename")) {
                var k: usize = 1;
                while (k + 2 <= stmt.len) : (k += 3) {
                    if (stmt[k].tag == .name and stmt[k + 1].tag == .eq and stmt[k + 2].tag == .name) {
                        // BUG-datasetschange F2: SAS errors "Variable x not
                        // found" — a typo'd target used to silently no-op.
                        if (ds.indexOf(stmt[k].text) == null)
                            return diags.fail(error.ExecError, stmt[k].line, "PROC DATASETS: MODIFY {s}: variable {s} not found", .{ ds.name, stmt[k].text });
                        // BUG-datasetsrenamecollide: SAS errors when the new name
                        // already names a variable — renaming anyway left the
                        // dataset with two same-named columns (silent-wrong).
                        if (!eqi(stmt[k].text, stmt[k + 2].text) and ds.indexOf(stmt[k + 2].text) != null)
                            return diags.fail(error.ExecError, stmt[k].line, "PROC DATASETS: MODIFY {s}: cannot rename {s} to {s}: a variable named {s} already exists", .{ ds.name, stmt[k].text, stmt[k + 2].text, stmt[k + 2].text });
                        colRename(ds, stmt[k].text, stmt[k + 2].text);
                    } else break;
                }
            } else if (tkKw(kw, "format")) {
                // `format VAR... SPEC;` applies the ONE trailing spec to EVERY
                // listed var; `format VAR...;` / `format _all_;` (no spec) strips
                // (BUG-datasetsfmtmulti, BUG-datasetsstrip). Vars are bare `.name`
                // tokens; the trailing format spec begins at the first spec marker:
                // a `$` (`$char20.`), a standalone number (`8.2`, `8.`), a `.dot`
                // (`date9.` → the name just before it), or a `.number` whose text
                // starts with `.` (`.2` in `dollar8.2` → its preceding name). No
                // marker ⇒ no spec ⇒ strip. See lexer: `8.2` is ONE number token,
                // `dollar8.2` is [name "dollar8", number ".2"].
                var fs: usize = stmt.len; // where the format spec begins (== len ⇒ none)
                for (stmt[1..], 1..) |tk, k| {
                    if (tk.tag == .dollar) {
                        fs = k;
                    } else if (tk.tag == .dot) {
                        fs = k - 1; // the format NAME precedes the lone dot (`date9.`)
                    } else if (tk.tag == .number) {
                        fs = if (tk.text.len > 0 and tk.text[0] == '.') k - 1 else k;
                    } else continue;
                    break;
                }
                const spec: ?[]const u8 = if (fs < stmt.len) try joinFmt(arena, stmt[fs..]) else null;
                var k: usize = 1;
                while (k < fs) : (k += 1) {
                    if (stmt[k].tag != .name) continue;
                    if (eqi(stmt[k].text, "_all_")) {
                        for (ds.columns.items) |*c| c.format = spec;
                    } else if (ds.indexOf(stmt[k].text)) |ix| {
                        // NOTE-fmtnumoncharcoerce: the descriptor edit gets the
                        // same type check as the FORMAT statement — else the
                        // poisoned descriptor coerces every later print to '.'.
                        if (spec) |sp| {
                            const col_char = ds.columns.items[ix].type == .char;
                            if (col_char != format.specIsChar(sp)) {
                                if (col_char)
                                    return diags.fail(error.ExecError, stmt[k].line, "The numeric format {s} cannot be used with character variable {s}.", .{ sp, stmt[k].text });
                                return diags.fail(error.ExecError, stmt[k].line, "The character format {s} cannot be used with numeric variable {s}.", .{ sp, stmt[k].text });
                            }
                        }
                        ds.columns.items[ix].format = spec;
                    } else {
                        // F2: unknown variable → fail loud, no silent no-op.
                        return diags.fail(error.ExecError, stmt[k].line, "PROC DATASETS: MODIFY {s}: variable {s} not found", .{ ds.name, stmt[k].text });
                    }
                }
            } else if (tkKw(kw, "informat")) {
                // GAP-datasetsinformatstmt: the INFORMAT statement, mirror of the
                // FORMAT arm above. Base SAS 9.4 Procedures Guide 7th ed. printed
                // p.640 (=== pdf 690 ===): "INFORMAT variable-1 <informat-1>
                // <variable-2 <informat-2> …>;" — "If you do not specify an
                // informat, the INFORMAT statement removes any existing informats
                // for the variables in variable-list." Same accepted shape as
                // FORMAT: ONE trailing spec applies to EVERY listed var, no spec ⇒
                // strip, `_all_` targets every column. NO numeric/character type
                // check (unlike FORMAT): a stored informat is descriptor metadata
                // that never re-renders a stored value, so a mismatched one cannot
                // silently coerce a later print to '.' — the ATTRIB INFORMAT=
                // arm's settled reasoning (2724b755, BUG-datasetsinformatstrip).
                var fs: usize = stmt.len; // where the informat spec begins (== len ⇒ none)
                for (stmt[1..], 1..) |tk, k| {
                    if (tk.tag == .dollar) {
                        fs = k;
                    } else if (tk.tag == .dot) {
                        fs = k - 1; // the informat NAME precedes the lone dot (`best12.`)
                    } else if (tk.tag == .number) {
                        fs = if (tk.text.len > 0 and tk.text[0] == '.') k - 1 else k;
                    } else continue;
                    break;
                }
                const spec: ?[]const u8 = if (fs < stmt.len) try joinFmt(arena, stmt[fs..]) else null;
                var k: usize = 1;
                while (k < fs) : (k += 1) {
                    if (stmt[k].tag != .name) continue;
                    if (eqi(stmt[k].text, "_all_")) {
                        for (ds.columns.items) |*c| c.informat = spec;
                    } else if (ds.indexOf(stmt[k].text)) |ix| {
                        ds.columns.items[ix].informat = spec;
                    } else {
                        // Same verdict as FORMAT/RENAME/LABEL: unknown variable
                        // in valid-SAS terms is the user's error → rc 1 (D-009;
                        // D-009b's corollary: the tree has already voted).
                        return diags.fail(error.ExecError, stmt[k].line, "PROC DATASETS: MODIFY {s}: variable {s} not found", .{ ds.name, stmt[k].text });
                    }
                }
            } else if (tkKw(kw, "label")) {
                var k: usize = 1;
                while (k + 2 < stmt.len) {
                    if (stmt[k].tag == .name and stmt[k + 1].tag == .eq and stmt[k + 2].tag == .string) {
                        if (ds.indexOf(stmt[k].text) == null)
                            return diags.fail(error.ExecError, stmt[k].line, "PROC DATASETS: MODIFY {s}: variable {s} not found", .{ ds.name, stmt[k].text });
                        ds.setLabel(stmt[k].text, stmt[k + 2].text);
                        k += 3;
                    } else k += 1;
                }
            }
        } else if (tkKw(kw, "length")) {
            // BUG-datasetslengthstmtnoop: was a SILENT no-op ("parsed but a
            // no-op (char width not tracked here)") while the sibling ATTRIB
            // LENGTH= arm failed loud (2724b755) — the same user intent loud
            // one way and silent the other (D-002). Real SAS REJECTS the
            // statement here: Base SAS 9.4 Procedures Guide 7th ed. printed
            // p.563 (DATASETS restrictions): "You cannot change the length of
            // a variable using the LENGTH statement or the LENGTH= option in
            // an ATTRIB statement" — and LENGTH is not among MODIFY's
            // subordinate statements (the p.576 syntax diagram runs ATTRIB …
            // XATTR with no LENGTH). rc 1, not 2: the user's SAS is wrong,
            // not an opensas gap — the ATTRIB LENGTH= arm's verdict (D-009;
            // D-009b's corollary: the tree has already voted). Same message
            // vocabulary as that arm so the family reads consistently.
            return diags.fail(error.ExecError, kw.line, "PROC DATASETS: the LENGTH statement is not valid in the DATASETS procedure (a variable's length cannot be changed after creation — use a DATA step)", .{});
        } else if (tkKw(kw, "contents")) {
            // `CONTENTS DATA=member [VARNUM] [NOPRINT] [OUT=ds];` — the same
            // variable/metadata listing PROC CONTENTS renders (GH#8). NOPRINT
            // (the SE/DM idiom) suppresses output and has no dataset effect → a
            // safe no-op. Without NOPRINT we print the listing, routing to the same
            // printOneContents standalone CONTENTS uses. But OUT= CREATES a dataset
            // a later step reads and we don't build it → fail LOUD, never a silent
            // drop (a downstream "not found" with no cause) (GAP-datasetscontents-loud).
            var has_noprint = false;
            var has_out = false;
            var data_name: ?[]const u8 = null;
            for (stmt[1..], 1..) |tk, k| {
                if (tkKw(tk, "noprint")) has_noprint = true;
                if (tkKw(tk, "out") and k + 1 < stmt.len and stmt[k + 1].tag == .eq) has_out = true;
                if (optAt(stmt, k, "data")) |v| data_name = v;
            }
            if (has_out) {
                // CONTENTS OUT= is valid SAS 9.4 (the output dataset) — a gap
                // (rc 2); the step still errors loud and creates nothing.
                diag.markGap();
                try diags.report(.err, 0, "PROC DATASETS: CONTENTS OUT= is not supported (the output dataset is not created)", .{});
            } else if (has_noprint) {
                // output suppressed, no dataset effect → nothing to do
            } else if (data_name) |dn| {
                const qn = try dsQualify(arena, libname, dn);
                if (isAllWildcard(qn)) {
                    // SAS: CONTENTS DATA=_ALL_ (and bare CONTENTS' whole-library
                    // default) lists EVERY member of the procedure library — not
                    // modeled. Name the gap; "member not found" misreads it as a
                    // typo'd member name (GAP-dsmgmt-tick262 F7). Whole-library
                    // CONTENTS is valid SAS 9.4 → a gap (rc 2), not the user's 1.
                    diag.markGap();
                    try diags.report(.err, 0, "PROC DATASETS: CONTENTS {s} (whole-library contents) is not supported — name a single DATA= member", .{qn});
                } else if (lib.find(qn)) |ds|
                    try printOneContents(arena, out, ds, false, false)
                else
                    try diags.report(.err, 0, "PROC DATASETS: CONTENTS DATA={s}: member not found", .{dn});
            } else {
                try diags.report(.err, 0, "PROC DATASETS: CONTENTS requires DATA=", .{});
            }
        } else if (kw.tag == .name and @import("parser.zig").isMidStepSkippable(kw.text)) {
            // D-014/D-014a: skip exactly what the top level HANDLES mid-step —
            // the main-hoisted globals (TITLE/FOOTNOTE/OPTIONS, hoisted to
            // their own segment with the tokens LEFT in the step) plus the
            // batch-unobservable inert set (GOPTIONS/DM/SASFILE/PAGE/…) — or
            // one legal `proc datasets; title "t"; …` kills the step at exit
            // 2. LIBNAME executed in the parseLibnames pre-pass; unhoisted
            // ODS/FILENAME keep hitting the loud else,
            // never a silent skip (skip predicate == handled predicate).
        } else {
            // Name the sub-statement (GAP-dsmgmt-tick262 F5): a silent-looking
            // generic "unsupported sub-statement" hid WHICH data-management
            // verb (COPY/SAVE/EXCHANGE/AGE/…) the user believes happened.
            unsupported(try std.fmt.allocPrint(arena, "PROC DATASETS: sub-statement {s} is not supported", .{kw.text}));
        }
    }
}

/// Apply an `ATTRIB <vars|_all_> FORMAT=<spec> INFORMAT=<spec> LABEL='…'` inside
/// PROC DATASETS MODIFY. An empty FORMAT=/INFORMAT= strips the display format /
/// read informat (the SDTM XPORT clean-up idiom); LABEL sets each targeted
/// column's label (BUG-datasetsstrip, BUG-datasetsinformatstrip). LENGTH= is not
/// a legal option here and errors (Base SAS 9.4 Procedures Guide 7th ed. p.598:
/// inside DATASETS, ATTRIB "can use only the FORMAT, INFORMAT, and LABEL options").
fn applyAttrib(arena: std.mem.Allocator, ds: *Dataset, toks: []const Token, diags: *diag.Diagnostics) diag.Error!void {
    const isOpt = struct {
        fn f(tk: Token) bool {
            return tk.tag == .name and (eqi(tk.text, "format") or eqi(tk.text, "informat") or eqi(tk.text, "label") or eqi(tk.text, "length"));
        }
    }.f;
    // target variable names (or `_all_`) precede the first option keyword
    var v: usize = 0;
    while (atTag(toks, v, .name) and !isOpt(toks[v])) v += 1;
    const targets = toks[0..v];
    const all = targets.len == 1 and eqi(targets[0].text, "_all_");
    // walk `opt = value` pairs; a value runs until the next option keyword (or end)
    var k = v;
    while (k + 1 < toks.len) {
        if (!(isOpt(toks[k]) and toks[k + 1].tag == .eq)) {
            k += 1;
            continue;
        }
        const opt = toks[k].text;
        var e = k + 2;
        while (e + 1 < toks.len and !(isOpt(toks[e]) and toks[e + 1].tag == .eq)) e += 1;
        if (e < toks.len and !(isOpt(toks[e]) and atTag(toks, e + 1, .eq))) e += 1; // include the last value token
        const val = toks[k + 2 .. @min(e, toks.len)];
        if (eqi(opt, "format")) {
            const spec: ?[]const u8 = if (val.len == 0) null else try joinFmt(arena, val);
            if (all) {
                for (ds.columns.items) |*c| c.format = spec;
            } else for (targets) |tk| if (tk.tag == .name) {
                if (ds.indexOf(tk.text)) |i| {
                    // NOTE-fmtnumoncharcoerce: same descriptor-poison guard as
                    // MODIFY's FORMAT statement above.
                    if (spec) |sp| {
                        const col_char = ds.columns.items[i].type == .char;
                        if (col_char != format.specIsChar(sp)) {
                            if (col_char)
                                return diags.fail(error.ExecError, tk.line, "The numeric format {s} cannot be used with character variable {s}.", .{ sp, tk.text });
                            return diags.fail(error.ExecError, tk.line, "The character format {s} cannot be used with numeric variable {s}.", .{ sp, tk.text });
                        }
                    }
                    ds.columns.items[i].format = spec;
                }
            };
        } else if (eqi(opt, "informat")) {
            // BUG-datasetsinformatstrip (GH#79): `attrib _all_ informat=;` used to
            // be a hard-coded no-op, justified by a comment claiming informats
            // "aren't stored". That claim went stale: `Dataset.Column.informat`
            // carries one, PROC CONTENTS prints an Informat column and xport.zig
            // writes it into the .xpt descriptor — so the no-op shipped a
            // "stripped" dataset still advertising every old informat, at rc 0.
            // Procedures Guide 7th ed. p.641: "To remove all informats from a data
            // set, use the ATTRIB statement ... and the _ALL_ keyword"; p.691's own
            // sample uses the bare empty-value spelling. Same shape as FORMAT= above.
            // ponytail: no numeric/character type check here (the FORMAT arm's
            // NOTE-fmtnumoncharcoerce guard) — a stored informat is descriptor
            // metadata, it never re-renders a stored value, so a mismatched one
            // cannot silently coerce a later print to '.'.
            const spec: ?[]const u8 = if (val.len == 0) null else try joinFmt(arena, val);
            if (all) {
                for (ds.columns.items) |*c| c.informat = spec;
            } else for (targets) |tk| if (tk.tag == .name) {
                if (ds.indexOf(tk.text)) |i| ds.columns.items[i].informat = spec;
            };
        } else if (eqi(opt, "label") and val.len >= 1 and val[0].tag == .string) {
            if (all) {
                for (ds.columns.items) |*c| c.label = val[0].text;
            } else for (targets) |tk| if (tk.tag == .name) ds.setLabel(tk.text, val[0].text);
        } else if (eqi(opt, "length")) {
            // D-002: LENGTH= is NOT one of the three options ATTRIB accepts inside
            // DATASETS (p.598) — real SAS rejects it, and silently dropping it left
            // the user believing a width change happened. rc 1, not 2: this is the
            // user's SAS being wrong, not an opensas gap (D-009 / D-009b(ii)).
            return diags.fail(error.ExecError, toks[k].line, "PROC DATASETS: ATTRIB LENGTH= is not valid in the DATASETS procedure (only FORMAT=, INFORMAT= and LABEL= are)", .{});
        }
        k = e;
    }
}

// ── PROC COMPARE ───────────────────────────────────────────────────────────

const CompCol = struct { bi: usize, ci: usize, name: []const u8, cname: []const u8 };
const CompPair = struct { br: usize, cr: usize };
const CompDiff = struct { p: CompPair, col: CompCol };

/// BUG-comparetypemismatch: pair the columns only when the TYPES match — SAS
/// requires matching variables be the same type and never cross-compares a
/// numeric against a character column (cmpValue would coerce the char via
/// toNum and call base 10 EQUAL to "10", a false green on a QC tool). A
/// conflicting pair is excluded from the value comparison and its name kept
/// so the report notes it loud.
fn compPairCol(arena: std.mem.Allocator, b: *const Dataset, c: *const Dataset, bi: usize, ci: usize, cols: *std.ArrayList(CompCol), mism: *std.ArrayList([]const u8)) error{OutOfMemory}!void {
    if (b.columns.items[bi].type != c.columns.items[ci].type) {
        try mism.append(arena, b.columns.items[bi].name);
        return;
    }
    try cols.append(arena, .{ .bi = bi, .ci = ci, .name = b.columns.items[bi].name, .cname = c.columns.items[ci].name });
}

/// PROC COMPARE METHOD= — how CRITERION=γ bounds the numeric difference
/// (BUG-comparecriterion).
const CompMethod = enum { absolute, relative, percent };

/// COMPARE's equality judgement: exact equality (incl. both-missing) always
/// passes; otherwise numerics are fuzzed per METHOD= — ABSOLUTE |a-b|<=γ,
/// RELATIVE (default) |a-b|/max(|a|,|b|)<=γ, PERCENT that ratio×100<=γ.
/// Chars and one-side-missing never fuzz away. Default γ=1e-8: SAS's default
/// comparison is not bit-exact, so exact-but-noise diffs aren't flagged.
fn compEqual(x: Value, y: Value, method: CompMethod, crit: f64) bool {
    if (cmpValue(x, y) == .eq) return true;
    if (x != .num or y != .num) return false;
    const a = x.num;
    const bv = y.num;
    if (std.math.isNan(a) or std.math.isNan(bv)) return false;
    const d = @abs(a - bv);
    const rel = d / @max(@abs(a), @abs(bv));
    return switch (method) {
        .absolute => d <= crit,
        .relative => rel <= crit,
        .percent => rel * 100 <= crit,
    };
}

/// The join of a row's ID-column values into one comparison key (an in-band
/// separator keeps distinct values from colliding, e.g. "a"+"bc" vs "ab"+"c").
fn idKey(arena: std.mem.Allocator, ds: *const Dataset, idcols: []const usize, row: usize) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    for (idcols, 0..) |ci, k| {
        if (k > 0) try buf.append(arena, 0x01);
        try buf.appendSlice(arena, try cellText(arena, ds.row(row)[ci]));
    }
    return buf.items;
}

/// `proc compare base=B compare=C [var …];` — the clinical double-programming QC
/// report: compare two datasets and summarise variable / observation overlap and
/// a value-level verdict (the all-equal note, or the count of unequal values).
/// ponytail: observations are matched by POSITION (ID-key matching not modeled)
/// and the report is a compact summary, not SAS's full multi-panel listing — the
/// QC signal (exactly-equal vs how many values differ) is complete.
pub fn runCompare(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var base_name: ?[]const u8 = null;
    var comp_name: ?[]const u8 = null;
    var criterion: f64 = 1e-8; // SAS's default fuzz — the comparison is not bit-exact (BUG-comparecriterion)
    var method: CompMethod = .relative;
    var out_name: ?[]const u8 = null; // BUG-compareout
    var out_base = false;
    var out_comp = false;
    var out_dif = false;
    var out_pct = false;
    var out_noequal = false;
    var b_novalues = false; // NOVALUES: suppress the value-difference detail (NOTE-compareoptsnoop)
    var b_nosummary = false; // NOSUMMARY: suppress the summary sections
    var b_brief = false; // BRIEF: compact report — summaries suppressed, value diffs only
    var i: usize = 2; // past `proc compare`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "base") orelse optAt(toks, i, "data")) |v| {
            base_name = v;
            i += 3;
        } else if (optAt(toks, i, "compare") orelse optAt(toks, i, "comp")) |v| {
            comp_name = v;
            i += 3;
        } else if (optAt(toks, i, "method")) |v| {
            method = if (eqi(v, "absolute")) .absolute else if (eqi(v, "relative")) .relative else if (eqi(v, "percent")) .percent else return diags.fail(error.ParseError, toks[i].line, "PROC COMPARE METHOD={s} is not recognized (use ABSOLUTE|RELATIVE|PERCENT)", .{v});
            i += 3;
        } else if (tkKw(toks[i], "criterion") and i + 2 < toks.len and
            toks[i + 1].tag == .eq and toks[i + 2].tag == .number)
        {
            criterion = std.fmt.parseFloat(f64, toks[i + 2].text) catch criterion;
            i += 3;
        } else if (optAt(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
        } else if (tkKw(toks[i], "outbase")) {
            out_base = true;
            i += 1;
        } else if (tkKw(toks[i], "outcomp")) {
            out_comp = true;
            i += 1;
        } else if (tkKw(toks[i], "outdif")) {
            out_dif = true;
            i += 1;
        } else if (tkKw(toks[i], "outpct")) {
            out_pct = true;
            i += 1;
        } else if (tkKw(toks[i], "outnoequal")) {
            out_noequal = true;
            i += 1;
        } else if (tkKw(toks[i], "novalues")) {
            b_novalues = true; // suppress the value-difference detail (NOTE-compareoptsnoop)
            i += 1;
        } else if (tkKw(toks[i], "nosummary")) {
            b_nosummary = true; // suppress the summary sections
            i += 1;
        } else if (tkKw(toks[i], "brief")) {
            b_brief = true; // compact: summaries suppressed, value diffs only
            i += 1;
        } else if (tkKw(toks[i], "listall") or tkKw(toks[i], "printall") or
            tkKw(toks[i], "transpose") or tkKw(toks[i], "clist"))
        {
            // NOTE-compareoptsnoop: these reshape the VALUE listing — LISTALL/
            // PRINTALL print equal values too, TRANSPOSE/CLIST re-panel it — none
            // modeled by the compact report. Fail loud, never silently accept-and-
            // ignore (a QC tool that drops a requested layout is a false green).
            unsupported(try std.fmt.allocPrint(arena, "PROC COMPARE: {s} is not supported", .{toks[i].text}));
            return;
        } else if (tkKw(toks[i], "maxprint") and i + 1 < toks.len and toks[i + 1].tag == .eq) {
            // MAXPRINT= caps the per-variable listing — accepted, the compact
            // summary never lists individual values anyway.
            i += 2;
            if (i < toks.len and toks[i].tag == .lparen) i = skipParen(toks, i) else i += 1;
        } else {
            // D-002 fail-loud (BUG-comparesilentopts), mirroring PROC CONTENTS:
            // an unknown option errors visibly — a typo'd criterionn= used to
            // vanish, silently re-arming the default 1e-8 fuzz and flipping the
            // verdict (a silent-wrong clinical result).
            if (toks[i].tag == .name) {
                // BUG-proctypoexits2: split — a documented option we don't
                // implement is a gap (rc 2, byte-identical UNSUPPORTED message);
                // any other name is the user's typo (rc 1, same body via diags).
                if (isCompareGapOption(toks[i].text)) {
                    unsupported(try std.fmt.allocPrint(arena, "PROC COMPARE: unknown option {s}", .{toks[i].text}));
                    return;
                }
                return diags.fail(error.ParseError, toks[i].line, "PROC COMPARE: unknown option {s}", .{toks[i].text});
            }
            i += 1;
        }
    }
    if (i < toks.len) i += 1; // past ';'

    var varlist: std.ArrayList([]const u8) = .empty;
    var withlist: std.ArrayList([]const u8) = .empty; // BUG-comparewith
    var with_line: usize = 0;
    var idlist: std.ArrayList([]const u8) = .empty;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (tkKw(toks[i], "var")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try varlist.append(arena, toks[i].text);
        } else if (tkKw(toks[i], "with")) {
            with_line = toks[i].line;
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try withlist.append(arena, toks[i].text);
        } else if (tkKw(toks[i], "id")) {
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1)
                if (toks[i].tag == .name) try idlist.append(arena, toks[i].text);
        } else if (toks[i].tag == .name and @import("parser.zig").isMidStepSkippable(toks[i].text)) {
            // Mid-step global statement the top level actually handles here:
            // hoisted (TITLE/FOOTNOTE/OPTIONS, applied via the global segment)
            // or inert-unobservable (GOPTIONS/SASFILE/PAGE/…) — skip, same as
            // TRANSPOSE. LIBNAME ran in the parseLibnames pre-pass; unhoisted
            // ODS/FILENAME fail loud below.
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
        } else {
            // D-002 fail-loud (BUG-comparesilentopts): an unknown statement
            // errors visibly instead of being silently dropped.
            if (toks[i].tag == .name) {
                unsupported(try std.fmt.allocPrint(arena, "PROC COMPARE: unknown statement {s}", .{toks[i].text}));
                return;
            }
            i += 1;
        }
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const b = (if (base_name) |n| lib.find(n) else null) orelse {
        unsupported("PROC COMPARE: BASE= dataset required");
        return;
    };
    const c = (if (comp_name) |n| lib.find(n) else null) orelse {
        unsupported("PROC COMPARE: COMPARE= dataset required");
        return;
    };

    // compared columns: the VAR list (if any), else every variable common to both
    // — but never the ID variables (those key the match, they are not compared).
    var cols: std.ArrayList(CompCol) = .empty;
    var type_mism: std.ArrayList([]const u8) = .empty; // BUG-comparetypemismatch: same-name vars with conflicting types, excluded
    if (withlist.items.len > 0) {
        // BUG-comparewith: WITH pairs positionally with VAR — base.VAR[k] is
        // compared against compare.WITH[k]. A shorter WITH leaves the trailing
        // VAR items compared by same name (SAS semantics); a longer one, or a
        // WITH/VAR name missing from its dataset, fails loud — a silently
        // dropped comparison is a false green on a QC tool. No VAR → each
        // WITH var compares against the same-named base var.
        if (varlist.items.len > 0 and withlist.items.len > varlist.items.len)
            return diags.fail(error.ParseError, with_line, "PROC COMPARE: WITH lists {d} variables but VAR lists only {d}", .{ withlist.items.len, varlist.items.len });
        const vn_list = if (varlist.items.len > 0) varlist.items else withlist.items;
        for (vn_list, 0..) |vn, k| {
            if (nameIn(idlist.items, vn)) continue;
            const wn = if (k < withlist.items.len) withlist.items[k] else vn;
            const bi = b.indexOf(vn) orelse return diags.fail(error.ParseError, with_line, "PROC COMPARE: variable {s} not found in base dataset {s}", .{ vn, b.name });
            const ci = c.indexOf(wn) orelse return diags.fail(error.ParseError, with_line, "PROC COMPARE: WITH variable {s} not found in compare dataset {s}", .{ wn, c.name });
            try compPairCol(arena, b, c, bi, ci, &cols, &type_mism);
        }
    } else if (varlist.items.len > 0) {
        for (varlist.items) |vn| {
            if (nameIn(idlist.items, vn)) continue;
            if (b.indexOf(vn)) |bi| if (c.indexOf(vn)) |ci|
                try compPairCol(arena, b, c, bi, ci, &cols, &type_mism);
        }
    } else {
        for (b.columns.items, 0..) |bc, bi| {
            if (nameIn(idlist.items, bc.name)) continue;
            if (c.indexOf(bc.name)) |ci|
                try compPairCol(arena, b, c, bi, ci, &cols, &type_mism);
        }
    }
    var common_vars: usize = 0;
    for (b.columns.items) |bc| if (c.indexOf(bc.name) != null) {
        common_vars += 1;
    };
    var base_only: usize = 0;
    for (b.columns.items) |bc| if (c.indexOf(bc.name) == null) {
        base_only += 1;
    };
    var comp_only: usize = 0;
    for (c.columns.items) |cc| if (b.indexOf(cc.name) == null) {
        comp_only += 1;
    };

    const nb = b.rowCount();
    const nc = c.rowCount();

    // BUG-compareid: an `id v…;` whose vars exist in BOTH datasets aligns the
    // observations by that key (SAS sort-merges on it); otherwise fall back to the
    // positional obs-number match. ponytail: keys are assumed unique per dataset
    // (clinical QC data always has a unique subject/visit key).
    var id_bi: std.ArrayList(usize) = .empty;
    var id_ci: std.ArrayList(usize) = .empty;
    var use_id = idlist.items.len > 0;
    for (idlist.items) |idn| {
        const bi = b.indexOf(idn);
        const ci = c.indexOf(idn);
        if (bi != null and ci != null) {
            try id_bi.append(arena, bi.?);
            try id_ci.append(arena, ci.?);
        } else use_id = false; // an ID var missing on one side → cannot key
    }
    if (id_bi.items.len == 0) use_id = false;

    // matched (base,comp) observation pairs + the per-side unmatched counts
    var pairs: std.ArrayList(CompPair) = .empty;
    var obs_common: usize = 0;
    var obs_base_only: usize = 0;
    var obs_comp_only: usize = 0;
    if (use_id) {
        var cmap = std.StringHashMap(usize).init(arena);
        for (0..nc) |cr| try cmap.put(try idKey(arena, c, id_ci.items, cr), cr);
        const matched_comp = try arena.alloc(bool, nc);
        @memset(matched_comp, false);
        for (0..nb) |br| {
            if (cmap.get(try idKey(arena, b, id_bi.items, br))) |cr| {
                try pairs.append(arena, .{ .br = br, .cr = cr });
                matched_comp[cr] = true;
                obs_common += 1;
            } else obs_base_only += 1;
        }
        for (0..nc) |cr| if (!matched_comp[cr]) {
            obs_comp_only += 1;
        };
    } else {
        obs_common = @min(nb, nc);
        obs_base_only = nb - obs_common;
        obs_comp_only = nc - obs_common;
        for (0..obs_common) |ri| try pairs.append(arena, .{ .br = ri, .cr = ri });
    }

    // compare the VAR cells within matched pairs only, recording each difference.
    var vars_unequal: usize = 0;
    var total_unequal: usize = 0;
    var diffs: std.ArrayList(CompDiff) = .empty;
    const pair_unequal = try arena.alloc(bool, pairs.items.len); // OUTNOEQUAL filter
    @memset(pair_unequal, false);
    for (cols.items) |col| {
        // the matched pair must index real columns on BOTH sides — a bad pair
        // here is a wrong EQUAL/UNEQUAL verdict from the QC tool itself, the
        // most expensive silent error in the repo (TASTE-asserts).
        assert(col.bi < b.columns.items.len);
        assert(col.ci < c.columns.items.len);
        var any = false;
        for (pairs.items, 0..) |p, pi| {
            if (!compEqual(b.row(p.br)[col.bi], c.row(p.cr)[col.ci], method, criterion)) {
                total_unequal += 1;
                any = true;
                pair_unequal[pi] = true;
                try diffs.append(arena, .{ .p = p, .col = col });
            }
        }
        if (any) vars_unequal += 1;
    }

    // BUG-compareout: OUT= materializes the comparison as a dataset for
    // downstream QC steps — per matched pair one row per requested _TYPE_
    // (BASE by default when no OUTxxx option is given; COMP/DIF/PCT on
    // demand), keyed by the ID vars + _OBS_. DIF = compare−base (SAS: Diff =
    // comparison − base — BUG-comparedifsign), PCT = dif/base×100 (char
    // columns and a zero base → missing).
    // ponytail: observations in one side only are not written.
    if (out_name) |on| {
        const o = try arena.create(Dataset);
        o.* = Dataset.init(arena, on);
        for (id_bi.items) |bi| _ = try o.addColumnLike(b.columns.items[bi].name, b.columns.items[bi]);
        for (cols.items) |col| _ = try o.addColumnLike(col.name, b.columns.items[col.bi]);
        _ = try o.addColumn("_TYPE_", .char);
        _ = try o.addColumn("_OBS_", .num);
        const want_base = out_base or !(out_comp or out_dif or out_pct);
        const nid = id_bi.items.len;
        const w = nid + cols.items.len + 2;
        for (pairs.items, 0..) |p, pi| {
            if (out_noequal and !pair_unequal[pi]) continue;
            const brow = b.row(p.br);
            const crow = c.row(p.cr);
            const obs: f64 = @floatFromInt(p.br + 1);
            var kind: usize = 0; // 0=BASE 1=COMP 2=DIF 3=PCT
            while (kind < 4) : (kind += 1) {
                if (kind == 0 and !want_base) continue;
                if (kind == 1 and !out_comp) continue;
                if (kind == 2 and !out_dif) continue;
                if (kind == 3 and !out_pct) continue;
                const r = try arena.alloc(Value, w);
                for (id_bi.items, 0..) |bi, k| r[k] = brow[bi];
                for (cols.items, 0..) |col, k| {
                    r[nid + k] = switch (kind) {
                        0 => brow[col.bi],
                        1 => crow[col.ci],
                        else => blk: {
                            if (b.columns.items[col.bi].type == .char) break :blk Value.missing;
                            const d = toNum(crow[col.ci]) - toNum(brow[col.bi]); // BUG-comparedifsign: Diff = comparison − base
                            if (kind == 2) break :blk .{ .num = d };
                            const bv = toNum(brow[col.bi]);
                            if (bv == 0) break :blk if (d == 0) .{ .num = 0 } else Value.missing;
                            break :blk .{ .num = d / bv * 100 };
                        },
                    };
                }
                r[w - 2] = .{ .str = switch (kind) {
                    0 => "BASE",
                    1 => "COMP",
                    2 => "DIF",
                    else => "PCT",
                } };
                r[w - 1] = .{ .num = obs };
                try o.appendRow(r);
            }
        }
        try lib.put(on, o);
    }

    try out.appendSlice(arena, "\n" ++ " " ** 26 ++ "The COMPARE Procedure\n");
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  Comparison of {s} with {s}\n\n", .{ b.name, c.name }));
    // Summary reports — suppressed by NOSUMMARY / BRIEF (NOTE-compareoptsnoop).
    // BRIEF is NOSUMMARY in the compact report: our value section is already the
    // one-line-per-diff short form BRIEF would produce, so both leave only the
    // header + value differences.
    if (!b_nosummary and !b_brief) {
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  Data Set Summary\n    {s}: {d} variables, {d} observations\n    {s}: {d} variables, {d} observations\n\n", .{ b.name, b.columns.items.len, nb, c.name, c.columns.items.len, nc }));
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  Variables Summary\n    Variables in common: {d}\n    In {s} only: {d}\n    In {s} only: {d}\n", .{ common_vars, b.name, base_only, c.name, comp_only }));
        if (type_mism.items.len > 0)
            try out.appendSlice(arena, try std.fmt.allocPrint(arena, "    Conflicting types (not compared): {d}\n", .{type_mism.items.len}));
        try out.appendSlice(arena, "\n");
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  Observation Summary\n    Observations in common: {d}\n    In {s} only: {d}\n    In {s} only: {d}\n\n", .{ obs_common, b.name, obs_base_only, c.name, obs_comp_only }));
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  Values Comparison Summary\n    Variables compared: {d}\n    Variables all equal: {d}\n    Variables with unequal values: {d}\n    Total unequal values: {d}\n", .{ cols.items.len, cols.items.len - vars_unequal, vars_unequal, total_unequal }));
        if (type_mism.items.len > 0) {
            var names: std.ArrayList(u8) = .empty;
            for (type_mism.items, 0..) |nm, k| {
                if (k > 0) try names.appendSlice(arena, ", ");
                try names.appendSlice(arena, nm);
            }
            try out.appendSlice(arena, try std.fmt.allocPrint(arena, "  NOTE: {d} variable(s) not compared — type differs between base and compare: {s}\n", .{ type_mism.items.len, names.items }));
        }
    }

    if (total_unequal == 0) {
        try out.appendSlice(arena, "\n  NOTE: No unequal values were found. All values compared are exactly equal.\n");
        return;
    }
    // per-difference detail: which observation (by ID key, or obs number) and
    // variable differ, with the base vs compare value. Suppressed by NOVALUES —
    // the summaries still report the counts (NOTE-compareoptsnoop).
    if (b_novalues) return;
    try out.appendSlice(arena, "\n  Value Comparison Results\n\n");
    for (diffs.items) |d| {
        const key = if (use_id) blk: {
            var kb: std.ArrayList(u8) = .empty;
            for (idlist.items, id_bi.items) |nm, bi| {
                if (kb.items.len > 0) try kb.append(arena, ' ');
                try kb.appendSlice(arena, try std.fmt.allocPrint(arena, "{s}={s}", .{ nm, try cellText(arena, b.row(d.p.br)[bi]) }));
            }
            break :blk kb.items;
        } else try std.fmt.allocPrint(arena, "Obs {d}", .{d.p.br + 1});
        const vdisp = if (eqi(d.col.name, d.col.cname)) d.col.name else try std.fmt.allocPrint(arena, "{s} with {s}", .{ d.col.name, d.col.cname });
        try out.appendSlice(arena, try std.fmt.allocPrint(arena, "    {s}  {s}: base={s} compare={s}\n", .{
            key,
            vdisp,
            try cellText(arena, b.row(d.p.br)[d.col.bi]),
            try cellText(arena, c.row(d.p.cr)[d.col.ci]),
        }));
    }
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "\n  NOTE: {d} unequal values found across {d} variable(s).\n", .{ total_unequal, vars_unequal }));
}

// ── PROC TABULATE ──────────────────────────────────────────────────────────

/// The one TABULATE shape the corpus pins: `class R; var V; table R, V*STAT;`
/// — one class variable down the rows, one analysis variable × one statistic
/// across a single data column, drawn as a boxed table.
/// ponytail: exactly this shape — no nested/crossed dimensions, multiple stats,
/// `ALL`, or cell formats. Grow when a fixture needs it.
pub fn runTabulate(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var in_name: ?[]const u8 = null;
    var proc_fmt: ?[]const u8 = null; // proc-level `format=8.2` — default cell format (GAP-tabformat)
    var missing_opt = false; // MISSING: keep obs with a missing CLASS value (BUG-tabulatemissclass)
    var class_order: GroupOrder = .internal; // ORDER=INTERNAL|FORMATTED|DATA|FREQ (GAP-tabulateopts)
    var var_labels: std.ArrayList(NameLabel) = .empty; // LABEL stmt — variable header text (GAP-tabulateopts)
    var key_labels: std.ArrayList(NameLabel) = .empty; // KEYLABEL stmt — statistic-keyword header text
    var i: usize = 2; // past `proc tabulate`
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAt(toks, i, "data")) |v| {
            in_name = v;
            i += 3;
        } else if (tkKw(toks[i], "format") and atTag(toks, i + 1, .eq)) {
            const end = fmtSpecEnd(toks, i + 2);
            if (end > i + 2) proc_fmt = try joinFmt(arena, toks[i + 2 .. end]);
            i = end;
        } else if (tkKw(toks[i], "missing")) {
            missing_opt = true;
            i += 1;
        } else if (tkKw(toks[i], "order") and atTag(toks, i + 1, .eq) and i + 2 < toks.len and toks[i + 2].tag == .name) {
            // ORDER=INTERNAL|FORMATTED|DATA|FREQ — the CLASS level order
            // (GAP-tabulateopts); was silently ignored. A bad value fails loud.
            const v = toks[i + 2].text;
            if (eqi(v, "internal")) class_order = .internal //
            else if (eqi(v, "formatted")) class_order = .formatted //
            else if (eqi(v, "data")) class_order = .data //
            else if (eqi(v, "freq")) class_order = .freq //
            else {
                unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: ORDER={s} is not valid — expected INTERNAL, FORMATTED, DATA, or FREQ", .{v}));
                return;
            }
            i += 3;
        } else if (tkKw(toks[i], "order") and atTag(toks, i + 1, .eq)) {
            // `order=;` with NO value fell to the catch-all and was silently
            // ignored (NOTE-tabulateorderempty) — fail loud, like a bad value.
            unsupported("PROC TABULATE: ORDER= requires a value (DATA/FREQ/FORMATTED/INTERNAL)");
            return;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // data=d(where=/keep=/…) dataset options — applied via procInput
        } else if (toks[i].tag == .name) {
            // D-002 fail-loud (GAP-tabprocopt): an unknown proc option (NOSEPS,
            // FORMCHAR=, a typo, …) used to fall through here and vanish silently
            // — a swallowed option changes expected output. Error visibly, mirroring
            // the SORT header + the TABLE `/`-option fail-loud.
            unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: proc option {s} is not supported yet", .{toks[i].text}));
            return;
        } else i += 1; // stray punctuation
    }
    if (atTag(toks, i, .semicolon)) i += 1;

    var classes: std.ArrayList([]const u8) = .empty; // CLASS vars — tell a class column from an analysis one
    var miss_classes: std.ArrayList([]const u8) = .empty; // class vars with `/ missing` — keep their missing level (BUG-tabulatemed)
    var class_orders: std.ArrayList(ClassOrder) = .empty; // per-class `/ order=` overrides (BUG-tabulatemed)
    var specs: std.ArrayList(TabSpec) = .empty; // one spec per TABLE statement — each renders its own table (BUG-tabulatemed)
    var bys: std.ArrayList([]const u8) = .empty; // `by v …;` — one table per BY group (BUG-tabulatebyfreq)
    var freq_var: ?[]const u8 = null; // `freq f;` — each obs counts trunc(f) times (BUG-tabulatebyfreq)
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run")) break;
        if (tkKw(toks[i], "class")) {
            i += 1;
            const c0 = classes.items.len; // the vars of THIS statement — `/` options apply to all of them
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .slash) {
                    // CLASS `/` options (BUG-tabulatemed): `/ missing` keeps the
                    // missing level of these vars (per-var proc-MISSING), `/ order=`
                    // overrides their level order. `/ mlf` (multilabel) and unknown
                    // options FAIL LOUD — they used to be silently swallowed as
                    // phantom class names (`missing`/`order`/`freq` "variables").
                    i += 1;
                    while (i < toks.len and toks[i].tag != .semicolon) {
                        if (toks[i].tag != .name) {
                            i += 1;
                            continue;
                        }
                        const nm = toks[i].text;
                        if (eqi(nm, "missing")) {
                            for (classes.items[c0..]) |cn| try miss_classes.append(arena, cn);
                            i += 1;
                        } else if (eqi(nm, "order") and atTag(toks, i + 1, .eq)) {
                            if (i + 2 >= toks.len or toks[i + 2].tag != .name) {
                                unsupported("PROC TABULATE: class option ORDER= requires a value (DATA/FREQ/FORMATTED/INTERNAL)");
                                return;
                            }
                            const v = toks[i + 2].text;
                            const ord: GroupOrder = if (eqi(v, "internal")) .internal //
                            else if (eqi(v, "formatted")) .formatted //
                            else if (eqi(v, "data")) .data //
                            else if (eqi(v, "freq")) .freq //
                            else {
                                unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: class option ORDER={s} is not valid — expected INTERNAL, FORMATTED, DATA, or FREQ", .{v}));
                                return;
                            };
                            for (classes.items[c0..]) |cn| try class_orders.append(arena, .{ .name = cn, .order = ord });
                            i += 3;
                        } else if (eqi(nm, "mlf")) {
                            unsupported("PROC TABULATE: class option MLF (multilabel) is not supported");
                            return;
                        } else {
                            unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: class option {s} is not supported yet", .{nm}));
                            return;
                        }
                    }
                    break;
                }
                if (toks[i].tag == .name) try appendVarListName(arena, toks, &i, &classes); // GAP-varcolonprefix-procs: keep `pfx:`
            }
        } else if (tkKw(toks[i], "table")) {
            i += 1;
            const ts = i;
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
            // Fresh accumulators per TABLE statement (BUG-tabulatemed #5): they
            // used to share one set, so a later table with no new row var
            // silently MERGED into the first instead of rendering separately.
            var spec = TabSpec{};
            if (!try parseTable(arena, diags, toks[ts..i], &spec, classes.items)) return; // failed loud already
            try specs.append(arena, spec);
        } else if (tkKw(toks[i], "label") or tkKw(toks[i], "keylabel")) {
            // LABEL v='…' / KEYLABEL kw='…' — header text for the named variable /
            // statistic keyword (GAP-tabulateopts); both were silently ignored.
            // A bare name RESETS the heading to the default — already our default.
            const into = if (tkKw(toks[i], "keylabel")) &key_labels else &var_labels;
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) {
                if (toks[i].tag == .name and atTag(toks, i + 1, .eq) and i + 2 < toks.len and toks[i + 2].tag == .string) {
                    try into.append(arena, .{ .name = toks[i].text, .text = toks[i + 2].text });
                    i += 3;
                } else i += 1;
            }
        } else if (tkKw(toks[i], "by")) {
            try parseProcBy(arena, diags, toks, &i, &bys); // one table per BY group (BUG-tabulatebyfreq)
        } else if (tkKw(toks[i], "freq")) {
            i += 1; // `freq f;` — the frequency-count variable (BUG-tabulatebyfreq)
            while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
                if (toks[i].tag == .name) freq_var = toks[i].text;
            }
        } else i += 1; // var list informs nothing the TABLE stmt doesn't
        if (atTag(toks, i, .semicolon)) i += 1;
    }

    const raw = (if (in_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC TABULATE: no input dataset");
        return;
    };
    var ds = try procInput(arena, raw, toks, diags); // WHERE stmt / data= options (BUG-procwhere)
    // FREQ f: each obs counts trunc(f) times (missing/<1 dropped). Expand once so
    // every cell/N/SUM sees the frequency-expanded sample (BUG-tabulatebyfreq),
    // exactly as PROC MEANS does. Distinct from WEIGHT (fractional, handled below).
    if (freq_var) |fv| {
        const fcol = ds.indexOf(fv) orelse
            return diags.fail(error.ParseError, 0, "PROC TABULATE: FREQ variable {s} not in {s}", .{ fv, ds.name });
        ds = try expandFreq(arena, diags, ds, fcol);
    }
    // GAP-varcolonprefix-procs: expand `pfx:` entries in the CLASS list now
    // that the dataset is known (PDV order — see expandVarPrefixes). ONE
    // point, ahead of the miss-class filter and every render-time lookup;
    // parseTable ran pre-dataset, so IT matched class names against the wire
    // form (nameOrPrefixListed).
    try expandVarListPrefixes(arena, ds, &classes, diags, toks[0].line, "PROC TABULATE");
    // BUG-tabulatemissclass: SAS excludes obs with a missing value on ANY class
    // variable from the whole table (cells AND pctn/pctsum denominators) unless
    // the MISSING option — the same once-up-front filter MEANS/FREQ use. Applies
    // to the cross path too: runTabulateCross receives this filtered view.
    if (!missing_opt and classes.items.len > 0) {
        var ccols: std.ArrayList(usize) = .empty;
        for (classes.items) |cn| {
            // `/ missing` copied the PRE-expansion entry — a `pfx:` there
            // covers every var it expanded to (nameOrPrefixListed).
            if (nameOrPrefixListed(miss_classes.items, cn)) continue; // `/ missing`: keep this var's missing level (BUG-tabulatemed)
            if (ds.indexOf(cn)) |idx| try ccols.append(arena, idx);
        }
        if (ccols.items.len > 0) ds = try dropMissingClass(arena, ds, ccols.items);
    }
    if (specs.items.len == 0) return unsupported("PROC TABULATE: no TABLE row variable");
    // Validate every TABLE's row var up front — the same errors, in the same
    // order, as the old single-table path, never after a printed BY line.
    for (specs.items) |*spec| {
        // GAP-tabulateforms #8: an ALL-only row dimension (`table all, v*sum`)
        // is documented (p.2547: two dimensions → rows, columns; ALL is a
        // dimension element) — one grand-total row. Anything else row-less
        // stays loud.
        if (spec.row_var == null and !spec.row_all) return unsupported("PROC TABULATE: no TABLE row variable");
        if (spec.row_var) |rv| {
            if (ds.indexOf(rv) == null) return unsupported("PROC TABULATE: row variable not found");
        }
    }

    // BY groups (BUG-tabulatebyfreq): one table per group over the SORTED input,
    // exactly like PROC MEANS. No BY → one null-rep slice over all rows, so the
    // dispatch below is byte-identical to the pre-BY single-table path. Every
    // TABLE statement renders per group — each its own table (BUG-tabulatemed #5).
    var obcols: std.ArrayList(usize) = .empty;
    const pb = try decodeProcBy(arena, bys.items); // GAP-procbydescending: clean names + directions
    for (pb.names) |bn|
        try obcols.append(arena, ds.indexOf(bn) orelse return unsupported("PROC TABULATE: BY variable not found"));
    // BY demands sorted data (SAS errors otherwise) — a backward step between
    // contiguous groups is the tell (mirrors TRANSPOSE's SET/BY guard), per key
    // under BY DESCENDING; BY NOTSORTED drops the check (Statements ref p.41).
    if (obcols.items.len > 0 and !pb.notsorted) {
        const rows = ds.rows.items;
        var s: usize = 0;
        while (s < rows.len) {
            var e = s + 1;
            while (e < rows.len and byEqual(rows[s], rows[e], obcols.items)) e += 1;
            if (e < rows.len) if (byOrderViolation(rows[e], rows[s], obcols.items, pb.desc)) |k|
                return diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (pb.desc[k]) "descending" else "ascending" });
            s = e;
        }
    }
    for (try bySlices(arena, ds.rows.items, obcols.items)) |bs| {
        if (bs.rep) |r| try appendByLine(arena, out, ds, r, obcols.items);
        const gds = if (obcols.items.len == 0) ds else try subsetRows(arena, ds, bs.rows);
        for (specs.items) |*spec| {
            const rname: ?[]const u8 = spec.row_var; // null = an ALL-only row dimension (GAP-tabulateforms #8)
            const ridx: ?usize = if (spec.row_var) |rv| ds.indexOf(rv).? else null; // gds shares ds's columns — same index
            // LABEL/KEYLABEL header text (GAP-tabulateopts) — display only; dataset
            // lookups keep the real variable names. A TABLE *f= wins over FORMAT=.
            // Inline TABLE `elem='label'` (BUG-tabinlinelabel) wins over LABEL/KEYLABEL
            // for THIS table: prepend the per-spec overrides so labelFor's first-match
            // returns them. No inline labels → merged list == proc list, byte-identical.
            var mvar: std.ArrayList(NameLabel) = .empty;
            try mvar.appendSlice(arena, spec.inline_labels.items);
            try mvar.appendSlice(arena, var_labels.items);
            var mkey: std.ArrayList(NameLabel) = .empty;
            if (spec.all_label) |al| try mkey.append(arena, .{ .name = "all", .text = al });
            try mkey.appendSlice(arena, key_labels.items);
            const dress = TabOpts{ .order = class_order, .var_labels = mvar.items, .key_labels = mkey.items, .box_text = spec.box_text, .class_orders = class_orders.items };
            const cell_fmt = spec.table_fmt orelse proc_fmt;
            if (spec.col_class) |cc|
                try runTabulateCross(arena, out, gds, rname, ridx, cc, spec.blocks.items, spec.row_all, cell_fmt, dress)
            else
                try runTabulateSingle(arena, out, gds, rname, ridx, spec.blocks.items, spec.row_all, cell_fmt, dress);
        }
    }
}

/// A shallow copy of `ds` restricted to `rows` (columns + row pointers shared,
/// cells untouched) so a BY-group slice can be handed to the per-table renderers
/// without disturbing the library dataset — mirrors dropMissingClass.
fn subsetRows(arena: std.mem.Allocator, ds: *Dataset, rows: []const []const Value) !*Dataset {
    const copy = try arena.create(Dataset);
    copy.* = Dataset.init(arena, ds.name);
    for (ds.columns.items) |c| try copy.columns.append(arena, c);
    for (rows) |r| try copy.rows.append(arena, r);
    return copy;
}

/// One TABULATE table: rows are the `rname` class levels; the column dimension
/// is the parsed block list — one block per concatenated segment, each with its
/// own analysis variable and statistics (GAP-tabulateforms #7), plus at most
/// one ALL subtotal block. Split out of runTabulate so BUG-tabulatebyfreq can
/// render it once per BY group.
fn runTabulateSingle(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, rname: ?[]const u8, ridx: ?usize, blocks: []const TabBlock, row_all: bool, cell_fmt: ?[]const u8, dress: TabOpts) diag.Error!void {
    const rname_d: []const u8 = if (rname) |rn| labelFor(dress.var_labels, rn) orelse rn else "";
    const all_text = labelFor(dress.key_labels, "all") orelse "All"; // KEYLABEL all='…'

    // per-block resolution: the analysis-var column index (null = var-less),
    // the heading text, the grand-total Stats (pctn/pctsum denominator + ALL row).
    const nblocks = blocks.len;
    const bidx = try arena.alloc(?usize, nblocks);
    const blabel = try arena.alloc([]const u8, nblocks);
    const grands = try arena.alloc(Stats, nblocks);
    var ncols: usize = 0;
    var any_heading = false; // a block with heading text → the block-name header row shows
    for (blocks, 0..) |b, bi| {
        bidx[bi] = if (b.variable) |v| (ds.indexOf(v) orelse return unsupported("PROC TABULATE: analysis variable not found")) else null;
        blabel[bi] = if (b.is_all) all_text else if (b.variable) |v| labelFor(dress.var_labels, v) orelse v else "";
        if (blabel[bi].len > 0) any_heading = true;
        grands[bi] = if (bidx[bi]) |ai| computeStats(ds.rows.items, ai, null) else undefined;
        ncols += b.stats.items.len;
    }

    // group the rows by class value, keeping the full per-group row list so we
    // can compute the *requested* statistic (not just a running sum).
    // The CLASS index keys every row into its group — out-of-range = the whole
    // table grouped on a wrong cell, silently (TASTE-asserts).
    var keys: std.ArrayList([]const u8) = .empty;
    var groups: std.ArrayList(std.ArrayList([]const Value)) = .empty;
    if (ridx) |ri| {
        assert(ri < ds.columns.items.len);
        for (ds.rows.items) |row| {
            const key = switch (row[ri]) {
                .str => |s| std.mem.trimEnd(u8, s, " "),
                .num => |x| try tabNum(arena, x),
            };
            var hit = false;
            for (keys.items, 0..) |k, idx| if (eqi(k, key)) {
                try groups.items[idx].append(arena, row);
                hit = true;
                break;
            };
            if (!hit) {
                try keys.append(arena, key);
                var g: std.ArrayList([]const Value) = .empty;
                try g.append(arena, row);
                try groups.append(arena, g);
            }
        }
    } else {
        // GAP-tabulateforms #8: the row dimension is ALL alone — one
        // grand-total row over the whole table.
        try keys.append(arena, all_text);
        var g: std.ArrayList([]const Value) = .empty;
        for (ds.rows.items) |row| try g.append(arena, row);
        try groups.append(arena, g);
    }

    // value matrix: vals[group][column] — the columns are the blocks in
    // source order, each block's own statistics side by side (#7).
    var vals: std.ArrayList([]f64) = .empty;
    for (groups.items) |g| {
        const rowv = try arena.alloc(f64, ncols);
        try tabSingleVals(arena, blocks, bidx, grands, rname, g.items, ds.rows.items.len, rowv);
        try vals.append(arena, rowv);
    }

    // order class values (GAP-tabulateopts ORDER=): INTERNAL = numerically when the
    // class is numeric (BUG-tabnumorder: MEANS orders 1,2,10 numerically — TABULATE
    // must too, not lexical 1,10,2), FORMATTED = the display string, DATA = first
    // appearance (grouping appended in order), FREQ = descending group size. The
    // insertion sort is stable, so FREQ ties keep first-appearance order. Parallel
    // arrays keys/vals/nums/groups move together.
    const rnum = ridx != null and ds.columns.items[ridx.?].type == .num;
    const nums = try arena.alloc(f64, keys.items.len);
    if (rnum) for (groups.items, 0..) |g, gi| {
        nums[gi] = g.items[0][ridx.?].num;
    };
    const row_order = orderFor(dress.class_orders, rname orelse "") orelse dress.order; // a CLASS `/ order=` beats the proc ORDER= (BUG-tabulatemed)
    var m: usize = 1;
    while (row_order != .data and m < keys.items.len) : (m += 1) {
        var j = m;
        while (j > 0 and switch (row_order) {
            .data => unreachable,
            .freq => groups.items[j].items.len > groups.items[j - 1].items.len,
            .internal => if (rnum) tabNumLess(nums[j], nums[j - 1]) else std.mem.order(u8, keys.items[j - 1], keys.items[j]) == .gt,
            .formatted => std.mem.order(u8, keys.items[j - 1], keys.items[j]) == .gt,
        }) : (j -= 1) {
            std.mem.swap([]const u8, &keys.items[j - 1], &keys.items[j]);
            std.mem.swap([]f64, &vals.items[j - 1], &vals.items[j]);
            std.mem.swap(f64, &nums[j - 1], &nums[j]);
            std.mem.swap(std.ArrayList([]const Value), &groups.items[j - 1], &groups.items[j]);
        }
    }

    // ALL grand-total row (BUG-tabulateall): every block over the whole table —
    // appended after the sort so it stays last; its pctn/pctsum are 100 by
    // construction. (An ALL-ONLY row dimension — #8 — already drew that row as
    // its single group above; appending again would double it.)
    if (row_all and ridx != null) {
        try keys.append(arena, all_text);
        const rowv = try arena.alloc(f64, ncols);
        try tabSingleVals(arena, blocks, bidx, grands, rname, ds.rows.items, ds.rows.items.len, rowv);
        try vals.append(arena, rowv);
    }

    // widths
    var w1: usize = rname_d.len; // row-label column
    for (keys.items) |k| w1 = @max(w1, k.len);
    if (dress.box_text) |b| w1 = @max(w1, b.len); // the corner box shares the column
    w1 += 2;
    const labels = try arena.alloc([]const u8, ncols);
    const wcol = try arena.alloc(usize, ncols);
    {
        var f: usize = 0;
        for (blocks) |b| for (b.stats.items) |kw| {
            labels[f] = labelFor(dress.key_labels, kw) orelse try capFirst(arena, kw); // "mean" → "Mean", or KEYLABEL text
            var w = labels[f].len;
            for (vals.items) |rowv| w = @max(w, (try tabCell(arena, rowv[f], cell_fmt)).len);
            wcol[f] = w + 2;
            f += 1;
        };
    }
    var data_w: usize = ncols - 1; // the internal `|` separators
    for (wcol) |w| data_w += w;
    // each block's span fits its heading (the analysis var's name or the ALL
    // text), widening the block's last column when it doesn't — for one block
    // of one stat this reproduces the old `w2 = max(cname, label, values) + 2`.
    const bwidth = try arena.alloc(usize, nblocks);
    {
        var off: usize = 0;
        for (blocks, 0..) |b, bi| {
            var bw: usize = b.stats.items.len - 1;
            for (wcol[off .. off + b.stats.items.len]) |w| bw += w;
            const need = blabel[bi].len + 2;
            if (bw < need) {
                const deficit = need - bw;
                wcol[off + b.stats.items.len - 1] += deficit;
                bw += deficit;
                data_w += deficit;
            }
            bwidth[bi] = bw;
            off += b.stats.items.len;
        }
    }

    const total_w = 1 + w1 + 1 + data_w + 1;
    try boxRule(arena, out, total_w);
    // header row 1: the block headings (analysis var / ALL text) spanning their
    // stat columns; the corner cell holds the `/ box='…'` text when given
    // (GAP-tabulateopts). Skipped when NO block carries a heading (a stat-only
    // table like `table a, n` — GAP-tabulateforms #9).
    if (any_heading) {
        const corner = dress.box_text orelse "";
        var h1: std.ArrayList(Cell) = .empty;
        try h1.append(arena, .{ .text = corner, .w = w1, .al = .left });
        for (blocks, 0..) |_, bi| try h1.append(arena, .{ .text = blabel[bi], .w = bwidth[bi], .al = .center });
        try boxRowN(arena, out, h1.items);
    }
    // header row 2: one statistic label per column
    var hdr: std.ArrayList(Cell) = .empty;
    try hdr.append(arena, .{ .text = "", .w = w1, .al = .left });
    for (labels, 0..) |lb, si| try hdr.append(arena, .{ .text = lb, .w = wcol[si], .al = .center });
    try boxRowN(arena, out, hdr.items);
    // separator
    var seps: std.ArrayList(usize) = .empty;
    try seps.append(arena, w1);
    for (wcol) |w| try seps.append(arena, w);
    try boxSepN(arena, out, seps.items);
    // row-label header (blank data cells)
    var rlab: std.ArrayList(Cell) = .empty;
    try rlab.append(arena, .{ .text = rname_d, .w = w1, .al = .left });
    for (wcol) |w| try rlab.append(arena, .{ .text = "", .w = w, .al = .left });
    try boxRowN(arena, out, rlab.items);
    // data rows
    for (keys.items, vals.items) |k, rowv| {
        var cells: std.ArrayList(Cell) = .empty;
        try cells.append(arena, .{ .text = k, .w = w1, .al = .left });
        for (rowv, 0..) |v, si| try cells.append(arena, .{ .text = try tabCell(arena, v, cell_fmt), .w = wcol[si], .al = .rmargin });
        try boxRowN(arena, out, cells.items);
    }
    try boxRule(arena, out, total_w);
}

/// One data row of the 1-way table (GAP-tabulateforms #7): every block's own
/// statistics over `rows` — a class-level slice, or the whole table for the
/// ALL row (so the ALL row and an ALL block are row-restricted by
/// construction, BUG-tabulatemed #4). `grands[bi]` is the block's grand-total
/// Stats, the default pctn/pctsum denominator. A var-less block (a bare `all`
/// subtotal — default N, p.2547) takes the frequency path and never reads an
/// analysis column.
fn tabSingleVals(arena: std.mem.Allocator, blocks: []const TabBlock, bidx: []const ?usize, grands: []const Stats, rname: ?[]const u8, rows: []const []const Value, total_rows: usize, rowv: []f64) diag.Error!void {
    var f: usize = 0;
    for (blocks, 0..) |b, bi| {
        if (bidx[bi]) |ai| {
            const s = computeStats(rows, ai, null);
            for (b.stats.items, 0..) |kw, si| {
                const dn: ?[]const u8 = if (si < b.denoms.items.len) b.denoms.items[si] else null;
                // an ALL-only row dimension (#8) has no row var a `<rowvar>`
                // clause could name — tabBasis1's "" never matches, so such a
                // clause hits its loud arm, exactly like a bogus denominator.
                const basis = (try tabBasis1(arena, dn, rname orelse "", s, grands[bi])) orelse return;
                rowv[f] = tabCellValue(kw, s, basis, rows.len) orelse return unsupported("PROC TABULATE: unknown statistic");
                f += 1;
            }
        } else {
            for (b.stats.items) |kw| {
                rowv[f] = tabCellFreq(kw, rows.len, total_rows) orelse return unsupported("PROC TABULATE: unknown statistic");
                f += 1;
            }
        }
    }
}

fn levelKey(arena: std.mem.Allocator, v: Value) ![]const u8 {
    return switch (v) {
        .str => |s| std.mem.trimEnd(u8, s, " "),
        .num => |x| try tabNum(arena, x),
    };
}

fn addUniqueKey(arena: std.mem.Allocator, list: *std.ArrayList([]const u8), key: []const u8) !void {
    for (list.items) |x| if (eqi(x, key)) return;
    try list.append(arena, key);
}

fn strLess(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.order(u8, x, y) == .lt;
}

/// Level ordering for TABULATE class dimensions: by underlying numeric value when
/// the class is numeric (parse the formatted key back), else lexical.
const LevelCtx = struct {
    num: bool,
    fn less(self: LevelCtx, x: []const u8, y: []const u8) bool {
        if (self.num) {
            // a missing level (".") sorts before every present value (BUG-tabulatemissclass)
            const xm = std.mem.eql(u8, x, ".");
            const ym = std.mem.eql(u8, y, ".");
            if (xm != ym) return xm;
            const fx = std.fmt.parseFloat(f64, x) catch return strLess({}, x, y);
            const fy = std.fmt.parseFloat(f64, y) catch return strLess({}, x, y);
            return fx < fy;
        }
        return std.mem.order(u8, x, y) == .lt;
    }
};

/// Case-insensitive string-key map context — TABULATE class levels dedup with
/// eqi, so the PERF-tabulatecross bucket maps must hash/compare the same way.
const CICtx = struct {
    pub fn hash(_: CICtx, k: []const u8) u64 {
        var h = std.hash.Wyhash.init(0);
        var buf: [64]u8 = undefined;
        var i: usize = 0;
        while (i < k.len) {
            const n = @min(buf.len, k.len - i);
            for (0..n) |j| buf[j] = std.ascii.toLower(k[i + j]);
            h.update(buf[0..n]);
            i += n;
        }
        return h.final();
    }
    pub fn eql(_: CICtx, a: []const u8, b: []const u8) bool {
        return std.ascii.eqlIgnoreCase(a, b);
    }
};

/// 2-way cross: rows are the `rname` class levels, columns are the `ccname`
/// class levels each holding the crossing block's statistics (or a count when
/// there is no analysis var), plus at most one trailing ALL subtotal block
/// carrying its OWN statistics (GAP-tabulateforms #7 — the old shared stat
/// list unioned `all*v*(…)`'s statistics into every class-level block and
/// rendered extra columns). Populates every cell — BUG-tabulatecross.
fn runTabulateCross(arena: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, rname: ?[]const u8, ridx: ?usize, ccname: []const u8, blocks: []const TabBlock, row_all: bool, cell_fmt: ?[]const u8, dress: TabOpts) diag.Error!void {
    const ccidx = ds.indexOf(ccname) orelse return unsupported("PROC TABULATE: column class variable not found");
    // parseTable's shape constraints guarantee exactly one crossing block plus
    // at most one ALL block here.
    var xb: TabBlock = undefined;
    var allb: ?TabBlock = null;
    for (blocks) |b| {
        if (b.is_all) allb = b else xb = b;
    }
    const aidx: ?usize = if (xb.variable) |an| (ds.indexOf(an) orelse return unsupported("PROC TABULATE: analysis variable not found")) else null;
    const aidx_all: ?usize = if (allb) |ab| (if (ab.variable) |an| (ds.indexOf(an) orelse return unsupported("PROC TABULATE: analysis variable not found")) else null) else null;
    // LABEL/KEYLABEL header text (GAP-tabulateopts) — display only.
    const rname_d: []const u8 = if (rname) |rn| labelFor(dress.var_labels, rn) orelse rn else "";
    const rname_s: []const u8 = rname orelse ""; // "" matches no <dim> denominator — an ALL-only row (#8) has no row var to name
    const ccname_d = labelFor(dress.var_labels, ccname) orelse ccname;
    const an_d: ?[]const u8 = if (xb.variable) |an| labelFor(dress.var_labels, an) orelse an else null;
    const an_all_d: ?[]const u8 = if (allb) |ab| (if (ab.variable) |an| labelFor(dress.var_labels, an) orelse an else null) else null;
    const all_text = labelFor(dress.key_labels, "all") orelse "All"; // KEYLABEL all='…'
    const stat_kws: []const []const u8 = xb.stats.items;
    const nstats = stat_kws.len;
    const astats: usize = if (allb) |ab| ab.stats.items.len else 0; // the ALL block's own stat count
    // without an analysis var only N/PCTN are computable — anything else must fail
    // loud, not silently render a frequency (or read an uninitialised cell).
    // (parseTable rejects those first with rc 1 — this is the unreachable backstop.)
    if (aidx == null) for (stat_kws) |kw| {
        if (!eqi(kw, "n") and !eqi(kw, "pctn")) return unsupported("PROC TABULATE: statistic requires an analysis variable");
    };
    if (allb != null and aidx_all == null) for (allb.?.stats.items) |kw| {
        if (!eqi(kw, "n") and !eqi(kw, "pctn")) return unsupported("PROC TABULATE: statistic requires an analysis variable");
    };
    const grand: Stats = if (aidx) |ai| computeStats(ds.rows.items, ai, null) else undefined; // pctn/pctsum denominator + ALL margins
    const grand_all: Stats = if (aidx_all) |ai| computeStats(ds.rows.items, ai, null) else undefined; // the ALL block's own denominator

    // distinct, sorted row & column levels (precompute each row's two keys once)
    const rk = try arena.alloc([]const u8, ds.rows.items.len);
    const ck = try arena.alloc([]const u8, ds.rows.items.len);
    var rkeys: std.ArrayList([]const u8) = .empty;
    var ckeys: std.ArrayList([]const u8) = .empty;
    for (ds.rows.items, 0..) |row, k| {
        rk[k] = if (ridx) |ri| try levelKey(arena, row[ri]) else all_text; // no row var: an ALL-only row (#8) — every row in the one group
        ck[k] = try levelKey(arena, row[ccidx]);
        try addUniqueKey(arena, &rkeys, rk[k]);
        try addUniqueKey(arena, &ckeys, ck[k]);
    }
    // numeric class levels order by value, not lexically (BUG-tabnumorder);
    // ORDER= DATA/FREQ/FORMATTED override (GAP-tabulateopts).
    const rnum = ridx != null and ds.columns.items[ridx.?].type == .num;
    const cnum = ds.columns.items[ccidx].type == .num;
    try orderLevels(arena, rkeys.items, rk, rnum, orderFor(dress.class_orders, rname orelse "") orelse dress.order);
    try orderLevels(arena, ckeys.items, ck, cnum, orderFor(dress.class_orders, ccname) orelse dress.order);
    // ALL grand-total row (BUG-tabulateall): a trailing "All" level that
    // matches every row — appended after sorting so it stays last. The ALL
    // column is no longer a level: it is the ALL block's own column group (#7).
    // (an ALL-ONLY row dimension — #8 — already keyed every row into the one
    // "All" group above; appending again would double the row.)
    const row_all_appended = row_all and ridx != null;
    if (row_all_appended) try rkeys.append(arena, all_text);
    const nr = rkeys.items.len;
    const nc = ckeys.items.len;
    const ndata = nc * nstats + astats; // (col-level × crossing stat) + the ALL block's own
    // BUG-tabulatezerocrash: 0 obs with no ALL block → no column levels, so
    // ndata==0 and the width pass below underflows (`ndata - 1` on usize →
    // SIGABRT). A cross with no columns has no table to draw; render nothing,
    // mirroring PROC FREQ's empty-input no-op. (an ALL block keeps ndata>=1,
    // so that 0-obs path renders unchanged.)
    if (ndata == 0) return;

    // PERF-tabulatecross: ONE pass buckets every row into its (ri, ci) cell — the
    // old nr×nc×N rescan is O(N·Ca·Cb) (quadratic in class cardinality: N=100k
    // C=200 → 38s, N=1M timed out). Buckets preserve row order, so computeStats
    // sees the exact same slice as the old per-cell `match` scan → byte-identical
    // output for every statistic. The trailing "All" level is handled by flags,
    // not the map, so a class level literally named "all" buckets exactly like
    // the old eqi scan. Keys built the level lists, so map lookups always hit.
    const CIMap = std.HashMap([]const u8, usize, CICtx, std.hash_map.default_max_load_percentage);
    var rmap = CIMap.init(arena);
    var cmap = CIMap.init(arena);
    for (rkeys.items[0 .. nr - @as(usize, @intFromBool(row_all_appended))], 0..) |k, ri| try rmap.put(k, ri);
    for (ckeys.items, 0..) |k, ci| try cmap.put(k, ci);
    const buckets = try arena.alloc(std.ArrayList([]const Value), nr * nc);
    for (buckets) |*b| b.* = .empty;
    // the ALL block's cells: one row-restricted slice per table row (the whole
    // table on the ALL row) — the old col_all bucket column, unknotted from
    // the level grid (#7). Skipped entirely without an ALL block so the
    // PERF-tabulatecross bucketing stays a single pass.
    const all_buckets = try arena.alloc(std.ArrayList([]const Value), if (allb != null) nr else 0);
    for (all_buckets) |*b| b.* = .empty;
    for (ds.rows.items, 0..) |row, k| {
        const ri = rmap.get(rk[k]).?;
        const ci = cmap.get(ck[k]).?;
        try buckets[ri * nc + ci].append(arena, row);
        if (row_all_appended) try buckets[(nr - 1) * nc + ci].append(arena, row);
        if (allb != null) {
            try all_buckets[ri].append(arena, row);
            if (row_all_appended) try all_buckets[nr - 1].append(arena, row);
        }
    }

    // GAP-tabdenom: a PCTN/PCTSUM `<dim>` clause divides each cell by the named
    // dimension's subtotal — `<rowvar>` = the row subtotal, `<colvar>` = the column
    // subtotal, `<all>` = the grand total (the no-clause default). The dimension
    // must be part of this TABLE's crossing (SAS errors otherwise); a bogus one
    // fails loud naming the denominator, never "unknown statistic". Row/column
    // member lists + their Stats are built once, on first use, and cached.
    var row_lists: ?[]std.ArrayList([]const Value) = null;
    var col_lists: ?[]std.ArrayList([]const Value) = null;
    var row_basis: ?[]?Stats = null;
    var col_basis: ?[]?Stats = null;
    for (blocks) |b| for (b.denoms.items) |dn| {
        const d = dn orelse continue;
        if (!eqi(d, "all") and !eqi(d, rname_s) and !eqi(d, ccname)) {
            unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: PCTN/PCTSUM denominator '{s}' is not a class variable in this TABLE's crossing", .{d}));
            return;
        }
        if (row_lists == null) {
            row_lists = try arena.alloc(std.ArrayList([]const Value), nr);
            col_lists = try arena.alloc(std.ArrayList([]const Value), nc);
            for (row_lists.?) |*l| l.* = .empty;
            for (col_lists.?) |*l| l.* = .empty;
            for (ds.rows.items, 0..) |row, k| {
                try row_lists.?[rmap.get(rk[k]).?].append(arena, row);
                try col_lists.?[cmap.get(ck[k]).?].append(arena, row);
                if (row_all_appended) try row_lists.?[nr - 1].append(arena, row);
            }
            row_basis = try arena.alloc(?Stats, nr);
            col_basis = try arena.alloc(?Stats, nc);
            for (row_basis.?) |*bb| bb.* = null;
            for (col_basis.?) |*bb| bb.* = null;
        }
    };

    // value grid vals[r][column]: the crossing block per (level × stat), then
    // the ALL block's own columns (#7).
    const vals = try arena.alloc([]f64, nr);
    for (0..nr) |ri| {
        vals[ri] = try arena.alloc(f64, ndata);
        for (0..nc) |ci| {
            const match = buckets[ri * nc + ci].items;
            if (aidx) |ai| {
                const s = computeStats(match, ai, null);
                for (stat_kws, 0..) |kw, si| {
                    var basis = grand; // no clause / `<all>` → grand-total denominator
                    if ((if (si < xb.denoms.items.len) xb.denoms.items[si] else null)) |d| {
                        if (eqi(d, rname_s)) {
                            if (row_basis.?[ri] == null) row_basis.?[ri] = computeStats(row_lists.?[ri].items, ai, null);
                            basis = row_basis.?[ri].?;
                        } else if (eqi(d, ccname)) {
                            if (col_basis.?[ci] == null) col_basis.?[ci] = computeStats(col_lists.?[ci].items, ai, null);
                            basis = col_basis.?[ci].?;
                        }
                    }
                    vals[ri][ci * nstats + si] = tabCellValue(kw, s, basis, match.len) orelse return unsupported("PROC TABULATE: unknown statistic");
                }
            } else for (stat_kws, 0..) |kw, si| {
                var dcnt: usize = ds.rows.items.len; // pctn basis: grand count
                if ((if (si < xb.denoms.items.len) xb.denoms.items[si] else null)) |d| {
                    if (eqi(d, rname_s)) dcnt = row_lists.?[ri].items.len else if (eqi(d, ccname)) dcnt = col_lists.?[ci].items.len;
                }
                vals[ri][ci * nstats + si] = tabCellFreq(kw, match.len, dcnt) orelse return unsupported("PROC TABULATE: unknown statistic");
            }
        }
        // the ALL block's own columns (a row-restricted slice — the cross-path
        // form of BUG-tabulatemed #4): its OWN statistics, never the crossing
        // block's (#7).
        if (allb) |ab| {
            const match = all_buckets[ri].items;
            if (aidx_all) |ai| {
                const s = computeStats(match, ai, null);
                for (ab.stats.items, 0..) |kw, si| {
                    var basis = grand_all;
                    if ((if (si < ab.denoms.items.len) ab.denoms.items[si] else null)) |d| {
                        if (eqi(d, rname_s)) {
                            basis = computeStats(row_lists.?[ri].items, ai, null); // one column: no basis cache needed
                        } else if (eqi(d, ccname)) {
                            basis = s; // the ALL column spans every column level — its own subtotal is the basis
                        }
                    }
                    vals[ri][nc * nstats + si] = tabCellValue(kw, s, basis, match.len) orelse return unsupported("PROC TABULATE: unknown statistic");
                }
            } else for (ab.stats.items, 0..) |kw, si| {
                var dcnt: usize = ds.rows.items.len;
                if ((if (si < ab.denoms.items.len) ab.denoms.items[si] else null)) |d| {
                    if (eqi(d, rname_s)) dcnt = row_lists.?[ri].items.len else if (eqi(d, ccname)) dcnt = match.len;
                }
                vals[ri][nc * nstats + si] = tabCellFreq(kw, match.len, dcnt) orelse return unsupported("PROC TABULATE: unknown statistic");
            }
        }
    }

    // widths: row-label column, then one width per data column, widened so each
    // level label / the class name fits over its span.
    var w1: usize = rname_d.len;
    for (rkeys.items) |k| w1 = @max(w1, k.len);
    if (dress.box_text) |b| w1 = @max(w1, b.len); // the corner box shares the column
    w1 += 2;
    const labels = try arena.alloc([]const u8, ndata);
    const wcol = try arena.alloc(usize, ndata);
    for (0..ndata) |f| {
        labels[f] = if (f < nc * nstats)
            (labelFor(dress.key_labels, stat_kws[f % nstats]) orelse try capFirst(arena, stat_kws[f % nstats]))
        else
            (labelFor(dress.key_labels, allb.?.stats.items[f - nc * nstats]) orelse try capFirst(arena, allb.?.stats.items[f - nc * nstats]));
        var w = labels[f].len;
        for (0..nr) |ri| w = @max(w, (try tabCell(arena, vals[ri][f], cell_fmt)).len);
        wcol[f] = w + 2;
    }
    // per-level block must fit the level label and (if any) the analysis-var name
    const need_block = if (an_d) |an| @max(an.len, blk: {
        var m: usize = 0;
        for (ckeys.items) |c| m = @max(m, c.len);
        break :blk m;
    }) else blk: {
        var m: usize = 0;
        for (ckeys.items) |c| m = @max(m, c.len);
        break :blk m;
    };
    for (0..nc) |ci| {
        var bw: usize = nstats - 1;
        for (0..nstats) |si| bw += wcol[ci * nstats + si];
        if (bw < need_block) wcol[ci * nstats + nstats - 1] += need_block - bw; // widen the block's last col
    }
    // the ALL block's span fits its own headings (the ALL text / its var name)
    if (allb != null) {
        var need_all: usize = all_text.len;
        if (an_all_d) |an| need_all = @max(need_all, an.len);
        var bw: usize = astats - 1;
        for (0..astats) |si| bw += wcol[nc * nstats + si];
        if (bw < need_all) wcol[nc * nstats + astats - 1] += need_all - bw;
    }
    // total data width, widened so the column-class name fits across all of it
    var data_w: usize = ndata - 1;
    for (wcol) |w| data_w += w;
    if (data_w < ccname_d.len) {
        wcol[ndata - 1] += ccname_d.len - data_w;
        data_w = ccname_d.len;
    }
    const blockW = try arena.alloc(usize, nc + @as(usize, @intFromBool(allb != null))); // final per-level span + the ALL span
    for (0..nc) |ci| {
        var bw: usize = nstats - 1;
        for (0..nstats) |si| bw += wcol[ci * nstats + si];
        blockW[ci] = bw;
    }
    if (allb != null) {
        var bw: usize = astats - 1;
        for (0..astats) |si| bw += wcol[nc * nstats + si];
        blockW[nc] = bw;
    }

    const total_w = 1 + w1 + 1 + data_w + 1;
    try boxRule(arena, out, total_w);
    // header 1: the column-class variable, spanning all data columns; the corner
    // cell holds the `/ box='…'` text when given (GAP-tabulateopts).
    try boxRowN(arena, out, &.{ .{ .text = dress.box_text orelse "", .w = w1, .al = .left }, .{ .text = ccname_d, .w = data_w, .al = .center } });
    // header 2: each column level, spanning its stat columns, then the ALL block
    var h2: std.ArrayList(Cell) = .empty;
    try h2.append(arena, .{ .text = "", .w = w1, .al = .left });
    for (ckeys.items, 0..) |c, ci| try h2.append(arena, .{ .text = c, .w = blockW[ci], .al = .center });
    if (allb != null) try h2.append(arena, .{ .text = all_text, .w = blockW[nc], .al = .center });
    try boxRowN(arena, out, h2.items);
    // header 3 (only with an analysis var): its name, per level block / the ALL block
    if (an_d != null or an_all_d != null) {
        var h3: std.ArrayList(Cell) = .empty;
        try h3.append(arena, .{ .text = "", .w = w1, .al = .left });
        for (0..nc) |ci| try h3.append(arena, .{ .text = an_d orelse "", .w = blockW[ci], .al = .center });
        if (allb != null) try h3.append(arena, .{ .text = an_all_d orelse "", .w = blockW[nc], .al = .center });
        try boxRowN(arena, out, h3.items);
    }
    // header 4: the statistic label per data column
    var h4: std.ArrayList(Cell) = .empty;
    try h4.append(arena, .{ .text = "", .w = w1, .al = .left });
    for (0..ndata) |f| try h4.append(arena, .{ .text = labels[f], .w = wcol[f], .al = .center });
    try boxRowN(arena, out, h4.items);
    // separator, then the row-variable header (blank data cells)
    var seps: std.ArrayList(usize) = .empty;
    try seps.append(arena, w1);
    for (wcol) |w| try seps.append(arena, w);
    try boxSepN(arena, out, seps.items);
    var rlab: std.ArrayList(Cell) = .empty;
    try rlab.append(arena, .{ .text = rname_d, .w = w1, .al = .left });
    for (wcol) |w| try rlab.append(arena, .{ .text = "", .w = w, .al = .left });
    try boxRowN(arena, out, rlab.items);
    // data rows
    for (rkeys.items, 0..) |rkey, ri| {
        var cells: std.ArrayList(Cell) = .empty;
        try cells.append(arena, .{ .text = rkey, .w = w1, .al = .left });
        for (0..ndata) |f| try cells.append(arena, .{ .text = try tabCell(arena, vals[ri][f], cell_fmt), .w = wcol[f], .al = .rmargin });
        try boxRowN(arena, out, cells.items);
    }
    try boxRule(arena, out, total_w);
}

/// A LABEL/KEYLABEL `name='text'` pair (GAP-tabulateopts).
const NameLabel = struct { name: []const u8, text: []const u8 };

/// Header-text override for a variable (LABEL) or a statistic keyword
/// (KEYLABEL, incl. `all`); null = the default heading.
fn labelFor(list: []const NameLabel, name: []const u8) ?[]const u8 {
    for (list) |nl| if (eqi(nl.name, name)) return nl.text;
    return null;
}

/// Ordering/cosmetic knobs shared by both TABULATE render paths (GAP-tabulateopts):
/// the ORDER= class-level order, LABEL/KEYLABEL header text, `/ box=` corner text.
const TabOpts = struct {
    order: GroupOrder = .internal,
    var_labels: []const NameLabel = &.{},
    key_labels: []const NameLabel = &.{},
    box_text: ?[]const u8 = null,
    class_orders: []const ClassOrder = &.{},
};

/// One column-dimension BLOCK of a TABLE statement (GAP-tabulateforms #7):
/// the concatenation (blank) operator splits the column expression into
/// segments, and each segment renders as ONE block with its OWN analysis
/// variable and statistics — Base SAS 9.4 Procedures Guide printed p.2548
/// (pdf 2597), the blank operator "places the output for each element
/// immediately after the output for the preceding element". The old flat
/// stats list unioned every segment's statistics onto the LAST analysis
/// variable: `table r, a*sum b*mean` rendered b×(Sum,Mean) — an extra,
/// unrequested column and a silently dropped one. `variable == null` is a
/// var-less block (N/PCTN only, p.2548's restriction); `is_all` marks the
/// universal class variable ALL crossed into the segment (a subtotal block,
/// p.2547) — rendered like any other block (the row-crossing restricts it),
/// only its heading is the ALL text.
const TabBlock = struct {
    variable: ?[]const u8 = null,
    stats: std.ArrayList([]const u8) = .empty,
    denoms: std.ArrayList(?[]const u8) = .empty, // parallel to stats
    is_all: bool = false,
};

/// One parsed TABLE statement: row var (+ALL), optional column class (2-way
/// cross), the column blocks (one per concatenated segment), cell format,
/// corner box. runTabulate renders one table per spec — SAS emits each TABLE
/// statement as a SEPARATE table (BUG-tabulatemed #5); the old shared
/// accumulator silently merged them.
const TabSpec = struct {
    row_var: ?[]const u8 = null,
    col_class: ?[]const u8 = null,
    blocks: std.ArrayList(TabBlock) = .empty,
    row_all: bool = false,
    table_fmt: ?[]const u8 = null,
    box_text: ?[]const u8 = null,
    inline_labels: std.ArrayList(NameLabel) = .empty, // TABLE `r='Region'` — per-table var header text; wins over LABEL (BUG-tabinlinelabel)
    all_label: ?[]const u8 = null, // TABLE `all='Total'` — inline grand-total heading (BUG-tabinlinelabel)
};

/// A per-class `/ order=` override from a CLASS statement (BUG-tabulatemed #6).
const ClassOrder = struct { name: []const u8, order: GroupOrder };

/// The CLASS-statement `/ order=` for one class var; null = use the proc ORDER=.
fn orderFor(list: []const ClassOrder, name: []const u8) ?GroupOrder {
    for (list) |co| {
        if (eqi(co.name, name)) return co.order;
        // GAP-varcolonprefix-procs: a CLASS `/ order=` copied the PRE-expansion
        // `pfx:` entry — it covers every var the prefix expanded to.
        if (co.name.len > 0 and co.name[co.name.len - 1] == ':' and std.ascii.startsWithIgnoreCase(name, co.name[0 .. co.name.len - 1])) return co.order;
    }
    return null;
}

/// One var-less TABULATE cell value: N is the cell's row count, PCTN its
/// share of the denominator count (the frequency path of a crossing with no
/// analysis variable — same semantics as runTabulateCross's var-less cells).
/// null = a statistic that cannot stand without an analysis variable;
/// parseTable rejects those first, so render sites treat null as fail-loud.
fn tabCellFreq(kw: []const u8, cnt: usize, dcnt: usize) ?f64 {
    if (eqi(kw, "n")) return @floatFromInt(cnt);
    if (eqi(kw, "pctn")) return 100.0 * @as(f64, @floatFromInt(cnt)) / @as(f64, @floatFromInt(dcnt));
    return null;
}

/// TABULATE statistics SAS knows but opensas doesn't compute (GAP-tabulateopts):
/// they fail loud NAMING the statistic instead of falling through to the bogus
/// "analysis variable not found" (the keyword used to land in the analysis slot).
fn isUnsupportedTabStat(nm: []const u8) bool {
    const list = [_][]const u8{ "colpctn", "rowpctn", "reppctn", "pagepctn", "colpctsum", "rowpctsum", "reppctsum", "pagepctsum" };
    for (list) |x| if (eqi(nm, x)) return true;
    return false;
}

/// ORDER= for one TABULATE class dimension's level list (GAP-tabulateopts).
/// INTERNAL = underlying value (numeric-aware, BUG-tabnumorder), FORMATTED = the
/// display string, DATA = first appearance, FREQ = descending count (std.mem.sort
/// is stable → ties keep first-appearance order). `row_keys` is the per-row key
/// array the levels were collected from (the FREQ counts).
fn orderLevels(arena: std.mem.Allocator, keys: [][]const u8, row_keys: []const []const u8, num: bool, order: GroupOrder) !void {
    switch (order) {
        .internal => std.mem.sort([]const u8, keys, LevelCtx{ .num = num }, LevelCtx.less),
        .formatted => std.mem.sort([]const u8, keys, {}, strLess),
        .data => {}, // addUniqueKey appended in first-appearance order
        .freq => {
            const LN = struct { key: []const u8, n: usize };
            const byCountDesc = struct {
                fn f(_: void, a: LN, b: LN) bool {
                    return a.n > b.n;
                }
            }.f;
            var idx = std.HashMap([]const u8, usize, CICtx, std.hash_map.default_max_load_percentage).init(arena);
            const lns = try arena.alloc(LN, keys.len);
            for (keys, 0..) |k, ki| {
                try idx.put(k, ki);
                lns[ki] = .{ .key = k, .n = 0 };
            }
            for (row_keys) |k| lns[idx.get(k).?].n += 1;
            std.mem.sort(LN, lns, {}, byCountDesc);
            for (lns, 0..) |ln, ki| keys[ki] = ln.key;
        },
    }
}

/// Parse `ROW , <col dimension>` from a TABLE statement's token span. The row
/// dimension is a class var, optionally with `all` for a grand-total row
/// (BUG-tabulateall). The column dimension is a `*`-separated crossing whose
/// terms are classified against the CLASS list: a class var → the column-class
/// (2-way split), a stat keyword (or TABULATE-only pctn/pctsum, each with an
/// optional `<dim>` denominator clause — GAP-tabdenom) → a statistic,
/// `all` → a grand-total column, `(s1 s2 …)` → several statistics, anything
/// else → the analysis var. `denoms` stays parallel to `stats` (null = default
/// grand-total basis). Returns false after failing loud (unknown statistic
/// in an explicit stat list — never silently summed, BUG-tabpctsum).
/// TABLE inline `elem='label'` (BUG-tabinlinelabel): a dimension element name
/// followed by `= 'string'` carries a per-table header override. Returns the
/// label text when toks[i+1..] is `= <string>`; the caller advances i by 2.
fn inlineLabelAt(toks: []const Token, i: usize) ?[]const u8 {
    if (atTag(toks, i + 1, .eq) and i + 2 < toks.len and toks[i + 2].tag == .string)
        return toks[i + 2].text;
    return null;
}

fn parseTable(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, spec: *TabSpec, classes: []const []const u8) diag.Error!bool {
    var i: usize = 0;
    // row dimension: names up to the comma — `all` → grand-total row, the first
    // other name → the row var.
    // ponytail: single row var only. A 2nd non-ALL row name (stacked `table g h,`
    // or crossed `table g*h,`) FAILS LOUD rather than silently dropping the extra
    // class — the render path here draws exactly one row-label column, and a silent
    // drop is indistinguishable from a valid single-var table (BUG-tabulaterowdim).
    // Mirrors how PROC REPORT rejects ACROSS. Upgrade path: nested row rendering.
    while (i < toks.len and toks[i].tag != .comma and toks[i].tag != .slash) : (i += 1) {
        // GAP-varcolonprefix-procs: a `pfx:` inside the TABLE EXPRESSION is a
        // crossing position the doc never settles (the TABLES-analogous
        // grouping doc lists parens and name ranges, not prefixes) — LOUD gap,
        // never the old silent skip that read `x:` as a phantom row var `x`.
        if (toks[i].tag == .colon) {
            unsupported("PROC TABULATE: a name prefix (x:) in a TABLE expression is not supported");
            return false;
        }
        if (toks[i].tag != .name) continue;
        if (eqi(toks[i].text, "f") and atTag(toks, i + 1, .eq)) {
            // `table g*f=8., …` formats the row LABELS — not modeled; fail loud
            // instead of misreading `f` as a second row variable (GAP-tabformat).
            unsupported("PROC TABULATE: row-dimension *f= formats are not supported");
            return false;
        }
        if (eqi(toks[i].text, "all")) {
            spec.row_all = true;
            if (inlineLabelAt(toks, i)) |lbl| {
                spec.all_label = lbl;
                i += 2;
            }
        } else if (spec.row_var == null) {
            spec.row_var = toks[i].text;
            if (inlineLabelAt(toks, i)) |lbl| {
                try spec.inline_labels.append(arena, .{ .name = toks[i].text, .text = lbl });
                i += 2;
            }
        } else {
            unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: crossed/stacked row dimensions (2nd row variable '{s}') are not supported", .{toks[i].text}));
            return false;
        }
    }
    // no comma → a one-dimensional table (`table g;` / `table v;`): an
    // unsupported shape (GAP-tabulateopts). Fail loud NAMING it — the old
    // fall-through died later with a confusing "no TABLE analysis variable".
    if (i >= toks.len or toks[i].tag == .slash) {
        unsupported("PROC TABULATE: one-dimensional tables are not supported yet — expected `table rowdim, coldim;`");
        return false;
    }
    i += 1; // past the comma → into the column dimension

    // GAP-tabulateforms #7: split the column expression at the concatenation
    // (blank) operator into segments, each `*`-crossed segment becoming ONE
    // block with its OWN statistics (Procedures Guide printed p.2548, pdf
    // 2597: blank "places the output for each element immediately after the
    // output for the preceding element"). The old flat stats list unioned
    // every segment's statistics onto the LAST analysis variable —
    // `table r, a*sum b*mean` rendered b×(Sum,Mean), an extra unrequested
    // column and a silently dropped one. `after_star` tracks the operator: a
    // name/paren reached across a blank closes the current segment.
    var seg = TabBlock{};
    var seg_class = false; // the segment named the column class
    var seg_open = false; // the segment holds anything at all
    var after_star = true; // start of the expression behaves like after `*`
    while (i < toks.len) : (i += 1) {
        const tag = toks[i].tag;
        if (tag == .star) {
            after_star = true;
            continue;
        }
        if (tag == .comma) {
            // a SECOND top-level comma starts the page dimension (p.2537's
            // `<<page-expression,> row-expression,> column-expression`) — it
            // used to be silently swallowed into the column crossing, drawing
            // the wrong table with no diagnostic.
            unsupported("PROC TABULATE: page dimensions (a third comma-separated TABLE dimension) are not supported yet");
            return false;
        }
        if (tag == .slash) {
            // TABLE `/ options` (GAP-tabulateopts): `box='…'` is honored (the corner
            // box text); every other option fails loud NAMING itself — the old
            // fall-through mis-parsed `box`/`rts` as the analysis variable and died
            // with the bogus "analysis variable not found".
            i += 1;
            while (i < toks.len) {
                if (toks[i].tag == .name) {
                    const nm = toks[i].text;
                    if (eqi(nm, "box") and atTag(toks, i + 1, .eq)) {
                        if (i + 2 < toks.len and toks[i + 2].tag == .string) {
                            spec.box_text = toks[i + 2].text;
                            i += 3;
                        } else {
                            unsupported("PROC TABULATE: BOX= expects a quoted string (BOX=variable is not supported yet)");
                            return false;
                        }
                    } else if (atTag(toks, i + 1, .eq)) {
                        unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: table option {s}= is not supported yet", .{nm}));
                        return false;
                    } else {
                        unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: table option {s} is not supported yet", .{nm}));
                        return false;
                    }
                } else i += 1; // stray punctuation between options
            }
            break;
        }
        if (toks[i].tag == .colon) {
            unsupported("PROC TABULATE: a name prefix (x:) in a TABLE expression is not supported");
            return false;
        }
        if (tag != .name and tag != .lparen) continue; // stray punctuation, as before
        if (!after_star and seg_open) { // the blank operator: close the segment
            if (!try closeTabSegment(arena, diags, &seg, seg_class, &spec.blocks)) return false;
            seg = TabBlock{};
            seg_class = false;
            seg_open = false;
        }
        after_star = false;
        seg_open = true;
        if (tag == .lparen) { // `(s1 s2 …)` explicit stat list — validate every name
            i += 1;
            while (i < toks.len and toks[i].tag != .rparen) : (i += 1)
                if (toks[i].tag == .name) {
                    const nm = toks[i].text;
                    if (!isTabStat(nm)) {
                        if (isUnsupportedTabStat(nm))
                            unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: statistic '{s}' is not supported yet", .{nm}))
                        else
                            unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: unknown statistic '{s}'", .{nm}));
                        return false;
                    }
                    const dc = (try denomClauseAt(arena, toks, i)) orelse return false;
                    if (!hasStat(seg.stats.items, seg.denoms.items, nm, dc.denom)) {
                        try seg.stats.append(arena, nm);
                        try seg.denoms.append(arena, dc.denom);
                    }
                    i = dc.next - 1; // the loop's `i += 1` lands past the clause
                };
        } else {
            const nm = toks[i].text;
            if (eqi(nm, "f") and atTag(toks, i + 1, .eq)) {
                // cell format `*f=6.2` (GAP-tabformat): applies to every data cell
                // of the crossing. A second, DIFFERENT spec would be a per-element
                // format we don't model — fail loud, never silently pick one.
                // (`f` unfollowed by `=` stays a plain variable name.)
                const end = fmtSpecEnd(toks, i + 2);
                if (end == i + 2) {
                    unsupported("PROC TABULATE: malformed *f= cell format");
                    return false;
                }
                const fspec = try joinFmt(arena, toks[i + 2 .. end]);
                if (spec.table_fmt) |prev| {
                    if (!eqi(prev, fspec)) {
                        unsupported("PROC TABULATE: per-element cell formats (multiple distinct *f=) are not supported");
                        return false;
                    }
                } else spec.table_fmt = fspec;
                i = end - 1; // the loop's `i += 1` lands past the spec
            } else if (eqi(nm, "all")) {
                seg.is_all = true; // the universal class variable (p.2547) → a subtotal block
                if (inlineLabelAt(toks, i)) |lbl| {
                    spec.all_label = lbl;
                    i += 2;
                }
            } else if (nameOrPrefixListed(classes, nm)) { // GAP-varcolonprefix-procs: the class list may still hold `pfx:` wire entries here (parse-time)
                // a CLASS var → the column split. A 2nd DISTINCT one is a nested
                // column dimension the renderer doesn't model: it used to fall
                // through to the analysis slot, silently merging cells over it
                // (wrong sums, no diagnostic — BUG-tabnestcol). Mirror the
                // row-dimension guard (BUG-tabulaterowdim): fail loud.
                if (spec.col_class == null) {
                    spec.col_class = nm;
                    seg_class = true;
                    if (inlineLabelAt(toks, i)) |lbl| {
                        try spec.inline_labels.append(arena, .{ .name = nm, .text = lbl });
                        i += 2;
                    }
                } else if (eqi(spec.col_class.?, nm)) {
                    seg_class = true; // the same class crossed into a later segment
                } else {
                    unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: nested column dimension with 2 class variables ('{s}' then '{s}') is not supported yet", .{ spec.col_class.?, nm }));
                    return false;
                }
            } else if (isTabStat(nm)) {
                // sum/mean/n/pctn/pctsum/… → a statistic of THIS segment (deduped within it)
                const dc = (try denomClauseAt(arena, toks, i)) orelse return false;
                if (!hasStat(seg.stats.items, seg.denoms.items, nm, dc.denom)) {
                    try seg.stats.append(arena, nm);
                    try seg.denoms.append(arena, dc.denom);
                }
                i = dc.next - 1;
            } else if (isUnsupportedTabStat(nm)) {
                // COLPCTN/ROWPCTN/REPPCTN/*PCTSUM/…: real SAS statistics we don't
                // compute (GAP-tabulateopts). Fail loud naming the statistic — never
                // a wrong value, never the old bogus "analysis variable not found".
                unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: statistic '{s}' is not supported yet", .{nm}));
                return false;
            } else if (seg.variable == null) {
                seg.variable = nm; // the segment's analysis (VAR) variable
                if (inlineLabelAt(toks, i)) |lbl| {
                    try spec.inline_labels.append(arena, .{ .name = nm, .text = lbl });
                    i += 2;
                }
            } else {
                // a 2nd analysis var IN ONE CROSSING (`a*b*sum`): valid SAS we
                // don't render — used to silently overwrite the first var and
                // draw the wrong table. (Concatenated vars, `a*sum b*mean`, are
                // the supported form — they close the segment at the blank.)
                unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: multiple analysis variables in one crossing ('{s}' then '{s}') are not supported yet — concatenate them instead (a*sum b*mean)", .{ seg.variable.?, nm }));
                return false;
            }
        }
    }
    if (!try closeTabSegment(arena, diags, &seg, seg_class, &spec.blocks)) return false;

    // Shape constraints over the block list — valid SAS forms this renderer
    // doesn't draw yet (gaps, rc 2 D-009), never a silently wrong table.
    if (spec.blocks.items.len == 0) {
        unsupported("PROC TABULATE: no TABLE analysis variable");
        return false;
    }
    var non_all: usize = 0;
    var alls: usize = 0;
    for (spec.blocks.items) |b| {
        if (b.is_all) alls += 1 else non_all += 1;
    }
    if (alls > 1) {
        unsupported("PROC TABULATE: multiple ALL column blocks in one table are not supported yet");
        return false;
    }
    if (spec.col_class != null and non_all > 1) {
        unsupported("PROC TABULATE: concatenated column blocks in a class-crossed table are not supported yet");
        return false;
    }
    if (spec.col_class == null) for (spec.blocks.items) |b| {
        // GAP-tabulateforms #9: a stat-only 1-way column (`table a, n`) — N/PCTN
        // need no analysis variable (p.2548), the renderer just doesn't yet.
        if (!b.is_all and b.variable == null) {
            unsupported("PROC TABULATE: no TABLE analysis variable");
            return false;
        }
    };
    return true;
}

/// Close one concatenation segment into block(s) (GAP-tabulateforms #7):
/// applies the default statistic (SUM for an analysis variable, else N —
/// printed p.2547 "For analysis variables, the default statistic is SUM.
/// Otherwise, the default statistic is N."), enforces p.2548's restriction
/// that only N (and, by the pinned `prod*(n pctn)` idiom, PCTN) can stand
/// without an analysis variable — anything else is malformed SAS, a user
/// error (rc 1, D-009) — and splits a segment naming BOTH the column class
/// and ALL into a cross block plus a subtotal block (`c*all*v*sum` ≡
/// `c*v*sum all*v*sum`). Returns false after failing loud.
fn closeTabSegment(arena: std.mem.Allocator, diags: *diag.Diagnostics, seg: *TabBlock, seg_class: bool, blocks: *std.ArrayList(TabBlock)) diag.Error!bool {
    if (seg.variable == null and seg.stats.items.len == 0 and !seg.is_all and !seg_class) return true; // empty segment
    if (seg.stats.items.len == 0) {
        try seg.stats.append(arena, if (seg.variable != null) "sum" else "n"); // p.2547 defaults
        try seg.denoms.append(arena, null);
    }
    if (seg.variable == null) for (seg.stats.items) |kw| {
        if (!eqi(kw, "n") and !eqi(kw, "pctn"))
            return diags.fail(error.ParseError, 0, "PROC TABULATE: statistic '{s}' requires an analysis variable — only N and PCTN can stand without one", .{kw});
    };
    if (seg_class and seg.is_all) {
        const cross = seg.*;
        seg.is_all = true;
        try blocks.append(arena, cross);
        try blocks.append(arena, seg.*);
        return true;
    }
    try blocks.append(arena, seg.*);
    return true;
}

/// One parsed `<dim>` denominator clause: the dimension name (null when there
/// was no `<`) and the index one past it.
const DenomClause = struct { denom: ?[]const u8, next: usize };

/// Optional PCTN/PCTSUM `<dim>` denominator definition at toks[i] (GAP-tabdenom).
/// No `<` follows → null denom, next = i+1. A `<` on any other statistic, or a
/// clause that isn't exactly `<name>` (empty, unterminated, compound `<a*b>`),
/// fails loud with a message that names PCTN<>/PCTSUM<> — never the old bogus
/// "unknown statistic 'grp'" (the `<...>` used to be mis-parsed as a stat name).
fn denomClauseAt(arena: std.mem.Allocator, toks: []const Token, i: usize) !?DenomClause {
    if (i + 1 >= toks.len or toks[i + 1].tag != .lt) return .{ .denom = null, .next = i + 1 };
    const kw = toks[i].text;
    if (!eqi(kw, "pctn") and !eqi(kw, "pctsum")) {
        unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: only PCTN and PCTSUM accept a <denominator> definition ('{s}<')", .{kw}));
        return null;
    }
    if (i + 3 >= toks.len or toks[i + 2].tag != .name or toks[i + 3].tag != .gt) {
        unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: {s}<...> expects a single class-variable denominator, e.g. {s}<grp> (compound <a*b> definitions are not supported)", .{ kw, kw }));
        return null;
    }
    return .{ .denom = toks[i + 2].text, .next = i + 4 };
}

/// Stat dedup for a crossing: the same keyword with the same `<dim>`
/// denominator (or none) is one statistic — `x*sum all*x*sum` names SUM twice.
/// Same keyword, DIFFERENT denominators are two columns (`pctsum<a> pctsum<b>`).
fn hasStat(stats: []const []const u8, denoms: []const ?[]const u8, nm: []const u8, dn: ?[]const u8) bool {
    for (stats, 0..) |x, k| {
        if (!eqi(x, nm)) continue;
        const dk = denoms[k];
        if (dk == null and dn == null) return true;
        if (dk != null and dn != null and eqi(dk.?, dn.?)) return true;
    }
    return false;
}

/// TABULATE accepts the MEANS stat keywords plus its own pctn/pctsum (each cell's
/// share of the grand total — BUG-tabpctsum).
fn isTabStat(nm: []const u8) bool {
    return statFromKw(nm) != null or eqi(nm, "pctn") or eqi(nm, "pctsum");
}

/// One TABULATE cell value: pctn/pctsum are 100 × cell/basis (report %; the
/// grand total is the default basis — BUG-tabpctsum, a `<dim>` clause swaps in
/// the named dimension's subtotal — GAP-tabdenom); anything else defers to
/// statValue. `obs` is the cell's row count: NMISS = obs − nonmissing n, which
/// statValue can't know (it returned NaN → "." — BUG-tabnmiss), so every render
/// site passes its row-slice length, exactly as emitMeansBlock does for MEANS.
/// null = unknown keyword; parseTable rejects those first, so the render sites
/// treat null as fail-loud, never as a silent SUM fallback.
fn tabCellValue(kw: []const u8, s: Stats, grand: Stats, obs: usize) ?f64 {
    if (statFromKw(kw)) |sk| {
        if (sk == .nmiss) return @floatFromInt(obs - s.n);
        return statValue(sk, s);
    }
    if (eqi(kw, "pctn")) return 100.0 * @as(f64, @floatFromInt(s.n)) / @as(f64, @floatFromInt(grand.n));
    if (eqi(kw, "pctsum")) return 100.0 * s.sum / grand.sum;
    return null;
}

/// GAP-tabdenom denominator basis for a PCTN/PCTSUM `<dim>` cell in the 1-way
/// table: no clause or `<all>` = the grand total (default); `<rowvar>` holds the
/// row class fixed, i.e. the cell's own group (SAS: the percent is then 100).
/// Any other name is not a dimension of this TABLE's crossing → fail loud,
/// null (never the old "unknown statistic 'grp'").
fn tabBasis1(arena: std.mem.Allocator, dn: ?[]const u8, rname: []const u8, s: Stats, grand: Stats) !?Stats {
    const d = dn orelse return grand;
    if (eqi(d, "all")) return grand;
    if (eqi(d, rname)) return s;
    unsupported(try std.fmt.allocPrint(arena, "PROC TABULATE: PCTN/PCTSUM denominator '{s}' is not a class variable in this TABLE's crossing", .{d}));
    return null;
}

fn isInList(list: []const []const u8, name: []const u8) bool {
    for (list) |x| if (eqi(x, name)) return true;
    return false;
}

/// GAP-varcolonprefix-procs: one variable-list entry for a proc's name list.
/// A name directly followed by `:` is kept as one "pfx:" entry — main.zig
/// collectNames' wire form (GAP-varcolonprefix), the DROP/KEEP parseNameList
/// model (GAP-dropcolon) — for expandVarPrefixes once the dataset is known;
/// a bare colon never survives token-skipping into a name. Callers' loops
/// advance past the name themselves, so on a colon this consumes one extra.
fn appendVarListName(arena: std.mem.Allocator, toks: []const Token, i: *usize, list: *std.ArrayList([]const u8)) !void {
    if (i.* + 1 < toks.len and toks[i.* + 1].tag == .colon) {
        try list.append(arena, try std.fmt.allocPrint(arena, "{s}:", .{toks[i.*].text}));
        i.* += 1;
    } else try list.append(arena, toks[i.*].text);
}

/// GAP-varcolonprefix-procs: THE one expander — any "pfx:" entries
/// (appendVarListName's wire form; the name-prefix variable list, Language Reference: Concepts
/// printed p.69 / p.70 Table 4.5) expand against the dataset's columns,
/// case-insensitively, in PDV order — Language Reference: Concepts printed p.62: a variable list
/// refers to its variables "in the same order that SAS uses to keep track of
/// the variables". MEANS/UNIVARIATE/FREQ/TABULATE call this ONCE per list
/// where the dataset is known — never a prefix test at each `ds.indexOf`.
/// The proc.zig twin of main.zig's expandVarList (PROC PRINT). A prefix
/// matching NO column is a typo'd prefix → a loud rc-1 ERROR naming it: the
/// two existing expansion sites already agree on loud rc 1 (eval.zig's OF
/// arm "the name prefix '{s}' matched no variables"; main.zig's PRINT arm
/// "Variable X not found.") — a third disagreeing behaviour would replace
/// one inconsistency with another. Same message vocabulary as the OF arm.
fn expandVarPrefixes(arena: std.mem.Allocator, ds: *Dataset, names: []const []const u8, diags: *diag.Diagnostics, line_no: usize, proc_name: []const u8) diag.Error![][]const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (names) |n| {
        if (n.len > 0 and n[n.len - 1] == ':') {
            var matched = false;
            for (ds.columns.items) |c| {
                if (std.ascii.startsWithIgnoreCase(c.name, n[0 .. n.len - 1])) {
                    try out.append(arena, c.name);
                    matched = true;
                }
            }
            if (!matched)
                return diags.fail(error.ParseError, line_no, "{s}: the name prefix '{s}' matched no variables", .{ proc_name, n });
        } else try out.append(arena, n);
    }
    return out.items;
}

/// In-place sibling for the ArrayList-held lists (one call per list).
fn expandVarListPrefixes(arena: std.mem.Allocator, ds: *Dataset, list: *std.ArrayList([]const u8), diags: *diag.Diagnostics, line_no: usize, proc_name: []const u8) diag.Error!void {
    const ev = try expandVarPrefixes(arena, ds, list.items, diags, line_no, proc_name);
    list.* = .{ .items = ev, .capacity = ev.len };
}

/// Is `nm` named by a class-style list that may still hold not-yet-expanded
/// "pfx:" entries (parse-time, before the dataset is known)? A wire entry
/// matches every name starting with its prefix, case-insensitively.
fn nameOrPrefixListed(list: []const []const u8, nm: []const u8) bool {
    for (list) |x| {
        if (eqi(x, nm)) return true;
        if (x.len > 0 and x[x.len - 1] == ':' and std.ascii.startsWithIgnoreCase(nm, x[0 .. x.len - 1])) return true;
    }
    return false;
}

const Align = enum { left, center, rmargin };
const Cell = struct { text: []const u8, w: usize, al: Align };

/// One boxed row of arbitrary cells: `| c0 | c1 | … |`.
fn boxRowN(arena: std.mem.Allocator, out: *std.ArrayList(u8), cells: []const Cell) !void {
    try out.append(arena, '|');
    for (cells) |c| {
        try boxCell(arena, out, c.text, c.w, c.al);
        try out.append(arena, '|');
    }
    try out.append(arena, '\n');
}

fn boxCell(arena: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, w: usize, al: Align) !void {
    const pad = w -| text.len;
    switch (al) {
        .left => {
            try out.appendSlice(arena, text);
            try blanks(arena, out, pad);
        },
        .center => {
            try blanks(arena, out, pad / 2);
            try out.appendSlice(arena, text);
            try blanks(arena, out, pad - pad / 2);
        },
        .rmargin => { // right-justified with a one-blank right margin
            try blanks(arena, out, (w -| 1) -| text.len);
            try out.appendSlice(arena, text);
            try out.append(arena, ' ');
        },
    }
}

/// Separator `| --- + --- + … |` under the header, one dash-run per column.
fn boxSepN(arena: std.mem.Allocator, out: *std.ArrayList(u8), widths: []const usize) !void {
    try out.append(arena, '|');
    for (widths, 0..) |w, i| {
        for (0..w) |_| try out.append(arena, '-');
        try out.append(arena, if (i + 1 < widths.len) '+' else '|');
    }
    try out.append(arena, '\n');
}

fn boxRule(arena: std.mem.Allocator, out: *std.ArrayList(u8), n: usize) !void {
    for (0..n) |_| try out.append(arena, '-');
    try out.append(arena, '\n');
}

fn blanks(arena: std.mem.Allocator, out: *std.ArrayList(u8), n: usize) !void {
    for (0..n) |_| try out.append(arena, ' ');
}

/// Numeric class-level compare for the one-way sort: a missing value sorts
/// before every present one, special missings by rank (._ < . < .A<…<.Z), as
/// SAS / the cmpNum missingRank fix (BUG-tabulatemissclass). NaN compare
/// (`nums[j-1] > nums[j]`) is always false, so a missing level used to stay
/// wherever the data happened to put it.
fn tabNumLess(a: f64, b: f64) bool {
    const am = std.math.isNan(a);
    const bm = std.math.isNan(b);
    if (am and bm) return Value.missingRank(a) < Value.missingRank(b);
    if (am != bm) return am;
    return a < b;
}

fn tabNum(arena: std.mem.Allocator, x: f64) ![]const u8 {
    // A missing CLASS value keys/renders by its glyph so distinct special
    // missings stay distinct levels (.a→A, ._→_, plain→.) instead of all
    // collapsing to one "." (BUG-tabulatespecialmiss). ±inf is not a missing.
    if (std.math.isNan(x)) return arena.dupe(u8, &[_]u8{Value.missingChar(x)});
    if (!std.math.isFinite(x)) return "."; // ±inf → missing
    if (x == @trunc(x) and @abs(x) < 1e15)
        return std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))});
    // SAS's default cell format is BEST12. — route through the shared path PROC
    // PRINT/MEANS use; raw Zig `{d}` printed 17-digit binary-float noise
    // (BUG-tabrawfloat, qa-findings-tick144).
    return format.bestNum(arena, x);
}

/// A TABULATE data cell: the TABLE `*f=` / proc-level FORMAT= spec when given
/// (GAP-tabformat), else the BEST12. default. Width scans must render through
/// the same path so the column width matches the printed text.
fn tabCell(arena: std.mem.Allocator, x: f64, fmt: ?[]const u8) ![]const u8 {
    if (!std.math.isFinite(x)) return "."; // missing stays missing under any format
    if (fmt) |spec| return format.apply(arena, .{ .num = x }, spec);
    return tabNum(arena, x);
}

fn capFirst(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (s.len == 0) return s;
    const out = try arena.dupe(u8, s);
    out[0] = std.ascii.toUpper(out[0]);
    for (out[1..]) |*c| c.* = std.ascii.toLower(c.*);
    return out;
}

fn sortKeys(keys: [][]const u8, sums: []f64) void {
    var i: usize = 1;
    while (i < keys.len) : (i += 1) {
        var j = i;
        while (j > 0 and std.mem.order(u8, keys[j - 1], keys[j]) == .gt) : (j -= 1) {
            std.mem.swap([]const u8, &keys[j - 1], &keys[j]);
            std.mem.swap(f64, &sums[j - 1], &sums[j]);
        }
    }
}

// ── token helpers ────────────────────────────────────────────────────────────

/// Index just past the balanced `(…)` group starting at toks[i] (a .lparen) —
/// for header scans that skip dataset-option groups like `data=d(keep=x)`.
fn skipParen(toks: []const Token, start: usize) usize {
    var i = start;
    var depth: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag == .lparen) depth += 1;
        if (toks[i].tag == .rparen) {
            depth -= 1;
            if (depth == 0) return i + 1;
        }
    }
    return i;
}

/// If `toks[i..]` is `name = value` with `name` matching (case-insensitively),
/// return the value token's text; else null.
fn optAt(toks: []const Token, i: usize, name: []const u8) ?[]const u8 {
    if (i + 2 >= toks.len) return null;
    if (toks[i].tag != .name or !eqi(toks[i].text, name)) return null;
    if (toks[i + 1].tag != .eq or toks[i + 2].tag != .name) return null;
    return toks[i + 2].text;
}

/// Like `optAt` but the value may also be a quoted string (`outfile="a.csv"`),
/// whose token carries the unquoted text — for EXPORT/IMPORT path options.
fn optAny(toks: []const Token, i: usize, name: []const u8) ?[]const u8 {
    if (i + 2 >= toks.len) return null;
    if (toks[i].tag != .name or !eqi(toks[i].text, name)) return null;
    if (toks[i + 1].tag != .eq) return null;
    return switch (toks[i + 2].tag) {
        .name, .string => toks[i + 2].text,
        else => null,
    };
}

/// `PROC EXPORT data=DS outfile="path" [dbms=csv] [replace];` — serialize DS to a
/// CSV file through the shared CSV engine. ponytail: only DBMS=CSV is wired; any
/// other DBMS is a NOTE + no-op, never a silent success.
/// Documented SAS 9.4 PROC EXPORT options opensas does NOT implement — the
/// gap arms of the two catch-alls (rc 2); anything else is the user's typo
/// (rc 1). Closed sets from the EXPORT syntax block (Base SAS 9.4 Procedures
/// Guide, 7th ed., printed pp. 851-852, === pdf 900/901 ===): the statement
/// options are DATA=/OUTFILE=|OUTTABLE=/DBMS=/REPLACE/LABEL, the delimited-
/// file sub-statements DELIMITER=/PUTNAMES= and the JMP ones DBENCODING=/
/// FMTLIB=/META=.
fn isExportGapOption(kw: []const u8) bool {
    return eqi(kw, "outtable") or eqi(kw, "label");
}

fn isExportStmtGapOption(kw: []const u8) bool {
    inline for (.{ "delimiter", "dbencoding", "fmtlib", "meta" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// Documented SAS 9.4 PROC IMPORT options opensas does NOT implement — same
/// shape (printed pp. 1327-1328, === pdf 1376/1377 ===): statement options
/// DATAFILE=|TABLE=/OUT=/DBMS=/REPLACE; delimited sub-statements DATAROW=/
/// DELIMITER=/GETNAMES=/GUESSINGROWS=/VARNAMEROW=; JMP DBENCODING=/FMTLIB=/
/// META=. MIXED= is from SAS/ACCESS Interface to PC Files (a different
/// book), so it degrades to rc 1, never a false rc 2.
fn isImportGapOption(kw: []const u8) bool {
    return eqi(kw, "table");
}

fn isImportStmtGapOption(kw: []const u8) bool {
    inline for (.{ "varnamerow", "dbencoding", "fmtlib", "meta" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

pub fn runExport(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var data_name: ?[]const u8 = null;
    var outfile: ?[]const u8 = null;
    var dbms: []const u8 = "csv";
    var putnames = true; // SAS default YES: header row written
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAny(toks, i, "data")) |v| {
            data_name = v;
            i += 3;
        } else if (optAny(toks, i, "outfile") orelse optAny(toks, i, "file")) |v| {
            outfile = v;
            i += 3;
        } else if (optAny(toks, i, "dbms")) |v| {
            dbms = v;
            i += 3;
        } else if (optAny(toks, i, "putnames")) |v| {
            putnames = !eqi(v, "no");
            i += 3;
        } else if (tkKw(toks[i], "replace")) {
            // REPLACE: SAS's overwrite consent. The CSV writer overwrites
            // unconditionally (long-standing behavior), so REPLACE is already
            // exactly what happens — enumerate it (every export fixture passes
            // it) instead of silently skipping the token (GAP-procopts).
            i += 1;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // data=x(keep=…) — not routed through procInput; skip without false-firing on `keep`
        } else if (toks[i].tag == .name) {
            // GAP-procopts: an unknown header option (`replaced`, `dbm=csv`, …)
            // used to be silently skipped by the bare `else i += 1`.
            // SPLIT: OUTTABLE=/LABEL are documented (rc 2); a typo stays rc 1.
            if (isExportGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC EXPORT: option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC EXPORT: option {s} is not supported", .{toks[i].text});
        } else i += 1;
    }
    // sub-statements after the header `;` — SAS's `putnames=no;` lives there
    // (BUG-exportputnames). It was dropped on the floor → a NO file wrongly
    // carried the header line.
    if (atTag(toks, i, .semicolon)) i += 1;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (optAny(toks, i, "putnames")) |v| {
            putnames = !eqi(v, "no");
            i += 3;
            continue;
        }
        // GAP-procopts: any other sub-statement used to be skipped token by
        // token — a typo'd `putname=no` silently re-armed the header row.
        // SPLIT: DELIMITER=/DBENCODING=/FMTLIB=/META= are the documented
        // delimited/JMP sub-statements (rc 2); a typo stays rc 1.
        if (toks[i].tag == .name) {
            if (isExportStmtGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC EXPORT: statement option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC EXPORT: statement option {s} is not supported", .{toks[i].text});
        }
        i += 1; // `;` between sub-statements
    }
    const ds = (if (data_name) |n| lib.find(n) else lastDataset(lib)) orelse {
        unsupported("PROC EXPORT: no input dataset");
        return;
    };
    if (!eqi(dbms, "csv")) {
        unsupported("PROC EXPORT: only DBMS=CSV is supported");
        return;
    }
    const path = outfile orelse {
        unsupported("PROC EXPORT: OUTFILE= required");
        return;
    };
    var csv = try io.writeCsvExport(arena, ds); // empty field for numeric missing, not "." (GH#68)
    // PUTNAMES=NO: drop the header row — the writer's first line is always the
    // column names, so slicing past it is byte-identical to not writing it.
    if (!putnames) if (std.mem.indexOfScalar(u8, csv, '\n')) |nl| {
        csv = csv[nl + 1 ..];
    };
    if (!io.writeFileRaw(path, csv)) unsupported("PROC EXPORT: could not write the output file");
}

/// `PROC IMPORT datafile="path" out=DS [dbms=csv|xlsx] [replace]; [sheet="S";]` —
/// read a CSV (shared CSV engine) or XLSX (minimal in-memory reader below) file
/// into a new dataset. The `sheet=` sub-statement rides after the first `;`.
pub fn runImport(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var datafile: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var dbms: []const u8 = "csv";
    var replace = false;
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (optAny(toks, i, "datafile") orelse optAny(toks, i, "file")) |v| {
            datafile = v;
            i += 3;
        } else if (optAny(toks, i, "out")) |v| {
            out_name = v;
            i += 3;
        } else if (optAny(toks, i, "dbms")) |v| {
            dbms = v;
            i += 3;
        } else if (tkKw(toks[i], "replace")) {
            replace = true;
            i += 1;
        } else if (toks[i].tag == .lparen) {
            i = skipParen(toks, i); // out=x(keep=…) — skip without false-firing on `keep`
        } else if (toks[i].tag == .name) {
            // GAP-procopts: an unknown header option used to be silently
            // skipped by the bare `else i += 1` — a typo'd `dbm=xlsx` then
            // read the file as CSV and landed garbage columns.
            // SPLIT: TABLE= is documented (rc 2); a typo stays rc 1.
            if (isImportGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC IMPORT: option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC IMPORT: option {s} is not supported", .{toks[i].text});
        } else i += 1;
    }
    // sub-statements after the header `;` — `sheet="Name";` (XLSX tab), the
    // Excel-engine `range="Name$";` (BUG-procimport) and the DLM controls
    // `delimiter="x"; getnames=yes|no; datarow=N;` (BUG-importdlm).
    var sheet: ?[]const u8 = null;
    var range: ?[]const u8 = null;
    var delim: ?u8 = null;
    var getnames = true;
    var datarow: usize = 0; // 0 = SAS default (2 with names, 1 without)
    if (atTag(toks, i, .semicolon)) i += 1;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (optAny(toks, i, "sheet")) |v| {
            sheet = v;
            i += 3;
            continue;
        }
        if (optAny(toks, i, "range")) |v| {
            range = v;
            i += 3;
            continue;
        }
        if (optAny(toks, i, "delimiter") orelse optAny(toks, i, "dlm")) |v| {
            if (v.len > 0) delim = v[0];
            i += 3;
            continue;
        }
        if (optAny(toks, i, "getnames")) |v| {
            getnames = !eqi(v, "no");
            i += 3;
            continue;
        }
        if (tkKw(toks[i], "datarow") and i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .number) {
            // optAny only takes name/string values; DATAROW's is numeric.
            datarow = std.fmt.parseInt(usize, toks[i + 2].text, 10) catch 0;
            i += 3;
            continue;
        }
        if (tkKw(toks[i], "guessingrows") and i + 2 < toks.len and toks[i + 1].tag == .eq and
            (toks[i + 2].tag == .number or (toks[i + 2].tag == .name and eqi(toks[i + 2].text, "max"))))
        {
            // INERT (SAS 9.4 PROC IMPORT doc): GUESSINGROWS= bounds the rows
            // scanned to guess column types. opensas's reader infers from the
            // WHOLE column (io.zig readDelimited) — GUESSINGROWS=MAX behavior
            // already, a superset of any requested window.
            // ponytail: a smaller window is never simulated; add row-bounded
            // inference if a study's types ever depend on it.
            i += 3;
            continue;
        }
        // GAP-procopts: any other sub-statement was skipped token by token —
        // a typo'd `getname=yes` silently re-armed the header-row default.
        // SPLIT: VARNAMEROW=/DBENCODING=/FMTLIB=/META= are the documented
        // delimited/JMP sub-statements (rc 2); a typo stays rc 1 (MIXED=
        // included — it is from the PC Files book, not this one).
        if (toks[i].tag == .name) {
            if (isImportStmtGapOption(toks[i].text))
                return failGap(diags, toks[i].line, "PROC IMPORT: statement option {s} is not supported", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC IMPORT: statement option {s} is not supported", .{toks[i].text});
        }
        i += 1; // `;` between sub-statements
    }
    const path = datafile orelse {
        unsupported("PROC IMPORT: DATAFILE= required");
        return;
    };
    const out = out_name orelse {
        unsupported("PROC IMPORT: OUT= required");
        return;
    };
    // SAS 9.4: OUT= already existing without REPLACE is an ERROR, never an
    // overwrite — clobbering a kept dataset is the silent-wrong worst case
    // (BUG-importnoreplace). Checked before the file read so a bogus DATAFILE
    // can't mask the clobber.
    if (!replace and lib.find(out) != null) {
        return diags.fail(error.ExecError, toks[0].line, "PROC IMPORT: {s} already exists — specify the REPLACE option to overwrite it", .{out});
    }
    // The Excel engine's RANGE="Name$" names a whole sheet (the trailing $) —
    // map it onto SHEET=. Ignoring RANGE read the FIRST sheet instead: silent
    // wrong data (BUG-procimport). A cell area ("Name$A1:C9") or named range
    // (no $) would import the wrong slice → fail loud.
    if (sheet == null) if (range) |r| {
        if (r.len > 0 and r[r.len - 1] == '$' and std.mem.indexOfScalar(u8, r[0 .. r.len - 1], '$') == null) {
            sheet = r[0 .. r.len - 1];
        } else {
            unsupported(try std.fmt.allocPrint(arena, "PROC IMPORT: RANGE \"{s}\" (cell area / named range) is not supported — only a whole sheet \"Name$\"", .{r}));
            return;
        }
    };
    const is_csv = eqi(dbms, "csv");
    const is_dlm = eqi(dbms, "dlm") or eqi(dbms, "tab");
    // DBMS=EXCEL/XLS is the legacy Excel engine over the same workbook files —
    // route it to the xlsx reader (a binary .xls fails loud below). EXCEL2000/
    // 2002/2003/2007 are version-tagged aliases for the same engine (GH#55).
    const is_xlsx = eqi(dbms, "xlsx") or eqi(dbms, "excel") or eqi(dbms, "xls") or
        eqi(dbms, "excel2000") or eqi(dbms, "excel2002") or
        eqi(dbms, "excel2003") or eqi(dbms, "excel2007");
    if (!is_csv and !is_dlm and !is_xlsx) {
        // checked BEFORE the file read, so a missing file can't mask the real gap
        unsupported(try std.fmt.allocPrint(arena, "PROC IMPORT: DBMS={s} is not supported (CSV, DLM/TAB, XLSX/EXCEL)", .{dbms}));
        return;
    }
    const bytes = io.readFileRaw(arena, path) orelse {
        // name the path: a bogus/undelivered external file (DV.sas's E:\ paths)
        // must read as source skew in the histogram, not an interpreter bug
        unsupported(try std.fmt.allocPrint(arena, "PROC IMPORT: could not read DATAFILE \"{s}\"", .{path}));
        return;
    };
    // GAP-importtypes: an empty (or all-whitespace) delimited input has NO
    // variables and NO observations — importing it as a 0-variable dataset is
    // a silent no-op whose only symptom is a confusing downstream "variable
    // not found". The Procedures Guide IMPORT chapter is silent on the exact
    // SAS message (wording here is ours); we make it an ERROR and create NO
    // dataset — fail loud at the cause, per house rules.
    if ((is_csv or is_dlm) and std.mem.trim(u8, bytes, " \t\r\n").len == 0) {
        return diags.fail(error.ExecError, toks[0].line, "PROC IMPORT: DATAFILE \"{s}\" is empty — no variables or observations to import", .{path});
    }
    if (is_csv) {
        const ds = try io.readDelimited(arena, bytes, out, delim orelse ',', getnames, datarow, true);
        try lib.put(out, ds);
    } else if (is_dlm) {
        // DLM: the DELIMITER= char (SAS default a blank; TAB = a tab).
        const d: u8 = delim orelse (if (eqi(dbms, "tab")) '\t' else ' ');
        const ds = try io.readDelimited(arena, bytes, out, d, getnames, datarow, true);
        try lib.put(out, ds);
    } else {
        if (!std.mem.startsWith(u8, bytes, "PK")) {
            unsupported("PROC IMPORT: not an XLSX workbook (legacy binary .xls is not supported)");
            return;
        }
        const ds = readXlsx(arena, bytes, out, sheet) catch {
            unsupported("PROC IMPORT: could not read the XLSX file");
            return;
        } orelse return; // readXlsx already printed a specific UNSUPPORTED
        try lib.put(out, ds);
    }
}

// ── minimal XLSX reader (PROC IMPORT DBMS=XLSX, MACRO-xlsximport) ─────────────
//
// An .xlsx is a ZIP of XML: `xl/workbook.xml` names the sheets (name→r:id),
// `xl/_rels/workbook.xml.rels` maps r:id→sheet file, `xl/sharedStrings.xml` is
// the string pool, and each `xl/worksheets/sheetN.xml` holds the cells (a cell
// with t="s" stores a pool index, otherwise a literal number). We unzip the few
// members we need in-memory and scan the XML by hand — no styles/formulas/dates.
// ponytail: happy-path only (store/deflate members, shared/number/inline cells,
// getnames=yes, per-column numeric-or-char inference). Anything outside → fail
// loud, never a silently-wrong table. Upgrade path: honor number formats (dates)
// and getnames=no when a program needs them.

/// Extract one member of an in-memory ZIP by exact name, decompressed. Returns
/// null if the member isn't present. Walks the central directory (whose sizes
/// are authoritative even when a local header uses a data descriptor).
fn zipMember(arena: std.mem.Allocator, zip: []const u8, name: []const u8) !?[]const u8 {
    // End-of-central-directory: scan back for the PK\x05\x06 signature.
    if (zip.len < 22) return null;
    var p: usize = zip.len - 22;
    while (true) : (p -= 1) {
        if (std.mem.eql(u8, zip[p .. p + 4], &.{ 'P', 'K', 5, 6 })) break;
        if (p == 0) return null;
    }
    var cd: usize = rdU32(zip, p + 16); // central-directory offset
    const n_ent = rdU16(zip, p + 10);
    var e: usize = 0;
    while (e < n_ent and cd + 46 <= zip.len) : (e += 1) {
        if (!std.mem.eql(u8, zip[cd .. cd + 4], &.{ 'P', 'K', 1, 2 })) return null;
        const method = rdU16(zip, cd + 10);
        const csize = rdU32(zip, cd + 20);
        const usize_ = rdU32(zip, cd + 24);
        const fn_len = rdU16(zip, cd + 28);
        const ex_len = rdU16(zip, cd + 30);
        const cm_len = rdU16(zip, cd + 32);
        const lho = rdU32(zip, cd + 42);
        const fname = zip[cd + 46 .. cd + 46 + fn_len];
        if (std.mem.eql(u8, fname, name)) {
            // Local header: data starts after its own (independent) name+extra.
            if (!std.mem.eql(u8, zip[lho .. lho + 4], &.{ 'P', 'K', 3, 4 })) return null;
            const l_fn = rdU16(zip, lho + 26);
            const l_ex = rdU16(zip, lho + 28);
            const data = zip[lho + 30 + l_fn + l_ex ..][0..csize];
            if (method == 0) return data; // stored
            if (method == 8) return try inflateRaw(arena, data, usize_); // deflate
            unsupported("PROC IMPORT XLSX: unsupported ZIP compression");
            return null;
        }
        cd += 46 + fn_len + ex_len + cm_len;
    }
    return null;
}

fn rdU16(b: []const u8, o: usize) usize {
    return @as(usize, b[o]) | (@as(usize, b[o + 1]) << 8);
}
fn rdU32(b: []const u8, o: usize) usize {
    return rdU16(b, o) | (rdU16(b, o + 2) << 16);
}

fn inflateRaw(arena: std.mem.Allocator, comp: []const u8, expected: usize) ![]u8 {
    const out = try arena.alloc(u8, expected);
    var in: std.Io.Reader = .fixed(comp);
    var window: [std.compress.flate.max_window_len]u8 = undefined;
    var dc: std.compress.flate.Decompress = .init(&in, .raw, &window);
    var w: std.Io.Writer = .fixed(out);
    _ = dc.reader.streamRemaining(&w) catch return error.InflateFailed;
    return out;
}

/// Build a dataset from the requested (or first) sheet of an XLSX byte buffer.
/// Returns null after printing a specific UNSUPPORTED when the shape is outside
/// the happy path.
fn readXlsx(arena: std.mem.Allocator, zip: []const u8, out_name: []const u8, sheet: ?[]const u8) !?*Dataset {
    const shared = try sharedStrings(arena, (try zipMember(arena, zip, "xl/sharedStrings.xml")) orelse &.{});
    const wb = (try zipMember(arena, zip, "xl/workbook.xml")) orelse {
        unsupported("PROC IMPORT XLSX: no workbook.xml");
        return null;
    };
    // Resolve sheet name → r:id (workbook.xml) → target file (rels). No sheet=
    // → the first `<sheet>` element.
    const rid = sheetRid(wb, sheet) orelse {
        unsupported("PROC IMPORT XLSX: requested SHEET= not found");
        return null;
    };
    const rels = (try zipMember(arena, zip, "xl/_rels/workbook.xml.rels")) orelse "";
    const target = relTarget(rels, rid) orelse {
        unsupported("PROC IMPORT XLSX: sheet relationship not found");
        return null;
    };
    const member = try std.fmt.allocPrint(arena, "xl/{s}", .{target});
    const sheet_xml = (try zipMember(arena, zip, member)) orelse {
        unsupported("PROC IMPORT XLSX: sheet part not found");
        return null;
    };

    // Parse cells into a grid: rows of columns, each an optional string.
    var grid: std.ArrayList([]?[]const u8) = .empty;
    var maxc: usize = 0;
    var ri = std.mem.indexOf(u8, sheet_xml, "<sheetData>") orelse {
        unsupported("PROC IMPORT XLSX: no sheetData");
        return null;
    };
    while (std.mem.indexOfPos(u8, sheet_xml, ri, "<row")) |rs| {
        const re = std.mem.indexOfPos(u8, sheet_xml, rs, "</row>") orelse break;
        var cells: std.ArrayList(?[]const u8) = .empty;
        var ci: usize = rs;
        while (std.mem.indexOfPos(u8, sheet_xml, ci, "<c ")) |cs| {
            if (cs > re) break;
            const open_end = std.mem.indexOfScalarPos(u8, sheet_xml, cs, '>') orelse break;
            const open = sheet_xml[cs..open_end]; // the `<c ...` attributes
            const col = colIndex(attr(open, "r=") orelse "A1");
            var text: ?[]const u8 = null;
            if (sheet_xml[open_end - 1] != '/') { // not self-closing (empty cell)
                const cell_end = std.mem.indexOfPos(u8, sheet_xml, open_end, "</c>") orelse break;
                const body = sheet_xml[open_end + 1 .. cell_end];
                const raw = tagText(body, "v") orelse tagText(body, "t"); // <v> or inline <t>
                if (raw) |rv| {
                    const ctype = attr(open, "t=") orelse "";
                    if (eqi(ctype, "s")) {
                        const idx = std.fmt.parseInt(usize, std.mem.trim(u8, rv, " \t\r\n"), 10) catch 0;
                        text = if (idx < shared.len) shared[idx] else "";
                    } else text = try xmlUnescape(arena, rv);
                }
                ci = cell_end + 4;
            } else ci = open_end + 1;
            while (cells.items.len < col) try cells.append(arena, null); // pad gaps
            try cells.append(arena, text);
        }
        maxc = @max(maxc, cells.items.len);
        try grid.append(arena, cells.items);
        ri = re + 6;
    }
    if (grid.items.len == 0) {
        unsupported("PROC IMPORT XLSX: empty sheet");
        return null;
    }

    const ds = try arena.create(Dataset);
    ds.* = Dataset.init(arena, out_name);
    const header = grid.items[0];
    // Column names from the first row (getnames=yes); type = numeric iff every
    // non-blank data cell in the column parses as a number.
    var names: std.ArrayList([]const u8) = .empty;
    for (0..maxc) |c| {
        const raw = if (c < header.len) header[c] else null;
        const base = if (raw) |r| io.validName(arena, r, c) else try std.fmt.allocPrint(arena, "VAR{d}", .{c + 1});
        _ = try io.uniqueName(arena, &names, base); // appends the deduped name to `names`
    }
    for (0..maxc) |c| {
        var numeric = true;
        var any = false;
        for (grid.items[1..]) |row| {
            const v = if (c < row.len) row[c] else null;
            if (v) |s| {
                const tr = std.mem.trim(u8, s, " \t\r\n");
                if (tr.len == 0) continue;
                any = true;
                _ = std.fmt.parseFloat(f64, tr) catch {
                    numeric = false;
                    break;
                };
            }
        }
        _ = try ds.addColumn(names.items[c], if (numeric and any) .num else .char);
    }
    for (grid.items[1..]) |row| {
        const vals = try arena.alloc(Value, maxc);
        for (0..maxc) |c| {
            const v = if (c < row.len) row[c] else null;
            if (ds.columns.items[c].type == .num) {
                vals[c] = if (v) |s| blk: {
                    const tr = std.mem.trim(u8, s, " \t\r\n");
                    break :blk if (tr.len == 0) Value.missing else Value{ .num = std.fmt.parseFloat(f64, tr) catch std.math.nan(f64) };
                } else Value.missing;
            } else vals[c] = .{ .str = v orelse "" };
        }
        try ds.appendRow(vals);
    }
    return ds;
}

/// All `<si>` entries of a sharedStrings.xml, each the concatenation of its
/// `<t>` runs (rich-text si has several), XML-unescaped.
fn sharedStrings(arena: std.mem.Allocator, xml: []const u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, xml, i, "<si>")) |ss| {
        const se = std.mem.indexOfPos(u8, xml, ss, "</si>") orelse break;
        const body = xml[ss + 4 .. se];
        var buf: std.ArrayList(u8) = .empty;
        var ti: usize = 0;
        while (std.mem.indexOfPos(u8, body, ti, "<t")) |ts| {
            const te_open = std.mem.indexOfScalarPos(u8, body, ts, '>') orelse break;
            if (body[te_open - 1] == '/') { // <t/> empty
                ti = te_open + 1;
                continue;
            }
            const te = std.mem.indexOfPos(u8, body, te_open, "</t>") orelse break;
            try buf.appendSlice(arena, try xmlUnescape(arena, body[te_open + 1 .. te]));
            ti = te + 4;
        }
        try list.append(arena, buf.items);
        i = se + 5;
    }
    return list.items;
}

/// The r:id of the `<sheet name="X">` whose name matches (case-insensitive), or
/// the first sheet when `want` is null.
fn sheetRid(wb: []const u8, want: ?[]const u8) ?[]const u8 {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, wb, i, "<sheet ")) |ss| {
        const se = std.mem.indexOfScalarPos(u8, wb, ss, '>') orelse return null;
        const tag = wb[ss..se];
        const nm = attr(tag, "name=") orelse "";
        const rid = attr(tag, "id=") orelse "";
        if (want == null or eqi(nm, want.?)) return rid;
        i = se + 1;
    }
    return null;
}

/// The Target of the `<Relationship Id="rId">` in a .rels file.
fn relTarget(rels: []const u8, rid: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (std.mem.indexOfPos(u8, rels, i, "<Relationship ")) |rs| {
        const re = std.mem.indexOfScalarPos(u8, rels, rs, '>') orelse return null;
        const tag = rels[rs..re];
        if (attr(tag, "Id=")) |id| if (eqi(id, rid)) return attr(tag, "Target=");
        i = re + 1;
    }
    return null;
}

/// The value of `key` (e.g. `name=` or `r=`) in a tag's attribute text, reading
/// the quoted string that follows. `key` includes the `=` (or a trailing space
/// for the bare `r ` fallback).
fn attr(tag: []const u8, key: []const u8) ?[]const u8 {
    const k = std.mem.indexOf(u8, tag, key) orelse return null;
    const q = std.mem.indexOfScalarPos(u8, tag, k + key.len, '"') orelse return null;
    const end = std.mem.indexOfScalarPos(u8, tag, q + 1, '"') orelse return null;
    return tag[q + 1 .. end];
}

/// Inner text of the first `<name>…</name>` in `body`, or null.
fn tagText(body: []const u8, name: []const u8) ?[]const u8 {
    var open_buf: [8]u8 = undefined;
    const open = std.fmt.bufPrint(&open_buf, "<{s}>", .{name}) catch return null;
    const os = std.mem.indexOf(u8, body, open) orelse return null;
    var close_buf: [8]u8 = undefined;
    const close = std.fmt.bufPrint(&close_buf, "</{s}>", .{name}) catch return null;
    const cs = std.mem.indexOfPos(u8, body, os + open.len, close) orelse return null;
    return body[os + open.len .. cs];
}

/// Excel A1-style column letters → 0-based column index.
fn colIndex(ref: []const u8) usize {
    var n: usize = 0;
    for (ref) |ch| {
        const up = std.ascii.toUpper(ch);
        if (up < 'A' or up > 'Z') break;
        n = n * 26 + (up - 'A' + 1);
    }
    return if (n == 0) 0 else n - 1;
}

/// Unescape the five predefined XML entities. Returns the input unchanged when
/// there's no `&` (the common case), avoiding an allocation.
fn xmlUnescape(arena: std.mem.Allocator, s: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, s, '&') == null) return s;
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '&') {
            if (std.mem.startsWith(u8, s[i..], "&amp;")) {
                try buf.append(arena, '&');
                i += 5;
            } else if (std.mem.startsWith(u8, s[i..], "&lt;")) {
                try buf.append(arena, '<');
                i += 4;
            } else if (std.mem.startsWith(u8, s[i..], "&gt;")) {
                try buf.append(arena, '>');
                i += 4;
            } else if (std.mem.startsWith(u8, s[i..], "&quot;")) {
                try buf.append(arena, '"');
                i += 6;
            } else if (std.mem.startsWith(u8, s[i..], "&apos;")) {
                try buf.append(arena, '\'');
                i += 6;
            } else {
                try buf.append(arena, s[i]);
                i += 1;
            }
        } else {
            try buf.append(arena, s[i]);
            i += 1;
        }
    }
    return buf.items;
}

/// parser.zig's keyword matcher, reused (QL-B): one idiom for token-keyword
/// tests across the tree instead of a per-file re-implementation.
const tkKw = @import("parser.zig").tkKw;

/// True if token `i` exists and is keyword `kw` — the bound stated positively,
/// once, so call sites don't each re-derive `i < toks.len and …` (QL-B, taste
/// #13: one forgotten bound among ~100 hand-copies is an OOB token read).
fn atKw(toks: []const Token, i: usize, kw: []const u8) bool {
    return i < toks.len and tkKw(toks[i], kw);
}

/// True if token `i` exists and has tag `tag` (the `.tag ==` form of atKw).
fn atTag(toks: []const Token, i: usize, tag: lex.Tag) bool {
    return i < toks.len and toks[i].tag == tag;
}

/// Shared PROC-statement `by [descending] var … [notsorted];` scanner
/// (MEANS/TRANSPOSE/UNIVARIATE/RANK/STANDARD/TABULATE, and PROC PRINT in
/// main.zig — PROCBY-printfreq). Routes through parser.scanByList — the SAME
/// scanner the DATA step uses (GAP-procbydescending): no third BY parser, so
/// DESCENDING (per-variable, Statements ref p.39-43) and NOTSORTED
/// (statement-wide, contiguous-run grouping) mean exactly one thing across
/// DATA step, PROC SORT and every PROC on this path. GROUPFORMAT still fails
/// loud there (GAP-bygroupformat — "You cannot use the GROUPFORMAT option,
/// which is available in the BY statement in a DATA step, in a BY statement in
/// any PROC step", Base SAS Procedures Guide p.75). PROC SORT's own BY (which
/// implements DESCENDING as sort keys) does not route through here. Output is
/// scanByList's wire encoding — decode with decodeProcBy before any indexOf.
pub fn parseProcBy(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, i: *usize, bys: *std.ArrayList([]const u8)) diag.Error!void {
    i.* += 1; // by
    try bys.appendSlice(arena, try @import("parser.zig").Parser.scanByList(arena, diags, toks, i));
}
/// decodeProcBy's result: clean BY names, per-variable direction (parallel to
/// `names`), and the statement-wide NOTSORTED flag.
pub const ProcBy = struct { names: []const []const u8, desc: []const bool, notsorted: bool };

/// exec.decodeBy's PROC-side twin (GAP-procbydescending): split scanByList's
/// wire encoding (`"\x00D"` prefix = descending var, `"\x00notsorted"` trailer)
/// back into clean names + directions, so every PROC BY consumer reads the
/// SAME value the DATA step does.
pub fn decodeProcBy(arena: std.mem.Allocator, encoded: []const []const u8) error{OutOfMemory}!ProcBy {
    var names: std.ArrayList([]const u8) = .empty;
    var desc: std.ArrayList(bool) = .empty;
    var notsorted = false;
    for (encoded) |n| {
        if (n.len > 0 and n[0] == 0) {
            if (n.len >= 2 and n[1] == 'D') {
                try names.append(arena, n[2..]);
                try desc.append(arena, true);
            } else notsorted = true; // "\x00notsorted"
        } else {
            try names.append(arena, n);
            try desc.append(arena, false);
        }
    }
    return .{ .names = names.items, .desc = desc.items, .notsorted = notsorted };
}

fn lastDataset(lib: *Library) ?*Dataset {
    const n = lib.sets.items.len;
    return if (n == 0) null else lib.sets.items[n - 1];
}

fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

// TEST-quietnoise2: negative tests (reportacross/reportcomputed/…) exercise the
// fail-loud UNSUPPORTED path but must not spam stderr — that noise + zig's ensuing
// "failed command" line read as a suite failure on a GREEN build. In a test build
// the message is CAPTURED for a test to assert on; the CLI still prints it.
var g_test_unsup_buf: [512]u8 = undefined;
pub var g_test_last_unsup: []const u8 = "";

/// GAP guard (D-009): the construct is valid SAS 9.4 opensas doesn't implement
/// — an opensas gap, exit 2 ("file an opensas issue"), not rc 1 ("fix your
/// SAS"). Flag the gap, then fail with the usual loud ERROR. parser.zig's
/// failGap, same shape; `unsupported` is the no-diags sibling. ONLY for guards
/// matching a SPECIFIC valid construct (a named keyword/option) — a catch-all
/// that also swallows typos stays a plain user-error `fail`
/// (audit-exitcodecontract.md §5b).
fn failGap(diags: *diag.Diagnostics, line_no: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    diag.markGap();
    return diags.fail(error.ParseError, line_no, fmt, args);
}

/// The SAS 9.4 member types a PROC DATASETS MEMTYPE= value can validly be,
/// beyond the DATA opensas accepts. Deliberately the universally documented
/// set only — an exotic-but-valid type degrades to the user's rc 1, never a
/// false rc 2 (audit-exitcodecontract.md §5b).
fn isDatasetMemberType(kw: []const u8) bool {
    inline for (.{ "all", "catalog", "view" }) |mtyp|
        if (eqi(kw, mtyp)) return true;
    return false;
}

// BUG-proctypoexits2 — the `unsupported("PROC X: unknown option")` catch-alls
// below conflated a TYPO (user error, rc 1) with a documented SAS 9.4 option we
// simply don't implement (gap, rc 2), so a misspelling exited 2 — "file an
// opensas issue" for the user's own mistake (the inverse of D-009, the same
// disease 2a57cc33 fixed in main.zig). The fix is the 342b8305 split: each
// PROC's option set is CLOSED by the doc (Base SAS 9.4 Procedures Guide,
// Seventh Edition), so a catch-all name in the doc set keeps the byte-identical
// UNSUPPORTED message at rc 2, and any other name becomes the user's rc 1.
// Deliberately the doc's set only — an exotic-but-valid alias the guide omits
// degrades to rc 1, never a false rc 2 (audit-exitcodecontract.md §5b).

/// PROC SORT (printed pp. 2406-2408): the options opensas does NOT implement.
/// The bare collating-sequence keywords (ASCII…SWEDISH) are valid options too;
/// SORTSEQ= is handled upstream. NODUPRECS/NODUPS/SORTWKNO=/TECHNIQUE= are not
/// in this edition of the guide, so they stay on the typo arm.
fn isSortGapOption(kw: []const u8) bool {
    inline for (.{ "ascii", "danish", "ebcdic", "finnish", "national", "norwegian", "reverse", "swedish", "force", "presorted", "sortsize", "uniqueout", "nouniquekey", "nounikey", "nounikeys", "nouniquekeys" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// PROC TRANSPOSE (printed pp. 2697-2699): DATA=/DELIMITER=/LABEL=/LET/NAME=/
/// OUT=/PREFIX=/SUFFIX= are all implemented — INDB= is the one valid option
/// left, so every other name reaching the catch-all is the user's typo.
fn isTransposeGapOption(kw: []const u8) bool {
    return eqi(kw, "indb");
}

/// PROC CONTENTS (printed pp. 493-497): the documented set opensas does NOT
/// implement (DATA=/OUT=/NOPRINT/ORDER=/VARNUM/SHORT are handled upstream;
/// POSITION is an accepted-but-undocumented alias, so it can't be a gap here).
fn isContentsGapOption(kw: []const u8) bool {
    inline for (.{ "centiles", "details", "nodetails", "directory", "encryptkey", "fmtlen", "memtype", "mtype", "mt", "nods", "out2" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// PROC COMPARE (printed pp. 428-435): the documented set opensas does NOT
/// implement (BASE=/COMPARE=/METHOD=/CRITERION=/OUT=/OUTBASE/OUTCOMP/OUTDIF/
/// OUTNOEQUAL/NOVALUES/NOSUMMARY/BRIEF/MAXPRINT= are handled upstream; LISTALL/
/// PRINTALL/TRANSPOSE/CLIST already fail loud as gaps on their own arm).
/// OUTPERCENT is the documented name opensas only accepts under its OUTPCT
/// alias — valid SAS, so a gap here; C= is the documented COMPARE= alias.
fn isCompareGapOption(kw: []const u8) bool {
    inline for (.{ "allobs", "allstats", "allvars", "briefsummary", "c", "error", "fuzz", "list", "listbase", "listbaseobs", "listbasevar", "listcomp", "listcompobs", "listcompvar", "listequalvar", "listobs", "listvar", "nodate", "nomissbase", "nomisscomp", "nomissing", "nomiss", "noprint", "note", "outall", "outpercent", "outstats", "stats", "warning" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

fn unsupported(msg: []const u8) void {
    diag.markGap(); // opensas gap → the run exits 2 (D-009 / FLY-exitcodes)
    if (@import("builtin").is_test) {
        g_test_last_unsup = std.fmt.bufPrint(&g_test_unsup_buf, "{s}", .{msg}) catch "unsupported message too long";
    } else {
        std.debug.print("UNSUPPORTED: {s}\n", .{msg});
    }
}

// ── tests ────────────────────────────────────────────────────────────────────

const t = std.testing;

fn strV(s: []const u8) Value {
    return .{ .str = s };
}
fn numV(x: f64) Value {
    return .{ .num = x };
}

fn buildHave(arena: std.mem.Allocator) !*Dataset {
    const ds = try arena.create(Dataset);
    ds.* = Dataset.init(arena, "have");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("age", .num);
    try ds.appendRow(&.{ strV("Carol"), numV(40) });
    try ds.appendRow(&.{ strV("Alice"), numV(30) });
    try ds.appendRow(&.{ strV("Bob"), numV(25) });
    return ds;
}

// ── PROC FORMAT ──────────────────────────────────────────────────────────────
// `proc format; value NAME v1="lbl" v2-v3="lbl" other="lbl"; value $CNAME "k"="lbl" 'A'-'C'="lbl"; run;`
// Parse each VALUE statement into a format.UserFmt and install the catalog so the
// format engine (put / a column format in PROC PRINT) decodes coded values to
// labels (BUG-userformat). Numeric formats take single values or `lo-hi` ranges
// (with `low`/`high` for open ends) plus an `OTHER=`; `$NAME` formats key on the
// character value. A range's label may instead be `[fmtname w.d]` — a nested-format
// label (SAS directed formatting, BUG-fmtnestlabel) resolved by format.apply.
// `$NAME` formats also take character RANGES ('A'-'C'=, lexical match, `<`
// exclusion like numeric — GAP-fmtcharrange).
// Catalogs from multiple PROC FORMAT steps accumulate.
//
// FAIL LOUD (BUG-fmtprocbatch): every statement/option/entry this parser doesn't
// implement is a visible error, never a skipped token — INVALUE, SELECT/EXCLUDE/
// FMTLIB, `(multilabel)`/other VALUE options, `.` missing keys, unquoted labels.
// Overlapping VALUE ranges error like SAS without MULTILABEL (BUG-fmtoverlap).
//
// ponytail: INVALUE informats and MULTILABEL themselves are not implemented (loud
// GAP, not silent). CNTLOUT= dumps the catalog (inverse of CNTLIN=). `LIBRARY=` is
// accepted: the catalog is process-wide, so a format built early (e.g.
// a codelist-format macro's VISNUM) persists to a later step's apply (GAP-permformat).
/// Documented SAS 9.4 PROC FORMAT statement options opensas does NOT
/// implement — the gap arm of BOTH header catch-alls (rc 2); anything else
/// is the user's typo (rc 1). Closed set from the "Summary of Optional
/// Arguments" (Base SAS 9.4 Procedures Guide, 7th ed., printed p. 1085,
/// === pdf 1134/1135 ===): CASFMTLIB=/CNTLIN=/CNTLOUT=/FMTLIB/LIBRARY=/
/// LOCALE/MAXLABLEN=/MAXSELEN=/NOREPLACE/PAGE; CNTLIN=/CNTLOUT=/LIBRARY=
/// are handled. One list serves both arms because the two arms split on
/// token SHAPE (`name = name` vs anything else), not on option kind:
/// MAXLABLEN= takes a number, CASFMTLIB= a quoted string, FMTLIB is bare.
fn isFormatGapOption(kw: []const u8) bool {
    inline for (.{ "casfmtlib", "fmtlib", "locale", "maxlablen", "maxselen", "noreplace", "page" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// Documented SAS 9.4 PICTURE per-entry `(picture-N-options)` opensas does
/// NOT implement — "The DATATYPE, DECSEP, DIG3SEP, FILL, LANGUAGE, MULT,
/// NOEDIT, and PREFIX options are valid in parentheses after the
/// user-supplied value label" (printed pp. 1098-1099, === pdf 1147/1148 ===);
/// PREFIX=/MULT=/ROUND are handled. Gap arm (rc 2); a typo stays rc 1.
fn isPictureGapOption(kw: []const u8) bool {
    inline for (.{ "datatype", "decsep", "dig3sep", "fill", "language", "noedit" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

/// The PICTURE statement's POSITION-1 `(format-options)` — "The DEFAULT,
/// FUZZ, MAX, MIN, MULTILABEL, NOTSORTED, and ROUND options are valid before
/// the value range specification" (printed p. 1098, === pdf 1147 ===). None
/// are honoured → the gap arm (rc 2); any other name in that paren group is
/// the user's error (rc 1). Corrects the entry catch-all's USER-ERROR
/// verdict: that reasoning covered ENTRIES, but the position-1 group is not
/// an entry and the doc allows it there (§5b own-slice find).
fn isPicturePos1Option(kw: []const u8) bool {
    inline for (.{ "default", "fuzz", "max", "min", "multilabel", "notsorted", "round" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

pub fn runFormat(cx: ProcCtx, toks: []const Token) diag.Error!void {
    const arena = cx.arena;
    const lib = cx.lib;
    const diags = cx.diags;
    var cats: std.ArrayList(format.UserFmt) = .empty;
    var i: usize = 2; // past `proc format`
    // The `proc format <options>;` header statement. CNTLIN=<dataset> builds
    // formats from the control dataset; CNTLOUT=<dataset> dumps the catalog to
    // one after the VALUE/PICTURE statements install (inverse, BUG-fmtcntlout);
    // LIBRARY=/LIB= are accepted as-is. Anything else errors — no silent skip.
    var cntlout: ?[]const u8 = null;
    while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) {
        if (toks[i].tag == .name and i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
            if (tkKw(toks[i], "cntlin")) {
                try appendCntlin(arena, lib, toks[i + 2].text, &cats);
            } else if (tkKw(toks[i], "cntlout")) {
                cntlout = toks[i + 2].text;
            } else if (tkKw(toks[i], "library") or tkKw(toks[i], "lib")) {
                // accepted — single process-wide catalog (GAP-permformat)
            } else {
                // SPLIT: a documented but unimplemented option (rc 2) vs the
                // user's typo (rc 1) — same message body, one closed set.
                if (isFormatGapOption(toks[i].text))
                    return failGap(diags, toks[i].line, "PROC FORMAT: option {s}= is not supported (only CNTLIN=, CNTLOUT=, LIBRARY=)", .{toks[i].text});
                return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: option {s}= is not supported (only CNTLIN=, CNTLOUT=, LIBRARY=)", .{toks[i].text});
            }
            i += 3;
        } else if (toks[i].tag == .name and isFormatGapOption(toks[i].text))
            // the bare flags / number- or string-valued members of the same
            // closed set (FMTLIB, LOCALE, NOREPLACE, PAGE, MAXLABLEN=8,
            // CASFMTLIB='name') — gap (rc 2)
            return failGap(diags, toks[i].line, "PROC FORMAT: '{s}' is not a supported PROC FORMAT statement option", .{toks[i].text})
        else return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: '{s}' is not a supported PROC FORMAT statement option", .{toks[i].text});
    }
    if (atTag(toks, i, .semicolon)) i += 1;
    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "run") or tkKw(toks[i], "quit")) break;
        if (atTag(toks, i, .semicolon)) { // empty statement
            i += 1;
            continue;
        }
        if (tkKw(toks[i], "picture")) {
            try parsePicture(arena, diags, toks, &i, &cats);
            continue;
        }
        if (!tkKw(toks[i], "value")) {
            // INVALUE (informats) and EXCLUDE/SELECT (catalog maintenance) are
            // valid SAS 9.4 PROC FORMAT statements — a gap (rc 2); a typo'd
            // keyword stays the user's error below.
            if (tkKw(toks[i], "invalue") or tkKw(toks[i], "exclude") or tkKw(toks[i], "select"))
                return failGap(diags, toks[i].line, "PROC FORMAT: statement {s} is not supported (only VALUE and PICTURE)", .{toks[i].text});
            return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: statement {s} is not supported (only VALUE and PICTURE)", .{toks[i].text});
        }
        i += 1; // past `value`
        var is_char = false;
        if (atTag(toks, i, .dollar)) {
            is_char = true;
            i += 1;
        }
        if (i >= toks.len or toks[i].tag != .name)
            return diags.fail(error.ParseError, toks[i -| 1].line, "PROC FORMAT: VALUE requires a format name", .{});
        const fname = toks[i].text;
        const def_line = toks[i].line;
        i += 1;
        // VALUE statement options live in parens — `(multilabel)`, `(notsorted)`.
        // MULTILABEL changes overlap semantics, NOTSORTED lookup order: installing
        // an ordinary single-label format would silently mis-resolve, so error
        // (BUG-fmtmultilabel).
        if (atTag(toks, i, .lparen)) {
            const opt = if (i + 1 < toks.len) toks[i + 1].text else "";
            // MULTILABEL/NOTSORTED are the two valid SAS 9.4 VALUE options — a
            // gap (rc 2); any other paren option is the user's typo (rc 1).
            if (eqi(opt, "multilabel") or eqi(opt, "notsorted"))
                return failGap(diags, toks[i].line, "PROC FORMAT: VALUE option ({s}) is not supported", .{opt});
            return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: VALUE option ({s}) is not supported", .{opt});
        }
        var entries: std.ArrayList(format.UserFmtEntry) = .empty;
        while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) {
            var e: format.UserFmtEntry = .{ .label = "" };
            if (tkKw(toks[i], "other")) {
                e.is_other = true;
                i += 1;
            } else if (is_char and toks[i].tag == .string) {
                e.skey = toks[i].text;
                i += 1;
                // Character RANGE 'A'-'C'= (GAP-fmtcharrange) with the same `<`
                // endpoint exclusion as numeric ranges (parseNumRange); matching
                // is lexical, in format.zig. LOW/HIGH open ends are numeric-only
                // in SAS → a non-quoted high endpoint fails loud, never mis-keys.
                if (atTag(toks, i, .lt)) {
                    e.lo_excl = true;
                    i += 1;
                }
                if (atTag(toks, i, .minus)) {
                    i += 1;
                    if (atTag(toks, i, .lt)) {
                        e.hi_excl = true;
                        i += 1;
                    }
                    if (i >= toks.len or toks[i].tag != .string)
                        return diags.fail(error.ParseError, toks[i -| 1].line, "PROC FORMAT: character range requires a quoted high endpoint ('A'-'C'=label; LOW/HIGH are numeric-only)", .{});
                    if (toks[i].text.len == 0)
                        return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: empty character range high endpoint is not supported", .{});
                    e.skey_hi = toks[i].text;
                    i += 1;
                }
            } else if (toks[i].tag == .number or tkKw(toks[i], "low") or tkKw(toks[i], "high") or
                (atTag(toks, i, .minus) and i + 1 < toks.len and toks[i + 1].tag == .number))
            {
                parseNumRange(toks, &i, &e);
            } else if (atTag(toks, i, .dot)) {
                // `.` (numeric missing) as a VALUE key is valid SAS — the gap the
                // else message used to name; split out so a garbage entry below
                // stays the user's rc 1.
                return failGap(diags, toks[i].line, "PROC FORMAT: a '.' missing VALUE key is not supported", .{});
            } else {
                return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: unsupported VALUE entry '{s}' (entries are number/low/high ranges or 'char' keys)", .{toks[i].text});
            }
            if (atTag(toks, i, .eq)) i += 1; // `=`
            if (atTag(toks, i, .string)) {
                e.label = toks[i].text;
                i += 1;
            } else if (atTag(toks, i, .lbrace)) { // `[fmtname w.d]` — nested-format label
                e.nested = true;
                e.label = try parseNestedSpec(arena, diags, toks, &i);
            } else {
                return diags.fail(error.ParseError, toks[i -| 1].line, "PROC FORMAT: VALUE entry requires ='label' or =[format]", .{});
            }
            try entries.append(arena, e);
        }
        if (!is_char) try checkValueOverlap(diags, fname, entries.items, def_line);
        try cats.append(arena, .{ .name = fname, .is_char = is_char, .entries = try entries.toOwnedSlice(arena) });
    }
    // Accumulate across PROC FORMAT steps (all share the program arena).
    const existing = format.userFormats();
    if (existing.len == 0) {
        format.setUserFormats(try cats.toOwnedSlice(arena));
    } else {
        var merged: std.ArrayList(format.UserFmt) = .empty;
        try merged.appendSlice(arena, existing);
        try merged.appendSlice(arena, cats.items);
        format.setUserFormats(try merged.toOwnedSlice(arena));
    }
    // CNTLOUT= — dump the (whole, merged) catalog to a control dataset.
    if (cntlout) |name| try dumpCntlout(arena, lib, name, format.userFormats());
}

/// Parse a nested-format label `[fmtname<w><.d>]` (SAS directed formatting:
/// the range's label is another format applied to the value at render time —
/// BUG-fmtnestlabel). The brackets lex as lbrace/rbrace and the spec inside is
/// reassembled as text (`[dollar8.2]` → name 'dollar8' + number '.2' → "dollar8.2");
/// format.apply parses it again at apply time.
fn parseNestedSpec(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, ip: *usize) diag.Error![]const u8 {
    var i = ip.*;
    const def_line = toks[i].line;
    i += 1; // past `[`
    var buf: std.ArrayList(u8) = .empty;
    if (atTag(toks, i, .dollar)) {
        try buf.append(arena, '$');
        i += 1;
    }
    if (i >= toks.len or toks[i].tag != .name)
        return diags.fail(error.ParseError, def_line, "PROC FORMAT: nested-format label [..] requires a format name", .{});
    try buf.appendSlice(arena, toks[i].text);
    i += 1;
    if (atTag(toks, i, .dot)) { // trailing `.` of `name.`
        try buf.append(arena, '.');
        i += 1;
    }
    if (i < toks.len and toks[i].tag == .number) { // `.d` lexes as one number token
        try buf.appendSlice(arena, toks[i].text);
        i += 1;
    }
    if (!atTag(toks, i, .rbrace))
        return diags.fail(error.ParseError, def_line, "PROC FORMAT: malformed nested-format label — expected [fmtname<w.d>]", .{});
    i += 1; // past `]`
    ip.* = i;
    return buf.items;
}

/// SAS rejects overlapping VALUE ranges at compile time unless MULTILABEL is set
/// ("ERROR: These two ranges overlap"); opensas installed them and resolved
/// first-match with no diagnostic (BUG-fmtoverlap). Sorted-adjacent disjointness
/// is exactly the PERF-fmtrangescan criterion (format.zig sortedRanges): touching
/// endpoints overlap unless an exclusion flag separates them. OTHER= entries are
/// exempt (they match only after every range misses).
/// ponytail: char-key duplicates/char-range overlaps and CNTLIN-built formats are
/// unchecked — SAS errors on the former too; add when a study hits either.
fn checkValueOverlap(diags: *diag.Diagnostics, fname: []const u8, entries: []const format.UserFmtEntry, def_line: usize) diag.Error!void {
    const s = try diags.arena.alloc(format.UserFmtEntry, entries.len);
    var n: usize = 0;
    for (entries) |e| if (!e.is_other) {
        s[n] = e;
        n += 1;
    };
    const r = s[0..n];
    std.mem.sort(format.UserFmtEntry, r, {}, struct {
        fn lt(_: void, x: format.UserFmtEntry, y: format.UserFmtEntry) bool {
            return if (x.lo != y.lo) x.lo < y.lo else x.hi < y.hi;
        }
    }.lt);
    var k: usize = 0;
    while (k + 1 < r.len) : (k += 1) {
        const p = r[k];
        const c = r[k + 1];
        if (!(p.hi < c.lo or (p.hi == c.lo and (p.hi_excl or c.lo_excl))))
            return diags.fail(error.ParseError, def_line, "PROC FORMAT: ranges of format {s} overlap (only legal under the MULTILABEL option, which is not supported)", .{fname});
    }
}

/// CNTLOUT= — dump the catalog to a control dataset, the inverse of appendCntlin
/// (BUG-fmtcntlout): columns FMTNAME, START, END, LABEL (all char, bound values
/// as their text) plus TYPE ('C' char / 'P' picture / '' numeric) and HLO
/// ('L'/'H' open ends — both for `low-high` — 'O' OTHER). A nested-format label
/// dumps in its source bracket form `[spec]`.
/// ponytail: no SEXCL/EEXCL columns, so exclusive-endpoint flags don't round-trip
/// through CNTLIN= — add when a study needs it.
fn dumpCntlout(arena: std.mem.Allocator, lib: *Library, name: []const u8, cats: []const format.UserFmt) diag.Error!void {
    const ds = try arena.create(Dataset);
    ds.* = Dataset.init(arena, name);
    inline for (.{ "FMTNAME", "START", "END", "LABEL", "TYPE", "HLO" }) |n| _ = try ds.addColumn(n, .char);
    for (cats) |uf| {
        const ty: []const u8 = if (uf.is_char) "C" else if (uf.is_picture) "P" else "";
        for (uf.entries) |e| {
            var start: []const u8 = "";
            var end: []const u8 = "";
            var hlo_buf: [2]u8 = undefined;
            var hlo_len: usize = 0;
            if (e.is_other) {
                hlo_buf[hlo_len] = 'O';
                hlo_len += 1;
            } else if (uf.is_char) {
                start = e.skey;
                end = if (e.skey_hi.len > 0) e.skey_hi else e.skey;
            } else {
                if (std.math.isInf(e.lo) and e.lo < 0) {
                    hlo_buf[hlo_len] = 'L';
                    hlo_len += 1;
                } else start = try std.fmt.allocPrint(arena, "{d}", .{e.lo});
                if (std.math.isInf(e.hi) and e.hi > 0) {
                    hlo_buf[hlo_len] = 'H';
                    hlo_len += 1;
                } else end = try std.fmt.allocPrint(arena, "{d}", .{e.hi});
            }
            const label = if (e.nested) try std.fmt.allocPrint(arena, "[{s}]", .{e.label}) else e.label;
            try ds.appendRow(&.{ strV(uf.name), strV(start), strV(end), strV(label), strV(ty), strV(hlo_buf[0..hlo_len]) });
        }
    }
    try lib.put(name, ds);
}

/// Build user formats from a CNTLIN= control dataset and append them to `cats`.
/// Standard CDISC/SAS layout: one row per range with columns FMTNAME, START, END,
/// LABEL, and optional TYPE ('C'→char keys, 'P'→PICTURE — the label is a digit
/// template, not a literal: BUG-cntlinpicture) and HLO ('L'/'H'→low/high open ends,
/// 'O'→OTHER). SEXCL/EEXCL='Y' mark an exclusive start/end endpoint (`0-<5`).
/// Rows sharing a FMTNAME group into one format (GAP-permformat).
fn appendCntlin(arena: std.mem.Allocator, lib: *Library, name: []const u8, cats: *std.ArrayList(format.UserFmt)) diag.Error!void {
    const ds = lib.find(name) orelse {
        unsupported("PROC FORMAT: CNTLIN dataset not found");
        return;
    };
    const i_fmt = ds.indexOf("fmtname") orelse {
        unsupported("PROC FORMAT: CNTLIN dataset has no FMTNAME column");
        return;
    };
    const i_start = ds.indexOf("start");
    const i_end = ds.indexOf("end");
    const i_label = ds.indexOf("label");
    const i_type = ds.indexOf("type");
    const i_hlo = ds.indexOf("hlo");
    const i_sexcl = ds.indexOf("sexcl");
    const i_eexcl = ds.indexOf("eexcl");

    const Group = struct { name: []const u8, is_char: bool, is_picture: bool, entries: std.ArrayList(format.UserFmtEntry) };
    var groups: std.ArrayList(Group) = .empty;
    for (ds.rows.items) |row| {
        const fname = std.mem.trimEnd(u8, cellStr(row, i_fmt), " ");
        if (fname.len == 0) continue;
        const ty = cellStr(row, i_type);
        const is_char = ty.len > 0 and (ty[0] == 'C' or ty[0] == 'c');
        // TYPE='P' — rebuild the same representation parsePicture installs
        // (is_picture UserFmt + numeric-range entries whose label is the digit
        // template). PREFIX=/MULT= don't round-trip (CNTLOUT doesn't dump them);
        // the template's implicit decimal-point mult does (renderPicture).
        const is_picture = ty.len > 0 and (ty[0] == 'P' or ty[0] == 'p');
        var gi: usize = groups.items.len;
        for (groups.items, 0..) |g, k| if (eqi(g.name, fname)) {
            gi = k;
            break;
        };
        if (gi == groups.items.len)
            try groups.append(arena, .{ .name = try arena.dupe(u8, fname), .is_char = is_char, .is_picture = is_picture, .entries = .empty });

        var e: format.UserFmtEntry = .{ .label = if (i_label) |il| try arena.dupe(u8, std.mem.trimEnd(u8, cellStr(row, il), " ")) else "" };
        // SEXCL/EEXCL='Y' — exclusive range endpoints, read-side twin of the
        // dumpCntlout ponytail (BUG-cntlinpicture). Without these an exclusive
        // range (`0-<5`) rebuilds INCLUSIVE and a shared boundary maps to the
        // wrong side. Same flags parseNumRange sets for a direct definition.
        if (hasCharCI(cellStr(row, i_sexcl), 'Y')) e.lo_excl = true;
        if (hasCharCI(cellStr(row, i_eexcl), 'Y')) e.hi_excl = true;
        const hlo = cellStr(row, i_hlo);
        if (hasCharCI(hlo, 'O')) {
            e.is_other = true;
        } else if (is_char) {
            e.skey = try arena.dupe(u8, std.mem.trimEnd(u8, cellStr(row, i_start), " "));
            const endk = std.mem.trimEnd(u8, cellStr(row, i_end), " ");
            if (endk.len > 0 and !std.mem.eql(u8, endk, e.skey)) e.skey_hi = try arena.dupe(u8, endk);
        } else {
            e.lo = if (hasCharCI(hlo, 'L')) -std.math.inf(f64) else if (i_start) |is| toNum(row[is]) else 0;
            e.hi = if (hasCharCI(hlo, 'H')) std.math.inf(f64) else if (i_end) |ie| toNum(row[ie]) else e.lo;
        }
        try groups.items[gi].entries.append(arena, e);
    }
    for (groups.items) |*g|
        try cats.append(arena, .{ .name = g.name, .is_char = g.is_char, .is_picture = g.is_picture, .entries = try g.entries.toOwnedSlice(arena) });
}

/// A control-dataset cell as a string ("" for a numeric cell or a missing column).
fn cellStr(row: []const Value, idx: ?usize) []const u8 {
    const i = idx orelse return "";
    return switch (row[i]) {
        .str => |s| s,
        .num => "",
    };
}

/// Case-insensitive: does `s` contain `c` (given upper-case)?
fn hasCharCI(s: []const u8, c: u8) bool {
    for (s) |ch| if (std.ascii.toUpper(ch) == c) return true;
    return false;
}

/// A range endpoint (`low`/`high` → ±inf, or a number with an optional leading
/// `-` — `-5--1` is a legal range), advancing `i` past it.
fn rangeVal(toks: []const Token, i: *usize) f64 {
    var sign: f64 = 1;
    if (atTag(toks, i.*, .minus)) {
        sign = -1;
        i.* += 1;
    }
    // Truncated range (`value v 65 -` at EOF, BUG-formatnumrangecrash): never
    // index past end / consume the eof or `;` terminator — leave `i` ON it so
    // the caller's error branch fails loud on a token that's in bounds.
    if (i.* >= toks.len or toks[i.*].tag == .eof or toks[i.*].tag == .semicolon) return 0;
    const v = if (tkKw(toks[i.*], "low")) -std.math.inf(f64) else if (tkKw(toks[i.*], "high")) std.math.inf(f64) else std.fmt.parseFloat(f64, toks[i.*].text) catch 0;
    i.* += 1;
    return sign * v;
}

/// Parse a `n` / `lo-hi` numeric range (with `<` exclusion and `low`/`high` opens)
/// into `e`, advancing `i` past it. Shared by VALUE and PICTURE (both range the
/// same way; only the RHS differs — a label vs a digit template).
fn parseNumRange(toks: []const Token, i: *usize, e: *format.UserFmtEntry) void {
    e.lo = rangeVal(toks, i);
    if (atTag(toks, i.*, .lt)) { // `n<-m` — low endpoint EXCLUDED
        e.lo_excl = true;
        i.* += 1;
    }
    if (atTag(toks, i.*, .minus)) { // `lo-hi`
        i.* += 1;
        if (atTag(toks, i.*, .lt)) { // `n-<m` — high endpoint EXCLUDED
            e.hi_excl = true;
            i.* += 1;
        }
        if (i.* < toks.len) e.hi = rangeVal(toks, i);
    } else e.hi = e.lo;
}

// `picture NAME range='template' [(prefix='..' mult=n)] … ;` — a numeric digit-selector
// format (PICTURE-format). Ranges parse exactly like VALUE; the RHS is a template
// applied to the value at render time (format.renderPicture). FAIL LOUD on the parts
// v1 doesn't do: `$char` pictures, date-directive templates (`%Y` etc.), and any
// option beyond PREFIX=/MULT= — never a silent wrong render.
fn parsePicture(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, ip: *usize, cats: *std.ArrayList(format.UserFmt)) diag.Error!void {
    var i = ip.*;
    i += 1; // past `picture`
    if (atTag(toks, i, .dollar))
        // `picture $NAME` — character picture formats are valid SAS 9.4 → gap.
        return failGap(diags, toks[i].line, "PROC FORMAT: character ($) PICTURE formats are not supported", .{});
    if (i >= toks.len or toks[i].tag != .name) {
        ip.* = i;
        return;
    }
    const fname = toks[i].text;
    i += 1;
    // `picture NAME (format-options) range='template' …` — the POSITION-1
    // option group (the doc's syntax: `PICTURE name <(format-options)>`).
    // It used to fall to the ENTRY catch-all: rc 1 with the degenerate
    // `unsupported PICTURE entry ''` (the lparen token's empty text) on
    // options the doc explicitly allows there. Split per the closed set: a
    // documented name failGaps (rc 2), anything else errors (rc 1) — both
    // NAMED. A name right after `=` is a VALUE, not an option — skip it.
    if (atTag(toks, i, .lparen)) {
        i += 1;
        while (i < toks.len and toks[i].tag != .rparen and toks[i].tag != .semicolon and toks[i].tag != .eof) {
            if (toks[i].tag == .name and toks[i - 1].tag != .eq) {
                if (isPicturePos1Option(toks[i].text))
                    return failGap(diags, toks[i].line, "PROC FORMAT: PICTURE format option {s} is not supported (position-1 options DEFAULT=/FUZZ=/MAX=/MIN=/MULTILABEL/NOTSORTED/ROUND are not honoured)", .{toks[i].text});
                return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: PICTURE format option {s} is not supported (position-1 options DEFAULT=/FUZZ=/MAX=/MIN=/MULTILABEL/NOTSORTED/ROUND are not honoured)", .{toks[i].text});
            }
            i += 1;
        }
        if (atTag(toks, i, .rparen)) i += 1;
    }
    var entries: std.ArrayList(format.UserFmtEntry) = .empty;
    while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) {
        var e: format.UserFmtEntry = .{ .label = "" };
        if (tkKw(toks[i], "other")) {
            e.is_other = true;
            i += 1;
        } else if (toks[i].tag == .number or tkKw(toks[i], "low") or tkKw(toks[i], "high") or
            (atTag(toks, i, .minus) and i + 1 < toks.len and toks[i + 1].tag == .number))
        {
            parseNumRange(toks, &i, &e);
        } else {
            return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: unsupported PICTURE entry '{s}' (entries are number/low/high ranges)", .{toks[i].text});
        }
        if (atTag(toks, i, .eq)) i += 1;
        if (atTag(toks, i, .string)) {
            e.label = toks[i].text;
            i += 1;
        } else return diags.fail(error.ParseError, toks[i -| 1].line, "PROC FORMAT: PICTURE range requires ='template'", .{});
        if (std.mem.indexOfScalar(u8, e.label, '%')) |p| {
            if (p + 1 < e.label.len and std.ascii.isAlphabetic(e.label[p + 1]))
                // A `%x` template is valid SAS either way (a DATATYPE= directive,
                // or a literal without DATATYPE=) → our refusal is a gap (rc 2).
                return failGap(diags, toks[i -| 1].line, "PROC FORMAT: date-directive PICTURE templates (%Y/%m/… via DATATYPE=) are not supported", .{});
        }
        // Optional `(prefix='..' mult=n round)` options.
        if (atTag(toks, i, .lparen)) {
            i += 1;
            while (i < toks.len and toks[i].tag != .rparen and toks[i].tag != .semicolon and toks[i].tag != .eof) {
                if (tkKw(toks[i], "prefix")) {
                    i += 1;
                    if (atTag(toks, i, .eq)) i += 1;
                    if (atTag(toks, i, .string)) {
                        e.prefix = toks[i].text;
                        i += 1;
                    }
                } else if (tkKw(toks[i], "mult") or tkKw(toks[i], "multiplier")) {
                    i += 1;
                    if (atTag(toks, i, .eq)) i += 1;
                    if (i < toks.len and toks[i].tag == .number) {
                        e.mult = std.fmt.parseFloat(f64, toks[i].text) catch 1;
                        i += 1;
                    }
                } else if (tkKw(toks[i], "round")) {
                    e.round = true; // GAP-pictureround: round, don't truncate
                    i += 1;
                } else if (isPictureGapOption(toks[i].text))
                    // a documented per-entry picture option (rc 2), same body
                    return failGap(diags, toks[i].line, "PROC FORMAT: PICTURE option {s}= is not supported (only PREFIX=, MULT=, ROUND)", .{toks[i].text})
                else return diags.fail(error.ParseError, toks[i].line, "PROC FORMAT: PICTURE option {s}= is not supported (only PREFIX=, MULT=, ROUND)", .{toks[i].text});
            }
            if (atTag(toks, i, .rparen)) i += 1;
        }
        try entries.append(arena, e);
    }
    try cats.append(arena, .{ .name = fname, .is_char = false, .is_picture = true, .entries = try entries.toOwnedSlice(arena) });
    ip.* = i;
}

test "PROC FORMAT CNTLIN builds a value format resolved at apply time (GAP-permformat)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    format.clearUserFormats();
    defer format.clearUserFormats();

    // Control dataset (as a codelist-format macro builds from a codelist CSV): a VISNUM
    // value format — 1="Screening", 2-3="Treatment", other="Other".
    var lib = Library.init(a);
    const ctl = try a.create(Dataset);
    ctl.* = Dataset.init(a, "ctl");
    inline for (.{ "FMTNAME", "LABEL", "HLO" }) |n| _ = try ctl.addColumn(n, .char);
    inline for (.{ "START", "END" }) |n| _ = try ctl.addColumn(n, .num);
    // rows: FMTNAME, LABEL, HLO, START, END
    try ctl.rows.append(a, &.{ strV("VISNUM"), strV("Screening"), strV(""), numV(1), numV(1) });
    try ctl.rows.append(a, &.{ strV("VISNUM"), strV("Treatment"), strV(""), numV(2), numV(3) });
    try ctl.rows.append(a, &.{ strV("VISNUM"), strV("Other"), strV("O"), numV(0), numV(0) });
    try lib.put("ctl", ctl);

    const toks = try lex.tokenize(a, "proc format library=lib cntlin=ctl; run;", &diags);
    try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    // The named format resolves at apply time from the (process-wide) catalog.
    try t.expectEqualStrings("Screening", try format.apply(a, numV(1), "VISNUM."));
    try t.expectEqualStrings("Treatment", try format.apply(a, numV(2), "VISNUM."));
    try t.expectEqualStrings("Treatment", try format.apply(a, numV(3), "VISNUM."));
    try t.expectEqualStrings("Other", try format.apply(a, numV(9), "VISNUM.")); // OTHER catch-all
}

test "PROC FORMAT installs a VALUE catalog that format.apply decodes (BUG-userformat)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    const src =
        \\proc format;
        \\  value sexf 1="Male" 2="Female" other="Unknown";
        \\  value agec 0-17="Minor" 18-high="Adult";
        \\  value $yn "Y"="Yes" "N"="No";
        \\run;
    ;
    const toks = try lex.tokenize(a, src, &diags);
    format.clearUserFormats();
    defer format.clearUserFormats();
    var lib = Library.init(a);
    try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    try t.expectEqualStrings("Male", try format.apply(a, .{ .num = 1 }, "sexf."));
    try t.expectEqualStrings("Female", try format.apply(a, .{ .num = 2 }, "sexf."));
    try t.expectEqualStrings("Unknown", try format.apply(a, .{ .num = 9 }, "sexf.")); // OTHER
    try t.expectEqualStrings("Minor", try format.apply(a, .{ .num = 5 }, "agec."));
    try t.expectEqualStrings("Adult", try format.apply(a, .{ .num = 90 }, "agec.")); // 18-high
    try t.expectEqualStrings("Yes", try format.apply(a, .{ .str = "Y" }, "$yn."));
    try t.expectEqualStrings("No", try format.apply(a, .{ .str = "N" }, "$yn."));
}

test "PROC FORMAT nested-format label =[fmtname] renders via the named format (BUG-fmtnestlabel)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    const src =
        \\proc format;
        \\  value bnest low-<100=[dollar8.2] 100-high='big';
        \\  value nbr -5--1='neg' 0='zero' 1-high=[best.];
        \\run;
    ;
    const toks = try lex.tokenize(a, src, &diags);
    format.clearUserFormats();
    defer format.clearUserFormats();
    var lib = Library.init(a);
    try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
    try t.expect(!diags.hasErrors());

    // The bracketed format renders the value at apply time (SAS directed formatting).
    try t.expectEqualStrings("  $42.50", try format.apply(a, numV(42.5), "bnest.")); // dollar8.2
    try t.expectEqualStrings("big", try format.apply(a, numV(150), "bnest."));
    try t.expectEqualStrings("neg", try format.apply(a, numV(-3), "nbr.")); // negative range
    try t.expectEqualStrings("zero", try format.apply(a, numV(0), "nbr."));
    try t.expectEqualStrings("42.5", try format.apply(a, numV(42.5), "nbr.")); // [best.]
}

test "PROC FORMAT fail-loud: INVALUE / unknown statement / (multilabel) / overlap (BUG-fmtprocbatch)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    format.clearUserFormats();
    defer format.clearUserFormats();

    // INVALUE — custom informats are a loud GAP at the definition site, not a
    // silent drop that fails only at the later INPUT (BUG-fmtinvalue).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; invalue mynum 'one'=1; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "invalue") != null);
    }
    // Any other unrecognized statement (SELECT/EXCLUDE/FMTLIB/…) — same loud else.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; select sexf; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "select") != null);
    }
    // (multilabel) VALUE option — not silently dropped (BUG-fmtmultilabel).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value agec (multilabel) 0-29='Y' 0-59='U'; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "multilabel") != null);
    }
    // Overlapping ranges error like SAS without MULTILABEL (BUG-fmtoverlap).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value bad 0-29='Young' 0-59='Under60'; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "overlap") != null);
    }
    // Touching endpoints overlap too (0-5 and 5-10 share 5); an exclusion
    // flag separates them and stays legal.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value t 0-5='a' 5-10='b'; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    }
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value ok 0-<5='a' 5-10='b'; run;", &diags);
        try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
        try t.expect(!diags.hasErrors());
    }
    // A '.' missing key errors instead of being silently dropped.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value m .='miss' 0='zero'; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    }
}

test "PROC FORMAT: truncated numeric range fails loud, never crashes (BUG-formatnumrangecrash)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    format.clearUserFormats();
    defer format.clearUserFormats();

    // `65 -` at EOF — rangeVal must not index/consume past the last token
    // (qa tick174 F-3: this SIGABRTed on an OOB token read).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value v 65 -", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(diags.hasErrors());
    }
    // Same truncation right before the statement's `;`.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value v 65 - ; run;", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    }
    // `65 - -` at EOF — rangeVal's own sign branch at end-of-tokens.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value v 65 - -", &diags);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    }
    // Valid ranges — including negative endpoints (`-5--1`, both minus paths) —
    // are byte-identical.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const toks = try lex.tokenize(a, "proc format; value v 65-70='x' -5--1='n' other='o'; run;", &diags);
        try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
        try t.expect(!diags.hasErrors());
    }
}

test "PROC FORMAT CNTLOUT= dumps the catalog and CNTLIN= round-trips it (BUG-fmtcntlout)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    format.clearUserFormats();
    defer format.clearUserFormats();
    var lib = Library.init(a);

    const toks1 = try lex.tokenize(a, "proc format; value sexf 1='Male' 2='Female'; value agec low-17='Minor' 18-high='Adult'; run;", &diags);
    try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks1);
    const toks2 = try lex.tokenize(a, "proc format cntlout=fmtout; run;", &diags);
    try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks2);
    try t.expect(!diags.hasErrors());

    const ds = lib.find("fmtout").?;
    try t.expectEqual(@as(usize, 4), ds.rows.items.len); // 2 sexf + 2 agec entries
    const i_label = ds.indexOf("label").?;
    const i_start = ds.indexOf("start").?;
    const i_hlo = ds.indexOf("hlo").?;
    try t.expectEqualStrings("Male", cellStr(ds.rows.items[0], i_label));
    try t.expectEqualStrings("1", cellStr(ds.rows.items[0], i_start));
    try t.expectEqualStrings("L", cellStr(ds.rows.items[2], i_hlo)); // agec low-17
    try t.expectEqualStrings("H", cellStr(ds.rows.items[3], i_hlo)); // agec 18-high

    // The dump re-reads through CNTLIN= (inverse): same decodes.
    format.clearUserFormats();
    const toks3 = try lex.tokenize(a, "proc format cntlin=fmtout; run;", &diags);
    try runFormat(.{ .arena = a, .lib = &lib, .diags = &diags }, toks3);
    try t.expectEqualStrings("Female", try format.apply(a, numV(2), "sexf."));
    try t.expectEqualStrings("Minor", try format.apply(a, numV(5), "agec."));
    try t.expectEqualStrings("Adult", try format.apply(a, numV(90), "agec."));
}

test "PROC DATASETS: APPEND, MODIFY RENAME, DELETE, CHANGE (CLIN-datasets)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    inline for (.{ "base", "extra" }) |nm| {
        const d = try a.create(Dataset);
        d.* = Dataset.init(a, nm);
        _ = try d.addColumn("id", .num);
        _ = try d.addColumn("x", .num);
        try lib.put(nm, d);
    }
    try lib.find("base").?.rows.append(a, &.{ .{ .num = 1 }, .{ .num = 10 } });
    try lib.find("extra").?.rows.append(a, &.{ .{ .num = 2 }, .{ .num = 20 } });
    const tmp = try a.create(Dataset);
    tmp.* = Dataset.init(a, "tmp");
    _ = try tmp.addColumn("id", .num);
    try lib.put("tmp", tmp);

    const src =
        \\proc datasets library=work nolist;
        \\  append base=base data=extra;
        \\  modify base; rename x=score;
        \\  delete tmp;
        \\  change base=combined;
        \\quit;
    ;
    const toks = try lex.tokenize(a, src, &diags);
    var out: std.ArrayList(u8) = .empty;
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    try t.expect(lib.find("tmp") == null); // DELETE dropped it
    try t.expect(lib.find("base") == null); // CHANGE renamed it away
    const c = lib.find("combined").?; // change base=combined
    try t.expectEqual(@as(usize, 2), c.rows.items.len); // APPEND added extra's row
    try t.expect(c.indexOf("score") != null); // MODIFY RENAME x=score
    try t.expect(c.indexOf("x") == null);
}

test "PROC APPEND: in-place append, FORCE reconcile, loud mismatch (FEAT-procappend)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const base = try a.create(Dataset);
    base.* = Dataset.init(a, "base");
    _ = try base.addColumn("id", .num);
    _ = try base.addColumn("x", .num);
    try base.appendRow(&.{ numV(1), numV(10) });
    try lib.put("base", base);
    const extra = try a.create(Dataset);
    extra.* = Dataset.init(a, "extra");
    _ = try extra.addColumn("id", .num);
    _ = try extra.addColumn("x", .num);
    try extra.appendRow(&.{ numV(2), numV(20) });
    try lib.put("extra", extra);

    // same-structure append; the two-level work. name resolves to the WORK member
    const toks = try lex.tokenize(a, "proc append base=work.base data=extra; run;", &diags);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
    try t.expectEqual(@as(usize, 2), lib.find("base").?.rows.items.len);
    try t.expectEqual(@as(f64, 20), lib.find("base").?.rows.items[1][1].num);

    // DATA= with an extra variable and NO force → ERROR, nothing appended
    const wide = try a.create(Dataset);
    wide.* = Dataset.init(a, "wide");
    _ = try wide.addColumn("id", .num);
    _ = try wide.addColumn("y", .char);
    try wide.appendRow(&.{ numV(3), strV("z") });
    try lib.put("wide", wide);
    const toks2 = try lex.tokenize(a, "proc append base=base data=wide; run;", &diags);
    try t.expectError(error.ExecError, runAppend(.{ .arena = a, .lib = &lib, .diags = &diags }, toks2));
    try t.expect(diags.hasErrors()); // the captured reporter holds the ERROR
    try t.expectEqual(@as(usize, 2), lib.find("base").?.rows.items.len); // not appended

    // FORCE: the extra var is dropped with a warning; BASE-only var → missing
    var diags2 = diag.Diagnostics.init(a);
    const toks3 = try lex.tokenize(a, "proc append base=base data=wide force; run;", &diags2);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags2 }, toks3);
    const b3 = lib.find("base").?;
    try t.expectEqual(@as(usize, 3), b3.rows.items.len);
    try t.expectEqual(@as(f64, 3), b3.rows.items[2][0].num);
    try t.expect(std.math.isNan(b3.rows.items[2][1].num)); // x not in DATA= → missing
    var warned = false;
    for (diags2.list.items) |d| if (d.severity == .warning) {
        warned = true;
    };
    try t.expect(warned);

    // FORCE type conflict (char DATA= var vs num BASE= var) → missing + warning
    const clash = try a.create(Dataset);
    clash.* = Dataset.init(a, "clash");
    _ = try clash.addColumn("id", .num);
    _ = try clash.addColumn("x", .char);
    try clash.appendRow(&.{ numV(4), strV("oops") });
    try lib.put("clash", clash);
    var diags3 = diag.Diagnostics.init(a);
    const toks4 = try lex.tokenize(a, "proc append base=base data=clash force; run;", &diags3);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags3 }, toks4);
    const b4 = lib.find("base").?;
    try t.expectEqual(@as(usize, 4), b4.rows.items.len);
    try t.expect(std.math.isNan(b4.rows.items[3][1].num)); // incompatible → missing
    // …and the same conflict WITHOUT force errors instead
    var diags4 = diag.Diagnostics.init(a);
    const toks5 = try lex.tokenize(a, "proc append base=base data=clash; run;", &diags4);
    try t.expectError(error.ExecError, runAppend(.{ .arena = a, .lib = &lib, .diags = &diags4 }, toks5));
    try t.expectEqual(@as(usize, 4), lib.find("base").?.rows.items.len);
}

test "PROC APPEND length mismatch: no-FORCE ERROR, FORCE reconciles at the store (BUG-appendcharwidth)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    // BASE=: s Char 3, n Num 5 — declared widths on both types.
    const base = try a.create(Dataset);
    base.* = Dataset.init(a, "base");
    _ = try base.addColumn("s", .char);
    _ = try base.addColumn("n", .num);
    base.setLen("s", 3);
    base.setLen("n", 5);
    try base.appendRow(&.{ strV("abc"), numV(1.5) });
    try lib.put("base", base);

    // DATA= LONGER on both (s Char 8, n Num 8), no FORCE → ERROR, nothing
    // appended (Procedures Guide, APPEND Stmt p.588: "longer than the
    // variables in the BASE= data set" is the third FORCE criterion).
    const wide = try a.create(Dataset);
    wide.* = Dataset.init(a, "wide");
    _ = try wide.addColumn("s", .char);
    _ = try wide.addColumn("n", .num);
    wide.setLen("s", 8);
    try wide.appendRow(&.{ strV("abcdefgh"), numV(36.6) });
    try lib.put("wide", wide);
    const toks = try lex.tokenize(a, "proc append base=base data=wide; run;", &diags);
    try t.expectError(error.ExecError, runAppend(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    try t.expect(diags.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("base").?.rows.items.len); // not appended

    // FORCE → warning, and the STORE reconciles to the BASE= length (doc
    // p.595: "The length of the variables in the BASE= data set takes
    // precedence"): s holds 'abc' — never 8 bytes under a Char 3 descriptor —
    // and n holds the len-5 truncation of 36.6; the descriptors don't move.
    var diags2 = diag.Diagnostics.init(a);
    const toks2 = try lex.tokenize(a, "proc append base=base data=wide force; run;", &diags2);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags2 }, toks2);
    const b2 = lib.find("base").?;
    try t.expectEqual(@as(usize, 2), b2.rows.items.len);
    try t.expectEqualStrings("abc", b2.rows.items[1][0].str);
    try t.expectEqual(Pdv.truncNum(36.6, 5), b2.rows.items[1][1].num);
    try t.expectEqual(@as(?usize, 3), b2.columns.items[0].len);
    try t.expectEqual(@as(?usize, 5), b2.columns.items[1].len);
    var warned = false;
    for (diags2.list.items) |d| if (d.severity == .warning) {
        warned = true;
    };
    try t.expect(warned);

    // shorter DATA= (Char 3 into Char 8) needs no FORCE and stores as-is —
    // char storage is dynamic, so the doc's "pad" is a no-op.
    const tall = try a.create(Dataset);
    tall.* = Dataset.init(a, "tall");
    _ = try tall.addColumn("s", .char);
    tall.setLen("s", 8);
    try tall.appendRow(&.{strV("abcdefgh")});
    try lib.put("tall", tall);
    const short = try a.create(Dataset);
    short.* = Dataset.init(a, "short");
    _ = try short.addColumn("s", .char);
    short.setLen("s", 3);
    try short.appendRow(&.{strV("pq")});
    try lib.put("short", short);
    var diags3 = diag.Diagnostics.init(a);
    const toks3 = try lex.tokenize(a, "proc append base=tall data=short; run;", &diags3);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags3 }, toks3);
    try t.expect(!diags3.hasErrors());
    const b3 = lib.find("tall").?;
    try t.expectEqual(@as(usize, 2), b3.rows.items.len);
    try t.expectEqualStrings("pq", b3.rows.items[1][0].str);

    // an untracked-width DATA= column (len null) holding a wider cell: no
    // declared mismatch to gate, but the store still clips to the descriptor —
    // the cell must not disagree with it (2a4a2b6a).
    const raw = try a.create(Dataset);
    raw.* = Dataset.init(a, "raw");
    _ = try raw.addColumn("s", .char); // len null
    try raw.appendRow(&.{strV("abcdefgh")});
    try lib.put("raw", raw);
    var diags4 = diag.Diagnostics.init(a);
    const toks4 = try lex.tokenize(a, "proc append base=tall data=raw; run;", &diags4);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags4 }, toks4);
    const b4 = lib.find("tall").?;
    try t.expectEqual(@as(usize, 3), b4.rows.items.len);
    try t.expectEqualStrings("abcdefgh", b4.rows.items[2][0].str); // fits Char 8
    const toks5 = try lex.tokenize(a, "proc append base=base data=raw; run;", &diags4);
    // Char 8 into Char 3 with NO declared DATA= width: appends, store clips.
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags4 }, toks5);
    const b5 = lib.find("base").?;
    try t.expectEqualStrings("abc", b5.rows.items[b5.rows.items.len - 1][0].str);
}

test "PROC DATASETS APPEND type-checks + FORCE-gates like PROC APPEND (BUG-datasetsappendtype)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const base = try a.create(Dataset);
    base.* = Dataset.init(a, "base");
    _ = try base.addColumn("x", .num);
    try base.appendRow(&.{numV(1)});
    try lib.put("base", base);
    const add = try a.create(Dataset);
    add.* = Dataset.init(a, "add");
    _ = try add.addColumn("x", .char);
    try add.appendRow(&.{strV("hello")});
    try lib.put("add", add);

    var out: std.ArrayList(u8) = .empty;
    // char DATA= var vs num BASE= var, no FORCE → captured ERROR, base untouched
    // (the old dsAppend landed 'hello' in numeric x with no diagnostic at all).
    const toks = try lex.tokenize(a, "proc datasets lib=work nolist; append base=base data=add; quit;", &diags);
    try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
    try t.expect(diags.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("base").?.rows.items.len);
    try t.expectEqual(@as(f64, 1), lib.find("base").?.rows.items[0][0].num);

    // FORCE → appends with the incompatible value missing + a warning
    var diags2 = diag.Diagnostics.init(a);
    const toks2 = try lex.tokenize(a, "proc datasets lib=work nolist; append base=base data=add force; quit;", &diags2);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags2 }, &out, toks2);
    const b2 = lib.find("base").?;
    try t.expectEqual(@as(usize, 2), b2.rows.items.len);
    try t.expect(std.math.isNan(b2.rows.items[1][0].num));
    var warned = false;
    for (diags2.list.items) |d| if (d.severity == .warning) {
        warned = true;
    };
    try t.expect(warned);

    // matching types append cleanly, no diagnostic
    const more = try a.create(Dataset);
    more.* = Dataset.init(a, "more");
    _ = try more.addColumn("x", .num);
    try more.appendRow(&.{numV(2)});
    try lib.put("more", more);
    var diags3 = diag.Diagnostics.init(a);
    const toks3 = try lex.tokenize(a, "proc datasets lib=work nolist; append base=base data=more; quit;", &diags3);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags3 }, &out, toks3);
    const b3 = lib.find("base").?;
    try t.expectEqual(@as(usize, 3), b3.rows.items.len);
    try t.expectEqual(@as(f64, 2), b3.rows.items[2][0].num);
    try t.expect(!diags3.hasErrors());
}

test "PROC DATASETS/APPEND: CHANGE dup-name + MODIFY unknown-var fail loud; APPEND auto-creates BASE= (BUG-datasetschange)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;

    var lib = Library.init(a);
    const mk = struct {
        fn f(al: std.mem.Allocator, l: *Library, nm: []const u8, id: f64) !void {
            const d = try al.create(Dataset);
            d.* = Dataset.init(al, nm);
            _ = try d.addColumn("id", .num);
            _ = try d.addColumn("x", .num);
            try d.appendRow(&.{ numV(id), numV(id * 10) });
            try l.put(nm, d);
        }
    }.f;
    try mk(a, &lib, "a", 1);
    try mk(a, &lib, "b", 2);

    // F1: CHANGE a=b when b exists → captured ERROR; both members intact.
    const toks1 = try lex.tokenize(a, "proc datasets library=work nolist; change a=b; quit;", &diags);
    try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks1));
    try t.expect(diags.hasErrors());
    try t.expect(lib.find("a") != null);
    const b1 = lib.find("b").?;
    try t.expectEqual(@as(usize, 1), b1.rows.items.len);
    try t.expectEqual(@as(f64, 2), b1.rows.items[0][0].num); // b not shadowed/lost

    // F1: CHANGE to a FREE name still renames.
    var diags2 = diag.Diagnostics.init(a);
    const toks2 = try lex.tokenize(a, "proc datasets library=work nolist; change a=c; quit;", &diags2);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags2 }, &out, toks2);
    try t.expect(lib.find("a") == null);
    try t.expect(lib.find("c") != null);

    // F2: MODIFY RENAME/FORMAT/LABEL on a variable that doesn't exist → ERROR.
    inline for (.{ "rename nosuch=q", "format nosuch 8.", "label nosuch='x'" }) |stmt| {
        var d2 = diag.Diagnostics.init(a);
        const src = "proc datasets library=work nolist; modify b; " ++ stmt ++ "; quit;";
        const toks = try lex.tokenize(a, src, &d2);
        try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &d2 }, &out, toks));
        try t.expect(d2.hasErrors());
    }
    // F2: MODIFY of an existing var is unchanged.
    var diags3 = diag.Diagnostics.init(a);
    const toks3 = try lex.tokenize(a, "proc datasets library=work nolist; modify b; rename x=score; format score 8.2; label score='s'; quit;", &diags3);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags3 }, &out, toks3);
    try t.expect(lib.find("b").?.indexOf("score") != null);

    // F3: PROC APPEND with a non-existent BASE= auto-creates it as a copy of DATA=.
    var diags4 = diag.Diagnostics.init(a);
    const toks4 = try lex.tokenize(a, "proc append base=fresh data=b; run;", &diags4);
    try runAppend(.{ .arena = a, .lib = &lib, .diags = &diags4 }, toks4);
    const fresh = lib.find("fresh").?;
    try t.expectEqual(@as(usize, 1), fresh.rows.items.len);
    try t.expectEqual(@as(f64, 2), fresh.rows.items[0][0].num);
    try t.expect(fresh.indexOf("score") != null); // schema copied (post-rename)
    // F3: PROC DATASETS APPEND auto-creates too; appending again to the now-
    // existing base behaves as a normal append.
    var diags5 = diag.Diagnostics.init(a);
    const toks5 = try lex.tokenize(a, "proc datasets lib=work nolist; append base=fresh2 data=b; append base=fresh2 data=b; quit;", &diags5);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags5 }, &out, toks5);
    try t.expectEqual(@as(usize, 2), lib.find("fresh2").?.rows.items.len);
}

test "PROC DATASETS MODIFY: RENAME-to-existing fails loud; multi-var FORMAT applies one spec to all (BUG-datasetsrenamecollide + BUG-datasetsfmtmulti)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;

    const mk = struct {
        fn f(al: std.mem.Allocator, l: *Library) !*Dataset {
            const d = try al.create(Dataset);
            d.* = Dataset.init(al, "m");
            _ = try d.addColumn("a", .num);
            _ = try d.addColumn("b", .num);
            _ = try d.addColumn("c", .num);
            try d.appendRow(&.{ numV(1), numV(2), numV(3) });
            try l.put("m", d);
            return d;
        }
    }.f;

    // (1) RENAME x=y where y already exists → captured ERROR, no dup column.
    {
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; rename a=b; quit;", &diags);
        try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(diags.hasErrors());
        try t.expectEqual(@as(usize, 3), lib.find("m").?.columns.items.len); // no 2nd "b"
    }
    // (1) RENAME to a FREE name still works.
    {
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; rename a=z; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(lib.find("m").?.indexOf("z") != null);
        try t.expect(lib.find("m").?.indexOf("a") == null);
    }
    // (2) `format a b dollar8.2;` applies dollar8.2 to BOTH a and b, not to c.
    {
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; format a b dollar8.2; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expectEqualStrings("dollar8.2", ds.columns.items[ds.indexOf("a").?].format.?);
        try t.expectEqualStrings("dollar8.2", ds.columns.items[ds.indexOf("b").?].format.?);
        try t.expect(ds.columns.items[ds.indexOf("c").?].format == null);
    }
    // (2) bare numeric-width spec `format a b 8.2;` also spreads to both.
    {
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; format a b 8.2; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expectEqualStrings("8.2", ds.columns.items[ds.indexOf("a").?].format.?);
        try t.expectEqualStrings("8.2", ds.columns.items[ds.indexOf("b").?].format.?);
    }
    // (2) bare `format a b;` (no spec) still STRIPS both.
    {
        var lib = Library.init(a);
        const ds0 = try mk(a, &lib);
        ds0.columns.items[0].format = "8.2";
        ds0.columns.items[1].format = "8.2";
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; format a b; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expect(ds.columns.items[ds.indexOf("a").?].format == null);
        try t.expect(ds.columns.items[ds.indexOf("b").?].format == null);
    }
}

test "PROC DATASETS MODIFY: ATTRIB _all_ INFORMAT= strips informats; LENGTH= is loud (BUG-datasetsinformatstrip)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;

    // Two informatted columns + one bare, so a strip is distinguishable from
    // "there was nothing to strip" and a named-var strip from `_all_`.
    const mk = struct {
        fn f(al: std.mem.Allocator, l: *Library) !*Dataset {
            const d = try al.create(Dataset);
            d.* = Dataset.init(al, "m");
            _ = try d.addColumn("a", .num);
            _ = try d.addColumn("b", .num);
            _ = try d.addColumn("c", .char);
            d.columns.items[0].informat = "best8.";
            d.columns.items[0].format = "best8.";
            d.columns.items[1].informat = "comma6.";
            try d.appendRow(&.{ numV(1), numV(2), strV("x") });
            try l.put("m", d);
            return d;
        }
    }.f;

    // (1) THE DEFECT: `attrib _all_ informat=;` used to be a hard-coded no-op at
    // rc 0 — the format went, the informat stayed (Procedures Guide 7th ed.
    // pp.598/641: _ALL_ + an empty INFORMAT= is the documented removal idiom).
    {
        diag.resetGap(); // process-global: an earlier test's gap would leak in
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; attrib _all_ format=; attrib _all_ informat=; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        for (ds.columns.items) |c| {
            try t.expect(c.format == null);
            try t.expect(c.informat == null);
        }
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (2) A named-var INFORMAT= strip touches only that variable.
    {
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; attrib a informat=; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expect(ds.columns.items[ds.indexOf("a").?].informat == null);
        try t.expectEqualStrings("best8.", ds.columns.items[ds.indexOf("a").?].format.?); // FORMAT= untouched
        try t.expectEqualStrings("comma6.", ds.columns.items[ds.indexOf("b").?].informat.?);
    }
    // (3) A non-empty INFORMAT= SETS it, and rides alongside LABEL= in one ATTRIB.
    {
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; attrib b informat=8.2 label='Bee'; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expectEqualStrings("8.2", ds.columns.items[ds.indexOf("b").?].informat.?);
        try t.expectEqualStrings("Bee", ds.columns.items[ds.indexOf("b").?].label.?);
    }
    // (4) LENGTH= is not one of the three options ATTRIB takes inside DATASETS
    // (p.598) — captured ERROR, rc 1 (the user's SAS is wrong, not an opensas
    // gap), never the old silent drop. D-003: captured reporter, no child.
    {
        diag.resetGap();
        var lib = Library.init(a);
        _ = try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; attrib c length=20; quit;", &diags);
        try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "ATTRIB LENGTH= is not valid in the DATASETS procedure") != null);
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    diag.resetGap();
}

test "PROC DATASETS MODIFY: the LENGTH statement fails loud rc 1 (BUG-datasetslengthstmtnoop)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    const mk = struct {
        fn f(al: std.mem.Allocator, l: *Library) !void {
            const d = try al.create(Dataset);
            d.* = Dataset.init(al, "m");
            _ = try d.addColumn("c", .char);
            try d.appendRow(&.{strV("x")});
            try l.put("m", d);
        }
    }.f;

    // THE DEFECT: `length c $20;` inside MODIFY used to parse and silently
    // drop at rc 0 — the user believes a width change happened. Real SAS
    // REJECTS it: Base SAS 9.4 Procedures Guide 7th ed. printed p.563
    // (DATASETS restrictions): "You cannot change the length of a variable
    // using the LENGTH statement or the LENGTH= option in an ATTRIB
    // statement", and LENGTH is absent from MODIFY's p.576
    // subordinate-statement syntax diagram. Captured ERROR at rc 1 — the
    // user's SAS is wrong, the same verdict the ATTRIB LENGTH= arm reached
    // (D-009 / D-009b corollary). D-003: captured reporter, no child process.
    {
        diag.resetGap(); // process-global: an earlier test's gap would leak in
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; length c $20; quit;", &diags);
        try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "LENGTH statement is not valid in the DATASETS procedure") != null);
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // …and outside MODIFY it is no more valid — not a DATASETS statement at
    // all, so the same rc 1 (not the old "attribute statement outside MODIFY"
    // rc-2 gap arm).
    {
        diag.resetGap();
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; length c $20; quit;", &diags);
        try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    diag.resetGap();
}

test "PROC DATASETS MODIFY: the INFORMAT statement sets/strips informats (GAP-datasetsinformatstmt)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    const mk = struct {
        fn f(al: std.mem.Allocator, l: *Library) !void {
            const d = try al.create(Dataset);
            d.* = Dataset.init(al, "m");
            _ = try d.addColumn("a", .num);
            _ = try d.addColumn("b", .num);
            _ = try d.addColumn("c", .char);
            d.columns.items[0].informat = "best8.";
            d.columns.items[1].informat = "comma6.";
            try d.appendRow(&.{ numV(1), numV(2), strV("x") });
            try l.put("m", d);
        }
    }.f;

    // (1) ONE trailing spec applies to EVERY listed var (the FORMAT arm's
    // accepted shape, Procedures Guide 7th ed. printed p.640); a `$`-spec on
    // the char var rides the same statement list. Unlisted vars keep theirs.
    {
        diag.resetGap(); // process-global: an earlier test's gap would leak in
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; informat a b 8.2; informat c $2.; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expectEqualStrings("8.2", ds.columns.items[ds.indexOf("a").?].informat.?);
        try t.expectEqualStrings("8.2", ds.columns.items[ds.indexOf("b").?].informat.?);
        try t.expectEqualStrings("$2.", ds.columns.items[ds.indexOf("c").?].informat.?);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (2) No spec ⇒ strip (p.640: "removes any existing informats for the
    // variables in variable-list"); a named strip touches only that variable.
    {
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; informat b; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        try t.expectEqualStrings("best8.", ds.columns.items[ds.indexOf("a").?].informat.?);
        try t.expect(ds.columns.items[ds.indexOf("b").?].informat == null);
    }
    // (3) `informat _all_;` strips every column, like the FORMAT arm's `_all_`.
    {
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; informat _all_; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const ds = lib.find("m").?;
        for (ds.columns.items) |c| try t.expect(c.informat == null);
    }
    // (4) Unknown variable: the FORMAT/RENAME/LABEL arms' shared verdict —
    // captured ERROR "variable z not found", rc 1 (the user's SAS is wrong,
    // D-009 / D-009b corollary). D-003: captured reporter, no child process.
    {
        diag.resetGap();
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; modify m; informat z 8.; quit;", &diags);
        try t.expectError(error.ExecError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "variable z not found") != null);
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (5) Outside a MODIFY RUN group the statement is not valid (p.640
    // restriction) — the shared gap arm, rc 2 (GAP-dsmgmt family).
    {
        diag.resetGap();
        g_test_last_unsup = "";
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist; informat a 8.; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "attribute statement outside MODIFY") != null);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diags.hasErrors()));
        g_test_last_unsup = "";
    }
    diag.resetGap();
}

test "GAP-varcolonprefix-procs: `pfx:` expands in MEANS/FREQ/TABULATE (PDV order); empty match rc 1; crossing/expression loud rc 2" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    diag.resetGap(); // process-global: an earlier test's gap would leak into the rc-0 arms
    // Columns CREATED x2, x1, x10 — PDV order (x2 x1 x10) differs from
    // alphabetical (x1 x10 x2), and every happy path below must keep PDV
    // order (Language Reference: Concepts printed p.62).
    const mk = struct {
        fn f(al: std.mem.Allocator, l: *Library) !void {
            const d = try al.create(Dataset);
            d.* = Dataset.init(al, "t");
            _ = try d.addColumn("x2", .num);
            _ = try d.addColumn("x1", .num);
            _ = try d.addColumn("x10", .num);
            _ = try d.addColumn("y", .num);
            _ = try d.addColumn("c2", .char);
            _ = try d.addColumn("c1", .char);
            try d.appendRow(&.{ numV(1), numV(2), numV(3), numV(10), strV("a"), strV("b") });
            try d.appendRow(&.{ numV(4), numV(5), numV(6), numV(20), strV("a"), strV("c") });
            try l.put("t", d);
        }
    }.f;

    // (1) MEANS `var y x:` — the prefix expands in PDV order after the plain
    // name (the listing's Variable rows ARE the expansion order).
    {
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=t n; var y x:; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const r = out.items;
        const p_y = std.mem.indexOf(u8, r, "\ny ").?;
        const p_2 = std.mem.indexOf(u8, r, "\nx2 ").?;
        const p_1 = std.mem.indexOf(u8, r, "\nx1 ").?;
        const p_10 = std.mem.indexOf(u8, r, "\nx10").?;
        try t.expect(p_y < p_2 and p_2 < p_1 and p_1 < p_10);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (2) FREQ `tables x:` — one one-way table per match, PDV order.
    {
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=t; tables x:; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const r = out.items;
        const p_2 = std.mem.indexOf(u8, r, "x2     Frequency").?;
        const p_1 = std.mem.indexOf(u8, r, "x1     Frequency").?;
        const p_10 = std.mem.indexOf(u8, r, "x10    Frequency").?;
        try t.expect(p_2 < p_1 and p_1 < p_10);
    }
    // (3) TABULATE `class c:` — the TABLE expression names an EXPANDED var,
    // matched against the pre-expansion wire form at parse time.
    {
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=t; class c:; table c2, x1*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "|c2  |") != null); // c2 rendered as the row CLASS, not an analysis var
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (4) Empty match — the SAME loud rc 1 as the OF (eval.zig) and PRINT
    // (main.zig) empty-match arms; same message vocabulary as the OF arm.
    // D-003: captured reporter, no child process.
    {
        diag.resetGap(); // process-global: an earlier test's gap would leak in
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=t; var zz:; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC MEANS: the name prefix 'zz:' matched no variables") != null);
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (5) FREQ's hard case: a prefix INSIDE a `*` crossing — the doc is
    // silent (Statistical Procedures 6th ed. p.103 Table 3.8 covers parens
    // and name ranges only), so it stays LOUD as a gap (rc 2), never guessed.
    {
        diag.resetGap();
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=t; tables x:*y; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "inside a TABLES '*' crossing is not supported") != null);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diags.hasErrors()));
    }
    // (6) A prefix in a TABULATE TABLE expression — same doc silence, same
    // loud gap (never the old phantom row var `x`).
    {
        diag.resetGap();
        var lib = Library.init(a);
        try mk(a, &lib);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=t; class y; table x:, y*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diags.hasErrors()));
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "name prefix (x:) in a TABLE expression is not supported") != null);
    }
    diag.resetGap();
}

test "PROC DATASETS MODIFY/DELETE resolve members in a directory libname (GAP-datasetsmodifylib)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    // A directory libname keys its members `<lib>.<member>` (as `data T.dm` / SET /
    // PRINT store them) — MODIFY must find `dm` there, not only in WORK.
    inline for (.{ "T.dm", "T.ae" }) |nm| {
        const d = try a.create(Dataset);
        d.* = Dataset.init(a, nm);
        _ = try d.addColumn("x", .num);
        d.setFormat("x", "8.2"); // a display format for ATTRIB _ALL_ FORMAT= to strip
        try lib.put(nm, d);
    }

    const src =
        \\proc datasets lib=T memtype=data nolist;
        \\  modify dm (label="D");
        \\  attrib _all_ format=;
        \\run;
        \\  delete ae;
        \\quit;
    ;
    const toks = try lex.tokenize(a, src, &diags);
    var out: std.ArrayList(u8) = .empty;
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const dm = lib.find("T.dm") orelse return error.MemberNotFound; // MODIFY found it
    try t.expectEqualStrings("D", dm.label.?); // MODIFY (label=…) applied
    try t.expect(dm.columns.items[0].format == null); // ATTRIB _ALL_ FORMAT= stripped it
    try t.expect(lib.find("T.ae") == null); // DELETE resolved the qualified member
}

test "PROC DATASETS CONTENTS: NOPRINT no-op; non-NOPRINT prints the listing; OUT= fails loud (GH#8 ISS-datasetscontents)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    try lib.put("d", d);

    const Case = struct { src: []const u8, wants_err: bool, wants_listing: bool };
    const cases = [_]Case{
        // NOPRINT (the SE/DM idiom): a safe no-op, no diagnostic, no output.
        .{ .src = "proc datasets lib=work nolist; contents data=d varnum noprint; quit;", .wants_err = false, .wants_listing = false },
        // no NOPRINT: print the same listing standalone CONTENTS renders (GH#8).
        .{ .src = "proc datasets lib=work nolist; contents data=d; quit;", .wants_err = false, .wants_listing = true },
        // OUT=: would create a dataset a later step reads → fail loud (captured).
        .{ .src = "proc datasets lib=work nolist; contents data=d out=c noprint; quit;", .wants_err = true, .wants_listing = false },
    };
    for (cases) |c| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, c.src, &diags);
        try t.expect(!diags.hasErrors()); // the input itself lexes clean
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks); // captured diag, never aborts the process
        try t.expectEqual(c.wants_err, diags.hasErrors());
        try t.expectEqual(c.wants_listing, std.mem.indexOf(u8, out.items, "The CONTENTS Procedure") != null);
    }
}

test "BUG-procimport: DBMS=EXCEL RANGE reads the named sheet; every gap fails loud, named" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var diags = diag.Diagnostics.init(a);
    const wb = "tests/corpus/includes/import_sample.xlsx";

    // DV.sas's shape: DBMS=EXCEL + RANGE="Data$" → the NAMED sheet (the 2nd),
    // not the first ("Info", a lone "city" cell) that ignoring RANGE would read.
    {
        g_test_last_unsup = "";
        const src = try std.fmt.allocPrint(a, "proc import out=d datafile=\"{s}\" dbms=excel replace; range=\"Data$\"; getnames=yes; run;", .{wb});
        try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, src, &diags));
        try t.expectEqualStrings("", g_test_last_unsup);
        const d = lib.find("d").?;
        try t.expectEqual(@as(usize, 3), d.columns.items.len);
        try t.expectEqualStrings("name", d.columns.items[1].name);
        try t.expectEqual(@as(usize, 2), d.rowCount());
        try t.expectEqualStrings("Bob & Lee", d.row(1)[1].str);
    }
    // GH#55: EXCEL2000/2002/2003/2007 are version-tagged aliases for the same
    // Excel-workbook engine — they read the .xlsx exactly like DBMS=EXCEL.
    for ([_][]const u8{ "excel2000", "excel2002", "excel2003", "excel2007" }) |eng| {
        g_test_last_unsup = "";
        const src = try std.fmt.allocPrint(a, "proc import out=x datafile=\"{s}\" dbms={s} replace; range=\"Data$\"; getnames=yes; run;", .{ wb, eng });
        try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, src, &diags));
        try t.expectEqualStrings("", g_test_last_unsup);
        const x = lib.find("x").?;
        try t.expectEqual(@as(usize, 3), x.columns.items.len);
        try t.expectEqual(@as(usize, 2), x.rowCount());
    }
    // a cell-area RANGE would import the wrong slice → loud, names the range
    {
        g_test_last_unsup = "";
        const src = try std.fmt.allocPrint(a, "proc import out=e datafile=\"{s}\" dbms=excel; range=\"Data$A1:B2\"; run;", .{wb});
        try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, src, &diags));
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "RANGE") != null);
        try t.expect(lib.find("e") == null);
    }
    // an unsupported DBMS is reported by NAME even when the file is also missing
    {
        g_test_last_unsup = "";
        try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, "proc import out=e datafile=\"no/such.accdb\" dbms=accdb; run;", &diags));
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "DBMS=accdb") != null);
    }
    // a missing DATAFILE names the path — an undelivered external file (DV.sas's
    // E:\ paths) must read as source skew in the histogram, not a mystery
    {
        g_test_last_unsup = "";
        try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, "proc import out=e datafile=\"E:\\nope\\gone.xlsx\" dbms=excel; run;", &diags));
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "gone.xlsx") != null);
    }
    // a non-zip payload behind an Excel DBMS → loud legacy-.xls message
    {
        g_test_last_unsup = "";
        try t.expect(io.writeFileRaw(".zig-cache/fake_legacy.xls", "not a zip"));
        try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, "proc import out=e datafile=\".zig-cache/fake_legacy.xls\" dbms=excel; run;", &diags));
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "legacy binary .xls") != null);
    }
}

test "BUG-importnoreplace: IMPORT to an existing OUT= without REPLACE errors and preserves the original" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var diags = diag.Diagnostics.init(a);
    const csv1 = "tests/corpus/includes/ei_roundtrip.csv";
    const csv2 = "tests/corpus/includes/em_fixture.csv";

    // new dataset → imports fine (no REPLACE needed)
    try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc import out=keep_me datafile=\"{s}\" dbms=csv; run;", .{csv1}), &diags));
    try t.expect(!diags.hasErrors());
    try t.expectEqual(@as(usize, 3), lib.find("keep_me").?.rowCount());

    // existing dataset, no REPLACE → ERROR, original rows preserved (SAS 9.4)
    try t.expectError(error.ExecError, runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc import out=keep_me datafile=\"{s}\" dbms=csv; run;", .{csv2}), &diags)));
    try t.expect(diags.hasErrors());
    const kept = lib.find("keep_me").?;
    try t.expectEqual(@as(usize, 3), kept.rowCount());
    try t.expectEqualStrings("Alice", kept.row(0)[0].str);

    // REPLACE → overwrites, as before
    try runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc import out=keep_me datafile=\"{s}\" dbms=csv replace; run;", .{csv2}), &diags));
    try t.expectEqual(@as(usize, 2), lib.find("keep_me").?.rowCount());
}

test "GAP-importtypes: an EMPTY import file is an ERROR, no 0-variable dataset (captured diag)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var diags = diag.Diagnostics.init(a);

    // 0-byte file → ExecError, message names the path, and NO dataset created
    // (a silent 0-variable dataset only fails confusingly downstream).
    try t.expect(io.writeFileRaw(".zig-cache/empty_import.csv", ""));
    const src = "proc import out=e datafile=\".zig-cache/empty_import.csv\" dbms=csv replace; getnames=yes; run;";
    try t.expectError(error.ExecError, runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, try lex.tokenize(a, src, &diags)));
    try t.expect(diags.hasErrors());
    try t.expect(lib.find("e") == null);
    // whitespace-only is just as empty
    var diags2 = diag.Diagnostics.init(a);
    try t.expect(io.writeFileRaw(".zig-cache/blank_import.csv", "  \n\n"));
    const src2 = "proc import out=b datafile=\".zig-cache/blank_import.csv\" dbms=dlm replace; delimiter=' '; run;";
    try t.expectError(error.ExecError, runImport(.{ .arena = a, .lib = &lib, .diags = &diags2 }, try lex.tokenize(a, src2, &diags2)));
    try t.expect(lib.find("b") == null);
    // a header-only file is NOT empty: 2 variables, 0 observations, no error.
    var diags3 = diag.Diagnostics.init(a);
    try t.expect(io.writeFileRaw(".zig-cache/hdr_only.csv", "a,b\n"));
    const src3 = "proc import out=h datafile=\".zig-cache/hdr_only.csv\" dbms=csv replace; run;";
    try runImport(.{ .arena = a, .lib = &lib, .diags = &diags3 }, try lex.tokenize(a, src3, &diags3));
    try t.expect(!diags3.hasErrors());
    const h = lib.find("h").?;
    try t.expectEqual(@as(usize, 2), h.columns.items.len);
    try t.expectEqual(@as(usize, 0), h.rowCount());
}

test "PROC DATASETS DELETE/KILL unlink on-disk members — no undead datasets (BUG-datasetsdeletedisk)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir = try std.fmt.allocPrint(a, ".zig-cache/tmp/{s}", .{tmp.sub_path});
    for ([_][]const u8{ "x.csv", "x.labels", "tmp_1.csv", "tmp_2.csv", "keep.csv" }) |f|
        try t.expect(io.writeFileRaw(try std.fmt.allocPrint(a, "{s}/{s}", .{ dir, f }), "v\n1\n"));
    const gone = struct {
        fn gone(al: std.mem.Allocator, d: []const u8, f: []const u8) !bool {
            return !io.fileExistsRaw(try std.fmt.allocPrint(al, "{s}/{s}", .{ d, f }));
        }
    }.gone;

    dsfns.bindLibrefs(&.{.{ .name = "t", .dir = dir }});
    defer dsfns.bindLibrefs(&.{});
    var lib = Library.init(a);
    var diags = diag.Diagnostics.init(a);

    // literal DELETE of a disk-only member (nothing in memory): file + sidecar
    // gone, no "member not found" — it DID exist, on disk.
    g_test_last_unsup = "";
    var out: std.ArrayList(u8) = .empty;
    var toks = try lex.tokenize(a, "proc datasets lib=t nolist; delete x; quit;", &diags);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try t.expect(try gone(a, dir, "x.csv"));
    try t.expect(try gone(a, dir, "x.labels"));
    try t.expectEqualStrings("", g_test_last_unsup);

    // wildcard family on disk; the non-matching member survives
    toks = try lex.tokenize(a, "proc datasets lib=t nolist; delete tmp_:; quit;", &diags);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try t.expect(try gone(a, dir, "tmp_1.csv"));
    try t.expect(try gone(a, dir, "tmp_2.csv"));
    try t.expect(!try gone(a, dir, "keep.csv"));

    // KILL sweeps every remaining on-disk member of the libname
    toks = try lex.tokenize(a, "proc datasets lib=t kill nolist; quit;", &diags);
    try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try t.expect(try gone(a, dir, "keep.csv"));
}

test "PROC COMPARE: equal datasets report all values exactly equal (CLIN-compare)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    inline for (.{ "prod", "qc" }) |nm| {
        const d = try a.create(Dataset);
        d.* = Dataset.init(a, nm);
        _ = try d.addColumn("id", .num);
        _ = try d.addColumn("x", .num);
        try d.rows.append(a, &.{ .{ .num = 1 }, .{ .num = 10 } });
        try d.rows.append(a, &.{ .{ .num = 2 }, .{ .num = 20 } });
        try lib.put(nm, d);
    }
    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc compare base=prod compare=qc; run;", &diags);
    try runCompare(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try t.expect(std.mem.indexOf(u8, out.items, "All values compared are exactly equal") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Variables all equal: 2") != null);

    // one differing value flips the verdict
    lib.find("qc").?.rows.items[1] = &.{ .{ .num = 2 }, .{ .num = 99 } };
    var out2: std.ArrayList(u8) = .empty;
    try runCompare(.{ .arena = a, .lib = &lib, .diags = &diags }, &out2, toks);
    try t.expect(std.mem.indexOf(u8, out2.items, "Total unequal values: 1") != null);
    try t.expect(std.mem.indexOf(u8, out2.items, "unequal values found") != null);
}

test "cellText: missing numeric renders as '.', not \"nan\"" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings(".", try cellText(a, Value.missing));
    try t.expectEqualStrings("42", try cellText(a, numV(42)));
    try t.expectEqualStrings("Bob", try cellText(a, strV("Bob")));
}

test "proc sort by a numeric key, in place" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const have = try buildHave(a);
    try lib.put("have", have);

    const toks = try lex.tokenize(a, "proc sort data=have; by age; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    // ascending by age: Bob 25, Alice 30, Carol 40
    try t.expectEqualStrings("Bob", have.row(0)[0].str);
    try t.expectEqual(@as(f64, 25), have.row(0)[1].num);
    try t.expectEqualStrings("Alice", have.row(1)[0].str);
    try t.expectEqualStrings("Carol", have.row(2)[0].str);
}

test "PROC SORT is STABLE at scale — ties keep input order (qa tick-37, gen2 AE row order)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 4000 rows, 3 distinct keys: far past pdq's insertion-sort threshold, so
    // an unstable sort here WOULD shuffle ties (qa's n<=400 probes stayed
    // stable only by falling into small-partition insertion sort).
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "big");
    _ = try ds.addColumn("k", .num);
    _ = try ds.addColumn("ord", .num);
    var i: usize = 0;
    while (i < 4000) : (i += 1) {
        try ds.appendRow(&.{ numV(@floatFromInt(i % 3)), numV(@floatFromInt(i)) });
    }
    try lib.put("big", ds);

    var diags = diag.Diagnostics.init(a);
    const toks = try lex.tokenize(a, "proc sort data=big; by k; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    var prev_k: f64 = -1;
    var prev_ord = [_]f64{ -1, -1, -1 };
    for (ds.rows.items) |r| {
        try t.expect(r[0].num >= prev_k); // keys ascend
        prev_k = r[0].num;
        const k: usize = @intFromFloat(r[0].num);
        try t.expect(r[1].num > prev_ord[k]); // ties keep input order (EQUALS)
        prev_ord[k] = r[1].num;
    }
}

test "descending BY, and OUT= leaves the source unsorted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const have = try buildHave(a);
    try lib.put("have", have);

    const toks = try lex.tokenize(a, "proc sort data=have out=want; by descending age; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const want = lib.find("want").?;
    try t.expectEqualStrings("Carol", want.row(0)[0].str); // 40 first (descending)
    try t.expectEqualStrings("Bob", want.row(2)[0].str);
    // source untouched by OUT=
    try t.expectEqualStrings("Carol", have.row(0)[0].str);
    try t.expectEqualStrings("Bob", have.row(2)[0].str);
}

test "SORTSEQ=LINGUISTIC sorts case-folded; unknown SORT option fails loud (BUG-sortseq/procoptswallow)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("name", .char);
    try ds.appendRow(&.{strV("Banana")});
    try ds.appendRow(&.{strV("apple")});
    try ds.appendRow(&.{strV("cherry")});
    try lib.put("d", ds);

    const toks = try lex.tokenize(a, "proc sort data=d sortseq=linguistic; by name; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
    // dictionary order: apple < Banana < cherry (ASCII would put Banana first)
    try t.expectEqualStrings("apple", ds.row(0)[0].str);
    try t.expectEqualStrings("Banana", ds.row(1)[0].str);
    try t.expectEqualStrings("cherry", ds.row(2)[0].str);

    // a bogus header option must not vanish silently — a typo is the user's
    // rc 1 via diags (BUG-proctypoexits2 split; the gap arm keeps g_test_last_unsup)
    const bad = try lex.tokenize(a, "proc sort data=d bogusopt; by name; run;", &diags);
    try t.expectError(error.ParseError, runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, bad));
    try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC SORT: unknown option bogusopt") != null);
}

test "GAP-sortlow-tick282: THREADS & co benign, out=_null_ discards, LINGUISTIC(...) fails loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{numV(3)});
    try ds.appendRow(&.{numV(1)});
    try ds.appendRow(&.{numV(1)});
    try lib.put("d", ds);

    // F6: THREADS/NOTHREADS/OVERWRITE/DATECOPY are accepted no-ops; sort still runs.
    g_test_last_unsup = "";
    for ([_][]const u8{ "threads", "nothreads", "overwrite", "datecopy" }) |opt| {
        const src = try std.fmt.allocPrint(a, "proc sort data=d {s}; by x; run;", .{opt});
        const toks = try lex.tokenize(a, src, &diags);
        try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
    }
    try t.expectEqualStrings("", g_test_last_unsup);
    try t.expectEqual(numV(1), ds.row(0)[0]);
    try t.expectEqual(numV(3), ds.row(2)[0]);

    // F5: out=_null_ discards the sorted result — but DUPOUT= still materializes.
    const t5 = try lex.tokenize(a, "proc sort data=d out=_null_ nodupkey dupout=g; by x; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, t5);
    try t.expect(lib.find("_null_") == null);
    const g = lib.find("g") orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(usize, 1), g.rows.items.len);
    try t.expectEqual(numV(1), g.row(0)[0]);

    // F7: parenthesized LINGUISTIC(...) sub-options fail loud, never swallowed.
    g_test_last_unsup = "";
    const t7 = try lex.tokenize(a, "proc sort data=d sortseq=linguistic(numeric_collation=on); by x; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, t7);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "LINGUISTIC(") != null);
}

test "GAP-freqlow-tick276: unknown FREQ option fails loud; zero-weight stratum prints no phantom table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // F6: a typo'd PROC FREQ statement option must not vanish — the old final
    // else `i += 1`'d ANY token (compress/odrer=freq ran silently, rc=0).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d odrer=freq; tables x; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "odrer") != null);
    }
    // Positive control: implemented (NLEVELS/ORDER=) + inert (COMPRESS/PAGE/
    // FORMCHAR=) options still parse and render.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(2)});
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d compress page formchar='|----|+|---' nlevels order=freq; tables x; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Number of Variable Levels") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Frequency") != null); // the freq table itself
    }
    // F5: a stratum whose obs all have zero weight has no observations → SAS
    // prints NO table for it (no phantom "Total 0 / 100.00" grid).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("h", .char);
        _ = try ds.addColumn("g", .char);
        _ = try ds.addColumn("s", .char);
        _ = try ds.addColumn("w", .num);
        try ds.appendRow(&.{ strV("A"), strV("X"), strV("Y"), numV(0) });
        try ds.appendRow(&.{ strV("B"), strV("X"), strV("Y"), numV(5) });
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables h*g*s; weight w; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Controlling for h=A") == null); // phantom suppressed
        try t.expect(std.mem.indexOf(u8, out.items, "Controlling for h=B") != null); // real stratum stays
        // `weight w / zeros` re-includes the zero-weight stratum (SAS).
        var out2: std.ArrayList(u8) = .empty;
        const toks2 = try lex.tokenize(a, "proc freq data=d; tables h*g*s; weight w / zeros; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out2, toks2);
        try t.expect(std.mem.indexOf(u8, out2.items, "Controlling for h=A") != null);
    }
}

test "GAP-procsubstmtswallow: SORT/MEANS/FREQ/CONTENTS statement loops fail loud; D-014a skip arms hold" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // An unknown SUB-STATEMENT was silently swallowed by SORT (whose own OPTION
    // loop was already loud — one PROC, two policies), MEANS, FREQ and CONTENTS
    // while PRINT/TRANSPOSE/SQL errored (D-002). Each loop now ends in a real
    // else naming the statement, behind a parser.isMidStepSkippable arm (D-014a
    // — the CONVERGED predicate: after BUG-filenamemidstep, FILENAME/ODS are
    // hoisted too, so NO isGlobalKw member fails loud here anymore).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);

        // SORT, unknown statement BEFORE the BY (the repro shape).
        const t1 = try lex.tokenize(a, "proc sort data=d; zzzqnosuchstatement; by x; run;", &diags);
        try t.expectError(error.ParseError, runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, t1));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC SORT statement zzzqnosuchstatement is not supported") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        // SORT, unknown statement AFTER the BY — same policy both sides.
        const t2 = try lex.tokenize(a, "proc sort data=d; by x; zzzqnosuchstatement; run;", &diags);
        try t.expectError(error.ParseError, runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, t2));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC SORT statement zzzqnosuchstatement is not supported") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t3 = try lex.tokenize(a, "proc means data=d; zzzqnosuchstatement; var x; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t3));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC MEANS statement zzzqnosuchstatement is not supported") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t4 = try lex.tokenize(a, "proc freq data=d; zzzqnosuchstatement; tables x; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t4));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC FREQ statement zzzqnosuchstatement is not supported") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t5 = try lex.tokenize(a, "proc contents data=d; zzzqnosuchstatement; run;", &diags);
        try t.expectError(error.ParseError, runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t5));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC CONTENTS statement zzzqnosuchstatement is not supported") != null);
    }
    // CONTENTS takes NO WHERE statement and runs no procInput, so WHERE hits
    // the loud else there (as SAS errors) — never an honest skip.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t5b = try lex.tokenize(a, "proc contents data=d; where x > 1; run;", &diags);
        try t.expectError(error.ParseError, runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t5b));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC CONTENTS statement where is not supported") != null);
    }
    // D-014: a hoisted mid-step global (TITLE) must NOT trip the loud else in
    // any of the four — main.zig hoists and executes it, the loop skips it.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t6 = try lex.tokenize(a, "proc means data=d; title 't'; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t6);
        try t.expect(!diags.hasErrors());
        const t7 = try lex.tokenize(a, "proc sort data=d; title 't'; by x; run;", &diags);
        try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, t7);
        try t.expect(!diags.hasErrors());
        const t8 = try lex.tokenize(a, "proc freq data=d; title 't'; tables x; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t8);
        try t.expect(!diags.hasErrors());
        const t9 = try lex.tokenize(a, "proc contents data=d; title 't'; run;", &diags);
        try runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t9);
        try t.expect(!diags.hasErrors());
    }
    // D-014a CONVERGED (BUG-filenamemidstep): FILENAME/ODS joined the hoist, so
    // mid-step they skip HONESTLY now — the prior attempt's 'FILENAME fails
    // loud' arm went stale on exactly this and is deliberately NOT re-added.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t10 = try lex.tokenize(a, "proc means data=d; filename q 'x'; ods listing; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t10);
        try t.expect(!diags.hasErrors());
    }
}

test "BUG-sortstraysemi: SORT pre-BY loop consumes exactly one token per path; unknown statement stays loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // QA tick357 F2 (regression in d1d38c27): the pre-BY loop's new
    // stray-punctuation arm consumed the stray `;` and the PRE-EXISTING
    // UNCONDITIONAL trailer then consumed the NEXT token too — the `by` — so
    // the loop landed on the BY variable and failed loud naming it. The
    // trailer is now GUARDED (`if (atTag(...))`), the same form the four
    // sibling loops already used. These arms pin that a stray token costs
    // exactly one token: the sort must RUN (OUT= exists, rows reordered).
    const sortRuns = struct {
        fn check(a2: std.mem.Allocator, src: []const u8) !void {
            var diags = diag.Diagnostics.init(a2);
            var lib = Library.init(a2);
            const ds = try a2.create(Dataset);
            ds.* = Dataset.init(a2, "d");
            _ = try ds.addColumn("x", .num);
            try ds.appendRow(&.{numV(2)});
            try ds.appendRow(&.{numV(1)});
            try lib.put("d", ds);
            const toks = try lex.tokenize(a2, src, &diags);
            try runSort(.{ .arena = a2, .lib = &lib, .diags = &diags }, toks);
            try t.expect(!diags.hasErrors());
            const s = lib.find("s") orelse return error.TestExpectedSortOutput;
            try t.expectEqual(@as(usize, 2), s.rows.items.len);
            try t.expectEqual(@as(f64, 1), s.rows.items[0][0].num); // sorted: BY parsed
            try t.expectEqual(@as(f64, 2), s.rows.items[1][0].num);
        }
    };
    // A null statement is legal SAS — silently ignored. A semicolon-terminated
    // macro call `%mymacro;` leaves EXACTLY this token stream after expansion
    // (macro expansion is upstream of runSort), so this arm is that case too;
    // the corpus fixture pins the real `%mymacro;` source end-to-end.
    try sortRuns.check(a, "proc sort data=d out=s; ; by x; run;");
    // Two nulls in a row, and a null after a mid-step global / WHERE.
    try sortRuns.check(a, "proc sort data=d out=s; ;; by x; run;");
    try sortRuns.check(a, "proc sort data=d out=s; title 't'; ; by x; run;");
    try sortRuns.check(a, "proc sort data=d out=s; where x > 0; ; by x; run;");
    // The OTHER unnamed token class: a stray `,` had the same double-advance
    // hole (probed, not reasoned) — now exactly one token, BY still parses.
    try sortRuns.check(a, "proc sort data=d out=s; , by x; run;");
    // The fix is position tracking, NOT a retreat from d1d38c27's policy: a
    // genuinely unknown sub-statement still fails loud NAMING ITSELF.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        const toks = try lex.tokenize(a, "proc sort data=d out=s; ; zzzqnosuchstatement; by x; run;", &diags);
        try t.expectError(error.ParseError, runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC SORT statement zzzqnosuchstatement is not supported") != null);
    }
}

test "GAP-dsmgmt-tick262-264: DATASETS verbs named-loud; SORT BY GROUPFORMAT named; CONTENTS _all_ named; mid-step globals skip" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // F5: COPY/SAVE/EXCHANGE/AGE (and other unsupported verbs) NAME themselves —
    // a silent-looking generic message hid WHICH data-management the user
    // believes happened.
    for ([_][]const u8{ "copy out=tgt", "save keepme", "exchange a=b", "age cur bk1 bk2", "select a" }) |verb| {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc datasets library=work nolist; {s}; quit;", .{verb});
        const toks = try lex.tokenize(a, src, &diags);
        g_test_last_unsup = "";
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const first_word = verb[0..(std.mem.indexOfScalar(u8, verb, ' ') orelse verb.len)];
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, first_word) != null);
    }
    // D-014/D-014a: a mid-step TITLE/FOOTNOTE/OPTIONS is hoisted by main.zig
    // and its tokens left in the step — the loud else must skip them, never
    // UNSUPPORTED (was: `proc datasets; title "t"; …` died at exit 2).
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work nolist; title \"mid\"; footnote1 \"f\"; options nonotes; delete d; quit;", &diags);
        g_test_last_unsup = "";
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqualStrings("", g_test_last_unsup); // no false UNSUPPORTED
        try t.expect(lib.find("d") == null); // the delete still ran
    }
    // F6: `by groupformat x` names the unsupported GROUPFORMAT option instead
    // of blaming a nonexistent variable.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        const toks = try lex.tokenize(a, "proc sort data=d; by groupformat x; run;", &diags);
        g_test_last_unsup = "";
        try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "GROUPFORMAT") != null);
    }
    // F7: CONTENTS DATA=_ALL_ names the whole-library gap (not "member not
    // found"); bare CONTENTS still requires DATA=; DATA=member keeps printing.
    {
        var diags = diag.Diagnostics.init(a);
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        try ds.appendRow(&.{numV(1)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const t1 = try lex.tokenize(a, "proc datasets library=work nolist; contents data=_all_; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, t1);
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "whole-library") != null);

        var diags2 = diag.Diagnostics.init(a);
        const t2 = try lex.tokenize(a, "proc datasets library=work nolist; contents; quit;", &diags2);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags2 }, &out, t2);
        try t.expect(std.mem.indexOf(u8, try diags2.render(), "requires DATA=") != null);

        var diags3 = diag.Diagnostics.init(a);
        const t3 = try lex.tokenize(a, "proc datasets library=work nolist; contents data=d; quit;", &diags3);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags3 }, &out, t3);
        try t.expect(!diags3.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "The CONTENTS Procedure") != null);
    }
}

test "PROC SORT DUPOUT=: collision fails loud, 1-obs DUPOUT exists, dupout(keep=) honored (BUG-sortdupoutfamily)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    _ = try d.addColumn("v", .num);
    try d.appendRow(&.{ numV(1), numV(10) });
    try d.appendRow(&.{ numV(1), numV(99) });
    try d.appendRow(&.{ numV(2), numV(5) });
    try lib.put("d", d);

    // F1a: dupout= naming the in-place input → ERROR, input NOT overwritten by dups.
    var diags1 = diag.Diagnostics.init(a);
    const c1 = try lex.tokenize(a, "proc sort data=d nodupkey dupout=d; by x; run;", &diags1);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags1 }, c1);
    try t.expect(diags1.hasErrors());
    try t.expect(std.mem.indexOf(u8, diags1.list.items[0].message, "DUPOUT=") != null);
    try t.expectEqual(@as(usize, 3), d.rows.items.len); // sorted data NOT lost

    // F1b: dupout= naming out= → ERROR, no partial out= member left behind.
    var diags2 = diag.Diagnostics.init(a);
    const c2 = try lex.tokenize(a, "proc sort data=d nodupkey dupout=o out=o; by x; run;", &diags2);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags2 }, c2);
    try t.expect(diags2.hasErrors());
    try t.expect(lib.find("o") == null);

    // F3: a 1-obs input still materializes DUPOUT (0 obs, full schema).
    var diags3 = diag.Diagnostics.init(a);
    const one = try a.create(Dataset);
    one.* = Dataset.init(a, "one");
    _ = try one.addColumn("x", .num);
    _ = try one.addColumn("v", .num);
    try one.appendRow(&.{ numV(1), numV(10) });
    try lib.put("one", one);
    const c3 = try lex.tokenize(a, "proc sort data=one nodupkey dupout=dps out=o1; by x; run;", &diags3);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags3 }, c3);
    try t.expect(!diags3.hasErrors());
    const dps = lib.find("dps").?;
    try t.expectEqual(@as(usize, 0), dps.rows.items.len);
    try t.expectEqual(@as(usize, 2), dps.columns.items.len);

    // F4: dupout=g(keep=x) keeps only x on the duplicates dataset.
    var diags4 = diag.Diagnostics.init(a);
    const c4 = try lex.tokenize(a, "proc sort data=d nodupkey dupout=g(keep=x) out=o2; by x; run;", &diags4);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags4 }, c4);
    const g = lib.find("g").?;
    try t.expectEqual(@as(usize, 1), g.columns.items.len);
    try t.expectEqualStrings("x", g.columns.items[0].name);
    try t.expectEqual(@as(usize, 1), g.rows.items.len); // the removed (1,99)
    try t.expectEqual(@as(f64, 1), g.row(0)[0].num);
}

test "PROC SORT validates BY even on a 0-obs input; schemaless empty stays tolerant (NOTE-sort0obsvalidation)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "e0");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    try lib.put("e0", ds); // 0 observations, but a real schema

    // missing BY on a 0-obs input used to be silently accepted — now fails loud.
    g_test_last_unsup = "";
    const nb = try lex.tokenize(a, "proc sort data=e0 out=o1; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, nb);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "without a BY statement") != null);

    // a bad BY var on a 0-obs input now fails loud too (its key list ends empty).
    g_test_last_unsup = "";
    const badby = try lex.tokenize(a, "proc sort data=e0 out=o2; by nosuchvar; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, badby);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "empty BY list") != null);

    // a truly SCHEMALESS empty dataset (0 cols, 0 rows) still can't check a BY
    // var, so it stays tolerant — no error (SORT-emptytol, must not regress).
    const es = try a.create(Dataset);
    es.* = Dataset.init(a, "e1");
    try lib.put("e1", es);
    g_test_last_unsup = "";
    const sl = try lex.tokenize(a, "proc sort data=e1 out=o3; by g; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, sl);
    try t.expect(g_test_last_unsup.len == 0);
}

test "cmpStrLing: case-folded dictionary order, blank-padded (BUG-sortseq)" {
    try t.expect(cmpStrLing("apple", "Banana") == .lt);
    try t.expect(cmpStrLing("Banana", "apple") == .gt);
    try t.expect(cmpStrLing("Apple", "apple") == .eq); // fold-equal → stable tie
    try t.expect(cmpStrLing("ab", "ABA") == .lt); // shorter side blank-pads
}

test "cmpColl: the shared collation compare's contract (NOTE-collationduplicated)" {
    // sql.zig's cmpValColl must become a pure delegate of cmpColl — pin the
    // exact semantics that delegation relies on, so a semantic drift here
    // reds before it silently moves row order on either side.
    const apple: Value = .{ .str = "apple" };
    const banana: Value = .{ .str = "Banana" };
    try t.expect(cmpColl(apple, banana, false) == .gt); // byte order: 'a' > 'B'
    try t.expect(cmpColl(apple, banana, true) == .lt); // ling: dictionary order
    try t.expect(cmpColl(banana, apple, true) == .gt);
    try t.expect(cmpColl(apple, apple, true) == .eq);
    const ab: Value = .{ .str = "ab" };
    const aba: Value = .{ .str = "ABA" };
    try t.expect(cmpColl(ab, aba, true) == .lt); // shorter side blank-pads
    const one: Value = .{ .num = 1 };
    try t.expect(cmpColl(Value.missing, one, false) == .lt); // missing lowest
    try t.expect(cmpColl(one, Value.missing, true) == .gt); // `ling` never touches numerics
    try t.expect(cmpColl(Value.specialMissing('A'), Value.missing, false) == .gt); // . < .A
    try t.expect(cmpColl(Value.specialMissing('_'), Value.missing, true) == .lt); // ._ < .
    try t.expect(cmpColl(Value.specialMissing('A'), one, false) == .lt); // all missings < real
    // A char that parses numerically still compares as a STRING when both sides
    // are char ("10" < "9" byte-wise) — the column-type homogeneity rule.
    const ten: Value = .{ .str = "10" };
    const nine: Value = .{ .str = "9" };
    try t.expect(cmpColl(ten, nine, false) == .lt);
}

test "PROC CONTENTS VARNUM creation order + SHORT names; unknown option fails loud (BUG-procoptswallow)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "v");
    _ = try ds.addColumn("Zebra", .num);
    _ = try ds.addColumn("Apple", .num);
    _ = try ds.addColumn("Mango", .num);
    try lib.put("v", ds);

    // VARNUM: creation order (Zebra, Apple, Mango), not alphabetic
    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc contents data=v varnum; run;", &diags);
    try runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try t.expect(std.mem.indexOf(u8, out.items, "Variables in Creation Order") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "Zebra").? < std.mem.indexOf(u8, out.items, "Apple").?);
    try t.expect(std.mem.indexOf(u8, out.items, "Apple").? < std.mem.indexOf(u8, out.items, "Mango").?);

    // SHORT: compact name list, no attribute table
    var out2: std.ArrayList(u8) = .empty;
    const toks2 = try lex.tokenize(a, "proc contents data=v short; run;", &diags);
    try runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out2, toks2);
    try t.expect(std.mem.indexOf(u8, out2.items, "Apple Mango Zebra") != null); // alpha default
    try t.expect(std.mem.indexOf(u8, out2.items, "Type") == null);

    const bad = try lex.tokenize(a, "proc contents data=v bogusopt; run;", &diags);
    var out3: std.ArrayList(u8) = .empty;
    // a typo is the user's rc 1 via diags (BUG-proctypoexits2 split)
    try t.expectError(error.ParseError, runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out3, bad));
    try t.expect(std.mem.indexOf(u8, try diags.render(), "PROC CONTENTS: unknown option bogusopt") != null);
}

test "char key sorts blank-padded ASCII; stable on ties" {
    var rows = [_][]const Value{
        &.{ strV("Bob"), numV(1) },
        &.{ strV("Al"), numV(2) },
        &.{ strV("Bob"), numV(3) }, // tie with row 0 on name
        &.{ strV("Al"), numV(4) },
    };
    sortRows(&rows, &.{.{ .idx = 0, .desc = false }});
    try t.expectEqualStrings("Al", rows[0][0].str);
    try t.expectEqual(@as(f64, 2), rows[0][1].num); // Al(2) before Al(4): stable
    try t.expectEqual(@as(f64, 4), rows[1][1].num);
    try t.expectEqual(@as(f64, 1), rows[2][1].num); // Bob(1) before Bob(3): stable
}

test "proc means renders the SAS listing table (matches the fixture)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30, 40 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc means data=have; run;", &diags);
    try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "                                       The MEANS Procedure\n" ++
        "\n" ++
        "                              Analysis Variable : x\n" ++
        "\n" ++
        "           N            Mean         Std Dev         Minimum         Maximum\n" ++
        "     -----------------------------------------------------------------------\n" ++
        "           4      25.0000000      12.9099445      10.0000000      40.0000000\n" ++
        "     -----------------------------------------------------------------------\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc means single var honors requested stats, not the default 5 (BUG-meansstat)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30, 40 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc means data=have mean median; var x; run;", &diags);
    try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const s = out.items;
    try t.expect(std.mem.indexOf(u8, s, "Mean") != null); // requested
    try t.expect(std.mem.indexOf(u8, s, "Median") != null); // requested (new stat)
    try t.expect(std.mem.indexOf(u8, s, "Std Dev") == null); // NOT forced in
    try t.expect(std.mem.indexOf(u8, s, "Minimum") == null); // NOT forced in
    try t.expect(std.mem.indexOf(u8, s, "25.0000000") != null); // mean & median both 25
}

test "BUG-meansoptnoop: DESCENDING/ORDER=/ALPHA= honored; COMPLETETYPES, ORDER=FORMATTED, bad ALPHA fail loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 2, 2 }, .{ 1, 3 }, .{ 2, 4 }, .{ 3, 5 }, .{ 1, 9 } }, [_][]const u8{ "b", "a", "b", "a", "c", "b" }) |r, nm|
        try ds.appendRow(&.{ strV(nm), numV(r[1]) });
    try lib.put("have", ds);

    // DESCENDING reverses the printed CLASS level order (c b a) — was a silent no-op.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have descending n mean; class g; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const s = out.items;
        const ci = std.mem.indexOf(u8, s, "c ").?;
        const bi = std.mem.indexOf(u8, s, "b ").?;
        const ai = std.mem.indexOf(u8, s, "a ").?;
        try t.expect(ci < bi and bi < ai);
    }
    // ORDER=FREQ (b a c by descending size) and ORDER=DATA (b a c appearance)
    // are honored, WITHOUT the old spurious "freq is not recognized" warning.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have order=freq n mean; class g; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const s = out.items;
        const bi = std.mem.indexOf(u8, s, "b ").?;
        const ai = std.mem.indexOf(u8, s, "a ").?;
        const ci = std.mem.indexOf(u8, s, "c ").?;
        try t.expect(bi < ai and ai < ci);
        try t.expect(std.mem.indexOf(u8, try diags.render(), "not recognized") == null); // no spurious warning
    }
    // ALPHA=0.1 relabels the CLM columns (90%) and recomputes the limits.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have alpha=0.1 clm; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Lower 90% CL for Mean") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "95% CL") == null);
    }
    // The rest fail LOUD (captured) — never a silent no-op.
    const loud = [_][]const u8{
        "proc means data=have completetypes n; class g; var x; run;",
        "proc means data=have order=formatted n; class g; var x; run;",
        "proc means data=have order=bogus n; class g; var x; run;",
        "proc means data=have alpha=0 clm; var x; run;",
        "proc means data=have alpha=1.5 clm; var x; run;",
    };
    for (loud) |src| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(diags.hasErrors());
        try t.expectEqual(@as(usize, 0), out.items.len); // no partial table on a rejected option
    }
}

test "PROCBY-modifiers: PROC BY DESCENDING/NOTSORTED honored, GROUPFORMAT loud, plain BY unaffected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 1, 20 }, .{ 2, 30 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("have", ds);

    // plain BY still parses and renders (baseline — no regression).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have mean; by g; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Mean") != null);
    }
    // BY DESCENDING g on DESCENDING-sorted data → groups, largest first
    // (GAP-procbydescending — was: loud "plain ascending BY only").
    var dlib = Library.init(a);
    const dds = try a.create(Dataset);
    dds.* = Dataset.init(a, "dhave");
    _ = try dds.addColumn("g", .num);
    _ = try dds.addColumn("x", .num);
    for ([_][2]f64{ .{ 2, 30 }, .{ 1, 20 }, .{ 1, 10 } }) |r| try dds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try dlib.put("dhave", dds);
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=dhave mean; by descending g; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &dlib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "g=2").? < std.mem.indexOf(u8, out.items, "g=1").?);
    }
    // BY DESCENDING g on ASCENDING data → captured ParseError naming the
    // direction (the sortedness guard flips per key), NO table emitted.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have mean; by descending g; var x; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "not sorted in descending sequence") != null);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    // BY g NOTSORTED → contiguous-run groups, no sortedness check (RANK path —
    // the modifier trails the vars).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=r; var x; by g notsorted; run;", &diags);
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("r") != null);
    }
    // BY GROUPFORMAT → STILL a captured ParseError (GAP-bygroupformat —
    // grouping on raw values, so accepting it would silently mis-group).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have mean; by g groupformat; var x; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "GROUPFORMAT is not yet supported") != null);
    }
}

test "BUG-meansoutbydescending: OUT= rows follow the BY direction; SORT NOTSORTED names the rule" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("h", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][3]f64{ .{ 3, 1, 7 }, .{ 2, 2, 10 }, .{ 2, 1, 20 }, .{ 1, 1, 5 }, .{ 1, 1, 15 } }) |r|
        try ds.appendRow(&.{ numV(r[0]), numV(r[1]), numV(r[2]) });
    try lib.put("d", ds);

    // MEANS OUT= with BY DESCENDING g → rows written 3,2,1 (was: 1,2,3, an
    // order our own `set s; by descending g;` then refused to read).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d; by descending g; var x; output out=s mean=m; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const s = lib.find("s").?;
        try t.expectEqual(@as(usize, 3), s.rows.items.len);
        for ([_]f64{ 3, 2, 1 }, 0..) |g, k| try t.expectEqual(g, s.rows.items[k][0].num);
    }
    // UNIVARIATE shares the builder → same rule.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d noprint; by descending g; var x; output out=u mean=m; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const u = lib.find("u").?;
        try t.expectEqual(@as(usize, 3), u.rows.items.len);
        for ([_]f64{ 3, 2, 1 }, 0..) |g, k| try t.expectEqual(g, u.rows.items[k][0].num);
    }
    // MIXED direction `by g descending h` → g ascending, h descending within g.
    var lib2 = Library.init(a);
    const ds2 = try a.create(Dataset);
    ds2.* = Dataset.init(a, "m");
    _ = try ds2.addColumn("g", .num);
    _ = try ds2.addColumn("h", .num);
    _ = try ds2.addColumn("x", .num);
    for ([_][3]f64{ .{ 1, 2, 10 }, .{ 1, 1, 20 }, .{ 2, 2, 30 }, .{ 2, 1, 40 } }) |r|
        try ds2.appendRow(&.{ numV(r[0]), numV(r[1]), numV(r[2]) });
    try lib2.put("m", ds2);
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=m; by g descending h; var x; output out=sm mean=m; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib2, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const sm = lib2.find("sm").?;
        try t.expectEqual(@as(usize, 4), sm.rows.items.len);
        for ([_][2]f64{ .{ 1, 2 }, .{ 1, 1 }, .{ 2, 2 }, .{ 2, 1 } }, 0..) |gh, k| {
            try t.expectEqual(gh[0], sm.rows.items[k][0].num);
            try t.expectEqual(gh[1], sm.rows.items[k][1].num);
        }
    }
    // plain ascending BY → UNCHANGED ascending order (blast-radius pin; data
    // sorted ascending by BOTH keys so the guard admits it).
    var lib3 = Library.init(a);
    const ds3 = try a.create(Dataset);
    ds3.* = Dataset.init(a, "a");
    _ = try ds3.addColumn("g", .num);
    _ = try ds3.addColumn("h", .num);
    _ = try ds3.addColumn("x", .num);
    for ([_][3]f64{ .{ 1, 1, 20 }, .{ 1, 2, 10 }, .{ 2, 1, 40 }, .{ 2, 2, 30 } }) |r|
        try ds3.appendRow(&.{ numV(r[0]), numV(r[1]), numV(r[2]) });
    try lib3.put("a", ds3);
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=a; by g h; var x; output out=sa mean=m; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib3, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const sa = lib3.find("sa").?;
        for ([_][2]f64{ .{ 1, 1 }, .{ 1, 2 }, .{ 2, 1 }, .{ 2, 2 } }, 0..) |gh, k| {
            try t.expectEqual(gh[0], sa.rows.items[k][0].num);
            try t.expectEqual(gh[1], sa.rows.items[k][1].num);
        }
    }
    // PROC SORT `by g notsorted` → captured ParseError naming the RULE (Base SAS
    // Procedures Guide p.75), not a phantom "BY variable notsorted" message
    // (NOTE-sortnotsortedmsg — erroring was always correct, the message was not).
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc sort data=d; by g notsorted; run;", &diags);
        try t.expectError(error.ParseError, runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(diags.hasErrors());
        const rendered = try diags.render();
        try t.expect(std.mem.indexOf(u8, rendered, "NOTSORTED option cannot be used in a PROC SORT step") != null);
        try t.expect(std.mem.indexOf(u8, rendered, "not in dataset") == null);
    }
}

test "GAP-rankguards: unimplemented RANK score options + bad TIES= fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30, 40 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    // Each unimplemented score option must ParseError, not emit ordinal ranks.
    for ([_][]const u8{ "fraction", "percent", "nplus1", "normal=blom", "savage", "blom", "tukey", "vw" }) |opt| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc rank data=have out=o {s}; var x; ranks fr; run;", .{opt});
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(diags.hasErrors());
        try t.expect(lib.find("o") == null); // no output dataset produced
    }

    // TIES=<unrecognized> must error, never silently default to MEAN.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=o ties=bogus; var x; ranks fr; run;", &diags);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "not recognized") != null);
    }

    // Baseline: plain ranks + a valid TIES= still work (no regression).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=o ties=mean; var x; ranks fr; run;", &diags);
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("o") != null);
    }
}

test "REOPEN-meansdefvar: char var in VAR list fails loud; CLASS/BY/WEIGHT/FREQ/ID excluded from the default analysis set (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 30 } }, [_][]const u8{ "a", "b" }) |r, nm|
        try ds.appendRow(&.{ strV(nm), numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);

    // #8: `var c x;` (c char) — SAS type ERROR, no fabricated stats, no output.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d; var c x; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "does not match type prescribed") != null);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    // #3: no VAR statement — the CLASS var g drops out of the analysis set.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d; class g; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Analysis Variable : x") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Analysis Variable : g") == null);
    }
}

test "GAP-meanspctlkeywords: PRT is a MEANS-family alias only — UNIVARIATE OUTPUT still rejects it (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 2, 4, 4, 6, 8 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("d", ds);

    // UNIVARIATE's OUTPUT keyword table (Table 4.14, printed p.354) lists PROBT and
    // NO PRT alias, and it spells aliases out elsewhere in the same table
    // ("KURTOSIS | KURT", "Q1 | P25") — so `prt=` must stay loud here even though
    // MEANS now accepts it. Accepting it would mean silently honouring syntax SAS
    // rejects, which is worse than the error it replaced.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var x; output out=obad prt=pr; run;", &diags);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "is not a UNIVARIATE statistic") != null);
        try t.expect(lib.find("obad") == null); // no dataset from a rejected keyword
    }
    // The control that keeps the guard honest: the CANONICAL spelling still works.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var x; output out=ogood probt=pb; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("ogood") != null);
    }
    // And MEANS accepts BOTH spellings, giving the same value — that equality is the
    // entire meaning of "alias" ("PROBT | PRT", printed p.1492).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d; var x; output out=om probt=pb prt=pr; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const om = lib.find("om").?;
        const ipb = om.indexOf("pb").?;
        const ipr = om.indexOf("pr").?;
        try t.expectEqual(toNum(om.rows.items[0][ipb]), toNum(om.rows.items[0][ipr]));
    }
}

test "GAP-meanspctlkeywords: P20–P80 are MEANS-family only — UNIVARIATE OUTPUT rejects them; a VAR named p20 is still a column (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("p20", .num);
    for ([_][2]f64{ .{ 1, 2 }, .{ 1, 4 }, .{ 2, 4 }, .{ 2, 6 }, .{ 2, 8 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);

    // (a) UNIVARIATE's OUTPUT table (Table 4.14, printed p.354) stops at
    // P1/P5/P10/P25/P50/P75/P90/P95/P99 — the six MEANS-family percentiles must
    // fail LOUD there, not silently decode via the shared statFromKw.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var p20; output out=obad p20=q; run;", &diags);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "is not a UNIVARIATE statistic") != null);
        try t.expect(lib.find("obad") == null);
    }
    // (b) MEANS computes them: on {2,4,4,6,8} (n=5), np = p/100·n is an integer
    // position for both — P20: np=1 → (x1+x2)/2 = 3; P80: np=4 → (x4+x5)/2 = 7
    // (QNTLDEF=5, the same rule the BUG-meanspctlmore fixture pins).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d noprint; var p20; output out=om p20=q p80=r; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const om = lib.find("om").?;
        try t.expectEqual(@as(f64, 3), toNum(om.rows.items[0][om.indexOf("q").?]));
        try t.expectEqual(@as(f64, 7), toNum(om.rows.items[0][om.indexOf("r").?]));
    }
    // (c) OVER-STRICTNESS PIN: statFromKw is how TABULATE/REPORT tell a STATISTIC
    // from a COLUMN NAME, so a VAR actually named p20 must not be silently eaten.
    // REPORT resolves COLUMN names against the dataset → renders the DATA column
    // (Σp20 = 2+4+4+6+8 = 24 under REPORT's default SUM).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g p20; run;", &diags);
        try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "24") != null);
    }
    // TABULATE: the statistic interpretation WINS over the var name in a TABLE
    // crossing (exactly as P10 always has), leaving no analysis variable — and a
    // statistic without one is malformed SAS (p.2548: "Statistic keywords other
    // than N must be associated with an analysis variable"), so it fails LOUD as
    // a user error (rc 1, D-009 — GAP-tabulateforms #7 moved it off the rc-2
    // unsupported channel), never a silently wrong table.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var p20; table g, p20; run;", &diags);
        try t.expectError(error.ParseError, runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "requires an analysis variable") != null);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "GAP-meansoutguards: MEANS/UNIVARIATE OUTPUT OUT= silent drops fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 1 }, .{ 2, 2 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);

    // (a) MEANS: OUTPUT OUT= with CLASS and no explicit stat list would emit a
    // misleading overall-only dataset (no `g`, no _TYPE_ rows). Must fail loud.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d; class g; output out=oa; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "CLASS and no explicit statistic list") != null);
        try t.expect(lib.find("oa") == null); // no misleading dataset produced
    }
    // (a) baseline: OUTPUT OUT= with no CLASS is still the correct overall long form.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d; var x; output out=oab; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("oab") != null);
    }

    // (b) UNIVARIATE: pctlpts=/pctlpre= are unimplemented; skipping them would drop
    // P33/P66 from `o`. Must fail loud naming the option, and produce no dataset.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var x; output out=ob pctlpts=33 66 pctlpre=P median=med; run;", &diags);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "pctlpts") != null);
        try t.expect(lib.find("ob") == null); // requested percentiles never vanish silently
    }
    // (b) baseline: a recognized stat-only OUTPUT still builds the dataset.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var x; output out=obb median=med; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("obb") != null);
    }

    // (c) UNIVARIATE: WEIGHT with a percentile in OUTPUT — the shared MEANS builder
    // would emit an UNWEIGHTED percentile silently. Must fail loud (WEIGHT-uni-impl).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var x; weight g; output out=ow median=m; run;", &diags);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "weighted OUTPUT percentile") != null);
    }
}

test "BUG-meansoutdupname/meansoutnamecount: OUTPUT dup names + name-count mismatch fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 20 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);

    // (a) bare `mean= std=` reuse the analysis-var name → TWO columns both named
    // `x` — a structurally broken dataset SAS refuses ("Variable x already exists").
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d noprint; var x; output out=od mean= std=; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "duplicate column name x in OUTPUT OUT=od") != null);
        try t.expect(lib.find("od") == null); // no broken dataset produced
    }
    // (b) name count ≠ var count: fewer names silently dropped vars, more names
    // cloned a value into duplicate columns — both must fail loud.
    for ([_][]const u8{
        "proc means data=d noprint; var x y; output out=oc mean=m; run;", // 1 name, 2 vars
        "proc means data=d noprint; var x y; output out=oc mean=a b c; run;", // 3 names, 2 vars
    }) |src| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "name(s) given for") != null);
        try t.expect(lib.find("oc") == null);
    }
    // (c) baselines stay green: properly-named stats, matched counts, AUTONAME.
    for ([_][]const u8{
        "proc means data=d noprint; var x; output out=ok1 mean=m std=s; run;",
        "proc means data=d noprint; var x y; output out=ok2 mean=mx my n=nx ny; run;",
        "proc means data=d noprint; var x y; output out=ok3 mean(x)=m; run;",
        "proc means data=d noprint; var x; output out=ok4 mean= std= / autoname; run;",
    }) |src| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
    }
    try t.expect(lib.find("ok1") != null and lib.find("ok2") != null and lib.find("ok3") != null and lib.find("ok4") != null);
}

test "BUG-meanstypes/meansways: TYPES/WAYS restrict the CLASS combos; misuse fails loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][3]f64{ .{ 1, 1, 10 }, .{ 1, 2, 20 }, .{ 2, 1, 30 } }) |r|
        try ds.appendRow(&.{ numV(r[0]), numV(r[1]), numV(r[2]) });
    try lib.put("d", ds);

    // `types a;` → ONLY the a-alone table: the collapsed a=1 group (Mean 15)
    // appears, the a*b cross cells (Mean 10) do NOT — previously silently the cross.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d n mean; class a b; types a; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "15.0000000") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "10.0000000") == null);
    }
    // `ways 1;` → both 1-way tables (a alone AND b alone).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d n mean; class a b; ways 1; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        var ntables: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "Analysis Variable : x")) |p| {
            ntables += 1;
            pos = p + 1;
        }
        try t.expectEqual(@as(usize, 2), ntables);
    }
    // Misuse fails loud, never silently regroups.
    for ([_][]const u8{
        "proc means data=d; class a b; types c; var x; run;", // not a CLASS var
        "proc means data=d; class a b; types a; ways 1; var x; run;", // TYPES+WAYS
        "proc means data=d; class a b; types a; var x; output out=o n=n1; run;", // with OUTPUT
        "proc means data=d; class a b; ways 3; var x; run;", // degree > #CLASS
        "proc means data=d; types a; var x; run;", // no CLASS
    }) |src| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
    }
    try t.expect(lib.find("o") == null); // no misleading OUTPUT dataset produced
}

test "BUG-meanstypescross: TYPES paren-group crossing expands per the doc — no spurious _TYPE_=0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    _ = try ds.addColumn("c", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][4]f64{ .{ 1, 1, 1, 10 }, .{ 2, 1, 2, 30 } }) |r|
        try ds.appendRow(&.{ numV(r[0]), numV(r[1]), numV(r[2]), numV(r[3]) });
    try lib.put("d", ds);

    // `types (a);` must equal `types a;` — ONE a-alone table. The loop this
    // replaced emitted a spurious overall (_TYPE_=0) table for ANY `(`
    // (probed by @pi-g2: two tables vs one). Pin: exactly one table, the
    // a=1 cell mean 10 present, the overall mean 20 absent.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d n mean; class a b c; types (a); var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        var ntables: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "Analysis Variable : x")) |p| {
            ntables += 1;
            pos = p + 1;
        }
        try t.expectEqual(@as(usize, 1), ntables);
        try t.expect(std.mem.indexOf(u8, out.items, "10.0000000") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "20.0000000") == null); // the spurious overall mean
    }
    // The doc's grouping syntax (Procedures Guide 7th ed., printed p. 1512):
    // `types (a b)*c;` = `types a*c b*c;` — exactly TWO tables, no overall,
    // no singles. Old parse: {}, {a}, {b,c} — three tables, two of them wrong.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d n mean; class a b c; types (a b)*c; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        var ntables: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "Analysis Variable : x")) |p| {
            ntables += 1;
            pos = p + 1;
        }
        try t.expectEqual(@as(usize, 2), ntables);
        try t.expect(std.mem.indexOf(u8, out.items, "20.0000000") == null); // overall mean: not requested
    }
    // `types a*(b c);` = `types a*b a*c;` — the doc's other shape, two tables.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d n mean; class a b c; types a*(b c); var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        var ntables: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "Analysis Variable : x")) |p| {
            ntables += 1;
            pos = p + 1;
        }
        try t.expectEqual(@as(usize, 2), ntables);
    }
    // `types ();` still requests the overall table (control): one table,
    // overall mean 20 present.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d n mean; class a b c; types (); var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "20.0000000") != null);
    }
    // Malformed requests fail LOUD, never silently regroup.
    for ([_][]const u8{
        "proc means data=d; class a b c; types a*; var x; run;", // trailing `*`
        "proc means data=d; class a b c; types (a; var x; run;", // unclosed group
        "proc means data=d; class a b c; types ()*a; var x; run;", // `()` mixed into a crossing
        "proc means data=d; class a b c; types *a; var x; run;", // `*` with no left factor
    }) |src| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
    }
}

test "proc WHERE (statement + data= option) filters rows, leaves the source intact (BUG-procwhere)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("age", .num);
    for ([_]f64{ 30, 45, 20, 55 }) |v| try ds.appendRow(&.{numV(v)}); // only 45,55 pass age>40
    try lib.put("have", ds);

    // WHERE statement: N=2, Mean=(45+55)/2=50 over the filtered subset
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have n mean; var age; where age > 40; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "50.0000000") != null); // mean of the 2 kept rows
        try t.expect(std.mem.indexOf(u8, out.items, "37.5000000") == null); // NOT the all-4 mean
    }
    // where= dataset option, same result
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have(where=(age > 40)) n mean; var age; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "50.0000000") != null);
    }
    // the library dataset is untouched (filter ran on a copy) — still 4 rows
    try t.expectEqual(@as(usize, 4), lib.find("have").?.rowCount());
}

test "proc means combined table: multiple vars + requested stats (proc_means_var)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ numV(1), numV(100) });
    try ds.appendRow(&.{ numV(2), numV(200) });
    try ds.appendRow(&.{ numV(3), numV(300) });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc means data=have n mean sum; var x y; run;", &diags);
    try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "                          The MEANS Procedure\n" ++
        "\n" ++
        "Variable     N            Mean             Sum\n" ++
        "------------------------------------------------------\n" ++
        "x            3       2.0000000       6.0000000\n" ++
        "y            3     200.0000000     600.0000000\n" ++
        "------------------------------------------------------\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc freq excludes missing and prints Frequency Missing (BUG-freqmiss)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    for ([_]Value{ numV(1), Value.missing, numV(1), numV(2), Value.missing }) |v| try ds.appendRow(&.{v});
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc freq data=d; tables g; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // missing (the two `.`) is not a category; percents are over N=3, not 5
    try t.expect(std.mem.indexOf(u8, out.items, "66.67") != null); // 2/3
    try t.expect(std.mem.indexOf(u8, out.items, "33.33") != null); // 1/3
    try t.expect(std.mem.indexOf(u8, out.items, "40.00") == null); // would be 2/5 if miss counted
    try t.expect(std.mem.indexOf(u8, out.items, "Frequency Missing = 2") != null);
}

test "proc freq all-missing still prints Frequency Missing; WEIGHT makes the count weighted (NOTE-freqallmissnone)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]Value{ Value.missing, Value.missing, Value.missing }) |v| try ds.appendRow(&.{v});
    try lib.put("d", ds);
    // The chapter's own worked example (Figure 3.12, p.157): A/Freq = 1 2, 2 2, . 2.
    const one = try a.create(Dataset);
    one.* = Dataset.init(a, "one");
    _ = try one.addColumn("a", .num);
    _ = try one.addColumn("f", .num);
    try one.appendRow(&.{ numV(1), numV(2) });
    try one.appendRow(&.{ numV(2), numV(2) });
    try one.appendRow(&.{ Value.missing, numV(2) });
    try lib.put("one", one);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc freq data=d; tables x; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    // p.156: "The procedure displays the number of missing observations
    // following each table" — even when EVERY observation is missing (the
    // table has no rows; the count line must still appear).
    try t.expect(std.mem.indexOf(u8, out.items, "Frequency Missing = 3") != null);

    var out2: std.ArrayList(u8) = .empty;
    const toks2 = try lex.tokenize(a, "proc freq data=one; tables a; weight f; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out2, toks2);
    // Figure 3.12's Default panel: one missing obs carrying Freq=2 → the line
    // is the WEIGHTED count 2, not a row count of 1.
    try t.expect(std.mem.indexOf(u8, out2.items, "Frequency Missing = 2") != null);
    try t.expect(std.mem.indexOf(u8, out2.items, "Frequency Missing = 1") == null);
}

test "computeStats: N/mean/sample-std/min/max, missing skipped" {
    const rows = [_][]const Value{
        &.{numV(10)}, &.{numV(20)}, &.{numV(30)}, &.{numV(40)}, &.{Value.missing},
    };
    const s = computeStats(&rows, 0, null);
    try t.expectEqual(@as(usize, 4), s.n); // missing not counted
    try t.expectEqual(@as(f64, 25), s.mean);
    try t.expectEqual(@as(f64, 10), s.min);
    try t.expectEqual(@as(f64, 40), s.max);
    try t.expectApproxEqAbs(@as(f64, 12.9099445), s.std, 1e-6);
}

test "computeStatsV: VARDEF= divisor applies to std/var (BUG-statvardef)" {
    // x = 2 4 6 8 10 → mean 6, CSS 40; DF var 40/4=10, N var 40/5=8.
    const rows = [_][]const Value{
        &.{numV(2)}, &.{numV(4)}, &.{numV(6)}, &.{numV(8)}, &.{numV(10)},
    };
    const df = computeStatsV(&rows, 0, null, .df);
    try t.expectApproxEqAbs(@as(f64, 10), df.std * df.std, 1e-9); // default unchanged
    const vn = computeStatsV(&rows, 0, null, .n);
    try t.expectApproxEqAbs(@as(f64, 8), vn.std * vn.std, 1e-9);
    try t.expectApproxEqAbs(@as(f64, 2.8284271), vn.std, 1e-6);
    // unweighted Σw == n, so WGT↔N and WDF↔DF coincide
    try t.expectApproxEqAbs(vn.std, computeStatsV(&rows, 0, null, .wgt).std, 1e-12);
    try t.expectApproxEqAbs(df.std, computeStatsV(&rows, 0, null, .wdf).std, 1e-12);
    try t.expectEqual(@as(?VarDef, .n), varDefFromName("N"));
    try t.expectEqual(@as(?VarDef, .wgt), varDefFromName("weight"));
    try t.expectEqual(@as(?VarDef, null), varDefFromName("bogus"));
}

test "pctldefPercentile: definitions 1-5 on 1..10 (BUG-univpctldef)" {
    // Expected Q1/Q3 per the SAS 9.4 UNIVARIATE "Calculating Percentiles" table.
    var pairs: [10]XW = undefined;
    for (&pairs, 0..) |*q, k| q.* = .{ .x = @floatFromInt(k + 1), .w = 1 };
    try t.expectApproxEqAbs(@as(f64, 2.5), univPercentile(&pairs, 25, 1), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 7.5), univPercentile(&pairs, 75, 1), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 2), univPercentile(&pairs, 25, 2), 1e-12); // tie → even
    try t.expectApproxEqAbs(@as(f64, 8), univPercentile(&pairs, 75, 2), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 3), univPercentile(&pairs, 25, 3), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 8), univPercentile(&pairs, 75, 3), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 2.75), univPercentile(&pairs, 25, 4), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 8.25), univPercentile(&pairs, 75, 4), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 3), univPercentile(&pairs, 25, 5), 1e-12); // def 5 unchanged
    try t.expectApproxEqAbs(@as(f64, 8), univPercentile(&pairs, 75, 5), 1e-12);
    // def 1 median of 1..10 is x₅ = 5 (no averaging); def 5 averages → 5.5
    try t.expectApproxEqAbs(@as(f64, 5), univPercentile(&pairs, 50, 1), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 5.5), univPercentile(&pairs, 50, 5), 1e-12);
}

test "computeStats: WEIGHT → weighted mean/sum/std; ≤0 counted in N, missing dropped (BUG-meanszeroweight)" {
    const rows = [_][]const Value{
        &.{ numV(10), numV(1) },
        &.{ numV(20), numV(2) },
        &.{ numV(30), numV(3) },
        &.{ numV(99), numV(0) }, // zero weight → COUNTED in N/MIN/MAX (SAS default), zero contribution
        &.{ numV(99), Value.missing }, // missing weight → excluded from N entirely
    };
    const s = computeStats(&rows, 0, 1); // col v, weight w
    try t.expectEqual(@as(usize, 4), s.n); // 3 positive + 1 zero-weight; missing-weight dropped
    try t.expectApproxEqAbs(@as(f64, 140.0 / 6.0), s.mean, 1e-9); // Σwx/Σw — zero weight adds nothing
    try t.expectEqual(@as(f64, 140), s.sum); // Σwx
    try t.expectEqual(@as(f64, 10), s.min); // zero-weight value still bounds MIN/MAX…
    try t.expectEqual(@as(f64, 99), s.max); // …the 99 with weight 0 is now the maximum
    // CSS=333.3333 (zero-weight row contributes 0), divisor n−1=3 → std=√111.1111
    try t.expectApproxEqAbs(@as(f64, 10.5409255), s.std, 1e-6);
    // same rows with no WEIGHT: the weight column is ignored, all 5 obs counted
    try t.expectEqual(@as(usize, 5), computeStats(&rows, 0, null).n);
}

test "PROC MEANS VAR/CV/STDERR/RANGE stat values (BUG-meansstatsmore)" {
    const rows = [_][]const Value{
        &.{numV(2)}, &.{numV(4)}, &.{numV(4)}, &.{numV(4)},
        &.{numV(5)}, &.{numV(5)}, &.{numV(7)}, &.{numV(9)},
    };
    const s = computeStats(&rows, 0, null); // n=8, mean=5, std=2.13809
    try t.expectApproxEqAbs(@as(f64, 4.5714286), statValue(.var_, s), 1e-6); // Std²
    try t.expectApproxEqAbs(@as(f64, 42.7617987), statValue(.cv, s), 1e-6); // 100·Std/Mean
    try t.expectApproxEqAbs(@as(f64, 0.7559289), statValue(.stderr, s), 1e-6); // Std/√n
    try t.expectEqual(@as(f64, 7), statValue(.range, s)); // max−min
    try t.expect(statFromKw("var").? == .var_ and statFromKw("stderr").? == .stderr);
}

test "computeStats: median/quantiles survive groups larger than the stack buffer (BUG-meanspctl4k)" {
    const a = std.testing.allocator;
    const N = 5000; // > the 4096 stack buffer → exercises the heap spill
    const cells = try a.alloc(Value, N);
    defer a.free(cells);
    const rows = try a.alloc([]const Value, N);
    defer a.free(rows);
    for (0..N) |i| {
        cells[i] = numV(@floatFromInt(i + 1)); // values 1..5000
        rows[i] = cells[i .. i + 1];
    }
    const s = computeStats(rows, 0, null);
    try t.expectEqual(@as(usize, N), s.n);
    try t.expectEqual(@as(f64, 2500.5), s.median); // was silently missing before the fix
    try t.expect(!std.math.isNan(s.q1) and !std.math.isNan(s.q3));
}

test "proc tabulate honors the requested statistic, not always SUM (BUG-tabstat)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("a"), numV(10) });
    try ds.appendRow(&.{ strV("a"), numV(20) });
    try ds.appendRow(&.{ strV("b"), numV(5) });
    try lib.put("d", ds);

    // mean: a=15, b=5 (not 30/5 as the sum would give)
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var v; table g, v*mean; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Mean") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "15") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "30") == null); // the old sum bug
    }
    // n: a=2, b=1
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var v; table g, v*n; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "| N |") != null or std.mem.indexOf(u8, out.items, "N") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "| 2 |") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "| 1 |") != null);
    }
    // multi-stat crossing v*(sum mean): both columns render (BUG-tabmulti)
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var v; table g, v*(sum mean); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Sum") != null); // stat 1
        try t.expect(std.mem.indexOf(u8, out.items, "Mean") != null); // stat 2 (was dropped)
        try t.expect(std.mem.indexOf(u8, out.items, "30") != null); // a sum
        try t.expect(std.mem.indexOf(u8, out.items, "15") != null); // a mean
    }
}

test "BUG-tabulatebyfreq: BY-group tables (not pooled), FREQ weighting, unsorted BY fails loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // F1: BY site -> one table PER group, values per-group not pooled.
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("site", .num);
    _ = try ds.addColumn("trt", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ numV(1), strV("A"), numV(100) });
    try ds.appendRow(&.{ numV(2), strV("A"), numV(300) });
    try ds.appendRow(&.{ numV(2), strV("A"), numV(400) });
    try lib.put("d", ds);
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; by site; class trt; var v; table trt, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "site=1") != null); // heading per group
        try t.expect(std.mem.indexOf(u8, out.items, "site=2") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "100") != null); // site 1 sum
        try t.expect(std.mem.indexOf(u8, out.items, "700") != null); // site 2 sum (300+400), not pooled 800
        try t.expect(std.mem.indexOf(u8, out.items, "800") == null); // the old pooled-over-all bug
    }

    // F2: FREQ f -> obs counts trunc(f) times; N=Σtrunc(f), Sum weighted.
    var lib2 = Library.init(a);
    const c = try a.create(Dataset);
    c.* = Dataset.init(a, "c");
    _ = try c.addColumn("trt", .char);
    _ = try c.addColumn("v", .num);
    _ = try c.addColumn("f", .num);
    try c.appendRow(&.{ strV("A"), numV(10), numV(3) });
    try c.appendRow(&.{ strV("B"), numV(20), numV(2) });
    try lib2.put("c", c);
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=c; freq f; class trt; var v; table trt, v*(n sum); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib2, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "| 3 |") != null); // A: N = trunc(f) = 3
        try t.expect(std.mem.indexOf(u8, out.items, "30") != null); // A: sum = 10*3
        try t.expect(std.mem.indexOf(u8, out.items, "40") != null); // B: sum = 20*2
    }

    // Unsorted BY (1,2,1) fails loud (captured), like MEANS/TRANSPOSE.
    var lib3 = Library.init(a);
    const u = try a.create(Dataset);
    u.* = Dataset.init(a, "u");
    _ = try u.addColumn("site", .num);
    _ = try u.addColumn("trt", .char);
    _ = try u.addColumn("v", .num);
    try u.appendRow(&.{ numV(1), strV("A"), numV(1) });
    try u.appendRow(&.{ numV(2), strV("A"), numV(2) });
    try u.appendRow(&.{ numV(1), strV("A"), numV(3) });
    try lib3.put("u", u);
    var diags3 = diag.Diagnostics.init(a);
    var out3: std.ArrayList(u8) = .empty;
    const toks3 = try lex.tokenize(a, "proc tabulate data=u; by site; class trt; var v; table trt, v*sum; run;", &diags3);
    try t.expectError(error.ParseError, runTabulate(.{ .arena = a, .lib = &lib3, .diags = &diags3 }, &out3, toks3));
    try t.expect(std.mem.indexOf(u8, try diags3.render(), "not sorted in ascending sequence") != null);
}

test "proc tabulate: pctn/pctsum are shares of the grand total + ALL row; unknown stat fails loud (BUG-tabpctsum/BUG-tabulateall)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(1), numV(20) });
    try ds.appendRow(&.{ numV(2), numV(30) });
    try lib.put("d", ds);

    // pctsum: g=1 → 30/60 = 50, g=2 → 50, All → 100 (never the old silent SUM).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var x; table g all, x*(sum pctsum); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Pctsum") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "|All") != null); // grand-total row (was dropped)
        try t.expect(std.mem.indexOf(u8, out.items, "50") != null); // a pct share — sums are only 30/60
        try t.expect(std.mem.indexOf(u8, out.items, "100") != null); // the All row's pctsum
    }
    // an unknown stat keyword in `(...)` fails loud instead of rendering SUM
    // under a mislabeled header.
    {
        g_test_last_unsup = "";
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var x; table g, x*(sum pctsumx); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "unknown statistic 'pctsumx'") != null);
        try t.expectEqual(@as(usize, 0), out.items.len); // nothing rendered past the gap
    }
}

test "proc tabulate: ORDER=/LABEL/KEYLABEL//box= honored, incl. the 2-way cross (GAP-tabulateopts)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    // g: first appearance c,a,b — counts b=3 a=2 c=1 — sums b=130 a=70 c=10.
    try ds.appendRow(&.{ strV("c"), numV(10) });
    try ds.appendRow(&.{ strV("a"), numV(20) });
    try ds.appendRow(&.{ strV("b"), numV(30) });
    try ds.appendRow(&.{ strV("b"), numV(40) });
    try ds.appendRow(&.{ strV("a"), numV(50) });
    try ds.appendRow(&.{ strV("b"), numV(60) });
    try lib.put("d", ds);

    // ORDER=DATA: first-appearance c,a,b (was silently re-sorted a,b,c).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d order=data; class g; var v; table g, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|c").? < std.mem.indexOf(u8, out.items, "\n|a").?);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|a").? < std.mem.indexOf(u8, out.items, "\n|b").?);
    }
    // ORDER=FREQ: descending count b(3),a(2),c(1) — neither lexical nor appearance.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d order=freq; class g; var v; table g, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|b").? < std.mem.indexOf(u8, out.items, "\n|a").?);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|a").? < std.mem.indexOf(u8, out.items, "\n|c").?);
    }
    // LABEL/KEYLABEL + `/ box=`: header text and the corner box (all were silent no-ops).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var v; table g, v*sum / box='Corner'; label g='Group' v='Dose'; keylabel sum='Total'; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Group") != null); // row-column header
        try t.expect(std.mem.indexOf(u8, out.items, "Dose") != null); // analysis-var header
        try t.expect(std.mem.indexOf(u8, out.items, "Total") != null); // KEYLABEL stat heading
        try t.expect(std.mem.indexOf(u8, out.items, "Sum") == null); // renamed away
        try t.expect(std.mem.indexOf(u8, out.items, "Corner") != null); // the corner box
    }
    // ORDER=DATA on the 2-way cross: column levels z,y in appearance order
    // (the internal/lexical default would give y,z).
    {
        const ds2 = try a.create(Dataset);
        ds2.* = Dataset.init(a, "d2");
        _ = try ds2.addColumn("r", .char);
        _ = try ds2.addColumn("c", .char);
        _ = try ds2.addColumn("x", .num);
        try ds2.appendRow(&.{ strV("p"), strV("z"), numV(1) });
        try ds2.appendRow(&.{ strV("p"), strV("y"), numV(2) });
        try ds2.appendRow(&.{ strV("q"), strV("z"), numV(3) });
        try ds2.appendRow(&.{ strV("q"), strV("y"), numV(4) });
        try lib.put("d2", ds2);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d2 order=data; class r c; var x; table r, c*x*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "z").? < std.mem.indexOf(u8, out.items, "y").?);
    }
}

test "proc tabulate: rts=/unknown table options, COLPCTN-family stats, 1-dim tables, bad ORDER= fail loud (GAP-tabulateopts)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("a"), numV(1) });
    try lib.put("d", ds);
    defer diag.resetGap();

    // Each was a SILENT no-op or the bogus "analysis variable not found" — now
    // every one fails loud naming the real culprit and renders nothing.
    const Case = struct { src: []const u8, msg: []const u8 };
    const cases = [_]Case{
        .{ .src = "proc tabulate data=d; class g; var v; table g, v*sum / rts=10; run;", .msg = "table option rts= is not supported yet" },
        .{ .src = "proc tabulate data=d; class g; var v; table g, v*sum / foobar; run;", .msg = "table option foobar is not supported yet" },
        .{ .src = "proc tabulate data=d; class g; var v; table g, v*sum / box=v; run;", .msg = "BOX= expects a quoted string" },
        .{ .src = "proc tabulate data=d; class g; var v; table g, v*colpctn; run;", .msg = "statistic 'colpctn' is not supported yet" },
        .{ .src = "proc tabulate data=d; class g; var v; table g, v*rowpctsum; run;", .msg = "statistic 'rowpctsum' is not supported yet" },
        .{ .src = "proc tabulate data=d; class g; var v; table g, v*(n reppctn); run;", .msg = "statistic 'reppctn' is not supported yet" },
        .{ .src = "proc tabulate data=d; class g; table g; run;", .msg = "one-dimensional tables are not supported yet" },
        .{ .src = "proc tabulate data=d; var v; table v; run;", .msg = "one-dimensional tables are not supported yet" },
        .{ .src = "proc tabulate data=d order=bogus; class g; var v; table g, v*sum; run;", .msg = "ORDER=bogus is not valid" },
    };
    for (cases) |cs| {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, cs.src, &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, cs.msg) != null);
        try t.expectEqual(@as(usize, 0), out.items.len); // nothing rendered past the gap
    }
}

test "proc tabulate: 2-way cross, class var in the column dim (BUG-tabulatecross)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("reg", .char);
    _ = try ds.addColumn("prod", .char);
    _ = try ds.addColumn("amt", .num);
    // reg(E/W) × prod(A/B): E:A=10, E:B=20, W:A=30, W:B=40
    try ds.appendRow(&.{ strV("E"), strV("A"), numV(10) });
    try ds.appendRow(&.{ strV("E"), strV("B"), numV(20) });
    try ds.appendRow(&.{ strV("W"), strV("A"), numV(30) });
    try ds.appendRow(&.{ strV("W"), strV("B"), numV(40) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc tabulate data=d; class reg prod; var amt; table reg, prod*amt*sum; run;", &diags);
    try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "-------------------\n" ++
        "|     |   prod    |\n" ++
        "|     |  A  |  B  |\n" ++
        "|     | amt | amt |\n" ++
        "|     | Sum | Sum |\n" ++
        "|-----+-----+-----|\n" ++
        "|reg  |     |     |\n" ++
        "|E    |  10 |  20 |\n" ++
        "|W    |  30 |  40 |\n" ++
        "-------------------\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc tabulate: PCTN/PCTSUM <denominator> definitions (GAP-tabdenom)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("reg", .char);
    _ = try ds.addColumn("prod", .char);
    _ = try ds.addColumn("amt", .num);
    // reg(E/W) × prod(A/B): E:A=10, E:B=20, W:A=30, W:B=40
    try ds.appendRow(&.{ strV("E"), strV("A"), numV(10) });
    try ds.appendRow(&.{ strV("E"), strV("B"), numV(20) });
    try ds.appendRow(&.{ strV("W"), strV("A"), numV(30) });
    try ds.appendRow(&.{ strV("W"), strV("B"), numV(40) });
    try lib.put("d", ds);

    // pctsum<prod> = cell share of the prod COLUMN subtotal: E×A 10/40=25,
    // W×A 30/40=75, E×B 20/60≈33.33 (grand-total pctsum would be 10/20/30/40).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg prod; var amt; table reg, prod*amt*(sum pctsum<prod>); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "25") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "75") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "33.333333333") != null); // BEST12. (BUG-tabrawfloat)
    }
    // pctsum<reg> = share of the reg ROW subtotal: W×A 30/70≈42.86 — a share no
    // other basis produces. Two <dim> variants of one keyword are two columns.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg prod; var amt; table reg, prod*amt*(pctsum<prod> pctsum<reg>); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "42.857142857") != null); // BEST12.
        try t.expect(std.mem.indexOf(u8, out.items, "57.142857143") != null); // BEST12.
    }
    // pctn<reg> on the no-analysis-var count path: each cell 1 of 2 in its row → 50.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg prod; table reg, prod*(n pctn<reg>); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "50") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "25") == null); // grand-total pctn would be 25
    }
    // 1-way degenerate: <rowvar> holds the only crossing dimension fixed → 100.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg; var amt; table reg, amt*pctsum<reg>; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "100") != null);
    }
    // a denominator outside the TABLE crossing fails loud, NAMING the
    // PCTN/PCTSUM denominator — never the old bogus "unknown statistic 'grp'".
    {
        g_test_last_unsup = "";
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg prod; var amt; table reg, prod*amt*pctsum<amt>; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "PCTN/PCTSUM denominator 'amt'") != null);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "unknown statistic") == null);
        try t.expectEqual(@as(usize, 0), out.items.len); // nothing rendered past the gap
    }
    // `<` on a non-PCT statistic and a compound `<a*b>` definition fail loud too.
    {
        g_test_last_unsup = "";
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg prod; var amt; table reg, prod*amt*mean<prod>; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "only PCTN and PCTSUM accept a <denominator>") != null);
    }
    {
        g_test_last_unsup = "";
        defer diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class reg prod; var amt; table reg, prod*amt*pctsum<reg*prod>; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "single class-variable denominator") != null);
    }
}

test "BUG-tabulatemed: 1-way ALL column row-restricted (#4), separate TABLE stmts (#5), CLASS / options (#6)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("x"), numV(10) });
    try ds.appendRow(&.{ strV("x"), numV(20) });
    try ds.appendRow(&.{ strV("y"), numV(30) });
    try lib.put("d", ds);

    // #4: the All column is each row's OWN subtotal (30/30) — never the grand
    // 60 on every row; the All Pctsum is the row share 50/50, never 100/100.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var v; table g, v*sum all*v*(sum pctsum); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "60") == null); // the grand total leaks nowhere
        try t.expect(std.mem.indexOf(u8, out.items, "100") == null); // All pctsum is the row share
        var n30: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "30")) |hit| : (pos = hit + 2) n30 += 1;
        try t.expectEqual(@as(usize, 4), n30); // x/y rows × (Sum, All-Sum)
    }
    // #5: two TABLE statements render TWO tables — 4 box rules, not one merged
    // table with a Sum and a Mean column side by side (2 rules).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var v; table g, v*sum; table g, v*mean; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Sum") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Mean") != null);
        var rules: usize = 0;
        var lines = std.mem.splitScalar(u8, out.items, '\n');
        while (lines.next()) |ln| {
            if (ln.len == 0) continue;
            var all_dash = true;
            for (ln) |ch| {
                if (ch != '-') {
                    all_dash = false;
                    break;
                }
            }
            if (all_dash) rules += 1;
        }
        try t.expectEqual(@as(usize, 4), rules); // two separate boxed tables
    }
    // #6: `class g / missing` keeps the missing-class obs — the "." level
    // appears (N=1, Sum=20); the default exclusion is pinned elsewhere.
    {
        const dm = try a.create(Dataset);
        dm.* = Dataset.init(a, "m");
        _ = try dm.addColumn("g", .num);
        _ = try dm.addColumn("v", .num);
        try dm.appendRow(&.{ numV(1), numV(10) });
        try dm.appendRow(&.{ Value.missing, numV(20) });
        try dm.appendRow(&.{ numV(2), numV(30) });
        try lib.put("m", dm);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=m; class g / missing; var v; table g, v*(n sum); run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|.") != null); // the missing level row
        try t.expect(std.mem.indexOf(u8, out.items, "20") != null); // its Sum
    }
    // #6: `class g / order=freq` orders the levels by descending count (b,c,a),
    // overriding the internal default (a,b,c).
    {
        const do_ = try a.create(Dataset);
        do_.* = Dataset.init(a, "o");
        _ = try do_.addColumn("g", .char);
        _ = try do_.addColumn("v", .num);
        try do_.appendRow(&.{ strV("a"), numV(1) });
        try do_.appendRow(&.{ strV("b"), numV(2) });
        try do_.appendRow(&.{ strV("b"), numV(3) });
        try do_.appendRow(&.{ strV("c"), numV(4) });
        try do_.appendRow(&.{ strV("b"), numV(5) });
        try do_.appendRow(&.{ strV("c"), numV(6) });
        try lib.put("o", do_);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=o; class g / order=freq; var v; table g, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|b").? < std.mem.indexOf(u8, out.items, "\n|c").?);
        try t.expect(std.mem.indexOf(u8, out.items, "\n|c").? < std.mem.indexOf(u8, out.items, "\n|a").?);
    }
    // #6: unknown `/` options and `/mlf` fail loud NAMING the option — never
    // the old silent swallow (they parsed as phantom class variables).
    {
        defer diag.resetGap();
        const Case = struct { src: []const u8, msg: []const u8 };
        const cases = [_]Case{
            .{ .src = "proc tabulate data=d; class g / zonk; var v; table g, v*sum; run;", .msg = "class option zonk is not supported yet" },
            .{ .src = "proc tabulate data=d; class g / mlf; var v; table g, v*sum; run;", .msg = "class option MLF (multilabel) is not supported" },
            .{ .src = "proc tabulate data=d; class g / order=bogus; var v; table g, v*sum; run;", .msg = "class option ORDER=bogus is not valid" },
            .{ .src = "proc tabulate data=d; class g / order=; var v; table g, v*sum; run;", .msg = "class option ORDER= requires a value" },
        };
        for (cases) |cs| {
            g_test_last_unsup = "";
            var out: std.ArrayList(u8) = .empty;
            const toks = try lex.tokenize(a, cs.src, &diags);
            try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
            try t.expect(std.mem.indexOf(u8, g_test_last_unsup, cs.msg) != null);
            try t.expectEqual(@as(usize, 0), out.items.len); // nothing rendered past the gap
        }
    }
}

test "proc univariate: moments + quantiles vs known values (VAR statement)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    // x = 1..5: N=5, Mean=3, Var=2.5, Std=1.5811.., USS=55, CSS=10, Skew=0, Kurt=-1.2,
    // CV=52.70.., SEM=0.7071.., Q1=2, Median=3, Q3=4, P1/P5=1, P95/P99=5, min=1, max=5.
    for ([_]f64{ 1, 2, 3, 4, 5 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc univariate data=d; var x; run;", &diags);
    try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    const o = out.items;

    const has = struct {
        fn f(hay: []const u8, needle: []const u8) bool {
            return std.mem.indexOf(u8, hay, needle) != null;
        }
    }.f;
    try t.expect(has(o, "The UNIVARIATE Procedure"));
    try t.expect(has(o, "Variable:  x"));
    try t.expect(has(o, "Moments"));
    // moments (exact for the clean ones, prefix for the irrationals)
    try t.expect(has(o, "Mean") and has(o, "Variance"));
    try t.expect(has(o, "1.5811388")); // Std Deviation
    try t.expect(has(o, "2.5")); // Variance
    try t.expect(has(o, "55")); // Uncorrected SS
    try t.expect(has(o, "-1.2")); // Kurtosis
    try t.expect(has(o, "52.704627")); // Coeff Variation
    try t.expect(has(o, "0.7071067")); // Std Error Mean
    // quantiles
    try t.expect(has(o, "100% Max"));
    try t.expect(has(o, "75% Q3"));
    try t.expect(has(o, "50% Median"));
    try t.expect(has(o, "25% Q1"));
    try t.expect(has(o, "0% Min"));
    // spot-check the quantile values render on their labelled lines
    try t.expect(has(o, "75% Q3") and has(o, "50% Median"));
    // N=5 present and CSS=10
    try t.expect(has(o, "Corrected SS"));
}

test "WEIGHT-uni-impl: weighted UNIVARIATE moments + quantiles (SAS 9.4 formulas)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("wt", .num);
    // x={10,30}, wt={1,3}: N=2, Sum Weights=4, Sum Obs=Σwx=10+90=100, Mean=25,
    // CSS=1·(10-25)²+3·(30-25)²=225+75=300, Var=CSS/(N-1)=300, Std=√300=17.32051,
    // USS=1·100+3·900=2800, SEM=Std/√Σw=17.32051/2=8.660254, CV=100·Std/Mean=69.28203.
    // Skew/Kurt missing (N<3/<4). Weighted quantiles (PCTLDEF=5, cumw over sorted):
    //   Min=10, Max=30; Q1(p25): thr=1.0=cumw@10 → avg(10,30)=20; Median(p50) thr=2.0,
    //   cumw jumps 1→4 → 30; Q3(p75) thr=3.0 → 30 (30 carries 75% of the weight mass).
    for ([_][2]f64{ .{ 10, 1 }, .{ 30, 3 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc univariate data=d; var x; weight wt; run;", &diags);
    try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    try t.expect(!diags.hasErrors());
    const o = out.items;
    const has = struct {
        fn f(hay: []const u8, needle: []const u8) bool {
            return std.mem.indexOf(u8, hay, needle) != null;
        }
    }.f;
    // Moments: weighted mean/sum/sumweights/USS are integers; std/sem/cv irrational.
    try t.expect(has(o, "Sum Weights")); // = Σw = 4 (not N=2)
    try t.expect(has(o, "17.320508")); // Std Deviation √300
    try t.expect(has(o, "8.6602540")); // Std Error Mean = Std/√Σw
    try t.expect(has(o, "69.282032")); // Coeff Variation
    try t.expect(has(o, "2800")); // Uncorrected SS Σwx²
    // Weighted quantiles: Q1=20 (boundary average), Median=Q3=30.
    try t.expect(has(o, "25% Q1"));
    try t.expect(has(o, "50% Median"));

    // Unit-check the numeric core independent of listing layout.
    const s = computeStats(ds.rows.items, 0, 1);
    try t.expectEqual(@as(usize, 2), s.n);
    try t.expectEqual(@as(f64, 4), s.sumw);
    try t.expectEqual(@as(f64, 100), s.sum);
    try t.expectEqual(@as(f64, 25), s.mean);
    try t.expectApproxEqAbs(@as(f64, 17.3205081), s.std, 1e-6);
    try t.expectEqual(@as(f64, 2800), s.uss);
    try t.expectEqual(@as(f64, 300), s.css);
    const pairs = [_]XW{ .{ .x = 10, .w = 1 }, .{ .x = 30, .w = 3 } };
    try t.expectEqual(@as(f64, 20), weightedPercentile(&pairs, 25)); // exact boundary → average
    try t.expectEqual(@as(f64, 30), weightedPercentile(&pairs, 50));
    try t.expectEqual(@as(f64, 30), weightedPercentile(&pairs, 75));
    // unweighted (w≡1) reduces to definition 5: matches percentile() exactly.
    const p1 = [_]XW{ .{ .x = 1, .w = 1 }, .{ .x = 2, .w = 1 }, .{ .x = 3, .w = 1 }, .{ .x = 4, .w = 1 } };
    const raw = [_]f64{ 1, 2, 3, 4 };
    try t.expectEqual(percentile(&raw, 25), weightedPercentile(&p1, 25));
    try t.expectEqual(percentile(&raw, 50), weightedPercentile(&p1, 50));
    try t.expectEqual(percentile(&raw, 75), weightedPercentile(&p1, 75));
}

test "proc rank: out=, ties, descending, groups, by (vs known ranks)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // helper: rank column value of the k-th output row
    const rk = struct {
        fn f(o: *Dataset, row: usize, colname: []const u8) f64 {
            return o.row(row)[o.indexOf(colname).?].num;
        }
    }.f;

    // ── ties on {10,20,20,30}: mean→1,2.5,2.5,4 ───────────────────────────────
    {
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        for ([_]f64{ 10, 20, 20, 30 }) |v| try ds.appendRow(&.{numV(v)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=d out=r ties=mean; var x; ranks rx; run;", &diags);
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const r = lib.find("r").?;
        try t.expectEqual(@as(usize, 4), r.rowCount());
        try t.expectEqual(@as(f64, 1), rk(r, 0, "rx"));
        try t.expectEqual(@as(f64, 2.5), rk(r, 1, "rx"));
        try t.expectEqual(@as(f64, 2.5), rk(r, 2, "rx"));
        try t.expectEqual(@as(f64, 4), rk(r, 3, "rx"));
        try t.expectEqual(@as(f64, 20), rk(r, 1, "x")); // original var kept alongside
    }
    // ── ties=high and ties=dense on the same data ─────────────────────────────
    {
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        for ([_]f64{ 10, 20, 20, 30 }) |v| try ds.appendRow(&.{numV(v)});
        try lib.put("d", ds);
        var o1: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &o1, try lex.tokenize(a, "proc rank data=d out=rh ties=high; var x; ranks rx; run;", &diags));
        const rh = lib.find("rh").?;
        try t.expectEqual(@as(f64, 3), rk(rh, 1, "rx")); // high: tied → 3,3
        try t.expectEqual(@as(f64, 3), rk(rh, 2, "rx"));
        var o2: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &o2, try lex.tokenize(a, "proc rank data=d out=rd ties=dense; var x; ranks rx; run;", &diags));
        const rd = lib.find("rd").?;
        try t.expectEqual(@as(f64, 1), rk(rd, 0, "rx")); // dense: 1,2,2,3
        try t.expectEqual(@as(f64, 2), rk(rd, 1, "rx"));
        try t.expectEqual(@as(f64, 3), rk(rd, 3, "rx"));
    }
    // ── descending: largest gets rank 1; ranks replace the var in place ───────
    {
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        for ([_]f64{ 10, 40, 20, 30 }) |v| try ds.appendRow(&.{numV(v)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, try lex.tokenize(a, "proc rank data=d out=rr descending; var x; run;", &diags));
        const r = lib.find("rr").?;
        try t.expectEqual(@as(usize, 1), r.columns.items.len); // no ranks stmt → in-place, still one col
        try t.expectEqual(@as(f64, 4), rk(r, 0, "x")); // 10 is smallest → rank 4 descending
        try t.expectEqual(@as(f64, 1), rk(r, 1, "x")); // 40 → rank 1
        try t.expectEqual(@as(f64, 3), rk(r, 2, "x")); // 20 → rank 3
        try t.expectEqual(@as(f64, 2), rk(r, 3, "x")); // 30 → rank 2
    }
    // ── groups=4 (quartiles) over 1..8 → 0,0,1,1,2,2,3,3 ──────────────────────
    {
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("x", .num);
        for ([_]f64{ 1, 2, 3, 4, 5, 6, 7, 8 }) |v| try ds.appendRow(&.{numV(v)});
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, try lex.tokenize(a, "proc rank data=d out=q groups=4; var x; ranks grp; run;", &diags));
        const q = lib.find("q").?;
        const want = [_]f64{ 0, 0, 1, 1, 2, 2, 3, 3 };
        for (want, 0..) |w, r| try t.expectEqual(w, rk(q, r, "grp"));
    }
    // ── BY groups rank independently within each group ────────────────────────
    {
        var lib = Library.init(a);
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "d");
        _ = try ds.addColumn("g", .char);
        _ = try ds.addColumn("x", .num);
        // g=A: 5,15 ; g=B: 30,10,20  (sorted by g as SAS requires)
        try ds.appendRow(&.{ strV("A"), numV(5) });
        try ds.appendRow(&.{ strV("A"), numV(15) });
        try ds.appendRow(&.{ strV("B"), numV(30) });
        try ds.appendRow(&.{ strV("B"), numV(10) });
        try ds.appendRow(&.{ strV("B"), numV(20) });
        try lib.put("d", ds);
        var out: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, try lex.tokenize(a, "proc rank data=d out=rb; by g; var x; ranks xr; run;", &diags));
        const r = lib.find("rb").?;
        try t.expectEqual(@as(f64, 1), rk(r, 0, "xr")); // A: 5 → 1
        try t.expectEqual(@as(f64, 2), rk(r, 1, "xr")); // A: 15 → 2
        try t.expectEqual(@as(f64, 3), rk(r, 2, "xr")); // B: 30 → 3 (of A? no—within B, 30 is largest → 3)
        try t.expectEqual(@as(f64, 1), rk(r, 3, "xr")); // B: 10 → 1
        try t.expectEqual(@as(f64, 2), rk(r, 4, "xr")); // B: 20 → 2
    }
}

test "proc contents: metadata listing + OUT= variable table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("name", .char); // position 1
    _ = try ds.addColumn("age", .num); //  position 2
    _ = try ds.addColumn("city", .char); // position 3
    ds.setFormat("age", "3.");
    try ds.appendRow(&.{ strV("Alice"), numV(30), strV("NYC") });
    try ds.appendRow(&.{ strV("Bob"), numV(25), strV("LA") });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc contents data=have out=meta; run;", &diags);
    try runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    const o = out.items;
    const has = struct {
        fn f(hay: []const u8, needle: []const u8) bool {
            return std.mem.indexOf(u8, hay, needle) != null;
        }
    }.f;
    try t.expect(has(o, "The CONTENTS Procedure"));
    try t.expect(has(o, "Observations   2"));
    try t.expect(has(o, "Variables      3"));
    try t.expect(has(o, "Num") and has(o, "Char"));
    try t.expect(has(o, "3.")); // age's format
    // alphabetic order in the listing: age, city, name
    try t.expect(std.mem.indexOf(u8, o, "age").? < std.mem.indexOf(u8, o, "city").?);
    try t.expect(std.mem.indexOf(u8, o, "city").? < std.mem.indexOf(u8, o, "name").?);

    // OUT= dataset: one row per variable in VARNUM order, with the metadata columns
    const meta = lib.find("meta").?;
    try t.expectEqual(@as(usize, 3), meta.rowCount());
    const nm = meta.indexOf("NAME").?;
    const ty = meta.indexOf("TYPE").?;
    const ln = meta.indexOf("LENGTH").?;
    const vn = meta.indexOf("VARNUM").?;
    // row 0 = name (char, len 5 = "Alice", varnum 1)
    try t.expectEqualStrings("name", meta.row(0)[nm].str);
    try t.expectEqual(@as(f64, 2), meta.row(0)[ty].num); // 2 = character
    try t.expectEqual(@as(f64, 5), meta.row(0)[ln].num); // widest value "Alice"
    try t.expectEqual(@as(f64, 1), meta.row(0)[vn].num);
    // row 1 = age (numeric, len 8, varnum 2)
    try t.expectEqual(@as(f64, 1), meta.row(1)[ty].num); // 1 = numeric
    try t.expectEqual(@as(f64, 8), meta.row(1)[ln].num);
    try t.expectEqual(@as(f64, 2), meta.row(1)[vn].num);
    // BUG-contentsfmtcol: the plain numeric `3.` format has no NAME, so FORMAT is
    // blank and the width/decimals land in FORMATL/FORMATD (SAS semantics).
    try t.expectEqualStrings("", meta.row(1)[meta.indexOf("FORMAT").?].str);
    try t.expectEqual(@as(f64, 3), meta.row(1)[meta.indexOf("FORMATL").?].num);
    try t.expectEqual(@as(f64, 0), meta.row(1)[meta.indexOf("FORMATD").?].num);
}

test "proc contents: char declared length from a $w. format (BUG-contentsmeta)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("code", .char); // declared $8 (via format), values shorter
    _ = try ds.addColumn("plain", .char); // no format → widest value
    ds.setFormat("code", "$8.");
    try ds.appendRow(&.{ strV("AB"), strV("hello") });
    try ds.appendRow(&.{ strV("CD"), strV("hi") });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc contents data=d out=m noprint; run;", &diags);
    try runContents(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    const m = lib.find("m").?;
    const ln = m.indexOf("LENGTH").?;
    const nm = m.indexOf("NAME").?;
    // code: declared length 8 from the $8. format (NOT the widest value 2)
    try t.expectEqualStrings("code", m.row(0)[nm].str);
    try t.expectEqual(@as(f64, 8), m.row(0)[ln].num);
    // plain: no format → widest value "hello" = 5
    try t.expectEqualStrings("plain", m.row(1)[nm].str);
    try t.expectEqual(@as(f64, 5), m.row(1)[ln].num);

    // width extraction: named char formats, and no-width formats
    try t.expectEqual(@as(?usize, 20), charFormatWidth("$char20."));
    try t.expectEqual(@as(?usize, 8), charFormatWidth("$8."));
    try t.expectEqual(@as(?usize, null), charFormatWidth("$yn.")); // no width
    try t.expectEqual(@as(?usize, null), charFormatWidth("3.")); // numeric format, not char
}

test "tabNum / cellText render non-finite as '.' (BUG-procinf)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const inf = std.math.inf(f64);
    try t.expectEqualStrings(".", try tabNum(a, inf));
    try t.expectEqualStrings(".", try tabNum(a, -inf));
    try t.expectEqualStrings(".", try cellText(a, .{ .num = inf }));
    try t.expectEqualStrings("5", try tabNum(a, 5)); // finite still fine
}

test "proc report: char left, numeric right (matches proc_report.sas)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("sales", .num);
    try ds.appendRow(&.{ strV("Alice"), numV(100) });
    try ds.appendRow(&.{ strV("Bob"), numV(200) });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc report data=have nowd; columns name sales; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "name     sales\n" ++
        "\n" ++
        "Alice      100\n" ++
        "Bob        200\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc report: GROUP var + ANALYSIS SUM collapses to one row per level (BUG-reportgroup)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    // a{10,20} b{30,40} — GROUP g + SUM v must give a=30, b=70 (2 rows, not 4 detail)
    try ds.appendRow(&.{ strV("a"), numV(10) });
    try ds.appendRow(&.{ strV("b"), numV(30) });
    try ds.appendRow(&.{ strV("a"), numV(20) });
    try ds.appendRow(&.{ strV("b"), numV(40) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column g v; define g / group; define v / analysis sum; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "g     v\n" ++
        "\n" ++
        "a    30\n" ++
        "b    70\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc report: ACROSS / comma-nested column fails loud, no wrong table (BUG-reportacross)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("reg", .char);
    _ = try ds.addColumn("prod", .char);
    _ = try ds.addColumn("sales", .num);
    try ds.appendRow(&.{ strV("E"), strV("A"), numV(10) });
    try ds.appendRow(&.{ strV("E"), strV("B"), numV(20) });
    try ds.appendRow(&.{ strV("W"), strV("A"), numV(30) });
    try ds.appendRow(&.{ strV("W"), strV("B"), numV(40) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column reg prod,sales; define reg / group; define prod / across; define sales / analysis sum; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // ACROSS crosstab is unsupported → emit nothing (UNSUPPORTED to stderr),
    // never the plausible-but-wrong collapsed "E A 30 / W A 70" table.
    try t.expectEqualStrings("", out.items);
}

test "Student-t CDF + inverse for MEANS CLM/T/PROBT (MEANS-cistat)" {
    // tinv(0.975, 10) = 2.228138852; probt sanity: cdf(0)=.5, symmetric.
    try t.expectApproxEqAbs(@as(f64, 2.228138852), tQuantile(0.975, 10), 1e-6);
    try t.expectApproxEqAbs(@as(f64, 0.5), studentTcdf(0, 8), 1e-12);
    try t.expectApproxEqAbs(@as(f64, 0.7953143998), studentTcdf(0.9, 5), 1e-9);
    // x=2..10: n=9, mean=6, std=sqrt(7.5), se=std/3 → lclm/uclm = 6 ± t(.975,8)·se.
    const s = computeStats(&.{
        &.{numV(2)}, &.{numV(3)}, &.{numV(4)}, &.{numV(5)}, &.{numV(6)},
        &.{numV(7)}, &.{numV(8)}, &.{numV(9)}, &.{numV(10)},
    }, 0, null);
    try t.expectApproxEqAbs(@as(f64, 3.8949159), statValue(.lclm, s), 1e-6);
    try t.expectApproxEqAbs(@as(f64, 8.1050841), statValue(.uclm, s), 1e-6);
    try t.expectApproxEqAbs(@as(f64, 6.5726707), statValue(.t, s), 1e-6);

    // MEANS-clmprec: weighted CL endpoint precision. x={1,2,3} w={2,2,2}: N=3 (df=2),
    // weighted mean=2, weighted std=√2, Σw=6, se=√2/√6. lclm = mean − TINV(0.975,2)·se.
    // Authoritative TINV(0.975,2)=4.302652729696142 (scipy stats.t.ppf) → the exact
    // closed form for df=2 is √(2p²/(1−p²)) with p=0.95, = 4.302652729749464. Both
    // agree to 1e-10; our inverse-t must land there, so lclm = −0.484137711720.
    // (Note: 1e-11-accurate vs the authoritative value — already well past the 1e-9 goal.)
    try t.expectApproxEqAbs(@as(f64, 4.302652729696), tQuantile(0.975, 2), 1e-9);
    try t.expectApproxEqAbs(@as(f64, 2.570581835636), tQuantile(0.975, 5), 1e-9);
    const sw = computeStats(&.{
        &.{ numV(1), numV(2) }, &.{ numV(2), numV(2) }, &.{ numV(3), numV(2) },
    }, 0, 1);
    try t.expectEqual(@as(f64, 2), sw.mean);
    try t.expectApproxEqAbs(@as(f64, -0.484137711720), statValue(.lclm, sw), 1e-8);
    try t.expectApproxEqAbs(@as(f64, 4.484137711720), statValue(.uclm, sw), 1e-8);
}

test "proc report: COMPUTED column fails loud, no silently-dropped column (BUG-reportcomputed)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(2), numV(20) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column a b c; define a / display; define b / analysis sum; define c / computed; compute c; c=b.sum*2; endcomp; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // The derived column c can't be honored → emit nothing (UNSUPPORTED to stderr),
    // never an a/b table with c silently dropped.
    try t.expectEqualStrings("", out.items);
}

test "proc report: DEFINE options — GROUP DESC / ORDER=FREQ / NOPRINT + fail-loud (tick240)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    // A=1  B=2+3+4=9  C=5+6=11  (B has 3 obs, C 2, A 1)
    try ds.appendRow(&.{ strV("A"), numV(1) });
    try ds.appendRow(&.{ strV("B"), numV(2) });
    try ds.appendRow(&.{ strV("B"), numV(3) });
    try ds.appendRow(&.{ strV("B"), numV(4) });
    try ds.appendRow(&.{ strV("C"), numV(5) });
    try ds.appendRow(&.{ strV("C"), numV(6) });
    try lib.put("d", ds);

    const cx = ProcCtx{ .arena = a, .lib = &lib, .diags = &diags };

    // F1 GROUP DESCENDING: levels descend C,B,A (was ascending A,B,C).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g v; define g / group descending; define v / analysis sum; run;", &diags);
        try runReport(cx, &out, toks);
        try t.expectEqualStrings("g     v\n\nC    11\nB     9\nA     1\n", out.items);
    }
    // F3 ORDER=FREQ: descending group frequency B(3),C(2),A(1).
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g v; define g / group order=freq; define v / analysis sum; run;", &diags);
        try runReport(cx, &out, toks);
        try t.expectEqualStrings("g     v\n\nB     9\nC    11\nA     1\n", out.items);
    }
    // F4 NOPRINT: v is summed for grouping but its column is omitted.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g v; define g / group; define v / analysis sum noprint; run;", &diags);
        try runReport(cx, &out, toks);
        try t.expectEqualStrings("g\n\nA\nB\nC\n", out.items);
    }
    // F2 unrecognized analysis STATISTIC (pctsum) → fail loud, never silent SUM.
    {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g v; define g / group; define v / analysis pctsum; run;", &diags);
        try runReport(cx, &out, toks);
        try t.expectEqualStrings("", out.items);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "unsupported DEFINE option/statistic") != null);
    }
    // F5 garbage DEFINE option → fail loud.
    {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g v; define g / group; define v / zonkzonk; run;", &diags);
        try runReport(cx, &out, toks);
        try t.expectEqualStrings("", out.items);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "unsupported DEFINE option/statistic") != null);
    }
    // F5 DEFINE of a var absent from the COLUMN list → fail loud.
    {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc report data=d nowd; column g v; define g / group; define nosuch / display; run;", &diags);
        try runReport(cx, &out, toks);
        try t.expectEqualStrings("", out.items);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "not in the COLUMN list") != null);
    }
}

test "proc report: BY statement fails loud, no merged report (BUG-procreportby)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "w");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(2), numV(20) });
    try lib.put("w", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc report data=w nowd; by g; column g x; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // BY-group reporting is unsupported → emit nothing (never one merged report),
    // and the captured fail-loud diagnostic names the BY statement.
    try t.expectEqualStrings("", out.items);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "PROC REPORT BY-group processing") != null);
}

test "proc report: ORDER sorts + blanks repeats, WIDTH=/FORMAT= honored (FEAT-procreport-1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ numV(2), strV("b"), numV(1) });
    try ds.appendRow(&.{ numV(1), strV("a"), numV(2) });
    try ds.appendRow(&.{ numV(3), strV("a"), numV(3) });
    try ds.appendRow(&.{ numV(4), strV("b"), numV(4) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column g v id; define g / order; define v / format=8.2 width=10; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // rows sorted by g (stable: a{2,3} then b{1,4}); g prints only on change;
    // v through 8.2 right-justified at WIDTH=10; id compact after it.
    const want =
        "g           v    id\n" ++
        "\n" ++
        "a        2.00     1\n" ++
        "         3.00     3\n" ++
        "b        1.00     2\n" ++
        "         4.00     4\n";
    try t.expectEqualStrings(want, out.items);
    // the input dataset is NOT reordered by the report
    try t.expectEqual(@as(f64, 2), lib.find("d").?.rows.items[0][0].num);
}

test "proc report: BREAK/RBREAK and proc options fail loud, nothing emitted (FEAT-procreport-1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .num);
    try ds.appendRow(&.{numV(1)});
    try lib.put("d", ds);

    inline for (.{
        "proc report data=d nowd; column a; break after a / summarize; run;",
        "proc report data=d nowd; column a; rbreak after / summarize; run;",
        "proc report data=d nowd headline; column a; run;",
        "proc report data=d nowd headskip nocenter; column a; run;",
    }) |src| {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqualStrings("", out.items); // fail loud, never a partial layout
        try t.expect(g_test_last_unsup.len > 0); // captured UNSUPPORTED message
    }
}

test "proc report: BREAK AFTER / SUMMARIZE subtotals + RBREAK grand total (FEAT-procreport-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    // a{10,20} b{30,40}: group sums a=30, b=70; break-after-g subtotals repeat the
    // group row (single group var), RBREAK grand total = 100.
    try ds.appendRow(&.{ strV("a"), numV(10) });
    try ds.appendRow(&.{ strV("b"), numV(30) });
    try ds.appendRow(&.{ strV("a"), numV(20) });
    try ds.appendRow(&.{ strV("b"), numV(40) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column g v; define g / group; define v / analysis sum; break after g / summarize; rbreak after / summarize; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "g      v\n" ++
        "\n" ++
        "a     30\n" ++
        "a     30\n" ++ // subtotal for a (break var shows its value)
        "b     70\n" ++
        "b     70\n" ++ // subtotal for b
        "     100\n"; // grand total, break var blank
    try t.expectEqualStrings(want, out.items);
}

test "proc report: unsupported break forms fail loud, nothing emitted (FEAT-procreport-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("a"), numV(10) });
    try lib.put("d", ds);

    inline for (.{
        "proc report data=d nowd; column g v; define g / group; define v / analysis sum; break sideways g / summarize; run;", // neither BEFORE nor AFTER
        "proc report data=d nowd; column g v; define g / group; define v / analysis sum; break after v / summarize; run;", // non-group break var
        "proc report data=d nowd; column g v; define g / group; define v / analysis sum; break after g / summarize skip; run;", // option beyond SUMMARIZE
        "proc report data=d nowd; column g v; define g / group; define v / analysis sum; break after g; run;", // no / SUMMARIZE
    }) |src| {
        var out: std.ArrayList(u8) = .empty;
        g_test_last_unsup = "";
        const toks = try lex.tokenize(a, src, &diags);
        try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqualStrings("", out.items); // fail loud, never a partial/wrong table
        try t.expect(g_test_last_unsup.len > 0); // captured UNSUPPORTED message
    }
}

test "proc report: COMPUTE basic computed column — arithmetic over displayed cols (FEAT-procreport-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(2), numV(20) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    g_test_last_unsup = "";
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column a b tot; define a / display; define b / display; define tot / computed; compute tot; tot = a + b; endcomp; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // tot = a + b per detail row; no fail-loud.
    const want =
        "  a     b    tot\n" ++
        "\n" ++
        "  1    10     11\n" ++
        "  2    20     22\n";
    try t.expectEqualStrings(want, out.items);
    try t.expectEqualStrings("", g_test_last_unsup);
}

test "proc report: COMPUTE with an unresolvable reference fails loud (FEAT-procreport-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try lib.put("d", ds);

    var out: std.ArrayList(u8) = .empty;
    g_test_last_unsup = "";
    // `zzz` is not a displayed numeric column → must fail loud, emit nothing,
    // never bind a silent missing (the worst clinical failure class).
    const toks = try lex.tokenize(a,
        "proc report data=d nowd; column a b tot; define tot / computed; compute tot; tot = a + zzz; endcomp; run;", &diags);
    try runReport(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    try t.expectEqualStrings("", out.items);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "not a displayed numeric column") != null);
}

test "proc transpose: var → wide with prefix (matches transpose.sas)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    const toks = try lex.tokenize(a, "proc transpose data=have out=want prefix=c; var x; run;", &diags);
    try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const w = lib.find("want").?;
    try t.expectEqual(@as(usize, 4), w.columns.items.len); // _NAME_, c1, c2, c3
    try t.expectEqualStrings("_NAME_", w.columns.items[0].name);
    try t.expectEqualStrings("c1", w.columns.items[1].name);
    try t.expectEqualStrings("c3", w.columns.items[3].name);
    try t.expectEqual(@as(usize, 1), w.rowCount());
    try t.expectEqualStrings("x", w.row(0)[0].str);
    try t.expectEqual(@as(f64, 10), w.row(0)[1].num);
    try t.expectEqual(@as(f64, 20), w.row(0)[2].num);
    try t.expectEqual(@as(f64, 30), w.row(0)[3].num);
}

test "proc transpose: OUT= drop=/keep= dataset options filter the output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    // keep= is an allow-list: only c1 and c3 survive (_NAME_ and c2 dropped)
    const toks = try lex.tokenize(a, "proc transpose data=have out=want(keep=c1 c3) prefix=c; var x; run;", &diags);
    try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const w = lib.find("want").?;
    try t.expectEqual(@as(usize, 2), w.columns.items.len);
    try t.expectEqualStrings("c1", w.columns.items[0].name);
    try t.expectEqualStrings("c3", w.columns.items[1].name);
    try t.expectEqual(@as(f64, 10), w.row(0)[0].num);
    try t.expectEqual(@as(f64, 30), w.row(0)[1].num);

    // drop= removes just the listed column (_NAME_ here)
    const toks2 = try lex.tokenize(a, "proc transpose data=have out=w2(drop=_name_) prefix=c; var x; run;", &diags);
    try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks2);
    const w2 = lib.find("w2").?;
    try t.expectEqual(@as(usize, 3), w2.columns.items.len); // c1, c2, c3 (no _NAME_)
    try t.expectEqualStrings("c1", w2.columns.items[0].name);
}

test "proc transpose: id names columns, name= renames _NAME_" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("subj", .char);
    _ = try ds.addColumn("score", .num);
    try ds.appendRow(&.{ strV("math"), numV(90) });
    try ds.appendRow(&.{ strV("read"), numV(80) });
    try lib.put("have", ds);

    const toks = try lex.tokenize(a, "proc transpose data=have out=w name=v; id subj; var score; run;", &diags);
    try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const w = lib.find("w").?;
    try t.expectEqualStrings("v", w.columns.items[0].name); // renamed _NAME_
    try t.expectEqualStrings("math", w.columns.items[1].name); // from id values
    try t.expectEqualStrings("read", w.columns.items[2].name);
    try t.expectEqualStrings("score", w.row(0)[0].str); // the transposed var name
    try t.expectEqual(@as(f64, 90), w.row(0)[1].num);
    try t.expectEqual(@as(f64, 80), w.row(0)[2].num);
}

test "BUG-transposedupid: duplicate ID value in a BY group fails loud (captured), unique still works" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "e");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("grp", .char);
    _ = try ds.addColumn("val", .num);
    // BY id=1 has grp "A" twice → SAS ERROR (would silently keep val=20, dropping 10).
    try ds.appendRow(&.{ numV(1), strV("A"), numV(10) });
    try ds.appendRow(&.{ numV(1), strV("A"), numV(20) });
    try ds.appendRow(&.{ numV(1), strV("B"), numV(30) });
    try lib.put("e", ds);

    var diags = diag.Diagnostics.init(a);
    const toks = try lex.tokenize(a, "proc transpose data=e out=o; by id; id grp; var val; run;", &diags);
    try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    try t.expect(std.mem.indexOf(u8, try diags.render(), "occurs twice in the same BY group") != null);
    try t.expect(lib.find("o") == null); // no silently-lossy dataset produced

    // A unique-ID transpose (drop the duplicate) still succeeds.
    var lib2 = Library.init(a);
    const ds2 = try a.create(Dataset);
    ds2.* = Dataset.init(a, "e");
    _ = try ds2.addColumn("id", .num);
    _ = try ds2.addColumn("grp", .char);
    _ = try ds2.addColumn("val", .num);
    try ds2.appendRow(&.{ numV(1), strV("A"), numV(10) });
    try ds2.appendRow(&.{ numV(1), strV("B"), numV(30) });
    try lib2.put("e", ds2);
    var diags2 = diag.Diagnostics.init(a);
    const toks2 = try lex.tokenize(a, "proc transpose data=e out=o; by id; id grp; var val; run;", &diags2);
    try runTranspose(.{ .arena = a, .lib = &lib2, .diags = &diags2 }, toks2);
    try t.expect(!diags2.hasErrors());
    const o = lib2.find("o").?;
    try t.expectEqual(@as(f64, 10), o.row(0)[o.indexOf("A").?].num);
    try t.expectEqual(@as(f64, 30), o.row(0)[o.indexOf("B").?].num);
}

test "BUG-transposebyorder: unsorted BY fails loud (captured), ascending BY still transposes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Unsorted BY (1,2,1) — SAS ERRORs "not sorted in ascending sequence" and stops;
    // consecutive-equal grouping alone would emit a duplicate subj=1 group at exit 0.
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("subj", .num);
    _ = try ds.addColumn("val", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(2), numV(20) });
    try ds.appendRow(&.{ numV(1), numV(30) });
    try lib.put("d", ds);
    var diags = diag.Diagnostics.init(a);
    const toks = try lex.tokenize(a, "proc transpose data=d out=w; by subj; var val; run;", &diags);
    try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
    try t.expect(std.mem.indexOf(u8, try diags.render(), "not sorted in ascending sequence") != null);
    try t.expect(lib.find("w") == null); // no silently-wrong reshape produced

    // Ascending BY (1,1,2) — normal transpose, unchanged.
    var lib2 = Library.init(a);
    const ds2 = try a.create(Dataset);
    ds2.* = Dataset.init(a, "d");
    _ = try ds2.addColumn("subj", .num);
    _ = try ds2.addColumn("val", .num);
    try ds2.appendRow(&.{ numV(1), numV(10) });
    try ds2.appendRow(&.{ numV(1), numV(30) });
    try ds2.appendRow(&.{ numV(2), numV(20) });
    try lib2.put("d", ds2);
    var diags2 = diag.Diagnostics.init(a);
    const toks2 = try lex.tokenize(a, "proc transpose data=d out=w; by subj; var val; run;", &diags2);
    try runTranspose(.{ .arena = a, .lib = &lib2, .diags = &diags2 }, toks2);
    try t.expect(!diags2.hasErrors());
    const w = lib2.find("w").?;
    try t.expectEqual(@as(usize, 2), w.rows.items.len); // subj=1 and subj=2, no duplicate
}

test "PROC TRANSPOSE fail-loud: mixed char/num VAR list + unknown VAR/BY/ID names (BUG-transposemixedvar/badname)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("n1", .num);
    _ = try ds.addColumn("n2", .num);
    _ = try ds.addColumn("c1", .char);
    _ = try ds.addColumn("c2", .char);
    try ds.appendRow(&.{ numV(1), numV(10), numV(20), strV("x"), strV("y") });
    try lib.put("have", ds);

    // Mixed char/num VAR list — SAS 9.4 ERRORs; was silently typed by the first
    // var, corrupting the char var to missing (doc-finder tick175).
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have out=o; var n1 c1; run;", &diags);
        try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "both character and numeric") != null);
        try t.expect(lib.find("o") == null); // no silently-corrupt dataset
    }
    // Unknown VAR / BY / ID names fail loud naming the variable (COPY already
    // did); a BY-typo silently collapsed all rows into one group.
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have out=o; var zz; run;", &diags);
        try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "VAR variable zz not found") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have out=o; by gg; var n1; run;", &diags);
        try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "BY variable gg not found") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have out=o; id zz; var n1; run;", &diags);
        try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "ID variable zz not found") != null);
    }
    // Single-type multi-VAR lists (all-num and all-char) still transpose.
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have out=o; var n1 n2; run;", &diags);
        try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
        try t.expect(!diags.hasErrors());
        const o = lib.find("o").?;
        try t.expectEqual(@as(usize, 2), o.rowCount());
        try t.expectEqualStrings("n2", o.row(1)[0].str);
        try t.expectEqual(@as(f64, 20), o.row(1)[1].num);
    }
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have out=oc; var c1 c2; run;", &diags);
        try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);
        try t.expect(!diags.hasErrors());
        const oc = lib.find("oc").?;
        try t.expectEqualStrings("c2", oc.row(1)[0].str);
        try t.expectEqualStrings("y", oc.row(1)[1].str);
    }
}

test "proc transpose: BY groups, ragged group padded with missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(1), numV(20) });
    try ds.appendRow(&.{ numV(2), numV(30) }); // group 2 is shorter
    try lib.put("have", ds);

    const toks = try lex.tokenize(a, "proc transpose data=have out=w prefix=v; by g; var x; run;", &diags);
    try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const w = lib.find("w").?;
    // columns: g, _NAME_, v1, v2
    try t.expectEqualStrings("g", w.columns.items[0].name);
    try t.expectEqual(@as(usize, 2), w.rowCount());
    try t.expectEqual(@as(f64, 1), w.row(0)[0].num); // g=1
    try t.expectEqual(@as(f64, 10), w.row(0)[2].num); // v1
    try t.expectEqual(@as(f64, 20), w.row(0)[3].num); // v2
    try t.expectEqual(@as(f64, 2), w.row(1)[0].num); // g=2
    try t.expectEqual(@as(f64, 30), w.row(1)[2].num); // v1
    try t.expect(w.row(1)[3].isMissing()); // v2 padded missing
}

test "BUG-transposecopy: COPY var carried through from first obs of each BY group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("keepme", .num);
    _ = try ds.addColumn("site", .char);
    try ds.appendRow(&.{ numV(1), numV(10), numV(999), strV("A") });
    try ds.appendRow(&.{ numV(1), numV(20), numV(888), strV("A") }); // later-obs COPY values ignored
    try ds.appendRow(&.{ numV(2), numV(30), numV(777), strV("B") });
    try lib.put("have", ds);

    const toks = try lex.tokenize(a, "proc transpose data=have out=w prefix=v; by g; var x; copy keepme site; run;", &diags);
    try runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const w = lib.find("w").?;
    // columns: g, _NAME_, v1, v2, keepme, site (COPY after the transposed values)
    try t.expectEqual(@as(usize, 6), w.columns.items.len);
    try t.expectEqualStrings("keepme", w.columns.items[4].name);
    try t.expectEqualStrings("site", w.columns.items[5].name);
    try t.expectEqual(@as(f64, 999), w.row(0)[4].num); // first obs of g=1
    try t.expectEqualStrings("A", w.row(0)[5].str);
    try t.expectEqual(@as(f64, 777), w.row(1)[4].num); // first obs of g=2
    try t.expectEqualStrings("B", w.row(1)[5].str);

    // Unknown COPY variable fails loud, never silently dropped.
    var diags2 = diag.Diagnostics.init(a);
    const toks2 = try lex.tokenize(a, "proc transpose data=have out=w2; var x; copy nosuch; run;", &diags2);
    try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &diags2 }, toks2));
    try t.expect(lib.find("w2") == null);
}

test "proc sort nodupkey keeps the first row of each BY key (BUG-sortdup)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("age", .num);
    try ds.appendRow(&.{ strV("Bob"), numV(25) });
    try ds.appendRow(&.{ strV("Alice"), numV(30) });
    try ds.appendRow(&.{ strV("Bob"), numV(25) });
    try ds.appendRow(&.{ strV("Alice"), numV(99) });
    try lib.put("have", ds);

    const toks = try lex.tokenize(a, "proc sort data=have out=u nodupkey; by name; run;", &diags);
    try runSort(.{ .arena = a, .lib = &lib, .diags = &diags }, toks);

    const u = lib.find("u").?;
    try t.expectEqual(@as(usize, 2), u.rowCount()); // one per name, not all 4
    try t.expectEqualStrings("Alice", u.row(0)[0].str);
    try t.expectEqual(@as(f64, 30), u.row(0)[1].num); // first Alice (30), not 99 — stable
    try t.expectEqualStrings("Bob", u.row(1)[0].str);
    // source untouched by OUT=
    try t.expectEqual(@as(usize, 4), ds.rowCount());
}

test "proc freq one-way with /nocum (matches the fixture)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("color", .char);
    for ([_][]const u8{ "red", "red", "red", "blue" }) |v| try ds.appendRow(&.{strV(v)});
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc freq data=have; tables color / nocum; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "                      The FREQ Procedure\n" ++
        "\n" ++
        "              color    Frequency     Percent\n" ++
        "              ---------------------------------\n" ++
        "              blue           1       25.00\n" ++
        "              red            3       75.00\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc freq one-way table (matches the fixture)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("grp", .char);
    for ([_][]const u8{ "A", "A", "B", "B", "B" }) |v| try ds.appendRow(&.{strV(v)});
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc freq data=have; tables grp; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    const want =
        "                                      The FREQ Procedure\n" ++
        "\n" ++
        "                                          Cumulative    Cumulative\n" ++
        "              grp    Frequency     Percent     Frequency      Percent\n" ++
        "              -------------------------------------------------------\n" ++
        "              A              2       40.00              2        40.00\n" ++
        "              B              3       60.00              5       100.00\n";
    try t.expectEqualStrings(want, out.items);
}

test "proc freq two-way table (matches the fixture)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("h", .char);
    try ds.appendRow(&.{ strV("A"), strV("X") });
    try ds.appendRow(&.{ strV("A"), strV("Y") });
    try ds.appendRow(&.{ strV("B"), strV("X") });
    try ds.appendRow(&.{ strV("B"), strV("X") });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc freq data=have; tables g*h; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    const o = out.items;
    const has = struct {
        fn f(hay: []const u8, n: []const u8) bool {
            return std.mem.indexOf(u8, hay, n) != null;
        }
    }.f;
    // SAS-default 4-stat cell + legend box (FREQ-crosstabpct). Exact full layout is
    // pinned by tests/corpus/proc_freq_2way.txt; here assert the hand-verified stats.
    // grand=4, rowTot A=B=2, colTot X=3 Y=1. A,X: freq 1, cell%25, row%50, col%33.33.
    try t.expect(has(o, "Frequency|\n") and has(o, "Percent  |\n") and has(o, "Row Pct  |\n"));
    try t.expect(has(o, "Col Pct  |X       |Y       |  Total"));
    try t.expect(has(o, "A        |      1 |      1 |      2")); // Frequency + row total
    try t.expect(has(o, "|  25.00 |  25.00 |  50.00")); // Percent (of grand) + row total %
    try t.expect(has(o, "|  50.00 |  50.00 |")); // Row Pct, blank in Total column
    try t.expect(has(o, "|  33.33 | 100.00 |")); // Col Pct (1/3, 1/1)
    try t.expect(has(o, "|  66.67 |   0.00 |")); // B row Col Pct (2/3, 0/1)
    try t.expect(has(o, "Total           3        1        4")); // marginal freq
    try t.expect(has(o, "75.00    25.00   100.00")); // marginal Percent
}

test "FREQ-hardening: unsupported TABLES statistics (chisq/agree/exact/expected) fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("h", .char);
    for ([_][2][]const u8{ .{ "A", "X" }, .{ "A", "Y" }, .{ "B", "X" }, .{ "B", "Y" } }) |r|
        try ds.appendRow(&.{ strV(r[0]), strV(r[1]) });
    try lib.put("d", ds);

    // Each stat option must ParseError naming itself, never a table without the stat.
    for ([_][]const u8{ "chisq", "agree", "exact", "measures", "cmh", "fisher", "relrisk", "expected", "cellchi2", "trend" }) |opt| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d; tables g*h / {s}; run;", .{opt});
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "not yet supported") != null);
        try t.expectEqual(@as(usize, 0), out.items.len); // no partial table emitted
    }

    // Baseline: a plain two-way table + tolerated display options still render.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g*h / nocum; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Table of g by h") != null);
    }
}

test "NOTE-freqdanglingcross: a dangling `*` in TABLES fails loud; well-formed one-/two-way unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("h", .char);
    for ([_][2][]const u8{ .{ "A", "X" }, .{ "B", "Y" } }) |r|
        try ds.appendRow(&.{ strV(r[0]), strV(r[1]) });
    try lib.put("d", ds);

    // Dangling `*`: at end of statement or before `/` — ParseError, no table.
    for ([_][]const u8{ "tables g*;", "tables g* / norow;" }) |stmt| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d; {s} run;", .{stmt});
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "expected a variable after '*'") != null);
        try t.expectEqual(@as(usize, 0), out.items.len); // no silent one-way on g
    }

    // Controls: a valid crosstab and a plain one-way still render.
    for ([_][]const u8{ "tables g*h;", "tables g;" }) |stmt| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d; {s} run;", .{stmt});
        const toks = try lex.tokenize(a, src, &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(out.items.len > 0);
    }
}

test "FREQ-crosstabpct: two-way / missing keeps the missing level; default drops it + Frequency Missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("h", .char);
    try ds.appendRow(&.{ strV("A"), strV("X") });
    try ds.appendRow(&.{ strV("A"), strV(" ") }); // h missing → dropped by default
    try ds.appendRow(&.{ strV("B"), strV("X") });
    try lib.put("d", ds);

    // default: the blank h obs is excluded → grand=2 over the single X column, and
    // SAS reports the excluded obs as `Frequency Missing = 1`.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g*h; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Frequency Missing = 1") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Total           2") != null); // grand = 2
    }
    // `/ missing`: the blank level is a category → grand=3, no Frequency Missing line.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g*h / missing; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Frequency Missing") == null);
        try t.expect(std.mem.indexOf(u8, out.items, "Total           1        2        3") != null); // grand = 3
    }
}

test "proc freq two-way WEIGHT sums the weight column (BUG-freqweight2way); 3-way strata + OUT= + NOPRINT (GAP-freqnway)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("h", .char);
    _ = try ds.addColumn("w", .num);
    try ds.appendRow(&.{ strV("A"), strV("X"), numV(2) });
    try ds.appendRow(&.{ strV("A"), strV("Y"), numV(1) });
    try ds.appendRow(&.{ strV("B"), strV("X"), numV(1) });
    try ds.appendRow(&.{ strV("B"), strV("Y"), numV(2) });
    try lib.put("have", ds);

    // weighted crosstab: cells 2/1/1/2, margins 3s, grand 6 (was 1/1/1/1, 4).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; weight w; tables g*h; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "A        |      2 |      1 |      3") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Total           3        3        6") != null);
    }
    // 3-way TABLES → one h×w crosstab per g level, each with its stratum header
    // (was a fail-loud ParseError until GAP-freqnway landed).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; tables g*h*w; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Table 1 of h by w") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Controlling for g=A") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Table 2 of h by w") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Controlling for g=B") != null);
        // stratum g=A: (X,w=2) and (Y,w=1) — w columns ascend 1,2 → X row is 0,1
        try t.expect(std.mem.indexOf(u8, out.items, "X        |      0 |      1 |      1") != null);
    }
    // NOPRINT + OUT= → no listing; dataset has the TABLES vars then COUNT, PERCENT,
    // one row per observed combo, percent of the stratum's two-way total.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have noprint; tables g*h / out=f; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expectEqual(@as(usize, 0), out.items.len);
        const f = lib.find("f").?;
        try t.expectEqual(@as(usize, 4), f.columns.items.len);
        try t.expect(eqi(f.columns.items[0].name, "g"));
        try t.expect(eqi(f.columns.items[1].name, "h"));
        try t.expect(eqi(f.columns.items[2].name, "COUNT"));
        try t.expect(eqi(f.columns.items[3].name, "PERCENT"));
        try t.expectEqual(@as(usize, 4), f.rows.items.len);
        // unweighted: each g×h combo occurs once → COUNT 1, PERCENT 25 (of 4 obs)
        try t.expectEqual(@as(f64, 1), f.rows.items[0][2].num);
        try t.expectEqual(@as(f64, 25), f.rows.items[0][3].num);
    }
}

test "proc freq two-way table with >=5 column levels does not overflow the line buffer (BUG-freqcrash)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("r", .char);
    _ = try ds.addColumn("c", .char);
    // 6 column levels (p,q,r,s,t,u): the old fixed 60-char buffer panicked at
    // the rule underline once nc >= 5, and clipped the Total column from nc >= 4.
    for ([_][]const u8{ "p", "q", "r", "s", "t" }) |cv| try ds.appendRow(&.{ strV("a"), strV(cv) });
    try ds.appendRow(&.{ strV("b"), strV("p") });
    try ds.appendRow(&.{ strV("b"), strV("u") });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc freq data=have; tables r*c; run;", &diags);
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
    const o = out.items;
    const has = struct {
        fn f(hay: []const u8, n: []const u8) bool {
            return std.mem.indexOf(u8, hay, n) != null;
        }
    }.f;
    // The overflow guard: the widest writes (Col Pct legend header + the marginal
    // Total row, right edge 31+9*nc) must render in full, not panic or clip.
    // Full 4-stat layout pinned by tests/corpus/proc_freq_2way_wide.txt.
    try t.expect(has(o, "Col Pct  |p       |q       |r       |s       |t       |u       |  Total"));
    try t.expect(has(o, "a        |      1 |      1 |      1 |      1 |      1 |      0 |      5"));
    try t.expect(has(o, "Total           2        1        1        1        1        1        7"));
    try t.expect(has(o, "28.57    14.29    14.29    14.29    14.29    14.29   100.00")); // marginal Percent
}

test "BUG-freqweightorder: zero-weight levels drop by default, /zeros re-includes; WEIGHT + ORDER= options validate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("cat", .char);
    _ = try ds.addColumn("w", .num);
    try ds.appendRow(&.{ strV("B"), numV(2) });
    try ds.appendRow(&.{ strV("A"), numV(3) });
    try ds.appendRow(&.{ strV("C"), numV(0) }); // C exists only at weight 0
    try lib.put("d", ds);

    // F2a: default — the zero-weight-only level C forms NO row (was a spurious
    // `Frequency 0` row); A/B counts and percents unchanged.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables cat; weight w; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "C              0") == null);
        try t.expect(std.mem.indexOf(u8, out.items, "A              3       60.00") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "B              2       40.00") != null);
    }
    // F2b: `/ zeros` re-includes C with Frequency 0 (counted in no percent base).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables cat; weight w / zeros; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "C              0        0.00") != null);
    }
    // F2c: an unknown WEIGHT `/` option fails loud (was silently swallowed).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables cat; weight w / bogus; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "WEIGHT option bogus") != null);
    }
    // F3: an invalid ORDER= value fails loud (was silently INTERNAL).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d order=badvalue; tables cat; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "ORDER=badvalue is not valid") != null);
    }
    // the valid ORDER= values all still parse and render
    for ([_][]const u8{ "freq", "data", "internal", "formatted" }) |v| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d order={s}; tables cat; weight w; run;", .{v});
        const toks = try lex.tokenize(a, src, &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
    }
}

test "GAP-freqignoreopt: unknown TABLES options fail loud (captured); OUTCUM adds CUM_FREQ/CUM_PCT to a one-way OUT=" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    for ([_]f64{ 1, 2, 2, 3 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("d", ds);

    // A typo'd option must ParseError naming itself — never silently accepted.
    for ([_][]const u8{ "bogusoption123", "outcumm" }) |opt| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d; tables g / {s}; run;", .{opt});
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), opt) != null);
    }

    // OUTCUM: CUM_FREQ/CUM_PCT running totals in the one-way OUT= dataset.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d noprint; tables g / out=fo outcum; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const fo = lib.find("fo").?;
        try t.expectEqualStrings("CUM_FREQ", fo.columns.items[3].name);
        try t.expectEqualStrings("CUM_PCT", fo.columns.items[4].name);
        // g = 1,2,3 → COUNT 1,2,1 → CUM_FREQ 1,3,4; CUM_PCT 25,75,100.
        try t.expectEqual(@as(f64, 1), fo.rows.items[0][3].num);
        try t.expectEqual(@as(f64, 4), fo.rows.items[2][3].num);
        try t.expectEqual(@as(f64, 100), fo.rows.items[2][4].num);
    }
}

test "NOTE-freqlistfmt: n-way / list fails loud (no silent grid substitute); one-way / list is a no-op; OUT= unaffected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("h", .num);
    for ([_]f64{ 1, 2, 2, 3 }, [_]f64{ 7, 7, 8, 8 }) |v, w| try ds.appendRow(&.{ numV(v), numV(w) });
    try lib.put("d", ds);

    // Two-way and three-way `/ list`: the listing would be the wrong layout —
    // ParseError naming the option, never the grid at exit 0.
    for ([_][]const u8{ "tables g*h / list;", "tables g*h*g / list;" }) |stmt| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d; {s} run;", .{stmt});
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "list") != null);
    }

    // One-way `/ list` is a genuine no-op: the one-way table IS the list layout.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g / list; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, "Cumulative") != null);
    }

    // `/ list out=o noprint`: no listing is rendered, so LIST is vacuous and
    // the OUT= dataset (which LIST never affects) is still produced.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g*h / list out=lo noprint; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("lo") != null);
    }
}

test "GAP-ebnfrcwrongclass: n-way TABLES / LIST is a NAMED rc-2 gap (was rc 1); one-way / list and / freq keep their classes" {
    // LIST is a DOCUMENTED TABLES option (Table 3.9, Statistical Procedures
    // printed p.105, === pdf 108 ===) that real SAS runs clean, so refusing
    // the n-way list layout is OUR gap: markGap → rc 2 (D-009/D-009b(i)),
    // not rc 1 "your SAS is broken". The message already NAMES list.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("h", .num);
    for ([_]f64{ 1, 2, 2, 3 }, [_]f64{ 7, 7, 8, 8 }) |v, w| try ds.appendRow(&.{ numV(v), numV(w) });
    try lib.put("d", ds);

    // n-way / list: ParseError, message names list, and the gap flag is set.
    {
        diag.resetGap();
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g*h / list; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "TABLES option list (n-way list layout) is not yet supported") != null);
        try t.expect(diag.gapHit());
    }
    // one-way / list: documented no-op — runs clean, no gap.
    {
        diag.resetGap();
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g / list; run;", &diags);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(!diag.gapHit());
    }
    // / freq is NOT in Table 3.9's closed TABLES option set (printed
    // pp.104-106) — a typo in real-SAS terms, so the catch-all stays rc 1
    // (no gap mark; the tick431 row's premise was stale).
    {
        diag.resetGap();
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=d; tables g / freq; run;", &diags);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "TABLES option freq is not supported") != null);
        try t.expect(!diag.gapHit());
    }
}

test "GAP-tabformat: *f= honored; row-dimension and distinct per-element *f= fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ strV("A"), numV(1) });
    try ds.appendRow(&.{ strV("A"), numV(2) });
    try ds.appendRow(&.{ strV("B"), numV(10) });
    try lib.put("d", ds);

    // cell *f=6.2 formats the data cells (mean 1.5 → 1.50); an analysis var
    // literally named `f` still parses as the var.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var x; table g, x*mean*f=6.2; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "1.50") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "10.00") != null);
    }
    // row-dimension *f= (would format row labels) — fail loud, not a bogus row var.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var x; table g*f=8.1, x*mean; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "row-dimension") != null);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    // two DISTINCT *f= specs would be per-element formats we don't model — fail loud.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g; var x; table g, x*sum*f=6.2 x*mean*f=8.1; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "per-element") != null);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "NOTE-tabulatelistnoop: TABULATE `/ list` fails loud naming the option — never a silently wrong-shaped table (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("A"), numV(1) });
    try lib.put("d", ds);

    // Both placements of `list` name themselves and render NOTHING (exit-2 gap):
    // the TABLE-statement `/ list` and the PROC-level `list`. The ticket's silent
    // no-op predates the GAP-tabprocopt / GAP-tabulateopts blanket option
    // fail-louds (probe: both already UNSUPPORTED) — this pins them. (FREQ's
    // 1-way no-op carve-out has no TABULATE analog: 1-dimensional tables are
    // themselves unsupported here, so no `/ list` form is vacuously safe.)
    for ([_][]const u8{
        "proc tabulate data=d; class g; var v; table g, v*sum / list; run;",
        "proc tabulate data=d list; class g; var v; table g, v*sum; run;",
    }) |src| {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "list") != null);
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "BUG-tabnestcol: a 2nd class variable in the column crossing fails loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("a", .char);
    _ = try ds.addColumn("b", .char);
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("A1"), strV("B1"), strV("C1"), numV(1) });
    try ds.appendRow(&.{ strV("A1"), strV("B1"), strV("C2"), numV(2) });
    try lib.put("d", ds);

    // `table a, b*c*v*sum`: the 2nd column class var (c) used to be silently
    // DROPPED — cells merged over c, wrong sums, no diagnostic. Now: loud ERROR,
    // nothing rendered (mirrors the row-dimension guard, BUG-tabulaterowdim).
    {
        diag.resetGap(); // global flag — don't credit an earlier test's gap
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class a b c; var v; table a, b*c*v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "nested column dimension") != null);
        try t.expect(diag.gapHit()); // marks the run exit-2, like every UNSUPPORTED
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    // a single column class var still renders — the guard only fires on the 2nd.
    {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class a b; var v; table a, b*v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqualStrings("", g_test_last_unsup);
        try t.expect(out.items.len > 0);
    }
}

test "GAP-tabulateforms #7: per-element stat lists render per block; crossed multi-var / cross-concat / page dim fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("r", .char);
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    try ds.appendRow(&.{ strV("x"), strV("p"), numV(1), numV(10) });
    try ds.appendRow(&.{ strV("x"), strV("q"), numV(2), numV(20) });
    try ds.appendRow(&.{ strV("y"), strV("p"), numV(3), numV(30) });
    try lib.put("d", ds);

    // the fixed rendering: `a*sum b*mean` = a-Sum then b-Mean (p.2548's
    // concatenation), each element carrying ONLY its own statistic — the old
    // union rendered b×(Sum,Mean): an extra column and a*sum silently dropped.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class r; var a b; table r, a*sum b*mean; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "|  a  |  b   |") != null); // one block per var
        try t.expect(std.mem.indexOf(u8, out.items, "| Sum | Mean |") != null); // one stat per block
        try t.expect(std.mem.indexOf(u8, out.items, "|   3 |   15 |") != null); // x: a-sum 3, b-mean 15
        try t.expect(std.mem.indexOf(u8, out.items, "|   3 |   30 |") != null); // y: a-sum 3, b-mean 30
        try t.expect(std.mem.indexOf(u8, out.items, "Sum | Mean | Sum") == null); // the union's tell: a 3rd stat column
    }
    // loud arms (captured): valid-SAS forms the renderer doesn't draw stay
    // rc-2 gaps, never a silently wrong table.
    const loud = [_]struct { src: []const u8, msg: []const u8 }{
        .{ .src = "proc tabulate data=d; class r; var a b; table r, a*b*sum; run;", .msg = "multiple analysis variables in one crossing" },
        .{ .src = "proc tabulate data=d; class r c; var a b; table r, c*a*sum b*mean; run;", .msg = "concatenated column blocks in a class-crossed table" },
        .{ .src = "proc tabulate data=d; class r c; var a; table c, r, a*sum; run;", .msg = "page dimensions" },
    };
    for (loud) |cs| {
        diag.resetGap();
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, cs.src, &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, cs.msg) != null);
        try t.expect(diag.gapHit()); // marks the run exit-2, like every UNSUPPORTED
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    // a var-less non-N/PCTN statistic is MALFORMED SAS (p.2548: "Statistic
    // keywords other than N must be associated with an analysis variable") —
    // a user error (rc 1 ParseError, D-009), not a gap.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class r; var a; table r, mean; run;", &diags);
        try t.expectError(error.ParseError, runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "GAP-tabulateforms #8: an ALL-only row dimension renders ONE grand-total row" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("c", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("x"), strV("p"), numV(1) });
    try ds.appendRow(&.{ strV("x"), strV("q"), numV(2) });
    try ds.appendRow(&.{ strV("y"), strV("p"), numV(3) });
    try lib.put("d", ds);

    // `table all, v*sum`: one grand-total row (p.2547: two dimensions → rows,
    // columns; ALL is a dimension element) — used to die "no TABLE row variable".
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g c; var v; table all, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "|All  |   6 |") != null);
        var alls: usize = 0; // exactly ONE All row — not a level row plus a total row
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "\n|All")) |hit| : (pos = hit + 4) alls += 1;
        try t.expectEqual(@as(usize, 1), alls);
    }
    // the crossed form: the single level group IS the All row — appending the
    // usual grand-total row on top would double it.
    {
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d; class g c; var v; table all, c*v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "|All  |   4 |   2 |") != null);
        var alls: usize = 0;
        var pos: usize = 0;
        while (std.mem.indexOfPos(u8, out.items, pos, "\n|All")) |hit| : (pos = hit + 4) alls += 1;
        try t.expectEqual(@as(usize, 1), alls);
    }
}

test "NOTE-tabulateorderempty: value-less order= fails loud (captured); order=freq still works" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{ strV("A"), numV(1) });
    try ds.appendRow(&.{ strV("B"), numV(2) });
    try lib.put("d", ds);

    // `order=;` (no value) used to fall to the catch-all and be silently
    // ignored — now a loud ERROR, nothing rendered.
    {
        diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d order=; class g; var v; table g, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqualStrings("PROC TABULATE: ORDER= requires a value (DATA/FREQ/FORMATTED/INTERNAL)", g_test_last_unsup);
        try t.expect(diag.gapHit()); // marks the run exit-2, like every UNSUPPORTED
        try t.expectEqual(@as(usize, 0), out.items.len);
    }
    // a valid order=freq is untouched by the guard.
    {
        g_test_last_unsup = "";
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc tabulate data=d order=freq; class g; var v; table g, v*sum; run;", &diags);
        try runTabulate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expectEqualStrings("", g_test_last_unsup);
        try t.expect(out.items.len > 0);
    }
}

test "proc means over BY groups emits a block per group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    // sorted by g: group 1 = {10,20}, group 2 = {100}
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(1), numV(20) });
    try ds.appendRow(&.{ numV(2), numV(100) });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc means data=have; var x; by g; run;", &diags);
    try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // two BY lines, and each group's N in its value row
    try t.expect(std.mem.indexOf(u8, out.items, "g=1") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "g=2") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "15.0000000") != null); // mean of group 1
    try t.expect(std.mem.indexOf(u8, out.items, "100.0000000") != null); // group 2 single value
}

test "proc means CLASS emits per-group stats over unsorted input (BUG-meansclass)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    // UNSORTED by g — CLASS must still group A={10,20,30}, B={100,200}
    try ds.appendRow(&.{ strV("A"), numV(10) });
    try ds.appendRow(&.{ strV("B"), numV(100) });
    try ds.appendRow(&.{ strV("A"), numV(20) });
    try ds.appendRow(&.{ strV("B"), numV(200) });
    try ds.appendRow(&.{ strV("A"), numV(30) });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc means data=have; class g; var x; run;", &diags);
    try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    // one combined table (class var a column, a row per level), NOT per-group
    // blocks — BUG-meansclass-layout
    try t.expect(std.mem.indexOf(u8, out.items, "Analysis Variable : x") != null);
    try t.expect(std.mem.indexOf(u8, out.items, "g=A") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "20.0000000") != null); // A mean (grouped across gaps)
    try t.expect(std.mem.indexOf(u8, out.items, "150.0000000") != null); // B mean
}

test "proc means OUTPUT OUT= builds the summary dataset; NOPRINT suppresses the listing (BUG-meansoutput)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ strV("A"), numV(10) });
    try ds.appendRow(&.{ strV("B"), numV(100) });
    try ds.appendRow(&.{ strV("A"), numV(20) });
    try ds.appendRow(&.{ strV("B"), numV(200) });
    try lib.put("have", ds);

    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc means data=have noprint; class g; var x; output out=o mean=avg sum=tot n=cnt; run;", &diags);
    try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);

    try t.expectEqual(@as(usize, 0), out.items.len); // NOPRINT → no listing

    const o = lib.find("o").?;
    // _TYPE_=0 grand-total row + one _TYPE_=1 row per CLASS level (BUG-meansouttype)
    try t.expectEqual(@as(usize, 3), o.rowCount());
    const gi = o.indexOf("g").?;
    const tp = o.indexOf("_TYPE_").?;
    const fr = o.indexOf("_FREQ_").?;
    const ai = o.indexOf("avg").?;
    const ti = o.indexOf("tot").?;
    const ci = o.indexOf("cnt").?;
    // row 0: overall — CLASS var missing (blank char), _TYPE_=0, _FREQ_=4, over all 4 obs
    try t.expectEqualStrings("", o.row(0)[gi].str);
    try t.expectEqual(@as(f64, 0), o.row(0)[tp].num);
    try t.expectEqual(@as(f64, 4), o.row(0)[fr].num);
    try t.expectEqual(@as(f64, 82.5), o.row(0)[ai].num); // (10+100+20+200)/4
    try t.expectEqual(@as(f64, 330), o.row(0)[ti].num);
    // rows 1,2: per-class, _TYPE_=1
    try t.expectEqualStrings("A", o.row(1)[gi].str);
    try t.expectEqual(@as(f64, 1), o.row(1)[tp].num);
    try t.expectEqual(@as(f64, 2), o.row(1)[fr].num);
    try t.expectEqual(@as(f64, 15), o.row(1)[ai].num); // (10+20)/2
    try t.expectEqual(@as(f64, 30), o.row(1)[ti].num);
    try t.expectEqual(@as(f64, 2), o.row(1)[ci].num);
    try t.expectEqualStrings("B", o.row(2)[gi].str);
    try t.expectEqual(@as(f64, 150), o.row(2)[ai].num); // (100+200)/2
    try t.expectEqual(@as(f64, 300), o.row(2)[ti].num);
}

test "BUG-weightvarcheck/univplotnoop/univvarnosuch: WEIGHT/VAR/plot validation fail loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("w", .num);
    try ds.appendRow(&.{ numV(10), numV(1) });
    try ds.appendRow(&.{ numV(20), numV(3) });
    try lib.put("d", ds);

    const Case = struct { src: []const u8, needle: []const u8, run: *const fn (ProcCtx, *std.ArrayList(u8), []const Token) diag.Error!void };
    // BUG-weightvarcheck: a typo'd WEIGHT var must error (not silently unweighted),
    // at all three sites. BUG-univplotnoop: plot statements error. BUG-univvarnosuch:
    // an unknown VAR errors naming it.
    const bad = [_]Case{
        .{ .src = "proc means data=d; weight nosuchw; var x; run;", .needle = "nosuchw", .run = runMeans },
        .{ .src = "proc freq data=d; tables x; weight nosuchw; run;", .needle = "nosuchw", .run = runFreq },
        .{ .src = "proc univariate data=d; weight nosuchw; var x; run;", .needle = "nosuchw", .run = runUnivariate },
        .{ .src = "proc univariate data=d; var x; histogram x / normal; run;", .needle = "histogram", .run = runUnivariate },
        .{ .src = "proc univariate data=d; var x nosuchvar; run;", .needle = "nosuchvar", .run = runUnivariate },
    };
    for (bad) |c| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, c.src, &diags);
        try t.expectError(error.ParseError, c.run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), c.needle) != null);
    }

    // Baselines: a VALID weight var and a VALID VAR list still work, no error.
    const good = [_]Case{
        .{ .src = "proc means data=d mean; weight w; var x; run;", .needle = "Mean", .run = runMeans },
        .{ .src = "proc univariate data=d; weight w; var x; run;", .needle = "UNIVARIATE", .run = runUnivariate },
        .{ .src = "proc univariate data=d; var x w; run;", .needle = "UNIVARIATE", .run = runUnivariate },
    };
    for (good) |c| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try c.run(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks: {
            break :toks try lex.tokenize(a, c.src, &diags);
        });
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, out.items, c.needle) != null);
    }
}

test "BUG-univmu0freq: MU0= + FREQ + fail-loud unrecognized option/statement (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("f", .num);
    try ds.appendRow(&.{ numV(1), numV(2) });
    try ds.appendRow(&.{ numV(2), numV(3) });
    try ds.appendRow(&.{ numV(3), numV(1) }); // Σf = 6, Σf·x = 11
    try lib.put("d", ds);

    // F1: MU0= is used as the reference — header prints Mu0=5 (not 0).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d mu0=5; var x; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Mu0=5") != null);
        try t.expect(std.mem.indexOf(u8, out.items, "Mu0=0") == null);
    }
    // default (no MU0=) still Mu0=0.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; var x; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(std.mem.indexOf(u8, out.items, "Mu0=0") != null);
    }
    // F2: FREQ f — N = Σf = 6, Mean = Σf·x/Σf = 11/6, via OUTPUT (exact).
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d noprint; freq f; var x; output out=fo n=nn mean=mm; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        const o = lib.find("fo").?;
        try t.expectEqual(@as(f64, 6), o.row(0)[o.indexOf("nn").?].num);
        try t.expectApproxEqAbs(@as(f64, 11.0 / 6.0), o.row(0)[o.indexOf("mm").?].num, 1e-9);
    }
    // ROOT-CAUSE: an unrecognized option / unmodeled statement now fails loud.
    const Case = struct { src: []const u8, needle: []const u8 };
    const bad = [_]Case{
        .{ .src = "proc univariate data=d normal; var x; run;", .needle = "normal" },
        .{ .src = "proc univariate data=d cibasic; var x; run;", .needle = "cibasic" },
        .{ .src = "proc univariate data=d; inset x; var x; run;", .needle = "inset" },
    };
    for (bad) |c| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, c.src, &diags);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), c.needle) != null);
    }
}

test "BUG-univignoresby: BY splits the listing per group; unsorted BY fails loud (captured)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Sorted BY (1,1,2): TWO block sets, each headed by its BY value, with the
    // per-group Mean (was: ONE pooled block, Mean 2, at exit 0 — silent-wrong).
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ numV(1), numV(1) });
    try ds.appendRow(&.{ numV(1), numV(3) });
    try ds.appendRow(&.{ numV(2), numV(10) });
    try lib.put("d", ds);
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; by g; var x; run;", &diags);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        const o = out.items;
        try t.expect(std.mem.indexOf(u8, o, "g=1") != null);
        try t.expect(std.mem.indexOf(u8, o, "g=2") != null);
        // per-group means 2 and 10, never the pooled 14/3
        try t.expect(std.mem.indexOf(u8, o, "4.6666667") == null);
    }
    // Unsorted BY (1,2,1) — SAS ERRORs "not sorted in ascending sequence" (the
    // shared MEANS/TRANSPOSE guard's exact wording) instead of printing a
    // duplicate g=1 group at exit 0.
    {
        var lib2 = Library.init(a);
        const ds2 = try a.create(Dataset);
        ds2.* = Dataset.init(a, "d");
        _ = try ds2.addColumn("g", .num);
        _ = try ds2.addColumn("x", .num);
        try ds2.appendRow(&.{ numV(1), numV(1) });
        try ds2.appendRow(&.{ numV(2), numV(10) });
        try ds2.appendRow(&.{ numV(1), numV(3) });
        try lib2.put("d", ds2);
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=d; by g; var x; output out=o mean=m; run;", &diags);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib2, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "not sorted in ascending sequence") != null);
        try t.expect(lib2.find("o") == null); // no silently-wrong OUT= either
    }
}

test "PROC IMPORT header→name follows VALIDVARNAME=V7 (GH#62 ISS-varnamev7)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 1) each invalid char → one `_`, runs NOT collapsed, trailing `_` KEPT.
    try t.expectEqualStrings("Foo_Bar__Baz_", io.validName(a, "Foo Bar (Baz)", 0));
    // 2) leading digit → prepend `_`.
    try t.expectEqualStrings("_2nd_Col", io.validName(a, "2nd Col", 0));
    // 2b) empty / all-invalid trimming → VAR{col+1}.
    try t.expectEqualStrings("VAR3", io.validName(a, "   ", 2));
    // 3) truncate to 32 bytes.
    const long = "abcdefghijklmnopqrstuvwxyz0123456789"; // 36 chars
    const got = io.validName(a, long, 0);
    try t.expectEqual(@as(usize, 32), got.len);
    try t.expectEqualStrings(long[0..32], got);

    // 4) dedup: collision detection is case-insensitive, but each name keeps its
    // own header case (SAS stores the case of the reference).
    var used: std.ArrayList([]const u8) = .empty;
    try t.expectEqualStrings("Foo", try io.uniqueName(a, &used, "Foo"));
    try t.expectEqualStrings("foo0", try io.uniqueName(a, &used, "foo"));
    try t.expectEqualStrings("FOO1", try io.uniqueName(a, &used, "FOO"));
    // dedup respects the 32-byte cap by truncating the base before the suffix.
    const b32 = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"; // 32 A's
    try t.expectEqualStrings(b32, try io.uniqueName(a, &used, b32));
    const d = try io.uniqueName(a, &used, b32);
    try t.expectEqual(@as(usize, 32), d.len);
    try t.expectEqualStrings("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA0", d);
}

test "proc standard: z-scores, constant column -> target mean, fail-loud options (GAP-procstandard)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("v", .num);
    _ = try ds.addColumn("k", .num); // constant -> std 0
    try ds.appendRow(&.{ numV(2), numV(5) });
    try ds.appendRow(&.{ numV(4), numV(5) });
    try ds.appendRow(&.{ numV(6), numV(5) });
    try lib.put("have", ds);

    const cx: ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diags };
    // no MEAN=/STD= -> identity on nonmissing, constant k unchanged (BUG-stdnodefault)
    try runStandard(cx, try lex.tokenize(a, "proc standard data=have out=z; run;", &diags));
    const z = lib.find("z").?;
    try t.expectEqual(@as(f64, 2), z.row(0)[0].num);
    try t.expectEqual(@as(f64, 4), z.row(1)[0].num);
    try t.expectEqual(@as(f64, 6), z.row(2)[0].num);
    for (0..3) |r| try t.expectEqual(@as(f64, 5), z.row(r)[1].num);

    // mean=100 std=15 replace: nonmissing {2,4,6} (mean 4, std 2) -> 85 100 115;
    // the missing -> the target mean 100.
    const d2 = try a.create(Dataset);
    d2.* = Dataset.init(a, "m");
    _ = try d2.addColumn("v", .num);
    try d2.appendRow(&.{numV(2)});
    try d2.appendRow(&.{numV(4)});
    try d2.appendRow(&.{Value.missing});
    try d2.appendRow(&.{numV(6)});
    try lib.put("m", d2);
    try runStandard(cx, try lex.tokenize(a, "proc standard data=m out=c mean=100 std=15 replace; var v; run;", &diags));
    const c = lib.find("c").?;
    try t.expectEqual(@as(f64, 85), c.row(0)[0].num);
    try t.expectEqual(@as(f64, 100), c.row(1)[0].num);
    try t.expectEqual(@as(f64, 100), c.row(2)[0].num); // replaced missing
    try t.expectEqual(@as(f64, 115), c.row(3)[0].num);

    // fail LOUD on unimplemented options/statements (captured, no real abort)
    try t.expectError(error.ParseError, runStandard(cx, try lex.tokenize(a, "proc standard data=m vardef=wgt; var v; run;", &diags)));
    try t.expectError(error.ParseError, runStandard(cx, try lex.tokenize(a, "proc standard data=m; var v; freq f; run;", &diags)));
}

test "NOTE-procsortguards: RANK/STANDARD unsorted BY fails loud (captured); sorted/descending BY unaffected" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Sorted BY (1,1,1,2,2,2) — correct per-group output, guard stays silent.
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 2 }, .{ 1, 4 }, .{ 1, 6 }, .{ 2, 10 }, .{ 2, 20 }, .{ 2, 30 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);
    {
        var dg = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib, .diags = &dg }, &out, try lex.tokenize(a, "proc rank data=d out=r; by g; var x; ranks rx; run;", &dg));
        try t.expect(!dg.hasErrors());
        const r = lib.find("r").?;
        const rx = r.indexOf("rx").?;
        for (0..6, [_]f64{ 1, 2, 3, 1, 2, 3 }) |row, want| try t.expectEqual(want, r.row(row)[rx].num);
    }
    {
        var dg = diag.Diagnostics.init(a);
        try runStandard(.{ .arena = a, .lib = &lib, .diags = &dg }, try lex.tokenize(a, "proc standard data=d out=sz mean=0 std=1; by g; var x; run;", &dg));
        try t.expect(!dg.hasErrors());
        const sz = lib.find("sz").?;
        const x = sz.indexOf("x").?;
        // {2,4,6}: mean 4 std 2 → −1 0 1; {10,20,30}: mean 20 std 10 → −1 0 1
        for (0..6, [_]f64{ -1, 0, 1, -1, 0, 1 }) |row, want| try t.expectEqual(want, sz.row(row)[x].num);
    }

    // Unsorted BY (2,1,2 — the ticket's probe): SAS ERRORs "not sorted in
    // ascending sequence" (the shared MEANS/TRANSPOSE/UNIVARIATE guard's exact
    // wording) and stops; consecutive-run grouping alone ranked every row 1 at
    // exit 0. No OUT= dataset may be produced.
    var lib2 = Library.init(a);
    const ds2 = try a.create(Dataset);
    ds2.* = Dataset.init(a, "d");
    _ = try ds2.addColumn("g", .num);
    _ = try ds2.addColumn("x", .num);
    for ([_][2]f64{ .{ 2, 10 }, .{ 1, 20 }, .{ 2, 30 } }) |r| try ds2.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib2.put("d", ds2);
    {
        var dg = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib2, .diags = &dg }, &out, try lex.tokenize(a, "proc rank data=d out=r; by g; var x; ranks rx; run;", &dg)));
        try t.expect(std.mem.indexOf(u8, try dg.render(), "not sorted in ascending sequence") != null);
        try t.expect(lib2.find("r") == null); // no silently-wrong ranks emitted
    }
    {
        var dg = diag.Diagnostics.init(a);
        try t.expectError(error.ParseError, runStandard(.{ .arena = a, .lib = &lib2, .diags = &dg }, try lex.tokenize(a, "proc standard data=d out=sz mean=0 std=1; by g; var x; run;", &dg)));
        try t.expect(std.mem.indexOf(u8, try dg.render(), "not sorted in ascending sequence") != null);
        try t.expect(lib2.find("sz") == null); // no silently-wrong OUT= either
    }

    // BY DESCENDING flips the guard per key: ascending data under `by descending g`
    // ERRORs. (The descending MESSAGE wording is INFERRED — it appears in none of
    // the acquired SAS volumes; it is whatever the one shared guard emits so all
    // procs stay identical. The check flip itself is Statements ref p.40.)
    {
        var dg = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &dg }, &out, try lex.tokenize(a, "proc rank data=d out=r2; by descending g; var x; ranks rx; run;", &dg)));
        try t.expect(std.mem.indexOf(u8, try dg.render(), "not sorted in descending sequence") != null);
        try t.expect(lib.find("r2") == null);
    }
    {
        var dg = diag.Diagnostics.init(a);
        try t.expectError(error.ParseError, runStandard(.{ .arena = a, .lib = &lib, .diags = &dg }, try lex.tokenize(a, "proc standard data=d out=sz2 mean=0 std=1; by descending g; var x; run;", &dg)));
        try t.expect(std.mem.indexOf(u8, try dg.render(), "not sorted in descending sequence") != null);
        try t.expect(lib.find("sz2") == null);
    }

    // BY DESCENDING on DESCENDING-sorted data → guard silent, groups ranked in
    // the data's own order (g=2 rows first).
    var lib3 = Library.init(a);
    const ds3 = try a.create(Dataset);
    ds3.* = Dataset.init(a, "dd");
    _ = try ds3.addColumn("g", .num);
    _ = try ds3.addColumn("x", .num);
    for ([_][2]f64{ .{ 2, 10 }, .{ 2, 30 }, .{ 1, 20 } }) |r| try ds3.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib3.put("dd", ds3);
    {
        var dg = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib3, .diags = &dg }, &out, try lex.tokenize(a, "proc rank data=dd out=rd; by descending g; var x; ranks rx; run;", &dg));
        try t.expect(!dg.hasErrors());
        const rd = lib3.find("rd").?;
        const rx = rd.indexOf("rx").?;
        for (0..3, [_]f64{ 1, 2, 1 }) |row, want| try t.expectEqual(want, rd.row(row)[rx].num);
    }

    // NOTSORTED drops the guard: unsorted (2,1,2) ranks each contiguous run —
    // explicit opt-in, no error.
    {
        var dg = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try runRank(.{ .arena = a, .lib = &lib2, .diags = &dg }, &out, try lex.tokenize(a, "proc rank data=d out=rn; by g notsorted; var x; ranks rx; run;", &dg));
        try t.expect(!dg.hasErrors());
        try t.expect(lib2.find("rn") != null);
    }
}

test "GAP-procopts: unknown PROC statement options fail LOUD across the PROC surface; honoured/inert controls stay clean" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ strV("a"), numV(1) });
    try ds.appendRow(&.{ strV("b"), numV(2) });
    try lib.put("d", ds);

    // ── the audit probe itself: PROC MEANS silently skipped `bogusopt=3`
    //    while PROC PRINT failed loud on the same class — the inconsistency. ──
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d bogusopt=3; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "bogusopt") != null);
    }
    // the typo class the audit named: `maxddec=2` must not silently skip MAXDEC=
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc summary data=d maxddec=2; var x; run;", &diags);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "maxddec") != null);
    }
    // positive controls: honoured options + inert SUMSIZE=/THREADS + the
    // data=d(keep=…) paren group (previously a bogus "statistic-keyword keep"
    // WARNING on legal input) — clean run, no warnings at all.
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=d(keep=x) sumsize=1000 threads nothreads maxdec=2 n mean; var x; run;", &diags);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(std.mem.indexOf(u8, try diags.render(), "WARNING") == null);
        try t.expect(std.mem.indexOf(u8, out.items, "Mean") != null);
    }
    // RANK: typo'd GROUPS= and an unguarded score request both name themselves
    for ([_][]const u8{ "proc rank data=d out=r grups=4; var x; ranks rx; run;", "proc rank data=d out=r blom; var x; run;" }) |src| {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, src, &diags);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
    }
    // RANK positive: out=r(keep=…) paren group must not false-fire the loud arm
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=d out=r(keep=x rx) ties=low descending; var x; ranks rx; run;", &diags);
        try runRank(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
    }
    // DELETE: LIB=/MEMTYPE=/a stray option names itself (a second bare name
    // after DATA= stays a dataset list — SAS's own parse, not an option)
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc delete lib=work data=d; run;", &diags);
        try t.expectError(error.ParseError, runDelete(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "lib") != null);
    }
    // DATASETS: unknown header option + non-DATA MEMTYPE= name themselves;
    // nolist/nodetails/memtype=data stay inert (delete still runs)
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets lib=work kll nolist; run; quit;", &diags);
        try t.expectError(error.ParseError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "kll") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets memtype=catalog nolist; run; quit;", &diags);
        try t.expectError(error.ParseError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "catalog") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets lib=work nolist nodetails memtype=data; delete d; run; quit;", &diags);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &diags }, &out, toks);
        try t.expect(!diags.hasErrors());
        try t.expect(lib.find("d") == null); // the delete still happened
    }
    // EXPORT: unknown header option + unknown sub-statement name themselves
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc export data=d outfile=\"/tmp/x.csv\" dbms=csv bogusopt=1; run;", &diags);
        try t.expectError(error.ParseError, runExport(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "bogusopt") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc export data=d outfile=\"/tmp/x.csv\" dbms=csv; putname=no; run;", &diags);
        try t.expectError(error.ParseError, runExport(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "putname") != null);
    }
    // IMPORT: unknown header option + unknown sub-statement name themselves
    // (both fire before any file is read)
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc import datafile=\"/no/such.csv\" out=b dbms=csv dbmx=csv; run;", &diags);
        try t.expectError(error.ParseError, runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "dbmx") != null);
    }
    {
        var diags = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc import datafile=\"/no/such.csv\" out=b dbms=csv replace; getname=yes; run;", &diags);
        try t.expectError(error.ParseError, runImport(.{ .arena = a, .lib = &lib, .diags = &diags }, toks));
        try t.expect(std.mem.indexOf(u8, try diags.render(), "getname") != null);
    }
}

test "D-009: a recognized-but-unsupported PROC construct exits 2, a typo stays 1 (GAP-gapsexitingone §5b)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    format.clearUserFormats();
    defer format.clearUserFormats();

    var lib = Library.init(a);
    try lib.put("have", try buildHave(a));

    // Each of these is VALID SAS 9.4 opensas doesn't implement, matched by a
    // guard naming THAT construct — an opensas gap (failGap/markGap) → exit 2,
    // "file an opensas issue". The step still fails LOUD with the same ERROR
    // message; only the rc signal moves 1 → 2. Pinned against exitCode
    // directly (the two signals main.zig:89-90 read) because only rc-pinned
    // fixtures can check this end-to-end (audit-exitcodecontract.md §6/I1).
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have order=formatted; var age; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have completetypes; class name; var age; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; histogram age; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work nolist; contents data=have out=b; run; quit;", &d);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work nolist; contents data=_all_; run; quit;", &d);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture $p low-high='99'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p low-high='%Y'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }

    // Controls keep rc 1 reachable: each is a condition real SAS 9.4 also
    // rejects — a typo'd/invalid option value, overlapping VALUE ranges
    // without MULTILABEL, a garbage PICTURE entry, a CONTENTS member that
    // isn't there.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have order=bogus; var age; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; value f 1-2='a' 2-3='b'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p foo='99'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work nolist; contents data=nothere; run; quit;", &d);
        try runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // Split catch-alls: the recognized valid-SAS arm goes to rc 2 …
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; exact age; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work memtype=view nolist; run; quit;", &d);
        try t.expectError(error.ParseError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; invalue mynum 'one'=1; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; value f (multilabel) 1='a' 1='b'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; value f .='missing' 1='a'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // … while the typo arm of the SAME split stays the user's rc 1.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; tabels age; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // §5b re-verdict splits (the statistical-volume PROCs) — each gap arm is a
    // documented SAS 9.4 construct the guide enumerates in one place (rc 2),
    // each typo arm is the SAME catch-all fed a non-option (rc 1).
    { // MEANS header option: FW= is documented (rc 2); `maxddec=2` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have fw=8; var age; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC MEANS: option fw is not supported") != null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have maxddec=2; var age; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC MEANS: option maxddec is not supported") != null);
    }
    { // MEANS sub-statement: LABEL is valid-in-MEANS (rc 2); `zzzq` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have; var age; label age='a'; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have; var age; zzzq age; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // MEANS OUTPUT `/`: LEVELS is documented (rc 2); `autonam` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have; var age; output out=o n= / levels; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have; var age; output out=o n= / autonam; run;", &d);
        try t.expectError(error.ParseError, runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // FREQ header ALREADY-CORRECT: Table 3.4's seven options are all handled,
      // so only a typo reaches the catch-all — pinned at rc 1.
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have odrer=freq; tables age; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // FREQ TABLES: MISSPRINT is in Table 3.9 (rc 2); `chisqq` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; tables age / missprint; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC FREQ: TABLES option missprint is not supported") != null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; tables age / chisqq; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC FREQ: TABLES option chisqq is not supported") != null);
    }
    { // UNIVARIATE header: NORMAL is documented (rc 2); `nromal` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have normal; var age; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have nromal; var age; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // UNIVARIATE sub-statement: INSET is a valid statement (rc 2 — this pin
      // STOOD at rc 1 while INSET was parked conflated; the split moves it);
      // `zzzq` stays a typo (rc 1).
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; inset age; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; zzzq age; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // UNIVARIATE OUTPUT: PCTLPTS= (percentile-options) and GEOMEAN (Table 4.14)
      // are documented keywords (rc 2); `pctlpt=` is a typo (rc 1).
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; var age; output out=o pctlpts=33; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; var age; output out=o geomean=g; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; var age; output out=o pctlpt=33; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // RANK: PRESERVERAWBYVALUES is documented (rc 2); `grups=4` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=r preserverawbyvalues; var age; run;", &d);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=r grups=4; var age; run;", &d);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // DELETE: MEMTYPE= is documented (rc 2); `dta=` is a typo (rc 1).
      // data=nothere, not have: the data= list deletes AS IT PARSES, so a
      // real member would vanish under the later pins (the warn is fine).
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc delete data=nothere memtype=catalog; run;", &d);
        try t.expectError(error.ParseError, runDelete(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC DELETE: option memtype is not supported") != null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc delete data=nothere dta=nothere; run;", &d);
        try t.expectError(error.ParseError, runDelete(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // APPEND: NOWARN is documented (rc 2); `froce` is a typo (rc 1).
      // Pinned on exitCode, not expectError: the two arms deliberately
      // return different error types (gap arm ParseError via failGap, the
      // family's long-standing ExecError typo arm) — the rc is the signal.
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc append base=have data=have nowarn; run;", &d);
        runAppend(.{ .arena = a, .lib = &lib, .diags = &d }, toks) catch {};
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc append base=have data=have froce; run;", &d);
        runAppend(.{ .arena = a, .lib = &lib, .diags = &d }, toks) catch {};
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // DATASETS header: NOPRINT is documented (rc 2); `kll` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work noprint nolist; run; quit;", &d);
        try t.expectError(error.ParseError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work kll nolist; run; quit;", &d);
        try t.expectError(error.ParseError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // EXPORT header: LABEL is documented (rc 2); `dbm=csv` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc export data=have outfile=\"/tmp/x.csv\" dbms=csv label; run;", &d);
        try t.expectError(error.ParseError, runExport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc export data=have outfile=\"/tmp/x.csv\" dbm=csv; run;", &d);
        try t.expectError(error.ParseError, runExport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // EXPORT sub-statement: DELIMITER= is documented (rc 2); `putname` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc export data=have outfile=\"/tmp/x.csv\" dbms=csv; delimiter=','; run;", &d);
        try t.expectError(error.ParseError, runExport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc export data=have outfile=\"/tmp/x.csv\" dbms=csv; putname=no; run;", &d);
        try t.expectError(error.ParseError, runExport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // IMPORT header: TABLE= is documented (rc 2); `dbm=` is a typo (rc 1)
      // (both fire before any file is read)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc import datafile=\"/no/such.csv\" out=b dbms=csv table=\"t\"; run;", &d);
        try t.expectError(error.ParseError, runImport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc import datafile=\"/no/such.csv\" out=b dbm=csv; run;", &d);
        try t.expectError(error.ParseError, runImport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // IMPORT sub-statement: VARNAMEROW= is documented (rc 2); `getname` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc import datafile=\"/no/such.csv\" out=b dbms=csv; varnamerow=2; run;", &d);
        try t.expectError(error.ParseError, runImport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc import datafile=\"/no/such.csv\" out=b dbms=csv replace; getname=yes; run;", &d);
        try t.expectError(error.ParseError, runImport(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // FORMAT header: CASFMTLIB=/MAXLABLEN=/FMTLIB are documented (rc 2);
      // `mxlablen=` / `zzzq` are typos (rc 1). The two header arms split on
      // token shape, so both shapes get a gap pin and a typo pin.
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format casfmtlib=x; value f 1='a'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format maxlablen=8; value f 1='a'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format fmtlib; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format cntln=x; value f 1='a'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format mxlablen=8; value f 1='a'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // FORMAT PICTURE per-entry options: FILL= is documented (rc 2);
      // `filll` is a typo (rc 1)
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p low-high='99' (fill='*'); run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p low-high='99' (filll='*'); run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc datasets library=work memtype=dta nolist; run; quit;", &d);
        try t.expectError(error.ParseError, runDatasets(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; valeu f 1='x'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; value f (multilabl) 1='a'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; value f @='x'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // Adjacent family (wording 'is not yet supported', outside the audit's 37):
    // named-list/keyword guards, every hit a recognized gap → rc 2.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; tables age / chisq; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc freq data=have; by name; tables age; run;", &d);
        try t.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have; id name; var age; run;", &d);
        try t.expectError(error.ParseError, runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=r savage; var age; run;", &d);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // BUG-proctypoexits2 follow-on: a bare documented NORMAL= score name
    // (BLOM/TUKEY/VW, Procedures Guide 7th ed. printed p. 2048) is the same
    // recognized gap — it can only be a score request, never a typo.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc rank data=have out=r blom; var age; run;", &d);
        try t.expectError(error.ParseError, runRank(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // BUG-proctypoexits2: the SORT/TRANSPOSE/CONTENTS/COMPARE `unknown option`
    // catch-alls, split. The gap arm — a documented SAS 9.4 option opensas
    // doesn't implement — keeps the byte-identical UNSUPPORTED message at rc 2 …
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc sort data=have force; by age; run;", &d);
        try runSort(.{ .arena = a, .lib = &lib, .diags = &d }, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expectEqualStrings("PROC SORT: unknown option force", g_test_last_unsup);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have indb=no; var age; run;", &d);
        try runTranspose(.{ .arena = a, .lib = &lib, .diags = &d }, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expectEqualStrings("PROC TRANSPOSE: unknown option indb", g_test_last_unsup);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc contents data=have directory; run;", &d);
        try runContents(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expectEqualStrings("PROC CONTENTS: unknown option directory", g_test_last_unsup);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc compare base=have compare=have outstats=s; run;", &d);
        try runCompare(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expectEqualStrings("PROC COMPARE: unknown option outstats", g_test_last_unsup);
    }
    // … while a plain TYPO landing on the SAME catch-all is the user's rc 1,
    // with the same message body reported through diags.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc sort data=have oout=have; by age; run;", &d);
        try t.expectError(error.ParseError, runSort(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC SORT: unknown option oout") != null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc transpose data=have prefx=c; var age; run;", &d);
        try t.expectError(error.ParseError, runTranspose(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC TRANSPOSE: unknown option prefx") != null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc contents data=have dta=have; run;", &d);
        try t.expectError(error.ParseError, runContents(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC CONTENTS: unknown option dta") != null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc compare base=have compare=have criterionn=0.1; run;", &d);
        try t.expectError(error.ParseError, runCompare(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC COMPARE: unknown option criterionn") != null);
    }
    // and rc 0: a clean PROC MEANS.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have n mean; var age; run;", &d);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    diag.resetGap();
}

test "PROC DELETE data=x(gennum=all) fails loud BEFORE the delete (BUG-deletegennumsilent)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The doc's OWN spelling for deleting all generations goes in parens after
    // the file name (printed pp. 786-787, === pdf 835/836/837 ===). opensas has
    // no generation model, so the four documented in-parens options failGap
    // (rc 2) — and the file must be UNTOUCHED: the old lparen-skip deleted x
    // and said nothing, a silent drop on a destructive request (D-002).
    {
        diag.resetGap();
        var lib = Library.init(a);
        try lib.put("have", try buildHave(a));
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc delete data=have(gennum=all); run;", &d);
        try t.expectError(error.ParseError, runDelete(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC DELETE: option gennum is not supported (only DATA=)") != null);
        try t.expect(lib.find("have") != null); // behaviour pin: the delete did NOT run
    }
    { // MEMTYPE= is in the same closed paren set — same gap, same survival.
        diag.resetGap();
        var lib = Library.init(a);
        try lib.put("have", try buildHave(a));
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc delete data=have (memtype=catalog); run;", &d);
        try t.expectError(error.ParseError, runDelete(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(lib.find("have") != null);
    }
    { // A name the doc does NOT put in those parens (KEEP=) stays put per
      // D-018: the old silent skip stands, the delete still runs, rc 0.
        diag.resetGap();
        var lib = Library.init(a);
        try lib.put("have", try buildHave(a));
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc delete data=have(keep=a); run;", &d);
        try runDelete(.{ .arena = a, .lib = &lib, .diags = &d }, toks);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(lib.find("have") == null);
    }
    diag.resetGap();
}

test "PROC UNIVARIATE accepts and APPLIES data=x(keep=/where=…) (BUG-univdatasetopts)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The paren group used to hit the header catch-all: rc 1 with a degenerate
    // empty-name message (the lparen token's text). Now skipped as a group so
    // procInput applies it — the WHERE= run's N=2 (not 3) pins APPLICATION.
    var lib = Library.init(a);
    try lib.put("have", try buildHave(a));
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have(keep=age); var age; run;", &d);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "is not supported") == null);
    }
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc univariate data=have(where=(age>28)); var age; run;", &d);
        try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, out.items, "N                              2  Sum Weights") != null); // 40,30 survive; unfiltered N=3
    }
    diag.resetGap();
}

test "PROC UNIVARIATE accepts and APPLIES the WHERE statement (BUG-univwherestmt)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // WHERE is documented with UNIVARIATE ("Procedures That Support the WHERE
    // Statement", printed p. 89, === pdf 138 ===) but the statement loop had
    // no arm: rc 1 on a universal statement. MEANS' arm now skips it and
    // procInput applies it — N=2 (not 3) pins the application.
    var lib = Library.init(a);
    try lib.put("have", try buildHave(a));
    diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const toks = try lex.tokenize(a, "proc univariate data=have; where age>28; var age; run;", &d);
    try runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
    try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try t.expect(std.mem.indexOf(u8, out.items, "N                              2  Sum Weights") != null);
    diag.resetGap();
}

test "PROC MEANS bare documented flags warn the truth, unknown keywords keep not-recognized (BUG-meansflagmsg)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try lib.put("have", try buildHave(a));
    // A documented bare flag (Summary of Optional Arguments, printed
    // pp. 1482-1484) used to be called "not recognized" — a lie about the
    // doc. Still a warn, still rc 0: message-only.
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have printalltypes; var age; run;", &d);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        const r = try d.render();
        try t.expect(std.mem.indexOf(u8, r, "PROC MEANS: option printalltypes is not supported and is ignored") != null);
        try t.expect(std.mem.indexOf(u8, r, "not recognized") == null);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    { // An unknown bare keyword keeps the honest not-recognized warning.
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const toks = try lex.tokenize(a, "proc means data=have zzzq; var age; run;", &d);
        try runMeans(.{ .arena = a, .lib = &lib, .diags = &d }, &out, toks);
        try t.expect(std.mem.indexOf(u8, try d.render(), "statistic-keyword zzzq is not recognized and is ignored") != null);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    diag.resetGap();
}

test "PROC FORMAT PICTURE position-1 (format-options) split (BUG-picturepos1opts)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    format.clearUserFormats();
    defer format.clearUserFormats();
    var lib = Library.init(a);
    // "The DEFAULT, FUZZ, MAX, MIN, MULTILABEL, NOTSORTED, and ROUND options
    // are valid before the value range specification" (printed p. 1098,
    // === pdf 1147 ===) — documented → rc 2, NAMED (was: rc 1 with the
    // degenerate `unsupported PICTURE entry ''`).
    {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p (fuzz=0.1) low-high='99'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC FORMAT: PICTURE format option fuzz is not supported") != null);
    }
    { // a name the doc does not put there → the user's rc 1, also NAMED.
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p (fuzzy=0.1) low-high='99'; run;", &d);
        try t.expectError(error.ParseError, runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks));
        try t.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try t.expect(std.mem.indexOf(u8, try d.render(), "PROC FORMAT: PICTURE format option fuzzy is not supported") != null);
    }
    { // control: no position-1 group → the picture builds clean.
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const toks = try lex.tokenize(a, "proc format; picture p low-high='99'; run;", &d);
        try runFormat(.{ .arena = a, .lib = &lib, .diags = &d }, toks);
        try t.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    diag.resetGap();
}
