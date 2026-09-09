//! CLI — the whole pipeline, wired end to end: read a `.sas` file, split it into
//! DATA/PROC steps, and for each run lexer → parser → executor, printing the SAS
//! log (`put` output) and any `proc print` table to stdout.
//!
//! Step framing is C3's job: the parser (A2) parses one step's *body* and knows
//! nothing of `data name;` / `proc …;`. We split the token stream at `data`/
//! `proc` keywords that sit on a statement boundary — safe because the lexer
//! emits `datalines` content as `.data_line` tokens, so a `data` buried in raw
//! data never looks like a keyword. Datasets a step creates are kept in a
//! `Library` so a later step's `set` finds them.
//!
//! `interpret` is deliberately IO-free (arena in, byte buffer out) so the whole
//! pipeline is unit-testable under `zig build test`; only `main` touches files
//! and stdout. Corpus programs are `data _null_;` + `put`, so their expected
//! output is exactly the log we accumulate here.
//!
//! ponytail: no dataset options (`data x(keep=…)`), no PROC but PRINT, and the
//! PRINT layout is a plain aligned table, not SAS's exact listing — grow with
//! the corpus. Unsupported features print `UNSUPPORTED: <feature>` to stderr,
//! the marker the corpus runner reads to name the next backlog task.

const std = @import("std");
const Io = std.Io;
const sas = @import("sas");

const Token = sas.lexer.Token;
const max_file: Io.Limit = .limited(1 << 31);

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    const io = init.io;

    const args = try init.minimal.args.toSlice(a);
    // Parse `--sasautos <dir>` (autocall library) anywhere in the args; the first
    // non-flag arg is the input `.sas`. `$SASAUTOS` is the fallback.
    var file: ?[]const u8 = null;
    var sasautos: ?[]const u8 = init.environ_map.get("SASAUTOS");
    var ai: usize = 1;
    while (ai < args.len) : (ai += 1) {
        if (std.mem.eql(u8, args[ai], "--sasautos") and ai + 1 < args.len) {
            sasautos = args[ai + 1];
            ai += 1;
        } else if (file == null) {
            file = args[ai];
        }
    }
    if (file == null) {
        std.debug.print("usage: sas [--sasautos <dir>] <file.sas>\n", .{});
        return;
    }
    sas.macro.setAutocallDir(sasautos);

    const src = Io.Dir.cwd().readFileAlloc(io, file.?, a, max_file) catch |e| {
        std.debug.print("sas: cannot read {s} ({t})\n", .{ file.?, e });
        return;
    };

    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    interpret(a, &out, &diags, src, io) catch |e| {
        // A propagated lex/parse/exec error already recorded a located diagnostic
        // via diags.fail() — render() below prints `ERROR(Ln): …`. Only emit the
        // bare error-name line when NO diagnostic carries the detail (e.g.
        // OutOfMemory), so we don't duplicate a location-less `ERROR: LexError`
        // above the real one (DIAG-lexloc). exit(1) still fires below via
        // diags.hasErrors().
        if (!diags.hasErrors()) failLoud("{t}", .{e});
    };

    // stdout carries the program's output only (log + print); diagnostics and
    // NOTEs go to stderr, SAS-style, so they never pollute a corpus diff.
    var buf: [4096]u8 = undefined;
    var fw = stdoutWriter(io, &buf);
    const w = &fw.interface;
    try w.writeAll(out.items);
    try w.flush();

    if (diags.count() > 0) std.debug.print("{s}", .{try diags.render()});

    const rc = processExitCode(&diags);
    if (rc != 0) std.process.exit(rc);
}

/// THE exit code for a finished run — D-009 plus the D-009a ABORT override.
/// 0 clean, 1 user-program error (their SAS is wrong — parse/exec/data errors
/// reported via `diags`, or a format error via `format.formatErrored`), 2 opensas
/// defect/gap (any UNSUPPORTED: path — `failLoud`'s `g_failed` or proc's
/// unsupported → `diag.gapHit()` — plus a caught propagated defect). A gap
/// outranks a user error so a calling agent files an opensas issue on 2 and fixes
/// the SAS on 1. (CLIN-failloud: a fail-loud still exits non-zero.)
///
/// ABORT ABEND n / ABORT RETURN n (D-009a, BUG-abortreturncode) outranks all of
/// it: the user's ABORT halted the session and their return code becomes the
/// process exit code, deliberately NOT confined to {0,1,2}.
///
/// BUG-wasmignoresabortrc — this is a FUNCTION, and pub, because it had been
/// COPIED: `wasm.zig` open-coded the two signals and `diag.exitCode` but not the
/// abort line above it, so `abort return 3` returned 1 on that surface. The
/// arithmetic was never the problem (audit §6/I5); the duplication was.
pub fn processExitCode(diags: *const sas.diag.Diagnostics) u8 {
    if (sas.exec.g_abort_rc) |arc| return arc;
    const gap = g_failed or sas.diag.gapHit();
    const user_err = diags.hasErrors() or sas.format.formatErrored();
    return sas.diag.exitCode(gap, user_err);
}

/// BUG-iostreamclobber: stdout MUST be a STREAMING writer, not the positional
/// default (`File.Writer.init` → pwrite at a tracked offset starting at 0).
/// Under `sas prog.sas > log 2>&1` (stdout+stderr share one file) positional
/// writes collided with stderr's own offset-0 start and the streams overwrote
/// each other — silently losing/corrupting PROC PRINT tables and PUT output.
/// Streaming mode writes at the shared OS file position, so combined streams
/// interleave in write order like real SAS.
fn stdoutWriter(io: Io, buf: []u8) Io.File.Writer {
    return .initStreaming(.stdout(), io, buf);
}

/// Set when an unsupported PROC/statement is hit, so `main` exits non-zero.
/// pub + reset per run for the wasm build (wasm.zig runs many programs per load).
pub var g_failed: bool = false;

/// TEST-quietnoise: negative tests exercise the fail-loud path but must not spam
/// stderr (it hides a REAL failure in the green gate). In a test build the message
/// is CAPTURED here for the test to assert on; the CLI (is_test=false) still prints
/// `ERROR:` to stderr and exits non-zero — fail-loud is unchanged.
var g_test_err_buf: [512]u8 = undefined;
pub var g_test_last_err: []const u8 = "";

/// Emit a SAS-style `ERROR:` line to the log (stderr) and mark the run failed.
/// `g_failed` is the GAP half of D-009 (→ rc 2, "file an opensas issue"), so
/// this is for UNSUPPORTED paths ONLY — a user error uses `userErr` below.
fn failLoud(comptime fmt: []const u8, args: anytype) void {
    g_failed = true;
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, fmt, args) catch "fail-loud message too long";
    } else {
        std.debug.print("ERROR: " ++ fmt ++ "\n", args);
    }
}

/// DEC-abortrcvsD009 — `failLoud`'s D-009 sibling for the OTHER class: the
/// user's SAS is wrong (they named a data set/libref that is not there, or gave
/// a format the column's type forbids), so the run exits **1** ("fix your SAS"),
/// not 2 ("file an opensas issue"). `failLoud` was doing double duty for both
/// classes, which put PROC PRINT's `Data set X is not sorted…` at rc 2 while the
/// six proc.zig sites emitting the BYTE-IDENTICAL message sat at rc 1.
/// Routing through `diags` is what makes it rc 1 (main's `user_err` reads
/// `diags.hasErrors()`), and it deliberately matches those twins exactly — a
/// plain step error, so errhalt/syntax-check treats a PRINT error like a MEANS
/// error. Under `is_test` the captured reporter holds it, never stderr (D-003).
fn userErr(diags: *sas.diag.Diagnostics, comptime fmt: []const u8, args: anytype) void {
    diags.report(.err, 0, fmt, args) catch {};
}

/// Run a whole `.sas` source, appending all program output to `out`. `io` is
/// null for the pure-in-memory path (unit tests, corpus programs); with an `Io`,
/// CSV-backed LIBNAME datasets are read before and written after the run.
pub fn interpret(a: std.mem.Allocator, out: *std.ArrayList(u8), diags: *sas.diag.Diagnostics, src: []const u8, io: ?Io) !void {
    // Drop any user format catalog from a prior run — it points into that run's
    // (now-freed) arena, and `format.apply` reads the global catalog (PROC FORMAT
    // reinstalls its own this run) — plus format.zig's other run-scoped globals
    // (BUG-fmterrorneverreset: g_fmt_error, g_nofmterr; see resetPerRun there).
    sas.format.resetPerRun();
    sas.functions.resetPerRun(); // drop prior-run prx/dsfns/hashing handles (taste #12)
    sas.diag.resetGap(); // clear the per-run opensas-gap flag (D-009 exit code)
    // …and resetGap's TWIN gap flag (BUG-fmterrorneverreset): `gap` is `g_failed
    // or gapHit()`, so clearing only one half left the other sticky. wasm.zig was
    // clearing this itself — i.e. the reset list had been COPIED, which is how the
    // format flags above came to leak there.
    g_failed = false;
    sas.exec.g_abort_rc = null; // clear any prior run's ABORT (BUG-abortreturncode)
    fileref_count = 0; // new session: drop prior-run filerefs (their name/path slices point into the prior run's freed arena — wasm runs many programs per load)
    var lib = sas.exec.Library.init(a);
    lib.diags = diags; // GH#15: so a read-only-libref output access reports LOUD
    sas.functions.bindLibrary(&lib); // BUG-sclbind: give SCL fns the live Library

    // One up-front expand (throwaway diags, discarded output) purely to discover
    // LIBNAME declarations and load input datasets — dataset references do not depend
    // on runtime macro timing, so this side-effect-free pass is safe and avoids
    // double-loading per chunk.
    var junk = sas.diag.Diagnostics.init(a);
    const setup_expanded = sas.macro.expand(a, src, &junk) catch "";
    // GH#17 ISS-macrolinemap: if the macro processor transformed the source at all,
    // every line the run reports is a POST-EXPANSION offset (macro bodies/%do add
    // newlines the source never had), so diag marks those positions `(expanded Lnn)`
    // instead of a bare `(Lnn)` that masquerades as — and gets line-mapped into — a
    // source/macro file. A no-op macro pass (plain program) leaves expanded==src, so
    // ordinary syntax errors keep their true, unmarked source line.
    diags.expansion_space = !std.mem.eql(u8, src, setup_expanded);
    var setup_toks = sas.lexer.tokenize(a, setup_expanded, &junk) catch &[_]Token{};
    // Mutable at runtime: an EXECUTED libname statement re-binds its libref for
    // every later step (GAP-proccopy); the setup pass holds FIRST declarations,
    // which the preloading below uses.
    var libref_list = try parseLibnames(a, diags, setup_toks); // GAP-libnameopt: the option-level fail-loud fires in THIS pre-pass
    const librefs = libref_list.items;
    try syncReadonlyRefs(a, &lib, librefs); // GH#15: which librefs reject output access
    setup_toks = try coalesceLibrefs(a, setup_toks, librefs);
    // BUG-existdisk: bind the libname map so EXIST() can disk-probe a member
    // nothing preloaded (a name built only inside macro text never appears as a
    // literal `lib.ds` token below). Empty for pure-in-memory runs (io == null).
    try bindDiskRefs(a, librefs, io != null);
    // Datasets read from a directory libname are loaded read-only: track their
    // object pointers so writeLibOutputs never writes an unmodified input back
    // (stray `.sas7bdat` churn that shadows an edited `.csv`) — E-sas7write-noreadback.
    var loaded_ro: std.ArrayList(*sas.dataset.Dataset) = .empty;
    var damaged: std.StringHashMap(void) = .init(a);
    if (io) |iov| try loadLibInputs(a, iov, &lib, librefs, setup_toks, &loaded_ro, &damaged, diags);
    // GH#34 ISS-fmtcatalog: load user format DEFINITIONS from each OPTIONS
    // FMTSEARCH= libref's `formats.sas7bcat` so PUT/vvalue/attached formats decode.
    try loadFmtCatalogs(a, setup_toks, librefs);

    // TITLE/FOOTNOTE accumulate across the whole run.
    var globals: Globals = .{};

    // INTERLEAVE macro expansion with execution (BUG-runtimemacroscope +
    // BUG-macrointerleave): expand one raw chunk, but flush-and-run each expanded
    // step at its `run;`/`quit;` boundary (via `expandExec` → `interleaveStep`) so a
    // CALL SYMPUT inside a macro's data step is visible to the SAME body's later
    // `%do &var`. Any trailing remainder (unterminated final step / pure-macro
    // output) is run afterwards. CALL SYMPUT vars feed back into the session so
    // later macro code (%put/%if/%do &n) sees them.
    var session = sas.macro.Session.init(a, diags);
    const chunks = try rawSegments(a, src);
    var ctx = StepCtx{
        .a = a,
        .out = out,
        .lib = &lib,
        .diags = diags,
        .globals = &globals,
        .io = io,
        .librefs = &libref_list,
        .session = &session,
        .loaded_ro = &loaded_ro,
        .damaged = &damaged,
    };
    // NOTE-chunkrelativelineno: chunks tile src contiguously, so track the
    // source line each chunk starts at (1 + newlines before it).
    var chunk_line: usize = 1;
    for (chunks) |chunk| {
        if (ctx.ended) break; // ENDSAS in an earlier chunk ended the session
        ctx.line_off = chunk_line - 1;
        var mit = lib.macro_vars.iterator();
        while (mit.next()) |e| try session.seedVar(e.key_ptr.*, e.value_ptr.*);

        const remainder = try session.expandExec(chunk, &ctx, interleaveStep);
        try runExpanded(&ctx, remainder, chunks.len == 1);
        chunk_line += std.mem.count(u8, chunk, "\n");
    }

    if (io) |iov| try writeLibOutputs(a, iov, &lib, libref_list.items, loaded_ro.items);
}

/// State the interleaved step-runner needs, passed through `expandExec` as an
/// opaque pointer so the macro layer can call back at each step boundary.
const StepCtx = struct {
    a: std.mem.Allocator,
    out: *std.ArrayList(u8),
    lib: *sas.exec.Library,
    diags: *sas.diag.Diagnostics,
    globals: *Globals,
    io: ?Io,
    librefs: *std.ArrayList(Libref), // mutable: runtime libname re-binds (GAP-proccopy)
    session: *sas.macro.Session,
    loaded_ro: *std.ArrayList(*sas.dataset.Dataset),
    // NOTE-truncreadmsg: two-level names whose member file was PRESENT but
    // unreadable (already reported once, naming the real cause) — later
    // loadLibInputs passes skip the re-read AND the re-report.
    damaged: *std.StringHashMap(void),
    ended: bool = false, // ENDSAS seen: stop reading input, exit normally (BUG-endsasexit)
    // NOTE-chunkrelativelineno (QA tick312 F3): the current raw chunk's start
    // line in src, minus 1 — tokenize restarts line numbering per chunk, so a
    // diagnostic after the first top-level `run;` was reported CHUNK-RELATIVE
    // (a typo on source line 9 came out as L3).
    line_off: usize = 0,
};

/// Run one slice of already-expanded source: tokenize, split into steps, execute
/// each (or apply a global statement), then feed any CALL SYMPUT vars it created
/// back into the macro session. `allow_anon` runs an unframed token stream as a
/// single `data _null_` step (only for a whole single-chunk open-code program).
fn runExpanded(ctx: *StepCtx, text: []const u8, allow_anon: bool) sas.diag.Error!void {
    const a = ctx.a;
    var toks = try sas.lexer.tokenize(a, text, ctx.diags);
    // NOTE-chunkrelativelineno: `text` is one rawSegments chunk (or a step
    // flushed from it), so its lines number from 1 — shift them back to
    // absolute source lines. Only when NO macro pass transformed the source:
    // with transformation the number is a post-expansion offset, honestly
    // marked `(expanded Lnn)` by GH#17 — shifting that would mislabel twice.
    if (!ctx.diags.expansion_space and ctx.line_off > 0) {
        for (toks) |*t| t.line += ctx.line_off;
    }
    toks = try coalesceLibrefs(a, toks, ctx.librefs.items);
    // BUG-existdisk: a libref member named only inside macro text first appears
    // as a literal `lib.ds` token HERE, after runtime expansion — the up-front
    // preload in `interpret` never saw it. Load any still-missing members now.
    if (ctx.io) |iov| try loadLibInputs(a, iov, ctx.lib, ctx.librefs.items, toks, ctx.loaded_ro, ctx.damaged, ctx.diags);
    const segs = try segments(a, toks, !allow_anon, ctx.diags);
    if (segs.len == 0) {
        if (allow_anon and toks.len > 0 and !ctx.diags.hasStepErrors())
            _ = try runData(a, ctx.out, ctx.lib, ctx.diags, toks, "_null_", ctx.io, &.{});
    } else for (segs) |seg| {
        if (seg.global) {
            // NOTE-globalstmtunresolved: a top-level global statement never
            // passes bindStepVars (that is the step path), so discharge the
            // pending unresolved-&name warnings HERE — late binding cannot
            // apply (no prior step exists in the chunk), the same reasoning
            // that makes %PUT warnable (Macro Language Ref. printed p.152).
            // A HOISTED mid-step global skips this: its tokens remain in the
            // step, where bindStepVars already discharges them — warning here
            // too would say it twice. Before any handling: SAS's word scanner
            // warns when the resolution fails, ahead of the statement itself.
            if (!seg.hoisted) try sas.macro.warnUnresolvedIn(toks[seg.start..seg.end], ctx.diags);
            // Global statements (libname/options/title) still apply in
            // syntax-check mode, as in real SAS.
            // GAP-proccopy: an EXECUTED libname statement re-binds the libref
            // for every later step (a real XPT-export macro points xptfile at a
            // NEW .xpt per %do iteration; first-declaration-wins wrote all 27
            // members through one path). Execution order governs from here on.
            if (eqi(toks[seg.start].text, "libname")) {
                // null diags: options were already validated by the whole-program
                // pre-pass (GAP-libnameopt) — re-reporting here would double-count.
                const nl = try parseLibnames(a, null, toks[seg.start..seg.end]);
                for (nl.items) |lr| try rebindLibref(ctx, lr);
            }
            try handleGlobal(a, ctx.globals, ctx.diags, toks[seg.start..seg.end]);
        } else if (seg.bad) {
            // BUG-opencodestmtswallow: the unrecognized open-code statement,
            // reported LOUD in source position — steps BEFORE it ran; this .err
            // then errhalt-skips every later step (BUG-errhalt), matching SAS
            // batch (ERROR 180-322 → syntax-check mode).
            const bt = toks[seg.start];
            if (eqi(bt.text, "missing") and (seg.start + 1 >= seg.end or toks[seg.start + 1].tag != .eq)) {
                // BUG-missingstmtwrongclass: the MISSING statement (Language Reference: Concepts printed
                // p.519, a worked example shown TWICE) is VALID SAS opensas
                // doesn't implement → a named gap, rc 2 (D-009/D-009b(i)) — not
                // "your SAS is not valid in open code" rc 1. Same message as
                // parser.zig's DATA-step arm (D-009b corollary: the twin
                // settles by internal consistency). `missing = 5;` keeps the
                // generic open-code error (the `=` guard).
                sas.diag.markGap();
                try ctx.diags.report(.err, bt.line, "the MISSING statement (special missing values) is not supported", .{});
            } else {
                try ctx.diags.report(.err, bt.line, "statement {s} is not valid in open code (or it is used out of proper order)", .{bt.text});
            }
        } else if (seg.endsas) {
            // BUG-endsasexit: ENDSAS terminates the session NORMALLY (Language Reference: Concepts
            // p.10/p.487 step boundary) — stop reading input, keep the exit
            // code whatever the steps before it earned (0 on a clean run).
            // Later segments in this slice were never even scanned; later
            // chunks and the CALL EXECUTE queue check ctx.ended below.
            ctx.ended = true;
            break;
        } else if (ctx.diags.hasStepErrors()) {
            // Syntax-check mode (BUG-errhalt): after any STEP ERROR, later
            // DATA/PROC steps are skipped — real SAS batch behavior. A truncated
            // intermediate must not flow on into a plausible-looking clinical
            // dataset (a real MH run wrote 310 wrong obs to TARGET; CLIN-failloud).
            try ctx.diags.note(0, "The SAS System stopped processing this step because of errors", .{});
        } else {
            const step_toks = try sas.macro.bindStepVars(a, toks[seg.start..seg.end], &ctx.lib.macro_vars, ctx.diags);
            // PROC COPY runs here, not in runProc: it needs the CURRENT libref
            // bindings and Io to write through them eagerly (GAP-proccopy).
            if (step_toks.len > 1 and eqi(step_toks[0].text, "proc") and eqi(step_toks[1].text, "copy")) {
                try runProcCopy(ctx, step_toks);
            } else try runStep(a, ctx.out, ctx.lib, ctx.diags, step_toks, ctx.globals, ctx.io);
        }
    }
    // CALL EXECUTE drain (FEAT-callexecute): the current step(s) finished — now
    // run the program text CALL EXECUTE queued, FIFO. Queued code may itself
    // CALL EXECUTE (appends to the same queue), so pop-and-run until empty.
    // ponytail: recursion depth = queue chain length (each nested runExpanded
    // drains the rest); fine for realistic call-execute fan-out, convert to a
    // flat worklist if a program ever queues thousands of fragments.
    // Queued fragments are GENERATED text, not a source chunk — keep their
    // fragment-relative lines rather than shifting them into this chunk's
    // source range (pre-existing behavior). Save/restore: this runExpanded may
    // itself be an interleaveStep flush mid-chunk, and the chunk's later steps
    // still need the offset.
    const saved_off = ctx.line_off;
    ctx.line_off = 0;
    while (ctx.lib.execute_queue.items.len > 0) {
        if (ctx.ended) break; // ENDSAS ended the session: queued code never runs
        const qtext = ctx.lib.execute_queue.orderedRemove(0);
        try runExpanded(ctx, qtext, false);
    }
    ctx.line_off = saved_off;
    var mit = ctx.lib.macro_vars.iterator();
    while (mit.next()) |e| try ctx.session.seedVar(e.key_ptr.*, e.value_ptr.*);
}

/// Callback invoked from macro expansion at each `run;`/`quit;` boundary. The
/// macro buffer is cleared+reused after we return, so dupe the text (tokens and
/// dataset metadata may hold slices into it). Lex/parse/exec errors are already
/// recorded in `diags` (→ non-zero exit); swallow them so expansion continues.
fn interleaveStep(ctx_ptr: *anyopaque, text: []const u8) std.mem.Allocator.Error!void {
    const ctx: *StepCtx = @ptrCast(@alignCast(ctx_ptr));
    if (ctx.ended) return; // ENDSAS ended the session (BUG-endsasexit)
    const owned = try ctx.a.dupe(u8, text);
    runExpanded(ctx, owned, false) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // BUG-sqlerrorswallow: swallowing here lets macro expansion continue to
        // the next run;/quit; boundary — safe ONLY because the error path is
        // supposed to have recorded a located diagnostic first (→ non-zero exit).
        // Some paths break that invariant: PROC SQL's select-list column resolver
        // returns error.ParseError with NO diag (sql.zig resolveCol …orelse return),
        // so a SELECT of a non-existent column silently skipped the proc and exited
        // 0. If nothing was recorded, surface the error loudly so it can't hide.
        else => if (!ctx.diags.hasErrors()) {
            // GAP-gapsexitingone §5d: an error with NO diagnostic is OUR defect,
            // never the user's — the CLI surface of this same invariant
            // (runFile's `failLoud("{t}")`, audit §2 row 67) already exits 2, and
            // the D-009b corollary settles the twin by internal consistency alone.
            // The report is still swallowed for macro continuation, as before.
            sas.diag.markGap();
            try ctx.diags.report(.err, 0, "step ended with an unreported error ({t}) and was skipped", .{e});
        },
    };
}

const Libref = struct { name: []const u8, dir: []const u8, readonly: bool };

/// GAP-ebnfrcwrongclass: DOCUMENTED LIBNAME statement options that real SAS
/// 9.4 runs clean but opensas does not implement — the rc-2 subset of the
/// catch-all below (the message already NAMES the option; only the class
/// moves, same shape as proc.zig's isFreqTablesGapOption split). Members,
/// each with its printed-page citation:
///   INENCODING= / OUTENCODING= — Procedures Guide `=== pdf 582/583 ===`
///     (printed pp. 532-533): the CVP example's own
///     `LIBNAME outlib 'SAS-library' outencoding="…";` is shown in the log
///     assigned CLEAN on "Engine: V9"; Table 17.9 (COPY) names both as
///     LIBNAME options. opensas does no transcoding → named gap.
///   CVPMULTIPLIER= — Procedures Guide printed p.1566 (`=== pdf 1616 ===`):
///     "read about the CVPMULTIPLIER= option" — the CVP family's LIBNAME
///     option; real SAS runs it clean (it implies the CVP engine).
/// NOT members: plain `cvp=` (the tick431 row's premise — the docs document
/// the CVP ENGINE, Statements Ref printed p.221, which the engine arm above
/// already gaps; no `CVP=` LIBNAME OPTION exists in the docs, so it keeps the
/// typo class), and the open-ended SAS/ACCESS engine-option set
/// (audit-exitcodecontract.md:653 — an unlicensed real SAS rejects those too,
/// never a false rc 2).
fn isDocLibnameGapOpt(opt: []const u8) bool {
    inline for (.{ "inencoding", "outencoding", "cvpmultiplier" }) |o|
        if (eqi(opt, o)) return true;
    return false;
}

/// Collect `libname NAME "dir" [access=readonly];` declarations. These sit at
/// the top level (before the first data/proc step), so the step loop skips them.
/// Collect `libname NAME "dir" [access=readonly];` declarations. These sit at
/// statement level but bind session-wide, so they're collected in a pre-pass.
/// `diags` is non-null ONLY at the whole-program pre-pass (GAP-libnameopt):
/// the option-list validation fires THERE — once per program over the fully
/// expanded source — never in the segment re-bind (which passes null, so an
/// executed libname isn't double-reported) and never in the statement loops
/// (they keep skipping LIBNAME per isMidStepSkippable, D-014a — BUG-libnamemidstepboth).
fn parseLibnames(a: std.mem.Allocator, diags: ?*sas.diag.Diagnostics, toks: []const Token) !std.ArrayList(Libref) {
    var list: std.ArrayList(Libref) = .empty;
    for (toks, 0..) |t, i| {
        const boundary = i == 0 or toks[i - 1].tag == .semicolon;
        if (!(boundary and t.tag == .name and eqi(t.text, "libname"))) continue;
        if (i + 2 >= toks.len or toks[i + 1].tag != .name) continue; // libref name
        // The path string may be preceded by an engine keyword: `libname x [xport] "…"`.
        var pi = i + 2;
        while (pi < toks.len and toks[pi].tag != .semicolon and toks[pi].tag != .string) pi += 1;
        if (pi >= toks.len or toks[pi].tag != .string) continue;
        // NOTE-libnameengine (D-015 silent superset): the engine keyword used
        // to be accepted and SKIPPED — member format is sniffed from the file
        // extension, so `libname t boguseng "x";` ran CLEAN where SAS errors
        // "The BOGUSENG engine cannot be found." Allowlist = the engines for
        // the formats opensas implements: BASE and its documented alias V9
        // (native dir/.sas7bdat — "V9 is an alias for the BASE engine",
        // Procedures Guide p.1032) and XPORT (transport files — "use the XPORT
        // keyword to specify the XPORT engine", Procedures Guide p.531).
        // Engines the doc names but opensas does NOT implement (CVP/JMP/JSON/
        // WebDAV — Statements Ref p.221 stubs — XML, SPDE, ORACLE, …) are
        // REJECTED AT THE STATEMENT, not accepted-and-failed-later: the engine
        // slot is advisory today (format comes from the extension), so there
        // IS no later loud point — deferring is the same silent swallow.
        if (pi > i + 2 and toks[i + 2].tag == .name) {
            const eng = toks[i + 2].text;
            if (!eqi(eng, "base") and !eqi(eng, "v9") and !eqi(eng, "xport")) {
                if (diags) |d| {
                    // GAP-gapsexitingone §5d SPLIT: a DOCUMENTED base engine
                    // opensas does not implement (the list above: JSON/XML/SPDE/
                    // CVP/JMP/WebDAV) is a gap — real SAS 9.4 finds the engine
                    // and runs — so rc 2 with a message that says "not
                    // supported"; "cannot be found" mis-describes it and rc 1
                    // would tell the agent to fix valid SAS. An UNKNOWN name
                    // (a typo, or a SAS/ACCESS engine an unlicensed SAS also
                    // rejects — ORACLE degrades here, never a false rc 2) keeps
                    // SAS's own rc-1 wording.
                    if (isDocLibEngine(eng)) {
                        sas.diag.markGap();
                        try d.report(.err, toks[i + 2].line, "LIBNAME engine {s} is not supported (BASE/V9/XPORT only)", .{eng});
                    } else {
                        try d.report(.err, toks[i + 2].line, "The {s} engine cannot be found.", .{eng});
                    }
                }
            }
        }
        var readonly = false;
        // GAP-libnameopt: the option list AFTER the path string gains a real
        // final else. It used to be one scan for the bare WORD "readonly"
        // anywhere before the `;` — so `libname x "p" bogusopt=1;` ran clean
        // (the audit probe) and a typo'd `acces=readonly` silently LEFT THE
        // LIB UNPROTECTED (it did match the value word, hiding the typo).
        // Classes (SAS 9.4 Language Reference, LIBNAME statement):
        //   ACCESS=READONLY — HONOURED: writes to the lib error "read-only
        //     library" (GH#15, audit probe); ACCESS=TEMP accepted (read-write).
        //   COMPRESS= / REUSE= — INERT: on-disk storage properties a reader
        //     is transparent to; opensas holds datasets in memory and writes
        //     csv/xpt through its own drivers, uncompressed either way.
        //   INENCODING=/OUTENCODING=/CVPMULTIPLIER= — DOCUMENTED, clean in
        //     real SAS, unimplemented here → NAMED rc-2 gap (isDocLibnameGapOpt).
        //   anything else — a typo or an unfiled engine option → LOUD at rc 1,
        //     naming it.
        var j = pi + 1;
        while (j < toks.len and toks[j].tag != .semicolon) {
            if (toks[j].tag == .name and eqi(toks[j].text, "access") and
                j + 2 < toks.len and toks[j + 1].tag == .eq and toks[j + 2].tag == .name)
            {
                const v = toks[j + 2].text;
                if (eqi(v, "readonly")) {
                    readonly = true;
                } else if (eqi(v, "temp")) {
                    // accepted — behaves read-write (audit probe)
                } else if (diags) |d| {
                    try d.report(.err, toks[j].line, "Invalid value for the ACCESS= LIBNAME option.", .{});
                }
                j += 3;
            } else if (toks[j].tag == .name and (eqi(toks[j].text, "compress") or eqi(toks[j].text, "reuse")) and
                j + 2 < toks.len and toks[j + 1].tag == .eq and toks[j + 2].tag == .name)
            {
                j += 3; // INERT storage-property pair, per the header comment
            } else {
                if (diags) |d| {
                    // The documented-but-unimplemented set is OUR gap (rc 2,
                    // D-009/D-009b(i)) — a user running valid SAS must not be
                    // told their code is broken; the byte-identical message
                    // already NAMES the option. Typos and unfiled engine
                    // options keep rc 1 (never a false rc 2).
                    if (isDocLibnameGapOpt(toks[j].text)) sas.diag.markGap();
                    try d.report(.err, toks[j].line, "LIBNAME option {s} is not supported", .{toks[j].text});
                }
                // one ERROR per statement (SAS shape) — skip the rest of THIS
                // libname; the pass still collects later librefs.
                while (j < toks.len and toks[j].tag != .semicolon) j += 1;
            }
        }
        try list.append(a, .{ .name = toks[i + 1].text, .dir = try normalizeSeps(a, toks[pi].text), .readonly = readonly });
    }
    return list;
}

/// GH#34 ISS-fmtcatalog: for each `OPTIONS FMTSEARCH=` libref, read a
/// `formats.sas7bcat` catalog from its directory and append its VALUE-format
/// definitions to the catalog `format.apply` consults — so `put(x, WORKSHOP.)`
/// decodes a label instead of failing loud. Mirrors PROC FORMAT's install
/// (proc.zig runFormat) so in-program and catalog formats coexist.
/// ponytail: probes only the explicit FMTSEARCH list and only the default
/// `formats.sas7bcat` member — SAS's implicit WORK/LIBRARY search order and named
/// `lib.catalog` members aren't (the corpus always names the libref explicitly).
fn loadFmtCatalogs(a: std.mem.Allocator, toks: []const Token, librefs: []const Libref) !void {
    const refs = try parseFmtSearch(a, toks);
    if (refs.len == 0) return;
    var cats: std.ArrayList(sas.format.UserFmt) = .empty;
    for (refs) |name| {
        const lr = findLibref(librefs, name) orelse continue;
        // A libref bound straight at a `.sas7bcat` file, else `<dir>/formats.sas7bcat`.
        const path = if (sas.io.endsWithIgnoreCase(lr.dir, ".sas7bcat"))
            lr.dir
        else
            try std.fmt.allocPrint(a, "{s}/formats.sas7bcat", .{lr.dir});
        const bytes = sas.io.readFileRaw(a, path) orelse continue; // no catalog there
        const ufs = sas.sas7bcat.read(a, bytes) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            // A present-but-unparseable catalog is an opensas gap — fail loud.
            else => {
                failLoud("cannot load format catalog {s} ({t})", .{ path, e });
                continue;
            },
        };
        try cats.appendSlice(a, ufs);
    }
    if (cats.items.len == 0) return;
    // Append to (not clobber) any already-installed formats.
    const existing = sas.format.userFormats();
    if (existing.len == 0) {
        sas.format.setUserFormats(try cats.toOwnedSlice(a));
    } else {
        var merged: std.ArrayList(sas.format.UserFmt) = .empty;
        try merged.appendSlice(a, existing);
        try merged.appendSlice(a, cats.items);
        sas.format.setUserFormats(try merged.toOwnedSlice(a));
    }
}

/// Parse the librefs from `OPTIONS FMTSEARCH=(LIB1 LIB2 …)` (or bare
/// `FMTSEARCH=LIB`). A `lib.catalog` two-level entry contributes its libref.
fn parseFmtSearch(a: std.mem.Allocator, toks: []const Token) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (!(toks[i].tag == .name and eqi(toks[i].text, "fmtsearch"))) continue;
        var j = i + 1;
        if (j < toks.len and toks[j].tag == .eq) j += 1;
        if (j < toks.len and toks[j].tag == .lparen) {
            j += 1;
            while (j < toks.len and toks[j].tag != .rparen and toks[j].tag != .semicolon) : (j += 1) {
                if (toks[j].tag == .name) try list.append(a, toks[j].text);
                // skip a `.catalog` suffix on a two-level entry
                if (j + 2 < toks.len and toks[j + 1].tag == .dot and toks[j + 2].tag == .name) j += 2;
            }
        } else if (j < toks.len and toks[j].tag == .name) {
            try list.append(a, toks[j].text);
        }
    }
    return list.toOwnedSlice(a);
}

/// Windows-authored study programs bind librefs with `\` separators
/// (`"&XPT.\ae.xpt"` — GAP-proccopy); normalize so unix file ops see a real path.
fn normalizeSeps(a: std.mem.Allocator, p: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, p, '\\') == null) return p;
    const q = try a.dupe(u8, p);
    for (q) |*c| {
        if (c.* == '\\') c.* = '/';
    }
    return q;
}

/// (Re)mirror the libref map into dsfns, so EXIST/OPEN/PATHNAME disk probes
/// and the VTABLE sweep see the CURRENT bindings. Empty when there is no Io.
fn bindDiskRefs(a: std.mem.Allocator, librefs: []const Libref, has_io: bool) !void {
    const refs = try a.alloc(sas.functions.DiskLibref, if (has_io) librefs.len else 0);
    for (refs, 0..) |*d, i| d.* = .{ .name = librefs[i].name, .dir = librefs[i].dir };
    sas.functions.bindLibrefs(refs);
}

/// GH#15: mirror the current read-only librefs into the Library, so `put`'s
/// output-access guard knows which two-level members reject creation/replacement.
/// Re-run whenever librefs change (initial parse + each runtime `libname`).
fn syncReadonlyRefs(a: std.mem.Allocator, lib: *sas.exec.Library, librefs: []const Libref) !void {
    var ro: std.ArrayList([]const u8) = .empty;
    for (librefs) |lr| if (lr.readonly) try ro.append(a, lr.name);
    lib.readonly_refs = ro.items;
}

/// Apply one runtime `libname` statement: update the existing entry in place
/// (findLibref is first-match, so the slot must be REPLACED, not shadowed) or
/// append a brand-new libref, then re-mirror into dsfns either way.
fn rebindLibref(ctx: *StepCtx, lr: Libref) !void {
    blk: {
        for (ctx.librefs.items) |*old_ref| if (eqi(old_ref.name, lr.name)) {
            old_ref.* = lr;
            break :blk;
        };
        try ctx.librefs.append(ctx.a, lr);
    }
    try bindDiskRefs(ctx.a, ctx.librefs.items, ctx.io != null);
    try syncReadonlyRefs(ctx.a, ctx.lib, ctx.librefs.items); // GH#15: readonly may flip at runtime
}

/// `proc copy in=LIB out=LIB [memtype=data]; select m1 m2 …; run;` — the SDTM
/// XPT-export idiom (GAP-proccopy): `libname xptfile XPORT "…&member..xpt";
/// proc copy in=sasfile out=xptfile; select <member>;` per %do iteration. Each
/// selected member is written through the out= binding CURRENT at this step
/// (the per-iteration re-bind is the whole point — the end-of-run pass only
/// sees the last one). ponytail: disk-write only, the member is not registered
/// in-memory under `out.m` — a later read finds it on disk through the normal
/// libref loader. EXCLUDE / bare COPY without SELECT fail loud.
fn runProcCopy(ctx: *StepCtx, toks: []const Token) sas.diag.Error!void {
    const a = ctx.a;
    var in_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    // options on the PROC COPY statement itself: `in=A out=B [memtype=data]`
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
        if (toks[i].tag != .name or i + 2 >= toks.len or toks[i + 1].tag != .eq) continue;
        if (eqi(toks[i].text, "in")) {
            in_name = toks[i + 2].text;
        } else if (eqi(toks[i].text, "out")) {
            out_name = toks[i + 2].text;
        } else if (!eqi(toks[i].text, "memtype") and !eqi(toks[i].text, "mt")) {
            failLoud("PROC COPY option {s} is not supported", .{toks[i].text});
            return;
        }
        i += 2;
    }
    // statements until run/quit: only SELECT (member names) is supported
    var members: std.ArrayList([]const u8) = .empty;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag == .semicolon) continue;
        if (toks[i].tag != .name or eqi(toks[i].text, "run") or eqi(toks[i].text, "quit")) break;
        if (!eqi(toks[i].text, "select")) {
            failLoud("PROC COPY statement {s} is not supported", .{toks[i].text});
            return;
        }
        i += 1;
        while (i < toks.len and toks[i].tag == .name) : (i += 1)
            try members.append(a, toks[i].text);
        if (i < toks.len and toks[i].tag != .semicolon) {
            failLoud("PROC COPY SELECT supports plain member names only", .{});
            return;
        }
    }
    // DEC-abortrcvsD009: these three are USER errors (rc 1), not gaps (rc 2) —
    // opensas implements `in=/out=/select`, and real SAS errors on all three too
    // ("The IN= option must be specified", "Libref X is not assigned", "File
    // LIB.MEM.DATA does not exist"). The mirror of 321b444e's reductio applies to
    // the unbound libref: "we might have failed to bind a libref we should have"
    // cannot demote it, or every user error would be a suspected opensas defect
    // and rc 1 would be unreachable.
    const in_lib = in_name orelse {
        userErr(ctx.diags, "PROC COPY requires in=", .{});
        return;
    };
    const out_lr = findLibref(ctx.librefs.items, out_name orelse "") orelse {
        userErr(ctx.diags, "PROC COPY out= libref is not bound", .{});
        return;
    };
    if (members.items.len == 0) {
        // ponytail: whole-library COPY needs a disk sweep of in=; add when a study uses it
        failLoud("PROC COPY without SELECT is not supported", .{});
        return;
    }
    const iov = ctx.io orelse {
        failLoud("PROC COPY needs file io", .{});
        return;
    };
    for (members.items) |m| {
        const full = try std.fmt.allocPrint(a, "{s}.{s}", .{ in_lib, m });
        if (ctx.lib.find(full) == null) {
            // disk-only member (the XPT idiom copies goldens never SET in memory)
            const t = [_]Token{.{ .tag = .name, .text = full, .line = toks[0].line }};
            try loadLibInputs(a, iov, ctx.lib, ctx.librefs.items, &t, ctx.loaded_ro, ctx.damaged, ctx.diags);
        }
        // in=work members are single-level names in the library
        const ds = ctx.lib.find(full) orelse (if (eqi(in_lib, "work")) ctx.lib.find(m) else null) orelse {
            // Same condition exec.zig reports at rc 1 as `File {s} does not exist`.
            userErr(ctx.diags, "PROC COPY: {s} not found", .{full});
            return;
        };
        try writeMember(a, iov, out_lr, m, ds);
    }
}

fn findLibref(librefs: []const Libref, name: []const u8) ?Libref {
    for (librefs) |lr| if (eqi(lr.name, name)) return lr;
    return null;
}

/// Fold `<libref> . <name>` runs into a single `libref.name` token so downstream
/// parsing treats a two-level dataset name as one ordinary name.
fn coalesceLibrefs(a: std.mem.Allocator, toks: []const Token, librefs: []const Libref) ![]Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        // Fold `<libref>.<name>` for a declared libref, and also the implicit
        // `work.<name>` (WORK is the default library) — BUG-twolevelread.
        if (i + 2 < toks.len and toks[i].tag == .name and toks[i + 1].tag == .dot and
            toks[i + 2].tag == .name and (findLibref(librefs, toks[i].text) != null or eqi(toks[i].text, "work")))
        {
            const text = try std.fmt.allocPrint(a, "{s}.{s}", .{ toks[i].text, toks[i + 2].text });
            try out.append(a, .{ .tag = .name, .text = text, .line = toks[i].line });
            i += 3;
        } else {
            try out.append(a, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Split a two-level `libref.dataset` name; null if it isn't one.
fn splitTwoLevel(librefs: []const Libref, name: []const u8) ?struct { lr: Libref, ds: []const u8 } {
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return null;
    const lr = findLibref(librefs, name[0..dot]) orelse return null;
    return .{ .lr = lr, .ds = name[dot + 1 ..] };
}

/// Read every input `libref.dataset` referenced (not the `data <libref.x>`
/// target) from its `dir/dataset.csv` into the Library, so `set`/`merge` find it.
/// A MISSING member file stays silent here — SET's "File X does not exist" is
/// then truthful. A PRESENT-but-unreadable member (truncated/damaged sas7bdat/
/// xpt) is reported ONCE at the referencing token's line, naming the real cause
/// (NOTE-truncreadmsg), recorded in `damaged` so later passes neither re-read
/// nor re-report it, and the .err trips syntax-check mode before the step runs
/// — the misleading downstream "does not exist" never prints.
fn loadLibInputs(a: std.mem.Allocator, io: Io, lib: *sas.exec.Library, librefs: []const Libref, toks: []const Token, loaded_ro: *std.ArrayList(*sas.dataset.Dataset), damaged: *std.StringHashMap(void), diags: *sas.diag.Diagnostics) !void {
    for (toks, 0..) |t, i| {
        if (t.tag != .name) continue;
        const two = splitTwoLevel(librefs, t.text) orelse continue;
        if (i > 0 and toks[i - 1].tag == .name and eqi(toks[i - 1].text, "data")) continue; // output target
        if (lib.find(t.text) != null) continue; // already loaded / created
        if (damaged.contains(t.text)) continue; // already reported — no re-read, no re-report

        // A libref pointed straight at a dataset FILE (not a directory): every
        // member name maps to that one file. Read the file itself by extension.
        // (QA: `libname s "real.sas7bdat"; set s.x;` must load real rows — before
        // this it built `real.sas7bdat/x.sas7bdat`, missed, and no-op'd exactly
        // like a bogus path.)
        if (sas.io.endsWithIgnoreCase(two.lr.dir, ".sas7bdat") or sas.io.endsWithIgnoreCase(two.lr.dir, ".xpt")) {
            if (Io.Dir.cwd().readFileAlloc(io, two.lr.dir, a, max_file)) |bytes| {
                // BUG-filelibrefmember (F6): the file holds ONE member — serve it
                // only under the name stamped in it (XPT DSCRPTR) or, for
                // sas7bdat, its filename stem. A mismatch skips the load, so the
                // referencing SET fails loud ("File X does not exist") exactly
                // like any absent member — a typo'd name no longer silently
                // reads the wrong dataset. An XPT stamp truncates to 8 chars, so
                // a longer request also matches on its first 8.
                const held = sas.io.stampedMemberName(two.lr.dir, bytes);
                const name_ok = eqi(two.ds, held) or
                    (two.ds.len > 8 and held.len == 8 and eqi(two.ds[0..8], held));
                if (name_ok) {
                    if (sas.io.readByExt(a, two.lr.dir, bytes, t.text)) |maybe| {
                        if (maybe) |ds| {
                            // F9-sidecar: apply a sibling `.labels` sidecar (the
                            // file's stem + .labels) exactly as the directory
                            // path does — labels/formats/informats survive a
                            // FILE-libref read too.
                            const dot = std.mem.lastIndexOfScalar(u8, two.lr.dir, '.') orelse two.lr.dir.len;
                            const lpath = try std.fmt.allocPrint(a, "{s}{s}", .{ two.lr.dir[0..dot], sas.io.label_ext });
                            if (Io.Dir.cwd().readFileAlloc(io, lpath, a, max_file)) |lb| {
                                try sas.io.applyLabelSidecar(a, ds, lb);
                            } else |_| {}
                            try lib.putInput(t.text, ds); // GH#15: preloading a readonly INPUT is a legal read
                            try loaded_ro.append(a, ds);
                        }
                    } else |e| switch (e) {
                        error.OutOfMemory => return error.OutOfMemory,
                        // NOTE-truncreadmsg: a PRESENT but unreadable member
                        // (truncated/damaged sas7bdat/xpt) was swallowed here
                        // and surfaced downstream as "File X does not exist" —
                        // the file plainly DOES exist. Name the real problem
                        // once (shape matches "cannot load format catalog"
                        // above); the .err errhalt-skips the referencing step.
                        else => {
                            try diags.report(.err, t.line, "cannot load {s} ({t}): the file exists but is damaged or truncated", .{ two.lr.dir, e });
                            try damaged.put(t.text, {});
                        },
                    }
                }
            } else |_| {}
            continue;
        }

        // Directory libref: discover the member file by name, auto-picking the
        // engine from its extension (`dir/member.csv|.xpt|.sas7bdat`).
        for (sas.io.member_exts) |ext| {
            const path = try std.fmt.allocPrint(a, "{s}/{s}{s}", .{ two.lr.dir, two.ds, ext });
            const bytes = Io.Dir.cwd().readFileAlloc(io, path, a, max_file) catch continue;
            if (sas.io.readByExt(a, path, bytes, t.text)) |maybe| {
                if (maybe) |ds| {
                    // apply the `.labels` sidecar written alongside the data, if any
                    const lpath = try std.fmt.allocPrint(a, "{s}/{s}{s}", .{ two.lr.dir, two.ds, sas.io.label_ext });
                    if (Io.Dir.cwd().readFileAlloc(io, lpath, a, max_file)) |lb| {
                        try sas.io.applyLabelSidecar(a, ds, lb);
                    } else |_| {}
                    try lib.putInput(t.text, ds); // GH#15: preloading a readonly INPUT is a legal read
                    try loaded_ro.append(a, ds); // read-only input — not re-written unless replaced
                    break;
                }
            } else |e| switch (e) {
                error.OutOfMemory => return error.OutOfMemory,
                // NOTE-truncreadmsg (as above): report the present-but-damaged
                // member and STOP probing — falling through to a stale .csv
                // sidecar would silently read superseded data (D-002).
                else => {
                    try diags.report(.err, t.line, "cannot load {s} ({t}): the file exists but is damaged or truncated", .{ path, e });
                    try damaged.put(t.text, {});
                    break;
                },
            }
        }
    }
}

/// Write every dataset in a writable libref: an XPORT libref → `.xpt`; a directory
/// libref → native `.sas7bdat` (AUTHORITATIVE on reload — preserves variable
/// type/length, E-sas7write-hookup) PLUS a `.csv` sidecar (diff-friendly / legacy;
/// ignored on reload when the `.sas7bdat` is present). `.labels` sidecar as before.
/// Whether `ds` should be written back to disk. A read-only-loaded input that was
/// never replaced (same object pointer as when loaded) is NOT persisted — writing
/// it back dirties the input dir and a generated `.sas7bdat` would shadow an edited
/// `.csv` on the next read. A step that re-creates the name via `lib.put` installs a
/// NEW object, so it's absent from `loaded_ro` → persisted (E-sas7write-noreadback).
fn shouldPersist(ds: *sas.dataset.Dataset, loaded_ro: []const *sas.dataset.Dataset) bool {
    return std.mem.indexOfScalar(*sas.dataset.Dataset, loaded_ro, ds) == null;
}

fn writeLibOutputs(a: std.mem.Allocator, io: Io, lib: *sas.exec.Library, librefs: []const Libref, loaded_ro: []const *sas.dataset.Dataset) !void {
    for (lib.names.items, 0..) |nm, i| {
        const two = splitTwoLevel(librefs, nm) orelse continue;
        if (two.lr.readonly) continue;
        // A dataset only READ from a directory libname (same object as loaded, never
        // replaced by a `data lib.x;`) is not persisted — writing it back is stray
        // churn that shadows an edited source (E-sas7write-noreadback).
        if (!shouldPersist(lib.sets.items[i], loaded_ro)) continue;
        try writeMember(a, io, two.lr, two.ds, lib.sets.items[i]);
    }
}

/// Write ONE member through a libref binding. Shared by end-of-run
/// writeLibOutputs and the eager PROC COPY path (GAP-proccopy), which must
/// write through the binding CURRENT at copy time — the end-of-run pass only
/// sees the libref's FINAL binding.
fn writeMember(a: std.mem.Allocator, io: Io, lr: Libref, ds_name: []const u8, ds: *sas.dataset.Dataset) sas.diag.Error!void {
    // `libname o xport "f.xpt"` writes the member out as XPORT v5 to that file
    // (CLIN-xptwrite). ONE member per .xpt (multi-member append unsupported —
    // F7(a)): before overwriting an existing file, compare the member stamped
    // in it and REFUSE LOUDLY (D-002) when it differs — the old behavior
    // silently destroyed the first dataset with a clean exit code. Re-writing
    // the SAME member (or its ≤8-char stamp prefix) is a legal replace.
    if (sas.io.endsWithIgnoreCase(lr.dir, ".xpt")) {
        if (Io.Dir.cwd().readFileAlloc(io, lr.dir, a, max_file)) |old| {
            if (sas.io.xptStampedMember(old)) |held| {
                const same = eqi(held, ds_name) or
                    (ds_name.len > 8 and held.len == 8 and eqi(ds_name[0..8], held));
                if (!same) {
                    failLoud("XPORT: {s} already holds member {s} — one member per transport file is supported; use a separate .xpt path per member (member {s} NOT written, {s} preserved)", .{ lr.dir, held, ds_name, held });
                    return;
                }
            }
        } else |_| {}
        // the XPT member header carries the dataset name (≤8): stamp the BARE
        // member name, not a two-level `libref.member` (truncates to `libref.m`
        // — Pinnacle 21 keys the define.xml match on it).
        var named = ds.*;
        named.name = ds_name;
        const bytes = sas.io.writeXport(a, &named) catch |e| switch (e) {
            error.OutOfMemory => return error.OutOfMemory,
            error.NotXport => { // reader-side tag; the writer can't hit it, but fail loud if it ever does
                failLoud("XPORT write of {s} failed", .{ds_name});
                return;
            },
        };
        // A real XPT-export macro makes the target dir via `X mkdir` — a no-op
        // global here — so create the parent ourselves.
        if (std.fs.path.dirname(lr.dir)) |parent| Io.Dir.cwd().createDirPath(io, parent) catch {};
        Io.Dir.cwd().writeFile(io, .{ .sub_path = lr.dir, .data = bytes }) catch {};
        return;
    }
    // A `.sas7bdat` libref is a read-only source (no member path): skip.
    if (sas.io.endsWithIgnoreCase(lr.dir, ".sas7bdat")) return;
    // Don't shadow an `.xpt` source we read from (BUG-csvshadow): the loader
    // prefers binaries, so writing next to a `dir/member.xpt` would stop
    // exercising the XPORT reader on the next run.
    const xpt = try std.fmt.allocPrint(a, "{s}/{s}.xpt", .{ lr.dir, ds_name });
    if (Io.Dir.cwd().access(io, xpt, .{})) |_| return else |_| {}

    Io.Dir.cwd().createDirPath(io, lr.dir) catch {};
    // E-sas7write-hookup: persist a directory-LIBNAME member as native
    // `.sas7bdat` — the AUTHORITATIVE reload format (io.member_exts prefers it),
    // so variable type/length survive a TARGET reload that CSV re-guessed
    // (META-fidelity: all-digit char '007' stays Char, not re-typed Num). The
    // `.csv` is still written as a diff-friendly / legacy sidecar (the program
    // fixtures structural-diff it, and it stays human-readable); it is ignored
    // on reload whenever the `.sas7bdat` is present.
    const s7bytes = sas.io.writeSas7bdat(a, ds) catch |e| switch (e) {
        error.OutOfMemory => return error.OutOfMemory,
        // GAP-xport0colskip: a 0-variable dataset has NO writable .sas7bdat
        // shape — read() itself refuses ncol==0 (a file we'd reject on
        // reload) and no real-file 0-column layout evidence exists.
        //
        // SEV-zerocolrefusal re-litigated the severity and KEPT exit 2. The
        // Macro Language Ref citation (SYSDATASTEPPHASE ex. 2, printed p. 246
        // /pdf 261: "NOTE: The data set WORK.NULL has 1 observations and 0
        // variables.") does NOT conflict, because it is about a WORK set and
        // that exact program already exits 0 here with a correct 1-obs/0-var
        // descriptor — verified by probe. Exit 2 fires only for the strictly
        // LARGER program that also demands a native library write, which p.246
        // never does and no volume describes. D-009 then settles it: the writer
        // returns error.Unsupported, which IS the "UNSUPPORTED feature" gap
        // class, and a gap is 2. Downgrading on "but real SAS exits 0" would
        // make rc=2 unreachable — every gap is by construction valid SAS that
        // real SAS runs clean, so that cannot be the test.
        //
        // The message must NOT promise the CSV rescues it: probed, a 0-column
        // `.csv` was two bytes ("\n\n") and reloaded as ONE PHANTOM `VAR1`
        // column with 0 observations, so the member does not survive the run at
        // all. Claiming otherwise is the silent-wrong-output class house rules
        // put first — which is also why exit 0 + WARNING is wrong here: it would
        // wave a pipeline past real data destruction. BUG-csvzerocolphantom then
        // stopped that file existing: writeCsv REFUSES ncol==0 (CSV cannot
        // encode it — see io.writeCsvImpl) and returns an empty body, which the
        // `text.len > 0` guard below skips exactly as `s7bytes` is skipped here.
        error.Unsupported => blk: {
            failLoud("SAS7BDAT: {s}/{s}.sas7bdat NOT written — a 0-variable data set has no native representation, and CSV cannot encode one either (an empty header row reads back as a phantom column), so NO file is written and this member does NOT survive the run", .{ lr.dir, ds_name });
            break :blk "";
        },
        error.NotSas7bdat, error.Damaged => blk: { // reader-side tags; fail loud if the writer ever raises one
            failLoud("SAS7BDAT write of {s}/{s} failed", .{ lr.dir, ds_name });
            break :blk "";
        },
    };
    if (s7bytes.len > 0) {
        const s7 = try std.fmt.allocPrint(a, "{s}/{s}.sas7bdat", .{ lr.dir, ds_name });
        Io.Dir.cwd().writeFile(io, .{ .sub_path = s7, .data = s7bytes }) catch {};
    }
    const path = try std.fmt.allocPrint(a, "{s}/{s}.csv", .{ lr.dir, ds_name });
    const text = try sas.io.writeCsv(a, ds);
    // BUG-csvzerocolphantom: an empty body means the writer REFUSED (0 variables
    // — CSV has no encoding for it; it reported the gap itself). Skip the write
    // rather than leave a file that reloads as a lie, same shape as `s7bytes`.
    if (text.len > 0) Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text }) catch {};
    // variable labels go in a SEPARATE `.labels` sidecar (the sas7bdat writer
    // carries type/length but not labels/formats yet) — unchanged behavior
    // (BUG-labelspersist); no file is written when nothing is labeled.
    if (try sas.io.labelSidecar(a, ds)) |meta| {
        const lpath = try std.fmt.allocPrint(a, "{s}/{s}{s}", .{ lr.dir, ds_name, sas.io.label_ext });
        Io.Dir.cwd().writeFile(io, .{ .sub_path = lpath, .data = meta }) catch {};
    }
}

/// Indices where a step begins: a `data`/`proc` name token at the very start or
/// right after a `;`, and not the target of an assignment (`data = 1;`).
fn stepStarts(a: std.mem.Allocator, toks: []const Token) ![]usize {
    var list: std.ArrayList(usize) = .empty;
    for (toks, 0..) |t, i| {
        if (t.tag != .name) continue;
        if (!eqi(t.text, "data") and !eqi(t.text, "proc")) continue;
        const at_boundary = i == 0 or toks[i - 1].tag == .semicolon;
        const is_assign = i + 1 < toks.len and toks[i + 1].tag == .eq;
        if (at_boundary and !is_assign) try list.append(a, i);
    }
    return list.toOwnedSlice(a);
}

const Seg = struct { start: usize, end: usize, global: bool, bad: bool = false, endsas: bool = false, hoisted: bool = false };

/// Split the token stream into top-level segments — DATA/PROC steps and global
/// statements (TITLE/FOOTNOTE/OPTIONS/FILENAME/ODS/X) — in order. A step runs to
/// its `run;`/`quit;` (or the next step); a global statement to its `;`. Global
/// keywords that occur *inside* a step (before its run/quit) stay part of it.
/// BUG-opencodestmtswallow: an unrecognized open-code statement no longer falls
/// off the end of the chain silently (a typo'd `titl 'x';` / `libnam raw 'p';`
/// or an unimplemented `endsas;` vanished at exit 0). Three classes, mirroring
/// the OPTIONS fix (BUG-optionsstmtswallow):
///   (a) implemented statements — the two arms below, unchanged;
///   (b) an explicit INERT allowlist (parser.isInertGlobalKw) — real SAS
///       top-level statements a batch interpreter cannot observe, skipped to
///       their `;` (the D-014 lesson: erroring on THOSE kills every real
///       program);
///   (c) anything else — recorded, and when the stream held at least one real
///       segment it becomes a `bad` seg that runExpanded reports LOUD in source
///       position (steps before it ran; the .err errhalt-skips the rest, like
///       SAS batch). With NO real segments the stream keeps the anonymous
///       `data _null_` fallback, which errors on its own terms.
fn isNameByte(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}

/// Split RAW source into chunks at top-level `run;`/`quit;` step boundaries that lie
/// outside %macro/%do blocks and quoted strings, so the CLI can expand+execute one
/// chunk at a time and feed CALL SYMPUT vars forward (BUG-runtimemacroscope).
/// Everything up to and including a step's terminating `;` is one chunk; trailing
/// text is the final chunk.
fn rawSegments(a: std.mem.Allocator, src: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    var i: usize = 0;
    var mdepth: usize = 0; // %macro..%mend
    var ddepth: usize = 0; // %do..%end
    while (i < src.len) {
        const c = src[i];
        if (c == '/' and i + 1 < src.len and src[i + 1] == '*') { // /* … */ comment
            i += 2;
            while (i + 1 < src.len and !(src[i] == '*' and src[i + 1] == '/')) i += 1;
            i = @min(i + 2, src.len);
            continue;
        }
        if (c == '"' or c == '\'') {
            const q = c;
            i += 1;
            while (i < src.len and src[i] != q) i += 1;
            if (i < src.len) i += 1;
            continue;
        }
        if (c == '%' and i + 1 < src.len and (std.ascii.isAlphabetic(src[i + 1]) or src[i + 1] == '_')) {
            var w = i + 1;
            while (w < src.len and isNameByte(src[w])) w += 1;
            const word = src[i + 1 .. w];
            if (eqi(word, "macro")) {
                mdepth += 1;
            } else if (eqi(word, "mend")) {
                if (mdepth > 0) mdepth -= 1;
            } else if (eqi(word, "do")) {
                ddepth += 1;
            } else if (eqi(word, "end")) {
                if (ddepth > 0) ddepth -= 1;
            }
            i = w;
            continue;
        }
        if (mdepth == 0 and ddepth == 0 and (std.ascii.isAlphabetic(c) or c == '_')) {
            var stmt_start = true; // is this word the start of a statement?
            var pb: usize = i;
            while (pb > 0) {
                pb -= 1;
                const pc = src[pb];
                if (pc == ' ' or pc == '\t' or pc == '\n' or pc == '\r') continue;
                stmt_start = (pc == ';');
                break;
            }
            var w = i;
            while (w < src.len and isNameByte(src[w])) w += 1;
            if (stmt_start and (eqi(src[i..w], "run") or eqi(src[i..w], "quit"))) {
                var e = w;
                while (e < src.len and src[e] != ';') e += 1;
                if (e < src.len) e += 1;
                try list.append(a, src[start..e]);
                start = e;
                i = e;
                continue;
            }
            i = w;
            continue;
        }
        i += 1;
    }
    if (start < src.len) try list.append(a, src[start..]);
    if (list.items.len == 0) try list.append(a, src);
    return list.items;
}

/// `strict` is false only for the single-chunk whole-program slice that may
/// fall back to the anonymous `data _null_` run — there an unrecognized
/// statement keeps the fallback (which errors on its own terms). Everywhere
/// else (flushed step boundaries, CALL EXECUTE fragments, later chunks) an
/// unrecognized open-code statement becomes a loud `bad` seg even when the
/// slice held no real segment.
fn segments(a: std.mem.Allocator, toks: []const Token, strict: bool, diags: *sas.diag.Diagnostics) ![]Seg {
    var list: std.ArrayList(Seg) = .empty;
    var unknown: ?usize = null; // first unrecognized open-code statement start
    // D-022 (GH#83 part 2): inert-skipped statements whose form IS observable
    // in batch (DM's FILE/OUT log redirection) — spans collected during the
    // scan, noted at the end (see there).
    var inert: std.ArrayList(Seg) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        const boundary = i == 0 or toks[i - 1].tag == .semicolon;
        if (!boundary or toks[i].tag != .name) {
            i += 1;
            continue;
        }
        const t = toks[i];
        const is_assign = i + 1 < toks.len and toks[i + 1].tag == .eq;
        if ((eqi(t.text, "data") or eqi(t.text, "proc")) and !is_assign) {
            const end = stepEnd(toks, i);
            // F3 (GAP-globalstmtswallow): a TITLE/FOOTNOTE/OPTIONS placed INSIDE
            // a DATA/PROC step is honored by SAS for that step's output (a common
            // TFL idiom). opensas folded them into the step where the proc/data
            // parser silently skips them. Hoist each as its own global segment
            // BEFORE the step so the shared Titles/options state is set before the
            // step renders. The tokens also stay in the step, where they remain
            // harmlessly skipped (the parser's isMidStepSkippable skip).
            // FILENAME/ODS hoist identically (BUG-filenamemidstep): SAS global
            // statements take effect when ENCOUNTERED (step-compile time), i.e.
            // before the step executes — so a hoisted `filename f 'new';`
            // re-binds f before `file f;` runs, exactly SAS's observable order.
            // EXCEPT PROC SQL:
            // it produces MULTIPLE listings interleaved with its own statements
            // and self-stamps titles/footnotes per-SELECT in source order
            // (GAP-titleinsql). Hoisting its mid-step titles to the front would
            // collapse that ordering (a title meant for the 2nd SELECT would hit
            // the 1st), so SQL keeps handling its own.
            const is_sql = eqi(t.text, "proc") and i + 1 < toks.len and eqi(toks[i + 1].text, "sql");
            var k = if (is_sql) end else i + 1;
            var step_end = end;
            var endsas_at: ?usize = null;
            while (k < end) {
                const kb = toks[k - 1].tag == .semicolon and toks[k].tag == .name;
                // BUG-endsasmidstep: ENDSAS is an ordinary step boundary
                // wherever it lands (Language Reference: Concepts p.10/p.487). Mid-step: the step
                // keeps the statements BEFORE it (they run and print), then
                // the session ends NORMALLY — nothing after ENDSAS is even
                // read, same as the open-code arm below. The `=` guard keeps
                // `endsas = 5;` a plain assignment. (PROC SQL self-parses;
                // endsas inside it stays its own concern, like its titles.)
                if (kb and eqi(toks[k].text, "endsas") and (k + 1 >= end or toks[k + 1].tag != .eq)) {
                    step_end = k;
                    endsas_at = k;
                    break;
                }
                if (kb and sas.parser.isHoistedGlobalKw(toks[k].text)) {
                    var j = k;
                    while (j < end and toks[j].tag != .semicolon) j += 1;
                    const gend = if (j < end) j + 1 else j;
                    // .hoisted: the tokens ALSO stay in the step, so the step's
                    // bindStepVars discharges their unresolved-& warnings — the
                    // global-seg discharge skips these or they warn twice.
                    try list.append(a, .{ .start = k, .end = gend, .global = true, .hoisted = true });
                    k = gend;
                } else k += 1;
            }
            try list.append(a, .{ .start = i, .end = step_end, .global = false });
            if (endsas_at) |m| {
                var j = m;
                while (j < toks.len and toks[j].tag != .semicolon) j += 1;
                const eend = if (j < toks.len) j + 1 else j;
                try list.append(a, .{ .start = m, .end = eend, .global = false, .endsas = true });
                break; // ENDSAS: nothing after it is read
            }
            i = end;
        } else if (!is_assign and (sas.parser.isGlobalKw(t.text) or isXStmt(toks, i))) {
            var j = i;
            while (j < toks.len and toks[j].tag != .semicolon) j += 1;
            const end = if (j < toks.len) j + 1 else j;
            try list.append(a, .{ .start = i, .end = end, .global = true });
            i = end;
        } else if (!is_assign and sas.parser.isInertGlobalKw(t.text)) {
            var j = i;
            while (j < toks.len and toks[j].tag != .semicolon) j += 1;
            const end = if (j < toks.len) j + 1 else j;
            try inert.append(a, .{ .start = i, .end = end, .global = true });
            i = end;
        } else if (!is_assign and eqi(t.text, "endsas")) {
            // BUG-endsasexit: ENDSAS is an ordinary step boundary that ends
            // the session NORMALLY (Language Reference: Concepts p.10, p.487) — not an error. Steps
            // before it ran; it stops the scan here, so nothing after it is
            // even read (real ENDSAS semantics; the mid-program case). A
            // trailing `endsas;` is a production idiom and must exit 0.
            var j = i;
            while (j < toks.len and toks[j].tag != .semicolon) j += 1;
            const eend = if (j < toks.len) j + 1 else j;
            try list.append(a, .{ .start = i, .end = eend, .global = false, .endsas = true });
            break;
        } else {
            if (unknown == null) unknown = i;
            i += 1;
        }
    }
    if (unknown) |u| if (strict or list.items.len > 0) {
        var j = u;
        while (j < toks.len and toks[j].tag != .semicolon) j += 1;
        const uend = if (j < toks.len) j + 1 else j;
        var at = list.items.len;
        for (list.items, 0..) |s, k| {
            if (s.start > u) {
                at = k;
                break;
            }
        }
        try list.insert(a, at, .{ .start = u, .end = uend, .global = false, .bad = true });
    };
    // D-022 (BUG-xstmtopencodesplit, GH#83 part 2): the inert skip stays silent
    // for everything a batch run cannot observe — but DM's FILE/OUT log
    // redirection IS observable (a downstream log check reads a file nobody
    // wrote), so it NOTEs, exactly like the mid-step parser arm; the SAME
    // emitter, and the SAME whole-word predicate (`dm 'log;clear;output;clear'`
    // stays silent). Emitted HERE, at the end, and only when this slice produced
    // real segments (or strict mode, where there is no fallback): a slice that
    // is ONLY inert statements falls back to the anonymous `data _null_` run in
    // runExpanded, whose parser arm notes the very same statement — emitting
    // here too would double the NOTE.
    if (strict or list.items.len > 0)
        for (inert.items) |s| try sas.parser.noteUnexecuted(diags, toks[s.start..s.end]);
    return list.items;
}

/// `X <command>;` — the only global whose keyword is a common variable name, so
/// require a command WORD after it (an `x =` / bare `x` is a DATA-step
/// reference). The command may be a quoted string OR bare words (`x mkdir
/// "/tmp/d";` — SAS quotes the command optionally) — the SAME recognizer
/// parser.zig's mid-step x/dm arm runs (BUG-xstmtopencodesplit, GH#83: when the
/// two disagreed, the bare-name form was accepted silently mid-step yet errored
/// "not valid in open code" between steps).
fn isXStmt(toks: []const Token, i: usize) bool {
    return eqi(toks[i].text, "x") and i + 1 < toks.len and
        (toks[i + 1].tag == .string or toks[i + 1].tag == .name);
}

/// End of the DATA/PROC step starting at `from`: the index past its `run;`/`quit;`,
/// else the next step's start, else end-of-tokens.
fn stepEnd(toks: []const Token, from: usize) usize {
    var i = from + 1;
    while (i < toks.len) : (i += 1) {
        if (toks[i - 1].tag != .semicolon or toks[i].tag != .name) continue;
        const w = toks[i].text;
        if ((eqi(w, "run") or eqi(w, "quit")) and i + 1 < toks.len and toks[i + 1].tag == .semicolon)
            return i + 2; // past `run;` / `quit;`
        if (eqi(w, "data") or eqi(w, "proc")) return i; // next step, no run/quit seen
    }
    return toks.len;
}

/// Accumulated TITLE/FOOTNOTE state. Lives in sql.zig (as `sas.sql.Titles`) so
/// PROC SQL — which stamps its own SELECT listings — shares ONE instance with this
/// top-level handler (GAP-titleinsql). The numbered-line/cancel semantics and the
/// stamp order (titles atop a listing, footnotes below) live on the type there.
const Globals = sas.sql.Titles;

/// A top-level global statement. TITLE/FOOTNOTE update the persistent state
/// (emitted later by the listing procs); OPTIONS/FILENAME/ODS/X are accepted and
/// produce no output (opensas: parse + accept) — EXCEPT the ODS sub-statements
/// that change WHAT is produced (SELECT/EXCLUDE/OUTPUT/TRACE), which fail LOUD.
fn handleGlobal(a: std.mem.Allocator, g: *Globals, diags: *sas.diag.Diagnostics, toks: []const Token) !void {
    if (try g.set(a, diags, toks)) return; // TITLE/FOOTNOTE — consumed into the shared state
    const kw = toks[0].text;
    // `X <command>;` in open code — NOT executed (settled, D-022), but no longer
    // SILENT about it: the SAME NOTE the mid-step parser arm emits (GH#83 part
    // 2). The statement used to fall through every chain below to a quiet no-op.
    if (eqi(kw, "x")) return sas.parser.noteUnexecuted(diags, toks);
    // OPTIONS: every token must be a KNOWN option (BUG-optionsstmtswallow).
    // Twelve names were recognized and EVERY other token fell off the chain
    // with no final `else` — `options obbs=2;` (a typo for obs=2) then read
    // EVERY row at exit 0, and `options obs=2k;` silently became obs=2 (the `k`
    // lexes as a separate token and vanished). Three classes below:
    //   (a) RESULT-CHANGING options — honoured here (Language Reference: Concepts citation per arm),
    //       or LOUD as unsupported when honouring lives in the exec layer;
    //   (b) an explicit INERT allowlist (isInertOption) — display/log/session
    //       cosmetics a batch interpreter genuinely cannot observe. The D-014
    //       lesson: erroring on THOSE kills every real program, so they stay
    //       accepted — but ENUMERATED, so the chain has a real final `else`;
    //   everything else is a typo or an unfiled gap → LOUD, naming it.
    if (startsWithI(kw, "options")) {
        var i: usize = 1;
        while (i < toks.len and toks[i].tag != .semicolon) {
            const t = toks[i];
            if (t.tag != .name) {
                try diags.report(.err, t.line, "unexpected token {s} in the OPTIONS statement", .{t.text});
                return;
            }
            // `options nofmterr;` / `options fmterr;` toggles the unknown-format
            // error (BUG-unknownfmtsilent).
            if (eqi(t.text, "nofmterr")) {
                sas.format.setNoFmtErr(true);
                i += 1;
            } else if (eqi(t.text, "fmterr")) {
                sas.format.setNoFmtErr(false);
                i += 1;
            } else if (eqi(t.text, "nonotes")) {
                // `options nonotes;` — suppress log NOTEs (production clinical runs
                // rely on it); `notes` re-enables (F7: was accepted but inert).
                diags.suppress_notes = true;
                i += 1;
            } else if (eqi(t.text, "notes")) {
                diags.suppress_notes = false;
                i += 1;
            } else if (eqi(t.text, "yearcutoff")) {
                // `options yearcutoff=<n>;` — wire the shared YEARCUTOFF span
                // (BUG-yearcutoffstmt: parsed then DROPPED → 2-digit years kept
                // the 1926 default = silent wrong dates). Fail LOUD on garbage.
                const v = if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .number)
                    std.fmt.parseInt(i64, toks[i + 2].text, 10) catch null
                else
                    null;
                if (v) |n| {
                    sas.format.setYearCutoff(n);
                    i += 3;
                } else {
                    try diags.report(.err, t.line, "Invalid value for the YEARCUTOFF option.", .{});
                    return;
                }
            } else if (eqi(t.text, "obs") or eqi(t.text, "firstobs")) {
                // `options obs=N|MAX|MIN;` / `options firstobs=N|MAX|MIN;` — the
                // GLOBAL default last/first obs for every subsequent input read
                // until reset (`obs=max` restores all-obs; Language Reference: Concepts p.247 +
                // p.517 Table 21.5; BUG-globalobs). Values honour the K/M/G
                // suffix (io.parseObsValue): `obs=2k` is 2048, never 2.
                // FIRSTOBS=0 is not a valid observation number → LOUD, like
                // garbage (BUG-optionsstmtswallow).
                const is_obs = eqi(t.text, "obs");
                const pv = if (i + 2 < toks.len and toks[i + 1].tag == .eq) sas.io.parseObsValue(toks, i + 2) else null;
                if (pv != null and (is_obs or pv.?.val > 0)) {
                    if (is_obs) sas.io.global_obs = pv.?.val else sas.io.global_firstobs = pv.?.val;
                    i += 2 + pv.?.consumed;
                } else {
                    try diags.report(.err, t.line, "Invalid value for the {s} option.", .{if (is_obs) "OBS" else "FIRSTOBS"});
                    return;
                }
            } else if (eqi(t.text, "missing")) {
                // `options missing='X';` — display char for a PLAIN missing
                // numeric (Language Reference: Concepts p.209/234; BUG-optmissing: parsed then DROPPED
                // → `.` printed regardless = silent wrong listing). `missing='';`
                // /`missing='.'` resets to the default `.`. Special missings
                // (.A–.Z/._) keep their letter. Fail LOUD on garbage, like
                // YEARCUTOFF above.
                if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .string) {
                    const s = toks[i + 2].text;
                    sas.io.global_missing = if (s.len == 0 or (s.len == 1 and s[0] == '.')) '.' else s[0];
                    i += 3;
                } else {
                    try diags.report(.err, t.line, "Invalid value for the MISSING option.", .{});
                    return;
                }
            } else if (eqi(t.text, "linesize") or eqi(t.text, "pagesize") or eqi(t.text, "ls") or eqi(t.text, "ps")) {
                // `options linesize=N pagesize=N;` (GAP-listingwidth) — captured
                // and validated; listing procs do NOT wrap/paginate to them yet
                // (accepted, not an error). Fail LOUD on garbage like OBS=.
                const is_ls = eqi(t.text, "linesize") or eqi(t.text, "ls");
                const v: ?usize = if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .number)
                    std.fmt.parseInt(usize, toks[i + 2].text, 10) catch null
                else
                    null;
                if (v) |n| {
                    if (is_ls) sas.io.global_linesize = n else sas.io.global_pagesize = n;
                    i += 3;
                } else {
                    try diags.report(.err, t.line, "Invalid value for the {s} option.", .{if (is_ls) "LINESIZE" else "PAGESIZE"});
                    return;
                }
            } else if (eqi(t.text, "dkricond") or eqi(t.text, "dkrocond")) {
                // Language Reference: Concepts pp.184-185: severity when DROP=/KEEP=/RENAME= names a
                // variable missing from an input (DKRICOND=, default ERROR) vs
                // output (DKROCOND=, default WARN) dataset. HONOURED in
                // io.reportUnreferenced.
                if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
                    const v = toks[i + 2].text;
                    const lvl: ?sas.io.CondLevel = if (eqi(v, "error"))
                        .err
                    else if (eqi(v, "warn") or eqi(v, "warning"))
                        .warn
                    else if (eqi(v, "nowarn") or eqi(v, "nowarning"))
                        .nowarn
                    else
                        null;
                    if (lvl) |l| {
                        if (eqi(t.text, "dkricond")) sas.io.global_dkricond = l else sas.io.global_dkrocond = l;
                        i += 3;
                        continue;
                    }
                }
                try diags.report(.err, t.line, "Invalid value for the {s} option.", .{if (eqi(t.text, "dkricond")) "DKRICOND" else "DKROCOND"});
                return;
            } else if (eqi(t.text, "sortseq")) {
                // SORTSEQ= system option: the DEFAULT collation for PROC SORT
                // (Language Reference: Concepts p.533 — BY honours the linguistic collation of
                // SORTSEQ=LINGUISTIC-sorted data; proc.zig BUG-sortseq).
                // HONOURED: runSort seeds from io.global_sortseq_linguistic.
                //
                // BUG-sortseqbaresuperset — DECLINED, and the volume refutes the
                // premise rather than leaving it open. The ticket says bare
                // `options sortseq=linguistic;` running clean is a silent
                // superset of the p.2415 Restrictions line ("The
                // SORTSEQ=LINGUISTIC option is available only on the PROC SORT
                // SORTSEQ= option and is not available for the system option
                // SORTSEQ"). THAT LINE IS STALE, contradicted TWICE inside its
                // own chapter and TWICE more in another volume:
                //   * Procedures Guide printed p.2403 (`=== pdf 2452 ===`),
                //     "Linguistic Sorting of Data Sets and ICU": "Starting in
                //     the third maintenance release of SAS 9.4, you can specify
                //     linguistic collation using the SORTSEQ= option in the SQL
                //     procedure AND BY SPECIFYING THE SORTSEQ=LINGUISTIC SYSTEM
                //     OPTION." — a DATED feature statement, i.e. the restriction
                //     describes the pre-M3 state; and its Note: "Only PROC SORT
                //     and PROC SQL are affected when the SORTSEQ=LINGUISTIC
                //     system option is specified."
                //   * SQL Procedure User's Guide printed p.261 (`=== pdf 276 ===`),
                //     PROC SQL SORTSEQ=: "If LINGUISTIC is specified for the
                //     SORTSEQ system option, then PROC SQL honors the setting",
                //     its CAUTION naming "the SORTSEQ=LINGUISTIC system option",
                //     and a See pointing at "SORTSEQ= System Option: UNIX,
                //     Windows, and z/OS" in the NLS guide.
                // So honouring it is CONFORMANT, not a superset, and the rc-0
                // arm below stays. (rc_sortseq_linguistic_bare.sas pins that it
                // really collates, which is the half a rc pin cannot state.)
                if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
                    const v = toks[i + 2].text;
                    if (eqi(v, "linguistic") and !(i + 3 < toks.len and toks[i + 3].tag == .lparen)) {
                        sas.io.global_sortseq_linguistic = true;
                        i += 3;
                        continue;
                    }
                    if (eqi(v, "ascii")) {
                        sas.io.global_sortseq_linguistic = false;
                        i += 3;
                        continue;
                    }
                    // GAP-gapsexitingone §5d SPLIT: EBCDIC, the collating-
                    // sequence-options and the SAS-provided translation tables
                    // (isUnimplSortseq) are documented values real SAS runs: a
                    // gap, rc 2, same message. Anything else is a typo'd VALUE
                    // → rc 1, the OPTIONS-statement wording.
                    // LINGUISTIC(<collating-options>) is on the GAP arm, and
                    // BUG-rcsplitmembership F2 MOVED IT TO rc 1 IN ERROR — that
                    // half is reverted here, the rest of F2/F3/F4/F5 stands.
                    // F2 cited the p.2415 Restrictions line, which the header
                    // comment above now shows is stale (refuted four times, once
                    // by a DATED "starting in the third maintenance release"
                    // sentence). With the exclusion gone, nothing says the
                    // system option rejects the modifier form, and D-018's
                    // asymmetry decides an undecided value: a wrong rc 2 costs
                    // one spurious "file an opensas issue", a wrong rc 1 tells a
                    // user their valid SAS is broken. So it goes back to the gap
                    // arm — we honour bare LINGUISTIC but implement none of the
                    // collating-options, and silently ignoring them would change
                    // sort order without saying so (D-002).
                    if (isUnimplSortseq(v) or (eqi(v, "linguistic") and i + 3 < toks.len and toks[i + 3].tag == .lparen)) {
                        sas.diag.markGap();
                        try diags.report(.err, t.line, "system option SORTSEQ={s} is not supported", .{v});
                    } else {
                        try diags.report(.err, t.line, "Invalid value for the SORTSEQ option.", .{});
                    }
                    return;
                }
                try diags.report(.err, t.line, "Invalid value for the SORTSEQ option.", .{});
                return;
            } else if (eqi(t.text, "nobyline") or eqi(t.text, "byline")) {
                // NOBYLINE suppresses the BY line atop each BY group's listing.
                // HONOURED at the two BY-line stampers (main.zig printByLine,
                // proc.zig appendByLine). BYLINE is the default.
                sas.io.global_nobyline = eqi(t.text, "nobyline");
                i += 1;
            } else if (eqi(t.text, "mergenoby")) {
                // Language Reference: Concepts p.574: controls whether SAS ISSUES A MESSAGE when MERGE
                // runs without BY. NOWARN is exactly opensas's behavior (a no-BY
                // 1:1 merge proceeds silently — made row-correct by
                // BUG-mergenobymissing) → inert. WARN/ERROR change the log /
                // step flow from inside the merge driver (exec.zig) → LOUD, and
                // an invalid value is LOUD too: a silent no-op defeats the
                // entire purpose of a guard-rail option (GAP-mergenoby).
                if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
                    const v = toks[i + 2].text;
                    if (eqi(v, "nowarn") or eqi(v, "nowarning")) {
                        i += 3;
                        continue;
                    }
                    if (eqi(v, "warn") or eqi(v, "warning") or eqi(v, "error")) {
                        // GAP-gapsexitingone §5d: the guard matches EXACTLY the
                        // documented-but-unimplemented values; a typo'd value
                        // falls to "Invalid value" below and stays rc 1.
                        sas.diag.markGap();
                        try diags.report(.err, t.line, "system option MERGENOBY={s} is not supported", .{v});
                        return;
                    }
                }
                try diags.report(.err, t.line, "Invalid value for the MERGENOBY option.", .{});
                return;
            } else if (eqi(t.text, "varinitchk")) {
                // Language Reference: Concepts p.488: VARINITCHK=ERROR STOPS the DATA step on an
                // uninitialized variable. NOTE is the SAS default and opensas's
                // exact behavior (the uninit NOTE, GH#75) → inert. WARN/ERROR/
                // ABEND upgrade that NOTE — the emitter is exec.zig's
                // noteUninitVars (a one-line upgrade once that file is free) —
                // so until then they fail LOUD rather than no-op a requested
                // safety check.
                if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
                    const v = toks[i + 2].text;
                    if (eqi(v, "note")) {
                        i += 3;
                        continue;
                    }
                    if (eqi(v, "warn") or eqi(v, "warning") or eqi(v, "error") or eqi(v, "abend")) {
                        // GAP-gapsexitingone §5d: same shape as MERGENOBY — the
                        // guard IS the documented unimplemented set (NOTE is
                        // honoured above; garbage → "Invalid value", rc 1).
                        sas.diag.markGap();
                        try diags.report(.err, t.line, "system option VARINITCHK={s} is not supported", .{v});
                        return;
                    }
                }
                try diags.report(.err, t.line, "Invalid value for the VARINITCHK option.", .{});
                return;
            } else if (eqi(t.text, "noreplace")) {
                // Language Reference: Concepts p.178 names REPLACE/NOREPLACE. NOREPLACE must REFUSE to
                // overwrite an existing dataset — the check belongs to the
                // output drivers (exec.zig). Silently accepting it would
                // overwrite exactly what the user asked to protect → LOUD.
                // (REPLACE, the SAS default and opensas's behavior, is inert.)
                // GAP-gapsexitingone §5d: the keyword itself is the documented
                // option (a typo like `noreplac` lands on "not recognized" at
                // rc 1), so the refusal is a gap → rc 2.
                sas.diag.markGap();
                try diags.report(.err, t.line, "system option NOREPLACE is not supported", .{});
                return;
            } else if (eqi(t.text, "validvarname")) {
                // Inert-equivalent: opensas's name handling is a fixed SUPERSET
                // of every mode — name literals are always accepted, IMPORT
                // headers are always mangled per V7 (io.zig). The VALUE is still
                // validated so `validvarname=v8` (a typo) dies.
                if (i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .name and
                    (eqi(toks[i + 2].text, "v7") or eqi(toks[i + 2].text, "upcase") or eqi(toks[i + 2].text, "any")))
                {
                    i += 3;
                    continue;
                }
                try diags.report(.err, t.line, "Invalid value for the VALIDVARNAME option.", .{});
                return;
            } else if (isInertOption(t.text)) {
                i += 1;
                i += skipOptionValue(toks, i);
            } else {
                // Neither honoured nor a known-inert option: a typo (`obbs=2`)
                // or a real option nobody filed → LOUD, naming it (D-002).
                try diags.report(.err, t.line, "system option {s} is not recognized", .{t.text});
                return;
            }
        }
    }
    // ods/x: accepted, no-op
    if (startsWithI(kw, "filename")) {
        // `filename REF "path";` — register the fileref so a later INFILE/FILE
        // can name it (GAP-filenameref: FILENAME was inert → the bare fileref
        // hit the parser's quoted-path requirement and errored). A device keyword
        // other than DISK (e.g. PIPE) fails LOUD — no PIPE engine. Forms with no
        // path (`filename ref;`, `filename ref clear;`) stay accepted-inert.
        if (toks.len >= 2 and toks[1].tag == .name) {
            var j: usize = 2;
            var device: ?[]const u8 = null;
            if (j < toks.len and toks[j].tag == .name) {
                device = toks[j].text;
                j += 1;
            }
            // BUG-filenameconcatnoop: the FILENAME CONCATENATION form
            // `filename ref ('a.txt' 'b.txt');` (Language Reference: Concepts Table 21.5 p.517:
            // "FILENAME statement with concatenation, wildcard, or piping")
            // was silently accepted and registered NOTHING — the later INFILE
            // then errored "expected an infile path" exactly as if the REF
            // were undefined, pointing the user at the wrong statement. No
            // concat engine exists, so fail LOUD at the FILENAME statement,
            // like the sibling `pipe` device on the same Table 21.5 row.
            if (j < toks.len and toks[j].tag == .lparen) {
                // GAP-gapsexitingone §5d: the guard is the lparen itself — the
                // documented concatenation form, valid SAS → gap, rc 2.
                sas.diag.markGap();
                return diags.fail(error.ParseError, toks[1].line, "FILENAME concatenation (a parenthesised list of files) is not supported", .{});
            }
            if (j < toks.len and toks[j].tag == .string) {
                if (device) |d| if (!eqi(d, "disk")) {
                    // GAP-gapsexitingone §5d SPLIT: a DOCUMENTED device keyword
                    // (the FILENAME syntax diagram's closed list — PIPE, FTP,
                    // SOCKET, …) is valid SAS we lack an engine for → gap, rc 2,
                    // same message. Anything else is a typo'd device word →
                    // rc 1, "not recognized" (the OPTIONS-statement wording).
                    if (isDocFilenameDevice(d)) {
                        sas.diag.markGap();
                        return diags.fail(error.ParseError, toks[1].line, "FILENAME device {s} is not supported (DISK only)", .{d});
                    }
                    return diags.fail(error.ParseError, toks[1].line, "FILENAME device {s} is not recognized (DISK only)", .{d});
                };
                try registerFileref(diags, toks[1].line, toks[1].text, toks[j].text);
                // GAP-filenameopt: trailing name=value options after the path
                // were parsed and silently IGNORED (the audit probe) — a typo'd
                // `lrelc=100` vanished. Enumerate (SAS 9.4 FILENAME statement,
                // DISK device) and end in a real else:
                //   LRECL=<n>      — INERT: the infile reader takes full lines of
                //     any length (same reasoning as INFILE lrecl=, GH#64 ISS-infilelrecl).
                //   TERMSTR=CRLF|CR|LF|NL — INERT: the reader splits on \n and
                //     trims \r (io.zig readLines), so every terminator variant
                //     reads byte-identically.
                //   RECFM=V — INERT: variable-length records are the only record
                //     form the reader has. RECFM=<fixed-length F/N…> would need
                //     a padded-record reader → LOUD, never a silent line-split.
                //   anything else (ENCODING=, a typo, …) → LOUD, naming it.
                var k = j + 1;
                while (k < toks.len and toks[k].tag != .semicolon) {
                    const t = toks[k];
                    if (t.tag == .name and k + 2 < toks.len and toks[k + 1].tag == .eq) {
                        const v = toks[k + 2];
                        if (eqi(t.text, "lrecl") and v.tag == .number) {
                            k += 3; // INERT, per the header comment
                        } else if (eqi(t.text, "termstr") and v.tag == .name and
                            (eqi(v.text, "crlf") or eqi(v.text, "cr") or eqi(v.text, "lf") or eqi(v.text, "nl")))
                        {
                            k += 3; // INERT, per the header comment
                        } else if (eqi(t.text, "recfm") and v.tag == .name and eqi(v.text, "v")) {
                            k += 3; // INERT, per the header comment
                        } else if (eqi(t.text, "recfm")) {
                            // report+return (the OPTIONS-arm style in this same
                            // function): captured .err, later steps errhalt-skip.
                            // GAP-gapsexitingone §5d SPLIT: a documented record
                            // form (F/N/P/VB/VS/VBS/U/D — V is the inert arm
                            // above) is valid SAS → gap, rc 2, same message;
                            // garbage is a typo'd value → rc 1.
                            if (isDocRecfm(v.text)) {
                                sas.diag.markGap();
                                try diags.report(.err, t.line, "FILENAME RECFM={s} is not supported (the reader is variable-length records only)", .{v.text});
                            } else {
                                try diags.report(.err, t.line, "Invalid value for the RECFM= FILENAME option.", .{});
                            }
                            return;
                        } else {
                            try diags.report(.err, t.line, "FILENAME option {s} is not supported", .{t.text});
                            return;
                        }
                    } else {
                        try diags.report(.err, t.line, "unexpected token {s} in the FILENAME statement", .{t.text});
                        return;
                    }
                }
            }
        }
    }
    // ponytail: opensas renders to ONE output stream (the listing), so ODS
    // destination open/close (`ods listing/html/pdf/rtf/csv/excel/html5 [close]`,
    // `ods _all_ close`) and the results/graphics/escapechar toggles are
    // accepted-as-listing no-ops — output correctly stays on stdout, and a
    // `ods pdf; … ods pdf close;` wrap around a PROC must still run and print.
    // But SELECT/EXCLUDE filter which output objects appear, OUTPUT captures a
    // PROC table into a dataset, and TRACE reports objects — ignoring any of
    // those is a silent WRONG/MISSING result, so they fail LOUD by name.
    if (eqi(kw, "ods") and toks.len >= 2 and toks[1].tag == .name) {
        const sub = toks[1].text;
        if (eqi(sub, "output")) {
            // GAP-gapsexitingone §5d: the guard matches the documented statement
            // itself (a typo'd sub-statement is the accepted no-op above), so
            // only valid SAS reaches these → gap, rc 2.
            sas.diag.markGap();
            return diags.fail(error.ParseError, toks[1].line, "ODS OUTPUT (capture to dataset) is not supported yet", .{});
        }
        if (eqi(sub, "select") or eqi(sub, "exclude") or eqi(sub, "trace")) {
            sas.diag.markGap(); // §5d — same shape as OUTPUT above
            return diags.fail(error.ParseError, toks[1].line, "ODS {s} is not supported yet", .{sub});
        }
    }
}

// ── FILENAME fileref registry (GAP-filenameref) ─────────────────────────────
// Session-wide, like the global OBS=/MISSING= state: paths are token slices
// (program-lifetime), so no allocation. ponytail: fixed 64 slots — a program
// declaring more filerefs errors loud rather than silently dropping one.
const Fileref = struct { name: []const u8, path: []const u8 };
const max_filerefs = 64;
var filerefs: [max_filerefs]Fileref = undefined;
var fileref_count: usize = 0;

fn registerFileref(diags: *sas.diag.Diagnostics, line: usize, name: []const u8, path: []const u8) sas.diag.Error!void {
    for (filerefs[0..fileref_count]) |*f| if (eqi(f.name, name)) { // re-declaration re-binds
        f.path = path;
        return;
    };
    if (fileref_count == max_filerefs) {
        // GAP-gapsexitingone §5d: the 64-slot ceiling is OURS — SAS 9.4 has no
        // fileref limit, so a program tripping it is valid SAS refused by an
        // opensas limitation → gap, rc 2 (D-009b(i)).
        sas.diag.markGap();
        return diags.fail(error.ParseError, line, "too many FILENAME filerefs (max {d})", .{max_filerefs});
    }
    filerefs[fileref_count] = .{ .name = name, .path = path };
    fileref_count += 1;
}

fn findFileref(name: []const u8) ?[]const u8 {
    for (filerefs[0..fileref_count]) |f| if (eqi(f.name, name)) return f.path;
    return null;
}

/// The D-014 INERT allowlist for the OPTIONS statement (BUG-optionsstmtswallow):
/// display/pagination/log cosmetics and session tuning that a batch
/// interpreter with no windowing environment genuinely cannot observe. An
/// option belongs here ONLY when accepting it silently can never change data
/// or listing content — anything that can is honoured in handleGlobal's
/// OPTIONS chain or fails loud there. (MINOPERATOR/MINDELIMITER look inert
/// here only because the macro layer already applied them at scan time —
/// BUG-minoperatoropt; the statement text passes through to us.)
fn isInertOption(name: []const u8) bool {
    const list = [_][]const u8{
        // listing cosmetics (opensas listings are unpaginated plain text)
        "date",         "nodate",      "number",     "nonumber",   "center",
        "nocenter",     "pageno",      "papersize",  "orientation",
        "topmargin",    "bottommargin", "leftmargin", "rightmargin",
        "formchar",     "formdlim",
        // label display is OPT-IN per proc (PROC PRINT LABEL/SPLIT=), never a
        // system default — LABEL/NOLABEL toggle a default nothing reads here
        "label",        "nolabel",
        // log cosmetics
        "source",       "nosource",    "source2",    "nosource2",   "echo",
        "noecho",       "msglevel",    "stimer",     "nostimer",    "fullstimer",
        "nofullstimer",
        // macro toggles/debugging (the macro processor runs regardless; the
        // `in` gate itself was already applied by macro.zig — see above)
        "mprint",       "nomprint",    "mlogic",     "nomlogic",    "symbolgen",
        "nosymbolgen",  "mrecall",     "nomrecall",  "merror",      "nomerror",
        "serror",       "noserror",    "quotelenmax", "noquotelenmax",
        "minoperator",  "nominoperator", "mindelimiter", "mstored",  "nomstored",
        "sasmstore",
        // case translation (opensas names are case-insensitive throughout)
        "caps",         "nocaps",
        // session/storage tuning: no observable effect on values or listings
        "compress",     "reuse",       "bufsize",    "bufno",       "blksize",
        "sortsize",     "memsize",     "realmemsize", "sumsize",    "cpucount",
        "threads",      "nothreads",   "s",          "s2",          "spool",
        "nospool",      "dtreset",     "nodtreset",  "noerrorabend", "replace",
        // format search order: there are no format catalogs — PROC FORMAT
        // registers into the single global table (format.zig), nothing to search
        "fmtsearch",
    };
    for (list) |o| if (eqi(name, o)) return true;
    return false;
}

/// Tokens past the optional `= value` of an inert OPTIONS entry, `i` pointing
/// just past the option NAME: 0 when no `=` follows, else the eq plus the
/// value — a scalar (number/string/name, optionally signed) or a balanced (…)
/// group (`fmtsearch=(lib work)`). A dangling `=` consumes nothing; the main
/// loop's non-name guard then errors on it.
fn skipOptionValue(toks: []const Token, i: usize) usize {
    if (i >= toks.len or toks[i].tag != .eq) return 0;
    var j = i + 1;
    if (j < toks.len and toks[j].tag == .lparen) {
        var depth: usize = 0;
        while (j < toks.len) : (j += 1) {
            if (toks[j].tag == .lparen) {
                depth += 1;
            } else if (toks[j].tag == .rparen) {
                depth -= 1;
                if (depth == 0) {
                    j += 1;
                    break;
                }
            }
        }
        return j - i;
    }
    if (j + 1 < toks.len and (toks[j].tag == .minus or toks[j].tag == .plus) and toks[j + 1].tag == .number) return 3;
    if (j < toks.len and toks[j].tag == .number) {
        // a size suffix lexes as a separate one-char name: `bufsize=64k`
        if (j + 1 < toks.len and toks[j + 1].tag == .name and toks[j + 1].text.len == 1 and
            std.mem.indexOfScalar(u8, "kmgKMg", toks[j + 1].text[0]) != null) return 3;
        return 2;
    }
    if (j < toks.len and (toks[j].tag == .string or toks[j].tag == .name)) return 2;
    return 0;
}

/// Rewrite `infile REF;` / `file REF;` naming a registered fileref into the
/// quoted path the parser requires (parser.zig owns the INFILE/FILE grammar and
/// only takes a .string — resolving here as a token patch keeps the parser
/// untouched). No registered filerefs (the common case) or no match → the
/// original slice, no copy.
fn resolveFilerefs(a: std.mem.Allocator, body: []const Token) ![]const Token {
    if (fileref_count == 0) return body;
    var patched: ?[]Token = null;
    for (body, 0..) |t, i| {
        if (t.tag != .name or !(eqi(t.text, "infile") or eqi(t.text, "file"))) continue;
        if (i + 1 >= body.len or body[i + 1].tag != .name) continue;
        const path = findFileref(body[i + 1].text) orelse continue;
        if (patched == null) patched = try a.dupe(Token, body);
        patched.?[i + 1] = .{ .tag = .string, .text = path, .line = body[i + 1].line };
    }
    return patched orelse body;
}

fn startsWithI(text: []const u8, prefix: []const u8) bool {
    return text.len >= prefix.len and eqi(text[0..prefix.len], prefix);
}

/// Read a DATA-statement output dataset name at `*pos`, consuming a two-level
/// `libref.member` when present (`DATA TOKEEP.TOKDM;` — DSOPT-out). Advances `pos`
/// past the name (and the `.member`). The full `libref.member` string is the
/// dataset name, so writeLibOutputs routes it to the libref like SET reads do.
fn dataName(a: std.mem.Allocator, toks: []const Token, pos: *usize) sas.diag.Error![]const u8 {
    var name = toks[pos.*].text;
    pos.* += 1;
    if (pos.* + 1 < toks.len and toks[pos.*].tag == .dot and toks[pos.* + 1].tag == .name) {
        name = try std.fmt.allocPrint(a, "{s}.{s}", .{ name, toks[pos.* + 1].text });
        pos.* += 2;
    }
    return name;
}

fn runStep(a: std.mem.Allocator, out: *std.ArrayList(u8), lib: *sas.exec.Library, diags: *sas.diag.Diagnostics, toks: []const Token, g: *Globals, io: ?Io) sas.diag.Error!void {
    if (eqi(toks[0].text, "data")) {
        // header: `data [name] ;`  — a name, else an anonymous output dataset.
        var pos: usize = 1;
        var name: []const u8 = "_data_";
        if (pos < toks.len and toks[pos].tag == .name) {
            name = try dataName(a, toks, &pos); // handles a two-level `libref.member`
        }
        // dataset options on the primary: `data out(keep=x rename=(a=b)); …` — the
        // option tokens (between the parens) are applied to the result after the
        // step runs (DSOPT); io.zig owns the parse+apply, main just carves them out.
        const opt_toks = if (pos < toks.len and toks[pos].tag == .lparen) skipParens(toks, &pos) else &[_]Token{};
        // `data a b …;` declares several output datasets (SAS 9.4 Language Reference: Concepts, DATA
        // statement): the implicit bottom-of-step output — and a bare
        // `output;` — writes the current observation to EVERY named dataset,
        // and ALL are created even when zero observations are written
        // (BUG-multioutput; silently dropping the extras was data loss).
        // Collect the extras WITH their per-dataset options; runData registers
        // them up front and the executor fans the writes out (DSMULTI). Extra
        // names may be two-level (`data a.b c.d;`), so consume the `.member`
        // before any options.
        var extras: std.ArrayList(DataOut) = .empty;
        while (pos < toks.len and toks[pos].tag == .name) {
            const xname = try dataName(a, toks, &pos);
            const xopts = if (pos < toks.len and toks[pos].tag == .lparen) skipParens(toks, &pos) else &[_]Token{};
            try extras.append(a, .{ .name = xname, .opt_toks = xopts });
        }
        if (pos >= toks.len or toks[pos].tag != .semicolon) {
            failLoud("DATA step options are not supported", .{});
            return;
        }
        const res = try runData(a, out, lib, diags, toks[pos + 1 ..], name, io, extras.items);
        // A STOPPED step may have registered nothing over an existing member
        // (GAP-errgatereplaces), so `lib.find` here could hand back the SURVIVOR —
        // applying this step's keep=/drop=/rename= to it would mutate the very
        // data set the "was not replaced" rule just saved. Deliberately coarser
        // than commitOut's rule (it skips the MODIFY-exempt and new-name cases
        // too): the cost is an unapplied option on a step that already failed,
        // against silently editing rescued data.
        if (!diags.hasStepErrors()) {
            // BUG-modifydsoptdescriptor / BUG-modifydsoptwhere: a MODIFY master
            // is FROZEN against DATA-statement data set options — its descriptor
            // (KEEP=/DROP=/RENAME=) and its ROWS (WHERE=, which was permanently
            // deleting every non-matching observation from the stored file).
            // It must be frozen against BOTH spellings. exec.zig's
            // modifyFrozenMaster froze the statement form (`modify d; drop y;`)
            // at the schema choke point; these two lines are the OTHER door —
            // they run AFTER the step, straight onto the committed dataset, so
            // the freeze never saw them and `data d(drop=y); modify d;` still
            // deleted column y and every value in it.
            // The master is identified by POINTER through `lib.find`, the same
            // lookup modifyFrozenMaster compares with, so there is no second
            // name-normalising predicate here to drift out of step with it.
            const master: ?*sas.dataset.Dataset = if (res.modify_master) |mm| lib.find(mm) else null;
            if (opt_toks.len > 0) if (lib.find(name)) |ds| {
                const toks_out = if (master != null and master.? == ds) try stripMasterOptions(a, opt_toks) else opt_toks;
                try sas.io.applyDatasetOptionsRefs(a, ds, toks_out, diags, false, res.refs); // OUTPUT dataset options: DKROCOND=WARN
            };
            // The extras are NOT exempt: `data master other(drop=y); modify master;`
            // creates `other` fresh, so it takes the ordinary full-PDV schema —
            // the same per-OUTPUT (not per-step) rule exec.zig applies for
            // p.260's Example 8. Only a name that resolves to the master itself
            // is frozen, which the pointer test below still catches.
            for (extras.items) |x| if (x.opt_toks.len > 0) if (lib.find(x.name)) |ds| {
                const toks_out = if (master != null and master.? == ds) try stripMasterOptions(a, x.opt_toks) else x.opt_toks;
                try sas.io.applyDatasetOptionsRefs(a, ds, toks_out, diags, false, res.refs);
            };
        }
    } else {
        try runProc(a, out, lib, diags, toks, g);
    }
}

/// A non-primary output of `data a b …;` (BUG-multioutput): its name and its
/// per-dataset option tokens (`data outa(keep=a) outb(keep=b);`), applied after
/// the step exactly like the primary's options.
const DataOut = struct { name: []const u8, opt_toks: []const Token };

/// Register one DATA-step output — UNLESS the step was stopped by an error and a
/// member of that name already exists. Language Reference: Concepts printed p.175 (Example Code 8.6; pdf
/// index 192, offset +17, the page's own footer re-verified here):
///
///   WARNING: Data set WORK.TEST was not replaced because this step was stopped.
///
/// A NEW name is still created: that same example's following `proc print
/// data=test` reports "NOTE: No variables in data set WORK.TEST" and NOT "does
/// not exist", so the stopped step left a member behind (BUG-emptycols parity —
/// exec's gates already `seedSchema` the compile-time columns). The two halves
/// are why "skip lib.put on a bad step" is too blunt.
///
/// GAP-errgatereplaces: this ONE place covers all 18 AUDIT-errhaltclass sites
/// that stop a step WITHOUT erroring — exec.zig's two compile-time gates (:720,
/// :770) and every `report`-and-continue that hands back a spent `.once` driver.
/// They all return normally, so `lib.put` used to fire for every one of them and
/// a live permanent member was replaced by the stopped step's empty output. The
/// gates deliberately keep RETURNING rather than erroring: an error out of
/// `ex.run` propagates past `interpret`'s `writeLibOutputs` call, which would
/// throw away every EARLIER step's disk output too.
fn commitOut(a: std.mem.Allocator, lib: *sas.exec.Library, diags: *sas.diag.Diagnostics, name: []const u8, ds: *sas.dataset.Dataset, stopped: bool) sas.diag.Error!void {
    if (stopped and memberExists(lib, name)) {
        const qual = if (std.mem.indexOfScalar(u8, name, '.') != null)
            name
        else
            try std.fmt.allocPrint(a, "work.{s}", .{name});
        try diags.warn(0, "Data set {s} was not replaced because this step was stopped", .{try std.ascii.allocUpperString(a, qual)});
        return;
    }
    try lib.put(name, ds);
}

/// Is there already a data set of this name — in the Library, or on disk under a
/// bound libref? The disk half is not optional: `loadLibInputs` deliberately does
/// NOT preload a `data <libref.x>` OUTPUT target, so a member written by an
/// EARLIER RUN is invisible to `lib.find` — and that is exactly the case where
/// replacing it destroys real data. Reuses BUG-existdisk's probe rather than a
/// second one.
fn memberExists(lib: *sas.exec.Library, name: []const u8) bool {
    return lib.find(name) != null or sas.functions.memberOnDisk(name);
}

/// Parse a DATA-step body and execute it into a fresh dataset, capturing its
/// `put` log into `out`. A non-`_null_` result is registered for later `set`.
/// Every `extras` output is created up front and handed to the executor, which
/// fans bare/implicit `output` writes out to them; all of them (and the primary)
/// are REGISTERED at the end through `commitOut`, so the "was not replaced" rule
/// governs every output of the step, not just the first.
/// What `runData` hands back to the step loop. `modify_master` is the name on
/// this step's MODIFY statement (null when there is none) — taken from the
/// executor's OWN `modify_names` AFTER `expandPrefixes`, never re-derived from
/// the tokens, so the caller's descriptor freeze cannot disagree with
/// exec.zig's (BUG-modifydsoptdescriptor).
const DataResult = struct { refs: []const []const u8, modify_master: ?[]const u8 = null };

fn runData(a: std.mem.Allocator, out: *std.ArrayList(u8), lib: *sas.exec.Library, diags: *sas.diag.Diagnostics, body_in: []const Token, name: []const u8, io: ?Io, extras: []const DataOut) sas.diag.Error!DataResult {
    // GAP-liststmt: a statement-initial `list;` (echo the current input record
    // to the log) fell through to the assignment parse → the MISLEADING
    // "expected '=' in assignment". Fail LOUD with the real story instead.
    // ponytail: statement-initial only — `if x then list;` still hits the old
    // parse error until LIST is actually implemented (parser.zig owns that).
    for (body_in, 0..) |t, i| {
        const boundary = i == 0 or body_in[i - 1].tag == .semicolon;
        if (boundary and t.tag == .name and eqi(t.text, "list") and
            i + 1 < body_in.len and body_in[i + 1].tag == .semicolon) {
            // GAP-gapsexitingone §5d: LIST is a documented DATA-step statement;
            // the guard is the keyword itself → gap, rc 2.
            sas.diag.markGap();
            return diags.fail(error.ParseError, t.line, "The LIST statement is not supported (it echoes the current input record to the log)", .{});
        }
    }
    const body = try resolveFilerefs(a, body_in); // GAP-filenameref
    var p = sas.parser.Parser.init(a, try withEof(a, body), diags);
    const program = try p.parseProgram();

    var pdv = sas.pdv.Pdv.init(a);
    var ev: sas.eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = diags, .call_fn = &sas.functions.dispatch };
    var ex = sas.exec.Executor.init(a, &pdv, diags, &ev, lib);
    ex.io = io;
    // The `length` statement fixes SAS variable order; parse it from the tokens
    // (its AST node is inert) so the executor can pre-seed the PDV in that order.
    ex.declared = try lengthVars(a, body, diags);

    const ds = try a.create(sas.dataset.Dataset);
    ds.* = sas.dataset.Dataset.init(a, name);
    // Build the extra outputs up front so `output m2;` writes into the SAME
    // dataset object the registration below (and runStep's option-application)
    // will see. They are REGISTERED after the step, with the primary, so a
    // stopped step cannot replace a live `data x lib.keeper;` member either
    // (GAP-errgatereplaces — patching only the primary leaves the sibling
    // output destroying data).
    const xds = try a.alloc(*sas.dataset.Dataset, extras.len);
    for (extras, 0..) |x, i| {
        const xd = try a.create(sas.dataset.Dataset);
        xd.* = sas.dataset.Dataset.init(a, x.name);
        xds[i] = xd;
    }
    ex.extra_outs = xds;
    try ex.run(program, ds);

    try out.appendSlice(a, ex.log.items);
    // This step's own errors: main skips a step once any prior one errored.
    // MODIFY is EXEMPT — it edits the master IN PLACE, so there is no "replace"
    // for Language Reference: Concepts' warning to be about, and its re-emitted master is the edit.
    // Withholding it would DISCARD the successfully-applied transactions, the
    // silent row loss BUG-modifybynomatch (§4 of audit-errhaltclass) exists to
    // prevent — that site reports `.err` and continues on purpose.
    const stopped = diags.hasStepErrors() and ex.modify_names == null;
    for (extras, 0..) |x, i| try commitOut(a, lib, diags, x.name, xds[i], stopped);
    if (!eqi(name, "_null_")) try commitOut(a, lib, diags, name, ds, stopped);
    // BUG-dropoptfalsewarn: hand the step's FULL PDV name set to the
    // output-option "never been referenced" check — the same set the
    // STATEMENT path validates against (exec.assertReferenced). Without it
    // `data b(drop=e); set a end=e;` false-warned: the finalized output
    // schema no longer carries the executor-dropped end= temp.
    var refs: std.ArrayList([]const u8) = .empty;
    for (pdv.vars.items) |v| try refs.append(a, v.name);
    return .{
        .refs = refs.items,
        // exec.zig's own post-expandPrefixes value — the single source of truth
        // for "which dataset is the MODIFY master" (BUG-modifydsoptdescriptor).
        .modify_master = if (ex.modify_names) |m| (if (m.len > 0) m[0] else null) else null,
    };
}

/// `opt_toks` with every clause that would EDIT THE STORED MASTER removed —
/// KEEP=, DROP=, RENAME= (the descriptor: BUG-modifydsoptdescriptor) and WHERE=
/// (the rows: BUG-modifydsoptwhere). Everything else is copied verbatim. Used
/// ONLY for a MODIFY master.
///
/// WHY WHERE= BELONGS HERE, measured and then cited. `data d(where=(x>15));
/// modify d;` PERMANENTLY DELETED every non-matching observation from the
/// stored data set — verified through four independent read paths and then in a
/// SEPARATE PROCESS re-reading the .sas7bdat, so it was the physical file and
/// not a session copy. The reference gives MODIFY no output to filter: printed
/// p.240 (`=== pdf 251 ===`, offset +11) — "Replaces, deletes, and appends
/// observations in an existing SAS data set IN PLACE but does not create an
/// additional copy" — and all four Syntax Forms hang `<(data-set-options)>` off
/// the MODIFY statement, while the DATA statement gets only the bare
/// Restriction "This data set must also appear in the DATA statement". The
/// Notes make the placement explicit for the one option whose misplacement they
/// bother to call out: specify it "in the MODIFY statement, AND NOT IN THE DATA
/// STATEMENT". So a DATA-statement WHERE= on the master has nothing to subset,
/// and deleting rows for it is destruction the program never asked for.
///
/// SILENT, not an ERROR, for internal consistency rather than by taste: the
/// three descriptor options on this exact spelling are already silently
/// ineffective (p.253's "it is not necessary to put NWSTOCK in a DROP
/// statement"), and WHERE= is the same shape — an option on the DATA statement
/// of a MODIFY step that would edit the stored master. Whether real SAS warns
/// here is NOT in the volumes; what is settled is that it must not destroy.
///
/// The call is still MADE with the stripped list rather than skipped, so
/// `data d(bogusopt=1); modify d;` keeps failing loud on the unknown option
/// (D-002) — skipping outright would have traded one silent bug for another.
///
/// The clause boundaries mirror `io.zig`'s own option walk exactly — a name
/// list runs until the next `name =` key (with `a1-a3` ranges consumed whole),
/// and RENAME=/WHERE= carry a balanced paren group, skipped as a GROUP for the
/// reason io.zig gives at its own where-arm: a `name =` INSIDE the predicate
/// (`where=(drop=1)`) must never be mistaken for an option key.
fn stripMasterOptions(a: std.mem.Allocator, opt_toks: []const Token) ![]const Token {
    var kept: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < opt_toks.len) {
        if (!(opt_toks[i].tag == .name and i + 1 < opt_toks.len and opt_toks[i + 1].tag == .eq)) {
            try kept.append(a, opt_toks[i]);
            i += 1;
            continue;
        }
        const key = opt_toks[i].text;
        if (eqi(key, "keep") or eqi(key, "drop")) {
            i += 2; // past `key =`, then the name list (io.collectNames' rule)
            while (i < opt_toks.len and opt_toks[i].tag == .name) {
                if (i + 1 < opt_toks.len and opt_toks[i + 1].tag == .eq) break; // next option key
                i += if (i + 2 < opt_toks.len and opt_toks[i + 1].tag == .minus and opt_toks[i + 2].tag == .name) 3 else 1;
            }
        } else if (eqi(key, "rename")) {
            i += 2;
            if (i < opt_toks.len and opt_toks[i].tag == .lparen) _ = skipParens(opt_toks, &i);
        } else if (eqi(key, "where")) {
            i += 2; // skip `where =` and the whole balanced group
            if (i < opt_toks.len and opt_toks[i].tag == .lparen) _ = skipParens(opt_toks, &i);
        } else {
            try kept.append(a, opt_toks[i]); // any other key: its value copies on later turns
            i += 1;
        }
    }
    return kept.items;
}

/// Collect the variables of every `length` (and `attrib … length=`) statement in
/// the body, in declaration order, tagging each char (`$`) vs numeric — so the
/// executor can build the PDV (and thus the output columns) in SAS variable order,
/// carrying the declared char width. Groups share one type:
/// `length a b c $ 10  x 8;` → a,b,c char; x numeric.
fn lengthVars(a: std.mem.Allocator, body: []const Token, diags: *sas.diag.Diagnostics) ![]sas.exec.DeclVar {
    var list: std.ArrayList(sas.exec.DeclVar) = .empty;
    // GH#73: variables whose length is already established by a PRIOR statement
    // (an assignment `x = …`) — a later char LENGTH on such a var is IGNORED by
    // SAS (first length wins) and warns; drop it from the pre-seed list so the
    // first assignment's length stands instead of the late one truncating.
    var seen: std.ArrayList([]const u8) = .empty;
    // GH#70: true once a SET/MERGE/UPDATE/MODIFY has brought input columns in —
    // a char LENGTH declared AFTER that meets an already-numeric source var and is
    // the fatal conflict; a LENGTH declared BEFORE is schema-pinning (lenient).
    var saw_input = false;
    // BUG-varorder: true once a var-declaring statement (RETAIN/FORMAT/INFORMAT/
    // INPUT/assignment/sum) has passed — SAS establishes a variable at the first
    // statement that mentions it, so a LENGTH/ATTRIB after one seeds its vars
    // AFTER those statements' vars (`.late`), not unconditionally first.
    // ponytail: DO-index/ARRAY-member vs LENGTH order left unhandled (rare).
    var saw_declaring = false;
    var i: usize = 0;
    while (i < body.len) {
        const boundary = i == 0 or body[i - 1].tag == .semicolon;
        // record an assignment target as an established (already-referenced) var
        if (boundary and body[i].tag == .name and i + 1 < body.len and body[i + 1].tag == .eq) {
            try seen.append(a, body[i].text);
            saw_declaring = true; // BUG-varorder: an assignment establishes its target
        }
        // a sum statement `v + expr;` establishes v at its position too
        if (boundary and body[i].tag == .name and i + 1 < body.len and body[i + 1].tag == .plus)
            saw_declaring = true;
        // RETAIN/FORMAT/INFORMAT/INPUT establish the vars they name (a special
        // name LIST like _numeric_ names no new variable — it expands later).
        if (boundary and body[i].tag == .name and (eqi(body[i].text, "retain") or
            eqi(body[i].text, "format") or eqi(body[i].text, "informat") or eqi(body[i].text, "input")))
        {
            const is_input = eqi(body[i].text, "input");
            var j = i + 1;
            while (j < body.len and body[j].tag != .semicolon) : (j += 1)
                if (body[j].tag == .name and !isSpecialListName(body[j].text)) {
                    saw_declaring = true;
                    // BUG-lengthaftersetinput: an INPUT variable is ESTABLISHED at
                    // its informat width, so a later char LENGTH/ATTRIB naming it
                    // is ignored + warns (Language Reference: Concepts p.49 note 1) — the GH#73 guard
                    // below consults this same list. ponytail: informat names
                    // (`date9.` in `input d date9.;`) land here too; they only
                    // false-fire if a later char LENGTH re-declares that exact
                    // name — and then the p.49 warning is still the right call.
                    if (is_input) try seen.append(a, body[j].text);
                };
        }
        if (boundary and body[i].tag == .name and (eqi(body[i].text, "set") or
            eqi(body[i].text, "merge") or eqi(body[i].text, "update") or eqi(body[i].text, "modify")))
            saw_input = true;
        if (boundary and body[i].tag == .name and eqi(body[i].text, "length")) {
            i += 1; // past `length`
            const stmt_start = list.items.len; // BUG-varorder: this statement's vars
            const late = saw_declaring;
            while (i < body.len and body[i].tag != .semicolon) {
                const group_start = list.items.len;
                while (i < body.len and body[i].tag == .name) {
                    const first = body[i].text;
                    i += 1;
                    // numbered range `x1-x3` (GH#32): expand, else this loop spins
                    // forever on the unconsumed `-`. Shared expander (zero-pad safe).
                    if (i + 1 < body.len and body[i].tag == .minus and body[i + 1].tag == .name) {
                        var names: std.ArrayList([]const u8) = .empty;
                        try sas.parser.expandRange(a, &names, first, body[i + 1].text);
                        i += 2;
                        for (names.items) |nm| try list.append(a, .{ .name = nm, .type = .num });
                    // BUG-speciallistphantom (GH#79): `_ALL_`/`_NUMERIC_`/
                    // `_CHARACTER_` are variable name LISTS (Statements Ref
                    // printed p.24), never a variable of their own — seeding
                    // one minted a phantom column named after the keyword.
                    // Nothing is lost: the vars the list names are established
                    // (a length on them is first-length-wins, GH#73) or not
                    // yet born, so there is nothing to seed either way.
                    } else if (!isSpecialListName(first)) try list.append(a, .{ .name = first, .type = .num });
                }
                const is_char = i < body.len and body[i].tag == .dollar;
                if (is_char) i += 1;
                var declared_len: usize = 0;
                if (i < body.len and body[i].tag == .number) {
                    declared_len = std.fmt.parseInt(usize, std.mem.trimEnd(u8, body[i].text, "."), 10) catch 0; // `length v $ 20;` → 20
                    i += 1;
                }
                if (is_char) {
                    for (list.items[group_start..]) |*dv| {
                        dv.type = .char;
                        dv.len = declared_len; // BUG-contentsmeta: carry the declared width to the column
                        dv.after_input = saw_input; // GH#70: char LENGTH after a SET = fatal conflict
                    }
                    // GH#73: a char LENGTH after the var's length was already set
                    // by a prior statement is IGNORED (keep first length) + warns.
                    var k = group_start;
                    while (k < list.items.len) {
                        if (seenHas(seen.items, list.items[k].name)) {
                            try diags.warn(0, "Length of character variable {s} has already been set. Use the LENGTH statement as the very first statement in the DATA STEP.", .{list.items[k].name});
                            _ = list.orderedRemove(k);
                        } else k += 1;
                    }
                    // BUG-lengthaftersetinput: a char LENGTH after a SET/MERGE —
                    // split into an early type sentinel + a late length copy.
                    try splitAfterSet(a, &list, group_start, saw_input);
                } else {
                    for (list.items[group_start..]) |*dv| dv.len = declared_len; // numeric byte-length → truncate-on-store (GH#46)
                }
            }
            for (list.items[stmt_start..]) |*dv| dv.late = late; // BUG-varorder
            continue;
        }
        // `attrib v1 v2 label='…' length=[$]n format=f …;` — the length= option must
        // seed the PDV var's type/length exactly like a LENGTH statement, so a char
        // var declared only via ATTRIB (ISS-attriblength: e.g. an `if 0;` shell
        // dataset) is Char n, not Char 1, and its assignments don't truncate to 1.
        if (boundary and body[i].tag == .name and eqi(body[i].text, "attrib")) {
            i += 1; // past `attrib`
            const stmt_start = list.items.len; // BUG-varorder
            const late = saw_declaring;
            while (i < body.len and body[i].tag != .semicolon) {
                // A variable-name group: names whose next token is NOT `=` (an
                // option name is always followed by `=`).
                const group_start = list.items.len;
                var group_named: usize = 0;
                while (i < body.len and body[i].tag == .name and
                    !(i + 1 < body.len and body[i + 1].tag == .eq)) : (i += 1)
                {
                    group_named += 1;
                    // BUG-speciallistphantom (GH#79): `_ALL_`/`_NUMERIC_`/
                    // `_CHARACTER_` are variable name LISTS — ATTRIB's own p.34
                    // "any form that SAS allows" delegates to the p.24 enumeration
                    // — never a variable of their own. Seeding one minted a phantom
                    // column named after the keyword; the group's FORMAT=/INFORMAT=/
                    // LABEL= still reaches the listed vars via exec's expansion.
                    if (!isSpecialListName(body[i].text)) try list.append(a, .{ .name = body[i].text, .type = .num });
                }
                if (group_named == 0) break; // no group name → stop (malformed)
                // The group's options (name `=` value …), applying length=.
                // ISS-attriblabeltype: only a var-creating option (LENGTH=/FORMAT=/
                // INFORMAT=, Language Reference: Concepts p.51) may seed type. A label-only group cannot even
                // create the var — dropping it lets a later `retain X ''` establish
                // CHARACTER (Language Reference: Concepts p.509-510) instead of this default-numeric seed
                // pre-empting it and corrupting the char assignment to missing.
                var creates = false;
                var group_has_len = false; // an explicit length= settles type/width (wins)
                while (i + 1 < body.len and body[i].tag == .name and body[i + 1].tag == .eq) {
                    const opt = body[i].text;
                    i += 2; // past the option name and `=`
                    if (eqi(opt, "length")) {
                        creates = true;
                        group_has_len = true;
                        const is_char = i < body.len and body[i].tag == .dollar;
                        if (is_char) i += 1;
                        var declared_len: usize = 0;
                        if (i < body.len and body[i].tag == .number) {
                            declared_len = std.fmt.parseInt(usize, std.mem.trimEnd(u8, body[i].text, "."), 10) catch 0;
                            i += 1;
                        }
                        while (i < body.len and body[i].tag == .dot) i += 1; // `$200.` trailing dot(s)
                        if (is_char) {
                            for (list.items[group_start..]) |*dv| {
                                dv.type = .char;
                                dv.len = declared_len;
                            }
                        } else {
                            for (list.items[group_start..]) |*dv| dv.len = declared_len; // numeric byte-length → truncate-on-store (GH#46)
                        }
                    } else if (eqi(opt, "label")) {
                        if (i < body.len and body[i].tag == .string) i += 1; // consume the label text
                    } else {
                        creates = true; // format=/informat= create the var
                        // BUG-attribfmttype: a `$` (character) spec with NO explicit
                        // length= types the group CHAR at the spec WIDTH (Language Reference: Concepts p.50
                        // Ex 4.1: `attrib Flavor format=$10.` → Char 10) — else the
                        // default-numeric seed here pre-empts declareStmt's char
                        // guess and a char assignment rots to missing.
                        if (!group_has_len) {
                            if (attribSpecCharWidth(body, i)) |w| {
                                for (list.items[group_start..]) |*dv| {
                                    dv.type = .char;
                                    dv.len = w;
                                }
                            }
                        }
                        i = skipFormatValue(body, i); // format=/informat= spec
                    }
                }
                if (!creates) {
                    list.shrinkRetainingCapacity(group_start); // label-only → don't seed type
                } else if (group_has_len) {
                    // BUG-lengthaftersetinput: the same p.49 note-1 guard the
                    // LENGTH branch runs — a char var already established by a
                    // prior assignment/INPUT keeps its first length; the ATTRIB
                    // length= is IGNORED + warns. (Only an explicit length= is a
                    // length re-specification — a format=$w. ATTACHES to an
                    // existing var silently, BUG-attribfmttype's pinned design.)
                    var k = group_start;
                    while (k < list.items.len) {
                        const dv = list.items[k];
                        if (dv.type == .char and dv.len > 0 and seenHas(seen.items, dv.name)) {
                            try diags.warn(0, "Length of character variable {s} has already been set. Use the LENGTH statement as the very first statement in the DATA STEP.", .{dv.name});
                            _ = list.orderedRemove(k);
                        } else k += 1;
                    }
                    try splitAfterSet(a, &list, group_start, saw_input);
                }
            }
            for (list.items[stmt_start..]) |*dv| dv.late = late; // BUG-varorder
            continue;
        }
        i += 1;
    }
    // A SET/MERGE step keeps the old pre-pass order for every declared var:
    // seedColumnsOf's GH#69/#70 type-conflict checks (and the lenient schema-pin)
    // need the LENGTH declaration in the PDV before the input columns are seeded.
    // BUG-lengthaftersetinput: EXCEPT the late copies splitAfterSet appended for
    // a char length declared AFTER the SET (char, after_input, len>0) — those
    // seed AFTER the source columns so exec's first-wins length guard sees the
    // carried source length, keeps it, and warns (Language Reference: Concepts p.49 note 1) instead of
    // truncating. The zero-len sentinels stay early (type check + PDV order).
    if (saw_input) for (list.items) |*dv| {
        dv.late = dv.type == .char and dv.len > 0 and dv.after_input;
    };
    return list.items;
}

/// BUG-lengthaftersetinput (QA tick356 F3, Language Reference: Concepts p.49 note 1): a CHAR length
/// declared AFTER a SET/MERGE/UPDATE/MODIFY must not truncate the length the
/// source already established — but this scan cannot know whether the source
/// carries the var, so each surviving decl in `start..` splits in two:
///   - the decl itself becomes a zero-len TYPE sentinel, still seeded EARLY —
///     the GH#70 fatal type check's declaredOf hit, the lenient schema-pin and
///     the pre-pass PDV position (output column order) are all unchanged, and a
///     var the source does NOT carry is still defined here;
///   - a late copy carrying the declared length, seeded AFTER the source
///     columns, where seedDeclVar's first-wins guard sees the carried length:
///     keeps it, warns, ignores the new one. For a NEW var the guard's len>0
///     test fails and the copy applies the declared length exactly as before.
/// The final `saw_input` pass in lengthVars routes the len>0 copies late.
fn splitAfterSet(a: std.mem.Allocator, list: *std.ArrayList(sas.exec.DeclVar), start: usize, saw_input: bool) !void {
    if (!saw_input) return;
    const end = list.items.len;
    var k = start;
    while (k < end) : (k += 1) {
        const dv = list.items[k];
        if (dv.type != .char or dv.len == 0) continue;
        try list.append(a, .{ .name = dv.name, .type = .char, .len = dv.len, .after_input = true });
        list.items[k].len = 0; // sentinel: type + PDV position only
    }
}

/// Width of a CHARACTER format/informat spec at `start` (`$` + name?/width) —
/// BUG-attribfmttype — or null when the spec is numeric (no leading `$`). Width
/// comes from the width number (`$10.` → 10) or the name's trailing digits
/// (`$char12.` → 12); no digits → 0 (no declared width, seedDeclVar keeps the
/// default). Mirrors skipFormatValue's token shape.
fn attribSpecCharWidth(body: []const Token, start: usize) ?usize {
    var i = start;
    if (i >= body.len or body[i].tag != .dollar) return null;
    i += 1;
    var width: usize = 0;
    if (i < body.len and body[i].tag == .name) {
        var d = body[i].text.len;
        while (d > 0 and std.ascii.isDigit(body[i].text[d - 1])) d -= 1;
        width = std.fmt.parseInt(usize, body[i].text[d..], 10) catch 0;
        i += 1;
    }
    if (i < body.len and body[i].tag == .number) {
        var d: usize = 0;
        while (d < body[i].text.len and std.ascii.isDigit(body[i].text[d])) d += 1;
        width = std.fmt.parseInt(usize, body[i].text[0..d], 10) catch 0;
    }
    return width;
}

/// `_numeric_`/`_character_`/`_all_` in a RETAIN/FORMAT list name no NEW variable
/// (they expand against the PDV later) — BUG-varorder's declaring-stmt scan.
fn isSpecialListName(name: []const u8) bool {
    return eqi(name, "_numeric_") or eqi(name, "_character_") or eqi(name, "_all_");
}

/// Case-insensitive membership test for GH#73's already-referenced-var list.
fn seenHas(names: []const []const u8, name: []const u8) bool {
    for (names) |n| if (eqi(n, name)) return true;
    return false;
}

/// Skip a FORMAT/INFORMAT value in an ATTRIB token scan: `[$]name[w][.[d]]` or
/// `[$]w.[d]`. Mirrors parser.tryFormatSpec so the scan stays aligned with the
/// next option or the next variable group. Always advances past the value.
fn skipFormatValue(body: []const Token, start: usize) usize {
    var i = start;
    if (i < body.len and body[i].tag == .dollar) i += 1;
    if (i < body.len and body[i].tag == .name) i += 1; // named format (best12, date9, …)
    if (i < body.len and body[i].tag == .number) i += 1; // width
    while (i < body.len and body[i].tag == .dot) i += 1;
    if (i < body.len and body[i].tag == .number) i += 1; // decimals
    if (i == start and i < body.len) i += 1; // safety: never stall on an odd value token
    return i;
}

/// The dataset a `proc sort` mutates IN PLACE: its `data=` name when there is no
/// distinct `out=` (out absent, or out= naming the same dataset). null when OUT=
/// names a different dataset (a copy, guarded by Library.put) or DATA= is omitted
/// (last-created dataset; ponytail: never a readonly disk input, not worth tracking).
fn sortInPlaceTarget(toks: []const Token) ?[]const u8 {
    var data_name: ?[]const u8 = null;
    var out_name: ?[]const u8 = null;
    var i: usize = 2; // past `proc sort`
    while (i < toks.len and toks[i].tag != .semicolon) : (i += 1) {
        if (i + 2 < toks.len and toks[i].tag == .name and toks[i + 1].tag == .eq and toks[i + 2].tag == .name) {
            if (eqi(toks[i].text, "data")) data_name = toks[i + 2].text else if (eqi(toks[i].text, "out")) out_name = toks[i + 2].text;
        }
    }
    const d = data_name orelse return null;
    if (out_name) |o| if (!eqi(o, d)) return null;
    return d;
}

/// Dispatch a `proc <name> …; … run;` step by name. Each proc hand-parses its
/// own tokens (parser.zig is A2's) — SORT lives in proc.zig; PRINT is below.
fn runProc(a: std.mem.Allocator, out: *std.ArrayList(u8), lib: *sas.exec.Library, diags: *sas.diag.Diagnostics, toks: []const Token, g: *Globals) sas.diag.Error!void {
    if (toks.len < 2 or toks[1].tag != .name) {
        failLoud("PROC name missing or unrecognized", .{});
        return;
    }
    const proc = toks[1].text;
    const pcx: sas.proc.ProcCtx = .{ .arena = a, .lib = lib, .diags = diags };
    // TITLE/FOOTNOTE print with the report procs (a listing), not with SORT or
    // TRANSPOSE (which produce a dataset, no page). Titles atop, footnotes below.
    // SUMMARY inverts MEANS: it lists (and so prints titles) only when PRINT is
    // given (BUG-summarydefaultprint).
    const listing = eqi(proc, "print") or eqi(proc, "means") or
        eqi(proc, "freq") or eqi(proc, "report") or eqi(proc, "tabulate") or eqi(proc, "compare") or
        eqi(proc, "univariate") or eqi(proc, "contents") or
        (eqi(proc, "summary") and procHasKw(toks, "print"));
    // BUG-byvaltitle: a TITLE/FOOTNOTE carrying #BYVAL/#BYVAR is re-resolved
    // per BY group, so PROC PRINT then owns its title/footnote emission
    // (substituted per group in printTable); otherwise titles stamp once here.
    const print_bysubst = eqi(proc, "print") and g.hasBySubst();
    if (listing and !print_bysubst) try g.emitTitles(a, out);

    if (eqi(proc, "sort")) {
        // GH#15: PROC SORT with no OUT= (or OUT= the source) sorts the source
        // IN PLACE — it mutates the dataset directly, never through Library.put,
        // so guard the read-only libref here. OUT= to a distinct member routes
        // through put and is caught there.
        if (sortInPlaceTarget(toks)) |src| if (lib.readonlyOut(src)) return lib.failReadonly(src);
        try sas.proc.runSort(pcx, toks);
    } else if (eqi(proc, "print")) {
        try printProc(a, out, lib, diags, toks, if (print_bysubst) g else null);
    } else if (eqi(proc, "means") or eqi(proc, "summary")) {
        try sas.proc.runMeans(pcx, out, toks);
    } else if (eqi(proc, "freq")) {
        try sas.proc.runFreq(pcx, out, toks);
    } else if (eqi(proc, "transpose")) {
        try sas.proc.runTranspose(pcx, toks);
    } else if (eqi(proc, "sql")) {
        try sas.sql.run(a, out, lib, diags, g, toks);
    } else if (eqi(proc, "report")) {
        try sas.proc.runReport(pcx, out, toks);
    } else if (eqi(proc, "tabulate")) {
        try sas.proc.runTabulate(pcx, out, toks);
    } else if (eqi(proc, "univariate")) {
        try sas.proc.runUnivariate(pcx, out, toks);
    } else if (eqi(proc, "rank")) {
        try sas.proc.runRank(pcx, out, toks);
    } else if (eqi(proc, "standard")) {
        try sas.proc.runStandard(pcx, toks);
    } else if (eqi(proc, "contents")) {
        try sas.proc.runContents(pcx, out, toks);
    } else if (eqi(proc, "format")) {
        try sas.proc.runFormat(pcx, toks);
    } else if (eqi(proc, "datasets")) {
        try sas.proc.runDatasets(pcx, out, toks);
    } else if (eqi(proc, "delete")) {
        try sas.proc.runDelete(pcx, toks);
    } else if (eqi(proc, "compare")) {
        try sas.proc.runCompare(pcx, out, toks);
    } else if (eqi(proc, "export")) {
        try sas.proc.runExport(pcx, toks);
    } else if (eqi(proc, "import")) {
        try sas.proc.runImport(pcx, toks);
    } else if (eqi(proc, "append")) {
        try sas.proc.runAppend(pcx, toks);
    } else if (eqi(proc, "printto")) {
        // PROC PRINTTO redirects the log/output destinations — irrelevant under
        // this harness (the runner captures stdout/stderr). A KNOWN, NAMED no-op
        // (both `printto log=...;` and bare `printto;`); the else below keeps
        // fail-loud INTACT for genuinely-unsupported PROCs (D-002 / GH#67).
        // ponytail: accepted-as-listing — opensas has one output stream, so a
        // redirection correctly leaves output on stdout.
    } else {
        failLoud("PROC {s} is not supported", .{proc});
    }

    if (listing and !print_bysubst) try g.emitFootnotes(a, out);
}

const PrintOpts = struct {
    noobs: bool = false,
    label: bool = false, // `proc print label;` (or a LABEL statement, or SPLIT=) → header shows labels
    nobyline: bool = false, // `proc print nobyline;` → suppress the BY-line header (system form: `options nobyline`, BUG-optionsstmtswallow)
    split: ?u8 = null, // `split='c'` → break header labels on c into multiple header lines
    vars: ?[]const []const u8 = null, // `var a b;` column select (in order)
    sums: ?[]const []const u8 = null, // `sum x;` totals
    by: ?[]const []const u8 = null, // `by g;` — section the listing per BY group
    id: ?[]const []const u8 = null, // `id v;` — v replaces the `Obs` column as the leftmost row identifier (F1)
    // per-print label overrides from a `label v="text";` statement (parallel arrays).
    lbl_names: ?[]const []const u8 = null,
    lbl_texts: ?[]const []const u8 = null,
    // per-print format overrides from a `format v fmt.;` statement (parallel arrays).
    fmt_names: ?[]const []const u8 = null,
    fmt_specs: ?[]const []const u8 = null,

    /// The header text for column `c`: the per-print override, else the column's
    /// stored label, else the name — only when label mode is on (F-printlabel).
    fn header(self: PrintOpts, c: Column) []const u8 {
        if (!self.label) return c.name;
        if (self.lbl_names) |names| for (names, self.lbl_texts.?) |n, t|
            if (eqi(n, c.name)) return t;
        return c.label orelse c.name;
    }

    /// The render format for column `c`: the per-print FORMAT-statement override,
    /// else the column's stored format (BUG-printfmtstmt).
    fn fmtFor(self: PrintOpts, c: Column) ?[]const u8 {
        if (self.fmt_names) |names| for (names, self.fmt_specs.?) |n, f|
            if (eqi(n, c.name)) return f;
        return c.format;
    }
};

const Just = enum { left, right };
const gutter = 3; // blank columns between fields

/// PROC PRINT: `proc print [data=NAME] [noobs]; [var a b;] [sum x;] run;`.
/// ponytail: only these options/statements; anything else on the line is skipped.
fn printProc(a: std.mem.Allocator, out: *std.ArrayList(u8), lib: *sas.exec.Library, diags: *sas.diag.Diagnostics, toks: []const Token, g: ?*const Globals) !void {
    var target: ?[]const u8 = null;
    var opts: PrintOpts = .{};
    var vlist: std.ArrayList([]const u8) = .empty;
    var slist: std.ArrayList([]const u8) = .empty;
    var blist: std.ArrayList([]const u8) = .empty;
    var ilist: std.ArrayList([]const u8) = .empty;

    // PROC statement options, up to its `;`
    var i: usize = 2;
    while (i < toks.len and toks[i].tag != .semicolon) {
        if (toks[i].tag == .name and eqi(toks[i].text, "data") and i + 2 < toks.len and toks[i + 1].tag == .eq) {
            target = toks[i + 2].text;
            i += 3;
            // Skip a dataset-option group `data=d(obs=3 where=…)`: procInput
            // re-scans it, and the header loop must not read `obs`/`where` inside
            // the parens as PROC PRINT options (they'd trip the F4 fail-loud).
            if (i < toks.len and toks[i].tag == .lparen) _ = skipParens(toks, &i);
            continue;
        }
        if (toks[i].tag == .name and eqi(toks[i].text, "noobs")) {
            opts.noobs = true;
            i += 1;
            continue;
        }
        if (toks[i].tag == .name and eqi(toks[i].text, "label")) {
            opts.label = true; // header shows labels
            i += 1;
            continue;
        }
        // `split='c'`: c breaks each column header label into multiple header
        // lines (GAP-printsplit). Must be exactly one character. SAS: SPLIT=
        // IMPLIES label mode (tick274 F5) — the ubiquitous `split='/'` idiom
        // never writes `label`, and headers must come from labels.
        if (toks[i].tag == .name and eqi(toks[i].text, "split") and i + 2 < toks.len and toks[i + 1].tag == .eq and toks[i + 2].tag == .string) {
            const s = toks[i + 2].text;
            if (s.len != 1) {
                failLoud("PROC PRINT SPLIT= must be a single character", .{});
                return;
            }
            opts.split = s[0];
            opts.label = true;
            i += 3;
            continue;
        }
        if (toks[i].tag == .name and eqi(toks[i].text, "nobyline")) {
            opts.nobyline = true;
            i += 1;
            continue;
        }
        // F4 (D-002): an unrecognized PROC PRINT option is a typo or a real-but-
        // unsupported option (DOUBLE/N/OBS='…'/WIDTH=…). Silently swallowing it
        // hid the same typo class as F3 → fail loud, don't no-op. ponytail:
        // DOUBLE/N/OBS= are real SAS options; wire one up here when a program needs it.
        if (toks[i].tag == .name) {
            failLoud("PROC PRINT option {s} is not supported", .{toks[i].text});
            return;
        }
        i += 1;
    }
    // sub-statements until `run`
    var lnames: std.ArrayList([]const u8) = .empty;
    var ltexts: std.ArrayList([]const u8) = .empty;
    var fnames: std.ArrayList([]const u8) = .empty;
    var fspecs: std.ArrayList([]const u8) = .empty;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag != .name) continue;
        if (eqi(toks[i].text, "run")) break;
        // `where <expr>;` is evaluated by procInput below; skip its tokens here
        // so a var/sum/id/by/label/format-named COLUMN inside the predicate isn't
        // mistaken for a sub-statement (BUG-printwherekw, qa-findings-tick142).
        if (eqi(toks[i].text, "where")) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
            continue;
        }
        if (eqi(toks[i].text, "var")) {
            try collectNames(a, toks, &i, &vlist);
            continue;
        }
        if (eqi(toks[i].text, "sum")) {
            try collectNames(a, toks, &i, &slist);
            continue;
        }
        if (eqi(toks[i].text, "id")) {
            try collectNames(a, toks, &i, &ilist);
            continue;
        }
        if (eqi(toks[i].text, "by")) {
            // shared PROC BY scanner (PROCBY-printfreq; 2363dc7 family) —
            // DESCENDING/NOTSORTED accepted via parser.scanByList since
            // GAP-procbydescending; decoded at the printTable BY block.
            try sas.proc.parseProcBy(a, diags, toks, &i, &blist);
            continue;
        }
        // `label v="text" w='...';` — per-print label overrides; also turns label
        // mode ON (SAS applies the labels a PROC PRINT LABEL statement defines).
        if (eqi(toks[i].text, "label")) {
            i += 1;
            while (i + 2 < toks.len and toks[i].tag == .name and toks[i + 1].tag == .eq and toks[i + 2].tag == .string) {
                try lnames.append(a, toks[i].text);
                try ltexts.append(a, toks[i + 2].text);
                i += 3;
            }
            opts.label = true;
            continue;
        }
        // `format v1 v2 fmt1 v3 fmt2 …;` — per-print format overrides; a format
        // applies to every var named since the previous one (SAS shape, mirrors
        // parser.parseFormatList). A var never given a format, or any other
        // token shape, fails loud (D-002) — never silently skipped
        // (BUG-printfmtstmt).
        if (eqi(toks[i].text, "format")) {
            var pending: std.ArrayList([]const u8) = .empty; // vars awaiting a format
            i += 1;
            while (i < toks.len and toks[i].tag != .semicolon) {
                if (try fmtSpecToks(a, toks, &i)) |spec| {
                    for (pending.items) |vn| {
                        try fnames.append(a, vn);
                        try fspecs.append(a, spec);
                    }
                    pending.clearRetainingCapacity();
                } else if (toks[i].tag == .name) {
                    try pending.append(a, toks[i].text);
                    i += 1;
                } else {
                    failLoud("unexpected token in FORMAT statement", .{});
                    return;
                }
            }
            if (pending.items.len > 0) {
                failLoud("FORMAT statement: no format specified for variable {s}", .{pending.items[pending.items.len - 1]});
                return;
            }
            continue;
        }
        // Global statements are legal mid-PROC. Skip exactly what the top
        // level HANDLES there (D-014a, parser.isMidStepSkippable): a hoisted
        // TITLE/FOOTNOTE/OPTIONS/FILENAME/ODS was already EXECUTED by the
        // driver (main.segments hoists it to a global segment BEFORE this
        // step — BUG-filenamemidstep), and an inert statement (GOPTIONS/DM/
        // SASFILE/PAGE/…) is unobservable — skipping either is honest
        // (GAP-globalpredicatemismatch: this used to be isGlobalKw, which
        // ALSO skipped ODS/LIBNAME/FILENAME when they were never hoisted —
        // a silent no-op — while erroring on the inert set top level
        // accepts, asserting the same statement is both harmless and fatal).
        // LIBNAME is skipped too: it EXECUTED in the up-front parseLibnames
        // pre-pass (BUG-libnamemidstepboth — it both ran and errored).
        // Unknown statements hit the fail-loud below.
        // BUG-printprintglobalargs: skip the WHOLE statement to its `;` — a
        // global stmt may carry name-token args (`title j=c "x"`, `options
        // nodate`), and those args would otherwise fall to the fail-loud below.
        if (sas.parser.isMidStepSkippable(toks[i].text)) {
            while (i < toks.len and toks[i].tag != .semicolon) i += 1;
            continue;
        }
        // Real-but-unimplemented PROC PRINT statements get their own loud gap.
        if (eqi(toks[i].text, "sumby") or eqi(toks[i].text, "pageby")) {
            failLoud("PROC PRINT statement {s} is not supported yet", .{toks[i].text});
            return;
        }
        // BUG-printsubstmtsilent: anything else is a typo (`vae x;`) — fail
        // loud naming it, matching the PROC-line options behavior.
        failLoud("PROC PRINT statement {s} is not supported", .{toks[i].text});
        return;
    }
    if (vlist.items.len > 0) opts.vars = vlist.items;
    if (slist.items.len > 0) opts.sums = slist.items;
    if (blist.items.len > 0) opts.by = blist.items;
    if (ilist.items.len > 0) opts.id = ilist.items;
    if (lnames.items.len > 0) {
        opts.lbl_names = lnames.items;
        opts.lbl_texts = ltexts.items;
    }
    if (fnames.items.len > 0) {
        opts.fmt_names = fnames.items;
        opts.fmt_specs = fspecs.items;
    }

    const ds = if (target) |n| lib.find(n) else lastDataset(lib);
    if (ds == null) {
        // DEC-abortrcvsD009: rc 1. Both arms are the user's error in real-SAS
        // terms — a named set that is not there ("File WORK.X.DATA does not
        // exist", exec.zig's rc-1 twin) or `proc print;` with no _LAST_ ("No
        // data set open to look up variables"). PROC PRINT itself is supported,
        // so nothing here is an opensas gap; and if an EARLIER step hit a real
        // gap, its rc 2 already outranks this (diag.exitCode).
        userErr(diags, "PROC PRINT with no dataset", .{});
        return;
    }
    // GAP-varcolonprefix: expand `pfx:` entries now that the dataset is known
    // (PDV order — see expandVarList). Serves var/id/sum alike; BY is not a
    // variable-list statement here (scanByList owns its wire form).
    const pcols = ds.?.columns.items;
    if (opts.vars) |vs| opts.vars = try expandVarList(a, pcols, vs, diags) orelse return;
    if (opts.sums) |ss| opts.sums = try expandVarList(a, pcols, ss, diags) orelse return;
    if (opts.id) |ids| opts.id = try expandVarList(a, pcols, ids, diags) orelse return;
    // NOTE-fmtnumoncharcoerce: the PROC-step FORMAT statement gets the same
    // compile-time type check as the DATA step's (exec.declareStmt) — a
    // numeric format on a char column (or a `$` on numeric) silently coerced
    // the cell to '.' at render (exit 0). Fail BEFORE any output is produced.
    for (fnames.items, fspecs.items) |vn, fspec| {
        const ci = ds.?.indexOf(vn) orelse continue; // unknown var: printTable's existing behavior stands
        if (fspec.len == 0) continue; // `format v;` disassociates — no type to conflict
        const col_char = ds.?.columns.items[ci].type == .char;
        if (col_char == sas.format.specIsChar(fspec)) continue;
        // DEC-abortrcvsD009: rc 1, matching the THREE sites already emitting this
        // byte-identical message at rc 1 (exec.zig:1515/1517 declareStmt,
        // proc.zig:2394). It is SAS's own ERROR text for a program whose FORMAT
        // statement contradicts the column's type — the user's SAS is wrong.
        if (col_char)
            userErr(diags, "The numeric format {s} cannot be used with character variable {s}.", .{ fspec, vn })
        else
            userErr(diags, "The character format {s} cannot be used with numeric variable {s}.", .{ fspec, vn });
        return;
    }
    // Honour a `where <expr>;` statement or `data=NAME(where=…)` option (BUG-procwhere).
    // srcobs carries each surviving row's physical SOURCE obs number so the Obs
    // column doesn't renumber 1..n over the subset (BUG-printobsnum).
    // BUG-byvaltitle: with a BY statement and a #BYVAL/#BYVAR title/footnote,
    // printTable re-resolves the lines per BY group; otherwise PRINT stamps
    // them exactly where runProc would (atop the listing / below the table).
    const per_group = g != null and opts.by != null;
    if (g != null and !per_group) try g.?.emitTitles(a, out);
    const pin = try sas.proc.procInputObs(a, ds.?, toks, diags);
    try printTable(a, out, pin.ds, pin.srcobs, opts, diags, if (per_group) g.? else null);
    if (g != null and !per_group) try g.?.emitFootnotes(a, out);
}

/// Collect the `.name` tokens of a `var`/`sum`/`id` list, leaving `i` on its
/// `;`. A name directly followed by `:` is kept as one "pfx:" entry — the
/// DROP/KEEP parseNameList model (GAP-dropcolon) — for expandVarList
/// (GAP-varcolonprefix); a bare colon never survives token-skipping into a name.
fn collectNames(a: std.mem.Allocator, toks: []const Token, i: *usize, list: *std.ArrayList([]const u8)) !void {
    i.* += 1; // skip the keyword
    while (i.* < toks.len and toks[i.*].tag != .semicolon) : (i.* += 1) {
        if (toks[i.*].tag != .name) continue;
        if (i.* + 1 < toks.len and toks[i.* + 1].tag == .colon) {
            try list.append(a, try std.fmt.allocPrint(a, "{s}:", .{toks[i.*].text}));
            i.* += 1; // consume the colon
        } else try list.append(a, toks[i.*].text);
    }
}

/// GAP-varcolonprefix: expand any "pfx:" entries (collectNames' wire form) in
/// a var/id/sum list against the dataset's columns, case-insensitively, in PDV
/// order — Language Reference: Concepts printed p.62: a variable list refers to its variables "in the
/// same order that SAS uses to keep track of the variables", and p.69's own
/// Example 7 puts a variable list in PROC PRINT's VAR statement (the prefix
/// form is defined beside it). PROC PRINT's VAR entry (procedures guide
/// printed pp.1784-1785) restricts nothing: `VAR variable(s)`. One expansion
/// point, so printTable's resolution/dedup/totals see only plain names. A
/// prefix matching NO column is a typo'd prefix — the SAME loud rc-1
/// "Variable X not found." as an unknown name (Table 4.5 settles only the
/// matching rule; GAP-ofcolonprefix's empty-match arm is the precedent, and
/// both sites now agree). Returns null with the diag already reported.
fn expandVarList(a: std.mem.Allocator, cols: []const Column, names: []const []const u8, diags: *sas.diag.Diagnostics) !?[]const []const u8 {
    var out: std.ArrayList([]const u8) = .empty;
    for (names) |n| {
        if (n.len > 0 and n[n.len - 1] == ':') {
            var matched = false;
            for (cols) |c| {
                if (std.ascii.startsWithIgnoreCase(c.name, n[0 .. n.len - 1])) {
                    try out.append(a, c.name);
                    matched = true;
                }
            }
            if (!matched) {
                varNotFound(a, diags, n);
                return null;
            }
        } else try out.append(a, n);
    }
    return out.items;
}

/// If the tokens at `*i` spell a format spec (`[$]name[w][.[d]]` or `[$]w.[d]`),
/// consume them, return the reconstructed spec string, and advance `*i`;
/// otherwise consume nothing and return null. Token-stream mirror of
/// parser.tryFormatSpec (specs tokenize unevenly — `8.2` is one number,
/// `comma10.2` is name+".2", `date9.` is name+dot — so stitch the pieces back).
fn fmtSpecToks(a: std.mem.Allocator, toks: []const Token, i: *usize) !?[]const u8 {
    var j = i.*;
    var buf: std.ArrayList(u8) = .empty;
    if (j < toks.len and toks[j].tag == .dollar) {
        try buf.append(a, '$');
        j += 1;
    }
    if (j < toks.len and toks[j].tag == .name) {
        // a name belongs to a format only when a dot / dotted-number follows it
        // (a plain name is the next variable, not a format).
        const nx = if (j + 1 < toks.len) toks[j + 1] else toks[j]; // no eof guarantee in a step slice
        const name_is_fmt = nx.tag == .dot or (nx.tag == .number and nx.text.len > 0 and nx.text[0] == '.');
        if (buf.items.len > 0 or name_is_fmt) {
            try buf.appendSlice(a, toks[j].text);
            j += 1;
        } else if (buf.items.len == 0) return null; // bare name → not a format
    }
    if (j < toks.len and toks[j].tag == .number) {
        try buf.appendSlice(a, toks[j].text);
        j += 1;
    }
    if (j < toks.len and toks[j].tag == .dot) {
        try buf.append(a, '.');
        j += 1;
    }
    if (buf.items.len == 0) return null;
    i.* = j;
    return buf.items;
}

fn lastDataset(lib: *sas.exec.Library) ?*sas.dataset.Dataset {
    const n = lib.sets.items.len;
    return if (n == 0) null else lib.sets.items[n - 1];
}

/// Aligned listing: an optional `Obs` column then the selected variables, char
/// left-justified, numeric right-justified, `gutter` blanks between, a blank
/// line under the header, and an `====`/total footer per summed column.
fn printTable(a: std.mem.Allocator, out: *std.ArrayList(u8), ds: *sas.dataset.Dataset, srcobs: ?[]const usize, opts_in: PrintOpts, diags: *sas.diag.Diagnostics, titles: ?*const Globals) !void {
    var opts = opts_in; // mutable: `id` suppresses the Obs column below
    const cols = ds.columns.items;
    const nrows = ds.rowCount();
    std.debug.assert(srcobs == null or srcobs.?.len == nrows); // one source number per surviving row

    // selected column indices. F1: `id` variables render leftmost and REPLACE the
    // Obs column; then the `var` list (in its order), else every column. F3
    // (D-002): a var naming no column is a typo that would silently drop data →
    // fail loud and stop the step (SAS: "Variable X not found.").
    var sel: std.ArrayList(usize) = .empty;
    if (opts.id) |ids| {
        opts.noobs = true; // ID takes the place of Obs
        for (ids) |vn| {
            const j = resolveCol(cols, vn) orelse return varNotFound(a, diags, vn);
            try sel.append(a, j);
        }
    }
    if (opts.vars) |vs| {
        for (vs) |vn| {
            const j = resolveCol(cols, vn) orelse return varNotFound(a, diags, vn);
            // tick274 F4: SAS KEEPS a repeated column — an ID∩VAR overlap prints
            // the variable twice (ID statement doc), and a duplicated VAR entry
            // too (VAR is positional, no dedup). Only the no-VAR branch below
            // dedups (ID var must not reappear among "all remaining columns").
            try sel.append(a, j);
        }
    } else for (cols, 0..) |_, j| {
        if (!containsIdx(sel.items, j)) try sel.append(a, j);
    }
    // BUG-printsumnotinvar: a SUM var not already displayed (VAR/ID) is auto-
    // ADDED by SAS, appended after the VAR columns — else its column and grand
    // total silently vanish (blank total lines, rc 0).
    if (opts.sums) |ss| for (ss) |sn| {
        const j = resolveCol(cols, sn) orelse return varNotFound(a, diags, sn);
        if (!containsIdx(sel.items, j)) try sel.append(a, j);
    };
    const sidx = sel.items;

    // column widths = max(header, every rendered cell); plus the Obs width.
    var colw = try a.alloc(usize, sidx.len);
    for (sidx, 0..) |cj, k| colw[k] = headerWidth(cols[cj], opts); // label width when label mode is on
    var w_obs: usize = "Obs".len;
    var r: usize = 0;
    while (r < nrows) : (r += 1) {
        if (!opts.noobs) w_obs = @max(w_obs, (try std.fmt.allocPrint(a, "{d}", .{obsNum(srcobs, r)})).len);
        const rv = ds.row(r);
        for (sidx, 0..) |cj, k| colw[k] = @max(colw[k], (try fmtCell(a, rv[cj], opts.fmtFor(cols[cj]))).len);
    }

    // per-column totals for the `sum` list, widened to fit the rendered total.
    var totals = try a.alloc(?f64, sidx.len);
    for (totals) |*t| t.* = null;
    if (opts.sums) |ss| for (sidx, 0..) |cj, k| {
        for (ss) |sn| if (eqi(cols[cj].name, sn)) {
            // F2 (D-002): summing a character column produced a bogus `0`/`====`;
            // SAS rejects it. Report a user ERROR (rc=1) instead of a fake total.
            if (cols[cj].type == .char) {
                try diags.report(.err, 0, "Variable {s} in list does not match type prescribed for this list.", .{std.ascii.allocUpperString(a, cols[cj].name) catch cols[cj].name});
                return;
            }
            var acc: f64 = 0;
            r = 0;
            while (r < nrows) : (r += 1) switch (ds.row(r)[cj]) {
                .num => |x| if (std.math.isFinite(x)) { // skip missing (NaN) and ±inf
                    acc += x;
                },
                .str => {},
            };
            totals[k] = acc;
            colw[k] = @max(colw[k], (try fmtCell(a, .{ .num = acc }, opts.fmtFor(cols[cj]))).len);
            break;
        };
    };

    // With BY: one section per contiguous BY group — a BY-line header, the
    // group's own column header + rows, and (with SUM) a per-group subtotal —
    // then a grand total. Without BY: one flat section (the original layout).
    if (opts.by) |bys| {
        // GAP-procbydescending: parseProcBy emits scanByList's wire encoding —
        // decode once for clean names, per-key directions and NOTSORTED.
        const pb = try sas.proc.decodeProcBy(a, bys);
        // BUG-byvarnotfound: BY resolution had no not-found branch — a typo'd
        // BY var was silently dropped (flat listing, empty BY line, rc 0).
        // Same loud "Variable X not found." as the VAR/SUM/ID resolvers (F3).
        var bcols: std.ArrayList(usize) = .empty;
        for (pb.names) |bn| try bcols.append(a, resolveCol(cols, bn) orelse return varNotFound(a, diags, bn));
        // BUG-printbyunsorted: BY demands sorted data. A backward step between
        // groups (which any repeated non-adjacent key forces) errors like SAS
        // instead of emitting duplicate sections — per key under BY DESCENDING
        // (GAP-procbydescending); BY NOTSORTED drops the check.
        var g0: usize = 0;
        var prev_g: usize = 0;
        var gfirst = true;
        while (g0 < nrows) {
            if (!gfirst and !pb.notsorted) if (byRowOrderViolation(ds, g0, prev_g, bcols.items, pb.desc)) |k| {
                // DEC-abortrcvsD009: rc 1, matching the SIX proc.zig sites that
                // emit this byte-identical message at rc 1 (1411/4013/5501/6174/
                // 6363/8010). Probed pre-fix: the same one-line log gave rc 2 from
                // `proc print; by x;` and rc 1 from `proc means; by x;`.
                userErr(diags, "Data set {s} is not sorted in {s} sequence.", .{ ds.name, if (pb.desc[k]) "descending" else "ascending" });
                return;
            };
            gfirst = false;
            prev_g = g0;
            g0 += 1;
            while (g0 < nrows and byRowsEqual(ds, prev_g, g0, bcols.items)) g0 += 1;
        }
        // BUG-byvaltitle: #BYVAL/#BYVAR substitution context, in BY order —
        // #BYVAR prefers the label, #BYVAL takes the group's formatted value
        // (filled per group below; same render as the BY line).
        var byvars: ?[]Globals.ByVar = null;
        if (titles) |g| {
            const bvs = try a.alloc(Globals.ByVar, bcols.items.len);
            for (bcols.items, 0..) |bj, k| bvs[k] = .{
                .name = cols[bj].name,
                .label = cols[bj].label orelse cols[bj].name,
                .value = "",
            };
            byvars = bvs;
            if (nrows == 0) { // no group to resolve against: stamp literally, as before
                try g.emitTitles(a, out);
                try g.emitFootnotes(a, out);
            }
        }
        var start: usize = 0;
        var first = true;
        while (start < nrows) {
            var end = start + 1;
            while (end < nrows and byRowsEqual(ds, start, end, bcols.items)) end += 1;
            if (!first) try out.append(a, '\n'); // blank line between groups
            first = false;
            if (byvars) |bvs| {
                for (bcols.items, 0..) |bj, k| bvs[k].value = try fmtCell(a, ds.row(start)[bj], opts.fmtFor(cols[bj]));
                try titles.?.emitTitlesBy(a, out, bvs);
            }
            try printByLine(a, out, ds, start, cols, bcols.items, opts);
            try printHeader(a, out, cols, sidx, colw, w_obs, opts);
            var rr = start;
            while (rr < end) : (rr += 1) try printDataRow(a, out, ds, rr, srcobs, cols, sidx, colw, w_obs, opts);
            if (opts.sums != null)
                try printTotalsRow(a, out, try rangeTotals(a, ds, cols, sidx, opts.sums.?, start, end), cols, sidx, colw, w_obs, opts);
            if (byvars) |bvs| try titles.?.emitFootnotesBy(a, out, bvs);
            start = end;
        }
        if (opts.sums != null and nrows > 0) { // grand total across all groups
            try out.append(a, '\n');
            try printTotalsRow(a, out, totals, cols, sidx, colw, w_obs, opts);
        }
        return;
    }

    try printHeader(a, out, cols, sidx, colw, w_obs, opts);
    r = 0;
    while (r < nrows) : (r += 1) try printDataRow(a, out, ds, r, srcobs, cols, sidx, colw, w_obs, opts);
    // BUG-print0obssum: 0 obs → SAS prints no table/total ("No observations"
    // NOTE). The bare header stays (tick155 decision); only the phantom
    // `= 0` grand total is suppressed.
    if (opts.sums != null and nrows > 0)
        try printTotalsRow(a, out, totals, cols, sidx, colw, w_obs, opts);
}

const Column = sas.dataset.Column;

/// A header's width contribution: its full text, or the widest piece under SPLIT=.
fn headerWidth(c: Column, opts: PrintOpts) usize {
    const h = opts.header(c);
    const sc = opts.split orelse return h.len;
    var w: usize = 0;
    var it = std.mem.splitScalar(u8, h, sc);
    while (it.next()) |p| w = @max(w, p.len);
    return w;
}

/// The column-name header block, then a blank line under it. Under SPLIT= the
/// block is one row per header piece: labels break on the split char (the char
/// is consumed), labels without it sit on the bottom row.
fn printHeader(a: std.mem.Allocator, out: *std.ArrayList(u8), cols: []const Column, sidx: []const usize, colw: []const usize, w_obs: usize, opts: PrintOpts) !void {
    // per-column header pieces; one block row per max piece count
    var pieces = try a.alloc([]const []const u8, sidx.len);
    var rows: usize = 1;
    for (sidx, 0..) |cj, k| {
        var list: std.ArrayList([]const u8) = .empty;
        if (opts.split) |sc| {
            var it = std.mem.splitScalar(u8, opts.header(cols[cj]), sc);
            while (it.next()) |p| try list.append(a, p);
        } else try list.append(a, opts.header(cols[cj]));
        pieces[k] = list.items;
        rows = @max(rows, list.items.len);
    }
    var r: usize = 0;
    while (r < rows) : (r += 1) {
        var line: std.ArrayList(u8) = .empty;
        if (!opts.noobs) try cell(a, &line, if (r == rows - 1) "Obs" else "", w_obs, .right, true);
        for (sidx, 0..) |cj, k| {
            const j: Just = if (cols[cj].type == .char) .left else .right;
            const pk = pieces[k];
            // this column's piece on row r (bottom-aligned), "" above it
            const txt = if (r >= rows - pk.len) pk[r - (rows - pk.len)] else "";
            try cell(a, &line, txt, colw[k], j, opts.noobs and k == 0);
        }
        try flushLine(a, out, &line);
    }
    try out.append(a, '\n');
}

/// The Obs-column value for printed row `r`: the row's physical source
/// observation number when the input was subset (BUG-printobsnum), else `r`+1.
fn obsNum(srcobs: ?[]const usize, r: usize) usize {
    return if (srcobs) |l| l[r] else r + 1;
}

/// One data row: `Obs` (the source obs number) then the selected cells.
fn printDataRow(a: std.mem.Allocator, out: *std.ArrayList(u8), ds: *sas.dataset.Dataset, r: usize, srcobs: ?[]const usize, cols: []const Column, sidx: []const usize, colw: []const usize, w_obs: usize, opts: PrintOpts) !void {
    var line: std.ArrayList(u8) = .empty;
    const rv = ds.row(r);
    if (!opts.noobs) try cell(a, &line, try std.fmt.allocPrint(a, "{d}", .{obsNum(srcobs, r)}), w_obs, .right, true);
    for (sidx, 0..) |cj, k| {
        const j: Just = if (cols[cj].type == .char) .left else .right;
        try cell(a, &line, try fmtCell(a, rv[cj], opts.fmtFor(cols[cj])), colw[k], j, opts.noobs and k == 0);
    }
    try flushLine(a, out, &line);
}

/// The `====` underline then the totals row, for the summed columns.
fn printTotalsRow(a: std.mem.Allocator, out: *std.ArrayList(u8), totals: []const ?f64, cols: []const Column, sidx: []const usize, colw: []const usize, w_obs: usize, opts: PrintOpts) !void {
    var line: std.ArrayList(u8) = .empty;
    if (!opts.noobs) try pad(a, &line, w_obs);
    for (sidx, 0..) |_, k| {
        if (!(opts.noobs and k == 0)) try pad(a, &line, gutter);
        if (totals[k] != null) try repeat(a, &line, '=', colw[k]) else try pad(a, &line, colw[k]);
    }
    try flushLine(a, out, &line);
    line.clearRetainingCapacity();
    if (!opts.noobs) try pad(a, &line, w_obs);
    for (sidx, 0..) |cj, k| {
        if (!(opts.noobs and k == 0)) try pad(a, &line, gutter);
        if (totals[k]) |tot|
            try cellText(a, &line, try fmtCell(a, .{ .num = tot }, opts.fmtFor(cols[cj])), colw[k], .right)
        else
            try pad(a, &line, colw[k]);
    }
    try flushLine(a, out, &line);
}

/// The BY-group section header: `var=value …` from `row`, then a blank line.
fn printByLine(a: std.mem.Allocator, out: *std.ArrayList(u8), ds: *sas.dataset.Dataset, row: usize, cols: []const Column, bcols: []const usize, opts: PrintOpts) !void {
    if (sas.io.global_nobyline or opts.nobyline) return; // `options nobyline;` (BUG-optionsstmtswallow) / `proc print nobyline;` (tick274)
    var line: std.ArrayList(u8) = .empty;
    for (bcols, 0..) |bj, k| {
        if (k > 0) try line.append(a, ' ');
        try line.appendSlice(a, cols[bj].name);
        try line.append(a, '=');
        try line.appendSlice(a, try fmtCell(a, ds.row(row)[bj], opts.fmtFor(cols[bj])));
    }
    try flushLine(a, out, &line);
    try out.append(a, '\n');
}

/// Do rows `i` and `j` share every BY-column value? (char blank-padded).
fn byRowsEqual(ds: *sas.dataset.Dataset, i: usize, j: usize, bcols: []const usize) bool {
    for (bcols) |bj| {
        const va = ds.row(i)[bj];
        const vb = ds.row(j)[bj];
        const eq = switch (va) {
            .num => |x| vb == .num and (vb.num == x or (std.math.isNan(x) and std.math.isNan(vb.num))),
            .str => |s| vb == .str and std.mem.eql(u8, std.mem.trimEnd(u8, s, " "), std.mem.trimEnd(u8, vb.str, " ")),
        };
        if (!eq) return false;
    }
    return true;
}

/// The BY-key index where row `i`'s key steps BACKWARD from row `j`'s in the
/// BY-specified order — ascending per key, inverted under BY DESCENDING
/// (GAP-procbydescending; proc.byOrderViolation's twin, so PRINT and the
/// proc.zig PROCs apply the same rule) — else null. Equal keys continue.
/// (Storage order: missing lowest, char trimmed, binary.)
fn byRowOrderViolation(ds: *sas.dataset.Dataset, i: usize, j: usize, bcols: []const usize, descs: []const bool) ?usize {
    for (bcols, 0..) |bj, k| {
        const desc = k < descs.len and descs[k];
        const va = ds.row(i)[bj];
        const vb = ds.row(j)[bj];
        switch (va) {
            .num => |x| {
                const y = vb.num;
                const lt = if (std.math.isNan(x)) !std.math.isNan(y) else (!std.math.isNan(y) and x < y); // missing lowest
                const gt = if (std.math.isNan(y)) !std.math.isNan(x) else (!std.math.isNan(x) and x > y);
                if (lt) return if (desc) null else k;
                if (gt) return if (desc) k else null;
            },
            .str => |s| switch (std.mem.order(u8, std.mem.trimEnd(u8, s, " "), std.mem.trimEnd(u8, vb.str, " "))) {
                .lt => return if (desc) null else k,
                .gt => return if (desc) k else null,
                .eq => {},
            },
        }
    }
    return null;
}

/// Per-column totals of the summed columns over rows `[start, end)`.
fn rangeTotals(a: std.mem.Allocator, ds: *sas.dataset.Dataset, cols: []const Column, sidx: []const usize, sums: []const []const u8, start: usize, end: usize) ![]?f64 {
    const t = try a.alloc(?f64, sidx.len);
    for (t) |*x| x.* = null;
    for (sidx, 0..) |cj, k| for (sums) |sn| if (eqi(cols[cj].name, sn)) {
        var acc: f64 = 0;
        var r = start;
        while (r < end) : (r += 1) switch (ds.row(r)[cj]) {
            .num => |x| if (std.math.isFinite(x)) {
                acc += x;
            },
            .str => {},
        };
        t[k] = acc;
        break;
    };
    return t;
}

fn cell(a: std.mem.Allocator, line: *std.ArrayList(u8), text: []const u8, width: usize, j: Just, first: bool) !void {
    if (!first) try pad(a, line, gutter);
    try cellText(a, line, text, width, j);
}

fn cellText(a: std.mem.Allocator, line: *std.ArrayList(u8), text: []const u8, width: usize, j: Just) !void {
    const p = width -| text.len;
    if (j == .right) {
        try pad(a, line, p);
        try line.appendSlice(a, text);
    } else {
        try line.appendSlice(a, text);
        try pad(a, line, p);
    }
}

fn pad(a: std.mem.Allocator, line: *std.ArrayList(u8), n: usize) !void {
    for (0..n) |_| try line.append(a, ' ');
}

fn repeat(a: std.mem.Allocator, line: *std.ArrayList(u8), ch: u8, n: usize) !void {
    for (0..n) |_| try line.append(a, ch);
}

/// Append `line` with trailing blanks trimmed (a left-justified last column
/// would otherwise pad to the right edge) and a newline.
fn flushLine(a: std.mem.Allocator, out: *std.ArrayList(u8), line: *std.ArrayList(u8)) !void {
    try out.appendSlice(a, std.mem.trimEnd(u8, line.items, " "));
    try out.append(a, '\n');
}

/// Render a cell: apply the column's `format` (F1) when it has one, else the
/// compact default.
fn fmtCell(a: std.mem.Allocator, v: sas.Value, fmt: ?[]const u8) ![]const u8 {
    if (fmt) |spec| return sas.format.apply(a, v, spec);
    return fmtValue(a, v);
}

/// A value as SAS renders it: character verbatim, numeric through the ONE shared
/// BEST12. renderer (`format.bestNum`) — the same path `put` and `||` use — so a
/// computed value like `0.1+0.2` prints `0.3`, not the raw f64. (BUG-bestfmt: the
/// old per-callsite `{d}` here leaked full f64 precision into PROC PRINT.)
fn fmtValue(a: std.mem.Allocator, v: sas.Value) ![]const u8 {
    return switch (v) {
        .str => |s| s,
        // A PLAIN missing prints the OPTIONS MISSING= char (BUG-optmissing);
        // special missings (.A–.Z/._) keep their letter via bestNum.
        .num => |x| if (std.math.isNan(x) and sas.Value.missingChar(x) == '.')
            try std.fmt.allocPrint(a, "{c}", .{sas.io.global_missing})
        else
            try sas.format.bestNum(a, x),
    };
}

/// Ensure a token slice ends in `.eof` so the parser can peek past the end.
fn withEof(a: std.mem.Allocator, toks: []const Token) ![]Token {
    if (toks.len > 0 and toks[toks.len - 1].tag == .eof) return @constCast(toks);
    const out = try a.alloc(Token, toks.len + 1);
    @memcpy(out[0..toks.len], toks);
    out[toks.len] = .{ .tag = .eof };
    return out;
}

/// A bare keyword on the PROC statement (a name before the first `;`).
fn procHasKw(toks: []const Token, kw: []const u8) bool {
    for (toks[2..]) |tk| {
        if (tk.tag == .semicolon) break;
        if (tk.tag == .name and eqi(tk.text, kw)) return true;
    }
    return false;
}

fn eqi(x: []const u8, y: []const u8) bool {
    return std.ascii.eqlIgnoreCase(x, y);
}

/// GAP-gapsexitingone §5d — the closed documented sets behind the LIBNAME/
/// FILENAME/SORTSEQ catch-all splits: membership = documented valid SAS 9.4
/// opensas does not implement → the gap arm (rc 2); anything else = typo →
/// rc 1. Kept deliberately short: an exotic-but-valid name degrades to rc 1,
/// never a false rc 2.
fn isDocLibEngine(eng: []const u8) bool {
    // Base-product engines the Statements Ref names (the parseLibnames comment
    // cites p.221 for the stubs). SAS/ACCESS engines (ORACLE, …) are absent on
    // purpose — an unlicensed real SAS rejects those too, so they stay on the
    // rc-1 "cannot be found" arm.
    // BUG-rcsplitmembership F5: the VERSIONED base engines were missing. QA
    // flagged them as an open question because the Statements Ref's LIBNAME
    // section is a "has moved to SAS Global Statements" stub with no
    // engine-name value list — true, but the Procedures Guide settles it in two
    // places. (1) A worked LIBNAME statement uses V8 as the engine-name:
    // "libname MyLib v8 'source-library-pathname' shortfileext;" — printed
    // p.1577 (`=== pdf 1626 ===`), PROC MIGRATE, migrating a short-extension
    // library. (2) Overview: MIGRATE Procedure, printed p.1566 (`=== pdf 1615
    // ===`): "The migration must occur within the same engine family. For
    // example, V6, V7, or V8 can migrate to V9, but V6TAPE must migrate to
    // V9TAPE." — six engine names, of which V9 is already honoured as the BASE
    // alias, leaving the five below. Real SAS 9.4 FINDS all of them; opensas
    // implements only the V9/BASE on-disk format, so they are gaps (rc 2), not
    // "cannot be found" (rc 1).
    const list = [_][]const u8{ "json", "xml", "xmlv2", "xml92", "spde", "cvp", "jmp", "webdav", "v6", "v7", "v8", "v6tape", "v9tape" };
    for (list) |x| if (eqi(eng, x)) return true;
    return false;
}

fn isDocFilenameDevice(d: []const u8) bool {
    // BUG-rcsplitmembership F3 — RE-DERIVED IN FULL from the two enumerations
    // in the Statements reference, which the first cut of this list did
    // not read to the end (twelve documented names were missing, so real SAS
    // programs got rc 1 "fix your SAS"):
    //   (a) the `device-type` dictionary entries, printed pp.87-90 (FILE
    //       statement, `=== pdf 98-101 ===`) and printed pp.124-127 (INFILE
    //       statement, `=== pdf 135-138 ===`): ACTIVEMQ CATALOG CLIPBOARD DISK
    //       DUMMY FTP GTERM HADOOP JMS PIPE PLOTTER PRINTER SFTP SOCKET TAPE
    //       TERMINAL UPRINTER URL WEBDAV.
    //   (b) the FILENAME access-method sections, printed pp.108-111
    //       (`=== pdf 119-122 ===`): AZURE CATALOG CLIPBOARD DATAURL EMAIL
    //       (SMTP) FILESRVC FTP HADOOP S3 SFTP SOCKET URL WEBDAV ZIP.
    // DISK is honoured at the call site, so it is absent here on purpose.
    // TEMP and DDE appear in NEITHER enumeration — in fact in none of the eight
    // extracted volumes — but they are kept: they are real device types
    // documented in SAS Global Statements / the host companions (this volume's
    // FILENAME section is a "has moved to SAS Global Statements" stub, and both
    // device-type lists close with "Values in addition to the ones listed here
    // might be available in some operating environments").  Keeping a
    // possibly-real name on the gap arm costs a spurious "file an opensas
    // issue"; dropping it would cost a real SAS program a bogus rc 1, which is
    // the failure this ticket exists to remove.  D-015 removals are made only
    // where the doc EXCLUDES the value outright, as it does for F2's LINGUISTIC.
    const list = [_][]const u8{
        "activemq", "catalog", "clipboard", "dummy",    "ftp",      "gterm", "hadoop",
        "jms",      "pipe",    "plotter",   "printer",  "sftp",     "socket", "tape",
        "terminal", "uprinter", "url",      "webdav",   "azure",    "dataurl", "email",
        "filesrvc", "s3",      "zip",       "temp",     "dde",
    };
    for (list) |x| if (eqi(d, x)) return true;
    return false;
}

fn isDocRecfm(v: []const u8) bool {
    // Documented record forms (V is honoured, inert, at the call site).
    const list = [_][]const u8{ "f", "n", "p", "vb", "vs", "vbs", "u", "d" };
    for (list) |x| if (eqi(v, x)) return true;
    return false;
}

fn isUnimplSortseq(v: []const u8) bool {
    // BUG-rcsplitmembership F4 — RE-DERIVED IN FULL from the one sentence that
    // enumerates them, Base SAS 9.4 Procedures Guide printed p.2410
    // (`=== pdf 2459 ===`), SORTSEQ=collating-sequence: "specifies one of the
    // PROC SORT statement collating-sequence-options (ASCII, DANISH, EBCDIC,
    // FINNISH, NORWEGIAN, REVERSE, SWEDISH) or a translation table … Translation
    // tables provided by SAS are: ASCII, DANISH, EBCDIC, FINNISH, ITALIAN,
    // NORWEGIAN, POLISH, REVERSE, SPANISH, and SWEDISH."  The union of the two
    // lists is the ten below; the previous enumeration held five of them, so
    // ITALIAN/POLISH/SPANISH/REVERSE were called typos (rc 1) though real SAS
    // runs them.  ASCII is the tenth and is deliberately NOT here: it is
    // opensas's actual collation, honoured at the call site (rc 0) — a
    // supported value, not a gap.  LINGUISTIC is likewise absent on purpose:
    // p.2415 excludes it from the SYSTEM option outright (F2), so it belongs on
    // the rc-1 typo arm, not here.
    const list = [_][]const u8{ "ebcdic", "danish", "finnish", "norwegian", "swedish", "italian", "polish", "spanish", "reverse" };
    for (list) |x| if (eqi(v, x)) return true;
    return false;
}

/// Index of the column named `name` (case-insensitive), or null. Used by PROC
/// PRINT var/id/sum resolution so a typo fails loud (F3) instead of dropping data.
fn resolveCol(cols: []const Column, name: []const u8) ?usize {
    for (cols, 0..) |c, j| if (eqi(c.name, name)) return j;
    return null;
}

fn containsIdx(list: []const usize, x: usize) bool {
    for (list) |v| if (v == x) return true;
    return false;
}

/// F3 helper: report a user ERROR (rc=1 — "fix your SAS", not an opensas gap) for
/// a PROC PRINT var/id naming no column. `ERROR: Variable X not found.` (SAS
/// uppercases the name). Returns void so callers `return varNotFound(...)`.
fn varNotFound(a: std.mem.Allocator, diags: *sas.diag.Diagnostics, name: []const u8) void {
    userErr(diags, "Variable {s} not found.", .{std.ascii.allocUpperString(a, name) catch name});
}

/// `pos` sits on a `(`; return the tokens inside the balanced parens and leave
/// `pos` just past the matching `)`.
fn skipParens(toks: []const Token, pos: *usize) []const Token {
    const start = pos.* + 1;
    var depth: usize = 0;
    while (pos.* < toks.len) : (pos.* += 1) {
        if (toks[pos.*].tag == .lparen) depth += 1;
        if (toks[pos.*].tag == .rparen) {
            depth -= 1;
            if (depth == 0) {
                pos.* += 1;
                return toks[start .. pos.* - 1];
            }
        }
    }
    return toks[start..pos.*];
}

// ── tests ──────────────────────────────────────────────────────────────────

/// DEC-abortrcvsD009: the exit code a CLI run WOULD produce. Tests pin the RC,
/// not just the message — asserting the message alone passes with the wrong rc,
/// which is the entire bug class here. In-process and captured; nothing is
/// spawned (D-003). Call `resetRcSignals` first: the signals are process-globals
/// shared across tests.
/// BUG-wasmignoresabortrc: this is now a thin alias for the REAL `processExitCode`
/// rather than a third open-coding of the same expression — a copy that omitted
/// the ABORT override is exactly what shipped on the wasm surface, and a test
/// helper that re-derives the answer cannot catch that.
fn testRc(diags: *const sas.diag.Diagnostics) u8 {
    return processExitCode(diags);
}

fn resetRcSignals() void {
    g_failed = false;
    g_test_last_err = "";
    sas.format.g_fmt_error = false;
    sas.exec.g_abort_rc = null; // D-009a override; interpret clears it too
    sas.diag.resetGap(); // (interpret resets this too; explicit so testRc is honest before a run)
}

/// GAP-gapsexitingone §5d: run `src` with fresh rc signals; return the D-009 rc
/// the CLI would produce and the rendered log via `log`. Lets an rc pin sit on
/// one line per case, so the typo arm and the gap arm of a split are BOTH
/// asserted instead of the message standing in for the rc (audit §6/I1).
fn rcOf(a: std.mem.Allocator, out: *std.ArrayList(u8), src: []const u8, log: *[]const u8) !u8 {
    resetRcSignals();
    out.clearRetainingCapacity();
    var d = sas.diag.Diagnostics.init(a);
    interpret(a, out, &d, src, null) catch |e| {
        // Same contract as runFile: a propagated lex/parse/exec error already
        // recorded a located diagnostic (diags.fail) — the rc below reads the
        // recorded signals. Only an UNRECORDED error (OOM) is worth throwing.
        // (Whether fail's error propagates at all depends on the statement
        // landing in interleaveStep's swallowed flush vs the trailing
        // remainder — the CLI catches either way, so the pin must too.)
        if (!d.hasErrors()) return e;
    };
    log.* = try d.render();
    return testRc(&d);
}

fn expectRun(src: []const u8, want: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags, src, null); // io-free: no LIBNAME/CSV in these
    try std.testing.expectEqualStrings(want, out.items);
}

test "PROC PRINT with BY emits per-group sections, subtotals, and a grand total (BUG-printbysubtotal)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    // pre-sorted by g: A={10,20} (sum 30), B={5} (sum 5); grand total 35
    try interpret(a, &out, &diags,
        "data d;\n  input g $ x;\n  datalines;\nA 10\nA 20\nB 5\n;\nrun;\n" ++
            "proc print data=d; by g; sum x; run;\n", null);
    const s = out.items;

    const ia = std.mem.indexOf(u8, s, "g=A") orelse return error.NoGroupA;
    const ib = std.mem.indexOf(u8, s, "g=B") orelse return error.NoGroupB;
    try std.testing.expect(ia < ib); // BY-line section headers, in group order
    try std.testing.expect(std.mem.indexOf(u8, s, "==") != null); // subtotal underline
    // group A subtotal 30 appears before the g=B section; grand total 35 at the end
    const pos_sub = std.mem.indexOf(u8, s, "30") orelse return error.NoSubtotalA;
    try std.testing.expect(pos_sub < ib);
    const pos_grand = std.mem.lastIndexOf(u8, s, "35") orelse return error.NoGrandTotal;
    try std.testing.expect(pos_grand > ib); // grand total follows the last group
}

test "BUG-sqlerrorswallow: PROC SQL select of a non-existent column fails loud (not silent no-op)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data class; input name $ age; datalines;\nAlice 13\nBob 14\n;\nrun;\n";

    // A bare bad column returns error.ParseError from sql.zig WITHOUT a diag; the
    // interleaveStep catch used to swallow it → empty output, exit 0. Now surfaced.
    var out: std.ArrayList(u8) = .empty;
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, mk ++ "proc sql; select nosuchcol from class; quit;\n", null);
    try std.testing.expect(d1.hasErrors());

    // A valid select stays clean — the fix must not fail-loud on good SQL.
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, mk ++ "proc sql; select name, age from class where age > 13; quit;\n", null);
    try std.testing.expect(!d2.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Bob") != null);
}

test "PROC PRINT BY on unsorted data fails loud like SAS (BUG-printbyunsorted)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data d; input g $ x; datalines;\n";

    // repeated non-adjacent group (A B A) → SAS "not sorted in ascending sequence"
    // DEC-abortrcvsD009: rc **1**, not 2 — the user's data is unsorted, PROC PRINT
    // is not missing a feature. Pinned as an rc so it cannot regress to a gap the
    // way it originally shipped (probed pre-fix: this exact log line gave rc 2 from
    // PRINT and rc 1 from the six proc.zig sites emitting the identical message).
    resetRcSignals();
    var out: std.ArrayList(u8) = .empty;
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, mk ++ "A 1\nB 2\nA 3\n;\nrun;\nproc print data=d; by g; run;\n", null);
    try std.testing.expect(std.mem.indexOf(u8, try d1.render(), "not sorted in ascending sequence") != null);
    try std.testing.expect(!g_failed); // NOT the gap signal
    try std.testing.expectEqual(@as(u8, 1), testRc(&d1));

    // plain descending step (B then A) → same loud error, no listing
    resetRcSignals();
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, mk ++ "B 1\nA 2\n;\nrun;\nproc print data=d; by g; run;\n", null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d2));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") == null); // step stopped before printing

    // correctly sorted BY stays clean (no regression)
    resetRcSignals();
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, mk ++ "A 1\nA 2\nB 3\n;\nrun;\nproc print data=d; by g; run;\n", null);
    try std.testing.expectEqual(@as(u8, 0), testRc(&d3));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "g=A") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "g=B") != null);
}

test "DEC-abortrcvsD009: a user error exits 1 and a gap exits 2 — the SAME log line must not carry two rcs" {
    // D-009: rc 1 = "fix your SAS", rc 2 = "file an opensas issue". main.failLoud
    // sets `g_failed`, which is the GAP signal, and it was doing double duty for
    // both classes — so five user errors in this file exited 2. Every case below
    // pins the RC, not the message: asserting the message alone passes with the
    // wrong rc, which is exactly how these shipped.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;

    // (1) THE STRONGEST CASE — byte-identical message, two exit codes. The PROC
    // FORMAT type clash is SAS's own ERROR text and exec.zig's DATA-step twin
    // (declareStmt) already emits it at rc 1. Both surfaces are pinned on the
    // same wording so neither can drift.
    const clash = "The numeric format 8.2 cannot be used with character variable c.";
    resetRcSignals();
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, "data d; length c $3; c='ab'; run;\nproc print data=d; format c 8.2; run;\n", null);
    try std.testing.expect(std.mem.indexOf(u8, try d1.render(), clash) != null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d1));

    resetRcSignals();
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, "data d; length c $3; c='ab'; format c 8.2; run;\n", null);
    try std.testing.expect(std.mem.indexOf(u8, try d2.render(), clash) != null); // same words…
    try std.testing.expectEqual(@as(u8, 1), testRc(&d2)); // …and now the same rc

    // (2) The user named a data set that is not there. exec.zig's `File {s} does
    // not exist` (a DATA step `set`) is the same condition at rc 1.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, "proc print data=nosuchds; run;\n", null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d3));
    try std.testing.expect(!g_failed); // NOT the gap signal

    // (3)/(4) PROC COPY is implemented — a missing IN= or an unbound OUT= libref
    // is the program's error, not a missing feature. (The third converted COPY
    // site, `select`ing an absent member, sits behind the `io` requirement and is
    // probe- + mutation-verified against the real binary instead.)
    resetRcSignals();
    out.clearRetainingCapacity();
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4, "data x; v=1; run;\nproc copy out=work; select x; run;\n", null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d4));

    resetRcSignals();
    out.clearRetainingCapacity();
    var d5 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d5, "data x; v=1; run;\nproc copy in=work out=nolib; select x; run;\n", null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d5));

    // GAP CONTROLS — these must STAY 2. If a later sweep demotes them, rc 2 stops
    // being reachable and the calling agent is told to fix SAS that is already fine.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d6 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d6, "data d; x=1; run;\nproc frobnicate data=d; run;\n", null);
    try std.testing.expectEqual(@as(u8, 2), testRc(&d6));

    resetRcSignals();
    out.clearRetainingCapacity();
    var d7 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d7, "data d; x=1; run;\nproc print data=d double; run;\n", null);
    try std.testing.expectEqual(@as(u8, 2), testRc(&d7)); // unsupported PRINT option: a real gap

    // CLEAN CONTROL — nothing above leaked a sticky global into a good run.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d8 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d8, "data d; length c $3; c='ab'; run;\nproc print data=d; format c $3.; run;\n", null);
    try std.testing.expectEqual(@as(u8, 0), testRc(&d8));
    resetRcSignals();
}

test "GAP-gapsexitingone §5d: main.zig's gaps exit 2 — and every split's typo arm provably stays 1" {
    // The OTHER D-009 direction in this file: these sites reported through
    // `diags` (rc 1, "fix your SAS") for constructs that are valid SAS 9.4 —
    // and a gap is rc 2 ("file an opensas issue") even though real SAS exits 0
    // (D-009b(i)). Every case pins the RC, not the message: the message alone
    // passed with the wrong rc for years (audit §6/I1). Each SPLIT pins BOTH
    // arms — documented operand at 2, typo at 1 — so the gap arm can never be
    // re-tagged wholesale and eat a typo again. The CONFLATED catch-alls
    // (audit §5d LEFT rows) are pinned at 1 so a future wholesale re-tag reds.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // the honoured SORTSEQ arms below set module state; restore it like the
    // BUG-optionsstmtswallow test does, so nothing leaks into a later test.
    defer sas.io.global_sortseq_linguistic = false;
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    var log: []const u8 = "";

    // ── FIXED: the guard matches exactly one documented valid-SAS construct ──
    // OPTIONS arms (BUG-optionsstmtswallow's own comment calls these "LOUD gap")
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options noreplace;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options mergenoby=warn;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options mergenoby=error;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options varinitchk=error;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options varinitchk=abend;\n", &log));
    // FILENAME concatenation, ODS OUTPUT/SELECT/EXCLUDE/TRACE, DATA-step LIST
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "filename both ('fa.txt' 'fb.txt');\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "ods output Summary=s;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "ods select MyTable;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "ods exclude MyTable;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "ods trace on;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "data a; input x; list; datalines;\n1\n;\nrun;\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "The LIST statement is not supported") != null); // message unchanged

    // the 64-fileref ceiling is OURS — SAS 9.4 has no fileref limit
    var many: []const u8 = "";
    for (0..65) |i| many = try std.fmt.allocPrint(a, "{s}filename f{d} \"x{d}.txt\";\n", .{ many, i, i });
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, many, &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "too many FILENAME filerefs") != null);

    // ── SPLIT: documented operand → 2, typo → 1, on the SAME guard ──
    // SORTSEQ (Procedures Guide p.2410): the collating-sequence-options and the
    // SAS-provided translation tables. BUG-rcsplitmembership F4 — the whole
    // sentence, not the five that came to mind; each of the four that used to
    // sit on the typo arm is pinned by name so a partial list reds again.
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options sortseq=danish;\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "SORTSEQ=danish is not supported") != null); // message unchanged
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options sortseq=ebcdic;\n", &log));
    for ([_][]const u8{ "italian", "polish", "spanish", "reverse", "finnish", "norwegian", "swedish" }) |v| {
        const src = try std.fmt.allocPrint(a, "options sortseq={s};\n", .{v});
        try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, src, &log));
    }
    // ASCII is the tenth name in that sentence and is HONOURED, not a gap —
    // it is opensas's own collation, so it must stay rc 0.
    try std.testing.expectEqual(@as(u8, 0), try rcOf(a, &out, "options sortseq=ascii;\ndata _null_; x=1; run;\n", &log));
    // BUG-sortseqbaresuperset: LINGUISTIC is a VALID system-option value
    // (Procedures Guide p.2403 — "starting in the third maintenance release of
    // SAS 9.4 … by specifying the SORTSEQ=LINGUISTIC system option"; SQL
    // Procedure p.261), so the bare form is honoured at rc 0 and the modifier
    // form is a GAP at rc 2 — NOT the rc 1 that BUG-rcsplitmembership F2 gave
    // it on the strength of the stale p.2415 restriction.
    try std.testing.expectEqual(@as(u8, 0), try rcOf(a, &out, "options sortseq=linguistic;\ndata _null_; x=1; run;\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "options sortseq=linguistic(collation=pinyin);\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "system option SORTSEQ=linguistic is not supported") != null);
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "options sortseq=bogus;\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "Invalid value for the SORTSEQ option.") != null);

    // FILENAME device (the FILE/INFILE device-type dictionary + the FILENAME
    // access-method sections). BUG-rcsplitmembership F3 — the twelve that were
    // missing are pinned by name.
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "filename cmd pipe \"echo hi\";\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "FILENAME device pipe is not supported") != null); // unchanged
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "filename f ftp \"x\";\n", &log));
    for ([_][]const u8{ "hadoop", "sftp", "zip", "clipboard", "dataurl", "s3", "azure", "filesrvc", "dummy", "plotter", "activemq", "jms" }) |d| {
        const src = try std.fmt.allocPrint(a, "filename f {s} \"x\";\n", .{d});
        try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, src, &log));
    }
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "filename f bogusdev \"x\";\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "FILENAME device bogusdev is not recognized") != null);

    // FILENAME RECFM (F/N/P/VB/VS/VBS/U/D documented; V honoured, inert)
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "filename f \"x.txt\" recfm=f;\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "RECFM=f is not supported") != null); // unchanged
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "filename f \"x.txt\" recfm=bogus;\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "Invalid value for the RECFM= FILENAME option.") != null);
    try std.testing.expectEqual(@as(u8, 0), try rcOf(a, &out, "filename f \"x.txt\" recfm=v;\ndata _null_; x=1; run;\n", &log)); // honoured arm stays clean

    // LIBNAME engine (base-product documented set; SAS/ACCESS degrades to rc 1)
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "libname t json \"nowhere\";\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "LIBNAME engine json is not supported (BASE/V9/XPORT only)") != null);
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "libname t xml \"nowhere\";\n", &log));
    try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, "libname t spde \"nowhere\";\n", &log));
    // BUG-rcsplitmembership F5: the versioned base engines (Procedures Guide
    // p.1566 / p.1577). Real SAS finds them; opensas has only the V9 format.
    for ([_][]const u8{ "v6", "v7", "v8", "v6tape", "v9tape" }) |e| {
        const src = try std.fmt.allocPrint(a, "libname t {s} \"nowhere\";\n", .{e});
        try std.testing.expectEqual(@as(u8, 2), try rcOf(a, &out, src, &log));
    }
    // V9/BASE stay HONOURED (V9 is the documented BASE alias, p.1032), and a
    // SAS/ACCESS engine still degrades to rc 1 — neither may drift into the gap arm.
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "libname t oracle \"nowhere\";\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "The oracle engine cannot be found.") != null);
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "libname t boguseng \"nowhere\";\n", &log));
    try std.testing.expect(std.mem.indexOf(u8, log, "The boguseng engine cannot be found.") != null);

    // ── controls: the typo arms that were ALWAYS rc 1 must not move ──
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "options mergenoby=zzz;\n", &log));
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "options varinitchk=zzz;\n", &log));
    // the CONFLATED catch-alls stay 1 (NEEDS-JUDGEMENT, §5d LEFT rows)
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "options bogusopt=1;\n", &log));
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "libname x \"p\" bogusopt=1;\n", &log));
    try std.testing.expectEqual(@as(u8, 1), try rcOf(a, &out, "filename f \"x.txt\" lrelc=100;\n", &log));
    // clean control — no sticky gap leaked into a good run
    try std.testing.expectEqual(@as(u8, 0), try rcOf(a, &out, "data _null_; x=1; put x; run;\n", &log));
    resetRcSignals();
}

test "BUG-fmterrorneverreset: format.zig's run-scoped globals must NOT leak into the next interpret()" {
    // The CLI runs one program per process, so process exit hid this. `wasm.zig`
    // runs many programs per load and calls this same `interpret`, so the leak is
    // reachable there and only there. NOTHING below calls `resetRcSignals()`
    // between the two runs of a pair — the point is that `interpret` itself must
    // clear the flag. (The test above does reset between cases, which is exactly
    // why its "CLEAN CONTROL" could not see this.)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    const unknown_fmt = "data _null_; x=1; put x nosuchfmt8.; run;\n";
    const clean = "data _null_; y=2; put y 8.; run;\n";

    // (1) g_fmt_error — the reported half. Program 1 is genuinely wrong (rc 1)…
    resetRcSignals();
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, unknown_fmt, null);
    try std.testing.expect(sas.format.formatErrored());
    try std.testing.expectEqual(@as(u8, 1), testRc(&d1));

    // …and program 2 is clean, so it must exit 0. PRE-FIX IT EXITED 1: a correct
    // program reported as failing for a format it never mentioned.
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, clean, null);
    try std.testing.expect(!sas.format.formatErrored());
    try std.testing.expectEqual(@as(u8, 0), testRc(&d2));

    // (2) g_nofmterr — the same leak, opposite sign, and the WORSE direction:
    // program 1's `OPTIONS NOFMTERR` must not silence program 2. A false negative
    // on invalid SAS is silent wrong output, the house's worst failure class.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, "options nofmterr;\n" ++ unknown_fmt, null);
    try std.testing.expectEqual(@as(u8, 0), testRc(&d3)); // suppressed WITHIN the run: by design
    try std.testing.expect(std.mem.trim(u8, out.items, " \n").len > 0); // still renders the fallback

    out.clearRetainingCapacity();
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4, unknown_fmt, null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d4)); // pre-fix: 0, error swallowed

    // (3) `g_failed`, the SAME shape found by the sweep this ticket asked for:
    // `gap` is `g_failed or gapHit()` and only the second half was reset here, so
    // one unsupported PROC made every later program exit 2 ("file an opensas
    // issue") for code that has no gap in it. wasm.zig was papering over it with
    // its own copy of the reset; that copy is now gone.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d5 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d5, "data d; x=1; run;\nproc frobnicate data=d; run;\n", null);
    try std.testing.expectEqual(@as(u8, 2), testRc(&d5)); // a real gap, unchanged

    out.clearRetainingCapacity();
    var d6 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d6, clean, null);
    try std.testing.expect(!g_failed);
    try std.testing.expectEqual(@as(u8, 0), testRc(&d6)); // pre-fix: 2
    resetRcSignals();
}

test "BUG-wasmignoresabortrc / D-009a: the ABORT rc outranks D-009 in the ONE shared exit-code function" {
    // `wasm.run` re-derived the rc from the two D-009 signals and `diag.exitCode`,
    // which silently dropped the ABORT line that sits ABOVE them in `main` — so
    // `abort return 3` exited 3 on the CLI and returned 1 in the browser. Both
    // surfaces now call `processExitCode`, and `testRc` is an alias for it, so
    // every case below pins the code wasm.run returns as well as the CLI's.
    //
    // COVERAGE, stated plainly: the CLI end of this is pinned end-to-end by
    // tests/corpus/abort_rc.sas (`expect-rc: 3`) and by the cases here. wasm.run's
    // one-line CALL has NO automated protection — `zig build test` only COMPILES
    // the wasm target (build.zig:238), nothing executes it, and no fixture runner
    // can. Deduplicating was the point: the untested line is now a call, not a
    // re-implementation, so it can no longer drift on its own.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    const mk = "data a; x=1; ";

    // THE SHARPEST CASE FIRST — ABORT reports an ERROR diagnostic, so D-009 alone
    // says 1. It must be 3. If the override is ever dropped again this is the
    // assertion that names why: `hasErrors()` and the rc deliberately disagree.
    resetRcSignals();
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, mk ++ "abort return 3; run;\n", null);
    try std.testing.expect(d1.hasErrors()); // …which on its own would be rc 1
    try std.testing.expectEqual(@as(u8, 3), testRc(&d1)); // wasm pre-fix: 1

    // ABEND n, the other named form; and bare ABEND is abnormal so it is never 0.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, mk ++ "abort abend 4; run;\n", null);
    try std.testing.expectEqual(@as(u8, 4), testRc(&d2));

    resetRcSignals();
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, mk ++ "abort abend; run;\n", null);
    try std.testing.expectEqual(@as(u8, 1), testRc(&d3));

    // The override is an OVERRIDE, not a maximum: `abort return 0` exits 0 even
    // though the run recorded an ERROR. D-009a says the user-supplied rc becomes
    // the exit code, full stop — pinned so nobody "fixes" it into a max().
    resetRcSignals();
    out.clearRetainingCapacity();
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4, mk ++ "abort return 0; run;\n", null);
    try std.testing.expect(d4.hasErrors());
    try std.testing.expectEqual(@as(u8, 0), testRc(&d4));

    // …and it beats a GAP too, which is the ordering `main` has always had (the
    // abort line sits above `gap or user_err`, not inside `diag.exitCode`).
    // The gap must come FIRST: ABORT reports an ERROR, which puts the run into
    // syntax-check mode (BUG-errhalt) and skips every later step — a probe with
    // the PROC after the ABORT looks like it passes and proves nothing. (My first
    // version of this case did exactly that and this assertion caught it.)
    resetRcSignals();
    out.clearRetainingCapacity();
    var d5 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d5, mk ++ "run;\nproc frobnicate data=a; run;\ndata b; abort return 7; run;\n", null);
    try std.testing.expect(g_failed); // a real gap was hit…
    try std.testing.expectEqual(@as(u8, 7), testRc(&d5)); // …and the ABORT still wins

    // CONTROLS. Plain `abort;` names no rc, so D-009 applies unchanged; and the
    // NEXT program in a wasm session must not inherit the last one's abort code.
    resetRcSignals();
    out.clearRetainingCapacity();
    var d6 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d6, mk ++ "abort; run;\n", null);
    try std.testing.expectEqual(@as(u8, 0), testRc(&d6));

    out.clearRetainingCapacity();
    var d7 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d7, mk ++ "abort return 9; run;\n", null);
    try std.testing.expectEqual(@as(u8, 9), testRc(&d7));
    out.clearRetainingCapacity();
    var d8 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d8, "data b; y=2; run;\n", null); // no resetRcSignals: interpret's job
    try std.testing.expectEqual(@as(u8, 0), testRc(&d8));
    resetRcSignals();
}

test "PROC PRINT unknown sub-statement fails loud; global TITLE mid-proc is exempt (BUG-printsubstmtsilent)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data d; x=1; run;\n";
    var out: std.ArrayList(u8) = .empty;

    // a typo'd sub-statement names itself in a loud error (was: silently ignored)
    g_failed = false;
    g_test_last_err = "";
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, mk ++ "proc print data=d; vae x; run;\n", null);
    try std.testing.expect(g_failed);
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "vae") != null);

    // real-but-unimplemented PROC PRINT statements fail loud as gaps, not silent
    g_failed = false;
    g_test_last_err = "";
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, mk ++ "proc print data=d; sumby x; run;\n", null);
    try std.testing.expect(g_failed);
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "sumby") != null);

    // global statements are legal mid-PROC: title between proc and var runs clean
    g_failed = false;
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, mk ++ "proc print data=d; title \"hi\"; var x; run;\n", null);
    try std.testing.expect(!g_failed and !d3.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") != null); // listing printed
}

test "BUG-libnamemidstepboth + BUG-filenamemidstep: mid-PROC globals EXECUTE (pre-pass/hoist); ODS OUTPUT stays loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data d; x=1; run;\n";
    var out: std.ArrayList(u8) = .empty;

    // F4 repro: a mid-PROC libname EXECUTED in the up-front parseLibnames
    // pre-pass and then ALSO errored in the statement loop (exit 2, listing
    // lost). D-014a: the pre-pass handled it → the loop skips it.
    g_failed = false;
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, mk ++ "proc print data=d noobs; libname zzzq \"nowhere\"; var x; run;\n", null);
    try std.testing.expect(!g_failed and !d1.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "1") != null); // listing printed

    // BUG-filenamemidstep: FILENAME mid-PROC is now HOISTED by main.segments
    // and EXECUTED before the step (SAS: a global statement takes effect when
    // encountered — during step compilation, before the step runs). Accepted,
    // listing renders, and the binding is REAL: a later step reads through it.
    g_failed = false;
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, mk ++
        "proc print data=d noobs; filename zzzq \"tests/corpus/filename_infile.dat\"; var x; run;\n" ++
        "data _null_; infile zzzq; input w $; put \"READ-VIA-MIDPROC-FILEREF: \" w; run;\n", null);
    try std.testing.expect(!g_failed and !d2.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "READ-VIA-MIDPROC-FILEREF:") != null);

    // ODS destination mid-PROC: hoisted and accepted as a listing no-op
    // (batch renders to ONE output stream), same as top level — no longer
    // FATAL (the over-strict arm D-014 was written against).
    g_failed = false;
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, mk ++ "proc print data=d noobs; ods listing; var x; run;\n", null);
    try std.testing.expect(!g_failed and !d3.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "1") != null); // listing printed

    // ODS OUTPUT mid-PROC stays LOUD — via the hoisted global segment's
    // handleGlobal arm (result-changing, unimplemented), captured diags (D-003).
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4, mk ++ "proc print data=d noobs; ods output zzzq; run;\n", null);
    try std.testing.expect(d4.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try d4.render(), "ODS OUTPUT (capture to dataset) is not supported yet") != null);
}

test "GAP-printby-low-tick274: ID∩VAR/dup VAR keep both columns; SPLIT= implies LABEL; NOBYLINE honored; N/DOUBLE/ROUND/WIDTH= stay loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data d; input g subj x; label x = 'Long*Label'; datalines;\n1 101 10\n2 102 20\n;\nrun;\n";
    var out: std.ArrayList(u8) = .empty;

    // ID∩VAR overlap: SAS prints the variable TWICE (ID statement doc).
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, mk ++ "proc print data=d noobs; id subj; var subj x; run;\n", null);
    try std.testing.expect(!d1.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "subj   subj") != null); // two subj columns

    // duplicated VAR entry: also kept (VAR is positional, no dedup).
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, mk ++ "proc print data=d noobs; var x x g; run;\n", null);
    try std.testing.expect(!d2.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, " x    x   g") != null); // two x columns

    // SPLIT= without LABEL: SAS puts PRINT in label mode — the header is the
    // label, split on '*', not the variable name.
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, mk ++ "proc print data=d split='*' noobs; var x; run;\n", null);
    try std.testing.expect(!d3.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Long\n") != null); // label header, split
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Label") != null);

    // NOBYLINE: BY groups still section, the `g=…` BY line is gone.
    out.clearRetainingCapacity();
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4, mk ++ "proc print data=d noobs nobyline; by g; run;\n", null);
    try std.testing.expect(!d4.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "g=") == null); // no BY line
    try std.testing.expect(std.mem.indexOf(u8, out.items, "101") != null); // rows still printed

    // N / DOUBLE / ROUND / WIDTH= stay D-002 loud, naming the option.
    inline for (.{ "n", "double", "round", "width=full" }) |opt| {
        g_failed = false;
        g_test_last_err = "";
        out.clearRetainingCapacity();
        var dl = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &dl, mk ++ "proc print data=d " ++ opt ++ "; run;\n", null);
        try std.testing.expect(g_failed);
        try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "PROC PRINT option") != null);
    }
}

test "data _null_ with assignment, functions and put" {
    try expectRun(
        "data _null_;\n  s = sum(1,2,3);\n  put \"s=\" s;\nrun;\n",
        "s=6\n",
    );
}

test "GH#73 lengthVars: char LENGTH after first reference is dropped + warns; before is kept" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // late LENGTHs (after the assignment) are IGNORED (dropped) and warn
    {
        var diags = sas.diag.Diagnostics.init(a);
        const body = try sas.lexer.tokenize(a, "x = \"hello\"; length x $20; y = \"world\"; length y $2;", &diags);
        const declared = try lengthVars(a, body, &diags);
        try std.testing.expectEqual(@as(usize, 0), declared.len);
        var warns: usize = 0;
        for (diags.list.items) |d| if (d.severity == .warning) {
            warns += 1;
        };
        try std.testing.expectEqual(@as(usize, 2), warns);
    }
    // a LENGTH that precedes the first reference is honored (kept, no warning)
    {
        var diags = sas.diag.Diagnostics.init(a);
        const body = try sas.lexer.tokenize(a, "length x $20; x = \"hi\";", &diags);
        const declared = try lengthVars(a, body, &diags);
        try std.testing.expectEqual(@as(usize, 1), declared.len);
        try std.testing.expectEqualStrings("x", declared[0].name);
        try std.testing.expectEqual(@as(usize, 20), declared[0].len);
        try std.testing.expectEqual(@as(usize, 0), diags.count());
    }
}

test "BUG-speciallistphantom: _ALL_/_NUMERIC_/_CHARACTER_ in LENGTH/ATTRIB seed no phantom var (GH#79)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // LENGTH: the special-list names seed nothing; a real name in the same
    // statement still seeds. (Statements Ref printed p.24 — they are variable
    // name LISTS, never variables of their own.)
    {
        var diags = sas.diag.Diagnostics.init(a);
        const body = try sas.lexer.tokenize(a, "length _all_ 8 _numeric_ 4; length v $ 3;", &diags);
        const declared = try lengthVars(a, body, &diags);
        try std.testing.expectEqual(@as(usize, 1), declared.len);
        try std.testing.expectEqualStrings("v", declared[0].name);
    }
    // ATTRIB: an all-special group seeds nothing (its options still parse —
    // the format reaches the listed vars exec-side); a mixed group seeds only
    // its real names.
    {
        var diags = sas.diag.Diagnostics.init(a);
        const body = try sas.lexer.tokenize(a, "attrib _all_ format=best8.; attrib _character_ s format=$8.;", &diags);
        const declared = try lengthVars(a, body, &diags);
        try std.testing.expectEqual(@as(usize, 1), declared.len);
        try std.testing.expectEqualStrings("s", declared[0].name);
    }
    // end-to-end, the two failure halves of GH#79: NO phantom column AND the
    // attribute reaches the listed variables (8.2 renders 1 → 1.00).
    try expectRun(
        "data c; p = 1; q = 2; format _all_ 8.2; run;\nproc print data=c noobs; run;\n",
        "       p          q\n\n    1.00       2.00\n",
    );
    // …and the reporter's second symptom: the phantom no longer pre-empts a
    // later character assignment, so the misleading "defined as both
    // character and numeric" conflict cannot fire off a special list — the
    // char var simply takes its value.
    try expectRun(
        "data c2; attrib _character_ format=$8.; a = \"x\"; run;\nproc print data=c2 noobs; run;\n",
        "a\n\nx\n",
    );
    // the type guard survives expansion: a numeric format over `_all_` lands
    // on a CHARACTER member and is LOUD (rc 1, reported ONCE) — SAS errors
    // that attach whichever way the variable is named.
    {
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data m; a = \"x\"; b = 1; format _all_ best8.; run;", null);
        try std.testing.expect(diags.hasErrors());
        var hits: usize = 0;
        for (diags.list.items) |d| {
            if (std.mem.indexOf(u8, d.message, "The numeric format best8. cannot be used with character variable a.") != null) hits += 1;
        }
        try std.testing.expectEqual(@as(usize, 1), hits);
    }
}

test "BUG-lengthaftersetinput: char LENGTH/ATTRIB after SET or INPUT keeps the first length + warns (Language Reference: Concepts p.49 n.1)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const p49 = "Length of character variable";

    // scan shape after SET: an early zero-len type sentinel (GH#70's fatal type
    // check + PDV position) + a LATE copy carrying the declared length — and NO
    // scan-time warning (a NEW var after SET is legal, so the warn must wait for
    // the PDV-side first-wins guard).
    {
        var diags = sas.diag.Diagnostics.init(a);
        const body = try sas.lexer.tokenize(a, "set src; length s $3;", &diags);
        const declared = try lengthVars(a, body, &diags);
        try std.testing.expectEqual(@as(usize, 2), declared.len);
        try std.testing.expectEqual(@as(usize, 0), declared[0].len); // sentinel
        try std.testing.expect(!declared[0].late); // sentinel seeds EARLY
        try std.testing.expect(declared[0].after_input); // GH#70 type check intact
        try std.testing.expectEqual(@as(usize, 3), declared[1].len); // copy
        try std.testing.expect(declared[1].late); // copy seeds AFTER the columns
        try std.testing.expectEqual(@as(usize, 0), diags.count());
    }
    // scan shape after INPUT: dropped at scan by the SAME GH#73 seen-guard the
    // assignment path uses, with the one p.49 warning.
    {
        var diags = sas.diag.Diagnostics.init(a);
        const body = try sas.lexer.tokenize(a, "input s $10.; length s $3;", &diags);
        const declared = try lengthVars(a, body, &diags);
        try std.testing.expectEqual(@as(usize, 0), declared.len);
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), p49) != null);
    }
    // end-to-end (captured diags; no spawned process): all three establishment
    // paths agree — established var keeps its first length, p.49 warning arms,
    // the wrong "Multiple lengths" text is GONE, a NEW var after SET/INPUT is
    // still declared at its length with no warning.
    {
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags,
            "data a; length s $10; s='abcdefghij'; run;\n" ++
                "data b; set a; length s $3; put \"set=[\" s \"]\"; run;\n" ++
                "data b2; set a; attrib s length=$3; put \"setat=[\" s \"]\"; run;\n" ++
                "data c; input s $10.; length s $3; put \"inp=[\" s \"]\"; datalines;\nabcdefghij\n;\nrun;\n" ++
                "data d; s='abcdefghij'; length s $3; put \"asn=[\" s \"]\"; run;\n" ++
                "data e; set a; length newv $3; newv='xyz'; put \"new=[\" newv \"]\"; run;\n", null);
        // expected strings carry the BUG-putlistsep blank a list value owes a
        // following literal (`s "]"` → `… ]`) — the test's intent is lengths.
        try std.testing.expectEqualStrings("set=[abcdefghij ]\nsetat=[abcdefghij ]\ninp=[abcdefghij ]\nasn=[abcdefghij ]\nnew=[xyz ]\n", out.items);
        const log = try diags.render();
        try std.testing.expect(std.mem.indexOf(u8, log, "Multiple lengths") == null); // wrong message gone
        var warns: usize = 0;
        for (diags.list.items) |d| {
            if (d.severity != .warning) continue;
            warns += 1;
            try std.testing.expect(std.mem.indexOf(u8, d.message, p49) != null); // every warning is the p.49 one
        }
        try std.testing.expectEqual(@as(usize, 4), warns); // set, set-attrib, input, assignment — NOT newv
    }
    // GH#70 guard-rail: the split must NOT defuse the fatal char-LENGTH-after-SET
    // on a NUMERIC source var (the sentinel keeps the type check in place).
    {
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data n; t=5; run;\ndata h; set n; length t $24; run;\n", null);
        try std.testing.expect(diags.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "Character length cannot be used with numeric variable t.") != null);
    }
}

test "QL-D2: prx/dsfns/hashing globals reset per run — stale handles die, not dangle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    // Run 1: register handle 1 in all three module-global tables.
    try interpret(a, &out, &diags,
        "data x; v=42; run;\n" ++
            "data _null_; p=prxparse('/abc/'); d=open('work.x'); h=hashing_init('MD5'); put p= d= h=; run;", null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "p=1 d=1 h=1") != null); // handles live in run 1
    // Run 2 (same process): every stale handle-1 must be dead. Without the
    // per-run reset, prxmatch=1 (stale pattern matches), fetch=0 (reads run 1's
    // freed Library), hashing_term=hex digest.
    out.clearRetainingCapacity();
    try interpret(a, &out, &diags,
        "data _null_; m=prxmatch(1,'abc'); f=fetch(1); t=hashing_term(1); put m= f= t=; run;", null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "m=0 f=-1 t=.") != null);
}

test "BUG-barepctundef: undefined bare %word warns+drops, no LexError halts the pipeline" {
    // Full pipeline (expand→lex→run), NOT expectExpand: a bare %undefmac must not
    // leak its % to the lexer. Before the fix this halted with Lex|unexpected '%'.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags, "%undefmac; data _null_; put \"x\"; run;", null);
    try std.testing.expectEqualStrings("x\n", out.items); // step ran; % never reached lexer
    try std.testing.expect(!diags.hasErrors()); // warn-and-drop, not a hard error
}

test "BUG-errhalt: a DATA-step ERROR poisons downstream steps (syntax-check mode)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    // "before" prints; the unsorted SET-BY errors; "after" must NOT print —
    // real SAS batch enters syntax-check mode after a step error, so a
    // truncated intermediate can't flow into later (clinical) outputs
    // (a real MH run wrote a plausible 310-obs TARGET.MH, golden 227).
    try interpret(a, &out, &diags,
        "data a; input k; datalines;\n1\n3\n;\nrun;\n" ++
            "data b; input k; datalines;\n2\n1\n;\nrun;\n" ++
            "data _null_; put \"before\"; run;\n" ++
            "data m; set a b; by k; run;\n" ++
            "data _null_; put \"after\"; run;\n", null);
    try std.testing.expect(diags.hasErrors()); // captured diagnostic (D-003)
    try std.testing.expect(std.mem.indexOf(u8, out.items, "before") != null); // pre-error ran
    try std.testing.expect(std.mem.indexOf(u8, out.items, "after") == null); // post-error skipped
}

test "GAP-errgatereplaces: a stopped step does not REPLACE an existing member, still CREATES a new one, and MODIFY is exempt" {
    // Language Reference: Concepts printed p.175, Example Code 8.6: "WARNING: Data set WORK.TEST was not
    // replaced because this step was stopped." The three cases below are the whole
    // rule; the SURVIVOR'S CONTENT is pinned on disk by tests/programs/errgate_*,
    // which is what an ERROR-only assertion would miss. Captured diagnostics (D-003).
    const src_head = "data k; input id v; datalines;\n1 10\n2 20\n3 30\n;\nrun;\n";
    const warning = "was not replaced because this step was stopped";

    { // (a) REPLACE of an existing member — withheld, and said so.
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, src_head ++ "data k; length z 8; goto nowhere; run;\n", null);
        const log = try diags.render();
        try std.testing.expect(diags.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, log, "WARNING: Data set WORK.K " ++ warning) != null);
    }
    { // (b) a NEW name — created (0 obs, compile-time columns), so NO warning.
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, src_head ++ "data fresh; length z 8; goto nowhere; run;\n", null);
        try std.testing.expect(diags.hasErrors()); // the gate still fires
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), warning) == null);
    }
    { // (c) MODIFY edits IN PLACE — there is no replace, and withholding its
        // re-emitted master would DISCARD the transactions that did apply
        // (BUG-modifybynomatch reports .err and continues on purpose).
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, src_head ++
            "data t; input id v; datalines;\n1 99\n9 90\n;\nrun;\n" ++
            "data k; modify k t; by id; run;\n", null);
        try std.testing.expect(diags.hasErrors()); // the no-match ERROR
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), warning) == null);
    }
}

test "GH#17 ISS-macrolinemap: macro-expansion error is marked (expanded Lnn); plain error keeps its bare source line" {
    // (a) A multi-line %do body whose expansion errors: the reported line is in
    // post-expansion coordinates, so it MUST render `(expanded Lnn)` — never a bare
    // `(Lnn)` a line-map harness would blame on an innocent source/macro file.
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags,
            "%macro g;\n" ++
                "  data _null_;\n" ++
                "    %do i = 1 %to 3;\n" ++
                "      x = ;\n" ++
                "    %end;\n" ++
                "  run;\n" ++
                "%mend;\n" ++
                "%g\n", null);
        const log = try diags.render();
        try std.testing.expect(diags.hasErrors()); // captured (D-003), no spawn
        try std.testing.expect(std.mem.indexOf(u8, log, "expanded L") != null);
    }
    // (b) The SAME error with no macro at all: expansion is a no-op, so the position
    // is a real source line and must stay UNMARKED (regression guard for non-macro).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data _null_;\n  x = ;\nrun;\n", null);
        const log = try diags.render();
        try std.testing.expect(diags.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, log, "expanded") == null); // no marker
        try std.testing.expect(std.mem.indexOf(u8, log, "(L2)") != null); // real source line 2
    }
}

test "NOTE-globalstmtunresolved: TITLE/FOOTNOTE/OPTIONS discharge the unresolved-&name warning; the false-positive controls stay silent" {
    // 85087c38 made %PUT warn (Macro Language Reference printed p.152); TITLE,
    // FOOTNOTE and OPTIONS still swallowed the same warning because main.zig
    // routes global segments around bindStepVars (the step discharge). Global
    // statements are warnable for the same reason %PUT is: late binding
    // provably cannot apply — no prior step exists in the chunk. The discharge
    // is main.zig's call over the segment's tokens, through macro.zig's
    // warnUnresolvedIn and the SAME g_unresolved gate as the step path, so the
    // four controls that must stay silent there stay silent here too.
    // NO CORPUS FIXTURE: the WARNING rides stderr and both suites diff stdout
    // (tests/corpus_runner.zig) — captured diagnostics (D-003), no spawn.
    const H = struct {
        fn log(src: []const u8) !struct { n: usize, errs: bool } {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var diags = sas.diag.Diagnostics.init(a);
            var out: std.ArrayList(u8) = .empty;
            try interpret(a, &out, &diags, src, null);
            const r = try diags.render();
            return .{ .n = std.mem.count(u8, r, "Apparent symbolic reference"), .errs = diags.hasErrors() };
        }
    };

    // THE TICKET — TITLE and FOOTNOTE each warn once, at the statement.
    {
        const r = try H.log("title \"study &zzz\";\nfootnote2 \"page &zzz\";\n");
        try std.testing.expectEqual(2, r.n);
        try std.testing.expect(!r.errs); // a warning never becomes an error
    }
    // OPTIONS: an unresolved ref warns FIRST (SAS's word scanner runs ahead of
    // the statement), then the executor's own complaint stands as before. The
    // scan-time verbatim copy that made OPTIONS swallow the reference is gone,
    // so a RESOLVABLE ref now resolves (SAS runs `options &v;` clean).
    {
        const r = try H.log("options nodate &zzz;\n");
        try std.testing.expectEqual(1, r.n);
        try std.testing.expect(r.errs); // the `&` is still not an option word
    }
    {
        const r = try H.log("%let v=nodate;\noptions &v;\ndata _null_; put \"ok\"; run;\n");
        try std.testing.expectEqual(0, r.n);
        try std.testing.expect(!r.errs);
    }
    // THE FOUR FALSE-POSITIVE CONTROLS. Post-lex these are indistinguishable
    // from a real reference; the g_unresolved gate is what discriminates, and
    // it holds here exactly as on the step/%PUT paths (macro.zig's tests cite
    // printed p.21 / p.38 / p.106 for the first three).
    //   * `a & b`      — a bare ampersand is not a trigger (blank after &);
    //   * 'AT&T'       — single quotes: never resolved, never recorded;
    //   * "%nrstr(&x)" — masked at scan time, so never recorded;
    //   * &SYS*        — warned EAGERLY by resolveAmpRun, never recorded, so
    //                    the discharge must not say it a SECOND time.
    {
        const r = try H.log("title \"a & b\";\ntitle2 'AT&T';\ntitle3 \"%nrstr(&x)\";\n%let known=ok;\ntitle4 \"&known\";\ndata _null_; put \"ok\"; run;\n");
        try std.testing.expectEqual(0, r.n);
        try std.testing.expect(!r.errs);
    }
    {
        const r = try H.log("footnote \"&sysnosuchauto\";\n");
        try std.testing.expectEqual(1, r.n); // exactly once — the eager warning
    }
    // A HOISTED mid-step TITLE also warns exactly once: its tokens remain in
    // the step, where bindStepVars already discharges them — the global-seg
    // discharge skips hoisted segments or the warning would sound twice.
    {
        const r = try H.log("data _null_;\ntitle \"mid &zzz\";\nput \"ok\";\nrun;\n");
        try std.testing.expectEqual(1, r.n);
    }
    // LATE BINDING still rescues a title that follows its CALL SYMPUT step:
    // the second chunk expands after the first ran, so `&t` resolves and is
    // never recorded. Warning here would be the D-004 false positive.
    {
        const r = try H.log("data _null_; call symput(\"t\",\"hi\"); run;\ntitle \"&t\";\n");
        try std.testing.expectEqual(0, r.n);
        try std.testing.expect(!r.errs);
    }
}

test "NOTE-chunkrelativelineno: diagnostics after the first top-level run; report the ABSOLUTE source line" {
    // QA tick312 F3: rawSegments chunks the program at top-level run;/quit; and
    // each chunk tokenized from line 1, so a typo on source line 9 reported L3.
    // With no macro transformation the number must be the true source line,
    // unmarked. (Captured diagnostics, D-003 — no aborting process.)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags,
        "data d;\n" ++ // 1
            "  x=1;\n" ++ // 2
            "run;\n" ++ // 3
            "\n" ++ // 4
            "proc print data=d noobs;\n" ++ // 5
            "run;\n" ++ // 6
            "\n" ++ // 7
            "zzzq 5;\n", // 8 <- the typo
        null);
    const log = try diags.render();
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, log, "expanded") == null); // no macro, no marker
    try std.testing.expect(std.mem.indexOf(u8, log, "ERROR(L8): statement zzzq") != null); // absolute, not L6/L1
    try std.testing.expect(std.mem.indexOf(u8, out.items, "1") != null); // the pre-error PRINT still ran
}

test "BUG-macrointerleave: intra-body CALL SYMPUT feeds the SAME body's later %do" {
    // The data step's symput must EXECUTE at its run; before the %do expands, so
    // &n resolves to 3 (whole-body-first expansion saw it unset → printed nothing).
    try expectRun(
        "%macro t; data _null_; call symput(\"n\",\"3\"); run;" ++
            " data _null_; %do i=1 %to &n; put \"I=&i\"; %end; run; %mend; %t",
        "I=1\nI=2\nI=3\n",
    );
    // The metadata-driven shell-macro shape: a later step's %do generates columns
    // from the count a prior step's symput set → the output dataset has >0 vars.
    try expectRun(
        "%macro t; data _null_; call symput(\"k\",\"2\"); run;" ++
            " data want; %do i=1 %to &k; x&i=&i; %end; run; %mend; %t" ++
            " data _null_; set want; put \"row \" x1= x2=; run;",
        "row x1=1 x2=2\n",
    );
}

test "CALL SYMPUT var resolves in a later step's string literal (BUG-symput)" {
    // step 1 sets &a at run time; step 2's "&a" — unknown to the up-front macro
    // pass — must bind to it before step 2 compiles.
    try expectRun(
        "data _null_;\n  call symput(\"a\", \"hello\");\nrun;\n" ++
            "data _null_;\n  x = \"&a\";\n  put x=;\nrun;\n",
        "x=hello\n",
    );
    // symputx numeric value + trailing-dot delimiter inside a string
    try expectRun(
        "data _null_;\n  call symputx(\"n\", 42);\nrun;\n" ++
            "data _null_;\n  put \"n is &n.!\";\nrun;\n",
        "n is 42!\n",
    );
}

test "CALL SYMPUT var resolves BARE (unquoted) in a later step's expression (BUG-symputbare)" {
    // `&cnt` outside quotes: the lexer split it into `&` + name, so binding must
    // splice the re-lexed value back in — `n = &cnt + 1` → 7 + 1.
    try expectRun(
        "data _null_;\n  call symput(\"cnt\", \"7\");\nrun;\n" ++
            "data _null_;\n  n = &cnt + 1;\n  put n=;\nrun;\n",
        "n=8\n",
    );
    // bare &var in a comparison and a product
    try expectRun(
        "data _null_;\n  call symputx(\"m\", 3);\nrun;\n" ++
            "data _null_;\n  if &m > 2 then put \"big\";\n  y = &m * 10;\n  put y=;\nrun;\n",
        "big\ny=30\n",
    );
}

test "global statements: OPTIONS/TITLE/FOOTNOTE/FILENAME/ODS/X accepted, no DATA-step output (G-global)" {
    // TITLE/FOOTNOTE are settings, not statements that print here: a DATA step
    // emits only its own log (titles show atop a *proc* — see G-global-apply).
    try expectRun(
        "options nodate;\ntitle \"Rpt\";\nfootnote \"cf\";\ndata _null_;\n  put \"body\";\nrun;\n",
        "body\n",
    );
    // filename / ods / x accepted with no output, between and around a step
    try expectRun(
        "filename f \"/tmp/x\";\nods listing;\nx \"echo hi\";\ndata _null_;\n  put \"ok\";\nrun;\nods listing close;\n",
        "ok\n",
    );
    // a numbered title between two steps is inert until a proc consumes it
    try expectRun(
        "data _null_;\n  put \"a\";\nrun;\ntitle2 \"Mid\";\ndata _null_;\n  put \"b\";\nrun;\n",
        "a\nb\n",
    );
}

test "GAP-odsbatch: ODS destinations accepted-as-listing; SELECT/EXCLUDE/OUTPUT/TRACE fail loud" {
    // Group A: the `ods pdf; … ods pdf close;` wrap (and every other
    // destination/toggle form) runs and still prints the listing — no error.
    try expectRun(
        "data c; input x; datalines;\n1\n;\nrun;\n" ++
            "ods pdf file=\"x.pdf\";\nproc print data=c noobs; run;\nods pdf close;\n" ++
            "ods listing close;\nods listing;\nods html; ods html close;\nods html5;\n" ++
            "ods rtf; ods rtf close;\nods csv; ods excel; ods _all_ close;\n" ++
            "ods results; ods noresults;\nods graphics on; ods graphics off;\nods escapechar='^';\n" ++
            "proc printto; run;\nproc printto log=\"x.log\" print=\"x.lst\"; run;\n" ++
            "proc print data=c noobs; run;\n",
        "x\n\n1\nx\n\n1\n",
    );
    // Group B: captured diagnostics (D-003 — no spawned abort), each naming
    // its own sub-statement.
    inline for (.{
        .{ "ods select MyTable;\n", "ODS select is not supported yet" },
        .{ "ods exclude MyTable;\n", "ODS exclude is not supported yet" },
        .{ "ods output Summary=s;\n", "ODS OUTPUT (capture to dataset) is not supported yet" },
        .{ "ods trace on;\n", "ODS trace is not supported yet" },
    }) |case| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, case[0] ++ "data _null_; x=1; run;\n", null);
        try std.testing.expect(diags.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), case[1]) != null);
    }
}

test "BUG-optmissing: OPTIONS MISSING= char prints for a PLAIN missing numeric (PRINT + PUT)" {
    defer sas.io.global_missing = '.'; // module state — restore for later tests
    // core: a missing numeric prints the set char in PROC PRINT and list-PUT;
    // special missings keep their letter; `missing='.'` resets to the default.
    try expectRun(
        "options missing='X';\n" ++
            "data a; input id v w; datalines;\n1 . .A\n2 5 3\n;\nrun;\n" ++
            "proc print data=a; run;\n" ++
            "data _null_; x = .; y = ._; put x; put y; run;\n" ++
            "options missing='.';\n" ++
            "proc print data=a; run;\n",
        "Obs   id   v   w\n\n" ++
            "  1    1   X   A\n" ++
            "  2    2   5   3\n" ++
            "X\n_\n" ++
            "Obs   id   v   w\n\n" ++
            "  1    1   .   A\n" ++
            "  2    2   5   3\n",
    );
    // garbage fails LOUD (captured diagnostic, D-003 — no spawned abort)
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "options missing=;\ndata _null_; x=1; run;\n", null);
        try std.testing.expect(diags.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "Invalid value for the MISSING option.") != null);
    }
}

test "BUG-inputnosourcefabricates: INPUT with no INFILE and no DATALINES is a loud ERROR, not one fabricated all-missing obs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags, "data d; input x y; run;\nproc print data=d; run;\n", null);
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "No DATALINES or INFILE statement.") != null);
    // no fabricated observation reaches stdout (the PROC never prints a . . row)
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") == null);
    // a declared-but-EMPTY source (0-line datalines) stays quiet: 0 obs, no error
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    const a2 = arena2.allocator();
    var diags2 = sas.diag.Diagnostics.init(a2);
    var out2: std.ArrayList(u8) = .empty;
    try interpret(a2, &out2, &diags2, "data e; input x; datalines;\n;\nrun;\n", null);
    try std.testing.expect(!diags2.hasErrors());
}

test "GAP-filenameref: FILENAME fileref resolves for INFILE and FILE; PIPE fails loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io_ = std.Io.Threaded.global_single_threaded.io();
    const path = "/tmp/opensas_gap_filenameref.txt";
    defer Io.Dir.cwd().deleteFile(io_, path) catch {};
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    // `file REF;` writes through the fileref, `infile REF;` reads it back.
    try interpret(a, &out, &diags,
        "filename piomf \"/tmp/opensas_gap_filenameref.txt\";\n" ++
            "data _null_; file piomf; put \"via fileref\"; run;\n" ++
            "data back; infile piomf; input line $20.; run;\n" ++
            "proc print data=back; run;\n", io_);
    try std.testing.expect(!diags.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "via fileref") != null);
    // a re-declaration re-binds the fileref (no duplicate-slot leak)
    try std.testing.expectEqualStrings(path, findFileref("piomf").?);
    // PIPE device: no engine → fail LOUD at the FILENAME statement
    {
        var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena2.deinit();
        const a2 = arena2.allocator();
        var diags2 = sas.diag.Diagnostics.init(a2);
        var out2: std.ArrayList(u8) = .empty;
        try interpret(a2, &out2, &diags2, "filename piomcmd pipe \"echo hi\";\ndata _null_; x=1; run;\n", null);
        try std.testing.expect(diags2.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try diags2.render(), "FILENAME device pipe is not supported") != null);
    }
}

test "BUG-filenameconcatnoop: FILENAME concatenation form fails loud AT the FILENAME statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    // Language Reference: Concepts Table 21.5 (p.517): "FILENAME statement with concatenation" — was a
    // silent no-op; the INFILE then mis-errored as if the REF were undefined.
    try interpret(a, &out, &diags, "filename both ('fa.txt' 'fb.txt');\ndata _null_; infile both; input k $ v; run;\n", null);
    try std.testing.expect(diags.hasErrors());
    const r = try diags.render();
    try std.testing.expect(std.mem.indexOf(u8, r, "FILENAME concatenation") != null);
    // the error names the FILENAME statement (line 1), not the INFILE (line 2)
    try std.testing.expect(std.mem.indexOf(u8, r, "(L1)") != null);
    // a plain single-path FILENAME still registers and reads (control)
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    const a2 = arena2.allocator();
    var diags2 = sas.diag.Diagnostics.init(a2);
    var out2: std.ArrayList(u8) = .empty;
    try interpret(a2, &out2, &diags2, "filename ok 'f4control.txt';\ndata _null_; put \"CONTROL OK\"; run;\n", null);
    try std.testing.expect(!diags2.hasErrors());
    try std.testing.expectEqualStrings("f4control.txt", findFileref("ok").?);
}

test "GAP-liststmt: DATA-step LIST fails LOUD with a clear message (not the misleading assignment error)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags, "data a; input x; list; datalines;\n1\n;\nrun;\n", null);
    try std.testing.expect(diags.hasErrors()); // captured (D-003), no spawn
    const log = try diags.render();
    try std.testing.expect(std.mem.indexOf(u8, log, "The LIST statement is not supported") != null);
    try std.testing.expect(std.mem.indexOf(u8, log, "expected '=' in assignment") == null); // the old misdirection is gone
    // a variable NAMED list (`list = 5;`) is not the statement — still parses
    try expectRun("data _null_; list = 5; put list; run;\n", "5\n");
}

test "GAP-listingwidth: LINESIZE=/PAGESIZE= captured (inert), garbage fails loud" {
    defer {
        sas.io.global_linesize = 0;
        sas.io.global_pagesize = 0;
    }
    try expectRun(
        "options linesize=40 pagesize=10;\ndata a; x=1; run;\nproc print data=a; run;\n",
        "Obs   x\n\n  1   1\n",
    );
    try std.testing.expectEqual(@as(usize, 40), sas.io.global_linesize);
    try std.testing.expectEqual(@as(usize, 10), sas.io.global_pagesize);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags, "options pagesize=abc;\n", null);
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "Invalid value for the PAGESIZE option.") != null);
}

test "BUG-optionsstmtswallow: OPTIONS fails LOUD on typos/unsupported; the inert allowlist + honoured set stay accepted" {
    defer { // restore the module state the honoured arms set
        sas.io.global_obs = std.math.maxInt(usize);
        sas.io.global_firstobs = 1;
        sas.io.global_dkricond = .err;
        sas.io.global_dkrocond = .warn;
        sas.io.global_nobyline = false;
        sas.io.global_sortseq_linguistic = false;
    }
    // ── positive control (the D-014 anti-regression assertion): a realistic
    //    inert bundle + every HONOURED arm parses clean and the program runs.
    try expectRun(
        "options nodate nonumber center pageno=1 msglevel=i compress=yes reuse=no\n" ++
            "  validvarname=v7 fmtsearch=(work sashelp) mprint symbolgen minoperator\n" ++
            "  mindelimiter=',' bufsize=64k sortsize=16m threads stimer source notes\n" ++
            "  nolabel byline replace mergenoby=nowarn varinitchk=note dkricond=warn\n" ++
            "  sortseq=ascii obs=max firstobs=1;\n" ++
            "data d; x=1; run;\nproc print data=d noobs; run;\n",
        "x\n\n1\n",
    );
    try std.testing.expectEqual(sas.io.CondLevel.warn, sas.io.global_dkricond);
    // honoured: the K suffix is a magnitude, not a token to drop — obs=2k = 2048
    try expectRun("options obs=2k; data d; x=1; run;\n", "");
    try std.testing.expectEqual(@as(usize, 2048), sas.io.global_obs);

    const Case = struct { src: []const u8, msg: []const u8 };
    const cases = [_]Case{
        // a typo on a READ LIMIT — read EVERYTHING before this fix
        .{ .src = "options obbs=2;\n", .msg = "system option obbs is not recognized" },
        .{ .src = "options zzzznotanoption=5;\n", .msg = "system option zzzznotanoption is not recognized" },
        // result-changing but honoured only in the exec layer → LOUD gap
        .{ .src = "options varinitchk=error;\n", .msg = "system option VARINITCHK=error is not supported" },
        .{ .src = "options mergenoby=warn;\n", .msg = "system option MERGENOBY=warn is not supported" },
        .{ .src = "options noreplace;\n", .msg = "system option NOREPLACE is not supported" },
        .{ .src = "options sortseq=danish;\n", .msg = "system option SORTSEQ=danish is not supported" },
        // invalid VALUES on known options
        .{ .src = "options firstobs=0;\n", .msg = "Invalid value for the FIRSTOBS option." },
        .{ .src = "options mergenoby=zzz;\n", .msg = "Invalid value for the MERGENOBY option." },
        .{ .src = "options varinitchk=zzz;\n", .msg = "Invalid value for the VARINITCHK option." },
        .{ .src = "options validvarname=v8;\n", .msg = "Invalid value for the VALIDVARNAME option." },
        .{ .src = "options dkricond=zzz;\n", .msg = "Invalid value for the DKRICOND option." },
    };
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, c.src, null);
        try std.testing.expect(diags.hasErrors());
        const rendered = try diags.render();
        if (std.mem.indexOf(u8, rendered, c.msg) == null) {
            std.debug.print("for {s}: wanted '{s}' in:\n{s}", .{ c.src, c.msg, rendered });
            return error.TestUnexpectedResult;
        }
    }
}

test "BUG-opencodestmtswallow: unknown open-code statements fail LOUD naming the statement; the inert allowlist + anonymous fallback stay accepted" {
    // ── positive control (the D-014 anti-regression assertion): the full
    //    inert allowlist interleaved with real steps and globals runs clean.
    //    The `;` inside the DM string must not end the skip early.
    try expectRun(
        "dm 'log;clear';\ngoptions reset=all;\nsasfile work.d load;\ncatname pcats (work);\n" ++
            "options nodate;\ntitle 't';\ndata d; x=1; run;\nrun;\nquit;\nproc print data=d noobs; run;\n",
        "t\nx\n\n1\n",
    );
    // ── the anonymous whole-program open-code fallback is unchanged.
    try expectRun("x=5; put x=;\n", "x=5\n");

    const Case = struct { src: []const u8, msg: []const u8 };
    const cases = [_]Case{
        // a typo'd global that used to vanish — the listing was built on the
        // setting that never took effect, at exit 0
        .{ .src = "titl 'Study 06';\ndata d; x=1; run;\n", .msg = "statement titl is not valid in open code" },
        .{ .src = "data d; x=1; run;\nlibnam raw '/data';\n", .msg = "statement libnam is not valid in open code" },
        .{ .src = "data d; x=1; run;\nzzzq 5;\n", .msg = "statement zzzq is not valid in open code" },
        // an open-code assignment between steps is not a statement either
        .{ .src = "data d; x=1; run;\ny = 2;\n", .msg = "statement y is not valid in open code" },
    };
    // ── ENDSAS: an ordinary step boundary that ends the session NORMALLY
    //    (Language Reference: Concepts p.10, p.487; BUG-endsasexit). Everything before it ran and
    //    printed; nothing after it is read; exit 0 (no diags errors).
    const endsas_cases = [_]struct { src: []const u8, want: []const u8 }{
        // the F4 repro: a trailing endsas; on a complete correct run
        .{ .src = "data d; x=1; run;\nproc print data=d noobs; run;\nendsas;\n", .want = "x\n\n1\n" },
        // mid-program: steps before it printed; later steps never run
        .{ .src = "data d; x=1; run;\nproc print data=d noobs; run;\nendsas;\ndata e; y=2; run;\nproc print data=e noobs; run;\n", .want = "x\n\n1\n" },
        // endsas FIRST: nothing runs at all, still exit 0
        .{ .src = "endsas;\ndata d; x=1; run;\n", .want = "" },
    };
    for (endsas_cases) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, c.src, null);
        try std.testing.expect(!diags.hasErrors()); // NORMAL termination — exit 0
        try std.testing.expectEqualStrings(c.want, out.items);
    }
    // ── ENDSAS mid-STEP (BUG-endsasmidstep, QA tick322 F5): the same ordinary
    //    step boundary INSIDE a step — the step runs with the statements
    //    before it (the listing prints), the session ends, nothing after is
    //    read, exit 0. Pre-fix the PROC loop's fail-loud ate it: listing lost
    //    AND the post-endsas steps ran (the error went to g_failed, so
    //    errhalt never engaged). Assert BOTH no-diags and no-g_failed.
    const mid_cases = [_]struct { src: []const u8, want: []const u8 }{
        // the F5 repro: endsas inside a PROC PRINT step
        .{ .src = "data d; x=1; run;\nproc print data=d noobs;\nendsas;\nrun;\ndata e; y=2; run;\nproc print data=e noobs; run;\n", .want = "x\n\n1\n" },
        // mid-DATA-step: the step's statements before endsas run (d is
        // written), then the session ends — nothing prints, exit 0
        .{ .src = "data d; x=1;\nendsas;\nrun;\nproc print data=d noobs; run;\n", .want = "" },
        // positive control: `endsas = 5;` is a plain ASSIGNMENT (the `=`
        // guard) — the session does NOT end, the print after it runs
        .{ .src = "data d; endsas = 5; run;\nproc print data=d noobs; run;\n", .want = "endsas\n\n     5\n" },
    };
    for (mid_cases) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        g_failed = false;
        try interpret(a, &out, &diags, c.src, null);
        try std.testing.expect(!diags.hasErrors() and !g_failed); // NORMAL termination — exit 0
        try std.testing.expectEqualStrings(c.want, out.items);
    }
    // an ERROR before endsas still exits nonzero — endsas is not an eraser
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data d; x=1; run;\nzzzq 5;\nendsas;\nproc print data=d noobs; run;\n", null);
        try std.testing.expect(diags.hasErrors());
        try std.testing.expectEqualStrings("", out.items); // errhalt + endsas: nothing after zzzq ran
    }
    for (cases) |c| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, c.src, null);
        try std.testing.expect(diags.hasErrors());
        const rendered = try diags.render();
        if (std.mem.indexOf(u8, rendered, c.msg) == null) {
            std.debug.print("for {s}: wanted '{s}' in:\n{s}", .{ c.src, c.msg, rendered });
            return error.TestUnexpectedResult;
        }
    }
    // ── in-position semantics (SAS batch): steps BEFORE the bad statement ran;
    //    the error errhalt-skips every LATER step (BUG-errhalt).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try interpret(a, &out, &diags, "data d; x=1; run;\nproc print data=d noobs; run;\nzzzq 5;\nproc print data=d noobs; run;\n", null);
    try std.testing.expect(diags.hasErrors());
    try std.testing.expectEqualStrings("x\n\n1\n", out.items); // printed once, not twice
}

test "BUG-missingstmtwrongclass: open-code MISSING is a NAMED rc-2 gap (was rc-1 'not valid in open code'); `missing =` stays the generic error" {
    // The MISSING statement declares special missing values (Language Reference: Concepts printed
    // p.519, a worked example shown TWICE) — VALID SAS real SAS runs clean, so
    // refusing it is OUR gap: rc 2 (D-009/D-009b(i)), with a message naming
    // MISSING, identical to parser.zig's DATA-step arm (D-009b corollary).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        resetRcSignals();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data d; x=1; run;\nmissing A;\n", null);
        try std.testing.expect(diags.hasErrors());
        const rendered = try diags.render();
        try std.testing.expect(std.mem.indexOf(u8, rendered, "the MISSING statement (special missing values) is not supported") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, "not valid in open code") == null); // the OLD misclass is gone
        try std.testing.expectEqual(@as(u8, 2), testRc(&diags));
    }
    // `missing = 5;` in open code is not the statement — keeps the generic
    // open-code error at rc 1 (the `=` guard).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        resetRcSignals();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data d; x=1; run;\nmissing = 5;\n", null);
        try std.testing.expect(diags.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "statement missing is not valid in open code") != null);
        try std.testing.expectEqual(@as(u8, 1), testRc(&diags));
    }
}

test "BUG-xstmtopencodesplit: open-code X (quoted AND bare-name) and open-code DM redirection NOTE (D-022); windowing DM stays silent (GH#83)" {
    const noteCount = struct {
        fn f(diags: *const sas.diag.Diagnostics, needle: []const u8) usize {
            var n: usize = 0;
            for (diags.list.items) |d| {
                if (d.severity == .note and std.mem.indexOf(u8, d.message, needle) != null) n += 1;
            }
            return n;
        }
    }.f;

    // Open-code X in BOTH spellings notes and does not errhalt. The bare-name
    // form (`x mkdir "…";`) is the split itself: mid-step it sailed through,
    // in open code it used to ERROR "not valid in open code" rc 1 — one
    // recognizer now (parser.zig's x/dm arm and main.zig's isXStmt agree).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data t; a=1; run;\n" ++
            "x \"mkdir /tmp/gh83_quoted_never\";\n" ++
            "x mkdir \"/tmp/gh83_bare_never\";\n" ++
            "proc print data=t noobs; run;\n", null);
        try std.testing.expect(!diags.hasErrors()); // NOTEs, never an ERROR — rc stays 0
        try std.testing.expectEqualStrings("a\n\n1\n", out.items); // the steps AROUND the X statements ran
        try std.testing.expectEqual(@as(usize, 2), noteCount(&diags, "X statement not executed"));
    }
    // Open-code DM log-redirection notes — dm_statement.sas's last-line case,
    // unreachable from the parser-only fix (the inert skip is main.zig's).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data t; a=1; run;\ndm log \"file '/tmp/gh83_never_written.log' replace;\";\nproc print data=t noobs; run;\n", null);
        try std.testing.expect(!diags.hasErrors());
        try std.testing.expectEqual(@as(usize, 1), noteCount(&diags, "DM statement not executed"));
    }
    // …but a file holding ONLY that line falls back to the anonymous
    // `data _null_` run, whose parser arm notes the very same statement — the
    // segmenter must NOT note it a second time.
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "dm log \"file '/tmp/gh83_never_written.log' replace;\";\n", null);
        try std.testing.expect(!diags.hasErrors());
        try std.testing.expectEqual(@as(usize, 1), noteCount(&diags, "DM statement not executed"));
    }
    // NEGATIVE CONTROL, and the load-bearing one: the open-code windowing
    // idiom stays SILENT — the DM predicate matches WHOLE WORDS, so the
    // "out" inside "output;clear" must not fire it (the commonest DM idiom
    // in the corpus would note for nothing).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, "data t; a=1; run;\ndm 'log;clear;output;clear';\nproc print data=t noobs; run;\n", null);
        try std.testing.expect(!diags.hasErrors());
        try std.testing.expectEqual(@as(usize, 0), diags.count());
        try std.testing.expectEqualStrings("a\n\n1\n", out.items);
    }
}

test "TITLE/FOOTNOTE print atop/below a proc listing and persist across procs (G-global-apply)" {
    // title atop the PRINT table, footnote below; both persist to the 2nd proc.
    try expectRun(
        \\data d;
        \\  input x;
        \\  datalines;
        \\1
        \\2
        \\;
        \\run;
        \\title "Rpt";
        \\footnote "cf";
        \\proc print data=d noobs; run;
        \\proc print data=d noobs; run;
    ,
        "Rpt\nx\n\n1\n2\ncf\nRpt\nx\n\n1\n2\ncf\n",
    );
    // `title;` clears every line, so a later proc has no title
    try expectRun(
        \\data d;
        \\  input x;
        \\  datalines;
        \\1
        \\;
        \\run;
        \\title "Gone";
        \\title;
        \\proc print data=d noobs; run;
    ,
        "x\n\n1\n",
    );
}

test "put with a format, and a format statement applied by PROC PRINT (F1)" {
    // put statement with trailing format specs
    try expectRun(
        "data _null_;\n  x = 3.14159;\n  put x 8.2;\nrun;\n",
        "    3.14\n",
    );
    // `format` statement → the display format PROC PRINT renders
    try expectRun(
        \\data have;
        \\  input x;
        \\  format x comma8.2;
        \\  datalines;
        \\1234.5
        \\;
        \\run;
        \\proc print data=have;
        \\run;
        \\
    ,
        "Obs          x\n\n  1   1,234.50\n",
    );
}

test "retain + input + datalines drives the loop" {
    try expectRun(
        "data _null_;\n  retain t 0;\n  input x;\n  t = t + x;\n  put \"t=\" t;\n  datalines;\n1\n2\n3\n;\nrun;\n",
        "t=1\nt=3\nt=6\n",
    );
}

test "two steps: set reads the first step's dataset, then proc print" {
    try expectRun(
        \\data nums;
        \\  input v;
        \\  datalines;
        \\5
        \\7
        \\;
        \\run;
        \\data _null_;
        \\  set nums;
        \\  put "v=" v;
        \\run;
        \\
    ,
        "v=5\nv=7\n",
    );
}

test "stepStarts ignores a `data`-named assignment target" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = sas.diag.Diagnostics.init(a);
    const toks = try sas.lexer.tokenize(a, "data _null_; data = 1; run;", &diags);
    const starts = try stepStarts(a, toks);
    try std.testing.expectEqual(@as(usize, 1), starts.len); // only the leading `data`
}

test "unsupported PROC/CALL fails loud (CLIN-failloud)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;

    // an unsupported PROC sets the fail flag → main exits non-zero. The fail-loud
    // message is captured (not stderr) in a test build (TEST-quietnoise).
    g_failed = false;
    g_test_last_err = "";
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, "proc bogus data=x; run;", null);
    try std.testing.expect(g_failed);
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "bogus") != null);

    // an unsupported CALL routine reports an ERROR diagnostic (hasErrors → exit)
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, "data _null_;\n  call bogusroutine(1);\nrun;\n", null);
    try std.testing.expect(d2.hasErrors());

    // a supported program stays clean — no false failure
    g_failed = false;
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, "data _null_;\n  x = 1;\n  put x=;\nrun;\n", null);
    try std.testing.expect(!g_failed and !d3.hasErrors());
}

test "GAP-procprint: bad var / char SUM are user ERRORs (rc=1); unknown option is a gap (rc=2); ID replaces Obs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var out: std.ArrayList(u8) = .empty;

    // F3: a `var` naming no column is a typo that would silently drop a clinical
    // column → user ERROR via the captured reporter (rc=1), no output printed.
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1, "data d; id=1; x=2; output; run;\nproc print data=d; var id nosuchvar x; run;\n", null);
    try std.testing.expect(d1.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try d1.render(), "NOSUCHVAR not found") != null);
    try std.testing.expectEqualStrings("", out.items); // step stopped before printing

    // F2: summing a character column is a type error (was a bogus 0/==== total).
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2, "data d; c=\"AB\"; output; run;\nproc print data=d; var c; sum c; run;\n", null);
    try std.testing.expect(d2.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try d2.render(), "does not match type prescribed") != null);

    // F4: an unrecognized PROC PRINT option is no longer swallowed — fail loud as
    // an opensas gap (rc=2, captured in g_test_last_err in a test build).
    g_failed = false;
    g_test_last_err = "";
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3, "data d; x=1; output; run;\nproc print data=d frobnicate; var x; run;\n", null);
    try std.testing.expect(g_failed);
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "frobnicate") != null);

    // F1: `id` suppresses the Obs column (id var leftmost); clean run, no output loss.
    g_failed = false;
    out.clearRetainingCapacity();
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4, "data d; input s $ v; datalines;\nX 5\n;\nrun;\nproc print data=d; id s; var v; run;\n", null);
    try std.testing.expect(!g_failed and !d4.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") == null); // Obs replaced by id
}

test "PROCBY-printfreq: PRINT BY DESCENDING honored (unsorted-per-spec loud) / FREQ BY fail loud; plain PRINT BY sections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data d; do g = 1 to 2; x = g; output; end; run;\n";

    // plain BY baseline: sectioned listing, no errors (no regression)
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc print data=d; by g; run;", null);
        try std.testing.expect(!d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, out.items, "g=1") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "g=2") != null);
    }
    // PRINT BY DESCENDING on DESCENDING-sorted data → sections, largest first
    // (GAP-procbydescending — was: loud "plain ascending BY only").
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc sort data=d out=dd; by descending g; run;\nproc print data=dd; by descending g; run;", null);
        try std.testing.expect(!d.hasErrors());
        const p2 = std.mem.indexOf(u8, out.items, "g=2").?;
        const p1 = std.mem.indexOf(u8, out.items, "g=1").?;
        try std.testing.expect(p2 < p1);
    }
    // PRINT BY DESCENDING on ASCENDING data → loud ERROR naming the direction
    // (the sortedness guard flips per key; the printTable guard reports through
    // `diags` at rc 1 — DEC-abortrcvsD009 — the BUG-printbyunsorted contract).
    {
        resetRcSignals();
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc print data=d; by descending g; run;", null);
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "not sorted in descending sequence") != null);
        try std.testing.expectEqual(@as(u8, 1), testRc(&d));
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") == null);
    }
    // FREQ BY → captured ERROR, no GLOBAL table (was: BY ignored entirely)
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc freq data=d; by g; tables x; run;", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Frequency") == null);
    }
}

test "BUG-byvarnotfound: PRINT BY on an unknown variable fails loud; valid BY unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data d; do g = 1 to 2; x = g; output; end; run;\n";

    // `by nosuch;` → captured ERROR "Variable NOSUCH not found.", no listing
    // (was: flat section, empty BY line, rc 0 — the lost-BY-line class).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc print data=d; by nosuch; run;", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "NOSUCH not found") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") == null);
    }
    // partially valid `by g nosuch;` → fails loud on NOSUCH, not silently by g alone
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc print data=d; by g nosuch; run;", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "NOSUCH not found") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Obs") == null);
    }
    // valid BY still sections (no regression from the new branch)
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, mk ++ "proc print data=d; by g; run;", null);
        try std.testing.expect(!d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, out.items, "g=1") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "g=2") != null);
    }
}

test "GH#15 ISS-readonlyguard: output access to ACCESS=READONLY libref fails loud; reads pass" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ro = "libname src \"/tmp/opensas_gh15_nodir\" access=readonly;\n";
    const RO = "read-only library";

    // (1) DATA SRC.NEW — CREATING a member in a read-only libref → captured ERROR
    // (was: silent exit 0). The data-step write routes through Library.put.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, ro ++ "data src.new; x = 1; run;", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), RO) != null);
    }
    // (2) PROC SORT DATA=SRC.EC (no OUT=) — IN-PLACE mutation of a read-only member
    // → captured ERROR (was: silent in-memory sort, exit 0). This path never hits
    // Library.put, so it is guarded at the PROC SORT dispatch.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, ro ++ "proc sort data=src.ec; by x; run;", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), RO) != null);
    }
    // (3) READ access is untouched: a SET of a read-only member emits NO read-only
    // ERROR (the member simply isn't loaded here, so a warn/skip at most).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, ro ++ "data work.x; set src.ec; run;", null);
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), RO) == null);
    }
    // (4) PROC SORT ... OUT=WORK.s reading a read-only source writes to WORK, not
    // the source → NO read-only ERROR (only in-place / output-to-readonly aborts).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, ro ++ "proc sort data=src.ec out=work.s; by x; run;", null);
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), RO) == null);
    }
}

test "writeLibOutputs skips read-only-loaded inputs, persists created datasets (E-sas7write-noreadback)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `src.nums` was loaded read-only; `target.sorted` was created this run.
    const loaded = try a.create(sas.dataset.Dataset);
    loaded.* = sas.dataset.Dataset.init(a, "src.nums");
    const created = try a.create(sas.dataset.Dataset);
    created.* = sas.dataset.Dataset.init(a, "target.sorted");
    const loaded_ro = [_]*sas.dataset.Dataset{loaded};

    try std.testing.expect(!shouldPersist(loaded, &loaded_ro)); // read-only input → not re-written
    try std.testing.expect(shouldPersist(created, &loaded_ro)); // created → persisted

    // A `data src.nums; …;` re-creates the name as a NEW object → persisted again.
    const replaced = try a.create(sas.dataset.Dataset);
    replaced.* = sas.dataset.Dataset.init(a, "src.nums");
    try std.testing.expect(shouldPersist(replaced, &loaded_ro));
}

test "GAP-xport0colskip: a 0-variable dataset refuses BOTH writes LOUDLY (no phantom CSV); 1-column control still writes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io_ = std.Io.Threaded.global_single_threaded.io();
    const lr = Libref{ .name = "o", .dir = "/tmp/opensas_0col", .readonly = false };

    // 0 columns: real SAS CREATES the set with a bare NOTE (Macro Language Ref,
    // SYSDATASTEPPHASE ex. 2, printed p. 246/pdf 261 — "NOTE: The data set
    // WORK.NULL has 1 observations and 0 variables."), so the set lives; only
    // the native write refuses, and it must be LOUD (a silent skip is the no-op
    // house rules forbid; cf3fecc6 sibling = ERROR). SEV-zerocolrefusal kept
    // exit 2: p.246 is a WORK set and that program already exits 0 here, so the
    // citation and this refusal are about different layers (see writeMember).
    // 1 observation, 0 variables — the documented shape exactly.
    const empty = try a.create(sas.dataset.Dataset);
    empty.* = sas.dataset.Dataset.init(a, "o.empty");
    try empty.appendRow(&.{});
    // A leftover from an earlier run would make the two absence assertions below
    // pass or fail for the wrong reason — start from a known-clean directory.
    Io.Dir.cwd().deleteFile(io_, "/tmp/opensas_0col/empty.sas7bdat") catch {};
    Io.Dir.cwd().deleteFile(io_, "/tmp/opensas_0col/empty.csv") catch {};
    g_failed = false;
    g_test_last_err = "";
    try writeMember(a, io_, lr, "empty", empty);
    try std.testing.expect(g_failed); // → exit 2 (D-009 gap), never exit 0
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "0-variable") != null);
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().access(io_, "/tmp/opensas_0col/empty.sas7bdat", .{}));

    // BUG-csvzerocolphantom: NEITHER file may exist. The CSV used to be written
    // as two bytes ("\n\n") that reloaded as one phantom VAR1 column with 0
    // observations — the observation lost AND a variable fabricated. CSV has no
    // encoding for 0 variables (io.writeCsvImpl explains both grounds), so the
    // writer refuses and the sidecar is no longer created; that reload lie is
    // pinned directly on the two bytes by io.zig's BUG-csvzerocolphantom test,
    // so it stays proven rather than merely asserted here.
    try std.testing.expectError(error.FileNotFound, Io.Dir.cwd().access(io_, "/tmp/opensas_0col/empty.csv", .{}));
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "does NOT survive") != null);

    // Control: a normal 1-column member must NOT move — writes, no fail-loud.
    const ctrl = try a.create(sas.dataset.Dataset);
    ctrl.* = sas.dataset.Dataset.init(a, "o.ctrl");
    _ = try ctrl.addColumn("x", .num);
    try ctrl.appendRow(&.{.{ .num = 1 }});
    g_failed = false;
    try writeMember(a, io_, lr, "ctrl", ctrl);
    try std.testing.expect(!g_failed);
    const s7 = try Io.Dir.cwd().readFileAlloc(io_, "/tmp/opensas_0col/ctrl.sas7bdat", a, max_file);
    const back = try sas.io.readSas7bdat(a, s7, "o.ctrl"); // and it reads back
    try std.testing.expectEqual(@as(usize, 1), back.columns.items.len);
    g_failed = false; // leave the global clean for later tests
}

test "BUG-iostreamclobber: stdout writer is STREAMING, never positional" {
    // Positional mode pwrites at a tracked offset starting at 0 — under
    // `sas prog > log 2>&1` that collides with stderr's own offset-0 start and
    // silently clobbers output. Streaming writes at the shared OS position.
    var buf: [64]u8 = undefined;
    const w = stdoutWriter(std.testing.io, &buf);
    try std.testing.expect(w.mode == .streaming);
}

fn diagHas(d: *const sas.diag.Diagnostics, needle: []const u8) bool {
    for (d.list.items) |it| if (std.mem.indexOf(u8, it.message, needle) != null) return true;
    return false;
}

test "FILE libref serves only the file's own member name + applies sibling .labels (BUG-filelibrefmember)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io_ = std.Io.Threaded.global_single_threaded.io();

    // A .sas7bdat + .labels sidecar, and an XPT whose STAMPED member name
    // ("flm") deliberately differs from the filename stem ("opensas_flm").
    var ds = sas.dataset.Dataset.init(a, "flm");
    _ = try ds.addColumn("usubjid", .char);
    _ = try ds.addColumn("age", .num);
    try ds.appendRow(&.{ .{ .str = "S1" }, .{ .num = 34 } });
    ds.setLabel("usubjid", "Unique Subject");
    ds.setFormat("age", "3.");
    const s7 = "/tmp/flm_ae.sas7bdat";
    const s7l = "/tmp/flm_ae.labels";
    const xp = "/tmp/opensas_flm.xpt";
    defer Io.Dir.cwd().deleteFile(io_, s7) catch {};
    defer Io.Dir.cwd().deleteFile(io_, s7l) catch {};
    defer Io.Dir.cwd().deleteFile(io_, xp) catch {};
    try Io.Dir.cwd().writeFile(io_, .{ .sub_path = s7, .data = try sas.io.writeSas7bdat(a, &ds) });
    try Io.Dir.cwd().writeFile(io_, .{ .sub_path = s7l, .data = (try sas.io.labelSidecar(a, &ds)).? });
    try Io.Dir.cwd().writeFile(io_, .{ .sub_path = xp, .data = try sas.io.writeXport(a, &ds) });

    // 1) correct member name reads — and the sibling .labels sidecar (label +
    //    format) survives a FILE-libref read, as on the directory path (F9).
    var out: std.ArrayList(u8) = .empty;
    var d1 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d1,
        "libname f \"/tmp/flm_ae.sas7bdat\";\n" ++
            "data back; set f.flm_ae; run;\n" ++
            "data _null_; dsid=open(\"back\");\n" ++
            "  l=varlabel(dsid,1); fm=varfmt(dsid,2);\n" ++
            "  put \"LBL=\" l; put \"FMT=\" fm; rc=close(dsid); run;\n", io_);
    try std.testing.expect(!d1.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "LBL=Unique Subject") != null); // label survived
    try std.testing.expect(std.mem.indexOf(u8, out.items, "FMT=3.") != null); // format survived

    // 2) F6: a typo'd member name is NOT served the one file — the load is
    //    refused, so SET fails loud like any absent member (captured diag).
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d2,
        "libname f \"/tmp/flm_ae.sas7bdat\";\ndata nope; set f.zzz_nonexistent; run;\n", io_);
    try std.testing.expect(d2.hasErrors());
    try std.testing.expect(diagHas(&d2, "File f.zzz_nonexistent does not exist"));

    // 3) XPT: the STAMPED member name governs — `x.flm` reads even though the
    //    stem is "opensas_flm", and `x.opensas_flm` is refused.
    out.clearRetainingCapacity();
    var d3 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d3,
        "libname x \"/tmp/opensas_flm.xpt\";\ndata back; set x.flm; run;\n", io_);
    try std.testing.expect(!d3.hasErrors());
    out.clearRetainingCapacity();
    var d4 = sas.diag.Diagnostics.init(a);
    try interpret(a, &out, &d4,
        "libname x \"/tmp/opensas_flm.xpt\";\ndata nope; set x.opensas_flm; run;\n", io_);
    try std.testing.expect(diagHas(&d4, "does not exist"));
}

test "F7(a): a second member into one XPORT libref fails loud and the first member survives" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io_ = std.Io.Threaded.global_single_threaded.io();
    const xp = "/tmp/f7a_multi.xpt";
    defer Io.Dir.cwd().deleteFile(io_, xp) catch {};

    // The silent-wrong repro: two members through one .xpt libref used to exit
    // 0 with ONLY the second on disk. Now the second is refused LOUDLY
    // (captured, never a real aborting process) and member ONE is preserved.
    var out: std.ArrayList(u8) = .empty;
    var d = sas.diag.Diagnostics.init(a);
    g_failed = false;
    g_test_last_err = "";
    try interpret(a, &out, &d,
        "libname o xport \"/tmp/f7a_multi.xpt\";\n" ++
            "data o.one; x=1; run;\n" ++
            "data o.two; y=2; run;\n", io_);
    try std.testing.expect(g_failed);
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "already holds member one") != null);
    try std.testing.expect(std.mem.indexOf(u8, g_test_last_err, "member two NOT written") != null);

    // the file on disk still holds member one, intact
    const bytes = try Io.Dir.cwd().readFileAlloc(io_, xp, a, max_file);
    try std.testing.expectEqualStrings("one", sas.io.xptStampedMember(bytes).?);
    const back = try sas.io.readXport(a, bytes, "one");
    try std.testing.expectEqual(@as(usize, 1), back.columns.items.len); // x, not y
    try std.testing.expectEqualStrings("x", back.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), back.rows.items.len);

    // re-writing the SAME member to the same path stays a legal replace
    out.clearRetainingCapacity();
    var d2 = sas.diag.Diagnostics.init(a);
    g_failed = false;
    g_test_last_err = "";
    try interpret(a, &out, &d2,
        "libname o xport \"/tmp/f7a_multi.xpt\";\ndata o.one; x=99; run;\n", io_);
    try std.testing.expect(!g_failed);
    try std.testing.expect(!d2.hasErrors());
}

test "GAP-libnameopt + GAP-filenameopt: LIBNAME/FILENAME option lists end in a real else (captured diags)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ── the audit probes: an unknown option ran CLEAN at exit 0 ──
    // `libname x "p" bogusopt=1;` → one captured ERROR naming the option, and
    // the later step errhalt-skips (the error trips syntax-check mode).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname zzzq \"nowhere\" bogusopt=1;\ndata _null_; put \"LOST\"; run;\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "LIBNAME option bogusopt is not supported") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "LOST") == null);
    }
    // the audit's typo risk: `acces=readonly` must die NAMED — never silently
    // leave the lib unprotected (the old word-scan even matched the value,
    // hiding the typo while binding read-write).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname zzzq \"nowhere\" acces=readonly;\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "LIBNAME option acces is not supported") != null);
    }
    // an invalid ACCESS= value → captured ERROR (SAS wording class, like OPTIONS)
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname zzzq \"nowhere\" access=bogus;\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "Invalid value for the ACCESS= LIBNAME option.") != null);
    }
    // positive: ACCESS=TEMP + the inert COMPRESS=/REUSE= storage pair parse and
    // bind; ACCESS=READONLY still marks the libref readonly (GH#15 machinery).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname zzzq \"nowhere\" access=temp compress=yes reuse=no;\nlibname ro \"nowhere\" access=readonly compress=char;\ndata _null_; put \"OK\"; run;\n", null);
        try std.testing.expect(!d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, out.items, "OK") != null);
    }
    // FILENAME: a typo'd trailing option ran clean (audit probe) → now named
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "filename zzzf \"nowhere.txt\" lrelc=100;\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "FILENAME option lrelc is not supported") != null);
    }
    // FILENAME RECFM=<fixed-length> → loud (the reader is variable-length only)
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "filename zzzf \"nowhere.txt\" recfm=f;\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "RECFM=f") != null);
    }
    // positive: the inert pile (LRECL=/TERMSTR=/RECFM=V) registers the fileref,
    // and the no-path forms (`clear`, bare) stay accepted-inert.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "filename zzzf \"nowhere.txt\" lrecl=32767 termstr=crlf recfm=v;\nfilename zzzf clear;\nfilename zzzg;\ndata _null_; put \"OK2\"; run;\n", null);
        try std.testing.expect(!d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, out.items, "OK2") != null);
    }
}

test "GAP-ebnfrcwrongclass: documented-but-unimplemented LIBNAME options (INENCODING=/OUTENCODING=/CVPMULTIPLIER=) are NAMED rc-2 gaps; typos and plain cvp= stay rc 1" {
    // The catch-all's message already NAMED the option but exited rc 1 — "your
    // SAS is broken" — for options real SAS runs clean. The documented set is
    // OUR gap: rc 2 (D-009/D-009b(i)), message byte-identical (proc.zig's
    // isFreqTablesGapOption split shape). Citations in isDocLibnameGapOpt.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Each documented option: one captured ERROR naming it, at rc 2.
    for ([_][]const u8{ "outencoding=\"utf-8\"", "inencoding=wlatin1", "cvpmultiplier=2.5" }) |opt| {
        resetRcSignals();
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        const src = try std.fmt.allocPrint(a, "libname zzzq \"nowhere\" {s};\n", .{opt});
        try interpret(a, &out, &d, src, null);
        try std.testing.expect(d.hasErrors());
        const rendered = try d.render();
        try std.testing.expect(std.mem.indexOf(u8, rendered, "LIBNAME option ") != null);
        try std.testing.expect(std.mem.indexOf(u8, rendered, " is not supported") != null);
        try std.testing.expectEqual(@as(u8, 2), testRc(&d));
    }
    // A typo (`bogusopt`, `acces`) keeps the rc-1 typo class — never a false
    // rc 2 — and plain `cvp=` stays rc 1 too: the docs document the CVP
    // ENGINE (Statements Ref printed p.221, already rc 2 in the engine arm),
    // but no `CVP=` LIBNAME OPTION exists in them (the tick431 row's premise).
    for ([_][]const u8{ "bogusopt=1", "acces=readonly", "cvp=yes" }) |opt| {
        resetRcSignals();
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        const src = try std.fmt.allocPrint(a, "libname zzzq \"nowhere\" {s};\n", .{opt});
        try interpret(a, &out, &d, src, null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), " is not supported") != null);
        try std.testing.expectEqual(@as(u8, 1), testRc(&d));
    }
}

test "NOTE-libnameengine: an unknown LIBNAME engine fails loud (SAS: 'engine cannot be found'); BASE/V9/XPORT bind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ── the audit probe: `libname t boguseng "x";` ran CLEAN at exit 0 ──
    // → one captured ERROR in SAS's own wording, later steps errhalt-skip.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname t boguseng \"nowhere\";\ndata _null_; put \"LOST\"; run;\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "The boguseng engine cannot be found.") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "LOST") == null);
    }
    // a doc-named but UNIMPLEMENTED engine (JSON — Statements Ref p.221 stub)
    // rejects AT THE STATEMENT too: there is no later loud point (engine slot
    // is advisory; format is extension-sniffed), so deferral = silent swallow.
    // GAP-gapsexitingone §5d re-classed it: real SAS 9.4 HAS the JSON engine,
    // so the refusal is a gap — named "not supported" and rc 2 (pinned in the
    // §5d test below), not SAS's rc-1 "cannot be found".
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname t json \"nowhere\";\n", null);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), "LIBNAME engine json is not supported (BASE/V9/XPORT only)") != null);
    }
    // positive: the engines for the formats opensas implements bind clean —
    // BASE, its documented alias V9 (Procedures Guide p.1032), XPORT (p.531),
    // any case; and engine-less forms are untouched.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d, "libname a BASE \"nowhere\";\nlibname b v9 \"nowhere\";\nlibname c Xport \"nowhere.xpt\";\nlibname e \"nowhere\";\ndata _null_; put \"OK\"; run;\n", null);
        try std.testing.expect(!d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, out.items, "OK") != null);
    }
}

test "NOTE-truncreadmsg: a truncated sas7bdat/xpt member reports 'damaged or truncated' — never 'does not exist'" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io_ = std.Io.Threaded.global_single_threaded.io();

    // Build truncated members from real fixture bytes (hermetic), in /tmp like
    // the F7/FLM tests, deleted on exit.
    const s7 = try Io.Dir.cwd().readFileAlloc(io_, "tests/corpus/includes/dslabel/d.sas7bdat", a, max_file);
    const s7p = "/tmp/opensas_lb_trunc.sas7bdat";
    defer Io.Dir.cwd().deleteFile(io_, s7p) catch {};
    try std.testing.expect(sas.io.writeFileRaw(s7p, s7[0..200]));
    const xp = try Io.Dir.cwd().readFileAlloc(io_, "tests/corpus/includes/pc_ae.xpt", a, max_file);
    const xpp = "/tmp/opensas_lb_trunc.xpt";
    defer Io.Dir.cwd().deleteFile(io_, xpp) catch {};
    try std.testing.expect(sas.io.writeFileRaw(xpp, xp[0..400]));

    // 1) FILE-libref, truncated sas7bdat: ONE truthful ERROR naming the real
    //    cause; the misleading "does not exist" never prints; the referencing
    //    step errhalt-skips (captured diags — no real aborting process).
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d,
            "libname f \"/tmp/opensas_lb_trunc.sas7bdat\";\ndata d; set f.opensas_lb_trunc; put \"RAN\"; run;\n", io_);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(diagHas(&d, "the file exists but is damaged or truncated"));
        try std.testing.expect(!diagHas(&d, "does not exist"));
        try std.testing.expect(std.mem.indexOf(u8, out.items, "RAN") == null);
        // reported ONCE although the loader runs an up-front AND a per-chunk pass
        const r = try d.render();
        const first = std.mem.indexOf(u8, r, "damaged or truncated").?;
        try std.testing.expect(std.mem.indexOf(u8, r[first + 1 ..], "damaged or truncated") == null);
    }
    // 2) FILE-libref, truncated xpt: same truthful shape.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d,
            "libname x \"/tmp/opensas_lb_trunc.xpt\";\ndata d; set x.opensas_lb_trunc; run;\n", io_);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(diagHas(&d, "the file exists but is damaged or truncated"));
        try std.testing.expect(!diagHas(&d, "does not exist"));
    }
    // 3) DIR-libref: a damaged .sas7bdat must NOT silently fall through to a
    //    stale .csv sidecar of the same member (D-002) — loud, csv never read.
    {
        const dp = "/tmp/opensas_lb_dd.sas7bdat";
        defer Io.Dir.cwd().deleteFile(io_, dp) catch {};
        try std.testing.expect(sas.io.writeFileRaw(dp, s7[0..200]));
        const cp = "/tmp/opensas_lb_dd.csv";
        defer Io.Dir.cwd().deleteFile(io_, cp) catch {};
        try std.testing.expect(sas.io.writeFileRaw(cp, "x\nSENTINEL_CSV_ROW\n"));
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d,
            "libname t \"/tmp\";\ndata d; set t.opensas_lb_dd; run;\nproc print data=d noobs; run;\n", io_);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(diagHas(&d, "the file exists but is damaged or truncated"));
        try std.testing.expect(std.mem.indexOf(u8, out.items, "SENTINEL_CSV_ROW") == null);
    }
    // 4) control: a genuinely MISSING member still says "does not exist" —
    //    that message is truthful there and must not move.
    {
        var out: std.ArrayList(u8) = .empty;
        var d = sas.diag.Diagnostics.init(a);
        try interpret(a, &out, &d,
            "libname t \"/tmp\";\ndata d; set t.opensas_lb_absent; run;\n", io_);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(diagHas(&d, "does not exist"));
        try std.testing.expect(!diagHas(&d, "damaged or truncated"));
    }
}

test "BUG-dropoptfalsewarn: output dataset-option drop=/keep=/rename= of a referenced end=/in= temp draws no false 'never been referenced'; a typo still warns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const mk = "data a; input x; datalines;\n1\n2\n;\nrun;\n";
    // The ticket's exact case: `e` IS referenced (`if e then`) — the
    // STATEMENT path (`drop e;`) already stayed silent by validating against
    // the PDV (exec.assertReferenced); the OPTION path validated against the
    // FINALIZED schema, which the executor had already stripped of the end=
    // temp. Now both spellings reach the same PDV answer (D-009b's
    // corollary) — pinned for all THREE lists the message names, plus the
    // in= temp and the statement form so they cannot drift apart again.
    {
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, mk ++
            "data b(drop=e); set a end=e; if e then put \"LAST\"; run;\n" ++
            "data b2(keep=x e); set a end=e; run;\n" ++
            "data b3(rename=(e=last)); set a end=e; run;\n" ++
            "data b4(drop=f); set a(in=f) end=e; if f then put \"F\"; run;\n" ++
            "data b5; set a end=e; drop e; if e then put \"LAST5\"; run;\n", null);
        try std.testing.expect(!diagHas(&diags, "has never been referenced"));
        try std.testing.expect(std.mem.indexOf(u8, out.items, "LAST") != null); // e really drove the step
        try std.testing.expect(!diags.hasStepErrors());
    }
    // A genuinely never-referenced name must STILL warn — the warning exists
    // to catch a typo'd DROP/KEEP/RENAME name; silencing it is worse than
    // the bug. All three option lists, WARNING (DKROCOND default), step runs.
    {
        var diags = sas.diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        try interpret(a, &out, &diags, mk ++
            "data c(drop=typo); set a end=e; run;\n" ++
            "data c2(keep=x typo); set a; run;\n" ++
            "data c3(rename=(typo=t2)); set a; run;\n", null);
        try std.testing.expect(diagHas(&diags, "The variable TYPO in the DROP, KEEP, or RENAME list has never been referenced"));
        try std.testing.expect(!diags.hasStepErrors());
    }
}
