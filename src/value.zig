const std = @import("std");
const pdv = @import("pdv.zig"); // sasParseFloat — the char→num twin (import cycle is fine, Zig is lazy)

/// A SAS data value. SAS has exactly two data types: numeric (an IEEE-754
/// double) and character (a byte string). There is no integer, no boolean —
/// every number is an `f64`, every truth test collapses to `truthy()` below.
///
/// A numeric can be *missing* (`.`). We represent missing as a quiet NaN so
/// arithmetic propagates it for free (`. + 1` stays missing); `isMissing`
/// treats any NaN as missing. Character values are borrowed slices: the arena
/// that owns the bytes (the PDV, M0.3) outlives any `Value` handed around.
pub const Value = union(enum) {
    num: f64,
    str: []const u8,

    /// SAS numeric missing, `.`.
    pub const missing: Value = .{ .num = std.math.nan(f64) };

    // Special missings (._, . , .A–.Z) ride in the NaN payload so a numeric
    // Value still fits one f64 and arithmetic keeps propagating them. The low 5
    // mantissa bits hold a code: 0 = plain `.` (also every arithmetic NaN);
    // 1..26 = .A..Z; 27 = ._ . A canonical NaN (payload 0) reads back as plain.
    const miss_code_mask: u64 = 0x1F;

    /// A special missing numeric for `letter` ('A'–'Z' or '_'); anything else
    /// (incl. '.') gives the plain missing.
    pub fn specialMissing(letter: u8) Value {
        const code: u64 = switch (letter) {
            '_' => 27,
            'A'...'Z' => letter - 'A' + 1,
            'a'...'z' => letter - 'a' + 1,
            else => 0,
        };
        return .{ .num = @bitCast(@as(u64, 0x7FF8000000000000) | code) };
    }

    /// Text ingestion: a field that is exactly `.`+one[A-Za-z] or `.`+`_` is a
    /// numeric special missing (.A–.Z, ._). Trims blanks; null for anything else
    /// (incl. plain `.`, blanks, real numbers) so callers fall through to their
    /// parseFloat path. Call BEFORE that fallback in every text sink.
    pub fn parseSpecialMissing(field: []const u8) ?Value {
        const tr = std.mem.trim(u8, field, " \t");
        if (tr.len == 2 and tr[0] == '.') switch (tr[1]) {
            'A'...'Z', 'a'...'z', '_' => return specialMissing(tr[1]),
            else => {},
        };
        return null;
    }

    /// Sort rank of a missing numeric: ._ (0) < . (1) < .A (2) < … < .Z (27).
    /// Real numbers rank above all of these — the comparison handles that.
    pub fn missingRank(x: f64) u8 {
        const code: u8 = @intCast(@as(u64, @bitCast(x)) & miss_code_mask);
        return if (code == 27) 0 else code + 1;
    }

    /// Display char for a missing numeric: '.' plain, 'A'–'Z' special, '_' for ._ .
    pub fn missingChar(x: f64) u8 {
        const code: u8 = @intCast(@as(u64, @bitCast(x)) & miss_code_mask);
        return switch (code) {
            0 => '.',
            27 => '_',
            else => 'A' + code - 1,
        };
    }

    /// A missing *numeric*. Character values are never "missing" in SAS — an
    /// absent char is the blank/empty string, which `truthy()` reads as false.
    pub fn isMissing(self: Value) bool {
        return switch (self) {
            .num => |x| std.math.isNan(x),
            .str => false,
        };
    }

    /// SAS truthiness, as `if`, `do while/until`, and `and`/`or`/`not` use it:
    ///   numeric   → true iff present and non-zero,
    ///   character → SAS first applies the implicit char→numeric conversion
    ///     (trimmed `w.` informat; blank/unparseable → missing), THEN numeric
    ///     truthiness: '0' and 'abc' are BOTH false, '2.5' true
    ///     (BUG-charinboolean — was C-style "any non-blank → true").
    /// ponytail: the conversion/invalid-data NOTEs SAS logs here are omitted —
    /// truthy() has no diags handle (same split as numToChar: "the NOTE stays
    /// with each caller"). Route through an Evaluator helper if a fixture ever
    /// asserts those notes.
    pub fn truthy(self: Value) bool {
        return switch (self) {
            .num => |x| !std.math.isNan(x) and x != 0,
            .str => |s| {
                const tr = std.mem.trim(u8, s, " ");
                if (tr.len == 0) return false;
                if (parseSpecialMissing(tr) != null) return false; // '.A' → missing → false
                const x = pdv.sasParseFloat(tr) orelse return false; // unparseable → missing → false
                return x != 0; // validated decimal grammar, never NaN
            },
        };
    }

    /// WHERE-clause truthiness (Language Reference: Concepts p.216) — DELIBERATELY different from
    /// `truthy()` and the two must not be unified (BUG-wherebarechar): "The
    /// names of character variables can also stand alone. SAS selects
    /// observations where the value of the character variable is not blank."
    /// No char→numeric conversion, so '0' is TRUE here but false in an `if`.
    /// Numeric rule identical to truthy(). Called ONLY by the top-level WHERE
    /// evaluators (exec.applyWhereStmt, io.applyWhere, sql's WHERE paths) —
    /// ponytail: a char operand nested inside and/or/not still converts via
    /// truthy() (eval.zig), the p.216 rule as documented covers the bare case.
    pub fn whereTruthy(self: Value) bool {
        return switch (self) {
            .num => |x| !std.math.isNan(x) and x != 0,
            .str => |s| std.mem.trim(u8, s, " ").len != 0,
        };
    }
};

test "truthy: numeric" {
    const t = std.testing;
    try t.expect(Value.truthy(.{ .num = 1 }));
    try t.expect(Value.truthy(.{ .num = -0.5 }));
    try t.expect(!Value.truthy(.{ .num = 0 }));
    try t.expect(!Value.truthy(Value.missing)); // missing is false, not "zero"
}

test "truthy: character auto-converts char→numeric first (BUG-charinboolean)" {
    const t = std.testing;
    try t.expect(!Value.truthy(.{ .str = "0" })); // '0' → 0 → false
    try t.expect(!Value.truthy(.{ .str = " -0.0 " })); // → 0 → false
    try t.expect(Value.truthy(.{ .str = "1" }));
    try t.expect(Value.truthy(.{ .str = "2.5" }));
    try t.expect(Value.truthy(.{ .str = " -1e2 " }));
    try t.expect(!Value.truthy(.{ .str = "abc" })); // unparseable → missing → false
    try t.expect(!Value.truthy(.{ .str = "x" }));
    try t.expect(!Value.truthy(.{ .str = ".A" })); // special missing → false
    try t.expect(!Value.truthy(.{ .str = "." })); // no digits → missing → false
    try t.expect(!Value.truthy(.{ .str = "" }));
    try t.expect(!Value.truthy(.{ .str = "   " })); // blank → missing → false
}

test "whereTruthy: WHERE's bare-char rule is non-blank, NOT numeric conversion (BUG-wherebarechar)" {
    const t = std.testing;
    // numeric: identical to truthy()
    try t.expect(Value.whereTruthy(.{ .num = 1 }));
    try t.expect(!Value.whereTruthy(.{ .num = 0 }));
    try t.expect(!Value.whereTruthy(Value.missing));
    // character: non-blank is TRUE — the sharp divergences from truthy()
    try t.expect(Value.whereTruthy(.{ .str = "0" })); // WHERE: true; IF: false
    try t.expect(Value.whereTruthy(.{ .str = "abc" })); // WHERE: true; IF: missing→false
    try t.expect(Value.whereTruthy(.{ .str = ".A" })); // non-blank char → true
    try t.expect(!Value.whereTruthy(.{ .str = "" }));
    try t.expect(!Value.whereTruthy(.{ .str = "   " })); // blank → false (p.216)
    // and truthy() itself must NOT have moved
    try t.expect(!Value.truthy(.{ .str = "0" }));
    try t.expect(!Value.truthy(.{ .str = "abc" }));
}

test "special missing: encode, rank order, display char (G-specialmiss)" {
    const t = std.testing;
    const a = Value.specialMissing('A');
    const z = Value.specialMissing('Z');
    const u = Value.specialMissing('_');
    try t.expect(a.isMissing() and z.isMissing() and u.isMissing());
    // sort rank: ._ (0) < . (1) < .A (2) < … < .Z (27)
    try t.expectEqual(@as(u8, 0), Value.missingRank(u.num));
    try t.expectEqual(@as(u8, 1), Value.missingRank(Value.missing.num));
    try t.expectEqual(@as(u8, 2), Value.missingRank(a.num));
    try t.expectEqual(@as(u8, 27), Value.missingRank(z.num));
    // display char
    try t.expectEqual(@as(u8, 'A'), Value.missingChar(a.num));
    try t.expectEqual(@as(u8, 'Z'), Value.missingChar(z.num));
    try t.expectEqual(@as(u8, '_'), Value.missingChar(u.num));
    try t.expectEqual(@as(u8, '.'), Value.missingChar(Value.missing.num));
    // an ordinary arithmetic NaN reads back as the plain missing
    try t.expectEqual(@as(u8, '.'), Value.missingChar(std.math.nan(f64)));
}

test "parseSpecialMissing: text ingestion (ISS-specialmissing)" {
    const t = std.testing;
    // NaN != NaN under expectEqual — compare bit patterns.
    const bits = struct {
        fn of(v: Value) u64 {
            return @bitCast(v.num);
        }
    }.of;
    try t.expectEqual(bits(Value.specialMissing('A')), bits(Value.parseSpecialMissing(".A").?));
    try t.expectEqual(bits(Value.specialMissing('K')), bits(Value.parseSpecialMissing(" .K ").?));
    try t.expectEqual(bits(Value.specialMissing('_')), bits(Value.parseSpecialMissing("._").?));
    try t.expectEqual(bits(Value.specialMissing('a')), bits(Value.parseSpecialMissing(".a").?)); // case-insensitive
    // non-matches fall through (null) → caller's parseFloat path
    try t.expect(Value.parseSpecialMissing(".") == null); // plain missing
    try t.expect(Value.parseSpecialMissing("1") == null);
    try t.expect(Value.parseSpecialMissing(".12") == null);
    try t.expect(Value.parseSpecialMissing(".AB") == null);
    try t.expect(Value.parseSpecialMissing("A") == null);
    try t.expect(Value.parseSpecialMissing("") == null);
}

test "isMissing" {
    const t = std.testing;
    try t.expect(Value.missing.isMissing());
    try t.expect(!(Value{ .num = 0 }).isMissing());
    try t.expect(!(Value{ .str = "" }).isMissing()); // char is never "missing"
}
