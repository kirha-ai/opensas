//! Expression parser — tokens → `ast.Expr`. Precedence climbing (Pratt): one
//! `parseBin(min_prec)` loop with a per-operator precedence, `**` right-assoc,
//! unary `-`/`NOT` binding looser than `**` (so `-2**2` is `-(2**2)`), function
//! calls, and the lone `.` numeric-missing literal.
//!
//! Input contract — the `Token` stream:
//!   Tokens come from `lexer.zig`, which OWNS the `Token`/`Tag` types (they were
//!   seeded here while no lexer existed and have since been hoisted, L1). The
//!   statement parser (A2) reuses this same `Parser` — the cursor helpers are
//!   `pub` — over the whole token stream.
//!
//! Arena: every node is `arena.create`d; the caller owns the arena and frees
//! the whole tree at once. Errors go through the shared `Diagnostics` (M0.4).

const std = @import("std");
const ast = @import("ast.zig");
const diag = @import("diag.zig");
const lexer = @import("lexer.zig");
const Value = @import("value.zig").Value; // special-missing encoding for `.A`-`.Z`

const Error = diag.Error;

// The token contract lives in the lexer now (L1); re-exported so consumers can
// spell either `lexer.Token` or `parser_expr.Token`.
pub const Token = lexer.Token;
pub const Tag = lexer.Tag;

// ── Precedence table ─────────────────────────────────────────────────────
// Higher binds tighter. Mirrors SAS operator priority (OR<AND<compare<concat<
// add<mul<pow). Unary operands parse at `prec_pow` so `**` binds into them but
// `*`/`/` do not — this is what makes `-2**2` == `-(2**2)`.

// minmax (`><`/`<>`/MIN/MAX) is SAS Group I TOGETHER with `**` and the unary
// ops: one precedence level, evaluated right-to-left — `2 ** 3 <> 4` is
// 2**(3<>4)=16 and `-2 <> 3` is -(2<>3)=-3, the same rule that makes -2**2=-4
// (BUG-minmaxprec; a separate left-assoc level 7 silently mis-grouped exactly
// those mixes).
const prec_pow: u8 = 8;
const prec_minmax: u8 = prec_pow;

const OpInfo = struct { op: ast.BinOp, prec: u8, right: bool };

/// peekNotCmp's result: the negated comparison op, or the `not =*` sounds-like
/// marker (its desugar needs the soundex() pair, not a bare BinOp).
const NotCmp = union(enum) { op: ast.BinOp, sounds_like };

// ── Parser ───────────────────────────────────────────────────────────────

/// Walks a `[]const Token` that MUST end with an `.eof` token (so `peek` is
/// always valid). Reusable by the statement parser: `peek`/`advance`/`check`/
/// `eat`/`expect` are `pub`, and `parseExpr` consumes exactly one expression,
/// leaving the cursor on the first token it did not use.
/// One `array` declaration, seen so a later `a{i}` in an expression resolves to
/// its member variables. Registered by the statement parser (E1); read here.
/// One array dimension: explicit lower bound (`{lo:hi}` → lo; a bare `{n}` → 1)
/// and its element count. `dims.len` is the array's rank (GAP-multidimarray).
pub const ArrayDim = struct { lo: i64 = 1, size: usize = 0 };

/// A declared array. Element access offsets each subscript by its dimension's
/// lower bound and folds a multi-dim `{i,j}` reference into one row-major flat
/// index (SAS 9.4: the number of elements is the product of the dimensions; the
/// rightmost subscript varies fastest), so the resolved 0-based `elements` list
/// is hit at `elements[flat]` with NO runtime change (ARRAY-lobound / GAP-multidimarray).
pub const ArrayDef = struct { name: []const u8, elements: []const []const u8, special: ?ast.SpecialArr = null, dims: []const ArrayDim = &.{.{}} };

pub const Parser = struct {
    arena: std.mem.Allocator,
    toks: []const Token,
    diags: *diag.Diagnostics,
    pos: usize = 0,
    arrays: std.ArrayList(ArrayDef) = .empty, // declared arrays, for a{i} refs
    // Inside a WHERE expression `<>` means NOT-EQUAL, not the MAX operator —
    // the documented SAS WHERE quirk — and `><` (MIN) is not valid at all.
    // Set by every WHERE parse site (WHERE statement, where= option, PROC
    // WHERE); silently keeping MAX turned `where x <> 3` into a filter that
    // kept every row (BUG-wherene).
    where_ctx: bool = false,
    // GAP-hashinexpr: a hash method/attribute call met inside an expression
    // (`if h.find() = 0 then`) can't be seen by the evaluator, so parsePrimary
    // hoists it here (target = a minted `__hashattr_N` temp); the statement
    // parser drains the list into `hash_op` statements around the enclosing
    // statement. Temps are minted through the statement parser's own counter so
    // they share its `__hashattr:` drop wildcard. Null = disabled (WHERE/SQL
    // sub-parsers) — a hash call there stays the loud parse error it was.
    hash_hoists: std.ArrayList(ast.HashCall) = .empty,
    hashattr_n: ?*usize = null,
    // Live recursion depth of parseBin — every nesting level (a paren, a unary
    // op, a call/array arg) routes through it, so one counter here guards the
    // whole Pratt loop. Adversarial input (`(((…1…)))` ~100k deep) overflowed
    // the native stack and SEGFAULTed instead of failing loud (BUG-parser-deepnest).
    depth: u16 = 0,

    pub fn init(arena: std.mem.Allocator, toks: []const Token, diags: *diag.Diagnostics) Parser {
        return .{ .arena = arena, .toks = toks, .diags = diags };
    }

    /// A declared array (members + special-list kind), matched case-insensitively.
    pub fn lookupArray(self: *Parser, name: []const u8) ?ArrayDef {
        for (self.arrays.items) |d| {
            if (std.ascii.eqlIgnoreCase(d.name, name)) return d;
        }
        return null;
    }

    /// Offset an array subscript by an explicit lower bound: `a{i}` on an array
    /// declared `{lo:hi}` reads the (i-lo)-th 0-based member, so rewrite the
    /// subscript to `i - (lo-1)` — then the shared `elements[i-1]` runtime path
    /// lands on the right slot with NO runtime change (ARRAY-lobound-impl). A
    /// default lower bound (lo=1) returns the index untouched.
    pub fn offsetArrayIndex(self: *Parser, index: *const ast.Expr, lo: i64) Error!*const ast.Expr {
        if (lo == 1) return index;
        return self.mk(.{ .binary = .{
            .op = .sub,
            .lhs = index,
            .rhs = try self.mk(.{ .num = @floatFromInt(lo - 1) }),
        } });
    }

    /// Fold an array reference's subscript list into ONE 1-based flat index
    /// expression, so the shared `elements[i-1]` runtime path reaches the right
    /// member with no runtime change (GAP-multidimarray). 1-D keeps the exact
    /// ARRAY-lobound rewrite. Multi-dim is row-major (SAS: rightmost varies
    /// fastest): flat = 1 + Σ_m (idx_m − lo_m)·(Π sizes after m).
    ///
    /// SAS 9.4 validates EACH subscript against ITS dimension's bounds and
    /// truncates it to an integer BEFORE folding — a per-dimension OOR (`a{1,3}`
    /// on a{2,2}) must fail loud, not silently carry into a valid-but-wrong flat
    /// slot (BUG-arraymultidimoor, data corruption). Two encodings, both hit the
    /// unchanged `elements[flat-1]` runtime path:
    ///   • all-literal subscripts → fold to a constant flat index HERE, checking
    ///     bounds at parse time (SAS reports constant OOR at compile time) — keeps
    ///     the fold const-foldable (GAP-multidimarray tests) and fixes truncation.
    ///   • any dynamic subscript → a synthetic `__dimchk` call (resolved in
    ///     eval.zig) carrying each dim's (index, lo, size) so the truncate + check
    ///     + fold run at eval. Read / write / put all inherit it via `index`.
    pub fn arraySubscript(self: *Parser, name_tok: Token, indices: []const *const ast.Expr, dims: []const ArrayDim) Error!*const ast.Expr {
        if (dims.len <= 1) return self.offsetArrayIndex(indices[0], if (dims.len == 1) dims[0].lo else 1);
        var all_const = true;
        for (indices) |ix| if (ix.* != .num) {
            all_const = false;
        };
        if (all_const) {
            var flat: f64 = 1; // 1-based: elements[flat-1]
            for (dims, 0..) |dim, m| {
                const v = @floor(indices[m].num); // SAS truncates each subscript
                const hi = dim.lo + @as(i64, @intCast(dim.size)) - 1;
                if (v < @as(f64, @floatFromInt(dim.lo)) or v > @as(f64, @floatFromInt(hi)))
                    return self.diags.fail(error.ParseError, name_tok.line, "Array subscript {d} out of range for {s} at line {d} column 0.", .{ v, name_tok.text, name_tok.line });
                var mult: i64 = 1;
                for (dims[m + 1 ..]) |d2| mult *= @intCast(d2.size);
                flat += (v - @as(f64, @floatFromInt(dim.lo))) * @as(f64, @floatFromInt(mult));
            }
            return self.mk(.{ .num = flat });
        }
        const args = try self.arena.alloc(ast.Expr, 2 + 3 * dims.len);
        args[0] = .{ .str = name_tok.text };
        args[1] = .{ .num = @floatFromInt(name_tok.line) };
        for (dims, 0..) |dim, m| {
            const base = 2 + m * 3;
            args[base] = indices[m].*;
            args[base + 1] = .{ .num = @floatFromInt(dim.lo) };
            args[base + 2] = .{ .num = @floatFromInt(dim.size) };
        }
        return self.mk(.{ .call = .{ .name = "__dimchk", .args = args } });
    }

    // cursor -----------------------------------------------------------------

    pub fn peek(self: *Parser) Token {
        // The eof-sentinel contract can be broken upstream: a truncated `of`
        // list (`sum(of a` — no closing paren) makes the token-level of-list
        // rewrite drop the trailing .eof, and the cursor then walks past the
        // array (BUG-ofcrashtruncated: panic/SIGABRT). Clamp to a synthetic
        // eof so the parse fails loud via expect() like any other truncated
        // call, instead of panicking. Real (eof-terminated) slices never take
        // this branch.
        if (self.pos >= self.toks.len)
            return .{ .tag = .eof, .line = if (self.toks.len > 0) self.toks[self.toks.len - 1].line else 0 };
        return self.toks[self.pos];
    }

    pub fn advance(self: *Parser) Token {
        const t = self.peek();
        if (t.tag != .eof) self.pos += 1;
        return t;
    }

    pub fn check(self: *Parser, tag: Tag) bool {
        return self.peek().tag == tag;
    }

    pub fn eat(self: *Parser, tag: Tag) bool {
        if (self.check(tag)) {
            _ = self.advance();
            return true;
        }
        return false;
    }

    pub fn expect(self: *Parser, tag: Tag, comptime what: []const u8) Error!Token {
        if (self.check(tag)) return self.advance();
        return self.diags.fail(error.ParseError, self.peek().line, "expected " ++ what, .{});
    }

    // expressions ------------------------------------------------------------

    /// Parse one full expression (lowest precedence).
    pub fn parseExpr(self: *Parser) Error!*const ast.Expr {
        return self.parseBin(0);
    }

    // Ceiling on expression nesting. Real SAS code never nests this deep; well
    // under the ~100k parens that overflow the native stack, so we fail loud
    // first. ponytail: bump if a legitimate program ever trips it.
    pub const max_depth: u16 = 2000;

    fn parseBin(self: *Parser, min_prec: u8) Error!*const ast.Expr {
        if (self.depth >= max_depth)
            return self.diags.fail(error.ParseError, self.peek().line, "expression nesting too deep (over {d} levels)", .{max_depth});
        self.depth += 1;
        defer self.depth -= 1;
        var lhs = try self.parseUnary();
        // rhs operand of the last comparison built at THIS level — a following
        // comparison op chains SAS-style (QA-chaincmp below).
        var chain_rhs: ?*const ast.Expr = null;
        while (true) {
            // IN / NOT IN sit at comparison precedence (3) but take a parenthesized
            // LIST, not a single operand, so peekBinOp can't model them. Desugar to
            // an OR of equalities (AND of inequalities for NOT IN) — no new AST node.
            if (self.peekIn()) |negated| {
                if (3 < min_prec) break;
                if (negated) _ = self.advance(); // 'not'
                _ = self.advance(); // 'in'
                // `IN:` — the colon prefix-match modifier, the same family as
                // `=:` ("You can add a colon (:) modifier to any of the
                // operators", Language Reference: Concepts p.127; p.130 names the "IN: comparison"
                // explicitly). Each membership test truncates to the shorter
                // operand through the ONE existing prefix compare, mkTruncCmp.
                const truncate = self.eat(.colon);
                lhs = try self.parseInRhs(lhs, negated, truncate);
                chain_rhs = null;
                continue;
            }
            // CONTAINS / `?` (its synonym) are WHERE-only comparison operators
            // (prec 3). No BinOp/eval path exists for them, so desugar to
            // `index(L, R) gt 0` (`= 0` when negated), mirroring sql.zig:1017
            // (GH#16 ISS-wherecontains). Kept out of plain IF via where_ctx.
            if (self.peekContains()) |negated| {
                if (3 < min_prec) break;
                if (negated) _ = self.advance(); // 'not'
                _ = self.advance(); // 'contains' / '?'
                const rhs = try self.parseBin(4); // rhs at comparison prec + 1
                lhs = try self.mkContains(lhs, rhs, negated);
                chain_rhs = null;
                continue;
            }
            // LIKE / NOT LIKE — WHERE-only comparison operator (prec 3). `%` matches
            // any string, `_` exactly one char. Desugar to the like() runtime call,
            // mirroring sql.zig:1011 so DATA-step and PROC/SQL WHERE agree (GH#20).
            if (self.peekLike()) |negated| {
                if (3 < min_prec) break;
                if (negated) _ = self.advance(); // 'not'
                _ = self.advance(); // 'like'
                const rhs = try self.parseBin(4); // rhs at comparison prec + 1
                lhs = try self.mkLike(lhs, rhs, negated);
                chain_rhs = null;
                continue;
            }
            // Infix `NOT` before a comparison operator (`x not eq 4`) or before
            // `=*` (`lastname not =* 'Smith'`) — Language Reference: Concepts p.226: "You can use the
            // NOT logical operator in combination with any SAS and WHERE
            // expression operator", p.224 (sounds-like). The six sibling
            // negations (not in/contains/like/between, is not missing) already
            // worked; desugar to the NEGATED operator — no new AST node, the
            // same trick as NOT IN (GAP-wherenotinfix). Ungated like NOT IN:
            // a PREFIX not never reaches here (parseUnary eats it), so
            // `not x eq 4` keeps SAS's (not x) eq 4 precedence.
            if (self.peekNotCmp()) |nc| {
                if (3 < min_prec) break;
                _ = self.advance(); // 'not'
                _ = self.advance(); // the comparison operator
                switch (nc) {
                    .op => |op| {
                        const rhs = try self.parseBin(4); // rhs at comparison prec + 1
                        lhs = try self.mk(.{ .binary = .{ .op = op, .lhs = lhs, .rhs = rhs } });
                        chain_rhs = rhs; // a negated compare is still a compare (chains)
                    },
                    .sounds_like => {
                        _ = self.advance(); // '*'
                        const rhs = try self.parseBin(4);
                        const sl = try self.mkCall1("soundex", lhs);
                        const sr = try self.mkCall1("soundex", rhs);
                        lhs = try self.mk(.{ .binary = .{ .op = .ne, .lhs = sl, .rhs = sr } });
                        chain_rhs = null;
                    },
                }
                continue;
            }
            // `=*` sounds-like comparison (prec 3): TRUE when SOUNDEX(L) =
            // SOUNDEX(R). The lexer has no `=*` token — it lexes as `.eq` then
            // `.star` — so peek the pair here and desugar to
            // `soundex(L) = soundex(R)`, the same no-new-BinOp trick as
            // mkLike/mkTruncCmp (GAP-soundslike). `a = * b` was a parse error
            // before, so stealing the pair breaks nothing. soundex() coerces
            // both operands to char and yields '' for blanks, so two blanks
            // compare equal — exactly SAS's rule.
            if (self.peek().tag == .eq and self.toks[self.pos + 1].tag == .star) {
                if (3 < min_prec) break;
                _ = self.advance(); // '='
                _ = self.advance(); // '*'
                const rhs = try self.parseBin(4); // rhs at comparison prec + 1
                const sl = try self.mkCall1("soundex", lhs);
                const sr = try self.mkCall1("soundex", rhs);
                lhs = try self.mk(.{ .binary = .{ .op = .eq, .lhs = sl, .rhs = sr } });
                chain_rhs = null;
                continue;
            }
            const info = self.peekBinOp() orelse break;
            if (info.prec < min_prec) break;
            // The `><` SYMBOL has no WHERE meaning (and `<>` became NE above) —
            // erroring beats silently computing a MIN nobody asked for
            // (BUG-wherene). The word form MIN is fine (Language Reference: Concepts p.225).
            if (self.where_ctx and info.op == .min and self.peek().tag == .min_op)
                return self.diags.fail(error.ParseError, self.peek().line, "the >< (MIN) operator is not valid in a WHERE expression", .{});
            // The LEGACY `=<`/`=>` spellings of LE/GE are accepted everywhere a
            // DATA-step expression is — but NOT in a WHERE clause (Language Reference: Concepts p.127
            // Table 6.4 fn.2/3). The lexer stamped the spelling on the token, so
            // reject it loud here rather than silently comparing, exactly like
            // `><` above. ponytail: the same footnote excludes PROC SQL, which
            // parses its WHERE through this parser WITHOUT where_ctx (sql.zig
            // owns that path) — so the SQL half is not enforced yet.
            if (self.where_ctx and (std.mem.eql(u8, self.peek().text, "=<") or std.mem.eql(u8, self.peek().text, "=>")))
                return self.diags.fail(error.ParseError, self.peek().line, "the {s} operator is not valid in a WHERE expression", .{self.peek().text});
            _ = self.advance();
            // Colon-modified comparison (`x =: 'T'`, `x ^=: 'T'`, `eq:`, …): the
            // `:` is a separate token right after the op (EBNF `compare_op [ ":" ]`),
            // so peek for it here rather than exploding the operator token set.
            // It truncates the compare to the shorter operand's length (GH#29).
            // NOTE-sqltruncblanks: a colon MARKED "trim" was planted by sql.zig's
            // EQT-family rewrite and carries PROC SQL's trailing-blank rule
            // (p.405); an unmarked one is the DATA step's own `=:` and keeps the
            // storage-length rule. Read before eating — `eat` discards the token.
            const trim_blanks = self.check(.colon) and std.mem.eql(u8, self.peek().text, "trim");
            const truncate = isCmpOp(info.op) and self.eat(.colon);
            // right-assoc: recurse at the same prec so a following same-prec op
            // binds into the rhs; left-assoc: recurse one higher so it doesn't.
            const next_min = if (info.right) info.prec else info.prec + 1;
            const rhs = try self.parseBin(next_min);
            if (truncate) {
                // ponytail: truncated compares don't chain — build and move on.
                lhs = try self.mkTruncCmp(info.op, lhs, rhs, trim_blanks);
                chain_rhs = null;
                continue;
            }
            // SAS chained comparison (QA-chaincmp): `a <= x <= b` means
            // (a<=x) AND (x<=b) — NOT the C-style ((a<=x))<=b, whose 0/1 result
            // compared to a date/datetime is almost always true (this silently
            // broke every low<=x<=high window check, e.g. an EPOCH macro's). The
            // shared middle operand is one AST node evaluated twice — SAS
            // expressions are pure, so that's safe.
            if (isCmpOp(info.op) and chain_rhs != null) {
                const cmp = try self.mk(.{ .binary = .{ .op = info.op, .lhs = chain_rhs.?, .rhs = rhs } });
                lhs = try self.mk(.{ .binary = .{ .op = .@"and", .lhs = lhs, .rhs = cmp } });
            } else {
                lhs = try self.mk(.{ .binary = .{ .op = info.op, .lhs = lhs, .rhs = rhs } });
            }
            chain_rhs = if (isCmpOp(info.op)) rhs else null;
        }
        return lhs;
    }

    /// At an `in` / `not in` operator? Returns whether it's negated, else null.
    fn peekIn(self: *Parser) ?bool {
        const t = self.peek();
        if (t.tag != .name) return null;
        if (std.ascii.eqlIgnoreCase(t.text, "in")) return false;
        if (std.ascii.eqlIgnoreCase(t.text, "not")) {
            const nx = if (self.pos + 1 < self.toks.len) self.toks[self.pos + 1] else self.toks[self.toks.len - 1];
            if (nx.tag == .name and std.ascii.eqlIgnoreCase(nx.text, "in")) return true;
        }
        return null;
    }

    /// At a CONTAINS / `?` operator (WHERE-only)? Returns whether it's negated
    /// (`NOT CONTAINS` / `NOT ?`), else null. Gated on where_ctx so `if x contains…`
    /// stays a loud parse error outside WHERE (GH#16).
    fn peekContains(self: *Parser) ?bool {
        if (!self.where_ctx) return null;
        const t = self.peek();
        if (t.tag == .question) return false;
        if (t.tag != .name) return null;
        if (std.ascii.eqlIgnoreCase(t.text, "contains")) return false;
        if (std.ascii.eqlIgnoreCase(t.text, "not")) {
            const nx = if (self.pos + 1 < self.toks.len) self.toks[self.pos + 1] else self.toks[self.toks.len - 1];
            if (nx.tag == .question or (nx.tag == .name and std.ascii.eqlIgnoreCase(nx.text, "contains"))) return true;
        }
        return null;
    }

    /// At a LIKE / NOT LIKE operator (WHERE-only)? Returns whether it's negated,
    /// else null. Gated on where_ctx so `if x like…` stays a loud parse error
    /// outside WHERE, matching CONTAINS (GH#20).
    fn peekLike(self: *Parser) ?bool {
        if (!self.where_ctx) return null;
        const t = self.peek();
        if (t.tag != .name) return null;
        if (std.ascii.eqlIgnoreCase(t.text, "like")) return false;
        if (std.ascii.eqlIgnoreCase(t.text, "not")) {
            const nx = if (self.pos + 1 < self.toks.len) self.toks[self.pos + 1] else self.toks[self.toks.len - 1];
            if (nx.tag == .name and std.ascii.eqlIgnoreCase(nx.text, "like")) return true;
        }
        return null;
    }

    /// At an infix `NOT` + comparison operator (`x not eq 4`, `x not = 4`,
    /// `x not =* 'S'`)? Returns the NEGATED operator, or .sounds_like for
    /// `not =*` (GAP-wherenotinfix). Null when `not` is the prefix operator
    /// (followed by an operand) or precedes a non-comparison word (`not and`,
    /// `not min`) — those are not this form.
    fn peekNotCmp(self: *Parser) ?NotCmp {
        const t = self.peek();
        if (t.tag != .name or !std.ascii.eqlIgnoreCase(t.text, "not")) return null;
        const nx = if (self.pos + 1 < self.toks.len) self.toks[self.pos + 1] else self.toks[self.toks.len - 1];
        switch (nx.tag) {
            .name => {
                const m = mnemonicOp(nx.text) orelse return null;
                return switch (m.op) {
                    .eq => .{ .op = .ne },
                    .ne => .{ .op = .eq },
                    .lt => .{ .op = .ge },
                    .le => .{ .op = .gt },
                    .gt => .{ .op = .le },
                    .ge => .{ .op = .lt },
                    else => null,
                };
            },
            .eq => {
                // `not =*` (sounds-like) vs plain `not =`: peek the third token.
                const nx2 = if (self.pos + 2 < self.toks.len) self.toks[self.pos + 2] else self.toks[self.toks.len - 1];
                if (nx2.tag == .star) return .sounds_like;
                return .{ .op = .ne };
            },
            .ne => return .{ .op = .eq },
            .lt => return .{ .op = .ge },
            .le => return .{ .op = .gt },
            .gt => return .{ .op = .le },
            .ge => return .{ .op = .lt },
            else => return null,
        }
    }

    /// `L like R` → `like(L, R)` (1/0); `L not like R` → `not like(L, R)`.
    /// Mirrors sql.zig:1011 so DATA-step and PROC/SQL WHERE agree.
    fn mkLike(self: *Parser, lhs: *const ast.Expr, rhs: *const ast.Expr, negated: bool) Error!*const ast.Expr {
        const args = try self.arena.alloc(ast.Expr, 2);
        args[0] = lhs.*;
        args[1] = rhs.*;
        const call = try self.mk(.{ .call = .{ .name = "like", .args = args } });
        if (!negated) return call;
        return self.mk(.{ .unary = .{ .op = .not, .operand = call } });
    }

    /// `L op: R` — colon-modified (truncated) comparison. SAS truncates the
    /// LONGER operand to the SHORTER one's length before comparing (Language Reference: Concepts Ch.6
    /// p.129: "SAS truncates the longer value to the length of the shorter
    /// value"), so BOTH operands are cut to `min(lengthc(L), lengthc(R))` —
    /// LENGTHC (storage length incl. trailing blanks, declared width for vars),
    /// not trimmed LENGTH (BUG-coloncmplen: `"ca" =: "cat"` is 1 in SAS;
    /// `v/$10 =: w/$5` compares 5 chars). Reuses the substr/lengthc/min runtime
    /// rather than adding a BinOp+eval path (GH#29).
    /// ponytail: this is a CHAR operator — numeric operands coerce to char via
    /// substr/lengthc, matching SAS's own character-context handling.
    ///
    /// NOTE-sqltruncblanks — `trim_blanks` picks WHICH SURFACE'S RULE applies,
    /// and the SQL Procedure User's Guide p.405 assigns the two itself, in one
    /// sentence naming both: "The Base SAS WHERE processor truncates comparisons
    /// based on the ACTUAL LENGTH of a string, EVEN IF A STRING INCLUDES BLANKS
    /// AT THE END. PROC SQL TRIMS TRAILING BLANKS from the string values before
    /// it truncates comparisons."
    ///   • false → DATA step / WHERE (`=:`, `>:`, IN:): LENGTHC, the storage
    ///     length, trailing blanks INCLUDED. The sentence above confirms that is
    ///     right, so this half is conformant and must not move.
    ///   • true  → PROC SQL's EQT/GTT/LTT/GET/LET/NET: LENGTHN, the length AFTER
    ///     trailing blanks are trimmed (0 for an all-blank value). One
    ///     identifier's difference, because "trim, then take the shorter length"
    ///     IS `min(lengthn, lengthn)`.
    /// Not threaded through a parser field: sql.zig MARKS the colon token its
    /// EQT rewrite emits, and only that rewrite can produce one inside PROC SQL
    /// (the colon modifier is not SQL syntax at all, p.405), so a user-typed
    /// DATA-step colon can never be mistaken for it.
    fn mkTruncCmp(self: *Parser, op: ast.BinOp, lhs: *const ast.Expr, rhs: *const ast.Expr, trim_blanks: bool) Error!*const ast.Expr {
        const len_fn = if (trim_blanks) "lengthn" else "lengthc";
        const n = try self.mkCall2("min", try self.mkCall1(len_fn, lhs), try self.mkCall1(len_fn, rhs));
        const sub_l = try self.mkSubstr(lhs, n);
        const sub_r = try self.mkSubstr(rhs, n);
        const cmp = try self.mk(.{ .binary = .{ .op = op, .lhs = sub_l, .rhs = sub_r } });
        // BUG-coloncmpempty (Language Reference: Concepts p.130): "If you compare a zero-length
        // character value with any other character value in either an IN:
        // comparison or an EQ: comparison, the two-character values are not
        // considered equal. The result always evaluates to 0." A blank IS the
        // zero-length/missing character value (p.129), so min(lengthn)=0 marks
        // the case (LENGTHN: 0 for blank; LENGTH blanks→1) — `'' =: ''`
        // truncated to ' ' = ' ' and trivially matched.
        // The page settles EQ: (IN: is unimplemented here and already fails
        // loud), so the guard wraps .eq only; <=:/>=: at zero length stay
        // truncation-defined (needs-oracle beyond the page).
        if (op != .eq) return cmp;
        const min_len = try self.mkCall2("min", try self.mkCall1("lengthn", lhs), try self.mkCall1("lengthn", rhs));
        const zero = try self.mk(.{ .num = 0 });
        const nonempty = try self.mk(.{ .binary = .{ .op = .gt, .lhs = min_len, .rhs = zero } });
        return self.mk(.{ .binary = .{ .op = .@"and", .lhs = nonempty, .rhs = cmp } });
    }

    fn mkCall1(self: *Parser, name: []const u8, arg: *const ast.Expr) Error!*const ast.Expr {
        const args = try self.arena.alloc(ast.Expr, 1);
        args[0] = arg.*;
        return self.mk(.{ .call = .{ .name = name, .args = args } });
    }

    fn mkCall2(self: *Parser, name: []const u8, a1: *const ast.Expr, a2: *const ast.Expr) Error!*const ast.Expr {
        const args = try self.arena.alloc(ast.Expr, 2);
        args[0] = a1.*;
        args[1] = a2.*;
        return self.mk(.{ .call = .{ .name = name, .args = args } });
    }

    /// SUBSTRN, not SUBSTR: "Returns a substring, ALLOWING A RESULT WITH A
    /// LENGTH OF ZERO" (SAS 9.4 Functions and CALL Routines: Reference p.1534).
    /// A truncated compare can legally ask for a zero-length prefix — `x =: ''`
    /// is the documented false case (Language Reference: Concepts p.130) — and SUBSTR treats length 0
    /// as an INVALID ARGUMENT: it writes "Invalid third argument to function
    /// SUBSTR", sets _ERROR_=1, and returns the whole REMAINDER of the string.
    /// All three are wrong here: the user wrote a comparison and never called
    /// SUBSTR, the case is merely false rather than erroneous, and the remainder
    /// is the wrong string for a PREFIX compare. SUBSTRN yields the empty prefix
    /// silently. Removes 4 spurious NOTEs from colon_cmplen (stdout unchanged).
    fn mkSubstr(self: *Parser, e: *const ast.Expr, len: *const ast.Expr) Error!*const ast.Expr {
        const args = try self.arena.alloc(ast.Expr, 3);
        args[0] = e.*;
        args[1] = .{ .num = 1 };
        args[2] = len.*;
        return self.mk(.{ .call = .{ .name = "substrn", .args = args } });
    }

    /// `L contains R` → `index(L, R) gt 0`; `L not contains R` → `index(L, R) = 0`.
    /// Mirrors sql.zig:1017 so DATA-step and PROC/SQL WHERE agree.
    fn mkContains(self: *Parser, lhs: *const ast.Expr, rhs: *const ast.Expr, negated: bool) Error!*const ast.Expr {
        const args = try self.arena.alloc(ast.Expr, 2);
        args[0] = lhs.*;
        args[1] = rhs.*;
        const call = try self.mk(.{ .call = .{ .name = "index", .args = args } });
        const zero = try self.mk(.{ .num = 0 });
        return self.mk(.{ .binary = .{ .op = if (negated) .eq else .gt, .lhs = call, .rhs = zero } });
    }

    /// The right operand of IN, `in` already consumed: either an ARRAY NAME —
    /// "You can also use the IN operator to search an array" (Language Reference: Concepts p.128
    /// numeric / p.130 character) — or the parenthesized value list. A name that
    /// is not a declared array falls through, so `x in y` stays the loud
    /// "expected '(' after IN" it was.
    fn parseInRhs(self: *Parser, lhs: *const ast.Expr, negated: bool, truncate: bool) Error!*const ast.Expr {
        const t = self.peek();
        // A subscripted `a{i}` / `a(i)` is an ELEMENT, not the array — not an IN
        // right operand, so leave it to parseInList's loud '(' expectation.
        if (t.tag == .name and self.tokAt(1).tag != .lbrace and self.tokAt(1).tag != .lparen) {
            if (self.lookupArray(t.text)) |def| return self.parseInArray(lhs, def, negated, truncate);
        }
        return self.parseInList(lhs, negated, truncate);
    }

    /// `lhs in a` — membership over array `a`'s elements, the same OR-of-equalities
    /// desugar the value-list form uses (element ORDER cannot matter: the result is
    /// 1 as soon as any element matches, Language Reference: Concepts Example Code 6.2/6.3). Missing and
    /// blank elements are compared like any other value — an all-blank char array
    /// simply never matches a non-blank probe, which is exactly Example Code 6.3.
    fn parseInArray(self: *Parser, lhs: *const ast.Expr, def: ArrayDef, negated: bool, truncate: bool) Error!*const ast.Expr {
        const tok = self.advance(); // the array name
        // `array v{*} _numeric_` members are a runtime fact (GH#48) — expanding
        // them here would silently search the wrong set, so stay loud.
        if (def.special != null or def.elements.len == 0)
            return self.diags.fail(error.ParseError, tok.line, "IN over array {s}: its members are not known until run time", .{tok.text});
        var acc: ?*const ast.Expr = null;
        for (def.elements) |name| {
            const cmp = try self.mkMember(lhs, try self.mk(.{ .variable = name }), negated, truncate);
            acc = if (acc) |prev| try self.mk(.{ .binary = .{
                .op = if (negated) .@"and" else .@"or",
                .lhs = prev,
                .rhs = cmp,
            } }) else cmp;
        }
        return acc.?; // elements.len > 0 was checked above
    }

    /// One IN membership test: `lhs = value` (`ne` when negated), or — for `IN:` —
    /// the prefix-truncated compare, reusing the `=:` implementation so the two
    /// colon forms share ONE prefix compare (including the zero-length rule of
    /// Language Reference: Concepts p.130, which names IN: and EQ: in the same sentence).
    fn mkMember(self: *Parser, lhs: *const ast.Expr, value: *const ast.Expr, negated: bool, truncate: bool) Error!*const ast.Expr {
        if (!truncate) return self.mk(.{ .binary = .{
            .op = if (negated) .ne else .eq,
            .lhs = lhs,
            .rhs = value,
        } });
        // false: `IN:` is DATA-step-only syntax (PROC SQL has no colon modifier
        // at all, SQL Procedure p.405), so the storage-length rule always governs.
        const cmp = try self.mkTruncCmp(.eq, lhs, value, false);
        return if (negated) self.mk(.{ .unary = .{ .op = .not, .operand = cmp } }) else cmp;
    }

    /// `(e1, e2, …)` → `lhs=e1 or lhs=e2 …` (IN), or `lhs<>e1 and lhs<>e2 …`
    /// (NOT IN). An empty list is a SAS syntax error (IN requires ≥1 value).
    /// A `M:N` item enumerates the INTEGERS M..N (Language Reference: Concepts p.128): membership is
    /// `lhs>=M and lhs<=N and floor(lhs)=lhs` — `2.5 in (1:3)` is FALSE
    /// (BUG-inrangecontinuous). Bounds must be integer literals; `(1.5:3)` is
    /// a syntax error. Singletons and ranges mix freely (PG-inrange).
    fn parseInList(self: *Parser, lhs: *const ast.Expr, negated: bool, truncate: bool) Error!*const ast.Expr {
        const in_line = self.peek().line;
        _ = try self.expect(.lparen, "'(' after IN");
        var acc: ?*const ast.Expr = null;
        if (!self.check(.rparen)) {
            while (true) {
                const elem_line = self.peek().line;
                const elem = try self.parseExpr();
                const cmp = if (self.eat(.colon)) blk: {
                    const hi_line = self.peek().line;
                    const hi = try self.parseExpr();
                    // `M:N` enumerates INTEGERS; a prefix-match over a numeric
                    // range is undefined (Language Reference: Concepts documents IN: only as a character
                    // comparison), so refuse rather than invent one.
                    if (truncate)
                        return self.diags.fail(error.ParseError, elem_line, "the IN: prefix modifier does not accept the M:N range form", .{});
                    if (inRangeBound(elem) == null)
                        return self.diags.fail(error.ParseError, elem_line, "IN range bounds must be integers", .{});
                    if (inRangeBound(hi) == null)
                        return self.diags.fail(error.ParseError, hi_line, "IN range bounds must be integers", .{});
                    const ge = try self.mk(.{ .binary = .{ .op = .ge, .lhs = lhs, .rhs = elem } });
                    const le = try self.mk(.{ .binary = .{ .op = .le, .lhs = lhs, .rhs = hi } });
                    const is_int = try self.mk(.{ .binary = .{ .op = .eq, .lhs = lhs, .rhs = try self.mkCall1("floor", lhs) } });
                    const within = try self.mk(.{ .binary = .{ .op = .@"and", .lhs = ge, .rhs = le } });
                    const in_range = try self.mk(.{ .binary = .{ .op = .@"and", .lhs = within, .rhs = is_int } });
                    break :blk if (negated) try self.mk(.{ .unary = .{ .op = .not, .operand = in_range } }) else in_range;
                } else try self.mkMember(lhs, elem, negated, truncate);
                if (acc) |prev| {
                    acc = try self.mk(.{ .binary = .{
                        .op = if (negated) .@"and" else .@"or",
                        .lhs = prev,
                        .rhs = cmp,
                    } });
                } else acc = cmp;
                // SAS accepts a SPACE- or comma-separated IN list — the comma is
                // optional; keep taking elements until the closing ')' (BUG-inspacelist).
                _ = self.eat(.comma);
                if (self.check(.rparen)) break;
            }
        }
        _ = try self.expect(.rparen, "')' to close the IN list");
        return acc orelse self.diags.fail(error.ParseError, in_line, "IN operator requires at least one value", .{});
    }

    /// Integer-literal value of an IN-range bound (`3`, `-3`), else null — SAS
    /// requires M and N of `M:N` to be integers (BUG-inrangecontinuous).
    fn inRangeBound(e: *const ast.Expr) ?f64 {
        const v: f64 = switch (e.*) {
            .num => |n| n,
            .unary => |u| if (u.op == .neg and u.operand.* == .num) -u.operand.num else return null,
            else => return null,
        };
        return if (v == @trunc(v)) v else null;
    }

    fn parseUnary(self: *Parser) Error!*const ast.Expr {
        const t = self.peek();
        switch (t.tag) {
            .minus => {
                _ = self.advance();
                const e = try self.parseBin(prec_pow);
                return self.mk(.{ .unary = .{ .op = .neg, .operand = e } });
            },
            .plus => { // unary plus is identity — no node
                _ = self.advance();
                return self.parseBin(prec_pow);
            },
            .caret => {
                _ = self.advance();
                const e = try self.parseBin(prec_pow);
                return self.mk(.{ .unary = .{ .op = .not, .operand = e } });
            },
            .name => {
                if (std.ascii.eqlIgnoreCase(t.text, "not")) {
                    _ = self.advance();
                    const e = try self.parseBin(prec_pow);
                    return self.mk(.{ .unary = .{ .op = .not, .operand = e } });
                }
                return self.parsePrimary();
            },
            else => return self.parsePrimary(),
        }
    }

    fn parsePrimary(self: *Parser) Error!*const ast.Expr {
        const t = self.peek();
        switch (t.tag) {
            .number => {
                _ = self.advance();
                const n = std.fmt.parseFloat(f64, t.text) catch
                    return self.diags.fail(error.ParseError, t.line, "invalid numeric literal '{s}'", .{t.text});
                return self.mk(.{ .num = n });
            },
            .string => {
                _ = self.advance();
                return self.mk(.{ .str = t.text });
            },
            .dot => {
                _ = self.advance();
                // A `.dot` carrying a letter is a special missing `.A`-`.Z`/`._`
                // (the lexer stamped its letter); a bare `.` is plain missing.
                if (t.text.len > 0) return self.mk(.{ .num = Value.specialMissing(t.text[0]).num });
                return self.mk(.missing);
            },
            .name => {
                // GAP-hashinexpr: `obj.method(…)` / `obj.attr` in expression
                // position — hoist the call (see parseHashExpr). Gated on the
                // statement parser opting in via hashattr_n.
                if (self.hashattr_n) |cnt|
                    if (self.tokAt(1).tag == .dot and self.tokAt(2).tag == .name)
                        return self.parseHashExpr(cnt);
                _ = self.advance();
                if (self.check(.lparen)) {
                    // `a(i)` is an array subscript when `a` is a declared array —
                    // SAS 9.4 allows ()/{}/[] interchangeably (`[`/`{` lex to
                    // .lbrace; `(` stays .lparen for genuine calls). Only divert
                    // when the name resolves to an array; else it's a function
                    // call (GAP-arrayparensubscript).
                    if (self.lookupArray(t.text) != null) return self.parseArrayRef(t);
                    return self.parseCall(t);
                }
                if (self.check(.lbrace)) return self.parseArrayRef(t);
                return self.mk(.{ .variable = t.text });
            },
            .lparen => {
                _ = self.advance();
                const inner = try self.parseExpr();
                _ = try self.expect(.rparen, "')'");
                return inner;
            },
            else => return self.diags.fail(error.ParseError, t.line, "expected an expression", .{}),
        }
    }

    /// The token `k` positions ahead of the cursor (clamped to the trailing
    /// eof, like the statement parser's tokAt).
    fn tokAt(self: *Parser, k: usize) Token {
        const j = self.pos + k;
        return if (j < self.toks.len) self.toks[j] else self.toks[self.toks.len - 1];
    }

    /// `obj.method(args)` / `obj.attr` in expression position (GAP-hashinexpr).
    /// Hoist the call: mint a `__hashattr_N` temp, queue it for the statement
    /// parser to emit as a `hash_op` statement before the enclosing statement,
    /// and read the temp. Nested calls (`h.add(key: h2.find())`) queue inner
    /// first, since the outer is appended only after its args parse.
    fn parseHashExpr(self: *Parser, cnt: *usize) Error!*const ast.Expr {
        const obj = self.advance().text;
        _ = self.advance(); // '.'
        const method = (try self.expect(.name, "a hash method")).text;
        const args: []ast.HashArg = if (self.eat(.lparen)) try self.parseHashArgs() else &.{};
        cnt.* += 1;
        const tmp = try std.fmt.allocPrint(self.arena, "__hashattr_{d}", .{cnt.*});
        try self.hash_hoists.append(self.arena, .{ .target = tmp, .obj = obj, .method = method, .args = args });
        return self.mk(.{ .variable = tmp });
    }

    /// Method arguments up to and including the closing `)`: `key: 1` (named)
    /// or `"k"` / `x` (positional). Shared by the statement parser's hash-op
    /// forms and parseHashExpr above.
    pub fn parseHashArgs(self: *Parser) Error![]ast.HashArg {
        var args: std.ArrayList(ast.HashArg) = .empty;
        while (!self.check(.rparen) and !self.check(.eof)) {
            var argname: ?[]const u8 = null;
            if (self.check(.name) and self.tokAt(1).tag == .colon) {
                argname = self.advance().text;
                _ = self.advance(); // ':'
            }
            const value = try self.parseExpr();
            try args.append(self.arena, .{ .name = argname, .value = value });
            if (!self.eat(.comma)) break;
        }
        _ = try self.expect(.rparen, "')' to close hash method arguments");
        return args.toOwnedSlice(self.arena);
    }

    /// Parse `{ i [, j …] }` (the `{` NOT yet consumed) and fold the subscript
    /// list against the named array's dimensions into ONE flat index. Rank
    /// mismatch fails loud (GAP-multidimarray). Shared by array reads, subscripted
    /// assignment lvalues, and `put a{i}`.
    pub fn parseArraySubscript(self: *Parser, name_tok: Token) Error!struct { def: ArrayDef, index: *const ast.Expr } {
        // Opener picks the closer: `(` closes on `)`, `{`/`[` on `}`/`]` (both lex
        // to lbrace/rbrace). SAS treats the three bracket styles as interchangeable
        // for array subscripting (GAP-arrayparensubscript).
        const paren = self.check(.lparen);
        _ = self.advance(); // consume '(' / '{' / '['
        var indices: std.ArrayList(*const ast.Expr) = .empty;
        while (true) {
            try indices.append(self.arena, try self.parseExpr());
            if (!self.eat(.comma)) break;
        }
        if (paren)
            _ = try self.expect(.rparen, "')' to close array subscript")
        else
            _ = try self.expect(.rbrace, "'}}' to close array subscript");
        const def = self.lookupArray(name_tok.text) orelse
            return self.diags.fail(error.ParseError, name_tok.line, "{s} is not a declared array", .{name_tok.text});
        // A special-list array (`array v{*} _numeric_;`) is 1-D and dynamic — keep
        // its single subscript verbatim (resolved against the live PDV at eval).
        if (def.special != null) return .{ .def = def, .index = indices.items[0] };
        if (indices.items.len != def.dims.len)
            return self.diags.fail(error.ParseError, name_tok.line, "array {s}: {d} subscript(s) given for a {d}-dimensional array", .{ name_tok.text, indices.items.len, def.dims.len });
        return .{ .def = def, .index = try self.arraySubscript(name_tok, indices.items, def.dims) };
    }

    /// `a{ i[,j] }` — resolve `a` to its members and fold the subscript(s).
    fn parseArrayRef(self: *Parser, name_tok: Token) Error!*const ast.Expr {
        const r = try self.parseArraySubscript(name_tok);
        return self.mk(.{ .array_ref = .{ .name = name_tok.text, .elements = r.def.elements, .index = r.index, .special = r.def.special, .line = name_tok.line } });
    }

    fn parseCall(self: *Parser, name_tok: Token) Error!*const ast.Expr {
        _ = self.advance(); // consume '('
        var args: std.ArrayList(ast.Expr) = .empty;
        if (!self.check(.rparen)) {
            while (true) {
                // INPUT error-suppression modifier `?`/`??` precedes the informat
                // arg (`input(x, ?? best.)`): `?` skips the invalid-data message, `??`
                // also skips _ERROR_. opensas input() is already silent-missing on bad
                // data, so drop the marker and parse the informat/expr that follows
                // (works for name informats AND numeric `w.d` — BUG-inputqq).
                while (self.check(.question)) _ = self.advance();
                // an omitted positional arg (`compress(x, , "kd")`) — the slot
                // before a comma or `)` is empty. Emit an empty-string default so
                // the arg *count* is preserved (the function decides how to
                // default it: e.g. compress's char set becomes empty).
                if (self.check(.comma) or self.check(.rparen)) {
                    try args.append(self.arena, .{ .str = "" });
                }
                // an informat argument (`input(x, date9.)`) is a name followed by
                // a dot — not a valid expression, so reconstruct it as a string.
                else if (try self.tryInformatSpec()) |spec| {
                    try args.append(self.arena, .{ .str = spec });
                } else {
                    const arg = try self.parseExpr();
                    try args.append(self.arena, arg.*);
                }
                if (!self.eat(.comma)) break;
            }
        }
        _ = try self.expect(.rparen, "')' to close function call");
        // dim/hbound/lbound(array [, d]): a named array's size is a compile-time
        // fact only the parser holds, so resolve the array-name argument to its
        // element count here; functions.zig turns that into the bound. (opensas dim)
        // A SPECIAL-LIST array (`array v{*} _numeric_;`) has no parse-time count —
        // leave the arg as an `array_ref` carrying its `special` kind so the
        // evaluator counts the matching PDV vars at runtime (GH#48).
        if (isBoundFn(name_tok.text) and args.items.len >= 1) {
            const arr_name: ?[]const u8 = switch (args.items[0]) {
                .variable => |v| v,
                else => null,
            };
            if (arr_name) |nm| {
                // BUG-dimnonarray: the name isn't a registered array (a scalar
                // typo like `dim(cnt)`, or an array renamed without updating the
                // call). Without this guard the variable sailed through to
                // charfns' generic handler, which returned its VALUE as the
                // "bound" — silent-wrong. SAS: the argument must be an ARRAY name.
                const def = self.lookupArray(nm) orelse
                    return self.diags.fail(error.ParseError, name_tok.line, "{s}: the argument must be an ARRAY name; {s} is not a declared array", .{ name_tok.text, nm });
                if (def.special) |k| {
                    args.items[0] = .{ .array_ref = .{ .name = nm, .elements = def.elements, .index = try self.mk(.{ .num = 1 }), .special = k } };
                } else if (def.dims.len > 1 or def.dims[0].lo != 1) {
                    // Explicit lower bound / multi-dim: charfns' bound folder assumes a
                    // 1-based 1-D array, so fold the answer here where the per-dimension
                    // lo/size are known (ARRAY-lobound / GAP-multidimarray). The optional
                    // 2nd arg picks the dimension k (1-based, default 1); it must be a
                    // parse-time constant — a dynamic k on such an array isn't supported.
                    var kdim: usize = 1;
                    if (args.items.len >= 2) {
                        if (args.items[1] == .num) kdim = @intFromFloat(args.items[1].num) else {
                            // `dim(arr, k)` with a runtime k is valid SAS 9.4 we don't
                            // fold — an opensas gap → exit 2 (D-009; parser.failGap's twin).
                            diag.markGap();
                            return self.diags.fail(error.ParseError, name_tok.line, "{s}: a non-constant dimension index is not supported for array {s}", .{ name_tok.text, nm });
                        }
                    }
                    if (kdim < 1 or kdim > def.dims.len)
                        return self.diags.fail(error.ParseError, name_tok.line, "{s}: dimension {d} is out of range for array {s} ({d} dimension(s))", .{ name_tok.text, kdim, nm, def.dims.len });
                    const d = def.dims[kdim - 1];
                    const size: i64 = @intCast(d.size);
                    const val: f64 = if (std.ascii.eqlIgnoreCase(name_tok.text, "lbound"))
                        @floatFromInt(d.lo)
                    else if (std.ascii.eqlIgnoreCase(name_tok.text, "hbound"))
                        @floatFromInt(d.lo + size - 1)
                    else
                        @floatFromInt(size); // dim
                    return self.mk(.{ .num = val });
                } else {
                    args.items[0] = .{ .num = @floatFromInt(def.elements.len) };
                }
            }
        }
        return self.mk(.{ .call = .{
            .name = name_tok.text,
            .args = try args.toOwnedSlice(self.arena),
        } });
    }

    /// If the cursor is at an informat spec — `[$] NAME (. | .digits)`, e.g.
    /// `date9.`, `yymmdd10.`, `comma8.2` (which tokenize unevenly) — consume it
    /// and return the reconstructed spec string; else consume nothing, return
    /// null. A bare name or number is not an informat (left to `parseExpr`).
    fn tryInformatSpec(self: *Parser) Error!?[]const u8 {
        var j = self.pos;
        if (j >= self.toks.len) return null; // truncated call at EOF (`sum(of` — BUG-ofcrashtruncated-2): guard before the toks[j] index, matching peek()'s clamp
        const has_dollar = self.toks[j].tag == .dollar;
        if (has_dollar) j += 1;
        if (j >= self.toks.len) return null;
        // Two shapes after the optional `$`:
        //   NAME [. | .digits]  — date9., comma8.2, $char100. (name-based format)
        //   NUMBER              — $100., $8. (dollar-width char format `$w.[d]`); the
        //                         lexer folds "100." into one number token. Requires
        //                         the `$` — a bare numeric format (`8.2`) is left to
        //                         parseExpr, unchanged (BUG-putcharfmt).
        if (self.toks[j].tag == .name) {
            const after = if (j + 1 < self.toks.len) self.toks[j + 1] else self.toks[self.toks.len - 1];
            const is_inf = after.tag == .dot or (after.tag == .number and after.text.len > 0 and after.text[0] == '.');
            if (!is_inf) return null;
            // GAP-hashinexpr, function-argument slot: `NAME . NAME` is never an
            // informat — a spec ENDS at its '.' (`date9.`) or carries digits
            // (`comma8.2`), so a name after the dot cannot belong to it. Left
            // to the greedy grab above, `sum(h.num_items, 1)` was read as the
            // spec "h." and then blamed the paren ("expected ')' to close
            // function call") while `if h.find() = 0` — the SAME operand one
            // position over — already parsed. Hand the shape back to
            // parsePrimary, which routes it to parseHashExpr. Declared librefs
            // are folded to ONE token upstream (main.coalesceLibrefs), so this
            // cannot steal a `lib.member`. Gated on hashattr_n like
            // parsePrimary's arm, so WHERE/SQL sub-parsers are untouched.
            // ponytail: a LIBRARY-QUALIFIED informat (`input(x, lib.fmt.)`) also
            // matches NAME.NAME and now takes the hash path — but informat_ref
            // has no qualified form in the grammar, so it was a loud parse error
            // before this and is a loud "hash object lib is not declared" after;
            // ceiling is the error WORDING, not acceptance. Add a
            // `toks[j+3] != .dot` term here if catalog informats ever land.
            if (self.hashattr_n != null and !has_dollar and
                (if (j + 2 < self.toks.len) self.toks[j + 2].tag == .name else false)) return null;
        } else if (!(has_dollar and self.toks[j].tag == .number)) {
            return null;
        }

        var buf: std.ArrayList(u8) = .empty;
        if (has_dollar) {
            _ = self.advance();
            try buf.append(self.arena, '$');
        }
        try buf.appendSlice(self.arena, self.advance().text); // NAME ("date9") or width ("100.")
        if (self.check(.dot)) {
            _ = self.advance();
            try buf.append(self.arena, '.');
        } else if (self.check(.number)) {
            try buf.appendSlice(self.arena, self.advance().text); // ".d" decimals
        }
        return buf.items;
    }

    fn peekBinOp(self: *Parser) ?OpInfo {
        const t = self.peek();
        return switch (t.tag) {
            .pipe => .{ .op = .@"or", .prec = 1, .right = false },
            .amp => .{ .op = .@"and", .prec = 2, .right = false },
            .eq => .{ .op = .eq, .prec = 3, .right = false },
            .ne => .{ .op = .ne, .prec = 3, .right = false },
            .lt => .{ .op = .lt, .prec = 3, .right = false },
            .le => .{ .op = .le, .prec = 3, .right = false },
            .gt => .{ .op = .gt, .prec = 3, .right = false },
            .ge => .{ .op = .ge, .prec = 3, .right = false },
            .concat => .{ .op = .concat, .prec = 4, .right = false },
            .plus => .{ .op = .add, .prec = 5, .right = false },
            .minus => .{ .op = .sub, .prec = 5, .right = false },
            .star => .{ .op = .mul, .prec = 6, .right = false },
            .slash => .{ .op = .div, .prec = 6, .right = false },
            .star2 => .{ .op = .pow, .prec = prec_pow, .right = true },
            .min_op => .{ .op = .min, .prec = prec_minmax, .right = true },
            // WHERE context: `<>` is NE (comparison prec) — only the SYMBOLS are
            // WHERE-special (`><` errors in parseBin); the MIN/MAX word forms are
            // ordinary Group-I operators in a WHERE too (Language Reference: Concepts p.225, GAP-whereminmax).
            .max_op => if (self.where_ctx)
                .{ .op = .ne, .prec = 3, .right = false }
            else
                .{ .op = .max, .prec = prec_minmax, .right = true },
            .name => mnemonicOp(t.text),
            else => null,
        };
    }

    fn mk(self: *Parser, e: ast.Expr) Error!*const ast.Expr {
        const p = try self.arena.create(ast.Expr);
        p.* = e;
        return p;
    }
};

/// A comparison operator — the ops that chain SAS-style (QA-chaincmp).
fn isCmpOp(op: ast.BinOp) bool {
    return switch (op) {
        .eq, .ne, .lt, .le, .gt, .ge => true,
        else => false,
    };
}

/// The array-bounds functions, whose first argument is an array NAME the parser
/// resolves to an element count (arrays don't exist at eval time).
fn isBoundFn(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "dim") or
        std.ascii.eqlIgnoreCase(name, "hbound") or
        std.ascii.eqlIgnoreCase(name, "lbound");
}

/// SAS word-form operators (case-insensitive). `NOT` is handled as a prefix in
/// `parseUnary`, not here. A `name` that is none of these is a plain variable.
fn mnemonicOp(text: []const u8) ?OpInfo {
    const eqi = std.ascii.eqlIgnoreCase;
    if (eqi(text, "eq")) return .{ .op = .eq, .prec = 3, .right = false };
    if (eqi(text, "ne")) return .{ .op = .ne, .prec = 3, .right = false };
    if (eqi(text, "lt")) return .{ .op = .lt, .prec = 3, .right = false };
    if (eqi(text, "le")) return .{ .op = .le, .prec = 3, .right = false };
    if (eqi(text, "gt")) return .{ .op = .gt, .prec = 3, .right = false };
    if (eqi(text, "ge")) return .{ .op = .ge, .prec = 3, .right = false };
    if (eqi(text, "and")) return .{ .op = .@"and", .prec = 2, .right = false };
    if (eqi(text, "or")) return .{ .op = .@"or", .prec = 1, .right = false };
    // Infix MIN/MAX operators (GAP-minmaxop). Only reached in operator position —
    // a `min(a,b)`/`max(a,b)` function call is consumed in parsePrimary first.
    if (eqi(text, "min")) return .{ .op = .min, .prec = prec_minmax, .right = true };
    if (eqi(text, "max")) return .{ .op = .max, .prec = prec_minmax, .right = true };
    return null;
}

test "=* sounds-like desugars to soundex(L) = soundex(R) (GAP-soundslike)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `x =* 'Smith'` → eq(soundex(x), soundex('Smith')).
    const e = try parseSrc(a, &diags, "x =* 'Smith'");
    try std.testing.expect(e.binary.op == .eq);
    try std.testing.expectEqualStrings("soundex", e.binary.lhs.call.name);
    try std.testing.expect(e.binary.lhs.call.args[0] == .variable);
    try std.testing.expectEqualStrings("soundex", e.binary.rhs.call.name);

    // comparison precedence: `1 + 2 =* x` → soundex(1+2) = soundex(x).
    const f = try parseSrc(a, &diags, "1 + 2 =* x");
    try std.testing.expect(f.binary.op == .eq);
    try std.testing.expect(f.binary.lhs.call.args[0].binary.op == .add);

    // plain `=` untouched: `x = 1` stays a bare eq.
    const g = try parseSrc(a, &diags, "x = 1");
    try std.testing.expect(g.binary.op == .eq);
    try std.testing.expect(g.binary.lhs.* == .variable);
}

test "infix NOT + comparison desugars to the negated op (GAP-wherenotinfix)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `x not eq 4` → ne(x, 4); word and symbol forms agree.
    try std.testing.expect((try parseSrc(a, &diags, "x not eq 4")).binary.op == .ne);
    try std.testing.expect((try parseSrc(a, &diags, "x not = 4")).binary.op == .ne);
    // the full negation table
    try std.testing.expect((try parseSrc(a, &diags, "x not ne 4")).binary.op == .eq);
    try std.testing.expect((try parseSrc(a, &diags, "x not lt 4")).binary.op == .ge);
    try std.testing.expect((try parseSrc(a, &diags, "x not le 4")).binary.op == .gt);
    try std.testing.expect((try parseSrc(a, &diags, "x not gt 4")).binary.op == .le);
    try std.testing.expect((try parseSrc(a, &diags, "x not ge 4")).binary.op == .lt);

    // `x not =* 'Smith'` → ne(soundex(x), soundex('Smith')).
    const s = try parseSrc(a, &diags, "x not =* 'Smith'");
    try std.testing.expect(s.binary.op == .ne);
    try std.testing.expectEqualStrings("soundex", s.binary.lhs.call.name);
    try std.testing.expectEqualStrings("soundex", s.binary.rhs.call.name);

    // a PREFIX not keeps SAS precedence: `not x eq 4` → eq(not(x), 4).
    const p = try parseSrc(a, &diags, "not x eq 4");
    try std.testing.expect(p.binary.op == .eq);
    try std.testing.expect(p.binary.lhs.* == .unary);

    // `not` before a non-comparison word is not this form: `x not and y`
    // leaves the `not` unconsumed (loud leftover for the statement parser).
    var q = Parser.init(a, try lexer.tokenize(a, "x not and y", &diags), &diags);
    _ = try q.parseExpr();
    try std.testing.expect(q.peek().tag == .name);
}

fn parseSrc(arena: std.mem.Allocator, diags: *diag.Diagnostics, src: []const u8) Error!*const ast.Expr {
    const toks = try lexer.tokenize(arena, src, diags);
    var p = Parser.init(arena, toks, diags);
    return p.parseExpr();
}

test "minmax operators: >< / <> and MIN/MAX bind at Group I (GAP-minmaxop)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `2 * 3 >< 4` → mul(2, min(3, 4)): >< binds tighter than *.
    const e = try parseSrc(a, &diags, "2 * 3 >< 4");
    try std.testing.expect(e.binary.op == .mul);
    try std.testing.expect(e.binary.rhs.binary.op == .min);

    // `10 >< 2 ** 3` → min(10, pow(2, 3)): ** binds tighter than ><.
    const f = try parseSrc(a, &diags, "10 >< 2 ** 3");
    try std.testing.expect(f.binary.op == .min);
    try std.testing.expect(f.binary.rhs.binary.op == .pow);

    // `<>` → max; word forms map to the same ops.
    try std.testing.expect((try parseSrc(a, &diags, "5 <> 3")).binary.op == .max);
    try std.testing.expect((try parseSrc(a, &diags, "5 min 3")).binary.op == .min);
    try std.testing.expect((try parseSrc(a, &diags, "5 max 3")).binary.op == .max);

    // right-assoc (Group I evaluates right-to-left): `9 >< 4 >< 7` → min(9, min(4,7)).
    const g = try parseSrc(a, &diags, "9 >< 4 >< 7");
    try std.testing.expect(g.binary.op == .min);
    try std.testing.expect(g.binary.rhs.binary.op == .min);

    // a min()/max() call still parses as a function, not the operator.
    try std.testing.expect((try parseSrc(a, &diags, "min(5, 3)")).call.args.len == 2);

    // BUG-minmaxprec: **, unary and minmax are ONE right-to-left group.
    // `2 ** 3 <> 4` → pow(2, max(3,4)) — the rightmost operator binds first.
    const h = try parseSrc(a, &diags, "2 ** 3 <> 4");
    try std.testing.expect(h.binary.op == .pow);
    try std.testing.expect(h.binary.rhs.binary.op == .max);
    // `-2 <> 3` → neg(max(2,3)), same rule as -2**2 = -(2**2).
    const i = try parseSrc(a, &diags, "-2 <> 3");
    try std.testing.expect(i.unary.op == .neg);
    try std.testing.expect(i.unary.operand.binary.op == .max);
}

test "where context: <> is NE, >< errors, word MIN/MAX stay operators (BUG-wherene, GAP-whereminmax)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    var p = Parser.init(a, try lexer.tokenize(a, "x <> 3", &diags), &diags);
    p.where_ctx = true;
    try std.testing.expect((try p.parseExpr()).binary.op == .ne);

    // `><` is not valid in a WHERE expression — loud, not a silent MIN.
    var q = Parser.init(a, try lexer.tokenize(a, "x >< 3", &diags), &diags);
    q.where_ctx = true;
    try std.testing.expectError(error.ParseError, q.parseExpr());

    // The word forms ARE operators in a WHERE (Language Reference: Concepts p.225) — only the symbols
    // are WHERE-special. `x max 3` → max(x, 3), `a min b` → min(a, b).
    var r = Parser.init(a, try lexer.tokenize(a, "x max 3", &diags), &diags);
    r.where_ctx = true;
    try std.testing.expect((try r.parseExpr()).binary.op == .max);
    var s = Parser.init(a, try lexer.tokenize(a, "a min b", &diags), &diags);
    s.where_ctx = true;
    try std.testing.expect((try s.parseExpr()).binary.op == .min);
    // a variable NAMED min/max in operand position is untouched (`min > 3`).
    var v = Parser.init(a, try lexer.tokenize(a, "min > 3", &diags), &diags);
    v.where_ctx = true;
    const ve = try v.parseExpr();
    try std.testing.expect(ve.binary.op == .gt);
    try std.testing.expectEqualStrings("min", ve.binary.lhs.variable);
}

test "where CONTAINS / ? desugar to index()>0; rejected outside where (GH#16)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `x contains "b"` → index(x, "b") gt 0
    var p = Parser.init(a, try lexer.tokenize(a, "x contains \"b\"", &diags), &diags);
    p.where_ctx = true;
    const e = try p.parseExpr();
    try std.testing.expect(e.binary.op == .gt);
    try std.testing.expectEqualStrings("index", e.binary.lhs.call.name);
    try std.testing.expectEqual(@as(usize, 2), e.binary.lhs.call.args.len);
    try std.testing.expectEqual(@as(f64, 0), e.binary.rhs.num);

    // `?` is the synonym → same shape
    var q = Parser.init(a, try lexer.tokenize(a, "x ? \"b\"", &diags), &diags);
    q.where_ctx = true;
    try std.testing.expect((try q.parseExpr()).binary.op == .gt);

    // `not contains` → index() eq 0
    var r = Parser.init(a, try lexer.tokenize(a, "x not contains \"b\"", &diags), &diags);
    r.where_ctx = true;
    try std.testing.expect((try r.parseExpr()).binary.op == .eq);

    // WHERE-only: outside where_ctx the operator is unknown, expression stops at x
    var s = Parser.init(a, try lexer.tokenize(a, "x contains \"b\"", &diags), &diags);
    try std.testing.expect((try s.parseExpr()).* == .variable);
}

test "colon-modified comparison desugars to substrn(both,1,min(lengthc both)) op (GH#29, BUG-coloncmplen, NOTE-truncsubstrnote)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `x =: 'T'` → min(length(x),length('T'))>0 AND
    // substr(x,1,min(lengthc(x),lengthc('T'))) = substr('T',1,min(...))
    // (the and-guard is BUG-coloncmpempty: a zero-length EQ: is always 0,
    // Language Reference: Concepts p.130).
    const e = try parseSrc(a, &diags, "x =: 'T'");
    try std.testing.expect(e.binary.op == .@"and");
    try std.testing.expect(e.binary.lhs.binary.op == .gt); // min(lengthn) > 0
    try std.testing.expectEqualStrings("lengthn", e.binary.lhs.binary.lhs.call.args[0].call.name);
    const eqe = e.binary.rhs;
    try std.testing.expect(eqe.binary.op == .eq);
    try std.testing.expectEqualStrings("substrn",eqe.binary.lhs.call.name);
    try std.testing.expectEqualStrings("x", eqe.binary.lhs.call.args[0].variable);
    try std.testing.expectEqual(@as(f64, 1), eqe.binary.lhs.call.args[1].num);
    const mn = eqe.binary.lhs.call.args[2].call;
    try std.testing.expectEqualStrings("min", mn.name);
    try std.testing.expectEqualStrings("lengthc", mn.args[0].call.name);
    try std.testing.expectEqualStrings("x", mn.args[0].call.args[0].variable);
    try std.testing.expectEqualStrings("lengthc", mn.args[1].call.name);
    try std.testing.expectEqualStrings("T", mn.args[1].call.args[0].str);
    // RHS is cut to the same min too — `"ca" =: "cat"` truncates the LONGER (RHS).
    try std.testing.expectEqualStrings("substrn",eqe.binary.rhs.call.name);
    try std.testing.expectEqualStrings("T", eqe.binary.rhs.call.args[0].str);

    // symbolic `^=:`, mnemonic `ne:` map to the plain shape (guard is eq-only);
    // `eq:` gets the and-guard; `>=:` stays truncation-defined.
    try std.testing.expect((try parseSrc(a, &diags, "x ^=: 'T'")).binary.op == .ne);
    try std.testing.expect((try parseSrc(a, &diags, "x ne: 'T'")).binary.op == .ne);
    try std.testing.expect((try parseSrc(a, &diags, "x eq: 'T'")).binary.op == .@"and");
    try std.testing.expect((try parseSrc(a, &diags, "x >=: 'T'")).binary.op == .ge);

    // no colon → still a plain comparison (regression guard)
    try std.testing.expect((try parseSrc(a, &diags, "x = 'T'")).binary.op == .eq);
}

test "precedence: 1 + 2 * 3 → add(1, mul(2, 3))" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const e = try parseSrc(a, &diags, "1 + 2 * 3");
    try std.testing.expect(e.binary.op == .add);
    try std.testing.expectEqual(@as(f64, 1), e.binary.lhs.num);
    try std.testing.expect(e.binary.rhs.binary.op == .mul);
    try std.testing.expectEqual(@as(f64, 2), e.binary.rhs.binary.lhs.num);
}

test "** is right-associative: 2 ** 3 ** 2 → pow(2, pow(3, 2))" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const e = try parseSrc(a, &diags, "2 ** 3 ** 2");
    try std.testing.expect(e.binary.op == .pow);
    try std.testing.expectEqual(@as(f64, 2), e.binary.lhs.num);
    try std.testing.expect(e.binary.rhs.binary.op == .pow);
    try std.testing.expectEqual(@as(f64, 3), e.binary.rhs.binary.lhs.num);
}

test "unary minus binds looser than **: -2 ** 2 → neg(pow(2, 2))" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const e = try parseSrc(a, &diags, "-2 ** 2");
    try std.testing.expect(e.unary.op == .neg);
    try std.testing.expect(e.unary.operand.binary.op == .pow);
}

test "call with args and the lone-dot missing literal: sum(a, b, .)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const e = try parseSrc(a, &diags, "sum(a, b, .)");
    try std.testing.expectEqualStrings("sum", e.call.name);
    try std.testing.expectEqual(@as(usize, 3), e.call.args.len);
    try std.testing.expectEqualStrings("a", e.call.args[0].variable);
    try std.testing.expect(e.call.args[2] == .missing);
}

test "omitted positional arg is an empty-string slot, count preserved (ARGS-empty)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // middle omitted: compress(x, , "kd") → 3 args, [1] an empty default
    const e = try parseSrc(a, &diags, "compress(x, , \"kd\")");
    try std.testing.expectEqual(@as(usize, 3), e.call.args.len);
    try std.testing.expectEqualStrings("x", e.call.args[0].variable);
    try std.testing.expectEqualStrings("", e.call.args[1].str);
    try std.testing.expectEqualStrings("kd", e.call.args[2].str);

    // leading and trailing omitted slots both parse
    const e2 = try parseSrc(a, &diags, "f(, b)");
    try std.testing.expectEqual(@as(usize, 2), e2.call.args.len);
    try std.testing.expectEqualStrings("", e2.call.args[0].str);
    try std.testing.expectEqualStrings("b", e2.call.args[1].variable);

    const e3 = try parseSrc(a, &diags, "g(a, )");
    try std.testing.expectEqual(@as(usize, 2), e3.call.args.len);
    try std.testing.expectEqualStrings("", e3.call.args[1].str);
}

test "informat argument reconstructs into a string literal (INFEXPR)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `date9.` (name+dot) and `comma8.2` (name+".2") are informats, not exprs
    const e = try parseSrc(a, &diags, "input(x, date9.)");
    try std.testing.expectEqualStrings("input", e.call.name);
    try std.testing.expectEqual(@as(usize, 2), e.call.args.len);
    try std.testing.expectEqualStrings("x", e.call.args[0].variable);
    try std.testing.expectEqualStrings("date9.", e.call.args[1].str);

    const e2 = try parseSrc(a, &diags, "input(s, comma8.2)");
    try std.testing.expectEqualStrings("comma8.2", e2.call.args[1].str);

    // a plain name arg is NOT mistaken for an informat
    const e3 = try parseSrc(a, &diags, "max(p, q)");
    try std.testing.expectEqualStrings("q", e3.call.args[1].variable);
}

test "IN desugars to OR of equalities; NOT IN to AND of inequalities (WHIN)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // x in (1,2,3) → (x=1 or x=2) or x=3
    const e = try parseSrc(a, &diags, "x in (1, 2, 3)");
    try std.testing.expect(e.binary.op == .@"or");
    try std.testing.expect(e.binary.rhs.binary.op == .eq);
    try std.testing.expectEqual(@as(f64, 3), e.binary.rhs.binary.rhs.num);
    try std.testing.expect(e.binary.lhs.binary.op == .@"or");
    try std.testing.expectEqualStrings("x", e.binary.rhs.binary.lhs.variable);

    // g not in ("A","B") → g^=A and g^=B
    const e2 = try parseSrc(a, &diags, "g not in (\"A\", \"B\")");
    try std.testing.expect(e2.binary.op == .@"and");
    try std.testing.expect(e2.binary.lhs.binary.op == .ne);
    try std.testing.expectEqualStrings("A", e2.binary.lhs.binary.rhs.str);
    try std.testing.expectEqualStrings("B", e2.binary.rhs.binary.rhs.str);

    // empty list: x in () is a syntax error (BUG-inrangecontinuous)
    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "x in ()"));
    try std.testing.expect(diags.hasErrors());

    // IN binds tighter than AND: a and x in (1,2) → a and (x=1 or x=2)
    const e4 = try parseSrc(a, &diags, "a and x in (1, 2)");
    try std.testing.expect(e4.binary.op == .@"and");
    try std.testing.expect(e4.binary.rhs.binary.op == .@"or");
}

test "IN M:N range enumerates integers M..N; mixes with singletons (BUG-inrangecontinuous, PG-inrange)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // x in (1:3) → ((x>=1) and (x<=3)) and (x = floor(x)) — integer-enumerated
    // (Language Reference: Concepts p.128): 2.5 in (1:3) is FALSE.
    const e = try parseSrc(a, &diags, "x in (1:3)");
    try std.testing.expect(e.binary.op == .@"and");
    try std.testing.expect(e.binary.lhs.binary.op == .@"and");
    try std.testing.expect(e.binary.lhs.binary.lhs.binary.op == .ge);
    try std.testing.expectEqual(@as(f64, 1), e.binary.lhs.binary.lhs.binary.rhs.num);
    try std.testing.expect(e.binary.lhs.binary.rhs.binary.op == .le);
    try std.testing.expectEqual(@as(f64, 3), e.binary.lhs.binary.rhs.binary.rhs.num);
    try std.testing.expect(e.binary.rhs.binary.op == .eq);
    try std.testing.expectEqualStrings("floor", e.binary.rhs.binary.rhs.call.name);

    // mixed range + singleton: x in (1:3, 5) → (range) or x=5
    const e2 = try parseSrc(a, &diags, "x in (1:3, 5)");
    try std.testing.expect(e2.binary.op == .@"or");
    try std.testing.expect(e2.binary.lhs.binary.op == .@"and");
    try std.testing.expect(e2.binary.rhs.binary.op == .eq);
    try std.testing.expectEqual(@as(f64, 5), e2.binary.rhs.binary.rhs.num);

    // negative-integer bounds are fine: x in (-3:0)
    const e3 = try parseSrc(a, &diags, "x in (-3:0)");
    try std.testing.expect(e3.binary.op == .@"and");

    // NOT IN a range → not(range), combined with AND
    const e4 = try parseSrc(a, &diags, "x not in (1:3)");
    try std.testing.expect(e4.unary.op == .not);
    try std.testing.expect(e4.unary.operand.binary.op == .@"and");
}

test "IN range with a non-integer bound fails loud (BUG-inrangecontinuous)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var d1 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, parseSrc(a, &d1, "x in (1.5:3)"));
    try std.testing.expect(d1.hasErrors());

    var d2 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, parseSrc(a, &d2, "x in (1:3.5)"));
    try std.testing.expect(d2.hasErrors());

    // a non-literal bound (variable/expression) is not an integer literal either
    var d3 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, parseSrc(a, &d3, "x in (lo:3)"));
    try std.testing.expect(d3.hasErrors());

    var d4 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, parseSrc(a, &d4, "x in ()"));
    try std.testing.expect(d4.hasErrors());
    var d5 = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, parseSrc(a, &d5, "x not in ()"));
    try std.testing.expect(d5.hasErrors());
}

test "mnemonic op + prefix NOT: a and not b → and(a, not b)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const e = try parseSrc(a, &diags, "a and not b");
    try std.testing.expect(e.binary.op == .@"and");
    try std.testing.expectEqualStrings("a", e.binary.lhs.variable);
    try std.testing.expect(e.binary.rhs.unary.op == .not);
    try std.testing.expectEqualStrings("b", e.binary.rhs.unary.operand.variable);
}

test "parens override precedence, concat, comparison" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    const e1 = try parseSrc(a, &diags, "(1 + 2) * 3");
    try std.testing.expect(e1.binary.op == .mul);
    try std.testing.expect(e1.binary.lhs.binary.op == .add);

    const e2 = try parseSrc(a, &diags, "'a' || 'b'");
    try std.testing.expect(e2.binary.op == .concat);
    try std.testing.expectEqualStrings("a", e2.binary.lhs.str);

    const e3 = try parseSrc(a, &diags, "x >= 3");
    try std.testing.expect(e3.binary.op == .ge);
}

test "deep-nested parens fail loud past the ceiling, not a segfault (BUG-parser-deepnest)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // Build `((((…1…))))` a few hundred levels past the ceiling — the guard
    // trips (returning error.ParseError) long before the native stack does.
    const n = Parser.max_depth + 200;
    var src: std.ArrayList(u8) = .empty;
    try src.appendNTimes(a, '(', n);
    try src.append(a, '1');
    try src.appendNTimes(a, ')', n);

    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, src.items));
    try std.testing.expect(diags.hasErrors());

    // A normally-nested expression is unaffected (regression guard).
    var ok = diag.Diagnostics.init(a);
    const e = try parseSrc(a, &ok, "((((1 + 2))))");
    try std.testing.expect(e.binary.op == .add);
}

test "truncated of-list fails loud instead of panicking (BUG-ofcrashtruncated)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `sum(of a` with no closing paren: the token-level of-list rewrite
    // (parser.zig expandOf) drops the trailing .eof when the list runs to
    // end-of-input, so the expression parser receives a slice with NO sentinel
    // and the old peek() indexed past the array (panic/SIGABRT). The clamped
    // peek turns it into the same loud ParseError as any truncated call.
    const full = try lexer.tokenize(a, "sum(a", &diags);
    try std.testing.expect(full[full.len - 1].tag == .eof);
    var p = Parser.init(a, full[0 .. full.len - 1], &diags); // sentinel stripped
    try std.testing.expectError(error.ParseError, p.parseExpr());
    try std.testing.expect(diags.hasErrors());

    // eof-terminated slices are untouched: `sum(of a b c)` expands upstream to
    // sum(a, b, c) and parses exactly as before (end-to-end output pinned by
    // tests/corpus/of_sum_list.sas).
    var ok = diag.Diagnostics.init(a);
    const e = try parseSrc(a, &ok, "sum(a, b, c)");
    try std.testing.expectEqualStrings("sum", e.call.name);
    try std.testing.expectEqual(@as(usize, 3), e.call.args.len);
    try std.testing.expect(!ok.hasErrors());
}

test "truncated of-list at the informat-spec probe fails loud, not SIGABRT (BUG-ofcrashtruncated-2)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `sum(of` at end-of-input: after the token-level of-list rewrite drops the
    // trailing .eof, parseCall consumes `(` and lands the cursor AT toks.len,
    // then probes tryInformatSpec — which indexed self.toks[j] (j = self.pos)
    // before its own bounds guard (SIGABRT). Reproduce that exact cursor state
    // by stripping the sentinel from `sum(`: tryInformatSpec is entered with
    // self.pos == toks.len. The added guard turns it into a loud ParseError.
    const full = try lexer.tokenize(a, "sum(", &diags);
    try std.testing.expect(full[full.len - 1].tag == .eof);
    var p = Parser.init(a, full[0 .. full.len - 1], &diags); // sentinel stripped
    try std.testing.expectError(error.ParseError, p.parseExpr());
    try std.testing.expect(diags.hasErrors());
}

test "syntax error reports through Diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "1 +"));
    try std.testing.expect(diags.hasErrors());
}

test "legacy =< / => parse as LE / GE, loud in a WHERE (Language Reference: Concepts p.127 Table 6.4 fn.2/3)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `=<` is LE and `=>` is GE — the SAME node as the modern spelling, so
    // precedence, chaining and the mnemonics are shared by construction.
    try std.testing.expect((try parseSrc(a, &diags, "x =< 5")).binary.op == .le);
    try std.testing.expect((try parseSrc(a, &diags, "x => 5")).binary.op == .ge);
    // chains like any other comparison (D-013): `1 =< x =< 5` → and(le, le).
    const c = try parseSrc(a, &diags, "1 =< x =< 5");
    try std.testing.expect(c.binary.op == .@"and");
    try std.testing.expect(c.binary.lhs.binary.op == .le);
    try std.testing.expect(c.binary.rhs.binary.op == .le);
    // the neighbours the new lexer pair must not steal
    const neg = try parseSrc(a, &diags, "x =-1");
    try std.testing.expect(neg.binary.op == .eq and neg.binary.rhs.unary.op == .neg);
    const snd = try parseSrc(a, &diags, "x =* 'S'");
    try std.testing.expect(snd.binary.op == .eq);
    try std.testing.expectEqualStrings("soundex", snd.binary.lhs.call.name);

    // ...but the same footnotes say the legacy spellings are NOT valid in a
    // WHERE clause: loud there, like `><` (BUG-wherene), never a silent compare.
    var w = Parser.init(a, try lexer.tokenize(a, "x =< 3", &diags), &diags);
    w.where_ctx = true;
    try std.testing.expectError(error.ParseError, w.parseExpr());
    var w2 = Parser.init(a, try lexer.tokenize(a, "x => 3", &diags), &diags);
    w2.where_ctx = true;
    try std.testing.expectError(error.ParseError, w2.parseExpr());
    try std.testing.expect(diags.hasErrors());
    const last = diags.list.items[diags.list.items.len - 1];
    try std.testing.expect(std.mem.indexOf(u8, last.message, "=>") != null);
    // the modern spellings keep working in a WHERE
    var w3 = Parser.init(a, try lexer.tokenize(a, "x <= 3", &diags), &diags);
    w3.where_ctx = true;
    try std.testing.expect((try w3.parseExpr()).binary.op == .le);
}

test "IN over an ARRAY name searches its members (Language Reference: Concepts p.128 / p.130)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `x in arr` → or(or(x=a1, x=a2), x=a3): the same desugar the value-list
    // form uses, so order cannot matter and no new AST node appears.
    var p = Parser.init(a, try lexer.tokenize(a, "x in arr", &diags), &diags);
    try p.arrays.append(a, .{ .name = "arr", .elements = &.{ "a1", "a2", "a3" } });
    const e = try p.parseExpr();
    try std.testing.expect(e.binary.op == .@"or");
    try std.testing.expect(e.binary.lhs.binary.op == .@"or");
    try std.testing.expectEqualStrings("a1", e.binary.lhs.binary.lhs.binary.rhs.variable);
    try std.testing.expectEqualStrings("a3", e.binary.rhs.binary.rhs.variable);

    // NOT IN over an array is the AND of the inequalities.
    var q = Parser.init(a, try lexer.tokenize(a, "x not in arr", &diags), &diags);
    try q.arrays.append(a, .{ .name = "arr", .elements = &.{ "a1", "a2" } });
    const n = try q.parseExpr();
    try std.testing.expect(n.binary.op == .@"and");
    try std.testing.expect(n.binary.lhs.binary.op == .ne);

    // array names are case-insensitive like every SAS name; one member → one compare
    var r = Parser.init(a, try lexer.tokenize(a, "x in ARR", &diags), &diags);
    try r.arrays.append(a, .{ .name = "arr", .elements = &.{"a1"} });
    try std.testing.expect((try r.parseExpr()).binary.op == .eq);

    // `IN:` over an array truncates each member compare (the =: desugar).
    var t = Parser.init(a, try lexer.tokenize(a, "x in: arr", &diags), &diags);
    try t.arrays.append(a, .{ .name = "arr", .elements = &.{"a1"} });
    const tr = try t.parseExpr();
    try std.testing.expect(tr.binary.op == .@"and"); // and(lengthn>0, substr eq)
    try std.testing.expectEqualStrings("substrn",tr.binary.rhs.binary.lhs.call.name);

    // A name that is NOT a declared array stays the loud value-list form, and a
    // `{*} _numeric_` array (members are a runtime fact, GH#48) is loud too —
    // expanding an empty member list would silently search nothing.
    var s = Parser.init(a, try lexer.tokenize(a, "x in notanarray", &diags), &diags);
    try std.testing.expectError(error.ParseError, s.parseExpr());
    var v = Parser.init(a, try lexer.tokenize(a, "x in v", &diags), &diags);
    try v.arrays.append(a, .{ .name = "v", .elements = &.{}, .special = .numeric });
    try std.testing.expectError(error.ParseError, v.parseExpr());
    try std.testing.expect(diags.hasErrors());

    // the value-list form is untouched
    try std.testing.expect((try parseSrc(a, &diags, "x in (1, 2)")).binary.op == .@"or");
}

test "IN: is the prefix compare, sharing the =: desugar (Language Reference: Concepts p.127 / p.130)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // `v in: ('AB')` builds EXACTLY what `v =: 'AB'` builds — one prefix
    // compare, including the zero-length guard (Language Reference: Concepts p.130 names both forms).
    const e = try parseSrc(a, &diags, "v in: ('AB')");
    const f = try parseSrc(a, &diags, "v =: 'AB'");
    try std.testing.expect(e.binary.op == f.binary.op);
    try std.testing.expect(e.binary.lhs.binary.op == .gt); // min(lengthn) > 0
    try std.testing.expectEqualStrings("substrn",e.binary.rhs.binary.lhs.call.name);
    try std.testing.expectEqualStrings("substrn",f.binary.rhs.binary.lhs.call.name);

    // two elements → OR of two prefix compares; NOT IN: → AND of their negations
    const g = try parseSrc(a, &diags, "v in: ('AB','CD')");
    try std.testing.expect(g.binary.op == .@"or");
    try std.testing.expect(g.binary.lhs.binary.op == .@"and");
    const h = try parseSrc(a, &diags, "v not in: ('AB','CD')");
    try std.testing.expect(h.binary.op == .@"and");
    try std.testing.expect(h.binary.lhs.unary.op == .not);

    // the M:N integer-range item has no prefix meaning — loud, not invented
    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "v in: (1:3)"));
    try std.testing.expect(diags.hasErrors());
    // plain IN still compares in full, and the range form still works there
    try std.testing.expect((try parseSrc(a, &diags, "v in ('AB')")).binary.op == .eq);
    try std.testing.expect((try parseSrc(a, &diags, "v in (1:3)")).binary.op == .@"and");
}

test "dim/hbound/lbound of a non-array name fails loud at parse time (BUG-dimnonarray)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);

    // No array registry entries in an expression-only parse, so any bare name
    // is a NON-array here: all three bound fns must refuse it (SAS: the
    // argument must be an ARRAY name) instead of echoing the variable's value.
    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "dim(x)"));
    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "hbound(cnt)"));
    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "lbound(x)"));
    try std.testing.expectError(error.ParseError, parseSrc(a, &diags, "dim(x, 1)"));
    try std.testing.expect(diags.hasErrors());
    // The captured diagnostic names the offending variable (fail-loud contract).
    const last = diags.list.items[diags.list.items.len - 1];
    try std.testing.expect(last.severity == .err);
    try std.testing.expect(std.mem.indexOf(u8, last.message, "must be an ARRAY name") != null);
    try std.testing.expect(std.mem.indexOf(u8, last.message, "x") != null);
}
