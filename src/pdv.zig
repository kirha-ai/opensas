//! The PDV (Program Data Vector) — the DATA step's working row.
//!
//! One `Pdv` is the single buffer the executor (C1) reads and writes as it
//! runs statements over an observation: `x = a + 1;` reads `a`'s cell and
//! writes `x`'s. Variables are an *ordered* set of named cells — order is the
//! order SAS first saw each name, and it is the order `output` snapshots into
//! a `Dataset` (see dataset.zig) and PROC PRINT shows columns.
//!
//! A variable has a fixed type (`num`/`char`), set when it is first mentioned;
//! its cell holds the current `Value`, which is *missing-of-type* until set —
//! numeric `.` or a blank char string. SAS names are case-insensitive, and
//! per the house rule that comparison is the consumer's job, the lookup here
//! (`indexOf`) is where that case-folding actually happens.
//!
//! Arena-backed: the arena owns variable names (and any char bytes a caller
//! chooses to route through it). Retain/reset *policy* — which cells survive
//! into the next iteration — is the executor's overlay; the PDV only offers
//! the mechanism (`reset`).

const std = @import("std");
const Value = @import("value.zig").Value;
const diag = @import("diag.zig");
const format = @import("format.zig");

pub const VarType = enum { num, char };

/// SAS caps a character variable's length at 32767 bytes: LENGTH Statement,
/// SAS 9.4 DATA Step Statements: Reference, printed p.217 (pdf 228 at the
/// volume's +11 offset) — "For character variables, 1 to 32767 bytes under
/// all operating environments"; ATTRIB's LENGTH= repeats it, printed p.34
/// (pdf 45). Enforced LOUD at the store (setAt) — see the comment there.
pub const max_char_len: usize = 32767;

/// The default cell for a freshly-declared variable of this type: numeric
/// missing (`.`) or the blank/empty char string.
pub fn missingOf(t: VarType) Value {
    return switch (t) {
        .num => Value.missing,
        .char => .{ .str = "" },
    };
}

fn typeOf(v: Value) VarType {
    return switch (v) {
        .num => .num, // a missing numeric is still numeric
        .str => .char,
    };
}

/// SAS AUTOMATIC num→char conversion (Language Reference: Concepts p.124, BUG-numcharwidth): BESTw.
/// RIGHT-JUSTIFIED in a w-wide field — `n||"x"` converts n with w=12
/// (`"           5x"`); assignment `c = n` into a length-n char var uses BESTn.
/// Explicit conversions (PUT with a format, the CAT family) never come here.
/// The single home for the pad, D-001 spirit (sasParseFloat is the char→num
/// twin). The conversion NOTE stays with each caller (it has the diags handle).
pub fn numToChar(arena: std.mem.Allocator, x: f64, w: usize) std.mem.Allocator.Error![]const u8 {
    const s = try format.bestNumW(arena, x, w); // missings → `.`/`.A`-`.Z`/`._`
    if (s.len >= w) return s; // bestNumW is sized to w; >= is belt-and-braces
    const out = try arena.alloc(u8, w);
    @memset(out, ' ');
    @memcpy(out[w - s.len ..], s);
    return out;
}

/// Parse a string as SAS's plain `w.` numeric informat does: optional surrounding
/// blanks, optional sign, decimal digits with at most one point, an optional E
/// exponent — and NOTHING else. Zig's `std.fmt.parseFloat` additionally accepts hex
/// floats (`0x1F`), digit underscores (`1_000`), binary (`0b101`) and `inf`/`nan`,
/// none of which the `w.` informat allows — SAS yields MISSING for those, so bare
/// parseFloat read them as real numbers (BUG-charnum-parsefloat). We validate the
/// strict grammar first, then delegate to parseFloat for the value (the validated
/// string is plain decimal, so no extended syntax can slip through). null → missing.
/// The single home for all 4 char→num sinks (eval/pdv/functions), D-001 spirit.
pub fn sasParseFloat(raw: []const u8) ?f64 {
    const s = std.mem.trim(u8, raw, " ");
    if (s.len == 0) return null;
    var i: usize = 0;
    if (s[i] == '+' or s[i] == '-') i += 1;
    var mant: usize = 0; // mantissa digits (before + after the point)
    while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) mant += 1;
    if (i < s.len and s[i] == '.') {
        i += 1;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) mant += 1;
    }
    if (mant == 0) return null; // "", "+", ".", "e5" — no digit in the mantissa
    if (i < s.len and (s[i] == 'e' or s[i] == 'E')) {
        i += 1;
        if (i < s.len and (s[i] == '+' or s[i] == '-')) i += 1;
        var edig: usize = 0;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) edig += 1;
        if (edig == 0) return null; // exponent marker with no digits
    }
    if (i != s.len) return null; // trailing garbage: 0x1F, 1_000, 1,234, 0b101, 1.2.3
    return std.fmt.parseFloat(f64, s) catch null;
}

/// SAS implicit char→numeric conversion (BEST input): trimmed digits parse,
/// blank or unparsable text is the numeric missing (real SAS notes and moves on).
fn parseNum(s: []const u8) Value {
    const tr = std.mem.trim(u8, s, " ");
    if (tr.len == 0) return Value.missing;
    if (Value.parseSpecialMissing(tr)) |sm| return sm; // .A–.Z, ._ (ISS-specialmissing)
    return if (sasParseFloat(tr)) |x| .{ .num = x } else Value.missing;
}

pub const Var = struct {
    name: []const u8, // arena-owned, original case preserved
    type: VarType,
    value: Value,
    format: ?[]const u8 = null, // associated display format (FORMAT / ATTRIB statement)
    informat: ?[]const u8 = null, // associated read informat (INFORMAT / ATTRIB statement)
    label: ?[]const u8 = null, // variable label (LABEL / ATTRIB statement)
    len: usize = 0, // declared (allocated) char length; 0 = none (VLENGTH — BUG-vlength)
    numlen: usize = 0, // declared numeric byte-length 3..7 (LENGTH/ATTRIB); 0/8 = full f64 (GH#46)
    // Declared by the compile-time pass with a STATICALLY-GUESSED type
    // (BUG-pdvcompilevars); the first runtime write corrects the type and
    // clears this, so executed paths keep exact runtime typing.
    guessed: bool = false,
    // The over-cap char-length ERROR (max_char_len) fires ONCE per var, not
    // per row — loadRow writes by slot on every row of every source.
    len_err_reported: bool = false,
};

pub const Pdv = struct {
    arena: std.mem.Allocator,
    vars: std.ArrayList(Var),
    /// Lowercased name → slot in `vars` (PERF-lbtimeout). `vars` is append-only,
    /// so slots never move and the map never goes stale. The linear scan this
    /// replaced was ~98% of a 12k-row study program's runtime: loadRow does one
    /// lookup per column per row, and wide steps (an EPOCH macro's dt_1..dt_N
    /// transpose merges) push the PDV to hundreds of vars.
    index: std.StringHashMapUnmanaged(usize),
    /// Shared reporter for the SAS char→numeric conversion NOTEs (ISS-charnumassign).
    /// Null in standalone/unit uses; the executor wires the run's `diags` in via
    /// `Executor.init` so `set` can fail LOUD instead of silently dropping a
    /// mistyped char assignment to missing.
    diags: ?*diag.Diagnostics = null,

    pub fn init(arena: std.mem.Allocator) Pdv {
        return .{ .arena = arena, .vars = .empty, .index = .empty };
    }

    /// Index of `name`, case-insensitively, or null if unknown.
    pub fn indexOf(self: *const Pdv, name: []const u8) ?usize {
        // SAS names are ≤32 chars; "first."/"last." PDV flags stay well under 64.
        var buf: [64]u8 = undefined;
        if (name.len <= buf.len) return self.index.get(std.ascii.lowerString(&buf, name));
        // oversized name: fall back to the scan (correct on any input)
        for (self.vars.items, 0..) |v, i| {
            if (std.ascii.eqlIgnoreCase(v.name, name)) return i;
        }
        return null;
    }

    /// Declare a variable, returning its slot index. Idempotent: a name already
    /// present keeps its slot and its type — a variable's type is fixed at its
    /// first mention (`input x $;`, `length`, or first assignment), so a later
    /// `define` with a different type is ignored here (that mismatch is the
    /// executor's diagnostic to raise, not the PDV's). One exception: a var
    /// whose type was only a compile-time GUESS (`declare`) adopts the first
    /// CERTAIN type — a zero-row SET source's schema must beat the `v="99"`
    /// guess, else the var lands char and every golden numeric goes missing
    /// (TRIAGE-gen2values: EG VISITNUM).
    pub fn define(self: *Pdv, name: []const u8, t: VarType) !usize {
        if (self.indexOf(name)) |i| {
            const vr = &self.vars.items[i];
            if (vr.guessed) {
                vr.type = t;
                vr.value = missingOf(t);
                vr.guessed = false;
            }
            return i;
        }
        const owned = try self.arena.dupe(u8, name);
        try self.vars.append(self.arena, .{ .name = owned, .type = t, .value = missingOf(t) });
        const key = try std.ascii.allocLowerString(self.arena, name);
        try self.index.put(self.arena, key, self.vars.items.len - 1);
        return self.vars.items.len - 1;
    }

    /// Current value of `name`, or null if the variable does not exist.
    pub fn get(self: *const Pdv, name: []const u8) ?Value {
        return if (self.indexOf(name)) |i| self.vars.items[i].value else null;
    }

    /// Declare a variable at COMPILE time with a statically-GUESSED type
    /// (BUG-pdvcompilevars). Same idempotence as `define`, but a variable this
    /// creates is marked `guessed` so the first runtime `set` can correct the
    /// type — a certain `define` (input/length/SET schema) is never disturbed.
    pub fn declare(self: *Pdv, name: []const u8, t: VarType) !usize {
        if (self.indexOf(name)) |i| return i;
        const i = try self.define(name, t);
        self.vars.items[i].guessed = true;
        return i;
    }

    /// Write `name`'s cell, auto-declaring it (type inferred from `v`) if new.
    /// An existing variable keeps its declared type — a compile-time guess is
    /// corrected inside `define`. A character value written to a certainly-
    /// NUMERIC variable converts the SAS way (implicit BEST input: blanks or
    /// unparsable → missing), so `VISITNUM = put(v, fmt.)` yields 99, not a
    /// stray char cell in a numeric column (TRIAGE-gen2values). A numeric
    /// stored into a CHAR variable becomes a proper char cell (compact BEST12)
    /// at the num→char branch below.
    pub fn set(self: *Pdv, name: []const u8, v: Value) !void {
        const i = try self.define(name, typeOf(v));
        try self.setAt(i, v);
    }

    /// `set` by slot index — no name lookup (PERF-loadrowdual: io.loadRow's
    /// readback loop resolves column→slot once per source via `define`, then
    /// writes by slot on every row). Identical coercion semantics to `set`;
    /// the var at `i` already exists (slots are stable — `vars` is
    /// append-only), so no auto-declare or guess-correction happens here.
    pub fn setAt(self: *Pdv, i: usize, v: Value) std.mem.Allocator.Error!void {
        const vr = &self.vars.items[i];
        // GAP-xportio-low: a declared char length over max_char_len is a loud
        // ERROR, never a silently over-long cell (the root of the XPORT
        // writer's F5 refusal — such a length must not exist in the PDV at
        // all). The store is the choke point EVERY length entry point
        // converges on: LENGTH/ATTRIB stamps, SET-source carries (GH#72),
        // XPORT/sas7bdat reader lens. The executor's error gate then halts
        // the step, as for the seedDeclVar conflicts. ponytail: rejecting a
        // store-FREE `length x $40000; run;` belongs to parser.zig/exec.zig
        // (outside this ticket's ownership) — every DATA path is covered
        // here, which is where silent corruption would ride.
        if (vr.type == .char and vr.len > max_char_len and !vr.len_err_reported) {
            vr.len_err_reported = true;
            if (self.diags) |d|
                try d.report(.err, 0, "Character variable {s} has length {d}, over the SAS maximum character length 32767.", .{ vr.name, vr.len });
        }
        // A declared char LENGTH truncates every write, as in SAS — parse-time
        // substr-wrapping covers LENGTH/ATTRIB statements, but a width carried
        // in from a SET source's schema (the EMPTY_* metadata idiom) is only
        // known here (GAP-charlength).
        if (vr.type == .char and vr.len > 0 and v == .str and v.str.len > vr.len) {
            vr.value = .{ .str = v.str[0..vr.len] };
            return;
        }
        if (vr.type == .num and v == .str) {
            // SAS implicit char→numeric conversion: it converts and CONTINUES,
            // but it is never silent (Language Reference: Concepts "Automatic Numeric-Character
            // Conversion") — a run that drops a mistyped assignment to missing
            // with exit 0 is the worst failure class for clinical data
            // (ISS-charnumassign). Emit the same NOTEs SAS logs, then store.
            const conv = parseNum(v.str);
            // A blank string is a valid representation of numeric missing — only
            // non-blank text that won't parse is an actual invalid conversion.
            const invalid = std.mem.trim(u8, v.str, " ").len > 0 and conv.isMissing();
            if (self.diags) |d| {
                // ponytail: no source position — the store layer (`set`/`setAt`)
                // is shared by exec/io/sql/functions callers and threading a
                // statement line through it is a cross-file refactor, so SAS's
                // "at line N column M." tail (Language Reference: Concepts Example Code 4.1) is OMITTED,
                // not frozen at 0/0 (GH#78, NOTE-invalidnumdataloc). NOTEs go to
                // stderr (not the corpus diff). SAS aggregates the "converted"
                // note by place; this fires once per conversion — dedupe by
                // location if wide *DTC studies make the stderr log volume a
                // problem.
                try d.note(0, "Character values have been converted to numeric values at the places given by: (Line):(Column).", .{});
                if (invalid)
                    try d.note(0, "Invalid numeric data, '{s}'.", .{v.str});
            }
            vr.value = conv; // write BEFORE the _error_ set below: that set may
            // append/realloc `vars` and invalidate `vr`.
            // SAS sets the DATA-step automatic `_ERROR_=1` the moment an invalid
            // char→num conversion happens (Language Reference: Concepts p.111/124) — live in-step, so a
            // later `put _error_` in the same iteration sees it. `_ERROR_` is a
            // plain PDV var; the executor resets it to 0 at the top of each
            // iteration (CHARNUM-errorvar).
            if (invalid) try self.set("_error_", .{ .num = 1 });
            return;
        }
        // A declared numeric LENGTH < 8 stores only the high N bytes of the
        // 8-byte IEEE double, zeroing the low 8−N — SAS's deliberate precision
        // loss (GH#46). Bit-mask on store; missing (non-finite NaN) is left
        // untouched so it stays missing-of-type.
        if (vr.type == .num and vr.numlen > 0 and vr.numlen < 8 and v == .num and std.math.isFinite(v.num)) {
            vr.value = .{ .num = truncNum(v.num, vr.numlen) };
            return;
        }
        // num→char on STORE: a char var receiving a numeric cell. Two callers,
        // both wanting the COMPACT (left-justified) value:
        // (a) SET/MERGE/UPDATE loads where CSV type inference read a really-char
        //     column as numeric (the GH#69/#70 leniency — real SDTM ID columns):
        //     the SAS-truthful rendering is the value AS IF it had been char all
        //     along, i.e. unpadded — the real-SAS-derived goldens pin it;
        // (b) a true `c = n` assignment to a char var whose length the PARSER
        //     didn't know (ATTRIB/schema-seeded) — same rendering opensas always
        //     gave. A `length`-declared target never reaches here: the parser
        //     desugars it to __assignc, which renders BESTn. right-justified
        //     (Language Reference: Concepts p.124, BUG-numcharwidth).
        // Stored as a real char cell (was: raw .num cell in a char var — a later
        // numeric read then skipped the char→num NOTE pair). The conversion
        // NOTE still fires (GH#74).
        if (vr.type == .char and v == .num) {
            if (self.diags) |d|
                try d.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{});
            vr.value = .{ .str = try format.bestNum(self.arena, v.num) };
            return;
        }
        vr.value = v;
    }

    /// Keep the high `n` bytes (n=3..7) of the 8-byte IEEE double, zeroing the
    /// low 8−n (big-endian view: `bits & (~0 << 8*(8−n))`). len5 of 36.6 →
    /// 40424CCCCC000000 = 36.59999990463257 (validated GH#46). pub so PROC
    /// APPEND's FORCE store reconciliation reuses it (BUG-appendcharwidth) —
    /// this is the source of truth; exec.zig's truncBySet keeps a local copy.
    pub fn truncNum(x: f64, n: usize) f64 {
        const shift: u6 = @intCast(8 * (8 - n));
        const mask: u64 = ~@as(u64, 0) << shift;
        return @bitCast(@as(u64, @bitCast(x)) & mask);
    }

    /// Associate a display format with `name` (FORMAT / ATTRIB); no-op if the
    /// variable is not (yet) defined — the caller re-tries once it exists.
    pub fn setFormat(self: *Pdv, name: []const u8, fmt: []const u8) void {
        if (self.indexOf(name)) |i| self.vars.items[i].format = fmt;
    }

    /// The variable's associated display format, or null.
    pub fn formatOf(self: *const Pdv, name: []const u8) ?[]const u8 {
        return if (self.indexOf(name)) |i| self.vars.items[i].format else null;
    }

    /// Associate a read informat (INFORMAT / ATTRIB); no-op if not yet defined.
    pub fn setInformat(self: *Pdv, name: []const u8, inf: []const u8) void {
        if (self.indexOf(name)) |i| self.vars.items[i].informat = inf;
    }

    /// The variable's associated read informat, or null.
    pub fn informatOf(self: *const Pdv, name: []const u8) ?[]const u8 {
        return if (self.indexOf(name)) |i| self.vars.items[i].informat else null;
    }

    /// Associate a variable label (LABEL / ATTRIB); no-op if not yet defined.
    pub fn setLabel(self: *Pdv, name: []const u8, label: []const u8) void {
        if (self.indexOf(name)) |i| self.vars.items[i].label = label;
    }

    /// The variable's label, or null.
    pub fn labelOf(self: *const Pdv, name: []const u8) ?[]const u8 {
        return if (self.indexOf(name)) |i| self.vars.items[i].label else null;
    }

    /// Reset every cell to its type's missing value — the mechanism the
    /// executor uses at the top of each DATA-step iteration. Retained variables
    /// are the executor's overlay: it re-applies their kept values after.
    pub fn reset(self: *Pdv) void {
        for (self.vars.items) |*v| v.value = missingOf(v.type);
    }
};

test "define/get/set, case-insensitive names" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // an undeclared variable reads as null
    try std.testing.expect(pdv.get("age") == null);

    // define keeps type; freshly-defined cell is missing-of-type
    _ = try pdv.define("Age", .num);
    _ = try pdv.define("Name", .char);
    try std.testing.expect(pdv.get("AGE").?.isMissing()); // case-insensitive lookup
    try std.testing.expectEqualStrings("", pdv.get("name").?.str);

    // set writes through, re-declaring type stays fixed
    try pdv.set("age", .{ .num = 42 });
    _ = try pdv.define("AGE", .char); // ignored — Age is already numeric
    try std.testing.expectEqual(@as(f64, 42), pdv.get("age").?.num);
    try std.testing.expect(pdv.indexOf("age").? == 0); // still the first slot

    // set auto-declares a new variable from the value's type
    try pdv.set("City", .{ .str = "NYC" });
    try std.testing.expectEqualStrings("NYC", pdv.get("city").?.str);
}

test "declare: guessed type yields missing-of-type, first write corrects it (BUG-pdvcompilevars)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // never written → stays the guess, reads missing-of-type
    _ = try pdv.declare("ev2", .num);
    try std.testing.expect(pdv.get("ev2").?.isMissing());
    try std.testing.expect(pdv.vars.items[pdv.indexOf("ev2").?].type == .num);

    // wrong guess (num) corrected by the first char write
    _ = try pdv.declare("s", .num);
    try pdv.set("s", .{ .str = "hi" });
    try std.testing.expect(pdv.vars.items[pdv.indexOf("s").?].type == .char);
    try std.testing.expect(!pdv.vars.items[pdv.indexOf("s").?].guessed);

    // a CERTAIN define is never corrected: char stays char after a num write
    _ = try pdv.define("c", .char);
    try pdv.set("c", .{ .num = 1 });
    try std.testing.expect(pdv.vars.items[pdv.indexOf("c").?].type == .char);

    // declare on an existing var is a no-op (keeps slot, type, certainty)
    _ = try pdv.declare("c", .num);
    try std.testing.expect(pdv.vars.items[pdv.indexOf("c").?].type == .char);
    try std.testing.expect(!pdv.vars.items[pdv.indexOf("c").?].guessed);
}

test "name index stays exact over many defines (PERF-lbtimeout)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // the hashed index must agree with slot order across a wide PDV
    // (the dt_1..dt_N transpose-merge shape that made LB quadratic)
    var buf: [16]u8 = undefined;
    for (0..500) |k| {
        const nm = try std.fmt.bufPrint(&buf, "dt_{d}", .{k});
        try std.testing.expectEqual(k, try pdv.define(nm, .num));
    }
    for (0..500) |k| {
        const nm = try std.fmt.bufPrint(&buf, "DT_{d}", .{k}); // case-insensitive hit
        try std.testing.expectEqual(@as(?usize, k), pdv.indexOf(nm));
        try std.testing.expectEqual(k, try pdv.define(nm, .char)); // idempotent, slot kept
    }
    try std.testing.expect(pdv.indexOf("dt_500") == null);
    // an oversized name (>64) takes the fallback scan and still round-trips
    const long = "x" ** 70;
    const li = try pdv.define(long, .num);
    try std.testing.expectEqual(@as(?usize, li), pdv.indexOf(long));
}

test "setAt writes by slot with set's coercion, no name lookup (PERF-loadrowdual)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    const ni = try pdv.define("n", .num);
    const ci = try pdv.define("c", .char);
    pdv.vars.items[ci].len = 3; // declared char width

    // plain write lands in the right slot
    try pdv.setAt(ni, .{ .num = 42 });
    try std.testing.expectEqual(@as(f64, 42), pdv.get("n").?.num);

    // char→num coercion fires by slot too
    try pdv.setAt(ni, .{ .str = "7" });
    try std.testing.expectEqual(@as(f64, 7), pdv.get("n").?.num);

    // declared char LENGTH truncates, num→char store converts (compact)
    try pdv.setAt(ci, .{ .str = "abcdef" });
    try std.testing.expectEqualStrings("abc", pdv.get("c").?.str);
    try pdv.setAt(ci, .{ .num = 5 });
    try std.testing.expectEqualStrings("5", pdv.get("c").?.str);
}

test "GAP-xportio-low: a char length over the SAS 32767 cap is a LOUD ERROR on store, never a silently over-long cell" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = diag.Diagnostics.init(arena.allocator());
    var pdv = Pdv.init(arena.allocator());
    pdv.diags = &diags; // the executor wires this in Executor.init

    // a `length x $40000;` stamp — LENGTH Statement, Statements Ref printed
    // p.217: "For character variables, 1 to 32767 bytes under all operating
    // environments."
    const i = try pdv.define("x", .char);
    pdv.vars.items[i].len = 40000;

    // any store to the over-long var reports ONE loud error …
    try pdv.set("x", .{ .str = "abc" });
    try std.testing.expect(diags.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), diags.count());
    try std.testing.expect(std.mem.indexOf(u8, diags.list.items[0].message, "over the SAS maximum character length 32767") != null);

    // … once per var, not per row (loadRow writes by slot on every row)
    try pdv.setAt(i, .{ .str = "def" });
    try std.testing.expectEqual(@as(usize, 1), diags.count());

    // exactly at the cap is legal SAS — no diagnostic
    const j = try pdv.define("y", .char);
    pdv.vars.items[j].len = 32767;
    try pdv.set("y", .{ .str = "ok" });
    try std.testing.expectEqual(@as(usize, 1), diags.count());
    try std.testing.expectEqualStrings("ok", pdv.get("y").?.str);
}

test "reset returns cells to missing-of-type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    try pdv.set("x", .{ .num = 1 });
    try pdv.set("s", .{ .str = "hi" });
    pdv.reset();

    try std.testing.expect(pdv.get("x").?.isMissing()); // numeric → .
    try std.testing.expectEqualStrings("", pdv.get("s").?.str); // char → blank
}

test "setFormat/formatOf associate a display format with a variable (G-attrib)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    _ = try pdv.define("d", .num);
    try std.testing.expect(pdv.formatOf("d") == null);
    pdv.setFormat("d", "date9.");
    try std.testing.expectEqualStrings("date9.", pdv.formatOf("d").?);
    pdv.setFormat("missingvar", "8.2"); // no-op when the var is undefined
    try std.testing.expect(pdv.formatOf("missingvar") == null);
}

test "setInformat/setLabel associate read informat + label with a variable (EXEC-varattr)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    _ = try pdv.define("amt", .num);
    try std.testing.expect(pdv.informatOf("amt") == null);
    try std.testing.expect(pdv.labelOf("amt") == null);
    pdv.setInformat("amt", "comma8.");
    pdv.setLabel("amt", "Amount Due");
    try std.testing.expectEqualStrings("comma8.", pdv.informatOf("amt").?);
    try std.testing.expectEqualStrings("Amount Due", pdv.labelOf("amt").?);
    // set-only: no-op (no auto-define) when the var is undefined, so column order stays put
    pdv.setInformat("ghost", "8.");
    pdv.setLabel("ghost", "x");
    try std.testing.expect(pdv.informatOf("ghost") == null);
    try std.testing.expect(pdv.labelOf("ghost") == null);
}

test "TRIAGE-gen2values: certain define corrects a guess; char->num assignment converts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // EG's VISITNUM shape: the compile pass guesses char from `v = put(...)`,
    // then a source schema (MERGE/UPDATE pre-declare) certainly says numeric.
    const i = try pdv.declare("v", .char);
    _ = try pdv.define("v", .num); // certain — must beat the guess
    try std.testing.expectEqual(VarType.num, pdv.vars.items[i].type);
    try std.testing.expect(pdv.get("v").?.isMissing());

    // a char value assigned to the certainly-numeric var converts (SAS
    // implicit BEST input): digits parse, blank/unparsable go missing
    try pdv.set("v", .{ .str = "99" });
    try std.testing.expectEqual(@as(f64, 99), pdv.get("v").?.num);
    try pdv.set("v", .{ .str = "  " });
    try std.testing.expect(pdv.get("v").?.isMissing());
    try pdv.set("v", .{ .str = "END OF STUDY" });
    try std.testing.expect(pdv.get("v").?.isMissing());

    // a guess with NO certain define still self-heals on the first real write
    _ = try pdv.declare("w", .num);
    try pdv.set("w", .{ .str = "text" });
    try std.testing.expectEqualStrings("text", pdv.get("w").?.str);
}

test "ISS-charnumassign: char→numeric assignment is LOUD, never silent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = diag.Diagnostics.init(arena.allocator());
    var pdv = Pdv.init(arena.allocator());
    pdv.diags = &diags; // the executor wires this in Executor.init

    _ = try pdv.define("n", .num);

    // invalid text → missing AND two NOTEs (converted + invalid numeric data),
    // never a silent exit-0 drop (the SDTM `*DTC` corruption class).
    try pdv.set("n", .{ .str = "hello" });
    try std.testing.expect(pdv.get("n").?.isMissing());
    try std.testing.expectEqual(@as(usize, 2), diags.count());
    try std.testing.expect(std.mem.indexOf(u8, diags.list.items[0].message, "converted to numeric") != null);
    try std.testing.expect(std.mem.indexOf(u8, diags.list.items[1].message, "Invalid numeric data, 'hello'") != null);

    // a valid numeric string still converts to the number, with the "converted"
    // note only (no invalid-data note) — must not regress n="123" → 123.
    try pdv.set("n", .{ .str = "123" });
    try std.testing.expectEqual(@as(f64, 123), pdv.get("n").?.num);
    try std.testing.expectEqual(@as(usize, 3), diags.count());

    // a blank string is valid missing: converts, note, but no "invalid data".
    try pdv.set("n", .{ .str = "  " });
    try std.testing.expect(pdv.get("n").?.isMissing());
    try std.testing.expectEqual(@as(usize, 4), diags.count());
}

test "NOTE-invalidnumdataloc: invalid-data NOTE omits the position, never freezes 0/0 (GH#78)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = diag.Diagnostics.init(arena.allocator());
    var pdv = Pdv.init(arena.allocator());
    pdv.diags = &diags;

    // The PDV store has no statement context, so SAS's "at line N column M."
    // tail is honestly absent — the captured reporter proves nothing frozen
    // rides in the message or the rendered log.
    _ = try pdv.define("n", .num);
    try pdv.set("n", .{ .str = "hello" });
    try std.testing.expectEqualStrings("Invalid numeric data, 'hello'.", diags.list.items[1].message);
    const log = try diags.render();
    try std.testing.expect(std.mem.indexOf(u8, log, "NOTE: Invalid numeric data, 'hello'.\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, log, "(L0") == null);
    try std.testing.expect(std.mem.indexOf(u8, log, "column 0") == null);
    try std.testing.expectEqual(@as(f64, 1), pdv.get("_error_").?.num); // _ERROR_=1 kept
}

test "CHARNUM-errorvar: an invalid char→num conversion sets _ERROR_=1, live in-step" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());
    _ = try pdv.define("n", .num);

    // executor resets _ERROR_ to 0 at the top of each iteration; model that.
    try pdv.set("_error_", .{ .num = 0 });
    try std.testing.expectEqual(@as(f64, 0), pdv.get("_error_").?.num);

    // a valid numeric string converts without raising the flag.
    try pdv.set("n", .{ .str = "123" });
    try std.testing.expectEqual(@as(f64, 0), pdv.get("_error_").?.num);

    // a blank string is valid missing — still no error.
    try pdv.set("n", .{ .str = "  " });
    try std.testing.expectEqual(@as(f64, 0), pdv.get("_error_").?.num);

    // non-blank unparsable text is the invalid conversion → _ERROR_=1 immediately.
    try pdv.set("n", .{ .str = "hello" });
    try std.testing.expectEqual(@as(f64, 1), pdv.get("_error_").?.num);

    // next iteration: executor's reset clears it back to 0.
    try pdv.set("_error_", .{ .num = 0 });
    try std.testing.expectEqual(@as(f64, 0), pdv.get("_error_").?.num);
}

test "GH#74: num→char assignment logs the SAS conversion NOTE, GH#9 char→num still fires" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var diags = diag.Diagnostics.init(arena.allocator());
    var pdv = Pdv.init(arena.allocator());
    pdv.diags = &diags;

    // `length c $8; c = n;` (n numeric): char var, num value → converted note (case 3)
    _ = try pdv.define("c", .char);
    pdv.vars.items[pdv.indexOf("c").?].len = 8;
    try pdv.set("c", .{ .num = 42 });
    try std.testing.expectEqual(@as(usize, 1), diags.count());
    try std.testing.expect(std.mem.indexOf(u8, diags.list.items[0].message, "converted to character") != null);

    // GH#9 guard: char→num ASSIGNMENT still emits its converted note (not regressed)
    _ = try pdv.define("n", .num);
    try pdv.set("n", .{ .str = "123" });
    try std.testing.expectEqual(@as(usize, 2), diags.count());
    try std.testing.expect(std.mem.indexOf(u8, diags.list.items[1].message, "converted to numeric") != null);
}

test "GH#46: numeric LENGTH<8 stores the high N bytes of the IEEE double" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var pdv = Pdv.init(arena.allocator());

    // the validated big-endian truncation table for 36.6 (0x40424CCCCCCCCCCD)
    const table = [_]struct { n: usize, bits: u64 }{
        .{ .n = 3, .bits = 0x40424C0000000000 }, // 36.59375
        .{ .n = 4, .bits = 0x40424CCC00000000 }, // 36.5999755859375
        .{ .n = 5, .bits = 0x40424CCCCC000000 }, // 36.59999990463257
        .{ .n = 6, .bits = 0x40424CCCCCCC0000 }, // 36.59999999962747
        .{ .n = 7, .bits = 0x40424CCCCCCCCC00 }, // 36.599999999998545
    };
    for (table) |t| {
        var v = try pdv.define("x", .num);
        pdv.vars.items[v].numlen = t.n;
        try pdv.set("x", .{ .num = 36.6 });
        try std.testing.expectEqual(t.bits, @as(u64, @bitCast(pdv.get("x").?.num)));
        pdv.vars.items[v].numlen = 0; // reset for the next round
        _ = &v;
    }

    // length 8 (or unset) is the full, untruncated double
    var f = try pdv.define("y", .num);
    pdv.vars.items[f].numlen = 8;
    try pdv.set("y", .{ .num = 36.6 });
    try std.testing.expectEqual(@as(f64, 36.6), pdv.get("y").?.num);
    _ = &f;

    // missing stays missing (never bit-masked into a live value)
    var m = try pdv.define("z", .num);
    pdv.vars.items[m].numlen = 5;
    try pdv.set("z", Value.missing);
    try std.testing.expect(pdv.get("z").?.isMissing());
    _ = &m;
}

test "BUG-numcharwidth: numToChar is BESTw. RIGHT-JUSTIFIED; set() converts num→char to the padded string" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // the helper: w=12 expression width, w=8/20 assignment widths, sign/decimal/missing
    try std.testing.expectEqualStrings("           5", try numToChar(a, 5, 12));
    try std.testing.expectEqualStrings("       5", try numToChar(a, 5, 8));
    try std.testing.expectEqualStrings("                   5", try numToChar(a, 5, 20));
    try std.testing.expectEqualStrings("         -42", try numToChar(a, -42, 12));
    try std.testing.expectEqualStrings("        3.25", try numToChar(a, 3.25, 12));
    try std.testing.expectEqualStrings("    0.000123", try numToChar(a, 0.000123, 12));
    try std.testing.expectEqualStrings("           .", try numToChar(a, Value.missing.num, 12));
    const sm = Value.parseSpecialMissing(".A").?;
    try std.testing.expectEqualStrings("           A", try numToChar(a, sm.num, 12)); // ISS-specialmiss-tochar

    // set(): a numeric stored into a char var becomes a COMPACT char cell —
    // the SET-load leniency (GH#69/#70: CSV read a really-char ID as numeric;
    // the value renders as if it had been char all along, real-SAS goldens pin
    // it). BESTn. padding lives in __assignc (parser-known `length` targets).
    var pdv = Pdv.init(a);
    const i = try pdv.define("c", .char);
    pdv.vars.items[i].len = 8; // ATTRIB/SET-schema width
    try pdv.set("c", .{ .num = 5 });
    try std.testing.expectEqualStrings("5", pdv.get("c").?.str);
    _ = try pdv.define("d", .char);
    try pdv.set("d", .{ .num = 5 });
    try std.testing.expectEqualStrings("5", pdv.get("d").?.str);
}
