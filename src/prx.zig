//! A small backtracking Perl-compatible regex engine and the PRX* function
//! registry that SAS's PRXPARSE/PRXMATCH/PRXCHANGE/PRXPOSN/PRXPAREN build on.
//!
//! PRXPARSE compiles a pattern and returns an integer id into a module-global
//! registry; later PRX calls take that id. PRXMATCH/PRXCHANGE record the last
//! match's capture spans on the entry so PRXPOSN/PRXPAREN can read them.
//!
//! Supported: literals, `.`, `*` `+` `?` (greedy and lazy `*?`), `{n,m}`, `[...]`
//! classes with ranges, POSIX classes `[[:alpha:]]` (incl. `[[:^…:]]`), `\d \w \s`
//! and complements, `( )` capturing, `(?: )` non-capturing, `(?<name> )`/`(?'name' )`
//! named groups (numbered like any capture), `(?= )`/`(?! )` zero-width lookahead,
//! back references `\num` (multi-digit), `|` alternation, `^` `$` anchors (`/m` line-aware),
//! `\b \B`, `\n \t \r \f \v \e \a \xHH`, and the `/i /g /s /m /o` modifiers.
//!
//! FAIL-LOUD rule (doc-finder tick133): any other documented PRX construct —
//! lookbehind, `\k`, `\A`, unknown POSIX classes, unknown `/` modifiers, a bad
//! back reference, an unbalanced pattern — is a COMPILE ERROR, logged LOUD
//! (ERROR/UNSUPPORTED + missing id), never silently literalized into a pattern
//! that matches the wrong text (silent-wrong is the clinical worst class).
//! ponytail: a step budget caps catastrophic backtracking (raise BUDGET if a real
//! pattern needs more).

const std = @import("std");
const diag = @import("diag.zig");

// ── compiled form ────────────────────────────────────────────────────────────

const Quant = struct { min: u32, max: ?u32, greedy: bool = true };
const one: Quant = .{ .min = 1, .max = 1 };

const Class = struct {
    neg: bool = false,
    ranges: []const [2]u8 = &.{},
    d: bool = false, // \d
    w: bool = false, // \w
    s: bool = false, // \s
};

const Atom = union(enum) {
    lit: u8,
    any,
    class: Class,
    astart, // ^
    aend, //   $
    wordb, //  \b  word boundary
    nwordb, // \B  non-boundary
    backref: u32, // \N — the text capture group N matched (1-based)
    look: Look, //   (?=…) / (?!…) — zero-width lookahead
    group: Group,
};
const Group = struct { alts: []const []const Term, cap: ?u32 };
const Look = struct { alts: []const []const Term, neg: bool };
const Term = struct { atom: Atom, q: Quant };
const Prog = struct { alts: []const []const Term };

// ── parser (recursive descent) ───────────────────────────────────────────────

const Parser = struct {
    a: std.mem.Allocator,
    src: []const u8,
    i: usize = 0,
    ncap: u32 = 0,
    err_msg: ?[]const u8 = null, // WHY a BadPattern — logged LOUD by parse()
    err_kind: FailKind = .invalid,

    const FailKind = enum { invalid, unsupported };

    /// Record why the pattern failed (an invalid user pattern, or a documented
    /// construct this engine does not implement) and bail — parse() turns this
    /// into the loud ERROR/UNSUPPORTED line tick133 demands.
    fn fail(self: *Parser, kind: FailKind, comptime fmt: []const u8, args: anytype) error{BadPattern} {
        self.err_msg = std.fmt.allocPrint(self.a, fmt, args) catch null;
        self.err_kind = kind;
        return error.BadPattern;
    }

    fn peek(self: *Parser) ?u8 {
        return if (self.i < self.src.len) self.src[self.i] else null;
    }
    fn eat(self: *Parser) u8 {
        const c = self.src[self.i];
        self.i += 1;
        return c;
    }

    fn parseAlt(self: *Parser) error{ OutOfMemory, BadPattern }![]const []const Term {
        var alts: std.ArrayList([]const Term) = .empty;
        try alts.append(self.a, try self.parseSeq());
        while (self.peek() == '|') {
            _ = self.eat();
            try alts.append(self.a, try self.parseSeq());
        }
        return alts.toOwnedSlice(self.a);
    }

    fn parseSeq(self: *Parser) error{ OutOfMemory, BadPattern }![]const Term {
        var terms: std.ArrayList(Term) = .empty;
        while (self.peek()) |c| {
            if (c == '|' or c == ')') break;
            if (c == '(' and self.i + 2 < self.src.len and self.src[self.i + 1] == '?' and self.src[self.i + 2] == '#') {
                // (?#…) comment — contributes nothing, ends at the first ')'
                const close = std.mem.indexOfScalarPos(u8, self.src, self.i + 3, ')') orelse
                    return self.fail(.invalid, "unterminated '(?#' comment", .{});
                self.i = close + 1;
                continue;
            }
            const atom = try self.parseAtom();
            const q = self.parseQuant();
            try terms.append(self.a, .{ .atom = atom, .q = q });
        }
        return terms.toOwnedSlice(self.a);
    }

    fn parseQuant(self: *Parser) Quant {
        const c = self.peek() orelse return one;
        var q: Quant = switch (c) {
            '*' => .{ .min = 0, .max = null },
            '+' => .{ .min = 1, .max = null },
            '?' => .{ .min = 0, .max = 1 },
            '{' => return self.parseBrace(), // {n} / {n,} / {n,m} / {,m}
            else => return one,
        };
        _ = self.eat();
        if (self.peek() == '?') { // lazy
            _ = self.eat();
            q.greedy = false;
        }
        return q;
    }

    /// `{n}` `{n,}` `{n,m}` `{,m}` — a bounded repetition. A malformed `{…` is not
    /// a quantifier: restore and leave the `{` to be read as a literal atom.
    fn parseBrace(self: *Parser) Quant {
        const save = self.i;
        _ = self.eat(); // '{'
        const min = self.parseDigits();
        var max: ?u32 = min; // `{n}` → exactly n
        var comma = false;
        if (self.peek() == ',') {
            _ = self.eat();
            comma = true;
            max = self.parseDigits(); // `{n,}` → unbounded (null)
        }
        // valid only with a closing '}' and at least one bound given
        if (self.peek() == '}' and (min != null or (comma and max != null))) {
            _ = self.eat();
            var q = Quant{ .min = min orelse 0, .max = max, .greedy = true };
            if (self.peek() == '?') {
                _ = self.eat();
                q.greedy = false;
            }
            return q;
        }
        self.i = save; // not a quantifier
        return one;
    }

    fn parseDigits(self: *Parser) ?u32 {
        const start = self.i;
        while (self.peek()) |d| {
            if (!std.ascii.isDigit(d)) break;
            _ = self.eat();
        }
        if (self.i == start) return null;
        return std.fmt.parseInt(u32, self.src[start..self.i], 10) catch null;
    }

    fn parseAtom(self: *Parser) error{ OutOfMemory, BadPattern }!Atom {
        const c = self.eat();
        switch (c) {
            '.' => return .any,
            '^' => return .astart,
            '$' => return .aend,
            '(' => return self.parseGroup(),
            '[' => return .{ .class = try self.parseClass() },
            '\\' => return self.parseEscape(),
            else => return .{ .lit = c },
        }
    }

    /// `( … )` capturing, `(?:…)` non-capturing, `(?<name>…)`/`(?'name'…)` named
    /// (numbered left-to-right like any capture — positional PRXPOSN works),
    /// `(?=…)`/`(?!…)` zero-width lookahead. Everything else under `(?` —
    /// lookbehind, atomic groups, inline flags, … — fails LOUD, never compiles
    /// as literal text (BUG-prxconstruct).
    fn parseGroup(self: *Parser) error{ OutOfMemory, BadPattern }!Atom {
        var cap: ?u32 = null;
        if (self.peek() == '?') {
            const n1 = if (self.i + 1 < self.src.len) self.src[self.i + 1] else 0;
            switch (n1) {
                0 => return self.fail(.invalid, "unbalanced '(' — missing ')'", .{}),
                ':' => self.i += 2,
                '=', '!' => {
                    self.i += 2;
                    const alts = try self.parseAlt();
                    if (self.peek() == ')') _ = self.eat() else return self.fail(.invalid, "unbalanced '(?' — missing ')'", .{});
                    return .{ .look = .{ .alts = alts, .neg = n1 == '!' } };
                },
                '<' => {
                    const n2 = if (self.i + 2 < self.src.len) self.src[self.i + 2] else 0;
                    if (n2 == '=' or n2 == '!') return self.fail(.unsupported, "PRX lookbehind '(?<{c}' is not supported", .{n2});
                    self.i += 2;
                    try self.scanGroupName('>');
                    self.ncap += 1;
                    cap = self.ncap;
                },
                '\'' => {
                    self.i += 2;
                    try self.scanGroupName('\'');
                    self.ncap += 1;
                    cap = self.ncap;
                },
                '#' => return self.fail(.invalid, "unterminated '(?#' comment", .{}),
                else => return self.fail(.unsupported, "PRX construct '(?{c}' is not supported", .{n1}),
            }
        } else {
            self.ncap += 1;
            cap = self.ncap;
        }
        const alts = try self.parseAlt();
        if (self.peek() == ')') _ = self.eat() else return self.fail(.invalid, "unbalanced '(' — missing ')'", .{});
        return .{ .group = .{ .alts = alts, .cap = cap } };
    }

    /// Validate a named group's name through its terminator, then drop it: SAS
    /// numbers named groups like ordinary captures, so only the number matters.
    /// (`\k<name>` references fail loud in parseEscape.)
    fn scanGroupName(self: *Parser, term: u8) error{BadPattern}!void {
        const start = self.i;
        while (self.peek()) |ch| {
            if (ch == term) break;
            if (!std.ascii.isAlphanumeric(ch) and ch != '_') return self.fail(.invalid, "invalid character '{c}' in named group", .{ch});
            _ = self.eat();
        }
        if (self.peek() != term) return self.fail(.invalid, "unterminated named group", .{});
        const nm = self.src[start..self.i];
        _ = self.eat(); // the terminator
        if (nm.len == 0 or std.ascii.isDigit(nm[0])) return self.fail(.invalid, "invalid group name \"{s}\"", .{nm});
    }

    fn parseEscape(self: *Parser) error{ OutOfMemory, BadPattern }!Atom {
        if (self.i >= self.src.len) return .{ .lit = '\\' };
        const e = self.eat();
        switch (e) {
            'd' => return .{ .class = .{ .d = true } },
            'D' => return .{ .class = .{ .d = true, .neg = true } },
            'w' => return .{ .class = .{ .w = true } },
            'W' => return .{ .class = .{ .w = true, .neg = true } },
            's' => return .{ .class = .{ .s = true } },
            'S' => return .{ .class = .{ .s = true, .neg = true } },
            'b' => return .wordb, // word boundary (backspace only inside a class)
            'B' => return .nwordb,
            'n' => return .{ .lit = '\n' },
            't' => return .{ .lit = '\t' },
            'r' => return .{ .lit = '\r' },
            'f' => return .{ .lit = 0x0c },
            'v' => return .{ .lit = 0x0b },
            'e' => return .{ .lit = 0x1b },
            'a' => return .{ .lit = 0x07 },
            'x' => return .{ .lit = try self.parseHex() },
            '1'...'9' => {
                // \1-\9 (multi-digit allowed): match the text group N captured.
                // A reference to a group not yet opened is a compile ERROR (SAS:
                // "Invalid back reference") — never the literal digit (BUG-prxbackref).
                var n: u32 = e - '0';
                while (self.peek()) |d| {
                    if (!std.ascii.isDigit(d)) break;
                    _ = self.eat();
                    n = if (n > 100_000) n else n * 10 + (d - '0'); // saturate; only compared to ncap
                }
                if (n > self.ncap) return self.fail(.invalid, "invalid back reference \\{d} — pattern has {d} capture group(s) before it", .{ n, self.ncap });
                return .{ .backref = n };
            },
            else => {
                // A documented construct we don't implement (\A \z \k \0 …) fails
                // LOUD; other escapes follow Perl's passthrough — an escaped
                // metachar or ordinary letter is that literal.
                if (e == '0' or isUnimplementedEscape(e)) return self.fail(.unsupported, "PRX escape '\\{c}' is not supported", .{e});
                return .{ .lit = e };
            },
        }
    }

    /// The s/// replacement side of a pattern follows the SAME capture-reference
    /// rule as `\num` in the pattern (one engine, one meaning for a group number
    /// — GAP-prxrepldoubledigit): `$num`/`\num` parse num GREEDILY as a
    /// multi-digit number ($10 = buffer 10 — Functions and CALL Routines Ref,
    /// printed p.1713: "num is a positive integer"), and a reference past the
    /// last capture group is a compile ERROR, never group 1 + a literal tail.
    /// `$0` (whole match) stays valid.
    fn checkRepl(self: *Parser, repl: []const u8) error{BadPattern}!void {
        var i: usize = 0;
        while (i < repl.len) : (i += 1) {
            const c = repl[i];
            if ((c == '$' or c == '\\') and i + 1 < repl.len and std.ascii.isDigit(repl[i + 1])) {
                var n: u32 = repl[i + 1] - '0';
                i += 2;
                while (i < repl.len and std.ascii.isDigit(repl[i])) : (i += 1)
                    n = if (n > 100_000) n else n * 10 + (repl[i] - '0'); // saturate; only compared to ncap
                i -= 1; // the loop's += 1 re-reads the first non-digit
                if (n > self.ncap) return self.fail(.invalid, "invalid capture reference {c}{d} — pattern has {d} capture group(s)", .{ c, n, self.ncap });
            }
        }
    }

    /// `\xHH` / `\x{H…}` — a byte value. Malformed, or > 0xFF in this
    /// byte-oriented engine, is a compile error.
    fn parseHex(self: *Parser) error{BadPattern}!u8 {
        var v: u32 = 0;
        var nd: usize = 0;
        if (self.peek() == '{') {
            _ = self.eat();
            while (self.peek()) |h| {
                const d = std.fmt.charToDigit(h, 16) catch break;
                v = v * 16 + d;
                nd += 1;
                _ = self.eat();
                if (v > 0xFF) break;
            }
            if (self.peek() == '}') _ = self.eat() else return self.fail(.invalid, "malformed '\\x{{…}}' escape", .{});
        } else {
            while (nd < 2) {
                const h = self.peek() orelse break;
                const d = std.fmt.charToDigit(h, 16) catch break;
                v = v * 16 + d;
                nd += 1;
                _ = self.eat();
            }
        }
        if (nd == 0) return self.fail(.invalid, "malformed '\\x' escape", .{});
        if (v > 0xFF) return self.fail(.invalid, "'\\x' value {X:0>2} exceeds a byte", .{v});
        return @intCast(v);
    }

    fn parseClass(self: *Parser) error{ OutOfMemory, BadPattern }!Class {
        var cl = Class{};
        if (self.peek() == '^') {
            _ = self.eat();
            cl.neg = true;
        }
        var ranges: std.ArrayList([2]u8) = .empty;
        while (self.peek()) |c| {
            if (c == ']') {
                _ = self.eat();
                cl.ranges = try ranges.toOwnedSlice(self.a);
                return cl;
            }
            if (c == '\\') {
                _ = self.eat();
                if (self.i >= self.src.len) break;
                const e = self.eat();
                switch (e) {
                    'd' => cl.d = true,
                    'w' => cl.w = true,
                    's' => cl.s = true,
                    'D' => try appendComplement(self.a, &ranges, &digit_ranges),
                    'W' => try appendComplement(self.a, &ranges, &word_ranges),
                    'S' => try appendComplement(self.a, &ranges, &space_ranges),
                    'n' => try ranges.append(self.a, .{ '\n', '\n' }),
                    't' => try ranges.append(self.a, .{ '\t', '\t' }),
                    'r' => try ranges.append(self.a, .{ '\r', '\r' }),
                    'f' => try ranges.append(self.a, .{ 0x0c, 0x0c }),
                    'v' => try ranges.append(self.a, .{ 0x0b, 0x0b }),
                    'e' => try ranges.append(self.a, .{ 0x1b, 0x1b }),
                    'a' => try ranges.append(self.a, .{ 0x07, 0x07 }),
                    'b' => try ranges.append(self.a, .{ 0x08, 0x08 }), // backspace inside a class
                    'x' => {
                        const v = try self.parseHex();
                        try ranges.append(self.a, .{ v, v });
                    },
                    '0'...'9' => return self.fail(.unsupported, "PRX octal/back reference '\\{c}' inside a character class is not supported", .{e}),
                    else => {
                        if (isUnimplementedEscape(e)) return self.fail(.unsupported, "PRX escape '\\{c}' inside a character class is not supported", .{e});
                        try ranges.append(self.a, .{ e, e });
                    },
                }
                continue;
            }
            if (c == '[' and self.i + 1 < self.src.len and self.src[self.i + 1] == ':') {
                // POSIX class [[:name:]] / [[:^name:]] — expand to byte ranges
                // (complement ranges for ^, which compose with an outer [^…]).
                _ = self.eat(); // '['
                _ = self.eat(); // ':'
                var neg = false;
                if (self.peek() == '^') {
                    _ = self.eat();
                    neg = true;
                }
                const nstart = self.i;
                while (self.peek()) |ch| {
                    if (ch == ':') break;
                    _ = self.eat();
                }
                const nm = self.src[nstart..self.i];
                if (self.peek() == ':') _ = self.eat();
                if (self.peek() == ']') _ = self.eat() else return self.fail(.invalid, "malformed POSIX class '[[:{s}' — expected ':]'", .{nm});
                const base = posixLookup(nm) orelse return self.fail(.invalid, "unknown POSIX class '[[:{s}:]]'", .{nm});
                if (neg) try appendComplement(self.a, &ranges, base) else for (base) |r| try ranges.append(self.a, r);
                continue;
            }
            _ = self.eat();
            if (self.peek() == '-' and self.i + 1 < self.src.len and self.src[self.i + 1] != ']') {
                _ = self.eat(); // '-'
                const hi = self.eat();
                try ranges.append(self.a, .{ c, hi });
            } else try ranges.append(self.a, .{ c, c });
        }
        return self.fail(.invalid, "unterminated '[' character class", .{});
    }
};

/// Alphabetic escapes that name a real Perl/PRX construct this engine does not
/// implement — these must fail LOUD, never literalize (tick133). Other letters
/// follow Perl's passthrough: an escaped ordinary letter is the letter itself.
fn isUnimplementedEscape(e: u8) bool {
    return switch (e) {
        'A', 'z', 'Z', 'G', 'K', 'Q', 'E', 'U', 'L', 'u', 'l', 'k', 'g', 'h', 'H', 'R', 'N', 'X', 'C', 'p', 'P', 'c' => true,
        else => false,
    };
}

const digit_ranges = [_][2]u8{.{ '0', '9' }};
const word_ranges = [_][2]u8{ .{ '0', '9' }, .{ 'A', 'Z' }, .{ '_', '_' }, .{ 'a', 'z' } };
const space_ranges = [_][2]u8{ .{ 0x09, 0x0D }, .{ 0x20, 0x20 } };

/// SAS 9.4's documented POSIX classes, as sorted disjoint byte ranges.
const posix_classes = [_]struct { name: []const u8, ranges: []const [2]u8 }{
    .{ .name = "alnum", .ranges = &.{ .{ '0', '9' }, .{ 'A', 'Z' }, .{ 'a', 'z' } } },
    .{ .name = "alpha", .ranges = &.{ .{ 'A', 'Z' }, .{ 'a', 'z' } } },
    .{ .name = "blank", .ranges = &.{ .{ 0x09, 0x09 }, .{ 0x20, 0x20 } } },
    .{ .name = "cntrl", .ranges = &.{ .{ 0x00, 0x1F }, .{ 0x7F, 0x7F } } },
    .{ .name = "digit", .ranges = &digit_ranges },
    .{ .name = "graph", .ranges = &.{.{ 0x21, 0x7E }} },
    .{ .name = "lower", .ranges = &.{.{ 'a', 'z' }} },
    .{ .name = "print", .ranges = &.{.{ 0x20, 0x7E }} },
    .{ .name = "punct", .ranges = &.{ .{ 0x21, 0x2F }, .{ 0x3A, 0x40 }, .{ 0x5B, 0x60 }, .{ 0x7B, 0x7E } } },
    .{ .name = "space", .ranges = &space_ranges },
    .{ .name = "upper", .ranges = &.{.{ 'A', 'Z' }} },
    .{ .name = "xdigit", .ranges = &.{ .{ '0', '9' }, .{ 'A', 'F' }, .{ 'a', 'f' } } },
};

fn posixLookup(name: []const u8) ?[]const [2]u8 {
    for (&posix_classes) |pc| if (std.mem.eql(u8, pc.name, name)) return pc.ranges;
    return null;
}

/// Append the byte-complement of `base` (sorted, disjoint ranges) to `ranges` —
/// eager expansion, so it composes with the class's own `neg` ([^[:^d:]] ≡ [[:d:]]).
fn appendComplement(a: std.mem.Allocator, ranges: *std.ArrayList([2]u8), base: []const [2]u8) error{OutOfMemory}!void {
    var lo: u16 = 0;
    for (base) |r| {
        if (r[0] > lo) try ranges.append(a, .{ @intCast(lo), r[0] - 1 });
        lo = @as(u16, r[1]) + 1;
    }
    if (lo < 256) try ranges.append(a, .{ @intCast(lo), 255 });
}

// ── matcher (continuation-passing backtracker) ───────────────────────────────

const BUDGET: usize = 2_000_000;

/// A continuation: what to match after the current position succeeds.
const K = union(enum) {
    done,
    seq: struct { terms: []const Term, i: usize, next: *const K },
    rep: struct { atom: *const Atom, q: Quant, count: u32, next: *const K },
    close: struct { cap: u32, start: usize, next: *const K },
};

const M = struct {
    a: std.mem.Allocator,
    text: []const u8,
    ic: bool,
    dotall: bool, //    /s — '.' also matches \n
    multiline: bool, // /m — '^'/'$' also match at embedded \n
    caps: [][2]?usize,
    budget: usize = BUDGET,

    fn run(self: *M, k: *const K, pos: usize) ?usize {
        if (self.budget == 0) return null;
        self.budget -= 1;
        switch (k.*) {
            .done => return pos,
            .close => |c| {
                const saved = self.caps[c.cap];
                self.caps[c.cap] = .{ c.start, pos };
                if (self.run(c.next, pos)) |e| return e;
                self.caps[c.cap] = saved; // undo on backtrack
                return null;
            },
            .seq => |s| {
                if (s.i >= s.terms.len) return self.run(s.next, pos);
                const term = &s.terms[s.i];
                const rest = K{ .seq = .{ .terms = s.terms, .i = s.i + 1, .next = s.next } };
                const rep = K{ .rep = .{ .atom = &term.atom, .q = term.q, .count = 0, .next = &rest } };
                return self.run(&rep, pos);
            },
            .rep => |r| {
                const can_more = r.q.max == null or r.count < r.q.max.?;
                if (r.q.greedy) {
                    if (can_more) {
                        const more = K{ .rep = .{ .atom = r.atom, .q = r.q, .count = r.count + 1, .next = r.next } };
                        if (self.atomOnce(r.atom.*, pos, &more)) |e| return e;
                    }
                    if (r.count >= r.q.min) return self.run(r.next, pos);
                    return null;
                } else {
                    if (r.count >= r.q.min) if (self.run(r.next, pos)) |e| return e;
                    if (can_more) {
                        const more = K{ .rep = .{ .atom = r.atom, .q = r.q, .count = r.count + 1, .next = r.next } };
                        return self.atomOnce(r.atom.*, pos, &more);
                    }
                    return null;
                }
            },
        }
    }

    /// Match `atom` exactly once at `pos`, then run continuation `k` at its end.
    fn atomOnce(self: *M, atom: Atom, pos: usize, k: *const K) ?usize {
        switch (atom) {
            .lit => |c| {
                if (pos < self.text.len and self.eqc(self.text[pos], c)) return self.run(k, pos + 1);
                return null;
            },
            .any => {
                if (pos < self.text.len and (self.dotall or self.text[pos] != '\n')) return self.run(k, pos + 1);
                return null;
            },
            .class => |cl| {
                if (pos < self.text.len and self.classMatch(cl, self.text[pos])) return self.run(k, pos + 1);
                return null;
            },
            .astart => return if (pos == 0 or (self.multiline and self.text[pos - 1] == '\n')) self.run(k, pos) else null,
            .aend => return if (pos == self.text.len or (self.multiline and self.text[pos] == '\n')) self.run(k, pos) else null,
            .wordb => return if (self.atWordBoundary(pos)) self.run(k, pos) else null,
            .nwordb => return if (!self.atWordBoundary(pos)) self.run(k, pos) else null,
            .backref => |n| {
                // The exact text group N captured (case-insensitively under /i).
                // A group that didn't participate fails the reference (PCRE rule).
                if (n >= self.caps.len) return null;
                const sp = self.caps[n];
                const lo = sp[0] orelse return null;
                const hi = sp[1] orelse return null;
                const want = self.text[lo..hi];
                if (pos + want.len > self.text.len) return null;
                for (want, 0..) |ch, j| if (!self.eqc(self.text[pos + j], ch)) return null;
                return self.run(k, pos + want.len);
            },
            .look => |lk| {
                if (lk.neg) {
                    // Probe against a scratch copy — a (discarded) hit must not
                    // leak its captures into the real match state.
                    const save = self.caps;
                    self.caps = self.a.dupe([2]?usize, save) catch return null;
                    var hit = false;
                    for (lk.alts) |alt| {
                        var dk: K = .done;
                        const ik = K{ .seq = .{ .terms = alt, .i = 0, .next = &dk } };
                        if (self.run(&ik, pos) != null) {
                            hit = true;
                            break;
                        }
                    }
                    self.caps = save;
                    return if (hit) null else self.run(k, pos);
                }
                // ponytail: a successful probe keeps its captures (Perl semantics —
                // a later \N can use them) but they aren't undone if the outer match
                // backtracks past this lookahead; stale PRXPOSN only in that corner.
                for (lk.alts) |alt| {
                    var dk: K = .done;
                    const ik = K{ .seq = .{ .terms = alt, .i = 0, .next = &dk } };
                    if (self.run(&ik, pos) != null) return self.run(k, pos);
                }
                return null;
            },
            .group => |g| {
                for (g.alts) |alt| {
                    if (g.cap) |ci| {
                        const closeK = K{ .close = .{ .cap = ci, .start = pos, .next = k } };
                        const innerK = K{ .seq = .{ .terms = alt, .i = 0, .next = &closeK } };
                        if (self.run(&innerK, pos)) |e| return e;
                    } else {
                        const innerK = K{ .seq = .{ .terms = alt, .i = 0, .next = k } };
                        if (self.run(&innerK, pos)) |e| return e;
                    }
                }
                return null;
            },
        }
    }

    fn eqc(self: *M, a: u8, b: u8) bool {
        if (a == b) return true;
        return self.ic and std.ascii.toLower(a) == std.ascii.toLower(b);
    }

    /// `\b`: a boundary sits between a word char and a non-word char (or a string
    /// edge). True when exactly one side of `pos` is a word character.
    fn atWordBoundary(self: *M, pos: usize) bool {
        const before = pos > 0 and isWord(self.text[pos - 1]);
        const after = pos < self.text.len and isWord(self.text[pos]);
        return before != after;
    }

    fn classMatch(self: *M, cl: Class, ch: u8) bool {
        const hit = member(cl, ch) or (self.ic and member(cl, flipCase(ch)));
        return if (cl.neg) !hit else hit;
    }
};

fn isWord(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

fn member(cl: Class, ch: u8) bool {
    for (cl.ranges) |r| if (ch >= r[0] and ch <= r[1]) return true;
    if (cl.d and std.ascii.isDigit(ch)) return true;
    if (cl.w and (std.ascii.isAlphanumeric(ch) or ch == '_')) return true;
    if (cl.s and isSpace(ch)) return true;
    return false;
}
fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0b or ch == 0x0c;
}
fn flipCase(ch: u8) u8 {
    return if (std.ascii.isUpper(ch)) std.ascii.toLower(ch) else std.ascii.toUpper(ch);
}

// ── registry + public API ────────────────────────────────────────────────────

const Entry = struct {
    prog: Prog,
    ncap: u32,
    ic: bool = false,
    global: bool = false,
    dotall: bool = false, //    /s
    multiline: bool = false, // /m
    repl: ?[]const u8 = null, // s/// replacement template
    freed: bool = false, // CALL PRXFREE — the pattern no longer matches
    last_src: []const u8 = "",
    last_caps: [][2]?usize = &.{},
    last_which: usize = 0, // PRXPAREN: highest capture group that matched
};

const Match = struct { s: usize, e: usize, caps: [][2]?usize };

var g_arena: ?std.heap.ArenaAllocator = null;
var g_entries: std.ArrayList(Entry) = .empty;

/// Drop the compiled-pattern registry from a prior run (taste #12) — entries
/// live in this module's arena; a stale id must not match in the next run.
pub fn resetPerRun() void {
    if (g_arena) |*ar| ar.deinit();
    g_arena = null;
    g_entries = .empty;
}

fn arena() std.mem.Allocator {
    if (g_arena == null) g_arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    return g_arena.?.allocator();
}

/// Compile a SAS PRX pattern (`/re/flags`, `s/re/repl/flags`, or a bare `re`) and
/// register it; returns the 1-based id, or null on a compile error — LOUDLY
/// (GAP-prxinvalidnote): an invalid pattern logs ERROR, an unimplemented
/// construct logs UNSUPPORTED and marks the opensas gap (exit 2, D-009).
pub fn parse(pattern: []const u8) ?u32 {
    const a = arena();
    var body: []const u8 = pattern;
    var repl: ?[]const u8 = null;
    var flags: []const u8 = "";

    if (pattern.len >= 2 and pattern[0] == 's' and !std.ascii.isAlphanumeric(pattern[1])) {
        // s<d>pat<d>repl<d>flags
        const d = pattern[1];
        const m1 = findDelim(pattern, 2, d) orelse {
            loudInvalid("unmatched '{c}' delimiter in PRX pattern \"{s}\"", .{ d, pattern });
            return null;
        };
        const m2 = findDelim(pattern, m1 + 1, d) orelse {
            loudInvalid("unmatched '{c}' delimiter in PRX pattern \"{s}\"", .{ d, pattern });
            return null;
        };
        body = pattern[2..m1];
        repl = pattern[m1 + 1 .. m2];
        flags = pattern[m2 + 1 ..];
    } else if (pattern.len >= 1 and pattern[0] == '/') {
        const m1 = findDelim(pattern, 1, '/') orelse {
            loudInvalid("unmatched '/' delimiter in PRX pattern \"{s}\"", .{pattern});
            return null;
        };
        body = pattern[1..m1];
        flags = pattern[m1 + 1 ..];
    }

    var p = Parser{ .a = a, .src = a.dupe(u8, body) catch return null };
    const alts = p.parseAlt() catch |err| {
        if (err == error.OutOfMemory) return null;
        switch (p.err_kind) {
            .invalid => loudInvalid("{s} in PRX pattern \"{s}\"", .{ p.err_msg orelse "invalid syntax", pattern }),
            .unsupported => loudUnsup("{s}", .{p.err_msg orelse "PRX construct"}),
        }
        return null;
    };
    if (p.i != p.src.len) {
        loudInvalid("unbalanced ')' in PRX pattern \"{s}\"", .{pattern});
        return null;
    }

    var e = Entry{ .prog = .{ .alts = alts }, .ncap = p.ncap };
    for (flags) |f| switch (f) {
        'i' => e.ic = true,
        'g' => e.global = true,
        's' => e.dotall = true,
        'm' => e.multiline = true,
        'o' => {}, // compile-once hint — every PRXPARSE here compiles fresh, which honors it
        else => {
            loudUnsup("PRX modifier '/{c}' is not supported", .{f});
            return null;
        },
    };
    if (repl) |r| {
        p.checkRepl(r) catch {
            loudInvalid("{s} in PRX pattern \"{s}\"", .{ p.err_msg orelse "invalid replacement", pattern });
            return null;
        };
        e.repl = a.dupe(u8, r) catch return null;
    }

    g_entries.append(a, e) catch return null;
    return @intCast(g_entries.items.len); // 1-based id
}

/// Scan for the closing delimiter, honoring `\<d>` escapes — `/a\//` is the
/// pattern `a/`, not `a\` with a stray tail.
fn findDelim(src: []const u8, from: usize, d: u8) ?usize {
    var i = from;
    while (i < src.len) : (i += 1) {
        if (src[i] == '\\') {
            i += 1;
            continue;
        }
        if (src[i] == d) return i;
    }
    return null;
}

// ── loud-error channel (tick133) ────────────────────────────────────────────
// A PRX pattern that is invalid (the user's SAS is wrong — SAS logs ERROR and
// returns missing) or uses a documented construct this engine does not implement
// (an opensas gap — UNSUPPORTED + exit 2) must say so LOUD; the old code silently
// compiled a DIFFERENT pattern (silent-wrong, the clinical worst class). The CLI
// prints to stderr (SAS-style log); test builds CAPTURE the line (D-003 — never
// spawn an aborting process from a test).
// ponytail: loudInvalid can't reach the run's Diagnostics — prx.parse is called
// from functions.zig/exec.zig without a diags handle and prx owns only this file —
// so a user-invalid pattern exits 0 though the ERROR is in the log. Upgrade path:
// thread ev.diags through the prxparse dispatch (functions.zig) for exit-1 parity.
pub var g_test_last_err: []const u8 = "";
pub var g_test_last_unsup: []const u8 = "";
var g_err_buf: [512]u8 = undefined;
var g_unsup_buf: [512]u8 = undefined;

fn loudInvalid(comptime fmt: []const u8, args: anytype) void {
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_err_buf, fmt, args) catch "prx: message too long";
    } else {
        std.debug.print("ERROR: " ++ fmt ++ "\n", args);
    }
}

fn loudUnsup(comptime fmt: []const u8, args: anytype) void {
    diag.markGap(); // opensas gap → the run exits 2 (D-009 / FLY-exitcodes)
    if (@import("builtin").is_test) {
        g_test_last_unsup = std.fmt.bufPrint(&g_unsup_buf, fmt, args) catch "prx: message too long";
    } else {
        std.debug.print("UNSUPPORTED: " ++ fmt ++ "\n", args);
    }
}

fn entryAt(id: u32) ?*Entry {
    if (id == 0 or id > g_entries.items.len) return null;
    return &g_entries.items[id - 1];
}

/// First match of `entry` in `text` at or after `from`, capture spans filled.
fn search(e: *Entry, text: []const u8, from: usize) ?Match {
    const a = arena();
    var s = from;
    while (s <= text.len) : (s += 1) {
        const caps = a.alloc([2]?usize, e.ncap + 1) catch return null;
        @memset(caps, .{ null, null });
        var m = M{ .a = a, .text = text, .ic = e.ic, .dotall = e.dotall, .multiline = e.multiline, .caps = caps };
        for (e.prog.alts) |alt| {
            var doneK: K = .done;
            var seqK = K{ .seq = .{ .terms = alt, .i = 0, .next = &doneK } };
            if (m.run(&seqK, s)) |end| {
                caps[0] = .{ s, end };
                return .{ .s = s, .e = end, .caps = caps };
            }
        }
    }
    return null;
}

fn whichLast(caps: [][2]?usize) usize {
    var i = caps.len;
    while (i > 1) {
        i -= 1;
        if (caps[i][0] != null) return i;
    }
    return 0;
}

/// PRXMATCH: 1-based position of the first match in `source` (0 if none). Records
/// the capture state on the entry for a later PRXPOSN/PRXPAREN.
pub fn matchId(id: u32, source: []const u8) usize {
    const e = entryAt(id) orelse return 0;
    if (e.freed) return 0;
    const mt = search(e, source, 0) orelse return 0;
    e.last_src = arena().dupe(u8, source) catch return 0;
    e.last_caps = mt.caps;
    e.last_which = whichLast(mt.caps);
    return mt.s + 1;
}

/// PRXPOSN: the substring captured by group `n` in the last match, or "".
pub fn posn(id: u32, n: usize) []const u8 {
    const e = entryAt(id) orelse return "";
    if (n >= e.last_caps.len) return "";
    const span = e.last_caps[n];
    if (span[0]) |lo| if (span[1]) |hi| if (hi <= e.last_src.len) return e.last_src[lo..hi];
    return "";
}

/// PRXPAREN: number of the last (highest) capture group that matched.
pub fn paren(id: u32) usize {
    const e = entryAt(id) orelse return 0;
    return e.last_which;
}

/// A 1-based position + length, as the CALL PRX routines report. `pos == 0` means
/// "no match" (SAS leaves position and length 0 in that case).
pub const Span = struct { pos: usize = 0, len: usize = 0 };

fn record(e: *Entry, src: []const u8, mt: Match) void {
    e.last_src = arena().dupe(u8, src) catch "";
    e.last_caps = mt.caps;
    e.last_which = whichLast(mt.caps);
}

/// CALL PRXSUBSTR: first match of `id` in `source` → its 1-based position and
/// length (0/0 if none). Records the capture buffers for a later CALL PRXPOSN.
pub fn substr(id: u32, source: []const u8) Span {
    const e = entryAt(id) orelse return .{};
    if (e.freed) return .{};
    const mt = search(e, source, 0) orelse return .{};
    record(e, source, mt);
    return .{ .pos = mt.s + 1, .len = mt.e - mt.s };
}

/// CALL PRXNEXT: next match at/after 1-based `start`, not past 1-based `stop` →
/// its position and length (0/0 if none). The caller advances `start` past the
/// returned match to iterate. Records the capture buffers.
pub fn next(id: u32, source: []const u8, start: usize, stop: usize) Span {
    const e = entryAt(id) orelse return .{};
    if (e.freed) return .{};
    const from = if (start >= 1) start - 1 else 0;
    const hi = if (stop >= 1 and stop <= source.len) stop else source.len;
    if (from > hi) return .{};
    const region = source[0..hi];
    const mt = search(e, region, from) orelse return .{};
    record(e, region, mt);
    return .{ .pos = mt.s + 1, .len = mt.e - mt.s };
}

/// CALL PRXPOSN: 1-based position and length of capture group `n` in the last
/// match (0/0 if the group did not match).
pub fn posnSpan(id: u32, n: usize) Span {
    const e = entryAt(id) orelse return .{};
    if (n >= e.last_caps.len) return .{};
    const span = e.last_caps[n];
    if (span[0]) |lo| if (span[1]) |sp_hi| return .{ .pos = lo + 1, .len = sp_hi - lo };
    return .{};
}

/// CALL PRXFREE: release the compiled pattern. The id slot stays (ids remain
/// stable) but the pattern no longer matches — SAS also sets the id var to missing.
pub fn free(id: u32) void {
    if (entryAt(id)) |e| e.freed = true;
}

/// PRXCHANGE: apply the entry's s/// substitution to `source`, up to `times`
/// replacements (< 0 or the /g flag → all), returning the result in `out_a`.
pub fn change(out_a: std.mem.Allocator, id: u32, times: i64, source: []const u8) ![]const u8 {
    const e = entryAt(id) orelse return out_a.dupe(u8, source);
    if (e.freed) return out_a.dupe(u8, source);
    const repl = e.repl orelse return out_a.dupe(u8, source);
    const unlimited = e.global or times < 0;

    var out: std.ArrayList(u8) = .empty;
    var pos: usize = 0;
    var done: i64 = 0;
    while (pos <= source.len) {
        if (!unlimited and done >= times) break;
        const mt = search(e, source, pos) orelse break;
        try out.appendSlice(out_a, source[pos..mt.s]);
        try expand(out_a, &out, repl, source, mt.caps);
        done += 1;
        if (mt.e == mt.s) { // empty match: emit one char and advance to avoid a loop
            if (mt.e < source.len) try out.append(out_a, source[mt.e]);
            pos = mt.e + 1;
        } else pos = mt.e;
    }
    if (pos <= source.len) try out.appendSlice(out_a, source[pos..]);
    return out.items;
}

/// Expand a replacement template: `$num`/`\num` → capture num (multi-digit,
/// mirroring `\num` in the pattern; `$0`/`&` → whole match). Parser.checkRepl
/// already rejected num > ncap at compile time; the range guard is defense.
fn expand(a: std.mem.Allocator, out: *std.ArrayList(u8), repl: []const u8, src: []const u8, caps: [][2]?usize) !void {
    var i: usize = 0;
    while (i < repl.len) {
        const c = repl[i];
        if ((c == '$' or c == '\\') and i + 1 < repl.len and std.ascii.isDigit(repl[i + 1])) {
            var n: usize = repl[i + 1] - '0';
            i += 2;
            while (i < repl.len and std.ascii.isDigit(repl[i])) : (i += 1)
                n = if (n > 100_000) n else n * 10 + (repl[i] - '0'); // saturate; only compared to caps.len
            if (n < caps.len) if (caps[n][0]) |lo| if (caps[n][1]) |hi| try out.appendSlice(a, src[lo..hi]);
        } else if (c == '&') {
            if (caps[0][0]) |lo| if (caps[0][1]) |hi| try out.appendSlice(a, src[lo..hi]);
            i += 1;
        } else {
            try out.append(a, c);
            i += 1;
        }
    }
}

// ── tests ────────────────────────────────────────────────────────────────────

const t = std.testing;

test "prxparse + prxmatch: literal, classes, anchors, alternation" {
    // "xabcy": 'a' at index 1 → 1-based position 2
    try t.expectEqual(@as(usize, 2), matchId(parse("/abc/").?, "xabcy"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/abc/").?, "xyz"));
    // \d+ finds the digit run
    try t.expectEqual(@as(usize, 4), matchId(parse("/\\d+/").?, "abc123"));
    // anchors
    try t.expectEqual(@as(usize, 1), matchId(parse("/^\\w+$/").?, "hello"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/^\\w+$/").?, "hi there"));
    // alternation + quantifier
    try t.expectEqual(@as(usize, 1), matchId(parse("/(cat|dog)s?/").?, "cats"));
    // ignorecase flag
    try t.expectEqual(@as(usize, 1), matchId(parse("/abc/i").?, "ABC"));
    // char class range
    try t.expectEqual(@as(usize, 3), matchId(parse("/[0-9]+/").?, "ab42"));
}

test "prxposn + prxparen: capture groups" {
    const rx = parse("/(\\d+)-(\\d+)/").?;
    try t.expect(matchId(rx, "code 12-345 end") > 0);
    try t.expectEqualStrings("12", posn(rx, 1));
    try t.expectEqualStrings("345", posn(rx, 2));
    try t.expectEqualStrings("12-345", posn(rx, 0)); // whole match
    try t.expectEqual(@as(usize, 2), paren(rx)); // last matched group

    // alternation picks the matching branch for PRXPAREN
    const rx2 = parse("/(a)|(b)/").?;
    _ = matchId(rx2, "zzb");
    try t.expectEqual(@as(usize, 2), paren(rx2));
}

test "prxchange: substitution, global and count-limited" {
    var arena_i = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena_i.deinit();
    const a = arena_i.allocator();

    // global replace of digit runs
    const g = parse("s/\\d+/#/").?; // no /g, but times=-1 → all
    try t.expectEqualStrings("a#b#c", try change(a, g, -1, "a1b22c"));
    // capture reference in the replacement
    const swap = parse("s/(\\w+)=(\\w+)/$2:$1/").?;
    try t.expectEqualStrings("y:x", try change(a, swap, -1, "x=y"));
    // count-limited: only the first
    const one_ = parse("s/o/0/").?;
    try t.expectEqualStrings("f0obar", try change(a, one_, 1, "foobar"));
    // /g flag replaces all
    const gg = parse("s/o/0/g").?;
    try t.expectEqualStrings("f00bar", try change(a, gg, 1, "foobar"));
}

test "CALL PRXSUBSTR / PRXNEXT / PRXPOSN spans + PRXFREE" {
    // PRXSUBSTR: first match position + length
    const rx = parse("/\\d+/").?;
    const sp = substr(rx, "ab123cd");
    try t.expectEqual(@as(usize, 3), sp.pos); // '1' at 1-based col 3
    try t.expectEqual(@as(usize, 3), sp.len); // "123"

    // PRXNEXT: iterate every digit run in "a1b22c333"
    const src = "a1b22c333";
    const m1 = next(rx, src, 1, src.len);
    try t.expectEqual(@as(usize, 2), m1.pos); // "1"
    try t.expectEqual(@as(usize, 1), m1.len);
    const m2 = next(rx, src, m1.pos + m1.len, src.len); // advance past the first
    try t.expectEqual(@as(usize, 4), m2.pos); // "22"
    try t.expectEqual(@as(usize, 2), m2.len);
    const m3 = next(rx, src, m2.pos + m2.len, src.len);
    try t.expectEqual(@as(usize, 7), m3.pos); // "333"
    try t.expectEqual(@as(usize, 3), m3.len);
    try t.expectEqual(@as(usize, 0), next(rx, src, m3.pos + m3.len, src.len).pos); // no more

    // CALL PRXPOSN: capture group spans from the last match
    const cap = parse("/(\\d+)-(\\d+)/").?;
    try t.expect(matchId(cap, "x 12-345") > 0);
    const g1 = posnSpan(cap, 1);
    try t.expectEqual(@as(usize, 3), g1.pos); // "12" at col 3
    try t.expectEqual(@as(usize, 2), g1.len);
    const g2 = posnSpan(cap, 2);
    try t.expectEqual(@as(usize, 6), g2.pos); // "345" at col 6
    try t.expectEqual(@as(usize, 3), g2.len);

    // PRXFREE: after freeing, the pattern no longer matches
    const fr = parse("/x/").?;
    try t.expect(matchId(fr, "axb") > 0);
    free(fr);
    try t.expectEqual(@as(usize, 0), matchId(fr, "axb"));
}

test "BUG-prxquant: {n} {n,} {n,m} bounded quantifiers + \\b word boundary" {
    var ai = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ai.deinit();
    const a = ai.allocator();

    // {n}: exactly n
    try t.expect(matchId(parse("/^\\d{3}$/").?, "123") > 0);
    try t.expectEqual(@as(usize, 0), matchId(parse("/^\\d{3}$/").?, "12"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/^\\d{3}$/").?, "1234"));

    // {n,}: n or more
    try t.expect(matchId(parse("/^a{2,}$/").?, "aaaa") > 0);
    try t.expectEqual(@as(usize, 0), matchId(parse("/^a{2,}$/").?, "a"));

    // {n,m}: between n and m — greedy, so it consumes as many as allowed
    const zip = parse("/\\d{3,5}/").?;
    try t.expectEqual(@as(usize, 1), matchId(zip, "12345")); // matches at pos 1
    // greedy {3,5} over 7 digits takes the first 5 (verify via a capture change)
    const cap = parse("s/(\\d{3,5})/[$1]/").?;
    try t.expectEqualStrings("[12345]67", try change(a, cap, -1, "1234567"));

    // a malformed brace is a literal '{'
    try t.expect(matchId(parse("/a{b/").?, "a{b") > 0);

    // \b word boundary: "cat" as a whole word, not inside "category"
    const wb = parse("/\\bcat\\b/").?;
    try t.expect(matchId(wb, "the cat sat") > 0);
    try t.expectEqual(@as(usize, 0), matchId(wb, "category"));
    // \bcat matches the start of "category" (boundary before, none required after)
    try t.expect(matchId(parse("/\\bcat/").?, "category") > 0);
    // \B non-boundary: "cat" only when NOT at a word boundary → inside "scatter"
    try t.expect(matchId(parse("/\\Bcat/").?, "scatter") > 0);
    try t.expectEqual(@as(usize, 0), matchId(parse("/\\Bcat/").?, "cat"));
}

test "BUG-prxbackref: back references \\1-\\9 match the captured text" {
    // doc-finder tick133's SAS-verified table
    try t.expectEqual(@as(usize, 3), matchId(parse("/(ab)\\1/").?, "zzababzz"));
    try t.expectEqual(@as(usize, 3), matchId(parse("/(\\w)\\1/").?, "hello"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/(\\w)\\1/").?, "world"));
    try t.expectEqual(@as(usize, 1), matchId(parse("/(\\d+)-\\1/").?, "34-34"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/(\\d+)-\\1/").?, "34-56"));
    // /i: capture "AB", the reference matches "ab"
    try t.expectEqual(@as(usize, 3), matchId(parse("/(ab)\\1/i").?, "zzABabzz"));
    // a group that didn't participate fails the reference (PCRE), never matches empty
    try t.expectEqual(@as(usize, 0), matchId(parse("/(x)|(b)\\2/").?, "ab"));
    // multi-digit reference
    try t.expectEqual(@as(usize, 1), matchId(parse("/(a)(b)(c)(d)(e)(f)(g)(h)(i)\\9/").?, "abcdefghii"));
    // a reference past the opened groups is a compile ERROR, LOUD — not a literal digit
    g_test_last_err = "";
    try t.expect(parse("/(a)\\2/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "invalid back reference") != null);
}

test "GAP-prxrepldoubledigit: replacement $num is multi-digit, mirrors \\num" {
    var ai = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ai.deinit();
    const a = ai.allocator();

    // $10 = capture buffer 10 (Functions ref, printed p.1713: "num is a
    // positive integer") — not group 1 + a literal "0".
    const rx = parse("s/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/$10-$1/").?;
    try t.expectEqualStrings("j-akl", try change(a, rx, -1, "abcdefghijkl"));
    // $1-$9 unchanged (controls)
    const rx9 = parse("s/(a)(b)(c)(d)(e)(f)(g)(h)(i)/$9$8$7$6$5$4$3$2$1/").?;
    try t.expectEqualStrings("ihgfedcba", try change(a, rx9, -1, "abcdefghi"));
    // $0 = whole match
    const rx0 = parse("s/(a)(b)/[$0]/").?;
    try t.expectEqualStrings("[ab]", try change(a, rx0, -1, "ab"));
    // \num in the replacement follows the same multi-digit rule
    const rxb = parse("s/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)/\\10/").?;
    try t.expectEqualStrings("jkl", try change(a, rxb, -1, "abcdefghijkl"));
    // \10 on the PATTERN side resolves to group 10 (the verified asymmetry)
    try t.expectEqual(@as(usize, 1), matchId(parse("/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\\10/").?, "abcdefghijj"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/(a)(b)(c)(d)(e)(f)(g)(h)(i)(j)\\10/").?, "abcdefghija0"));

    // ambiguity rule, mirroring the pattern side exactly: $10 with only 5
    // groups is a LOUD compile ERROR — never group 1 + a literal tail.
    g_test_last_err = "";
    try t.expect(parse("s/(a)(b)(c)(d)(e)/$10/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "invalid capture reference $10") != null);
    // a reference to a non-existent group errors the same way
    g_test_last_err = "";
    try t.expect(parse("s/(a)/$2/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "invalid capture reference $2") != null);
    // ...and the \num replacement form is checked identically
    g_test_last_err = "";
    try t.expect(parse("s/(a)/\\2/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "invalid capture reference \\2") != null);
}

test "BUG-prxconstruct: lookahead, named groups, /s /m, POSIX classes" {
    // positive / negative lookahead are zero-width
    try t.expectEqual(@as(usize, 1), matchId(parse("/foo(?=bar)/").?, "foobar"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/foo(?=bar)/").?, "foobaz"));
    try t.expectEqual(@as(usize, 1), matchId(parse("/foo(?!bar)/").?, "foobaz"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/foo(?!bar)/").?, "foobar"));
    try t.expectEqual(@as(usize, 2), matchId(parse("/a(?=b|c)/").?, "zac"));
    // captures inside a positive lookahead are visible to a later backref (Perl)
    try t.expectEqual(@as(usize, 3), matchId(parse("/(?=(ab))\\1/").?, "zzab"));
    // a negative-lookahead probe must not leak captures into the real match
    const nl = parse("/(?!x)(\\w)/").?;
    try t.expectEqual(@as(usize, 1), matchId(nl, "ab"));
    try t.expectEqualStrings("a", posn(nl, 1));

    // named groups number like ordinary captures (both (?<n>) and (?'n'))
    const ng = parse("/(?<y>\\d{4})-(?'m'\\d{2})/").?;
    try t.expectEqual(@as(usize, 4), matchId(ng, "yr 2026-07"));
    try t.expectEqualStrings("2026", posn(ng, 1));
    try t.expectEqualStrings("07", posn(ng, 2));
    try t.expectEqual(@as(usize, 2), paren(ng));

    // /s dotall: '.' matches \n; /m multiline: ^/$ at embedded line breaks
    try t.expectEqual(@as(usize, 1), matchId(parse("/a.b/s").?, "a\nb"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/a.b/").?, "a\nb"));
    try t.expectEqual(@as(usize, 3), matchId(parse("/^b/m").?, "a\nb"));
    try t.expectEqual(@as(usize, 3), matchId(parse("/c$/m").?, "abc\nd"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/^b/").?, "a\nb"));
    try t.expectEqual(@as(usize, 0), matchId(parse("/c$/").?, "abc\nd"));

    // POSIX classes — including [[:^…]] and [^[:…:]] (complements compose)
    try t.expectEqual(@as(usize, 3), matchId(parse("/[[:digit:]]+/").?, "ab123"));
    try t.expectEqual(@as(usize, 3), matchId(parse("/[[:alpha:]]+/").?, "12ab"));
    try t.expectEqual(@as(usize, 3), matchId(parse("/[[:^digit:]]+/").?, "12ab34"));
    try t.expectEqual(@as(usize, 3), matchId(parse("/[^[:digit:]]+/").?, "12ab34"));
    try t.expectEqual(@as(usize, 1), matchId(parse("/^[[:xdigit:]]+$/").?, "deAdBeef"));
}

test "BUG-prxconstruct / GAP-prxinvalidnote: invalid + unsupported fail LOUD (captured)" {
    // invalid pattern → null + a captured ERROR (GAP-prxinvalidnote)
    g_test_last_err = "";
    try t.expect(parse("/(abc/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "unbalanced") != null);
    g_test_last_err = "";
    try t.expect(parse("/[ab/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "unterminated") != null);
    g_test_last_err = "";
    try t.expect(parse("/[[:nosuch:]]/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "POSIX") != null);
    // a valid pattern logs nothing
    g_test_last_err = "";
    try t.expect(parse("/a\\d/") != null);
    try t.expectEqualStrings("", g_test_last_err);

    // unsupported constructs → null + captured UNSUPPORTED (+ gap marked → exit 2)
    g_test_last_unsup = "";
    try t.expect(parse("/(?<=a)b/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "lookbehind") != null);
    g_test_last_unsup = "";
    try t.expect(parse("/(?<!a)b/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "lookbehind") != null);
    g_test_last_unsup = "";
    try t.expect(parse("/a/x") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "modifier") != null);
    g_test_last_unsup = "";
    try t.expect(parse("/\\Acat/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "'\\A'") != null);
    g_test_last_unsup = "";
    try t.expect(parse("/(?<n>\\d)\\k<n>/") == null);
    try t.expect(std.mem.indexOf(u8, g_test_last_unsup, "'\\k'") != null);
    diag.resetGap(); // don't leak the gap flag into the exit-code tests
}
