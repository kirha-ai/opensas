//! Built-in SAS functions — the `call_fn` hook the evaluator (B1) dispatches
//! through. C1 installs it with `ev.call_fn = &functions.dispatch`. Args arrive
//! already evaluated (SAS built-ins are eager); we read the evaluator's arena
//! for results and its diagnostics for usage NOTEs.
//!
//! Function names are matched case-insensitively (SAS names fold). Argument
//! type is coerced the SAS way: a char in a numeric slot parses as a number
//! (blank/garbage → missing); a numeric in a char slot prints compactly.
//!
//! Coverage is the DATA-step core the corpus reaches now — numeric aggregates
//! and scalars, the common string ops, and a stub `put`/`input`. An unknown or
//! not-yet-built function is a diagnostic returning missing, so the corpus
//! runner names it as the next backlog item rather than silently guessing.
//! ponytail: `put(x,fmt)` renders via
//! the format engine (F1); `input(x,informat)` still ignores its informat.

const std = @import("std");
const eval = @import("eval.zig");
const pdv_mod = @import("pdv.zig");
const diag = @import("diag.zig");
const format = @import("format.zig");
const prx = @import("prx.zig");
const dsfns = @import("dsfns.zig");
const Value = @import("value.zig").Value;

/// Pure one-f64-in/one-f64-out numeric functions: arity 1, missing propagates,
/// no side effects. Data-over-code — add a row, not an `if`. Irregular numeric
/// fns (sqrt/round/mod: arity ranges, NOTEs, extra args) stay explicit below.
const UnaryFn = enum {
    abs, trunc, ceil, floor, sign,
    truncz, ceilz, floorz, // non-fuzzed forms (INTZ/CEILZ/FLOORZ)
    exp, ln, log2, log10,
    sin, cos, tan, asin, acos, atan,
    sinh, cosh, tanh, asinh, acosh, atanh,
    cot, csc, sec,
    digamma, trigamma, lgamma, gamma, erf, erfc,
    probnorm, probit, lfact, log1px, fuzz, airy, dairy, logistic,
};
pub const unary_math = [_]struct { name: []const u8, op: UnaryFn }{
    .{ .name = "abs", .op = .abs },
    .{ .name = "int", .op = .trunc },
    .{ .name = "ceil", .op = .ceil },
    .{ .name = "floor", .op = .floor },
    .{ .name = "sign", .op = .sign },
    .{ .name = "exp", .op = .exp },
    .{ .name = "log", .op = .ln }, // SAS LOG is the natural logarithm
    .{ .name = "log2", .op = .log2 },
    .{ .name = "log10", .op = .log10 },
    .{ .name = "sin", .op = .sin },
    .{ .name = "cos", .op = .cos },
    .{ .name = "tan", .op = .tan },
    .{ .name = "arsin", .op = .asin },
    .{ .name = "arcos", .op = .acos },
    .{ .name = "atan", .op = .atan },
    .{ .name = "sinh", .op = .sinh },
    .{ .name = "cosh", .op = .cosh },
    .{ .name = "tanh", .op = .tanh },
    .{ .name = "arsinh", .op = .asinh },
    .{ .name = "arcosh", .op = .acosh },
    .{ .name = "artanh", .op = .atanh },
    .{ .name = "cot", .op = .cot },
    .{ .name = "csc", .op = .csc },
    .{ .name = "sec", .op = .sec },
    // the `z` variants are the non-fuzzed forms; INT/CEIL/FLOOR fuzz (snap to a
    // near integer within 1e-12, per SAS 9.4) so e.g. floor(0.3/0.1)=3 not 2.
    .{ .name = "ceilz", .op = .ceilz },
    .{ .name = "floorz", .op = .floorz },
    .{ .name = "intz", .op = .truncz },
    .{ .name = "digamma", .op = .digamma },
    .{ .name = "trigamma", .op = .trigamma },
    .{ .name = "lgamma", .op = .lgamma },
    .{ .name = "gamma", .op = .gamma },
    .{ .name = "erf", .op = .erf },
    .{ .name = "erfc", .op = .erfc },
    .{ .name = "probnorm", .op = .probnorm },
    .{ .name = "probit", .op = .probit },
    .{ .name = "lfact", .op = .lfact },
    .{ .name = "log1px", .op = .log1px },
    .{ .name = "fuzz", .op = .fuzz },
    .{ .name = "airy", .op = .airy },
    .{ .name = "dairy", .op = .dairy },
    .{ .name = "logistic", .op = .logistic },
};

/// The character classes the ANYxxx/NOTxxx family scans for. `first`/`namechar`
/// are SAS-variable-name classes (VALIDVARNAME=V7); `graph` is printable-non-blank.
pub const CharClass = enum { alnum, alpha, digit, space, punct, upper, lower, cntrl, first, graph, namechar, print, xdigit };
pub const class_fns = [_]struct { name: []const u8, cls: CharClass, negate: bool }{
    .{ .name = "anyalnum", .cls = .alnum, .negate = false }, .{ .name = "notalnum", .cls = .alnum, .negate = true },
    .{ .name = "anyalpha", .cls = .alpha, .negate = false }, .{ .name = "notalpha", .cls = .alpha, .negate = true },
    .{ .name = "anydigit", .cls = .digit, .negate = false }, .{ .name = "notdigit", .cls = .digit, .negate = true },
    .{ .name = "anyspace", .cls = .space, .negate = false }, .{ .name = "notspace", .cls = .space, .negate = true },
    .{ .name = "anypunct", .cls = .punct, .negate = false }, .{ .name = "notpunct", .cls = .punct, .negate = true },
    .{ .name = "anyupper", .cls = .upper, .negate = false }, .{ .name = "notupper", .cls = .upper, .negate = true },
    .{ .name = "anylower", .cls = .lower, .negate = false }, .{ .name = "notlower", .cls = .lower, .negate = true },
    .{ .name = "anycntrl", .cls = .cntrl, .negate = false }, .{ .name = "notcntrl", .cls = .cntrl, .negate = true },
    .{ .name = "anyfirst", .cls = .first, .negate = false }, .{ .name = "notfirst", .cls = .first, .negate = true },
    .{ .name = "anygraph", .cls = .graph, .negate = false }, .{ .name = "notgraph", .cls = .graph, .negate = true },
    .{ .name = "anyname", .cls = .namechar, .negate = false }, .{ .name = "notname", .cls = .namechar, .negate = true },
    .{ .name = "anyprint", .cls = .print, .negate = false }, .{ .name = "notprint", .cls = .print, .negate = true },
    .{ .name = "anyxdigit", .cls = .xdigit, .negate = false }, .{ .name = "notxdigit", .cls = .xdigit, .negate = true },
};

/// Two-arg bitwise ops (BNOT is unary, handled separately).
const BitOp = enum { band, bor, bxor, blshift, brshift };
pub const bit_binops = [_]struct { name: []const u8, op: BitOp }{
    .{ .name = "band", .op = .band },
    .{ .name = "bor", .op = .bor },
    .{ .name = "bxor", .op = .bxor },
    .{ .name = "blshift", .op = .blshift },
    .{ .name = "brshift", .op = .brshift },
};

/// A bitwise arg → u32, or null if missing / out of the 0..2^32-1 range.
pub fn toU32(v: Value) ?u32 {
    const x = toNum(v);
    if (isMiss(x) or x < 0 or x > 4294967295) return null;
    return @intFromFloat(@round(x));
}

/// THE guard for every `@intFromFloat` on a user-supplied value (BUG-intfromfloat):
/// a non-finite (NaN/±inf) or out-of-safe-range float would trap `@intFromFloat`,
/// but SAS never traps — it yields missing. Returns the truncated i64, or null
/// when the value can't be one; callers map null to their SAS out-of-range result
/// (`Value.missing`, "", 0, or a clamp). 9e15 is past f64's exact-integer reach
/// and clear of i64's edges, so downstream index/date math can't overflow either.
pub fn toInt(x: f64) ?i64 {
    if (!std.math.isFinite(x) or @abs(x) >= 9.0e15) return null;
    return @intFromFloat(@trunc(x));
}

/// A 1-based position arg for search fns (FIND/ANY*): out-of-range magnitudes
/// clamp just past the relevant end (so the search finds nothing / scans the
/// whole string) instead of trapping. Missing (NaN) reads as "past the end".
fn clampPos(x: f64, len: usize) i64 {
    return toInt(x) orelse if (x < 0) -@as(i64, @intCast(len)) - 1 else @as(i64, @intCast(len)) + 1;
}

/// Collect the present (nonmissing) numeric args into an arena slice.
pub fn collectNums(ev: *eval.Evaluator, args: []const Value) ![]f64 {
    var list: std.ArrayList(f64) = .empty;
    for (args) |a| {
        const x = toNum(a);
        if (!isMiss(x)) try list.append(ev.arena, x);
    }
    return list.items;
}

pub fn ascF64(_: void, a: f64, b: f64) bool {
    return a < b;
}

/// Fritsch-Butland (1984) monotone piecewise-cubic Hermite, the method SAS's
/// MSPLINT documents. Knots (xs,ys) sorted ascending; returns the ordinate at x.
/// Passes through every knot exactly and never overshoots on a monotone run.
fn msplintEval(x: f64, xs: []const f64, ys: []const f64, d1: ?f64, dn: ?f64) f64 {
    const n = xs.len;
    if (n == 1) return ys[0];
    if (n > 64) return std.math.nan(f64);
    var h: [64]f64 = undefined;
    var s: [64]f64 = undefined;
    for (0..n - 1) |i| {
        h[i] = xs[i + 1] - xs[i];
        if (h[i] == 0) return std.math.nan(f64);
        s[i] = (ys[i + 1] - ys[i]) / h[i];
    }
    var d: [64]f64 = undefined;
    for (0..n) |i| {
        if (i == 0) {
            d[i] = d1 orelse endpointSlope(s[0], if (n > 2) s[1] else s[0], h[0], if (n > 2) h[1] else h[0]);
        } else if (i == n - 1) {
            d[i] = dn orelse endpointSlope(s[n - 2], if (n > 2) s[n - 3] else s[n - 2], h[n - 2], if (n > 2) h[n - 3] else h[n - 2]);
        } else if (s[i - 1] * s[i] <= 0) {
            d[i] = 0;
        } else {
            d[i] = 3 * (h[i - 1] + h[i]) / ((2 * h[i] + h[i - 1]) / s[i - 1] + (h[i] + 2 * h[i - 1]) / s[i]);
        }
    }
    var seg: usize = 0;
    while (seg < n - 2 and x > xs[seg + 1]) seg += 1;
    const fr = (x - xs[seg]) / h[seg];
    const fr2 = fr * fr;
    const fr3 = fr2 * fr;
    const h00 = 2 * fr3 - 3 * fr2 + 1;
    const h10 = fr3 - 2 * fr2 + fr;
    const h01 = -2 * fr3 + 3 * fr2;
    const h11 = fr3 - fr2;
    return h00 * ys[seg] + h10 * h[seg] * d[seg] + h01 * ys[seg + 1] + h11 * h[seg] * d[seg + 1];
}

/// Monotone-limited endpoint derivative (noncentered three-point, Fritsch-Carlson clamp).
fn endpointSlope(s0: f64, s1: f64, h0: f64, h1: f64) f64 {
    var d = ((2 * h0 + h1) * s0 - h0 * s1) / (h0 + h1);
    if (d * s0 <= 0) {
        d = 0;
    } else if (s0 * s1 <= 0 and @abs(d) > @abs(3 * s0)) {
        d = 3 * s0;
    }
    return d;
}

/// Σ(x-mean)² and the mean, in one pass-pair over the values.
pub fn cssMean(xs: []const f64) struct { css: f64, mean: f64 } {
    var s: f64 = 0;
    for (xs) |x| s += x;
    const m = s / @as(f64, @floatFromInt(xs.len));
    var css: f64 = 0;
    for (xs) |x| css += (x - m) * (x - m);
    return .{ .css = css, .mean = m };
}

/// Percentile by SAS's default definition 5 (same as PROC UNIVARIATE); `sorted`
/// is the nonmissing values ascending. 0 ≤ p ≤ 100.
pub fn pctlDef5(sorted: []const f64, p: f64) f64 {
    const n = sorted.len;
    if (n == 0) return std.math.nan(f64);
    const nc = @as(f64, @floatFromInt(n)) * p / 100.0;
    const j = @floor(nc);
    if (nc == j and j >= 1 and @as(usize, @intFromFloat(j)) < n) {
        const ji: usize = @intFromFloat(j); // integer position → average with next
        return (sorted[ji - 1] + sorted[ji]) / 2.0;
    }
    var idx: usize = @intFromFloat(@ceil(nc));
    if (idx < 1) idx = 1;
    if (idx > n) idx = n;
    return sorted[idx - 1];
}

/// Error function via Abramowitz & Stegun 7.1.26 (|error| ≤ 1.5e-7).
/// erfc for z ≥ 0 via a Chebyshev approximation, accurate to ~1e-15 (full f64) —
/// Numerical Recipes 3rd ed. Replaces the old ~1.5e-7 A&S 7.1.26 fit (BUG-erfaccuracy).
fn erfccheb(z: f64) f64 {
    const cof = [_]f64{
        -1.3026537197817094,   6.4196979235649026e-1, 1.9476473204185836e-2,
        -9.561514786808631e-3, -9.46595344482036e-4,  3.66839497852761e-4,
        4.2523324806907e-5,    -2.0278578112534e-5,   -1.624290004647e-6,
        1.303655835580e-6,     1.5626441722e-8,       -8.5238095915e-8,
        6.529054439e-9,        5.059343495e-9,        -9.91364156e-10,
        -2.27365122e-10,       9.6467911e-11,         2.394038e-12,
        -6.886027e-12,         8.94487e-13,           3.13092e-13,
        -1.12708e-13,          3.81e-16,              7.106e-15,
        -1.523e-15,            -9.4e-17,              1.21e-16,
        -2.8e-17,
    };
    const tc = 2.0 / (2.0 + z);
    const ty = 4.0 * tc - 2.0;
    var d: f64 = 0;
    var dd: f64 = 0;
    var j: usize = cof.len - 1;
    while (j > 0) : (j -= 1) {
        const tmp = d;
        d = ty * d - dd + cof[j];
        dd = tmp;
    }
    return tc * @exp(-z * z + 0.5 * (cof[0] + ty * d) - dd);
}

fn erfOf(x: f64) f64 {
    return if (x >= 0) 1.0 - erfccheb(x) else erfccheb(-x) - 1.0;
}

/// erfc(x) directly (avoids the 1−erf cancellation for large x).
fn erfcOf(x: f64) f64 {
    return if (x >= 0) erfccheb(x) else 2.0 - erfccheb(-x);
}

/// Compounding intervals per year for EFFRATE/NOMRATE (CONTINUOUS handled apart).
pub fn intervalsPerYear(s: []const u8) ?f64 {
    const w = std.mem.trim(u8, s, " ");
    if (eqi(w, "day")) return 365;
    if (eqi(w, "semimonth")) return 24;
    if (eqi(w, "month")) return 12;
    if (eqi(w, "quarter")) return 4;
    if (eqi(w, "semiyear")) return 2;
    if (eqi(w, "year")) return 1;
    return null;
}

pub fn matchesClass(c: u8, cls: CharClass) bool {
    return switch (cls) {
        .alnum => std.ascii.isAlphanumeric(c),
        .alpha => std.ascii.isAlphabetic(c),
        .digit => std.ascii.isDigit(c),
        .space => std.ascii.isWhitespace(c),
        .punct => std.ascii.isPrint(c) and c != ' ' and !std.ascii.isAlphanumeric(c),
        .upper => std.ascii.isUpper(c),
        .lower => std.ascii.isLower(c),
        .cntrl => std.ascii.isControl(c),
        .first => c == '_' or std.ascii.isAlphabetic(c), // valid 1st char of a SAS name
        .graph => std.ascii.isPrint(c) and c != ' ', // printable, non-blank
        .namechar => c == '_' or std.ascii.isAlphanumeric(c), // valid char of a SAS name
        .print => std.ascii.isPrint(c),
        .xdigit => std.ascii.isHex(c),
    };
}

/// ANYxxx/NOTxxx: 1-based position of the first char (from optional `start`, default
/// 1; negative → search backward) that is / is-not in the class; 0 if none.
pub fn charScan(ev: *eval.Evaluator, name: []const u8, args: []const Value, cls: CharClass, negate: bool) eval.Error!Value {
    if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
    const s = try toStr(ev, args[0]);
    var start: i64 = if (args.len == 2) clampPos(toNum(args[1]), s.len) else 1;
    if (start == 0) start = 1;
    if (start > 0) {
        var i: usize = @intCast(start - 1);
        while (i < s.len) : (i += 1)
            if (matchesClass(s[i], cls) != negate) return numVal(@floatFromInt(i + 1));
    } else {
        var i: i64 = @min(-start, @as(i64, @intCast(s.len)));
        while (i >= 1) : (i -= 1)
            if (matchesClass(s[@intCast(i - 1)], cls) != negate) return numVal(@floatFromInt(i));
    }
    return numVal(0);
}

/// Bind the live Library so the SCL dataset functions (OPEN/FETCH/GETVAR/…) can
/// resolve member names — the fix for BUG-sclbind. The executor must call this
/// once per run (e.g. in main's runData/runStep, where `lib` is in scope):
/// `sas.functions.bindLibrary(lib);`. Exposed here so a caller that already
/// imports `functions` needn't import `dsfns` directly.
var g_lib: ?*@import("exec.zig").Library = null;

pub fn bindLibrary(lib: *@import("exec.zig").Library) void {
    g_lib = lib; // so SYMGET/SYMEXIST/RESOLVE can read the macro-variable store
    dsfns.bind(lib);
}

/// The CLI's `libname` map, bound once per run so EXIST can disk-probe a member
/// nothing preloaded (BUG-existdisk). Re-exported like bindLibrary so callers
/// needn't import `dsfns` directly.
pub const DiskLibref = dsfns.Libref;
pub fn bindLibrefs(refs: []const DiskLibref) void {
    dsfns.bindLibrefs(refs);
}

/// Does `libref.member` already have a file on disk under a bound libref?
/// Same probe EXIST uses, re-exported for main's "was not replaced" rule
/// (GAP-errgatereplaces) — a `data <libref.x>` output target is deliberately
/// never preloaded, so the Library alone cannot answer it.
pub fn memberOnDisk(name: []const u8) bool {
    return dsfns.onDisk(name);
}

/// Owned macro-var value (PERF-macroaccum): a malloc'd buffer REUSED and grown
/// (doubling) across overwrites. The old design arena-duped every generation and
/// orphaned the previous one — the macro arena never frees — so accumulating
/// `%let s=&s tok;` in a %do loop cost O(M²) time+RAM (1.5 GB at M=8000 while
/// the live value is ~48 KB). Now memory tracks the live set. Shared by
/// macro.zig's symbol table and the SYMGET mirror below.
pub const VarVal = struct {
    buf: []u8 = &.{}, // the whole allocation; the value is buf[0..len]
    len: usize = 0,
    /// smp_allocator: freed blocks are RECYCLED (c_allocator isn't linked in the
    /// `zig build test` step; page_allocator's 4KB floor hurts the &&vart_&i
    /// macro-array idiom — thousands of small live vars). SmpAllocator comptime-
    /// asserts a threaded target, so the single-threaded wasm build uses
    /// wasm_allocator (also recycling).
    const alloc = if (@import("builtin").target.cpu.arch.isWasm())
        std.heap.wasm_allocator
    else
        std.heap.smp_allocator;
    pub fn set(v: *VarVal, bytes: []const u8) error{OutOfMemory}!void {
        if (bytes.len > v.buf.len) {
            const cap = @max(bytes.len, v.buf.len * 2, 64);
            v.buf = if (v.buf.len == 0) try alloc.alloc(u8, cap) else try alloc.realloc(v.buf, cap);
        }
        @memcpy(v.buf[0..bytes.len], bytes);
        v.len = bytes.len;
    }
    pub fn get(v: *const VarVal) []const u8 {
        return v.buf[0..v.len];
    }
    pub fn deinit(v: *VarVal) void {
        if (v.buf.len > 0) alloc.free(v.buf);
    }
};

/// The %let macro-variable table. macro.zig mirrors every `%let` into here (it
/// already imports this module, so this avoids an import cycle) — BUG-symgetlet.
/// SYMGET/SYMEXIST/RESOLVE read it alongside the runtime CALL SYMPUT table (g_lib).
var g_letvars: std.StringHashMapUnmanaged(VarVal) = .empty;

pub fn clearLetVars() void {
    // The map is global and must survive per-run arena death, so its storage,
    // keys AND values are all smp-owned (VarVal.alloc) — safe to iterate here.
    var it = g_letvars.iterator();
    while (it.next()) |e| {
        VarVal.alloc.free(e.key_ptr.*);
        e.value_ptr.deinit();
    }
    g_letvars.deinit(VarVal.alloc);
    g_letvars = .empty; // fresh per run; macro.expand calls this at the start
}

/// Drop the bound Library (test isolation — a bound Library from a short-lived
/// arena must not be read after that arena is freed).
pub fn unbindLibrary() void {
    g_lib = null;
}

/// Uniform per-run reset of module globals (taste #12): the PRX registry, SCL
/// open-handle table and HASHING_* digest table all hold pointers into a prior
/// run's freed arenas — a stale 1-based handle must die, not dangle. Mirrors
/// format.clearUserFormats; interpret() calls this at every run start.
pub fn resetPerRun() void {
    prx.resetPerRun();
    dsfns.resetPerRun();
    const ga = std.heap.page_allocator;
    for (hashing_table.items) |*c| {
        ga.free(c.method);
        if (c.key) |k| ga.free(k);
        c.buf.deinit(ga);
    }
    hashing_table.deinit(ga);
    hashing_table = .empty;
}
pub fn setLetVar(name: []const u8, val: []const u8) !void {
    const a = VarVal.alloc; // see clearLetVars: everything here must be smp-owned
    var kbuf: [256]u8 = undefined;
    const lower: ?[]const u8 = if (name.len <= kbuf.len) std.ascii.lowerString(&kbuf, name) else null;
    const lname = lower orelse try std.ascii.allocLowerString(a, name);
    if (g_letvars.getPtr(lname)) |v| return v.set(val); // overwrite in place (PERF-macroaccum)
    var v: VarVal = .{};
    try v.set(val);
    try g_letvars.put(a, if (lower) |l| try a.dupe(u8, l) else lname, v);
}
fn letVar(name: []const u8) ?[]const u8 {
    var buf: [256]u8 = undefined;
    if (name.len == 0 or name.len > buf.len) return null;
    if (g_letvars.getPtr(std.ascii.lowerString(buf[0..name.len], name))) |v| return v.get();
    return null;
}

/// A macro variable's value from either store: the runtime CALL SYMPUT table wins
/// (it's written later), then the %let table. Null if defined in neither.
fn macroVarValue(name: []const u8) ?[]const u8 {
    if (g_lib) |lib| if (lib.macroVar(name)) |v| return v;
    return letVar(name);
}

pub fn dispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    conv_ev = ev; // stash for the ev-less leaf `toNum` (see conv_ev docs)
    // Internal assignment desugar — the parser's `truncate` rewrites `c = rhs`
    // (c a known-length-n char var) to `__assignc(rhs, n)`. A char rhs truncates
    // to n, identical to the old substr(rhs,1,n) desugar; a NUMERIC rhs renders
    // BESTn. RIGHT-JUSTIFIED (Language Reference: Concepts p.124: assignment conversion uses the LHS
    // variable's length), which substr's BEST12 field got wrong — n<12 sliced
    // the field's blank LEFT edge (BUG-numcharwidth). Not a SAS function.
    if (eqi(name, "__assignc")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const nf = toNum(args[1]);
        if (isMiss(nf) or nf < 1) return .{ .str = "" }; // parser emits n ≥ 1
        const n: usize = @intFromFloat(@min(nf, 1e9));
        return switch (args[0]) {
            .str => |s| .{ .str = s[0..@min(n, s.len)] },
            .num => |x| blk: {
                // same automatic-conversion NOTE the substr desugar fired (GH#74b)
                ev.diags.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{}) catch {};
                break :blk .{ .str = try pdv_mod.numToChar(ev.arena, x, n) };
            },
        };
    }
    // The pure function families live in their own files (QL-A split); each
    // returns null for "not mine". Names are globally unique, so order is free.
    if (try @import("numfns.zig").dispatch(ev, name, args)) |v| return v;
    if (try @import("charfns.zig").dispatch(ev, name, args)) |v| return v;
    if (try @import("datefns.zig").dispatch(ev, name, args)) |v| return v;
    if (try @import("statfns.zig").dispatch(ev, name, args)) |v| return v;
    if (try @import("finfns.zig").dispatch(ev, name, args)) |v| return v;
    // What remains below is the stateful/system residue that reads module
    // globals or engine state (PRX, SCL dsfns, macro symbols, streaming
    // digests, v-family, LAG/DIF, conversion, environment).
    // ── PRX (Perl regex): PRXPARSE compiles → id; the rest take an id or a literal
    if (eqi(name, "prxparse")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return if (prx.parse(try toStr(ev, args[0]))) |id| .{ .num = @floatFromInt(id) } else Value.missing;
    }
    if (eqi(name, "prxmatch")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const id = prxId(args[0]) orelse return Value.missing;
        return .{ .num = @floatFromInt(prx.matchId(id, try toStr(ev, args[1]))) };
    }
    if (eqi(name, "prxchange")) {
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const id = prxId(args[0]) orelse return Value.missing;
        const times: i64 = @intFromFloat(@trunc(toNum(args[1])));
        return .{ .str = try prx.change(ev.arena, id, times, try toStr(ev, args[2])) };
    }
    if (eqi(name, "prxposn")) {
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const id = prxId(args[0]) orelse return Value.missing;
        const n: usize = @intFromFloat(@trunc(toNum(args[1])));
        if (args.len == 3) _ = prx.matchId(id, try toStr(ev, args[2])); // populate from this source
        return .{ .str = try ev.arena.dupe(u8, prx.posn(id, n)) };
    }
    if (eqi(name, "prxparen")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const id = prxId(args[0]) orelse return Value.missing;
        return .{ .num = @floatFromInt(prx.paren(id)) };
    }

    // ── SCL dataset access: OPEN → dsid, then FETCH/GETVAR read the current row
    if (eqi(name, "open")) {
        if (args.len < 1) return badArity(ev, name, "1 or 2", args.len);
        return .{ .num = dsfns.open(try toStr(ev, args[0])) }; // mode arg (args[1]) ignored — read-only
    }
    if (eqi(name, "exist")) {
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        // EXIST(member[, type]): type defaults to DATA. opensas can only create
        // DATA sets (CREATE VIEW/CATALOG/... fail loud), so any non-DATA member
        // type cannot exist → 0. EXIST is a boolean check, never errors on type.
        if (args.len == 2) {
            const ty = std.mem.trim(u8, try toStr(ev, args[1]), " ");
            if (ty.len != 0 and !eqi(ty, "data")) return .{ .num = 0 };
        }
        return .{ .num = dsfns.exist(try toStr(ev, args[0])) };
    }
    if (eqi(name, "pathname")) {
        // PATHNAME(ref[, type]): the OS path bound to a libref — our LIBNAME map,
        // via the dsfns libref binding (GAP-pathname). Blank for an unknown ref.
        // SAS searches filerefs first then librefs; type 'F' restricts to filerefs.
        // ponytail: no FILENAME store yet, so 'F' is always blank and the default
        // search is librefs-only — extend when a program defines filerefs.
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        if (args.len == 2) {
            const ty = std.mem.trim(u8, try toStr(ev, args[1]), " ");
            if (ty.len > 0 and (ty[0] == 'F' or ty[0] == 'f')) return .{ .str = "" };
        }
        const ref = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        // WORK always has a physical temp path in real SAS, and study macros use
        // PATHNAME(WORK) non-blankness as a health check (SPLIT: "LIBRARY WORK
        // DOES NOT EXIST" killed gen-2 AE/CM — QA-pathnamework). Our WORK is
        // in-memory; answer the OS temp root. ponytail: a real per-run WORK dir
        // if a program ever writes through this path.
        if (eqi(ref, "work")) return .{ .str = "/tmp" };
        const dir = dsfns.librefDir(ref) orelse "";
        return .{ .str = try ev.arena.dupe(u8, dir) };
    }
    if (eqi(name, "close")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .num = dsfns.close(toNum(args[0])) };
    }
    if (eqi(name, "attrn")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.attrn(toNum(args[0]), try toStr(ev, args[1])) };
    }
    if (eqi(name, "attrc")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.attrc(toNum(args[0]), try toStr(ev, args[1]))) };
    }
    if (eqi(name, "varnum")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.varnum(toNum(args[0]), try toStr(ev, args[1])) };
    }
    if (eqi(name, "fetch")) {
        if (args.len < 1) return badArity(ev, name, "1", args.len);
        return .{ .num = dsfns.fetch(toNum(args[0])) };
    }
    if (eqi(name, "fetchobs")) {
        if (args.len < 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.fetchobs(toNum(args[0]), toNum(args[1])) };
    }
    if (eqi(name, "curobs")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .num = dsfns.curobs(toNum(args[0])) };
    }
    if (eqi(name, "getvarn")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.getvarn(toNum(args[0]), toNum(args[1])) };
    }
    if (eqi(name, "getvarc")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.getvarc(toNum(args[0]), toNum(args[1]))) };
    }
    if (eqi(name, "varname")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.varname(toNum(args[0]), toNum(args[1]))) };
    }
    if (eqi(name, "varlabel")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.varlabelRaw(toNum(args[0]), toNum(args[1]))) };
    }
    if (eqi(name, "varinfmt")) { // n-th variable's read informat (EXEC-varattr: Column.informat)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.varinfmt(toNum(args[0]), toNum(args[1]))) };
    }
    if (eqi(name, "vartype")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.vartype(toNum(args[0]), toNum(args[1]))) };
    }
    if (eqi(name, "varlen")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.varlen(toNum(args[0]), toNum(args[1])) };
    }
    if (eqi(name, "varfmt")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.varfmt(toNum(args[0]), toNum(args[1]))) };
    }
    if (eqi(name, "cexist")) {
        if (args.len < 1) return badArity(ev, name, "1 or 2", args.len);
        return .{ .num = dsfns.cexist(try toStr(ev, args[0])) };
    }
    if (eqi(name, "nobs")) { // observation count of an open dataset (= ATTRN NOBS) (BUG-sclmeta)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .num = dsfns.attrn(toNum(args[0]), "NOBS") };
    }
    if (eqi(name, "note")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .num = dsfns.note(toNum(args[0])) };
    }
    if (eqi(name, "point")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.point(toNum(args[0]), toNum(args[1])) };
    }
    if (eqi(name, "rewind")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .num = dsfns.rewind(toNum(args[0])) };
    }
    if (eqi(name, "dropnote")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        return .{ .num = dsfns.dropnote(toNum(args[0]), toNum(args[1])) };
    }
    if (eqi(name, "dsname")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = try ev.arena.dupe(u8, dsfns.dsname(toNum(args[0]))) };
    }

    // ── streaming (running) digest: HASHING_INIT → integer handle; HASHING_PART
    // feeds bytes; HASHING_TERM → final UPPERCASE hex digest (doc p.986 example).
    // Handle indexes process-global state (see hashing_table). Invalid method or
    // handle → missing, matching the doc — but the doc SPLITS the two failure
    // modes for HASHING_TERM and we now match both (BUG-charfnsmissingtype,
    // p.986): "If the handle is invalid, HASHING_TERM returns a NUMERIC MISSING
    // value" vs "If the final digest cannot be computed, the result is BLANK".
    // HASHING_INIT/HASHING_HMAC_INIT return the numeric handle itself, so their
    // unknown-method arms are correctly numeric missing; HASHING_PART returns a
    // numeric rc, so its arms are numeric too. Only TERM is a character function.
    if (eqi(name, "hashing_init")) { // HASHING_INIT(method) → positive-integer handle
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const method = try toStr(ev, args[0]);
        var probe: [64]u8 = undefined;
        if (hashDigest(method, "", &probe) == null) return Value.missing; // unknown method
        const ga = std.heap.page_allocator;
        const m = ga.dupe(u8, method) catch return Value.missing; // outlives the arena
        hashing_table.append(ga, .{ .method = m, .buf = .empty }) catch return Value.missing;
        return .{ .num = @floatFromInt(hashing_table.items.len) }; // 1-based handle
    }
    if (eqi(name, "hashing_hmac_init")) { // HASHING_HMAC_INIT(method, key) → handle
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const method = try toStr(ev, args[0]);
        var probe: [64]u8 = undefined;
        if (hmacDigest(method, "", "", &probe) == null) return Value.missing; // unknown method
        const ga = std.heap.page_allocator;
        const m = ga.dupe(u8, method) catch return Value.missing;
        const k = ga.dupe(u8, try toStr(ev, args[1])) catch return Value.missing;
        hashing_table.append(ga, .{ .method = m, .buf = .empty, .key = k }) catch return Value.missing;
        return .{ .num = @floatFromInt(hashing_table.items.len) };
    }
    if (eqi(name, "hashing_part")) { // HASHING_PART(handle, data [,data…]) → rc 0
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const ctx = hashingCtx(args[0]) orelse return Value.missing;
        for (args[1..]) |a| ctx.buf.appendSlice(std.heap.page_allocator, try toStr(ev, a)) catch return Value.missing;
        return .{ .num = 0 };
    }
    if (eqi(name, "hashing_term")) { // HASHING_TERM(handle) → final hex digest (HMAC if keyed)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const ctx = hashingCtx(args[0]) orelse return Value.missing; // p.986: invalid HANDLE → numeric missing
        var buf: [64]u8 = undefined;
        // p.986: digest cannot be computed → the result is BLANK (character).
        // Defensive: the method was validated at INIT, so these arms are unreachable
        // today — they are written to the doc anyway so a future method table that
        // accepts more at INIT than at TERM cannot leak a numeric out of a
        // character function.
        const n = if (ctx.key) |k|
            hmacDigest(ctx.method, k, ctx.buf.items, &buf) orelse return .{ .str = "" }
        else
            hashDigest(ctx.method, ctx.buf.items, &buf) orelse return .{ .str = "" };
        return .{ .str = try hexEncodeUpper(ev, buf[0..n]) };
    }

    if (eqi(name, "typeof") or eqi(name, "vtype")) { // 'N' for numeric arg, 'C' for character
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = if (args[0] == .str) "C" else "N" };
    }
    if (eqi(name, "vtypex")) { // 'N'/'C' of the variable NAMED by the (char) argument
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        if (ev.pdv.indexOf(vn)) |i|
            return .{ .str = if (ev.pdv.vars.items[i].type == .num) "N" else "C" };
        note(ev, "VTYPEX: variable {s} not found", .{vn});
        return .{ .str = " " };
    }
    if (eqi(name, "vnamex")) { // canonical name of the variable NAMED by the (char) argument
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        if (ev.pdv.indexOf(vn)) |i|
            return .{ .str = try ev.arena.dupe(u8, ev.pdv.vars.items[i].name) };
        note(ev, "VNAMEX: variable {s} not found", .{vn});
        return .{ .str = " " };
    }
    if (eqi(name, "vlabelx")) { // the variable's label, or its name if it has none
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        if (g_lib) |lib| if (lib.varLabel(vn)) |lbl| return .{ .str = try ev.arena.dupe(u8, lbl) };
        if (ev.pdv.indexOf(vn)) |i| return .{ .str = try ev.arena.dupe(u8, ev.pdv.vars.items[i].name) };
        note(ev, "VLABELX: variable {s} not found", .{vn});
        return .{ .str = " " };
    }
    if (eqi(name, "vlength")) { // storage length: 8 for a numeric, the char width
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return numVal(switch (args[0]) {
            .num => 8,
            .str => |s| @floatFromInt(s.len), // a bare variable is resolved to its declared length in eval (BUG-vlength); here: a literal/expr width
        });
    }
    if (eqi(name, "vlengthx")) { // declared storage length of the variable NAMED by the arg
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const i = ev.pdv.indexOf(vn) orelse {
            note(ev, "VLENGTHX: variable {s} not found", .{vn});
            return numVal(0);
        };
        const v = ev.pdv.vars.items[i];
        // declared numeric LENGTH<8 (3..7) is the storage length; else 8 (GH#59)
        if (v.type == .num) return numVal(if (v.numlen >= 3 and v.numlen < 8) @floatFromInt(v.numlen) else 8);
        if (v.len > 0) return numVal(@floatFromInt(v.len)); // declared char length (BUG-vlength)
        return numVal(@floatFromInt(switch (v.value) { // undeclared char → its value width
            .str => |s| s.len,
            .num => 0,
        }));
    }
    if (eqi(name, "vvalue")) { // argument value rendered with its (default) format
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        // A bare value carries no format here (that lives in exec's format list, not
        // reachable from a by-value arg), so an unformatted variable renders as its
        // compact default — same as vvaluex's no-format path. VVALUEX(name) picks up
        // an explicit format from the PDV. A numeric arg still logs the
        // num→char NOTE here (only the CAT family is note-free, BUG-catnote).
        if (args[0] == .num) ev.diags.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{}) catch {};
        return .{ .str = try catStr(ev, args[0]) };
    }
    if (eqi(name, "vvaluex")) { // the variable's value rendered with its format (default if none)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const i = ev.pdv.indexOf(vn) orelse {
            note(ev, "VVALUEX: variable {s} not found", .{vn});
            return .{ .str = " " };
        };
        const v = ev.pdv.vars.items[i];
        if (v.format orelse libColFmt(vn, false)) |f| { // fall back to the dataset column (BUG-vformatxlabel)
            if (bestWidth(f)) |w| return .{ .str = try bestFmt(ev.arena, toNum(v.value), w) };
            return .{ .str = try format.apply(ev.arena, v.value, f) };
        }
        if (v.value == .num) ev.diags.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{}) catch {}; // BUG-catnote: note lives here, not in catStr
        return .{ .str = try catStr(ev, v.value) }; // unformatted → compact default
    }
    if (eqi(name, "vformatx")) { // complete format (uppercased, with period), e.g. COMMA8.2
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varFmtOf(ev, vn) orelse {
            note(ev, "VFORMATX: variable {s} not found", .{vn});
            return .{ .str = " " };
        };
        return .{ .str = try buildFmtStr(ev.arena, vf) };
    }
    if (eqi(name, "vformatnx")) { // just the format NAME (uppercased), e.g. COMMA
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varFmtOf(ev, vn) orelse {
            note(ev, "VFORMATNX: variable {s} not found", .{vn});
            return .{ .str = " " };
        };
        const up = try ev.arena.dupe(u8, vf.name);
        for (up) |*c| c.* = std.ascii.toUpper(c.*);
        return .{ .str = if (vf.char) try std.fmt.allocPrint(ev.arena, "${s}", .{up}) else up };
    }
    if (eqi(name, "vformatwx")) { // the format width
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varFmtOf(ev, vn) orelse {
            note(ev, "VFORMATWX: variable {s} not found", .{vn});
            return Value.missing;
        };
        return numVal(@floatFromInt(vf.w));
    }
    if (eqi(name, "vformatdx")) { // the format decimal count
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varFmtOf(ev, vn) orelse {
            note(ev, "VFORMATDX: variable {s} not found", .{vn});
            return Value.missing;
        };
        return numVal(@floatFromInt(vf.d));
    }
    // VINFORMAT*X — the read-informat twins of VFORMAT*X. The parser rewrites the
    // bare-variable forms (VINFORMAT(x) → VINFORMATX("x")); EXEC-varattr stores the
    // INFORMAT statement's spec on the PDV var so varInfmtOf can read it.
    if (eqi(name, "vinformatx")) { // complete informat (uppercased, with period), e.g. COMMA8.
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varInfmtOf(ev, vn) orelse {
            note(ev, "VINFORMATX: variable {s} not found", .{vn});
            return .{ .str = " " };
        };
        return .{ .str = try buildFmtStr(ev.arena, vf) };
    }
    if (eqi(name, "vinformatnx")) { // just the informat NAME (uppercased), e.g. COMMA
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varInfmtOf(ev, vn) orelse {
            note(ev, "VINFORMATNX: variable {s} not found", .{vn});
            return .{ .str = " " };
        };
        const up = try ev.arena.dupe(u8, vf.name);
        for (up) |*c| c.* = std.ascii.toUpper(c.*);
        return .{ .str = if (vf.char) try std.fmt.allocPrint(ev.arena, "${s}", .{up}) else up };
    }
    if (eqi(name, "vinformatwx")) { // the informat width
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varInfmtOf(ev, vn) orelse {
            note(ev, "VINFORMATWX: variable {s} not found", .{vn});
            return Value.missing;
        };
        return numVal(@floatFromInt(vf.w));
    }
    if (eqi(name, "vinformatdx")) { // the informat decimal count
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const vn = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const vf = varInfmtOf(ev, vn) orelse {
            note(ev, "VINFORMATDX: variable {s} not found", .{vn});
            return Value.missing;
        };
        return numVal(@floatFromInt(vf.d));
    }

    // ── macro-symbol access: BOTH stores — the runtime CALL SYMPUT table (g_lib)
    // and the %let table macro.zig mirrors here (BUG-symgetlet).
    if (eqi(name, "symget")) { // the value of a macro variable, blank if undefined
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const mv = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        return .{ .str = try ev.arena.dupe(u8, macroVarValue(mv) orelse "") };
    }
    if (eqi(name, "symexist")) { // 1 if the macro variable exists in either store, else 0
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const mv = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        return numVal(if (macroVarValue(mv) != null) 1 else 0);
    }
    if (eqi(name, "symglobl")) { // 1 if a GLOBAL macro var exists — all of ours are global
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return numVal(if (macroVarValue(std.mem.trim(u8, try toStr(ev, args[0]), " ")) != null) 1 else 0);
    }
    if (eqi(name, "symlocal")) { // no %local scope in our model → a var is never local
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        _ = try toStr(ev, args[0]);
        return numVal(0);
    }
    if (eqi(name, "resolve")) { // resolve &macro-var references in the argument text
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return .{ .str = try resolveMacros(ev, try toStr(ev, args[0])) };
    }
    if (eqi(name, "modexist")) { // MODEXIST: no external module system → never exists
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        return numVal(0);
    }

    // ── stateful queue: LAGn / DIFn (state lives on the Evaluator)
    if (queueDepth(name, "lag")) |n| {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        // LAG passes the Value through unchanged — a char lag returns the prior
        // row's string, a numeric lag the prior number (BUG-lagchar).
        return lagFifo(ev, name, n, args[0]);
    }
    if (queueDepth(name, "dif")) |n| {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        // DIF is numeric-only: coerce (a char arg → missing), keep a numeric FIFO.
        const x = toNum(args[0]);
        // NOTE-difcharnoterr: a non-convertible char arg already draws toNum's
        // converted+invalid-data NOTE pair but left _ERROR_=0 — SAS flags
        // _ERROR_=1 too (eval.zig's toNum pairs them). Blank char → missing
        // stays benign (silent there too).
        if (args[0] == .str and isMiss(x) and std.mem.trim(u8, args[0].str, " ").len != 0)
            try ev.setError();
        const prev = toNum(lagFifo(ev, name, n, numVal(x))); // separate FIFO from LAG
        return if (isMiss(x) or isMiss(prev)) Value.missing else numVal(x - prev);
    }

    // ── conversion (stubs: format/informat spec ignored — see header ponytail)
    // INPUTN/INPUTC are the runtime-informat variants of INPUT (the informat is a
    // char expression) — our INPUT already takes the informat as a value, so they
    // share the path. ponytail: no forced numeric/char return-type distinction.
    if (eqi(name, "input") or eqi(name, "inputn") or eqi(name, "inputc")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const s = try toStr(ev, args[0]); // the DATA: an implicit num→char here DOES note
        // a bare-numeric spec (`input(x, 4.)`) auto-converts 12-wide right-justified
        // (BUG-numcharwidth) — trim back to the spec text, and coerce it SILENTLY:
        // `input("123", 8.)` used to log a num→char NOTE for the `8.` (QA tick356 F4).
        const spec = try specText(ev, args[1]); // the informat (a char spec)
        const v = readInformat(spec, s);
        // Named `$` informats post-process the verbatim read (readInformat has no
        // allocator): $UPCASE/$LOWCASE case-fold, $QUOTE strips quotes, $HEX decodes
        // hex pairs (BUG-upcaseinformat / BUG-quoteinformat). Done here where
        // ev.arena is available; shared with the INPUT-statement path in io.zig.
        if (v == .str and spec.len > 0 and spec[0] == '$')
            return .{ .str = try format.charInformat(ev.arena, informatName(spec), v.str) };
        return v;
    }
    if (eqi(name, "put") or eqi(name, "putn") or eqi(name, "putc")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        // BUG-putbarenumnote: a bare-numeric spec (`put(x, 8.2)`) is a format, not
        // data — coerce it SILENTLY (specText), never toStr's num→char NOTE.
        const spec = try specText(ev, args[1]);
        // ±inf → render as missing, never leak "inf". But NaN carries the
        // special-missing payload (.A-.Z/._) — keep it so bestFmt/format emits
        // its letter (ISS-specialmiss-tochar), don't flatten it to plain `.`.
        const v: Value = if (args[0] == .num and std.math.isInf(args[0].num)) Value.missing else args[0];
        // BESTw. shows the value's natural/compact form (decimals kept, trailing
        // zeros dropped) — not a fixed `w.d`. The generic engine treats it as
        // `w.` (d=0) and would round 36.2 → "36"; handle it here, right-justified.
        if (bestWidth(spec)) |w| return .{ .str = try bestFmt(ev.arena, toNum(v), w) };
        return .{ .str = try format.apply(ev.arena, v, spec) };
    }

    // ── system / environment: correct in a base session with no options set
    if (eqi(name, "sysparm")) { // SYSPARM= option string; none set here → empty
        if (args.len != 0) return badArity(ev, name, "0", args.len);
        return .{ .str = "" };
    }
    if (eqi(name, "sysrc")) { // last system-error number; none → 0
        if (args.len != 0) return badArity(ev, name, "0", args.len);
        return numVal(0);
    }
    if (eqi(name, "sysmsg")) { // last dataset/file-function message; none → empty
        if (args.len != 0) return badArity(ev, name, "0", args.len);
        return .{ .str = "" };
    }
    if (eqi(name, "wto")) { // write to the operator console (z/OS); log it and return 0
        // ponytail: no operator console here — surface the text as a NOTE.
        if (args.len >= 1) note(ev, "WTO: {s}", .{try toStr(ev, args[0])});
        return numVal(0);
    }
    if (eqi(name, "sleep")) { // SAS SLEEP returns its first argument
        // ponytail: a batch interpreter does NOT actually suspend — returning n
        // honors the documented return value without stalling the run.
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const n = toNum(args[0]);
        if (isMiss(n) or n < 0) return Value.missing;
        return numVal(n);
    }

    if (eqi(name, "msplint")) { // ordinate of a monotonicity-preserving interpolating spline
        // MSPLINT(x, n, X1..Xn, Y1..Yn <, D1, Dn>): Fritsch-Butland (1984) monotone
        // piecewise-cubic Hermite; interpolates knots exactly, never overshoots a monotone run.
        if (args.len < 3) return badArity(ev, name, "3 or more", args.len);
        const x = toNum(args[0]);
        const nf = toNum(args[1]);
        if (isMiss(x) or isMiss(nf) or nf < 1) return Value.missing;
        const n: usize = @intFromFloat(@trunc(nf));
        const rest = args.len - 2;
        if (rest != 2 * n and rest != 2 * n + 2) return badArity(ev, name, "x,n,Xs,Ys(+D1,Dn)", args.len);
        const xs = try ev.arena.alloc(f64, n);
        const ys = try ev.arena.alloc(f64, n);
        for (0..n) |i| {
            xs[i] = toNum(args[2 + i]);
            ys[i] = toNum(args[2 + n + i]);
            if (isMiss(xs[i]) or isMiss(ys[i])) return Value.missing;
        }
        const d1: ?f64 = if (rest == 2 * n + 2) blk: {
            const dd = toNum(args[2 + 2 * n]);
            break :blk if (isMiss(dd)) null else dd;
        } else null;
        const dn: ?f64 = if (rest == 2 * n + 2) blk: {
            const dd = toNum(args[3 + 2 * n]);
            break :blk if (isMiss(dd)) null else dd;
        } else null;
        return numVal(msplintEval(x, xs, ys, d1, dn));
    }

    // An unknown/unimplemented function logs ONCE as an ERROR (SAS-like), not a
    // NOTE + ERROR — `_ERROR_`/the corpus surface the err level.
    ev.diags.report(.err, 0, "function {s}() is not supported yet", .{name}) catch {};
    return Value.missing;
}

// ── aggregates ─────────────────────────────────────────────────────────────

const Agg = enum { sum, mean, min, max, n, nmiss };

pub fn agg(kind: Agg, args: []const Value) Value {
    var acc: f64 = 0;
    var cnt: usize = 0;
    var miss: usize = 0;
    var lo: f64 = std.math.inf(f64);
    var hi: f64 = -std.math.inf(f64);
    for (args) |a| {
        const x = toNum(a);
        if (isMiss(x)) {
            miss += 1;
            continue;
        }
        cnt += 1;
        acc += x;
        if (x < lo) lo = x;
        if (x > hi) hi = x;
    }
    return switch (kind) {
        .n => numVal(@floatFromInt(cnt)),
        .nmiss => numVal(@floatFromInt(miss)),
        .sum => if (cnt == 0) Value.missing else numVal(acc),
        .mean => if (cnt == 0) Value.missing else numVal(acc / @as(f64, @floatFromInt(cnt))),
        .min => if (cnt == 0) Value.missing else numVal(lo),
        .max => if (cnt == 0) Value.missing else numVal(hi),
    };
}

// ── shared helpers ─────────────────────────────────────────────────────────

/// SAS-style fuzz: snap to the nearest integer when within 1e-12 of it.
fn fuzzInt(x: f64) f64 {
    return if (@abs(x - @round(x)) < 1e-12) @round(x) else x;
}

pub fn unary(ev: *eval.Evaluator, name: []const u8, args: []const Value, op: UnaryFn) Value {
    if (args.len != 1) return badArity(ev, name, "1", args.len);
    const x = toNum(args[0]);
    if (isMiss(x)) return Value.missing;
    // ovfVal, not numVal: overflow (exp(710), sinh(710), …) emits the
    // math-domain NOTE on its way to missing (NOTE-overflownonote).
    return ovfVal(ev, name, switch (op) {
        .abs => @abs(x),
        // INT/CEIL/FLOOR fuzz: an argument within 1e-12 of an integer snaps to
        // it first (SAS 9.4), so FP noise like 0.3/0.1=2.9999…996 floors to 3.
        .trunc => @trunc(fuzzInt(x)),
        .ceil => @ceil(fuzzInt(x)),
        .floor => @floor(fuzzInt(x)),
        .truncz => @trunc(x),
        .ceilz => @ceil(x),
        .floorz => @floor(x),
        .sign => if (x > 0) @as(f64, 1) else if (x < 0) @as(f64, -1) else @as(f64, 0),
        .exp => @exp(x),
        // log-family: argument must be positive
        .ln => if (x > 0) @log(x) else return domErr(ev, name),
        .log2 => if (x > 0) @log2(x) else return domErr(ev, name),
        .log10 => if (x > 0) @log10(x) else return domErr(ev, name),
        .sin => @sin(x),
        .cos => @cos(x),
        .tan => @tan(x),
        .asin => if (@abs(x) <= 1) std.math.asin(x) else return domErr(ev, name),
        .acos => if (@abs(x) <= 1) std.math.acos(x) else return domErr(ev, name),
        .atan => std.math.atan(x),
        .sinh => std.math.sinh(x),
        .cosh => std.math.cosh(x),
        .tanh => std.math.tanh(x),
        .asinh => std.math.asinh(x),
        .acosh => if (x >= 1) std.math.acosh(x) else return domErr(ev, name),
        .atanh => if (@abs(x) < 1) std.math.atanh(x) else return domErr(ev, name),
        .cot => 1.0 / @tan(x),
        .csc => 1.0 / @sin(x),
        .sec => 1.0 / @cos(x),
        // gamma family: poles at the non-positive integers (LGAMMA: all x ≤ 0)
        .digamma => if (x <= 0 and x == @trunc(x)) return domErr(ev, name) else digammaOf(x),
        .trigamma => if (x <= 0 and x == @trunc(x)) return domErr(ev, name) else trigammaOf(x),
        .gamma => if (x <= 0 and x == @trunc(x)) return domErr(ev, name) else gammaOf(x),
        .lgamma => if (x > 0) lgammaOf(x) else return domErr(ev, name),
        .lfact => if (x >= 0) lgammaOf(x + 1) else return domErr(ev, name), // log(n!) = lgamma(n+1)
        .erf => erfOf(x),
        .erfc => erfcOf(x),
        // = 0.5·(1 + sign(x)·erf(|x|/√2)), via gammaP for precision
        .probnorm => 0.5 * (1.0 + (if (x >= 0) gammaP(0.5, x * x / 2.0) else -gammaP(0.5, x * x / 2.0))),
        .probit => if (x > 0 and x < 1) probitOf(x) else return domErr(ev, name),
        .log1px => if (x > -1) std.math.log1p(x) else return domErr(ev, name),
        .fuzz => fuzzInt(x),
        .airy => airyAi(x, false),
        .dairy => airyAi(x, true), // Ai′
        .logistic => 1.0 / (1.0 + @exp(-x)),
    });
}

/// Out-of-domain argument → SAS missing plus a NOTE.
pub fn domErr(ev: *eval.Evaluator, name: []const u8) Value {
    note(ev, "{s}: argument out of domain (result set to missing)", .{name});
    // MISC-fnseterror: SAS also sets _ERROR_=1 on an invalid argument — route
    // through eval's PDV setter so every fn file using domErr gets it. catch{}:
    // keeps the plain-Value signature (~40 cross-file callers); only OOM can
    // fail, and the NOTE (the fail-loud signal) is already out, same as note().
    ev.setError() catch {};
    return Value.missing;
}

/// `domErr` for a CHARACTER function: same NOTE and the same `_ERROR_=1`, but the
/// result is the CHARACTER missing — a blank — not a numeric `.`
/// (BUG-charfnsmissingtype). `domErr` itself cannot simply be made type-aware:
/// its ~40 callers are overwhelmingly numeric (PROBIT, LOG1PX, the financial
/// family …) and a numeric `.` is right for every one of them, so the FLAVOUR
/// belongs at the call site, not in a shared branch. Only the handful of
/// character functions that route through the domain path use this one: SUBPAD,
/// and (BUG-charfnsnodomerr) BYTE, COLLATE, HASHING and HASHING_HMAC — each
/// because its OWN doc entry says the failure is diagnosed, not because the
/// family should look uniform. Two arms deliberately do NOT come here and must
/// stay out: COLLATE with an omitted start-position (`collate(,,56)` is a
/// documented working example, p.524) and COLLATE's `length` (no prescribed
/// range in the doc). Same discipline as HASHING_TERM's split at p.986 —
/// invalid handle → numeric missing, uncomputable digest → blank.
pub fn domErrChar(ev: *eval.Evaluator, name: []const u8) Value {
    _ = domErr(ev, name); // NOTE + _ERROR_=1, one implementation
    return .{ .str = "" };
}

pub fn mapCase(ev: *eval.Evaluator, name: []const u8, args: []const Value, comptime f: fn (u8) u8) eval.Error!Value {
    if (args.len != 1) return badArity(ev, name, "1", args.len);
    const s = try toStr(ev, args[0]);
    const out = try ev.arena.dupe(u8, s);
    for (out) |*c| c.* = f(c.*);
    return .{ .str = out };
}

pub fn substr(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
    const s = try toStr(ev, args[0]);
    const posf = toNum(args[1]);
    if (isMiss(posf)) return .{ .str = "" };
    // SAS 9.4: a NONPOSITIVE position is INVALID for SUBSTR (read) — it logs a NOTE
    // that the 2nd argument is invalid and returns the WHOLE remainder from the
    // (clamped) start to the end, IGNORING length. This is deliberately UNLIKE
    // SUBSTRN, which begins at char 1 with the length reduced (SAS 9.4 functions
    // ref, SUBSTRN comparison table, p.1535). Was: clamp start→1 but keep length →
    // 'he' instead of 'hello' (SUBSTR-posclamp, silent-wrong). MISC-fnseterror:
    // SAS also sets _ERROR_=1 alongside the NOTE.
    if (posf < 1) {
        note(ev, "Invalid second argument to function SUBSTR.", .{});
        try ev.setError();
        return .{ .str = s };
    }
    // Compare against string bounds as floats first — pos may be huge and not fit
    // i64, so guard before @intFromFloat (which panics on overflow).
    // NOTE-substrpastend: a position PAST the end is invalid in SAS 9.4 too — same
    // NOTE + _ERROR_=1 as the nonpositive-position branch above, value still blank.
    if (posf > @as(f64, @floatFromInt(s.len))) {
        note(ev, "Invalid second argument to function SUBSTR.", .{});
        try ev.setError();
        return .{ .str = "" };
    }
    const pos: i64 = @intFromFloat(posf); // 1-based
    const start: usize = @intCast(pos - 1);
    const avail = s.len - start;
    var take = avail;
    if (args.len == 3) {
        const lenf = toNum(args[2]);
        if (!isMiss(lenf)) {
            if (lenf <= 0) {
                // SAS 9.4: a NONPOSITIVE length (zero or negative) is INVALID for
                // SUBSTR (read) — it logs a NOTE (3rd arg invalid) and returns the
                // remainder from position to the end (SUBSTRN comparison table,
                // p.1535). Was: return "" (BUG-substrneglen, silent-wrong). `take`
                // is already `avail` (the remainder), so just emit the NOTE.
                // MISC-fnseterror: SAS also sets _ERROR_=1 alongside the NOTE.
                note(ev, "Invalid third argument to function SUBSTR.", .{});
                try ev.setError();
            } else if (lenf > @as(f64, @floatFromInt(avail))) {
                // NOTE-substrlenpastend: a positive length that runs PAST the end
                // is invalid in SAS 9.4 too — same NOTE (3rd arg) + _ERROR_=1 as
                // the nonpositive-length branch above, value still the clamped
                // remainder. Strict `>`: an exact fit (lenf == avail) is valid.
                // Mirrors NOTE-substrpastend (2410a3b) for the position arg.
                note(ev, "Invalid third argument to function SUBSTR.", .{});
                try ev.setError();
                take = avail;
            } else take = @intFromFloat(lenf); // lenf < avail <= s.len, no overflow
        }
    }
    return .{ .str = s[start .. start + take] };
}

/// SAS's ONE shared default word-delimiter set for SCAN / COUNTW / FINDW on
/// ASCII (SCAN p.1465, COUNTW p.575, FINDW p.781):
/// blank ! $ % & ( ) * + , - . / ; < ^ |
/// Tab / CR / LF are NOT defaults (the `s` modifier adds them); `>` never is.
pub const word_delims = " !$%&()*+,-./;<^|";

/// Modifier letter → character class for the class-adder modifiers shared by
/// SCAN/COUNTW/FINDW/FINDC/COUNTC (a=alpha c=cntrl d=digit f=first-name g=graph
/// l=lower n=name p=punct s=space u=upper w=print x=xdigit).
pub fn classMod(m: u8) ?CharClass {
    return switch (std.ascii.toLower(m)) {
        'a' => .alpha, 'd' => .digit, 'u' => .upper, 'l' => .lower,
        's' => .space, 'p' => .punct, 'c' => .cntrl, 'f' => .first,
        'g' => .graph, 'n' => .namechar, 'w' => .print, 'x' => .xdigit,
        else => null,
    };
}

/// Effective word-delimiter spec for SCAN / COUNTW / FINDW (BUG-scanmodifiers).
pub const WordSpec = struct {
    set: [256]bool, // final delimiter set (class-add, i-fold, k-invert applied)
    keep_empty: bool = false, // m: consecutive/edge delimiters bound EMPTY words
    word_number: bool = false, // e (FINDW only — SCAN/COUNTW reject it)
    trim: bool = false, // t: caller trims trailing blanks of the string arg
    ci: bool = false, // i: set is already case-folded; FINDW also folds the word compare
};

/// Build the effective delimiter set from the char-list and SAS modifier
/// letters: class adders extend the set, k inverts it (only the listed/kept
/// chars are NON-delimiters), i case-folds, t trims string+list, m keeps empty
/// words, o is a semantic no-op here. q/r/b/v and unknown letters ERROR + null
/// (D-002: an unsupported modifier must never be a silent no-op).
pub fn wordSpec(ev: *eval.Evaluator, name: []const u8, list: []const u8, mods: []const u8) eval.Error!?WordSpec {
    var spec: WordSpec = .{ .set = undefined };
    var k = false;
    var classes: [16]CharClass = undefined;
    var ncls: usize = 0;
    for (mods) |m| {
        if (classMod(m)) |cc| {
            if (ncls < classes.len) {
                classes[ncls] = cc;
                ncls += 1;
            }
            continue;
        }
        switch (std.ascii.toLower(m)) {
            'k' => k = true,
            'i' => spec.ci = true,
            't' => spec.trim = true,
            'm' => spec.keep_empty = true,
            'e' => spec.word_number = true,
            'o', ' ' => {}, // o: process-once hint, no effect here; blanks ignored
            else => {
                ev.diags.report(.err, 0, "{s}() modifier '{c}' is not supported yet", .{ name, m }) catch {};
                return null;
            },
        }
    }
    const lst = if (spec.trim) std.mem.trimEnd(u8, list, " ") else list;
    var set = [_]bool{false} ** 256;
    for (lst) |c| set[c] = true;
    for (classes[0..ncls]) |cc| for (0..256) |c| {
        if (matchesClass(@intCast(c), cc)) set[c] = true;
    };
    if (spec.ci) for (0..128) |c| {
        if (set[c]) {
            set[std.ascii.toUpper(@intCast(c))] = true;
            set[std.ascii.toLower(@intCast(c))] = true;
        }
    };
    if (k) for (&set) |*b| {
        b.* = !b.*;
    };
    spec.set = set;
    return spec;
}

/// Split `s` into words over `set`: delimiter runs collapse (default) or each
/// delimiter bounds a field, empties included (`m` / keep_empty).
pub fn wordTokens(arena: std.mem.Allocator, s: []const u8, set: *const [256]bool, keep_empty: bool) eval.Error!std.ArrayList([]const u8) {
    var toks: std.ArrayList([]const u8) = .empty;
    if (keep_empty) {
        var start: usize = 0;
        for (s, 0..) |c, i| {
            if (set[c]) {
                try toks.append(arena, s[start..i]);
                start = i + 1;
            }
        }
        try toks.append(arena, s[start..]);
    } else {
        var i: usize = 0;
        while (i < s.len) {
            while (i < s.len and set[s[i]]) i += 1;
            const start = i;
            while (i < s.len and !set[s[i]]) i += 1;
            if (i > start) try toks.append(arena, s[start..i]);
        }
    }
    return toks;
}

/// `scan(str, n [, delims [, mods]])` — the n-th word. Consecutive delimiters
/// collapse (no empty words) unless `m` keeps them (BUG-scanmmod); `n < 0`
/// counts from the right; out of range → "". Class adders + k/i/t honored
/// (BUG-scanmodifiers); q/r/b etc. error loudly (D-002).
///
/// BUG-scanmissingtype: SCAN is a CHARACTER function (SAS 9.4 Functions and CALL
/// Routines: Reference, 5th ed., p.1462 — "Returns the nth word from a character
/// string"), so EVERY exit — including the invalid/missing-count and the
/// fail-loud modifier arms — must yield a BLANK CHARACTER value, never a numeric
/// missing. A numeric missing here flips the receiving variable's TYPE, so
/// `put (x) ($char10.);` errored out (rc 1) where SAS prints ten blanks (rc 0).
/// SUBSTR (:1087) and CHOOSEC already had this right; scan was the odd one out.
pub fn scan(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (args.len < 2 or args.len > 4) return badArity(ev, name, "2 to 4", args.len);
    var s = try toStr(ev, args[0]);
    const nf = toNum(args[1]);
    if (isMiss(nf)) return .{ .str = "" }; // invalid/missing count — still CHARACTER
    const n: i64 = toInt(nf) orelse return .{ .str = "" }; // huge index → out of range
    if (n == 0) return .{ .str = "" };
    const list = if (args.len >= 3) try toStr(ev, args[2]) else word_delims;
    const mods = if (args.len >= 4) try toStr(ev, args[3]) else "";
    const spec = (try wordSpec(ev, name, list, mods)) orelse return .{ .str = "" };
    if (spec.word_number) { // `e` is FINDW-only
        ev.diags.report(.err, 0, "{s}() modifier 'e' is not supported yet", .{name}) catch {};
        return .{ .str = "" };
    }
    if (spec.trim) s = std.mem.trimEnd(u8, s, " ");

    // Collect tokens once under the chosen split rule, then index (a negative n
    // counts from the right).
    const toks = try wordTokens(ev.arena, s, &spec.set, spec.keep_empty);
    const count = toks.items.len;
    if (count == 0) return .{ .str = "" };

    const idx: usize = if (n > 0) @intCast(n - 1) else blk: {
        const from_end = @as(i64, @intCast(count)) + n; // n < 0 → from the right
        if (from_end < 0) return .{ .str = "" };
        break :blk @intCast(from_end);
    };
    if (idx >= count) return .{ .str = "" };
    return .{ .str = try ev.arena.dupe(u8, toks.items[idx]) };
}

/// `find(str, sub [, mods] [, start])` — 1-based position of `sub` in `str`, 0 if
/// absent. Arg 3 is `start` when numeric, else modifiers (`i` case-insensitive,
/// `t` trim trailing blanks); a numeric arg 4 is always `start`.
/// Negative `start` searches right-to-left from `|start|`.
pub fn find(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (args.len < 2 or args.len > 4) return badArity(ev, name, "2 to 4", args.len);
    var s = try toStr(ev, args[0]);
    var sub = try toStr(ev, args[1]);
    var start: i64 = 1;
    var ci = false;
    var trim = false;
    if (args.len >= 3) {
        if (args[2] == .num) {
            start = clampPos(toNum(args[2]), s.len);
        } else for (try toStr(ev, args[2])) |c| {
            if (c == 'i' or c == 'I') ci = true;
            if (c == 't' or c == 'T') trim = true;
        }
    }
    if (args.len >= 4) start = clampPos(toNum(args[3]), s.len);
    if (trim) {
        s = std.mem.trimEnd(u8, s, " ");
        sub = std.mem.trimEnd(u8, sub, " ");
    }
    if (sub.len == 0 or sub.len > s.len) return numVal(0);

    // Negative start: search right-to-left, i.e. the largest starting position
    // p (1-based) with p <= |start| where `sub` matches.
    if (start < 0) {
        var p: usize = @min(@as(usize, @intCast(-start)), s.len - sub.len + 1);
        while (p >= 1) : (p -= 1) {
            const seg = s[p - 1 .. p - 1 + sub.len];
            const hit = if (ci) std.ascii.eqlIgnoreCase(seg, sub) else std.mem.eql(u8, seg, sub);
            if (hit) return numVal(@floatFromInt(p));
        }
        return numVal(0);
    }

    const from: usize = if (start > 1) @min(@as(usize, @intCast(start - 1)), s.len) else 0;
    if (from >= s.len) return numVal(0);
    const rel = if (ci) std.ascii.indexOfIgnoreCase(s[from..], sub) else std.mem.indexOf(u8, s[from..], sub);
    return numVal(@floatFromInt(if (rel) |p| from + p + 1 else 0));
}

/// `tranwrd(str, target, replacement)` — replace EVERY occurrence of `target`.
/// ponytail: empty target → unchanged; no trailing-blank trimming of the args.
pub fn tranwrd(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (args.len != 3) return badArity(ev, name, "3", args.len);
    const s = try toStr(ev, args[0]);
    const from = try toStr(ev, args[1]);
    const to = try toStr(ev, args[2]);
    if (from.len == 0) return .{ .str = try ev.arena.dupe(u8, s) };
    return .{ .str = try std.mem.replaceOwned(u8, ev.arena, s, from, to) };
}

/// `compress(source [, chars [, mods]])` — remove characters from `source`.
/// No `chars` → remove blanks; with `chars` → remove exactly that set. Modifiers:
/// `k` keep (instead of remove), `i` case-insensitive, and class adders that
/// extend the set, routed through classMod (a/d/p/s/l/u/n/f/g/w/c/x — the same
/// machinery COUNTC/SCAN use). Unknown letters ERROR loudly (D-002).
pub fn compress(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (args.len < 1 or args.len > 3) return badArity(ev, name, "1 to 3", args.len);
    const src = try toStr(ev, args[0]);

    var inset = [_]bool{false} ** 256;
    if (args.len >= 2) {
        for (try toStr(ev, args[1])) |c| inset[c] = true;
    } else {
        inset[' '] = true; // no chars arg → remove blanks
    }

    var keep = false;
    if (args.len == 3) {
        var ci = false;
        for (try toStr(ev, args[2])) |mm| {
            if (classMod(mm)) |cc| {
                addClass(&inset, cc);
                continue;
            }
            switch (std.ascii.toLower(mm)) {
                'k' => keep = true,
                'i' => ci = true,
                'o', ' ' => {}, // o: process-once hint, no effect here; blanks ignored
                else => {
                    ev.diags.report(.err, 0, "{s}() modifier '{c}' is not supported yet", .{ name, mm }) catch {};
                    return .{ .str = "" }; // BUG-scanmissingtype: COMPRESS is CHARACTER too
                },
            }
        }
        if (ci) for (0..128) |c| if (inset[c]) {
            inset[std.ascii.toUpper(@intCast(c))] = true;
            inset[std.ascii.toLower(@intCast(c))] = true;
        };
    }

    const out = try ev.arena.alloc(u8, src.len);
    var n: usize = 0;
    for (src) |c| if (inset[c] == keep) { // remove: keep non-members; keep-mode: keep members
        out[n] = c;
        n += 1;
    };
    return .{ .str = out[0..n] };
}

fn addClass(inset: *[256]bool, cls: CharClass) void {
    for (0..256) |c| if (matchesClass(@intCast(c), cls)) {
        inset[c] = true;
    };
}

test "BUG-compressclass: compress routes all class modifiers; unknown errors loud (D-002)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // keep-mode over class modifiers (the silently-dropped ones).
    const kn = try dispatch(&e, "compress", &.{ strV("a b!c@d"), strV(""), strV("kn") });
    try t.expectEqualStrings("abcd", kn.str);
    const kl = try dispatch(&e, "compress", &.{ strV("AbCdEf"), strV(""), strV("kl") });
    try t.expectEqualStrings("bdf", kl.str);
    const ku = try dispatch(&e, "compress", &.{ strV("AbCdEf"), strV(""), strV("ku") });
    try t.expectEqualStrings("ACE", ku.str);
    // original four still right.
    const kd = try dispatch(&e, "compress", &.{ strV("a1b2c3"), strV(""), strV("kd") });
    try t.expectEqualStrings("123", kd.str);
    const ka = try dispatch(&e, "compress", &.{ strV("Ab c9!"), strV(""), strV("ka") });
    try t.expectEqualStrings("Abc", ka.str);
    const rp = try dispatch(&e, "compress", &.{ strV("a,b!c"), strV(""), strV("p") });
    try t.expectEqualStrings("abc", rp.str);
    const rs = try dispatch(&e, "compress", &.{ strV("a b c"), strV(""), strV("s") });
    try t.expectEqualStrings("abc", rs.str);

    // unknown modifier → blank CHARACTER + captured err (never silent). The type
    // matters: COMPRESS is a character function (BUG-scanmissingtype), so even the
    // fail-loud arm must not hand back a numeric missing and flip the LHS's type.
    const before = h.diags.count();
    const bad = try dispatch(&e, "compress", &.{ strV("abc"), strV(""), strV("kz") });
    try t.expect(bad == .str);
    try t.expectEqualStrings("", bad.str);
    try t.expect(h.diags.count() > before);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[h.diags.count() - 1].message, "compress() modifier 'z' is not supported yet") != null);
}

pub fn eqi(a: []const u8, b: []const u8) bool {
    return std.ascii.eqlIgnoreCase(a, b);
}

pub fn isMiss(x: f64) bool {
    return std.math.isNan(x);
}

/// If `spec` names the BEST format (`best`, `best8.`, `BEST12.` …), return its
/// width (default 12); else null.
fn bestWidth(spec: []const u8) ?usize {
    var i: usize = 0;
    while (i < spec.len and std.ascii.isAlphabetic(spec[i])) i += 1;
    if (!eqi(spec[0..i], "best")) return null;
    const ws = i;
    while (i < spec.len and std.ascii.isDigit(spec[i])) i += 1;
    return std.fmt.parseInt(usize, spec[ws..i], 10) catch 12;
}

/// BESTw. rendering: the compact form (whole numbers without a decimal point,
/// others with trailing zeros dropped), right-justified in `w`. Missing → `.`.
/// ponytail: no scientific-notation fallback when the value overflows `w`.
fn bestFmt(a: std.mem.Allocator, x: f64, w: usize) ![]const u8 {
    // BESTw. bounds the value to w columns (fixed-or-E, most significant digits) —
    // NOT the raw f64 that overflowed the field (BESTFMT-explicit). Reuse the same
    // width-bounded logic the default numeric-display path uses, then right-justify.
    // bestNumW already renders missing (plain/special) via Value.missingChar —
    // ISS-specialmiss-tochar: no `.` shortcut, or `.K` would print as `.`.
    const body = try format.bestNumW(a, x, w);
    if (body.len >= w) return body;
    const out = try a.alloc(u8, w);
    @memset(out[0 .. w - body.len], ' ');
    @memcpy(out[w - body.len ..], body);
    return out;
}

/// The format attached to the variable `vn` names, decomposed for the VFORMAT*X
/// family. Null when the variable is unknown. An unformatted variable reports the
/// SAS default (BEST12. for numeric, $w. for character).
/// ponytail: the char default width is the current value's length — our data model
/// tracks no declared char length, so a genuinely unformatted char reports its
/// value width rather than SAS's fixed declared length.
const VarFmt = struct { char: bool, name: []const u8, w: usize, d: usize };
/// A FORMAT/INFORMAT attached to a column of some loaded dataset (not on the PDV
/// var): after `data d; format x dollar10.2; …; set d;`, the format lives on d's
/// column, not the fresh PDV var, so VFORMATX must fall back to it (BUG-vformatxlabel).
/// ponytail: first dataset with a matching formatted column wins — unambiguous for
/// the usual single-source SET; a same-named column with a different format in an
/// earlier set would shadow, which the corpus never hits.
fn libColFmt(vn: []const u8, want_informat: bool) ?[]const u8 {
    const lib = g_lib orelse return null;
    for (lib.sets.items) |ds| {
        if (ds.indexOf(vn)) |i| {
            const c = ds.columns.items[i];
            if ((if (want_informat) c.informat else c.format)) |f| return f;
        }
    }
    return null;
}

fn varFmtOf(ev: *eval.Evaluator, vn: []const u8) ?VarFmt {
    const i = ev.pdv.indexOf(vn) orelse return null;
    const v = ev.pdv.vars.items[i];
    if (v.format orelse libColFmt(vn, false)) |f| {
        const s = format.parseSpec(f);
        return .{ .char = s.is_char, .name = s.name, .w = s.w, .d = s.d };
    }
    if (v.type == .char) {
        const len = if (v.value == .str) std.mem.trimEnd(u8, v.value.str, " ").len else 0;
        return .{ .char = true, .name = "", .w = @max(len, 1), .d = 0 };
    }
    return .{ .char = false, .name = "BEST", .w = 12, .d = 0 };
}

/// The informat attached to `vn`, decomposed for the VINFORMAT*X family. Mirrors
/// varFmtOf but reads the read-informat attribute (EXEC-varattr stores it on the
/// PDV var). An unassigned informat reports the type default (like VFORMAT*X).
fn varInfmtOf(ev: *eval.Evaluator, vn: []const u8) ?VarFmt {
    const i = ev.pdv.indexOf(vn) orelse return null;
    const v = ev.pdv.vars.items[i];
    if (v.informat orelse libColFmt(vn, true)) |f| {
        const s = format.parseSpec(f);
        return .{ .char = s.is_char, .name = s.name, .w = s.w, .d = s.d };
    }
    if (v.type == .char) {
        const len = if (v.value == .str) std.mem.trimEnd(u8, v.value.str, " ").len else 0;
        return .{ .char = true, .name = "", .w = @max(len, 1), .d = 0 };
    }
    return .{ .char = false, .name = "BEST", .w = 12, .d = 0 };
}

/// Reassemble a VarFmt into SAS's canonical format string: `<$>NAME<w>.<d>`,
/// name uppercased (e.g. COMMA8.2, DATE9., $CHAR20., 8.2, BEST12.).
fn buildFmtStr(a: std.mem.Allocator, vf: VarFmt) ![]const u8 {
    const up = try a.dupe(u8, vf.name);
    for (up) |*c| c.* = std.ascii.toUpper(c.*);
    const d: []const u8 = if (vf.char) "$" else "";
    if (vf.w > 0 and vf.d > 0) return std.fmt.allocPrint(a, "{s}{s}{d}.{d}", .{ d, up, vf.w, vf.d });
    if (vf.w > 0) return std.fmt.allocPrint(a, "{s}{s}{d}.", .{ d, up, vf.w });
    return std.fmt.allocPrint(a, "{s}{s}.", .{ d, up });
}

/// Decimal places in a rounding unit: 0.1 → 1, 0.25 → 2, 1/5/10 → 0.
pub fn cleanDecimals(unit: f64) usize {
    var u = @abs(unit);
    var d: usize = 0;
    while (d < 12 and @abs(u - @round(u)) > 1e-9) : (d += 1) u *= 10;
    return d;
}

pub fn pow10(n: usize) f64 {
    var p: f64 = 1;
    for (0..n) |_| p *= 10;
    return p;
}

pub fn numVal(x: f64) Value {
    // BUG-mathoverflowinf: SAS has no infinity — overflow (exp(710), 1/0, …)
    // is a genuine missing, not a live ±inf that would defeat MISSING()/`x=.`
    // and misrank in sorts/comparisons. NaN passes through untouched: special
    // missings (.A–.Z, ._) ride in its payload.
    if (std.math.isInf(x)) return Value.missing;
    return .{ .num = x };
}

/// NOTE-overflownonote (tick183): numVal's overflow→missing collapse was the
/// ONLY silent numeric-error path — div-by-zero and math-domain errors both
/// NOTE. Route overflow through the same NOTE-emitting mechanism (note())
/// reusing domErr's exact math-domain wording; the value stays missing.
/// Unlike domErr this does NOT set _ERROR_ — only the NOTE side-effect is
/// added. numVal itself stays pure (no `ev`; ~40 cross-file callers, most of
/// them int-valued). ponytail: ev-less callers that could theoretically
/// overflow (agg sum/mean, splines) stay silent until they grow an `ev`.
pub fn ovfVal(ev: *eval.Evaluator, name: []const u8, x: f64) Value {
    if (std.math.isInf(x)) {
        note(ev, "{s}: argument out of domain (result set to missing)", .{name});
        return Value.missing;
    }
    return .{ .num = x };
}

/// Soundex code for a letter (0 = vowel / H / W / Y).
pub fn soundexCode(c: u8) u8 {
    return switch (std.ascii.toUpper(c)) {
        'B', 'F', 'P', 'V' => 1,
        'C', 'G', 'J', 'K', 'Q', 'S', 'X', 'Z' => 2,
        'D', 'T' => 3,
        'L' => 4,
        'M', 'N' => 5,
        'R' => 6,
        else => 0,
    };
}

/// Value equality for WHICHN/WHICHC: chars compare blank-trimmed, else numeric
/// (a missing value never equals anything).
pub fn valuesEqual(a: Value, b: Value) bool {
    if (a == .str and b == .str)
        return std.mem.eql(u8, std.mem.trimEnd(u8, a.str, " "), std.mem.trimEnd(u8, b.str, " "));
    const x = toNum(a);
    const y = toNum(b);
    return !isMiss(x) and !isMiss(y) and x == y;
}

/// n! for a non-negative integer `n` (as f64; overflows to +inf past ~170!).
pub fn factorial(n: f64) f64 {
    if (n > 170) return std.math.inf(f64); // 171! overflows f64 → bound the loop
    var r: f64 = 1;
    var k: f64 = 2;
    while (k <= n) : (k += 1) r *= k;
    return r;
}

/// COMB(n,r), the binomial coefficient (assumes 0 ≤ r ≤ n integers). Interleaved
/// product `∏_{i=1}^{r} (n-r+i)/i` so every partial product stays ≤ the final value
/// — a representable answer (e.g. comb(1000,500)≈2.7e299) never overflows mid-way,
/// unlike computing the full descending numerator first (BUG-comboverflow). Uses
/// r=min(r,n-r) by symmetry C(n,r)=C(n,n-r): fewest iterations AND the tightest
/// partial products (also keeps the ≤170-step overflow-bounded loop guarantee).
/// Returns ±inf on genuine overflow so the caller collapses it to missing.
pub fn comb2(n: f64, r_in: f64) f64 {
    const r = @min(r_in, n - r_in);
    var result: f64 = 1;
    var i: f64 = 1;
    while (i <= r) : (i += 1) {
        result *= (n - r + i) / i;
        if (!std.math.isFinite(result)) return result;
    }
    return @round(result); // comb is integral; discard accumulated fp drift
}

/// The digamma function ψ(x): raise the argument with ψ(x)=ψ(x+1)−1/x until it's
/// large enough for the asymptotic series. ponytail: accurate for x>0; no negative
/// reflection (integer poles are rejected by the caller).
fn digammaOf(x_in: f64) f64 {
    var x = x_in;
    var result: f64 = 0;
    while (x < 10) : (x += 1) result -= 1.0 / x;
    const inv2 = 1.0 / (x * x);
    result += @log(x) - 0.5 / x - inv2 * (1.0 / 12.0 - inv2 * (1.0 / 120.0 - inv2 * (1.0 / 252.0)));
    return result;
}

// Lanczos approximation (g = 7), accurate to ~1e-13 for x > 0.
const lanczos_g = 7.0;
const lanczos_c = [_]f64{
    0.99999999999980993,   676.5203681218851,     -1259.1392167224028,
    771.32342877765313,    -176.61502916214059,   12.507343278686905,
    -0.13857109526572012,  9.9843695780195716e-6, 1.5056327351493116e-7,
};

/// ln Γ(x) for x > 0 (Lanczos).
pub fn lgammaOf(x: f64) f64 {
    const xx = x - 1.0;
    var a = lanczos_c[0];
    const tt = xx + lanczos_g + 0.5;
    inline for (1..lanczos_c.len) |i| a += lanczos_c[i] / (xx + @as(f64, @floatFromInt(i)));
    return 0.5 * @log(2.0 * std.math.pi) + (xx + 0.5) * @log(tt) - tt + @log(a);
}

/// Γ(x): exp(lgamma) for x ≥ 0.5; reflection Γ(x)=π/(sin(πx)·Γ(1−x)) below that.
fn gammaOf(x: f64) f64 {
    if (x < 0.5) return std.math.pi / (@sin(std.math.pi * x) * gammaOf(1.0 - x));
    return @exp(lgammaOf(x));
}

pub fn gcdU64(a: u64, b: u64) u64 {
    var x = a;
    var y = b;
    while (y != 0) {
        const tmp = y;
        y = x % y;
        x = tmp;
    }
    return x;
}

/// Levenshtein edit distance between two byte strings (single-row DP).
pub fn levenshtein(ev: *eval.Evaluator, a: []const u8, b: []const u8) !usize {
    if (a.len == 0) return b.len;
    if (b.len == 0) return a.len;
    const row = try ev.arena.alloc(usize, b.len + 1);
    for (row, 0..) |*c, j| c.* = j;
    for (a, 1..) |ca, i| {
        var prev = row[0]; // row[0] before overwrite = dp[i-1][0]
        row[0] = i;
        for (b, 1..) |cb, j| {
            const cur = row[j];
            const cost: usize = if (ca == cb) 0 else 1;
            row[j] = @min(@min(row[j] + 1, row[j - 1] + 1), prev + cost);
            prev = cur;
        }
    }
    return row[b.len];
}

fn dpRelax(dp: []u64, k: usize, v: u64) void {
    if (v < dp[k]) dp[k] = v;
}

fn eqCase(a: u8, b: u8, icase: bool) bool {
    return if (icase) std.ascii.toLower(a) == std.ascii.toLower(b) else a == b;
}

/// Byte that COMPGED charges its PUNCTUATION cost for: printable, non-alphanumeric,
/// non-space.
fn isPunctByte(c: u8) bool {
    return std.ascii.isPrint(c) and !std.ascii.isAlphanumeric(c) and c != ' ';
}

/// SPEDIS spelling cost: the minimum weighted cost of converting `keyword`
/// (source) into `query` (target) by SAS's asymmetric operations. Costs (SPEDIS
/// doc): match 0, singlet 25, append 35, doublet/swap/truncate/delete 50,
/// insert/replace/firstdel 100, firstins/firstrep 200. The caller divides by the
/// query length. Full 2D DP; predecessors are (i-1,·), (·,j-1), (i-2,j-2), all
/// filled earlier in row-major order.
pub fn spedisCost(ev: *eval.Evaluator, keyword: []const u8, query: []const u8) !u64 {
    const K = keyword;
    const Q = query;
    const m = K.len;
    const n = Q.len;
    const inf = std.math.maxInt(u64);
    const w = n + 1;
    const dp = try ev.arena.alloc(u64, (m + 1) * w);
    @memset(dp, inf);
    dp[0] = 0;
    var i: usize = 0;
    while (i <= m) : (i += 1) {
        var j: usize = 0;
        while (j <= n) : (j += 1) {
            const cur = dp[i * w + j];
            if (cur == inf) continue;
            // match (0) / replace (firstrep 200 at the very start, else 100)
            if (i < m and j < n) {
                const add: u64 = if (K[i] == Q[j]) 0 else if (i == 0 and j == 0) 200 else 100;
                dpRelax(dp, (i + 1) * w + (j + 1), cur + add);
            }
            // delete a keyword letter: firstdel 100 / singlet 25 (a doubled letter) / delete|truncate 50
            if (i < m) {
                var dc: u64 = if (i == 0) 100 else 50;
                if (i != 0 and ((i + 1 < m and K[i] == K[i + 1]) or K[i] == K[i - 1])) dc = 25;
                dpRelax(dp, (i + 1) * w + j, cur + dc);
            }
            // insert a query letter: firstins 200 / append 35 (past keyword end) / doublet 50 / insert 100
            if (j < n) {
                var ic: u64 = if (j == 0) 200 else if (i == m) 35 else 100;
                if (j != 0 and i != m and Q[j] == Q[j - 1]) ic = @min(ic, 50);
                dpRelax(dp, i * w + (j + 1), cur + ic);
            }
            // swap two consecutive letters
            if (i + 1 < m and j + 1 < n and K[i] == Q[j + 1] and K[i + 1] == Q[j])
                dpRelax(dp, (i + 2) * w + (j + 2), cur + 50);
        }
    }
    return dp[m * w + n];
}

/// COMPGED generalized edit distance: minimum-cost sequence that constructs
/// `out` (string-1) from `inp` (string-2), a pointer walking `inp`, using SAS's
/// default costs (match 0, single/double/swap 20, blank/truncate 10, punct 30,
/// append 50, insert/delete/replace 100, first* 200). 2D DP over (pointer, output).
pub fn compgedCost(ev: *eval.Evaluator, out: []const u8, inp: []const u8, icase: bool) !u64 {
    const S1 = out; // output / target
    const S2 = inp; // input / source (the pointer walks this)
    const n = S1.len;
    const m = S2.len;
    const inf = std.math.maxInt(u64);
    const w = n + 1;
    const dp = try ev.arena.alloc(u64, (m + 1) * w);
    @memset(dp, inf);
    dp[0] = 0;
    var p: usize = 0;
    while (p <= m) : (p += 1) {
        var o: usize = 0;
        while (o <= n) : (o += 1) {
            const cur = dp[p * w + o];
            if (cur == inf) continue;
            // match / replace (advance both); punctuation & blank give cheaper replacements
            if (p < m and o < n) {
                if (eqCase(S2[p], S1[o], icase)) {
                    dpRelax(dp, (p + 1) * w + (o + 1), cur);
                } else {
                    var rc: u64 = if (p == 0 and o == 0) 200 else 100; // freplace / replace
                    if (isPunctByte(S2[p]) and isPunctByte(S1[o])) rc = @min(rc, 30);
                    if (S2[p] == ' ' or S1[o] == ' ') rc = @min(rc, 10);
                    dpRelax(dp, (p + 1) * w + (o + 1), cur + rc);
                }
            }
            // delete (advance pointer): fdelete 200 / single 20 / truncate 10 / blank 10 / punct 30 / delete 100
            if (p < m) {
                var dc: u64 = if (o == 0) 200 else 100;
                if (p + 1 < m and S2[p] == S2[p + 1]) dc = @min(dc, 20);
                if (o == n) dc = @min(dc, 10);
                if (S2[p] == ' ') dc = @min(dc, 10);
                if (isPunctByte(S2[p])) dc = @min(dc, 30);
                dpRelax(dp, (p + 1) * w + o, cur + dc);
            }
            // insert (advance output): finsert 200 / append 50 / double 20 / blank 10 / punct 30 / insert 100
            if (o < n) {
                var ins: u64 = if (p == 0) 200 else 100;
                if (p == m) ins = @min(ins, 50);
                if (p < m and eqCase(S1[o], S2[p], icase)) ins = @min(ins, 20);
                if (S1[o] == ' ') ins = @min(ins, 10);
                if (isPunctByte(S1[o])) ins = @min(ins, 30);
                dpRelax(dp, p * w + (o + 1), cur + ins);
            }
            // swap two consecutive letters
            if (p + 1 < m and o + 1 < n and eqCase(S2[p + 1], S1[o], icase) and eqCase(S2[p], S1[o + 1], icase))
                dpRelax(dp, (p + 2) * w + (o + 2), cur + 20);
        }
    }
    return dp[m * w + n];
}

/// Trigamma ψ′(x) = Σ 1/(x+k)²: recurrence up to x≥6, then the asymptotic series.
/// ponytail: accurate for x>0 (the distribution helpers never call it below).
fn trigammaOf(x_in: f64) f64 {
    var x = x_in;
    var r: f64 = 0;
    while (x < 6) : (x += 1) r += 1.0 / (x * x);
    const inv = 1.0 / x;
    const inv2 = inv * inv;
    // ψ′ ≈ 1/x + 1/2x² + 1/6x³ − 1/30x⁵ + 1/42x⁷ − 1/30x⁹
    return r + inv + 0.5 * inv2 + inv * inv2 * (1.0 / 6.0 - inv2 * (1.0 / 30.0 - inv2 * (1.0 / 42.0 - inv2 * (1.0 / 30.0))));
}

/// Regularized lower incomplete gamma P(a,x) = γ(a,x)/Γ(a), a>0, x≥0. NR §6.2.
pub fn gammaP(a: f64, x: f64) f64 {
    if (x <= 0) return 0;
    if (x < a + 1) { // series representation
        var ap = a;
        var del = 1.0 / a;
        var sum = del;
        var n: usize = 0;
        while (n < 300) : (n += 1) {
            ap += 1;
            del *= x / ap;
            sum += del;
            if (@abs(del) < @abs(sum) * 1e-15) break;
        }
        return sum * @exp(-x + a * @log(x) - lgammaOf(a));
    }
    return 1.0 - gammaQcf(a, x); // continued fraction for the upper tail
}

/// Regularized upper incomplete gamma Q(a,x) via the Lentz continued fraction.
fn gammaQcf(a: f64, x: f64) f64 {
    const tiny: f64 = 1e-30;
    var b = x + 1 - a;
    var c = 1.0 / tiny;
    var d = 1.0 / b;
    var h = d;
    var i: f64 = 1;
    while (i < 300) : (i += 1) {
        const an = -i * (i - a);
        b += 2;
        d = an * d + b;
        if (@abs(d) < tiny) d = tiny;
        c = b + an / c;
        if (@abs(c) < tiny) c = tiny;
        d = 1.0 / d;
        const del = d * c;
        h *= del;
        if (@abs(del - 1) < 1e-15) break;
    }
    return @exp(-x + a * @log(x) - lgammaOf(a)) * h;
}

/// Regularized incomplete beta I_x(a,b), 0≤x≤1, a>0, b>0. NR §6.4.
pub fn betaI(x: f64, a: f64, b: f64) f64 {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    const bt = @exp(lgammaOf(a + b) - lgammaOf(a) - lgammaOf(b) + a * @log(x) + b * @log(1 - x));
    if (x < (a + 1) / (a + b + 2))
        return bt * betaCf(a, b, x) / a;
    return 1.0 - bt * betaCf(b, a, 1 - x) / b;
}

fn betaCf(a: f64, b: f64, x: f64) f64 {
    const tiny: f64 = 1e-30;
    const qab = a + b;
    const qap = a + 1;
    const qam = a - 1;
    var c: f64 = 1;
    var d = 1 - qab * x / qap;
    if (@abs(d) < tiny) d = tiny;
    d = 1.0 / d;
    var h = d;
    var m: f64 = 1;
    while (m < 300) : (m += 1) {
        const m2 = 2 * m;
        var aa = m * (b - m) * x / ((qam + m2) * (a + m2));
        d = 1 + aa * d;
        if (@abs(d) < tiny) d = tiny;
        c = 1 + aa / c;
        if (@abs(c) < tiny) c = tiny;
        d = 1.0 / d;
        h *= d * c;
        aa = -(a + m) * (qab + m) * x / ((a + m2) * (qap + m2));
        d = 1 + aa * d;
        if (@abs(d) < tiny) d = tiny;
        c = 1 + aa / c;
        if (@abs(c) < tiny) c = tiny;
        d = 1.0 / d;
        const del = d * c;
        h *= del;
        if (@abs(del - 1) < 1e-14) break;
    }
    return h;
}

/// Student's t CDF at x with df degrees of freedom (central).
fn probTcdf(x: f64, df: f64) f64 {
    const ib = betaI(df / (df + x * x), df / 2.0, 0.5);
    return if (x >= 0) 1.0 - 0.5 * ib else 0.5 * ib;
}

/// Inverse standard-normal CDF via Acklam's rational approximation (|err|<1.2e-9).
fn probitOf(p: f64) f64 {
    const a = [_]f64{ -3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02, 1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00 };
    const b = [_]f64{ -5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02, 6.680131188771972e+01, -1.328068155288572e+01 };
    const c = [_]f64{ -7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00, -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00 };
    const d = [_]f64{ 7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00, 3.754408661907416e+00 };
    const plow = 0.02425;
    var x: f64 = undefined;
    if (p < plow) {
        const q = @sqrt(-2 * @log(p));
        x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    } else if (p > 1 - plow) {
        const q = @sqrt(-2 * @log(1 - p));
        x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5]) / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1);
    } else {
        const q = p - 0.5;
        const r = q * q;
        x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1);
    }
    // One Halley step against the high-precision forward CDF lifts Acklam's
    // ~1e-9 error to full double precision (SAS: probit(0.975)=1.959963984540054).
    // NOTE-probitdeeptail: PARKED, not a conformance gap. The reference (p.1332)
    // states NO accuracy guarantee — only Range 0<p<1 (domErr above) and a
    // CAUTION that the result could be truncated to [-8.222, 7.941]. Measured:
    // ≤7.8e-11 relative over p ∈ [0.001, 0.9999]; 1.54e-9 relative at p=1e-10,
    // where the Halley step is limited by the forward CDF's own tail precision.
    // Both doc example values (probit(.025), probit(1.e-7)) match to all 10
    // printed digits. Accuracy we do have is pinned in
    // tests/corpus/note_probit_deeptail.sas — tighten only with a doc target.
    const u = (stdNormCdf(x) - p) / stdNormPdf(x);
    const x1 = x - u / (1 + x * u / 2);
    return if (std.math.isFinite(x1)) x1 else x; // |x| huge: keep Acklam
}

fn stdNormPdf(z: f64) f64 {
    return @exp(-0.5 * z * z) / @sqrt(2.0 * std.math.pi);
}

/// Which forward CDF a quantile inverse should bisect.
const CdfKind = enum { gamma, chisq, beta, f, t };
fn cdfEval(kind: CdfKind, x: f64, p1: f64, p2: f64) f64 {
    return switch (kind) {
        .gamma => gammaP(p1, x), // p1 = shape a
        .chisq => gammaP(p1 / 2.0, x / 2.0), // p1 = df
        .beta => betaI(x, p1, p2),
        .f => betaI(p1 * x / (p1 * x + p2), p1 / 2.0, p2 / 2.0),
        .t => probTcdf(x, p1),
    };
}

/// Invert a monotone CDF by bisection: smallest x in [lo,hi] with cdf(x) ≥ p.
pub fn bisectCdf(kind: CdfKind, p: f64, p1: f64, p2: f64, lo0: f64, hi0: f64) f64 {
    var lo = lo0;
    var hi = hi0;
    var it: usize = 0;
    while (it < 200) : (it += 1) {
        const mid = 0.5 * (lo + hi);
        if (cdfEval(kind, mid, p1, p2) < p) lo = mid else hi = mid;
        if (hi - lo < 1e-12 * (1 + @abs(mid))) break;
    }
    return 0.5 * (lo + hi);
}

/// Noncentral chi-square CDF F(x; df, nc): a Poisson(nc/2)-weighted mixture of
/// central chi-squares with df+2j degrees of freedom. Log-space Poisson weights
/// keep it stable near the mode (j≈nc/2).
pub fn noncentralChisqCdf(x: f64, df: f64, nc: f64) f64 {
    if (x <= 0) return 0;
    if (nc <= 0) return gammaP(df / 2.0, x / 2.0);
    const half = nc / 2.0;
    var sum: f64 = 0;
    var cumw: f64 = 0;
    var j: usize = 0;
    while (j < 3000) : (j += 1) {
        const jf: f64 = @floatFromInt(j);
        const w = @exp(-half + jf * @log(half) - lgammaOf(jf + 1)); // Poisson pmf
        sum += w * gammaP(df / 2.0 + jf, x / 2.0);
        cumw += w;
        if (jf > half and (cumw > 0.9999999 or w < 1e-15)) break;
    }
    return sum;
}

/// Noncentral F CDF: Poisson(nc/2)-weighted mixture of incomplete-beta terms.
pub fn noncentralFCdf(x: f64, ndf: f64, ddf: f64, nc: f64) f64 {
    if (x <= 0) return 0;
    if (nc <= 0) return betaI(ndf * x / (ndf * x + ddf), ndf / 2.0, ddf / 2.0);
    const half = nc / 2.0;
    const y = ndf * x / (ndf * x + ddf);
    var sum: f64 = 0;
    var cumw: f64 = 0;
    var j: usize = 0;
    while (j < 3000) : (j += 1) {
        const jf: f64 = @floatFromInt(j);
        const w = @exp(-half + jf * @log(half) - lgammaOf(jf + 1));
        sum += w * betaI(y, ndf / 2.0 + jf, ddf / 2.0);
        cumw += w;
        if (jf > half and (cumw > 0.9999999 or w < 1e-15)) break;
    }
    return sum;
}

/// Noncentral Student's t CDF (Algorithm AS 243). Reduces to the central t CDF
/// at δ=0. Handles x<0 by the reflection P(T≤x;δ)=1−P(T≤−x;−δ).
pub fn noncentralTCdf(x: f64, df: f64, delta: f64) f64 {
    if (delta == 0) return probTcdf(x, df); // AS243 series is 0·log0 at δ=0
    if (x < 0) return 1.0 - noncentralTCdf(-x, df, -delta);
    const y = x * x / (x * x + df);
    const d2 = delta * delta / 2.0;
    var sum: f64 = 0;
    var j: usize = 0;
    while (j < 2000) : (j += 1) {
        const jf: f64 = @floatFromInt(j);
        const p = @exp(-d2 + jf * @log(d2) - lgammaOf(jf + 1)); // e^{-δ²/2}(δ²/2)^j/j!
        const q = delta / @sqrt(2.0) * @exp(-d2 + jf * @log(d2) - lgammaOf(jf + 1.5));
        sum += p * betaI(y, jf + 0.5, df / 2.0) + q * betaI(y, jf + 1.0, df / 2.0);
        if (jf > d2 and p < 1e-15) break;
    }
    return stdNormCdf(-delta) + 0.5 * sum;
}

/// Solve for the noncentrality parameter: the CDF decreases as nc rises, so if
/// `prob` ≥ the central (nc=0) probability the answer is 0; otherwise bisect.
/// Returns null (→ missing) if no nc in [0, 2000] reaches `prob`.
const NoncKind = enum { chisq, f, t };
fn noncentralCdf(kind: NoncKind, x: f64, p1: f64, p2: f64, nc: f64) f64 {
    return switch (kind) {
        .chisq => noncentralChisqCdf(x, p1, nc),
        .f => noncentralFCdf(x, p1, p2, nc),
        .t => noncentralTCdf(x, p1, nc),
    };
}
pub fn solveNoncentrality(kind: NoncKind, x: f64, p1: f64, p2: f64, prob: f64) ?f64 {
    const central = noncentralCdf(kind, x, p1, p2, 0);
    if (prob >= central) return 0; // can't exceed the central probability with nc≥0
    var lo: f64 = 0;
    var hi: f64 = 2000;
    if (noncentralCdf(kind, x, p1, p2, hi) > prob) return null; // unreachable in range
    var it: usize = 0;
    while (it < 200) : (it += 1) {
        const mid = 0.5 * (lo + hi);
        if (noncentralCdf(kind, x, p1, p2, mid) > prob) lo = mid else hi = mid;
        if (hi - lo < 1e-10 * (1 + mid)) break;
    }
    return 0.5 * (lo + hi);
}

/// CDF of the sample median of `n` iid standard-normal variables at `x` (PROBMED).
/// Odd n: the closed form I_Φ(x)((n+1)/2,(n+1)/2). Even n: the middle-pair integral
/// (Simpson over (−∞,x], φ concentrated within ±8 so x−40 is a safe lower bound).
pub fn probMed(n: i64, x: f64) f64 {
    const half_i = @divTrunc(n, 2);
    if (@mod(n, 2) == 1) { // odd
        const a: f64 = @floatFromInt(@divTrunc(n + 1, 2));
        return betaI(stdNormCdf(x), a, a);
    }
    const nf: f64 = @floatFromInt(n);
    const h: f64 = @floatFromInt(half_i); // n/2
    const coeff = 2.0 * @exp(lgammaOf(nf) - 2.0 * lgammaOf(h)); // 2/B(n/2,n/2)
    const g = struct {
        fn f(u: f64, xx: f64, hh: f64) f64 {
            const phi = @exp(-0.5 * u * u) / @sqrt(2.0 * std.math.pi);
            const pu = stdNormCdf(u);
            const term = std.math.pow(f64, 1 - pu, hh) - std.math.pow(f64, 1 - stdNormCdf(2 * xx - u), hh);
            return term * std.math.pow(f64, pu, hh - 1) * phi;
        }
    }.f;
    const lo = x - 40.0;
    const steps: usize = 1000;
    const hstep = (x - lo) / @as(f64, @floatFromInt(steps));
    var sum = g(lo, x, h) + g(x, x, h);
    var i: usize = 1;
    while (i < steps) : (i += 1) {
        const u = lo + hstep * @as(f64, @floatFromInt(i));
        sum += g(u, x, h) * (if (i % 2 == 1) @as(f64, 4) else 2);
    }
    return coeff * (hstep / 3.0) * sum;
}

/// The distributions the CDF/PDF/QUANTILE/SDF family understands. ponytail: a
/// solid continuous+discrete core, not SAS's full ~25-distribution list; an
/// unrecognized name → missing (never a wrong number).
const Dist = enum { normal, lognormal, t, f, chisq, gamma, expo, beta, uniform, cauchy, logistic, poisson, binomial, bernoulli };

/// `s` is a case-insensitive prefix (≥4 chars) of the canonical distribution name.
pub fn distIs(s: []const u8, canon: []const u8) bool {
    if (s.len < 4 or s.len > canon.len) return false;
    return std.ascii.eqlIgnoreCase(s, canon[0..s.len]);
}

pub fn parseDist(s_in: []const u8) ?Dist {
    const s = std.mem.trim(u8, s_in, " ");
    if (std.ascii.eqlIgnoreCase(s, "t")) return .t;
    if (std.ascii.eqlIgnoreCase(s, "f")) return .f;
    if (distIs(s, "NORMAL") or distIs(s, "GAUSSIAN")) return .normal;
    if (distIs(s, "LOGNORMAL")) return .lognormal;
    if (distIs(s, "CHISQUARE") or distIs(s, "CHISQ")) return .chisq;
    if (distIs(s, "GAMMA")) return .gamma;
    if (distIs(s, "EXPONENTIAL")) return .expo;
    if (distIs(s, "BETA")) return .beta;
    if (distIs(s, "UNIFORM")) return .uniform;
    if (distIs(s, "CAUCHY")) return .cauchy;
    if (distIs(s, "LOGISTIC")) return .logistic;
    if (distIs(s, "POISSON")) return .poisson;
    if (distIs(s, "BINOMIAL")) return .binomial;
    if (distIs(s, "BERNOULLI")) return .bernoulli; // "BERN" prefix covered by distIs
    return null;
}

/// Standard-normal CDF Φ(z) via the (high-precision) regularized incomplete gamma.
fn stdNormCdf(z: f64) f64 {
    const e = gammaP(0.5, z * z / 2.0); // = erf(|z|/√2)
    return 0.5 * (1.0 + (if (z >= 0) e else -e));
}

/// Distribution parameter `i` (0-based, after dist+quantile) or a default.
fn distParam(args: []const Value, i: usize, default: f64) f64 {
    return if (args.len > 2 + i) toNum(args[2 + i]) else default;
}

/// CDF of `d` at `x` with the parameters in `args[2..]`. null = out of support/unsupported.
pub fn distCdf(d: Dist, x: f64, args: []const Value) ?f64 {
    return switch (d) {
        .normal => stdNormCdf((x - distParam(args, 0, 0)) / distParam(args, 1, 1)),
        .lognormal => if (x <= 0) 0 else stdNormCdf((@log(x) - distParam(args, 0, 0)) / distParam(args, 1, 1)),
        .t => probTcdf(x, distParam(args, 0, 1)),
        .f => blk: {
            if (x <= 0) break :blk 0;
            const ndf = distParam(args, 0, 1);
            const ddf = distParam(args, 1, 1);
            break :blk betaI(ndf * x / (ndf * x + ddf), ndf / 2.0, ddf / 2.0);
        },
        .chisq => gammaP(distParam(args, 0, 1) / 2.0, x / 2.0),
        .gamma => gammaP(distParam(args, 0, 1), x / distParam(args, 1, 1)),
        .expo => if (x <= 0) 0 else 1.0 - @exp(-x / distParam(args, 0, 1)),
        .beta => betaI(x, distParam(args, 0, 1), distParam(args, 1, 1)),
        .uniform => blk: {
            const l = distParam(args, 0, 0);
            const r = distParam(args, 1, 1);
            break :blk if (x <= l) 0 else if (x >= r) 1 else (x - l) / (r - l);
        },
        .cauchy => 0.5 + std.math.atan((x - distParam(args, 0, 0)) / distParam(args, 1, 1)) / std.math.pi,
        .logistic => 1.0 / (1.0 + @exp(-(x - distParam(args, 0, 0)) / distParam(args, 1, 1))),
        .poisson => if (x < 0) 0 else 1.0 - gammaP(@floor(x) + 1.0, distParam(args, 0, 1)),
        .binomial => blk: {
            const p = distParam(args, 0, 0.5);
            const n = distParam(args, 1, 1);
            const k = @floor(x);
            if (k < 0) break :blk 0;
            if (k >= n) break :blk 1;
            break :blk betaI(1.0 - p, n - k, k + 1.0);
        },
        .bernoulli => blk: {
            const p = distParam(args, 0, 0.5);
            if (p < 0 or p > 1) break :blk null;
            break :blk if (x < 0) 0 else if (x < 1) 1 - p else 1;
        },
    };
}

/// PDF/PMF of `d` at `x`. null = unsupported.
pub fn distPdf(d: Dist, x: f64, args: []const Value) ?f64 {
    const norm = struct {
        fn phi(z: f64) f64 {
            return @exp(-0.5 * z * z) / @sqrt(2.0 * std.math.pi);
        }
    }.phi;
    return switch (d) {
        .normal => blk: {
            const s = distParam(args, 1, 1);
            break :blk norm((x - distParam(args, 0, 0)) / s) / s;
        },
        .lognormal => blk: {
            if (x <= 0) break :blk 0;
            const s = distParam(args, 1, 1);
            break :blk norm((@log(x) - distParam(args, 0, 0)) / s) / (x * s);
        },
        .t => blk: {
            const df = distParam(args, 0, 1);
            const c = @exp(lgammaOf((df + 1) / 2.0) - lgammaOf(df / 2.0)) / @sqrt(df * std.math.pi);
            break :blk c * std.math.pow(f64, 1.0 + x * x / df, -(df + 1) / 2.0);
        },
        .f => blk: {
            if (x <= 0) break :blk 0;
            const m = distParam(args, 0, 1);
            const n = distParam(args, 1, 1);
            const lg = lgammaOf((m + n) / 2.0) - lgammaOf(m / 2.0) - lgammaOf(n / 2.0);
            break :blk @exp(lg + (m / 2.0) * @log(m / n) + (m / 2.0 - 1) * @log(x) - ((m + n) / 2.0) * @log(1 + m * x / n));
        },
        .chisq => blk: {
            const k = distParam(args, 0, 1);
            if (x <= 0) break :blk 0;
            break :blk @exp((k / 2.0 - 1) * @log(x) - x / 2.0 - (k / 2.0) * @log(2.0) - lgammaOf(k / 2.0));
        },
        .gamma => blk: {
            const a = distParam(args, 0, 1);
            const lam = distParam(args, 1, 1);
            if (x <= 0) break :blk 0;
            break :blk @exp((a - 1) * @log(x) - x / lam - a * @log(lam) - lgammaOf(a));
        },
        .expo => blk: {
            const lam = distParam(args, 0, 1);
            break :blk if (x < 0) 0 else @exp(-x / lam) / lam;
        },
        .beta => blk: {
            const a = distParam(args, 0, 1);
            const b = distParam(args, 1, 1);
            if (x <= 0 or x >= 1) break :blk 0;
            break :blk @exp((a - 1) * @log(x) + (b - 1) * @log(1 - x) - (lgammaOf(a) + lgammaOf(b) - lgammaOf(a + b)));
        },
        .uniform => blk: {
            const l = distParam(args, 0, 0);
            const r = distParam(args, 1, 1);
            break :blk if (x < l or x > r) 0 else 1.0 / (r - l);
        },
        .cauchy => blk: {
            const s = distParam(args, 1, 1);
            const z = (x - distParam(args, 0, 0)) / s;
            break :blk 1.0 / (std.math.pi * s * (1 + z * z));
        },
        .logistic => blk: {
            const s = distParam(args, 1, 1);
            const ez = @exp(-(x - distParam(args, 0, 0)) / s);
            break :blk ez / (s * (1 + ez) * (1 + ez));
        },
        .poisson => blk: {
            const m = distParam(args, 0, 1);
            const k = @round(x);
            if (k < 0 or k != x) break :blk 0;
            break :blk @exp(-m + k * @log(m) - lgammaOf(k + 1));
        },
        .binomial => blk: {
            const p = distParam(args, 0, 0.5);
            const n = distParam(args, 1, 1);
            const k = @round(x);
            if (k < 0 or k > n or k != x) break :blk 0;
            break :blk @exp(lgammaOf(n + 1) - lgammaOf(k + 1) - lgammaOf(n - k + 1) + k * @log(p) + (n - k) * @log(1 - p));
        },
        .bernoulli => blk: {
            const p = distParam(args, 0, 0.5);
            if (p < 0 or p > 1) break :blk null;
            break :blk if (x == 1) p else if (x == 0) 1 - p else 0;
        },
    };
}

/// log Q(z) = log(1−Φ(z)) for z deep in the upper tail, via the Mills-ratio
/// continued fraction Q(z) = φ(z)·r(z), r(z) = 1/(z + 1/(z + 2/(z + 3/(z+⋯)))).
/// BUG-logxdftail (doc LOGCDF p.1169: the log family exists for tail accuracy):
/// the direct CDF underflows f64 at |z|≳38 (and our gammaP Φ collapses to 0/1
/// near |z|≈8 — OBS-probnormtail), so callers reach here only with |z| large;
/// the CF converges fast there. Modified Lentz (Numerical Recipes §5.2).
pub fn logStdNormTail(z: f64) f64 {
    const tiny = 1e-300;
    var f = z; // evaluates B = z + 1/(z + 2/(z + 3/(z+⋯))); r = 1/B
    var c = z;
    var dd: f64 = 0;
    var j: f64 = 1;
    while (j < 10000) : (j += 1) {
        dd = z + j * dd;
        if (dd == 0) dd = tiny;
        dd = 1 / dd;
        c = z + j / c;
        if (c == 0) c = tiny;
        const delta = c * dd;
        f *= delta;
        if (@abs(delta - 1) < 1e-16) break;
    }
    return -0.5 * z * z - 0.5 * @log(2.0 * std.math.pi) - @log(f);
}

/// log of the PDF/PMF of `d` at `x`, computed in log-space — same formulas as
/// distPdf but returning the @exp argument. −inf outside the support (→ missing,
/// exactly like log(pdf=0) today). BUG-logxdftail fallback: called only when the
/// direct density underflowed to 0 (or overflowed/NaN'd at a pole), so mid-range
/// LOGPDF stays byte-identical to @log(pdf).
pub fn distLogPdf(d: Dist, x: f64, args: []const Value) f64 {
    const ninf = -std.math.inf(f64);
    const logphi = struct { // log of the standard-normal density
        fn f(z: f64) f64 {
            return -0.5 * z * z - 0.5 * @log(2.0 * std.math.pi);
        }
    }.f;
    return switch (d) {
        .normal => blk: {
            const s = distParam(args, 1, 1);
            break :blk logphi((x - distParam(args, 0, 0)) / s) - @log(s);
        },
        .lognormal => blk: {
            if (x <= 0) break :blk ninf;
            const s = distParam(args, 1, 1);
            break :blk logphi((@log(x) - distParam(args, 0, 0)) / s) - @log(x) - @log(s);
        },
        .t => blk: {
            const df = distParam(args, 0, 1);
            // log(1+x²/df); the 2ln|x|−ln(df) form when x² would overflow f64
            const l = if (@abs(x) > 1e150) 2 * @log(@abs(x)) - @log(df) else @log(1 + x * x / df);
            break :blk lgammaOf((df + 1) / 2.0) - lgammaOf(df / 2.0) - 0.5 * @log(df * std.math.pi) - ((df + 1) / 2.0) * l;
        },
        .f => blk: {
            if (x <= 0) break :blk ninf;
            const m = distParam(args, 0, 1);
            const n = distParam(args, 1, 1);
            const lg = lgammaOf((m + n) / 2.0) - lgammaOf(m / 2.0) - lgammaOf(n / 2.0);
            break :blk lg + (m / 2.0) * @log(m / n) + (m / 2.0 - 1) * @log(x) - ((m + n) / 2.0) * @log(1 + m * x / n);
        },
        .chisq => blk: {
            const k = distParam(args, 0, 1);
            if (x <= 0) break :blk ninf;
            break :blk (k / 2.0 - 1) * @log(x) - x / 2.0 - (k / 2.0) * @log(2.0) - lgammaOf(k / 2.0);
        },
        .gamma => blk: {
            const a = distParam(args, 0, 1);
            const lam = distParam(args, 1, 1);
            if (x <= 0) break :blk ninf;
            break :blk (a - 1) * @log(x) - x / lam - a * @log(lam) - lgammaOf(a);
        },
        .expo => blk: {
            const lam = distParam(args, 0, 1);
            break :blk if (x < 0) ninf else -x / lam - @log(lam);
        },
        .beta => blk: {
            const a = distParam(args, 0, 1);
            const b = distParam(args, 1, 1);
            if (x <= 0 or x >= 1) break :blk ninf;
            break :blk (a - 1) * @log(x) + (b - 1) * @log(1 - x) - (lgammaOf(a) + lgammaOf(b) - lgammaOf(a + b));
        },
        .uniform => blk: {
            const l = distParam(args, 0, 0);
            const r = distParam(args, 1, 1);
            break :blk if (x < l or x > r) ninf else -@log(r - l);
        },
        .cauchy => blk: {
            const s = distParam(args, 1, 1);
            const z = (x - distParam(args, 0, 0)) / s;
            const lz = if (@abs(z) > 1e150) 2 * @log(@abs(z)) else @log(1 + z * z);
            break :blk -@log(std.math.pi) - @log(s) - lz;
        },
        .logistic => blk: { // −|z|-form, stable where e^{±z} would overflow
            const s = distParam(args, 1, 1);
            const z = (x - distParam(args, 0, 0)) / s;
            const az = @abs(z);
            break :blk -az - @log(s) - 2 * @log(1 + @exp(-az));
        },
        .poisson => blk: {
            const m = distParam(args, 0, 1);
            const k = @round(x);
            if (k < 0 or k != x) break :blk ninf;
            break :blk -m + k * @log(m) - lgammaOf(k + 1);
        },
        .binomial => blk: {
            const p = distParam(args, 0, 0.5);
            const n = distParam(args, 1, 1);
            const k = @round(x);
            if (k < 0 or k > n or k != x) break :blk ninf;
            break :blk lgammaOf(n + 1) - lgammaOf(k + 1) - lgammaOf(n - k + 1) + k * @log(p) + (n - k) * @log(1 - p);
        },
        .bernoulli => blk: {
            const p = distParam(args, 0, 0.5);
            break :blk if (x == 1) @log(p) else if (x == 0) @log(1 - p) else ninf;
        },
    };
}

/// log of the CDF (right=false) or SDF (right=true) of `d` at `x`, in log-space.
/// BUG-logxdftail fallback: called only when the direct tail probability
/// underflowed to exactly 0, so the tail is always deep. null = no log-space
/// form → missing, unchanged from today (ponytail: deep CDF tails for
/// chisq/gamma/t/f/beta/cauchy and the discrete dists need a log-space
/// incomplete-gamma/beta — add when a study actually hits them). −inf = outside
/// the support (→ missing, same as log(0) today).
pub fn distLogCdfSdf(d: Dist, x: f64, args: []const Value, right: bool) ?f64 {
    const ninf = -std.math.inf(f64);
    switch (d) {
        .normal, .lognormal => {
            const z = if (d == .normal)
                (x - distParam(args, 0, 0)) / distParam(args, 1, 1)
            else if (x > 0)
                (@log(x) - distParam(args, 0, 0)) / distParam(args, 1, 1)
            else
                return ninf; // left of the lognormal support
            // underflow ⇒ left tail has z very negative, right tail z very positive
            return if (right) logStdNormTail(z) else logStdNormTail(-z);
        },
        .expo => {
            const lam = distParam(args, 0, 1);
            if (x <= 0) return ninf; // sdf(0)=1 never underflows; cdf(0)=0 → −inf
            // trigger ⇒ right: e^{−x/λ} underflowed; left: 1−e^{−x/λ} rounded to 0
            // (x/λ ≲ 1e-16, where log(1−e^{−t}) = log t to 5e-17)
            return if (right) -x / lam else @log(x / lam);
        },
        .logistic => {
            const z = (x - distParam(args, 0, 0)) / distParam(args, 1, 1);
            // trigger ⇒ |z| ≳ 710: logcdf = z − e^z ≈ z, logsdf = −z − e^{−z} ≈ −z
            return if (right) -z else z;
        },
        else => return null,
    }
}

/// Quantile (inverse CDF) of `d` at probability `p`∈(0,1). null = degenerate parms.
pub fn distQuantile(d: Dist, p: f64, args: []const Value) ?f64 {
    return switch (d) {
        .normal => distParam(args, 0, 0) + distParam(args, 1, 1) * probitOf(p),
        .lognormal => @exp(distParam(args, 0, 0) + distParam(args, 1, 1) * probitOf(p)),
        .t => bisectCdf(.t, p, distParam(args, 0, 1), 0, -1e6, 1e6),
        .f => bisectCdf(.f, p, distParam(args, 0, 1), distParam(args, 1, 1), 0, 1e7),
        .chisq => bisectCdf(.chisq, p, distParam(args, 0, 1), 0, 0, 1e7),
        .gamma => distParam(args, 1, 1) * bisectCdf(.gamma, p, distParam(args, 0, 1), 0, 0, 1e7),
        .expo => -distParam(args, 0, 1) * @log(1 - p),
        .beta => bisectCdf(.beta, p, distParam(args, 0, 1), distParam(args, 1, 1), 0, 1),
        .uniform => distParam(args, 0, 0) + p * (distParam(args, 1, 1) - distParam(args, 0, 0)),
        .cauchy => distParam(args, 0, 0) + distParam(args, 1, 1) * @tan(std.math.pi * (p - 0.5)),
        .logistic => distParam(args, 0, 0) + distParam(args, 1, 1) * @log(p / (1 - p)),
        // discrete: smallest k with F(k) ≥ p, integer bisect on the CDF
        // (mirrors statfns.zig extQuantile negbinomial/hypergeometric).
        // 1e-12 slack: CDF values land a few ulps off exact ties (gammaP/betaI).
        .poisson => blk: {
            const m = distParam(args, 0, 1);
            if (m <= 0) break :blk null; // degenerate parm → missing
            if ((distCdf(.poisson, 0, args) orelse return null) >= p - 1e-12) break :blk 0;
            var lo: f64 = 0; // invariant: F(lo) < p
            var hi: f64 = @max(1, 4.0 * m); // mean-based first guess
            while ((distCdf(.poisson, hi, args) orelse return null) < p - 1e-12) {
                lo = hi;
                hi *= 2;
                if (hi > 1e12) break :blk null; // degenerate parms
            }
            while (hi - lo > 1) {
                const mid = @floor((lo + hi) / 2.0);
                if ((distCdf(.poisson, mid, args) orelse return null) >= p - 1e-12) hi = mid else lo = mid;
            }
            break :blk hi;
        },
        .binomial => blk: { // support [0,n], so plain bisect, no expansion
            const pr = distParam(args, 0, 0.5);
            const n = distParam(args, 1, 1);
            if (pr < 0 or pr > 1 or n < 1) break :blk null;
            if ((distCdf(.binomial, 0, args) orelse return null) >= p - 1e-12) break :blk 0;
            var lo: f64 = 0; // invariant: F(lo) < p (F(n)=1 ≥ p always)
            var hi: f64 = @floor(n);
            while (hi - lo > 1) {
                const mid = @floor((lo + hi) / 2.0);
                if ((distCdf(.binomial, mid, args) orelse return null) >= p - 1e-12) hi = mid else lo = mid;
            }
            break :blk hi;
        },
        .bernoulli => blk: {
            const pr = distParam(args, 0, 0.5);
            if (pr < 0 or pr > 1) break :blk null;
            break :blk if (p <= 1 - pr) 0 else 1;
        },
    };
}

/// US states + DC: postal code, FIPS number, mixed-case name. Uppercase names
/// (STNAME/FIPNAME) are derived from `name`. FIPS numbering has documented gaps
/// (3, 7, 14, 43, 52 …) — the table is the source of truth, not the index.
const StateRow = struct { po: []const u8, fips: u8, name: []const u8 };
const states = [_]StateRow{
    .{ .po = "AL", .fips = 1, .name = "Alabama" },        .{ .po = "AK", .fips = 2, .name = "Alaska" },
    .{ .po = "AZ", .fips = 4, .name = "Arizona" },        .{ .po = "AR", .fips = 5, .name = "Arkansas" },
    .{ .po = "CA", .fips = 6, .name = "California" },     .{ .po = "CO", .fips = 8, .name = "Colorado" },
    .{ .po = "CT", .fips = 9, .name = "Connecticut" },    .{ .po = "DE", .fips = 10, .name = "Delaware" },
    .{ .po = "DC", .fips = 11, .name = "District of Columbia" }, .{ .po = "FL", .fips = 12, .name = "Florida" },
    .{ .po = "GA", .fips = 13, .name = "Georgia" },       .{ .po = "HI", .fips = 15, .name = "Hawaii" },
    .{ .po = "ID", .fips = 16, .name = "Idaho" },         .{ .po = "IL", .fips = 17, .name = "Illinois" },
    .{ .po = "IN", .fips = 18, .name = "Indiana" },       .{ .po = "IA", .fips = 19, .name = "Iowa" },
    .{ .po = "KS", .fips = 20, .name = "Kansas" },        .{ .po = "KY", .fips = 21, .name = "Kentucky" },
    .{ .po = "LA", .fips = 22, .name = "Louisiana" },     .{ .po = "ME", .fips = 23, .name = "Maine" },
    .{ .po = "MD", .fips = 24, .name = "Maryland" },      .{ .po = "MA", .fips = 25, .name = "Massachusetts" },
    .{ .po = "MI", .fips = 26, .name = "Michigan" },      .{ .po = "MN", .fips = 27, .name = "Minnesota" },
    .{ .po = "MS", .fips = 28, .name = "Mississippi" },   .{ .po = "MO", .fips = 29, .name = "Missouri" },
    .{ .po = "MT", .fips = 30, .name = "Montana" },       .{ .po = "NE", .fips = 31, .name = "Nebraska" },
    .{ .po = "NV", .fips = 32, .name = "Nevada" },        .{ .po = "NH", .fips = 33, .name = "New Hampshire" },
    .{ .po = "NJ", .fips = 34, .name = "New Jersey" },    .{ .po = "NM", .fips = 35, .name = "New Mexico" },
    .{ .po = "NY", .fips = 36, .name = "New York" },      .{ .po = "NC", .fips = 37, .name = "North Carolina" },
    .{ .po = "ND", .fips = 38, .name = "North Dakota" },  .{ .po = "OH", .fips = 39, .name = "Ohio" },
    .{ .po = "OK", .fips = 40, .name = "Oklahoma" },      .{ .po = "OR", .fips = 41, .name = "Oregon" },
    .{ .po = "PA", .fips = 42, .name = "Pennsylvania" },  .{ .po = "RI", .fips = 44, .name = "Rhode Island" },
    .{ .po = "SC", .fips = 45, .name = "South Carolina" },.{ .po = "SD", .fips = 46, .name = "South Dakota" },
    .{ .po = "TN", .fips = 47, .name = "Tennessee" },     .{ .po = "TX", .fips = 48, .name = "Texas" },
    .{ .po = "UT", .fips = 49, .name = "Utah" },          .{ .po = "VT", .fips = 50, .name = "Vermont" },
    .{ .po = "VA", .fips = 51, .name = "Virginia" },      .{ .po = "WA", .fips = 53, .name = "Washington" },
    .{ .po = "WV", .fips = 54, .name = "West Virginia" }, .{ .po = "WI", .fips = 55, .name = "Wisconsin" },
    .{ .po = "WY", .fips = 56, .name = "Wyoming" },
};

pub fn stateByPostal(po: []const u8) ?StateRow {
    const p = std.mem.trim(u8, po, " ");
    for (states) |s| if (std.ascii.eqlIgnoreCase(p, s.po)) return s;
    return null;
}

pub fn stateByFips(fips: i64) ?StateRow {
    for (states) |s| if (s.fips == fips) return s;
    return null;
}

/// ASCII-uppercase a string into the arena (for STNAME/FIPNAME).
pub fn upperDup(ev: *eval.Evaluator, s: []const u8) ![]const u8 {
    const out = try ev.arena.alloc(u8, s.len);
    for (s, out) |c, *o| o.* = std.ascii.toUpper(c);
    return out;
}

/// Decode the HTML entities SAS's HTMLDECODE handles: named &lt;&gt;&amp;&quot;&apos;
/// and numeric &#nn; / &#xhh;. Unknown entities pass through verbatim.
pub fn htmlDecode(ev: *eval.Evaluator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] != '&') {
            try out.append(ev.arena, s[i]);
            i += 1;
            continue;
        }
        const semi = std.mem.indexOfScalarPos(u8, s, i, ';') orelse {
            try out.append(ev.arena, s[i]);
            i += 1;
            continue;
        };
        const ent = s[i + 1 .. semi];
        var decoded: ?u8 = null;
        if (std.mem.eql(u8, ent, "lt")) decoded = '<';
        if (std.mem.eql(u8, ent, "gt")) decoded = '>';
        if (std.mem.eql(u8, ent, "amp")) decoded = '&';
        if (std.mem.eql(u8, ent, "quot")) decoded = '"';
        if (std.mem.eql(u8, ent, "apos")) decoded = '\'';
        if (ent.len > 1 and ent[0] == '#') {
            const digits = ent[1..];
            const code = if (digits.len > 0 and (digits[0] == 'x' or digits[0] == 'X'))
                std.fmt.parseInt(u32, digits[1..], 16) catch null
            else
                std.fmt.parseInt(u32, digits, 10) catch null;
            if (code) |cp| if (cp < 256) {
                decoded = @intCast(cp);
            };
        }
        if (decoded) |c| {
            try out.append(ev.arena, c);
            i = semi + 1;
        } else {
            try out.append(ev.arena, s[i]);
            i += 1;
        }
    }
    return out.items;
}

/// Net present value at time 0 for cash flows c0,c1,…,cn (missing→0), rate `r`
/// (a fraction) over `freq` payments per base period. freq=0 → continuous.
pub fn netpvValue(r: f64, freq: f64, cash: []const Value) f64 {
    const x = if (freq == 0) @exp(-r) else 1.0 / std.math.pow(f64, 1 + r, 1.0 / freq);
    var sum: f64 = 0;
    var xi: f64 = 1;
    for (cash) |c| {
        const cv = toNum(c);
        if (!isMiss(cv)) sum += cv * xi;
        xi *= x;
    }
    return sum;
}

/// 30/360 day count between two SAS dates. `euro` = the European (basis 4) rule
/// (day 31 → 30 unconditionally on both ends); otherwise the US/NASD rule.
fn days30360(d1: i64, d2: i64, euro: bool) f64 {
    const c1 = civilFromSas(d1);
    const c2 = civilFromSas(d2);
    var a = c1.d;
    var b = c2.d;
    if (euro) {
        if (a == 31) a = 30;
        if (b == 31) b = 30;
    } else {
        if (a == 31) a = 30;
        if (b == 31 and a == 30) b = 30;
    }
    return @floatFromInt((c2.y - c1.y) * 360 + (c2.m - c1.m) * 30 + (b - a));
}

/// Day-count fraction (period length in years) between two SAS dates under a SAS
/// day-count basis: 0 = US 30/360, 1 = actual/actual, 2 = actual/360,
/// 3 = actual/365, 4 = European 30/360. ponytail: basis 1 uses a 365-day year
/// (exact for the sub-year discount-security periods DISC/RECEIVED/PRICEDISC use).
fn dcf(basis: f64, d1: i64, d2: i64) f64 {
    const actual: f64 = @floatFromInt(d2 - d1);
    return switch (@as(i64, @intFromFloat(basis))) {
        2 => actual / 360.0,
        3 => actual / 365.0,
        4 => days30360(d1, d2, true) / 360.0,
        1 => actual / 365.0,
        else => days30360(d1, d2, false) / 360.0, // 0
    };
}

/// The coupon period bracketing `settlement` for a bond maturing at `maturity`
/// paying `freq` times a year (1/2/4). Coupon dates march back from maturity in
/// 12/freq-month steps (day-of-month clamped to each month's length). `pcd` is the
/// coupon on or before settlement, `ncd` the next one after, `num` the count of
/// coupons still due after settlement through maturity.
const Coupon = struct { pcd: i64, ncd: i64, num: i64 };
fn couponSchedule(settlement: i64, maturity: i64, freq: i64) ?Coupon {
    if (freq != 1 and freq != 2 and freq != 4) return null;
    const step = @divTrunc(@as(i64, 12), freq);
    var k: i64 = 0;
    var cd = maturity;
    while (cd > settlement) {
        k += 1;
        cd = addMonthsCal(maturity, -k * step);
        if (k > 4000) return null; // safety: ~1000 years of coupons
    }
    return .{ .pcd = cd, .ncd = addMonthsCal(maturity, -(k - 1) * step), .num = k };
}

/// One FINANCE parameter as f64, `dflt` when absent or missing (SAS passes `.`
/// for an omitted optional argument).
fn fparam(p: []const Value, i: usize, dflt: f64) f64 {
    if (i >= p.len) return dflt;
    const x = toNum(p[i]);
    return if (isMiss(x)) dflt else x;
}

/// Annuity future value: -(pv·(1+r)^n + pmt·(1+r·type)·((1+r)^n−1)/r).
fn annFv(r: f64, n: f64, pmt: f64, pv: f64, ty: f64) f64 {
    if (r == 0) return -(pv + pmt * n);
    const g = std.math.pow(f64, 1 + r, n);
    return -(pv * g + pmt * (1 + r * ty) * (g - 1) / r);
}

/// The annuity balance at maturity, pv·(1+r)^n + pmt·(1+r·type)·((1+r)^n−1)/r + fv,
/// whose root (over r) is the RATE. For a large r, (1+r)^n overflows to +inf and the
/// naive expression is inf−inf = NaN, which breaks bisection — so when the growth
/// factor is non-finite we return a finite ±sentinel with the sign the balance takes
/// as r→∞ (dominated by pv·(1+r)^n, or pmt's sign when pv is zero). Root always lies
/// below that region, so the sentinel just tells bisection "go lower".
fn rateBalance(r: f64, n: f64, pmt: f64, pv: f64, fv: f64, ty: f64) f64 {
    if (r == 0) return pv + pmt * n + fv;
    const g = std.math.pow(f64, 1 + r, n);
    if (!std.math.isFinite(g) or !std.math.isFinite(g / r)) {
        const sign: f64 = if (pv > 0) 1 else if (pv < 0) -1 else if (pmt >= 0) 1 else -1;
        return sign * 1e300;
    }
    return pv * g + pmt * (1 + r * ty) * (g - 1) / r + fv;
}

/// Annuity level payment: -(pv·(1+r)^n + fv)·r / ((1+r·type)·((1+r)^n−1)).
fn annPmt(r: f64, n: f64, pv: f64, fv: f64, ty: f64) f64 {
    if (n == 0) return std.math.nan(f64);
    if (r == 0) return -(pv + fv) / n;
    const g = std.math.pow(f64, 1 + r, n);
    return -(pv * g + fv) * r / ((1 + r * ty) * (g - 1));
}

/// Interest portion of payment `per` (1-based): interest on the balance carried
/// into the period. Matches Excel/SAS IPMT for the default (end-of-period) case.
fn annIpmt(r: f64, per: f64, n: f64, pv: f64, fv: f64, ty: f64) f64 {
    const pmt = annPmt(r, n, pv, fv, ty);
    if (ty == 1) {
        if (per <= 1) return 0;
        return annFv(r, per - 2, pmt, pv, 1) * r;
    }
    return annFv(r, per - 1, pmt, pv, 0) * r;
}

/// Σ flow[i] / (1+r)^i, i from 0 — the polynomial FINANCE IRR drives to zero.
fn irrPoly(flows: []const Value, r: f64) f64 {
    var sum: f64 = 0;
    var disc: f64 = 1;
    const step = 1.0 / (1.0 + r);
    for (flows) |c| {
        sum += toNum(c) * disc;
        disc *= step;
    }
    return sum;
}

/// IRR by bracketed bisection over (−0.999, 100); null if no sign change.
fn irrSolve(flows: []const Value) ?f64 {
    var lo: f64 = -0.999999;
    var hi: f64 = 100.0;
    var flo = irrPoly(flows, lo);
    const fhi = irrPoly(flows, hi);
    if (isMiss(flo) or isMiss(fhi) or flo * fhi > 0) return null;
    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const mid = 0.5 * (lo + hi);
        const fm = irrPoly(flows, mid);
        if (@abs(fm) < 1e-12 or (hi - lo) < 1e-13) return mid;
        if (flo * fm <= 0) hi = mid else {
            lo = mid;
            flo = fm;
        }
    }
    return 0.5 * (lo + hi);
}

/// The FINANCE umbrella: `FINANCE(mode, params…)` dispatches to one financial
/// calculation. Implements the closed-form (Excel-parity) modes — annuities,
/// depreciation, rate conversion, cash-flow NPV/IRR/MIRR, dollar fractions.
/// ponytail: the security/bond/coupon modes (PRICE, YIELD, COUP*, ACCRINT, …)
/// need day-count-basis + coupon-schedule machinery and are not built yet — they
/// return missing with a NOTE, so FINANCE stays [ ] in the tracker until complete.
pub fn finance(ev: *eval.Evaluator, args: []const Value) eval.Error!Value {
    if (args.len < 1) return badArity(ev, "finance", "1 or more", args.len);
    const mode = try toStr(ev, args[0]);
    const p = args[1..];

    if (eqi(mode, "dollarde") or eqi(mode, "dollarfr")) {
        const dollar = fparam(p, 0, 0);
        const fr = fparam(p, 1, 0);
        if (fr == 0) return domErr(ev, "finance");
        const ipart = @trunc(dollar);
        const frac = dollar - ipart;
        const k = @ceil(@log10(fr)); // digit positions the fraction occupies
        const scale = std.math.pow(f64, 10, k);
        return numVal(if (eqi(mode, "dollarde")) ipart + frac * scale / fr else ipart + frac * fr / scale);
    }
    if (eqi(mode, "fvschedule")) {
        var v = fparam(p, 0, 0); // principal
        for (p[1..]) |r| v *= (1 + toNum(r));
        return numVal(v);
    }
    // EFFECT/NOMINAL are the SAS mode names; EFFRATE/NOMRATE are accepted aliases
    if (eqi(mode, "effect") or eqi(mode, "effrate")) { // effective rate from nominal, npery compoundings
        const nom = fparam(p, 0, 0);
        const npery = fparam(p, 1, 0);
        if (npery < 1) return domErr(ev, "finance");
        return numVal(std.math.pow(f64, 1 + nom / npery, npery) - 1);
    }
    if (eqi(mode, "nominal") or eqi(mode, "nomrate")) {
        const eff = fparam(p, 0, 0);
        const npery = fparam(p, 1, 0);
        if (npery < 1 or eff <= -1) return domErr(ev, "finance");
        return numVal(npery * (std.math.pow(f64, 1 + eff, 1.0 / npery) - 1));
    }
    if (eqi(mode, "nper")) { // NPER(rate, pmt, pv, <fv>, <type>): number of periods
        const r = fparam(p, 0, 0);
        const pmt = fparam(p, 1, 0);
        const pv = fparam(p, 2, 0);
        const fv = fparam(p, 3, 0);
        const ty = fparam(p, 4, 0);
        if (r == 0) { // no interest: nper = -(pv + fv) / pmt
            if (pmt == 0) return domErr(ev, "finance");
            return numVal(-(pv + fv) / pmt);
        }
        // (1+r)^nper = (pmt(1+r·type) − fv·r) / (pmt(1+r·type) + pv·r)
        const c = pmt * (1 + r * ty);
        const num = c - fv * r;
        const den = c + pv * r;
        if (den == 0 or (num / den) <= 0) return domErr(ev, "finance");
        return numVal(@log(num / den) / @log(1 + r));
    }
    if (eqi(mode, "coupncd") or eqi(mode, "couppcd") or eqi(mode, "coupnum") or
        eqi(mode, "coupdays") or eqi(mode, "coupdaybs") or eqi(mode, "coupdaysnc"))
    {
        // COUP*(settlement, maturity, frequency, basis)
        if (p.len < 3) return badArity(ev, "finance", "settlement, maturity, frequency", p.len);
        const set = toNum(p[0]);
        const mat = toNum(p[1]);
        const freq = fparam(p, 2, 0);
        if (isMiss(set) or isMiss(mat)) return Value.missing;
        const basis = fparam(p, 3, 0);
        const s = floorI64(set);
        const c = couponSchedule(s, floorI64(mat), floorI64(freq)) orelse return Value.missing;
        const thirty = basis == 0 or basis == 4;
        if (eqi(mode, "coupncd")) return numVal(@floatFromInt(c.ncd));
        if (eqi(mode, "couppcd")) return numVal(@floatFromInt(c.pcd));
        if (eqi(mode, "coupnum")) return numVal(@floatFromInt(c.num));
        if (eqi(mode, "coupdays")) // days in the coupon period containing settlement
            return numVal(if (thirty) 360.0 / freq else @floatFromInt(c.ncd - c.pcd));
        if (eqi(mode, "coupdaybs")) // days from period start to settlement
            return numVal(if (thirty) days30360(c.pcd, s, basis == 4) else @floatFromInt(s - c.pcd));
        // coupdaysnc: days from settlement to next coupon
        return numVal(if (thirty) days30360(s, c.ncd, basis == 4) else @floatFromInt(c.ncd - s));
    }
    if (eqi(mode, "disc") or eqi(mode, "pricedisc") or eqi(mode, "received") or
        eqi(mode, "intrate") or eqi(mode, "yielddisc"))
    {
        if (p.len < 4) return badArity(ev, "finance", "settlement, maturity + 2 args", p.len);
    }
    if (eqi(mode, "intrate") or eqi(mode, "yielddisc")) {
        // INTRATE(settlement, maturity, investment, redemption, basis) and
        // YIELDDISC(settlement, maturity, price, redemption, basis): (red−base)/base / dcf
        const set = toNum(p[0]);
        const mat = toNum(p[1]);
        const base = fparam(p, 2, 0); // investment (INTRATE) or price (YIELDDISC)
        const red = fparam(p, 3, 0);
        if (isMiss(set) or isMiss(mat) or base == 0) return Value.missing;
        const f = dcf(fparam(p, 4, 0), floorI64(set), floorI64(mat));
        if (f == 0) return Value.missing;
        return numVal((red - base) / base / f);
    }
    if (eqi(mode, "disc")) { // DISC(settlement, maturity, price, redemption, basis): discount rate
        const set = toNum(p[0]);
        const mat = toNum(p[1]);
        const price = fparam(p, 2, 0);
        const red = fparam(p, 3, 0);
        if (isMiss(set) or isMiss(mat) or red == 0) return Value.missing;
        const f = dcf(fparam(p, 4, 0), floorI64(set), floorI64(mat));
        if (f == 0) return Value.missing;
        return numVal((red - price) / red / f);
    }
    if (eqi(mode, "pricedisc")) { // PRICEDISC(settlement, maturity, discount, redemption, basis)
        const set = toNum(p[0]);
        const mat = toNum(p[1]);
        const disc = fparam(p, 2, 0);
        const red = fparam(p, 3, 0);
        if (isMiss(set) or isMiss(mat)) return Value.missing;
        const f = dcf(fparam(p, 4, 0), floorI64(set), floorI64(mat));
        return numVal(red * (1 - disc * f));
    }
    if (eqi(mode, "received")) { // RECEIVED(settlement, maturity, investment, discount, basis)
        const set = toNum(p[0]);
        const mat = toNum(p[1]);
        const inv = fparam(p, 2, 0);
        const disc = fparam(p, 3, 0);
        if (isMiss(set) or isMiss(mat)) return Value.missing;
        const f = dcf(fparam(p, 4, 0), floorI64(set), floorI64(mat));
        const den = 1 - disc * f;
        if (den == 0) return Value.missing;
        return numVal(inv / den);
    }
    if (eqi(mode, "fv")) { // FV(rate, nper, pmt, pv, type)
        const r = fparam(p, 0, 0);
        const n = fparam(p, 1, 0);
        const pmt = fparam(p, 2, 0);
        const pv = fparam(p, 3, 0);
        const ty = fparam(p, 4, 0);
        if (r == 0) return numVal(-(pv + pmt * n));
        const g = std.math.pow(f64, 1 + r, n);
        return numVal(-(pv * g + pmt * (1 + r * ty) * (g - 1) / r));
    }
    if (eqi(mode, "pv")) { // PV(rate, nper, pmt, fv, type)
        const r = fparam(p, 0, 0);
        const n = fparam(p, 1, 0);
        const pmt = fparam(p, 2, 0);
        const fv = fparam(p, 3, 0);
        const ty = fparam(p, 4, 0);
        if (r == 0) return numVal(-(fv + pmt * n));
        const g = std.math.pow(f64, 1 + r, n);
        return numVal(-(fv + pmt * (1 + r * ty) * (g - 1) / r) / g);
    }
    if (eqi(mode, "pmt")) { // PMT(rate, nper, pv, fv, type)
        const r = fparam(p, 0, 0);
        const n = fparam(p, 1, 0);
        const pv = fparam(p, 2, 0);
        const fv = fparam(p, 3, 0);
        const ty = fparam(p, 4, 0);
        if (n == 0) return Value.missing;
        if (r == 0) return numVal(-(pv + fv) / n);
        const g = std.math.pow(f64, 1 + r, n);
        return numVal(-(pv * g + fv) * r / ((1 + r * ty) * (g - 1)));
    }
    if (eqi(mode, "ipmt")) { // IPMT(rate, per, nper, pv, fv, type)
        return numVal(annIpmt(fparam(p, 0, 0), fparam(p, 1, 0), fparam(p, 2, 0), fparam(p, 3, 0), fparam(p, 4, 0), fparam(p, 5, 0)));
    }
    if (eqi(mode, "ppmt")) { // principal portion = payment − interest
        const r = fparam(p, 0, 0);
        const per = fparam(p, 1, 0);
        const n = fparam(p, 2, 0);
        const pv = fparam(p, 3, 0);
        const fv = fparam(p, 4, 0);
        const ty = fparam(p, 5, 0);
        return numVal(annPmt(r, n, pv, fv, ty) - annIpmt(r, per, n, pv, fv, ty));
    }
    if (eqi(mode, "cumipmt") or eqi(mode, "cumprinc")) {
        // CUM*(rate, nper, pv, start-period, end-period, type): sum over the range
        const r = fparam(p, 0, 0);
        const n = fparam(p, 1, 0);
        const pv = fparam(p, 2, 0);
        const s = fparam(p, 3, 0);
        const en = fparam(p, 4, 0);
        const ty = fparam(p, 5, 0);
        if (s < 1 or en < s or en > n) return Value.missing;
        const pmt = annPmt(r, n, pv, 0, ty);
        var sum: f64 = 0;
        var per = s;
        while (per <= en) : (per += 1) {
            const ip = annIpmt(r, per, n, pv, 0, ty);
            sum += if (eqi(mode, "cumipmt")) ip else (pmt - ip); // principal = pmt − interest
        }
        return numVal(sum);
    }
    if (eqi(mode, "ispmt")) { // ISPMT(rate, per, nper, pv) = pv·rate·(per/nper − 1)
        const r = fparam(p, 0, 0);
        const per = fparam(p, 1, 0);
        const n = fparam(p, 2, 0);
        const pv = fparam(p, 3, 0);
        if (n == 0) return Value.missing;
        return numVal(pv * r * (per / n - 1));
    }
    if (eqi(mode, "nper")) { // NPER(rate, payment, pv, fv, type)
        const r = fparam(p, 0, 0);
        const pmt = fparam(p, 1, 0);
        const pv = fparam(p, 2, 0);
        const fv = fparam(p, 3, 0);
        const ty = fparam(p, 4, 0);
        if (r == 0) {
            if (pmt == 0) return Value.missing;
            return numVal(-(pv + fv) / pmt);
        }
        const a = pmt * (1 + r * ty);
        const num = a - fv * r;
        const den = a + pv * r;
        if (num <= 0 or den <= 0) return Value.missing; // log of non-positive
        return numVal(@log(num / den) / @log(1 + r));
    }
    if (eqi(mode, "rate")) { // RATE(nper, payment, pv, fv, type): solve for the period rate
        const n = fparam(p, 0, 0);
        const pmt = fparam(p, 1, 0);
        const pv = fparam(p, 2, 0);
        const fv = fparam(p, 3, 0);
        const ty = fparam(p, 4, 0);
        // bisect the annuity-balance root; rateBalance() is overflow-safe so a
        // large-r (1+r)^n → inf can't poison the sign test (BUG-rategarbage)
        var lo: f64 = -0.999999;
        var hi: f64 = 100.0;
        var flo = rateBalance(lo, n, pmt, pv, fv, ty);
        const fhi = rateBalance(hi, n, pmt, pv, fv, ty);
        if (flo * fhi > 0) return Value.missing;
        var i: usize = 0;
        while (i < 300) : (i += 1) {
            const mid = 0.5 * (lo + hi);
            const fm = rateBalance(mid, n, pmt, pv, fv, ty);
            if (@abs(fm) < 1e-12 or (hi - lo) < 1e-15) return numVal(mid);
            if (flo * fm <= 0) hi = mid else {
                lo = mid;
                flo = fm;
            }
        }
        return numVal(0.5 * (lo + hi));
    }
    if (eqi(mode, "npv")) { // Σ v_i/(1+rate)^i, i from 1
        const r = fparam(p, 0, 0);
        var sum: f64 = 0;
        var disc: f64 = 1.0 / (1.0 + r);
        for (p[1..]) |c| {
            sum += toNum(c) * disc;
            disc /= (1.0 + r);
        }
        return numVal(sum);
    }
    if (eqi(mode, "irr")) {
        return if (irrSolve(p)) |r| numVal(r) else Value.missing;
    }
    if (eqi(mode, "mirr")) { // flows…, finance-rate, reinvest-rate
        if (p.len < 3) return badArity(ev, "finance", "flows + 2 rates", p.len);
        const flows = p[0 .. p.len - 2];
        const frate = toNum(p[p.len - 2]);
        const rrate = toNum(p[p.len - 1]);
        const n = flows.len;
        var pv_neg: f64 = 0;
        var fv_pos: f64 = 0;
        for (flows, 0..) |c, i| {
            const v = toNum(c);
            if (v < 0) pv_neg += v / std.math.pow(f64, 1 + frate, @floatFromInt(i));
            if (v > 0) fv_pos += v * std.math.pow(f64, 1 + rrate, @floatFromInt(n - 1 - i));
        }
        if (pv_neg == 0 or n < 2) return Value.missing;
        return numVal(std.math.pow(f64, fv_pos / -pv_neg, 1.0 / @as(f64, @floatFromInt(n - 1))) - 1);
    }
    if (eqi(mode, "sln")) { // straight-line depreciation per period
        const cost = fparam(p, 0, 0);
        const salvage = fparam(p, 1, 0);
        const life = fparam(p, 2, 0);
        if (life == 0) return Value.missing;
        return numVal((cost - salvage) / life);
    }
    if (eqi(mode, "syd")) { // sum-of-years-digits depreciation for `period`
        const cost = fparam(p, 0, 0);
        const salvage = fparam(p, 1, 0);
        const life = fparam(p, 2, 0);
        const per = fparam(p, 3, 0);
        if (life <= 0) return Value.missing;
        return numVal((cost - salvage) * (life - per + 1) * 2 / (life * (life + 1)));
    }
    if (eqi(mode, "ddb")) { // (double-)declining-balance depreciation for `period`
        const cost = fparam(p, 0, 0);
        const salvage = fparam(p, 1, 0);
        const life = fparam(p, 2, 0);
        const per = fparam(p, 3, 0);
        const factor = fparam(p, 4, 2);
        if (life <= 0) return Value.missing;
        var book = cost;
        var dep: f64 = 0;
        var i: f64 = 0;
        while (i < per) : (i += 1) {
            dep = @min(book * factor / life, book - salvage);
            if (dep < 0) dep = 0;
            book -= dep;
        }
        return numVal(dep);
    }
    if (eqi(mode, "db")) { // fixed-declining-balance depreciation for `period`
        const cost = fparam(p, 0, 0);
        const salvage = fparam(p, 1, 0);
        const life = fparam(p, 2, 0);
        const per = fparam(p, 3, 0);
        const month = fparam(p, 4, 12);
        if (life <= 0 or cost <= 0) return Value.missing;
        const rate = @round((1 - std.math.pow(f64, salvage / cost, 1.0 / life)) * 1000) / 1000;
        var accum: f64 = cost * rate * month / 12; // period 1 (partial by `month`)
        if (per == 1) return numVal(accum);
        var dep = accum;
        var k: f64 = 2;
        while (k <= per) : (k += 1) {
            dep = if (k > life) (cost - accum) * rate * (12 - month) / 12 else (cost - accum) * rate;
            accum += dep;
        }
        return numVal(dep);
    }

    note(ev, "FINANCE mode '{s}' is not supported yet", .{mode});
    return Value.missing;
}

/// Internal rate of return (fraction) making NETPV zero, by bracketed bisection.
/// null if the cash flows don't bracket a root in (−1, ∞).
pub fn solveIrr(freq: f64, cash: []const Value) ?f64 {
    var lo: f64 = -0.999999;
    var hi: f64 = 1e7;
    var flo = netpvValue(lo, freq, cash);
    const fhi = netpvValue(hi, freq, cash);
    if ((flo > 0) == (fhi > 0)) return null; // not bracketed
    var it: usize = 0;
    while (it < 200) : (it += 1) {
        const mid = 0.5 * (lo + hi);
        const fm = netpvValue(mid, freq, cash);
        if ((fm > 0) == (flo > 0)) {
            lo = mid;
            flo = fm;
        } else hi = mid;
        if (hi - lo < 1e-12 * (1 + @abs(mid))) break;
    }
    return 0.5 * (lo + hi);
}

/// Accumulated depreciation through time `p` (clamped to [0,y]) — one closed form
/// per method. The per-period depreciation is DACC(p)−DACC(p−1); SAS's fractional-
/// period proration falls straight out of the difference. Verified against the PDF
/// examples (DEPSL=75, DEPSYD 83.33/316.67, DACCSL=175, DACCDB=760.93).
pub const DepMethod = enum { sl, syd, db };
pub fn daccOf(m: DepMethod, p_in: f64, v: f64, y: f64, r: f64) f64 {
    const p = @max(0, @min(p_in, y));
    return switch (m) {
        .sl => p * v / y, // straight line: constant v/y per period
        .syd => blk: { // sum-of-years-digits: rate (y−j+1)/T for period j
            const k = @floor(p);
            const frac = p - k;
            const total = y * (y + 1) / 2;
            const full = k * (2 * y - k + 1) / 2; // Σ_{j=1}^{k}(y−j+1)
            break :blk v * (full + frac * (y - k)) / total;
        },
        .db => v * (1 - std.math.pow(f64, 1 - r / y, p)), // declining balance, rate r/y
    };
}

/// Generalized Black option price from a forward `fwd`, strike `k`, vol `sigma`,
/// maturity `t`, and discount factor `disc`. `call`=true → call, else put. This one
/// helper covers Black-Scholes (fwd=S·e^{rt}), Black-76 (fwd=F), Garman-Kohlhagen
/// (fwd=S·e^{(Rd−Rf)t}) and Margrabe (fwd=X1, k=X2, disc=1).
pub fn blackOption(fwd: f64, k: f64, sigma: f64, tm: f64, disc: f64, call: bool) f64 {
    const st = sigma * @sqrt(tm);
    const d1 = (@log(fwd / k) + 0.5 * st * st) / st;
    const d2 = d1 - st;
    return if (call)
        disc * (fwd * stdNormCdf(d1) - k * stdNormCdf(d2))
    else
        disc * (k * stdNormCdf(-d2) - fwd * stdNormCdf(-d1));
}

/// Accumulated declining-balance-with-straight-line-conversion depreciation through
/// time `p`. Each period takes max(DB, SL-on-remaining); once SL wins it stays SL,
/// so the asset fully depreciates by `y`. No closed form → iterate, prorating the
/// fractional tail. DACCDBSL(y)=v; DEPDBSL(p)=DACCDBSL(p)−DACCDBSL(p−1).
pub fn daccDbsl(p_in: f64, v: f64, y: f64, r: f64) f64 {
    const p = @max(0, @min(p_in, y));
    const full: usize = @intFromFloat(@floor(p));
    const frac = p - @floor(p);
    var acc: f64 = 0;
    var book = v;
    var k: usize = 1;
    while (k <= full) : (k += 1) {
        const remaining_life = y - @as(f64, @floatFromInt(k - 1));
        const dep = @max(book * r / y, book / remaining_life);
        acc += dep;
        book -= dep;
    }
    if (frac > 0 and @as(f64, @floatFromInt(full)) < y) {
        const remaining_life = y - @as(f64, @floatFromInt(full));
        const dep = @max(book * r / y, book / remaining_life);
        acc += dep * frac;
    }
    return acc;
}

/// Present value of an enumerated cash flow: Σ c(k)/(1+y)^(k/f).
pub fn enumPv(y: f64, f: f64, cfs: []const Value) f64 {
    var p: f64 = 0;
    for (cfs, 1..) |c, k| {
        p += toNum(c) / std.math.pow(f64, 1 + y, @as(f64, @floatFromInt(k)) / f);
    }
    return p;
}

/// Price of a periodic (bond) cash flow stream — PVP and the base for DURP/CONVXP.
/// t_k = n·k0+k−1; coupon c/n·A each period, plus par A at the last.
pub fn bondPv(a: f64, c: f64, n: f64, bigK: usize, k0: f64, y: f64) f64 {
    const yr = y / n;
    var p: f64 = 0;
    var k: usize = 1;
    while (k <= bigK) : (k += 1) {
        const tk = n * k0 + @as(f64, @floatFromInt(k)) - 1;
        const ck = c / n * a + (if (k == bigK) a else 0);
        p += ck / std.math.pow(f64, 1 + yr, tk);
    }
    return p;
}

/// GLM deviance of `y` from mean/shape `mu` for a named distribution; null if the
/// distribution is unsupported. Standard exponential-family unit deviances.
/// BUG-devianceeps (SAS 9.4 functions ref pp.614–618): every distribution except
/// NORMAL takes an ε (default 1e-12, floored to 1e-12, capped at 0.01) that clamps
/// the boundary args, so boundary inputs yield FINITE deviances instead of
/// log(0)/÷0 → missing: BERNOULLI p→[ε,1−ε]; BINOMIAL μ→[nε, n(1−ε)];
/// GAMMA/IGAUSS variable and μ→[ε,∞); POISSON μ→[ε,∞). `n` is BINOMIAL's trial
/// count (ignored otherwise). Clamping applies only on the documented intervals
/// — out-of-domain negatives stay on the NaN→missing path (doc formula tables).
pub fn devianceOf(dist: []const u8, y: f64, mu: f64, n: f64, eps_in: f64) ?f64 {
    const d = std.mem.trim(u8, dist, " ");
    const ylny = struct { // y·ln(y/m), with the 0·ln0 = 0 limit
        fn f(a: f64, m: f64) f64 {
            return if (a == 0) 0 else a * @log(a / m);
        }
    }.f;
    if (distIs(d, "NORMAL") or distIs(d, "GAUSSIAN")) return (y - mu) * (y - mu); // no ε per doc
    const eps = @min(0.01, @max(1e-12, eps_in)); // doc: <1e-12 → 1e-12, >0.01 → 0.01
    const lo = struct { // v in [0, bound) → bound; anything else untouched
        fn f(v: f64, bound: f64) f64 {
            return if (v >= 0 and v < bound) bound else v;
        }
    }.f;
    if (distIs(d, "POISSON")) {
        const m = lo(mu, eps);
        return 2 * (ylny(y, m) - (y - m));
    }
    if (distIs(d, "GAMMA")) {
        const yy = lo(y, eps);
        const m = lo(mu, eps);
        return 2 * ((yy - m) / m - @log(yy / m));
    }
    if (distIs(d, "IGAUSS") or distIs(d, "WALD")) {
        const yy = lo(y, eps);
        const m = lo(mu, eps);
        return (yy - m) * (yy - m) / (m * m * yy);
    }
    if (distIs(d, "BERNOULLI") or distIs(d, "BERN")) {
        var p = mu;
        if (p >= 0 and p < eps) p = eps;
        if (p > 1 - eps and p <= 1) p = 1 - eps;
        return if (y == 1) -2 * @log(p) else -2 * @log(1 - p);
    }
    if (distIs(d, "BINOMIAL") or distIs(d, "BINO")) { // mu is the mean np, n = trials
        var m = mu;
        if (m >= 0 and m < n * eps) m = n * eps;
        if (m > n * (1 - eps) and m <= n) m = n * (1 - eps);
        return 2 * (ylny(y, m) + ylny(n - y, n - m));
    }
    return null;
}

/// Excel-/SAS-compatible level payment: PMT(rate,nper,pv,fv,type). Negative for a
/// loan (positive pv). type 0 = end-of-period, 1 = beginning.
pub fn pmtOf(r: f64, n: f64, pv: f64, fv: f64, kind: f64) f64 {
    if (r == 0) return -(pv + fv) / n;
    const pw = std.math.pow(f64, 1 + r, n);
    return -(pv * pw + fv) * r / ((pw - 1) * (1 + r * kind));
}

/// Remaining balance (FV of principal + payments) after `k` periods of `pmt`.
fn balanceAfter(r: f64, k: f64, pv: f64, pmt: f64, kind: f64) f64 {
    if (r == 0) return pv + pmt * k;
    const pw = std.math.pow(f64, 1 + r, k);
    return pv * pw + pmt * (1 + r * kind) * (pw - 1) / r;
}

/// Interest portion of the payment in period `per` (Excel IPMT convention).
pub fn ipmtOf(r: f64, per: f64, n: f64, pv: f64, fv: f64, kind: f64) f64 {
    const pmt = pmtOf(r, n, pv, fv, kind);
    if (kind == 1 and per == 1) return 0; // begin-of-period first payment has no interest
    const bal = balanceAfter(r, per - 1, pv, pmt, kind); // outstanding at start of `per`
    const ip = -bal * r; // interest is an outflow (negative), like PMT
    return if (kind == 1) ip / (1 + r) else ip;
}

/// Hypergeometric CDF P(X≤x): direct pmf sum, each term via lgamma binomials.
/// Central only (odds ratio r=1). N pop, K tagged, n drawn.
pub fn hyperCdf(bigN: f64, bigK: f64, n: f64, x: f64) f64 {
    const logC = struct {
        fn f(a: f64, b: f64) f64 { // log C(a,b)
            if (b < 0 or b > a) return -std.math.inf(f64);
            return lgammaOf(a + 1) - lgammaOf(b + 1) - lgammaOf(a - b + 1);
        }
    }.f;
    const denom = logC(bigN, n);
    const lo = @max(0, n - (bigN - bigK));
    const hi = @min(x, @min(bigK, n));
    if (hi < lo) return 0;
    // BUG-probhyprhang: iterate an INTEGER term count, not a float `i` — for a huge
    // population `i += 1` is a float no-op (i > 2^53) → infinite loop. Also cap the
    // term count (SAS switches to an approximation we don't model → missing).
    const terms = hi - lo + 1;
    if (terms > 2_000_000) return std.math.nan(f64);
    const nterms: usize = @intFromFloat(terms);
    var sum: f64 = 0;
    var tk: usize = 0;
    while (tk < nterms) : (tk += 1) {
        const i = lo + @as(f64, @floatFromInt(tk));
        sum += @exp(logC(bigK, i) + logC(bigN - bigK, n - i) - denom);
    }
    return sum;
}

/// Bessel J_nu(x) by its ascending series (stable for |x| up to ~15; our use is
/// small x). ponytail: no large-x asymptotic — returns the series value regardless.
pub fn besselJ(nu: f64, x: f64) f64 {
    const h = x / 2.0;
    var term = std.math.pow(f64, h, nu) / @exp(lgammaOf(nu + 1)); // k=0
    var sum = term;
    var k: f64 = 1;
    while (k < 100) : (k += 1) {
        term *= -(h * h) / (k * (nu + k));
        sum += term;
        if (@abs(term) < 1e-16 * @abs(sum)) break;
    }
    return sum;
}

/// Modified Bessel I_nu(x), ascending series; `scaled` returns exp(−|x|)·I.
pub fn besselI(nu: f64, x: f64, scaled: bool) f64 {
    const h = x / 2.0;
    var term = std.math.pow(f64, h, nu) / @exp(lgammaOf(nu + 1));
    var sum = term;
    var k: f64 = 1;
    while (k < 200) : (k += 1) {
        term *= (h * h) / (k * (nu + k));
        sum += term;
        if (@abs(term) < 1e-16 * @abs(sum)) break;
    }
    return if (scaled) sum * @exp(-@abs(x)) else sum;
}

/// Airy Ai(x) or Ai′(x) via the two ascending series f,g: Ai = c1·f − c2·g.
/// ponytail: converges for |x|≲6; no asymptotic beyond.
const airy_c1 = 0.3550280538878172; //  Ai(0)
const airy_c2 = 0.2588194037928068; // −Ai′(0)
fn airyAi(x: f64, derivative: bool) f64 {
    var f: f64 = 1; // f = Σ ∏(3j+1)/(3k)! x^{3k}
    var g: f64 = x; // g = Σ ∏(3j+2)/(3k+1)! x^{3k+1}
    var fp: f64 = 0; // f′
    var gp: f64 = 1; // g′
    var cf: f64 = 1; // current f term
    var cg: f64 = x; // current g term
    var k: f64 = 1;
    while (k < 60) : (k += 1) {
        cf *= x * x * x / ((3 * k) * (3 * k - 1));
        cg *= x * x * x / ((3 * k + 1) * (3 * k));
        f += cf;
        g += cg;
        if (x != 0) {
            fp += cf * 3 * k / x;
            gp += cg * (3 * k + 1) / x;
        }
        if (@abs(cf) + @abs(cg) < 1e-18 * (@abs(f) + @abs(g))) break;
    }
    return if (derivative) airy_c1 * fp - airy_c2 * gp else airy_c1 * f - airy_c2 * g;
}

/// NVALID: is `s` a valid SAS variable name under the (default) V7 rules —
/// 1–32 chars, first a letter or underscore, rest letters/digits/underscore.
pub fn isValidName(s: []const u8) bool {
    if (s.len == 0 or s.len > 32) return false;
    if (!(std.ascii.isAlphabetic(s[0]) or s[0] == '_')) return false;
    for (s[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}

/// HTMLENCODE default: encode & < > as &amp; &lt; &gt; (SAS's default set).
pub fn htmlEncode(ev: *eval.Evaluator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| switch (c) {
        '&' => try out.appendSlice(ev.arena, "&amp;"),
        '<' => try out.appendSlice(ev.arena, "&lt;"),
        '>' => try out.appendSlice(ev.arena, "&gt;"),
        else => try out.append(ev.arena, c),
    };
    return out.items;
}

/// Lowercase-hex encode raw bytes into the arena.
pub fn hexEncode(ev: *eval.Evaluator, bytes: []const u8) ![]const u8 {
    const hex = "0123456789abcdef";
    const out = try ev.arena.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0F];
    }
    return out;
}

/// MVALID COMPAT rule (doc p.1219): letter/underscore start, then letters/digits/
/// underscores, length ≤ 32.
pub fn mvalidCompat(s: []const u8) bool {
    if (s.len == 0 or s.len > 32) return false;
    if (!(std.ascii.isAlphabetic(s[0]) or s[0] == '_')) return false;
    for (s[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}
/// MVALID EXTEND rule (doc p.1219): ≤ 32 bytes, no / \ * ? " < > | : - or NUL, and
/// must not start with a blank or period.
pub fn mvalidExtend(s: []const u8) bool {
    if (s.len == 0 or s.len > 32 or s[0] == ' ' or s[0] == '.') return false;
    for (s) |c| switch (c) {
        0, '/', '\\', '*', '?', '"', '<', '>', '|', ':', '-' => return false,
        else => {},
    };
    return true;
}

/// Uppercase hex — HASHING_TERM renders its digest in uppercase (doc p.986).
pub fn hexEncodeUpper(ev: *eval.Evaluator, bytes: []const u8) ![]const u8 {
    const hex = "0123456789ABCDEF";
    const out = try ev.arena.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        out[i * 2] = hex[b >> 4];
        out[i * 2 + 1] = hex[b & 0x0F];
    }
    return out;
}

/// Running-digest state for HASHING_INIT/PART/TERM. We accumulate the message and
/// one-shot hashDigest() it at TERM — the final digest equals hashing the
/// concatenation, which is the only observable value. The table is process-global
/// because dispatch() is value-in/value-out and has nowhere per-session to stash a
/// handle. ponytail: global, allocations leak per handle, and (unlike SAS) a handle
/// survives across DATA steps — harmless for a single-program run. Upgrade path if
/// isolation ever matters: move this beside `ev.lag` as a per-Evaluator field.
const HashCtx = struct { method: []const u8, buf: std.ArrayList(u8), key: ?[]const u8 = null };
var hashing_table: std.ArrayList(HashCtx) = .empty;

/// Resolve a HASHING_* handle Value (1-based) to its running state, or null if the
/// handle is missing/out of range.
fn hashingCtx(handle: Value) ?*HashCtx {
    const h = toNum(handle);
    if (std.math.isNan(h)) return null;
    const idx = @as(i64, @intFromFloat(h)) - 1;
    if (idx < 0 or idx >= @as(i64, @intCast(hashing_table.items.len))) return null;
    return &hashing_table.items[@intCast(idx)];
}

/// Compute a named message digest of `msg` into `out`; returns the digest length
/// (bytes) or null for an unknown method. Covers MD5/SHA1/SHA256/SHA384/SHA512.
pub fn hashDigest(method: []const u8, msg: []const u8, out: *[64]u8) ?usize {
    const m = std.mem.trim(u8, method, " ");
    if (eqi(m, "MD5")) {
        std.crypto.hash.Md5.hash(msg, out[0..16], .{});
        return 16;
    }
    if (eqi(m, "SHA1")) {
        std.crypto.hash.Sha1.hash(msg, out[0..20], .{});
        return 20;
    }
    if (eqi(m, "SHA256")) {
        std.crypto.hash.sha2.Sha256.hash(msg, out[0..32], .{});
        return 32;
    }
    if (eqi(m, "SHA384")) {
        std.crypto.hash.sha2.Sha384.hash(msg, out[0..48], .{});
        return 48;
    }
    if (eqi(m, "SHA512")) {
        std.crypto.hash.sha2.Sha512.hash(msg, out[0..64], .{});
        return 64;
    }
    if (eqi(m, "CRC32")) { // 4-byte IEEE CRC-32, big-endian → hex like "352441c2"
        std.mem.writeInt(u32, out[0..4], std.hash.crc.Crc32.hash(msg), .big);
        return 4;
    }
    return null;
}

/// HMAC of `msg` under `key` for a named hash; returns the MAC length or null.
pub fn hmacDigest(method: []const u8, key: []const u8, msg: []const u8, out: *[64]u8) ?usize {
    const m = std.mem.trim(u8, method, " ");
    const hmac = std.crypto.auth.hmac;
    if (eqi(m, "MD5")) {
        hmac.Hmac(std.crypto.hash.Md5).create(out[0..16], msg, key);
        return 16;
    }
    if (eqi(m, "SHA1")) {
        hmac.Hmac(std.crypto.hash.Sha1).create(out[0..20], msg, key);
        return 20;
    }
    if (eqi(m, "SHA256")) {
        hmac.sha2.HmacSha256.create(out[0..32], msg, key);
        return 32;
    }
    if (eqi(m, "SHA384")) {
        hmac.sha2.HmacSha384.create(out[0..48], msg, key);
        return 48;
    }
    if (eqi(m, "SHA512")) {
        hmac.sha2.HmacSha512.create(out[0..64], msg, key);
        return 64;
    }
    return null;
}

/// URLENCODE: percent-encode everything but the RFC-3986 unreserved set
/// (A–Z a–z 0–9 - _ . ~). Space → %20 (SAS does not use '+').
pub fn urlEncode(ev: *eval.Evaluator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (s) |c| {
        if (std.ascii.isAlphanumeric(c) or c == '-' or c == '_' or c == '.' or c == '~') {
            try out.append(ev.arena, c);
        } else {
            const hex = "0123456789ABCDEF";
            try out.appendSlice(ev.arena, &.{ '%', hex[c >> 4], hex[c & 0x0F] });
        }
    }
    return out.items;
}

/// Decode URL percent-escapes (%HH) and treat '+' as a space.
pub fn urlDecode(ev: *eval.Evaluator, s: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '%' and i + 2 < s.len) {
            if (std.fmt.parseInt(u8, s[i + 1 .. i + 3], 16)) |b| {
                try out.append(ev.arena, b);
                i += 2;
                continue;
            } else |_| {}
        }
        try out.append(ev.arena, if (s[i] == '+') ' ' else s[i]);
    }
    return out.items;
}

/// `<prefix>[n]` → depth `n` (bare name = 1), else null. `lag`→1, `lag2`→2,
/// `dif`→1; rejects `lag0` and unrelated names (`lags`, `different`).
fn queueDepth(name: []const u8, prefix: []const u8) ?usize {
    if (name.len < prefix.len or !eqi(name[0..prefix.len], prefix)) return null;
    const rest = name[prefix.len..];
    if (rest.len == 0) return 1;
    const n = std.fmt.parseInt(usize, rest, 10) catch return null;
    return if (n == 0) null else n;
}

/// The LAG value for this call: the input from `n` executions ago, or missing
/// until the FIFO is deep enough. Then records the current input. DIF drives
/// the same machinery under its own key, so LAG and DIF never share a queue.
///
/// Keyed by the call *site*, not the function text: `name` is the token slice
/// from the AST (`ast.Call.name`), so two `lag(x)`/`lag(y)` calls are distinct
/// tokens at distinct source offsets → distinct `name.ptr` → independent
/// queues (matching SAS, where each LAG occurrence has its own queue). The AST
/// is built once, so the same site presents the same pointer every iteration;
/// a fresh DATA step re-parses (new pointers) and gets a fresh Evaluator.
/// SAS's classic uniform RNG (Fishman & Moore 1982, prime-modulus multiplicative:
/// x←16807·x mod 2³¹−1, value = x/(2³¹−1)). One stream per data step, held in
/// `ev.lag` under a fixed key: the FIRST positive seed initializes it and every
/// subsequent random draw (any generator) advances the same stream, so sequential
/// draws differ and a fixed seed is reproducible — matching SAS's shared-stream model.
/// ponytail: SAS's DOCUMENTED algorithm, but the seed-scramble details aren't
/// published, so the stream is reproducible and uniform-distributed yet may not
/// bit-match SAS's exact sequence. seed≤0 (SAS: clock) → a fixed seed (deterministic).
pub fn nextUniform(ev: *eval.Evaluator, seed: f64) f64 {
    const gop = ev.lag.getOrPut(ev.stateArena(), "\x00rngstream") catch return 0.5;
    if (!gop.found_existing) {
        gop.value_ptr.* = .empty;
        const s0: i64 = if (seed > 0 and seed < 2147483647) (toInt(seed) orelse 1) else 1;
        gop.value_ptr.append(ev.stateArena(), .{ .num = @floatFromInt(s0) }) catch {}; // the shared FIFO holds Value now
    }
    const state = gop.value_ptr;
    const x: u64 = @intFromFloat(state.items[0].num);
    const nxt: u64 = (16807 * x) % 2147483647;
    state.items[0] = .{ .num = @floatFromInt(nxt) };
    return @as(f64, @floatFromInt(nxt)) / 2147483647.0;
}

// ── MT19937 (Mersenne-Twister) for RAND / CALL STREAMINIT ────────────────────
// SAS's RAND uses MT19937 (init_by_array seeding + genrand_res53), so a seeded
// RAND stream reproduces SAS bit-for-bit (streaminit(1) -> 0.13436424…, the
// value SAS and reference MT19937 emit). RANUNI-family keeps the Lehmer
// nextUniform above.
// ponytail: the 624-word state is (de)serialised through the shared lag Value
//   FIFO each draw — fine at validation scale; lift to an Evaluator field only
//   if a step draws enough randoms for the copy to dominate.
const MT_N = 624;
const MT_M = 397;

fn mtSeed(mt: *[MT_N]u32, key: u32) void {
    mt[0] = 19650218;
    var i: usize = 1;
    while (i < MT_N) : (i += 1)
        mt[i] = 1812433253 *% (mt[i - 1] ^ (mt[i - 1] >> 30)) +% @as(u32, @intCast(i));
    // init_by_array, single-word key [key] (key_length 1 -> j stays 0)
    var ii: usize = 1;
    var k: usize = MT_N;
    while (k > 0) : (k -= 1) {
        mt[ii] = (mt[ii] ^ ((mt[ii - 1] ^ (mt[ii - 1] >> 30)) *% 1664525)) +% key;
        ii += 1;
        if (ii >= MT_N) { mt[0] = mt[MT_N - 1]; ii = 1; }
    }
    k = MT_N - 1;
    while (k > 0) : (k -= 1) {
        mt[ii] = (mt[ii] ^ ((mt[ii - 1] ^ (mt[ii - 1] >> 30)) *% 1566083941)) -% @as(u32, @intCast(ii));
        ii += 1;
        if (ii >= MT_N) { mt[0] = mt[MT_N - 1]; ii = 1; }
    }
    mt[0] = 0x80000000;
}

fn mtNext(mt: *[MT_N]u32, mti: *usize) u32 {
    if (mti.* >= MT_N) {
        var kk: usize = 0;
        while (kk < MT_N - MT_M) : (kk += 1) {
            const y = (mt[kk] & 0x80000000) | (mt[kk + 1] & 0x7fffffff);
            mt[kk] = mt[kk + MT_M] ^ (y >> 1) ^ (if (y & 1 != 0) @as(u32, 0x9908b0df) else 0);
        }
        while (kk < MT_N - 1) : (kk += 1) {
            const y = (mt[kk] & 0x80000000) | (mt[kk + 1] & 0x7fffffff);
            mt[kk] = mt[kk + MT_M - MT_N] ^ (y >> 1) ^ (if (y & 1 != 0) @as(u32, 0x9908b0df) else 0);
        }
        const y = (mt[MT_N - 1] & 0x80000000) | (mt[0] & 0x7fffffff);
        mt[MT_N - 1] = mt[MT_M - 1] ^ (y >> 1) ^ (if (y & 1 != 0) @as(u32, 0x9908b0df) else 0);
        mti.* = 0;
    }
    var y = mt[mti.*];
    mti.* += 1;
    y ^= y >> 11;
    y ^= (y << 7) & 0x9d2c5680;
    y ^= (y << 15) & 0xefc60000;
    y ^= y >> 18;
    return y;
}

/// One U(0,1) draw from the MT19937 stream seeded by CALL STREAMINIT (genrand_res53).
pub fn nextRandUniform(ev: *eval.Evaluator) f64 {
    var seed: u32 = 1; // no STREAMINIT -> deterministic default (SAS uses a clock seed)
    if (ev.lag.get("\x00rnginit")) |iv| {
        if (iv.items.len > 0 and iv.items[0].num > 0) {
            seed = @intFromFloat(@min(iv.items[0].num, 4294967295.0));
        }
    }
    const gop = ev.lag.getOrPut(ev.stateArena(), "\x00mtstream") catch return 0.5;
    const st = gop.value_ptr;
    var mt: [MT_N]u32 = undefined;
    var mti: usize = MT_N;
    const fresh = !gop.found_existing or st.items.len < MT_N + 2 or
        @as(u32, @intFromFloat(st.items[0].num)) != seed;
    if (fresh) {
        mtSeed(&mt, seed);
        st.* = .empty;
        st.append(ev.stateArena(), .{ .num = @floatFromInt(seed) }) catch return 0.5;
        st.append(ev.stateArena(), .{ .num = @floatFromInt(mti) }) catch return 0.5;
        for (mt) |w| st.append(ev.stateArena(), .{ .num = @floatFromInt(w) }) catch return 0.5;
    } else {
        mti = @intFromFloat(st.items[1].num);
        for (&mt, 0..) |*w, i| w.* = @intFromFloat(st.items[2 + i].num);
    }
    const a = mtNext(&mt, &mti) >> 5;
    const b = mtNext(&mt, &mti) >> 6;
    st.items[1] = .{ .num = @floatFromInt(mti) };
    for (mt, 0..) |w, i| st.items[2 + i] = .{ .num = @floatFromInt(w) };
    return (@as(f64, @floatFromInt(a)) * 67108864.0 + @as(f64, @floatFromInt(b))) / 9007199254740992.0;
}

/// Uniform draw for a variate generator: MT19937 for RAND, Lehmer for RANUNI-family.
inline fn randU(ev: *eval.Evaluator, seed: f64, mt: bool) f64 {
    return if (mt) nextRandUniform(ev) else nextUniform(ev, seed);
}

/// One standard-normal draw (Box-Muller). `mt` selects the RAND MT19937 stream
/// over the RANUNI Lehmer stream.
pub fn drawNormal(ev: *eval.Evaluator, seed: f64, mt: bool) f64 {
    return @sqrt(-2.0 * @log(randU(ev, seed, mt))) * @cos(2.0 * std.math.pi * randU(ev, seed, mt));
}

/// One Gamma(shape a, scale 1) draw (Marsaglia–Tsang) from the shared stream.
pub fn drawGamma(ev: *eval.Evaluator, seed: f64, mt: bool, a: f64) f64 {
    var boost: f64 = 1;
    var aa = a;
    if (a < 1) {
        boost = std.math.pow(f64, randU(ev, seed, mt), 1.0 / a);
        aa = a + 1;
    }
    const d = aa - 1.0 / 3.0;
    const c = 1.0 / @sqrt(9.0 * d);
    while (true) {
        const z = drawNormal(ev, seed, mt);
        const v3 = 1.0 + c * z;
        if (v3 <= 0) continue;
        const v = v3 * v3 * v3;
        if (@log(randU(ev, seed, mt)) < 0.5 * z * z + d - d * v + d * @log(v)) return d * v * boost;
    }
}

fn lagFifo(ev: *eval.Evaluator, name: []const u8, n: usize, v: Value) Value {
    const key = std.fmt.allocPrint(ev.stateArena(), "{x}", .{@intFromPtr(name.ptr)}) catch return Value.missing;
    const gop = ev.lag.getOrPut(ev.stateArena(), key) catch return Value.missing;
    if (!gop.found_existing) gop.value_ptr.* = .empty;
    const fifo = gop.value_ptr;
    // Before the queue fills (the first n obs) there is no prior value: a CHARACTER
    // lag yields blank, a numeric lag yields numeric missing '.' (BUG-lagcharfirst).
    const result: Value = if (fifo.items.len >= n) fifo.items[0] else switch (v) {
        .str => .{ .str = "" },
        .num => Value.missing,
    };
    // Dupe a char value into the STATE arena — the PDV cell it came from is
    // overwritten each iteration (and may point into the per-row scratch,
    // BUG-datastepoom), so the FIFO must own its bytes to hand them back later.
    const stored: Value = switch (v) {
        .str => |s| .{ .str = ev.stateArena().dupe(u8, s) catch s },
        .num => v,
    };
    fifo.append(ev.stateArena(), stored) catch {};
    if (fifo.items.len > n) _ = fifo.orderedRemove(0);
    return result;
}

/// Evaluator of the in-flight `dispatch`, stashed so the leaf coercion helper
/// `toNum` can emit the SAS implicit-conversion NOTE without threading `ev`
/// through its 200+ call sites across six function files (numfns/charfns/… all
/// share `fns.toNum` and most lack an `ev` param). Set at every `dispatch`
/// entry; single-threaded, so it's always the current call's evaluator.
/// ponytail: module-global for a cross-file leaf — thread `ev` into toNum only
/// if these files ever run concurrently.
var conv_ev: ?*eval.Evaluator = null;

/// SAS char→num: trimmed empty or unparseable → missing (NaN). Every non-blank
/// implicit conversion logs the SAS NOTE (GH#74b), matching eval.zig's `toNum`
/// and pdv.zig's char→num assignment note — unparsable text adds the paired
/// "Invalid numeric data" note. Blank (→ missing) is silent, as in eval.zig.
pub fn toNum(v: Value) f64 {
    return switch (v) {
        .num => |x| x,
        .str => |s| blk: {
            const tr = std.mem.trim(u8, s, " ");
            if (tr.len == 0) break :blk std.math.nan(f64);
            if (conv_ev) |e|
                e.diags.note(0, "Character values have been converted to numeric values at the places given by: (Line):(Column).", .{}) catch {};
            break :blk pdv_mod.sasParseFloat(tr) orelse {
                // NOTE-invalidnumdataloc (GH#78): no "at line N column M" tail —
                // this leaf sees only the Value; the borrowed evaluator has no
                // current line and AST expressions carry no source span, so the
                // only printable position was a frozen 0/0 literal. Omitted, not
                // frozen — same wording as eval.zig's and pdv.zig's notes.
                if (conv_ev) |e|
                    e.diags.note(0, "Invalid numeric data, '{s}'.", .{s}) catch {};
                break :blk std.math.nan(f64);
            };
        },
    };
}

/// SAS AUTOMATIC num→char conversion for a character-expecting argument:
/// BEST12. RIGHT-JUSTIFIED in a 12-wide field (Language Reference: Concepts p.124, BUG-numcharwidth) —
/// so `length(n)` is 12 and `substr(n,1,3)` is blanks, exactly as SAS does.
/// Borrows a char slice as-is. Explicit conversions don't come here (PUT routes
/// through format.apply/bestFmt; the CAT family uses catStr's compact BEST12).
pub fn toStr(ev: *eval.Evaluator, v: Value) eval.Error![]const u8 {
    return switch (v) {
        .str => |s| s,
        .num => |x| blk: {
            // SAS logs a NOTE on every implicit num→char conversion (GH#74b) —
            // this is the path a declared-length `c = n` takes (parser wraps it
            // as `substr(n,1,len)`, whose first arg coerces here).
            ev.diags.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{}) catch {};
            // missings keep their `.`/`.A`-`.Z`/`._` letter, padded
            // (ISS-specialmiss-tochar, via bestNumW inside numToChar).
            break :blk try pdv_mod.numToChar(ev.arena, x, 12);
        },
    };
}

/// The format/informat SPEC argument of PUT()/PUTN()/PUTC() and INPUT()/INPUTN()/
/// INPUTC(). A bare-numeric spelling (`put(x, 8.2)`, `input(c, 8.)`) reaches us as a
/// `.num` and must be coerced SILENTLY: the spec is a format, not data, so toStr's
/// implicit num→char NOTE is a FALSE POSITIVE — and it fires on the very functions
/// whose purpose is an explicit conversion. Same BEST12 coercion toStr does, minus
/// the note, trimmed because both engines want the bare spec text.
/// BUG-putbarenumnote fixed this inline for PUT only; INPUT/INPUTN/INPUTC were left
/// on toStr and still logged the bogus NOTE (QA tick356 F4) — one helper, both
/// callers, instead of a second copy. Only the SPEC coerces silently: the DATA
/// argument keeps toStr, so a genuinely implicit `input(123, 8.)` still notes.
fn specText(ev: *eval.Evaluator, v: Value) eval.Error![]const u8 {
    return std.mem.trim(u8, switch (v) {
        .str => |s| s,
        .num => |x| try pdv_mod.numToChar(ev.arena, x, 12),
    }, " ");
}

/// Render a CAT-family argument: a numeric goes through SAS BEST12 (dev3's central
/// `format.bestNum`, left-aligned/compact — so 1/3 → "0.3333333333", not the raw
/// f64), a char passes through verbatim. BUG-catbest: cat/cats/catt/catx must NOT
/// use the raw `{d}` form `toStr` gives. BUG-catnote: and must NOT log the
/// num→char NOTE — SAS 9.4 "CAT Function" (p.453-455): BESTw., leading blanks
/// removed, "SAS does not write a note to the log". Non-CAT callers that DO note
/// (vvalue/vvaluex/catq) emit it at their own call sites.
pub fn catStr(ev: *eval.Evaluator, v: Value) eval.Error![]const u8 {
    return switch (v) {
        .str => |s| s,
        .num => |x| try format.bestNum(ev.arena, x),
    };
}

pub fn badArity(ev: *eval.Evaluator, name: []const u8, expected: []const u8, got: usize) Value {
    note(ev, "{s}() expects {s} argument(s), got {d}", .{ name, expected, got });
    return Value.missing;
}

/// A PRX regex handle: a numeric id from PRXPARSE, or a literal pattern compiled
/// on the fly. Null when a string pattern fails to compile.
fn prxId(v: Value) ?u32 {
    return switch (v) {
        .num => |x| if (isMiss(x) or x < 1) null else @intFromFloat(@trunc(x)),
        .str => |s| prx.parse(s),
    };
}

// ── date/time internals ──────────────────────────────────────────────────────
// The civil↔serial conversion is Howard Hinnant's `days_from_civil`, adapted to
// floor division. It yields days since the Unix epoch (1970-01-01); we shift by
// `sas_epoch_days` so day 0 is SAS's 1960-01-01.

/// 1970-01-01 expressed as a SAS date. 1960→1970 spans 3653 days (10y, 3 leaps).
pub const sas_epoch_days: i64 = 3653;

pub const Civil = struct { y: i64, m: i64, d: i64 };

/// (year, month, day) → days since 1970-01-01. `m`/`d` assumed already in range.
pub fn daysFromCivil(y: i64, m: i64, d: i64) i64 {
    const yy = y - @as(i64, @intFromBool(m <= 2)); // Jan/Feb belong to the prior year
    const era = @divFloor(yy, 400);
    const yoe = yy - era * 400; // [0, 399]
    const mp = @mod(m + 9, 12); // Mar=0 … Feb=11
    const doy = @divFloor(153 * mp + 2, 5) + d - 1; // [0, 365]
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

fn monWeekday(wd: i64) i64 { // Sun=1..Sat=7  →  Mon=1..Sun=7
    return if (wd == 1) 7 else wd - 1;
}

fn isoHas53(y: i64) bool {
    const jan1 = daysFromCivil(y, 1, 1) + sas_epoch_days;
    const wmon = monWeekday(weekdayOf(jan1));
    const leap = (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
    return wmon == 4 or (leap and wmon == 3); // Jan 1 is Thursday, or leap-year Wednesday
}

/// WEEK(date, descriptor): U (Sunday-first, 0–53, default), W (Monday-first, 0–53),
/// V (ISO 8601, 1–53). See SAS 9.4 Functions Ref, WEEK Function.
pub fn weekNumber(d: i64, desc: u8) i64 {
    const c = civilFromSas(d);
    const doy = d - (daysFromCivil(c.y, 1, 1) + sas_epoch_days) + 1; // day of year, 1-based
    const wd = weekdayOf(d); // Sun=1..Sat=7
    return switch (desc) {
        'W' => @divFloor(doy + 7 - monWeekday(wd), 7),
        'V' => blk: {
            const w = @divFloor(doy - monWeekday(wd) + 10, 7);
            if (w < 1) break :blk if (isoHas53(c.y - 1)) 53 else 52;
            if (w > 52 and !isoHas53(c.y)) break :blk 1;
            break :blk w;
        },
        else => @divFloor(doy + 6 - wd, 7), // U (default)
    };
}

// ── informats: char → value (the `input(x, informat.)` conversion) ───────────

/// Convert `s` under informat `spec` (e.g. "date9.", "yymmdd10.", "comma8.").
/// Dates yield a SAS day number; COMMA/DOLLAR strip separators; everything else
/// parses as a plain number. Unparseable input → missing.
pub fn readInformat(spec: []const u8, s: []const u8) Value {
    // A `$` (dollar) informat reads the source as a CHARACTER value: `input("abc",
    // $8.)` → "abc" (clipped to the width w). Without this it fell through to the
    // numeric path and returned missing for non-numeric text (BUG-putcharfmt).
    if (spec.len > 0 and spec[0] == '$') {
        const w = informatWD(spec).w;
        const clipped = if (w > 0 and w < s.len) s[0..w] else s;
        // Plain `$w.` (no name): SAS strips leading blanks and reads a field
        // that is a LONE '.' as the char missing value — gen2 VSSTRESC's
        // `input(<numeric missing>, $40.)` must yield "", not "." (the implicit
        // num→char conversion writes "           ." first; QA-dollarwdot).
        // Named forms ($CHARw. etc.) keep the field verbatim per SAS.
        if (informatName(spec).len == 0) {
            const t2 = std.mem.trimStart(u8, clipped, " ");
            if (std.mem.eql(u8, std.mem.trimEnd(u8, t2, " "), ".")) return .{ .str = "" };
            return .{ .str = t2 };
        }
        return .{ .str = clipped };
    }
    const nm = informatName(spec);
    if (eqi(nm, "date")) return dateFromDDMMMYYYY(s);
    if (eqi(nm, "yymmdd")) return dateFromYMD(s);
    if (eqi(nm, "mmddyy")) return dateFromParts(s, .mdy);
    if (eqi(nm, "ddmmyy")) return dateFromParts(s, .dmy);
    // BUG-datetimeinputfn: datetime / ISO-8601 / time informats parse to SAS
    // datetime/time seconds. format.readNumeric already implements these (the same
    // path the INPUT statement uses), so the INPUT() function routes through it to
    // match — the digit-bearing names (E8601DT.) need the raw spec, not `nm`.
    const bare = if (spec.len > 0 and spec[0] == '$') spec[1..] else spec;
    const sw = std.ascii.startsWithIgnoreCase;
    // ISS-e8601dainf: ISO-8601 DATE informats (extended `e8601da`, basic `b8601da`)
    // read yyyy-mm-dd / yyyymmdd → a SAS day number. Digit-bearing names, so match
    // the raw spec (informatName stops at "e"); dateFromYMD handles both separators.
    if (sw(bare, "e8601da") or sw(bare, "b8601da")) return dateFromYMD(s);
    // BUG-percentinputfn: PERCENTw. must strip `%` and divide by 100 — readNumeric
    // does both; numFromSpec below only strips comma/dollar, so route percent here.
    if (sw(bare, "datetime") or sw(bare, "e8601dt") or sw(bare, "b8601dt") or
        sw(bare, "e8601tm") or sw(bare, "b8601tm") or eqi(nm, "time") or eqi(nm, "hhmmss") or eqi(nm, "percent") or
        eqi(nm, "monyy") or eqi(nm, "yyq") or eqi(nm, "yyqc") or // MONYY/YYQ: read-side date informats
        eqi(nm, "julian") or // JULIANw.: readNumeric has the parser (BUG-julianinputfn)
        // TODw.: same one-line shape as JULIAN above — the STATEMENT read was fixed
        // (BUG-todinformat) while this chain still fell through to numFromSpec, so
        // `input("10:30:00", tod8.)` returned missing where `input a tod8.;` read
        // 37800 (BUG-todinputfn). tod was the LAST name in format.isKnownInformat
        // with no route here; the two informat entry points now agree name-for-name.
        eqi(nm, "tod") or
        // HEXw./OCTALw. (GAP-hexinformat/octalinformat): the digit parse lives in
        // readNumeric too — routing here replaces the old error-then-decimal
        // fallback (`octal8.` on '377' printed 377 after the ERROR).
        eqi(nm, "hex") or eqi(nm, "octal") or
        // GAP-anydtinformat: ANYDTDTE/DTM/TME auto-detect the date/datetime/time
        // layout — that try-each-parser logic lives in readNumeric. Without this the
        // fn path fell through to numFromSpec (silent missing) once format whitelisted
        // the names — a fail-loud regression on the INPUT() function path.
        eqi(nm, "anydtdte") or eqi(nm, "anydtdtm") or eqi(nm, "anydttme") or
        // BUG-commaxinformat: COMMAX/DOLLARX European `,`/`.` roles (and NLNUM's
        // comma grouping) live in readNumeric; numFromSpec only strips US commas,
        // so the -x variants / nlnum came back missing here. NUMXw.d likewise
        // (BUG-numxinformat).
        eqi(nm, "commax") or eqi(nm, "dollarx") or eqi(nm, "nlnum") or eqi(nm, "numx") or
        // plain w.d / F / BZ: blank handling is informat-specific and lives in
        // readNumeric — BZw.d blanks→ZEROS, plain w.d embedded blank→missing+NOTE
        // (BUG-bzinformat / BUG-numembeddedblank). numFromSpec drops all blanks.
        // Z/BEST/E/D are w.d aliases → the SAME embedded-blank rule (NOTE-
        // informatlow-tick245 #9); COMMA/DOLLAR gain readNumeric's interior-hyphen
        // removal (#13) — numFromSpec below has neither rule.
        nm.len == 0 or eqi(nm, "f") or eqi(nm, "bz") or
        eqi(nm, "z") or eqi(nm, "best") or eqi(nm, "e") or eqi(nm, "d") or
        eqi(nm, "comma") or eqi(nm, "dollar"))
        return format.readNumeric(spec, s);
    // An unimplemented/unknown informat must FAIL LOUD, not silently read missing
    // (BUG-informatreadloud) — twin of the write-side unknown-format error.
    if (!format.isKnownInformat(nm)) format.informatNotFound(nm, false);
    const wd = informatWD(spec);
    return numFromSpec(s, wd.w, wd.d);
}

/// The width and implied-decimals of an informat: "5.2" → {5, 2}, "12." → {12, 0}.
const InfWD = struct { w: usize, d: usize };
fn informatWD(spec: []const u8) InfWD {
    var i: usize = 0;
    if (i < spec.len and spec[i] == '$') i += 1;
    while (i < spec.len and std.ascii.isAlphabetic(spec[i])) i += 1; // skip the name
    const ws = i;
    while (i < spec.len and std.ascii.isDigit(spec[i])) i += 1;
    const w = std.fmt.parseInt(usize, spec[ws..i], 10) catch 0;
    var d: usize = 0;
    if (i < spec.len and spec[i] == '.') {
        i += 1;
        const ds = i;
        while (i < spec.len and std.ascii.isDigit(spec[i])) i += 1;
        d = std.fmt.parseInt(usize, spec[ds..i], 10) catch 0;
    }
    return .{ .w = w, .d = d };
}

/// The alphabetic informat name (after an optional `$`): "date9." → "date".
fn informatName(spec: []const u8) []const u8 {
    var i: usize = 0;
    if (i < spec.len and spec[i] == '$') i += 1;
    const start = i;
    while (i < spec.len and std.ascii.isAlphabetic(spec[i])) i += 1;
    return spec[start..i];
}

fn monthAbbr(abbr: []const u8) ?i64 {
    const names = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
    for (names, 0..) |m, i| if (eqi(abbr, m)) return @intCast(i + 1);
    return null;
}

/// `ddMMMyyyy` (e.g. `15JAN1960`; day 1–2 digits). Hyphens, slashes and blanks
/// between the parts are separators, not data: `15-MAR-2020` via DATE11.
/// (GAP-date11informat), `16 mar 2012` (BUG-dateblanksep).
fn dateFromDDMMMYYYY(s0: []const u8) Value {
    const s = std.mem.trim(u8, s0, " ");
    var buf: [32]u8 = undefined;
    var p = s;
    if (std.mem.indexOfAny(u8, s, "-/ ") != null) { // separated → strip, then packed read
        var n: usize = 0;
        for (s) |c| {
            if (c == '-' or c == '/' or c == ' ') continue;
            if (n >= buf.len) return Value.missing;
            buf[n] = c;
            n += 1;
        }
        p = buf[0..n];
    }
    if (p.len < 6) return Value.missing;
    // The packed ddMMMyyyy read (incl. the 1–2-digit day) lives in ONE place —
    // format.parseDDMMMYYYY — so the INPUT() function and the informat paths
    // can't disagree (BUG-datesingledigitday; the duplicated day slice fixed
    // in one copy only is how this class kept re-firing).
    return if (format.parseDDMMMYYYY(p)) |dn| numVal(@floatFromInt(dn)) else Value.missing;
}

/// `yyyy-mm-dd` / `yyyy/mm/dd` / `yyyymmdd` (year first).
fn dateFromYMD(s: []const u8) Value {
    var buf: [3]i64 = undefined;
    const n = digitGroups(s, &buf);
    if (n == 3) return dateFrom(applyCutoff(buf[0]), buf[1], buf[2]);
    if (n == 1) { // packed yyyymmdd / yymmdd
        const tr = std.mem.trim(u8, s, " ");
        if (tr.len == 8) return dateFrom(intOf(tr[0..4]), intOf(tr[4..6]), intOf(tr[6..8]));
        if (tr.len == 6) return dateFrom(applyCutoff(intOf(tr[0..2])), intOf(tr[2..4]), intOf(tr[4..6]));
    }
    return Value.missing;
}

const DateOrder = enum { mdy, dmy };
fn dateFromParts(s: []const u8, order: DateOrder) Value {
    var buf: [3]i64 = undefined;
    const n = digitGroups(s, &buf);
    if (n == 3) return switch (order) {
        .mdy => dateFrom(applyCutoff(buf[2]), buf[0], buf[1]),
        .dmy => dateFrom(applyCutoff(buf[2]), buf[1], buf[0]),
    };
    // packed digit-only form (`150312` under DDMMYY6. → 15MAR2012) — the same
    // branch dateFromYMD has and the INPUT statement applies (BUG-ddmmyyfnpacked).
    if (n == 1) {
        const tr = std.mem.trim(u8, s, " ");
        if (tr.len != 6 and tr.len != 8) return Value.missing;
        const yw: usize = if (tr.len == 8) 4 else 2; // year field width
        const a = intOf(tr[0..2]);
        const b = intOf(tr[2..4]);
        const y = intOf(tr[4 .. 4 + yw]);
        return switch (order) {
            .mdy => dateFrom(applyCutoff(y), a, b),
            .dmy => dateFrom(applyCutoff(y), b, a),
        };
    }
    return Value.missing;
}

fn dateFrom(y: i64, m: i64, d: i64) Value {
    if (m < 1 or m > 12 or d < 1 or d > 31) return Value.missing;
    const n = sasDate(y, m, d);
    const c = civilFromSas(n); // reject an invalid day that rolled over (e.g. 31FEB → Mar 2)
    if (c.y != y or c.m != m or c.d != d) return Value.missing;
    return numVal(@floatFromInt(n));
}

/// A 2-digit year → full year via the shared YEARCUTOFF (default 1926, OPTIONS-aware).
fn applyCutoff(y: i64) i64 {
    return format.expandYear(y);
}

fn intOf(s: []const u8) i64 {
    return std.fmt.parseInt(i64, s, 10) catch 0;
}

/// Fill `out` with the leading numeric groups of `s` (split on any non-digit);
/// returns how many were found (capped at out.len).
fn digitGroups(s: []const u8, out: []i64) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < s.len and n < out.len) {
        if (!std.ascii.isDigit(s[i])) {
            i += 1;
            continue;
        }
        const start = i;
        while (i < s.len and std.ascii.isDigit(s[i])) i += 1;
        out[n] = intOf(s[start..i]);
        n += 1;
    }
    return n;
}

/// Read a numeric field under a `w.d` informat: honour the width (only the first
/// `w` bytes are read), strip `,`/`$` for COMMA/DOLLAR, apply the implied `d`
/// decimals when the source has no explicit point, and collapse overflow (a
/// non-finite parse, e.g. 1e400) to missing.
fn numFromSpec(s0: []const u8, w: usize, d: usize) Value {
    const s = if (w > 0 and w < s0.len) s0[0..w] else s0;
    var buf: [64]u8 = undefined;
    var n: usize = 0;
    var has_dot = false;
    for (s) |c| {
        if (c == ' ') continue;
        if (c == '.') has_dot = true;
        if (n < buf.len) {
            buf[n] = c;
            n += 1;
        }
    }
    if (n == 0) return Value.missing;
    if (Value.parseSpecialMissing(buf[0..n])) |sm| return sm; // .A–.Z, ._ (ISS-specialmissing)
    var x = pdv_mod.sasParseFloat(buf[0..n]) orelse return Value.missing;
    if (!has_dot and d > 0) { // implied decimals: `input("1234", 5.2)` → 12.34
        var p: f64 = 1;
        for (0..d) |_| p *= 10;
        x /= p;
    }
    if (!std.math.isFinite(x)) return Value.missing; // overflow → missing
    return numVal(x);
}

/// days since 1970-01-01 → (year, month, day).
fn civilFromDays(z0: i64) Civil {
    const z = z0 + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097; // [0, 146096]
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    const y = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100)); // [0, 365]
    const mp = @divFloor(5 * doy + 2, 153); // [0, 11]
    const d = doy - @divFloor(153 * mp + 2, 5) + 1; // [1, 31]
    const m = if (mp < 10) mp + 3 else mp - 9; // [1, 12]
    return .{ .y = y + @as(i64, @intFromBool(m <= 2)), .m = m, .d = d };
}

pub fn sasDate(y: i64, m: i64, d: i64) i64 {
    return daysFromCivil(y, m, d) + sas_epoch_days;
}
pub fn civilFromSas(n: i64) Civil {
    return civilFromDays(n - sas_epoch_days);
}

/// The interval spanning two dates as (base, multiple): whole months on the same
/// day-of-month → MONTH/YEAR; otherwise DAY. For INTGET/INTFIT. ponytail: no
/// WEEK/SEMIMONTH detection (those fall through to DAY).
pub const Ivl = struct { base: []const u8, mult: i64 };
pub fn intervalBetween(d1: i64, d2: i64) Ivl {
    const days = d2 - d1;
    const c1 = civilFromSas(d1);
    const c2 = civilFromSas(d2);
    if (c1.d == c2.d) { // same day-of-month → possibly month/year aligned
        const months = (c2.y - c1.y) * 12 + (c2.m - c1.m);
        if (months != 0) {
            if (@rem(months, 12) == 0) return .{ .base = "YEAR", .mult = @divTrunc(months, 12) };
            return .{ .base = "MONTH", .mult = months };
        }
    }
    return .{ .base = "DAY", .mult = days };
}

pub fn fmtIvl(ev: *eval.Evaluator, iv: Ivl) ![]const u8 {
    return std.fmt.allocPrint(ev.arena, "{s}{d}", .{ iv.base, iv.mult });
}

/// Months in a month-based interval base (for INTCK CONTINUOUS anniversaries), else
/// null (day/week/time intervals don't use a calendar month-shift).
pub fn baseMonths(base: []const u8) ?i64 {
    if (eqi(base, "YEAR")) return 12;
    if (eqi(base, "SEMIYEAR")) return 6;
    if (eqi(base, "QTR")) return 3;
    if (eqi(base, "MONTH")) return 1;
    return null;
}

/// Calendar month-shift preserving day-of-month (clamped to the target month's
/// length): BUG-intckcontyear — the continuous anniversary of `date` is the same
/// month/day, not the same day-of-year (which INTNX SAME uses).
pub fn addMonthsCal(date: i64, months: i64) i64 {
    const c = civilFromSas(date);
    const total = c.y * 12 + (c.m - 1) + months;
    const ny = @divFloor(total, 12);
    const nm = @mod(total, 12) + 1;
    const nd = @min(c.d, daysInMonth(ny, nm));
    return sasDate(ny, nm, nd);
}

/// SAS date of the nth weekday `wd` (1=Sun..7=Sat) in month `mo`/`yr`; n=5 → last.
fn nthWeekday(n: i64, wd: i64, mo: i64, yr: i64) i64 {
    const first = sasDate(yr, mo, 1);
    const offset = @mod(wd - weekdayOf(first) + 7, 7); // days from the 1st to the first `wd`
    var day = 1 + offset + (n - 1) * 7;
    if (day > daysInMonth(yr, mo)) day -= 7; // n=5 overshoots → last occurrence
    return first + day - 1;
}

/// Easter Sunday for `yr` (Anonymous Gregorian / computus algorithm) as a SAS date.
fn easterDate(yr: i64) i64 {
    const a = @mod(yr, 19);
    const b = @divFloor(yr, 100);
    const c = @mod(yr, 100);
    const d = @divFloor(b, 4);
    const ee = @mod(b, 4);
    const f = @divFloor(b + 8, 25);
    const g = @divFloor(b - f + 1, 3);
    const hh = @mod(19 * a + b - d - g + 15, 30);
    const ii = @divFloor(c, 4);
    const k = @mod(c, 4);
    const l = @mod(32 + 2 * ee + 2 * ii - hh - k, 7);
    const m = @divFloor(a + 11 * hh + 22 * l, 451);
    const month = @divFloor(hh + l - 7 * m + 114, 31);
    const day = @mod(hh + l - 7 * m + 114, 31) + 1;
    return sasDate(yr, month, day);
}

/// SAS named holidays. `kind` selects the date rule; a/b/c carry its parameters
/// (fixed: month,day · nth: n,weekday,month). ponytail: the common US/Canada set,
/// no locale/"observed"/floating variants.
const HKind = enum { fixed, nth, easter, victoria };
pub const Holiday = struct { name: []const u8, kind: HKind, a: i64 = 0, b: i64 = 0, c: i64 = 0 };
pub const holidays = [_]Holiday{
    .{ .name = "NEWYEAR", .kind = .fixed, .a = 1, .b = 1 },
    .{ .name = "VALENTINES", .kind = .fixed, .a = 2, .b = 14 },
    .{ .name = "CANADA", .kind = .fixed, .a = 7, .b = 1 },
    .{ .name = "USINDEPENDENCE", .kind = .fixed, .a = 7, .b = 4 },
    .{ .name = "JUNETEENTH", .kind = .fixed, .a = 6, .b = 19 },
    .{ .name = "HALLOWEEN", .kind = .fixed, .a = 10, .b = 31 },
    .{ .name = "VETERANS", .kind = .fixed, .a = 11, .b = 11 },
    .{ .name = "CHRISTMAS", .kind = .fixed, .a = 12, .b = 25 },
    .{ .name = "BOXING", .kind = .fixed, .a = 12, .b = 26 },
    .{ .name = "MLK", .kind = .nth, .a = 3, .b = 2, .c = 1 }, // 3rd Mon Jan
    .{ .name = "USPRESIDENTS", .kind = .nth, .a = 3, .b = 2, .c = 2 }, // 3rd Mon Feb
    .{ .name = "MEMORIAL", .kind = .nth, .a = 5, .b = 2, .c = 5 }, // last Mon May
    .{ .name = "MOTHERS", .kind = .nth, .a = 2, .b = 1, .c = 5 }, // 2nd Sun May
    .{ .name = "FATHERS", .kind = .nth, .a = 3, .b = 1, .c = 6 }, // 3rd Sun Jun
    .{ .name = "LABOR", .kind = .nth, .a = 1, .b = 2, .c = 9 }, // 1st Mon Sep
    .{ .name = "COLUMBUS", .kind = .nth, .a = 2, .b = 2, .c = 10 }, // 2nd Mon Oct
    .{ .name = "THANKSGIVING", .kind = .nth, .a = 4, .b = 5, .c = 11 }, // 4th Thu Nov
    .{ .name = "EASTER", .kind = .easter },
    .{ .name = "VICTORIA", .kind = .victoria }, // Monday on/before May 24 (Canada)
};

/// RESOLVE: substitute `&macro-var` references in `text` with their values from
/// the bound macro store. `&&` → `&`; an unknown `&name` is left as-is; a trailing
/// `.` after a name is the delimiter and is consumed. ponytail: no `%macro` calls.
fn resolveMacros(ev: *eval.Evaluator, text: []const u8) eval.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '&' and i + 1 < text.len) {
            if (text[i + 1] == '&') { // && → a literal &
                try out.append(ev.arena, '&');
                i += 2;
                continue;
            }
            var j = i + 1;
            while (j < text.len and (std.ascii.isAlphanumeric(text[j]) or text[j] == '_')) j += 1;
            if (j > i + 1) {
                const nm = text[i + 1 .. j];
                if (macroVarValue(nm)) |v| try out.appendSlice(ev.arena, v) else try out.appendSlice(ev.arena, text[i..j]);
                i = if (j < text.len and text[j] == '.') j + 1 else j; // consume the . delimiter
                continue;
            }
        }
        try out.append(ev.arena, text[i]);
        i += 1;
    }
    return out.items;
}

/// The alphabetic base of a format/informat name (uppercased, keeping a leading
/// `$`): `best12.` → `BEST`, `$char20.` → `$CHAR`, `dollar8.2` → `DOLLAR`.
pub fn fmtBase(s: []const u8, buf: []u8) []const u8 {
    const txt = std.mem.trim(u8, s, " ");
    var n: usize = 0;
    var i: usize = 0;
    if (i < txt.len and txt[i] == '$') {
        buf[0] = '$';
        n = 1;
        i = 1;
    }
    while (i < txt.len and std.ascii.isAlphabetic(txt[i]) and n < buf.len) : (i += 1) {
        buf[n] = std.ascii.toUpper(txt[i]);
        n += 1;
    }
    return buf[0..n];
}

/// FMTINFO CAT: the format category ("num"/"char"/"curr"/"date"/"time"/
/// "datetime") for the common formats; null for one we don't classify.
pub fn fmtCat(base: []const u8) ?[]const u8 {
    if (base.len == 0) return null;
    if (base[0] == '$') return "char";
    inline for (.{ "DOLLAR", "DOLLARX", "EURO", "EUROX", "YEN" }) |c| if (eqi(base, c)) return "curr";
    inline for (.{ "DATETIME", "DATEAMPM" }) |c| if (eqi(base, c)) return "datetime";
    inline for (.{ "TIME", "HHMM", "HOUR", "MMSS", "TOD", "TIMEAMPM" }) |c| if (eqi(base, c)) return "time";
    inline for (.{ "DATE", "DAY", "DDMMYY", "MMDDYY", "YYMMDD", "MONYY", "MONTH", "YEAR", "QTR", "WEEKDATE", "WORDDATE", "WORDDATX", "JULIAN", "JULDAY", "DOWNAME", "MONNAME", "YYMON" }) |c| if (eqi(base, c)) return "date";
    inline for (.{ "BEST", "BESTD", "COMMA", "COMMAX", "F", "Z", "PERCENT", "PERCENTN", "E", "HEX", "BINARY", "OCTAL", "NEGPAREN", "FRACT", "ROMAN", "WORDS", "ORDINAL", "SSN", "ZD", "NUMX" }) |c| if (eqi(base, c)) return "num";
    return null;
}

pub fn holidayDate(name: []const u8, yr: i64) ?i64 {
    const n = std.mem.trim(u8, name, " ");
    for (holidays) |hol| {
        if (!eqi(n, hol.name)) continue;
        return switch (hol.kind) {
            .fixed => sasDate(yr, hol.a, hol.b),
            .nth => nthWeekday(hol.a, hol.b, hol.c, yr),
            .easter => easterDate(yr),
            .victoria => blk: {
                const d = sasDate(yr, 5, 24);
                break :blk d - @mod(weekdayOf(d) - 2 + 7, 7); // back up to Monday (wd 2)
            },
        };
    }
    return null;
}

/// The base SAS time intervals INTTEST accepts (a leading name, optional DT prefix,
/// before any multiplier/shift). ponytail: names only — the multiplier.shift suffix
/// is stripped but not range-checked.
const interval_bases = [_][]const u8{
    "YEAR", "SEMIYEAR", "QTR", "MONTH", "SEMIMONTH", "TENDAY", "WEEK",
    "WEEKDAY", "DAY", "HOUR", "MINUTE", "SECOND", "YEARV", "WEEKV", "QTRV",
    "WEEKU", "WEEKW",
};
pub fn validInterval(spec: []const u8) bool {
    var s = std.mem.trim(u8, spec, " ");
    if (s.len == 0) return false;
    if (std.ascii.startsWithIgnoreCase(s, "DT")) s = s[2..]; // datetime variant
    var i: usize = 0;
    while (i < s.len and std.ascii.isAlphabetic(s[i])) i += 1;
    var base = s[0..i];
    // WEEKDAYnW: keep just the WEEKDAY head
    if (std.ascii.startsWithIgnoreCase(base, "WEEKDAY")) base = base[0..7];
    for (interval_bases) |b| if (std.ascii.eqlIgnoreCase(base, b)) return true;
    return false;
}

/// Split an interval spec into its base name (uppercased, DT prefix dropped),
/// multiplier, and `.shift-index` (default 1). e.g. "DTMONTH2.1" → ("MONTH", 2, 1).
pub fn parseInterval(spec: []const u8, buf: []u8) struct { base: []const u8, mult: i64, shift: i64, wkend: u8 } {
    var s = std.mem.trim(u8, spec, " ");
    if (std.ascii.startsWithIgnoreCase(s, "DT")) s = s[2..];
    // BUG-intervalcrash: cap the base at `buf` so an over-long name can't index past it.
    var i: usize = 0;
    while (i < s.len and i < buf.len and std.ascii.isAlphabetic(s[i])) : (i += 1) buf[i] = std.ascii.toUpper(s[i]);
    const base = buf[0..i];
    // multiplier: parse the digit run through parseInt, which errors (→ a huge
    // sentinel, rejected downstream) instead of overflowing i64 on a long number.
    var j = i;
    while (j < s.len and std.ascii.isDigit(s[j])) : (j += 1) {}
    var mult: i64 = 1;
    if (j > i) {
        mult = std.fmt.parseInt(i64, s[i..j], 10) catch std.math.maxInt(i64);
        if (mult <= 0) mult = 1;
    }
    // WEEKDAYdW: a digit run closed by W is a weekend spec, not a multiplier —
    // each digit '1'..'7' (Sun..Sat) marks a weekend day (BUG-intnxweekendskip).
    var wkend: u8 = 0b1000001; // default WEEKDAY: Sunday + Saturday
    if (std.mem.startsWith(u8, base, "WEEKDAY") and j < s.len and (s[j] == 'w' or s[j] == 'W')) {
        mult = 1;
        var m: u8 = 0;
        for (s[i..j]) |c| {
            if (c >= '1' and c <= '7') m |= @as(u8, 1) << @intCast(c - '1');
        }
        if (m != 0) wkend = m;
    }
    // .shift-index (QTR.2, YEAR.3): seasons offset by shift-1 shift-periods.
    var shift: i64 = 1;
    if (j < s.len and s[j] == '.') {
        var k = j + 1;
        while (k < s.len and std.ascii.isDigit(s[k])) : (k += 1) {}
        if (k > j + 1) {
            shift = std.fmt.parseInt(i64, s[j + 1 .. k], 10) catch std.math.maxInt(i64);
            if (shift <= 0) shift = 1;
        }
    }
    return .{ .base = base, .mult = mult, .shift = shift, .wkend = wkend };
}

/// Intervals per seasonal cycle (year) for the base date intervals we support.
pub fn baseSeasons(base: []const u8) ?i64 {
    if (eqi(base, "YEAR")) return 1;
    if (eqi(base, "SEMIYEAR")) return 2;
    if (eqi(base, "QTR")) return 4;
    if (eqi(base, "MONTH")) return 12;
    if (eqi(base, "SEMIMONTH")) return 24;
    if (eqi(base, "TENDAY")) return 36;
    return null;
}

/// Standardized bivariate-normal CDF P(X≤x, Y≤y | corr r), via the exact integral
/// Φ2 = Φ(x)Φ(y) + (1/2π)∫₀ʳ exp(−(x²−2xyt+y²)/2(1−t²))/√(1−t²) dt (Simpson, N=400).
pub fn bivarNormCdf(x: f64, y: f64, r: f64) f64 {
    const base = stdNormCdf(x) * stdNormCdf(y);
    if (r == 0) return base;
    const g = struct {
        fn f(tv: f64, xx: f64, yy: f64) f64 {
            const om = 1 - tv * tv;
            return @exp(-(xx * xx - 2 * xx * yy * tv + yy * yy) / (2 * om)) / @sqrt(om);
        }
    }.f;
    const n: usize = 400;
    const hstep = r / @as(f64, @floatFromInt(n));
    var sum = g(0, x, y) + g(r, x, y);
    var i: usize = 1;
    while (i < n) : (i += 1) {
        const ti = hstep * @as(f64, @floatFromInt(i));
        sum += g(ti, x, y) * (if (i % 2 == 1) @as(f64, 4) else 2);
    }
    return base + (hstep / 3.0) * sum / (2.0 * std.math.pi);
}

/// Geodetic (great-circle) distance in km via haversine, mean Earth radius 6371 km.
pub fn haversineKm(lat1: f64, lon1: f64, lat2: f64, lon2: f64) f64 {
    const dlat = (lat2 - lat1) / 2;
    const dlon = (lon2 - lon1) / 2;
    const a = @sin(dlat) * @sin(dlat) + @cos(lat1) * @cos(lat2) * @sin(dlon) * @sin(dlon);
    return 6371.0 * 2 * std.math.atan2(@sqrt(a), @sqrt(1 - a));
}

fn isLeap(y: i64) bool {
    return (@mod(y, 4) == 0 and @mod(y, 100) != 0) or @mod(y, 400) == 0;
}

/// Fractional years between SAS dates `d1` and `d2` under `basis`:
///   ACT/365   actual days / 365
///   ACT/360   actual days / 360
///   30/360    30-day months, 360-day year (US NASD adjustment)
///   ACT/ACT   ISDA actual/actual: day fractions weighted by each year's length
/// Blank basis defaults to ACT/ACT; any other unrecognized basis → NOTE +
/// missing (BUG-datdifbasis — was a silent ACT/ACT fallback).
/// SQL LIKE glob match: `%` matches any sequence (incl. empty), `_` any single
/// char, all other chars literal (case-sensitive, as SAS). Linear with one
/// backtrack point — enough for the single-`%` patterns SQL fixtures use.
/// Pure matcher: callers pre-trim/pad operands (BUG-likepadwidth — SAS
/// compares the pattern against the value at its DECLARED blank-padded width,
/// unreachable here; charfns `like` currently trim-both, EPIC-charfixedwidth).
pub fn sqlLike(s: []const u8, pat: []const u8) bool {
    var si: usize = 0;
    var pi: usize = 0;
    var star_p: ?usize = null;
    var star_s: usize = 0;
    while (si < s.len) {
        if (pi < pat.len and (pat[pi] == '_' or pat[pi] == s[si])) {
            si += 1;
            pi += 1;
        } else if (pi < pat.len and pat[pi] == '%') {
            star_p = pi;
            star_s = si;
            pi += 1;
        } else if (star_p) |sp| {
            pi = sp + 1;
            star_s += 1;
            si = star_s;
        } else return false;
    }
    while (pi < pat.len and pat[pi] == '%') pi += 1;
    return pi == pat.len;
}

/// An unsupported day-count basis → NOTE + _ERROR_ + missing (the domErr
/// idiom), never a silent ACT/ACT fallback (BUG-datdifbasis). These leaves
/// carry no `ev` — route through the dispatch-stashed `conv_ev`, like toNum.
fn badBasis(comptime fname: []const u8, b: []const u8) Value {
    if (conv_ev) |e| {
        note(e, "Invalid basis '{s}' in " ++ fname ++ " (result set to missing)", .{b});
        e.setError() catch {}; // same catch{} reasoning as domErr
    }
    return Value.missing;
}

/// datdif(d1, d2, basis) — day count between two SAS dates. ACT/ACT (and
/// ACTUAL) is the plain serial difference; 30/360 uses the 30-day-month
/// convention (same day adjustment as yrdif). Blank basis → ACT/ACT; any
/// other unrecognized basis → NOTE + missing.
pub fn datdif(d1: i64, d2: i64, basis: []const u8) Value {
    const b = std.mem.trim(u8, basis, " ");
    if (eqi(b, "30/360")) {
        const a = civilFromSas(d1);
        const c = civilFromSas(d2);
        var dd1 = a.d;
        var dd2 = c.d;
        if (dd1 == 31) dd1 = 30;
        if (dd2 == 31 and dd1 == 30) dd2 = 30;
        const days = 360 * (c.y - a.y) + 30 * (c.m - a.m) + (dd2 - dd1);
        return numVal(@floatFromInt(days));
    }
    if (b.len != 0 and !eqi(b, "ACT/ACT") and !eqi(b, "ACTUAL"))
        return badBasis("DATDIF", b); // e.g. ACT/360 is a YRDIF basis, not DATDIF
    return numVal(@floatFromInt(d2 - d1)); // ACT/ACT / ACTUAL
}

/// Anniversary date (m/d in year y), clamping Feb-29 to Feb-28 in non-leap
/// years so mdy math never rolls into March. For the AGE basis of yrdif.
fn annivDate(y: i64, m: i64, d: i64) i64 {
    if (m == 2 and d == 29 and !isLeap(y)) return sasDate(y, 2, 28);
    return sasDate(y, m, d);
}

pub fn yrdif(d1: i64, d2: i64, basis: []const u8) Value {
    const b = std.mem.trim(u8, basis, " ");
    if (eqi(b, "ACT/365")) return numVal(@as(f64, @floatFromInt(d2 - d1)) / 365.0);
    if (eqi(b, "ACT/360")) return numVal(@as(f64, @floatFromInt(d2 - d1)) / 360.0);

    // AGE: whole anniversary years plus the fraction of the current
    // anniversary-to-anniversary span. Exact anniversaries return integers.
    if (eqi(b, "AGE")) {
        if (d1 == d2) return numVal(0);
        const sign: f64 = if (d2 < d1) -1 else 1;
        const lo = @min(d1, d2);
        const hi = @max(d1, d2);
        const a = civilFromSas(lo);
        const c = civilFromSas(hi);
        var years = c.y - a.y;
        if (c.m < a.m or (c.m == a.m and c.d < a.d)) years -= 1;
        const anniv = annivDate(a.y + years, a.m, a.d);
        const next = annivDate(a.y + years + 1, a.m, a.d);
        const frac = @as(f64, @floatFromInt(hi - anniv)) / @as(f64, @floatFromInt(next - anniv));
        return numVal(sign * (@as(f64, @floatFromInt(years)) + frac));
    }

    if (eqi(b, "30/360")) {
        const a = civilFromSas(d1);
        const c = civilFromSas(d2);
        var dd1 = a.d;
        var dd2 = c.d;
        if (dd1 == 31) dd1 = 30;
        if (dd2 == 31 and dd1 == 30) dd2 = 30;
        const days = 360 * (c.y - a.y) + 30 * (c.m - a.m) + (dd2 - dd1);
        return numVal(@as(f64, @floatFromInt(days)) / 360.0);
    }

    if (b.len != 0 and !eqi(b, "ACT/ACT") and !eqi(b, "ACTUAL"))
        return badBasis("YRDIF", b);

    // ACT/ACT (ISDA): fraction of the start year + whole years + fraction of the
    // end year, each year weighted by its own length (365 or 366).
    const y1 = civilFromSas(d1).y;
    const y2 = civilFromSas(d2).y;
    const len1: f64 = if (isLeap(y1)) 366 else 365;
    if (y1 == y2) return numVal(@as(f64, @floatFromInt(d2 - d1)) / len1);
    const len2: f64 = if (isLeap(y2)) 366 else 365;
    const frac_start = @as(f64, @floatFromInt(sasDate(y1 + 1, 1, 1) - d1)) / len1;
    const frac_end = @as(f64, @floatFromInt(d2 - sasDate(y2, 1, 1))) / len2;
    return numVal(frac_start + @as(f64, @floatFromInt(y2 - y1 - 1)) + frac_end);
}

/// SAS weekday: 1 = Sunday … 7 = Saturday. Day 0 (1960-01-01) was a Friday (6).
pub fn weekdayOf(n: i64) i64 {
    return @mod(n + 5, 7) + 1;
}

pub fn floorI64(x: f64) i64 {
    const f = @floor(x);
    // Saturate absurd / NaN inputs instead of panicking on @intFromFloat.
    // Bound is far beyond any real date yet far from i64's edges, so the
    // downstream calendar math (daysFromCivil/civilFromDays) can't overflow.
    const lim = 1e13;
    if (std.math.isNan(f)) return 0;
    if (f >= lim) return @intFromFloat(@as(f64, lim));
    if (f <= -lim) return @intFromFloat(@as(f64, -lim));
    return @intFromFloat(f);
}

/// Wall-clock seconds since the Unix epoch, cross-platform (the eval path carries no
/// `Io`, so we read the OS clock directly). POSIX has `clock_gettime`; Windows has no
/// such syscall, so use `RtlGetSystemTimePrecise` (100-ns ticks since 1601) — only the
/// target's switch prong is analyzed, so the cross-compile stays clean.
fn epochSeconds() i64 {
    return switch (@import("builtin").os.tag) {
        .windows => @divFloor(@as(i64, std.os.windows.ntdll.RtlGetSystemTimePrecise()), 10_000_000) + std.time.epoch.windows,
        else => blk: {
            var ts: std.posix.timespec = undefined;
            if (std.posix.errno(std.posix.system.clock_gettime(.REALTIME, &ts)) != .SUCCESS) break :blk 0;
            break :blk @intCast(ts.sec);
        },
    };
}

pub fn currentSasDate() i64 {
    return @divFloor(epochSeconds(), 86400) + sas_epoch_days;
}

/// Seconds since local midnight (for TIME/DATETIME). ponytail: UTC, no timezone.
pub fn currentSecondOfDay() i64 {
    return @mod(epochSeconds(), 86400);
}

/// Expand a 2-digit year to a full year within the YEARCUTOFF window — the shared,
/// OPTIONS-aware helper (BUG-yearcutoff; was a separate hardcoded copy).
pub fn expandYear(yy: i64) i64 {
    return format.expandYear(yy);
}

pub fn daysInMonth(y: i64, m: i64) i64 {
    const next = if (m == 12) daysFromCivil(y + 1, 1, 1) else daysFromCivil(y, m + 1, 1);
    return next - daysFromCivil(y, m, 1);
}

/// Clamp a float to the i64 range before @intFromFloat (which panics on overflow).
/// NaN would slip through @min/@max unchanged, so map it to 0 first.
pub fn clampI64(x: f64) i64 {
    if (std.math.isNan(x)) return 0;
    return @intFromFloat(@max(-9.0e15, @min(9.0e15, @trunc(x))));
}

/// CATQ(modifiers <,delimiter>, item…): concatenate with a delimiter, quoting items
/// that contain it. Supported modifiers: 1/'/2/" (quote char), a/A (quote all),
/// c/C (comma), h/H (tab), d/D (explicit delimiter arg), s/S (strip), t/T (trim).
pub fn catq(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!Value {
    if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
    const mods = try toStr(ev, args[0]);
    var qc: u8 = '"';
    var quote_all = false;
    var delim: []const u8 = " ";
    var strip_it = false;
    var trim_it = false;
    var delim_arg = false;
    for (mods) |m| switch (m) {
        '1', '\'' => qc = '\'',
        '2', '"' => qc = '"',
        'a', 'A' => quote_all = true,
        'c', 'C' => delim = ",",
        'h', 'H' => delim = "\t",
        'd', 'D' => delim_arg = true,
        's', 'S' => strip_it = true,
        't', 'T' => trim_it = true,
        else => {},
    };
    var idx: usize = 1;
    if (delim_arg and idx < args.len) {
        delim = try toStr(ev, args[idx]);
        idx += 1;
    }
    var parts: std.ArrayList([]const u8) = .empty;
    for (args[idx..]) |arg| {
        // BUG-catnote: CATQ is outside the note-free cat/cats/catt/catx set —
        // its numeric coercion still logs the NOTE (catStr no longer does).
        if (arg == .num) ev.diags.note(0, "Numeric values have been converted to character values at the places given by: (Line):(Column).", .{}) catch {};
        var it = try catStr(ev, arg); // BUG-catbest: numerics via BEST12, not raw f64
        if (strip_it) it = std.mem.trim(u8, it, " ") else if (trim_it) it = std.mem.trimEnd(u8, it, " ");
        if (quote_all or std.mem.indexOf(u8, it, delim) != null) {
            var b: std.ArrayList(u8) = .empty;
            try b.append(ev.arena, qc);
            for (it) |c| {
                if (c == qc) try b.append(ev.arena, qc);
                try b.append(ev.arena, c);
            }
            try b.append(ev.arena, qc);
            try parts.append(ev.arena, b.items);
        } else try parts.append(ev.arena, it);
    }
    return .{ .str = try std.mem.join(ev.arena, delim, parts.items) };
}

/// Seconds in a time interval base (HOUR/MINUTE/SECOND), else null. A DT-prefixed
/// time base is the same unit on a datetime (already seconds) — no special case.
fn timeSecsOf(base: []const u8) ?i64 {
    if (eqi(base, "HOUR")) return 3600;
    if (eqi(base, "MINUTE")) return 60;
    if (eqi(base, "SECOND")) return 1;
    return null;
}

/// Monday of ISO week 1 of year `y` (the Monday of the week containing Jan 4).
fn isoYearStart(y: i64) i64 {
    const jan4 = sasDate(y, 1, 4);
    return jan4 - @mod(weekdayOf(jan4) - 2 + 7, 7);
}

/// ISO 8601 year of date `d`: the civil year of the Thursday of d's Monday-week.
fn isoYearOf(d: i64) i64 {
    const mon = d - @mod(weekdayOf(d) - 2 + 7, 7);
    return civilFromSas(mon + 3).y;
}

/// WEEKDAY period index of date `d` under weekend mask `we` (bit 0 = Sunday …
/// bit 6 = Saturday, set = weekend day): working days are 1-day periods; weekend
/// days share the preceding working day's period. `we` == 0x7F (all weekend)
/// returns null upstream, so a working day always exists.
fn weekdayBucket(d: i64, we: u8) i64 {
    const w = @divFloor(d + 5, 7); // Sunday-start week (day -5 = 1959-12-27 Sun)
    const o: u3 = @intCast(@mod(d + 5, 7)); // 0=Sun … 6=Sat
    var wd: i64 = 0; // working days per week
    var rank: i64 = 0; // working days before offset o in the week
    var i: u3 = 0;
    while (i < 7) : (i += 1) {
        if (we & (@as(u8, 1) << i) != 0) continue;
        wd += 1;
        if (i < o) rank += 1;
    }
    return if (we & (@as(u8, 1) << o) != 0) w * wd + rank - 1 else w * wd + rank;
}

/// First day (SAS date) of weekday bucket `b` under weekend mask `we` — the
/// inverse of `weekdayBucket`. Buckets start on working days, so the r-th
/// working day of week @divFloor(b, wd) is the answer.
fn weekdayBucketFirst(b: i64, we: u8) i64 {
    const wd: i64 = 7 - @as(i64, @popCount(we));
    const w = @divFloor(b, wd);
    const r = @mod(b, wd);
    var o: i64 = 0;
    var cnt: i64 = 0;
    var i: u3 = 0;
    while (i < 7) : (i += 1) {
        if (we & (@as(u8, 1) << i) != 0) continue;
        if (cnt == r) {
            o = i;
            break;
        }
        cnt += 1;
    }
    return w * 7 - 5 + o;
}

/// Bucket index of SAS date `d` for a parsed interval (multiplier + shift-index
/// applied). `bucketFirst` inverts it, so INTCK (bucket difference) and INTNX
/// (bucket → day) can never disagree. null = unrecognised base, or a shift-index
/// on a base that has none → the caller's loud "unknown interval" NOTE.
fn dateBucket(base: []const u8, mult: i64, shift: i64, wkend: u8, d: i64) ?i64 {
    if (eqi(base, "DAY")) return @divFloor(d - (shift - 1), mult);
    if (eqi(base, "WEEK") or eqi(base, "WEEKU")) return @divFloor(d + 5 - (shift - 1), 7 * mult); // weeks start Sunday (WEEKU = WEEK's U descriptor)
    if (eqi(base, "WEEKW")) return @divFloor(d + 6 - (shift - 1), 7 * mult); // Saturday start = WEEK offset 1 day
    if (eqi(base, "WEEKDAY")) {
        if (shift != 1 or wkend == 0x7F) return null; // all-weekend = invalid
        return @divFloor(weekdayBucket(d, wkend), mult);
    }
    if (eqi(base, "WEEKV")) { // ISO week = Monday-start week
        if (shift != 1) return null;
        return @divFloor(d + 4, 7 * mult);
    }
    if (eqi(base, "YEARV")) { // ISO year
        if (shift != 1) return null;
        return @divFloor(isoYearOf(d), mult);
    }
    if (eqi(base, "QTRV")) { // 13-week quarters of the ISO year; a 53rd week lands in Q4
        if (shift != 1) return null;
        const iy = isoYearOf(d);
        const q = @min(@divFloor(@divFloor(d - isoYearStart(iy), 7), 13), 3);
        return @divFloor(iy * 4 + q, mult);
    }
    const c = civilFromSas(d);
    const mi = c.y * 12 + (c.m - 1); // absolute month index
    const bm: ?i64 = if (eqi(base, "QUARTER")) 3 else baseMonths(base);
    if (bm) |m| return @divFloor(mi - (shift - 1), m * mult); // YEAR/SEMIYEAR/QTR/MONTH: shift in months
    if (eqi(base, "SEMIMONTH")) { // 1st–15th / 16th–end
        const raw = mi * 2 + @as(i64, if (c.d >= 16) 1 else 0);
        return @divFloor(raw - (shift - 1), mult);
    }
    if (eqi(base, "TENDAY")) { // 1st / 11th / 21st
        const raw = mi * 3 + @as(i64, if (c.d >= 21) 2 else if (c.d >= 11) 1 else 0);
        return @divFloor(raw - (shift - 1), mult);
    }
    return null;
}

/// First day of bucket `b` — the inverse of `dateBucket`.
fn bucketFirst(base: []const u8, mult: i64, shift: i64, wkend: u8, b: i64) ?i64 {
    if (eqi(base, "DAY")) return b * mult + (shift - 1);
    if (eqi(base, "WEEK") or eqi(base, "WEEKU")) return b * 7 * mult - 5 + (shift - 1);
    if (eqi(base, "WEEKW")) return b * 7 * mult - 6 + (shift - 1);
    if (eqi(base, "WEEKDAY")) {
        if (shift != 1 or wkend == 0x7F) return null;
        return weekdayBucketFirst(b * mult, wkend);
    }
    if (eqi(base, "WEEKV")) {
        if (shift != 1) return null;
        return b * 7 * mult - 4;
    }
    if (eqi(base, "YEARV")) {
        if (shift != 1) return null;
        return isoYearStart(b * mult);
    }
    if (eqi(base, "QTRV")) {
        if (shift != 1) return null;
        const raw = b * mult;
        return isoYearStart(@divFloor(raw, 4)) + @mod(raw, 4) * 91; // 13-week quarters
    }
    const bm: ?i64 = if (eqi(base, "QUARTER")) 3 else baseMonths(base);
    if (bm) |m| {
        const fm = b * m * mult + (shift - 1); // first month index of the period
        return sasDate(@divFloor(fm, 12), @mod(fm, 12) + 1, 1);
    }
    if (eqi(base, "SEMIMONTH")) {
        const raw = b * mult + (shift - 1);
        const mt = @divFloor(raw, 2);
        return sasDate(@divFloor(mt, 12), @mod(mt, 12) + 1, if (@mod(raw, 2) == 0) 1 else 16);
    }
    if (eqi(base, "TENDAY")) {
        const raw = b * mult + (shift - 1);
        const mt = @divFloor(raw, 3);
        return sasDate(@divFloor(mt, 12), @mod(mt, 12) + 1, @mod(raw, 3) * 10 + 1);
    }
    return null;
}

/// The serial index of the interval that contains `n` — differencing two
/// of these gives `intck`'s boundary count. null = unrecognised interval.
/// Routed through `parseInterval`: DT prefix, multipliers, and shift-index all
/// recognised (GAP-intnxintervals), so INTCK accepts what INTTEST accepts.
pub fn bucketOf(iv: []const u8, n: i64) ?i64 {
    var buf: [32]u8 = undefined;
    const pi = parseInterval(iv, &buf);
    if (pi.mult > 100_000 or pi.shift > 100_000) return null; // parse-overflow sentinel
    if (timeSecsOf(pi.base)) |unit| return @divFloor(n - (pi.shift - 1) * unit, unit * pi.mult);
    const is_dt = std.ascii.startsWithIgnoreCase(std.mem.trim(u8, iv, " "), "DT");
    const d = if (is_dt) @divFloor(n, 86400) else n; // datetime → its calendar day
    return dateBucket(pi.base, pi.mult, pi.shift, pi.wkend, d);
}

/// The first date of the interval `n` intervals on from `start` (BEGINNING
/// alignment). null = unrecognised interval. Same `parseInterval` routing as
/// `bucketOf`; a datetime result is the period start at midnight.
fn intnxOf(iv: []const u8, start: i64, n: i64) ?i64 {
    var buf: [32]u8 = undefined;
    const pi = parseInterval(iv, &buf);
    if (pi.mult > 100_000 or pi.shift > 100_000) return null;
    if (timeSecsOf(pi.base)) |unit| {
        const b = @divFloor(start - (pi.shift - 1) * unit, unit * pi.mult);
        return (b + n) * unit * pi.mult + (pi.shift - 1) * unit;
    }
    const is_dt = std.ascii.startsWithIgnoreCase(std.mem.trim(u8, iv, " "), "DT");
    const d = if (is_dt) @divFloor(start, 86400) else start;
    const b = dateBucket(pi.base, pi.mult, pi.shift, pi.wkend, d) orelse return null;
    const first = bucketFirst(pi.base, pi.mult, pi.shift, pi.wkend, b + n) orelse return null;
    return if (is_dt) first * 86400 else first;
}

pub const Align = enum { begin, middle, end, same };

/// intnx with alignment. `intnxOf` gives the interval's first day (BEGINNING);
/// END is the day before the next interval, MIDDLE the midpoint, and SAME keeps
/// the source's offset into its own interval.
pub fn intnxAlign(iv: []const u8, start: i64, n: i64, al: Align) ?i64 {
    const b = intnxOf(iv, start, n) orelse return null;
    return switch (al) {
        .begin => b,
        .same => sameAlign(iv, start, b) orelse return null,
        .end => (intnxOf(iv, start, n + 1) orelse return null) - 1,
        .middle => b + @divFloor((intnxOf(iv, start, n + 1) orelse return null) - 1 - b, 2),
    };
}

/// SAME alignment: `start`'s position within its interval, applied to the target
/// period that begins at `b`. All month-shift-period intervals (MONTH, QTR,
/// SEMIYEAR, YEAR — SAS gives them a shift period of MONTH) must preserve the
/// source MONTH-offset + DAY, clamping an overflowing day to the target month's
/// last day (Feb 29→28; 31Jan +1mo→29Feb, NOT 02Mar). A plain day offset instead
/// spills into the next month (BUG-intnxyearsame for YEAR; BUG-intnxmonthsame for
/// MONTH/QTR).
fn sameAlign(iv: []const u8, start: i64, b: i64) ?i64 {
    const ps = intnxOf(iv, start, 0) orelse return null; // start's period beginning
    var ibuf: [32]u8 = undefined;
    const base = parseInterval(iv, &ibuf).base; // uppercased, DT/multiplier stripped
    const is_dt = std.ascii.startsWithIgnoreCase(std.mem.trim(u8, iv, " "), "DT");
    if (eqi(base, "MONTH") or eqi(base, "QTR") or eqi(base, "QUARTER") or
        eqi(base, "SEMIYEAR") or eqi(base, "YEAR"))
    {
        // DT: clamp the calendar day like the date variant, then re-attach the
        // time-of-day (BUG-intnxdtsameoverflow — plain seconds offset spills).
        const tod: i64 = if (is_dt) @mod(start, 86400) else 0;
        const sd = if (is_dt) @divFloor(start, 86400) else start;
        const psd = if (is_dt) @divFloor(ps, 86400) else ps;
        const bd = if (is_dt) @divFloor(b, 86400) else b;
        const s = civilFromSas(sd);
        const bc = civilFromSas(bd); // target period beginning; bc.m is its start month
        const idx = (bc.m - 1) + (s.m - civilFromSas(psd).m); // 0-based month index from bc.y
        const ty = bc.y + @divFloor(idx, 12);
        const tm = @mod(idx, 12) + 1;
        const day = sasDate(ty, tm, @min(s.d, daysInMonth(ty, tm)));
        return if (is_dt) day * 86400 + tod else day;
    }
    return b + (start - ps);
}

pub fn unknownInterval(ev: *eval.Evaluator, iv: []const u8) Value {
    note(ev, "unknown date interval '{s}' (set to missing)", .{iv});
    return Value.missing;
}

/// Compounding periods per year for TIMEVALUE/SAVINGS, extending the EFFRATE set
/// with WEEK/TENDAY. Null = an interval those functions can't compound over.
fn ppyOf(iv: []const u8) ?f64 {
    if (intervalsPerYear(iv)) |v| return v;
    const w = std.mem.trim(u8, iv, " ");
    if (eqi(w, "week")) return 52;
    if (eqi(w, "tenday")) return 36; // 3 periods/month, matching intnxOf's TENDAY stepper
    return null;
}

/// The interest rate (percent) in effect at `date`: the date-rate pair with the
/// latest date at or before `date`; ties on a date take the last one listed
/// (SAS: "applies only the final rate that is listed for that date"). `pairs` is
/// the flat date-1, rate-1, date-2, rate-2, … argument tail. Null if none apply.
fn rateInEffect(pairs: []const Value, date: i64) ?f64 {
    var best_date: ?i64 = null;
    var best_rate: f64 = 0;
    var i: usize = 0;
    while (i + 1 < pairs.len) : (i += 2) {
        const dt = toNum(pairs[i]);
        const rt = toNum(pairs[i + 1]);
        if (isMiss(dt) or isMiss(rt)) continue;
        const d = floorI64(dt);
        if (d <= date and (best_date == null or d >= best_date.?)) {
            best_date = d;
            best_rate = rt;
        }
    }
    return if (best_date == null) null else best_rate;
}

/// Accumulation factor from `from` to `to` (to > from): the product of per-period
/// compounding factors under the variable rates, with SAS's simple interest on the
/// final partial period. Null if the interval is uncompoundable or a period has no
/// rate in effect.
fn accumFactor(iv: []const u8, from: i64, to: i64, pairs: []const Value) ?f64 {
    // Compounding boundaries are anchored at `to` (the base date the balance is
    // measured at) and stepped backward; the final partial period sits at the
    // `from` end and earns simple interest.
    const ppy = ppyOf(iv) orelse return null;
    var cur = to;
    var f: f64 = 1;
    while (cur > from) {
        const prv = intnxAlign(iv, cur, -1, .same) orelse return null;
        if (prv >= cur) return null; // guard: interval must retreat
        if (prv >= from) {
            const rate = rateInEffect(pairs, prv) orelse return null;
            f *= (1 + rate / 100.0 / ppy);
            cur = prv;
        } else {
            const rate = rateInEffect(pairs, from) orelse return null;
            const frac = @as(f64, @floatFromInt(cur - from)) / @as(f64, @floatFromInt(cur - prv));
            f *= (1 + rate / 100.0 / ppy * frac); // simple interest for the partial period
            cur = from;
        }
    }
    return f;
}

/// Time value at `base` of `amount` sitting at `from`: accumulate forward when
/// base is later, discount when base is earlier.
pub fn timeGrow(amount: f64, from: i64, base: i64, iv: []const u8, pairs: []const Value) ?f64 {
    if (base == from) return amount;
    if (base > from) {
        const f = accumFactor(iv, from, base, pairs) orelse return null;
        return amount * f;
    }
    const f = accumFactor(iv, base, from, pairs) orelse return null;
    return amount / f;
}

pub fn dateField(ev: *eval.Evaluator, name: []const u8, args: []const Value, comptime f: fn (i64) i64) Value {
    if (args.len != 1) return badArity(ev, name, "1", args.len);
    const x = toNum(args[0]);
    if (isMiss(x)) return Value.missing;
    const whole = floorI64(x);
    var r: f64 = @floatFromInt(f(whole));
    // SECOND/TIMEPART preserve fractional seconds (SAS time values carry them);
    // HOUR/MINUTE/DATEPART/DAY/etc. stay whole.
    if (eqi(name, "second") or eqi(name, "timepart")) r += x - @as(f64, @floatFromInt(whole));
    return numVal(r);
}

pub fn note(ev: *eval.Evaluator, comptime fmt: []const u8, args: anytype) void {
    ev.diags.report(.note, 0, fmt, args) catch {}; // best-effort; line 0 (no AST line)
}

// ── tests ────────────────────────────────────────────────────────────────

const t = std.testing;

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

fn harness() Harness {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

fn numV(x: f64) Value {
    return .{ .num = x };
}
fn strV(v: []const u8) Value {
    return .{ .str = v };
}

test "GAP-weekufn: WEEKU()/WEEKW() stay LOUD — SAS 9.4 has no such FUNCTIONS" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SAS 9.4 Functions and CALL Routines: Reference (Fifth Ed.) has NO WEEKU or
    // WEEKW function entry — on the WEEK Function page (printed p.1681) the See
    // Also names WEEKUw./WEEKWw. only as FORMATS and INFORMATS, and the WEEK
    // entry is followed directly by WEEKDAY (full-dictionary scan: zero function
    // hits). The U/W week-numbering rules exist as WEEK(date,'U'/'W')
    // (numfns.zig) and as the INTCK/INTNX WEEKU/WEEKW intervals (GAP-weekuw).
    // Implementing standalone functions would be a SILENT SUPERSET — a typo then
    // computes a plausible number where real SAS errors "The function WEEKU is
    // unknown" (the NEGPAREN-informat class, NOTE-informatlow-tick245 #14). Pin
    // the loud gap (D-002); GAP-weekufn is resolved as documented-loud.
    _ = try dispatch(&e, "weeku", &.{numV(22100)});
    _ = try dispatch(&e, "weekw", &.{numV(22100)});
    try t.expectEqual(@as(usize, 2), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "function weeku() is not supported yet") != null);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[1].message, "function weekw() is not supported yet") != null);
    // the documented spellings for the same rules DO work (22100 = 04JUL2020).
    try t.expectEqual(@as(f64, 26), (try dispatch(&e, "week", &.{ numV(22100), strV("U") })).num);
    try t.expectEqual(@as(f64, 26), (try dispatch(&e, "week", &.{ numV(22100), strV("W") })).num);
    try t.expectEqual(@as(usize, 2), h.diags.count()); // no new diagnostics
}

test "MISC-fnseterror: invalid function argument sets _ERROR_=1 via the PDV (NOTE kept)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SUBSTR nonpositive position → NOTE + _ERROR_=1, value still the remainder.
    try h.pdv.set("_error_", .{ .num = 0 });
    const r1 = try dispatch(&e, "substr", &.{ strV("hello"), numV(0), numV(2) });
    try t.expectEqualStrings("hello", r1.str);
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "Invalid second argument to function SUBSTR") != null);

    // SUBSTR nonpositive length → NOTE + _ERROR_=1.
    try h.pdv.set("_error_", .{ .num = 0 });
    _ = try dispatch(&e, "substr", &.{ strV("hello"), numV(2), numV(-1) });
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[1].message, "Invalid third argument to function SUBSTR") != null);

    // domErr path (log of nonpositive) → NOTE + _ERROR_=1, missing result.
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "log", &.{numV(-1)})).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);

    // valid calls leave _ERROR_ alone.
    try h.pdv.set("_error_", .{ .num = 0 });
    _ = try dispatch(&e, "substr", &.{ strV("hello"), numV(2), numV(3) });
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}

test "NOTE-subpadinvpos: a nonpositive SUBPAD position is INVALID — NOTE + _ERROR_=1, not a silent missing" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SUBPAD's `position` "is a positive integer" (SAS 9.4 Functions and CALL
    // Routines: Reference p.1529). The volume's general rule (p.5): an invalid
    // argument — "for example, missing or outside the prescribed range" — makes
    // SAS write a note, set _ERROR_ to 1, and return a missing value. We already
    // returned missing; the note and the flag are the half that was absent.
    //
    // BUG-charfnsmissingtype fixed this test's PREMISE, not its assertion: SUBPAD
    // is a CHARACTER function (p.1529), so its "missing value" is a BLANK, and
    // `isMissing()` — which is false for every string, `Value.missing` being
    // numeric-only — was asserting the wrong TYPE. The NOTE and the `_ERROR_=1`
    // this ticket exists for are asserted exactly as before; only the shape of
    // the returned value changed, and it is now pinned by its union tag.
    for ([_]f64{ 0, -2 }) |bad| {
        try h.pdv.set("_error_", .{ .num = 0 });
        const r = try dispatch(&e, "subpad", &.{ strV("abcdef"), numV(bad), numV(3) });
        try t.expect(r == .str);
        try t.expectEqualStrings("", r.str);
        try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    }
    // valid positions are untouched — value AND flag
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expectEqualStrings("bcd", (try dispatch(&e, "subpad", &.{ strV("abcdef"), numV(2), numV(3) })).str);
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
    // A MISSING position is still its own rule — p.7 separates it from the range
    // rule, so NO note and NO _ERROR_ — but the result is a blank CHARACTER, same
    // as every other SUBPAD exit. Ditto a position or length too big for an i64.
    try h.pdv.set("_error_", .{ .num = 0 });
    const miss_pos = try dispatch(&e, "subpad", &.{ strV("abcdef"), Value.missing, numV(3) });
    try t.expect(miss_pos == .str);
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
    try t.expect((try dispatch(&e, "subpad", &.{ strV("abcdef"), numV(1e19), numV(3) })) == .str);
    try t.expect((try dispatch(&e, "subpad", &.{ strV("abcdef"), numV(1), numV(1e19) })) == .str);
}

test "GAP-bondrangenote (additive half): an out-of-range financial arg NOTEs, a MISSING one does not" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // Functions ref p.5: an argument "outside the prescribed range" is invalid →
    // note + _ERROR_=1 + missing. p.7 carves out financial functions ONLY for the
    // MISSING-value rule, not for the range rule, so the two must behave
    // differently — that split is what this test pins.
    // Ranges: DEPDB p.604 "y > 0"; PVP p.1385 / YIELDP p.1688 "n > 0", "K > 0";
    // DUR p.658 / CONVX p.560 "f > 0".
    const OutOfRange = struct { name: []const u8, args: []const Value };
    const bad = [_]OutOfRange{
        .{ .name = "depdb", .args = &.{ numV(10), numV(1000), numV(0), numV(2) } }, // y = 0
        .{ .name = "depdb", .args = &.{ numV(10), numV(1000), numV(-15), numV(2) } }, // y < 0
        .{ .name = "daccdb", .args = &.{ numV(10), numV(1000), numV(-1), numV(2) } },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), numV(0), numV(3), numV(1), numV(0.05) } }, // n = 0
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), numV(1), numV(0), numV(1), numV(0.05) } }, // K = 0
        .{ .name = "durp", .args = &.{ numV(1000), numV(0.05), numV(-1), numV(3), numV(1), numV(0.05) } },
        .{ .name = "convxp", .args = &.{ numV(1000), numV(0.05), numV(1), numV(0), numV(1), numV(0.05) } },
        .{ .name = "yieldp", .args = &.{ numV(1000), numV(0.01), numV(0), numV(14), numV(0.165), numV(800) } },
        .{ .name = "dur", .args = &.{ numV(0.05), numV(0), numV(100) } }, // f = 0
        .{ .name = "convx", .args = &.{ numV(0.05), numV(-1), numV(100) } },
    };
    for (bad) |b| {
        try h.pdv.set("_error_", .{ .num = 0 });
        try t.expect((try dispatch(&e, b.name, b.args)).isMissing());
        try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num); // the NOTE half of p.5
    }

    // A MISSING argument is the p.7 EXCEPTION for financial functions: still
    // missing, but NO note and NO _ERROR_. This is the control that proves the
    // two rules were split rather than merged.
    const miss = [_]OutOfRange{
        .{ .name = "depdb", .args = &.{ numV(10), numV(1000), Value.missing, numV(2) } },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), Value.missing, numV(3), numV(1), numV(0.05) } },
        .{ .name = "dur", .args = &.{ Value.missing, numV(1), numV(100) } },
    };
    for (miss) |m| {
        try h.pdv.set("_error_", .{ .num = 0 });
        try t.expect((try dispatch(&e, m.name, m.args)).isMissing());
        try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
    }

    // In-range calls keep BOTH their value and a clean flag — the doc's own
    // worked examples: DEPDB p.605 → 36.779648624, DUR p.658 → 5.284024988.
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expectApproxEqAbs(@as(f64, 36.779648624), (try dispatch(&e, "depdb", &.{ numV(10), numV(1000), numV(15), numV(2) })).num, 1e-6);
    try t.expectApproxEqAbs(@as(f64, 5.284024988), (try dispatch(&e, "dur", &.{ numV(1.0 / 20.0), numV(1), numV(0.33), numV(0.44), numV(0.55), numV(0.49), numV(0.50), numV(0.22), numV(0.4), numV(0.8), numV(0.01), numV(0.36), numV(0.2), numV(0.4) })).num, 1e-6);
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}

test "NOTE-bitrangenote: an out-of-range bitwise arg NOTEs and sets _ERROR_ (value still missing)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // BAND p.265–266 "Range: An integer value between 0 and (2^32)–1 inclusive"
    // (BNOT p.278–279 / BOR p.279 same bounds) + p.6's invalid-argument rule. The
    // two shapes tests/corpus/bitwise_exact.sas exercises are first.
    for ([_][]const Value{
        &.{ numV(-1), numV(255) }, // band(-1,255)  — below the range
        &.{ numV(4294967296), numV(3) }, // above (2^32)-1
    }) |a| {
        try h.pdv.set("_error_", .{ .num = 0 });
        try t.expect((try dispatch(&e, "band", a)).isMissing()); // value unchanged
        try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num); // …flag is new
    }
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "bnot", &.{numV(1e300)})).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);

    // the MISSING arm keeps its own wording and was already conformant
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "band", &.{ Value.missing, numV(3) })).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);

    // in-range values and the flag are untouched — and NOTE-bitfracround stays
    // parked: an in-range FRACTION still rounds (band(1.9,3)=2), because the
    // entries never say round-or-truncate. Pinned so the park is visible.
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "band", &.{ numV(12), numV(10) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "band", &.{ numV(1.9), numV(3) })).num);
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}

test "GAP-bondrangenote (value half): an unchecked out-of-range arg no longer computes a plausible number" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // These all COMPUTED a credible-looking figure before — the worst D-002
    // shape, because nothing in the output says the answer is meaningless.
    // Ranges: DEPDB p.604 "r >= 0"; PVP p.1385 / YIELDP p.1688 / DURP p.659 /
    // CONVXP p.561 "A > 0", "0 <= c < 1", "n > 0 and is an integer",
    // "0 < k0 <= 1/n", "y > 0" (YIELDP's 6th arg is a price, "p > 0");
    // DUR p.658 "y > 0"; CONVX p.560 "0 < y < 1".
    const Case = struct { name: []const u8, args: []const Value, why: []const u8 };
    const bad = [_]Case{
        .{ .name = "depdb", .args = &.{ numV(10), numV(1000), numV(15), numV(-2) }, .why = "r < 0 (was -411.2990416)" },
        .{ .name = "pvp", .args = &.{ numV(-1000), numV(0.05), numV(1), numV(3), numV(1), numV(0.05) }, .why = "A <= 0" },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(1.5), numV(1), numV(3), numV(1), numV(0.05) }, .why = "c >= 1" },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(-0.01), numV(1), numV(3), numV(1), numV(0.05) }, .why = "c < 0" },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), numV(1.5), numV(3), numV(1), numV(0.05) }, .why = "n not an integer" },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), numV(4), numV(3), numV(0.9), numV(0.05) }, .why = "k0 > 1/n" },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(0), numV(0.05) }, .why = "k0 <= 0" },
        .{ .name = "pvp", .args = &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(1), numV(-0.05) }, .why = "y <= 0" },
        .{ .name = "durp", .args = &.{ numV(1000), numV(0.05), numV(4), numV(3), numV(0.9), numV(0.05) }, .why = "k0 > 1/n" },
        .{ .name = "convxp", .args = &.{ numV(0), numV(0.05), numV(1), numV(3), numV(1), numV(0.05) }, .why = "A <= 0" },
        .{ .name = "yieldp", .args = &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(1), numV(-800) }, .why = "price <= 0" },
        .{ .name = "dur", .args = &.{ numV(-0.05), numV(1), numV(100) }, .why = "DUR y <= 0" },
        .{ .name = "convx", .args = &.{ numV(1.5), numV(1), numV(100) }, .why = "CONVX y >= 1 (DUR allows it, CONVX does not)" },
        .{ .name = "convx", .args = &.{ numV(0), numV(1), numV(100) }, .why = "CONVX y <= 0" },
    };
    for (bad) |b| {
        try h.pdv.set("_error_", .{ .num = 0 });
        try t.expect((try dispatch(&e, b.name, b.args)).isMissing());
        try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    }

    // The two ranges that DIFFER between siblings: y=1.5 is legal for DUR
    // ("y > 0") and illegal for CONVX ("0 < y < 1"). If those were collapsed
    // into one predicate this pair would fail.
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect(!(try dispatch(&e, "dur", &.{ numV(1.5), numV(1), numV(100) })).isMissing());
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);

    // Boundaries that are INSIDE the ranges must still compute: c=0 is legal
    // ("0 <= c"), and k0 exactly 1/n is legal ("k0 <= 1/n").
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect(!(try dispatch(&e, "pvp", &.{ numV(1000), numV(0), numV(1), numV(3), numV(1), numV(0.05) })).isMissing());
    try t.expect(!(try dispatch(&e, "pvp", &.{ numV(1000), numV(0.01), numV(4), numV(14), numV(0.25), numV(0.10) })).isMissing());
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);

    // …and the doc's own worked example is untouched: PVP p.1385
    // pvp(1000, .01, 4, 14, .33/2, .10) = 743.168.
    try t.expectApproxEqAbs(@as(f64, 743.168), (try dispatch(&e, "pvp", &.{ numV(1000), numV(0.01), numV(4), numV(14), numV(0.165), numV(0.10) })).num, 1e-3);
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}

test "NOTE-besselneg: nu<0 is OUTSIDE the documented range — NOTE + _ERROR_=1, not a silent missing" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // IBESSEL (Functions ref p.1022) and JBESSEL (p.1115) both give `nu` the
    // attribute "Range nu ≥ 0". p.5: an argument outside the prescribed range is
    // INVALID — note + _ERROR_=1 + missing. The missing was already right.
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "jbessel", &.{ numV(-1), numV(1) })).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "ibessel", &.{ numV(-1), numV(1), numV(0) })).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);

    // in-range calls keep their values AND leave the flag alone (the tabulated
    // reference values above are the value control; this is the flag control)
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expectApproxEqAbs(@as(f64, 0.7651976866), (try dispatch(&e, "jbessel", &.{ numV(0), numV(1) })).num, 1e-8);
    try t.expectApproxEqAbs(@as(f64, 1.2660658778), (try dispatch(&e, "ibessel", &.{ numV(0), numV(1), numV(0) })).num, 1e-8);
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
    // a missing nu stays a plain missing — untouched, same scoping as SUBPAD
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "jbessel", &.{ Value.missing, numV(1) })).isMissing());
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}

test "NOTE-overflownonote: overflow→missing emits the math-domain NOTE (value unchanged)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // exp(710) overflows → missing WITH the domErr-worded NOTE (was silent).
    try t.expect((try dispatch(&e, "exp", &.{numV(710)})).isMissing());
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expectEqualStrings("exp: argument out of domain (result set to missing)", h.diags.list.items[0].message);
    // NOTE-only side-effect: _ERROR_ is NOT set (unlike domErr / div-by-zero).
    try t.expect(h.pdv.get("_error_") == null);

    // normal values: unchanged, no spurious NOTE.
    try t.expect((try dispatch(&e, "exp", &.{numV(1)})).num > 2.71);
    try t.expect((try dispatch(&e, "sqrt", &.{numV(4)})).num == 2);
    try t.expectEqual(@as(usize, 1), h.diags.count());

    // non-overflow domain errors keep their own domErr behavior (NOTE + _ERROR_).
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, "log", &.{numV(-1)})).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    try t.expectEqualStrings("log: argument out of domain (result set to missing)", h.diags.list.items[1].message);
}

test "GH#74b: functions.zig toStr/toNum log the SAS implicit-conversion NOTEs" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // num→char via substr(n,1,8) — the declared-length `c = n` path (parser
    // rewrites the assignment to substr), where toStr coerces the numeric arg.
    _ = try dispatch(&e, "substr", &.{ numV(42), numV(1), numV(8) });
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "converted to character") != null);

    // char→num via substr's position arg: toNum coerces the char "2".
    _ = try dispatch(&e, "substr", &.{ strV("abcdef"), strV("2") });
    try t.expectEqual(@as(usize, 2), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[1].message, "converted to numeric") != null);

    // unparsable char→num: BOTH the converted note AND the invalid-data note.
    _ = try dispatch(&e, "abs", &.{strV("xyz")});
    try t.expectEqual(@as(usize, 4), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[3].message, "Invalid numeric data, 'xyz'") != null);
}

test "NOTE-invalidnumdataloc: toNum's invalid-data NOTE omits the position, never freezes 0/0 (GH#78)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // The exact GH#78 path: scan's count argument coerces char→num through the
    // toNum leaf, which sees only the Value (the evaluator has no current line,
    // AST expressions carry no span) — so the NOTE must OMIT the position, not
    // print the frozen "at line 0 column 0." an external user quoted.
    _ = try dispatch(&e, "scan", &.{ strV("a:b:c"), strV(":"), numV(2) });
    try t.expectEqualStrings("Invalid numeric data, ':'.", h.diags.list.items[1].message);
    // The RENDERED log: plain "NOTE: …" — no "(L0)" tag, no position text.
    const log = try h.diags.render();
    try t.expect(std.mem.indexOf(u8, log, "NOTE: Invalid numeric data, ':'.\n") != null);
    try t.expect(std.mem.indexOf(u8, log, "(L0") == null);
    try t.expect(std.mem.indexOf(u8, log, "column 0") == null);
}

test "BUG-catnote: CAT-family num→char conversion logs NO note; other sites still do" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SAS 9.4 "CAT Function" (p.453-455): numeric items convert via BESTw. and
    // "SAS does not write a note to the log" — cat/cats/catt/catx stay silent
    // (GH#74c got this wrong). Values unchanged (BEST12, blank-stripped).
    try t.expectEqualStrings("1x", (try dispatch(&e, "cat", &.{ numV(1), strV("x") })).str);
    try t.expectEqualStrings("x42", (try dispatch(&e, "cats", &.{ strV("x"), numV(42) })).str);
    try t.expectEqualStrings("x42", (try dispatch(&e, "catt", &.{ strV("x"), numV(42) })).str);
    try t.expectEqualStrings("1|x", (try dispatch(&e, "catx", &.{ strV("|"), numV(1), strV("x") })).str);
    try t.expectEqual(@as(usize, 0), h.diags.count());

    // the NOTE survives OUTSIDE the CAT family — vvalue's numeric coercion.
    _ = try dispatch(&e, "vvalue", &.{numV(42)});
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "converted to character") != null);
}

test "BUG-putbarenumnote: PUT with a bare-numeric format spec logs NO num→char NOTE" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // bare spec `put(x, 8.2)`: the format engine result, no conversion note
    // (a quoted spec was already silent — same output, still no note).
    try t.expectEqualStrings("   42.00", (try dispatch(&e, "put", &.{ numV(42), numV(8.2) })).str);
    try t.expectEqualStrings("   42.00", (try dispatch(&e, "put", &.{ numV(42), strV("8.2") })).str);
    try t.expectEqual(@as(usize, 0), h.diags.count());

    // the NOTE still fires where a numeric is genuinely converted to data.
    _ = try dispatch(&e, "vvalue", &.{numV(42)});
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "converted to character") != null);
}

test "QA tick356 F4: INPUT/INPUTN/INPUTC with a bare-numeric informat spec log NO num→char NOTE" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // the reported shape: `input("123", 8.)` read the right value but logged a
    // conversion NOTE for the SPEC — the twin of BUG-putbarenumnote above, left on
    // toStr. The bare and named spellings must agree, and both must be silent.
    try t.expectEqual(@as(f64, 123), (try dispatch(&e, "input", &.{ strV("123"), numV(8.0) })).num);
    try t.expectEqual(@as(f64, 123), (try dispatch(&e, "input", &.{ strV("123"), strV("8.") })).num);
    try t.expectEqual(@as(f64, 123), (try dispatch(&e, "input", &.{ strV("123"), strV("best8.") })).num);
    try t.expectEqual(@as(f64, 456), (try dispatch(&e, "inputn", &.{ strV("456"), numV(8.0) })).num);
    try t.expectEqualStrings("xy", (try dispatch(&e, "inputc", &.{ strV("xy"), strV("$2.") })).str);
    try t.expectEqual(@as(usize, 0), h.diags.count());

    // the DATA argument is NOT a spec: a numeric there is a genuine implicit
    // conversion and must still note (the fix must not silence the real one).
    _ = try dispatch(&e, "input", &.{ numV(123), strV("8.") });
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "converted to character") != null);
}

test "Phase F net-new: spedis/compged/vtypex/vnamex + system fns" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SPEDIS(query, keyword): each row isolates one operation, values floored per doc
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "spedis", &.{ strV("fuzzy"), strV("fuzzy") })).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "spedis", &.{ strV("fuzy"), strV("fuzzy") })).num); // singlet
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "spedis", &.{ strV("fuuzzy"), strV("fuzzy") })).num); // doublet
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "spedis", &.{ strV("fzuzy"), strV("fuzzy") })).num); // swap
    try t.expectEqual(@as(f64, 12), (try dispatch(&e, "spedis", &.{ strV("fuzz"), strV("fuzzy") })).num); // truncate
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "spedis", &.{ strV("fuzzys"), strV("fuzzy") })).num); // append
    try t.expectEqual(@as(f64, 12), (try dispatch(&e, "spedis", &.{ strV("fzzy"), strV("fuzzy") })).num); // delete
    try t.expectEqual(@as(f64, 16), (try dispatch(&e, "spedis", &.{ strV("fluzzy"), strV("fuzzy") })).num); // insert
    try t.expectEqual(@as(f64, 20), (try dispatch(&e, "spedis", &.{ strV("fizzy"), strV("fuzzy") })).num); // replace
    try t.expectEqual(@as(f64, 25), (try dispatch(&e, "spedis", &.{ strV("uzzy"), strV("fuzzy") })).num); // firstdel
    try t.expectEqual(@as(f64, 33), (try dispatch(&e, "spedis", &.{ strV("pfuzzy"), strV("fuzzy") })).num); // firstins
    try t.expectEqual(@as(f64, 40), (try dispatch(&e, "spedis", &.{ strV("wuzzy"), strV("fuzzy") })).num); // firstrep

    // COMPGED(string1, string2): SAS "Generalized Edit Distance" example rows
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "compged", &.{ strV("baboon"), strV("baboon") })).num);
    try t.expectEqual(@as(f64, 100), (try dispatch(&e, "compged", &.{ strV("baXboon"), strV("baboon") })).num); // insert
    try t.expectEqual(@as(f64, 100), (try dispatch(&e, "compged", &.{ strV("baoon"), strV("baboon") })).num); // delete
    try t.expectEqual(@as(f64, 100), (try dispatch(&e, "compged", &.{ strV("baXoon"), strV("baboon") })).num); // replace
    try t.expectEqual(@as(f64, 50), (try dispatch(&e, "compged", &.{ strV("baboonX"), strV("baboon") })).num); // append
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "compged", &.{ strV("baboo"), strV("baboon") })).num); // truncate
    try t.expectEqual(@as(f64, 20), (try dispatch(&e, "compged", &.{ strV("babboon"), strV("baboon") })).num); // double
    try t.expectEqual(@as(f64, 20), (try dispatch(&e, "compged", &.{ strV("babon"), strV("baboon") })).num); // single
    try t.expectEqual(@as(f64, 20), (try dispatch(&e, "compged", &.{ strV("baobon"), strV("baboon") })).num); // swap
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "compged", &.{ strV("bab oon"), strV("baboon") })).num); // blank
    try t.expectEqual(@as(f64, 30), (try dispatch(&e, "compged", &.{ strV("bab,oon"), strV("baboon") })).num); // punctuation
    try t.expectEqual(@as(f64, 200), (try dispatch(&e, "compged", &.{ strV("bXaoon"), strV("baboon") })).num); // insert+delete
    try t.expectEqual(@as(f64, 200), (try dispatch(&e, "compged", &.{ strV("Xbaboon"), strV("baboon") })).num); // finsert
    try t.expectEqual(@as(f64, 120), (try dispatch(&e, "compged", &.{ strV("aboon"), strV("baboon") })).num); // swap+delete
    try t.expectEqual(@as(f64, 200), (try dispatch(&e, "compged", &.{ strV("Xaboon"), strV("baboon") })).num); // freplace
    try t.expectEqual(@as(f64, 300), (try dispatch(&e, "compged", &.{ strV("axoon"), strV("baboon") })).num); // fdelete+replace
    try t.expectEqual(@as(f64, 120), (try dispatch(&e, "compged", &.{ strV("baby"), strV("baboon") })).num); // replace+truncate*2
    try t.expectEqual(@as(f64, 200), (try dispatch(&e, "compged", &.{ strV("balloon"), strV("baboon") })).num); // replace+insert
    // cutoff caps the result; "i" modifier ignores case
    try t.expectEqual(@as(f64, 50), (try dispatch(&e, "compged", &.{ strV("baXboon"), strV("baboon"), numV(50) })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "compged", &.{ strV("BABOON"), strV("baboon"), strV("i") })).num);

    // VTYPEX / VNAMEX resolve a variable by the NAME the argument spells (case-insensitive)
    try h.pdv.set("Age", .{ .num = 40 });
    try h.pdv.set("Name", .{ .str = "x" });
    try t.expectEqualStrings("N", (try dispatch(&e, "vtypex", &.{strV("age")})).str);
    try t.expectEqualStrings("C", (try dispatch(&e, "vtypex", &.{strV("NAME")})).str);
    try t.expectEqualStrings("Age", (try dispatch(&e, "vnamex", &.{strV("age")})).str); // canonical case
    try t.expectEqualStrings(" ", (try dispatch(&e, "vtypex", &.{strV("nope")})).str); // absent

    // VVALUE: a value rendered with its default format (compact, unformatted).
    try t.expectEqualStrings("3.14", (try dispatch(&e, "vvalue", &.{numV(3.14)})).str);
    try t.expectEqualStrings("hello", (try dispatch(&e, "vvalue", &.{strV("hello")})).str);
    try t.expectEqualStrings("0", (try dispatch(&e, "vvalue", &.{numV(0)})).str);

    // VLENGTH: storage length — 8 for numeric, value width for character.
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "vlength", &.{numV(42)})).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "vlength", &.{strV("hello")})).num);
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "vlength", &.{numV(0)})).num);

    // VFORMATX / VVALUEX / VLABELX are UN-TICKED: through the real pipeline the
    // FORMAT statement's spec lives in exec's `formats` list and is only lazily
    // copied to pdv.Var.format at output time (exec.zig:1120), and LABEL is parsed
    // then discarded (no Var.label field) — neither is reachable from functions.zig,
    // so these return the default/name, not the assigned format/label. Making them
    // correct needs an exec.zig change (eager pdv.setFormat + a stored label), which
    // is out of this file's scope. The code stays as a correct-once-populated stub.

    // system fns: correct in a base session with no options / no prior error
    try t.expectEqualStrings("", (try dispatch(&e, "sysparm", &.{})).str);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "sysrc", &.{})).num);
    try t.expectEqualStrings("", (try dispatch(&e, "sysmsg", &.{})).str);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "wto", &.{strV("hi")})).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "sleep", &.{numV(5)})).num); // returns n, no actual delay
    try t.expectEqual(@as(f64, 0.25), (try dispatch(&e, "sleep", &.{ numV(0.25), numV(0.001) })).num);
}

test "Phase F net-new: FINANCE umbrella (closed-form modes vs SAS doc)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;

    // dollar fraction conversions (inverse of each other)
    try near((try dispatch(&e, "finance", &.{ strV("dollarde"), numV(1.125), numV(16) })).num, 1.78125, 1e-9);
    try near((try dispatch(&e, "finance", &.{ strV("dollarfr"), numV(1.125), numV(16) })).num, 1.02, 1e-9);
    // future value of a schedule of rates
    try near((try dispatch(&e, "finance", &.{ strV("fvschedule"), numV(1), numV(0.09), numV(0.11), numV(0.10) })).num, 1.33089, 1e-5);
    // rate conversions (EFFECT/NOMINAL + the EFFRATE/NOMRATE aliases)
    try near((try dispatch(&e, "finance", &.{ strV("effect"), numV(0.0525), numV(4) })).num, 0.053543, 1e-5);
    try near((try dispatch(&e, "finance", &.{ strV("nominal"), numV(0.08), numV(4) })).num, 0.0777061876, 1e-8);
    try near((try dispatch(&e, "finance", &.{ strV("effrate"), numV(0.06), numV(12) })).num, 0.0616778119, 1e-8);
    try near((try dispatch(&e, "finance", &.{ strV("nomrate"), numV(0.0616778119), numV(12) })).num, 0.06, 1e-8);
    // NPER (FINANCE-modes part 2): inverse of PMT(0.005,360,100000)=-599.5505
    try near((try dispatch(&e, "finance", &.{ strV("nper"), numV(0.005), numV(-599.5505), numV(100000) })).num, 360, 1e-2);
    try near((try dispatch(&e, "finance", &.{ strV("nper"), numV(0), numV(-100), numV(1000) })).num, 10, 1e-9); // no interest
    // annuity FV / PMT
    try near((try dispatch(&e, "finance", &.{ strV("fv"), numV(0.06 / 12.0), numV(10), numV(-200), numV(-500), numV(1) })).num, 2581.4033741, 1e-4);
    try near((try dispatch(&e, "finance", &.{ strV("pmt"), numV(0.08), numV(5), numV(91), numV(3), numV(0) })).num, -23.30290673, 1e-6);
    // cash-flow NPV / IRR / MIRR
    try near((try dispatch(&e, "finance", &.{ strV("npv"), numV(0.08), numV(200), numV(1000), numV(0) })).num, 1042.5240055, 1e-4);
    try near((try dispatch(&e, "finance", &.{ strV("irr"), numV(-70000), numV(12000), numV(15000), numV(18000), numV(21000), numV(26000) })).num, 0.086630948, 1e-7);
    try near((try dispatch(&e, "finance", &.{ strV("mirr"), numV(-1000), numV(3000), numV(4000), numV(5000), numV(0.08), numV(0.10) })).num, 1.3531420172, 1e-8);
    // depreciation
    try near((try dispatch(&e, "finance", &.{ strV("ddb"), numV(2400), numV(300), numV(10 * 365), numV(1), Value.missing })).num, 1.3150684932, 1e-8);
    try near((try dispatch(&e, "finance", &.{ strV("db"), numV(1000000), numV(100000), numV(6), numV(2), numV(7) })).num, 259639.41667, 1e-3);
    // SLN / SYD (definitional)
    try near((try dispatch(&e, "finance", &.{ strV("sln"), numV(2400), numV(300), numV(10) })).num, 210, 1e-9);
    try near((try dispatch(&e, "finance", &.{ strV("syd"), numV(2400), numV(300), numV(10), numV(1) })).num, 381.8181818, 1e-6);
    // an unimplemented (bond) mode → missing, not a crash
    try t.expect((try dispatch(&e, "finance", &.{ strV("price"), numV(1), numV(2) })).isMissing());
}

test "Phase F net-new: TIMEVALUE / SAVINGS (variable-rate time value)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;

    const d2000 = eval.dateConst("01JAN2000").?;
    const d2001 = eval.dateConst("01JAN2001").?;
    const d2005 = eval.dateConst("01JAN2005").?;
    const jul2000 = eval.dateConst("01JUL2000").?;

    // TIMEVALUE — SAS doc example values (nominal rate, monthly compounding)
    try near((try dispatch(&e, "timevalue", &.{ numV(d2001), numV(d2000), numV(1000), strV("MONTH"), numV(d2000), numV(10) })).num, 1104.7130674, 1e-4);
    try near((try dispatch(&e, "timevalue", &.{ numV(d2001), numV(d2000), numV(1000), strV("MONTH"), numV(d2000), numV(10), numV(jul2000), numV(20) })).num, 1160.6365778, 1e-4);
    // date-rate pairs need not be sorted → same result
    try near((try dispatch(&e, "timevalue", &.{ numV(d2001), numV(d2000), numV(1000), strV("MONTH"), numV(jul2000), numV(20), numV(d2000), numV(10) })).num, 1160.6365778, 1e-4);

    // SAVINGS — $300 monthly for 24 months, quarterly compounding at 4%. base3's
    // window ends before the last deposits, so deposits dated after base don't count.
    try near((try dispatch(&e, "savings", &.{ numV(d2005), numV(d2000), numV(300), numV(24), strV("MONTH"), strV("QUARTER"), numV(d2000), numV(4.00) })).num, 8458.794159, 1e-3);
    try near((try dispatch(&e, "savings", &.{ numV(d2001), numV(d2000), numV(300), numV(24), strV("MONTH"), strV("QUARTER"), numV(d2000), numV(4.00) })).num, 3978.6903712, 1e-3);
}

test "numeric aggregates ignore missing; empty→missing" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "SUM", &.{ numV(1), numV(2), Value.missing, numV(3) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "mean", &.{ numV(1), numV(3), Value.missing })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "min", &.{ numV(3), numV(1), Value.missing })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "max", &.{ numV(3), numV(1), Value.missing })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "n", &.{ numV(3), numV(1), Value.missing })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "nmiss", &.{ numV(3), numV(1), Value.missing })).num);
    try t.expect((try dispatch(&e, "sum", &.{ Value.missing, Value.missing })).isMissing());
}

test "math family: exp/log/trig/atan2/sign/fact/comb/perm/digamma (Phase F)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const approx = struct {
        fn eq(got: f64, want: f64) !void {
            try t.expect(@abs(got - want) < 1e-9);
        }
    }.eq;
    try approx((try dispatch(&e, "exp", &.{numV(0)})).num, 1);
    try approx((try dispatch(&e, "log", &.{numV(1)})).num, 0);
    try approx((try dispatch(&e, "log10", &.{numV(1000)})).num, 3);
    try approx((try dispatch(&e, "log2", &.{numV(8)})).num, 3);
    try approx((try dispatch(&e, "sin", &.{numV(0)})).num, 0);
    try approx((try dispatch(&e, "cos", &.{numV(0)})).num, 1);
    try approx((try dispatch(&e, "atan2", &.{ numV(1), numV(1) })).num, std.math.pi / 4.0);
    try approx((try dispatch(&e, "arcos", &.{numV(1)})).num, 0);
    try approx((try dispatch(&e, "tanh", &.{numV(0)})).num, 0);
    try t.expectEqual(@as(f64, -1), (try dispatch(&e, "sign", &.{numV(-42)})).num);
    try t.expectEqual(@as(f64, 720), (try dispatch(&e, "fact", &.{numV(6)})).num);
    try t.expectEqual(@as(f64, 15), (try dispatch(&e, "comb", &.{ numV(6), numV(2) })).num);
    // COMB multinomial (BUG-combmulti): comb(10,2,3)=2520; invalid split → missing
    try t.expectEqual(@as(f64, 2520), (try dispatch(&e, "comb", &.{ numV(10), numV(2), numV(3) })).num);
    try t.expectEqual(@as(f64, 2520), (try dispatch(&e, "comb", &.{ numV(10), numV(2), numV(3), numV(5) })).num);
    try t.expect((try dispatch(&e, "comb", &.{ numV(5), numV(2), numV(4) })).isMissing());
    try t.expectEqual(@as(f64, 30), (try dispatch(&e, "perm", &.{ numV(6), numV(2) })).num);
    try t.expect(@abs((try dispatch(&e, "digamma", &.{numV(1)})).num - (-0.5772156649)) < 1e-4); // -γ (asymptotic approx)
    // out-of-domain → missing
    try t.expect((try dispatch(&e, "log", &.{numV(-1)})).isMissing());
    try t.expect((try dispatch(&e, "arcos", &.{numV(2)})).isMissing());
}

test "unary table (TASTE-unarytable): each folded fn maps to its own op" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const approx = struct {
        fn eq(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.eq;
    // one distinguishing value per folded fn — a swapped switch arm fails here
    try approx((try dispatch(&e, "trigamma", &.{numV(1)})).num, std.math.pi * std.math.pi / 6.0, 1e-4);
    try approx((try dispatch(&e, "lgamma", &.{numV(4)})).num, @log(6.0), 1e-9);
    try approx((try dispatch(&e, "gamma", &.{numV(5)})).num, 24, 1e-6);
    try approx((try dispatch(&e, "lfact", &.{numV(3)})).num, @log(6.0), 1e-9);
    try approx((try dispatch(&e, "erf", &.{numV(1)})).num, 0.8427007929, 1e-6);
    try approx((try dispatch(&e, "erfc", &.{numV(1)})).num, 0.1572992071, 1e-6);
    try approx((try dispatch(&e, "probnorm", &.{numV(0)})).num, 0.5, 1e-12);
    try approx((try dispatch(&e, "probit", &.{numV(0.975)})).num, 1.959963985, 1e-6);
    try approx((try dispatch(&e, "log1px", &.{numV(0)})).num, 0, 1e-12);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "fuzz", &.{numV(3.0 + 1e-13)})).num);
    try approx((try dispatch(&e, "airy", &.{numV(0)})).num, 0.3550280539, 1e-6); // Ai(0)=3^(-2/3)/Γ(2/3)
    try approx((try dispatch(&e, "dairy", &.{numV(0)})).num, -0.2588194038, 1e-6); // Ai′(0)
    try approx((try dispatch(&e, "logistic", &.{numV(0)})).num, 0.5, 1e-12);
    // domain checks preserved through the table
    try t.expect((try dispatch(&e, "lgamma", &.{numV(0)})).isMissing());
    try t.expect((try dispatch(&e, "probit", &.{numV(1)})).isMissing());
    try t.expect((try dispatch(&e, "log1px", &.{numV(-1)})).isMissing());
    try t.expect((try dispatch(&e, "gamma", &.{numV(-2)})).isMissing());
    try t.expect((try dispatch(&e, "lfact", &.{numV(-1)})).isMissing());
    // missing propagates; bad arity reports
    try t.expect((try dispatch(&e, "erf", &.{Value.missing})).isMissing());
    try t.expect((try dispatch(&e, "logistic", &.{ numV(1), numV(2) })).isMissing());
}

test "scalar numeric: abs/int/round/sqrt/mod/ceil/floor, missing propagates" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "abs", &.{numV(-5)})).num);
    // array bounds: parser passes the element count; 1-based (G-dim)
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "dim", &.{numV(5)})).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "hbound", &.{numV(5)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "lbound", &.{numV(5)})).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "dim", &.{ numV(5), numV(1) })).num); // dim(a,1)
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "int", &.{numV(3.9)})).num);
    try t.expectEqual(@as(f64, 2.5), (try dispatch(&e, "round", &.{ numV(2.46), numV(0.1) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "round", &.{numV(2.6)})).num);
    // .x5 boundaries round UP (away from zero) despite f64 error (BUG-roundfuzz)
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "round", &.{numV(2.5)})).num);
    try t.expectEqual(@as(f64, -3), (try dispatch(&e, "round", &.{numV(-2.5)})).num);
    try t.expectEqual(@as(f64, 0.13), (try dispatch(&e, "round", &.{ numV(0.125), numV(0.01) })).num);
    try t.expectEqual(@as(f64, -0.13), (try dispatch(&e, "round", &.{ numV(-0.125), numV(0.01) })).num);
    try t.expectEqual(@as(f64, 1.05), (try dispatch(&e, "round", &.{ numV(1.045), numV(0.01) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "round", &.{numV(2.4)})).num); // non-boundary unaffected
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "sqrt", &.{numV(16)})).num);
    try t.expect((try dispatch(&e, "sqrt", &.{numV(-1)})).isMissing());
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "mod", &.{ numV(5), numV(3) })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "ceil", &.{numV(3.2)})).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "floor", &.{numV(3.8)})).num);
    // fuzz: 0.3/0.1 = 2.9999…996 in f64; INT/CEIL/FLOOR snap to 3 (SAS 9.4)
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "floor", &.{numV(2.9999999999999996)})).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "int", &.{numV(2.9999999999999996)})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "floorz", &.{numV(2.9999999999999996)})).num); // no fuzz
    try t.expect((try dispatch(&e, "abs", &.{Value.missing})).isMissing());
}

test "round to a decimal unit is clean; BESTw. keeps decimals (PROG-vs)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // (97.16 - 32) * 5 / 9 = 36.2; round to 0.1 must be exactly 36.2, not 36.8000004
    const c = (try dispatch(&e, "round", &.{ numV((97.16 - 32) * 5.0 / 9.0), numV(0.1) })).num;
    try t.expectEqual(@as(f64, 36.2), c);
    // the classic 368*0.1 artifact is cleaned
    try t.expectEqual(@as(f64, 36.8), (try dispatch(&e, "round", &.{ numV(36.83), numV(0.1) })).num);
    try t.expectEqual(@as(f64, 2.5), (try dispatch(&e, "round", &.{ numV(2.46), numV(0.1) })).num);

    // put(x, best8.) shows the natural form (decimals kept), not w. (d=0)
    try t.expectEqualStrings("36.2", std.mem.trim(u8, (try dispatch(&e, "put", &.{ numV(36.2), strV("best8.") })).str, " "));
    try t.expectEqualStrings("1234.5", std.mem.trim(u8, (try dispatch(&e, "put", &.{ numV(1234.5), strV("best8.") })).str, " "));
    try t.expectEqualStrings("36", std.mem.trim(u8, (try dispatch(&e, "put", &.{ numV(36), strV("best8.") })).str, " "));
}

test "string: upcase/lowcase/trim/strip/left/length/substr/index" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    try t.expectEqualStrings("ABC", (try dispatch(&e, "upcase", &.{strV("aBc")})).str);
    try t.expectEqualStrings("abc", (try dispatch(&e, "lowcase", &.{strV("aBc")})).str);
    try t.expectEqualStrings("hi", (try dispatch(&e, "trim", &.{strV("hi   ")})).str);
    try t.expectEqualStrings(" ", (try dispatch(&e, "trim", &.{strV("   ")})).str); // all-blank → one blank
    try t.expectEqualStrings("hi", (try dispatch(&e, "strip", &.{strV("  hi  ")})).str);
    try t.expectEqualStrings("hi ", (try dispatch(&e, "left", &.{strV(" hi")})).str); // length preserved
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "length", &.{strV("abc  ")})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "length", &.{strV("   ")})).num); // blank → 1
    try t.expectEqualStrings("cde", (try dispatch(&e, "substr", &.{ strV("abcde"), numV(3) })).str);
    try t.expectEqualStrings("bc", (try dispatch(&e, "substr", &.{ strV("abcde"), numV(2), numV(2) })).str);
    // guards: absurd pos/len must clamp, not panic on @intFromFloat overflow
    try t.expectEqualStrings("", (try dispatch(&e, "substr", &.{ strV("abcde"), numV(1e19) })).str);
    try t.expectEqualStrings("abcde", (try dispatch(&e, "substr", &.{ strV("abcde"), numV(1), numV(1e19) })).str);
    try t.expectEqualStrings("abcde", (try dispatch(&e, "substr", &.{ strV("abcde"), numV(-1e19) })).str);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "index", &.{ strV("abcde"), strV("cd") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "index", &.{ strV("abcde"), strV("zz") })).num);

    // scan: nth word, consecutive delims collapse, negative n from the right
    try t.expectEqualStrings("alpha", (try dispatch(&e, "scan", &.{ strV("alpha beta gamma"), numV(1) })).str);
    try t.expectEqualStrings("beta", (try dispatch(&e, "scan", &.{ strV("alpha beta gamma"), numV(2) })).str);
    try t.expectEqualStrings("gamma", (try dispatch(&e, "scan", &.{ strV("alpha beta gamma"), numV(-1) })).str);
    try t.expectEqualStrings("", (try dispatch(&e, "scan", &.{ strV("alpha beta"), numV(9) })).str); // out of range
    try t.expectEqualStrings("b", (try dispatch(&e, "scan", &.{ strV("a,,b"), numV(2), strV(",") })).str); // collapse
    // BUG-scandelim: one shared ASCII default set — '>' and TAB are NOT delimiters
    try t.expectEqualStrings("", (try dispatch(&e, "scan", &.{ strV("x>y"), numV(2) })).str);
    try t.expectEqualStrings("", (try dispatch(&e, "scan", &.{ strV("a\tb"), numV(2) })).str);
    // BUG-scanmodifiers: `d` adds the digit class, `k` keeps only the listed chars
    try t.expectEqualStrings("cd", (try dispatch(&e, "scan", &.{ strV("ab12cd"), numV(2), strV(" "), strV("d") })).str);
    try t.expectEqualStrings("2", (try dispatch(&e, "scan", &.{ strV("a1b2c3"), numV(2), strV("123"), strV("k") })).str);
    // unsupported modifier → ERROR diagnostic + BLANK CHARACTER, never a silent
    // no-op (D-002) and never a numeric missing (BUG-scanmissingtype: the ERROR
    // is the point, but SCAN still has to hand back a character value).
    const dbase = h.diags.count();
    try t.expectEqualStrings("", (try dispatch(&e, "scan", &.{ strV("a b"), numV(1), strV(" "), strV("q") })).str);
    try t.expectEqual(dbase + 1, h.diags.count());

    // find: 1-based position, start arg, 0 when absent, `i` case-insensitive
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("bc") })).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("bc"), numV(3) })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("zz") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "find", &.{ strV("ABC"), strV("abc"), strV("i") })).num);
    // negative start → backward search from |start| (BUG-findneg)
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("bc"), numV(-6) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("bc"), numV(-4) })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("abc"), numV(-10) })).num); // clamps
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "find", &.{ strV("abcabc"), strV("zz"), numV(-6) })).num);

    // tranwrd: replace every occurrence
    try t.expectEqualStrings("fish dog fish", (try dispatch(&e, "tranwrd", &.{ strV("cat dog cat"), strV("cat"), strV("fish") })).str);
    try t.expectEqualStrings("xyz", (try dispatch(&e, "tranwrd", &.{ strV("xyz"), strV(""), strV("q") })).str); // empty target
}

test "BUG-scanmissingtype: EVERY SCAN exit is a CHARACTER value, never a numeric missing" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SAS 9.4 Functions and CALL Routines: Reference, 5th ed., p.1462 — SCAN
    // "Returns the nth word from a character string", so a no-match / invalid
    // count is a BLANK CHARACTER, not `.`. The union tag is the assertion here:
    // a numeric missing would flip the receiving variable's type and make
    // `put (x) ($char10.);` a hard ERROR (see tests/corpus/scan_missing_type.sas).
    const blanks = [_]Value{
        try dispatch(&e, "scan", &.{ strV("a b c"), Value.missing }), // missing count — was `.`
        try dispatch(&e, "scan", &.{ strV("a:b:c"), strV(":"), numV(2) }), // #78: ':' in the count slot
        try dispatch(&e, "scan", &.{ strV("a b c"), numV(9) }), // count past the end
        try dispatch(&e, "scan", &.{ strV("a b c"), numV(0) }), // count 0
        try dispatch(&e, "scan", &.{ strV("a b c"), numV(-9) }), // negative past the start
        try dispatch(&e, "scan", &.{ strV("a b c"), numV(1e19) }), // count too big for i64
        try dispatch(&e, "scan", &.{ strV(""), numV(1) }), // empty source
        try dispatch(&e, "scan", &.{ Value.missing, numV(1) }), // missing source
    };
    for (blanks) |v| {
        try t.expect(v == .str); // the union TAG is the whole point of this ticket
        try t.expectEqualStrings("", std.mem.trim(u8, v.str, " "));
    }

    // The fail-loud arms still ERROR (D-002) — and still hand back a character.
    const dbase = h.diags.count();
    const bad_mod = try dispatch(&e, "scan", &.{ strV("a b"), numV(1), strV(" "), strV("q") });
    try t.expect(bad_mod == .str);
    const e_mod = try dispatch(&e, "scan", &.{ strV("a b"), numV(1), strV(" "), strV("e") }); // FINDW-only
    try t.expect(e_mod == .str);
    // COMPRESS is a character function too, same one-line class.
    const cmp = try dispatch(&e, "compress", &.{ strV("a b"), strV(" "), strV("q") });
    try t.expect(cmp == .str);
    try t.expectEqual(dbase + 3, h.diags.count());

    // The correct 3- and 4-arg calls are untouched: `count` stays the SECOND
    // argument and `character-list` the THIRD (GH#78 claimed otherwise — it was
    // wrong, and closed as such).
    try t.expectEqualStrings("a", (try dispatch(&e, "scan", &.{ strV("a:b:c"), numV(1), strV(":") })).str);
    try t.expectEqualStrings("b", (try dispatch(&e, "scan", &.{ strV("a:b:c"), numV(2), strV(":") })).str);
    try t.expectEqualStrings("c", (try dispatch(&e, "scan", &.{ strV("a:b:c"), numV(-1), strV(":") })).str);
    try t.expectEqualStrings("b", (try dispatch(&e, "scan", &.{ strV("a b c"), numV(2) })).str);
    try t.expectEqualStrings("b", (try dispatch(&e, "scan", &.{ strV("a.b,c"), numV(2), strV(".,"), strV("o") })).str);
}

test "coercion across the num/char boundary" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // char in a numeric slot parses
    try t.expectEqual(@as(f64, 15), (try dispatch(&e, "sum", &.{ strV("10"), numV(5) })).num);
    // numeric in a char slot auto-converts BEST12. RIGHT-JUSTIFIED (Language Reference: Concepts p.124,
    // BUG-numcharwidth): trim drops only TRAILING blanks, so the 10 leading pad
    // blanks survive — the classic SAS gotcha behind the trim(left(n)) idiom
    try t.expectEqualStrings("          14", (try dispatch(&e, "trim", &.{numV(14)})).str);
    // input applies the informat (INFEXPR): numeric, dates, comma
    try t.expectEqual(@as(f64, 42), (try dispatch(&e, "input", &.{ strV("42"), strV("best12.") })).num);
    try t.expectEqual(@as(f64, 14), (try dispatch(&e, "input", &.{ strV("15JAN1960"), strV("date9.") })).num);
    try t.expectEqual(@as(f64, 19068), (try dispatch(&e, "input", &.{ strV("16 mar 2012"), strV("date11.") })).num); // BUG-dateblanksep
    try t.expectEqual(@as(f64, 14), (try dispatch(&e, "input", &.{ strV("1960-01-15"), strV("yymmdd10.") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "input", &.{ strV("01JAN1960"), strV("date9.") })).num); // epoch
    try t.expectEqual(@as(f64, 1234), (try dispatch(&e, "input", &.{ strV("1,234"), strV("comma8.") })).num);
    // BUG-commaxinformat: INPUT() honors the European roles (was missing) —
    // routed through format.readNumeric like the INPUT statement.
    try t.expectEqual(@as(f64, 1234.56), (try dispatch(&e, "input", &.{ strV("1.234,56"), strV("commax10.2") })).num);
    try t.expectEqual(@as(f64, 1234.56), (try dispatch(&e, "input", &.{ strV("$1.234,56"), strV("dollarx12.2") })).num);
    try t.expectEqual(@as(f64, 1234.56), (try dispatch(&e, "input", &.{ strV("1,234.56"), strV("nlnum12.2") })).num);
    try t.expectEqual(@as(f64, 1234.56), (try dispatch(&e, "input", &.{ strV("1,234.56"), strV("comma10.2") })).num); // US unchanged
    // BUG-datetimeinputfn: input() must parse datetime/ISO-8601/time informats
    // (25DEC2024 = day 23735; 10:30:00 = 37800s; datetime = 23735*86400 + 37800)
    const want_dt: f64 = @floatFromInt(23735 * 86400 + 37800);
    try t.expectEqual(want_dt, (try dispatch(&e, "input", &.{ strV("25DEC2024:10:30:00"), strV("datetime20.") })).num);
    try t.expectEqual(want_dt, (try dispatch(&e, "input", &.{ strV("2024-12-25T10:30:00"), strV("e8601dt.") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "input", &.{ strV("01JAN1960:00:00:00"), strV("datetime.") })).num); // epoch
    try t.expectEqual(@as(f64, 37800), (try dispatch(&e, "input", &.{ strV("10:30:00"), strV("time8.") })).num); // time-of-day secs
    try t.expectEqualStrings("       7", (try dispatch(&e, "put", &.{ numV(7), strV("8.") })).str);

    // BUG-infwidth: informat width truncates the source, and `d` implies decimals
    try t.expectEqual(@as(f64, 123), (try dispatch(&e, "input", &.{ strV("12345"), strV("3.") })).num);
    try t.expectEqual(@as(f64, 12.34), (try dispatch(&e, "input", &.{ strV("1234"), strV("5.2") })).num);
    try t.expectEqual(@as(f64, 12.5), (try dispatch(&e, "input", &.{ strV("12.5"), strV("6.2") })).num); // explicit point wins
    // BUG-putinf: overflow on input / put → missing, never "inf"
    try t.expect((try dispatch(&e, "input", &.{ strV("1e400"), strV("12.") })).isMissing());
    try t.expect(std.mem.indexOf(u8, (try dispatch(&e, "put", &.{ numV(std.math.inf(f64)), strV("8.") })).str, "inf") == null);
    // BUG-infdate: an invalid day is rejected, not rolled over
    try t.expect((try dispatch(&e, "input", &.{ strV("31FEB2020"), strV("date9.") })).isMissing());
    try t.expect((try dispatch(&e, "input", &.{ strV("2020-02-31"), strV("yymmdd10.") })).isMissing());
    try t.expectEqual(@as(f64, 14), (try dispatch(&e, "input", &.{ strV("1960-01-15"), strV("yymmdd10.") })).num); // valid still works
}

test "unknown function and bad arity report and yield missing" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    try t.expect((try dispatch(&e, "frobnicate", &.{numV(1)})).isMissing());
    try t.expect(h.diags.hasErrors());

    try t.expect((try dispatch(&e, "abs", &.{ numV(1), numV(2) })).isMissing()); // wrong arity
    try t.expect(h.diags.count() >= 2);
}

test "catx strips and joins non-blank args; yrdif over the three bases" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // catx: strip each value, drop the blank/empty ones, join with the separator
    try t.expectEqualStrings("John Smith", (try dispatch(&e, "catx", &.{ strV(" "), strV("John"), strV(" "), strV("Smith") })).str);
    try t.expectEqualStrings("A-B-C", (try dispatch(&e, "catx", &.{ strV("-"), strV("A"), strV(""), strV("B"), strV("C") })).str);

    // compress: remove blanks (no chars), a char set, and keep-mode / class mods
    try t.expectEqualStrings("Abnormal(NCS)", (try dispatch(&e, "compress", &.{strV("Abnormal (NCS)")})).str); // blanks
    try t.expectEqualStrings("Abnormal(NCS)", (try dispatch(&e, "compress", &.{ strV("Abnormal (NCS)"), strV(" ") })).str);
    try t.expectEqualStrings("abc", (try dispatch(&e, "compress", &.{ strV("a1b2c3"), strV("123") })).str); // remove digits
    try t.expectEqualStrings("123", (try dispatch(&e, "compress", &.{ strV("a1b2c3"), strV("123"), strV("k") })).str); // keep
    try t.expectEqualStrings("abc", (try dispatch(&e, "compress", &.{ strV("a1 b2!c3"), strV(""), strV("sdp") })).str); // strip classes

    // yrdif: SAS day serials 21915=01JAN2020, 22281=01JAN2021, 22646=01JAN2022,
    // 22097=01JUL2020. Whole-year and half-year cases land exactly.
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "yrdif", &.{ numV(21915), numV(22281), strV("ACT/ACT") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "yrdif", &.{ numV(22281), numV(22646), strV("ACT/365") })).num);
    try t.expectEqual(@as(f64, 0.5), (try dispatch(&e, "yrdif", &.{ numV(21915), numV(22097), strV("30/360") })).num);
    // ACT/360: 22371=01APR2021, so 90 actual days / 360 = 0.25 (was silently ACT/ACT)
    try t.expectEqual(@as(f64, 0.25), (try dispatch(&e, "yrdif", &.{ numV(22281), numV(22371), strV("ACT/360") })).num);

    // AGE: exact anniversaries must be whole years (was 1.0001… via ISDA fallback).
    // 21929=15JAN2020, 22295=15JAN2021, 22660=15JAN2022.
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "yrdif", &.{ numV(21929), numV(22295), strV("AGE") })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "yrdif", &.{ numV(21929), numV(22660), strV("AGE") })).num);
    try t.expectEqual(@as(f64, -1), (try dispatch(&e, "yrdif", &.{ numV(22295), numV(21929), strV("AGE") })).num); // signed
    // AGE fraction: 01JAN2020→01JUL2020 = 182 days over the 366-day anniversary span.
    try t.expectApproxEqAbs(@as(f64, 182.0 / 366.0), (try dispatch(&e, "yrdif", &.{ numV(21915), numV(22097), strV("AGE") })).num, 1e-9);

    // datdif: ACT/ACT is the serial diff; 30/360 the 30-day-month day count
    try t.expectEqual(@as(f64, 60), (try dispatch(&e, "datdif", &.{ numV(21915), numV(21975), strV("ACT/ACT") })).num);
    try t.expectEqual(@as(f64, 60), (try dispatch(&e, "datdif", &.{ numV(21945), numV(22005), strV("30/360") })).num); // 31JAN→31MAR

    // coalesce / coalescec: first non-missing / non-blank
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "coalesce", &.{ Value.missing, numV(5), numV(9) })).num);
    try t.expect((try dispatch(&e, "coalesce", &.{ Value.missing, Value.missing })).isMissing());
    try t.expectEqualStrings("hi", (try dispatch(&e, "coalescec", &.{ strV(""), strV("hi") })).str);
}

test "BUG-datdifbasis: unsupported basis → NOTE + _ERROR_ + missing; valid bases unchanged" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // 21915=01JAN2020, 22097=01JUL2020 (182 days apart).
    try h.pdv.set("_error_", .{ .num = 0 });

    // ACT/360 is a YRDIF basis but NOT a DATDIF basis → missing + NOTE (was 182).
    try t.expect((try dispatch(&e, "datdif", &.{ numV(21915), numV(22097), strV("ACT/360") })).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "Invalid basis 'ACT/360' in DATDIF") != null);

    // Garbage basis → same, both fns.
    try t.expect((try dispatch(&e, "datdif", &.{ numV(21915), numV(22097), strV("GARBAGE") })).isMissing());
    try t.expect((try dispatch(&e, "yrdif", &.{ numV(21915), numV(22097), strV("GARBAGE") })).isMissing());
    try t.expectEqual(@as(usize, 3), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[1].message, "Invalid basis 'GARBAGE' in DATDIF") != null);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[2].message, "Invalid basis 'GARBAGE' in YRDIF") != null);

    // Valid bases stay byte-identical and NOTE-free: datdif ACT/ACT+30/360,
    // yrdif ACT/360; blank basis keeps the ACT/ACT default, silent.
    try t.expectEqual(@as(f64, 182), (try dispatch(&e, "datdif", &.{ numV(21915), numV(22097), strV("ACT/ACT") })).num);
    try t.expectEqual(@as(f64, 180), (try dispatch(&e, "datdif", &.{ numV(21915), numV(22097), strV("30/360") })).num);
    try t.expectEqual(@as(f64, 182.0 / 360.0), (try dispatch(&e, "yrdif", &.{ numV(21915), numV(22097), strV("ACT/360") })).num);
    try t.expectEqual(@as(f64, 182), (try dispatch(&e, "datdif", &.{ numV(21915), numV(22097), strV("") })).num);
    try t.expectEqual(@as(f64, 182), (try dispatch(&e, "datdif", &.{ numV(21915), numV(22097), strV("ACTUAL") })).num);
    try t.expectEqual(@as(usize, 3), h.diags.count());
}

test "lag/dif keep independent per-call FIFO state across executions" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // LAG1: first call missing, then the value from one call ago.
    try t.expect((try dispatch(&e, "lag", &.{numV(10)})).isMissing());
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "lag", &.{numV(14)})).num);
    try t.expectEqual(@as(f64, 14), (try dispatch(&e, "lag", &.{numV(19)})).num);

    // DIF1 has its OWN queue (not disturbed by the lag calls above): x - lag(x).
    try t.expect((try dispatch(&e, "dif", &.{numV(10)})).isMissing());
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "dif", &.{numV(14)})).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "dif", &.{numV(19)})).num);

    // LAG2: missing until two calls have gone by.
    try t.expect((try dispatch(&e, "lag2", &.{numV(1)})).isMissing());
    try t.expect((try dispatch(&e, "lag2", &.{numV(2)})).isMissing());
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "lag2", &.{numV(3)})).num);
}

test "lag() of a character variable returns the prior string; dif() stays numeric (BUG-lagchar)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const a = h.arena.allocator();
    const site = try a.dupe(u8, "lag"); // one call site

    try t.expectEqualStrings("", (try dispatch(&e, site, &.{strV("EYE")})).str); // first row: blank, not '.' (BUG-lagcharfirst)
    try t.expectEqualStrings("EYE", (try dispatch(&e, site, &.{strV("SKIN")})).str);
    try t.expectEqualStrings("SKIN", (try dispatch(&e, site, &.{strV("HEART")})).str);

    // DIF is numeric-only: a character argument coerces to missing.
    const dsite = try a.dupe(u8, "dif");
    try t.expect((try dispatch(&e, dsite, &.{strV("A")})).isMissing());
    try t.expect((try dispatch(&e, dsite, &.{strV("B")})).isMissing());
}

test "dif() of a non-convertible char flags _ERROR_=1 (NOTE-difcharnoterr)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const a = h.arena.allocator();
    const dsite = try a.dupe(u8, "dif"); // one call site

    // non-convertible char → missing + converted/invalid-data NOTEs + _ERROR_=1.
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, dsite, &.{strV("abc")})).isMissing());
    try t.expectEqual(@as(f64, 1), h.pdv.get("_error_").?.num);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "converted to numeric") != null);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[1].message, "Invalid numeric data, 'abc'") != null);

    // blank char → benign missing: no note, _ERROR_ stays 0 (matches eval.zig).
    try h.pdv.set("_error_", .{ .num = 0 });
    const n0 = h.diags.count();
    try t.expect((try dispatch(&e, dsite, &.{strV("   ")})).isMissing());
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
    try t.expectEqual(n0, h.diags.count());

    // convertible char / numeric → unchanged (no _ERROR_).
    try h.pdv.set("_error_", .{ .num = 0 });
    try t.expect((try dispatch(&e, dsite, &.{strV("5")})).isMissing()); // prev row missing
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, dsite, &.{numV(9)})).num); // 9-5
    try t.expectEqual(@as(f64, 0), h.pdv.get("_error_").?.num);
}

test "two lag() call sites keep independent queues (BUG-lagdesync)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const a = h.arena.allocator();

    // Same text "lag", two distinct AST tokens → two distinct pointers, as the
    // parser hands each call site its own source slice.
    const site_a = try a.dupe(u8, "lag");
    const site_b = try a.dupe(u8, "lag");

    // Interleave the sites; each must track its OWN stream (10,20,30 vs 1,2,3).
    // With the old name-keyed queue these would desync into one shared FIFO.
    try t.expect((try dispatch(&e, site_a, &.{numV(10)})).isMissing());
    try t.expect((try dispatch(&e, site_b, &.{numV(1)})).isMissing());
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, site_a, &.{numV(20)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, site_b, &.{numV(2)})).num);
    try t.expectEqual(@as(f64, 20), (try dispatch(&e, site_a, &.{numV(30)})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, site_b, &.{numV(3)})).num);
}

test "date: mdy anchors on the SAS 1960 epoch; year/month/day/qtr/weekday extract" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // epoch and a well-known anchor: 01JAN1960 = 0, 01JAN2020 = 21915
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mdy", &.{ numV(1), numV(1), numV(1960) })).num);
    const d2020 = (try dispatch(&e, "MDY", &.{ numV(1), numV(1), numV(2020) })).num;
    try t.expectEqual(@as(f64, 21915), d2020);

    try t.expectEqual(@as(f64, 2020), (try dispatch(&e, "year", &.{numV(d2020)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "month", &.{numV(d2020)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "day", &.{numV(d2020)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "qtr", &.{numV(d2020)})).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "weekday", &.{numV(d2020)})).num); // Wed

    // invalid day-of-month → missing; missing arg propagates
    try t.expect((try dispatch(&e, "mdy", &.{ numV(2), numV(30), numV(2020) })).isMissing());
    try t.expect((try dispatch(&e, "mdy", &.{ numV(1), Value.missing, numV(2020) })).isMissing());

    // guard: absurd date arg saturates in floorI64 instead of panicking on
    // @intFromFloat overflow / downstream calendar-math i64 overflow.
    try t.expect(!std.math.isNan((try dispatch(&e, "year", &.{numV(1e300)})).num));
    try t.expect(!std.math.isNan((try dispatch(&e, "intnx", &.{ strV("year"), numV(1e300), numV(5) })).num));
}

test "datetime: datepart/timepart split; hour/minute/second read the clock" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const dt = 21915.0 * 86400.0 + 3661.0; // 01JAN2020 00:00 + 1h01m01s
    try t.expectEqual(@as(f64, 21915), (try dispatch(&e, "datepart", &.{numV(dt)})).num);
    try t.expectEqual(@as(f64, 3661), (try dispatch(&e, "timepart", &.{numV(dt)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "hour", &.{numV(3661)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "minute", &.{numV(3661)})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "second", &.{numV(3661)})).num);

    // hms/dhms build time and datetime values (inverse of hour/minute/second)
    try t.expectEqual(@as(f64, 49530), (try dispatch(&e, "hms", &.{ numV(13), numV(45), numV(30) })).num);
    try t.expectEqual(@as(f64, dt), (try dispatch(&e, "dhms", &.{ numV(21915), numV(1), numV(1), numV(1) })).num);
    try t.expect((try dispatch(&e, "hms", &.{ numV(1), Value.missing, numV(0) })).isMissing());
}

test "intck counts boundaries; intnx advances to the interval start" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const mdy = struct {
        fn f(ev: *eval.Evaluator, m: f64, d: f64, y: f64) !f64 {
            return (try dispatch(ev, "mdy", &.{ numV(m), numV(d), numV(y) })).num;
        }
    }.f;

    // intck — boundary counts, not elapsed units
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "intck", &.{ strV("day"), numV(0), numV(10) })).num);
    try t.expectEqual(@as(f64, 20), (try dispatch(&e, "intck", &.{ strV("year"), numV(try mdy(&e, 1, 1, 2000)), numV(try mdy(&e, 1, 1, 2020)) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intck", &.{ strV("month"), numV(try mdy(&e, 1, 15, 2020)), numV(try mdy(&e, 3, 10, 2020)) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "intck", &.{ strV("qtr"), numV(try mdy(&e, 1, 1, 2020)), numV(try mdy(&e, 12, 31, 2020)) })).num);
    // BUG-intckcont: CONTINUOUS ('C') counts complete anniversary intervals.
    // PDF example: months between 14FEB2021 and 12MAR2021 is 0 (Feb14→Mar14 = 1 mo).
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "intck", &.{ strV("month"), numV(try mdy(&e, 2, 14, 2021)), numV(try mdy(&e, 3, 12, 2021)), strV("continuous") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intck", &.{ strV("month"), numV(try mdy(&e, 2, 14, 2021)), numV(try mdy(&e, 3, 14, 2021)), strV("C") })).num); // exactly 1 month
    // discrete (default and explicit 'D') still counts boundary crossings
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intck", &.{ strV("month"), numV(try mdy(&e, 2, 14, 2021)), numV(try mdy(&e, 3, 12, 2021)), strV("D") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "intck", &.{ strV("month"), numV(try mdy(&e, 1, 15, 2020)), numV(try mdy(&e, 2, 14, 2020)), strV("C") })).num); // Jan15→Feb14 < 1 month → 0
    // BUG-intckcontyear: year continuous uses the CALENDAR anniversary (same month/
    // day), so 01MAR2020 → 01MAR2021 is exactly 1 full year even across the leap
    // boundary (day-of-year would wrongly give 0); 28FEB2021 is < 1 year (0).
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intck", &.{ strV("year"), numV(try mdy(&e, 3, 1, 2020)), numV(try mdy(&e, 3, 1, 2021)), strV("C") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "intck", &.{ strV("year"), numV(try mdy(&e, 3, 1, 2020)), numV(try mdy(&e, 2, 28, 2021)), strV("C") })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intck", &.{ strV("year"), numV(try mdy(&e, 3, 1, 2020)), numV(try mdy(&e, 3, 1, 2022)), strV("C") })).num);
    // qtr continuous: 15JAN2020 → 15JUL2020 = 2 quarters (6 months); → 14JUL = 1
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intck", &.{ strV("qtr"), numV(try mdy(&e, 1, 15, 2020)), numV(try mdy(&e, 7, 15, 2020)), strV("C") })).num);

    // intnx — beginning of the target interval
    try t.expectEqual(try mdy(&e, 2, 1, 2020), (try dispatch(&e, "intnx", &.{ strV("month"), numV(try mdy(&e, 1, 15, 2020)), numV(1) })).num);
    try t.expectEqual(try mdy(&e, 1, 1, 2022), (try dispatch(&e, "intnx", &.{ strV("year"), numV(try mdy(&e, 6, 15, 2020)), numV(2) })).num);
    try t.expectEqual(@as(f64, 105), (try dispatch(&e, "intnx", &.{ strV("day"), numV(100), numV(5) })).num);
    // 01JAN2020 is a Wednesday; the week's start (Sunday) is 29DEC2019
    try t.expectEqual(try mdy(&e, 12, 29, 2019), (try dispatch(&e, "intnx", &.{ strV("week"), numV(try mdy(&e, 1, 1, 2020)), numV(0) })).num);
    // an alignment 4th arg is tolerated (and ignored)
    try t.expectEqual(try mdy(&e, 2, 1, 2020), (try dispatch(&e, "intnx", &.{ strV("month"), numV(try mdy(&e, 1, 15, 2020)), numV(1), strV("b") })).num);
    // alignment: MIDDLE / END / SAME (INTNX-align), from 15MAR2020
    const mar15 = numV(try mdy(&e, 3, 15, 2020));
    try t.expectEqual(try mdy(&e, 3, 16, 2020), (try dispatch(&e, "intnx", &.{ strV("month"), mar15, numV(0), strV("middle") })).num);
    try t.expectEqual(try mdy(&e, 5, 31, 2020), (try dispatch(&e, "intnx", &.{ strV("month"), mar15, numV(2), strV("e") })).num);
    try t.expectEqual(try mdy(&e, 5, 15, 2020), (try dispatch(&e, "intnx", &.{ strV("month"), mar15, numV(2), strV("same") })).num);
    // unknown interval → missing
    try t.expect((try dispatch(&e, "intck", &.{ strV("fortnight"), numV(0), numV(30) })).isMissing());
}

test "today() returns a plausible current SAS date" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const d = (try dispatch(&e, "today", &.{})).num;
    // 20000 ≈ 2014-10, 40000 ≈ 2069 — brackets any real run of this suite.
    try t.expect(d > 20000 and d < 40000);
    try t.expectEqual(d, (try dispatch(&e, "date", &.{})).num); // date() is a synonym
}

test "gamma/lgamma/beta/std/week/cat + char classification (Phase F batch 2)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64) !void {
            try t.expect(@abs(got - want) < 1e-6);
        }
    }.f;

    try near((try dispatch(&e, "gamma", &.{numV(5)})).num, 24); // Lanczos ≈ 24 (4!)
    try near((try dispatch(&e, "lgamma", &.{numV(5)})).num, @log(24.0));
    try near((try dispatch(&e, "beta", &.{ numV(2), numV(3) })).num, 1.0 / 12.0);
    try near((try dispatch(&e, "digamma", &.{numV(1)})).num, -0.5772156649); // -γ, tight now
    try near((try dispatch(&e, "std", &.{ numV(2), numV(4), numV(4), numV(4), numV(5), numV(5), numV(7), numV(9) })).num, 2.13809);
    // WEEK: PDF examples (01jan2020 = SAS day 21915; 31dec2020 = 22280)
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "week", &.{numV(21915)})).num);
    try t.expectEqual(@as(f64, 52), (try dispatch(&e, "week", &.{ numV(22280), strV("u") })).num);
    // CAT keeps blanks
    try t.expectEqualStrings("ab  cd", (try dispatch(&e, "cat", &.{ strV("ab "), strV(" cd") })).str);
    // BUG-catbest: numeric args render via SAS BEST12, not raw f64
    try t.expectEqualStrings("0.3333333333", (try dispatch(&e, "cats", &.{numV(1.0 / 3.0)})).str);
    try t.expectEqualStrings("x=0.3333333333", (try dispatch(&e, "cats", &.{ strV("x="), numV(1.0 / 3.0) })).str);
    try t.expectEqualStrings("1 2 3", (try dispatch(&e, "catx", &.{ strV(" "), numV(1), numV(2), numV(3) })).str);
    try t.expectEqualStrings("0.3", (try dispatch(&e, "cat", &.{numV(0.1 + 0.2)})).str); // not 0.30000000000000004
    // character classification / helpers
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "anyalpha", &.{strV("123abc")})).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "notalpha", &.{strV("abc9")})).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "anydigit", &.{strV("abcd")})).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "compare", &.{ strV("cat"), strV("car") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "compare", &.{ strV("cat"), strV("cat") })).num);
    try t.expectEqual(@as(f64, 65), (try dispatch(&e, "rank", &.{strV("A")})).num);
    try t.expectEqualStrings("B", (try dispatch(&e, "byte", &.{numV(66)})).str);
    try t.expectEqualStrings("ABCDEF", (try dispatch(&e, "collate", &.{ numV(65), numV(70) })).str);
    try t.expectEqualStrings("a b c", (try dispatch(&e, "compbl", &.{strV("a    b   c")})).str);
}

test "string + date families: substrn/cats/quote/translate/verify/juldate/nwkdom (Phase F)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    try t.expectEqualStrings("bcd", (try dispatch(&e, "substrn", &.{ strV("abcde"), numV(2), numV(3) })).str);
    try t.expectEqualStrings("a", (try dispatch(&e, "substrn", &.{ strV("abcde"), numV(-1), numV(3) })).str);
    try t.expectEqualStrings("ab", (try dispatch(&e, "cats", &.{ strV(" a "), strV(" b ") })).str);
    try t.expectEqualStrings(" a b", (try dispatch(&e, "catt", &.{ strV(" a "), strV(" b ") })).str);
    try t.expectEqualStrings("\"ab\"", (try dispatch(&e, "quote", &.{strV("ab")})).str);
    try t.expectEqualStrings("ab", (try dispatch(&e, "dequote", &.{strV("\"ab\"")})).str);
    try t.expectEqualStrings("XYcXYc", (try dispatch(&e, "translate", &.{ strV("abcabc"), strV("XY"), strV("ab") })).str);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "verify", &.{ strV("abc"), strV("ab") })).num);
    try t.expectEqualStrings("cba", (try dispatch(&e, "reverse", &.{strV("abc")})).str);
    try t.expectEqualStrings("ababab", (try dispatch(&e, "repeat", &.{ strV("ab"), numV(2) })).str);
    // BUG-repeatoom: a huge finite count must cap at the char max (32767), not OOM/hang
    try t.expectEqual(@as(usize, 32767), (try dispatch(&e, "repeat", &.{ strV("x"), numV(1e12) })).str.len);
    try t.expectEqual(@as(usize, 32767), (try dispatch(&e, "repeat", &.{ strV("ab"), numV(1e9) })).str.len);
    try t.expectEqualStrings("", (try dispatch(&e, "repeat", &.{ strV(""), numV(1e12) })).str); // empty stays empty
    try t.expectEqualStrings("Hello World", (try dispatch(&e, "propcase", &.{strV("hello world")})).str);
    try t.expectEqualStrings("\"x\",\"y\"", (try dispatch(&e, "catq", &.{ strV("acs"), strV("x"), strV("y") })).str);
    // dates (SAS day 14609 = 31dec1999; 50769 = 01jan2099; 21915 = 01jan2020)
    try t.expectEqual(@as(f64, 99365), (try dispatch(&e, "juldate", &.{numV(14609)})).num);
    try t.expectEqual(@as(f64, 2099001), (try dispatch(&e, "juldate", &.{numV(50770)})).num); // 01jan2099
    try t.expectEqual(@as(f64, 2020001), (try dispatch(&e, "juldate7", &.{numV(21915)})).num);
    try t.expectEqual(@as(f64, 21915), (try dispatch(&e, "datejul", &.{numV(2020001)})).num);
    try t.expectEqual(@as(f64, 21933), (try dispatch(&e, "nwkdom", &.{ numV(3), numV(1), numV(1), numV(2020) })).num); // 3rd Sunday Jan 2020
}

test "count/countc/countw/indexc/indexw/constant/choose/which/ifn/soundex (Phase F)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    try t.expect(@abs((try dispatch(&e, "constant", &.{strV("pi")})).num - std.math.pi) < 1e-12);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "count", &.{ strV("abcabc"), strV("bc") })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "countc", &.{ strV("mississippi"), strV("s") })).num);
    // COUNTC class modifiers (BUG-countcmodifiers)
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "countc", &.{ strV("a1b2c3"), strV(""), strV("d") })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "countc", &.{ strV("aAbBcC"), strV(""), strV("u") })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "countc", &.{ strV("a1b2"), strV(""), strV("d"), strV("v") })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "countw", &.{strV("a b  c d")})).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "indexc", &.{ strV("xy9z"), strV("0123456789") })).num);
    // FINDC character-class modifiers add a whole class to the search (BUG-findcmodifiers)
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "findc", &.{ strV("abc123"), strV(" "), strV("d") })).num); // first digit
    // FINDC k = complement (first char NOT in the set) — BUG-findckmod
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "findc", &.{ strV("abc123"), strV("abc"), strV("k") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "findc", &.{ strV("abc123"), strV("123"), strV("k") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "findc", &.{ strV("aaa"), strV("abc"), strV("k") })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "findc", &.{ strV("abcABC"), strV(" "), strV("u") })).num); // first upper
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "findc", &.{ strV("ABCabc"), strV(""), strV("l") })).num); // first lower
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "findc", &.{ strV("hello world"), strV(""), strV("s") })).num); // first space
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "findc", &.{ strV("abc123"), strV("0123456789") })).num); // explicit list
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "findc", &.{ strV("abc"), strV(" "), strV("d") })).num); // no digit → 0
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "indexw", &.{ strV("the cat sat"), strV("cat") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "indexw", &.{ strV("scatter"), strV("cat") })).num); // not a whole word
    try t.expectEqualStrings("b", (try dispatch(&e, "char", &.{ strV("abc"), numV(2) })).str);
    try t.expectEqualStrings("  ab", (try dispatch(&e, "right", &.{strV("ab  ")})).str);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "lengthn", &.{strV("ab   ")})).num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "lengthc", &.{strV("ab   ")})).num);
    try t.expectEqual(@as(f64, 22), (try dispatch(&e, "choosen", &.{ numV(2), numV(11), numV(22), numV(33) })).num);
    try t.expectEqualStrings("z", (try dispatch(&e, "choosec", &.{ numV(-1), strV("x"), strV("y"), strV("z") })).str);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "whichn", &.{ numV(22), numV(11), numV(22), numV(33) })).num);
    try t.expectEqual(@as(f64, 100), (try dispatch(&e, "ifn", &.{ numV(1), numV(100), numV(200) })).num);
    try t.expectEqualStrings("no", (try dispatch(&e, "ifc", &.{ numV(0), strV("yes"), strV("no") })).str);
    try t.expectEqualStrings("R163", (try dispatch(&e, "soundex", &.{strV("Robert")})).str);
    try t.expectEqualStrings("\"a b\"n", (try dispatch(&e, "nliteral", &.{strV("a b")})).str);
}

test "bitwise/trig-recip/z-variants/divide/cmiss/compound + char classes (Phase F batch 5)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64) !void {
            try t.expect(@abs(got - want) < 1e-6);
        }
    }.f;

    // bitwise (PDF hex examples): band(0F,05)=5, blshift(07,2)=0x1C=28
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "band", &.{ numV(0x0F), numV(0x05) })).num);
    try t.expectEqual(@as(f64, 0x0F), (try dispatch(&e, "bor", &.{ numV(0x0A), numV(0x05) })).num);
    try t.expectEqual(@as(f64, 0x0F), (try dispatch(&e, "bxor", &.{ numV(0x0C), numV(0x03) })).num);
    try t.expectEqual(@as(f64, 28), (try dispatch(&e, "blshift", &.{ numV(0x07), numV(2) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "brshift", &.{ numV(0x0C), numV(2) })).num);
    // bnot(0F000000F) = 0FFFFFF0
    try t.expectEqual(@as(f64, 0x0FFFFFF0), (try dispatch(&e, "bnot", &.{numV(0xF000000F)})).num);
    try t.expect((try dispatch(&e, "band", &.{ Value.missing, numV(1) })).isMissing());

    // trig reciprocals
    try near((try dispatch(&e, "cot", &.{numV(1)})).num, 1.0 / @tan(@as(f64, 1)));
    try near((try dispatch(&e, "csc", &.{numV(1)})).num, 1.0 / @sin(@as(f64, 1)));
    try near((try dispatch(&e, "sec", &.{numV(1)})).num, 1.0 / @cos(@as(f64, 1)));

    // z-variants (non-fuzzed round/ceil/floor/int)
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "ceilz", &.{numV(2.1)})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "floorz", &.{numV(2.9)})).num);
    try t.expectEqual(@as(f64, -2), (try dispatch(&e, "intz", &.{numV(-2.9)})).num);
    try t.expectEqual(@as(f64, 2.5), (try dispatch(&e, "roundz", &.{ numV(2.46), numV(0.5) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "roundz", &.{numV(2.6)})).num);

    // divide / cmiss / compound
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "divide", &.{ numV(6), numV(2) })).num);
    try t.expect((try dispatch(&e, "divide", &.{ numV(6), Value.missing })).isMissing());
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "cmiss", &.{ numV(1), Value.missing, strV("  "), strV("x") })).num);
    // PDF example: compound(2000, ., 0.09/12, 30) → 2502.5435276
    try near((try dispatch(&e, "compound", &.{ numV(2000), Value.missing, numV(0.09 / 12.0), numV(30) })).num, 2502.5435276);
    try near((try dispatch(&e, "compound", &.{ Value.missing, numV(2502.5435276), numV(0.09 / 12.0), numV(30) })).num, 2000);

    // new character classes
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "anyxdigit", &.{strV("xyF12")})).num); // F at pos 3
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "anyfirst", &.{strV("_ab")})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "anyname", &.{strV(" a9")})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "anygraph", &.{strV(" x ")})).num); // non-blank printable
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "anycntrl", &.{strV("abc")})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "anyprint", &.{strV("abc")})).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "notxdigit", &.{strV("abcx")})).num); // x at pos 4
}

test "descriptive stats + erf/rounde/compfuzz/effrate + choosen guard (Phase F batch 6)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64) !void {
            try t.expect(@abs(got - want) < 1e-6);
        }
    }.f;
    const v12345 = [_]Value{ numV(1), numV(2), numV(3), numV(4), numV(5) };

    // sums of squares / norms
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "css", &v12345)).num); // Σ(x-3)²
    try t.expectEqual(@as(f64, 55), (try dispatch(&e, "uss", &v12345)).num); // Σx²
    try near((try dispatch(&e, "rms", &v12345)).num, @sqrt(11.0));
    try near((try dispatch(&e, "euclid", &v12345)).num, @sqrt(55.0));
    try t.expectEqual(@as(f64, 15), (try dispatch(&e, "sumabs", &.{ numV(3), numV(0), numV(-4), numV(-8) })).num);
    try near((try dispatch(&e, "cv", &v12345)).num, 100.0 * @sqrt(2.5) / 3.0);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "lpnorm", &.{ numV(2), numV(3), numV(0), numV(-4) })).num);
    try t.expectEqual(@as(f64, 7), (try dispatch(&e, "lpnorm", &.{ numV(1), numV(3), numV(0), numV(-4) })).num);

    // geometric / harmonic means
    try near((try dispatch(&e, "geomean", &.{ numV(1), numV(2), numV(4) })).num, 2); // 8^(1/3)
    try near((try dispatch(&e, "harmean", &.{ numV(1), numV(2), numV(4) })).num, 3.0 / 1.75);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "geomean", &.{ numV(0), numV(5) })).num);
    try t.expect((try dispatch(&e, "harmean", &.{ numV(0), numV(5) })).isMissing()); // 0 not allowed

    // skewness / kurtosis (hand-computed for {1..5}: 0 and −1.2)
    try near((try dispatch(&e, "skewness", &v12345)).num, 0);
    try near((try dispatch(&e, "kurtosis", &v12345)).num, -1.2);

    // order statistics / quantiles (PDF examples: iqr=2, mad=1.5)
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "median", &v12345)).num);
    try t.expectEqual(@as(f64, 2.5), (try dispatch(&e, "median", &.{ numV(1), numV(2), numV(3), numV(4) })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "range", &v12345)).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "iqr", &.{ numV(2), numV(4), numV(1), numV(3), numV(999999) })).num);
    try t.expectEqual(@as(f64, 1.5), (try dispatch(&e, "mad", &.{ numV(2), numV(4), numV(1), numV(3), numV(5), numV(999999) })).num);
    try t.expectEqual(@as(f64, 1.5), (try dispatch(&e, "pctl", &.{ numV(25), numV(2), numV(4), numV(1), numV(3) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "largest", &.{ numV(2), numV(1), numV(5), numV(3) })).num); // 2nd largest
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "smallest", &.{ numV(1), numV(5), numV(3), numV(9) })).num);
    try t.expect((try dispatch(&e, "largest", &.{ numV(9), numV(1), numV(5) })).isMissing()); // k>nvals
    // ORDINAL includes missing in the ordering (missing sorts first)
    try t.expect((try dispatch(&e, "ordinal", &.{ numV(1), Value.missing, numV(5), numV(3) })).isMissing());
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "ordinal", &.{ numV(2), Value.missing, numV(5), numV(3) })).num);

    // scalar special / rounding / financial — ERF/ERFC to full f64 (BUG-erfaccuracy)
    try t.expectApproxEqAbs(@as(f64, 0.8427007929497149), (try dispatch(&e, "erf", &.{numV(1)})).num, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 0.5204998778130465), (try dispatch(&e, "erf", &.{numV(0.5)})).num, 1e-14);
    try t.expectApproxEqAbs(@as(f64, 0.15729920705028513), (try dispatch(&e, "erfc", &.{numV(1)})).num, 1e-14);
    try t.expectApproxEqAbs(@as(f64, -0.8427007929497149), (try dispatch(&e, "erf", &.{numV(-1)})).num, 1e-14);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "rounde", &.{numV(2.5)})).num); // ties to even → 2
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "rounde", &.{numV(3.5)})).num); // ties to even → 4
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "compfuzz", &.{ numV(1), numV(1) })).num);
    try t.expectEqual(@as(f64, -1), (try dispatch(&e, "compfuzz", &.{ numV(1), numV(2), numV(0.1) })).num);
    try near((try dispatch(&e, "effrate", &.{ strV("MONTH"), numV(10) })).num, 10.471306744);
    try near((try dispatch(&e, "nomrate", &.{ strV("MONTH"), numV(10) })).num, 9.5689685147);

    // BUG-choosencrash: a huge index must not panic @intFromFloat, just miss out
    try t.expect((try dispatch(&e, "choosen", &.{ numV(1e300), numV(1), numV(2) })).isMissing());
    try t.expectEqualStrings("", (try dispatch(&e, "choosec", &.{ numV(-1e300), strV("a"), strV("b") })).str);
}

test "distributions + inverses + log-gamma/gcd + string helpers (Phase F batch 7)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const num = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) !f64 {
            return (try dispatch(ev, name, args)).num;
        }
    }.f;

    // BUG-facthang: huge/invalid args must return missing, not hang
    try t.expect((try dispatch(&e, "fact", &.{numV(1e12)})).isMissing());
    try t.expect((try dispatch(&e, "fact", &.{numV(171)})).isMissing());
    try t.expect((try dispatch(&e, "perm", &.{ numV(1e12), numV(5e11) })).isMissing());
    try t.expect((try dispatch(&e, "comb", &.{ numV(1e12), numV(5e11) })).isMissing());
    try t.expectEqual(@as(f64, 720), (try dispatch(&e, "fact", &.{numV(6)})).num); // still correct

    // distribution CDFs (PDF worked examples)
    try near(try num(&e, "probnorm", &.{numV(1.96)}), 0.9750021049, 1e-9);
    try near(try num(&e, "probgam", &.{ numV(1), numV(3) }), 0.0803013971, 1e-9);
    try near(try num(&e, "poisson", &.{ numV(1), numV(2) }), 0.9196986029, 1e-9);
    try near(try num(&e, "probbeta", &.{ numV(0.2), numV(3), numV(4) }), 0.09888, 1e-5);
    try near(try num(&e, "probbnml", &.{ numV(0.5), numV(10), numV(4) }), 0.376953125, 1e-9);
    try near(try num(&e, "probt", &.{ numV(0.9), numV(5) }), 0.7953143998, 1e-9);
    try near(try num(&e, "probchi", &.{ numV(3.841458821), numV(1) }), 0.95, 1e-7); // χ²₁ 95th pct
    try near(try num(&e, "probf", &.{ numV(1), numV(10), numV(10) }), 0.5, 1e-9); // F symmetric at 1
    try near(try num(&e, "probit", &.{numV(0.975)}), 1.959963985, 1e-6);

    // quantile inverses (round-trip against their CDFs)
    try near(try num(&e, "cinv", &.{ numV(0.95), numV(1) }), 3.841458821, 1e-5);
    try near(try num(&e, "tinv", &.{ numV(0.975), numV(10) }), 2.228138852, 1e-5);
    try near(try num(&e, "betainv", &.{ numV(0.5), numV(1), numV(1) }), 0.5, 1e-6);
    try near(try num(&e, "finv", &.{ numV(0.5), numV(10), numV(10) }), 1.0, 1e-5);
    try near(try num(&e, "gaminv", &.{ numV(0.0803013971), numV(3) }), 1.0, 1e-5);

    // log-gamma family / number theory
    try near(try num(&e, "logbeta", &.{ numV(2), numV(3) }), @log(1.0 / 12.0), 1e-9);
    try near(try num(&e, "lfact", &.{numV(5)}), @log(120.0), 1e-9);
    try near(try num(&e, "lperm", &.{ numV(6), numV(2) }), @log(30.0), 1e-9);
    try near(try num(&e, "lcomb", &.{ numV(6), numV(2) }), @log(15.0), 1e-9);
    try near(try num(&e, "log1px", &.{numV(1e-10)}), 1e-10, 1e-18);
    try near(try num(&e, "trigamma", &.{numV(1)}), std.math.pi * std.math.pi / 6.0, 1e-8);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "gcd", &.{ numV(12), numV(18) })).num);
    try t.expectEqual(@as(f64, 36), (try dispatch(&e, "lcm", &.{ numV(12), numV(18) })).num);
    // BUG-lcmoverflow: coprime ~9e15 args make LCM ~8.1e31; the u64 multiply used to
    // PANIC (safe build). Checked mul -> missing; small args (4,6)->12 stay exact.
    try t.expect((try dispatch(&e, "lcm", &.{ numV(8999999999999999), numV(8999999999999998) })).isMissing());
    try t.expectEqual(@as(f64, 12), (try dispatch(&e, "lcm", &.{ numV(4), numV(6) })).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "gcd", &.{ numV(24), numV(36), numV(54) })).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "fuzz", &.{numV(5.9999999999999)})).num);
    try t.expectEqual(@as(f64, 5.99999999), (try dispatch(&e, "fuzz", &.{numV(5.99999999)})).num);
    try near(try num(&e, "var", &.{ numV(1), numV(2), numV(3), numV(4), numV(5) }), 2.5, 1e-12);
    try near(try num(&e, "stderr", &.{ numV(1), numV(2), numV(3), numV(4), numV(5) }), @sqrt(0.5), 1e-12);

    // string helpers
    try t.expectEqualStrings("cde", (try dispatch(&e, "subpad", &.{ strV("abcde"), numV(3) })).str);
    try t.expectEqualStrings("cde ", (try dispatch(&e, "subpad", &.{ strV("abcde"), numV(3), numV(4) })).str); // pads past end
    try t.expectEqualStrings("a-b-c", (try dispatch(&e, "transtrn", &.{ strV("a.b.c"), strV("."), strV("-") })).str);
    try t.expectEqualStrings("ac", (try dispatch(&e, "transtrn", &.{ strV("abc"), strV("b"), strV("") })).str); // remove
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "complev", &.{ strV("kitten"), strV("sitting") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "complev", &.{ strV("abc"), strV("abc  ") })).num); // trailing blanks
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "complev", &.{ strV("kitten"), strV("sitting"), numV(2) })).num); // cutoff
}

test "BUG-intfromfloat: no @intFromFloat site traps on non-finite/huge args" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const inf = std.math.inf(f64);
    const huge = 1e300;

    // Every one of these once panicked on an unguarded @intFromFloat; SAS returns
    // missing / blank / out-of-range. The point is that the call RETURNS (no trap).
    inline for (.{ inf, -inf, huge, -huge }) |bad| {
        // numeric args → missing
        try t.expect((try dispatch(&e, "week", &.{numV(bad)})).isMissing());
        try t.expect((try dispatch(&e, "juldate", &.{numV(bad)})).isMissing());
        try t.expect((try dispatch(&e, "juldate7", &.{numV(bad)})).isMissing());
        try t.expect((try dispatch(&e, "datejul", &.{numV(bad)})).isMissing());
        try t.expect((try dispatch(&e, "nwkdom", &.{ numV(bad), numV(1), numV(1), numV(2020) })).isMissing());
        try t.expect((try dispatch(&e, "gcd", &.{ numV(bad), numV(12) })).isMissing());
        try t.expect((try dispatch(&e, "lcm", &.{ numV(bad), numV(12) })).isMissing());
        // string/position args → blank or 0, never a trap
        _ = try dispatch(&e, "scan", &.{ strV("a b c"), numV(bad) });
        _ = try dispatch(&e, "find", &.{ strV("abc"), strV("b"), numV(bad) });
        _ = try dispatch(&e, "anyalpha", &.{ strV("abc"), numV(bad) });
        _ = try dispatch(&e, "repeat", &.{ strV("ab"), numV(bad) });
        _ = try dispatch(&e, "subpad", &.{ strV("abc"), numV(2), numV(bad) });
        // later-batch sites (deptab period, cumprinc nper, depdbsl period/lifetime)
        _ = try dispatch(&e, "deptab", &.{ numV(bad), numV(1000), numV(0.3), numV(0.4) });
        _ = try dispatch(&e, "cumprinc", &.{ numV(0.01), numV(bad), numV(1000), numV(1), numV(12), numV(0) });
        _ = try dispatch(&e, "depdbsl", &.{ numV(bad), numV(1000), numV(bad), numV(2) });
        _ = try dispatch(&e, "daccdbsl", &.{ numV(bad), numV(1000), numV(10), numV(2) });
    }
    // subpad with a huge length arg → can't materialize, so it gives up — as a
    // BLANK CHARACTER. This test's own comment three lines above already said
    // "string/position args → blank or 0, never a trap"; the assertion said
    // `isMissing()`, i.e. a numeric, and BUG-charfnsmissingtype made the code
    // match the stated intent. The trap-avoidance this test exists for is
    // unchanged and still asserted — dispatch returning at all is the check.
    const huge_len = try dispatch(&e, "subpad", &.{ strV("abc"), numV(2), numV(inf) });
    try t.expect(huge_len == .str);
    try t.expectEqualStrings("", huge_len.str);
    // a finite in-range value still works after the guard
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "find", &.{ strV("abcb"), strV("c") })).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "gcd", &.{ numV(12), numV(18) })).num);
}

test "distribution family + FIPS/state + financial + html/url (Phase F batch 8)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const num = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) !f64 {
            return (try dispatch(ev, name, args)).num;
        }
    }.f;

    // CDF matches the PROBxxx equivalents already verified against the PDF
    try near(try num(&e, "cdf", &.{ strV("NORMAL"), numV(1.96) }), 0.9750021049, 1e-9);
    try near(try num(&e, "cdf", &.{ strV("CHISQUARE"), numV(3.841458821), numV(1) }), 0.95, 1e-7);
    try near(try num(&e, "cdf", &.{ strV("T"), numV(0.9), numV(5) }), 0.7953143998, 1e-9);
    try near(try num(&e, "cdf", &.{ strV("F"), numV(1), numV(10), numV(10) }), 0.5, 1e-9);
    try near(try num(&e, "cdf", &.{ strV("GAMMA"), numV(1), numV(3) }), 0.0803013971, 1e-9);
    try near(try num(&e, "cdf", &.{ strV("POISSON"), numV(2), numV(1) }), 0.9196986029, 1e-9);
    try near(try num(&e, "cdf", &.{ strV("EXPONENTIAL"), numV(1) }), 1.0 - @exp(-1.0), 1e-12);
    try near(try num(&e, "cdf", &.{ strV("UNIFORM"), numV(0.25) }), 0.25, 1e-12);
    try near(try num(&e, "cdf", &.{ strV("BINOMIAL"), numV(4), numV(0.5), numV(10) }), 0.376953125, 1e-9);
    // aliases + minimal identification
    try near(try num(&e, "cdf", &.{ strV("GAUSS"), numV(0) }), 0.5, 1e-12);
    try near(try num(&e, "cdf", &.{ strV("Norm"), numV(0) }), 0.5, 1e-12);
    // SDF / LOGCDF / LOGSDF
    try near(try num(&e, "sdf", &.{ strV("NORMAL"), numV(1.96) }), 1.0 - 0.9750021049, 1e-9);
    try near(try num(&e, "logcdf", &.{ strV("NORMAL"), numV(0) }), @log(0.5), 1e-12);
    try near(try num(&e, "logsdf", &.{ strV("NORMAL"), numV(0) }), @log(0.5), 1e-12);
    // PDF / LOGPDF
    try near(try num(&e, "pdf", &.{ strV("NORMAL"), numV(0) }), 1.0 / @sqrt(2.0 * std.math.pi), 1e-12);
    try near(try num(&e, "pdf", &.{ strV("EXPONENTIAL"), numV(0) }), 1.0, 1e-12);
    try near(try num(&e, "pdf", &.{ strV("UNIFORM"), numV(0.5) }), 1.0, 1e-12);
    try near(try num(&e, "pdf", &.{ strV("POISSON"), numV(0), numV(1) }), @exp(-1.0), 1e-12);
    try near(try num(&e, "logpdf", &.{ strV("NORMAL"), numV(0) }), @log(1.0 / @sqrt(2.0 * std.math.pi)), 1e-12);
    // QUANTILE round-trips its CDF; SQUANTILE uses the right-tail probability
    try near(try num(&e, "quantile", &.{ strV("NORMAL"), numV(0.975) }), 1.959963985, 1e-6);
    try near(try num(&e, "quantile", &.{ strV("CHISQUARE"), numV(0.95), numV(1) }), 3.841458821, 1e-5);
    try near(try num(&e, "quantile", &.{ strV("EXPONENTIAL"), numV(0.5) }), @log(2.0), 1e-9);
    try near(try num(&e, "squantile", &.{ strV("NORMAL"), numV(0.025) }), 1.959963985, 1e-6);
    // unknown distribution → loud ERROR + missing, never a wrong number
    // (GAP-distsilentmiss; PARETO is implemented now — NORMALMIX stays a gap)
    try t.expect((try dispatch(&e, "cdf", &.{ strV("NORMALMIX"), numV(1), numV(1) })).isMissing());

    // FIPS / state lookups
    try t.expectEqual(@as(f64, 37), (try dispatch(&e, "stfips", &.{strV("NC")})).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "stfips", &.{strV("ca")})).num); // case-insensitive
    try t.expectEqualStrings("NC", (try dispatch(&e, "fipstate", &.{numV(37)})).str);
    try t.expectEqualStrings("NORTH CAROLINA", (try dispatch(&e, "stname", &.{strV("NC")})).str);
    try t.expectEqualStrings("North Carolina", (try dispatch(&e, "stnamel", &.{strV("NC")})).str);
    try t.expectEqualStrings("TEXAS", (try dispatch(&e, "fipname", &.{numV(48)})).str);
    try t.expectEqualStrings("District of Columbia", (try dispatch(&e, "fipnamel", &.{numV(11)})).str);
    try t.expect((try dispatch(&e, "stfips", &.{strV("ZZ")})).isMissing());
    try t.expectEqualStrings("", (try dispatch(&e, "fipstate", &.{numV(3)})).str); // gap in FIPS numbering

    // financial (hand-computed cases; r=0 branches and annuity round-trips)
    try t.expectEqual(@as(f64, 100), (try dispatch(&e, "mort", &.{ numV(1200), Value.missing, numV(0), numV(12) })).num);
    try t.expectEqual(@as(f64, 1200), (try dispatch(&e, "mort", &.{ Value.missing, numV(100), numV(0), numV(12) })).num);
    try t.expectEqual(@as(f64, 1200), (try dispatch(&e, "saving", &.{ Value.missing, numV(100), numV(0), numV(12) })).num);
    // MORT payment then solve back for n
    const pay = try num(&e, "mort", &.{ numV(1000), Value.missing, numV(0.01), numV(24) });
    try near(try num(&e, "mort", &.{ numV(1000), numV(pay), numV(0.01), Value.missing }), 24, 1e-6);
    try near(try num(&e, "netpv", &.{ numV(0.1), numV(1), numV(-100), numV(0), numV(121) }), 0, 1e-9);
    try near(try num(&e, "npv", &.{ numV(10), numV(1), numV(-100), numV(0), numV(121) }), 0, 1e-9); // % rate
    try near(try num(&e, "intrr", &.{ numV(1), numV(-100), numV(110) }), 0.1, 1e-6);
    try near(try num(&e, "irr", &.{ numV(1), numV(-100), numV(110) }), 10, 1e-4);

    // HTML / URL decode
    try t.expectEqualStrings("a<b>&\"c\"", (try dispatch(&e, "htmldecode", &.{strV("a&lt;b&gt;&amp;&quot;c&quot;")})).str);
    try t.expectEqualStrings("A&B", (try dispatch(&e, "htmldecode", &.{strV("&#65;&amp;&#x42;")})).str);
    try t.expectEqualStrings("a b&c", (try dispatch(&e, "urldecode", &.{strV("a+b%26c")})).str);
}

test "depreciation + annuity + extra distributions + bessel/airy (Phase F batch 9)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const num = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) !f64 {
            return (try dispatch(ev, name, args)).num;
        }
    }.f;

    // depreciation (PDF worked examples)
    try near(try num(&e, "depsl", &.{ numV(9.0 / 12.0), numV(1000), numV(10) }), 75, 1e-9);
    try near(try num(&e, "depsyd", &.{ numV(3.0 / 12.0), numV(1000), numV(5) }), 83.333333333, 1e-6);
    try near(try num(&e, "depsyd", &.{ numV(15.0 / 12.0), numV(1000), numV(5) }), 316.66666667, 1e-6);
    try near(try num(&e, "daccsl", &.{ numV(1.75), numV(1000), numV(10) }), 175, 1e-9);
    try near(try num(&e, "daccdb", &.{ numV(10), numV(1000), numV(15), numV(2) }), 760.93, 1e-2);
    // straight-line full period = v/y; accumulated over full life = v
    try near(try num(&e, "depsl", &.{ numV(3), numV(1000), numV(10) }), 100, 1e-9);
    try near(try num(&e, "daccsl", &.{ numV(10), numV(1000), numV(10) }), 1000, 1e-9);
    try near(try num(&e, "daccsyd", &.{ numV(5), numV(1000), numV(5) }), 1000, 1e-9);

    // annuity: PMT is Excel-compatible (negative for a loan), and the pieces close
    try near(try num(&e, "pmt", &.{ numV(0.08 / 12.0), numV(10), numV(10000) }), -1037.0320766, 1e-4);
    const pv = 10000.0;
    const r = 0.08 / 12.0;
    const nper = 10.0;
    const pmt = try num(&e, "pmt", &.{ numV(r), numV(nper), numV(pv) });
    // PPMT + IPMT = PMT every period; ΣPPMT over the life = −pv (loan cleared)
    var sump: f64 = 0;
    var per: f64 = 1;
    while (per <= nper) : (per += 1) {
        const ip = try num(&e, "ipmt", &.{ numV(r), numV(per), numV(nper), numV(pv) });
        const pp = try num(&e, "ppmt", &.{ numV(r), numV(per), numV(nper), numV(pv) });
        try near(ip + pp, pmt, 1e-9);
        sump += pp;
    }
    try near(sump, -pv, 1e-6);
    // CUMPRINC over all periods = ΣPPMT; CUMPRINC+CUMIPMT = nper·PMT
    try near(try num(&e, "cumprinc", &.{ numV(r), numV(nper), numV(pv), numV(1), numV(nper), numV(0) }), -pv, 1e-6);
    // DoS: an absurd nper must be rejected, not loop nper times over the schedule
    try t.expect((try dispatch(&e, "cumprinc", &.{ numV(r), numV(1e9), numV(pv), numV(1), numV(1e9), numV(0) })).isMissing());
    try near(
        (try num(&e, "cumprinc", &.{ numV(r), numV(nper), numV(pv), numV(1), numV(nper), numV(0) })) +
            (try num(&e, "cumipmt", &.{ numV(r), numV(nper), numV(pv), numV(1), numV(nper), numV(0) })),
        nper * pmt,
        1e-6,
    );

    // extra distributions
    try near(try num(&e, "probnegb", &.{ numV(0.5), numV(1), numV(0) }), 0.5, 1e-9); // 0 failures before 1st success
    try near(try num(&e, "probhypr", &.{ numV(10), numV(5), numV(5), numV(2) }), 0.5, 1e-9); // symmetric
    try near(try num(&e, "probhypr", &.{ numV(10), numV(5), numV(5), numV(5) }), 1.0, 1e-12);
    // BUG-probhyprhang: a huge population must not infinite-loop (float i+=1 no-op past
    // 2^53) or spin a billion terms — single-term huge returns fast, big range → missing
    try near(try num(&e, "probhypr", &.{ numV(1e18), numV(5e17), numV(1e18), numV(5e17) }), 1, 1e-6);
    try t.expect((try dispatch(&e, "probhypr", &.{ numV(1e18), numV(1e9), numV(1e9), numV(1e9) })).isMissing());

    // special functions (tabulated reference values)
    try near(try num(&e, "airy", &.{numV(0)}), 0.3550280539, 1e-9);
    try near(try num(&e, "dairy", &.{numV(0)}), -0.2588194038, 1e-9);
    try near(try num(&e, "airy", &.{numV(1)}), 0.1352924163, 1e-8);
    try near(try num(&e, "jbessel", &.{ numV(0), numV(1) }), 0.7651976866, 1e-8);
    try near(try num(&e, "jbessel", &.{ numV(1), numV(1) }), 0.4400505857, 1e-8);
    try near(try num(&e, "ibessel", &.{ numV(0), numV(1), numV(0) }), 1.2660658778, 1e-8);
    try near(try num(&e, "ibessel", &.{ numV(1), numV(1), numV(0) }), 0.5651591040, 1e-8);
    try near(try num(&e, "ibessel", &.{ numV(0), numV(1), numV(1) }), 1.2660658778 * @exp(-1.0), 1e-8); // scaled

    // name checks / type / html+url encode
    try t.expectEqualStrings("N", (try dispatch(&e, "typeof", &.{numV(5)})).str);
    try t.expectEqualStrings("C", (try dispatch(&e, "typeof", &.{strV("x")})).str);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "nvalid", &.{strV("_abc1")})).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "nvalid", &.{strV("9x")})).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "nvalid", &.{strV("a b")})).num);
    try t.expectEqualStrings("a&lt;b&gt;&amp;c", (try dispatch(&e, "htmlencode", &.{strV("a<b>&c")})).str);
    try t.expectEqualStrings("a%20b%26c", (try dispatch(&e, "urlencode", &.{strV("a b&c")})).str);
    // round-trips against the decoders shipped in batch 8
    try t.expectEqualStrings("<&>", (try dispatch(&e, "htmldecode", &.{try dispatch(&e, "htmlencode", &.{strV("<&>")})})).str);
}

test "option pricing + logistic + DBSL depreciation + bond analytics + deviance (Phase F batch 10)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const num = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) !f64 {
            return (try dispatch(ev, name, args)).num;
        }
    }.f;

    // Black-Scholes: canonical S=E=100,t=1,r=0.05,sigma=0.2 → call 10.4506, put via parity
    const call = try num(&e, "blkshclprc", &.{ numV(100), numV(1), numV(100), numV(0.05), numV(0.2) });
    const put = try num(&e, "blkshptprc", &.{ numV(100), numV(1), numV(100), numV(0.05), numV(0.2) });
    try near(call, 10.4506, 1e-3);
    try near(call - put, 100 - 100 * @exp(-0.05), 1e-9); // put-call parity: C−P = S − E·e^{−rt}
    // Black futures reduces to BS when F = S·e^{rt}
    try near(
        try num(&e, "blackclprc", &.{ numV(100), numV(1), numV(100 * @exp(0.05)), numV(0.05), numV(0.2) }),
        call,
        1e-9,
    );
    // Garman-Kohlhagen with Rf=0 reduces to Black-Scholes
    try near(
        try num(&e, "garkhclprc", &.{ numV(100), numV(1), numV(100), numV(0.05), numV(0), numV(0.2) }),
        call,
        1e-9,
    );
    // Margrabe put-call parity: C − P = X1 − X2
    const mc = try num(&e, "margrclprc", &.{ numV(100), numV(1), numV(90), numV(0.2), numV(0.3), numV(0.5) });
    const mp = try num(&e, "margrptprc", &.{ numV(100), numV(1), numV(90), numV(0.2), numV(0.3), numV(0.5) });
    try near(mc - mp, 100 - 90, 1e-9);

    // logistic
    try near(try num(&e, "logistic", &.{numV(0)}), 0.5, 1e-12);
    try near(try num(&e, "logistic", &.{numV(2)}), 1.0 / (1.0 + @exp(-2.0)), 1e-12);

    // declining-balance-with-SL: accumulated over full life = cost
    try near(try num(&e, "daccdbsl", &.{ numV(10), numV(1000), numV(10), numV(2) }), 1000, 1e-6);
    try near(
        try num(&e, "depdbsl", &.{ numV(1), numV(1000), numV(10), numV(2) }),
        1000 * 2.0 / 10.0,
        1e-9,
    ); // first period is pure DB = v·r/y

    // bond analytics — cross-checked against the enumerated forms and hand cases
    // DUR of a single 1-period zero = 1/(1+y); CONVX = 2/(1+y)²
    try near(try num(&e, "dur", &.{ numV(0.05), numV(1), numV(100) }), 1.0 / 1.05, 1e-9);
    try near(try num(&e, "convx", &.{ numV(0.05), numV(1), numV(100) }), 2.0 / (1.05 * 1.05), 1e-9);
    // BUG-convxfreq: doc p.561 numerator weight is k(k+f), not k(k+1). f=2, y=0.1:
    // P=100*1.1^-.5+100*1.1^-1=186.2553498; num=1*3*100*1.1^-.5+2*4*100*1.1^-1=1013.3115040;
    // C=1013.3115040/(186.2553498*1.1^2*2^2)=1.1240583489. f=1 unchanged (k(k+1)==k(k+f)).
    try near(try num(&e, "convx", &.{ numV(0.1), numV(2), numV(100), numV(100) }), 1.1240583489, 1e-9);
    // DUR PDF example
    try near(try num(&e, "dur", &.{ numV(1.0 / 20.0), numV(1), numV(0.33), numV(0.44), numV(0.55), numV(0.49), numV(0.50), numV(0.22), numV(0.4), numV(0.8), numV(0.01), numV(0.36), numV(0.2), numV(0.4) }), 5.284024988, 1e-6);
    // par bond (coupon = yield) prices at par; DURP/CONVXP match the enumerated DUR/CONVX
    try near(try num(&e, "pvp", &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(1), numV(0.05) }), 1000, 1e-6);
    // BUG (DoS): an absurd coupon count K must be rejected, not loop K times
    try t.expect((try dispatch(&e, "pvp", &.{ numV(1000), numV(0.05), numV(1), numV(1e12), numV(1), numV(0.05) })).isMissing());
    try t.expect((try dispatch(&e, "durp", &.{ numV(1000), numV(0.05), numV(1), numV(1e12), numV(1), numV(0.05) })).isMissing());
    try near(
        try num(&e, "durp", &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(1), numV(0.05) }),
        try num(&e, "dur", &.{ numV(0.05), numV(1), numV(50), numV(50), numV(1050) }),
        1e-6,
    );
    try near(
        try num(&e, "convxp", &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(1), numV(0.05) }),
        try num(&e, "convx", &.{ numV(0.05), numV(1), numV(50), numV(50), numV(1050) }),
        1e-6,
    );
    // YIELDP inverts PVP: par price → coupon-rate yield
    try near(try num(&e, "yieldp", &.{ numV(1000), numV(0.05), numV(1), numV(3), numV(1), numV(1000) }), 0.05, 1e-6);

    // deviance (standard GLM unit deviances)
    try near(try num(&e, "deviance", &.{ strV("NORMAL"), numV(5), numV(3) }), 4, 1e-12);
    try near(try num(&e, "deviance", &.{ strV("POISSON"), numV(2), numV(1) }), 2 * (2 * @log(2.0) - 1), 1e-12);
    try near(try num(&e, "deviance", &.{ strV("BERNOULLI"), numV(1), numV(0.25) }), -2 * @log(0.25), 1e-12);
    try t.expect((try dispatch(&e, "deviance", &.{ strV("WEIBULL"), numV(1), numV(1) })).isMissing());
}

test "put/input variants + table depreciation + holidays + interval/geodist (Phase F batch 11)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const day = struct { // SAS date for a y/m/d
        fn f(y: i64, m: i64, d: i64) f64 {
            return @floatFromInt(sasDate(y, m, d));
        }
    }.f;

    // PUTN/PUTC/INPUTN/INPUTC — runtime-format variants of PUT/INPUT
    try t.expectEqualStrings(
        (try dispatch(&e, "put", &.{ numV(1234.5), strV("dollar10.2") })).str,
        (try dispatch(&e, "putn", &.{ numV(1234.5), strV("dollar10.2") })).str,
    );
    try t.expectEqualStrings(" $1,234.50", (try dispatch(&e, "putn", &.{ numV(1234.5), strV("dollar10.2") })).str); // right-justified in w=10
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "inputn", &.{ strV("5"), strV("best.") })).num);

    // table depreciation
    try t.expectEqual(@as(f64, 400), (try dispatch(&e, "deptab", &.{ numV(2), numV(1000), numV(0.3), numV(0.4), numV(0.3) })).num);
    try t.expectEqual(@as(f64, 700), (try dispatch(&e, "dacctab", &.{ numV(2), numV(1000), numV(0.3), numV(0.4), numV(0.3) })).num);

    // holidays (2020)
    try t.expectEqual(day(2020, 12, 25), (try dispatch(&e, "holiday", &.{ strV("CHRISTMAS"), numV(2020) })).num);
    try t.expectEqual(day(2020, 1, 1), (try dispatch(&e, "holiday", &.{ strV("NEWYEAR"), numV(2020) })).num);
    try t.expectEqual(day(2020, 1, 20), (try dispatch(&e, "holiday", &.{ strV("MLK"), numV(2020) })).num); // 3rd Mon Jan
    try t.expectEqual(day(2020, 11, 26), (try dispatch(&e, "holiday", &.{ strV("THANKSGIVING"), numV(2020) })).num); // 4th Thu Nov
    try t.expectEqual(day(2020, 5, 25), (try dispatch(&e, "holiday", &.{ strV("MEMORIAL"), numV(2020) })).num); // last Mon May
    try t.expectEqual(day(2020, 4, 12), (try dispatch(&e, "holiday", &.{ strV("EASTER"), numV(2020) })).num); // computus
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "holidaytest", &.{ strV("CHRISTMAS"), numV(day(2021, 12, 25)) })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "holidaytest", &.{ strV("CHRISTMAS"), numV(day(2021, 12, 24)) })).num);
    try t.expectEqual(day(2020, 7, 4), (try dispatch(&e, "holidayny", &.{ strV("USINDEPENDENCE"), numV(2020) })).num);
    try t.expect((try dispatch(&e, "holiday", &.{ strV("NOTAHOLIDAY"), numV(2020) })).isMissing());

    // interval validity
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "inttest", &.{strV("MONTH")})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "inttest", &.{strV("QTR")})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "inttest", &.{strV("MONTH3.2")})).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "inttest", &.{strV("DTDAY")})).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "inttest", &.{strV("FORTNIGHT")})).num);

    // GAP-intnxintervals: INTNX/INTCK route through parseInterval — WEEKDAY, INTCK
    // SEMIYEAR/SEMIMONTH/TENDAY parity, DT/time intervals, multipliers, shift-index.
    try t.expectEqual(day(2020, 1, 6), (try dispatch(&e, "intnx", &.{ strV("weekday"), numV(day(2020, 1, 1)), numV(3) })).num); // Wed +3 → Mon
    try t.expectEqual(day(2020, 3, 18), (try dispatch(&e, "intnx", &.{ strV("weekday"), numV(day(2020, 3, 15)), numV(3) })).num); // Sun +3 → Wed
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "intck", &.{ strV("weekday"), numV(day(2020, 3, 13)), numV(day(2020, 3, 18)) })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intck", &.{ strV("semiyear"), numV(day(2020, 1, 1)), numV(day(2020, 7, 1)) })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intck", &.{ strV("semimonth"), numV(day(2020, 3, 1)), numV(day(2020, 3, 20)) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intck", &.{ strV("tenday"), numV(day(2020, 3, 1)), numV(day(2020, 3, 25)) })).num);
    try t.expectEqual(day(2020, 5, 1), (try dispatch(&e, "intnx", &.{ strV("month2"), numV(day(2020, 3, 15)), numV(1) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intck", &.{ strV("month2"), numV(day(2020, 1, 1)), numV(day(2020, 5, 1)) })).num);
    try t.expectEqual(day(2020, 4, 30), (try dispatch(&e, "intnx", &.{ strV("month2"), numV(day(2020, 3, 15)), numV(0), strV("e") })).num); // END alignment on a multiplier
    try t.expectEqual(day(2019, 11, 1), (try dispatch(&e, "intnx", &.{ strV("qtr.2"), numV(day(2020, 1, 15)), numV(0) })).num); // shifted quarter Nov–Jan
    try t.expectEqual(day(2019, 3, 1), (try dispatch(&e, "intnx", &.{ strV("year.3"), numV(day(2020, 1, 15)), numV(0) })).num); // year starting 01Mar
    try t.expectEqual(day(2019, 12, 1), (try dispatch(&e, "intnx", &.{ strV("month2.2"), numV(day(2020, 1, 15)), numV(0) })).num);
    // datetime (seconds) and time intervals
    try t.expectEqual(day(2020, 4, 1) * 86400, (try dispatch(&e, "intnx", &.{ strV("dtmonth"), numV(day(2020, 3, 15) * 86400 + 43200), numV(1) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intck", &.{ strV("dtmonth"), numV(day(2020, 1, 1) * 86400), numV(day(2020, 3, 1) * 86400) })).num);
    try t.expectEqual(day(2020, 1, 1) * 86400 + 17 * 3600, (try dispatch(&e, "intnx", &.{ strV("hour"), numV(day(2020, 1, 1) * 86400 + 43200), numV(5) })).num);
    try t.expectEqual(@as(f64, 12), (try dispatch(&e, "intck", &.{ strV("hour"), numV(day(2020, 1, 1) * 86400), numV(day(2020, 1, 1) * 86400 + 43200) })).num);

    // geodist: Mobile,AL → Asheville,NC (PDF example: 748.6529147 km / 465.29081088 mi)
    try near((try dispatch(&e, "geodist", &.{ numV(30.68), numV(-88.25), numV(35.43), numV(-82.55) })).num, 748.6529147, 0.5);
    try near((try dispatch(&e, "geodist", &.{ numV(30.68), numV(-88.25), numV(35.43), numV(-82.55), strV("M") })).num, 465.29081088, 0.4);
}

test "holiday range/count + interval metadata + trunc + bivariate normal (Phase F batch 12)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const num = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) !f64 {
            return (try dispatch(ev, name, args)).num;
        }
    }.f;
    const day = struct {
        fn f(y: i64, m: i64, d: i64) f64 {
            return @floatFromInt(sasDate(y, m, d));
        }
    }.f;

    // HOLIDAYCK: occurrences of a specific named holiday in a range (correct for the
    // holidays we define); an unrecognized name → missing, never a wrong 0.
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "holidayck", &.{ strV("CHRISTMAS"), numV(day(2020, 1, 1)), numV(day(2022, 12, 31)) })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "holidayck", &.{ strV("CHRISTMAS"), numV(day(2020, 1, 1)), numV(day(2020, 6, 1)) })).num);
    try t.expect((try dispatch(&e, "holidayck", &.{ strV("GOODFRIDAY"), numV(day(2020, 1, 1)), numV(day(2020, 12, 31)) })).isMissing());

    // interval metadata (supported subset)
    try t.expectEqual(@as(f64, 12), (try dispatch(&e, "intseas", &.{strV("MONTH")})).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "intseas", &.{strV("QTR")})).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "intseas", &.{strV("MONTH2")})).num); // multiplier divides
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intseas", &.{strV("YEAR")})).num);
    try t.expect((try dispatch(&e, "intseas", &.{strV("FORTNIGHT")})).isMissing());
    // BUG-intervalcrash: an over-long multiplier / base must not overflow-panic → missing
    try t.expect((try dispatch(&e, "intseas", &.{strV("MONTH99999999999999999999")})).isMissing());
    try t.expect((try dispatch(&e, "intseas", &.{strV("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA")})).isMissing());
    try t.expect((try dispatch(&e, "intnest", &.{ strV("MONTH"), strV("YEAR99999999999999999999") })).isMissing());
    _ = try dispatch(&e, "intindex", &.{ strV("MONTH99999999999999999999"), numV(21990) }); // no panic
    _ = try dispatch(&e, "intcycle", &.{strV("QTR88888888888888888888")}); // no panic
    try t.expectEqualStrings("YEAR", (try dispatch(&e, "intcycle", &.{strV("MONTH")})).str);
    try t.expectEqualStrings("YEAR", (try dispatch(&e, "intcycle", &.{strV("QTR")})).str);

    // INTCINDEX: cycle index — week-of-year for day/week (doc: 01SEP2021 → 36),
    // month-of-year / qtr-of-year for month/qtr.
    try t.expectEqual(@as(f64, 36), (try dispatch(&e, "intcindex", &.{ strV("day"), numV(22524) })).num); // 01SEP2021
    try t.expectEqual(@as(f64, 36), (try dispatch(&e, "intcindex", &.{ strV("week"), numV(22524) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "intcindex", &.{ strV("month"), numV(22354) })).num); // 15MAR2021
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "intcindex", &.{ strV("qtr"), numV(22507) })).num); // 15AUG2021
    try t.expect((try dispatch(&e, "intcindex", &.{ strV("hour"), numV(22524) })).isMissing()); // time not modeled
    // INTINDEX — verified against the PDF examples (MONTH/DEC→12, QTR→1, DAY→weekday)
    try t.expectEqual(@as(f64, 12), (try dispatch(&e, "intindex", &.{ strV("MONTH"), numV(day(2012, 12, 1)) })).num);
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "intindex", &.{ strV("MONTH"), numV(day(2020, 3, 15)) })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intindex", &.{ strV("QTR"), numV(day(2013, 1, 1)) })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intindex", &.{ strV("QTR"), numV(day(2013, 3, 31)) })).num);
    try t.expectEqual(@as(f64, 4), (try dispatch(&e, "intindex", &.{ strV("QTR"), numV(day(2020, 11, 1)) })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "intindex", &.{ strV("SEMIYEAR"), numV(day(2020, 8, 1)) })).num);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "intindex", &.{ strV("DAY"), numV(day(2012, 12, 7)) })).num); // Fri = 6 (PDF)
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "intindex", &.{ strV("SEMIMONTH"), numV(day(2013, 3, 20)) })).num); // (3-1)*2+2
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "intindex", &.{ strV("TENDAY"), numV(day(2013, 2, 15)) })).num); // (2-1)*3+2

    // TRUNC: byte truncation — 8 bytes = identity; 1/5→3 bytes = SAS's 0.1999816895
    try t.expectEqual(@as(f64, 3.14159), (try dispatch(&e, "trunc", &.{ numV(3.14159), numV(8) })).num);
    try t.expectEqual(@as(f64, 1.0), (try dispatch(&e, "trunc", &.{ numV(1.0), numV(3) })).num);
    try near((try dispatch(&e, "trunc", &.{ numV(1.0 / 5.0), numV(3) })).num, 0.1999816895, 1e-9); // exact SAS value
    try t.expect((try dispatch(&e, "trunc", &.{ numV(1.0 / 5.0), numV(3) })).num != 0.2); // and NOT the original

    // bivariate normal — exact anchors
    try near(try num(&e, "probbnrm", &.{ numV(0), numV(0), numV(0) }), 0.25, 1e-9);
    try near(try num(&e, "probbnrm", &.{ numV(0), numV(0), numV(0.5) }), 0.25 + std.math.asin(@as(f64, 0.5)) / (2 * std.math.pi), 1e-7);
    try near(try num(&e, "probbnrm", &.{ numV(1), numV(1), numV(0) }), stdNormCdf(1) * stdNormCdf(1), 1e-9); // independent
    try near(try num(&e, "probbnrm", &.{ numV(5), numV(5), numV(0.3) }), 1, 1e-6); // both far right

    // VTYPE (value type) + INTNEST (a finer interval nests in a coarser one)
    try t.expectEqualStrings("N", (try dispatch(&e, "vtype", &.{numV(5)})).str);
    try t.expectEqualStrings("C", (try dispatch(&e, "vtype", &.{strV("x")})).str);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intnest", &.{ strV("MONTH"), strV("YEAR") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intnest", &.{ strV("MONTH"), strV("QTR") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "intnest", &.{ strV("QTR"), strV("YEAR") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "intnest", &.{ strV("QTR"), strV("MONTH") })).num); // coarser in finer

    // INTGET / INTFIT — the interval implied by dates (PDF examples: DAY2, MONTH4)
    const dd = struct {
        fn f(ev: *eval.Evaluator, y: i64, m: i64, d: i64) eval.Error!f64 {
            return (try dispatch(ev, "mdy", &.{ numV(@floatFromInt(m)), numV(@floatFromInt(d)), numV(@floatFromInt(y)) })).num;
        }
    }.f;
    try t.expectEqualStrings("DAY2", (try dispatch(&e, "intget", &.{ numV(try dd(&e, 2000, 3, 1)), numV(try dd(&e, 2000, 3, 3)), numV(try dd(&e, 2000, 3, 9)) })).str);
    try t.expectEqualStrings("MONTH4", (try dispatch(&e, "intget", &.{ numV(try dd(&e, 2000, 1, 15)), numV(try dd(&e, 2000, 5, 15)), numV(try dd(&e, 2000, 9, 15)) })).str);
    try t.expectEqualStrings("MONTH1", (try dispatch(&e, "intfit", &.{ numV(try dd(&e, 2020, 1, 15)), numV(try dd(&e, 2020, 2, 15)) })).str);
    try t.expectEqualStrings("YEAR2", (try dispatch(&e, "intfit", &.{ numV(try dd(&e, 2018, 6, 1)), numV(try dd(&e, 2020, 6, 1)) })).str);
    try t.expectEqualStrings("DAY5", (try dispatch(&e, "intfit", &.{ numV(try dd(&e, 2020, 1, 1)), numV(try dd(&e, 2020, 1, 6)) })).str);

    // INTFMT(interval, 'L'|'S') → recommended format — SAS's own doc examples (p.1070).
    // Multiplier/shift are ignored: month2 → MONTH, week3.2 → WEEK.
    try t.expectEqualStrings("YYQC4.", (try dispatch(&e, "intfmt", &.{ strV("qtr"), strV("s") })).str);
    try t.expectEqualStrings("YYQC6.", (try dispatch(&e, "intfmt", &.{ strV("qtr"), strV("l") })).str);
    try t.expectEqualStrings("MONYY7.", (try dispatch(&e, "intfmt", &.{ strV("month"), strV("l") })).str);
    try t.expectEqualStrings("WEEKDATX15.", (try dispatch(&e, "intfmt", &.{ strV("week"), strV("short") })).str);
    try t.expectEqualStrings("WEEKDATX17.", (try dispatch(&e, "intfmt", &.{ strV("week3.2"), strV("l") })).str);
    try t.expectEqualStrings("DATE9.", (try dispatch(&e, "intfmt", &.{ strV("day"), strV("long") })).str);
    try t.expectEqualStrings("MONYY7.", (try dispatch(&e, "intfmt", &.{ strV("month2"), strV("long") })).str);
    try t.expect((try dispatch(&e, "intfmt", &.{ strV("fortnight"), strV("l") })).isMissing()); // unknown interval

    // MVALID(libname, string, member-type [,rule]) → 1 valid / 0 invalid.
    // COMPAT (default): letter/underscore start, alnum/underscore body, ≤32 chars.
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("myvar"), strV("data") })).num);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("_x1"), strV("data") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("1abc"), strV("data") })).num); // digit start
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("a b"), strV("data") })).num); // blank
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("a#b"), strV("data") })).num); // bad char
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"), strV("data") })).num); // 33 chars
    // EXTEND: blanks allowed, but not / \ * ? " < > | : - or a leading blank/period.
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("a b"), strV("data"), strV("extend") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("a-b"), strV("data"), strV("extend") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV("a/b"), strV("data"), strV("extend") })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "mvalid", &.{ strV("work"), strV(".ab"), strV("data"), strV("extend") })).num); // leading period
}

test "noncentral distributions + noncentrality solvers (Phase F batch 14)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;
    const num = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) !f64 {
            return (try dispatch(ev, name, args)).num;
        }
    }.f;

    // nc=0 reduces each noncentral CDF to the central one already verified in batch 7
    try near(try num(&e, "probchi", &.{ numV(3.841458821), numV(1), numV(0) }), 0.95, 1e-6);
    try near(try num(&e, "probchi", &.{ numV(3.841458821), numV(1) }), 0.95, 1e-6);
    try near(try num(&e, "probf", &.{ numV(1), numV(10), numV(10), numV(0) }), 0.5, 1e-9);
    try near(try num(&e, "probt", &.{ numV(0.9), numV(5), numV(0) }), 0.7953143998, 1e-7); // central AS243 reduction

    // a positive noncentrality shifts mass right → CDF at a fixed x drops below central
    const pc = try num(&e, "probchi", &.{ numV(3.841458821), numV(1), numV(4) });
    try t.expect(pc < 0.95 and pc > 0);

    // CNONCT/FNONCT/TNONCT round-trip: pick nc, get the prob, recover nc
    const chi_p = try num(&e, "probchi", &.{ numV(6), numV(2), numV(5) });
    try near(try num(&e, "cnonct", &.{ numV(6), numV(2), numV(chi_p) }), 5, 1e-3);
    const f_p = try num(&e, "probf", &.{ numV(2), numV(4), numV(20), numV(6) });
    try near(try num(&e, "fnonct", &.{ numV(2), numV(4), numV(20), numV(f_p) }), 6, 1e-2);
    const t_p = try num(&e, "probt", &.{ numV(2), numV(10), numV(1.5) });
    try near(try num(&e, "tnonct", &.{ numV(2), numV(10), numV(t_p) }), 1.5, 1e-2);

    // PROBMED — sample-median CDF. PDF example: PROBMED(5,-0.1)=0.4256380897 (odd n);
    // even n symmetric at x=0 → 0.5; n=1 → Phi(x).
    try near(try num(&e, "probmed", &.{ numV(5), numV(-0.1) }), 0.4256380897, 1e-8); // odd: closed form
    try near(try num(&e, "probmed", &.{ numV(4), numV(0) }), 0.5, 1e-5); // even: Simpson integral
    try near(try num(&e, "probmed", &.{ numV(6), numV(0) }), 0.5, 1e-5);
    try near(try num(&e, "probmed", &.{ numV(1), numV(0.5) }), stdNormCdf(0.5), 1e-9); // odd
    try near(try num(&e, "probmed", &.{ numV(3), numV(0) }), 0.5, 1e-9); // odd, symmetric

    // prob ≥ the central probability → noncentrality is 0 (SAS: nonnegative param)
    const central = try num(&e, "probchi", &.{ numV(3.841458821), numV(1) });
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "cnonct", &.{ numV(3.841458821), numV(1), numV(central) })).num); // prob=central
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "cnonct", &.{ numV(3.841458821), numV(1), numV(0.99) })).num); // 0.99 > central
}

test "cryptographic hashes: md5/sha256/hashing/hmac (Phase F batch 16)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const str = struct {
        fn f(ev: *eval.Evaluator, name: []const u8, args: []const Value) ![]const u8 {
            return (try dispatch(ev, name, args)).str;
        }
    }.f;

    // raw digests → check via hex; standard NIST/RFC test vectors
    try t.expectEqualStrings("900150983cd24fb0d6963f7d28e17f72", try hexEncode(&e, try str(&e, "md5", &.{strV("abc")})));
    try t.expectEqualStrings("d41d8cd98f00b204e9800998ecf8427e", try hexEncode(&e, try str(&e, "md5", &.{strV("")})));
    try t.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", try hexEncode(&e, try str(&e, "sha256", &.{strV("abc")})));
    // MD5/SHA256 return the raw binary digest (16/32 bytes)
    try t.expectEqual(@as(usize, 16), (try dispatch(&e, "md5", &.{strV("abc")})).str.len);
    try t.expectEqual(@as(usize, 32), (try dispatch(&e, "sha256", &.{strV("abc")})).str.len);

    // SHA256HEX
    try t.expectEqualStrings("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", try str(&e, "sha256hex", &.{strV("abc")}));

    // SHA256HMACHEX — SAS's own documented example
    try t.expectEqualStrings(
        "f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8",
        try str(&e, "sha256hmachex", &.{ strV("key"), strV("The quick brown fox jumps over the lazy dog") }),
    );

    // HASHING(method, msg) → UPPERCASE hex (SAS doc p.975 example); several methods
    try t.expectEqualStrings("900150983CD24FB0D6963F7D28E17F72", try str(&e, "hashing", &.{ strV("MD5"), strV("abc") }));
    try t.expectEqualStrings("BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD", try str(&e, "hashing", &.{ strV("SHA256"), strV("abc") }));
    try t.expectEqualStrings("A9993E364706816ABA3E25717850C26C9CD0D89D", try str(&e, "hashing", &.{ strV("SHA1"), strV("abc") }));
    try t.expectEqualStrings("352441C2", try str(&e, "hashing", &.{ strV("CRC32"), strV("abc") })); // IEEE CRC-32
    // unknown method → BLANK CHARACTER, not `.` (BUG-charfnsmissingtype). HASHING is
    // `Categories: Character` (p.975): the old premise here asserted isMissing(),
    // i.e. a numeric out of a character function, which flipped the LHS's type.
    const bad_meth = try dispatch(&e, "hashing", &.{ strV("CRC99"), strV("abc") });
    try t.expect(bad_meth == .str);
    try t.expectEqualStrings("", bad_meth.str);
    const bad_hmeth = try dispatch(&e, "hashing_hmac", &.{ strV("CRC99"), strV("k"), strV("abc") });
    try t.expect(bad_hmeth == .str);

    // HASHING_HMAC(method, key, msg) → UPPERCASE hex; matches the SHA256HMAC vector
    try t.expectEqualStrings(
        "F7BC83F430538424B13298E6AA6FB143EF4D59A14946175997479DBC2D1A3CD8",
        try str(&e, "hashing_hmac", &.{ strV("SHA256"), strV("key"), strV("The quick brown fox jumps over the lazy dog") }),
    );

    // HASHING_INIT/PART/TERM — streaming digest. Feed "abc" as "a"+"bc"; TERM's
    // final digest equals one-shot sha256("abc"), UPPERCASE (doc p.986 example).
    const hs = try dispatch(&e, "hashing_init", &.{strV("SHA256")});
    try t.expect(hs.num > 0); // positive-integer handle
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "hashing_part", &.{ numV(hs.num), strV("a") })).num);
    _ = try dispatch(&e, "hashing_part", &.{ numV(hs.num), strV("bc") });
    try t.expectEqualStrings(
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
        (try dispatch(&e, "hashing_term", &.{numV(hs.num)})).str,
    );
    // MD5 of the empty message fed via one empty part → known empty-MD5 vector.
    const hm = try dispatch(&e, "hashing_init", &.{strV("md5")});
    _ = try dispatch(&e, "hashing_part", &.{ numV(hm.num), strV("") });
    try t.expectEqualStrings(
        "D41D8CD98F00B204E9800998ECF8427E",
        (try dispatch(&e, "hashing_term", &.{numV(hm.num)})).str,
    );
    // multi-arg PART concatenates; matches sha256("abc")
    const hc = try dispatch(&e, "hashing_init", &.{strV("SHA256")});
    _ = try dispatch(&e, "hashing_part", &.{ numV(hc.num), strV("a"), strV("b"), strV("c") });
    try t.expectEqualStrings(
        "BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD",
        (try dispatch(&e, "hashing_term", &.{numV(hc.num)})).str,
    );
    // invalid method → missing handle; invalid handle → NUMERIC missing digest.
    // That last one is NOT the BUG-charfnsmissingtype class and must not be
    // "fixed": p.986 states the split explicitly — "If the handle is invalid,
    // HASHING_TERM returns a numeric missing value" (here) versus "If the final
    // digest cannot be computed, the result is blank" (the digest arms, which are
    // unreachable today because INIT validates the method).
    try t.expect((try dispatch(&e, "hashing_init", &.{strV("SHA999")})).isMissing());
    try t.expect((try dispatch(&e, "hashing_term", &.{numV(9999)})).isMissing());
    try t.expect((try dispatch(&e, "hashing_part", &.{ numV(9999), strV("x") })).isMissing());

    // HASHING_HMAC_INIT — streaming HMAC. SAS's own doc example (p.982): key="key",
    // msg="The quick brown fox jumps over the lazy dog", uppercase hex.
    const msg = "The quick brown fox jumps over the lazy dog";
    const cases = .{
        .{ "md5", "80070713463E7749B90C2DC24911E275" },
        .{ "sha1", "DE7C9B85B8B78AA6BC8A7A36F70A90701C9DB4D9" },
        .{ "sha256", "F7BC83F430538424B13298E6AA6FB143EF4D59A14946175997479DBC2D1A3CD8" },
    };
    inline for (cases) |c| {
        const hh = try dispatch(&e, "hashing_hmac_init", &.{ strV(c[0]), strV("key") });
        try t.expect(hh.num > 0);
        _ = try dispatch(&e, "hashing_part", &.{ numV(hh.num), strV(msg) });
        try t.expectEqualStrings(c[1], (try dispatch(&e, "hashing_term", &.{numV(hh.num)})).str);
    }
    try t.expect((try dispatch(&e, "hashing_hmac_init", &.{ strV("SHA999"), strV("key") })).isMissing());
}

test "random-variate generators: reproducible stream + distributions (Phase F batch 17)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const near = struct {
        fn f(got: f64, want: f64, tol: f64) !void {
            try t.expect(@abs(got - want) < tol);
        }
    }.f;

    // RANUNI: the first draw of a fresh stream seeded 1 is the documented
    // 16807/(2^31−1); UNIFORM is an alias; both draw from the SAME stream.
    try near((try dispatch(&e, "ranuni", &.{numV(1)})).num, 16807.0 / 2147483647.0, 1e-9);
    // subsequent draws advance the stream (differ from the first)
    const ud = (try dispatch(&e, "uniform", &.{numV(1)})).num;
    try t.expect(ud != 16807.0 / 2147483647.0 and ud > 0 and ud < 1);

    // a fresh evaluator re-seeded 1 reproduces the first value (reproducibility)
    var h2 = harness();
    defer h2.deinit();
    h2.prime();
    var e2 = h2.ev();
    try near((try dispatch(&e2, "ranuni", &.{numV(1)})).num, 16807.0 / 2147483647.0, 1e-12);

    // uniform mean over many draws ≈ 0.5; all in (0,1)
    var su: f64 = 0;
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        const u = (try dispatch(&e, "ranuni", &.{numV(1)})).num;
        try t.expect(u > 0 and u < 1);
        su += u;
    }
    try near(su / 5000.0, 0.5, 0.02);

    // RANEXP > 0; RANNOR/NORMAL mean ≈ 0 over many draws; RANCAU finite
    try t.expect((try dispatch(&e, "ranexp", &.{numV(1)})).num > 0);
    var sn: f64 = 0;
    i = 0;
    while (i < 5000) : (i += 1) sn += (try dispatch(&e, "rannor", &.{numV(1)})).num;
    try near(sn / 5000.0, 0, 0.06);
    try t.expect(std.math.isFinite((try dispatch(&e, "rancau", &.{numV(1)})).num));

    // RANTRI in (0,1); RANPOI/RANBIN non-negative integers; RANGAM > 0
    const tri = (try dispatch(&e, "rantri", &.{ numV(1), numV(0.5) })).num;
    try t.expect(tri >= 0 and tri <= 1);
    const poi = (try dispatch(&e, "ranpoi", &.{ numV(3), numV(4.5) })).num;
    try t.expect(poi >= 0 and poi == @floor(poi));
    const bin = (try dispatch(&e, "ranbin", &.{ numV(5), numV(20), numV(0.3) })).num;
    try t.expect(bin >= 0 and bin <= 20 and bin == @floor(bin));
    try t.expect((try dispatch(&e, "rangam", &.{ numV(7), numV(2.0) })).num > 0);

    // RANTBL returns a 1-based index into the probability table
    const tbl = (try dispatch(&e, "rantbl", &.{ numV(9), numV(0.2), numV(0.3), numV(0.5) })).num;
    try t.expect(tbl >= 1 and tbl <= 3);

    // RAND(dist,…) over the shared stream — distribution sanity
    var ru: f64 = 0;
    var rc: f64 = 0;
    i = 0;
    while (i < 5000) : (i += 1) {
        ru += (try dispatch(&e, "rand", &.{strV("UNIFORM")})).num;
        rc += (try dispatch(&e, "rand", &.{ strV("CHISQUARE"), numV(4) })).num;
    }
    try near(ru / 5000.0, 0.5, 0.02); // uniform mean ½
    try near(rc / 5000.0, 4, 0.3); // χ²(4) mean = df = 4
    try t.expect(std.math.isFinite((try dispatch(&e, "rand", &.{strV("NORMAL")})).num));
    try t.expect((try dispatch(&e, "rand", &.{strV("EXPONENTIAL")})).num > 0);
    const rb = (try dispatch(&e, "rand", &.{ strV("BINOMIAL"), numV(0.3), numV(20) })).num;
    try t.expect(rb >= 0 and rb <= 20 and rb == @floor(rb));
    const rbeta = (try dispatch(&e, "rand", &.{ strV("BETA"), numV(2), numV(3) })).num;
    try t.expect(rbeta > 0 and rbeta < 1);
    try t.expect((try dispatch(&e, "rand", &.{strV("WEIBULLX")})).isMissing()); // unsupported → missing
}

test "PRX regex functions wired through dispatch (prxparse/match/posn/paren/change)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // PRXPARSE → id; PRXMATCH(id, src) → 1-based position (0 = no match)
    const id = (try dispatch(&e, "prxparse", &.{strV("/(\\d+)-(\\d+)/")})).num;
    try t.expect(id >= 1);
    try t.expectEqual(@as(f64, 6), (try dispatch(&e, "prxmatch", &.{ numV(id), strV("code 12-345") })).num); // '1' at col 6
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "prxmatch", &.{ numV(id), strV("nope") })).num);

    // PRXMATCH also accepts a literal pattern (compiled on the fly)
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "prxmatch", &.{ strV("/\\w+/"), strV("hello") })).num);

    // PRXPOSN(id, n, src) → captured group text; PRXPAREN → last matched group
    try t.expectEqualStrings("12", (try dispatch(&e, "prxposn", &.{ numV(id), numV(1), strV("code 12-345") })).str);
    try t.expectEqualStrings("345", (try dispatch(&e, "prxposn", &.{ numV(id), numV(2), strV("code 12-345") })).str);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "prxparen", &.{numV(id)})).num);

    // PRXCHANGE(id, times, src) — substitution with a capture reference
    const sid = (try dispatch(&e, "prxparse", &.{strV("s/(\\w+)@(\\w+)/$2.$1/")})).num;
    try t.expectEqualStrings("b.a", (try dispatch(&e, "prxchange", &.{ numV(sid), numV(-1), strV("a@b") })).str);
    const gid = (try dispatch(&e, "prxparse", &.{strV("s/\\s+/_/g")})).num;
    try t.expectEqualStrings("a_b_c", (try dispatch(&e, "prxchange", &.{ numV(gid), numV(1), strV("a  b   c") })).str);

    // a bad pattern → PRXPARSE returns missing
    try t.expect((try dispatch(&e, "prxparse", &.{strV("/(unclosed/")})).isMissing());
}

test "PATHNAME(libref) returns the bound dir; blank for unknown ref / type 'F' (GAP-pathname)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const refs = [_]DiskLibref{.{ .name = "target", .dir = "/study/sdtm" }};
    bindLibrefs(&refs);
    defer bindLibrefs(&.{}); // test isolation — the slice dies with this frame

    // case-insensitive libref, trimmed arg (the %sysfunc text route pads)
    try t.expectEqualStrings("/study/sdtm", (try dispatch(&e, "pathname", &.{strV("TARGET")})).str);
    try t.expectEqualStrings("/study/sdtm", (try dispatch(&e, "pathname", &.{strV(" target ")})).str);
    // explicit type 'L' still resolves; 'F' (fileref) has no store → blank
    try t.expectEqualStrings("/study/sdtm", (try dispatch(&e, "pathname", &.{ strV("target"), strV("L") })).str);
    try t.expectEqualStrings("", (try dispatch(&e, "pathname", &.{ strV("target"), strV("F") })).str);
    // unknown ref → blank
    try t.expectEqualStrings("", (try dispatch(&e, "pathname", &.{strV("nope")})).str);
    // WORK is never blank — real SAS always has a WORK temp dir; study macros
    // probe PATHNAME(WORK) as a health check (QA-pathnamework).
    try t.expectEqualStrings("/tmp", (try dispatch(&e, "pathname", &.{strV("WORK")})).str);
}

test "BUG-sclbind: SCL OPEN->FETCH->GETVARN returns a REAL value through dispatch" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const a = h.arena.allocator();

    // a live Library the executor would own, bound via the public hook
    const Library = @import("exec.zig").Library;
    const DS = @import("dataset.zig").Dataset;
    var lib = Library.init(a);
    const ds = try a.create(DS);
    ds.* = DS.init(a, "have");
    _ = try ds.addColumn("name", .char);
    _ = try ds.addColumn("age", .num);
    try ds.appendRow(&.{ strV("Alice"), numV(30) });
    try ds.appendRow(&.{ strV("Bob"), numV(25) });
    try lib.put("have", ds);
    bindLibrary(&lib); // the BUG-sclbind fix: without this, OPEN returns 0

    // every SCL function reached THROUGH functions.dispatch (the evaluator path)
    const id = (try dispatch(&e, "open", &.{strV("work.have")})).num;
    try t.expect(id >= 1); // OPEN resolved the member (not 0)
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "exist", &.{strV("have")})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "attrn", &.{ numV(id), strV("NOBS") })).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "varnum", &.{ numV(id), strV("age") })).num);

    // the crux of BUG-sclbind — fetch a row and read a variable → a REAL value
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "fetch", &.{numV(id)})).num);
    const age = (try dispatch(&e, "getvarn", &.{ numV(id), numV(2) })).num;
    try t.expect(!std.math.isNan(age)); // NOT missing
    try t.expectEqual(@as(f64, 30), age);
    try t.expectEqualStrings("Alice", (try dispatch(&e, "getvarc", &.{ numV(id), numV(1) })).str);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "curobs", &.{numV(id)})).num);

    // second row, then close
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "fetch", &.{numV(id)})).num);
    try t.expectEqual(@as(f64, 25), (try dispatch(&e, "getvarn", &.{ numV(id), numV(2) })).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "close", &.{numV(id)})).num);
}

test "FMTINFO metadata + unknown function logs a single ERROR diagnostic" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // FMTINFO — the doc's BEST example, plus category for common formats
    try t.expectEqualStrings("num", (try dispatch(&e, "fmtinfo", &.{ strV("best"), strV("cat") })).str);
    try t.expectEqualStrings("BOTH", (try dispatch(&e, "fmtinfo", &.{ strV("best"), strV("type") })).str);
    try t.expectEqualStrings("SAS System chooses best notation", (try dispatch(&e, "fmtinfo", &.{ strV("best"), strV("desc") })).str);
    try t.expectEqualStrings("num", (try dispatch(&e, "fmtinfo", &.{ strV("comma8."), strV("cat") })).str);
    try t.expectEqualStrings("curr", (try dispatch(&e, "fmtinfo", &.{ strV("dollar12.2"), strV("cat") })).str);
    try t.expectEqualStrings("char", (try dispatch(&e, "fmtinfo", &.{ strV("$char20."), strV("cat") })).str);
    try t.expectEqualStrings("date", (try dispatch(&e, "fmtinfo", &.{ strV("date9."), strV("cat") })).str);

    // unknown/unimplemented function: exactly ONE diagnostic (an ERROR), not NOTE+ERROR
    const before = e.diags.count();
    _ = try dispatch(&e, "no_such_function_xyz", &.{numV(1)});
    try t.expectEqual(@as(usize, 1), e.diags.count() - before);
}

test "SYMGET/SYMEXIST/RESOLVE/MODEXIST via the bound macro store" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const a = h.arena.allocator();

    const Library = @import("exec.zig").Library;
    var lib = Library.init(a);
    try lib.setMacroVar("city", "Paris");
    try lib.setMacroVar("n", "42");
    bindLibrary(&lib);

    // SYMGET → the macro value; unknown → blank
    try t.expectEqualStrings("Paris", (try dispatch(&e, "symget", &.{strV("city")})).str);
    try t.expectEqualStrings("42", (try dispatch(&e, "symget", &.{strV("N")})).str); // case-insensitive
    try t.expectEqualStrings("", (try dispatch(&e, "symget", &.{strV("missing")})).str);

    // SYMEXIST → 1/0
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "symexist", &.{strV("city")})).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "symexist", &.{strV("nope")})).num);

    // RESOLVE → &var substitution ('.' delimiter consumed, unknown left as-is)
    try t.expectEqualStrings("in Paris now", (try dispatch(&e, "resolve", &.{strV("in &city now")})).str);
    try t.expectEqualStrings("Parisian", (try dispatch(&e, "resolve", &.{strV("&city.ian")})).str);
    try t.expectEqualStrings("&unknown", (try dispatch(&e, "resolve", &.{strV("&unknown")})).str);

    // MODEXIST → 0 (no external module system)
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "modexist", &.{strV("mymod")})).num);
}

test "VFORMATX/VVALUEX correct when the PDV var carries a format (stub root cause is exec-side)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    // define a variable WITH a format directly in the PDV (as a running DATA step has)
    _ = try h.pdv.define("amt", .num);
    try h.pdv.set("amt", .{ .num = 1234.5 });
    h.pdv.setFormat("amt", "dollar10.2");
    try t.expectEqualStrings("DOLLAR10.2", (try dispatch(&e, "vformatx", &.{strV("amt")})).str);
    try t.expectEqualStrings(" $1,234.50", (try dispatch(&e, "vvaluex", &.{strV("amt")})).str);
}

test "V-attribute cluster: VINFORMAT*X + VFORMAT*X decompose the PDV var's attrs" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    _ = try h.pdv.define("amt", .num);
    try h.pdv.set("amt", .{ .num = 5 });
    h.pdv.setFormat("amt", "comma10.2");
    h.pdv.setInformat("amt", "comma8.");
    // format side
    try t.expectEqualStrings("COMMA10.2", (try dispatch(&e, "vformatx", &.{strV("amt")})).str);
    try t.expectEqualStrings("COMMA", (try dispatch(&e, "vformatnx", &.{strV("amt")})).str);
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "vformatwx", &.{strV("amt")})).num);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "vformatdx", &.{strV("amt")})).num);
    // informat side (net-new)
    try t.expectEqualStrings("COMMA8.", (try dispatch(&e, "vinformatx", &.{strV("amt")})).str);
    try t.expectEqualStrings("COMMA", (try dispatch(&e, "vinformatnx", &.{strV("amt")})).str);
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "vinformatwx", &.{strV("amt")})).num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "vinformatdx", &.{strV("amt")})).num);
}

test "QA-dollarwdot: plain $w. strips leading blanks and reads a lone '.' as char missing" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    // lone '.' (incl. the blank-padded implicit num->char form) -> "" — gen2
    // VSSTRESC = input(<numeric missing>, $40.) must be blank, not "."
    try t.expectEqualStrings("", (try dispatch(&e, "input", &.{ strV("."), strV("$8.") })).str);
    try t.expectEqualStrings("", (try dispatch(&e, "input", &.{ strV("           ."), strV("$40.") })).str);
    // leading blanks stripped ($w. left-aligns); interior dots untouched
    try t.expectEqualStrings("abc", (try dispatch(&e, "input", &.{ strV("  abc"), strV("$8.") })).str);
    try t.expectEqualStrings("a.b", (try dispatch(&e, "input", &.{ strV("a.b"), strV("$8.") })).str);
    // $CHARw. keeps the field verbatim — no strip, no dot rule
    try t.expectEqualStrings("  . ", (try dispatch(&e, "input", &.{ strV("  . "), strV("$char4.") })).str);
}

test "BUG-yearcutoff: input() FUNCTION applies YEARCUTOFF (SAS 9.4 default 1926)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    defer format.setYearCutoff(1926); // isolation
    format.setYearCutoff(1926);

    // a 2-digit-year read must equal the 4-digit read of the same (2024, not 1924)
    const y24 = (try dispatch(&e, "input", &.{ strV("01/01/24"), strV("mmddyy8.") })).num;
    const y2024 = (try dispatch(&e, "input", &.{ strV("01/01/2024"), strV("mmddyy10.") })).num;
    try t.expectEqual(y2024, y24);
    // DATE7 informat (previously gave a year-20-AD negative)
    const d20 = (try dispatch(&e, "input", &.{ strV("16JAN20"), strV("date7.") })).num;
    const d2020 = (try dispatch(&e, "input", &.{ strV("16JAN2020"), strV("date9.") })).num;
    try t.expectEqual(d2020, d20);
    try t.expect(d20 > 0);
    // ddmmyy / yymmdd honor it too
    const dd = (try dispatch(&e, "input", &.{ strV("01/01/24"), strV("ddmmyy8.") })).num;
    try t.expectEqual(y2024, dd);
    // packed 6/8-digit forms on the INPUT() path (BUG-ddmmyyfnpacked):
    // 15MAR2012 = SAS day 19067 (date(2012,3,15) - date(1960,1,1)).
    try t.expectEqual(@as(f64, 19067), (try dispatch(&e, "input", &.{ strV("150312"), strV("ddmmyy6.") })).num);
    try t.expectEqual(@as(f64, 19067), (try dispatch(&e, "input", &.{ strV("031512"), strV("mmddyy6.") })).num);
    try t.expectEqual(@as(f64, 19067), (try dispatch(&e, "input", &.{ strV("15032012"), strV("ddmmyy8.") })).num);

    // OPTIONS YEARCUTOFF=2000: the span moves so 26 → 2026
    format.setYearCutoff(2000);
    const y26 = (try dispatch(&e, "input", &.{ strV("01/01/26"), strV("mmddyy8.") })).num;
    const y2026 = (try dispatch(&e, "input", &.{ strV("01/01/2026"), strV("mmddyy10.") })).num;
    try t.expectEqual(y2026, y26);
}

test "BUG-datesingledigitday: INPUT() DATEw. reads a 1-digit day (was silent missing)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    // 1- and 2-digit days agree; 2- and 4-digit years agree; width-less too.
    try t.expectEqual(@as(f64, 11017), (try dispatch(&e, "input", &.{ strV("1MAR90"), strV("date7.") })).num);
    try t.expectEqual(@as(f64, 11017), (try dispatch(&e, "input", &.{ strV("01MAR90"), strV("date7.") })).num);
    try t.expectEqual(@as(f64, 11017), (try dispatch(&e, "input", &.{ strV("1MAR1990"), strV("date9.") })).num);
    try t.expectEqual(@as(f64, 11017), (try dispatch(&e, "input", &.{ strV("1MAR1990"), strV("date.") })).num);
    // the already-correct paths are unchanged: 2-digit day, separated DATE11.,
    // MMDDYY, and an impossible day still reads missing.
    try t.expectEqual(@as(f64, 21929), (try dispatch(&e, "input", &.{ strV("15JAN2020"), strV("date9.") })).num);
    try t.expectEqual(@as(f64, 21989), (try dispatch(&e, "input", &.{ strV("15-MAR-2020"), strV("date11.") })).num);
    try t.expectEqual(@as(f64, 10959), (try dispatch(&e, "input", &.{ strV("1/2/90"), strV("mmddyy8.") })).num);
    try t.expect((try dispatch(&e, "input", &.{ strV("31FEB2020"), strV("date9.") })).isMissing());
}

test "INTSHIFT: shift interval of a base interval (SAS doc p.1104 examples)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const sh = struct {
        fn f(ev: *eval.Evaluator, iv: []const u8) ![]const u8 {
            return (try dispatch(ev, "intshift", &.{strV(iv)})).str;
        }
    }.f;
    // the seven worked examples from the reference
    try t.expectEqualStrings("MONTH", try sh(&e, "year"));
    try t.expectEqualStrings("DTMONTH", try sh(&e, "dtyear"));
    try t.expectEqualStrings("DTMINUTE", try sh(&e, "minute"));
    try t.expectEqualStrings("WEEKDAY", try sh(&e, "weekdays"));
    try t.expectEqualStrings("WEEKDAY", try sh(&e, "weekday5.4"));
    try t.expectEqualStrings("MONTH", try sh(&e, "qtr"));
    try t.expectEqualStrings("DTTENDAY", try sh(&e, "dttenday"));
    // and the plain self-shifting / MONTH-shifting cases
    try t.expectEqualStrings("MONTH", try sh(&e, "month"));
    try t.expectEqualStrings("MONTH", try sh(&e, "semiyear"));
    try t.expectEqualStrings("DAY", try sh(&e, "day"));
    try t.expectEqualStrings("DTHOUR", try sh(&e, "hour"));
    try t.expectEqualStrings("TENDAY", try sh(&e, "tenday"));
    try t.expectEqualStrings("", try sh(&e, "bogus")); // invalid → blank
}

test "VLABELX: label from the bound Library, else the variable name (BUG-vlabelx)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    var lib = @import("exec.zig").Library.init(h.arena.allocator());
    bindLibrary(&lib);
    defer unbindLibrary();
    try lib.setVarLabel("age", "Age in Years");
    _ = try h.pdv.define("age", .num);
    _ = try h.pdv.define("nm", .num);
    try t.expectEqualStrings("Age in Years", (try dispatch(&e, "vlabelx", &.{strV("age")})).str); // labeled
    try t.expectEqualStrings("nm", (try dispatch(&e, "vlabelx", &.{strV("nm")})).str); // unlabeled → name
}

test "INTNX YEAR/SEMIYEAR SAME preserves month/day across leap boundaries (BUG-intnxyearsame)" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const same = struct {
        fn f(ev: *eval.Evaluator, iv: []const u8, y: i64, m: i64, d: i64, n: f64) !f64 {
            const start: f64 = @floatFromInt(sasDate(y, m, d));
            return (try dispatch(ev, "intnx", &.{ strV(iv), numV(start), numV(n), strV("same") })).num;
        }
    }.f;
    const day = struct {
        fn f(y: i64, m: i64, d: i64) f64 {
            return @floatFromInt(sasDate(y, m, d));
        }
    }.f;
    // leap-boundary anniversaries: same month/day N years later (was off by one)
    try t.expectEqual(day(2021, 6, 15), try same(&e, "year", 2020, 6, 15, 1)); // leap → non-leap
    try t.expectEqual(day(2020, 6, 15), try same(&e, "year", 2019, 6, 15, 1)); // non-leap → leap
    try t.expectEqual(day(2021, 1, 15), try same(&e, "year", 2020, 1, 15, 1)); // before Feb: unaffected
    try t.expectEqual(day(2021, 2, 28), try same(&e, "year", 2020, 2, 29, 1)); // Feb 29 clamps to Feb 28
    // SEMIYEAR shared the bug; position-within-half is preserved
    try t.expectEqual(day(2021, 6, 15), try same(&e, "semiyear", 2020, 6, 15, 2)); // 2 halves = 1 year
    try t.expectEqual(day(2020, 12, 15), try same(&e, "semiyear", 2020, 6, 15, 1)); // 1 half → Dec
    // mid-month MONTH/QTR: day-of-month is preserved unchanged
    try t.expectEqual(day(2021, 6, 15), try same(&e, "month", 2020, 6, 15, 12));
    try t.expectEqual(day(2021, 6, 15), try same(&e, "qtr", 2020, 6, 15, 4));
    // MONTH/QTR day-overflow clamps to the target month's last day (BUG-intnxmonthsame):
    // 31Jan +1mo → 29Feb (leap), 28Feb (non-leap), NOT 02/03 Mar.
    try t.expectEqual(day(2020, 2, 29), try same(&e, "month", 2020, 1, 31, 1));
    try t.expectEqual(day(2021, 2, 28), try same(&e, "month", 2021, 1, 31, 1));
    try t.expectEqual(day(2020, 2, 29), try same(&e, "month", 2020, 3, 31, -1)); // 31Mar -1mo → 29Feb
    try t.expectEqual(day(2020, 4, 30), try same(&e, "qtr", 2020, 1, 31, 1)); // Jan(off0,d31) → Apr, clamp 30
}

test "BUG-numcharwidth: __assignc — char truncates, numeric renders BESTn. right-justified" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // char rhs: truncate to n (identical to the old substr(rhs,1,n) desugar)
    try t.expectEqualStrings("abc", (try dispatch(&e, "__assignc", &.{ strV("abcdef"), numV(3) })).str);
    try t.expectEqualStrings("ab", (try dispatch(&e, "__assignc", &.{ strV("ab"), numV(20) })).str); // short stays short
    // numeric rhs: BESTn. right-justified in n (Language Reference: Concepts p.124) — incl. n < 12
    try t.expectEqualStrings("       5", (try dispatch(&e, "__assignc", &.{ numV(5), numV(8) })).str);
    try t.expectEqualStrings("                   5", (try dispatch(&e, "__assignc", &.{ numV(5), numV(20) })).str);
    try t.expectEqualStrings("     -4.5", (try dispatch(&e, "__assignc", &.{ numV(-4.5), numV(9) })).str);
    // the automatic-conversion NOTE still fires (GH#74b): 2 numeric coercions above
    try t.expectEqual(@as(usize, 3), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "converted to character") != null);
}

test "BUG-julianinputfn: INPUT() function routes JULIANw. to format.readNumeric" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // 1960 day 011 → SAS day 10 (was: silently 1960011 via the plain numeric read)
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "input", &.{ strV("1960011"), strV("julian7.") })).num);
    // 1900 is NOT a leap year → day 366 invalid → missing
    try t.expect((try dispatch(&e, "input", &.{ strV("1900366"), strV("julian7.") })).isMissing());
    // yyyyddd 5-digit form: 60011 → SAS day 10
    try t.expectEqual(@as(f64, 10), (try dispatch(&e, "input", &.{ strV("60011"), strV("julian5.") })).num);
}

test "NOTE-informatlow-tick245: INPUT() fn routes Z/BEST/E/D + COMMA/DOLLAR to format.readNumeric" {
    var h = harness();
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // #9: the fn path used to fall to numFromSpec (drop-all-blanks) — `input("4 2",
    // z3.)` silently read 42 where the statement path (readNumeric) reads missing.
    // Both paths now agree: w.d aliases → embedded blank invalid → missing.
    try t.expect((try dispatch(&e, "input", &.{ strV("4 2"), strV("z3.") })).isMissing());
    try t.expect((try dispatch(&e, "input", &.{ strV("4 2"), strV("best4.") })).isMissing());
    try t.expect((try dispatch(&e, "input", &.{ strV("4 2"), strV("e4.") })).isMissing());
    // leading/trailing blanks still trim fine
    try t.expectEqual(@as(f64, 42), (try dispatch(&e, "input", &.{ strV(" 42 "), strV("z4.") })).num);
    // #13: interior hyphen removal reaches the fn path (was numFromSpec → missing)
    try t.expectEqual(@as(f64, 1234), (try dispatch(&e, "input", &.{ strV("12-34"), strV("comma10.") })).num);
    try t.expectEqual(@as(f64, -500), (try dispatch(&e, "input", &.{ strV("-500"), strV("comma10.") })).num);
    // comma/dollar staples unchanged through the new route (parens-neg, strips)
    try t.expectEqual(@as(f64, -1234.5), (try dispatch(&e, "input", &.{ strV("(1,234.5)"), strV("comma12.1") })).num);
    try t.expectEqual(@as(f64, 1500.5), (try dispatch(&e, "input", &.{ strV("$1,500.50"), strV("dollar12.2") })).num);
    // #14: NEGPAREN informat fails loud on the fn path too (D-002)
    format.g_fmt_error = false;
    format.setNoFmtErr(false);
    format.g_test_last_err = "";
    try t.expect((try dispatch(&e, "input", &.{ strV("(1,234)"), strV("negparen12.") })).isMissing());
    try t.expect(format.formatErrored());
    try t.expect(std.mem.indexOf(u8, format.g_test_last_err, "negparen") != null);
    format.g_fmt_error = false; // reset module state for other tests
}
