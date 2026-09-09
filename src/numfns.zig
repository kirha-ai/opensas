//! Scalar numeric functions (rounding, modular/bitwise arithmetic, log-gamma
//! family, number theory), split verbatim out of functions.zig dispatch (QL-A).
//! The unary_math comptime table and shared helpers stay in functions.zig;
//! `null` means "name not mine".
const std = @import("std");
const eval = @import("eval.zig");
const Value = @import("value.zig").Value;

const fns = @import("functions.zig");
const eqi = fns.eqi;
const toNum = fns.toNum;
const toStr = fns.toStr;
const toInt = fns.toInt;
const toU32 = fns.toU32;
const isMiss = fns.isMiss;
const numVal = fns.numVal;
const badArity = fns.badArity;
const domErr = fns.domErr;
const note = fns.note;
const unary = fns.unary;
const unary_math = fns.unary_math;
const bit_binops = fns.bit_binops;
const bivarNormCdf = fns.bivarNormCdf;
const cleanDecimals = fns.cleanDecimals;
const collectNums = fns.collectNums;
const comb2 = fns.comb2;
const cssMean = fns.cssMean;
const factorial = fns.factorial;
const gcdU64 = fns.gcdU64;
const intervalsPerYear = fns.intervalsPerYear;
const lgammaOf = fns.lgammaOf;
const pow10 = fns.pow10;
const weekNumber = fns.weekNumber;

/// NOTE-bitwisemisserror: a MISSING arg to a bitwise op yields missing AND
/// _ERROR_=1 — the value was already right, but a program branching on _ERROR_
/// never saw the flag. Same NOTE + PDV-setError mechanism as domErr
/// (MISC-fnseterror).
/// NOTE-bitrangenote: the OUT-OF-RANGE (non-missing) arg used to keep a plain
/// SILENT missing, and bitwise_exact.sas pinned that silence — but the pin
/// predates this repo being able to grep the functions reference. BAND p.265–266
/// prints "Range: An integer value between 0 and (2^32)–1 inclusive" (BNOT
/// p.278–279, BOR p.279 the same bounds), and the volume's general rule at p.6
/// ("If the value of an argument is invalid (for example, missing or outside the
/// prescribed range), SAS writes a note to the log indicating that the argument
/// is invalid, sets _ERROR_ to 1, and sets the result to a missing value")
/// makes an out-of-range argument invalid: note + _ERROR_=1 + missing. So both
/// arms now diagnose; only the missing arm keeps its own wording, because that
/// one the entries state themselves ("If either argument contains a missing
/// value, the function returns a missing value and sets _ERROR_ equal to 1").
/// NOTE-bitshiftcount: BLSHIFT/BRSHIFT argument-2 has a TIGHTER documented
/// range, "0 to 31, inclusive" (BLSHIFT p.278, BRSHIFT p.280) — a count of 32+
/// passed toU32 and silently masked (& 31), so blshift(1,32) computed 1<<0=1,
/// a plausible wrong number. The p.6 rule reaches it too: domErr, below.
/// The RESULT is missing either way — this adds the diagnostic, never a value.
/// ponytail: still nothing here about a non-integer IN range (`band(1.9,3)`);
/// that is NOTE-bitfracround and the entries genuinely do not say, so it keeps
/// rounding via toU32 until an oracle settles it.
fn bitArgInvalid(ev: *eval.Evaluator, name: []const u8, arg: Value) Value {
    if (isMiss(toNum(arg))) {
        note(ev, "{s}: missing argument (result set to missing)", .{name});
        ev.setError() catch {}; // same catch{} reasoning as domErr
        return Value.missing;
    }
    return domErr(ev, name); // outside 0..2^32-1 (p.5)
}

pub fn dispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!?Value {
    // ── scalar numeric: missing propagates
    inline for (unary_math) |u| if (eqi(name, u.name)) return unary(ev, name, args, u.op);
    if (eqi(name, "sqrt")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const x = toNum(args[0]);
        if (isMiss(x)) return Value.missing;
        // BUG-sqrtmoderror: route through domErr (NOTE + _ERROR_=1 + missing),
        // same invalid-arg path as LOG — was NOTE-only, so `if _error_` never fired.
        if (x < 0) return domErr(ev, name);
        return numVal(@sqrt(x));
    }
    if (eqi(name, "round")) {
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const x = toNum(args[0]);
        if (isMiss(x)) return Value.missing;
        const unit = if (args.len == 2) toNum(args[1]) else 1;
        if (isMiss(unit)) return Value.missing;
        if (unit == 0) return numVal(x); // round(x, 0) is x
        // `x/unit` for a .x5 boundary can land just below (1.045/0.01 → 104.4999…),
        // so @round would truncate it down. SAS nudges away from zero by a tiny
        // fuzz first, so boundaries round UP: round(1.045,0.01)=1.05.
        const q = x / unit;
        // ponytail: nudge is relative to |q| (to clear the ~|q|·1e-16 division
        // error) but CAPPED under 0.5, so a tiny unit — where |q| is huge, e.g.
        // 97/1e-10 = 9.7e11 — can never jump to a neighbouring integer and inject
        // FP noise (GH#47). Cap only bites for |q|≳1e10, where q's own ULP already
        // exceeds the unit and rounding to it is meaningless anyway.
        const nudge = std.math.copysign(@min(@abs(q) * 1e-11, 0.1), q);
        const scaled = @round(q + nudge) * unit;
        // `368 * 0.1` isn't exactly 36.8, so re-round to the unit's decimal count
        // (division lands on the clean nearest f64: 36.8, not 36.800000000000004).
        const p = pow10(cleanDecimals(unit));
        return numVal(if (p > 1) @round(scaled * p) / p else scaled);
    }
    if (eqi(name, "mod")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const x = toNum(args[0]);
        const y = toNum(args[1]);
        if (isMiss(x) or isMiss(y)) return Value.missing;
        if (y == 0) return domErr(ev, name); // BUG-sqrtmoderror: NOTE + _ERROR_=1 + missing
        const r = x - @trunc(x / y) * y; // remainder, sign of x
        // SAS MOD fuzz: a remainder within 1e-12 relative of 0 or of |y| is FP
        // dust → exactly 0 (mod(0.3,0.1)=0). MODZ is the un-fuzzed form.
        // Scale is |y| (remainders are bounded by |y|), NOT |x| — an |x|-scaled
        // tolerance would snap exact integer remainders (mod(1e15,3)=1) to 0.
        const tol = 1e-12 * @abs(y);
        if (@abs(r) <= tol or @abs(@abs(r) - @abs(y)) <= tol) return numVal(0);
        return numVal(r);
    }
    if (eqi(name, "atan2")) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const y = toNum(args[0]);
        const x = toNum(args[1]);
        if (isMiss(y) or isMiss(x)) return Value.missing;
        return numVal(std.math.atan2(y, x));
    }
    if (eqi(name, "fact")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const n = toNum(args[0]);
        if (isMiss(n)) return Value.missing;
        if (n < 0 or n != @trunc(n)) return domErr(ev, name);
        if (n > 170) return Value.missing; // overflows f64 → SAS returns missing
        return numVal(factorial(n));
    }
    if (eqi(name, "comb") or eqi(name, "perm")) {
        // COMB(n,r)=n!/(r!(n-r)!); PERM(n,r)=n!/(n-r)!  (PERM's 2nd arg optional → r=n)
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        const n = toNum(args[0]);
        if (isMiss(n)) return Value.missing;
        if (n < 0 or n != @trunc(n)) return domErr(ev, name);
        // COMB multinomial: comb(n, r1, r2, …) = n!/(r1!…rk!(n−Σr)!) — ways to split n
        // items into the given group sizes, computed as ∏ comb(remaining, ri)
        // (BUG-combmulti). PERM has no multinomial form.
        if (eqi(name, "comb") and args.len >= 3) {
            var remaining = n;
            var result: f64 = 1;
            for (args[1..]) |ra| {
                const ri = toNum(ra);
                if (isMiss(ri)) return Value.missing;
                if (ri < 0 or ri != @trunc(ri) or ri > remaining) return domErr(ev, name);
                result *= comb2(remaining, ri);
                if (!std.math.isFinite(result)) return Value.missing;
                remaining -= ri;
            }
            return numVal(result);
        }
        if (args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const r = if (args.len == 2) toNum(args[1]) else n;
        if (isMiss(r)) return Value.missing;
        if (r < 0 or r > n or r != @trunc(r)) return domErr(ev, name);
        // COMB routes through comb2's interleaved product (BUG-comboverflow): a
        // representable binomial never overflows mid-computation. PERM is the raw
        // descending product ∏_{i=0}^{r-1}(n-i), which genuinely overflows f64 for
        // large n,r → missing. ponytail: the overflow break also bounds the loop
        // (integer terms ≥1 overflow within ~170 steps), so perm(1e12,…) returns
        // missing instead of hanging.
        if (eqi(name, "comb")) {
            const result = comb2(n, r);
            if (!std.math.isFinite(result)) return Value.missing;
            return numVal(result);
        }
        var p: f64 = 1;
        var i: f64 = 0;
        while (i < r) : (i += 1) {
            p *= (n - i);
            if (!std.math.isFinite(p)) return Value.missing;
        }
        return numVal(p);
    }
    if (eqi(name, "beta")) {
        // B(a,b) = Γ(a)Γ(b)/Γ(a+b), via log-gamma for stability
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const av = toNum(args[0]);
        const bv = toNum(args[1]);
        if (isMiss(av) or isMiss(bv)) return Value.missing;
        if (av <= 0 or bv <= 0) return domErr(ev, name);
        return numVal(@exp(lgammaOf(av) + lgammaOf(bv) - lgammaOf(av + bv)));
    }
    if (eqi(name, "std")) {
        // sample standard deviation of the arguments (missing ignored, n≥2)
        var n: usize = 0;
        var sum: f64 = 0;
        for (args) |arg| {
            const x = toNum(arg);
            if (!isMiss(x)) {
                n += 1;
                sum += x;
            }
        }
        if (n < 2) return Value.missing;
        const mean = sum / @as(f64, @floatFromInt(n));
        var ss: f64 = 0;
        for (args) |arg| {
            const x = toNum(arg);
            if (!isMiss(x)) ss += (x - mean) * (x - mean);
        }
        return numVal(@sqrt(ss / @as(f64, @floatFromInt(n - 1))));
    }
    if (eqi(name, "week")) {
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const d = toNum(args[0]);
        const desc: u8 = if (args.len == 2) blk: {
            const s = try toStr(ev, args[1]);
            break :blk if (s.len > 0) std.ascii.toUpper(s[0]) else 'U';
        } else 'U';
        // NOTE-weekbaddesc: an invalid descriptor letter was silently treated
        // as 'U' — the user asked for a week-numbering rule that doesn't exist
        // and got a plausible number from a different one. Fail loud naming it
        // (D-002), same NOTE + _ERROR_=1 + missing mechanism as domErr.
        if (desc != 'U' and desc != 'V' and desc != 'W') {
            note(ev, "WEEK: invalid descriptor '{c}' (valid: U, V, W; result set to missing)", .{desc});
            ev.setError() catch {}; // same catch{} reasoning as domErr
            return Value.missing;
        }
        if (isMiss(d)) return Value.missing;
        return numVal(@floatFromInt(weekNumber(toInt(@round(d)) orelse return Value.missing, desc)));
    }

    // ── bitwise logical ops: args are 32-bit unsigned ints; missing propagates
    inline for (bit_binops) |b| if (eqi(name, b.name)) {
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const a = toU32(args[0]) orelse return bitArgInvalid(ev, name, args[0]);
        const c = toU32(args[1]) orelse return bitArgInvalid(ev, name, args[1]);
        // NOTE-bitshiftcount: shift count's documented range is 0–31 (BLSHIFT
        // p.278, BRSHIFT p.280); 32+ used to silently mask (& 31) into a
        // plausible wrong shift (blshift(1,32)=1). p.6 rule → domErr. b.op is
        // comptime, so this folds away for band/bor/bxor.
        if ((b.op == .blshift or b.op == .brshift) and c > 31) return domErr(ev, name);
        return numVal(@floatFromInt(switch (b.op) {
            .band => a & c,
            .bor => a | c,
            .bxor => a ^ c,
            .blshift => a << @intCast(c), // count ≤ 31 per the guard above
            .brshift => a >> @intCast(c),
        }));
    };
    if (eqi(name, "bnot")) {
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const a = toU32(args[0]) orelse return bitArgInvalid(ev, name, args[0]);
        return numVal(@floatFromInt(~a));
    }
    if (eqi(name, "roundz")) {
        // nearest multiple of unit (default 1), no fuzz; ties to even (funcref p.1455).
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const x = toNum(args[0]);
        if (isMiss(x)) return Value.missing;
        const unit = if (args.len == 2) toNum(args[1]) else 1;
        if (isMiss(unit)) return Value.missing;
        if (unit == 0) return numVal(x);
        const q = x / unit;
        const fl = @floor(q);
        const frac = q - fl;
        var r = fl;
        if (frac > 0.5) {
            r = fl + 1;
        } else if (frac == 0.5) {
            r = if (@mod(fl, 2) == 0) fl else fl + 1; // halfway → even multiple
        }
        return numVal(r * unit);
    }
    if (eqi(name, "divide")) {
        // x/y, missing propagates. ponytail: SAS's ODS special-missing values
        // (.I=+inf, .M=-inf) aren't modeled — we have no distinct special missings.
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const x = toNum(args[0]);
        const y = toNum(args[1]);
        if (isMiss(x) or isMiss(y)) return Value.missing;
        return numVal(x / y);
    }
    if (eqi(name, "cmiss")) {
        // count of missing args, no type conversion (numeric `.` or blank char).
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        var c: f64 = 0;
        for (args) |arg| {
            const miss = switch (arg) {
                .num => arg.isMissing(),
                .str => |s| std.mem.trim(u8, s, " ").len == 0,
            };
            if (miss) c += 1;
        }
        return numVal(c);
    }
    if (eqi(name, "compound")) {
        // f = a*(1+r)^n; exactly one of the four args is missing → solve for it.
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const a = toNum(args[0]);
        const f = toNum(args[1]);
        const r = toNum(args[2]);
        const n = toNum(args[3]);
        if (isMiss(r)) return domErr(ev, name); // PDF: solving for r is an error
        // GAP-compoundnonote (doc p.544): a,f,r,n must all be >= 0; out-of-range
        // -> invalid-argument NOTE + missing (was silent NaN->missing).
        // ponytail: SAS also sets _ERROR_=1; NOTE only (MISC-fnseterror gap, same as MORT).
        if ((!isMiss(a) and a < 0) or (!isMiss(f) and f < 0) or r < 0 or (!isMiss(n) and n < 0)) {
            note(ev, "Invalid argument to function COMPOUND.", .{});
            return Value.missing;
        }
        if (isMiss(a)) return numVal(f / std.math.pow(f64, 1 + r, n));
        if (isMiss(f)) return numVal(a * std.math.pow(f64, 1 + r, n));
        if (isMiss(n)) return numVal(@log(f / a) / @log(1 + r));
        return Value.missing; // no missing arg → nothing to solve
    }

    // ── scalar special / rounding / financial
    if (eqi(name, "rounde")) { // round to nearest multiple of unit; ties to even (fuzzed — doc p.1453)
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const x = toNum(args[0]);
        if (isMiss(x)) return Value.missing;
        const unit = if (args.len == 2) toNum(args[1]) else 1;
        if (isMiss(unit)) return Value.missing;
        if (unit == 0) return numVal(x);
        const q = x / unit;
        const fl = @floor(q);
        var frac = q - fl;
        // NOTE-roundefuzz (doc p.1453): ROUNDE fuzzes — "approximately halfway"
        // snaps to the tie, THEN ties-to-even. A decimal .xx5 boundary divides
        // to one ULP off the tie (8.075/0.01 → 807.4999999999999) and must tie
        // → 808, not round down to 807. Two-sided: for negative x the division
        // error flips side (−8.075/0.01 → frac 0.5000000000001). Tolerance is
        // ROUND's nudge shape: relative to |q| to clear the division error,
        // capped under 0.5 so a tiny unit (|q| huge, GH#47) can never snap a
        // genuinely-different frac to the tie.
        const tol = @min(@abs(q) * 1e-11, 0.1);
        if (@abs(frac - 0.5) <= tol) frac = 0.5;
        var r = fl;
        if (frac > 0.5) {
            r = fl + 1;
        } else if (frac == 0.5) {
            r = if (@mod(fl, 2) == 0) fl else fl + 1; // halfway → even multiple
        }
        return numVal(r * unit);
    }
    if (eqi(name, "compfuzz")) { // fuzzy compare: -1 / 0 / 1
        if (args.len < 2 or args.len > 4) return badArity(ev, name, "2 to 4", args.len);
        const v1 = toNum(args[0]);
        const v2 = toNum(args[1]);
        if (isMiss(v1) or isMiss(v2)) return Value.missing;
        const fuzz = if (args.len >= 3) toNum(args[2]) else 1024;
        const scale = if (args.len >= 4) toNum(args[3]) else @max(@abs(v1), @abs(v2));
        if (isMiss(fuzz) or isMiss(scale)) return Value.missing;
        const maceps = std.math.floatEps(f64);
        const threshold = if (fuzz < 1) fuzz * @abs(scale) else fuzz * @abs(scale) * maceps;
        if (v1 < v2 - threshold) return numVal(-1);
        if (v1 > v2 + threshold) return numVal(1);
        return numVal(0);
    }
    if (eqi(name, "effrate") or eqi(name, "nomrate")) {
        // convert between nominal and effective annual rate (both as percentages)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const ivl = try toStr(ev, args[0]);
        const rate = toNum(args[1]);
        if (isMiss(rate) or rate < -99) return Value.missing;
        const r = rate / 100.0;
        if (eqi(std.mem.trim(u8, ivl, " "), "continuous")) {
            const frac = if (eqi(name, "effrate")) @exp(r) - 1.0 else @log(1.0 + r);
            return numVal(100.0 * frac);
        }
        const m = intervalsPerYear(ivl) orelse return Value.missing;
        if (eqi(name, "effrate"))
            return numVal(100.0 * (std.math.pow(f64, 1.0 + r / m, m) - 1.0));
        return numVal(100.0 * m * (std.math.pow(f64, 1.0 + r, 1.0 / m) - 1.0));
    }

    // ── log-gamma family and integer number theory
    if (eqi(name, "logbeta")) { // log B(a,b)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const a = toNum(args[0]);
        const b = toNum(args[1]);
        if (isMiss(a) or isMiss(b)) return Value.missing;
        if (a <= 0 or b <= 0) return domErr(ev, name);
        return numVal(lgammaOf(a) + lgammaOf(b) - lgammaOf(a + b));
    }
    if (eqi(name, "lperm")) { // log of PERM(n,r)
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        const n = toNum(args[0]);
        const r = if (args.len == 2) toNum(args[1]) else n;
        if (isMiss(n) or isMiss(r)) return Value.missing;
        if (n < 0 or r < 0 or r > n) return domErr(ev, name);
        return numVal(lgammaOf(n + 1) - lgammaOf(n - r + 1));
    }
    if (eqi(name, "lcomb")) { // log of COMB(n,r)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const n = toNum(args[0]);
        const r = toNum(args[1]);
        if (isMiss(n) or isMiss(r)) return Value.missing;
        if (n < 0 or r < 0 or r > n) return domErr(ev, name);
        return numVal(lgammaOf(n + 1) - lgammaOf(r + 1) - lgammaOf(n - r + 1));
    }
    if (eqi(name, "gcd") or eqi(name, "lcm")) { // integer gcd / lcm over the args
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        var acc: u64 = if (eqi(name, "gcd")) 0 else 1;
        for (args) |arg| {
            const v = toNum(arg);
            if (isMiss(v) or v != @trunc(v)) return domErr(ev, name);
            const u: u64 = @intCast(toInt(@abs(v)) orelse return domErr(ev, name)); // guards ±inf
            if (eqi(name, "gcd")) {
                acc = gcdU64(acc, u);
            } else {
                if (u == 0) return numVal(0);
                // lcm(a,b)=a/gcd·b; checked mul: result past u64 → missing, never panic (BUG-lcmoverflow)
                const prod = @mulWithOverflow(acc / gcdU64(acc, u), u);
                if (prod[1] != 0) return Value.missing;
                acc = prod[0];
            }
        }
        return numVal(@floatFromInt(acc));
    }
    if (eqi(name, "var") or eqi(name, "stderr")) { // sample variance / std error of mean
        const xs = try collectNums(ev, args);
        if (xs.len < 2) return Value.missing;
        const cm = cssMean(xs);
        const nf: f64 = @floatFromInt(xs.len);
        const variance = cm.css / (nf - 1);
        return numVal(if (eqi(name, "var")) variance else @sqrt(variance / nf));
    }

    // ── remaining numerics: byte truncation, bivariate normal
    if (eqi(name, "trunc")) { // truncate a double to `length` bytes (zero the low bytes)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const x = toNum(args[0]);
        const lenf = toNum(args[1]);
        if (isMiss(x) or isMiss(lenf)) return Value.missing;
        const len = toInt(lenf) orelse return Value.missing;
        if (len >= 8) return numVal(x);
        if (len < 1) return Value.missing;
        const shift: u6 = @intCast((8 - len) * 8);
        const bits: u64 = @bitCast(x);
        return numVal(@bitCast(bits & (~@as(u64, 0) << shift)));
    }
    if (eqi(name, "probbnrm")) { // bivariate-normal probability P(X≤x, Y≤y | r)
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const x = toNum(args[0]);
        const y = toNum(args[1]);
        const r = toNum(args[2]);
        if (isMiss(x) or isMiss(y) or isMiss(r)) return Value.missing;
        if (r < -1 or r > 1) return domErr(ev, name);
        return numVal(bivarNormCdf(x, y, r));
    }

    return null;
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

fn compound4(e: *eval.Evaluator, a: Value, f: Value, r: Value, n: Value) !Value {
    return (try dispatch(e, "compound", &.{ a, f, r, n })) orelse error.NotMine;
}

fn nv(x: f64) Value {
    return .{ .num = x };
}

test "BUG-sqrtmoderror: SQRT(-x) and MOD(x,0) emit the invalid-arg NOTE, set _ERROR_=1, return missing" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    const sqrtNeg = (try dispatch(&e, "sqrt", &.{nv(-1)})).?;
    try t.expect(sqrtNeg.isMissing());
    const modZero = (try dispatch(&e, "mod", &.{ nv(5), nv(0) })).?;
    try t.expect(modZero.isMissing());

    // one NOTE each via the shared domErr path, and _ERROR_=1 left in the PDV.
    try t.expectEqual(@as(usize, 2), h.diags.count());
    for (h.diags.list.items) |d|
        try t.expect(std.mem.indexOf(u8, d.message, "argument out of domain") != null);
    try t.expectEqual(Value{ .num = 1 }, h.pdv.get("_error_").?);

    // valid calls: clean result, no new NOTEs, _ERROR_ untouched (reset by executor).
    h.pdv.set("_error_", .{ .num = 0 }) catch unreachable;
    const s = (try dispatch(&e, "sqrt", &.{nv(16)})).?;
    try t.expectEqual(@as(f64, 4), s.num);
    const m = (try dispatch(&e, "mod", &.{ nv(5), nv(2) })).?;
    try t.expectEqual(@as(f64, 1), m.num);
    try t.expectEqual(@as(usize, 2), h.diags.count());
    try t.expectEqual(Value{ .num = 0 }, h.pdv.get("_error_").?);
}

test "GAP-compoundnonote: COMPOUND out-of-range args log the invalid-argument NOTE (doc p.544)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const numV = struct {
        fn f(x: f64) Value {
            return .{ .num = x };
        }
    }.f;

    // negative rate / amount / n: NOTE + missing, one NOTE each.
    try t.expect((try compound4(&e, numV(1000), Value.missing, numV(-0.05), numV(12))).isMissing());
    try t.expect((try compound4(&e, numV(-1000), Value.missing, numV(0.05), numV(12))).isMissing());
    try t.expect((try compound4(&e, numV(1000), Value.missing, numV(0.05), numV(-2))).isMissing());
    try t.expectEqual(@as(usize, 3), h.diags.count());
    for (h.diags.list.items) |d|
        try t.expect(std.mem.indexOf(u8, d.message, "Invalid argument to function COMPOUND") != null);

    // the doc example (a=500, r=0.09/12, n=120 -> f=1228.24) still computes, no note.
    const f = try compound4(&e, numV(500), Value.missing, numV(0.09 / 12.0), numV(120));
    try t.expect(@abs(f.num - 1225.68) < 1e-2);
    // zero args are valid (>= 0): compound(0, ., r, n) = 0.
    const z = try compound4(&e, numV(0), Value.missing, numV(0.05), numV(12));
    try t.expect(z.num == 0);
    try t.expectEqual(@as(usize, 3), h.diags.count());
}

test "NOTE-weekbaddesc: WEEK with an invalid descriptor letter fails loud (NOTE naming it + _ERROR_=1 + missing)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const sv = struct {
        fn f(s: []const u8) Value {
            return .{ .str = s };
        }
    }.f;

    // 'Q' is not a week-numbering rule: loud, naming the descriptor — was
    // silently treated as 'U' and returned a plausible week number.
    const bad = (try dispatch(&e, "week", &.{ nv(21915), sv("Q") })).?;
    try t.expect(bad.isMissing());
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "WEEK: invalid descriptor 'Q'") != null);
    try t.expectEqual(Value{ .num = 1 }, h.pdv.get("_error_").?);

    // a missing date does not mask the invalid descriptor.
    _ = (try dispatch(&e, "week", &.{ Value.missing, sv("q") })).?;
    try t.expectEqual(@as(usize, 2), h.diags.count());

    // the three valid descriptors (+ lowercase + default/empty) stay as they were.
    h.pdv.set("_error_", .{ .num = 0 }) catch unreachable;
    for ([_][]const u8{ "U", "v", "W", "" }) |d| {
        const r = (try dispatch(&e, "week", &.{ nv(21915), sv(d) })).?;
        try t.expect(!r.isMissing());
    }
    _ = (try dispatch(&e, "week", &.{nv(21915)})).?;
    try t.expectEqual(@as(usize, 2), h.diags.count()); // no new NOTEs
    try t.expectEqual(Value{ .num = 0 }, h.pdv.get("_error_").?);
}

test "NOTE-bitwisemisserror + NOTE-bitrangenote: a missing OR out-of-range bitwise arg sets _ERROR_=1 (value still missing)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // every binary op + BNOT: missing arg → NOTE + _ERROR_=1 + missing.
    for ([_][]const u8{ "band", "bor", "bxor", "blshift", "brshift" }) |name| {
        h.pdv.set("_error_", .{ .num = 0 }) catch unreachable;
        try t.expect((try dispatch(&e, name, &.{ Value.missing, nv(1) })).?.isMissing());
        try t.expectEqual(Value{ .num = 1 }, h.pdv.get("_error_").?);
    }
    h.pdv.set("_error_", .{ .num = 0 }) catch unreachable;
    try t.expect((try dispatch(&e, "bnot", &.{Value.missing})).?.isMissing());
    try t.expectEqual(Value{ .num = 1 }, h.pdv.get("_error_").?);
    // one NOTE per missing-arg call, naming the function.
    try t.expectEqual(@as(usize, 6), h.diags.count());
    for (h.diags.list.items) |d|
        try t.expect(std.mem.indexOf(u8, d.message, "missing argument") != null);

    // NOTE-bitrangenote: out-of-range (non-missing) args used to be a plain
    // SILENT missing, and this test pinned that. The pin predates the functions
    // reference being greppable here: BAND p.265–266 prints "Range: An integer
    // value between 0 and (2^32)–1 inclusive", and p.6 makes an argument outside
    // a printed range invalid — note + _ERROR_=1 + missing. Same VALUES (missing),
    // now with the diagnostic; the two rows tests/corpus/bitwise_exact.sas
    // exercises are exactly these, and its expected stdout is unchanged because
    // notes go to stderr.
    h.pdv.set("_error_", .{ .num = 0 }) catch unreachable;
    try t.expect((try dispatch(&e, "band", &.{ nv(-1), nv(255) })).?.isMissing());
    try t.expect((try dispatch(&e, "bnot", &.{nv(1e300)})).?.isMissing());
    try t.expectEqual(@as(usize, 8), h.diags.count()); // 6 missing-arg + 2 out-of-range
    try t.expectEqual(Value{ .num = 1 }, h.pdv.get("_error_").?);
    for (h.diags.list.items[6..]) |d|
        try t.expect(std.mem.indexOf(u8, d.message, "out of domain") != null);

    // NOTE-bitshiftcount: the shift COUNT's own range is 0–31 (BLSHIFT p.278,
    // BRSHIFT p.280) — 32+ passed toU32 and silently masked (& 31), computing a
    // plausible wrong shift (blshift(1,32) was 1<<0=1). Now domErr per p.6.
    for ([_][]const u8{ "blshift", "brshift" }) |name| {
        h.pdv.set("_error_", .{ .num = 0 }) catch unreachable;
        try t.expect((try dispatch(&e, name, &.{ nv(8), nv(32) })).?.isMissing());
        try t.expectEqual(Value{ .num = 1 }, h.pdv.get("_error_").?);
    }
    try t.expectEqual(@as(usize, 10), h.diags.count()); // +2 shift-count NOTEs
    for (h.diags.list.items[8..]) |d|
        try t.expect(std.mem.indexOf(u8, d.message, "out of domain") != null);

    // valid calls unaffected — boundary counts 31 and 0 stay exact.
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "band", &.{ nv(0x0F), nv(0x05) })).?.num);
    try t.expectEqual(@as(f64, 2147483648), (try dispatch(&e, "blshift", &.{ nv(1), nv(31) })).?.num);
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "brshift", &.{ nv(8), nv(0) })).?.num);
}

test "NOTE-roundefuzz: ROUNDE fuzzes the approximately-halfway case to the tie, then ties-to-even (doc p.1453)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const r2 = struct {
        fn f(ev2: *eval.Evaluator, x: f64, u: f64) !f64 {
            return (try dispatch(ev2, "rounde", &.{ nv(x), nv(u) })).?.num;
        }
    }.f;
    const r1 = struct {
        fn f(ev2: *eval.Evaluator, x: f64) !f64 {
            return (try dispatch(ev2, "rounde", &.{nv(x)})).?.num;
        }
    }.f;

    // the tie, exactly representable: ties-to-even (also corpus-pinned).
    try t.expectEqual(@as(f64, 2), try r1(&e, 2.5));
    try t.expectEqual(@as(f64, 4), try r1(&e, 3.5));
    // below-tie: decimal .xx5 boundaries divide to one ULP UNDER the tie —
    // fuzzed to the tie, then even (807 is odd → 808; without fuzz this is 8.07).
    try t.expectEqual(@as(f64, 8.08), try r2(&e, 8.075, 0.01));
    try t.expectEqual(@as(f64, 1.0), try r2(&e, 1.005, 0.01)); // 100 even → stays
    try t.expectEqual(@as(f64, 0.28), try r2(&e, 0.285, 0.01)); // 28 even → stays
    // above-tie: one ULP OVER the tie from below (negative x flips the division
    // error's side) — two-sided snap, even multiple −808, not nearest −807.
    try t.expectEqual(@as(f64, -8.08), try r2(&e, -8.075, 0.01));
    // genuinely off the tie by more than the fuzz: plain nearest, NO tie path —
    // 2.5000000001 rounds UP to odd 3 (tie-to-even would give 2);
    // 3.4999999999 rounds DOWN to odd 3 (a fuzzy snap would give even 4).
    try t.expectEqual(@as(f64, 3), try r1(&e, 2.5000000001));
    try t.expectEqual(@as(f64, 3), try r1(&e, 3.4999999999));
    try t.expectEqual(@as(usize, 0), h.diags.count());
}
