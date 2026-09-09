//! Character/string functions (scan/substr/cat family, classification, state
//! lookups, encode/decode, stateless digests), split verbatim out of
//! functions.zig dispatch (QL-A). Shared helpers stay in functions.zig;
//! `null` means "name not mine".
const std = @import("std");
const eval = @import("eval.zig");
const Value = @import("value.zig").Value;

const fns = @import("functions.zig");
const eqi = fns.eqi;
const toNum = fns.toNum;
const toStr = fns.toStr;
const toInt = fns.toInt;
const isMiss = fns.isMiss;
const numVal = fns.numVal;
const badArity = fns.badArity;
const domErr = fns.domErr;
const domErrChar = fns.domErrChar;
const note = fns.note;
const catq = fns.catq;
const catStr = fns.catStr;
const charScan = fns.charScan;
const clampI64 = fns.clampI64;
const compgedCost = fns.compgedCost;
const compress = fns.compress;
const find = fns.find;
const hashDigest = fns.hashDigest;
const hexEncode = fns.hexEncode;
const hexEncodeUpper = fns.hexEncodeUpper;
const hmacDigest = fns.hmacDigest;
const htmlDecode = fns.htmlDecode;
const htmlEncode = fns.htmlEncode;
const isValidName = fns.isValidName;
const levenshtein = fns.levenshtein;
const mapCase = fns.mapCase;
const matchesClass = fns.matchesClass;
const scan = fns.scan;
const soundexCode = fns.soundexCode;
const spedisCost = fns.spedisCost;
const sqlLike = fns.sqlLike;
const stateByFips = fns.stateByFips;
const stateByPostal = fns.stateByPostal;
const substr = fns.substr;
const tranwrd = fns.tranwrd;
const upperDup = fns.upperDup;
const classMod = fns.classMod;
const wordSpec = fns.wordSpec;
const wordTokens = fns.wordTokens;
const urlDecode = fns.urlDecode;
const urlEncode = fns.urlEncode;
const valuesEqual = fns.valuesEqual;
const word_delims = fns.word_delims;
const class_fns = fns.class_fns;
const CharClass = fns.CharClass;

// COMPARE `n` modifier: strip a surrounding name-literal quote pair
// ("text"n → text, or bare "text" → text). Trailing blanks tolerated so a
// blank-padded literal still dequotes. Non-literals return unchanged.
fn dequoteNameLit(s: []const u8) []const u8 {
    var lit = std.mem.trimEnd(u8, s, " ");
    if (lit.len >= 1 and (lit[lit.len - 1] == 'n' or lit[lit.len - 1] == 'N')) lit = lit[0 .. lit.len - 1];
    if (lit.len >= 2 and lit[0] == '"' and lit[lit.len - 1] == '"') return lit[1 .. lit.len - 1];
    return s;
}

/// NVALID(...,'NLITERAL'): is `s` itself a SAS name literal — 'name'n or
/// "name"n, embedded quotes of the same kind doubled, inner name 1-32 bytes.
fn isNameLiteral(s: []const u8) bool {
    if (s.len < 4) return false; // shortest: 'a'n
    const q = s[0];
    if (q != '\'' and q != '"') return false;
    const last = s[s.len - 1];
    if (last != 'n' and last != 'N') return false;
    if (s[s.len - 2] != q) return false;
    var n: usize = 0;
    var i: usize = 1;
    const end = s.len - 2; // inner span: s[1..len-2]
    while (i < end) {
        if (s[i] == q) {
            if (i + 1 < end and s[i + 1] == q) { // doubled quote = one char
                i += 2;
                n += 1;
                continue;
            }
            return false; // undoubled quote inside
        }
        i += 1;
        n += 1;
    }
    return n >= 1 and n <= 32;
}

pub fn dispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!?Value {
    // ── string helpers
    if (eqi(name, "subpad")) { // substring of a given length, blank-padded past the end
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const s = try toStr(ev, args[0]);
        const posf = toNum(args[1]);
        // BUG-charfnsmissingtype: SUBPAD is `Categories: Character` (SAS 9.4
        // Functions and CALL Routines: Reference p.1529 — "Returns a substring
        // that has a length that you specify"), so EVERY give-up arm below is a
        // BLANK CHARACTER. A numeric `.` flips the receiving variable's TYPE and
        // turns a later `put (x) ($char10.);` into a hard ERROR at rc 1.
        if (isMiss(posf)) return .{ .str = "" };
        // NOTE-subpadinvpos: SUBPAD's `position` "is a positive integer" (p.1529),
        // so a nonpositive one is an INVALID argument — and the volume's general
        // rule (p.5) is that an invalid argument, "for example, missing or outside
        // the prescribed range", makes SAS "write a note to the log …, set _ERROR_
        // to 1, and set the result to a missing value". We already returned the
        // missing; the NOTE and the flag were the missing half, so a program
        // branching on _ERROR_ never saw its own bad subscript.
        //
        // The shared domain path (MISC-fnseterror) returns a NUMERIC missing,
        // which is right for its ~40 numeric callers and wrong here — so this
        // routes through `domErrChar`, the character flavour: identical NOTE,
        // identical `_ERROR_=1`, blank result. The alternative (teaching `domErr`
        // itself about types) would have touched every numeric caller for one
        // character one.
        if (posf < 1) return domErrChar(ev, name);
        // Positions and lengths too big for an i64 are "outside the prescribed
        // range" the same way — still CHARACTER.
        const start: usize = @intCast((toInt(posf) orelse return .{ .str = "" }) - 1);
        const outlen: usize = if (args.len == 3)
            @intCast(toInt(@max(toNum(args[2]), 0)) orelse return .{ .str = "" })
        else if (start < s.len) s.len - start else 0;
        const out = try ev.arena.alloc(u8, outlen);
        @memset(out, ' ');
        var i: usize = 0;
        while (i < outlen and start + i < s.len) : (i += 1) out[i] = s[start + i];
        return .{ .str = out };
    }
    if (eqi(name, "transtrn")) { // replace/remove all occurrences of target
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const s = try toStr(ev, args[0]);
        const target = try toStr(ev, args[1]);
        const repl = try toStr(ev, args[2]);
        if (target.len == 0) return .{ .str = try ev.arena.dupe(u8, s) };
        return .{ .str = try std.mem.replaceOwned(u8, ev.arena, s, target, repl) };
    }
    if (eqi(name, "complev")) { // Levenshtein edit distance (trailing blanks ignored)
        if (args.len < 2 or args.len > 4) return badArity(ev, name, "2 to 4", args.len);
        var s1 = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ");
        var s2 = std.mem.trimEnd(u8, try toStr(ev, args[1]), " ");
        // args[2..] hold an optional numeric cutoff and/or a modifier string, either
        // order (mirror the compged branch). levenshtein has no icase param, so
        // casefold s1/s2 up front for i/n.
        var cutoff: ?f64 = null;
        for (args[2..]) |a| {
            if (a == .str) {
                const mods = a.str;
                if (std.mem.indexOfAny(u8, mods, "iInN") != null) {
                    s1 = try upperDup(ev, s1);
                    s2 = try upperDup(ev, s2);
                }
                if (std.mem.indexOfAny(u8, mods, "lL") != null) {
                    s1 = std.mem.trimStart(u8, s1, " ");
                    s2 = std.mem.trimStart(u8, s2, " ");
                }
                if (std.mem.indexOfScalar(u8, mods, ':') != null) {
                    const short = @max(@as(usize, 1), @min(s1.len, s2.len));
                    if (s1.len > short) s1 = s1[0..short];
                    if (s2.len > short) s2 = s2[0..short];
                }
            } else {
                const c = toNum(a);
                if (!isMiss(c)) cutoff = c;
            }
        }
        const dist = try levenshtein(ev, s1, s2);
        if (cutoff) |c| {
            if (@as(f64, @floatFromInt(dist)) > c) return numVal(c);
        }
        return numVal(@floatFromInt(dist));
    }
    if (eqi(name, "compged")) { // generalized edit distance (SAS default costs)
        if (args.len < 2 or args.len > 4) return badArity(ev, name, "2 to 4", args.len);
        var s1 = try toStr(ev, args[0]);
        var s2 = try toStr(ev, args[1]);
        // args[2..] hold an optional numeric cutoff and/or a modifier string, either order
        var cutoff: ?f64 = null;
        var icase = false;
        for (args[2..]) |a| {
            if (a == .str) {
                const mods = a.str;
                if (std.mem.indexOfAny(u8, mods, "iInN") != null) icase = true;
                if (std.mem.indexOfAny(u8, mods, "lL") != null) {
                    s1 = std.mem.trimStart(u8, s1, " ");
                    s2 = std.mem.trimStart(u8, s2, " ");
                }
                if (std.mem.indexOfScalar(u8, mods, ':') != null) {
                    const short = @max(@as(usize, 1), @min(s1.len, s2.len));
                    if (s1.len > short) s1 = s1[0..short];
                    if (s2.len > short) s2 = s2[0..short];
                }
            } else {
                const c = toNum(a);
                if (!isMiss(c)) cutoff = c;
            }
        }
        var cost: f64 = @floatFromInt(try compgedCost(ev, s1, s2, icase));
        if (cutoff) |c| cost = @min(cost, c);
        return numVal(cost);
    }
    if (eqi(name, "spedis")) { // asymmetric spelling distance: convert keyword → query
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const query = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ");
        const keyword = std.mem.trimEnd(u8, try toStr(ev, args[1]), " ");
        const cost: f64 = @floatFromInt(try spedisCost(ev, keyword, query));
        const ratio = cost / @as(f64, @floatFromInt(@max(@as(usize, 1), query.len)));
        return numVal(if (ratio > 1) @floor(ratio) else ratio); // doc: floor only when >1
    }

    // ── US state / FIPS lookups
    if (eqi(name, "stfips")) { // postal → FIPS number
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const st = stateByPostal(try toStr(ev, args[0])) orelse return Value.missing;
        return numVal(@floatFromInt(st.fips));
    }
    if (eqi(name, "fipstate")) { // FIPS → postal code (uppercase)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const f = toInt(toNum(args[0])) orelse return .{ .str = "" };
        const st = stateByFips(f) orelse return .{ .str = "" };
        return .{ .str = try ev.arena.dupe(u8, st.po) };
    }
    if (eqi(name, "stname") or eqi(name, "stnamel")) { // postal → name (upper / mixed)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const st = stateByPostal(try toStr(ev, args[0])) orelse return .{ .str = "" };
        return .{ .str = if (eqi(name, "stname")) try upperDup(ev, st.name) else try ev.arena.dupe(u8, st.name) };
    }
    if (eqi(name, "fipname") or eqi(name, "fipnamel")) { // FIPS → name (upper / mixed)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const f = toInt(toNum(args[0])) orelse return .{ .str = "" };
        const st = stateByFips(f) orelse return .{ .str = "" };
        return .{ .str = if (eqi(name, "fipname")) try upperDup(ev, st.name) else try ev.arena.dupe(u8, st.name) };
    }

    // ── HTML / URL encode+decode
    if (eqi(name, "htmldecode")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = try htmlDecode(ev, try toStr(ev, args[0])) };
    }
    if (eqi(name, "htmlencode")) {
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const s = try toStr(ev, args[0]);
        if (args.len == 1) return .{ .str = try htmlEncode(ev, s) }; // default set, byte-identical
        return try htmlEncodeOpts(ev, s, try toStr(ev, args[1]));
    }
    if (eqi(name, "urldecode")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = try urlDecode(ev, try toStr(ev, args[0])) };
    }
    if (eqi(name, "urlencode")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = try urlEncode(ev, try toStr(ev, args[0])) };
    }

    // ── cryptographic message digests (std.crypto). MD5/SHA256 return the RAW
    // binary digest; the *HEX / HASHING family return a lowercase-hex string.
    if (eqi(name, "md5")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        var d: [16]u8 = undefined;
        std.crypto.hash.Md5.hash(try toStr(ev, args[0]), &d, .{});
        return .{ .str = try ev.arena.dupe(u8, &d) };
    }
    if (eqi(name, "sha256")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        var d: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(try toStr(ev, args[0]), &d, .{});
        return .{ .str = try ev.arena.dupe(u8, &d) };
    }
    if (eqi(name, "sha256hex")) { // hex SHA256 digest; optional flag arg accepted (ignored)
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        var d: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(try toStr(ev, args[0]), &d, .{});
        return .{ .str = try hexEncode(ev, &d) };
    }
    if (eqi(name, "sha256hmachex")) { // HMAC-SHA256(key,msg) as hex
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const key = try toStr(ev, args[0]);
        const msg = try toStr(ev, args[1]);
        var d: [32]u8 = undefined;
        std.crypto.auth.hmac.sha2.HmacSha256.create(&d, msg, key);
        return .{ .str = try hexEncode(ev, &d) };
    }
    if (eqi(name, "hashing")) { // HASHING(method, message [,flag]) → hex digest
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const method = try toStr(ev, args[0]);
        var buf: [64]u8 = undefined;
        // BUG-charfnsmissingtype: unknown method → blank CHARACTER, never `.`
        // BUG-charfnsnodomerr: and that blank is LOUD. p.976 states the failure
        // mode verbatim — "If method is invalid, the returned digest is blank,
        // and a note, warning, or error message is issued stating that the
        // argument is invalid." — so this is doc-mandated, not house consistency.
        const n = hashDigest(method, try toStr(ev, args[1]), &buf) orelse return domErrChar(ev, name);
        return .{ .str = try hexEncodeUpper(ev, buf[0..n]) }; // SAS HASHING → UPPERCASE hex (doc p.975)
    }
    if (eqi(name, "hashing_hmac")) { // HASHING_HMAC(method, key, message [,flag]) → hex
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const method = try toStr(ev, args[0]);
        const key = try toStr(ev, args[1]);
        var buf: [64]u8 = undefined;
        // BUG-charfnsmissingtype: unknown method → blank CHARACTER, never `.`
        // BUG-charfnsnodomerr: loud, on p.979's own sentence — identical wording
        // to HASHING's ("a note, warning, or error message is issued").
        const n = hmacDigest(method, key, try toStr(ev, args[2]), &buf) orelse return domErrChar(ev, name);
        return .{ .str = try hexEncodeUpper(ev, buf[0..n]) }; // SAS → UPPERCASE hex, matches HASHING_TERM
    }
    // ── character classification: position of first char in/not-in a class
    inline for (class_fns) |cf| if (eqi(name, cf.name)) return try charScan(ev, name, args, cf.cls, cf.negate);
    if (eqi(name, "rank")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        return numVal(@floatFromInt(if (s.len > 0) s[0] else @as(u8, ' ')));
    }
    if (eqi(name, "byte")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const n = toNum(args[0]);
        // BUG-charfnsmissingtype: BYTE is `Categories: Character` (SAS 9.4 Functions
        // and CALL Routines: Reference p.282, `Range 0–255`), so an out-of-range or
        // missing `n` yields the CHARACTER missing — a blank — not a numeric `.`.
        // p.5's general invalid-argument rule says "sets the result to a missing
        // value"; for a character function that missing value is blank, and handing
        // back a `.` here flips the receiving variable's TYPE (see the module note
        // on scan, BUG-scanmissingtype).
        // BUG-charfnsnodomerr: that blank is LOUD. BYTE's own entry states
        // `Range 0–255` on `n`, so an out-of-range or missing `n` is exactly
        // p.5's case — "If the value of an argument is invalid (for example,
        // missing or outside the prescribed range), SAS writes a note to the log
        // indicating that the argument is invalid, sets _ERROR_ to 1, and sets
        // the result to a missing value." domErrChar is all three at once.
        if (isMiss(n) or n < 0 or n > 255) return domErrChar(ev, name);
        const out = try ev.arena.alloc(u8, 1);
        out[0] = @intFromFloat(n);
        return .{ .str = out };
    }
    if (eqi(name, "collate")) {
        // COLLATE(start[,end]) | (start,,length) — ASCII run from `start`. With no
        // end-position, run to the end of the sequence or `length` chars (default
        // 200), capped at 255 (doc p.521).
        // BUG-charfnsmissingtype: COLLATE is `Categories: Character` (p.521), so
        // every give-up arm below hands back a BLANK CHARACTER, not a numeric `.`.
        if (args.len < 1 or args.len > 3) return badArity(ev, name, "1 to 3", args.len);
        // BUG-collateomittedstart: an OMITTED start-position defaults to 0. The
        // Functions Reference p.524 Example 3 is literally `y = collate(,,56);`,
        // described as "the COLLATE function returns the first 56 characters of the
        // ASCII collating sequence" — first 56 means positions 0..55, so the empty
        // slot is position 0, not a give-up.
        // The omission IS distinguishable from an explicit `collate(.)`: the parser
        // fills an empty positional slot with an empty-STRING literal to keep the
        // arg count (parser_expr.zig parseCall), while `.` arrives as a numeric
        // missing. So test the union TAG *before* toNum() flattens both to NaN.
        // ponytail: a hand-written `collate("")` is the same AST as the omission
        // and so also defaults to 0. Undocumented, and character-to-numeric on a
        // blank is a missing anyway; not worth a second channel to separate.
        const omitted_start = args[0] == .str and args[0].str.len == 0;
        const lo: f64 = if (omitted_start) 0 else toNum(args[0]);
        // BUG-charfnsnodomerr splits what follows in two, because the doc does.
        // DOC-SILENT: an explicit `collate(.)` gives up blank and stays quiet
        // (pinned in BUG-charfnsmissingtype). Note the ORIGINAL premise here —
        // "an omitted arg is indistinguishable from `collate(.)`" — was DISPROVEN
        // by BUG-collateomittedstart above; the decline still stands, but on the
        // narrower and correct ground that only the EXPLICIT missing reaches here.
        if (isMiss(lo)) return .{ .str = "" };
        // Out of the sequence, though, is p.5's "outside the prescribed range":
        // p.522 pins it, "The ASCII collating sequence contains 256 positions,
        // referenced with the position numbers 0 through 255." → loud.
        if (lo < 0 or lo > 255) return domErrChar(ev, name);
        const a: u16 = @intFromFloat(lo);
        // end-position form: a non-missing 2nd arg
        const end_pos: ?f64 = if (args.len >= 2) blk: {
            const e = toNum(args[1]);
            break :blk if (isMiss(e)) null else e;
        } else null;
        const b: u16 = if (end_pos) |hi| bl: {
            // p.522 "Tips end-position must be larger than start-position" and
            // "The maximum end-position … is 255" are both prescribed ranges, so
            // BUG-charfnsnodomerr makes this arm loud under p.5 as well.
            if (hi > 255 or hi < lo) return domErrChar(ev, name);
            break :bl @intFromFloat(hi);
        } else bl: {
            const len_arg = if (args.len == 3) toNum(args[2]) else std.math.nan(f64);
            const length: u16 = if (isMiss(len_arg)) 200 else @intFromFloat(@max(len_arg, 0));
            // DOC-SILENT (BUG-charfnsnodomerr): `length` is the one COLLATE
            // argument the doc gives NO range for — p.522 says only "specifies
            // the number of characters" / "Default 200". With no prescribed
            // range there is nothing for p.5 to be outside of, so a zero (or
            // clamped-negative) length stays a quiet blank. Declined, not missed.
            if (length == 0) return .{ .str = "" }; // zero-length run is still CHARACTER
            break :bl @min(@as(u16, 255), a + length - 1);
        };
        const out = try ev.arena.alloc(u8, b - a + 1);
        for (out, 0..) |*c, i| c.* = @intCast(a + i);
        return .{ .str = out };
    }
    if (eqi(name, "compbl")) {
        // collapse runs of blanks to a single blank
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        var out: std.ArrayList(u8) = .empty;
        var prev_blank = false;
        for (s) |c| {
            if (c == ' ') {
                if (!prev_blank) try out.append(ev.arena, ' ');
                prev_blank = true;
            } else {
                try out.append(ev.arena, c);
                prev_blank = false;
            }
        }
        return .{ .str = out.items };
    }
    if (eqi(name, "compare")) {
        // 0 if equal (blank-padded); else signed position of the first difference.
        // Modifiers (case-insensitive): `i` ignore-case, `l` strip leading blanks,
        // `:` truncate the longer operand to the shorter's length, `n` dequote a
        // name literal ("text"n → text) AND ignore case (funcref p.526).
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        var s1 = try toStr(ev, args[0]);
        var s2 = try toStr(ev, args[1]);
        var icase = false;
        var colon = false;
        if (args.len == 3) {
            const mods = try toStr(ev, args[2]);
            icase = std.mem.indexOfAny(u8, mods, "iI") != null;
            if (std.mem.indexOfAny(u8, mods, "nN") != null) {
                icase = true; // `n` implies case-insensitive
                s1 = dequoteNameLit(s1);
                s2 = dequoteNameLit(s2);
            }
            if (std.mem.indexOfAny(u8, mods, "lL") != null) {
                s1 = std.mem.trimStart(u8, s1, " ");
                s2 = std.mem.trimStart(u8, s2, " ");
            }
            colon = std.mem.indexOfScalar(u8, mods, ':') != null;
        }
        const n = if (colon) @min(s1.len, s2.len) else @max(s1.len, s2.len);
        var i: usize = 0;
        while (i < n) : (i += 1) {
            var c1 = if (i < s1.len) s1[i] else ' ';
            var c2 = if (i < s2.len) s2[i] else ' ';
            if (icase) {
                c1 = std.ascii.toLower(c1);
                c2 = std.ascii.toLower(c2);
            }
            if (c1 != c2) return numVal(@floatFromInt(if (c1 < c2) -%@as(i64, @intCast(i + 1)) else @as(i64, @intCast(i + 1))));
        }
        return numVal(0);
    }
    if (eqi(name, "cat")) {
        // concatenate arguments with NO blank-stripping (unlike CATS/CATT/CATX)
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        var out: std.ArrayList(u8) = .empty;
        for (args) |arg| try out.appendSlice(ev.arena, try catStr(ev, arg));
        return .{ .str = out.items };
    }

    // ── string
    if (eqi(name, "upcase")) return try mapCase(ev, name, args, std.ascii.toUpper);
    if (eqi(name, "lowcase")) return try mapCase(ev, name, args, std.ascii.toLower);
    if (eqi(name, "trim")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        const tr = std.mem.trimEnd(u8, s, " ");
        return .{ .str = if (tr.len == 0) " " else tr }; // SAS TRIM: all-blank → one blank
    }
    if (eqi(name, "strip")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        return .{ .str = std.mem.trim(u8, s, " ") }; // all-blank → ""
    }
    if (eqi(name, "left")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        const body = std.mem.trimStart(u8, s, " ");
        const out = try ev.arena.alloc(u8, s.len); // LEFT preserves length
        @memcpy(out[0..body.len], body);
        @memset(out[body.len..], ' ');
        return .{ .str = out };
    }
    if (eqi(name, "length")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        const tr = std.mem.trimEnd(u8, s, " ");
        return numVal(@floatFromInt(if (tr.len == 0) @as(usize, 1) else tr.len)); // blank → 1
    }
    if (eqi(name, "substr")) return try substr(ev, name, args);
    if (eqi(name, "index")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        // ponytail: trim BOTH operands (BUG-likepadwidth) — this doubles as the
        // WHERE CONTAINS path (parser desugars `x contains y` → index(x,y)>0),
        // whose needle must not NOMATCH just because it carries trailing
        // blanks (`'cat' contains 't '`). True SAS pads the SOURCE to its
        // declared width and keeps the needle verbatim; the declared width
        // isn't reachable at the functions boundary (EPIC-charfixedwidth).
        // Trim-both gives SAS's 1-based position for any match not spanning
        // into padding, and agrees with SAS on the >0 CONTAINS question.
        const s = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ");
        const sub = std.mem.trimEnd(u8, try toStr(ev, args[1]), " ");
        if (sub.len == 0) return numVal(0);
        const p = std.mem.indexOf(u8, s, sub);
        return numVal(@floatFromInt(if (p) |i| i + 1 else 0)); // 1-based, 0 = not found
    }
    if (eqi(name, "missing")) {
        // 1 if the arg is missing: numeric `.` (NaN) or an all-blank char.
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const miss = switch (args[0]) {
            .num => args[0].isMissing(),
            .str => |s| std.mem.trim(u8, s, " ").len == 0,
        };
        return numVal(if (miss) 1 else 0);
    }
    if (eqi(name, "like")) {
        // SQL LIKE: `%` = any sequence, `_` = any single char, else literal.
        // ponytail: trim BOTH operands (BUG-likepadwidth) — true SAS compares
        // the pattern against the value blank-padded to its DECLARED width
        // (trailing blanks significant, `_` matches a blank), but the width
        // isn't reachable at the functions boundary: args arrive as evaluated
        // Values, the width lives in the PDV/exec (EPIC-charfixedwidth).
        // Until the umbrella lands, symmetric trim at least keeps a trailing-
        // blank pattern matchable; known divergence: a wildcard-less pattern
        // on an over-wide var (`trt like 'Placebo'` on $20) MATCHes here but
        // NOMATCHes in SAS.
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const s = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ");
        const pat = std.mem.trimEnd(u8, try toStr(ev, args[1]), " ");
        return numVal(if (sqlLike(s, pat)) 1 else 0);
    }
    if (eqi(name, "catx")) {
        // catx(sep, a, b, …): strip each value, join the non-blank ones with sep.
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        const sep = try toStr(ev, args[0]); // separator used verbatim
        var parts: std.ArrayList([]const u8) = .empty;
        for (args[1..]) |arg| {
            if (arg == .num and isMiss(arg.num)) continue; // missing numeric → skip
            const stripped = std.mem.trim(u8, try catStr(ev, arg), " ");
            if (stripped.len > 0) try parts.append(ev.arena, stripped);
        }
        return .{ .str = try std.mem.join(ev.arena, sep, parts.items) };
    }
    if (eqi(name, "cats") or eqi(name, "catt")) {
        // CATS strips leading+trailing blanks per item; CATT trims trailing only.
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        const strip_both = eqi(name, "cats");
        var out: std.ArrayList(u8) = .empty;
        for (args) |arg| {
            const raw = try catStr(ev, arg);
            try out.appendSlice(ev.arena, if (strip_both) std.mem.trim(u8, raw, " ") else std.mem.trimEnd(u8, raw, " "));
        }
        return .{ .str = out.items };
    }
    if (eqi(name, "catq")) return try catq(ev, name, args);
    if (eqi(name, "substrn")) {
        // like SUBSTR but tolerant: positions outside [1, len] are simply ignored.
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const s = try toStr(ev, args[0]);
        const posf = toNum(args[1]);
        if (isMiss(posf)) return .{ .str = "" };
        const slen: i64 = @intCast(s.len);
        const pos = clampI64(posf);
        const lenf = if (args.len == 3) toNum(args[2]) else 0;
        if (isMiss(lenf)) return .{ .str = "" };
        var start = pos; // 1-based inclusive
        // 2-arg runs to end of string (BUG-substrn2argpos: the old
        // `posf + s.len` default length double-counted pos, truncating
        // nonpositive starts); 3-arg keeps the explicit-length window.
        var end = if (args.len == 3) pos + clampI64(lenf) else slen + 1; // 1-based exclusive
        if (start < 1) start = 1;
        if (end > slen + 1) end = slen + 1;
        if (end <= start) return .{ .str = "" };
        return .{ .str = s[@intCast(start - 1)..@intCast(end - 1)] };
    }
    if (eqi(name, "quote")) {
        if (args.len < 1) return badArity(ev, name, "1 or 2", args.len);
        // QUOTE keeps trailing blanks INSIDE the quotes (p.1393: the
        // receiving variable must hold the argument "including trailing
        // blanks"). Was trimEnd (BUG-quotetrailingblank).
        const s = try toStr(ev, args[0]);
        const qc: u8 = if (args.len >= 2) blk: {
            const q = try toStr(ev, args[1]);
            break :blk if (q.len > 0) q[0] else '"';
        } else '"';
        var out: std.ArrayList(u8) = .empty;
        try out.append(ev.arena, qc);
        for (s) |c| {
            if (c == qc) try out.append(ev.arena, qc); // double an embedded quote
            try out.append(ev.arena, c);
        }
        try out.append(ev.arena, qc);
        return .{ .str = out.items };
    }
    if (eqi(name, "dequote")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        if (s.len >= 2 and (s[0] == '"' or s[0] == '\'') and s[s.len - 1] == s[0]) {
            const qc = s[0];
            const inner = s[1 .. s.len - 1];
            var out: std.ArrayList(u8) = .empty;
            var i: usize = 0;
            while (i < inner.len) : (i += 1) {
                try out.append(ev.arena, inner[i]);
                if (inner[i] == qc and i + 1 < inner.len and inner[i + 1] == qc) i += 1; // collapse doubled
            }
            return .{ .str = out.items };
        }
        return .{ .str = s };
    }
    if (eqi(name, "translate")) {
        if (args.len < 3) return badArity(ev, name, "3 or more", args.len);
        if (args.len % 2 == 0) return badArity(ev, name, "to/from pairs", args.len); // BUG-translatepairs: loud, never half-translate
        const out = try ev.arena.dupe(u8, try toStr(ev, args[0]));
        var i: usize = 1;
        while (i + 1 < args.len) : (i += 2) {
            const to = try toStr(ev, args[i]);
            const from = try toStr(ev, args[i + 1]);
            for (out) |*c| if (std.mem.indexOfScalar(u8, from, c.*)) |idx| {
                c.* = if (idx < to.len) to[idx] else ' ';
            };
        }
        return .{ .str = out };
    }
    if (eqi(name, "verify")) {
        // position of the first char of arg0 not present in any of the other args
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const s = try toStr(ev, args[0]);
        for (s, 0..) |c, i| {
            var in_set = false;
            for (args[1..]) |setarg| if (std.mem.indexOfScalar(u8, try toStr(ev, setarg), c) != null) {
                in_set = true;
                break;
            };
            if (!in_set) return numVal(@floatFromInt(i + 1));
        }
        return numVal(0);
    }
    if (eqi(name, "reverse")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        const out = try ev.arena.alloc(u8, s.len);
        for (s, 0..) |c, i| out[s.len - 1 - i] = c;
        return .{ .str = out };
    }
    if (eqi(name, "repeat")) {
        // SAS REPEAT(str, n) returns n+1 copies (n *additional* repetitions)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const s = try toStr(ev, args[0]);
        const nf = toNum(args[1]);
        if (isMiss(nf) or nf < 0 or s.len == 0) return .{ .str = s };
        const n: usize = @intCast(toInt(nf) orelse return .{ .str = s }); // guards ±inf/huge
        // BUG-repeatoom: SAS truncates to the receiving variable's length (char max
        // 32767), so cap the build there — a huge finite count must not OOM/hang.
        const max_len: usize = 32767;
        var out: std.ArrayList(u8) = .empty;
        var k: usize = 0;
        while (k <= n and out.items.len < max_len) : (k += 1) {
            const room = max_len - out.items.len;
            try out.appendSlice(ev.arena, if (s.len <= room) s else s[0..room]);
        }
        return .{ .str = out.items };
    }
    if (eqi(name, "propcase")) {
        if (args.len < 1) return badArity(ev, name, "1 or 2", args.len);
        const s = try toStr(ev, args[0]);
        const delims = if (args.len >= 2) try toStr(ev, args[1]) else " \t/-(.";
        const out = try ev.arena.alloc(u8, s.len);
        var word_start = true;
        for (s, 0..) |c, i| {
            if (std.mem.indexOfScalar(u8, delims, c) != null) {
                out[i] = c;
                word_start = true;
            } else {
                out[i] = if (word_start) std.ascii.toUpper(c) else std.ascii.toLower(c);
                word_start = false;
            }
        }
        return .{ .str = out };
    }
    if (eqi(name, "kstrip")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = std.mem.trim(u8, try toStr(ev, args[0]), " ") };
    }
    if (eqi(name, "constant")) {
        if (args.len < 1) return badArity(ev, name, "1 or 2", args.len);
        const cn = try toStr(ev, args[0]);
        if (eqi(cn, "pi")) return numVal(std.math.pi);
        if (eqi(cn, "e")) return numVal(std.math.e);
        if (eqi(cn, "euler")) return numVal(0.5772156649015329); // Euler-Mascheroni γ
        if (eqi(cn, "golden")) return numVal((@sqrt(5.0) - 1.0) / 2.0); // SAS GOLDEN = golden ratio − 1 = 1/φ ≈ 0.6180
        const BIG = std.math.floatMax(f64);
        const SMALL = std.math.floatMin(f64);
        const EPS = std.math.floatEps(f64);
        if (eqi(cn, "maceps")) return numVal(EPS);
        if (eqi(cn, "sqrtmaceps")) return numVal(@sqrt(EPS));
        if (eqi(cn, "big")) return numVal(BIG);
        if (eqi(cn, "small")) return numVal(SMALL);
        // GAP-constmissing (doc p.555): the *RECIP pair — on IEEE hardware 1/BIG
        // is subnormal-but-finite and 1/SMALL is finite (both re-invert), so
        // BIGRECIP=BIG and SMALLRECIP=SMALL here.
        if (eqi(cn, "bigrecip")) return numVal(BIG);
        if (eqi(cn, "smallrecip")) return numVal(SMALL);
        if (eqi(cn, "sqrtbig")) return numVal(@sqrt(BIG));
        if (eqi(cn, "sqrtsmall")) return numVal(@sqrt(SMALL));
        if (eqi(cn, "exactint")) {
            // largest int exactly representable in a SAS numeric of nbytes (doc
            // p.557: 2..8, default 8): mantissa = 8·nbytes−12 bits → 2^(8·n−11).
            if (args.len < 2 or isMiss(toNum(args[1]))) return numVal(9007199254740992); // 2^53
            const nb = toInt(toNum(args[1])) orelse return domErr(ev, name);
            if (nb < 2 or nb > 8) return domErr(ev, name);
            return numVal(@exp2(@as(f64, @floatFromInt(8 * nb - 11))));
        }
        // LOG<constant><,base> (doc p.557-559): base defaults to E and must
        // exceed 1+SQRTMACEPS — a bad base fails loud, never a wrong number.
        if (eqi(cn, "logbig") or eqi(cn, "logbigrecip") or eqi(cn, "logsmall") or
            eqi(cn, "logsmallrecip") or eqi(cn, "logmaceps"))
        {
            const x = if (eqi(cn, "logbig") or eqi(cn, "logbigrecip")) BIG else if (eqi(cn, "logmaceps")) EPS else SMALL;
            if (args.len >= 2 and !isMiss(toNum(args[1]))) {
                const b = toNum(args[1]);
                if (b <= 1 + @sqrt(EPS)) return domErr(ev, name);
                return numVal(@log(x) / @log(b));
            }
            return numVal(@log(x));
        }
        return domErr(ev, name);
    }
    if (eqi(name, "count")) {
        // non-overlapping occurrences of a substring; optional 3rd-arg modifiers
        // i=ignore-case, t=trim trailing blanks (both string and substring), like
        // COUNTC/COUNTW/FINDC. Unknown letters fail LOUD (NOTE-findcunknownmod,
        // D-002) — same policy as wordSpec, which SCAN/COUNTW/FINDW share.
        // (BUG-countmodifiers)
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        var s = try toStr(ev, args[0]);
        var sub = try toStr(ev, args[1]);
        var ci = false;
        var trim = false;
        if (args.len >= 3) {
            const mods = toStr(ev, args[2]) catch "";
            for (mods) |m| switch (std.ascii.toLower(m)) {
                'i' => ci = true,
                't' => trim = true,
                'o', ' ' => {}, // o: process-once hint, no effect here; blanks ignored
                else => {
                    ev.diags.report(.err, 0, "{s}() modifier '{c}' is not supported yet", .{ name, m }) catch {};
                    return Value.missing;
                },
            };
        }
        if (trim) {
            s = std.mem.trimEnd(u8, s, " ");
            sub = std.mem.trimEnd(u8, sub, " ");
        }
        if (sub.len == 0) return numVal(0);
        var c: f64 = 0;
        var i: usize = 0;
        while (i + sub.len <= s.len) {
            const win = s[i .. i + sub.len];
            const hit = if (ci) std.ascii.eqlIgnoreCase(win, sub) else std.mem.eql(u8, win, sub);
            if (hit) {
                c += 1;
                i += sub.len;
            } else i += 1;
        }
        return numVal(c);
    }
    if (eqi(name, "countc")) {
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        var s = try toStr(ev, args[0]);
        var set = try toStr(ev, args[1]);
        // optional modifiers (3rd arg): a class letter adds a whole class to the set
        // (a=alpha d=digit u=upper l=lower s=space p=punct c=cntrl f=first g=graph
        // n=name w=print x=hex); i=ignore-case, t=trim, v=count chars NOT in the set
        // (BUG-countcmodifiers -- same gap FINDC had).
        var classes: [16]CharClass = undefined;
        var ncls: usize = 0;
        var ci = false;
        var trim = false;
        var invert = false;
        if (args.len >= 3) {
            const mods = toStr(ev, args[2]) catch "";
            for (mods) |m| {
                if (classMod(m)) |cc| {
                    if (ncls < classes.len) {
                        classes[ncls] = cc;
                        ncls += 1;
                    }
                } else switch (std.ascii.toLower(m)) {
                    'i' => ci = true,
                    't' => trim = true,
                    'v', 'k' => invert = true, // count chars NOT in the set (SAS uses k, like FINDC)
                    'o', ' ' => {}, // o: process-once hint, no effect here; blanks ignored
                    else => { // NOTE-findcunknownmod: fail loud like SCAN/COUNTW/FINDW (D-002)
                        ev.diags.report(.err, 0, "{s}() modifier '{c}' is not supported yet", .{ name, m }) catch {};
                        return Value.missing;
                    },
                }
            }
        }
        if (trim) {
            s = std.mem.trimEnd(u8, s, " ");
            set = std.mem.trimEnd(u8, set, " ");
        }
        const cls = classes[0..ncls];
        var c: f64 = 0;
        for (s) |ch| {
            var inset = std.mem.indexOfScalar(u8, set, ch) != null;
            if (!inset) for (cls) |cc| if (matchesClass(ch, cc)) {
                inset = true;
                break;
            };
            if (!inset and ci) {
                const other = if (std.ascii.isUpper(ch)) std.ascii.toLower(ch) else std.ascii.toUpper(ch);
                if (std.mem.indexOfScalar(u8, set, other) != null) inset = true;
            }
            if (inset != invert) c += 1;
        }
        return numVal(c);
    }
    if (eqi(name, "countw")) {
        // COUNTW(string <, chars> <, modifiers>): word count over the shared
        // default delimiter set (BUG-scandelim). Class adders + k/i/t honored
        // (BUG-scanmodifiers); `m` counts the empty words too.
        if (args.len < 1 or args.len > 3) return badArity(ev, name, "1 to 3", args.len);
        var s = try toStr(ev, args[0]);
        const list = if (args.len >= 2) try toStr(ev, args[1]) else word_delims;
        const mods = if (args.len >= 3) try toStr(ev, args[2]) else "";
        const spec = (try wordSpec(ev, name, list, mods)) orelse return Value.missing;
        if (spec.word_number) { // `e` is FINDW-only
            ev.diags.report(.err, 0, "{s}() modifier 'e' is not supported yet", .{name}) catch {};
            return Value.missing;
        }
        if (spec.trim) s = std.mem.trimEnd(u8, s, " ");
        if (s.len == 0) return numVal(0);
        const toks = try wordTokens(ev.arena, s, &spec.set, spec.keep_empty);
        return numVal(@floatFromInt(toks.items.len));
    }
    if (eqi(name, "indexc")) {
        // position of the first char of arg0 that appears in any following set
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const s = try toStr(ev, args[0]);
        for (s, 0..) |ch, i| for (args[1..]) |setarg| {
            if (std.mem.indexOfScalar(u8, try toStr(ev, setarg), ch) != null) return numVal(@floatFromInt(i + 1));
        };
        return numVal(0);
    }
    if (eqi(name, "findc")) {
        // FINDC(string, char-list <, modifiers | startpos>): first position of a
        // char that is in the list OR in a class named by a modifier letter
        // (a=alpha d=digit u=upper l=lower s=space p=punct c=cntrl f=first-name
        // g=graph n=name w=print x=hex); i=ignore-case, t=trim, b=backward; a
        // NUMERIC arg is a start position (negative → backward). (BUG-findcmodifiers)
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        var s = try toStr(ev, args[0]);
        var list = try toStr(ev, args[1]);
        var classes: [16]CharClass = undefined;
        var ncls: usize = 0;
        var ci = false;
        var trim = false;
        var backward = false;
        var complement = false; // k modifier (BUG-findckmod)
        var start: i64 = 1;
        var have_start = false;
        for (args[2..]) |arg| switch (arg) {
            .num => |x| {
                if (!isMiss(x)) {
                    start = @intFromFloat(@trunc(x));
                    have_start = true;
                }
            },
            .str => |mods| for (mods) |m| {
                if (classMod(m)) |cc| {
                    if (ncls < classes.len) {
                        classes[ncls] = cc;
                        ncls += 1;
                    }
                } else switch (std.ascii.toLower(m)) {
                    'i' => ci = true,
                    't' => trim = true,
                    'b' => backward = true,
                    'k' => complement = true, // find a char NOT in the set (BUG-findckmod)
                    'o', ' ' => {}, // o: process-once hint, no effect here; blanks ignored
                    else => { // NOTE-findcunknownmod: fail loud like SCAN/COUNTW/FINDW (D-002)
                        ev.diags.report(.err, 0, "{s}() modifier '{c}' is not supported yet", .{ name, m }) catch {};
                        return Value.missing;
                    },
                }
            },
        };
        if (trim) {
            s = std.mem.trimEnd(u8, s, " ");
            list = std.mem.trimEnd(u8, list, " ");
        }
        if (have_start and start < 0) backward = true;
        const inSet = struct {
            fn f(ch: u8, lst: []const u8, cls: []const CharClass, insensitive: bool) bool {
                for (cls) |cc| if (matchesClass(ch, cc)) return true;
                if (std.mem.indexOfScalar(u8, lst, ch) != null) return true;
                if (insensitive) {
                    const other = if (std.ascii.isUpper(ch)) std.ascii.toLower(ch) else std.ascii.toUpper(ch);
                    if (std.mem.indexOfScalar(u8, lst, other) != null) return true;
                }
                return false;
            }
        }.f;
        const cls = classes[0..ncls];
        if (backward) {
            var i: usize = if (have_start) @min(@as(usize, @intCast(@abs(start))), s.len) else s.len;
            while (i > 0) : (i -= 1) if (inSet(s[i - 1], list, cls, ci) != complement) return numVal(@floatFromInt(i));
        } else {
            const from: usize = if (have_start and start > 1) @intCast(start - 1) else 0;
            var i: usize = from;
            while (i < s.len) : (i += 1) if (inSet(s[i], list, cls, ci) != complement) return numVal(@floatFromInt(i + 1));
        }
        return numVal(0);
    }
    if (eqi(name, "indexw")) {
        // position of `word` delimited by `delim` (default blank — p.1034; do
        // NOT widen, that blank-only default is INDEXW's documented behavior)
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const s = try toStr(ev, args[0]);
        const w = try toStr(ev, args[1]);
        const delim = if (args.len >= 3) try toStr(ev, args[2]) else " ";
        if (w.len == 0) return numVal(0);
        var i: usize = 0;
        while (i + w.len <= s.len) : (i += 1) {
            const before = i == 0 or std.mem.indexOfScalar(u8, delim, s[i - 1]) != null;
            const after = i + w.len == s.len or std.mem.indexOfScalar(u8, delim, s[i + w.len]) != null;
            if (before and after and std.mem.eql(u8, s[i .. i + w.len], w)) return numVal(@floatFromInt(i + 1));
        }
        return numVal(0);
    }
    if (eqi(name, "findw")) {
        // FINDW(string, word <, chars> <, modifiers> <, startpos>): position of
        // `word` as a delimited word, 0 if absent. 2-arg default delimiters are
        // the full SCAN set (FINDW p.781 — INDEXW above stays blank-only).
        // Modifiers: class adders + i/t/k; `e` returns the WORD NUMBER instead
        // (BUG-findwdefaults). A numeric optional arg is the start position.
        if (args.len < 2 or args.len > 5) return badArity(ev, name, "2 to 5", args.len);
        var s = try toStr(ev, args[0]);
        var w = try toStr(ev, args[1]);
        var list: []const u8 = word_delims;
        var mods: []const u8 = "";
        var start: usize = 0; // 0-based offset of the search window
        var nstr: usize = 0;
        for (args[2..]) |arg| switch (arg) {
            .num => |x| {
                if (!isMiss(x)) {
                    const p = toInt(x) orelse return numVal(0); // huge → beyond the string
                    start = if (p <= 1) 0 else @min(@as(usize, @intCast(p - 1)), s.len);
                }
            },
            .str => |v| {
                nstr += 1;
                if (nstr == 1) list = v else mods = v;
            },
        };
        const spec = (try wordSpec(ev, name, list, mods)) orelse return Value.missing;
        if (spec.keep_empty) { // `m` is SCAN/COUNTW-only
            ev.diags.report(.err, 0, "{s}() modifier 'm' is not supported yet", .{name}) catch {};
            return Value.missing;
        }
        if (spec.trim) {
            s = std.mem.trimEnd(u8, s, " ");
            w = std.mem.trimEnd(u8, w, " ");
        }
        if (w.len == 0 or start >= s.len) return numVal(0);
        // ponytail: `e` word numbers are relative to the search window.
        const win = s[start..];
        var i: usize = 0;
        var wnum: usize = 0;
        while (i < win.len) {
            while (i < win.len and spec.set[win[i]]) i += 1;
            const ws = i;
            while (i < win.len and !spec.set[win[i]]) i += 1;
            if (i == ws) break;
            wnum += 1;
            const tok = win[ws..i];
            const hit = if (spec.ci) std.ascii.eqlIgnoreCase(tok, w) else std.mem.eql(u8, tok, w);
            if (hit) return numVal(@floatFromInt(if (spec.word_number) wnum else start + ws + 1));
        }
        return numVal(0);
    }
    if (eqi(name, "char")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const s = try toStr(ev, args[0]);
        const p = toNum(args[1]);
        if (isMiss(p) or p < 1 or p > @as(f64, @floatFromInt(s.len))) return .{ .str = " " };
        const i: usize = @intFromFloat(p);
        return .{ .str = s[i - 1 .. i] };
    }
    if (eqi(name, "first")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        return .{ .str = if (s.len > 0) s[0..1] else " " };
    }
    if (eqi(name, "right")) {
        // right-justify: trailing blanks moved to the front, length preserved
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        const body = std.mem.trimEnd(u8, s, " ");
        const out = try ev.arena.alloc(u8, s.len);
        @memset(out[0 .. s.len - body.len], ' ');
        @memcpy(out[s.len - body.len ..], body);
        return .{ .str = out };
    }
    if (eqi(name, "trimn")) {
        // TRIM but all-blank → "" (TRIM gives one blank)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ") };
    }
    if (eqi(name, "lengthn")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return numVal(@floatFromInt(std.mem.trimEnd(u8, try toStr(ev, args[0]), " ").len)); // 0 for blank
    }
    if (eqi(name, "lengthc") or eqi(name, "lengthm")) {
        // storage/memory length — for an in-memory value, its full byte length
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return numVal(@floatFromInt((try toStr(ev, args[0])).len));
    }
    if (eqi(name, "modz")) {
        // MOD with no fuzzing (exact remainder)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const x = toNum(args[0]);
        const y = toNum(args[1]);
        if (isMiss(x) or isMiss(y)) return Value.missing;
        // GAP-modzerror: zero divisor takes the shared domErr path (NOTE +
        // _ERROR_=1 + missing), same as MOD — was silent missing, so the
        // `if _error_ then …` idiom never fired (qa-findings-tick138).
        if (y == 0) return domErr(ev, name);
        return numVal(x - @trunc(x / y) * y);
    }
    if (eqi(name, "choosen") or eqi(name, "choosec")) {
        // the index-th value (1-based; negative counts from the end)
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const idxf = toNum(args[0]);
        if (isMiss(idxf)) return if (eqi(name, "choosec")) .{ .str = "" } else Value.missing;
        const nvals: i64 = @intCast(args.len - 1);
        // guard @intFromFloat: a huge index is out of range anyway, so short-circuit
        // before the conversion would panic (|idxf| well past nvals can't select).
        if (@abs(idxf) > @as(f64, @floatFromInt(nvals))) return if (eqi(name, "choosec")) .{ .str = "" } else Value.missing;
        var idx: i64 = @intFromFloat(idxf);
        if (idx < 0) idx = nvals + idx + 1;
        if (idx < 1 or idx > nvals) return if (eqi(name, "choosec")) .{ .str = "" } else Value.missing;
        return args[@intCast(idx)];
    }
    if (eqi(name, "whichn") or eqi(name, "whichc")) {
        // 1-based position of arg0 among the following values (0 if none). A MISSING
        // search key returns missing before any search (WHICHN p.1684 / WHICHC p.1683).
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const key_missing = if (eqi(name, "whichn"))
            isMiss(toNum(args[0]))
        else
            std.mem.trim(u8, try toStr(ev, args[0]), " ").len == 0;
        if (key_missing) return Value.missing;
        for (args[1..], 0..) |v, i| if (valuesEqual(args[0], v)) return numVal(@floatFromInt(i + 1));
        return numVal(0);
    }
    if (eqi(name, "ifn") or eqi(name, "ifc")) {
        // IFN(cond, whenTrue, whenFalse [, whenMissing])
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const cond = toNum(args[0]);
        if (isMiss(cond)) return if (args.len == 4) args[3] else args[2];
        return if (cond != 0) args[1] else args[2];
    }
    if (eqi(name, "soundex")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = try toStr(ev, args[0]);
        var i: usize = 0;
        while (i < s.len and !std.ascii.isAlphabetic(s[i])) i += 1;
        if (i >= s.len) return .{ .str = "" };
        var out: std.ArrayList(u8) = .empty;
        try out.append(ev.arena, std.ascii.toUpper(s[i]));
        var prev = soundexCode(s[i]);
        i += 1;
        while (i < s.len) : (i += 1) {
            if (!std.ascii.isAlphabetic(s[i])) continue;
            const code = soundexCode(s[i]);
            if (code != 0 and code != prev) try out.append(ev.arena, '0' + code);
            prev = code; // a 0-code (vowel) breaks a run of equal codes
        }
        return .{ .str = out.items };
    }
    if (eqi(name, "nvalid")) {
        // BUG-nvalidmod (tick243 F1): shadows statfns' nvalid (charfns
        // dispatches first) — the old one ignored args[1] and trimmed BOTH
        // sides. Doc p.1267: trailing blanks ignored; a LEADING blank is data.
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const s = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ");
        if (args.len == 1) return numVal(if (isValidName(s)) 1 else 0); // default = V7
        const kind = std.mem.trim(u8, try toStr(ev, args[1]), " ");
        // V7: 1-32 chars, letter/_ start, alnum/_. UPCASE/NAME: same charset rules.
        if (eqi(kind, "v7") or eqi(kind, "upcase") or eqi(kind, "name"))
            return numVal(if (isValidName(s)) 1 else 0);
        // ANY: 1-32 bytes of anything, blanks included.
        if (eqi(kind, "any"))
            return numVal(if (s.len >= 1 and s.len <= 32) 1 else 0);
        // NLITERAL: the string must BE a name literal ('name'n / "name"n).
        if (eqi(kind, "nliteral"))
            return numVal(if (isNameLiteral(s)) 1 else 0);
        note(ev, "Invalid NVALID type '{s}' (expected V7, ANY, NLITERAL, or UPCASE).", .{kind});
        ev.setError() catch {};
        return Value.missing;
    }
    if (eqi(name, "nliteral")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const s = std.mem.trimEnd(u8, try toStr(ev, args[0]), " ");
        // BUG-nliteralquotes (tick243 F2): a valid V7 name is returned UNCHANGED
        // (isValidName adds the 32-byte cap the old inline check lacked).
        if (isValidName(s)) return .{ .str = s };
        // >32 bytes: neither a V7 name nor expressible as an n-literal — SAS
        // writes an ERROR, sets _ERROR_=1, returns a blank (doc p.1225-1226).
        // ponytail: the declared-length insufficient-space sub-case (c) stays
        // the generic PDV clamp — a fn can't see its target width.
        if (s.len > 32) {
            note(ev, "Invalid argument to function NLITERAL (name exceeds 32 bytes).", .{});
            ev.setError() catch {};
            return .{ .str = "" };
        }
        // Quote choice (doc p.1225-1226): SINGLE quotes when the string
        // contains '&', '%', or more '"' than '\'' (macro-safe); else double.
        var nd: usize = 0;
        var ns: usize = 0;
        var single = false;
        for (s) |c| switch (c) {
            '"' => nd += 1,
            '\'' => ns += 1,
            '&', '%' => single = true,
            else => {},
        };
        if (nd > ns) single = true;
        const q: u8 = if (single) '\'' else '"';
        var out: std.ArrayList(u8) = .empty;
        try out.append(ev.arena, q);
        for (s) |c| {
            if (c == q) try out.append(ev.arena, q); // embedded quotes doubled
            try out.append(ev.arena, c);
        }
        try out.append(ev.arena, q);
        try out.append(ev.arena, 'n');
        return .{ .str = out.items };
    }
    if (eqi(name, "compress")) return try compress(ev, name, args);
    // array bounds: the parser replaced the array name with its element count, so
    // arg[0] IS the count. 1-based arrays → dim = hbound = count, lbound = 1.
    if (eqi(name, "dim") or eqi(name, "hbound")) {
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        return numVal(@round(toNum(args[0])));
    }
    if (eqi(name, "lbound")) {
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        return numVal(1);
    }
    if (eqi(name, "scan")) return try scan(ev, name, args);
    if (eqi(name, "find")) return try find(ev, name, args);
    if (eqi(name, "tranwrd")) return try tranwrd(ev, name, args);

    return null;
}

/// HTMLENCODE with an explicit options list (space/comma separated): encode ONLY
/// the named entities (lt gt amp quot apos). Unknown option → fail loud (ERROR),
/// and the result is a BLANK CHARACTER: HTMLENCODE is `Categories: Character`
/// (doc p.1019), so even the error arm must not flip the LHS's type
/// (BUG-charfnsmissingtype).
fn htmlEncodeOpts(ev: *eval.Evaluator, s: []const u8, opts: []const u8) eval.Error!?Value {
    var lt = false;
    var gt = false;
    var amp = false;
    var quot = false;
    var apos = false;
    var it = std.mem.tokenizeAny(u8, opts, " ,\t");
    while (it.next()) |w| {
        if (eqi(w, "lt")) lt = true else if (eqi(w, "gt")) gt = true else if (eqi(w, "amp")) amp = true else if (eqi(w, "quot")) quot = true else if (eqi(w, "apos")) apos = true else {
            ev.diags.report(.err, 0, "HTMLENCODE option '{s}' is not supported yet", .{w}) catch {};
            return .{ .str = "" };
        }
    }
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| switch (c) {
        '<' => try out.appendSlice(ev.arena, if (lt) "&lt;" else "<"),
        '>' => try out.appendSlice(ev.arena, if (gt) "&gt;" else ">"),
        '&' => try out.appendSlice(ev.arena, if (amp) "&amp;" else "&"),
        '"' => try out.appendSlice(ev.arena, if (quot) "&quot;" else "\""),
        '\'' => try out.appendSlice(ev.arena, if (apos) "&apos;" else "'"),
        else => try out.append(ev.arena, c),
    };
    return .{ .str = out.items };
}

// ── tests ────────────────────────────────────────────────────────────────

const t = std.testing;
const diag = @import("diag.zig");
const pdv_mod = @import("pdv.zig");

const Harness = struct {
    arena: std.heap.ArenaAllocator,
    pdv: pdv_mod.Pdv = undefined,
    diags: diag.Diagnostics = undefined,
    fn deinit(self: *Harness) void {
        self.arena.deinit();
    }
    fn prime(self: *Harness) void {
        const a = self.arena.allocator();
        self.pdv = pdv_mod.Pdv.init(a);
        self.diags = diag.Diagnostics.init(a);
    }
    fn ev(self: *Harness) eval.Evaluator {
        return .{ .arena = self.arena.allocator(), .pdv = &self.pdv, .diags = &self.diags };
    }
};

fn near(actual: f64, expected: f64) !void {
    try t.expect(@abs(actual - expected) <= 1e-9 * @max(1, @abs(expected)));
}

fn constant1(e: *eval.Evaluator, cn: []const u8) !Value {
    return (try dispatch(e, "constant", &.{.{ .str = cn }})) orelse error.NotMine;
}

test "GAP-constmissing: CONSTANT's documented names + EXACTINT nbytes (doc p.555-559)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // the filled gaps — values are the doc definitions evaluated in f64
    try near((try constant1(&e, "logbig")).num, 709.782712893384);
    try near((try constant1(&e, "logsmall")).num, -708.3964185322641);
    try near((try constant1(&e, "logmaceps")).num, -36.043653389117154);
    try near((try constant1(&e, "sqrtmaceps")).num, 1.4901161193847656e-8);
    try near((try constant1(&e, "bigrecip")).num, std.math.floatMax(f64));
    try near((try constant1(&e, "smallrecip")).num, std.math.floatMin(f64));
    try near((try constant1(&e, "logbigrecip")).num, 709.782712893384);
    // with an explicit base: LOGBIG base 10 = 308.2547…
    try near(((try dispatch(&e, "constant", &.{ .{ .str = "logbig" }, .{ .num = 10 } })).?).num, 308.25471555991675);

    // EXACTINT honors nbytes (2..8, default 8): 2^(8·nbytes−11)
    try t.expectEqual(@as(f64, 9007199254740992), (try constant1(&e, "exactint")).num); // 2^53
    try t.expectEqual(@as(f64, 137438953472), ((try dispatch(&e, "constant", &.{ .{ .str = "exactint" }, .{ .num = 6 } })).?).num); // 2^37
    try t.expectEqual(@as(f64, 8192), ((try dispatch(&e, "constant", &.{ .{ .str = "exactint" }, .{ .num = 3 } })).?).num); // 2^13
    try t.expectEqual(@as(f64, 32), ((try dispatch(&e, "constant", &.{ .{ .str = "exactint" }, .{ .num = 2 } })).?).num); // 2^5

    // fail-loud: nbytes out of range, base ≤ 1+SQRTMACEPS, unknown name → missing + NOTE
    try t.expect(((try dispatch(&e, "constant", &.{ .{ .str = "exactint" }, .{ .num = 9 } })).?).isMissing());
    try t.expect(((try dispatch(&e, "constant", &.{ .{ .str = "logbig" }, .{ .num = 1 } })).?).isMissing());
    try t.expect((try constant1(&e, "nosuchconst")).isMissing());
    try t.expectEqual(@as(usize, 3), h.diags.count());
}

test "NOTE-htmlencodeopts: options subset honored, unknown option fails loud" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // default path unchanged
    try t.expectEqualStrings("a&lt;b&gt;&amp;c\"d'", (try dispatch(&e, "htmlencode", &.{.{ .str = "a<b>&c\"d'" }})).?.str);
    // options select ONLY the named entities (space or comma separated)
    try t.expectEqualStrings("a&lt;b>&c\"d", (try dispatch(&e, "htmlencode", &.{ .{ .str = "a<b>&c\"d" }, .{ .str = "lt" } })).?.str);
    try t.expectEqualStrings("a&lt;b&gt;&amp;c&quot;d&apos;", (try dispatch(&e, "htmlencode", &.{ .{ .str = "a<b>&c\"d'" }, .{ .str = "lt gt, amp quot apos" } })).?.str);
    try t.expectEqual(@as(usize, 0), h.diags.count());
    // unknown option → BLANK CHARACTER + loud diag naming it. The ERROR is still
    // the point (D-002); what changed is the TYPE (BUG-charfnsmissingtype): the
    // old premise here asserted `isMissing()`, i.e. a numeric `.` out of a
    // character function, which flipped the receiving variable's type.
    const bad_opt = (try dispatch(&e, "htmlencode", &.{ .{ .str = "x" }, .{ .str = "7bit" } })).?;
    try t.expect(bad_opt == .str);
    try t.expectEqualStrings("", bad_opt.str);
    try t.expectEqual(@as(usize, 1), h.diags.count());
}

fn nv(e: *eval.Evaluator, s: []const u8, kind: ?[]const u8) !Value {
    return (try dispatch(e, "nvalid", if (kind) |k| &.{ .{ .str = s }, .{ .str = k } } else &.{.{ .str = s }})) orelse error.NotMine;
}

test "BUG-nvalidnliteral: NVALID honors the type arg + no left-trim; NLITERAL quotes per doc" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // F1: default = V7; trailing blanks ignored, a LEADING blank is data
    try t.expectEqual(@as(f64, 1), (try nv(&e, "abc", null)).num);
    try t.expectEqual(@as(f64, 1), (try nv(&e, "_x9", null)).num);
    try t.expectEqual(@as(f64, 0), (try nv(&e, "2bc", null)).num);
    try t.expectEqual(@as(f64, 0), (try nv(&e, " abc", null)).num); // leading blank
    try t.expectEqual(@as(f64, 1), (try nv(&e, "abc ", null)).num); // trailing ok
    try t.expectEqual(@as(f64, 0), (try nv(&e, "a b", null)).num);
    // explicit V7 behaves like the default
    try t.expectEqual(@as(f64, 1), (try nv(&e, "abc", "V7")).num);
    try t.expectEqual(@as(f64, 0), (try nv(&e, "2bc", "v7")).num);
    // ANY: 1-32 bytes of anything, blanks included (case-insensitive keyword)
    try t.expectEqual(@as(f64, 1), (try nv(&e, "a b", "ANY")).num);
    try t.expectEqual(@as(f64, 1), (try nv(&e, "foo-bar", "any")).num);
    try t.expectEqual(@as(f64, 0), (try nv(&e, "   ", "ANY")).num); // all-blank
    try t.expectEqual(@as(f64, 0), (try nv(&e, "a" ** 33, "ANY")).num); // >32
    // NLITERAL: the string must BE a name literal ('name'n / "name"n)
    try t.expectEqual(@as(f64, 1), (try nv(&e, "'a b'n", "NLITERAL")).num);
    try t.expectEqual(@as(f64, 1), (try nv(&e, "\"x\"N", "nliteral")).num);
    try t.expectEqual(@as(f64, 1), (try nv(&e, "'it''s'n", "NLITERAL")).num); // doubled quote
    try t.expectEqual(@as(f64, 0), (try nv(&e, "abc", "NLITERAL")).num); // not literal form
    try t.expectEqual(@as(f64, 0), (try nv(&e, "'a b'", "NLITERAL")).num); // missing n
    try t.expectEqual(@as(f64, 0), (try nv(&e, "'a b\"n", "NLITERAL")).num); // mixed quotes
    // unknown type → missing + loud diag (+_ERROR_), never a silent 0
    try t.expect((try nv(&e, "abc", "bogus")).isMissing());
    try t.expectEqual(@as(usize, 1), h.diags.count());

    // F2: valid V7 names come back unchanged
    try t.expectEqualStrings("abc", (try dispatch(&e, "nliteral", &.{.{ .str = "abc" }})).?.str);
    try t.expectEqualStrings("_x9", (try dispatch(&e, "nliteral", &.{.{ .str = "_x9" }})).?.str);
    // double quotes by default; embedded doubles doubled
    try t.expectEqualStrings("\"a b\"n", (try dispatch(&e, "nliteral", &.{.{ .str = "a b" }})).?.str);
    try t.expectEqualStrings("\"2x\"n", (try dispatch(&e, "nliteral", &.{.{ .str = "2x" }})).?.str);
    try t.expectEqualStrings("'a\"b'n", (try dispatch(&e, "nliteral", &.{.{ .str = "a\"b" }})).?.str); // more '"' than '\'' → single
    // &, % force SINGLE quotes (macro-safe)
    try t.expectEqualStrings("'cats & dogs'n", (try dispatch(&e, "nliteral", &.{.{ .str = "cats & dogs" }})).?.str);
    try t.expectEqualStrings("'100%'n", (try dispatch(&e, "nliteral", &.{.{ .str = "100%" }})).?.str);
    try t.expectEqualStrings("\"a\"\"b'c\"n", (try dispatch(&e, "nliteral", &.{.{ .str = "a\"b'c" }})).?.str); // tie → double, doubled
    // a lone '\'' does not force single quotes (double quotes hold it fine)
    try t.expectEqualStrings("\"it's\"n", (try dispatch(&e, "nliteral", &.{.{ .str = "it's" }})).?.str);
    // >32 bytes: blank + loud diag
    try t.expectEqualStrings("", (try dispatch(&e, "nliteral", &.{.{ .str = "a" ** 40 }})).?.str);
    try t.expectEqual(@as(usize, 2), h.diags.count());
}

test "NOTE-findcunknownmod: COUNT/COUNTC/FINDC fail loud on an unknown modifier letter, like SCAN/COUNTW/FINDW" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const sv = struct {
        fn f(s: []const u8) Value {
            return .{ .str = s };
        }
    }.f;

    // unknown letters were silently ignored (else => {}) — the requested
    // character class never applied. Now: .err naming the letter + missing,
    // the wordSpec policy (D-002).
    try t.expect((try dispatch(&e, "count", &.{ sv("aAaA"), sv("a"), sv("q") })).?.isMissing());
    try t.expect((try dispatch(&e, "countc", &.{ sv("abc123"), sv(""), sv("z") })).?.isMissing());
    try t.expect((try dispatch(&e, "findc", &.{ sv("abc"), sv("b"), sv("q") })).?.isMissing());
    try t.expectEqual(@as(usize, 3), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "count() modifier 'q' is not supported yet") != null);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[1].message, "countc() modifier 'z' is not supported yet") != null);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[2].message, "findc() modifier 'q' is not supported yet") != null);

    // the honored letters (+ 'o' no-op) keep working, no new diags.
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "count", &.{ sv("aAaA"), sv("a"), sv("io") })).?.num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "countc", &.{ sv("a1b2"), sv(""), sv("d") })).?.num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "countc", &.{ sv("a1b2"), sv(""), sv("dv") })).?.num); // v inverts
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "findc", &.{ sv("abcdef"), sv("bd"), sv("b") })).?.num); // backward
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "findc", &.{ sv("aaa"), sv("abc"), sv("k") })).?.num); // complement: none outside the set
    try t.expectEqual(@as(usize, 3), h.diags.count());
}

test "BUG-charfnsmissingtype: BYTE/COLLATE/HASHING/HASHING_HMAC/HTMLENCODE give up as CHARACTER, never numeric" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const sv = struct {
        fn f(s: []const u8) Value {
            return .{ .str = s };
        }
    }.f;
    const nvv = struct {
        fn f(x: f64) Value {
            return .{ .num = x };
        }
    }.f;

    // Every one of these is `Categories: Character` in the SAS 9.4 Functions and
    // CALL Routines: Reference (BYTE p.282, COLLATE p.521, HASHING p.975,
    // HASHING_HMAC p.978, HTMLENCODE p.1019), so p.5's "sets the result to a
    // missing value" means the CHARACTER missing — a blank. A numeric `.` here
    // flips the receiving variable's TYPE, and then `put (x) ($char10.);` is a
    // hard ERROR at rc 1 where SAS prints blanks at rc 0. The union TAG is the
    // assertion; the rendered text is not the regression surface.
    const blanks = [_]Value{
        (try dispatch(&e, "byte", &.{nvv(-1)})).?, // below the 0–255 range
        (try dispatch(&e, "byte", &.{nvv(999)})).?, // above it
        (try dispatch(&e, "byte", &.{Value.missing})).?, // missing n
        (try dispatch(&e, "collate", &.{nvv(-1)})).?, // start below range
        (try dispatch(&e, "collate", &.{nvv(300)})).?, // start above range
        (try dispatch(&e, "collate", &.{Value.missing})).?, // missing start
        (try dispatch(&e, "collate", &.{ nvv(65), nvv(60) })).?, // p.521: end must exceed start
        (try dispatch(&e, "collate", &.{ nvv(65), nvv(999) })).?, // end above range
        (try dispatch(&e, "collate", &.{ nvv(65), Value.missing, nvv(0) })).?, // zero-length run
        (try dispatch(&e, "hashing", &.{ sv("nosuchmethod"), sv("x") })).?,
        (try dispatch(&e, "hashing_hmac", &.{ sv("nosuchmethod"), sv("k"), sv("m") })).?,
    };
    for (blanks) |v| {
        try t.expect(v == .str); // the TAG is the whole ticket
        try t.expectEqualStrings("", std.mem.trim(u8, v.str, " "));
    }

    // HTMLENCODE's bad-option arm still ERRORs loudly — and still hands back a
    // character (pinned in NOTE-htmlencodeopts above as well; kept here so the
    // whole class reads in one place).
    const before = h.diags.count();
    const bad_opt = (try dispatch(&e, "htmlencode", &.{ sv("a<b"), sv("zz") })).?;
    try t.expect(bad_opt == .str);
    try t.expect(h.diags.count() > before);

    // The good paths are untouched — value AND type.
    try t.expectEqualStrings("P", (try dispatch(&e, "byte", &.{nvv(80)})).?.str); // p.282's own example
    try t.expectEqualStrings("ABC", (try dispatch(&e, "collate", &.{ nvv(65), nvv(67) })).?.str);
    try t.expectEqualStrings("ABC", (try dispatch(&e, "collate", &.{ nvv(65), Value.missing, nvv(3) })).?.str);
    try t.expectEqual(@as(usize, 32 * 2), (try dispatch(&e, "hashing", &.{ sv("sha256"), sv("abc") })).?.str.len);
    try t.expectEqual(@as(usize, 32 * 2), (try dispatch(&e, "hashing_hmac", &.{ sv("sha256"), sv("k"), sv("abc") })).?.str.len);
}

test "BUG-charfnsnodomerr: the char give-up arms the DOC diagnoses are loud; the two it does not are quiet" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const sv = struct {
        fn f(s: []const u8) Value {
            return .{ .str = s };
        }
    }.f;
    const nvv = struct {
        fn f(x: f64) Value {
            return .{ .num = x };
        }
    }.f;
    // _ERROR_ read back out of the PDV: domErrChar routes through ev.setError(),
    // so the NOTE and the flag are one event and both belong in the assertion.
    const errFlag = struct {
        fn f(hh: *Harness) f64 {
            const v = hh.pdv.get("_error_") orelse return 0;
            return switch (v) {
                .num => |x| x,
                .str => 0,
            };
        }
    }.f;

    // ── LOUD, each on its own doc sentence ────────────────────────────────
    // BYTE p.282 `Range 0–255` + p.5's general invalid-argument rule;
    // COLLATE p.522 "0 through 255" and "end-position must be larger than
    // start-position" + p.5; HASHING p.976 / HASHING_HMAC p.979 verbatim
    // ("the returned digest is blank, and a note, warning, or error message is
    // issued stating that the argument is invalid").
    const loud = [_][]const Value{
        &.{nvv(-1)}, // byte, below range
        &.{nvv(999)}, // byte, above range
        &.{Value.missing}, // byte, missing n (p.5 names "missing" explicitly)
    };
    for (loud) |args| {
        h.diags.list.clearRetainingCapacity();
        try h.pdv.set("_error_", .{ .num = 0 });
        const v = (try dispatch(&e, "byte", args)).?;
        try t.expect(v == .str); // the type fix from f6a80889 is NOT revisited
        try t.expectEqualStrings("", v.str);
        try t.expectEqual(@as(usize, 1), h.diags.count());
        try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "byte") != null);
        try t.expectEqual(@as(f64, 1), errFlag(&h));
    }

    const LoudCall = struct { fn_name: []const u8, args: []const Value };
    const loud_calls = [_]LoudCall{
        .{ .fn_name = "collate", .args = &.{nvv(-1)} }, // start below the sequence
        .{ .fn_name = "collate", .args = &.{nvv(300)} }, // start above it
        .{ .fn_name = "collate", .args = &.{ nvv(65), nvv(60) } }, // end below start
        .{ .fn_name = "collate", .args = &.{ nvv(65), nvv(999) } }, // end above 255
        .{ .fn_name = "hashing", .args = &.{ sv("nosuchmethod"), sv("x") } },
        .{ .fn_name = "hashing_hmac", .args = &.{ sv("nosuchmethod"), sv("k"), sv("m") } },
    };
    for (loud_calls) |c| {
        h.diags.list.clearRetainingCapacity();
        try h.pdv.set("_error_", .{ .num = 0 });
        const v = (try dispatch(&e, c.fn_name, c.args)).?;
        try t.expect(v == .str);
        try t.expectEqualStrings("", v.str);
        try t.expectEqual(@as(usize, 1), h.diags.count());
        try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, c.fn_name) != null);
        try t.expectEqual(@as(f64, 1), errFlag(&h));
    }

    // ── DOC-SILENT, declined on purpose ───────────────────────────────────
    // (a) COLLATE with an omitted/missing start-position. p.524 Example 3 is
    //     `y = collate(,,56);` — a WORKING call in the Functions Reference — and
    //     an omitted arg is indistinguishable from `.` by the time it reaches
    //     here, so warning would fire on documented-correct usage.
    // (b) COLLATE's `length`. p.522 gives it no range at all ("Default 200"),
    //     so there is no prescribed range for p.5 to be outside of.
    const quiet = [_][]const Value{
        &.{Value.missing}, // (a) missing start
        &.{ Value.missing, Value.missing, nvv(56) }, // (a) p.524's own collate(,,56) shape
        &.{ nvv(65), Value.missing, nvv(0) }, // (b) zero-length run
        &.{ nvv(65), Value.missing, nvv(-3) }, // (b) negative length, clamped to 0
    };
    for (quiet) |args| {
        h.diags.list.clearRetainingCapacity();
        try h.pdv.set("_error_", .{ .num = 0 });
        const v = (try dispatch(&e, "collate", args)).?;
        try t.expect(v == .str);
        try t.expectEqualStrings("", v.str);
        try t.expectEqual(@as(usize, 0), h.diags.count()); // no NOTE …
        try t.expectEqual(@as(f64, 0), errFlag(&h)); // … and no _ERROR_
    }

    // Good paths gained nothing: still silent, still correct.
    h.diags.list.clearRetainingCapacity();
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expectEqualStrings("P", (try dispatch(&e, "byte", &.{nvv(80)})).?.str);
    try t.expectEqualStrings("ABC", (try dispatch(&e, "collate", &.{ nvv(65), nvv(67) })).?.str);
    try t.expectEqualStrings("A", (try dispatch(&e, "collate", &.{ nvv(65), nvv(65) })).?.str); // end == start, unchanged
    try t.expectEqual(@as(usize, 32 * 2), (try dispatch(&e, "hashing", &.{ sv("sha256"), sv("abc") })).?.str.len);
    try t.expectEqual(@as(usize, 0), h.diags.count());
    try t.expectEqual(@as(f64, 0), errFlag(&h));
}

test "BUG-collateomittedstart: an omitted start-position is position 0 (p.524 Example 3), and stays SILENT" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    try h.pdv.set("_error_", .{ .num = 0 });
    var e = h.ev();
    // The parser hands an omitted positional slot to us as an empty-STRING literal
    // (parser_expr.zig parseCall), so this is exactly what `collate(,,56)` evaluates to.
    const omit: Value = .{ .str = "" };
    const nvv = struct {
        fn f(x: f64) Value {
            return .{ .num = x };
        }
    }.f;

    // p.524 Example 3, `y = collate(,,56);` → "the first 56 characters of the ASCII
    // collating sequence": LENGTH 56, CONTENT positions 0..55.
    const y = (try dispatch(&e, "collate", &.{ omit, omit, nvv(56) })).?;
    try t.expect(y == .str);
    try t.expectEqual(@as(usize, 56), y.str.len);
    for (y.str, 0..) |c, i| try t.expectEqual(@as(u8, @intCast(i)), c);
    // …identical to spelling the 0 out, which already worked.
    try t.expectEqualStrings(y.str, (try dispatch(&e, "collate", &.{ nvv(0), omit, nvv(56) })).?.str);

    // Sibling defaults, same default-to-0 start:
    // omitted start + explicit end → 0..65 inclusive = 66 characters.
    const a = (try dispatch(&e, "collate", &.{ omit, nvv(65) })).?;
    try t.expectEqual(@as(usize, 66), a.str.len);
    try t.expectEqual(@as(u8, 65), a.str[65]);
    // everything but start omitted → p.522's `length` Default 200, from position 0.
    try t.expectEqual(@as(usize, 200), (try dispatch(&e, "collate", &.{omit})).?.str.len);
    try t.expectEqual(@as(usize, 200), (try dispatch(&e, "collate", &.{ omit, omit })).?.str.len);
    try t.expectEqual(@as(usize, 200), (try dispatch(&e, "collate", &.{ omit, omit, omit })).?.str.len);

    // The DECLINE stays pinned: an EXPLICIT missing start is still a blank
    // CHARACTER give-up (BUG-charfnsmissingtype), NOT position 0.
    const dot = (try dispatch(&e, "collate", &.{ Value.missing, omit, nvv(56) })).?;
    try t.expect(dot == .str);
    try t.expectEqualStrings("", dot.str);
    try t.expect((try dispatch(&e, "collate", &.{Value.missing})).?.str.len == 0);

    // …and every arm above is DOC-SILENT: p.524 demonstrates the omitted form as
    // correct usage, so not one diagnostic and _ERROR_ untouched.
    try t.expectEqual(@as(usize, 0), h.diags.count());
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}
