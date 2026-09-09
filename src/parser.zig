//! Statement parser — tokens → `ast.Program` (a DATA-step statement list).
//!
//! Wraps the A1 expression parser (`parser_expr.Parser`): one shared cursor
//! walks the whole token stream, so a statement keyword and the expressions
//! inside it advance the same position. Statement keywords (IF/DO/OUTPUT/…) are
//! plain `.name` tokens matched case-insensitively — SAS doesn't reserve them,
//! and this parser follows the DATA-step convention that the leading word at a
//! statement boundary is the keyword; anything else is an assignment target.
//!
//! Covers the board's A2 list: assign, if/then/else (+ subsetting `if c;`),
//! do (simple / iterative / while / until … end), output, drop, keep, retain,
//! set, datalines, input, put. Arena-allocated; errors go through Diagnostics.
//!
//! ponytail: `data …;`/`proc` framing is out of scope (A2 parses one step's
//! statements); a bare trailing `run;` is tolerated as a no-op boundary so C3
//! can feed a whole `.sas` body. Add a DataStep node when named output / PROCs
//! land.

const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const lex = @import("lexer.zig");
const pe = @import("parser_expr.zig");
const sql = @import("sql.zig"); // reuse desugarPredicates so the WHERE stmt matches where= (GAP-wherestmtops)
const format = @import("format.zig"); // constant-fold a numeric-literal PUT item (GAP-putnumliteral)
const pdv = @import("pdv.zig"); // max_char_len — the declared-length cap (BUG-lengthcapnostore)
const Value = @import("value.zig").Value;

const Error = diag.Error;
const Token = lex.Token;

/// BUG-putptroom: ceiling for PUT pointer controls (@n / +n / #n). SAS caps a
/// line at LS=/LRECL (max 32767); beyond it we fail loud instead of padding or
/// newline-emitting gigabytes (effective hang / OOM). ponytail: hard ceiling,
/// not the live LINESIZE option — wire io.global_linesize in if exact LS
/// truncation is ever needed.
const max_put_ptr: usize = 32767;

const CharLen = struct { name: []const u8, len: usize };

/// A global-statement keyword: TITLE / FOOTNOTE (optionally numbered, `title2`),
/// OPTIONS, FILENAME, ODS, LIBNAME. Used by main.segments' OPEN-CODE arm (a
/// statement starting with one of these between steps is its own global
/// segment). Mid-step the skip predicate is the narrower isMidStepSkippable
/// (D-014a) — every member here is handled there: hoisted or pre-pass-bound.
pub fn isGlobalKw(text: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(text, "options") or std.ascii.eqlIgnoreCase(text, "filename") or std.ascii.eqlIgnoreCase(text, "ods") or std.ascii.eqlIgnoreCase(text, "libname")) return true;
    const base: []const u8 = if (startsWithI(text, "title")) "title" else if (startsWithI(text, "footnote")) "footnote" else return false;
    const rest = text[base.len..];
    if (rest.len > 2) return false; // title / title1 / title10
    for (rest) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

// ── D-014a layering (GAP-globalpredicatemismatch) ────────────────────────────
// ONE home for every global-statement predicate, with real containment:
//   isHoistedGlobalKw  ⊂  isGlobalKw   — mid-step: HOISTED by main.segments
//       into its own global segment before the step and EXECUTED, so skipping
//       its leftover tokens inside the step is honest.
//   isInertGlobalKw    ∩  isGlobalKw = {} — batch-UNOBSERVABLE wherever it
//       appears (no SAS log, no graphics, one session), so accepting it
//       silently can never change data or listings.
// A PROC statement loop with a D-002 fail-loud skips exactly
//   isMidStepSkippable(t) == isHoistedGlobalKw(t) or isInertGlobalKw(t) or LIBNAME
// — what the top level actually HANDLES mid-step. LIBNAME is the one global
// with a whole-program PRE-PASS: main.parseLibnames binds every libref and
// preloads its datasets before step 1 runs, mid-step statements included — so
// by the time a loop skips the leftover tokens the statement HAS executed
// (BUG-libnamemidstepboth: a mid-PROC libname both ran via the pre-pass AND
// errored in the loop). ODS/FILENAME are hoisted (below) since
// BUG-filenamemidstep: skipping them un-executed was a silent no-op — a
// mid-DATA-step `filename f 'new';` re-bound nothing, so `file f;` kept
// writing to the OLD path at exit 0 (the exact sin D-014a was amended for).
// Every isGlobalKw member is now handled mid-step: hoisted ∪ pre-pass — the
// skip predicate and the handle predicate agree everywhere (D-014a closed).

/// The mid-step globals main.segments hoists OUT of a DATA/PROC step into
/// their own global segment (executed BEFORE the step): TITLE[n]/FOOTNOTE[n]/
/// OPTIONS (render/exec state the step reads) and FILENAME/ODS
/// (BUG-filenamemidstep). SAS runs global statements the moment they are
/// encountered — i.e. during step COMPILATION, before the step executes — so
/// binding a fileref / applying an ODS statement before the whole step runs
/// is exactly the observable SAS order for FILE/INFILE (execution-time
/// consumers). ODS destinations stay accepted no-ops and ODS OUTPUT/SELECT/
/// EXCLUDE/TRACE stay loud — now in handleGlobal, mid-step included, instead
/// of a mid-DATA silent swallow. NOT libname/x mid-step: libname has the
/// pre-pass, x is a DATA-step statement (parseStmt). PROC SQL is excluded
/// from the hoist scan (self-parses, GAP-titleinsql).
pub fn isHoistedGlobalKw(text: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(text, "options") or std.ascii.eqlIgnoreCase(text, "filename") or std.ascii.eqlIgnoreCase(text, "ods")) return true;
    const base: []const u8 = if (startsWithI(text, "title")) "title" else if (startsWithI(text, "footnote")) "footnote" else return false;
    const rest = text[base.len..];
    if (rest.len > 2) return false; // title / title1 / title10
    for (rest) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// Real SAS global statements a batch interpreter cannot observe, so they are
/// accepted silently WHEREVER they appear (open code: main.segments skips
/// them; mid-step: the PROC loops' isMidStepSkippable arm). Doc per member
/// (BUG-inertglobalstmts): RUN/QUIT step boundaries; DM windowing; GOPTIONS
/// graphics; SASFILE memory caching (performance only); CATNAME catalogs;
/// PAGE/SKIP Language Reference: Concepts p.209 (pure SAS-log pagination); RESETLINE/SYSECHO same
/// log family (SAS Global Statements: Reference); CHECKPOINT EXECUTE_ALWAYS
/// Language Reference: Concepts p.181 (no-op unless checkpoint mode is on; no STEPCHKPT here); LOCK
/// single-session always grants; AXIS/LEGEND/PATTERN/SYMBOL SAS/GRAPH, bare
/// or numbered (SYMBOL255 max). NOT here: MISSING (Language Reference: Concepts p.106 — changes
/// INPUT decoding → result-changing → loud) and ENDSAS (Language Reference: Concepts p.10/p.487 —
/// implemented as normal session termination, BUG-endsasexit).
/// CAVEAT (D-022, BUG-xstmtsilentnoop): "cannot observe" is FALSE for DM's
/// FILE/OUT log-redirection form, and for X (not in this set — parseStmtRaw
/// swallows it). Those two keep their inertness but emit a NOTE, so they are
/// not a silent no-op; see noteUnexecuted below. Membership here is unchanged.
pub fn isInertGlobalKw(text: []const u8) bool {
    const list = [_][]const u8{ "run", "quit", "dm", "goptions", "sasfile", "catname", "page", "skip", "resetline", "sysecho", "checkpoint", "lock" };
    for (list) |o| if (std.ascii.eqlIgnoreCase(text, o)) return true;
    const graph = [_][]const u8{ "axis", "legend", "pattern", "symbol" };
    outer: for (graph) |g| {
        if (!startsWithI(text, g)) continue;
        const rest = text[g.len..];
        if (rest.len > 3) continue; // symbol255 max
        for (rest) |c| if (!std.ascii.isDigit(c)) continue :outer;
        return true;
    }
    return false;
}

/// BUG-xstmtsilentnoop (GH#83 part 1) — D-022's emitter. `isInertGlobalKw`'s own
/// doc-comment justifies the set as "Real SAS global statements a batch
/// interpreter CANNOT OBSERVE". That claim is true for RUN/QUIT, GOPTIONS,
/// SASFILE, PAGE/SKIP and DM's windowing commands, and it is FALSE for exactly
/// two things, which are what this notes:
///   X                  — runs an OS command. `data _null_; x "mkdir /tmp/d"; run;`
///                        produced ZERO output at rc 0 and no directory: the
///                        side effect is on the FILESYSTEM, outside the session.
///   DM … FILE/OUT …    — redirects the LOG or OUTPUT window to a FILE. A
///                        downstream log check then reads a file nobody wrote.
/// Both were a silent rc-0 no-op, which D-002 forbids ("clinical: silent success
/// is the dangerous failure"). This is the D-014a shape exactly: satisfying the
/// letter of a rule traded a loud failure for a SILENT one, "a worse failure
/// class than the over-strict error D-014 was written to fix".
///
/// A NOTE, and deliberately NOT an ERROR, on both halves:
///   - X NOT EXECUTING IS SETTLED and stays (jira `x_stmt` by design;
///     `docs/sas9.4.ebnf` x_stmt deliberately carries no `(* opensas *)`). The
///     defect was the silence, not the inertness — so the fix is VISIBILITY.
///   - an ERROR would break every program that legitimately carries an X
///     statement, and because a step ERROR triggers syntax-check mode
///     (BUG-errhalt) it would then skip EVERY LATER STEP. That is the precise
///     failure D-014 was written after. A NOTE satisfies D-002 without touching
///     the exit code.
/// Everything else DM does (clear, editor, windowing) has no observable effect
/// in batch and STAYS SILENT — widening this to all of DM would put a NOTE on
/// the `dm 'log;clear'` autoexec idiom for nothing.
///
/// ponytail: this covers the two PARSER sites (parseProgram's atGlobalStmt
/// swallow and parseStmtRaw's x/dm arm); the OPEN-CODE sites live in main.zig
/// (`isXStmt` → handleGlobal at :1142, isInertGlobalKw at :1148) and call the
/// SAME emitter — exported for exactly that (GH#83 part 2,
/// BUG-xstmtopencodesplit), never pre-exported as dead code.
pub fn noteUnexecuted(diags: *diag.Diagnostics, toks: []const Token) error{OutOfMemory}!void {
    if (toks.len == 0 or toks[0].tag != .name) return;
    const kw = toks[0];
    if (std.ascii.eqlIgnoreCase(kw.text, "x"))
        return diags.note(kw.line, "X statement not executed: opensas does not run OS commands, so anything the command would have created does not exist", .{});
    if (std.ascii.eqlIgnoreCase(kw.text, "dm") and dmRedirectsToFile(toks[1..]))
        return diags.note(kw.line, "DM statement not executed: the FILE/OUT command did not run, so no log or output file was written", .{});
}

/// True when a DM command list carries the FILE or OUT command word. The list is
/// free text and reaches us in either shape — `dm log "file '&f' replace;"` puts
/// it inside a STRING token, `dm log file f;` in bare name tokens — so scan every
/// token's TEXT. WHOLE WORDS ONLY, and that is the load-bearing part: the
/// `dm 'log;clear;output;clear'` idiom (pinned by open_code_stmt_allowlist)
/// contains "out" inside "output", which is the OUTPUT WINDOW — pure windowing,
/// unobservable in batch, and it must stay silent.
fn dmRedirectsToFile(toks: []const Token) bool {
    for (toks) |t| {
        var it = std.mem.tokenizeAny(u8, t.text, " \t\r\n;:,()=.'\"");
        while (it.next()) |w|
            if (std.ascii.eqlIgnoreCase(w, "file") or std.ascii.eqlIgnoreCase(w, "out")) return true;
    }
    return false;
}

/// THE mid-step skip predicate (D-014a: skip == what the top level handles
/// mid-step — hoisted ∪ inert ∪ LIBNAME-via-pre-pass). See the layering note.
pub fn isMidStepSkippable(text: []const u8) bool {
    return isHoistedGlobalKw(text) or isInertGlobalKw(text) or std.ascii.eqlIgnoreCase(text, "libname");
}

fn startsWithI(text: []const u8, prefix: []const u8) bool {
    return text.len >= prefix.len and std.ascii.eqlIgnoreCase(text[0..prefix.len], prefix);
}

/// GAP guard (D-009): the syntax is valid SAS 9.4 opensas doesn't implement —
/// an opensas gap, exit 2 ("file an opensas issue"), not rc 1 ("fix your
/// SAS"). Flag the gap, then fail with the usual loud ERROR (prx.zig
/// loudUnsup's shape). ONLY for guards matching a SPECIFIC valid construct
/// (a named modifier/keyword) — a catch-all that also swallows typos stays a
/// plain user-error `fail` (see audit-exitcodecontract.md §5).
fn failGap(diags: *diag.Diagnostics, line: usize, comptime fmt: []const u8, args: anytype) Error {
    diag.markGap();
    return diags.fail(error.ParseError, line, fmt, args);
}

pub const Parser = struct {
    p: pe.Parser, // the expression parser IS the shared cursor
    char_lens: std.ArrayList(CharLen) = .empty, // `length v $ n;` → truncate assigns to v
    sum_vars: std.ArrayList([]const u8) = .empty, // `var + expr;` accumulators → auto-retain 0
    // Vars carrying an EXPLICIT init (array element inits, RETAIN inits): the
    // init IS the value — the sum statement's auto retain-0 must not overwrite
    // it (QA tick377 F2: the retain-inits application moved later, exposing the
    // clobber). Recorded at array/retain parse time; registerSumVar skips these.
    // If the sum statement precedes the retain/array the skip misses and the
    // retain-0 queues — harmless: statement order still lets the explicit init
    // apply after it.
    explicit_init_vars: std.ArrayList([]const u8) = .empty,
    pending: std.ArrayList(ast.Stmt) = .empty, // statements to inject right after the current one
    has_set: bool = false, // any `set …;` seen → drop the `_setobs_` helper var
    has_doover: bool = false, // any `do over …;` expanded → drop the implicit `_i_` index
    hashattr_n: usize = 0, // hoisted hash-attribute do-bound temps (`__hashattr_N`, GAP-hashnumitems)

    pub fn init(arena: std.mem.Allocator, toks: []const Token, diags: *diag.Diagnostics) Parser {
        return .{ .p = pe.Parser.init(arena, toks, diags) };
    }

    /// Parse every statement up to `.eof`. A lone `run;` is swallowed as a step
    /// boundary (produces no node).
    pub fn parseProgram(self: *Parser) Error!ast.Program {
        // Opt the shared expression parser into hash-call hoisting
        // (GAP-hashinexpr): temps mint from the same `__hashattr_N` counter the
        // do-bound hoists use, so one `drop __hashattr:` covers both.
        self.p.hashattr_n = &self.hashattr_n;
        // Fold `first.var` / `last.var` (which lex as name·dot·name) into a
        // single `.name` token so the expression parser reads them as one
        // BY-group automatic variable — keeps this out of the lexer/expr parser.
        self.p.toks = try coalesceFirstLast(self.p.arena, self.p.toks);
        // Expand `of a{*}` (all-elements list in a function call) into
        // `a{1}, a{2}, …, a{n}` so the expression parser sees ordinary refs.
        self.p.toks = try expandArrayStars(self.p.arena, self.p.toks);
        // Expand the general `of` operator (`sum(of x1-x3)`, `mean(of a b c)`)
        // into a comma-separated argument list.
        self.p.toks = try expandOf(self.p.arena, self.p.toks, self.p.diags);
        // Rewrite `vlabel(x)` → `vlabelx("x")` (and vname/vformat/vvalue) so the
        // variable's NAME reaches the function (the evaluator passes only its value).
        self.p.toks = try rewriteVMeta(self.p.arena, self.p.toks);
        // Desugar the numbered array-bound aliases `dim2(a)` → `dim(a, 2)`
        // (GAP-arraybounds-batch) — the bound-folding machinery knows only the
        // two-arg form.
        self.p.toks = try rewriteBoundAliases(self.p.arena, self.p.toks);
        // Rewrite `do over arr; … end;` into `do _i_=lo to hi; … end;` with the bare
        // array name replaced by `arr{_i_}` in the body.
        self.p.toks = try expandDoOver(self.p.arena, self.p.diags, self.p.toks, &self.has_doover);
        var stmts: std.ArrayList(ast.Stmt) = .empty;
        while (!self.p.check(.eof)) {
            if (self.atKw("run")) {
                _ = self.p.advance();
                _ = try self.p.expect(.semicolon, "';' after run");
                continue;
            }
            // A global statement (TITLE/FOOTNOTE/OPTIONS/FILENAME/ODS) is executed
            // immediately at the top level (main.zig); if one lands inside a step's
            // token range, swallow it here rather than misparsing it as DATA-step.
            if (self.atGlobalStmt()) {
                const from = self.p.pos;
                while (!self.p.check(.semicolon) and !self.p.check(.eof)) _ = self.p.advance();
                // D-022: the swallow is silent for everything a batch run cannot
                // observe, but DM's log-redirection form IS observable.
                try noteUnexecuted(self.p.diags, self.p.toks[from..self.p.pos]);
                _ = self.p.eat(.semicolon);
                continue;
            }
            try stmts.append(self.p.arena, try self.parseStmt());
            // Inject any statements a desugar queued (e.g. `nobs=v` → `v = _setobs_`)
            // right after the statement that produced them.
            for (self.pending.items) |ps| try stmts.append(self.p.arena, ps);
            self.pending.clearRetainingCapacity();
        }
        // A step that reads rows (set/merge) gets a `_setobs_` helper from
        // io.loadRow; keep it out of the output dataset.
        if (self.has_set) {
            const names = try self.p.arena.alloc([]const u8, 1);
            names[0] = "_setobs_";
            try stmts.insert(self.p.arena, 0, .{ .drop = names });
        }
        // Hoisted hash-attribute do-bound temps (`__hashattr_1`, …) are parser
        // machinery — keep them out of the output dataset (GAP-hashnumitems).
        // One prefix wildcard covers every temp the hoists minted.
        if (self.hashattr_n > 0) {
            const names = try self.p.arena.alloc([]const u8, 1);
            names[0] = "__hashattr:";
            try stmts.insert(self.p.arena, 0, .{ .drop = names });
        }
        // DO OVER desugars to `do _i_=lo to hi;` — SAS's implicit-array index `_I_`
        // is automatic and never emitted, so drop it from the output (BUG-dooverindex).
        if (self.has_doover) {
            const names = try self.p.arena.alloc([]const u8, 1);
            names[0] = "_i_";
            try stmts.insert(self.p.arena, 0, .{ .drop = names });
        }
        return stmts.toOwnedSlice(self.p.arena);
    }

    /// Statement choke point: drain hash calls hoisted out of this statement's
    /// expressions (GAP-hashinexpr, parser_expr.parseHashExpr) into `hash_op`
    /// statements that run first, wrapping the group in a bare DO. The minted
    /// `__hashattr_N` temp stands in for the call's return code inside the
    /// statement. Because every statement routes here (top level, DO bodies,
    /// IF/SELECT branches), the hoist lands immediately before the statement
    /// whose expression needed it, at the right nesting level.
    pub fn parseStmt(self: *Parser) Error!ast.Stmt {
        // Nesting guard AT the choke point: every recursive statement path
        // (DO bodies, IF/ELSE branches, SELECT whens) routes through here, so
        // one check covers them all — deep machine-generated nesting fails
        // loud instead of overflowing the native stack
        // (BUG-stmtnest-deepguard; the old parseDo-only guard left parseIf's
        // else-if recursion unguarded). Shares the counter/ceiling of the
        // expression guard (BUG-parser-deepnest); build.zig sizes the stack
        // so the ceiling trips before the guard pages do, Debug included.
        if (self.p.depth >= pe.Parser.max_depth)
            return self.p.diags.fail(error.ParseError, self.p.peek().line, "statement nesting too deep (over {d} levels)", .{pe.Parser.max_depth});
        self.p.depth += 1;
        defer self.p.depth -= 1;
        const mark = self.p.hash_hoists.items.len;
        const stmt = try self.parseStmtRaw();
        const extra = self.p.hash_hoists.items[mark..];
        if (extra.len == 0) return stmt;
        var body: std.ArrayList(ast.Stmt) = .empty;
        try body.ensureUnusedCapacity(self.p.arena, extra.len + 1);
        for (extra) |hc| body.appendAssumeCapacity(.{ .hash_op = hc });
        body.appendAssumeCapacity(stmt);
        self.p.hash_hoists.shrinkRetainingCapacity(mark);
        return .{ .do_ = .{ .header = .simple, .body = try body.toOwnedSlice(self.p.arena) } };
    }

    fn parseStmtRaw(self: *Parser) Error!ast.Stmt {
        const t = self.p.peek();
        // A lone `;` (or `;;`) in statement position is the SAS null statement — a
        // no-op, not an error. Lets a program degrade gracefully when a macro that
        // would have emitted a statement expands to nothing (PARSE-nullstmt).
        if (t.tag == .semicolon) {
            _ = self.p.advance();
            return .null_stmt;
        }
        if (t.tag != .name)
            return self.p.diags.fail(error.ParseError, t.line, "expected a statement", .{});

        // `name:` at a statement boundary is a label (a GOTO/LINK target); the
        // labeled statement follows as the next statement.
        if (self.tokAt(1).tag == .colon) {
            const lbl = self.p.advance().text;
            _ = self.p.advance(); // ':'
            return .{ .label = lbl };
        }

        // A statement-position `IDENT =` is an assignment, even when IDENT collides
        // with a statement keyword — `label = left(x);`, `format = …;`, `end = …;`
        // are ordinary variables in codelist/format-building steps. Route to the
        // assignment parser before the keyword dispatch so `label`/`format`/… aren't
        // misread as their statements (PARSE-starcomment).
        if (self.tokAt(1).tag == .eq) return self.parseAssign();

        // `X <command>;` / `DM <command>;` — an OS command / display-manager command
        // (SAS global stmts that may also sit inside a step, e.g. `X mkdir "&dir";` in
        // a `data _null_`, or `dm 'log;clear';` at the top of an Autoexec). Both keywords
        // are common variable names, so only when a command word/string follows (never
        // `x=`/`dm=`/`x+`/`x{i}`/`x.method`, all handled elsewhere). opensas: parsed and
        // NOT executed, but no longer SILENT about it — see noteUnexecuted (D-022).
        if ((self.atKw("x") or self.atKw("dm")) and (self.tokAt(1).tag == .name or self.tokAt(1).tag == .string)) {
            const from = self.p.pos;
            while (!self.p.check(.semicolon) and !self.p.check(.eof)) _ = self.p.advance();
            try noteUnexecuted(self.p.diags, self.p.toks[from..self.p.pos]);
            _ = try self.p.expect(.semicolon, "';' after command statement");
            return .null_stmt;
        }

        if (self.atKw("if")) return self.parseIf();
        if (self.atKw("do")) return self.parseDo();
        if (self.atKw("output")) return .{ .output = try self.parseNameList("output", false) };
        if (self.atKw("drop")) return .{ .drop = try self.parseNameList("drop", true) };
        if (self.atKw("keep")) return .{ .keep = try self.parseNameList("keep", true) };
        if (self.atKw("set")) return .{ .set = try self.parseDatasetRefs("set") };
        if (self.atKw("merge")) return .{ .merge = try self.parseDatasetRefs("merge") };
        if (self.atKw("update")) return .{ .update = try self.parseDatasetRefs("update") };
        if (self.atKw("modify")) return .{ .modify = try self.parseDatasetRefs("modify") };
        if (self.atKw("array")) return self.parseArray();
        if (self.atKw("where")) return self.parseWhere();
        if (self.atKw("select")) return self.parseSelect();
        if (self.atKw("declare") or self.atKw("dcl")) return self.parseDeclare();
        // `h.method(...);` (statement form) — an object method call.
        if (self.hashMethodAhead()) {
            const hop = try self.parseHashOp(null);
            _ = try self.p.expect(.semicolon, "';' after hash method call");
            return .{ .hash_op = hop };
        }
        if (self.atKw("by")) return .{ .by = try self.parseBy() };
        if (self.atKw("length")) return self.parseLength();
        // `label v='text' v2='text2' …;` — variable display labels. Carried to exec
        // on the `.format` node with a NUL-prefixed fmt sentinel (see rideAsLabel).
        if (self.atKw("label")) {
            _ = self.p.advance(); // label
            var items: std.ArrayList(ast.FormatItem) = .empty;
            while (self.p.check(.name)) {
                const nm = self.p.advance();
                _ = self.p.eat(.eq); // '='
                const lbl = if (self.p.check(.string)) self.p.advance().text else "";
                try items.append(self.p.arena, .{ .name = nm.text, .fmt = try rideAsLabel(self.p.arena, self.p.diags, nm.text, lbl, nm.line) });
            }
            _ = try self.p.expect(.semicolon, "';' after label");
            return .{ .format = try items.toOwnedSlice(self.p.arena) };
        }
        if (self.atKw("rename")) return self.parseRename();
        if (self.atKw("retain")) return self.parseRetain();
        if (self.atKw("infile")) return self.parseInfile();
        if (self.atKw("file")) return self.parseFile();
        if (self.atKw("input")) return self.parseInput();
        // PUTLOG is PUT that always targets the SAS log; opensas PUT already writes
        // to the log, so PUTLOG reuses the identical parse/exec path. parsePut blindly
        // advances past its leading keyword, so `putlog` is consumed the same as `put`.
        if (self.atKw("put") or self.atKw("putlog")) return self.parsePut();
        if (self.atKw("format")) return .{ .format = try self.parseFormatList("format") };
        if (self.atKw("informat")) return .{ .informat = try self.parseFormatList("informat") };
        if (self.atKw("datalines") or self.atKw("cards") or self.atKw("lines") or
            self.atKw("datalines4") or self.atKw("cards4"))
            return self.parseDatalines();
        if (self.atKw("delete")) {
            _ = self.p.advance();
            _ = try self.p.expect(.semicolon, "';' after delete");
            return .delete;
        }
        if (self.atKw("stop")) {
            _ = self.p.advance();
            _ = try self.p.expect(.semicolon, "';' after stop");
            return .stop;
        }
        // REPLACE / REMOVE — MODIFY-step obs control (FEAT-datamodify-rest). Bare
        // form only: `replace`/`remove` are ordinary variable names too, so gate on
        // a bare `;` following (an `IDENT =` already routed to parseAssign above).
        // Encoded as a \x00-sentinel OUTPUT node — no new AST variant needed; exec
        // routes it to the MODIFY driver and fails loud outside a MODIFY step.
        if ((self.atKw("replace") or self.atKw("remove")) and self.tokAt(1).tag == .semicolon) {
            const kw = self.p.advance().text; // replace | remove
            _ = self.p.advance(); // ';'
            const one = try self.p.arena.alloc([]const u8, 1);
            one[0] = if (std.ascii.eqlIgnoreCase(kw, "replace")) "\x00replace" else "\x00remove";
            return .{ .output = one };
        }
        // Named form `REMOVE ds;` / `REPLACE ds;` — valid SAS in a multi-dataset
        // MODIFY step, but opensas implements the BARE form only (exec's MODIFY
        // driver routes no named target). Without this guard the dataset name
        // fell through to parseAssign → "expected '=' in assignment", a
        // diagnostic naming the WRONG construct (NOTE-removenamedds; the
        // GAP-liststmt precedent). Fail loud NAMING the statement (D-002).
        // `remove = 5;` stays an ordinary assignment — gate on a NAME following.
        if ((self.atKw("replace") or self.atKw("remove")) and self.tokAt(1).tag == .name)
            return failGap(self.p.diags, self.p.peek().line, "{s} with a named data set is not supported (only the bare {s}; MODIFY-step form)", .{ self.p.peek().text, self.p.peek().text });
        // MISSING — declares the characters raw numeric input reads as special
        // missing values (.A-.Z/._; Language Reference: Concepts printed p.519, a worked example shown
        // TWICE). VALID SAS 9.4 opensas doesn't implement → a NAMED gap, rc 2
        // (D-009/D-009b(i); BUG-missingstmtwrongclass). It used to fall through
        // to parseAssign → "expected '=' in assignment" — rc 1 blaming the
        // WRONG construct (the NOTE-removenamedds / GAP-liststmt precedent).
        // `missing = 5;` routes to parseAssign on the `IDENT =` check above, so
        // a `missing` reaching here IS the statement. Same message as main.zig's
        // open-code arm (D-009b corollary: the twin settles by consistency).
        if (self.atKw("missing"))
            return failGap(self.p.diags, self.p.peek().line, "the MISSING statement (special missing values) is not supported", .{});
        if (self.atKw("continue")) {
            _ = self.p.advance();
            _ = try self.p.expect(.semicolon, "';' after continue");
            return .continue_;
        }
        if (self.atKw("leave")) {
            _ = self.p.advance();
            _ = try self.p.expect(.semicolon, "';' after leave");
            return .leave;
        }
        if (self.atKw("return")) {
            _ = self.p.advance();
            _ = try self.p.expect(.semicolon, "';' after return");
            return .return_;
        }
        if (self.atKw("abort")) return self.parseAbort();
        if (self.atKw("attrib")) return self.parseAttrib();
        if (self.atKw("call")) return self.parseCall();
        if (self.atKw("goto") or self.atKw("go")) {
            _ = self.p.advance(); // goto / go
            if (self.atKw("to")) _ = self.p.advance(); // the `go to` two-word form
            const lbl = (try self.p.expect(.name, "a GOTO label")).text;
            _ = try self.p.expect(.semicolon, "';' after goto");
            return .{ .goto = lbl };
        }
        if (self.atKw("link")) {
            _ = self.p.advance();
            const lbl = (try self.p.expect(.name, "a LINK label")).text;
            _ = try self.p.expect(.semicolon, "';' after link");
            return .{ .link = lbl };
        }
        return self.parseAssign();
    }

    /// `abort [abend [n] | return [n] | n];` (BUG-abortreturncode, Language Reference: Concepts p.485-486).
    /// Plain `abort;` ends the DATA step with _ERROR_=1 (like STOP); ABEND /
    /// RETURN [n] / bare n terminate the WHOLE session with a process exit code.
    /// `abort return;` (no n) is LEGAL — the syntax makes n optional (Statements
    /// Ref printed p.16, marker "=== pdf 27 ===") and the doc's own z/OS example
    /// runs `if errcode=16 then abort return;` (printed p.19, marker "=== pdf 30
    /// ==="); RETURN without n "returns ... a condition code that indicates an
    /// error" (printed p.18, marker "=== pdf 29 ===") → default 1, the same
    /// default ABEND-no-n takes exec-side. Anything else (a stray word, a
    /// NON-number after RETURN) is a hard parse ERROR — a silently-misparsed
    /// ABORT is a clinical fail-fast that never fires.
    fn parseAbort(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // abort
        if (self.p.check(.semicolon)) {
            _ = self.p.advance();
            return .{ .abort = .plain };
        }
        if (self.atKw("abend")) {
            _ = self.p.advance();
            const n = try self.abortCode();
            _ = try self.p.expect(.semicolon, "';' after abort abend");
            return .{ .abort = .{ .abend = n } };
        }
        if (self.atKw("return")) {
            _ = self.p.advance();
            const n = try self.abortCode() orelse blk: {
                // No n: legal ONLY at `;` (default rc 1, see the doc comment).
                // A stray word here is the typo it always was — abortCode's
                // null cannot tell the two apart, the semicolon check does.
                if (!self.p.check(.semicolon))
                    return self.p.diags.fail(error.ParseError, self.p.peek().line, "ABORT RETURN requires a return code", .{});
                break :blk 1;
            };
            _ = try self.p.expect(.semicolon, "';' after abort return");
            return .{ .abort = .{ .n = n } };
        }
        const n = try self.abortCode() orelse
            return self.p.diags.fail(error.ParseError, self.p.peek().line, "unsupported ABORT argument (want ABEND [n] | RETURN n | n)", .{});
        _ = try self.p.expect(.semicolon, "';' after abort");
        return .{ .abort = .{ .n = n } };
    }

    /// The optional integer return code of an ABORT: null at `;`, a loud parse
    /// ERROR on a non-integer or out-of-range (0-255) value.
    fn abortCode(self: *Parser) Error!?u8 {
        if (!self.p.check(.number)) return null;
        const text = self.p.advance().text;
        return std.fmt.parseInt(u8, text, 10) catch
            return self.p.diags.fail(error.ParseError, self.p.peek().line, "ABORT return code must be an integer 0-255, got '{s}'", .{text});
    }

    /// `call ROUTINE(args);` — a CALL statement. Parse `ROUTINE(args)` as a call
    /// expression (name + args) and wrap it; the executor dispatches on the name.
    /// ponytail: only CALL MISSING is implemented (see exec.runCall); other
    /// routines parse but are a NOTE-and-ignore at run time.
    fn parseCall(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // call
        const e = try self.p.parseExpr(); // ROUTINE(args) → Expr.call
        _ = try self.p.expect(.semicolon, "';' after call");
        if (e.* != .call)
            return self.p.diags.fail(error.ParseError, self.p.peek().line, "CALL must name a routine", .{});
        return .{ .call_ = e.call };
    }

    /// `attrib v1 v2 length=[$]n [format=f] [informat=f] [label='…'] …;` — apply a
    /// `$`-length (truncates assignments, like LENGTH), a FORMAT (display format,
    /// like FORMAT) and an INFORMAT (read format, like INFORMAT — BUG-attribinformat:
    /// it rode home discarded, so `attrib d informat=date9.; input d;` read MISSING).
    /// The informat rides the `.format` node with a \x01 sentinel — the same tag
    /// scan() uses for a real INFORMAT statement, so attrs/patchInformats/INPUT all
    /// pick it up unchanged. Numeric `length=n` is applied too (GH#46).
    /// An EMPTY `format=`/`informat=` value is a user error here, not a silent
    /// drop — see attribValueMissing (BUG-attribemptyvaluenoop).
    fn parseAttrib(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // attrib
        var fmts: std.ArrayList(ast.FormatItem) = .empty;
        while (self.p.check(.name)) {
            var names: std.ArrayList([]const u8) = .empty;
            while (self.p.check(.name) and self.tokAt(1).tag != .eq)
                try names.append(self.p.arena, self.p.advance().text);
            if (names.items.len == 0) break; // safety: no group name → stop
            while (self.p.check(.name) and self.tokAt(1).tag == .eq) {
                const opt_tok = self.p.advance();
                const opt = opt_tok.text;
                _ = self.p.advance(); // '='
                if (eqi(opt, "length")) {
                    const is_char = self.p.eat(.dollar);
                    // `length=$11.` — the customary SAS trailing dot (and the
                    // macro-built `$40..` double dot) must not drop the width:
                    // it silently left EMPTY_* metadata columns at len 1 and
                    // no assignment ever truncated (GAP-charlength, gen2 CM).
                    const len = self.lengthNumber();
                    try self.checkDeclLen(is_char, len, names.items[0], opt_tok.line);
                    if (is_char) if (len) |l| {
                        for (names.items) |nm| try self.char_lens.append(self.p.arena, .{ .name = nm, .len = l });
                    };
                } else if (eqi(opt, "format")) {
                    const fmt = try self.tryFormatSpec() orelse return self.attribValueMissing(opt_tok, names.items[0]);
                    for (names.items) |nm| try fmts.append(self.p.arena, .{ .name = nm, .fmt = fmt });
                } else if (eqi(opt, "label")) {
                    if (self.p.check(.string)) {
                        const lbl = self.p.advance().text;
                        for (names.items) |nm| try fmts.append(self.p.arena, .{ .name = nm, .fmt = try rideAsLabel(self.p.arena, self.p.diags, nm, lbl, opt_tok.line) });
                    }
                } else if (eqi(opt, "informat")) {
                    // informat=spec — same \x01 sentinel the scan() .informat
                    // handler tags, riding the .format node like label= does (\x00).
                    const spec = try self.tryFormatSpec() orelse return self.attribValueMissing(opt_tok, names.items[0]);
                    for (names.items) |nm| try fmts.append(self.p.arena, .{ .name = nm, .fmt = try std.fmt.allocPrint(self.p.arena, "\x01{s}", .{spec}) });
                } else {
                    // unknown ATTRIB option — consume the value, ignore it.
                    if (self.p.check(.string)) _ = self.p.advance() else if ((try self.tryFormatSpec()) == null) _ = self.p.advance();
                }
            }
        }
        _ = try self.p.expect(.semicolon, "';' after attrib");
        if (fmts.items.len > 0) return .{ .format = try fmts.toOwnedSlice(self.p.arena) };
        return .{ .drop = &[_][]const u8{} }; // length-only → inert (effect in char_lens)
    }

    /// BUG-attribemptyvaluenoop — `attrib a format=;` / `attrib a informat=;` in a
    /// DATA STEP. tryFormatSpec returns null at `;` (and at a name with no trailing
    /// dot), and both arms used to fall off the end UNRECORDED: the value vanished,
    /// the OLD format stayed attached and the run exited 0 with zero diagnostics —
    /// the silent no-op D-002 forbids ("clinical: silent success is the dangerous
    /// failure"). This makes it LOUD.
    ///
    /// WHY LOUD AND NOT "CLEAR THE ATTRIBUTE" — the empty spelling is real SAS, but
    /// not HERE. Three doc facts, in order of weight:
    ///   1. Statements Ref printed p.36: "You can use ATTRIB in a PROC step, but the
    ///      rules are different." The only place SAS 9.4 documents `format=` with an
    ///      empty value is the PROC DATASETS MODIFY ATTRIB *option* (Procedures Guide
    ///      printed p.691 Example 1, `attrib _all_ format=;` — SAS's own sample code,
    ///      and what proc.zig's applyAttrib implements). p.36 rules that surface out
    ///      of the DATA step in one sentence, so importing it here would be inventing
    ///      syntax, not honouring a citation.
    ///   2. Statements Ref printed p.34 gives the DATA-step slots as `FORMAT=format`
    ///      and `INFORMAT=informat` — value REQUIRED. The volume brackets what is
    ///      optional (`LENGTH=<$>length` on the same page), so an unbracketed operand
    ///      is not an omission. `format=;` appears NOWHERE in the volume.
    ///   3. The DOCUMENTED DATA-step removal is a BARE FORMAT/INFORMAT statement —
    ///      printed p.112: "To disassociate a format from a variable, use the variable
    ///      in a FORMAT statement without specifying a format … In a DATA step, place
    ///      this FORMAT statement after the SET statement", worked at printed p.115
    ///      Example 3 (`format x;`). That route is implemented (parseFormatList's
    ///      pending-at-`;` arm) and stays untouched, so the user is not left without a
    ///      way to remove the attribute — the message names it.
    /// The D-015 shape decides the residual doubt: accepting an undocumented spelling
    /// and quietly dropping a display format is a SILENT SUPERSET — a typo or an
    /// empty macro variable would strip a date format and print 21929 instead of
    /// 15JAN2020, at rc 0. Loud costs one error message; silent costs a wrong number.
    ///
    /// rc 1, not rc 2 (D-009 / D-009b(ii)): by (1)+(2) this is not valid DATA-step
    /// SAS, so it is the USER's code that is wrong ("fix your SAS"), not an opensas
    /// gap ("file an opensas issue") — hence a plain `fail`, never `failGap`.
    ///
    /// ponytail: NOT absorbing the `"$."` clear sentinel (parser.zig's parseFormatList
    /// ponytail) — a real clear needs an exec-side null-format path and exec.zig is
    /// outside this task's ownership. Nothing here depends on it: the loud path never
    /// mints a sentinel. `label=` with a non-string value is the same silent-drop
    /// shape one arm above and is deliberately left for its own ticket.
    fn attribValueMissing(self: *Parser, opt_tok: Token, first_name: []const u8) Error {
        const opt = opt_tok.text;
        if (self.p.check(.semicolon) or self.p.check(.eof))
            return self.p.diags.fail(error.ParseError, opt_tok.line, "attrib {s}=: an empty {s} value is not valid in a DATA step (that spelling is PROC DATASETS only); to remove the attribute use a bare '{s} {s};' statement", .{ opt, opt, opt, first_name });
        return self.p.diags.fail(error.ParseError, opt_tok.line, "attrib {s}=: '{s}' is not a {s} specification (a {s} name needs its trailing '.', e.g. {s}.)", .{ opt, self.p.peek().text, opt, opt, self.p.peek().text });
    }

    /// `infile "path" [DLM=|DELIMITER= "x"] [DSD] [FIRSTOBS=n];` — external text
    /// input. DSD with no DLM defaults the delimiter to a comma.
    fn parseInfile(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // infile
        // INFILE naming the inline-data device (DATALINES/DATALINES4/CARDS/CARDS4)
        // reads the embedded datalines block — with options (DLM=/DSD/FIRSTOBS=) —
        // instead of an external file (ISS-infiledevice). Otherwise a quoted path.
        var inf = ast.Infile{ .path = undefined };
        if (self.atKw("datalines") or self.atKw("datalines4") or self.atKw("cards") or self.atKw("cards4")) {
            inf.path = self.p.advance().text;
            inf.inline_data = true;
        } else {
            inf.path = (try self.p.expect(.string, "an infile path")).text;
        }
        while (!self.p.check(.semicolon) and !self.p.check(.eof)) {
            if (self.atKw("dlm") or self.atKw("delimiter")) {
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                if (self.p.check(.string)) {
                    const d = self.p.advance().text;
                    // BUG-dlmmultichar: DLM= is a LIST of single-char delimiters —
                    // keep the whole string, not just the first byte. (The distinct
                    // "one multi-char delimiter" form DLMSTR= is unsupported and
                    // fails loud via the else branch below.)
                    if (d.len > 0) inf.dlm = d;
                }
            } else if (self.atKw("dsd")) {
                _ = self.p.advance();
                inf.dsd = true;
            } else if (self.atKw("firstobs")) {
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                if (self.p.check(.number)) inf.firstobs = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 1;
            } else if (self.atKw("lrecl")) {
                // ponytail: accept-and-ignore — we read full lines, so logical
                // record length has no runtime effect. Consume the value so it
                // doesn't hit the fail-loud else (ISS-infilelrecl).
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                if (self.p.check(.number)) _ = self.p.advance();
            } else if (self.atKw("flowover")) {
                _ = self.p.advance();
                inf.overflow = .flowover;
            } else if (self.atKw("missover")) {
                _ = self.p.advance();
                inf.overflow = .missover;
            } else if (self.atKw("truncover")) {
                _ = self.p.advance();
                inf.overflow = .truncover;
            } else if (self.atKw("stopover")) {
                _ = self.p.advance();
                inf.overflow = .stopover;
            } else if (self.atKw("end")) {
                // END=variable (FEAT-infileend) — temp flag, 1 on the last record.
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                inf.end_var = (try self.p.expect(.name, "a variable name after END=")).text;
            } else if (self.atKw("obs")) {
                // OBS=n (FEAT-infileobslinesize) — last record number read (1-based).
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                const n = try self.p.expect(.number, "a record count after OBS=");
                inf.obs = std.fmt.parseInt(usize, n.text, 10) catch
                    return self.p.diags.fail(error.ParseError, n.line, "INFILE OBS= expects an integer", .{});
            } else if (self.atKw("linesize") or self.atKw("ls")) {
                // LINESIZE=/LS=n (FEAT-infileobslinesize) — cap each record at n columns.
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                const n = try self.p.expect(.number, "a length after LINESIZE=");
                inf.linesize = std.fmt.parseInt(usize, n.text, 10) catch
                    return self.p.diags.fail(error.ParseError, n.line, "INFILE LINESIZE= expects an integer", .{});
            } else if (self.atKw("unbuffered") or self.atKw("unbuf")) {
                // GAP-infileoptrc (3b): UNBUFFERED (alias UNBUF) is a documented
                // INFILE option (Statements Ref printed p.138, marker
                // "=== pdf 149 ===") opensas has not implemented — an opensas
                // gap → rc 2 (D-009/D-009b(i)), split out of the rc-1 typo
                // catch-all below. Same loud ERROR text; only the rc moves.
                return failGap(self.p.diags, self.p.peek().line, "INFILE option {s} is not supported", .{self.p.peek().text});
            } else if (self.atKw("eof")) {
                // GAP-infileoptrc (3c): EOF=variable (printed p.130, marker
                // "=== pdf 141 ===") — the doc's own prescribed substitute
                // where END= is invalid (DATALINES / multi-record INPUT).
                // Same gap class, same split off the catch-all.
                return failGap(self.p.diags, self.p.peek().line, "INFILE option {s} is not supported", .{self.p.peek().text});
            } else if (self.atKw("eov")) {
                // GAP-infileeov: EOV=variable (printed p.130, marker
                // "=== pdf 141 ===") — set to 1 when the first record of the
                // next file in a concatenated series is read. Documented but
                // unimplemented → same gap class as EOF= above, same split
                // off the rc-1 typo catch-all. Same ERROR text; only rc moves.
                return failGap(self.p.diags, self.p.peek().line, "INFILE option {s} is not supported", .{self.p.peek().text});
            } else if (self.atKw("nopad")) {
                // NOPAD is the documented DEFAULT of the same PAD|NOPAD entry
                // (printed p.135) — accept-and-ignore is truthful here, not a
                // silent no-op: opensas never pads, so the option asks for
                // exactly what happens (D-018: the split must be right in both
                // directions; leaving the default at typo-rc would be the
                // mirror-image error).
                _ = self.p.advance();
            } else if (self.atKw("pad") or self.atKw("dlmstr")) {
                // GAP-ebnfholes-tick356: PAD (printed p.135, marker "=== pdf
                // 146 ===") and DLMSTR= (printed p.128, marker "=== pdf 139
                // ===", self-confirmed "DLMSTR= on page 128") are DOCUMENTED
                // INFILE options opensas has not implemented → gap rc 2
                // (D-009/D-009b(i)), split off the rc-1 typo catch-all below.
                // PAD deliberately stays loud rather than accept-and-ignore:
                // it pads short records to LRECL=, and LRECL= is a no-op here,
                // so there is nothing to pad TO (BUG-infilepadinert — loud
                // beats lying). Same ERROR text on both arms; only rc moves.
                return failGap(self.p.diags, self.p.peek().line, "INFILE option {s} is not supported", .{self.p.peek().text});
            } else {
                // House rule: an unrecognized INFILE option must FAIL LOUD, never a
                // silent no-op — a swallowed record-boundary option (e.g. MISSOVER)
                // silently corrupts data (BUG-infilemissover).
                // BUG-infilepadinert: PAD used to take this loud path too — it was
                // once parsed, stored, and never read, the lone silent hole in
                // this wall (D-002); it is now the NAMED failGap arm above (rc 2),
                // still loud, because it pads short records out to LRECL= and
                // LRECL= is a documented accept-and-ignore no-op
                // (ISS-infilelrecl), so there is nothing to pad TO until that
                // lands — loud beats lying. (ast.Infile.pad is now vestigial;
                // ast.zig is another dev's file.)
                const opt = self.p.peek();
                return self.p.diags.fail(error.ParseError, opt.line, "INFILE option {s} is not supported", .{opt.text});
            }
        }
        if (inf.dsd and inf.dlm == null) inf.dlm = ","; // DSD → comma by default
        _ = try self.p.expect(.semicolon, "';' after infile");
        return .{ .infile = inf };
    }

    /// `file "path" [DLM=|DELIMITER= "x"] [DSD];` — external text output for
    /// `put`. Mirrors parseInfile's option shape; an unknown option fails loud.
    fn parseFile(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // file
        // GAP-fileprint: unquoted PRINT/LOG fileref keywords (atKw matches a
        // .name token only, so a quoted "print" still parses as an external
        // path below) — accepted, PUT routes to the normal output.
        var f = if (self.atKw("print") or self.atKw("log"))
            ast.File{ .path = self.p.advance().text, .print_log = true }
        else
            ast.File{ .path = (try self.p.expect(.string, "a file path")).text };
        while (!self.p.check(.semicolon) and !self.p.check(.eof)) {
            if (self.atKw("dlm") or self.atKw("delimiter")) {
                _ = self.p.advance();
                _ = self.p.eat(.eq);
                if (self.p.check(.string)) {
                    const d = self.p.advance().text;
                    if (d.len > 0) f.dlm = d[0];
                }
            } else if (self.atKw("dsd")) {
                _ = self.p.advance();
                f.dsd = true;
            } else {
                // House rule: an unrecognized FILE option must FAIL LOUD, never a
                // silent no-op — a swallowed DLM=/DSD silently misformats the
                // output file (BUG-fileopts).
                const opt = self.p.peek();
                return self.p.diags.fail(error.ParseError, opt.line, "FILE option {s} is not supported", .{opt.text});
            }
        }
        if (f.dsd and f.dlm == null) f.dlm = ','; // DSD → comma by default
        _ = try self.p.expect(.semicolon, "';' after file");
        return .{ .file = f };
    }

    // ── individual statements ───────────────────────────────────────────────

    fn parseAssign(self: *Parser) Error!ast.Stmt {
        const target = self.p.advance().text; // known `.name`
        // SUBSTR pseudo-variable: `substr(var, pos <, len>) = value;` overwrites a
        // slice of `var` in place (BUG-substrlvalue).
        if (self.p.check(.lparen) and eqi(target, "substr")) {
            _ = self.p.advance(); // '('
            const v = (try self.p.expect(.name, "SUBSTR variable")).text;
            _ = try self.p.expect(.comma, "',' after the SUBSTR variable");
            const pos = try self.p.parseExpr();
            const len: ?*const ast.Expr = if (self.p.eat(.comma)) try self.p.parseExpr() else null;
            _ = try self.p.expect(.rparen, "')' after SUBSTR arguments");
            _ = try self.p.expect(.eq, "'=' in SUBSTR assignment");
            const value = try self.p.parseExpr();
            _ = try self.p.expect(.semicolon, "';'");
            return .{ .substr_assign = .{ .target = v, .pos = pos, .len = len, .value = value } };
        }
        // Sum statement `var + expr;` — an accumulator. Desugar to
        // `var = sum(var, expr)` (sum() treats a missing addend as 0) and record
        // `var` so parseProgram prepends `retain var 0;`.
        if (self.p.check(.plus)) {
            _ = self.p.advance(); // '+'
            const addend = try self.p.parseExpr();
            _ = try self.p.expect(.semicolon, "';'");
            try self.registerSumVar(target);
            const args = try self.p.arena.alloc(ast.Expr, 2);
            args[0] = .{ .variable = target };
            args[1] = addend.*;
            const call = try self.p.arena.create(ast.Expr);
            call.* = .{ .call = .{ .name = "sum", .args = args } };
            return .{ .assign = .{ .target = target, .value = call } };
        }
        // Subscripted lvalue: `a{i} = expr;` / `a{i,j} = expr;` (GAP-multidimarray).
        // `a(i) = expr;` too — SAS allows ()/{}/[] interchangeably; gate the paren
        // form on a declared array so a genuine call-looking LHS still errors
        // (GAP-arrayparenwrite; parseArraySubscript is paren-aware).
        if (self.p.check(.lbrace) or (self.p.check(.lparen) and self.p.lookupArray(target) != null)) {
            const name_tok: Token = .{ .tag = .name, .text = target, .line = self.p.peek().line };
            const r = try self.p.parseArraySubscript(name_tok);
            // Array-element SUM statement `a[i] + expr;` — the subscripted analog
            // of `var + expr;` (GAP-arraysum): retain the element across
            // iterations and add expr each execution. Desugar to
            // `a[i] = sum(a[i], expr)`; since the subscript is dynamic, register
            // EVERY element for `retain … 0` (registerSumVar skips elements with
            // an explicit array init — that init is the value, the auto-zero
            // must not clobber it). ponytail: special-list arrays (`array v{*} _numeric_`) have no static
            // elements, so nothing is retained — add only if a real program hits it.
            if (self.p.check(.plus)) {
                _ = self.p.advance(); // '+'
                const addend = try self.p.parseExpr();
                _ = try self.p.expect(.semicolon, "';'");
                for (r.def.elements) |e| try self.registerSumVar(e);
                const aref = try self.p.arena.create(ast.Expr);
                aref.* = .{ .array_ref = .{ .name = target, .elements = r.def.elements, .index = r.index, .special = r.def.special, .line = name_tok.line } };
                const args = try self.p.arena.alloc(ast.Expr, 2);
                args[0] = aref.*;
                args[1] = addend.*;
                const call = try self.p.arena.create(ast.Expr);
                call.* = .{ .call = .{ .name = "sum", .args = args } };
                return .{ .array_assign = .{
                    .array = .{ .name = target, .elements = r.def.elements, .index = r.index, .special = r.def.special, .line = name_tok.line },
                    .value = call,
                } };
            }
            _ = try self.p.expect(.eq, "'=' in assignment");
            const value = try self.p.parseExpr();
            _ = try self.p.expect(.semicolon, "';'");
            return .{ .array_assign = .{
                .array = .{ .name = target, .elements = r.def.elements, .index = r.index, .special = r.def.special, .line = name_tok.line },
                .value = value,
            } };
        }
        _ = try self.p.expect(.eq, "'=' in assignment");
        // `rc = h.method(...);` — the RHS is a hash method call, not an expression
        // (the evaluator can't see hash ops), so capture it as a statement with a
        // return-code target. Only when the call IS the whole RHS (followed by
        // `;`) — `x = h.find() + 1;` is the expression form (GAP-hashinexpr) and
        // falls through to parseExpr, which hoists the call.
        if (self.hashStmtAhead()) {
            const hop = try self.parseHashOp(target);
            _ = try self.p.expect(.semicolon, "';'");
            return .{ .hash_op = hop };
        }
        // `h = _new_ hash(...);` / `hi = _new_ hiter('h');` — the RHS
        // constructor forms (GAP-hashnew; GAP-hashnewhiter — Language Reference: Concepts p.624's
        // verbatim two-step iterator instantiation, stated there as equivalent
        // to `declare hiter hi('h')`). Both desugar to the SAME hash_decl the
        // declare forms produce; exec treats them alike (one positional string
        // arg is the iter_of capture either way). Other `_new_` targets stay loud.
        if (self.atKw("_new_")) {
            _ = self.p.advance(); // _new_
            if (!self.eatKw("hash") and !self.eatKw("hiter"))
                return self.p.diags.fail(error.ParseError, self.p.peek().line, "only '_new_ hash()'/'_new_ hiter()' is supported", .{});
            var args: []const ast.HashArg = &.{};
            if (self.p.eat(.lparen)) args = try self.p.parseHashArgs();
            _ = try self.p.expect(.semicolon, "';' after _new_ hash()/hiter()");
            return .{ .hash_decl = .{ .name = target, .args = args } };
        }
        var value = try self.p.parseExpr();
        _ = try self.p.expect(.semicolon, "';'");
        // A `length v $ n;` variable truncates every char assignment to n bytes.
        // Desugar to `__assignc(rhs, n)` (functions.zig) — char truncates like
        // substr(rhs,1,n) did, but a NUMERIC rhs renders BESTn. right-justified
        // (Language Reference: Concepts p.124: assignment conversion uses the LHS length; substr's
        // BEST12 field blanked n<12) (BUG-numcharwidth).
        if (self.charLenOf(target)) |n| value = try self.truncate(value, n);
        return .{ .assign = .{ .target = target, .value = value } };
    }

    /// `rename old=new old2=new2 …;` — the statement form of the `rename=(…)`
    /// dataset option: rename variables in the step's output. Exec collects the
    /// pairs and applies them to the output dataset at finalize, reusing the
    /// dataset-option rename path (G-falsemarkers2).
    fn parseRename(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // rename
        var pairs: std.ArrayList(ast.RenamePair) = .empty;
        while (self.p.check(.name)) {
            const old = self.p.advance().text;
            _ = try self.p.expect(.eq, "'=' in rename");
            const new = (try self.p.expect(.name, "a new variable name")).text;
            try pairs.append(self.p.arena, .{ .old = old, .new = new });
        }
        _ = try self.p.expect(.semicolon, "';' after rename");
        return .{ .rename = try pairs.toOwnedSlice(self.p.arena) };
    }

    /// `length v1 $ n1 v2 n2 …;` — records char lengths (with `$`) so assignments
    /// truncate; numeric lengths (GH#46) are carried via main.lengthVars into the
    /// PDV var's numlen, truncating each store to the high N of 8 IEEE bytes (a
    /// deliberate precision loss, not a no-op). Declarative → an inert node here.
    /// ponytail: must precede the assignments it governs (we parse top-down), and
    /// truncation only — SAS also blank-pads a short value to n (put trims it).
    fn parseLength(self: *Parser) Error!ast.Stmt {
        const kw = self.p.advance(); // length
        // `length v1 v2 … $ n  w1 … m;` — each group is a *list* of variables
        // sharing one `$`/length spec. The `$` and length come after the whole
        // list, so collect every name first, then apply the length to all of them
        // (BUG-lenmulti: only the last was getting it).
        // ponytail: `length` also fixes SAS variable *order*, but that needs the
        // PDV pre-seeded at compile time (a `length` AST node the executor reads);
        // desugaring to runtime assignments would wipe SET-loaded values. Left as
        // an inert node — dm runs with correct values, column order is a follow-up.
        while (self.p.check(.name)) {
            var group: std.ArrayList([]const u8) = .empty;
            // A group may use a numbered range `x1-x3` (GH#32) — same expander the
            // keep=/drop= and parseNameList sides use, so `x01-x03` pads correctly.
            while (self.p.check(.name)) {
                const name = self.p.advance().text;
                if (self.p.eat(.minus)) {
                    const last = try self.p.expect(.name, "name after '-' in length range");
                    try expandRange(self.p.arena, &group, name, last.text);
                } else try group.append(self.p.arena, name);
            }
            const is_char = self.p.eat(.dollar);
            const len = self.lengthNumber(); // `$4` or dotted `$4.`
            try self.checkDeclLen(is_char, len, group.items[0], kw.line);
            if (is_char) if (len) |l| {
                for (group.items) |name| try self.char_lens.append(self.p.arena, .{ .name = name, .len = l });
            };
        }
        _ = try self.p.expect(.semicolon, "';' after length");
        return .{ .drop = &[_][]const u8{} }; // no-op statement (effect recorded above)
    }

    /// A LENGTH width number, tolerant of the SAS trailing dot: `11`, `11.`
    /// (one number token or a number followed by stray dot tokens). null =
    /// none written — distinct from an explicit `0`, which is out of range.
    fn lengthNumber(self: *Parser) ?usize {
        if (!self.p.check(.number)) return null;
        const n = std.fmt.parseInt(usize, std.mem.trimEnd(u8, self.p.advance().text, "."), 10) catch 0;
        while (self.p.eat(.dot)) {}
        return n;
    }

    /// BUG-lengthcapnostore: reject an impossible declared length AT THE
    /// STATEMENT (LENGTH and ATTRIB both route here), so a store-free
    /// `length y $40000; run;` is loud — SAS rejects the LENGTH statement
    /// itself at compile time, no assignment needed (a metadata-driven shell
    /// generator emits declarations without any store).
    /// Complements pdv.setAt's cap (67a3c834), which stays: that one catches
    /// lengths arriving by routes that never pass through this parser (SET-
    /// source carries, XPORT/sas7bdat reader lens) at the first store; this
    /// one fires earlier for parser-stamped declarations, so the two never
    /// double-report. Same message text on both routes.
    /// Doc: LENGTH Statement, SAS 9.4 DATA Step Statements: Reference printed
    /// p.217 (pdf 228 at the volume's +11 offset — verified: the "LENGTH
    /// Statement 217" footer closes pdf 228): "For character variables, 1 to
    /// 32767 bytes under all operating environments"; ATTRIB LENGTH= repeats
    /// it at printed p.34 (pdf 45 — "34 Chapter 2" footer). Numeric range is
    /// "2 to 8 bytes or 3 to 8 bytes, depending on your operating
    /// environment": the 8 cap is universal and checked.
    /// BUG-attrboundssilent: so are the FLOORS, which this function used to
    /// swallow under a blanket "minimum is platform-dependent" park. The
    /// character minimum is NOT platform-dependent — "1 to 32767 bytes under
    /// all operating environments" is the same doc sentence — and numeric 0/1
    /// are out of range on every platform the doc lists, z/OS included. An
    /// out-of-range length is a malformed program → rc 1 (D-009b(ii)), same
    /// class and wording shape as the two maximum errors above.
    fn checkDeclLen(self: *Parser, is_char: bool, len: ?usize, name: []const u8, line: usize) Error!void {
        const l = len orelse return; // no width written (`length c $;`) — nothing to check
        if (is_char and l > pdv.max_char_len)
            return self.p.diags.fail(error.ParseError, line, "Character variable {s} has length {d}, over the SAS maximum character length 32767.", .{ name, l });
        if (!is_char and l > 8)
            return self.p.diags.fail(error.ParseError, line, "Numeric variable {s} has length {d}, over the SAS maximum numeric length 8.", .{ name, l });
        if (is_char and l == 0)
            return self.p.diags.fail(error.ParseError, line, "Character variable {s} has length {d}, under the SAS minimum character length 1.", .{ name, l });
        // ponytail: numeric length 2 stays ACCEPTED — legal z/OS, illegal
        // UNIX/Windows; that ONE boundary really is platform-dependent (the
        // park the old comment over-applied to every lower bound). Reject 2
        // when a platform target is decided (oracle-unblocked-readings.md 4a).
        if (!is_char and l < 2)
            return self.p.diags.fail(error.ParseError, line, "Numeric variable {s} has length {d}, under the SAS minimum numeric length 2.", .{ name, l });
    }

    fn charLenOf(self: *Parser, name: []const u8) ?usize {
        for (self.char_lens.items) |c| if (std.ascii.eqlIgnoreCase(c.name, name)) return c.len;
        return null;
    }

    /// Record a sum-statement accumulator (dedup, case-insensitive) and queue
    /// its `retain v 0;` into `pending` — injected right AFTER the statement,
    /// so the compile-time PDV establishes the var at the SUM STATEMENT's
    /// textual position (first-mention: Language Reference: Concepts p.478 Fig. 20.2 lands TeamTotal
    /// AFTER the INPUT vars, and a SET/assignment preceding the sum statement
    /// owns the earlier slots — QA tick377 F2, where the old step-TOP hoist
    /// pre-empted a second-SET POINT= lookup's columns).
    fn registerSumVar(self: *Parser, name: []const u8) Error!void {
        for (self.sum_vars.items) |n| if (std.ascii.eqlIgnoreCase(n, name)) return;
        for (self.explicit_init_vars.items) |n| if (std.ascii.eqlIgnoreCase(n, name)) return;
        try self.sum_vars.append(self.p.arena, name);
        const zero = try self.p.arena.create(ast.Expr);
        zero.* = .{ .num = 0 };
        const items = try self.p.arena.alloc(ast.RetainItem, 1);
        items[0] = .{ .name = name, .init = zero };
        try self.pending.append(self.p.arena, .{ .retain = items });
    }

    /// Wrap `value` in `__assignc(value, n)` — assignment-to-length-n-char-var
    /// semantics (see functions.zig); substr(rhs,1,n) was the old desugar but
    /// it slices the BEST12 field's blank left edge for a numeric rhs (n<12).
    fn truncate(self: *Parser, value: *const ast.Expr, n: usize) Error!*const ast.Expr {
        const args = try self.p.arena.alloc(ast.Expr, 2);
        args[0] = value.*;
        args[1] = .{ .num = @floatFromInt(n) };
        const call = try self.p.arena.create(ast.Expr);
        call.* = .{ .call = .{ .name = "__assignc", .args = args } };
        return call;
    }

    fn parseIf(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // if
        const cond = try self.p.parseExpr();
        if (self.eatKw("then")) {
            const then_branch = try self.mkStmt(try self.parseStmt());
            const else_branch: ?*const ast.Stmt =
                if (self.eatKw("else")) try self.mkStmt(try self.parseStmt()) else null;
            return .{ .if_ = .{ .cond = cond, .then_branch = then_branch, .else_branch = else_branch } };
        }
        // subsetting `if c;` — both branches null
        _ = try self.p.expect(.semicolon, "';' or 'then'");
        return .{ .if_ = .{ .cond = cond, .then_branch = null, .else_branch = null } };
    }

    /// `where expr;` — engine-level pre-read filter (exec.applyWhereStmt).
    fn parseWhere(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // where
        // Grab the predicate token span up to the terminating ';' and route it
        // through the SAME desugar as the where= dataset option, so BETWEEN /
        // IS NULL / IS MISSING parse identically to PROC SQL and where=
        // (GH#35 ISS-wherenull, GAP-wherestmtops). LIKE/IN/CONTAINS/comparisons
        // are already handled by parser_expr's WHERE-context Pratt loop; desugar
        // leaves those untouched.
        const start = self.p.pos;
        while (!self.p.check(.semicolon) and !self.p.check(.eof)) _ = self.p.advance();
        const span = self.p.toks[start..self.p.pos];
        _ = try self.p.expect(.semicolon, "';' after where");
        const dtoks = try sql.desugarPredicates(self.p.arena, self.p.diags, span);
        // eof-terminate so the sub-parser can peek past the end.
        const wtoks = try self.p.arena.alloc(Token, dtoks.len + 1);
        @memcpy(wtoks[0..dtoks.len], dtoks);
        wtoks[dtoks.len] = .{ .tag = .eof, .line = self.p.peek().line };
        var pp = pe.Parser.init(self.p.arena, wtoks, self.p.diags);
        pp.where_ctx = true; // `<>` means NE in a WHERE expression (BUG-wherene)
        pp.arrays = self.p.arrays; // keep array refs resolvable, as the shared cursor did
        const cond = try pp.parseExpr();
        // Fail LOUD on leftover tokens — an unparsed predicate must not silently
        // filter nothing (fail-loud, mirrors io.applyWhere).
        if (pp.peek().tag != .eof)
            return self.p.diags.fail(error.ParseError, pp.peek().line, "unexpected token '{s}' in where predicate", .{pp.peek().text});
        // A dedicated node, NOT a subsetting-if: WHERE is an engine-level
        // pre-read filter, so end=/first./last. must see the filtered stream
        // (exec.applyWhereStmt — GAP-vtabledisk fallout).
        return .{ .where_ = cond };
    }

    /// `select (sel); when (v…) s; … otherwise s; end;` — desugared to a nested
    /// if/then/else chain (only the first matching WHEN runs, then the OTHERWISE).
    /// A bare `select;` uses each WHEN's expression as the condition directly.
    fn parseSelect(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // select
        const selector: ?*const ast.Expr = if (self.p.check(.lparen)) blk: {
            _ = self.p.advance();
            const e = try self.p.parseExpr();
            _ = try self.p.expect(.rparen, "')' after select expression");
            break :blk e;
        } else null;
        _ = try self.p.expect(.semicolon, "';' after select");

        const When = struct { cond: *const ast.Expr, stmt: *const ast.Stmt };
        var whens: std.ArrayList(When) = .empty;
        var otherwise: ?*const ast.Stmt = null;
        while (!self.atKw("end") and !self.p.check(.eof)) {
            // SAS 9.4: OTHERWISE must be the LAST clause — a WHEN (or a second
            // OTHERWISE) after it is a syntax error, not an unreachable branch
            // (BUG-selectwhenafterother). One guard covers both.
            if (otherwise != null)
                return self.p.diags.fail(error.ParseError, self.p.peek().line, "OTHERWISE must be the last clause in a SELECT block", .{});
            if (self.eatKw("otherwise")) {
                // A bodyless `otherwise;` is VALID SAS: "do nothing for unmatched
                // values" — it suppresses the no-match error (BUG-emptyotherwise).
                // Desugar to a no-op branch (null_stmt) so the terminal else is a
                // real statement, NOT the fail-loud select_nomatch node below.
                otherwise = if (self.p.check(.semicolon)) blk: {
                    _ = self.p.advance(); // `otherwise;` → no action
                    break :blk try self.mkStmt(.null_stmt);
                } else try self.mkStmt(try self.parseStmt());
            } else if (self.eatKw("when")) {
                _ = try self.p.expect(.lparen, "'(' after when");
                var cond = try self.whenCond(selector, try self.p.parseExpr());
                while (self.p.eat(.comma))
                    cond = try self.mkExpr(.{ .binary = .{ .op = .@"or", .lhs = cond, .rhs = try self.whenCond(selector, try self.p.parseExpr()) } });
                _ = try self.p.expect(.rparen, "')' after when values");
                try whens.append(self.p.arena, .{ .cond = cond, .stmt = try self.mkStmt(try self.parseStmt()) });
            } else {
                return self.p.diags.fail(error.ParseError, self.p.peek().line, "expected WHEN or OTHERWISE in SELECT", .{});
            }
        }
        try self.expectKw("end");
        _ = try self.p.expect(.semicolon, "';' after end");

        // fold right-to-left into `if c1 then s1; else if c2 then s2; … else oth;`.
        // No OTHERWISE → the terminal else must FAIL LOUD if reached: SAS errors and
        // stops the step when no WHEN matches and there is no OTHERWISE (BUG-selectnomatch).
        // A bare `select;` (no WHENs, no OTHERWISE) is a genuine no-op — nothing to match.
        var else_b: ?*const ast.Stmt = otherwise orelse
            (if (whens.items.len == 0) null else try self.mkStmt(.select_nomatch));
        var k = whens.items.len;
        while (k > 0) {
            k -= 1;
            else_b = try self.mkStmt(.{ .if_ = .{ .cond = whens.items[k].cond, .then_branch = whens.items[k].stmt, .else_branch = else_b } });
        }
        if (else_b) |node| return node.*;
        return .{ .do_ = .{ .header = .simple, .body = &.{} } }; // empty select → no-op
    }

    /// The WHEN condition: `selector = value` when SELECT has a selector, else the
    /// value expression used directly (bare `select;`).
    fn whenCond(self: *Parser, selector: ?*const ast.Expr, value: *const ast.Expr) Error!*const ast.Expr {
        const sel = selector orelse return value;
        return self.mkExpr(.{ .binary = .{ .op = .eq, .lhs = sel, .rhs = value } });
    }

    fn mkExpr(self: *Parser, e: ast.Expr) Error!*const ast.Expr {
        const p = try self.p.arena.create(ast.Expr);
        p.* = e;
        return p;
    }

    // ── hash objects ────────────────────────────────────────────────────────

    /// The token `k` positions ahead of the cursor (clamped to the trailing eof).
    fn tokAt(self: *Parser, k: usize) Token {
        const j = self.p.pos + k;
        return if (j < self.p.toks.len) self.p.toks[j] else self.p.toks[self.p.toks.len - 1];
    }

    /// Does the cursor sit on `obj . method (` — an object method call? (`first.`/
    /// `last.` were already coalesced into single name tokens, so they don't match.)
    fn hashMethodAhead(self: *Parser) bool {
        return self.p.check(.name) and self.tokAt(1).tag == .dot and
            self.tokAt(2).tag == .name and self.tokAt(3).tag == .lparen;
    }

    /// Does the cursor sit on `obj . attribute` with NO `(` — a parenless hash
    /// attribute reference (`n = h.num_items;`, Language Reference: Concepts p.623; GAP-hashnumitems)?
    /// The absent paren is what distinguishes it from the method-call form.
    fn hashAttrAhead(self: *Parser) bool {
        return self.p.check(.name) and self.tokAt(1).tag == .dot and
            self.tokAt(2).tag == .name and self.tokAt(3).tag != .lparen;
    }

    /// `declare hash h(dataset:"x");` — only the `hash` object type for now.
    fn parseDeclare(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // declare / dcl
        // `declare hash h(...)` or `declare hiter hi("h")` — both carry a name and
        // a paren arg list; the executor tells them apart (an hiter's sole arg is
        // the positional hash name).
        if (!self.eatKw("hash") and !self.eatKw("hiter"))
            return self.p.diags.fail(error.ParseError, self.p.peek().line, "only 'declare hash'/'hiter' is supported", .{});
        const name = (try self.p.expect(.name, "a hash object name")).text;
        var args: []const ast.HashArg = &.{};
        if (self.p.eat(.lparen)) args = try self.p.parseHashArgs();
        _ = try self.p.expect(.semicolon, "';' after declare");
        return .{ .hash_decl = .{ .name = name, .args = args } };
    }

    /// Statement-form hash call after `=`: `rc = h.m(…);` — the call is the
    /// WHOLE rhs, i.e. followed by `;`. The attr form (`n = h.num_items;`) has
    /// no parens to balance.
    fn hashStmtAhead(self: *Parser) bool {
        if (self.hashAttrAhead()) return self.tokAt(3).tag == .semicolon;
        if (!self.hashMethodAhead()) return false;
        var i: usize = 4; // cursor on obj; tokAt(3) is the '('
        var depth: usize = 1;
        while (true) : (i += 1) {
            switch (self.tokAt(i).tag) {
                .lparen => depth += 1,
                .rparen => depth -= 1,
                .eof => return false,
                else => {},
            }
            if (depth == 0) break;
        }
        return self.tokAt(i + 1).tag == .semicolon;
    }

    /// `obj . method ( args )` — leaves the cursor just past the `)`. The
    /// attribute form `obj . attribute` (Language Reference: Concepts p.623: num_items, item_size)
    /// has no parens at all (GAP-hashnumitems) and yields an empty arg list.
    fn parseHashOp(self: *Parser, target: ?[]const u8) Error!ast.HashCall {
        const obj = self.p.advance().text; // the object name
        _ = try self.p.expect(.dot, "'.' in a hash method call");
        const method = (try self.p.expect(.name, "a hash method")).text;
        const args: []const ast.HashArg = if (self.p.eat(.lparen)) try self.p.parseHashArgs() else &.{};
        return .{ .target = target, .obj = obj, .method = method, .args = args };
    }

    fn parseDo(self: *Parser) Error!ast.Stmt {
        // Nesting depth is guarded once in parseStmt (BUG-stmtnest-deepguard).
        _ = self.p.advance(); // do
        // A combined `do i=… while(c)` / `until(c)` yields a guard to weave into
        // the body (desugar to plain iter + `if … then leave;` — no new AST).
        var guard_cond: ?*const ast.Expr = null;
        var guard_until = false;
        var hoisted: std.ArrayList(ast.Stmt) = .empty; // hash-attr bound reads (GAP-hashnumitems)
        var loop_hoists: std.ArrayList(ast.Stmt) = .empty; // hash calls in the while/until guard (GAP-hashinexpr)
        const header = try self.parseDoHeader(&guard_cond, &guard_until, &hoisted, &loop_hoists);
        // A pure `do while(c)` / `do until(c)` whose guard hoisted a hash call
        // KEEPS exec's while_/until_ header (desugaring to a do-group would make
        // the leave-guard a stray LEAVE — invalid SAS). Instead prime the temp:
        // WHILE tests at the top, so run the call BEFORE the loop and re-arm it
        // at the bottom of the body; UNTIL tests at the bottom, so the call
        // belongs at the bottom of the body only. Each test then reads a fresh
        // call, in the same order SAS would issue them.
        var pure_while = false;
        var pure_until = false;
        if (loop_hoists.items.len > 0 and guard_cond == null) switch (header) {
            .while_ => {
                try hoisted.appendSlice(self.p.arena, loop_hoists.items);
                pure_while = true;
            },
            .until_ => pure_until = true,
            else => {},
        };
        var body: std.ArrayList(ast.Stmt) = .empty;
        // Combined `do i=… while(c)`: test at the top — `if not c then leave;`
        // before the body, with the guard's hoisted calls re-run first EVERY
        // iteration (leaving them to the statement-level drain would test one
        // stale temp forever).
        if (guard_cond) |c| if (!guard_until) {
            try body.appendSlice(self.p.arena, loop_hoists.items);
            try body.append(self.p.arena, try self.leaveGuard(c, false));
        };
        while (!self.atKw("end") and !self.p.check(.eof))
            try body.append(self.p.arena, try self.parseStmt());
        // Combined UNTIL: test at the bottom — `if c then leave;` after the body.
        if (guard_cond) |c| if (guard_until) {
            try body.appendSlice(self.p.arena, loop_hoists.items);
            try body.append(self.p.arena, try self.leaveGuard(c, true));
        };
        if (pure_while or pure_until)
            try body.appendSlice(self.p.arena, loop_hoists.items);
        try self.expectKw("end");
        _ = try self.p.expect(.semicolon, "';' after end");
        const loop: ast.Stmt = .{ .do_ = .{ .header = header, .body = try body.toOwnedSlice(self.p.arena) } };
        if (hoisted.items.len == 0) return loop;
        // A hash-attribute bound (`do i = 1 to h.num_items;`) reads the attribute
        // via a hash_op hoisted BEFORE the loop into a temp the bound references
        // (SAS evaluates the bounds once at loop entry — the hoist is exact).
        var wrap: std.ArrayList(ast.Stmt) = .empty;
        try wrap.appendSlice(self.p.arena, hoisted.items);
        try wrap.append(self.p.arena, loop);
        return .{ .do_ = .{ .header = .simple, .body = try wrap.toOwnedSlice(self.p.arena) } };
    }

    /// A do-header bound expression. Bounds are ordinary expressions, EXCEPT a
    /// parenless hash attribute `h.num_items` / `h.item_size` (Language Reference: Concepts p.623,
    /// GAP-hashnumitems): the evaluator can't see hash objects, so hoist the
    /// read into a `__hashattr_N` temp (a hash_op statement emitted before the
    /// loop) and bind the temp. Anything deeper (`h.num_items + 1`) hoists the
    /// same way via the general expression path (GAP-hashinexpr).
    fn parseDoBound(self: *Parser, hoisted: *std.ArrayList(ast.Stmt)) Error!*const ast.Expr {
        if (self.hashAttrAhead()) {
            const obj = self.p.advance().text;
            _ = self.p.advance(); // '.'
            const attr = self.p.advance().text;
            self.hashattr_n += 1;
            const tmp = try std.fmt.allocPrint(self.p.arena, "__hashattr_{d}", .{self.hashattr_n});
            try hoisted.append(self.p.arena, .{ .hash_op = .{ .target = tmp, .obj = obj, .method = attr, .args = &.{} } });
            return self.mkExpr(.{ .variable = tmp });
        }
        return self.p.parseExpr();
    }

    fn parseDoHeader(self: *Parser, guard_cond: *?*const ast.Expr, guard_until: *bool, hoisted: *std.ArrayList(ast.Stmt), loop_hoists: *std.ArrayList(ast.Stmt)) Error!ast.DoHeader {
        var header: ast.DoHeader = undefined;
        if (self.p.check(.semicolon)) {
            header = .simple;
        } else if (self.eatKw("while")) {
            header = .{ .while_ = try self.parseGuardExpr(loop_hoists) };
        } else if (self.eatKw("until")) {
            header = .{ .until_ = try self.parseGuardExpr(loop_hoists) };
        } else {
            const name = (try self.p.expect(.name, "a do-loop variable")).text;
            _ = try self.p.expect(.eq, "'=' in do loop");
            // one or more comma-separated specs, each `expr [to expr [by expr]]`
            var specs: std.ArrayList(ast.DoSpec) = .empty;
            while (true) {
                const start = try self.parseDoBound(hoisted);
                // `to` and `by` may appear in EITHER order, and `by` may appear
                // WITHOUT `to` (an open-ended counter loop) — GAP-dobynoto. SAS
                // accepts `1 to 6 by 2`, `1 by 2 to 6`, and `1 by 1` alike.
                var stop: ?*const ast.Expr = null;
                var by: ?*const ast.Expr = null;
                while (true) {
                    if (stop == null and self.eatKw("to")) {
                        stop = try self.parseDoBound(hoisted);
                    } else if (by == null and self.eatKw("by")) {
                        by = try self.parseDoBound(hoisted);
                    } else break;
                }
                try specs.append(self.p.arena, .{ .start = start, .stop = stop, .by = by });
                if (!self.p.eat(.comma)) break;
            }
            // combined iterative + conditional tail: `… while(c)` / `… until(c)`
            if (self.eatKw("while")) {
                guard_cond.* = try self.parseGuardExpr(loop_hoists);
                guard_until.* = false;
            } else if (self.eatKw("until")) {
                guard_cond.* = try self.parseGuardExpr(loop_hoists);
                guard_until.* = true;
            }
            // a single `start to stop [by]` keeps the plain iter path (and its guard
            // weaving); a single open-ended `start by step` (no TO) is also iter;
            // anything else (a value list / mixed ranges) is a `.list`.
            const only = specs.items.len == 1;
            if (only and specs.items[0].stop != null) {
                header = .{ .iter = .{ .name = name, .start = specs.items[0].start, .stop = specs.items[0].stop.?, .by = specs.items[0].by } };
            } else if (only and specs.items[0].by != null) {
                // Open-ended `do i=start by step;` (no TO) — runs until an UNTIL/WHILE
                // guard (or LEAVE) fires; else effectively unbounded, like SAS. exec
                // has no open-ended iter, so synthesize a stop its
                // `step>0 ? x<=stop : x>=stop` test won't reach first: stop =
                // start + step*1e15 (direction follows step's runtime sign).
                // ponytail: 1e15 caps a truly exitless loop instead of hanging;
                // widen if a real counter loop ever needs more iterations.
                const sp = specs.items[0];
                const big = try self.p.arena.create(ast.Expr);
                big.* = .{ .num = 1e15 };
                const scaled = try self.p.arena.create(ast.Expr);
                scaled.* = .{ .binary = .{ .op = .mul, .lhs = sp.by.?, .rhs = big } };
                const stop = try self.p.arena.create(ast.Expr);
                stop.* = .{ .binary = .{ .op = .add, .lhs = sp.start, .rhs = scaled } };
                header = .{ .iter = .{ .name = name, .start = sp.start, .stop = stop, .by = sp.by } };
            } else {
                header = .{ .list = .{ .name = name, .specs = try specs.toOwnedSlice(self.p.arena) } };
            }
        }
        _ = try self.p.expect(.semicolon, "';' after do header");
        return header;
    }

    /// `if not c then leave;` (WHILE, `until=false`) or `if c then leave;`
    /// (UNTIL, `until=true`) — the conditional-exit for a combined iterative DO.
    fn leaveGuard(self: *Parser, cond: *const ast.Expr, until: bool) Error!ast.Stmt {
        const leave_stmt = try self.p.arena.create(ast.Stmt);
        leave_stmt.* = .leave;
        const guard: *const ast.Expr = if (until) cond else blk: {
            const n = try self.p.arena.create(ast.Expr);
            n.* = .{ .unary = .{ .op = .not, .operand = cond } };
            break :blk n;
        };
        return .{ .if_ = .{ .cond = guard, .then_branch = leave_stmt, .else_branch = null } };
    }

    fn parseRetain(self: *Parser) Error!ast.Stmt {
        const kw_line = self.p.peek().line;
        _ = self.p.advance(); // retain
        var items: std.ArrayList(ast.RetainItem) = .empty;
        // RETAIN is a series of groups: `element-list <initial-value(s)>`. Within a
        // group the trailing values bind positionally when there are multiple
        // (1st value → 1st element; elements past the value count get no init).
        // A SINGLE value after the element-list seeds EVERY element in the group
        // (`retain a b c 'X'` → a=b=c='X'; `retain s1-s2 0` → s1=s2=0).
        while (self.p.check(.name)) {
            var elems: std.ArrayList([]const u8) = .empty;
            while (self.p.check(.name)) {
                const name = self.p.advance().text;
                // `a1-a3` numbered range (STMT-ranges). `-` followed by a
                // non-name is an initial value, not a range — leave it for values.
                if (self.p.check(.minus) and self.peekNext().tag == .name) {
                    _ = self.p.advance(); // '-'
                    try expandRange(self.p.arena, &elems, name, self.p.advance().text);
                } else {
                    try elems.append(self.p.arena, name);
                }
            }
            // Initial values come in two forms with DIFFERENT distribution
            // (GAP-retainpareninit): a bare list after the element-list keeps the
            // historical rule (a SINGLE value seeds EVERY element, GH#51; several
            // bind positionally), while a parenthesised `(v1 v2 …)` group binds
            // STRICTLY positionally — `retain a b c (0)` inits only a (b,c stay
            // missing). MORE values than elements is a SAS ERROR (NOTE-retainexcessinit,
            // mirrors the ARRAY fix BUG-arrayinitvalidate F1) — the excess used to be
            // silently dropped. FEWER stays legal (elements past the value count get no
            // init).
            var vals: std.ArrayList(*const ast.Expr) = .empty;
            var paren_vals = false;
            if (self.p.eat(.lparen)) {
                // mirror the ARRAY `(…)` init list: space- or comma-separated exprs
                paren_vals = true;
                while (!self.p.check(.rparen) and !self.p.check(.eof)) {
                    if (self.p.eat(.comma)) continue;
                    const val_line = self.p.peek().line;
                    const v = try self.p.parseExpr();
                    // CONSTANTS ONLY, same hole and same rule as the ARRAY list
                    // (GH#81): `retain x (a);` with `a=5` used to give `x=.` at rc 0.
                    // The BARE form below never had the hole — its `is_val` gate
                    // already admits only number/dot/string tokens.
                    if (try self.badInitValue(v)) |what|
                        return self.p.diags.fail(error.ParseError, val_line, "{s} is not a valid initial value in the RETAIN statement; RETAIN initial values must be constants.", .{what});
                    try vals.append(self.p.arena, v);
                }
                _ = try self.p.expect(.rparen, "')' after retain initial values");
            } else {
                // trailing initial values for this element-list (a `-` here begins a
                // negative literal, since the name-list above already ran out).
                while (true) {
                    // `retain t .A` — a special-missing init after a var NAME lexes as a
                    // plain `.` (member-access dot, empty text) + a one-letter NAME, since
                    // the lexer can't tell `.A` from `obj.field` context-free. In RETAIN
                    // value position there is no member access, so fold `. A` back into one
                    // special-missing literal (BUG-retaininitspecialmiss).
                    if (self.p.check(.dot) and self.p.peek().text.len == 0 and isMissLetter(self.peekNext())) {
                        _ = self.p.advance(); // '.'
                        const letter = self.p.advance().text[0];
                        const e = try self.p.arena.create(ast.Expr);
                        e.* = .{ .num = Value.specialMissing(letter).num };
                        try vals.append(self.p.arena, e);
                        continue;
                    }
                    const is_val = switch (self.p.peek().tag) {
                        .number, .dot, .string => true,
                        .minus => self.peekNext().tag == .number or self.peekNext().tag == .dot,
                        else => false,
                    };
                    if (!is_val) break;
                    try vals.append(self.p.arena, try self.p.parseExpr());
                }
            }
            if (vals.items.len > elems.items.len)
                return self.p.diags.fail(error.ParseError, kw_line, "The number of initial values ({d}) exceeds the number of variables ({d}) in the RETAIN statement.", .{ vals.items.len, elems.items.len });
            for (elems.items, 0..) |nm, i| {
                const init_val: ?*const ast.Expr =
                    if (!paren_vals and vals.items.len == 1) vals.items[0] else if (i < vals.items.len) vals.items[i] else null;
                if (init_val != null) try self.explicit_init_vars.append(self.p.arena, nm);
                try items.append(self.p.arena, .{ .name = nm, .init = init_val });
            }
        }
        _ = try self.p.expect(.semicolon, "';' after retain");
        return .{ .retain = try items.toOwnedSlice(self.p.arena) };
    }

    fn parseInput(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // input
        var items: std.ArrayList(ast.InputItem) = .empty;
        while (!self.p.check(.semicolon) and !self.p.check(.eof)) {
            // `/` line pointer → advance to the next input record (io handles it).
            if (self.p.eat(.slash)) {
                try items.append(self.p.arena, .{ .name = "", .type = .num, .informat = "/" });
                continue;
            }
            // pointer controls: `@col` (column), `+n` (skip), `#n` (line) — a
            // position item (name = "") the reader applies; io tracks the column.
            // BUG-inputatvarptr: `@` followed by a number OR a variable NAME is a
            // column pointer (`@n` reads the column from n's PDV value) — a
            // trailing `@` line-hold is `@` with NO operand (directly before `;`).
            // ponytail: `+var`/`#var` siblings have the same number-only limit
            // (GAP-inputpointerguard: their valid forms fail as GAPS below, rc 2).
            // GAP-inputatstring: `@'string'` adds a THIRD form — column pointer to
            // just after the next occurrence of the literal in the record. The
            // string token's text is quote-stripped, so re-wrap it: the quote in
            // the encoded spec is how io tells it from `@n`/`@var`.
            // GAP-atexpression: `@(expression)` — the FOURTH `@` pointer form
            // (Statements printed p.168: 'moves the pointer to the column that is
            // given by the value of expression'; zero/negative → column 1, the SAME
            // clamp as @n/@numeric-variable). The AST rides the item (col_expr) and
            // io.zig evaluates it per read — `b=5; input @(b*3) name $10.;` is the
            // doc's own example. (BUG-atcol0crash's loud parse of this form is now
            // a real implementation; the clamp it protected is clampCol's.)
            if (self.p.check(.at) and self.peekNext().tag == .lparen) {
                _ = self.p.advance(); // '@'
                _ = self.p.advance(); // '('
                const e = try self.p.parseExpr();
                _ = try self.p.expect(.rparen, "')' after @(expression");
                try items.append(self.p.arena, .{ .name = "", .type = .num, .col_expr = e });
                continue;
            }
            if (self.p.check(.at) and (self.peekNext().tag == .number or self.peekNext().tag == .name or self.peekNext().tag == .string)) {
                _ = self.p.advance(); // '@'
                const t = self.p.advance();
                const spec = if (t.tag == .string)
                    try std.fmt.allocPrint(self.p.arena, "@'{s}'", .{t.text})
                else
                    try std.fmt.allocPrint(self.p.arena, "@{s}", .{t.text});
                try items.append(self.p.arena, .{ .name = "", .type = .num, .informat = spec });
                continue;
            }
            if (self.p.check(.plus)) {
                const t = self.p.advance(); // '+'
                // GAP-inputpointerguard: `+numeric-variable` / `+(expression)` are
                // valid SAS 9.4 INPUT pointer controls (Statements Table 2.3)
                // opensas doesn't implement → gap (rc 2); anything else after `+`
                // is not INPUT syntax → user error (rc 1). Same message either way
                // (D-009). Only `+n` reads today — `+var` needs a backward-capable
                // input buffer, which is exec work, deliberately not this guard.
                if (!self.p.check(.number)) {
                    if (self.p.check(.name) or self.p.check(.lparen))
                        return failGap(self.p.diags, t.line, "input: only an integer +n column pointer is supported", .{});
                    return self.p.diags.fail(error.ParseError, t.line, "input: only an integer +n column pointer is supported", .{});
                }
                const n = self.p.advance().text;
                try items.append(self.p.arena, .{ .name = "", .type = .num, .informat = try std.fmt.allocPrint(self.p.arena, "+{s}", .{n}) });
                continue;
            }
            if (self.p.check(.hash)) {
                const t = self.p.advance(); // '#'
                // `#numeric-variable` / `#(expression)`: same split as `+` above —
                // valid SAS 9.4 (Table 2.3 line pointer controls) → gap; else user
                // error. `#var` additionally needs N=>1 line-buffer tracking (exec).
                if (!self.p.check(.number)) {
                    if (self.p.check(.name) or self.p.check(.lparen))
                        return failGap(self.p.diags, t.line, "input: only an integer #n line pointer is supported", .{});
                    return self.p.diags.fail(error.ParseError, t.line, "input: only an integer #n line pointer is supported", .{});
                }
                const n = self.p.advance().text;
                try items.append(self.p.arena, .{ .name = "", .type = .num, .informat = try std.fmt.allocPrint(self.p.arena, "#{s}", .{n}) });
                continue;
            }
            // `@@` double-trailing hold → a sentinel item the driver acts on
            // (hold the input line across DATA-step iterations).
            if (self.p.eat(.atat)) {
                try items.append(self.p.arena, .{ .name = "", .type = .num, .informat = "@@" });
                continue;
            }
            // single trailing `@` — hold the input record for the next INPUT in this
            // same iteration (released when control returns to the top of the step).
            // A nameless `@` sentinel item the executor acts on (PG-atptr).
            if (self.p.eat(.at)) {
                try items.append(self.p.arena, .{ .name = "", .type = .num, .informat = "@" });
                continue;
            }
            if (!self.p.check(.name)) break;
            const name_tok = self.p.advance();
            const name = name_tok.text;
            // GAP-inputarrayelem: `input v{i}` — an array-element target, the
            // shape Language Reference: Concepts Table 21.5 row 1 (p.516) names ("#n or / line pointer
            // control in the INPUT statement with a DO loop" reads N records
            // into array elements). Mirrors parsePut: the def + flat subscript
            // are parsed here, io.zig resolves the index per read. PUT and
            // assignment already accepted the same reference; INPUT was the
            // lone rejection, with a misleading "expected ';'" message.
            var arr_index: ?*const ast.Expr = null;
            var arr_elements: []const []const u8 = &.{};
            var arr_name: []const u8 = &.{};
            if (self.p.check(.lbrace)) {
                _ = self.p.lookupArray(name) orelse
                    return self.p.diags.fail(error.ParseError, name_tok.line, "input: {s} is not a declared array", .{name});
                if (self.p.pos + 1 < self.p.toks.len and self.p.toks[self.p.pos + 1].tag == .star)
                    return self.p.diags.fail(error.ParseError, name_tok.line, "input: whole-array reference {s}{{*}} is not an INPUT target", .{name});
                const r = try self.p.parseArraySubscript(name_tok);
                if (r.def.special != null)
                    return self.p.diags.fail(error.ParseError, name_tok.line, "input: special-list array {s} (_NUMERIC_/_CHARACTER_/_ALL_) is not an INPUT target", .{name});
                arr_index = r.index;
                arr_elements = r.def.elements;
                arr_name = name;
            }
            // GAP-inputnumrange: a numbered range `Score1-Score3` expands via the
            // shared expandRange helper (ARRAY/KEEP/PUT/OF all use it — the GH#32 /
            // BUG-lengthrange precedent); every member inherits the item's
            // modifiers. A NUMBER after the dash is not this — `var 1-5` is column
            // input, handled below.
            var range: ?std.ArrayList([]const u8) = null;
            if (arr_index == null and self.p.check(.minus) and self.peekNext().tag == .name) {
                _ = self.p.advance(); // '-'
                range = .empty;
                try expandRange(self.p.arena, &range.?, name, self.p.advance().text);
            }
            var is_char = self.p.eat(.dollar);
            // INPUT error-suppression modifier `?`/`??` between the var and its
            // informat (`input x ?? 3.;`) — twin of the INPUT() fn path
            // (parser_expr.zig, BUG-inputqq). SAS: `?` suppresses the invalid-data
            // NOTE, `??` also suppresses _ERROR_=1. Counted into item.suppress
            // (NOTE-inputinvalidnote made the read path emit them). (GAP-inputstmtqq)
            var suppress: u2 = 0;
            while (self.p.check(.question)) {
                _ = self.p.advance();
                if (suppress < 2) suppress += 1;
            }
            var informat: ?[]const u8 = null;
            var list_mod = false;
            if (self.p.eat(.colon)) {
                // `:informat.` list-input modifier — reconstruct the spec (it
                // tokenizes unevenly, e.g. `comma8.` = name+dot). The colon means
                // list input (token-then-informat), NOT fixed-width (DATALINES-informat).
                list_mod = true;
                informat = try self.tryFormatSpec();
            } else if (self.p.check(.number) and self.peekNext().tag == .minus) {
                // column input `var start-end` → encode the range as `@s-e`.
                const start = self.p.advance().text;
                _ = self.p.advance(); // '-'
                const end = if (self.p.check(.number)) self.p.advance().text else start;
                informat = try std.fmt.allocPrint(self.p.arena, "@{s}-{s}", .{ start, end });
                // GAP-inputcoldecimal F10: the trailing `.decimals` parameter
                // (`input x 1-5 .2;` — divide by 10^d when the field holds no
                // explicit decimal point) is VALID SAS (SAS 9.4 DATA Step
                // Statements: Reference, INPUT Statement: Column, printed
                // p.183: ".decimals specifies the power of 10 by which to
                // divide the value. If the data contains decimal points, the
                // .decimals value is ignored."). Applying the divisor is
                // read-path work (exec/io), so it is refused HERE as a named
                // gap, rc 2 (D-009/D-009b(i)) — it used to fall to "expected
                // ';' after input", rc 1 blaming punctuation. `.decimals` on
                // a `$` item is not valid SAS → stays the user's rc 1.
                if (!is_char and self.p.check(.number) and self.p.peek().text.len > 1 and self.p.peek().text[0] == '.')
                    return failGap(self.p.diags, self.p.peek().line, "input: the column-input .decimals parameter (input x 1-5 .2;) is not supported", .{});
            } else {
                // a formatted informat right after the variable (`d date9.`, `x 5.`).
                informat = try self.tryFormatSpec();
            }
            if (informat) |spec| if (spec.len > 0 and spec[0] == '$') {
                is_char = true; // a `$…` informat reads a character value
            };
            if (range) |names| {
                for (names.items) |nm| try items.append(self.p.arena, .{ .name = nm, .type = if (is_char) .char else .num, .informat = informat, .list_mod = list_mod, .suppress = suppress });
            } else {
                // an array-element target carries an EMPTY name (the array's own
                // name is not a PDV column — the compile-time pre-declare skips
                // nameless items; BUG-inputptrvar) plus the subscript/elements.
                try items.append(self.p.arena, .{ .name = if (arr_index != null) "" else name, .type = if (is_char) .char else .num, .informat = informat, .list_mod = list_mod, .arr_index = arr_index, .arr_elements = arr_elements, .arr_name = arr_name, .suppress = suppress });
            }
        }
        // GAP-inputmods: name the unsupported modifier instead of a bare
        // "expected ';'" — `&` (values with embedded blanks), `~` (quoted
        // values), named input `x=` each fail loud with their own message.
        // (`~` lexes as .caret; none of these can follow a complete INPUT item.)
        if (self.p.check(.amp))
            return failGap(self.p.diags, self.p.peek().line, "input: the & modifier (list input of values with embedded blanks) is not supported", .{});
        if (self.p.check(.caret))
            return failGap(self.p.diags, self.p.peek().line, "input: the ~ modifier (list input of quoted values) is not supported", .{});
        if (self.p.check(.eq))
            return failGap(self.p.diags, self.p.peek().line, "input: named input (x=) is not supported", .{});
        _ = try self.p.expect(.semicolon, "';' after input");
        return .{ .input = try items.toOwnedSlice(self.p.arena) };
    }

    /// `array a{n} a1-a5 (10 20 …);` — dimension, member list (numbered ranges
    /// expanded), optional parenthesised initial values. Registers the array so
    /// later `a{i}` expressions resolve. `_temporary_` gives the array anonymous
    /// members (synthesised from the dimension). ponytail: no `$`/`k*v` repeats.
    fn parseArray(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // array
        const name = (try self.p.expect(.name, "array name")).text;
        // Dimension delimiter: `{n}`/`[n]` (the lexer maps `{` and `[` to lbrace) OR
        // `(n)`/`(*)` — SAS allows all three. The FIRST paren after the array name is
        // the dimension; the optional initial-value `(…)` list comes AFTER the element
        // list, so position disambiguates them (BUG-arrayparendim; real SDTM macro
        // libraries use `array bits (&n) &varlist;`).
        const paren_dim = self.p.eat(.lparen);
        if (!paren_dim) _ = try self.p.expect(.lbrace, "'{{' array dimension");
        // GAP-multidimarray: one or more comma-separated dimensions, each `n` or
        // `lo:hi` (ARRAY-lobound-impl per dimension). SAS 9.4: "the number of
        // elements is the product of the dimensions." `dims` records each lo/size
        // for the reference index-fold; `dim` is the element count for member
        // auto-generation. A single `*` (1-D only) infers its size from the members.
        var dims_list: std.ArrayList(pe.ArrayDim) = .empty;
        const dim_line = self.p.peek().line;
        while (true) {
            // A bound may be NEGATIVE (`array x[-3:3]`, GAP-arraybounds-batch): a
            // leading `.minus` belongs to the bound, not to a range operator.
            const neg = self.p.eat(.minus);
            if (self.p.check(.number)) {
                var first = std.fmt.parseInt(i64, self.p.advance().text, 10) catch 0;
                if (neg) first = -first;
                if (self.p.eat(.colon)) {
                    const neg_hi = self.p.eat(.minus);
                    if (self.p.check(.number)) {
                        var hi = std.fmt.parseInt(i64, self.p.advance().text, 10) catch first;
                        if (neg_hi) hi = -hi;
                        if (hi < first)
                            return self.p.diags.fail(error.ParseError, dim_line, "ARRAY {s}: upper bound {d} is below lower bound {d}", .{ name, hi, first });
                        try dims_list.append(self.p.arena, .{ .lo = first, .size = @intCast(hi - first + 1) });
                    } else if (self.p.eat(.star)) {
                        try dims_list.append(self.p.arena, .{ .lo = first, .size = 0 }); // {lo:*} — inferred
                    } else return self.p.diags.fail(error.ParseError, dim_line, "ARRAY {s}: expected an upper bound after ':'", .{name});
                } else {
                    // a bare `{n}` is an element COUNT — a negative one is nonsense
                    if (neg)
                        return self.p.diags.fail(error.ParseError, dim_line, "ARRAY {s}: negative dimension {d}; use lo:hi for a negative lower bound", .{name, first});
                    try dims_list.append(self.p.arena, .{ .lo = 1, .size = @intCast(first) }); // bare `{n}`
                }
            } else if (!neg and self.p.eat(.star)) {
                try dims_list.append(self.p.arena, .{ .lo = 1, .size = 0 }); // `{*}` — inferred
            } else return self.p.diags.fail(error.ParseError, dim_line, "ARRAY {s}: expected an array dimension", .{name});
            if (!self.p.eat(.comma)) break;
        }
        if (paren_dim)
            _ = try self.p.expect(.rparen, "')' after array dimension")
        else
            _ = try self.p.expect(.rbrace, "'}}' after array dimension");

        // An inferred (`*`) size needs the member list to resolve — only makes sense
        // for a single dimension (can't infer two unknowns). Fail loud otherwise.
        var inferred = false;
        for (dims_list.items) |d| if (d.size == 0) {
            inferred = true;
        };
        if (inferred and dims_list.items.len > 1)
            return self.p.diags.fail(error.ParseError, dim_line, "ARRAY {s}: a '*' dimension is only allowed for a one-dimensional array", .{name});
        // element count = product of the dimensions (0 = inferred → use members/inits)
        var dim: usize = if (inferred) 0 else 1;
        if (!inferred) for (dims_list.items) |d| {
            dim *= d.size;
        };

        // optional `$ [len]` — a character array (its members are char, optionally
        // of a declared length).
        const is_char = self.p.eat(.dollar);
        var char_len: usize = 0;
        if (is_char and self.p.check(.number))
            char_len = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 0;

        var elems: std.ArrayList([]const u8) = .empty;
        var temporary = false;
        var special: ?ast.SpecialArr = null;
        if (self.p.check(.name) and eqi(self.p.peek().text, "_temporary_")) {
            // anonymous members: <name>{1..dim}, referenced only by subscript
            temporary = true;
            _ = self.p.advance();
            var k: usize = 1;
            while (k <= dim) : (k += 1) {
                try elems.append(self.p.arena, try std.fmt.allocPrint(self.p.arena, "_temp_{s}_{d}", .{ name, k }));
            }
        } else if (self.p.check(.name) and specialArrName(self.p.peek().text) != null) {
            // `array v{*} _numeric_ / _character_ / _all_` — members are every
            // matching PDV variable, which isn't known until exec (the PDV type set
            // is a runtime fact). Leave `elems` empty; the kind rides on the decl and
            // every reference, expanded against the live PDV at eval time (GH#48).
            special = specialArrName(self.p.advance().text);
        } else {
            while (self.p.check(.name)) {
                const first = self.p.advance().text;
                if (self.p.eat(.minus)) {
                    const last = (try self.p.expect(.name, "range end variable")).text;
                    try expandRange(self.p.arena, &elems, first, last);
                } else {
                    try elems.append(self.p.arena, first);
                }
            }
        }
        // BUG-arraydimmembercount: an EXPLICIT dimension that disagrees with an
        // EXPLICIT member list is a SAS 9.4 ERROR ("The number of variables ...
        // does not correspond to the number of elements ..."), not a silent
        // override by the member count. Untouched: `{*}` (size inferred from the
        // members), dim-only (`array a{5};` auto-generates a1-a5), _temporary_
        // (its generated count IS the dim) and _numeric_/_character_/_all_
        // (resolved against the PDV at exec).
        if (!inferred and !temporary and special == null and elems.items.len > 0 and elems.items.len != dim)
            return self.p.diags.fail(error.ParseError, dim_line, "ARRAY {s}: the number of variables in the variable list ({d}) does not correspond to the number of array elements ({d})", .{ name, elems.items.len, dim });
        // initial values `(v1 v2 …)` — parsed before finalizing the member list so an
        // implicit-name array can size itself from them when the dimension is `*`.
        var inits: std.ArrayList(*const ast.Expr) = .empty;
        if (self.p.eat(.lparen)) {
            while (!self.p.check(.rparen) and !self.p.check(.eof)) {
                if (self.p.eat(.comma)) continue; // list may be space- or comma-separated
                // SAS repeat factor `n * value` → n copies of value, e.g.
                // `(3*0 1 2)` = 0,0,0,1,2 (BUG-arrayrepeat). In an array init the `*`
                // is always a repeat, never multiplication.
                var count: usize = 1;
                if (self.p.check(.number) and self.p.pos + 1 < self.p.toks.len and self.p.toks[self.p.pos + 1].tag == .star) {
                    count = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 1; // n
                    _ = self.p.advance(); // the '*'
                }
                const val_line = self.p.peek().line;
                var val = try self.p.parseExpr();
                // CONSTANTS ONLY (GH#81) — checked BEFORE the `$len` desugar below,
                // which would otherwise wrap the node in a call and hide what it was.
                // This also gives `array v[2] (1+1 2*3);` an honest diagnostic: the
                // `1+1` is rejected as an expression instead of the old confusing
                // arity error the `n*value` repeat rule produced downstream.
                if (try self.badInitValue(val)) |what|
                    return self.p.diags.fail(error.ParseError, val_line, "{s} is not a valid initial value for the array {s}; ARRAY initial values must be constants.", .{ what, name });
                // An explicit `$len` is authoritative: an init constant longer than
                // it is TRUNCATED (and a shorter one padded) to the declared length,
                // exactly like an assignment through the array (BUG-arraycharinitlen).
                // Without a `$len` the length is inferred from the constants — leave
                // them raw. Reuses the assignment desugar so init and assignment agree.
                if (is_char and char_len > 0) val = try self.truncate(val, char_len);
                var c: usize = 0;
                while (c < count) : (c += 1) try inits.append(self.p.arena, val);
            }
            _ = try self.p.expect(.rparen, "')' after array initial values");
        }

        // No explicit member list → SAS auto-generates `<name>1 … <name>N`, where N
        // is the declared dimension (or the initial-value count for `{*}`). Without
        // this the `array a{n} (inits)` form produced ZERO elements — silent
        // data-loss (BUG-arrayimplinit).
        if (elems.items.len == 0 and !temporary and special == null) {
            const need = if (dim > 0) dim else inits.items.len;
            var k: usize = 1;
            while (k <= need) : (k += 1)
                try elems.append(self.p.arena, try std.fmt.allocPrint(self.p.arena, "{s}{d}", .{ name, k }));
        }
        const elements = try elems.toOwnedSlice(self.p.arena);

        // a declared `$ len` truncates assignments to each member, like `length`.
        if (is_char and char_len > 0)
            for (elements) |e| try self.char_lens.append(self.p.arena, .{ .name = e, .len = char_len });

        _ = try self.p.expect(.semicolon, "';' after array");

        // an inferred (`*`) 1-D size is the resolved member count (dim/hbound = it).
        if (inferred and dims_list.items.len == 1) dims_list.items[0].size = elements.len;
        const dims = try dims_list.toOwnedSlice(self.p.arena);
        try self.p.arrays.append(self.p.arena, .{ .name = name, .elements = elements, .special = special, .dims = dims });
        const inits_ow = try inits.toOwnedSlice(self.p.arena);
        for (inits_ow, 0..) |_, k| {
            if (k >= elements.len) break;
            try self.explicit_init_vars.append(self.p.arena, elements[k]);
        }
        return .{ .array = .{ .name = name, .elements = elements, .inits = inits_ow, .temporary = temporary, .type = if (is_char) .char else .num, .special = special } };
    }

    fn parsePut(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // put
        var items: std.ArrayList(ast.PutItem) = .empty;
        var cur_line: usize = 1; // notional PUT line, for `#n` (GAP-putcolptr)
        while (!self.p.check(.semicolon) and !self.p.check(.eof)) {
            const t = self.p.peek();
            // OVERPRINT directive (overstrike the previous line) — a PUT keyword, not
            // a variable. Unsupported → fail loud like the sibling @(expr)/-C/@@
            // directives, rather than misreading it as an uninitialized var "overprint".
            if (t.tag == .name and eqi(t.text, "overprint"))
                return failGap(self.p.diags, t.line, "PUT OVERPRINT is not supported yet", .{});
            // BUG-hashattrput: a hash ATTRIBUTE reference (`put h.num_items …`) is
            // not PUT-item syntax — extend the statement/expression guard
            // (hashAttrAhead) here. Without it the `.` bound a bogus "." format
            // to `h` and the attribute became a SECOND item, printing
            // `. num_items=.` with two NOTE-only diagnostics (silent-wrong),
            // while `n = h.num_items;` in assignment position works.
            if (t.tag == .name and self.hashAttrAhead())
                return self.p.diags.fail(error.ParseError, t.line, "put: object attribute {s}.{s} is not valid here — read it into a variable first (n = {s}.{s};)", .{ t.text, self.tokAt(2).text, t.text, self.tokAt(2).text });
            // `+n` (relative column pointer) — move the pointer n columns right.
            // The buffer is append-only and forward, so "move right n" is exactly
            // "emit n spaces" and suppress the default inter-item space. Desugared
            // to a literal so exec needs no new item kind (GAP-putcolptr). ponytail:
            // integer literal only; `+(expr)` / negative moves fail loud.
            if (t.tag == .plus) {
                _ = self.p.advance(); // '+'
                // `+numeric-variable` / `+(expression)` are valid SAS 9.4 PUT
                // pointer controls (Statements Table 2.5) opensas doesn't
                // implement → gap (rc 2); anything else after `+` is not PUT
                // syntax → user error (rc 1). Same message either way (D-009).
                if (!self.p.check(.number)) {
                    if (self.p.check(.name) or self.p.check(.lparen))
                        return failGap(self.p.diags, t.line, "put: only an integer +n column pointer is supported", .{});
                    return self.p.diags.fail(error.ParseError, t.line, "put: only an integer +n column pointer is supported", .{});
                }
                const n = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 0;
                if (n > max_put_ptr)
                    return self.p.diags.fail(error.ParseError, t.line, "put: +{d} column pointer exceeds the {d} line-size ceiling", .{ n, max_put_ptr });
                const pad = try self.p.arena.alloc(u8, n);
                @memset(pad, ' ');
                try items.append(self.p.arena, .{ .literal = pad });
                continue;
            }
            // `#n` (line pointer) — move to line n. Forward-only in an append buffer:
            // emit (n - current) newlines. n == current is a no-op; n < current can't
            // rewind, so fail loud rather than silently misplace output (GAP-putcolptr).
            if (t.tag == .hash) {
                _ = self.p.advance(); // '#'
                // `#numeric-variable` / `#(expression)`: same split as `+`
                // above — valid SAS 9.4 (Table 2.5) → gap; else user error.
                if (!self.p.check(.number)) {
                    if (self.p.check(.name) or self.p.check(.lparen))
                        return failGap(self.p.diags, t.line, "put: only an integer #n line pointer is supported", .{});
                    return self.p.diags.fail(error.ParseError, t.line, "put: only an integer #n line pointer is supported", .{});
                }
                const n = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 0;
                if (n > max_put_ptr)
                    return self.p.diags.fail(error.ParseError, t.line, "put: #{d} line pointer exceeds the {d} line-size ceiling", .{ n, max_put_ptr });
                if (n < cur_line)
                    return self.p.diags.fail(error.ParseError, t.line, "put: #{d} cannot move to an earlier line (already on line {d})", .{ n, cur_line });
                while (cur_line < n) : (cur_line += 1) try items.append(self.p.arena, .newline);
                continue;
            }
            // `-R` / `-L` alignment modifier — right/left-justify the PRECEDING item's
            // formatted field within its width (GAP-putalign). Carried into exec by a
            // leading marker byte on the item's fmt ('>' right, '<' left); exec peels
            // it. ponytail: `-C` (center) is not supported → fail loud, not dropped.
            if (t.tag == .minus and self.tokAt(1).tag == .name) {
                const mod = self.tokAt(1).text;
                const marker: ?u8 = if (eqi(mod, "r")) '>' else if (eqi(mod, "l")) '<' else null;
                if (marker) |m| {
                    if (items.items.len == 0)
                        return self.p.diags.fail(error.ParseError, t.line, "put: -{s} alignment has no preceding value", .{mod});
                    _ = self.p.advance(); // '-'
                    _ = self.p.advance(); // R / L
                    if (!try attachAlign(self.p.arena, &items.items[items.items.len - 1], m))
                        return self.p.diags.fail(error.ParseError, t.line, "put: -{s} alignment must follow a value", .{mod});
                    continue;
                }
            }
            // `put x1-x3;` — a numbered variable-RANGE list expands to x1 x2 x3, the
            // SAME expander INPUT/KEEP/ARRAY/FORMAT route through (BUG-putvarrange).
            // Gated on a digit-suffixed endpoint so the `-R`/`-L` alignment modifier
            // (handled above) and any non-numbered `name`-`name` never divert here.
            // ponytail: expands to plain variables (no shared trailing format); a
            // `put x1-x3 8.2;` per-range format is the upgrade path if ever needed.
            if (t.tag == .name and self.tokAt(1).tag == .minus and
                self.tokAt(2).tag == .name and splitNumSuffix(self.tokAt(2).text).digits != 0)
            {
                _ = self.p.advance(); // first name
                _ = self.p.advance(); // '-'
                const last = self.p.advance(); // last name
                var names: std.ArrayList([]const u8) = .empty;
                try expandRange(self.p.arena, &names, t.text, last.text);
                for (names.items) |nm| try items.append(self.p.arena, .{ .variable = .{ .name = nm, .fmt = null } });
                continue;
            }
            // `put (varlist)(format-list);` — grouped format list. The format-list
            // is a CYCLIC stream of pointer-controls (+n/@n: emitted, non-consuming)
            // and format specs (each consumes ONE variable; `=` = named output).
            // Expanded here into individual PUT items so runPut needs no new render
            // path (NOTE-putgroupfmt). The varlist reuses expandRange for numbered
            // ranges, exactly like the sibling `put x1-x3` branch above. ponytail:
            // a pointer emits just before the format that consumes a var; a
            // format-list of pointers only (no consuming spec) fails loud, since it
            // would never advance a variable.
            if (t.tag == .lparen) {
                _ = self.p.advance(); // '(' of the variable group
                var names: std.ArrayList([]const u8) = .empty;
                while (self.p.check(.name)) {
                    const nm = self.p.advance().text;
                    if (self.p.check(.minus) and self.peekNext().tag == .name) {
                        _ = self.p.advance(); // '-'
                        try expandRange(self.p.arena, &names, nm, self.p.advance().text);
                    } else try names.append(self.p.arena, nm);
                }
                _ = try self.p.expect(.rparen, "')' after PUT group variable list");
                if (names.items.len == 0)
                    return self.p.diags.fail(error.ParseError, t.line, "put: empty () variable group", .{});
                if (!self.p.eat(.lparen))
                    return self.p.diags.fail(error.ParseError, t.line, "put: '(variable-list)' must be followed by a '(format-list)' group", .{});
                const GElem = union(enum) {
                    literal: []const u8,
                    col: usize,
                    fmt: struct { named: bool, spec: ?[]const u8 },
                };
                var elems: std.ArrayList(GElem) = .empty;
                var has_fmt = false;
                while (!self.p.check(.rparen) and !self.p.check(.eof)) {
                    const g = self.p.peek();
                    if (g.tag == .plus) {
                        _ = self.p.advance(); // '+'
                        // group format-list `+var`/`+(expr)`: same split as the
                        // top-level `+` guard — valid SAS 9.4 (Table 2.5, and
                        // p.293 allows pointer controls in a format-list) → gap.
                        if (!self.p.check(.number)) {
                            if (self.p.check(.name) or self.p.check(.lparen))
                                return failGap(self.p.diags, g.line, "put: only an integer +n column pointer is supported", .{});
                            return self.p.diags.fail(error.ParseError, g.line, "put: only an integer +n column pointer is supported", .{});
                        }
                        const n = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 0;
                        if (n > max_put_ptr)
                            return self.p.diags.fail(error.ParseError, g.line, "put: +{d} column pointer exceeds the {d} line-size ceiling", .{ n, max_put_ptr });
                        const pad = try self.p.arena.alloc(u8, n);
                        @memset(pad, ' ');
                        try elems.append(self.p.arena, .{ .literal = pad });
                    } else if (g.tag == .at) {
                        _ = self.p.advance(); // '@'
                        // group format-list `@var`/`@(expr)`: same split as `+`.
                        if (!self.p.check(.number)) {
                            if (self.p.check(.name) or self.p.check(.lparen))
                                return failGap(self.p.diags, g.line, "put: only an integer @n column pointer is supported", .{});
                            return self.p.diags.fail(error.ParseError, g.line, "put: only an integer @n column pointer is supported", .{});
                        }
                        const n = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 0;
                        if (n > max_put_ptr)
                            return self.p.diags.fail(error.ParseError, g.line, "put: @{d} column pointer exceeds the {d} line-size ceiling", .{ n, max_put_ptr });
                        try elems.append(self.p.arena, .{ .col = n });
                    } else if (g.tag == .eq) {
                        _ = self.p.advance(); // '=' → named output, optional following format
                        try elems.append(self.p.arena, .{ .fmt = .{ .named = true, .spec = try self.tryFormatSpec() } });
                        has_fmt = true;
                    } else if (try self.tryFormatSpec()) |spec| {
                        try elems.append(self.p.arena, .{ .fmt = .{ .named = false, .spec = spec } });
                        has_fmt = true;
                    } else return self.p.diags.fail(error.ParseError, g.line, "put: unexpected item in group format-list", .{});
                }
                _ = try self.p.expect(.rparen, "')' after PUT group format list");
                if (!has_fmt)
                    return self.p.diags.fail(error.ParseError, t.line, "put: group format-list has no format for the variables", .{});
                var cur: usize = 0;
                for (names.items) |nm| while (true) {
                    const e = elems.items[cur];
                    cur = (cur + 1) % elems.items.len;
                    switch (e) {
                        .literal => |s| try items.append(self.p.arena, .{ .literal = s }),
                        .col => |n| try items.append(self.p.arena, .{ .col = n }),
                        .fmt => |f| {
                            try items.append(self.p.arena, if (f.named)
                                .{ .named = .{ .name = nm, .fmt = f.spec } }
                            else
                                .{ .variable = .{ .name = nm, .fmt = f.spec } });
                            break;
                        },
                    }
                };
                continue;
            }
            const item: ast.PutItem = switch (t.tag) {
                .string => blk: {
                    _ = self.p.advance();
                    break :blk .{ .literal = t.text };
                },
                .slash => blk: {
                    _ = self.p.advance();
                    cur_line += 1;
                    break :blk .newline;
                },
                // `@n` / `@(expression)` column pointer — position the output column
                // before the next item. ponytail: a trailing `@`/`@@` output-line hold
                // and `@'string'` still fail loud (no silent drop).
                .at => blk: {
                    _ = self.p.advance(); // '@'
                    // GAP-atexpression-put: `@(expression)` (Statements printed p.269),
                    // the PUT twin of INPUT's p.168 form landed in GAP-atexpression. The
                    // AST rides the item; exec evaluates it per PUT and clamps through
                    // io.clampCol, so all four `@` pointer forms share ONE clamp.
                    if (self.p.check(.lparen)) {
                        _ = self.p.advance(); // '('
                        const e = try self.p.parseExpr();
                        _ = try self.p.expect(.rparen, "')' after @(expression");
                        break :blk .{ .col_expr = e };
                    }
                    // `@numeric-variable` and the trailing-`@` output line hold
                    // are valid SAS 9.4 (Statements Table 2.5; the `@@` sibling
                    // below is already failGap) → gap, rc 2. `@'string'` string
                    // search is INPUT-only (Table 2.3), not PUT syntax → user
                    // error, rc 1 — same decision GAP-atexpression-put made for
                    // `@(character-expression)`. Same message either way (D-009).
                    if (!self.p.check(.number)) {
                        if (self.p.check(.name) or self.p.check(.semicolon))
                            return failGap(self.p.diags, t.line, "put: only an integer @n or @(expression) column pointer is supported — no trailing-@ line hold or @'string' search", .{});
                        return self.p.diags.fail(error.ParseError, t.line, "put: only an integer @n or @(expression) column pointer is supported — no trailing-@ line hold or @'string' search", .{});
                    }
                    const n = std.fmt.parseInt(usize, self.p.advance().text, 10) catch 0;
                    if (n > max_put_ptr)
                        return self.p.diags.fail(error.ParseError, t.line, "put: @{d} column pointer exceeds the {d} line-size ceiling", .{ n, max_put_ptr });
                    break :blk .{ .col = n };
                },
                // `x=` named output (prints "x=<value>"), else a variable with an
                // optional format: `put x 8.2`
                .name => blk: {
                    _ = self.p.advance();
                    // array element ref `a[i]` / whole array `a[*]` — brackets/braces
                    // both lex as lbrace (BUG-putarrayref).
                    if (self.p.check(.lbrace)) if (self.p.lookupArray(t.text)) |def| {
                        // `a{*}` — the whole array (null index). Peek past `{` for the star.
                        if (self.p.pos + 1 < self.p.toks.len and self.p.toks[self.p.pos + 1].tag == .star) {
                            _ = self.p.advance(); // '[' / '{'
                            _ = self.p.advance(); // '*'
                            _ = try self.p.expect(.rbrace, "']' / '}}' after array subscript");
                            break :blk .{ .array_elem = .{ .name = t.text, .elements = def.elements, .index = null, .special = def.special } };
                        }
                        // `a{i}` / `a{i,j}` — fold to a flat index (GAP-multidimarray).
                        const r = try self.p.parseArraySubscript(t);
                        // `put a[i]=;` — named output: a trailing `=` marks it, same
                        // as a plain `x=` item (FEAT-putarraynamed). `a[*]=` is not
                        // consumed → stays fail-loud like any stray `=`.
                        const named = self.p.eat(.eq);
                        break :blk .{ .array_elem = .{ .name = t.text, .elements = r.def.elements, .index = r.index, .special = r.def.special, .named = named } };
                    };
                    // NAMED output (`put x= fmt.`) takes NO modifier: the "PUT
                    // Statement: Named" entry's syntax is `variable=<format.>`
                    // with no `:`/`~` slot (Statements ref printed p.302), so a
                    // colon after `x=` stays the rc-1 catch-all below.
                    if (self.p.eat(.eq)) break :blk .{ .named = .{ .name = t.text, .fmt = try self.tryFormatSpec() } };
                    break :blk .{ .variable = .{ .name = t.text, .fmt = try self.tryModifiedList(t) } };
                },
                // A bare NUMERIC literal is a value operand — SAS formats/writes it
                // (`put 42 best8.;` → "      42", `put 3.14 5.2;` → " 3.14"). The value
                // is constant, so fold it here through the SAME format engine exec uses
                // for `put x fmt.`, emitting a plain literal — output is byte-identical
                // and needs no new PutItem/exec kind (GAP-putnumliteral). ponytail: the
                // trailing-format detection reuses tryFormatSpec (shared with the
                // variable case), so a rare `put 1 2 3;` reads "2"/"3" as formats — same
                // ceiling the variable operand already has.
                .number => blk: {
                    const x = std.fmt.parseFloat(f64, t.text) catch
                        return self.p.diags.fail(error.ParseError, t.line, "put: invalid numeric literal {s}", .{t.text});
                    _ = self.p.advance();
                    const s = if (try self.tryFormatSpec()) |f|
                        try format.apply(self.p.arena, Value{ .num = x }, f)
                    else
                        try format.bestNum(self.p.arena, x);
                    break :blk .{ .literal = s };
                },
                // GAP-puthold: trailing `@@` line hold named explicitly.
                .atat => return failGap(self.p.diags, t.line, "put: trailing @@ (output line hold across iterations) is not supported", .{}),
                else => return self.p.diags.fail(error.ParseError, t.line, "unexpected item in put statement", .{}),
            };
            try items.append(self.p.arena, item);
        }
        _ = try self.p.expect(.semicolon, "';' after put");
        return .{ .put = try items.toOwnedSlice(self.p.arena) };
    }

    /// `format v1 v2 fmt1 v3 fmt2 …;` — a format applies to every variable named
    /// since the previous one. `informat` shares this shape.
    fn parseFormatList(self: *Parser, comptime kw: []const u8) Error![]const ast.FormatItem {
        _ = self.p.advance(); // keyword
        var items: std.ArrayList(ast.FormatItem) = .empty;
        var pending: std.ArrayList([]const u8) = .empty; // vars awaiting a format
        while (!self.p.check(.semicolon) and !self.p.check(.eof)) {
            if (try self.tryFormatSpec()) |fmt| {
                for (pending.items) |name| try items.append(self.p.arena, .{ .name = name, .fmt = fmt });
                pending.clearRetainingCapacity();
            } else if (self.p.check(.name)) {
                const name = self.p.advance().text;
                // numbered range `d1-d3` (GAP-formatvarrange) — the same
                // expander KEEP/ARRAY/RETAIN route through.
                if (self.p.check(.minus) and self.peekNext().tag == .name) {
                    _ = self.p.advance(); // '-'
                    try expandRange(self.p.arena, &pending, name, self.p.advance().text);
                } else {
                    try pending.append(self.p.arena, name);
                }
            } else {
                const t = self.p.peek();
                return self.p.diags.fail(error.ParseError, t.line, "unexpected token in " ++ kw ++ " statement", .{});
            }
        }
        // Names still pending at `;` got NO format spec — SAS's removal form:
        // `format x;` CLEARS x's format (reverts to default), not a no-op
        // (BUG-formatremoval — these used to be dropped, keeping the old
        // format). Emitted through the existing FormatItem plumbing:
        //   FORMAT   → "$.": renders the default for BOTH types via the
        //              unmodified format engine (char verbatim; num → valToStr
        //              → bestNum, the same BEST12. the no-format path uses).
        //   INFORMAT → "":  scan's \x01-wrap yields a len-1 attr, which
        //              patchInformats skips (len > 1 required), so a later
        //              bare `input x;` reads default; applyAttrs blanks the
        //              var's stored informat.
        // ponytail: parser-only (task owns parser.zig) — exec's null-format
        // path is unreachable from the AST, so x's format metadata reads "$.",
        // not a true none (CONTENTS/VFORMAT show it); a clear as a var's FIRST
        // mention guesses char; a same-step informat assign still wins
        // patchInformats' first-match. Plumb a clear sentinel in exec if a
        // golden ever needs exact metadata.
        for (pending.items) |name|
            try items.append(self.p.arena, .{ .name = name, .fmt = if (comptime std.mem.eql(u8, kw, "format")) "$." else "" });
        _ = try self.p.expect(.semicolon, "';' after " ++ kw);
        return items.toOwnedSlice(self.p.arena);
    }

    /// If the tokens at the cursor spell a format spec, consume them and return
    /// the reconstructed spec string; otherwise consume nothing and return null.
    /// Specs tokenize unevenly — `8.2` is one number, `comma10.2` is name+".2",
    /// `date9.` is name+dot — so we stitch the pieces back into a string.
    /// A PUT item's trailing format, allowing the `:` MODIFIED LIST OUTPUT
    /// modifier in front of it (GAP-putcolonformat).
    ///
    /// SAS 9.4 DATA Step Statements ref, "PUT Statement: List". Printed p.297
    /// gives the syntax slot — `PUT <pointer-control> variable < : | ~> format.
    /// <@ | @@>;` — and printed p.298 (pdf 309; that page's own footer reads
    /// "298 Chapter 2 / Dictionary of SAS DATA Step Statements") defines it:
    ///
    ///   :  enables you to specify a format that the PUT statement uses to write
    ///      the variable value. All leading and trailing blanks are deleted, and
    ///      each value is followed by a single blank.
    ///
    /// This is NOT the INPUT statement's colon, and the two must not be
    /// conflated: INPUT's (printed p.193) governs WHERE READING STOPS ("reads
    /// the value from the next non-blank column until the pointer reaches the
    /// next blank column…"), PUT's governs blank-stripping on OUTPUT. The
    /// volumes never cross-reference them — each `:` entry only "See"s its own
    /// side's details section — so the parallel is structural, not semantic.
    ///
    /// Carried into exec as a ':' MARKER BYTE on the format string, the same
    /// convention `-R`/`-L` already uses ('>'/'<', attachAlign + exec.peelAlign).
    /// attachAlign PREPENDS, so an aligned modified-list item reads ">:fmt" and
    /// exec peels align first, then the colon — no new AST field, no new item
    /// kind. `~` is the modifier's only documented sibling (p.298 — quotes the
    /// value, requires the DSD option in the FILE statement). Its DSD quoting
    /// lives in exec.zig, so it is NOT implemented here — but the lexer keeps
    /// the source byte on .caret's `text`, so the parser names it as its own
    /// GAP arm (rc 2) instead of letting it fall into the typo catch-all. A
    /// `^` in the same slot IS a typo and keeps rc 1 (GAP-puttildemodifier).
    fn tryModifiedList(self: *Parser, t: Token) Error!?[]const u8 {
        if (self.p.check(.caret) and std.mem.eql(u8, self.p.peek().text, "~"))
            return failGap(self.p.diags, t.line, "put: the '~' modifier (DSD-quoted modified list output) is not supported", .{});
        if (!self.p.eat(.colon)) return self.tryFormatSpec();
        // p.297's syntax slot is `< : | ~> format.` — the format is not optional
        // after the modifier, so a bare `put x : ;` is a user error (rc 1), not a
        // silently-dropped modifier.
        const spec = try self.tryFormatSpec() orelse
            return self.p.diags.fail(error.ParseError, t.line, "put: the ':' modifier requires a format (put {s} : fmt.;)", .{t.text});
        const buf = try self.p.arena.alloc(u8, spec.len + 1);
        buf[0] = ':';
        @memcpy(buf[1..], spec);
        return buf;
    }

    fn tryFormatSpec(self: *Parser) Error!?[]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        const a = self.p.arena;

        if (self.p.check(.dollar)) {
            _ = self.p.advance();
            try buf.append(a, '$');
        }
        if (self.p.check(.name)) {
            // a name belongs to a format only when a dot / dotted-number follows
            // it (a plain name is the next variable, not a format).
            const nx = self.peekNext();
            const name_is_fmt = nx.tag == .dot or (nx.tag == .number and startsWithDot(nx.text));
            if (buf.items.len > 0 or name_is_fmt) {
                try buf.appendSlice(a, self.p.advance().text);
            } else if (buf.items.len == 0) {
                return null; // bare name → not a format
            }
        }
        if (self.p.check(.number)) try buf.appendSlice(a, self.p.advance().text);
        if (self.p.check(.dot)) {
            _ = self.p.advance();
            try buf.append(a, '.');
        }
        return if (buf.items.len == 0) null else buf.items;
    }

    fn peekNext(self: *Parser) Token {
        const j = self.p.pos + 1;
        return if (j < self.p.toks.len) self.p.toks[j] else self.p.toks[self.p.toks.len - 1];
    }

    /// A one-character NAME token spelling a special-missing letter (`A`-`Z`/`_`) —
    /// the tail of a `.A` split by the lexer into `.` + name (BUG-retaininitspecialmiss).
    fn isMissLetter(tk: Token) bool {
        return tk.tag == .name and tk.text.len == 1 and
            (std.ascii.isAlphabetic(tk.text[0]) or tk.text[0] == '_');
    }

    /// An ARRAY / RETAIN parenthesised initial-value list takes CONSTANTS ONLY.
    /// SAS 9.4 DATA Step Statements printed p.24: "(initial-value-list) gives
    /// initial values for the corresponding elements in the array. The values for
    /// elements can be numbers or character strings." The disambiguating example is
    /// printed p.26 Ex.3 — `array test2{*} $ a1 a2 a3 ('a','b','c');` puts the
    /// variable NAMES outside the parentheses and the constants inside.
    ///
    /// Both lists used to call `parseExpr` and accept whatever came back, so
    /// `array v[2](a1 a2);` silently declared phantom `v1`/`v2` seeded from an
    /// unevaluatable variable read (missing) and left `a1`/`a2` untouched — stderr
    /// empty, rc 0 (GH#81). Same hole in `retain x (a);`. Returns null when `e` is
    /// a legal constant, else the phrase naming what it actually is, for the
    /// diagnostic. A signed literal (`-1`) folds to a constant, so `.neg` rides.
    fn badInitValue(self: *Parser, e: *const ast.Expr) Error!?[]const u8 {
        return switch (e.*) {
            .num, .str, .missing => null,
            .unary => |u| if (u.op == .neg) self.badInitValue(u.operand) else "An expression",
            .variable => |v| try std.fmt.allocPrint(self.p.arena, "The variable {s}", .{v}),
            .array_ref => |r| try std.fmt.allocPrint(self.p.arena, "The array reference {s}", .{r.name}),
            .call => |c| try std.fmt.allocPrint(self.p.arena, "The function call {s}()", .{c.name}),
            .binary => "An expression",
        };
    }

    fn parseDatalines(self: *Parser) Error!ast.Stmt {
        _ = self.p.advance(); // datalines / cards / lines
        _ = try self.p.expect(.semicolon, "';' after datalines");
        var lines: std.ArrayList([]const u8) = .empty;
        while (self.p.check(.data_line)) try lines.append(self.p.arena, self.p.advance().text);
        _ = try self.p.expect(.semicolon, "';' terminating datalines");
        return .{ .datalines = try lines.toOwnedSlice(self.p.arena) };
    }

    // ── shared bits ─────────────────────────────────────────────────────────

    /// Consume a leading keyword, then bare names until `;`. Serves output,
    /// drop and keep (all "keyword name* ;"). With `vars` set (drop/keep — the
    /// entries name PDV variables, not datasets) two list shorthands apply:
    /// a name-prefix colon wildcard `pfx:` is kept as a single "pfx:" entry
    /// that exec's nameIn prefix-matches against the PDV (GAP-dropcolon), and
    /// a numbered range `a1-a3` expands via expandRange — the same helper the
    /// keep=/drop= dataset-option side uses (STMT-ranges, bd905b6).
    fn parseNameList(self: *Parser, comptime kw: []const u8, comptime vars: bool) Error![]const []const u8 {
        _ = self.p.advance(); // keyword
        var names: std.ArrayList([]const u8) = .empty;
        while (self.p.check(.name)) {
            const name = self.p.advance().text;
            if (vars and self.p.eat(.colon)) {
                try names.append(self.p.arena, try std.fmt.allocPrint(self.p.arena, "{s}:", .{name}));
            } else if (vars and self.p.eat(.minus)) {
                const last = try self.p.expect(.name, "name after '-' in " ++ kw ++ " range");
                try expandRange(self.p.arena, &names, name, last.text);
            } else {
                try names.append(self.p.arena, name);
            }
        }
        _ = try self.p.expect(.semicolon, "';' after " ++ kw);
        return names.toOwnedSlice(self.p.arena);
    }

    /// DATA-step `BY [descending] var { [descending] var } [notsorted] ;`.
    /// The list itself is scanned by scanByList — the SAME scanner the
    /// PROC-statement BY routes through (GAP-procbydescending) — so the two
    /// contexts can never disagree about DESCENDING/NOTSORTED again.
    fn parseBy(self: *Parser) Error![]const []const u8 {
        _ = self.p.advance(); // by
        const names = try scanByList(self.p.arena, self.p.diags, self.p.toks, &self.p.pos);
        _ = try self.p.expect(.semicolon, "';' after by");
        return names;
    }

    /// The ONE BY-list scanner (GAP-procbydescending): DATA-step `by` (parseBy
    /// above) and PROC-statement BY (proc.parseProcBy) both call here, sharing
    /// one wire encoding so no third parser can drift. SAS 9.4 Statements ref
    /// p.39-43: `BY <DESCENDING> variable-1 <…<DESCENDING> variable-n>
    /// <NOTSORTED> <GROUPFORMAT>;` — DESCENDING is PER-VARIABLE (applies to the
    /// variable immediately after it, Example 2 p.43), NOTSORTED is
    /// statement-wide (drops the sorted-input requirement — groups then form
    /// on CONSECUTIVE equal values, p.41). Leaves the cursor ON the
    /// list-terminating token; the caller consumes its `;`.
    /// The AST keeps `.by` a plain name list, so the modifiers ride as
    /// sentinels (the end=/point= pattern): a descending var is prefixed
    /// `"\x00D"`, and NOTSORTED appends a `"\x00notsorted"` entry;
    /// exec.decodeBy (DATA step) and proc.decodeProcBy (PROCs) split them back
    /// out (GAP-batch-qa107).
    /// GROUPFORMAT (group on FORMATTED values) still fails loud
    /// (GAP-bygroupformat): exec groups on raw values, so accepting it would
    /// silently draw wrong BY-group boundaries whenever a format collapses
    /// distinct raw values. (It is DATA-step-only syntax anyway — Statements
    /// ref p.40 restriction — so the PROC path must never accept it either.)
    pub fn scanByList(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, i: *usize) Error![]const []const u8 {
        var names: std.ArrayList([]const u8) = .empty;
        var descending = false;
        var notsorted = false;
        while (i.* < toks.len and toks[i.*].tag == .name) {
            const t = toks[i.*];
            i.* += 1;
            if (eqi(t.text, "descending")) {
                descending = true;
                continue;
            }
            if (eqi(t.text, "notsorted")) {
                notsorted = true;
                continue;
            }
            // a keyword, not a variable — else it becomes a phantom BY var
            if (eqi(t.text, "groupformat"))
                return failGap(diags, t.line, "BY GROUPFORMAT is not yet supported (formatted-value BY grouping)", .{});
            if (descending) {
                try names.append(arena, try std.fmt.allocPrint(arena, "\x00D{s}", .{t.text}));
                descending = false;
            } else {
                try names.append(arena, t.text);
            }
        }
        if (descending)
            return diags.fail(error.ParseError, if (i.* < toks.len) toks[i.*].line else 0, "BY DESCENDING must be followed by a variable name", .{});
        // `by;` / `by notsorted;` — zero variables. sas9.4.ebnf by_stmt requires
        // >= 1 var, so this is a USER error (rc 1, D-009b), never a silent no-op
        // of the whole BY mechanism (BUG-bystmtempty). A macro spelling
        // (`by &bv;` with an empty &bv) lands here too: expansion is textual
        // before lex/parse (D-004), so the parser sees `by ;` either way.
        if (names.items.len == 0)
            return diags.fail(error.ParseError, if (i.* < toks.len) toks[i.*].line else 0, "BY statement requires at least one variable", .{});
        if (notsorted) try names.append(arena, "\x00notsorted");
        return names.toOwnedSlice(arena);
    }

    /// `set`/`merge` source list, where each source may carry input dataset
    /// options: `src(keep=… drop=… rename=(…) where=(…) in=x)`. The AST holds only
    /// dataset names, so the options ride along inside the name string —
    /// `"src(keep=a b)"` — and the executor splits + applies them at read time.
    fn parseDatasetRefs(self: *Parser, comptime kw: []const u8) Error![]const []const u8 {
        _ = self.p.advance(); // keyword
        self.has_set = true; // set/merge read rows via io.loadRow, which sets `_setobs_`
        var names: std.ArrayList([]const u8) = .empty;
        while (self.p.check(.name)) {
            var base = self.p.advance().text;
            // statement option `opt = var` (nobs=/end=/point=) — NOT a dataset name
            if (self.p.check(.eq)) {
                _ = self.p.advance(); // '='
                const optvar = if (self.p.check(.name)) self.p.advance().text else "";
                // nobs=v: io.loadRow exposes the source's obs count in `_setobs_`;
                // desugar `nobs=v` to `v = _setobs_` (injected right after the set).
                if (optvar.len > 0 and std.ascii.eqlIgnoreCase(base, "nobs")) {
                    const rhs = try self.p.arena.create(ast.Expr);
                    rhs.* = .{ .variable = "_setobs_" };
                    try self.pending.append(self.p.arena, .{ .assign = .{ .target = optvar, .value = rhs } });
                } else if (optvar.len > 0 and
                    (std.ascii.eqlIgnoreCase(base, "end") or std.ascii.eqlIgnoreCase(base, "point")))
                {
                    // Pass end=/point= to exec as a NUL-sentinel entry in the name list
                    // (BUG-setend / BUG-setpoint) — exec pulls these out before resolving
                    // datasets. Keeps the `.set` AST a plain name list (ast.zig untouched).
                    try names.append(self.p.arena, try std.fmt.allocPrint(self.p.arena, "\x00{s}={s}", .{ base, optvar }));
                } else if (optvar.len > 0 and std.mem.eql(u8, kw, "update") and
                    std.ascii.eqlIgnoreCase(base, "updatemode"))
                {
                    // GAP-updatemode: UPDATEMODE=MISSINGCHECK (default — a missing
                    // transaction value keeps the master) | NOMISSINGCHECK (missing
                    // overwrites). Rides to exec as a NUL-sentinel like end=/point=
                    // (the AST stays a plain name list); only NOMISSINGCHECK needs
                    // carrying. Any other value fails loud.
                    if (std.ascii.eqlIgnoreCase(optvar, "nomissingcheck"))
                        try names.append(self.p.arena, "\x00updatemode=nomissingcheck")
                    else if (!std.ascii.eqlIgnoreCase(optvar, "missingcheck"))
                        return self.p.diags.fail(error.ParseError, self.p.peek().line, "UPDATEMODE= must be MISSINGCHECK or NOMISSINGCHECK", .{});
                } else if (optvar.len > 0 and std.ascii.eqlIgnoreCase(base, "key") and
                    (std.mem.eql(u8, kw, "modify") or std.mem.eql(u8, kw, "set")))
                {
                    // GAP-modifykey: KEY= is keyed/indexed direct access (SET and
                    // MODIFY). opensas has no dataset-index layer at all (no INDEX=/
                    // INDEX CREATE, no key→row map, no _IORC_) and building one is
                    // out of scope — so fail loud with a clear indexed-access
                    // diagnostic, never the generic unknown-option arm (and never a
                    // silent sequential read).
                    return failGap(self.p.diags, self.p.peek().line, "{s} KEY= (indexed access) is not supported yet", .{kw});
                } else
                    // Any other `name=var` statement option (CUROBS=, …) would be
                    // silently DROPPED here (BUG-setunknownopt) — `set m curobs=c;`
                    // then reads sequentially instead of a keyed lookup → plausible-but-wrong
                    // output at rc=0. Fail loud; keyed execution is a separate exec.zig
                    // feature. (A missing var, `nobs=;`, lands here too — also an error.)
                    return self.p.diags.fail(error.ParseError, self.p.peek().line, kw ++ " option {s}= is not supported", .{base});
                continue;
            }
            // Two-level `libref.member` name. coalesceLibrefs (main.zig) folds a
            // DECLARED libref into one token before we get here; an UNDECLARED one
            // stays three tokens (`name . name`), so fold it here too. An unknown
            // libref then resolves to nothing at read time → warn-and-skip (like a
            // declared-but-empty lib), not a ParseError (PARSE-twolevelset).
            if (self.p.check(.dot) and self.tokAt(1).tag == .name) {
                _ = self.p.advance(); // '.'
                const member = self.p.advance().text;
                base = try std.fmt.allocPrint(self.p.arena, "{s}.{s}", .{ base, member });
            }
            // Prefix-wildcard list `name:` — all members of the active library whose
            // names start with `name` (ISS-setdslist). The parser can't enumerate the
            // library, so emit a `\x00prefix=…` sentinel that exec expands at read time
            // (like the end=/point= sentinels).
            if (self.p.check(.colon)) {
                _ = self.p.advance(); // ':'
                try names.append(self.p.arena, try std.fmt.allocPrint(self.p.arena, "\x00prefix={s}", .{base}));
                continue;
            }
            // Numbered-range list `name1 - nameN` — the inclusive sequence sharing the
            // same non-numeric prefix (ISS-setdslist), reusing the var-list range
            // expander. Purely syntactic. ponytail: one-level endpoints only; a
            // `lib.a1-lib.a5` libref range would need the dot folded on the high
            // endpoint too — add when the corpus hits it.
            if (self.p.check(.minus) and self.tokAt(1).tag == .name) {
                _ = self.p.advance(); // '-'
                const hi = self.p.advance().text;
                try expandRange(self.p.arena, &names, base, hi);
                continue;
            }
            const name = if (self.p.check(.lparen))
                try std.fmt.allocPrint(self.p.arena, "{s}{s}", .{ base, try self.serializeParens() })
            else
                base;
            try names.append(self.p.arena, name);
        }
        _ = try self.p.expect(.semicolon, "';' after " ++ kw);
        return names.toOwnedSlice(self.p.arena);
    }

    /// Consume a balanced `( … )` (cursor on the `(`) and re-serialize its tokens
    /// to a space-separated, re-lexable string — so the executor can tokenize the
    /// options back out of the encoded dataset name.
    fn serializeParens(self: *Parser) Error![]const u8 {
        _ = self.p.advance(); // '('
        var buf: std.ArrayList(u8) = .empty;
        try buf.append(self.p.arena, '(');
        var depth: usize = 1;
        while (!self.p.check(.eof)) {
            const t = self.p.advance();
            if (t.tag == .lparen) {
                depth += 1;
            } else if (t.tag == .rparen) {
                depth -= 1;
                if (depth == 0) break;
            }
            if (t.tag == .string) {
                // Re-quote a string literal so it survives re-lexing as a string,
                // not a bare name — a char `where=(v in ("A","B"))` option would
                // otherwise lose its values (BUG-datawhere-char). ponytail: no
                // escaping of an embedded quote (rare in a dataset-option string).
                try buf.append(self.p.arena, '"');
                try buf.appendSlice(self.p.arena, t.text);
                try buf.append(self.p.arena, '"');
            } else try buf.appendSlice(self.p.arena, tokenText(t) orelse
                return self.p.diags.fail(error.ParseError, t.line, "unsupported token in dataset options", .{}));
            try buf.append(self.p.arena, ' ');
        }
        try buf.append(self.p.arena, ')');
        return buf.items;
    }

    /// A while/until guard condition. Hash calls hoisted out of it
    /// (GAP-hashinexpr) must RE-RUN every iteration, so they are moved to
    /// `loop_hoists` (woven into the loop body by parseDo), not left for the
    /// statement-level drain, which would run them once before the loop.
    fn parseGuardExpr(self: *Parser, loop_hoists: *std.ArrayList(ast.Stmt)) Error!*const ast.Expr {
        const mark = self.p.hash_hoists.items.len;
        const cond = try self.parseParenExpr();
        for (self.p.hash_hoists.items[mark..]) |hc|
            try loop_hoists.append(self.p.arena, .{ .hash_op = hc });
        self.p.hash_hoists.shrinkRetainingCapacity(mark);
        return cond;
    }

    fn parseParenExpr(self: *Parser) Error!*const ast.Expr {
        _ = try self.p.expect(.lparen, "'('");
        const e = try self.p.parseExpr();
        _ = try self.p.expect(.rparen, "')'");
        return e;
    }

    fn mkStmt(self: *Parser, s: ast.Stmt) Error!*const ast.Stmt {
        const node = try self.p.arena.create(ast.Stmt);
        node.* = s;
        return node;
    }

    fn atKw(self: *Parser, kw: []const u8) bool {
        const t = self.p.peek();
        return t.tag == .name and std.ascii.eqlIgnoreCase(t.text, kw);
    }

    /// At a global statement keyword the top level HANDLES mid-step
    /// (D-014a, parser.isMidStepSkippable — BUG-filenamemidstep): hoisted
    /// globals (TITLE[n]/FOOTNOTE[n]/OPTIONS/FILENAME/ODS) EXECUTE via
    /// main.segments before the step, LIBNAME via the parseLibnames
    /// pre-pass, so skipping the leftover tokens here is honest. This used
    /// to claim isGlobalKw, wider by exactly {filename, ods}: nothing
    /// executed those mid-step, so a mid-DATA-step `filename f 'new';`
    /// silently re-bound NOTHING and `file f;` kept writing to the OLD
    /// path at exit 0 (QA tick336 F1, silent wrong data). The x command
    /// form IS handled (parseStmt).
    /// NOTE-pagemidstep (QA tick322 F6): the batch-unobservable inert set
    /// (isInertGlobalKw — PAGE/SKIP Language Reference: Concepts p.209, GOPTIONS/DM/SASFILE/…) is
    /// accepted in open code and mid-PROC, so agree here too (D-014a):
    /// pre-fix a mid-DATA-step `page;` fell through to parseAssign and died
    /// with the misleading "expected '=' in assignment", naming the wrong
    /// construct. POSITIVE-match guard: the inert statement's second token
    /// is only ever `;` (page;), a name (goptions reset=all), a string
    /// (dm 'cmd') or a number (skip 3) — anything else is a real DATA-step
    /// construct that owns the keyword as an identifier: `page = 5;`
    /// assignment, `skip:` a GOTO label (ctl_goto), `h.remove()` a call.
    fn atGlobalStmt(self: *Parser) bool {
        const t = self.p.peek();
        if (t.tag != .name) return false;
        if (isInertGlobalKw(t.text)) {
            return switch (self.tokAt(1).tag) {
                .semicolon, .name, .string, .number => true,
                else => false,
            };
        }
        return isMidStepSkippable(t.text);
    }

    fn eatKw(self: *Parser, kw: []const u8) bool {
        if (self.atKw(kw)) {
            _ = self.p.advance();
            return true;
        }
        return false;
    }

    fn expectKw(self: *Parser, comptime kw: []const u8) Error!void {
        if (self.eatKw(kw)) return;
        return self.p.diags.fail(error.ParseError, self.p.peek().line, "expected '" ++ kw ++ "'", .{});
    }
};

fn startsWithDot(s: []const u8) bool {
    return s.len > 0 and s[0] == '.';
}

fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

/// Prepend a PUT alignment marker byte ('>' right / '<' left) onto a put item's
/// format so exec can justify the field within its width (GAP-putalign). Only
/// value-bearing items (`variable`/`named`) carry a format; alignment on anything
/// else (a literal, `/`, `@n`) has no field to justify → false (caller fails loud).
fn attachAlign(arena: std.mem.Allocator, item: *ast.PutItem, marker: u8) Error!bool {
    const slot: *?[]const u8 = switch (item.*) {
        .variable => |*v| &v.fmt,
        .named => |*n| &n.fmt,
        else => return false,
    };
    const old = slot.* orelse "";
    const buf = try arena.alloc(u8, old.len + 1);
    buf[0] = marker;
    @memcpy(buf[1..], old);
    slot.* = buf;
    return true;
}

/// The ARRAY special-list keywords — `array v{*} _numeric_;` and friends — whose
/// members are resolved against the live PDV at exec time (GH#48). null = a plain
/// member name.
fn specialArrName(name: []const u8) ?ast.SpecialArr {
    if (eqi(name, "_numeric_")) return .numeric;
    if (eqi(name, "_character_")) return .character;
    if (eqi(name, "_all_")) return .all;
    return null;
}

/// A token's source text, for re-serializing dataset options back into a string.
/// null = a token this can't re-serialize; the caller must fail LOUD — the old
/// `else => ""` silently dropped operators, so `where=(x <> 3)` re-lexed as
/// `where=(x 3)` and filtered nothing (QA-audit42).
fn tokenText(t: Token) ?[]const u8 {
    return switch (t.tag) {
        .name, .number => t.text,
        .eq => "=",
        .lparen => "(",
        .rparen => ")",
        .comma => ",",
        .dollar => "$",
        .gt => ">",
        .lt => "<",
        .ge => ">=",
        .le => "<=",
        .ne => "^=",
        .min_op => "><",
        .max_op => "<>",
        .star => "*",
        .star2 => "**",
        .plus => "+",
        .minus => "-",
        .slash => "/",
        .concat => "||",
        .amp => "&",
        .pipe => "|",
        .dot => ".",
        .colon => ":",
        .semicolon => ";",
        else => null,
    };
}

/// Rewrite `of NAME { * }` (an all-elements function-call list) into
/// `NAME{1}, NAME{2}, …, NAME{dim}` — ordinary array refs the expression parser
/// already handles. The dimension comes from a pre-scan of `array NAME { n }`.
/// ponytail: only the `{*}` form; `of a-b` / `of a b c` var-lists aren't expanded.
/// Rewrite each `do over ARR; BODY end;` into `do _dooverK_ = LO to HI; BODY' end;`,
/// where BODY' replaces every bare `ARR` (the array name, unsubscripted) with
/// `ARR{_dooverK_}`. Iterates to a fixpoint so nested/multiple do-overs expand.
/// SAS 9.4 DO-statement doc: "DO OVER array-name" iterates the array's
/// LBOUND..HBOUND with an implicit index, and the unsubscripted array name in
/// the body refers to the current element — the desugar reproduces exactly
/// that. Bounds come from the declaration: `array a{n}` → 1..n, `array a{lo:hi}`
/// → lo..hi (FEAT-doover). A `do over` of anything else (undeclared name,
/// non-array variable, `{*}`/multi-dim/negative-bound arrays) fails LOUD
/// (D-002). ponytail: only literal non-negative integer bounds are matched;
/// signed or expression bounds fall to the loud error, extend the scan if a
/// real program needs them.
fn expandDoOver(a: std.mem.Allocator, diags: *diag.Diagnostics, toks_in: []const Token, expanded: *bool) Error![]const Token {
    var toks = toks_in;
    while (true) {
        // array name → declared bounds (`array NAME { N }` or `array NAME { LO : HI }`)
        const Dim = struct { name: []const u8, lo: []const u8, hi: []const u8 };
        var dims: std.ArrayList(Dim) = .empty;
        {
            var i: usize = 0;
            while (i + 4 < toks.len) : (i += 1) {
                const boundary = i == 0 or toks[i - 1].tag == .semicolon;
                if (!(boundary and tkKw(toks[i], "array") and toks[i + 1].tag == .name and
                    toks[i + 2].tag == .lbrace and toks[i + 3].tag == .number)) continue;
                if (toks[i + 4].tag == .rbrace)
                    try dims.append(a, .{ .name = toks[i + 1].text, .lo = "1", .hi = toks[i + 3].text })
                else if (i + 6 < toks.len and toks[i + 4].tag == .colon and
                    toks[i + 5].tag == .number and toks[i + 6].tag == .rbrace)
                    try dims.append(a, .{ .name = toks[i + 1].text, .lo = toks[i + 3].text, .hi = toks[i + 5].text });
            }
        }

        // find the first `do over NAME` whose NAME is a known array
        var start: ?usize = null;
        var name: []const u8 = "";
        var lo: []const u8 = "1";
        var hi: []const u8 = "0";
        {
            var i: usize = 0;
            while (i + 2 < toks.len) : (i += 1) {
                const boundary = i == 0 or toks[i - 1].tag == .semicolon;
                if (boundary and tkKw(toks[i], "do") and tkKw(toks[i + 1], "over") and toks[i + 2].tag == .name) {
                    var known = false;
                    for (dims.items) |d| if (eqi(d.name, toks[i + 2].text)) {
                        start = i;
                        name = d.name;
                        lo = d.lo;
                        hi = d.hi;
                        known = true;
                        break;
                    };
                    if (start != null) break;
                    // `do over` of a non-array (or an array form the scan above
                    // can't bound) must not slip through to the confusing
                    // "expected '=' in do loop" — fail LOUD here (FEAT-doover, D-002).
                    if (!known)
                        return diags.fail(error.ParseError, toks[i].line, "DO OVER {s}: not a declared one-dimensional array with constant bounds", .{toks[i + 2].text});
                }
            }
        }
        if (start == null) return toks; // no more do-over

        const s = start.?;
        var bodystart = s + 3; // past `do over NAME`
        if (bodystart < toks.len and toks[bodystart].tag == .semicolon) bodystart += 1;
        // matching `end` by do/end depth
        var depth: usize = 1;
        var j = bodystart;
        while (j < toks.len) : (j += 1) {
            if (tkKw(toks[j], "do")) depth += 1 else if (tkKw(toks[j], "end")) {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        const body = toks[bodystart..j];
        var after = if (j < toks.len) j + 1 else j; // past `end`
        if (after < toks.len and toks[after].tag == .semicolon) after += 1;

        // The index is SAS's automatic implicit-array variable `_I_`: a body/step
        // may read it (legal SAS), and it is dropped from the output by the caller.
        // ponytail: a single shared `_i_` — nested DO OVER (do-over inside do-over)
        // would collide, but SAS itself reuses `_I_` for nested implicit arrays and
        // no corpus program nests them; do-over inside a plain DO is fine (distinct
        // index names). Give each loop a unique index if a nested case ever appears.
        const idx = "_i_";
        expanded.* = true;

        var out: std.ArrayList(Token) = .empty;
        try out.appendSlice(a, toks[0..s]);
        // do _dooverK_ = LO to HI ;
        try out.appendSlice(a, &.{
            .{ .tag = .name, .text = "do" }, .{ .tag = .name, .text = idx }, .{ .tag = .eq },
            .{ .tag = .number, .text = lo }, .{ .tag = .name, .text = "to" },
            .{ .tag = .number, .text = hi }, .{ .tag = .semicolon },
        });
        // body with bare NAME → NAME { idx }
        var k: usize = 0;
        while (k < body.len) : (k += 1) {
            const tk = body[k];
            const bare = tk.tag == .name and eqi(tk.text, name) and !(k + 1 < body.len and body[k + 1].tag == .lbrace);
            if (bare) try out.appendSlice(a, &.{
                .{ .tag = .name, .text = name }, .{ .tag = .lbrace },
                .{ .tag = .name, .text = idx }, .{ .tag = .rbrace },
            }) else try out.append(a, tk);
        }
        try out.appendSlice(a, &.{ .{ .tag = .name, .text = "end" }, .{ .tag = .semicolon } });
        try out.appendSlice(a, toks[after..]);
        toks = out.items; // re-scan for further do-overs (nested/sibling)
    }
}

pub fn tkKw(tk: Token, kw: []const u8) bool {
    return tk.tag == .name and eqi(tk.text, kw);
}

fn expandArrayStars(a: std.mem.Allocator, toks: []const Token) Error![]const Token {
    // pass 1: array name → declared dimensions (per-dim lower bound + size).
    const Dim = struct { name: []const u8, dims: []const pe.ArrayDim };
    var dims: std.ArrayList(Dim) = .empty;
    {
        var i: usize = 0;
        while (i + 4 < toks.len) : (i += 1) {
            const boundary = i == 0 or toks[i - 1].tag == .semicolon;
            if (!(boundary and toks[i].tag == .name and eqi(toks[i].text, "array") and
                toks[i + 1].tag == .name and toks[i + 2].tag == .lbrace)) continue;
            const scan = (try scanStarDims(a, toks, i + 2)) orelse continue;
            const dl = scan.dims;
            // resolve a single-dim `*` (size 0) from the member list (`array a{*} …`)
            if (dl.len == 1 and dl[0].size == 0) dl[0].size = countMembers(toks, memberStart(toks, scan.after));
            var ok = dl.len > 0;
            for (dl) |d| if (d.size == 0) {
                ok = false; // an unresolved size (multi-dim `*`) — parseArray fails loud
            };
            if (ok) try dims.append(a, .{ .name = toks[i + 1].text, .dims = dl });
        }
    }
    const lookup = struct {
        fn f(list: []const Dim, name: []const u8) ?[]const pe.ArrayDim {
            for (list) |d| if (eqi(d.name, name)) return d.dims;
            return null;
        }
    }.f;

    // is there an `of NAME{*}` to expand at all?
    var any = false;
    {
        var i: usize = 0;
        while (i + 4 < toks.len) : (i += 1) {
            if (isOfStar(toks, i) and lookup(dims.items, toks[i + 1].text) != null) {
                any = true;
                break;
            }
        }
    }
    if (!any) return toks;

    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (i + 4 < toks.len and isOfStar(toks, i)) {
            if (lookup(dims.items, toks[i + 1].text)) |dl| {
                const name = toks[i + 1].text;
                const line = toks[i].line;
                // Emit every element in ROW-MAJOR order (SAS: rightmost subscript
                // varies fastest) as `NAME{i1,i2,…}` refs; each fold (arraySubscript)
                // maps back to 0-based `elements`, so a lo!=1 / multi-dim array
                // expands correctly (GAP-multidimarray).
                var total: usize = 1;
                for (dl) |d| total *= d.size;
                const counter = try a.alloc(usize, dl.len);
                @memset(counter, 0);
                var e: usize = 0;
                while (e < total) : (e += 1) {
                    if (e > 0) try out.append(a, .{ .tag = .comma, .line = line });
                    try out.append(a, .{ .tag = .name, .text = name, .line = line });
                    try out.append(a, .{ .tag = .lbrace, .line = line });
                    for (dl, 0..) |d, m| {
                        if (m > 0) try out.append(a, .{ .tag = .comma, .line = line });
                        try out.append(a, .{ .tag = .number, .text = try std.fmt.allocPrint(a, "{d}", .{d.lo + @as(i64, @intCast(counter[m]))}), .line = line });
                    }
                    try out.append(a, .{ .tag = .rbrace, .line = line });
                    // odometer, rightmost dimension fastest
                    var m = dl.len;
                    while (m > 0) {
                        m -= 1;
                        counter[m] += 1;
                        if (counter[m] < dl[m].size) break;
                        counter[m] = 0;
                    }
                }
                i += 5; // consumed `of NAME { * }`
                continue;
            }
        }
        try out.append(a, toks[i]);
        i += 1;
    }
    return out.toOwnedSlice(a);
}

/// A variable label carried on a `.format` FormatItem: NUL-prefixed so exec can tell
/// it apart from a real format spec (which is always printable). See exec's `.format`.
/// BUG-attrboundssilent (4b): the 256-byte cap is enforced here — the single
/// choke point BOTH label producers (LABEL statement, ATTRIB LABEL=) route
/// through. LABEL Statement, Statements Ref printed p.207 (marker
/// "=== pdf 218 ===", footer "LABEL Statement 207"): "text-string specifies a
/// label of up to 256 bytes." Over the cap is a malformed program → rc 1
/// (D-009b(ii)); ERROR-vs-truncate is doc-silent, and D-002 forbids the old
/// silent store either way.
fn rideAsLabel(a: std.mem.Allocator, diags: *diag.Diagnostics, name: []const u8, label: []const u8, line: usize) Error![]const u8 {
    if (label.len > 256)
        return diags.fail(error.ParseError, line, "Label for variable {s} is {d} bytes, over the SAS maximum label length 256.", .{ name, label.len });
    return std.fmt.allocPrint(a, "\x00{s}", .{label});
}

/// The `…X` name-taking twin of a V-metadata function, or null if `name` isn't one.
fn vMetaX(name: []const u8) ?[]const u8 {
    if (eqi(name, "vlabel")) return "vlabelx";
    if (eqi(name, "vname")) return "vnamex";
    if (eqi(name, "vvalue")) return "vvaluex";
    if (eqi(name, "vformat")) return "vformatx";
    if (eqi(name, "vformatn")) return "vformatnx";
    if (eqi(name, "vformatw")) return "vformatwx";
    if (eqi(name, "vformatd")) return "vformatdx";
    if (eqi(name, "vinformat")) return "vinformatx";
    if (eqi(name, "vinformatn")) return "vinformatnx";
    if (eqi(name, "vinformatw")) return "vinformatwx";
    if (eqi(name, "vinformatd")) return "vinformatdx";
    return null;
}

/// Desugar the numbered array-bound aliases `dimN(a)` / `hboundN(a)` / `lboundN(a)`
/// into the two-arg form `dim(a, N)` / … (GAP-arraybounds-batch). SAS spells the
/// dimension as a digit suffix on the function name; parser_expr's bound folding
/// (isBoundFn) knows only the two-arg form, so strip the suffix from the name and
/// insert `, N` before the call's close paren.
/// ponytail: rewrites ANY `dimN(`/`hboundN(`/`lboundN(` name token — an ARRAY
/// named e.g. `dim1` subscripted with parens (`dim1(i)`) would be mis-rewritten
/// (SAS shares that name ambiguity). Upgrade path: a call-site desugar in
/// parser_expr where the array table is known.
fn rewriteBoundAliases(a: std.mem.Allocator, toks: []const Token) Error![]const Token {
    // split `dim2` / `hbound10` / `lbound1` → base + digit suffix; null otherwise
    const split = struct {
        fn f(s: []const u8) ?struct { base: []const u8, n: []const u8 } {
            var e = s.len;
            while (e > 0 and std.ascii.isDigit(s[e - 1])) e -= 1;
            if (e == s.len or e == 0) return null; // no digit suffix
            const b = s[0..e];
            if (eqi(b, "dim") or eqi(b, "hbound") or eqi(b, "lbound"))
                return .{ .base = b, .n = s[e..] };
            return null;
        }
    }.f;
    const isAliasCall = struct {
        fn f(ts: []const Token, i: usize) bool {
            return ts[i].tag == .name and i + 1 < ts.len and ts[i + 1].tag == .lparen and split(ts[i].text) != null;
        }
    }.f;
    var any = false;
    for (toks, 0..) |_, i| if (isAliasCall(toks, i)) {
        any = true;
        break;
    };
    if (!any) return toks;

    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (isAliasCall(toks, i)) {
            const s = split(toks[i].text).?;
            const line = toks[i].line;
            try out.append(a, .{ .tag = .name, .text = s.base, .line = line });
            try out.append(a, toks[i + 1]); // (
            i += 2;
            // copy the call body, inserting `, N` at its matching close paren
            var depth: usize = 1;
            while (i < toks.len and depth > 0) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1;
                if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) {
                        try out.append(a, .{ .tag = .comma, .line = line });
                        try out.append(a, .{ .tag = .number, .text = s.n, .line = line });
                    }
                }
                try out.append(a, toks[i]);
            }
        } else {
            try out.append(a, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Rewrite `vfunc(NAME)` → `vfuncx("NAME")` for the V-metadata functions that take a
/// bare variable. The evaluator hands a function the variable's VALUE, losing its
/// name, so these need the name as a string literal. Only the simple `f(name)` form
/// matches (SAS requires a bare variable arg); arrays use `{}`, so no collision.
fn rewriteVMeta(a: std.mem.Allocator, toks: []const Token) Error![]const Token {
    const matches = struct {
        fn f(ts: []const Token, i: usize) bool {
            return i + 3 < ts.len and vMetaX(ts[i].text) != null and
                ts[i + 1].tag == .lparen and ts[i + 2].tag == .name and ts[i + 3].tag == .rparen;
        }
    }.f;
    var any = false;
    for (toks, 0..) |t, i| if (t.tag == .name and matches(toks, i)) {
        any = true;
        break;
    };
    if (!any) return toks;

    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (toks[i].tag == .name and matches(toks, i)) {
            try out.append(a, .{ .tag = .name, .text = vMetaX(toks[i].text).?, .line = toks[i].line });
            try out.append(a, toks[i + 1]); // (
            try out.append(a, .{ .tag = .string, .text = toks[i + 2].text, .line = toks[i + 2].line }); // "name"
            try out.append(a, toks[i + 3]); // )
            i += 4;
        } else {
            try out.append(a, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Expand the `of` operator inside a function call: `sum(of x1-x3)` →
/// `sum(x1, x2, x3)`, `mean(of a b c)` → `mean(a, b, c)`. Numbered ranges expand;
/// a special list (`_numeric_`/`_all_`/`_character_`) passes through as one name
/// for the evaluator to resolve against the runtime PDV. `of a{*}` is already
/// handled by expandArrayStars; an array element ref passes through verbatim.
fn expandOf(a: std.mem.Allocator, toks: []const Token, diags: *diag.Diagnostics) Error![]const Token {
    var any = false;
    for (toks, 0..) |t, i| {
        if (i > 0 and t.tag == .name and eqi(t.text, "of") and
            (toks[i - 1].tag == .lparen or toks[i - 1].tag == .comma))
        {
            any = true;
            break;
        }
    }
    if (!any) return toks;

    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        const after_open = out.items.len > 0 and
            (out.items[out.items.len - 1].tag == .lparen or out.items[out.items.len - 1].tag == .comma);
        if (toks[i].tag == .name and eqi(toks[i].text, "of") and after_open) {
            const line = toks[i].line;
            i += 1; // past `of`
            var first = true;
            while (i < toks.len and toks[i].tag != .rparen and toks[i].tag != .comma) {
                // A colon NOT immediately after a name (`of :`, `of x1-x:`) is
                // not the prefix form — malformed SAS: rc 1 (D-009), not a gap.
                if (toks[i].tag == .colon)
                    return diags.fail(error.ParseError, toks[i].line, "unexpected ':' in an OF variable list (the name-prefix form is written sum(of x:))", .{});
                if (toks[i].tag != .name) {
                    i += 1;
                    continue;
                }
                // `sum(of x:)` — the name-PREFIX list (Language Reference: Concepts printed p.70
                // Table 4.5: "Function(OF x:) Performs the function on all the
                // variables that begin with 'x'"; funcref printed p.6: OF's
                // variable-list "can be any form of a SAS variable list").
                // This pre-pass has no PDV to expand the prefix against, so
                // wrap it in a synthetic `__ofprefix("x")` argument — the
                // `__dimchk` pattern — for eval to expand at call time beside
                // `of _numeric_`. A CALL node, not a bare `x:` variable, so
                // exec's uninitialized-var scan sees a string and stays quiet.
                if (i + 1 < toks.len and toks[i + 1].tag == .colon) {
                    if (!first) try out.append(a, .{ .tag = .comma, .line = line });
                    try out.append(a, .{ .tag = .name, .text = "__ofprefix", .line = line });
                    try out.append(a, .{ .tag = .lparen, .line = line });
                    try out.append(a, .{ .tag = .string, .text = toks[i].text, .line = line });
                    try out.append(a, .{ .tag = .rparen, .line = line });
                    first = false;
                    i += 2;
                    continue;
                }
                if (i + 2 < toks.len and toks[i + 1].tag == .minus and toks[i + 2].tag == .name) {
                    var names: std.ArrayList([]const u8) = .empty; // NAME - NAME range
                    try expandRange(a, &names, toks[i].text, toks[i + 2].text);
                    for (names.items) |nm| {
                        if (!first) try out.append(a, .{ .tag = .comma, .line = line });
                        try out.append(a, .{ .tag = .name, .text = nm, .line = line });
                        first = false;
                    }
                    i += 3;
                } else if (i + 1 < toks.len and toks[i + 1].tag == .lbrace) {
                    if (!first) try out.append(a, .{ .tag = .comma, .line = line });
                    first = false;
                    var depth: usize = 0; // array element ref: copy `name{…}` verbatim
                    while (i < toks.len) : (i += 1) {
                        try out.append(a, toks[i]);
                        if (toks[i].tag == .lbrace) {
                            depth += 1;
                        } else if (toks[i].tag == .rbrace) {
                            depth -= 1;
                            if (depth == 0) {
                                i += 1;
                                break;
                            }
                        }
                    }
                } else {
                    if (!first) try out.append(a, .{ .tag = .comma, .line = line });
                    try out.append(a, toks[i]);
                    first = false;
                    i += 1;
                }
            }
            continue;
        }
        try out.append(a, toks[i]);
        i += 1;
    }
    return out.toOwnedSlice(a);
}

/// Token-level scan of an array's dimension spec, starting at the `{`/`[` token:
/// parse the comma-separated dimensions (`n` / `lo:hi` / `*`) into per-dim lo/size
/// (size 0 = `*`, inferred), returning them and the position just past the closing
/// bracket. null on malformed input (parseArray then reports the real error).
/// Mirrors parseArray's dimension loop; used only to expand `of NAME{*}`.
fn scanStarDims(a: std.mem.Allocator, toks: []const Token, brace: usize) Error!?struct { dims: []pe.ArrayDim, after: usize } {
    var list: std.ArrayList(pe.ArrayDim) = .empty;
    var j = brace + 1;
    while (j < toks.len) {
        // mirror parseArray: a bound may carry a leading minus (`{-2:2}`)
        var neg = false;
        if (toks[j].tag == .minus) {
            neg = true;
            j += 1;
        }
        if (j < toks.len and toks[j].tag == .number) {
            var first = std.fmt.parseInt(i64, toks[j].text, 10) catch 0;
            if (neg) first = -first;
            j += 1;
            if (j < toks.len and toks[j].tag == .colon) {
                j += 1;
                const neg_hi = j < toks.len and toks[j].tag == .minus;
                if (neg_hi) j += 1;
                if (j < toks.len and toks[j].tag == .number) {
                    var hi = std.fmt.parseInt(i64, toks[j].text, 10) catch first;
                    if (neg_hi) hi = -hi;
                    j += 1;
                    try list.append(a, .{ .lo = first, .size = if (hi >= first) @intCast(hi - first + 1) else 0 });
                } else if (j < toks.len and toks[j].tag == .star) {
                    j += 1;
                    try list.append(a, .{ .lo = first, .size = 0 }); // lo:* — inferred
                } else return null;
            } else if (neg) return null // a bare negative count is nonsense — parseArray fails loud
            else try list.append(a, .{ .lo = 1, .size = @intCast(first) });
        } else if (!neg and j < toks.len and toks[j].tag == .star) {
            j += 1;
            try list.append(a, .{ .lo = 1, .size = 0 }); // * — inferred
        } else return null;
        if (j < toks.len and toks[j].tag == .comma) {
            j += 1;
            continue;
        }
        break;
    }
    if (j >= toks.len or toks[j].tag != .rbrace) return null;
    return .{ .dims = list.items, .after = j + 1 };
}

/// Skip an optional `$ [len]` after an array dimension to reach the member list.
fn memberStart(toks: []const Token, at: usize) usize {
    var j = at;
    if (j < toks.len and toks[j].tag == .dollar) {
        j += 1;
        if (j < toks.len and toks[j].tag == .number) j += 1;
    }
    return j;
}

/// Count array members (names, with `a1-a3` ranges expanded) up to `(` or `;`.
fn countMembers(toks: []const Token, start: usize) usize {
    var count: usize = 0;
    var j = start;
    while (j < toks.len and toks[j].tag != .lparen and toks[j].tag != .semicolon) {
        if (toks[j].tag == .name) {
            if (j + 2 < toks.len and toks[j + 1].tag == .minus and toks[j + 2].tag == .name) {
                const f = splitNumSuffix(toks[j].text);
                const l = splitNumSuffix(toks[j + 2].text);
                count += if (f.digits > 0 and l.digits > 0 and l.num >= f.num) l.num - f.num + 1 else 2;
                j += 3;
            } else {
                count += 1;
                j += 1;
            }
        } else j += 1;
    }
    return count;
}

fn isOfStar(toks: []const Token, i: usize) bool {
    return toks[i].tag == .name and eqi(toks[i].text, "of") and
        toks[i + 1].tag == .name and toks[i + 2].tag == .lbrace and
        toks[i + 3].tag == .star and toks[i + 4].tag == .rbrace;
}

/// Expand a numbered variable range `a1-a5` into `a1 a2 a3 a4 a5`. When the two
/// names don't share a prefix + numeric suffix, fall back to just the endpoints.
/// Zero-padded endpoints (`ds00-ds02` → `ds00 ds01 ds02`) reproduce the literal
/// member names: SAS numbered-range names must match the padding or the members
/// aren't found.
pub fn expandRange(a: std.mem.Allocator, out: *std.ArrayList([]const u8), first: []const u8, last: []const u8) std.mem.Allocator.Error!void {
    const f = splitNumSuffix(first);
    const l = splitNumSuffix(last);
    if (f.digits == 0 or l.digits == 0 or f.num > l.num or
        !std.ascii.eqlIgnoreCase(first[0 .. first.len - f.digits], last[0 .. last.len - l.digits]))
    {
        try out.append(a, first);
        try out.append(a, last);
        return;
    }
    const prefix = first[0 .. first.len - f.digits];
    // Leading zeros present when the digit run is wider than the value needs
    // (`00`: 2 digits, value 0). Pad every generated suffix to the widest
    // endpoint; `ds0-ds2` (no padding) stays plain integers.
    const padded = f.digits > decWidth(f.num);
    const width = @max(f.digits, l.digits);
    var n = f.num;
    while (n <= l.num) : (n += 1) {
        if (padded) {
            try out.append(a, try std.fmt.allocPrint(a, "{[p]s}{[n]d:0>[w]}", .{ .p = prefix, .n = n, .w = width }));
        } else {
            try out.append(a, try std.fmt.allocPrint(a, "{s}{d}", .{ prefix, n }));
        }
    }
}

/// Number of decimal digits in `n` (0 → 1).
fn decWidth(n: usize) usize {
    var w: usize = 1;
    var v = n;
    while (v >= 10) : (v /= 10) w += 1;
    return w;
}

/// Split a trailing run of digits off `s`: `.num` is their value, `.digits` how
/// many there were (0 = none).
fn splitNumSuffix(s: []const u8) struct { num: usize, digits: usize } {
    var i = s.len;
    while (i > 0 and s[i - 1] >= '0' and s[i - 1] <= '9') i -= 1;
    const digits = s.len - i;
    const num = std.fmt.parseInt(usize, s[i..], 10) catch 0;
    return .{ .num = num, .digits = digits };
}

/// Merge each `first`/`last` · `.` · name run into one `.name` token whose text
/// is `first.<var>` — the BY-group automatic variable. Everything else passes
/// through untouched; returns the input slice unchanged when no run is present.
fn coalesceFirstLast(a: std.mem.Allocator, toks: []const Token) Error![]const Token {
    var i: usize = 0;
    var any = false;
    while (i + 2 < toks.len) : (i += 1) {
        if (isFirstLast(toks[i]) and toks[i + 1].tag == .dot and toks[i + 2].tag == .name) {
            any = true;
            break;
        }
    }
    if (!any) return toks;

    var out: std.ArrayList(Token) = .empty;
    i = 0;
    while (i < toks.len) {
        const t = toks[i];
        if (i + 2 < toks.len and isFirstLast(t) and toks[i + 1].tag == .dot and toks[i + 2].tag == .name) {
            const text = try std.fmt.allocPrint(a, "{s}.{s}", .{ t.text, toks[i + 2].text });
            try out.append(a, .{ .tag = .name, .text = text, .line = t.line });
            i += 3;
        } else {
            try out.append(a, t);
            i += 1;
        }
    }
    return out.toOwnedSlice(a);
}

fn isFirstLast(t: Token) bool {
    return t.tag == .name and
        (std.ascii.eqlIgnoreCase(t.text, "first") or std.ascii.eqlIgnoreCase(t.text, "last"));
}

/// Source → statement list, in one call (lexer + parser). Convenience for C3
/// and tests; errors are collected in `diags`.
pub fn parse(arena: std.mem.Allocator, src: []const u8, diags: *diag.Diagnostics) Error!ast.Program {
    const toks = try lex.tokenize(arena, src, diags);
    var p = Parser.init(arena, toks, diags);
    return p.parseProgram();
}

// ── tests ────────────────────────────────────────────────────────────────

const testing = std.testing;

fn prog(a: std.mem.Allocator, diags: *diag.Diagnostics, src: []const u8) Error!ast.Program {
    return parse(a, src, diags);
}

test "BUG-lengthcapnostore: an over-long DECLARED length errors at the statement, store or no store; the cap boundaries stay legal" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // The residual this fixes: a store-free declaration slipped through silent.
    // Loud now, via the captured reporter (D-003) — never a spawned abort.
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "length y $40000;"));
    try testing.expect(d1.hasErrors());
    try testing.expect(std.mem.indexOf(u8, d1.list.items[0].message, "over the SAS maximum character length 32767") != null);

    // ATTRIB is the other spelling of the same declaration (printed p.34).
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "attrib z length=$40000;"));
    try testing.expect(d2.hasErrors());

    // Regression guard on 67a3c834: the with-a-store case stays loud (now at
    // the statement, one step earlier than setAt — same message text).
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, "length x $40000; x='hi';"));
    try testing.expect(d3.hasErrors());

    // Boundary controls — exactly at the cap is legal, one over is not.
    var d4 = diag.Diagnostics.init(a);
    _ = try prog(a, &d4, "length a $32766 b $32767; attrib c length=$32767;");
    try testing.expect(!d4.hasErrors());
    var d5 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d5, "length w $32768;"));

    // Numeric side: length 8 legal, over 8 loud (same class; the doc cap is
    // universal). The platform-dependent minimum (2 z/OS / 3 elsewhere) is
    // deliberately not pinned.
    var d6 = diag.Diagnostics.init(a);
    _ = try prog(a, &d6, "length m 8;");
    try testing.expect(!d6.hasErrors());
    var d7 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d7, "length m 99;"));
    try testing.expect(std.mem.indexOf(u8, d7.list.items[0].message, "maximum numeric length 8") != null);
}

test "BUG-attribemptyvaluenoop: a DATA-step empty format=/informat= is LOUD, not a silent no-op; every valued clause and the documented bare-statement removal stay clean" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Both empty forms used to fall off the end of parseAttrib unrecorded: the
    // spec vanished, the old attribute stayed, rc 0, zero diagnostics (D-002).
    // Loud now via the captured reporter (D-003) — never a spawned abort.
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "attrib v format=;"));
    try testing.expect(d1.hasErrors());
    try testing.expect(std.mem.indexOf(u8, d1.list.items[0].message, "an empty format value is not valid in a DATA step") != null);
    // The message must hand the user the DOCUMENTED route (printed p.112 /
    // p.115 Ex.3), or a loud error just strands a program that meant to strip.
    try testing.expect(std.mem.indexOf(u8, d1.list.items[0].message, "'format v;'") != null);

    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "attrib v informat=;"));
    try testing.expect(std.mem.indexOf(u8, d2.list.items[0].message, "an empty informat value is not valid in a DATA step") != null);
    try testing.expect(std.mem.indexOf(u8, d2.list.items[0].message, "'informat v;'") != null);

    // rc 1, not rc 2 (D-009): invalid DATA-step SAS is the USER's error, so the
    // gap flag must stay DOWN. gapHit() is process-global — reset first.
    diag.resetGap();
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, "attrib v format=;"));
    try testing.expect(!diag.gapHit());

    // Same arm, other shape: a format NAME with no trailing dot is not a spec
    // either (tryFormatSpec returns null there too) — it was the same silent
    // drop, and it gets its own message naming what it saw.
    var d4 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d4, "attrib v format=myfmt;"));
    try testing.expect(std.mem.indexOf(u8, d4.list.items[0].message, "is not a format specification") != null);

    // POSITIVE CONTROL (D-014's lesson): everything the doc blesses stays clean.
    // Every valued clause, both orders, multi-variable groups, `$` widths.
    var d5 = diag.Diagnostics.init(a);
    _ = try prog(a, &d5, "attrib q format=comma10.2 informat=best8. label='Q' length=8; attrib s t length=$4 format=$char4. label='S/T';");
    try testing.expect(!d5.hasErrors());

    // …and the DOCUMENTED removal route (a bare FORMAT/INFORMAT statement,
    // printed p.112) must NOT have been swept up by this change: it parses,
    // reports nothing, and still emits its clear item.
    var d6 = diag.Diagnostics.init(a);
    const p6 = try prog(a, &d6, "format x; informat y;");
    try testing.expect(!d6.hasErrors());
    try testing.expectEqual(@as(usize, 2), p6.len);
    try testing.expectEqualStrings("x", p6[0].format[0].name);
    try testing.expectEqualStrings("y", p6[1].informat[0].name);
}

test "BUG-attrboundssilent: declared-length floors and the 256-byte label cap fail loud rc-1-side; legal edges + the numeric 2 park untouched" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // 4a — the floors an upper-bounds-only checkDeclLen swallowed. Captured
    // reporter (D-003), and each is a USER error: rc 1, never gap-tagged
    // (D-009b(ii) — `length c $0` is not valid SAS on ANY platform).
    const lows = [_][]const u8{
        "length c $0;", // char: "1 to 32767 bytes under all operating environments"
        "attrib c length=$0;", // ATTRIB spelling of the same declaration (p.34)
        "length n 0;", // numeric 0: out of range on every platform the doc lists
        "length n 1;", // numeric 1: same, z/OS included
        "attrib n length=1;",
    };
    for (lows) |src| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &d, src));
        try testing.expect(d.hasErrors());
        try testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "under the SAS minimum") != null);
        try testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }

    // 4b — the 256-byte label cap through BOTH producers (LABEL statement and
    // ATTRIB LABEL=), which funnel through rideAsLabel. Guarding one call
    // site would leave the sibling broken.
    const l257 = "X" ** 257;
    const via_label = try std.fmt.allocPrint(a, "label v = '{s}';", .{l257});
    const via_attrib = try std.fmt.allocPrint(a, "attrib v label='{s}';", .{l257});
    for ([_][]const u8{ via_label, via_attrib }) |src| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &d, src));
        try testing.expect(d.hasErrors());
        try testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "over the SAS maximum label length 256") != null);
        try testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }

    // Boundary controls (the D-014 lesson: over-rejecting a legal program is
    // the worse regression). In-range edges — also pinned end-to-end by the
    // attr_bounds_doc corpus fixture, which must not move — and the no-width
    // forms (`length e $;` is a legal width-less char declaration, distinct
    // from an explicit `$0` now that lengthNumber returns ?usize).
    var ok = diag.Diagnostics.init(a);
    _ = try prog(a, &ok, "length a $1 b $32767 c 3 d 8; length e $; length f;");
    try testing.expect(!ok.hasErrors());
    // Exactly 256 label bytes stays legal — the legal edge a 257 check must
    // not trip over.
    const ok_src = try std.fmt.allocPrint(a, "label v = '{s}';", .{"L" ** 256});
    var ok3 = diag.Diagnostics.init(a);
    _ = try prog(a, &ok3, ok_src);
    try testing.expect(!ok3.hasErrors());
    // numeric 2: the ONE genuinely platform-dependent boundary (legal z/OS,
    // illegal UNIX/Windows) stays parked — pinned ACCEPTED here so flipping
    // the park is a conscious test edit, but deliberately NOT a corpus golden.
    var ok2 = diag.Diagnostics.init(a);
    _ = try prog(a, &ok2, "length g 2;");
    try testing.expect(!ok2.hasErrors());
}

test "array: range expansion, initial values, and a{i} resolution" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "array a{3} x1-x3 (10 20 30);\ny = a{2};");
    try testing.expectEqual(@as(usize, 2), p.len);

    const decl = p[0].array;
    try testing.expectEqualStrings("a", decl.name);
    try testing.expectEqual(@as(usize, 3), decl.elements.len);
    try testing.expectEqualStrings("x1", decl.elements[0]);
    try testing.expectEqualStrings("x3", decl.elements[2]); // x1-x3 expanded
    try testing.expectEqual(@as(usize, 3), decl.inits.len);
    try testing.expectEqual(@as(f64, 20), decl.inits[1].num);

    // y = a{2} → an array_ref carrying the resolved member list + subscript
    const ar = p[1].assign.value.array_ref;
    try testing.expectEqualStrings("a", ar.name);
    try testing.expectEqual(@as(usize, 3), ar.elements.len);
    try testing.expectEqualStrings("x2", ar.elements[1]);
    try testing.expectEqual(@as(f64, 2), ar.index.num);
}

test "array: parenthesized init `(count * value)` repeat form + mixes, `[..]` dim (GAP-arrayinit)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // SAS initializes array members from a parenthesized list after the dimension/
    // element list, including the `n * value` repetition (SAS Concepts: ARRAY
    // statement — an initialized array is also implicitly RETAINed). `[..]` bracket
    // dimension too (a real max-length utility uses `array maxi[&n] (&n * 1);`).
    const src =
        \\array x[3] (3 * 0);
        \\array m{4} (2*1 2*9);
        \\array c[3] (2*0 5);
    ;
    const p = try prog(a, &diags, src);
    try testing.expectEqual(@as(usize, 3), p.len);

    // (3 * 0) → three zeros; implicit member names x1..x3 (no element list given).
    const d0 = p[0].array;
    try testing.expectEqual(@as(usize, 3), d0.inits.len);
    try testing.expectEqualStrings("x1", d0.elements[0]);
    try testing.expectEqualStrings("x3", d0.elements[2]);
    for (d0.inits) |iv| try testing.expectEqual(@as(f64, 0), iv.num);

    // (2*1 2*9) → 1, 1, 9, 9  (two repeat factors in one list)
    const d1 = p[1].array;
    try testing.expectEqual(@as(usize, 4), d1.inits.len);
    try testing.expectEqual(@as(f64, 1), d1.inits[0].num);
    try testing.expectEqual(@as(f64, 1), d1.inits[1].num);
    try testing.expectEqual(@as(f64, 9), d1.inits[2].num);
    try testing.expectEqual(@as(f64, 9), d1.inits[3].num);

    // (2*0 5) → 0, 0, 5  (repeat factor mixed with a plain trailing value)
    const d2 = p[2].array;
    try testing.expectEqual(@as(usize, 3), d2.inits.len);
    try testing.expectEqual(@as(f64, 0), d2.inits[0].num);
    try testing.expectEqual(@as(f64, 0), d2.inits[1].num);
    try testing.expectEqual(@as(f64, 5), d2.inits[2].num);
}

test "array: explicit lower-bound {lo:hi} offsets the subscript and folds dim/lbound/hbound (ARRAY-lobound-impl)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `array x{5:10} x5-x10;` sizes 6 members; `x{5}` (first) rewrites the subscript
    // to `5 - 4` so the shared `elements[i-1]` runtime path reads member 0.
    const p = try prog(a, &diags, "array x{5:10} x5-x10;\nx{5}=1;\nx{10}=6;\nn=dim(x);\nlo=lbound(x);\nhi=hbound(x);");
    const d = p[0].array;
    try testing.expectEqual(@as(usize, 6), d.elements.len);
    // x{5}= : index is (5 - 4)
    const a1 = p[1].array_assign.array.index;
    try testing.expect(a1.* == .binary and a1.binary.op == .sub);
    try testing.expectEqual(@as(f64, 5), a1.binary.lhs.num);
    try testing.expectEqual(@as(f64, 4), a1.binary.rhs.num);
    // dim/lbound/hbound fold to constants honoring lo (6 / 5 / 10)
    try testing.expectEqual(@as(f64, 6), p[3].assign.value.num);
    try testing.expectEqual(@as(f64, 5), p[4].assign.value.num);
    try testing.expectEqual(@as(f64, 10), p[5].assign.value.num);

    // inverted bounds fail loud (not silently mis-indexed).
    try testing.expectError(error.ParseError, prog(a, &diags, "array bad{6:2} b1-b5;"));

    // Plain {n} keeps a bare subscript (lo defaults to 1, no offset node).
    const q = try prog(a, &diags, "array ok{3} o1-o3;\nok{2}=9;");
    try testing.expect(q[1].array_assign.array.index.* == .num);
}

test "array: multi-dimensional {lo1:hi1, lo2:hi2} folds m{i,j} to a row-major flat index (GAP-multidimarray)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `array m{2,3}` → 6 members m1-m6. `m{i,j}` folds to 1 + (i-1)*3 + (j-1).
    const p = try prog(a, &diags, "array m{2,3} m1-m6;\nm{1,1}=10;\nm{2,3}=60;\nn=dim(m,2);\nlo=lbound(m,1);\nhi=hbound(m,2);");
    try testing.expectEqual(@as(usize, 6), p[0].array.elements.len);
    // m{2,3} evaluated: 1 + (2-1)*3 + (3-1) = 6 (constant-fold via a tiny eval)
    try testing.expectEqual(@as(f64, 6), evalConst(p[2].array_assign.array.index));
    try testing.expectEqual(@as(f64, 1), evalConst(p[1].array_assign.array.index)); // m{1,1} → 1
    // per-dimension dim/lbound/hbound: dim(m,2)=3, lbound(m,1)=1, hbound(m,2)=3
    try testing.expectEqual(@as(f64, 3), p[3].assign.value.num);
    try testing.expectEqual(@as(f64, 1), p[4].assign.value.num);
    try testing.expectEqual(@as(f64, 3), p[5].assign.value.num);

    // non-1 lower bounds per dimension: `array g{0:1,5:7}` → 2*3 = 6 members
    const q = try prog(a, &diags, "array g{0:1,5:7} g1-g6;\ng{0,5}=1;\ng{1,7}=6;");
    try testing.expectEqual(@as(usize, 6), q[0].array.elements.len);
    try testing.expectEqual(@as(f64, 1), evalConst(q[1].array_assign.array.index)); // g{0,5} → first
    try testing.expectEqual(@as(f64, 6), evalConst(q[2].array_assign.array.index)); // g{1,7} → last

    // wrong subscript count fails loud (2-D array, 1 subscript).
    try testing.expectError(error.ParseError, prog(a, &diags, "array w{2,3} w1-w6;\nw{4}=1;"));
    // `*` only allowed for a single dimension.
    try testing.expectError(error.ParseError, prog(a, &diags, "array s{2,*} s1-s6;"));
}

test "array/retain initial values are CONSTANTS ONLY — a variable or expression fails LOUD (GH#81 ISS-arrayinitnonconst)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // SAS 9.4 DATA Step Statements printed p.24: the values in an
    // (initial-value-list) "can be numbers or character strings"; p.26 Ex.3 puts
    // the variable NAMES outside the parentheses. `array v[2](a1 a2);` used to
    // parse clean and declare phantom v1/v2 seeded from an unevaluated variable
    // read, leaving a1/a2 untouched at rc 0. Same hole in `retain x (a);`.
    // rc CLASS: the user wrote invalid SAS → 1, not 2 (D-009, and D-009b(ii) —
    // the rc reports the class in real-SAS terms).
    const bad = [_]struct { src: []const u8, needle: []const u8 }{
        .{ .src = "array v[2](a1 a2);", .needle = "The variable a1 is not a valid initial value for the array v" },
        .{ .src = "array v[2] $ ('x' b);", .needle = "The variable b is not a valid initial value for the array v" },
        .{ .src = "array v[2] (put(1,8.) 2);", .needle = "The function call put() is not a valid initial value" },
        // rider (i): the `n*value` repeat rule used to swallow `2*3` and report a
        // confusing "3 initial values exceeds 2 elements"; `1+1` is now named for
        // what it is, at the init site.
        .{ .src = "array v[2] (1+1 2*3);", .needle = "An expression is not a valid initial value for the array v" },
        // rider (ii): the RETAIN paren list, same rule, same file.
        .{ .src = "retain x (a);", .needle = "The variable a is not a valid initial value in the RETAIN statement" },
        .{ .src = "retain x y (1 z);", .needle = "The variable z is not a valid initial value in the RETAIN statement" },
    };
    for (bad) |c| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &d, c.src));
        try testing.expect(d.hasErrors());
        try testing.expect(std.mem.indexOf(u8, d.list.items[0].message, c.needle) != null);
        try testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }

    // The legal forms must keep parsing (D-014: over-rejecting is the worse
    // regression). Signed literals fold to constants; `.` is the missing literal;
    // `n*value` stays a repeat factor; the BARE (unparenthesised) member list is a
    // variable REFERENCE list and is untouched by this rule.
    var diags = diag.Diagnostics.init(a);
    const p = try prog(a, &diags,
        \\array v[2] (1 2);
        \\array w[2] $ ("x" "y");
        \\array n[3] (-1 0 1);
        \\array r[4] (2*7 1 2);
        \\array m[2] (. 5);
        \\array k[2] a1 a2;
        \\array j[2] b1 b2 (1 2);
        \\retain s 0;
        \\retain t u (1 2);
    );
    try testing.expect(!diags.hasErrors());
    try testing.expectEqual(@as(usize, 2), p[0].array.inits.len);
    try testing.expectEqual(ast.UnOp.neg, p[2].array.inits[0].unary.op); // `-1` rides as neg(1)
    try testing.expectEqual(@as(f64, 1), p[2].array.inits[0].unary.operand.num);
    try testing.expectEqual(@as(f64, 7), p[3].array.inits[1].num); // 2*7 → 7,7,1,2
    try testing.expectEqual(@as(usize, 0), p[5].array.inits.len); // bare list: refs, no inits
    try testing.expectEqualStrings("a1", p[5].array.elements[0]);
}

test "infile: record-boundary options parse; an unknown option fails loud (BUG-infilemissover)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "infile datalines missover;\ninfile datalines truncover;\ninfile datalines stopover;\ninfile datalines;");
    try testing.expectEqual(ast.OverflowMode.missover, p[0].infile.overflow);
    try testing.expectEqual(ast.OverflowMode.truncover, p[1].infile.overflow);
    try testing.expectEqual(ast.OverflowMode.stopover, p[2].infile.overflow);
    try testing.expectEqual(ast.OverflowMode.flowover, p[3].infile.overflow); // default

    // an unrecognized INFILE option is a hard error, not a silent no-op.
    try testing.expectError(error.ParseError, prog(a, &diags, "infile datalines wombat;"));
    // BUG-infilepadinert: PAD was accepted and never read — a silent no-op, the
    // one hole in the fail-loud wall (D-002). It pads to LRECL=, which is itself
    // inert (ISS-infilelrecl), so loud-unsupported is the honest behavior.
    try testing.expectError(error.ParseError, prog(a, &diags, "infile datalines pad;"));
}

test "infile: END=name parses; END with no name fails loud (FEAT-infileend)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "infile datalines end=eof;\ninfile \"/tmp/x.dat\" END=last;");
    try testing.expectEqualStrings("eof", p[0].infile.end_var.?);
    try testing.expectEqualStrings("last", p[1].infile.end_var.?);
    try testing.expect(p[0].infile.inline_data);

    // END= with no variable name is a hard error.
    try testing.expectError(error.ParseError, prog(a, &diags, "infile datalines end=;"));
}

test "infile: OBS=/LINESIZE=/LS= parse; junk fails loud (FEAT-infileobslinesize)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "infile datalines obs=2;\ninfile datalines linesize=80;\ninfile datalines ls=3;");
    try testing.expectEqual(@as(?usize, 2), p[0].infile.obs);
    try testing.expectEqual(@as(?usize, 80), p[1].infile.linesize);
    try testing.expectEqual(@as(?usize, 3), p[2].infile.linesize);

    // no value / a non-number fails loud, unknown options still fail loud
    try testing.expectError(error.ParseError, prog(a, &diags, "infile datalines obs=;"));
    try testing.expectError(error.ParseError, prog(a, &diags, "infile datalines linesize=abc;"));
    try testing.expectError(error.ParseError, prog(a, &diags, "infile datalines wombat;"));
}

test "file: DLM=/DSD options parse; an unknown option fails loud (BUG-fileopts)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "file \"x.txt\" dlm=\",\" dsd;\nfile \"y.txt\" dsd;\nfile \"z.txt\";");
    try testing.expectEqual(@as(?u8, ','), p[0].file.dlm);
    try testing.expect(p[0].file.dsd);
    try testing.expectEqual(@as(?u8, ','), p[1].file.dlm); // DSD → comma default
    try testing.expectEqual(@as(?u8, null), p[2].file.dlm);
    try testing.expect(!p[2].file.dsd);

    // an unrecognized FILE option is a hard error, never a silent swallow.
    try testing.expectError(error.ParseError, prog(a, &diags, "file \"x.txt\" wombat;"));
}

/// Fold a purely-numeric expression tree to its value — a 20-line helper so the
/// multi-dim parser test can assert the flat-index arithmetic without an evaluator.
fn evalConst(e: *const ast.Expr) f64 {
    return switch (e.*) {
        .num => |n| n,
        .binary => |b| switch (b.op) {
            .add => evalConst(b.lhs) + evalConst(b.rhs),
            .sub => evalConst(b.lhs) - evalConst(b.rhs),
            .mul => evalConst(b.lhs) * evalConst(b.rhs),
            else => std.math.nan(f64),
        },
        else => std.math.nan(f64),
    };
}

test "array: parenthesized (n) dimension parses like {n}/[n]; init paren still follows (BUG-arrayparendim)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `(n)` dim + element list; and `(n)` dim + element list + trailing `(init)` —
    // position disambiguates the dim paren (before elements) from the init paren.
    const p = try prog(a, &diags, "array bits (3) b1-b3;\narray v (3) v1-v3 (10 20 30);");
    const d0 = p[0].array;
    try testing.expectEqual(@as(usize, 3), d0.elements.len);
    try testing.expectEqualStrings("b1", d0.elements[0]);
    try testing.expectEqualStrings("b3", d0.elements[2]);
    try testing.expectEqual(@as(usize, 0), d0.inits.len); // no initial values
    const d1 = p[1].array;
    try testing.expectEqual(@as(usize, 3), d1.elements.len);
    try testing.expectEqual(@as(usize, 3), d1.inits.len); // the trailing (init) list
    try testing.expectEqual(@as(f64, 20), d1.inits[1].num);
}

test "do over ARR desugars to an iterative array loop (ARR-doover)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "array a{3} a1-a3 (5 10 15);\ndo over a; a = a + 1; end;");
    // a `drop _i_;` is prepended (the implicit index is not emitted) — find the DO
    var dov: @TypeOf(p[0].do_) = undefined;
    for (p) |st| if (st == .do_) {
        dov = st.do_;
    };
    // header became `do _i_ = 1 to 3`
    try testing.expect(dov.header == .iter);
    try testing.expectEqual(@as(f64, 1), dov.header.iter.start.num);
    try testing.expectEqual(@as(f64, 3), dov.header.iter.stop.num);
    // body `a = a + 1` became `a{_i_} = a{_i_} + 1`
    try testing.expect(dov.body[0] == .array_assign);
    try testing.expectEqualStrings("a", dov.body[0].array_assign.array.name);
    // the index of the subscripted lvalue is the synthetic loop variable
    try testing.expectEqualStrings(dov.header.iter.name, dov.body[0].array_assign.array.index.variable);
}

test "do over ARR with explicit {lo:hi} bounds iterates lo..hi (FEAT-doover)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "array b{2:4} b2-b4 (10 20 30);\ndo over b; s + b; end;");
    // locate the desugared DO (an explicit-bounds ARRAY may emit extra stmts)
    var dov: @TypeOf(p[0].do_) = undefined;
    var found = false;
    for (p) |st| if (st == .do_) {
        dov = st.do_;
        found = true;
    };
    try testing.expect(found);
    try testing.expect(dov.header == .iter);
    try testing.expectEqual(@as(f64, 2), dov.header.iter.start.num); // lower bound honored
    try testing.expectEqual(@as(f64, 4), dov.header.iter.stop.num);
    try testing.expect(!diags.hasErrors());
}

test "abort variants parse distinctly; junk fails LOUD (BUG-abortreturncode)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "abort;\nx=1;\nabort abend;\nabort abend 9;\nabort return 8;\nabort 3;\nabort return;");
    try testing.expect(!diags.hasErrors());
    try testing.expect(p[0] == .abort and p[0].abort == .plain);
    try testing.expectEqual(@as(?u8, null), p[2].abort.abend);
    try testing.expectEqual(@as(?u8, 9), p[3].abort.abend);
    try testing.expectEqual(@as(u8, 8), p[4].abort.n);
    try testing.expectEqual(@as(u8, 3), p[5].abort.n);
    // `abort return;` (no n) is LEGAL — the syntax's <n> is optional and the
    // doc's own z/OS example runs it bare; no-n RETURN = "a condition code
    // that indicates an error" → default 1, ABEND-no-n's exec-side default
    // (GAP-ebnfholes-tick356; Statements Ref printed p.16/18/19).
    try testing.expectEqual(@as(u8, 1), p[6].abort.n);

    // ambiguous/garbage ABORT is a captured parse ERROR (D-003), never a silent STOP
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "abort banana;"));
    try testing.expect(d2.hasErrors());
    // a NON-number after RETURN stays the loud typo it always was — the no-n
    // default fires only at `;` (a silently-misparsed ABORT is a fail-fast
    // that never fires).
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, "abort return banana;"));
    try testing.expect(d3.hasErrors());
    var d4 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d4, "abort return 300;"));
    try testing.expect(d4.hasErrors());
}

test "do over of a non-array name fails LOUD via captured reporter (FEAT-doover, D-002)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // x is a plain variable, not an array → hard parse ERROR, never a silent skip
    try testing.expectError(error.ParseError, prog(a, &diags, "x = 1;\ndo over x; y = 2; end;"));
    try testing.expect(diags.hasErrors()); // captured diagnostic (D-003), not a spawned abort

    // a {*}-bound array has no constant bounds for the desugar → also loud
    var diags2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags2, "array s{*} s1-s2;\ndo over s; y = 2; end;"));
    try testing.expect(diags2.hasErrors());
}

test "character array: `$` marks members char; numeric array does not (CHARARRAY)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "array w{3} $ w1-w3 (\"a\" \"b\" \"c\");\narray n{2} n1-n2;");
    const cdecl = p[0].array;
    try testing.expect(cdecl.type == .char);
    try testing.expectEqual(@as(usize, 3), cdecl.elements.len);
    try testing.expectEqualStrings("w1", cdecl.elements[0]);
    try testing.expectEqualStrings("c", cdecl.inits[2].str);

    try testing.expect(p[1].array.type == .num); // no `$` → numeric, unchanged
}

test "assignment and a trailing run;" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "x = 1 + 2; run;");
    try testing.expectEqual(@as(usize, 1), p.len); // run; is swallowed
    try testing.expectEqualStrings("x", p[0].assign.target);
    try testing.expect(p[0].assign.value.binary.op == .add);
}

test "OF operator expands a var list into function args (G-ofoperator)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // sum(of x1-x3) → sum(x1, x2, x3); mean(of a b c) → mean(a, b, c)
    const p = try prog(a, &diags, "r = sum(of x1-x3); m = mean(of a b c); n = sum(of _numeric_);");
    const sumc = p[0].assign.value.call;
    try testing.expectEqualStrings("sum", sumc.name);
    try testing.expectEqual(@as(usize, 3), sumc.args.len);
    try testing.expectEqualStrings("x1", sumc.args[0].variable);
    try testing.expectEqualStrings("x3", sumc.args[2].variable);

    try testing.expectEqual(@as(usize, 3), p[1].assign.value.call.args.len);
    try testing.expectEqualStrings("b", p[1].assign.value.call.args[1].variable);

    // _numeric_ passes through as a single arg for the evaluator to expand
    const nc = p[2].assign.value.call;
    try testing.expectEqual(@as(usize, 1), nc.args.len);
    try testing.expectEqualStrings("_numeric_", nc.args[0].variable);
}

test "UPDATE / MODIFY parse into dataset-ref lists (G-update)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // update/modify read rows, so a leading `_setobs_` drop is injected — find
    // the statements by tag rather than by a fixed index.
    const p = try prog(a, &diags, "update master trans; by id; modify master;");
    var upd: ?[]const []const u8 = null;
    var mod: ?[]const []const u8 = null;
    for (p) |s| switch (s) {
        .update => |u| upd = u,
        .modify => |m| mod = m,
        else => {},
    };
    try testing.expectEqual(@as(usize, 2), upd.?.len);
    try testing.expectEqualStrings("master", upd.?[0]);
    try testing.expectEqualStrings("trans", upd.?[1]);
    try testing.expectEqual(@as(usize, 1), mod.?.len);
    try testing.expectEqualStrings("master", mod.?[0]);
}

test "UPDATEMODE= parses to a NUL-sentinel; unknown value fails loud (GAP-updatemode)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "update m t updatemode=nomissingcheck; by id;");
    var upd: ?[]const []const u8 = null;
    for (p) |s| switch (s) {
        .update => |u| upd = u,
        else => {},
    };
    try testing.expectEqual(@as(usize, 3), upd.?.len);
    try testing.expectEqualStrings("\x00updatemode=nomissingcheck", upd.?[2]);

    // MISSINGCHECK is the default: parses clean, carries nothing.
    const p2 = try prog(a, &diags, "update m t updatemode=missingcheck; by id;");
    var upd2: ?[]const []const u8 = null;
    for (p2) |s| switch (s) {
        .update => |u| upd2 = u,
        else => {},
    };
    try testing.expectEqual(@as(usize, 2), upd2.?.len);

    // Unknown mode fails loud (never silently default to MISSINGCHECK).
    try testing.expectError(error.ParseError, prog(a, &diags, "update m t updatemode=bogus; by id;"));
    // …and on SET it stays an unsupported option (UPDATE-only in SAS).
    try testing.expectError(error.ParseError, prog(a, &diags, "set m updatemode=nomissingcheck;"));
}

test "MODIFY/SET KEY= fails LOUD with a clear indexed-access message (GAP-modifykey)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // KEY= is recognized as a statement option (never parsed as a dataset/variable)
    // and rejected with a specific indexed-access diagnostic — opensas has no
    // dataset-index layer to build the keyed lookup on. Assert via the CAPTURED
    // reporter, never a spawned process.
    try testing.expectError(error.ParseError, prog(a, &diags, "modify master key=id;"));
    try testing.expect(diags.hasErrors());
    try testing.expectEqualStrings("modify KEY= (indexed access) is not supported yet", diags.list.items[diags.list.items.len - 1].message);

    var diags2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags2, "set master key=id;"));
    try testing.expectEqualStrings("set KEY= (indexed access) is not supported yet", diags2.list.items[diags2.list.items.len - 1].message);

    // …and the failure stays step-local: a later clean step still parses.
    var diags3 = diag.Diagnostics.init(a);
    const p = try prog(a, &diags3, "y = 1;");
    try testing.expectEqual(@as(usize, 1), p.len);
}

test "NOTE-removenamedds: named REMOVE/REPLACE fails loud NAMING the statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `remove a;` used to fall through to parseAssign → "expected '=' in
    // assignment" — the wrong construct entirely. Assert via the CAPTURED
    // reporter, never a spawned process (D-003).
    var diags = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags, "remove a;"));
    try testing.expectEqualStrings("remove with a named data set is not supported (only the bare remove; MODIFY-step form)", diags.list.items[diags.list.items.len - 1].message);

    var diags2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags2, "replace a;"));
    try testing.expect(std.mem.indexOf(u8, diags2.list.items[diags2.list.items.len - 1].message, "replace with a named data set") != null);

    // bare `remove;` (the MODIFY form) still parses — the two must not disagree
    var diags3 = diag.Diagnostics.init(a);
    _ = try prog(a, &diags3, "remove;");
    try testing.expect(!diags3.hasErrors());

    // `remove` is still an ordinary variable name: `remove = 5;` is an assignment
    var diags4 = diag.Diagnostics.init(a);
    const p = try prog(a, &diags4, "remove = 5;");
    try testing.expectEqualStrings("remove", p[0].assign.target);
}

test "BUG-missingstmtwrongclass: DATA-step MISSING is a NAMED rc-2 gap, not an assignment error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `missing A B;` used to fall through to parseAssign → "expected '=' in
    // assignment" — rc 1 naming the WRONG construct. Now it names MISSING and
    // flags the gap (rc 2, D-009/D-009b(i)). Assert via the CAPTURED reporter,
    // never a spawned process (D-003).
    diag.resetGap();
    var diags = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags, "missing A B;"));
    try testing.expectEqualStrings("the MISSING statement (special missing values) is not supported", diags.list.items[diags.list.items.len - 1].message);
    try testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diags.hasErrors()));

    // `missing = 5;` is still an ordinary assignment (variable named missing).
    var diags2 = diag.Diagnostics.init(a);
    const p = try prog(a, &diags2, "missing = 5;");
    try testing.expectEqualStrings("missing", p[0].assign.target);
}

test "GAP-inputcoldecimal F10: column input `.decimals` is a NAMED rc-2 gap (printed p.183), not a ';' error" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `input x 1-5 .2;` used to die "expected ';' after input" (rc 1, blaming
    // punctuation) — the parameter is VALID SAS (SAS 9.4 DATA Step Statements:
    // Reference, INPUT Statement: Column, printed p.183). Now it names the
    // parameter and flags the gap (rc 2, D-009/D-009b(i)).
    diag.resetGap();
    var diags = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags, "input x 1-5 .2;"));
    try testing.expectEqualStrings("input: the column-input .decimals parameter (input x 1-5 .2;) is not supported", diags.list.items[diags.list.items.len - 1].message);
    try testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diags.hasErrors()));

    // the plain column range still parses — no parameter consumed, no gap
    diag.resetGap();
    var diags2 = diag.Diagnostics.init(a);
    _ = try prog(a, &diags2, "input x 1-5 y $ 6-10;");
    try testing.expect(!diags2.hasErrors() and !diag.gapHit());

    // `.decimals` on a `$` item is not valid SAS → the user's rc 1, no gap flag
    diag.resetGap();
    var diags3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags3, "input x $ 1-5 .2;"));
    try testing.expect(!diag.gapHit());
}

test "if/then/else and subsetting if" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "if x < 5 then y = 1; else y = 2;\nif z;");
    try testing.expectEqual(@as(usize, 2), p.len);

    const iff = p[0].if_;
    try testing.expect(iff.cond.binary.op == .lt);
    try testing.expectEqualStrings("y", iff.then_branch.?.assign.target);
    try testing.expectEqual(@as(f64, 2), iff.else_branch.?.assign.value.num);

    const sub = p[1].if_; // subsetting if → both branches null
    try testing.expect(sub.then_branch == null);
    try testing.expect(sub.else_branch == null);
    try testing.expectEqualStrings("z", sub.cond.variable);
}

test "do loops: iterative with by, and do while" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "do i = 1 to 10 by 2; x = i; output; end;");
    try testing.expectEqual(@as(usize, 1), p.len);
    const it = p[0].do_.header.iter;
    try testing.expectEqualStrings("i", it.name);
    try testing.expectEqual(@as(f64, 1), it.start.num);
    try testing.expectEqual(@as(f64, 10), it.stop.num);
    try testing.expectEqual(@as(f64, 2), it.by.?.num);
    try testing.expectEqual(@as(usize, 2), p[0].do_.body.len);

    const w = try prog(a, &diags, "do while (x < 5); x = x + 1; end;");
    try testing.expect(w[0].do_.header == .while_);
    try testing.expect(w[0].do_.header.while_.binary.op == .lt);
}

test "combined iterative DO desugars while/until to an if-leave guard (DO-whileiter)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // WHILE → iter header + `if not (cond) then leave;` prepended to the body.
    const w = try prog(a, &diags, "do i = 1 to 5 while(i < 4); x = i; end;");
    try testing.expect(w[0].do_.header == .iter);
    try testing.expectEqual(@as(usize, 2), w[0].do_.body.len); // guard + `x=i`
    const g = w[0].do_.body[0].if_;
    try testing.expect(g.cond.unary.op == .not); // WHILE leaves when cond is false
    try testing.expect(g.then_branch.?.* == .leave);
    try testing.expect(w[0].do_.body[1] == .assign);

    // UNTIL → guard appended after the body, and NOT negated.
    const u = try prog(a, &diags, "do j = 1 to 5 until(j >= 3); y = j; end;");
    try testing.expect(u[0].do_.header == .iter);
    try testing.expect(u[0].do_.body[0] == .assign); // body first
    const gu = u[0].do_.body[1].if_; // guard last
    try testing.expect(gu.cond.binary.op == .ge); // UNTIL leaves when cond is true (no `not`)
    try testing.expect(gu.then_branch.?.* == .leave);
}

test "output / drop / keep / set / retain" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "set old; drop a b; keep c; retain x 0 y; output out;");
    // a `drop _setobs_;` is prepended because the step has a SET (io sets that helper)
    try testing.expectEqual(@as(usize, 6), p.len);
    try testing.expectEqualStrings("_setobs_", p[0].drop[0]);
    try testing.expectEqualStrings("old", p[1].set[0]);
    try testing.expectEqual(@as(usize, 2), p[2].drop.len);
    try testing.expectEqualStrings("c", p[3].keep[0]);

    const ret = p[4].retain;
    try testing.expectEqual(@as(usize, 2), ret.len);
    try testing.expectEqual(@as(f64, 0), ret[0].init.?.num); // x 0
    try testing.expect(ret[1].init == null); // y (no initial)

    try testing.expectEqualStrings("out", p[5].output[0]);
}

test "retain: MORE initial values than variables fails LOUD (NOTE-retainexcessinit)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // parenthesised excess → captured ParseError (D-003), never a silent drop
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "retain a b (1 2 3);"));
    try testing.expect(d1.hasErrors());
    // bare excess → same ERROR
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "retain a b 1 2 3;"));
    try testing.expect(d2.hasErrors());

    // controls: exact count binds positionally, FEWER stays legal (rest no init),
    // a bare SINGLE value still seeds every element (GH#51)
    var d3 = diag.Diagnostics.init(a);
    const p = try prog(a, &d3, "retain a b c (1 2 3); retain d e f (1 2); retain g h 7;");
    try testing.expect(!d3.hasErrors());
    const exact = p[0].retain;
    try testing.expectEqual(@as(usize, 3), exact.len);
    for (exact, 1..) |it, i| try testing.expectEqual(@as(f64, @floatFromInt(i)), it.init.?.num);
    const fewer = p[1].retain;
    try testing.expectEqual(@as(f64, 1), fewer[0].init.?.num);
    try testing.expectEqual(@as(f64, 2), fewer[1].init.?.num);
    try testing.expect(fewer[2].init == null); // f: no init
    const seed = p[2].retain;
    try testing.expectEqual(@as(f64, 7), seed[0].init.?.num);
    try testing.expectEqual(@as(f64, 7), seed[1].init.?.num); // single value seeds all
}

test "input, datalines and put" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const src =
        "input name $ age;\n" ++
        "put 'age=' age /;\n" ++
        "datalines;\n" ++
        "Ann 30\n" ++
        "Bo 25\n" ++
        ";\n";
    const p = try prog(a, &diags, src);
    try testing.expectEqual(@as(usize, 3), p.len);

    const in = p[0].input;
    try testing.expectEqual(@as(usize, 2), in.len);
    try testing.expect(in[0].type == .char); // name $
    try testing.expect(in[1].type == .num); // age

    const put = p[1].put;
    try testing.expectEqualStrings("age=", put[0].literal);
    try testing.expectEqualStrings("age", put[1].variable.name);
    try testing.expect(put[1].variable.fmt == null);
    try testing.expect(put[2] == .newline);

    const dl = p[2].datalines;
    try testing.expectEqual(@as(usize, 2), dl.len);
    try testing.expectEqualStrings("Ann 30", dl[0]);
    try testing.expectEqualStrings("Bo 25", dl[1]);
}

test "INPUT stmt `?`/`??` error-suppression modifier parses and is dropped (GAP-inputstmtqq)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `??` before the informat was a hard parse error ("expected ';' after
    // input"); opensas INPUT is already silent-missing on bad data, so the
    // marker is dropped and the informat still applies.
    const p = try prog(a, &diags, "input x ?? 3. y ? 5. z $;");
    try testing.expect(!diags.hasErrors());
    const in = p[0].input;
    try testing.expectEqual(@as(usize, 3), in.len);
    try testing.expectEqualStrings("x", in[0].name);
    try testing.expectEqualStrings("3", in[0].informat.?[0..1]); // numeric informat kept
    try testing.expectEqualStrings("y", in[1].name);
    try testing.expect(in[2].type == .char); // z $
}

test "column & formatted INPUT: ranges, informats, / pointer (G-input)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "input id 1-3 name $ 4-11 d date9. amt comma8. / z;");
    const in = p[0].input;
    try testing.expectEqual(@as(usize, 6), in.len);
    try testing.expectEqualStrings("@1-3", in[0].informat.?); // column range
    try testing.expect(in[1].type == .char);
    try testing.expectEqualStrings("@4-11", in[1].informat.?); // char column range
    try testing.expectEqualStrings("date9.", in[2].informat.?); // formatted informat
    try testing.expectEqualStrings("comma8.", in[3].informat.?);
    try testing.expectEqualStrings("/", in[4].informat.?); // line pointer
    try testing.expect(in[5].informat == null); // plain list var after the `/`
}

test "SET where= keeps string literals through option serialization (BUG-datawhere-char)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // The string must survive re-serialization (re-quoted); else the executor
    // re-lexes `where=(sev = )` and the char filter silently drops out.
    const p = try prog(a, &diags, "set src(where=(sev = \"SEVERE\"));");
    try testing.expect(std.mem.indexOf(u8, setNameOf(p), "\"SEVERE\"") != null);

    const p2 = try prog(a, &diags, "set src(where=(sev in (\"A\",\"B\")));");
    const n2 = setNameOf(p2);
    try testing.expect(std.mem.indexOf(u8, n2, "\"A\"") != null);
    try testing.expect(std.mem.indexOf(u8, n2, "\"B\"") != null);
}

fn setNameOf(p: ast.Program) []const u8 {
    for (p) |s| if (s == .set) return s.set[0];
    return "";
}

test "SET nobs= desugars to `v = _setobs_`; end= rides the name list as a sentinel" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `set a nobs=n end=e;` → drop _setobs_ ; set a "\x00end=e" ; n = _setobs_
    const p = try prog(a, &diags, "set a nobs=n end=e; x = 1;");
    try testing.expect(p[0] == .drop); // prepended _setobs_ drop
    try testing.expectEqualStrings("_setobs_", p[0].drop[0]);
    try testing.expectEqualStrings("a", p[1].set[0]); // options are not dataset names
    try testing.expectEqual(@as(usize, 2), p[1].set.len); // "a" + the end= sentinel
    try testing.expectEqualStrings("\x00end=e", p[1].set[1]); // exec pulls this out
    // nobs= injected right after the set
    try testing.expectEqualStrings("n", p[2].assign.target);
    try testing.expectEqualStrings("_setobs_", p[2].assign.value.variable);
    try testing.expectEqualStrings("x", p[3].assign.target); // no stray stmt from the options
}

test "SET/MERGE unknown option (KEY=/CUROBS=) fails LOUD; supported ones stay quiet (BUG-setunknownopt)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `set m key=id;` used to drop key= and read m sequentially → wrong data at
    // rc=0. Now a captured parse ERROR (D-002/D-003), never a silent drop.
    try testing.expectError(error.ParseError, prog(a, &diags, "set m key=id;"));
    try testing.expect(diags.hasErrors());

    var diags2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags2, "merge a b curobs=c;"));
    try testing.expect(diags2.hasErrors());

    // Supported statement options (nobs=/end=/point=) + parenthesized dataset
    // options (keep=/where= route through serializeParens) are untouched.
    var diags3 = diag.Diagnostics.init(a);
    const p = try prog(a, &diags3, "set m(keep=id where=(id > 1)) nobs=n end=e point=p;");
    try testing.expect(!diags3.hasErrors());
    try testing.expectEqualStrings("\x00point=p", p[1].set[2]); // sentinel still rides along
}

test "sum statement desugars to retain 0 + var = sum(var, expr)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "total + x; total + 5;");
    // each `total + e;` → total = sum(total, e)
    const asn = p[0].assign;
    try testing.expectEqualStrings("total", asn.target);
    try testing.expectEqualStrings("sum", asn.value.call.name);
    try testing.expectEqual(@as(usize, 2), asn.value.call.args.len);
    try testing.expectEqualStrings("total", asn.value.call.args[0].variable);
    try testing.expectEqualStrings("x", asn.value.call.args[1].variable);
    // one retain 0 rides right AFTER the first sum statement (deduped — the
    // second adds none): the var's PDV slot belongs at the sum statement's
    // textual position (first-mention, Language Reference: Concepts p.478 Fig. 20.2 — QA tick377 F2),
    // not hoisted to the top of the step.
    try testing.expect(p[1] == .retain);
    try testing.expectEqual(@as(usize, 1), p[1].retain.len);
    try testing.expectEqualStrings("total", p[1].retain[0].name);
    try testing.expectEqual(@as(f64, 0), p[1].retain[0].init.?.num);
    try testing.expectEqual(@as(f64, 5), p[2].assign.value.call.args[1].num);
}

test "length statement truncates char assignments via __assignc desugar" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "length code $ 3; code = \"ABCDEF\"; x = 5;");
    // stmt 0 is the inert length node (empty drop)
    try testing.expect(p[0] == .drop);
    try testing.expectEqual(@as(usize, 0), p[0].drop.len);
    // stmt 1: code = __assignc("ABCDEF", 3)  — truncation desugar (was substr;
    // __assignc also renders a numeric rhs BESTn. right-justified, BUG-numcharwidth)
    const asn = p[1].assign;
    try testing.expectEqualStrings("code", asn.target);
    try testing.expectEqualStrings("__assignc", asn.value.call.name);
    try testing.expectEqual(@as(usize, 2), asn.value.call.args.len);
    try testing.expectEqualStrings("ABCDEF", asn.value.call.args[0].str);
    try testing.expectEqual(@as(f64, 3), asn.value.call.args[1].num);
    // stmt 2: x is not length-declared → plain assignment, no wrap
    try testing.expect(p[2].assign.value.* == .num);
}

test "length applies to EVERY var in a multi-var group (BUG-lenmulti)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `length a b c $ 3;` — all three must truncate, not just c.
    const p = try prog(a, &diags, "length a b c $ 3; a = \"hello\"; b = \"world\"; c = \"abcde\";");
    for (p[1..4]) |s| {
        try testing.expectEqualStrings("__assignc", s.assign.value.call.name); // each wrapped
        try testing.expectEqual(@as(f64, 3), s.assign.value.call.args[1].num); // length 3
    }
}

test "put with formats and a format statement" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // put items reconstruct their format spec across uneven tokenization
    const p = try prog(a, &diags, "put x 8.2 n comma10.2 d date9. mm mmddyy10.;");
    const put = p[0].put;
    try testing.expectEqual(@as(usize, 4), put.len);
    try testing.expectEqualStrings("8.2", put[0].variable.fmt.?);
    try testing.expectEqualStrings("comma10.2", put[1].variable.fmt.?);
    try testing.expectEqualStrings("date9.", put[2].variable.fmt.?);
    try testing.expectEqualStrings("mmddyy10.", put[3].variable.fmt.?);

    // `format` statement: one format applies to every preceding un-formatted var
    const f = try prog(a, &diags, "format x y comma8. d date9.;");
    const items = f[0].format;
    try testing.expectEqual(@as(usize, 3), items.len);
    try testing.expectEqualStrings("x", items[0].name);
    try testing.expectEqualStrings("comma8.", items[0].fmt);
    try testing.expectEqualStrings("comma8.", items[1].fmt); // y shares it
    try testing.expectEqualStrings("d", items[2].name);
    try testing.expectEqualStrings("date9.", items[2].fmt);
}

test "put +n/#n/-R desugar to spaces/newlines/fmt-marker (GAP-putcolptr+putalign)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // +3 → a literal of 3 spaces; #3 (from line 1) → two newlines to reach line 3.
    const p = try prog(a, &diags, "put a +3 b; put a #3 b;");
    const p1 = p[0].put;
    try testing.expect(p1[0] == .variable);
    try testing.expectEqualStrings("   ", p1[1].literal); // +3
    try testing.expect(p1[2] == .variable);
    const p2 = p[1].put;
    try testing.expect(p2[0] == .variable);
    try testing.expect(p2[1] == .newline); // #3 from line 1 …
    try testing.expect(p2[2] == .newline); // … two newlines
    try testing.expect(p2[3] == .variable);

    // -R / -L prepend the alignment marker onto the item's format.
    const q = try prog(a, &diags, "put x 6. -L; put y $6. -R;");
    try testing.expectEqualStrings("<6.", q[0].put[0].variable.fmt.?); // -L → '<'
    try testing.expectEqualStrings(">$6.", q[1].put[0].variable.fmt.?); // -R → '>'
}

test "input &/~/x= and put trailing @/@@ fail loud, naming the modifier (GAP-inputmods/GAP-puthold)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // Each unsupported modifier is a hard ERROR whose message names it —
    // never a bare "expected ';'" that hides WHAT failed.
    try testing.expectError(error.ParseError, prog(a, &diags, "input x & $;"));
    try testing.expectEqualStrings("input: the & modifier (list input of values with embedded blanks) is not supported", diags.list.items[diags.list.items.len - 1].message);
    try testing.expectError(error.ParseError, prog(a, &diags, "input x ~ $;"));
    try testing.expectEqualStrings("input: the ~ modifier (list input of quoted values) is not supported", diags.list.items[diags.list.items.len - 1].message);
    try testing.expectError(error.ParseError, prog(a, &diags, "input x=;"));
    try testing.expectEqualStrings("input: named input (x=) is not supported", diags.list.items[diags.list.items.len - 1].message);
    try testing.expectError(error.ParseError, prog(a, &diags, "put x @;"));
    try testing.expectEqualStrings("put: only an integer @n or @(expression) column pointer is supported — no trailing-@ line hold or @'string' search", diags.list.items[diags.list.items.len - 1].message);
    // GAP-atexpression-put landed `@(expression)` (Statements printed p.269) but
    // NOT its `@numeric-variable` neighbour one entry above (`a=15; put @a name
    // $10.;`) — that stays a LOUD gap, pinned here so it can never start silently
    // meaning something else. `@(a)` is the supported spelling of the same thing.
    try testing.expectError(error.ParseError, prog(a, &diags, "put @a x;"));
    try testing.expectEqualStrings("put: only an integer @n or @(expression) column pointer is supported — no trailing-@ line hold or @'string' search", diags.list.items[diags.list.items.len - 1].message);
    _ = try prog(a, &diags, "put @(a) x; put @(a*3+1) x; put @(1+2) 'lit';"); // the parenthesised form parses
    try testing.expectError(error.ParseError, prog(a, &diags, "put x @@;"));
    try testing.expectEqualStrings("put: trailing @@ (output line hold across iterations) is not supported", diags.list.items[diags.list.items.len - 1].message);

    // `?`/`??` stay accepted: opensas INPUT is already silent-missing on bad
    // data, so the suppression markers change nothing (GAP-inputstmtqq).
    _ = try prog(a, &diags, "input x ?; input y ??; input z ?? 3.;");
}

test "put OVERPRINT directive fails loud, not a phantom uninit var (BUG-putoverprint)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // OVERPRINT is a PUT directive keyword — reject at the item position rather
    // than parse it as an uninitialized variable "overprint" (bogus '.').
    try testing.expectError(error.ParseError, prog(a, &diags, "put overprint \"x\";"));
    try testing.expectEqualStrings("PUT OVERPRINT is not supported yet", diags.list.items[diags.list.items.len - 1].message);

    // Control: a normal variable whose name merely contains "over" is untouched.
    _ = try prog(a, &diags, "put over; put \"text\" a;");
}

test "D-009: a recognized-but-unsupported syntax gap exits 2, a real syntax error exits 1 (GAP-gapsexitingone)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Each of these is VALID SAS 9.4 opensas doesn't implement — an opensas
    // gap (failGap → markGap) → exit 2, "file an opensas issue". The parse
    // still fails LOUD with the same ERROR message; only the rc signal moves
    // 1 → 2. Pinned against exitCode directly because no fixture surface can
    // pin an rc today (audit-exitcodecontract.md §6/I1).
    const gaps = [_][]const u8{
        "input x & $;", // & list-input modifier
        "input x ~ $;", // ~ list-input modifier
        "input x=;", // named input
        "put overprint \"x\";", // PUT OVERPRINT directive
        "put x @@;", // trailing @@ output-line hold
        "by groupformat age;", // BY GROUPFORMAT
        "modify master key=id;", // MODIFY KEY= indexed access
        "remove a;", // named REMOVE (multi-dataset MODIFY form)
        // BUG-missingstmtwrongclass: the MISSING statement (Language Reference: Concepts printed
        // p.519, a worked example TWICE) is valid SAS opensas doesn't
        // implement — named rc-2 gap, never the rc-1 "expected '=' in
        // assignment" fall-through. Message pinned in the dedicated test below.
        "missing A B;", // MISSING statement, DATA-step site
        // GAP-inputcoldecimal F10: column input's trailing `.decimals`
        // parameter (printed p.183) is valid SAS — named rc-2 gap, never the
        // rc-1 "expected ';' after input" fall-through.
        "input x 1-5 .2;", // INPUT column-input .decimals parameter
        "array m[2,3] m1-m6; d = dim(m, y);", // runtime dim index (parser_expr)
        // GAP-putptrslice: the PUT pointer-control family — each valid SAS 9.4
        // (Statements Table 2.5; format-list pointer controls per p.293) but
        // unimplemented, so the conflated guards SPLIT: these recognized forms
        // route to failGap while the catch-all arms below stay rc 1.
        "put +x a;", // +numeric-variable
        "put +(x) a;", // +(expression)
        "put #x a;", // #numeric-variable
        "put #(x) a;", // #(expression)
        "put (a b)(+x 4. 5.);", // group format-list +numeric-variable
        "put (a b)(@x 4. 5.);", // group format-list @numeric-variable
        "put (a b)(@(x) 4. 5.);", // group format-list @(expression)
        "put @x a;", // @numeric-variable
        "put a @;", // trailing @ output line hold
        // GAP-inputpointerguard: INPUT's `+`/`#` pointer guards — same split as
        // the PUT family above, against Statements Table 2.3 (INPUT pointer
        // controls, printed p.174). These used to fall THROUGH the guard to
        // `expected ';'` (rc 1 blaming punctuation); now failGap, rc 2.
        "input +x a;", // +numeric-variable
        "input +(x) a;", // +(expression)
        "input #x a;", // #numeric-variable
        "input #(x) a;", // #(expression)
        // GAP-infileoptrc (3b/3c): INFILE UNBUFFERED/UNBUF (printed p.138) and
        // EOF= (printed p.130) are documented options opensas hasn't written —
        // split out of the INFILE catch-all, which keeps rc 1 for typos only.
        "infile \"f\" unbuffered;", // INFILE UNBUFFERED
        "infile \"f\" unbuf;", // alias UNBUF
        "infile \"f\" eof=done;", // INFILE EOF=variable
        "infile datalines eof=done;", // instream spelling of the same gap
        // GAP-infileeov: EOV=variable (same printed p.130 entry as EOF=) —
        // the leftover of that landing, now pinned at the same rc 2.
        "infile \"f\" eov=v;", // INFILE EOV=variable
        "infile datalines eov=v;", // instream spelling
        // GAP-ebnfholes-tick356: PAD (printed p.135, marker "=== pdf 146 ===")
        // and DLMSTR= (printed p.128, marker "=== pdf 139 ===") — documented,
        // unimplemented, same split off the catch-all. NOPAD, the documented
        // DEFAULT of the same entry, is accepted-inert (pinned below at rc 0).
        "infile \"f\" pad;", // INFILE PAD
        "infile datalines pad;", // instream spelling
        "infile \"f\" dlmstr='~!';", // INFILE DLMSTR= (multi-char delimiter)
        "infile datalines dlmstr='~!';", // instream spelling
    };
    for (gaps) |src| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &d, src));
        try testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }

    // The SAME five pointer guards keep rc 1 for what real SAS 9.4 also
    // rejects — a typo must not be re-tagged as a gap (D-009b: rc reports the
    // class in real-SAS terms). `@'string'` string search is INPUT-only
    // (Table 2.3, not in PUT's Table 2.5) — same decision GAP-atexpression-put
    // made for `@(character-expression)`; the rest are plain garbage.
    const user_errors = [_][]const u8{
        "put +'a' x;", // no `+'string'` form exists
        "put #'a' x;", // no `#'string'` form exists
        "put (a b)(+'a' 4. 5.);", // group garbage
        "put (a b)(@'a' 4. 5.);", // group `@'string'`
        "put @'ab' a;", // @'character-string' — INPUT-only
        // GAP-inputpointerguard: the SAME two INPUT guards keep rc 1 for what
        // real SAS 9.4 also rejects — Table 2.3 has no `+'string'`/`#'string'`
        // form (only `@'character-string'` exists, and opensas implements it).
        "input +'a' x;", // no `+'string'` form exists
        "input #'a' x;", // no `#'string'` form exists
        "infile \"f\" unbuff;", // typo of UNBUFFERED — the catch-all keeps rc 1
        "infile \"f\" eoff=x;", // typo of EOF= — same
        "infile \"f\" eovv=v;", // typo of EOV= — same (EOV= itself is pinned above)
        "infile \"f\" padd;", // typo of PAD — the catch-all keeps rc 1
        "infile \"f\" dlmstrr='x';", // typo of DLMSTR= — same
        "s = sum(of :);", // a colon NOT after a name is not the prefix form (GAP-ofcolonprefix)
    };
    for (user_errors) |src| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &d, src));
        try testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }

    // Controls keep rc 1 and rc 0 reachable from the parser: `abort xyz;` is a
    // genuine syntax error (outside SAS's whole ABEND/RETURN/n list) → the
    // USER's rc 1; a clean parse → 0.
    diag.resetGap();
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "abort xyz;"));
    try testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d1.hasErrors()));
    diag.resetGap();
    var d0 = diag.Diagnostics.init(a);
    _ = try prog(a, &d0, "y = 1;");
    try testing.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d0.hasErrors()));
    // `@'string'` IS a documented INPUT pointer control (Table 2.3,
    // `@'character-string'` — the flip side of it being rc 1 in PUT) and
    // opensas implements it (GAP-inputatstring): a clean parse, rc 0.
    diag.resetGap();
    var d0b = diag.Diagnostics.init(a);
    _ = try prog(a, &d0b, "input @'ab' a;");
    try testing.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d0b.hasErrors()));
    // NOPAD — the documented DEFAULT of the PAD|NOPAD entry (printed p.135):
    // accepted-inert, not a gap and not a typo → clean parse, rc 0.
    diag.resetGap();
    var d0c = diag.Diagnostics.init(a);
    _ = try prog(a, &d0c, "infile \"f\" nopad;");
    try testing.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d0c.hasErrors()));
    diag.resetGap();
}

test "hash: declare + method calls parse to hash nodes" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "declare hash h(); h.defineKey(\"k\"); rc = h.find(key: 1);");
    try testing.expectEqual(@as(usize, 3), p.len);

    try testing.expectEqualStrings("h", p[0].hash_decl.name);

    const m = p[1].hash_op; // h.defineKey("k")  — statement form, no target
    try testing.expect(m.target == null);
    try testing.expectEqualStrings("h", m.obj);
    try testing.expectEqualStrings("defineKey", m.method);
    try testing.expectEqual(@as(usize, 1), m.args.len);
    try testing.expect(m.args[0].name == null); // positional
    try testing.expectEqualStrings("k", m.args[0].value.str);

    const f = p[2].hash_op; // rc = h.find(key: 1)  — expression form, target rc
    try testing.expectEqualStrings("rc", f.target.?);
    try testing.expectEqualStrings("find", f.method);
    try testing.expectEqualStrings("key", f.args[0].name.?); // named
    try testing.expectEqual(@as(f64, 1), f.args[0].value.num);
}

test "hash: `h = _new_ hash(...)` desugars to hash_decl; other _new_ targets fail loud (GAP-hashnew)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const p = try prog(a, &diags, "declare hash h; h = _new_ hash(ordered:'a');");
    try testing.expectEqual(@as(usize, 2), p.len);
    try testing.expectEqual(@as(usize, 0), p[0].hash_decl.args.len); // bare declare
    const c = p[1].hash_decl; // the _new_ assignment — same AST as `declare hash h(...)`
    try testing.expectEqualStrings("h", c.name);
    try testing.expectEqual(@as(usize, 1), c.args.len);
    try testing.expectEqualStrings("ordered", c.args[0].name.?);

    // `_new_ hiter('h')` desugars to the SAME hash_decl `declare hiter
    // hi('h')` produces (GAP-hashnewhiter — Language Reference: Concepts p.624 states the equivalence);
    // the two spellings cannot drift because there is one AST and one exec path.
    const hi1 = try prog(a, &diags, "declare hiter hi('h');");
    const hi2 = try prog(a, &diags, "hi = _new_ hiter('h');");
    try testing.expectEqualDeep(hi1[0].hash_decl, hi2[0].hash_decl);

    // any other `_new_` target stays a loud parse error.
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "x = _new_ javaobj('h');"));
}

test "hash attributes: parenless num_items/item_size parse as hash ops; do-bound hoists (GAP-hashnumitems)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `n = h.num_items;` — the parenless attribute form (Language Reference: Concepts p.623) is a hash
    // op with an empty arg list, no longer a hard parse error.
    const p = try prog(a, &diags, "n = h.num_items; s = h.item_size; m = h.num_items();");
    try testing.expectEqual(@as(usize, 3), p.len);
    const attr = p[0].hash_op;
    try testing.expectEqualStrings("n", attr.target.?);
    try testing.expectEqualStrings("h", attr.obj);
    try testing.expectEqualStrings("num_items", attr.method);
    try testing.expectEqual(@as(usize, 0), attr.args.len);
    try testing.expectEqualStrings("item_size", p[1].hash_op.method);
    try testing.expectEqual(@as(usize, 0), p[1].hash_op.args.len);
    // the paren method form keeps working — same shape
    try testing.expectEqualStrings("num_items", p[2].hash_op.method);
    try testing.expectEqual(@as(usize, 0), p[2].hash_op.args.len);

    // `do i = 1 to h.num_items;` — the attribute read is hoisted before the
    // loop into a temp the bound references; a prefix drop keeps the temp out
    // of the output dataset.
    const q = try prog(a, &diags, "do i = 1 to h.num_items; x = i; end;");
    try testing.expectEqual(@as(usize, 2), q.len);
    try testing.expectEqualStrings("__hashattr:", q[0].drop[0]);
    const wrap = q[1].do_;
    try testing.expect(wrap.header == .simple);
    try testing.expectEqual(@as(usize, 2), wrap.body.len);
    const hoist = wrap.body[0].hash_op;
    try testing.expectEqualStrings("__hashattr_1", hoist.target.?);
    try testing.expectEqualStrings("h", hoist.obj);
    try testing.expectEqualStrings("num_items", hoist.method);
    const it = wrap.body[1].do_.header.iter;
    try testing.expectEqualStrings("i", it.name);
    try testing.expectEqualStrings("__hashattr_1", it.stop.variable);
}

test "BUG-hashattrput: a hash attribute in a PUT item fails loud (not two NOTE-only variables)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `put h.num_items=;` and the parenless list form both used to mis-parse
    // into `.variable h` + a second item — plausible output, NOTE-only
    // diagnostics. Now the same loud failure `h.num_items` gets anywhere else.
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "put h.num_items=;"));
    try testing.expect(std.mem.indexOf(u8, d1.list.items[0].message, "h.num_items") != null);
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "put h.num_items;"));
    // …while ordinary PUT items with dotted FORMATS are untouched by the guard.
    var d3 = diag.Diagnostics.init(a);
    const p = try prog(a, &d3, "put x comma10.2; put y=; put x date9. y;");
    try testing.expectEqual(@as(usize, 3), p.len);
    try testing.expectEqualStrings("comma10.2", p[0].put[0].variable.fmt.?);
    try testing.expectEqualStrings("date9.", p[2].put[0].variable.fmt.?);
    try testing.expectEqualStrings("y", p[2].put[1].variable.name);
}

test "var_list: the name: prefix form in an OF argument parses to a synthetic __ofprefix arg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // GAP-ofcolonprefix: `sum(of x:)` is valid SAS (Language Reference: Concepts printed p.70
    // Table 4.5). The prefix can't expand at parse time (no PDV), so the AST
    // carries a synthetic `__ofprefix("x")` call arg for eval to expand.
    var d1 = diag.Diagnostics.init(a);
    const p1 = try prog(a, &d1, "s = sum(of x:);");
    const sum_args = p1[0].assign.value.call.args;
    try testing.expectEqual(@as(usize, 1), sum_args.len);
    try testing.expect(sum_args[0] == .call);
    try testing.expectEqualStrings("__ofprefix", sum_args[0].call.name);
    try testing.expectEqualStrings("x", sum_args[0].call.args[0].str);

    // …mid-list, mixed with the honored forms, and two prefixes in one call.
    var d2 = diag.Diagnostics.init(a);
    const p2 = try prog(a, &d2, "s = sum(of a x: b y1-y2); t = mean(of x: y:);");
    const mixed = p2[0].assign.value.call.args;
    try testing.expectEqual(@as(usize, 5), mixed.len);
    try testing.expectEqualStrings("a", mixed[0].variable);
    try testing.expectEqualStrings("__ofprefix", mixed[1].call.name);
    try testing.expectEqualStrings("b", mixed[2].variable);
    try testing.expectEqualStrings("y1", mixed[3].variable);
    try testing.expectEqualStrings("y2", mixed[4].variable);
    const two = p2[1].assign.value.call.args;
    try testing.expectEqualStrings("x", two[0].call.args[0].str);
    try testing.expectEqualStrings("y", two[1].call.args[0].str);

    // a colon NOT after a name is not the prefix form — still loud (rc 1).
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, "s = sum(of :);"));
    // the previously honored forms are untouched.
    var d4 = diag.Diagnostics.init(a);
    _ = try prog(a, &d4, "s = sum(of x1-x3); t = mean(of a b c);");
}

test "where parses to its own pre-read node; select to an if/else chain" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // where → a dedicated engine-filter node (NOT a subsetting if: end=/first./
    // last. must see the filtered stream — exec.applyWhereStmt)
    const w = try prog(a, &diags, "where x > 10;");
    try testing.expect(w[0] == .where_);
    try testing.expect(w[0].where_.binary.op == .gt);

    // select (g) with two whens + otherwise → nested if/else, selector = value
    const p = try prog(a, &diags, "select (g); when (1) a = 1; when (2) a = 2; otherwise a = 9; end;");
    try testing.expectEqual(@as(usize, 1), p.len);
    const outer = p[0].if_;
    try testing.expect(outer.cond.binary.op == .eq); // g = 1
    try testing.expectEqualStrings("g", outer.cond.binary.lhs.variable);
    try testing.expectEqual(@as(f64, 1), outer.cond.binary.rhs.num);
    try testing.expectEqualStrings("a", outer.then_branch.?.assign.target);
    const inner = outer.else_branch.?.if_; // else if g = 2
    try testing.expectEqual(@as(f64, 2), inner.cond.binary.rhs.num);
    try testing.expectEqual(@as(f64, 9), inner.else_branch.?.assign.value.num); // otherwise
}

test "syntax errors report through Diagnostics" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    try testing.expectError(error.ParseError, prog(a, &diags, "x 1;")); // missing '='
    try testing.expect(diags.hasErrors());
    try testing.expectError(error.ParseError, prog(a, &diags, "do i = 1 to 3; x = i;")); // no end
}

test "GAP-batch-qa107: DATA-step BY DESCENDING/NOTSORTED parse to sentinel-encoded names" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // plain ascending BY still parses cleanly (baseline — no regression).
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by k1 k2;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqual(@as(usize, 2), p[0].by.len);
        try testing.expectEqualStrings("k1", p[0].by[0]);
    }
    // BY DESCENDING k → the var rides with a \x00D prefix (descending key),
    // NOT grouping by an undefined "DESCENDING" var (BUG-bydescending).
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by descending k;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqual(@as(usize, 1), p[0].by.len);
        try testing.expectEqualStrings("\x00Dk", p[0].by[0]);
    }
    // mixed: `by a descending b;` — a plain, b descending.
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by a descending b;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqualStrings("a", p[0].by[0]);
        try testing.expectEqualStrings("\x00Db", p[0].by[1]);
    }
    // BY k NOTSORTED → trailing \x00notsorted sentinel, not a "NOTSORTED" var.
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by k notsorted;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqual(@as(usize, 2), p[0].by.len);
        try testing.expectEqualStrings("k", p[0].by[0]);
        try testing.expectEqualStrings("\x00notsorted", p[0].by[1]);
    }
    // a dangling DESCENDING (no variable after it) still fails loud.
    {
        var diags = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &diags, "by k descending;"));
        try testing.expect(diags.hasErrors());
    }
}

test "GAP-arraybounds-batch: negative array lower bound parses and folds bounds" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // array b[-2:2] — 5 members; lbound/hbound/dim const-fold to -2/2/5.
    const p = try prog(a, &diags, "array b[-2:2] b1-b5; l = lbound(b); h = hbound(b); d = dim(b);");
    try testing.expect(!diags.hasErrors());
    try testing.expectEqual(@as(usize, 5), p[0].array.elements.len);
    try testing.expectEqual(@as(f64, -2), p[1].assign.value.num);
    try testing.expectEqual(@as(f64, 2), p[2].assign.value.num);
    try testing.expectEqual(@as(f64, 5), p[3].assign.value.num);

    // a fully-negative range works too; an inverted range still fails loud.
    const q = try prog(a, &diags, "array c[-5:-2] c1-c4;");
    try testing.expectEqual(@as(usize, 4), q[0].array.elements.len);
    try testing.expectError(error.ParseError, prog(a, &diags, "array d[2:-2] d1-d4;"));
    // a bare negative count `{-3}` is nonsense — fail loud, not a silent dim.
    try testing.expectError(error.ParseError, prog(a, &diags, "array e[-3] e1-e3;"));
}

test "GAP-arraybounds-batch: dimN/hboundN/lboundN digit-suffix aliases desugar to two-arg" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // dim2(m) ≡ dim(m,2) → const-folds to the 2nd dimension's size (3); the
    // digit-suffixed bounds follow the same fold on an explicit lower bound.
    const p = try prog(a, &diags, "array m[2,3] m1-m6; d1 = dim1(m); d2 = dim2(m); h2 = hbound2(m); l1 = lbound1(m);");
    try testing.expect(!diags.hasErrors());
    try testing.expectEqual(@as(f64, 2), p[1].assign.value.num);
    try testing.expectEqual(@as(f64, 3), p[2].assign.value.num);
    try testing.expectEqual(@as(f64, 3), p[3].assign.value.num);
    try testing.expectEqual(@as(f64, 1), p[4].assign.value.num);

    const q = try prog(a, &diags, "array b[-2:2] b1-b5; l = lbound1(b); h = hbound1(b);");
    try testing.expectEqual(@as(f64, -2), q[1].assign.value.num);
    try testing.expectEqual(@as(f64, 2), q[2].assign.value.num);

    // an out-of-range suffix fails loud, same as dim(a, 9) does.
    try testing.expectError(error.ParseError, prog(a, &diags, "array m[2,3] m1-m6; d = dim9(m);"));
}

test "GAP-bygroupformat: BY GROUPFORMAT fails loud, not a phantom var" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // plain ascending BY still parses cleanly (baseline — no regression).
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by age;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqual(@as(usize, 1), p[0].by.len);
        try testing.expectEqualStrings("age", p[0].by[0]);
    }
    // BY GROUPFORMAT age → captured ParseError naming GROUPFORMAT, NOT
    // grouping by a bogus "groupformat" variable (silent-wrong).
    {
        var diags = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &diags, "by groupformat age;"));
        try testing.expect(diags.hasErrors());
        try testing.expect(std.mem.indexOf(u8, try diags.render(), "GROUPFORMAT is not yet supported") != null);
    }
    // trailing position too; and BY DESCENDING now parses (GAP-batch-qa107) —
    // it no longer trips the loud error and never reaches the GROUPFORMAT arm.
    {
        var diags = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &diags, "by age groupformat;"));
        try testing.expect(diags.hasErrors());
    }
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by descending age;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqualStrings("\x00Dage", p[0].by[0]);
    }
}

test "BUG-bystmtempty: `by;` (zero variables) fails loud rc-1-side; legal BY forms untouched" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `by;` — the literal empty spelling. EBNF by_stmt requires >= 1 var, so
    // this is a user error (ParseError → rc 1, D-009b), never a silent no-op.
    {
        var diags = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &diags, "by;"));
        try testing.expect(diags.hasErrors());
        try testing.expect(std.mem.indexOf(u8, try diags.render(), "BY statement requires at least one variable") != null);
    }
    // `by notsorted;` — NOTSORTED is a modifier, not a variable: still zero
    // vars, still an error (and the sentinel must not mask the check).
    {
        var diags = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &diags, "by notsorted;"));
        try testing.expect(diags.hasErrors());
    }
    // `by descending;` keeps its own, more specific message (pre-existing).
    {
        var diags = diag.Diagnostics.init(a);
        try testing.expectError(error.ParseError, prog(a, &diags, "by descending;"));
        try testing.expect(std.mem.indexOf(u8, try diags.render(), "BY DESCENDING must be followed by a variable name") != null);
    }
    // Controls (D-014: over-rejecting a legal BY is worse than the bug):
    // plain, descending, and multi-var + NOTSORTED all still parse.
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by age;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqual(@as(usize, 1), p[0].by.len);
    }
    {
        var diags = diag.Diagnostics.init(a);
        const p = try prog(a, &diags, "by descending a b notsorted;");
        try testing.expect(!diags.hasErrors());
        try testing.expectEqualStrings("\x00Da", p[0].by[0]);
        try testing.expectEqualStrings("b", p[0].by[1]);
        try testing.expectEqualStrings("\x00notsorted", p[0].by[2]);
    }
}

test "deep-nested DO fails loud past the ceiling, not a segfault (BUG-stmtnest-deepguard)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `do; do; … x=1; … end; end;` a few hundred levels past the ceiling — the
    // guard trips (captured ParseError) long before the native stack overflows.
    const n = pe.Parser.max_depth + 200;
    var src: std.ArrayList(u8) = .empty;
    for (0..n) |_| try src.appendSlice(a, "do; ");
    try src.appendSlice(a, "x = 1; ");
    for (0..n) |_| try src.appendSlice(a, "end; ");

    var diags = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &diags, src.items));
    try testing.expect(diags.hasErrors());

    // The else-if chain recurses parseStmt→parseIf→parseStmt with no DO at
    // all — the old parseDo-only guard missed it entirely (segfault).
    var chain: std.ArrayList(u8) = .empty;
    try chain.appendSlice(a, "if x then y = 1; ");
    for (0..n) |_| try chain.appendSlice(a, "else if x then y = 1; ");
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, chain.items));
    try testing.expect(d3.hasErrors());

    // A reasonably-nested DO (50 deep) still parses fine — guard isn't too tight.
    var ok_src: std.ArrayList(u8) = .empty;
    for (0..50) |_| try ok_src.appendSlice(a, "do; ");
    try ok_src.appendSlice(a, "x = 1; ");
    for (0..50) |_| try ok_src.appendSlice(a, "end; ");
    var ok = diag.Diagnostics.init(a);
    const p = try prog(a, &ok, ok_src.items);
    try testing.expectEqual(@as(usize, 1), p.len);
    try testing.expect(p[0] == .do_);
}

test "select: no OTHERWISE desugars to a fail-loud terminal else; OTHERWISE keeps its branch (BUG-selectnomatch)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // No OTHERWISE: a no-match must reach the loud `.select_nomatch` node, not null.
    const p = try prog(a, &diags, "select (x); when (1) x=1; when (2) x=2; end;");
    try testing.expect(p[0] == .if_); // if x=1 …
    const inner = p[0].if_.else_branch.?.*; // else if x=2 …
    try testing.expect(inner == .if_);
    try testing.expect(inner.if_.else_branch.?.* == .select_nomatch);

    // WITH OTHERWISE: the terminal else is the OTHERWISE statement, never select_nomatch.
    const q = try prog(a, &diags, "select (x); when (1) x=1; otherwise x=9; end;");
    try testing.expect(q[0].if_.else_branch.?.* != .select_nomatch);
}

test "select: WHEN or a 2nd OTHERWISE after OTHERWISE fails LOUD (BUG-selectwhenafterother)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // WHEN after OTHERWISE → hard parse ERROR, never a silently-reordered branch.
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "select (x); when (1) x=1; otherwise x=9; when (5) x=5; end;"));
    try testing.expect(d1.hasErrors()); // captured diagnostic (D-003), not a spawned abort

    // A second OTHERWISE is the same violation.
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "select (x); otherwise x=1; otherwise x=2; end;"));
    try testing.expect(d2.hasErrors());

    // WHENs in any order among themselves + trailing OTHERWISE stay valid.
    var d3 = diag.Diagnostics.init(a);
    _ = try prog(a, &d3, "select (x); when (2) x=2; when (1) x=1; otherwise; end;");
    try testing.expect(!d3.hasErrors());
}

test "array: explicit dimension must match the explicit member count (BUG-arraydimmembercount)" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // dim 5 vs 3 members → hard ERROR (was silently overridden by the member count).
    var d1 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d1, "array a{5} x y z;"));
    try testing.expect(d1.hasErrors());

    // dim 2 vs 3 members → same ERROR, the other direction.
    var d2 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d2, "array a{2} x y z;"));
    try testing.expect(d2.hasErrors());

    // multi-dim: product 2*2=4 vs 3 members → ERROR.
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, "array a{2,2} x y z;"));
    try testing.expect(d3.hasErrors());

    // lo:hi span {0:2} = 3 elements vs 2 members → ERROR.
    var d4 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d4, "array a{0:2} x y;"));
    try testing.expect(d4.hasErrors());

    // Legal forms stay legal: matching dim, `{*}`, dim-only auto-gen, multi-dim
    // match, lo:hi match, _temporary_, and the _numeric_ special list.
    var ok = diag.Diagnostics.init(a);
    _ = try prog(a, &ok,
        \\array a{3} x y z;
        \\array s{*} x y z;
        \\array g{5};
        \\array m{2,2} w x y z;
        \\array b{0:2} x y z;
        \\array t{4} _temporary_;
        \\array v{*} _numeric_;
    );
    try testing.expect(!ok.hasErrors());
}

test "global-statement predicates: D-014a layering holds (hoisted ⊂ global; inert ∩ global = ∅; skippable == hoisted ∪ inert ∪ libname)" {
    // BUG-filenamemidstep: filename/ods joined the hoist — every isGlobalKw
    // member is now EXECUTED mid-step (hoisted ∪ pre-pass), so no skip arm
    // anywhere can silent-no-op one (D-014a closed).
    const hoisted = [_][]const u8{ "title", "TITLE2", "footnote", "footnote10", "options", "filename", "ods" };
    const inert = [_][]const u8{ "run", "quit", "dm", "goptions", "sasfile", "catname", "page", "skip", "resetline", "sysecho", "checkpoint", "lock", "axis", "axis1", "legend12", "pattern255", "symbol1", "symbol255" };
    const neither = [_][]const u8{ "missing", "endsas", "zzzq", "var", "symbolize", "axle", "titlex", "footnote100", "symbol2555" };
    for (hoisted) |t| {
        try testing.expect(isHoistedGlobalKw(t));
        try testing.expect(isGlobalKw(t)); // hoisted ⊂ global
        try testing.expect(!isInertGlobalKw(t));
        try testing.expect(isMidStepSkippable(t));
    }
    // LIBNAME: never hoisted, but EXECUTED mid-step by the up-front
    // parseLibnames pre-pass — skipping the leftover tokens is honest
    // (BUG-libnamemidstepboth: it both ran and errored).
    try testing.expect(isGlobalKw("libname"));
    try testing.expect(!isHoistedGlobalKw("libname"));
    try testing.expect(!isInertGlobalKw("libname"));
    try testing.expect(isMidStepSkippable("libname"));
    for (inert) |t| {
        try testing.expect(isInertGlobalKw(t));
        try testing.expect(!isGlobalKw(t)); // inert ∩ global = ∅
        try testing.expect(!isHoistedGlobalKw(t));
        try testing.expect(isMidStepSkippable(t));
    }
    for (neither) |t| {
        try testing.expect(!isGlobalKw(t));
        try testing.expect(!isHoistedGlobalKw(t));
        try testing.expect(!isInertGlobalKw(t));
        try testing.expect(!isMidStepSkippable(t));
    }
}

test "NOTE-pagemidstep: inert globals parse clean mid-DATA-step; `page = 5;` stays an assignment" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // QA tick322 F6: `page;` mid-DATA-step fell through to parseAssign and
    // died with "expected '=' in assignment", naming the wrong construct.
    // The inert set is accepted in open code (Language Reference: Concepts p.209 log-only family),
    // so agree here (D-014a) — all batch-unobservable, they leave NO ast.
    var ok = diag.Diagnostics.init(a);
    const p = try prog(a, &ok, "x = 1; page; skip; goptions reset=all; symbol1 v=dot; lock; y = 2;");
    try testing.expect(!ok.hasErrors());
    try testing.expectEqual(@as(usize, 2), p.len); // only the two assignments

    // positive control: `page = 5;` is a plain ASSIGNMENT and `skip:` a GOTO
    // LABEL (ctl_goto.sas pins it end-to-end) — the positive-match guard
    // keeps identifiers that merely SHARE an inert keyword out of the swallow.
    var d2 = diag.Diagnostics.init(a);
    const q = try prog(a, &d2, "page = 5; goto skip; skip: y = 2;");
    try testing.expect(!d2.hasErrors());
    try testing.expectEqual(@as(usize, 4), q.len); // assign, goto, label, assign
    try testing.expect(q[0] == .assign);
    try testing.expectEqualStrings("page", q[0].assign.target);
    try testing.expect(q[2] == .label);
    try testing.expectEqualStrings("skip", q[2].label);

    // a genuinely unknown statement mid-DATA-step STILL fails loud (the
    // point of the original fix — the inert agreement must not widen).
    var d3 = diag.Diagnostics.init(a);
    try testing.expectError(error.ParseError, prog(a, &d3, "zzzq 5;"));
    try testing.expect(d3.hasErrors());
}

test "BUG-xstmtsilentnoop: X and DM-to-a-FILE emit a NOTE instead of vanishing; the rest of the inert set stays silent and no rc moves" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // X: an OS command with a FILESYSTEM side effect. It stays UNEXECUTED (settled
    // by design), but the silence was the D-002 violation — `x "mkdir /tmp/d";`
    // produced zero output at rc 0 and no directory.
    // Quoted form only — the bare-name command form is accepted here today but
    // whether it STAYS accepted is GH#83 part 2's call (it owns main.zig, where
    // the open-code recognizer disagrees with this one), so nothing here pins it.
    for ([_][]const u8{"x \"mkdir /tmp/d\";"}) |src| {
        var d = diag.Diagnostics.init(a);
        const p = try prog(a, &d, src);
        try testing.expectEqual(@as(usize, 1), p.len); // still parsed, still inert
        try testing.expect(p[0] == .null_stmt);
        try testing.expectEqual(@as(usize, 1), d.count());
        // A NOTE, NOT an error: an ERROR here would errhalt (BUG-errhalt) and skip
        // every later step of any program that legitimately carries an X — the D-014
        // failure. The exit code must not move.
        try testing.expectEqual(diag.Severity.note, d.list.items[0].severity);
        try testing.expect(!d.hasErrors());
        try testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "X statement not executed") != null);
    }

    // DM's log/output REDIRECTION form is the other observable member: a downstream
    // log check reads a file nobody wrote. Both spellings — command inside a string,
    // and bare name tokens.
    for ([_][]const u8{ "dm log \"file '/tmp/f.log' replace;\";", "dm log file f;", "dm 'out;file x'; " }) |src| {
        var d = diag.Diagnostics.init(a);
        _ = try prog(a, &d, src);
        try testing.expectEqual(@as(usize, 1), d.count());
        try testing.expectEqual(diag.Severity.note, d.list.items[0].severity);
        try testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "DM statement not executed") != null);
    }

    // NEGATIVE CONTROL, and the load-bearing one: everything the inert set is
    // genuinely justified by ("cannot observe") must STAY SILENT — most of all
    // `dm 'log;clear;output;clear'`, whose "output" contains "out". A substring
    // match would have noted the commonest DM idiom in the corpus for nothing.
    var d2 = diag.Diagnostics.init(a);
    _ = try prog(a, &d2, "dm 'log;clear;output;clear'; dm 'wpgm;editor'; page; skip; run; goptions reset=all; sasfile w.d load; lock w.d;");
    try testing.expectEqual(@as(usize, 0), d2.count());

    // …and the identifiers that merely share the keyword keep their meaning.
    var d3 = diag.Diagnostics.init(a);
    const q = try prog(a, &d3, "x = 1; dm = x + 1;");
    try testing.expectEqual(@as(usize, 0), d3.count());
    try testing.expectEqual(@as(usize, 2), q.len);
    try testing.expect(q[0] == .assign);
    try testing.expect(q[1] == .assign);
}
