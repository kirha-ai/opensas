//! PROC SQL — a small query engine over datasets in the `Library`.
//!
//! Supported: `select [distinct] <*|items> from T [inner|left join T2 on c]
//! [where c] [group by … [having c]] [order by …]`, items being a (possibly
//! `t.`-qualified) column, `col as alias`, an aggregate `count/sum/avg/min/max
//! (col|*) [as alias]`, a `case when … then … [else …] end`, `coalesce(…)`, or any
//! arithmetic expression (a later item may reference an earlier one via `calculated`);
//! `select … <union|intersect|except> [all] select … [order by …]`; and `create table N as <select>`
//! (registers N for a later DATA step). HAVING may reference a SELECT alias or a CASE.
//! WHERE may contain a scalar or `in (…)` subquery. A bare `select` prints a plain report.
//!
//! WHERE/ON reuse the DATA-step expression stack (parser_expr + eval): each row is
//! loaded into a PDV and the condition evaluated. Joins, aggregates, grouping, and
//! subquery substitution are SQL-specific and handled here.
//!
//! Joins fold left-to-right over any number of tables (inner / left / cross, the
//! last also written as a comma); columns may be referenced qualified (`a.id`) or,
//! when unambiguous, bare (`x` finds `a.x`).
//!
//! ponytail: no RIGHT/FULL join; a computed column's type follows its first row's
//! value (a CASE its first THEN literal); an aggregate inside an expression needs a
//! GROUP BY to be computed over a group; an ambiguous bare column picks the first
//! match; set operators fold left-to-right
//! (each dedups unless `ALL`), not by SAS's INTERSECT-binds-tighter precedence; the
//! bare-select report is a simple aligned listing, not SAS's format.
//!
//! CREATE TABLE (…) integrity constraints (`[constraint name] primary key(…) /
//! unique(…) / check(…) / foreign key(…) references …`, plus the column-level
//! `not null` / `primary key` / `unique` / `check(…)` / `references …` forms) are
//! parsed as constraints — never as phantom columns — and enforced per row on
//! INSERT/UPDATE: a violating row is rejected with an ERROR (BUG-sqlconstraints).
//! FOREIGN KEY is enforced child-side only (an inserted/updated value must exist
//! in the referenced table); parent-side RESTRICT is not enforced.

const std = @import("std");
const lex = @import("lexer.zig");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const Value = @import("value.zig").Value;
const Dataset = @import("dataset.zig").Dataset;
const Column = @import("dataset.zig").Column;
const Library = @import("exec.zig").Library;
const Pdv = @import("pdv.zig").Pdv;
const missingOf = @import("pdv.zig").missingOf;
const sasParseFloat = @import("pdv.zig").sasParseFloat;
const VarType = @import("pdv.zig").VarType;
const pe = @import("parser_expr.zig");
const eval = @import("eval.zig");
const functions = @import("functions.zig");
const io = @import("io.zig");
const format = @import("format.zig");
const proc = @import("proc.zig"); // cmpColl — THE one collation-aware Value compare (NOTE-collationduplicated)
const dsfns = @import("dsfns.zig"); // libref dir lookup — DROP TABLE's on-disk unlink

const Token = lex.Token;

// `variance` (not `var` — Zig keyword) is SQL VAR; `std`/`stderr`/… are the
// summary statistic aggregates (GAP-sqlstataggs). FREQ aliases N; PRT stays
// unimplemented (needs the t-distribution CDF) and still fails loud.
const AggFn = enum { count, sum, avg, min, max, n, nmiss, std, variance, stderr, cv, css, uss, range, median, t, sumwgt };

const Item = struct {
    agg: ?AggFn = null,
    agg_star: bool = false, // count(*)
    agg_distinct: bool = false, // count(distinct …)
    agg_arg: ?[]const Token = null, // aggregate over a compound expr, e.g. sum(price*qty)
    col: ?[]const u8 = null, // aggregate argument column, or a plain selected column
    alias: ?[]const u8 = null,
    case_toks: ?[]const Token = null, // `case when … end` — evaluated per row
    expr_toks: ?[]const Token = null, // any other expression (arithmetic, coalesce, calculated)
    is_star: bool = false, // a `*` / `alias.*` item in a multi-item SELECT list (ISS-sqlaliasstar)
    star_qual: ?[]const u8 = null, // the `alias` in `alias.*`; null → unqualified `*` (all columns)
    // trailing SELECT column-attribute modifiers `format=`/`informat=`/`label=`/
    // `length=` (BUG-sqlselectmodifier, BUG-sqlselectlength) — consumed by
    // parseItem, threaded onto the OutCol.
    format: ?[]const u8 = null,
    informat: ?[]const u8 = null,
    label: ?[]const u8 = null,
    length: ?usize = null,
};

/// An ORDER BY key. `idx` (a pre-resolved 0-based output-column index) is set for
/// `ORDER BY <n>` (positional) and `ORDER BY <agg>` (matched to a SELECT item);
/// `case_toks`/`expr_toks` hold a `case … end` or a bare expression (`10-x`,
/// `abs(x)`, `a+b`) evaluated per output row at sort time (BUG-sqlorderexpr);
/// otherwise `col` names the column, resolved against the output at sort time.
const Order = struct { col: []const u8 = "", desc: bool = false, idx: ?usize = null, case_toks: ?[]const Token = null, expr_toks: ?[]const Token = null };

/// One joined-in table after the first: how it's joined and (for inner/left) the
/// ON condition. `cross` (also plain `,`) has no condition — a Cartesian product.
const JoinStep = struct { kind: enum { inner, left, right, full, cross }, table: []const u8, alias: ?[]const u8 = null, on: ?[]const Token, from_sub: ?[]const Token = null, opts: ?[]const Token = null }; // from_sub: `join (SELECT …) alias` inline view, materialized in buildJoin — mirrors Query.from_sub (GH#14). opts: a `join T(where=/keep=/…)` dataset-option list applied to T (GH#33)

/// One parsed integrity constraint (BUG-sqlconstraints). Column- and table-level
/// forms both land here; enforcement is per-row on INSERT/UPDATE
/// (violatesConstraint). FOREIGN KEY is enforced child-side only (a value must
/// exist in the referenced table); parent-side RESTRICT on UPDATE/DELETE of a
/// referenced row is NOT enforced (ponytail: no fixture needs it — add if one does).
const Constraint = struct {
    kind: enum { pk, unique, not_null, check, fk },
    cols: []const []const u8 = &.{}, // pk/unique key columns; not_null: the one column; fk: child columns
    pred: []const Token = &.{}, // check ( expr ) predicate tokens
    ref_table: []const u8 = "", // fk: referenced table
    ref_cols: []const []const u8 = &.{}, // fk: referenced columns (empty → the parent's PRIMARY KEY)
};

// Fixed-capacity process-global registry, pointer-keyed, no allocator and no
// free. A lookup only ever COMPARES the pointer, never dereferences it.
//
// BUG-sqlconsleak: this used to be append-only for the life of the process, and
// the old note here argued that stale entries were harmless because a re-created
// table gets a fresh Dataset pointer. That argument only covered CORRECTNESS, and
// only while the prior arena is alive; it said nothing about CAPACITY, which is
// the half that bites — the slots filled up and a later program got "too many
// constrained tables" for tables that earlier, unrelated programs had created.
// `pruneConstraints` below now bounds the registry by what is actually LIVE, so
// the staleness argument is no longer load-bearing and is not restated: a stale
// entry cannot survive into a later run to be reasoned about at all.
var g_cons: [256]struct { ds: *Dataset, cons: []const Constraint } = undefined;
var g_cons_len: usize = 0;

/// BUG-sqlconsleak — bound the registry by the LIVE library. Drops every entry
/// that can no longer be reached:
///   - its Dataset is not in `lib` (a PRIOR RUN's table — wasm calls
///     `main.interpret` many times per module load and each run builds a fresh
///     Library — or one DROPped/deleted since), and
///   - it is superseded by a later entry for the same Dataset. `constraintsOf`
///     reads the newest match, so the older ones are already dead weight; ALTER
///     TABLE ADD CONSTRAINT re-registers the whole merged list every time.
/// Pointers are only compared, never dereferenced, so an entry left over from a
/// freed arena is safe to inspect here.
///
/// Called from `run`, this file's only entry point, so there is ONE reset and it
/// lives with the global it resets — no second list for anyone to forget.
/// ponytail: per STEP, not per statement. A single `proc sql;` that creates and
/// drops more than 256 constrained tables without ever hitting `quit;` still
/// reports the cap; move the call into the statement loop if one ever does.
fn pruneConstraints(lib: *const Library) void {
    var keep: usize = 0;
    for (g_cons[0..g_cons_len], 0..) |e, i| {
        var live = false;
        for (lib.sets.items) |ds| if (ds == e.ds) {
            live = true;
            break;
        };
        if (!live) continue;
        var superseded = false;
        for (g_cons[i + 1 .. g_cons_len]) |later| if (later.ds == e.ds) {
            superseded = true;
            break;
        };
        if (superseded) continue;
        g_cons[keep] = e; // keep <= i always, so this never clobbers an unread entry
        keep += 1;
    }
    g_cons_len = keep;
}

fn registerConstraints(ds: *Dataset, cons: []const Constraint, diags: *diag.Diagnostics) void {
    if (g_cons_len == g_cons.len) {
        diags.report(.err, 0, "PROC SQL: too many constrained tables (limit {d}); constraints on {s} not enforced", .{ g_cons.len, ds.name }) catch {};
        return;
    }
    g_cons[g_cons_len] = .{ .ds = ds, .cons = cons };
    g_cons_len += 1;
}

/// The constraints registered for exactly this Dataset, most recent first.
fn constraintsOf(ds: *Dataset) ?[]const Constraint {
    var i = g_cons_len;
    while (i > 0) {
        i -= 1;
        if (g_cons[i].ds == ds) return g_cons[i].cons;
    }
    return null;
}

const Query = struct {
    star: bool = false,
    distinct: bool = false, // SELECT DISTINCT → dedup output rows
    items: []Item = &.{},
    table: []const u8 = "", // first FROM table
    alias: ?[]const u8 = null, // its `from T [as] X` alias, for correlated refs (X.col)
    from_sub: ?[]const Token = null, // `from (SELECT …)` derived table — materialized at exec (BUG-sqlderivedtable)
    from_opts: ?[]const Token = null, // `from T(where=/keep=/drop=/…)` dataset-option list applied to T (GH#33)
    into: []const []const u8 = &.{}, // `SELECT … INTO :v1[,:v2…]` macro-var targets (BUG-sqlintomacro)
    into_sep: ?[]const u8 = null, // `SEPARATED BY 'x'` — join a column's values across rows
    into_range: bool = false, // `:v1-:vn` numbered range — values go DOWN rows, not across columns
    joins: []const JoinStep = &.{}, // subsequent tables (inner/left/cross)
    where: ?[]const Token = null,
    group_exprs: []const []const Token = &.{}, // GROUP BY terms (a column or an expression)
    having: ?[]const Token = null, // HAVING <cond> — filter groups after aggregation
    order: []const Order = &.{},
};

// A pass-through column (select *, select col, even `col as alias`) carries its
// source column's attached format/informat/label; computed/aggregate columns
// leave them null (GH#49). These ride into the created table's schema.
const OutCol = struct { name: []const u8, type: VarType, format: ?[]const u8 = null, informat: ?[]const u8 = null, label: ?[]const u8 = null, len: ?usize = null };
const Result = struct { cols: []OutCol, rows: [][]Value };

/// Copy a Result's output columns onto a freshly-created dataset, carrying each
/// pass-through column's attached format/informat/label (GH#49). Used by every
/// create-table path (CREATE TABLE AS, derived tables, inline join views).
/// Override the just-appended OutCol's format/informat/label/len with an item's
/// SELECT-list modifiers (BUG-sqlselectmodifier). No-op when the item carries none.
fn applyItemMods(cols: *std.ArrayList(OutCol), it: Item) void {
    if (cols.items.len == 0) return;
    const c = &cols.items[cols.items.len - 1];
    if (it.format) |f| c.format = f;
    if (it.informat) |f| c.informat = f;
    if (it.label) |l| c.label = l;
    if (it.length) |n| c.len = n;
}

fn addResultCols(ds: *Dataset, cols: []const OutCol) !void {
    for (cols) |c| {
        const idx = try ds.addColumn(c.name, c.type);
        ds.columns.items[idx].format = c.format;
        ds.columns.items[idx].informat = c.informat;
        ds.columns.items[idx].label = c.label;
        ds.columns.items[idx].len = c.len;
    }
}

/// A SELECT-clause `length=n` (BUG-sqlselectlength) caps a character column's
/// storage: every cell TRUNCATES to n bytes, exactly as a `char(n)` DDL width
/// does (GAP-sqldatatypewidth — SAS stores 'abcdef' at length=3 as 'abc').
/// Numeric lengths are descriptor-only (contentsLen/GH#59); f64 cells stay whole.
fn applyLens(res: *Result) void {
    for (res.cols, 0..) |c, k| {
        const n = c.len orelse continue;
        if (c.type != .char) continue;
        for (res.rows) |row| if (k < row.len and row[k] == .str and row[k].str.len > n) {
            row[k] = .{ .str = row[k].str[0..n] };
        };
    }
}

/// TITLE / FOOTNOTE state, SHARED with main.zig's global-statement handler, which
/// reaches it as `sas.sql.Titles`. A TITLE is a persistent setting — not emitted
/// where written; SAS stamps the active titles atop each listing proc's output and
/// footnotes below, until changed. `title1`..`title10` are the numbered lines; the
/// unnumbered `title` is line 1 and cancels 2..10. Defined HERE (not a new module)
/// so main.zig and PROC SQL share ONE type without a root.zig registration or
/// touching exec.zig. ponytail: left-aligned raw text (SAS centers to LINESIZE),
/// emitted once per proc, not repeated per page.
pub const Titles = struct {
    titles: [10]?[]const u8 = .{null} ** 10,
    footnotes: [10]?[]const u8 = .{null} ** 10,

    /// Apply a `title[N]` / `footnote[N] ["text"];` statement (`toks[0]` = the
    /// keyword). Returns true if it WAS a title/footnote (so the caller knows it
    /// was consumed and is not an ordinary statement); false otherwise. `arena`
    /// backs any rebuilt unquoted text; `diags` carries the out-of-range error.
    pub fn set(self: *Titles, arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token) diag.Error!bool {
        if (toks.len == 0) return false;
        const kw = toks[0].text;
        const is_title = std.ascii.startsWithIgnoreCase(kw, "title");
        const is_footnote = std.ascii.startsWithIgnoreCase(kw, "footnote");
        if (!is_title and !is_footnote) return false;
        const slots = if (is_footnote) &self.footnotes else &self.titles;
        const base: usize = if (is_footnote) "footnote".len else "title".len;
        // `title` / `titleN` — the digits after the keyword name the 1-based line (none → line 1).
        const n = std.fmt.parseInt(usize, kw[base..], 10) catch 1;
        if (n < 1 or n > slots.len) {
            // F5: SAS 9.4 restricts the line number to 1–10 and errors out of
            // range — was silently dropped (rc=0, text gone). Fail LOUD.
            try diags.report(.err, toks[0].line, "Invalid line number for the {s} statement.", .{if (is_footnote) "FOOTNOTE" else "TITLE"});
            return true;
        }
        // First quoted string is the text. If there is NO quoted string but there
        // ARE tokens after the keyword, SAS accepts the UNQUOTED text and SETS the
        // line (`title1 Acme Study;` is valid — Statements: Reference). Only a bare
        // `title[n];` with nothing past the keyword is the cancel form.
        var text: ?[]const u8 = null;
        for (toks[1..]) |tk| if (tk.tag == .string) {
            text = tk.text;
            break;
        };
        if (text == null) text = try joinUnquoted(arena, toks[1..]);
        slots[n - 1] = text;
        // Empty text (`title;` or `titleN;`) cancels that line AND every
        // higher-numbered line (BUG-titlecancel; same rule for FOOTNOTE).
        if (text == null) for (slots[n - 1 ..]) |*s| {
            s.* = null;
        };
        return true;
    }

    /// Rebuild unquoted TITLE/FOOTNOTE text from the tokens after the keyword,
    /// joined by single spaces; `null` if there is no real text (the cancel form).
    /// ponytail: tokens carry no source offset, so exact interior spacing and
    /// punctuation runs are lost — join the slices; add a raw source span only if
    /// a study needs byte-exact unquoted titles.
    fn joinUnquoted(arena: std.mem.Allocator, toks: []const Token) diag.Error!?[]const u8 {
        var buf: std.ArrayList(u8) = .empty;
        for (toks) |tk| {
            const piece: []const u8 = switch (tk.tag) {
                .semicolon, .eof => continue,
                .dot => ".",
                .comma => ",",
                else => tk.text,
            };
            if (piece.len == 0) continue;
            if (buf.items.len != 0) try buf.append(arena, ' ');
            try buf.appendSlice(arena, piece);
        }
        return if (buf.items.len == 0) null else buf.items;
    }

    pub fn emitTitles(self: *const Titles, a: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        for (self.titles) |ln| if (ln) |s| {
            try out.appendSlice(a, s);
            try out.append(a, '\n');
        };
    }

    pub fn emitFootnotes(self: *const Titles, a: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
        for (self.footnotes) |ln| if (ln) |s| {
            try out.appendSlice(a, s);
            try out.append(a, '\n');
        };
    }

    /// One resolved BY variable for #BYVAL/#BYVAR title substitution
    /// (BUG-byvaltitle): `value` is the current group's FORMATTED value,
    /// `label` the variable's label-or-name (#BYVAR). The caller (which owns
    /// the dataset/row) builds the list in BY order (#BYVAL1 → byvars[0]).
    pub const ByVar = struct { name: []const u8, label: []const u8, value: []const u8 };

    /// True when any active title/footnote line carries a #BYVAL/#BYVAR token —
    /// a PROC with a BY statement then re-resolves the lines per BY group
    /// (emitTitlesBy) instead of stamping the raw text once.
    pub fn hasBySubst(self: *const Titles) bool {
        for (self.titles) |ln| if (ln) |s| {
            if (scanSubst(s)) return true;
        };
        for (self.footnotes) |ln| if (ln) |s| {
            if (scanSubst(s)) return true;
        };
        return false;
    }

    /// Title lines with #BYVAL(var)/#BYVALn → the BY variable's current-group
    /// formatted value and #BYVAR(var)/#BYVARn → its label-or-name (all
    /// case-insensitive). Unresolvable tokens (unknown var, out-of-range
    /// position) stay literal — SAS leaves them as-is too.
    pub fn emitTitlesBy(self: *const Titles, a: std.mem.Allocator, out: *std.ArrayList(u8), byvars: []const ByVar) !void {
        for (self.titles) |ln| if (ln) |s| {
            try out.appendSlice(a, try substByLine(a, s, byvars));
            try out.append(a, '\n');
        };
    }

    pub fn emitFootnotesBy(self: *const Titles, a: std.mem.Allocator, out: *std.ArrayList(u8), byvars: []const ByVar) !void {
        for (self.footnotes) |ln| if (ln) |s| {
            try out.appendSlice(a, try substByLine(a, s, byvars));
            try out.append(a, '\n');
        };
    }
};

/// A parsed `#BYVAL…`/`#BYVAR…` token: what it keys on (a variable name, or a
/// 1-based position into the BY list) and the token's end offset in the line.
const SubstTok = struct {
    is_val: bool, // #BYVAL → value; #BYVAR → label/name
    end: usize,
    name: ?[]const u8 = null,
    pos: usize = 0,
};

/// True when `s` holds at least one well-formed #BYVAL/#BYVAR token.
fn scanSubst(s: []const u8) bool {
    var i: usize = 0;
    while (std.mem.indexOfScalarPos(u8, s, i, '#')) |h| {
        if (parseSubstTok(s, h) != null) return true;
        i = h + 1;
    }
    return false;
}

/// Parse the token at `s[h]` (`s[h] == '#'`): `#BYVAL(name)`, `#BYVALn`,
/// `#BYVAR(name)`, `#BYVARn`, case-insensitive; null when it isn't one.
fn parseSubstTok(s: []const u8, h: usize) ?SubstTok {
    if (h + 6 > s.len) return null;
    const kw = s[h + 1 .. h + 6];
    const is_val = std.ascii.eqlIgnoreCase(kw, "byval");
    if (!is_val and !std.ascii.eqlIgnoreCase(kw, "byvar")) return null;
    var j = h + 6;
    if (j < s.len and s[j] == '(') {
        const close = std.mem.indexOfScalarPos(u8, s, j + 1, ')') orelse return null;
        return .{ .is_val = is_val, .end = close + 1, .name = std.mem.trim(u8, s[j + 1 .. close], " ") };
    }
    var pos: usize = 0;
    var digits: usize = 0;
    while (j < s.len and std.ascii.isDigit(s[j])) : (j += 1) {
        pos = pos * 10 + (s[j] - '0');
        digits += 1;
    }
    if (digits == 0) return null;
    return .{ .is_val = is_val, .end = j, .pos = pos };
}

/// Replace every resolvable #BYVAL/#BYVAR token in `s`; anything else (and a
/// token naming a non-BY variable / out-of-range position) passes through
/// byte-identical.
fn substByLine(a: std.mem.Allocator, s: []const u8, byvars: []const Titles.ByVar) ![]const u8 {
    if (!scanSubst(s)) return s; // fast path: untouched bytes
    var buf: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '#') if (parseSubstTok(s, i)) |tk| {
            const bv: ?Titles.ByVar = if (tk.name) |n| blk: {
                for (byvars) |b| if (std.ascii.eqlIgnoreCase(b.name, n)) break :blk b;
                break :blk null;
            } else if (tk.pos >= 1 and tk.pos <= byvars.len) byvars[tk.pos - 1] else null;
            if (bv) |b| {
                try buf.appendSlice(a, if (tk.is_val) b.value else b.label);
                i = tk.end;
                continue;
            }
        };
        try buf.append(a, s[i]);
        i += 1;
    }
    return buf.items;
}

/// PROC SQL statement/RESET options that change execution (BUG-sqloptions-tick271).
/// Process-global, reset at each `run()` entry — SAS scopes these to one PROC SQL
/// step (RESET accumulates/overrides them within the step; QUIT ends it). PROC SQL
/// never nests here (subqueries call execQuery, not run()), so a global is safe.
const SqlOpts = struct {
    outobs: ?usize = null, // cap on rows OUTPUT (displayed / written to a table) — F2
    inobs: ?usize = null, // cap on rows READ from each source table — F3
    noexec: bool = false, // syntax-check only: validate but don't execute side effects — F1
    noprint: bool = false, // suppress the query LISTING (rows still computed, INTO still bound) — F5
    number: bool = false, // prepend a 1-based "Row" column to the query listing — F6
    feedback: bool = false, // echo the star-expanded statement to the log — F7
    // GAP-sqlsortseqlinguistic. `null` = the PROC SQL SORTSEQ= option was not
    // given, so the SORTSEQ= SYSTEM option decides; true/false = it was, and it
    // WINS. That precedence is doc-stated, not inferred — SQL Procedure User's
    // Guide printed p.261 (`=== pdf 276 ===`): "If LINGUISTIC is specified for
    // the SORTSEQ system option, then PROC SQL honors the setting. The setting
    // of the PROC SQL SORTSEQ option overrides the setting of the SORTSEQ
    // system option." One sentence settles all three combinations.
    sortseq_ling: ?bool = null,
};
var g_opts: SqlOpts = .{};

/// F7 FEEDBACK: the expanded-statement echo of the SELECT currently running,
/// captured by execQuery and emitted by runStmt (null → nothing pending).
var g_feedback: ?[]const u8 = null;

/// Real SAS 9.4 PROC SQL options we recognize but don't implement — accepted as a
/// no-op so a valid program isn't rejected. OUTOBS/INOBS/EXEC/NOEXEC and
/// PRINT/NOPRINT/NUMBER/NONUMBER/FEEDBACK/NOFEEDBACK are handled specially in
/// parseOptions and are NOT in this list. Anything not here and not special is a
/// genuinely-unknown option → fail loud (F4).
fn isNoopSqlOption(name: []const u8) bool {
    inline for (.{
        "double",    "nodouble",  "dquote",      "errorstop", "noerrorstop", "flow",
        "noflow",    "ipassthru", "noipassthru", "loops",     "prompt",      "noprompt",
        // SORTSEQ was here and is GONE (GAP-sqlsortseqlinguistic): it CHANGES
        // ROW ORDER, so no-oping it was silent wrong output (D-002), not a
        // harmless accept. parseOptions handles it below.
        "reduceput", "sortmsg",   "nosortmsg",   "stimer",      "nostimer",
        "threads",   "nothreads", "undo_policy", "warn",      "nowarn",      "buffersize",
    }) |opt| if (eqi(name, opt)) return true;
    return false;
}

/// Parse a PROC SQL statement-header / RESET option list into g_opts (F1–F4).
/// `toks` is the option region (no leading `proc sql` / `reset`, up to the `;`).
fn parseOptions(diags: *diag.Diagnostics, toks: []const Token) diag.Error!void {
    var i: usize = 0;
    while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) {
        const tok = toks[i];
        if (tok.tag != .name) { // stray punctuation between options — skip
            i += 1;
            continue;
        }
        const name = tok.text;
        if (eqi(name, "noexec")) {
            g_opts.noexec = true;
            i += 1;
        } else if (eqi(name, "exec")) {
            g_opts.noexec = false;
            i += 1;
        } else if (eqi(name, "noprint")) { // F5
            g_opts.noprint = true;
            i += 1;
        } else if (eqi(name, "print")) {
            g_opts.noprint = false;
            i += 1;
        } else if (eqi(name, "number")) { // F6
            g_opts.number = true;
            i += 1;
        } else if (eqi(name, "nonumber")) {
            g_opts.number = false;
            i += 1;
        } else if (eqi(name, "feedback")) { // F7
            g_opts.feedback = true;
            i += 1;
        } else if (eqi(name, "nofeedback")) {
            g_opts.feedback = false;
            i += 1;
        } else if (eqi(name, "sortseq")) {
            // GAP-sqlsortseqlinguistic. `SORTSEQ=sort-table | LINGUISTIC`, SQL
            // Procedure User's Guide printed p.261 (`=== pdf 276 ===`) —
            // "specifies the collating sequence to use when a query contains an
            // ORDER BY clause". Added in 9.4M3: printed p.45 (`=== pdf 60 ===`),
            // "Beginning with SAS 9.4M3, linguistic collation is supported with
            // the SORTSEQ statement option."
            i += 1;
            if (atTag(toks, i, .eq)) i += 1;
            const v = if (i < toks.len and toks[i].tag == .name) toks[i].text else "";
            if (eqi(v, "linguistic")) {
                // LINGUISTIC(<collating-options>) tunes the collation; honouring
                // the bare form while dropping the modifiers would collate
                // differently than asked, so it is LOUD — the same call runSort
                // makes for `proc sort sortseq=linguistic(...)` (proc.zig).
                if (i + 1 < toks.len and toks[i + 1].tag == .lparen) {
                    // rc 2, not 1: `LINGUISTIC<(collating-options)>` is documented
                    // valid SAS (Procedures Guide p.2410) that opensas does not
                    // implement — a gap, per D-009 and the whole
                    // BUG-rcsplitmembership epic. Same class as the EBCDIC arm below.
                    diag.markGap();
                    return diags.fail(error.ExecError, tok.line, "PROC SQL: SORTSEQ=LINGUISTIC(...) collating options are not supported", .{});
                }
                g_opts.sortseq_ling = true;
            } else if (eqi(v, "ascii")) {
                g_opts.sortseq_ling = false; // explicit ASCII overrides a system SORTSEQ=LINGUISTIC
            } else {
                // Everything else is a TRANSLATION TABLE. This arm is knowingly
                // CONFLATED and rc 2 is the deliberate choice: p.261 says
                // sort-table "specifies a translation table that YOU CREATED
                // with PROC TRANTAB", so the valid set is user-created names and
                // NO closed list exists to split a typo from a real table
                // (§5d's LEFT rows, same shape). D-018 then decides it — an
                // undecidable value stays on the gap arm, because a wrong rc 2
                // costs one spurious "file an opensas issue" while a wrong rc 1
                // tells a user their valid SAS is broken. Loud either way: this
                // used to be a silent no-op that reordered nothing.
                diag.markGap();
                return diags.fail(error.ExecError, tok.line, "PROC SQL: SORTSEQ= collation other than ASCII/LINGUISTIC is not supported", .{});
            }
            i += 1;
        } else if (eqi(name, "outobs") or eqi(name, "inobs")) {
            i += 1;
            if (atTag(toks, i, .eq)) i += 1;
            const n: ?usize = if (atTag(toks, i, .number)) std.fmt.parseInt(usize, toks[i].text, 10) catch null else null;
            if (n == null) return diags.fail(error.ExecError, tok.line, "PROC SQL: {s}= requires a numeric value", .{name});
            if (eqi(name, "outobs")) g_opts.outobs = n else g_opts.inobs = n;
            i += 1;
        } else if (isNoopSqlOption(name)) {
            i += 1;
            if (atTag(toks, i, .eq)) { // recognized `opt=value` form — swallow the value
                i += 1;
                if (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) i += 1;
            }
        } else {
            // F4: an unrecognized option was silently swallowed — SAS errors, and the
            // house rule is fail-loud. A typo'd `outob=3` lands here instead of a
            // silent no-op that hides an uncapped query.
            return diags.fail(error.ExecError, tok.line, "PROC SQL: unrecognized option {s}", .{name});
        }
    }
}

/// Truncate a SELECT Result to OUTOBS= rows (F2) and reflect the cap in &SQLOBS.
/// Applied at the three statement-level output sites (SELECT print, CREATE TABLE
/// AS, INSERT … SELECT) — NOT inside execSelect, so a derived-table/subquery source
/// is never capped.
fn applyOutobs(res: Result) Result {
    const cap = g_opts.outobs orelse return res;
    if (res.rows.len <= cap) return res;
    var r = res;
    r.rows = res.rows[0..cap];
    g_select_rows = cap;
    return r;
}

/// Run a whole `proc sql; … quit;` step (`toks` starts at the `proc` token).
pub fn run(arena: std.mem.Allocator, out: *std.ArrayList(u8), lib: *Library, diags: *diag.Diagnostics, titles: *Titles, toks_in: []const Token) diag.Error!void {
    g_opts = .{}; // options are per-step; a RESET statement mutates them within the step
    pruneConstraints(lib); // BUG-sqlconsleak: forget constraints on tables this Library no longer holds
    // Fold `table.column` (name·dot·name) into single name tokens, so qualified
    // references in select/on/where/order read as one identifier.
    const toks = try coalesceDots(arena, toks_in);
    var i: usize = 2; // past `proc sql`
    const hdr_end = stmtEnd(toks, i);
    try parseOptions(diags, toks[i..hdr_end]); // statement-header options (F1–F4)
    i = if (hdr_end < toks.len) hdr_end + 1 else hdr_end; // past the header ';'

    while (i < toks.len and toks[i].tag != .eof) {
        if (tkKw(toks[i], "quit")) break;
        const end = stmtEnd(toks, i);
        const stmt = toks[i..end];
        // GAP-titleinsql: TITLE/FOOTNOTE are valid SAS 9.4 inside PROC SQL — update
        // the shared title state (stamped over each SELECT's listing in runStmt),
        // exactly as the top-level global handler does. Not an SQL statement, so it
        // leaves &SQLOBS/&SQLRC untouched.
        if (try titles.set(arena, diags, stmt)) {
            i = if (end < toks.len) end + 1 else end;
            continue;
        }
        const nobs = try runStmt(arena, out, lib, diags, titles, stmt);
        // Automatic macro vars SAS sets after every SQL statement (BUG-sqlobs).
        try lib.setMacroVar("sqlobs", try std.fmt.allocPrint(arena, "{d}", .{nobs}));
        try lib.setMacroVar("sqlrc", "0"); // ponytail: 0=success; error-code paths TBD
        i = if (end < toks.len) end + 1 else end; // skip the ';'
    }
}

/// A mnemonic operator emitted as a `.name` token — after one of these a `.` is
/// the numeric-missing literal, not a member-access dot (so `col ne . group by`
/// must NOT fold `ne.group`, which would swallow the GROUP BY — BUG-sqlwherenemiss).
fn isWordOp(tok: Token) bool {
    if (tok.tag != .name) return false;
    // …or a CASE keyword: `then .` / `else .` / `when .` / `case .` put a MISSING
    // literal between two name-tagged keywords, which must not fold into one name
    // (BUG-sqlemptyaggexpr sibling: `case when count(*)>0 then mean(x) else . end`).
    inline for (.{ "eq", "ne", "lt", "le", "gt", "ge", "in", "and", "or", "not", "case", "when", "then", "else" }) |op|
        if (std.ascii.eqlIgnoreCase(tok.text, op)) return true;
    return false;
}

/// A dot before one of these clause keywords is NOT member access: it is a
/// trailing format-spec dot (`format=best8. from`) — folding `best8.from` would
/// hide the FROM clause and break parsing (BUG-sqlselectmodifier). The
/// constraint keywords are the CREATE/ALTER column-def siblings (`format=date9.
/// not null` — BUG-sqlddlmed). None of these is ever a valid bare
/// qualified-column suffix.
fn isFoldStop(tok: Token) bool {
    inline for (.{ "from", "where", "group", "having", "order", "into", "union", "intersect", "except", "on", "not", "primary", "unique", "distinct", "check", "references", "constraint" }) |kw|
        if (tkKw(tok, kw)) return true;
    return false;
}

/// Merge `t . c` runs into a single `t.c` name token (a `table.column` reference).
fn coalesceDots(arena: std.mem.Allocator, toks: []const Token) ![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        // Only a value name preceding the dot is a member-access reference; a word
        // operator (ne/eq/…) before the dot means the dot is a missing literal.
        if (atTag(toks, i, .name) and !isWordOp(toks[i]) and
            atTag(toks, i + 1, .dot) and atTag(toks, i + 2, .name) and !isFoldStop(toks[i + 2]) and
            // …and a trailing format-spec dot before a column modifier
            // (`format=date9. label=…`) must not fold `date9.label` either
            // (BUG-sqlddlmed; isColModAt = modifier keyword followed by `=`)
            !isColModAt(toks, i + 2))
        {
            const text = try std.fmt.allocPrint(arena, "{s}.{s}", .{ toks[i].text, toks[i + 2].text });
            try out.append(arena, .{ .tag = .name, .text = text, .line = toks[i].line });
            i += 3;
        } else {
            try out.append(arena, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

fn qualify(arena: std.mem.Allocator, tbl: []const u8, c: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena, "{s}.{s}", .{ tbl, c });
}

/// The part of a name after the last `.` (`a.id` → `id`; `id` → `id`).
fn unqualify(name: []const u8) []const u8 {
    return if (std.mem.lastIndexOfScalar(u8, name, '.')) |d| name[d + 1 ..] else name;
}

/// PROC SQL does NOT get the DATA step's whole operator surface: three symbol
/// spellings differ here, and all three were leaking, because every one of the
/// dozen `pe.Parser.init` sites below parses WITHOUT `where_ctx` — the flag
/// parser_expr uses to apply the WHERE-clause operator rules. Normalizing the
/// statement's tokens ONCE, here, gives every clause the same rule (WHERE, ON,
/// HAVING, a CASE arm, a SELECT item, an UPDATE SET, a CHECK constraint) instead
/// of threading a flag into a dozen call sites — and it avoids what that flag
/// would ALSO switch on: parser_expr's CONTAINS/`?`/LIKE arms, which SQL already
/// desugars itself at the token level (desugarPredicates).
///   • `<>` is NOT EQUAL in PROC SQL (Language Reference: Concepts p.219 Table 11.3 lists `<>` among
///     the NE spellings), never the DATA-step MAX operator. It was reaching
///     parser_expr as `.max_op` = MAX, so `where x <> 3` computed max(x, 3) —
///     non-zero for every row — and the filter KEPT THE WHOLE TABLE. That is
///     the exact BUG-wherene failure mode, silently, in SQL. `quantCmpOf`
///     already mapped `.max_op` → NE for `<> ALL`, so the two now agree.
///   • `><` (MIN) has no predicate meaning — loud, as in a DATA-step WHERE.
///   • `=<` / `=>` (the LEGACY spellings of LE / GE) are loud: "It is not
///     supported in WHERE clauses or in PROC SQL" (Language Reference: Concepts p.127 Table 6.4
///     fn.2/3). That sentence qualifies WHERE with "clauses" but names PROC SQL
///     WITHOUT qualification, so the ban is procedure-wide, not WHERE-only —
///     which is what one pass over the whole statement gives. The lexer stamps
///     the spelling in `text` (`<=` / `>=` carry none), which is the only way to
///     tell them apart once both are `.le`/`.ge`.
///   • EQT / GTT / LTT / GET / LET / NET — the six alphabetic TRUNCATED
///     comparison operators (SQL Procedure User's Guide, Table 8.2 group 7,
///     printed p.403-404; "Truncated String Comparison Operators", p.405:
///     "Unlike the DATA step, PROC SQL does not support the colon operators
///     (such as =:, >:, and <=:) … Use the alphabetic operators (such as EQT,
///     GTT, and LET)"; same six with examples in Table 2.5, printed p.55-56).
///     Each rewrites to the symbol operator token + the colon-modifier token —
///     the exact pair the DATA step's `=:` parses from — so all six reach
///     parser_expr's ONE prefix compare, mkTruncCmp, and the two surfaces
///     share the shorter-operand rule (p.405), the zero-length EQ guard
///     (Language Reference: Concepts p.130) and the numeric-coercion NOTE by construction. The colon
///     form itself is NOT banned here (GAP-sqlcolonmodifier, held): this
///     change is purely additive. Guard: only BETWEEN two operand edges
///     (isInfixTruncOp) — a column or table named GET / LET / NET in operand
///     position must keep resolving as a name.
/// ponytail: per STATEMENT, so earlier statements in the step still run before
/// the offending one errors (SAS's own timing). Widen to the step header too if
/// a fixture ever puts a comparison there.
fn sqlOperatorRules(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token) diag.Error![]const Token {
    var out: std.ArrayList(Token) = .empty;
    try out.ensureTotalCapacity(arena, toks.len);
    for (toks, 0..) |tok, i| {
        switch (tok.tag) {
            .le, .ge => {
                if (std.mem.eql(u8, tok.text, "=<") or std.mem.eql(u8, tok.text, "=>"))
                    return diags.fail(error.ParseError, tok.line, "PROC SQL: the {s} operator is not supported here (SAS 9.4 accepts the legacy {s} spelling in a DATA step only); use {s}", .{ tok.text, if (tok.tag == .le) "LE" else "GE", if (tok.tag == .le) "<=" else ">=" });
                try out.append(arena, tok);
            },
            .max_op => try out.append(arena, .{ .tag = .ne, .text = "", .line = tok.line }), // `<>` = NE in SQL
            .min_op => return diags.fail(error.ParseError, tok.line, "PROC SQL: the >< (MIN) operator is not valid here", .{}),
            .name => if (truncOpTag(tok.text)) |op| {
                if (isInfixTruncOp(toks, i)) {
                    try out.append(arena, .{ .tag = op, .text = "", .line = tok.line });
                    // NOTE-sqltruncblanks: the colon is MARKED "trim" so
                    // parser_expr applies PROC SQL's trailing-blank rule to it
                    // and not the DATA step's storage-length rule — p.405 states
                    // both in one sentence and gives each to a different surface:
                    // "The Base SAS WHERE processor truncates comparisons based
                    // on the actual length of a string, even if a string includes
                    // blanks at the end. PROC SQL trims trailing blanks from the
                    // string values before it truncates comparisons."
                    // Marking the token (rather than threading a parser flag
                    // through the dozen pe.Parser.init sites) is safe precisely
                    // because the colon modifier is NOT SQL syntax: inside a
                    // PROC SQL step the only colon that can reach a comparison
                    // is the one this rewrite plants.
                    try out.append(arena, .{ .tag = .colon, .text = "trim", .line = tok.line });
                } else try out.append(arena, tok);
            } else try out.append(arena, tok),
            else => try out.append(arena, tok),
        }
    }
    return out.items;
}

/// EQT / NET / GTT / LTT / GET / LET → the ordinary comparison tag the word
/// truncates (SQL Procedure Table 8.2 group 7, printed p.403-404).
/// Case-insensitive, like every SAS operator word.
fn truncOpTag(text: []const u8) ?lex.Tag {
    if (eqi(text, "eqt")) return .eq;
    if (eqi(text, "net")) return .ne;
    if (eqi(text, "gtt")) return .gt;
    if (eqi(text, "ltt")) return .lt;
    if (eqi(text, "get")) return .ge;
    if (eqi(text, "let")) return .le;
    return null;
}

/// Words that can stand right BEFORE an operand in SQL — a clause introducer,
/// a DDL verb, or a word operator. After one of these an EQT-family word is an
/// OPERAND (a column/table named GET, LET, NET, …), never the operator.
fn isPreOperandKw(text: []const u8) bool {
    inline for (.{ "select", "from", "where", "on", "having", "when", "then", "else", "case", "by", "as", "set", "into", "values", "table", "using", "join", "calculated", "distinct", "add", "modify", "drop", "and", "or", "not", "eq", "ne", "gt", "ge", "lt", "le", "in", "between", "like", "contains", "is", "escape", "exists", "all", "any", "some" }) |kw|
        if (eqi(text, kw)) return true;
    return false;
}

/// Words that can stand right AFTER an operand — they end the expression. In
/// front of one an EQT-family word is an operand, not the operator.
fn isPostOperandKw(text: []const u8) bool {
    inline for (.{ "from", "where", "group", "having", "order", "on", "as", "then", "else", "end", "when", "and", "or", "union", "except", "intersect", "join", "inner", "left", "right", "full", "cross", "using", "set", "values", "into", "desc", "asc", "add", "modify", "drop", "quit" }) |kw|
        if (eqi(text, kw)) return true;
    return false;
}

/// True when the EQT-family word at toks[i] sits BETWEEN two operands — the
/// infix truncated-comparison operator, never a name in operand position.
/// Same neighbor shape as isInfixMinMax (`min`/`max`), plus the keyword
/// guards: `select get from t` must keep resolving GET as a column while
/// `where name eqt 'A'` must become the operator.
fn isInfixTruncOp(toks: []const Token, i: usize) bool {
    if (i == 0 or i + 1 >= toks.len) return false;
    const prev_ok = switch (toks[i - 1].tag) {
        .number, .string, .rparen => true,
        .name => !isPreOperandKw(toks[i - 1].text),
        else => false,
    };
    const next_ok = switch (toks[i + 1].tag) {
        .number, .string, .lparen => true,
        .name => !isPostOperandKw(toks[i + 1].text),
        else => false,
    };
    return prev_ok and next_ok;
}

/// Runs one SQL statement and returns its `&SQLOBS` row count (rows selected /
/// created / inserted / deleted). CREATE/INSERT/DELETE count the target table's
/// size change around the op; UPDATE reports the table size (best-effort).
fn runStmt(arena: std.mem.Allocator, out: *std.ArrayList(u8), lib: *Library, diags: *diag.Diagnostics, titles: *Titles, stmt_in: []const Token) !usize {
    const stmt = try sqlOperatorRules(arena, diags, stmt_in);
    if (stmt.len == 0) return 0;
    if (tkKw(stmt[0], "select")) {
        // execSelect returns null for a SELECT … INTO (print suppressed) — read the
        // processed row count from g_select_rows so &SQLOBS is right either way.
        // GAP-titleinsql: stamp the active TITLEs atop this listing and FOOTNOTEs
        // below, like the other report procs (main.zig runProc). Kept here (not in
        // runProc's pre-emit) because a TITLE set *inside* this PROC SQL isn't in
        // the shared state until the loop above reads it — so PROC SQL is NOT in
        // runProc's `listing` set; it self-stamps around its own output instead.
        g_feedback = null; // drop any echo leaked by a CREATE/INSERT … SELECT
        const sel_res = try execSelect(arena, lib, diags, stmt);
        // F7 FEEDBACK: the expanded-statement echo goes to the log even under
        // NOEXEC/NOPRINT — SAS writes it while validating the statement.
        if (g_feedback) |fb| try out.appendSlice(arena, fb);
        if (sel_res) |res0| {
            const res = applyOutobs(res0); // OUTOBS= caps displayed rows (F2)
            // NOEXEC validates the SELECT (bad columns still ERROR) but suppresses
            // its output — SAS syntax-checks and produces no listing (F1).
            // NOPRINT (F5) also suppresses the listing, but the query RAN: rows
            // were computed and INTO macro vars were bound inside execSelect.
            if (!g_opts.noexec and !g_opts.noprint) {
                try titles.emitTitles(arena, out);
                try report(arena, out, res);
                try titles.emitFootnotes(arena, out);
            }
        }
        return g_select_rows;
    }
    if (tkKw(stmt[0], "reset")) {
        // RESET re-specifies options mid-step (e.g. `reset noexec;` then `reset exec;`).
        try parseOptions(diags, stmt[1..]);
        return 0;
    }
    // F1: under NOEXEC every side-effecting statement is syntax-checked but NOT run —
    // a `noexec` dry-run of a destructive DROP/DELETE/UPDATE/CREATE must not mutate.
    if (g_opts.noexec) return 0;
    if (tkKw(stmt[0], "drop")) {
        try runDrop(arena, lib, diags, stmt);
        return 0;
    }
    if (tkKw(stmt[0], "create")) {
        try runCreate(arena, lib, diags, stmt);
        return sqlTargetRows(lib, stmt); // the new table's rows
    }
    if (tkKw(stmt[0], "insert")) {
        const before = sqlTargetRows(lib, stmt);
        try runInsert(arena, lib, diags, stmt);
        return sqlTargetRows(lib, stmt) -| before; // rows added
    }
    if (tkKw(stmt[0], "delete")) {
        const before = sqlTargetRows(lib, stmt);
        try runDelete(arena, lib, diags, stmt);
        return before -| sqlTargetRows(lib, stmt); // rows removed
    }
    if (tkKw(stmt[0], "update")) {
        try runUpdate(arena, lib, diags, stmt);
        return sqlTargetRows(lib, stmt); // best-effort: rows in the table
    }
    if (tkKw(stmt[0], "alter")) {
        try runAlter(arena, lib, diags, stmt);
        return sqlTargetRows(lib, stmt);
    }
    unsupported("PROC SQL: unsupported statement");
    return 0;
}

/// `ALTER TABLE t ADD col type [, …] | ADD <constraint clause> [, …] | DROP col
/// [, …]` (GAP-sqlddl). ADD appends a column and back-fills existing rows with
/// its type's missing value, or registers a table-level integrity constraint via
/// the SAME parser CREATE TABLE uses; DROP removes a column and its cell from
/// every row. MODIFY and DROP CONSTRAINT fail loud as gaps (D-009 rc 2).
/// Comma-separated ADD/DROP items share the leading verb.
fn runAlter(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, stmt: []const Token) !void {
    var i: usize = 1;
    if (atKw(stmt, i, "table")) i += 1;
    const ds = if (atTag(stmt, i, .name)) lib.find(stmt[i].text) else null;
    if (ds == null) {
        unsupported("PROC SQL: ALTER TABLE — table not found");
        return;
    }
    i += 1;
    // BUG-sqlddlmed: constraints from ADD'd column suffixes, registered below.
    var acons: std.ArrayList(Constraint) = .empty;
    while (i < stmt.len) {
        if (atKw(stmt, i, "add")) {
            i += 1;
            // one or more `col [type] [modifiers|constraints]` items, comma-separated
            while (i < stmt.len and atTag(stmt, i, .name)) {
                // BUG-sqlalteraddconstraint: a TABLE-LEVEL constraint clause is not
                // a column def. `constraint`/`primary`/`unique`/`check`/`foreign`
                // all lex as plain `.name`, so the column path below read
                // `add constraint c1 check (x > 0)` as a column literally named
                // `constraint` — a silently corrupted schema at exit 0, the worst
                // failure class here. Route it to the SAME parser CREATE TABLE uses
                // (BUG-sqlconstraints) rather than growing a second one; that also
                // makes the column-vs-keyword ambiguity resolve identically in both
                // statements, which is the only defensible way for it to differ.
                if (tkKw(stmt[i], "constraint") or isTableConstraintStart(stmt[i])) {
                    const cstart = i;
                    i = alterItemEnd(stmt, i);
                    try parseColumnOrConstraint(arena, diags, ds.?, &acons, stmt[cstart..i]);
                    if (atTag(stmt, i, .comma)) {
                        i += 1;
                        continue;
                    } else break;
                }
                const ctok = stmt[i];
                const cname = ctok.text;
                i += 1;
                const tstart = i;
                i = alterItemEnd(stmt, i);
                var ty: VarType = .num;
                var awidth: ?usize = null; // declared char(n) width, as in CREATE (GAP-sqldatatypewidth)
                for (tstart..i) |k|
                    if (tkKw(stmt[k], "char") or tkKw(stmt[k], "varchar") or tkKw(stmt[k], "character")) {
                        ty = .char;
                        if (atTag(stmt, k + 1, .lparen) and atTag(stmt, k + 2, .number) and atTag(stmt, k + 3, .rparen))
                            awidth = std.fmt.parseInt(usize, stmt[k + 2].text, 10) catch null;
                    };
                const idx = try ds.?.addColumn(cname, ty);
                if (awidth) |w| ds.?.columns.items[idx].len = w;
                for (ds.?.rows.items) |*r| { // back-fill existing rows with missing
                    const nr = try arena.alloc(Value, idx + 1);
                    @memcpy(nr[0..idx], r.*);
                    nr[idx] = missingOf(ty);
                    r.* = nr;
                }
                // an inline constraint/modifier on ADD used to be silently
                // dropped — parse the region like a CREATE column def.
                try parseColSuffix(arena, diags, ds.?, idx, cname, &acons, stmt[tstart..i], 0, ctok.line);
                if (atTag(stmt, i, .comma)) i += 1 else break;
            }
        } else if (atKw(stmt, i, "drop")) {
            i += 1;
            while (i < stmt.len and atTag(stmt, i, .name)) {
                // Sibling of the ADD defect: `drop constraint c1` / `drop primary
                // key` / `drop foreign key f` name a CONSTRAINT, not a column. We
                // cannot drop one — a Constraint carries no name (CREATE reads
                // `constraint <name>` as metadata and skips it) — so this is valid
                // SAS we do not implement: a GAP, rc 2 per D-009. It already exited
                // 2, but via "column not found", which sends the reader hunting a
                // column that was never the subject.
                if (tkKw(stmt[i], "constraint") or isTableConstraintStart(stmt[i])) {
                    unsupported("PROC SQL: ALTER TABLE DROP CONSTRAINT — dropping an integrity constraint is not supported");
                    return;
                }
                const j = ds.?.indexOf(stmt[i].text) orelse {
                    unsupported("PROC SQL: ALTER TABLE DROP — column not found");
                    return;
                };
                _ = ds.?.columns.orderedRemove(j);
                for (ds.?.rows.items) |*r| {
                    const nr = try arena.alloc(Value, r.len - 1);
                    @memcpy(nr[0..j], r.*[0..j]);
                    @memcpy(nr[j..], r.*[j + 1 ..]);
                    r.* = nr;
                }
                i += 1;
                if (atTag(stmt, i, .comma)) i += 1 else break;
            }
        } else {
            unsupported("PROC SQL: ALTER TABLE — only ADD column / ADD constraint / DROP column supported");
            return;
        }
    }
    if (acons.items.len > 0) {
        // register merged with any CREATE-time constraints (constraintsOf sees
        // only the newest entry for a table — don't shadow the old ones)
        var all: std.ArrayList(Constraint) = .empty;
        if (constraintsOf(ds.?)) |old| try all.appendSlice(arena, old);
        try all.appendSlice(arena, acons.items);
        registerConstraints(ds.?, all.items, diags);
        // existing rows must comply too (e.g. NOT NULL on a non-empty table,
        // whose back-filled missings violate it) — one ERROR at the first
        // violation; the constraint stays enforced on later INSERT/UPDATE.
        for (ds.?.rows.items, 0..) |r, ri|
            if (try violatesConstraint(arena, lib, diags, ds.?, r, ri, stmt[0].line)) break;
    }
}

/// True at a top-level ALTER clause verb (`add`/`drop`/`modify`) — ends an item's
/// type region so a bare `add`/`drop` after an untyped column isn't read as a type.
fn isAlterVerb(stmt: []const Token, i: usize) bool {
    return atKw(stmt, i, "add") or atKw(stmt, i, "drop") or atKw(stmt, i, "modify");
}

/// End of the ALTER clause item starting at `start`: the next TOP-LEVEL comma or
/// ALTER verb, or the statement end. Paren-depth aware, which the hand-rolled scan
/// this replaces was not — `primary key (a, b)` and `check (x in (1, 2))` carry
/// commas that must not split the item, and the same scan feeds the column path,
/// where `add y num check (a in (1, 2))` was truncated mid-paren for the same reason.
fn alterItemEnd(stmt: []const Token, start: usize) usize {
    var i = start;
    var depth: usize = 0;
    while (i < stmt.len) : (i += 1) {
        if (stmt[i].tag == .lparen) {
            depth += 1;
        } else if (stmt[i].tag == .rparen) {
            if (depth == 0) break; // an unbalanced ')' — stop rather than run off
            depth -= 1;
        } else if (depth == 0 and (stmt[i].tag == .comma or isAlterVerb(stmt, i))) break;
    }
    return i;
}

/// `DROP TABLE t [, …]` / `DROP VIEW v [, …]` — remove the named member(s) from
/// the library, in memory AND on disk (BUG-sqlupdatedropcol: this was a 100%
/// silent no-op, exit 0, the table stayed in the library). A member that isn't
/// there is the SAS "does not exist" ERROR. DROP VIEW always errors here:
/// CREATE VIEW is unsupported, so no view can exist — and a same-named TABLE
/// is not a view (SAS errors on that too).
fn runDrop(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, stmt: []const Token) diag.Error!void {
    var i: usize = 1;
    const is_view = atKw(stmt, i, "view");
    if (is_view or atKw(stmt, i, "table")) i += 1 else {
        unsupported("PROC SQL: DROP — only DROP TABLE / DROP VIEW are supported");
        return;
    }
    while (atTag(stmt, i, .name)) {
        const name = stmt[i].text;
        const line = stmt[i].line;
        i += 1;
        if (is_view)
            return diags.fail(error.ExecError, line, "PROC SQL: view {s} does not exist", .{name});
        if (lib.readonlyOut(name)) return lib.failReadonly(name);
        if (!libRemove(arena, lib, name))
            return diags.fail(error.ExecError, line, "PROC SQL: table {s} does not exist", .{name});
        if (atTag(stmt, i, .comma)) i += 1 else break;
    }
}

/// Drop a leading `work.` — WORK is the default library (Library.find's rule).
fn stripWorkPrefix(name: []const u8) []const u8 {
    return if (name.len >= 5 and eqi(name[0..5], "work.")) name[5..] else name;
}

/// Remove the member `name` from the library — in memory AND, for a directory
/// libname, on disk (else the per-slice `loadLibInputs` preload resurrects it at
/// the next `lib.member` token). proc.zig dsDelete's SQL twin. True when a
/// member went. The Library index self-heals: slotOf reindexes on the shrink.
fn libRemove(arena: std.mem.Allocator, lib: *Library, name: []const u8) bool {
    const q = stripWorkPrefix(name);
    var found = false;
    for (lib.names.items, 0..) |n, i| if (eqi(stripWorkPrefix(n), q)) {
        _ = lib.names.orderedRemove(i);
        _ = lib.sets.orderedRemove(i);
        found = true;
        break;
    };
    const dot = std.mem.indexOfScalar(u8, name, '.') orelse return found;
    if (eqi(name[0..dot], "work")) return found;
    const dir = dsfns.librefDir(name[0..dot]) orelse return found;
    if (io.endsWithIgnoreCase(dir, ".sas7bdat") or io.endsWithIgnoreCase(dir, ".xpt")) return found;
    if (io.deleteMemberFiles(arena, dir, name[dot + 1 ..], false) > 0) found = true;
    return found;
}

/// The table a CREATE/INSERT/UPDATE/DELETE targets (`create table N`, `insert
/// into N`, `update N`, `delete from N`) — skips the connector keyword.
fn sqlTargetName(stmt: []const Token) ?[]const u8 {
    var i: usize = 1; // past the leading keyword
    if (atKw(stmt, i, "table") or atKw(stmt, i, "into") or atKw(stmt, i, "from")) i += 1;
    return if (atTag(stmt, i, .name)) stmt[i].text else null;
}

fn sqlTargetRows(lib: *Library, stmt: []const Token) usize {
    const n = sqlTargetName(stmt) orelse return 0;
    return if (lib.find(n)) |d| d.rows.items.len else 0;
}

/// `CREATE TABLE n AS <select>` (rows from a query) or `CREATE TABLE n (col type
/// …)` (empty table with a declared schema; char/varchar → char, else numeric).
fn runCreate(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, stmt: []const Token) !void {
    var i: usize = 1;
    if (atKw(stmt, i, "view")) { // GAP-sqladvanced: fail loud with the RIGHT name
        unsupported("PROC SQL: CREATE VIEW is not supported yet");
        return;
    }
    if (atKw(stmt, i, "table")) i += 1;
    const name = if (atTag(stmt, i, .name)) stmt[i].text else {
        unsupported("PROC SQL: CREATE TABLE without a name");
        return;
    };
    i += 1;
    if (atKw(stmt, i, "as")) {
        i += 1;
        const res = applyOutobs((try execSelect(arena, lib, diags, stmt[i..])) orelse return); // OUTOBS= caps written rows (F2)
        const ds = try arena.create(Dataset);
        ds.* = Dataset.init(arena, name);
        try addResultCols(ds, res.cols); // GH#49: carry attached formats
        for (res.rows) |row| try ds.appendRow(row);
        try lib.put(name, ds);
        return;
    }
    if (atKw(stmt, i, "like")) { // `CREATE TABLE new LIKE old` — copy schema, no rows (GAP-sqlddl)
        i += 1;
        const src = if (atTag(stmt, i, .name)) lib.find(stmt[i].text) else null;
        if (src == null) {
            unsupported("PROC SQL: CREATE TABLE LIKE — source table not found");
            return;
        }
        const ds = try arena.create(Dataset);
        ds.* = Dataset.init(arena, name);
        for (src.?.columns.items) |c| _ = try ds.addColumnLike(c.name, c);
        try lib.put(name, ds);
        return;
    }
    if (atTag(stmt, i, .lparen)) {
        i += 1;
        const ds = try arena.create(Dataset);
        ds.* = Dataset.init(arena, name);
        // The paren body splits on top-level commas; each item is either a column
        // def (`x num [not null|primary key|unique|check(…)|references …]`) or a
        // table-level constraint clause (`[constraint name] primary key(…) |
        // unique(…) | check(…) | foreign key(…) references …`) — BUG-sqlconstraints:
        // these used to be parsed as COLUMNS literally named `constraint`/`primary`.
        const bstart = i;
        var depth: usize = 0;
        while (i < stmt.len and !(depth == 0 and stmt[i].tag == .rparen)) : (i += 1) {
            if (stmt[i].tag == .lparen) depth += 1 else if (stmt[i].tag == .rparen and depth > 0) depth -= 1;
        }
        var cons: std.ArrayList(Constraint) = .empty;
        for (try splitTopComma(arena, stmt[bstart..i])) |item|
            try parseColumnOrConstraint(arena, diags, ds, &cons, item);
        if (cons.items.len > 0) registerConstraints(ds, cons.items, diags);
        try lib.put(name, ds);
        return;
    }
    unsupported("PROC SQL: unsupported CREATE TABLE");
}

/// True for the first token of a table-level constraint clause.
fn isTableConstraintStart(tok: Token) bool {
    inline for (.{ "primary", "unique", "distinct", "check", "foreign" }) |kw|
        if (tkKw(tok, kw)) return true;
    return false;
}

/// True for a PROC SQL column type keyword (`num`, `char`, `date`, …).
fn isTypeKeyword(tok: Token) bool {
    inline for (.{ "num", "numeric", "char", "varchar", "character", "int", "integer", "smallint", "dec", "decimal", "float", "real", "double", "date", "time", "datetime" }) |kw|
        if (tkKw(tok, kw)) return true;
    return false;
}

/// True for the first token of a column-level constraint clause (it ends the
/// type region of a column def).
fn isColConstraintStart(tok: Token) bool {
    inline for (.{ "not", "primary", "unique", "distinct", "check", "references", "constraint" }) |kw|
        if (tkKw(tok, kw)) return true;
    return false;
}

fn oneCol(arena: std.mem.Allocator, name: []const u8) ![]const []const u8 {
    const out = try arena.alloc([]const u8, 1);
    out[0] = name;
    return out;
}

/// `( a , b )` at toks[i] → the column names; null (no advance) when not on '('.
fn parenColList(arena: std.mem.Allocator, toks: []const Token, i: *usize) !?[]const []const u8 {
    const inner = captureDsOpts(toks, i) orelse return null; // same balanced-paren capture
    var cols: std.ArrayList([]const u8) = .empty;
    for (try splitTopComma(arena, inner)) |span|
        if (span.len > 0 and span[0].tag == .name) try cols.append(arena, span[0].text);
    return cols.items;
}

/// Append a constraint after validating its columns exist in the schema — a
/// typo'd column must not silently drop the constraint (fail LOUD: one ERROR,
/// the constraint is skipped).
fn appendCheckedCons(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, cons: *std.ArrayList(Constraint), c: Constraint, line: usize) !void {
    for (c.cols) |cn| if (ds.indexOf(cn) == null) {
        try diags.report(.err, line, "PROC SQL: constraint references unknown column {s} in table {s}", .{ cn, ds.name });
        return;
    };
    try cons.append(arena, c);
}

/// Interpret one top-level-comma item of a CREATE TABLE (…) body: a column def
/// (add it to `ds`) or a table-level constraint clause (append to `cons`).
fn parseColumnOrConstraint(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, cons: *std.ArrayList(Constraint), item: []const Token) !void {
    if (item.len == 0) return;
    // `[constraint <name>] <clause>` — the name is metadata only; skip it.
    if (tkKw(item[0], "constraint")) {
        var i: usize = 1;
        if (atTag(item, i, .name)) i += 1;
        return parseTableConstraint(arena, diags, ds, cons, item[i..]);
    }
    if (isTableConstraintStart(item[0]))
        return parseTableConstraint(arena, diags, ds, cons, item);
    if (item[0].tag != .name) return; // a stray token — pre-fix code skipped these too
    const cname = item[0].text;
    // A duplicate column name is a malformed column list: fail LOUD at CREATE and
    // skip it — the old code added a second same-named column, and the corrupt
    // schema later panicked dataset.appendRow on INSERT (BUG-sqlcreatedupcol).
    if (ds.indexOf(cname) != null) {
        try diags.report(.err, item[0].line, "PROC SQL: duplicate column name {s} in CREATE TABLE {s}", .{ cname, ds.name });
        return;
    }
    var i: usize = 1;
    // type region: everything up to the first constraint keyword or column
    // modifier (`num`, `char(8)`, …). More than one type keyword in it
    // (`c num num`) is a stray extra token — fail LOUD and skip the item (same
    // BUG). Unknown trailing single names keep the old lenient skip, so
    // `double precision`-style phrases pass.
    var ty: VarType = .num;
    var width: ?usize = null; // declared char(n)/varchar(n) width (GAP-sqldatatypewidth)
    var type_kws: usize = 0;
    while (i < item.len and !isColConstraintStart(item[i]) and !isColModAt(item, i)) : (i += 1) {
        if (isTypeKeyword(item[i])) type_kws += 1;
        if (tkKw(item[i], "char") or tkKw(item[i], "varchar") or tkKw(item[i], "character")) {
            ty = .char;
            // `char ( n )` — the declared storage width. A numeric type's
            // `(p,s)` is precision/scale metadata: SAS stores every numeric as
            // a double regardless, so only char widths are captured.
            if (atTag(item, i + 1, .lparen) and atTag(item, i + 2, .number) and atTag(item, i + 3, .rparen))
                width = std.fmt.parseInt(usize, item[i + 2].text, 10) catch null;
        }
    }
    if (type_kws > 1) {
        try diags.report(.err, item[0].line, "PROC SQL: malformed column definition for {s} in CREATE TABLE {s} (unexpected extra type token)", .{ cname, ds.name });
        return;
    }
    const col_idx = try ds.addColumn(cname, ty);
    if (width) |w| ds.columns.items[col_idx].len = w;
    try parseColSuffix(arena, diags, ds, col_idx, cname, cons, item, i, item[0].line);
}

/// The column-def suffix after the type region: column-level constraint clauses
/// (`not null` / `primary key` / `unique` / `check(…)` / `references …`,
/// optionally `constraint <name>`-prefixed) and the `format=` / `informat=` /
/// `label=` column modifiers. BUG-sqlddlmed: the modifiers used to be silently
/// dropped — they now attach to the column like a data-step ATTRIB. Shared by
/// CREATE TABLE and ALTER TABLE ADD (which passes its type region too; bare
/// type tokens fall through the final skip).
fn parseColSuffix(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, col_idx: usize, cname: []const u8, cons: *std.ArrayList(Constraint), item: []const Token, start: usize, line: usize) !void {
    var i = start;
    while (i < item.len) {
        if (isColModAt(item, i)) { // format=/informat=/label= → attach to the column
            const kw = item[i].text;
            i += 2; // past the keyword and `=` (guaranteed progress)
            if (eqi(kw, "label")) {
                if (atTag(item, i, .string)) {
                    ds.columns.items[col_idx].label = item[i].text;
                    i += 1;
                }
            } else if (eqi(kw, "length")) {
                // LENGTH= is a SELECT-clause modifier, not a DDL column-def one —
                // skip the count (as before BUG-sqlselectlength) rather than let
                // captureFmtSpec swallow it into a bogus informat.
                if (atTag(item, i, .number)) i += 1;
            } else if (try captureFmtSpec(arena, item, &i)) |spec| {
                if (eqi(kw, "format")) ds.columns.items[col_idx].format = spec else ds.columns.items[col_idx].informat = spec;
            }
        } else if (tkKw(item[i], "constraint")) { // a named column-level clause — skip the name, the kind follows
            i += 1;
            if (atTag(item, i, .name)) i += 1;
        } else if (tkKw(item[i], "not") and atKw(item, i + 1, "null")) {
            try cons.append(arena, .{ .kind = .not_null, .cols = try oneCol(arena, cname) });
            i += 2;
        } else if (tkKw(item[i], "primary")) {
            i += 1;
            if (atKw(item, i, "key")) i += 1;
            try cons.append(arena, .{ .kind = .pk, .cols = try oneCol(arena, cname) });
        } else if (tkKw(item[i], "unique") or tkKw(item[i], "distinct")) {
            try cons.append(arena, .{ .kind = .unique, .cols = try oneCol(arena, cname) });
            i += 1;
        } else if (tkKw(item[i], "check")) {
            i += 1;
            try appendCheckCons(arena, diags, cons, captureDsOpts(item, &i), line);
        } else if (tkKw(item[i], "references")) {
            try cons.append(arena, try parseReferences(arena, item, &i, try oneCol(arena, cname)));
        } else i += 1; // a type-region token (num/char(8)/double precision/…) — skip
    }
}

/// A table-level constraint clause: `primary key (…)`, `unique (…)`/`distinct (…)`,
/// `check (…)`, or `foreign key (…) references <t> [(…)]`. Anything else fails loud.
fn parseTableConstraint(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, cons: *std.ArrayList(Constraint), toks: []const Token) !void {
    if (toks.len == 0) return;
    var i: usize = 1; // past the kind keyword
    if (tkKw(toks[0], "primary")) {
        if (atKw(toks, i, "key")) i += 1;
        if (try parenColList(arena, toks, &i)) |cols|
            try appendCheckedCons(arena, diags, ds, cons, .{ .kind = .pk, .cols = cols }, toks[0].line);
    } else if (tkKw(toks[0], "unique") or tkKw(toks[0], "distinct")) {
        if (try parenColList(arena, toks, &i)) |cols|
            try appendCheckedCons(arena, diags, ds, cons, .{ .kind = .unique, .cols = cols }, toks[0].line);
    } else if (tkKw(toks[0], "check")) {
        try appendCheckCons(arena, diags, cons, captureDsOpts(toks, &i), toks[0].line);
    } else if (tkKw(toks[0], "foreign")) {
        if (atKw(toks, i, "key")) i += 1;
        const cols = (try parenColList(arena, toks, &i)) orelse &.{};
        if (atKw(toks, i, "references")) {
            try appendCheckedCons(arena, diags, ds, cons, try parseReferences(arena, toks, &i, cols), toks[0].line);
        } else unsupported("PROC SQL: FOREIGN KEY without REFERENCES");
    } else unsupported("PROC SQL: unsupported CREATE TABLE constraint clause");
}

/// Store a CHECK constraint from its `( expr )` capture, after verifying the
/// predicate parses — silent acceptance of an unparseable one would let every
/// row pass (evalSpan maps a parse error to missing = UNKNOWN), so fail loud at
/// CREATE and skip the constraint.
fn appendCheckCons(arena: std.mem.Allocator, diags: *diag.Diagnostics, cons: *std.ArrayList(Constraint), pred: ?[]const Token, line: usize) !void {
    const p = pred orelse return;
    const desug = try desugarPredicates(arena, diags, p);
    var pp = pe.Parser.init(arena, try withEof(arena, desug), diags);
    _ = pp.parseExpr() catch {
        try diags.report(.err, line, "PROC SQL: unsupported CHECK predicate (not enforced)", .{});
        return;
    };
    try cons.append(arena, .{ .kind = .check, .pred = p });
}

/// Parse `references <table> [( <cols> )]` with toks[i] on `references` (advances
/// `i`). `child` is the child-side column list: the one defining column for the
/// column-level form, the FOREIGN KEY (…) list for the table-level form.
fn parseReferences(arena: std.mem.Allocator, toks: []const Token, i: *usize, child: []const []const u8) !Constraint {
    var c = Constraint{ .kind = .fk, .cols = child };
    i.* += 1; // past `references`
    if (atTag(toks, i.*, .name)) {
        c.ref_table = toks[i.*].text;
        i.* += 1;
    }
    if (try parenColList(arena, toks, i)) |rc| c.ref_cols = rc;
    return c;
}

/// `INSERT INTO n [(cols)] VALUES (…) [VALUES (…)…]` or `INSERT INTO n [(cols)]
/// <select>`. VALUES map to `cols` (or all columns, in order); a value/column
/// count mismatch — or an unknown target-list name — is an ERROR
/// (BUG-sqlddlmed: both used to silently drop/pad). SELECT rows append
/// positionally.
fn runInsert(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, stmt: []const Token) !void {
    var i: usize = 1;
    if (atKw(stmt, i, "into")) i += 1;
    const name = if (atTag(stmt, i, .name)) stmt[i].text else {
        unsupported("PROC SQL: INSERT without a table");
        return;
    };
    i += 1;
    const ds = lib.find(name) orelse {
        unsupported("PROC SQL: INSERT target not found");
        return;
    };
    var cols: std.ArrayList([]const u8) = .empty;
    if (atTag(stmt, i, .lparen)) {
        i += 1;
        while (i < stmt.len and stmt[i].tag != .rparen) : (i += 1)
            if (stmt[i].tag == .name) try cols.append(arena, stmt[i].text);
        if (atTag(stmt, i, .rparen)) i += 1;
        // BUG-sqlddlmed: a target-list name that isn't a column of the table is
        // the SAS "columns were not found" ERROR (mirrors UPDATE SET's check,
        // BUG-sqlupdatedropcol) — the old code silently dropped those values.
        for (cols.items) |cn|
            if (ds.indexOf(cn) == null)
                return diags.fail(error.ExecError, stmt[0].line, "PROC SQL: the following columns were not found in the contributing tables: {s}", .{cn});
    }
    if (atKw(stmt, i, "values")) {
        while (atKw(stmt, i, "values")) {
            i += 1;
            if (!(atTag(stmt, i, .lparen))) break;
            const startv = i + 1;
            var depth: usize = 1;
            var j = i + 1;
            while (j < stmt.len and depth > 0) : (j += 1) {
                if (stmt[j].tag == .lparen) depth += 1 else if (stmt[j].tag == .rparen) depth -= 1;
                if (depth == 0) break;
            }
            try insertRow(arena, lib, diags, ds, cols.items, stmt[startv..j]);
            i = j + 1;
        }
    } else if (atKw(stmt, i, "select")) {
        const res = applyOutobs((try execSelect(arena, lib, diags, stmt[i..])) orelse return); // OUTOBS= caps inserted rows (F2)
        for (res.rows) |row| {
            if (cols.items.len > 0) {
                // BUG-sqlinsertcollist: an explicit target list maps the i-th
                // SELECT result column to the i-th NAMED column (like VALUES);
                // unlisted columns stay missing.
                const cells = try arena.alloc(Value, ds.columns.items.len);
                for (ds.columns.items, 0..) |c, k| cells[k] = missingOf(c.type);
                for (row, 0..) |v, vi| {
                    const idx: ?usize = if (vi < cols.items.len) ds.indexOf(cols.items[vi]) else null;
                    // coerceToColumn, same as VALUES/UPDATE: a declared char(n)
                    // truncates the stored value (BUG-sqlinsertoverwidth).
                    if (idx) |ci| cells[ci] = try coerceToColumn(arena, diags, stmt[0].line, &ds.columns.items[ci], v);
                }
                if (try violatesConstraint(arena, lib, diags, ds, cells, null, stmt[0].line)) continue;
                try ds.appendRow(cells);
            } else {
                // BUG-sqlcreatedupcol: a ragged SELECT row (width ≠ the target
                // table's schema) must fail LOUD, not trip appendRow's assert.
                if (row.len != ds.columns.items.len) {
                    try diags.report(.err, stmt[0].line, "PROC SQL: INSERT into {s} — SELECT has {d} columns but the table has {d}", .{ name, row.len, ds.columns.items.len });
                    break;
                }
                // BUG-sqlinsertoverwidth: the SELECT form must store through the
                // SAME coerceToColumn as the VALUES form — the SQL volume's
                // INSERT section (pp.290-292) is silent on truncation, but a
                // stored cell wider than its own descriptor is not a doc
                // question (2a4a2b6a: "a descriptor must not disagree with the
                // cell it describes"): the DATA-step read clips to the declared
                // width (1dcc5b51) while PROC PRINT/EXPORT render the raw cell,
                // so an unclipped store makes the table disagree with itself
                // depending on the reader. Clip at the store and every surface
                // is right by construction.
                const cells = try arena.alloc(Value, ds.columns.items.len);
                for (row, 0..) |v, vi| cells[vi] = try coerceToColumn(arena, diags, stmt[0].line, &ds.columns.items[vi], v);
                if (try violatesConstraint(arena, lib, diags, ds, cells, null, stmt[0].line)) continue;
                try ds.appendRow(cells);
            }
        }
    } else unsupported("PROC SQL: INSERT expects VALUES or a SELECT");
}

/// SAS missing-ness for constraint purposes: numeric NaN, or an all-blank char
/// (a char has no missing value in SAS, but a blank violates NOT NULL / a key).
fn consMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trimEnd(u8, s, " ").len == 0,
    };
}

/// Check candidate row `cells` (aligned to `ds.columns`) against the table's
/// registered constraints (BUG-sqlconstraints). `skip` excludes one existing row
/// from the key scans (UPDATE's own pre-update row). Returns true — after
/// reporting one ERROR — when the row violates a constraint and must be
/// rejected (INSERT skips it, UPDATE keeps the original row).
fn violatesConstraint(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, ds: *Dataset, cells: []const Value, skip: ?usize, line: usize) !bool {
    const cons = constraintsOf(ds) orelse return false;
    for (cons) |c| {
        switch (c.kind) {
            .not_null => {
                const idx = ds.indexOf(c.cols[0]) orelse continue;
                if (consMissing(cells[idx])) {
                    try diags.report(.err, line, "Add/Update failed for data set {s} because data value(s) do not comply with integrity constraint: NOT NULL column {s} would be missing", .{ ds.name, c.cols[0] });
                    return true;
                }
            },
            .pk, .unique => {
                var idxs: std.ArrayList(usize) = .empty;
                var any_missing = false;
                for (c.cols) |cn| {
                    const idx = ds.indexOf(cn) orelse break;
                    if (consMissing(cells[idx])) any_missing = true;
                    try idxs.append(arena, idx);
                }
                if (idxs.items.len != c.cols.len) continue; // schema drift — not this table's constraint
                if (any_missing) {
                    if (c.kind == .pk) { // a PRIMARY KEY column is implicitly NOT NULL
                        try diags.report(.err, line, "Add/Update failed for data set {s} because data value(s) do not comply with integrity constraint: PRIMARY KEY column would be missing", .{ds.name});
                        return true;
                    }
                    continue; // UNIQUE: SQL lets any number of NULL/blank keys pass
                }
                for (ds.rows.items, 0..) |r, ri| {
                    if (skip) |s| if (ri == s) continue;
                    var all = true;
                    for (idxs.items) |ci| if (cmpVal(r[ci], cells[ci]) != .eq) {
                        all = false;
                        break;
                    };
                    if (all) {
                        try diags.report(.err, line, "Add/Update failed for data set {s} because data value(s) do not comply with integrity constraint: duplicate {s} value", .{ ds.name, if (c.kind == .pk) "PRIMARY KEY" else "UNIQUE" });
                        return true;
                    }
                }
            },
            .check => {
                var pdv = Pdv.init(arena);
                try loadForEval(&pdv, ds, cells);
                var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
                const v = try evalSpan(arena, diags, &ev, try desugarPredicates(arena, diags, c.pred));
                // SQL: a CHECK passes when the predicate is TRUE *or* UNKNOWN (missing)
                if (!v.isMissing() and !v.truthy()) {
                    try diags.report(.err, line, "Add/Update failed for data set {s} because data value(s) do not comply with integrity constraint: CHECK predicate failed", .{ds.name});
                    return true;
                }
            },
            .fk => {
                var childIdx: std.ArrayList(usize) = .empty;
                var cmiss = false;
                for (c.cols) |cn| {
                    const idx = ds.indexOf(cn) orelse break;
                    if (consMissing(cells[idx])) cmiss = true;
                    try childIdx.append(arena, idx);
                }
                if (childIdx.items.len != c.cols.len or cmiss) continue; // SQL: a NULL child key never violates the FK
                const rds = lib.find(c.ref_table) orelse {
                    try diags.report(.err, line, "Add/Update failed for data set {s}: FOREIGN KEY referenced table {s} not found", .{ ds.name, c.ref_table });
                    return true;
                };
                var refcols = c.ref_cols;
                if (refcols.len == 0) { // a bare `references t` names the parent's PRIMARY KEY
                    if (constraintsOf(rds)) |rcons| for (rcons) |rc| {
                        if (rc.kind == .pk) {
                            refcols = rc.cols;
                            break;
                        }
                    };
                    if (refcols.len == 0) {
                        try diags.report(.err, line, "Add/Update failed for data set {s}: FOREIGN KEY references {s} without columns and no PRIMARY KEY there", .{ ds.name, c.ref_table });
                        return true;
                    }
                }
                if (refcols.len != c.cols.len) {
                    try diags.report(.err, line, "Add/Update failed for data set {s}: FOREIGN KEY column count does not match the referenced columns", .{ds.name});
                    return true;
                }
                var ridx: std.ArrayList(usize) = .empty;
                var bad_ref = false;
                for (refcols) |cn| {
                    const idx = rds.indexOf(cn) orelse {
                        bad_ref = true;
                        break;
                    };
                    try ridx.append(arena, idx);
                }
                if (bad_ref) {
                    try diags.report(.err, line, "Add/Update failed for data set {s}: FOREIGN KEY referenced column not found in {s}", .{ ds.name, c.ref_table });
                    return true;
                }
                var found = false;
                for (rds.rows.items) |r| {
                    var all = true;
                    for (ridx.items, childIdx.items) |rci, cci| if (cmpVal(r[rci], cells[cci]) != .eq) {
                        all = false;
                        break;
                    };
                    if (all) {
                        found = true;
                        break;
                    }
                }
                if (!found) {
                    try diags.report(.err, line, "Add/Update failed for data set {s} because data value(s) do not comply with integrity constraint: FOREIGN KEY value not present in {s}", .{ ds.name, c.ref_table });
                    return true;
                }
            },
        }
    }
    return false;
}

/// BUG-sqltypeconsistency: a CHARACTER value stored into a NUMERIC column
/// (INSERT VALUES / UPDATE SET) converts the SAS way — implicit w. informat,
/// NOT an error and never the raw text in a num cell: blank → missing
/// silently; a special missing ('.K') → that missing; parseable → the number
/// with the "converted" NOTE; unparseable → missing after the "converted" +
/// "Invalid numeric data" NOTE pair (the same texts eval.zig's toNum logs).
/// GAP-sqlcolumnattr: an INFORMAT= attached at CREATE/ALTER is APPLIED to a
/// character value first (D-002: stored-but-ignored was the silent bug), with
/// the INPUT() function's exact semantics (functions.readInformat + the
/// $-name post-process): '15JAN2020' under date9. reads as the SAS day, 'abc'
/// under $upcase. stores 'ABC'. A type-mismatched informat (a numeric read
/// for a char column, a $ read for a num column) falls through to the generic
/// path. ponytail: SAS rejects a mismatched informat at CREATE; add that
/// check if a program hits it.
/// NOTE-invalidnumdataloc (GH#78): `line` is the REAL statement line the
/// caller already had in hand (tokens carry one; no column exists —
/// NOTE-arrayoorlineno); it rides the diag's line field, rendered "NOTE(L<n>):",
/// instead of the old frozen in-text "at line 0 column 0."
/// ponytail: num→char and INSERT…SELECT cell sinks are not coerced (no
/// reported divergence); route them through here if one appears.
fn coerceToColumn(arena: std.mem.Allocator, diags: *diag.Diagnostics, line: usize, c: *const Column, v: Value) diag.Error!Value {
    var val = v;
    if (c.informat) |inf| if (v == .str) {
        const read = functions.readInformat(inf, v.str);
        if (c.type == .num and read == .num) return read;
        if (c.type == .char and read == .str)
            val = .{ .str = try format.charInformat(arena, format.parseSpec(inf).name, read.str) };
    };
    if (c.type == .num and val == .str) {
        const s = val.str;
        const tr = std.mem.trim(u8, s, " ");
        if (tr.len == 0) return Value.missing;
        if (Value.parseSpecialMissing(tr)) |sm| return sm;
        diags.note(line, "Character values have been converted to numeric values at the places given by: (Line):(Column).", .{}) catch {};
        return if (sasParseFloat(tr)) |x| .{ .num = x } else blk: {
            diags.note(line, "Invalid numeric data, '{s}'.", .{s}) catch {};
            break :blk Value.missing;
        };
    }
    // GAP-sqldatatypewidth: a declared char(n)/varchar(n) width TRUNCATES a
    // too-long stored value (Language Reference: Concepts/SQL: the declared width IS the storage
    // length — SAS stores 'abcdef' into char(3) as 'abc'). Under-width values
    // stay unpadded: char storage is dynamic and comparisons trim trailing
    // blanks, so blank-padding would only churn goldens.
    if (c.type == .char and val == .str) if (c.len) |n| {
        if (val.str.len > n) val = .{ .str = val.str[0..n] };
    };
    return val;
}

fn insertRow(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, ds: *Dataset, cols: []const []const u8, valToks: []const Token) !void {
    const vals = try splitTopComma(arena, valToks);
    // BUG-sqlddlmed: SAS ERRORs when the VALUES count doesn't match the target
    // column count (the explicit list's, else the whole table's) — the old code
    // silently dropped extra values / padded a short row with missings.
    const want = if (cols.len > 0) cols.len else ds.columns.items.len;
    if (vals.len != want) {
        try diags.report(.err, if (valToks.len > 0) valToks[0].line else 0, "PROC SQL: INSERT into {s} — VALUES lists {d} value(s) for {d} targeted column(s)", .{ ds.name, vals.len, want });
        return;
    }
    const cells = try arena.alloc(Value, ds.columns.items.len);
    for (ds.columns.items, 0..) |c, k| cells[k] = missingOf(c.type);
    for (vals, 0..) |vspan, vi| {
        const idx: ?usize = if (cols.len > 0)
            (if (vi < cols.len) ds.indexOf(cols[vi]) else null)
        else
            (if (vi < ds.columns.items.len) vi else null);
        if (idx) |ci| cells[ci] = try coerceToColumn(arena, diags, if (valToks.len > 0) valToks[0].line else 0, &ds.columns.items[ci], try evalConst(arena, diags, vspan));
    }
    // BUG-sqlconstraints: a row that violates the table's constraints is
    // rejected (one ERROR) instead of appended.
    if (try violatesConstraint(arena, lib, diags, ds, cells, null, if (valToks.len > 0) valToks[0].line else 0)) return;
    try ds.appendRow(cells);
}

/// `UPDATE n SET c = expr [, …] [WHERE pred]`. Each row's assignments evaluate
/// against that row's original values (so `x = x + 1` reads the pre-update x).
fn runUpdate(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, stmt: []const Token) !void {
    var i: usize = 1;
    const name = if (atTag(stmt, i, .name)) stmt[i].text else {
        unsupported("PROC SQL: UPDATE without a table");
        return;
    };
    i += 1;
    const ds = lib.find(name) orelse {
        unsupported("PROC SQL: UPDATE target not found");
        return;
    };
    // optional `[as] alias` (`update m as x set …`) — needed so a correlated SET
    // subquery binds the outer row via `x.col` (ISS-sqlupdate #42). `set` is a
    // .name token, so guard against consuming it as the alias.
    var alias: ?[]const u8 = null;
    if (atKw(stmt, i, "as")) i += 1;
    if (atTag(stmt, i, .name) and !tkKw(stmt[i], "set")) {
        alias = stmt[i].text;
        i += 1;
    }
    if (!(atKw(stmt, i, "set"))) {
        unsupported("PROC SQL: UPDATE without SET");
        return;
    }
    i += 1;
    const setStart = i;
    // paren-aware SET/WHERE split — a `set c=(select … where …)` subquery holds its
    // own `where` inside parens, which must not end the SET clause (ISS-sqlupdate).
    var sdepth: usize = 0;
    while (i < stmt.len and !(sdepth == 0 and tkKw(stmt[i], "where"))) : (i += 1) {
        if (stmt[i].tag == .lparen) sdepth += 1 else if (stmt[i].tag == .rparen and sdepth > 0) sdepth -= 1;
    }
    const asgs = try splitTopComma(arena, stmt[setStart..i]);
    // A SET target naming no column of the table is the SAS "columns were not
    // found" ERROR — the per-row write lookup below (ds.indexOf) skips an
    // unknown name, so without this check a typo'd SET silently no-ops
    // (BUG-sqlupdatedropcol). Mirrors validateWhereCols (BUG-sqldmlwhere).
    for (asgs) |asg| {
        if (asg.len < 3 or asg[1].tag != .eq or asg[0].tag != .name) continue; // not `col = expr`
        if (ds.indexOf(asg[0].text) == null)
            return diags.fail(error.ExecError, asg[0].line, "PROC SQL: the following columns were not found in the contributing tables: {s}", .{asg[0].text});
    }
    var wtoks: ?[]const Token = null;
    if (atKw(stmt, i, "where")) {
        i += 1;
        wtoks = stmt[i..];
    }
    const target = if (wtoks) |w| try rowsMatching(arena, lib, diags, ds, w, name, alias) else try allRows(arena, ds);
    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    // PERF-sqlupdatecorr: a SET RHS that is exactly a correlated scalar subquery
    // `(select v from t where t.k = m.k)` reuses the SELECT list's hash path
    // (PERF-sqlcorrsubqsel): build the inner key→value map ONCE and probe per
    // row — O(N+M) instead of re-executing the inner query per target row
    // (O(N·M), 82 s/4.4 GB at N=20k). null → the correct per-row
    // substituteSubqueries path below (same scope as the SELECT fast path).
    const usels = try arena.alloc(?ScalarSel, asgs.len);
    for (asgs, 0..) |asg, ai| {
        usels[ai] = if (asg.len >= 3 and asg[1].tag == .eq and hasSubquery(asg[2..]))
            if (try detectScalarSubq(arena, lib, .{ .table = name, .alias = alias }, ds, asg[2..])) |sh| try buildScalarSel(arena, diags, sh) else null
        else
            null;
    }
    var pkb: std.ArrayList(u8) = .empty; // reused scalar-probe key buffer
    for (target) |ri| {
        try loadForEval(&pdv, ds, ds.row(ri));
        const cells = try arena.alloc(Value, ds.columns.items.len);
        @memcpy(cells, ds.row(ri));
        for (asgs, 0..) |asg, ai| {
            if (asg.len < 3 or asg[1].tag != .eq) continue; // col = expr
            if (usels[ai]) |sm| {
                // hash probe — same value the per-row path yields (first match /
                // empty-group fold / missing), see buildScalarSel.
                if (ds.indexOf(asg[0].text)) |ci| {
                    pkb.clearRetainingCapacity();
                    try appendCompositeKey(&pkb, arena, ds.row(ri), sm.ocols);
                    const pv = if (sm.ineq) |*iqsel| probeIneqSel(iqsel, pkb.items, toNum(ds.row(ri)[iqsel.ocol])) else sm.map.get(pkb.items) orelse sm.miss;
                    cells[ci] = try coerceToColumn(arena, diags, asg[0].line, &ds.columns.items[ci], pv);
                }
                continue;
            }
            // a `(select …)` scalar subquery RHS parser_expr can't parse — collapse
            // it to its value first, correlated to this row via the table alias
            // (ISS-sqlupdate #42); plain expressions pass through untouched.
            const rhs0 = if (hasSubquery(asg[2..]))
                try substituteSubqueries(arena, lib, diags, asg[2..], .{ .ds = ds, .ri = ri, .table = name, .alias = alias })
            else
                asg[2..];
            // parser_expr has no case-expr, so a `set x = case … end` would lex `case`
            // as a bare variable → missing (BUG-sqlupdatecase). Fold each CASE to its
            // per-row value first, mirroring the WHERE path / evalSpan; `ev` is already
            // bound to this row (loadForEval above), so column refs in arms resolve.
            const rhs = try substituteCase(arena, diags, &ev, rhs0);
            var p = pe.Parser.init(arena, try withEof(arena, rhs), diags);
            const e = p.parseExpr() catch continue;
            if (ds.indexOf(asg[0].text)) |ci| cells[ci] = try coerceToColumn(arena, diags, asg[0].line, &ds.columns.items[ci], try ev.eval(e));
        }
        // BUG-sqlconstraints: keep the original row when the update would
        // violate a constraint (its own pre-update row is excluded from key scans).
        if (try violatesConstraint(arena, lib, diags, ds, cells, ri, stmt[0].line)) continue;
        ds.rows.items[ri] = cells;
    }
}

/// `DELETE FROM n [WHERE pred]` — drop matching rows (all rows if no WHERE).
fn runDelete(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, stmt: []const Token) !void {
    var i: usize = 1;
    if (atKw(stmt, i, "from")) i += 1;
    // #61 (reverses #41/#53): real SAS 9.4 leniently ignores a stray `*` in
    // DELETE and executes the delete anyway. Treat `DELETE * FROM t` as
    // `DELETE FROM t`; emit a non-fatal note. Proof: a real SDTM LB program golden.
    if (atTag(stmt, i, .star)) {
        diags.note(0, "PROC SQL: '*' ignored in DELETE (SELECT-only syntax); deleting rows", .{}) catch {};
        i += 1;
        if (atKw(stmt, i, "from")) i += 1;
    }
    const name = if (atTag(stmt, i, .name)) stmt[i].text else {
        unsupported("PROC SQL: DELETE without a table");
        return;
    };
    i += 1;
    const ds = lib.find(name) orelse {
        unsupported("PROC SQL: DELETE target not found");
        return;
    };
    if (!(atKw(stmt, i, "where"))) {
        ds.rows = .empty; // DELETE FROM t; → remove every row
        return;
    }
    const drop = try rowsMatching(arena, lib, diags, ds, stmt[i + 1 ..], name, null);
    var keep: std.ArrayList([]const Value) = .empty;
    for (ds.rows.items, 0..) |r, ri| {
        var dropped = false;
        for (drop) |d| if (d == ri) {
            dropped = true;
            break;
        };
        if (!dropped) try keep.append(arena, r);
    }
    ds.rows = keep;
}

fn allRows(arena: std.mem.Allocator, ds: *Dataset) ![]const usize {
    var all: std.ArrayList(usize) = .empty;
    for (ds.rows.items, 0..) |_, ri| try all.append(arena, ri);
    return all.items;
}

/// Split a token span on top-level commas (parens respected).
fn splitTopComma(arena: std.mem.Allocator, toks: []const Token) ![]const []const Token {
    var out: std.ArrayList([]const Token) = .empty;
    var depth: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and toks[i].tag == .comma) {
            try out.append(arena, toks[start..i]);
            start = i + 1;
        }
    }
    if (start <= toks.len) try out.append(arena, toks[start..]);
    return out.items;
}

/// Evaluate a constant expression token span (VALUES / SET RHS with no row).
fn evalConst(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token) diag.Error!Value {
    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    var p = pe.Parser.init(arena, try withEof(arena, toks), diags);
    const e = p.parseExpr() catch return Value.missing;
    return ev.eval(e);
}

// ── query parsing ────────────────────────────────────────────────────────────

/// A keyword that can legally follow the FROM table (so a bare name here is a
/// join/clause start, not a table alias).
fn followsFromKw(tok: Token) bool {
    inline for (.{ "where", "group", "order", "having", "join", "inner", "left", "right", "full", "cross", "on", "union", "intersect", "except" }) |kw|
        if (tkKw(tok, kw)) return true;
    return false;
}

/// A `(` immediately after a FROM/JOIN table NAME is a dataset-option list — a
/// subquery would have REPLACED the name, so here it can only be options (GH#33).
/// Returns the tokens BETWEEN the parens (what io.applyDatasetOptions expects)
/// and advances `i` past the closing `)`. Null if not on a `(` (or unbalanced —
/// downstream parsing then errors).
fn captureDsOpts(toks: []const Token, i: *usize) ?[]const Token {
    if (i.* >= toks.len or toks[i.*].tag != .lparen) return null;
    const start = i.* + 1;
    var depth: usize = 0;
    var j = i.*;
    while (j < toks.len) : (j += 1) {
        if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
            depth -= 1;
            if (depth == 0) break;
        }
    }
    if (j >= toks.len) return null; // unbalanced
    i.* = j + 1; // past ')'
    return toks[start..j];
}

/// Apply a FROM/JOIN table's dataset options to a COPY (never the live library
/// dataset — mutating it would corrupt later reads) via the shared DATA-step
/// implementation, so where=/keep=/drop=/rename=/obs=/firstobs= all behave
/// exactly as they do on a SET (GH#33). No opts → the source, untouched.
fn withOptions(arena: std.mem.Allocator, diags: *diag.Diagnostics, src: *Dataset, opts: ?[]const Token) !*Dataset {
    // F3: INOBS= caps rows READ from EACH source table. This is the one choke point
    // every FROM/JOIN/dict source load routes through, so the cap lands once here.
    // No opts and no INOBS → the source, untouched.
    if (opts == null and g_opts.inobs == null) return src;
    const cp = try arena.create(Dataset);
    cp.* = Dataset.init(arena, src.name);
    for (src.columns.items) |c| try cp.columns.append(arena, c);
    try cp.rows.appendSlice(arena, src.rows.items); // shares Value cells; option funcs never mutate them
    if (g_opts.inobs) |n| if (cp.rows.items.len > n) cp.rows.shrinkRetainingCapacity(n); // read only the first N
    if (opts) |ot|
        try io.applyDatasetOptions(arena, cp, ot, diags, true); // FROM/JOIN is INPUT: DKRICOND=ERROR (GH#71)
    return cp;
}

fn parseQuery(arena: std.mem.Allocator, toks: []const Token) !Query {
    var q = Query{};
    var i: usize = 0;
    if (!(atKw(toks, i, "select"))) return error.ParseError;
    i += 1;

    if (atKw(toks, i, "distinct")) {
        q.distinct = true;
        i += 1;
    }

    if (atTag(toks, i, .star)) {
        q.star = true;
        i += 1;
    } else {
        var items: std.ArrayList(Item) = .empty;
        while (i < toks.len and !tkKw(toks[i], "from") and !tkKw(toks[i], "into")) {
            const parsed = try parseItem(arena, toks, i);
            try items.append(arena, parsed.item);
            i = parsed.next;
            if (atTag(toks, i, .comma)) i += 1;
        }
        q.items = try items.toOwnedSlice(arena);
    }

    // `INTO :v1 [, :v2 …] [SEPARATED BY 'delim']` — bind query values to macro vars
    // (BUG-sqlintomacro). The write happens in execSelect once the result exists.
    if (atKw(toks, i, "into")) {
        i += 1;
        var names: std.ArrayList([]const u8) = .empty;
        while (atTag(toks, i, .colon)) {
            i += 1; // ':'
            if (!(atTag(toks, i, .name))) return error.ParseError;
            const base = toks[i].text;
            i += 1;
            // numbered range `:v1-:vn` → expand base..hi (values go down the column)
            if (atTag(toks, i, .minus) and atTag(toks, i + 1, .colon) and atTag(toks, i + 2, .name)) {
                try expandNumRange(arena, &names, base, toks[i + 2].text);
                q.into_range = true;
                i += 3;
            } else try names.append(arena, base);
            if (atTag(toks, i, .comma)) {
                i += 1;
                continue;
            }
            break;
        }
        if (atKw(toks, i, "separated")) {
            i += 1;
            if (atKw(toks, i, "by")) i += 1;
            if (atTag(toks, i, .string)) {
                q.into_sep = toks[i].text;
                i += 1;
            }
        }
        q.into = try names.toOwnedSlice(arena);
    }

    if (!(atKw(toks, i, "from"))) return error.ParseError;
    i += 1;
    if (atTag(toks, i, .lparen)) {
        // `from (SELECT …)` — a derived table: capture the balanced-paren subquery
        // tokens; execQuery materializes them and runs the outer query against the
        // result (BUG-sqlderivedtable).
        const sub_start = i + 1;
        var depth: usize = 0;
        while (i < toks.len) : (i += 1) {
            if (toks[i].tag == .lparen) depth += 1
            else if (toks[i].tag == .rparen) {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        if (i >= toks.len) return error.ParseError; // unbalanced
        q.from_sub = toks[sub_start..i];
        i += 1; // past ')'
    } else if (atTag(toks, i, .name)) {
        q.table = toks[i].text;
        i += 1;
        q.from_opts = captureDsOpts(toks, &i); // `from T(where=/keep=/…)` — GH#33
    } else return error.ParseError;

    // optional table alias `from T [as] X` — needed so a correlated subquery can
    // bind the outer row via `X.col` and resolve its own `X.col` (BUG-sqlcorrscalar).
    if (atKw(toks, i, "as")) i += 1;
    if (atTag(toks, i, .name) and !followsFromKw(toks[i])) {
        q.alias = toks[i].text;
        i += 1;
    }

    // one or more joins: `, T` / `cross join T` / `[inner|left [outer]] join T on <cond>`
    var joins: std.ArrayList(JoinStep) = .empty;
    while (i < toks.len) {
        var kind: @TypeOf(@as(JoinStep, undefined).kind) = undefined;
        var needs_on = false;
        if (toks[i].tag == .comma) {
            kind = .cross;
            i += 1;
        } else if (tkKw(toks[i], "cross")) {
            kind = .cross;
            i += 1;
            if (atKw(toks, i, "join")) i += 1;
        } else if (tkKw(toks[i], "inner") or tkKw(toks[i], "left") or tkKw(toks[i], "right") or tkKw(toks[i], "full") or tkKw(toks[i], "join")) {
            kind = .inner;
            needs_on = true;
            if (tkKw(toks[i], "left") or tkKw(toks[i], "right") or tkKw(toks[i], "full")) {
                kind = if (tkKw(toks[i], "left")) .left else if (tkKw(toks[i], "right")) .right else .full;
                i += 1;
                if (atKw(toks, i, "outer")) i += 1; // optional OUTER
            } else if (tkKw(toks[i], "inner")) i += 1;
            if (!(atKw(toks, i, "join"))) return error.ParseError;
            i += 1;
        } else break;

        // The joined term is either a table name or an inline view `(select …)`.
        // Capture the balanced-paren subquery the same way the FROM clause does
        // (GH#14) — materialized in buildJoin.
        var tn: []const u8 = "";
        var sub: ?[]const Token = null;
        var topts: ?[]const Token = null;
        if (atTag(toks, i, .lparen)) {
            const sub_start = i + 1;
            var depth: usize = 0;
            while (i < toks.len) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            if (i >= toks.len) return error.ParseError; // unbalanced
            sub = toks[sub_start..i];
            i += 1; // past ')'
        } else if (atTag(toks, i, .name)) {
            tn = toks[i].text;
            i += 1;
            topts = captureDsOpts(toks, &i); // `join T(where=/keep=/…)` — GH#33
        } else return error.ParseError;
        // optional `[as] alias` on the joined table (BUG-sqljoinalias) — required
        // for self-joins; an alias hides the table name, so columns qualify by it.
        var talias: ?[]const u8 = null;
        if (atKw(toks, i, "as")) i += 1;
        if (atTag(toks, i, .name) and !followsFromKw(toks[i])) {
            talias = toks[i].text;
            i += 1;
        }
        if (sub != null and talias == null) return error.ParseError; // a derived table needs an alias to qualify its columns
        var on: ?[]const Token = null;
        if (needs_on) {
            if (!(atKw(toks, i, "on"))) return error.ParseError;
            i += 1;
            const s = i;
            while (i < toks.len and !tkKw(toks[i], "where") and !tkKw(toks[i], "group") and
                !tkKw(toks[i], "order") and !tkKw(toks[i], "inner") and !tkKw(toks[i], "left") and
                !tkKw(toks[i], "right") and !tkKw(toks[i], "full") and
                !tkKw(toks[i], "cross") and !tkKw(toks[i], "join") and toks[i].tag != .comma) i += 1;
            on = toks[s..i];
        }
        try joins.append(arena, .{ .kind = kind, .table = tn, .alias = talias, .on = on, .from_sub = sub, .opts = topts });
    }
    q.joins = try joins.toOwnedSlice(arena);

    while (i < toks.len) {
        if (tkKw(toks[i], "where")) {
            i += 1;
            const s = i;
            // A subquery's own GROUP BY/HAVING/ORDER BY lives inside parens — only a
            // clause keyword at paren depth 0 ends this WHERE (BUG-sqlsubqnest).
            var depth: usize = 0;
            while (i < toks.len and !(depth == 0 and (tkKw(toks[i], "group") or tkKw(toks[i], "having") or tkKw(toks[i], "order")))) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen and depth > 0) depth -= 1;
            }
            q.where = toks[s..i];
        } else if (tkKw(toks[i], "group")) {
            i += 1;
            if (atKw(toks, i, "by")) i += 1;
            // each GROUP BY term is a token span (a column or a whole expression),
            // split on top-level commas — BUG-groupexpr
            var exprs: std.ArrayList([]const Token) = .empty;
            var depth: usize = 0;
            var start2 = i;
            while (i < toks.len and !(depth == 0 and (tkKw(toks[i], "having") or tkKw(toks[i], "order")))) : (i += 1) {
                if (toks[i].tag == .lparen or tkKw(toks[i], "case")) depth += 1 else if (toks[i].tag == .rparen or tkKw(toks[i], "end")) {
                    if (depth > 0) depth -= 1;
                } else if (depth == 0 and toks[i].tag == .comma) {
                    if (i > start2) try exprs.append(arena, toks[start2..i]);
                    start2 = i + 1;
                }
            }
            if (i > start2) try exprs.append(arena, toks[start2..i]);
            q.group_exprs = try exprs.toOwnedSlice(arena);
        } else if (tkKw(toks[i], "having")) {
            i += 1;
            const s = i;
            var depth: usize = 0; // a subquery's ORDER BY is inside parens (BUG-sqlsubqnest)
            while (i < toks.len and !(depth == 0 and tkKw(toks[i], "order"))) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen and depth > 0) depth -= 1;
            }
            q.having = toks[s..i];
        } else if (tkKw(toks[i], "order")) {
            i += 1;
            if (atKw(toks, i, "by")) i += 1;
            var ords: std.ArrayList(Order) = .empty;
            while (i < toks.len) {
                // Capture one ORDER BY term as a whole token span (paren/CASE aware),
                // up to a top-level comma or a trailing ASC/DESC — then classify it.
                // A bare expression (`10-x`, `abs(x)`, `a+b`) becomes `expr_toks`,
                // evaluated per output row at sort time (BUG-sqlorderexpr); the old
                // token-by-token loop split it into phantom per-token keys.
                const start = i;
                var depth: usize = 0;
                while (i < toks.len) : (i += 1) {
                    const tk = toks[i];
                    if (tk.tag == .lparen or tkKw(tk, "case")) depth += 1 else if (tk.tag == .rparen or tkKw(tk, "end")) {
                        if (depth > 0) depth -= 1;
                    } else if (depth == 0 and (tk.tag == .comma or tkKw(tk, "asc") or tkKw(tk, "desc"))) break;
                }
                const span = toks[start..i];
                if (span.len > 0) try ords.append(arena, classifyOrder(q, span));
                // trailing ASC/DESC applies to the just-parsed term, then the comma
                if (i < toks.len and tkKw(toks[i], "desc")) {
                    if (ords.items.len > 0) ords.items[ords.items.len - 1].desc = true;
                    i += 1;
                } else if (i < toks.len and tkKw(toks[i], "asc")) i += 1;
                if (i < toks.len and toks[i].tag == .comma) i += 1;
            }
            q.order = try ords.toOwnedSlice(arena);
        } else i += 1;
    }
    return q;
}

/// Classify one ORDER BY term (its whole token span, without any trailing
/// ASC/DESC) into an `Order`: a positional `<n>`, a `case … end`, a matched
/// `agg(col|*)`, a bare column, or (the general case) an arbitrary expression
/// evaluated per output row at sort time — BUG-sqlorderexpr.
fn classifyOrder(q: Query, span: []const Token) Order {
    if (span.len == 1 and span[0].tag == .number) {
        // ORDER BY <n> — the n-th SELECT column (1-based) — BUG-orderbypos
        const n = std.fmt.parseInt(usize, span[0].text, 10) catch 0;
        return .{ .idx = if (n > 0) n - 1 else null };
    }
    if (isPureCase(span)) return .{ .case_toks = span[1 .. span.len - 1] }; // BUG-ordercase
    if (isPureAgg(span) and aggOf(span[0].text) != null) {
        // ORDER BY <agg(col|*)> — match it to a SELECT item — BUG-orderbyagg.
        // Only the simple `agg(*)` / `agg(col)` forms match; a compound arg falls
        // through to the per-row expression path below.
        const arg = span[2 .. span.len - 1];
        if (arg.len == 1 and arg[0].tag == .star)
            return .{ .idx = matchAggItem(q.items, aggOf(span[0].text).?, true, "") };
        if (arg.len == 1 and arg[0].tag == .name)
            return .{ .idx = matchAggItem(q.items, aggOf(span[0].text).?, false, arg[0].text) };
    }
    if (span.len == 1 and span[0].tag == .name) return .{ .col = span[0].text };
    return .{ .expr_toks = span };
}

/// True when `toks[i]` begins a SELECT column-attribute modifier (`format=`/
/// `informat=`/`label=`/`length=`) — a `name` keyword immediately followed by
/// `=` (BUG-sqlselectmodifier, BUG-sqlselectlength). These end the value span
/// and attach to the item.
fn isColModAt(toks: []const Token, i: usize) bool {
    return i < toks.len and toks[i].tag == .name and atTag(toks, i + 1, .eq) and
        (eqi(toks[i].text, "format") or eqi(toks[i].text, "informat") or eqi(toks[i].text, "label") or eqi(toks[i].text, "length"));
}

/// Rebuild a format/informat spec from its tokens at `*i` (advancing past them):
/// `dollar10.2` lexes as name(`dollar10`)+number(`.2`), `best18.` as name+dot, a
/// leading `$`, a plain `8.` as number+dot. Mirrors main.zig's fmtSpecToks.
fn captureFmtSpec(arena: std.mem.Allocator, toks: []const Token, i: *usize) !?[]const u8 {
    var j = i.*;
    var buf: std.ArrayList(u8) = .empty;
    if (j < toks.len and toks[j].tag == .dollar) {
        try buf.append(arena, '$');
        j += 1;
    }
    if (j < toks.len and toks[j].tag == .name) {
        try buf.appendSlice(arena, toks[j].text);
        j += 1;
    }
    if (j < toks.len and toks[j].tag == .number) {
        try buf.appendSlice(arena, toks[j].text); // number text carries its own leading `.`
        j += 1;
    }
    if (j < toks.len and toks[j].tag == .dot) {
        try buf.append(arena, '.');
        j += 1;
    }
    if (buf.items.len == 0) return null;
    i.* = j;
    return buf.items;
}

fn parseItem(arena: std.mem.Allocator, toks: []const Token, start: usize) !struct { item: Item, next: usize } {
    // capture the value span up to a top-level `as`/`,`/`from` or a `format=`/
    // `informat=`/`label=` modifier (paren & CASE aware)
    var i = start;
    var depth: usize = 0;
    while (i < toks.len) : (i += 1) {
        const tk = toks[i];
        if (tk.tag == .lparen or tkKw(tk, "case")) depth += 1 else if (tk.tag == .rparen or tkKw(tk, "end")) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and (tk.tag == .comma or tkKw(tk, "from") or tkKw(tk, "as") or tkKw(tk, "into") or isColModAt(toks, i))) break;
    }
    const span = toks[start..i];

    var item = Item{};
    if (atKw(toks, i, "as")) { // optional `as alias`
        i += 1;
        if (atTag(toks, i, .name)) {
            item.alias = toks[i].text;
            i += 1;
        }
    }
    // trailing column-attribute modifiers (BUG-sqlselectmodifier): consume onto
    // the item so no phantom `_colN` is produced and format=/label= reach output.
    while (isColModAt(toks, i)) {
        const kw = toks[i].text;
        i += 2; // past the keyword and `=`
        if (eqi(kw, "label")) {
            if (!atTag(toks, i, .string)) return error.ParseError;
            item.label = toks[i].text;
            i += 1;
        } else if (eqi(kw, "length")) { // BUG-sqlselectlength: a bare byte count
            if (!atTag(toks, i, .number)) return error.ParseError;
            item.length = std.fmt.parseInt(usize, toks[i].text, 10) catch return error.ParseError;
            i += 1;
        } else {
            const spec = (try captureFmtSpec(arena, toks, &i)) orelse return error.ParseError;
            if (eqi(kw, "format")) item.format = spec else item.informat = spec;
        }
    }
    if (span.len == 0) return error.ParseError;

    // A qualified star `alias.*` (name·dot·star — coalesceDots only folds name·dot·name,
    // so it survives as three tokens) or a bare `*` mid-list expands at exec time to
    // the matching source columns (ISS-sqlaliasstar).
    if (span.len == 1 and span[0].tag == .star) {
        item.is_star = true;
    } else if (span.len == 3 and span[0].tag == .name and span[1].tag == .dot and span[2].tag == .star) {
        item.is_star = true;
        item.star_qual = span[0].text;
    } else if (span.len == 1 and span[0].tag == .name) {
        item.col = span[0].text; // a bare column
    } else if (tkKw(span[0], "case") and isPureCase(span)) {
        item.case_toks = span[1 .. span.len - 1]; // between `case` and `end`
    } else if (isPureAgg(span) and aggAt(span, 0) != null) {
        // single-arg summary aggregate; a multi-arg call (aggAt == null) falls
        // through to expr_toks — the per-row DATA-step function (median(x,y) etc.)
        item.agg = aggAt(span, 0);
        var arg = span[2 .. span.len - 1]; // between the agg's parens
        if (arg.len >= 1 and tkKw(arg[0], "distinct")) {
            item.agg_distinct = true;
            arg = arg[1..];
        }
        if (arg.len == 1 and arg[0].tag == .star) {
            item.agg_star = true;
        } else if (arg.len == 1 and arg[0].tag == .name) {
            item.col = arg[0].text; // simple column — fast path
        } else {
            item.agg_arg = arg; // compound expression — evaluated per row then folded
        }
    } else {
        item.expr_toks = span; // arbitrary expression — evaluated per row
    }
    return .{ .item = item, .next = i };
}

/// True when `span` is exactly one `case … end` (its `case` closes at the last token).
fn isPureCase(span: []const Token) bool {
    if (span.len < 2 or !tkKw(span[0], "case")) return false;
    var depth: usize = 0;
    for (span, 0..) |tk, k| {
        if (tkKw(tk, "case")) depth += 1 else if (tkKw(tk, "end")) {
            depth -= 1;
            if (depth == 0) return k == span.len - 1;
        }
    }
    return false;
}

/// True when `span` is exactly one `agg(…)` call — the `(` after the function
/// name matches the last token — so agg(col), agg(*) and agg(price*qty) all
/// qualify but `sum(a)+1` / `sum(a)+sum(b)` do not (BUG-sqlaggexpr).
fn isPureAgg(span: []const Token) bool {
    if (span.len < 4 or span[0].tag != .name or aggOf(span[0].text) == null or span[1].tag != .lparen) return false;
    var depth: usize = 0;
    for (span[1..], 1..) |tk, k| {
        if (tk.tag == .lparen) {
            depth += 1;
        } else if (tk.tag == .rparen) {
            depth -= 1;
            if (depth == 0) return k == span.len - 1; // pure iff it closes at the last token
        }
    }
    return false;
}

/// True if `toks` contains an aggregate call anywhere — an aggregate name directly
/// followed by `(`. Used to detect an aggregate NESTED in an outer expression
/// (`sum(v)+10`, `max(v)-min(v)`), which must still collapse to one row per group
/// (BUG-sqlaggouter).
fn exprHasAgg(toks: []const Token) bool {
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        // skip a nested `( select … )` subquery — its aggregates are its own, not the
        // outer query's (a correlated scalar subquery must stay per-row).
        if (toks[i].tag == .lparen and atKw(toks, i + 1, "select")) {
            var depth: usize = 0;
            while (i < toks.len) : (i += 1) {
                if (toks[i].tag == .lparen) {
                    depth += 1;
                } else if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            continue;
        }
        if (aggAt(toks, i) != null) return true; // single-arg summary aggregate
    }
    return false;
}

/// True when `name` is a single-name GROUP BY term — constant per group, so a BARE
/// selection of it collapses normally and never forces a remerge. `gexprs` are the
/// RESOLVED group expressions (aliases/positionals already expanded).
fn isGroupTerm(gexprs: []const []const Token, name: []const u8) bool {
    for (gexprs) |g|
        if (g.len == 1 and g[0].tag == .name and eqi(unqualify(g[0].text), name)) return true;
    return false;
}

/// True when `name` appears as a name token anywhere inside a resolved GROUP BY
/// expression (e.g. `dt` within `group by year(dt)`, `v` within `group by (v>10)`,
/// `age` within a CASE grouped by its alias). A select EXPRESSION built only from
/// grouped columns is constant per group → not detail. (Subsumes isGroupTerm.)
fn inGroupExpr(gexprs: []const []const Token, name: []const u8) bool {
    for (gexprs) |g|
        for (g) |tk|
            if (tk.tag == .name and eqi(unqualify(tk.text), name)) return true;
    return false;
}

/// True when `toks` references a non-summarized detail column: a column name that
/// is NOT an aggregate argument and NOT covered by the GROUP BY (e.g. `sal` inside
/// `sal/sum(sal)` grouped by dept). Aggregate calls and nested subqueries are
/// skipped whole — the former summarize their args, the latter own their columns
/// (BUG-sqlexprdetailremerge).
fn exprHasDetailCol(toks: []const Token, gexprs: []const []const Token, ds: *Dataset) bool {
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        // skip a nested `( select … )` subquery whole — its columns are its own
        if (toks[i].tag == .lparen and atKw(toks, i + 1, "select")) {
            var depth: usize = 0;
            while (i < toks.len) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            continue;
        }
        // skip an aggregate call and its (summarized) arguments whole
        if (aggAt(toks, i) != null) {
            i += 1; // now at '('
            var depth: usize = 0;
            while (i < toks.len) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            continue;
        }
        if (toks[i].tag != .name) continue;
        if (atTag(toks, i + 1, .lparen)) continue; // a function name, not a column
        const name = unqualify(toks[i].text);
        if (resolveCol(ds, name) == null) continue; // keyword/alias, not a real column
        if (!inGroupExpr(gexprs, name)) return true;
    }
    return false;
}

/// True when the select list has a non-summarized detail column — the trigger for
/// SAS remerge. A BARE column (BUG-sqlremergedetail/BUG-sqlgroupremerge) or a column
/// referenced inside an EXPRESSION/CASE (`sal/sum(sal)`, BUG-sqlexprdetailremerge),
/// as long as it is not covered by the GROUP BY (constant per group → collapses).
/// Detection uses the RESOLVED group expressions so `group by <alias>` / `group by n`
/// / `group by calculated x` match. A bare column must BE a single-name group key to
/// collapse; a column inside an expression need only be COVERED by the grouping
/// (selecting `year(dt)` while grouped by `year(dt)` collapses, but bare `dt` remerges).
/// With no GROUP BY the whole table is one group, so any detail column qualifies.
fn hasDetailCol(arena: std.mem.Allocator, q: Query, ds: *Dataset) !bool {
    const gexprs = try resolveGroupAliases(arena, q);
    for (q.items) |it| {
        if (it.agg != null) continue; // a pure aggregate item is summarized
        if (it.expr_toks) |et| {
            if (exprHasDetailCol(et, gexprs, ds)) return true;
        } else if (it.case_toks) |ct| {
            if (exprHasDetailCol(ct, gexprs, ds)) return true;
        } else if (it.col) |c| {
            if (!isGroupTerm(gexprs, unqualify(c))) return true;
        }
    }
    return false;
}

// ── execution ────────────────────────────────────────────────────────────────

const SetKind = enum { union_, intersect, except, outer_union };
const SetOp = struct { kind: SetKind, all: bool, corr: bool = false };

/// Run a SELECT that may combine arms with `UNION`/`INTERSECT`/`EXCEPT [ALL]`.
/// Arms split at top level and fold left-to-right by their operator; each op
/// de-duplicates the running result unless `ALL` was given. A trailing
/// `ORDER BY` (on the last arm) orders the whole combined result.
/// Expand a numbered macro range `:v1-:vn` (shared prefix, trailing integers) into
/// the individual target names v1,v2,…,vn. A non-numeric endpoint falls back to the
/// single low name.
fn expandNumRange(arena: std.mem.Allocator, names: *std.ArrayList([]const u8), lo: []const u8, hi: []const u8) !void {
    const digits = struct {
        fn start(s: []const u8) usize {
            var k = s.len;
            while (k > 0 and s[k - 1] >= '0' and s[k - 1] <= '9') k -= 1;
            return k;
        }
    }.start;
    const p = digits(lo);
    const start = std.fmt.parseInt(usize, lo[p..], 10) catch return names.append(arena, lo);
    const end = std.fmt.parseInt(usize, hi[digits(hi)..], 10) catch return names.append(arena, lo);
    var k = start;
    while (k <= end) : (k += 1) try names.append(arena, try std.fmt.allocPrint(arena, "{s}{d}", .{ lo[0..p], k }));
}

/// Write query values into the `INTO :` macro targets. Each value is blank-trimmed
/// (SAS default). SEPARATED BY joins a column down its rows; a `:v1-:vn` range walks
/// column 0 down its rows; otherwise the targets take the first row across columns.
fn writeInto(arena: std.mem.Allocator, lib: *Library, q: Query, res: Result) !void {
    if (res.rows.len == 0) return; // no rows -> targets left unset (as SAS)
    const trimmed = struct {
        fn f(al: std.mem.Allocator, v: Value) ![]const u8 {
            return std.mem.trim(u8, try cellText(al, v), " ");
        }
    }.f;
    if (q.into_sep) |sep| {
        for (q.into, 0..) |name, ci| {
            if (ci >= res.cols.len) break;
            var buf: std.ArrayList(u8) = .empty;
            for (res.rows, 0..) |row, ri| {
                if (ri > 0) try buf.appendSlice(arena, sep);
                try buf.appendSlice(arena, try trimmed(arena, row[ci]));
            }
            try lib.setMacroVar(name, buf.items);
        }
    } else if (q.into_range) {
        for (q.into, 0..) |name, ri| {
            if (ri >= res.rows.len) break;
            try lib.setMacroVar(name, try trimmed(arena, res.rows[ri][0]));
        }
    } else {
        for (q.into, 0..) |name, ci| {
            if (ci >= res.cols.len) break;
            try lib.setMacroVar(name, try trimmed(arena, res.rows[0][ci]));
        }
    }
}

/// Rows the last SELECT processed — captured here (not from the returned Result)
/// because a `SELECT … INTO` returns null to suppress its print, yet &SQLOBS must
/// still report the rows it selected (BUG-sqlobs).
var g_select_rows: usize = 0;

fn execSelect(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, toks: []const Token) diag.Error!?Result {
    g_select_rows = 0;
    const split = try splitSetOps(arena, toks);
    if (split.arms.len == 1) {
        const q = parseQuery(arena, toks) catch {
            unsupported("PROC SQL: unsupported SELECT");
            return null;
        };
        var res = try execQuery(arena, lib, diags, q);
        g_select_rows = if (res) |r| r.rows.len else 0;
        if (q.into.len > 0) { // SELECT … INTO :mac — bind macro vars, suppress the print
            if (res) |r| try writeInto(arena, lib, q, r);
            return null;
        }
        if (res) |*r| applyLens(r);
        return res;
    }
    // BUG-sqlsetprec: INTERSECT binds TIGHTER than UNION/EXCEPT/OUTER UNION, so a
    // strict left-to-right fold is wrong. Fold in two tiers: first collapse each
    // maximal INTERSECT run into one term (`cur`), then fold the resulting terms
    // left-to-right by the remaining (lower-precedence) operators. Equal-precedence
    // operators still go left to right.
    var final_order: []const Order = &.{}; // trailing ORDER BY belongs to the whole set
    var terms: std.ArrayList(Result) = .empty;
    var low_ops: std.ArrayList(SetOp) = .empty;
    var cur: ?Result = null;
    for (split.arms, 0..) |arm, idx| {
        const q = parseQuery(arena, arm) catch {
            unsupported("PROC SQL: unsupported SELECT");
            return null;
        };
        final_order = q.order; // the last arm carries the set-wide ORDER BY
        const res = (try execQuery(arena, lib, diags, q)) orelse continue;
        if (cur == null) {
            cur = res;
            continue;
        }
        const op = split.ops[idx - 1];
        if (op.kind == .intersect) {
            cur = try combineSetOp(arena, cur.?, res, op); // high precedence: bind now
        } else {
            try terms.append(arena, cur.?);
            try low_ops.append(arena, op);
            cur = res;
        }
    }
    if (cur) |c| try terms.append(arena, c);
    var result: ?Result = if (terms.items.len > 0) terms.items[0] else null;
    for (low_ops.items, 1..) |op, ti| result = try combineSetOp(arena, result.?, terms.items[ti], op);
    var out = result orelse return null;
    try orderRows(arena, diags, &out, final_order, null, null); // BUG-unionorder: order the combined result
    applyLens(&out);
    g_select_rows = out.rows.len;
    return out;
}

/// Combine two SELECT results by one set operator. `left`'s columns and row
/// order are kept. For `ALL`, the ANSI multiset rules apply per value:
/// INTERSECT ALL keeps min(countA, countB); EXCEPT ALL keeps max(0, countA−countB)
/// — realised by CONSUMING a distinct right match per left row (BUG-sqlsetopall).
/// Without `ALL` the result is deduped to distinct values.
/// Pad each row to `ncol` columns, filling the new trailing slots with the missing
/// value for that column's type. A no-op copy when rows are already `ncol` wide.
fn padRows(arena: std.mem.Allocator, rows: [][]Value, cols: []const OutCol) ![][]Value {
    const out = try arena.alloc([]Value, rows.len);
    for (rows, 0..) |r, i| {
        if (r.len == cols.len) {
            out[i] = r;
            continue;
        }
        const row = try arena.alloc(Value, cols.len);
        for (cols, 0..) |c, k| row[k] = if (k < r.len) r[k] else missingOf(c.type);
        out[i] = row;
    }
    return out;
}

/// Retype the marked columns of `r` to CHARACTER, rendering any numeric cell in
/// those positions to its BEST text (cellText). Used by cross-type set ops.
fn coerceCharCols(arena: std.mem.Allocator, r: Result, tochar: []const bool) !Result {
    const cols = try arena.dupe(OutCol, r.cols);
    for (tochar, 0..) |c, k| if (c) {
        cols[k].type = .char;
    };
    const rows = try arena.alloc([]Value, r.rows.len);
    for (r.rows, 0..) |row, i| {
        const nr = try arena.dupe(Value, row);
        for (tochar, 0..) |c, k| if (c and k < nr.len and nr[k] == .num) {
            // temp first: assigning `.str` into nr[k] in place would flip the tag
            // before cellText reads nr[k] (Zig result-location aliasing).
            const s = try cellText(arena, nr[k]);
            nr[k] = .{ .str = s };
        };
        rows[i] = nr;
    }
    return .{ .cols = cols, .rows = rows };
}

/// CORRESPONDING (GAP-sqlunioncorr) for UNION/INTERSECT/EXCEPT: restrict BOTH
/// arms to the columns whose names appear in both, projected in `left`'s order,
/// so the subsequent set op matches by name rather than position.
fn corrAlign(arena: std.mem.Allocator, left: Result, right: Result) !struct { left: Result, right: Result } {
    var cols: std.ArrayList(OutCol) = .empty;
    var lidx: std.ArrayList(usize) = .empty;
    var ridx: std.ArrayList(usize) = .empty;
    for (left.cols, 0..) |lc, k| {
        for (right.cols, 0..) |rc, j| if (eqi(lc.name, rc.name)) {
            try cols.append(arena, lc);
            try lidx.append(arena, k);
            try ridx.append(arena, j);
            break;
        };
    }
    const project = struct {
        fn f(a: std.mem.Allocator, rows: [][]Value, ocols: []OutCol, idx: []const usize) !Result {
            const out = try a.alloc([]Value, rows.len);
            for (rows, 0..) |r, ri| {
                const nr = try a.alloc(Value, idx.len);
                for (idx, 0..) |src, k| nr[k] = r[src];
                out[ri] = nr;
            }
            return .{ .cols = ocols, .rows = out };
        }
    }.f;
    const oc = try cols.toOwnedSlice(arena);
    return .{
        .left = try project(arena, left.rows, oc, lidx.items),
        .right = try project(arena, right.rows, oc, ridx.items),
    };
}

/// The width of a set-op result column, given the two arms' declared widths.
/// SQL Procedure User's Guide, printed p.397-398, Table 8.1 "Resolving Different
/// Lengths for the Same Variable": with two data-set sources, "the length of VAR1
/// in NewTable is the maximum length of VAR1 across both sources". So MAX, not the
/// left arm's — the left-wins width made applyLens TRUNCATE the right arm's longer
/// values ('ABCDEF' from a `$6` column → 'ABC' under a `$3` left arm), silent data
/// loss (found by differential probe while landing BUG-sqlcolwidthloss; before that
/// fix a pass-through column carried no width at all, so nothing truncated).
/// A null (unknown) width on either side stays null: opensas records null when no
/// LENGTH was ever declared, and enforcing one arm's width over data of unknown
/// width is the same trap. Table 8.1's SQL-view rows (an explicitly specified view
/// length wins over the max) are DOC-SILENT here — opensas has no SQL-view length
/// declaration distinct from a table's, so there is no case to distinguish.
fn setOpLen(a: ?usize, b: ?usize) ?usize {
    return @max(a orelse return null, b orelse return null);
}

fn combineSetOp(arena: std.mem.Allocator, left0: Result, right0: Result, op: SetOp) !Result {
    if (op.kind == .outer_union) return combineOuterUnion(arena, left0, right0, op.corr);
    var left = left0;
    var right = right0;
    if (op.corr) { // align by name, keep only common columns (CORRESPONDING)
        const al = try corrAlign(arena, left, right);
        left = al.left;
        right = al.right;
    }
    // Cross-type set-op (BUG-sqlunioncoerce): where the arms disagree on a
    // column's type, SAS 9.4 coerces the RESULT column to CHARACTER (char wins)
    // — the numeric arm's values render via BEST (cellText) into the char slot.
    // Done before stacking/compare so INTERSECT/EXCEPT also match on the coerced
    // (char) text. Only overlapping positions are considered; column-count
    // padding (below) fills the rest with type-correct missing.
    {
        const n = @min(left.cols.len, right.cols.len);
        const tochar = try arena.alloc(bool, n);
        var need = false;
        for (0..n) |k| {
            tochar[k] = left.cols[k].type != right.cols[k].type;
            if (tochar[k]) need = true;
        }
        if (need) {
            left = try coerceCharCols(arena, left, tochar);
            right = try coerceCharCols(arena, right, tochar);
        }
    }
    // The result column keeps the LEFT arm's name/attributes, but its WIDTH must
    // be the MAX of the two arms — see setOpLen. Merged here, before the
    // column-count padding below overwrites right.cols with the widened set.
    {
        const lc = try arena.dupe(OutCol, left.cols);
        for (0..@min(lc.len, right.cols.len)) |k| lc[k].len = setOpLen(lc[k].len, right.cols[k].len);
        left = .{ .cols = lc, .rows = left.rows };
    }
    // A column-count mismatch WITHOUT CORRESPONDING: SAS 9.4 matches by position,
    // pads the shorter arm with missing values (and warns) — it does NOT error, and
    // must never emit ragged rows (which panicked appendRow). Names come from the
    // first (left) query for overlapping positions; extra columns from the wider arm.
    // ponytail: SAS also logs a WARNING here — skipped (combineSetOp has no diags);
    // the padded values are the load-bearing part. Add the note if a program needs it.
    if (left.cols.len != right.cols.len) {
        var cols: std.ArrayList(OutCol) = .empty;
        try cols.appendSlice(arena, if (left.cols.len >= right.cols.len) left.cols else right.cols);
        for (0..@min(left.cols.len, right.cols.len)) |k| cols.items[k] = left.cols[k];
        const wide = try cols.toOwnedSlice(arena);
        left = .{ .cols = wide, .rows = try padRows(arena, left.rows, wide) };
        right = .{ .cols = wide, .rows = try padRows(arena, right.rows, wide) };
    }
    var rows: std.ArrayList([]Value) = .empty;
    // a right row may be matched by at most one left row (multiset arithmetic)
    const used = try arena.alloc(bool, right.rows.len);
    @memset(used, false);
    switch (op.kind) {
        .outer_union => unreachable, // handled above
        .union_ => {
            for (left.rows) |r| try rows.append(arena, r);
            for (right.rows) |r| try rows.append(arena, r);
        },
        .intersect => for (left.rows) |r| { // keep a left row iff it can pair with an unused right row
            if (op.all) {
                if (consumeMatch(right.rows, used, r)) try rows.append(arena, r);
            } else if (rowInRows(r, right.rows)) try rows.append(arena, r);
        },
        .except => for (left.rows) |r| { // keep a left row that has NO remaining right match
            if (op.all) {
                if (!consumeMatch(right.rows, used, r)) try rows.append(arena, r);
            } else if (!rowInRows(r, right.rows)) try rows.append(arena, r);
        },
    }
    var out = Result{ .cols = left.cols, .rows = try rows.toOwnedSlice(arena) };
    if (!op.all) out.rows = try dedupRows(arena, out.rows);
    return out;
}

/// OUTER UNION concatenates EVERY row of both arms and keeps EVERY column of both
/// — unlike plain UNION it does NOT overlay same-named columns nor align by
/// position: each row fills only its own arm's columns, the rest stay missing.
/// OUTER UNION CORR *does* overlay same-named columns (align by name) while still
/// concatenating rows. Neither form de-duplicates (it is a concatenation).
/// SAS 9.4 SQL Procedure, "Combining Queries with Set Operators": the OUTER UNION
/// operator concatenates the tables and, without CORRESPONDING, keeps all columns.
fn combineOuterUnion(arena: std.mem.Allocator, left: Result, right: Result, corr: bool) !Result {
    var cols: std.ArrayList(OutCol) = .empty;
    try cols.appendSlice(arena, left.cols);
    // rmap[j] = result-column index that right column j feeds. Non-CORR always
    // appends (its own fresh slot); CORR reuses a same-named left column.
    const rmap = try arena.alloc(usize, right.cols.len);
    for (right.cols, 0..) |rc, j| {
        if (corr) {
            var hit: ?usize = null;
            for (left.cols, 0..) |lc, k| if (eqi(lc.name, rc.name)) {
                hit = k;
                break;
            };
            if (hit) |k| {
                rmap[j] = k;
                cols.items[k].len = setOpLen(cols.items[k].len, rc.len); // widest arm wins (setOpLen)
                continue;
            }
        }
        rmap[j] = cols.items.len;
        try cols.append(arena, rc);
    }
    const ncol = cols.items.len;
    var rows: std.ArrayList([]Value) = .empty;
    for (left.rows) |r| { // left rows fill the first left.cols slots
        const row = try arena.alloc(Value, ncol);
        for (cols.items, 0..) |c, k| row[k] = missingOf(c.type);
        for (r, 0..) |v, k| row[k] = v;
        try rows.append(arena, row);
    }
    for (right.rows) |r| { // right rows fill via rmap; everything else missing
        const row = try arena.alloc(Value, ncol);
        for (cols.items, 0..) |c, k| row[k] = missingOf(c.type);
        for (r, 0..) |v, j| row[rmap[j]] = v;
        try rows.append(arena, row);
    }
    return .{ .cols = try cols.toOwnedSlice(arena), .rows = try rows.toOwnedSlice(arena) };
}

/// Mark and report the first unused right row equal to `r` — one left row consumes
/// at most one right row, giving the correct INTERSECT/EXCEPT ALL multiplicity.
fn consumeMatch(right: [][]Value, used: []bool, r: []const Value) bool {
    for (right, 0..) |o, j| if (!used[j] and rowEq(o, r)) {
        used[j] = true;
        return true;
    };
    return false;
}

fn rowInRows(r: []const Value, rows: [][]Value) bool {
    for (rows) |o| if (rowEq(o, r)) return true;
    return false;
}

/// Split a SELECT stream at top-level `UNION`/`INTERSECT`/`EXCEPT [ALL]`.
/// `ops[k]` is the operator joining `arms[k]` to `arms[k+1]`.
fn splitSetOps(arena: std.mem.Allocator, toks: []const Token) !struct { arms: []const []const Token, ops: []const SetOp } {
    var arms: std.ArrayList([]const Token) = .empty;
    var ops: std.ArrayList(SetOp) = .empty;
    var start: usize = 0;
    var depth: usize = 0;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag == .lparen) {
            depth += 1;
        } else if (toks[i].tag == .rparen) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and tkKw(toks[i], "outer") and atKw(toks, i + 1, "union")) {
            // `OUTER UNION [CORR|CORRESPONDING]` — must be caught before the bare
            // `union` check below, else the trailing UNION would be read alone.
            try arms.append(arena, toks[start..i]);
            i += 1; // now on UNION
            var corr = false;
            if (atKw(toks, i + 1, "corr") or atKw(toks, i + 1, "corresponding")) {
                corr = true;
                i += 1;
            }
            try ops.append(arena, .{ .kind = .outer_union, .all = false, .corr = corr });
            start = i + 1;
        } else if (depth == 0) {
            const kind: ?SetKind =
                if (tkKw(toks[i], "union")) .union_ else if (tkKw(toks[i], "intersect")) .intersect else if (tkKw(toks[i], "except")) .except else null;
            if (kind) |k| {
                try arms.append(arena, toks[start..i]);
                // `UNION|INTERSECT|EXCEPT [ALL] [CORR|CORRESPONDING]` — CORR applies
                // to all four set operators, not only OUTER UNION (GAP-sqlunioncorr).
                var all = false;
                var corr = false;
                while (true) {
                    if (atKw(toks, i + 1, "all")) {
                        all = true;
                        i += 1;
                    } else if (atKw(toks, i + 1, "corr") or atKw(toks, i + 1, "corresponding")) {
                        corr = true;
                        i += 1;
                    } else break;
                }
                try ops.append(arena, .{ .kind = k, .all = all, .corr = corr });
                start = i + 1;
            }
        }
    }
    try arms.append(arena, toks[start..]);
    return .{ .arms = try arms.toOwnedSlice(arena), .ops = try ops.toOwnedSlice(arena) };
}

fn synName(text: []const u8) Token {
    return .{ .tag = .name, .text = text, .line = 0 };
}
fn synTok(tag: lex.Tag, text: []const u8) Token {
    return .{ .tag = tag, .text = text, .line = 0 };
}
fn appendAll(arena: std.mem.Allocator, out: *std.ArrayList(Token), items: []const Token) !void {
    for (items) |x| try out.append(arena, x);
}

/// Rewrite the SQL-only infix predicates into ordinary expressions the DATA-step
/// expression parser understands (word operators + missing()/like()/index()):
///   L BETWEEN lo AND hi        → ( L ge lo and L le hi )
///   L IS [NOT] NULL|MISSING    → [not] missing(L)
///   L [NOT] LIKE pat           → [not] like(L, pat)
///   L [NOT] CONTAINS sub       → ( index(L, sub) gt|eq 0 )
/// ponytail: the left operand is captured as a FULL term by `popLeftOperand` —
/// a balanced function-call/parenthesized group (`lowcase(c)`, `substr(c,1,7)`)
/// or a single column/literal/coalesced `t.c`. Right operands: LIKE pat and
/// CONTAINS sub are FULL expressions via `scanOperand` (BUG-wherecontainslikeexpr
/// — `like "&p"||'%'` used to drop everything past the first token, silently
/// matching ZERO rows); BETWEEN lo/hi are full expressions too, stopping at
/// the top-level AND (BUG-wherebetweenexpr — Language Reference: Concepts p.221 "constants or
/// expressions": `between salary*0.30 and salary*0.50`).
///
/// Pop one full left operand off the tail of `out` (in source order). A
/// trailing `)` back-scans to its matching `(`, then swallows a preceding
/// function-name identifier — so `lowcase ( c )` comes off whole, not just the
/// `)`. Otherwise the single tail token (column/literal/coalesced `t.c`).
fn popLeftOperand(arena: std.mem.Allocator, diags: *diag.Diagnostics, out: *std.ArrayList(Token)) diag.Error![]const Token {
    if (out.items.len == 0)
        return diags.fail(error.ParseError, 0, "WHERE predicate: missing left operand", .{});
    if (out.items[out.items.len - 1].tag != .rparen) {
        const tail = out.pop().?;
        return try arena.dupe(Token, &.{tail});
    }
    var depth: usize = 0;
    var start = out.items.len;
    while (start > 0) {
        start -= 1;
        switch (out.items[start].tag) {
            .rparen => depth += 1,
            .lparen => {
                depth -= 1;
                if (depth == 0) break;
            },
            else => {},
        }
    }
    if (depth != 0)
        return diags.fail(error.ParseError, 0, "WHERE predicate: unbalanced '(' in the left operand", .{});
    if (start > 0 and out.items[start - 1].tag == .name) start -= 1; // function name
    const operand = try arena.dupe(Token, out.items[start..]);
    out.shrinkRetainingCapacity(start);
    return operand;
}

/// Scan one full operand expression starting at `toks[j.*]` (LIKE pattern /
/// CONTAINS substring; BETWEEN reuses it), advancing `j.*` past it: literals,
/// names, `.`, arithmetic/concat operators and balanced (…) groups at any
/// depth. A depth-0 boolean/comparison keyword, comma, `;` or a foreign `)`
/// ENDS it — so `like "&p"||'%'` and `contains trim(a)` come through whole
/// (Language Reference: Concepts p.223 "a SAS character expression", p.221 CONTAINS-with-TRIM).
/// `allow_fn`=false rejects a `name (` call: p.223 forbids a SAS function in
/// a LIKE pattern. Every failure reports via diags — never a bare ParseError.
fn scanOperand(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token, j: *usize, op_line: usize, opname: []const u8, allow_fn: bool) diag.Error![]const Token {
    const start = j.*;
    var k = start;
    var depth: usize = 0;
    var prev_name = false; // a `(` straight after a name is a function CALL
    scan: while (k < toks.len) : (k += 1) {
        const tk = toks[k];
        switch (tk.tag) {
            .lparen => {
                if (depth == 0 and prev_name and !allow_fn)
                    return diags.fail(error.ParseError, tk.line, "WHERE {s}: a SAS function is not allowed in the pattern (Language Reference: Concepts p.223)", .{opname});
                depth += 1;
                prev_name = false;
            },
            .rparen => {
                if (depth == 0) break :scan; // closes an outer group — not ours
                depth -= 1;
                prev_name = false;
            },
            .comma, .semicolon, .eof => if (depth == 0) break :scan,
            .number, .string, .dot, .plus, .minus, .star, .slash, .star2, .concat => prev_name = false,
            .name => {
                if (depth == 0 and isOperandBoundary(tk.text)) break :scan;
                prev_name = true;
            },
            else => if (depth == 0) break :scan, // comparison symbols, &, |, ^, …
        }
    }
    if (depth != 0)
        return diags.fail(error.ParseError, op_line, "WHERE {s}: unbalanced '(' in the operand", .{opname});
    if (k == start)
        return diags.fail(error.ParseError, op_line, "WHERE {s}: expected an operand", .{opname});
    j.* = k;
    return try arena.dupe(Token, toks[start..k]);
}

/// scanOperand's WALK without the dupe/errors — the end index of the depth-0
/// operand starting at `start`. For validators that only need the extent
/// (validateWhereCols' LIKE…ESCAPE check); keep the break set in sync with
/// scanOperand.
fn operandEnd(toks: []const Token, start: usize) usize {
    var k = start;
    var depth: usize = 0;
    while (k < toks.len) : (k += 1) {
        switch (toks[k].tag) {
            .lparen => depth += 1,
            .rparen => {
                if (depth == 0) break;
                depth -= 1;
            },
            .comma, .semicolon, .eof => if (depth == 0) break,
            .number, .string, .dot, .plus, .minus, .star, .slash, .star2, .concat => {},
            .name => if (depth == 0 and isOperandBoundary(toks[k].text)) break,
            else => if (depth == 0) break,
        }
    }
    return k;
}

/// True when toks[i] is `min`/`max` sitting BETWEEN two operands — the infix
/// MIN/MAX operator (Language Reference: Concepts p.225), never a column reference. Both neighbors
/// must look like operand edges so `min > 3` (column) and `min(a,b)` (call)
/// are untouched.
fn isInfixMinMax(toks: []const Token, i: usize) bool {
    if (!eqi(toks[i].text, "min") and !eqi(toks[i].text, "max")) return false;
    const prev_ok = i > 0 and switch (toks[i - 1].tag) {
        .name, .number, .string, .rparen => true,
        else => false,
    };
    const next_ok = i + 1 < toks.len and switch (toks[i + 1].tag) {
        .name, .number, .string, .lparen => true,
        else => false,
    };
    return prev_ok and next_ok;
}

/// Keywords that END a depth-0 operand scan: booleans, word comparisons, and
/// the predicate keywords that would start the next clause.
fn isOperandBoundary(text: []const u8) bool {
    const kws = [_][]const u8{ "and", "or", "not", "eq", "ne", "gt", "ge", "lt", "le", "in", "between", "like", "contains", "is", "escape" };
    for (kws) |kw| if (eqi(text, kw)) return true;
    return false;
}

/// Rewrite SQL-style infix predicates (IS [NOT] NULL/MISSING, BETWEEN, LIKE,
/// CONTAINS) into ordinary expression tokens. Shared with io.zig's DATA-step
/// `where=` path so it agrees with PROC SQL (GH#35 ISS-wherenull).
pub fn desugarPredicates(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token) diag.Error![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        const tok = toks[i];
        if (tkKw(tok, "is") and out.items.len > 0) {
            const L = try popLeftOperand(arena, diags, &out);
            var neg = false;
            var j = i + 1;
            if (atKw(toks, j, "not")) {
                neg = true;
                j += 1;
            }
            // GAP-wherelow-tick266: `IS` is ONLY `IS [NOT] NULL|MISSING`
            // (Language Reference: Concepts p.224). A bare `x is` used to desugar to missing(x) and
            // `x is not` to not missing(x) — an incomplete statement completed
            // by guesswork (silent wrong filter). Fail loud instead (D-002).
            if (atKw(toks, j, "null") or atKw(toks, j, "missing")) {
                j += 1;
            } else return diags.fail(error.ParseError, tok.line, "WHERE IS: expected NULL or MISSING after IS[ NOT] (Language Reference: Concepts p.224)", .{});
            i = j - 1;
            if (neg) try out.append(arena, synName("not"));
            try appendAll(arena, &out, &.{ synName("missing"), synTok(.lparen, "(") });
            try appendAll(arena, &out, L);
            try out.append(arena, synTok(.rparen, ")"));
        } else if ((tkKw(tok, "between") or tkKw(tok, "like") or tkKw(tok, "contains")) and out.items.len > 0) {
            var neg = false;
            if (tkKw(out.items[out.items.len - 1], "not")) {
                neg = true;
                _ = out.pop();
            }
            if (out.items.len == 0) {
                try out.append(arena, tok);
                continue;
            }
            const L = try popLeftOperand(arena, diags, &out);
            if (tkKw(tok, "between")) {
                var j = i + 1;
                const lo = try scanOperand(arena, diags, toks, &j, tok.line, "BETWEEN", true);
                if (!atKw(toks, j, "and"))
                    return diags.fail(error.ParseError, tok.line, "WHERE BETWEEN: expected AND between the range bounds", .{});
                j += 1;
                const hi = try scanOperand(arena, diags, toks, &j, tok.line, "BETWEEN", true);
                i = j - 1; // loop's `i += 1` lands past hi
                if (neg) try appendAll(arena, &out, &.{ synName("not"), synTok(.lparen, "(") });
                try out.append(arena, synTok(.lparen, "("));
                try appendAll(arena, &out, L);
                try out.append(arena, synName("ge"));
                try appendAll(arena, &out, lo);
                try out.append(arena, synName("and"));
                try appendAll(arena, &out, L);
                try out.append(arena, synName("le"));
                try appendAll(arena, &out, hi);
                try out.append(arena, synTok(.rparen, ")"));
                if (neg) try out.append(arena, synTok(.rparen, ")"));
            } else if (tkKw(tok, "like")) {
                var j = i + 1;
                const pat = try scanOperand(arena, diags, toks, &j, tok.line, "LIKE", false);
                // GAP-wherelow-tick291 (B): `LIKE pat ESCAPE 'c'` is valid SAS
                // 9.4 (SQL Procedure User's Guide printed p.389 syntax, p.390
                // examples; the DATA-step WHERE has the same clause, Statements
                // ref printed p.364) that we do not implement. It used to
                // desugar the bare LIKE and leave `escape 'c'` in the stream,
                // so `escape` was blamed as an unknown COLUMN the user never
                // wrote, at rc 1. Honest gap instead: name the clause, rc 2 —
                // real SAS runs this clean (D-009/D-009b(i)).
                if (atKw(toks, j, "escape")) {
                    diag.markGap();
                    return diags.fail(error.ExecError, tok.line, "WHERE LIKE: the ESCAPE clause is not supported (SQL Procedure User's Guide printed p.389; Statements ref printed p.364)", .{});
                }
                i = j - 1;
                if (neg) try out.append(arena, synName("not"));
                try appendAll(arena, &out, &.{ synName("like"), synTok(.lparen, "(") });
                try appendAll(arena, &out, L);
                try out.append(arena, synTok(.comma, ","));
                try appendAll(arena, &out, pat);
                try out.append(arena, synTok(.rparen, ")"));
            } else { // contains → index(L, sub) > 0
                var j = i + 1;
                const sub = try scanOperand(arena, diags, toks, &j, tok.line, "CONTAINS", true);
                i = j - 1;
                try appendAll(arena, &out, &.{ synTok(.lparen, "("), synName("index"), synTok(.lparen, "(") });
                try appendAll(arena, &out, L);
                try out.append(arena, synTok(.comma, ","));
                try appendAll(arena, &out, sub);
                try appendAll(arena, &out, &.{ synTok(.rparen, ")"), if (neg) synName("eq") else synName("gt"), synTok(.number, "0"), synTok(.rparen, ")") });
            }
        } else try out.append(arena, tok);
    }
    return out.items;
}

/// Row indices of `ds` whose `wtoks` predicate is true (SQL-predicate aware).
/// Used by DELETE/UPDATE; no CALCULATED/CASE support (ponytail: add if a DML
/// fixture needs it — SELECT's WHERE path already handles both).
fn rowsMatching(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, ds: *Dataset, wtoks: []const Token, table: []const u8, alias: ?[]const u8) diag.Error![]const usize {
    // GAP-sqldmlwhere: DML WHERE gets the same unknown-column fail-loud as the
    // SELECT path (BUG-sqlwhereunknown) — an unbound name must ERROR naming the
    // column, not bind to missing and silently match nothing/everything. DML
    // has no SELECT items, so any CALCULATED-style alias simply fails as an
    // unknown column (not SAS-legal in DML anyway).
    if (!(try validateWhereCols(diags, ds, .{ .table = table, .alias = alias, .where = wtoks }))) return error.ExecError;
    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    var kept: std.ArrayList(usize) = .empty;
    // EXISTS / NOT EXISTS or a correlated subquery in a DML WHERE must be resolved
    // per row — mirror the SELECT-WHERE path (execQuery). The old code ran only
    // substituteSubqueries, so a raw `exists(select …)` reached the parser as a
    // bare name → falsy → the DELETE/UPDATE matched zero rows (BUG-sqldmlexists).
    if (hasExists(wtoks) or hasCorrelatedSubq(wtoks, ds, table, alias)) {
        for (ds.rows.items, 0..) |_, ri| {
            try loadForEvalAlias(&pdv, ds, ds.row(ri), alias);
            const e = try substituteExists(arena, lib, diags, wtoks, ds, ri, table, alias);
            const s0 = try desugarPredicates(arena, diags, try substituteSubqueries(arena, lib, diags, e, .{ .ds = ds, .ri = ri, .table = table, .alias = alias }));
            const s = try substituteCase(arena, diags, &ev, s0);
            var wp = pe.Parser.init(arena, try withEof(arena, s), diags);
            const cond = wp.parseExpr() catch continue;
            if ((try ev.eval(cond)).whereTruthy()) try kept.append(arena, ri);
        }
        return kept.items;
    }
    const subst = try desugarPredicates(arena, diags, try substituteSubqueries(arena, lib, diags, wtoks, null));
    var wp = pe.Parser.init(arena, try withEof(arena, subst), diags);
    const cond = wp.parseExpr() catch return error.ParseError;
    for (ds.rows.items, 0..) |_, ri| {
        try loadForEval(&pdv, ds, ds.row(ri));
        if ((try ev.eval(cond)).whereTruthy()) try kept.append(arena, ri);
    }
    return kept.items;
}

fn execQuery(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, q_in: Query) diag.Error!?Result {
    var q = q_in;
    // GAP-sqlstataggs: unimplemented statistic aggregates (std/var/…) must not
    // fall through to the per-row expression path (silent wrong numbers — see
    // statAggCall). ponytail: guards SELECT items + HAVING; a std() buried in a
    // CASE or ORDER BY expression still slips through.
    for (q.items) |it| {
        const span = it.expr_toks orelse it.agg_arg orelse continue;
        if (statAggCall(span)) |nm| {
            unsupported(try std.fmt.allocPrint(arena, "PROC SQL: {s}() statistic aggregate is not implemented (single-argument {s} aggregates in SQL)", .{ nm, nm }));
            return null;
        }
    }
    if (q.having) |h| if (statAggCall(h)) |nm| {
        unsupported(try std.fmt.allocPrint(arena, "PROC SQL: {s}() statistic aggregate is not implemented (single-argument {s} aggregates in SQL)", .{ nm, nm }));
        return null;
    };
    // `from (SELECT …)` derived table: run the inner query, materialize it into a
    // temp dataset, then aim the outer query at that name (BUG-sqlderivedtable).
    if (q.from_sub) |subtoks| {
        const res = (try execSelect(arena, lib, diags, subtoks)) orelse return null;
        // Materialize under a UNIQUE internal name — NEVER the alias. Downstream alias
        // resolution assumes q.table (real dataset name) ≠ q.alias, exactly like
        // `from realtable as t`; reusing the alias as the table name made table==alias
        // and silently returned no rows (BUG-sqlderivedtable). q.alias stays as-is so
        // `t.col` binds to the derived columns.
        const name = try std.fmt.allocPrint(arena, "_sqlderived_{d}", .{lib.names.items.len});
        const sub = try arena.create(Dataset);
        sub.* = Dataset.init(arena, name);
        try addResultCols(sub, res.cols); // GH#49: carry attached formats through the derived table
        for (res.rows) |row| try sub.appendRow(row);
        try lib.put(name, sub);
        q.table = name;
    }
    const ds = if (q.joins.len > 0)
        (try buildJoin(arena, lib, diags, q.table, q.alias, q.from_opts, q.joins, q.where)) orelse return null
    else if (lib.find(q.table)) |d|
        try withOptions(arena, diags, d, q.from_opts) // GH#33: apply from T(where=/keep=/…)
    else if (dictKind(q.table) != null)
        // a `dictionary.*` / `sashelp.v*` introspection view — synthesized fresh
        // from live library/macro state at query time (ISS-dictviews).
        try withOptions(arena, diags, (try synthDictView(arena, lib, q.table)) orelse return null, q.from_opts)
    else if (isUnsupportedDict(q.table)) {
        unsupportedDict(arena, q.table);
        return null;
    } else {
        unsupported("PROC SQL: FROM table not found");
        return null;
    };

    // `alias.*` / bare `*` items now expand against the resolved (possibly joined)
    // dataset — each becomes a plain-column item (ISS-sqlaliasstar).
    q.items = try expandStars(arena, ds, q);
    // F7 FEEDBACK: capture the star-expanded statement for runStmt to echo.
    if (g_opts.feedback) g_feedback = try feedbackEcho(arena, ds, q);

    // A WHERE name matching nothing must fail loud, not bind to missing and
    // silently return 0 rows (BUG-sqlwhereunknown / BUG-sqlwherecalcagg).
    if (!(try validateWhereCols(diags, ds, q))) return null;

    // An unqualified column present in >1 joined table is ambiguous — SAS errors;
    // taking the first table silently corrupts a merge (a bare RIGHT/FULL join key
    // then drops right-only rows to a missing key) — BUG-sqlambigcol.
    if (!(try validateNoAmbiguity(diags, ds, q))) return null;

    // A summary function in WHERE is illegal in SAS ("Summary functions are not
    // allowed in the WHERE clause." — aggregates belong in HAVING). Left alone, a
    // single-arg sum/min/max/count/… was silently dispatched as the per-row
    // DATA-step function of the same name (max(v) → v, so `v >= max(v)` kept ALL
    // rows), dropping the filter entirely (BUG-sqlaggwherefilter). exprHasAgg skips
    // nested `(select …)` subqueries, so a subquery's own aggregate is untouched;
    // aggAt matches only single-arg calls, so a multi-arg scalar max(a,b) stays legal.
    if (q.where) |wtoks| if (exprHasAgg(wtoks))
        return diags.fail(error.ParseError, if (wtoks.len > 0) wtoks[0].line else 0, "PROC SQL: Summary functions are not allowed in the WHERE clause.", .{});

    // WHERE filter → the surviving row indices
    var kept: std.ArrayList(usize) = .empty;
    if (q.where != null and (hasExists(q.where.?) or hasCorrelatedSubq(q.where.?, ds, q.table, q.alias))) {
        // PERF-sqlcorrsubq: the safe single-equality semi-join shape resolves via a
        // hash of the inner table built ONCE, O(N+M) instead of re-executing the
        // inner query per outer row (was O(N*M), 4.7 GB OOM). Bails (→ per-row loop)
        // on any other shape — correctness first.
        if (try trySemiJoin(arena, lib, diags, q, ds)) |ks| {
            kept = ks;
        } else {
            // A correlated predicate (EXISTS, or a scalar subquery referencing the outer
            // row) must be evaluated per outer row: substitute each EXISTS with 0/1 and
            // each correlated `(select …)` with its per-row value, then desugar and
            // evaluate (BUG-sqlexists, BUG-sqlcorrscalar).
            var pdv = Pdv.init(arena);
            var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
            for (ds.rows.items, 0..) |_, ri| {
                try loadForEvalAlias(&pdv, ds, ds.row(ri), q.alias);
                const e = try substituteExists(arena, lib, diags, q.where.?, ds, ri, q.table, q.alias);
                const s0 = try desugarPredicates(arena, diags, try substituteSubqueries(arena, lib, diags, e, .{ .ds = ds, .ri = ri, .table = q.table, .alias = q.alias }));
                const s = try substituteCase(arena, diags, &ev, s0);
                var wp = pe.Parser.init(arena, try withEof(arena, s), diags);
                const cond = wp.parseExpr() catch continue;
                if ((try ev.eval(cond)).whereTruthy()) try kept.append(arena, ri);
            }
        }
    } else if (q.where) |wtoks| {
        // resolve scalar/IN subqueries, then desugar the SQL-only infix predicates
        // (BETWEEN / LIKE / IS NULL / CONTAINS) into ordinary expressions
        const subst0 = try desugarPredicates(arena, diags, try substituteSubqueries(arena, lib, diags, wtoks, null));
        // a CALCULATED reference names a computed SELECT column; strip the keyword and
        // bind those columns into the PDV per row before evaluating (BUG-calcwhere).
        const uses_calc = hasCalc(subst0);
        const subst = try removeCalculated(arena, subst0);
        const names = if (uses_calc) try itemNames(arena, q) else &.{};
        var pdv = Pdv.init(arena);
        var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
        // A CASE in the predicate is row-dependent, so it can't parse once — the
        // parser_expr grammar has no CASE. When present, replace each CASE with its
        // per-row value, then parse/eval the resulting ordinary expression per row
        // (BUG-casewhere). Otherwise parse the condition once (the common path).
        const cond0: ?*const ast.Expr = if (hasCase(subst)) null else blk: {
            var wp = pe.Parser.init(arena, try withEof(arena, subst), diags);
            break :blk try wp.parseExpr();
        };
        for (ds.rows.items, 0..) |_, ri| {
            try loadForEvalAlias(&pdv, ds, ds.row(ri), q.alias); // qualified + unqualified + alias
            if (uses_calc) try bindComputed(arena, diags, &ev, q, names);
            const cond = cond0 orelse blk: {
                const row_toks = try substituteCase(arena, diags, &ev, subst);
                var wp = pe.Parser.init(arena, try withEof(arena, row_toks), diags);
                break :blk wp.parseExpr() catch continue; // unparseable predicate → row dropped
            };
            if ((try ev.eval(cond)).whereTruthy()) try kept.append(arena, ri);
        }
    } else {
        for (ds.rows.items, 0..) |_, ri| try kept.append(arena, ri);
    }

    const has_agg = !q.star and blk: {
        for (q.items) |it| {
            if (it.agg != null) break :blk true;
            // an aggregate nested in a compound expression or CASE still aggregates —
            // route it through execGrouped, which resolves it over the group then
            // folds the outer expression once (BUG-sqlaggouter).
            if (it.expr_toks) |et| if (exprHasAgg(et)) break :blk true;
            if (it.case_toks) |ct| if (exprHasAgg(ct)) break :blk true;
        }
        // an aggregate appearing ONLY in HAVING still makes this a summary query —
        // it must group/remerge, not pass through row-wise (BUG-sqlgroupnoagg).
        if (q.having) |h| if (exprHasAgg(h)) break :blk true;
        break :blk false;
    };
    var res = if (q.star and q.having != null)
        // `select * … having <agg cond>` needs GROUP BY+HAVING remerge, which the
        // plain select* fast-path (ORDER BY only) skipped — it returned every row
        // (ISS-sqlremerge #37). Remerge is row-wise (one output row per surviving
        // detail row), so it is its own path, not execGrouped's group collapse.
        try execStarRemerge(arena, lib, ds, diags, q, kept.items)
    else if (q.star or !has_agg)
        // GROUP BY but no summary function anywhere (SELECT or HAVING): SAS treats
        // the GROUP BY as an ORDER BY — every detail row, ordered by the group keys
        // (BUG-sqlgroupnoagg). An explicit ORDER BY wins when present.
        try execRowWise(arena, lib, ds, diags, q, if (!has_agg and q.group_exprs.len != 0 and q.order.len == 0)
            try sortByGroupKeys(arena, diags, ds, q, kept.items)
        else
            kept.items)
    else if (has_agg and try hasDetailCol(arena, q, ds))
        // SAS remerge: a select that mixes an aggregate with a bare non-group
        // detail column broadcasts each group's aggregate across every detail row
        // of that group, so the result has one row per input row — not the single
        // collapsed group row execGrouped emits. Covers both the no-GROUP-BY case
        // (whole table = one group, BUG-sqlremergedetail) and the GROUP BY case
        // (per-group broadcast, BUG-sqlgroupremerge).
        try execRemerge(arena, lib, ds, diags, q, kept.items)
    else
        try execGrouped(arena, lib, ds, diags, q, kept.items);
    if (q.distinct) res.rows = try dedupRows(arena, res.rows);
    return res;
}

/// Hash + eql context for a row tuple → membership set (PERF-sqldistinct). eql
/// delegates to `rowEq` so dedup semantics can't drift from the linear scan;
/// `hash` agrees with it: equal rows hash equal. Canonicalizations matching
/// `cmpVal` — missings bucket by special-missing rank (.A ≠ ., BUG-sqlmissdistinct),
/// -0.0 → +0.0, char trailing blanks insignificant — plus a per-cell type tag so
/// a numeric and a char cell differ.
const RowKeyCtx = struct {
    pub fn hash(_: RowKeyCtx, key: []const Value) u64 {
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
    pub fn eql(_: RowKeyCtx, a: []const Value, b: []const Value) bool {
        return rowEq(a, b);
    }
};

/// GROUP BY key tuple → group slot, so partitioning kept rows into groups is O(1)
/// per row instead of a scan of every group seen so far (PERF-sqlgroupscan). Uses
/// RowKeyCtx (eql = rowEq, the tuple equality that grouping/dedup both use).
const GroupIndex = std.HashMapUnmanaged([]const Value, usize, RowKeyCtx, std.hash_map.default_max_load_percentage);

/// Keep the first occurrence of each distinct row (SELECT DISTINCT / UNION). The
/// ordered `out` list is the store (first-occurrence order preserved); a hash set
/// does the membership test in O(1), so dedup is O(N) not O(N²) (PERF-sqldistinct).
fn dedupRows(arena: std.mem.Allocator, rows: [][]Value) ![][]Value {
    var out: std.ArrayList([]Value) = .empty;
    var seen: std.HashMapUnmanaged([]const Value, void, RowKeyCtx, std.hash_map.default_max_load_percentage) = .empty;
    for (rows) |r| {
        const gop = try seen.getOrPutContext(arena, r, .{});
        if (!gop.found_existing) try out.append(arena, r);
    }
    return out.toOwnedSlice(arena);
}

fn rowEq(x: []const Value, y: []const Value) bool {
    if (x.len != y.len) return false;
    for (x, y) |xa, ya| if (cmpVal(xa, ya) != .eq) return false;
    return true;
}

/// COUNT(DISTINCT v) membership set. Same RowKeyCtx as SELECT DISTINCT, so the
/// distinct semantics (equal-under-cmpVal → one bucket) can't drift from the rest
/// of SQL; each value is keyed as a 1-element row tuple.
const DistinctSet = std.HashMapUnmanaged([]const Value, void, RowKeyCtx, std.hash_map.default_max_load_percentage);

/// Register a (non-missing) value in a COUNT(DISTINCT) set; true iff first sighting
/// (so the caller counts it). O(1) hash probe → the whole count is O(N), replacing
/// the old nested O(N²) rescan (PERF-sqlcountdistinct).
fn distinctFirst(arena: std.mem.Allocator, seen: *DistinctSet, v: Value) !bool {
    const probe = [_]Value{v};
    const gop = try seen.getOrPutContext(arena, &probe, .{});
    if (gop.found_existing) return false;
    gop.key_ptr.* = try arena.dupe(Value, &probe); // probe is a stack temp — stabilize the stored key
    return true;
}

/// Evaluate a HAVING predicate for one group: replace each aggregate call with its
/// value over the group, then evaluate the resulting expression against a PDV
/// holding the group's (constant) key columns.
fn evalHaving(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, ds: *Dataset, htoks: []const Token, grp: []const usize, rep: usize, cols: []const OutCol, cells: []const Value) diag.Error!bool {
    var pdv = Pdv.init(arena);
    // empty group (zero-row table, no GROUP BY): no rep row exists to load;
    // HAVING still runs — its aggregates resolve over the empty set (BUG-sqlemptyaggexpr)
    if (grp.len > 0) try loadForEval(&pdv, ds, ds.row(rep)); // group key columns are constant within the group
    // bind each SELECT output under its name/alias, so HAVING can reference it.
    // The VALUE's type governs, not the column's declared one: HAVING runs INSIDE
    // the grouped/remerge row loop, i.e. before retypeComputed has corrected a
    // computed column's declared type, so trusting `c.type` here bound a `.str`
    // cell to a `.num` var and pdv.setAt converted it to MISSING — `having` on a
    // char computed alias always failed (BUG-sqlremergecharcol). Matches how the
    // two `calculated` binds in execGrouped/execRemerge already do it.
    for (cols, cells) |c, v| try bindCol(&pdv, c.name, if (v == .num) .num else .char, c.len, v);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    const bare = try removeCalculated(arena, htoks); // `calculated alias` → the bound alias (BUG-calcwhere)
    // Collapse any `(select …)` scalar subquery to its value FIRST — same helper the
    // WHERE path uses — so `having sum(v) > (select avg(v) from t)` parses instead of
    // choking on the inner SELECT and silently keeping every group (BUG-sqlhavingsubq).
    const nosubq = try substituteSubqueries(arena, lib, diags, bare, null);
    // IS [NOT] NULL|MISSING (and BETWEEN/LIKE/CONTAINS) → function form through the
    // SAME desugar the WHERE path runs (BUG-sqlhavingismissing): without it `is
    // missing` parsed as stray column names and HAVING silently kept the COMPLEMENT
    // group. "IS NULL and IS MISSING are used in the WHERE, ON, and HAVING
    // expressions" (SQL Procedure Components, "IS Operator", printed p.372 / pdf 388).
    const desug = try desugarPredicates(arena, diags, nosubq);
    const with_aggs = try substituteAggs(arena, diags, ds, desug, grp); // aggregates → group values
    const resolved = try substituteCase(arena, diags, &ev, with_aggs); // then any CASE → its value (BUG-havingcase)
    var wp = pe.Parser.init(arena, try withEof(arena, resolved), diags);
    const cond = try wp.parseExpr(); // fail loud on a genuinely unparseable HAVING (was `catch return true` — hid wrong output)
    return (try ev.eval(cond)).truthy();
}

/// Replace `agg(col)` / `agg(*)` in a token stream with the aggregate's value over
/// `grp`, so the remainder is an ordinary expression the parser/evaluator can run.
fn substituteAggs(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, toks: []const Token, grp: []const usize) ![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (aggAt(toks, i)) |f| {
            var j = i + 2;
            const distinct = atKw(toks, j, "distinct");
            if (distinct) j += 1; // `count(distinct …)` — skip the keyword
            // Capture the whole argument span up to the matching ')', tracking paren
            // depth so a compound expression like sum(price*qty) is aggregated as a
            // unit rather than just its first column (BUG-sqlaggexpr).
            const arg_start = j;
            var depth: usize = 1;
            while (j < toks.len) : (j += 1) {
                if (toks[j].tag == .lparen) {
                    depth += 1;
                } else if (toks[j].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            const arg = toks[arg_start..j];
            if (atTag(toks, j, .rparen)) j += 1; // consume ')'
            const val = if (arg.len == 1 and arg[0].tag == .star)
                try computeAgg(arena, diags, ds, f, true, null, grp, distinct)
            else if (arg.len == 1 and arg[0].tag == .name)
                try computeAgg(arena, diags, ds, f, false, resolveCol(ds, arg[0].text), grp, distinct)
            else
                try computeAggExpr(arena, diags, ds, f, arg, grp, distinct);
            try out.append(arena, try valueToken(arena, val));
            i = j;
        } else {
            try out.append(arena, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Aggregate an arbitrary argument EXPRESSION (not just a bare column or `*`):
/// parse it once, evaluate it against each group row, then fold the per-row
/// values. This is what makes sum(price*qty) sum the products rather than the
/// first operand (BUG-sqlaggexpr). MIN/MAX use a generic (numeric-or-character)
/// compare; COUNT skips missing and honours DISTINCT; SUM/AVG coerce to numeric.
fn computeAggExpr(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, f: AggFn, arg: []const Token, grp: []const usize, distinct: bool) diag.Error!Value {
    // BUG-sqlnestedagg: an aggregate's ARGUMENT may not itself contain an aggregate —
    // SAS errors "Summary functions nested in this fashion are not supported." This is
    // the sole compound-argument path (bare col/`*` never nest); the old code ran
    // `max(v)` per row (= v) then summed, silently flattening to a wrong number.
    // exprHasAgg skips a nested `(select …)` — its aggregates are its own.
    if (exprHasAgg(arg))
        return diags.fail(error.ParseError, if (arg.len > 0) arg[0].line else 0, "PROC SQL: Summary functions nested in this fashion are not supported.", .{});
    const vals = try arena.alloc(Value, grp.len);
    // `sum(case when … end)` (or any aggregate over a CASE): the DATA-step expression
    // parser can't parse SQL CASE — evaluate it per row through the SQL CASE evaluator,
    // then fold (BUG-sqlsumcase; the old path returned missing / could null-unwrap).
    if (arg.len >= 2 and tkKw(arg[0], "case") and isPureCase(arg)) {
        const inner = arg[1 .. arg.len - 1]; // tokens between `case` and `end`
        // one PDV for the group, not one per row (BUG-sqlrowwiseoom)
        var pdv = Pdv.init(arena);
        var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
        for (grp, 0..) |ri, k| {
            try loadForEval(&pdv, ds, ds.row(ri));
            vals[k] = evalCase(arena, diags, &ev, inner) catch Value.missing;
        }
    } else {
        var pdv = Pdv.init(arena);
        var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
        var wp = pe.Parser.init(arena, try withEof(arena, arg), diags);
        const expr = wp.parseExpr() catch {
            unsupported("PROC SQL: unsupported aggregate argument expression");
            return Value.missing;
        };
        for (grp, 0..) |ri, k| {
            try loadForEval(&pdv, ds, ds.row(ri));
            vals[k] = ev.eval(expr) catch Value.missing;
        }
    }
    if (f == .count or f == .n or f == .nmiss) {
        var n: usize = 0; // count of NON-missing (distinct applies only to COUNT)
        var seen: DistinctSet = .empty; // COUNT(DISTINCT) membership — O(1)/row (PERF-sqlcountdistinct)
        for (vals) |v| {
            if (aggMissing(v)) continue;
            if (distinct and f == .count and !(try distinctFirst(arena, &seen, v))) continue;
            n += 1;
        }
        // BUG-sqlnnmiss: N = non-missing count; NMISS = missing count.
        return .{ .num = @floatFromInt(if (f == .nmiss) vals.len - n else n) };
    }
    if (f == .min or f == .max) {
        var best: ?Value = null;
        for (vals) |v| {
            if (v.isMissing()) continue;
            if (best) |b| {
                const ord = cmpVal(v, b);
                if ((f == .min and ord == .lt) or (f == .max and ord == .gt)) best = v;
            } else best = v;
        }
        return best orelse Value.missing;
    }
    // BUG-sqlsumwgtcharzero: character-argument guard for the EXPRESSION path
    // (e.g. sumwgt(upcase(b))) — an expression has no declared type, so test the
    // evaluated values: any .str means the argument resolves character, which
    // SAS rejects for every aggregate still live below (SUM/AVG + the isStatAgg
    // set; COUNT/N/NMISS and MIN/MAX returned above and stay type-agnostic).
    // An all-missing NUMERIC expression is .num-NaN throughout and passes
    // untouched, so the SUMWGT=0 all-missing pins are unaffected.
    // ponytail: a zero-row group evaluates nothing, so a char expression over an
    // EMPTY table slips past — detecting that needs static expression typing.
    for (vals) |v|
        if (v == .str)
            return diags.fail(error.ParseError, if (arg.len > 0) arg[0].line else 0, "PROC SQL: summary function {s} requires a numeric argument", .{aggName(f)});
    if (isStatAgg(f)) {
        const xs = try arena.alloc(f64, vals.len);
        var m: usize = 0;
        for (vals) |v| {
            const x = toNum(v);
            if (std.math.isNan(x)) continue;
            xs[m] = x;
            m += 1;
        }
        return statAgg(f, xs[0..m]);
    }
    var cnt: usize = 0;
    var sum: f64 = 0;
    var seen: DistinctSet = .empty; // SUM/AVG(DISTINCT) dedup — same membership as COUNT(DISTINCT) (BUG-sqldistinctagg)
    for (vals) |v| {
        const x = toNum(v);
        if (std.math.isNan(x)) continue;
        if (distinct and !(try distinctFirst(arena, &seen, v))) continue;
        cnt += 1;
        sum += x;
    }
    if (cnt == 0) return Value.missing;
    const r: f64 = switch (f) {
        .sum => sum,
        .avg => sum / @as(f64, @floatFromInt(cnt)),
        else => unreachable,
    };
    return if (std.math.isFinite(r)) .{ .num = r } else Value.missing;
}

/// Build the joined table for `T1 [inner|left] join T2 on <cond>`: a dataset
/// whose columns are qualified `T1.col` / `T2.col`. A nested loop pairs rows and
/// keeps those satisfying ON; a LEFT join also keeps each unmatched T1 row with
/// missing T2 columns. ponytail: O(n·m) nested loop — fine for corpus sizes.
/// Build the joined table for `T1 <join>*`. Start from a qualified copy of T1,
/// then fold each JoinStep in (cross = Cartesian, inner = ON-matching pairs, left
/// = also unmatched left rows with missing right columns). Columns end up
/// qualified `Table.col`. ponytail: O(product) nested loops — fine for corpus sizes.
/// PERF-sqlcommajoin: a comma (cross) step whose equijoin predicate sits in the
/// query WHERE (`from a, b, c where a.k=b.k and b.k=c.k`) — pick the top-level
/// `col = col` conjuncts that link the accumulated left side with THIS step's
/// table and return them as a synthetic ON, so joinTwo's hash fast path runs
/// instead of materializing the cartesian product (O(∏N) time+RAM). The full
/// WHERE still filters afterward, so the result rows are unchanged. Null →
/// nothing links this step (a real cross join) → the nested loop, as before.
fn commaStepOn(arena: std.mem.Allocator, acc: *Dataset, t2: *Dataset, t2q: []const u8, wtoks: []const Token) diag.Error!?[]const Token {
    if (hasCase(wtoks)) return null; // `and` inside CASE…WHEN is not a top-level conjunct — bail
    var on: std.ArrayList(Token) = .empty;
    var depth: usize = 0;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= wtoks.len) : (i += 1) {
        if (i < wtoks.len) {
            switch (wtoks[i].tag) {
                .lparen => {
                    depth += 1;
                    continue;
                },
                .rparen => {
                    if (depth > 0) depth -= 1;
                    continue;
                },
                else => if (depth > 0 or !tkKw(wtoks[i], "and")) continue,
            }
        }
        // wtoks[start..i] is one top-level conjunct (or the tail at i == len).
        var conj = wtoks[start..i];
        start = i + 1;
        // strip fully-wrapping parens: `(a.k = b.k)` → `a.k = b.k`
        while (conj.len >= 2 and conj[0].tag == .lparen) {
            var d: usize = 0;
            var m: usize = 0;
            while (m < conj.len) : (m += 1) {
                if (conj[m].tag == .lparen) d += 1 else if (conj[m].tag == .rparen) {
                    d -= 1;
                    if (d == 0) break;
                }
            }
            if (m != conj.len - 1) break; // not fully wrapped
            conj = conj[1 .. conj.len - 1];
        }
        if (conj.len != 3 or conj[0].tag != .name or conj[2].tag != .name) continue;
        if (conj[1].tag != .eq and !tkKw(conj[1], "eq")) continue;
        // Same acceptance as extractEqKeys: exactly one side in acc, the other
        // in t2, matching column types (a char=num pair coerces in eval but
        // never shares a hash key — leave it to the loop).
        const l_acc = resolveCol(acc, conj[0].text);
        const r_acc = resolveCol(acc, conj[2].text);
        const l_t2 = t2ColOf(t2, t2q, conj[0].text);
        const r_t2 = t2ColOf(t2, t2q, conj[2].text);
        const key: ?EqKey = if (l_acc != null and l_t2 == null and r_t2 != null and r_acc == null)
            .{ .left = l_acc.?, .right = r_t2.? }
        else if (r_acc != null and r_t2 == null and l_t2 != null and l_acc == null)
            .{ .left = r_acc.?, .right = l_t2.? }
        else
            null;
        if (key) |k| {
            if (acc.columns.items[k.left].type == t2.columns.items[k.right].type) {
                if (on.items.len > 0) try on.append(arena, synName("and"));
                try appendAll(arena, &on, conj);
            }
        }
    }
    return if (on.items.len > 0) on.items else null;
}

fn buildJoin(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, t1name: []const u8, t1alias: ?[]const u8, t1opts: ?[]const Token, joins: []const JoinStep, where: ?[]const Token) !?*Dataset {
    const t1 = try withOptions(arena, diags, lib.find(t1name) orelse {
        if (isUnsupportedDict(t1name)) unsupportedDict(arena, t1name) else unsupported("PROC SQL: FROM table not found");
        return null;
    }, t1opts); // GH#33: apply the FROM table's dataset options before joining
    var acc = try arena.create(Dataset);
    acc.* = Dataset.init(arena, "_join");
    // An alias hides the table name — qualify columns by it so `x.col` resolves
    // and a self-join's two sides get distinct qualifiers (BUG-sqljoinalias).
    const t1q = t1alias orelse t1name;
    for (t1.columns.items) |c| _ = try acc.addColumnLike(try qualify(arena, t1q, c.name), c); // GH#49: keep format
    try acc.rows.appendSlice(arena, t1.rows.items); // same values, requalified columns

    for (joins) |step_in| {
        var step = step_in;
        // An inline view `join (select …) alias` materializes the subquery into a
        // temp dataset, mirroring the FROM derived-table path (GH#14).
        const t2 = if (step.from_sub) |subtoks| blk: {
            const res = (try execSelect(arena, lib, diags, subtoks)) orelse return null;
            const sub = try arena.create(Dataset);
            sub.* = Dataset.init(arena, step.alias orelse "_joinsub");
            try addResultCols(sub, res.cols); // GH#49: carry attached formats through the inline view
            for (res.rows) |row| try sub.appendRow(row);
            break :blk sub;
        } else try withOptions(arena, diags, lib.find(step.table) orelse {
            if (isUnsupportedDict(step.table)) unsupportedDict(arena, step.table) else unsupported("PROC SQL: JOIN table not found");
            return null;
        }, step.opts); // GH#33: apply the joined table's dataset options
        // PERF-sqlcommajoin: a comma step has no ON — push the top-level
        // `col = col` WHERE conjuncts linking the accumulated left side with
        // this step's table into a synthetic ON so joinTwo's hash fast path
        // runs instead of materializing the cartesian product.
        if (step.kind == .cross and step.on == null) {
            if (where) |wt| step.on = try commaStepOn(arena, acc, t2, step.alias orelse step.table, wt);
        }
        acc = (try joinTwo(arena, diags, acc, step, t2)) orelse return null;
    }
    return acc;
}

/// Join the accumulated (already-qualified) result with one more table.
fn joinTwo(arena: std.mem.Allocator, diags: *diag.Diagnostics, acc: *Dataset, step: JoinStep, t2: *Dataset) !?*Dataset {
    const joined = try arena.create(Dataset);
    joined.* = Dataset.init(arena, "_join");
    for (acc.columns.items) |c| _ = try joined.addColumnLike(c.name, c); // already qualified; keep format (GH#49)
    const t2q = step.alias orelse step.table; // alias hides the table name
    for (t2.columns.items) |c| _ = try joined.addColumnLike(try qualify(arena, t2q, c.name), c); // GH#49: keep format

    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    const oncond = if (step.on) |ot| blk: {
        var wp = pe.Parser.init(arena, try withEof(arena, ot), diags);
        break :blk wp.parseExpr() catch {
            unsupported("PROC SQL: unsupported JOIN condition");
            return null;
        };
    } else null;

    const n1 = acc.columns.items.len;
    const n2 = t2.columns.items.len;
    // LEFT/FULL keep unmatched left rows; RIGHT/FULL keep unmatched right rows.
    const keep_left = step.kind == .left or step.kind == .full;
    const keep_right = step.kind == .right or step.kind == .full;
    const r2_matched = try arena.alloc(bool, t2.rows.items.len);
    @memset(r2_matched, false);

    // Equi-join fast path (BUG-sqljoinoom): an ON that is a conjunction of
    // `col = col` equalities hash-joins in O(n+m+matches). The nested loop
    // below allocated per PAIR (the qualify() names alone), so a large program's
    // lb×lbref left join grew the run arena past 16GB and OOMed. Key bytes
    // mirror eval.cmp equality exactly (trailing-blank-insensitive chars,
    // -0==+0, special-missing ranks) → same rows, same order as the loop.
    if (oncond) |cond| eq: {
        var keys: std.ArrayList(EqKey) = .empty;
        if (!try extractEqKeys(arena, acc, t2, t2q, cond, &keys)) break :eq;
        var map: std.StringHashMapUnmanaged(std.ArrayList(usize)) = .empty;
        var kb: std.ArrayList(u8) = .empty;
        for (t2.rows.items, 0..) |r2, ri2| {
            kb.clearRetainingCapacity();
            for (keys.items) |k| try appendJoinKey(&kb, arena, r2[k.right]);
            const g = try map.getOrPut(arena, kb.items);
            if (!g.found_existing) {
                g.key_ptr.* = try arena.dupe(u8, kb.items);
                g.value_ptr.* = .empty;
            }
            try g.value_ptr.append(arena, ri2); // scan order → t2 row order per bucket
        }
        for (acc.rows.items) |r1| {
            kb.clearRetainingCapacity();
            for (keys.items) |k| try appendJoinKey(&kb, arena, r1[k.left]);
            var matched = false;
            if (map.get(kb.items)) |bucket| for (bucket.items) |ri2| {
                matched = true;
                r2_matched[ri2] = true;
                const cells = try arena.alloc(Value, n1 + n2);
                @memcpy(cells[0..n1], r1);
                @memcpy(cells[n1..], t2.rows.items[ri2]);
                try joined.appendRow(cells);
            };
            if (keep_left and !matched) {
                const cells = try arena.alloc(Value, n1 + n2);
                @memcpy(cells[0..n1], r1);
                for (t2.columns.items, 0..) |c, j| cells[n1 + j] = missingOf(c.type);
                try joined.appendRow(cells);
            }
        }
        if (keep_right) for (t2.rows.items, 0..) |r2, ri2| {
            if (r2_matched[ri2]) continue;
            const cells = try arena.alloc(Value, n1 + n2);
            for (acc.columns.items, 0..) |c, j| cells[j] = missingOf(c.type);
            @memcpy(cells[n1..], r2);
            try joined.appendRow(cells);
        };
        return joined;
    }

    for (acc.rows.items) |r1| {
        var matched = false;
        for (t2.rows.items, 0..) |r2, ri2| {
            if (oncond) |cond| {
                try loadForEval(&pdv, acc, r1);
                for (t2.columns.items, 0..) |c, j| {
                    // joined's schema already holds the qualified name — reuse it;
                    // an allocPrint here ran once per PAIR and OOMed (BUG-sqljoinoom)
                    const nm = joined.columns.items[n1 + j].name;
                    try bindCol(&pdv, nm, c.type, c.len, r2[j]);
                    // Pass the QUALIFIED nm so aliasUnqualified defines the bare
                    // name too — an unqualified joined-col ref in ON (`d>lo`) must
                    // resolve, not read missing (BUG-sqljoinunqual).
                    try aliasUnqualified(&pdv, nm, c.type, c.len, r2[j]);
                }
                if (!(try ev.eval(cond)).truthy()) continue;
            }
            matched = true;
            r2_matched[ri2] = true;
            const cells = try arena.alloc(Value, n1 + n2);
            @memcpy(cells[0..n1], r1);
            @memcpy(cells[n1..], r2);
            try joined.appendRow(cells);
        }
        if (keep_left and !matched) { // left row with no right match → right side missing
            const cells = try arena.alloc(Value, n1 + n2);
            @memcpy(cells[0..n1], r1);
            for (t2.columns.items, 0..) |c, j| cells[n1 + j] = missingOf(c.type);
            try joined.appendRow(cells);
        }
    }
    if (keep_right) for (t2.rows.items, 0..) |r2, ri2| {
        if (r2_matched[ri2]) continue; // right row with no left match → left side missing
        const cells = try arena.alloc(Value, n1 + n2);
        for (acc.columns.items, 0..) |c, j| cells[j] = missingOf(c.type);
        @memcpy(cells[n1..], r2);
        try joined.appendRow(cells);
    };
    return joined;
}

/// One equi-join key: aligned column indices in the accumulated left side and
/// the joined-in right table (BUG-sqljoinoom).
const EqKey = struct { left: usize, right: usize };

/// `name` resolved as a column of the joined-in table `t2` (columns stored
/// UNqualified): a `q.col` ref must carry t2's qualifier `t2q`; bare `col`
/// resolves directly. Null if it isn't a t2 column.
fn t2ColOf(t2: *Dataset, t2q: []const u8, name: []const u8) ?usize {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |dot| {
        if (!eqi(name[0..dot], t2q)) return null;
        return t2.indexOf(name[dot + 1 ..]);
    }
    return t2.indexOf(name);
}

/// Try to read `e` as a conjunction of `col = col` equalities, each pairing one
/// acc column with one t2 column; append the pairs. False → not a pure
/// equi-join, caller falls back to the nested loop. Conservative bails: a ref
/// resolving in BOTH tables (ambiguous) or NEITHER, and a char=num key (its
/// per-pair coercion notes belong to the loop path).
fn extractEqKeys(arena: std.mem.Allocator, acc: *Dataset, t2: *Dataset, t2q: []const u8, e: *const ast.Expr, out: *std.ArrayList(EqKey)) diag.Error!bool {
    if (e.* != .binary) return false;
    const b = e.binary;
    switch (b.op) {
        .@"and" => return (try extractEqKeys(arena, acc, t2, t2q, b.lhs, out)) and
            (try extractEqKeys(arena, acc, t2, t2q, b.rhs, out)),
        .eq => {},
        else => return false,
    }
    if (b.lhs.* != .variable or b.rhs.* != .variable) return false;
    const l_acc = resolveCol(acc, b.lhs.variable);
    const r_acc = resolveCol(acc, b.rhs.variable);
    const l_t2 = t2ColOf(t2, t2q, b.lhs.variable);
    const r_t2 = t2ColOf(t2, t2q, b.rhs.variable);
    const key: EqKey = if (l_acc != null and l_t2 == null and r_t2 != null and r_acc == null)
        .{ .left = l_acc.?, .right = r_t2.? }
    else if (r_acc != null and r_t2 == null and l_t2 != null and l_acc == null)
        .{ .left = r_acc.?, .right = l_t2.? }
    else
        return false;
    if (acc.columns.items[key.left].type != t2.columns.items[key.right].type) return false;
    try out.append(arena, key);
    return true;
}

/// Append one value's join-key bytes, faithful to eval.cmp equality: char keys
/// drop trailing blanks (blank-padded compare), numeric keys are the IEEE bits
/// with -0 canonicalized to +0, and missings key by SAS rank so `.` from ANY
/// NaN payload matches `.` and `.A` stays distinct. Components are
/// fixed-length or length-framed, so multi-key concatenation can't collide.
fn appendJoinKey(kb: *std.ArrayList(u8), arena: std.mem.Allocator, v: Value) !void {
    switch (v) {
        .num => |x| if (std.math.isNan(x)) {
            try kb.appendSlice(arena, &.{ 'M', Value.missingRank(x) });
        } else {
            const canon: f64 = if (x == 0) 0 else x; // -0 == +0 under `=`
            try kb.append(arena, 'N');
            try kb.appendSlice(arena, std.mem.asBytes(&canon));
        },
        .str => |s| {
            const tr = std.mem.trimEnd(u8, s, " ");
            const len: u32 = @intCast(tr.len);
            try kb.append(arena, 'S');
            try kb.appendSlice(arena, std.mem.asBytes(&len));
            try kb.appendSlice(arena, tr);
        },
    }
}

/// A column reference: exact match first (qualified or plain), else a unique
/// match on the unqualified name (`x` finds `a.x`). Null if unknown.
fn resolveCol(ds: *Dataset, name: []const u8) ?usize {
    if (ds.indexOf(name)) |j| return j;
    for (ds.columns.items, 0..) |c, j| if (eqi(unqualify(c.name), name)) return j;
    // A `qualifier.col` lookup (e.g. `t.g`) against an UNqualified column resolves on
    // the bare name — the single-source case: `from x as t` and derived tables store
    // columns unqualified, so `t.g` never matched (BUG-sqlqualcol). Restricted to
    // dot-free columns so a JOIN's qualified columns (`a.g`/`b.g`) are never
    // cross-matched by the wrong qualifier.
    const bare = unqualify(name);
    if (bare.len != name.len)
        for (ds.columns.items, 0..) |c, j|
            if (std.mem.indexOfScalar(u8, c.name, '.') == null and eqi(c.name, bare)) return j;
    return null;
}

/// The SAS "columns were not found" ERROR for a SELECT/CREATE-AS column that
/// resolved to nothing — recorded so the failure is the precise SAS message,
/// not main.zig's generic "unreported error" fallback (BUG-sqlupdatedropcol).
fn colNotFound(diags: *diag.Diagnostics, name: []const u8) diag.Error {
    return diags.fail(error.ParseError, 0, "PROC SQL: the following columns were not found in the contributing tables: {s}", .{unqualify(name)});
}

/// Bind one value into the PDV under `name`, CARRYING the column's declared char
/// width — BUG-sqlcolwidthloss. Every SQL bind goes through here; the row loader
/// used to `define(name, type)` and drop `len`, so LENGTHC/VLENGTH inside PROC SQL
/// read the VALUE's byte count where the DATA step reads the STORAGE length:
/// `lengthc(b)` was 2 in PROC SQL and 4 in a DATA step for the same `$4` column
/// holding 'AB'.
///
/// SQL Procedure User's Guide, printed p.37 ("Specifying Column Attributes"),
/// lists LENGTH= as one of four column attributes and settles the default:
/// "If you do not specify these attributes, then PROC SQL uses attributes that
/// are already saved in the table" — so a column keeps its saved width. opensas
/// stores char values UNPADDED (EPIC-charfixedwidth deferred) where SAS pads to
/// the declared length (printed p.362, BTRIM note: a length-10 variable holding
/// `xxabcxx` is stored "with three blanks after the last x"), so the width rides
/// along as the PDV var's `len` — exactly as the DATA step's SET loader carries a
/// source column's width (exec.seedColumnsOf, BUG-vlength).
///
/// The bind is AUTHORITATIVE: a null width CLEARS a width an earlier bind of this
/// name set, because the only way one name gets two widths in one scan is an
/// aliased computed item shadowing a same-named source column — and there the
/// expression governs, not the column. Leaving the column's width in place would
/// make `pdv.setAt` silently TRUNCATE the computed value a `calculated` reference
/// then reads.
///
/// ponytail: char only. A numeric `Column.len` is the NUMLEN byte-length (GH#59),
/// whose PDV twin is `numlen` and whose store-side effect is bit-truncation of the
/// double (GH#46) — carrying it would change numeric VALUES, which no reported
/// symptom asks for. Wire it when a fixture needs SQL to honour numeric LENGTH.
fn bindCol(pdv: *Pdv, name: []const u8, ty: VarType, len: ?usize, v: Value) !void {
    const i = try pdv.define(name, ty);
    if (ty == .char) pdv.vars.items[i].len = len orelse 0;
    try pdv.set(name, v);
}

/// A pass-through column's output descriptor: `select col` — even `col as alias`,
/// even `*` — carries EVERY attribute already saved on the source column: the
/// attached format/informat/label (GH#49) and the declared LENGTH (p.37 again,
/// BUG-sqlcolwidthloss). A computed/aggregate/CASE/literal item is NOT a
/// pass-through and gets none of them: this volume assigns no width to a derived
/// column, so none is invented (DOC-SILENT — the width then falls back to the
/// data-derived one, unchanged from before). An explicit SELECT `length=n` still
/// overrides, via applyItemMods (p.368, LENGTH= column-modifier).
fn passCol(name: []const u8, c: Column) OutCol {
    return .{ .name = name, .type = c.type, .format = c.format, .informat = c.informat, .label = c.label, .len = c.len };
}

/// Load a row into the PDV under each column's qualified name AND its unqualified
/// alias, so a join's ON/WHERE may reference either `a.x` or (unambiguous) `x`.
fn loadForEval(pdv: *Pdv, ds: *Dataset, row: []const Value) !void {
    try loadForEvalAlias(pdv, ds, row, null);
}

/// As loadForEval, but a single-table column `col` also answers to `<alias>.col`
/// (the query's `from T alias`), so a correlated subquery's own `alias.col`
/// references resolve — BUG-sqlcorrscalar.
fn loadForEvalAlias(pdv: *Pdv, ds: *Dataset, row: []const Value, alias: ?[]const u8) !void {
    for (ds.columns.items, 0..) |c, j| {
        try bindCol(pdv, c.name, c.type, c.len, row[j]);
        try aliasUnqualified(pdv, c.name, c.type, c.len, row[j]);
        // A single-table column `id` also answers to its table-qualified form
        // `<table>.id`, so a WHERE/subquery may write `b.id` (BUG-sqlexists).
        if (std.mem.indexOfScalar(u8, c.name, '.') == null) {
            const q = try std.fmt.allocPrint(pdv.arena, "{s}.{s}", .{ unqualify(ds.name), c.name });
            try bindCol(pdv, q, c.type, c.len, row[j]);
            if (alias) |al| if (!eqi(al, unqualify(ds.name))) {
                const qa = try std.fmt.allocPrint(pdv.arena, "{s}.{s}", .{ al, c.name });
                try bindCol(pdv, qa, c.type, c.len, row[j]);
            };
        }
    }
}

fn aliasUnqualified(pdv: *Pdv, name: []const u8, ty: VarType, len: ?usize, v: Value) !void {
    const u = unqualify(name);
    if (!eqi(u, name)) try bindCol(pdv, u, ty, len, v);
}

/// Outer-row binding for a correlated subquery: its `<table>.col` (or `<alias>.col`)
/// references are replaced with the values in row `ri` of `ds` before it runs.
const RowCtx = struct { ds: *Dataset, ri: usize, table: []const u8, alias: ?[]const u8 = null };

/// Replace each `(select …)` in a WHERE token stream with a literal: a scalar
/// subquery becomes its single value; one following `in` becomes a `(v1, v2, …)`
/// list. Non-subquery parentheses pass through untouched. When `corr` is set the
/// subquery is correlated to that outer row first (BUG-sqlcorrscalar), so it runs
/// per outer row with the correlation predicate bound.
fn substituteSubqueries(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, toks: []const Token, corr: ?RowCtx) diag.Error![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (!(toks[i].tag == .lparen and atKw(toks, i + 1, "select"))) {
            try out.append(arena, toks[i]);
            i += 1;
            continue;
        }
        var depth: usize = 1;
        var j = i + 1;
        while (j < toks.len) : (j += 1) {
            if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
                depth -= 1;
                if (depth == 0) break;
            }
        }
        const orig_inner = toks[i + 1 .. j];
        // A correlated subquery references the outer row and resolves per row; a
        // duplicate inner key there is first-match-wins (pinned: sql_corr_scalarsel),
        // NOT a cardinality error — so the >1-row scalar guard applies only when the
        // subquery is NOT correlated to the current outer context (BUG-sqlscalarsubqcard).
        const correlated = if (corr) |c| subqRefsOuter(orig_inner, c) else false;
        const inner = if (corr) |c| try correlateSubq(arena, orig_inner, c.ds, c.ri, c.table, c.alias) else orig_inner;
        const sq = parseQuery(arena, inner) catch {
            try out.append(arena, toks[i]); // not a real subquery — leave the '(' be
            i += 1;
            continue;
        };
        const res = (try execQuery(arena, lib, diags, sq)) orelse return error.ParseError;
        // GAP-sqladvanced: `L <cmp> ANY|SOME|ALL (select …)` — a quantified
        // comparison. The subquery may return MANY rows; collapse per SQL rules.
        if (quantPattern(out.items)) |qp| {
            try collapseQuantified(arena, &out, qp, res, toks[i].line, diags);
        } else {
        const is_in = out.items.len > 0 and tkKw(out.items[out.items.len - 1], "in");
        if (is_in) {
            // BUG-sqlinsubqcols: an IN-predicate subquery may select only ONE column.
            if (res.cols.len > 1)
                return diags.fail(error.ParseError, toks[i].line, "PROC SQL: the subquery of an IN predicate may have only one column", .{});
            try out.append(arena, .{ .tag = .lparen });
            for (res.rows, 0..) |row, ri| {
                if (ri > 0) try out.append(arena, .{ .tag = .comma });
                try out.append(arena, try valueToken(arena, if (row.len > 0) row[0] else Value.missing));
            }
            try out.append(arena, .{ .tag = .rparen });
        } else {
            // BUG-sqlscalarsubqcard: a scalar subquery must return at most one row —
            // SAS aborts otherwise; silently taking the first row is wrong.
            if (!correlated and res.rows.len > 1)
                return diags.fail(error.ParseError, toks[i].line, "PROC SQL: subquery evaluated to more than one row (or more than one value)", .{});
            const v = if (res.rows.len > 0 and res.rows[0].len > 0) res.rows[0][0] else Value.missing;
            try out.append(arena, try valueToken(arena, v));
        }
        }
        i = j + 1; // past the ')'
    }
    return out.items;
}

/// A comparison operator in a quantified `L <cmp> ANY|ALL (select …)`.
const QuantCmp = enum { eq, ne, lt, le, gt, ge };

fn quantCmpOf(tok: Token) ?QuantCmp {
    switch (tok.tag) {
        .eq => return .eq,
        .ne => return .ne,
        .lt => return .lt,
        .le => return .le,
        .gt => return .gt,
        .ge => return .ge,
        .max_op => return .ne, // `<>` is NE in a WHERE expression (parser_expr where_ctx)
        else => {},
    }
    if (tok.tag == .name) {
        if (tkKw(tok, "eq")) return .eq;
        if (tkKw(tok, "ne")) return .ne;
        if (tkKw(tok, "lt")) return .lt;
        if (tkKw(tok, "le")) return .le;
        if (tkKw(tok, "gt")) return .gt;
        if (tkKw(tok, "ge")) return .ge;
    }
    return null;
}

const QuantPat = struct { cmp: QuantCmp, all: bool };

/// The tail of `out` is `<cmp> ANY|SOME|ALL` — the keyword immediately before a
/// `(select …)` is unambiguously the quantifier (a column ref can't precede a
/// paren unless it's a call, and ANY/ALL take no argument list).
fn quantPattern(items: []const Token) ?QuantPat {
    if (items.len < 2) return null;
    const all = tkKw(items[items.len - 1], "all");
    if (!all and !tkKw(items[items.len - 1], "any") and !tkKw(items[items.len - 1], "some")) return null;
    const cmp = quantCmpOf(items[items.len - 2]) orelse return null;
    return .{ .cmp = cmp, .all = all };
}

/// Collapse a quantified comparison whose subquery yielded `res` (GAP-sqladvanced):
///   `= ANY` ⇔ IN, `<> ALL` ⇔ NOT IN — reuse the IN-predicate token shape;
///   `L > ANY S` ⇔ `L > min(S)`, `L <= ALL S` ⇔ `L <= max(S)` etc. — the whole
///   comparison reduces to ONE bound value (SAS ordering, missing sorts low), so
///   the comparison operator stays and only the keyword becomes the bound literal.
/// Empty set: ANY→false, ALL→true per SQL — the predicate becomes `L ne|eq L`.
fn collapseQuantified(arena: std.mem.Allocator, out: *std.ArrayList(Token), qp: QuantPat, res: Result, line: usize, diags: *diag.Diagnostics) diag.Error!void {
    if (res.cols.len > 1)
        return diags.fail(error.ParseError, line, "PROC SQL: the subquery of an ANY/ALL comparison may have only one column", .{});
    const n = out.items.len;
    if ((qp.cmp == .eq and !qp.all) or (qp.cmp == .ne and qp.all)) {
        if (res.rows.len == 0) return rewriteQuantEmpty(arena, diags, out, qp.all);
        out.items[n - 2] = if (qp.all) synName("not") else synName("in");
        out.items[n - 1] = if (qp.all) synName("in") else synTok(.lparen, "(");
        if (qp.all) try out.append(arena, synTok(.lparen, "("));
        for (res.rows, 0..) |row, ri| {
            if (ri > 0) try out.append(arena, .{ .tag = .comma });
            try out.append(arena, try valueToken(arena, if (row.len > 0) row[0] else Value.missing));
        }
        try out.append(arena, synTok(.rparen, ")"));
        return;
    }
    if (qp.cmp == .eq or qp.cmp == .ne) // `= ALL` / `<> ANY` — fail loud, never silently wrong
        return diags.fail(error.ParseError, line, "PROC SQL: {s} {s} quantified comparison is not supported (use {s})", .{
            if (qp.cmp == .eq) "=" else "<>",
            if (qp.all) "ALL" else "ANY",
            if (qp.cmp == .eq) "= ANY / IN instead" else "<> ALL / NOT IN instead",
        });
    if (res.rows.len == 0) return rewriteQuantEmpty(arena, diags, out, qp.all);
    const want_min = (qp.cmp == .gt or qp.cmp == .ge) != qp.all; // ANY: >/>=→min, </<=→max; ALL flips
    var best: Value = if (res.rows[0].len > 0) res.rows[0][0] else Value.missing;
    for (res.rows[1..]) |row| {
        const v = if (row.len > 0) row[0] else Value.missing;
        const o = cmpVal(v, best);
        if ((want_min and o == .lt) or (!want_min and o == .gt)) best = v;
    }
    out.items[n - 1] = try valueToken(arena, best); // keep the comparison op, replace ANY/ALL
}

/// Empty quantified set: `L op ANY ()` is FALSE, `L op ALL ()` TRUE (SQL).
/// Rewrite the whole predicate to `L ne L` / `L eq L` — constant and
/// type-agnostic (even missing equals itself in SAS).
fn rewriteQuantEmpty(arena: std.mem.Allocator, diags: *diag.Diagnostics, out: *std.ArrayList(Token), all: bool) diag.Error!void {
    out.shrinkRetainingCapacity(out.items.len - 2); // drop the cmp op + ANY/ALL keyword
    // ponytail: popLeftOperand takes a SINGLE operand (a compound `a+b` LHS keeps
    // `a+`) — same accepted ceiling as the BETWEEN desugar above.
    const L = try popLeftOperand(arena, diags, out);
    try appendAll(arena, out, L);
    try out.append(arena, synName(if (all) "eq" else "ne"));
    try appendAll(arena, out, L);
}

fn hasExists(toks: []const Token) bool {
    for (toks) |tk| if (tkKw(tk, "exists")) return true;
    return false;
}

/// True when the subquery body `inner` references the outer row via a qualified
/// `<outer_table>.col` / `<outer_alias>.col` — i.e. it is correlated to `corr`.
fn subqRefsOuter(inner: []const Token, corr: RowCtx) bool {
    for (inner) |tk| {
        if (tk.tag != .name) continue;
        const d = std.mem.indexOfScalar(u8, tk.text, '.') orelse continue;
        const q = tk.text[0..d];
        if ((eqi(q, corr.table) or (corr.alias != null and eqi(q, corr.alias.?))) and resolveCol(corr.ds, tk.text[d + 1 ..]) != null) return true;
    }
    return false;
}

fn hasSubquery(toks: []const Token) bool {
    for (toks[0 .. toks.len -| 1], 0..) |tk, i| if (tk.tag == .lparen and tkKw(toks[i + 1], "select")) return true;
    return false;
}

/// True when some `(select …)` in `toks` references an `<outer_table>.col` or
/// `<outer_alias>.col` (a correlated subquery), so it must run per outer row —
/// BUG-sqlcorrscalar.
fn hasCorrelatedSubq(toks: []const Token, ds: *Dataset, outer_table: []const u8, outer_alias: ?[]const u8) bool {
    var i: usize = 0;
    while (i < toks.len) {
        if (toks[i].tag == .lparen and atKw(toks, i + 1, "select")) {
            var depth: usize = 1;
            var j = i + 1;
            while (j < toks.len) : (j += 1) {
                if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            for (toks[i + 2 .. j]) |tk| {
                if (tk.tag == .name) if (std.mem.indexOfScalar(u8, tk.text, '.')) |d| {
                    const q = tk.text[0..d];
                    if ((eqi(q, outer_table) or (outer_alias != null and eqi(q, outer_alias.?))) and resolveCol(ds, tk.text[d + 1 ..]) != null) return true;
                };
            }
            i = j + 1;
        } else i += 1;
    }
    return false;
}

const RefKind = enum { inner, outer, neither };
const ClassifiedRef = struct { kind: RefKind, col: usize };

/// Classify a qualified `qualifier.col` correlation operand as an inner-table or
/// outer-table column reference (PERF-sqlcorrsubq). The qualifier decides the side
/// (inner = the subquery's table/alias, outer = q's table/alias); the full text is
/// then resolved against that dataset. Unqualified refs → `.neither` (bail): the
/// side would be ambiguous, and correctness beats guessing.
fn classifyRef(text: []const u8, q: Query, iq: Query, ds: *Dataset, itbl: *Dataset) ClassifiedRef {
    const dot = std.mem.lastIndexOfScalar(u8, text, '.') orelse return .{ .kind = .neither, .col = 0 };
    const qual = text[0..dot];
    if (eqi(qual, iq.table) or (iq.alias != null and eqi(qual, iq.alias.?)))
        return if (resolveCol(itbl, text)) |ci| .{ .kind = .inner, .col = ci } else .{ .kind = .neither, .col = 0 };
    if (eqi(qual, q.table) or (q.alias != null and eqi(qual, q.alias.?)))
        return if (resolveCol(ds, text)) |ci| .{ .kind = .outer, .col = ci } else .{ .kind = .neither, .col = 0 };
    return .{ .kind = .neither, .col = 0 };
}

/// PERF-sqlcorrsubq fast path. Recognizes a correlated WHERE that is a single
/// equality semi-join and resolves it by building the inner table's key-set ONCE
/// (reusing `appendJoinKey`'s eval.cmp-equal canonical bytes), then probing each
/// outer row — O(N+M) time/mem instead of re-executing the inner query per outer
/// row (O(N*M), the 4.7 GB OOM). Returns the kept row indices, or null to BAIL to
/// the correct per-row loop.
///
/// Fast path ONLY for these EXACT shapes (whole WHERE, nothing else):
///   `<outer.ocol> [NOT] IN (select <inner.icol> from <itbl> where <i.icol> = <o.ocol>)`
///   `[NOT] EXISTS (select * from <itbl> [as a] where <i.icol> = <o.ocol>)`
/// BAIL (return null) on ANYTHING else — conservative, correctness first:
///   • extra outer WHERE terms (AND/OR, trailing tokens after the subquery ')')
///   • inner WHERE not exactly `ref = ref`, or either operand unqualified
///   • not exactly one inner-qualified + one outer-qualified correlation operand
///   • inner has a JOIN / derived FROM / dataset-options / GROUP BY / HAVING /
///     ORDER BY / INTO, or its table is absent
///   • IN form: IN-lhs ≠ the outer correlation column, or the select is not the
///     single inner correlation column (agg/expr/CASE/`*`/multi-col → bail)
fn trySemiJoin(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, q: Query, ds: *Dataset) diag.Error!?std.ArrayList(usize) {
    _ = diags;
    const toks = q.where orelse return null;
    // ---- outer shape: `[<ocol>] [not] (in|exists) ( <sub> )` spanning the whole WHERE ----
    var negate = false;
    var is_exists = false;
    var ocol_tok: ?Token = null;
    var k: usize = 0;
    if (atTag(toks, 0, .name) and !tkKw(toks[0], "not") and !tkKw(toks[0], "exists")) {
        ocol_tok = toks[0]; // IN form: leading outer column
        k = 1;
        if (atKw(toks, k, "not")) {
            negate = true;
            k += 1;
        }
        if (!atKw(toks, k, "in")) return null;
        k += 1;
    } else {
        if (atKw(toks, k, "not")) {
            negate = true;
            k += 1;
        }
        if (!atKw(toks, k, "exists")) return null;
        is_exists = true;
        k += 1;
    }
    if (!atTag(toks, k, .lparen)) return null;
    var depth: usize = 1;
    var j = k + 1;
    while (j < toks.len) : (j += 1) {
        if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
            depth -= 1;
            if (depth == 0) break;
        }
    }
    if (j != toks.len - 1) return null; // tokens after the subquery ')' → compound WHERE → bail
    const sub = toks[k + 1 .. j];

    // ---- inner query: plain single-table select with exactly `ref = ref` WHERE ----
    if (!atKw(sub, 0, "select")) return null;
    const iq = parseQuery(arena, sub) catch return null;
    if (iq.joins.len != 0 or iq.from_sub != null or iq.from_opts != null or iq.group_exprs.len != 0 or iq.having != null or iq.order.len != 0 or iq.into.len != 0) return null;
    const itbl = lib.find(iq.table) orelse return null;
    const iwhere = iq.where orelse return null;
    if (iwhere.len != 3 or iwhere[1].tag != .eq or iwhere[0].tag != .name or iwhere[2].tag != .name) return null;

    const ra = classifyRef(iwhere[0].text, q, iq, ds, itbl);
    const rb = classifyRef(iwhere[2].text, q, iq, ds, itbl);
    var icol: usize = undefined;
    var ocol: usize = undefined;
    if (ra.kind == .inner and rb.kind == .outer) {
        icol = ra.col;
        ocol = rb.col;
    } else if (ra.kind == .outer and rb.kind == .inner) {
        ocol = ra.col;
        icol = rb.col;
    } else return null;

    if (!is_exists) {
        // IN-lhs must be the SAME outer column as the correlation; the inner SELECT
        // must be exactly that one inner correlation column (else the reduction to a
        // pure semi-join is invalid → bail).
        const lhs = resolveCol(ds, ocol_tok.?.text) orelse return null;
        if (lhs != ocol) return null;
        if (iq.star or iq.items.len != 1) return null;
        const it = iq.items[0];
        if (it.agg != null or it.expr_toks != null or it.case_toks != null or it.is_star or it.col == null) return null;
        if ((resolveCol(itbl, it.col.?) orelse return null) != icol) return null;
    }

    // ---- build itbl's icol key-set once, probe outer.ocol per row ----
    var set: std.StringHashMapUnmanaged(void) = .empty;
    var kb: std.ArrayList(u8) = .empty;
    for (itbl.rows.items) |r| {
        kb.clearRetainingCapacity();
        try appendJoinKey(&kb, arena, r[icol]);
        const g = try set.getOrPut(arena, kb.items);
        if (!g.found_existing) g.key_ptr.* = try arena.dupe(u8, kb.items);
    }
    var kept: std.ArrayList(usize) = .empty;
    for (ds.rows.items, 0..) |r, ri| {
        kb.clearRetainingCapacity();
        try appendJoinKey(&kb, arena, r[ocol]);
        if (set.contains(kb.items) != negate) try kept.append(arena, ri); // NOT flips membership
    }
    return kept;
}

/// The resolved pieces of a plain correlated scalar subquery in a SELECT list —
/// `(select <selcol> from <itbl> where <corr_icol> = <outer.ocol>)` (PERF-sqlcorrsubqsel).
/// When `agg` is set it is the AGGREGATE sibling (PERF-sqlcorrsubqsel-agg):
/// `(select <agg>(<agg_col>) from <itbl> where <corr_icol> = <outer.ocol>)`.
/// PERF-sqlcorrsubq-ineq widens the correlation WHERE to a top-level AND of
/// `ref OP ref` conjuncts: the equalities form a COMPOSITE bucket key
/// (`b.k1=a.k1 and b.k2=a.k2 …`), and at most one inequality on numeric columns
/// (`and b.v > a.v`) becomes a per-bucket sorted-prefix probe.
const ScalarShape = struct {
    itbl: *Dataset,
    eq_icols: []usize, // inner equality-key cols (composite-key order)
    eq_ocols: []usize, // their outer partners, same order
    sel_col: usize, // the plain inner value col (agg == null)
    agg: ?AggFn = null, // set → aggregate scalar subquery
    agg_star: bool = false, // count(*)
    agg_distinct: bool = false, // count(distinct …)
    agg_col: ?usize = null, // the aggregated column (null for count(*))
    ineq: ?IneqShape = null, // optional single inequality conjunct
};
/// One normalized inequality conjunct: the predicate is `inner.icol OP outer.ocol`
/// (operand order already flipped so the inner ref is on the left), OP ∈ lt/le/gt/ge.
const IneqShape = struct { icol: usize, ocol: usize, op: lex.Tag };
/// A prebuilt scalar-subquery lookup for one SELECT item: outer.eq_ocols key → the
/// inner value (FIRST matching row for a plain select, or the per-key aggregate
/// fold for an aggregate select). A key absent from the map → `miss` (missing for
/// a plain select; the empty-group fold — 0 for count/n, else missing — for an
/// aggregate), mirroring a no-match inner subquery's single-row result.
const ScalarSel = struct {
    map: std.StringHashMapUnmanaged(Value),
    ocols: []const usize, // outer equality-key cols (composite-key order)
    miss: Value,
    ineq: ?IneqSel = null, // set → binary-search the sorted bucket per outer row
};
/// Inequality fast-path state: per composite-equality-key bucket, the inner
/// inequality column's values sorted ONCE in SAS cmpNum order (missings first,
/// by rank), so count/min/max over `v OP t` is a binary search per outer row
/// (PERF-sqlcorrsubq-ineq: O(M log M) build + O(N log M) probes, was O(N·M)).
const IneqSel = struct {
    bmap: std.StringHashMapUnmanaged(IneqBucket),
    ocol: usize, // outer threshold column
    op: lex.Tag, // .lt/.le/.gt/.ge, normalized to `inner OP outer`
    f: AggFn, // .count/.min/.max only — sum/avg would reorder the f64 additions the
    // per-row path performs in table order (prefix sums over sorted values differ in
    // the last ulp → NOT byte-identical), so they stay on the per-row fallback.
    star: bool, // count(*)
    miss: Value, // key absent → the empty-group fold (count 0, min/max missing)
};
const IneqBucket = struct {
    v: []f64, // inner inequality-col values, sorted by cmpNumF (missings prefix)
    nmiss: usize, // leading missing count in v (the folds skip missings)
    wpref: []usize, // count(col) only: wpref[i+1] = non-missing-col count among v[0..i]
};
const IneqPair = struct { v: f64, w: usize };

/// cmpNum on raw f64 — SAS order: missings below every number, ranked among
/// themselves (._ < . < .A < … < .Z); -0 == +0. Mirrors eval.cmpNum exactly so the
/// sorted bucket answers the same set the per-row path's WHERE would pass.
fn cmpNumF(a: f64, b: f64) std.math.Order {
    const am = std.math.isNan(a);
    const bm = std.math.isNan(b);
    if (am and bm) return std.math.order(Value.missingRank(a), Value.missingRank(b));
    if (am) return .lt;
    if (bm) return .gt;
    return std.math.order(a, b);
}

fn ineqPairLess(_: void, a: IneqPair, b: IneqPair) bool {
    return cmpNumF(a.v, b.v) == .lt;
}

/// Reverse a comparison operator (used when the outer ref is the left operand).
fn flipCmp(op: lex.Tag) lex.Tag {
    return switch (op) { .lt => .gt, .gt => .lt, .le => .ge, .ge => .le, else => op };
}

/// First index whose value is NOT less than t (count of `v < t`).
fn lowerBoundF(vals: []const f64, thr: f64) usize {
    var lo: usize = 0;
    var hi: usize = vals.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (cmpNumF(vals[mid], thr) == .lt) lo = mid + 1 else hi = mid;
    }
    return lo;
}

/// First index whose value IS greater than t (count of `v <= t`).
fn upperBoundF(vals: []const f64, thr: f64) usize {
    var lo: usize = 0;
    var hi: usize = vals.len;
    while (lo < hi) {
        const mid = (lo + hi) / 2;
        if (cmpNumF(vals[mid], thr) == .gt) hi = mid else lo = mid + 1;
    }
    return lo;
}

/// Probe one sorted bucket with outer threshold `t`: count / min / max over the
/// inner inequality values `v` with `v OP t`, byte-identical to the per-row path's
/// computeAgg fold over the filtered bucket rows. A NaN `t` is normalized to plain
/// `.` — the per-row path substitutes the outer value via valueToken, which
/// degrades ANY missing (incl. special .A–.Z) to a plain `.` literal.
fn probeIneqSel(sel: *const IneqSel, key: []const u8, t0: f64) Value {
    const b = sel.bmap.get(key) orelse return sel.miss;
    const thr = if (std.math.isNan(t0)) Value.missing.num else t0;
    const vals = b.v;
    var lo: usize = 0; // qualifying range is [lo, hi) — a single inequality
    var hi: usize = vals.len; // bounds exactly one side
    switch (sel.op) {
        .gt => lo = upperBoundF(vals, thr),
        .ge => lo = lowerBoundF(vals, thr),
        .lt => hi = lowerBoundF(vals, thr),
        .le => hi = upperBoundF(vals, thr),
        else => unreachable,
    }
    switch (sel.f) {
        .count => {
            const n = if (sel.star) hi - lo else b.wpref[hi] - b.wpref[lo];
            return .{ .num = @floatFromInt(n) };
        },
        .min, .max => {
            const first = @max(lo, b.nmiss); // missings are the sorted prefix; folds skip them
            if (first >= hi) return Value.missing;
            const x = if (sel.f == .min) vals[first] else vals[hi - 1];
            return if (std.math.isFinite(x)) .{ .num = x } else Value.missing; // ±inf → missing, as computeAgg
        },
        else => unreachable,
    }
}

/// Detect the SAFE plain correlated scalar-subquery shape in a SELECT item's
/// expression (PERF-sqlcorrsubqsel, case (a)): the item is EXACTLY
/// `(select <plain col> from <itbl> where <ref> = <ref>)` with a single equality
/// correlation (one inner-qualified + one outer-qualified operand) over a plain
/// table. Also accepts the AGGREGATE sibling (PERF-sqlcorrsubqsel-agg): a single
/// safe `count|sum|avg|min|max(<plain col>)` select (count(*) too). Returns null
/// (→ per-row path) on ANYTHING else — an expression around the subquery, DISTINCT,
/// an unsupported/expression-arg aggregate, an absent/non-conjunctive inner WHERE,
/// unqualified refs, or inner join/derived/from-opts/GROUP BY/HAVING/ORDER/INTO.
/// Conservative: correctness beats coverage.
fn detectScalarSubq(arena: std.mem.Allocator, lib: *Library, q: Query, ds: *Dataset, expr_toks: []const Token) diag.Error!?ScalarShape {
    if (expr_toks.len < 2 or expr_toks[0].tag != .lparen) return null;
    var depth: usize = 1;
    var j: usize = 1;
    while (j < expr_toks.len) : (j += 1) {
        if (expr_toks[j].tag == .lparen) depth += 1 else if (expr_toks[j].tag == .rparen) {
            depth -= 1;
            if (depth == 0) break;
        }
    }
    if (j != expr_toks.len - 1) return null; // more than just `( … )` → not a pure scalar subquery
    const sub = expr_toks[1..j];
    if (!atKw(sub, 0, "select")) return null;
    const iq = parseQuery(arena, sub) catch return null;
    if (iq.joins.len != 0 or iq.from_sub != null or iq.from_opts != null or iq.group_exprs.len != 0 or iq.having != null or iq.order.len != 0 or iq.into.len != 0 or iq.distinct) return null;
    const itbl = lib.find(iq.table) orelse return null;
    const iwhere = iq.where orelse return null;
    // PERF-sqlcorrsubq-ineq: the inner WHERE is a top-level AND of `ref OP ref`
    // conjuncts. Each operand must be one inner-qualified + one outer-qualified
    // column ref (either order). Equalities form the composite bucket key; at most
    // one inequality (numeric columns only — the sorted-prefix probe mirrors
    // eval.cmpNum) rides along. Anything else (OR/NOT/parens, an inner-only or
    // outer-only conjunct, a second inequality) → per-row fallback.
    var eq_icols: std.ArrayList(usize) = .empty;
    var eq_ocols: std.ArrayList(usize) = .empty;
    var ineq: ?IneqShape = null;
    var wi: usize = 0;
    while (wi < iwhere.len) {
        if (wi + 3 > iwhere.len or iwhere[wi].tag != .name or iwhere[wi + 2].tag != .name) return null;
        const op = iwhere[wi + 1].tag;
        switch (op) {
            .eq, .lt, .le, .gt, .ge => {},
            else => return null,
        }
        const ra = classifyRef(iwhere[wi].text, q, iq, ds, itbl);
        const rb = classifyRef(iwhere[wi + 2].text, q, iq, ds, itbl);
        var icol: usize = undefined;
        var ocol: usize = undefined;
        var flip = false;
        if (ra.kind == .inner and rb.kind == .outer) {
            icol = ra.col;
            ocol = rb.col;
        } else if (ra.kind == .outer and rb.kind == .inner) {
            ocol = ra.col;
            icol = rb.col;
            flip = true;
        } else return null;
        // a char/num column-type mix would COERCE in eval's compare but never
        // share a join key → bail (the single-= gate had this hole; don't widen it).
        if (itbl.columns.items[icol].type != ds.columns.items[ocol].type) return null;
        if (op == .eq) {
            try eq_icols.append(arena, icol);
            try eq_ocols.append(arena, ocol);
        } else {
            if (ineq != null) return null; // a second inequality conjunct → per-row
            if (itbl.columns.items[icol].type != .num) return null; // sorted probe is numeric-only
            ineq = .{ .icol = icol, .ocol = ocol, .op = if (flip) flipCmp(op) else op };
        }
        wi += 3;
        if (wi < iwhere.len) {
            if (!tkKw(iwhere[wi], "and")) return null;
            wi += 1;
        }
    }
    if (eq_icols.items.len == 0) return null; // nothing to bucket on
    // exactly one SELECT item: a plain inner column, or a safe aggregate over one.
    // an expression/CASE/`*`/multi-column select falls back to per-row.
    if (iq.star or iq.items.len != 1) return null;
    const it = iq.items[0];
    if (it.expr_toks != null or it.case_toks != null or it.is_star) return null;
    if (it.agg) |f| {
        // PERF-sqlcorrsubqsel-agg: whitelist the folds we accumulate per key; an
        // expression arg (computeAggExpr) or stat/median fold → bail to per-row.
        switch (f) {
            .count, .sum, .avg, .min, .max => {},
            else => return null,
        }
        if (it.agg_arg != null) return null;
        const agg_col: ?usize = if (it.agg_star) null else if (it.col) |c| (resolveCol(itbl, unqualify(c)) orelse return null) else return null;
        if (ineq != null) {
            // Inequality-filtered fold: only order-exact aggregates — count (an
            // integer) and min/max (order-independent), min/max restricted to the
            // inequality column itself so the sorted values answer it directly.
            // sum/avg need sorted-order prefix sums, which reorder the f64
            // additions the per-row path does in table order (last-ulp drift →
            // NOT byte-identical), so they keep the correct per-row fallback.
            switch (f) {
                .count, .min, .max => {},
                else => return null,
            }
            if (it.agg_distinct) return null;
            if (f != .count and (agg_col == null or agg_col.? != ineq.?.icol)) return null;
        }
        return .{ .itbl = itbl, .eq_icols = eq_icols.items, .eq_ocols = eq_ocols.items, .sel_col = 0, .agg = f, .agg_star = it.agg_star, .agg_distinct = it.agg_distinct, .agg_col = agg_col, .ineq = ineq };
    }
    if (it.col == null) return null;
    if (ineq != null) return null; // a plain first-match select can't use the sorted bucket
    const sel_col = resolveCol(itbl, it.col.?) orelse return null;
    return .{ .itbl = itbl, .eq_icols = eq_icols.items, .eq_ocols = eq_ocols.items, .sel_col = sel_col };
}

/// Build the composite equality key for one row (PERF-sqlcorrsubq-ineq): each
/// component goes through appendJoinKey, whose fixed-length/length-framed bytes
/// make concatenation collision-free (see its doc).
fn appendCompositeKey(kb: *std.ArrayList(u8), arena: std.mem.Allocator, row: []const Value, cols: []const usize) !void {
    for (cols) |ci| try appendJoinKey(kb, arena, row[ci]);
}

/// Build the outer.eq_ocols → first-matching inner-value map for a detected scalar
/// subquery (PERF-sqlcorrsubqsel). First-match per key mirrors the per-row path's
/// `res.rows[0][0]` (inner rows scanned in table order).
fn buildScalarSel(arena: std.mem.Allocator, diags: *diag.Diagnostics, sh: ScalarShape) diag.Error!ScalarSel {
    var map: std.StringHashMapUnmanaged(Value) = .empty;
    var kb: std.ArrayList(u8) = .empty;
    if (sh.agg) |f| {
        if (sh.ineq) |iqsh| {
            // PERF-sqlcorrsubq-ineq: bucket inner rows by the composite equality
            // key ONCE, sort each bucket's inequality-col values (SAS cmpNum order),
            // then count/min/max per outer row by binary search — O(M log M) build,
            // O(N log M) probes, instead of re-executing the inner query per row.
            const want_w = f == .count and sh.agg_col != null;
            var pbuckets: std.StringHashMapUnmanaged(std.ArrayList(IneqPair)) = .empty;
            for (sh.itbl.rows.items) |r| {
                kb.clearRetainingCapacity();
                try appendCompositeKey(&kb, arena, r, sh.eq_icols);
                const g = try pbuckets.getOrPut(arena, kb.items);
                if (!g.found_existing) {
                    g.key_ptr.* = try arena.dupe(u8, kb.items);
                    g.value_ptr.* = .empty;
                }
                try g.value_ptr.append(arena, .{ .v = toNum(r[iqsh.icol]), .w = if (want_w and !aggMissing(r[sh.agg_col.?])) 1 else 0 });
            }
            var bmap: std.StringHashMapUnmanaged(IneqBucket) = .empty;
            var pit = pbuckets.iterator();
            while (pit.next()) |e| {
                const pairs = e.value_ptr.items;
                std.mem.sort(IneqPair, pairs, {}, ineqPairLess);
                const vals = try arena.alloc(f64, pairs.len);
                var wpref: []usize = &.{};
                if (want_w) wpref = try arena.alloc(usize, pairs.len + 1);
                var nmiss: usize = 0;
                for (pairs, 0..) |p, pi| {
                    vals[pi] = p.v;
                    if (std.math.isNan(p.v)) nmiss += 1;
                    if (want_w) wpref[pi + 1] = wpref[pi] + p.w;
                }
                try bmap.put(arena, e.key_ptr.*, .{ .v = vals, .nmiss = nmiss, .wpref = wpref });
            }
            // a key with no inner rows → the empty-group fold (count 0, else missing).
            const miss: Value = if (f == .count) .{ .num = 0 } else Value.missing;
            return .{ .map = map, .ocols = sh.eq_ocols, .miss = miss, .ineq = .{ .bmap = bmap, .ocol = iqsh.ocol, .op = iqsh.op, .f = f, .star = sh.agg_star, .miss = miss } };
        }
        // PERF-sqlcorrsubqsel-agg: bucket inner rows by correlation key ONCE, then
        // fold each bucket with the SAME computeAgg call the per-row path makes for
        // `select <agg>(v) from itbl where icol = <key>` (execGrouped, one group) —
        // so char min/max, distinct, overflow, stat folds stay byte-identical.
        // O(N+M): one inner scan to bucket, folds sum to O(M) rows, N outer probes.
        var buckets: std.StringHashMapUnmanaged(std.ArrayList(usize)) = .empty;
        for (sh.itbl.rows.items, 0..) |r, ri| {
            kb.clearRetainingCapacity();
            try appendCompositeKey(&kb, arena, r, sh.eq_icols);
            const g = try buckets.getOrPut(arena, kb.items);
            if (!g.found_existing) {
                g.key_ptr.* = try arena.dupe(u8, kb.items);
                g.value_ptr.* = .empty;
            }
            try g.value_ptr.append(arena, ri);
        }
        var bit = buckets.iterator();
        while (bit.next()) |e|
            try map.put(arena, e.key_ptr.*, try computeAgg(arena, diags, sh.itbl, f, sh.agg_star, sh.agg_col, e.value_ptr.items, sh.agg_distinct));
        // a key with no inner rows → the empty-group fold (matches the per-row
        // no-match subquery: one row, count/n 0, other folds SAS-missing).
        return .{ .map = map, .ocols = sh.eq_ocols, .miss = try computeAgg(arena, diags, sh.itbl, f, sh.agg_star, sh.agg_col, &.{}, sh.agg_distinct) };
    }
    for (sh.itbl.rows.items) |r| {
        kb.clearRetainingCapacity();
        try appendCompositeKey(&kb, arena, r, sh.eq_icols);
        const g = try map.getOrPut(arena, kb.items);
        if (!g.found_existing) {
            g.key_ptr.* = try arena.dupe(u8, kb.items);
            g.value_ptr.* = r[sh.sel_col]; // keep FIRST match
        }
    }
    return .{ .map = map, .ocols = sh.eq_ocols, .miss = Value.missing };
}

/// Replace each `[NOT] EXISTS (subquery)` in a WHERE stream with `1`/`0` for the
/// outer row `ri`: the subquery's references to the outer table (`a.col`) are
/// bound to that row's values (correlation), then it is run and EXISTS is true
/// when it returns any row. ponytail: correlation matches `<outer-table>.col`
/// (the common form); table aliases and join-side correlation are follow-ups.
fn substituteExists(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, toks: []const Token, ds: *Dataset, ri: usize, outer_table: []const u8, outer_alias: ?[]const u8) diag.Error![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        var k = i;
        var negate = false;
        if (tkKw(toks[k], "not") and atKw(toks, k + 1, "exists")) {
            negate = true;
            k += 1;
        }
        if (tkKw(toks[k], "exists") and atTag(toks, k + 1, .lparen)) {
            var depth: usize = 1;
            var j = k + 2;
            while (j < toks.len) : (j += 1) {
                if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            const corr = try correlateSubq(arena, toks[k + 2 .. j], ds, ri, outer_table, outer_alias);
            var present = false;
            if (parseQuery(arena, corr)) |sq| {
                if (try execQuery(arena, lib, diags, sq)) |res| present = res.rows.len > 0;
            } else |_| {}
            if (negate) present = !present;
            try out.append(arena, .{ .tag = .number, .text = if (present) "1" else "0" });
            i = j + 1;
            continue;
        }
        try out.append(arena, toks[i]);
        i += 1;
    }
    return out.items;
}

/// Bind a subquery's correlated references to the outer row `ri`, leaving the
/// subquery's own columns alone. The outer qualifier is its alias when it has one
/// (`from T x` → `x.col`), else the table name — an alias shadows the name, so
/// matching only the effective qualifier avoids rebinding the inner table's refs.
fn correlateSubq(arena: std.mem.Allocator, toks: []const Token, ds: *Dataset, ri: usize, outer_table: []const u8, outer_alias: ?[]const u8) diag.Error![]const Token {
    const outer_q = outer_alias orelse outer_table;
    var out: std.ArrayList(Token) = .empty;
    for (toks) |tk| {
        // the lexer coalesces `table.col` into one `.name` token, so a correlated
        // `<outer>.col` is a single token with a dot inside.
        if (tk.tag == .name) {
            if (std.mem.indexOfScalar(u8, tk.text, '.')) |dot| {
                if (eqi(tk.text[0..dot], outer_q)) {
                    if (resolveCol(ds, tk.text) orelse resolveCol(ds, tk.text[dot + 1 ..])) |idx| {
                        try out.append(arena, try valueToken(arena, ds.row(ri)[idx]));
                        continue;
                    }
                }
            }
        }
        try out.append(arena, tk);
    }
    return out.items;
}

fn valueToken(arena: std.mem.Allocator, v: Value) !Token {
    return switch (v) {
        .num => |x| if (std.math.isNan(x)) .{ .tag = .dot } else .{
            .tag = .number,
            .text = if (x == @trunc(x) and @abs(x) < 1e15)
                try std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))})
            else
                try std.fmt.allocPrint(arena, "{d}", .{x}),
        },
        .str => |s| .{ .tag = .string, .text = s },
    };
}

/// `select *` or a plain column list, one output row per surviving input row.
/// A `dictionary.*` (SQL) / `sashelp.v*` (view alias) introspection table.
const DictKind = enum { columns, tables, macros };

/// Classify a FROM name as a dictionary/sashelp introspection view, else null.
/// `dictionary.X` and `sashelp.vX` name the same view (ISS-dictviews).
fn dictKind(name: []const u8) ?DictKind {
    if (eqi(name, "dictionary.columns") or eqi(name, "sashelp.vcolumn")) return .columns;
    if (eqi(name, "dictionary.tables") or eqi(name, "sashelp.vtable")) return .tables;
    if (eqi(name, "dictionary.macros") or eqi(name, "sashelp.vmacro")) return .macros;
    return null;
}

/// True for a `dictionary.*` / `sashelp.v*` name that is NOT one of the
/// implemented introspection views — so the FROM error names the unsupported
/// dictionary table instead of a misleading "table not found" (GAP-sqladvanced).
fn isUnsupportedDict(name: []const u8) bool {
    if (dictKind(name) != null) return false;
    if (name.len > "dictionary.".len and eqi(name[0.."dictionary.".len], "dictionary.")) return true;
    if (name.len > "sashelp.v".len and eqi(name[0.."sashelp.v".len], "sashelp.v")) return true;
    return false;
}

fn unsupportedDict(arena: std.mem.Allocator, name: []const u8) void {
    unsupported(std.fmt.allocPrint(arena, "PROC SQL: dictionary table {s} is not supported yet (only dictionary.columns / dictionary.tables / sashelp.vcolumn / sashelp.vtable are)", .{name}) catch "PROC SQL: dictionary table not supported yet");
}

/// Synthesize a dictionary view fresh from live library state (ISS-dictviews).
/// COLUMNS/TABLES read the in-memory members; MACROS is FAIL LOUD — PROC SQL only
/// sees `Library.macro_vars` (CALL SYMPUT / SQL INTO), not the macro processor's
/// symbol table (%let vars, %macro defs), so a vmacro built here would silently
/// omit most symbols — worse than a visible error for clinical use.
fn synthDictView(arena: std.mem.Allocator, lib: *Library, name: []const u8) !?*Dataset {
    return switch (dictKind(name).?) {
        .columns => try io.buildVcolumn(arena, lib.names.items, lib.sets.items),
        .tables => try io.buildVtable(arena, lib.names.items, lib.sets.items),
        .macros => blk: {
            unsupported("PROC SQL: dictionary.macros / sashelp.vmacro is not implemented (the macro symbol table is not visible to PROC SQL — only CALL SYMPUT / INTO vars are)");
            break :blk null;
        },
    };
}

/// Expand `alias.*` / bare `*` SELECT items into one plain-column item per matching
/// column of the resolved (possibly joined) dataset — ISS-sqlaliasstar. A qualified
/// star `a.*` yields only table/alias `a`'s columns; a bare `*` item yields every
/// column. Non-star items pass through untouched. A qualified star naming an unknown
/// table/alias matches nothing → fail LOUD (never silently drop the columns).
fn expandStars(arena: std.mem.Allocator, ds: *Dataset, q: Query) ![]Item {
    var any = false;
    for (q.items) |it| if (it.is_star) {
        any = true;
        break;
    };
    if (!any) return q.items;
    var out: std.ArrayList(Item) = .empty;
    for (q.items) |it| {
        if (!it.is_star) {
            try out.append(arena, it);
            continue;
        }
        var matched: usize = 0;
        for (ds.columns.items) |c| {
            if (it.star_qual) |ql| if (!starMatches(c.name, ql, q)) continue;
            // `col` carries the (possibly qualified) source name so resolveCol finds
            // it; the output name unqualifies it (see execRowWise's `names`).
            try out.append(arena, .{ .col = c.name });
            matched += 1;
        }
        if (matched == 0) {
            unsupported(try std.fmt.allocPrint(arena, "PROC SQL: SELECT {s}.* — no columns for table/alias '{s}'", .{ it.star_qual orelse "", it.star_qual orelse "" }));
        }
    }
    return out.toOwnedSlice(arena);
}

/// True if column `cname` belongs to qualifier `ql`: either it is pre-qualified as
/// `ql.<x>` (the join case — buildJoin qualifies every column by its table/alias),
/// or it is unqualified and `ql` names the query's sole FROM table/alias (single
/// table `t.*`).
fn starMatches(cname: []const u8, ql: []const u8, q: Query) bool {
    if (std.mem.indexOfScalar(u8, cname, '.')) |dot| return eqi(cname[0..dot], ql);
    if (q.alias) |a| if (eqi(a, ql)) return true;
    return eqi(unqualify(q.table), ql);
}

/// `select * … [group by …] having <cond>` — SAS remerge (ISS-sqlremerge #37):
/// the group aggregate is computed per group and joined back onto each DETAIL row,
/// then HAVING filters rows. One output row per surviving input row, NOT one per
/// group (execGrouped collapses groups; that's wrong for `select *`). An empty
/// GROUP BY makes the whole table one group — HAVING-without-GROUP-BY.
fn execStarRemerge(arena: std.mem.Allocator, lib: *Library, ds: *Dataset, diags: *diag.Diagnostics, q: Query, kept: []const usize) !Result {
    // partition kept rows into groups keyed by the evaluated GROUP BY tuple
    const gexprs = try resolveGroupAliases(arena, q);
    var groups: std.ArrayList(std.ArrayList(usize)) = .empty;
    var gidx: GroupIndex = .empty; // group-key tuple → group slot (PERF-sqlgroupscan)
    const rowgrp = try arena.alloc(usize, ds.rows.items.len); // ds row index → its group
    var gpdv = Pdv.init(arena); // one PDV reused across rows (PERF-sqlgroupmem)
    var gev: eval.Evaluator = .{ .arena = arena, .pdv = &gpdv, .diags = diags, .call_fn = &sqlDispatch };
    for (kept) |ri| {
        const key = try groupKey(arena, &gev, ds, ri, gexprs);
        const gop = try gidx.getOrPutContext(arena, key, .{});
        if (gop.found_existing) {
            try groups.items[gop.value_ptr.*].append(arena, ri);
            rowgrp[ri] = gop.value_ptr.*;
        } else {
            gop.value_ptr.* = groups.items.len;
            var lst: std.ArrayList(usize) = .empty;
            try lst.append(arena, ri);
            try groups.append(arena, lst);
            rowgrp[ri] = groups.items.len - 1;
        }
    }

    var cols: std.ArrayList(OutCol) = .empty;
    for (ds.columns.items) |c| try cols.append(arena, passCol(c.name, c)); // GH#49: pass-through keeps format; + its declared LENGTH (BUG-sqlcolwidthloss)
    var rows: std.ArrayList([]Value) = .empty;
    var srows: std.ArrayList(usize) = .empty; // res row → ds row, for ORDER BY on a non-selected source col
    for (kept) |ri| {
        // HAVING against THIS row's values, aggregates resolved over its group
        // (rep = ri, no extra SELECT bindings): reuse the grouped HAVING evaluator.
        if (q.having) |htoks|
            if (!try evalHaving(arena, lib, diags, ds, htoks, groups.items[rowgrp[ri]].items, ri, &.{}, &.{})) continue;
        const cells = try arena.alloc(Value, ds.columns.items.len);
        for (ds.row(ri), 0..) |v, j| cells[j] = v;
        try rows.append(arena, cells);
        try srows.append(arena, ri);
    }
    var res = Result{ .cols = try cols.toOwnedSlice(arena), .rows = try rows.toOwnedSlice(arena) };
    try orderRows(arena, diags, &res, q.order, null, .{ .ds = ds, .rows = srows.items });
    return res;
}

fn execRowWise(arena: std.mem.Allocator, lib: *Library, ds: *Dataset, diags: *diag.Diagnostics, q: Query, kept_in: []const usize) !Result {
    // BUG-sqlhavingnogroup: a HAVING with no aggregate of its own routes here
    // (has_agg false — an aggregate inside a `(select …)` subquery is the
    // subquery's own, exprHasAgg skips it) and was silently DROPPED, returning
    // every row. Apply it per row via the shared HAVING evaluator, mirroring
    // execStarRemerge: the whole kept set is one group, rep = this row.
    // ponytail: fresh PDV per row inside evalHaving — same cost class as the
    // star+having path; hoist only if a big-table no-agg HAVING profiles hot.
    var kept = kept_in;
    if (q.having) |htoks| {
        var f: std.ArrayList(usize) = .empty;
        for (kept_in) |ri|
            if (try evalHaving(arena, lib, diags, ds, htoks, kept_in, ri, &.{}, &.{})) try f.append(arena, ri);
        kept = f.items;
    }
    var cols: std.ArrayList(OutCol) = .empty;
    if (q.star) {
        for (ds.columns.items) |c| try cols.append(arena, passCol(c.name, c)); // GH#49: pass-through keeps format; + its declared LENGTH (BUG-sqlcolwidthloss)
        var rows: std.ArrayList([]Value) = .empty;
        for (kept) |ri| {
            const cells = try arena.alloc(Value, ds.columns.items.len);
            for (ds.row(ri), 0..) |v, j| cells[j] = v;
            try rows.append(arena, cells);
        }
        var res = Result{ .cols = try cols.toOwnedSlice(arena), .rows = try rows.toOwnedSlice(arena) };
        try orderRows(arena, diags, &res, q.order, null, .{ .ds = ds, .rows = kept });
        return res;
    }
    // output column names (an expression/CASE without an alias gets `_colN`)
    const names = try arena.alloc([]const u8, q.items.len);
    for (q.items, 0..) |it, k|
        names[k] = it.alias orelse if (it.col) |c| unqualify(c) else try std.fmt.allocPrint(arena, "_col{d}", .{k + 1});
    // Each item's DECLARED char width for the per-row PDV bind below, so a
    // `calculated <alias>` reference sees the width its OUTPUT column will carry:
    // a plain column's source width (kept even under an alias, p.37), overridden
    // by an explicit SELECT `length=n` (p.368) exactly as applyItemMods does to the
    // OutCol. A computed/aggregate/CASE/literal item stays null — DOC-SILENT.
    const ilens = try arena.alloc(?usize, q.items.len);
    for (q.items, 0..) |it, k|
        ilens[k] = it.length orelse if (it.col) |cn|
            (if (resolveCol(ds, cn)) |j| ds.columns.items[j].len else null)
        else
            null;

    var rows: std.ArrayList([]Value) = .empty;
    // ONE PDV for the whole scan (BUG-sqlrowwiseoom): a fresh PDV per row
    // re-allocated every column name (dupe + lowercased key + map entry) into
    // the run arena — 22GB on a 740k-row × 36-col joined SELECT. Reuse is
    // value-safe: loadForEvalAlias re-sets every ds column each row and the
    // computed names[k] are re-bound below.
    // PERF-sqlcorrsubqsel: for each SELECT item that is a plain correlated scalar
    // subquery, hash the inner table ONCE (outer.ocol → inner value) and probe per
    // row, instead of re-executing the inner query per outer row (was O(N*M), 4.7GB).
    // null → that item takes the correct per-row path below.
    const smaps = try arena.alloc(?ScalarSel, q.items.len);
    for (q.items, 0..) |it, k| {
        smaps[k] = if (it.case_toks == null and it.expr_toks != null)
            if (try detectScalarSubq(arena, lib, q, ds, it.expr_toks.?)) |sh| try buildScalarSel(arena, diags, sh) else null
        else
            null;
    }
    var pkb: std.ArrayList(u8) = .empty; // reused scalar-probe key buffer

    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    for (kept) |ri| {
        try loadForEvalAlias(&pdv, ds, ds.row(ri), q.alias);
        const cells = try arena.alloc(Value, q.items.len);
        for (q.items, 0..) |it, k| {
            cells[k] = if (smaps[k]) |sm| blk: {
                pkb.clearRetainingCapacity();
                try appendCompositeKey(&pkb, arena, ds.row(ri), sm.ocols);
                if (sm.ineq) |*iqsel| break :blk probeIneqSel(iqsel, pkb.items, toNum(ds.row(ri)[iqsel.ocol]));
                break :blk sm.map.get(pkb.items) orelse sm.miss;
            } else if (it.case_toks) |ct|
                try evalCase(arena, diags, &ev, ct)
            else if (it.expr_toks) |et|
                // a `(select …)` scalar subquery in the select list runs per outer
                // row, correlated to it (BUG-sqlcorrscalar); plain expressions untouched.
                // monotonic() → this row's 1-based number in kept order (GH#24).
                try evalExprItem(arena, diags, &ev, try substituteMonotonic(arena, if (hasSubquery(et))
                    try substituteSubqueries(arena, lib, diags, et, .{ .ds = ds, .ri = ri, .table = q.table, .alias = q.alias })
                else
                    et, rows.items.len + 1))
            else
                ds.row(ri)[resolveCol(ds, it.col.?) orelse return colNotFound(diags, it.col.?)];
            // bind the computed value so a later CALCULATED item can reference it,
            // under the SAME width its output column will carry (BUG-sqlcolwidthloss)
            try bindCol(&pdv, names[k], if (cells[k] == .num) .num else .char, ilens[k], cells[k]);
        }
        try rows.append(arena, cells);
    }

    // column types: a plain column follows its source; a computed column follows
    // its first row's value (a CASE falls back to its first THEN literal).
    for (q.items, 0..) |it, k| {
        // A plain column (even `col as alias`) is pass-through — carry its source
        // format/informat/label (GH#49); a computed/CASE column gets none.
        var src: ?Column = null;
        const ty: VarType = if (it.col) |c| blk: {
            const j = resolveCol(ds, c) orelse break :blk .num;
            src = ds.columns.items[j];
            break :blk ds.columns.items[j].type;
        } else if (rows.items.len > 0)
            (if (rows.items[0][k] == .num) .num else .char)
        else if (it.case_toks) |ct| caseResultType(ct) else .num;
        try cols.append(arena, if (src) |s| passCol(names[k], s) else .{ .name = names[k], .type = ty });
        applyItemMods(&cols, it);
    }

    var res = Result{ .cols = try cols.toOwnedSlice(arena), .rows = try rows.toOwnedSlice(arena) };
    try orderRows(arena, diags, &res, q.order, null, .{ .ds = ds, .rows = kept });
    return res;
}

/// A CASE result is character when the first THEN value is a string literal,
/// else numeric. ponytail: assumes all arms share the first arm's type.
fn caseResultType(toks: []const Token) VarType {
    var i: usize = 0;
    while (i < toks.len) : (i += 1)
        if (tkKw(toks[i], "then") and i + 1 < toks.len) return if (toks[i + 1].tag == .string) .char else .num;
    return .num;
}

/// BUG-lagdifsql: LAG/LAGn/DIF/DIFn carry observation-order queue state — a
/// DATA-step concept. PROC SQL has no observation order, so SAS 9.4 errors
/// (function-cannot-be-located class) instead of evaluating them; opensas used
/// to run the queue anyway and invent data. Guarded here, at the ONE call_fn
/// every SQL evaluator installs, so SELECT/WHERE/HAVING/CASE/ON all fail loud
/// through the same path; the DATA step keeps plain functions.dispatch.
fn sqlDispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (isLagDif(name))
        // NOTE-typoarmgapwording: rc-1 vocabulary — real SAS ERRORS on LAG in
        // SQL (the user's code is wrong), so this is "invalid", never the
        // rc-2 "not supported" a downstream agent routes on (D-009).
        return ev.diags.fail(error.ParseError, 0, "PROC SQL: {s}() is invalid here — LAG/DIF are DATA-step functions (SQL has no observation order)", .{name});
    return functions.dispatch(ev, name, args);
}

/// Mirrors functions.zig's queueDepth: bare `lag`/`dif`, or the name plus a
/// positive integer suffix (`lag2`, `dif12`), case-insensitive. `lag0` and
/// `different` are NOT queue functions and fall through to normal dispatch.
fn isLagDif(name: []const u8) bool {
    for (&[_][]const u8{ "lag", "dif" }) |p| {
        if (name.len >= p.len and eqi(name[0..p.len], p)) {
            const rest = name[p.len..];
            if (rest.len == 0) return true;
            const n = std.fmt.parseInt(usize, rest, 10) catch continue;
            if (n > 0) return true;
        }
    }
    return false;
}

/// Evaluate `case when C then V … [else E] end` for one row: the first WHEN whose
/// condition is true yields its THEN value; otherwise the ELSE value (or missing).
/// Evaluate a CASE against a pre-loaded evaluator (its PDV holds the current row).
/// Simple form `case <expr> when v1 …` compares the subject to each WHEN value;
/// searched form `case when <cond> …` treats each WHEN as a boolean. Arm spans are
/// split at the *top-level* when/then/else (nested CASE skipped) and evaluated
/// case-aware, so a CASE nested in any part works (BUG-casenest).
fn evalCase(arena: std.mem.Allocator, diags: *diag.Diagnostics, ev: *eval.Evaluator, toks: []const Token) diag.Error!Value {
    // BUG-sqltypeconsistency: a proven char/num mix in the result arms is a
    // SAS ERROR, not a silently mistyped column. (Per-row callers that
    // `catch Value.missing` still record the ERROR each row — loud, just
    // repeated; the `try` paths abort the statement on the first row.)
    if (caseArmTypeBits(ev, toks) == 3)
        return diags.fail(error.ParseError, if (toks.len > 0) toks[0].line else 0, "PROC SQL: CASE expression has both character and numeric result values", .{});
    const fw = firstWhen(toks);
    const subject: ?Value = if (fw > 0) try evalSpan(arena, diags, ev, toks[0..fw]) else null;
    var i: usize = fw;
    while (i < toks.len) {
        if (tkKw(toks[i], "when")) {
            i += 1;
            const cs = i;
            i = topKw(toks, i, "then", "");
            // BUG-sqlcasepredicate: a searched WHEN condition is a predicate, so
            // desugar IS NULL/BETWEEN/LIKE/CONTAINS just like the WHERE path does
            // (the THEN/ELSE value spans stay ordinary expressions, untouched).
            const cond = if (subject == null) try desugarPredicates(arena, diags, toks[cs..i]) else toks[cs..i];
            const when_val = try evalSpan(arena, diags, ev, cond);
            if (i < toks.len) i += 1; // past `then`
            const vs = i;
            i = topKw(toks, i, "when", "else");
            const matched = if (subject) |s| cmpVal(s, when_val) == .eq else when_val.truthy();
            if (matched) return evalSpan(arena, diags, ev, toks[vs..i]);
        } else if (tkKw(toks[i], "else")) {
            return evalSpan(arena, diags, ev, toks[i + 1 ..]);
        } else i += 1;
    }
    // BUG-sqlcasechartype: fall-through of a character CASE is a CHAR missing
    // (blank), not a numeric `.` — keeps render, column-type inference, and
    // `where flag=''` consistent; caseResultType is the single type oracle.
    return if (caseResultType(toks) == .char) .{ .str = "" } else Value.missing;
}

/// BUG-sqltypeconsistency: SAS ERRORs when a CASE expression's THEN/ELSE
/// results mix character and numeric ("Type mismatch") — it never builds a
/// first-arm-wins column. OR of the static arm-type bits (1 = proven char,
/// 2 = proven num) over every THEN/ELSE result arm; a simple-CASE subject and
/// the WHEN values are not result arms and are skipped. Compound expressions
/// contribute 0 (unknown) — ponytail: no static expression typer, so a mix is
/// only caught when a literal / PDV-typed column ref / nested CASE proves it;
/// unknown arms keep today's first-arm-wins inference, never a false ERROR.
fn caseArmTypeBits(ev: *eval.Evaluator, toks: []const Token) u2 {
    var seen: u2 = 0;
    var i = firstWhen(toks); // skip a simple-CASE subject — not a result arm
    while (i < toks.len) {
        if (tkKw(toks[i], "when")) {
            i += 1;
            i = topKw(toks, i, "then", "");
            if (i < toks.len) i += 1; // past `then`
            const vs = i;
            i = topKw(toks, i, "when", "else");
            seen |= armTypeBit(ev, toks[vs..i]);
        } else if (tkKw(toks[i], "else")) {
            seen |= armTypeBit(ev, toks[i + 1 ..]);
            break;
        } else i += 1;
    }
    return seen;
}

/// Static type of one result arm: 1 = proven character, 2 = proven numeric,
/// 0 = unknown without evaluating. String literal → char; number literal →
/// num; a bare column ref the PDV knows (incl. its `t.col` qualified form) →
/// its declared type; a pure nested CASE → its arms, recursively.
fn armTypeBit(ev: *eval.Evaluator, toks: []const Token) u2 {
    if (isPureCase(toks)) return caseArmTypeBits(ev, toks[1 .. toks.len - 1]);
    if (toks.len == 1) switch (toks[0].tag) {
        .string => return 1,
        .number => return 2,
        .name => if (ev.pdv.indexOf(toks[0].text)) |vi|
            return if (ev.pdv.vars.items[vi].type == .char) 1 else 2,
        else => {},
    };
    return 0;
}

/// Evaluate one arm span: resolve any nested CASE to a literal, then parse & eval.
fn evalSpan(arena: std.mem.Allocator, diags: *diag.Diagnostics, ev: *eval.Evaluator, toks: []const Token) diag.Error!Value {
    const resolved = try substituteCase(arena, diags, ev, toks);
    var p = pe.Parser.init(arena, try withEof(arena, resolved), diags);
    const expr = p.parseExpr() catch return Value.missing;
    return ev.eval(expr);
}

/// Index of the first top-level `kw1`/`kw2` (skipping nested CASE), or `toks.len`.
fn topKw(toks: []const Token, start: usize, kw1: []const u8, kw2: []const u8) usize {
    var depth: usize = 0;
    var i = start;
    while (i < toks.len) : (i += 1) {
        if (tkKw(toks[i], "case")) depth += 1 else if (tkKw(toks[i], "end")) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and (tkKw(toks[i], kw1) or (kw2.len > 0 and tkKw(toks[i], kw2)))) return i;
    }
    return toks.len;
}

/// Evaluate a CASE against source row `ri` of `ds` (loads a fresh PDV).
/// Evaluate a general SELECT-item expression against `ev`: strip the CALCULATED
/// keyword (its operand is an output column already bound in the PDV), resolve
/// COALESCE and any CASE, then parse & evaluate the ordinary expression.
fn evalExprItem(arena: std.mem.Allocator, diags: *diag.Diagnostics, ev: *eval.Evaluator, toks: []const Token) diag.Error!Value {
    const bare = try removeCalculated(arena, toks); // drop `calculated` markers
    const resolved = try substituteCoalesce(arena, diags, ev, bare);
    return evalSpan(arena, diags, ev, resolved); // evalSpan also resolves nested CASE
}

fn hasCalc(toks: []const Token) bool {
    for (toks) |tk| if (tkKw(tk, "calculated")) return true;
    return false;
}

/// Drop `calculated` keyword tokens — it just marks that its operand is a computed
/// output column (which the caller has bound into the PDV), not a source column.
fn removeCalculated(arena: std.mem.Allocator, toks: []const Token) ![]const Token {
    if (!hasCalc(toks)) return toks;
    var out: std.ArrayList(Token) = .empty;
    for (toks) |tk| if (!tkKw(tk, "calculated")) try out.append(arena, tk);
    return out.items;
}

/// True when `tok` is a WHERE-clause keyword / word operator that lexes as a
/// `.name` — never a column reference (BETWEEN/LIKE/IS NULL/CONTAINS are still
/// un-desugared at validation time).
fn isWhereKw(tok: Token) bool {
    if (tok.tag != .name) return false;
    inline for (.{ "and", "or", "not", "in", "eq", "ne", "lt", "le", "gt", "ge", "is", "null", "missing", "between", "like", "contains", "exists", "case", "when", "then", "else", "end" }) |kw|
        if (std.ascii.eqlIgnoreCase(tok.text, kw)) return true;
    return false;
}

/// True when `name` resolves to a column of the (possibly joined) contributing
/// dataset — mirroring the names loadForEvalAlias binds per row: the stored
/// name, its unqualified form, and `<table>.col` / `<alias>.col` for a
/// single-table column.
fn whereColVisible(ds: *Dataset, alias: ?[]const u8, name: []const u8) bool {
    for (ds.columns.items) |c| {
        if (eqi(name, c.name) or eqi(name, unqualify(c.name))) return true;
        if (std.mem.indexOfScalar(u8, c.name, '.') != null) continue;
        if (std.mem.indexOfScalar(u8, name, '.')) |d| {
            if (!eqi(name[d + 1 ..], c.name)) continue;
            if (eqi(name[0..d], unqualify(ds.name))) return true;
            if (alias) |al| if (eqi(name[0..d], al)) return true;
        }
    }
    return false;
}

/// Validate every column reference in `q.where` against the contributing
/// columns + the CALCULATED-reachable SELECT aliases (BUG-sqlwhereunknown /
/// BUG-sqlwherecalcagg): an unknown name used to bind to missing and silently
/// filter out every row. SAS errors instead — "The following columns were not
/// found in the contributing tables: X", and for a CALCULATED reference to a
/// summary alias "Summary functions are restricted to the SELECT and HAVING
/// clauses". Returns false (having reported the ERROR) on the first offender.
/// HAVING is NOT validated here — aggregates are legal there. ponytail:
/// `(select …)` groups are skipped whole (an inner query validates itself when
/// it runs).
fn validateWhereCols(diags: *diag.Diagnostics, ds: *Dataset, q: Query) diag.Error!bool {
    const wtoks = q.where orelse return true;
    var calc = false; // the previous name token was `calculated`
    var i: usize = 0;
    while (i < wtoks.len) : (i += 1) {
        const tok = wtoks[i];
        // skip a `( select … )` subquery whole — its names are its own query's
        if (tok.tag == .lparen and atKw(wtoks, i + 1, "select")) {
            var depth: usize = 0;
            while (i < wtoks.len) : (i += 1) {
                if (wtoks[i].tag == .lparen) depth += 1 else if (wtoks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            calc = false;
            continue;
        }
        if (tok.tag != .name) continue; // literals, operators, parens
        if (tkKw(tok, "calculated")) {
            calc = true;
            continue;
        }
        const was_calc = calc;
        calc = false;
        if (tkKw(tok, "like")) {
            // GAP-wherelow-tick291 (B): `LIKE pat ESCAPE 'c'` is valid SAS 9.4
            // (SQL Procedure User's Guide printed p.389 syntax, p.390 examples;
            // the DATA-step WHERE has the same clause, Statements ref printed
            // p.364) that we do not implement. Catch it HERE, before the name
            // check below misblames `escape` as an unknown COLUMN the user
            // never wrote (rc 1) — honest gap, rc 2 (D-009/D-009b(i)). The
            // `pat_end > i + 1` guard keeps a pattern that IS the name
            // `escape` on its old "expected an operand" error instead of a
            // false positive. desugarPredicates refuses the same clause on the
            // DATA-step WHERE paths.
            const pat_end = operandEnd(wtoks, i + 1);
            if (pat_end > i + 1 and atKw(wtoks, pat_end, "escape")) {
                diag.markGap();
                try diags.report(.err, tok.line, "WHERE LIKE: the ESCAPE clause is not supported (SQL Procedure User's Guide printed p.389; Statements ref printed p.364)", .{});
                return false;
            }
        }
        if (isWhereKw(tok)) continue;
        // Infix MIN/MAX word operators (Language Reference: Concepts p.225 — valid in WHERE): between
        // two operands the word is the operator, not a column. In OPERAND
        // position (`where min > 3`) fall through so a column named MIN still
        // resolves — and a non-column typo still fails loud (GAP-whereminmax).
        if (isInfixMinMax(wtoks, i)) continue;
        if (atTag(wtoks, i + 1, .lparen)) continue; // a function call, not a column
        if (whereColVisible(ds, q.alias, tok.text)) continue;
        // not a contributing column — a SELECT alias is only visible via CALCULATED
        for (q.items) |it| {
            const al = it.alias orelse continue;
            if (!eqi(al, tok.text)) continue;
            const is_agg = it.agg != null or
                (it.expr_toks != null and exprHasAgg(it.expr_toks.?)) or
                (it.case_toks != null and exprHasAgg(it.case_toks.?));
            if (is_agg and was_calc) {
                try diags.report(.err, tok.line, "PROC SQL: summary functions are restricted to the SELECT and HAVING clauses (CALCULATED {s} is a summary alias)", .{tok.text});
                return false;
            }
            if (was_calc and !is_agg) break; // a legal CALCULATED non-aggregate alias
            // SAS: an alias is not a contributing column — same not-found ERROR
            // whether it is a summary alias used bare or a plain alias without
            // CALCULATED.
            try diags.report(.err, tok.line, "PROC SQL: the following columns were not found in the contributing tables: {s}", .{tok.text});
            return false;
        } else {
            try diags.report(.err, tok.line, "PROC SQL: the following columns were not found in the contributing tables: {s}", .{tok.text});
            return false;
        }
    }
    return true;
}

/// BUG-sqlambigcol: an UNQUALIFIED column present in MORE THAN ONE contributing
/// table of a join is an ambiguous reference — SAS errors; opensas silently took
/// the FIRST table, so a bare join key in a RIGHT/FULL join dropped right-only rows
/// to a MISSING key (a corrupted merge). Precision: a QUALIFIED `a.k` names its
/// table (has a '.'), a single-table column is stored unqualified and unique
/// (indexOf hits), and `select *` expands to qualified names — none reach the >1
/// branch. Fires only on a genuine join where the bare name matches two tables.
fn ambiguousCol(ds: *Dataset, name: []const u8) bool {
    if (std.mem.indexOfScalar(u8, name, '.') != null) return false; // qualified — names its table
    if (ds.indexOf(name) != null) return false; // an exact stored (unqualified) column
    var n: usize = 0;
    for (ds.columns.items) |c| {
        if (eqi(unqualify(c.name), name)) n += 1;
    }
    return n > 1;
}

/// True when `name` is a SELECT output alias — ORDER BY / HAVING / CALCULATED
/// resolve against output columns first, so such a reference is NOT an ambiguous
/// contributing-table column (precision: SELECT alias unaffected by BUG-sqlambigcol).
fn isSelectAlias(q: Query, name: []const u8) bool {
    for (q.items) |it| if (it.alias) |al| if (eqi(al, name)) return true;
    return false;
}

/// First UNQUALIFIED ambiguous name in a token stream, or null. A nested
/// `(select …)` owns its own names (skipped whole); a `name(` is a function call;
/// a SELECT alias resolves to the output column, not a contributing table.
fn firstAmbiguous(ds: *Dataset, q: Query, toks: []const Token) ?[]const u8 {
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag == .lparen and atKw(toks, i + 1, "select")) {
            var depth: usize = 0;
            while (i < toks.len) : (i += 1) {
                if (toks[i].tag == .lparen) depth += 1 else if (toks[i].tag == .rparen) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            continue;
        }
        if (toks[i].tag != .name) continue;
        if (atTag(toks, i + 1, .lparen)) continue; // a function name, not a column
        if (isSelectAlias(q, toks[i].text)) continue; // resolves to the output alias
        if (ambiguousCol(ds, toks[i].text)) return toks[i].text;
    }
    return null;
}

fn ambigErr(diags: *diag.Diagnostics, name: []const u8) diag.Error!bool {
    try diags.report(.err, 0, "PROC SQL: Ambiguous reference, column {s} is in more than one table.", .{unqualify(name)});
    return false;
}

/// Fail loud on any ambiguous unqualified column reference across the query's
/// clauses (BUG-sqlambigcol). Mirrors validateWhereCols: reports the ERROR and
/// returns false so the caller emits no (corrupt) output. `q.items` is already
/// star-expanded, so `select *` items carry qualified names and never match.
fn validateNoAmbiguity(diags: *diag.Diagnostics, ds: *Dataset, q: Query) diag.Error!bool {
    for (q.items) |it| {
        if (it.expr_toks) |et| {
            if (firstAmbiguous(ds, q, et)) |c| return ambigErr(diags, c);
        } else if (it.case_toks) |ct| {
            if (firstAmbiguous(ds, q, ct)) |c| return ambigErr(diags, c);
        } else if (it.agg_arg) |ag| {
            if (firstAmbiguous(ds, q, ag)) |c| return ambigErr(diags, c);
        } else if (it.col) |c| {
            if (!isSelectAlias(q, c) and ambiguousCol(ds, c)) return ambigErr(diags, c);
        }
    }
    if (q.where) |w| if (firstAmbiguous(ds, q, w)) |c| return ambigErr(diags, c);
    for (q.group_exprs) |g| if (firstAmbiguous(ds, q, g)) |c| return ambigErr(diags, c);
    if (q.having) |h| if (firstAmbiguous(ds, q, h)) |c| return ambigErr(diags, c);
    for (q.order) |o| {
        if (o.expr_toks) |et| {
            if (firstAmbiguous(ds, q, et)) |c| return ambigErr(diags, c);
        } else if (o.case_toks) |ct| {
            if (firstAmbiguous(ds, q, ct)) |c| return ambigErr(diags, c);
        } else if (o.idx == null and o.col.len > 0 and !isSelectAlias(q, o.col)) {
            if (ambiguousCol(ds, o.col)) return ambigErr(diags, o.col);
        }
    }
    return true;
}

/// Output-column names (an expression/CASE without an alias gets `_colN`).
fn itemNames(arena: std.mem.Allocator, q: Query) ![]const []const u8 {
    const names = try arena.alloc([]const u8, q.items.len);
    for (q.items, 0..) |it, k|
        names[k] = it.alias orelse if (it.col) |c| unqualify(c) else try std.fmt.allocPrint(arena, "_col{d}", .{k + 1});
    return names;
}

/// Compute each computed SELECT item for source row `ri` and bind it into `ev`'s
/// PDV under its output name, so a WHERE/HAVING CALCULATED reference resolves.
fn bindComputed(arena: std.mem.Allocator, diags: *diag.Diagnostics, ev: *eval.Evaluator, q: Query, names: []const []const u8) diag.Error!void {
    for (q.items, 0..) |it, k| {
        const v = if (it.case_toks) |ct|
            try evalCase(arena, diags, ev, ct)
        else if (it.expr_toks) |et|
            try evalExprItem(arena, diags, ev, et)
        else
            continue; // a plain column is already in the PDV
        // a computed item only: a plain column already carries its width from the
        // row loader (`continue` above), so null here is the DOC-SILENT expression width
        try bindCol(ev.pdv, names[k], if (v == .num) .num else .char, null, v);
    }
}

/// Replace each `coalesce(a, b, …)` with the first non-missing argument's value.
fn substituteCoalesce(arena: std.mem.Allocator, diags: *diag.Diagnostics, ev: *eval.Evaluator, toks: []const Token) diag.Error![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (tkKw(toks[i], "coalesce") and atTag(toks, i + 1, .lparen)) {
            var depth: usize = 1;
            var j = i + 2;
            while (j < toks.len and depth > 0) : (j += 1) {
                if (toks[j].tag == .lparen) depth += 1 else if (toks[j].tag == .rparen) depth -= 1;
                if (depth == 0) break;
            }
            const inner = toks[i + 2 .. j]; // between `(` and `)`
            // BUG-sqltypeconsistency: SAS requires COALESCE arguments to be all
            // character or all numeric — a proven mix (same static oracle as
            // CASE) is an ERROR, not a per-row type surprise. The eval loop
            // below stops at the first non-missing arg, so this static pass
            // must scan ALL top-level comma-separated args first.
            var seen: u2 = 0;
            var s0: usize = 0;
            var d0: usize = 0;
            for (inner, 0..) |tk, k| {
                if (tk.tag == .lparen) d0 += 1 else if (tk.tag == .rparen) {
                    if (d0 > 0) d0 -= 1;
                } else if (d0 == 0 and tk.tag == .comma) {
                    seen |= armTypeBit(ev, inner[s0..k]);
                    s0 = k + 1;
                }
            }
            seen |= armTypeBit(ev, inner[s0..]);
            if (seen == 3)
                return diags.fail(error.ParseError, toks[i].line, "PROC SQL: COALESCE arguments must be all character or all numeric", .{});
            var result: Value = Value.missing;
            var s: usize = 0;
            var d2: usize = 0;
            for (inner, 0..) |tk, k| {
                if (tk.tag == .lparen) d2 += 1 else if (tk.tag == .rparen) {
                    if (d2 > 0) d2 -= 1;
                } else if (d2 == 0 and tk.tag == .comma) {
                    const v = try evalSpan(arena, diags, ev, inner[s..k]);
                    if (!v.isMissing()) {
                        result = v;
                        break;
                    }
                    s = k + 1;
                }
            } else {
                const v = try evalSpan(arena, diags, ev, inner[s..]); // the last argument
                if (!v.isMissing()) result = v;
            }
            try out.append(arena, try valueToken(arena, result));
            i = j + 1; // past `)`
        } else {
            try out.append(arena, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// True if the token stream calls `monotonic(` (case-insensitive) — the cheap gate
/// so the common no-monotonic case allocates nothing.
fn hasMonotonic(toks: []const Token) bool {
    for (toks, 0..) |tk, i| if (tk.tag == .name and eqi(tk.text, "monotonic") and atTag(toks, i + 1, .lparen)) return true;
    return false;
}

/// Replace each `monotonic()` (undocumented SAS row-id function, GH#24) with the
/// 1-based sequential row number `n`. There is no functions.dispatch entry because
/// dispatch has no row context — the counter is supplied by the projection loop, so
/// numbering follows read/processing order over WHERE-surviving rows (before ORDER BY).
fn substituteMonotonic(arena: std.mem.Allocator, toks: []const Token, n: usize) ![]const Token {
    if (!hasMonotonic(toks)) return toks;
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (toks[i].tag == .name and eqi(toks[i].text, "monotonic") and atTag(toks, i + 1, .lparen) and atTag(toks, i + 2, .rparen)) {
            try out.append(arena, try valueToken(arena, .{ .num = @floatFromInt(n) }));
            i += 3;
        } else {
            try out.append(arena, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Index of the first top-level `when` (skipping any nested CASE), or `toks.len`.
fn firstWhen(toks: []const Token) usize {
    var depth: usize = 0;
    for (toks, 0..) |tk, i| {
        if (tkKw(tk, "case")) depth += 1 else if (tkKw(tk, "end")) {
            if (depth > 0) depth -= 1;
        } else if (depth == 0 and tkKw(tk, "when")) return i;
    }
    return toks.len;
}

fn parseExprToks(arena: std.mem.Allocator, diags: *diag.Diagnostics, toks: []const Token) !*const ast.Expr {
    var p = pe.Parser.init(arena, try withEof(arena, toks), diags);
    return p.parseExpr();
}

fn hasCase(toks: []const Token) bool {
    for (toks) |tk| if (tkKw(tk, "case")) return true;
    return false;
}

/// Replace each `case … end` in a token stream with its value for row `ri`, so the
/// remainder is a plain expression the parser/evaluator can run (BUG-casewhere).
fn substituteCase(arena: std.mem.Allocator, diags: *diag.Diagnostics, ev: *eval.Evaluator, toks: []const Token) diag.Error![]const Token {
    var out: std.ArrayList(Token) = .empty;
    var i: usize = 0;
    while (i < toks.len) {
        if (tkKw(toks[i], "case")) {
            var depth: usize = 1;
            var j = i + 1;
            while (j < toks.len) : (j += 1) {
                if (tkKw(toks[j], "case")) depth += 1 else if (tkKw(toks[j], "end")) {
                    depth -= 1;
                    if (depth == 0) break;
                }
            }
            try out.append(arena, try valueToken(arena, try evalCase(arena, diags, ev, toks[i + 1 .. j])));
            i = j + 1; // past `end`
        } else {
            try out.append(arena, toks[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Aggregates and/or GROUP BY: one output row per group.
fn execGrouped(arena: std.mem.Allocator, lib: *Library, ds: *Dataset, diags: *diag.Diagnostics, q: Query, kept: []const usize) !Result {
    // partition kept rows into groups keyed by the *evaluated* GROUP BY tuple (a
    // term may be a column or an expression like year(dt)) — by value, not by
    // adjacency (SQL GROUP BY does not require sorted input) — BUG-groupexpr.
    var groups: std.ArrayList(std.ArrayList(usize)) = .empty;
    var reps: std.ArrayList(usize) = .empty; // a representative row per group
    var repkeys: std.ArrayList([]Value) = .empty; // each group's key tuple (for sorting)
    if (q.group_exprs.len == 0) {
        var all: std.ArrayList(usize) = .empty;
        for (kept) |ri| try all.append(arena, ri);
        try groups.append(arena, all);
        try reps.append(arena, if (kept.len > 0) kept[0] else 0);
        try repkeys.append(arena, &.{});
    } else {
        // BUG-sqlgroupbyalias: resolve GROUP BY of a SELECT-list alias / positional
        // to the item's real expression, so grouping doesn't collapse to one group.
        const gexprs = try resolveGroupAliases(arena, q);
        var gidx: GroupIndex = .empty; // group-key tuple → group slot (PERF-sqlgroupscan)
        var gpdv = Pdv.init(arena); // one PDV reused across rows (PERF-sqlgroupmem)
        var gev: eval.Evaluator = .{ .arena = arena, .pdv = &gpdv, .diags = diags, .call_fn = &sqlDispatch };
        for (kept) |ri| {
            const key = try groupKey(arena, &gev, ds, ri, gexprs);
            const gop = try gidx.getOrPutContext(arena, key, .{});
            if (gop.found_existing) {
                try groups.items[gop.value_ptr.*].append(arena, ri);
            } else {
                gop.value_ptr.* = groups.items.len;
                var lst: std.ArrayList(usize) = .empty;
                try lst.append(arena, ri);
                try groups.append(arena, lst);
                try reps.append(arena, ri);
                try repkeys.append(arena, key); // kept: GroupSort orders groups by key
            }
        }
    }

    // output columns from the select items
    var cols: std.ArrayList(OutCol) = .empty;
    for (q.items, 0..) |it, k| {
        if (it.case_toks) |ct| { // a CASE under GROUP BY — evaluated on the group's rep row
            try cols.append(arena, .{ .name = it.alias orelse try std.fmt.allocPrint(arena, "_col{d}", .{k + 1}), .type = caseResultType(ct) });
        } else if (it.expr_toks != null) { // an expression under GROUP BY
            try cols.append(arena, .{ .name = it.alias orelse try std.fmt.allocPrint(arena, "_col{d}", .{k + 1}), .type = .num });
        } else if (it.agg != null) {
            const nm = it.alias orelse try std.fmt.allocPrint(arena, "_col{d}", .{k + 1});
            try cols.append(arena, .{ .name = nm, .type = aggType(ds, it) });
        } else {
            const j = resolveCol(ds, it.col orelse return error.ParseError) orelse return colNotFound(diags, it.col.?);
            const sc = ds.columns.items[j]; // GH#49: a grouped pass-through column keeps its source format
            try cols.append(arena, passCol(it.alias orelse unqualify(it.col.?), sc));
        }
        applyItemMods(&cols, it);
    }

    // sort groups by their key tuples (SAS returns groups in key order)
    const GroupSort = struct {
        repkeys: [][]Value,
        fn less(ctx: @This(), x: usize, y: usize) bool {
            for (ctx.repkeys[x], ctx.repkeys[y]) |kx, ky| switch (cmpVal(kx, ky)) {
                .lt => return true,
                .gt => return false,
                .eq => {},
            };
            return false;
        }
    };
    var idxs: std.ArrayList(usize) = .empty;
    for (0..groups.items.len) |gi| try idxs.append(arena, gi);
    std.mem.sort(usize, idxs.items, GroupSort{ .repkeys = repkeys.items }, GroupSort.less);

    // An ORDER BY CASE can contain an aggregate (BUG-ordercaseagg) — orderRows sees
    // only the output row and can't resolve it, so when a CASE is present we build
    // the sort keys here, per group, where substituteAggs resolves the aggregate.
    const order_has_case = blk: {
        for (q.order) |o| if (o.case_toks != null) break :blk true;
        break :blk false;
    };
    var order_keys: std.ArrayList([]Value) = .empty;

    var rows: std.ArrayList([]Value) = .empty;
    var srows: std.ArrayList(usize) = .empty; // group row → its rep ds row, for ORDER BY on a non-selected source col
    // one PDV across all groups, not one per group/item (BUG-sqlrowwiseoom)
    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    for (idxs.items) |gi| {
        const grp = groups.items[gi].items;
        // zero-row table, no GROUP BY: the single group is empty and reps.items[gi]
        // is a bogus 0 — there is no rep row to load. The aggregates already yield
        // missing over the empty set, so evaluate the expression/CASE against that
        // (SAS emits one row, missing) — BUG-sqlemptyaggexpr.
        const has_rows = grp.len > 0;
        const cells = try arena.alloc(Value, q.items.len);
        for (q.items, 0..) |it, k| {
            if (it.case_toks) |ct| {
                // a CASE under GROUP BY: resolve any aggregate it uses over the group
                // first, then evaluate against the rep row (its group-key columns are
                // constant across the group) — BUG-casegroupcrash
                if (has_rows) try loadForEval(&pdv, ds, ds.row(reps.items[gi]));
                cells[k] = try evalCase(arena, diags, &ev, try substituteAggs(arena, diags, ds, ct, grp));
            } else if (it.expr_toks) |et| {
                // an expression under GROUP BY: a `(select …)` scalar subquery is
                // resolved first (correlated to the group's rep row, whose key
                // columns are constant across the group) so its own aggregates stay
                // inside it — BUG-sqlscalargroup; then this query's aggregates are
                // resolved over the group, and the rest evaluated against the rep row.
                const et2 = if (hasSubquery(et))
                    try substituteSubqueries(arena, lib, diags, et, if (has_rows) RowCtx{ .ds = ds, .ri = reps.items[gi], .table = q.table, .alias = q.alias } else null)
                else
                    et;
                if (has_rows) try loadForEvalAlias(&pdv, ds, ds.row(reps.items[gi]), q.alias);
                // bind earlier SELECT items so a `calculated <alias>` resolves — incl.
                // an AGGREGATE alias (`sum(x) as s, calculated s/2`), which substituteAggs
                // can't reach because `s` is a name, not an agg call (BUG-sqlcalcgroupagg).
                for (0..k) |j|
                    try bindCol(&pdv, cols.items[j].name, if (cells[j] == .num) .num else .char, cols.items[j].len, cells[j]);
                // monotonic() here numbers output groups in emission order (GH#24) —
                // ponytail: grouped monotonic is output-row order, not per-input-row.
                const bare = try removeCalculated(arena, et2); // `calculated s` → the bound `s`
                cells[k] = try evalExprItem(arena, diags, &ev, try substituteMonotonic(arena, try substituteAggs(arena, diags, ds, bare, grp), rows.items.len + 1));
            } else if (it.agg) |f| {
                cells[k] = if (it.agg_arg) |arg|
                    try computeAggExpr(arena, diags, ds, f, arg, grp, it.agg_distinct)
                else
                    try computeAgg(arena, diags, ds, f, it.agg_star, if (it.col) |c| resolveCol(ds, unqualify(c)) else null, grp, it.agg_distinct);
            } else if (it.col) |c| {
                const j = resolveCol(ds, c) orelse return colNotFound(diags, c); // was an unchecked .? (crash)
                cells[k] = ds.row(reps.items[gi])[j]; // group key: same across the group
            } else cells[k] = Value.missing;
        }
        // HAVING is checked after the row is built so it can see SELECT aliases
        // (e.g. `having tot > 15` where `tot` is `sum(v) as tot`) — BUG-havingalias.
        if (q.having) |htoks|
            if (!try evalHaving(arena, lib, diags, ds, htoks, grp, reps.items[gi], cols.items, cells)) continue;
        try rows.append(arena, cells);
        try srows.append(arena, reps.items[gi]);
        if (order_has_case) { // sort key per surviving row, aggregates resolved over the group
            const key = try arena.alloc(Value, q.order.len);
            for (q.order, 0..) |o, oi| {
                if (o.case_toks != null and has_rows) try loadForEval(&pdv, ds, ds.row(reps.items[gi]));
                key[oi] = if (o.case_toks) |ct|
                    (evalCase(arena, diags, &ev, try substituteAggs(arena, diags, ds, ct, grp)) catch Value.missing)
                else if (o.idx) |ci|
                    (if (ci < cells.len) cells[ci] else Value.missing)
                else nm: {
                    for (cols.items, 0..) |c, ci| if (eqi(c.name, unqualify(o.col))) break :nm cells[ci];
                    // a non-selected source column (e.g. the GROUP BY key) rides the
                    // group's rep row; a genuinely unknown name fails loud in orderRows
                    if (resolveCol(ds, o.col)) |j| break :nm if (has_rows) ds.row(reps.items[gi])[j] else Value.missing;
                    break :nm Value.missing;
                };
            }
            try order_keys.append(arena, key);
        }
    }
    retypeComputed(cols.items, q.items, rows.items); // BUG-sqlremergecharcol
    var res = Result{ .cols = try cols.toOwnedSlice(arena), .rows = try rows.toOwnedSlice(arena) };
    try orderRows(arena, diags, &res, q.order, if (order_has_case) order_keys.items else null, .{ .ds = ds, .rows = srows.items });
    return res;
}

/// Correct each COMPUTED output column's declared type from the value it actually
/// produced — BUG-sqlremergecharcol.
///
/// execGrouped and execRemerge must DECLARE their columns BEFORE the row loop,
/// because that loop binds `calculated <alias>` by name out of `cols`. At
/// declaration time no value exists, so an expression column was typed `.num`
/// outright and a CASE column from its first THEN literal — which put a CHARACTER
/// expression standing next to an aggregate (`select upcase(b) as ub, max(b) as mb`)
/// into a NUMERIC column while its cells stayed `.str`. The descriptor then LIED:
/// PROC SQL's own listing still printed the text (it renders the cell), but the
/// created table said `ub Num 8`, so a DATA step `set` of it read the character
/// value as numeric MISSING — 'AB' silently destroyed, and a nested SELECT
/// re-rendered it BEST12. Only the descriptor was wrong, which is exactly why a
/// green listing hid it.
///
/// Row 0's value is the same evidence execRowWise uses inline for its own computed
/// columns, so this makes the three paths agree rather than adding a fourth rule;
/// with no rows there is nothing to learn from and the declared guess stands
/// (caseResultType, or `.num`). Pass-through columns follow their source column and
/// aggregates follow `aggType` — neither is touched.
fn retypeComputed(cols: []OutCol, items: []const Item, rows: []const []Value) void {
    if (rows.len == 0) return;
    for (items, 0..) |it, k| {
        if (it.expr_toks == null and it.case_toks == null) continue;
        if (k < rows[0].len) cols[k].type = if (rows[0][k] == .num) .num else .char;
    }
}

/// SAS "remerge": a no-GROUP-BY select mixing aggregates with detail columns
/// computes each aggregate over the whole table, then broadcasts it back across
/// every input row — the result keeps one row per input row rather than the
/// single collapsed group row execGrouped would emit (BUG-sqlremergedetail).
/// The whole kept set is one group; every item is then evaluated per detail row.
fn execRemerge(arena: std.mem.Allocator, lib: *Library, ds: *Dataset, diags: *diag.Diagnostics, q: Query, kept: []const usize) !Result {
    diags.note(0, "The query requires remerging summary statistics back with the original data.", .{}) catch {};

    // Partition kept rows into groups by the GROUP BY key; each detail row then
    // resolves its aggregates over ITS group. With no GROUP BY the whole kept set
    // is one group (broadcast across every row) — BUG-sqlgroupremerge.
    var groups: std.ArrayList(std.ArrayList(usize)) = .empty;
    var repkeys: std.ArrayList([]Value) = .empty;
    const rowgrp = try arena.alloc(usize, ds.rows.items.len); // ds row index → its group
    if (q.group_exprs.len == 0) {
        var all: std.ArrayList(usize) = .empty;
        for (kept) |ri| {
            try all.append(arena, ri);
            rowgrp[ri] = 0;
        }
        try groups.append(arena, all);
    } else {
        const gexprs = try resolveGroupAliases(arena, q);
        var gidx: GroupIndex = .empty; // group-key tuple → group slot (PERF-sqlgroupscan)
        var gpdv = Pdv.init(arena); // one PDV reused across rows (PERF-sqlgroupmem)
        var gev: eval.Evaluator = .{ .arena = arena, .pdv = &gpdv, .diags = diags, .call_fn = &sqlDispatch };
        for (kept) |ri| {
            const key = try groupKey(arena, &gev, ds, ri, gexprs);
            const gop = try gidx.getOrPutContext(arena, key, .{});
            if (gop.found_existing) {
                try groups.items[gop.value_ptr.*].append(arena, ri);
                rowgrp[ri] = gop.value_ptr.*;
            } else {
                gop.value_ptr.* = groups.items.len;
                var lst: std.ArrayList(usize) = .empty;
                try lst.append(arena, ri);
                try groups.append(arena, lst);
                try repkeys.append(arena, key);
                rowgrp[ri] = groups.items.len - 1;
            }
        }
    }

    // output columns — same shape as execGrouped's
    var cols: std.ArrayList(OutCol) = .empty;
    for (q.items, 0..) |it, k| {
        if (it.case_toks) |ct| {
            try cols.append(arena, .{ .name = it.alias orelse try std.fmt.allocPrint(arena, "_col{d}", .{k + 1}), .type = caseResultType(ct) });
        } else if (it.expr_toks != null) {
            try cols.append(arena, .{ .name = it.alias orelse try std.fmt.allocPrint(arena, "_col{d}", .{k + 1}), .type = .num });
        } else if (it.agg != null) {
            try cols.append(arena, .{ .name = it.alias orelse try std.fmt.allocPrint(arena, "_col{d}", .{k + 1}), .type = aggType(ds, it) });
        } else {
            const j = resolveCol(ds, it.col orelse return error.ParseError) orelse return colNotFound(diags, it.col.?);
            const sc = ds.columns.items[j];
            try cols.append(arena, passCol(it.alias orelse unqualify(it.col.?), sc));
        }
        applyItemMods(&cols, it);
    }

    var rows: std.ArrayList([]Value) = .empty;
    var srows: std.ArrayList(usize) = .empty; // res row → ds row, for ORDER BY on a non-selected source col
    // one PDV across all rows, not one per row/item (BUG-sqlrowwiseoom)
    var pdv = Pdv.init(arena);
    var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
    for (kept) |ri| {
        const grp = groups.items[rowgrp[ri]].items; // aggregates resolve over THIS row's group
        const cells = try arena.alloc(Value, q.items.len);
        for (q.items, 0..) |it, k| {
            if (it.case_toks) |ct| {
                // aggregates resolved over the row's group, then the CASE per row
                try loadForEval(&pdv, ds, ds.row(ri));
                cells[k] = try evalCase(arena, diags, &ev, try substituteAggs(arena, diags, ds, ct, grp));
            } else if (it.expr_toks) |et| {
                const et2 = if (hasSubquery(et))
                    try substituteSubqueries(arena, lib, diags, et, .{ .ds = ds, .ri = ri, .table = q.table, .alias = q.alias })
                else
                    et;
                try loadForEvalAlias(&pdv, ds, ds.row(ri), q.alias);
                // bind earlier SELECT items so `calculated <alias>` (incl. an aggregate
                // alias) resolves in the remerge path too (BUG-sqlcalcgroupagg).
                for (0..k) |j|
                    try bindCol(&pdv, cols.items[j].name, if (cells[j] == .num) .num else .char, cols.items[j].len, cells[j]);
                // aggregate substituted (whole table), then the expr evaluated per row
                const bare = try removeCalculated(arena, et2); // `calculated s` → the bound `s`
                cells[k] = try evalExprItem(arena, diags, &ev, try substituteMonotonic(arena, try substituteAggs(arena, diags, ds, bare, grp), rows.items.len + 1));
            } else if (it.agg) |f| {
                // ponytail: recomputed per row (broadcast value is constant); O(N·agg)
                // is fine for SQL group sizes — hoist if a hot query ever needs it.
                cells[k] = if (it.agg_arg) |arg|
                    try computeAggExpr(arena, diags, ds, f, arg, grp, it.agg_distinct)
                else
                    try computeAgg(arena, diags, ds, f, it.agg_star, if (it.col) |c| resolveCol(ds, unqualify(c)) else null, grp, it.agg_distinct);
            } else if (it.col) |c| {
                cells[k] = ds.row(ri)[resolveCol(ds, c) orelse return colNotFound(diags, c)];
            } else cells[k] = Value.missing;
        }
        if (q.having) |htoks|
            if (!try evalHaving(arena, lib, diags, ds, htoks, grp, ri, cols.items, cells)) continue;
        try rows.append(arena, cells);
        try srows.append(arena, ri);
    }
    retypeComputed(cols.items, q.items, rows.items); // BUG-sqlremergecharcol
    var res = Result{ .cols = try cols.toOwnedSlice(arena), .rows = try rows.toOwnedSlice(arena) };
    try orderRows(arena, diags, &res, q.order, null, .{ .ds = ds, .rows = srows.items });
    return res;
}

/// SAS-missing for aggregation: NaN numeric OR an all-blank/empty char (which
/// `Value.isMissing` reports as present). COUNT and COUNT(DISTINCT) exclude these.
fn aggMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.indexOfNone(u8, s, " ") == null,
    };
}

fn computeAgg(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, f: AggFn, star: bool, col: ?usize, grp: []const usize, distinct: bool) diag.Error!Value {
    if (f == .count or f == .n or f == .nmiss) {
        if (star) return .{ .num = @floatFromInt(if (f == .nmiss) @as(usize, 0) else grp.len) };
        // No resolvable column (e.g. a mis-parsed arg) → 0, never a null deref
        // (BUG-countdistinctcrash — this used to `col.?`-panic on a missing value).
        const ci = col orelse return .{ .num = 0 };
        var n: usize = 0; // non-missing count (distinct applies only to COUNT)
        var seen: DistinctSet = .empty; // COUNT(DISTINCT) membership — O(1)/row (PERF-sqlcountdistinct)
        for (grp) |ri| {
            const v = ds.row(ri)[ci];
            if (aggMissing(v)) continue; // COUNT/N skip missing (incl. blank char)
            if (distinct and f == .count and !(distinctFirst(arena, &seen, v) catch return .{ .num = 0 })) continue;
            n += 1;
        }
        // BUG-sqlnnmiss: N = non-missing count; NMISS = missing count of the group.
        return .{ .num = @floatFromInt(if (f == .nmiss) grp.len - n else n) };
    }
    // SUM/AVG/MIN/MAX need a resolvable column; a null one (mis-parsed or
    // unresolved qualified name) yields SAS missing rather than a null-deref
    // panic (BUG-sqlaggqualcol — was an unchecked `col.?` at the loops below).
    const ci = col orelse return Value.missing;
    // BUG-sqlsumwgtcharzero: a CHARACTER argument to a numeric summary aggregate
    // is an ERROR in SAS, and must be one here — every fold below toNum-drops
    // char cells, so a char column arrives as an EMPTY xs: SUMWGT then reports a
    // computed 0 (since 9bc08694 hoisted it over the n==0 early-out) on a column
    // N() counts as 2, while STD/CSS/… report missing as if there were no data.
    // Doc: the SQL volume defines SUMWGT as "sum of the WEIGHT variable values¹
    // … ¹ In the SQL procedure, each row has a weight of 1" (Table 2.6, printed
    // p.60; pdf 75 at offset +15, footer verified) and the summary-function
    // Component (printed pp.411-413; pdf 426-428) defines the rest as
    // statistical calculations over the column's values — weights and
    // statistics are numbers, a character value contributes none, and no
    // reading of those pages yields 0 or missing for this input, so we fail
    // loud (house rule) rather than invent one. One guard at the funnel every
    // caller routes through, covering SUM/AVG + the whole isStatAgg set;
    // COUNT/N/NMISS returned above (type-agnostic), MIN/MAX excluded (lexical
    // on char, handled below).
    if (f != .min and f != .max and ds.columns.items[ci].type == .char)
        return diags.fail(error.ParseError, 0, "PROC SQL: summary function {s} requires a numeric argument", .{aggName(f)});
    // GAP-sqlstataggs summary statistics: gather the group's non-missing numerics
    // and fold them (VARDEF=DF, matching proc.zig). distinct is ignored, as SAS
    // applies DISTINCT only to COUNT.
    if (isStatAgg(f)) {
        const xs = arena.alloc(f64, grp.len) catch return Value.missing;
        var m: usize = 0;
        for (grp) |ri| {
            const x = toNum(ds.row(ri)[ci]);
            if (std.math.isNan(x)) continue;
            xs[m] = x;
            m += 1;
        }
        return statAgg(f, xs[0..m]);
    }
    // MIN/MAX over a character column: lexical (blank-padded) comparison, not
    // numeric — toNum would coerce every char to NaN and drop the whole column.
    if ((f == .min or f == .max) and ds.columns.items[ci].type == .char) {
        var best: ?Value = null;
        for (grp) |ri| {
            const v = ds.row(ri)[ci];
            if (best) |b| {
                const ord = cmpVal(v, b);
                if ((f == .min and ord == .lt) or (f == .max and ord == .gt)) best = v;
            } else best = v;
        }
        return best orelse Value.missing;
    }

    var cnt: usize = 0;
    var sum: f64 = 0;
    var lo: f64 = std.math.inf(f64);
    var hi: f64 = -std.math.inf(f64);
    // SUM/AVG(DISTINCT) dedup before folding; MIN/MAX are distinct-invariant so
    // the set is only built for sum/avg (BUG-sqldistinctagg).
    var seen: DistinctSet = .empty;
    const dedup = distinct and (f == .sum or f == .avg);
    for (grp) |ri| {
        const v = ds.row(ri)[ci];
        const x = toNum(v);
        if (std.math.isNan(x)) continue;
        if (dedup and !(distinctFirst(arena, &seen, v) catch return Value.missing)) continue;
        cnt += 1;
        sum += x;
        if (x < lo) lo = x;
        if (x > hi) hi = x;
    }
    if (cnt == 0) return Value.missing;
    const r: f64 = switch (f) {
        .sum => sum,
        .avg => sum / @as(f64, @floatFromInt(cnt)),
        .min => lo,
        .max => hi,
        else => unreachable, // count/n/nmiss above; stat aggs in the isStatAgg block
    };
    // Overflow (±inf) collapses to SAS missing, as the DATA-step evaluator does —
    // so an overflowed aggregate never gets stored/printed as a literal "inf".
    return if (std.math.isFinite(r)) .{ .num = r } else Value.missing;
}

/// Row-aligned source context for ORDER BY: `rows[i]` is the contributing-table
/// row that produced `res.rows[i]`, so an ORDER BY name missing from the SELECT
/// list still sorts by its real per-row value (BUG-sqlordernonselected).
const OrderSrc = struct { ds: *Dataset, rows: []const usize };

/// `precomp`, when given, is the sort-key vector per row (aligned with res.rows) —
/// used by the grouped path so a CASE containing an aggregate resolves over its
/// group (BUG-ordercaseagg), which orderRows can't do from the output row alone.
fn orderRows(arena: std.mem.Allocator, diags: *diag.Diagnostics, res: *Result, order: []const Order, precomp: ?[][]Value, src: ?OrderSrc) diag.Error!void {
    if (order.len == 0 or res.rows.len == 0) return;
    const has_expr = blk: {
        for (order) |o| if (o.case_toks != null or o.expr_toks != null) break :blk true;
        break :blk false;
    };
    // Resolve each named ORDER BY key once: the SELECT output column wins; else a
    // contributing-table column — SAS sorts by it (NOTE that it isn't in the SELECT
    // list). Used to fall through to sort-every-row-as-missing, i.e. the stable
    // input order (BUG-sqlordernonselected). A name matching neither fails loud,
    // like the WHERE validation (BUG-sqlwhereunknown).
    const src_col = try arena.alloc(?usize, order.len);
    var noted = false;
    for (order, 0..) |o, oi| {
        src_col[oi] = null;
        if (o.case_toks != null or o.expr_toks != null or o.idx != null) continue;
        for (res.cols) |c| {
            if (eqi(c.name, unqualify(o.col))) break;
        } else {
            if (src) |s| if (resolveCol(s.ds, o.col)) |j| {
                src_col[oi] = j;
                if (!noted) {
                    noted = true;
                    try diags.note(0, "The query as specified involves ordering by an item that doesn't appear in its SELECT clause.", .{});
                }
                continue;
            };
            return diags.fail(error.ParseError, 0, "PROC SQL: the following columns were not found in the contributing tables: {s}", .{unqualify(o.col)});
        }
    }
    // precompute the sort-key vector for each row (a CASE/expression key is evaluated
    // against the output row; idx is positional/aggregate; else the named output column).
    const kv = precomp orelse try arena.alloc([]Value, res.rows.len);
    if (precomp == null) {
        // one PDV for all rows, not one per row (BUG-sqlrowwiseoom)
        var pdv = Pdv.init(arena);
        var ev: eval.Evaluator = .{ .arena = arena, .pdv = &pdv, .diags = diags, .call_fn = &sqlDispatch };
        for (res.rows, 0..) |row, ri| {
            kv[ri] = try arena.alloc(Value, order.len);
            if (has_expr) for (res.cols, row) |c, v| try bindCol(&pdv, c.name, c.type, c.len, v);
            for (order, 0..) |o, oi| {
                kv[ri][oi] = if (o.case_toks) |ct|
                    (evalCase(arena, diags, &ev, ct) catch Value.missing)
                else if (o.expr_toks) |et|
                    (evalExprItem(arena, diags, &ev, et) catch Value.missing)
                else if (o.idx) |ci|
                    (if (ci < row.len) row[ci] else Value.missing)
                else nm: {
                    for (res.cols, 0..) |c, ci| if (eqi(c.name, unqualify(o.col))) break :nm row[ci];
                    if (src_col[oi]) |j| break :nm src.?.ds.row(src.?.rows[ri])[j];
                    break :nm Value.missing; // unreachable — named keys pre-validated above
                };
            }
        }
    }
    // sort a permutation by the key vectors, then reorder the rows to match
    const perm = try arena.alloc(usize, res.rows.len);
    for (perm, 0..) |*p, i| p.* = i;
    // GAP-sqlsortseqlinguistic: the ONE place PROC SQL orders rows, so the
    // collation is decided here and every ORDER BY path inherits it (all eight
    // callers of orderRows route through this sort). PROC SQL never nests
    // (subqueries call execQuery, not run()), which is why g_opts is safe to
    // read directly here — the same reason `report` reads g_opts.number.
    // Precedence per p.261: the statement option WINS when given, else the
    // system option decides. `orelse` IS that sentence.
    const ling = g_opts.sortseq_ling orelse io.global_sortseq_linguistic;
    const Sort = struct {
        kv: []const []Value,
        ord: []const Order,
        ling: bool,
        fn less(ctx: @This(), x: usize, y: usize) bool {
            for (ctx.ord, 0..) |o, oi| switch (proc.cmpColl(ctx.kv[x][oi], ctx.kv[y][oi], ctx.ling)) {
                .lt => return !o.desc,
                .gt => return o.desc,
                .eq => {},
            };
            return false;
        }
    };
    // std.sort.block (STABLE), not std.mem.sort (pdq, UNSTABLE at real-data
    // sizes). This was `std.mem.sort` and survived only because a byte compare
    // ties on nothing but byte-identical strings; CASE-FOLDING MANUFACTURES
    // TIES ("apple" vs "APPLE" now compare equal), so the collation above would
    // otherwise ship nondeterministic row order. proc.zig's sortRows carries
    // the same note from the same bug ("an unstable sort made gen2 AE's
    // value-identical rows land in a different order than golden"). Stable is a
    // VALID SAS outcome — 9.4 defaults to NOEQUALS, i.e. tie order unspecified.
    std.sort.block(usize, perm, Sort{ .kv = kv, .ord = order, .ling = ling }, Sort.less);
    const sorted = try arena.alloc([]Value, res.rows.len);
    for (perm, 0..) |p, i| sorted[i] = res.rows[p];
    @memcpy(res.rows, sorted);
}

/// Aligned column report: numeric columns right-justified, char left-justified,
/// each column as wide as its header or widest value, a 2-blank gutter between.
/// ponytail: content-fit width, not SAS's format-driven width (BEST12. would
/// pad numerics wider); no rule line — add if a fixture pins the exact listing.
/// F7 FEEDBACK: the statement after star expansion, as echo text for the log.
/// ponytail: minimal faithful echo — SAS lays the transform out over indented
/// lines with two-level names and `as <alias>`; one flat `select … from …;`
/// line pair here. Nested subquery expansions overwrite the slot (last wins);
/// CREATE/INSERT … SELECT echoes are captured but never emitted.
fn feedbackEcho(arena: std.mem.Allocator, ds: *Dataset, q: Query) ![]const u8 {
    var buf: std.ArrayList(u8) = .empty;
    try buf.appendSlice(arena, "NOTE: Statement transforms to:\n  select ");
    if (q.star and q.items.len == 0) { // bare `select *` — every resolved column
        for (ds.columns.items, 0..) |c, k| {
            if (k > 0) try buf.appendSlice(arena, ", ");
            try buf.appendSlice(arena, unqualify(c.name));
        }
    } else for (try itemNames(arena, q), 0..) |nm, k| {
        if (k > 0) try buf.appendSlice(arena, ", ");
        try buf.appendSlice(arena, nm);
    }
    try buf.appendSlice(arena, " from ");
    try buf.appendSlice(arena, q.table);
    try buf.appendSlice(arena, ";\n");
    return buf.items;
}

fn report(arena: std.mem.Allocator, out: *std.ArrayList(u8), res: Result) !void {
    var w = try arena.alloc(usize, res.cols.len);
    for (res.cols, 0..) |c, i| w[i] = c.name.len;
    for (res.rows) |row| for (row, 0..) |v, i| {
        w[i] = @max(w[i], (try cellFmt(arena, v, res.cols[i])).len);
    };

    // F6 NUMBER: a right-justified 1-based "Row" column heads the listing.
    const numbered = g_opts.number;
    const row_w = @max("Row".len, std.fmt.count("{d}", .{res.rows.len}));

    var line: std.ArrayList(u8) = .empty;

    line.clearRetainingCapacity();
    if (numbered) try reportCell(arena, &line, "Row", row_w, true, true);
    for (res.cols, 0..) |c, i| try reportCell(arena, &line, c.name, w[i], c.type == .num, i == 0 and !numbered);
    try reportFlush(arena, out, &line);

    for (res.rows, 0..) |row, ri| {
        line.clearRetainingCapacity();
        if (numbered) try reportCell(arena, &line, try std.fmt.allocPrint(arena, "{d}", .{ri + 1}), row_w, true, true);
        for (row, 0..) |v, i| try reportCell(arena, &line, try cellFmt(arena, v, res.cols[i]), w[i], res.cols[i].type == .num, i == 0 and !numbered);
        try reportFlush(arena, out, &line);
    }
}

/// A cell's display text, applying the column's attached SELECT `format=` when one
/// is set (BUG-sqlselectmodifier), else the plain BEST/char text.
fn cellFmt(arena: std.mem.Allocator, v: Value, c: OutCol) ![]const u8 {
    if (c.format) |f| return format.apply(arena, v, f);
    return cellText(arena, v);
}

fn reportCell(arena: std.mem.Allocator, line: *std.ArrayList(u8), text: []const u8, width: usize, right: bool, first: bool) !void {
    if (!first) try line.appendSlice(arena, "  "); // 2-blank gutter
    const pad = width -| text.len;
    if (right) {
        for (0..pad) |_| try line.append(arena, ' ');
        try line.appendSlice(arena, text);
    } else {
        try line.appendSlice(arena, text);
        for (0..pad) |_| try line.append(arena, ' ');
    }
}

fn reportFlush(arena: std.mem.Allocator, out: *std.ArrayList(u8), line: *std.ArrayList(u8)) !void {
    try out.appendSlice(arena, std.mem.trimEnd(u8, line.items, " ")); // no trailing pad
    try out.append(arena, '\n');
}

// ── helpers ──────────────────────────────────────────────────────────────────

/// The GROUP BY key tuple for source row `ri`: each term evaluated to a value.
/// The underlying token span of a SELECT item that carries a computed value —
/// its arithmetic expr, a reconstructed `case … end`, or (for a plain column
/// alias) a single name token. Null for an aggregate item.
fn groupItemToks(arena: std.mem.Allocator, it: Item) ?[]const Token {
    if (it.expr_toks) |e| return e;
    if (it.case_toks) |c| {
        const toks = arena.alloc(Token, c.len + 2) catch return null;
        toks[0] = .{ .tag = .name, .text = "case", .line = 0 };
        @memcpy(toks[1 .. 1 + c.len], c);
        toks[toks.len - 1] = .{ .tag = .name, .text = "end", .line = 0 };
        return toks;
    }
    if (it.col) |col| {
        const one = arena.alloc(Token, 1) catch return null;
        one[0] = .{ .tag = .name, .text = col, .line = 0 };
        return one;
    }
    return null;
}

/// Resolve each GROUP BY term that is a bare SELECT-list alias (optionally
/// `calculated alias`) or a 1-based positional (`group by 1`) to that item's real
/// expression tokens — otherwise the alias is not a dataset column and evaluates to
/// missing for every row, collapsing all rows into one group (BUG-sqlgroupbyalias).
fn resolveGroupAliases(arena: std.mem.Allocator, q: Query) ![]const []const Token {
    const out = try arena.alloc([]const Token, q.group_exprs.len);
    for (q.group_exprs, 0..) |term, gi| {
        out[gi] = term;
        var tm = term;
        if (tm.len >= 1 and tkKw(tm[0], "calculated")) tm = tm[1..];
        if (tm.len == 1 and tm[0].tag == .number) {
            const n = std.fmt.parseInt(usize, tm[0].text, 10) catch continue;
            if (n >= 1 and n <= q.items.len) if (groupItemToks(arena, q.items[n - 1])) |gt| {
                out[gi] = gt;
            };
        } else if (tm.len == 1 and tm[0].tag == .name) {
            for (q.items) |it| if (it.alias) |al| {
                if (eqi(al, tm[0].text)) {
                    if (groupItemToks(arena, it)) |gt| out[gi] = gt;
                    break;
                }
            };
        }
    }
    return out;
}

fn groupKey(arena: std.mem.Allocator, ev: *eval.Evaluator, ds: *Dataset, ri: usize, exprs: []const []const Token) diag.Error![]Value {
    const key = try arena.alloc(Value, exprs.len);
    // ponytail: reuse the caller's PDV/Evaluator (hoisted above the partition loop).
    // A fresh Pdv.init per row copied EVERY column of the row into the run arena and
    // never freed — ~3.9GB dead per-row PDVs at 1.6M rows (PERF-sqlgroupmem). loadForEval
    // re-sets the shared PDV's cells each row; only the key tuple is retained.
    try loadForEval(ev.pdv, ds, ds.row(ri));
    for (exprs, 0..) |e, i| key[i] = try evalExprItem(arena, ev.diags, ev, e);
    return key;
}

/// GROUP BY with no summary function anywhere in the query: SAS treats the GROUP
/// BY as an ORDER BY — all detail rows, ordered by the group keys
/// (BUG-sqlgroupnoagg). Sort `kept` by the evaluated key tuple; the `a < b`
/// tiebreak keeps ties in input order (deterministic fixtures).
fn sortByGroupKeys(arena: std.mem.Allocator, diags: *diag.Diagnostics, ds: *Dataset, q: Query, kept: []const usize) diag.Error![]usize {
    const gexprs = try resolveGroupAliases(arena, q);
    var gpdv = Pdv.init(arena); // one PDV reused across rows (PERF-sqlgroupmem)
    var gev: eval.Evaluator = .{ .arena = arena, .pdv = &gpdv, .diags = diags, .call_fn = &sqlDispatch };
    const keys = try arena.alloc([]Value, kept.len);
    const pos = try arena.alloc(usize, kept.len);
    for (kept, 0..) |ri, i| {
        keys[i] = try groupKey(arena, &gev, ds, ri, gexprs);
        pos[i] = i;
    }
    const Ctx = struct {
        keys: []const []Value,
        fn less(ctx: @This(), a: usize, b: usize) bool {
            for (ctx.keys[a], ctx.keys[b]) |ka, kb| switch (cmpVal(ka, kb)) {
                .lt => return true,
                .gt => return false,
                .eq => {},
            };
            return a < b;
        }
    };
    std.mem.sort(usize, pos, Ctx{ .keys = keys }, Ctx.less);
    const out = try arena.alloc(usize, kept.len);
    for (pos, 0..) |p, i| out[i] = kept[p];
    return out;
}

/// MIN/MAX over a character column yield a string, so the output column stays
/// char (left-justified, not coerced to numeric); every other aggregate is num.
fn aggType(ds: *Dataset, it: Item) VarType {
    if (it.agg != .min and it.agg != .max) return .num;
    const c = it.col orelse return .num;
    const j = ds.indexOf(c) orelse return .num;
    return ds.columns.items[j].type;
}

fn cmpVal(x: Value, y: Value) std.math.Order {
    return proc.cmpColl(x, y, false);
}

/// The collation choice lives in proc.cmpColl (NOTE-collationduplicated — the
/// private `cmpValColl` copy here was deleted; the bodies were verified
/// byte-equivalent first: same blank-pad, same ASCII case-fold, same
/// missingRank NaN handling, same toNum).
///
/// ONLY `orderRows` passes `ling = true`, and that is a doc restriction, not an
/// oversight: SQL Procedure User's Guide printed p.45 (`=== pdf 60 ===`) —
/// "Note: SORTSEQ= affects only the ORDER BY clause. It does not override your
/// operating environment's default comparison operations for the WHERE clause."
/// The surfaces actually at risk are DISTINCT / GROUP BY / UNION, which DO run
/// on `cmpVal`: folding `cmpVal` itself would have been the one-word change and
/// it would collapse "apple" and "APPLE" into one row — a row silently
/// destroyed. (WHERE is safe for a different reason — it compares through
/// eval.zig, never here — so the sql_sortseq_scope fixture's WHERE block is a
/// belt-and-braces check, not the load-bearing one; the DISTINCT and GROUP BY
/// blocks are what a mutation of this function actually reds.)

fn toNum(v: Value) f64 {
    return switch (v) {
        .num => |x| x,
        .str => |s| blk: {
            const tr = std.mem.trim(u8, s, " ");
            break :blk if (tr.len == 0) std.math.nan(f64) else (std.fmt.parseFloat(f64, tr) catch std.math.nan(f64));
        },
    };
}

fn cellText(arena: std.mem.Allocator, v: Value) ![]const u8 {
    return switch (v) {
        .str => |s| std.mem.trimEnd(u8, s, " "),
        .num => |x| if (!std.math.isNan(x) and x == @trunc(x) and @abs(x) < 1e15)
            try std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))})
        // A special missing (.A–.Z, ._) renders as its letter, matching PROC
        // PRINT/PUT (BUG-sqlmissdisplay); overflow ±inf and plain NaN render `.`.
        else if (std.math.isNan(x) and Value.missingChar(x) != '.')
            try std.fmt.allocPrint(arena, "{c}", .{Value.missingChar(x)})
        else if (!std.math.isFinite(x)) "."
        // A fractional value renders with the BEST12. format, so a SQL result
        // column matches what the DATA step would print (BUG-sqlbestfmt).
        else try format.bestNum(arena, x),
    };
}

/// Index of the SELECT item computing `f(col|*)`, so `ORDER BY <agg>` can reuse the
/// already-computed output column (BUG-orderbyagg). Null if no item matches.
fn matchAggItem(items: []const Item, f: AggFn, star: bool, col: []const u8) ?usize {
    for (items, 0..) |it, k| {
        if (it.agg != f or it.agg_star != star) continue;
        if (star or (it.col != null and eqi(it.col.?, col))) return k;
    }
    return null;
}

fn aggOf(text: []const u8) ?AggFn {
    if (eqi(text, "count")) return .count;
    if (eqi(text, "sum")) return .sum;
    if (eqi(text, "avg") or eqi(text, "mean")) return .avg;
    if (eqi(text, "min")) return .min;
    if (eqi(text, "max")) return .max;
    if (eqi(text, "n")) return .n; // BUG-sqlnnmiss: non-missing count
    if (eqi(text, "nmiss")) return .nmiss; // missing count
    if (eqi(text, "freq")) return .n; // FREQ = non-missing count, same as N
    // GAP-sqlstataggs summary statistics (single-arg; VARDEF=DF, matching proc.zig)
    if (eqi(text, "std") or eqi(text, "stddev")) return .std;
    if (eqi(text, "var")) return .variance;
    if (eqi(text, "stderr")) return .stderr;
    if (eqi(text, "cv")) return .cv;
    if (eqi(text, "css")) return .css;
    if (eqi(text, "uss")) return .uss;
    if (eqi(text, "range")) return .range;
    if (eqi(text, "median")) return .median;
    if (eqi(text, "t")) return .t;
    if (eqi(text, "sumwgt")) return .sumwgt;
    return null;
}

/// SAS display name of an aggregate for diagnostics (VAR for .variance, etc.).
fn aggName(f: AggFn) []const u8 {
    return switch (f) {
        .count => "COUNT", .sum => "SUM", .avg => "AVG", .min => "MIN", .max => "MAX",
        .n => "N", .nmiss => "NMISS", .std => "STD", .variance => "VAR", .stderr => "STDERR",
        .cv => "CV", .css => "CSS", .uss => "USS", .range => "RANGE", .median => "MEDIAN",
        .t => "T", .sumwgt => "SUMWGT",
    };
}

/// True for the summary statistic aggregates statAgg computes (everything aggOf
/// added for GAP-sqlstataggs). SUM/AVG/MIN/MAX/COUNT/N/NMISS keep their own paths.
fn isStatAgg(f: AggFn) bool {
    return switch (f) {
        .std, .variance, .stderr, .cv, .css, .uss, .range, .median, .t, .sumwgt => true,
        else => false,
    };
}

/// A SINGLE-argument summary-aggregate CALL at token `i`: an aggregate name
/// directly followed by `(` whose top-level argument list has NO comma. In SAS a
/// MULTI-argument call of the same name (min(a,b), median(x,y)) is the per-row
/// DATA-step function, not the summary aggregate, so it is not detected here
/// (GAP-sqlstataggs) — the caller leaves those tokens for the per-row evaluator.
fn aggAt(toks: []const Token, i: usize) ?AggFn {
    if (i >= toks.len or toks[i].tag != .name or !atTag(toks, i + 1, .lparen)) return null;
    const f = aggOf(toks[i].text) orelse return null;
    var depth: usize = 0;
    var j = i + 1;
    while (j < toks.len) : (j += 1) switch (toks[j].tag) {
        .lparen => depth += 1,
        .rparen => {
            depth -= 1;
            if (depth == 0) break;
        },
        .comma => if (depth == 1) return null, // multi-arg → per-row function
        else => {},
    };
    return f;
}

/// The summary statistic aggregates (STD/VAR/STDERR/CV/CSS/USS/RANGE/MEDIAN/T/
/// SUMWGT) over the non-missing numeric values `xs`. VARDEF=DF (n−1 divisor, css
/// via an explicit deviation pass) exactly as proc.zig computeStats, so PROC SQL
/// and PROC MEANS agree. Missing when undefined (VAR/STD/STDERR/CV/T need n≥2).
/// SUMWGT = n (PROC SQL has no WEIGHT, every obs weighs 1). MEDIAN sorts `xs` in
/// place — the caller's array is scratch.
fn statAgg(f: AggFn, xs: []f64) Value {
    const nan = std.math.nan(f64);
    const n = xs.len;
    // SUMWGT is ONE statistic shared by both surfaces, so it must not disagree
    // between them: Base SAS 9.4 Procedures Guide, Table 2.1 (printed p.70-71)
    // lists `SUMWGT | Sum of weights | CORR, MEANS or SUMMARY, REPORT, SQL,
    // TABULATE, UNIVARIATE` — PROC SQL and PROC UNIVARIATE, one row. proc.zig
    // already prints `Sum Weights 0` next to `N 0`; PROC SQL returned MISSING,
    // because the n==0 early-out below swallowed SUMWGT with the rest
    // (BUG-sqlsumwgtallmiss).
    //
    // It is 0, not missing, and that is settled twice over. Statistical
    // Procedures printed p.410 ("Sum of the Weights"): "the sum of the weights is
    // calculated as Σⁿᵢ₌₁wᵢ … If there is no WEIGHT variable, the SUM OF THE
    // WEIGHTS IS n" — PROC SQL has no WEIGHT clause at all, so Σwᵢ is
    // unconditionally n, and n here is 0. And the Procedures Guide's
    // "Computational Requirements for Statistics" (printed p.72) lists exactly
    // what needs data — "N and NMISS do not require any nonmissing observations",
    // "SUM, MEAN, MAX, MIN, RANGE, USS, and CSS require at least one nonmissing
    // observation", "VAR, STD, STDERR, and CV require at least two observations"
    // — and SUMWGT is in NONE of the three. Its closing rule, "Statistics are
    // reported as missing if they cannot be computed", does not reach a sum over
    // an empty set: that is computable and it is 0. So SUM/USS/CSS/RANGE staying
    // MISSING below is conformant by the same passage, not an inconsistency
    // (proc.zig's twin reasoning, NOTE-univallmiss).
    if (f == .sumwgt) return .{ .num = @floatFromInt(n) };
    if (n == 0) return Value.missing;
    var sum: f64 = 0;
    var uss: f64 = 0;
    var lo = xs[0];
    var hi = xs[0];
    for (xs) |x| {
        sum += x;
        uss += x * x;
        if (x < lo) lo = x;
        if (x > hi) hi = x;
    }
    const nf: f64 = @floatFromInt(n);
    const mean = sum / nf;
    var css: f64 = 0;
    for (xs) |x| {
        const d = x - mean;
        css += d * d;
    }
    const variance = if (n >= 2) css / (nf - 1) else nan;
    const sd = if (n >= 2) @sqrt(variance) else nan;
    const se = if (n >= 2) sd / @sqrt(nf) else nan;
    const r: f64 = switch (f) {
        .std => sd,
        .variance => variance,
        .stderr => se,
        .cv => if (n >= 2 and mean != 0) 100 * sd / mean else nan,
        .css => css,
        .uss => uss,
        .range => hi - lo,
        .sumwgt => nf,
        .t => if (n >= 2 and se != 0) mean / se else nan,
        .median => blk: {
            std.mem.sort(f64, xs, {}, std.sort.asc(f64));
            break :blk if (n % 2 == 1) xs[n / 2] else (xs[n / 2 - 1] + xs[n / 2]) / 2;
        },
        else => unreachable,
    };
    return if (std.math.isFinite(r)) .{ .num = r } else Value.missing;
}

/// SAS SQL statistic aggregates we still do NOT compute (aggOf's set is what we
/// DO — GAP-sqlstataggs implemented std/var/stderr/cv/css/uss/range/median/t/
/// sumwgt/freq). In SAS a SINGLE-argument call of one of these is the summary
/// aggregate; multiple arguments make it the per-row DATA-step function. Our
/// expression path would evaluate the single-arg form per row and remerge —
/// prt(x) of one value is meaningless — silent wrong numbers, so it must fail
/// loud instead. PRT needs the t-distribution CDF; left unimplemented.
const unimpl_stat_aggs = [_][]const u8{"prt"};

/// The name of the first unimplemented single-argument statistic-aggregate call
/// in `toks`, or null. A top-level comma inside the call's parens means multiple
/// arguments → the DATA-step function, which the per-row path handles correctly.
fn statAggCall(toks: []const Token) ?[]const u8 {
    var i: usize = 0;
    while (i < toks.len) : (i += 1) {
        if (toks[i].tag != .name or !atTag(toks, i + 1, .lparen)) continue;
        const nm = toks[i].text;
        const known = for (unimpl_stat_aggs) |s| {
            if (eqi(nm, s)) break true;
        } else false;
        if (!known) continue;
        var depth: usize = 0;
        var commas: usize = 0;
        var j = i + 1;
        while (j < toks.len) : (j += 1) {
            switch (toks[j].tag) {
                .lparen => depth += 1,
                .rparen => {
                    depth -= 1;
                    if (depth == 0) break;
                },
                .comma => {
                    if (depth == 1) commas += 1;
                },
                else => {},
            }
        }
        if (commas == 0) return nm;
        i = j; // multi-arg: a real DATA-step call — skip past it
    }
    return null;
}

/// parser.zig's keyword matcher, reused (QL-D1, as in proc.zig's QL-B): one
/// idiom for token-keyword tests across the tree instead of a per-file dup.
const tkKw = @import("parser.zig").tkKw;

/// True if token `i` exists and is keyword `kw` — the bound stated positively,
/// once, so call sites don't each re-derive `i < toks.len and …` (taste #13b:
/// one forgotten bound among the hand-copies is an OOB token read).
fn atKw(toks: []const Token, i: usize, kw: []const u8) bool {
    return i < toks.len and tkKw(toks[i], kw);
}

/// True if token `i` exists and has tag `tag` (the `.tag ==` form of atKw).
fn atTag(toks: []const Token, i: usize, tag: lex.Tag) bool {
    return i < toks.len and toks[i].tag == tag;
}

fn eqi(x: []const u8, y: []const u8) bool {
    return std.ascii.eqlIgnoreCase(x, y);
}

/// Index of the next `;` at or after `start` (statement terminator).
fn stmtEnd(toks: []const Token, start: usize) usize {
    var i = start;
    while (i < toks.len and toks[i].tag != .semicolon and toks[i].tag != .eof) i += 1;
    return i;
}

fn withEof(arena: std.mem.Allocator, toks: []const Token) ![]Token {
    const out = try arena.alloc(Token, toks.len + 1);
    @memcpy(out[0..toks.len], toks);
    out[toks.len] = .{ .tag = .eof };
    return out;
}

// TEST-quietnoise (as proc.zig): a test asserting a fail-loud path reads the
// CAPTURED message here instead of parsing stderr; the CLI still prints and
// the run exits 2.
var g_test_unsup_buf: [256]u8 = undefined;
pub var g_test_last_unsup: []const u8 = "";

fn unsupported(msg: []const u8) void {
    // BUG-sqlgapexit: this never called markGap, so every unsupported-SQL run
    // exited 0 — a silent D-009 contract break (proc.zig's twin marks the gap).
    diag.markGap();
    if (@import("builtin").is_test) {
        g_test_last_unsup = std.fmt.bufPrint(&g_test_unsup_buf, "{s}", .{msg}) catch "unsupported message too long";
    } else {
        std.debug.print("UNSUPPORTED: {s}\n", .{msg});
    }
}

// ── tests ────────────────────────────────────────────────────────────────────

const t = std.testing;

fn numV(x: f64) Value {
    return .{ .num = x };
}
fn strV(s: []const u8) Value {
    return .{ .str = s };
}

fn runSql(arena: std.mem.Allocator, lib: *Library, diags: *diag.Diagnostics, src: []const u8) !void {
    const toks = try lex.tokenize(arena, src, diags);
    var out: std.ArrayList(u8) = .empty;
    var titles: Titles = .{};
    try run(arena, &out, lib, diags, &titles, toks);
}

test "create table with aggregates, no group (matches sql_basic.sas)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("age", .num);
    for ([_]f64{ 30, 20, 40 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    try runSql(a, &lib, &diags,
        "proc sql; create table s as select count(*) as n, sum(age) as total, avg(age) as m from have; quit;");

    const s = lib.find("s").?;
    try t.expectEqual(@as(usize, 1), s.rowCount());
    try t.expectEqual(@as(f64, 3), s.row(0)[0].num); // count
    try t.expectEqual(@as(f64, 90), s.row(0)[1].num); // sum
    try t.expectEqual(@as(f64, 30), s.row(0)[2].num); // avg
    try t.expectEqualStrings("n", s.columns.items[0].name);
}

test "PROC SQL operator rules: <> is NE, >< and the legacy =< / => are loud (GAP-sqllegacycmp)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 3, 5 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("t", ds);

    // `<>` is NOT EQUAL here (Language Reference: Concepts p.219 Table 11.3), not the DATA-step MAX.
    // Before this rule it parsed as MAX: max(x,3) is non-zero for EVERY row, so
    // the predicate silently kept the whole table (3 rows, not 2).
    var d0 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d0, "proc sql; create table ne1 as select x from t where x <> 3; quit;");
    try t.expect(!d0.hasErrors());
    const ne1 = lib.find("ne1").?;
    try t.expectEqual(@as(usize, 2), ne1.rowCount());
    try t.expectEqual(@as(f64, 1), ne1.row(0)[0].num);
    try t.expectEqual(@as(f64, 5), ne1.row(1)[0].num);
    // …and it agrees with the mnemonic spelling, which never had the bug.
    var d1 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d1, "proc sql; create table ne2 as select x from t where x ne 3; quit;");
    try t.expectEqual(ne1.rowCount(), lib.find("ne2").?.rowCount());

    // The legacy LE/GE spellings are loud ANYWHERE in the procedure — the
    // Language Reference: Concepts p.127 fn.2/3 exclusion names PROC SQL without qualifying it to the
    // WHERE clause, so a SELECT item and a HAVING are refused too.
    for ([_][]const u8{
        "proc sql; select x from t where x =< 3; quit;",
        "proc sql; select x from t where x => 3; quit;",
        "proc sql; select x, (x =< 3) as flag from t; quit;",
        "proc sql; select x from t having x => 3; quit;",
        "proc sql; delete from t where x =< 0; quit;",
    }) |src| {
        var d = diag.Diagnostics.init(a);
        runSql(a, &lib, &d, src) catch {};
        try t.expect(d.hasErrors());
        var named = false;
        for (d.list.items) |m|
            if (m.severity == .err and std.mem.indexOf(u8, m.message, "not supported here") != null) {
                named = true;
            };
        try t.expect(named); // the diagnostic names the operator, D-002
    }

    // `><` (MIN) has no predicate meaning in SQL either — loud, not a silent MIN.
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; select x from t where x >< 3; quit;") catch {};
    try t.expect(d2.hasErrors());

    // Positive control: the modern spellings are untouched, and the table the
    // loud cases ran against is intact (no partial DELETE from the =< case).
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table le1 as select x from t where x <= 3; quit;");
    try t.expect(!d3.hasErrors());
    try t.expectEqual(@as(usize, 2), lib.find("le1").?.rowCount());
    try t.expectEqual(@as(usize, 3), lib.find("t").?.rowCount());
}

test "PROC SQL truncated-comparison operators EQT/NET/GTT/LTT/GET/LET (GAP-sqltruncops)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("name", .char);
    for ([_][]const u8{ "TWOSTORY", "TWO", "TWOFOLD", "THREE", "" }) |v|
        try ds.appendRow(&.{strV(v)});
    try lib.put("t", ds);

    // SQL Procedure User's Guide Table 8.2 group 7 (printed p.403-404) lists
    // the six alphabetic truncated-comparison operators; p.405: "PROC SQL does
    // not support the colon operators (such as =:, >:, and <=:) … Use the
    // alphabetic operators (such as EQT, GTT, and LET)". Each must agree with
    // its DATA-step `=:`-family counterpart ROW FOR ROW — both route through
    // parser_expr's ONE prefix compare, mkTruncCmp.
    const Pair = struct { word: []const u8, colon: []const u8 };
    for ([_]Pair{
        .{ .word = "eqt", .colon = "=:" },
        .{ .word = "net", .colon = "^=:" },
        .{ .word = "gtt", .colon = ">:" },
        .{ .word = "ltt", .colon = "<:" },
        .{ .word = "get", .colon = ">=:" },
        .{ .word = "let", .colon = "<=:" },
    }) |p| {
        const q1 = try std.fmt.allocPrint(a, "proc sql; create table w as select name from t where name {s} 'TWO'; quit;", .{p.word});
        const q2 = try std.fmt.allocPrint(a, "proc sql; create table c as select name from t where name {s} 'TWO'; quit;", .{p.colon});
        var d1 = diag.Diagnostics.init(a);
        try runSql(a, &lib, &d1, q1);
        try t.expect(!d1.hasErrors());
        var d2 = diag.Diagnostics.init(a);
        try runSql(a, &lib, &d2, q2);
        try t.expect(!d2.hasErrors());
        const w = lib.find("w").?;
        const c = lib.find("c").?;
        try t.expectEqual(c.rowCount(), w.rowCount());
        for (0..w.rowCount()) |ri|
            try t.expectEqualStrings(c.row(ri)[0].str, w.row(ri)[0].str);
    }

    // The shorter-operand rule, p.405's own example: 'TWOSTORY' eqt 'TWO' is
    // true; the truncation is internal (neither operand changes).
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table pre as select name from t where name eqt 'TWO'; quit;");
    try t.expectEqual(@as(usize, 3), lib.find("pre").?.rowCount()); // TWOSTORY, TWO, TWOFOLD

    // Zero-length: the shared helper's guard (Language Reference: Concepts p.130) — '' eqt '' and
    // '' =: '' are BOTH false, and agree. The volume is silent for SQL; the
    // agreement is by construction (same helper).
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table z1 as select name from t where name eqt ''; quit;");
    try t.expectEqual(@as(usize, 0), lib.find("z1").?.rowCount());
    var d5 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d5, "proc sql; create table z2 as select name from t where name =: ''; quit;");
    try t.expectEqual(@as(usize, 0), lib.find("z2").?.rowCount());

    // Predicate positions beyond WHERE: HAVING and a CASE arm take them too
    // (Table 8.2 group 7 is the sql-expression operator table).
    var d6 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d6, "proc sql; select name, case when name eqt 'TWO' then 'pfx' else 'other' end as cls from t having name eqt 'TWO'; quit;");
    try t.expect(!d6.hasErrors());

    // Name collision guard: a COLUMN named GET / LET / NET in operand
    // position keeps resolving as a name — only the infix word is an operator.
    const ds2 = try a.create(Dataset);
    ds2.* = Dataset.init(a, "g");
    _ = try ds2.addColumn("get", .num);
    _ = try ds2.addColumn("let", .num);
    _ = try ds2.addColumn("net", .num);
    try ds2.appendRow(&.{ numV(1), numV(2), numV(3) });
    try lib.put("g", ds2);
    var d7 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d7, "proc sql; create table cols as select get, let, net from g where get = 1; quit;");
    try t.expect(!d7.hasErrors());
    const cols = lib.find("cols").?;
    try t.expectEqual(@as(usize, 1), cols.rowCount());
    try t.expectEqual(@as(f64, 2), cols.row(0)[1].num);

    // …and an EQT-family word in pure OPERAND position (no left operand)
    // still fails LOUD as an unknown column, like any other typo (D-002).
    var d8 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d8, "proc sql; select name from t where eqt = 1; quit;") catch {};
    try t.expect(d8.hasErrors());
}

test "alias.* in a join SELECT expands to the aliased table's columns (ISS-sqlaliasstar)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const dsa = try a.create(Dataset);
    dsa.* = Dataset.init(a, "A");
    _ = try dsa.addColumn("USUBJID", .num);
    _ = try dsa.addColumn("V", .char);
    for ([_]f64{ 1, 2, 3 }) |v| try dsa.appendRow(&.{ numV(v), strV("x") });
    try lib.put("A", dsa);
    const dsb = try a.create(Dataset);
    dsb.* = Dataset.init(a, "B");
    _ = try dsb.addColumn("USUBJID", .num);
    _ = try dsb.addColumn("W", .char);
    try dsb.appendRow(&.{ numV(1), strV("y") });
    try lib.put("B", dsb);

    try runSql(a, &lib, &diags,
        "proc sql; create table j as select a.*, b.W from A as a left join B as b on a.USUBJID=b.USUBJID; quit;");
    const j = lib.find("j").?;
    // a.* → USUBJID, V (not a single collapsed _col1); then b.W
    try t.expectEqual(@as(usize, 3), j.columns.items.len);
    try t.expectEqualStrings("USUBJID", j.columns.items[0].name);
    try t.expectEqualStrings("V", j.columns.items[1].name);
    try t.expectEqualStrings("W", j.columns.items[2].name);
    try t.expectEqual(@as(usize, 3), j.rowCount());
    try t.expectEqual(@as(f64, 1), j.row(0)[0].num);
    try t.expectEqualStrings("x", j.row(0)[1].str);
    try t.expectEqualStrings("y", j.row(0)[2].str); // matched b row
}

test "dictionary.columns is populated from live library state (ISS-dictviews)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const w = try a.create(Dataset);
    w.* = Dataset.init(a, "W");
    _ = try w.addColumn("X", .num);
    _ = try w.addColumn("Y", .char);
    _ = try w.addColumn("Z", .char);
    try w.appendRow(&.{ numV(1), strV("a"), strV("b") });
    try lib.put("W", w);

    // the CHARVARS repro: names of W's char columns, in varnum order
    try runSql(a, &lib, &diags,
        "proc sql noprint; select name into :charvars separated by ' ' " ++
        "from dictionary.columns where libname=\"WORK\" and memname=\"W\" and type=\"char\"; quit;");
    try t.expectEqualStrings("Y Z", lib.macroVar("charvars").?);

    // materialize the whole view and check the schema/rows for W
    try runSql(a, &lib, &diags,
        "proc sql; create table c as select libname, memname, name, type, varnum " ++
        "from dictionary.columns where memname=\"W\"; quit;");
    const c = lib.find("c").?;
    try t.expectEqual(@as(usize, 3), c.rowCount());
    try t.expectEqualStrings("WORK", c.row(0)[0].str);
    try t.expectEqualStrings("W", c.row(0)[1].str);
    try t.expectEqualStrings("X", c.row(0)[2].str);
    try t.expectEqualStrings("num", c.row(0)[3].str);
    try t.expectEqual(@as(f64, 1), c.row(0)[4].num);
    try t.expectEqualStrings("char", c.row(1)[3].str); // Y
}

test "dictionary.tables reports member row/var counts (ISS-dictviews)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const w = try a.create(Dataset);
    w.* = Dataset.init(a, "W");
    _ = try w.addColumn("X", .num);
    _ = try w.addColumn("Y", .char);
    try w.appendRow(&.{ numV(1), strV("a") });
    try w.appendRow(&.{ numV(2), strV("b") });
    try lib.put("W", w);

    try runSql(a, &lib, &diags,
        "proc sql; create table tt as select nobs, nvar from dictionary.tables where memname=\"W\"; quit;");
    const tt = lib.find("tt").?;
    try t.expectEqual(@as(usize, 1), tt.rowCount());
    try t.expectEqual(@as(f64, 2), tt.row(0)[0].num); // nobs
    try t.expectEqual(@as(f64, 2), tt.row(0)[1].num); // nvar
}

test "dictionary.macros fails loud — not silently wrong (ISS-dictviews)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    g_test_last_unsup = "";
    try runSql(a, &lib, &diags, "proc sql; create table m as select * from dictionary.macros; quit;");
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "dictionary.macros") != null);
}

test "unimplemented dictionary tables fail loud NAMING the table (GAP-sqladvanced)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    g_test_last_unsup = "";
    try runSql(a, &lib, &diags, "proc sql; select * from dictionary.members; quit;");
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "dictionary.members") != null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "not supported") != null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "not found") == null); // never the misleading wording
    g_test_last_unsup = "";
    try runSql(a, &lib, &diags, "proc sql; select * from sashelp.vview; quit;");
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "sashelp.vview") != null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "not supported") != null);
}

test "CREATE VIEW fails loud with a clear message (GAP-sqladvanced)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    g_test_last_unsup = "";
    try runSql(a, &lib, &diags, "proc sql; create view v as select * from nothing; quit;");
    try t.expectEqualStrings("PROC SQL: CREATE VIEW is not supported yet", g_test_last_unsup);
}

test "ALTER TABLE ADD <constraint> adds no phantom column (BUG-sqlalteraddconstraint)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    try runSql(a, &lib, &diags, "proc sql; create table p (y num); quit;"); // FK parent
    // Every table-level spelling. All five lex as plain `.name`, so each one used
    // to become a column literally named `constraint`/`primary`/`unique`/`check`/
    // `foreign` — silently, at exit 0.
    inline for (.{
        "constraint c1 check (x > 0)",
        "primary key (x)",
        "unique (x)",
        "check (x > 0)",
        "foreign key (x) references p(y)",
        "primary key (x, z)", // the comma is INSIDE the parens: it must not split the item
    }, 0..) |clause, n| {
        try runSql(a, &lib, &diags, std.fmt.comptimePrint(
            "proc sql; create table m{d} (x num, z num); alter table m{d} add {s}; quit;",
            .{ n, n, clause },
        ));
        const ds = lib.find(std.fmt.comptimePrint("m{d}", .{n})).?;
        try t.expectEqual(@as(usize, 2), ds.columns.items.len); // x, z — and nothing else
        try t.expectEqualStrings("x", ds.columns.items[0].name);
        try t.expectEqualStrings("z", ds.columns.items[1].name);
    }
    // the ADD COLUMN path is untouched: a real column still lands
    try runSql(a, &lib, &diags, "proc sql; create table k (x num); alter table k add w char(4); quit;");
    const k = lib.find("k").?;
    try t.expectEqual(@as(usize, 2), k.columns.items.len);
    try t.expectEqualStrings("w", k.columns.items[1].name);
    try t.expectEqual(@as(usize, 4), k.columns.items[1].len);
}

test "ALTER TABLE DROP CONSTRAINT is a gap, and says so (BUG-sqlalteraddconstraint)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    // Dropping a named constraint is valid SAS we cannot do (a Constraint carries
    // no name), so it stays a gap — but it must not report a missing COLUMN, which
    // is what it did when `constraint` fell through into the DROP-COLUMN loop.
    inline for (.{ "constraint c1", "primary key", "foreign key f1" }) |clause| {
        g_test_last_unsup = "";
        try runSql(a, &lib, &diags, std.fmt.comptimePrint(
            "proc sql; create table m (x num); alter table m drop {s}; quit;",
            .{clause},
        ));
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "DROP CONSTRAINT") != null);
        try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "column not found") == null); // never the misleading wording
        try t.expectEqual(@as(usize, 1), lib.find("m").?.columns.items.len); // nothing half-removed
    }
    // …and the arm it sits in front of still reports a genuinely missing column
    g_test_last_unsup = "";
    try runSql(a, &lib, &diags, "proc sql; create table n (x num); alter table n drop nosuchcol; quit;");
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "column not found") != null);
}

test "LAG/DIF fail loud in PROC SQL expressions (BUG-lagdifsql)" {
    // the name gate: bare / positive-n suffix, case-insensitive; near-misses pass
    try t.expect(isLagDif("lag") and isLagDif("LAG") and isLagDif("lag2") and isLagDif("dif") and isLagDif("DIF12"));
    try t.expect(!isLagDif("lag0") and !isLagDif("different") and !isLagDif("lagging") and !isLagDif("xlag"));

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 14 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("t", ds);

    // SELECT, WHERE and HAVING all route through sqlDispatch → hard ERROR …
    try t.expectError(error.ParseError, runSql(a, &lib, &diags, "proc sql; select lag(x) from t; quit;"));
    try t.expectError(error.ParseError, runSql(a, &lib, &diags, "proc sql; select x from t where dif1(x) > 0; quit;"));
    try t.expectError(error.ParseError, runSql(a, &lib, &diags, "proc sql; select x from t group by x having lag2(x) > 0; quit;"));
    try t.expect(diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, try diags.render(), "is invalid here") != null); // rc-1 user-error wording (NOTE-typoarmgapwording)
    // … while a plain expression on the same table still evaluates fine.
    try runSql(a, &lib, &diags, "proc sql; create table ok as select x + 1 as y from t; quit;");
    try t.expectEqual(@as(f64, 11), lib.find("ok").?.row(0)[0].num);
}

test "quantified ANY/ALL subquery comparisons incl. empty-set edges (GAP-sqladvanced)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "a");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("a", ds);
    const bs = try a.create(Dataset);
    bs.* = Dataset.init(a, "b");
    _ = try bs.addColumn("y", .num);
    for ([_]f64{ 15, 25 }) |v| try bs.appendRow(&.{numV(v)});
    try lib.put("b", bs);
    const es = try a.create(Dataset);
    es.* = Dataset.init(a, "empty");
    _ = try es.addColumn("y", .num);
    try lib.put("empty", es);

    // x > ANY {15,25} ⇔ x > 15 → {20, 30}; x >= ALL ⇔ x >= 25 → {30}
    try runSql(a, &lib, &diags,
        "proc sql; create table r1 as select x from a where x > any (select y from b);" ++
        " create table r2 as select x from a where x >= all (select y from b); quit;");
    try t.expectEqual(@as(usize, 2), lib.find("r1").?.rowCount());
    try t.expectEqual(@as(f64, 20), lib.find("r1").?.row(0)[0].num);
    try t.expectEqual(@as(usize, 1), lib.find("r2").?.rowCount());
    try t.expectEqual(@as(f64, 30), lib.find("r2").?.row(0)[0].num);
    // `= ANY` ⇔ IN → {}; `<> ALL` ⇔ NOT IN → all three
    try runSql(a, &lib, &diags,
        "proc sql; create table r3 as select x from a where x = any (select y from b);" ++
        " create table r4 as select x from a where x <> all (select y from b); quit;");
    try t.expectEqual(@as(usize, 0), lib.find("r3").?.rowCount());
    try t.expectEqual(@as(usize, 3), lib.find("r4").?.rowCount());
    // Empty set: ANY→FALSE (0 rows), ALL→TRUE (all rows) — per SQL.
    try runSql(a, &lib, &diags,
        "proc sql; create table r5 as select x from a where x > any (select y from empty);" ++
        " create table r6 as select x from a where x <= all (select y from empty);" ++
        " create table r7 as select x from a where x = any (select y from empty);" ++
        " create table r8 as select x from a where x <> all (select y from empty); quit;");
    try t.expectEqual(@as(usize, 0), lib.find("r5").?.rowCount());
    try t.expectEqual(@as(usize, 3), lib.find("r6").?.rowCount());
    try t.expectEqual(@as(usize, 0), lib.find("r7").?.rowCount());
    try t.expectEqual(@as(usize, 3), lib.find("r8").?.rowCount());
    // word-operator + SOME spellings take the same path
    try runSql(a, &lib, &diags,
        "proc sql; create table r9 as select x from a where x lt some (select y from b); quit;");
    try t.expectEqual(@as(usize, 2), lib.find("r9").?.rowCount()); // x < 25 → {10, 20}
    // multi-column subquery in a quantified comparison fails loud
    try t.expectError(error.ParseError, runSql(a, &lib, &diags,
        "proc sql; create table r10 as select x from a where x > any (select x, y from a, b); quit;"));
}

test "fractional SQL cell renders with BEST12., matching the DATA step (BUG-sqlbestfmt)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("2", try cellText(a, .{ .num = 2 })); // integer stays integer
    try t.expectEqualStrings(".", try cellText(a, Value.missing)); // missing → '.'
    // 7/3 → BEST12. (10 significant digits), not Zig's full-precision {d}.
    try t.expectEqualStrings("2.3333333333", try cellText(a, .{ .num = 7.0 / 3.0 }));
    try t.expectEqualStrings("0.4285714286", try cellText(a, .{ .num = 3.0 / 7.0 }));
}

test "aggregate over a compound expression folds the whole expr, not the first operand (BUG-sqlaggexpr)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("price", .num);
    _ = try ds.addColumn("qty", .num);
    for ([_][2]f64{ .{ 10, 2 }, .{ 5, 4 }, .{ 3, 10 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("have", ds);

    // whole-table (no GROUP BY): the query must collapse to one row and aggregate
    // the products 20,20,30 — not sum(price)=18 or the pre-fix 36.
    try runSql(a, &lib, &diags,
        "proc sql; create table s as select sum(price*qty) as rev, avg(price*qty) as ar, " ++
        "max(price*qty) as mx, count(distinct price*qty) as dc from have; quit;");
    const s = lib.find("s").?;
    try t.expectEqual(@as(usize, 1), s.rowCount());
    try t.expectEqual(@as(f64, 70), s.row(0)[0].num); // 20+20+30
    try t.expectApproxEqAbs(@as(f64, 70.0 / 3.0), s.row(0)[1].num, 1e-9);
    try t.expectEqual(@as(f64, 30), s.row(0)[2].num); // max product
    try t.expectEqual(@as(f64, 2), s.row(0)[3].num); // distinct products {20,30}

    // a plain column aggregate still works (fast path preserved)
    try runSql(a, &lib, &diags, "proc sql; create table s2 as select sum(price) as sp from have; quit;");
    try t.expectEqual(@as(f64, 18), lib.find("s2").?.row(0)[0].num);
}

test "aggregate NESTED in an outer expression still collapses to one row (BUG-sqlaggouter)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("v", .num);
    for ([_]f64{ 2, 4, 6 }) |x| try ds.appendRow(&.{numV(x)});
    try lib.put("d", ds);

    // sum(v)=12: the outer +/-/*// folds ONCE over the aggregated group, one row.
    try runSql(a, &lib, &diags,
        "proc sql; create table r as select sum(v)+10 as sp, sum(v)*2 as sm, " ++
        "max(v)-min(v) as rng, avg(v)/2 as ah, sum(v)/count(*) as mean from d; quit;");
    const r = lib.find("r").?;
    try t.expectEqual(@as(usize, 1), r.rowCount()); // NOT 3 rows (the regression)
    try t.expectEqual(@as(f64, 22), r.row(0)[0].num); // 12+10
    try t.expectEqual(@as(f64, 24), r.row(0)[1].num); // 12*2
    try t.expectEqual(@as(f64, 4), r.row(0)[2].num); // 6-2 (max-min, was 0 per-row)
    try t.expectEqual(@as(f64, 2), r.row(0)[3].num); // avg=4, /2
    try t.expectEqual(@as(f64, 4), r.row(0)[4].num); // 12/3 (mean pattern)
}

test "DML: CREATE TABLE col-defs, INSERT VALUES, UPDATE, DELETE (G-sqldml)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    try runSql(a, &lib, &diags, "proc sql;" ++
        " create table t (id num, name char(10), score num);" ++
        " insert into t values (1, 'Ann', 10) values (2, 'Bob', 20);" ++
        " insert into t (id, name) values (3, 'Cy');" ++
        " update t set score = score + 5 where id = 1;" ++
        " delete from t where name = 'Bob';" ++
        " quit;");

    const tt = lib.find("t").?;
    try t.expectEqual(@as(usize, 3), tt.columns.items.len);
    try t.expectEqual(@as(usize, 2), tt.rowCount()); // Bob deleted
    try t.expectEqual(@as(f64, 1), tt.row(0)[0].num);
    try t.expectEqual(@as(f64, 15), tt.row(0)[2].num); // 10 + 5
    try t.expectEqualStrings("Cy", tt.row(1)[1].str);
    try t.expect(tt.row(1)[2].isMissing()); // score never inserted
}

test "DELETE * — SAS 9.4 leniently ignores the stray '*' and executes (#61 reverses #41/#53)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    g_test_last_unsup = "";
    try runSql(a, &lib, &diags, "proc sql;" ++
        " create table t (id num, name char(10));" ++
        " insert into t values (1, 'Ann') values (2, 'Bob');" ++
        " delete * from t where name = 'Bob';" ++ // '*' ignored, delete executes
        " quit;");

    // not fatal: no unsupported message
    try t.expectEqualStrings("", g_test_last_unsup);
    // and the matching row IS deleted (like plain DELETE FROM): only Ann (id 1) survives
    try t.expectEqual(@as(usize, 1), lib.find("t").?.rowCount());
    try t.expectEqual(@as(f64, 1), lib.find("t").?.row(0)[0].num);
}

test "BUG-sqlcreatedupcol: malformed CREATE TABLE column list fails loud, no panic" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const have = try a.create(Dataset);
    have.* = Dataset.init(a, "have");
    _ = try have.addColumn("x", .num);
    _ = try have.addColumn("y", .num);
    try have.appendRow(&.{ numV(1), numV(2) });
    try lib.put("have", have);

    // qa tick158 repro: stray extra type token + duplicate column, then an
    // INSERT ... SELECT. Used to panic `reached unreachable` in appendRow.
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql;" ++
        " create table u (a num, b num, c num num, c num);" ++
        " insert into u select * from have;" ++
        " quit;") catch {};
    try t.expect(d1.hasErrors()); // loud ERRORs, no crash (captured, not spawned)
    const u = lib.find("u").?;
    try t.expectEqual(@as(usize, 3), u.columns.items.len); // a, b, c — dup/extra items skipped
    try t.expectEqual(@as(usize, 0), u.rowCount()); // ragged INSERT rejected, not panicked

    // duplicate column name alone → ERROR, first definition kept
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; create table d (x num, x char); quit;") catch {};
    try t.expect(d2.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("d").?.columns.items.len);

    // INSERT ... SELECT width mismatch on a WELL-formed table → ERROR, no panic
    var d3 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d3, "proc sql;" ++
        " create table w (p num, q num, r num);" ++
        " insert into w select * from have;" ++ // 2 cols into 3
        " quit;") catch {};
    try t.expect(d3.hasErrors());
    try t.expectEqual(@as(usize, 0), lib.find("w").?.rowCount());

    // well-formed create + insert unchanged: no errors, rows land
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql;" ++
        " create table ok (id num, nm char(8));" ++
        " insert into ok values (1, 'Ann');" ++
        " insert into ok select * from ok;" ++ // 2 into 2 — fine
        " quit;");
    try t.expect(!d4.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqual(@as(usize, 2), ok.rowCount());
    try t.expectEqual(@as(f64, 1), ok.row(0)[0].num);
    try t.expectEqualStrings("Ann", ok.row(0)[1].str);
}

test "BUG-sqlddlmed: INSERT arity fail-loud, CREATE col format/label, ALTER ADD inline constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a); // BUG-sqlconsleak: `run` prunes prior tests' entries — no hand reset here

    // M4: too few VALUES for the table → ERROR, row rejected (not padded)
    var d1 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d1, "proc sql; create table t (x num, y char); insert into t values(1); quit;");
    try t.expect(d1.hasErrors());
    try t.expectEqual(@as(usize, 0), lib.find("t").?.rowCount());
    // M4: name-list count != value count → ERROR; unknown target name → ERROR
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2, "proc sql; insert into t (x, y) values(1); quit;");
    try t.expect(d2.hasErrors());
    var d2b = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2b, "proc sql; insert into t (bogus) values(1); quit;") catch {};
    try t.expect(d2b.hasErrors());
    // correct-arity INSERTs unchanged — no errors, rows land
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; insert into t values(1, 'a'); insert into t (y) values('b'); quit;");
    try t.expect(!d3.hasErrors());
    try t.expectEqual(@as(usize, 2), lib.find("t").?.rowCount());

    // M5: format=/informat=/label= on CREATE attach to the column
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table m (amt num format=dollar8.2 label='Amount', d num format=date9. informat=date9. not null); quit;");
    try t.expect(!d4.hasErrors());
    const m = lib.find("m").?;
    try t.expectEqualStrings("dollar8.2", m.columns.items[0].format.?);
    try t.expectEqualStrings("Amount", m.columns.items[0].label.?);
    try t.expectEqualStrings("date9.", m.columns.items[1].format.?);
    try t.expectEqualStrings("date9.", m.columns.items[1].informat.?);
    // … and a modifier doesn't swallow a following constraint: d is NOT NULL
    var d4b = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4b, "proc sql; insert into m values(1, .); quit;");
    try t.expect(d4b.hasErrors()); // d missing violates NOT NULL
    try t.expectEqual(@as(usize, 0), m.rowCount());

    // M6: ALTER ADD inline constraint registered + enforced on later INSERTs
    var d5 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d5, "proc sql; create table e (a num); alter table e add b num not null; quit;");
    try t.expect(!d5.hasErrors()); // empty table: no existing-row violation
    var d6 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d6, "proc sql; insert into e values(1, .); quit;");
    try t.expect(d6.hasErrors()); // b missing violates the ADD'd NOT NULL
    try t.expectEqual(@as(usize, 0), lib.find("e").?.rowCount());
    var d7 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d7, "proc sql; insert into e values(1, 2); quit;");
    try t.expect(!d7.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("e").?.rowCount());
    // M6: pre-existing rows that violate the new constraint are reported loudly
    var d8 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d8, "proc sql; alter table e add c num not null; quit;"); // 1 row → c back-filled missing
    try t.expect(d8.hasErrors());
    // M6: CREATE-time constraints survive an ALTER ADD (registry merge)
    var d9 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d9, "proc sql; insert into e values(3, ., 4); quit;"); // b (CREATE-era? no — ADD'd) still NOT NULL
    try t.expect(d9.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("e").?.rowCount());
}

test "DML predicates: BETWEEN, LIKE, IS NULL, CONTAINS (G-sqldml)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("v", .num);
    _ = try ds.addColumn("s", .char);
    try ds.appendRow(&.{ numV(5), strV("apple") });
    try ds.appendRow(&.{ numV(15), strV("banana") });
    try ds.appendRow(&.{ numV(25), strV("cherry") });
    try ds.appendRow(&.{ Value.missing, strV("date") });
    try lib.put("have", ds);

    try runSql(a, &lib, &diags, "proc sql;" ++
        " create table b as select v from have where v between 10 and 20;" ++
        " create table l as select s from have where s like 'b%';" ++
        " create table n as select s from have where v is null;" ++
        " create table c as select s from have where s contains 'err';" ++
        " create table x as select v from have where v not between 10 and 20;" ++
        " quit;");

    try t.expectEqual(@as(f64, 15), lib.find("b").?.row(0)[0].num); // BETWEEN
    try t.expectEqualStrings("banana", lib.find("l").?.row(0)[0].str); // LIKE b%
    try t.expectEqualStrings("date", lib.find("n").?.row(0)[0].str); // IS NULL
    try t.expectEqualStrings("cherry", lib.find("c").?.row(0)[0].str); // CONTAINS err
    try t.expectEqual(@as(usize, 3), lib.find("x").?.rowCount()); // NOT BETWEEN → 5,25,.
}

test "GAP-wherelow-tick266: malformed IS fails loud; valid IS spellings still filter" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("v", .num);
    try ds.appendRow(&.{numV(5)});
    try ds.appendRow(&.{Value.missing});
    try lib.put("have", ds);

    // Valid spellings keep working (desugarPredicates is shared by all four
    // WHERE routes, so this covers SQL / where= / WHERE stmt alike).
    var d_ok = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d_ok, "proc sql;" ++
        " create table n1 as select v from have where v is null;" ++
        " create table n2 as select v from have where v is missing;" ++
        " create table n3 as select v from have where v is not null;" ++
        " create table n4 as select v from have where v is not missing;" ++
        " quit;");
    try t.expect(!d_ok.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("n1").?.rowCount());
    try t.expectEqual(@as(usize, 1), lib.find("n2").?.rowCount());
    try t.expectEqual(@as(usize, 1), lib.find("n3").?.rowCount());
    try t.expectEqual(@as(usize, 1), lib.find("n4").?.rowCount());

    // Incomplete `IS` — `v is` / `v is not` were silently `missing(v)` /
    // `not missing(v)` and now carry the named WHERE IS diagnostic (D-002).
    // runSql reports to the captured diags (D-003), so assert on the reporter.
    const silent = [_][]const u8{ "v is", "v is not" };
    for (silent) |pred| {
        var d = diag.Diagnostics.init(a);
        const stmt = try std.fmt.allocPrint(a, "proc sql; create table t as select v from have where {s}; quit;", .{pred});
        runSql(a, &lib, &d, stmt) catch |e| switch (e) {
            error.OutOfMemory => return e,
            else => {}, // a loud WHERE parse/exec error is the WANTED outcome
        };
        try t.expect(d.hasErrors());
        var named = false;
        for (d.list.items) |e| named = named or std.mem.indexOf(u8, e.message, "WHERE IS") != null;
        try t.expect(named); // the diagnostic names the IS construct
    }
    // `v is <name>` was already loud on the SQL route (column validator) —
    // keep it loud (the where=/WHERE-stmt routes report the WHERE IS one).
    for ([_][]const u8{ "v is bananas", "v is not bananas" }) |pred| {
        var d = diag.Diagnostics.init(a);
        const stmt = try std.fmt.allocPrint(a, "proc sql; create table t as select v from have where {s}; quit;", .{pred});
        runSql(a, &lib, &d, stmt) catch |e| switch (e) {
            error.OutOfMemory => return e,
            else => {},
        };
        try t.expect(d.hasErrors());
    }
}

test "GAP-wherelow-tick291: LIKE ESCAPE is a named rc-2 gap on both WHERE routes; plain LIKE still filters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    diag.resetGap();
    defer diag.resetGap();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("name", .char);
    try ds.appendRow(&.{strV("100% sure")});
    try ds.appendRow(&.{strV("100x sure")});
    try lib.put("have", ds);

    // Plain LIKE (no ESCAPE) keeps filtering — the guard must not eat it.
    var d_ok = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d_ok, "proc sql; create table n1 as select name from have where name like '100x%'; quit;");
    try t.expect(!d_ok.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("n1").?.rowCount());
    try t.expect(!diag.gapHit());

    // PROC SQL route (validateWhereCols): `escape` was misblamed as an unknown
    // COLUMN at rc 1; now the named WHERE LIKE gap, marked rc 2 (D-009).
    var d_sql = diag.Diagnostics.init(a);
    runSql(a, &lib, &d_sql, "proc sql; create table bad as select name from have where name like '100!%' escape '!'; quit;") catch |e| switch (e) {
        error.OutOfMemory => return e,
        else => {}, // a loud gap error is the WANTED outcome
    };
    try t.expect(d_sql.hasErrors());
    var named = false;
    for (d_sql.list.items) |e| named = named or (std.mem.indexOf(u8, e.message, "WHERE LIKE") != null and std.mem.indexOf(u8, e.message, "ESCAPE") != null);
    try t.expect(named); // the diagnostic names the ESCAPE clause, not a phantom column
    try t.expect(diag.gapHit()); // gap class → rc 2, not the old rc 1

    // The shared-desugar route (DATA-step where=/WHERE stmt — tick266 covers
    // that sharing): the same refusal fires from desugarPredicates itself.
    diag.resetGap();
    var d_de = diag.Diagnostics.init(a);
    const wtoks = try lex.tokenize(a, "name like '100!%' escape '!'", &d_de);
    try t.expectError(error.ExecError, desugarPredicates(a, &d_de, wtoks));
    var named2 = false;
    for (d_de.list.items) |e| named2 = named2 or std.mem.indexOf(u8, e.message, "WHERE LIKE") != null;
    try t.expect(named2);
    try t.expect(diag.gapHit());
}

test "where + order by desc, row-wise" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 5, 12, 3, 20 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("have", ds);

    try runSql(a, &lib, &diags,
        "proc sql; create table q as select x from have where x > 10 order by x desc; quit;");

    const q = lib.find("q").?;
    try t.expectEqual(@as(usize, 2), q.rowCount());
    try t.expectEqual(@as(f64, 20), q.row(0)[0].num); // desc
    try t.expectEqual(@as(f64, 12), q.row(1)[0].num);
}

test "RIGHT and FULL OUTER JOIN keep unmatched rows (SQL-joinmore)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const dsa = try a.create(Dataset);
    dsa.* = Dataset.init(a, "a");
    _ = try dsa.addColumn("id", .num);
    _ = try dsa.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 20 }, .{ 3, 30 } }) |r| try dsa.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("a", dsa);
    const dsb = try a.create(Dataset);
    dsb.* = Dataset.init(a, "b");
    _ = try dsb.addColumn("id", .num);
    _ = try dsb.addColumn("y", .num);
    for ([_][2]f64{ .{ 2, 200 }, .{ 3, 300 }, .{ 4, 400 } }) |r| try dsb.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("b", dsb);

    // RIGHT: every b row kept; b.id=4 has no a match → x missing
    try runSql(a, &lib, &diags,
        "proc sql; create table jr as select b.id as bid, x from a right join b on a.id=b.id order by bid; quit;");
    const jr = lib.find("jr").?;
    try t.expectEqual(@as(usize, 3), jr.rowCount());
    try t.expectEqual(@as(f64, 4), jr.row(2)[jr.indexOf("bid").?].num);
    try t.expect(jr.row(2)[jr.indexOf("x").?].isMissing());

    // FULL: a.id=1 (no match) and b.id=4 (no match) both kept → 4 rows
    try runSql(a, &lib, &diags,
        "proc sql; create table jf as select a.id as aid, b.id as bid from a full join b on a.id=b.id; quit;");
    try t.expectEqual(@as(usize, 4), lib.find("jf").?.rowCount());
}

test "inner/left join and a scalar subquery in WHERE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const dsa = try a.create(Dataset);
    dsa.* = Dataset.init(a, "a");
    _ = try dsa.addColumn("id", .num);
    _ = try dsa.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 20 }, .{ 3, 30 } }) |r| try dsa.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("a", dsa);
    const dsb = try a.create(Dataset);
    dsb.* = Dataset.init(a, "b");
    _ = try dsb.addColumn("id", .num);
    _ = try dsb.addColumn("y", .num);
    for ([_][2]f64{ .{ 2, 200 }, .{ 3, 300 } }) |r| try dsb.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("b", dsb);

    // inner join: only matching ids (2,3)
    try runSql(a, &lib, &diags,
        "proc sql; create table ji as select a.id, a.x, b.y from a inner join b on a.id=b.id order by a.id; quit;");
    const ji = lib.find("ji").?;
    try t.expectEqual(@as(usize, 2), ji.rowCount());
    try t.expectEqualStrings("y", ji.columns.items[2].name); // output name unqualified
    try t.expectEqual(@as(f64, 2), ji.row(0)[ji.indexOf("id").?].num);
    try t.expectEqual(@as(f64, 200), ji.row(0)[ji.indexOf("y").?].num);

    // left join: id=1 kept with missing y
    try runSql(a, &lib, &diags,
        "proc sql; create table jl as select a.id, b.y from a left join b on a.id=b.id order by a.id; quit;");
    const jl = lib.find("jl").?;
    try t.expectEqual(@as(usize, 3), jl.rowCount());
    try t.expect(jl.row(0)[jl.indexOf("y").?].isMissing()); // id=1 → no match

    // scalar subquery: avg(x) over a is 20 → x > 20 keeps only 30
    try runSql(a, &lib, &diags,
        "proc sql; create table hi as select id from a where x > (select avg(x) from a); quit;");
    const hi = lib.find("hi").?;
    try t.expectEqual(@as(usize, 1), hi.rowCount());
    try t.expectEqual(@as(f64, 3), hi.row(0)[0].num);

    // cross join (comma): 3×2 = 6 rows; unqualified x,y resolve across tables
    try runSql(a, &lib, &diags,
        "proc sql; create table cx as select x, y from a, b; quit;");
    try t.expectEqual(@as(usize, 6), lib.find("cx").?.rowCount());

    // 3-table inner join with unqualified select columns
    const dsc = try a.create(Dataset);
    dsc.* = Dataset.init(a, "c");
    _ = try dsc.addColumn("id", .num);
    _ = try dsc.addColumn("z", .num);
    for ([_][2]f64{ .{ 2, 20 }, .{ 3, 30 } }) |r| try dsc.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("c", dsc);
    try runSql(a, &lib, &diags,
        "proc sql; create table j3 as select a.id, x, y, z from a inner join b on a.id=b.id inner join c on a.id=c.id order by a.id; quit;");
    const j3 = lib.find("j3").?;
    try t.expectEqual(@as(usize, 2), j3.rowCount()); // ids 2,3 in all three
    try t.expectEqual(@as(f64, 2), j3.row(0)[j3.indexOf("id").?].num);
    try t.expectEqual(@as(f64, 200), j3.row(0)[j3.indexOf("y").?].num);
    try t.expectEqual(@as(f64, 20), j3.row(0)[j3.indexOf("z").?].num);
}

test "BUG-sqlscalarsubqcard / sqlinsubqcols: scalar subq >1 row and IN multi-col fail loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "a");
    _ = try ds.addColumn("id", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 20 }, .{ 3, 30 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("a", ds);

    // SELECT-list scalar subquery returning 3 rows → ERROR, not first-row.
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; select id, (select x from a) as sub from a; quit;") catch {};
    try t.expect(d1.hasErrors());

    // WHERE = scalar subquery returning 3 rows → ERROR.
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; select * from a where x = (select x from a); quit;") catch {};
    try t.expect(d2.hasErrors());

    // IN subquery selecting 2 columns → ERROR (only one column allowed).
    var d3 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d3, "proc sql; select id from a where id in (select id, x from a); quit;") catch {};
    try t.expect(d3.hasErrors());

    // Positive: a genuine single-row scalar subquery still works (no error).
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table ok as select * from a where x = (select max(x) from a); quit;");
    try t.expect(!d4.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqual(@as(usize, 1), ok.rowCount()); // only id=3 (x=30=max)
    try t.expectEqual(@as(f64, 3), ok.row(0)[ok.indexOf("id").?].num);
}

test "BUG-sqlorderexpr: ORDER BY a bare expression sorts on the computed value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "s");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ -5, 3, -1 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("s", ds);

    // order by abs(x): keys 5,3,1 → ascending → x = -1, 3, -5
    try runSql(a, &lib, &diags, "proc sql; create table o as select x from s order by abs(x); quit;");
    const o = lib.find("o").?;
    try t.expectEqual(@as(f64, -1), o.row(0)[0].num);
    try t.expectEqual(@as(f64, 3), o.row(1)[0].num);
    try t.expectEqual(@as(f64, -5), o.row(2)[0].num);

    // order by 10-x descending-of-x form, plus a DESC on the expression
    try runSql(a, &lib, &diags, "proc sql; create table o2 as select x from s order by abs(x) desc; quit;");
    const o2 = lib.find("o2").?;
    try t.expectEqual(@as(f64, -5), o2.row(0)[0].num); // abs 5 first
    try t.expectEqual(@as(f64, -1), o2.row(2)[0].num); // abs 1 last
}

test "BUG-sqlordernonselected: ORDER BY a column not in the SELECT list still sorts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 30, 1 }, .{ 10, 3 }, .{ 20, 2 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("d", ds);

    // y drives the sort though only x is selected (input x order 30,10,20 → by y: 30,20,10)
    var d1 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d1, "proc sql; create table o as select x from d order by y; quit;");
    try t.expect(!d1.hasErrors());
    const o = lib.find("o").?;
    try t.expectEqual(@as(f64, 30), o.row(0)[0].num);
    try t.expectEqual(@as(f64, 20), o.row(1)[0].num);
    try t.expectEqual(@as(f64, 10), o.row(2)[0].num);

    // DESC on the non-selected column
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2, "proc sql; create table od as select x from d order by y desc; quit;");
    const od = lib.find("od").?;
    try t.expectEqual(@as(f64, 10), od.row(0)[0].num);
    try t.expectEqual(@as(f64, 30), od.row(2)[0].num);

    // control: ORDER BY a selected column unchanged
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table ox as select x from d order by x; quit;");
    const ox = lib.find("ox").?;
    try t.expectEqual(@as(f64, 10), ox.row(0)[0].num);
    try t.expectEqual(@as(f64, 30), ox.row(2)[0].num);

    // a genuinely unknown ORDER BY name fails loud, never sorts-as-missing
    var d4 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d4, "proc sql; create table bad as select x from d order by nosuch; quit;") catch {};
    try t.expect(d4.hasErrors());
    var named = false;
    for (d4.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "contributing tables") != null and std.mem.indexOf(u8, m.message, "nosuch") != null) {
            named = true;
        };
    try t.expect(named);
}

test "grouped IN-subquery: WHERE x in (select … group by … having …) (BUG-sqlsubqnest)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("g", .char);
    _ = try d.addColumn("v", .num);
    try d.appendRow(&.{ strV("A"), numV(1) });
    try d.appendRow(&.{ strV("A"), numV(2) });
    try d.appendRow(&.{ strV("A"), numV(3) });
    try d.appendRow(&.{ strV("B"), numV(1) });
    try d.appendRow(&.{ strV("B"), numV(2) });
    try d.appendRow(&.{ strV("C"), numV(1) });
    try lib.put("d", d);

    // groups with count>=2 are A(3) and B(2); the outer WHERE keeps every row in
    // those groups — 5 rows. (The subquery's GROUP BY/HAVING must stay inside the
    // subquery, not be grabbed as the outer query's group-by.)
    try runSql(a, &lib, &diags,
        "proc sql; create table r as select g, v from d where g in (select g from d group by g having count(*) >= 2) order by g, v; quit;");
    const r = lib.find("r").?;
    try t.expectEqual(@as(usize, 5), r.rowCount());
    const gi = r.indexOf("g").?;
    for (0..r.rowCount()) |ri| {
        const g = std.mem.trimEnd(u8, r.row(ri)[gi].str, " ");
        try t.expect(std.mem.eql(u8, g, "A") or std.mem.eql(u8, g, "B")); // never C
    }
}

test "correlated [NOT] EXISTS subquery in WHERE (BUG-sqlexists)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const dsa = try a.create(Dataset);
    dsa.* = Dataset.init(a, "a");
    _ = try dsa.addColumn("id", .num);
    _ = try dsa.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 20 }, .{ 3, 30 } }) |r| try dsa.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("a", dsa);
    const dsb = try a.create(Dataset);
    dsb.* = Dataset.init(a, "b");
    _ = try dsb.addColumn("id", .num);
    for ([_]f64{ 2, 3 }) |v| try dsb.appendRow(&.{numV(v)});
    try lib.put("b", dsb);

    // EXISTS: keep the a rows whose id has a match in b → 2, 3 (correlated on a.id)
    try runSql(a, &lib, &diags,
        "proc sql; create table e as select id, x from a where exists (select 1 from b where b.id = a.id) order by id; quit;");
    const e = lib.find("e").?;
    try t.expectEqual(@as(usize, 2), e.rowCount());
    try t.expectEqual(@as(f64, 2), e.row(0)[e.indexOf("id").?].num);
    try t.expectEqual(@as(f64, 3), e.row(1)[e.indexOf("id").?].num);

    // NOT EXISTS: keep the a rows with no match → id 1
    try runSql(a, &lib, &diags,
        "proc sql; create table ne as select id from a where not exists (select 1 from b where b.id = a.id) order by id; quit;");
    const ne = lib.find("ne").?;
    try t.expectEqual(@as(usize, 1), ne.rowCount());
    try t.expectEqual(@as(f64, 1), ne.row(0)[0].num);
}

test "correlated scalar-aggregate subquery, WHERE and select list (BUG-sqlcorrscalar)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const emp = try a.create(Dataset);
    emp.* = Dataset.init(a, "emp");
    _ = try emp.addColumn("dept", .num);
    _ = try emp.addColumn("sal", .num);
    // dept 10 avg = 150, dept 20 avg = 600 (global avg = 375 — the old bug's value)
    for ([_][2]f64{ .{ 10, 100 }, .{ 10, 200 }, .{ 20, 300 }, .{ 20, 900 } }) |r|
        try emp.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("emp", emp);

    // WHERE: keep rows above their OWN dept's average, not the global one → (10,200),(20,900)
    try runSql(a, &lib, &diags,
        "proc sql; create table hi as select dept, sal from emp " ++
        "where sal > (select avg(sal) from emp where dept = emp.dept) order by sal; quit;");
    const hi = lib.find("hi").?;
    try t.expectEqual(@as(usize, 2), hi.rowCount());
    try t.expectEqual(@as(f64, 200), hi.row(0)[hi.indexOf("sal").?].num);
    try t.expectEqual(@as(f64, 900), hi.row(1)[hi.indexOf("sal").?].num);

    // select-list form: a correlated scalar subquery as a computed column, per row
    try runSql(a, &lib, &diags,
        "proc sql; create table da as select dept, sal, " ++
        "(select avg(sal) from emp where dept = emp.dept) as davg from emp order by sal; quit;");
    const da = lib.find("da").?;
    try t.expectEqual(@as(usize, 4), da.rowCount());
    const dv = da.indexOf("davg").?;
    try t.expectEqual(@as(f64, 150), da.row(0)[dv].num); // sal 100 → dept 10 avg 150
    try t.expectEqual(@as(f64, 600), da.row(3)[dv].num); // sal 900 → dept 20 avg 600

    // QA's REOPENED case: FROM aliases on BOTH sides (self-subquery), correlation
    // y.g = x.g. Per-group avgs a=20, b=7 must show, NOT the global 12.2.
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("g", .char);
    _ = try d.addColumn("v", .num);
    for ([_]struct { g: []const u8, v: f64 }{
        .{ .g = "a", .v = 10 }, .{ .g = "a", .v = 30 },
        .{ .g = "b", .v = 5 },  .{ .g = "b", .v = 7 }, .{ .g = "b", .v = 9 },
    }) |r| try d.appendRow(&.{ strV(r.g), numV(r.v) });
    try lib.put("d", d);

    try runSql(a, &lib, &diags,
        "proc sql; create table ga as select g, v, " ++
        "(select avg(v) from d y where y.g=x.g) as ga from d x order by g, v; quit;");
    const g = lib.find("ga").?;
    const gc = g.indexOf("ga").?;
    try t.expectEqual(@as(usize, 5), g.rowCount());
    try t.expectEqual(@as(f64, 20), g.row(0)[gc].num); // a rows → 20 (not global 12.2)
    try t.expectEqual(@as(f64, 20), g.row(1)[gc].num);
    try t.expectEqual(@as(f64, 7), g.row(2)[gc].num); // b rows → 7
    try t.expectEqual(@as(f64, 7), g.row(4)[gc].num);

    try runSql(a, &lib, &diags,
        "proc sql; create table hw as select g, v from d x " ++
        "where v > (select avg(v) from d y where y.g=x.g) order by g; quit;");
    const hw = lib.find("hw").?;
    try t.expectEqual(@as(usize, 2), hw.rowCount()); // a 30 (>20), b 9 (>7) — was only a 30
    try t.expectEqual(@as(f64, 30), hw.row(0)[hw.indexOf("v").?].num);
    try t.expectEqual(@as(f64, 9), hw.row(1)[hw.indexOf("v").?].num);
}

test "cross / implicit / 3+-table joins + unqualified cols (SQL-joinmore)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const dsa = try a.create(Dataset);
    dsa.* = Dataset.init(a, "a");
    _ = try dsa.addColumn("id", .num);
    _ = try dsa.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 2, 20 }, .{ 3, 30 } }) |r| try dsa.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("a", dsa);
    const dsb = try a.create(Dataset);
    dsb.* = Dataset.init(a, "b");
    _ = try dsb.addColumn("id", .num);
    _ = try dsb.addColumn("y", .num);
    for ([_][2]f64{ .{ 2, 200 }, .{ 3, 300 } }) |r| try dsb.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("b", dsb);
    const dsc = try a.create(Dataset);
    dsc.* = Dataset.init(a, "c");
    _ = try dsc.addColumn("id", .num);
    _ = try dsc.addColumn("z", .num);
    for ([_][2]f64{ .{ 3, 33 }, .{ 9, 99 } }) |r| try dsc.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("c", dsc);

    // 1. implicit/comma cross join (no ON): 3×2 Cartesian, unqualified x,y resolve
    try runSql(a, &lib, &diags, "proc sql; create table j1 as select x, y from a, b order by x, y; quit;");
    const j1 = lib.find("j1").?;
    try t.expectEqual(@as(usize, 6), j1.rowCount());
    try t.expectEqual(@as(f64, 10), j1.row(0)[j1.indexOf("x").?].num); // x=10 pairs with y=200,300
    try t.expectEqual(@as(f64, 200), j1.row(0)[j1.indexOf("y").?].num);

    // 2. explicit CROSS JOIN keyword — same Cartesian
    try runSql(a, &lib, &diags, "proc sql; create table j2 as select x, y from a cross join b; quit;");
    try t.expectEqual(@as(usize, 6), lib.find("j2").?.rowCount());

    // 3. implicit join filtered by WHERE (comma + equijoin predicate) → ids 2,3
    try runSql(a, &lib, &diags,
        "proc sql; create table j3 as select a.id, x, y from a, b where a.id = b.id order by a.id; quit;");
    const j3 = lib.find("j3").?;
    try t.expectEqual(@as(usize, 2), j3.rowCount());
    try t.expectEqual(@as(f64, 2), j3.row(0)[j3.indexOf("id").?].num);
    try t.expectEqual(@as(f64, 200), j3.row(0)[j3.indexOf("y").?].num);

    // 4. 3-table chained join, mixed INNER then LEFT, unqualified cols across all three
    try runSql(a, &lib, &diags,
        "proc sql; create table j4 as select a.id, x, y, z from a inner join b on a.id=b.id " ++
        "left join c on b.id=c.id order by a.id; quit;");
    const j4 = lib.find("j4").?;
    try t.expectEqual(@as(usize, 2), j4.rowCount()); // ids 2,3 from a⋈b; c matches only 3
    try t.expect(j4.row(0)[j4.indexOf("z").?].isMissing()); // id=2 → no c match
    try t.expectEqual(@as(f64, 33), j4.row(1)[j4.indexOf("z").?].num); // id=3 → z=33
    try t.expectEqual(@as(f64, 300), j4.row(1)[j4.indexOf("y").?].num);
}

test "ORDER BY a CASE containing an aggregate, grouped (BUG-ordercaseagg)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("v", .num);
    // group sums: a=5, b=100, c=50 — the CASE (sum>=50 → 0) puts b,c ahead of a,
    // and within the 0-key the tie breaks on g → b,c,a. Group-key order would be a,b,c.
    for ([_]struct { g: []const u8, v: f64 }{
        .{ .g = "a", .v = 5 }, .{ .g = "b", .v = 100 }, .{ .g = "c", .v = 50 },
    }) |r| try ds.appendRow(&.{ strV(r.g), numV(r.v) });
    try lib.put("d", ds);

    try runSql(a, &lib, &diags,
        "proc sql; create table o as select g, sum(v) as s from d group by g " ++
        "order by case when sum(v) >= 50 then 0 else 1 end, g; quit;");
    const o = lib.find("o").?;
    try t.expectEqual(@as(usize, 3), o.rowCount());
    const gc = o.indexOf("g").?;
    try t.expectEqualStrings("b", o.row(0)[gc].str);
    try t.expectEqualStrings("c", o.row(1)[gc].str);
    try t.expectEqualStrings("a", o.row(2)[gc].str);
}

test "scalar subquery in a grouped SELECT list (BUG-sqlscalargroup)" {
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
    try ds.appendRow(&.{ strV("b"), numV(30) });
    try lib.put("d", ds);

    // global scalar subquery (count of the whole table) alongside a group aggregate
    try runSql(a, &lib, &diags,
        "proc sql; create table r as select g, sum(v) as s, (select count(*) from d) as n " ++
        "from d group by g order by g; quit;");
    const r = lib.find("r").?;
    try t.expectEqual(@as(usize, 2), r.rowCount());
    const ni = r.indexOf("n").?;
    try t.expectEqual(@as(f64, 30), r.row(0)[r.indexOf("s").?].num); // group a sum
    try t.expectEqual(@as(f64, 3), r.row(0)[ni].num); // was missing before the fix
    try t.expectEqual(@as(f64, 3), r.row(1)[ni].num);

    // correlated scalar subquery bound to the group key. The max() belongs to the
    // subquery, so the OUTER query has no summary function: SAS treats GROUP BY g
    // as ORDER BY g and returns every detail row (BUG-sqlgroupnoagg) — the
    // subquery still correlates per row to the same per-key maxima.
    try runSql(a, &lib, &diags,
        "proc sql; create table c as select g, (select max(v) from d y where y.g=x.g) as mx " ++
        "from d x group by g order by g; quit;");
    const c = lib.find("c").?;
    const mi = c.indexOf("mx").?;
    try t.expectEqual(@as(usize, 3), c.rowCount());
    try t.expectEqual(@as(f64, 20), c.row(0)[mi].num); // a → max 20
    try t.expectEqual(@as(f64, 20), c.row(1)[mi].num); // a again (no collapse)
    try t.expectEqual(@as(f64, 30), c.row(2)[mi].num); // b → max 30
}

test "group by with aggregate, groups in key order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    try ds.appendRow(&.{ numV(2), numV(30) }); // group 2 appears first
    try ds.appendRow(&.{ numV(1), numV(10) });
    try ds.appendRow(&.{ numV(1), numV(20) });
    try lib.put("have", ds);

    try runSql(a, &lib, &diags,
        "proc sql; create table s as select g, sum(x) as sx, count(*) as n from have group by g; quit;");

    const s = lib.find("s").?;
    try t.expectEqual(@as(usize, 2), s.rowCount());
    try t.expectEqual(@as(f64, 1), s.row(0)[0].num); // g=1 first (key order)
    try t.expectEqual(@as(f64, 30), s.row(0)[1].num); // sum 10+20
    try t.expectEqual(@as(f64, 2), s.row(0)[2].num); // n
    try t.expectEqual(@as(f64, 2), s.row(1)[0].num); // g=2
    try t.expectEqual(@as(f64, 30), s.row(1)[1].num);
}

test "WHERE col ne . before GROUP BY does not swallow the GROUP BY (BUG-sqlwherenemiss)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .char);
    _ = try ds.addColumn("price", .num);
    try ds.appendRow(&.{ .{ .str = "a" }, numV(10) });
    try ds.appendRow(&.{ .{ .str = "a" }, Value.missing }); // dropped by `price ne .`
    try ds.appendRow(&.{ .{ .str = "b" }, numV(3) });
    try lib.put("d", ds);

    // `ne . group` must not fold into a `ne.group` name token (which would drop
    // the GROUP BY and collapse every row into one group).
    try runSql(a, &lib, &diags,
        "proc sql; create table s as select g, count(*) as n from d where price ne . group by g order by g; quit;");
    const s = lib.find("s").?;
    try t.expectEqual(@as(usize, 2), s.rowCount()); // two groups, not one
    try t.expectEqualStrings("a", s.row(0)[0].str);
    try t.expectEqual(@as(f64, 1), s.row(0)[1].num); // group a: 1 non-missing row
    try t.expectEqualStrings("b", s.row(1)[0].str);
    try t.expectEqual(@as(f64, 1), s.row(1)[1].num);
}

test "select star copies all columns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("a", .num);
    _ = try ds.addColumn("b", .num);
    try ds.appendRow(&.{ numV(1), numV(2) });
    try lib.put("have", ds);

    try runSql(a, &lib, &diags, "proc sql; create table c as select * from have; quit;");
    const c = lib.find("c").?;
    try t.expectEqual(@as(usize, 2), c.columns.items.len);
    try t.expectEqual(@as(f64, 1), c.row(0)[0].num);
    try t.expectEqual(@as(f64, 2), c.row(0)[1].num);
}

test "cellText: non-finite (missing NaN / overflow inf) renders as '.', not nan/inf" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings(".", try cellText(a, Value.missing)); // NaN
    try t.expectEqualStrings(".", try cellText(a, numV(std.math.inf(f64)))); // +overflow
    try t.expectEqualStrings(".", try cellText(a, numV(-std.math.inf(f64)))); // -overflow
    try t.expectEqualStrings("42", try cellText(a, numV(42))); // finite still fine
}

test "HAVING, SELECT DISTINCT, and UNION (SQL-adv)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("g", .char);
    _ = try d.addColumn("v", .num);
    for ([_]struct { g: []const u8, v: f64 }{
        .{ .g = "a", .v = 10 }, .{ .g = "a", .v = 20 }, .{ .g = "b", .v = 5 }, .{ .g = "c", .v = 100 },
    }) |r| try d.appendRow(&.{ .{ .str = r.g }, .{ .num = r.v } });
    try lib.put("d", d);

    // HAVING drops group b (sum 5, not > 15)
    try runSql(a, &lib, &diags,
        "proc sql; create table h as select g, sum(v) as tot from d group by g having sum(v) > 15 order by g; quit;");
    const h = lib.find("h").?;
    try t.expectEqual(@as(usize, 2), h.rowCount());
    try t.expectEqualStrings("a", h.row(0)[0].str);
    try t.expectEqual(@as(f64, 30), h.row(0)[1].num);
    try t.expectEqualStrings("c", h.row(1)[0].str);

    // DISTINCT collapses the duplicate 'a' rows of v — build a table with dups first
    const nums = try a.create(Dataset);
    nums.* = Dataset.init(a, "nums");
    _ = try nums.addColumn("x", .num);
    for ([_]f64{ 1, 2, 2, 3, 3, 3 }) |x| try nums.appendRow(&.{.{ .num = x }});
    try lib.put("nums", nums);
    try runSql(a, &lib, &diags, "proc sql; create table u as select distinct x from nums order by x; quit;");
    const u = lib.find("u").?;
    try t.expectEqual(@as(usize, 3), u.rowCount());
    try t.expectEqual(@as(f64, 1), u.row(0)[0].num);
    try t.expectEqual(@as(f64, 3), u.row(2)[0].num);

    // UNION of {1,2} and {2,3} de-dups to {1,2,3}; UNION ALL keeps all 4
    const t1 = try a.create(Dataset);
    t1.* = Dataset.init(a, "t1");
    _ = try t1.addColumn("x", .num);
    for ([_]f64{ 1, 2 }) |x| try t1.appendRow(&.{.{ .num = x }});
    try lib.put("t1", t1);
    const t2 = try a.create(Dataset);
    t2.* = Dataset.init(a, "t2");
    _ = try t2.addColumn("x", .num);
    for ([_]f64{ 2, 3 }) |x| try t2.appendRow(&.{.{ .num = x }});
    try lib.put("t2", t2);
    try runSql(a, &lib, &diags, "proc sql; create table un as select x from t1 union select x from t2; quit;");
    try t.expectEqual(@as(usize, 3), lib.find("un").?.rowCount());
    try runSql(a, &lib, &diags, "proc sql; create table ua as select x from t1 union all select x from t2; quit;");
    try t.expectEqual(@as(usize, 4), lib.find("ua").?.rowCount());
}

test "CASE expr, HAVING on an alias, and ORDER BY after UNION (SQLFIX3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    // CASE
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    for ([_]f64{ 5, 15, 25 }) |x| try d.appendRow(&.{.{ .num = x }});
    try lib.put("d", d);
    try runSql(a, &lib, &diags,
        "proc sql; create table c as select x, case when x < 10 then \"lo\" when x < 20 then \"mid\" else \"hi\" end as grp from d; quit;");
    const c = lib.find("c").?;
    try t.expectEqualStrings("lo", c.row(0)[c.indexOf("grp").?].str);
    try t.expectEqualStrings("mid", c.row(1)[c.indexOf("grp").?].str);
    try t.expectEqualStrings("hi", c.row(2)[c.indexOf("grp").?].str);

    // HAVING on the SELECT alias `tot` (BUG-havingalias: was returning empty)
    const g = try a.create(Dataset);
    g.* = Dataset.init(a, "g");
    _ = try g.addColumn("k", .char);
    _ = try g.addColumn("v", .num);
    for ([_]struct { k: []const u8, v: f64 }{
        .{ .k = "a", .v = 10 }, .{ .k = "a", .v = 20 }, .{ .k = "b", .v = 5 },
    }) |r| try g.appendRow(&.{ .{ .str = r.k }, .{ .num = r.v } });
    try lib.put("g", g);
    try runSql(a, &lib, &diags,
        "proc sql; create table ha as select k, sum(v) as tot from g group by k having tot > 15; quit;");
    const ha = lib.find("ha").?;
    try t.expectEqual(@as(usize, 1), ha.rowCount()); // only k=a (30)
    try t.expectEqualStrings("a", ha.row(0)[0].str);

    // ORDER BY after UNION (BUG-unionorder: was ignored)
    const t1 = try a.create(Dataset);
    t1.* = Dataset.init(a, "t1");
    _ = try t1.addColumn("x", .num);
    for ([_]f64{ 3, 1 }) |x| try t1.appendRow(&.{.{ .num = x }});
    try lib.put("t1", t1);
    const t2 = try a.create(Dataset);
    t2.* = Dataset.init(a, "t2");
    _ = try t2.addColumn("x", .num);
    for ([_]f64{ 4, 2 }) |x| try t2.appendRow(&.{.{ .num = x }});
    try lib.put("t2", t2);
    try runSql(a, &lib, &diags,
        "proc sql; create table uo as select x from t1 union select x from t2 order by x; quit;");
    const uo = lib.find("uo").?;
    try t.expectEqual(@as(usize, 4), uo.rowCount());
    try t.expectEqual(@as(f64, 1), uo.row(0)[0].num);
    try t.expectEqual(@as(f64, 4), uo.row(3)[0].num);
}

test "ORDER BY position and ORDER BY a direct aggregate (SQLORDER)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    // ORDER BY 2 → sort by the 2nd SELECT column (v)
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("g", .char);
    _ = try d.addColumn("v", .num);
    for ([_]struct { g: []const u8, v: f64 }{
        .{ .g = "b", .v = 30 }, .{ .g = "a", .v = 10 }, .{ .g = "c", .v = 20 },
    }) |r| try d.appendRow(&.{ .{ .str = r.g }, .{ .num = r.v } });
    try lib.put("d", d);
    try runSql(a, &lib, &diags, "proc sql; create table p as select g, v from d order by 2; quit;");
    const p = lib.find("p").?;
    try t.expectEqual(@as(f64, 10), p.row(0)[1].num);
    try t.expectEqual(@as(f64, 30), p.row(2)[1].num);
    try t.expectEqualStrings("a", p.row(0)[0].str);

    // ORDER BY count(*) directly (not via alias)
    const e = try a.create(Dataset);
    e.* = Dataset.init(a, "e");
    _ = try e.addColumn("dept", .char);
    for ([_][]const u8{ "sales", "sales", "hr", "it", "it", "it" }) |s| try e.appendRow(&.{.{ .str = s }});
    try lib.put("e", e);
    try runSql(a, &lib, &diags, "proc sql; create table q as select dept, count(*) as n from e group by dept order by count(*); quit;");
    const q = lib.find("q").?;
    try t.expectEqual(@as(f64, 1), q.row(0)[q.indexOf("n").?].num); // hr
    try t.expectEqual(@as(f64, 3), q.row(2)[q.indexOf("n").?].num); // it
    try t.expectEqualStrings("hr", q.row(0)[0].str);
}

test "simple CASE compares the subject to each WHEN value (BUG-casesimple)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("grade", .char);
    for ([_][]const u8{ "A", "B", "C" }) |g| try d.appendRow(&.{.{ .str = g }});
    try lib.put("d", d);

    // simple form: `case grade when "A" then 4 …` — subject compared to each value
    try runSql(a, &lib, &diags,
        "proc sql; create table t as select grade, case grade when \"A\" then 4 when \"B\" then 3 else 0 end as gpa from d; quit;");
    const t2 = lib.find("t").?;
    const gi = t2.indexOf("gpa").?;
    try t.expectEqual(@as(f64, 4), t2.row(0)[gi].num); // A
    try t.expectEqual(@as(f64, 3), t2.row(1)[gi].num); // B (not the first branch)
    try t.expectEqual(@as(f64, 0), t2.row(2)[gi].num); // C → else
}

test "CASE inside a WHERE predicate filters correctly (BUG-casewhere)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    for ([_]f64{ 5, 15, 25 }) |x| try d.appendRow(&.{.{ .num = x }});
    try lib.put("d", d);

    // CASE in WHERE: keep rows whose case evaluates to "hi" (x >= 10)
    try runSql(a, &lib, &diags,
        "proc sql; create table t as select x from d where case when x < 10 then \"lo\" else \"hi\" end = \"hi\"; quit;");
    const t2 = lib.find("t").?;
    try t.expectEqual(@as(usize, 2), t2.rowCount()); // 15, 25 (not empty — was data loss)
    try t.expectEqual(@as(f64, 15), t2.row(0)[0].num);
    try t.expectEqual(@as(f64, 25), t2.row(1)[0].num);
}

test "nested CASE and ORDER BY a CASE expression (SQLCASE2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    for ([_]f64{ 5, 25, 15 }) |x| try d.appendRow(&.{.{ .num = x }});
    try lib.put("d", d);

    // nested CASE in a THEN value (BUG-casenest: was returning missing)
    try runSql(a, &lib, &diags,
        "proc sql; create table n as select x, case when x < 20 then case when x < 10 then \"lo\" else \"mid\" end else \"hi\" end as g from d; quit;");
    const n = lib.find("n").?;
    const gi = n.indexOf("g").?;
    // rows are in input order 5,25,15 → lo, hi, mid
    try t.expectEqualStrings("lo", n.row(0)[gi].str);
    try t.expectEqualStrings("hi", n.row(1)[gi].str);
    try t.expectEqualStrings("mid", n.row(2)[gi].str);

    // ORDER BY a CASE expression (BUG-ordercase: was ignored)
    try runSql(a, &lib, &diags,
        "proc sql; create table o as select x from d order by case when x < 10 then 1 when x < 20 then 2 else 3 end; quit;");
    const o = lib.find("o").?;
    try t.expectEqual(@as(f64, 5), o.row(0)[0].num);
    try t.expectEqual(@as(f64, 15), o.row(1)[0].num);
    try t.expectEqual(@as(f64, 25), o.row(2)[0].num);
}

test "CASE in a GROUP BY select — no crash, aggregates resolve (BUG-casegroupcrash)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("dept", .char);
    _ = try d.addColumn("v", .num);
    for ([_]struct { d: []const u8, v: f64 }{
        .{ .d = "a", .v = 10 }, .{ .d = "a", .v = 20 }, .{ .d = "b", .v = 5 }, .{ .d = "c", .v = 100 },
    }) |r| try d.appendRow(&.{ .{ .str = r.d }, .{ .num = r.v } });
    try lib.put("d", d);

    // a CASE over an aggregate under GROUP BY (was a null-unwrap crash)
    try runSql(a, &lib, &diags,
        "proc sql; create table t as select dept, case when sum(v) >= 30 then \"big\" else \"small\" end as sz, count(*) as n from d group by dept order by dept; quit;");
    const t2 = lib.find("t").?;
    const si = t2.indexOf("sz").?;
    try t.expectEqual(@as(usize, 3), t2.rowCount());
    try t.expectEqualStrings("big", t2.row(0)[si].str); // a: sum 30
    try t.expectEqualStrings("small", t2.row(1)[si].str); // b: sum 5
    try t.expectEqualStrings("big", t2.row(2)[si].str); // c: sum 100
}

test "COALESCE, CALCULATED, and HAVING with a CASE (SQL-coalcalc)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    // COALESCE: first non-missing
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("a", .num);
    _ = try d.addColumn("b", .num);
    const miss = std.math.nan(f64);
    try d.appendRow(&.{ .{ .num = miss }, .{ .num = 5 } });
    try d.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    try lib.put("d", d);
    try runSql(a, &lib, &diags, "proc sql; create table c as select coalesce(a, b) as v from d; quit;");
    const c = lib.find("c").?;
    try t.expectEqual(@as(f64, 5), c.row(0)[0].num);
    try t.expectEqual(@as(f64, 1), c.row(1)[0].num);

    // CALCULATED references a prior computed column
    const e = try a.create(Dataset);
    e.* = Dataset.init(a, "e");
    _ = try e.addColumn("x", .num);
    try e.appendRow(&.{.{ .num = 10 }});
    try lib.put("e", e);
    try runSql(a, &lib, &diags, "proc sql; create table q as select x, x * 2 as dbl, calculated dbl + 1 as inc from e; quit;");
    const q = lib.find("q").?;
    try t.expectEqual(@as(f64, 20), q.row(0)[q.indexOf("dbl").?].num);
    try t.expectEqual(@as(f64, 21), q.row(0)[q.indexOf("inc").?].num);

    // HAVING containing a CASE (was returning empty)
    const g = try a.create(Dataset);
    g.* = Dataset.init(a, "g");
    _ = try g.addColumn("k", .char);
    _ = try g.addColumn("v", .num);
    for ([_]struct { k: []const u8, v: f64 }{
        .{ .k = "a", .v = 10 }, .{ .k = "a", .v = 20 }, .{ .k = "b", .v = 5 },
    }) |r| try g.appendRow(&.{ .{ .str = r.k }, .{ .num = r.v } });
    try lib.put("g", g);
    try runSql(a, &lib, &diags,
        "proc sql; create table h as select k, sum(v) as tot from g group by k having case when sum(v) >= 30 then 1 else 0 end = 1; quit;");
    const h = lib.find("h").?;
    try t.expectEqual(@as(usize, 1), h.rowCount()); // only k=a (sum 30)
    try t.expectEqualStrings("a", h.row(0)[0].str);
}

test "GROUP BY an expression groups by its value (BUG-groupexpr)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("dt", .num);
    _ = try d.addColumn("v", .num);
    // 21915/21916 → 2020; 22281/22282 → 2021
    for ([_][2]f64{ .{ 21915, 10 }, .{ 22281, 20 }, .{ 21916, 5 }, .{ 22282, 100 } }) |r|
        try d.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] } });
    try lib.put("d", d);

    try runSql(a, &lib, &diags,
        "proc sql; create table t as select year(dt) as yr, count(*) as n, sum(v) as tot from d group by year(dt) order by yr; quit;");
    const t2 = lib.find("t").?;
    try t.expectEqual(@as(usize, 2), t2.rowCount()); // two years, not four per-row rows
    try t.expectEqual(@as(f64, 2020), t2.row(0)[t2.indexOf("yr").?].num);
    try t.expectEqual(@as(f64, 2), t2.row(0)[t2.indexOf("n").?].num);
    try t.expectEqual(@as(f64, 15), t2.row(0)[t2.indexOf("tot").?].num);
    try t.expectEqual(@as(f64, 120), t2.row(1)[t2.indexOf("tot").?].num);
}

test "count(distinct col) skips missing, no null-deref crash (BUG-countdistinctcrash)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("g", .num);
    _ = try d.addColumn("v", .num);
    // group 1: 10, 10, ., 20 → 2 distinct non-missing; group 2: 5, . → 1
    for ([_][2]f64{ .{ 1, 10 }, .{ 1, 10 }, .{ 1, undefinedNum() }, .{ 1, 20 }, .{ 2, 5 }, .{ 2, undefinedNum() } }) |r|
        try d.appendRow(&.{ .{ .num = r[0] }, if (std.math.isNan(r[1])) Value.missing else .{ .num = r[1] } });
    try lib.put("d", d);

    try runSql(a, &lib, &diags,
        "proc sql; create table t as select g, count(distinct v) as nd from d group by g; quit;");
    const t2 = lib.find("t").?;
    try t.expectEqual(@as(usize, 2), t2.rowCount());
    try t.expectEqual(@as(f64, 2), t2.row(0)[t2.indexOf("nd").?].num); // distinct {10,20}
    try t.expectEqual(@as(f64, 1), t2.row(1)[t2.indexOf("nd").?].num); // distinct {5}, . skipped
}

fn undefinedNum() f64 {
    return std.math.nan(f64);
}

test "CALCULATED alias in WHERE and HAVING (BUG-calcwhere)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    // WHERE calculated
    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30 }) |x| try d.appendRow(&.{.{ .num = x }});
    try lib.put("d", d);
    try runSql(a, &lib, &diags, "proc sql; create table w as select x, x * 2 as dbl from d where calculated dbl > 25; quit;");
    const w = lib.find("w").?;
    try t.expectEqual(@as(usize, 2), w.rowCount()); // 20,30 (dbl 40,60); not empty
    try t.expectEqual(@as(f64, 20), w.row(0)[0].num);
    try t.expectEqual(@as(f64, 30), w.row(1)[0].num);

    // HAVING calculated
    const g = try a.create(Dataset);
    g.* = Dataset.init(a, "g");
    _ = try g.addColumn("k", .char);
    _ = try g.addColumn("v", .num);
    for ([_]struct { k: []const u8, v: f64 }{
        .{ .k = "a", .v = 10 }, .{ .k = "a", .v = 20 }, .{ .k = "b", .v = 5 },
    }) |r| try g.appendRow(&.{ .{ .str = r.k }, .{ .num = r.v } });
    try lib.put("g", g);
    try runSql(a, &lib, &diags, "proc sql; create table h as select k, sum(v) as tot from g group by k having calculated tot > 15; quit;");
    const h = lib.find("h").?;
    try t.expectEqual(@as(usize, 1), h.rowCount()); // only k=a (30)
    try t.expectEqualStrings("a", h.row(0)[0].str);
}

test "ORDER BY sorts the whole UNION result, not just the last arm (BUG-unionorder)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const da = try a.create(Dataset);
    da.* = Dataset.init(a, "a");
    _ = try da.addColumn("x", .num);
    for ([_]f64{ 5, 1 }) |v| try da.appendRow(&.{numV(v)});
    try lib.put("a", da);
    const db = try a.create(Dataset);
    db.* = Dataset.init(a, "b");
    _ = try db.addColumn("x", .num);
    for ([_]f64{ 3, 9, 2 }) |v| try db.appendRow(&.{numV(v)});
    try lib.put("b", db);

    // ascending: the combined {5,1,3,9,2} sorts to 1,2,3,5,9 — not concat order
    try runSql(a, &lib, &diags, "proc sql; create table u as select x from a union select x from b order by x; quit;");
    const u = lib.find("u").?;
    try t.expectEqual(@as(usize, 5), u.rowCount());
    for ([_]f64{ 1, 2, 3, 5, 9 }, 0..) |want, i| try t.expectEqual(want, u.row(i)[0].num);

    // descending applies to the whole set too
    try runSql(a, &lib, &diags, "proc sql; create table d as select x from a union select x from b order by x desc; quit;");
    const d = lib.find("d").?;
    for ([_]f64{ 9, 5, 3, 2, 1 }, 0..) |want, i| try t.expectEqual(want, d.row(i)[0].num);
}

test "GROUP BY an expression collapses to groups, not per-row (BUG-groupexpr)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("v", .num);
    for ([_]f64{ 5, 15, 25, 8, 30 }) |v| try ds.appendRow(&.{numV(v)});
    try lib.put("d", ds);

    // group by the expression (v>10): two groups, not five per-row rows
    try runSql(a, &lib, &diags, "proc sql; create table g as select count(*) as n, sum(v) as s from d group by (v>10); quit;");
    const g = lib.find("g").?;
    try t.expectEqual(@as(usize, 2), g.rowCount());
    // key false (v<=10) first: {5,8} n=2 s=13 ; true: {15,25,30} n=3 s=70
    try t.expectEqual(@as(f64, 2), g.row(0)[0].num);
    try t.expectEqual(@as(f64, 13), g.row(0)[1].num);
    try t.expectEqual(@as(f64, 3), g.row(1)[0].num);
    try t.expectEqual(@as(f64, 70), g.row(1)[1].num);
}

test "aggregate over a CASE expression folds per group and whole-table, no crash (BUG-sqlsumcase)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ae = try a.create(Dataset);
    ae.* = Dataset.init(a, "ae");
    _ = try ae.addColumn("soc", .char);
    _ = try ae.addColumn("sev", .char);
    for ([_][2][]const u8{ .{ "A", "MILD" }, .{ "A", "SEV" }, .{ "B", "MILD" }, .{ "B", "MILD" } }) |r|
        try ae.appendRow(&.{ .{ .str = r[0] }, .{ .str = r[1] } });
    try lib.put("ae", ae);

    // grouped sum(case): A has 1 MILD, B has 2 (was a SIGABRT / missing)
    try runSql(a, &lib, &diags,
        "proc sql; create table x as select soc, sum(case when sev=\"MILD\" then 1 else 0 end) as mild from ae group by soc; quit;");
    const x = lib.find("x").?;
    try t.expectEqual(@as(usize, 2), x.rowCount());
    try t.expectEqual(@as(f64, 1), x.row(0)[x.indexOf("mild").?].num);
    try t.expectEqual(@as(f64, 2), x.row(1)[x.indexOf("mild").?].num);

    // ungrouped whole-table sum(case) collapses to one row = 3 MILD
    try runSql(a, &lib, &diags,
        "proc sql; create table y as select sum(case when sev=\"MILD\" then 1 else 0 end) as n from ae; quit;");
    try t.expectEqual(@as(usize, 1), lib.find("y").?.rowCount());
    try t.expectEqual(@as(f64, 3), lib.find("y").?.row(0)[0].num);
}

test "grouped STD/VAR/STDERR/CV/USS/RANGE/MEDIAN aggregates (GAP-sqlstataggs, VARDEF=DF); PRT still fails loud; multi-arg stays per-row (BUG-sqlgapexit)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    // g=1: x∈{1,2,3} → mean 2, css 2, var 1, std 1, se 1/√3, cv 50, uss 14, range 2, median 2
    // g=2: x∈{10,20} → mean 15, css 50, var 50, std √50, se 5
    for ([_][2]f64{ .{ 1, 1 }, .{ 1, 2 }, .{ 1, 3 }, .{ 2, 10 }, .{ 2, 20 } }) |r|
        try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("have", ds);

    const eps = 1e-9;
    diag.resetGap();
    try runSql(a, &lib, &diags,
        \\proc sql; create table o as
        \\  select g, std(x) as sd, var(x) as v, stderr(x) as se, cv(x) as cv,
        \\         uss(x) as uss, range(x) as rng, median(x) as med, t(x) as tt
        \\  from have group by g; quit;
    );
    try t.expect(!diag.gapHit());
    const o = lib.find("o").?; // rows in group-key order: g=1 then g=2
    const g1 = o.row(0);
    try t.expect(std.math.approxEqAbs(f64, 1, g1[1].num, eps)); // std
    try t.expect(std.math.approxEqAbs(f64, 1, g1[2].num, eps)); // var
    try t.expect(std.math.approxEqAbs(f64, 1.0 / @sqrt(3.0), g1[3].num, eps)); // stderr
    try t.expect(std.math.approxEqAbs(f64, 50, g1[4].num, eps)); // cv = 100*sd/mean
    try t.expect(std.math.approxEqAbs(f64, 14, g1[5].num, eps)); // uss = Σx²
    try t.expect(std.math.approxEqAbs(f64, 2, g1[6].num, eps)); // range = max-min
    try t.expect(std.math.approxEqAbs(f64, 2, g1[7].num, eps)); // median
    try t.expect(std.math.approxEqAbs(f64, 2.0 / (1.0 / @sqrt(3.0)), g1[8].num, eps)); // t = mean/stderr
    const g2 = o.row(1);
    try t.expect(std.math.approxEqAbs(f64, @sqrt(50.0), g2[1].num, eps)); // std
    try t.expect(std.math.approxEqAbs(f64, 50, g2[2].num, eps)); // var
    try t.expect(std.math.approxEqAbs(f64, 5, g2[3].num, eps)); // stderr = √50/√2

    // HAVING on an implemented stat aggregate: g=2 (var 50) survives, g=1 (var 1) drops
    diag.resetGap();
    try runSql(a, &lib, &diags,
        "proc sql; create table h as select g from have group by g having var(x) > 10; quit;");
    try t.expect(!diag.gapHit());
    const h = lib.find("h").?;
    try t.expectEqual(@as(usize, 1), h.rowCount());
    try t.expectEqual(@as(f64, 2), h.row(0)[0].num);

    // PRT is not implemented — single-arg call must still refuse loudly and create nothing
    diag.resetGap();
    try runSql(a, &lib, &diags,
        "proc sql; create table p as select g, prt(x) as pv from have group by g; quit;");
    try t.expect(diag.gapHit());
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "statistic aggregate") != null);
    try t.expect(lib.find("p") == null);

    // multi-argument = the per-row DATA-step function — stays allowed, not aggregated
    diag.resetGap();
    try runSql(a, &lib, &diags,
        "proc sql; create table m as select median(x, x + 2) as md from have; quit;");
    try t.expect(!diag.gapHit());
    const m = lib.find("m").?;
    try t.expectEqual(@as(f64, 2), m.row(0)[0].num); // median(1,3) per row 1
    diag.resetGap(); // leave the process-global flag clean for other tests
}

test "GROUP BY + expression detail column remerges to N rows; pure agg / group-key expr still collapse (BUG-sqlexprdetailremerge)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("dept", .num);
    _ = try ds.addColumn("sal", .num);
    // dept 1: {100,300} sum 400 ; dept 2: {200,200} sum 400
    for ([_][2]f64{ .{ 1, 100 }, .{ 1, 300 }, .{ 2, 200 }, .{ 2, 200 } }) |r|
        try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("t", ds);

    // remerge: `sal` inside sal/sum(sal) is non-summarized detail → one row per input row
    try runSql(a, &lib, &diags, "proc sql; create table f as select dept, sal/sum(sal) as frac from t group by dept; quit;");
    const f = lib.find("f").?;
    try t.expectEqual(@as(usize, 4), f.rowCount());
    const fi = f.indexOf("frac").?;
    try t.expectEqual(@as(f64, 0.25), f.row(0)[fi].num);
    try t.expectEqual(@as(f64, 0.75), f.row(1)[fi].num);
    try t.expectEqual(@as(f64, 0.5), f.row(2)[fi].num);
    try t.expectEqual(@as(f64, 0.5), f.row(3)[fi].num);

    // collapse: pure aggregate, no detail → one row per group
    try runSql(a, &lib, &diags, "proc sql; create table c1 as select dept, sum(sal) as tot from t group by dept; quit;");
    try t.expectEqual(@as(usize, 2), lib.find("c1").?.rowCount());

    // collapse: expression over only the group key → one row per group (guard, must NOT remerge)
    try runSql(a, &lib, &diags, "proc sql; create table c2 as select dept, dept/count(*) as g from t group by dept; quit;");
    try t.expectEqual(@as(usize, 2), lib.find("c2").?.rowCount());
}

test "CALCULATED referencing an aggregate alias resolves under GROUP BY (BUG-sqlcalcgroupagg)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t");
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("x", .num);
    for ([_][2]f64{ .{ 1, 10 }, .{ 1, 20 }, .{ 2, 5 } }) |r| try ds.appendRow(&.{ numV(r[0]), numV(r[1]) });
    try lib.put("t", ds);

    // `calculated s` where s = sum(x) was silently missing (substituteAggs can't see a
    // bare alias); chained calculated (d references calculated s) must also resolve.
    try runSql(a, &lib, &diags,
        "proc sql; create table o as select g, sum(x) as s, calculated s / 2 as half, calculated half + 1 as h1 from t group by g; quit;");
    const o = lib.find("o").?;
    try t.expectEqual(@as(usize, 2), o.rowCount());
    const si = o.indexOf("s").?;
    const hi = o.indexOf("half").?;
    const h1 = o.indexOf("h1").?;
    try t.expectEqual(@as(f64, 30), o.row(0)[si].num);
    try t.expectEqual(@as(f64, 15), o.row(0)[hi].num); // 30/2, was . before the fix
    try t.expectEqual(@as(f64, 16), o.row(0)[h1].num); // 15+1
    try t.expectEqual(@as(f64, 2.5), o.row(1)[hi].num); // 5/2
}

test "set operator with mismatched column counts pads by position, no crash (BUG-sqlsetopcols)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const wide = try a.create(Dataset);
    wide.* = Dataset.init(a, "wide");
    _ = try wide.addColumn("x", .num);
    _ = try wide.addColumn("n", .num);
    try wide.appendRow(&.{ numV(1), numV(10) });
    try wide.appendRow(&.{ numV(2), numV(20) });
    try lib.put("wide", wide);
    const narrow = try a.create(Dataset);
    narrow.* = Dataset.init(a, "narrow");
    _ = try narrow.addColumn("y", .num);
    try narrow.appendRow(&.{numV(3)});
    try lib.put("narrow", narrow);

    // 2-col UNION 1-col: SAS pads the short arm's 2nd column with missing (was a panic).
    try runSql(a, &lib, &diags, "proc sql; create table r as select x, n from wide union select y from narrow; quit;");
    const r = lib.find("r").?;
    try t.expectEqual(@as(usize, 2), r.columns.items.len);
    try t.expectEqual(@as(usize, 3), r.rowCount()); // {1,10},{2,20},{3,.}
    // find the row from the narrow arm (x=3) and assert its n is missing
    var found = false;
    for (0..r.rowCount()) |i| if (r.row(i)[0].num == 3) {
        try t.expect(r.row(i)[1].isMissing());
        found = true;
    };
    try t.expect(found);
}

test "cross-type UNION coerces result column to character (BUG-sqlunioncoerce)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const nums = try a.create(Dataset);
    nums.* = Dataset.init(a, "nums");
    _ = try nums.addColumn("v", .num);
    try nums.appendRow(&.{numV(42)});
    try lib.put("nums", nums);
    const chars = try a.create(Dataset);
    chars.* = Dataset.init(a, "chars");
    _ = try chars.addColumn("c", .char);
    try chars.appendRow(&.{.{ .str = "hi" }});
    try lib.put("chars", chars);

    // num arm UNION char arm: SAS coerces the result column to CHARACTER,
    // rendering the numeric 42 as text "42" (char wins).
    try runSql(a, &lib, &diags, "proc sql; create table u as select v from nums union select c from chars; quit;");
    const u = lib.find("u").?;
    try t.expectEqual(@as(usize, 1), u.columns.items.len);
    try t.expectEqual(VarType.char, u.columns.items[0].type); // result column is CHARACTER
    try t.expectEqual(@as(usize, 2), u.rowCount());
    var saw42 = false;
    var sawhi = false;
    for (0..u.rowCount()) |i| {
        const s = std.mem.trimEnd(u8, u.row(i)[0].str, " ");
        if (std.mem.eql(u8, s, "42")) saw42 = true;
        if (std.mem.eql(u8, s, "hi")) sawhi = true;
    }
    try t.expect(saw42 and sawhi); // numeric value rendered as text alongside the char value
}

test "special missings stay distinct in SQL dedup/GROUP BY and render as letters (BUG-sqlmissdistinct)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sm");
    _ = try ds.addColumn("k", .num);
    try ds.appendRow(&.{Value.specialMissing('A')});
    try ds.appendRow(&.{Value.missing});
    try ds.appendRow(&.{Value.specialMissing('A')});
    try ds.appendRow(&.{Value.specialMissing('Z')});
    try ds.appendRow(&.{Value.specialMissing('_')});
    try lib.put("sm", ds);

    // cmpVal: special missings compare/sort by rank, not one NaN bucket
    try t.expect(cmpVal(Value.specialMissing('A'), Value.missing) != .eq);
    try t.expect(cmpVal(Value.specialMissing('A'), Value.specialMissing('A')) == .eq);
    try t.expect(cmpVal(Value.specialMissing('_'), Value.missing) == .lt); // ._ < .
    try t.expect(cmpVal(Value.missing, Value.specialMissing('A')) == .lt); // . < .A

    // SELECT DISTINCT keeps .A, ., .Z, ._ apart (4 rows; the dup .A dedups)
    try runSql(a, &lib, &diags, "proc sql; create table d as select distinct k from sm; quit;");
    try t.expectEqual(@as(usize, 4), lib.find("d").?.rowCount());

    // GROUP BY: .A group has 2 rows, . and .Z and ._ one each
    try runSql(a, &lib, &diags, "proc sql; create table g as select k, count(*) as n from sm group by k; quit;");
    const g = lib.find("g").?;
    try t.expectEqual(@as(usize, 4), g.rowCount());
    for (0..g.rowCount()) |i| {
        const r = g.row(i);
        if (Value.missingChar(r[0].num) == 'A') try t.expectEqual(@as(f64, 2), r[1].num);
    }

    // display: special missings render as their letter, plain missing as '.'
    try t.expectEqualStrings("A", try cellText(a, Value.specialMissing('A')));
    try t.expectEqualStrings("Z", try cellText(a, Value.specialMissing('Z')));
    try t.expectEqualStrings("_", try cellText(a, Value.specialMissing('_')));
    try t.expectEqualStrings(".", try cellText(a, Value.missing));
}

test "derived table (in-line view) in FROM, with alias-qualified columns + outer WHERE (GAP-sqlderivedtable)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    const x = try a.create(Dataset);
    x.* = Dataset.init(a, "x");
    _ = try x.addColumn("g", .char);
    _ = try x.addColumn("v", .num);
    for ([_]struct { g: []const u8, v: f64 }{ .{ .g = "A", .v = 1 }, .{ .g = "A", .v = 2 }, .{ .g = "B", .v = 3 } }) |r|
        try x.appendRow(&.{ .{ .str = r.g }, numV(r.v) });
    try lib.put("x", x);

    // SAS 9.4 SQL "in-line view": a subquery as a FROM source, aliased; alias-qualified
    // columns (t.g/t.n) and an outer WHERE on a derived column must resolve. Before the
    // fix the alias was reused as the temp table name (table==alias) → no rows, and
    // `t.col` never matched an unqualified derived column (BUG-sqlqualcol).
    try runSql(a, &lib, &diags,
        "proc sql; create table o as select t.g, t.n from (select g, count(*) as n from x group by g) as t where t.n > 1; quit;");
    const o = lib.find("o").?;
    try t.expectEqual(@as(usize, 1), o.rowCount()); // only A (n=2>1); B (n=1) filtered
    try t.expectEqualStrings("A", o.row(0)[o.indexOf("g").?].str);
    try t.expectEqual(@as(f64, 2), o.row(0)[o.indexOf("n").?].num);

    // qualified column on a plain (non-join) aliased table must also resolve now
    try runSql(a, &lib, &diags, "proc sql; create table q as select t.g, t.v from x as t where t.v > 1; quit;");
    try t.expectEqual(@as(usize, 2), lib.find("q").?.rowCount()); // v=2 and v=3

    // derived table joined to a real table
    const lk = try a.create(Dataset);
    lk.* = Dataset.init(a, "lk");
    _ = try lk.addColumn("g", .char);
    _ = try lk.addColumn("lab", .char);
    try lk.appendRow(&.{ .{ .str = "A" }, .{ .str = "alpha" } });
    try lk.appendRow(&.{ .{ .str = "B" }, .{ .str = "bravo" } });
    try lib.put("lk", lk);
    try runSql(a, &lib, &diags,
        "proc sql; create table j as select d.g, d.n, lk.lab from (select g, count(*) as n from x group by g) as d inner join lk on d.g = lk.g; quit;");
    try t.expectEqual(@as(usize, 2), lib.find("j").?.rowCount());
}

test "equi-join hash fast path matches nested-loop semantics (BUG-sqljoinoom)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    const l = try a.create(Dataset);
    l.* = Dataset.init(a, "l");
    _ = try l.addColumn("id", .char);
    _ = try l.addColumn("n", .num);
    try l.appendRow(&.{ strV("A  "), numV(1) }); // trailing blanks still match "A"
    try l.appendRow(&.{ strV("B"), numV(2) });
    try l.appendRow(&.{ strV("C"), Value.missing }); // `.` = `.` matches, as the loop did
    try l.appendRow(&.{ strV("X"), numV(9) }); // unmatched left → right side missing
    try lib.put("l", l);

    const r = try a.create(Dataset);
    r.* = Dataset.init(a, "r");
    _ = try r.addColumn("rid", .char);
    _ = try r.addColumn("rn", .num);
    _ = try r.addColumn("v", .num);
    try r.appendRow(&.{ strV("A"), numV(1), numV(10) });
    try r.appendRow(&.{ strV("A"), numV(1), numV(11) }); // duplicate key → two output rows
    try r.appendRow(&.{ strV("B"), numV(2), numV(20) });
    try r.appendRow(&.{ strV("C"), Value.missing, numV(30) });
    try r.appendRow(&.{ strV("Z"), numV(7), numV(99) }); // never matches
    try lib.put("r", r);

    // two-key AND-of-equalities: the SDTM LB join shape that OOMed at study scale
    try runSql(a, &lib, &diags,
        "proc sql; create table j as select a.id, a.n, b.v from l as a left join r as b on a.id = b.rid and a.n = b.rn; quit;");

    const j = lib.find("j").?;
    // 2 (dup A) + 1 (B) + 1 (C, missing=missing) + 1 (unmatched X) = 5, in left-row order
    try t.expectEqual(@as(usize, 5), j.rowCount());
    try t.expectEqual(@as(f64, 10), j.row(0)[2].num);
    try t.expectEqual(@as(f64, 11), j.row(1)[2].num);
    try t.expectEqual(@as(f64, 20), j.row(2)[2].num);
    try t.expectEqual(@as(f64, 30), j.row(3)[2].num);
    try t.expect(j.row(4)[2].isMissing());

    // special missings stay distinct under the hash key: .A joins .A, not `.`
    const s1 = try a.create(Dataset);
    s1.* = Dataset.init(a, "s1");
    _ = try s1.addColumn("k", .num);
    try s1.appendRow(&.{Value.specialMissing('A')});
    try s1.appendRow(&.{Value.missing});
    try lib.put("s1", s1);
    const s2 = try a.create(Dataset);
    s2.* = Dataset.init(a, "s2");
    _ = try s2.addColumn("k2", .num);
    _ = try s2.addColumn("tag", .char);
    try s2.appendRow(&.{ Value.specialMissing('A'), strV("spA") });
    try s2.appendRow(&.{ Value.missing, strV("dot") });
    try lib.put("s2", s2);
    try runSql(a, &lib, &diags,
        "proc sql; create table sj as select b.tag from s1 as a inner join s2 as b on a.k = b.k2; quit;");
    const sj = lib.find("sj").?;
    try t.expectEqual(@as(usize, 2), sj.rowCount());
    try t.expectEqualStrings("spA", sj.row(0)[0].str);
    try t.expectEqualStrings("dot", sj.row(1)[0].str);
}

test "BUG-sqlconstraints: PK/NOT NULL/CHECK/UNIQUE enforced, no phantom columns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    // table-level PRIMARY KEY: dup rejected, and no phantom `primary`/`constraint` column
    try runSql(a, &lib, &diags,
        "proc sql; create table pkt (id num, primary key(id)); insert into pkt values(1); insert into pkt values(1); quit;");
    const pkt = lib.find("pkt").?;
    try t.expectEqual(@as(usize, 1), pkt.columns.items.len); // no phantom column
    try t.expectEqualStrings("id", pkt.columns.items[0].name);
    try t.expectEqual(@as(usize, 1), pkt.rowCount()); // the dup was rejected
    try t.expect(diags.hasErrors()); // reported as an ERROR (captured, not spawned)

    // column-level NOT NULL + named constraint form; `constraint` named table-level PK
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2,
        "proc sql; create table nnt (a num not null, b char, constraint nn_pk primary key(a)); " ++
            "insert into nnt values(5, 'x'); insert into nnt(a) values(6); insert into nnt(b) values('y'); quit;");
    const nnt = lib.find("nnt").?;
    try t.expectEqual(@as(usize, 2), nnt.columns.items.len);
    try t.expectEqual(@as(usize, 2), nnt.rowCount()); // 'y' row rejected (a missing), (6,'') ok
    try t.expect(d2.hasErrors());

    // column-level CHECK: the failing row is rejected. SAS predicates are
    // 2-valued — a missing age makes `age >= 18` FALSE (not SQL UNKNOWN), so
    // the missing row is rejected as well.
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3,
        "proc sql; create table ckt (age num, check (age >= 18)); " ++
            "insert into ckt values(20); insert into ckt values(7); insert into ckt values(.); quit;");
    const ckt = lib.find("ckt").?;
    try t.expectEqual(@as(usize, 1), ckt.rowCount()); // only 20 survives
    try t.expect(d3.hasErrors());

    // UNIQUE column-level: dup rejected, two missings pass
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4,
        "proc sql; create table uqt (k num unique); " ++
            "insert into uqt values(1); insert into uqt values(1); insert into uqt values(.); insert into uqt values(.); quit;");
    try t.expectEqual(@as(usize, 3), lib.find("uqt").?.rowCount());
    try t.expect(d4.hasErrors());

    // UPDATE respects constraints: the violating update is rejected, row kept
    var d5 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d5,
        "proc sql; update pkt set id = 1; quit;"); // would dup the existing pk value... only 1 row: updates own row (skip) → ok
    try t.expect(!d5.hasErrors()); // own row excluded from the scan → no violation
    try runSql(a, &lib, &d5,
        "proc sql; insert into pkt values(2); update pkt set id = 1 where id = 2; quit;");
    try t.expectEqual(@as(usize, 2), pkt.rowCount()); // the violating UPDATE was rejected
    try t.expectEqual(@as(f64, 2), pkt.row(1)[0].num); // original value kept
    try t.expect(d5.hasErrors());
}

test "BUG-sqlconstraints: FOREIGN KEY enforced child-side (both forms)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var lib = Library.init(a);

    try runSql(a, &lib, &diags,
        "proc sql; create table par (id num, primary key(id)); insert into par values(1); insert into par values(2); " ++
            "create table chi (cid num, pid num references par(id)); " ++
            "insert into chi values(10, 1); insert into chi values(11, 99); insert into chi values(12, .); quit;");
    const chi = lib.find("chi").?;
    try t.expectEqual(@as(usize, 2), chi.columns.items.len); // no phantom columns
    try t.expectEqual(@as(usize, 2), chi.rowCount()); // (10,1) ok; 99 rejected; NULL child passes
    try t.expect(diags.hasErrors());

    // table-level foreign key … references (bare → parent's PRIMARY KEY)
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2,
        "proc sql; create table ch2 (x num, foreign key (x) references par); " ++
            "insert into ch2 values(2); insert into ch2 values(7); quit;");
    try t.expectEqual(@as(usize, 1), lib.find("ch2").?.rowCount());
    try t.expect(d2.hasErrors());
}

test "BUG-sqlconsleak: the constraint registry is bounded by the LIVE library, not the life of the process" {
    // THE CORPUS CANNOT REACH THE CROSS-RUN HALF and that is on the record: both
    // fixture runners spawn one process per fixture, so a registry that survives
    // from one program to the next is unexpressible there even with `expect-rc:`.
    // This in-file test is the only automated protection for it, and it is a real
    // one — `run` is exactly the function `main.interpret` drives once per program,
    // and wasm.zig runs many programs per module load against a fresh Library each
    // time. NOTHING below resets `g_cons_len` by hand; the point is that `run`
    // itself must do it (the three tests that used to hand-reset now rely on this).

    // (1) CROSS-RUN. One "program": three constrained tables in their own arena,
    // which is then freed (the block's `defer` also fires if an assert below trips,
    // so a red run reports the assert and not a pile of leaks).
    {
        var arena1 = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena1.deinit(); // …and that program's tables become dangling pointers
        const a1 = arena1.allocator();
        var d1 = diag.Diagnostics.init(a1);
        var lib1 = Library.init(a1);
        try runSql(a1, &lib1, &d1,
            "proc sql; create table r1 (x num, primary key(x)); create table r2 (y num not null); " ++
                "create table r3 (z num unique); quit;");
        // EXACTLY three — every earlier test's registration was pruned on entry,
        // which is the same assertion as "a prior program's entries are gone".
        try t.expectEqual(@as(usize, 3), g_cons_len);
    }

    // The NEXT "program": a fresh Library, one constrained table. Pre-fix this read
    // 4 and only ever grew, until the 256 slots filled and a later program was told
    // "too many constrained tables" for tables it never created.
    var arena2 = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena2.deinit();
    const a = arena2.allocator();
    var d2 = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    try runSql(a, &lib, &d2, "proc sql; create table k (x num, primary key(x)); quit;");
    try t.expectEqual(@as(usize, 1), g_cons_len);

    // CONTROL: pruning must not disarm enforcement. The surviving PK still rejects
    // a duplicate, across a LATER step (so it survives that step's prune too).
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; insert into k values(1); insert into k values(1); quit;");
    try t.expectEqual(@as(usize, 1), lib.find("k").?.rowCount());
    try t.expect(d3.hasErrors());
    try t.expectEqual(@as(usize, 1), g_cons_len);

    // (2) IN-RUN, the second growth door: an ALTER that carries a constraint
    // re-registers the whole MERGED list (see the `acons` block in alterTable), so
    // repeated ALTERs on ONE table grew the registry without bound even inside a
    // single program. `constraintsOf` only ever reads the newest entry for a table,
    // so dropping the superseded ones is behaviour-preserving by construction.
    // (Spelling matters here: `alter table m add constraint c check (…)` is NOT the
    // table-level form — this file's ALTER only does ADD COLUMN, so that text adds a
    // phantom column named `constraint`. A first draft of this test used it and
    // passed on an INSERT ARITY error instead of on a constraint. Reported, not
    // fixed here.)
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table m (x num); quit;");
    for (0..5) |n| {
        var dn = diag.Diagnostics.init(a);
        const src = try std.fmt.allocPrint(a, "proc sql; alter table m add c{d} num not null; quit;", .{n});
        try runSql(a, &lib, &dn, src);
    }
    try t.expect(g_cons_len <= 3); // pre-fix: 1 (k) + 5 (alters) = 6, and rising
    // …and the MERGED list survived the pruning: the constraint added by the FIRST
    // alter (c0) still rejects, not just the newest one.
    var d5 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d5, "proc sql; insert into m values(1, ., 1, 1, 1, 1); quit;");
    try t.expectEqual(@as(usize, 0), lib.find("m").?.rowCount());
    try t.expect(d5.hasErrors());
    var d5b = diag.Diagnostics.init(a); // positive control: a compliant row goes in
    try runSql(a, &lib, &d5b, "proc sql; insert into m values(1, 1, 1, 1, 1, 1); quit;");
    try t.expectEqual(@as(usize, 1), lib.find("m").?.rowCount());
    try t.expect(!d5b.hasErrors());

    // (3) A DROPped table's entry goes too — it is unreachable, and holding it was
    // the third way the slots filled.
    const before = g_cons_len;
    var d6 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d6, "proc sql; drop table m; quit;");
    var d7 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d7, "proc sql; select * from k; quit;");
    try t.expect(g_cons_len < before);
}

test "WHERE validates column refs: unknown col and CALCULATED summary alias fail loud (BUG-sqlwhereunknown, BUG-sqlwherecalcagg)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "d");
    _ = try d.addColumn("x", .num);
    for ([_]f64{ 10, 20, 30 }) |x| try d.appendRow(&.{numV(x)});
    try lib.put("d", d);
    const g = try a.create(Dataset);
    g.* = Dataset.init(a, "g");
    _ = try g.addColumn("k", .char);
    _ = try g.addColumn("v", .num);
    for ([_]struct { k: []const u8, v: f64 }{ .{ .k = "a", .v = 1 }, .{ .k = "a", .v = 2 }, .{ .k = "b", .v = 5 } }) |r|
        try g.appendRow(&.{ strV(r.k), numV(r.v) });
    try lib.put("g", g);

    // unknown column → loud ERROR naming it, NO table (was: 0 rows, rc 0)
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; create table bad as select x from d where nosuchcol = 1; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expect(lib.find("bad") == null);
    var named = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "contributing tables") != null and std.mem.indexOf(u8, m.message, "nosuchcol") != null) {
            named = true;
        };
    try t.expect(named);

    // CALCULATED reference to a SUMMARY alias → loud summary-restricted ERROR
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; create table bad2 as select k, sum(v) as s from g where calculated s > 2 group by k; quit;") catch {};
    try t.expect(d2.hasErrors());
    try t.expect(lib.find("bad2") == null);
    var restricted = false;
    for (d2.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "restricted to the SELECT and HAVING") != null) {
            restricted = true;
        };
    try t.expect(restricted);

    // a bare summary alias (no CALCULATED) → not a contributing column → ERROR too
    var d2b = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2b, "proc sql; create table bad2b as select k, sum(v) as s from g where s > 2 group by k; quit;") catch {};
    try t.expect(d2b.hasErrors());
    try t.expect(lib.find("bad2b") == null);

    // well-formed WHERE unchanged: real column + CALCULATED non-aggregate alias filter
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table ok as select x, x * 2 as dbl from d where x > 5 and calculated dbl < 50; quit;");
    try t.expect(!d3.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqual(@as(usize, 2), ok.rowCount()); // x=10 (dbl 20), x=20 (dbl 40); x=30 → dbl 60 out
    try t.expectEqual(@as(f64, 10), ok.row(0)[0].num);
    try t.expectEqual(@as(f64, 20), ok.row(1)[0].num);

    // qualified ref + function call + subquery (its own WHERE) still validate clean;
    // a legitimately empty result stays silent (x≥10 ∩ v={1,2,5} → 0 rows, no ERROR)
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table ok2 as select x from d as dd where dd.x >= 10 and abs(x) > 1 and x in (select v from g where v > 0); quit;");
    try t.expect(!d4.hasErrors());
    try t.expectEqual(@as(usize, 0), lib.find("ok2").?.rowCount());
}

test "DML WHERE validates column refs: unknown col in UPDATE/DELETE fails loud (GAP-sqldmlwhere)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "t");
    _ = try d.addColumn("a", .num);
    for ([_]f64{ 1, 2, 3 }) |x| try d.appendRow(&.{numV(x)});
    try lib.put("t", d);

    // unknown column in DELETE WHERE → loud ERROR naming it, table untouched
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; delete from t where nosuchcol = 1; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expectEqual(@as(usize, 3), lib.find("t").?.rowCount()); // nothing deleted
    var named1 = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "contributing tables") != null and std.mem.indexOf(u8, m.message, "nosuchcol") != null) {
            named1 = true;
        };
    try t.expect(named1);

    // unknown column in UPDATE WHERE → loud ERROR naming it, table untouched
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; update t set a = 99 where nosuchcol = 2; quit;") catch {};
    try t.expect(d2.hasErrors());
    try t.expectEqual(@as(f64, 1), lib.find("t").?.row(0)[0].num); // nothing updated
    var named2 = false;
    for (d2.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "contributing tables") != null and std.mem.indexOf(u8, m.message, "nosuchcol") != null) {
            named2 = true;
        };
    try t.expect(named2);

    // valid UPDATE/DELETE with a real WHERE column: unchanged, no ERROR
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; update t set a = 10 * a where a >= 2; delete from t where a = 1; quit;");
    try t.expect(!d3.hasErrors());
    const ok = lib.find("t").?;
    try t.expectEqual(@as(usize, 2), ok.rowCount()); // a=1 deleted, a=20 & 30 remain
    try t.expectEqual(@as(f64, 20), ok.row(0)[0].num);
    try t.expectEqual(@as(f64, 30), ok.row(1)[0].num);
}

test "UPDATE SET bad col / SELECT bad col fail loud; DROP TABLE/VIEW implemented (BUG-sqlupdatedropcol)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "t");
    _ = try d.addColumn("a", .num);
    for ([_]f64{ 1, 2, 3 }) |x| try d.appendRow(&.{numV(x)});
    try lib.put("t", d);

    // UPDATE SET naming no column → loud ERROR naming it, table untouched
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; update t set nosuchcol = 1; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expectEqual(@as(f64, 1), lib.find("t").?.row(0)[0].num); // nothing updated
    var named1 = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "contributing tables") != null and std.mem.indexOf(u8, m.message, "nosuchcol") != null) {
            named1 = true;
        };
    try t.expect(named1);

    // SELECT of an unknown column → the precise SAS message, not "unreported error"
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; select nosuchcol from t; quit;") catch {};
    try t.expect(d2.hasErrors());
    var named2 = false;
    for (d2.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "contributing tables") != null and std.mem.indexOf(u8, m.message, "nosuchcol") != null) {
            named2 = true;
        };
    try t.expect(named2);

    // CREATE-AS of an unknown column → same precise message, no output table
    var d3 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d3, "proc sql; create table bad as select nosuchcol from t; quit;") catch {};
    try t.expect(d3.hasErrors());
    try t.expect(lib.find("bad") == null);

    // DROP TABLE really removes the member (was a silent no-op)
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; drop table t; quit;");
    try t.expect(lib.find("t") == null); // t is GONE

    // DROP of an absent table → loud "does not exist" ERROR
    var d5 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d5, "proc sql; drop table nonesuch; quit;") catch {};
    try t.expect(d5.hasErrors());
    var named5 = false;
    for (d5.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "does not exist") != null and std.mem.indexOf(u8, m.message, "nonesuch") != null) {
            named5 = true;
        };
    try t.expect(named5);

    // DROP VIEW → loud ERROR (CREATE VIEW is unsupported, so no view can exist)
    var d6 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d6, "proc sql; drop view v; quit;") catch {};
    try t.expect(d6.hasErrors());

    // valid UPDATE + SELECT + DROP-of-existing: unchanged, no ERROR
    const ok = try a.create(Dataset);
    ok.* = Dataset.init(a, "ok");
    _ = try ok.addColumn("a", .num);
    try ok.appendRow(&.{numV(5)});
    try lib.put("ok", ok);
    var d7 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d7, "proc sql; update ok set a = a + 1; select a from ok; quit;");
    try t.expect(!d7.hasErrors());
    try t.expectEqual(@as(f64, 6), lib.find("ok").?.row(0)[0].num); // valid UPDATE unchanged
    try runSql(a, &lib, &d7, "proc sql; drop table ok; quit;");
    try t.expect(!d7.hasErrors());
    try t.expect(lib.find("ok") == null); // DROP of an existing table works, quietly
}

test "BUG-sqltypeconsistency: mixed-type CASE results fail loud, consistent CASE untouched" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("c", .char);
    try ds.appendRow(&.{ numV(5), strV("hi") });
    try lib.put("have", ds);

    // char THEN literal + numeric ELSE literal → ERROR (SAS: "Type mismatch")
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; create table bad as select case when x > 0 then 'yes' else 5 end as m from have; quit;") catch {};
    try t.expect(d1.hasErrors()); // captured diagnostics — no spawned process
    try t.expect(lib.find("bad") == null);
    var loud = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "CASE expression has both character and numeric result values") != null) {
            loud = true;
        };
    try t.expect(loud);

    // numeric column-ref arm + char literal arm → ERROR too (PDV-typed oracle)
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; create table bad2 as select case when x > 0 then x else 'n/a' end as m from have; quit;") catch {};
    try t.expect(d2.hasErrors());
    try t.expect(lib.find("bad2") == null);

    // all-char arms, all-num arms, and a simple CASE with a char subject over
    // numeric results are all CONSISTENT — no error, values unchanged.
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table ok as select" ++
        " case when x > 0 then 'yes' else 'no' end as f1," ++
        " case x when 5 then 1 else 0 end as f2," ++
        " case when x > 0 then c else 'none' end as f3 from have; quit;");
    try t.expect(!d3.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqualStrings("yes", ok.row(0)[0].str);
    try t.expectEqual(@as(f64, 1), ok.row(0)[1].num);
    try t.expectEqualStrings("hi", ok.row(0)[2].str);
}

test "BUG-sqltypeconsistency: mixed-type COALESCE arguments fail loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lib = Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "have");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("c", .char);
    try ds.appendRow(&.{ Value.missing, strV("hi") });
    try lib.put("have", ds);

    // numeric column + char literal → ERROR (SAS: type mismatch)
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; create table bad as select coalesce(x, 'n/a') as m from have; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expect(lib.find("bad") == null);
    var loud = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "COALESCE arguments must be all character or all numeric") != null) {
            loud = true;
        };
    try t.expect(loud);

    // all-numeric and all-character COALESCEs are untouched (first non-missing wins)
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2, "proc sql; create table ok as select coalesce(x, 0) as n, coalesce(c, 'zz') as s from have; quit;");
    try t.expect(!d2.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqual(@as(f64, 0), ok.row(0)[0].num);
    try t.expectEqualStrings("hi", ok.row(0)[1].str);
}

test "BUG-sqltypeconsistency: char literal into a NUMERIC column converts (NOTE), never raw text" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    try runSql(a, &lib, &diags, "proc sql;" ++
        " create table t (a num, b char(8));" ++
        " insert into t values ('12.5', 'x');" ++ // parseable → 12.5
        " insert into t values ('abc', 'y');" ++ // unparseable → missing
        " insert into t values (7, 'z');" ++ // already numeric — untouched
        " update t set a = '3.25' where b = 'z';" ++ // UPDATE SET converts too
        " quit;");
    try t.expect(!diags.hasErrors()); // SAS converts with NOTEs — never an ERROR
    const tab = lib.find("t").?;
    try t.expectEqual(@as(f64, 12.5), tab.row(0)[0].num);
    try t.expect(tab.row(1)[0].isMissing()); // 'abc' → missing, not the raw text
    try t.expectEqual(@as(f64, 3.25), tab.row(2)[0].num);
    // the converted + "Invalid numeric data" NOTE pair fired (captured)
    var converted = false;
    var invalid = false;
    for (diags.list.items) |m| {
        if (m.severity == .note and std.mem.indexOf(u8, m.message, "Character values have been converted to numeric values") != null) converted = true;
        if (m.severity == .note and std.mem.indexOf(u8, m.message, "Invalid numeric data, 'abc'") != null) invalid = true;
    }
    try t.expect(converted and invalid);
}

test "NOTE-invalidnumdataloc: SQL invalid-data NOTE carries the REAL line, never a frozen 0/0 (GH#78)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var lib = Library.init(a);
    // The bad VALUES row sits on line 3, the bad UPDATE on line 4 — the NOTEs
    // must carry those REAL lines via the (L<n>) machinery (no column exists:
    // NOTE-arrayoorlineno), never an in-text "at line 0 column 0."
    try runSql(a, &lib, &diags, "proc sql;\n" ++
        " create table t (a num);\n" ++
        " insert into t values ('abc');\n" ++
        " update t set a = 'xyz';\n" ++
        " quit;");
    try t.expect(!diags.hasErrors()); // still NOTEs + missing, never an ERROR
    try t.expect(lib.find("t").?.row(0)[0].isMissing());
    const log = try diags.render();
    try t.expect(std.mem.indexOf(u8, log, "NOTE(L3): Invalid numeric data, 'abc'.\n") != null);
    try t.expect(std.mem.indexOf(u8, log, "NOTE(L4): Invalid numeric data, 'xyz'.\n") != null);
    try t.expect(std.mem.indexOf(u8, log, "(L0") == null);
    try t.expect(std.mem.indexOf(u8, log, "column 0") == null);
}

test "ambiguous unqualified column in a join fails loud (BUG-sqlambigcol)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const da = try a.create(Dataset);
    da.* = Dataset.init(a, "a");
    _ = try da.addColumn("k", .num);
    _ = try da.addColumn("x", .num);
    try da.appendRow(&.{ numV(1), numV(10) });
    try da.appendRow(&.{ numV(2), numV(20) });
    try lib.put("a", da);
    const db = try a.create(Dataset);
    db.* = Dataset.init(a, "b");
    _ = try db.addColumn("k", .num);
    _ = try db.addColumn("y", .num);
    try db.appendRow(&.{ numV(2), numV(200) });
    try db.appendRow(&.{ numV(3), numV(300) });
    try lib.put("b", db);

    // bare `k` is in BOTH tables → ambiguous → loud ERROR, no output table
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; create table bad as select k from a full join b on a.k=b.k; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expect(lib.find("bad") == null);
    var named = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "Ambiguous reference") != null and std.mem.indexOf(u8, m.message, "k") != null) {
            named = true;
        };
    try t.expect(named);

    // PRECISION, all legal — no error:
    // coalesced (qualified) full join keeps every key
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2, "proc sql; create table ok1 as select coalesce(a.k,b.k) as k from a full join b on a.k=b.k; quit;");
    try t.expect(!d2.hasErrors());
    try t.expectEqual(@as(usize, 3), lib.find("ok1").?.rowCount());
    // `x` is in exactly ONE table → unqualified is fine
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table ok2 as select x from a join b on a.k=b.k; quit;");
    try t.expect(!d3.hasErrors());
    // single-table bare column: never ambiguous
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table ok3 as select k from a; quit;");
    try t.expect(!d4.hasErrors());
    try t.expectEqual(@as(usize, 2), lib.find("ok3").?.rowCount());
}

test "nested summary functions fail loud (BUG-sqlnestedagg)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "t");
    _ = try d.addColumn("v", .num);
    _ = try d.addColumn("aa", .num);
    _ = try d.addColumn("bb", .num);
    try d.appendRow(&.{ numV(5), numV(1), numV(2) });
    try d.appendRow(&.{ numV(10), numV(3), numV(4) });
    try lib.put("t", d);

    // sum(max(v)) — an aggregate nested in an aggregate → loud ERROR (was 15)
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; create table bad as select sum(max(v)) from t; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expect(lib.find("bad") == null);
    var nested = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "nested in this fashion") != null) {
            nested = true;
        };
    try t.expect(nested);

    // non-nested aggregates unaffected: sum(v)=15, max(v)=10, sum(aa*bb)=14
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2, "proc sql; create table ok as select sum(v) as s, max(v) as m, sum(aa*bb) as p from t; quit;");
    try t.expect(!d2.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqual(@as(f64, 15), ok.row(0)[0].num);
    try t.expectEqual(@as(f64, 10), ok.row(0)[1].num);
    try t.expectEqual(@as(f64, 14), ok.row(0)[2].num);
}

test "summary function in WHERE fails loud; HAVING + plain WHERE still filter (BUG-sqlaggwherefilter)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "t");
    _ = try d.addColumn("v", .num);
    try d.appendRow(&.{numV(3)});
    try d.appendRow(&.{numV(9)});
    try d.appendRow(&.{numV(30)});
    try lib.put("t", d);

    // `where v > sum(v)/3` — a summary function in WHERE → loud ERROR (was: dropped
    // the filter, kept all rows since sum(v) dispatched as the per-row DATA-step SUM).
    var d1 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d1, "proc sql; create table bad as select * from t where v > sum(v)/3; quit;") catch {};
    try t.expect(d1.hasErrors());
    try t.expect(lib.find("bad") == null);
    var loud = false;
    for (d1.list.items) |m|
        if (m.severity == .err and std.mem.indexOf(u8, m.message, "not allowed in the WHERE clause") != null) {
            loud = true;
        };
    try t.expect(loud);

    // `where v >= max(v)` too (was: max(v) → v, so v>=v kept every row).
    var d2 = diag.Diagnostics.init(a);
    runSql(a, &lib, &d2, "proc sql; create table bad2 as select * from t where v >= max(v); quit;") catch {};
    try t.expect(d2.hasErrors());
    try t.expect(lib.find("bad2") == null);

    // the SAME logic via HAVING is legal: only the max row survives.
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table hi as select v from t having v >= max(v); quit;");
    try t.expect(!d3.hasErrors());
    const hi = lib.find("hi").?;
    try t.expectEqual(@as(usize, 1), hi.rows.items.len);
    try t.expectEqual(@as(f64, 30), hi.row(0)[0].num);

    // a plain non-aggregate WHERE still filters per-row (v > 5 → 9, 30).
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table lo as select v from t where v > 5; quit;");
    try t.expect(!d4.hasErrors());
    const lo = lib.find("lo").?;
    try t.expectEqual(@as(usize, 2), lo.rows.items.len);

    // a subquery's own aggregate is fine (exprHasAgg skips it); multi-arg max(a,b) too.
    var d5 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d5, "proc sql; create table sq as select v from t where v >= (select max(v) from t); quit;");
    try t.expect(!d5.hasErrors());
    try t.expectEqual(@as(usize, 1), lib.find("sq").?.rows.items.len);
}

test "TITLE: unquoted text sets the line, does not clear; n>10 fails loud (BUG-titleopts-tick269 F1/F5)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var g = Titles{};

    const tok = struct {
        fn go(al: std.mem.Allocator, dg: *diag.Diagnostics, src: []const u8) ![]Token {
            return lex.tokenize(al, src, dg);
        }
    }.go;

    // A quoted title sets slot 1.
    try t.expect(try g.set(a, &d, try tok(a, &d, "title \"KEEPME\";")));
    try t.expect(std.mem.eql(u8, g.titles[0].?, "KEEPME"));

    // F1: an UNQUOTED title SETS the line (must not silently clear to nothing).
    try t.expect(try g.set(a, &d, try tok(a, &d, "title Hello World;")));
    try t.expect(std.mem.eql(u8, g.titles[0].?, "Hello World"));

    // Bare `title;` still cancels (no tokens past the keyword → cancel form).
    try t.expect(try g.set(a, &d, try tok(a, &d, "title;")));
    try t.expect(g.titles[0] == null);

    // Unquoted FOOTNOTE sets too.
    try t.expect(try g.set(a, &d, try tok(a, &d, "footnote Bottom Line;")));
    try t.expect(std.mem.eql(u8, g.footnotes[0].?, "Bottom Line"));

    // F5: n outside 1..10 fails LOUD (was silently dropped).
    try t.expect(!d.hasErrors());
    try t.expect(try g.set(a, &d, try tok(a, &d, "title11 'x';")));
    try t.expect(d.hasErrors());
}

test "BUG-byvaltitle: #BYVAL/#BYVAR substitute per BY context; unresolvable stays literal" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var g = Titles{};
    const bvs = [_]Titles.ByVar{
        .{ .name = "g", .label = "Treatment Group", .value = "A" },
        .{ .name = "site", .label = "site", .value = "01" },
    };
    // name form (case-insensitive), label for #BYVAR, positional #BYVALn/#BYVARn.
    g.titles[0] = "Group: #byval(g) / #BYVAR(g)";
    g.titles[1] = "first=#byval1 second=#BYVAR2";
    // unknown var / out-of-range position stay literal (SAS no-BY behavior).
    g.footnotes[0] = "lit #byval(nope) #byval7 #byvalue end";
    try t.expect(g.hasBySubst());
    var out: std.ArrayList(u8) = .empty;
    try g.emitTitlesBy(a, &out, &bvs);
    try t.expectEqualStrings("Group: A / Treatment Group\nfirst=A second=site\n", out.items);
    out.clearRetainingCapacity();
    try g.emitFootnotesBy(a, &out, &bvs);
    try t.expectEqualStrings("lit #byval(nope) #byval7 #byvalue end\n", out.items);
    // A line without a token is not a subst line and passes through untouched.
    var g2 = Titles{};
    g2.titles[0] = "plain title";
    try t.expect(!g2.hasBySubst());
    try t.expectEqualStrings("plain title", try substByLine(a, g2.titles[0].?, &bvs));
}

test "BUG-sqlsumwgtcharzero: character argument to a numeric summary aggregate fails loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "t");
    _ = try d.addColumn("b", .char);
    _ = try d.addColumn("x", .num);
    try d.appendRow(&.{ strV("ab"), numV(1) });
    try d.appendRow(&.{ strV("cd"), numV(2) });
    try lib.put("t", d);

    const am = try a.create(Dataset);
    am.* = Dataset.init(a, "am");
    _ = try am.addColumn("x", .num);
    try am.appendRow(&.{Value.missing});
    try am.appendRow(&.{Value.missing});
    try lib.put("am", am);

    // char COLUMN to every numeric summary aggregate → loud ERROR (was 0 for
    // SUMWGT, missing for the rest — both silent); the message names the fn.
    inline for (.{ "sumwgt", "sum", "avg", "std", "css", "uss", "range", "median", "t", "stderr", "cv", "var" }) |fname| {
        var dd = diag.Diagnostics.init(a);
        runSql(a, &lib, &dd, "proc sql; create table bad as select " ++ fname ++ "(b) as v from t; quit;") catch {};
        try t.expect(dd.hasErrors());
        try t.expect(lib.find("bad") == null);
        var loud = false;
        for (dd.list.items) |m|
            if (m.severity == .err and std.mem.indexOf(u8, m.message, "requires a numeric argument") != null) {
                loud = true;
            };
        try t.expect(loud);
    }

    // char EXPRESSION (no declared type to check) → same loud ERROR
    var de = diag.Diagnostics.init(a);
    runSql(a, &lib, &de, "proc sql; select sumwgt(upcase(b)) as sw from t; quit;") catch {};
    try t.expect(de.hasErrors());

    // type-agnostic / lexical aggregates on the char column stay legal
    var d2 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d2, "proc sql; create table ok as select n(b) as nn, nmiss(b) as nm, count(b) as c, min(b) as mn, max(b) as mx from t; quit;");
    try t.expect(!d2.hasErrors());
    const ok = lib.find("ok").?;
    try t.expectEqual(@as(f64, 2), ok.row(0)[0].num);
    try t.expectEqual(@as(f64, 0), ok.row(0)[1].num);
    try t.expectEqual(@as(f64, 2), ok.row(0)[2].num);
    try t.expectEqualStrings("ab", ok.row(0)[3].str);
    try t.expectEqualStrings("cd", ok.row(0)[4].str);

    // numerics untouched: sumwgt(x)=2 / sum(x)=3, and the all-missing NUMERIC
    // cell stays SUMWGT=0 / SUM=missing (9bc08694, doc-correct) with no error.
    var d3 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d3, "proc sql; create table ctl as select sumwgt(x) as sw, sum(x) as s from t; quit;");
    try t.expect(!d3.hasErrors());
    const ctl = lib.find("ctl").?;
    try t.expectEqual(@as(f64, 2), ctl.row(0)[0].num);
    try t.expectEqual(@as(f64, 3), ctl.row(0)[1].num);
    var d4 = diag.Diagnostics.init(a);
    try runSql(a, &lib, &d4, "proc sql; create table amiss as select n(x) as nn, sumwgt(x) as sw, sum(x) as s, std(x) as sd from am; quit;");
    try t.expect(!d4.hasErrors());
    const amiss = lib.find("amiss").?;
    try t.expectEqual(@as(f64, 0), amiss.row(0)[0].num);
    try t.expectEqual(@as(f64, 0), amiss.row(0)[1].num); // SUMWGT=0 — must NOT regress
    try t.expect(amiss.row(0)[2].isMissing());
    try t.expect(amiss.row(0)[3].isMissing());
}

test "GAP-sqlsortseqlinguistic: ORDER BY honours SORTSEQ=LINGUISTIC; statement option beats system; loud otherwise" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    // the system option is a process global — restore it, like main.zig's rc
    // test and the BUG-optionsstmtswallow test do.
    defer io.global_sortseq_linguistic = false;

    const d = try a.create(Dataset);
    d.* = Dataset.init(a, "t");
    _ = try d.addColumn("name", .char);
    for ([_][]const u8{ "Zebra", "apple", "Banana" }) |s| try d.appendRow(&.{strV(s)});
    try lib.put("t", d);

    const H = struct { // run one query into table `o` and read its column top to bottom
        fn order(al: std.mem.Allocator, l: *Library, src: []const u8, want: []const []const u8) !void {
            var dd = diag.Diagnostics.init(al);
            try runSql(al, l, &dd, src);
            try t.expect(!dd.hasErrors());
            const got = l.find("o").?;
            try t.expectEqual(want.len, got.rows.items.len);
            for (want, 0..) |w, i| try t.expectEqualStrings(w, got.row(i)[0].str);
        }
    };
    const ling = [_][]const u8{ "apple", "Banana", "Zebra" }; // case-folded dictionary
    const ascii = [_][]const u8{ "Banana", "Zebra", "apple" }; // every upper before any lower

    // 1. SYSTEM option only — p.2403's Note / p.261 "PROC SQL honors the setting".
    io.global_sortseq_linguistic = true;
    try H.order(a, &lib, "proc sql; create table o as select name from t order by name; quit;", &ling);
    // 2. STATEMENT option only (system explicitly ASCII) — p.45, added in 9.4M3.
    io.global_sortseq_linguistic = false;
    try H.order(a, &lib, "proc sql sortseq=linguistic; create table o as select name from t order by name; quit;", &ling);
    // 3. PRECEDENCE, the direction that PROVES the rule instead of agreeing with
    //    it by accident: p.261 says the statement option overrides the system
    //    option, so ASCII must win over a system LINGUISTIC.
    io.global_sortseq_linguistic = true;
    try H.order(a, &lib, "proc sql sortseq=ascii; create table o as select name from t order by name; quit;", &ascii);
    // 4. RESET carries it mid-step; 5. neither set → the ASCII default.
    io.global_sortseq_linguistic = false;
    try H.order(a, &lib, "proc sql; reset sortseq=linguistic; create table o as select name from t order by name; quit;", &ling);
    try H.order(a, &lib, "proc sql; create table o as select name from t order by name; quit;", &ascii);

    // p.45: "SORTSEQ= affects only the ORDER BY clause. It does not override
    // your operating environment's default comparison operations for the WHERE
    // clause." WHERE compares through eval.zig rather than cmpVal, so this
    // asserts the guarantee rather than guarding this change — the surfaces a
    // cmpVal leak would actually break are DISTINCT and GROUP BY, held by
    // tests/corpus/sql_sortseq_scope.sas.
    io.global_sortseq_linguistic = true;
    var dw = diag.Diagnostics.init(a);
    try runSql(a, &lib, &dw, "proc sql; create table w as select name from t where name = \"APPLE\"; quit;");
    try t.expectEqual(@as(usize, 0), lib.find("w").?.rows.items.len); // NOT folded → no match

    // Loud arms. A documented-but-unimplemented collation is a GAP (markGap,
    // rc 2); an unknown OPTION NAME keeps the pre-existing rc-1 user error.
    io.global_sortseq_linguistic = false;
    inline for (.{
        .{ "sortseq=ebcdic", "SORTSEQ= collation other than ASCII/LINGUISTIC is not supported" },
        .{ "sortseq=mytable", "SORTSEQ= collation other than ASCII/LINGUISTIC is not supported" },
        .{ "sortseq=linguistic(strength=2)", "SORTSEQ=LINGUISTIC(...) collating options are not supported" },
    }) |c| {
        var dg = diag.Diagnostics.init(a);
        runSql(a, &lib, &dg, "proc sql " ++ c[0] ++ "; select name from t; quit;") catch {};
        try t.expect(dg.hasErrors());
        try t.expect(std.mem.indexOf(u8, try dg.render(), c[1]) != null);
    }
    var dt = diag.Diagnostics.init(a);
    runSql(a, &lib, &dt, "proc sql sortseqq=x; select name from t; quit;") catch {};
    try t.expect(std.mem.indexOf(u8, try dt.render(), "unrecognized option sortseqq") != null);
}
