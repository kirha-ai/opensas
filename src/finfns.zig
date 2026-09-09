//! Financial functions (amortization, depreciation, annuities, options, bonds,
//! cash-flow analytics), split verbatim out of functions.zig dispatch (QL-A).
//! Shared helpers stay in functions.zig; `null` means "name not mine".
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
const note = fns.note;
const finance = fns.finance;
const netpvValue = fns.netpvValue;
const solveIrr = fns.solveIrr;
const daccOf = fns.daccOf;
const daccDbsl = fns.daccDbsl;
const blackOption = fns.blackOption;
const enumPv = fns.enumPv;
const bondPv = fns.bondPv;
const pmtOf = fns.pmtOf;
const ipmtOf = fns.ipmtOf;
const DepMethod = fns.DepMethod;

pub fn dispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!?Value {
    // ── financial: amortization, savings, present value, internal rate of return
    if (eqi(name, "mort")) { // MORT(a,p,r,n): a=p·((1+r)ⁿ−1)/(r(1+r)ⁿ); one arg missing
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const a = toNum(args[0]);
        const p = toNum(args[1]);
        const r = toNum(args[2]);
        const n = toNum(args[3]);
        if (isMiss(r)) return domErr(ev, name); // solving for the rate is unsupported
        // GAP-mortnonote (doc p.1215): out-of-range args must log an invalid-
        // argument NOTE and return missing — was silent NaN→missing. Per the
        // doc's five bullets, applied per solve direction: r≤−1 (r=−1 also
        // 0-divides), n<0; solve-p: a≤0 or n≤0; solve-a: p≤0; solve-n: a≤0,
        // p≤0, or a·r≥p (payment must cover the per-period interest; equality
        // → n=∞). ponytail: SAS also sets _ERROR_=1; we emit only the NOTE
        // (the MISC-fnseterror infra gap — plumb _ERROR_ through the PDV later).
        if ((r <= -1 or n < 0) or
            (isMiss(p) and (a <= 0 or n <= 0)) or
            (isMiss(a) and p <= 0) or
            (isMiss(n) and (a <= 0 or p <= 0 or a * r >= p)))
        {
            note(ev, "Invalid argument to function MORT.", .{});
            return Value.missing;
        }
        const pw = std.math.pow(f64, 1 + r, n);
        if (isMiss(p)) return numVal(if (r == 0) a / n else a * r * pw / (pw - 1));
        if (isMiss(a)) return numVal(if (r == 0) p * n else p * (pw - 1) / (r * pw));
        if (isMiss(n)) return numVal(if (r == 0) a / p else @log(p / (p - a * r)) / @log(1 + r));
        return Value.missing;
    }
    if (eqi(name, "saving")) { // SAVING(f,p,r,n): f=p(1+r)((1+r)ⁿ−1)/r (annuity due)
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const f = toNum(args[0]);
        const p = toNum(args[1]);
        const r = toNum(args[2]);
        const n = toNum(args[3]);
        if (isMiss(r)) return domErr(ev, name);
        // BUG-savingdomain: out-of-range args must log an invalid-argument NOTE
        // and return missing — was silent nonsense (e.g. negative period count).
        // Mechanical mirror of MORT's guard above, f↔a positional (a,f,r,n≥0);
        // the solve-for `.` arg is exempt (isMiss → comparison is false on NaN).
        if ((r <= -1 or n < 0) or
            (isMiss(p) and (f <= 0 or n <= 0)) or
            (isMiss(f) and p <= 0) or
            (isMiss(n) and (f <= 0 or p <= 0 or f * r >= p)))
        {
            note(ev, "Invalid argument to function SAVING.", .{});
            return Value.missing;
        }
        const pw = std.math.pow(f64, 1 + r, n);
        if (isMiss(f)) return numVal(if (r == 0) p * n else p * (1 + r) * (pw - 1) / r);
        if (isMiss(p)) return numVal(if (r == 0) f / n else f * r / ((1 + r) * (pw - 1)));
        if (isMiss(n)) return numVal(if (r == 0) f / p else @log(1 + f * r / (p * (1 + r))) / @log(1 + r));
        return Value.missing;
    }
    if (eqi(name, "finance")) return try finance(ev, args);
    if (eqi(name, "npv") or eqi(name, "netpv")) { // net present value; NPV's rate is a %
        if (args.len < 4) return badArity(ev, name, "4 or more", args.len);
        var r = toNum(args[0]);
        const freq = toNum(args[1]);
        if (isMiss(r) or isMiss(freq) or freq < 0) return Value.missing;
        if (eqi(name, "npv")) r /= 100.0; // NPV takes a percentage; NETPV a fraction
        return numVal(netpvValue(r, freq, args[2..]));
    }
    if (eqi(name, "irr") or eqi(name, "intrr")) { // internal rate of return (% / fraction)
        if (args.len < 3) return badArity(ev, name, "3 or more", args.len);
        const freq = toNum(args[0]);
        if (isMiss(freq) or freq < 0) return Value.missing;
        const rate = solveIrr(freq, args[1..]) orelse return Value.missing;
        return numVal(if (eqi(name, "irr")) rate * 100.0 else rate);
    }

    // ── depreciation: DEP*(p) = DACC*(p) − DACC*(p−1); DACC* is accumulated
    inline for (.{
        .{ "depsl", DepMethod.sl, false, false }, .{ "daccsl", DepMethod.sl, true, false },
        .{ "depsyd", DepMethod.syd, false, false }, .{ "daccsyd", DepMethod.syd, true, false },
        .{ "depdb", DepMethod.db, false, true }, .{ "daccdb", DepMethod.db, true, true },
    }) |d| if (eqi(name, d[0])) {
        const want_r = d[3];
        const need: usize = if (want_r) 4 else 3;
        if (args.len != need) return badArity(ev, name, if (want_r) "4" else "3", args.len);
        const p = toNum(args[0]);
        const v = toNum(args[1]);
        const y = toNum(args[2]);
        const r = if (want_r) toNum(args[3]) else 0;
        // GAP-bondrangenote, additive half. The MISSING test and the RANGE test
        // are two different rules and must not share a branch:
        //   • missing → plain missing, NO note. Functions ref p.7: "When a
        //     numeric argument has a missing value, many functions write a note
        //     … Exceptions include some of the descriptive statistics functions
        //     and FINANCIAL FUNCTIONS." That exception is attached to the
        //     missing-value bullet, so it governs here.
        //   • outside a documented Range → note + _ERROR_=1 + missing (p.5).
        //     p.7's exception does NOT reach this bullet, so p.5 applies
        //     unmodified. DEPDB/DACCDB print "Range y > 0" (p.604).
        if (isMiss(p) or isMiss(v) or isMiss(y) or (want_r and isMiss(r))) return Value.missing;
        // p.604 prints TWO ranges for the DB forms: "Range y > 0" and "Range
        // r >= 0". y was already a (silent) missing — that half is additive; r
        // was not checked at all, so depdb(10,1000,15,-2) silently computed
        // -411.30. p and v carry no printed range, so they stay unchecked.
        if (y <= 0 or (want_r and r < 0)) return domErr(ev, name);
        const acc = daccOf(d[1], p, v, y, r);
        return numVal(if (d[2]) acc else acc - daccOf(d[1], p - 1, v, y, r));
    };

    // ── loan/annuity: PMT/PPMT/IPMT and their cumulative sums
    if (eqi(name, "pmt")) { // PMT(rate, nper, pv, <fv>, <type>)
        if (args.len < 3 or args.len > 5) return badArity(ev, name, "3 to 5", args.len);
        const r = toNum(args[0]);
        const n = toNum(args[1]);
        const pv = toNum(args[2]);
        const fv = if (args.len >= 4 and !isMiss(toNum(args[3]))) toNum(args[3]) else 0;
        const kind = if (args.len >= 5) toNum(args[4]) else 0;
        if (isMiss(r) or isMiss(n) or n <= 0) return Value.missing;
        return numVal(pmtOf(r, n, pv, fv, kind));
    }
    if (eqi(name, "ipmt") or eqi(name, "ppmt")) { // ...(rate, per, nper, pv, <fv>, <type>)
        if (args.len < 4 or args.len > 6) return badArity(ev, name, "4 to 6", args.len);
        const r = toNum(args[0]);
        const per = toNum(args[1]);
        const n = toNum(args[2]);
        const pv = toNum(args[3]);
        const fv = if (args.len >= 5 and !isMiss(toNum(args[4]))) toNum(args[4]) else 0;
        const kind = if (args.len >= 6) toNum(args[5]) else 0;
        if (isMiss(r) or isMiss(per) or isMiss(n) or n <= 0 or per < 1 or per > n) return Value.missing;
        const ip = ipmtOf(r, per, n, pv, fv, kind);
        if (eqi(name, "ipmt")) return numVal(ip);
        return numVal(pmtOf(r, n, pv, fv, kind) - ip); // principal = payment − interest
    }
    if (eqi(name, "cumprinc") or eqi(name, "cumipmt")) { // ...(rate, nper, pv, start, end, type)
        if (args.len != 6) return badArity(ev, name, "6", args.len);
        const r = toNum(args[0]);
        const n = toNum(args[1]);
        const pv = toNum(args[2]);
        const startf = toNum(args[3]);
        const endf = toNum(args[4]);
        const kind = toNum(args[5]);
        // cap nper: a loan with >1e6 payments is absurd, and it bounds the per-period
        // summation loop below (no DoS — 30yr monthly = 360 payments).
        if (isMiss(r) or isMiss(n) or isMiss(startf) or isMiss(endf) or n > 1_000_000) return Value.missing;
        const s = toInt(startf) orelse return Value.missing;
        const en = toInt(endf) orelse return Value.missing;
        // compare end vs nper in float space — `n` may be huge; @intFromFloat(n) would trap
        if (s < 1 or @as(f64, @floatFromInt(en)) > n or s > en) return Value.missing;
        const pmt = pmtOf(r, n, pv, 0, kind);
        var sum: f64 = 0;
        var per = s;
        while (per <= en) : (per += 1) {
            const ip = ipmtOf(r, @floatFromInt(per), n, pv, 0, kind);
            sum += if (eqi(name, "cumipmt")) ip else pmt - ip;
        }
        return numVal(sum);
    }

    // ── European option pricing (Black-Scholes / Black / Garman-Kohlhagen / Margrabe)
    if (eqi(name, "blkshclprc") or eqi(name, "blkshptprc")) { // BS stock option (E,t,S,r,sigma)
        if (args.len != 5) return badArity(ev, name, "5", args.len);
        const eK = toNum(args[0]);
        const tt = toNum(args[1]);
        const s = toNum(args[2]);
        const r = toNum(args[3]);
        const sig = toNum(args[4]);
        if (isMiss(eK) or isMiss(tt) or isMiss(s) or isMiss(r) or isMiss(sig) or tt <= 0 or sig <= 0) return Value.missing;
        return numVal(blackOption(s * @exp(r * tt), eK, sig, tt, @exp(-r * tt), eqi(name, "blkshclprc")));
    }
    if (eqi(name, "blackclprc") or eqi(name, "blackptprc")) { // Black futures option (E,t,F,r,sigma)
        if (args.len != 5) return badArity(ev, name, "5", args.len);
        const eK = toNum(args[0]);
        const tt = toNum(args[1]);
        const fwd = toNum(args[2]);
        const r = toNum(args[3]);
        const sig = toNum(args[4]);
        if (isMiss(eK) or isMiss(tt) or isMiss(fwd) or isMiss(r) or isMiss(sig) or tt <= 0 or sig <= 0) return Value.missing;
        return numVal(blackOption(fwd, eK, sig, tt, @exp(-r * tt), eqi(name, "blackclprc")));
    }
    if (eqi(name, "garkhclprc") or eqi(name, "garkhptprc")) { // Garman-Kohlhagen FX (E,t,S,Rd,Rf,sigma)
        if (args.len != 6) return badArity(ev, name, "6", args.len);
        const eK = toNum(args[0]);
        const tt = toNum(args[1]);
        const s = toNum(args[2]);
        const rd = toNum(args[3]);
        const rf = toNum(args[4]);
        const sig = toNum(args[5]);
        if (isMiss(eK) or isMiss(tt) or isMiss(s) or isMiss(rd) or isMiss(rf) or isMiss(sig) or tt <= 0 or sig <= 0) return Value.missing;
        return numVal(blackOption(s * @exp((rd - rf) * tt), eK, sig, tt, @exp(-rd * tt), eqi(name, "garkhclprc")));
    }
    if (eqi(name, "margrclprc") or eqi(name, "margrptprc")) { // Margrabe exchange (X1,t,X2,s1,s2,rho)
        if (args.len != 6) return badArity(ev, name, "6", args.len);
        const x1 = toNum(args[0]);
        const tt = toNum(args[1]);
        const x2 = toNum(args[2]);
        const s1 = toNum(args[3]);
        const s2 = toNum(args[4]);
        const rho = toNum(args[5]);
        if (isMiss(x1) or isMiss(tt) or isMiss(x2) or isMiss(s1) or isMiss(s2) or isMiss(rho) or tt <= 0) return Value.missing;
        const sig = @sqrt(s1 * s1 + s2 * s2 - 2 * rho * s1 * s2);
        if (sig <= 0) return Value.missing;
        return numVal(blackOption(x1, x2, sig, tt, 1, eqi(name, "margrclprc")));
    }

    // ── depreciation: declining balance with straight-line conversion
    if (eqi(name, "depdbsl") or eqi(name, "daccdbsl")) {
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const p = toNum(args[0]);
        const v = toNum(args[1]);
        const y = toNum(args[2]);
        const r = toNum(args[3]);
        // y > 1e6 is not a real depreciation lifetime; reject it — this also bounds
        // daccDbsl's per-period loop and its @intFromFloat (p is clamped to ≤ y there).
        if (isMiss(p) or isMiss(v) or isMiss(y) or isMiss(r) or y <= 0 or y > 1e6) return Value.missing;
        const acc = daccDbsl(p, v, y, r);
        return numVal(if (eqi(name, "daccdbsl")) acc else acc - daccDbsl(p - 1, v, y, r));
    }

    // ── bond / cash-flow analytics: price, duration, convexity, yield
    // GAP-bondrangenote (2/2, the VALUE half): the four periodic-cash-flow
    // functions take the SAME six arguments and the reference prints the SAME
    // range table for each — PVP p.1385, YIELDP p.1688, DURP p.659, CONVXP
    // p.561. One predicate for all four beats twenty-four inline comparisons.
    // These were not checked at all, so an out-of-range argument SILENTLY
    // COMPUTED a plausible number; p.5 makes it note + _ERROR_=1 + missing,
    // which is a value change (see the commit message) rather than the purely
    // additive first half.
    // Note k0's bound is 1/n, not 1: the entries print "0 < k0 <= 1/n" (DURP
    // p.659 extracts it cleanly; PVP/CONVXP break the fraction across lines).
    // Both doc examples satisfy it — k0=.33/2=.165 with n=4 gives 1/n=.25.
    const bondOutOfRange = struct {
        fn f(a: f64, c: f64, n: f64, k0: f64, last: f64) bool {
            return a <= 0 or // "Range: A > 0" (par/face value)
                c < 0 or c >= 1 or // "Range: 0 <= c < 1" (coupon rate)
                n <= 0 or n != @trunc(n) or // "Range: n > 0 and is an integer"
                k0 <= 0 or k0 > 1 / n or // "Range: 0 < k0 <= 1/n"
                last <= 0; // "Range: y > 0" (PVP/DURP/CONVXP) or "p > 0" (YIELDP)
        }
    }.f;
    if (eqi(name, "pvp")) { // present value of a periodic (bond) cash flow
        if (args.len != 6) return badArity(ev, name, "6", args.len);
        const a = toNum(args[0]);
        const c = toNum(args[1]);
        const n = toNum(args[2]);
        const bigK = toInt(toNum(args[3])) orelse return Value.missing;
        const k0 = toNum(args[4]);
        const y = toNum(args[5]);
        if (isMiss(a) or isMiss(c) or isMiss(n) or isMiss(k0) or isMiss(y)) return Value.missing; // p.7: financial fns are the missing-value exception
        if (bigK > 1_000_000) return Value.missing; // ponytail: OUR cap (not a doc range) to bound the coupon loop — no DoS; stays silent
        if (bigK < 1 or bondOutOfRange(a, c, n, k0, y)) return domErr(ev, name); // p.1385 ranges
        return numVal(bondPv(a, c, n, @intCast(bigK), k0, y));
    }
    if (eqi(name, "dur") or eqi(name, "convx")) { // modified duration / convexity, enumerated flows
        if (args.len < 3) return badArity(ev, name, "3 or more", args.len);
        const y = toNum(args[0]);
        const f = toNum(args[1]);
        if (isMiss(y) or isMiss(f)) return Value.missing; // p.7 missing-value exception
        // DUR p.658 and CONVX p.560 share an argument list but NOT their y range:
        // DUR prints "Range y > 0", CONVX prints "Range 0 < y < 1". Checked apart
        // on purpose — collapsing them would invent a range for one of the two.
        if (f <= 0) return domErr(ev, name); // both: "Range f > 0"
        if (y <= 0 or (eqi(name, "convx") and y >= 1)) return domErr(ev, name);
        const cfs = args[2..];
        const pval = enumPv(y, f, cfs);
        if (pval == 0) return Value.missing;
        var num: f64 = 0;
        for (cfs, 1..) |c, k| {
            const kf: f64 = @floatFromInt(k);
            const pv = toNum(c) / std.math.pow(f64, 1 + y, kf / f);
            num += if (eqi(name, "dur")) kf * pv else kf * (kf + f) * pv; // doc p.561: k(k+f), not k(k+1)
        }
        return numVal(if (eqi(name, "dur"))
            num / (pval * (1 + y) * f)
        else
            num / (pval * (1 + y) * (1 + y) * f * f));
    }
    if (eqi(name, "durp") or eqi(name, "convxp")) { // modified duration / convexity, bond
        if (args.len != 6) return badArity(ev, name, "6", args.len);
        const a = toNum(args[0]);
        const c = toNum(args[1]);
        const n = toNum(args[2]);
        const bigKf = toInt(toNum(args[3])) orelse return Value.missing;
        const k0 = toNum(args[4]);
        const y = toNum(args[5]);
        if (isMiss(a) or isMiss(c) or isMiss(n) or isMiss(k0) or isMiss(y)) return Value.missing; // p.7 missing-value exception
        if (bigKf > 1_000_000) return Value.missing; // ponytail: our loop cap, not a doc range
        if (bigKf < 1 or bondOutOfRange(a, c, n, k0, y)) return domErr(ev, name); // DURP p.659 / CONVXP p.561
        const bigK: usize = @intCast(bigKf);
        const yr = y / n;
        const pval = bondPv(a, c, n, bigK, k0, y);
        if (pval == 0) return Value.missing;
        var num: f64 = 0;
        var k: usize = 1;
        while (k <= bigK) : (k += 1) {
            const tk = n * k0 + @as(f64, @floatFromInt(k)) - 1;
            const ck = c / n * a + (if (k == bigK) a else 0);
            const pv = ck / std.math.pow(f64, 1 + yr, tk);
            num += if (eqi(name, "durp")) tk * pv else tk * (tk + 1) * pv;
        }
        return numVal(if (eqi(name, "durp"))
            num / (pval * (1 + yr) * n)
        else
            num / (pval * (1 + yr) * (1 + yr) * n * n));
    }
    if (eqi(name, "yieldp")) { // periodic yield: invert PVP so price matches (bisection)
        if (args.len != 6) return badArity(ev, name, "6", args.len);
        const a = toNum(args[0]);
        const c = toNum(args[1]);
        const n = toNum(args[2]);
        const bigKf = toInt(toNum(args[3])) orelse return Value.missing;
        const k0 = toNum(args[4]);
        const price = toNum(args[5]);
        if (isMiss(a) or isMiss(c) or isMiss(n) or isMiss(k0) or isMiss(price)) return Value.missing; // p.7 missing-value exception
        if (bigKf > 1_000_000) return Value.missing; // ponytail: our loop cap, not a doc range
        if (bigKf < 1 or bondOutOfRange(a, c, n, k0, price)) return domErr(ev, name); // YIELDP p.1688 (6th arg is the price, "Range p > 0")
        const bigK: usize = @intCast(bigKf);
        var lo: f64 = -0.999999;
        var hi: f64 = 1e6;
        // price decreases as yield rises → bisect for the crossing
        if ((bondPv(a, c, n, bigK, k0, lo) < price) == (bondPv(a, c, n, bigK, k0, hi) < price)) return Value.missing;
        var it: usize = 0;
        while (it < 200) : (it += 1) {
            const mid = 0.5 * (lo + hi);
            if (bondPv(a, c, n, bigK, k0, mid) > price) lo = mid else hi = mid;
            if (hi - lo < 1e-13 * (1 + @abs(mid))) break;
        }
        return numVal(0.5 * (lo + hi));
    }

    // ── table-based depreciation: DEP*(p)=DACC*(p)−DACC*(p−1); rates are the args
    if (eqi(name, "deptab") or eqi(name, "dacctab")) { // DEPTAB(p, v, t1, …, tn)
        if (args.len < 3) return badArity(ev, name, "3 or more", args.len);
        const v = toNum(args[1]);
        if (isMiss(toNum(args[0])) or isMiss(v)) return Value.missing;
        const rates = args[2..];
        const accAt = struct {
            fn f(p: f64, vv: f64, rs: []const Value) f64 {
                // clamp to [0, len] before @intFromFloat (BUG-intfromfloat guard): a
                // period past the table is just fully accumulated (sum of all rates).
                const pc = @max(0, @min(p, @as(f64, @floatFromInt(rs.len))));
                const k: usize = @intFromFloat(@floor(pc));
                const frac = pc - @floor(pc);
                var sum: f64 = 0;
                for (rs, 0..) |r, i| {
                    if (i < k) sum += toNum(r) else if (i == k) sum += frac * toNum(r);
                }
                return vv * sum;
            }
        }.f;
        const p = toNum(args[0]);
        const acc = accAt(p, v, rates);
        return numVal(if (eqi(name, "dacctab")) acc else acc - accAt(p - 1, v, rates));
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

fn mort4(e: *eval.Evaluator, a: Value, p: Value, r: Value, n: Value) !Value {
    return (try dispatch(e, "mort", &.{ a, p, r, n })) orelse error.NotMine;
}

test "GAP-mortnonote: MORT out-of-range args log the invalid-argument NOTE (doc p.1215)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const numV = struct {
        fn f(x: f64) Value {
            return .{ .num = x };
        }
    }.f;

    // the doc-finder repro: payment (500) doesn't cover per-period interest
    // (100000·0.10) → NOTE + missing; was a silent NaN→missing.
    try t.expect((try mort4(&e, numV(100000), numV(500), numV(0.10), Value.missing)).isMissing());
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "Invalid argument to function MORT") != null);

    // rate ≤ −1 and n < 0 are flagged too (bullets 1/3).
    try t.expect((try mort4(&e, numV(1000), Value.missing, numV(-2), numV(12))).isMissing());
    try t.expect((try mort4(&e, numV(1000), Value.missing, numV(0.01), numV(-5))).isMissing());
    try t.expectEqual(@as(usize, 3), h.diags.count());

    // the doc example (solve the payment) still computes, no extra note.
    const pay = try mort4(&e, numV(50000), Value.missing, numV(0.10 / 12.0), numV(360));
    try t.expect(@abs(pay.num - 438.7858) < 1e-3); // doc: payment=438.79
    try t.expectEqual(@as(usize, 3), h.diags.count());
}

fn saving4(e: *eval.Evaluator, f: Value, p: Value, r: Value, n: Value) !Value {
    return (try dispatch(e, "saving", &.{ f, p, r, n })) orelse error.NotMine;
}

test "BUG-savingdomain: SAVING out-of-range args log the invalid-argument NOTE (like MORT)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();
    const numV = struct {
        fn f(x: f64) Value {
            return .{ .num = x };
        }
    }.f;

    // out-of-range (negative amount/payment) → NOTE + missing, was silent nonsense.
    try t.expect((try saving4(&e, numV(-100), numV(100), numV(0.01), Value.missing)).isMissing());
    try t.expect((try saving4(&e, Value.missing, numV(-100), numV(0.01), numV(12))).isMissing());
    try t.expect((try saving4(&e, numV(-500), Value.missing, numV(0.01), numV(12))).isMissing());
    try t.expectEqual(@as(usize, 3), h.diags.count());
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "Invalid argument to function SAVING") != null);

    // valid in-range solve (solve for f) still computes, no extra note.
    const fut = try saving4(&e, Value.missing, numV(100), numV(0.005), numV(12));
    try t.expect(@abs(fut.num - 1239.724) < 1e-2); // annuity-due: p·(1+r)·((1+r)ⁿ−1)/r
    try t.expectEqual(@as(usize, 3), h.diags.count());
}
