//! Date/time functions (calendar arithmetic, intervals, holidays, time zones),
//! split verbatim out of functions.zig dispatch (QL-A). Shared helpers stay in
//! functions.zig; `null` means "name not mine".
const std = @import("std");
const eval = @import("eval.zig");
const Value = @import("value.zig").Value;

const format = @import("format.zig");
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
const Align = fns.Align;
const holidays = fns.holidays;
const addMonthsCal = fns.addMonthsCal;
const civilFromSas = fns.civilFromSas;
const currentSasDate = fns.currentSasDate;
const currentSecondOfDay = fns.currentSecondOfDay;
const datdif = fns.datdif;
const dateField = fns.dateField;
const daysFromCivil = fns.daysFromCivil;
const daysInMonth = fns.daysInMonth;
const expandYear = fns.expandYear;
const clampI64 = fns.clampI64;
const floorI64 = fns.floorI64;
const haversineKm = fns.haversineKm;
const holidayDate = fns.holidayDate;
const intervalBetween = fns.intervalBetween;
const intnxAlign = fns.intnxAlign;
const mvalidCompat = fns.mvalidCompat;
const mvalidExtend = fns.mvalidExtend;
const parseInterval = fns.parseInterval;
const sasDate = fns.sasDate;
const timeGrow = fns.timeGrow;
const unknownInterval = fns.unknownInterval;
const validInterval = fns.validInterval;
const weekdayOf = fns.weekdayOf;
const yrdif = fns.yrdif;
const bucketOf = fns.bucketOf;
const fmtIvl = fns.fmtIvl;
const baseMonths = fns.baseMonths;
const baseSeasons = fns.baseSeasons;
const fmtBase = fns.fmtBase;
const fmtCat = fns.fmtCat;
const sas_epoch_days = fns.sas_epoch_days;

pub fn dispatch(ev: *eval.Evaluator, name: []const u8, args: []const Value) eval.Error!?Value {
    // ── holidays
    if (eqi(name, "holiday")) { // SAS date of a named holiday in `year`
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const yr = toInt(toNum(args[1])) orelse return Value.missing;
        const d = holidayDate(try toStr(ev, args[0]), yr) orelse return Value.missing;
        return numVal(@floatFromInt(d));
    }
    if (eqi(name, "holidaytest")) { // 1 if `date` is that holiday
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const dt = toInt(toNum(args[1])) orelse return Value.missing;
        const yr = civilFromSas(dt).y;
        const hd = holidayDate(try toStr(ev, args[0]), yr) orelse return numVal(0);
        return numVal(if (hd == dt) 1 else 0);
    }
    if (eqi(name, "holidayny")) { // nth occurrence in `year` (once-yearly → n=1 only)
        if (args.len < 2 or args.len > 4) return badArity(ev, name, "2 to 4", args.len);
        const yr = toInt(toNum(args[1])) orelse return Value.missing;
        const nth = if (args.len >= 3) toNum(args[2]) else 1;
        if (isMiss(nth) or nth != 1) return Value.missing; // our holidays occur once/year
        const d = holidayDate(try toStr(ev, args[0]), yr) orelse return Value.missing;
        return numVal(@floatFromInt(d));
    }

    if (eqi(name, "fmtinfo")) { // metadata about a format/informat (doc p.803)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        var buf: [40]u8 = undefined;
        const base = fmtBase(try toStr(ev, args[0]), &buf); // uppercased alpha base (keeps a leading $)
        if (base.len == 0) return .{ .str = "" };
        const info = try toStr(ev, args[1]);
        // CAT is modeled for the common formats; TYPE/DESC for BEST (the doc's example).
        if (eqi(info, "cat")) return .{ .str = fmtCat(base) orelse "" };
        if (eqi(info, "type")) return .{ .str = if (eqi(base, "BEST")) "BOTH" else "" };
        if (eqi(info, "desc")) return .{ .str = if (eqi(base, "BEST")) "SAS System chooses best notation" else "" };
        return .{ .str = "" }; // MIND/MAXD/DEFD/MINW/MAXW/DEFW not modeled
    }

    // ── interval validity and geodetic distance
    if (eqi(name, "inttest")) { // 1 if a valid time interval name
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return numVal(if (validInterval(try toStr(ev, args[0]))) 1 else 0);
    }
    if (eqi(name, "geodist")) { // great-circle distance (km default; M→miles, R→radians in)
        if (args.len < 4 or args.len > 5) return badArity(ev, name, "4 or 5", args.len);
        var la1 = toNum(args[0]);
        var lo1 = toNum(args[1]);
        var la2 = toNum(args[2]);
        var lo2 = toNum(args[3]);
        if (isMiss(la1) or isMiss(lo1) or isMiss(la2) or isMiss(lo2)) return Value.missing;
        const opts = if (args.len == 5) try toStr(ev, args[4]) else "";
        const radians = std.mem.indexOfAny(u8, opts, "Rr") != null;
        if (!radians) { // default D: convert degrees → radians
            const k = std.math.pi / 180.0;
            la1 *= k;
            lo1 *= k;
            la2 *= k;
            lo2 *= k;
        }
        const km = haversineKm(la1, lo1, la2, lo2);
        return numVal(if (std.mem.indexOfAny(u8, opts, "Mm") != null) km / 1.609344 else km);
    }

    // ── holiday occurrences of a specific named holiday within [date1, date2].
    // (HOLIDAYCOUNT — count of ALL holidays on a date — is NOT implemented: it needs
    // SAS's complete default holiday database, which our curated table doesn't match.)
    if (eqi(name, "holidayck")) {
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const d1 = toInt(toNum(args[1])) orelse return Value.missing;
        const d2 = toInt(toNum(args[2])) orelse return Value.missing;
        const hname = try toStr(ev, args[0]);
        // unrecognized holiday name → missing (honest), never a wrong 0
        if (holidayDate(hname, civilFromSas(d1).y) == null) return Value.missing;
        var count: f64 = 0;
        var yr = civilFromSas(d1).y;
        const yend = civilFromSas(d2).y;
        while (yr <= yend) : (yr += 1) {
            if (holidayDate(hname, yr)) |hd| if (hd >= d1 and hd <= d2) {
                count += 1;
            };
        }
        return numVal(count);
    }

    // ── interval metadata (verifiable subset: YEAR/SEMIYEAR/QTR/MONTH families)
    if (eqi(name, "intseas")) { // intervals per seasonal cycle
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        var buf: [32]u8 = undefined;
        const iv = parseInterval(try toStr(ev, args[0]), &buf);
        const seas = baseSeasons(iv.base) orelse return Value.missing;
        if (@mod(seas, iv.mult) != 0) return Value.missing; // multiplier must divide the cycle
        return numVal(@floatFromInt(@divTrunc(seas, iv.mult)));
    }
    if (eqi(name, "intcycle")) { // interval spanning the next-higher seasonal cycle
        if (args.len < 1) return badArity(ev, name, "1 or more", args.len);
        var buf: [32]u8 = undefined;
        const iv = parseInterval(try toStr(ev, args[0]), &buf);
        // the sub-year date intervals cycle within a YEAR
        if (baseSeasons(iv.base)) |s| if (s > 1) return .{ .str = "YEAR" };
        return Value.missing;
    }
    if (eqi(name, "intshift")) { // the shift interval of a base interval (doc p.1104)
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const spec = std.mem.trim(u8, try toStr(ev, args[0]), " ");
        if (!validInterval(spec)) return .{ .str = "" };
        const has_dt = std.ascii.startsWithIgnoreCase(spec, "DT");
        var buf: [32]u8 = undefined;
        var base = parseInterval(spec, &buf).base; // uppercased; DT/multiplier/shift stripped
        if (std.mem.startsWith(u8, base, "WEEKDAY")) base = "WEEKDAY"; // WEEKDAYnW head
        // YEAR/SEMIYEAR/QTR shift by MONTH; every other interval shifts by itself.
        const shift = if (eqi(base, "YEAR") or eqi(base, "SEMIYEAR") or eqi(base, "QTR")) "MONTH" else base;
        // datetime intervals — input `DT…`, or the inherently-datetime time units — are DT-prefixed
        const dt = has_dt or eqi(base, "HOUR") or eqi(base, "MINUTE") or eqi(base, "SECOND");
        return .{ .str = if (dt) try std.fmt.allocPrint(ev.arena, "DT{s}", .{shift}) else try ev.arena.dupe(u8, shift) };
    }
    if (eqi(name, "intnest")) { // 1 if interval1 nests within interval2 (whole multiple)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        var b1: [32]u8 = undefined;
        var b2: [32]u8 = undefined;
        const iv1 = parseInterval(try toStr(ev, args[0]), &b1);
        const iv2 = parseInterval(try toStr(ev, args[1]), &b2);
        const raw1 = baseSeasons(iv1.base) orelse return Value.missing;
        const raw2 = baseSeasons(iv2.base) orelse return Value.missing;
        if (@mod(raw1, iv1.mult) != 0 or @mod(raw2, iv2.mult) != 0) return Value.missing;
        const s1 = @divTrunc(raw1, iv1.mult); // effective intervals per year
        const s2 = @divTrunc(raw2, iv2.mult);
        return numVal(if (s2 != 0 and @mod(s1, s2) == 0) 1 else 0); // finer nests in coarser
    }
    if (eqi(name, "intfit")) { // the interval between two dates (as an interval string)
        if (args.len < 2 or args.len > 3) return badArity(ev, name, "2 or 3", args.len);
        const d1 = toInt(toNum(args[0])) orelse return Value.missing;
        const d2 = toInt(toNum(args[1])) orelse return Value.missing;
        if (d1 == d2) return Value.missing;
        const lo = @min(d1, d2);
        const hi = @max(d1, d2);
        return .{ .str = try fmtIvl(ev, intervalBetween(lo, hi)) };
    }
    if (eqi(name, "intget")) { // interval implied by three (roughly equally spaced) dates
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const d1 = toInt(toNum(args[0])) orelse return Value.missing;
        const d2 = toInt(toNum(args[1])) orelse return Value.missing;
        const d3 = toInt(toNum(args[2])) orelse return Value.missing;
        if (d1 == d2 or d2 == d3) return Value.missing;
        const iva = intervalBetween(d1, d2);
        const ivb = intervalBetween(d2, d3);
        // same base and one multiple divides the other → the smaller interval; else missing
        if (!eqi(iva.base, ivb.base)) return Value.missing;
        const a = iva.mult;
        const b = ivb.mult;
        if (a != 0 and @rem(b, a) == 0) return .{ .str = try fmtIvl(ev, iva) };
        if (b != 0 and @rem(a, b) == 0) return .{ .str = try fmtIvl(ev, ivb) };
        return Value.missing;
    }
    if (eqi(name, "intcindex")) { // CYCLE index: the season's position within the larger cycle
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        var buf: [32]u8 = undefined;
        const iv = parseInterval(try toStr(ev, args[0]), &buf);
        const dt = toInt(toNum(args[1])) orelse return Value.missing;
        const c = civilFromSas(dt);
        // ponytail: time intervals (HOUR/MINUTE/SECOND → hour of day) not modeled,
        // as with INTINDEX; date intervals cycle within the YEAR.
        if (eqi(iv.base, "MONTH") or eqi(iv.base, "QTR") or eqi(iv.base, "SEMIYEAR")) {
            const idx: i64 = if (eqi(iv.base, "MONTH"))
                c.m // month of year (1-12)
            else if (eqi(iv.base, "QTR"))
                @divTrunc(c.m - 1, 3) + 1 // quarter (1-4)
            else
                if (c.m <= 6) 1 else 2;
            // BUG-intindexmult: fold into the multi-unit period — a multiplier n
            // groups n sub-intervals, so the index cycles 1..INTSEAS (same fold as
            // INTINDEX, with which this coincides at mult 1). ceil(idx/mult).
            return numVal(@floatFromInt(@divTrunc(idx - 1, iv.mult) + 1));
        }
        if (eqi(iv.base, "DAY") or eqi(iv.base, "WEEKDAY") or eqi(iv.base, "WEEK")) {
            // ponytail: week-cycle multiplier (WEEK2/DAY2) fold not SAS-verified —
            // honest missing, never a silently wrong number.
            if (iv.mult != 1) return Value.missing;
            // week of the year (SAS WEEK.1): weeks from the year's first week + 1.
            const ys = (try dispatch(ev, "intnx", &.{ .{ .str = "year" }, args[1], numVal(0) })).?;
            const wk = (try dispatch(ev, "intck", &.{ .{ .str = "week" }, ys, args[1] })).?;
            return numVal(toNum(wk) + 1);
        }
        return Value.missing;
    }
    if (eqi(name, "intindex")) { // seasonal index of a date within its cycle
        if (args.len < 2) return badArity(ev, name, "2 or more", args.len);
        var buf: [32]u8 = undefined;
        const iv = parseInterval(try toStr(ev, args[0]), &buf);
        const dt = toInt(toNum(args[1])) orelse return Value.missing;
        const c = civilFromSas(dt);
        // seasonal position within the interval's cycle. ponytail: time intervals
        // (HOUR/MINUTE/SECOND) not modeled.
        const idx: i64 = if (eqi(iv.base, "MONTH"))
            c.m // month of the year (1-12), cycle = YEAR
        else if (eqi(iv.base, "QTR"))
            @divTrunc(c.m - 1, 3) + 1 // quarter (1-4)
        else if (eqi(iv.base, "SEMIYEAR"))
            (if (c.m <= 6) @as(i64, 1) else 2)
        else if (eqi(iv.base, "YEAR"))
            1
        else if (eqi(iv.base, "SEMIMONTH"))
            (c.m - 1) * 2 + (if (c.d <= 15) @as(i64, 1) else 2) // 1-24
        else if (eqi(iv.base, "TENDAY"))
            (c.m - 1) * 3 + (if (c.d <= 10) @as(i64, 1) else if (c.d <= 20) @as(i64, 2) else 3) // 1-36
        else if (eqi(iv.base, "DAY") or eqi(iv.base, "WEEKDAY")) blk: {
            // ponytail: week-cycle multiplier (DAY2) fold not SAS-verified —
            // honest missing, never a silently wrong number.
            if (iv.mult != 1) return Value.missing;
            break :blk weekdayOf(dt); // day of week (1=Sun..7=Sat), cycle = WEEK
        } else
            return Value.missing;
        // BUG-intindexmult: fold the plain index into the multi-unit period — a
        // multiplier n groups n sub-intervals, so the index cycles 1..INTSEAS
        // (SAS: INTINDEX('MONTH2',15MAR2020)=2, INTINDEX('QTR2',15AUG2020)=2).
        // ceil(idx/mult); no-op at mult 1.
        return numVal(@floatFromInt(@divTrunc(idx - 1, iv.mult) + 1));
    }
    if (eqi(name, "intfmt")) { // INTFMT(interval, 'L'|'S') → recommended format name (doc p.1070)
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        var buf: [32]u8 = undefined;
        const iv = parseInterval(try toStr(ev, args[0]), &buf); // ignores multiple/shift
        const sz = std.mem.trim(u8, try toStr(ev, args[1]), " ");
        const long = if (std.ascii.startsWithIgnoreCase(sz, "L")) true else if (std.ascii.startsWithIgnoreCase(sz, "S")) false else return Value.missing;
        // Recommended formats per interval; short uses a 2-digit year, long a 4-digit
        // one (doc "Intervals by Category"). Only the common date intervals are
        // modeled. ponytail: time/retail intervals fall through to missing.
        const fmt = if (eqi(iv.base, "YEAR")) "YEAR4." else if (eqi(iv.base, "QTR"))
            (if (long) "YYQC6." else "YYQC4.")
        else if (eqi(iv.base, "MONTH"))
            (if (long) "MONYY7." else "MONYY5.")
        else if (eqi(iv.base, "WEEK"))
            (if (long) "WEEKDATX17." else "WEEKDATX15.")
        else if (eqi(iv.base, "DAY"))
            (if (long) "DATE9." else "DATE7.")
        else
            return Value.missing;
        return .{ .str = try ev.arena.dupe(u8, fmt) };
    }
    if (eqi(name, "mvalid")) { // MVALID(libname, string, member-type [,valid-member-name]) → 1/0
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        // Only `string` (arg 2) is validated; libname/member-type are not (doc p.1219).
        const s = std.mem.trimEnd(u8, try toStr(ev, args[1]), " "); // char padding ≠ name
        const extend = args.len == 4 and eqi(std.mem.trim(u8, try toStr(ev, args[3]), " "), "EXTEND");
        return numVal(if (if (extend) mvalidExtend(s) else mvalidCompat(s)) 1 else 0);
    }

    // ── date / time ──────────────────────────────────────────────────────────
    // A SAS *date* is days since 1960-01-01 (day 0); a *datetime* is seconds
    // since that midnight; a *time* is seconds since midnight. All arrive as
    // plain numerics, so these read/return `f64`s that happen to hold whole days
    // or seconds. ponytail: integer seconds only (fractional seconds floored),
    // no yearcutoff for 2-digit years.
    if (eqi(name, "today") or eqi(name, "date")) {
        if (args.len != 0) return badArity(ev, name, "0", args.len);
        return numVal(@floatFromInt(currentSasDate()));
    }
    if (eqi(name, "year")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return civilFromSas(n).y;
        }
    }.f);
    if (eqi(name, "month")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return civilFromSas(n).m;
        }
    }.f);
    if (eqi(name, "day")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return civilFromSas(n).d;
        }
    }.f);
    if (eqi(name, "qtr")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return @divFloor(civilFromSas(n).m - 1, 3) + 1;
        }
    }.f);
    if (eqi(name, "weekday")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return weekdayOf(n); // 1 = Sunday … 7 = Saturday
        }
    }.f);
    if (eqi(name, "hour")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return @divFloor(@mod(n, 86400), 3600);
        }
    }.f);
    if (eqi(name, "minute")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return @divFloor(@mod(n, 3600), 60);
        }
    }.f);
    if (eqi(name, "second")) return dateField(ev, name, args, struct {
        fn f(n: i64) i64 {
            return @mod(n, 60);
        }
    }.f);
    if (eqi(name, "datepart")) return dateField(ev, name, args, struct {
        fn f(dt: i64) i64 {
            return @divFloor(dt, 86400); // datetime seconds → date days
        }
    }.f);
    if (eqi(name, "juldate") or eqi(name, "juldate7")) {
        // SAS date → Julian date. JULDATE uses a 2-digit year inside the YEARCUTOFF
        // window (else 4); JULDATE7 always uses 4 (YYYYDDD).
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const d = toNum(args[0]);
        if (isMiss(d)) return Value.missing;
        const dn: i64 = toInt(@round(d)) orelse return Value.missing;
        const y = civilFromSas(dn).y;
        const doy = dn - (daysFromCivil(y, 1, 1) + sas_epoch_days) + 1;
        const two_digit = eqi(name, "juldate") and y >= format.yearCutoff() and y <= format.yearCutoff() + 99;
        return numVal(@floatFromInt((if (two_digit) @mod(y, 100) else y) * 1000 + doy));
    }
    if (eqi(name, "datejul")) {
        // Julian date (YYDDD or YYYYDDD) → SAS date
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        const j = toNum(args[0]);
        if (isMiss(j)) return Value.missing;
        const jn: i64 = toInt(@round(j)) orelse return Value.missing;
        var y = @divFloor(jn, 1000);
        const doy = @mod(jn, 1000);
        if (y < 100) y = expandYear(y); // 2-digit year → full via YEARCUTOFF
        return numVal(@floatFromInt(daysFromCivil(y, 1, 1) + sas_epoch_days + doy - 1));
    }
    if (eqi(name, "nwkdom")) {
        // date of the nth (1–5; 5 = last) `weekday` in `month`/`year`
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const n: i64 = toInt(toNum(args[0])) orelse return Value.missing;
        const wd: i64 = toInt(toNum(args[1])) orelse return Value.missing;
        const mo: i64 = toInt(toNum(args[2])) orelse return Value.missing;
        const yr: i64 = toInt(toNum(args[3])) orelse return Value.missing;
        // NOTE-nwkdomdomain: documented domains (Functions Ref p.1269: n 1–5,
        // weekday 1–7, month 1–12). Out-of-domain silently returned a date in a
        // DIFFERENT month — n=6 overshot into the next month (the −7 correction
        // below is right only for n=5), n=0 reached back into the previous year,
        // weekday 0/8 wrapped mod 7, month 13 rolled into next January. The doc
        // pins no out-of-range value, so be loud (D-002): NOTE + _ERROR_=1 +
        // missing via the shared domErr path. (year carries no documented
        // numeric range — same as mdy, not checked.)
        if (n < 1 or n > 5 or wd < 1 or wd > 7 or mo < 1 or mo > 12)
            return domErr(ev, name);
        const first = daysFromCivil(yr, mo, 1) + sas_epoch_days;
        const offset = @mod(wd - weekdayOf(first) + 7, 7); // days from the 1st to the first `wd`
        var day = 1 + offset + (n - 1) * 7;
        if (day > daysInMonth(yr, mo)) day -= 7; // n=5 overshoots → last occurrence
        return numVal(@floatFromInt(first + day - 1));
    }
    if (eqi(name, "datetime")) {
        if (args.len != 0) return badArity(ev, name, "0", args.len);
        return numVal(@floatFromInt(currentSasDate() * 86400 + currentSecondOfDay()));
    }
    if (eqi(name, "time")) {
        if (args.len != 0) return badArity(ev, name, "0", args.len);
        return numVal(@floatFromInt(currentSecondOfDay()));
    }
    if (eqi(name, "timepart")) return dateField(ev, name, args, struct {
        fn f(dt: i64) i64 {
            return @mod(dt, 86400); // datetime seconds → time-of-day seconds
        }
    }.f);
    if (eqi(name, "mdy")) {
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const mf = toNum(args[0]);
        const df = toNum(args[1]);
        const yf = toNum(args[2]);
        if (isMiss(mf) or isMiss(df) or isMiss(yf)) return Value.missing;
        const m = floorI64(mf);
        const d = floorI64(df);
        const y = floorI64(yf);
        if (m < 1 or m > 12 or d < 1 or d > 31) return Value.missing;
        const n = sasDate(y, m, d);
        const c = civilFromSas(n); // round-trip rejects e.g. 30FEB (rolls into March)
        if (c.y != y or c.m != m or c.d != d) return Value.missing;
        return numVal(@floatFromInt(n));
    }
    if (eqi(name, "yyq")) {
        // first day of quarter q of year y — mirrors mdy: out-of-range → missing
        if (args.len != 2) return badArity(ev, name, "2", args.len);
        const yf = toNum(args[0]);
        const qf = toNum(args[1]);
        if (isMiss(yf) or isMiss(qf)) return Value.missing;
        const y = floorI64(yf);
        const q = floorI64(qf);
        if (q < 1 or q > 4) return Value.missing;
        return numVal(@floatFromInt(sasDate(y, 3 * q - 2, 1)));
    }
    if (eqi(name, "hms")) {
        // SAS time value = seconds since midnight; no range clamp (SAS is lenient).
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const h = toNum(args[0]);
        const m = toNum(args[1]);
        const s = toNum(args[2]);
        if (isMiss(h) or isMiss(m) or isMiss(s)) return Value.missing;
        return numVal(h * 3600 + m * 60 + s);
    }
    if (eqi(name, "dhms")) {
        // SAS datetime = date(days)*86400 + time-of-day seconds.
        if (args.len != 4) return badArity(ev, name, "4", args.len);
        const d = toNum(args[0]);
        const h = toNum(args[1]);
        const m = toNum(args[2]);
        const s = toNum(args[3]);
        if (isMiss(d) or isMiss(h) or isMiss(m) or isMiss(s)) return Value.missing;
        return numVal(d * 86400 + h * 3600 + m * 60 + s);
    }
    if (eqi(name, "yrdif")) {
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const d1 = toNum(args[0]);
        const d2 = toNum(args[1]);
        if (isMiss(d1) or isMiss(d2)) return Value.missing;
        return yrdif(floorI64(d1), floorI64(d2), try toStr(ev, args[2]));
    }
    if (eqi(name, "datdif")) {
        if (args.len != 3) return badArity(ev, name, "3", args.len);
        const d1 = toNum(args[0]);
        const d2 = toNum(args[1]);
        if (isMiss(d1) or isMiss(d2)) return Value.missing;
        return datdif(floorI64(d1), floorI64(d2), try toStr(ev, args[2]));
    }
    // coalesce / coalescec — first non-missing (numeric) / non-blank (char) arg.
    if (eqi(name, "coalesce")) {
        for (args) |arg| {
            const v = toNum(arg);
            if (!isMiss(v)) return numVal(v);
        }
        return Value.missing;
    }
    if (eqi(name, "coalescec")) {
        for (args) |arg| {
            const s = try toStr(ev, arg);
            if (std.mem.trim(u8, s, " ").len != 0) return .{ .str = s };
        }
        return .{ .str = "" };
    }
    if (eqi(name, "intck")) {
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const iv = try toStr(ev, args[0]);
        const ff = toNum(args[1]);
        const tf = toNum(args[2]);
        if (isMiss(ff) or isMiss(tf)) return Value.missing;
        const from = floorI64(ff);
        const to = floorI64(tf);
        const bf = bucketOf(iv, from) orelse return unknownInterval(ev, iv);
        const bt = bucketOf(iv, to).?; // same interval → also non-null
        const d = bt - bf; // DISCRETE: boundary crossings
        // BUG-intckcont: 4th method arg. CONTINUOUS ('C') counts COMPLETE (anniversary)
        // intervals; DISCRETE ('D', default) = the crossings. BUG-intckdtcontinuous F2:
        // unknown NON-BLANK method → NOTE + missing (SAS "Invalid argument to
        // function INTCK"); blank/missing/empty keeps the DISCRETE default.
        var continuous = false;
        if (args.len == 4) {
            const m = std.mem.trim(u8, try toStr(ev, args[3]), " ");
            if (m.len > 0) switch (std.ascii.toLower(m[0])) {
                'c' => continuous = true,
                'd' => {},
                else => {
                    note(ev, "invalid INTCK method '{s}' (set to missing)", .{m});
                    return Value.missing;
                },
            };
        }
        if (!continuous or d == 0) return numVal(@floatFromInt(d));
        // the anniversary of `from`, d intervals out. Month-based intervals use a
        // calendar month/day shift (BUG-intckcontyear: NOT INTNX SAME's day-of-year,
        // which mis-counts across leap boundaries); day/week/time fall back to SAME.
        // BUG-intckdtcontinuous F1: DT-prefixed intervals keep from/to on the
        // SECONDS scale, but addMonthsCal shifts a DAYS-scale SAS date — shift the
        // calendar day, re-attach the time-of-day, compare in seconds (mirrors
        // sameAlign's days↔seconds handling, BUG-intnxdtsameoverflow).
        var buf: [32]u8 = undefined;
        const pi = parseInterval(iv, &buf);
        const is_dt = std.ascii.startsWithIgnoreCase(std.mem.trim(u8, iv, " "), "DT");
        const anniv = if (baseMonths(pi.base)) |bm| blk: {
            if (is_dt) {
                const fd = @divFloor(from, 86400);
                break :blk addMonthsCal(fd, d * bm * pi.mult) * 86400 + @mod(from, 86400);
            }
            break :blk addMonthsCal(from, d * bm * pi.mult);
        } else intnxAlign(iv, from, d, .same) orelse return numVal(@floatFromInt(d));
        const overshoot = if (d > 0) anniv > to else anniv < to;
        const adj: i64 = if (d > 0) 1 else -1;
        return numVal(@floatFromInt(if (overshoot) d - adj else d));
    }
    if (eqi(name, "intnx")) {
        if (args.len < 3 or args.len > 4) return badArity(ev, name, "3 or 4", args.len);
        const iv = try toStr(ev, args[0]);
        const sf = toNum(args[1]);
        const nf = toNum(args[2]);
        if (isMiss(sf) or isMiss(nf)) return Value.missing;
        var al: Align = .begin; // default BEGINNING
        if (args.len == 4) {
            const as = std.mem.trim(u8, try toStr(ev, args[3]), " ");
            // BUG-intckdtcontinuous F2: an unknown NON-BLANK alignment → NOTE +
            // missing (SAS "Invalid argument to function INTNX"); blank/missing/
            // empty keeps the BEGINNING default.
            if (as.len > 0) al = switch (std.ascii.toLower(as[0])) {
                'b' => .begin,
                'm' => .middle,
                'e' => .end,
                's' => .same,
                else => {
                    note(ev, "invalid INTNX alignment '{s}' (set to missing)", .{as});
                    return Value.missing;
                },
            };
        }
        // BUG-intnxfracincr: SAS truncates the increment toward zero (like INT),
        // not floor — -0.5 must be 0, not -1. Start date stays floored.
        const r = intnxAlign(iv, floorI64(sf), clampI64(nf), al) orelse return unknownInterval(ev, iv);
        return numVal(@floatFromInt(r));
    }
    if (eqi(name, "timevalue")) {
        // TIMEVALUE(base, ref, amount, compound-interval, date1, rate1 <, date2, rate2, …>)
        if (args.len < 6 or args.len % 2 != 0) return badArity(ev, name, "6, 8, 10, …", args.len);
        const base = toNum(args[0]);
        const ref = toNum(args[1]);
        const amount = toNum(args[2]);
        if (isMiss(base) or isMiss(ref) or isMiss(amount)) return Value.missing;
        const iv = try toStr(ev, args[3]);
        const r = timeGrow(amount, floorI64(ref), floorI64(base), iv, args[4..]) orelse return unknownInterval(ev, iv);
        return numVal(r);
    }
    if (eqi(name, "savings")) {
        // SAVINGS(base, init-deposit-date, amount, count, deposit-interval,
        //         compound-interval, date1, rate1 <, …>): each of `count` equal
        //         deposits (at deposit-interval starts from init-deposit-date) is
        //         time-valued to base and summed.
        if (args.len < 8 or args.len % 2 != 0) return badArity(ev, name, "8, 10, 12, …", args.len);
        const base = toNum(args[0]);
        const init = toNum(args[1]);
        const amount = toNum(args[2]);
        const count = toNum(args[3]);
        if (isMiss(base) or isMiss(init) or isMiss(amount) or isMiss(count) or count < 0) return Value.missing;
        const dep_iv = try toStr(ev, args[4]);
        const cmp_iv = try toStr(ev, args[5]);
        const nbase = floorI64(base);
        const n: usize = @intFromFloat(@min(count, 1_000_000)); // sane cap
        var total: f64 = 0;
        var k: usize = 0;
        while (k < n) : (k += 1) {
            const dep_date = intnxAlign(dep_iv, floorI64(init), @intCast(k), .same) orelse return unknownInterval(ev, dep_iv);
            if (dep_date > nbase) continue; // deposits after the base date don't contribute
            const v = timeGrow(amount, dep_date, nbase, cmp_iv, args[6..]) orelse return unknownInterval(ev, cmp_iv);
            total += v;
        }
        return numVal(total);
    }

    // ── time zones. This interpreter keeps wall-clock in UTC (see
    // `currentSecondOfDay`), so the user zone IS UTC: the ID/name are "UTC", the
    // offset is 0, and the local⇄UTC conversions are the identity.
    // ponytail: there is no time-zone database, so a NAMED non-UTC zone argument
    // cannot be honored — it errors loud (D-002) instead of silently answering
    // for UTC; blank/'UTC' and the zero-argument current-zone forms stay as-is.
    if (eqi(name, "tzoneid") or eqi(name, "tzonename")) { // current time-zone ID / std/DST name
        if (!try utcZoneOk(ev, name, args, 0)) return Value.missing;
        return .{ .str = "UTC" };
    }
    if (eqi(name, "tzoneoff")) { // user offset from UTC, in seconds
        if (!try utcZoneOk(ev, name, args, 0)) return Value.missing;
        return numVal(0);
    }
    if (eqi(name, "tzones2u") or eqi(name, "tzoneu2s")) { // local⇄UTC datetime (identity in UTC)
        if (args.len < 1) return badArity(ev, name, "1 or 2", args.len);
        if (!try utcZoneOk(ev, name, args, 1)) return Value.missing;
        const dt = toNum(args[0]);
        if (isMiss(dt)) return Value.missing;
        return numVal(dt);
    }
    if (eqi(name, "sysprod")) { // 1 if a SAS product is licensed — this interpreter has them all
        if (args.len != 1) return badArity(ev, name, "1", args.len);
        return numVal(1);
    }

    return null;
}

/// The optional time-zone argument at `args[idx]`: absent, blank, or 'UTC'
/// (case-insensitive) is honored — this interpreter's only zone (see the tzone
/// block above). A NAMED non-UTC zone cannot be resolved without a time-zone
/// database: ERROR + false (D-002 — silently answering for UTC would hand back
/// offset 0 / "UTC" / the identity conversion under the requested zone's name).
fn utcZoneOk(ev: *eval.Evaluator, name: []const u8, args: []const Value, idx: usize) eval.Error!bool {
    if (args.len <= idx) return true;
    const z = std.mem.trim(u8, try toStr(ev, args[idx]), " ");
    if (z.len == 0 or eqi(z, "UTC")) return true;
    ev.diags.report(.err, 0, "{s}(): time zone '{s}' is not supported — only 'UTC' (no time-zone database)", .{ name, z }) catch {};
    return false;
}

test "BUG-tzonesilentignore: a NAMED non-UTC zone errors loud (D-002); blank/'UTC'/zero-arg stay UTC" {
    const t = std.testing;
    const pdv_mod = @import("pdv.zig");
    const diag = @import("diag.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pdv = pdv_mod.Pdv.init(a);
    var diags = diag.Diagnostics.init(a);
    var e: eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = &diags };
    const strV = struct {
        fn v(s: []const u8) Value {
            return .{ .str = s };
        }
    }.v;

    // A named non-UTC zone → ERROR + missing on every TZONE* fn (was: silently
    // answered for UTC — off=0 / id="UTC" / identity conversion).
    try t.expect((try fns.dispatch(&e, "tzoneoff", &.{strV("America/New_York")})).isMissing());
    try t.expect((try fns.dispatch(&e, "tzoneid", &.{strV("America/New_York")})).isMissing());
    try t.expect((try fns.dispatch(&e, "tzonename", &.{strV("Europe/Paris")})).isMissing());
    try t.expect((try fns.dispatch(&e, "tzones2u", &.{ numVal(1893456000), strV("America/New_York") })).isMissing());
    try t.expect((try fns.dispatch(&e, "tzoneu2s", &.{ numVal(1893456000), strV("GMT") })).isMissing());
    try t.expectEqual(@as(usize, 5), diags.count());
    try t.expect(diags.hasErrors());
    try t.expect(std.mem.indexOf(u8, try diags.render(), "America/New_York") != null);

    // Blank / 'UTC' (any case) / zero-arg are honored — no new diagnostics.
    try t.expectEqualStrings("UTC", (try fns.dispatch(&e, "tzoneid", &.{strV("UTC")})).str);
    try t.expectEqualStrings("UTC", (try fns.dispatch(&e, "tzonename", &.{strV("utc")})).str);
    try t.expectEqual(@as(f64, 0), (try fns.dispatch(&e, "tzoneoff", &.{strV("")})).num);
    try t.expectEqual(@as(f64, 1893456000), (try fns.dispatch(&e, "tzones2u", &.{ numVal(1893456000), strV("Utc") })).num);
    try t.expectEqual(@as(f64, 1893456000), (try fns.dispatch(&e, "tzoneu2s", &.{numVal(1893456000)})).num);
    try t.expectEqualStrings("UTC", (try fns.dispatch(&e, "tzoneid", &.{})).str);
    try t.expectEqual(@as(usize, 5), diags.count());
}

test "NOTE-nwkdomdomain: NWKDOM out-of-domain args are loud (NOTE + _ERROR_=1 + missing); doc examples pinned" {
    const t = std.testing;
    const pdv_mod = @import("pdv.zig");
    const diag = @import("diag.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var pdv = pdv_mod.Pdv.init(a);
    var diags = diag.Diagnostics.init(a);
    var e: eval.Evaluator = .{ .arena = a, .pdv = &pdv, .diags = &diags };
    const d = struct {
        fn f(y: i64, m: i64, day: i64) f64 {
            return @floatFromInt(sasDate(y, m, day));
        }
    }.f;

    // documented domains (Functions Ref p.1269): n 1–5, weekday 1–7, month 1–12.
    // Each of these silently returned a plausible date in the WRONG month.
    const bad = [6][4]f64{
        .{ 6, 2, 1, 2020 }, // n=6 → was 03FEB2020 (next month)
        .{ 0, 2, 1, 2020 }, // n=0 → was 30DEC2019 (previous year)
        .{ 1, 0, 1, 2020 }, // wd=0 → was a Saturday (mod-7 wrap)
        .{ 1, 8, 1, 2020 }, // wd=8 → was a Sunday (mod-7 wrap)
        .{ 1, 1, 13, 2020 }, // mo=13 → was JAN2021
        .{ 1, 1, 0, 2020 }, // mo=0 → was DEC2019
    };
    for (bad) |args| {
        const v = (try fns.dispatch(&e, "nwkdom", &.{ numVal(args[0]), numVal(args[1]), numVal(args[2]), numVal(args[3]) }));
        try t.expect(v.isMissing());
    }
    try t.expectEqual(@as(usize, 6), diags.count());
    for (diags.list.items) |dg|
        try t.expect(std.mem.indexOf(u8, dg.message, "argument out of domain") != null);
    try t.expectEqual(Value{ .num = 1 }, pdv.get("_error_").?);

    // doc examples (p.1271) + the n=5 overshoot correction stay exact, no new NOTEs.
    try t.expectEqual(d(2021, 5, 17), (try fns.dispatch(&e, "nwkdom", &.{ numVal(3), numVal(2), numVal(5), numVal(2021) })).num);
    try t.expectEqual(d(2021, 12, 30), (try fns.dispatch(&e, "nwkdom", &.{ numVal(5), numVal(5), numVal(12), numVal(2021) })).num);
    try t.expectEqual(d(2021, 5, 31), (try fns.dispatch(&e, "nwkdom", &.{ numVal(5), numVal(2), numVal(5), numVal(2021) })).num); // last Mon, real 5th
    try t.expectEqual(d(2021, 2, 28), (try fns.dispatch(&e, "nwkdom", &.{ numVal(5), numVal(1), numVal(2), numVal(2021) })).num); // n=5 == n=4
    try t.expectEqual(d(2022, 1, 2), (try fns.dispatch(&e, "nwkdom", &.{ numVal(1), numVal(1), numVal(1), numVal(2022) })).num);
    try t.expectEqual(@as(usize, 6), diags.count());
}
