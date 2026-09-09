//! Statistics functions (aggregates, descriptive stats, probability
//! distributions, special functions, random-variate generators), split verbatim
//! out of functions.zig dispatch (QL-A). Shared helpers (and the RNG state they
//! close over) stay in functions.zig; `null` means "name not mine".
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
const agg = fns.agg;
const ascF64 = fns.ascF64;
const besselI = fns.besselI;
const besselJ = fns.besselJ;
const betaI = fns.betaI;
const bisectCdf = fns.bisectCdf;
const collectNums = fns.collectNums;
const cssMean = fns.cssMean;
const devianceOf = fns.devianceOf;
const distCdf = fns.distCdf;
const distIs = fns.distIs;
const distLogCdfSdf = fns.distLogCdfSdf;
const distLogPdf = fns.distLogPdf;
const distPdf = fns.distPdf;
const distQuantile = fns.distQuantile;
const drawGamma = fns.drawGamma;
const drawNormal = fns.drawNormal;
const gammaP = fns.gammaP;
const hyperCdf = fns.hyperCdf;
const isValidName = fns.isValidName;
const lgammaOf = fns.lgammaOf;
/// BUG-noncentralinverse: TINV/FINV/CINV accepted a noncentrality arg but
/// bisected the CENTRAL CDF, silently returning the central quantile. Invert the
/// same noncentral CDF the forward PROBT/PROBF/PROBCHI evaluate. nc==0 callers
/// keep the shared bisectCdf path (central results byte-identical).
const NcCdfKind = enum { chisq, f, t };
fn ncCdfEval(kind: NcCdfKind, x: f64, p1: f64, p2: f64, nc: f64) f64 {
    return switch (kind) {
        .chisq => noncentralChisqCdf(x, p1, nc),
        .f => noncentralFCdf(x, p1, p2, nc),
        .t => noncentralTCdf(x, p1, nc),
    };
}
fn bisectNcCdf(kind: NcCdfKind, p: f64, p1: f64, p2: f64, nc: f64, lo0: f64, hi0: f64) f64 {
    var lo = lo0;
    var hi = hi0;
    var it: usize = 0;
    while (it < 200) : (it += 1) {
        const mid = 0.5 * (lo + hi);
        if (ncCdfEval(kind, mid, p1, p2, nc) < p) lo = mid else hi = mid;
        if (hi - lo < 1e-12 * (1 + @abs(mid))) break;
    }
    return 0.5 * (lo + hi);
}

const nextRandUniform = fns.nextRandUniform;
const nextUniform = fns.nextUniform;
const noncentralChisqCdf = fns.noncentralChisqCdf;
const noncentralFCdf = fns.noncentralFCdf;
const noncentralTCdf = fns.noncentralTCdf;
const parseDist = fns.parseDist;
const pctlDef5 = fns.pctlDef5;
const probMed = fns.probMed;
const solveNoncentrality = fns.solveNoncentrality;

pub fn dispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!?Value {
    // ── numeric aggregates: ignore missing, return missing only if none present
    if (eqi(name, "sum")) return agg(.sum, args);
    if (eqi(name, "mean")) return agg(.mean, args);
    if (eqi(name, "min")) return agg(.min, args);
    if (eqi(name, "max")) return agg(.max, args);
    if (eqi(name, "n")) return agg(.n, args);
    if (eqi(name, "nmiss")) return agg(.nmiss, args);

    // ── descriptive statistics over the nonmissing argument list
    if (eqi(name, "css")) { // corrected sum of squares Σ(x-mean)²
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        return numVal(cssMean(xs).css);
    }
    if (eqi(name, "uss")) { // uncorrected sum of squares Σx²
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| s += x * x;
        return numVal(s);
    }
    if (eqi(name, "cv")) { // coefficient of variation: 100·(sample std)/mean
        const xs = try collectNums(ev, args);
        if (xs.len < 2) return Value.missing;
        const cm = cssMean(xs);
        if (cm.mean == 0) return Value.missing;
        const sd = @sqrt(cm.css / @as(f64, @floatFromInt(xs.len - 1)));
        return numVal(100.0 * sd / cm.mean);
    }
    if (eqi(name, "rms")) { // root mean square sqrt(Σx²/n)
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| s += x * x;
        return numVal(@sqrt(s / @as(f64, @floatFromInt(xs.len))));
    }
    if (eqi(name, "euclid")) { // L2 norm sqrt(Σx²)
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| s += x * x;
        return numVal(@sqrt(s));
    }
    if (eqi(name, "sumabs")) { // L1 norm Σ|x|
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| s += @abs(x);
        return numVal(s);
    }
    if (eqi(name, "lpnorm")) { // (Σ|xᵢ|^p)^(1/p) over the 2nd+ nonmissing args
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const p = toNum(args[0]);
        if (isMiss(p) or p < 1) return domErr(ev, name);
        const xs = try collectNums(ev, args[1..]);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| s += std.math.pow(f64, @abs(x), p);
        return numVal(std.math.pow(f64, s, 1.0 / p));
    }
    if (eqi(name, "geomean") or eqi(name, "geomeanz")) { // (Πx)^(1/n), x≥0
        // ponytail: GEOMEAN fuzzes near-zero args, GEOMEANZ doesn't — we don't
        // fuzz either way, so they share one impl.
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| {
            if (x < 0) return domErr(ev, name);
            if (x == 0) return numVal(0);
            s += @log(x);
        }
        return numVal(@exp(s / @as(f64, @floatFromInt(xs.len))));
    }
    if (eqi(name, "harmean") or eqi(name, "harmeanz")) { // n/Σ(1/x), x>0
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var s: f64 = 0;
        for (xs) |x| {
            if (x <= 0) return domErr(ev, name);
            s += 1.0 / x;
        }
        return numVal(@as(f64, @floatFromInt(xs.len)) / s);
    }
    if (eqi(name, "skewness")) { // sample skewness (n≥3)
        const xs = try collectNums(ev, args);
        const n = xs.len;
        if (n < 3) return Value.missing;
        const cm = cssMean(xs);
        const nf: f64 = @floatFromInt(n);
        const sd = @sqrt(cm.css / (nf - 1));
        if (sd == 0) return Value.missing;
        var s3: f64 = 0;
        for (xs) |x| s3 += std.math.pow(f64, (x - cm.mean) / sd, 3);
        return numVal(nf / ((nf - 1) * (nf - 2)) * s3);
    }
    if (eqi(name, "kurtosis")) { // sample excess kurtosis (n≥4)
        const xs = try collectNums(ev, args);
        const n = xs.len;
        if (n < 4) return Value.missing;
        const cm = cssMean(xs);
        const nf: f64 = @floatFromInt(n);
        const sd = @sqrt(cm.css / (nf - 1));
        if (sd == 0) return Value.missing;
        var s4: f64 = 0;
        for (xs) |x| s4 += std.math.pow(f64, (x - cm.mean) / sd, 4);
        const a = nf * (nf + 1) / ((nf - 1) * (nf - 2) * (nf - 3)) * s4;
        const b = 3 * (nf - 1) * (nf - 1) / ((nf - 2) * (nf - 3));
        return numVal(a - b);
    }
    if (eqi(name, "median")) {
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        std.mem.sort(f64, xs, {}, ascF64);
        return numVal(pctlDef5(xs, 50));
    }
    if (eqi(name, "range")) { // max - min of the nonmissing args
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        var lo = xs[0];
        var hi = xs[0];
        for (xs) |x| {
            if (x < lo) lo = x;
            if (x > hi) hi = x;
        }
        return numVal(hi - lo);
    }
    if (eqi(name, "iqr")) { // P75 − P25 (definition 5)
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        std.mem.sort(f64, xs, {}, ascF64);
        return numVal(pctlDef5(xs, 75) - pctlDef5(xs, 25));
    }
    if (eqi(name, "mad")) { // median of |xᵢ − median|
        const xs = try collectNums(ev, args);
        if (xs.len == 0) return Value.missing;
        std.mem.sort(f64, xs, {}, ascF64);
        const med = pctlDef5(xs, 50);
        const dev = try ev.arena.alloc(f64, xs.len);
        for (xs, dev) |x, *d| d.* = @abs(x - med);
        std.mem.sort(f64, dev, {}, ascF64);
        return numVal(pctlDef5(dev, 50));
    }
    if (eqi(name, "pctl")) { // PCTL(percentage, values…), definition 5
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const pct = toNum(args[0]);
        if (isMiss(pct) or pct < 0 or pct > 100) return domErr(ev, name);
        const xs = try collectNums(ev, args[1..]);
        if (xs.len == 0) return Value.missing;
        std.mem.sort(f64, xs, {}, ascF64);
        return numVal(pctlDef5(xs, pct));
    }
    if (eqi(name, "largest") or eqi(name, "smallest")) { // k-th of nonmissing values
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const kf = toNum(args[0]);
        const xs = try collectNums(ev, args[1..]);
        if (isMiss(kf) or kf < 1 or kf > @as(f64, @floatFromInt(args.len - 1))) return Value.missing;
        const k: usize = @intFromFloat(kf);
        if (k > xs.len) return Value.missing; // fewer nonmissing than k
        std.mem.sort(f64, xs, {}, ascF64);
        return numVal(if (eqi(name, "largest")) xs[xs.len - k] else xs[k - 1]);
    }
    if (eqi(name, "ordinal")) { // k-th smallest, missing values included in the order
        if (args.len < 3) return badArity(ev, name, "3 or more", args.len);
        const kf = toNum(args[0]);
        const nvals = args.len - 1;
        if (isMiss(kf) or kf < 1 or kf > @as(f64, @floatFromInt(nvals))) return Value.missing;
        const all = try ev.arena.alloc(f64, nvals);
        for (args[1..], all) |a, *slot| {
            const x = toNum(a);
            slot.* = if (isMiss(x)) -std.math.inf(f64) else x; // missing sorts lowest
        }
        std.mem.sort(f64, all, {}, ascF64);
        const k: usize = @intFromFloat(kf);
        const v = all[k - 1];
        return if (std.math.isInf(v)) Value.missing else numVal(v);
    }

    // ── probability distributions (CDFs) and their quantile inverses
    if (eqi(name, "probgam")) { // gamma CDF: P(a, x)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const x = toNum(args[0]);
        const a = toNum(args[1]);
        if (isMiss(x) or isMiss(a)) return Value.missing;
        if (a <= 0) return domErr(ev, name);
        return numVal(gammaP(a, x));
    }
    if (eqi(name, "probchi")) { // chi-square CDF, central or noncentral (optional nc)
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const x = toNum(args[0]);
        const df = toNum(args[1]);
        const nc = if (args.len == 3) toNum(args[2]) else 0;
        if (isMiss(x) or isMiss(df) or isMiss(nc)) return Value.missing;
        if (df <= 0 or nc < 0) return domErr(ev, name);
        return numVal(noncentralChisqCdf(x, df, nc));
    }
    if (eqi(name, "poisson")) { // Poisson CDF P(X≤n) = Q(n+1, m)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const m = toNum(args[0]);
        const n = toNum(args[1]);
        if (isMiss(m) or isMiss(n)) return Value.missing;
        if (m < 0 or n < 0) return domErr(ev, name);
        return numVal(1.0 - gammaP(@floor(n) + 1.0, m));
    }
    if (eqi(name, "probbeta")) { // beta CDF: I_x(a,b)
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const x = toNum(args[0]);
        const a = toNum(args[1]);
        const b = toNum(args[2]);
        if (isMiss(x) or isMiss(a) or isMiss(b)) return Value.missing;
        if (a <= 0 or b <= 0) return domErr(ev, name);
        return numVal(betaI(x, a, b));
    }
    if (eqi(name, "probf")) { // F CDF, central or noncentral (optional nc)
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const x = toNum(args[0]);
        const ndf = toNum(args[1]);
        const ddf = toNum(args[2]);
        const nc = if (args.len == 4) toNum(args[3]) else 0;
        if (isMiss(x) or isMiss(ndf) or isMiss(ddf) or isMiss(nc)) return Value.missing;
        if (ndf <= 0 or ddf <= 0 or nc < 0) return domErr(ev, name);
        if (x <= 0) return numVal(0);
        return numVal(noncentralFCdf(x, ndf, ddf, nc));
    }
    if (eqi(name, "probt")) { // Student's t CDF, central or noncentral (optional nc)
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const x = toNum(args[0]);
        const df = toNum(args[1]);
        const nc = if (args.len == 3) toNum(args[2]) else 0;
        if (isMiss(x) or isMiss(df) or isMiss(nc)) return Value.missing;
        if (df <= 0) return domErr(ev, name);
        return numVal(noncentralTCdf(x, df, nc));
    }
    if (eqi(name, "probmed")) { // CDF of the sample median of n std-normal draws
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const nf = toNum(args[0]);
        const x = toNum(args[1]);
        if (isMiss(nf) or isMiss(x)) return Value.missing;
        const n = toInt(nf) orelse return Value.missing;
        if (n < 1) return domErr(ev, name);
        return numVal(probMed(n, x));
    }
    if (eqi(name, "probbnml")) { // binomial CDF P(X≤m) = I_{1-p}(n-m, m+1)
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const p = toNum(args[0]);
        const n = toNum(args[1]);
        const m = toNum(args[2]);
        if (isMiss(p) or isMiss(n) or isMiss(m)) return Value.missing;
        if (p < 0 or p > 1 or n < 1) return domErr(ev, name);
        if (m < 0) return numVal(0);
        if (m >= n) return numVal(1);
        return numVal(betaI(1.0 - p, n - m, m + 1.0));
    }
    if (eqi(name, "gaminv")) { // inverse gamma CDF
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const p = toNum(args[0]);
        const a = toNum(args[1]);
        if (isMiss(p) or isMiss(a)) return Value.missing;
        // BUG-invquantp1: reject p>=1 like tinv/QUANTILE (was p>1, ran solver to
        // a garbage finite bound at p==1). p==0 stays 0 (SAS: 0<=p<1 domain).
        if (p < 0 or p >= 1 or a <= 0) return domErr(ev, name);
        if (p == 0) return numVal(0);
        return numVal(bisectCdf(.gamma, p, a, 0, 0, 1e7));
    }
    if (eqi(name, "cinv")) { // inverse chi-square CDF
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const p = toNum(args[0]);
        const df = toNum(args[1]);
        const nc = if (args.len == 3) toNum(args[2]) else 0;
        if (isMiss(p) or isMiss(df) or isMiss(nc)) return Value.missing;
        // BUG-invquantp1: reject p>=1 like tinv/QUANTILE. p==0 stays 0.
        if (p < 0 or p >= 1 or df <= 0 or nc < 0) return domErr(ev, name);
        if (p == 0) return numVal(0);
        if (nc > 0) return numVal(bisectNcCdf(.chisq, p, df, 0, nc, 0, 1e7));
        return numVal(bisectCdf(.chisq, p, df, 0, 0, 1e7));
    }
    if (eqi(name, "betainv")) { // inverse beta CDF (x in [0,1])
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const p = toNum(args[0]);
        const a = toNum(args[1]);
        const b = toNum(args[2]);
        if (isMiss(p) or isMiss(a) or isMiss(b)) return Value.missing;
        if (p < 0 or p > 1 or a <= 0 or b <= 0) return domErr(ev, name);
        // BUG-betainvendpoint: beta support is [0,1]; return exact endpoints
        // instead of the bisection's 4.5e-13 / 0.99996 artifacts.
        if (p == 0) return numVal(0);
        if (p == 1) return numVal(1);
        return numVal(bisectCdf(.beta, p, a, b, 0, 1));
    }
    if (eqi(name, "finv")) { // inverse F CDF
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const p = toNum(args[0]);
        const ndf = toNum(args[1]);
        const ddf = toNum(args[2]);
        const nc = if (args.len == 4) toNum(args[3]) else 0;
        if (isMiss(p) or isMiss(ndf) or isMiss(ddf) or isMiss(nc)) return Value.missing;
        // BUG-invquantp1: reject p>=1 like tinv/QUANTILE. p==0 stays 0.
        if (p < 0 or p >= 1 or ndf <= 0 or ddf <= 0 or nc < 0) return domErr(ev, name);
        if (p == 0) return numVal(0);
        if (nc > 0) return numVal(bisectNcCdf(.f, p, ndf, ddf, nc, 0, 1e7));
        return numVal(bisectCdf(.f, p, ndf, ddf, 0, 1e7));
    }
    if (eqi(name, "tinv")) { // inverse Student's t CDF (can be negative)
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const p = toNum(args[0]);
        const df = toNum(args[1]);
        const nc = if (args.len == 3) toNum(args[2]) else 0; // SAS: may be negative
        if (isMiss(p) or isMiss(df) or isMiss(nc)) return Value.missing;
        if (p <= 0 or p >= 1 or df <= 0) return domErr(ev, name);
        if (nc != 0) return numVal(bisectNcCdf(.t, p, df, 0, nc, -1e6, 1e6));
        return numVal(bisectCdf(.t, p, df, 0, -1e6, 1e6));
    }
    if (eqi(name, "cnonct")) { // noncentrality of a chi-square giving CDF(x;df)=prob
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const x = toNum(args[0]);
        const df = toNum(args[1]);
        const prob = toNum(args[2]);
        if (isMiss(x) or isMiss(df) or isMiss(prob)) return Value.missing;
        if (df <= 0 or prob <= 0 or prob >= 1) return domErr(ev, name);
        return numVal(solveNoncentrality(.chisq, x, df, 0, prob) orelse return Value.missing);
    }
    if (eqi(name, "fnonct")) { // noncentrality of an F distribution
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const x = toNum(args[0]);
        const ndf = toNum(args[1]);
        const ddf = toNum(args[2]);
        const prob = toNum(args[3]);
        if (isMiss(x) or isMiss(ndf) or isMiss(ddf) or isMiss(prob)) return Value.missing;
        if (ndf <= 0 or ddf <= 0 or prob <= 0 or prob >= 1) return domErr(ev, name);
        return numVal(solveNoncentrality(.f, x, ndf, ddf, prob) orelse return Value.missing);
    }
    if (eqi(name, "tnonct")) { // noncentrality of a Student's t distribution
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const x = toNum(args[0]);
        const df = toNum(args[1]);
        const prob = toNum(args[2]);
        if (isMiss(x) or isMiss(df) or isMiss(prob)) return Value.missing;
        if (df <= 0 or prob <= 0 or prob >= 1) return domErr(ev, name);
        return numVal(solveNoncentrality(.t, x, df, 0, prob) orelse return Value.missing);
    }

    // ── distribution family: CDF/SDF/PDF/QUANTILE and their log/right-tail siblings
    if (eqi(name, "cdf") or eqi(name, "sdf") or eqi(name, "logcdf") or eqi(name, "logsdf")) {
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const dname = try toStr(ev, args[0]);
        const d = parseDist(dname);
        const ed = if (d == null) parseExtDist(dname) else null;
        if (d == null and ed == null) return unknownDist(ev, name, dname);
        const x = toNum(args[1]);
        if (isMiss(x)) return Value.missing;
        const c = if (d) |dd|
            (cdfNc(ev, name, dd, x, args) orelse return Value.missing)
        else
            (extCdf(ev, name, ed.?, x, args) orelse return Value.missing);
        if (std.math.isNan(c)) return Value.missing;
        const right = eqi(name, "sdf") or eqi(name, "logsdf");
        const val = if (right) 1.0 - c else c;
        if (eqi(name, "logcdf") or eqi(name, "logsdf")) {
            if (val > 0) return numVal(@log(val)); // mid-range: byte-identical to before
            // BUG-logxdftail: the tail probability underflowed f64 to exactly 0,
            // so log(val) = −inf → missing — precisely the deep-tail range the
            // LOGxDF family exists for (doc LOGCDF p.1169). Recompute in log-space.
            const lv = if (d) |dd|
                distLogCdfSdf(dd, x, args, right)
            else
                extLogCdfSdf(ed.?, x, args, right);
            return numVal(lv orelse return Value.missing);
        }
        return numVal(val);
    }
    if (eqi(name, "pdf") or eqi(name, "logpdf")) {
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const dname = try toStr(ev, args[0]);
        const d = parseDist(dname);
        const ed = if (d == null) parseExtDist(dname) else null;
        if (d == null and ed == null) return unknownDist(ev, name, dname);
        const x = toNum(args[1]);
        if (isMiss(x)) return Value.missing;
        const dens = if (d) |dd|
            (distPdf(dd, x, args) orelse return Value.missing)
        else
            (extPdf(ev, name, ed.?, x, args) orelse return Value.missing);
        if (eqi(name, "logpdf")) {
            if (dens > 0 and !std.math.isInf(dens)) return numVal(@log(dens)); // byte-identical
            // BUG-logxdftail: dens underflowed to 0 deep in the tail (or blew up
            // to inf/NaN at a pole) — compute the log-density in log-space.
            // −inf/NaN out of it → missing, exactly like log(dens) before.
            const lv = if (d) |dd|
                distLogPdf(dd, x, args)
            else
                extLogPdf(ed.?, x, args);
            return numVal(lv);
        }
        if (std.math.isNan(dens)) return Value.missing;
        return numVal(dens);
    }
    if (eqi(name, "quantile") or eqi(name, "squantile")) {
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        const dname = try toStr(ev, args[0]);
        const d = parseDist(dname);
        const ed = if (d == null) parseExtDist(dname) else null;
        if (d == null and ed == null) return unknownDist(ev, name, dname);
        var p = toNum(args[1]);
        if (isMiss(p)) return Value.missing;
        if (eqi(name, "squantile")) p = 1.0 - p; // right-tail probability → left
        if (p <= 0 or p >= 1) return domErr(ev, name);
        const q = if (d) |dd|
            (distQuantile(dd, p, args) orelse return Value.missing)
        else
            (extQuantile(ev, name, ed.?, p, args) orelse return Value.missing);
        if (std.math.isNan(q)) return Value.missing;
        return numVal(q);
    }

    // ── extra distributions, special functions, name checks
    if (eqi(name, "probnegb")) { // negative-binomial CDF P(X≤m) = I_p(n, m+1)
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const p = toNum(args[0]);
        const n = toNum(args[1]);
        const m = toNum(args[2]);
        if (isMiss(p) or isMiss(n) or isMiss(m)) return Value.missing;
        if (p < 0 or p > 1 or n <= 0) return domErr(ev, name);
        if (m < 0) return numVal(0);
        return numVal(betaI(p, n, @floor(m) + 1.0));
    }
    if (eqi(name, "probhypr")) { // hypergeometric CDF; optional odds ratio ignored (central)
        if (args.len < 4 or args.len > 5) return badArity(ev, name, "4 or 5", args.len);
        const bigN = toNum(args[0]);
        const bigK = toNum(args[1]);
        const n = toNum(args[2]);
        const x = toNum(args[3]);
        if (isMiss(bigN) or isMiss(bigK) or isMiss(n) or isMiss(x)) return Value.missing;
        if (bigN < 0 or bigK < 0 or bigK > bigN or n < 0 or n > bigN) return domErr(ev, name);
        return numVal(hyperCdf(bigN, bigK, n, @floor(x)));
    }
    if (eqi(name, "jbessel")) { // Bessel J_nu(x)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const nu = toNum(args[0]);
        const x = toNum(args[1]);
        // NOTE-besselneg: JBESSEL's `nu` carries "Range nu ≥ 0" (Functions ref
        // p.1115), so nu<0 is an argument OUTSIDE THE PRESCRIBED RANGE — which
        // p.5 defines as invalid: note + _ERROR_=1 + missing. The missing was
        // already right; the diagnostic was not there. Same domErr path the
        // sibling range checks in this file already use (hyperCdf just above).
        if (isMiss(nu) or isMiss(x)) return Value.missing;
        if (nu < 0) return domErr(ev, name);
        return numVal(besselJ(nu, x));
    }
    if (eqi(name, "ibessel")) { // modified Bessel I_nu(x); kode≠0 → exp(−|x|)-scaled
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const nu = toNum(args[0]);
        const x = toNum(args[1]);
        const kode = toNum(args[2]);
        if (isMiss(nu) or isMiss(x) or isMiss(kode)) return Value.missing;
        if (nu < 0) return domErr(ev, name); // "Range nu ≥ 0", p.1022 — see JBESSEL above
        return numVal(besselI(nu, x, kode != 0));
    }
    if (eqi(name, "nvalid")) { // 1 if a valid SAS variable name (V7 rules)
        if (args.len < 1 or args.len > 2) return badArity(ev, name, "1 or 2", args.len);
        return numVal(if (isValidName(std.mem.trim(u8, try toStr(ev, args[0]), " "))) 1 else 0);
    }
    if (eqi(name, "deviance")) { // GLM deviance of a value from its mean/shape
        if (args.len < 3 or args.len > 5) return badArity(ev, name, "3 to 5", args.len);
        const dname = try toStr(ev, args[0]);
        const y = toNum(args[1]);
        const mu = toNum(args[2]);
        if (isMiss(y) or isMiss(mu)) return Value.missing;
        // BUG-devianceeps (doc pp.614–618): ε is the LAST argument — the 4th for
        // most distributions, the 5th for BINOMIAL whose shape params are (μ, n).
        // ponytail: a missing ε takes the doc default 1e-12 (unprobed; needs-oracle).
        const bino = distIs(std.mem.trim(u8, dname, " "), "BINOMIAL");
        const n = if (bino and args.len >= 4) toNum(args[3]) else 0;
        const eps_idx: usize = if (bino) 4 else 3;
        const eps = if (args.len > eps_idx) toNum(args[eps_idx]) else 1e-12;
        const dv = devianceOf(dname, y, mu, n, if (isMiss(eps)) 1e-12 else eps) orelse return Value.missing;
        if (std.math.isNan(dv)) return Value.missing;
        return numVal(dv);
    }
    // ── random-variate generators (SAS's classic seeded streams; see nextUniform)
    if (eqi(name, "ranuni") or eqi(name, "uniform")) { // uniform (0,1)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        if (isMiss(toNum(args[0]))) return Value.missing;
        return numVal(nextUniform(ev, toNum(args[0])));
    }
    if (eqi(name, "ranexp")) { // exponential(1): −ln(U) (inverse transform, per SAS)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        if (isMiss(toNum(args[0]))) return Value.missing;
        return numVal(-@log(nextUniform(ev, toNum(args[0]))));
    }
    if (eqi(name, "rancau")) { // Cauchy(0,1): tan(π(U−½)) (inverse transform)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        if (isMiss(toNum(args[0]))) return Value.missing;
        return numVal(@tan(std.math.pi * (nextUniform(ev, toNum(args[0])) - 0.5)));
    }
    if (eqi(name, "rannor") or eqi(name, "normal")) { // standard normal via Box-Muller
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        if (isMiss(toNum(args[0]))) return Value.missing;
        const ua = nextUniform(ev, toNum(args[0]));
        const ub = nextUniform(ev, toNum(args[0]));
        return numVal(@sqrt(-2.0 * @log(ua)) * @cos(2.0 * std.math.pi * ub));
    }
    if (eqi(name, "rantri")) { // triangular(0,1) with mode h, inverse transform
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const h = toNum(args[1]);
        if (isMiss(toNum(args[0])) or isMiss(h) or h < 0 or h > 1) return Value.missing;
        const u = nextUniform(ev, toNum(args[0]));
        return numVal(if (u < h) @sqrt(u * h) else 1.0 - @sqrt((1.0 - u) * (1.0 - h)));
    }
    if (eqi(name, "ranpoi")) { // Poisson(m) via Knuth's inverse method
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const seed = toNum(args[0]);
        const m = toNum(args[1]);
        if (isMiss(seed) or isMiss(m) or m < 0 or m > 1_000_000) return Value.missing;
        const lim = @exp(-m);
        var k: f64 = 0;
        var p: f64 = 1;
        while (true) {
            p *= nextUniform(ev, seed);
            if (p <= lim) break;
            k += 1;
        }
        return numVal(k);
    }
    if (eqi(name, "ranbin")) { // Binomial(n,p): count of n Bernoulli(p) draws
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const seed = toNum(args[0]);
        const nf = toNum(args[1]);
        const p = toNum(args[2]);
        if (isMiss(seed) or isMiss(nf) or isMiss(p) or nf < 0 or nf > 1_000_000 or p < 0 or p > 1) return Value.missing;
        const n: usize = @intFromFloat(@floor(nf));
        var count: f64 = 0;
        var i: usize = 0;
        while (i < n) : (i += 1) if (nextUniform(ev, seed) < p) {
            count += 1;
        };
        return numVal(count);
    }
    if (eqi(name, "rantbl")) { // RANTBL(seed, p1,…,pk): index i where U falls, 1-based
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        if (isMiss(toNum(args[0]))) return Value.missing;
        const u = nextUniform(ev, toNum(args[0]));
        var cum: f64 = 0;
        for (args[1..], 1..) |pv, idx| {
            cum += toNum(pv);
            if (u <= cum) return numVal(@floatFromInt(idx));
        }
        return numVal(@floatFromInt(args.len - 1)); // U past the table → last index
    }
    if (eqi(name, "rangam")) { // Gamma(shape a, scale 1) via Marsaglia–Tsang (2000)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const seed = toNum(args[0]);
        const a = toNum(args[1]);
        if (isMiss(seed) or isMiss(a) or a <= 0) return Value.missing;
        return numVal(drawGamma(ev, seed, false, a));
    }
    if (eqi(name, "rand")) { // modern RNG: RAND(dist <, parms>) over the shared stream
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        const dist = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        const par = struct { // parameter i (0-based, after the dist name) or a default
            fn f(a: []const Value, i: usize, d: f64) f64 {
                return if (a.len > 1 + i) toNum(a[1 + i]) else d;
            }
        }.f;
        const sd: f64 = 0; // RAND has no seed arg (set by CALL STREAMINIT) → shared stream
        if (distIs(dist, "UNIFORM"))
            return numVal(par(args, 0, 0) + (par(args, 1, 1) - par(args, 0, 0)) * nextRandUniform(ev));
        if (distIs(dist, "NORMAL") or distIs(dist, "GAUSSIAN"))
            return numVal(par(args, 0, 0) + par(args, 1, 1) * drawNormal(ev, sd, true));
        if (distIs(dist, "EXPONENTIAL"))
            return numVal(-par(args, 0, 1) * @log(nextRandUniform(ev)));
        if (distIs(dist, "CAUCHY"))
            return numVal(@tan(std.math.pi * (nextRandUniform(ev) - 0.5)));
        if (distIs(dist, "BERNOULLI"))
            return numVal(if (nextRandUniform(ev) < par(args, 0, 0.5)) 1 else 0);
        if (distIs(dist, "GAMMA"))
            return numVal(par(args, 1, 1) * drawGamma(ev, sd, true, par(args, 0, 1)));
        if (distIs(dist, "CHISQUARE"))
            return numVal(2.0 * drawGamma(ev, sd, true, par(args, 0, 1) / 2.0)); // χ²(df) = 2·Γ(df/2)
        if (distIs(dist, "BETA")) { // X/(X+Y), X~Γ(a), Y~Γ(b)
            const gx = drawGamma(ev, sd, true, par(args, 0, 1));
            const gy = drawGamma(ev, sd, true, par(args, 1, 1));
            return numVal(gx / (gx + gy));
        }
        if (distIs(dist, "T")) { // Z / sqrt(χ²(df)/df)
            const df = par(args, 0, 1);
            return numVal(drawNormal(ev, sd, true) / @sqrt(2.0 * drawGamma(ev, sd, true, df / 2.0) / df));
        }
        if (distIs(dist, "F")) { // (χ²(m)/m)/(χ²(n)/n)
            const m = par(args, 0, 1);
            const n = par(args, 1, 1);
            return numVal((2.0 * drawGamma(ev, sd, true, m / 2.0) / m) / (2.0 * drawGamma(ev, sd, true, n / 2.0) / n));
        }
        if (distIs(dist, "POISSON")) { // Knuth
            const mean = par(args, 0, 1);
            if (mean < 0 or mean > 1_000_000) return Value.missing;
            const lim = @exp(-mean);
            var k: f64 = 0;
            var p: f64 = 1;
            while (true) {
                p *= nextRandUniform(ev);
                if (p <= lim) break;
                k += 1;
            }
            return numVal(k);
        }
        if (distIs(dist, "BINOMIAL")) { // count of n Bernoulli(p)
            const p = par(args, 0, 0.5);
            const nf = par(args, 1, 1);
            if (nf < 0 or nf > 1_000_000 or p < 0 or p > 1) return Value.missing;
            const n: usize = @intFromFloat(@floor(nf));
            var count: f64 = 0;
            var i: usize = 0;
            while (i < n) : (i += 1) if (nextRandUniform(ev) < p) {
                count += 1;
            };
            return numVal(count);
        }
        if (distIs(dist, "WEIBULL")) { // b·(−ln U)^(1/a) (inverse transform)
            const a = par(args, 0, 1);
            const b = par(args, 1, 1);
            if (a <= 0 or b <= 0) return Value.missing;
            return numVal(b * std.math.pow(f64, -@log(nextRandUniform(ev)), 1.0 / a));
        }
        if (distIs(dist, "GEOMETRIC")) { // failures before 1st success (inverse transform)
            const p = par(args, 0, 0.5);
            if (p <= 0 or p > 1) return Value.missing;
            return numVal(@floor(@log(nextRandUniform(ev)) / @log(1.0 - p)));
        }
        if (distIs(dist, "NEGBINOMIAL")) { // failures before n-th success: n geometric draws
            const p = par(args, 0, 0.5);
            const nf = par(args, 1, 1);
            if (p <= 0 or p > 1 or nf < 1 or nf > 1_000_000) return Value.missing;
            const n: usize = @intFromFloat(@floor(nf));
            var tot: f64 = 0;
            var i: usize = 0;
            while (i < n) : (i += 1) tot += @floor(@log(nextRandUniform(ev)) / @log(1.0 - p));
            return numVal(tot);
        }
        if (distIs(dist, "HYPERGEOMETRIC")) { // n draws without replacement from (N,R)
            const bigN = par(args, 0, std.math.nan(f64));
            const bigR = par(args, 1, std.math.nan(f64));
            const nf = par(args, 2, std.math.nan(f64));
            if (isMiss(bigN) or isMiss(bigR) or isMiss(nf)) return Value.missing;
            if (bigN < 1 or bigR < 0 or bigR > bigN or nf < 0 or nf > bigN or nf > 1_000_000) return Value.missing;
            var rr = @floor(bigR);
            var nn = @floor(bigN);
            var succ: f64 = 0;
            var i: usize = 0;
            const ni: usize = @intFromFloat(@floor(nf));
            while (i < ni) : (i += 1) {
                if (nextRandUniform(ev) < rr / nn) {
                    succ += 1;
                    rr -= 1;
                }
                nn -= 1;
            }
            return numVal(succ);
        }
        // unknown dist → loud ERROR (D-002; was silent missing, GAP-distsilentmiss).
        // WALD/IGAUSS, TABLE, TRIANGLE … land here too: recognized gaps, not no-ops.
        ev.diags.report(.err, 0, "RAND: distribution '{s}' is not supported", .{dist}) catch {};
        return Value.missing;
    }

    return null;
}

// ── GAP-distsilentmiss: distributions beyond functions.zig's closed Dist enum
// (kept here so the change stays inside statfns.zig) + fail-loud on unknowns.

/// The added set: WEIBULL, GEOMETRIC, NEGBINOMIAL, HYPERGEOMETRIC (SAS 9.4
/// functions ref, CDF pp.485–502), LAPLACE, PARETO (closed-form continuous,
/// GAP-quantiledists). WALD/IGAUSS, NORMALMIX, TWEEDIE and RAND TABLE
/// deliberately stay fail-loud — recognized gaps, never silent missing.
const ExtDist = enum { weibull, geometric, negbinomial, hypergeometric, laplace, pareto };

fn parseExtDist(s_in: []const u8) ?ExtDist {
    const s = std.mem.trim(u8, s_in, " ");
    if (distIs(s, "WEIBULL")) return .weibull;
    if (distIs(s, "GEOMETRIC")) return .geometric;
    if (distIs(s, "NEGBINOMIAL")) return .negbinomial;
    if (distIs(s, "HYPERGEOMETRIC")) return .hypergeometric;
    if (distIs(s, "LAPLACE")) return .laplace;
    if (distIs(s, "PARETO")) return .pareto;
    return null;
}

/// Distribution parameter `i` (0-based, after dist+quantile) or a default —
/// local twin of functions.zig's private distParam.
fn xpar(args: []const Value, i: usize, default: f64) f64 {
    return if (args.len > 2 + i) toNum(args[2 + i]) else default;
}

/// log C(a,b), −inf when b∉[0,a].
fn logC(a: f64, b: f64) f64 {
    if (b < 0 or b > a) return -std.math.inf(f64);
    return lgammaOf(a + 1) - lgammaOf(b + 1) - lgammaOf(a - b + 1);
}

/// Bad parameter VALUE on a recognized dist → SAS NOTE + missing (domErr's
/// message, ?f64-flavored for the ext* helpers).
fn domNull(ev: *eval.Evaluator, fname: []const u8) ?f64 {
    note(ev, "{s}: argument out of domain (result set to missing)", .{fname});
    return null;
}

/// Unknown distribution name → loud ERROR (D-002) + missing. Was: silent
/// missing — the silent-wrong class this task kills.
fn unknownDist(ev: *eval.Evaluator, fname: []const u8, dname: []const u8) Value {
    ev.diags.report(.err, 0, "{s}: distribution '{s}' is not supported", .{ fname, std.mem.trim(u8, dname, " ") }) catch {};
    return Value.missing;
}

/// distCdf + the optional noncentrality parm SAS documents for CHISQUARE/F/T
/// (CDF('T',t,df<,nc>) …) and PROBCHI/PROBF/PROBT already accept — wired to the
/// same noncentral routines (distCdf itself is central-only).
/// `anytype`: functions.zig's Dist enum is file-private, can't be named here;
/// the enum literals still check against it.
fn cdfNc(ev: *eval.Evaluator, fname: []const u8, d: anytype, x: f64, args: []const Value) ?f64 {
    if (args.len > 3 and (d == .chisq or d == .t)) {
        const df = toNum(args[2]);
        const nc = toNum(args[3]);
        if (isMiss(df) or isMiss(nc)) return null;
        if (df <= 0 or (d == .chisq and nc < 0)) return domNull(ev, fname);
        return if (d == .chisq) noncentralChisqCdf(x, df, nc) else noncentralTCdf(x, df, nc);
    }
    if (args.len > 4 and d == .f) {
        const ndf = toNum(args[2]);
        const ddf = toNum(args[3]);
        const nc = toNum(args[4]);
        if (isMiss(ndf) or isMiss(ddf) or isMiss(nc)) return null;
        if (ndf <= 0 or ddf <= 0 or nc < 0) return domNull(ev, fname);
        if (x <= 0) return 0;
        return noncentralFCdf(x, ndf, ddf, nc);
    }
    return distCdf(d, x, args);
}

/// CDF at `x` of an extended dist; parms in args[2..]. null = missing input or
/// domain error (NOTEd); NaN passes through (hyperCdf's term cap → missing).
fn extCdf(ev: *eval.Evaluator, fname: []const u8, ed: ExtDist, x: f64, args: []const Value) ?f64 {
    switch (ed) {
        .weibull => { // 1 − e^(−(x/λ)ᵃ), x≥0; SAS: CDF('WEIBULL',x,a<,λ=1>)
            const a = xpar(args, 0, std.math.nan(f64));
            const lam = xpar(args, 1, 1);
            if (isMiss(a) or isMiss(lam)) return null;
            if (a <= 0 or lam <= 0) return domNull(ev, fname);
            return if (x < 0) 0 else 1.0 - @exp(-std.math.pow(f64, x / lam, a));
        },
        .geometric => { // failures before 1st success: 1 − (1−p)^(⌊m⌋+1)
            const p = xpar(args, 0, std.math.nan(f64));
            if (isMiss(p)) return null;
            if (p < 0 or p > 1) return domNull(ev, fname);
            if (x < 0) return 0;
            return 1.0 - std.math.pow(f64, 1.0 - p, @floor(x) + 1.0);
        },
        .negbinomial => { // failures before n-th success: I_p(n, ⌊m⌋+1) (PROBNEGB)
            const p = xpar(args, 0, std.math.nan(f64));
            const n = xpar(args, 1, std.math.nan(f64));
            if (isMiss(p) or isMiss(n)) return null;
            if (p < 0 or p > 1 or n <= 0) return domNull(ev, fname);
            if (x < 0) return 0;
            return betaI(p, n, @floor(x) + 1.0);
        },
        .hypergeometric => { // CDF('HYPER',x,N,R,n): P(X≤x), central (odds ratio 1)
            const bigN = xpar(args, 0, std.math.nan(f64));
            const bigR = xpar(args, 1, std.math.nan(f64));
            const n = xpar(args, 2, std.math.nan(f64));
            if (isMiss(bigN) or isMiss(bigR) or isMiss(n)) return null;
            if (bigN < 1 or bigR < 0 or bigR > bigN or n < 1 or n > bigN) return domNull(ev, fname);
            return hyperCdf(bigN, bigR, n, @floor(x));
        },
        .laplace => { // x<θ: ½·e^((x−θ)/λ); x≥θ: 1−½·e^(−(x−θ)/λ); CDF('LAPLACE',x<,θ=0,λ=1>)
            const th = xpar(args, 0, 0);
            const lam = xpar(args, 1, 1);
            if (isMiss(th) or isMiss(lam)) return null;
            if (lam <= 0) return domNull(ev, fname);
            const z = (x - th) / lam;
            return if (z < 0) 0.5 * @exp(z) else 1.0 - 0.5 * @exp(-z);
        },
        .pareto => { // 1 − (k/x)ᵃ, x ≥ k; SAS: CDF('PARETO',x,a<,k=1>)
            const a = xpar(args, 0, std.math.nan(f64));
            const k = xpar(args, 1, 1);
            if (isMiss(a) or isMiss(k)) return null;
            if (a <= 0 or k <= 0) return domNull(ev, fname);
            return if (x < k) 0 else 1.0 - std.math.pow(f64, k / x, a);
        },
    }
}

/// PDF/PMF at `x` of an extended dist. Discrete PMFs are 0 off the integers.
fn extPdf(ev: *eval.Evaluator, fname: []const u8, ed: ExtDist, x: f64, args: []const Value) ?f64 {
    switch (ed) {
        .weibull => { // (a/λ)(x/λ)ᵃ⁻¹·e^(−(x/λ)ᵃ), x≥0
            const a = xpar(args, 0, std.math.nan(f64));
            const lam = xpar(args, 1, 1);
            if (isMiss(a) or isMiss(lam)) return null;
            if (a <= 0 or lam <= 0) return domNull(ev, fname);
            if (x < 0) return 0;
            return (a / lam) * std.math.pow(f64, x / lam, a - 1) * @exp(-std.math.pow(f64, x / lam, a));
        },
        .geometric => { // P(X=m) = p(1−p)ᵐ, integer m≥0
            const p = xpar(args, 0, std.math.nan(f64));
            if (isMiss(p)) return null;
            if (p < 0 or p > 1) return domNull(ev, fname);
            const k = @round(x);
            if (k < 0 or k != x) return 0;
            return p * std.math.pow(f64, 1.0 - p, k);
        },
        .negbinomial => { // P(X=k) = C(n+k−1,k)·pⁿ(1−p)ᵏ, integer k≥0
            const p = xpar(args, 0, std.math.nan(f64));
            const n = xpar(args, 1, std.math.nan(f64));
            if (isMiss(p) or isMiss(n)) return null;
            if (p < 0 or p > 1 or n <= 0) return domNull(ev, fname);
            const k = @round(x);
            if (k < 0 or k != x) return 0;
            if (p == 1) return if (k == 0) 1 else 0; // 0·log(0) NaN guard
            return @exp(lgammaOf(n + k) - lgammaOf(n) - lgammaOf(k + 1) + n * @log(p) + k * @log(1.0 - p));
        },
        .hypergeometric => { // C(R,x)C(N−R,n−x)/C(N,n) on its support, else 0
            const bigN = xpar(args, 0, std.math.nan(f64));
            const bigR = xpar(args, 1, std.math.nan(f64));
            const n = xpar(args, 2, std.math.nan(f64));
            if (isMiss(bigN) or isMiss(bigR) or isMiss(n)) return null;
            if (bigN < 1 or bigR < 0 or bigR > bigN or n < 1 or n > bigN) return domNull(ev, fname);
            const k = @round(x);
            if (k != x) return 0;
            const lo = @max(0, n - (bigN - bigR));
            const hi = @min(bigR, n);
            if (k < lo or k > hi) return 0;
            return @exp(logC(bigR, k) + logC(bigN - bigR, n - k) - logC(bigN, n));
        },
        .laplace => { // e^(−|x−θ|/λ) / (2λ)
            const th = xpar(args, 0, 0);
            const lam = xpar(args, 1, 1);
            if (isMiss(th) or isMiss(lam)) return null;
            if (lam <= 0) return domNull(ev, fname);
            return @exp(-@abs(x - th) / lam) / (2.0 * lam);
        },
        .pareto => { // a·kᵃ/x^(a+1) = (a/x)(k/x)ᵃ, x ≥ k
            const a = xpar(args, 0, std.math.nan(f64));
            const k = xpar(args, 1, 1);
            if (isMiss(a) or isMiss(k)) return null;
            if (a <= 0 or k <= 0) return domNull(ev, fname);
            return if (x < k) 0 else (a / x) * std.math.pow(f64, k / x, a);
        },
    }
}

/// log of the PDF/PMF of an extended dist at `x` — the @exp argument of extPdf's
/// formulas. −inf outside the support (→ missing, like log(0) before). Called
/// only after extPdf returned a validated-params value that under/overflowed.
fn extLogPdf(ed: ExtDist, x: f64, args: []const Value) f64 {
    const ninf = -std.math.inf(f64);
    switch (ed) {
        .weibull => { // log(a/λ) + (a−1)log(x/λ) − (x/λ)ᵃ
            const a = xpar(args, 0, std.math.nan(f64));
            const lam = xpar(args, 1, 1);
            if (x < 0) return ninf;
            return @log(a / lam) + (a - 1) * @log(x / lam) - std.math.pow(f64, x / lam, a);
        },
        .geometric => { // log p + k·log(1−p)
            const p = xpar(args, 0, std.math.nan(f64));
            const k = @round(x);
            if (k < 0 or k != x) return ninf;
            return @log(p) + k * @log(1.0 - p);
        },
        .negbinomial => { // log C(n+k−1,k) + n·log p + k·log(1−p)
            const p = xpar(args, 0, std.math.nan(f64));
            const n = xpar(args, 1, std.math.nan(f64));
            const k = @round(x);
            if (k < 0 or k != x) return ninf;
            if (p == 1) return if (k == 0) 0 else ninf; // mirror extPdf's guard
            return lgammaOf(n + k) - lgammaOf(n) - lgammaOf(k + 1) + n * @log(p) + k * @log(1.0 - p);
        },
        .hypergeometric => { // logC(R,k) + logC(N−R,n−k) − logC(N,n)
            const bigN = xpar(args, 0, std.math.nan(f64));
            const bigR = xpar(args, 1, std.math.nan(f64));
            const n = xpar(args, 2, std.math.nan(f64));
            const k = @round(x);
            if (k != x) return ninf;
            const lo = @max(0, n - (bigN - bigR));
            const hi = @min(bigR, n);
            if (k < lo or k > hi) return ninf;
            return logC(bigR, k) + logC(bigN - bigR, n - k) - logC(bigN, n);
        },
        .laplace => { // −|x−θ|/λ − log(2λ)
            const th = xpar(args, 0, 0);
            const lam = xpar(args, 1, 1);
            return -@abs(x - th) / lam - @log(2.0 * lam);
        },
        .pareto => { // log a − log x + a·log(k/x)
            const a = xpar(args, 0, std.math.nan(f64));
            const k = xpar(args, 1, 1);
            if (x < k) return ninf;
            return @log(a) - @log(x) + a * @log(k / x);
        },
    }
}

/// log of the CDF (right=false) or SDF (right=true) of an extended dist, in
/// log-space — called only when the direct tail underflowed to exactly 0, so
/// the tail is always deep (see distLogCdfSdf). null = no log-space form →
/// missing, unchanged (ponytail: negbinomial/hypergeometric tails ride betaI/
/// hyperCdf sums — log-space versions only when a study hits them).
fn extLogCdfSdf(ed: ExtDist, x: f64, args: []const Value, right: bool) ?f64 {
    const ninf = -std.math.inf(f64);
    switch (ed) {
        .weibull => { // sdf = e^{−t}, cdf = 1−e^{−t}, t = (x/λ)ᵃ
            const a = xpar(args, 0, std.math.nan(f64));
            const lam = xpar(args, 1, 1);
            if (x < 0) return ninf;
            // right trigger ⇒ t underflowed e^{−t}; left trigger ⇒ t ≲ 1e-16,
            // where log(1−e^{−t}) = log t to 5e-17
            return if (right) -std.math.pow(f64, x / lam, a) else a * @log(x / lam);
        },
        .geometric => { // sdf = (1−p)^k, cdf = 1−(1−p)^k, k = ⌊x⌋+1
            const p = xpar(args, 0, std.math.nan(f64));
            if (x < 0) return ninf;
            const u = (@floor(x) + 1.0) * @log(1.0 - p); // = log(sdf)
            return if (right) u else @log(-u); // left trigger ⇒ u ≈ 0⁻, 1−e^u ≈ −u
        },
        .laplace => { // x<θ: logcdf = z−ln2; x≥θ: logsdf = −z−ln2
            const th = xpar(args, 0, 0);
            const lam = xpar(args, 1, 1);
            const z = (x - th) / lam;
            return if (right) -z - @log(2.0) else z - @log(2.0);
        },
        .pareto => { // sdf = (k/x)ᵃ, cdf = 1−(k/x)ᵃ
            const a = xpar(args, 0, std.math.nan(f64));
            const k = xpar(args, 1, 1);
            if (x < k) return ninf;
            const u = a * @log(k / x); // = log(sdf)
            return if (right) u else @log(-u); // left trigger ⇒ (k/x)ᵃ rounded to 1
        },
        else => return null,
    }
}

/// Quantile at probability `p`∈(0,1) of an extended dist. Discrete: smallest
/// support point whose CDF ≥ p (SAS QUANTILE definition).
fn extQuantile(ev: *eval.Evaluator, fname: []const u8, ed: ExtDist, p: f64, args: []const Value) ?f64 {
    switch (ed) {
        .weibull => { // λ(−ln(1−p))^(1/a)
            const a = xpar(args, 0, std.math.nan(f64));
            const lam = xpar(args, 1, 1);
            if (isMiss(a) or isMiss(lam)) return null;
            if (a <= 0 or lam <= 0) return domNull(ev, fname);
            return lam * std.math.pow(f64, -@log(1.0 - p), 1.0 / a);
        },
        .geometric => { // closed form ⌈ln(1−p)/ln(1−ps)⌉−1, FP-adjusted
            const ps = xpar(args, 0, std.math.nan(f64));
            if (isMiss(ps)) return null;
            if (ps <= 0 or ps > 1) return domNull(ev, fname);
            // 1e-12 slack: F values land a few ulps off exact ties (betaI/pow),
            // and a discrete quantile AT an exact CDF value must still pick it.
            var m = @max(0, @ceil(@log(1.0 - p) / @log(1.0 - ps)) - 1.0);
            while (m > 0 and 1.0 - std.math.pow(f64, 1.0 - ps, m) >= p - 1e-12) m -= 1;
            while (1.0 - std.math.pow(f64, 1.0 - ps, m + 1.0) < p - 1e-12) m += 1;
            return m;
        },
        .negbinomial => { // smallest m with F(m) = I_p(n,m+1) ≥ p, integer bisect
            const ps = xpar(args, 0, std.math.nan(f64));
            const n = xpar(args, 1, std.math.nan(f64));
            if (isMiss(ps) or isMiss(n)) return null;
            if (ps <= 0 or ps > 1 or n <= 0) return domNull(ev, fname);
            if (betaI(ps, n, 1) >= p - 1e-12) return 0;
            var lo: f64 = 0; // invariant: F(lo) < p
            var hi: f64 = @max(1, 4.0 * n * (1.0 - ps) / ps); // mean-based first guess
            while (betaI(ps, n, hi + 1.0) < p - 1e-12) {
                lo = hi;
                hi *= 2;
                if (hi > 1e12) return domNull(ev, fname); // degenerate parms
            }
            while (hi - lo > 1) {
                const mid = @floor((lo + hi) / 2.0);
                if (betaI(ps, n, mid + 1.0) >= p - 1e-12) hi = mid else lo = mid;
            }
            return hi;
        },
        .hypergeometric => { // smallest x∈[lo,hi] with P(X≤x) ≥ p, integer bisect
            const bigN = xpar(args, 0, std.math.nan(f64));
            const bigR = xpar(args, 1, std.math.nan(f64));
            const n = xpar(args, 2, std.math.nan(f64));
            if (isMiss(bigN) or isMiss(bigR) or isMiss(n)) return null;
            if (bigN < 1 or bigR < 0 or bigR > bigN or n < 1 or n > bigN) return domNull(ev, fname);
            const lo = @max(0, n - (bigN - bigR));
            const hi = @min(bigR, n);
            if (hyperCdf(bigN, bigR, n, lo) >= p - 1e-12) return lo;
            if (hyperCdf(bigN, bigR, n, hi) < p - 1e-12) return null; // NaN term-cap → missing
            var a = lo;
            var b = hi;
            while (b - a > 1) {
                const mid = @floor((a + b) / 2.0);
                if (hyperCdf(bigN, bigR, n, mid) >= p - 1e-12) b = mid else a = mid;
            }
            return b;
        },
        .laplace => { // θ+λ·ln(2p) for p<½; θ−λ·ln(2(1−p)) for p≥½
            const th = xpar(args, 0, 0);
            const lam = xpar(args, 1, 1);
            if (isMiss(th) or isMiss(lam)) return null;
            if (lam <= 0) return domNull(ev, fname);
            return if (p < 0.5) th + lam * @log(2.0 * p) else th - lam * @log(2.0 * (1.0 - p));
        },
        .pareto => { // k·(1−p)^(−1/a)
            const a = xpar(args, 0, std.math.nan(f64));
            const k = xpar(args, 1, 1);
            if (isMiss(a) or isMiss(k)) return null;
            if (a <= 0 or k <= 0) return domNull(ev, fname);
            return k * std.math.pow(f64, 1.0 - p, -1.0 / a);
        },
    }
}

// ── tests ────────────────────────────────────────────────────────────────

const t = std.testing;
const pdv_mod = @import("pdv.zig");
const diag = @import("diag.zig");

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

fn numV(x: f64) Value {
    return .{ .num = x };
}
fn strV(v: []const u8) Value {
    return .{ .str = v };
}

test "GAP-distsilentmiss: WEIBULL/GEOMETRIC/NEGBINOMIAL/HYPERGEOMETRIC CDF+PDF+QUANTILE match the doc formulas" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // WEIBULL(a=2, λ=3): F(1.5) = 1−e^(−0.5²); pdf; q(0.5) = 3√ln2 (doc p.502)
    try t.expectApproxEqAbs(0.22119921692859512, (try dispatch(&e, "cdf", &.{ strV("WEIBULL"), numV(1.5), numV(2), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.25960026102379705, (try dispatch(&e, "pdf", &.{ strV("WEIBULL"), numV(1.5), numV(2), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(2.497663833473093, (try dispatch(&e, "quantile", &.{ strV("WEIBULL"), numV(0.5), numV(2), numV(3) })).?.num, 1e-12);
    // doc example: cdf('WEIBULL',1,2) = 0.63212 (λ defaults to 1)
    try t.expectApproxEqAbs(0.6321205588285577, (try dispatch(&e, "cdf", &.{ strV("WEIBULL"), numV(1), numV(2) })).?.num, 1e-12);

    // GAP-quantiledists — LAPLACE(θ=0, λ=1): F(−1)=e⁻¹/2, f(2)=e⁻²/2,
    // q(0.9)=−ln(0.2); location/scale: F(8;2,3)=1−e⁻²/2, q roundtrips.
    try t.expectApproxEqAbs(0.18393972058572117, (try dispatch(&e, "cdf", &.{ strV("LAPLACE"), numV(-1) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.8160602794142788, (try dispatch(&e, "cdf", &.{ strV("LAPLACE"), numV(1) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.5, (try dispatch(&e, "pdf", &.{ strV("LAPLACE"), numV(0) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.06766764161830635, (try dispatch(&e, "pdf", &.{ strV("LAPLACE"), numV(2) })).?.num, 1e-12);
    try t.expectApproxEqAbs(1.6094379124341003, (try dispatch(&e, "quantile", &.{ strV("LAPLACE"), numV(0.9) })).?.num, 1e-12);
    try t.expectApproxEqAbs(-1.6094379124341003, (try dispatch(&e, "quantile", &.{ strV("LAPLACE"), numV(0.1) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.9323323583816937, (try dispatch(&e, "cdf", &.{ strV("LAPLACE"), numV(8), numV(2), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(2, (try dispatch(&e, "quantile", &.{ strV("LAPLACE"), numV(0.5), numV(2), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(8, (try dispatch(&e, "quantile", &.{ strV("LAPLACE"), numV(0.9323323583816937), numV(2), numV(3) })).?.num, 1e-9);
    // PARETO(a=2, k=1): F(2)=3/4, f(2)=1/4, q(3/4)=2; (a=3, k=2): F(4)=7/8, q roundtrips.
    try t.expectApproxEqAbs(0.75, (try dispatch(&e, "cdf", &.{ strV("PARETO"), numV(2), numV(2) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.25, (try dispatch(&e, "pdf", &.{ strV("PARETO"), numV(2), numV(2) })).?.num, 1e-12);
    try t.expectApproxEqAbs(2, (try dispatch(&e, "quantile", &.{ strV("PARETO"), numV(0.75), numV(2) })).?.num, 1e-12);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "cdf", &.{ strV("PARETO"), numV(0.5), numV(2) })).?.num); // x < k
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "pdf", &.{ strV("PARETO"), numV(0.5), numV(2) })).?.num);
    try t.expectApproxEqAbs(0.875, (try dispatch(&e, "cdf", &.{ strV("PARETO"), numV(4), numV(3), numV(2) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.09375, (try dispatch(&e, "pdf", &.{ strV("PARETO"), numV(4), numV(3), numV(2) })).?.num, 1e-12);
    try t.expectApproxEqAbs(4, (try dispatch(&e, "quantile", &.{ strV("PARETO"), numV(0.875), numV(3), numV(2) })).?.num, 1e-12);
    // degenerate parms → missing (NOTE), unknown dists still fail loud
    try t.expect((try dispatch(&e, "cdf", &.{ strV("PARETO"), numV(2), numV(0) })).?.isMissing());
    try t.expect((try dispatch(&e, "pdf", &.{ strV("LAPLACE"), numV(1), numV(0), numV(0) })).?.isMissing());
    try t.expect((try dispatch(&e, "quantile", &.{ strV("LAPLACE"), numV(0.5), numV(0), numV(-1) })).?.isMissing());
    try t.expect((try dispatch(&e, "cdf", &.{ strV("NORMALMIX"), numV(1) })).?.isMissing());
    try t.expect((try dispatch(&e, "cdf", &.{ strV("TWEEDIE"), numV(1), numV(1.5) })).?.isMissing());

    // GEOMETRIC(p=0.25): F(3) = 1−0.75⁴; P(X=3) = 0.25·0.75³; q(0.9) = 8 (doc p.485)
    try t.expectApproxEqAbs(0.68359375, (try dispatch(&e, "cdf", &.{ strV("GEOMETRIC"), numV(3), numV(0.25) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.10546875, (try dispatch(&e, "pdf", &.{ strV("GEOMETRIC"), numV(3), numV(0.25) })).?.num, 1e-12);
    try t.expectEqual(@as(f64, 8), (try dispatch(&e, "quantile", &.{ strV("GEOMETRIC"), numV(0.9), numV(0.25) })).?.num);

    // NEGBINOMIAL: doc example cdf('NEGB',1,.5,2) = 0.5; F(2)=0.5, P(X=2)=0.1875, q(0.5)=2 (n=3, p=0.5)
    try t.expectApproxEqAbs(0.5, (try dispatch(&e, "cdf", &.{ strV("NEGB"), numV(1), numV(0.5), numV(2) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.5, (try dispatch(&e, "cdf", &.{ strV("NEGBINOMIAL"), numV(2), numV(0.5), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.1875, (try dispatch(&e, "pdf", &.{ strV("NEGBINOMIAL"), numV(2), numV(0.5), numV(3) })).?.num, 1e-12);
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "quantile", &.{ strV("NEGBINOMIAL"), numV(0.5), numV(0.5), numV(3) })).?.num);

    // HYPERGEOMETRIC(N=10, R=4, n=3): F(1) = 80/120, P(X=1) = 60/120, q(0.5) = 1
    try t.expectApproxEqAbs(2.0 / 3.0, (try dispatch(&e, "cdf", &.{ strV("HYPERGEOMETRIC"), numV(1), numV(10), numV(4), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(0.5, (try dispatch(&e, "pdf", &.{ strV("HYPERGEOMETRIC"), numV(1), numV(10), numV(4), numV(3) })).?.num, 1e-12);
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "quantile", &.{ strV("HYPERGEOMETRIC"), numV(0.5), numV(10), numV(4), numV(3) })).?.num);
    // doc example: cdf('HYPER',2,200,50,10) = 0.52367 (doc p.486)
    try t.expectApproxEqAbs(0.52367, (try dispatch(&e, "cdf", &.{ strV("HYPER"), numV(2), numV(200), numV(50), numV(10) })).?.num, 1e-5);
}

test "BUG-quantilediscrete: POISSON/BINOMIAL QUANTILE/SQUANTILE return the integer quantile (doc-finder tick140)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SAS 9.4: quantile('POISSON',0.857,2)=3, quantile('BINOMIAL',0.5,0.5,10)=5
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "quantile", &.{ strV("POISSON"), numV(0.857), numV(2) })).?.num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "quantile", &.{ strV("BINOMIAL"), numV(0.5), numV(0.5), numV(10) })).?.num);
    // SQUANTILE right-tail forms: 1−0.143=0.857
    try t.expectEqual(@as(f64, 3), (try dispatch(&e, "squantile", &.{ strV("POISSON"), numV(0.143), numV(2) })).?.num);
    try t.expectEqual(@as(f64, 5), (try dispatch(&e, "squantile", &.{ strV("BINOMIAL"), numV(0.5), numV(0.5), numV(10) })).?.num);
    // exact CDF tie still picks the tied value: F(0)=0.25 for BINOMIAL(0.5,2)
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "quantile", &.{ strV("BINOMIAL"), numV(0.25), numV(0.5), numV(2) })).?.num);
    // roundtrip sanity: q(F(k)) = k for a mid-support Poisson point
    try t.expectEqual(@as(f64, 2), (try dispatch(&e, "quantile", &.{ strV("POISSON"), numV(0.6766764161830635), numV(2) })).?.num);
}

test "BUG-invquantp1: CINV/FINV/GAMINV reject p>=1 (missing, like QUANTILE) — interior unchanged" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // p==1 out of domain → missing, matching opensas's own QUANTILE path
    // (was a bogus finite quantile from running the solver to its upper bound).
    try t.expect((try dispatch(&e, "cinv", &.{ numV(1), numV(10) })).?.isMissing());
    try t.expect((try dispatch(&e, "finv", &.{ numV(1), numV(3), numV(10) })).?.isMissing());
    try t.expect((try dispatch(&e, "gaminv", &.{ numV(1), numV(2) })).?.isMissing());
    try t.expect((try dispatch(&e, "quantile", &.{ strV("CHISQ"), numV(1), numV(10) })).?.isMissing());
    // p==0 lower boundary stays 0 (SAS domain is 0<=p<1 for these)
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "cinv", &.{ numV(0), numV(10) })).?.num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "finv", &.{ numV(0), numV(3), numV(10) })).?.num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "gaminv", &.{ numV(0), numV(2) })).?.num);
    // interior quantiles UNCHANGED
    try t.expectApproxEqAbs(3.8414588206941236, (try dispatch(&e, "cinv", &.{ numV(0.95), numV(1) })).?.num, 1e-9);
    try t.expectApproxEqAbs(3.7082648190959834, (try dispatch(&e, "finv", &.{ numV(0.95), numV(3), numV(10) })).?.num, 1e-9);
    try t.expectApproxEqAbs(1.6783469900166605, (try dispatch(&e, "gaminv", &.{ numV(0.5), numV(2) })).?.num, 1e-9);
    try t.expectApproxEqAbs(2.2281388519649385, (try dispatch(&e, "tinv", &.{ numV(0.975), numV(10) })).?.num, 1e-9);
}

test "BUG-noncentralinverse: TINV/FINV/CINV honor nc (invert the noncentral CDF) — central unchanged" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // scipy reference values: nct/ncf/ncx2 .ppf — the inverse now solves the
    // same noncentral CDF the forward PROBT/PROBF/PROBCHI evaluate.
    try t.expectApproxEqAbs(4.357475178664401, (try dispatch(&e, "tinv", &.{ numV(0.95), numV(10), numV(2) })).?.num, 1e-6);
    try t.expectApproxEqAbs(5.952705641727215, (try dispatch(&e, "finv", &.{ numV(0.95), numV(3), numV(10), numV(2) })).?.num, 1e-6);
    try t.expectApproxEqAbs(21.805514828085343, (try dispatch(&e, "cinv", &.{ numV(0.95), numV(10), numV(2) })).?.num, 1e-6);
    // negative delta is legal for TINV: tinv(p,df,-d) = -tinv(1-p,df,d)
    try t.expectApproxEqAbs(-4.357475178664401, (try dispatch(&e, "tinv", &.{ numV(0.05), numV(10), numV(-2) })).?.num, 1e-6);
    // nc>0 shifts each quantile right of the central one (was byte-identical)
    try t.expect((try dispatch(&e, "tinv", &.{ numV(0.95), numV(10), numV(2) })).?.num > (try dispatch(&e, "tinv", &.{ numV(0.95), numV(10) })).?.num);
    try t.expect((try dispatch(&e, "cinv", &.{ numV(0.95), numV(10), numV(2) })).?.num > (try dispatch(&e, "cinv", &.{ numV(0.95), numV(10) })).?.num);
    // nc==0 (explicit or omitted) → the shared central path, byte-identical
    try t.expectEqual((try dispatch(&e, "tinv", &.{ numV(0.975), numV(10) })).?.num, (try dispatch(&e, "tinv", &.{ numV(0.975), numV(10), numV(0) })).?.num);
    try t.expectEqual((try dispatch(&e, "finv", &.{ numV(0.95), numV(3), numV(10) })).?.num, (try dispatch(&e, "finv", &.{ numV(0.95), numV(3), numV(10), numV(0) })).?.num);
    try t.expectEqual((try dispatch(&e, "cinv", &.{ numV(0.95), numV(10) })).?.num, (try dispatch(&e, "cinv", &.{ numV(0.95), numV(10), numV(0) })).?.num);
    // nc<0 out of domain for CINV/FINV; missing nc → missing (like PROB*)
    try t.expect((try dispatch(&e, "cinv", &.{ numV(0.95), numV(10), numV(-1) })).?.isMissing());
    try t.expect((try dispatch(&e, "finv", &.{ numV(0.95), numV(3), numV(10), numV(-1) })).?.isMissing());
    try t.expect((try dispatch(&e, "tinv", &.{ numV(0.95), numV(10), Value.missing })).?.isMissing());
    // round-trip through the forward noncentral CDF recovers p
    const q = (try dispatch(&e, "tinv", &.{ numV(0.9), numV(7), numV(1.5) })).?.num;
    try t.expectApproxEqAbs(0.9, (try dispatch(&e, "probt", &.{ numV(q), numV(7), numV(1.5) })).?.num, 1e-9);
}

test "BUG-betainvendpoint: BETAINV returns exact 0/1 at the endpoints — interior unchanged" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // beta support is [0,1]; endpoints are exact, not bisection artifacts
    try t.expectEqual(@as(f64, 1), (try dispatch(&e, "betainv", &.{ numV(1), numV(3), numV(4) })).?.num);
    try t.expectEqual(@as(f64, 0), (try dispatch(&e, "betainv", &.{ numV(0), numV(3), numV(4) })).?.num);
    // interior UNCHANGED
    try t.expectApproxEqAbs(0.4214071906968516, (try dispatch(&e, "betainv", &.{ numV(0.5), numV(3), numV(4) })).?.num, 1e-9);
}

test "GAP-distsilentmiss: CDF family honors the noncentrality parm (PROBCHI/PROBF/PROBT routines)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // with nc: identical to the PROB* noncentral paths
    try t.expectEqual((try dispatch(&e, "probchi", &.{ numV(7), numV(3), numV(2) })).?.num, (try dispatch(&e, "cdf", &.{ strV("CHISQUARE"), numV(7), numV(3), numV(2) })).?.num);
    try t.expectEqual((try dispatch(&e, "probf", &.{ numV(2.5), numV(3), numV(20), numV(4) })).?.num, (try dispatch(&e, "cdf", &.{ strV("F"), numV(2.5), numV(3), numV(20), numV(4) })).?.num);
    try t.expectEqual((try dispatch(&e, "probt", &.{ numV(1.5), numV(10), numV(1) })).?.num, (try dispatch(&e, "cdf", &.{ strV("T"), numV(1.5), numV(10), numV(1) })).?.num);
    // central path unchanged when nc absent
    try t.expectEqual((try dispatch(&e, "probchi", &.{ numV(7), numV(3) })).?.num, (try dispatch(&e, "cdf", &.{ strV("CHISQUARE"), numV(7), numV(3) })).?.num);
    // nc actually shifts the value (not silently ignored)
    const central = (try dispatch(&e, "cdf", &.{ strV("CHISQUARE"), numV(7), numV(3) })).?.num;
    const noncentral = (try dispatch(&e, "cdf", &.{ strV("CHISQUARE"), numV(7), numV(3), numV(2) })).?.num;
    try t.expect(noncentral < central);
}

test "GAP-distsilentmiss: unknown distribution fails LOUD (D-002), captured reporter (D-003)" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // SAS-supported but unimplemented (WALD) → ERROR + missing, not silent missing
    try t.expect((try dispatch(&e, "cdf", &.{ strV("WALD"), numV(1), numV(1), numV(2) })).?.isMissing());
    try t.expectEqual(@as(usize, 1), h.diags.count());
    try t.expectEqual(diag.Severity.err, h.diags.list.items[0].severity);
    try t.expect(std.mem.indexOf(u8, h.diags.list.items[0].message, "not supported") != null);

    // garbage name → same, on every family member + RAND
    _ = try dispatch(&e, "pdf", &.{ strV("NOSUCHDIST"), numV(1) });
    _ = try dispatch(&e, "quantile", &.{ strV("IGAUS"), numV(0.5) }); // 5-char IGAUSS prefix also unknown
    _ = try dispatch(&e, "rand", &.{strV("TABLE")});
    try t.expectEqual(@as(usize, 4), h.diags.count());
    for (h.diags.list.items) |d| try t.expectEqual(diag.Severity.err, d.severity);
    try t.expect(h.diags.hasErrors()); // non-zero exit wired via hasErrors
}

test "GAP-distsilentmiss: RAND WEIBULL/GEOMETRIC/NEGBINOMIAL/HYPERGEOMETRIC draws sane" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    var sw: f64 = 0;
    var sg: f64 = 0;
    var i: usize = 0;
    while (i < 5000) : (i += 1) {
        sw += (try dispatch(&e, "rand", &.{ strV("WEIBULL"), numV(2), numV(3) })).?.num;
        sg += (try dispatch(&e, "rand", &.{ strV("GEOMETRIC"), numV(0.25) })).?.num;
    }
    try t.expectApproxEqAbs(2.6587, sw / 5000.0, 0.1); // λ·Γ(1+1/a) = 3·Γ(1.5)
    try t.expectApproxEqAbs(3.0, sg / 5000.0, 0.25); // (1−p)/p

    const rn = (try dispatch(&e, "rand", &.{ strV("NEGBINOMIAL"), numV(0.5), numV(3) })).?.num;
    try t.expect(rn >= 0 and rn == @floor(rn));
    const rh = (try dispatch(&e, "rand", &.{ strV("HYPERGEOMETRIC"), numV(10), numV(4), numV(3) })).?.num;
    try t.expect(rh >= 0 and rh <= 3 and rh == @floor(rh));
}

test "BUG-devianceeps + BUG-logxdftail: DEVIANCE ε-clamps (doc pp.614-618) + LOGxDF tails computed in log-space" {
    var h = Harness{ .arena = std.heap.ArenaAllocator.init(t.allocator) };
    defer h.deinit();
    h.prime();
    var e = h.ev();

    // ── deviance ε-clamps: boundary args now FINITE (was missing via log(0)/÷0)
    // BERN p→ε: −2·ln(1e-12); also p=1e-13 < ε clamps up to the same ε
    try t.expectApproxEqAbs(55.262042231857096, (try dispatch(&e, "deviance", &.{ strV("BERN"), numV(1), numV(0) })).?.num, 1e-9);
    // y=0, p=1 → p clamped to 1−ε: −2·ln(1−(1−ε)) — f64 rounds 1−(1−1e-12) to
    // 9.99978e-13, so this is NOT exactly −2·ln(ε) (IEEE-double-faithful, as SAS).
    try t.expectApproxEqAbs(55.26208647578672, (try dispatch(&e, "deviance", &.{ strV("BERN"), numV(0), numV(1) })).?.num, 1e-9);
    try t.expectApproxEqAbs(55.262042231857096, (try dispatch(&e, "deviance", &.{ strV("BERN"), numV(1), numV(1e-13) })).?.num, 1e-9);
    // BINO μ→nε: 2·(10·ln(10/1e-11)+0) = 20·ln(1e12)
    try t.expectApproxEqAbs(552.620422318571, (try dispatch(&e, "deviance", &.{ strV("BINO"), numV(10), numV(0), numV(10) })).?.num, 1e-6);
    // GAMMA y→ε: 2·((ε−5)/5 − ln(ε/5)) = 2·(ln(5e12)−1)
    try t.expectApproxEqAbs(56.48091805672569, (try dispatch(&e, "deviance", &.{ strV("GAMMA"), numV(0), numV(5) })).?.num, 1e-9);
    // POISSON μ→ε: 2·(3·ln(3/ε) − (3−ε))
    try t.expectApproxEqAbs(166.37780042758195, (try dispatch(&e, "deviance", &.{ strV("POISSON"), numV(3), numV(0) })).?.num, 1e-6);
    // IGAUSS y→ε: (ε−2)²/(4ε)
    try t.expectApproxEqAbs(999999999998.9999, (try dispatch(&e, "deviance", &.{ strV("IGAUSS"), numV(0), numV(2) })).?.num, 1e-1);
    // ε itself clamped to [1e-12, 0.01]: ε=5 → 0.01 → −2·ln(0.01)
    try t.expectApproxEqAbs(9.210340371976182, (try dispatch(&e, "deviance", &.{ strV("BERN"), numV(1), numV(0), numV(5) })).?.num, 1e-12);
    // explicit ε honored: −2·ln(1e-9)
    try t.expectApproxEqAbs(41.44653167389282, (try dispatch(&e, "deviance", &.{ strV("BERN"), numV(1), numV(0), numV(1e-9) })).?.num, 1e-12);
    // NORMAL ignores ε; in-range values unchanged
    try t.expectApproxEqAbs(4, (try dispatch(&e, "deviance", &.{ strV("NORMAL"), numV(5), numV(3) })).?.num, 1e-12);
    try t.expectApproxEqAbs(2 * (2 * @log(2.0) - 1), (try dispatch(&e, "deviance", &.{ strV("POISSON"), numV(2), numV(1) })).?.num, 1e-12);
    try t.expectApproxEqAbs(-2 * @log(0.25), (try dispatch(&e, "deviance", &.{ strV("BERN"), numV(1), numV(0.25) })).?.num, 1e-12);

    // ── LOGxDF deep tails: finite large-negative logs (was missing)
    // log Φ(−10) = −53.23128515051247 (mpmath); logsdf is the symmetric tail
    try t.expectApproxEqAbs(-53.23128515051247, (try dispatch(&e, "logcdf", &.{ strV("NORMAL"), numV(-10) })).?.num, 1e-10);
    try t.expectApproxEqAbs(-53.23128515051247, (try dispatch(&e, "logsdf", &.{ strV("NORMAL"), numV(10) })).?.num, 1e-10);
    try t.expectApproxEqAbs(-726.5572160188201, (try dispatch(&e, "logcdf", &.{ strV("NORMAL"), numV(-38) })).?.num, 1e-8);
    // logpdf normal 39 = −39²/2 − ½ln(2π)
    try t.expectApproxEqAbs(-761.4189385332047, (try dispatch(&e, "logpdf", &.{ strV("NORMAL"), numV(39) })).?.num, 1e-10);
    // closed-form ext tails: expo sdf = −x/λ; weibull sdf = −(x/λ)ᵃ; laplace cdf = z−ln2
    try t.expectApproxEqAbs(-800, (try dispatch(&e, "logsdf", &.{ strV("EXPONENTIAL"), numV(800) })).?.num, 1e-12);
    try t.expectApproxEqAbs(-1000, (try dispatch(&e, "logsdf", &.{ strV("WEIBULL"), numV(1000), numV(1) })).?.num, 1e-12);
    try t.expectApproxEqAbs(-800.6931471805599, (try dispatch(&e, "logcdf", &.{ strV("LAPLACE"), numV(-800) })).?.num, 1e-10);
    // pareto sdf = a·ln(k/x) = 2·ln(1e-200)
    try t.expectApproxEqAbs(-921.0340371976183, (try dispatch(&e, "logsdf", &.{ strV("PARETO"), numV(1e200), numV(2), numV(1) })).?.num, 1e-7);
    // mid-range LOGCDF/LOGPDF byte-identical to log of the direct value
    const c0 = (try dispatch(&e, "cdf", &.{ strV("NORMAL"), numV(0) })).?.num;
    try t.expectEqual(@as(f64, @log(c0)), (try dispatch(&e, "logcdf", &.{ strV("NORMAL"), numV(0) })).?.num);
    const p0 = (try dispatch(&e, "pdf", &.{ strV("NORMAL"), numV(0) })).?.num;
    try t.expectEqual(@as(f64, @log(p0)), (try dispatch(&e, "logpdf", &.{ strV("NORMAL"), numV(0) })).?.num);
    // outside the support still missing (log(0) = −inf)
    try t.expect((try dispatch(&e, "logcdf", &.{ strV("EXPONENTIAL"), numV(-1) })).?.isMissing());
    try t.expect((try dispatch(&e, "logpdf", &.{ strV("UNIFORM"), numV(5) })).?.isMissing());
}
