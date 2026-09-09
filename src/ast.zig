//! AST for the SAS DATA step — the parser↔exec contract.
//!
//! Pure data. Nodes carry arena-allocated children (`*const Expr`, slices) and
//! nothing else: no methods that evaluate, no ownership/`deinit`. The parser
//! (Track A) allocates every node into one arena and hands back a `Program`;
//! the executor (Track C) walks it and drops the whole arena at once. That is
//! why children are `const` pointers/slices — the tree is immutable once built.
//!
//! Names (variables, functions) are stored verbatim as the lexer produced them.
//! SAS names are case-insensitive; comparison is the consumer's job (PDV /
//! function table), not the AST's — the AST just carries the bytes.
//!
//! This is a frozen M0 contract: it covers the DATA-step surface the parser
//! (A2) and executor (C1) actually name. Anything past that scope is marked
//! `ponytail:` at the node it would touch — add it when the corpus demands it,
//! not before.

const std = @import("std");
const VarType = @import("pdv.zig").VarType;

// ── Expressions ──────────────────────────────────────────────────────────

pub const BinOp = enum {
    // arithmetic
    add, // +
    sub, // -
    mul, // *
    div, // /
    pow, // **  (parser makes this right-assoc; the AST just records it)
    // MIN/MAX operators (SAS Group I): `><` returns the smaller operand, `<>`
    // the larger; a missing value ranks lowest (unlike the min()/max() FUNCTIONS,
    // which ignore missing). Also spelled MIN/MAX infix (GAP-minmaxop).
    min, // ><  MIN
    max, // <>  MAX
    // comparison — SAS yields 1/0, but that is the evaluator's job (B1)
    eq, // =  EQ
    ne, // ^= NE
    lt, // <  LT
    le, // <= LE
    gt, // >  GT
    ge, // >= GE
    // logical
    @"and", // &  AND
    @"or", //  |  OR
    // string
    concat, // ||
};

pub const UnOp = enum {
    neg, // -x
    not, // ^x  NOT x
};

pub const Unary = struct { op: UnOp, operand: *const Expr };
pub const Binary = struct { op: BinOp, lhs: *const Expr, rhs: *const Expr };
pub const Call = struct { name: []const u8, args: []const Expr };

/// An ARRAY declared over a special variable list — `array v{*} _numeric_;`
/// (or `_character_`/`_all_`). Its members can't be known at parse time (the PDV
/// type set is a runtime fact), so the list is resolved against the live PDV at
/// exec time instead of baked into `elements` (GH#48).
pub const SpecialArr = enum { numeric, character, all };

/// `a{i}` — an array element reference. The parser resolves the array name to
/// its element variables at parse time (arrays are declared before use), so the
/// evaluator only needs to index `elements` with the runtime subscript. When the
/// array is a special list (`special != null`) `elements` is empty and the member
/// names are resolved from the live PDV at eval time (GH#48).
pub const ArrayRef = struct { name: []const u8, elements: []const []const u8, index: *const Expr, special: ?SpecialArr = null, line: usize = 0 }; // line = source line of the subscript reference (NOTE-arrayoorlineno); 0 = unknown

pub const Expr = union(enum) {
    num: f64, // numeric literal
    str: []const u8, // 'quoted' / "quoted" char literal
    missing, // lone `.` — the numeric missing literal
    // ponytail: only plain `.`; special missings .A–.Z / ._ when the corpus hits one.
    variable: []const u8, // reference to a PDV variable
    unary: Unary,
    binary: Binary,
    call: Call,
    array_ref: ArrayRef, // a{i}
};

// ── Statements ───────────────────────────────────────────────────────────

pub const Assign = struct { target: []const u8, value: *const Expr };

/// `array a{n} a1-a5 (10 20 …);` — `elements` are the member variables (ranges
/// already expanded, or synthesised for a `_temporary_` array); `inits` are the
/// parenthesised initial values, applied positionally to `elements` (and, like
/// SAS, retained). `temporary` members are kept out of the output dataset.
pub const ArrayDecl = struct {
    name: []const u8,
    elements: []const []const u8,
    inits: []const *const Expr,
    temporary: bool = false,
    type: VarType = .num, // `array a{n} $ …;` → .char members
    special: ?SpecialArr = null, // `array v{*} _numeric_;` — members from the PDV (GH#48)
};

/// `a{i} = expr;` — assignment to an array element (subscripted lvalue).
pub const ArrayAssign = struct { array: ArrayRef, value: *const Expr };

/// `substr(var, pos <, len>) = expr;` — the SUBSTR pseudo-variable: splice `value`
/// into `target`'s char value at [pos, pos+len), leaving the rest untouched.
pub const SubstrAssign = struct { target: []const u8, pos: *const Expr, len: ?*const Expr, value: *const Expr };

/// `if c then s; else s;` — a bare subsetting `if c;` is both branches null.
pub const If = struct {
    cond: *const Expr,
    then_branch: ?*const Stmt,
    else_branch: ?*const Stmt,
};

/// `do i = start to stop by step;`
pub const DoIter = struct {
    name: []const u8,
    start: *const Expr,
    stop: *const Expr,
    by: ?*const Expr, // null → step 1
};

/// One term of a value-list DO: a single value (`stop`/`by` null) or a range.
pub const DoSpec = struct { start: *const Expr, stop: ?*const Expr = null, by: ?*const Expr = null };

pub const DoHeader = union(enum) {
    simple, // do; … end;
    iter: DoIter, // do i = … ; … end;
    while_: *const Expr, // do while (cond);
    until_: *const Expr, // do until (cond);
    list: struct { name: []const u8, specs: []const DoSpec }, // do i = 1, 3, 5; / mixed ranges
};

pub const Do = struct { header: DoHeader, body: []const Stmt };

/// `retain x 0 y;` — optional initial value per name.
pub const RetainItem = struct { name: []const u8, init: ?*const Expr };

/// list input: `input name $;` or `input n :comma8.;`. `informat` is the read
/// format after a `:` modifier (null = plain list input); io.readList applies it.
/// `list_mod` distinguishes the `:informat.` list form (read a whitespace token,
/// then apply the informat) from a plain formatted `$w.`/`w.` informat (read the
/// full fixed width incl. embedded blanks) — same spec string, different reader
/// (DATALINES-informat). ponytail: column ranges encoded as `@s-e` in informat.
pub const InputItem = struct {
    name: []const u8,
    type: VarType,
    informat: ?[]const u8 = null,
    list_mod: bool = false,
    // GAP-inputarrayelem: `input v{i}` — an array-element target. `name` is ""
    // on such items (the array's own name is not a PDV column — its elements
    // are, via the ARRAY statement); the reader resolves the flat subscript
    // `arr_index` against `arr_elements` per read (a DO-loop index changes
    // every iteration), then reads the element as a plain var.
    arr_index: ?*const Expr = null,
    arr_elements: []const []const u8 = &.{},
    arr_name: []const u8 = &.{}, // the array's own name, for diagnostics
    // GAP-atexpression: `@(expression)` column pointer (Statements printed
    // p.168: 'moves the pointer to the column that is given by the value of
    // expression'). A nameless pointer item like `@n`, but the operand AST
    // rides the item and io.zig evaluates it PER READ against the PDV (a
    // variable computed earlier in the same step moves the pointer — the
    // doc's own example is `b=5; input @(b*3) name $10.;`), routing the value
    // through the SAME clamp as `@n`/`@var` (zero/negative → column 1).
    col_expr: ?*const Expr = null,
    // NOTE-inputinvalidnote: the `?`/`??` error-suppression modifier count
    // (0/1/2) — 1 suppresses the invalid-data NOTE, 2 also suppresses _ERROR_=1.
    suppress: u2 = 0,
};

/// one item of a `put` list.
/// ponytail: `@n` and `@(expr)` column pointers supported; a trailing `@`/`@@`
/// output-line hold is not (parser fails loud on it).
pub const PutItem = union(enum) {
    variable: struct { name: []const u8, fmt: ?[]const u8 = null }, // a value, optional format (`put x 8.2`)
    literal: []const u8, // put a quoted string
    col: usize, // `@n` — move the output column pointer to column n (1-based)
    // GAP-atexpression-put: `@(expression)` — the same column pointer as `col`,
    // but the operand AST rides the item and exec evaluates it PER PUT against
    // the PDV (Statements printed p.269: 'moves the pointer to the column that
    // is given by the value of expression'; the doc's own example is
    // `b=5; put @(b*3) name $10.;`). The value routes through io.clampCol —
    // the SAME clamp `@n`/`@var`/INPUT's `@(expr)` use.
    col_expr: *const Expr,
    newline, // `/`
    named: struct { name: []const u8, fmt: ?[]const u8 = null }, // `x=` / `x= fmt.` — named output, prints "x=<value>"
    // `put a[i]` / `put a[*]` — an array element (runtime index) or the whole array
    // (index null → every element) (BUG-putarrayref). `named` = `put a[i]=;` —
    // named output, prints "<element-name>=<value>" (FEAT-putarraynamed).
    array_elem: struct { name: []const u8, elements: []const []const u8, index: ?*const Expr, special: ?SpecialArr = null, named: bool = false },
};

/// one `var → format` pairing from a `format`/`informat` statement.
pub const FormatItem = struct { name: []const u8, fmt: []const u8 };

/// one `old = new` pairing from a statement-form `rename old=new …;`.
pub const RenamePair = struct { old: []const u8, new: []const u8 };

/// INFILE record-boundary option (BUG-infilemissover). SAS 9.4: these "control
/// what happens when an INPUT statement reaches the end of the current record."
/// flowover (default) fetches the next record for more values; missover/truncover
/// set the remaining variables missing (truncover keeps a partial last field);
/// stopover raises an error.
pub const OverflowMode = enum { flowover, missover, truncover, stopover };

/// `infile "path" [dlm=x] [dsd] [firstobs=n] [missover|truncover|stopover|flowover] [pad];`
/// — read an external text file, one line per DATA-step iteration, parsed by the
/// following `input`.
pub const Infile = struct {
    path: []const u8,
    dlm: ?[]const u8 = null, // delimiter SET — each byte is an independent single-char delimiter (null → whitespace, SAS default). DLM='|;' splits on '|' AND ';' (BUG-dlmmultichar).
    dsd: bool = false, // quoted fields; consecutive delimiters → missing
    firstobs: usize = 1, // 1-based first line to read (skips a header)
    inline_data: bool = false, // path is a DATALINES/CARDS device → read the embedded block, not a file
    overflow: OverflowMode = .flowover, // record-boundary behavior (BUG-infilemissover)
    // (BUG-infilepadinert: the `pad` field lived here, parsed-stored-never-read.
    // PAD now takes parser.zig's loud unsupported-option path, so nothing writes
    // or reads it — removed rather than left as a field that looks implemented.)
    end_var: ?[]const u8 = null, // END=name → temp var, 1 when the current read consumes the last record (FEAT-infileend)
    obs: ?usize = null, // OBS=n → last record number read (absolute, 1-based; FEAT-infileobslinesize)
    linesize: ?usize = null, // LINESIZE=/LS=n → truncate each record to n columns (FEAT-infileobslinesize)
};

/// `file "path" [dlm=x] [dsd];` — external text output destination for `put`.
/// DLM sets the list-item separator (null → blank, the SAS default); DSD
/// implies dlm=',' when unset and quotes values containing the delimiter.
pub const File = struct {
    path: []const u8,
    dlm: ?u8 = null,
    dsd: bool = false,
    /// GAP-fileprint: an UNQUOTED `file print;`/`file log;` keyword — PUT routes
    /// to the normal output (listing/log are one stdout stream here, main.zig),
    /// no external file is written. A QUOTED "print"/"log" stays external.
    print_log: bool = false,
};

/// One argument to a hash method: `key: 1` (named) or `"k"` (positional, name null).
pub const HashArg = struct { name: ?[]const u8, value: *const Expr };

/// `declare hash h(dataset:"x");` — a hash-object declaration.
pub const HashDecl = struct { name: []const u8, args: []const HashArg };

/// `h.method(args);` or `rc = h.method(args);` — a hash-object method call.
/// `target` is the optional `rc` variable that receives the return code.
/// Hash ops are statements (not expressions), so the evaluator never sees them.
pub const HashCall = struct { target: ?[]const u8, obj: []const u8, method: []const u8, args: []const HashArg };

pub const Stmt = union(enum) {
    assign: Assign,
    array_assign: ArrayAssign, // `a{i} = expr;`
    substr_assign: SubstrAssign, // `substr(v,p,n) = expr;`
    if_: If,
    do_: Do,
    output: []const []const u8, // `output;` → empty slice = the implicit dataset
    drop: []const []const u8,
    keep: []const []const u8,
    rename: []const RenamePair, // `rename a=b c=d;` — rename output vars (statement form)
    retain: []const RetainItem,
    set: []const []const u8, // `set a b;` → prior datasets, in order
    merge: []const []const u8, // `merge a b;` → match-merge sources (paired with `by`)
    update: []const []const u8, // `update master trans;` → master + transaction, keyed by `by`
    modify: []const []const u8, // `modify ds [trans];` → in-place update of a dataset
    array: ArrayDecl, // `array a{n} v1-vn (inits);`
    by: []const []const u8, // `by dept;` → BY-group vars (input assumed sorted)
    datalines: []const []const u8, // raw inline data lines, verbatim
    input: []const InputItem,
    put: []const PutItem,
    format: []const FormatItem, // `format x 8.2 y date9.;` — display formats
    informat: []const FormatItem, // `informat …;` — read formats (parsed; input-side)
    hash_decl: HashDecl, // `declare hash h(...);`
    hash_op: HashCall, // `h.method(...);` / `rc = h.method(...);`
    call_: Call, // `call routine(args);` — a CALL statement (reuses the Call node)
    infile: Infile, // `infile "path" …;` — external text input source
    file: File, // `file "path" …;` — external text output destination for `put`
    where_: *const Expr, // `where expr;` — ENGINE-level input filter: applied pre-read, so end=/first./last. see the filtered stream (unlike a subsetting if)
    delete, // `delete;` — drop the current obs and return to the top of the step
    null_stmt, // lone `;` — the SAS null statement, a no-op (PARSE-nullstmt)
    stop, // `stop;` — terminate the DATA step immediately
    abort: AbortArg, // `abort [abend [n]|return n|n];` — plain ends the step w/ _ERROR_=1; the rest halt the session with an exit rc (BUG-abortreturncode)
    continue_, // `continue;` — skip to the next iteration of the enclosing DO loop
    leave, // `leave;` — exit the enclosing DO loop
    return_, // `return;` — implicit output (or return from a LINK), then top of step
    label: []const u8, // `name:` — a statement label (a GOTO/LINK target)
    goto: []const u8, // `goto name;` — jump to the labeled statement
    link: []const u8, // `link name;` — call the labeled block; `return;` comes back
    select_nomatch, // terminal else of a selector SELECT with no OTHERWISE — fail LOUD if reached (BUG-selectnomatch)
};

/// The parser's output: the statement stream inside one DATA step. The
pub const AbortArg = union(enum) {
    plain, // `abort;` — end the DATA step now, _ERROR_=1 (like STOP)
    abend: ?u8, // `abort abend [n];` — halt the whole session, rc = n (default 1)
    n: u8, // `abort return n;` / `abort n;` — halt the whole session, rc = n
};

/// The parser's output: the statement stream inside one DATA step. The
/// `data … ; … run;` framing (output dataset name, step boundary) is the
/// executor's concern — A2's statement list stops at `data`/`run`.
pub const Program = []const Stmt;

test "hand-build and walk `x = a + 1;`" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const lhs = try a.create(Expr);
    lhs.* = .{ .variable = "a" };
    const rhs = try a.create(Expr);
    rhs.* = .{ .num = 1 };
    const sum = try a.create(Expr);
    sum.* = .{ .binary = .{ .op = .add, .lhs = lhs, .rhs = rhs } };

    const s: Stmt = .{ .assign = .{ .target = "x", .value = sum } };

    try std.testing.expectEqualStrings("x", s.assign.target);
    try std.testing.expect(s.assign.value.binary.op == .add);
    try std.testing.expectEqualStrings("a", s.assign.value.binary.lhs.variable);
    try std.testing.expectEqual(@as(f64, 1), s.assign.value.binary.rhs.num);
}

test "missing literal, subsetting if, and a call with args" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // `sum(x, .)` — a call whose second arg is the missing literal.
    const args = try a.alloc(Expr, 2);
    args[0] = .{ .variable = "x" };
    args[1] = .missing;
    const cond = try a.create(Expr);
    cond.* = .{ .call = .{ .name = "sum", .args = args } };

    // subsetting `if sum(x, .);` — both branches null.
    const s: Stmt = .{ .if_ = .{ .cond = cond, .then_branch = null, .else_branch = null } };

    try std.testing.expect(s.if_.then_branch == null);
    try std.testing.expectEqualStrings("sum", s.if_.cond.call.name);
    try std.testing.expectEqual(@as(usize, 2), s.if_.cond.call.args.len);
    try std.testing.expect(s.if_.cond.call.args[1] == .missing);
}
