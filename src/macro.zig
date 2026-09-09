//! Macro preprocessor — source-to-source, run before the lexer (main.zig calls
//! `expand` on the raw `.sas` text; the lexer/parser/exec then see the result).
//!
//! A single left-to-right scan over the source. Most characters pass through
//! verbatim; two sigils are special:
//!   `&name`            → replaced by the macro variable's value (a trailing
//!                        `.` is a consumed delimiter: `&x.y` → value-of-x + "y")
//!   `%word …`          → a macro statement or call:
//!     `%let n = v;`                     define a macro variable (value is
//!                                       macro-expanded and blank-trimmed)
//!     `%macro m(a,b); … %mend;`         define a macro
//!     `%m(x,y)`                         invoke it: bind params, expand the body
//!     `%if c %then A; %else B;`         evaluate `c`, expand the taken branch
//!                                       (a branch may be `%do; … %end;`)
//!
//! ponytail — deliberately NOT the full SAS macro facility:
//!   * one global symbol table (no `%local`/`%global`, no nested `%macro`)
//!   * `&x`/`%x` inside SINGLE quotes resolve in macro-statement text only
//!     (the SAS rule — see `sq_masks_triggers`); compiler-bound single-quoted
//!     strings stay inert, also the SAS rule (printed p.38).
//!   * `%eval` is integer-only (`**` exponentiates); `%sysevalf` covers floats.
//!     `%do i=… %to …` and `%do %while/%until` iterate; `%global`/`%local` share
//!     the one global table (no real scoping). `%sysfunc` supports a string-fn
//!     subset. No `&&` indirection, autocall, or string-aware keyword scanning.

const std = @import("std");
const diag = @import("diag.zig");
const lex = @import("lexer.zig"); // bindVars re-resolves &vars inside string tokens
const functions = @import("functions.zig"); // %sysfunc routes to the DATA-step table
const eval = @import("eval.zig");
const format = @import("format.zig"); // %sysfunc output-format apply + error suppression
const Pdv = @import("pdv.zig").Pdv;
const Value = @import("value.zig").Value;

const Error = std.mem.Allocator.Error;

const SavedVar = struct { name: []const u8, prev: ?[]const u8 };
/// One macro invocation's local symbol table. `owner` is the invoked macro's
/// name, UPPERCASED, because `%PUT _USER_`/`_LOCAL_` print it as the scope column
/// — SAS names the owning macro there, never the word LOCAL (NOTE-userscopename).
const Scope = struct {
    owner: []const u8,
    vars: std.ArrayList(SavedVar) = .empty,
    /// printed p.77 rule 2 case 3: the body CONTAINS a computed %GOTO, so CALL
    /// SYMPUT treats this frame as nonempty even when `vars` is empty.
    computed_goto: bool = false,
};
const Param = struct { name: []const u8, default: []const u8, is_keyword: bool };
const Macro = struct { params: []const Param, body: []const u8, pbuff: bool = false, minop: bool = false, mindelim: u8 = ' ', has_mindelim: bool = false };

/// Cap on macro-invocation nesting. A recursive macro (`%macro r; %r %mend; %r`)
/// otherwise recurses forever through handleCall→process→handleCall and
/// overflows the stack (segfault). 400 is far beyond any real nesting yet well
/// under the frame count that overflows an 8 MB stack.
const max_macro_depth = 400;
/// Backstop for `%do %while/%until` — a runaway condition (never falsified by the
/// body) stops here instead of looping forever.
const max_loop_iters = 100_000;

/// Masked-ampersand sentinel (BUG-macronrstrmask). %nrstr/%nrbquote and the
/// Q-functions emit `&` as this byte so resolveAmpRun (which fires only on a
/// real '&') can never re-resolve it — the mask survives %let storage and any
/// number of later &var references, exactly like SAS quoting. Text LEAVING the
/// macro layer (expanded program text, %put log lines, the SYMGET mirror)
/// passes through unmaskTriggers to render it back as '&'.
/// ponytail: the CLI late-bind (resolveVarsIn over CALL SYMPUT vars)
/// runs on UNMASKED text, so a masked '&x' whose x is ALSO a symput var would
/// bind late; %let-only vars (the common case) are not in that store.
const mask_amp: u8 = 0x01;
/// Masked-percent sentinel (BUG-macropctmask): a `%` folded by a quoting fn
/// (`%str(50%%)`) or masked by %nrstr/%nrbquote/%nrquote must survive storage
/// and rescan as a literal too — an unmasked stored `%` re-fires as a macro
/// call the next time the value flows through resolveText (`%let b=&a;`).
const mask_pct: u8 = 0x02;
/// Masked-comma sentinel (BUG-sysfunccommamask): a comma quoted by %str/%quote/
/// %nrstr & co. is NOT an argument delimiter — `%sysfunc(catx(%str(,),a,b,c))`
/// must join ON the comma, not split there. Masked by the quoting fns exactly
/// like '&'/'%', unmasked by unmaskTriggers on text leaving the macro layer and
/// at BOTH function-argument boundaries — %sysfunc's and the macro-function one
/// (%scan/%index/%verify & co.) — so the consumer sees the literal ',', per SAS.
/// That second boundary was missing and every byte-comparing macro fn searched
/// for the sentinel instead of the comma (BUG-macroscandelim).
/// Unquoted commas still split args normally.
const mask_comma: u8 = 0x03;
/// Masked-blank sentinel (BUG-macrogroupamasking): a blank quoted by %str & co.
/// is DATA, not a token separator — `%bquote(&s)` with `Susan's Office Supplies`
/// is ONE operand in the %IF condition (Macro Ref p.107-108's READIT example).
const mask_blank: u8 = 0x04;
/// The rest of Table 7.6 group A, one sentinel per masked character, so a quoted
/// operator reaches %EVAL/%IF as character data (printed p.162: %STR quotes the
/// comparison values AND and OR "so they are not ambiguous"). The bytes skip
/// 0x09-0x0D — those are real '\t' '\n' '\v' '\f' '\r' in SAS source, and the
/// first draft's contiguous range rewrote every newline to '>' on the way out.
const mask_plus: u8 = 0x05; // +
const mask_minus: u8 = 0x06; // -
const mask_star: u8 = 0x07; // *
const mask_slash: u8 = 0x08; // /
const mask_lt: u8 = 0x0E; // <
const mask_gt: u8 = 0x0F; // >
const mask_eq: u8 = 0x10; // =
const mask_caret: u8 = 0x11; // ^
const mask_bar: u8 = 0x12; // |
const mask_tilde: u8 = 0x13; // ~
const mask_semi: u8 = 0x14; // ;
const mask_hash: u8 = 0x15; // #
const mask_notsign: u8 = 0x16; // ¬ (the two bytes 0xC2 0xAC, masked as one)
/// Prefix marking the WHOLE FOLLOWING WORD as a masked mnemonic operator (AND
/// OR NOT EQ NE LE LT GE GT IN — group A's word half). The word's letters stay
/// verbatim after the prefix, so unmasking just drops the byte. NOT stays a
/// legal prefix operator and IN stays MINOPERATOR-conditional — masking only
/// ever touches QUOTED text; bare mnemonics are never rewritten.
const mask_word: u8 = 0x17;

/// True for any quoting-sentinel byte — the 0x01-0x17 range MINUS the real
/// whitespace control chars 0x09-0x0D, which appear verbatim in every program.
fn isSentinel(c: u8) bool {
    return c >= mask_amp and c <= mask_word and (c < '\t' or c > '\r');
}

/// True for a group A mnemonic operator word (Table 7.6), case-insensitively.
fn isMnemonic(w: []const u8) bool {
    const list = .{ "and", "or", "not", "eq", "ne", "le", "lt", "ge", "gt", "in" };
    inline for (list) |m| if (eqi(w, m)) return true;
    return false;
}

/// The one masking pass behind every quoting function (BUG-macrogroupamasking):
/// Table 7.6 group A — the specials `+ - * / < > = ¬ ^ | ~ ; , #` and blank,
/// plus the mnemonic operators as WHOLE words (`candy` keeps its `and`) — each
/// masked char REPLACED by its sentinel (a prefix would leave the real char to
/// act as an operator), each masked word prefixed by mask_word. `triggers`
/// additionally masks `&`/`%` (group B — the NR fns, %superq, and the Q-form
/// result quoting; %QSCAN's documented result list, printed p.338, is group A
/// plus `& % ' " ( )`). Existing sentinel bytes pass through untouched (nested
/// %str inside %str), so masking is idempotent. Borrowed slice back if nothing
/// masked. unmaskTriggers reverses it all at the text's exit points.
fn maskQuoted(a: std.mem.Allocator, s: []const u8, comptime triggers: bool) Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var changed = false;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        const sent: ?u8 = switch (c) {
            ' ' => mask_blank,
            '+' => mask_plus,
            '-' => mask_minus,
            '*' => mask_star,
            '/' => mask_slash,
            '<' => mask_lt,
            '>' => mask_gt,
            '=' => mask_eq,
            '^' => mask_caret,
            '|' => mask_bar,
            '~' => mask_tilde,
            ';' => mask_semi,
            '#' => mask_hash,
            ',' => mask_comma,
            '&' => if (triggers) mask_amp else null,
            '%' => if (triggers) mask_pct else null,
            else => null,
        };
        if (sent) |m| {
            try out.append(a, m);
            changed = true;
            i += 1;
            continue;
        }
        // `¬` is the two bytes 0xC2 0xAC (BUG-macroevalnotsign) — masked as one.
        if (c == 0xC2 and i + 1 < s.len and s[i + 1] == 0xAC) {
            try out.append(a, mask_notsign);
            changed = true;
            i += 2;
            continue;
        }
        if (isNameChar(c)) {
            var j = i;
            while (j < s.len and isNameChar(s[j])) j += 1;
            if (isMnemonic(s[i..j])) {
                try out.append(a, mask_word);
                changed = true;
            }
            try out.appendSlice(a, s[i..j]);
            i = j;
            continue;
        }
        try out.append(a, c);
        i += 1;
    }
    return if (changed) out.items else s;
}

/// Replace every real '&'/'%' plus all of group A with sentinels (borrowed
/// slice back if none) — the NR-fn / %superq / Q-form-result rule.
fn maskTriggers(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    return maskQuoted(a, s, true);
}

/// Group A only (BUG-macrogroupamasking): the .resolve quoting fns
/// (%str/%quote/%bquote) leave `&`/`%` resolved/live but mask group A — the
/// quoted comma/blank/operator/mnemonic is data, never syntax.
fn maskGroupA(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    return maskQuoted(a, s, false);
}

/// Render every quoting sentinel back to its literal character(s) for text
/// leaving the macro layer — expanded program text, %put lines, the SYMGET
/// mirror — and at BOTH function-argument boundaries (%sysfunc's and the
/// macro-function one). SAS unquotes an item as it leaves the word scanner
/// (Macro Ref printed p.113-114) and when %SCAN/%SUBSTR/%UPCASE return it
/// (p.114 + the %SCAN entry, printed p.338) — those boundaries are why
/// `%scan(%str(a b),1)` still sees the blank as a delimiter and returns `a`.
fn unmaskTriggers(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    var any = false;
    for (s) |c| if (isSentinel(c)) {
        any = true;
        break;
    };
    if (!any) return s;
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| switch (c) {
        mask_amp => try out.append(a, '&'),
        mask_pct => try out.append(a, '%'),
        mask_comma => try out.append(a, ','),
        mask_blank => try out.append(a, ' '),
        mask_plus => try out.append(a, '+'),
        mask_minus => try out.append(a, '-'),
        mask_star => try out.append(a, '*'),
        mask_slash => try out.append(a, '/'),
        mask_lt => try out.append(a, '<'),
        mask_gt => try out.append(a, '>'),
        mask_eq => try out.append(a, '='),
        mask_caret => try out.append(a, '^'),
        mask_bar => try out.append(a, '|'),
        mask_tilde => try out.append(a, '~'),
        mask_semi => try out.append(a, ';'),
        mask_hash => try out.append(a, '#'),
        mask_notsign => try out.appendSlice(a, "\xC2\xAC"),
        mask_word => {}, // the prefix marks; the word's letters were kept verbatim
        else => try out.append(a, c),
    };
    return out.items;
}

const State = struct {
    a: std.mem.Allocator,
    /// Values are OWNED malloc'd buffers (functions.VarVal), reused across
    /// overwrites — arena dupes here orphaned O(M²) RAM on `%let s=&s tok;`
    /// accumulation loops (PERF-macroaccum).
    vars: std.StringHashMapUnmanaged(functions.VarVal) = .empty,
    macros: std.StringHashMapUnmanaged(Macro) = .empty,
    diags: *diag.Diagnostics,
    call_depth: usize = 0,
    scopes: std.ArrayList(Scope) = .empty,
    /// Names already tried via autocall (SASAUTOS) this run — load each file at
    /// most once, matching SAS, and avoid re-reading on every unresolved call.
    autoload_attempted: std.StringHashMapUnmanaged(void) = .empty,
    /// Active `%goto LABEL` target (lowercased): while set, process() drops all
    /// output until it reaches `%LABEL:`, implementing macro-label early-return
    /// (a real date-conversion macro's `%GOTO EXIT` / `%EXIT:`). Cleared at the
    /// label or the macro boundary (a goto never escapes its macro).
    goto_target: ?[]const u8 = null,
    /// Set by `%return`: unwind the CURRENT macro's body immediately (nothing after
    /// the `%return` in the body runs). process() stops its scan at the next loop
    /// check and every enclosing %do/%if bails; handleCall clears it at the macro
    /// invocation boundary — a `%return` never escapes its macro (like goto_target).
    returning: bool = false,
    /// %ABORT halts the whole program. Set (alongside `returning`, to reuse every
    /// bail point) when %ABORT runs, and — unlike `returning` — NEVER cleared at
    /// the macro boundary, so the halt propagates all the way to the top-level
    /// scan: every statement after %ABORT is dropped from the expanded text and
    /// thus never lexed/executed (NOTE-macroloudlabels).
    aborting: bool = false,
    /// How many macro invocations are currently on the stack. Unlike call_depth
    /// (bumped by EVERY process() re-entry — nested %if branches, arg/%let text),
    /// this counts only handleCall bodies, so `%return` can tell whether it is
    /// inside a macro. `%return` in open code (depth 0) is invalid: it must warn
    /// visibly and NOT set `returning` (else it would silently swallow the rest of
    /// the program at exit 0 — the worst failure class). GH#4 open-code guard.
    macro_call_depth: usize = 0,
    /// MINOPERATOR gate for the `in`/`#` macro operator, and MINDELIMITER= for
    /// its list delimiter (BUG-macroinoperator). Sources: the system option
    /// (`OPTIONS MINOPERATOR [MINDELIMITER='c'];`, intercepted by process() at
    /// scan time — BUG-minoperatoropt) OR-ed per-invocation with the enclosing
    /// %MACRO definition's `/ minoperator` (and its MINDELIMITER= when given),
    /// restored on exit. SAS 9.4 default: NOMINOPERATOR — `in` is ordinary
    /// text (and thus a loud %EVAL parse error in %if/%eval). Blank delimiter.
    minoperator: bool = false,
    mindelimiter: u8 = ' ',
    /// True once seedAutomatics ran (GAP-macroautovars) — process() re-enters,
    /// the automatics are seeded exactly once per State.
    auto_seeded: bool = false,
    /// TRUE while scanning COMPILER-BOUND text (program source, macro bodies,
    /// %if/%do branch text): a single-quoted string there is a SAS string
    /// literal, and the word scanner does not pass &/% inside it to the macro
    /// processor — Macro Language Ref printed p.38 ("Macro Variable
    /// Reference": "Macro variable references that are enclosed in single
    /// quotation marks are not resolved", the TITLE-statement example) — so
    /// process() copies the quoted span verbatim. FALSE while scanning MACRO
    /// statement text via resolveText (%LET values, %PUT text, macro function
    /// arguments, %IF conditions): to the macro processor quotation marks are
    /// ordinary characters, and ONLY the NR quoting functions mask & and % —
    /// printed p.7 ("You must use a macro quoting function to mask the special
    /// characters", about assigning a value containing ampersands to a macro
    /// variable), Table 7.2 printed p.100 (`%name &name`: "%NRSTR, %NRBQUOTE,
    /// and %NRQUOTE mask these patterns"), printed p.342 ("In addition, %NRSTR
    /// also masks the following characters: & %"). This is the settled answer
    /// behind BUG-letsinglequoteampunresolved / NOTE-putsinglequoteamp: a
    /// single quote does NOT mask `&` in the macro language, only in SAS
    /// statements.
    sq_masks_triggers: bool = true,
    /// A Session is a real user-facing run; the free `expand` is the CLI setup
    /// pass (junk diags) or a unit test. %PUT writes a plain log line straight
    /// to stderr only in a real run (GAP-macroputnote); everywhere else it
    /// stays on the captured-diagnostics channel.
    plain_put: bool = false,
    /// Pooled expansion scratch for resolveText (PERF-resolvetextscratch).
    /// process() re-enters resolveText mid-scan (a %sysfunc/macro-fn arg
    /// resolving while an outer resolveText is still appending), so one shared
    /// buffer would be clobbered — each entry pops its OWN scratch and returns
    /// it after the result is copied out. Only the final arena dupe persists;
    /// scratch capacity is reused across calls instead of orphaning a fresh
    /// arena ArrayList per call (the other half of PERF-macroaccum's RSS).
    scratch_pool: std.ArrayList(std.ArrayList(u8)) = .empty,
    /// Interleaved execution (BUG-macrointerleave): when set, process() flushes the
    /// accumulated expanded text to `exec_fn` at each top-level `run;`/`quit;` step
    /// boundary and clears the buffer, so a step EXECUTES (its CALL SYMPUT vars land
    /// in the macro table) before the SAME macro body's later `%do &var` expands.
    /// Null (the setup pass, unit tests) = expand the whole body at once, no flush.
    exec_ctx: ?*anyopaque = null,
    exec_fn: ?*const fn (*anyopaque, []const u8) Error!void = null,

    /// Open the local symbol table for an invocation of macro `owner`.
    fn pushScope(st: *State, owner: []const u8) Error!void {
        try st.scopes.append(st.a, .{ .owner = try upperDup(st.a, owner) });
    }
    /// Record that `name` is local to the current macro scope, saving its prior
    /// value so popScope can restore it. No-op in open code (no scope on the stack).
    fn declareLocal(st: *State, name: []const u8) Error!void {
        if (st.scopes.items.len == 0) return;
        return st.declareLocalAt(st.scopes.items.len - 1, name);
    }
    /// `declareLocal` against a NAMED frame rather than the innermost one. CALL
    /// SYMPUT needs it: its variable lands in the closest NON-EMPTY symbol table,
    /// which may be an enclosing macro's rather than the current one (symputFrame).
    fn declareLocalAt(st: *State, idx: usize, name: []const u8) Error!void {
        const lname = try lowerDup(st.a, name);
        const fr = &st.scopes.items[idx].vars;
        for (fr.items) |sv| if (std.mem.eql(u8, sv.name, lname)) return;
        const prev: ?[]const u8 = if (st.vars.get(lname)) |v| try st.a.dupe(u8, v.get()) else null;
        try fr.append(st.a, .{ .name = lname, .prev = prev });
    }
    /// BUG-symputscope — where CALL SYMPUT puts its variable, per SAS 9.4 Macro
    /// Language: Reference, Fifth Edition, printed p.77 ("Special Cases of Scope
    /// with the CALL SYMPUT Routine"), rule 1:
    ///
    ///   "CALL SYMPUT creates the macro variable in the current symbol table
    ///    available while the DATA step is executing, provided that symbol table
    ///    is not empty. If it is empty (contains no local macro variables),
    ///    usually CALL SYMPUT creates the variable in the closest nonempty
    ///    symbol table."
    ///
    /// Returns the frame index that owns the variable, or null for "no nonempty
    /// local table" → GLOBAL. Emptiness is per-FRAME, so a parameterized macro
    /// (params are declareLocal'd) keeps its symput vars private while a
    /// parameter-less one (empty frame) leaks them to the global table — the
    /// doc's ENV1-vs-ENV3 contrast, and the whole subtlety of the rule.
    /// A frame also counts as nonempty when the macro CONTAINS a computed %GOTO
    /// (rule 2 case 3, `computed_goto`) — SYSPBUFF (case 2) needs no flag here
    /// because it is declareLocal'd at invocation, so it sits in `vars`.
    fn symputFrame(st: *State) ?usize {
        var i = st.scopes.items.len;
        while (i > 0) {
            i -= 1;
            const fr = &st.scopes.items[i];
            if (fr.vars.items.len > 0 or fr.computed_goto) return i;
        }
        return null;
    }
    /// BUG-symputxsymtab — replace the OUTER value that the outermost frame
    /// owning `name` saved, so `popScope` restores THIS value once the last
    /// shadow dies. That is how `CALL SYMPUTX(…,'G')` writes the global while a
    /// live local keeps shadowing it (printed p.307: "even if a local symbol
    /// table exists"). Outermost, not innermost: an inner frame's saved value is
    /// the enclosing LOCAL, which must still be restored on its own pop.
    /// Returns false when no frame owns the name — then it IS the global and the
    /// ordinary global write applies.
    fn setSavedOutermost(st: *State, name: []const u8, val: []const u8) bool {
        var kbuf: [256]u8 = undefined;
        if (name.len == 0 or name.len > kbuf.len) return false;
        const lname = std.ascii.lowerString(kbuf[0..name.len], name);
        for (st.scopes.items) |*fr| {
            for (fr.vars.items) |*sv| {
                if (!std.mem.eql(u8, sv.name, lname)) continue;
                sv.prev = st.a.dupe(u8, val) catch return false;
                return true;
            }
        }
        return false;
    }
    /// Pop the current scope, restoring (or removing) each local it captured.
    fn popScope(st: *State) void {
        const top = st.scopes.pop() orelse return;
        for (top.vars.items) |sv| {
            if (sv.prev) |pv| {
                st.putOwned(sv.name, pv) catch {};
                functions.setLetVar(sv.name, pv) catch {};
            } else {
                if (st.vars.fetchRemove(sv.name)) |kv| {
                    var v = kv.value;
                    v.deinit();
                }
                functions.setLetVar(sv.name, "") catch {};
            }
        }
    }

    fn setVar(st: *State, name: []const u8, val: []const u8) Error!void {
        try st.putOwned(name, val);
        // mirror to SYMGET/SYMEXIST (BUG-symgetlet) — unmasked: the DATA step
        // must see '&a', never the sentinel byte.
        try functions.setLetVar(name, try unmaskTriggers(st.a, val));
    }
    /// Overwrite `name` with an OWNED copy of `bytes`: the malloc'd buffer is
    /// reused/grown in place and the map key duped only on first insert, so a
    /// hot `%let s=&s tok;` loop orphans nothing in the arena (PERF-macroaccum).
    /// `bytes` must not alias the var's current buffer (getVar slices are
    /// consumed or snapshotted by callers before any setVar — see syscallSort).
    fn putOwned(st: *State, name: []const u8, bytes: []const u8) Error!void {
        var kbuf: [256]u8 = undefined;
        const lower: ?[]const u8 = if (name.len <= kbuf.len) std.ascii.lowerString(&kbuf, name) else null;
        const lname = lower orelse try lowerDup(st.a, name);
        if (st.vars.getPtr(lname)) |v| return v.set(bytes);
        var v: functions.VarVal = .{};
        try v.set(bytes);
        try st.vars.put(st.a, if (lower) |l| try st.a.dupe(u8, l) else lname, v);
    }
    /// Record a `&name` the scanner could not resolve, for the deferred warning
    /// `bindStepVars` emits if late binding never rescues it (`g_unresolved`).
    fn noteUnresolved(st: *State, name: []const u8) Error!void {
        var kbuf: [256]u8 = undefined;
        if (name.len == 0 or name.len > kbuf.len) return;
        const lname = std.ascii.lowerString(kbuf[0..name.len], name);
        if (g_unresolved.contains(lname)) return;
        try g_unresolved.put(st.a, try st.a.dupe(u8, lname), {});
    }
    fn getVar(st: *State, name: []const u8) ?[]const u8 {
        var buf: [256]u8 = undefined;
        if (name.len == 0 or name.len > buf.len) return null;
        for (name, 0..) |c, i| buf[i] = std.ascii.toLower(c);
        if (st.vars.getPtr(buf[0..name.len])) |v| return v.get();
        return null;
    }
    /// The SavedVar for `name` if it was declared %local in any ACTIVE scope
    /// (innermost declaration wins), else null. `prev != null` means the local
    /// shadows a pre-existing outer (global) value — SAS %SYMGLOBL still sees
    /// that global (BUG-macrosymglobl).
    fn findLocal(st: *State, name: []const u8) ?SavedVar {
        return (st.findLocalIn(name) orelse return null).sv;
    }
    /// `findLocal` plus WHICH frame owns the variable. `%PUT _USER_` needs the
    /// index for both halves of its scope column — the owning macro's name, and
    /// the innermost-outward ordering (NOTE-userscopename). Single loop; findLocal
    /// is the value-only view of it.
    fn findLocalIn(st: *State, name: []const u8) ?struct { idx: usize, sv: SavedVar } {
        var buf: [256]u8 = undefined;
        if (name.len == 0 or name.len > buf.len) return null;
        for (name, 0..) |c, i| buf[i] = std.ascii.toLower(c);
        const lname = buf[0..name.len];
        var i = st.scopes.items.len;
        while (i > 0) {
            i -= 1;
            for (st.scopes.items[i].vars.items) |sv|
                if (std.mem.eql(u8, sv.name, lname)) return .{ .idx = i, .sv = sv };
        }
        return null;
    }

    fn getMacro(st: *State, name: []const u8) ?Macro {
        var buf: [256]u8 = undefined;
        if (name.len == 0 or name.len > buf.len) return null;
        for (name, 0..) |c, i| buf[i] = std.ascii.toLower(c);
        return st.macros.get(buf[0..name.len]);
    }
};

/// Autocall (SASAUTOS) directory: when an invoked macro is undefined, look for
/// `<dir>/<name>.sas` (case-insensitively — real autocall libraries are mixed case),
/// compile it (which defines the macro), and retry. Set once by the CLI from
/// `--sasautos`/`$SASAUTOS`; null disables autocall (the warn-and-skip path).
var g_sasautos: ?[]const u8 = null;
pub fn setAutocallDir(dir: ?[]const u8) void {
    g_sasautos = dir;
}

/// Expand `src` into arena-owned text with all macro constructs resolved.
pub fn expand(a: std.mem.Allocator, src: []const u8, diags: *diag.Diagnostics) Error![]const u8 {
    functions.clearLetVars(); // fresh %let → SYMGET table per run (BUG-symgetlet)
    g_unresolved = .empty; // its keys belong to the PREVIOUS run's arena
    var st = State{ .a = a, .diags = diags };
    var out: std.ArrayList(u8) = .empty;
    try process(&st, src, &out);
    return unmaskTriggers(a, out.items);
}

/// The read-only automatic macro variables SAS seeds at session start
/// (GAP-macroautovars). Called once per State from process(). &SYSERR starts
/// "0" and flips to a sticky "4" at the first step error (the process() flush
/// path); the date/time stamps are the session-start wall clock, per SAS.
/// ponytail: a %let can still overwrite these (SAS makes them read-only), and
/// there is no env override for the clock (0.16's env API needs a process Init
/// the macro layer doesn't carry) — add one if reproducible stamps are needed.
fn seedAutomatics(st: *State) Error!void {
    try st.setVar("syserr", "0");
    try st.setVar("sysindex", "0");
    try st.setVar("sysmacroname", "");
    try st.setVar("sysparm", "");
    try st.setVar("sysver", "9.4");
    try st.setVar("sysscp", switch (@import("builtin").os.tag) {
        .windows => "WIN X64",
        .macos => "MAC",
        else => "LIN X64",
    });
    // GAP-macroautofeatures (F5): the rest of the documented automatics the
    // macro layer can determine. &SYSSCPL is the long OS name (pairs &SYSSCP).
    try st.setVar("sysscpl", switch (@import("builtin").os.tag) {
        .windows => "Windows",
        .macos => "macOS",
        else => "Linux",
    });
    // &SYSCC/&SYSRC: condition/return codes, 0 clean. &SYSCC flips sticky to 4
    // at the first step error in the same process() flush hook as &SYSERR;
    // &SYSRC stays 0 (the host-command layer that would set it doesn't exist).
    try st.setVar("syscc", "0");
    try st.setVar("sysrc", "0");
    // &SYSLAST/&SYSNOBS: SAS's session-start values. The live refresh (name +
    // obs of the last CREATED dataset) lives in exec.zig's Library, out of the
    // macro layer's reach — plumb it through the step-flush callback if needed.
    // &SYSPROCESSNAME is likewise deferred (needs argv / the process Init);
    // a reference to it still warns loudly via the undefined-&SYS* path.
    try st.setVar("syslast", "_NULL_");
    try st.setVar("sysnobs", "0");
    // &SYSDATE/&SYSDATE9/&SYSTIME/&SYSDAY, rendered through the real formats.
    // (currentSasDate/currentSecondOfDay are UTC — the same ceiling DATE()/TIME()
    // already carry; no local timezone in the eval path.)
    // F12: &SYSDAY trims DOWNAME.'s blank pad (an artefact of the format's
    // default width 9, not SAS's value) — SAS gives the trimmed day name.
    const dtxt = try std.fmt.allocPrint(st.a, "{d}", .{functions.currentSasDate()});
    try st.setVar("sysdate9", try computeSysfunc(st.a, "putn", &.{ dtxt, "date9." }, st.diags));
    try st.setVar("sysdate", try computeSysfunc(st.a, "putn", &.{ dtxt, "date7." }, st.diags));
    const downtxt = try computeSysfunc(st.a, "putn", &.{ dtxt, "downame." }, st.diags);
    try st.setVar("sysday", std.mem.trimEnd(u8, downtxt, " "));
    const ttxt = try std.fmt.allocPrint(st.a, "{d}", .{functions.currentSecondOfDay()});
    try st.setVar("systime", try computeSysfunc(st.a, "putn", &.{ ttxt, "time5." }, st.diags));
    // F12: the remaining documented automatics the macro layer can source
    // HONESTLY — CPU count and the OS env's user/host names. When the host
    // can't supply one it stays UNSEEDED so a reference warns loudly: a
    // plausible-but-wrong constant is worse than no value (the seeded-stale
    // &SYSLAST/&SYSNOBS lesson, BUG-syslastrefresh). Still loud by design:
    // &SYSVLONG/&SYSVLONG4 (maintenance+patch stamp — unsourceable), &SYSJOBID/
    // &SYSPROCESSNAME/&SYSSTARTID (pid/argv semantics we don't model),
    // &SYSCHARWIDTH (session encoding), &SYSMAXLONG (2^53 vs 2^63 guess),
    // &SYSSITE (license number), &SYSTIMEZONE (no local tz in the eval path),
    // &SYSMENV.
    if (std.Thread.getCpuCount()) |n| {
        try st.setVar("sysncpu", try std.fmt.allocPrint(st.a, "{d}", .{n}));
    } else |_| {}
    if (envValue(st.a, "USER")) |u| try st.setVar("sysuserid", u);
    if (envValue(st.a, "HOSTNAME")) |h| try st.setVar("syshostname", h);
}

/// A resumable macro expander: it carries macro definitions and variables across
/// successive `expand` calls so the CLI can INTERLEAVE macro expansion with step
/// execution. After a step runs, a CALL SYMPUT variable it created is pushed back
/// in via `seedVar`, making it visible to later macro code (BUG-runtimemacroscope).
pub const Session = struct {
    st: State,

    pub fn init(a: std.mem.Allocator, diags: *diag.Diagnostics) Session {
        functions.clearLetVars();
        g_unresolved = .empty; // its keys belong to the PREVIOUS run's arena
        return .{ .st = .{ .a = a, .diags = diags } };
    }

    /// Push a runtime (CALL SYMPUT) variable into the macro symbol table, unless a
    /// %let/%local of the same name already owns it in macro scope this session.
    pub fn seedVar(self: *Session, name: []const u8, val: []const u8) Error!void {
        try self.st.setVar(name, val);
    }

    pub fn expand(self: *Session, src: []const u8) Error![]const u8 {
        self.st.plain_put = true; // a Session is a real run (GAP-macroputnote)
        var out: std.ArrayList(u8) = .empty;
        try process(&self.st, src, &out);
        return unmaskTriggers(self.st.a, out.items);
    }

    /// Like `expand`, but interleaves execution: at each top-level `run;`/`quit;`
    /// the accumulated step is flushed to `cb` (which runs it + feeds CALL SYMPUT
    /// vars back via `seedVar`), so a `%do &n` later in the SAME body sees them
    /// (BUG-macrointerleave). Returns the trailing remainder (text after the last
    /// flush — an unterminated final step / pure-macro output) for the caller to run.
    pub fn expandExec(
        self: *Session,
        src: []const u8,
        ctx: *anyopaque,
        cb: *const fn (*anyopaque, []const u8) Error!void,
    ) Error![]const u8 {
        self.st.exec_ctx = ctx;
        self.st.exec_fn = cb;
        // BUG-symputscope: a DATA step can only execute INSIDE a macro body via
        // this interleaved path, so this is the exact window in which exec.zig's
        // CALL SYMPUT may need a macro scope. Publishing the live State here (and
        // only here) keeps the hook self-contained in macro.zig — no main.zig
        // wiring, and null everywhere it must be (setup pass, unit tests).
        g_live = &self.st;
        defer {
            self.st.exec_ctx = null;
            self.st.exec_fn = null;
            g_live = null;
        }
        var out: std.ArrayList(u8) = .empty;
        self.st.plain_put = true; // a Session is a real run (GAP-macroputnote)
        try process(&self.st, src, &out);
        return unmaskTriggers(self.st.a, out.items);
    }
};

/// The State of the Session currently interleaving execution, or null when no
/// step can be running inside a macro body. Same module-global hook pattern as
/// functions.zig's `g_lib` / macro.zig's `g_sasautos`.
/// ponytail: one live Session per process (main.zig makes exactly one); a second
/// concurrent Session would need this threaded through Library instead.
var g_live: ?*State = null;

/// CLIN-macrounresolvedsilent — macro-trigger names the scanner could NOT
/// resolve (lowercased keys, arena-owned), pending a deferred warning.
///
/// WHY A RECORD-AND-DISCHARGE PAIR RATHER THAN A WARNING AT FIRST SIGHT. The two
/// halves of this decision live in two different places and neither can do the
/// job alone:
///
///   * only the SCANNER knows which `&` is a genuine macro trigger. Post-lex the
///     evidence is gone: `a & b` (logical AND) and `a&b` (a reference — SAS
///     warns for it, printed p.484's `if x&y then do;`) both become `.amp`+
///     `.name`; the lexer strips quotes, so a single-quoted `'AT&T'` (never
///     resolved, never warned — printed p.38) is indistinguishable from a
///     double-quoted one; and a `%nrstr`-masked `&` (explicitly warning-free,
///     printed p.106) is unmasked back to a plain `&` before the lexer sees it.
///     process() gets all three right already, so IT records.
///   * only the CONSUMPTION POINT knows whether late binding saved it. Warning
///     at first sight would break D-004/BUG-macrointerleave, where an unknown
///     `&var` MUST survive verbatim so a later CALL SYMPUT can bind it.
///
/// `bindStepVars` discharges: it is the last instruction executed before a step
/// is compiled, and it is where the exec→macro queue gets its final chance to
/// bind. That is SAS's own warning point, not an approximation of it — Macro
/// Language Reference printed p.158: "As this DATA step is tokenized and
/// compiled, the & causes the word scanner to trigger the macro processor, which
/// looks for a MACVAR entry in a symbol table. Because such an entry does not
/// exist, the macro processor generates the warning message." Hence the CALL
/// SYMPUT written in the SAME step does NOT discharge the record (p.531: "A step
/// boundary such as a RUN statement must be reached before resolving the macro
/// variable created with CALL SYMPUT"), while one written in an EARLIER step
/// does — because that one is already in the queue `bindStepVars` reads.
///
/// Entries are never removed: an entry means "the scanner genuinely could not
/// resolve this name", and if a later step CAN bind it, `bindStepVars` binds it
/// and no `&name` survives for the discharge to see. Self-correcting.
///
/// ponytail: one live Session per process (the same assumption `g_live` makes);
/// a second concurrent Session would need this threaded through bindStepVars.
var g_unresolved: std.StringHashMapUnmanaged(void) = .empty;

/// BUG-symputscope — CALL SYMPUT's scope decision, asked by exec.zig before it
/// writes. Returns true when the variable BELONGS TO A LOCAL symbol table (per
/// `symputFrame`, printed p.77 rule 1) and has been stored there; the caller then
/// must NOT also write the flat `Library.macro_vars` store.
///
/// WHY THE TWO STORES STAY SEPARATE (deliberate, and the smaller of the two fixes
/// on offer): `Library.macro_vars` is not a symbol table, it is the exec→macro
/// handoff QUEUE — main.zig drains it into the session after every step, and
/// `bindStepVars` late-binds `&var` out of it for steps the up-front pass could
/// not resolve. It has no scope concept and needs none, because everything in it
/// is global by construction once this function has skimmed off the local cases.
/// The scoped table (`State.vars` + the `scopes` ownership log) stays the single
/// owner of scope. So: local symput → the macro table only (popScope reclaims it,
/// and it never enters the queue, which is what stops it being resurrected in a
/// later step by `bindStepVars` or the re-seed loop); global symput → the queue,
/// exactly as before. Merging the two stores outright would mean moving the queue
/// and its late-bind into macro.zig for no conformance gain.
/// BUG-symputnoupdate — UPDATE BEATS CREATE, and it is checked FIRST. Macro
/// Language Reference printed p.301, "CALL SYMPUT Routine": "If macro-variable
/// exists in any enclosing scope, macro-variable is updated. If macro-variable
/// does not exist, SYMPUT creates it." The p.77 rule-1 placement above answers
/// only the second sentence — WHERE a NEW variable is created. Running it
/// unconditionally made every CALL SYMPUT inside a parameterized macro shadow
/// the enclosing/global variable it was supposed to write, so the doc's own
/// prescribed remedy for the scope trap (p.152: "you must use a %GLOBAL
/// statement to declare the macro variable") silently did nothing.
///
/// Three outcomes, in the order SAS decides them:
///   1. the name is owned by an ACTIVE local frame (findLocalIn — innermost
///      declaration wins, i.e. "the most local symbol table in which it
///      exists") → update it there, and keep it OUT of the queue;
///   2. the name exists in `vars` but no frame owns it → it is GLOBAL → return
///      false so the caller updates the queue (see the two-store note above);
///   3. the name exists nowhere → CREATE, placed by p.77 rule 1.
///
/// `tab` is CALL SYMPUTX's third argument (BUG-symputxsymtab), which overrides
/// all of that — see `SymTab`. CALL SYMPUT has no such argument and always
/// passes `.default`.
pub fn symputLocal(name: []const u8, val: []const u8, tab: SymTab) Error!bool {
    const st = g_live orelse return false;
    switch (tab) {
        // "G: stored in the global symbol table, even if a local symbol table
        // exists" (printed p.307). A LIVE local of the same name must keep
        // shadowing it for the rest of that macro, so the new global value goes
        // into the OUTERMOST owning frame's SAVED outer value — popScope then
        // publishes it at exactly the moment the last shadow dies, and every
        // inner frame still restores the shadow it saved.
        // ponytail: that route lands in `State.vars` and NOT in the exec→macro
        // queue, so a step already lexed before the %MEND cannot late-bind it;
        // ordinary `&name` resolution after the macro returns sees it. With no
        // shadow at all (the common case, incl. after %GLOBAL) it takes the
        // plain global path and the queue, exactly like a rule-1 global.
        .global => {
            if (st.setSavedOutermost(name, val)) return true;
            return false;
        },
        // "L: … the most local symbol table that exists" (printed p.307) — the
        // INNERMOST frame, empty or not. That is deliberately not `symputFrame`'s
        // "closest NONEMPTY table": L is the explicit override, so it does not
        // skip an empty frame the way the default placement rule does. "If a
        // local symbol table does not exist" (open code) → global.
        .local => {
            if (st.scopes.items.len == 0) return false;
            try st.declareLocalAt(st.scopes.items.len - 1, name);
            try st.setVar(name, val);
            return true;
        },
        .default => {},
    }
    if (st.findLocalIn(name) != null) {
        try st.setVar(name, val);
        return true;
    }
    if (st.getVar(name) != null) return false; // existing GLOBAL → update via the queue
    const idx = st.symputFrame() orelse return false;
    try st.declareLocalAt(idx, name);
    try st.setVar(name, val);
    return true;
}

/// CALL SYMPUTX's `symbol-table` argument, SAS 9.4 Macro Language: Reference,
/// Fifth Edition, printed p.307. `default` is the routine's documented default
/// `F` ("uses the version in the most local symbol table in which it exists…
/// otherwise stores it in the most local symbol table that it finds"), which is
/// the same create/update rule CALL SYMPUT follows — so both routines share the
/// one code path and cannot drift apart.
pub const SymTab = enum { default, global, local };

/// Resolve `&name`/`&name.` references in `text` against a macro-var map (keys
/// lowercased, as `Library.setMacroVar` stores them), leaving any unknown
/// reference untouched. This is the late-binding half of CALL SYMPUT: the
/// up-front `expand` pass runs before any DATA step, so a `&var` a prior step
/// created with `symput` is unknown then and survives verbatim; the CLI calls
/// this per step (once the store is populated) to bind it (BUG-symput). Returns
/// `text` unchanged (no allocation) when it holds no `&`.
pub fn resolveVarsIn(a: std.mem.Allocator, text: []const u8, vars: *const std.StringHashMapUnmanaged([]const u8)) Error![]const u8 {
    if (std.mem.indexOfScalar(u8, text, '&') == null) return text;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '&' and i + 1 < text.len and isNameStart(text[i + 1])) {
            const s = i + 1;
            var j = s;
            while (j < text.len and isNameChar(text[j])) j += 1;
            const name = text[s..j];
            var buf: [256]u8 = undefined;
            if (name.len <= buf.len) {
                for (name, 0..) |ch, k| buf[k] = std.ascii.toLower(ch);
                if (vars.get(buf[0..name.len])) |val| {
                    try out.appendSlice(a, val);
                    if (j < text.len and text[j] == '.') j += 1; // trailing-dot delimiter is consumed
                    i = j;
                    continue;
                }
            }
            try out.appendSlice(a, text[i..j]); // unknown var → keep `&name` verbatim
            i = j;
        } else {
            try out.append(a, text[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Look up a macro var by (case-insensitive) name in a lowercased-key store.
fn varLookup(vars: *const std.StringHashMapUnmanaged([]const u8), name: []const u8) ?[]const u8 {
    var buf: [256]u8 = undefined;
    if (name.len == 0 or name.len > buf.len) return null;
    for (name, 0..) |c, i| buf[i] = std.ascii.toLower(c);
    return vars.get(buf[0..name.len]);
}

/// Late-bind CALL SYMPUT values into one step's already-lexed tokens, returning a
/// fresh slice. Two forms of a `&var` that the up-front pass couldn't resolve (it
/// runs before any step executes) are bound here, once a *prior* step's symput
/// has populated `vars`:
///   * inside a string literal — `x = "&a"` — resolved in place (BUG-symput);
///   * bare — `n = &cnt + 1` — the lexer split it into `.amp` + a name token, so
///     when that name is a macro var we drop the pair and splice in the value,
///     re-lexed to tokens (a trailing `.` delimiter is consumed) (BUG-symputbare).
/// The CLI calls this on each step's token slice right before compiling it.
/// ponytail: post-lex, the whitespace that told `a&b` (concat/macro) from `a & b`
/// (logical AND) is gone, so a bare `&name` binds only when `name` is actually a
/// macro var — a false hit needs a real variable to share a symput var's name.
pub fn bindStepVars(a: std.mem.Allocator, toks: []const lex.Token, vars: *const std.StringHashMapUnmanaged([]const u8), diags: *diag.Diagnostics) diag.Error![]const lex.Token {
    if (vars.count() == 0) {
        try warnUnresolvedIn(toks, diags);
        return toks;
    }
    var out: std.ArrayList(lex.Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        const t = toks[i];
        // bare `&name`: an `.amp` immediately followed by a name that is a macro var
        if (t.tag == .amp and i + 1 < toks.len and toks[i + 1].tag == .name) {
            if (varLookup(vars, toks[i + 1].text)) |val| {
                const vt = try lex.tokenize(a, val, diags); // re-lex the value
                const n = if (vt.len > 0 and vt[vt.len - 1].tag == .eof) vt.len - 1 else vt.len;
                try out.appendSlice(a, vt[0..n]);
                i += 2;
                if (i < toks.len and toks[i].tag == .dot) i += 1; // `&name.` delimiter
                continue;
            }
        }
        if (t.tag == .string and std.mem.indexOfScalar(u8, t.text, '&') != null) {
            var nt = t;
            nt.text = try resolveVarsIn(a, t.text, vars);
            try out.append(a, nt);
        } else {
            try out.append(a, t);
        }
        i += 1;
    }
    try warnUnresolvedIn(out.items, diags);
    return out.items;
}

/// CLIN-macrounresolvedsilent — the DISCHARGE half of `g_unresolved`, run on a
/// step's tokens after `bindStepVars` has had its last chance to bind them. A
/// `&name` still standing here is definitively unresolved: SAS warns at exactly
/// this moment (printed p.158) and so do we.
///
/// The `g_unresolved` gate is what makes this sound. It fires ONLY for names the
/// scanner itself classified as genuine macro triggers, so `a & b`, `'AT&T'` and
/// `%nrstr(&x)` — all indistinguishable from a real reference in the token
/// stream — cannot reach the warning, because they were never recorded.
///
/// STEP text is discharged here; `%PUT` text is discharged by `handlePut`
/// through `warnUnresolvedRaw` (NOTE-putunresolvedwarn); top-level GLOBAL
/// statements (TITLE/FOOTNOTE/OPTIONS/…) are discharged by main.zig's
/// runExpanded through THIS function — main.zig routes those around
/// `bindStepVars`, so the call is one main.zig owns, not one macro.zig can
/// place (NOTE-globalstmtunresolved). Late binding provably cannot apply to a
/// global statement either — no step runs before it in its chunk — which is
/// what makes it warnable.
pub fn warnUnresolvedIn(toks: []const lex.Token, diags: *diag.Diagnostics) diag.Error!void {
    if (g_unresolved.count() == 0) return;
    for (toks, 0..) |t, i| switch (t.tag) {
        // bare `&name` — the lexer split the reference into `.amp` + `.name`
        .amp => if (i + 1 < toks.len and toks[i + 1].tag == .name)
            try warnIfPending(toks[i + 1].text, t.line, diags),
        // `"… &name …"` — the reference rides inside the literal's text
        .string => try warnUnresolvedRaw(t.text, t.line, diags),
        else => {},
    };
}

/// The same discharge over RAW text rather than a token stream: every `&name`
/// still standing in `text` gets the pending-warning treatment. Used for string
/// literals inside a step or a global statement, and for `%PUT` text
/// (NOTE-putunresolvedwarn).
fn warnUnresolvedRaw(text: []const u8, line: usize, diags: *diag.Diagnostics) Error!void {
    if (g_unresolved.count() == 0) return;
    var k: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, k, '&')) |at| {
        var e = at + 1;
        if (e < text.len and isNameStart(text[e])) {
            while (e < text.len and isNameChar(text[e])) e += 1;
            try warnIfPending(text[at + 1 .. e], line, diags);
        }
        k = at + 1; // always advances, so `&&`/`&1` cannot spin
    }
}

/// Warn for `name` if the scanner recorded it as an unresolved macro trigger.
/// SAS uppercases the name in the message.
fn warnIfPending(name: []const u8, line: usize, diags: *diag.Diagnostics) Error!void {
    var kbuf: [256]u8 = undefined;
    if (name.len == 0 or name.len > kbuf.len) return;
    if (!g_unresolved.contains(std.ascii.lowerString(kbuf[0..name.len], name))) return;
    // diag.report allocPrints the message, so a stack buffer is safe here.
    var ubuf: [256]u8 = undefined;
    try diags.warn(line, "Apparent symbolic reference {s} not resolved.", .{std.ascii.upperString(ubuf[0..name.len], name)});
}

// ── the scanner ─────────────────────────────────────────────────────────────

fn process(st: *State, src: []const u8, out: *std.ArrayList(u8)) Error!void {
    // Seed the automatic macro variables once per State (GAP-macroautovars) —
    // process() re-enters constantly, so this is the single choke point.
    if (!st.auto_seeded) {
        st.auto_seeded = true;
        try seedAutomatics(st);
    }
    // Every recursion route — macro calls, nested %if branches, arg/%let text
    // resolution — re-enters process, so one depth guard here stops all of them
    // (a recursive %macro or thousands of nested %if would else overflow the stack).
    if (st.call_depth >= max_macro_depth) {
        try st.diags.note(0, "macro expansion nested past {d} levels — stopped (recursion?)", .{max_macro_depth});
        return;
    }
    st.call_depth += 1;
    defer st.call_depth -= 1;

    var i: usize = 0;
    // Inside a "double-quoted" string SAS still resolves &/% but a ' is a literal
    // char, not a single-quote delimiter. Track dq state so an apostrophe inside
    // "..." (e.g. `"d'x"` in a real macro) doesn't open a phantom single-quote
    // span and desync the scanner, leaking a later %if/%do to the lexer
    // (BUG-barepct). `/* */` and `%*` are also inert inside "...".
    var in_dq = false;
    while (i < src.len) {
        // %return in effect: stop scanning this body at once — nothing after the
        // %return is emitted. handleCall clears the flag at the macro boundary, so
        // this only unwinds up to the enclosing invocation (ISS-macroreturn).
        if (st.returning) break;
        // %goto in effect: drop everything (emit nothing) until the matching
        // `%LABEL:` is reached, then resume. If the label isn't in this src, the
        // loop runs to the end with goto_target still set and the caller unwinds.
        if (st.goto_target) |target| {
            if (src[i] == '%') {
                var e = i + 1;
                while (e < src.len and isNameChar(src[e])) e += 1;
                if (e < src.len and src[e] == ':' and eqi(src[i + 1 .. e], target)) {
                    st.goto_target = null;
                    i = e + 1;
                    continue;
                }
            }
            i += 1;
            continue;
        }
        const c = src[i];
        if (c == '"') {
            // Toggle double-quote state; a doubled "" is an embedded quote (stay in).
            if (in_dq and i + 1 < src.len and src[i + 1] == '"') {
                try out.appendSlice(st.a, src[i .. i + 2]);
                i += 2;
                continue;
            }
            in_dq = !in_dq;
            try out.append(st.a, c);
            i += 1;
        } else if (!in_dq and c == '/' and i + 1 < src.len and src[i + 1] == '*') {
            // /* ... */ comment: the macro processor does not scan comment text,
            // so `%calls`/`&vars` inside it pass through inert (BUG-macrocomment).
            const rel = std.mem.indexOf(u8, src[i + 2 ..], "*/");
            const end = if (rel) |r| i + 2 + r + 2 else src.len;
            try out.appendSlice(st.a, src[i..end]);
            i = end;
        } else if (!in_dq and st.sq_masks_triggers and c == '\'') {
            // '...' single-quoted string in COMPILER-BOUND text: SAS masks & and
            // % inside single quotes there (double quotes still expand — printed
            // p.38). A doubled '' is an embedded quote. Macro-STATEMENT text
            // takes the other branch (sq_masks_triggers is false inside
            // resolveText): quotes are ordinary characters to the macro
            // processor and triggers inside them resolve normally.
            var j = i + 1;
            while (j < src.len) : (j += 1) {
                if (src[j] == '\'') {
                    if (j + 1 < src.len and src[j + 1] == '\'') {
                        j += 1; // skip the escaped '' pair, stay in the string
                        continue;
                    }
                    j += 1; // consume the closing quote
                    break;
                }
            }
            try out.appendSlice(st.a, src[i..j]);
            i = j;
        } else if (c == '&' and i + 1 < src.len and (src[i + 1] == '&' or isNameStart(src[i + 1]))) {
            // Extract the maximal &-reference run (ampersands, name chars, delimiter
            // dots) and resolve it with SAS's multi-pass rule so `&&var&i` indirection
            // works: `&&`→`&` then rescan until stable (BUG-macroindirect).
            var j = i;
            while (j < src.len and (src[j] == '&' or isNameChar(src[j]) or src[j] == '.')) j += 1;
            try out.appendSlice(st.a, try resolveAmpRun(st, src[i..j]));
            i = j;
        } else if (!in_dq and c == '%' and i + 1 < src.len and src[i + 1] == '*') {
            // `%* … ;` macro comment — skip to the terminating ';', emit nothing.
            // `%*` isn't a name-start so it would otherwise leak the `%` to the
            // lexer (BUG-barepct: a real utility macro's `%** … ** ;` → LexError).
            var e = i + 2;
            while (e < src.len and src[e] != ';') e += 1;
            i = if (e < src.len) e + 1 else e;
        } else if (c == '%' and i + 1 < src.len and isNameStart(src[i + 1])) {
            i = try handlePercent(st, src, i, out);
        } else if (st.exec_fn != null and !in_dq and
            (c == 'r' or c == 'R' or c == 'q' or c == 'Q') and
            stmtBoundary(out.items) and
            (stmtKw(src, i, "run") or stmtKw(src, i, "quit")))
        {
            // Top-level step boundary during interleaved expansion: emit the
            // `run;`/`quit;`, then flush the accumulated (complete) step to the
            // interpreter so its CALL SYMPUT vars are visible to the rest of THIS
            // body's expansion (BUG-macrointerleave). `out` is always a full
            // program prefix here, so executing it is safe; then reset it.
            var e = i;
            while (e < src.len and isNameChar(src[e])) e += 1; // past run/quit
            while (e < src.len and src[e] != ';') e += 1;
            if (e < src.len) e += 1; // past ';'
            try out.appendSlice(st.a, src[i..e]);
            i = e;
            try st.exec_fn.?(st.exec_ctx.?, try unmaskTriggers(st.a, out.items));
            out.clearRetainingCapacity();
            // GAP-macroautovars: a step just RAN — refresh &SYSERR. The callback
            // records step failures in diags and swallows them, so a sticky
            // 4-once-any-step-errored is all that's observable from here; clean
            // steps keep the seeded 0. (SAS resets SYSERR per step; sticky
            // matches our syntax-check halt — after a step error later steps
            // are skipped, so a following %if &syserr must still fire.)
            if (st.diags.hasStepErrors()) {
                try st.setVar("syserr", "4");
                try st.setVar("syscc", "4"); // F5: session condition code mirrors &SYSERR
            }
        } else if (!in_dq and (c == 'o' or c == 'O') and stmtBoundary(out.items) and stmtKw(src, i, "options")) {
            // `OPTIONS MINOPERATOR [MINDELIMITER='c'];` — the SYSTEM-option form
            // of the `in`/`#` gate (BUG-minoperatoropt). It takes effect when
            // READ, before any later macro invocation, so process() intercepts
            // it at scan time into st.minoperator/.mindelimiter; the statement
            // text itself is the executor's business (it owns every other
            // option). ponytail: word scan also fires on a DATA-step
            // `options = 1;` assignment — harmless, it holds no option words.
            var e = i;
            while (e < src.len) : (e += 1) {
                if (src[e] == ';') break;
                if (src[e] == '\'' or src[e] == '"') { // a quoted ';' doesn't end it
                    const q = src[e];
                    e += 1;
                    while (e < src.len and src[e] != q) e += 1;
                }
            }
            applyOptionsStmt(st, src[i..e]);
            // Do NOT consume the statement: it used to be copied to `out`
            // verbatim, which bypassed the ordinary scan — so an `&ref` in an
            // OPTIONS statement was never resolved (`%let v=nodate; options
            // &v;` errored where SAS runs clean) and never recorded, which is
            // what let OPTIONS swallow the unresolved-reference warning
            // (NOTE-globalstmtunresolved). Emit just the 'o'; the ordinary
            // loop scans the rest — resolving/recording `&` and honouring
            // quotes — exactly as it does for any other statement.
            try out.append(st.a, c);
            i += 1;
        } else {
            try out.append(st.a, c);
            i += 1;
        }
    }
}

/// True when nothing (or only whitespace/comments) has been emitted since the
/// last `;` — i.e. the next word starts a statement (for run;/quit; boundary
/// detection). Comments pass through expansion verbatim (BUG-macrocomment), so
/// a trailing `/* … */` must not hide the boundary: `%m(); /* note */ run;`
/// deferred the step past expansion-time %sysfunc(exist()) checks and silently
/// broke real EPOCH-derivation macros (BUG-dv1trace / BUG-ae2register).
fn stmtBoundary(emitted: []const u8) bool {
    var k = emitted.len;
    while (k > 0) {
        switch (emitted[k - 1]) {
            ' ', '\t', '\n', '\r' => k -= 1,
            '/' => {
                if (k >= 2 and emitted[k - 2] == '*') {
                    // Walk back over a `/* … */` block. ponytail: lastIndexOf can
                    // land on a `/*` inside a string literal — a miss here only
                    // defers the flush (old behavior), never corrupts.
                    const open = std.mem.lastIndexOf(u8, emitted[0 .. k - 2], "/*") orelse return false;
                    k = open;
                } else return false;
            },
            ';' => return true,
            else => return false,
        }
    }
    return true; // start of the buffer
}

/// `src[i..]` begins with keyword `word` (case-insensitive) not followed by a
/// name char — a whole-word match at a statement position.
fn stmtKw(src: []const u8, i: usize, word: []const u8) bool {
    if (i + word.len > src.len) return false;
    if (!std.ascii.eqlIgnoreCase(src[i .. i + word.len], word)) return false;
    const after = i + word.len;
    return after >= src.len or !isNameChar(src[after]);
}

/// Scan an `OPTIONS …` statement body (sans `;`) for the macro-expression
/// system options (BUG-minoperatoropt): MINOPERATOR/NOMINOPERATOR toggle the
/// `in`/`#` gate; MINDELIMITER='c' sets its list delimiter. Every other option
/// is the executor's business — the statement text passes through untouched.
fn applyOptionsStmt(st: *State, stmt: []const u8) void {
    var i: usize = 0;
    while (i < stmt.len) {
        if (isNameStart(stmt[i])) {
            const s = i;
            while (i < stmt.len and isNameChar(stmt[i])) i += 1;
            const w = stmt[s..i];
            if (eqi(w, "minoperator")) {
                st.minoperator = true;
            } else if (eqi(w, "nominoperator")) {
                st.minoperator = false;
            } else if (eqi(w, "mindelimiter")) {
                var ignored: usize = undefined;
                if (parseMindelim(st, stmt, i, &ignored)) |d| st.mindelimiter = d;
            }
        } else i += 1;
    }
}

/// MINDELIMITER= value parser (F10): SAS takes a SINGLE character. The value
/// starts at `from` (just past the keyword): spaces/`=`, then either a quoted
/// char (`'c'`/`"c"`) or a bare run up to whitespace/`;`. Anything that isn't
/// exactly one character (`'ab'`, `''`, `=xyz`) used to keep the first byte
/// and drop the rest SILENTLY — fail loud and leave the delimiter unchanged.
/// `end` gets the index just past the value (past the closing quote when
/// quoted) so the %MACRO option chain can step over it (GAP-macroopts).
fn parseMindelim(st: *State, text: []const u8, from: usize, end: *usize) ?u8 {
    var p = from;
    while (p < text.len and (text[p] == ' ' or text[p] == '\t' or text[p] == '=')) p += 1;
    var close: u8 = 0;
    if (p < text.len and (text[p] == '\'' or text[p] == '"')) {
        close = text[p];
        p += 1;
    }
    const vs = p;
    if (close != 0) {
        while (p < text.len and text[p] != close) p += 1;
    } else {
        while (p < text.len and text[p] != ' ' and text[p] != '\t' and text[p] != ';') p += 1;
    }
    const val = text[vs..p];
    end.* = if (close != 0 and p < text.len) p + 1 else p; // past the closing quote
    if (val.len != 1) {
        st.diags.macroErr(0, "MINDELIMITER= requires a single character, got '{s}'", .{val}) catch {};
        return null;
    }
    return val[0];
}

// CLIN-macrounresolvedsilent: `emitVar` lived here — a single-`&` resolver that
// NOTEd "macro variable &x is not resolved". It had no callers (resolveAmpRun
// superseded it long ago) and no test, so that note never reached a log; it was
// removed rather than left as a second, contradictory answer to the question
// this ticket settles (see `g_unresolved`).

/// Resolve a run of `&` references with SAS's iterative rescan: each pass reduces
/// `&&`→`&` and replaces a defined `&name` with its value; the result is rescanned
/// until nothing changes. This is what makes `&&var&i` (macro-array) indirection
/// resolve. An undefined `&name` is left verbatim (stops that chain).
fn resolveAmpRun(st: *State, run: []const u8) Error![]const u8 {
    var cur = run;
    var pass: usize = 0;
    while (pass < 20) : (pass += 1) {
        if (std.mem.indexOfScalar(u8, cur, '&') == null) break;
        var out: std.ArrayList(u8) = .empty;
        var changed = false;
        var i: usize = 0;
        while (i < cur.len) {
            if (cur[i] == '&' and i + 1 < cur.len and cur[i + 1] == '&') {
                try out.append(st.a, '&'); // && → & (deferred to the next scan)
                i += 2;
                changed = true;
            } else if (cur[i] == '&' and i + 1 < cur.len and isNameStart(cur[i + 1])) {
                var j = i + 1;
                while (j < cur.len and isNameChar(cur[j])) j += 1;
                if (st.getVar(cur[i + 1 .. j])) |val| {
                    try out.appendSlice(st.a, val);
                    if (j < cur.len and cur[j] == '.') j += 1; // delimiter dot
                    changed = true;
                } else {
                    // GAP-macroautovars: an undefined &SYSxxx must not pass
                    // through silently — SAS warns. Scoped to pass 0 and the
                    // SYS prefix, because an automatic variable is never a CALL
                    // SYMPUT target, so warning EAGERLY is safe for it alone.
                    if (pass == 0 and j - (i + 1) > 3 and eqi(cur[i + 1 .. i + 4], "sys")) {
                        try st.diags.warn(0, "Apparent symbolic reference {s} not resolved.", .{try upperDup(st.a, cur[i + 1 .. j])});
                    } else {
                        // CLIN-macrounresolvedsilent: every OTHER unresolved
                        // trigger is RECORDED, never warned here — the CALL
                        // SYMPUT late-bind idiom needs it to survive verbatim
                        // (D-004). bindStepVars warns for whatever never bound.
                        try st.noteUnresolved(cur[i + 1 .. j]);
                    }
                    try out.appendSlice(st.a, cur[i..j]); // undefined → keep &name
                }
                i = j;
            } else {
                try out.append(st.a, cur[i]);
                i += 1;
            }
        }
        cur = out.items;
        if (!changed) break;
    }
    return cur;
}

fn handlePercent(st: *State, src: []const u8, at: usize, out: *std.ArrayList(u8)) Error!usize {
    const start = at + 1;
    var j = start;
    while (j < src.len and isNameChar(src[j])) j += 1;
    const word = src[start..j];

    // Macro label `%NAME:` (a %goto target, e.g. a date macro's `%EXIT:`) — consume
    // it, emit nothing. On fall-through it is inert; the %goto skip loop in
    // process() handles the jump target itself.
    if (word.len > 0 and j < src.len and src[j] == ':') return j + 1;
    if (eqi(word, "goto")) return handleGoto(st, src, j);

    // `%return;` — early exit from the current macro. Set the unwind flag; process()
    // and the enclosing %do/%if bail immediately, and handleCall clears it at the
    // macro boundary (ISS-macroreturn). Swallow the optional trailing `;`.
    if (eqi(word, "return")) {
        var e = j;
        while (e < src.len and src[e] != ';') e += 1;
        const after = if (e < src.len) e + 1 else e;
        // `%return` outside any macro is invalid. SAS reports an error and CONTINUES;
        // we must NOT set `returning` here — an open-code unwind would silently drop
        // every following statement (GH#4). macroErr + keep scanning gives exactly
        // SAS's shape: loud ERROR, non-zero exit, later independent steps still run
        // (macro_scoped — no syntax-check step-skipping).
        // Severity is doc-grounded (SEV-returnopencode): Macro Language Ref App.2
        // lists this family in its ERROR Messages section (printed p.500: "Error:
        // The %RETURN statement is not valid in open code." — SAS really prints a
        // mixed-case "Error:" here; ours carries the renderer's severity tag), and
        // the Cause is "executed outside a macro definition" — the user's code is
        // invalid SAS, so D-009 exit 1. The handled siblings (%GOTO / iterative
        // %DO open-code guards) were already macroErr; %RETURN was the family
        // outlier at WARNING/exit 0 (left behind by NOTE-macroerrwordingfamily).
        if (st.macro_call_depth == 0) {
            try st.diags.macroErr(0, "The %RETURN statement is not valid in open code.", .{});
            return after;
        }
        st.returning = true;
        return after;
    }

    // %ABORT (inside a macro) — SAS terminates the step/session. We don't
    // implement the ABEND/RETURN/n variants, but the halt itself must be honored:
    // emit a loud error and set `aborting` (+ `returning` to reuse the bail
    // points). process() then stops emitting, so every statement after %ABORT is
    // dropped from the expanded text and never lexed/executed. Previously %ABORT
    // fell through to the generic "apparent invocation of macro ABORT not
    // resolved" WARNING and execution CONTINUED — a mislabeled statement + a
    // behavioral divergence (F4). In OPEN code %ABORT is not a halt at all —
    // see the guard below.
    if (eqi(word, "abort")) {
        var e = j;
        while (e < src.len and src[e] != ';') e += 1;
        const after = if (e < src.len) e + 1 else e;
        // `%ABORT` outside any macro is invalid — NOT a halt. Same App.2 family
        // (Macro Language Ref ERROR Messages section, printed p.500: "Error: The
        // %ABORT statement is not valid in open code."): SAS ERRORS and CONTINUES,
        // where we used to set `aborting` and drop the rest of the program — too
        // strict, the opposite direction from the family's report-and-continue.
        // Only the OPEN-CODE case relaxes; the in-macro halt below is unchanged
        // (pinned by NOTE-macroloudlabels) and `aborting` is still set nowhere
        // else, so no other path depended on an open-code halt
        // (SEV-opencodefamilyrest).
        if (st.macro_call_depth == 0) {
            try st.diags.macroErr(0, "The %ABORT statement is not valid in open code.", .{});
            return after;
        }
        try st.diags.macroErr(0, "%ABORT is not supported — halting execution", .{});
        st.returning = true;
        st.aborting = true;
        return after;
    }
    // `%end` outside any macro is invalid — same App.2 open-code family (Macro
    // Language Ref ERROR Messages section, printed p.500: "Error: The %END
    // statement is not valid in open code."). In-macro `%do;…%end;` blocks never
    // reach here (handleDo/matchingEnd consume the `%end`), so an `%end` that
    // reaches handlePercent with no enclosing macro is open-code junk — exactly
    // what a missing/misspelled %MEND dumps into the stream. Was the generic
    // "Apparent invocation of macro END not resolved." WARNING at exit 0 — wrong
    // message AND wrong severity for this family. macroErr + drop the statement:
    // loud ERROR, D-009 exit 1, open code keeps running (SEV-opencodefamilyrest).
    if (eqi(word, "end") and st.macro_call_depth == 0) {
        var e = j;
        while (e < src.len and src[e] != ';') e += 1;
        try st.diags.macroErr(0, "The %END statement is not valid in open code.", .{});
        return if (e < src.len) e + 1 else e;
    }
    // %SYSEXEC / %WINDOW / %DISPLAY — real macro statements opensas does not
    // implement. Fail loud NAMING the statement (not the generic "apparent
    // invocation of macro X not resolved", which mislabels a known statement as an
    // undefined macro call — F4) and drop the statement text up to its `;`.
    if (eqi(word, "sysexec") or eqi(word, "window") or eqi(word, "display")) {
        var e = j;
        while (e < src.len and src[e] != ';') e += 1;
        try st.diags.macroErr(0, "%{s} is not a supported macro statement", .{try upperDup(st.a, word)});
        return if (e < src.len) e + 1 else e;
    }

    if (eqi(word, "let")) return handleLet(st, src, j);
    if (eqi(word, "put")) return handlePut(st, src, j);
    if (eqi(word, "macro")) return handleMacro(st, src, j);
    if (eqi(word, "if")) return handleIf(st, src, j, out);
    if (eqi(word, "do")) return handleDo(st, src, j, out);
    if (eqi(word, "eval")) return handleEval(st, src, j, out);
    if (eqi(word, "scan") or eqi(word, "qscan")) return macroFn(st, src, j, out, .scan, isQForm(word));
    if (eqi(word, "substr") or eqi(word, "qsubstr")) return macroFn(st, src, j, out, .substr, isQForm(word));
    if (eqi(word, "upcase") or eqi(word, "qupcase")) return macroFn(st, src, j, out, .upcase, isQForm(word));
    if (eqi(word, "lowcase") or eqi(word, "qlowcase")) return macroFn(st, src, j, out, .lowcase, isQForm(word));
    // autocall string macros: %LEFT/%TRIM/%CMPRES + Q-forms (GAP-macroautocall)
    if (eqi(word, "left") or eqi(word, "qleft")) return macroFn(st, src, j, out, .left, isQForm(word));
    if (eqi(word, "trim") or eqi(word, "qtrim")) return macroFn(st, src, j, out, .trim, isQForm(word));
    if (eqi(word, "cmpres") or eqi(word, "qcmpres")) return macroFn(st, src, j, out, .cmpres, isQForm(word));
    // autocall companions (GAP-sysrcmacro): %SYSRC (_IORC_ codes), %DATATYP, %VERIFY
    if (eqi(word, "sysrc")) return handleSysrc(st, src, j, out);
    if (eqi(word, "datatyp")) return macroFn(st, src, j, out, .datatyp, false);
    if (eqi(word, "verify")) return macroFn(st, src, j, out, .verify, false);
    if (eqi(word, "index")) return macroFn(st, src, j, out, .index, false);
    if (eqi(word, "length")) return macroFn(st, src, j, out, .length, false);
    if (eqi(word, "include") or eqi(word, "inc")) return handleInclude(st, src, j, out);
    if (eqi(word, "global")) return handleScope(st, src, j, false);
    if (eqi(word, "local")) return handleScope(st, src, j, true);
    // masking: %str/%quote/%bquote resolve &/%; %nrstr masks verbatim;
    // %nrbquote/%nrquote are execution-time — resolve first, THEN mask.
    if (eqi(word, "str") or eqi(word, "quote") or eqi(word, "bquote")) return handleMask(st, src, j, out, .resolve, word);
    if (eqi(word, "nrstr")) return handleMask(st, src, j, out, .mask_only, word);
    if (eqi(word, "nrbquote") or eqi(word, "nrquote")) return handleMask(st, src, j, out, .resolve_mask, word);
    if (eqi(word, "superq")) return handleSuperq(st, src, j, out);
    if (eqi(word, "sysfunc") or eqi(word, "qsysfunc")) return handleSysfunc(st, src, j, out, isQForm(word));
    if (eqi(word, "sysget")) return handleSysget(st, src, j, out);
    if (eqi(word, "sysevalf")) return handleSysevalf(st, src, j, out);
    if (eqi(word, "symexist")) return handleSymExist(st, src, j, out, .exist);
    if (eqi(word, "symglobl")) return handleSymExist(st, src, j, out, .global);
    if (eqi(word, "symlocal")) return handleSymExist(st, src, j, out, .local);
    if (eqi(word, "sysmacexist")) return handleSysmacexist(st, src, j, out);
    if (eqi(word, "symdel")) return handleSymdel(st, src, j);
    if (eqi(word, "unquote")) return handleUnquote(st, src, j, out);
    if (eqi(word, "syscall")) return handleSyscall(st, src, j);
    if (st.getMacro(word) != null) return handleCall(st, src, j, word, out);

    // Autocall (SASAUTOS): an undefined invocation may be defined in a file
    // `<name>.sas` under the autocall dir. Load+compile it, then retry as a
    // normal call. If it stays undefined (no file / bad file), fall through to
    // the warn-and-skip below.
    if (g_sasautos != null and try tryAutocall(st, word)) {
        return handleCall(st, src, j, word, out);
    }

    // Unknown `%word` — an apparent macro invocation with no matching definition.
    // SAS emits `WARNING: Apparent invocation of macro X not resolved.` and drops
    // the call so execution continues; emitting the raw `%X` text would instead
    // hit the lexer as a stray `%` and HALT the program (BUG-undefmacro for the
    // `(...)` form, BUG-barepctundef for the bare form). Warn and DROP either way
    // — swallowing a balanced arg list when present. Keyword statements/functions
    // (%put/%if/%str/…) were all handled above, so this only fires for a real
    // unresolved macro name.
    try st.diags.warn(0, "Apparent invocation of macro {s} not resolved.", .{try upperDup(st.a, word)});
    const ap = skipWs(src, j);
    if (ap < src.len and src[ap] == '(') return skipBalancedParen(src, ap);
    return j; // bare %word: drop the token, emit nothing
}

/// SASAUTOS autocall: find `<word>.sas` (case-insensitive) in `g_sasautos`,
/// compile it so its `%macro` registers, and report whether `word` is now
/// defined. Each name is attempted at most once per run. A missing dir/file is
/// silent (caller falls back to warn-and-skip); a file that fails to compile is
/// surfaced as a diagnostic naming the autocall file — never a crash.
fn tryAutocall(st: *State, word: []const u8) Error!bool {
    const dir_path = g_sasautos orelse return false;
    const key = try lowerDup(st.a, word);
    if (st.autoload_attempted.contains(key)) return st.getMacro(word) != null;
    try st.autoload_attempted.put(st.a, key, {});

    // The macro layer carries no `Io`, so a true case-insensitive dir scan isn't
    // available here — try the three casings the real files use instead.
    // ponytail: real autocall files are uniform-case (all-lower or all-upper
    // filenames); if a mixed-case filename ever needs matching on a
    // case-sensitive FS, thread an `Io` down and iterate the dir.
    const lname = try lowerDup(st.a, word);
    const uname = try upperDup(st.a, word);
    var text: ?[]const u8 = null;
    var name: []const u8 = "";
    for ([_][]const u8{ word, lname, uname }) |cand| {
        const full = try std.fmt.allocPrint(st.a, "{s}/{s}.sas", .{ dir_path, cand });
        if (readFileText(st.a, full)) |t| {
            text = t;
            name = try std.fmt.allocPrint(st.a, "{s}.sas", .{cand});
            break;
        }
    }
    if (text == null) return false; // no file in any casing → caller warn-skips
    // Compile into a scratch buffer (discarded): the side effect is the macro
    // definition landing in st.macros. process() only surfaces allocator errors,
    // so a malformed macro file cannot crash here — it just leaves the macro
    // undefined, which we report so the caller warns naming the file.
    var scratch: std.ArrayList(u8) = .empty;
    process(st, text.?, &scratch) catch |e| {
        try st.diags.warn(0, "autocall file {s} failed to compile ({t})", .{ name, e });
        return st.getMacro(word) != null;
    };
    if (st.getMacro(word) == null) {
        try st.diags.warn(0, "autocall file {s} did not define macro {s}", .{ name, try upperDup(st.a, word) });
    }
    return st.getMacro(word) != null;
}

fn upperDup(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    const out = try a.alloc(u8, s.len);
    for (s, 0..) |c, i| out[i] = std.ascii.toUpper(c);
    return out;
}

/// `%include "file" [/options];` — splice the included file's source at this site
/// (recursively processed, so its own `%include`/macros/`&vars` resolve in the
/// same scope). Options such as `/nosource` are accepted and ignored. A path is a
/// quoted "file"/'file' or a bare token; a missing file is a loud ERROR (SAS 9.4
/// treats a missing include as a hard failure — dropping the code it was meant to
/// contribute is silent-wrong). The include path resolves against the CWD.
fn handleInclude(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    var k = skipWs(src, from);
    var path: []const u8 = "";
    if (k < src.len and (src[k] == '"' or src[k] == '\'')) {
        const q = src[k];
        k += 1;
        const ps = k;
        while (k < src.len and src[k] != q) k += 1;
        path = src[ps..k];
        if (k < src.len) k += 1; // closing quote
    } else {
        const ps = k;
        while (k < src.len and src[k] != ';' and src[k] != '/' and !std.ascii.isWhitespace(src[k])) k += 1;
        path = src[ps..k];
    }
    // swallow any trailing options (`/nosource`, `/source2`, …) up to the `;`
    while (k < src.len and src[k] != ';') k += 1;
    if (k < src.len) k += 1; // consume the terminating `;`

    if (readFileText(st.a, path)) |text| {
        try process(st, text, out); // splice + expand the included source in place
    } else {
        // Missing %include is a hard ERROR in SAS 9.4 (F5): silently continuing on
        // a NOTE drops code the program expected to run → silent-wrong downstream.
        // The successful path above (read + splice + expand) is unchanged.
        try st.diags.macroErr(0, "%include: cannot open file \"{s}\"", .{path});
    }
    return k;
}

/// Read a whole file (the macro preprocessor carries no `Io`, and threading one
/// down just for `%include`/autocall isn't worth it). Uses the hardcoded
/// single-threaded blocking Io via the portable std.Io.Dir API — CWD-relative and
/// cross-platform (posix.openat's AT.FDCWD is absent on Windows: BUILD-windows).
/// Returns null on any open/read error so the caller can degrade to a NOTE.
fn readFileText(a: std.mem.Allocator, path: []const u8) ?[]const u8 {
    const io = std.Io.Threaded.global_single_threaded.io();
    return std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1 << 31)) catch null;
}

/// `%let name = value ;` — value is macro-expanded then blank-trimmed.
/// Skip a balanced `(...)` span starting at `lp` (which must be `(`), returning the
/// index just past the matching `)`. A `%`-escaped paren is literal text and
/// doesn't count (BUG-macropctmask — `%str(a%(b)` still balances).
fn skipBalancedParen(src: []const u8, lp: usize) usize {
    var depth: usize = 0;
    var k = lp;
    while (k < src.len) {
        if (src[k] == '%' and k + 1 < src.len and isPctEscapable(src[k + 1])) {
            k += 2;
            continue;
        }
        if (src[k] == '(') {
            depth += 1;
        } else if (src[k] == ')') {
            depth -= 1;
            if (depth == 0) return k + 1;
        }
        k += 1;
    }
    return k;
}

/// Find the `;` that terminates a %let / %put value, skipping over `%word(...)`
/// macro-function spans (`%str`, `%quote`, `%sysfunc`, …) whose argument may hold a
/// masked `;` that must not end the statement (macro-quoting).
/// `quote_eof`, when non-null, is set true if a quoted span was opened but ran
/// to EOF with no closing quote — the malformed `%let x="oops;` case, which
/// otherwise silently swallows every following statement (LETQUOTE-eof).
fn macroValueEnd(src: []const u8, from: usize, quote_eof: ?*bool) usize {
    var k = from;
    while (k < src.len and src[k] != ';') {
        // A quoted string: a `;` INSIDE quotes is literal value text, not the
        // statement terminator — `%let SEP=";";` must read the whole `";"`
        // (ISS-letquotedsemi). Skip to the matching close quote, treating a doubled
        // quote (`''`/`""`) as an embedded quote, matching the lexer's string rule.
        if (src[k] == '\'' or src[k] == '"') {
            const q = src[k];
            k += 1;
            while (k < src.len) : (k += 1) {
                if (src[k] == q) {
                    if (k + 1 < src.len and src[k + 1] == q) {
                        k += 1; // doubled quote → embedded, stay in the string
                        continue;
                    }
                    break; // lone quote closes the literal
                }
            }
            if (k < src.len) {
                k += 1; // past the closing quote
            } else if (quote_eof) |flag| flag.* = true; // ran to EOF unclosed
            continue;
        }
        if (src[k] == '%' and k + 1 < src.len and isNameStart(src[k + 1])) {
            var w = k + 1;
            while (w < src.len and isNameChar(src[w])) w += 1;
            const ws = skipWs(src, w);
            if (ws < src.len and src[ws] == '(') {
                k = skipBalancedParen(src, ws);
                continue;
            }
        }
        k += 1;
    }
    return k;
}

/// True if `text` holds a TOP-LEVEL `%let` keyword — a nested %let statement,
/// not value text: quoted `'%let'` and masked `%str(%let)` spans don't count
/// (BUG-macrodowhilehang).
fn nestedLet(text: []const u8) bool {
    var k: usize = 0;
    while (k < text.len) {
        // Quotation marks do NOT mask a `%` in macro statement text (the
        // sq_masks_triggers rule), so a quoted '%let' is a live nested %LET,
        // not inert text — no quote skip here.
        if (text[k] == '%' and k + 1 < text.len and isNameStart(text[k + 1])) {
            var w = k + 1;
            while (w < text.len and isNameChar(text[w])) w += 1;
            const ws = skipWs(text, w);
            if (ws < text.len and text[ws] == '(') {
                k = skipBalancedParen(text, ws); // %str/%quote/... arg is masked text
                continue;
            }
            if (eqi(text[k + 1 .. w], "let")) return true;
        }
        k += 1;
    }
    return false;
}

fn handleLet(st: *State, src: []const u8, from: usize) Error!usize {
    var k = skipWs(src, from);
    const ns = k;
    // The target NAME may itself carry macro references — `%let vart_&i. = …`,
    // the %do-loop indexed-variable idiom (real SDTM split macros build tables of
    // these; the old name-chars-only scan assigned to the literal "vart_" and
    // every &&vart_&i read came back unresolved/empty — QA-letindexed). Scan
    // name chars PLUS `&` refs and their terminating dots, then resolve — the
    // same rule handleScope applies to `%global &dataset.KEEPSTRING`.
    while (k < src.len and (isNameChar(src[k]) or src[k] == '&' or src[k] == '.')) k += 1;
    const name = std.mem.trim(u8, try resolveText(st, src[ns..k]), " \t\r\n");
    // SAS macro variable names are 1–32 chars, letter/underscore start (F10).
    // An invalid name was silently ACCEPTED — stored yet unreferenceable (`&1bad`
    // doesn't even scan as a reference) — corrupting every later read. Fail loud
    // and skip the assignment.
    // ponytail: an EMPTY name stays the old silent skip — it's how the
    // %str(%let) masking route re-enters handleLet (handleMask .resolve runs
    // the arg through process()), a path pinned error-free by BUG-macrodowhilehang.
    var name_ok = true;
    if (name.len > 0) {
        if (name.len > 32 or !isNameStart(name[0])) name_ok = false;
        if (name_ok) for (name) |c| {
            if (!isNameChar(c)) {
                name_ok = false;
                break;
            }
        };
    }
    if (!name_ok) {
        try st.diags.macroErr(0, "%LET: '{s}' is not a valid macro variable name (1–32 chars, letter/underscore start)", .{name});
        var e = k;
        while (e < src.len and src[e] != ';') e += 1;
        return if (e < src.len) e + 1 else e; // past ';'
    }
    k = skipWs(src, k);
    if (k < src.len and src[k] == '=') k += 1;
    const vs = k;
    var quote_eof = false;
    k = macroValueEnd(src, k, &quote_eof);
    if (quote_eof) try st.diags.warn(0, "quote not closed before end of file in %LET value", .{});
    // A nested `%let` STATEMENT inside a %let value is malformed (SAS: statement
    // "used out of proper order") and hang-prone: the inner %let EXECUTES while
    // the value resolves, then the outer %let overwrites the same var with the
    // (empty) expansion — a `%do %while` guard var never advances and the loop
    // spins forever (BUG-macrodowhilehang, qa tick158 fuzz). Fail loud and
    // unwind the macro (the %return machinery, confined to the macro by
    // handleCall) instead of assigning garbage. GH#4: never unwind OPEN code —
    // there the loud error alone stands and processing continues.
    if (nestedLet(src[vs..k])) {
        try st.diags.macroErr(0, "%LET is not valid inside a %LET value (statement used out of proper order)", .{});
        if (st.macro_call_depth > 0) st.returning = true;
        return if (k < src.len) k + 1 else k;
    }
    const val = try resolveText(st, std.mem.trim(u8, src[vs..k], " \t\r\n"));
    // BUG-macrobareletscope: a bare %let of a BRAND-NEW name inside a macro is
    // LOCAL to that invocation in SAS 9.4 (was leaking to global). A name any
    // active scope already owns (findLocal — %local/param/earlier auto-local,
    // innermost wins) or that already exists in the flat table (a global, or an
    // enclosing macro's local) updates in place — SAS updates the nearest
    // EXISTING scope, never shadows. Only the brand-new case declares, riding
    // the same SavedVar scope %local uses, so popScope discards it at %mend.
    if (st.scopes.items.len > 0 and st.findLocal(name) == null and st.getVar(name) == null)
        try st.declareLocal(name);
    try st.setVar(name, val);
    return if (k < src.len) k + 1 else k; // past ';'
}

/// `%put <text> ;` — resolve macro references in the text and write it to the
/// log. SAS writes a %PUT line PLAIN — no `NOTE:` prefix (GAP-macroputnote) —
/// so a real run (Session, plain_put) prints it straight to stderr; the
/// free-expand setup pass and unit tests stay on the captured-diagnostics
/// channel (the setup pass's junk diags swallow the line as before, and a test
/// must not spam stderr — TEST-quietnoise). G-macroput regression guard: %put
/// was falling through as an unknown `%word` and the raw `%put …` text hit the
/// lexer → "unexpected character '%'" — either way it is consumed here.
fn handlePut(st: *State, src: []const u8, from: usize) Error!usize {
    const k = macroValueEnd(src, from, null);
    const raw = std.mem.trim(u8, src[from..k], " \t\r\n");
    // F7 (GAP-macroautofeatures): a bare _ALL_/_USER_/_GLOBAL_/_LOCAL_/
    // _AUTOMATIC_ keyword dumps the matching symbol-table group instead of
    // printing the keyword literally (SAS %PUT keyword form).
    // ponytail: only the sole-keyword form (the debugging idiom); a keyword
    // mixed into other %PUT text stays literal, as before.
    if (eqi(raw, "_all_") or eqi(raw, "_user_") or eqi(raw, "_global_") or
        eqi(raw, "_local_") or eqi(raw, "_automatic_"))
    {
        try dumpPutVars(st, raw);
        return if (k < src.len) k + 1 else k; // past the ';'
    }
    // NOTE-puttevalpartial: diagnostics render once at end-of-run (main.zig),
    // so a %put line whose OWN resolution just recorded an ERROR would print
    // its partially-substituted text (`A=0` from a failed %eval) AHEAD of that
    // ERROR — in SAS the diagnostic precedes the line it came from. Emitting
    // the line after the ERROR from here would need the deferred-render drain
    // main owns; within the macro layer the honest move is to suppress the
    // line and let the ERROR stand alone, loud at rc 1. The 0-substitution
    // itself is pinned SAS-model behavior (NOTE-macroevalnonint) and is NOT
    // changed — only the misleadingly-ordered line is dropped. Keyed on errors
    // recorded by THIS resolution, so a %put after an earlier statement's
    // error still prints.
    const diags_before = st.diags.list.items.len;
    const text = try resolveText(st, try rewritePutAmpEq(st, raw));
    for (st.diags.list.items[diags_before..]) |d| {
        if (d.severity == .err) return if (k < src.len) k + 1 else k; // past ';'
    }
    // NOTE-putunresolvedwarn — %PUT is a CONSUMPTION POINT, and the last one:
    // whatever `&name` is still standing in the resolved text goes to the log
    // verbatim, and no CALL SYMPUT can rescue it afterwards (the line is already
    // written). Macro Language Reference printed p.152 prints BOTH halves — the
    // literal text AND "WARNING: Apparent symbolic reference MACVAR not
    // resolved." — while we printed only the text, which is what made the whole
    // scope trap read as silent to a reporter.
    //
    // Scanned BEFORE `unmaskTriggers`, so a `%nrstr`-masked `&` — still a
    // sentinel byte at this point, a plain `&` one line later — can never reach
    // the warning. The `g_unresolved` gate independently requires the scanner to
    // have classified the name as a genuine trigger (see `warnUnresolvedIn`), so
    // `&SYS*` (warned EAGERLY in resolveAmpRun, never recorded) cannot double-warn.
    //
    // Emitted BEFORE the line: SAS's word scanner warns when the resolution
    // fails, i.e. before the text is written. In a real run the line goes
    // straight to stderr while diagnostics render at end-of-run (main.zig), so
    // the ordering only holds on the captured channel — same as every other
    // diagnostic in the interpreter.
    try warnUnresolvedRaw(text, 0, st.diags);
    const line = try unmaskTriggers(st.a, text);
    if (!@import("builtin").is_test and st.plain_put) {
        std.debug.print("{s}\n", .{line});
    } else {
        try st.diags.note(0, "{s}", .{line});
    }
    return if (k < src.len) k + 1 else k; // past the ';'
}

/// F12: `%put &=name;` — the SAS 9.4 name-and-value debugging form — prints
/// `NAME=value`. Rewrite each `&=name` in the %PUT text to `NAME=&name` and
/// let normal resolution fill the value (an unresolved name keeps `&name`
/// verbatim with its usual diagnostic — loud, never a blank). A trailing dot
/// is the reference delimiter. Borrowed-slice return when no `&=` is present.
fn rewritePutAmpEq(st: *State, raw: []const u8) Error![]const u8 {
    if (std.mem.indexOf(u8, raw, "&=") == null) return raw;
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '&' and i + 2 < raw.len and raw[i + 1] == '=' and isNameStart(raw[i + 2])) {
            var e = i + 2;
            while (e < raw.len and isNameChar(raw[e])) e += 1;
            const name = raw[i + 2 .. e];
            if (e < raw.len and raw[e] == '.') e += 1; // delimiter dot
            try out.appendSlice(st.a, try upperDup(st.a, name));
            try out.append(st.a, '=');
            try out.append(st.a, '&');
            try out.appendSlice(st.a, name);
            try out.append(st.a, '.');
            i = e;
        } else {
            try out.append(st.a, raw[i]);
            i += 1;
        }
    }
    return out.items;
}

/// `%put _all_|_user_|_global_|_local_|_automatic_;` — one `SCOPE NAME value`
/// line per matching macro variable (SAS format). SYS* names are the
/// automatics (ponytail: a user-%let `sysfoo` would also classify AUTOMATIC —
/// SAS reserves the prefix, so no real program does); a name an active scope
/// owns (%local / param / auto-local — findLocalIn) is local; the rest GLOBAL.
///
/// NOTE-userscopename — THE SCOPE COLUMN IS THE OWNING MACRO'S NAME, not the
/// word LOCAL. SAS 9.4 Macro Language: Reference, Fifth Edition, printed p.419
/// ("%PUT Macro Statement"), verified against the "%PUT Macro Statement 419"
/// footer above the `=== pdf 435 ===` marker (offset printed + 15):
///   _USER_      "lists user-generated global and local macro variables. The
///                scope is identified either as GLOBAL, or as the name of the
///                macro in which the macro variable is defined."
///   _LOCAL_     "lists user-generated local macro variables. The scope is the
///                name of the currently executing macro."
///   _GLOBAL_    "The scope is identified as GLOBAL."
///   _AUTOMATIC_ "The scope is identified as AUTOMATIC."
/// Worked examples agree: printed p.79 `ENV1 MYVAR1 a token` / `ENV1 PARAM1 10`,
/// p.84 `ENV4 MYVAR4 a token`, p.421 `MYPRINT NAME consumer`, p.170 `TOTINV VAR
/// price`. This is PRESENTATION ONLY — which frame owns which variable is
/// unchanged (BUG-symputscope owns that, and its fixture still pins it).
///
/// ORDER, from the same page's Details: "Macro variables are listed in order
/// from the current local macro variables outward to the global macro
/// variables", with the 9.4 note that "the variables are always listed
/// alphabetically" within a scope. So locals sort innermost-frame-first and
/// globals/automatics last — printed p.421 shows exactly that (`MYPRINT NAME`
/// before `GLOBAL FOOT`), and a flat sort of the rendered lines got it backwards
/// (GLOBAL < LOCAL) and, once the column became a macro name, would have
/// reshuffled by whatever the macro happened to be called. Non-locals keep the
/// old rendered-line sort, so `_GLOBAL_`/`_AUTOMATIC_` output is byte-identical.
fn dumpPutVars(st: *State, kw: []const u8) Error!void {
    const user = eqi(kw, "_all_") or eqi(kw, "_user_");
    const want_global = user or eqi(kw, "_global_");
    const want_local = user or eqi(kw, "_local_");
    const want_auto = eqi(kw, "_all_") or eqi(kw, "_automatic_");
    // Rank orders the buckets; within a rank the rendered line breaks the tie
    // (alphabetical, and for one frame the scope prefix is constant so that is
    // name order). Non-locals share the last rank, keeping their existing order.
    const global_rank = std.math.maxInt(usize);
    const Line = struct { rank: usize, text: []const u8 };
    var lines: std.ArrayList(Line) = .empty;
    var it = st.vars.iterator();
    while (it.next()) |e| {
        const name = e.key_ptr.*; // keys are stored lowercased
        const auto = std.mem.startsWith(u8, name, "sys");
        const owner: ?usize = if (auto) null else if (st.findLocalIn(name)) |l| l.idx else null;
        const want = if (auto) want_auto else if (owner) |idx|
            // _LOCAL_ is "the currently executing macro" only (printed p.420,
            // Figure 19.1 labels it "(current macro only)"); _USER_/_ALL_ take
            // every active frame. Without this an ENCLOSING macro's variable
            // would be listed under _LOCAL_ carrying that macro's name — a
            // diagnostic naming a scope the reader did not ask about.
            want_local and (user or idx == st.scopes.items.len - 1)
        else
            want_global;
        if (!want) continue;
        const scope: []const u8 = if (auto) "AUTOMATIC" else if (owner) |idx| st.scopes.items[idx].owner else "GLOBAL";
        try lines.append(st.a, .{
            // Innermost frame first, then outward, then the global bucket.
            .rank = if (owner) |idx| st.scopes.items.len - 1 - idx else global_rank,
            .text = try std.fmt.allocPrint(st.a, "{s} {s} {s}", .{
                scope,
                try upperDup(st.a, name),
                try unmaskTriggers(st.a, e.value_ptr.get()),
            }),
        });
    }
    std.mem.sort(Line, lines.items, {}, struct {
        fn f(_: void, x: Line, y: Line) bool {
            if (x.rank != y.rank) return x.rank < y.rank;
            return std.mem.lessThan(u8, x.text, y.text);
        }
    }.f);
    for (lines.items) |l| {
        const line = l.text;
        if (!@import("builtin").is_test and st.plain_put) {
            std.debug.print("{s}\n", .{line});
        } else {
            try st.diags.note(0, "{s}", .{line});
        }
    }
}

/// `%macro name(p1,p2); body %mend [name];` — body kept raw until expansion.
fn handleMacro(st: *State, src: []const u8, from: usize) Error!usize {
    var k = skipWs(src, from);
    const ns = k;
    while (k < src.len and isNameChar(src[k])) k += 1;
    const name = src[ns..k];
    k = skipWs(src, k);

    var params: std.ArrayList(Param) = .empty;
    if (k < src.len and src[k] == '(') {
        k += 1;
        // The param list must be comment-aware: SAS strips `/* … */` before macro
        // processing, so a `)`/`,` inside a comment (real macro headers annotate each
        // default, e.g. `DATEC= /*Entry date (Char)*/`) must NOT terminate the list
        // or a default — that truncated the param list at the first `)` and
        // corrupted the whole macro (BUG-makedateparams).
        while (true) {
            k = skipWsc(src, k);
            if (k >= src.len or src[k] == ')') break;
            const ps = k;
            while (k < src.len and isNameChar(src[k])) k += 1;
            const pname = src[ps..k];
            k = skipWsc(src, k);
            var def: []const u8 = "";
            var is_kw = false;
            if (k < src.len and src[k] == '=') { // keyword param with a default value
                is_kw = true;
                k += 1;
                const ds = k;
                while (k < src.len and src[k] != ',' and src[k] != ')') {
                    if (src[k] == '/' and k + 1 < src.len and src[k + 1] == '*') {
                        k = skipBlockComment(src, k);
                    } else k += 1;
                }
                def = try stripBlockComments(st.a, src[ds..k]);
            }
            if (pname.len > 0) {
                // SAS rejects a duplicate parameter name at definition time
                // (F11): last-wins rebinding silently discarded one argument.
                for (params.items) |pp| if (eqi(pp.name, pname)) {
                    try st.diags.macroErr(0, "Duplicate parameter {s} found in macro {s} parameter list", .{ try upperDup(st.a, pname), try upperDup(st.a, name) });
                };
                try params.append(st.a, .{ .name = pname, .default = def, .is_keyword = is_kw });
            }
            k = skipWsc(src, k);
            if (k < src.len and src[k] == ',') k += 1 else break;
        }
        if (k < src.len and src[k] == ')') k += 1;
    }
    // The header ends at the first `;`; an optional `/ options` list sits
    // between the param list and that `;` — it must not leak into the body
    // (G-ebnf-sweep: macro_opt). Options can't hold an unquoted `;`.
    // GAP-macroopts: the list is now a REAL chain with a final else (the
    // BUG-optionsstmtswallow OPTIONS-statement model, f93bba23):
    //   honoured — PARMBUFF/NOPARMBUFF (raw arg list into &SYSPBUFF),
    //     MINOPERATOR/NOMINOPERATOR + MINDELIMITER= (the `in`/`#` gate);
    //   inert — NOSECURE (the SAS default; enumerated so the chain's final
    //     else stays honest);
    //   UNSUPPORTED, loud, GAP (rc 2 — D-009) — STORE/SECURE/DES=/SOURCE/SRC
    //     (opensas keeps macros for the session only: no stored-macro catalog)
    //     and CMD/STMT (command-/statement-style invocation; opensas invokes
    //     via %name only). Every one is in the %MACRO statement's documented
    //     option list (Macro Reference printed pp.408-411, re-derived IN FULL
    //     per D-018 — that is how SOURCE/SRC joined; the catch-all had been
    //     calling a documented option "Unrecognized" at rc 1), so each is valid
    //     SAS 9.4 opensas cannot run: an opensas gap, exit 2, "file an opensas
    //     issue" (GAP-ebnfrcwrongclass). An unsupported option ERRORs, naming
    //     itself, and the macro is NOT defined (D-002) — a call then warns
    //     "apparent invocation … not resolved", like SAS after a failed compile;
    //   anything else — a typo or an unfiled option: ERROR naming it at rc 1
    //     (a genuine typo like STROE is the user's own SAS — D-009), so the
    //     next unknown word can't be swallowed like these five were.
    const opt_start = k;
    while (k < src.len and src[k] != ';') k += 1;
    var pbuff = false;
    var minop = false;
    var mindelim: u8 = ' ';
    var has_mindelim = false;
    var bad_opt = false;
    {
        const opt = src[opt_start..k];
        var oi = skipWsc(opt, 0);
        if (oi < opt.len and opt[oi] == '/') oi += 1; // the option list opens with `/`
        while (true) {
            oi = skipWsc(opt, oi);
            if (oi >= opt.len) break;
            if (!isNameStart(opt[oi])) {
                try st.diags.macroErr(0, "Syntax error in the %MACRO option list", .{});
                bad_opt = true;
                break;
            }
            const ws = oi;
            while (oi < opt.len and isNameChar(opt[oi])) oi += 1;
            const w = opt[ws..oi];
            if (eqi(w, "parmbuff")) {
                pbuff = true;
            } else if (eqi(w, "noparmbuff")) {
                pbuff = false;
            } else if (eqi(w, "minoperator")) {
                minop = true;
            } else if (eqi(w, "nominoperator")) {
                minop = false;
            } else if (eqi(w, "mindelimiter")) {
                var vend: usize = oi;
                if (parseMindelim(st, opt, oi, &vend)) |d| {
                    mindelim = d;
                    has_mindelim = true;
                }
                oi = vend;
            } else if (eqi(w, "nosecure")) {
                // the SAS default — nothing to secure in, nothing to do
            } else if (eqi(w, "store") or eqi(w, "secure") or eqi(w, "des") or eqi(w, "source") or eqi(w, "src")) {
                try st.diags.macroErr(0, "The %MACRO option {s} is not supported (opensas keeps macros for the session only — no stored-macro catalog)", .{try upperDup(st.a, w)});
                diag.markGap(); // documented option, valid SAS 9.4 — gap, rc 2 (D-009)
                bad_opt = true;
                break;
            } else if (eqi(w, "cmd") or eqi(w, "stmt")) {
                try st.diags.macroErr(0, "The %MACRO option {s} is not supported (command-/statement-style invocation; opensas invokes macros via %name only)", .{try upperDup(st.a, w)});
                diag.markGap(); // documented option, valid SAS 9.4 — gap, rc 2 (D-009)
                bad_opt = true;
                break;
            } else {
                try st.diags.macroErr(0, "Unrecognized %MACRO option {s}", .{try upperDup(st.a, w)});
                bad_opt = true;
                break;
            }
        }
    }
    if (k < src.len) k += 1; // past the terminating ';'

    const bs = k;
    // Find the BALANCED `%mend`: a nested `%macro` inside the body opens a level
    // that its own `%mend` closes, so the outer def isn't truncated at the first
    // (inner) `%mend` (BUG-nestedmacro). The inner def stays in the body text and
    // registers when the outer macro runs (process() → handleMacro), per SAS
    // scoping. ponytail: like findKeyword, doesn't skip `%macro`/`%mend` that
    // appear inside comments/strings — no real macro file does that.
    const mend = findBalancedMend(src, k);
    const be = mend orelse src.len;
    // A rejected option list (bad_opt) leaves the macro UNDEFINED, like SAS
    // after a failed %MACRO compile — the ERROR above already failed the run's
    // exit code, and calls warn "apparent invocation … not resolved" instead
    // of running a macro whose options we could not honour (D-002).
    if (!bad_opt)
        try st.macros.put(st.a, try lowerDup(st.a, name), .{ .params = params.items, .body = src[bs..be], .pbuff = pbuff, .minop = minop, .mindelim = mindelim, .has_mindelim = has_mindelim });

    if (mend) |m| {
        var e = m + "%mend".len;
        // `%mend name;` — SAS checks the name against the %MACRO name (F11);
        // a mismatch means the author closed the wrong macro. Blank `%mend;`
        // is always fine.
        const mns = skipWs(src, e);
        var mne = mns;
        while (mne < src.len and isNameChar(src[mne])) mne += 1;
        const mname = src[mns..mne];
        if (mname.len > 0 and !eqi(mname, name))
            try st.diags.macroErr(0, "The %MEND name ({s}) does not match the %MACRO name ({s})", .{ try upperDup(st.a, mname), try upperDup(st.a, name) });
        while (e < src.len and src[e] != ';') e += 1;
        return if (e < src.len) e + 1 else e; // past `%mend …;`
    }
    return src.len;
}

/// `%m(a,b)` — bind params to (macro-expanded) args, expand the body into `out`.
fn handleCall(st: *State, src: []const u8, from: usize, name: []const u8, out: *std.ArrayList(u8)) Error!usize {
    var k = skipWs(src, from);
    const m = st.getMacro(name).?;
    // Collect raw arg spans (comma-separated, respecting nested parens), then split
    // into positional values and keyword (name=value) args (SAS keyword params).
    var pos: std.ArrayList([]const u8) = .empty;
    var kw: std.StringHashMapUnmanaged([]const u8) = .empty;
    var pbuff_text: []const u8 = ""; // /parmbuff: raw call arg list incl. parens
    if (k < src.len and src[k] == '(') {
        const args_start = k;
        k += 1;
        while (k < src.len and src[k] != ')') {
            const as = k;
            k = scanMacroArg(src, k);
            // Strip inline `/* … */` between/inside args (SAS removes comments
            // before macro processing) so keyword detect isn't fooled (#40).
            const raw = try stripBlockComments(st.a, src[as..k]);
            // keyword arg if it is `name=…` and `name` is a declared keyword param
            var handled = false;
            if (std.mem.indexOfScalar(u8, raw, '=')) |eq| {
                const kname = std.mem.trim(u8, raw[0..eq], " \t");
                var valid = kname.len > 0;
                for (kname) |ch| if (!isNameChar(ch)) {
                    valid = false;
                };
                if (valid) {
                    for (m.params) |pp| if (pp.is_keyword and eqi(pp.name, kname)) {
                        try kw.put(st.a, try lowerDup(st.a, kname), try resolveText(st, std.mem.trim(u8, raw[eq + 1 ..], " \t")));
                        handled = true;
                    };
                    // A clean `name=value` arg whose name is not a declared keyword
                    // param is a keyword-parameter error in SAS — NOT a positional
                    // value. Rebinding it as positional (a="zzz=99") is silent-wrong;
                    // fail loud and drop the arg (macroErr = loud + non-zero exit).
                    // Exception: /PARMBUFF with NO parameter list puts the whole
                    // invocation in &SYSPBUFF — there is nothing to validate and a
                    // keyword-looking arg is legal text (BUG-parmbuffkeyword).
                    if (!handled) {
                        if (!(m.pbuff and m.params.len == 0))
                            try st.diags.macroErr(0, "The keyword parameter {s} was not defined for the macro {s}", .{ try upperDup(st.a, kname), try upperDup(st.a, name) });
                        handled = true;
                    }
                }
            }
            if (!handled) try pos.append(st.a, try resolveText(st, raw));
            if (k < src.len and src[k] == ',') k += 1;
        }
        if (k < src.len and src[k] == ')') k += 1;
        pbuff_text = src[args_start..k]; // includes the surrounding parens
    }
    // Macro parameters are LOCAL to the call: open a scope, and restore on exit.
    try st.pushScope(name); // frame carries the macro's name for %PUT _USER_
    // printed p.77 rule 2 case 3: a macro whose body CONTAINS a computed %GOTO
    // keeps its CALL SYMPUT vars local even with an otherwise-empty table.
    st.scopes.items[st.scopes.items.len - 1].computed_goto = containsComputedGoto(m.body);
    defer st.popScope();
    // /parmbuff: &SYSPBUFF holds the raw call arg list, exactly as passed
    // (`(a,b,c)`), local to this invocation. Populated instead of silently
    // swallowing the option (was: option dropped, &SYSPBUFF never set).
    if (m.pbuff) {
        try st.declareLocal("syspbuff");
        try st.setVar("syspbuff", pbuff_text);
    }
    var pi: usize = 0;
    for (m.params) |p| {
        try st.declareLocal(p.name);
        if (p.is_keyword) {
            try st.setVar(p.name, kw.get(try lowerDup(st.a, p.name)) orelse p.default);
        } else if (pi < pos.items.len) {
            try st.setVar(p.name, pos.items[pi]);
            pi += 1;
        } else {
            try st.setVar(p.name, p.default);
        }
    }
    // Surplus positional args (more than declared positional params) are a SAS
    // error — silently dropping them is silent-wrong. Fail loud (too-FEW args is
    // fine: missing params default to blank, handled by the else branch above).
    // Exception: a /parmbuff macro legally takes any number of args (they land in
    // &SYSPBUFF), so surplus positionals are NOT an error there.
    if (!m.pbuff and pi < pos.items.len) {
        try st.diags.macroErr(0, "More positional parameters found than defined for the macro {s}", .{try upperDup(st.a, name)});
    }
    // GAP-macroautovars: &SYSINDEX counts macro invocations begun this
    // session; &SYSMACRONAME is the currently-executing macro (blank in open
    // code), saved/restored so nested calls each see their own name.
    if (st.getVar("sysindex")) |v| {
        const n = std.fmt.parseInt(usize, v, 10) catch 0;
        try st.setVar("sysindex", try std.fmt.allocPrint(st.a, "{d}", .{n + 1}));
    }
    const prev_macroname = try st.a.dupe(u8, st.getVar("sysmacroname") orelse "");
    try st.setVar("sysmacroname", try upperDup(st.a, name));
    // MINOPERATOR/MINDELIMITER: the gate is ON when EITHER the system option
    // (OPTIONS MINOPERATOR — BUG-minoperatoropt) or this definition's /
    // minoperator says so; the definition's MINDELIMITER= overrides only when
    // given (else the current/system delimiter stands). Restored on exit so a
    // caller with a different setting is unaffected (BUG-macroinoperator).
    const prev_minop = st.minoperator;
    const prev_mindelim = st.mindelimiter;
    st.minoperator = prev_minop or m.minop;
    st.mindelimiter = if (m.has_mindelim) m.mindelim else prev_mindelim;
    st.macro_call_depth += 1;
    try process(st, m.body, out); // depth-guarded inside process()
    st.macro_call_depth -= 1;
    st.minoperator = prev_minop;
    st.mindelimiter = prev_mindelim;
    try st.setVar("sysmacroname", prev_macroname);
    // A `%return` unwinds only to HERE (the invocation boundary): clear it so the
    // caller's code after `%m(...)` resumes normally (ISS-macroreturn). A `%ABORT`
    // also set `returning`, but with the sticky `aborting` flag — a program halt
    // must NOT be cleared here (later steps stay dropped, propagating to the top).
    if (!st.aborting) st.returning = false;
    // A %goto that never found its label must not leak past the macro (it would
    // silently swallow output at the call site). Report and clear at the boundary.
    if (st.goto_target) |t| {
        try st.diags.warn(0, "%goto label {s}: not found in macro {s}", .{ t, name });
        st.goto_target = null;
    }
    return k;
}

const MacroFn = enum { scan, substr, upcase, lowcase, index, length, left, trim, cmpres, datatyp, verify };

/// `%SYSRC(mnemonic)` — the _IORC_ return-code autocall macro (GAP-sysrcmacro).
/// Only DOC-SOURCED values are emitted: Language Reference: Concepts Table 23.4 (p.599) names the
/// mnemonics; the worked logs give _SOK=0 (a match, PDF p.623 `_IORC_=0`) and
/// _DSENMR=1230015 (MODIFY+BY no-match, PDF p.619); _DSENOM=1230011 is the
/// value every worked SELECT program (pp.601/604/605) compares _IORC_ against.
/// Any other mnemonic — including _DSEMTR/_SENOCHN, named in Table 23.4 but
/// never given a value in the doc — FAILS LOUD instead of guessing: a wrong
/// code compared against _IORC_ silently takes the wrong branch.
fn handleSysrc(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const pa = parenArg(src, from) orelse {
        try st.diags.macroErr(0, "%SYSRC requires a parenthesized _IORC_ mnemonic, e.g. %sysrc(_sok)", .{});
        return from;
    };
    const name = std.mem.trim(u8, try resolveText(st, pa.text), " \t\r\n");
    if (eqi(name, "_sok")) {
        try out.appendSlice(st.a, "0");
    } else if (eqi(name, "_dsenom")) {
        try out.appendSlice(st.a, "1230011");
    } else if (eqi(name, "_dsenmr")) {
        try out.appendSlice(st.a, "1230015");
    } else {
        try st.diags.macroErr(0, "%SYSRC: no doc-sourced value for _IORC_ mnemonic {s}", .{name});
    }
    return pa.end;
}

/// True for the Q-form of a macro-function name (`qscan`, `qlowcase`, …) —
/// the Q-forms mask `&` in their RESULT (BUG-macronrstrmask).
fn isQForm(word: []const u8) bool {
    return word.len > 0 and (word[0] == 'q' or word[0] == 'Q');
}

/// A macro-language function `%fn(a, b, …)`. Args are comma-separated and
/// macro-expanded (like a macro call); the computed text is emitted in place.
/// `quote` (the Q-form) sentinel-masks `&` in the result so it cannot re-resolve.
fn macroFn(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8), kind: MacroFn, quote: bool) Error!usize {
    var k = skipWs(src, from);
    var args: std.ArrayList([]const u8) = .empty;
    if (k < src.len and src[k] == '(') {
        k += 1;
        // Split on top-level commas only: an argument may itself contain a nested
        // `%func(...)` (e.g. `%substr(x,2,%length(x)-3)`), whose inner parens must
        // not be mistaken for the arg/call terminator (BUG-domainrows-empty).
        while (k < src.len and src[k] != ')') {
            const as = k;
            k = scanMacroArg(src, k);
            try args.append(st.a, try resolveText(st, try stripBlockComments(st.a, src[as..k])));
            if (k < src.len and src[k] == ',') k += 1;
        }
        if (k < src.len and src[k] == ')') k += 1;
    }
    // BUG-macroscandelim: a &/%/',' quoted by %str/%quote/%nrstr & co. survived
    // the arg split as its SENTINEL byte, and the consumers below BYTE-COMPARE
    // their args — so `%qscan(&s,2,%str(,))` searched for 0x03, never found it,
    // and returned "" where SAS gives the 2nd comma-separated word. `%str(,)` is
    // THE idiom for a comma delimiter (an unmasked one would split the arg list),
    // so this broke the normal way of doing a common thing, silently.
    // Unmask at the ARGUMENT BOUNDARY, not per call site: the same fix handles
    // %index's needle, %verify's excerpt, and the mirror direction (a MASKED
    // SUBJECT never split on an unmasked delimiter either). This is verbatim what
    // handleSysfunc already does one function over — the mask_comma doc calls that
    // "the %sysfunc argument boundary", and its Q-result comment already claims to
    // "mirror the Q-form macro fns (%qscan/…)"; macroFn is the half that drifted.
    for (args.items) |*arg| arg.* = try unmaskTriggers(st.a, arg.*);
    // Numeric position/length (substr) and count (scan) args carry implicit
    // %eval semantics: `%substr(x,1+1,%length(x)-3)` uses 2 and len-3, not the
    // raw text (BUG-domainrows-empty). Evaluate those slots before computing.
    const numeric: []const usize = switch (kind) {
        .substr => &.{ 1, 2 },
        .scan => &.{1},
        else => &.{},
    };
    for (numeric) |ni| {
        if (ni < args.items.len and args.items[ni].len > 0)
            args.items[ni] = std.fmt.allocPrint(st.a, "{d}", .{evalInt(st, args.items[ni]) catch continue}) catch continue;
    }
    const res = try computeMacroFn(st.a, kind, args.items);
    // The Q-form quotes its RESULT — mask every &/% AND comma, the same rule
    // %QSYSFUNC uses (maskTriggers, not the old maskAmps): now that the args are
    // unmasked above, re-masking only '&' would let a quoted comma escape the Q
    // form as a live argument delimiter. Plain %scan/%substr return unmasked, as
    // plain %sysfunc does — SAS's non-Q functions do not quote their result.
    try out.appendSlice(st.a, if (quote) try maskTriggers(st.a, res) else res);
    return k;
}

fn macroArg(args: []const []const u8, i: usize) []const u8 {
    return if (i < args.len) args[i] else "";
}

fn intArg(args: []const []const u8, i: usize, default: i64) i64 {
    return std.fmt.parseInt(i64, std.mem.trim(u8, macroArg(args, i), " \t\r\n"), 10) catch default;
}

/// The default word delimiters for `%scan` (SAS's macro-language set).
const scan_delims = " \t\r\n.<(+&!$*);^-/,%|";

fn computeMacroFn(a: std.mem.Allocator, kind: MacroFn, args: []const []const u8) Error![]const u8 {
    const s = macroArg(args, 0);
    switch (kind) {
        .upcase, .lowcase => {
            const o = try a.alloc(u8, s.len);
            for (s, 0..) |c, i| o[i] = if (kind == .upcase) std.ascii.toUpper(c) else std.ascii.toLower(c);
            return o;
        },
        .left => return std.mem.trimStart(u8, s, " "),
        .trim => return std.mem.trimEnd(u8, s, " "),
        // strip lead/trail blanks and collapse each run of internal blanks to one
        .cmpres => {
            const t = std.mem.trim(u8, s, " ");
            var o: std.ArrayList(u8) = .empty;
            var i: usize = 0;
            while (i < t.len) : (i += 1) {
                try o.append(a, t[i]);
                if (t[i] == ' ') while (i + 1 < t.len and t[i + 1] == ' ') {
                    i += 1;
                };
            }
            return o.items;
        },
        .substr => {
            const pos = intArg(args, 1, 1); // 1-based
            if (pos < 1 or pos > @as(i64, @intCast(s.len))) return "";
            const start: usize = @intCast(pos - 1);
            const remain = s.len - start;
            const len: usize = if (args.len > 2) @min(remain, @as(usize, @intCast(@max(0, intArg(args, 2, 0))))) else remain;
            return s[start .. start + len];
        },
        .scan => return scanWord(a, s, intArg(args, 1, 1), if (args.len > 2) macroArg(args, 2) else scan_delims),
        .index => {
            const p = std.mem.indexOf(u8, s, macroArg(args, 1));
            return std.fmt.allocPrint(a, "{d}", .{if (p) |x| x + 1 else 0}); // 1-based, 0 = absent
        },
        .length => return std.fmt.allocPrint(a, "{d}", .{s.len}),
        // NUMERIC if the value parses as a number, else CHAR. ponytail: parseFloat
        // covers decimal/scientific; SAS hex/binary literals read CHAR.
        .datatyp => {
            const t = std.mem.trim(u8, s, " \t\r\n");
            if (t.len == 0) return "CHAR";
            _ = std.fmt.parseFloat(f64, t) catch return "CHAR";
            return "NUMERIC";
        },
        // 1-based position of the first char of s NOT present in args[1]; 0 if
        // every char is present (empty excerpt → first char, like DATA-step VERIFY).
        .verify => {
            const excerpt = macroArg(args, 1);
            for (s, 0..) |c, i|
                if (std.mem.indexOfScalar(u8, excerpt, c) == null)
                    return std.fmt.allocPrint(a, "{d}", .{i + 1});
            return "0";
        },
    }
}

/// The `n`-th word of `s` (1-based; negative counts from the end), split on any
/// `delims` character; runs of delimiters collapse. Out-of-range → "".
fn scanWord(a: std.mem.Allocator, s: []const u8, n: i64, delims: []const u8) Error![]const u8 {
    var words: std.ArrayList([]const u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        while (i < s.len and std.mem.indexOfScalar(u8, delims, s[i]) != null) i += 1;
        const ws = i;
        while (i < s.len and std.mem.indexOfScalar(u8, delims, s[i]) == null) i += 1;
        if (i > ws) try words.append(a, s[ws..i]);
    }
    const cnt: i64 = @intCast(words.items.len);
    const idx: i64 = if (n < 0) cnt + n else n - 1;
    if (idx < 0 or idx >= cnt) return "";
    return words.items[@intCast(idx)];
}

const Paren = struct { text: []const u8, end: usize, closed: bool }; // end = index past the ')'; closed=false ⇒ ran to EOF with no matching ')'

/// The balanced-parenthesis argument starting at/after `from`. Null if there is
/// no `(`. Handles nested parens (so `%sysfunc(upcase(x))` reads `upcase(x)`).
/// A `%`-escaped char is literal text, never a paren — `%str(a%(b)` must not
/// treat the escaped `(` as nesting (BUG-macropctmask).
fn parenArg(src: []const u8, from: usize) ?Paren {
    const k = skipWs(src, from);
    if (k >= src.len or src[k] != '(') return null;
    var depth: usize = 1;
    var i = k + 1;
    const cs = i;
    while (i < src.len and depth > 0) {
        if (src[i] == '%' and i + 1 < src.len and isPctEscapable(src[i + 1])) {
            i += 2; // `%(` `%)` `%%` `%…` — escaped literal, skip both bytes
            continue;
        }
        if (src[i] == '(') {
            depth += 1;
        } else if (src[i] == ')') {
            depth -= 1;
            if (depth == 0) break;
        }
        i += 1;
    }
    return .{ .text = src[cs..i], .end = if (i < src.len) i + 1 else i, .closed = depth == 0 };
}

/// `%global v1 v2 …;` / `%local v1 v2 …;` — one global symbol table here, so this
/// just ensures each name exists (empty) so a later `&v` resolves. ponytail: no
/// real scoping; %local does not shadow.
/// `%syscall routine(name1, name2, …);` — invoke a CALL routine whose arguments are
/// macro-variable NAMES; the routine mutates their values in place. SORTN (numeric)
/// and SORTC (character) are supported (the common macro-array sort); other routines
/// are a NOTE and no-op so the statement never leaks to the lexer.
fn handleSyscall(st: *State, src: []const u8, from: usize) Error!usize {
    var k = skipWs(src, from);
    const rs = k;
    while (k < src.len and isNameChar(src[k])) k += 1;
    const routine = src[rs..k];
    const pa = parenArg(src, skipWs(src, k)) orelse {
        var e = k;
        while (e < src.len and src[e] != ';') e += 1;
        return if (e < src.len) e + 1 else e;
    };
    var names: std.ArrayList([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, pa.text, ',');
    while (it.next()) |a| {
        const nm = std.mem.trim(u8, try resolveText(st, a), " \t");
        if (nm.len > 0) try names.append(st.a, nm);
    }
    if (eqi(routine, "sortn")) {
        try syscallSort(st, names.items, false);
    } else if (eqi(routine, "sortc")) {
        try syscallSort(st, names.items, true);
    } else {
        try st.diags.note(0, "%syscall {s} is not supported", .{routine});
    }
    var e = pa.end;
    while (e < src.len and src[e] != ';') e += 1;
    return if (e < src.len) e + 1 else e;
}

/// Sort the values of the named macro variables in place (SORTN numeric / SORTC char).
fn syscallSort(st: *State, names: []const []const u8, char: bool) Error!void {
    if (char) {
        const vals = try st.a.alloc([]const u8, names.len);
        // Snapshot the values: the setVar below reallocs/frees the owned buffer
        // a getVar slice aliases (PERF-macroaccum), and names may repeat.
        for (names, 0..) |nm, i| vals[i] = try st.a.dupe(u8, st.getVar(nm) orelse "");
        std.mem.sort([]const u8, vals, {}, struct {
            fn f(_: void, x: []const u8, y: []const u8) bool {
                return std.mem.lessThan(u8, x, y);
            }
        }.f);
        for (names, 0..) |nm, i| try st.setVar(nm, vals[i]);
    } else {
        const nums = try st.a.alloc(f64, names.len);
        for (names, 0..) |nm, i|
            nums[i] = std.fmt.parseFloat(f64, std.mem.trim(u8, st.getVar(nm) orelse "0", " ")) catch 0;
        std.mem.sort(f64, nums, {}, comptime std.sort.asc(f64));
        for (names, 0..) |nm, i| {
            const txt = if (nums[i] == @trunc(nums[i]) and @abs(nums[i]) < 1e15)
                try std.fmt.allocPrint(st.a, "{d}", .{@as(i64, @intFromFloat(nums[i]))})
            else
                try std.fmt.allocPrint(st.a, "{d}", .{nums[i]});
            try st.setVar(nm, txt);
        }
    }
}

/// GAP-macrooracle-tick284 (F9) — printed p.77 rule 2 case 3: "If the executing
/// macro contains a computed %GOTO statement, the variable will be created in
/// the local symbol table", i.e. CALL SYMPUT "behaves as if the local symbol
/// table was not empty" (p.77, continuing onto printed p.78). CONTAINS, not
/// executes — the doc's condition is presence in the macro (parallel to
/// SYSPBUFF "created at macro invocation time"), so a never-taken
/// `%if 1=0 %then %goto &x;` still counts. A computed %GOTO is one "that uses a
/// label that contains an & or a % in it" (p.77; same definition as the p.396
/// footnote GAP-macrogotocomputed cites). Lexical scan for `%goto` whose operand
/// (up to ';') holds & or % — matches handlePercent, which dispatches only the
/// one-word form, so `%go to` is not looked for either.
/// ponytail: `/* */` comments are skipped (a commented-out computed %goto does
/// not count); `%*` macro comments and a nested %macro's body text are not —
/// both false-positive paths are contrived, and the failure is a symput var
/// landing local instead of global, never a crash. Tighten if a real program
/// trips either.
fn containsComputedGoto(body: []const u8) bool {
    var i: usize = 0;
    while (i < body.len) {
        if (body[i] == '/' and i + 1 < body.len and body[i + 1] == '*') {
            const end = std.mem.indexOfPos(u8, body, i + 2, "*/") orelse return false;
            i = end + 2;
            continue;
        }
        if (body[i] == '%' and i + 5 <= body.len and
            std.ascii.eqlIgnoreCase(body[i + 1 .. i + 5], "goto") and
            (i + 5 == body.len or !isNameChar(body[i + 5])))
        {
            var j = i + 5;
            while (j < body.len and body[j] != ';') : (j += 1)
                if (body[j] == '&' or body[j] == '%') return true;
            i = j;
        } else i += 1;
    }
    return false;
}

test "containsComputedGoto: only a label holding & or % counts, comments do not" {
    try std.testing.expect(containsComputedGoto("%goto &home;"));
    try std.testing.expect(containsComputedGoto("%GOTO %scrub(x);"));
    try std.testing.expect(containsComputedGoto("%if 1=0 %then %goto &where;"));
    try std.testing.expect(!containsComputedGoto("%goto done; %done:"));
    try std.testing.expect(!containsComputedGoto("%gotox &y;")); // not a %goto
    try std.testing.expect(!containsComputedGoto("/* %goto &x; */ data;"));
    try std.testing.expect(!containsComputedGoto("%put nothing here;"));
}

/// `%goto LABEL;` — set the unwind target; process() drops output until it hits
/// `%LABEL:`. Used for macro early-return (`%if err %then %goto exit;` … `%exit:`).
///
/// GAP-macrogotocomputed — the operand is a TEXT EXPRESSION, not a bare name.
/// SAS 9.4 Macro Language: Reference, Fifth Edition, printed p.396 (pdf 411 —
/// offset printed+15, verified here against the "396 Chapter 19 / Macro
/// Statements" footer immediately preceding the `=== pdf 412 ===` marker),
/// "%GOTO Macro Statement", Required Argument `label`:
///
///   "is either the name of the label that you want execution to branch to or a
///    text expression that generates the label. A text expression that generates
///    a label in a %GOTO statement is called a computed %GOTO destination."
///     … "%goto &home;  /* branch to the label that is the value of the macro
///        variable HOME */"
///   footnote: "A computed %GOTO contains % or & and resolves to a label."
///
/// So the operand is resolved through the SHARED resolveText (the same expander
/// every other macro-expanding site here uses — handleScope resolves `%global
/// &dataset.KEEP;` the same way), and only the RESULT is the label. Reading it
/// with isNameChar stopped dead at the `&`, producing an EMPTY target — which
/// process() then never matches, so the empty target swallowed the whole rest of
/// the macro body and the run still exited 0 with a warning naming no label at
/// all. Two DATA steps silently vanished; the worst failure class.
///
/// WHAT THE DOC CONSTRAINS THE RESULT TO, and both cases are errors it names by
/// text (printed pp.500-501, "SAS Macro Error Messages"):
///   * null — "A macro variable was used as the label in a %GOTO statement but
///     has a null value. The label for the %GOTO statement must be a valid SAS
///     name." → "Error: The %GOTO statement has no target. The statement will be
///     ignored." IGNORED is load-bearing: we must not set a target, or the body
///     after it disappears.
///   * not a SAS name (`%goto a-1;`, or a stray `&`/`%` left by an unresolved
///     reference) — "Error: In macro value, the target of the statement %GOTO
///     value, resolved into the label value, which is not a valid statement
///     label." Same ignore-and-report treatment.
/// A resolved-but-absent label is NOT diagnosable here (the label may appear
/// later in the body); handleCall reports it at the macro boundary, and now
/// prints the RESOLVED text rather than the empty string.
fn handleGoto(st: *State, src: []const u8, from: usize) Error!usize {
    var k = from;
    while (k < src.len and src[k] != ';') k += 1; // whole operand, up to the ';'
    const operand = std.mem.trim(u8, src[from..k], " \t\r\n");
    const after = if (k < src.len) k + 1 else k;
    // `%GOTO` outside any macro is invalid. SAS reports an error and CONTINUES;
    // we must NOT set `goto_target` — an open-code target would make process()
    // drop every following statement and exit 0 with no diagnostic (silent-wrong).
    // Mirrors the `%RETURN` open-code guard in handlePercent (macroErr = loud +
    // non-zero exit, later independent steps still run). Checked BEFORE resolving:
    // an invalid statement must not run its operand's macro calls for side effects.
    // Wording is SAS's exact text (Macro Language Ref, App.2 printed p.500, the
    // nine-statement open-code family: "Error: The %GOTO statement is not valid
    // in open code." — "Error:" is SAS's severity PREFIX, the renderer adds its
    // own tag, so the body carries the sentence only — NOTE-gotodoopencode).
    if (st.macro_call_depth == 0) {
        try st.diags.macroErr(0, "The %GOTO statement is not valid in open code.", .{});
        return after;
    }
    const label = std.mem.trim(u8, try resolveText(st, operand), " \t\r\n");
    if (label.len == 0) {
        try st.diags.macroErr(0, "The %GOTO statement has no target. The statement will be ignored", .{});
        return after;
    }
    // "The label must be a valid SAS name that contains no special characters"
    // (printed p.500) — the same V7 rule NVALID enforces, so reuse it rather than
    // spell the character set out a second time.
    if (!functions.isValidName(label)) {
        try st.diags.macroErr(0, "The target of the statement %GOTO {s} resolved into the label {s}, which is not a valid statement label", .{ operand, label });
        return after;
    }
    st.goto_target = try lowerDup(st.a, label);
    return after;
}

fn handleScope(st: *State, src: []const u8, from: usize, is_local: bool) Error!usize {
    // Resolve the whole name list first: SAS allows a `&var` reference to NAME the
    // variable, e.g. `%global &dataset.KEEPSTRING;` → declares `<dataset>KEEPSTRING`
    // (BUG-makeemptyhang: the old char-by-char loop never advanced past the `&`/`.`
    // and never resolved it → infinite spin). One pass to the `;`, then split on
    // whitespace/commas — no inner cursor to stall.
    var e = from;
    while (e < src.len and src[e] != ';') e += 1;
    // `%LOCAL` outside any macro is invalid. Was a SILENT declare-and-continue
    // (exit 0, no diagnostic) — silent wrong output on invalid SAS, the failure
    // class house rules put first. SAS reports an error and CONTINUES (Macro
    // Language Ref App.2 ERROR Messages section, printed p.500: "Error: The
    // %LOCAL statement is not valid in open code." — "Error:" is SAS's severity
    // PREFIX, the renderer adds its own tag). Cause there: "executed outside a
    // macro definition" → the user's code is invalid SAS → D-009 exit 1 via
    // macroErr (macro_scoped — no step-skip, later steps still run), same shape
    // as the %RETURN/%GOTO/%DO open-code guards (SEV-opencodefamilyrest).
    // Checked BEFORE resolving: an invalid statement must not run its operand's
    // macro calls for side effects (same call as the %GOTO guard). %GLOBAL is
    // NOT in the family — valid in open code — so only the is_local arm guards.
    if (is_local and st.macro_call_depth == 0) {
        try st.diags.macroErr(0, "The %LOCAL statement is not valid in open code.", .{});
        return if (e < src.len) e + 1 else e;
    }
    const names = try resolveText(st, src[from..e]);
    var it = std.mem.tokenizeAny(u8, names, " \t\r\n,");
    while (it.next()) |nm| {
        if (is_local) { // shadow any outer var; restored when the macro returns
            try st.declareLocal(nm);
            try st.setVar(nm, "");
        } else if (st.findLocal(nm) != null) {
            // SAS errors "Attempt to %GLOBAL a name (X) which exists in a local
            // environment" (F10); the silent no-op left the caller believing a
            // global exists while the local swallowed every assignment.
            try st.diags.macroErr(0, "Attempt to %GLOBAL a name ({s}) which exists in a local environment", .{try upperDup(st.a, nm)});
        } else if (st.getVar(nm) == null) {
            try st.setVar(nm, "");
        }
    }
    return if (e < src.len) e + 1 else e; // past ';'
}

/// How a quoting fn treats its argument (SAS 9.4 quoting taxonomy).
const MaskMode = enum {
    resolve, // %str/%quote/%bquote — resolve `&`/`%`, no post-mask
    mask_only, // %nrstr — verbatim, triggers masked (never resolve)
    resolve_mask, // %nrbquote/%nrquote — resolve FIRST, then mask what survives
};

/// `%str`/`%quote`/`%bquote` resolve `&`/`%` in the argument; `%nrstr` emits it
/// verbatim with the triggers sentinel-masked so they can never re-resolve,
/// even after the value is stored and referenced again (BUG-macronrstrmask).
/// `%nrbquote`/`%nrquote` are EXECUTION-time: they RESOLVE macro references
/// first, then mask the `&`/`%` that survive in the result so a later rescan
/// can't re-fire them (BUG-macronrbquoteresolve / BUG-macronrquotemissing).
/// In every mode a `%`-escaped special folds to the literal char first
/// (BUG-macropctmask): `%%`→`%`, `%&`→`&`, `%(`→`(`, …
fn handleMask(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8), mode: MaskMode, fname: []const u8) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    // An unclosed argument ran to EOF: the `)` was never found (`%str(%)` escapes
    // its own paren, a bare trailing `%str(a`, …). Silently returning the swallowed
    // remainder drops the assignment and every following statement at exit 0 — the
    // worst failure class. Fail LOUD like the %GOTO open-code / %LET quote-eof
    // guards (BUG-macrounclosedparen). The rest is consumed (the boundary is
    // unrecoverable) but the loss is now announced, not silent.
    if (!pa.closed) {
        try st.diags.macroErr(0, "unclosed %{s}( argument — ')' not found before end of file", .{try upperDup(st.a, fname)});
        return pa.end;
    }
    const folded = try foldPctEscapes(st.a, pa.text);
    const text = switch (mode) {
        .resolve, .resolve_mask => try resolveText(st, folded),
        .mask_only => folded,
    };
    try out.appendSlice(st.a, switch (mode) {
        .resolve => try maskGroupA(st.a, text),
        .mask_only, .resolve_mask => try maskTriggers(st.a, text),
    });
    return pa.end;
}

/// The chars a `%` escapes inside macro-quoting argument text (SAS %STR
/// convention): the escape masks that one char and the leading `%` is dropped.
fn isPctEscapable(c: u8) bool {
    return c == '%' or c == '&' or c == '(' or c == ')' or c == '\'' or c == '"';
}

/// Fold `%`-escaped specials in quoting-fn argument text (BUG-macropctmask):
/// `%x` → literal `x` for x ∈ {%, &, (, ), ', "}. A folded `&` or `%` comes out
/// SENTINEL-masked so no later rescan re-fires it — `%str(a%%b)` stored and
/// referenced must yield `a%b`, never warn about an apparent macro B.
fn foldPctEscapes(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    var found = false;
    var i: usize = 0;
    while (i + 1 < s.len) : (i += 1) {
        if (s[i] == '%' and isPctEscapable(s[i + 1])) {
            found = true;
            break;
        }
    }
    if (!found) return s; // common case: nothing to fold, borrow the slice
    var out: std.ArrayList(u8) = .empty;
    i = 0;
    while (i < s.len) {
        if (s[i] == '%' and i + 1 < s.len and isPctEscapable(s[i + 1])) {
            const c = s[i + 1];
            try out.append(a, if (c == '&') mask_amp else if (c == '%') mask_pct else c);
            i += 2;
        } else {
            try out.append(a, s[i]);
            i += 1;
        }
    }
    return out.items;
}

/// `%superq(name)` — the *unresolved* value of the macro variable named by the
/// argument, with all & and % in the value left masked (not rescanned). The name
/// itself is resolved (so `%superq(&x)` works); an undefined variable yields empty.
/// This is the standard defensive quote for values that may contain & or %.
fn handleSuperq(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    if (!pa.closed) { // ran to EOF unclosed — fail loud, never swallow (BUG-macrounclosedparen)
        try st.diags.macroErr(0, "unclosed %SUPERQ( argument — ')' not found before end of file", .{});
        return pa.end;
    }
    var name = std.mem.trim(u8, try resolveText(st, pa.text), " \t");
    if (name.len > 0 and name[0] == '&') name = name[1..]; // tolerate %superq(&x)
    if (st.getVar(name)) |val| {
        // MASK every real &/% (and comma) in the RAW value with the same sentinels
        // %NRSTR uses, so downstream resolution can never re-fire them (F1). A value
        // that is already masked (from %nrstr) or has no specials passes unchanged.
        try out.appendSlice(st.a, try maskTriggers(st.a, val));
    } else {
        // Undefined var is not silently empty (F1): SAS warns and yields empty text.
        try st.diags.warn(0, "Apparent symbolic reference {s} not resolved.", .{try upperDup(st.a, name)});
    }
    return pa.end;
}

const SymScope = enum { exist, global, local };

/// `%symexist(name)` — "1" if the macro variable exists at all. `%symglobl(name)`
/// — "1" only if it exists in the GLOBAL table: a %local var does NOT count
/// (BUG-macrosymglobl) unless it shadows a pre-existing outer value (findLocal's
/// saved prev), matching SAS where that global still exists. `%symlocal(name)`
/// — "1" only if declared %local in an ACTIVE macro scope (BUG-macrosymlocal).
/// The name argument is resolved first (so `%symexist(&x)` works).
fn handleSymExist(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8), mode: SymScope) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    var name = std.mem.trim(u8, try resolveText(st, pa.text), " \t");
    if (name.len > 0 and name[0] == '&') name = name[1..];
    const loc = st.findLocal(name);
    const yes = switch (mode) {
        .exist => st.getVar(name) != null,
        .global => st.getVar(name) != null and (loc == null or loc.?.prev != null),
        .local => loc != null,
    };
    try out.appendSlice(st.a, if (yes) "1" else "0");
    return pa.end;
}

/// `%symdel v1 <v2 …> </ nowarn>;` — delete macro variables (GAP-macrosymdel).
/// The name list is resolved first (a `&ref` may name the var); everything
/// after a `/` is options. SAS warns when a named variable does not exist
/// unless NOWARN is given. ponytail: one shared table — a %symdel inside a
/// macro can drop a var a scope would have restored (SAS restricts it to
/// globals); nobody hits that without real scoping.
fn handleSymdel(st: *State, src: []const u8, from: usize) Error!usize {
    var e = from;
    while (e < src.len and src[e] != ';') e += 1;
    const resolved = try resolveText(st, src[from..e]);
    const slash = std.mem.indexOfScalar(u8, resolved, '/');
    const names = if (slash) |s| resolved[0..s] else resolved;
    const opts = if (slash) |s| resolved[s + 1 ..] else "";
    var nowarn = false;
    var oit = std.mem.tokenizeAny(u8, opts, " \t\r\n,");
    while (oit.next()) |o| if (eqi(o, "nowarn")) {
        nowarn = true;
    };
    var it = std.mem.tokenizeAny(u8, names, " \t\r\n,");
    while (it.next()) |nm| {
        var buf: [256]u8 = undefined;
        if (nm.len > buf.len) continue;
        for (nm, 0..) |c, i| buf[i] = std.ascii.toLower(c);
        const lname = buf[0..nm.len];
        // AUTOMATIC macro variables cannot be deleted (F10): the sys* prefix is
        // this codebase's automatic classifier (dumpPutVars) and SAS reserves
        // it. Deleting &SYSDATE9 &co silently corrupts every later reference —
        // a wrong-answer generator, not a diagnostics nit. /nowarn only
        // suppresses the not-found warning, never this.
        if (std.mem.startsWith(u8, lname, "sys")) {
            try st.diags.macroErr(0, "The automatic macro variable {s} cannot be deleted (%SYMDEL)", .{try upperDup(st.a, nm)});
            continue;
        }
        if (st.vars.fetchRemove(lname)) |kv| {
            var v = kv.value;
            v.deinit();
            functions.setLetVar(lname, "") catch {}; // drop the SYMGET mirror too
        } else if (!nowarn) {
            try st.diags.warn(0, "apparent attempt to delete macro variable {s} failed — variable not found", .{try upperDup(st.a, nm)});
        }
    }
    return if (e < src.len) e + 1 else e; // past ';'
}

/// `%sysmacexist(name)` — "1" if a macro named `name` is defined, else "0".
fn handleSysmacexist(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    const name = std.mem.trim(u8, try resolveText(st, pa.text), " \t");
    try out.appendSlice(st.a, if (st.getMacro(name) != null) "1" else "0");
    return pa.end;
}

/// `%unquote(text)` — remove masking so any & / % in the (already resolved) value
/// resolve now: resolve the argument, drop any &/% sentinel mask, then resolve
/// the result once more.
fn handleUnquote(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    const once = try resolveText(st, pa.text);
    try out.appendSlice(st.a, try resolveText(st, try unmaskTriggers(st.a, once)));
    return pa.end;
}

/// `%sysget(VAR)` — the value of host environment variable VAR
/// (GAP-macroautofeatures F6). An unset variable yields an empty result + a
/// WARNING (SAS warns). The value is returned unquoted, like plain %sysfunc;
/// the name is case-sensitive on Unix, matching SAS.
fn handleSysget(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    if (!pa.closed) { // fail LOUD like the %str unclosed-paren guard — never drop silently
        try st.diags.macroErr(0, "unclosed %SYSGET( argument — ')' not found before end of file", .{});
        return pa.end;
    }
    const name = std.mem.trim(u8, try resolveText(st, pa.text), " \t\r\n");
    if (envValue(st.a, name)) |val| {
        try out.appendSlice(st.a, val);
    } else {
        try st.diags.warn(0, "%SYSGET: environment variable {s} is not defined", .{name});
    }
    return pa.end;
}

/// Host environment lookup for %SYSGET.
/// ponytail: zig 0.16 exposes the environment only via std.process.Init,
/// which the macro layer doesn't carry. macOS links libSystem (build.zig) →
/// plain getenv; Linux stays libc-free and scans /proc/self/environ. Other
/// targets always miss (→ the %SYSGET warning); wire Init.environ_map down
/// from main.zig when another port needs it.
fn envValue(a: std.mem.Allocator, name: []const u8) ?[]const u8 {
    if (name.len == 0) return null;
    if (@import("builtin").os.tag == .macos) {
        const nz = a.dupeZ(u8, name) catch return null;
        const v = std.c.getenv(nz) orelse return null;
        return std.mem.span(v);
    }
    if (@import("builtin").os.tag != .linux) return null;
    const io = std.Io.Threaded.global_single_threaded.io();
    const file = std.Io.Dir.cwd().openFile(io, "/proc/self/environ", .{}) catch return null;
    defer file.close(io);
    // /proc reports st_size 0 — both readFileAlloc and the streaming reader
    // trust the size and return "" — so pread chunks until a short read.
    var buf: std.ArrayList(u8) = .empty;
    var chunk: [16384]u8 = undefined;
    while (buf.items.len < (1 << 20)) { // environ can't exceed the kernel arg max
        const n = file.readPositional(io, &.{chunk[0..]}, buf.items.len) catch return null;
        if (n == 0) break;
        buf.appendSlice(a, chunk[0..n]) catch return null;
    }
    return envScan(buf.items, name);
}

/// The `name=value` lookup over a NUL-separated environ block (split out so a
/// test can pin the parse without depending on this machine's environment).
fn envScan(buf: []const u8, name: []const u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, buf, 0);
    while (it.next()) |entry| {
        const eq = std.mem.indexOfScalar(u8, entry, '=') orelse continue;
        if (std.mem.eql(u8, entry[0..eq], name)) return entry[eq + 1 ..];
    }
    return null;
}

/// `%sysfunc(fn(args) [, fmt])` — call a DATA-step function on the (resolved)
/// arguments. ponytail: a common subset of the string/edit functions; the
/// optional output format is ignored.
fn handleSysfunc(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8), quote: bool) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    const inner = try resolveText(st, pa.text); // nested %sysfunc already resolved
    const lp = std.mem.indexOfScalar(u8, inner, '(') orelse {
        try st.diags.note(0, "%sysfunc without a function call", .{});
        return pa.end;
    };
    const fname = std.mem.trim(u8, inner[0..lp], " \t");
    // The function's own arguments end at the ')' MATCHING its '(' (balanced) — the
    // old lastIndexOf grabbed a trailing format's own text and dropped it.
    const mrp = matchParen(inner, lp);
    var fargs: std.ArrayList([]const u8) = .empty;
    try splitTopArgs(st.a, inner[lp + 1 .. mrp], &fargs);
    // A masked &/%/',' (from %nrstr/%superq/%str) survived the split as its
    // sentinel; hand the function layer the LITERAL character (F2 — SAS unmasks
    // every quoted trigger before the call, so the real function sees true chars).
    for (fargs.items) |*arg| arg.* = try unmaskTriggers(st.a, arg.*);
    // Whitespace-significant functions get args VERBATIM (BUG-sysfunctrim);
    // every other function gets blanks stripped per arg (SAS strips unquoted
    // argument blanks — and keyword args like attrn's attr-name need it).
    if (!wsSignificant(fname)) for (fargs.items) |*arg| {
        arg.* = std.mem.trim(u8, arg.*, " \t");
    };
    // Optional %sysfunc output format after the call: `%sysfunc(fn(...), fmt.)`
    // (BUG-sysfuncfmt). Apply it to the result via putn/putc.
    var fmt: []const u8 = "";
    var t = mrp + 1;
    while (t < inner.len and (inner[t] == ' ' or inner[t] == '\t')) t += 1;
    if (t < inner.len and inner[t] == ',') fmt = std.mem.trim(u8, inner[t + 1 ..], " \t");
    var result = try computeSysfunc(st.a, fname, fargs.items, st.diags);
    if (fmt.len > 0) {
        const put_fn: []const u8 = if (fmt[0] == '$') "putc" else "putn";
        const raw = result;
        // BUG-sysfuncformat(a): an unsupported %sysfunc output format must not
        // fail the run (or panic) — SAS macro code like `%let d=%sysfunc(today(),
        // yymmddn.)` should degrade to the raw value. Suppress format.zig's
        // fatal "format not found" (which else sets the non-zero-exit flag), fall
        // back to the raw value, and emit a clean macro WARNING instead.
        // BUG-sysfuncnofmterrclobber: RESTORE THE PRIOR VALUE, not the constant
        // `false`. `OPTIONS NOFMTERR;` sets this same global, so restoring to a
        // constant silently switched the user's option back ON — after any
        // %sysfunc that carried a format, a later genuine "format not found" was
        // reported and the run exited 1, for an option the program had asked to
        // be off. The suppression here is a LOCAL borrow of a GLOBAL the user also
        // owns, so it has to be given back exactly as it was found.
        const prev_nofmterr = format.nofmterr();
        format.setNoFmtErr(true);
        result = try computeSysfunc(st.a, put_fn, &.{ raw, fmt }, st.diags);
        format.setNoFmtErr(prev_nofmterr);
        // A NAMED format that left the value unchanged fell back = unsupported.
        // ponytail: may also fire for a supported named numeric format (best8.)
        // whose output matches the raw digits; exact support-detection belongs to
        // part (b) in format.zig — this is a non-fatal log line, not behavior.
        const spec = format.parseSpec(fmt);
        if (spec.name.len > 0 and
            std.mem.eql(u8, std.mem.trim(u8, result, " "), std.mem.trim(u8, raw, " ")))
        {
            try st.diags.warn(0, "%sysfunc: format {s} not supported — using unformatted value", .{fmt});
        }
    }
    // %QSYSFUNC quotes its RESULT (F2): mask every &/% (and comma) so a later
    // reference can't re-resolve them — mirrors the Q-form macro fns (%qscan/…).
    // Plain %sysfunc returns the result unmasked (SAS does not quote it).
    try out.appendSlice(st.a, if (quote) try maskTriggers(st.a, result) else result);
    return pa.end;
}

/// Index of the ')' that matches the '(' at `lp` (balanced); s.len if unbalanced.
fn matchParen(s: []const u8, lp: usize) usize {
    var depth: usize = 0;
    var k = lp;
    while (k < s.len) : (k += 1) {
        if (s[k] == '(') depth += 1 else if (s[k] == ')') {
            depth -= 1;
            if (depth == 0) return k;
        }
    }
    return s.len;
}

/// `%sysfunc` functions whose string arguments are DATA in which leading/
/// trailing blanks are observable (a blank separator, a space from/to string,
/// padding to reverse) — these receive their args verbatim (BUG-sysfunctrim).
/// Their DATA-step implementations carry the SAS blank semantics themselves
/// (catx strips item values, keeps the separator; numeric args re-trim in
/// sysfuncDispatch). Everything else %sysfunc calls gets per-arg blanks
/// stripped, the old behavior keyword lookups (attrn/varnum) rely on.
fn wsSignificant(fname: []const u8) bool {
    const list = .{ "tranwrd", "translate", "cat", "cats", "catt", "catx", "catq", "repeat", "reverse" };
    inline for (list) |f| if (eqi(fname, f)) return true;
    return false;
}

/// Split a function-argument list on top-level commas (nested parens are kept
/// intact); empty/blank input yields zero arguments (a zero-arg call). A comma
/// quoted by %str & co. arrives as the mask_comma sentinel and never splits
/// (BUG-sysfunccommamask) — callers unmask per arg afterwards.
fn splitTopArgs(a: std.mem.Allocator, s: []const u8, list: *std.ArrayList([]const u8)) Error!void {
    if (std.mem.trim(u8, s, " \t").len == 0) return;
    var depth: usize = 0;
    var start: usize = 0;
    var k: usize = 0;
    while (k < s.len) : (k += 1) {
        if (s[k] == '(') {
            depth += 1;
        } else if (s[k] == ')') {
            if (depth > 0) depth -= 1;
        } else if (s[k] == ',' and depth == 0) {
            // ponytail: NO trim — macro whitespace is significant
            // (%sysfunc(catx(%str( ),a,b)) must keep the blank separator;
            // BUG-sysfunctrim). Numeric paths re-trim on their own.
            try list.append(a, s[start..k]);
            start = k + 1;
        }
    }
    try list.append(a, s[start..]);
}

/// The DATA-step functions `%sysfunc` supports here: a macro-tuned string/edit
/// subset, then anything else (numeric functions like max/min/int/round/abs, …)
/// through the real function table so `%sysfunc(max(3,7))` → 7.
fn computeSysfunc(a: std.mem.Allocator, fname: []const u8, args: []const []const u8, diags: *diag.Diagnostics) Error![]const u8 {
    const s = macroArg(args, 0);
    if (eqi(fname, "upcase")) return computeMacroFn(a, .upcase, args);
    if (eqi(fname, "lowcase")) return computeMacroFn(a, .lowcase, args);
    if (eqi(fname, "substr")) return computeMacroFn(a, .substr, args);
    if (eqi(fname, "index")) return computeMacroFn(a, .index, args);
    if (eqi(fname, "scan")) return computeMacroFn(a, .scan, args);
    if (eqi(fname, "length")) return std.fmt.allocPrint(a, "{d}", .{std.mem.trimEnd(u8, s, " ").len});
    if (eqi(fname, "strip")) return std.mem.trim(u8, s, " \t");
    if (eqi(fname, "left")) return std.mem.trimStart(u8, s, " \t");
    if (eqi(fname, "trim")) return std.mem.trimEnd(u8, s, " \t");
    if (eqi(fname, "compress")) {
        if (args.len >= 3) return sysfuncDispatch(a, fname, args, diags); // modifier form (kd/s/…) → real COMPRESS
        const rem = if (args.len > 1) macroArg(args, 1) else " ";
        const o = try a.alloc(u8, s.len);
        var n: usize = 0;
        for (s) |c| if (std.mem.indexOfScalar(u8, rem, c) == null) {
            o[n] = c;
            n += 1;
        };
        return o[0..n];
    }
    return sysfuncDispatch(a, fname, args, diags);
}

/// A quoted SAS date/time/datetime literal (`'15JAN2020'd`, `'12:00't`,
/// `'01JAN2020:12:00'dt`; single or double quotes) → its SAS numeric value, or
/// null if `s0` isn't one. Lets %sysfunc/%sysevalf evaluate a date literal in
/// their args instead of coercing the raw string to NaN (BUG-macrodateliteral).
fn macroDateLiteral(s0: []const u8) ?f64 {
    const s = std.mem.trim(u8, s0, " \t");
    if (s.len < 3) return null;
    const q = s[0];
    if (q != '\'' and q != '"') return null;
    const close = std.mem.lastIndexOfScalar(u8, s, q) orelse return null;
    if (close == 0) return null;
    const inner = s[1..close];
    const suffix = s[close + 1 ..];
    if (eqi(suffix, "dt")) return eval.datetimeConst(inner);
    if (eqi(suffix, "d")) return eval.dateConst(inner);
    if (eqi(suffix, "t")) return eval.timeConst(inner);
    return null;
}

/// Route a `%sysfunc` call through the DATA-step function table. Each argument
/// becomes a numeric Value if it parses as a number (or a date/time literal),
/// else a char Value; the result is rendered back to macro text (integers
/// without a decimal, `.` for a missing/NaN result).
fn sysfuncDispatch(a: std.mem.Allocator, fname: []const u8, args: []const []const u8, diags: *diag.Diagnostics) Error![]const u8 {
    var pdv = Pdv.init(a);
    var ev: eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = diags, .call_fn = &functions.dispatch };
    const vals = try a.alloc(Value, args.len);
    for (args, 0..) |arg, i| {
        const trimmed = std.mem.trim(u8, arg, " \t");
        if (macroDateLiteral(trimmed)) |dnum| {
            vals[i] = .{ .num = dnum };
        } else vals[i] = if (std.mem.eql(u8, trimmed, "."))
            Value.missing // bare `.` is a numeric missing (BUG-sysfuncmissingdot)
        else if (Value.parseSpecialMissing(trimmed)) |sm|
            sm // .A–.Z, ._
        else if (std.fmt.parseFloat(f64, trimmed)) |x| .{ .num = x } else |_| .{ .str = arg };
    }
    // NOTE-sysfuncattrnname: the SCL dataset family takes a DSID — a number handed
    // back by OPEN() — as argument 1. Passing the dataset NAME is the natural
    // mistake, and it used to char→num coerce to missing, so
    // `%sysfunc(attrn(work.d1,NOBS))` quietly yielded `.` at exit 0 with only a
    // conversion NOTE. Macro Language Reference printed p.518 documents the
    // diagnostic verbatim: "Argument value to function value referenced by the
    // %SYSFUNC or %QSYSFUNC macro function is not a number", cause "A nonnumeric
    // argument value is used instead of the expected numeric value."
    // A numeric MISSING stays legal here (it is a number): scl_baddsid pins
    // `attrn(., "NOBS")`, and that is the DATA-step path anyway — this guard is at
    // the %SYSFUNC boundary the doc's message explicitly names.
    // ponytail: argument 1 of THIS family only. A complete numeric-argument table
    // for every function is itself oracle-blocked — the doc's own remedy is "refer
    // to the documentation for the function", i.e. the Functions and CALL Routines
    // Reference, which is not in docs/. Widen when that volume lands.
    const dsid_fns = [_][]const u8{ "attrn", "attrc", "varnum", "varname", "vartype", "varlen", "varfmt", "varlabel", "fetch", "fetchobs", "curobs", "getvarn", "getvarc", "close" };
    for (dsid_fns) |f| {
        if (!eqi(fname, f)) continue;
        if (vals.len > 0 and vals[0] == .str) {
            try diags.macroErr(0, "Argument 1 to function {s} referenced by the %SYSFUNC or %QSYSFUNC macro function is not a number.", .{try upperDup(a, fname)});
            return "";
        }
        break;
    }
    const r = functions.dispatch(&ev, fname, vals) catch return "";
    return switch (r) {
        .str => |s| s,
        // SAS default: a numeric %sysfunc result renders through BEST12. (its
        // default num→char format), NOT raw f64 precision. So
        // `%sysfunc(constant(pi))` is `3.1415926536`, not 3.141592653589793,
        // and `%sysfunc(int(1e15))` is `1E15` (BUG-sysfuncbest).
        .num => |x| try format.bestNum(a, x),
    };
}

/// `%sysevalf(expr [, type])` — floating-point evaluation. `type` is
/// INTEGER/CEIL/FLOOR/BOOLEAN (default: the plain value). ponytail: `+ - * /`,
/// `**`, unary sign, parentheses, and ONE comparison (the doc's reason the
/// function exists — printed p.352/p.91); no AND/OR/NOT/IN — those are LOUD.
fn handleSysevalf(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const pa = parenArg(src, from) orelse return from;
    // split off an optional top-level `, type`
    var expr_text = pa.text;
    var type_text: []const u8 = "";
    var depth: usize = 0;
    for (pa.text, 0..) |c, i| {
        if (c == '(') depth += 1 else if (c == ')') depth -= 1 else if (c == ',' and depth == 0) {
            expr_text = pa.text[0..i];
            type_text = std.mem.trim(u8, pa.text[i + 1 ..], " \t");
            break;
        }
    }
    const resolved = try resolveText(st, expr_text);
    // NOTE-sysevalfempty: a null or all-blank expression is an ERROR, never a
    // silent 0 — printed p.354 quotes the message VERBATIM (used verbatim):
    //     ERROR: %SYSEVALF function has no expression to evaluate.
    // ("If expression evaluates to a null value or one or more blank spaces")
    // Nothing is emitted for the call. Report-only, no stopMacro: the entry
    // quotes only this one line and documents no termination (DOC-SILENT on
    // stopping — same read as the p.506 div-by-zero precedent in
    // reportEvalParse), and in open code there is no macro to stop anyway.
    if (std.mem.trim(u8, resolved, " \t\r\n").len == 0) {
        try st.diags.macroErr(0, "%SYSEVALF function has no expression to evaluate.", .{});
        return pa.end;
    }
    var fp = FloatParser{ .s = resolved };
    const v = fp.cmpr();
    // QA tick377 F3: anything the float grammar left unconsumed used to be
    // SILENTLY DROPPED — `%sysevalf(1.5 ^= 2.5)` returned 1.5, the left
    // operand, exit 0 (D-002's worst class: `%if %sysevalf(&x > &lim)` was
    // true whenever &x was non-zero). Loud now, in two D-009 classes: a
    // LOGICAL operator SAS supports in %SYSEVALF but the float grammar lacks
    // (and/or/not words, & | and bare ^ ~ \xC2\xAC) is an opensas GAP → rc 2;
    // anything else — including `in`, which SAS ITSELF rejects in %SYSEVALF
    // (Restriction, printed p.353) — is the user's own invalid expression →
    // rc 1. The value is still emitted (as %EVAL does on its parse errors),
    // with the same stop-the-macro pair (p.162, BUG-macroerrnostop).
    fp.ws();
    if (fp.i < resolved.len) {
        const rest = std.mem.trim(u8, resolved[fp.i..], " \t\r\n");
        const gap = switch (rest[0]) {
            '&', '|', '^', '~' => true,
            0xC2 => rest.len > 1 and rest[1] == 0xAC,
            else => blk: {
                var j: usize = 0;
                while (j < rest.len and std.ascii.isAlphabetic(rest[j])) j += 1;
                const op = wordOp(rest[0..j]) orelse break :blk false;
                break :blk op == .and_ or op == .or_ or op == .not_;
            },
        };
        try st.diags.macroErr(0, "%SYSEVALF: invalid or unsupported operator in '{s}'", .{try unmaskTriggers(st.a, rest)});
        if (gap) diag.markGap();
        try stopMacro(st);
    }
    // BUG-sysevalfmissingzero: a missing operand is NaN inside FloatParser and
    // PROPAGATES through arithmetic (Macro Language Reference printed pp.353-354:
    // `%sysevalf(10+.)` returns `.`; CEIL/FLOOR/INTEGER "an expression with a
    // missing value produces a missing value") — never coerced to 0. BOOLEAN is
    // the one conversion that maps missing to 0 (p.353: "0 if the result of the
    // expression is 0 or missing", `%sysevalf(10+.,boolean)` returns 0). SAS's
    // float model has no NaN distinct from missing, so any NaN — missing operand
    // or invalid op like (-1)**0.5 — renders as `.`. p.353 says CEIL also emits
    // "a message noting that fact" but never quotes it — DOC-SILENT, not invented.
    const r: f64 = if (eqi(type_text, "integer") or eqi(type_text, "int")) @trunc(v) else if (eqi(type_text, "ceil")) @ceil(v) else if (eqi(type_text, "floor")) @floor(v) else if (eqi(type_text, "boolean")) (if (v != 0 and !std.math.isNan(v)) 1 else 0) else v;
    if (std.math.isNan(r))
        try out.append(st.a, '.')
    else if (r == @trunc(r) and @abs(r) < 1e15)
        try out.print(st.a, "{d}", .{@as(i64, @intFromFloat(r))})
    else
        try out.print(st.a, "{d}", .{r});
    return pa.end;
}

/// A tiny recursive-descent float evaluator for `%sysevalf`.
const FloatParser = struct {
    s: []const u8,
    i: usize = 0,

    fn ws(self: *FloatParser) void {
        while (self.i < self.s.len and (self.s[self.i] == ' ' or self.s[self.i] == '\t' or self.s[self.i] == '\r' or self.s[self.i] == '\n')) self.i += 1;
    }
    /// QA tick377 F3: ONE optional comparison above the additive level (the
    /// same single-comparison level %EVAL's cmp() has), yielding 1/0. The
    /// layer was ABSENT, so every comparison operator was silently dropped
    /// and the left operand came back — while the dictionary entry's own
    /// summary says %SYSEVALF "Evaluates arithmetic AND LOGICAL expressions
    /// using floating-point arithmetic" (Macro Language Reference printed
    /// p.352), and printed p.91: "You must use the %SYSEVALF function to
    /// evaluate logical expressions containing floating-point or missing
    /// values" — comparisons are this function's documented reason to exist.
    /// Shares %EVAL's Cmp enum and Table 6.3 spelling set (matchCmpOp); the
    /// compare ACTION is f64 here, deliberately — cmpVals' int-exact /
    /// text-fallback semantics are %EVAL's, not floating-point.
    fn cmpr(self: *FloatParser) f64 {
        const l = self.expr();
        self.ws();
        const m = matchCmpOp(self.s, self.i) orelse return l;
        self.i += m.n;
        const r = self.expr();
        // Missing in a COMPARISON does not propagate: printed pp.91-92 (the
        // COMPFLT macro) pin it as the SMALLEST value — "-.1 is greater than .",
        // "0 is greater than ." — so compare as -inf and yield 1/0, never `.`.
        // `. = .` itself is DOC-SILENT; -inf = -inf holds, matching SAS's
        // missing-equals-missing DATA-step semantics.
        const lm = if (std.math.isNan(l)) -std.math.inf(f64) else l;
        const rm = if (std.math.isNan(r)) -std.math.inf(f64) else r;
        const b = switch (m.c) {
            .eq => lm == rm,
            .ne => lm != rm,
            .lt => lm < rm,
            .le => lm <= rm,
            .gt => lm > rm,
            .ge => lm >= rm,
        };
        return if (b) 1 else 0;
    }
    fn expr(self: *FloatParser) f64 {
        var v = self.term();
        while (true) {
            self.ws();
            if (self.i >= self.s.len) break;
            const c = self.s[self.i];
            if (c == '+') {
                self.i += 1;
                v += self.term();
            } else if (c == '-') {
                self.i += 1;
                v -= self.term();
            } else break;
        }
        return v;
    }
    fn term(self: *FloatParser) f64 {
        var v = self.factor();
        while (true) {
            self.ws();
            if (self.i >= self.s.len) break;
            const c = self.s[self.i];
            if (c == '*') {
                self.i += 1;
                v *= self.factor();
            } else if (c == '/') {
                self.i += 1;
                const d = self.factor();
                // The div-by-zero guard's silent 0 is pre-existing (doc-silent),
                // but it must not EAT a missing: `./0` stays missing like any op.
                v = if (d != 0) v / d else if (std.math.isNan(v)) v else 0;
            } else break;
        }
        return v;
    }
    fn factor(self: *FloatParser) f64 {
        self.ws();
        if (self.i >= self.s.len) return 0;
        const c = self.s[self.i];
        if (c == '-') {
            self.i += 1;
            return -self.factor(); // binds LOOSER than `**`: -2**2 = -(2**2) = -4
        }
        if (c == '+') {
            self.i += 1;
            return self.factor();
        }
        return self.powP();
    }
    /// `**` exponentiation (BUG-macropow — used to parse as `* <garbage>` → 0).
    /// Right-associative; the exponent may itself be signed (2**-1 = 0.5).
    fn powP(self: *FloatParser) f64 {
        var v = self.primary();
        self.ws();
        if (self.i + 1 < self.s.len and self.s[self.i] == '*' and self.s[self.i + 1] == '*') {
            self.i += 2;
            v = std.math.pow(f64, v, self.factor());
        }
        return v;
    }
    fn primary(self: *FloatParser) f64 {
        self.ws();
        if (self.i >= self.s.len) return 0;
        const c = self.s[self.i];
        if (c == '(') {
            self.i += 1;
            const v = self.cmpr(); // parens carry a FULL expression, comparison included (%EVAL parity)
            self.ws();
            if (self.i < self.s.len and self.s[self.i] == ')') self.i += 1;
            return v;
        }
        // A quoted date/time literal, e.g. %sysevalf('15JAN2020'd) — convert to its
        // SAS numeric before the digit scan (BUG-macrodateliteral).
        if (c == '\'' or c == '"') {
            if (std.mem.indexOfScalarPos(u8, self.s, self.i + 1, c)) |close| {
                var j = close + 1;
                while (j < self.s.len and std.ascii.isAlphabetic(self.s[j])) j += 1;
                if (macroDateLiteral(self.s[self.i..j])) |v| {
                    self.i = j;
                    return v;
                }
            }
        }
        const start = self.i;
        while (self.i < self.s.len and (std.ascii.isDigit(self.s[self.i]) or self.s[self.i] == '.')) self.i += 1;
        // scientific notation `e`/`E`[+/-]digits — consumed only when a valid
        // exponent actually follows, so a trailing identifier isn't swallowed
        // (BUG-sysevalfsci: the scan used to stop at `e`, reading 1e10 as 1).
        if (self.i < self.s.len and (self.s[self.i] == 'e' or self.s[self.i] == 'E')) {
            var j = self.i + 1;
            if (j < self.s.len and (self.s[j] == '+' or self.s[j] == '-')) j += 1;
            if (j < self.s.len and std.ascii.isDigit(self.s[j])) {
                while (j < self.s.len and std.ascii.isDigit(self.s[j])) j += 1;
                self.i = j;
            }
        }
        const tok = self.s[start..self.i];
        // A bare `.` is a SAS MISSING value (printed pp.353-354), NOT 0 — carried
        // as NaN so IEEE propagates it through every arithmetic op. `.5`/`1.`
        // still parse as numbers (the token isn't exactly ".").
        if (std.mem.eql(u8, tok, ".")) return std.math.nan(f64);
        return std.fmt.parseFloat(f64, tok) catch 0;
    }
};

/// `%if cond %then A; [%else B;]` — expand the taken branch only.
fn handleIf(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const then_at = findKeyword(src, from, "then") orelse {
        try st.diags.note(0, "%if without %then", .{});
        return from;
    };
    const cond = try evalCond(st, src[from..then_at]);

    var k = skipWs(src, then_at + "%then".len);
    const tb = branchUnit(src, k);
    if (cond) try process(st, src[tb.cs..tb.ce], out);
    k = tb.after;

    const p = skipWs(src, k);
    if (matchKeyword(src, p, "else")) {
        const eb = branchUnit(src, skipWs(src, p + "%else".len));
        if (!cond) try process(st, src[eb.cs..eb.ce], out);
        k = eb.after;
    }
    return k;
}

/// `%do i = start %to stop [%by step]; BODY %end;` — iterate at macro time,
/// expanding BODY once per value with `i` bound. Also handles the block form
/// `%do; BODY %end;` (expand once). `from` is just past `%do`.
fn handleDo(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    var k = skipWs(src, from);

    // block form `%do;` — no iteration variable
    if (k < src.len and src[k] == ';') {
        const body_start = k + 1;
        const end_at = matchingEnd(src, body_start) orelse src.len;
        try process(st, src[body_start..end_at], out);
        return pastEnd(src, end_at);
    }

    // conditional loop: `%do %while(cond);` (test at top) / `%do %until(cond);`
    // (test at bottom, runs at least once). The body must change a macro var the
    // condition reads, else the guard stops it.
    if (matchKeyword(src, k, "while") or matchKeyword(src, k, "until")) {
        const is_until = matchKeyword(src, k, "until");
        const pa = parenArg(src, k + (if (is_until) "%until".len else "%while".len)) orelse {
            try st.diags.note(0, "%do %while/%until without a condition", .{});
            return k;
        };
        var semi = pa.end;
        while (semi < src.len and src[semi] != ';') semi += 1;
        const body_start = if (semi < src.len) semi + 1 else semi;
        const end_at = matchingEnd(src, body_start) orelse src.len;
        const body = src[body_start..end_at];
        var guard: usize = 0;
        // A %goto whose label is NOT in this body leaves the loop NOW, exactly
        // like %return (NOTE-gotodowhilespin): the flag stays set and the outer
        // process() resumes at the label. Without the break %until SPINS to the
        // convergence cap (the goto-suppressed resolveText renders the condition
        // empty/false, so the bottom-test never breaks) — %while only escaped by
        // that same side effect. A label inside the body clears the flag before
        // process() returns, so an in-body jump iterates normally.
        if (is_until) {
            while (guard < max_loop_iters) : (guard += 1) {
                try process(st, body, out);
                if (st.returning) break; // %return: stop the loop AND the macro
                if (st.goto_target != null) break; // %goto out of the loop
                if (try evalCond(st, pa.text)) break;
            }
        } else {
            while (guard < max_loop_iters and try evalCond(st, pa.text)) : (guard += 1) {
                try process(st, body, out);
                if (st.returning) break;
                if (st.goto_target != null) break;
            }
        }
        // Backstop tripped: the condition never falsified. Stop LOUD — a silent
        // cap hides a non-converging loop (BUG-macrodowhilehang). A %goto break
        // leaves guard below the cap, so it can never trip this.
        if (guard >= max_loop_iters and !st.returning)
            try st.diags.macroErr(0, "%do %while/%until did not converge in {d} iterations — stopped", .{max_loop_iters});
        return pastEnd(src, end_at);
    }

    // iterative: `var = start %to stop [%by step] ;` — valid only INSIDE a
    // macro (F11). In open code SAS rejects it, and an open-code iterative %DO
    // is exactly what a MISSING/misspelled %MEND dumps into the stream —
    // accepting it silently swallows the rest of the program with no
    // diagnostic. Error loud and skip the loop. (The block `%do;` /
    // `%do %while` forms under an open-code %if stay accepted — pinned by
    // macro_autovars / macro_runtimescope.)
    // Wording is SAS's exact text (Macro Language Ref, App.2 printed p.500:
    // "Error: The %DO statement is not valid in open code."). The old
    // "iterative … — a missing %MEND?" locator is dropped: exact SAS text
    // outranks the locator (same call as 1a83f0fa's "in %do bound" drop) —
    // the missing-%MEND tell stays documented here (NOTE-gotodoopencode).
    if (st.macro_call_depth == 0) {
        try st.diags.macroErr(0, "The %DO statement is not valid in open code.", .{});
        var semi = k;
        while (semi < src.len and src[semi] != ';') semi += 1;
        const body_start = if (semi < src.len) semi + 1 else semi;
        const end_at = matchingEnd(src, body_start) orelse src.len;
        return pastEnd(src, end_at);
    }
    const ns = k;
    while (k < src.len and isNameChar(src[k])) k += 1;
    const var_name = src[ns..k];
    k = skipWs(src, k);
    if (k >= src.len or src[k] != '=') {
        try st.diags.note(0, "%do without '='", .{});
        return k;
    }
    k += 1; // past '='
    const to_at = findKeyword(src, k, "to") orelse {
        try st.diags.note(0, "%do without %to", .{});
        return k;
    };
    const start_text = src[k..to_at];
    const after_to = to_at + "%to".len;

    // header ends at the next `;`; an optional `%by step` may precede it
    var semi = after_to;
    while (semi < src.len and src[semi] != ';') semi += 1;
    var stop_end = semi;
    var step_text: ?[]const u8 = null;
    if (findKeyword(src, after_to, "by")) |bat| if (bat < semi) {
        stop_end = bat;
        step_text = src[bat + "%by".len .. semi];
    };
    const stop_text = src[after_to..stop_end];

    const body_start = if (semi < src.len) semi + 1 else semi;
    const end_at = matchingEnd(src, body_start) orelse src.len;
    const body = src[body_start..end_at];

    // Resolve the bounds first and reject an UNRESOLVED macro reference loud.
    // resolveText leaves an undefined `&name` verbatim, so a surviving `&<name>`
    // means a bound like `%to &MAXID.` where MAXID was never set; running one
    // silent iteration is the worst class (CLIN-failloud / BUG-macrodounresolved,
    // my obsidtmp5 find).
    const start_r = try resolveText(st, start_text);
    const stop_r = try resolveText(st, stop_text);
    const step_r = if (step_text) |t| try resolveText(st, t) else null;
    if (unresolvedRef(start_r) orelse unresolvedRef(stop_r) orelse
        (if (step_r) |s| unresolvedRef(s) else null)) |name|
    {
        // macroErr, not report: real SAS confines this to "the macro will stop
        // executing" — later independent steps still run (exit stays non-zero).
        // Text is SAS's exact unresolved-reference message (Macro Language Ref,
        // App.2 printed p.531). Real SAS emits it as a WARNING, then errors
        // separately ("Error: The value &X of the %DO I loop is invalid.", App.2
        // printed p.502); we deliberately merge both into this ONE macroErr at
        // the %do (firing point pinned by 5d662c9f) — no opensas-specific
        // "in %do bound" suffix; exact SAS text outranks the locator
        // (NOTE-macroerrwordingfamily).
        st.diags.macroErr(0, "Apparent symbolic reference {s} not resolved.", .{try upperDup(st.a, name)}) catch {};
        return pastEnd(src, end_at);
    }

    const start = try evalResolvedInt(st, start_r);
    const stop = try evalResolvedInt(st, stop_r);
    const step = if (step_r) |s| try evalResolvedInt(st, s) else @as(i64, 1);

    if (step != 0) {
        // BUG-macrodoscope (a): the %do index rides the %let scoping path
        // (BUG-macrobareletscope) — raw setVar leaked a BRAND-NEW index to
        // global. A name an active scope or the flat table already owns
        // updates in place (nearest existing scope, never a shadow); only a
        // brand-new name becomes LOCAL to this macro invocation (SAS 9.4).
        if (st.scopes.items.len > 0 and st.findLocal(var_name) == null and st.getVar(var_name) == null)
            try st.declareLocal(var_name);
        var v = start;
        var jumped = false; // %goto fired: the index keeps its jump-time value
        while (if (step > 0) v <= stop else v >= stop) {
            const top = v; // value the body saw this pass — the advancement reference
            var buf: [24]u8 = undefined;
            try st.setVar(var_name, std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable);
            try process(st, body, out);
            if (st.returning) break; // %return: stop iterating and unwind the macro
            // %goto whose label is NOT in this body leaves the loop NOW — the
            // search-then-report idiom reads &i at the jump, not the terminal
            // value (BUG-dogotoindex). A label inside the body clears the flag
            // before process() returns, so an in-body jump iterates normally.
            if (st.goto_target != null) {
                jumped = true;
                break;
            }
            // GAP-macrodoindex: RE-READ the index from the symbol table. It was a
            // Zig-local counter the body could never influence, so the documented
            // early-exit idiom silently ran the full trip count. Macro Language
            // Reference, printed p.388, `macro-variable`: "You can change the value
            // of the index variable during processing. For example, using
            // conditional processing to set the value of the index variable beyond
            // the stop value when a certain condition is met ends processing of the
            // loop." The SAME page makes the contrast explicit for %BY — "Increment
            // is evaluated before the first iteration of the loop. Therefore, you
            // cannot change it as the loop iterates" — so `step` stays evaluated
            // once above and only the INDEX is re-read.
            // The `ponytail:` corner left here when the re-read landed is now
            // settled by the reference (printed p.509): "Error: The index variable
            // in the %DO value loop has taken on an invalid or missing value. The
            // macro will stop executing." — cause, "The index variable of a macro
            // %DO statement has been set to missing or given a non-numeric" value.
            // So a body that leaves the index non-integer is a LOUD STOP, not the
            // silent fall-back-to-the-internal-counter this used to do.
            if (st.getVar(var_name)) |cur| {
                const t = std.mem.trim(u8, cur, " \t\r\n");
                v = std.fmt.parseInt(i64, t, 10) catch {
                    try st.diags.macroErr(0, "The index variable in the %DO loop has taken on an invalid or missing value: '{s}'", .{t});
                    try stopMacro(st);
                    break;
                };
            }
            v +|= step; // saturating: a %to bound at the i64 ceiling must never wrap
            // QA tick377 F1: NON-ADVANCEMENT guard, replacing the raw trip-count
            // backstop (max_loop_iters) this loop briefly shared with %do %while.
            // The count cut a LEGAL long loop off at 100,000 and returned a wrong
            // value; the reference places NO upper bound on the trip count (the
            // %DO entry's own re-read/early-exit text, printed p.388-389, has
            // none). The re-read above makes advancement observable instead: an
            // index that did not move TOWARD `stop` this pass (unchanged, or moved
            // away) can never reach the bound — trip NOW, on the first stuck pass.
            // An ordinary long loop advances every pass and never trips. Real SAS
            // spins forever here, so stopping is an opensas LIMIT, not a user
            // error — D-009 class 2 (markGap), not 1.
            if ((step > 0 and v <= top) or (step < 0 and v >= top)) {
                try st.diags.macroErr(0, "iterative %DO did not converge — the index is not advancing toward the stop value (does the loop body reset its index?)", .{});
                diag.markGap();
                break;
            }
        }
        // BUG-macrodoscope (b): SAS leaves the index at the FIRST value that
        // failed the bound (start + k*step past stop), not the last in-range
        // value — store the post-increment v. On %return v is the current
        // value and the local scope unwinds anyway, so the store is harmless.
        // On %goto out of the loop the jump-time value (already stored at the
        // top of the firing iteration) must survive — skip the terminal store.
        if (!jumped) {
            var buf: [24]u8 = undefined;
            try st.setVar(var_name, std.fmt.bufPrint(&buf, "{d}", .{v}) catch unreachable);
        }
    }
    return pastEnd(src, end_at);
}

/// Position of the `%end` matching the `%do` whose body starts at `from`
/// (nesting-aware). Null if unbalanced.
fn matchingEnd(src: []const u8, from: usize) ?usize {
    var depth: usize = 1;
    var k = from;
    while (k < src.len) {
        if (matchKeyword(src, k, "do")) {
            depth += 1;
            k += "%do".len;
        } else if (matchKeyword(src, k, "end")) {
            depth -= 1;
            if (depth == 0) return k;
            k += "%end".len;
        } else k += 1;
    }
    return null;
}

/// Index just past `%end;` (the terminating `;` is consumed).
fn pastEnd(src: []const u8, end_at: usize) usize {
    if (end_at >= src.len) return src.len;
    var e = end_at + "%end".len;
    while (e < src.len and src[e] != ';') e += 1;
    return if (e < src.len) e + 1 else e;
}

/// Resolve `&vars` in `text` and evaluate it as a macro integer expression.
fn evalInt(st: *State, text: []const u8) Error!i64 {
    return evalResolvedInt(st, try resolveText(st, text));
}

/// Evaluate an ALREADY-resolved macro integer expression (no further `&`/`%`
/// resolution). Split from evalInt so a %do bound can be resolved once, checked
/// for unresolved references, then evaluated (BUG-macrodounresolved).
fn evalResolvedInt(st: *State, resolved: []const u8) Error!i64 {
    const toks = try tokenizeEval(st.a, resolved, st.minoperator);
    var p = EvalParser{ .toks = toks, .delim = st.mindelimiter };
    const v = p.expr();
    // GAP-macroevalfloat: SAS %EVAL is integer-only. A non-integer/character
    // operand in ARITHMETIC, or a token the grammar leaves unconsumed (an
    // unknown "operator" like `mod` or `foo`), is an ERROR in SAS — the old
    // silent coerce-to-0 / keep-first-operand was the worst failure class.
    // macroErr: loud + non-zero exit, but later independent steps still run.
    try reportEvalParse(st, &p, resolved);
    const s = v.str orelse return v.int;
    return std.fmt.parseInt(i64, s, 10) catch {
        // NOTE-macroevalnonint: a bare non-integer leaf (`%eval(3.5)`) is the
        // SAME invalid %EVAL operand as one reached via arithmetic (p.bad
        // above) — SAS raises the identical ERROR for both. The old lowercase
        // NOTE here made the two paths inconsistent. Still yields 0.
        if (s.len != 0) {
            try st.diags.macroErr(0, "A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '{s}'", .{s});
            try stopMacro(st); // p.162 — same error, same termination
        }
        return 0;
    };
}

/// The name of the first still-unresolved `&name` reference in `text`, or null.
/// resolveText leaves an undefined macro var verbatim as `&name`, so a surviving
/// `&<name-start>` flags it (a fully-resolved numeric expression has no `&`).
fn unresolvedRef(text: []const u8) ?[]const u8 {
    var i: usize = 0;
    while (i + 1 < text.len) : (i += 1) {
        if (text[i] == '&' and isNameStart(text[i + 1])) {
            var e = i + 1;
            while (e < text.len and isNameChar(text[e])) e += 1;
            return text[i + 1 .. e];
        }
    }
    return null;
}

const Branch = struct { cs: usize, ce: usize, after: usize };

/// The extent of one `%then`/`%else` branch: a `%do; … %end;` block, or a
/// single statement up to (and including) its `;`.
fn branchUnit(src: []const u8, start: usize) Branch {
    if (matchKeyword(src, start, "do")) {
        var k = start + "%do".len;
        while (k < src.len and src[k] != ';') k += 1;
        if (k < src.len) k += 1; // past `%do;`
        // matchingEnd tracks nested %do/%end depth so an inner %end doesn't close
        // this branch (BUG-makedateparams: nested `%if %then %do; %if %then %do;
        // … %end; %end;` leaked the outer %end as a stray `%`).
        const end_at = matchingEnd(src, k) orelse src.len;
        var after = end_at;
        if (end_at < src.len) {
            after = end_at + "%end".len;
            while (after < src.len and src[after] != ';') after += 1;
            if (after < src.len) after += 1;
        }
        return .{ .cs = k, .ce = end_at, .after = after };
    }
    // BUG-macroelseifchain: an `%if`-headed branch is itself a full conditional
    // unit — `%if c %then <unit> [%else <unit>]` — not a single statement. Recurse
    // so the else-if idiom (`%else %if … %then …; %else …;`) binds each inner
    // %else to its own %if. The old single-`;` cut truncated the else-branch at
    // the first `;` and orphaned the inner %else into the outer stream, where it
    // ran unconditionally (plus a stray "macro ELSE not resolved" warning).
    if (matchKeyword(src, start, "if")) {
        if (findKeyword(src, start, "then")) |then_at| {
            const tb = branchUnit(src, skipWs(src, then_at + "%then".len));
            var after = tb.after;
            const p = skipWs(src, after);
            if (matchKeyword(src, p, "else"))
                after = branchUnit(src, skipWs(src, p + "%else".len)).after;
            // Whole span is fed back through process(), which re-parses it via
            // handleIf — so the nested %if/%then/%else resolves recursively.
            return .{ .cs = start, .ce = after, .after = after };
        }
    }
    // The `;` delimits the branch, skipping %str/%word(...) spans so a masked ; inside
    // %then %str(a; b) does not truncate the branch (BUG-strsemicolon).
    const k = macroValueEnd(src, start, null);
    const after = if (k < src.len) k + 1 else k;
    return .{ .cs = start, .ce = k, .after = after };
}

// ── condition evaluation ────────────────────────────────────────────────────

const Cmp = enum { eq, ne, lt, le, gt, ge };

/// `%if` / `%do %while` condition: resolve, then run the ONE macro expression
/// evaluator (tokenizeEval + EvalParser — same grammar as %eval) and take the
/// result's truthiness. QL-C unified the parser; BUG-minoperatoropt unified the
/// VERDICT: %if surfaces the same loud parse errors %eval does on the same text.
/// The old last line, `truthy(p.expr())`, dropped every parse error and treated
/// any leftover/non-blank text as TRUE — so an un-gated `in` (`%if q in a b c`,
/// NOMINOPERATOR) was ALWAYS true at exit 0, and a bare `%if abc` was silently
/// TRUE where %eval(abc) errors (BUG-ifbaretruthy). Manager call: fail loud.
fn evalCond(st: *State, text: []const u8) Error!bool {
    const resolved = std.mem.trim(u8, try resolveText(st, text), " \t\r\n");
    const toks = try tokenizeEval(st.a, resolved, st.minoperator);
    var p = EvalParser{ .toks = toks, .delim = st.mindelimiter };
    const v = p.expr();
    try reportEvalParse(st, &p, resolved);
    if (v.str) |s| {
        // Bare leaf: an integer decides by nonzero; an EMPTY leaf (unresolved
        // &ref / empty var — the `%if &flag` guard idiom) stays silently false;
        // anything else is the character-operand ERROR %eval raises on it.
        if (s.len == 0) return false;
        return std.fmt.parseInt(i64, s, 10) catch {
            try st.diags.macroErr(0, "A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '{s}'", .{s});
            try stopMacro(st); // p.162
            return false;
        } != 0;
    }
    return v.int != 0;
}

/// BUG-macroerrnostop: a %EVAL/%IF expression error does not merely report — it
/// STOPS THE ENCLOSING MACRO. Macro Language Reference printed p.162 shows both
/// lines SAS emits for the ambiguous-token case:
///     ERROR: A character operand was found in the %EVAL function or %IF
///            condition where a numeric operand is required. The condition was:…
///     ERROR: The macro will stop executing.
/// We emitted only the first and carried on, so a macro kept running past a
/// condition it could not evaluate and silently took a branch. The second message
/// matters on its own: without it the user is never told the macro stopped.
///
/// Reuses the EXISTING %RETURN/%ABORT machinery (`st.returning`, cleared at the
/// macro-call boundary) rather than a parallel termination path.
/// Open code is deliberately excluded: SAS's sentence is about "the macro", there
/// is no macro to stop, and handlePercent's %RETURN guard documents why setting
/// `returning` at depth 0 is harmful — it would silently drop every following
/// statement at exit 0 (GH#4). At depth 0 the caller's error still stands alone.
fn stopMacro(st: *State) Error!void {
    if (st.macro_call_depth == 0) return; // open code: nothing to unwind (GH#4)
    try st.diags.macroErr(0, "The macro will stop executing.", .{});
    st.returning = true;
}

/// The loud parse-error checks %EVAL and %IF share (BUG-minoperatoropt): a
/// character operand arithmetic tried to coerce, a zero divisor, or a token the
/// grammar left unconsumed (an unknown "operator" like `mod`/`foo`, or an `in`
/// with MINOPERATOR off) are all ERRORs — never a silent 0 / silent branch.
fn reportEvalParse(st: *State, p: *const EvalParser, resolved: []const u8) Error!void {
    if (p.bad) |s| {
        try st.diags.macroErr(0, "A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '{s}'", .{s});
        try stopMacro(st); // p.162, verbatim pair
    } else if (p.divzero) {
        // BUG-macroevaldivzero: SAS raises an ERROR here; the old silent 0 was
        // the worst failure class (DATA step div-by-zero already fails loud).
        // NOT a stopMacro site: the reference's entry for this one (printed p.506,
        // "Error: Division by zero in %EVAL is invalid.") carries only Cause and
        // Solution — no "The macro will stop executing." Unlike its neighbours it
        // is not documented as terminating, so it keeps reporting only.
        try st.diags.macroErr(0, "Division by zero in %EVAL", .{});
    } else if (p.pos < p.toks.len) {
        // p.162's own words for this class: the common expression errors are "the
        // presence of character operands where numeric operands are required OR
        // ambiguity about whether a token is a numeric operator or a character
        // value" — a token the grammar could not consume is that second half.
        try st.diags.macroErr(0, "%EVAL: invalid operator or operand in '{s}'", .{std.mem.trim(u8, try unmaskTriggers(st.a, resolved), " \t\r\n")});
        try stopMacro(st);
    }
}

fn compare(l: []const u8, r: []const u8, cmp: Cmp) bool {
    if (parseNum(l)) |ln| if (parseNum(r)) |rn| return switch (cmp) {
        .eq => ln == rn,
        .ne => ln != rn,
        .lt => ln < rn,
        .le => ln <= rn,
        .gt => ln > rn,
        .ge => ln >= rn,
    };
    const o = std.mem.order(u8, l, r);
    return switch (cmp) {
        .eq => o == .eq,
        .ne => o != .eq,
        .lt => o == .lt,
        .le => o != .gt,
        .gt => o == .gt,
        .ge => o != .lt,
    };
}

fn parseNum(s: []const u8) ?f64 {
    if (s.len == 0) return null;
    return std.fmt.parseFloat(f64, s) catch null;
}

// ── %eval — integer expression evaluation ────────────────────────────────────

/// `%eval(expr)` — resolve `&vars` in `expr`, evaluate it as an integer
/// arithmetic/comparison/logical expression, and emit the result as text.
fn handleEval(st: *State, src: []const u8, from: usize, out: *std.ArrayList(u8)) Error!usize {
    const k = skipWs(src, from);
    if (k >= src.len or src[k] != '(') {
        try st.diags.note(0, "%eval without parentheses", .{});
        return k;
    }
    // balanced parens
    var depth: usize = 1;
    var i = k + 1;
    const cs = i;
    while (i < src.len and depth > 0) : (i += 1) {
        if (src[i] == '(') depth += 1 else if (src[i] == ')') depth -= 1;
        if (depth == 0) break;
    }
    const resolved = try resolveText(st, src[cs..i]);
    try out.print(st.a, "{d}", .{try evalResolvedInt(st, resolved)});
    return if (i < src.len) i + 1 else i; // past ')'
}

const EOp = enum { num, str_, plus, minus, star, slash, pow, lp, rp, lt, le, gt, ge, eq, ne, and_, or_, not_, in_, amb };
const ETok = struct { op: EOp, val: i64 = 0, text: []const u8 = "" };

/// True for any char that continues an operand run: everything that is not
/// whitespace and not one of the operator/grouping chars. Keeps `abc1`, `1.5`,
/// `"quoted"` and 20-digit ids intact as single operands (QL-C — the old
/// tokenizer dropped non-numeric words, so %eval couldn't compare strings).
fn isOperandChar(c: u8) bool {
    return switch (c) {
        ' ', '\t', '\n', '\r', '+', '-', '*', '/', '(', ')', '<', '>', '=', '^', '~', '&', '|' => false,
        else => true,
    };
}

fn tokenizeEval(a: std.mem.Allocator, s: []const u8, minop: bool) Error![]const ETok {
    var out: std.ArrayList(ETok) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        // BUG-macroevalnotsign: `¬` is the two bytes 0xC2 0xAC, and isOperandChar
        // calls every non-ASCII-operator byte an OPERAND char — so the operand scan
        // below swallowed the glyph as a word and the operator switch never saw it.
        // `%if 1 ¬= 2` then lexed as `1` `¬` `=` `2`, whose leftover token made
        // reportEvalParse fire while the leaf `1` still tested truthy: the RIGHT
        // branch and a hard error at once. `¬(1=2)` was plainly WRONG (false).
        // Table 6.3 "Macro Language Operators" (Macro Language Reference printed
        // p.87-88) lists the glyph on BOTH rows it belongs to — `¬^~ NOT` and
        // `¬= ^= ~= NE` — so unlike `<>` (absent, hence loud: NOTE-macroevalops)
        // this one must WORK. Same table, both edges.
        // Maximal munch, matched BEFORE the operand scan, claiming only the exact
        // two-byte NOT SIGN: `¦` (0xC2 0xA6) and `¢` keep their current handling,
        // and `¦` in particular must stay loud — Table 6.3's OR row is `|` alone.
        // The two halves are COUPLED and must not be separated: the operand scan
        // below stops at these bytes, so if this branch stopped consuming them the
        // scan would return an empty word, `i` would never advance, and tokenizeEval
        // would spin forever (mutation-verified: removing this half hangs).
        if (c == 0xC2 and i + 1 < s.len and s[i + 1] == 0xAC) {
            const eqd = i + 2 < s.len and s[i + 2] == '=';
            try out.append(a, .{ .op = if (eqd) .ne else .not_ });
            i += if (eqd) 3 else 2;
            continue;
        }
        if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
            i += 1;
        } else if (isOperandChar(c)) {
            var j = i;
            // …and the operand scan must STOP at the glyph too, or a glued
            // `%eval(1¬=2)` (no blanks — ordinary SAS) swallows 0xC2 0xAC into the
            // operand "1¬" and compares it to 2: silently 0, with no error at all,
            // because the grammar then consumes everything. Same two bytes, same
            // maximal-munch rule, the other side of the scan.
            while (j < s.len and isOperandChar(s[j]) and
                !(s[j] == 0xC2 and j + 1 < s.len and s[j + 1] == 0xAC)) j += 1;
            const w = s[i..j];
            // `in`/`#` are the membership operator only under MINOPERATOR; when
            // off they fall through and stay ordinary text (SAS 9.4 default).
            // ponytail: `#` must be blank-delimited here (`&x # a`); a glued
            // `&x#a` stays one operand — no real clinical macro writes it glued.
            const wop: ?EOp = if (minop and (eqi(w, "in") or std.mem.eql(u8, w, "#"))) .in_ else wordOp(w);
            if (wop) |op| {
                // GAP-macrocharoperanddetect (Macro Ref printed p.162): a BARE
                // mnemonic where an OPERAND belongs is ambiguous — "whether a
                // token is a numeric operator or a character value" — and SAS
                // raises the character-operand ERROR and stops the macro. Mark
                // it .amb: the parser records it in `bad`, so the EXISTING
                // reportEvalParse/stopMacro path emits the verbatim pair naming
                // the word (never a sentinel: a masked word fails wop). The two
                // exemptions match the masked-word checks, not re-decided: a
                // QUOTED mnemonic never gets here (its mask_word prefix fails
                // wop, so %str(and) stays the str_ operand below), and `not` is
                // a prefix-ONLY operator — unambiguous exactly where an operand
                // belongs. Operand position = start, or after any operator/`(`
                // — the previous token is not an operand or `)`.
                const operand_pos = out.items.len == 0 or switch (out.items[out.items.len - 1].op) {
                    .num, .str_, .rp, .amb => false,
                    else => true,
                };
                // …but a mnemonic that is the ONLY token is NOT the ambiguous
                // case: it is the implicit empty-operand compare the scan-loop
                // idiom relies on — `%do %while(&word ne);` collapses to ` ne `
                // when &word runs out (the %QSCAN entry's own Example 2,
                // printed p.343) and "" ne "" is false, no ERROR (the settled
                // QL-C contract). Anything around it — `not eq`, `(and)` — is
                // the ambiguous class again.
                const lone = out.items.len == 0 and std.mem.trim(u8, s[j..], " \t\r\n").len == 0;
                if (op != .not_ and operand_pos and !lone)
                    try out.append(a, .{ .op = .amb, .text = w })
                else
                    try out.append(a, .{ .op = op });
            } else if (std.fmt.parseInt(i64, w, 10)) |n|
                try out.append(a, .{ .op = .num, .val = n })
            else |_| // non-integer operand ("abc", "1.5", 2^63+) → carried as text.
                // Unmask quoting sentinels HERE (BUG-macrogroupamasking): after the
                // wordOp/parseInt checks saw the MASKED form, so a %str-quoted `and`
                // is the operand "and" while a bare `and` above stays the operator,
                // and a masked blank/special inside the run made it ONE operand
                // (NOTE-bquoteblank: `%bquote(&s)` with two embedded blanks).
                try out.append(a, .{ .op = .str_, .text = try unmaskTriggers(a, w) });
            i = j;
        } else switch (c) {
            '+' => {
                try out.append(a, .{ .op = .plus });
                i += 1;
            },
            '-' => {
                try out.append(a, .{ .op = .minus });
                i += 1;
            },
            '*' => {
                // `**` is exponentiation (BUG-macropow); a bare `*` multiplies.
                if (i + 1 < s.len and s[i + 1] == '*') {
                    try out.append(a, .{ .op = .pow });
                    i += 2;
                } else {
                    try out.append(a, .{ .op = .star });
                    i += 1;
                }
            },
            '/' => {
                try out.append(a, .{ .op = .slash });
                i += 1;
            },
            '(' => {
                try out.append(a, .{ .op = .lp });
                i += 1;
            },
            ')' => {
                try out.append(a, .{ .op = .rp });
                i += 1;
            },
            '&' => {
                try out.append(a, .{ .op = .and_ });
                i += 1;
            },
            '|' => {
                try out.append(a, .{ .op = .or_ });
                i += 1;
            },
            '=' => {
                try out.append(a, .{ .op = .eq });
                i += 1;
            },
            '<' => {
                // `<=` → le; bare `<` → lt. There is NO `<>` operator in the macro
                // language: Table 6.3 "Macro Language Operators" (Macro Language
                // Reference, printed p.87-88) enumerates the full precedence ladder
                // 1-8 and spells NE as `¬=` `^=` `~=` / NE — footnote 1 exists purely
                // to list the keyboard variants, so a fourth spelling would be there.
                // `<>` appears nowhere as an operator in the volume; %EVAL's own entry
                // (p.328) names Chapter 6 as "a complete discussion". We used to map it
                // to NE from a since-deleted evalBool's behaviour, not from the doc —
                // a silent superset (D-015): `%if &a <> &b` computed a plausible
                // boolean here where SAS 9.4 errors (NOTE-macroevalops).
                // Lexing `<` and `>` separately is what a tokenizer without the
                // operator does; the stray `>` is then left unconsumed and
                // reportEvalParse raises the existing loud unknown-operator ERROR.
                // NB this is the MACRO surface only — `<>` stays MAX in the DATA step
                // (minmax_operators) and NE in WHERE/SQL (sql_ne_diamond, Language Reference: Concepts p.219).
                const le = i + 1 < s.len and s[i + 1] == '=';
                try out.append(a, .{ .op = if (le) .le else .lt });
                i += if (le) 2 else 1;
            },
            '>' => {
                const ge = i + 1 < s.len and s[i + 1] == '=';
                try out.append(a, .{ .op = if (ge) .ge else .gt });
                i += if (ge) 2 else 1;
            },
            '^', '~' => {
                const eqd = i + 1 < s.len and s[i + 1] == '=';
                try out.append(a, .{ .op = if (eqd) .ne else .not_ });
                i += if (eqd) 2 else 1;
            },
            else => i += 1, // skip anything else
        }
    }
    return out.items;
}

fn wordOp(w: []const u8) ?EOp {
    if (eqi(w, "and")) return .and_;
    if (eqi(w, "or")) return .or_;
    if (eqi(w, "not")) return .not_;
    if (eqi(w, "eq")) return .eq;
    if (eqi(w, "ne")) return .ne;
    if (eqi(w, "lt")) return .lt;
    if (eqi(w, "le")) return .le;
    if (eqi(w, "gt")) return .gt;
    if (eqi(w, "ge")) return .ge;
    return null;
}

/// One comparison operator of Table 6.3 at `s[i]`, the same spelling set
/// %EVAL's tokenizeEval munches: `=` `<` `>` `<=` `>=` `^=` `~=` `\xC2\xAC=`
/// and the word forms EQ/NE/LT/LE/GT/GE (the word scan is alphanumeric, so a
/// glued `ne2` is an operand, never an operator — tokenizeEval agrees). Bare
/// `^`/`~`/`\xC2\xAC` are prefix NOT, not comparisons: null. %SYSEVALF's
/// FloatParser is the caller; tokenizeEval keeps its own switch because it
/// also owns `in`/MINOPERATOR and the int-vs-text token split, which the
/// float grammar deliberately lacks — the SHARE LINE is spellings + the Cmp
/// enum, not the tokenizer and not the compare action.
fn matchCmpOp(s: []const u8, i: usize) ?struct { c: Cmp, n: usize } {
    if (i >= s.len) return null;
    switch (s[i]) {
        '=' => return .{ .c = .eq, .n = 1 },
        '<' => return if (i + 1 < s.len and s[i + 1] == '=') .{ .c = .le, .n = 2 } else .{ .c = .lt, .n = 1 },
        '>' => return if (i + 1 < s.len and s[i + 1] == '=') .{ .c = .ge, .n = 2 } else .{ .c = .gt, .n = 1 },
        '^', '~' => return if (i + 1 < s.len and s[i + 1] == '=') .{ .c = .ne, .n = 2 } else null,
        0xC2 => return if (i + 2 < s.len and s[i + 1] == 0xAC and s[i + 2] == '=') .{ .c = .ne, .n = 3 } else null,
        else => {},
    }
    var j = i;
    while (j < s.len and std.ascii.isAlphanumeric(s[j])) j += 1;
    const op = wordOp(s[i..j]) orelse return null;
    const c: Cmp = switch (op) {
        .eq => .eq,
        .ne => .ne,
        .lt => .lt,
        .le => .le,
        .gt => .gt,
        .ge => .ge,
        else => return null, // and/or/not are logicals, not comparisons
    };
    return .{ .c = c, .n = j - i };
}

/// A macro expression value: an exact integer, or (str != null) the raw operand
/// text a leaf carried ("abc", "1.5", `"quoted"`, or "" for a missing operand).
/// Comparisons on text use `compare` (numeric when both sides parse, else
/// lexical); arithmetic goes through EvalParser.intOf, which RECORDS a
/// non-integer operand (GAP-macroevalfloat) so %eval can error instead of
/// silently coercing it to 0.
const EVal = struct { int: i64 = 0, str: ?[]const u8 = null };

/// Old evalBool leaf truthiness, kept exactly: nonzero number, else non-blank text.
fn truthy(v: EVal) bool {
    const s = v.str orelse return v.int != 0;
    if (parseNum(s)) |n| return n != 0;
    return s.len != 0;
}

/// int/int compares exactly (i64 — floats would round 2^53+); anything textual
/// routes through `compare`, rendering an int side into a stack buffer.
fn cmpVals(l: EVal, r: EVal, c: Cmp) bool {
    if (l.str == null and r.str == null) return switch (c) {
        .eq => l.int == r.int,
        .ne => l.int != r.int,
        .lt => l.int < r.int,
        .le => l.int <= r.int,
        .gt => l.int > r.int,
        .ge => l.int >= r.int,
    };
    var lb: [24]u8 = undefined;
    var rb: [24]u8 = undefined;
    const ls = l.str orelse (std.fmt.bufPrint(&lb, "{d}", .{l.int}) catch unreachable);
    const rs = r.str orelse (std.fmt.bufPrint(&rb, "{d}", .{r.int}) catch unreachable);
    return compare(ls, rs, c);
}

/// Recursive-descent evaluator for %eval AND %if/%do %while (QL-C: one grammar).
/// Precedence (loosest first): OR, AND, one comparison, +/-, *//, unary.
/// Comparisons/logicals yield 0/1; arithmetic is integer-only (`/` truncates;
/// div-by-zero flags `divzero` (loud in %eval, 0 in %if)); `**` exponentiates (saturating); string leaves survive
/// to the comparison level so `abc = abc` and `1.5 lt 2` compare as SAS does.
/// ponytail: no float arithmetic — SAS uses %sysevalf for those;
/// malformed input degrades to 0 rather than erroring.
const EvalParser = struct {
    toks: []const ETok,
    pos: usize = 0,
    /// First non-integer text operand arithmetic tried to coerce (GAP-macroevalfloat).
    /// %eval reports it as an ERROR; %if/%while ignore it (bare text leaves are
    /// legitimate conditions) — same coerce-to-0 value as before either way.
    bad: ?[]const u8 = null,
    /// Set on a zero divisor in `/` (BUG-macroevaldivzero): %eval errors loud;
    /// %if/%while ignore it like `bad` and keep the coerce-to-0 value.
    divzero: bool = false,
    /// MINDELIMITER for the `in`/`#` list (BUG-macroinoperator); blank by default.
    delim: u8 = ' ',

    /// Integer value of an EVal for arithmetic; a non-integer text operand is
    /// remembered in `bad` and degrades to 0 (the caller decides loudness).
    fn intOf(self: *EvalParser, v: EVal) i64 {
        const s = v.str orelse return v.int;
        return std.fmt.parseInt(i64, s, 10) catch {
            if (self.bad == null and s.len > 0) self.bad = s;
            return 0;
        };
    }

    fn peek(self: *EvalParser) ?EOp {
        return if (self.pos < self.toks.len) self.toks[self.pos].op else null;
    }
    fn expr(self: *EvalParser) EVal {
        var l = self.andE();
        while (self.peek() == .or_) {
            self.pos += 1;
            const r = self.andE();
            l = .{ .int = b2i(truthy(l) or truthy(r)) };
        }
        return l;
    }
    fn andE(self: *EvalParser) EVal {
        var l = self.cmp();
        while (self.peek() == .and_) {
            self.pos += 1;
            const r = self.cmp();
            l = .{ .int = b2i(truthy(l) and truthy(r)) };
        }
        return l;
    }
    fn cmp(self: *EvalParser) EVal {
        const l = self.addsub();
        // `l in a b c` (MINOPERATOR): the left operand equals one of the
        // delimiter-split items in the operand run that follows. The list runs
        // until a token the operand grammar can't start (and/or/rp/eof), so
        // `&x in a b and &y` stops the list at `and`. Case-sensitive via cmpVals.
        if (self.peek() == .in_) {
            self.pos += 1;
            var matched = false;
            while (self.peek()) |op| {
                const item: EVal = switch (op) {
                    .num => .{ .int = self.toks[self.pos].val },
                    .str_ => .{ .str = self.toks[self.pos].text },
                    // The same ambiguous-mnemonic ERROR inside an `in` list:
                    // record the word and end the list — `bad` wins in
                    // reportEvalParse over the leftover token.
                    .amb => {
                        if (self.bad == null) self.bad = self.toks[self.pos].text;
                        break;
                    },
                    else => break,
                };
                self.pos += 1;
                // A blank delimiter leaves each whitespace-split token whole; a
                // custom one (MINDELIMITER=',') splits the token's own text.
                if (item.str) |t| {
                    var it = std.mem.splitScalar(u8, t, self.delim);
                    while (it.next()) |piece| {
                        const p = std.mem.trim(u8, piece, " \t");
                        if (p.len != 0 and cmpVals(l, .{ .str = p }, .eq)) matched = true;
                    }
                } else if (cmpVals(l, item, .eq)) matched = true;
            }
            return .{ .int = b2i(matched) };
        }
        const c: Cmp = switch (self.peek() orelse return l) {
            .lt => .lt,
            .le => .le,
            .gt => .gt,
            .ge => .ge,
            .eq => .eq,
            .ne => .ne,
            else => return l,
        };
        self.pos += 1;
        return .{ .int = b2i(cmpVals(l, self.addsub(), c)) };
    }
    fn addsub(self: *EvalParser) EVal {
        var l = self.muldiv();
        while (self.peek()) |op| {
            if (op == .plus) {
                self.pos += 1;
                l = .{ .int = self.intOf(l) +| self.intOf(self.muldiv()) }; // saturating: %eval must never crash on overflow
            } else if (op == .minus) {
                self.pos += 1;
                l = .{ .int = self.intOf(l) -| self.intOf(self.muldiv()) };
            } else break;
        }
        return l;
    }
    fn muldiv(self: *EvalParser) EVal {
        var l = self.unary();
        while (self.peek()) |op| {
            if (op == .star) {
                self.pos += 1;
                l = .{ .int = self.intOf(l) *| self.intOf(self.unary()) }; // saturating
            } else if (op == .slash) {
                self.pos += 1;
                const r = self.intOf(self.unary());
                const n = self.intOf(l);
                // div-by-zero → flagged loud by %eval (BUG-macroevaldivzero),
                // value degrades to 0; MIN / -1 would overflow, so saturate it too.
                if (r == 0) self.divzero = true;
                l = .{ .int = if (r == 0) 0 else if (r == -1) 0 -| n else @divTrunc(n, r) };
            } else break;
        }
        return l;
    }
    fn unary(self: *EvalParser) EVal {
        switch (self.peek() orelse return self.powE()) {
            .minus => {
                self.pos += 1;
                return .{ .int = 0 -| self.intOf(self.unary()) }; // saturating negate (MIN would overflow)
            },
            .plus => {
                self.pos += 1;
                return .{ .int = self.intOf(self.unary()) };
            },
            .not_ => {
                self.pos += 1;
                return .{ .int = b2i(!truthy(self.unary())) };
            },
            else => return self.powE(),
        }
    }
    /// `**` exponentiation: binds tighter than unary minus and is right-
    /// associative, so -2**2 = -(2**2) = -4 and 2**3**2 = 2**9 = 512 (SAS 9.4
    /// %EVAL supports `**`; BUG-macropow — it used to degrade to 0).
    fn powE(self: *EvalParser) EVal {
        const l = self.primary(); // stays .str so string compares still work
        if (self.peek() == .pow) {
            self.pos += 1;
            return .{ .int = ipow(self.intOf(l), self.intOf(self.unary())) };
        }
        return l;
    }
    fn primary(self: *EvalParser) EVal {
        const op = self.peek() orelse return .{ .str = "" };
        if (op == .num) {
            const v = self.toks[self.pos].val;
            self.pos += 1;
            return .{ .int = v };
        }
        if (op == .str_) {
            const t = self.toks[self.pos].text;
            self.pos += 1;
            return .{ .str = t };
        }
        if (op == .amb) {
            // A bare mnemonic sat in operand position (GAP-macrocharoperanddetect)
            // — it IS the character operand the ERROR names (p.162); record the
            // first and carry it as text so the rest of the expression parses.
            const t = self.toks[self.pos].text;
            self.pos += 1;
            if (self.bad == null) self.bad = t;
            return .{ .str = t };
        }
        if (op == .lp) {
            self.pos += 1;
            const v = self.expr();
            if (self.peek() == .rp) self.pos += 1;
            return v;
        }
        // A dangling operator: yield the empty operand WITHOUT consuming, so a
        // bare `ne` (empty %while var) compares "" ne "" → false and terminates.
        return .{ .str = "" };
    }
};

fn b2i(b: bool) i64 {
    return if (b) 1 else 0;
}

/// Integer exponentiation for %eval, saturating like the rest of the evaluator
/// (never panics on overflow). A negative exponent yields a fraction, which
/// %eval truncates toward 0 — except ±1 bases: 1**-n = 1, (-1)**-n = ±1.
fn ipow(b: i64, e_in: i64) i64 {
    if (e_in < 0) {
        if (b == 1) return 1;
        if (b == -1) return if (@rem(e_in, 2) == 0) 1 else -1;
        return 0; // includes 0**-n (SAS: div-by-zero class; %eval degrades to 0)
    }
    var r: i64 = 1;
    var bb = b;
    var e: u64 = @intCast(e_in);
    while (e > 0) : (e >>= 1) {
        if (e & 1 == 1) r = r *| bb;
        bb = bb *| bb;
    }
    return r;
}

// ── helpers ─────────────────────────────────────────────────────────────────

fn resolveText(st: *State, text: []const u8) Error![]const u8 {
    // Pop a pooled scratch instead of orphaning a fresh arena ArrayList per
    // call (PERF-resolvetextscratch). process() below can re-enter resolveText
    // (nested %sysfunc/macro-fn arg resolution), so each frame needs its OWN
    // buffer. Callers persist the returned slice, so the result is duped out
    // and only that exact-size dupe lives on in the arena.
    var tmp: std.ArrayList(u8) = st.scratch_pool.pop() orelse .empty;
    tmp.clearRetainingCapacity();
    // A failed return-to-pool must not fail the call: the scratch just
    // orphans (pre-fix behavior for that one buffer); output is unaffected.
    defer st.scratch_pool.append(st.a, tmp) catch {};
    // Every resolveText caller hands over MACRO statement text (see
    // sq_masks_triggers): single quotes must NOT mask &/% in this scan.
    // Save/restore — an enclosing compiler-bound process() scan owns the
    // true value and needs it back when this resolution returns.
    const saved_mask = st.sq_masks_triggers;
    st.sq_masks_triggers = false;
    defer st.sq_masks_triggers = saved_mask;
    try process(st, text, &tmp);
    return st.a.dupe(u8, tmp.items);
}

fn matchKeyword(src: []const u8, i: usize, word: []const u8) bool {
    if (i >= src.len or src[i] != '%') return false;
    const s = i + 1;
    if (s + word.len > src.len) return false;
    if (!std.ascii.eqlIgnoreCase(src[s .. s + word.len], word)) return false;
    const after = s + word.len;
    return after >= src.len or !isNameChar(src[after]);
}

/// Find the `%mend` that closes the macro whose body starts at `from`, matching
/// nested `%macro`/`%mend` pairs so an inner definition is skipped (BUG-nestedmacro).
fn findBalancedMend(src: []const u8, from: usize) ?usize {
    var i = from;
    var depth: usize = 0;
    while (i < src.len) : (i += 1) {
        if (matchKeyword(src, i, "macro")) {
            depth += 1;
        } else if (matchKeyword(src, i, "mend")) {
            if (depth == 0) return i;
            depth -= 1;
        }
    }
    return null;
}

fn findKeyword(src: []const u8, from: usize, word: []const u8) ?usize {
    var i = from;
    while (i < src.len) : (i += 1) if (matchKeyword(src, i, word)) return i;
    return null;
}

fn skipWs(src: []const u8, i: usize) usize {
    var k = i;
    while (k < src.len and (src[k] == ' ' or src[k] == '\t' or src[k] == '\n' or src[k] == '\r')) k += 1;
    return k;
}

/// Index just past a `/* … */` block comment starting at `at` (must be `/*`);
/// an unterminated comment runs to end-of-source.
fn skipBlockComment(src: []const u8, at: usize) usize {
    var k = at + 2;
    while (k + 1 < src.len) : (k += 1) {
        if (src[k] == '*' and src[k + 1] == '/') return k + 2;
    }
    return src.len;
}

/// Index just past a quoted string starting at `at` (a `'` or `"`); a doubled
/// quote (`''`/`""`) is an embedded quote, matching the lexer. Unterminated →
/// end of source.
fn skipQuoted(src: []const u8, at: usize) usize {
    const q = src[at];
    var k = at + 1;
    while (k < src.len) : (k += 1) {
        if (src[k] == q) {
            if (k + 1 < src.len and src[k + 1] == q) {
                k += 1; // doubled quote → embedded, stay in the string
                continue;
            }
            return k + 1; // lone quote closes the literal
        }
    }
    return src.len;
}

/// Scan one comma-separated macro-call/-function argument starting at `from`,
/// returning the index of its terminating top-level `,`/`)` (or end of source).
/// Nested parens keep the scan going; a `,`/`(`/`)` inside a quoted string or a
/// `/* … */` comment is masked so it can't split an arg or fool keyword detect
/// (ISS-macroargscan: `%q('Other, specify')`, `%u(a=X, /* c */ b=Y)`).
fn scanMacroArg(src: []const u8, from: usize) usize {
    var k = from;
    var depth: usize = 0;
    while (k < src.len and (depth > 0 or (src[k] != ',' and src[k] != ')'))) {
        if (src[k] == '\'' or src[k] == '"') {
            k = skipQuoted(src, k);
        } else if (src[k] == '/' and k + 1 < src.len and src[k + 1] == '*') {
            k = skipBlockComment(src, k);
        } else {
            if (src[k] == '(') depth += 1 else if (src[k] == ')') depth -= 1;
            k += 1;
        }
    }
    return k;
}

/// Skip whitespace AND `/* … */` comments — used only in the macro header, where
/// SAS strips comments before parsing the parameter list (BUG-makedateparams).
fn skipWsc(src: []const u8, i: usize) usize {
    var k = i;
    while (k < src.len) {
        if (src[k] == ' ' or src[k] == '\t' or src[k] == '\n' or src[k] == '\r') {
            k += 1;
        } else if (src[k] == '/' and k + 1 < src.len and src[k + 1] == '*') {
            k = skipBlockComment(src, k);
        } else break;
    }
    return k;
}

/// Remove `/* … */` comments from a macro-param default and trim blanks:
/// `DATEC= /*Entry date (Char)*/` → "".
fn stripBlockComments(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    if (std.mem.indexOf(u8, s, "/*") == null) return std.mem.trim(u8, s, " \t\r\n");
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '/' and i + 1 < s.len and s[i + 1] == '*') {
            i = skipBlockComment(s, i);
        } else {
            try out.append(a, s[i]);
            i += 1;
        }
    }
    return std.mem.trim(u8, out.items, " \t\r\n");
}

fn lowerDup(a: std.mem.Allocator, s: []const u8) Error![]const u8 {
    const out = try a.alloc(u8, s.len);
    for (s, 0..) |c, i| out[i] = std.ascii.toLower(c);
    return out;
}

fn isNameStart(c: u8) bool {
    return std.ascii.isAlphabetic(c) or c == '_';
}
fn isNameChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_';
}
fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

// ── tests ────────────────────────────────────────────────────────────────────

fn expectExpand(src: []const u8, want: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings(want, try expand(a, src, &diags));
}

test "PERF-macroaccum: %let accumulation in a %do loop yields the right value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    // The perf win (O(M²) orphaned arena copies → one reused owned buffer) is by
    // construction; this pins the BEHAVIOR: same final value, both stores.
    const M = 4000;
    var sess = Session.init(a, &diags);
    // %global: post BUG-macrobareletscope a bare %let in a macro is LOCAL, but
    // this test pins the accumulation/buffer-reuse behavior on a var that
    // outlives the macro — declare it global, exactly what SAS needs too.
    const src = try std.fmt.allocPrint(a, "%macro m;\n%global s;\n%let s=;\n%do i=1 %to {d};\n%let s=&s.ab;\n%end;\n%mend;\n%m\n", .{M});
    _ = try sess.expand(src);
    const v = sess.st.getVar("s").?;
    try std.testing.expectEqual(@as(usize, 2 * M), v.len);
    for (0..M) |i| try std.testing.expectEqualStrings("ab", v[i * 2 ..][0..2]);
    // Overwrite with a shorter value reuses the buffer (no orphan, no growth).
    _ = try sess.expand("%let s=z;");
    try std.testing.expectEqualStrings("z", sess.st.getVar("s").?);
}

test "PERF-resolvetextscratch: repeated + nested resolution stays correct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    // The perf win (pooled scratch reused across calls → no per-call orphaned
    // ArrayList; only the final dupe persists) is by construction — the pool
    // assertions below pin that construction. The rest pins BEHAVIOR: same
    // resolved text under repetition, an earlier returned slice survives later
    // calls (callers persist them), and nesting (resolveText → process →
    // %upcase arg → resolveText) doesn't clobber the outer frame's scratch.
    var sess = Session.init(a, &diags);
    _ = try sess.expand("%let x=ab;");
    const first = try resolveText(&sess.st, "&x.cd"); // dot delimiter consumed → "abcd"
    for (0..100) |_| try std.testing.expectEqualStrings("abcd", try resolveText(&sess.st, "&x.cd"));
    try std.testing.expectEqualStrings("abcd", first); // survived 100 scratch reuses
    // Nested: %upcase's arg is itself resolved via resolveText mid-process.
    try std.testing.expectEqualStrings("ABCD", try resolveText(&sess.st, "%upcase(&x.cd)"));
    // Scratch actually flowed through the pool and stays bounded by the
    // nesting depth (≤2 here), not by the call count.
    try std.testing.expect(sess.st.scratch_pool.items.len > 0);
    try std.testing.expect(sess.st.scratch_pool.items.len <= 2);
    // Byte-for-byte via the public path too.
    try expectExpand("%let x=ab;\n%upcase(&x.cd) &x", "\nABCD ab");
}

test "%let and &var (in text and expressions, with trailing dot)" {
    try expectExpand("%let n=5;\nx = &n * 2;", "\nx = 5 * 2;");
    try expectExpand("%let w=World;\nput \"Hi &w\";", "\nput \"Hi World\";");
    try expectExpand("%let p=foo;\n&p.bar", "\nfoobar"); // dot delimiter consumed
}

test "ISS-letquotedsemi: a quoted ; in a %let value is literal, not the terminator" {
    // `%let SEP=";";` — the `;` inside the quotes is part of the value; only the
    // trailing `;` ends the statement. &SEP resolves to the two-quote-plus text.
    try expectExpand("%let SEP=\";\";x=&SEP;", "x=\";\";");
    // single quotes too (the terminator rule is the same — quote BALANCING is
    // quote-kind-blind; what single quotes no longer do is mask &/% in macro
    // statement text, sq_masks_triggers); and a longer value with an interior ;
    try expectExpand("%let a=';';[&a]", "[';']");
    try expectExpand("%let m=\"a;b\";[&m]", "[\"a;b\"]");
    // a doubled quote inside the value is not the close, so the ; after it is still
    // interior text — the whole quoted run is the value.
    try expectExpand("%let d=\"x\"\";y\";[&d]", "[\"x\"\";y\"]");
}

test "LETQUOTE-eof: an unclosed quote in a %let value warns instead of silently swallowing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    // `"oops;` opens a quote that never closes — macroValueEnd scans to EOF and
    // eats the following statement. We can't recover the boundary, but we MUST
    // fail loud rather than silently drop `data x; run;`.
    _ = try expand(a, "%let x=\"oops; data x; run;", &diags);
    try std.testing.expectEqualStrings(
        "WARNING: quote not closed before end of file in %LET value\n",
        try diags.render(),
    );
    // A well-formed quoted value (GH#5 / ISS-letquotedsemi) must NOT warn.
    var clean = diag.Diagnostics.init(a);
    _ = try expand(a, "%let x=\";\";", &clean);
    try std.testing.expectEqualStrings("", try clean.render());
}

test "BUG-letsinglequoteampunresolved: %LET resolves & inside single quotes at STORAGE time" {
    // The settled rule (see `sq_masks_triggers`): a single quote masks &/% in
    // COMPILER-BOUND text only (Macro Language Ref printed p.38, the TITLE
    // example). In a MACRO statement the macro processor resolves triggers
    // inside both quote kinds; masking requires an NR quoting function
    // (printed p.7: "You must use a macro quoting function to mask the special
    // characters" — about assigning a value containing ampersands to a macro
    // variable; Table 7.2 printed p.100, `%name &name`: "%NRSTR, %NRBQUOTE,
    // and %NRQUOTE mask these patterns"; printed p.342: "In addition, %NRSTR
    // also masks the following characters: & %").
    //
    // %LET therefore resolves at ASSIGNMENT time and stores the RESOLVED text
    // (the %LET entry's own examples resolve the RHS "before assignment",
    // printed p.403-404). We stored the raw text and resolved at reference
    // time — invisible to `&q` (it renders right either way, which is why QA
    // F2 survived) but wrong three ways: SYMGET handed a DATA step the literal
    // 'AT&t' at rc 0 (silent wrong value crossing into stored data), %SUPERQ
    // read the unresolved text, and a later `%let t=…` retroactively changed
    // `&q` — late binding SAS never does. The double-quoted form was already
    // correct; arm one pins both quote kinds to the SAME snapshot semantics.
    try expectExpand(
        "%let t=RESOLVED;%let q='AT&t';[&q][%superq(q)]%let t=CHANGED;[&q]",
        "['ATRESOLVED']['ATRESOLVED']['ATRESOLVED']",
    );
    // Double quotes: unchanged — already storage-time, same result.
    try expectExpand(
        "%let t=RESOLVED;%let q=\"AT&t\";[&q][%superq(q)]%let t=CHANGED;[&q]",
        "[\"ATRESOLVED\"][\"ATRESOLVED\"][\"ATRESOLVED\"]",
    );
    // Masking still works — through %NRSTR, the doc's route, not the quotes.
    try expectExpand("%let t=RESOLVED;%let q=%nrstr('AT&t');[&q]", "['AT&t']");
    // A quoted nested %LET is a LIVE nested %LET under the same rule (quotes
    // don't mask `%` either): the nestedLet guard must see through them.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = diag.Diagnostics.init(arena.allocator());
    _ = try expand(arena.allocator(), "%let q='%let';", &diags);
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try diags.render(), "not valid inside a %LET value") != null);
}

test "%macro / %mend and %name(args) invocation" {
    try expectExpand("%macro g(w);[&w]%mend;%g(A)%g(B)", "[A][B]");
}

test "BUG-macrounclosedparen: a quoting-fn arg unclosed at EOF fails loud, never swallows the rest" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `%nrstr(a%)` — the `%)` is an ESCAPED ')', so the nrstr paren never closes
    // and the scan runs to EOF. It used to silently return the swallowed remainder
    // (assignment + `data after` dropped, exit 0). Now it errors loud like the
    // %GOTO open-code / %LET quote-eof guards.
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let x = %nrstr(a%); data after; y=1; run;", &d1);
    try std.testing.expectEqualStrings("ERROR: unclosed %NRSTR( argument — ')' not found before end of file\n", try d1.render());
    try std.testing.expect(d1.hasErrors());

    // A bare trailing quoting call with no close also fails loud.
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%str(hello", &d2);
    try std.testing.expectEqualStrings("ERROR: unclosed %STR( argument — ')' not found before end of file\n", try d2.render());

    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%superq(x", &d3);
    try std.testing.expectEqualStrings("ERROR: unclosed %SUPERQ( argument — ')' not found before end of file\n", try d3.render());

    // PRESERVE: properly-closed calls are unchanged and never warn/error.
    try expectExpand("%let x=%str(hello);&x", "hello");
    try expectExpand("%nrstr(a%)b)", "a)b"); // %) escaped inside a call that DOES close
    try expectExpand("%bquote((x))", "(x)"); // balanced nested parens
    var clean = diag.Diagnostics.init(a);
    _ = try expand(a, "%let x=%str(hello);", &clean);
    try std.testing.expectEqualStrings("", try clean.render());
}

test "BUG-macrogotoopen: %GOTO in open code fails loud and does NOT drop later statements" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Open-code `%goto` used to set the unwind target unconditionally: process()
    // then dropped everything after it, exit 0, no diagnostic. Now it errors and
    // the following text still expands.
    var diags = diag.Diagnostics.init(a);
    const out = try expand(a, "before %goto skip; after", &diags);
    try std.testing.expectEqualStrings("before  after", out);
    try std.testing.expectEqualStrings("ERROR: The %GOTO statement is not valid in open code.\n", try diags.render());
    try std.testing.expect(diags.hasErrors());

    // `%goto` INSIDE a macro is normal control flow — unchanged, no error.
    var clean = diag.Diagnostics.init(a);
    const ok = try expand(a, "%macro m;a%goto skip;b%skip:c%mend;%m", &clean);
    try std.testing.expectEqualStrings("ac", ok);
    try std.testing.expectEqualStrings("", try clean.render());
}

test "F11 definition diagnostics: duplicate param / %mend name mismatch / open-code iterative %do fail loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 1. Duplicate parameter name (was silently accepted, last one winning).
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro dup(a,a);[&a]%mend;%dup(1,2)", &d1);
    try std.testing.expectEqualStrings("ERROR: Duplicate parameter A found in macro DUP parameter list\n", try d1.render());

    // 2. %mend name mismatch (was silent). A MATCHING name and a blank %mend
    // stay clean.
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro mm(x);[&x]%mend nn;", &d2);
    try std.testing.expectEqualStrings("ERROR: The %MEND name (NN) does not match the %MACRO name (MM)\n", try d2.render());
    var c2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro mm(x);[&x]%mend mm;%mm(5)%macro n;[n]%mend;", &c2);
    try std.testing.expectEqualStrings("", try c2.render());

    // 3. Iterative %do in OPEN CODE errors and is skipped — the missing-%MEND
    // tell (a macro that forgot %mend used to dump its body into open code and
    // RUN it silently). The block `%do;` under an open-code %if stays legal.
    var d3 = diag.Diagnostics.init(a);
    const o3 = try expand(a, "%do i=1 %to 2;X&i;%end;after", &d3);
    try std.testing.expectEqualStrings("after", o3);
    try std.testing.expectEqualStrings("ERROR: The %DO statement is not valid in open code.\n", try d3.render());
    var c3 = diag.Diagnostics.init(a);
    const oc3 = try expand(a, "%if 1 %then %do;yes%end;", &c3);
    try std.testing.expectEqualStrings("yes", oc3);
    try std.testing.expectEqualStrings("", try c3.render());
}

test "BUG-dogotoindex: %goto out of an iterative %do leaves the index at the jump value" {
    // The search-then-report idiom: was I=6 (terminal), SAS keeps I=3.
    try expectExpand("%macro l;%do i=1 %to 5;%if &i = 3 %then %goto found;%end;NONE%return;%found:AT&i;%mend;%l", "AT3;");
    // Loop running to completion still leaves the index at the first value
    // past the bound (BUG-macrodoscope (b)) — unchanged.
    try expectExpand("%macro l;%do i=1 %to 3;%end;DONE&i;%mend;%l", "DONE4;");
}

test "NOTE-gotodowhilespin: %goto out of %do %while/%until leaves the loop, never spins to the cap" {
    // %until SPUN to the 100k convergence cap and errored: the goto-suppressed
    // resolveText renders the condition empty/false, so the bottom-test never
    // breaks. Now the goto breaks the loop like %return does.
    try expectExpand("%macro l;%let i=0;%do %until (&i>100);%let i=%eval(&i+1);%if &i = 3 %then %goto found;%end;NONE%return;%found:AT&i;%mend;%l", "AT3;");
    // %while escaped only via that same side effect; the explicit break keeps it.
    try expectExpand("%macro l;%let i=0;%do %while (1);%let i=%eval(&i+1);%if &i = 3 %then %goto found;%end;NONE%return;%found:AT&i;%mend;%l", "AT3;");
    // PRESERVE: a label INSIDE the body clears the flag mid-process(), so an
    // in-body jump iterates normally (i=1:XY, i=2:Y, i=3:XY, then 3>2 stops).
    try expectExpand("%macro l;%let i=0;%do %until (&i>2);%let i=%eval(&i+1);%if &i = 2 %then %goto skip;X%skip:Y%end;DONE&i;%mend;%l", "XYYXYDONE3;");
}

test "BUG-macrogotoopen: surplus positional and undeclared keyword args fail loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // F2: more positional args than declared params → error (was silently dropped).
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m(x,y);[&x|&y]%mend;%m(1,2,3,4)", &d1);
    try std.testing.expectEqualStrings("ERROR: More positional parameters found than defined for the macro M\n", try d1.render());

    // F3: `name=value` whose name is not a declared keyword param → error (was
    // rebound as a positional value, x="zzz=99").
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m(x,y);[&x|&y]%mend;%m(zzz=99)", &d2);
    try std.testing.expectEqualStrings("ERROR: The keyword parameter ZZZ was not defined for the macro M\n", try d2.render());

    // PRESERVE: correctly-declared keyword args still bind by name; too-few
    // positional args are fine (missing default to blank); no error either way.
    var clean = diag.Diagnostics.init(a);
    const ok = try expand(a, "%macro m(x,k=def);[&x|&k]%mend;%m(1,k=2)%m(1)", &clean);
    try std.testing.expectEqualStrings("[1|2][1|def]", ok);
    try std.testing.expectEqualStrings("", try clean.render());
}

test "NOTE-macroloudlabels: %ABORT fails loud AND halts (drops later text)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Was: WARNING "apparent invocation of macro ABORT not resolved" + CONTINUE.
    // Now: loud ERROR and a hard halt — text after the %abort never expands, so a
    // later DATA step never reaches the lexer/exec.
    var d = diag.Diagnostics.init(a);
    const out = try expand(a, "%macro m;%abort;%mend;before %m after-abort", &d);
    try std.testing.expectEqualStrings("before ", out);
    try std.testing.expectEqualStrings("ERROR: %ABORT is not supported — halting execution\n", try d.render());
    try std.testing.expect(d.hasErrors());
}

test "NOTE-macroloudlabels: %SYSEXEC/%WINDOW/%DISPLAY fail loud with the statement name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Each was mislabeled "apparent invocation of macro X not resolved"; now each
    // names the unsupported statement and drops it to its `;` (execution continues).
    var d1 = diag.Diagnostics.init(a);
    const o1 = try expand(a, "%sysexec ls -la;KEEP", &d1);
    try std.testing.expectEqualStrings("KEEP", o1);
    try std.testing.expectEqualStrings("ERROR: %SYSEXEC is not a supported macro statement\n", try d1.render());

    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%window w color=red;", &d2);
    try std.testing.expectEqualStrings("ERROR: %WINDOW is not a supported macro statement\n", try d2.render());

    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%display w;", &d3);
    try std.testing.expectEqualStrings("ERROR: %DISPLAY is not a supported macro statement\n", try d3.render());
}

test "NOTE-macroloudlabels: missing %include is a loud ERROR, not a NOTE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const out = try expand(a, "%include \"/no/such/file_opensas_xyz.sas\";AFTER", &d);
    try std.testing.expectEqualStrings("AFTER", out);
    try std.testing.expectEqualStrings("ERROR: %include: cannot open file \"/no/such/file_opensas_xyz.sas\"\n", try d.render());
    try std.testing.expect(d.hasErrors());
}

test "NOTE-macroloudlabels: /parmbuff populates &SYSPBUFF with the raw arg list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Was: /parmbuff swallowed, &syspbuff never set (unresolved-ref warning).
    // Now: &syspbuff = the raw call arg list, parens included, local to the call.
    var d = diag.Diagnostics.init(a);
    const out = try expand(a, "%macro m() / parmbuff;GOT:&syspbuff:%mend;%m(a,b,c)", &d);
    try std.testing.expectEqualStrings("GOT:(a,b,c):", out);
    try std.testing.expectEqualStrings("", try d.render());
}

test "BUG-parmbuffkeyword: /parmbuff with NO parameter list never validates keyword-looking args" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Was: ERROR "The keyword parameter A was not defined" + exit 1 on a VALID
    // program. No parameter list => nothing to validate; &syspbuff takes it all.
    var d = diag.Diagnostics.init(a);
    const out = try expand(a, "%macro pb / parmbuff;[&syspbuff];%mend;%pb(1,2,a=3)AFTER", &d);
    try std.testing.expectEqualStrings("[(1,2,a=3)];AFTER", out);
    try std.testing.expectEqualStrings("", try d.render());
    // A macro WITH a parameter list + parmbuff still validates.
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro pb2(x) / parmbuff;%mend;%pb2(a=3)", &d2);
    try std.testing.expectEqualStrings(
        "ERROR: The keyword parameter A was not defined for the macro PB2\n",
        try d2.render(),
    );
}

test "BUG-undefmacro: unresolved %FOO(args) warns + drops instead of LexError" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    // The undefined call is swallowed (parens balanced) so no stray `%` reaches
    // the lexer; a defined macro next to it still runs.
    const out = try expand(a, "%macro ok;Z%mend;a %MAKE_SHELL(dm, keep=x) %ok b", &diags);
    try std.testing.expectEqualStrings("a  Zb", out);
    try std.testing.expectEqualStrings(
        "WARNING: Apparent invocation of macro MAKE_SHELL not resolved.\n",
        try diags.render(),
    );
}

test "MACRO-autocall: unresolved %m(args) loads <name>.sas from SASAUTOS, case-insensitive" {
    setAutocallDir("tests/autocall");
    defer setAutocallDir(null);
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    // greet.sas (exact case) and SHOUT.sas (macro `shout` in file `SHOUT`) both
    // resolve via autocall with no %include; an unknown name still warn-skips.
    const out = try expand(a, "%greet(World) %shout(hi) %NOPE(x)", &diags);
    try std.testing.expectEqualStrings(
        "data _null_;put \"Hello World\";run; data _null_;put \"[HI]\";run; ",
        out,
    );
    try std.testing.expectEqualStrings(
        "WARNING: Apparent invocation of macro NOPE not resolved.\n",
        try diags.render(),
    );
}

test "BUG-sysfuncformat(a): unsupported %sysfunc format warns + falls back to raw, never fatal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Unsupported named format → raw value, a clean WARNING, and NO fatal flag.
    var d1 = diag.Diagnostics.init(a);
    // Use a genuinely unknown format name (yymmddn. is now implemented in format.zig).
    const out = try expand(a, "%sysfunc(int(24293.7), notarealfmt.)", &d1);
    try std.testing.expectEqualStrings("24293", out);
    try std.testing.expect(!format.formatErrored()); // suppressed → run not killed
    try std.testing.expectEqualStrings(
        "WARNING: %sysfunc: format notarealfmt. not supported — using unformatted value\n",
        try d1.render(),
    );
    // A supported format still applies and does NOT warn.
    var d2 = diag.Diagnostics.init(a);
    const out2 = try expand(a, "%sysfunc(int(24293.7), comma8.)", &d2);
    try std.testing.expectEqualStrings("  24,293", out2); // comma8. right-justifies to width 8
    try std.testing.expectEqualStrings("", try d2.render());

    // BUG-sysfuncnofmterrclobber — the suppression above BORROWS the same global
    // that `OPTIONS NOFMTERR;` sets, so it must hand it back exactly as found. It
    // used to restore the constant `false`, silently switching a user's NOFMTERR
    // back ON; the end-to-end consequence (a later step's genuine "format not
    // found" reported, rc 1) is pinned by tests/corpus/macro_sysfunc_nofmterr.sas.
    // This is the mechanism half: BOTH prior values must survive, and the state is
    // left as it was found so no later test inherits it.
    const saved = format.nofmterr();
    defer format.setNoFmtErr(saved);
    for ([_]bool{ true, false }) |prior| {
        format.setNoFmtErr(prior);
        var d3 = diag.Diagnostics.init(a);
        _ = try expand(a, "%sysfunc(int(24293.7), notarealfmt.)", &d3); // unsupported: takes the guard
        try std.testing.expectEqual(prior, format.nofmterr());
        var d4 = diag.Diagnostics.init(a);
        _ = try expand(a, "%sysfunc(int(24293.7), comma8.)", &d4); // supported: same guard, same rule
        try std.testing.expectEqual(prior, format.nofmterr());
    }
}

test "BUG-makeemptyhang: %global/%local resolve &var in the name list, no spin" {
    // `%global &dataset.KEEPSTRING;` names the var via a &ref — the old char loop
    // stalled on the unresolved `&` (infinite loop). It now resolves to DMKEEPSTRING
    // and declares it; the reference then expands to its (empty) value.
    try expectExpand(
        "%macro m(dataset=);%global &dataset.KEEPSTRING;X[&DMKEEPSTRING]%mend;%m(dataset=DM)",
        "X[]",
    );
    // Plain and comma-separated name lists still work.
    try expectExpand("%global a b,c;%let a=1;%let b=2;%let c=3;&a&b&c", "123");
}

test "G-ebnf-sweep: macro header /options chain — honoured, inert, loud (GAP-macroopts)" {
    // The `/ options` between the param list and `;` must not leak into the body.
    // HONOURED options define and run the macro; the NO- forms are the defaults.
    try expectExpand("%macro m(a) / parmbuff minoperator mindelimiter=',';B&a.E%mend;%m(hi)", "BhiE");
    try expectExpand("%macro q / noparmbuff nominoperator nosecure;Z%mend;%q", "Z");
    // STORE/SECURE/DES=/CMD/STMT and any unknown word ERROR, naming the option,
    // and leave the macro UNDEFINED (D-002: they were silently accepted before —
    // the invocation then warns "apparent invocation … not resolved", like SAS
    // after a failed compile). Captured diagnostics, never a real abort (D-003).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d1 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("", try expand(a, "%macro m(a) / store des=\"x\";B&a.E%mend;%m(hi)", &d1));
    try std.testing.expectEqualStrings("ERROR: The %MACRO option STORE is not supported (opensas keeps macros for the session only — no stored-macro catalog)\n" ++
        "WARNING: Apparent invocation of macro M not resolved.\n", try d1.render());
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro n / stmt;Z%mend;%n", &d2);
    try std.testing.expectEqualStrings("ERROR: The %MACRO option STMT is not supported (command-/statement-style invocation; opensas invokes macros via %name only)\n" ++
        "WARNING: Apparent invocation of macro N not resolved.\n", try d2.render());
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro o / bogusword;Y%mend;%o", &d3);
    try std.testing.expectEqualStrings("ERROR: Unrecognized %MACRO option BOGUSWORD\n" ++
        "WARNING: Apparent invocation of macro O not resolved.\n", try d3.render());
}

test "GAP-ebnfrcwrongclass: documented-but-unimplemented %MACRO options exit 2; a typo stays 1" {
    // D-009: an opensas gap is rc 2 ("file an opensas issue"), the user's own
    // error rc 1 ("fix your SAS"). The %MACRO statement's documented option
    // list — Macro Reference printed pp.408-411 (pdf 423-426, offset +15,
    // confirmed against the printed footers) — re-derived IN FULL (D-018):
    // CMD, DES=, MINDELIMITER=, MINOPERATOR/NOMINOPERATOR, PARMBUFF,
    // SECURE/NOSECURE, STMT, SOURCE/SRC, STORE. Every documented-but-
    // unimplemented one is a gap (the re-derivation is how SOURCE/SRC joined
    // STORE/SECURE/DES=/CMD/STMT — the catch-all had called SOURCE
    // "Unrecognized" at rc 1, both wrong). The catch-all stays rc 1 so a
    // genuine typo (STROE) still says "fix your SAS". Captured reporter,
    // nothing spawned (D-003); the two signals main.zig reads, as in diag.zig's
    // own D-009 test.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const gap_opts = [_][]const u8{ "store", "secure", "des", "cmd", "stmt", "source", "src" };
    for (gap_opts) |opt| {
        diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const src = try std.fmt.allocPrint(a, "%macro m / {s};Z%mend;", .{opt});
        _ = try expand(a, src, &d);
        try std.testing.expect(d.hasErrors()); // the loud ERROR stands
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // Typo control: STROE is in no documented list → the user's own SAS, rc 1.
    diag.resetGap();
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m / stroe;Z%mend;", &d1);
    try std.testing.expect(d1.hasErrors());
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d1.hasErrors()));
    // Honoured-option control: clean define+run, rc 0 (the gap flag must not
    // leak across cases — resetGap each time, per diag.zig's test pattern).
    diag.resetGap();
    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("Z", try expand(a, "%macro m / parmbuff;Z%mend;%m", &d2));
    try std.testing.expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d2.hasErrors()));
    diag.resetGap();
}

test "BUG-barepct: %* macro comment skipped; bare %name invokes; undefined bare passes through" {
    // %* … ; macro comment (incl. the `%**` form) emits nothing — the % must not
    // leak to the lexer. Text after the ';' is kept.
    try expectExpand("A%* a comment with %if and &x ;B", "AB");
    try expectExpand("X%** MBO001 note ** ;Y", "XY");
    // A bare %name (no parens) invokes a DEFINED macro with empty/default args.
    try expectExpand("%macro g;GG%mend;a%g;b", "aGG;b");
    try expectExpand("%macro k(x=Z);[&x]%mend;%k;", "[Z];");
    // An UNDEFINED bare %word warns + DROPS (BUG-barepctundef) — the % must never
    // reach the lexer. (Was pass-through; that leaked in the full pipeline.)
    try expectExpand("pre %nope post", "pre  post");
    // An apostrophe inside a "double-quoted" string is a literal char, NOT a
    // single-quote delimiter — it must not desync the scanner and leak a later
    // %if to the lexer (a real log-scanning macro tripped this).
    try expectExpand(
        "%macro t;if find(x,\"l'a\",'i');%if 1 %then Y;%mend;%t",
        "if find(x,\"l'a\",'i');Y",
    );
    // &var still resolves inside double quotes; ' stays literal there.
    try expectExpand("%let f=AE;a=\"log &f. it's\";", "a=\"log AE it's\";");
}

test "BUG-makedateparams: param defaults ignore /* */ comments (incl. inner parens)" {
    // A `)` inside a default's comment must not truncate the param list — this
    // corrupted a real date macro (every `DATEC= /*…(Char)*/` param) → misfiring checks.
    try expectExpand("%macro m(a= /*Entry (Char)*/, b= /*x*/);[&a][&b]%mend;%m(a=1,b=2)", "[1][2]");
    try expectExpand("%macro m(a= /*d (Char)*/, b=);[&a][&b]%mend;%m()", "[][]");
}

test "BUG-makedateparams: nested %if/%do balances %end; %goto label early-return; &&&" {
    // inner %end must not close the outer %do (branchUnit now uses matchingEnd).
    try expectExpand("%macro t;A%if 1=1 %then %do;B%if 1=1 %then %do;C%end;D%end;E%mend;%t", "ABCDE");
    // %goto LABEL skips to %LABEL:; the label itself is consumed on fall-through.
    try expectExpand("%macro t(e=0);%if &e=1 %then %goto x;GOOD%x:%mend;[%t(e=0)][%t(e=1)]", "[GOOD][]");
    // triple-ampersand indirection: &&&opt → &<value-of-opt> → its value.
    try expectExpand("%let opt=DATEC;%let DATEC=hi;[&&&opt]", "[hi]");
}

test "GAP-macrogotocomputed: a computed %GOTO destination resolves before the branch" {
    // printed p.396: label "is either the name of the label … or a text expression
    // that generates the label … called a computed %GOTO destination"; `%goto
    // &home;` is the doc's own example. The corpus fixture
    // (macro_gotocomputed) pins the BRANCHING through DATA-step `put`, i.e.
    // stdout; the doc-named ERROR TEXTS below only ever reach stderr, which the
    // corpus does not diff, so they are asserted here on the captured reporter.

    // `&var` and a macro CALL both generate the destination (the footnote's
    // "contains % or &"); the literal form is the control and is unchanged.
    try expectExpand("%macro t;%let h=x;%goto &h;SKIPPED%x:HIT%mend;[%t]", "[HIT]");
    try expectExpand("%macro l;x%mend;%macro t;%goto %l;SKIPPED%x:HIT%mend;[%t]", "[HIT]");
    try expectExpand("%macro t;%goto x;SKIPPED%x:HIT%mend;[%t]", "[HIT]");
    // Assembled from two references, so the branch is genuinely chosen at run time.
    try expectExpand("%macro t(n);%let s=leg;%goto &s.&n;%leg1:ONE%goto z;%leg2:TWO%z:%mend;[%t(1)][%t(2)]", "[ONE][TWO]");

    const E = struct {
        fn check(src: []const u8, want_out: []const u8, want_log: []const u8) !void {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var d = diag.Diagnostics.init(a);
            try std.testing.expectEqualStrings(want_out, try expand(a, src, &d));
            try std.testing.expectEqualStrings(want_log, try d.render());
        }
    };
    // NULL destination (printed p.500): "Error: The %GOTO statement has no target.
    // The statement will be ignored." IGNORED is the load-bearing word — the body
    // after it SURVIVES ("BODY" is emitted). Before the fix an unreadable operand
    // set an EMPTY target, which process() can never match, so the rest of the
    // body was deleted and the run still exited 0.
    try E.check(
        "%macro t;%local h;%goto &h;BODY%mend;[%t]",
        "[BODY]",
        "ERROR: The %GOTO statement has no target. The statement will be ignored\n",
    );
    // Resolves to a non-name (printed p.501's own `%goto a-1;`): same
    // ignore-and-report, and the message names BOTH the operand and what it
    // resolved into, per the doc's "the target of the statement %GOTO value,
    // resolved into the label value".
    try E.check(
        "%macro t;%let h=a-1;%goto &h;BODY%mend;[%t]",
        "[BODY]",
        "ERROR: The target of the statement %GOTO &h resolved into the label a-1, " ++
            "which is not a valid statement label\n",
    );
    // A resolved-but-absent label is not diagnosable at the %GOTO (the label may
    // still appear later in the body), so handleCall reports it at the macro
    // boundary — and now prints the RESOLVED text. It used to print nothing at
    // all there ("%goto label : not found"), naming the wrong thing.
    try E.check(
        "%macro t;%let h=nowhere;%goto &h;BODY%mend;[%t]",
        "[]",
        "WARNING: %goto label nowhere: not found in macro t\n",
    );
    // Open code stays invalid, and is still rejected BEFORE the operand resolves.
    try E.check("%goto &h;TAIL", "TAIL", "ERROR: The %GOTO statement is not valid in open code.\n");
}

test "BUG-nestedmacro: nested %macro def compiles; inner is callable once outer runs" {
    // Outer body holds a nested def; before the fix findKeyword paired the outer
    // %macro with the inner %mend → the tail leaked to the lexer as a stray %.
    // Inner is defined when the outer executes, then invoked inside the outer.
    try expectExpand("%macro o;%macro i;[in]%mend i;[pre]%i[post]%mend o;%o", "[pre][in][post]");
    // A nested def alone must not leak / error; sibling defs still work.
    try expectExpand("%macro a;%macro b;B%mend b;%mend a;A%a", "A");
    // Two levels of nesting.
    try expectExpand("%macro o;%macro m;%macro i;X%mend i;%i%mend m;%m%mend o;%o", "X");
}

test "comments and single quotes mask macro triggers (BUG-macrocomment)" {
    // /* ... */ comment text passes through untouched, even %calls and &vars
    try expectExpand("%let x=1;/* %let x=9; &x */z=&x;", "/* %let x=9; &x */z=1;");
    try expectExpand("/* no close &y %let", "/* no close &y %let"); // unterminated: verbatim
    // single-quoted strings mask &/% ; double-quoted still expand
    try expectExpand("%let x=1;'&x' \"&x\"", "'&x' \"1\"");
    try expectExpand("%let x=1;'it''s &x here'", "'it''s &x here'"); // '' embedded quote
}

test "%do iteration: to, by (negative), block form, and inside a macro" {
    // Iterative %do is macro-only (F11) — these run inside a macro; the block
    // form stays legal in open code (macro_autovars idiom).
    try expectExpand("%macro m;%do i=1 %to 3;[&i]%end;%mend;%m", "[1][2][3]");
    try expectExpand("%macro m;%do i=10 %to 6 %by -2;[&i]%end;%mend;%m", "[10][8][6]");
    try expectExpand("%do;AB%end;", "AB"); // block form, expand once
    try expectExpand("%macro m;%do i=1 %to 0;X%end;Y%mend;%m", "Y"); // empty range → no body
    // bound is an expression / resolved var, evaluated at call time
    try expectExpand("%macro c(n);%do i=1 %to &n;(&i)%end;%mend;%c(2)", "(1)(2)");
}

test "%do with an unresolved bound fails loud, no silent iteration (BUG-macrodounresolved)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `%to &MAXID.` where MAXID was never set: real SAS errors "apparent symbolic
    // reference not resolved". We must NOT run the body once (the obsidtmp5
    // MAXID-unset path silently produced a stray row/iteration).
    var d1 = diag.Diagnostics.init(a);
    const out = try expand(a, "%macro m;%do i=1 %to &MAXID;[&i]%end;X%mend;%m", &d1);
    try std.testing.expect(d1.hasErrors()); // captured diagnostic (D-003)
    try std.testing.expect(std.mem.indexOf(u8, out, "[1]") == null); // body never ran
    try std.testing.expect(std.mem.indexOf(u8, out, "X") != null); // control flows past %end
    // exact SAS wording (NOTE-macroerrwordingfamily): stderr-only, so no fixture
    // can pin it — a corpus .txt would pass vacuously.
    try std.testing.expectEqualStrings("ERROR: Apparent symbolic reference MAXID not resolved.\n", try d1.render());

    // an unresolved START bound is caught too (lowercase source: SAS uppercases
    // the name in the message, like every other emit of this text)
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m;%do i=&lo %to 3;[&i]%end;%mend;%m", &d2);
    try std.testing.expect(d2.hasErrors());
    try std.testing.expectEqualStrings("ERROR: Apparent symbolic reference LO not resolved.\n", try d2.render());

    // control: a defined bound (even 0) does NOT error — only unresolved does
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m;%let z=0;%do i=1 %to &z;[&i]%end;%mend;%m", &d3);
    try std.testing.expect(!d3.hasErrors());
}

test "ISS-macroreturn: %return stops the current macro immediately, resumes the caller" {
    // The early-exit path: cond true → enter %do, emit L, %return → nothing else in
    // the body runs (NEVER / AFTER dropped). The non-early call runs to completion.
    // Open-code text after each call still emits (%return unwinds only to the macro).
    try expectExpand(
        "%macro m(x=);%if &x= %then %do;L%return;NEVER%end;AFTER&x%mend;[%m(x=)][%m(x=hi)]",
        "[L][AFTERhi]",
    );
    // %return inside a %do loop stops the loop AND the macro (tail not reached).
    try expectExpand(
        "%macro n;%do i=1 %to 5;[&i]%if &i=2 %then %return;%end;TAIL%mend;%n",
        "[1][2]",
    );
    // A fresh call after a returning call is unaffected (flag cleared at the boundary).
    try expectExpand("%macro r;A%return;B%mend;%r%r", "AA");

    // Only the pre-%return %put fires; the post-%return line does not (the repro).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    _ = try expand(a,
        "%macro m(x=);%if &x= %then %do;%put NOTE: missing arg, leaving.;%return;%end;%put NOTE: should not print;%mend;%m(x=)",
        &diags);
    const log = try diags.render();
    try std.testing.expect(std.mem.indexOf(u8, log, "leaving") != null);
    try std.testing.expect(std.mem.indexOf(u8, log, "should not print") == null);

    // GH#4 (qa gate): `%return` in OPEN CODE (no enclosing macro) must NOT unwind —
    // that would silently swallow the rest of the program. It errors visibly and
    // open code keeps running (AFTER is still emitted).
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    const a2 = arena2.allocator();
    var diags2 = diag.Diagnostics.init(a2);
    const got = try expand(a2, "START%return;AFTER", &diags2);
    try std.testing.expectEqualStrings("STARTAFTER", got);
    // SEV-returnopencode: exact SAS wording (App.2 printed p.500) at SAS's own
    // severity — ERROR, not WARNING. stderr-only, so no corpus fixture can pin it
    // (a stdout diff passes vacuously); pinned via the captured reporter (D-003).
    try std.testing.expectEqualStrings("ERROR: The %RETURN statement is not valid in open code.\n", try diags2.render());
    // The observable halves of the severity change: exit code 1 (D-009
    // user-program error — the hasErrors→exitCode mapping is pinned in diag.zig's
    // D-009 test)…
    try std.testing.expect(diags2.hasErrors());
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(false, diags2.hasErrors()));
    // …while a LATER STEP STILL RUNS: macro_scoped ⇒ no step error ⇒ main's
    // syntax-check gate (hasStepErrors) never trips, and the text after %return
    // survived expansion above.
    try std.testing.expect(!diags2.hasStepErrors());
}

test "SEV-opencodefamilyrest: open-code %LOCAL ERRORS (was a silent declare)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `%local` in open code used to silently declare at exit 0 with NO diagnostic
    // — a silent no-op on invalid SAS, the failure class house rules put first.
    // App.2 ERROR Messages section, printed p.500 (pdf 515, +15 offset): "Error:
    // The %LOCAL statement is not valid in open code." stderr-only, so no corpus
    // fixture can pin it (a stdout diff passes vacuously) — pinned via the
    // captured reporter (D-003), exactly as SEV-returnopencode's test.
    var d = diag.Diagnostics.init(a);
    const got = try expand(a, "%local x;AFTER", &d);
    // SAS "reports an error and CONTINUES": the statement is dropped and the
    // text after it still expands (a later step still runs).
    try std.testing.expectEqualStrings("AFTER", got);
    try std.testing.expectEqualStrings("ERROR: The %LOCAL statement is not valid in open code.\n", try d.render());
    // Exit 1 (D-009 user-program error)…
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(false, d.hasErrors()));
    // …with NO step-skip: macro_scoped ⇒ main's hasStepErrors gate never trips.
    try std.testing.expect(!d.hasStepErrors());
    // Inside a macro %local still declares (the guard is open-code-only).
    try expectExpand("%macro m;%local x;%let x=hi;[&x]%mend;%m", "[hi]");
    // %GLOBAL is NOT in the family — still valid in open code.
    try expectExpand("%global g;%let g=ok;&g", "ok");
}

test "SEV-opencodefamilyrest: open-code %END ERRORS (was unresolved-macro WARNING)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // A stray open-code `%end` (the classic missing/misspelled %MEND tell) fell
    // through to "WARNING: Apparent invocation of macro END not resolved." at
    // exit 0 — wrong message and wrong severity. App.2 ERROR Messages section,
    // printed p.500 (pdf 515, +15 offset): "Error: The %END statement is not
    // valid in open code." Captured reporter (D-003) — stderr-only, a corpus
    // fixture would pass vacuously.
    var d = diag.Diagnostics.init(a);
    const got = try expand(a, "START%end;AFTER", &d);
    // The whole statement (to its `;`) is dropped and open code keeps running.
    try std.testing.expectEqualStrings("STARTAFTER", got);
    try std.testing.expectEqualStrings("ERROR: The %END statement is not valid in open code.\n", try d.render());
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(false, d.hasErrors()));
    try std.testing.expect(!d.hasStepErrors()); // macro_scoped — no step-skip
    // Open-code %if … %then %do;…%end; blocks stay accepted (M5+, pinned by
    // macro_autovars/macro_runtimescope): their %end never reaches handlePercent.
    try expectExpand("%if 1 %then %do;yes%end;after", "yesafter");
}

test "SEV-opencodefamilyrest: open-code %ABORT ERRORS and CONTINUES (was a halt)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Open-code %ABORT used to set `aborting` and drop the rest of the program —
    // too strict: App.2 lists it in the same ERROR Messages family (printed
    // p.500, pdf 515 +15 offset: "Error: The %ABORT statement is not valid in
    // open code."), and SAS reports the error and CONTINUES. The RELAXATION only
    // touches the open-code guard; the in-macro halt below is untouched.
    var d = diag.Diagnostics.init(a);
    const got = try expand(a, "before %abort; after-abort", &d);
    // The real content: text after the open-code %abort STILL EXPANDS (a later
    // step still runs) — pre-fix this came back "before ".
    try std.testing.expectEqualStrings("before  after-abort", got);
    try std.testing.expectEqualStrings("ERROR: The %ABORT statement is not valid in open code.\n", try d.render());
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(false, d.hasErrors()));
    try std.testing.expect(!d.hasStepErrors()); // macro_scoped — no step-skip
    // The in-macro halt is NOT relaxed: still loud, still drops later text
    // (same assertions as NOTE-macroloudlabels, pinned against this change).
    var d2 = diag.Diagnostics.init(a);
    const out2 = try expand(a, "%macro m;%abort;%mend;before %m after-abort", &d2);
    try std.testing.expectEqualStrings("before ", out2);
    try std.testing.expectEqualStrings("ERROR: %ABORT is not supported — halting execution\n", try d2.render());
}

test "%if / %then / %else, numeric and default-truthy" {
    try expectExpand("%if 15>10 %then %let r=big;%else %let r=small;&r", "big");
    try expectExpand("%if 3>10 %then %let r=big;%else %let r=small;&r", "small");
    try expectExpand("%let x=0;%if &x %then A;%else B;", "B"); // 0 is false
}

test "BUG-macroevalcond: %if/%while honor and/or + mnemonic ops (unify with %eval)" {
    // and/or were ignored (only the first comparison was read) → this was TRUE.
    try expectExpand("%if 20>=1 and 20<=10 %then A;%else B;", "B");
    try expectExpand("%if 5>=1 and 5<=10 %then A;%else B;", "A");
    // precedence: and binds tighter than or.
    try expectExpand("%if 0 or 1 and 0 %then A;%else B;", "B");
    // mnemonic comparison operators (were unrecognized → wrong branch).
    try expectExpand("%if X eq X %then A;%else B;", "A");
    try expectExpand("%if X eq Y %then A;%else B;", "B");
    try expectExpand("%if 5 ne 5 %then A;%else B;", "B");
    // %do %while with a mnemonic `ne` against an empty value must TERMINATE, not
    // spin forever: `%scan` runs out → `&d` empty → `ne` compares ""ne"" → false.
    try expectExpand(
        "%let l=DM AE;%let i=1;%let d=%scan(&l,&i);%do %while(&d ne );[&d]%let i=%eval(&i+1);%let d=%scan(&l,&i);%end;",
        "[DM][AE]",
    );
}

test "%eval integer arithmetic, comparison, logical, precedence" {
    try expectExpand("%let a=3;%let b=4;[%eval(&a+&b)][%eval(&a*&b)][%eval(&b/&a)]", "[7][12][1]");
    try expectExpand("[%eval((1+2)*3)][%eval(10-2-3)][%eval(-5+2)]", "[9][5][-3]");
    try expectExpand("[%eval(5>2)][%eval(1>2)][%eval(2>1 and 3>2)][%eval(0 or 0)][%eval(not 0)]", "[1][0][1][0][1]");
    // %eval inside %if: the function yields 1/0 and %if tests truthiness
    try expectExpand("%let a=3;%if %eval(&a=3) %then Y;%else N;", "Y");
    try expectExpand("%let a=3;%if %eval(&a>9) %then Y;%else N;", "N");
}

test "%eval saturates on i64 overflow (BUG-evaloverflow), never crashes" {
    try expectExpand("[%eval(9223372036854775807 + 1)]", "[9223372036854775807]"); // MAX+1 → MAX
    try expectExpand("[%eval(9999999999 * 9999999999)]", "[9223372036854775807]"); // product → MAX
    try expectExpand("[%eval(-9223372036854775807 - 2)]", "[-9223372036854775808]"); // → MIN
    try expectExpand("[%eval(-9999999999 * 9999999999)]", "[-9223372036854775808]"); // → MIN
    // BUG-macropow: `**` exponentiates (used to degrade to 0) — binds tighter
    // than unary minus, right-associative, saturating on overflow.
    try expectExpand("[%eval(2**10)][%eval(3**3)][%eval(2**0)]", "[1024][27][1]");
    try expectExpand("[%eval(-2**2)][%eval(2**3**2)][%eval(2*3**2)]", "[-4][512][18]");
    try expectExpand("[%eval(2**-1)][%eval(0**0)][%eval((-1)**-3)]", "[0][1][-1]");
    try expectExpand("[%eval(10**20)]", "[9223372036854775807]"); // saturate, no crash
    try expectExpand("[%sysevalf(2**0.5)]", "[1.4142135623730951]");
    try expectExpand("[%sysevalf(-2**2)][%sysevalf(2**-1)]", "[-4][0.5]");
}

test "recursive macro terminates (bounded) instead of overflowing the stack" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    // Unbounded self-recursion: must return bounded output, not segfault.
    const outp = try expand(a, "%macro r; a%r %mend;%r", &diags);
    try std.testing.expect(outp.len > 0);
    try std.testing.expect(outp.len < 100_000);
}

test "BUG-macrodowhilehang: nested %let in a %let value errors loud, never hangs" {
    // qa tick158 fuzz repro: the malformed nested `%let` left the guard var
    // unchanged → `%do %while` never converged → HANG. Now: one loud macro-
    // scoped ERROR and the macro unwinds; open code after the call still runs.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    const outp = try expand(a,
        \\%let list=;
        \\%macro build;
        \\  %let i=1;
        \\  %do %while(&i <= 3);
        \\    %let list=&list-&i;
        \\    %let i=%let i=%eval(&i + 1);
        \\  %end;
        \\%mend;
        \\%build
        \\AFTER
    , &diags);
    // Terminated with a bounded expansion (a hang never returns; a cap-spin
    // would balloon `list` toward max_loop_iters entries).
    try std.testing.expect(outp.len < 10_000);
    try std.testing.expect(std.mem.indexOf(u8, outp, "AFTER") != null); // macro-scoped: later code runs
    try std.testing.expect(diags.hasErrors());
    try std.testing.expect(!diags.hasStepErrors()); // no syntax-check poison (BUG-errhalt)
    const log = try diags.render();
    try std.testing.expect(std.mem.indexOf(u8, log, "not valid inside a %LET value") != null);

    // Well-formed loops are untouched: run to normal completion, no error.
    try expectExpand("%macro w;%let i=1;%do %while(&i <= 3);[&i]%let i=%eval(&i+1);%end;%mend;%w", "[1][2][3]");
    try expectExpand("%macro u;%let k=0;%do %until(&k >= 3);[&k]%let k=%eval(&k+1);%end;%mend;%u", "[0][1][2]");
    // NR-quoted `%let` TEXT is a value, not a statement — must NOT error.
    // %nrstr is the ONLY in-value route that masks `%` (printed p.342: "In
    // addition, %NRSTR also masks the following characters: & %"); %str and
    // quotation marks do not (%str(%let) expanding to empty is pre-existing
    // %str semantics, untouched here; a quoted '%let' is a LIVE nested %LET
    // under the sq_masks_triggers rule and errors — pinned by the ticket test).
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    var diags2 = diag.Diagnostics.init(arena2.allocator());
    const ok = try expand(arena2.allocator(), "%let x=%str(%let);%let q=%nrstr('%let');[&q]", &diags2);
    try std.testing.expectEqualStrings("['%let']", ok);
    try std.testing.expect(!diags2.hasErrors());
}

test "chained: macro sets a var via %if, body uses it" {
    try expectExpand(
        "%macro c(n);%if &n > 10 %then %let L=big;%else %let L=small;[&n:&L]%mend;\n%c(15)%c(3)",
        "\n[15:big][3:small]",
    );
}

test "macro functions: %scan / %substr / %upcase / %lowcase (MACROFN)" {
    try expectExpand("%let s=alpha beta gamma;\n&s|%scan(&s,2)|%scan(&s,-1)", "\nalpha beta gamma|beta|gamma");
    try expectExpand("%let s=abcdef;\n%substr(&s,2,3)|%substr(&s,4)", "\nbcd|def");
    try expectExpand("%upcase(Hello)|%lowcase(Hello)", "HELLO|hello");
    // a custom delimiter for %scan
    try expectExpand("%scan(a-b-c,2,-)", "b");
}

test "%global/%local, %do %while/%until, %str/%nrstr, %sysfunc/%sysevalf, %index/%length (G-macro)" {
    // %global/%local just ensure the name exists in the one global table
    try expectExpand("%global g;%let g=7;&g", "7");
    try expectExpand("%local x;%let x=hi;&x", "hi");
    // %do %while — tested at the top; body must move the guard var
    try expectExpand("%let i=1;%do %while(&i < 3);[&i]%let i=%eval(&i+1);%end;", "[1][2]");
    // %do %until — tested at the bottom, runs at least once
    try expectExpand("%let k=0;%do %until(&k >= 2);%let k=%eval(&k+1);%end;&k", "2");
    // %length / %index (1-based; 0 when absent)
    try expectExpand("%length(hello)|%index(abcdef,cd)|%index(abc,z)", "5|3|0");
    // %str/%quote/%bquote resolve &/%; %nrstr emits verbatim; %nrbquote/%nrquote
    // are execution-time — resolve THEN mask (BUG-macronrbquoteresolve).
    try expectExpand("%let x=9;%str(&x-a)|%nrstr(&x-a)", "9-a|&x-a");
    try expectExpand("%let x=9;%quote(&x-a)|%bquote(&x-a)|%nrbquote(&x-a)|%nrquote(&x-a)", "9-a|9-a|9-a|9-a");
    // %superq yields the unresolved value of the NAMED var; %qupcase masks+uppercases
    try expectExpand("%let z=hi;%superq(z)|%qupcase(&z)", "hi|HI");
    // %sysfunc string subset
    try expectExpand("%sysfunc(upcase(hi))|%sysfunc(length(abc))|%sysfunc(compress(a b c))", "HI|3|abc");
    // %sysfunc also routes numeric functions through the DATA-step table (G-sysfuncnum)
    try expectExpand("%sysfunc(max(3,7))|%sysfunc(int(4.9))|%sysfunc(abs(-5))", "7|4|5");
    // %sysevalf floats, with an optional result type
    try expectExpand("%sysevalf(1.5+2.5)|%sysevalf(7/2)|%sysevalf(2.5+2.5,integer)", "4|3.5|5");
}

test "BUG-sysfuncbest: numeric %sysfunc result uses BEST12., not raw f64 precision" {
    // Real SAS renders a numeric %sysfunc result through its default BEST12.
    // format — 12 columns of significant digits — not full double precision.
    try expectExpand("%sysfunc(constant(pi))", "3.1415926536");
    try expectExpand("%sysfunc(sqrt(2))", "1.4142135624");
    try expectExpand("%sysfunc(exp(1))", "2.7182818285");
    // integers stay plain; a whole number too wide for 12 cols → E-notation
    try expectExpand("%sysfunc(int(4.9))|%sysfunc(abs(-5))", "4|5");
    try expectExpand("%sysfunc(int(1e15))", "1E15");
}

test "BUG-sysevalfsci: %sysevalf reads scientific-notation exponents" {
    // The float scan used to stop at `e`, reading 1e10 as 1.
    try expectExpand("%sysevalf(1e10)|%sysevalf(1E3)|%sysevalf(1.5e3)", "10000000000|1000|1500");
    try expectExpand("%sysevalf(1e-2)|%sysevalf(2 + 1e3)|%sysevalf(2.5e2 + 1)", "0.01|1002|251");
}

test "QA-tick377-F3: %sysevalf evaluates comparisons — its documented reason to exist" {
    // Macro Language Reference printed p.352 (footer-verified): %SYSEVALF
    // "Evaluates arithmetic AND LOGICAL expressions using floating-point
    // arithmetic"; printed p.91: "You must use the %SYSEVALF function to
    // evaluate logical expressions containing floating-point or missing
    // values." The comparison layer was ABSENT — every operator was silently
    // dropped and the LEFT OPERAND came back, exit 0.
    try expectExpand("%sysevalf(1.5 ^= 2.5)|%sysevalf(1.5 ne 2.5)", "1|1"); // the F3 repro, A and B
    try expectExpand("%sysevalf(1.5 < 2.5)|%sysevalf(1.5 = 2.5)", "1|0"); // the F3 repro, C and D
    try expectExpand("%sysevalf(2.5 > 1.5)|%sysevalf(2.5 >= 2.5)|%sysevalf(1.5 <= 1.5)", "1|1|1");
    try expectExpand("%sysevalf(1.5 eq 1.5)|%sysevalf(1.5 gt 2.5)|%sysevalf(1.5 lt 2.5)", "1|0|1");
    // the \xC2\xAC glyph — %EVAL's b2e55324 spelling, the two tokenizers agree
    try expectExpand("%sysevalf(2.5 ¬= 2.5)|%sysevalf(2.5 ¬= 3.5)", "0|1");
    // comparisons bind LOOSER than arithmetic; parens carry a full expression;
    // a conversion type applies to the 1/0 result
    try expectExpand("%sysevalf(1 + 2 = 3)|%sysevalf((1.5 < 2.5) + 1)", "1|2");
    try expectExpand("%sysevalf(1.5 < 2.5, boolean)|%sysevalf(1.5 > 2.5, boolean)", "1|0");
    // a glued `ne2` is an OPERAND, not the NE operator (tokenizeEval agrees) —
    // here simply a leftover, kept out of the silent-drop class by the F3 loud
    // check below; arithmetic is byte-identical to before (regression guard)
    try expectExpand("%sysevalf(1.5 + 2.5)|%sysevalf(7 / 2)|%sysevalf(2**0.5)", "4|3.5|1.4142135623730951");
}

test "QA-tick377-F3: an operator %sysevalf cannot evaluate is LOUD, never silently dropped" {
    // The F3 root class: unconsumed input came back as the left operand with
    // exit 0. Now: a documented logical operator the float grammar lacks
    // (and/or/not) is an opensas GAP (D-009 rc 2); garbage — and `in`, which
    // SAS itself rejects in %SYSEVALF (Restriction, printed p.353) — is the
    // user's own error (rc 1). Captured reporter (D-003), no aborting child.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    diag.resetGap();
    defer diag.resetGap(); // leave the process-global flag clean for other tests
    var d = diag.Diagnostics.init(a);
    _ = try expand(a, "%put %sysevalf(1.5 and 2.5);", &d);
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(diag.gapHit()); // documented in SAS, missing here → our gap
    diag.resetGap();
    for ([_][]const u8{ "%put %sysevalf(1.5 @@ 2.5);", "%put %sysevalf(1.5 in 1.5 2.5);" }) |prog| {
        var d2 = diag.Diagnostics.init(a);
        _ = try expand(a, prog, &d2);
        try std.testing.expect(d2.hasErrors());
        try std.testing.expect(!diag.gapHit()); // the user's own error, not our gap
    }
}

test "NOTE-sysevalfempty: an empty %sysevalf() is the verbatim p.354 ERROR, not a silent 0" {
    // Printed p.354: "If expression evaluates to a null value or one or more
    // blank spaces, then there is nothing for %SYSEVALF to evaluate. In that
    // case, the following error results:
    //     ERROR: %SYSEVALF function has no expression to evaluate."
    // The wording is QUOTED in the doc and asserted VERBATIM below. Captured
    // reporter (D-003), no aborting child.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const verbatim = "ERROR: %SYSEVALF function has no expression to evaluate.";
    for ([_][]const u8{
        "%sysevalf()", // null
        "%sysevalf(   )", // one or more blank spaces
        "%let e=;%sysevalf(&e)", // "evaluates to a null value"
        "%sysevalf(,boolean)", // a conversion type rescues nothing — no EXPRESSION
    }) |prog| {
        var d = diag.Diagnostics.init(a);
        const out = try expand(a, prog, &d);
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), verbatim) != null);
        try std.testing.expect(std.mem.indexOf(u8, out, "0") == null); // never the old silent 0
    }
    // controls: a real expression does not error — and neither does a PRESENT
    // missing literal (`%sysevalf(.)` has an expression; it evaluates to `.`).
    for ([_][]const u8{ "%sysevalf(1/3)", "%sysevalf(.)", "%sysevalf(0)" }) |prog| {
        var d = diag.Diagnostics.init(a);
        _ = try expand(a, prog, &d);
        try std.testing.expect(!d.hasErrors());
    }
}

test "BUG-macrodateliteral: date/time literals evaluate inside %sysfunc/%sysevalf" {
    try expectExpand("%sysevalf('15JAN2020'd)", "21929");
    try expectExpand("%sysevalf('15JAN2020'd + 1)", "21930"); // literal in an expression
    try expectExpand("%sysevalf('12:00't)|%sysevalf('15JAN2020:12:00:00'dt)", "43200|1894708800");
    try expectExpand("%sysfunc(day('15JAN2020'd))", "15");
    try expectExpand("%sysfunc(intnx(month, '15JAN2020'd, 3))", "22006");
    try expectExpand("%sysfunc(month(\"01JAN2020\"d))", "1"); // double-quoted literal too
}

test "macro-indirect &&var&i / &&& ; %superq raw value" {
    // &&var&i macro-array indirection (the SDTM loop-over-domains idiom)
    try expectExpand("%let v1=AE;%let v2=CM;%let i=2;&&v&i", "CM");
    // triple &&&x: resolve &x to a name, then that name
    try expectExpand("%let x=a;%let a=hello;&&&x", "hello");
    // %superq returns the named variable's value; empty when undefined
    try expectExpand("%let a=hello;%superq(a)", "hello");
    try expectExpand("%superq(nope)", "");
    // %let/%put value scan skips %str(...) spans, so a masked ; does not end it early
    try expectExpand("%let c=%str(x=1; y=2);&c", "x=1; y=2");
    try expectExpand("%let d=%str(a,b;c);&d", "a,b;c");
    // keyword params + defaults (the core SDTM %macro pattern)
    try expectExpand("%macro m(a,b=B,c=C);[&a|&b|&c]%mend;%m(1)%m(2,c=Z)%m(3,b=Y)", "[1|B|C][2|B|Z][3|Y|C]");
    // positional then keyword; a keyword value may contain spaces
    try expectExpand("%macro r(dom,keep=id);<&dom:&keep>%mend;%r(AE)%r(CM,keep=id trt)", "<AE:id><CM:id trt>");
}

test "macro-sysfuncfmt: optional format arg, 2-arg putn, nested %sysfunc" {
    // 2-arg putn applies its own format
    try expectExpand("%sysfunc(putn(21915,date9.))", "01JAN2020");
    // the optional %sysfunc output format (after the call) — BUG-sysfuncfmt
    try expectExpand("%sysfunc(mdy(1,1,2020),date9.)", "01JAN2020");
    // nested %sysfunc: inner value formatted by the outer putn
    try expectExpand("%sysfunc(putn(%sysfunc(mdy(1,1,2020)),date9.))", "01JAN2020");
}

test "macro-macrofns: %sysevalf int, %qscan, %symexist/%symglobl" {
    try expectExpand("%sysevalf(7/2,int)|%sysevalf(7/2,integer)|%sysevalf(7/2,ceil)|%sysevalf(7/2,floor)", "3|3|4|3");
    try expectExpand("%sysevalf(0,boolean)|%sysevalf(5,boolean)", "0|1");
    try expectExpand("%qscan(a-b-c,2,-)|%qscan(x y z,-1)", "b|z");
    try expectExpand("%let y=1;%symexist(y)|%symexist(no)", "1|0");
    try expectExpand("%let g=1;%symglobl(g)|%symglobl(no)", "1|0");
}

test "macro-sysfunc breadth incl compress modifiers" {
    try expectExpand("%sysfunc(compress(a1b2c3,,kd))|%sysfunc(compress(a-b-c,-))", "123|abc");
    try expectExpand("%sysfunc(catx(-,a,b,c))|%sysfunc(tranwrd(aXbX,X,-))", "a-b-c|a-b-");
    try expectExpand("%sysfunc(reverse(abc))|%sysfunc(count(abcabc,a))|%sysfunc(propcase(john doe))", "cba|2|John Doe");
    try expectExpand("%sysfunc(year(21915))|%sysfunc(month(21915))|%sysfunc(day(21915))", "2020|1|1");
}

test "BUG-strsemicolon: %str/%nrstr mask ; across %let, %then, open code" {
    // %let value keeps the masked ;
    try expectExpand("%let a=%str(x;y);&a", "x;y");
    // %then / %else branch not truncated by a ; inside %str
    try expectExpand("%macro c(n);%if &n>0 %then %str(p;q);%else %str(r;s);%mend;%c(1)|%c(-1)", "p;q|r;s");
    // %nrstr masks ; too (and does not resolve &)
    try expectExpand("%let b=%nrstr(m;&n);&b", "m;&n");
}

test "macro-unquote-macexist: %sysmacexist, %unquote" {
    try expectExpand("%macro e;x%mend;%sysmacexist(e)|%sysmacexist(none)", "1|0");
    // %unquote resolves an & that %nrstr had masked
    try expectExpand("%let x=5;%let q=%nrstr(&x go);%unquote(&q)", "5 go");
}

test "macro-syscall: %syscall sortn/sortc mutate macro vars" {
    try expectExpand("%let a=3;%let b=1;%let c=2;%syscall sortn(a,b,c);&a &b &c", "1 2 3");
    try expectExpand("%let a=cm;%let b=ae;%let c=lb;%syscall sortc(a,b,c);&a &b &c", "ae cm lb");
}

test "QA-letindexed: %let resolves macro refs in the TARGET name (vart_&i idiom)" {
    // `%let v_&i=…` assigns v_1, not a literal "v_" (the %do-loop indexed-table
    // idiom — real SDTM split macros build VART_1..VART_n this way; the broken form lost
    // the split rows of every double-coded AE).
    try expectExpand("%let i=1;%let v_&i=HELLO;<&v_1>", "<HELLO>");
    // dotted-terminator form, and && indirection reading it back
    try expectExpand("%let i=2;%let w_&i.=B;<&&w_&i>", "<B>");
    // inside a macro with %local of the computed name (SPLIT's exact shape)
    try expectExpand("%macro m;%do i=1 %to 2;%local t_&i;%let t_&i=X&i;%end;<&t_1&t_2>%mend;%m", "<X1X2>");
    // plain %let unaffected
    try expectExpand("%let a=1;<&a>", "<1>");
}

test "BUG-macrobareletscope: bare %let of a new name inside a macro is auto-local" {
    // (a) sibling isolation: each macro's auto-local i is its own, and NEITHER
    // survives to global after return (%symexist 0 at open code).
    try expectExpand("%macro a;%let i=1;[&i]%mend;%macro b;%let i=2;[&i]%mend;%a%b;[%symexist(i)]", "[1][2];[0]");
    // auto-local is visible inside its macro as local: exist yes, local yes, global no.
    try expectExpand("%macro m;%let q=1;[%symexist(q)][%symlocal(q)][%symglobl(q)]%mend;%m", "[1][1][0]");
    // computed names auto-localize the same way and die with the macro.
    try expectExpand("%macro m;%do k=1 %to 2;%let v_&k=V&k;%end;[&v_1&v_2]%mend;%m;[%symexist(v_1)]", "[V1V2];[0]");
    // (b) %let of an EXISTING global still updates the global (no shadow).
    try expectExpand("%let g=1;%macro m;%let g=2;%mend;%m;[&g]", ";[2]");
    // a name an ENCLOSING macro's scope owns updates there, not a new inner local.
    try expectExpand("%macro in2;%let z=IN;%mend;%macro out2;%let z=OUT;%in2;[&z]%mend;%out2;[%symexist(z)]", ";[IN];[0]");
    // explicit %local unchanged: the %let hits the local, nothing survives.
    try expectExpand("%macro m;%local y;%let y=v;[&y]%mend;%m;[%symexist(y)]", "[v];[0]");
    // open-code %let is still global.
    try expectExpand("%let x=hi;[%symglobl(x)][&x]", "[1][hi]");
}

test "macro-localscope: %local shadows+restores; params are local; %global persists" {
    // %local x shadows the outer x and is restored when the macro returns
    try expectExpand("%macro m;%local x;%let x=in;<&x>%mend;%let x=out;%m<&x>", "<in><out>");
    // macro parameters are local — do not clobber a same-named global
    try expectExpand("%macro u(p);<&p>%mend;%let p=G;%u(L)<&p>", "<L><G>");
    // %global persists past the macro
    try expectExpand("%macro g;%global gv;%let gv=keep;%mend;%g<&gv>", "<keep>");
}

test "resolveVarsIn: late-binds CALL SYMPUT vars into string text (BUG-symput)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // the store keys are lowercased, like Library.setMacroVar writes them
    var vars: std.StringHashMapUnmanaged([]const u8) = .empty;
    try vars.put(a, "a", "hello");
    try vars.put(a, "n", "42");

    try std.testing.expectEqualStrings("hello", try resolveVarsIn(a, "&a", &vars));
    try std.testing.expectEqualStrings("x=hello", try resolveVarsIn(a, "x=&a", &vars));
    try std.testing.expectEqualStrings("n is 42!", try resolveVarsIn(a, "n is &n.!", &vars)); // trailing-dot delimiter consumed
    try std.testing.expectEqualStrings("hello", try resolveVarsIn(a, "&A", &vars)); // name lookup is case-insensitive
    try std.testing.expectEqualStrings("&z", try resolveVarsIn(a, "&z", &vars)); // unknown var kept verbatim
    try std.testing.expectEqualStrings("no macros here", try resolveVarsIn(a, "no macros here", &vars)); // fast path
}

test "BUG-symgetlet: %let vars are visible to SYMGET/SYMEXIST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    functions.unbindLibrary(); // no CALL SYMPUT store here; read the %let table only

    // %let a=hi; runs the macro pass, which mirrors the var into the SYMGET table
    _ = try expand(a, "%let a=hi;\n%let n=42;", &diags);

    var pdv = Pdv.init(a);
    var ev: eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = &diags };
    try std.testing.expectEqualStrings("hi", (try functions.dispatch(&ev, "symget", &.{.{ .str = "a" }})).str);
    try std.testing.expectEqualStrings("42", (try functions.dispatch(&ev, "symget", &.{.{ .str = "N" }})).str); // case-insensitive
    try std.testing.expectEqual(@as(f64, 1), (try functions.dispatch(&ev, "symexist", &.{.{ .str = "a" }})).num);
    try std.testing.expectEqual(@as(f64, 0), (try functions.dispatch(&ev, "symexist", &.{.{ .str = "nope" }})).num);
    try std.testing.expectEqual(@as(f64, 1), (try functions.dispatch(&ev, "symglobl", &.{.{ .str = "a" }})).num);
    try std.testing.expectEqual(@as(f64, 0), (try functions.dispatch(&ev, "symlocal", &.{.{ .str = "a" }})).num);
    functions.clearLetVars();
}

test "QL-C: one evaluator — %if keeps evalBool semantics, %eval gains string compares" {
    // %eval string compares (the gap the consolidation fixes): lexical when a
    // side doesn't parse as an integer, numeric otherwise.
    try expectExpand("%eval(abc = abc)", "1");
    try expectExpand("%eval(abc = abd)", "0"); // was 1: both words dropped to 0
    try expectExpand("%eval(abc lt abd)", "1"); // was 0: lexical lt now works
    try expectExpand("%eval(1.5 lt 2)", "1"); // non-integer numerics compare as floats
    try expectExpand("%eval(2 lt 10)", "1"); // still numeric, not lexical ("2" gt "10")
    try expectExpand("%eval(10 / 3)", "3"); // integer arithmetic unchanged
    // %if leaf semantics preserved through the merge (the corpus fixture
    // macro_eval_cond pins the full matrix; these are the sharp edges):
    try expectExpand("%macro m;%if ABC = abc %then y;%else n;%mend;%m", "n"); // case-sensitive lexical
    // BUG-ifbaretruthy (manager call): bare NON-numeric leaves are no longer
    // truthy — `%if abc` / `%if 0.0` raise the same character-operand ERROR
    // %eval does (loud half pinned by the BUG-minoperatoropt test below).
    // Integer leaves keep the nonzero-true reading.
    try expectExpand("%macro m;%if 7 %then y;%else n;%mend;%m", "y");
    try expectExpand("%macro m;%if 0 %then y;%else n;%mend;%m", "n");
    // NOTE-macroevalops: `<>` is NOT a macro-language operator. Table 6.3 "Macro
    // Language Operators" (Macro Language Reference, printed p.87-88) spells NE as
    // `¬=` / `^=` / `~=` / NE and lists no fourth form; %EVAL's own entry (p.328)
    // points at that chapter as "a complete discussion". We used to read it as NE,
    // which made `%if &a <> &b` a silent superset. Now it is the same loud
    // unknown-operator %EVAL error `mod`/`foo` already raise — captured reporter (D-003).
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var d = diag.Diagnostics.init(a);
        _ = try expand(a, "%macro m;%if a <> b %then y;%else n;%mend;%m", &d);
        try std.testing.expect(d.hasErrors());
    }
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var d = diag.Diagnostics.init(a);
        _ = try expand(a, "%eval(1 <> 2)", &d);
        try std.testing.expect(d.hasErrors());
    }
    // …and every spelling Table 6.3 DOES list still works, plus the `<`/`<=` that
    // share the tokenizer arm `<>` was carved out of.
    try expectExpand("%macro m;%if a ^= b %then y;%else n;%mend;%m", "y");
    try expectExpand("%macro m;%if a ne b %then y;%else n;%mend;%m", "y");
    try expectExpand("%eval(1 ^= 2)|%eval(1 ne 2)|%eval(1 < 2)|%eval(1 <= 2)|%eval(2 > 1)", "1|1|1|1|1");
    // empty-operand mnemonic: bare `ne` (empty var both sides) is false → loops exit
    try expectExpand("%let e=;%macro m;%if &e ne %then y;%else n;%mend;%m", "n");
}

test "GAP-macrodoindex: the iterative %DO index is re-read, so the body can end the loop" {
    // Macro Language Reference printed p.388: "You can change the value of the index
    // variable during processing … set[ting] the value of the index variable beyond
    // the stop value … ends processing of the loop." The index was a Zig-local
    // counter, so the body's %let never reached the loop and it ran the full count.
    try expectExpand("%macro m;%do i=1 %to 5;x&i.%if &i = 2 %then %let i = 99;%end;%mend;%m", "x1x2");
    try expectExpand("%macro m;%do i=5 %to 1 %by -1;d&i.%if &i = 4 %then %let i = -7;%end;%mend;%m", "d5d4");
    // untouched loops are unchanged, and %BY stays evaluated ONCE (same page:
    // "you cannot change it as the loop iterates") — only the INDEX is re-read.
    try expectExpand("%macro m;%do i=1 %to 3;y&i.%end;%mend;%m", "y1y2y3");
    try expectExpand("%macro m;%do i=1 %to 6 %by 2;z&i.%end;%mend;%m", "z1z3z5");
    // the terminal value stays the first one that failed the bound (BUG-macrodoscope b)
    try expectExpand("%macro m;%do i=1 %to 3;%end;&i%mend;%m", "4");
    try expectExpand("%macro m;%do i=1 %to 5;%if &i = 2 %then %let i = 99;%end;&i%mend;%m", "100");
    // an inner loop's early exit leaves the outer index alone
    try expectExpand("%macro m;%do i=1 %to 2;[&i.%do j=1 %to 9;%if &j = 1 %then %let j = 42;%end;]%end;%mend;%m", "[1][2]");
}

test "BUG-macroerrnostop: a %EVAL/%IF expression error STOPS the enclosing macro" {
    // Macro Language Reference printed p.162 prints both lines for this class, and
    // we emitted only the first — so a macro ran on past a condition it could not
    // evaluate. Everything after the failing %if must now disappear.
    try expectExpand("%macro m;BEFORE %if abc %then A;AFTER%mend;%m", "BEFORE ");
    try expectExpand("%macro m;BEFORE %if 1 %then A;AFTER%mend;%m", "BEFORE AAFTER"); // clean macro untouched
    // the second message is half the defect: without it nobody is told it stopped
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var d = diag.Diagnostics.init(a);
        _ = try expand(a, "%macro m;%if abc %then A;%mend;%m", &d);
        var saw_stop = false;
        for (d.list.items) |it|
            if (std.mem.indexOf(u8, it.message, "macro will stop executing") != null) {
                saw_stop = true;
            };
        try std.testing.expect(saw_stop);
    }
    // OPEN CODE must NOT unwind: SAS's sentence is about "the macro", and setting
    // `returning` at depth 0 would silently drop the rest of the program (GH#4,
    // the %RETURN open-code guard). The error still stands; the text keeps coming.
    try expectExpand("%eval(3.5)|tail", "0|tail");
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        var d = diag.Diagnostics.init(a);
        _ = try expand(a, "%eval(3.5)", &d);
        for (d.list.items) |it|
            try std.testing.expect(std.mem.indexOf(u8, it.message, "macro will stop executing") == null);
    }
    // Division by zero is NOT a documented stop (printed p.506 carries only Cause
    // and Solution) — it reports and the macro continues. Doc-supported sites only.
    try expectExpand("%macro m;BEFORE %eval(1/0) AFTER%mend;%m", "BEFORE 0 AFTER");
    // printed p.509: an index left non-integer by the body is a loud STOP, which
    // replaces the internal-counter fallback the %DO re-read shipped with.
    try expectExpand("%macro m;%do i=1 %to 3;x&i.%let i=abc;%end;TAIL%mend;%m", "x1");
}

test "BUG-macroevalnotsign: the two-byte `¬` lexes as NOT / NE in %EVAL's own tokenizer" {
    // Table 6.3 (Macro Language Reference printed p.87-88) lists the glyph on both
    // the `¬^~ NOT` row and the `¬= ^= ~= NE` row, so it must WORK — the same table
    // that made `<>` loud by omitting it.
    try expectExpand("%eval(1 ¬= 2)|%eval(5 ¬= 5)", "1|0");
    try expectExpand("%eval(¬0)|%eval(¬1)", "1|0");
    // 0 on the left proves this is real NE evaluation: the old code left the leaf
    // `1` behind, which merely tested TRUTHY, so `1 ¬= 2` looked right by accident
    // while `0 ¬= 2` would have come out false.
    try expectExpand("%eval(0 ¬= 2)", "1");
    try expectExpand("%macro m;%if 0 ¬= 2 %then Y;%else N;%mend;%m", "Y");
    try expectExpand("%macro m;%if ¬(1=2) %then Y;%else N;%mend;%m", "Y"); // was N
    // GLUED (no blanks) is ordinary SAS and was the silent-0 shape: the operand
    // scan ate 0xC2 0xAC into "1¬", compared it to 2, and the grammar consumed
    // everything, so nothing errored. Both sides of the scan needed the munch.
    try expectExpand("%eval(1¬=2)|%eval(5¬=5)", "1|0");
    // the glyph agrees with its ASCII twins and mixes with them
    try expectExpand("%eval(1 ^= 2)|%eval(1 ~= 2)|%eval(1 ¬= 2 and 3 ^= 4)", "1|1|1");
    try expectExpand("%eval(abc ¬= abd)", "1"); // lexical NE
}

test "BUG-macroevalnotsign: `¦` is NOT a macro OR operator and stays loud" {
    // Table 6.3's OR row is `|` ALONE. The broken bar occurs in the volume only in
    // character-class lists (never the operator table), so accepting it would be
    // the `<>` silent superset again. Captured reporter (D-003).
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    _ = try expand(a, "%put [%eval(0 ¦ 1)];", &d);
    try std.testing.expect(d.hasErrors());
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put [%eval(0 ¦¦ 1)];", &d2);
    try std.testing.expect(d2.hasErrors());
    // the ASCII OR it does list keeps working
    try expectExpand("%eval(0 | 1)", "1");
}

test "NOTE-sysfuncattrnname: a dataset NAME where %sysfunc wants a DSID fails loud" {
    // Macro Language Reference printed p.518: "Argument value to function value
    // referenced by the %SYSFUNC or %QSYSFUNC macro function is not a number" —
    // cause "A nonnumeric argument value is used instead of the expected numeric
    // value." It used to char→num coerce to missing, so the run "succeeded" with
    // `.`. Captured reporter (D-003). The positive control (a real DSID from OPEN)
    // is the corpus fixture opendisk.sas, which must stay green.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    _ = try expand(a, "%put [%sysfunc(attrn(work.d1,NOBS))];", &d);
    try std.testing.expect(d.hasErrors());
    // every member of the family is guarded, not just the one that was filed
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put [%sysfunc(varnum(work.d1,x))];", &d2);
    try std.testing.expect(d2.hasErrors());
    // a NUMERIC argument (including a missing) is not the error this guard raises
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put [%sysfunc(attrn(9999,NOBS))];", &d3);
    try std.testing.expect(!d3.hasErrors());
}

test "GAP-macrodoindex: a non-advancing %DO index trips the loud guard (QA tick377 F1)" {
    // Re-reading the index makes a non-advancing loop possible, which it was not
    // before (the internal counter always moved). Real SAS spins here; we stop on
    // the FIRST pass whose index fails to move toward `stop` — never on a raw trip
    // count, which truncated legal long loops (F1). Stopping where SAS spins is an
    // opensas limit: D-009 class 2 (gap), not 1. Captured reporter (D-003) — no
    // aborting child process.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    diag.resetGap();
    defer diag.resetGap(); // don't leak the process-global flag into other tests
    // pinned below stop (trips on the second pass) and pushed AWAY from stop
    // (trips on the first): both are the same non-advancement hazard.
    for ([_][]const u8{
        "%macro m;%do i=1 %to 5;%let i = 1;%end;%mend;%m",
        "%macro m;%do i=1 %to 5;%let i = %eval(&i - 2);%end;%mend;%m",
    }) |prog| {
        var d = diag.Diagnostics.init(a);
        _ = try expand(a, prog, &d);
        try std.testing.expect(d.hasErrors());
        const log = try d.render();
        try std.testing.expect(std.mem.indexOf(u8, log, "did not converge") != null);
        try std.testing.expect(diag.gapHit()); // D-009: an opensas limit exits 2, not 1
    }
    // a legal loop well past the OLD 100,000 raw-count backstop completes clean:
    // every pass advances, so the guard never trips (the F1 repro itself).
    var d2 = diag.Diagnostics.init(a);
    const out = try expand(a, "%macro m;%local n;%let n=0;%do i=1 %to 150000;%let n=%eval(&n+1);%end;BIGLOOP_N=&n%mend;%m", &d2);
    try std.testing.expect(!d2.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out, "BIGLOOP_N=150000") != null);
}

test "BUG-macroscandelim: a %str-quoted delimiter/needle is unmasked at the macro-fn arg boundary" {
    // The headline repro: %str(,) is THE comma-delimiter idiom, and the sentinel
    // reached scanWord's byte compare, so nothing ever split (word 2 came back "").
    try expectExpand("%let s=a,b c,d;[%qscan(&s,2,%str(,))]", "[b c]");
    try expectExpand("%let s=a,b c,d;[%qscan(&s,1,%str(,))]", "[a]");
    try expectExpand("%let s=a,b c,d;[%scan(&s,2,%str(,))]", "[b c]");
    try expectExpand("%let s=a,b c,d;[%qscan(&s,-1,%str(,))]", "[d]"); // negative index
    // %quote/%bquote mask identically, so they were equally broken.
    try expectExpand("%let s=a,b c,d;[%scan(&s,2,%quote(,))]", "[b c]");
    try expectExpand("%let s=a,b c,d;[%scan(&s,3,%bquote(,))]", "[d]");
    // The SIBLING byte-comparers the one boundary fix also covers.
    try expectExpand("%let s=a,b c,d;[%index(&s,%str(,))]", "[2]"); // was 0
    try expectExpand("%let s=a,b c,d;[%verify(&s,%str(a,bcd ))]", "[0]"); // was 2
    // Mirror direction: a masked SUBJECT never split on the DEFAULT delimiter set
    // either (',' is in scan_delims but the subject carried the sentinel).
    try expectExpand("%let m=%str(a,b);[%scan(&m,2)]", "[b]"); // was ""
    try expectExpand("%let m=%str(a,b);[%scan(&m,2,%str(,))]", "[b]");
    // Unmasked delimiters were always fine — pin that the fix left them alone.
    try expectExpand("[%scan(a-b-c,2,-)]", "[b]");
    try expectExpand("%let s=a,b c,d;[%scan(&s,2,%str(-))]", "[]"); // no '-' → one word
}

test "BUG-macrogroupamasking: Table 7.6 group A masked by the quoting fns (p.162 + NOTE-bquoteblank)" {
    // p.162's CORRECTED program must produce the documented log lines — before
    // this fix %str(and) did not mask the mnemonic, so %conjunct(word=and) said
    // NOT a conjunction and %eval(%str(and) = %str(and)) was 0: the doc's own
    // remedy, silently wrong. %put lands on the captured reporter in tests.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro conjunct(word= );%if %bquote(&word) = %str(and) or %bquote(&word) = but or %bquote(&word) = %str(or) %then %put *** &word is a conjunction. ***;%else %put *** &word is not a conjunction. ***;%mend conjunct;%conjunct(word=and)%conjunct(word=but)%conjunct(word=or)%conjunct(word=foo)", &diags);
    try std.testing.expectEqualStrings("NOTE: *** and is a conjunction. ***\nNOTE: *** but is a conjunction. ***\nNOTE: *** or is a conjunction. ***\nNOTE: *** foo is not a conjunction. ***\n", try diags.render());
    try std.testing.expect(!diags.hasErrors());
    // The %eval half of the same repro: quoted `and` is the VALUE, equal to itself.
    try expectExpand("[%eval(%str(and) = %str(and))]", "[1]"); // was 0
    // …and a masked mnemonic survives %let storage to compare equal later.
    try expectExpand("%let x=%str(and);%if &x = %str(and) %then T;%else F;", "T");
    // The %SCAN dictionary entry (printed p.338) settles the design question:
    // "%SCAN does not mask special characters or mnemonic operators in its
    // result, even when the argument was previously masked" — the blank still
    // DELIMITS (the boundary unmask), so this is `a`, never `a b`.
    try expectExpand("[%scan(%str(a b),1)]", "[a]");
    try expectExpand("[%scan(%str(a b),2)]", "[b]");
    // NOTE-bquoteblank, the p.107-108 READIT mechanism: two embedded blanks
    // quoted by %bquote are ONE operand, so `ne <empty>` is true; bare, the
    // same text is a leftover-token ERROR (SAS errors on the unquoted form).
    try expectExpand("%let s=Office Supplies;%if %bquote(&s) ne %then valid;%else null;", "valid");
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    var diags2 = diag.Diagnostics.init(arena2.allocator());
    _ = try expand(arena2.allocator(), "%let s=Office Supplies;%if &s ne %then valid;%else null;", &diags2);
    try std.testing.expect(diags2.hasErrors()); // captured, never a real abort (D-003)
    // A masked special char is character data in %EVAL.
    try expectExpand("[%eval(%str(=) = %str(=))]", "[1]");
    // NOT stays a live PREFIX operator and AND/OR stay live when BARE — only
    // quoted text is masked (the ticket's two subtleties, kept explicit).
    try expectExpand("[%eval(not 0)][%eval(1 and 0 or 1)]", "[1][1]");
    // A mnemonic inside a larger word is NOT a word token: no masking.
    try expectExpand("%upcase(%str(candy and or))", "CANDY AND OR");
    // The Q-form masks its result's group A items: the %qscan-produced `and`
    // stays DATA in the condition where plain %scan's would be the operator.
    try expectExpand("%if %qscan(a and b,2) = %str(and) %then T;%else F;", "T");
    // The tokenizer unmask is pinned through DIAGNOSTICS: masked-vs-masked
    // comparisons pass with or without it, but the character-operand ERROR must
    // name the operand 'and' — never the raw sentinel byte in a clinical log.
    var arena3 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena3.deinit();
    var diags3 = diag.Diagnostics.init(arena3.allocator());
    _ = try expand(arena3.allocator(), "%if %str(and) %then T;", &diags3);
    try std.testing.expect(std.mem.indexOf(u8, try diags3.render(), "'and'") != null);
}

test "GAP-macrocharoperanddetect: a BARE mnemonic in operand position is the p.162 loud ERROR" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // p.162's UNCORRECTED program: the bare `and`/`or` being compared "could
    // also be interpreted as the numeric operators AND and OR", so SAS emits
    // the character-operand ERROR pair for ANY argument and the macro prints
    // neither branch line — it is the PROGRAM that is wrong, not the call.
    // Captured reporter, never a real aborting process (D-003).
    var diags = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro conjunct(word= );%if &word = and or &word = but or &word = or %then %put *** &word is a conjunction. ***;%else %put *** &word is not a conjunction. ***;%mend conjunct;%conjunct(word=and)%conjunct(word=but)", &diags);
    const pair = "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: 'and'\n" ++
        "ERROR: The macro will stop executing.\n";
    try std.testing.expectEqualStrings(pair ++ pair, try diags.render());
    // The same ERROR in open code (%eval) carries no stop line — nothing to
    // unwind — and names the word AS WRITTEN, case preserved (never a
    // sentinel byte: a bare word carries no mask).
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(OR = or)", &d2);
    try std.testing.expectEqualStrings("ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: 'OR'\n", try d2.render());
    // Operand position, not mere presence: after `or`, after `(`, after `not`.
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(1 or and)%eval((and))%eval(not eq)", &d3);
    const r3 = try d3.render();
    try std.testing.expect(std.mem.indexOf(u8, r3, "'and'") != null);
    try std.testing.expect(std.mem.indexOf(u8, r3, "'eq'") != null);
    // CONTROLS — quoted mnemonics stay legal (BUG-macrogroupamasking made them
    // arrive masked; unmasking them here would re-break the doc's own remedy).
    try expectExpand("[%eval(%str(and) = %str(and))][%eval(%bquote(and) = %str(and))][%eval(%nrstr(and) = %str(and))]", "[1][1][1]");
    // …and the corrected p.162 program keeps printing the documented lines.
    try expectExpand("%macro c(word= );%if %bquote(&word) = %str(and) or %bquote(&word) = but or %bquote(&word) = %str(or) %then Y;%else N;%mend;%c(word=and)%c(word=but)%c(word=or)%c(word=foo)", "YYYN");
    // OPERATOR position stays live, and NOT stays a live PREFIX operator.
    try expectExpand("[%eval(1 and 0)][%eval(0 or 1)][%eval(2 eq 2)][%eval(not 0)]", "[0][1][1][1]");
    // IN is an operator only under MINOPERATOR: with the option OFF a bare `in`
    // is ordinary text (the BUT analog) and compares equal to itself…
    try expectExpand("[%eval(in = in)]", "[1]");
    // …with it ON, a bare `in` where an OPERAND belongs is the same loud ERROR,
    // as is a bare mnemonic inside an `in` LIST. (Two macros: the first ERROR
    // stops its own macro, so each case needs one.)
    var d4 = diag.Diagnostics.init(a);
    _ = try expand(a, "options minoperator;%macro m;%eval(in = in)%mend;%m%macro n;%if x in and b %then T;%mend;%n", &d4);
    const r4 = try d4.render();
    try std.testing.expect(std.mem.indexOf(u8, r4, "'in'") != null);
    try std.testing.expect(std.mem.indexOf(u8, r4, "'and'") != null);
    // The lone-mnemonic collapse is NOT this ERROR: the scan-loop idiom's
    // ` ne ` (empty &word) stays the implicit empty-operand compare — false.
    try expectExpand("%let l=DM AE;%let i=1;%let d=%scan(&l,&i);%do %while(&d ne );[&d]%let i=%eval(&i+1);%let d=%scan(&l,&i);%end;", "[DM][AE]");
}

test "BUG-macronrstrmask: %nrstr &-mask survives storage + re-resolution; Q-results mask &" {
    // The headline repro: %nrstr(&a) stored, then referenced — must stay &a.
    try expectExpand("%let a=one;%let b=%nrstr(&a);[&b]", "[&a]");
    // …referenced twice, and through a second %let hop.
    try expectExpand("%let a=one;%let b=%nrstr(&a);%let c=&b;[&b][&c]", "[&a][&a]");
    // % masking already survived (no sentinel needed) — pin the asymmetry.
    try expectExpand("%macro pct;P%mend;%let e=%nrstr(%pct);[&e]", "[%pct]");
    // Q-function RESULTS mask &: a masked & through %qsubstr/%qupcase stays masked.
    try expectExpand("%let b=one;%let q=%qsubstr(%nrstr(a&b),2,2);[&q]", "[&b]");
    try expectExpand("%let b=one;[%qupcase(%nrstr(&b))]", "[&B]");
    try expectExpand("%let b=one;[%qscan(%nrstr(x&b|y),1,|)]", "[x&b]");
    // %unquote drops the mask: the & resolves on the next pass.
    try expectExpand("%let x=5;%let q=%nrstr(&x);%unquote(&q)", "5");
    // Plain %str still resolves & at mask time (unchanged).
    try expectExpand("%let x=9;[%str(&x-a)]", "[9-a]");
}

test "BUG-macrosymglobl/BUG-macrosymlocal: scope-aware %symglobl/%symlocal" {
    // %local var: not global, is local (the headline repros).
    try expectExpand("%macro t;%local x;%let x=5;[%symglobl(x)][%symlocal(x)]%mend;%t", "[0][1]");
    // a macro PARAM is local too.
    try expectExpand("%macro t(p);[%symglobl(p)][%symlocal(p)]%mend;%t(1)", "[0][1]");
    // plain %let global: global, not local.
    try expectExpand("%let g=1;[%symglobl(g)][%symlocal(g)]", "[1][0]");
    // missing var: all three 0.
    try expectExpand("[%symglobl(no)][%symlocal(no)][%symexist(no)]", "[0][0][0]");
    // a %local that SHADOWS an existing global: the global still exists (SAS).
    try expectExpand("%let x=1;%macro t;%local x;[%symglobl(x)][%symlocal(x)]%mend;%t", "[1][1]");
    // after the macro returns, the local is gone from every table.
    try expectExpand("%macro t;%local x;%let x=5;%mend;%t[%symlocal(x)][%symexist(x)]", "[0][0]");
}

test "GAP-macroqlowcase: %qlowcase lowercases + quotes like %lowcase" {
    try expectExpand("[%qlowcase(ABC Def)]", "[abc def]");
    try expectExpand("%lowcase(ABC)|%qlowcase(ABC)", "abc|abc");
}

test "GAP-macroautocall: %left/%trim/%cmpres + Q-forms" {
    try expectExpand("[%left(   hi)]", "[hi]");
    try expectExpand("[%trim(hi   )x]", "[hix]");
    try expectExpand("[%cmpres(  a    b   c  )]", "[a b c]");
    // no-op on already-clean text; empty arg stays empty
    try expectExpand("[%left()][%trim()][%cmpres()]", "[][][]");
    // Q-forms transform identically and mask & in the RESULT (like %qupcase).
    try expectExpand("%let b=one;[%qcmpres(a   b   %nrstr(&b))]", "[a b &b]");
    try expectExpand("%let z=hi;[%qleft(   &z)][%qtrim(&z   )]", "[hi][hi]");
}

test "GAP-sysrcmacro: %SYSRC expands doc-sourced _IORC_ codes; unsourced mnemonics fail loud" {
    // Language Reference: Concepts-sourced values (Table 23.4 p.599 + worked logs pp.600/603).
    try expectExpand("[%sysrc(_sok)][%sysrc(_DSENOM)][%sysrc( _dsenmr )]", "[0][1230011][1230015]");
    // _DSEMTR/_SENOCHN are named in Table 23.4 but never valued in the doc —
    // fail loud, never guess a return code. Asserted via CAPTURED diagnostics.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    _ = try expand(a, "%sysrc(_dsemtr)", &d);
    try std.testing.expectEqualStrings(
        "ERROR: %SYSRC: no doc-sourced value for _IORC_ mnemonic _dsemtr\n",
        try d.render(),
    );
}

test "GAP-sysrcmacro: %DATATYP/%VERIFY autocall companions" {
    try expectExpand("[%datatyp(123)][%datatyp(-1.5e3)][%datatyp(abc)][%datatyp()]", "[NUMERIC][NUMERIC][CHAR][CHAR]");
    try expectExpand("[%verify(abc,abcdef)][%verify(abz,ab)][%verify(,abc)][%verify(abc,)]", "[0][3][0][1]");
}

test "GAP-macroevalfloat: %eval errors loud on non-integer operand / invalid token (no silent 0)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Non-integer operand in arithmetic: was a silent 0.
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(1.5 + 2.5)", &d1);
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '1.5'\n",
        try d1.render(),
    );
    // `mod` is not a %EVAL operator: was a silent first-operand (10).
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(10 mod 3)", &d2);
    try std.testing.expectEqualStrings(
        "ERROR: %EVAL: invalid operator or operand in '10 mod 3'\n",
        try d2.render(),
    );
    // Invalid token between operands: was a silent first-operand (5).
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(5 foo 3)", &d3);
    try std.testing.expectEqualStrings(
        "ERROR: %EVAL: invalid operator or operand in '5 foo 3'\n",
        try d3.render(),
    );
    // Clean integer %eval records nothing.
    var d4 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("3", try expand(a, "%eval(10 / 3)", &d4));
    try std.testing.expectEqualStrings("", try d4.render());
    // String COMPARES are not arithmetic — no error (QL-C behavior preserved).
    var d5 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("1", try expand(a, "%eval(abc = abc)", &d5));
    try std.testing.expectEqualStrings("", try d5.render());
}

test "NOTE-macroevalnonint: bare non-integer %eval leaf takes the SAME error path as arithmetic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Bare leaf: was a lowercase NOTE; must now be the arithmetic ERROR, value 0.
    var d1 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("0", try expand(a, "%eval(3.5)", &d1));
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '3.5'\n",
        try d1.render(),
    );
    // Arithmetic: identical message, same substituted 0.
    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("0", try expand(a, "%eval(3.5 + 1.2)", &d2));
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '3.5'\n",
        try d2.render(),
    );
    // Integer control: unchanged, no diagnostic.
    var d3 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("7", try expand(a, "%eval(3 + 4)", &d3));
    try std.testing.expectEqualStrings("3", try expand(a, "%eval(10 / 3)", &d3));
    try std.testing.expectEqualStrings("", try d3.render());
}

test "NOTE-puttevalpartial: a %put whose own resolution ERRORs does not print the partial line" {
    // Diagnostics render once at end-of-run, so `%put A=%eval(3.5);` printed
    // `A=0` AHEAD of the non-integer ERROR its own resolution recorded. The
    // 0-substitution is pinned above and stays; the LINE is suppressed — the
    // ERROR stands alone. Captured reporter (D-003): in this channel the line
    // would render as a trailing `NOTE: A=0`, so its absence pins the fix.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put A=%eval(3.5);", &d1);
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '3.5'\n",
        try d1.render(),
    );
    // Same on the pre-existing arithmetic path.
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put A=%eval(3.5+1.2);", &d2);
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '3.5'\n",
        try d2.render(),
    );
    // Controls: a clean %put still prints, and a %put AFTER an errored one is
    // unaffected (suppression is keyed on THIS resolution's diagnostics).
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put A=%eval(3.5);%put B=1;", &d3);
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '3.5'\n" ++
            "NOTE: B=1\n",
        try d3.render(),
    );
}

test "BUG-minoperatoropt: OPTIONS MINOPERATOR gates `in`; un-gated `in` and bare text leaves error like %eval" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // (a) the SYSTEM-option form gates `in`/`#` exactly like %MACRO /
    // minoperator: member and non-member take DIFFERENT branches, through the
    // OPTIONS MINDELIMITER= (a macro without its own inherits the system's).
    try expectExpand(
        "options minoperator mindelimiter=',';" ++
            "%macro g;%if b in a,b,c %then YES;%else NO;%mend;%g",
        "options minoperator mindelimiter=',';YES",
    );
    try expectExpand(
        "options minoperator mindelimiter=',';" ++
            "%macro g;%if q in a,b,c %then YES2;%else NO2;%mend;%g",
        "options minoperator mindelimiter=',';NO2",
    );
    // default (blank) delimiter via the system option; NOMINOPERATOR turns the
    // gate back off (the error path below is then armed again).
    try expectExpand(
        "options minoperator;%macro h;%if b in a b c %then MEM;%else NM;%mend;%h",
        "options minoperator;MEM",
    );
    try expectExpand(
        "options minoperator mindelimiter=',';%macro d(x) / minoperator;" ++
            "%if &x in a,b,c %then M;%else N;%mend;%d(c)",
        "options minoperator mindelimiter=',';M",
    );
    // (b) %IF and %EVAL agree on the same text: an un-gated `in` is the same
    // two ERRORs through both paths (leftover token + bare text leaf).
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro n;%if q in a b c %then T;%else F;%mend;%n", &d1);
    // BUG-macroerrnostop: each %EVAL expression error now also stops the macro
    // (printed p.162 emits the pair), so both errors carry their stop line.
    try std.testing.expectEqualStrings(
        "ERROR: %EVAL: invalid operator or operand in 'q in a b c'\n" ++
            "ERROR: The macro will stop executing.\n" ++
            "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: 'q'\n" ++
            "ERROR: The macro will stop executing.\n",
        try d1.render(),
    );
    // The %EVAL half runs INSIDE a macro too, so the comparison stays
    // apples-to-apples: open code deliberately does not emit the stop line
    // (nothing to unwind), which would otherwise make these differ for a reason
    // that has nothing to do with the verdict being tested.
    var d1b = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro nb;%eval(q in a b c)%mend;%nb", &d1b);
    try std.testing.expectEqualStrings(try d1.render(), try d1b.render()); // identical verdicts
    // NOMINOPERATOR after MINOPERATOR restores the loud default.
    var d1c = diag.Diagnostics.init(a);
    _ = try expand(a, "options minoperator; options nominoperator;%macro n;%if q in a b c %then T;%else F;%mend;%n", &d1c);
    try std.testing.expectEqualStrings(try d1.render(), try d1c.render());
}

test "BUG-ifbaretruthy: a bare non-numeric %if leaf errors like %eval (no silent TRUE); empty leaf stays a silent FALSE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `%if abc` — was silently TRUE at exit 0; now the %eval(abc) ERROR.
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro z;%if abc %then T;%else F;%mend;%z", &d1);
    // BUG-macroerrnostop: inside a macro the error now carries its p.162 twin.
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: 'abc'\n" ++
            "ERROR: The macro will stop executing.\n",
        try d1.render(),
    );
    // `%if 0.0` — float leaf: %eval(0.0) errors, so %if must too (agreement).
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro z;%if 0.0 %then T;%else F;%mend;%z", &d2);
    try std.testing.expectEqualStrings(
        "ERROR: A character operand was found in the %EVAL function or %IF condition where a numeric operand is required: '0.0'\n" ++
            "ERROR: The macro will stop executing.\n",
        try d2.render(),
    );
    // integer leaf / empty leaf / string COMPARE stay silent and branch right.
    var d3 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings(
        "ynF",
        try expand(a, "%macro z;%if 2 %then y;%else n;%mend;%z" ++
            "%macro w;%if 0 %then y;%else n;%mend;%w" ++
            "%let e=;%macro v;%if &e %then T;%else F;%mend;%v", &d3),
    );
    try std.testing.expectEqualStrings("", try d3.render());
    var d4 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("L", try expand(a, "%macro z;%if abc = abc %then L;%else N;%mend;%z", &d4));
    try std.testing.expectEqualStrings("", try d4.render());
}

test "BUG-macroevaldivzero: %eval(5/0) errors loud, no silent 0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(5/0)", &d1);
    try std.testing.expectEqualStrings("ERROR: Division by zero in %EVAL\n", try d1.render());
    // nested inside a larger expression: still caught
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%eval(1 + 5/0)", &d2);
    try std.testing.expectEqualStrings("ERROR: Division by zero in %EVAL\n", try d2.render());
    // normal division is untouched: still 3, no diagnostic
    var d3 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("3", try expand(a, "%eval(6/2)", &d3));
    try std.testing.expectEqualStrings("", try d3.render());
}

test "BUG-macronrbquoteresolve/BUG-macronrquotemissing: %nrbquote/%nrquote resolve THEN mask" {
    // The headline repro (doc-finder tick138): &x resolves, the RESULT is then
    // masked — 9-a, not &x-a. %nrquote is the same execution-time group.
    try expectExpand("%let x=9;[%nrbquote(&x-a)][%nrquote(&x-a)]", "[9-a][9-a]");
    // the resolved-then-masked value survives storage and re-reference
    try expectExpand("%let x=9;%let q=%nrbquote(&x-a);[&q]", "[9-a]");
    // a trigger that SURVIVES resolution (undefined &u) is masked so a later
    // rescan can't re-fire it; it unmasks to a literal & on the way out
    try expectExpand("%let q=%nrbquote(&u-z);[&q]", "[&u-z]");
    // %nrquote no longer warns + drops (was: apparent invocation not resolved)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    const out = try expand(a, "%let x=9;[%nrquote(&x-a)]", &diags);
    try std.testing.expectEqualStrings("[9-a]", out);
    try std.testing.expectEqualStrings("", try diags.render());
}

test "BUG-macropctmask: %-escaped specials fold to literals inside quoting fns" {
    try expectExpand("%let x=%str(50%%);[&x]", "[50%]");
    try expectExpand("%let x=%nrstr(50%%);[&x]", "[50%]");
    try expectExpand("%let x=%str(a%&b);[&x]", "[a&b]");
    // an escaped paren is literal text — the %str still balances, no lexer error
    try expectExpand("%let x=%str(a%(b);[&x]", "[a(b]");
    try expectExpand("%let x=%str(a%)b);[&x]", "[a)b]");
    // the 95% CI title idiom
    try expectExpand("%let t=%str(95%% CI);[&t]", "[95% CI]");
    // a folded % is masked: it can NOT re-fire as a macro trigger when the
    // stored value is rescanned (was: spurious 'macro B/C not resolved' warns)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    const out = try expand(a, "%let x=%str(a%%b%%c);%let y=&x;[&y]", &diags);
    try std.testing.expectEqualStrings("[a%b%c]", out);
    try std.testing.expectEqualStrings("", try diags.render());
}

test "GAP-macroautovars: automatic macro variables are seeded" {
    // &SYSVER constant; &SYSMACRONAME blank in open code / uppercased macro name
    // inside; &SYSINDEX counts invocations begun.
    try expectExpand("[&sysver][&sysmacroname][&sysindex]", "[9.4][][0]");
    try expectExpand("%macro m;[&sysmacroname]%mend;%m", "[M]");
    try expectExpand("%macro a;x%mend;%macro b;y%mend;%a%b[&sysindex]", "xy[2]");
    // nested calls see their own name; the outer name is restored after
    try expectExpand("%macro i;[&sysmacroname]%mend;%macro o;[&sysmacroname]%i[&sysmacroname]%mend;%o", "[O][I][O]");
    // date/time stamps: the shape is fixed whatever today's date is (date9.=9
    // chars, date7.=7, time5.=5, &SYSDAY is a non-blank weekday name)
    try expectExpand("%length(&sysdate9)|%length(&sysdate)|%length(&systime)", "9|7|5");
    try expectExpand("%if &sysday ne %then D;%else N;", "D");
    // %length form: &SYSSCP is multi-word ("LIN X64"), so a bare `%if &sysscp ne`
    // is not a valid macro condition (errors, like %eval — BUG-minoperatoropt).
    try expectExpand("%if %length(&sysscp) %then S;%else N;", "S");
    // an UNKNOWN &SYSxxx warns instead of passing through silently
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    _ = try expand(a, "&sysnosuchvar", &diags);
    try std.testing.expectEqualStrings(
        "WARNING: Apparent symbolic reference SYSNOSUCHVAR not resolved.\n",
        try diags.render(),
    );
    // An undefined ORDINARY &var stays quiet HERE, and that is not an oversight:
    // the free `expand` has no execution callback, so no step ever consumes this
    // text and late binding is still possible for all it knows. It is RECORDED
    // instead, and warned at the step that consumes it — see the
    // CLIN-macrounresolvedsilent test below for both directions.
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "&ordinary", &d2);
    try std.testing.expectEqualStrings("", try d2.render());
}

test "CLIN-macrounresolvedsilent: an unresolved &name warns at the step that CONSUMES it, never before" {
    // Timing is the whole ticket, so the harness reproduces the production
    // handoff rather than approximating it: expandExec flushes each `run;` step,
    // and the callback does what main.zig's interleaveStep -> runExpanded does —
    // tokenize, give the exec->macro queue its LAST chance via `bindStepVars`,
    // and only THEN let this step's CALL SYMPUT publish. That ordering is the
    // reason a same-step reference cannot be rescued (Macro Language Reference
    // printed p.158) while a previous-step one is (printed p.531).
    const Ctx = struct {
        a: std.mem.Allocator,
        d: *diag.Diagnostics,
        s: *Session,
        q: std.StringHashMapUnmanaged([]const u8) = .empty, // stands in for Library.macro_vars
    };
    const H = struct {
        fn step(ctx_p: *anyopaque, text: []const u8) Error!void {
            const c: *Ctx = @ptrCast(@alignCast(ctx_p));
            const toks = lex.tokenize(c.a, text, c.d) catch return;
            // Stand-in for main.zig's `segments`. ONE flush can carry SEVERAL
            // steps (`data a; … data b; … run;`), and bindStepVars runs once per
            // step, after the previous step has executed and published. Emulating
            // that split matters: it is the route that saves the third arm below,
            // and collapsing it into a single bind call is what an unfaithful
            // harness does — it invents a false positive the real CLI never has.
            var start: usize = 0;
            var i: usize = 1;
            while (i <= toks.len) : (i += 1) {
                if (i < toks.len and !(toks[i].tag == .name and
                    eqi(toks[i].text, "data") and toks[i - 1].tag == .semicolon)) continue;
                _ = bindStepVars(c.a, toks[start..i], &c.q, c.d) catch return;
                // exec.zig's CALL SYMPUT, which lands AFTER the step compiled.
                for (toks[start..i]) |t| {
                    if (t.tag != .name or !eqi(t.text, "symput")) continue;
                    try c.q.put(c.a, "v", "bound");
                    try c.s.seedVar("v", "bound");
                    break;
                }
                start = i;
            }
        }
        fn log(a: std.mem.Allocator, src: []const u8) Error![]const u8 {
            const d = try a.create(diag.Diagnostics);
            d.* = diag.Diagnostics.init(a);
            const s = try a.create(Session);
            s.* = Session.init(a, d); // also resets g_unresolved between arms
            const c = try a.create(Ctx);
            c.* = .{ .a = a, .d = d, .s = s };
            _ = try s.expandExec(src, @ptrCast(c), step);
            return d.render();
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // THE TICKET. Nothing can ever bind it, so the consuming step warns.
    try std.testing.expectEqualStrings(
        "WARNING(L1): Apparent symbolic reference NOSUCHVAR not resolved.\n",
        try H.log(a, "data _null_; y = \"&nosuchvar\"; run;"),
    );

    // D-004 / BUG-macrointerleave — THE REGRESSION THIS MUST NOT CAUSE. A prior
    // step's CALL SYMPUT binds the reference, so it must stay SILENT. This is the
    // idiom that took the study meter 0/27 -> 26/27; warning here would be the false
    // positive that makes the whole diagnostic worse than the silence it replaces.
    try std.testing.expectEqualStrings("", try H.log(a,
        "data _null_; call symput(\"v\",\"bound\"); run;\ndata _null_; x = \"&v\"; run;"));

    // The same idiom through the OTHER late-bind route: two steps, ONE `run;`, so
    // the reference is scanned while `v` is still unknown and only `bindStepVars`
    // can save it. Also silent — this is the case that rules out discharging at
    // the flush instead of inside bindStepVars.
    try std.testing.expectEqualStrings("", try H.log(a,
        "data a; call symput(\"v\",\"bound\"); data b; x = \"&v\"; run;"));

    // Printed p.158, the doc's own flagship: CALL SYMPUT in the SAME step is too
    // late — "As this DATA step is tokenized and compiled, the & causes the word
    // scanner to trigger the macro processor ... Because such an entry does not
    // exist, the macro processor generates the warning message."
    try std.testing.expectEqualStrings(
        "WARNING(L1): Apparent symbolic reference V not resolved.\n",
        try H.log(a, "data _null_; call symput(\"v\",\"bound\"); x = \"&v\"; run;"),
    );

    // FALSE-POSITIVE CONTROLS. Post-lex these are indistinguishable from a real
    // reference, which is why the warning is gated on what the SCANNER recorded:
    //   * `a & b` is logical AND — printed p.21 makes a trigger an ampersand
    //     "followed by a nonblank character", so the blank disqualifies it;
    //   * `'AT&T'` is single-quoted — never resolved, never warned (printed p.38);
    //   * `%nrstr(&Stacy)` is masked — printed p.106 says in as many words that
    //     %NRSTR means "the macro processor does not issue warning messages for
    //     unresolvable macro variable references". Doc's own example, verbatim.
    try std.testing.expectEqualStrings("", try H.log(a,
        "data _null_; a=1; b=0; if a & b then put \"and\"; s = 'AT&T'; t = \"%nrstr(Mary&Stacy&Joan Ltd.)\"; run;"));

    // ...and the CONTRAST that proves the control is a real discrimination and not
    // a blanket exemption: printed p.484 lists `if x&y then do;` and
    // `if buyer="Smith&Jones, Inc."` as things SAS DOES warn about. Same token
    // shapes as the line above; only the blank and the quote kind differ.
    try std.testing.expectEqualStrings(
        "WARNING(L1): Apparent symbolic reference Y not resolved.\n" ++
            "WARNING(L1): Apparent symbolic reference JONES not resolved.\n",
        try H.log(a, "data _null_; x=1; y=0; if x&y then put \"trig\"; buyer = \"Smith&Jones, Inc.\"; run;"),
    );
}

test "NOTE-putunresolvedwarn: %PUT warns for a reference it prints unresolved (p.152)" {
    // SAS 9.4 Macro Language: Reference, Fifth Edition, printed p.152 shows the
    // log of exactly this case carrying BOTH halves — the %PUT line with the
    // reference standing verbatim, AND "WARNING: Apparent symbolic reference
    // MACVAR not resolved." We printed only the line, which is what made the
    // whole CALL SYMPUT scope trap read as silent to a reporter: the same
    // program in a DATA step warned correctly, and %PUT — the debugging
    // statement you reach for to find out what went wrong — did not.
    //
    // NO CORPUS FIXTURE: both the %PUT line and the WARNING travel on stderr,
    // and the corpus diffs stdout, so a fixture would be the vacuous 0-byte
    // golden the house rules warn about. `expand` (not a Session) keeps %PUT on
    // the captured channel and resets `g_unresolved` per arm.
    const S = struct {
        fn log(src: []const u8, want: []const u8) !void {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var d = diag.Diagnostics.init(a);
            _ = try expand(a, src, &d);
            try std.testing.expectEqualStrings(want, try d.render());
        }
    };

    // THE TICKET. The warning precedes the line: SAS's word scanner warns when
    // the resolution fails, i.e. before the text is written.
    try S.log("%put A[&zzz];", "WARNING: Apparent symbolic reference ZZZ not resolved.\n" ++
        "NOTE: A[&zzz]\n");

    // A resolved reference stays quiet — the warning is about failure, not about
    // the presence of an `&`.
    try S.log("%let known=ok;%put R[&known];", "NOTE: R[ok]\n");

    // THE SAME FALSE-POSITIVE CONTROLS as the step path, because they run
    // through the SAME `g_unresolved` gate — but every arm here rests on the
    // rule that actually governs MACRO statements (NOTE-putsinglequoteamp):
    //
    //   * `a & b` is not a trigger — Macro Ref printed p.21 defines a macro
    //     trigger as "an ampersand (&) or percent sign (%) followed by a
    //     nonblank character", so the blank disqualifies it;
    //   * `'AT&T'` WARNS — quotation marks are ordinary characters to the
    //     macro processor; masking `&` requires an NR quoting function
    //     (printed p.7: "You must use a macro quoting function to mask the
    //     special characters", about assigning a value containing ampersands
    //     to a macro variable; Table 7.2 printed p.100, `%name &name`:
    //     "%NRSTR, %NRBQUOTE, and %NRQUOTE mask these patterns"; printed
    //     p.342: "In addition, %NRSTR also masks the following characters:
    //     & %"). 85087c38 asserted SILENCE here citing printed p.38 — but
    //     p.38 ("Macro Variable Reference") is the SAS-STATEMENT rule: its
    //     own example is a TITLE statement, i.e. quoted string literals in
    //     compiler-bound text. It does not govern %PUT, and the old arm
    //     passed only because T was never recorded as a trigger — a control
    //     passing by accident (QA F3);
    //   * `%nrstr(&hidden)` is the masking route the rule names, and is
    //     explicitly warning-free (printed p.106). This arm also proves the
    //     scan happens BEFORE unmaskTriggers — one line later the sentinel
    //     is a plain `&` and would have matched.
    try S.log("%put R[a & b];", "NOTE: R[a & b]\n");
    try S.log("%put R['AT&T'];", "WARNING: Apparent symbolic reference T not resolved.\n" ++
        "NOTE: R['AT&T']\n");
    try S.log("%put R[%nrstr(&hidden)];", "NOTE: R[&hidden]\n");

    // The rule cuts both ways (QA F3a): a DEFINED reference RESOLVES inside
    // single quotes in %PUT text, exactly as it does inside double quotes.
    try S.log("%let t=RESOLVED;%put A['AT&t'];", "NOTE: A['ATRESOLVED']\n");
    try S.log("%let t=RESOLVED;%put A[\"AT&t\"];", "NOTE: A[\"ATRESOLVED\"]\n");

    // And the warning no longer rides NAME HISTORY (QA F3b): before the fix
    // a single-quoted reference warned iff the same name had failed ELSEWHERE
    // first. Same text, same outcome, either order.
    try S.log("%put P2['AT&TT'];", "WARNING: Apparent symbolic reference TT not resolved.\n" ++
        "NOTE: P2['AT&TT']\n");
    try S.log("%put P0[&tt];%put P2['AT&TT'];", "WARNING: Apparent symbolic reference TT not resolved.\n" ++
        "NOTE: P0[&tt]\n" ++
        "WARNING: Apparent symbolic reference TT not resolved.\n" ++
        "NOTE: P2['AT&TT']\n");

    // An undefined automatic (&SYS*) is warned EAGERLY by resolveAmpRun and
    // never recorded, so it must warn exactly ONCE, not twice.
    try S.log("%put R[&sysnosuchauto];", "WARNING: Apparent symbolic reference SYSNOSUCHAUTO not resolved.\n" ++
        "NOTE: R[&sysnosuchauto]\n");

    // `%put &=name;` (the name-and-value debugging form) resolves through the
    // same path, so an unknown name warns there too instead of printing a bare
    // `NAME=&name` with nothing to say why.
    try S.log("%put &=nope;", "WARNING: Apparent symbolic reference NOPE not resolved.\n" ++
        "NOTE: NOPE=&nope.\n");
}

test "GAP-macroautovars: &SYSERR is 0 clean and flips sticky after a step error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Fake step-runner: a flushed step containing "bad" records a step error
    // (the real CLI callback does the same via runExpanded), else clean.
    const Fake = struct {
        fn run(ctx: *anyopaque, text: []const u8) Error!void {
            const d: *diag.Diagnostics = @ptrCast(@alignCast(ctx));
            if (std.mem.indexOf(u8, text, "bad") != null)
                try d.report(.err, 0, "mock step error", .{});
        }
    };
    // clean run: %if &syserr=0 takes the true branch (the clinical idiom)
    var d1 = diag.Diagnostics.init(a);
    var s1 = Session.init(a, &d1);
    const clean = try s1.expandExec(
        "data _null_; x=1; run;\n%if &syserr=0 %then CLEAN;%else ERR;",
        &d1,
        Fake.run,
    );
    try std.testing.expectEqualStrings("\nCLEAN", clean);
    // after a step error the branch flips (and stays flipped — sticky)
    var d2 = diag.Diagnostics.init(a);
    var s2 = Session.init(a, &d2);
    const errored = try s2.expandExec(
        "data bad; run;\n%if &syserr=0 %then CLEAN;%else ERR;\n%if &syserr ne 0 %then ABORT;",
        &d2,
        Fake.run,
    );
    try std.testing.expectEqualStrings("\nERR\nABORT", errored);
}

test "GAP-macroautofeatures: F5 seeds &SYSSCPL/&SYSCC/&SYSRC/&SYSLAST/&SYSNOBS" {
    // sysscpl is platform-dependent → assert non-empty; the rest are fixed.
    try expectExpand("%if &sysscpl ne %then S;%else N;[&syscc][&sysrc][&syslast][&sysnobs]", "S[0][0][_NULL_][0]");
}

test "GAP-macroautofeatures: &SYSCC is 0 clean and flips sticky after a step error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Fake = struct {
        fn run(ctx: *anyopaque, text: []const u8) Error!void {
            const d: *diag.Diagnostics = @ptrCast(@alignCast(ctx));
            if (std.mem.indexOf(u8, text, "bad") != null)
                try d.report(.err, 0, "mock step error", .{});
        }
    };
    var d1 = diag.Diagnostics.init(a);
    var s1 = Session.init(a, &d1);
    const clean = try s1.expandExec(
        "data _null_; x=1; run;\n%if &syscc=0 %then CLEAN;%else ERR;",
        &d1,
        Fake.run,
    );
    try std.testing.expectEqualStrings("\nCLEAN", clean);
    var d2 = diag.Diagnostics.init(a);
    var s2 = Session.init(a, &d2);
    const errored = try s2.expandExec(
        "data bad; run;\n%if &syscc=0 %then CLEAN;%else ERR;",
        &d2,
        Fake.run,
    );
    try std.testing.expectEqualStrings("\nERR", errored);
}

test "GAP-macroautofeatures: %SYSGET reads the environment, warns when unset" {
    // PATH is effectively always set; its value is machine-specific → assert
    // only non-empty (via %length).
    try expectExpand("%if %length(%sysget(PATH)) > 0 %then SET;%else EMPTY;", "SET");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // an unset variable: empty result + a proper WARNING (SAS warns)
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let v=%sysget(OPENSAS_NOSUCH_ENVVAR_7Q);[&v]", &d1);
    try std.testing.expectEqualStrings(
        "WARNING: %SYSGET: environment variable OPENSAS_NOSUCH_ENVVAR_7Q is not defined\n",
        try d1.render(),
    );
    // the environ-block parser: exact-value lookup, key match is exact
    try std.testing.expectEqualStrings("/home/x", envScan("A=1\x00HOME=/home/x\x00H=/nope\x00", "HOME").?);
    try std.testing.expect(envScan("A=1\x00", "HOME") == null);
    try std.testing.expect(envScan("HOME\x00", "HOME") == null); // no '=' → skipped
}

test "GAP-macroautofeatures: %put _user_/_local_/_automatic_/_all_ dump the table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // _user_ in open code = the user globals (automatics excluded)
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%global g;%let g=1;%put _user_;", &d1);
    try std.testing.expectEqualStrings("NOTE: GLOBAL G 1\n", try d1.render());
    // _local_ inside a macro lists params and auto-locals with their values.
    // Scope column is the OWNING MACRO'S NAME, not the word LOCAL — printed p.419,
    // _LOCAL_: "The scope is the name of the currently executing macro"
    // (NOTE-userscopename).
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m(x);%let y=2;%put _local_;%mend;%m(1)", &d2);
    const r2 = try d2.render();
    try std.testing.expect(std.mem.indexOf(u8, r2, "NOTE: M X 1\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, r2, "NOTE: M Y 2\n") != null);
    // _automatic_ dumps the SYS* autos (date/time values vary → spot-check)
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put _automatic_;", &d3);
    const r3 = try d3.render();
    try std.testing.expect(std.mem.indexOf(u8, r3, "NOTE: AUTOMATIC SYSERR 0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, r3, "NOTE: AUTOMATIC SYSSCPL ") != null);
    try std.testing.expect(std.mem.indexOf(u8, r3, "NOTE: AUTOMATIC SYSLAST _NULL_\n") != null);
    // _all_ = both groups
    var d4 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let u=9;%put _all_;", &d4);
    const r4 = try d4.render();
    try std.testing.expect(std.mem.indexOf(u8, r4, "NOTE: GLOBAL U 9\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, r4, "NOTE: AUTOMATIC SYSVER 9.4\n") != null);
    // plain %put text and a keyword mixed into text are unchanged
    var d5 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put hello;%put see _user_ here;", &d5);
    try std.testing.expectEqualStrings("NOTE: hello\nNOTE: see _user_ here\n", try d5.render());
}

test "BUG-symputscope: CALL SYMPUT lands in the closest NONEMPTY symbol table (p.77 rule 1)" {
    // The corpus fixture (macroedge_symput_scopelocal) pins the VALUES, which is
    // what a program can observe; the SCOPE LABEL only ever appears in `%put
    // _user_`, i.e. on stderr, which the corpus does not diff. So the
    // classification is asserted here, on the captured diagnostics reporter.
    //
    // `symputLocal` is what exec.zig's CALL SYMPUT calls; driving it from the
    // step-boundary callback is exactly where it runs for real (expandExec ->
    // interleaveStep -> the DATA step -> back here), without dragging exec.zig in.
    const H = struct {
        // Both halves of the real pair: exec.zig asks `symputLocal` first, and on
        // false writes Library.macro_vars, which main.zig's drain then pushes back
        // through `seedVar` (a global). Emulated here so the false branch is a
        // genuine GLOBAL and not just an absent variable.
        fn step(ctx: *anyopaque, _: []const u8) Error!void {
            const s: *Session = @ptrCast(@alignCast(ctx));
            if (!try symputLocal("myvar", "a token", .default)) try s.seedVar("myvar", "a token");
        }
        fn run(a: std.mem.Allocator, d: *diag.Diagnostics, src: []const u8) Error![]const u8 {
            const s = try a.create(Session);
            s.* = Session.init(a, d);
            _ = try s.expandExec(src, @ptrCast(s), step);
            return d.render();
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // ENV1 (printed p.78): parameterized macro, complete DATA step. PARAM1 makes
    // the local table nonempty => MYVAR is LOCAL, and `%put _user_` in open code
    // writes NOTHING because no global was created.
    var d1 = diag.Diagnostics.init(a);
    const r1 = try H.run(a, &d1, "%macro env1(param1);data _null_;run;%put _user_;%mend;%env1(10)%put _user_;");
    // The scope column is the OWNING MACRO'S NAME (NOTE-userscopename); printed
    // p.79 prints this exact pair, `ENV1 MYVAR1 a token` / `ENV1 PARAM1 10`. It
    // was the word LOCAL here until then, which is why the placement it pins now
    // reads directly off the line: the frame is NAMED, not merely "some local".
    try std.testing.expectEqualStrings("NOTE: ENV1 MYVAR a token\nNOTE: ENV1 PARAM1 10\n", r1);

    // ENV3 (printed p.83): NO parameters => the local table is empty => the
    // variable goes to the closest nonempty table, the global one. Same shape and
    // same `run;` placement as ENV1: emptiness alone decides.
    var d3 = diag.Diagnostics.init(a);
    const r3 = try H.run(a, &d3, "%macro env3;data _null_;run;%mend;%env3%put _user_;");
    try std.testing.expectEqualStrings("NOTE: GLOBAL MYVAR a token\n", r3);

    // Open code: no local table at all => global, i.e. the pre-existing behaviour.
    var d0 = diag.Diagnostics.init(a);
    const r0 = try H.run(a, &d0, "data _null_;run;%put _user_;");
    try std.testing.expectEqualStrings("NOTE: GLOBAL MYVAR a token\n", r0);

    // "the CLOSEST nonempty symbol table": INNER's frame is empty, so the
    // variable belongs to OUTER's and dies with OUTER, not with INNER — and the
    // scope column now SAYS OUTER, so this pins the frame identity rather than
    // just "it is local to something".
    var dn = diag.Diagnostics.init(a);
    const rn = try H.run(a, &dn, "%macro inner;data _null_;run;%mend;" ++
        "%macro outer(p);%inner%put _user_;%mend;%outer(9)%put _user_;");
    try std.testing.expectEqualStrings("NOTE: OUTER MYVAR a token\nNOTE: OUTER P 9\n", rn);
}

test "BUG-symputnoupdate: CALL SYMPUT UPDATES an existing enclosing variable (p.301)" {
    // Macro Language Reference printed p.301: "If macro-variable exists in any
    // enclosing scope, macro-variable is updated. If macro-variable does not
    // exist, SYMPUT creates it." The corpus fixture (macroedge_symput_update)
    // pins the VALUES a program can observe; WHICH SCOPE the value landed in is
    // only ever visible through `%put _user_`, i.e. stderr, which the corpus does
    // not diff — so the classification is asserted here, on the captured reporter.
    const H = struct {
        // Same faithful pair as the p.77 test above: exec.zig asks `symputLocal`
        // first and, on false, writes Library.macro_vars, which main.zig's drain
        // pushes back through `seedVar` — so the false branch is a real GLOBAL.
        fn step(ctx: *anyopaque, _: []const u8) Error!void {
            const s: *Session = @ptrCast(@alignCast(ctx));
            if (!try symputLocal("gv", "a token", .default)) try s.seedVar("gv", "a token");
        }
        fn run(a: std.mem.Allocator, d: *diag.Diagnostics, src: []const u8) Error![]const u8 {
            const s = try a.create(Session);
            s.* = Session.init(a, d);
            _ = try s.expandExec(src, @ptrCast(s), step);
            return d.render();
        }
    };
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // THE TICKET, and printed p.152's prescribed remedy: %GLOBAL inside a
    // PARAMETERIZED macro (non-empty local table). GV exists in an enclosing
    // scope, so it is UPDATED there — it must survive as GLOBAL, not as the dead
    // local shadow rule 1 alone would have created.
    var d1 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings(
        "NOTE: GLOBAL GV a token\n",
        try H.run(a, &d1, "%macro m(p);%global gv;data _null_;run;%mend;%m(1)%put _user_;"),
    );

    // A pre-existing global %LET is likewise updated in place, not shadowed.
    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings(
        "NOTE: GLOBAL GV a token\n",
        try H.run(a, &d2, "%let gv=OLD;%macro m(p);data _null_;run;%mend;%m(1)%put _user_;"),
    );

    // "the most local symbol table in which it exists": OUTER owns GV, so INNER's
    // symput writes OUTER's copy even though INNER's own frame is non-empty.
    var d3 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings(
        "NOTE: OUTER GV a token\nNOTE: OUTER P 9\n",
        try H.run(a, &d3, "%macro inner(q);data _null_;run;%mend;" ++
            "%macro outer(p);%local gv;%inner(7)%put _user_;%mend;%outer(9)"),
    );

    // THE GUARD against over-correcting: a name that exists NOWHERE is still
    // CREATED by p.77 rule 1, i.e. local to the parameterized macro and gone in
    // open code. Nothing global is left behind.
    var d4 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings(
        "",
        try H.run(a, &d4, "%macro m(p);data _null_;run;%mend;%m(1)%put _user_;"),
    );
}

test "NOTE-userscopename: %put _user_ names the OWNING MACRO as the scope, not LOCAL" {
    // NO CORPUS FIXTURE, deliberately: this divergence has no DATA-step-visible
    // consequence at all — the scope column exists only in `%put _user_`/`_local_`
    // output, which goes to stderr, and the corpus diffs stdout. A fixture would
    // be the exact 0-byte-golden vacuous pass the house rules warn about. The
    // captured diagnostics reporter is the only honest place to assert it, and
    // `expand` (not a Session) keeps %PUT on that channel.
    //
    // SAS 9.4 Macro Language: Reference, Fifth Edition, printed p.419, "%PUT
    // Macro Statement": _USER_ "lists user-generated global and local macro
    // variables. The scope is identified either as GLOBAL, or as the name of the
    // macro in which the macro variable is defined." Placement is untouched here
    // — BUG-symputscope owns that and its own test/fixture still pin it.
    const S = struct {
        fn log(src: []const u8, want: []const u8) !void {
            var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
            defer arena.deinit();
            const a = arena.allocator();
            var d = diag.Diagnostics.init(a);
            _ = try expand(a, src, &d);
            try std.testing.expectEqualStrings(want, try d.render());
        }
    };

    // printed p.421, Example 3 — reproduced verbatim, values and ORDER. Details on
    // p.419: "listed in order from the current local macro variables outward to
    // the global macro variables". A flat sort of the rendered lines put GLOBAL
    // first (G < L), i.e. backwards.
    try S.log(
        "%let foot=Preliminary Data;%macro myprint(name);%put _user_;%mend;%myprint(consumer)",
        "NOTE: MYPRINT NAME consumer\nNOTE: GLOBAL FOOT Preliminary Data\n",
    );
    // Same page: "The result ... does not list the macro variable NAME because it
    // was local to MYPRINT and ceased to exist when MYPRINT finished execution."
    try S.log(
        "%let foot=Preliminary Data;%macro myprint(name);%mend;%myprint(consumer)%put _user_;",
        "NOTE: GLOBAL FOOT Preliminary Data\n",
    );
    // printed p.170: TOTINV — a %GLOBAL declared inside the macro still reports
    // GLOBAL, so the column tracks the OWNING TABLE and not "was I in a macro".
    try S.log(
        "%macro totinv(var);%global macvar;%let macvar=1240800;%put _USER_;%mend;%let trace=ON;%totinv(price)",
        "NOTE: TOTINV VAR price\nNOTE: GLOBAL MACVAR 1240800\nNOTE: GLOBAL TRACE ON\n",
    );
    // Nested frames: innermost first, then outward, then global. Each carries its
    // OWN macro's name — one shared "LOCAL" could not have distinguished them.
    try S.log(
        "%let g=0;%macro inner(q);%put _user_;%mend;%macro outer(p);%inner(9)%mend;%outer(1)",
        "NOTE: INNER Q 9\nNOTE: OUTER P 1\nNOTE: GLOBAL G 0\n",
    );
    // _LOCAL_ is "the currently executing macro" only (printed p.419-420, and
    // Figure 19.1 labels _LOCAL_ "(current macro only)") — the enclosing OUTER's P
    // is NOT listed, though _USER_ above lists it.
    try S.log(
        "%let g=0;%macro inner(q);%put _local_;%mend;%macro outer(p);%inner(9)%mend;%outer(1)",
        "NOTE: INNER Q 9\n",
    );
    // _GLOBAL_ and _AUTOMATIC_ say GLOBAL/AUTOMATIC as before — printed p.419
    // fixes those two words, and only the local column ever named a macro.
    try S.log("%macro m(p);%global g;%let g=1;%put _global_;%mend;%m(2)", "NOTE: GLOBAL G 1\n");
    // A macro variable %LOCAL'd but never assigned still belongs to the frame:
    // "Macro variables with null values show only the scope and name" (p.419), so
    // the trailing space before the empty value is SAS's, not an artefact.
    try S.log("%macro m;%local e;%put _local_;%mend;%m", "NOTE: M E \n");
    // Case: the frame carries the macro's name UPPERCASED, however it was called.
    try S.log("%macro MiXeD(p);%put _local_;%mend;%mixed(7)", "NOTE: MIXED P 7\n");
}

test "GAP-macrosymdel: %symdel deletes macro vars (warn unless NOWARN)" {
    try expectExpand("%let g=1;%symdel g;[%symexist(g)]", "[0]");
    try expectExpand("%let a=1;%let b=2;%symdel a b;[%symexist(a)%symexist(b)]", "[00]");
    // comma-separated list and the /nowarn option
    try expectExpand("%let a=1;%symdel a,b / nowarn;[%symexist(a)][%symexist(b)]", "[0][0]");
    // the leftover argument text no longer corrupts the parse (tick138 repro)
    try expectExpand("%let g=1;%symdel g;data ok;", "data ok;");
    // deleting a var a macro uses is visible immediately
    try expectExpand("%macro m(v);%symdel &v;%mend;%let z=5;%m(z)[%symexist(z)]", "[0]");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // a missing var warns …
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%symdel nosuch;", &d1);
    try std.testing.expectEqualStrings(
        "WARNING: apparent attempt to delete macro variable NOSUCH failed — variable not found\n",
        try d1.render(),
    );
    // … unless NOWARN
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%symdel nosuch / nowarn;", &d2);
    try std.testing.expectEqualStrings("", try d2.render());
}

test "F10 symbol-table diagnostics: symdel-automatic / %global-of-local / %let name / MINDELIMITER= fail loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 1. %SYMDEL of an AUTOMATIC: SAS protects automatics — &SYSDATE9 must
    // survive (was really deleted; every later reference silently unresolved).
    var d1 = diag.Diagnostics.init(a);
    const o1 = try expand(a, "%symdel sysdate9;[&sysdate9]", &d1);
    const r1 = try d1.render();
    try std.testing.expect(std.mem.indexOf(u8, r1, "ERROR: The automatic macro variable SYSDATE9 cannot be deleted (%SYMDEL)\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, r1, "not resolved") == null); // value intact
    try std.testing.expect(std.mem.indexOf(u8, o1, "&sysdate9") == null); // still resolves
    // a USER variable still deletes cleanly (no false protection). The sys*
    // prefix is the automatic classifier (dumpPutVars precedent: SAS reserves
    // the prefix), so a user-created sys* name is protected too — no real
    // program names one.
    try expectExpand("%let mine=1;%symdel mine;[%symexist(mine)]", "[0]");

    // 2. %GLOBAL of a name that is already LOCAL errors (was a silent no-op).
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m;%local x;%let x=1;%global x;%mend;%m", &d2);
    try std.testing.expectEqualStrings("ERROR: Attempt to %GLOBAL a name (X) which exists in a local environment\n", try d2.render());
    // PRESERVE: the %global-first result-var idiom and idempotent %global — clean.
    var c2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro m;%global y;%let y=1;%mend;%m%global g;%global g;", &c2);
    try std.testing.expectEqualStrings("", try c2.render());

    // 3. Invalid / over-length %let names error (were silently accepted, stored
    // but unreferenceable). The indexed-name idiom still resolves + assigns.
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let this_name_is_way_way_too_long_for_sas=1;", &d3);
    try std.testing.expectEqualStrings("ERROR: %LET: 'this_name_is_way_way_too_long_for_sas' is not a valid macro variable name (1–32 chars, letter/underscore start)\n", try d3.render());
    var d4 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let 1bad=2;", &d4);
    try std.testing.expectEqualStrings("ERROR: %LET: '1bad' is not a valid macro variable name (1–32 chars, letter/underscore start)\n", try d4.render());
    // PRESERVE: the indexed-name idiom resolves and assigns (auto-locals, so
    // referenced INSIDE the macro — BUG-macrobareletscope).
    try expectExpand("%macro m;%do i=1 %to 2;%let vart_&i. = v&i;%end;[&vart_1][&vart_2]%mend;%m", "[v1][v2]");

    // 4. MINDELIMITER= takes ONE character — both the OPTIONS-statement and the
    // %macro-option sites error on multi-char (was: first byte kept silently).
    var d5 = diag.Diagnostics.init(a);
    _ = try expand(a, "options mindelimiter='xyz';", &d5);
    try std.testing.expectEqualStrings("ERROR: MINDELIMITER= requires a single character, got 'xyz'\n", try d5.render());
    var d6 = diag.Diagnostics.init(a);
    _ = try expand(a, "%macro d / minoperator mindelimiter='ab';%mend;", &d6);
    try std.testing.expectEqualStrings("ERROR: MINDELIMITER= requires a single character, got 'ab'\n", try d6.render());
    // PRESERVE: a single-char delimiter still gates `in` (end-to-end behavior
    // is pinned by macro_minoperator_opt / macro_in_operator).
    try expectExpand("options minoperator mindelimiter=',';%macro g;%if b in a,b,c %then Y;%else N;%mend;%g", "options minoperator mindelimiter=',';Y");
}

test "F12 automatics fidelity: trimmed &SYSDAY, %put &=name, honest SYSNCPU/SYSUSERID/SYSHOSTNAME" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // &SYSDAY is the trimmed day name — DOWNAME.'s blank pad to width 9 was an
    // artefact of the format route and leaked into text uses. Date-independent:
    // a trimmed value equals its own %trim.
    try expectExpand("%if %length(&sysday) = %length(%trim(&sysday)) %then T;%else F;", "T");
    // `%put &=name;` — the name-and-value form (was literal passthrough).
    var d1 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let x=5;%put &=x;", &d1);
    try std.testing.expectEqualStrings("NOTE: X=5\n", try d1.render());
    var d2 = diag.Diagnostics.init(a);
    _ = try expand(a, "%let a=1;%let b=2;%put &=a &=b;", &d2);
    try std.testing.expectEqualStrings("NOTE: A=1 B=2\n", try d2.render());
    // an unresolved &= name stays verbatim + loud (never a silently blank value)
    var d3 = diag.Diagnostics.init(a);
    _ = try expand(a, "%put &=sysnosuch;", &d3);
    try std.testing.expect(std.mem.indexOf(u8, try d3.render(), "not resolved") != null);
    // SYSNCPU/SYSUSERID/SYSHOSTNAME are seeded ONLY when the host honestly
    // supplies the fact — the assertion mirrors the seed condition, and the
    // value must BE the host's value (never a constant).
    if (std.Thread.getCpuCount()) |_| {
        try expectExpand("%if &sysncpu >= 1 %then C;%else N;", "C");
    } else |_| {}
    if (envValue(a, "USER")) |u| {
        var d4 = diag.Diagnostics.init(a);
        const got = try expand(a, "[&sysuserid]", &d4);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "[{s}]", .{u}), got);
    }
    if (envValue(a, "HOSTNAME")) |h| {
        var d5 = diag.Diagnostics.init(a);
        const got = try expand(a, "[&syshostname]", &d5);
        try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "[{s}]", .{h}), got);
    }
    // Unsourceable automatics stay loud — a guessed constant is the
    // BUG-syslastrefresh trap, worse than no value.
    var d6 = diag.Diagnostics.init(a);
    _ = try expand(a, "&sysvlong", &d6);
    try std.testing.expect(std.mem.indexOf(u8, try d6.render(), "not resolved") != null);
}

test "BUG-sysfuncmissingdot: %sysfunc maps bare `.`/`.A`–`.Z` to numeric missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // `.` is a numeric missing → missing(.) = 1 (was 0: kept as char ".").
    var d1 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("1", try expand(a, "%sysfunc(missing(.))", &d1));
    // Special missing .a → 1.
    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("1", try expand(a, "%sysfunc(missing(.a))", &d2));
    // Non-missing control: 5 → 0.
    var d3 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("0", try expand(a, "%sysfunc(missing(5))", &d3));
    // n()/nmiss()/sum() over a `.` arg: counts/skips the missing, NO bogus
    // "Invalid numeric data" NOTE (was emitted for the char ".").
    var d4 = diag.Diagnostics.init(a);
    try std.testing.expectEqualStrings("2", try expand(a, "%sysfunc(n(1,.,3))", &d4));
    try std.testing.expectEqualStrings("4", try expand(a, "%sysfunc(sum(1,.,3))", &d4));
    try std.testing.expectEqualStrings("", try d4.render());
}
