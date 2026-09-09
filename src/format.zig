//! Format engine — render a `Value` as text under a SAS format spec.
//!
//! A spec is `<$>NAME<w>.<d>`: an optional `$` (char), a name (empty = the
//! plain numeric `w.d` / F format), a width `w`, and decimals `d`. Supported:
//!   w.d        right-justified fixed-point, `d` decimals, width `w`
//!   $w.        char, left-justified, blank-padded / truncated to `w`
//!   COMMAw.d   like w.d with thousands separators
//!   DOLLARw.d  COMMA with a leading `$`
//!   DATEw.     a SAS date (days since 1960-01-01) as ddMMMyy(yy); w≥9 → 4-digit year,
//!                w≥10 → hyphenated dd-MMM-yy(yy)
//!   MMDDYYw.   a SAS date as mm/dd/yy(yy); w≥10 → 4-digit year
//!   DDMMYYw.   a SAS date as dd/mm/yy(yy); w≥10 → 4-digit year
//!   YYMMDDw.   a SAS date as yy(yy)-mm-dd; w≥10 → 4-digit year
//!   WORDDATEw. a SAS date as `Month d, yyyy`
//!   TIMEw.     a SAS time (seconds) as hh:mm:ss
//!   Zw.d       like w.d but left-padded with zeros instead of blanks
//!   PERCENTw.d value×100 with a trailing `%`; negatives wrapped in parentheses
//! Missing numerics render as `.` (right-justified). This is the engine behind
//! the `put` statement/function and the `format` statement (PROC PRINT).
//!
//! ponytail: unknown numeric names (BEST/DOLLAR/…) fall back to plain `w.d`;
//! overflow/too-narrow widths return the natural text rather than SAS's `*`
//! fill — add both when a corpus fixture pins the exact SAS output.

const std = @import("std");
const assert = std.debug.assert;
const Value = @import("value.zig").Value;
const pdv = @import("pdv.zig"); // sasParseFloat (import cycle is fine — Zig is lazy)
const diag = @import("diag.zig"); // markGap — D-009 §5f documented-name split

const Error = std.mem.Allocator.Error;

pub const Spec = struct {
    name: []const u8 = "", // format name sans `$`/width; "" = plain numeric w.d
    is_char: bool = false, // leading `$`
    w: usize = 0, // width (0 = unspecified)
    d: usize = 0, // decimals
};

// ── User-defined formats (`proc format; value NAME …;`) ──────────────────────
// A VALUE format maps values (or numeric ranges) to display labels. proc.zig
// parses the VALUE statements into this catalog and installs it here; `apply`
// consults it before the built-in renderers, so `put(x, sexf.)` / a PROC PRINT
// column format shows the label. Coded-value → label decode is the single most
// common clinical-SAS idiom (BUG-userformat).

pub const UserFmtEntry = struct {
    lo: f64 = 0, // numeric range low (single value → lo==hi)
    hi: f64 = 0, // numeric range high
    lo_excl: bool = false, // `<n-m` — low endpoint EXCLUDED (BUG-formatexclrange)
    hi_excl: bool = false, // `n-<m` — high endpoint EXCLUDED
    skey: []const u8 = "", // character key (for `$NAME` formats)
    skey_hi: []const u8 = "", // char RANGE high endpoint (`'A'-'C'=`, GAP-fmtcharrange); "" → single exact key
    label: []const u8, // the display label (a PICTURE template when the fmt is_picture)
    nested: bool = false, // label is a NESTED-FORMAT spec (`range=[fmtname w.d]`,
    // BUG-fmtnestlabel): apply resolves it by rendering the value under that spec.
    is_other: bool = false, // the catch-all `OTHER=` entry
    prefix: []const u8 = "", // PICTURE PREFIX= — prepended to the rendered digits
    mult: f64 = 0, // PICTURE MULT= — value multiplier before picturing (0 → 1)
    round: bool = false, // PICTURE `(round)` — round to the last selector instead of truncating
};

pub const UserFmt = struct {
    name: []const u8, // base name, no `$`/width/`.` (compared case-insensitively)
    is_char: bool, // defined as `$NAME` (character keys)
    is_picture: bool = false, // PICTURE format: labels are digit-selector templates
    entries: []const UserFmtEntry,
};

// ponytail: a single process-wide catalog — the interpreter runs one program at a
// time; main clears it per program, proc.zig replaces it. Not threaded through
// `apply`'s eight callers, which would be far more churn than the feature needs.
var user_catalog: []const UserFmt = &.{};

// ── Definition-time entry index (PERF-fmtscan) ───────────────────────────────
// Without this, `put(x, $FMT.)` over N rows costs O(N × entries): lookupUserFmt
// scans every entry per call. A controlled-terminology codelist has hundreds–
// thousands of entries, so a real SDTM decode is quadratic. We index each
// format's entries ONCE (at setUserFormats): discrete CHAR → key hashmap,
// discrete NUMERIC (all-single-value formats) → numeric key hashmap, and true
// low-high RANGE formats → entries sorted by `lo` for a binary search
// (PERF-fmtrangescan) — kept only when the ranges are provably non-overlapping,
// so the unique containing range IS the linear first-match and output is
// byte-identical. Overlapping ranges (first-match-by-definition-order) keep the
// linear scan. `fmt_index[i]`
// pairs with `user_catalog[i]`; borrowed key/label slices live as long as the
// catalog does, so the index is rebuilt/dropped in lockstep with it.
const FmtIndex = struct {
    char_map: std.StringHashMapUnmanaged(*const UserFmtEntry) = .empty,
    num_map: std.AutoHashMapUnmanaged(u64, *const UserFmtEntry) = .empty,
    other: ?*const UserFmtEntry = null, // precomputed OTHER= entry (first wins), so a miss is O(1)
    indexed: bool = false, // false → lookupUserFmt uses the linear fallback (overlapping ranges / OOM)
    // Numeric entries (ranges + any discrete singles) sorted by (lo,hi),
    // VERIFIED pairwise non-overlapping at build. Empty → no range path.
    ranges: []const UserFmtEntry = &.{},
};
var fmt_index: []FmtIndex = &.{};
var idx_arena: ?std.heap.ArenaAllocator = null;

/// Install the VALUE-format catalog (proc.zig owns the arena it points into) and
/// (re)build the entry index over it.
pub fn setUserFormats(c: []const UserFmt) void {
    user_catalog = c;
    buildIndex(c);
}

/// Drop any installed formats — main calls this at the start of each program so a
/// previous run's (freed) catalog is never read. Also resets YEARCUTOFF to the SAS
/// default, so an `OPTIONS YEARCUTOFF=` from a prior run doesn't leak.
/// Per-run callers want `resetPerRun` below; this is the catalog half, kept
/// separate because ~20 tests use it purely to drop a catalog they installed.
pub fn clearUserFormats() void {
    user_catalog = &.{};
    if (idx_arena) |*a| a.deinit();
    idx_arena = null;
    fmt_index = &.{};
    year_cutoff = 1926;
}

/// BUG-fmterrorneverreset — EVERY run-scoped process-global this file owns,
/// cleared in one place; `main.interpret` calls it at the start of each program.
/// The CLI got this for free from process exit, but `wasm.zig` runs many programs
/// per load, so both flags leaked across programs in a demo session and each leak
/// is silent:
///   - `g_fmt_error` (→ D-009 rc 1): ONE unknown format made EVERY LATER program
///     exit 1, reporting a correct program as failing with no clue why.
///   - `g_nofmterr` (`OPTIONS NOFMTERR`): the same leak with the opposite and
///     WORSE sign — a prior program's NOFMTERR silently SWALLOWED a later
///     program's format error, so invalid SAS came back clean at rc 0.
/// `year_cutoff` was already being reset per run inside `clearUserFormats`, which
/// is the precedent: an OPTIONS-derived global is run-scoped, not session-scoped.
pub fn resetPerRun() void {
    clearUserFormats();
    g_fmt_error = false;
    g_nofmterr = false;
}

/// Build `fmt_index` for `c`. Best-effort: on OOM the whole index is dropped and
/// every format falls back to the linear scan (slower, but correct).
/// ponytail: numeric keys hashed by IEEE bit-pattern — matches the `lo==hi` `==`
/// the linear scan does for real codelist codes; a -0.0/0.0 mismatch (never in a
/// codelist) or NaN (excluded by the caller) is the only gap. Owns its own page-
/// arena rather than threading proc.zig's allocator through setUserFormats.
fn buildIndex(c: []const UserFmt) void {
    if (idx_arena) |*a| a.deinit();
    idx_arena = null;
    fmt_index = &.{};
    if (c.len == 0) return;
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const a = arena.allocator();
    const idx = a.alloc(FmtIndex, c.len) catch {
        arena.deinit();
        return;
    };
    for (idx) |*fi| fi.* = .{};
    for (c, 0..) |uf, i| {
        if (uf.is_picture) continue; // pictures render via renderPicture, never lookupUserFmt
        buildOne(a, uf, &idx[i]) catch {
            arena.deinit();
            return;
        };
    }
    idx_arena = arena;
    fmt_index = idx;
}

fn buildOne(a: std.mem.Allocator, uf: UserFmt, fi: *FmtIndex) !void {
    // The maps/pointers reference the catalog's entries (arena-owned) directly —
    // an ENTRY is stored (not just its label) so a nested-format label
    // (`=[fmtname]`) still resolves at apply time (BUG-fmtnestlabel).
    for (uf.entries, 0..) |e, k| if (e.is_other) {
        fi.other = &uf.entries[k]; // first OTHER wins, mirroring the trailing catch-all loop
        break;
    };
    if (uf.is_char) {
        var has_range = false; // char RANGE entries ('A'-'C'=) can't hash — see below
        for (uf.entries, 0..) |e, k| {
            if (e.is_other) continue;
            if (e.skey_hi.len > 0) {
                has_range = true;
                continue;
            }
            const gop = try fi.char_map.getOrPut(a, std.mem.trimEnd(u8, e.skey, " "));
            if (!gop.found_existing) gop.value_ptr.* = &uf.entries[k]; // first match wins
        }
        // A range interleaves with discrete keys in DEFINITION order (first match
        // wins), which a hashmap can't reproduce — such formats keep the linear scan.
        fi.indexed = !has_range;
        return;
    }
    // Numeric: hash-index only if EVERY non-OTHER entry is a single discrete value.
    var all_discrete = true;
    for (uf.entries) |e| {
        if (e.is_other) continue;
        // BIT-compare, not `!=`: a special-missing key (.A=, from a sas7bcat
        // catalog or CNTLIN START=.A — NOTE-sas7bcatspecialmiss) is a NaN whose
        // lo==hi must still count as ONE discrete value (NaN != NaN by IEEE).
        if (@as(u64, @bitCast(e.lo)) != @as(u64, @bitCast(e.hi)) or e.lo_excl or e.hi_excl) {
            all_discrete = false;
            break;
        }
    }
    if (all_discrete) {
        for (uf.entries, 0..) |e, k| {
            if (e.is_other) continue;
            const gop = try fi.num_map.getOrPut(a, @bitCast(e.lo));
            if (!gop.found_existing) gop.value_ptr.* = &uf.entries[k];
        }
        fi.indexed = true;
        return;
    }
    // A true range is present: sort the non-OTHER entries by (lo,hi) once for an
    // O(log R) lookup (PERF-fmtrangescan). Empty result → overlap/NaN → linear.
    fi.ranges = try sortedRanges(a, uf.entries);
}

/// The non-OTHER entries sorted by (lo,hi) for the binary-search range path — or
/// an empty slice when the format must keep the linear scan: NaN bounds, or any
/// OVERLAP (sorted adjacent pair not provably disjoint), where SAS first-match
/// by definition order is the tie-break a bsearch can't reproduce. When every
/// adjacent pair is disjoint, at most ONE entry can contain any value, so the
/// bsearch match is exactly the linear first-match (byte-identical output).
/// Touching endpoints count as disjoint only when an exclusion flag separates
/// them (`0-<5` and `<5-10` share no value).
fn sortedRanges(a: std.mem.Allocator, entries: []const UserFmtEntry) ![]const UserFmtEntry {
    var n: usize = 0;
    for (entries) |e| if (!e.is_other) {
        if (std.math.isNan(e.lo) or std.math.isNan(e.hi)) return &.{}; // unordered bound → linear
        n += 1;
    };
    const s = try a.alloc(UserFmtEntry, n);
    n = 0;
    for (entries) |e| if (!e.is_other) {
        s[n] = e;
        n += 1;
    };
    std.mem.sort(UserFmtEntry, s, {}, struct {
        fn lt(_: void, x: UserFmtEntry, y: UserFmtEntry) bool {
            return if (x.lo != y.lo) x.lo < y.lo else x.hi < y.hi;
        }
    }.lt);
    var i: usize = 0;
    while (i + 1 < s.len) : (i += 1) {
        const p = s[i];
        const c = s[i + 1];
        if (!(p.hi < c.lo or (p.hi == c.lo and (p.hi_excl or c.lo_excl)))) return &.{};
    }
    return s;
}

/// Binary-search the sorted, verified-non-overlapping ranges for the entry whose
/// [lo,hi] contains `x` (endpoint exclusions honoured); null on no match — the
/// caller then applies OTHER=/default, exactly like the linear scan. The probe
/// lands on the LAST entry with lo <= x, the only possible match — except at an
/// exclusion-split boundary (`0-5` / `5<-10`, x=5) where the LEFT NEIGHBOUR
/// holds it, so both are probed. Same lo_ok/hi_ok test as the linear scan.
fn rangeLookup(r: []const UserFmtEntry, x: f64) ?UserFmtEntry {
    var lo: usize = 0;
    var hi: usize = r.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (r[mid].lo <= x) lo = mid + 1 else hi = mid;
    }
    var back: usize = 0;
    while (back < 2 and back < lo) : (back += 1) {
        const e = r[lo - 1 - back];
        const lo_ok = if (e.lo_excl) x > e.lo else x >= e.lo;
        const hi_ok = if (e.hi_excl) x < e.hi else x <= e.hi;
        if (lo_ok and hi_ok) return e;
    }
    return null;
}

/// The first year of the 100-year span used to read a 2-digit year (OPTIONS
/// YEARCUTOFF=, default 1926 — SAS 9.4). BUG-yearcutoff — the caller (main's OPTIONS handler)
/// sets it; date informats in io.zig read it.
var year_cutoff: i64 = 1926;

pub fn setYearCutoff(y: i64) void {
    year_cutoff = y;
}
pub fn yearCutoff() i64 {
    return year_cutoff;
}

/// Expand a 2-digit year `yy` (0–99) into the full year within the YEARCUTOFF span
/// [cutoff, cutoff+99]. A 4-digit `y` (≥100) passes through unchanged.
pub fn expandYear(y: i64) i64 {
    if (y >= 100 or y < 0) return y;
    const century = @divFloor(year_cutoff, 100) * 100;
    const cand = century + y;
    return if (cand < year_cutoff) cand + 100 else cand;
}

/// The current catalog (proc.zig reads it to append across multiple PROC FORMAT
/// steps).
pub fn userFormats() []const UserFmt {
    return user_catalog;
}

/// True when `spec` names an installed VALUE format (regardless of whether a
/// value matches). Lets `apply` tell "defined format, value fell through a range"
/// apart from "unknown format" so the former renders raw instead of failing loud.
fn isUserFmtName(v: Value, spec: Spec) bool {
    if (spec.name.len == 0) return false;
    for (user_catalog) |uf| {
        // Same value-type-aware match as lookupUserFmt (QA-charfmtnodollar): a
        // char-typed format referenced $-lessly on a char value IS this format.
        const type_ok = uf.is_char == spec.is_char or (uf.is_char and !spec.is_char and v == .str);
        if (type_ok and eqi(uf.name, spec.name)) return true;
    }
    return false;
}

/// Default width of a user-defined format = the length of its longest label
/// (GH#63 ISS-fmtdefwidth). SAS uses this when a PUT names the format with no
/// explicit width, so an unmatched CHAR value is truncated to it. Returns 0 when
/// `spec` names no installed format, so a built-in `$.`/`$w.` keeps its own w==0
/// meaning ("value as-is", NOT truncated).
fn userFmtDefaultWidth(v: Value, spec: Spec) usize {
    if (spec.name.len == 0) return 0;
    for (user_catalog) |uf| {
        const type_ok = uf.is_char == spec.is_char or (uf.is_char and !spec.is_char and v == .str);
        if (!type_ok or !eqi(uf.name, spec.name)) continue;
        var maxw: usize = 0;
        for (uf.entries) |e| maxw = @max(maxw, e.label.len);
        return maxw;
    }
    return 0;
}

/// SAS 9.4 DEFAULT width for the width-less date formats (BUG-fmtdefwidth-date,
/// doc-finder tick250; Language Reference: Concepts p.147/164 "Write SAS date values in recognizable
/// forms": `MONYY.`→`MAR13`, `JULIAN.`→`13076` — both 5, the 2-DIGIT-year form).
/// The word/name formats pad into their field: WORDDATE/WORDDATX 18, WEEKDATE/
/// WEEKDATX 29 (right-justified), MONNAME/DOWNAME 9. 0 = keep the renderer's
/// natural form (every other format; DTMONYY/DTWKDATX/PDJULIAN/NLDATE included).
/// DATETIME's default is the one this table was missing (NOTE-datetimewidth):
/// `DATETIMEw.d — w Default 16, Range 7–40` with the entry's own worked example
/// `put x datetime.;` → `14MAR18:22:25:33` (SAS 9.4 Formats and Informats:
/// Reference, printed p.176-177). A width-less `datetime.` was rendering the
/// renderer's "natural" 18-wide FOUR-digit-year form, i.e. the wrong year width
/// on every width-less datetime PUT. 16 selects the 2-digit-year form through
/// the EXISTING width ladder — `datetime16.` already produced exactly the
/// doc's string, so this is a default-width fix, not a renderer change.
fn dateDefaultWidth(name: []const u8) usize {
    if (eqi(name, "monyy") or eqi(name, "julian")) return 5;
    if (eqi(name, "nengo")) return 10; // NENGOw. p.257, Default 10
    if (eqi(name, "worddate") or eqi(name, "worddatx")) return 18;
    if (eqi(name, "weekdate") or eqi(name, "weekdatx")) return 29;
    if (eqi(name, "monname") or eqi(name, "downame")) return 9;
    if (eqi(name, "datetime")) return 16;
    // TIMEw.d — `w Default 8, Range 2–20` (p.478). The field width is what
    // supplies the leading blank the entry states NORMATIVELY, twice: "If hh is
    // a single digit, TIMEw.d places a leading blank before the digit" (p.479)
    // and "The TIMEw.d format writes a leading blank for a single-hour digit"
    // (p.479, Comparisons). Width-less `time.` used the renderer's natural form
    // and so dropped that blank (`9:00:00` where `time8.` gives ` 9:00:00`).
    // Not a contradiction of Language Reference: Concepts p.147's `TIME. 19434 -> 5:23:54` table row:
    // that CELL cannot show leading whitespace — as the Formats entry's own
    // inline example, "writes 9:00 instead of 09:00", equally cannot.
    // This is also the blank-pad half of the TOD contrast (NOTE-todhourpad):
    // TOD ZERO-pads its hour, TIME BLANK-pads it. Two rules, both cited.
    if (eqi(name, "time")) return 8;
    // ponytail: DATEw. (Default 7, p.172) and TODw.d (Default 8, p.483) need no
    // entry — each renderer's natural w==0 form is ALREADY its documented
    // default width (`date.` == `date7.`; TOD's zero-padded hour makes its body
    // exactly 8), so an entry would be inert. Add one only if that stops holding.
    return 0;
}

/// If `spec` names an installed VALUE format, return the matching ENTRY (its
/// range/key match, else the `OTHER=` entry). Null when no such format, no match
/// and no OTHER — the caller then falls back to the built-in renderers. The
/// caller renders `.label` — or, for a nested-format label (`range=[fmtname]`,
/// `.nested` set), applies the spec held in `.label` to the value at render time
/// (BUG-fmtnestlabel).
/// If `spec` names an installed PICTURE format whose range matches `v`, return the
/// matching entry (its `.label` is the digit template + PREFIX/MULT). Null otherwise
/// — a named-but-unmatched picture falls through to a raw render (isUserFmtName).
fn pictureEntryFor(v: Value, spec: Spec) ?UserFmtEntry {
    if (user_catalog.len == 0 or spec.name.len == 0) return null;
    for (user_catalog) |uf| {
        if (!uf.is_picture or !eqi(uf.name, spec.name)) continue;
        const x = valToNum(v);
        if (std.math.isNan(x)) return null;
        for (uf.entries) |e| {
            if (e.is_other) continue;
            const lo_ok = if (e.lo_excl) x > e.lo else x >= e.lo;
            const hi_ok = if (e.hi_excl) x < e.hi else x <= e.hi;
            if (lo_ok and hi_ok) return e;
        }
        for (uf.entries) |e| if (e.is_other) return e;
        return null;
    }
    return null;
}

/// Render a numeric PICTURE. Digit selectors ('0'–'9') consume the value's decimal
/// digits right-to-left; a leading position with no digit prints a blank under a `0`
/// selector (leading zeros SUPPRESSED) and '0' under a nonzero selector (zero-fill)
/// — SAS 9.4 semantics: "nines print zeros, zeros suppress" (BUG-picturedigitsel).
/// Non-selector chars are message/literal chars. In the leading SUPPRESSED
/// region of a `0`-selector template (before the first significant digit),
/// message chars print as blanks and PREFIX= hugs the first significant digit
/// (BUG-picturesep); once significant digits start, message chars print verbatim.
/// MULT scales the value first.
/// ponytail: magnitude only (SAS default drops the sign on plain pictures); a
/// value wider than the template drops its high digits. Add sign/fill
/// options when a program needs them.
fn renderPicture(arena: std.mem.Allocator, x: f64, e: UserFmtEntry) Error![]const u8 {
    // MULT= scales the value before picturing. SAS default: if the picture has a
    // decimal point and no explicit MULT=, the multiplier is 10^(digit selectors
    // after the '.') so the fractional part fills the trailing selectors
    // (BUG-picturedecimal) — else the value was rounded to an integer and the
    // digits landed in the wrong selectors (12.5 with '0009.99' → "000 .13").
    var mult: f64 = if (e.mult == 0) 1 else e.mult;
    if (e.mult == 0) if (std.mem.indexOfScalar(u8, e.label, '.')) |dot| {
        var ndec: usize = 0;
        for (e.label[dot + 1 ..]) |c| if (c >= '0' and c <= '9') {
            ndec += 1;
        };
        var m: f64 = 1;
        for (0..ndec) |_| m *= 10;
        mult = m;
    };
    // SAS 9.4 TRUNCATES the scaled value by default — rounding is opt-in via the
    // PICTURE `(round)` option (BUG-picturetrunc, GAP-pictureround). Zig's
    // @intFromFloat already truncates toward 0, so the default is a bare cast
    // (12.35×10 → 123, not 124); `(round)` rounds the scaled value first (3.98
    // under '009.9' → 39.8 → 40 → `4.0`). @round is ties-away-from-zero, and the
    // magnitude is already non-negative — matches SAS half-up rounding.
    const scaled0 = @abs(x) * mult;
    const scaled = if (e.round) @round(scaled0) else scaled0;
    // Guard the @intFromFloat: a scaled magnitude ≥ 2^64 (or inf) traps the
    // cast (BUG-pictureoverflowpanic, QA fuzz tick158). Per SAS a value that
    // cannot fit the picture fills the field with asterisks, like any numeric
    // format that cannot represent the value. `!(scaled < 2^64)` also catches
    // NaN. In-range values are unchanged.
    if (!(scaled < 18446744073709551616.0)) {
        const out = try arena.alloc(u8, e.prefix.len + e.label.len);
        @memset(out, '*');
        return out;
    }
    const n: u64 = @intFromFloat(scaled);
    var digbuf: [24]u8 = undefined;
    const digs = std.fmt.bufPrint(&digbuf, "{d}", .{n}) catch unreachable;
    const tmpl = e.label;
    // SAS requires one selector digit per picture; a NONZERO selector zero-FILLs
    // (never suppressed) and keeps the old path: prefix at field start, message
    // chars verbatim (`$000,042`). Only all-`0` templates take the suppression
    // logic below (BUG-picturesep).
    var zero_fill = false;
    for (tmpl) |c| if (c >= '1' and c <= '9') {
        zero_fill = true;
        break;
    };
    const out = try arena.alloc(u8, e.prefix.len + tmpl.len);
    const body = out[e.prefix.len..];
    var di = digs.len;
    var ti = tmpl.len;
    var sig_start: usize = tmpl.len;
    while (ti > 0) {
        ti -= 1;
        const c = tmpl[ti];
        if (c >= '0' and c <= '9') {
            if (di > 0) {
                di -= 1;
                body[ti] = digs[di];
                sig_start = ti;
            } else body[ti] = if (c == '0') ' ' else '0';
        } else body[ti] = c;
    }
    if (!zero_fill and sig_start < tmpl.len) {
        // Leading suppressed region: blank the message chars too, and slide
        // PREFIX= up against the first significant digit. The significant tail
        // body[sig_start..] already sits at out[sig_start + prefix.len..], so
        // only the blanks + prefix need writing.
        @memset(out[0..sig_start], ' ');
        @memcpy(out[sig_start .. sig_start + e.prefix.len], e.prefix);
        return out;
    }
    @memcpy(out[0..e.prefix.len], e.prefix);
    return out;
}

fn lookupUserFmt(v: Value, spec: Spec) ?UserFmtEntry {
    if (user_catalog.len == 0 or spec.name.len == 0) return null;
    for (user_catalog, 0..) |uf, i| {
        if (uf.is_picture) continue; // pictures render via renderPicture, not as literal labels
        // A character VALUE resolves a char-typed format referenced WITHOUT the
        // `$` — SAS matches by name + value type there (the study's CNTLIN
        // TYPE='C' codelists are applied `put(VISIT, VISNUM_ALL_PERIOD.)`,
        // $-less; QA-charfmtnodollar). A `$fmt` on a numeric value still falls
        // through to the default renderers.
        const type_ok = uf.is_char == spec.is_char or (uf.is_char and !spec.is_char and v == .str);
        if (!type_ok or !eqi(uf.name, spec.name)) continue;
        // Indexed fast path (PERF-fmtscan): O(1) discrete lookup, precomputed
        // OTHER. Semantics match the linear scan below exactly — first-match
        // (getOrPut kept the first duplicate), $fmt-on-numeric → null, miss →
        // OTHER-or-null, numeric-missing → its exact missing key, else OTHER-or-null.
        if (i < fmt_index.len and fmt_index[i].indexed) {
            const fi = &fmt_index[i];
            if (uf.is_char) {
                const s = switch (v) {
                    .str => |cs| std.mem.trimEnd(u8, cs, " "),
                    .num => return null,
                };
                if (fi.char_map.get(s)) |ep| return ep.*;
            } else {
                const x = valToNum(v);
                // A numeric MISSING value also consults the map: a special-missing
                // KEY (.A=) is hashed by its NaN bits and matches only that exact
                // missing (NOTE-sas7bcatspecialmiss). `v == .num` keeps a char
                // value's failed num parse out of the missing path.
                if (!std.math.isNan(x) or v == .num) if (fi.num_map.get(@bitCast(x))) |ep| return ep.*;
            }
            return if (fi.other) |op| op.* else null;
        }
        // Sorted-range fast path (PERF-fmtrangescan): O(log R) bsearch over the
        // verified-non-overlapping ranges. Same NaN-skip and OTHER-or-null miss
        // semantics as the linear scan below.
        if (i < fmt_index.len and !uf.is_char and fmt_index[i].ranges.len > 0) {
            const fi = &fmt_index[i];
            const x = valToNum(v);
            if (!std.math.isNan(x)) if (rangeLookup(fi.ranges, x)) |e| return e;
            return if (fi.other) |op| op.* else null;
        }
        // ── linear fallback: overlapping-range formats, or index unavailable (OOM) ──
        if (uf.is_char) {
            const s = switch (v) {
                .str => |cs| std.mem.trimEnd(u8, cs, " "),
                .num => return null, // a `$fmt` on a numeric value: leave to the default
            };
            for (uf.entries) |e| {
                if (e.is_other) continue;
                const lo = std.mem.trimEnd(u8, e.skey, " ");
                if (e.skey_hi.len == 0) {
                    if (std.mem.eql(u8, lo, s)) return e;
                } else {
                    // Char range 'A'-'C' (GAP-fmtcharrange): bytewise lexical match
                    // on the trimmed value (SAS collating order); `<` excludes an
                    // endpoint exactly like the numeric range path below.
                    // ponytail: a value with bytes < 0x20 sorts differently than
                    // SAS blank-padding — control chars never appear in codelists.
                    const hi = std.mem.trimEnd(u8, e.skey_hi, " ");
                    const lo_ok = if (e.lo_excl) std.mem.order(u8, s, lo) == .gt else std.mem.order(u8, s, lo) != .lt;
                    const hi_ok = if (e.hi_excl) std.mem.order(u8, s, hi) == .lt else std.mem.order(u8, s, hi) != .gt;
                    if (lo_ok and hi_ok) return e;
                }
            }
        } else {
            const x = valToNum(v);
            if (std.math.isNan(x)) {
                // A numeric MISSING value matches an exact missing KEY only
                // (bit-equal, so .A finds .A's label and never .B's) —
                // NOTE-sas7bcatspecialmiss. `v == .num` keeps a char value out.
                if (v == .num) for (uf.entries) |e| {
                    if (!e.is_other and @as(u64, @bitCast(e.lo)) == @as(u64, @bitCast(x)) and
                        @as(u64, @bitCast(e.hi)) == @as(u64, @bitCast(x))) return e;
                };
            } else {
                for (uf.entries) |e| {
                    const lo_ok = if (e.lo_excl) x > e.lo else x >= e.lo;
                    const hi_ok = if (e.hi_excl) x < e.hi else x <= e.hi;
                    if (!e.is_other and lo_ok and hi_ok) return e;
                }
            }
        }
        for (uf.entries) |e| if (e.is_other) return e; // catch-all
        return null; // named format but no match/OTHER → default rendering
    }
    return null;
}

/// Parse `<$>NAME<w>.<d>`. Tolerant: any missing piece defaults (name "", w 0,
/// d 0). Case is preserved; callers compare names case-insensitively.
pub fn parseSpec(text: []const u8) Spec {
    var s: Spec = .{};
    var i: usize = 0;
    if (i < text.len and text[i] == '$') {
        s.is_char = true;
        i += 1;
    }
    const name_start = i;
    // A format name is letters/digits/underscores, but SAS names never END in a
    // digit — the TRAILING digit run is the width. So scan the whole alnum run,
    // then peel the final digits off as w (QA-e8601put: `E8601DT19.` is name
    // E8601DT + w 19; the old letters-only scan made it name "e" + w 8601 → the
    // Ew. scientific format, silent wrong output). Underscores are ALWAYS part
    // of the name (CNTLIN codelists like `VISNUM_ALL_PERIOD.`, QA-svvisnum);
    // names ending in letters split exactly as before (`comma8.`, `date9.`).
    while (i < text.len and (std.ascii.isAlphanumeric(text[i]) or text[i] == '_')) i += 1;
    var name_end = i;
    while (name_end > name_start and std.ascii.isDigit(text[name_end - 1])) name_end -= 1;
    s.name = text[name_start..name_end];
    s.w = std.fmt.parseInt(usize, text[name_end..i], 10) catch 0;
    if (i < text.len and text[i] == '.') {
        i += 1;
        const d_start = i;
        while (i < text.len and std.ascii.isDigit(text[i])) i += 1;
        s.d = std.fmt.parseInt(usize, text[d_start..i], 10) catch 0;
    }
    return s;
}

/// Read a numeric field under an informat `spec_text` (INPUT/INFILE), returning a
/// SAS numeric Value. Two behaviours a plain float parse misses:
///   * a `w.d` informat's IMPLIED decimal — a field with no explicit `.` is
///     scaled by 10^-d, so `12345` under `5.2` reads as 123.45 (BUG-informatdec);
///   * PERCENTw. — a trailing `%` is dropped and the value divided by 100, so
///     `45%` reads as 0.45 (BUG-percentinformat); parentheses read as a
///     negative percentage, so `(25%)` reads as -0.25 (BUG-percentinformat2).
/// COMMA/DOLLAR grouping (`,` `$` spaces) is stripped while scanning, so those
/// informats get the implied decimal too. A blank or unparseable field → missing.
/// This entry slices the field to `w` (INPUT()-fn semantics — the fn's old
/// numFromSpec did the same); the INPUT STATEMENT routes via readNumericStmt.
pub fn readNumeric(spec_text: []const u8, field: []const u8) Value {
    return readNumericImpl(spec_text, field, true);
}

/// INPUT-statement entry (io.zig readNum): same rules as readNumeric but the
/// field is NOT sliced to `w`. Language Reference: Concepts p.513 "Modified List Input": the colon
/// form tokenizes — SAS reads to a blank column, the defined length of the
/// variable "(character only)", or end of line — so a numeric `:comma5.` on
/// `5,678,999` reads 5678999, not 5678 (qa_tick336_input_fmtnamed_seams S3).
/// Non-colon column reads arrive pre-sliced to w, so skipping the slice is a
/// no-op for them (NOTE-informatlow-tick245 review bounce).
pub fn readNumericStmt(spec_text: []const u8, field: []const u8) Value {
    return readNumericImpl(spec_text, field, false);
}

fn readNumericImpl(spec_text: []const u8, field: []const u8, slice_w: bool) Value {
    var spec = parseSpec(spec_text);
    // Date/time informats (BUG-datetimeinformat): a `:`-delimited datetime, an
    // ISO-8601 datetime, or a bare time → SAS datetime/time seconds. Some names
    // carry digits (E8601DT), which `parseSpec` would cut at the first digit, so
    // match the raw spec text (minus any leading `$`) for those.
    const nm = if (spec_text.len > 0 and spec_text[0] == '$') spec_text[1..] else spec_text;
    if (startsWithCI(nm, "datetime")) return parseDatetime(field, .native);
    if (startsWithCI(nm, "e8601dt") or startsWithCI(nm, "b8601dt")) return parseDatetime(field, .iso);
    if (startsWithCI(nm, "e8601da") or startsWithCI(nm, "b8601da")) { // ISO date yyyy-mm-dd → SAS day (GH#52)
        if (parseIsoDate(field)) |day| return .{ .num = @floatFromInt(day) };
        return Value.missing;
    }
    if (eqi(spec.name, "time") or startsWithCI(nm, "e8601tm") or startsWithCI(nm, "b8601tm")) {
        if (parseTimeSecs(field)) |sc| return .{ .num = sc };
        return Value.missing;
    }
    if (eqi(spec.name, "hhmmss")) { // colon AND digit-packed forms (BUG-hhmmssinformat)
        if (parseHhmmss(field)) |sc| return .{ .num = sc };
        return Value.missing;
    }
    // TODw. informat: time-of-day → SAS time (seconds since midnight). Was in
    // isKnownInformat's whitelist with NO read branch, so `input t tod8.` on
    // '10:30:00' fell through to the plain numeric read and silently returned
    // MISSING while the TOD *format* rendered the same value fine — the two
    // directions of one feature disagreed (BUG-todinformat). Reads like TIMEw.
    // (hh:mm:ss[.frac], hh:mm, hh, AM/PM) PLUS the datetime form: a
    // `ddMMMyyyy:hh:mm:ss` field keeps only its time-of-day, the read twin of
    // renderTod's mod-86400 (that datetime→time-of-day extraction is the whole
    // reason TOD exists next to TIME).
    if (eqi(spec.name, "tod")) {
        const dt = parseDatetime(field, .native);
        if (!dt.isMissing()) return .{ .num = @mod(dt.num, 86400) };
        if (parseTimeSecs(field)) |sc| return .{ .num = sc };
        return Value.missing;
    }
    // MONYY / YYQ date informats (BUG-informatreadloud): month-year → 1st of month,
    // year-quarter → 1st of the quarter. Read-side twins of renderMonyy/renderYyq.
    if (eqi(spec.name, "monyy")) {
        if (parseMonyy(field)) |day| return .{ .num = @floatFromInt(day) };
        return Value.missing;
    }
    if (eqi(spec.name, "yyq") or eqi(spec.name, "yyqc")) {
        if (parseYyq(field)) |day| return .{ .num = @floatFromInt(day) };
        return Value.missing;
    }
    // JULIANw. informat: packed Julian `yyddd` / `yyyyddd` → SAS day. Was in
    // isKnownInformat's whitelist with NO read branch, so the digits fell
    // through to the plain numeric read — `input x julian7.` on '1960011'
    // silently returned 1960011 instead of SAS day 10 (BUG-julianinformat).
    if (eqi(spec.name, "julian")) {
        if (parseJulian(field)) |day| return .{ .num = @floatFromInt(day) };
        return Value.missing;
    }
    // ANYDTDTEw./ANYDTDTMw./ANYDTTMEw. (GAP-anydtinformat, Language Reference: Concepts "ANYDTDTEw.
    // Informat"): the "any date" informats — try the DATE / DDMMYY / MMDDYY /
    // YMD / DATETIME parsers in order, first success wins; unparseable →
    // missing. ANYDTDTM date-only input reads as midnight.
    if (eqi(spec.name, "anydtdte")) {
        if (parseAnyDate(field)) |day| return .{ .num = @floatFromInt(day) };
        return Value.missing;
    }
    if (eqi(spec.name, "anydtdtm")) {
        const nat = parseDatetime(field, .native);
        if (!nat.isMissing()) return nat;
        const iso = parseDatetime(field, .iso);
        if (!iso.isMissing()) return iso;
        if (parseAnyDate(field)) |day| return .{ .num = @floatFromInt(day * 86400) };
        return Value.missing;
    }
    if (eqi(spec.name, "anydttme")) {
        if (parseTimeSecs(field)) |secs| return .{ .num = secs };
        return Value.missing;
    }
    if (Value.parseSpecialMissing(field)) |sm| return sm; // .A–.Z, ._ (ISS-specialmissing)
    // Width beyond the SAS cap fails loud + clamps (BUG-fmtwidthunbounded),
    // like the write side. After the named date/time branches, whose informats
    // carry their own SAS width ranges and never slice by `w`.
    spec.w = checkWidth(spec_text, spec);
    // An unimplemented/unknown informat must FAIL LOUD, not silently read missing
    // (BUG-informatreadloud) — the read-side twin of the write-side unknown-format
    // error. Known numeric informats fall through to the plain numeric parse below.
    if (!isKnownInformat(spec.name)) informatNotFound(spec.name, false);
    // COMMA/DOLLAR-family informats read parentheses as a negative value —
    // `(1,234)` → -1234 (Language Reference: Concepts "Reading Nonstandard Numeric Data": parens require
    // the COMMA informat). PERCENTw.d reads them the same way — `(25%)` → -0.25
    // (BUG-percentinformat2). A plain `w.` informat leaves `(`/`)` in the buffer
    // so parseFloat rejects them (SAS: invalid → missing) — BUG-commaparen.
    // SAS 9.4 has NO NEGPAREN informat (the 108-entry informat dictionary — it is
    // a FORMAT only): accepting it silently read data a typo never asked for, so it
    // was dropped from isKnownInformat above (NOTE-informatlow-tick245 #14, D-002).
    // The statement path now ERRORs at io.zig's whitelist check like SAS 48-59; the
    // INPUT() fn reports informatNotFound. "negparen" stays OUT of commalike too —
    // a format-only name gets no informat parse rules.
    const commalike = eqi(spec.name, "comma") or eqi(spec.name, "dollar") or
        eqi(spec.name, "commax") or eqi(spec.name, "dollarx") or
        eqi(spec.name, "nlnum") or eqi(spec.name, "percent");
    // BUG-commaxinformat: COMMAX/DOLLARX reverse the separator roles — PERIOD
    // is the grouping separator (dropped), COMMA the decimal point (kept as '.').
    // NUMXw.d is the same European convention (BUG-numxinformat).
    const euro = eqi(spec.name, "commax") or eqi(spec.name, "dollarx") or
        eqi(spec.name, "numx");
    // Blank handling is INFORMAT-SPECIFIC (BUG-bzinformat / BUG-numembeddedblank):
    //   BZw.d     — every blank (leading, trailing, EMBEDDED) reads as a ZERO
    //               (`bz4.` on "1   " → 1000, `bz5.` on "  1  " → 100);
    //   plain w.d — leading/trailing blanks trim away, but an EMBEDDED blank is
    //               invalid numeric data → missing + a log NOTE (`4.` on "2 3 " → .);
    //   the COMMA/DOLLAR/PERCENT family keeps the legacy drop-all-blanks (COMMA's
    //   blank-dropping IS documented: "removes embedded … blanks");
    //   Z/BEST/E/D are w.d ALIASES (the w.d informat page names BESTw.d/Dw.d/Ew.d/
    //   Fw.d as aliases) so they follow plain w.d: embedded blank → missing + NOTE
    //   (NOTE-informatlow-tick245 #9) — they used to drop-all-blanks like COMMA.
    const bz = eqi(spec.name, "bz");
    const plain = spec.name.len == 0 or eqi(spec.name, "f") or eqi(spec.name, "z") or
        eqi(spec.name, "best") or eqi(spec.name, "e") or eqi(spec.name, "d");
    // The INPUT() fn reads only the first w bytes of the field (its old
    // numFromSpec did the same). The statement path skips the slice: list/colon
    // reads hand over the WHOLE token (readNumericStmt; Language Reference: Concepts p.513 — the width
    // limit is character-only) and column reads arrive pre-sliced to w.
    const fld = if (slice_w and spec.w > 0 and spec.w < field.len) field[0..spec.w] else field;
    // HEXw. / OCTALw. informats (GAP-hexinformat/octalinformat, Language Reference: Concepts Table 21.2):
    // the digits ARE the integer representation — `hex4.` on "000F" → 15,
    // `octal3.` on "017" → 15. `$HEXw.` (char hex → bytes) is the charInformat
    // path, not here.
    if (!spec.is_char and (eqi(spec.name, "hex") or eqi(spec.name, "octal")))
        return parseBaseInt(fld, if (eqi(spec.name, "octal")) 8 else 16);
    var buf: [128]u8 = undefined;
    var n: usize = 0;
    var had_dot = false;
    var neg = false;
    var blank_tail = false; // plain w.d: a blank followed content — embedded if more content comes
    for (fld) |c| switch (c) {
        ' ', '\t' => if (bz) {
            if (n < buf.len) {
                buf[n] = '0';
                n += 1;
            }
        } else if (plain) {
            if (n > 0) blank_tail = true; // leading blanks (n==0) just drop
        },
        ',' => if (euro) { // European decimal point → keep as '.'
            had_dot = true;
            if (n < buf.len) {
                buf[n] = '.';
                n += 1;
            }
        },
        '$', '%' => {}, // grouping comma / currency / percent: drop
        // COMMAw.d "removes embedded commas, blanks, dollar signs, percent signs,
        // HYPHENS, and close parentheses" (NOTE-informatlow-tick245 #13): an
        // INTERIOR '-' drops (`12-34` → 1234). A LEADING minus (`- 23` → -23) and
        // E-notation's exponent sign (`1E-3`) keep their meaning.
        '-' => if (commalike and n > 0 and buf[n - 1] != 'e' and buf[n - 1] != 'E') {} else if (n < buf.len) {
            if (blank_tail) return invalidNumeric(field);
            buf[n] = c;
            n += 1;
        },
        '(', ')' => if (commalike) {
            neg = true; // parens → negative magnitude
        } else if (n < buf.len) {
            if (blank_tail) return invalidNumeric(field);
            buf[n] = c;
            n += 1;
        },
        '.' => if (!euro) { // euro: period is the grouping separator → drop
            had_dot = true;
            if (n < buf.len) {
                if (blank_tail) return invalidNumeric(field);
                buf[n] = c;
                n += 1;
            }
        },
        else => if (n < buf.len) {
            if (blank_tail) return invalidNumeric(field);
            buf[n] = c;
            n += 1;
        },
    };
    if (n == 0) return Value.missing;
    // sasParseFloat, not bare parseFloat: the w. informat rejects hex/underscore/
    // binary/inf-nan syntaxes Zig accepts (BUG-charnum-parsefloat).
    var x = pdv.sasParseFloat(buf[0..n]) orelse return Value.missing;
    if (!std.math.isFinite(x)) return Value.missing; // overflow (e.g. 1e400) → missing, like numFromSpec
    if (neg) x = -x;
    if (eqi(spec.name, "percent")) return .{ .num = x / 100.0 };
    // implied decimal: only when the field itself carried no `.`
    if (spec.d > 0 and !had_dot) return .{ .num = x / pow10f(@intCast(spec.d)) };
    return .{ .num = x };
}

/// HEXw./OCTALw. read helper: base-16/base-8 digits → integer value (the common
/// integer form). Blank, a non-digit for the base, or >u64 overflow → missing.
// ponytail: no HEX16. raw-IEEE-double read; add if a program feeds 16-digit doubles.
fn parseBaseInt(field: []const u8, base: u8) Value {
    const s = std.mem.trim(u8, field, " \t");
    if (s.len == 0) return Value.missing;
    const v = std.fmt.parseInt(u64, s, base) catch return Value.missing;
    return .{ .num = @floatFromInt(v) };
}

/// Post-read transform for a named `$` (char) informat, applied after the field
/// is width-clipped. Shared by the INPUT() function (functions.zig) and the
/// INPUT statement (io.zig) so both paths agree:
///   $UPCASE / $LOWCASE — case-fold
///   $QUOTE            — strip ONE matched pair of surrounding " or ' quotes
///   $HEX              — decode hex-digit pairs to bytes ("414243" → "ABC")
/// Any other name (or none) reads verbatim — but an UNRECOGNIZED name first
/// fails loud (BUG-charinformatloud, D-002; the char twin of the numeric
/// BUG-informatreadloud path): SAS errors on an unknown informat, a verbatim
/// read of `$bogus.` is a false green. `nm` is the informat name only
/// (see the callers' `informatName`).
pub fn charInformat(arena: std.mem.Allocator, nm: []const u8, field: []const u8) Error![]const u8 {
    if (eqi(nm, "upcase")) return std.ascii.allocUpperString(arena, field);
    if (eqi(nm, "lowcase")) return std.ascii.allocLowerString(arena, field);
    if (eqi(nm, "quote")) {
        if (field.len >= 2 and (field[0] == '"' or field[0] == '\'') and field[field.len - 1] == field[0])
            return field[1 .. field.len - 1];
        return field;
    }
    if (eqi(nm, "hex")) {
        // A trailing odd nibble is the high nibble of a final byte (low bits 0),
        // matching SAS; a non-hex byte ends the decode.
        const out = try arena.alloc(u8, (field.len + 1) / 2);
        var oi: usize = 0;
        var i: usize = 0;
        while (i < field.len) : (i += 2) {
            const hi = std.fmt.charToDigit(field[i], 16) catch break;
            const lo: u8 = if (i + 1 < field.len) (std.fmt.charToDigit(field[i + 1], 16) catch 0) else 0;
            out[oi] = (hi << 4) | lo;
            oi += 1;
        }
        return out[0..oi];
    }
    // BUG-charinformatloud: unknown/unimplemented char informat — FAIL LOUD,
    // then keep the verbatim field as the fallback so the rest of the output
    // survives (the loud-then-fallback shape of the numeric read side).
    checkCharInformat(nm);
    return field;
}

/// CHAR informat names the read paths implement — plain `$w.` (no name),
/// $CHAR, $UPCASE/$LOWCASE, $QUOTE, $HEX, $VARYING (io.zig's length-variable
/// read). Anything else is unimplemented/a typo → fail loud
/// (BUG-charinformatloud). The char twin of isKnownInformat.
pub fn isKnownCharInformat(name: []const u8) bool {
    if (name.len == 0) return true; // plain $w.
    const known = [_][]const u8{ "char", "upcase", "lowcase", "quote", "hex", "varying" };
    for (known) |k| if (eqi(name, k)) return true;
    return false;
}

/// BUG-charinformatloud: char-read paths that don't route through charInformat
/// (io.zig's column/list reads) fail loud on an unknown $-informat too —
/// same error path/message as the numeric side (informatNotFound).
pub fn checkCharInformat(name: []const u8) void {
    if (!isKnownCharInformat(name)) informatNotFound(name, true);
}

const DtStyle = enum { native, iso };

/// Parse a datetime informat field → SAS datetime (seconds since 1960-01-01
/// 00:00:00) = SAS-day × 86400 + seconds-of-day. `native` (DATETIMEw.):
/// `ddMMMyyyy:hh:mm:ss` (date, then a `:`, then the time). `iso` (E8601DT.):
/// `yyyy-mm-ddThh:mm:ss`. A missing time defaults to 00:00:00; unparseable →
/// missing. Reuses the same civil-day math as the DATE informats.
fn parseDatetime(field: []const u8, style: DtStyle) Value {
    const s = std.mem.trim(u8, field, " ");
    const sep = switch (style) {
        .native => std.mem.indexOfScalar(u8, s, ':') orelse return Value.missing,
        .iso => std.mem.indexOfAny(u8, s, "Tt") orelse return Value.missing,
    };
    const day = (switch (style) {
        .native => parseDDMMMYYYY(s[0..sep]),
        .iso => parseIsoDate(s[0..sep]),
    }) orelse return Value.missing;
    const secs = parseTimeSecs(s[sep + 1 ..]) orelse 0;
    return .{ .num = @as(f64, @floatFromInt(day * 86400)) + secs };
}

/// SAS day for y/m/d, or null if the day-of-month is invalid for that month —
/// e.g. `31FEB2020` must NOT roll over to 02Mar (BUG-infdate-stmt). Mirrors the
/// INPUT-function validation by round-tripping through civilFromDays.
pub fn sasDayChecked(y: i64, m: i64, d: i64) ?i64 {
    const civ = daysFromCivil(y, m, d); // days since 1970-01-01
    const c = civilFromDays(civ);
    if (c.y != y or @as(i64, c.m) != m or @as(i64, c.d) != d) return null;
    return civ + sas_epoch_days;
}

/// `ddMMMyyyy` (e.g. `25DEC2024`) → SAS day number, or null. The day is 1–2
/// digits (BUG-datesingledigitday: a hardcoded 2-char day slice rejected
/// `1MAR90` — Language Reference: Concepts Table 21.2's own example — while the date literal and
/// MMDDYY accepted the class; a silently-missing date).
pub fn parseDDMMMYYYY(s0: []const u8) ?i64 {
    const s = std.mem.trim(u8, s0, " ");
    var nd: usize = 0;
    while (nd < s.len and nd < 2 and std.ascii.isDigit(s[nd])) nd += 1;
    if (nd == 0 or s.len < nd + 5) return null; // day + MMM + ≥2-digit year
    const day = std.fmt.parseInt(i64, s[0..nd], 10) catch return null;
    const mon = monthAbbr(s[nd .. nd + 3]) orelse return null;
    const year = expandYear(std.fmt.parseInt(i64, s[nd + 3 ..], 10) catch return null); // 2-digit → YEARCUTOFF
    return sasDayChecked(year, mon, day);
}

/// ANYDTDTEw. helper: try the DATE parser (`15JAN2020`), then a DDMMYY and an
/// MMDDYY numeric triplet (`15/01/2020`, `01/15/2020`), then the YMD ISO parser
/// (`2020-01-15`, `20200115`) — first success wins, null if none parse.
/// (GAP-anydtinformat)
fn parseAnyDate(field: []const u8) ?i64 {
    if (parseDDMMMYYYY(field)) |d| return d;
    if (parseDateParts(field, true)) |d| return d; // DDMMYY
    if (parseDateParts(field, false)) |d| return d; // MMDDYY
    if (parseIsoDate(field)) |d| return d; // YMD
    return null;
}

/// A numeric date triplet `a<sep>b<sep>y` (separators `/`, `-`, `.`, space) →
/// SAS day. `dmy` reads `a` as the day, else `a` is the month. Exactly three
/// parts; a 2-digit year expands via YEARCUTOFF; a rolled-over/impossible day
/// is null (sasDayChecked), which is also how an ambiguous triplet falls
/// through to the next parser (`01/15/2020` fails DMY, reads as MDY).
fn parseDateParts(field: []const u8, dmy: bool) ?i64 {
    const s = std.mem.trim(u8, field, " ");
    var it = std.mem.tokenizeAny(u8, s, "/-. :");
    const a = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const b = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const y = expandYear(std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null);
    if (it.next() != null) return null; // exactly three parts
    const d = if (dmy) a else b;
    const m = if (dmy) b else a;
    if (m < 1 or m > 12 or d < 1 or d > 31) return null;
    return sasDayChecked(y, m, d);
}

/// MONYYw. informat: `MONyyyy` / `MONyy` (e.g. `MAR2020`, `MAR20`), optional
/// separator between the 3-letter month and the year → SAS day of the 1st of that
/// month (Language Reference: Concepts "MONYYw. Informat"). null if unparseable.
fn parseMonyy(field: []const u8) ?i64 {
    const s = std.mem.trim(u8, field, " ");
    if (s.len < 5) return null; // MON + 2-digit year minimum
    const mon = monthAbbr(s[0..3]) orelse return null;
    var ys = s[3..];
    if (ys.len > 0 and !std.ascii.isDigit(ys[0])) ys = ys[1..]; // MON-YYYY separator
    ys = std.mem.trim(u8, ys, " ");
    const year = expandYear(std.fmt.parseInt(i64, ys, 10) catch return null);
    return sasDayChecked(year, mon, 1);
}

/// YYQw. informat: `yyyyQq` / `yyQq` / `yyyy:q` etc. (e.g. `2020Q2`, `2020:2`) →
/// SAS day of the 1st of the quarter's first month (Q1→Jan, Q2→Apr, Q3→Jul,
/// Q4→Oct) (Language Reference: Concepts "YYQw. Informat"). null if unparseable.
fn parseYyq(field: []const u8) ?i64 {
    const s = std.mem.trim(u8, field, " ");
    var i: usize = 0;
    while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
    if (i == 0 or i >= s.len) return null; // need a year then a separator/quarter
    const year = expandYear(std.fmt.parseInt(i64, s[0..i], 10) catch return null);
    var qs = s[i..];
    if (qs.len > 0 and !std.ascii.isDigit(qs[0])) qs = qs[1..]; // skip Q / : / -
    qs = std.mem.trim(u8, qs, " ");
    const q = std.fmt.parseInt(i64, qs, 10) catch return null;
    if (q < 1 or q > 4) return null;
    return sasDayChecked(year, (q - 1) * 3 + 1, 1);
}

/// JULIANw. informat: packed Julian date `yyddd` / `yyyyddd` (e.g. `60011` /
/// `1960011` → 1960 day 11 = SAS day 10) (Language Reference: Concepts "JULIANw. Informat"). 2-digit
/// year → YEARCUTOFF via expandYear; day-of-year must fit the year (366 only in
/// leap years). null if unparseable.
fn parseJulian(field: []const u8) ?i64 {
    const s = std.mem.trim(u8, field, " ");
    if (std.mem.indexOfNone(u8, s, "0123456789") != null) return null;
    const split: usize = switch (s.len) {
        5 => 2,
        7 => 4,
        else => return null,
    };
    const year = expandYear(std.fmt.parseInt(i64, s[0..split], 10) catch return null);
    const doy = std.fmt.parseInt(i64, s[split..], 10) catch return null;
    const leap = @rem(year, 4) == 0 and (@rem(year, 100) != 0 or @rem(year, 400) == 0);
    if (doy < 1 or doy > (if (leap) @as(i64, 366) else 365)) return null;
    const jan1 = sasDayChecked(year, 1, 1) orelse return null;
    return jan1 + doy - 1;
}

/// `yyyy-mm-dd` (or `yyyy/mm/dd`) or the packed basic form `yyyymmdd` (8 digits,
/// no separators, e.g. B8601DA) → SAS day number, or null. Both the INPUT
/// statement (readNumeric) and the INPUT() function route here, so both read the
/// packed form (E8601DA-packed-input).
/// ponytail: packed DATE only. A packed datetime keeps its `T` (`yyyymmddThhmmss`),
/// so parseDatetime still splits it and the date part lands here; a fully-packed
/// `yyyymmddhhmmss` (no T) is out of scope — add a length split in parseDatetime
/// if a fixture ever needs it.
fn parseIsoDate(s0: []const u8) ?i64 {
    const s = std.mem.trim(u8, s0, " ");
    if (s.len == 8 and std.mem.indexOfNone(u8, s, "0123456789") == null) {
        return sasDayChecked(
            expandYear(std.fmt.parseInt(i64, s[0..4], 10) catch return null),
            std.fmt.parseInt(i64, s[4..6], 10) catch return null,
            std.fmt.parseInt(i64, s[6..8], 10) catch return null,
        );
    }
    var it = std.mem.tokenizeAny(u8, s, "-/");
    const y = expandYear(std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null);
    const m = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    const d = std.fmt.parseInt(i64, it.next() orelse return null, 10) catch return null;
    if (m < 1 or m > 12 or d < 1 or d > 31) return null;
    return sasDayChecked(y, m, d);
}

// ── PROC IMPORT EFI date/time guessing (GAP-importtypes) ─────────────────────
// Base SAS 9.4 Procedures Guide, PROC IMPORT chapter, printed p. 1330 (pdf
// 1379): "All values are read in as character strings. If a Date and Time
// format or a numeric informat can be applied to the data value, the type is
// declared as numeric. Otherwise, the type remains character." The attached
// format FAMILY matches the recognised pattern — worked Example 1, printed
// p. 1340-41: `JAN2001` → informat+format MONYY7. DATEw. is recognised
// (`10MAY14` "becomes 10MAY14, which is a date value", p. 1326) and datetimes
// too (`06JAN2016:10:04:26` — "SAS might try to read it as a date", p. 1324);
// TIMEw. has no worked example — recognised under the same p. 1330 "Date and
// Time format" category rule. DOC-SILENT patterns stay character: mm/dd vs
// dd/mm slash dates (ambiguous order — the chapter never says which wins),
// ISO-8601 `T` datetimes, packed 8-digit dates (`20240305` — a plain number to
// EFI before any date informat is tried), and separator variants beyond the
// documented contiguous forms.
pub const ImportDateKind = enum { yymmdd, date, monyy, datetime, time };
pub const ImportDate = struct { kind: ImportDateKind, value: f64 };

/// EFI guess for ONE delimited field: the recognised pattern + its SAS numeric
/// value, or null when the field fits none of them (the caller keeps a
/// mixed/non-date column character). STRICT shapes — the INPUT-statement
/// parsers underneath are lenient by design (packed forms, period times, a
/// missing time defaulting to midnight); import guessing must not inherit that
/// leniency: a wrongly-detected date converts a readable string into a number
/// nobody can check by eye.
pub fn importDateGuess(field: []const u8) ?ImportDate {
    const f = std.mem.trim(u8, field, " ");
    if (f.len == 0) return null;
    // ISO date `yyyy-mm-dd` / `yyyy/mm/dd` — 4-digit year first (unambiguous
    // YMD order); parseIsoDate's packed 8-digit form is excluded (EFI reads
    // that as a plain number, never a date).
    if (f.len >= 8 and f.len <= 10 and std.mem.indexOfAny(u8, f, "-/") != null and allDigits(f[0..4])) {
        if (parseIsoDate(f)) |day| return .{ .kind = .yymmdd, .value = @floatFromInt(day) };
    }
    if (std.mem.indexOfScalar(u8, f, ':')) |colon| {
        // datetime `ddMONyy[yy]:hh:mm[:ss]` — BOTH sides strict: parseDatetime
        // alone would default a garbage time part to midnight.
        if (parseDDMMMYYYY(f[0..colon])) |day| {
            if (strictTime(f[colon + 1 ..])) |secs|
                return .{ .kind = .datetime, .value = @as(f64, @floatFromInt(day * 86400)) + secs };
        }
        // bare time `hh:mm[:ss]` (p. 1330 category rule — no worked example).
        if (strictTime(f)) |secs| return .{ .kind = .time, .value = secs };
        return null; // has a ':' but fits no date/time shape → character
    }
    // DATEw. `ddMONyy[yy]` — 1-2-digit day, contiguous (`10MAY14`, `05MAR2024`).
    if (parseDDMMMYYYY(f)) |day| return .{ .kind = .date, .value = @floatFromInt(day) };
    // MONYYw. `MONyy` / `MONyyyy` — contiguous, like the p. 1341 `JAN2001`
    // example; separator variants (`MAR-2020`) are DOC-SILENT → character.
    if ((f.len == 5 or f.len == 7) and allDigits(f[3..])) {
        if (parseMonyy(f)) |day| return .{ .kind = .monyy, .value = @floatFromInt(day) };
    }
    return null;
}

/// The attached-format NAME for an EFI-detected column; the width is the
/// caller's (the column's widest value, as EFI's $w./MONYY7. behave).
pub fn importDateFormatName(kind: ImportDateKind) []const u8 {
    return switch (kind) {
        .yymmdd => "YYMMDD",
        .date => "DATE",
        .monyy => "MONYY",
        .datetime => "DATETIME",
        .time => "TIME",
    };
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |c| if (!std.ascii.isDigit(c)) return false;
    return true;
}

/// Strict `hh:mm[:ss[.frac]]` (+ optional AM/PM) for import guessing: minutes
/// REQUIRED (a bare `10` is a number, never a time), fields in range —
/// parseTimeSecs itself accepts `10:99` and the period form `12.56`, both too
/// lenient here. Returns parseTimeSecs' value (AM/PM/fraction semantics kept).
fn strictTime(s0: []const u8) ?f64 {
    var s = std.mem.trim(u8, s0, " ");
    if (s.len > 2) {
        const tail = s[s.len - 2 ..];
        if (eqi(tail, "am") or eqi(tail, "pm")) s = std.mem.trimEnd(u8, s[0 .. s.len - 2], " ");
    }
    var it = std.mem.tokenizeScalar(u8, s, ':');
    const h = std.fmt.parseInt(u8, it.next() orelse return null, 10) catch return null;
    const m = std.fmt.parseInt(u8, it.next() orelse return null, 10) catch return null; // minutes required
    var sec: f64 = 0;
    if (it.next()) |t3| sec = std.fmt.parseFloat(f64, t3) catch return null;
    if (it.next() != null) return null; // at most hh:mm:ss
    if (h > 23 or m > 59 or sec >= 60) return null;
    return parseTimeSecs(s0); // non-null given the shape checked above
}

/// `hh:mm[:ss[.frac]]` (or the period-separated `hh.mm` form) with an optional
/// AM/PM suffix → seconds since midnight, keeping any sub-second fraction; null
/// if unparseable. TIMEw. informat rules (BUG-timeinformat): `:` or `.` separate
/// the fields (`12.56` → 12:56 = 46560), `PM` adds 12h except at 12 (12 PM =
/// noon = 43200), and 12 AM is hour 0. Shared by the INPUT statement (io.zig)
/// and the INPUT() function / readNumeric paths.
pub fn parseTimeSecs(s0: []const u8) ?f64 {
    var s = std.mem.trim(u8, s0, " ");
    if (s.len == 0) return null;
    var pm: ?bool = null; // true = PM suffix
    if (s.len > 2) {
        const tail = s[s.len - 2 ..];
        if (eqi(tail, "am") or eqi(tail, "pm")) {
            pm = eqi(tail, "pm");
            s = std.mem.trimEnd(u8, s[0 .. s.len - 2], " ");
        }
    }
    var h: f64 = 0;
    var m: f64 = 0;
    var sec: f64 = 0;
    var it = std.mem.tokenizeScalar(u8, s, ':');
    const t1 = it.next() orelse return null;
    if (it.next()) |t2| {
        h = std.fmt.parseFloat(f64, t1) catch return null;
        m = std.fmt.parseFloat(f64, t2) catch return null;
        if (it.next()) |t3| sec = std.fmt.parseFloat(f64, t3) catch return null;
    } else if (std.mem.indexOfScalar(u8, t1, '.')) |dot| { // `hh.mm` — period separator
        h = std.fmt.parseFloat(f64, t1[0..dot]) catch return null;
        m = std.fmt.parseFloat(f64, t1[dot + 1 ..]) catch return null;
    } else {
        h = std.fmt.parseFloat(f64, t1) catch return null;
    }
    if (pm) |is_pm| {
        if (is_pm) {
            if (h < 12) h += 12;
        } else if (h == 12) h = 0;
    }
    return h * 3600 + m * 60 + sec;
}

/// HHMMSSw. informat (BUG-hhmmssinformat): the `hh:mm:ss` colon form, OR
/// digit-packed `hhmmss`; a short packed field is LEFT-padded with zeros
/// (`124` → 012400 → 1:24:00 = 5040) and fractional seconds are ignored.
pub fn parseHhmmss(field: []const u8) ?f64 {
    const s = std.mem.trim(u8, field, " ");
    if (s.len == 0) return null;
    if (std.mem.indexOfScalar(u8, s, ':') != null) {
        const secs = parseTimeSecs(s) orelse return null;
        return @floor(secs); // HHMMSS ignores the fraction
    }
    if (s.len > 6) return null;
    for (s) |c| if (!std.ascii.isDigit(c)) return null;
    // SAS pads a short packed field on the LEFT to an even digit count, then on
    // the RIGHT to 6: "124" → "0124" → "012400" → 1:24:00 (HHMMSSw. doc).
    var buf = [_]u8{'0'} ** 6;
    const off: usize = s.len & 1;
    @memcpy(buf[off .. off + s.len], s);
    const h = std.fmt.parseInt(i64, buf[0..2], 10) catch unreachable; // digits only
    const m = std.fmt.parseInt(i64, buf[2..4], 10) catch unreachable;
    const sec = std.fmt.parseInt(i64, buf[4..6], 10) catch unreachable;
    return @floatFromInt(h * 3600 + m * 60 + sec);
}

fn monthAbbr(abbr: []const u8) ?i64 {
    for (months, 0..) |mn, i| if (eqi(abbr, mn)) return @intCast(i + 1);
    return null;
}

fn startsWithCI(s: []const u8, prefix: []const u8) bool {
    return s.len >= prefix.len and eqi(s[0..prefix.len], prefix);
}

const sas_epoch_days: i64 = 3653; // 1970-01-01 is SAS day 3653

/// Days from 1970-01-01 for a proleptic-Gregorian date (Hinnant; the inverse of
/// `civilFromDays`). SAS day = this + `sas_epoch_days`.
fn daysFromCivil(y_in: i64, m: i64, d: i64) i64 {
    const y = if (m <= 2) y_in - 1 else y_in;
    const era = @divFloor(if (y >= 0) y else y - 399, 400);
    const yoe = y - era * 400;
    const mp = if (m > 2) m - 3 else m + 9;
    const doy = @divTrunc(153 * mp + 2, 5) + d - 1;
    const doe = yoe * 365 + @divTrunc(yoe, 4) - @divTrunc(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

/// Render `v` per `spec_text` into an arena-owned string.
/// BUG-unknownfmtsilent: applying an unrecognized/unsupported format is a SAS
/// ERROR ("format not found") unless `options nofmterr`. We print the error and
/// set a flag the main loop turns into a non-zero exit, then still render a plain
/// fallback so the rest of the output survives. `options nofmterr` sets g_nofmterr.
var g_nofmterr: bool = false;
// pub so cross-file fail-loud tests (functions.zig readInformat routing) can
// save/reset the flag per D-003, like g_test_last_err/g_test_last_note below.
pub var g_fmt_error: bool = false;
/// TEST-quietnoise: in a test build the "format not found" message is captured here
/// (for the test to assert on) instead of going to stderr; the CLI still prints it.
var g_test_err_buf: [256]u8 = undefined;
pub var g_test_last_err: []const u8 = "";
pub fn setNoFmtErr(v: bool) void {
    g_nofmterr = v;
}
pub fn nofmterr() bool {
    return g_nofmterr;
}
pub fn formatErrored() bool {
    return g_fmt_error;
}
/// D-009 §5f — the documented-name lists that SPLIT the unknown-format and
/// unknown-informat catch-alls below (GAP-gapsexitingone, format slice). A name
/// reaching reportUnknownFormat/informatNotFound is either a real SAS 9.4
/// format opensas does not implement (gap → rc 2, "file an opensas issue") or
/// not a SAS format at all (typo → rc 1, "fix your SAS"). The SAS 9.4 Formats
/// and Informats: Reference closes the valid set in ONE place — the tick397j
/// predictor's best case — so these lists are its dictionary RE-DERIVED IN
/// FULL (D-018, never assembled from memory): every `^NAMEw[.d] Format$` /
/// `^NAMEw[.d] Informat$` heading in the Formats and Informats reference,
/// with the x-metavariable families expanded to each entry's OWN syntax-table
/// letters (MMDDYYxw. p.243 / DDMMYYxw. p.182 / YYMMDDxw. p.514 take
/// B/C/D/N/P/S; YYMMxw. p.516 / MMYYxw. p.249 / YYQxw. p.521 / YYQRxw. p.525
/// take C/D/N/P/S — no B). doc_inf_num also carries the nine informats the
/// volume names only by See-Also cross-reference into the NLS Reference Guide
/// (EURO/EUROX pp.215/218, NENGO p.257, NLMNY/NLMNYI pp.408/410,
/// NLNUM/NLNUMI pp.412/413, NLPCT/NLPCTI pp.415/417) — D-018's TEMP/DDE
/// shape: real, documented in a volume this repo does not carry. Char-ness is
/// part of the name: real SAS scopes format lookup by type, so `$date9.` is
/// "format $DATE not found" (user error) even though DATEw. exists — the char
/// and numeric sets are separate lists. Self-maintaining: reaching a
/// catch-all already means unimplemented, so implementing a format later
/// needs no list edit here.
const doc_fmt_num = [_][]const u8{
    "b8601da", "b8601dn", "b8601dt", "b8601dx", "b8601dz", "b8601lx", "b8601lz", "b8601tm", "b8601tx",
    "b8601tz", "best", "bestd", "binary", "comma", "commax", "d", "date", "dateampm", "datetime", "day",
    "ddmmyy", "ddmmyyb", "ddmmyyc", "ddmmyyd", "ddmmyyn", "ddmmyyp", "ddmmyys", "dollar", "dollarx",
    "downame", "dtdate", "dtmonyy", "dtwkdatx", "dtyear", "dtyyqc", "e", "e8601da", "e8601dn", "e8601dt",
    "e8601dx", "e8601dz", "e8601lx", "e8601lz", "e8601tm", "e8601tx", "e8601tz", "euro", "eurox", "f",
    "float", "fract", "hex", "hhmm", "hour", "ib", "ibr", "ieee", "julday", "julian", "mdyampm", "mmddyy",
    "mmddyyb", "mmddyyc", "mmddyyd", "mmddyyn", "mmddyyp", "mmddyys", "mmss", "mmyy", "mmyyc", "mmyyd",
    "mmyyn", "mmyyp", "mmyys", "monname", "month", "monyy", "negparen", "nengo", "nlbest", "nldate",
    "nldatel", "nldatem", "nldatemd", "nldatemdl", "nldatemdm", "nldatemds", "nldatemn", "nldates",
    "nldatew", "nldatewn", "nldateym", "nldateyml", "nldateymm", "nldateyms", "nldateyq", "nldateyql",
    "nldateyqm", "nldateyqs", "nldateyr", "nldateyw", "nldatm", "nldatmap", "nldatmdt", "nldatml",
    "nldatmm", "nldatmmd", "nldatmmdl", "nldatmmdm", "nldatmmds", "nldatmmn", "nldatms", "nldatmtm",
    "nldatmtz", "nldatmw", "nldatmwn", "nldatmwz", "nldatmym", "nldatmyml", "nldatmymm", "nldatmyms",
    "nldatmyq", "nldatmyql", "nldatmyqm", "nldatmyqs", "nldatmyr", "nldatmyw", "nldatmz", "nlmniaed",
    "nlmniaud", "nlmnibgn", "nlmnibrl", "nlmnicad", "nlmnichf", "nlmnicny", "nlmniczk", "nlmnidkk",
    "nlmnieek", "nlmniegp", "nlmnieur", "nlmnigbp", "nlmnihkd", "nlmnihrk", "nlmnihuf", "nlmniidr",
    "nlmniils", "nlmniinr", "nlmnijpy", "nlmnikrw", "nlmniltl", "nlmnilvl", "nlmnimop", "nlmnimxn",
    "nlmnimyr", "nlmninok", "nlmninzd", "nlmnipln", "nlmnirub", "nlmnisek", "nlmnisgd", "nlmnithb",
    "nlmnitry", "nlmnitwd", "nlmniusd", "nlmnizar", "nlmnlaed", "nlmnlaud", "nlmnlbgn", "nlmnlbrl",
    "nlmnlcad", "nlmnlchf", "nlmnlcny", "nlmnlczk", "nlmnldkk", "nlmnleek", "nlmnlegp", "nlmnleur",
    "nlmnlgbp", "nlmnlhkd", "nlmnlhrk", "nlmnlhuf", "nlmnlidr", "nlmnlils", "nlmnlinr", "nlmnljpy",
    "nlmnlkrw", "nlmnlltl", "nlmnllvl", "nlmnlmop", "nlmnlmxn", "nlmnlmyr", "nlmnlnok", "nlmnlnzd",
    "nlmnlpln", "nlmnlrub", "nlmnlsek", "nlmnlsgd", "nlmnlthb", "nlmnltry", "nlmnltwd", "nlmnlusd",
    "nlmnlzar", "nlmny", "nlmnyi", "nlnum", "nlnumi", "nlpct", "nlpcti", "nlpctn", "nlpctp", "nlpvalue",
    "nlstrmon", "nlstrqtr", "nlstrwk", "nltimap", "nltime", "numx", "octal", "oddsr", "pd", "pdjulg",
    "pdjuli", "percent", "percentn", "pib", "pibr", "pk", "pvalue", "qtr", "qtrr", "rb", "roman", "s370ff",
    "s370fib", "s370fibu", "s370fpd", "s370fpdu", "s370fpib", "s370frb", "s370fzd", "s370fzdl", "s370fzds",
    "s370fzdt", "s370fzdu", "sizek", "ssn", "time", "timeampm", "tod", "vaxrb", "vmszn", "weekdate",
    "weekdatx", "weekday", "weeku", "weekv", "weekw", "worddate", "worddatx", "wordf", "words", "year",
    "yymm", "yymmc", "yymmd", "yymmdd", "yymmddb", "yymmddc", "yymmddd", "yymmddn", "yymmddp", "yymmdds",
    "yymmn", "yymmp", "yymms", "yymon", "yyq", "yyqc", "yyqd", "yyqn", "yyqp", "yyqr", "yyqrc", "yyqrd",
    "yyqrn", "yyqrp", "yyqrs", "yyqs", "yyqz", "yyweeku", "yyweekv", "yyweekw", "z", "zd",
};

const doc_fmt_char = [_][]const u8{
    "ascii", "base64x", "binary", "char", "cstr", "ebcdic", "hex", "msgcase", "n8601b", "n8601ba",
    "n8601e", "n8601ea", "n8601eh", "n8601ex", "n8601h", "n8601x", "octal", "quote", "reverj", "revers",
    "upcase", "uuid", "varying",
};

const doc_inf_num = [_][]const u8{
    "anydtdte", "anydtdtm", "anydttme", "b8601ci", "b8601da", "b8601dj", "b8601dn", "b8601dt", "b8601dx",
    "b8601dz", "b8601lx", "b8601tm", "b8601tx", "b8601tz", "binary", "bits", "bz", "cb", "comma", "commax",
    "date", "datetime", "ddmmyy", "e8601da", "e8601dn", "e8601dt", "e8601dx", "e8601dz", "e8601lx",
    "e8601lz", "e8601tm", "e8601tx", "e8601tz", "euro", "eurox", "float", "hex", "hhmmss", "ib", "ibr",
    "ieee", "julian", "mdyampm", "mmddyy", "monyy", "msec", "nengo", "nlmny", "nlmnyi", "nlnum", "nlnumi",
    "nlpct", "nlpcti", "numx", "octal", "pd", "pdjulg", "pdjuli", "pdtime", "percent", "pib", "pibr", "pk",
    "punch", "rb", "rmfdur", "rmfstamp", "row", "s370ff", "s370fib", "s370fibu", "s370fpd", "s370fpdu",
    "s370fpib", "s370frb", "s370fzd", "s370fzdb", "s370fzdl", "s370fzds", "s370fzdt", "s370fzdu",
    "shrstamp", "smfstamp", "stimer", "time", "todstamp", "trailsgn", "tu", "vaxrb", "vmszn", "weeku",
    "weekv", "weekw", "ymddttm", "yymmdd", "yymmn", "yyq", "zd", "zdb", "zdv",
};

const doc_inf_char = [_][]const u8{
    "ascii", "base64x", "binary", "cb", "char", "charzb", "ebcdic", "hex", "n8601b", "n8601e", "octal",
    "phex", "quote", "upcase", "uuid", "varying",
};

fn inDocList(list: []const []const u8, name: []const u8) bool {
    for (list) |k| if (eqi(name, k)) return true;
    return false;
}

/// Is `name` a SAS 9.4 FORMAT the reference's dictionary names (write side)?
/// `is_char` selects the $-prefixed half of the dictionary.
pub fn isDocumentedFormat(name: []const u8, is_char: bool) bool {
    return inDocList(if (is_char) &doc_fmt_char else &doc_fmt_num, name);
}

/// Is `name` a SAS 9.4 INFORMAT the reference names (read side) — the local
/// dictionary plus the See-Also-named NLS-guide informats?
pub fn isDocumentedInformat(name: []const u8, is_char: bool) bool {
    return inDocList(if (is_char) &doc_inf_char else &doc_inf_num, name);
}

/// Fail loud on an unrecognized/unsupported format `name` (BUG-unknownfmtsilent,
/// BUG-charfmtsink). Shared by the numeric tail and the `$`-char branch so both
/// paths report identically; the caller still renders a plain fallback afterwards.
/// D-009 §5f: a name the 9.4 dictionary NAMES is an opensas gap (markGap → rc 2);
/// anything else is the user's typo and stays rc 1 — same message either way.
fn reportUnknownFormat(name: []const u8, is_char: bool) void {
    if (g_nofmterr) return;
    if (isDocumentedFormat(name, is_char)) diag.markGap();
    g_fmt_error = true;
    // TEST-quietnoise: capture in a test build so the green gate stays clean;
    // the CLI still prints ERROR: to stderr (fail-loud unchanged).
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, "The format {s} was not found or could not be loaded.", .{name}) catch "format-not-found";
    } else {
        std.debug.print("ERROR: The format {s} was not found or could not be loaded.\n", .{name});
    }
}

/// BUG-charfmtonnum: a `$` (character) format applied to a NUMERIC value — SAS
/// 9.4 is a compile-time error (a character format cannot be used with a
/// numeric variable); we silently coerced the number to text (D-002). Same
/// loud-then-fallback shape (and TEST-quietnoise capture) as
/// reportUnknownFormat; the caller still renders the raw value afterwards.
fn reportCharFmtOnNumeric(spec_text: []const u8) void {
    if (g_nofmterr) return;
    g_fmt_error = true;
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, "The character format {s} cannot be used with a numeric value.", .{spec_text}) catch "char-fmt-on-numeric";
    } else {
        std.debug.print("ERROR: The character format {s} cannot be used with a numeric value.\n", .{spec_text});
    }
}

/// Effective character-ness of a format spec for the STATEMENT-level type
/// checks (NOTE-fmtnumoncharcoerce: exec.declareStmt, PROC PRINT/DATASETS,
/// groupFormats): a leading `$`, or a char-typed user format referenced
/// $-lessly — SAS resolves those by name + value type (QA-charfmtnodollar),
/// so on a char variable they are NOT a mismatch.
pub fn specIsChar(spec_text: []const u8) bool {
    const spec = parseSpec(spec_text);
    if (spec.is_char) return true;
    if (spec.name.len == 0) return false;
    for (user_catalog) |uf| if (uf.is_char and eqi(uf.name, spec.name)) return true;
    return false;
}

/// NOTE-fmtnumoncharcoerce: the mirror of BUG-charfmtonnum — a numeric format
/// applied to a CHARACTER value. SAS rejects the ASSOCIATION at compile time
/// (Formats & Informats Ref printed p.7: the FORMAT statement associates char
/// vars with char formats and numeric vars with numeric formats; p.5: an
/// incompatible format falls back to an analogous format of the other type or
/// ERRORs — never a silent coerce). The FORMAT/ATTRIB statement surfaces now
/// check at compile time (exec.declareStmt, PROC PRINT/DATASETS, groupFormats);
/// a value that still reaches here (a stale descriptor, a PUT/put() spec) used
/// to be parsed as a number — 'abc' → missing → '.' — DESTROYING the cell with
/// exit 0. Same loud-then-fallback shape as reportCharFmtOnNumeric: the caller
/// renders the raw text afterwards.
fn reportNumFmtOnChar(spec_text: []const u8) void {
    if (g_nofmterr) return;
    g_fmt_error = true;
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, "The numeric format {s} cannot be used with a character value.", .{spec_text}) catch "num-fmt-on-char";
    } else {
        std.debug.print("ERROR: The numeric format {s} cannot be used with a character value.\n", .{spec_text});
    }
}

/// A nested-format label chain (`=[fmtname]`) looped back on itself — SAS:
/// "ERROR: Format reference is circular". Same loud-then-fallback pattern (and
/// TEST-quietnoise capture) as reportUnknownFormat.
fn reportCircularFormat(name: []const u8) void {
    if (g_nofmterr) return;
    g_fmt_error = true;
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, "Format reference is circular: {s}.", .{name}) catch "circular-format";
    } else {
        std.debug.print("ERROR: Format reference is circular: {s}.\n", .{name});
    }
}

/// Numeric format names the plain renderer legitimately handles — everything else
/// reaching the numeric fallback is a typo / unsupported name that must fail loud.
fn isKnownNumFmt(name: []const u8) bool {
    if (name.len == 0) return true; // plain w.d / Fw.
    const known = [_][]const u8{ "f", "comma", "commax", "dollar", "dollarx", "negparen", "nlnum" };
    for (known) |k| if (eqi(name, k)) return true;
    return false;
}

/// Informat names the READ paths legitimately handle — plain numeric aliases,
/// COMMA/DOLLAR family, PERCENT, and the implemented date/time informats. Anything
/// else reaching a numeric-read fallback is unimplemented/typo → fail loud
/// (BUG-informatreadloud). Shared by readNumeric (INPUT stmt) and functions.zig
/// readInformat (INPUT() function). Date-name informats are listed too so a caller
/// that routes them here does not false-trip; `spec.name` is already lowercased-safe
/// via eqi. `e`/`b` cover the digit-bearing E8601/B8601 names parseSpec cuts short.
pub fn isKnownInformat(name: []const u8) bool {
    if (name.len == 0) return true; // plain w.d
    const known = [_][]const u8{
        "f",      "best",     "z",       "e",       "d",     "numx", "bz", // plain numeric
        "comma",  "commax",   "dollar",  "dollarx", "nlnum", "percent",
        "hex",    "octal", // GAP-hexinformat/octalinformat: digit-string informats
        "date",   "mmddyy",   "ddmmyy",  "yymmdd",  "monyy", "yyq",  "yyqc",
        "time",   "hhmmss",   "datetime", "tod",    "julian",
        "anydtdte", "anydtdtm", "anydttme", // GAP-anydtinformat
        "e8601da", "e8601dt", "e8601tm", "b8601da", "b8601dt", "b8601tm",
    };
    for (known) |k| if (eqi(name, k)) return true;
    return false;
}

/// Read-side twin of the write-side unknown-format fail-loud (BUG-informatreadloud):
/// flag the run as errored (→ non-zero exit via formatErrored) and report, unless
/// `options nofmterr`. Message mirrors the write side, captured in a test build.
/// SAS "Invalid numeric data" NOTE for a plain `w.d` field with an embedded blank
/// (BUG-numembeddedblank): the value reads as missing, but this is a NOTE, not an
/// ERROR — the run is NOT failed (unlike informatNotFound), matching the
/// diags.note path the implicit char→num conversion uses. Captured in a test
/// build so a fail-loud test can assert it (TEST-quietnoise); the CLI prints it.
var g_test_note_buf: [256]u8 = undefined;
pub var g_test_last_note: []const u8 = "";
/// NOTE-inputinvalidnote dedupe: set when a numeric read already emitted its
/// own invalid-data NOTE (this plain-w.d embedded-blank path), so io.zig's
/// p.518 reporter doesn't print a SECOND note for the same field (SAS prints
/// one). io.zig's readNum clears it per field read; single-threaded.
pub var read_noted: bool = false;
fn invalidNumeric(field: []const u8) Value {
    read_noted = true;
    // NOTE-invalidnumdataloc (GH#78): no "at line N column M" tail — the
    // informat layer sees only the field text; the record line/column lives up
    // in io.zig's noteInvalidNum (which already prints the REAL position for
    // every other invalid-read path). A frozen 0/0 was a lie, so the position
    // is omitted — and the test capture is byte-identical to the CLI text.
    const msg = "Invalid numeric data, '{s}'.";
    if (@import("builtin").is_test) {
        g_test_last_note = std.fmt.bufPrint(&g_test_note_buf, msg, .{field}) catch "invalid-numeric-data";
    } else {
        std.debug.print("NOTE: " ++ msg ++ "\n", .{field});
    }
    return Value.missing;
}

/// BUG-fmtwidthunbounded: reject a width beyond the SAS maximum (numeric 32 /
/// $char 32767) with a loud ERROR (→ non-zero exit via formatErrored; captured
/// in a test build, TEST-quietnoise) and clamp to the cap so any downstream
/// w-fed alloc stays bounded — mirroring the unknown-format loud-then-fallback
/// pattern (BUG-unknownfmtsilent). `options nofmterr` suppresses it, like the
/// other format errors.
fn checkWidth(spec_text: []const u8, spec: Spec) usize {
    const cap: usize = if (spec.is_char) 32767 else 32;
    if (spec.w <= cap) return spec.w;
    if (!g_nofmterr) {
        g_fmt_error = true;
        if (@import("builtin").is_test) {
            g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, "Width specified for format {s} is invalid (maximum {d}).", .{ spec_text, cap }) catch "invalid-format-width";
        } else {
            std.debug.print("ERROR: Width specified for format {s} is invalid (maximum {d}).\n", .{ spec_text, cap });
        }
    }
    return cap;
}

pub fn informatNotFound(name: []const u8, is_char: bool) void {
    if (g_nofmterr) return;
    if (isDocumentedInformat(name, is_char)) diag.markGap(); // D-009 §5f — write-side twin above
    g_fmt_error = true;
    if (@import("builtin").is_test) {
        g_test_last_err = std.fmt.bufPrint(&g_test_err_buf, "The informat {s} was not found or could not be loaded.", .{name}) catch "informat-not-found";
    } else {
        std.debug.print("ERROR: The informat {s} was not found or could not be loaded.\n", .{name});
    }
}

pub fn apply(arena: std.mem.Allocator, v: Value, spec_text: []const u8) Error![]const u8 {
    return applyNest(arena, v, spec_text, 0);
}

/// `apply` + a nested-format depth counter: a VALUE entry whose label is a
/// bracketed format spec (`range=[fmtname w.d]`, SAS directed formatting) renders
/// the value under THAT spec — resolved by re-applying here (BUG-fmtnestlabel).
fn applyNest(arena: std.mem.Allocator, v: Value, spec_text: []const u8, depth: u8) Error![]const u8 {
    var spec = parseSpec(spec_text);
    // BUG-charfmtonnum: a `$` (char) format on a NUMERIC value is a SAS
    // compile-time error — flag it loud (D-002) before any renderer silently
    // coerces the number to text, then fall through and render the raw value
    // so the rest of the output survives. The reverse direction (numeric
    // format on a char value) is NOTE-fmtnumoncharcoerce — checked below, once
    // the char-spec renderers have been routed away. "$." is exempt: the
    // FORMAT-removal form `format x;` rides it as a deliberately TYPE-AGNOSTIC
    // default sentinel (BUG-formatremoval), not a real char format.
    if (spec.is_char and v == .num and !eqi(spec_text, "$.") and !eqi(spec_text, ".")) reportCharFmtOnNumeric(spec_text);
    // A user-defined PICTURE format renders the value through its digit template
    // (PICTURE-format). Checked before VALUE lookup so a picture's template is
    // never mistaken for a literal label.
    if (pictureEntryFor(v, spec)) |e| return renderPicture(arena, valToNum(v), e);
    // A user-defined VALUE format wins over every built-in: `put(x, sexf.)` shows
    // the decoded label (BUG-userformat).
    if (lookupUserFmt(v, spec)) |e| {
        if (e.nested) {
            // `value a 1=[a.]` chains back to itself — unbounded recursion. SAS
            // errors ("format reference is circular"); cap the chain and fail
            // loud, then render the raw value so the rest of the output lands.
            if (depth >= 16) {
                reportCircularFormat(spec.name);
                return switch (v) {
                    .str => |s| renderChar(arena, s, 0),
                    .num => renderNum(arena, valToNum(v), 0, 0, false, false, false),
                };
            }
            return applyNest(arena, v, e.label, depth + 1);
        }
        // BUG-fmtlabelwidth: an explicit width on the format (`f4.`) truncates the
        // matched label to w chars (keeping the first w) and blank-pads a shorter
        // one to w — SAS left-justifies a value label into its field. renderChar
        // returns the label verbatim when w==0 (`f.` → format default width), so
        // the width-less path is unchanged.
        return renderChar(arena, e.label, spec.w);
    }
    // SAS caps a format width (numeric 32 / $char 32767) and rejects larger at
    // compile time; the uncapped parseSpec width fed `arena.alloc(u8, w)`
    // directly, so `put x 33.2` silently over-widened and w=4294967296 hung on
    // a ~4 GB alloc (BUG-fmtwidthunbounded). After the user-format lookups so a
    // defined VALUE format's width-free label render is untouched.
    spec.w = checkWidth(spec_text, spec);
    // GAP-fmtdefwidth-num: a named numeric format with NO explicit width renders
    // at its documented SAS DEFAULT width, right-justified into it (SAS 9.4
    // Formats Reference: COMMA/COMMAX/DOLLAR/DOLLARX/NEGPAREN/PERCENT all default
    // to 6) — `put 0.5 percent.` is "   50%", not "50%". w==0 used to mean
    // natural width / no padding here. BEST (12, below) and the date/time formats
    // carry their own defaults; NLNUM/Z keep prior behavior (unverified default).
    if (spec.w == 0 and (eqi(spec.name, "comma") or eqi(spec.name, "commax") or
        eqi(spec.name, "dollar") or eqi(spec.name, "dollarx") or
        eqi(spec.name, "negparen") or eqi(spec.name, "percent") or
        // GAP-fmtwrite-unimpl: EURO/EUROX (pp.215/218, Default 6) and the
        // locale-invariant NLPCTI/NLPCTN (pp.417/418, Default 6).
        eqi(spec.name, "euro") or eqi(spec.name, "eurox") or
        eqi(spec.name, "nlpcti") or eqi(spec.name, "nlpctn"))) spec.w = 6;
    // BUG-fmtdefwidth-date: the width-less DATE formats do the same — render at
    // the documented DEFAULT width (MONYY/JULIAN 5 ⇒ 2-digit year: `put x monyy.`
    // is `JUL20`, not `JUL2020`; word/name formats pad into their field). w==0
    // used to mean "widest natural form" here. Explicit widths are untouched.
    if (spec.w == 0) spec.w = dateDefaultWidth(spec.name);
    // HEX (before the char branch, so `$HEXw.` isn't treated as a plain char pad):
    // `$HEXw.` hex-encodes each byte of a character value (md5/sha/crc digests →
    // hex), `HEXw.` hex-encodes a numeric value's integer part (BUG-hexformat).
    if (eqi(spec.name, "hex")) {
        if (spec.is_char) return renderHexChar(arena, try valToStr(arena, v), spec.w);
        return renderHexNum(arena, valToNum(v), spec.w);
    }
    if (spec.is_char or eqi(spec.name, "char")) {
        // $UPCASEw./$LOWCASEw. FORMATS transform case before padding — the
        // write-side twin of the $UPCASE informat (BUG-upcaseinformat). They
        // used to fall into the plain char pad and leak the original case
        // (BUG-upcaseformat).
        const raw = try valToStr(arena, v);
        // $QUOTEw. wraps the value in double quotes, DOUBLING an embedded `"` —
        // the same CSV/DSD escape the QUOTE() function (charfns.zig), the FILE
        // DSD writer and PROC EXPORT already use, and the rule the INFILE DSD
        // reader collapses back (BUG-dsddoublequote). Without doubling, a value
        // carrying a `"` quoted out as `"a"b"` — unreadable by any DSD reader,
        // opensas's own included (NOTE-fmtquotedouble: round-trip a"b ↔ "a""b").
        if (eqi(spec.name, "quote")) {
            var q: std.ArrayList(u8) = .empty;
            try q.append(arena, '"');
            for (raw) |c| {
                if (c == '"') try q.append(arena, '"');
                try q.append(arena, c);
            }
            try q.append(arena, '"');
            return renderChar(arena, q.items, spec.w);
        }
        const cased = if (eqi(spec.name, "upcase"))
            try std.ascii.allocUpperString(arena, raw)
        else if (eqi(spec.name, "lowcase"))
            try std.ascii.allocLowerString(arena, raw)
        else
            raw;
        // BUG-charfmtsink: an unknown `$NAME` (not a built-in `$.`/`$CHAR`/
        // `$UPCASE`/`$LOWCASE`/`$QUOTE`/`$HEX`, and not a defined user format)
        // used to fall through to a plain pad — a silent sink. Fail loud like
        // the numeric tail, then still render the raw pad so output survives.
        const known = spec.name.len == 0 or eqi(spec.name, "char") or
            eqi(spec.name, "upcase") or eqi(spec.name, "lowcase");
        if (!known and !isUserFmtName(v, spec)) reportUnknownFormat(spec.name, true);
        // Unmatched user CHAR format with no explicit width → truncate to the
        // format's default width (longest label, GH#63). Built-in `$.`/`$w.`
        // names no user format → w stays 0 → value as-is (untouched).
        const w = if (spec.w == 0) userFmtDefaultWidth(v, spec) else spec.w;
        return renderChar(arena, cased, w);
    }
    // NOTE-fmtnumoncharcoerce: every spec below here is numeric, so a char
    // value reaching this point is the destructive mismatch — report it loud
    // and render the raw text (the analogous-format fallback of Formats Ref
    // p.5), never the silent '.'. A DEFINED user format is exempt: its
    // value-type-aware lookup above resolves a match, and a range miss renders
    // raw at the numeric tail (BUG-formatexclrange / QA-charfmtnomatch).
    if (v == .str and !isUserFmtName(v, spec)) {
        reportNumFmtOnChar(spec_text);
        return renderChar(arena, v.str, spec.w);
    }
    if (eqi(spec.name, "date"))
        return renderDate(arena, valToNum(v), spec.w, .date);
    if (eqi(spec.name, "mmddyy"))
        return renderDate(arena, valToNum(v), spec.w, .mmddyy);
    if (eqi(spec.name, "ddmmyy"))
        return renderDate(arena, valToNum(v), spec.w, .ddmmyy);
    if (eqi(spec.name, "yymmdd"))
        return renderDate(arena, valToNum(v), spec.w, .yymmdd);
    // YYMMDDxw. family (BUG-sysfuncformat): same y-m-d order, a per-suffix
    // separator. N has NO separator (yyyymmdd at w≥8), the rest match the base
    // YYMMDD width rule (4-digit year only at w≥10). Needed by the Autoexec's
    // `%sysfunc(today(), yymmddn.)`.
    if (eqi(spec.name, "yymmddn")) return renderYymmddX(arena, valToNum(v), spec.w, null);
    if (eqi(spec.name, "yymmddb")) return renderYymmddX(arena, valToNum(v), spec.w, ' ');
    if (eqi(spec.name, "yymmddc")) return renderYymmddX(arena, valToNum(v), spec.w, ':');
    if (eqi(spec.name, "yymmddd")) return renderYymmddX(arena, valToNum(v), spec.w, '-');
    if (eqi(spec.name, "yymmddp")) return renderYymmddX(arena, valToNum(v), spec.w, '.');
    if (eqi(spec.name, "yymmdds")) return renderYymmddX(arena, valToNum(v), spec.w, '/');
    if (eqi(spec.name, "worddate"))
        return renderWordDate(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "weekdate")) // BUG-datefmtcluster: "Saturday, July 4, 2020"
        return renderWeekDate(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "nldate")) // en_US NLDATE renders like WORDDATE ("July 4, 2020")
        return renderWordDate(arena, valToNum(v), spec.w);
    // BUG-datefmtcluster: the rest of the date write-format family (all leaked raw)
    if (eqi(spec.name, "weekdatx")) return renderWeekDatx(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "worddatx")) return renderWordDatx(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "julian")) return renderJulian(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "qtr")) return renderQtr(arena, valToNum(v), spec.w, false);
    if (eqi(spec.name, "qtrr")) return renderQtr(arena, valToNum(v), spec.w, true);
    if (eqi(spec.name, "yyq")) return renderYyq(arena, valToNum(v), spec.w, 'Q');
    if (eqi(spec.name, "yyqc")) return renderYyq(arena, valToNum(v), spec.w, ':');
    if (eqi(spec.name, "weekday")) return renderDatePart(arena, valToNum(v), spec.w, .weekday);
    if (eqi(spec.name, "month")) return renderDatePart(arena, valToNum(v), spec.w, .month);
    if (eqi(spec.name, "day")) return renderDatePart(arena, valToNum(v), spec.w, .day);
    if (eqi(spec.name, "yymmn")) return renderYymmn(arena, valToNum(v), spec.w);
    // YYMMw./MMYYw. + xw. separator variants (GAP-fmtyymm). Base separator is the
    // letter `M`; C/D/P/S swap it, N drops it. YYMMN already handled just above.
    if (eqi(spec.name, "yymm")) return renderYymm(arena, valToNum(v), spec.w, 'M', false);
    if (eqi(spec.name, "yymmc")) return renderYymm(arena, valToNum(v), spec.w, ':', false);
    if (eqi(spec.name, "yymmd")) return renderYymm(arena, valToNum(v), spec.w, '-', false);
    if (eqi(spec.name, "yymmp")) return renderYymm(arena, valToNum(v), spec.w, '.', false);
    if (eqi(spec.name, "yymms")) return renderYymm(arena, valToNum(v), spec.w, '/', false);
    if (eqi(spec.name, "mmyy")) return renderYymm(arena, valToNum(v), spec.w, 'M', true);
    if (eqi(spec.name, "mmyyc")) return renderYymm(arena, valToNum(v), spec.w, ':', true);
    if (eqi(spec.name, "mmyyd")) return renderYymm(arena, valToNum(v), spec.w, '-', true);
    if (eqi(spec.name, "mmyyn")) return renderYymm(arena, valToNum(v), spec.w, null, true);
    if (eqi(spec.name, "mmyyp")) return renderYymm(arena, valToNum(v), spec.w, '.', true);
    if (eqi(spec.name, "mmyys")) return renderYymm(arena, valToNum(v), spec.w, '/', true);
    if (eqi(spec.name, "time"))
        return renderTime(arena, valToNum(v), spec.w, spec.d, false);
    // WRITE-side date/time cluster (BUG-dateformats) — all fell through to the
    // numeric renderer and printed the raw SAS number.
    if (eqi(spec.name, "monyy")) return renderMonyy(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "monname")) return renderMonName(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "downame")) return renderDowName(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "year")) return renderYear(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "datetime")) return renderDatetime(arena, valToNum(v), spec.w, spec.d);
    // DT-prefixed formats write the DATE part of a SAS DATETIME value (seconds
    // since 1960) — take datepart() then reuse the matching date renderer (SAS 9.4
    // "DTDATEw./DTMONYYw./DTYEARw./DTWKDATXw. write the date part of a datetime").
    if (eqi(spec.name, "dtdate")) return renderDate(arena, datePartOf(valToNum(v)), spec.w, .date);
    if (eqi(spec.name, "dtmonyy")) return renderMonyy(arena, datePartOf(valToNum(v)), spec.w);
    if (eqi(spec.name, "dtyear")) return renderYear(arena, datePartOf(valToNum(v)), spec.w);
    if (eqi(spec.name, "dtwkdatx")) return renderWeekDatx(arena, datePartOf(valToNum(v)), spec.w);
    // ISO 8601 write side (QA-e8601put) — the informat side already reads these.
    if (eqi(spec.name, "e8601da")) return renderYymmddX(arena, valToNum(v), if (spec.w == 0) 10 else spec.w, '-');
    if (eqi(spec.name, "e8601dt")) return renderE8601Dt(arena, valToNum(v), spec.w);
    // E8601TMw. — ISO time hh:mm:ss (a time value); same body as TIME. E8601DNw. —
    // the DATE part of an ISO DATETIME as yyyy-mm-dd (datepart then E8601DA). GAP-timeformats.
    if (eqi(spec.name, "e8601tm")) return renderTime(arena, valToNum(v), if (spec.w == 0) 8 else spec.w, 0, true); // ISO: zero-pad hh
    if (eqi(spec.name, "e8601dn")) return renderYymmddX(arena, datePartOf(valToNum(v)), if (spec.w == 0) 10 else spec.w, '-');
    // GAP-fmtwritebatch (doc-finder tick126): ISO 8601 BASIC forms (no
    // separators) + the date/time/special write formats that used to fail loud.
    // Still loud: the LOCALE=-driven NL* writes — NLPCT/NLPCTP/NLMNYI and the
    // NLMNI<ccy> currency family render per the SESSION locale (every entry:
    // "The output value depends on the locale"), which opensas does not model,
    // so any output would be a guess (GAP-fmtwrite-unimpl) — and PDJULG/PDJULI
    // (packed-byte forms).
    if (eqi(spec.name, "b8601da")) return renderYymmddX(arena, valToNum(v), if (spec.w == 0) 10 else spec.w, null);
    if (eqi(spec.name, "b8601dt")) return renderB8601Dt(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "b8601tm")) return renderB8601Tm(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "yymon")) return renderYymon(arena, valToNum(v), spec.w);
    // NENGOw. — Japanese era date (p.257; GAP-fmtwrite-unimpl).
    if (eqi(spec.name, "nengo")) return renderNengo(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "julday")) return renderJulday(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "pdjulian")) return renderJulian(arena, valToNum(v), spec.w); // yyyyddd, JULIAN twin
    if (eqi(spec.name, "dateampm")) return renderDateAmpm(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "mmss")) return renderMmss(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "roman")) return renderRoman(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "words")) return renderWords(arena, valToNum(v), spec.w);
    // NL* en_US approximations, same house pattern as NLDATE→WORDDATE above.
    if (eqi(spec.name, "nldatm")) return renderNldatm(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "nltime")) return renderTime(arena, valToNum(v), spec.w, 0, false);
    // ponytail: d==0 (unspecified or explicit .0 — indistinguishable) → 2
    // decimals, the en_US currency default; use DOLLARw.0 for 0 decimals.
    if (eqi(spec.name, "nlmny")) return renderNum(arena, valToNum(v), spec.w, if (spec.d == 0) 2 else spec.d, true, true, false);
    // NLPCTIw.d (p.417) / NLPCTNw.d (p.418) — the two locale-INVARIANT percent
    // formats of the NL family (GAP-fmtwrite-unimpl). NLPCTI: comma grouping +
    // period decimal ALWAYS (the Comparisons paragraph pins it; the NLPCT
    // entry's own example shows nlpcti identical under en_US and
    // German_Germany). NLPCTN: no separators, minus sign, trailing blank.
    // NLPCT (p.415) / NLPCTP (p.419) stay loud — separators locale-specific.
    if (eqi(spec.name, "nlpcti")) return renderNlpcti(arena, valToNum(v), spec.w, spec.d);
    if (eqi(spec.name, "nlpctn")) return renderNlpctn(arena, valToNum(v), spec.w, spec.d);
    // Time hour:minute + component formats (GAP-timeformats).
    if (eqi(spec.name, "hhmm")) return renderHhmm(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "hour")) return renderHour(arena, valToNum(v), spec.w, spec.d);
    if (eqi(spec.name, "minute")) return renderMinute(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "second")) return renderSecond(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "binary")) return renderBinaryNum(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "timeampm")) return renderTimeAmpm(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "tod")) return renderTod(arena, valToNum(v), spec.w, spec.d);
    if (eqi(spec.name, "z"))
        return renderNum(arena, valToNum(v), spec.w, spec.d, false, false, true); // zero-padded
    if (eqi(spec.name, "percent"))
        return renderPercent(arena, valToNum(v), spec.w, spec.d);
    if (eqi(spec.name, "e"))
        return renderE(arena, valToNum(v), spec.w, spec.d);
    if (eqi(spec.name, "best")) {
        // BESTw. shows the value to the most digits that fit in w columns (keeping
        // decimals when they fit), then right-justifies. No width → the BEST12.
        // value, unpadded (the default list-output path).
        const w = if (spec.w > 0) spec.w else 12;
        const s = try bestNumW(arena, valToNum(v), w);
        return if (spec.w > 0) justRight(arena, s, spec.w) else s;
    }
    // NLNUM (en_US locale numeric) groups like COMMA (BUG-fmtxnlneg).
    if (eqi(spec.name, "nlnum"))
        return renderNum(arena, valToNum(v), spec.w, spec.d, true, false, false);
    // COMMAX / DOLLARX are European: render as COMMA / DOLLAR then swap the
    // separators (`,`↔`.`) so `.`=thousands and `,`=decimal (BUG-fmtxnlneg).
    if (eqi(spec.name, "commax") or eqi(spec.name, "dollarx")) {
        const dx = eqi(spec.name, "dollarx");
        const s = try renderNum(arena, valToNum(v), spec.w, spec.d, true, dx, false);
        const m = try arena.dupe(u8, s); // dupe → mutable; each apply call is a fresh arena
        for (m) |*c| c.* = switch (c.*) {
            ',' => '.',
            '.' => ',',
            else => c.*,
        };
        return m;
    }
    // NEGPAREN — comma-grouped magnitude; negatives in parens, positives reserve
    // the last column for the absent close-paren (BUG-fmtxnlneg).
    if (eqi(spec.name, "negparen"))
        return renderNegParen(arena, valToNum(v), spec.w, spec.d);
    // EUROw.d/EUROXw.d (pp.215/218) — the DOLLAR/DOLLARX twins with a leading
    // `E` for `$` ("similar to the DOLLARw.d format, except … euro symbol").
    // NOT locale-driven, unlike the NL* family: fixed comma/period (EURO) or
    // period/comma (EUROX) separators. GAP-fmtwrite-unimpl.
    if (eqi(spec.name, "euro") or eqi(spec.name, "eurox"))
        return renderEuro(arena, valToNum(v), spec.w, spec.d, eqi(spec.name, "eurox"));
    // GAP-fmtwrite-unimpl: FRACTw. (p.224) and Dw.p (p.170) write renderers.
    if (eqi(spec.name, "fract")) return renderFract(arena, valToNum(v), spec.w);
    if (eqi(spec.name, "d")) return renderD(arena, valToNum(v), spec.w, spec.d);
    const dollar = eqi(spec.name, "dollar");
    if (isKnownNumFmt(spec.name)) // plain w.d, COMMA, DOLLAR, or a recognized numeric name
        return renderNum(arena, valToNum(v), spec.w, spec.d, dollar or eqi(spec.name, "comma"), dollar, false);
    // A DEFINED user VALUE format whose value matched no range (and had no OTHER=)
    // is NOT unknown — SAS renders the raw value with no error (BUG-formatexclrange).
    if (isUserFmtName(v, spec)) return switch (v) {
        // QA-charfmtnomatch: a CHAR value under a defined char format with no
        // matching key and no OTHER= renders the RAW VALUE (SAS) — the old
        // renderNum path printed "." and silently blanked gen2 AEOUT (67 rows).
        .str => |s| renderChar(arena, s, if (spec.w == 0) userFmtDefaultWidth(v, spec) else spec.w),
        // NOTE-numfmtdefwidth: numeric twin of the CHAR path above — an unmatched
        // numeric value with no explicit width right-justifies in the format's
        // default (widest-label) width, the same source userFmtDefaultWidth feeds char.
        .num => renderNum(arena, valToNum(v), if (spec.w == 0) userFmtDefaultWidth(v, spec) else spec.w, spec.d, false, false, false),
    };
    // An unrecognized/unsupported format name — fail loud (BUG-unknownfmtsilent),
    // then render a plain fallback so the remaining output still lands.
    reportUnknownFormat(spec.name, false);
    return renderNum(arena, valToNum(v), spec.w, spec.d, false, false, false);
}

// ── renderers ──────────────────────────────────────────────────────────────

fn renderChar(arena: std.mem.Allocator, s: []const u8, w: usize) Error![]const u8 {
    if (w == 0) return s; // `$.` — no width, value as-is
    const out = try arena.alloc(u8, w);
    const n = @min(s.len, w);
    @memcpy(out[0..n], s[0..n]);
    @memset(out[n..], ' '); // left-justified, blank-padded
    return out;
}

const hexdigits = "0123456789ABCDEF";

/// `$HEXw.` — each byte of a character value → two uppercase hex digits. `w` hex
/// digits = ceil(w/2) bytes; a value shorter than that is blank-padded (0x20, so
/// "20"), as SAS does. `w`==0 → the whole value. This is how a raw md5/sha/crc
/// digest (a byte string) is printed as hex.
fn renderHexChar(arena: std.mem.Allocator, s: []const u8, w: usize) Error![]const u8 {
    const nbytes = if (w > 0) (w + 1) / 2 else s.len;
    const out = try arena.alloc(u8, nbytes * 2);
    for (0..nbytes) |i| {
        const b: u8 = if (i < s.len) s[i] else ' ';
        out[2 * i] = hexdigits[b >> 4];
        out[2 * i + 1] = hexdigits[b & 0x0f];
    }
    return if (w > 0 and w < out.len) out[0..w] else out; // trim if w is odd
}

/// `HEXw.` — a numeric value's integer part in uppercase hex, right-justified and
/// zero-padded to `w` digits (low `w` digits kept if it overflows). Non-finite →
/// blanks. Negatives render as their two's-complement bit pattern truncated to
/// the field's `4*w` bits (SAS: -5 hex4. → FFFB).
fn renderHexNum(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (!std.math.isFinite(x)) return renderChar(arena, "", w); // missing → blanks
    // HEXw. with w>=16 shows the raw 8-byte IEEE double, big-endian, as 16 hex
    // digits (36.6 → 40424CCCCCCCCCCD) — not the integer magnitude (GH#46).
    if (w >= 16) {
        const bits: u64 = @bitCast(x);
        const out = try arena.alloc(u8, w);
        @memset(out, ' '); // right-justify the 16 digits if w>16 (SAS caps HEX at 16)
        for (0..16) |j| {
            const nib: u4 = @truncate(bits >> @intCast(4 * (15 - j)));
            out[w - 16 + j] = hexdigits[nib];
        }
        return out;
    }
    // |x| >= 2^64 overflows the u64 cast → abort (BUG-fmtnumoverflow). SAS caps
    // the field on overflow; clamp to the field-full value (all-F digits).
    const overflow = @abs(x) >= 18446744073709551616.0;
    var v: u64 = if (overflow) std.math.maxInt(u64) else @intFromFloat(@trunc(@abs(x)));
    // In-range negatives → two's-complement, masked to the field's 4*w bits. Masking
    // also matches the existing low-digit truncation for oversized positives, and an
    // overflowed value (capped to all-1s) stays field-full (all-F) either sign. Top
    // nibble of an in-range negative is nonzero, so the field fills with F's here
    // rather than the zero-pad below.
    if (w > 0) { // w<16 guaranteed here (w>=16 returned above)
        if (x < 0 and !overflow) v = 0 -% v;
        v &= (@as(u64, 1) << @intCast(4 * w)) - 1;
    }
    var tmp: [16]u8 = undefined;
    var n: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else while (v > 0 and n < tmp.len) : (n += 1) {
        tmp[n] = hexdigits[@intCast(v & 0x0f)];
        v >>= 4;
    }
    const width = if (w > 0) w else n;
    const out = try arena.alloc(u8, width);
    @memset(out, '0');
    var k: usize = 0;
    while (k < n and k < width) : (k += 1) out[width - 1 - k] = tmp[k]; // right-justified
    return out;
}

/// Nothing fits the field → all asterisks, `*` × w (SAS overflow convention).
fn stars(arena: std.mem.Allocator, w: usize) Error![]const u8 {
    const out = try arena.alloc(u8, w);
    @memset(out, '*');
    return out;
}

fn renderNum(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize, commas: bool, dollar: bool, zero: bool) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, try arena.dupe(u8, &[_]u8{Value.missingChar(x)}), w);

    const finish = struct {
        fn f(ar: std.mem.Allocator, body: []const u8, width: usize, z: bool) Error![]const u8 {
            return if (z) justRightZero(ar, body, width) else justRight(ar, body, width);
        }
    }.f;

    // Fit to `w` (BUG-fmtwidth): SAS never overflows the field. Try the fixed w.d
    // form, reducing decimals until it fits; then drop grouping commas, then the
    // `$`; then BESTw/Ew; finally fill the field with `*`. `w == 0` means no width
    // was specified, so nothing to fit — the first (full) form is taken.
    const fits = struct {
        fn f(len: usize, width: usize) bool {
            return width == 0 or len <= width;
        }
    }.f;
    var d: usize = @min(d_in, 15);
    while (true) : (d -= 1) {
        if (try buildFixed(arena, x, d, commas, dollar)) |body|
            if (fits(body.len, w)) return finish(arena, body, w, zero);
        if (d == 0) break;
    }
    if (commas) // drop the grouping separators, keep the `$`
        if (try buildFixed(arena, x, 0, false, dollar)) |body|
            if (fits(body.len, w)) return finish(arena, body, w, zero);
    if (dollar) // drop the `$` too
        if (try buildFixed(arena, x, 0, false, false)) |body|
            if (fits(body.len, w)) return finish(arena, body, w, zero);
    const best = try bestNumW(arena, x, w); // BESTw / Ew notation sized to the field
    if (fits(best.len, w)) return finish(arena, best, w, zero);
    return stars(arena, w); // nothing fits → all asterisks (SAS)
}

/// The fixed `w.d` body (sign, optional `$`, grouped/plain integer, `.` + `d`
/// fraction) with NO width padding — the caller checks its length. Null when the
/// value is too large for the integer path (caller falls back to BEST/E).
fn buildFixed(arena: std.mem.Allocator, x: f64, d: usize, commas: bool, dollar: bool) Error!?[]const u8 {
    var pow10: u64 = 1;
    for (0..d) |_| pow10 *= 10;
    const scaled = scaledRoundExact(x, d) orelse return null; // too big for the integer path
    const int_part = scaled / pow10;
    const frac = scaled % pow10;

    var body: std.ArrayList(u8) = .empty;
    if (x < 0 and scaled != 0) try body.append(arena, '-');
    if (dollar) try body.append(arena, '$'); // DOLLAR: `$` after the sign, before digits

    var intbuf: [32]u8 = undefined;
    const int_digits = std.fmt.bufPrint(&intbuf, "{d}", .{int_part}) catch unreachable;
    assert(int_digits.len <= intbuf.len); // digits of a u64 (≤20) fit the [32]u8
    if (commas) try appendGrouped(arena, &body, int_digits) else try body.appendSlice(arena, int_digits);

    if (d > 0) {
        try body.append(arena, '.');
        var fracbuf: [32]u8 = undefined;
        const fs = std.fmt.bufPrint(&fracbuf, "{d}", .{frac}) catch unreachable;
        assert(fs.len <= fracbuf.len); // frac < pow10 (≤15 digits) fits the [32]u8
        for (fs.len..d) |_| try body.append(arena, '0'); // left-pad fraction to d
        try body.appendSlice(arena, fs);
    }
    return body.items;
}

/// |x| · 10^d rounded to an integer, decided from the EXACT binary value of x
/// (BUG-wdroundtie). SAS's w.d renders the true stored double: an exact decimal
/// tie (…5) rounds half away from zero, anything strictly below the tie rounds
/// down. The old `@round(@abs(x) * 10^d)` let the f64 multiply snap a below-tie
/// value onto a FALSE tie — put(2.675,8.2) gave "2.68" where SAS renders the
/// stored 2.67499999999999982… as "2.67". Null when too big for the integer
/// path (caller falls back to BEST/E).
fn scaledRoundExact(x: f64, d: usize) ?u64 {
    const bits: u64 = @bitCast(@abs(x));
    const be = (bits >> 52) & 0x7ff;
    const m: u128 = if (be == 0) bits & 0xf_ffff_ffff_ffff else (bits & 0xf_ffff_ffff_ffff) | 0x10_0000_0000_0000;
    if (m == 0) return 0;
    const e2: i32 = if (be == 0) -1074 else @as(i32, @intCast(be)) - 1075; // x = m · 2^e2 (denormal: 2^-1074)
    var num: u128 = m;
    for (0..d) |_| num *= 10; // m < 2^53 and d ≤ 15 (callers cap) → num < 2^103, no u128 overflow
    const q: u128 = if (e2 >= 0) blk: {
        // Integer-valued already, no fraction to round. e2 ≥ 11 ⇒ ≥ 2^63 ≥ 9e18
        // ⇒ too big; below that num·2^e2 < 2^113 stays in u128.
        if (e2 >= 11) return null;
        break :blk num << @intCast(e2);
    } else blk: {
        if (-e2 > 127) break :blk 0; // num < 2^103 < 2^(s-1): strictly below the tie → 0
        const sh: u7 = @intCast(-e2);
        const quo = num >> sh;
        const rem = num - (quo << sh);
        break :blk if (rem >= @as(u128, 1) << (sh - 1)) quo + 1 else quo; // tie/above → away from 0
    };
    if (q >= 9_000_000_000_000_000_000) return null; // 9e18 is exact in both f64 and u128
    return @intCast(q);
}

/// Ew.[d] — scientific notation `[-]m.dddE±nn`. Fixed `d` mantissa decimals
/// (default: as many as fit in `w` after the sign, `d.`, and `E±nn`); a signed,
/// ≥2-digit exponent; right-justified. Unlike BEST's E-notation it keeps trailing
/// mantissa zeros and always shows the exponent sign (BUG-eformat).
/// ax / 10^exp, i.e. ax scaled into the mantissa range [1,10). Direct division
/// underflows to +inf for the tiniest denormals (|x| ~ 5e-324, exp ~ -324) when
/// 10^exp itself underflows to 0 — the subsequent @intFromFloat then aborts
/// (BUG-fmtnumoverflow). Fall back to a stepwise scale that stays finite there.
fn eMantissa(ax: f64, exp: i32) f64 {
    const p = std.math.pow(f64, 10, @floatFromInt(exp));
    if (p != 0 and std.math.isFinite(p)) return ax / p;
    var m = ax;
    var e = exp;
    while (e > 0) : (e -= 1) m /= 10.0;
    while (e < 0) : (e += 1) m *= 10.0;
    return m;
}

fn renderE(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize) Error![]const u8 {
    if (!std.math.isFinite(x)) return justRight(arena, ".", w);
    const neg = x < 0;
    const ax = @abs(x);
    const exp: i32 = if (ax == 0) 0 else @intFromFloat(@floor(@log10(ax)));
    var exp_digits: usize = 2;
    {
        var ae: i32 = if (exp < 0) -exp else exp;
        var c: usize = 1;
        while (ae >= 10) : (ae = @divTrunc(ae, 10)) c += 1;
        if (c > exp_digits) exp_digits = c;
    }
    const overhead = (if (neg) @as(usize, 1) else 0) + 2 + 2 + exp_digits; // sign + "d." + "E±" + exp
    var d: usize = if (d_in > 0) @min(d_in, 15) else (if (w > overhead) w - overhead else 0);
    // Fit ladder (BUG-percentfit): reduce mantissa decimals until the body fits
    // `w`; still too wide → asterisk-fill like SAS, never overflow the field.
    while (true) : (d -= 1) {
        const body = try buildEBody(arena, ax, exp, exp_digits, neg, d);
        if (w == 0 or body.len <= w) return justRight(arena, body, w);
        if (d == 0) break;
    }
    return stars(arena, w);
}

/// The E-body `[-]m.dddE±nn` at `d` mantissa decimals, with NO width padding —
/// the caller checks its length. exp renormalizes +1 when rounding lifts the
/// mantissa to 10.xxx.
fn buildEBody(arena: std.mem.Allocator, ax: f64, exp_in: i32, exp_digits: usize, neg: bool, d: usize) Error![]const u8 {
    var exp = exp_in;
    // A double carries ~15-16 significant decimal digits; scaling by 10^d for
    // d≥19 both overflows the u64 mantissa (@intFromFloat then panics — the
    // BUG-efmtcrash abort at wide Ew.d) and would only emit conversion noise past
    // double precision. Compute at most 15 decimals into the integer mantissa and
    // pad the remaining positions with text zeros — SAS renders wide Ew.d the same
    // way (mantissa to representable precision, zero-filled to width).
    // ponytail: 15 is the IEEE-754 f64 decimal-precision ceiling; only revisit if
    // this ever renders from an f80/f128.
    const dc: usize = @min(d, 15); // typed: bare @min narrows to u4, then dc+1 overflows
    var mant: f64 = if (ax == 0) 0 else eMantissa(ax, exp);
    var mi: u64 = @intFromFloat(@round(mant * pow10f(@intCast(dc))));
    if (@as(f64, @floatFromInt(mi)) >= pow10f(@intCast(dc + 1))) { // rounded up to 10.xxx → renormalize
        exp += 1;
        mant = eMantissa(ax, exp);
        mi = @intFromFloat(@round(mant * pow10f(@intCast(dc))));
    }
    // mantissa digits: leading digit + d decimals. The first dc+1 come from the
    // integer mantissa (zero-padded up front if short); decimals beyond double
    // precision are trailing zeros.
    var mbuf: [24]u8 = undefined;
    const ms = std.fmt.bufPrint(&mbuf, "{d}", .{mi}) catch unreachable;
    var digits: [40]u8 = undefined;
    const total = d + 1;
    const calc_total = dc + 1;
    const pad = if (ms.len < calc_total) calc_total - ms.len else 0;
    @memset(digits[0..pad], '0');
    @memcpy(digits[pad .. pad + ms.len], ms);
    @memset(digits[pad + ms.len .. total], '0'); // decimals past f64 precision
    const dstr = digits[0..total];

    var body: std.ArrayList(u8) = .empty;
    if (neg) try body.append(arena, '-');
    try body.append(arena, dstr[0]);
    if (d > 0) {
        try body.append(arena, '.');
        try body.appendSlice(arena, dstr[1..]);
    }
    try body.append(arena, 'E');
    try body.append(arena, if (exp < 0) '-' else '+');
    try appendPadded(arena, &body, @intCast(if (exp < 0) -exp else exp), exp_digits);
    return body.items;
}

/// PERCENTw.d — scale by 100, render like `w.d`, append `%`; negatives are
/// wrapped in parentheses (SAS convention), then right-justified in `w`.
fn renderPercent(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const scaled = x * 100.0;
    const neg = scaled < 0;
    // Fit ladder (BUG-percentfit): reduce decimals until `num%` / `(num%)` fits
    // `w`; still too wide → asterisk-fill like SAS, never overflow the field.
    var d: usize = @min(d_in, 15);
    while (true) : (d -= 1) {
        if (try buildFixed(arena, @abs(scaled), d, false, false)) |num| {
            var body: std.ArrayList(u8) = .empty;
            if (neg) try body.append(arena, '(');
            try body.appendSlice(arena, num);
            try body.append(arena, '%');
            if (neg) try body.append(arena, ')');
            if (w == 0 or body.items.len <= w) return justRight(arena, body.items, w);
        } else if (w == 0) {
            // Too big for the integer path, no width to fit → old BEST fallback.
            var body: std.ArrayList(u8) = .empty;
            if (neg) try body.append(arena, '(');
            try body.appendSlice(arena, try bestNumW(arena, @abs(scaled), 0));
            try body.append(arena, '%');
            if (neg) try body.append(arena, ')');
            return body.items;
        } else break; // too big for the integer path → asterisks below
        if (d == 0) break;
    }
    return stars(arena, w);
}

/// NLPCTIw.d — percentage of the INTERNATIONAL expression (SAS 9.4 Formats
/// Reference p.417). Locale-INVARIANT, unlike the parked NLPCTw.d (p.415): the
/// Comparisons paragraph pins "a comma (,) as thousands separator and a period
/// (.) as a decimal separator" always, and the NLPCT entry's own example shows
/// nlpcti output identical under en_US and German_Germany (`-1,234.57%`).
/// ×100 like PERCENTw.d, but a MINUS sign for negatives (not parens), trailing
/// `%`, LEFT-justified (Alignment: Left). Default w 6, d 0 (GAP-fmtwrite-unimpl).
fn renderNlpcti(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justLeft(arena, ".", w);
    const scaled = x * 100.0;
    const neg = scaled < 0;
    var d: usize = @min(d_in, 15);
    while (true) : (d -= 1) {
        if (try buildFixed(arena, @abs(scaled), d, true, false)) |num| {
            var body: std.ArrayList(u8) = .empty;
            if (neg) try body.append(arena, '-');
            try body.appendSlice(arena, num);
            try body.append(arena, '%');
            if (w == 0 or body.items.len <= w) return justLeft(arena, body.items, w);
        } else break; // too big for the integer path → asterisks below
        if (d == 0) break;
    }
    return stars(arena, w);
}

/// NLPCTNw.d — percentages with a MINUS sign for negative values (SAS 9.4
/// Formats Reference p.418: "multiplies negative values by 100, adds a minus
/// sign … and adds a percent sign (%) to the end"; example x=-0.02 → `-2%`).
/// No thousands separator anywhere in the entry — locale-invariant, unlike the
/// parked NLPCTPw.d (p.419). Alignment Right; the width Tip reserves "the
/// minus sign, the percent sign, and a trailing blank, whether the number is
/// negative or positive" — so the body always ends in one blank (`-2% `; the
/// Range floor 4 is exactly `-2% `). Default w 6, d 0 (GAP-fmtwrite-unimpl).
fn renderNlpctn(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const scaled = x * 100.0;
    const neg = scaled < 0;
    var d: usize = @min(d_in, 15);
    while (true) : (d -= 1) {
        if (try buildFixed(arena, @abs(scaled), d, false, false)) |num| {
            var body: std.ArrayList(u8) = .empty;
            if (neg) try body.append(arena, '-');
            try body.appendSlice(arena, num);
            try body.append(arena, '%');
            try body.append(arena, ' '); // documented trailing blank (p.418 Tip)
            if (w == 0 or body.items.len <= w) return justRight(arena, body.items, w);
        } else break; // too big for the integer path → asterisks below
        if (d == 0) break;
    }
    return stars(arena, w);
}

/// EUROw.d/EUROXw.d — numeric with a leading euro symbol `E` (SAS 9.4 Formats
/// Reference p.215: "similar to the DOLLARw.d format, except that DOLLARw.d
/// format writes a leading dollar sign instead of the euro symbol"; p.218:
/// EUROX "reverses the roles of the decimal point and the comma" like
/// DOLLARX). NOT locale-driven, unlike the NL* family — fixed separators.
/// Default w 6, Range 1–32, d Default 0. The w=6 default-length logs (p.217,
/// p.220) pin the fit ladder: reduce d → drop the SYMBOL keeping grouping
/// (`55,555`, not `E55555` — the opposite rung order to renderNum's DOLLAR
/// ladder) → drop grouping → BESTw (`7.78E6`, separators NOT swapped under
/// EUROX) → asterisks (GAP-fmtwrite-unimpl).
fn renderEuro(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize, swap: bool) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, try arena.dupe(u8, &[_]u8{Value.missingChar(x)}), w);
    var d: usize = @min(d_in, 15);
    while (true) : (d -= 1) {
        if (try euroBody(arena, x, d, true, true, swap)) |body|
            if (w == 0 or body.len <= w) return justRight(arena, body, w);
        if (d == 0) break;
    }
    if (try euroBody(arena, x, 0, true, false, swap)) |body| // drop the E, keep grouping
        if (w == 0 or body.len <= w) return justRight(arena, body, w);
    if (try euroBody(arena, x, 0, false, false, swap)) |body| // drop grouping too
        if (w == 0 or body.len <= w) return justRight(arena, body, w);
    const best = try bestNumW(arena, x, w); // BESTw: no E, separators NOT swapped (p.220)
    if (w == 0 or best.len <= w) return justRight(arena, best, w);
    return stars(arena, w);
}

/// The fixed EURO/EUROX body via buildFixed: `$`→`E`, then for EUROX swap the
/// separator roles (`,`↔`.`). Null when too big for the integer path (caller
/// falls to BESTw, whose separators stay put).
fn euroBody(arena: std.mem.Allocator, x: f64, d: usize, commas: bool, symbol: bool, swap: bool) Error!?[]const u8 {
    const s = (try buildFixed(arena, x, d, commas, symbol)) orelse return null;
    const m = try arena.dupe(u8, s); // dupe → mutable; each apply call is a fresh arena
    for (m) |*c| c.* = switch (c.*) {
        '$' => 'E',
        ',' => if (swap) '.' else ',',
        '.' => if (swap) ',' else '.',
        else => c.*,
    };
    return m;
}

/// FRACTw. — the value as a reduced fraction `p/q`, right-justified in `w`
/// (SAS 9.4 Formats Reference, FRACTw. Format p.224: default w 10, range 4–32;
/// "writes fractions in reduced form (for example, 1/2 instead of 50/100)").
/// The most accurate rational whose `p/q` display fits the field, walked through
/// the continued fraction of |x|: convergent/semiconvergent candidates improve
/// monotonically, so per CF step the widest-fitting one is champion and a later
/// champion only replaces the incumbent when strictly closer in f64 (doc rows:
/// 0.6666666667 fract8. → `     2/3`, 0.2784 fract8. → ` 174/625`). The strict
/// rule keeps deep convergents of a decimal-typed input — which tie at f64
/// noise — from displacing the simpler intended fraction. An exact hit
/// (err == 0) stops the walk: nothing later is shorter. Integers render `n/1`
/// (doc silent); the plain-integer rendering competes on error and wins when no
/// exact `n/1` fits (123456 fract7. → ` 123456`); nothing fits → asterisks.
/// ponytail: the CF runs on the f64 working value, so partial quotients past
/// q ≈ 1e15 are noise — unreachable for w ≤ 32 except for irrationals, where
/// any display-fitting answer is unverifiable anyway.
fn renderFract(arena: std.mem.Allocator, x: f64, w_in: usize) Error![]const u8 {
    const w = if (w_in == 0) 10 else w_in; // doc default 10
    if (std.math.isNan(x)) return justRight(arena, try arena.dupe(u8, &[_]u8{Value.missingChar(x)}), w);
    const ax = @abs(x);
    const neg = x < 0;
    // Display budget: [-]p/q must fit w. Beyond 1e30 even `n/1` overflows w ≤ 32.
    const dispCap = struct {
        fn f(p: u128, q: u128, s: bool, width: usize) bool {
            var pb: [40]u8 = undefined;
            const ps = std.fmt.bufPrint(&pb, "{d}", .{p}) catch unreachable;
            var qb: [40]u8 = undefined;
            const qs = std.fmt.bufPrint(&qb, "{d}", .{q}) catch unreachable;
            return @as(usize, @intFromBool(s)) + ps.len + 1 + qs.len <= width;
        }
    }.f;
    var best_p: u128 = 0;
    var best_q: u128 = 1;
    var best_err: f64 = ax;
    // `0/1` — the always-simplest candidate (skipped for huge |x|, where no
    // fraction can fit and showing 0/1 for 1e300 would be silently wrong).
    var have_best = ax < 1.0e30 and dispCap(0, 1, neg, w);
    if (ax < 1.0e30) {
        var p_im2: u128 = 0;
        var p_im1: u128 = 1;
        var q_im2: u128 = 1;
        var q_im1: u128 = 0;
        var cf = ax;
        var iter: usize = 0;
        while (iter < 256 and std.math.isFinite(cf) and best_err > 0) : (iter += 1) {
            const a_f = @floor(cf);
            if (a_f > 1.0e18) break; // quotient beyond f64 precision — noise
            const a: u128 = @intFromFloat(a_f);
            // Largest semiconvergent index i ∈ [1,a] with p(i)/q(i) display-fitting.
            // p,q grow monotonically in i ⇒ binary search; caps keep u128 safe.
            const qcap: u128 = 10_000_000_000_000_000_000_000_000_000_000; // 1e31
            var i_max: u128 = a;
            if (q_im1 > 0) i_max = @min(i_max, (qcap - q_im2) / q_im1);
            if (p_im1 > 0) i_max = @min(i_max, (qcap - p_im2) / p_im1);
            var lo: u128 = 1;
            var hi: u128 = i_max;
            var take: u128 = 0;
            while (lo <= hi) {
                const mid = lo + (hi - lo) / 2;
                if (dispCap(mid * p_im1 + p_im2, mid * q_im1 + q_im2, neg, w)) {
                    take = mid;
                    lo = mid + 1;
                } else hi = mid - 1;
            }
            if (take > 0) {
                const cp = take * p_im1 + p_im2;
                const cq = take * q_im1 + q_im2;
                const err = @abs(ax - @as(f64, @floatFromInt(cp)) / @as(f64, @floatFromInt(cq)));
                if (!have_best or err < best_err) {
                    best_p = cp;
                    best_q = cq;
                    best_err = err;
                    have_best = true;
                }
            }
            if (take < a or cf == a_f) break; // display exhausted, or CF terminates
            const pn = a * p_im1 + p_im2;
            const qn = a * q_im1 + q_im2;
            p_im2 = p_im1;
            p_im1 = pn;
            q_im2 = q_im1;
            q_im1 = qn;
            cf = 1.0 / (cf - a_f);
        }
    }
    // The plain-integer rendering competes on error (the fraction wins ties):
    // an integer value whose `n/1` overflows the field prints as the exact
    // integer rather than a coarser inexact fraction (123456 fract7. → 123456,
    // not 99999/1).
    if (try buildFixed(arena, x, 0, false, false)) |ibody| {
        if (w == 0 or ibody.len <= w) {
            const ierr = @abs(ax - @as(f64, @floatFromInt(scaledRoundExact(ax, 0) orelse 0)));
            if (!have_best or ierr < best_err) return justRight(arena, ibody, w);
        }
    }
    if (have_best) {
        const body = if (neg)
            try std.fmt.allocPrint(arena, "-{d}/{d}", .{ best_p, best_q })
        else
            try std.fmt.allocPrint(arena, "{d}/{d}", .{ best_p, best_q });
        return justRight(arena, body, w);
    }
    if (w > 0) return stars(arena, w); // nothing fits the field (SAS overflow)
    return bestNumW(arena, x, 0); // `fract.` with w never set — unreachable (default 10)
}

/// Dw.p — fixed-point with decimal points aligned in magnitude groups (SAS 9.4
/// Formats Reference, Dw.p Format p.170: default w 12, range 1–32; p default 3,
/// range 0–16, "if p is omitted or is specified as 0, then p is set to 3").
/// The doc's six d10.4 rows pin the rule: decimals d = w−1−p·(⌊m/p⌋+1) where
/// m = integer digits of |x| (0 for |x| < 1) — 12345./1234.5 (m ≥ p) → 1 decimal,
/// everything smaller → 5, right-justified in w. d gone negative (huge m) clamps
/// to 0 — undocumented; renderNum then shrinks to fit the field as usual.
fn renderD(arena: std.mem.Allocator, x: f64, w_in: usize, p_in: usize) Error![]const u8 {
    const w = if (w_in == 0) 12 else w_in; // doc default 12
    const p = if (p_in == 0) 3 else p_in; // doc: omitted or 0 → 3
    if (std.math.isNan(x) or !std.math.isFinite(x)) return renderNum(arena, x, w, 0, false, false, false);
    // m = digits of the integer part (0 for |x| < 1), via log10 with a pow10
    // fixup so exact powers of ten land on the right side.
    const ax = @abs(x);
    var m: usize = 0;
    if (ax >= 1) {
        m = @intFromFloat(@max(0, @floor(std.math.log10(ax))) + 1);
        var lo: f64 = 1;
        for (0..m - 1) |_| lo *= 10;
        while (ax < lo) {
            m -= 1;
            lo /= 10;
        }
        while (ax >= lo * 10) {
            m += 1;
            lo *= 10;
        }
    }
    const d_i: i64 = @as(i64, @intCast(w)) - 1 - @as(i64, @intCast(p)) * @as(i64, @intCast(m / p + 1));
    const d: usize = @intCast(@max(0, d_i));
    return renderNum(arena, x, w, d, false, false, false);
}

/// NEGPARENw.d — comma-grouped magnitude; a negative value is wrapped in
/// parentheses `(1,234)`, a positive value reserves the last column (a trailing
/// blank) for the close-paren it doesn't print, so a column of mixed-sign values
/// lines up on the paren. Right-justified in `w` (BUG-fmtxnlneg).
fn renderNegParen(arena: std.mem.Allocator, x: f64, w: usize, d_in: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    // Fit ladder (BUG-percentfit): reduce decimals until the parenthesized /
    // blank-padded body fits `w`; then BESTw/Ew like renderNum; still too wide
    // → asterisk-fill like SAS, never overflow the field.
    var d: usize = @min(d_in, 15);
    while (true) : (d -= 1) {
        if (try buildFixed(arena, @abs(x), d, true, false)) |mag| {
            var body: std.ArrayList(u8) = .empty;
            if (x < 0) {
                try body.append(arena, '(');
                try body.appendSlice(arena, mag);
                try body.append(arena, ')');
            } else {
                try body.appendSlice(arena, mag);
                if (w > 0) try body.append(arena, ' '); // reserve the absent close-paren column
            }
            if (w == 0 or body.items.len <= w) return justRight(arena, body.items, w);
        } else {
            // Too big for the integer path → BEST/E sized to the field.
            const best = try bestNumW(arena, x, w);
            if (w == 0 or best.len <= w) return justRight(arena, best, w);
            break;
        }
        if (d == 0) break;
    }
    return stars(arena, w);
}

const DateStyle = enum { date, mmddyy, ddmmyy, yymmdd };

fn renderDate(arena: std.mem.Allocator, x: f64, w: usize, style: DateStyle) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    // Outside the displayable date range (roughly years 1–9999) fall back to a
    // plain number — guards both @intFromFloat below and the u32 year cast.
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ymd = civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
    // Below the format's minimum width nothing fits → all asterisks (SAS 9.4
    // Formats ref: DATEw. range 5-9, MMDDYYw./DDMMYYw./YYMMDDw. range 2-10).
    const min_w: usize = if (style == .date) 5 else 2;
    if (w > 0 and w < min_w) return stars(arena, w);
    // 4-digit year at the wide widths (DATE9 / MMDDYY10), else 2-digit. Built by
    // hand: `{d:0>4}` on a signed year prints a stray '+'.
    const four_digit_year = switch (style) {
        .date => w == 9 or w >= 11, // w≥10's hyphens cost 2 cols → 4-digit year at w≥11
        .mmddyy, .ddmmyy, .yymmdd => w >= 10,
    };
    const yr: u32 = @intCast(if (four_digit_year) ymd.y else @mod(ymd.y, 100));
    // Width ladder (BUG-fmtdatewidth): narrow widths drop trailing components,
    // then separators. w=0 (no width given) = the default full form.
    //   MMDDYY/DDMMYY: w2-3 first part, w4 +second, w5 separated pair,
    //   w6-7 compact 6-char (no separators), w8+ separated. YYMMDD: same
    //   ladder with '-' and year first. DATE: w5-6 ddMMM, w7+ ddMMMyy(yy),
    //   w≥10 hyphenated (BUG-putdate11).
    var body: std.ArrayList(u8) = .empty;
    switch (style) {
        .date => { // ddMMMyy(yy); w≥10 → hyphenated dd-MMM-yy(yy) (BUG-putdate11)
            const hyph = w >= 10;
            try appendPadded(arena, &body, ymd.d, 2);
            if (hyph) try body.append(arena, '-');
            try body.appendSlice(arena, months[ymd.m - 1]);
            if (w == 0 or w >= 7) {
                if (hyph) try body.append(arena, '-');
                try appendPadded(arena, &body, yr, if (four_digit_year) 4 else 2);
            }
        },
        .mmddyy, .ddmmyy => { // mm/dd/yy(yy) or dd/mm/yy(yy)
            const first = if (style == .mmddyy) ymd.m else ymd.d;
            const second = if (style == .mmddyy) ymd.d else ymd.m;
            try appendPadded(arena, &body, first, 2);
            if (w == 0 or w >= 4) {
                if (w == 0 or w == 5 or w >= 8) try body.append(arena, '/');
                try appendPadded(arena, &body, second, 2);
            }
            if (w == 0 or w >= 6) {
                if (w == 0 or w >= 8) try body.append(arena, '/');
                try appendPadded(arena, &body, yr, if (four_digit_year) 4 else 2);
            }
        },
        .yymmdd => { // yy(yy)-mm-dd
            try appendPadded(arena, &body, yr, if (four_digit_year) 4 else 2);
            if (w == 0 or w >= 4) {
                if (w == 0 or w == 5 or w >= 8) try body.append(arena, '-');
                try appendPadded(arena, &body, ymd.m, 2);
            }
            if (w == 0 or w >= 6) {
                if (w == 0 or w >= 8) try body.append(arena, '-');
                try appendPadded(arena, &body, ymd.d, 2);
            }
        },
    }
    return justRight(arena, body.items, w);
}

/// YYMMDDxw. — year-month-day with a suffix-selected separator (`sep`); `null`
/// sep is the N variant (no separators → `yyyymmdd` when it fits). The N variant
/// takes a 4-digit year at w≥8 (default 8); the separated variants only at w≥10,
/// matching base YYMMDD.
fn renderYymmddX(arena: std.mem.Allocator, x: f64, w: usize, sep: ?u8) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ymd = civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
    const four = if (sep == null) (w == 0 or w >= 8) else (w >= 10);
    const yr: u32 = @intCast(if (four) ymd.y else @mod(ymd.y, 100));
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, yr, if (four) 4 else 2);
    if (sep) |c| try body.append(arena, c);
    try appendPadded(arena, &body, ymd.m, 2);
    if (sep) |c| try body.append(arena, c);
    try appendPadded(arena, &body, ymd.d, 2);
    return justRight(arena, body.items, w);
}

/// WORDDATEw. — `Month d, yyyy` (full month name, no leading zero on the day).
fn renderWordDate(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ymd = civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
    const s = try std.fmt.allocPrint(arena, "{s} {d}, {d}", .{ full_months[ymd.m - 1], ymd.d, ymd.y });
    return justRight(arena, s, w);
}

/// WEEKDATEw. — the day of week and date, "Saturday, July 4, 2020" (default w=29).
/// ponytail: full form at w≥29/none, the 3-letter day at w 3–8; the middle widths
/// use an abbreviated form truncated to fit rather than SAS's exact per-width ladder.
fn renderWeekDate(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const sasday = @as(i64, @intFromFloat(xr));
    const ymd = civilFromDays(sasday - unix_epoch_sas_day);
    const dow: usize = @intCast(@mod(sasday + 5, 7)); // SAS day 0 is a Friday
    const full = try std.fmt.allocPrint(arena, "{s}, {s} {d}, {d}", .{ day_names[dow], full_months[ymd.m - 1], ymd.d, ymd.y });
    if (w == 0 or w >= full.len) return justRight(arena, full, w);
    if (w <= 8) return justRight(arena, day_names[dow][0..3], w); // just the day, abbreviated
    const abbr = try std.fmt.allocPrint(arena, "{s}, {s} {d}, {d}", .{ day_names[dow][0..3], full_months[ymd.m - 1][0..3], ymd.d, ymd.y });
    return justRight(arena, abbr[0..@min(abbr.len, w)], w);
}

/// WEEKDATXw. — day-of-week then day-before-month: "Thursday, 16 January 2020".
fn renderWeekDatx(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max)) return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const sasday = @as(i64, @intFromFloat(xr));
    const ymd = civilFromDays(sasday - unix_epoch_sas_day);
    const dow: usize = @intCast(@mod(sasday + 5, 7));
    const full = try std.fmt.allocPrint(arena, "{s}, {d} {s} {d}", .{ day_names[dow], ymd.d, full_months[ymd.m - 1], ymd.y });
    if (w != 0 and w <= 8) return justRight(arena, day_names[dow][0..3], w);
    return justRight(arena, full, w);
}

/// WORDDATXw. — day before month: "16 January 2020".
fn renderWordDatx(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    return justRight(arena, try std.fmt.allocPrint(arena, "{d} {s} {d}", .{ ymd.d, full_months[ymd.m - 1], ymd.y }), w);
}

/// JULIANw. — `yyddd` (w≤5) or `yyyyddd` (w≥7): 16JAN2020 → 20016 / 2020016.
fn renderJulian(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max)) return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ymd = civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
    const doy = @as(i64, @intFromFloat(xr)) - (daysFromCivil(ymd.y, 1, 1) + sas_epoch_days) + 1;
    const four = w == 0 or w >= 7;
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    try appendPadded(arena, &body, @intCast(doy), 3);
    return justRight(arena, body.items, w);
}

/// QTRw. — the quarter (1–4), or roman (I–IV) for QTRR.
fn renderQtr(arena: std.mem.Allocator, x: f64, w: usize, roman: bool) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const q: usize = @intCast(@divTrunc(ymd.m - 1, 3) + 1); // 1..4
    if (roman) return justRight(arena, ([_][]const u8{ "I", "II", "III", "IV" })[q - 1], w);
    return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{q}), w);
}

/// YYQw. / YYQCw. — `yyyy<sep>q` (w≥6) or `yy<sep>q`: 2020Q1 / 2020:1.
fn renderYyq(arena: std.mem.Allocator, x: f64, w: usize, sep: u8) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const q = @divTrunc(ymd.m - 1, 3) + 1;
    var body: std.ArrayList(u8) = .empty;
    const four = w == 0 or w >= 6;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    try body.append(arena, sep);
    try appendPadded(arena, &body, @intCast(q), 1);
    return justRight(arena, body.items, w);
}

/// YYMMNw. — `yyyymm` with no separator (16JAN2020 → 202001).
fn renderYymmn(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    var body: std.ArrayList(u8) = .empty;
    const four = w == 0 or w >= 6;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    try appendPadded(arena, &body, @intCast(ymd.m), 2);
    return justRight(arena, body.items, w);
}

/// YYMMw. / MMYYw. and their separator variants (GAP-fmtyymm) — `<yyyy|yy><sep><mm>`
/// (YYMM) or `<mm><sep><yyyy|yy>` (MMYY). The base format's separator is the literal
/// letter `M` (01MAR2020 → `2020M03` / `03M2020`); the xw. variants swap it: C=`:`,
/// D=`-`, P=`.`, S=`/`, N=none. A 4-digit year needs the full-width field — w≥7 with
/// a 1-char separator, w≥6 for the separator-less N form (matching renderYymmn's rule;
/// default w 7 ⇒ 4-digit). SAS 9.4 "YYMMw./MMYYw. Format".
fn renderYymm(arena: std.mem.Allocator, x: f64, w: usize, sep: ?u8, month_first: bool) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const four = w == 0 or w >= (if (sep == null) @as(usize, 6) else 7);
    const year: u32 = @intCast(if (four) ymd.y else @mod(ymd.y, 100));
    var body: std.ArrayList(u8) = .empty;
    if (month_first) {
        try appendPadded(arena, &body, ymd.m, 2);
        if (sep) |s| try body.append(arena, s);
        try appendPadded(arena, &body, year, if (four) 4 else 2);
    } else {
        try appendPadded(arena, &body, year, if (four) 4 else 2);
        if (sep) |s| try body.append(arena, s);
        try appendPadded(arena, &body, ymd.m, 2);
    }
    return justRight(arena, body.items, w);
}

const DatePart = enum { weekday, month, day };

/// WEEKDAYw. (1=Sun..7=Sat) / MONTHw. (1–12) / DAYw. (1–31) — a right-justified number.
fn renderDatePart(arena: std.mem.Allocator, x: f64, w: usize, part: DatePart) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max)) return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ymd = civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
    const n: i64 = switch (part) {
        .weekday => @as(i64, @intCast(@mod(@as(i64, @intFromFloat(xr)) + 5, 7))) + 1, // 1=Sunday
        .month => ymd.m,
        .day => ymd.d,
    };
    return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{n}), w);
}

/// TIMEw.d — a SAS time (seconds since midnight) as hh:mm:ss<.ff>, right-justified.
/// Hours are not capped at 24 (SAS time deltas can exceed a day). Width ladder
/// (BUG-fmttimewidth): w 2–4 → hh, w 5–7 → hh:mm, w ≥ 8 → hh:mm:ss (a component
/// is shown only whole, never truncated mid-field); d appends `.ff` fractional
/// seconds when they fit (w ≥ 9+d). w=0 (no width given) = the full form.
/// TIMEw.d and siblings. `zero_pad_hour` distinguishes the two hour conventions
/// that share this body: SAS TIME/NLTIME BLANK-pad a single-digit leading hour
/// (` 9:05:00`, matching TIMEAMPM/HHMM — justRight supplies the blank), while ISO
/// E8601TM and TOD zero-pad to 2 digits (`09:05:00`). TOD used to be listed on the
/// blank-pad side here; Language Reference: Concepts' format tables contradict that, printing `TIME. 19434
/// -> 5:23:54` next to `TOD. 19434 -> 05:23:54` (printed p.147 and p.150) —
/// NOTE-todhourpad. Minutes/seconds are always
/// 2-digit zero-padded. Component inclusion is fit-based off the actual hour width:
/// with a 1-digit hour, `h:mm:ss` (7 chars) fits TIME7 and its seconds render, where
/// a zero-padded `01:01:01` (8) would overflow and drop them. Capped at 2 digits so a
/// 2-/3-digit hour keeps the historic width-5 (mm) / width-8 (ss) thresholds exactly.
fn renderTime(arena: std.mem.Allocator, x: f64, w: usize, d: usize, zero_pad_hour: bool) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    if (!(x > -1.0e11 and x < 1.0e11)) // guard @intFromFloat; covers every real time
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ax = @abs(x);
    var total: i64 = @intFromFloat(@floor(ax));
    // ponytail: fraction capped at 6 digits (µs) — keeps pow10 in exact-f64 range.
    const dd: usize = @min(d, 6);
    const p10 = pow10f(@intCast(dd));
    var frac: i64 = @intFromFloat(@round((ax - @floor(ax)) * p10));
    if (@as(f64, @floatFromInt(frac)) >= p10) { // rounding carried into the seconds
        total += 1;
        frac = 0;
    }
    var body: std.ArrayList(u8) = .empty;
    if (x < 0) try body.append(arena, '-');
    const hstart = body.items.len;
    if (zero_pad_hour) // ISO hh (≥2 digits, zero-padded), same path the old code used for all
        try appendPadded(arena, &body, @intCast(@divFloor(total, 3600)), 2)
    else // SAS h (no zero-pad; a single-digit hour is blank-padded by justRight)
        try body.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{@divFloor(total, 3600)}));
    const hlen = body.items.len - hstart; // hour digit count (sign excluded), capped at 2 below
    if (w == 0 or w >= @min(hlen + 3, 5)) {
        try body.append(arena, ':');
        try appendPadded(arena, &body, @intCast(@divFloor(@mod(total, 3600), 60)), 2); // mm
    }
    if (w == 0 or w >= @min(hlen + 6, 8)) {
        try body.append(arena, ':');
        try appendPadded(arena, &body, @intCast(@mod(total, 60)), 2); // ss
        if (dd > 0 and (w == 0 or body.items.len + 1 + dd <= w)) {
            try body.append(arena, '.');
            try appendPadded(arena, &body, @intCast(frac), dd);
        }
    }
    return justRight(arena, body.items, w);
}

const day_names = [_][]const u8{ "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday" };

/// datepart(): a SAS datetime (seconds since 1960) → its SAS day number. NaN passes
/// through (the date renderers print "." for a missing value).
fn datePartOf(x: f64) f64 {
    return @floor(x / 86400.0);
}

/// Civil y/m/d for a SAS date, or null when out of the displayable range.
fn ymdFromSasDay(x: f64) ?Ymd {
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max)) return null;
    return civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
}

/// MONYYw. — `MONYYYY` (`DEC2024`) at w≥7, else `MONYY` (`DEC24`).
fn renderMonyy(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(arena, months[ymd.m - 1]);
    const four = w == 0 or w >= 7;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    return justRight(arena, body.items, w);
}

/// MONNAMEw. — the full month name in a w-wide field (value left, blank-padded
/// right; truncated when longer). renderChar is exactly that pad/truncate.
fn renderMonName(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    return renderChar(arena, full_months[ymd.m - 1], w);
}

/// DOWNAMEw. — the weekday name (SAS day 0 = 1960-01-01 = Friday), same field rule.
fn renderDowName(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const dow: usize = @intCast(@mod(@as(i64, @intFromFloat(xr)) + 5, 7)); // +5: SAS day 0 is Friday
    return renderChar(arena, day_names[dow], w);
}

/// YEARw. — the year, w digits (4-digit at w≥4, else 2-digit), right-justified.
fn renderYear(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    var body: std.ArrayList(u8) = .empty;
    const four = w == 0 or w >= 4;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    return justRight(arena, body.items, w);
}

/// DATETIMEw.d — a SAS datetime (seconds since 1960-01-01) as
/// `ddMMMyy(yy):hh:mm:ss<.ff>` (4-digit year at w≥18). Width ladder
/// (BUG-fmttimewidth): against the 2-digit-year form, :hh from w≥10, :mm from
/// w≥13 (`datetime13.` → `17MAR13:14:45`), :ss from w≥16; a 4-digit year eats 2
/// columns first. d appends fractional seconds when they fit. w=0 = full form.
fn renderDatetime(arena: std.mem.Allocator, x: f64, w: usize, d: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    if (!(x > -3.0e12 and x < 3.0e12))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const fx = @floor(x);
    var total: i64 = @intFromFloat(fx);
    const dd: usize = @min(d, 6); // ponytail: µs cap, same as renderTime
    const p10 = pow10f(@intCast(dd));
    var frac: i64 = @intFromFloat(@round((x - fx) * p10));
    if (@as(f64, @floatFromInt(frac)) >= p10) { // rounding carried into the seconds
        total += 1;
        frac = 0;
    }
    const day = @divFloor(total, 86400);
    const secs = total - day * 86400; // 0..86399
    const ymd = civilFromDays(day - unix_epoch_sas_day);
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, ymd.d, 2);
    try body.appendSlice(arena, months[ymd.m - 1]);
    const four = w == 0 or w >= 18;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    const ww = if (four and w > 0) w - 2 else w; // 4-digit year eats 2 columns
    if (w == 0 or ww >= 10) {
        try body.append(arena, ':');
        try appendPadded(arena, &body, @intCast(@divFloor(secs, 3600)), 2);
    }
    if (w == 0 or ww >= 13) {
        try body.append(arena, ':');
        try appendPadded(arena, &body, @intCast(@divFloor(@mod(secs, 3600), 60)), 2);
    }
    if (w == 0 or ww >= 16) {
        try body.append(arena, ':');
        try appendPadded(arena, &body, @intCast(@mod(secs, 60)), 2);
        if (dd > 0 and (w == 0 or body.items.len + 1 + dd <= w)) {
            try body.append(arena, '.');
            try appendPadded(arena, &body, @intCast(frac), dd);
        }
    }
    return justRight(arena, body.items, w);
}

/// E8601DTw. — a SAS datetime (seconds since 1960-01-01) as ISO 8601 extended
/// `yyyy-mm-ddThh:mm:ss` (w defaults to 19; fractional seconds not rendered).
fn renderE8601Dt(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 19 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -3.0e12 and x < 3.0e12))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(x));
    const day = @divFloor(total, 86400);
    const secs = total - day * 86400; // 0..86399
    const ymd = civilFromDays(day - unix_epoch_sas_day);
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, @intCast(ymd.y), 4);
    try body.append(arena, '-');
    try appendPadded(arena, &body, ymd.m, 2);
    try body.append(arena, '-');
    try appendPadded(arena, &body, ymd.d, 2);
    try body.append(arena, 'T');
    try appendPadded(arena, &body, @intCast(@divFloor(secs, 3600)), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@divFloor(@mod(secs, 3600), 60)), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@mod(secs, 60)), 2);
    return justRight(arena, body.items, width);
}

/// B8601DTw. — a SAS datetime as ISO 8601 BASIC `yyyymmddThhmmss` (no
/// separators, GAP-fmtwritebatch). Default w 15. ponytail: no fractional seconds
/// (SAS's default w 26 includes `.ffffff`); add when a program needs sub-second.
fn renderB8601Dt(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 15 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -3.0e12 and x < 3.0e12))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(x));
    const day = @divFloor(total, 86400);
    const secs = total - day * 86400; // 0..86399
    const ymd = civilFromDays(day - unix_epoch_sas_day);
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, @intCast(ymd.y), 4);
    try appendPadded(arena, &body, ymd.m, 2);
    try appendPadded(arena, &body, ymd.d, 2);
    try body.append(arena, 'T');
    try appendPadded(arena, &body, @intCast(@divFloor(secs, 3600)), 2);
    try appendPadded(arena, &body, @intCast(@divFloor(@mod(secs, 3600), 60)), 2);
    try appendPadded(arena, &body, @intCast(@mod(secs, 60)), 2);
    return justRight(arena, body.items, width);
}

/// B8601TMw. — a SAS time as ISO 8601 BASIC `hhmmss` (GAP-fmtwritebatch).
/// Default w 8. Hours are not capped at 24 (same as TIMEw.). ponytail: no
/// fractional seconds.
fn renderB8601Tm(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 8 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(@abs(x)));
    var body: std.ArrayList(u8) = .empty;
    if (x < 0) try body.append(arena, '-');
    try appendPadded(arena, &body, @intCast(@divFloor(total, 3600)), 2);
    try appendPadded(arena, &body, @intCast(@divFloor(@mod(total, 3600), 60)), 2);
    try appendPadded(arena, &body, @intCast(@mod(total, 60)), 2);
    return justRight(arena, body.items, width);
}

/// YYMONw. — `yyyyMON` (19434 → `2013MAR`, Language Reference: Concepts p.148) at w≥7 (default 7),
/// `yyMON` below.
fn renderYymon(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const ymd = ymdFromSasDay(x) orelse return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    var body: std.ArrayList(u8) = .empty;
    const four = w == 0 or w >= 7;
    try appendPadded(arena, &body, @intCast(if (four) ymd.y else @mod(ymd.y, 100)), if (four) 4 else 2);
    try body.appendSlice(arena, months[ymd.m - 1]);
    return justRight(arena, body.items, w);
}

/// JULDAYw. — the day-of-year as a number (19434 → 76, Language Reference: Concepts p.146).
fn renderJulday(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const ymd = civilFromDays(@as(i64, @intFromFloat(xr)) - unix_epoch_sas_day);
    const doy = @as(i64, @intFromFloat(xr)) - (daysFromCivil(ymd.y, 1, 1) + sas_epoch_days) + 1;
    return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{doy}), w);
}

// ── NENGOw. (GAP-fmtwrite-unimpl) ──────────────────────────────────────────

const NengoEra = struct { start: i64, base: i64, letter: u8 };
/// Japanese imperial era boundaries as SAS dates (historical fact; the five
/// eras are named in the NENGOw. entry, p.257).
const nengo_eras = [_]NengoEra{
    .{ .start = daysFromCivil(1868, 9, 8) + sas_epoch_days, .base = 1868, .letter = 'M' }, // Meiji
    .{ .start = daysFromCivil(1912, 7, 30) + sas_epoch_days, .base = 1912, .letter = 'T' }, // Taisho
    .{ .start = daysFromCivil(1926, 12, 25) + sas_epoch_days, .base = 1926, .letter = 'S' }, // Showa
    .{ .start = daysFromCivil(1989, 1, 8) + sas_epoch_days, .base = 1989, .letter = 'H' }, // Heisei
    .{ .start = daysFromCivil(2019, 5, 1) + sas_epoch_days, .base = 2019, .letter = 'R' }, // Reiwa
};

/// NENGOw. — a SAS date as a Japanese era date `e.yymmdd` (SAS 9.4 Formats and
/// Informats Reference p.257: Default w 10, Range 2–10, Alignment Left; "If the
/// width is too small, SAS omits the period"). `e` is the era name's first
/// letter, `yy` the year OF THE ERA. The entry's own example (15342 = 02JAN2002
/// = Heisei 14) pins the width ladder — w10 `H.14/01/02`, w9 `H14/01/02`, w8
/// `H.140102`, w6 `H14/01`, w3 `H14` — reproduced below as an ordered candidate
/// list, longest fitting wins; the unexemplified w7/w5/w4/w2 rungs interpolate
/// the same list (doc shows no output for them). A date before the Meiji era
/// (doc silent) fills the field with `*`, the SAS cannot-represent idiom —
/// never a fabricated era letter.
fn renderNengo(arena: std.mem.Allocator, x: f64, w_in: usize) Error![]const u8 {
    const w = if (w_in == 0) 10 else w_in;
    if (std.math.isNan(x)) return justLeft(arena, ".", w);
    const xr = @round(x);
    if (!(xr >= sas_day_min and xr <= sas_day_max))
        return justLeft(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const day: i64 = @intFromFloat(xr);
    if (day < nengo_eras[0].start) return stars(arena, w); // pre-Meiji: doc silent
    var era = nengo_eras[0];
    for (nengo_eras[1..]) |e| {
        if (day >= e.start) era = e;
    }
    const ymd = civilFromDays(day - unix_epoch_sas_day);
    const yy: u64 = @intCast(ymd.y - era.base + 1);
    var ybuf: [24]u8 = undefined;
    const ys = std.fmt.bufPrint(&ybuf, "{d:0>2}", .{yy}) catch unreachable;
    var mbuf: [8]u8 = undefined;
    const ms = std.fmt.bufPrint(&mbuf, "{d:0>2}", .{ymd.m}) catch unreachable;
    var dbuf: [8]u8 = undefined;
    const ds = std.fmt.bufPrint(&dbuf, "{d:0>2}", .{ymd.d}) catch unreachable;
    if (w == 2) { // doc silent: era letter + the year's leading digit
        return try std.fmt.allocPrint(arena, "{c}{c}", .{ era.letter, ys[0] });
    }
    // Candidate forms in doc-ladder order; mm/dd separator 0 = packed, null =
    // component dropped. First candidate that fits `w` wins.
    const Form = struct { dot: bool, mm: ?u8, dd: ?u8 };
    const forms = [_]Form{
        .{ .dot = true, .mm = '/', .dd = '/' }, // e.yy/mm/dd — w10 (doc)
        .{ .dot = false, .mm = '/', .dd = '/' }, // eyy/mm/dd  — w9  (doc)
        .{ .dot = true, .mm = 0, .dd = 0 }, // e.yymmdd     — w8  (doc)
        .{ .dot = false, .mm = 0, .dd = 0 }, // eyymmdd      — w7  (interp.)
        .{ .dot = true, .mm = '/', .dd = null }, // e.yy/mm
        .{ .dot = false, .mm = '/', .dd = null }, // eyy/mm    — w6  (doc)
        .{ .dot = true, .mm = 0, .dd = null }, // e.yymm
        .{ .dot = false, .mm = 0, .dd = null }, // eyymm       — w5  (interp.)
        .{ .dot = true, .mm = null, .dd = null }, // e.yy      — w4  (interp.)
        .{ .dot = false, .mm = null, .dd = null }, // eyy       — w3  (doc)
    };
    for (forms) |f| {
        var body: std.ArrayList(u8) = .empty;
        try body.append(arena, era.letter);
        if (f.dot) try body.append(arena, '.');
        try body.appendSlice(arena, ys);
        if (f.mm) |sep| {
            if (sep != 0) try body.append(arena, sep);
            try body.appendSlice(arena, ms);
            if (f.dd) |sep2| {
                if (sep2 != 0) try body.append(arena, sep2);
                try body.appendSlice(arena, ds);
            }
        }
        if (body.items.len <= w) return justLeft(arena, body.items, w);
    }
    return stars(arena, w); // only w==1 reaches here (doc Range 2–10)
}

/// DATEAMPMw. — a SAS datetime as `ddMMMyy:hh:mm:ss AM/PM` (1679097600 →
/// `17MAR13:12:00:00 AM`, Language Reference: Concepts p.150). Default w 19. ponytail: full form only;
/// SAS's narrow-width component-drop ladder is not implemented (a small w shows
/// the full form, like the other justRight overflow paths).
fn renderDateAmpm(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 19 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -3.0e12 and x < 3.0e12))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(x));
    const day = @divFloor(total, 86400);
    const secs = total - day * 86400; // 0..86399
    const ymd = civilFromDays(day - unix_epoch_sas_day);
    const h = @divFloor(secs, 3600);
    var h12 = @mod(h, 12);
    if (h12 == 0) h12 = 12;
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, ymd.d, 2);
    try body.appendSlice(arena, months[ymd.m - 1]);
    try appendPadded(arena, &body, @intCast(@mod(ymd.y, 100)), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(h12), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@divFloor(@mod(secs, 3600), 60)), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@mod(secs, 60)), 2);
    try body.append(arena, ' ');
    try body.appendSlice(arena, if (h >= 12) "PM" else "AM");
    return justRight(arena, body.items, width);
}

/// MMSSw. — a SAS time as `mm:ss`; minutes are the whole value's minute count
/// and may exceed 59. When `mm:ss` doesn't fit `w`, the minutes alone are
/// written (19434 s → `323` at the default w 5, Language Reference: Concepts p.150).
fn renderMmss(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 5 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(@abs(x)));
    const mm = @divFloor(total, 60);
    var body: std.ArrayList(u8) = .empty;
    if (x < 0) try body.append(arena, '-');
    try body.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{mm}));
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@mod(total, 60)), 2);
    if (body.items.len <= width) return justRight(arena, body.items, width);
    return justRight(arena, try std.fmt.allocPrint(arena, "{s}{d}", .{ if (x < 0) "-" else "", mm }), width);
}

const RomanNumeral = struct { v: u64, s: []const u8 };
const roman_numerals = [_]RomanNumeral{
    .{ .v = 1000, .s = "M" }, .{ .v = 900, .s = "CM" }, .{ .v = 500, .s = "D" }, .{ .v = 400, .s = "CD" },
    .{ .v = 100, .s = "C" },  .{ .v = 90, .s = "XC" },  .{ .v = 50, .s = "L" },  .{ .v = 40, .s = "XL" },
    .{ .v = 10, .s = "X" },   .{ .v = 9, .s = "IX" },   .{ .v = 5, .s = "V" },   .{ .v = 4, .s = "IV" }, .{ .v = 1, .s = "I" },
};

/// ROMANw. — a positive integer in Roman numerals (M repeated past 3999).
/// Non-integers are truncated toward zero; non-positive values render as plain
/// Arabic numbers (SAS leaves those unconverted). Default w 6.
fn renderRoman(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 6 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e15 and x < 1.0e15))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const n: i64 = @intFromFloat(@trunc(x));
    if (n <= 0) return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{n}), width);
    var rem: u64 = @intCast(n);
    var body: std.ArrayList(u8) = .empty;
    for (roman_numerals) |nm| while (rem >= nm.v) {
        try body.appendSlice(arena, nm.s);
        rem -= nm.v;
    };
    return justRight(arena, body.items, width);
}

const word_ones = [_][]const u8{ "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen" };
const word_tens = [_][]const u8{ "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety" };
const WordGroup = struct { v: u64, name: []const u8 };
const word_groups = [_]WordGroup{
    .{ .v = 1_000_000_000_000, .name = "trillion" }, .{ .v = 1_000_000_000, .name = "billion" },
    .{ .v = 1_000_000, .name = "million" },          .{ .v = 1_000, .name = "thousand" },
};

/// Spell a positive integer (< 1e15) in English words into `body`: lowercase, no
/// "and", hyphenated 21–99 (sas-functions-ref p.680: 2105 → "two thousand one
/// hundred five").
fn spellWords(arena: std.mem.Allocator, body: *std.ArrayList(u8), n_in: u64) Error!void {
    var n = n_in;
    var sep: []const u8 = "";
    for (word_groups) |g| {
        const q = n / g.v;
        if (q > 0) {
            try body.appendSlice(arena, sep);
            sep = " ";
            try spellWords(arena, body, q);
            try body.append(arena, ' ');
            try body.appendSlice(arena, g.name);
            n -= q * g.v;
        }
    }
    if (n >= 100) {
        try body.appendSlice(arena, sep);
        sep = " ";
        try body.appendSlice(arena, word_ones[@intCast(n / 100)]);
        try body.appendSlice(arena, " hundred");
        n %= 100;
    }
    if (n >= 20) {
        try body.appendSlice(arena, sep);
        try body.appendSlice(arena, word_tens[@intCast(n / 10)]);
        if (n % 10 > 0) {
            try body.append(arena, '-');
            try body.appendSlice(arena, word_ones[@intCast(n % 10)]);
        }
    } else if (n > 0) {
        try body.appendSlice(arena, sep);
        try body.appendSlice(arena, word_ones[@intCast(n)]);
    }
}

/// WORDSw. — a number in English words, LEFT-justified and truncated/padded to w
/// (a rare left-justified numeric format). Negatives get a leading "minus"; a
/// decimal part renders as "point" + digit words (−2.5 → "minus two point
/// five"). ponytail: |x| ≥ 1e15 → plain digits, and an E-notation-scale decimal
/// part stops at the exponent — the oracle (sas-functions-ref p.680) verifies
/// the integer form only.
fn renderWords(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return renderChar(arena, ".", w);
    if (!std.math.isFinite(x) or @abs(x) >= 1.0e15)
        return renderChar(arena, try bestNum(arena, x), w);
    var body: std.ArrayList(u8) = .empty;
    if (x < 0) try body.appendSlice(arena, "minus ");
    const int_part: u64 = @intFromFloat(@trunc(@abs(x)));
    if (int_part == 0) try body.appendSlice(arena, "zero") else try spellWords(arena, &body, int_part);
    const bs = try bestNum(arena, @abs(x));
    if (std.mem.indexOfScalar(u8, bs, '.')) |dot| {
        try body.appendSlice(arena, " point");
        for (bs[dot + 1 ..]) |c| {
            if (c < '0' or c > '9') break; // E-notation tail — stop at the exponent
            try body.append(arena, ' ');
            try body.appendSlice(arena, word_ones[c - '0']);
        }
    }
    return renderChar(arena, body.items, w);
}

/// NLDATMw. (en_US approximation, same house pattern as NLDATE→WORDDATE) —
/// `ddMONyyyy:hh:mm:ss` with a Title-case month (`04Jul2020:14:05:06`,
/// GAP-fmtwritebatch). Other locales are unimplemented; add when a program sets one.
fn renderNldatm(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    if (!(x > -3.0e12 and x < 3.0e12))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const total: i64 = @intFromFloat(@floor(x));
    const day = @divFloor(total, 86400);
    const secs = total - day * 86400; // 0..86399
    const ymd = civilFromDays(day - unix_epoch_sas_day);
    const mon = months[ymd.m - 1];
    const mbuf: [3]u8 = .{ mon[0], std.ascii.toLower(mon[1]), std.ascii.toLower(mon[2]) };
    var body: std.ArrayList(u8) = .empty;
    try appendPadded(arena, &body, ymd.d, 2);
    try body.appendSlice(arena, &mbuf);
    try appendPadded(arena, &body, @intCast(ymd.y), 4);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@divFloor(secs, 3600)), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@divFloor(@mod(secs, 3600), 60)), 2);
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@mod(secs, 60)), 2);
    return justRight(arena, body.items, w);
}

/// TIMEAMPMw. — a SAS time as 12-hour `h:mm:ss AM/PM` (seconds dropped at w<11).
fn renderTimeAmpm(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    const total: i64 = @intFromFloat(@floor(@abs(x)));
    const h = @divFloor(total, 3600);
    var h12 = @mod(h, 12);
    if (h12 == 0) h12 = 12;
    var body: std.ArrayList(u8) = .empty;
    try body.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{h12})); // hour, no leading zero
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@divFloor(@mod(total, 3600), 60)), 2);
    if (w == 0 or w >= 11) { // seconds
        try body.append(arena, ':');
        try appendPadded(arena, &body, @intCast(@mod(total, 60)), 2);
    }
    try body.append(arena, ' ');
    try body.appendSlice(arena, if (h >= 12) "PM" else "AM");
    return justRight(arena, body.items, w);
}

/// TODw.d — the time-of-day of a SAS datetime (its seconds-of-day) as `hh:mm:ss<.ff>`.
/// The hour is ZERO-padded to 2 digits, unlike TIME/TIMEAMPM/HHMM which blank-pad it
/// (NOTE-todhourpad). Language Reference: Concepts' format tables list the two side by side on the SAME
/// input — `TIME. 19434 -> 5:23:54` vs `TOD. 19434 -> 05:23:54` (printed p.147 "Time
/// formats" and again p.150 "Write SAS time values as time values"); the sibling rows
/// there (TIMEAMPM, HHMM, HOUR) all keep the bare single-digit hour, so TOD's leading
/// zero is deliberate. We blank-padded both.
/// `@mod` on the FLOAT (not `@floor` then integer `@mod`) keeps the sub-second part, so
/// a `.d` renders its fractional seconds and TOD rounds the way TIMEw.d already does —
/// the pre-floor made TODw.d silently incapable of `.ff` and split the two on rounding
/// (`5445.5` → TIME8. `1:30:46` but TOD8. `1:30:45`) (NOTE-todfloorfrac).
fn renderTod(arena: std.mem.Allocator, x: f64, w: usize, d: usize) Error![]const u8 {
    if (std.math.isNan(x)) return justRight(arena, ".", w);
    if (!(x > -3.0e12 and x < 3.0e12))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), w);
    return renderTime(arena, @mod(x, 86400.0), w, d, true);
}

/// HHMMw.d — a SAS time (seconds since midnight) as `hh:mm` (no seconds). Hour is
/// NOT zero-padded (SAS writes a leading blank for a single-digit hour); minute is
/// zero-padded to 2. Rounds to the nearest minute on the seconds (SAS). Default w 5.
/// ponytail: whole minutes only — the fractional-minute `.d` variant is not rendered;
/// add when a program needs sub-minute HHMM.
fn renderHhmm(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 5 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total_min: i64 = @intFromFloat(@round(@abs(x) / 60.0)); // nearest minute
    var body: std.ArrayList(u8) = .empty;
    if (x < 0) try body.append(arena, '-');
    try body.appendSlice(arena, try std.fmt.allocPrint(arena, "{d}", .{@divFloor(total_min, 60)})); // hh, no pad
    try body.append(arena, ':');
    try appendPadded(arena, &body, @intCast(@mod(total_min, 60)), 2); // mm
    return justRight(arena, body.items, width);
}

/// HOURw.d — the hour of a SAS time. d=0 → the integer hour, ROUNDED on the
/// fractional hour (minutes): `put 45000 hour.` (12h30m) → 13, `43200` (12h00m)
/// → 12. SAS 9.4 Formats Reference (HOUR format Details): "SAS rounds hours based
/// on the value of minutes in the SAS time value." d>0 → value/3600 with d
/// decimals (11.5). Default w 2. ponytail: no hour-of-day wrap (>24h prints as-is);
/// SAS uses asterisks for out-of-0–24-range values, a display nicety we skip.
fn renderHour(arena: std.mem.Allocator, x: f64, w: usize, d: usize) Error![]const u8 {
    const width = if (w == 0) 2 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    if (d > 0) return renderNum(arena, x / 3600.0, w, d, false, false, false);
    const h: i64 = @intFromFloat(@round(x / 3600.0));
    return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{h}), width);
}

/// MINUTEw. — the minute component (0–59) of a SAS time. Default w 2, blank-padded
/// (a component number, not zero-padded).
fn renderMinute(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 2 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(@abs(x)));
    return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{@divFloor(@mod(total, 3600), 60)}), width);
}

/// SECONDw. — the second component (0–59) of a SAS time. Default w 2, blank-padded.
fn renderSecond(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    const width = if (w == 0) 2 else w;
    if (std.math.isNan(x)) return justRight(arena, ".", width);
    if (!(x > -1.0e11 and x < 1.0e11))
        return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{x}), width);
    const total: i64 = @intFromFloat(@floor(@abs(x)));
    return justRight(arena, try std.fmt.allocPrint(arena, "{d}", .{@mod(total, 60)}), width);
}

/// BINARYw. — a numeric value's integer part in base-2, right-justified and
/// zero-padded to `w` bits (low `w` bits kept on overflow). Mirrors renderHexNum.
/// Non-finite → blanks. Negatives render as their two's-complement bit pattern
/// truncated to the field's `w` bits (SAS: -1 binary16. → sixteen 1s).
fn renderBinaryNum(arena: std.mem.Allocator, x: f64, w: usize) Error![]const u8 {
    if (!std.math.isFinite(x)) return renderChar(arena, "", w);
    // |x| >= 2^64 overflows the u64 cast → abort (BUG-fmtnumoverflow); clamp to
    // the field-full value (all-1 bits), matching renderHexNum.
    const overflow = @abs(x) >= 18446744073709551616.0;
    var v: u64 = if (overflow) std.math.maxInt(u64) else @intFromFloat(@trunc(@abs(x)));
    // In-range negatives → two's-complement, masked to the field's w bits (see
    // renderHexNum); overflowed values stay field-full (all-1s) either sign.
    if (w > 0) {
        if (x < 0 and !overflow) v = 0 -% v;
        if (w < 64) v &= (@as(u64, 1) << @intCast(w)) - 1;
    }
    var tmp: [64]u8 = undefined;
    var n: usize = 0;
    if (v == 0) {
        tmp[0] = '0';
        n = 1;
    } else while (v > 0 and n < tmp.len) : (n += 1) {
        tmp[n] = '0' + @as(u8, @intCast(v & 1));
        v >>= 1;
    }
    const width = if (w > 0) w else n;
    const out = try arena.alloc(u8, width);
    @memset(out, '0');
    var k: usize = 0;
    while (k < n and k < width) : (k += 1) out[width - 1 - k] = tmp[k]; // right-justified
    return out;
}

/// Append `n` zero-padded to at least `width` digits.
fn appendPadded(arena: std.mem.Allocator, body: *std.ArrayList(u8), n: u32, width: usize) Error!void {
    var buf: [10]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{d}", .{n}) catch unreachable;
    assert(s.len <= buf.len); // digits of a u32 (≤10) fit the [10]u8
    for (s.len..@max(s.len, width)) |_| try body.append(arena, '0'); // ponytail: content may exceed width (TIME ≥100h), never truncate
    try body.appendSlice(arena, s);
}

// ── helpers ──────────────────────────────────────────────────────────────

/// Right-justify `s` in width `w`, blank-padded on the left. Overflow (`s`
/// wider than `w`) returns `s` unchanged.
fn justRight(arena: std.mem.Allocator, s: []const u8, w: usize) Error![]const u8 {
    if (s.len >= w) return s;
    const out = try arena.alloc(u8, w);
    const pad = w - s.len;
    @memset(out[0..pad], ' ');
    @memcpy(out[pad..], s);
    return out;
}

/// Left-justify `s` in `w` (blank-pad right) — the NENGO/NL* entries say
/// "Alignment: Left" (GAP-fmtwrite-unimpl).
fn justLeft(arena: std.mem.Allocator, s: []const u8, w: usize) Error![]const u8 {
    if (w == 0 or s.len >= w) return s;
    const out = try arena.alloc(u8, w);
    @memcpy(out[0..s.len], s);
    @memset(out[s.len..], ' ');
    return out;
}

/// Like `justRight` but pads with `0`. A leading `-` stays leftmost, zeros go
/// after it: `-3.5` in width 8 → `-0003.50`.
fn justRightZero(arena: std.mem.Allocator, s: []const u8, w: usize) Error![]const u8 {
    if (s.len >= w) return s;
    const out = try arena.alloc(u8, w);
    const pad = w - s.len;
    if (s.len > 0 and s[0] == '-') {
        out[0] = '-';
        @memset(out[1 .. 1 + pad], '0');
        @memcpy(out[1 + pad ..], s[1..]);
    } else {
        @memset(out[0..pad], '0');
        @memcpy(out[pad..], s);
    }
    return out;
}

/// Append `digits` (an unsigned integer string) with `,` every three from the
/// right: "1234567" → "1,234,567".
fn appendGrouped(arena: std.mem.Allocator, body: *std.ArrayList(u8), digits: []const u8) Error!void {
    var lead = digits.len % 3;
    if (lead == 0) lead = 3;
    try body.appendSlice(arena, digits[0..lead]);
    var i = lead;
    while (i < digits.len) : (i += 3) {
        try body.append(arena, ',');
        try body.appendSlice(arena, digits[i .. i + 3]);
    }
}

fn valToNum(v: Value) f64 {
    return switch (v) {
        .num => |x| x,
        .str => |s| blk: {
            const tr = std.mem.trim(u8, s, " ");
            if (tr.len == 0) break :blk std.math.nan(f64);
            break :blk std.fmt.parseFloat(f64, tr) catch std.math.nan(f64);
        },
    };
}

fn valToStr(arena: std.mem.Allocator, v: Value) Error![]const u8 {
    return switch (v) {
        .str => |s| s,
        .num => |x| try bestNum(arena, x),
    };
}

/// SAS's default numeric format, BEST12. — a **12-column** field (not 12
/// significant digits). SAS shows the value with the most significant digits that
/// fit in w columns, choosing fixed or E-notation by whichever shows more (a tie
/// prefers fixed); trailing zeros are dropped. So `1/3` → `0.3333333333` (exactly
/// 12 chars), `0.1+0.2` → `0.3`, `123456789.12345` → `123456789.12`, and a value
/// too big/small for fixed → E-notation (`1e13` → `1E13`, `1e-11` → `1E-11`).
/// This is THE default num→string path; exec/eval/CSV renderers route here.
pub fn bestNum(arena: std.mem.Allocator, x: f64) Error![]const u8 {
    return bestNumW(arena, x, 12);
}

/// The BESTw. value: the most significant digits that fit in `w` columns (fixed or
/// E-notation), UNPADDED. Exposed so the `put(x, bestw.)` path reuses this instead
/// of printing the raw f64 (BESTFMT-explicit).
pub fn bestNumW(arena: std.mem.Allocator, x: f64, w_in: usize) Error![]const u8 {
    // SAS: a width of 0 means the format's DEFAULT width (BEST12.) — resolve it
    // BEFORE any width arithmetic, or `w - sign` underflows usize on a negative
    // value and aborts (BUG-bestnumwidth0). w ≥ 1 below, so `w - sign` ≥ 0.
    const w = if (w_in == 0) 12 else w_in;
    if (std.math.isNan(x)) return arena.dupe(u8, &[_]u8{Value.missingChar(x)}); // `.`/`A`-`Z`/`_`
    if (!std.math.isFinite(x)) return "."; // overflow ±inf
    if (x == 0) return "0";
    const sign: usize = if (x < 0) 1 else 0;
    const ax = @abs(x);
    // a whole number whose digits fit in the field → plain integer. Format the
    // f64 directly ({d} prints a whole double as a plain integer) — casting to
    // i64 first panicked for magnitudes ≥ 2^63 that still fit the field at wide
    // w (e.g. `put(1e20, best32.)`) (BUG-bestint-i64-overflow).
    if (x == @trunc(x) and ax < pow10f(@intCast(w - sign)))
        return std.fmt.allocPrint(arena, "{d}", .{x});

    const e = @as(i32, @intFromFloat(@floor(@log10(ax)))); // decimal exponent
    const fixed = try fixedStr(arena, x, w, sign, e);
    const estr = try eStr(arena, x, w, sign, e);
    // pick the notation showing more significant digits; a tie prefers fixed
    if (fixed) |fs| return if (sigDigits(estr) > sigDigits(fs)) estr else fs;
    return estr;
}

/// Fixed-notation candidate within `w` columns, or null when the value can't be
/// shown in fixed form (integer part overflows, or it rounds away to 0).
fn fixedStr(arena: std.mem.Allocator, x: f64, w: usize, sign: usize, e: i32) Error!?[]const u8 {
    const int_digits: usize = if (e >= 0) @as(usize, @intCast(e)) + 1 else 1;
    if (int_digits + sign > w) return null; // integer part alone doesn't fit
    if (int_digits + sign + 1 > w) { // no room for '.' → rounded integer
        // Rounding can carry into an extra digit (999999999999.9 → 1e12), which
        // then overflows `w`; fall back to E-notation in that case (BESTFMT-edge).
        const s = try std.fmt.allocPrint(arena, "{d}", .{@round(x)});
        return if (s.len <= w) s else null;
    }
    const decimals = w - sign - int_digits - 1;
    const scale = pow10f(@intCast(decimals));
    const rounded = @round(x * scale) / scale;
    if (rounded == 0) return null; // too small to show any digit in fixed form
    return try std.fmt.allocPrint(arena, "{d}", .{rounded}); // {d} drops trailing zeros
}

/// E-notation candidate: `[-]m.mmmmE±xx`, mantissa filling the columns left after
/// the exponent. SAS drops a positive exponent's sign and trailing mantissa zeros.
fn eStr(arena: std.mem.Allocator, x: f64, w: usize, sign: usize, e_in: i32) Error![]const u8 {
    var e = e_in;
    var mant = x / pow10f(e);
    if (@abs(mant) >= 10) { // log10 rounding slop → renormalise
        e += 1;
        mant = x / pow10f(e);
    } else if (@abs(mant) < 1) {
        e -= 1;
        mant = x / pow10f(e);
    }
    var ebuf: [16]u8 = undefined;
    var es = std.fmt.bufPrint(&ebuf, "E{d}", .{e}) catch unreachable; // "E-11" / "E13"
    assert(es.len <= ebuf.len); // "E" + a small exponent fits the [16]u8
    const overhead = sign + 2 + es.len; // sign + "d." + exponent
    const decimals = if (w > overhead) w - overhead else 0;
    const scale = pow10f(@intCast(decimals));
    var rmant = @round(mant * scale) / scale;
    if (@abs(rmant) >= 10) { // rounding carried the mantissa to 10 → 10E13 becomes 1E14
        rmant /= 10;
        e += 1;
        es = std.fmt.bufPrint(&ebuf, "E{d}", .{e}) catch unreachable;
        assert(es.len <= ebuf.len); // renormalized exponent still fits the [16]u8
    }
    return std.fmt.allocPrint(arena, "{d}{s}", .{ rmant, es });
}

/// Count significant digits in a rendered number (skip sign/dot/leading zeros;
/// stop at the exponent marker).
fn sigDigits(s: []const u8) usize {
    var count: usize = 0;
    var started = false;
    for (s) |ch| {
        if (ch == 'E' or ch == 'e') break;
        if (ch >= '1' and ch <= '9') {
            started = true;
            count += 1;
        } else if (ch == '0' and started) count += 1;
    }
    return count;
}

fn pow10f(e: i32) f64 {
    // 10^0..10^22 are exactly representable in f64, and repeated multiply stays
    // exact through 10^22; 1.0/exact is a single correctly-rounded division. Past
    // ±22 naive `*= 10` drifts 1-2 ULP (pow10f(299)=1.0000000000000002e299),
    // which corrupts wide BEST/COMMA of extreme magnitudes (BUG-fmtextrememag).
    // For that tail, parse the literal — std.fmt.parseFloat is correctly rounded,
    // yielding the same f64 the compiler would for `1e<e>` (and a finite subnormal
    // for very negative e, subsuming the old BUG-subnormalfmt hand-rolled path).
    if (e >= 0 and e <= 22) {
        var r: f64 = 1;
        var n = e;
        while (n > 0) : (n -= 1) r *= 10;
        return r;
    }
    if (e < 0 and e >= -22) {
        var r: f64 = 1;
        var n = -e;
        while (n > 0) : (n -= 1) r *= 10;
        return 1.0 / r;
    }
    var buf: [16]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "1e{d}", .{e}) catch unreachable;
    return std.fmt.parseFloat(f64, s) catch unreachable;
}

fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

// SAS counts days from 1960-01-01; 1970-01-01 (the civil-from-days epoch) is
// SAS day 3653.
const unix_epoch_sas_day: i64 = 3653;
// Displayable SAS-date range: 01JAN0001 (mdy(1,1,1)) .. 31DEC9999 (mdy(12,31,9999)).
// These are this codebase's own mdy/civilFromDays endpoints (round-trip verified);
// a tighter clamp printed year-1 / year-9999 dates as raw day numbers (BUG-datefmtedge).
const sas_day_min: f64 = -715509;
const sas_day_max: f64 = 2936549;
const months = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
const full_months = [_][]const u8{ "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" };

const Ymd = struct { y: i64, m: u32, d: u32 };

/// Howard Hinnant's civil-from-days: `z` = days since 1970-01-01 → Y/M/D.
fn civilFromDays(z_in: i64) Ymd {
    const z = z_in + 719468;
    const era = @divFloor(if (z >= 0) z else z - 146096, 146097);
    const doe = z - era * 146097; // [0, 146096]
    const yoe = @divTrunc(doe - @divTrunc(doe, 1460) + @divTrunc(doe, 36524) - @divTrunc(doe, 146096), 365);
    const y = yoe + era * 400;
    const doy = doe - (365 * yoe + @divTrunc(yoe, 4) - @divTrunc(yoe, 100)); // [0, 365]
    const mp = @divTrunc(5 * doy + 2, 153); // [0, 11]
    const d = doy - @divTrunc(153 * mp + 2, 5) + 1; // [1, 31]
    const m = if (mp < 10) mp + 3 else mp - 9; // [1, 12]
    return .{ .y = if (m <= 2) y + 1 else y, .m = @intCast(m), .d = @intCast(d) };
}

// ── tests ────────────────────────────────────────────────────────────────

const t = std.testing;

fn expectFmt(expected: []const u8, x: Value, spec: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings(expected, try apply(arena.allocator(), x, spec));
}

test "Ew. scientific format + BEST rounding-overflow residual (BUG-eformat)" {
    // Ew. — fixed mantissa decimals (as many as fit in w), signed >=2-digit
    // exponent, trailing mantissa zeros kept, right-justified.
    try expectFmt("1.2340E+03", .{ .num = 1234 }, "e10.");
    try expectFmt("1.2346E+04", .{ .num = 12345.678 }, "e10.");
    try expectFmt("1.230000E-04", .{ .num = 0.000123 }, "e12.");
    try expectFmt("-1.23400E+03", .{ .num = -1234 }, "e12."); // sign eats one decimal
    try expectFmt("         .", Value.missing, "e10."); // missing → "." right-justified
    try expectFmt("1.23E+03", .{ .num = 1234 }, "e8.2"); // explicit Ew.d honours d

    // BEST: a non-integer rounding up to a 13-digit power of 10 must switch to
    // E-notation, not overflow to 13 chars (BESTFMT-edge residual).
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("1E12", try bestNum(a, 999999999999.9));
    try t.expectEqualStrings("1.2345679E12", try bestNum(a, 1234567890123));
}

test "BUG-fmtnumoverflow: HEX/BINARY/E guard huge + denormal doubles (no SIGABRT)" {
    // |x| >= 2^64 overflowed the u64 cast in renderHexNum(w<16)/renderBinaryNum
    // → abort on valid finite data. Now caps the field (all-F / all-1).
    try expectFmt("FFFFFFFF", .{ .num = 1e300 }, "hex8.");
    try expectFmt("FFFFFFFFFF", .{ .num = -1e250 }, "hex10.");
    try expectFmt("1111111111111111", .{ .num = 1e300 }, "binary16.");
    // small magnitudes still render their real value, not the cap.
    try expectFmt("000000FF", .{ .num = 255 }, "hex8.");
    // Ew. of the tiniest denormals: pow(10,exp) underflowed → mant=inf → OOB
    // cast. Finite-safe mantissa now renders without crashing (decimals reduced
    // to fit the field — BUG-percentfit).
    try expectFmt("4.9E-324", .{ .num = 5e-324 }, "e8.5");
}

test "BUG-percentfit: PERCENT/NEGPAREN/E reduce decimals, then asterisk-fill" {
    // SAS never overflows the field: percent6.2 of 123.456 drops to 0 decimals.
    try expectFmt("12346%", .{ .num = 123.456 }, "percent6.2");
    // in-width percent is byte-identical (right-justified, decimals kept).
    try expectFmt(" 12.3%", .{ .num = 0.1234 }, "percent6.1");
    try expectFmt("  (5.0%)", .{ .num = -0.05 }, "percent8.1");
    // negparen that can't fit even at d=0 → all asterisks.
    try expectFmt("******", .{ .num = 12345678 }, "negparen6.");
    // in-width negparen unchanged (parens for neg, reserved blank for pos).
    try expectFmt("   (1,234)", .{ .num = -1234 }, "negparen10.");
    try expectFmt(" (1,234,567.89)", .{ .num = -1234567.89 }, "negparen15.2");
    // E: explicit d reduced to fit; w too small for any E-body → asterisks.
    try expectFmt("9.88131292E-324", .{ .num = 1e-323 }, "e15.10");
    try expectFmt("*****", .{ .num = -1234 }, "e5.");
}

test "WRITE-side date/time cluster: MONYY/MONNAME/DOWNAME/YEAR/DATETIME/TIMEAMPM/TOD (BUG-dateformats)" {
    // 25DEC2024 = SAS date 23735 (a Wednesday); datetime 2050741800 = that at 10:30:00
    try expectFmt("DEC2024", .{ .num = 23735 }, "monyy7.");
    try expectFmt("DEC24", .{ .num = 23735 }, "monyy5.");
    try expectFmt("DEC24", .{ .num = 23735 }, "monyy."); // width-less → default 5, 2-digit year (BUG-fmtdefwidth-date)
    try expectFmt("December ", .{ .num = 23735 }, "monname."); // default 9: value left, blank-padded (BUG-fmtdefwidth-date)
    try expectFmt("Dec", .{ .num = 23735 }, "monname3."); // truncated to w
    try expectFmt("July     ", .{ .num = 22100 }, "monname9."); // explicit w: padded into the 9-col field
    try expectFmt("Wednesday", .{ .num = 23735 }, "downame.");
    try expectFmt("2024", .{ .num = 23735 }, "year4.");
    try expectFmt("  25DEC2024:10:30:00", .{ .num = 2050741800 }, "datetime20."); // right-justified
    try expectFmt("10:30:00 AM", .{ .num = 37800 }, "timeampm11."); // a TIME value (seconds of day)
    try expectFmt(" 1:00:00 PM", .{ .num = 46800 }, "timeampm11.");
    try expectFmt("10:30:00", .{ .num = 2050741800 }, "tod8."); // time-of-day of a datetime
    try expectFmt("Friday   ", .{ .num = 0 }, "downame."); // SAS day 0 = 1960-01-01 = Friday
}

test "width-less DATETIME renders at its documented DEFAULT 16 (NOTE-datetimewidth)" {
    // SAS 9.4 Formats and Informats: Reference, printed p.176: `DATETIMEw.d`
    // — w "Default 16", "Range 7–40" — and the entry's own worked example
    // prints `put x datetime.;` as `14MAR18:22:25:33` for a 2018 value, i.e.
    // the TWO-digit-year form. We rendered the 18-wide four-digit-year form on
    // every width-less datetime PUT. 21258 is the doc's own 15MAR2018 (p.173),
    // so 21258*86400 + 9*3600 = 1836723600 is 15MAR2018:09:00:00.
    try expectFmt("15MAR18:09:00:00", .{ .num = 1836723600 }, "datetime.");
    // the default is exactly the explicit 16, and the wider explicit widths
    // (which were already right) are untouched
    try expectFmt("15MAR18:09:00:00", .{ .num = 1836723600 }, "datetime16.");
    try expectFmt("15MAR2018:09:00:00", .{ .num = 1836723600 }, "datetime18.");
    try expectFmt(" 15MAR2018:09:00:00", .{ .num = 1836723600 }, "datetime19.");

    // Sibling defaults, checked at the same time: DATEw. "Default 7" (p.172) —
    // already right, its width-less form IS date7.
    try expectFmt("15MAR18", .{ .num = 21258 }, "date.");
    try expectFmt("15MAR18", .{ .num = 21258 }, "date7.");
}

test "width-less TIME renders at its documented DEFAULT 8, blank-padding a 1-digit hour (NOTE-timedefwidth)" {
    // TIMEw.d — `w Default 8` (Formats and Informats p.478). The 8-column field
    // is what produces the leading blank the entry states normatively TWICE:
    // "If hh is a single digit, TIMEw.d places a leading blank before the digit"
    // and "The TIMEw.d format writes a leading blank for a single-hour digit"
    // (both p.479). Width-less `time.` used to skip the field entirely, so a
    // single-digit hour lost the blank. 32400 = 9:00:00, 59083 = 16:24:43
    // (the doc's own TIME example value), 19434 = 5:23:54 (Language Reference: Concepts p.147's row).
    try expectFmt(" 9:00:00", .{ .num = 32400 }, "time.");
    try expectFmt(" 9:00:00", .{ .num = 32400 }, "time8."); // default == explicit 8
    try expectFmt(" 5:23:54", .{ .num = 19434 }, "time.");
    try expectFmt("16:24:43", .{ .num = 59083 }, "time."); // 2-digit hour: fills the field
    // TOD is the CONTRAST, not a copy: it ZERO-pads the same hour (p.483,
    // NOTE-todhourpad) and its body is already 8 wide, so it needs no default.
    try expectFmt("05:23:54", .{ .num = 19434 }, "tod.");
    try expectFmt("05:23:54", .{ .num = 19434 }, "tod8.");
    // justRight never truncates (`s.len >= w` returns s), so a value WIDER than
    // the default field still prints in full — a 100-hour duration and its
    // negative are unchanged by giving TIME a default width at all.
    try expectFmt("100:00:00", .{ .num = 360000 }, "time.");
    try expectFmt("-100:00:00", .{ .num = -360000 }, "time.");
}

test "HEXw. / $HEXw. formats encode to uppercase hex (BUG-hexformat)" {
    // HEXw. — numeric integer part, right-justified, zero-padded
    try expectFmt("000000FF", .{ .num = 255 }, "hex8.");
    try expectFmt("FF", .{ .num = 255 }, "hex2.");
    try expectFmt("00", .{ .num = 0 }, "hex2.");
    try expectFmt("00000100", .{ .num = 256 }, "hex8.");
    // $HEXw. — each byte → two hex digits; a short value is blank-padded (0x20)
    try expectFmt("414243", .{ .str = "ABC" }, "$hex6."); // A=41 B=42 C=43
    try expectFmt("4142", .{ .str = "AB" }, "$hex."); // no width → whole value
    try expectFmt("4120", .{ .str = "A" }, "$hex4."); // pad byte 0x20 → "20"
    // HEX16. — raw 8-byte IEEE double, big-endian, 16 hex digits (GH#46)
    try expectFmt("40424CCCCCCCCCCD", .{ .num = 36.6 }, "hex16.");
    try expectFmt("40424CCCCC000000", .{ .num = 36.59999990463257 }, "hex16."); // the len-5 stored value
    try expectFmt("0000000000000000", .{ .num = 0 }, "hex16.");
}

test "readNumeric informat: DATETIME / E8601DT / TIME (BUG-datetimeinformat)" {
    // 25DEC2024 = SAS day 23735; 10:30:00 = 37800s; datetime = 23735*86400+37800
    const want: f64 = 23735 * 86400 + 37800;
    try t.expectEqual(want, readNumeric("datetime20.", "25DEC2024:10:30:00").num);
    try t.expectEqual(want, readNumeric("e8601dt.", "2024-12-25T10:30:00").num); // digit-bearing name
    try t.expectEqual(want, readNumeric("b8601dt19.", "2024-12-25T10:30:00").num);
    // bare time → seconds of day
    try t.expectEqual(@as(f64, 37800), readNumeric("time8.", "10:30:00").num);
    try t.expectEqual(@as(f64, 0), readNumeric("datetime.", "01JAN1960:00:00:00").num); // SAS epoch
    // unparseable → missing
    try t.expect(readNumeric("datetime20.", "not a datetime").isMissing());
    try t.expect(readNumeric("e8601dt.", "2024-12-25").isMissing()); // no time separator
}

test "BUG-timeinformat: TIMEw. AM/PM, period separator, fractional seconds" {
    try t.expectEqual(@as(f64, 48600), readNumeric("time11.", "1:30:00 PM").num); // 13*3600+30*60
    try t.expectEqual(@as(f64, 5445.5), readNumeric("time11.", "01:30:45.5").num);
    try t.expectEqual(@as(f64, 46560), readNumeric("time10.", "12.56").num); // period = separator
    try t.expectEqual(@as(f64, 47580), readNumeric("time10.", "1:13 pm").num);
    try t.expectEqual(@as(f64, 0), readNumeric("time10.", "12:00 AM").num); // 12 AM = hour 0
    try t.expectEqual(@as(f64, 43200), readNumeric("time10.", "12:00 PM").num); // 12 PM = noon
    try t.expectEqual(@as(f64, 52215.5), readNumeric("e8601tm12.", "14:30:15.5").num);
    // the datetime forms keep the fraction instead of truncating to midnight
    const day: f64 = 21991 * 86400; // 2020-03-17
    try t.expectEqual(day + 52215.5, readNumeric("e8601dt22.", "2020-03-17T14:30:15.5").num);
    try t.expect(readNumeric("time8.", "not a time").isMissing());
}

test "BUG-todinformat: TODw. reads a time-of-day; the read agrees with the TOD write" {
    try t.expectEqual(@as(f64, 37800), readNumeric("tod8.", "10:30:00").num);
    try t.expectEqual(@as(f64, 53100), readNumeric("tod5.", "14:45").num); // hh:mm
    try t.expectEqual(@as(f64, 25200), readNumeric("tod2.", "7").num); // bare hour
    try t.expectEqual(@as(f64, 5445.5), readNumeric("tod10.", "01:30:45.5").num); // fraction kept
    try t.expectEqual(@as(f64, 48600), readNumeric("tod11.", "1:30:00 PM").num);
    // the TOD-only rule: a datetime field keeps ONLY its time-of-day
    try t.expectEqual(@as(f64, 37800), readNumeric("tod20.", "25DEC2024:10:30:00").num);
    try t.expectEqual(@as(f64, 37800), readNumeric("tod20.", "01JAN1959:10:30:00").num); // pre-epoch
    try t.expect(readNumeric("tod8.", "not a time").isMissing());
    try t.expect(!formatErrored()); // a known informat never flags not-found
    // round-trip: read then write with the same TOD width gives the field back
    try expectFmt("10:30:00", .{ .num = readNumeric("tod8.", "10:30:00").num }, "tod8.");
    try expectFmt("14:45:00", .{ .num = readNumeric("tod5.", "14:45").num }, "tod8.");
}

test "NOTE-todhourpad/NOTE-todfloorfrac: TOD zero-pads the hour and keeps the fraction" {
    // Language Reference: Concepts' format tables, verbatim: the SAME input 19434 under the two formats,
    // listed one row apart (printed p.147 "Time formats", repeated p.150). TOD
    // zero-pads a single-digit hour; TIME (and TIMEAMPM/HHMM beside it) do not.
    try expectFmt("05:23:54", .{ .num = 19434 }, "tod8.");
    try expectFmt(" 5:23:54", .{ .num = 19434 }, "time8."); // justRight supplies the blank
    try expectFmt("05:23:54", .{ .num = 19434 }, "tod."); // TOD. — default width 8
    // a datetime input still reduces to its time-of-day first
    try expectFmt("10:30:00", .{ .num = 2050741800 }, "tod8.");
    // NOTE-todfloorfrac: the pre-floor made `.d` impossible and split TOD from TIME
    // on rounding (TIME8. 1:30:46 vs TOD8. 1:30:45). They now agree, and `.d` renders.
    try expectFmt("01:30:46", .{ .num = 5445.5 }, "tod8.");
    try expectFmt(" 1:30:46", .{ .num = 5445.5 }, "time8.");
    try expectFmt("01:30:45.5", .{ .num = 5445.5 }, "tod10.1");
    try expectFmt("01:30:45.500", .{ .num = 5445.5 }, "tod12.3");
    // negative / pre-epoch datetimes still land in [0,86400) — @mod, not @rem
    try expectFmt("10:30:00", .{ .num = -86400 + 37800 }, "tod8.");
}

test "BUG-hhmmssinformat: HHMMSSw. colon and digit-packed forms" {
    try t.expectEqual(@as(f64, 5445), readNumeric("hhmmss6.", "013045").num); // 1:30:45
    try t.expectEqual(@as(f64, 52215), readNumeric("hhmmss8.", "143015").num);
    try t.expectEqual(@as(f64, 5040), readNumeric("hhmmss8.", "124").num); // left 0-pad → 012400
    try t.expectEqual(@as(f64, 48645), readNumeric("hhmmss8.", "13:30:45").num); // colon form
    try t.expect(readNumeric("hhmmss8.", "13:30:45.9").num == 48645); // fraction ignored
    try t.expect(readNumeric("hhmmss8.", "1234567").isMissing()); // >6 packed digits
}

test "readNumeric informat: w.d implied decimal and PERCENT (BUG-informatdec/percentinformat)" {
    // implied decimal — a field with no explicit `.` is scaled by 10^-d
    try t.expectEqual(@as(f64, 123.45), readNumeric("5.2", "12345").num);
    try t.expectEqual(@as(f64, 123.456), readNumeric("6.3", "123456").num);
    // an explicit `.` in the field wins — no scaling
    try t.expectEqual(@as(f64, 1.5), readNumeric("5.2", "1.5").num);
    // d = 0 → plain integer
    try t.expectEqual(@as(f64, 12345), readNumeric("5.", "12345").num);
    // PERCENTw. — drop `%`, divide by 100
    try t.expectEqual(@as(f64, 0.45), readNumeric("percent8.", "45%").num);
    try t.expectEqual(@as(f64, 0.5), readNumeric("percent.", "50%").num);
    // parens → negative percentage; bare digits still divide by 100
    // (BUG-percentinformat2)
    try t.expectEqual(@as(f64, -0.25), readNumeric("percent8.", "(25%)").num);
    try t.expectEqual(@as(f64, -0.25), readNumeric("percent8.", "(25)").num);
    try t.expectEqual(@as(f64, 0.25), readNumeric("percent8.", "25").num);
    // COMMA grouping stripped, and the implied decimal still applies
    try t.expectEqual(@as(f64, 12.34), readNumeric("comma8.2", "1,234").num);
    // BUG-numxinformat: NUMXw.d — comma is the DECIMAL, period the grouping.
    try t.expectEqual(@as(f64, 12.5), readNumeric("numx8.2", "12,5").num);
    try t.expectEqual(@as(f64, 1234.56), readNumeric("numx8.2", "1.234,56").num);
    try t.expectEqual(@as(f64, 1000), readNumeric("numx8.", "1.000").num);
    // no explicit decimal comma → d implied decimals still apply
    try t.expectEqual(@as(f64, 12.34), readNumeric("numx8.2", "1234").num);
    // blank / unparseable → missing
    try t.expect(readNumeric("5.2", "   ").isMissing());
    try t.expect(readNumeric("5.2", "abc").isMissing());
}

test "BUG-bzinformat/numembeddedblank: blank handling is informat-specific" {
    // BZw.d — EVERY blank (leading, trailing, embedded) reads as a ZERO.
    try t.expectEqual(@as(f64, 1000), readNumeric("bz4.", "1   ").num);
    try t.expectEqual(@as(f64, 100), readNumeric("bz5.", "  1  ").num);
    try t.expectEqual(@as(f64, 102), readNumeric("bz3.", "1 2").num);
    // BZ + implied decimal: zero-fill first, then scale.
    try t.expectEqual(@as(f64, 100), readNumeric("bz5.2", "1    ").num);
    // plain w.d — leading/trailing blanks still trim fine…
    try t.expectEqual(@as(f64, 42), readNumeric("4.", " 42 ").num);
    try t.expectEqual(@as(f64, 42), readNumeric("f4.", " 42").num);
    // …but an EMBEDDED blank is invalid numeric data → missing + the SAS NOTE.
    g_test_last_note = "";
    try t.expect(readNumeric("4.", "2 3 ").isMissing());
    try t.expect(std.mem.indexOf(u8, g_test_last_note, "Invalid numeric data") != null);
    // NOTE-invalidnumdataloc (GH#78): the capture is byte-identical to the CLI
    // text and carries NO frozen "line 0 column 0" (the record position lives
    // in io.zig, unreachable at the informat layer).
    g_test_last_note = "";
    const saved_noted = read_noted;
    defer read_noted = saved_noted;
    try t.expect(readNumeric("4.", "2 3").isMissing());
    try t.expectEqualStrings("Invalid numeric data, '2 3'.", g_test_last_note);
    try t.expect(read_noted); // still dedupes io.zig's second note
    // an all-blank field is a plain silent missing — no NOTE.
    g_test_last_note = "";
    try t.expect(readNumeric("4.", "    ").isMissing());
    try t.expectEqual(@as(usize, 0), g_test_last_note.len);
    // SAS reads only the first w bytes (the INPUT() fn's numFromSpec did the same).
    try t.expectEqual(@as(f64, 123), readNumeric("3.", "12345").num);
    // no regression: COMMA/DOLLAR/PERCENT keep the DOCUMENTED blank-drop
    // (COMMAw.d "removes embedded … blanks"). BEST does NOT — BESTw.d is a w.d
    // ALIAS (the w.d informat page names BESTw.d/Dw.d/Ew.d/Fw.d as aliases), so
    // its embedded blank is invalid, same as plain w.d above. This line used to
    // pin `best8.` on "2 3 " → 23 — that pinned the bug fixed in
    // NOTE-informatlow-tick245 #9 (SAS: missing + invalid-data NOTE).
    try t.expectEqual(@as(f64, 1234), readNumeric("comma8.", "1 234").num);
    try t.expectEqual(@as(f64, 0.45), readNumeric("percent8.", "45 %").num);
    try t.expect(readNumeric("best8.", "2 3 ").isMissing());
    // special missing still reads through the plain path (.A / ._).
    try t.expect(readNumeric("8.", " .A ").isMissing());
    try t.expect(!std.math.isNan(readNumeric("8.", "42").num));
}

test "NOTE-informatlow-tick245: Z/BEST/E/D embedded blank invalid; COMMA interior hyphen; NEGPAREN informat loud" {
    // #9 zebestblank — Z/BEST/E/D are w.d aliases: an embedded blank is invalid
    // numeric data → missing + the SAS NOTE, like plain w.d. Was: legacy
    // drop-all-blanks (`z3.` on "4 2" silently read 42).
    for ([_][]const u8{ "z3.", "best4.", "e4.", "d4." }) |spec| {
        g_test_last_note = "";
        try t.expect(readNumeric(spec, "4 2").isMissing());
        try t.expect(std.mem.indexOf(u8, g_test_last_note, "Invalid numeric data") != null);
    }
    // leading/trailing blanks still trim fine on the same informats.
    try t.expectEqual(@as(f64, 42), readNumeric("z4.", " 42 ").num);
    try t.expectEqual(@as(f64, 42), readNumeric("best5.", " 42 ").num);
    // #13 commahyphen — COMMAw.d "removes embedded … hyphens": an INTERIOR '-'
    // drops; a LEADING minus and E-notation's exponent sign keep their meaning.
    try t.expectEqual(@as(f64, 1234), readNumeric("comma10.", "12-34").num);
    try t.expectEqual(@as(f64, -500), readNumeric("comma10.", "-500").num);
    try t.expectEqual(@as(f64, -23), readNumeric("comma4.", "- 23").num);
    try t.expectEqual(@as(f64, 0.001), readNumeric("comma10.", "1E-3").num);
    // #14 negpareninformat — SAS 9.4 has NO NEGPAREN informat (the 108-entry
    // informat dictionary; it is a FORMAT only): fail loud (D-002) naming the
    // informat, then the field reads missing on the fallback like any unknown
    // informat. The NEGPAREN write FORMAT is untouched (renderNegParen above).
    g_fmt_error = false;
    g_nofmterr = false;
    g_test_last_err = "";
    try t.expect(readNumeric("negparen10.", "(1,234)").isMissing());
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "negparen") != null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "informat") != null);
    g_fmt_error = false; // reset module state for other tests
}

test "BESTw. with an explicit width keeps decimals and right-justifies (fmt_bestw)" {
    // was falling through to `w.d` with d=0 → integer; now honors w and decimals
    try expectFmt(" 12345.678", .{ .num = 12345.678 }, "best10.");
    try expectFmt("0.000123", .{ .num = 0.000123 }, "best8."); // fills 8 exactly, no pad
    try expectFmt(" 3.14159", .{ .num = 3.14159 }, "best8.");
    try expectFmt("      42", .{ .num = 42 }, "best8."); // whole number right-justified
}

test "bestNum: BEST12. is a 12-CHARACTER field, fixed-or-E by max digits (BUG-bestfmt)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // fixed notation — value fills 12 columns, trailing zeros dropped
    try t.expectEqualStrings("0.3", try bestNum(a, 0.1 + 0.2)); // not 0.30000000000000004
    try t.expectEqualStrings("0.3333333333", try bestNum(a, 1.0 / 3.0)); // 12 chars, 10 decimals
    try t.expectEqualStrings("-0.333333333", try bestNum(a, -1.0 / 3.0)); // sign eats a column (12 total)
    try t.expectEqualStrings("0.2857142857", try bestNum(a, 2.0 / 7.0));
    try t.expectEqualStrings("123456789.12", try bestNum(a, 123456789.12345));
    try t.expectEqualStrings("0.0000001", try bestNum(a, 0.0000001)); // exact → fixed, not E
    try t.expectEqualStrings("123.456", try bestNum(a, 123.456));
    try t.expectEqualStrings("1100000", try bestNum(a, 1000000.0 * 1.1)); // whole after de-noise
    try t.expectEqualStrings("42", try bestNum(a, 42));
    try t.expectEqualStrings("0", try bestNum(a, 0));
    try t.expectEqualStrings(".", try bestNum(a, std.math.nan(f64)));
    // E-notation — magnitudes that don't fit 12 columns in fixed form
    try t.expectEqualStrings("1E13", try bestNum(a, 1e13)); // 14-digit integer won't fit
    try t.expectEqualStrings("1E-11", try bestNum(a, 1e-11)); // rounds to 0 in fixed
    try t.expectEqualStrings("3.3333333E-9", try bestNum(a, 1.0 / 3.0e8)); // E shows more digits
    // mantissa that rounds up to 10 renormalises (not "10E13")
    try t.expectEqualStrings("1E14", try bestNum(a, 9.9999999999e13));
    try t.expectEqualStrings("-1E14", try bestNum(a, -9.9999999999e13));
    try t.expectEqualStrings("1E-11", try bestNum(a, 9.9999999e-12));
}

test "bestNumW: width 0 resolves to the default width, never underflows (BUG-bestnumwidth0)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // w == 0 with a negative value did `0 - 1` in usize → integer-overflow abort.
    // SAS: width 0 = the format's default width → BEST12. behavior, both signs.
    try t.expectEqualStrings("-12345", try bestNumW(a, -12345, 0));
    try t.expectEqualStrings("12345", try bestNumW(a, 12345, 0));
    try t.expectEqualStrings("-0.333333333", try bestNumW(a, -1.0 / 3.0, 0));
    try t.expectEqualStrings("0", try bestNumW(a, 0, 0));
}

test "bestNumW: wide-field whole numbers past 2^63 don't panic (BUG-bestint-i64-overflow)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // whole doubles whose digit count fits the field but whose magnitude exceeds
    // i64 — the old @intFromFloat(i64) cast panicked ("integer part … out of bounds")
    try t.expectEqualStrings("100000000000000000000", try bestNumW(a, 1e20, 32));
    try t.expectEqualStrings("10000000000000000000", try bestNumW(a, 1e19, 20));
    try t.expectEqualStrings("-100000000000000000000", try bestNumW(a, -1e20, 32));
}

test "BESTFMT-enotation: high-precision doubles keep the full decimal, not E (GH#46 follow-up)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // SAS 9.4 BESTw. uses E-notation ONLY when a plain decimal cannot show the
    // magnitude (integer part overflows w, or the value rounds away to 0). A
    // LENGTH-5-truncated 36.6 == 36.59999990463257 fits as a decimal, so it must
    // print the full decimal to the field width — never `3.66E1`.
    const x: f64 = 36.59999990463257;
    try t.expectEqualStrings("36.599999905", try bestNumW(a, x, 12)); // BEST12 default
    try t.expectEqualStrings("36.6", try bestNumW(a, x, 6)); // narrow: decimal, not 3.66E1
    try t.expectEqualStrings("36.59999990463257", try bestNumW(a, x, 17)); // wide: full decimal
    // no |x|>=1 value whose integer part fits w may flip to E-notation
    const bases = [_]f64{ 36.6, 123.456, 1234.5678, 98765.4321, 3.14159, 1.0 / 3.0, 2.0 / 7.0, 42.4242 };
    for (bases) |b| {
        var w: usize = 6;
        while (w <= 15) : (w += 1) {
            const s = try bestNumW(a, b, w);
            for (s) |ch| try t.expect(ch != 'E' and ch != 'e');
        }
    }
    // BESTFMT-edge (don't regress): a non-integer rounding up to a 13-digit power
    // of 10 stays E-notation because the fixed form overflows 12 columns.
    try t.expectEqualStrings("1E12", try bestNum(a, 999999999999.9));
}

test "BUG-wdroundtie: w.d rounds the EXACT stored binary value (no multiply-snap false ties)" {
    // Below-tie literals: the stored f64 is strictly BELOW the decimal tie → down.
    try expectFmt("    2.67", .{ .num = 2.675 }, "8.2"); // stored 2.6749999999999998224
    try expectFmt("    0.01", .{ .num = 0.015 }, "8.2"); // stored 0.0149999999999999994
    try expectFmt("    0.04", .{ .num = 0.045 }, "8.2"); // stored 0.0449999999999999983
    try expectFmt("    0.07", .{ .num = 0.075 }, "8.2"); // stored 0.0749999999999999972
    try expectFmt("    1.04", .{ .num = 1.045 }, "8.2"); // stored 1.0449999999999999289
    try expectFmt("     0.1", .{ .num = 0.15 }, "8.1"); //  stored 0.1499999999999999944
    try expectFmt("     0.3", .{ .num = 0.35 }, "8.1"); //  stored 0.3499999999999999778
    try expectFmt("     0.8", .{ .num = 0.85 }, "8.1"); //  stored 0.8499999999999999778
    try expectFmt("     0.9", .{ .num = 0.95 }, "8.1"); //  stored 0.9499999999999999556
    try expectFmt("     1.000", .{ .num = 1.0005 }, "10.3"); // stored 1.0004999999999999449
    // Must-not-move: EXACT ties still round half-AWAY-from-zero (not half-to-even).
    try expectFmt("       3", .{ .num = 2.5 }, "8.");
    try expectFmt("      -3", .{ .num = -2.5 }, "8.");
    try expectFmt("    0.13", .{ .num = 0.125 }, "8.2"); // 0.125 exact in binary → true tie
    try expectFmt("    1.00", .{ .num = 1.005 }, "8.2"); // 1.005·100 stays below 100.5
}

test "numeric w.d: rounding, right-justify, sign, missing" {
    try expectFmt("    3.14", .{ .num = 3.14159 }, "8.2");
    try expectFmt("   42", .{ .num = 42 }, "5.");
    try expectFmt("    -3.5", .{ .num = -3.5 }, "8.1");
    try expectFmt("3", .{ .num = 2.6 }, "1."); // overflow-narrow → natural text
    try expectFmt("       .", .{ .num = std.math.nan(f64) }, "8.2"); // missing
    // char under a numeric spec renders the raw text (loud now —
    // NOTE-fmtnumoncharcoerce; the loud path is asserted in its own test below)
    {
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        defer arena.deinit();
        g_fmt_error = false;
        try t.expectEqualStrings("15", try apply(arena.allocator(), .{ .str = "15" }, "2."));
        g_fmt_error = false; // reset module state for other tests
    }
}

test "NOTE-fmtnumoncharcoerce: a numeric format on a CHAR value fails loud, renders raw (mirror of BUG-charfmtonnum)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Controls: numeric format on numeric, `$` format on char — no error.
    g_nofmterr = false;
    g_fmt_error = false;
    _ = try apply(a, .{ .num = 42 }, "8.2");
    _ = try apply(a, .{ .str = "hi" }, "$5.");
    try t.expect(!formatErrored());

    // 'abc' under 8.2 used to render `.` — the value DESTROYED with exit 0.
    // Now: loud error (captured in a test build, TEST-quietnoise) + raw text.
    g_test_last_err = "";
    const out = try apply(a, .{ .str = "abc" }, "8.2");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "The numeric format 8.2 cannot be used with a character value.") != null);
    try t.expectEqualStrings("abc     ", out); // fallback raw render, left-justified in w=8

    // A char-typed USER format referenced $-lessly is NOT a mismatch (SAS
    // matches by name + value type, QA-charfmtnodollar): no error from the
    // statement-level specIsChar either.
    try t.expect(!specIsChar("8.2"));
    try t.expect(specIsChar("$8."));

    // `options nofmterr` suppresses it like the other format errors.
    g_fmt_error = false;
    g_nofmterr = true;
    _ = try apply(a, .{ .str = "abc" }, "8.2");
    try t.expect(!formatErrored());

    g_nofmterr = false;
    g_fmt_error = false; // reset module state for other tests
}

test "BUG-fmtwidth: numeric output is fit to width w (reduce d, drop sep, BEST/E, *)" {
    try expectFmt("1234.6", .{ .num = 1234.567 }, "6.2"); // 1234.57 won't fit → drop a decimal
    try expectFmt("1.23", .{ .num = 1.23456 }, "4.3"); // 1.235 → 1.23
    try expectFmt("$1000000", .{ .num = 1000000 }, "dollar8."); // $1,000,000 → drop commas, keep $
    try expectFmt("1.23E6", .{ .num = 1234567 }, "comma6."); // drop commas → still 7 → BEST/E
    try expectFmt("1.2E5", .{ .num = 123456 }, "5."); // no decimals to drop → BEST/E fills the field
    try expectFmt("**", .{ .num = 123456 }, "2."); // nothing fits → asterisks
    try expectFmt(" 12.50", .{ .num = 12.5 }, "6.2"); // already fits → unchanged (no regression)
    try expectFmt("-1235", .{ .num = -1234.5 }, "5."); // sign kept, rounds to fit
}

test "char $w.: pad and truncate" {
    try expectFmt("hi   ", .{ .str = "hi" }, "$5.");
    try expectFmt("too", .{ .str = "toolong" }, "$3."); // truncated
}

test "BUG-charfmtonnum: a $ (char) format on a NUMERIC value fails loud (D-002)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // $ on char and a numeric format on numeric: no error (no false positive).
    g_nofmterr = false;
    g_fmt_error = false;
    _ = try apply(a, .{ .str = "hi" }, "$5.");
    _ = try apply(a, .{ .num = 42 }, "8.2");
    try t.expect(!formatErrored());

    // A KNOWN char format on a numeric value: loud error (captured in a test
    // build, TEST-quietnoise), then the raw value still renders (fallback).
    g_test_last_err = "";
    const out = try apply(a, .{ .num = 42 }, "$upcase5.");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "$upcase5.") != null);
    try t.expectEqualStrings("42   ", out); // fallback raw render

    // `options nofmterr` suppresses it like the other format errors.
    g_fmt_error = false;
    g_nofmterr = true;
    _ = try apply(a, .{ .num = 42 }, "$5.");
    try t.expect(!formatErrored());

    g_nofmterr = false;
    g_fmt_error = false; // reset module state for other tests
}

test "COMMAw.d: thousands separators" {
    try expectFmt("   1,234,567", .{ .num = 1234567 }, "COMMA12.");
    try expectFmt("  1,234.50", .{ .num = 1234.5 }, "comma10.2");
    try expectFmt("123", .{ .num = 123 }, "comma3."); // no separator under 1000
}

test "BUG-fmtxnlneg: COMMAX/DOLLARX (European) / NEGPAREN / NLNUM" {
    // COMMAX: `.`=thousands, `,`=decimal
    try expectFmt("   1.234.567,89", .{ .num = 1234567.89 }, "commax15.2");
    // DOLLARX: COMMAX with a leading `$`
    try expectFmt("  $1.234.567,89", .{ .num = 1234567.89 }, "dollarx15.2");
    // NEGPAREN: negatives in parens; positives reserve the close-paren column
    try expectFmt("   (1,234)", .{ .num = -1234 }, "negparen10.");
    try expectFmt(" (1,234,567.89)", .{ .num = -1234567.89 }, "negparen15.2");
    try expectFmt("  1,234,567.89 ", .{ .num = 1234567.89 }, "negparen15.2"); // positive reserves last col
    // NLNUM: en_US grouping, like COMMA
    try expectFmt("   1,234,567.89", .{ .num = 1234567.89 }, "nlnum15.2");
}

test "DATEw.: SAS day → ddMMMyy(yy)" {
    try expectFmt("01JAN1960", .{ .num = 0 }, "DATE9."); // epoch
    try expectFmt("01JAN2000", .{ .num = 14610 }, "date9.");
    try expectFmt("01JAN60", .{ .num = 0 }, "date7."); // 2-digit year
    try expectFmt("15JAN1960", .{ .num = 14 }, "DATE9.");
    // guard: day out of displayable range → plain number, no @intFromFloat/@intCast panic
    try expectFmt("  5000000", .{ .num = 5000000 }, "date9.");
    // BUG-putdate11: w≥10 → hyphenated dd-MMM-yy(yy); 21989 = mdy(3,15,2020)
    try expectFmt("15-MAR-2020", .{ .num = 21989 }, "date11.");
    try expectFmt(" 15-MAR-20", .{ .num = 21989 }, "date10."); // 2-digit year, right-justified
    try expectFmt("15MAR2020", .{ .num = 21989 }, "date9."); // non-hyphen neighbors intact
    try expectFmt("15MAR20", .{ .num = 21989 }, "date7.");
}

test "MMDDYYw.: SAS day → mm/dd/yy(yy)" {
    try expectFmt("01/01/1960", .{ .num = 0 }, "MMDDYY10.");
    try expectFmt("01/01/60", .{ .num = 0 }, "mmddyy8."); // 2-digit year
    try expectFmt("01/15/1960", .{ .num = 14 }, "mmddyy10.");
}

test "DDMMYY/YYMMDD/TIME/WORDDATE date pictures" {
    // 22100 = mdy(7, 4, 2020) = 04JUL2020
    try expectFmt("04/07/2020", .{ .num = 22100 }, "ddmmyy10.");
    try expectFmt("04/07/20", .{ .num = 22100 }, "ddmmyy8."); // 2-digit year
    try expectFmt("2020-07-04", .{ .num = 22100 }, "yymmdd10.");
    try expectFmt("20-07-04", .{ .num = 22100 }, "yymmdd8.");
    try expectFmt("      July 4, 2020", .{ .num = 22100 }, "worddate."); // default 18, right-justified (BUG-fmtdefwidth-date)
    // YYMMDDxw. family (BUG-sysfuncformat) — 22100 = 04JUL2020
    try expectFmt("20200704", .{ .num = 22100 }, "yymmddn8.");
    try expectFmt("20200704", .{ .num = 22100 }, "yymmddn."); // default 8, 4-digit year
    try expectFmt("200704", .{ .num = 22100 }, "yymmddn6."); // 2-digit year, no sep
    try expectFmt("2020/07/04", .{ .num = 22100 }, "yymmdds10.");
    try expectFmt("20:07:04", .{ .num = 22100 }, "yymmddc8."); // 2-digit at w=8
    try expectFmt("2020.07.04", .{ .num = 22100 }, "yymmddp10.");
    try expectFmt("2020 07 04", .{ .num = 22100 }, "yymmddb10.");
    try expectFmt("2020-07-04", .{ .num = 22100 }, "yymmddd10.");
    // 45045 s = 12:30:45
    try expectFmt("12:30:45", .{ .num = 45045 }, "time8.");
    try expectFmt(" 1:00:05", .{ .num = 3605 }, "time8."); // SAS blank-pads a single-digit hour (BUG-timezeropad), not "01:00:05"
    try expectFmt("       .", .{ .num = std.math.nan(f64) }, "time8."); // missing
}

test "BUG-datefmtcluster: WEEKDATE / NLDATE write formats (July 4 2020 is a Saturday)" {
    try expectFmt("       Saturday, July 4, 2020", .{ .num = 22100 }, "weekdate."); // default 29, right-justified (BUG-fmtdefwidth-date)
    try expectFmt("   Saturday, July 4, 2020", .{ .num = 22100 }, "weekdate25."); // right-justified in 25
    try expectFmt("Sat", .{ .num = 22100 }, "weekdate3."); // narrow → day abbreviation
    try expectFmt("July 4, 2020", .{ .num = 22100 }, "nldate."); // en_US NLDATE = WORDDATE (natural form; NLDATE default-width uncontested)
    try expectFmt("                            .", .{ .num = std.math.nan(f64) }, "weekdate."); // missing → "." right-justified in 29
}

test "BUG-datefmtcluster: the rest of the date write-family (d=21930 = Thu 16JAN2020)" {
    const d: Value = .{ .num = 21930 };
    try expectFmt("    Thursday, 16 January 2020", d, "weekdatx."); // default 29
    try expectFmt("   16 January 2020", d, "worddatx."); // default 18
    try expectFmt("20016", d, "julian5.");
    try expectFmt("20016", d, "julian."); // width-less → default 5, yyddd (BUG-fmtdefwidth-date)
    try expectFmt("2020016", d, "julian7.");
    try expectFmt("1", d, "qtr."); // quarter number
    try expectFmt("I", d, "qtrr."); // roman quarter
    try expectFmt("2020Q1", d, "yyq6.");
    try expectFmt("2020:1", d, "yyqc6.");
    try expectFmt("5", d, "weekday1."); // Thursday = 5 (1=Sunday)
    try expectFmt(" 1", d, "month2."); // month 1, right-justified in 2
    try expectFmt("16", d, "day2.");
    try expectFmt("202001", d, "yymmn6.");
}

test "GAP-fmtyymm: YYMMw./MMYYw. + separator variants (21975 = 01MAR2020)" {
    const d = Value{ .num = 21975 };
    try expectFmt("2020M03", d, "yymm7."); // default width, 4-digit year, 'M' separator
    try expectFmt("2020M03", d, "yymm."); // w=0 → default 7
    try expectFmt("20M03", d, "yymm5."); // narrow → 2-digit year
    try expectFmt("03M2020", d, "mmyy7.");
    try expectFmt("03M20", d, "mmyy5.");
    // separator variants: C=':' D='-' P='.' S='/' N=none
    try expectFmt("2020:03", d, "yymmc7.");
    try expectFmt("2020-03", d, "yymmd7.");
    try expectFmt("2020.03", d, "yymmp7.");
    try expectFmt("2020/03", d, "yymms7.");
    try expectFmt("03/2020", d, "mmyys7.");
    try expectFmt("032020", d, "mmyyn6."); // no separator → 4-digit year fits at w=6
    try expectFmt("      .", .{ .num = std.math.nan(f64) }, "yymm7."); // missing → right-justified "."
}

test "DOLLARw.d: `$` + thousands separators" {
    try expectFmt("  $12,345.68", .{ .num = 12345.678 }, "dollar12.2");
    try expectFmt("    12,345.7", .{ .num = 12345.678 }, "comma12.1");
    try expectFmt("     -3.14", .{ .num = -3.14159 }, "10.2"); // negative right-justified
}

test "Zw.d: zero-padded, sign-aware" {
    try expectFmt("00042", .{ .num = 42 }, "z5."); // formats_z_percent.sas
    try expectFmt("007", .{ .num = 7 }, "z3.");
    try expectFmt("-0003.50", .{ .num = -3.5 }, "z8.2"); // minus stays leftmost
    try expectFmt("008.50", .{ .num = 8.5 }, "z6.2");
}

test "PERCENTw.d: ×100, trailing %, parens for negatives" {
    try expectFmt("    7.5%", .{ .num = 0.075 }, "percent8.1"); // formats_z_percent.sas
    try expectFmt("50%", .{ .num = 0.5 }, "percent3."); // no decimals
    try expectFmt("  (5.0%)", .{ .num = -0.05 }, "percent8.1"); // negative → parens
}

test "GAP-fmtdefwidth-num: omitted width → SAS default 6, right-justified" {
    try expectFmt("   50%", .{ .num = 0.5 }, "percent."); // PERCENT default w=6
    try expectFmt(" (50%)", .{ .num = -0.5 }, "percent."); // negative → parens, still 6
    try expectFmt(" 1,235", .{ .num = 1235 }, "comma."); // COMMA default w=6
    try expectFmt("  $100", .{ .num = 100 }, "dollar."); // DOLLAR default w=6
    try expectFmt("1,235 ", .{ .num = 1235 }, "negparen."); // positive reserves close-paren col
    try expectFmt("  (12)", .{ .num = -12 }, "negparen.");
    try expectFmt(" 1.235", .{ .num = 1235 }, "commax."); // COMMAX default w=6
    try expectFmt("     .", .{ .num = std.math.nan(f64) }, "comma."); // missing right-justified
    // explicit widths are byte-identical (untouched by the default)
    try expectFmt("    7.5%", .{ .num = 0.075 }, "percent8.1");
    try expectFmt("  1,234.50", .{ .num = 1234.5 }, "comma10.2");
    // too wide for 6 → the normal fit ladder, never overflow
    try expectFmt("******", .{ .num = 12345678 }, "negparen.");
}

test "parseSpec pieces" {
    const s = parseSpec("COMMA10.2");
    try t.expectEqualStrings("COMMA", s.name);
    try t.expectEqual(@as(usize, 10), s.w);
    try t.expectEqual(@as(usize, 2), s.d);
    try t.expect(parseSpec("$8.").is_char);
}

test "parseSpec: digit-carrying names split at the TRAILING digit run (QA-e8601put)" {
    // E8601DT19. is name E8601DT + w 19 — the old letters-only scan yielded
    // name "e" + w 8601 = the Ew. scientific format, silently wrong output.
    const iso = parseSpec("e8601dt19.");
    try t.expectEqualStrings("e8601dt", iso.name);
    try t.expectEqual(@as(usize, 19), iso.w);
    // names ending in letters split exactly as before
    const ymd = parseSpec("yymmdd10.");
    try t.expectEqualStrings("yymmdd", ymd.name);
    try t.expectEqual(@as(usize, 10), ymd.w);
    // Ew. itself still reachable
    const e = parseSpec("e12.");
    try t.expectEqualStrings("e", e.name);
    try t.expectEqual(@as(usize, 12), e.w);
    // underscore CNTLIN names keep the whole name, no width (QA-svvisnum)
    const u = parseSpec("VISNUM_ALL_PERIOD.");
    try t.expectEqualStrings("VISNUM_ALL_PERIOD", u.name);
    try t.expectEqual(@as(usize, 0), u.w);
    // plain w.d unchanged
    const p = parseSpec("8.2");
    try t.expectEqualStrings("", p.name);
    try t.expectEqual(@as(usize, 8), p.w);
    try t.expectEqual(@as(usize, 2), p.d);
}

test "E8601DA/E8601DT write side renders ISO 8601 (QA-e8601put)" {
    // 28MAR2019 = SAS day 21636; datetime = 21636*86400 = 1869350400
    try expectFmt("2019-03-28", .{ .num = 21636 }, "e8601da10.");
    try expectFmt("2019-03-28T00:00:00", .{ .num = 1869350400 }, "e8601dt19.");
    // 25DEC2024 10:30:00 = 2050741800 (same anchor as the DATETIME cluster test)
    try expectFmt("2024-12-25T10:30:00", .{ .num = 2050741800 }, "e8601dt19.");
    try expectFmt("                  .", Value.missing, "e8601dt19."); // missing → dot, right-justified in w=19
}

test "GAP-fmtwritebatch: YYMON/JULDAY/ROMAN/WORDS/DATEAMPM/MMSS/B8601/NL* write formats" {
    // d=22100 (04JUL2020, day-of-year 186), dt=1909490706 (04JUL2020:14:05:06),
    // t=50706 (14:05:06). Oracle: Language Reference: Concepts pp.146-150, sas-functions-ref p.680.
    try expectFmt("2020JUL", .{ .num = 22100 }, "yymon7.");
    try expectFmt("20JUL", .{ .num = 22100 }, "yymon5."); // 2-digit year below w7
    try expectFmt("2013MAR", .{ .num = 19434 }, "yymon."); // Language Reference: Concepts p.148
    try expectFmt("186", .{ .num = 22100 }, "julday3.");
    try expectFmt(" 76", .{ .num = 19434 }, "julday3."); // Language Reference: Concepts p.146
    try expectFmt("2020186", .{ .num = 22100 }, "pdjulian7."); // yyyyddd, JULIAN twin
    try expectFmt("MCCXXXIV", .{ .num = 1234 }, "roman8.");
    try expectFmt("  MCML", .{ .num = 1950 }, "roman6.");
    try expectFmt("     0", .{ .num = 0 }, "roman."); // non-positive → Arabic
    try expectFmt(" -3", .{ .num = -3.9 }, "roman3."); // truncated, negative → Arabic
    try expectFmt("two thousand one hundred five", .{ .num = 2105 }, "words."); // p.680
    try expectFmt("one thousand two hundred thirty-four", .{ .num = 1234 }, "words.");
    try expectFmt("minus two point five", .{ .num = -2.5 }, "words.");
    try expectFmt("zero", .{ .num = 0 }, "words.");
    try expectFmt("four hundred thousan", .{ .num = 400501 }, "words20."); // truncated, left-justified
    try expectFmt("17MAR13:12:00:00 AM", .{ .num = 1679097600 }, "dateampm."); // Language Reference: Concepts p.150
    try expectFmt("    04JUL20:02:05:06 PM", .{ .num = 1909490706 }, "dateampm23.");
    try expectFmt("  323", .{ .num = 19434 }, "mmss."); // minutes only when mm:ss can't fit (Language Reference: Concepts)
    try expectFmt("61:01", .{ .num = 3661 }, "mmss5.");
    try expectFmt("  845:06", .{ .num = 50706 }, "mmss8.");
    try expectFmt("  20200704", .{ .num = 22100 }, "b8601da10.");
    try expectFmt("20200704", .{ .num = 22100 }, "b8601da8.");
    try expectFmt("20200704T140506", .{ .num = 1909490706 }, "b8601dt.");
    try expectFmt("  140506", .{ .num = 50706 }, "b8601tm.");
    try expectFmt("140506", .{ .num = 50706 }, "b8601tm6.");
    try expectFmt("04Jul2020:14:05:06", .{ .num = 1909490706 }, "nldatm.");
    try expectFmt("14:05:06", .{ .num = 50706 }, "nltime.");
    try expectFmt(" $1,234.00", .{ .num = 1234 }, "nlmny10.");
    try expectFmt("                  .", .{ .num = std.math.nan(f64) }, "dateampm."); // missing, padded to 19
}

test "special missing renders as its letter (G-specialmiss)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("A", try bestNum(a, Value.specialMissing('A').num));
    try std.testing.expectEqualStrings("_", try bestNum(a, Value.specialMissing('_').num));
    try std.testing.expectEqualStrings(".", try bestNum(a, Value.missing.num));
}

test "NOTE-sas7bcatspecialmiss: a special-missing KEY matches only its own missing value (.A→label; .B/plain . → OTHER-or-default)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // All-discrete + OTHER → the indexed path.
    const disc = [_]UserFmtEntry{
        .{ .lo = 1, .hi = 1, .label = "One" },
        .{ .lo = Value.specialMissing('A').num, .hi = Value.specialMissing('A').num, .label = "Special A" },
        .{ .label = "Other", .is_other = true },
    };
    // Missing key + a real range → sortedRanges rejects the NaN bound → linear path.
    const mixed = [_]UserFmtEntry{
        .{ .lo = 0, .hi = 17, .label = "Kid" },
        .{ .lo = Value.specialMissing('C').num, .hi = Value.specialMissing('C').num, .label = "See" },
    };
    const cat = [_]UserFmt{
        .{ .name = "missf", .is_char = false, .entries = &disc },
        .{ .name = "mixf", .is_char = false, .entries = &mixed },
    };
    setUserFormats(&cat);
    defer clearUserFormats();

    try std.testing.expectEqualStrings("One", try apply(a, .{ .num = 1 }, "missf."));
    try std.testing.expectEqualStrings("Special A", try apply(a, .{ .num = Value.specialMissing('A').num }, "missf."));
    try std.testing.expectEqualStrings("Other", try apply(a, .{ .num = Value.specialMissing('B').num }, "missf.")); // .B ≠ .A → OTHER
    try std.testing.expectEqualStrings("Other", try apply(a, Value.missing, "missf.")); // plain . has no key → OTHER
    try std.testing.expectEqualStrings("Other", try apply(a, .{ .num = 9 }, "missf."));

    try std.testing.expectEqualStrings("Kid", try apply(a, .{ .num = 5 }, "mixf."));
    try std.testing.expectEqualStrings("See", try apply(a, .{ .num = Value.specialMissing('C').num }, "mixf."));
    // no OTHER and no matching key → the default missing render (the letter,
    // right-justified to the format default width = longest label, here 3).
    try std.testing.expectEqualStrings("  A", try apply(a, .{ .num = Value.specialMissing('A').num }, "mixf."));
}

test "user-defined VALUE format decodes coded values (BUG-userformat)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const sexf = [_]UserFmtEntry{
        .{ .lo = 1, .hi = 1, .label = "Male" },
        .{ .lo = 2, .hi = 2, .label = "Female" },
        .{ .label = "Unknown", .is_other = true },
    };
    const rng = [_]UserFmtEntry{ // a numeric range
        .{ .lo = 0, .hi = 17, .label = "Minor" },
        .{ .lo = 18, .hi = 200, .label = "Adult" },
    };
    const grp = [_]UserFmtEntry{
        .{ .skey = "H", .label = "High" },
        .{ .skey = "L", .label = "Low" },
    };
    const cat = [_]UserFmt{
        .{ .name = "sexf", .is_char = false, .entries = &sexf },
        .{ .name = "agec", .is_char = false, .entries = &rng },
        .{ .name = "grp", .is_char = true, .entries = &grp },
    };
    setUserFormats(&cat);
    defer clearUserFormats();

    try std.testing.expectEqualStrings("Male", try apply(a, .{ .num = 1 }, "sexf."));
    try std.testing.expectEqualStrings("Female", try apply(a, .{ .num = 2 }, "sexf."));
    try std.testing.expectEqualStrings("Unknown", try apply(a, .{ .num = 9 }, "sexf.")); // OTHER
    try std.testing.expectEqualStrings("Minor", try apply(a, .{ .num = 5 }, "agec."));
    try std.testing.expectEqualStrings("Adult", try apply(a, .{ .num = 42 }, "agec."));
    try std.testing.expectEqualStrings("High", try apply(a, .{ .str = "H" }, "$grp."));
    try std.testing.expectEqualStrings("Low", try apply(a, .{ .str = "L " }, "$grp.")); // trailing blank
    // a char VALUE resolves the char format WITHOUT the `$` too — the CNTLIN
    // TYPE='C' codelist apply idiom `put(VISIT, VISNUM_ALL_PERIOD.)`
    // (QA-charfmtnodollar); a $-less name on a NUM value must NOT match it.
    try std.testing.expectEqualStrings("High", try apply(a, .{ .str = "H" }, "grp."));
    try std.testing.expect(!std.mem.eql(u8, "High", try apply(a, .{ .num = 1 }, "grp.")));
    // a char value that matches NO key (and no OTHER=) renders the source value —
    // not "." via the numeric fallback (QA-charfmtnomatch, gen2 AEOUT) — TRUNCATED
    // to the format's default width = its longest label (High/Low → 4), so
    // "NOT RECOVERED" → "NOT " (GH#63 ISS-fmtdefwidth; a value that fits is raw).
    try std.testing.expectEqualStrings("NOT ", try apply(a, .{ .str = "NOT RECOVERED" }, "grp."));
    try std.testing.expectEqualStrings("NOT ", try apply(a, .{ .str = "NOT RECOVERED" }, "$grp."));

    // a numeric value with no matching entry and no OTHER renders the raw value
    // right-justified in the format's default width = its longest label (Minor/
    // Adult → 5), the numeric twin of the char truncation above (NOTE-numfmtdefwidth).
    try std.testing.expectEqualStrings("  250", try apply(a, .{ .num = 250 }, "agec."));
    // a plain built-in format is unaffected by the catalog
    try std.testing.expectEqualStrings("Male", try apply(a, .{ .num = 1 }, "sexf."));
    try std.testing.expectEqualStrings("3.14", try apply(a, .{ .num = 3.14159 }, ".2"));
}

test "unknown format fails loud unless nofmterr (BUG-unknownfmtsilent)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // a known format never flags an error
    g_fmt_error = false;
    g_nofmterr = false;
    _ = try apply(a, .{ .num = 45.7 }, "5.1");
    try t.expect(!formatErrored());

    // `options nofmterr` suppresses the error for an unknown name (silent fallback)
    g_nofmterr = true;
    _ = try apply(a, .{ .num = 45.7 }, "undefinedfmt.");
    try t.expect(!formatErrored());

    // default: an unknown/unsupported name fails loud — captured (not stderr) in a
    // test build, so assert both the flag and the captured message (TEST-quietnoise).
    g_nofmterr = false;
    g_test_last_err = "";
    _ = try apply(a, .{ .num = 45.7 }, "undefinedfmt.");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "undefinedfmt") != null);

    g_fmt_error = false; // reset module state for other tests
}

test "D-009 §5f (write side): a documented-but-unimplemented format marks the gap (rc 2); a typo stays rc 1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    g_nofmterr = false;
    const rc = struct {
        fn f() u8 {
            return diag.exitCode(diag.gapHit(), formatErrored());
        }
    }.f;
    const reset = struct {
        fn r() void {
            g_fmt_error = false;
            diag.resetGap();
        }
    }.r;

    // Numeric: NLPCTw.d (p.415) is documented, unimplemented → gap.
    reset();
    _ = try apply(a, .{ .num = 0.5 }, "nlpct10.2");
    try t.expectEqual(@as(u8, 2), rc());
    // Typo: YEN is in NO SAS 9.4 dictionary (D-015) → rc 1.
    reset();
    _ = try apply(a, .{ .num = 0.5 }, "yen8.");
    try t.expect(formatErrored());
    try t.expectEqual(@as(u8, 1), rc());
    // Char: $UUIDw. is a documented char format → gap.
    reset();
    _ = try apply(a, .{ .str = "ab" }, "$uuid32.");
    try t.expectEqual(@as(u8, 2), rc());
    // Char typo → rc 1.
    reset();
    _ = try apply(a, .{ .str = "ab" }, "$bogus8.");
    try t.expectEqual(@as(u8, 1), rc());
    // Type scope: DATEw. is a NUMERIC format — real SAS reports $DATE "not
    // found" → user error, rc 1. Mirror: $CSTR is char-only → numeric rc 1.
    reset();
    _ = try apply(a, .{ .str = "ab" }, "$date9.");
    try t.expectEqual(@as(u8, 1), rc());
    reset();
    _ = try apply(a, .{ .num = 0.5 }, "cstr8.");
    try t.expectEqual(@as(u8, 1), rc());
    // Clean control: a supported format flags neither signal.
    reset();
    _ = try apply(a, .{ .num = 45.7 }, "comma12.2");
    try t.expectEqual(@as(u8, 0), rc());
    reset();

    // The doc list pins the split boundary itself (D-018 re-derivation).
    try t.expect(isDocumentedFormat("nlpct", false));
    try t.expect(isDocumentedFormat("nlpctp", false));
    try t.expect(isDocumentedFormat("nlmnyi", false));
    try t.expect(isDocumentedFormat("pvalue", false));
    try t.expect(isDocumentedFormat("uuid", true));
    try t.expect(!isDocumentedFormat("yen", false));
    try t.expect(!isDocumentedFormat("yen", true));
    try t.expect(!isDocumentedFormat("date", true)); // $DATE is "not found" in real SAS
    try t.expect(!isDocumentedFormat("cstr", false));
    // x-metavariable letter sets came from EACH entry's own syntax table:
    // MMDDYYxw./DDMMYYxw./YYMMDDxw. take B/C/D/N/P/S; YYMMxw./MMYYxw./YYQxw./
    // YYQRxw. take C/D/N/P/S — no B. `x` itself is a placeholder, not a name.
    try t.expect(isDocumentedFormat("mmddyyb", false));
    try t.expect(isDocumentedFormat("yymmddb", false));
    try t.expect(!isDocumentedFormat("yymmb", false));
    try t.expect(!isDocumentedFormat("mmyyb", false));
    try t.expect(isDocumentedFormat("mmyyc", false));
    try t.expect(!isDocumentedFormat("yyqx", false));
    try t.expect(!isDocumentedFormat("mmyyx", false));
}

test "D-009 §5f (read side): a documented-but-unimplemented informat marks the gap (rc 2); a typo stays rc 1" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    _ = a;
    g_nofmterr = false;
    const rc = struct {
        fn f() u8 {
            return diag.exitCode(diag.gapHit(), formatErrored());
        }
    }.f;
    const reset = struct {
        fn r() void {
            g_fmt_error = false;
            diag.resetGap();
        }
    }.r;

    // Numeric: PDw.d is a documented informat → gap.
    reset();
    _ = readNumeric("pd8.", "1234");
    try t.expectEqual(@as(u8, 2), rc());
    // NLS-named: the NENGOw. Informat exists only in the NLS Reference Guide,
    // named by this volume's See Also (p.257) → gap.
    reset();
    _ = readNumeric("nengo8.", "1234");
    try t.expectEqual(@as(u8, 2), rc());
    // Typo → rc 1.
    reset();
    _ = readNumeric("yen8.", "1234");
    try t.expectEqual(@as(u8, 1), rc());
    // Doc-EXCLUDED: NEGPAREN is a FORMAT only — the informat dictionary has
    // no entry (NOTE-informatlow-tick245 #14) → rc 1.
    reset();
    _ = readNumeric("negparen8.", "1234");
    try t.expectEqual(@as(u8, 1), rc());
    // Char: $UUIDw. informat documented → gap; typo → rc 1; numeric-only
    // DATE as a $-informat → rc 1.
    reset();
    checkCharInformat("uuid");
    try t.expectEqual(@as(u8, 2), rc());
    reset();
    checkCharInformat("bogus");
    try t.expectEqual(@as(u8, 1), rc());
    reset();
    checkCharInformat("date");
    try t.expectEqual(@as(u8, 1), rc());
    reset();

    // The doc list pins the split boundary itself (D-018 re-derivation).
    try t.expect(isDocumentedInformat("pd", false));
    try t.expect(isDocumentedInformat("nengo", false)); // NLS See-Also named
    try t.expect(isDocumentedInformat("uuid", true));
    try t.expect(!isDocumentedInformat("yen", false));
    try t.expect(!isDocumentedInformat("nlpctn", false)); // FORMAT exists; the INFORMAT is named nowhere
    try t.expect(!isDocumentedInformat("negparen", false)); // format-only name (doc excludes it as an informat)
    try t.expect(!isDocumentedInformat("date", true)); // $DATE informat is "not found" in real SAS
    try t.expect(!isDocumentedInformat("charzb", false)); // $CHARZB only (CB exists BOTH ways — not a probe)
}

test "GAP-fmtwrite-unimpl: P/ORDINAL/YEN + locale-driven NL* fail loud (no silent BEST/raw fallback)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    g_nofmterr = false;
    // doc-finder tick143 flagged FRACT/D/P/ORDINAL + these four as having no
    // write renderer. FRACTw. (p.224), Dw.p (p.170), NENGOw. (p.257),
    // EUROw.d/EUROXw.d (pp.215/218) and the locale-invariant NLPCTIw.d (p.417)
    // / NLPCTNw.d (p.418) are now implemented (tests below). Still loud:
    //  - `p`, `ordinal`, `yen`: none exists in the SAS 9.4 Formats and
    //    Informats Reference (checked the dictionary, the category lists, and
    //    all nine docs) — D-015: an absent name is never implemented.
    //  - `nlpct` (p.415), `nlpctp` (p.419), `nlmnyi` (p.410), `nlmnieur`
    //    (p.331): output depends on the SESSION locale ("The output value
    //    depends on the locale" / separators "locale-specific") and opensas
    //    has no LOCALE= option — any rendering would be a guessed symbol.
    const names = [_][]const u8{ "p", "ordinal", "yen", "nlpct", "nlpctp", "nlmnyi", "nlmnieur" };
    for (names) |n| {
        g_fmt_error = false;
        g_test_last_err = "";
        const spec = try std.fmt.allocPrint(a, "{s}10.2", .{n});
        _ = try apply(a, .{ .num = 0.5 }, spec);
        try t.expect(formatErrored()); // loud, not silently rendered
        try t.expect(std.mem.indexOf(u8, g_test_last_err, n) != null); // names the format
    }
    g_fmt_error = false; // reset module state for other tests
}

test "GAP-fmtwrite-unimpl: NENGOw. writes Japanese era dates (p.257)" {
    // The entry's own example: 15342 = 02JAN2002 = Heisei 14, all five widths.
    try expectFmt("H14", .{ .num = 15342 }, "nengo3.");
    try expectFmt("H14/01", .{ .num = 15342 }, "nengo6.");
    try expectFmt("H.140102", .{ .num = 15342 }, "nengo8.");
    try expectFmt("H14/01/02", .{ .num = 15342 }, "nengo9.");
    try expectFmt("H.14/01/02", .{ .num = 15342 }, "nengo10.");
    // Default w 10; Alignment Left (pads right on a wider field).
    try expectFmt("H.14/01/02", .{ .num = 15342 }, "nengo.");
    try expectFmt("H.14/01/02  ", .{ .num = 15342 }, "nengo12.");
    // Era boundaries: Showa 64 ends 07JAN1989, Heisei 1 begins 08JAN1989;
    // Heisei 31 ends 30APR2019, Reiwa 1 begins 01MAY2019; Meiji 45 ends
    // 29JUL1912, Taisho 1 begins 30JUL1912.
    const d = struct {
        fn f(y: i64, m: i64, dd: i64) f64 {
            return @floatFromInt(daysFromCivil(y, m, dd) + sas_epoch_days);
        }
    }.f;
    try expectFmt("S.64/01/07", .{ .num = d(1989, 1, 7) }, "nengo10.");
    try expectFmt("H.01/01/08", .{ .num = d(1989, 1, 8) }, "nengo10.");
    try expectFmt("H.31/04/30", .{ .num = d(2019, 4, 30) }, "nengo10.");
    try expectFmt("R.01/05/01", .{ .num = d(2019, 5, 1) }, "nengo10.");
    try expectFmt("M.45/07/29", .{ .num = d(1912, 7, 29) }, "nengo10.");
    try expectFmt("T.01/07/30", .{ .num = d(1912, 7, 30) }, "nengo10.");
    // Pre-Meiji (doc silent) → asterisks, never a fabricated era letter.
    try expectFmt("**********", .{ .num = d(1868, 9, 7) }, "nengo10.");
    // Interpolated rungs (the doc shows no output for w7/w5/w4/w2).
    try expectFmt("H140102", .{ .num = 15342 }, "nengo7.");
    try expectFmt("H1401", .{ .num = 15342 }, "nengo5.");
    try expectFmt("H.14", .{ .num = 15342 }, "nengo4.");
    try expectFmt("H1", .{ .num = 15342 }, "nengo2.");
    // Missing → dot, left-justified.
    try expectFmt(".         ", .{ .num = std.math.nan(f64) }, "nengo10.");
}

test "GAP-fmtwrite-unimpl: EUROw.d/EUROXw.d write the euro symbol (pp.215/218)" {
    // The doc example value 1254.71, all four widths of both logs.
    try expectFmt(" E1,254.71", .{ .num = 1254.71 }, "euro10.2");
    try expectFmt("1,255", .{ .num = 1254.71 }, "euro5.");
    try expectFmt("E1,254.71", .{ .num = 1254.71 }, "euro9.2");
    try expectFmt("     E1,254.710", .{ .num = 1254.71 }, "euro15.3");
    try expectFmt(" E1.254,71", .{ .num = 1254.71 }, "eurox10.2");
    try expectFmt("1.255", .{ .num = 1254.71 }, "eurox5.");
    try expectFmt("E1.254,71", .{ .num = 1254.71 }, "eurox9.2");
    try expectFmt("     E1.254,710", .{ .num = 1254.71 }, "eurox15.3");
    // The w=6 default-length logs (p.217, p.220): the ladder drops the SYMBOL
    // before the grouping (`55,555`, not `E55555`), then BESTw — whose
    // separators are NOT swapped under EUROX (`7.78E6`).
    try expectFmt("E4,444", .{ .num = 4444 }, "euro.");
    try expectFmt("55,555", .{ .num = 55555 }, "euro.");
    try expectFmt("666666", .{ .num = 666666 }, "euro.");
    try expectFmt("7.78E6", .{ .num = 7777777 }, "euro.");
    try expectFmt("8.89E7", .{ .num = 88888888 }, "euro.");
    try expectFmt("E4.444", .{ .num = 4444 }, "eurox.");
    try expectFmt("55.555", .{ .num = 55555 }, "eurox.");
    try expectFmt("7.78E6", .{ .num = 7777777 }, "eurox.");
    // Missing → dot right-justified (Alignment: Right), like DOLLAR.
    try expectFmt("     .", .{ .num = std.math.nan(f64) }, "euro.");
}

test "GAP-fmtwrite-unimpl: NLPCTIw.d/NLPCTNw.d locale-invariant percents (pp.417/418)" {
    // NLPCTI: minus sign, comma/period ALWAYS, left-justified — the NLPCT
    // entry's example shows this exact value identical under en_US and
    // German_Germany (`-1,234.57%`).
    try expectFmt("-1,234.57%                      ", .{ .num = -12.3456789 }, "nlpcti32.2");
    try expectFmt("7.5%    ", .{ .num = 0.075 }, "nlpcti8.1");
    try expectFmt("8%    ", .{ .num = 0.075 }, "nlpcti."); // default w6 d0, left
    // NLPCTN: minus sign, no separators, documented trailing blank (p.418 Tip).
    try expectFmt("  -2% ", .{ .num = -0.02 }, "nlpctn6."); // the doc example
    try expectFmt("   7.5% ", .{ .num = 0.075 }, "nlpctn8.1");
    try expectFmt("  50% ", .{ .num = 0.5 }, "nlpctn6.");
    try expectFmt("     .", .{ .num = std.math.nan(f64) }, "nlpctn6.");
}

test "GAP-fmtwrite-unimpl: FRACTw. writes reduced fractions (p.224)" {
    g_nofmterr = false;
    g_fmt_error = false;
    // The two documented rows (p.224 Example, `put x fract8.`): right-justified
    // in 8, reduced form.
    try expectFmt("     2/3", .{ .num = 0.6666666667 }, "fract8.");
    try expectFmt(" 174/625", .{ .num = 0.2784 }, "fract8.");
    // Default w 10 (p.224); sign inside the field; integer → n/1; missing → `.`.
    try expectFmt("       2/3", .{ .num = 0.6666666667 }, "fract.");
    try expectFmt("    -1/2", .{ .num = -0.5 }, "fract8.");
    try expectFmt("     5/1", .{ .num = 5 }, "fract8.");
    try expectFmt("     0/1", .{ .num = 0 }, "fract8.");
    try expectFmt("       .", .{ .num = std.math.nan(f64) }, "fract8.");
    // An integer whose n/1 overflows the field prints as the exact integer,
    // not a coarser inexact fraction; nothing fitting → asterisks.
    try expectFmt(" 123456", .{ .num = 123456 }, "fract7.");
    try expectFmt("123456/1", .{ .num = 123456 }, "fract8.");
    try expectFmt("**********", .{ .num = 1e300 }, "fract10.");
    try t.expect(!formatErrored());
}

test "GAP-fmtwrite-unimpl: Dw.p aligns decimals by magnitude group (p.170)" {
    g_nofmterr = false;
    g_fmt_error = false;
    // All six documented d10.4 rows (p.170–171 Example, `put x d10.4;`):
    // m ≥ p → 1 decimal; m < p → 5, right-justified in 10.
    try expectFmt("   12345.0", .{ .num = 12345 }, "d10.4");
    try expectFmt("    1234.5", .{ .num = 1234.5 }, "d10.4");
    try expectFmt(" 123.45000", .{ .num = 123.45 }, "d10.4");
    try expectFmt("  12.34500", .{ .num = 12.345 }, "d10.4");
    try expectFmt("   1.23450", .{ .num = 1.2345 }, "d10.4");
    try expectFmt("   0.12345", .{ .num = 0.12345 }, "d10.4");
    // Defaults: w 12, p 3; p=0 → 3 (p.170: "omitted or specified as 0 → 3").
    try expectFmt("  1.23450000", .{ .num = 1.2345 }, "d.");
    try expectFmt(" 12345.000", .{ .num = 12345 }, "d10.0");
    try expectFmt(" 12345.000", .{ .num = 12345 }, "d10.");
    // Negative, zero, missing, huge (d clamps to 0 and shrinks to fit).
    try expectFmt("  -1.50000", .{ .num = -1.5 }, "d10.4");
    try expectFmt("   0.00000", .{ .num = 0 }, "d10.4");
    try expectFmt("         .", .{ .num = std.math.nan(f64) }, "d10.4");
    try expectFmt(" 100000000", .{ .num = 1e8 }, "d10.4");
    try t.expect(!formatErrored());
}

test "BUG-charfmtsink: $QUOTE wraps; unknown $format fails loud (not a silent pad)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // $QUOTE wraps in double quotes then pads/truncates to w.
    try expectFmt("\"Hi\"    ", .{ .str = "Hi" }, "$quote8.");
    try expectFmt("\"Hi\"", .{ .str = "Hi" }, "$quote.");
    // Known char builtins unchanged (no false-positive error).
    g_nofmterr = false;
    g_fmt_error = false;
    g_test_last_err = "";
    try expectFmt("Hi  ", .{ .str = "Hi" }, "$char4.");
    try expectFmt("HI      ", .{ .str = "Hi" }, "$upcase8.");
    try t.expect(!formatErrored());
    // An unknown $format is NO LONGER a silent sink — fail loud (captured, not
    // stderr, in a test build) then still render the raw pad so output survives.
    g_test_last_err = "";
    const out = try apply(a, .{ .str = "Hi" }, "$zzznotreal8.");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "zzznotreal") != null);
    try t.expectEqualStrings("Hi      ", out); // fallback raw pad
    g_fmt_error = false; // reset module state for other tests
}

test "PICTURE truncates the scaled value by default; rounding is opt-in (BUG-picturetrunc)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // SAS 9.4 default is TRUNCATE (rounding needs the PICTURE `(round)` option):
    // 12.35 → `  12.3` and 99.99 → `  99.9`, NOT the rounded `  12.4` / ` 100.0`
    // (leading `0` selectors blank-suppress — see BUG-picturedigitsel test below).
    const entries = [_]UserFmtEntry{.{ .lo = -1e300, .hi = 1e300, .label = "0000.0" }};
    const cat = [_]UserFmt{.{ .name = "p", .is_char = false, .is_picture = true, .entries = &entries }};
    setUserFormats(&cat);
    defer clearUserFormats();
    try t.expectEqualStrings("  12.3", try apply(a, .{ .num = 12.35 }, "p."));
    try t.expectEqualStrings("  99.9", try apply(a, .{ .num = 99.99 }, "p."));
    try t.expectEqualStrings("  12.5", try apply(a, .{ .num = 12.5 }, "p.")); // exact .5 unaffected
}

test "PICTURE (round) rounds the scaled value to the last selector (GAP-pictureround)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // Same template, round on vs off: 3.98 under '009.9' → scaled 39.8 →
    // truncated `  3.9` by default, rounded `  4.0` with (round).
    const r_entries = [_]UserFmtEntry{.{ .lo = -1e300, .hi = 1e300, .label = "009.9", .round = true }};
    const t_entries = [_]UserFmtEntry{.{ .lo = -1e300, .hi = 1e300, .label = "009.9" }};
    const m_entries = [_]UserFmtEntry{.{ .lo = -1e300, .hi = 1e300, .label = "00009", .mult = 100, .round = true }};
    const cat = [_]UserFmt{
        .{ .name = "pr", .is_char = false, .is_picture = true, .entries = &r_entries },
        .{ .name = "pt", .is_char = false, .is_picture = true, .entries = &t_entries },
        .{ .name = "pm", .is_char = false, .is_picture = true, .entries = &m_entries },
    };
    setUserFormats(&cat);
    defer clearUserFormats();
    try t.expectEqualStrings("  4.0", try apply(a, .{ .num = 3.98 }, "pr."));
    try t.expectEqualStrings("  3.9", try apply(a, .{ .num = 3.98 }, "pt.")); // default still truncates
    try t.expectEqualStrings(" 1300", try apply(a, .{ .num = 12.999 }, "pm.")); // (round) × MULT=100: 1299.9 → 1300
}

test "PICTURE digit selectors: `0` suppresses leading zeros, nonzero zero-fills (BUG-picturedigitsel)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // SAS 9.4: "nines print zeros, zeros suppress". x=7 → pz='0000' gives `   7`,
    // pn='9999' gives `0007` (opensas had this INVERTED — silent-wrong zero-padded IDs).
    const z_entries = [_]UserFmtEntry{.{ .lo = -1e300, .hi = 1e300, .label = "0000" }};
    const n_entries = [_]UserFmtEntry{.{ .lo = -1e300, .hi = 1e300, .label = "9999" }};
    const cat = [_]UserFmt{
        .{ .name = "pz", .is_char = false, .is_picture = true, .entries = &z_entries },
        .{ .name = "pn", .is_char = false, .is_picture = true, .entries = &n_entries },
    };
    setUserFormats(&cat);
    defer clearUserFormats();
    try t.expectEqualStrings("   7", try apply(a, .{ .num = 7 }, "pz."));
    try t.expectEqualStrings(" 700", try apply(a, .{ .num = 700 }, "pz."));
    try t.expectEqualStrings("0007", try apply(a, .{ .num = 7 }, "pn."));
    try t.expectEqualStrings("0700", try apply(a, .{ .num = 700 }, "pn."));
}

test "format/informat width beyond the SAS cap fails loud + clamps (BUG-fmtwidthunbounded)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    // valid widths (≤32 numeric) render normally and never flag an error
    g_fmt_error = false;
    g_nofmterr = false;
    try t.expectEqualStrings("                            1.50", try apply(a, .{ .num = 1.5 }, "32.2"));
    try t.expect(!formatErrored());

    // an over-wide NUMERIC width (33 > 32) ERRORs and clamps — no over-wide field
    g_test_last_err = "";
    const s33 = try apply(a, .{ .num = 1.5 }, "33.2");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "33.2") != null);
    try t.expect(s33.len <= 32);

    // a huge width fails FAST (clamped) instead of hanging on a multi-GB alloc
    g_fmt_error = false;
    g_test_last_err = "";
    const sbig = try apply(a, .{ .num = 1 }, "4294967296.");
    try t.expect(formatErrored());
    try t.expect(sbig.len <= 32);

    // $CHAR width caps at 32767 (SAS), not 32
    g_fmt_error = false;
    g_test_last_err = "";
    _ = try apply(a, .{ .str = "x" }, "$40000.");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "32767") != null);
    g_fmt_error = false;
    _ = try apply(a, .{ .str = "x" }, "$32767.");
    try t.expect(!formatErrored());

    // same on the READ side: an over-wide numeric informat ERRORs; 32. is quiet
    g_fmt_error = false;
    _ = readNumeric("33.2", "12.5");
    try t.expect(formatErrored());
    g_fmt_error = false;
    _ = readNumeric("32.2", "12.5");
    try t.expect(!formatErrored());

    g_fmt_error = false; // reset module state for other tests
}

test "read informats: MONYY/YYQ parse correctly; unknown informat fails loud (BUG-informatreadloud)" {
    // MONYY reads to the 1st of the month; YYQ to the 1st of the quarter.
    // 01MAR2020 = SAS day 21975; 01APR2020 = 22006 (DATE9 of these below).
    try t.expectEqual(@as(f64, 21975), readNumeric("monyy7.", "MAR2020").num);
    try t.expectEqual(@as(f64, 21975), readNumeric("monyy5.", "MAR20").num); // 2-digit year
    try t.expectEqual(@as(f64, 22006), readNumeric("yyq6.", "2020Q2").num);
    try t.expectEqual(@as(f64, 22006), readNumeric("yyq.", "2020:2").num); // ':' separator
    try t.expect(readNumeric("monyy7.", "ZZZ2020").isMissing()); // bad month → missing

    // a plain numeric informat never flags an error
    g_fmt_error = false;
    g_nofmterr = false;
    _ = readNumeric("8.2", "12.5");
    _ = readNumeric("comma8.", "1,234");
    try t.expect(!formatErrored());

    // an unknown/unimplemented informat FAILS LOUD (captured in a test build)
    g_test_last_err = "";
    _ = readNumeric("bogusfmt5.", "x");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "bogusfmt") != null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "informat") != null);

    // options nofmterr suppresses it (silent fallback, matches the write side)
    g_fmt_error = false;
    g_nofmterr = true;
    _ = readNumeric("bogusfmt5.", "x");
    try t.expect(!formatErrored());

    g_nofmterr = false;
    g_fmt_error = false; // reset module state for other tests
}

test "unknown char informat fails loud (BUG-charinformatloud)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    g_nofmterr = false;
    g_fmt_error = false;

    // recognized char informats read exactly as before — no false trip
    try t.expectEqualStrings("HELLO", try charInformat(a, "upcase", "Hello"));
    try t.expectEqualStrings("abc", try charInformat(a, "", "abc")); // plain $w.
    try t.expectEqualStrings("abc", try charInformat(a, "char", "abc"));
    try t.expectEqualStrings("ABC", try charInformat(a, "hex", "414243"));
    try t.expect(!formatErrored());

    // an unknown/unimplemented char informat FAILS LOUD (captured in a test
    // build), verbatim field as the fallback so output survives
    g_test_last_err = "";
    const out = try charInformat(a, "zzz", "abc");
    try t.expect(formatErrored());
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "zzz") != null);
    try t.expect(std.mem.indexOf(u8, g_test_last_err, "informat") != null);
    try t.expectEqualStrings("abc", out);

    // options nofmterr suppresses it (silent fallback, matches the numeric side)
    g_fmt_error = false;
    g_nofmterr = true;
    _ = try charInformat(a, "octal", "abc");
    try t.expect(!formatErrored());

    g_nofmterr = false;
    g_fmt_error = false; // reset module state for other tests
}

test "BUG-commaxinformat: COMMAX/DOLLARX read European separators; US COMMA unchanged" {
    // European: PERIOD = grouping (dropped), COMMA = decimal point.
    try t.expectEqual(@as(f64, 1234.56), readNumeric("commax10.2", "1.234,56").num);
    try t.expectEqual(@as(f64, 1234.56), readNumeric("dollarx12.2", "$1.234,56").num);
    try t.expectEqual(@as(f64, 1234567.89), readNumeric("commax15.2", "1.234.567,89").num);
    // implied decimals still apply when the field carries no decimal comma
    try t.expectEqual(@as(f64, 1234.56), readNumeric("commax10.2", "123456").num);
    // parens negative (commalike) + a bare comma decimal
    try t.expectEqual(@as(f64, -500.5), readNumeric("commax10.1", "(500,5)").num);
    // US COMMA/DOLLAR roles unchanged: comma grouping, period decimal.
    try t.expectEqual(@as(f64, 1234.56), readNumeric("comma10.2", "1,234.56").num);
    try t.expectEqual(@as(f64, 1234.56), readNumeric("dollar12.2", "$1,234.56").num);
}

test "write formats: $UPCASE/$LOWCASE transform case (BUG-upcaseformat)" {
    try expectFmt("ABC", .{ .str = "abc" }, "$upcase.");
    try expectFmt("ABC", .{ .str = "AbC" }, "$upcase.");
    try expectFmt("ABC     ", .{ .str = "abc" }, "$upcase8."); // case then pad
    try expectFmt("AB", .{ .str = "abc" }, "$upcase2.");       // case then truncate
    try expectFmt("abc", .{ .str = "ABC" }, "$lowcase.");
}

test "read informats: JULIANw. parses packed Julian dates (BUG-julianinformat)" {
    // 1960 day 11 = SAS day 10; both yyddd and yyyyddd forms
    try t.expectEqual(@as(f64, 10), readNumeric("julian5.", "60011").num);
    try t.expectEqual(@as(f64, 10), readNumeric("julian7.", "1960011").num);
    // day 1 = Jan 1 = SAS day 0; leap-year day 366 valid in 2000, invalid in 1900
    try t.expectEqual(@as(f64, 0), readNumeric("julian5.", "60001").num);
    try t.expectEqual(@as(f64, 14975), readNumeric("julian7.", "2000366").num); // 2000-12-31
    try t.expect(readNumeric("julian7.", "1900366").isMissing()); // 1900 not leap
    try t.expect(readNumeric("julian5.", "61366").isMissing()); // day 366 in non-leap 1961
    try t.expect(readNumeric("julian5.", "60000").isMissing()); // day 0
    try t.expect(!formatErrored()); // a known informat never flags not-found
    g_fmt_error = false;
}

test "ANYDTDTE/ANYDTDTM/ANYDTTME informats read any date form (GAP-anydtinformat)" {
    // 15JAN2020 = SAS day 21929; every date form lands on the same day.
    try t.expectEqual(@as(f64, 21929), readNumeric("anydtdte9.", "15JAN2020").num); // DATE
    try t.expectEqual(@as(f64, 21929), readNumeric("anydtdte10.", "15/01/2020").num); // DDMMYY
    try t.expectEqual(@as(f64, 21929), readNumeric("anydtdte10.", "01/15/2020").num); // MMDDYY (DMY impossible → falls through)
    try t.expectEqual(@as(f64, 21929), readNumeric("anydtdte10.", "2020-01-15").num); // YMD
    try t.expectEqual(@as(f64, 21929), readNumeric("anydtdte8.", "20200115").num); // packed YMD
    // datetime: native and ISO forms → SAS day x 86400 + time (10:30:00 = 37800)
    const want: f64 = 21929 * 86400 + 37800;
    try t.expectEqual(want, readNumeric("anydtdtm19.", "15JAN2020:10:30:00").num);
    try t.expectEqual(want, readNumeric("anydtdtm19.", "2020-01-15T10:30:00").num);
    try t.expectEqual(@as(f64, 21929 * 86400), readNumeric("anydtdtm19.", "15JAN2020").num); // date-only → midnight
    // time: hh:mm[:ss] → seconds of day
    try t.expectEqual(@as(f64, 37800), readNumeric("anydttme8.", "10:30:00").num);
    try t.expectEqual(@as(f64, 37800), readNumeric("anydttme5.", "10:30").num);
    // unparseable → missing, never a loud not-found (whitelisted)
    try t.expect(readNumeric("anydtdte9.", "not a date").isMissing());
    try t.expect(readNumeric("anydtdtm19.", "nope").isMissing());
    try t.expect(readNumeric("anydttme8.", "nope").isMissing());
    try t.expect(!formatErrored());
    g_fmt_error = false;
}

test "BUG-datesingledigitday: DATEw. reads a 1-digit day (`1MAR90` → 11017)" {
    // Language Reference: Concepts Table 21.2 row 6's own example; the literal '1MAR1990'd gives
    // 11017 and MMDDYY8. on 1/2/90 gives 10959 — three paths, one class.
    try t.expectEqual(@as(?i64, 11017), parseDDMMMYYYY("1MAR90")); // dMMMyy
    try t.expectEqual(@as(?i64, 11017), parseDDMMMYYYY("01MAR90")); // ddMMMyy
    try t.expectEqual(@as(?i64, 11017), parseDDMMMYYYY("1MAR1990")); // dMMMyyyy
    try t.expectEqual(@as(?i64, 21929), parseDDMMMYYYY("15JAN2020")); // ddMMMyyyy (unchanged)
    try t.expectEqual(@as(?i64, null), parseDDMMMYYYY("31FEB2020")); // invalid day still rejected
    try t.expectEqual(@as(?i64, null), parseDDMMMYYYY("MAR1990")); // no day
    // through the informat paths that share the parser (ANYDTDTE / DATETIME)
    try t.expectEqual(@as(f64, 11017), readNumeric("anydtdte9.", "1MAR90").num);
    try t.expectEqual(@as(f64, 11017 * 86400), readNumeric("datetime20.", "1MAR1990:00:00:00").num);
    try t.expect(!formatErrored());
    g_fmt_error = false;
}

test "HEXw./OCTALw. informats read digit strings as integers (GAP-hexinformat/octalinformat)" {
    // Language Reference: Concepts Table 21.2: hex digits are the integer representation.
    try t.expectEqual(@as(f64, 15), readNumeric("hex4.", "000F").num);
    try t.expectEqual(@as(f64, 50338), readNumeric("hex8.", "C4A2").num);
    try t.expectEqual(@as(f64, 255), readNumeric("hex2.", "ff").num); // lowercase ok
    try t.expectEqual(@as(f64, 255), readNumeric("octal3.", "377").num);
    try t.expectEqual(@as(f64, 15), readNumeric("octal3.", "017").num);
    // the width slices the field: `hex2.` on "00FF" reads "00"
    try t.expectEqual(@as(f64, 0), readNumeric("hex2.", "00FF").num);
    // blank / non-digit for the base / >u64 overflow → missing
    try t.expect(readNumeric("hex4.", "    ").isMissing());
    try t.expect(readNumeric("hex4.", "GG").isMissing());
    try t.expect(readNumeric("octal3.", "89").isMissing());
    try t.expect(readNumeric("hex32.", "FFFFFFFFFFFFFFFFF").isMissing());
    // special missings still read; a known informat never flags not-found
    try t.expect(readNumeric("hex4.", ".A").isMissing());
    try t.expect(!formatErrored());
    g_fmt_error = false;
}

test "DT-prefixed formats write the date part of a datetime (GAP-dtformats)" {
    // 01JAN2020 = SAS day 21915; 12:30:00 → datetime 21915*86400 + 45000. The DT
    // formats must drop the time part and render the date (SAS 9.4 DTDATE/DTMONYY/
    // DTYEAR/DTWKDATX). 01JAN2020 is a Wednesday.
    const dt: Value = .{ .num = 21915.0 * 86400.0 + 45000.0 };
    try expectFmt("01JAN2020", dt, "dtdate9.");
    try expectFmt("01JAN20", dt, "dtdate7."); // width variant → 2-digit year
    try expectFmt("JAN2020", dt, "dtmonyy7.");
    try expectFmt("2020", dt, "dtyear4.");
    try expectFmt("Wednesday, 1 January 2020", dt, "dtwkdatx."); // WEEKDATX: non-padded day
    // a missing datetime renders "." (right-justified) like every date format, no fail-loud
    g_fmt_error = false;
    g_nofmterr = false;
    try expectFmt("        .", Value.missing, "dtdate9.");
    try t.expect(!formatErrored());
}

test "PERF-fmtscan: definition-time index equals the linear scan (discrete, first-match, range fallback)" {
    const num_entries = [_]UserFmtEntry{
        .{ .lo = 1, .hi = 1, .label = "one" },
        .{ .lo = 2, .hi = 2, .label = "two" },
        .{ .lo = 2, .hi = 2, .label = "two-dup" }, // duplicate key: the FIRST must win
        .{ .is_other = true, .label = "other-n" },
    };
    const char_entries = [_]UserFmtEntry{
        .{ .skey = "A", .label = "Alpha" },
        .{ .skey = "B ", .label = "Beta" }, // trailing blank in key → trimmed on match
        .{ .is_other = true, .label = "other-c" },
    };
    const range_entries = [_]UserFmtEntry{
        .{ .lo = 0, .hi = 59, .label = "Fail" },
        .{ .lo = 60, .hi = 100, .label = "Pass" },
    };
    const cat = [_]UserFmt{
        .{ .name = "nf", .is_char = false, .entries = &num_entries },
        .{ .name = "cf", .is_char = true, .entries = &char_entries },
        .{ .name = "gf", .is_char = false, .entries = &range_entries },
    };
    setUserFormats(&cat);
    defer clearUserFormats();

    // discrete numeric → indexed; first-match on the duplicate; miss & missing → OTHER
    try t.expect(fmt_index[0].indexed);
    try t.expectEqualStrings("one", lookupUserFmt(.{ .num = 1 }, .{ .name = "nf" }).?.label);
    try t.expectEqualStrings("two", lookupUserFmt(.{ .num = 2 }, .{ .name = "nf" }).?.label);
    try t.expectEqualStrings("other-n", lookupUserFmt(.{ .num = 9 }, .{ .name = "nf" }).?.label);
    try t.expectEqualStrings("other-n", lookupUserFmt(Value.missing, .{ .name = "nf" }).?.label);

    // discrete char → indexed; trailing-blank key trimmed; miss → OTHER
    try t.expect(fmt_index[1].indexed);
    try t.expectEqualStrings("Alpha", lookupUserFmt(.{ .str = "A" }, .{ .name = "cf", .is_char = true }).?.label);
    try t.expectEqualStrings("Beta", lookupUserFmt(.{ .str = "B" }, .{ .name = "cf", .is_char = true }).?.label);
    try t.expectEqualStrings("other-c", lookupUserFmt(.{ .str = "Z" }, .{ .name = "cf", .is_char = true }).?.label);

    // range format → NOT indexed; linear fallback still resolves the ranges; no OTHER → null
    try t.expect(!fmt_index[2].indexed);
    try t.expectEqualStrings("Fail", lookupUserFmt(.{ .num = 30 }, .{ .name = "gf" }).?.label);
    try t.expectEqualStrings("Pass", lookupUserFmt(.{ .num = 75 }, .{ .name = "gf" }).?.label);
    try t.expect(lookupUserFmt(.{ .num = 200 }, .{ .name = "gf" }) == null);
}
