//! Lexer — SAS source → `Token` stream. The rebuilt original (it was lost
//! before ever being committed; see L1). This file OWNS the `Token`/`Tag`
//! contract: it was seeded in `parser_expr.zig` while no lexer existed and is
//! hoisted here now that one does. Both the lexer and the parser share it, and
//! a later statement lexer extends it.
//!
//! SAS names are case-insensitive; the lexer emits their bytes verbatim and
//! leaves folding to the consumer (the parser's mnemonic check, the PDV). The
//! word operators AND/OR/NOT/EQ/… are emitted as `.name` on purpose — the
//! parser classifies them, so the lexer needs no keyword table.
//!
//! Scope: literals, names, `( ) ,`, arithmetic, comparisons (symbolic +
//! `^=`/`~=` + the legacy `=<`/`=>` spellings of LE/GE), `**`, `|| & |`,
//! `^`/`~` (NOT), plus the statement tokens `;`,
//! `$`, `:` (input informat modifier) and a `datalines`/`cards` raw-line mode
//! (A2). `/* */` comments are skipped.
//! ponytail: no `''` in-string escape — add when the corpus hits it.

const std = @import("std");
const diag = @import("diag.zig");
const eval = @import("eval.zig"); // typed-constant value conversions ('…'d/t/dt/b/x)

pub const Error = diag.Error;

pub const Tag = enum {
    number, // numeric literal; `text` is the source digits
    string, // char literal; `text` is the content, quotes already stripped
    name, // identifier: variable, function, or mnemonic op (EQ/AND/…)
    dot, // lone `.` → the numeric-missing literal
    lparen,
    rparen,
    comma,
    plus,
    minus,
    star, // *
    slash, // /
    star2, // **
    eq, // =
    ne, // ^= ~=
    lt, // <
    le, // <=
    gt, // >
    ge, // >=
    min_op, // ><  MIN operator (SAS Group I)
    max_op, // <>  MAX operator
    concat, // ||
    amp, // &
    pipe, // |
    caret, // ^ / ~  (lone NOT prefix; `^=`/`~=` is `ne`). `text` carries the
    // source byte so a consumer can tell `~` from `^` (PUT's modifier slot).
    semicolon, // ;  statement terminator
    dollar, // $  (char marker in `input`)
    colon, // :  (informat modifier in `input`)
    at, // @  column pointer in `input` (@col); trailing @ holds the line
    atat, // @@ double-trailing hold
    hash, // #  line pointer in `input` (#n)
    question, // ?  INPUT error-suppression modifier (`input(x, ?? best.)`); `??` is two of these
    lbrace, // {  array dimension / subscript
    rbrace, // }
    data_line, // one raw line of a `datalines`/`cards` block; `text` is verbatim
    eof,
};

pub const Token = struct {
    tag: Tag,
    text: []const u8 = "",
    /// 1-based source line, for diagnostics.
    line: usize = 0,
};

/// Tokenize `src` into an arena-allocated slice that always ends with `.eof`
/// (so parsers can `peek` without a bounds check). Lex errors are reported to
/// `diags` and returned as `error.LexError`.
pub fn tokenize(arena: std.mem.Allocator, src: []const u8, diags: *diag.Diagnostics) Error![]Token {
    var out: std.ArrayList(Token) = .empty;
    var line: usize = 1;
    var i: usize = 0;
    while (i < src.len) {
        const c = src[i];
        switch (c) {
            '\n' => {
                line += 1;
                i += 1;
            },
            ' ', '\t', '\r' => i += 1,
            '0'...'9' => i = try lexNumber(arena, &out, src, i, line),
            '.' => {
                if (i + 1 < src.len and isDigit(src[i + 1])) {
                    i = try lexNumber(arena, &out, src, i, line);
                } else if (i + 1 < src.len and (std.ascii.isAlphabetic(src[i + 1]) or src[i + 1] == '_') and !prevIsValue(out.items)) {
                    // special missing `.A`-`.Z` / `._` (only where a value is
                    // expected — a `.` after a value is member access, e.g. `a.b`).
                    // Carry the letter as the `.dot` token's text so it survives
                    // to the parser (member-access dots stay empty-texted).
                    try emit(arena, &out, .dot, src[i + 1 .. i + 2], line);
                    i += 2;
                } else {
                    try emit(arena, &out, .dot, "", line);
                    i += 1;
                }
            },
            'a'...'z', 'A'...'Z', '_' => {
                const start = i;
                while (i < src.len and (std.ascii.isAlphanumeric(src[i]) or src[i] == '_')) i += 1;
                const text = src[start..i];
                try emit(arena, &out, .name, text, line);
                // `datalines;`/`cards;`/`lines;` switches to raw-line capture:
                // the block's bytes are data, not SAS tokens. But ONLY when it
                // begins a statement — the token before it is `;` (or it is the
                // first token). When `datalines` instead FOLLOWS another token
                // (`infile datalines;` device ref, or a var named datalines) it
                // is not a raw block, so don't switch to raw capture, which would
                // swallow the rest of the step (BUG-infiledatalines).
                if (isDatalinesKw(text) and (out.items.len < 2 or out.items[out.items.len - 2].tag == .semicolon)) {
                    var j = i;
                    while (j < src.len and (src[j] == ' ' or src[j] == '\t')) j += 1;
                    if (j < src.len and src[j] == ';') i = try lexDatalines(arena, &out, src, j, &line, isDatalines4Kw(text));
                }
            },
            ';' => {
                try emit(arena, &out, .semicolon, "", line);
                i += 1;
            },
            '$' => {
                try emit(arena, &out, .dollar, "", line);
                i += 1;
            },
            ':' => {
                try emit(arena, &out, .colon, "", line);
                i += 1;
            },
            // `[`/`]` are array-subscript delimiters, interchangeable with `{`/`}` in
            // SAS (`array a[n]`, `a[i]`) — the only DATA-step use of brackets, so
            // alias them to the brace tokens (BUG-arraybracket).
            '{', '[' => {
                try emit(arena, &out, .lbrace, "", line);
                i += 1;
            },
            '}', ']' => {
                try emit(arena, &out, .rbrace, "", line);
                i += 1;
            },
            '\'', '"' => i = try lexString(arena, &out, src, i, line, diags),
            '*' => {
                // A `*` in STATEMENT position begins a comment statement that runs
                // to the next `;` (SAS `* … ;`). Statement position = file start or
                // right after a `;`. Anywhere else `*`/`**` are the multiply/power
                // operators (lexOp). ponytail: `;`-boundary only, and the content is
                // consumed raw (so apostrophes / `&` / `%` inside don't lex) — widen
                // the boundary set if the corpus needs it.
                if (out.items.len == 0 or out.items[out.items.len - 1].tag == .semicolon) {
                    while (i < src.len and src[i] != ';') : (i += 1) {
                        if (src[i] == '\n') line += 1;
                    }
                    if (i < src.len) i += 1; // consume the terminating ';'
                } else i = try lexOp(arena, &out, src, i, line, diags);
            },
            '/' => {
                if (i + 1 < src.len and src[i + 1] == '*') {
                    i = try skipComment(src, i, &line, diags);
                } else {
                    try emit(arena, &out, .slash, "", line);
                    i += 1;
                }
            },
            else => i = try lexOp(arena, &out, src, i, line, diags),
        }
    }
    try emit(arena, &out, .eof, "", line);
    return out.toOwnedSlice(arena);
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn emit(arena: std.mem.Allocator, out: *std.ArrayList(Token), tag: Tag, text: []const u8, line: usize) Error!void {
    try out.append(arena, .{ .tag = tag, .text = text, .line = line });
}

/// Digits, an optional decimal point, and an optional `e[+/-]NN` exponent. The
/// lexer is deliberately permissive — a malformed number (`1.2.3`) is caught by
/// the parser's `parseFloat`, which owns the numeric error message.
fn lexNumber(arena: std.mem.Allocator, out: *std.ArrayList(Token), src: []const u8, start: usize, line: usize) Error!usize {
    // SAS numeric hex constant: a decimal digit, then 0-15 more hex digits (16
    // total max), immediately followed by `x`/`X` — e.g. `0fx`=15, `9x`=9,
    // `0b0ax` (Language Reference: Concepts, "Numeric Constants Expressed in Hexadecimal Notation").
    // lexNumber only fires on a leading digit 0-9, so `Fx`/`max`/`xx` stay names.
    // Tried before decimal lexing, but `1.5`/`1e5`/`123` fall through (no trailing
    // x). Guarded so a hex run continued by an ident char (`0fxy`) is not silently
    // truncated — fall through and let the parser fail loud.
    {
        var h = start;
        while (h < src.len and std.ascii.isHex(src[h])) h += 1;
        const ndig = h - start;
        if (h < src.len and (src[h] == 'x' or src[h] == 'X') and ndig >= 1 and ndig <= 16 and
            !(h + 1 < src.len and (std.ascii.isAlphanumeric(src[h + 1]) or src[h + 1] == '_')))
        {
            const v = std.fmt.parseInt(u64, src[start..h], 16) catch unreachable;
            return emitNum(arena, out, @floatFromInt(v), line, h + 1);
        }
    }
    var i = start;
    while (i < src.len and (isDigit(src[i]) or src[i] == '.')) i += 1;
    if (i < src.len and (src[i] == 'e' or src[i] == 'E')) {
        i += 1;
        if (i < src.len and (src[i] == '+' or src[i] == '-')) i += 1;
        while (i < src.len and isDigit(src[i])) i += 1;
    }
    try emit(arena, out, .number, src[start..i], line);
    return i;
}

/// `'…'` or `"…"`. `text` is the content between the quotes.
/// ponytail: no `''`/`""` embedded-quote escape yet.
fn lexString(arena: std.mem.Allocator, out: *std.ArrayList(Token), src: []const u8, open: usize, line: usize, diags: *diag.Diagnostics) Error!usize {
    const quote = src[open];
    const start = open + 1;
    var i = start;
    var escaped = false; // a doubled quote (`''` / `""`) stands for one quote char
    while (i < src.len) {
        if (src[i] == quote) {
            if (i + 1 < src.len and src[i + 1] == quote) {
                escaped = true;
                i += 2; // consume both halves of the doubled quote
                continue;
            }
            break; // a lone quote closes the literal
        }
        i += 1;
    }
    if (i >= src.len) return diags.fail(error.LexError, line, "unterminated string literal", .{});
    const raw = src[start..i];
    // Only allocate when there is something to collapse; the common case borrows
    // the source slice as before.
    const body = if (escaped) try collapseQuotes(arena, raw, quote) else raw;

    // A type suffix immediately after the closing quote makes this a typed
    // constant: 'x'd date, 'x't time, 'x'dt datetime, 'x'b bit, 'x'x hex bytes,
    // 'x'n name literal. Read the letter run and match a known suffix.
    var e = i + 1;
    while (e < src.len and std.ascii.isAlphabetic(src[e])) e += 1;
    const suffix = src[i + 1 .. e];
    if (suffix.len > 0) {
        const eqi = std.ascii.eqlIgnoreCase;
        if (eqi(suffix, "n")) { // name literal → an identifier token
            try emit(arena, out, .name, body, line);
            return e;
        } else if (eqi(suffix, "x")) {
            if (eval.hexConst(arena, body)) |bytes| {
                try emit(arena, out, .string, bytes, line);
                return e;
            }
        } else if (eqi(suffix, "d")) {
            if (eval.dateConst(body)) |v| return try emitNum(arena, out, v, line, e);
        } else if (eqi(suffix, "t")) {
            if (eval.timeConst(body)) |v| return try emitNum(arena, out, v, line, e);
        } else if (eqi(suffix, "dt")) {
            if (eval.datetimeConst(body)) |v| return try emitNum(arena, out, v, line, e);
        } else if (eqi(suffix, "b")) {
            if (eval.bitConst(body)) |v| return try emitNum(arena, out, v, line, e);
        }
        // unknown suffix or a malformed body → fall through to a plain string
    }
    // SAS char constants are NEVER zero-length: a quoted empty literal `''`/`""`
    // is a SINGLE BLANK, not a zero-length string (SAS 9.4 Fns Ref, TRANSTRN
    // p.1577). Only TRIMN('') — computed, not lexed — yields zero-length. Fixing
    // it here, at the one point a quoted literal is materialized, keeps computed
    // empties (trimn/substr/empty columns) and the parser's synthesized
    // omitted-arg `.str=""` genuinely zero-length. GH#60.
    try emit(arena, out, .string, if (body.len == 0) " " else body, line);
    return i + 1; // skip the closing quote
}

/// Emit a converted typed-constant as a `.number` token and return the new cursor.
fn emitNum(arena: std.mem.Allocator, out: *std.ArrayList(Token), v: f64, line: usize, next: usize) Error!usize {
    try emit(arena, out, .number, try std.fmt.allocPrint(arena, "{d}", .{v}), line);
    return next;
}

/// True if the last token could end an operand (so a following `.` is member
/// access, not a value-position special missing).
fn prevIsValue(items: []const Token) bool {
    if (items.len == 0) return false;
    const last = items[items.len - 1];
    return switch (last.tag) {
        // A `.name` ends an operand UNLESS it's a value-EXPECTING keyword operator
        // (`if`, `and`, `to`, …): those are lexed as `.name` too but a value must
        // follow, so `if .a` / `x and .b` is a special missing, not `.` + `a`
        // (BUG-specialmiss-afterkw). Member access (`obj.field`, `h.find()`) still
        // follows a real variable name, which is not in this set.
        .name => !isValueExpectingKw(last.text),
        .number, .string, .rparen => true,
        else => false,
    };
}

/// SAS keyword operators / control words that expect a VALUE (expression) to
/// follow. After one of these a leading `.a`-`.z`/`._` is a special-missing
/// literal, never member access.
fn isValueExpectingKw(text: []const u8) bool {
    const eqi = std.ascii.eqlIgnoreCase;
    inline for (.{
        "if",  "then", "else", "and",      "or",   "not",  "until", "while",
        "to",  "by",   "eq",   "ne",       "lt",   "le",   "gt",    "ge",
        "in",  "min",  "max",  "contains", "like",
    }) |kw| {
        if (eqi(text, kw)) return true;
    }
    return false;
}

/// Collapse each doubled quote (`''` or `""`) in `raw` to a single quote char.
fn collapseQuotes(arena: std.mem.Allocator, raw: []const u8, quote: u8) Error![]const u8 {
    const buf = try arena.alloc(u8, raw.len); // result is never longer than the input
    var n: usize = 0;
    var k: usize = 0;
    while (k < raw.len) : (k += 1) {
        buf[n] = raw[k];
        n += 1;
        if (raw[k] == quote and k + 1 < raw.len and raw[k + 1] == quote) k += 1; // skip the second quote
    }
    return buf[0..n];
}

/// Skips a `/* … */` block comment, counting newlines so line numbers stay
/// accurate. Returns the index just past `*/`.
fn skipComment(src: []const u8, open: usize, line: *usize, diags: *diag.Diagnostics) Error!usize {
    var i = open + 2;
    while (i + 1 < src.len) {
        if (src[i] == '*' and src[i + 1] == '/') return i + 2;
        if (src[i] == '\n') line.* += 1;
        i += 1;
    }
    return diags.fail(error.LexError, line.*, "unterminated '/*' comment", .{});
}

fn isDatalinesKw(text: []const u8) bool {
    const eqi = std.ascii.eqlIgnoreCase;
    return eqi(text, "datalines") or eqi(text, "cards") or eqi(text, "lines") or isDatalines4Kw(text);
}

/// DATALINES4/CARDS4: an inline block terminated by `;;;;` on its own line,
/// letting the data itself contain `;`.
fn isDatalines4Kw(text: []const u8) bool {
    const eqi = std.ascii.eqlIgnoreCase;
    return eqi(text, "datalines4") or eqi(text, "cards4");
}

/// Capture a `datalines`/`cards` block: the raw lines after the opening `;` up
/// to a line whose first non-blank byte is `;`. Each data line becomes a
/// `.data_line` token (verbatim, sans trailing `\r`); the opening and
/// terminating `;` are `.semicolon`. `at` indexes the opening `;`. Returns the
/// index just past the terminator (or EOF, if the block is unterminated — the
/// parser's trailing `expect(.semicolon)` reports that).
fn lexDatalines(arena: std.mem.Allocator, out: *std.ArrayList(Token), src: []const u8, at: usize, line: *usize, four: bool) Error!usize {
    try emit(arena, out, .semicolon, "", line.*);
    var i = at + 1;
    // the rest of the opening line is ignored; data starts on the next line
    while (i < src.len and src[i] != '\n') i += 1;
    if (i < src.len) {
        i += 1;
        line.* += 1;
    }
    while (i < src.len) {
        const ls = i;
        while (i < src.len and src[i] != '\n') i += 1;
        const raw = src[ls..i];
        const at_line = line.*;
        if (i < src.len) {
            i += 1;
            line.* += 1;
        }
        const trimmed = std.mem.trim(u8, raw, " \t\r");
        // DATALINES4/CARDS4 end on a lone `;;;;`; DATALINES/CARDS on a leading `;`.
        const terminates = if (four) std.mem.startsWith(u8, trimmed, ";;;;") else (trimmed.len > 0 and trimmed[0] == ';');
        if (terminates) {
            try emit(arena, out, .semicolon, "", at_line);
            return i;
        }
        try emit(arena, out, .data_line, std.mem.trimEnd(u8, raw, "\r"), at_line);
    }
    return i;
}

fn lexOp(arena: std.mem.Allocator, out: *std.ArrayList(Token), src: []const u8, i: usize, line: usize, diags: *diag.Diagnostics) Error!usize {
    if (two(src, i, '*', '*')) return emit2(arena, out, .star2, line, i);
    if (two(src, i, '|', '|')) return emit2(arena, out, .concat, line, i);
    if (two(src, i, '!', '!')) return emit2(arena, out, .concat, line, i); // `!!` — alt concat
    // `¦¦` — broken-bar concat; each `¦` is UTF-8 0xC2 0xA6, so the pair is 4 bytes.
    if (i + 3 < src.len and src[i] == 0xC2 and src[i + 1] == 0xA6 and src[i + 2] == 0xC2 and src[i + 3] == 0xA6) {
        try emit(arena, out, .concat, "", line);
        return i + 4;
    }
    if (two(src, i, '<', '=')) return emit2(arena, out, .le, line, i);
    if (two(src, i, '>', '=')) return emit2(arena, out, .ge, line, i);
    // `=<` / `=>` — the LEGACY spellings of LE / GE, still accepted by SAS 9.4
    // "for compatibility with previous releases of SAS" (Language Reference: Concepts p.127 Table 6.4
    // footnotes 2 and 3). They become the ORDINARY `.le`/`.ge` tokens, so
    // precedence, chained comparison and the `:` modifier all come for free; the
    // spelling rides along in `text` only because the same footnotes say these
    // two are not valid in a WHERE clause, which parser_expr rejects.
    // Maximal munch: both chars must be ADJACENT, and nothing else in the
    // grammar starts a token with `=` — `x =-1`, `a = <expr>` and the `=*`
    // sounds-like pair (which lexes `.eq`+`.star`) are untouched.
    if (two(src, i, '=', '<')) {
        try emit(arena, out, .le, "=<", line);
        return i + 2;
    }
    if (two(src, i, '=', '>')) {
        try emit(arena, out, .ge, "=>", line);
        return i + 2;
    }
    // `><` MIN / `<>` MAX operators (SAS Group I). Checked before the single
    // `<`/`>` fallthrough; the second char differs from `<=`/`>=` so order is safe.
    if (two(src, i, '>', '<')) return emit2(arena, out, .min_op, line, i);
    if (two(src, i, '<', '>')) return emit2(arena, out, .max_op, line, i);
    if (two(src, i, '^', '=') or two(src, i, '~', '=')) return emit2(arena, out, .ne, line, i);
    if (two(src, i, '@', '@')) return emit2(arena, out, .atat, line, i); // `@@` double-trailing hold
    // `¦` / `¬` — the EBCDIC-era OR / NOT glyphs, alternate spellings of `|` /
    // `^` (GAP-whereorbang). Both are multi-byte UTF-8 (0xC2 0xA6 / 0xC2 0xAC),
    // so match the byte pair; the `¦¦` concat above stays concat, like `||`.
    if (src[i] == 0xC2 and i + 1 < src.len) {
        if (src[i + 1] == 0xA6) {
            try emit(arena, out, .pipe, "", line);
            return i + 2;
        }
        if (src[i + 1] == 0xAC) {
            // `¬=` (0xC2 0xAC 0x3D) — the not-sign NOT-EQUAL, one token by
            // maximal munch: Language Reference: Concepts p.219 Table 11.3 lists `^= ~= ¬= <>` as the
            // NE spellings and SQL Procedure Table 8.2 group 7 (printed
            // p.403-404) lists `¬=, ^=, <>, ne`. Split as `¬`+`=` it was
            // caret+eq: loud in the DATA step but a SILENT no-op filter in
            // PROC SQL (BUG-sqlnotequalunicode). `¬ =` (space) stays NOT then
            // `=`, same as `^ =`.
            if (i + 2 < src.len and src[i + 2] == '=') {
                try emit(arena, out, .ne, "", line);
                return i + 3;
            }
            try emit(arena, out, .caret, "", line);
            return i + 2;
        }
    }

    const tag: Tag = switch (src[i]) {
        '@' => .at, // column pointer / single trailing hold
        '#' => .hash, // line pointer
        '?' => .question, // INPUT error-suppression modifier (`?`/`??`)
        '+' => .plus,
        '-' => .minus,
        '*' => .star,
        '=' => .eq,
        '<' => .lt,
        '>' => .gt,
        '|' => .pipe,
        '!' => .pipe, // `!` — alt OR; the `!!` concat check above already won doubles
        '&' => .amp,
        '^', '~' => .caret,
        '(' => .lparen,
        ')' => .rparen,
        ',' => .comma,
        else => return diags.fail(error.LexError, line, "unexpected character '{c}'", .{src[i]}),
    };
    // `.caret` keeps its source byte as text: `^` and `~` share the tag (both
    // are NOT prefix, so expression parsing must NOT diverge) but PUT's
    // modifier slot must tell the documented `~` modifier from a `^` typo
    // (GAP-puttildemodifier, D-018). The `¬` alias above stays empty-texted.
    try emit(arena, out, tag, if (tag == .caret) src[i .. i + 1] else "", line);
    return i + 1;
}

fn two(src: []const u8, at: usize, a: u8, b: u8) bool {
    return at + 1 < src.len and src[at] == a and src[at + 1] == b;
}

fn emit2(arena: std.mem.Allocator, out: *std.ArrayList(Token), tag: Tag, line: usize, i: usize) Error!usize {
    try emit(arena, out, tag, "", line);
    return i + 2;
}

// ── tests ────────────────────────────────────────────────────────────────

test "tokenizes the expression operator surface" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const toks = try tokenize(a, "foo(1, .5) ** 2 <= x || 'hi' & a ^= b", &diags);
    const want = [_]Tag{
        .name,  .lparen, .number, .comma,  .number, .rparen, .star2, .number,
        .le,    .name,   .concat, .string, .amp,    .name,   .ne,    .name,
        .eof,
    };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
    try std.testing.expectEqualStrings("foo", toks[0].text);
    try std.testing.expectEqualStrings(".5", toks[4].text);
    try std.testing.expectEqualStrings("hi", toks[11].text);
}

test "doubled quotes escape to a single quote in the literal value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // 'it''s'  →  it's   ;   "say ""hi"""  →  say "hi"
    const toks = try tokenize(a, "'it''s' \"say \"\"hi\"\"\"", &diags);
    try std.testing.expect(toks[0].tag == .string);
    try std.testing.expectEqualStrings("it's", toks[0].text);
    try std.testing.expect(toks[1].tag == .string);
    try std.testing.expectEqualStrings("say \"hi\"", toks[1].text);

    // an unescaped, unpaired closing quote still terminates normally
    const pair = try tokenize(a, "'ab' 'cd'", &diags);
    try std.testing.expectEqualStrings("ab", pair[0].text);
    try std.testing.expectEqualStrings("cd", pair[1].text);
}

test "mnemonics stay names; block comments are skipped; names kept verbatim" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const toks = try tokenize(a, "AgE /* drop this */ And b", &diags);
    const want = [_]Tag{ .name, .name, .name, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
    try std.testing.expectEqualStrings("AgE", toks[0].text); // verbatim, not folded
    try std.testing.expectEqualStrings("And", toks[1].text);
}

test "lone dot vs decimal, and | vs ||" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const toks = try tokenize(a, "x = . | y || z", &diags);
    const want = [_]Tag{ .name, .eq, .dot, .pipe, .name, .concat, .name, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
}

test "not-sign operators: `¬=` is one NE token, `¬` is NOT, non-ASCII stays loud" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // BUG-sqlnotequalunicode: `¬=` (U+00AC + `=`, bytes 0xC2 0xAC 0x3D) is a
    // NOT-EQUAL spelling (Language Reference: Concepts p.219 Table 11.3; SQL Procedure Table 8.2
    // group 7, printed p.403-404). Maximal munch: ONE .ne token, not .caret+.eq
    // — split, it was loud in the DATA step but silently kept every row in SQL.
    const toks = try tokenize(a, "x ¬= 3", &diags);
    const want = [_]Tag{ .name, .ne, .number, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, tk| try std.testing.expect(w == tk.tag);

    // adjacency: `¬ =` (space) stays NOT then `=`, like `^ =`
    const spaced = try tokenize(a, "x ¬ = 3", &diags);
    const want2 = [_]Tag{ .name, .caret, .eq, .number, .eof };
    for (want2, spaced) |w, tk| try std.testing.expect(w == tk.tag);

    // `¬` alone and the broken bar keep their GAP-whereorbang aliases
    const glyphs = try tokenize(a, "¬a ¦ b ¦¦ c", &diags);
    const want3 = [_]Tag{ .caret, .name, .pipe, .name, .concat, .name, .eof };
    for (want3, glyphs) |w, tk| try std.testing.expect(w == tk.tag);

    // any OTHER 0xC2-led glyph still fails LOUD (captured diags, never abort)
    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.LexError, tokenize(a, "a © b", &d2));
    try std.testing.expect(d2.hasErrors());
}

test "unexpected char and unterminated string report LexError" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    try std.testing.expectError(error.LexError, tokenize(a, "a ` b", &diags)); // backtick: still unexpected
    try std.testing.expect(diags.hasErrors());
    try std.testing.expectError(error.LexError, tokenize(a, "'oops", &diags));
}

test "statement tokens: semicolon and dollar" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const toks = try tokenize(a, "input name $ age;", &diags);
    const want = [_]Tag{ .name, .name, .dollar, .name, .semicolon, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
}

test "input informat modifier lexes the colon" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const toks = try tokenize(a, "input n :comma8. d :date9.;", &diags);
    const want = [_]Tag{
        .name,  .name, .colon, .name, .dot, // input n :comma8.
        .name,  .colon, .name, .dot, // d :date9.
        .semicolon, .eof,
    };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
}

test "numeric hex constant lexes to its value; idents ending in x stay names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // 0fx=15, 1Fx=31, 9x=9 (single hex digit), 0b0ax=2826; max/xx stay names.
    const toks = try tokenize(a, "0fx 1Fx 9x 0b0ax max xx", &diags);
    const want = [_]Tag{ .number, .number, .number, .number, .name, .name, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
    try std.testing.expectEqualStrings("15", toks[0].text);
    try std.testing.expectEqualStrings("31", toks[1].text);
    try std.testing.expectEqualStrings("9", toks[2].text);
    try std.testing.expectEqualStrings("2826", toks[3].text);
    try std.testing.expectEqualStrings("max", toks[4].text);
    try std.testing.expectEqualStrings("xx", toks[5].text);

    // decimal/scientific are untouched (no trailing x)
    const nums = try tokenize(a, "1.5 1e5 123", &diags);
    try std.testing.expectEqualStrings("1.5", nums[0].text);
    try std.testing.expectEqualStrings("1e5", nums[1].text);
    try std.testing.expectEqualStrings("123", nums[2].text);
}

test "legacy =< / => lex as LE / GE and carry their spelling (Language Reference: Concepts p.127 fn.2/3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const toks = try tokenize(a, "a =< b  c => d", &diags);
    const want = [_]Tag{ .name, .le, .name, .name, .ge, .name, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
    // the spelling rides in `text` — parser_expr rejects it in a WHERE clause
    try std.testing.expectEqualStrings("=<", toks[1].text);
    try std.testing.expectEqualStrings("=>", toks[4].text);
    // the modern spellings are the same tags with no stamp
    const modern = try tokenize(a, "a <= b >= c", &diags);
    try std.testing.expect(modern[1].tag == .le and modern[1].text.len == 0);
    try std.testing.expect(modern[3].tag == .ge and modern[3].text.len == 0);

    // the neighbours the two-char munch must NOT steal: `=-1` stays `=` `-` `1`,
    // `=*` stays `=` `*` (parser_expr peeks that pair for sounds-like), and a
    // spaced `= <` is two tokens (SAS requires the legacy pair to be adjacent).
    const neg = try tokenize(a, "x =-1", &diags);
    const neg_want = [_]Tag{ .name, .eq, .minus, .number, .eof };
    for (neg_want, neg) |w, t| try std.testing.expect(w == t.tag);
    const snd = try tokenize(a, "x =* y", &diags);
    const snd_want = [_]Tag{ .name, .eq, .star, .name, .eof };
    for (snd_want, snd) |w, t| try std.testing.expect(w == t.tag);
    const spaced = try tokenize(a, "x = < 1", &diags);
    const spaced_want = [_]Tag{ .name, .eq, .lt, .number, .eof };
    for (spaced_want, spaced) |w, t| try std.testing.expect(w == t.tag);
}

test "datalines block captures raw lines up to the terminator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const src =
        "datalines;\n" ++
        "Ann 30\n" ++
        "  Bo 25 \n" ++
        ";\n";
    const toks = try tokenize(a, src, &diags);
    // name(datalines) ; data_line data_line ; eof
    const want = [_]Tag{ .name, .semicolon, .data_line, .data_line, .semicolon, .eof };
    try std.testing.expectEqual(want.len, toks.len);
    for (want, toks) |w, t| try std.testing.expect(w == t.tag);
    try std.testing.expectEqualStrings("Ann 30", toks[2].text);
    try std.testing.expectEqualStrings("  Bo 25 ", toks[3].text); // leading/trailing kept
}
