//! UNIVARIATE summary extensions: syntax, numerical summaries, and rendering.
//! SAS 9.4 Statistical Procedures pp.299–306, 342, 353–358, 408–414, 460–466.
const std = @import("std");
const proc = @import("../proc.zig");
const normality = @import("normality.zig");
const h = proc.UnivariateHelpers;
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Allocator = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const nan = std.math.nan(f64);

fn kw(t: Token, name: []const u8) bool {
    return t.tag == .name and eq(t.text, name);
}
fn end(t: []const Token, i: usize) bool {
    return i >= t.len or t[i].tag == .semicolon or t[i].tag == .eof;
}
fn option(t: []const Token, i: usize) bool {
    return i + 1 < t.len and t[i].tag == .name and t[i + 1].tag == .eq;
}
fn number(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (t[i.*].tag == .minus or t[i.*].tag == .plus) {
        if (t[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (t[i.*].tag != .number) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: expected a number", .{});
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: invalid number", .{});
    i.* += 1;
    return sign * v;
}
fn numbers(a: Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error![]f64 {
    var list: std.ArrayList(f64) = .empty;
    while (!end(t, i.*) and !option(t, i.*)) {
        if (t[i.*].tag == .comma) {
            i.* += 1;
            continue;
        }
        if (t[i.*].tag != .number and t[i.*].tag != .minus and t[i.*].tag != .plus) break;
        const start = try number(d, t, i);
        if (!end(t, i.*) and kw(t[i.*], "to")) {
            i.* += 1;
            const stop = try number(d, t, i);
            var step: f64 = 1;
            if (kw(t[i.*], "by")) {
                i.* += 1;
                step = try number(d, t, i);
            }
            if (step <= 0 or stop < start or (stop - start) / step > 100000) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid numeric range", .{});
            var n: usize = 0;
            while (start + @as(f64, @floatFromInt(n)) * step <= stop + 1e-12) : (n += 1) try list.append(a, start + @as(f64, @floatFromInt(n)) * step);
        } else try list.append(a, start);
    }
    if (list.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty numeric list", .{});
    return list.toOwnedSlice(a);
}
fn names(a: Allocator, t: []const Token, i: *usize) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    while (!end(t, i.*) and !option(t, i.*) and (t[i.*].tag == .name or t[i.*].tag == .string or t[i.*].tag == .comma)) : (i.* += 1) {
        if (t[i.*].tag != .comma) try list.append(a, t[i.*].text);
    }
    return list.toOwnedSlice(a);
}
pub const Options = struct {
    source: ?*Dataset = null,
    nobs_source: ?*Dataset = null,
    source_rows: std.AutoHashMapUnmanaged(usize, []const Value) = .empty,
    obscol: ?usize = null,
    freqcol: ?usize = null,
    round_units: []f64 = &.{},
    by_starts: std.ArrayList(usize) = .empty,
    class_missing: [2]bool = .{ false, false },
    class_order: [2][]const u8 = .{ "internal", "internal" },
    freq: bool = false,
    modes: bool = false,
    idout: bool = false,
    exclnpwgt: bool = false,
    nextrobs: usize = 5,
    nextrval: usize = 0,
    round: []const f64 = &.{},
    outtable: ?[]const u8 = null,
    pub fn identify(self: *Options, a: Allocator, ds: *Dataset, obs: ?[]const usize) !*Dataset {
        const copy = try a.create(Dataset);
        copy.* = Dataset.init(a, ds.name);
        try copy.columns.appendSlice(a, ds.columns.items);
        self.obscol = copy.columns.items.len;
        _ = try copy.addColumn("__UNIV_SOURCE_OBS__", .num);
        for (ds.rows.items, 0..) |r, j| {
            const row = try a.alloc(Value, r.len + 1);
            @memcpy(row[0..r.len], r);
            row[r.len] = .{ .num = @floatFromInt(if (obs) |v| v[j] else j + 1) };
            try copy.rows.append(a, row);
            try self.source_rows.put(a, @intFromFloat(h.toNum(row[r.len])), row);
        }
        self.source = copy;
        return copy;
    }
    /// Record BY boundaries after input filtering but before FREQ exclusion.
    pub fn markBy(self: *Options, a: Allocator, ds: *Dataset, cols: []const usize) !void {
        if (cols.len == 0) return;
        for (ds.rows.items, 0..) |row, j| {
            var start = j == 0;
            if (j > 0) for (cols) |ci| {
                if (h.compareValue(row[ci], ds.rows.items[j - 1][ci]) != .eq) start = true;
            };
            if (start) try self.by_starts.append(a, @intFromFloat(h.toNum(row[self.obscol.?])));
        }
    }
    pub fn classOptions(self: *Options, d: *diag.Diagnostics, t: []const Token, i: *usize, j: usize) diag.Error!void {
        i.* += 1;
        while (!end(t, i.*) and t[i.*].tag != .rparen) {
            if (kw(t[i.*], "missing")) {
                self.class_missing[j] = true;
                i.* += 1;
            } else if (kw(t[i.*], "order") and option(t, i.*)) {
                i.* += 2;
                const v = t[i.*].text;
                if (!eq(v, "data") and !eq(v, "freq") and !eq(v, "internal") and !eq(v, "formatted")) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid CLASS ORDER", .{});
                self.class_order[j] = v;
                i.* += 1;
            } else return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported CLASS option {s}", .{t[i.*].text});
        }
        if (t[i.*].tag != .rparen) return d.fail(error.ParseError, 0, "UNIVARIATE: unclosed CLASS options", .{});
    }
    pub fn parse(self: *Options, a: Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!bool {
        const key = t[i.*].text;
        inline for (.{ "freq", "modes", "idout", "exclnpwgt" }) |f| {
            if (eq(key, f)) {
                @field(self, f) = true;
                i.* += 1;
                return true;
            }
        }
        if (eq(key, "mode")) {
            self.modes = true;
            i.* += 1;
            return true;
        }
        if (eq(key, "exclnpwgts")) {
            self.exclnpwgt = true;
            i.* += 1;
            return true;
        }
        if (!option(t, i.*)) return false;
        if (eq(key, "round")) {
            i.* += 2;
            self.round = try numbers(a, d, t, i);
            for (self.round) |v| if (v < 0) return d.fail(error.ParseError, 0, "UNIVARIATE: ROUND units must be nonnegative", .{});
            return true;
        }
        if (eq(key, "nextrobs") or eq(key, "nextrval")) {
            i.* += 2;
            const v = try number(d, t, i);
            if (v < 0 or v != @floor(v) or v > 1000000) return d.fail(error.ParseError, 0, "UNIVARIATE: extreme count must be a nonnegative integer", .{});
            if (eq(key, "nextrobs")) self.nextrobs = @intFromFloat(v) else self.nextrval = @intFromFloat(v);
            return true;
        }
        if (eq(key, "outtable")) {
            i.* += 2;
            self.outtable = try datasetName(a, t, i);
            return true;
        }
        return false;
    }
    pub fn configureRounding(self: *Options, a: Allocator, d: *diag.Diagnostics, ds: *Dataset, cols: []const usize) diag.Error!void {
        if (self.round.len == 0) return;
        if (self.round.len != 1 and self.round.len != cols.len) return d.fail(error.ParseError, 0, "UNIVARIATE: ROUND list must match VAR list", .{});
        self.round_units = try a.alloc(f64, ds.columns.items.len);
        @memset(self.round_units, 0);
        for (cols, 0..) |ci, j| self.round_units[ci] = self.round[if (self.round.len == 1) 0 else j];
    }
};
fn roundEven(x: f64) f64 {
    const lo = @floor(x);
    const f = x - lo;
    return if (f > 0.5 + 1e-12 or (@abs(f - 0.5) <= 1e-12 and @mod(lo, 2) != 0)) lo + 1 else lo;
}
pub fn datasetName(a: Allocator, t: []const Token, i: *usize) ![]const u8 {
    const name = t[i.*].text;
    i.* += 1;
    if (i.* + 1 < t.len and t[i.*].tag == .dot) {
        i.* += 2;
        return std.fmt.allocPrint(a, "{s}.{s}", .{ name, t[i.* - 1].text });
    }
    return name;
}
const Request = struct { key: []const u8, name: []const u8, var_index: usize, pct: ?f64 = null };
pub const Output = struct { tokens: []const Token = &.{}, name: ?[]const u8 = null, req: std.ArrayList(Request) = .empty, pts: []f64 = &.{}, pre: [][]const u8 = &.{}, suffix: [][]const u8 = &.{}, byvar: bool = false, ndec: ?u8 = null };
pub fn parseOutput(a: Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Output {
    var o: Output = .{};
    const start = i.*;
    i.* += 1;
    while (!end(t, i.*)) {
        if (!option(t, i.*)) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: expected OUTPUT option", .{});
        const key = t[i.*].text;
        i.* += 2;
        if (eq(key, "out")) {
            o.name = try datasetName(a, t, i);
            if (t[i.*].tag == .lparen) {
                var depth: usize = 1;
                i.* += 1;
                while (i.* < t.len and depth > 0) : (i.* += 1) {
                    if (t[i.*].tag == .lparen) depth += 1;
                    if (t[i.*].tag == .rparen) depth -= 1;
                }
            }
        } else if (eq(key, "pctlpts")) {
            o.pts = try numbers(a, d, t, i);
            for (o.pts) |p| if (p < 0 or p > 100) return d.fail(error.ParseError, 0, "UNIVARIATE: percentile must be between 0 and 100", .{});
        } else if (eq(key, "pctlpre")) o.pre = try names(a, t, i) else if (eq(key, "pctlname")) o.suffix = try names(a, t, i) else if (eq(key, "pctlgroup")) {
            if (!kw(t[i.*], "byvar") and !kw(t[i.*], "bystat")) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid PCTLGROUP", .{});
            o.byvar = kw(t[i.*], "byvar");
            i.* += 1;
        } else if (eq(key, "pctlndec")) {
            const v = try number(d, t, i);
            if (v < 0 or v != @floor(v)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid PCTLNDEC", .{});
            o.ndec = @intFromFloat(@min(v, 8));
        } else {
            if (!validStat(key)) {
                if (h.isUnivOutGapOption(key)) {
                    diag.markGap();
                    try d.report(.err, 0, "UNIVARIATE: OUTPUT {s} is not implemented", .{key});
                    return error.ParseError;
                }
                return d.fail(error.ParseError, 0, "PROC UNIVARIATE: OUTPUT keyword {s}= is not a UNIVARIATE statistic", .{key});
            }
            const ns = try names(a, t, i);
            if (ns.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTPUT statistic needs a name", .{});
            for (ns, 0..) |n, j| try o.req.append(a, .{ .key = key, .name = n, .var_index = j });
        }
    }
    if ((o.pts.len == 0) != (o.pre.len == 0)) return d.fail(error.ParseError, 0, "UNIVARIATE: PCTLPTS and PCTLPRE must be specified together", .{});
    if (o.req.items.len == 0 and o.pts.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTPUT needs statistics or percentiles", .{});
    o.tokens = t[start..i.*];
    return o;
}
fn validStat(k: []const u8) bool {
    if (h.statFromKw(k) != null and !h.univariateRejectsStatKw(k)) return true;
    inline for (.{ "nobs", "q2", "geomean", "harmean" }) |s| if (eq(k, s)) return true;
    return false;
}
fn pctName(a: Allocator, pre: []const u8, suffix: ?[]const u8, p: f64, ndec: ?u8) ![]const u8 {
    const s = suffix orelse blk: {
        var text: []u8 = undefined;
        if (ndec) |digits| {
            const scale = std.math.pow(f64, 10, @floatFromInt(@min(digits, 8)));
            text = try std.fmt.allocPrint(a, "{d}", .{@floor(p * scale + 0.5) / scale});
        } else if (p == @floor(p)) {
            text = try std.fmt.allocPrint(a, "{d}", .{p});
        } else {
            const full = try std.fmt.allocPrint(a, "{d:.8}", .{p});
            const trimmed = std.mem.trimEnd(u8, full, "0");
            const dot = std.mem.indexOfScalar(u8, trimmed, '.').?;
            const len = if (trimmed.len == dot + 1) @min(full.len, dot + 3) else @min(trimmed.len, dot + 3);
            text = full[0..len];
        }
        for (text) |*c| if (c.* == '.') {
            c.* = '_';
        };
        break :blk text;
    };
    return std.fmt.allocPrint(a, "{s}{s}", .{ pre[0..@min(pre.len, 32 -| s.len)], s[0..@min(s.len, 32)] });
}

fn percentile(k: []const u8) ?f64 {
    if (eq(k, "median") or eq(k, "q2") or eq(k, "p50")) return 50;
    if (eq(k, "q1") or eq(k, "p25")) return 25;
    if (eq(k, "q3") or eq(k, "p75")) return 75;
    inline for (.{ "p1", "p5", "p10", "p90", "p95", "p99" }, .{ 1, 5, 10, 90, 95, 99 }) |name, p| if (eq(k, name)) return p;
    return null;
}
fn pairsFor(a: Allocator, ds: *Dataset, col: usize, wc: ?usize) ![]h.XW {
    var p: std.ArrayList(h.XW) = .empty;
    for (ds.rows.items, 0..) |r, j| {
        const x = h.toNum(r[col]);
        if (std.math.isNan(x)) continue;
        const w = h.weightAt(r, wc) orelse continue;
        try p.append(a, .{ .x = x, .w = w, .obs = j + 1 });
    }
    std.mem.sort(h.XW, p.items, {}, struct {
        fn less(_: void, l: h.XW, r: h.XW) bool {
            return l.x < r.x or (l.x == r.x and l.obs < r.obs);
        }
    }.less);
    return p.toOwnedSlice(a);
}
const Summary = struct {
    s: h.Stats,
    pairs: []h.XW,
    nmiss: usize,
    nobs: usize,
    geo: f64 = nan,
    harm: f64 = nan,
    msign: f64 = nan,
    probm: f64 = nan,
    signrank: f64 = nan,
    probs: f64 = nan,
    normaltest: f64 = nan,
    probn: f64 = nan,
    gini: f64 = nan,
    mad: f64 = nan,
    sn: f64 = nan,
    qn: f64 = nan,
    std_sn: f64 = nan,
    std_qn: f64 = nan,
    fn value(self: Summary, key: []const u8, def: u8, vd: h.VarDef, mu0: f64) f64 {
        if (percentile(key)) |p| return quantile(self.pairs, p, def);
        if (eq(key, "qrange")) return h.univPercentile(self.pairs, 75, def) - h.univPercentile(self.pairs, 25, def);
        if (eq(key, "nmiss")) return @floatFromInt(self.nmiss);
        if (eq(key, "nobs")) return @floatFromInt(self.nobs);
        if (eq(key, "geomean")) return self.geo;
        if (eq(key, "harmean")) return self.harm;
        inline for (.{ "msign", "probm", "signrank", "probs", "normaltest", "probn", "gini", "mad", "sn", "qn", "std_sn", "std_qn" }) |f| if (eq(key, f)) return @field(self, f);
        if (eq(key, "std_mad")) return self.mad * 1.4826;
        if (eq(key, "std_gini")) return self.gini * std.math.sqrt(std.math.pi) / 2;
        if (eq(key, "std_qrange")) return (h.univPercentile(self.pairs, 75, def) - h.univPercentile(self.pairs, 25, def)) / 1.34898;
        if (eq(key, "t") or eq(key, "probt")) {
            if (vd != .df or self.s.n < 2 or !(self.s.std > 0)) return nan;
            const tv = (self.s.mean - mu0) / (self.s.std / @sqrt(self.s.sumw));
            return if (eq(key, "t")) tv else 2 * (1 - h.studentTcdf(@abs(tv), @as(f64, @floatFromInt(self.s.n)) - 1));
        }
        if ((eq(key, "stderr") or eq(key, "stdmean")) and vd != .df) return nan;
        if (h.statFromKw(key)) |k| return h.statValue(k, self.s);
        return nan;
    }
};
fn summarize(a: Allocator, ds: *Dataset, col: usize, wc: ?usize, vd: h.VarDef, mu0: f64, robust: bool) !Summary {
    // SAS 9.4 pp.398,408: missing weights exclude observations from NMISS.
    // Zero/negative weights still count unless EXCLNPWGT already removed them.
    var nmiss: usize = 0;
    for (ds.rows.items) |row| {
        if (std.math.isNan(h.toNum(row[col])) and h.weightAt(row, wc) != null) nmiss += 1;
    }
    var z: Summary = .{ .s = h.computeStatsV(ds.rows.items, col, wc, vd), .pairs = try pairsFor(a, ds, col, wc), .nmiss = nmiss, .nobs = ds.rows.items.len };
    if (z.pairs.len == 1) z.s.mode = z.pairs[0].x;
    if (z.s.n > 0 and z.s.sumw == 0) z.s.css = 0;
    var logs: f64 = 0;
    var recip: f64 = 0;
    var negative = false;
    var zero = false;
    for (z.pairs) |p| {
        if (p.w > 0) {
            if (p.x < 0) negative = true;
            if (p.x == 0) zero = true;
            logs += p.w * @log(p.x);
            recip += p.w / p.x;
        }
    }
    if (z.s.sumw > 0) {
        z.geo = if (negative) nan else if (zero) 0 else @exp(logs / z.s.sumw);
        z.harm = if (zero or recip == 0) nan else z.s.sumw / recip;
    }
    if (vd == .n and z.s.std > 0) {
        var m3: f64 = 0;
        var m4: f64 = 0;
        for (z.pairs) |p| {
            const v = @sqrt(p.w) * (p.x - z.s.mean) / z.s.std;
            m3 += v * v * v;
            m4 += v * v * v * v;
        }
        z.s.skew = m3 / @as(f64, @floatFromInt(z.s.n));
        z.s.kurt = m4 / @as(f64, @floatFromInt(z.s.n)) - 3;
    }
    if (wc == null) {
        const NZ = struct { x: f64, pos: bool };
        var nz: std.ArrayList(NZ) = .empty;
        var pos: usize = 0;
        for (z.pairs) |p| if (p.x != mu0) {
            try nz.append(a, .{ .x = @abs(p.x - mu0), .pos = p.x > mu0 });
            if (p.x > mu0) pos += 1;
        };
        const n = nz.items.len;
        z.msign = @as(f64, @floatFromInt(pos)) - @as(f64, @floatFromInt(n)) / 2;
        if (n > 0) {
            const high = @max(pos, n - pos);
            z.probm = @min(1, 2 * h.betai(@floatFromInt(high), @floatFromInt(n - high + 1), 0.5));
        }
        std.mem.sort(NZ, nz.items, {}, struct {
            fn less(_: void, l: NZ, r: NZ) bool {
                return l.x < r.x;
            }
        }.less);
        const ranks = try a.alloc(i64, n);
        var tie: f64 = 0;
        var lo: usize = 0;
        while (lo < n) {
            var hi = lo + 1;
            while (hi < n and nz.items[hi].x == nz.items[lo].x) hi += 1;
            const count: @TypeOf(tie) = @floatFromInt(hi - lo);
            tie += count * (count - 1) * (2 * count + 5);
            @memset(ranks[lo..hi], @intCast(lo + hi + 1));
            lo = hi;
        }
        var sum: i64 = 0;
        for (ranks, 0..) |r, j| {
            sum += if (nz.items[j].pos) r else -r;
        }
        z.signrank = @as(f64, @floatFromInt(sum)) / 4;
        if (n > 0) z.probs = try h.signedRankP(a, ranks, sum, tie);
        if (robust) {
            try robustStats(a, &z);
            const sorted = try a.alloc(f64, z.pairs.len);
            for (z.pairs, 0..) |pair, j| sorted[j] = pair.x;
            if (try normality.compute(a, sorted)) |result| {
                z.normaltest = result.statistic;
                z.probn = result.p;
            }
        }
    }
    return z;
}
fn median(x: []f64) f64 {
    if (x.len == 0) return nan;
    std.mem.sort(f64, x, {}, std.sort.asc(f64));
    return if (x.len % 2 == 1) x[x.len / 2] else (x[x.len / 2 - 1] + x[x.len / 2]) / 2;
}
fn robustStats(a: Allocator, z: *Summary) !void {
    const n = z.pairs.len;
    if (n == 0) return;
    const nf: f64 = @floatFromInt(n);
    const med = h.univPercentile(z.pairs, 50, 5);
    const dev = try a.alloc(f64, n);
    var total: f64 = 0;
    for (z.pairs, 0..) |p, j| {
        dev[j] = @abs(p.x - med);
        total += (2 * @as(f64, @floatFromInt(j)) + 1 - nf) * p.x;
    }
    z.mad = median(dev);
    if (n < 2) {
        z.gini = 0;
        z.sn = 0;
        z.qn = 0;
        z.std_sn = 0;
        z.std_qn = 0;
        return;
    }
    z.gini = 2 * total / (nf * (nf - 1));
    // SAS default limits (printed p.301); FORCEQN/FORCESN are separate options.
    if (n <= 1_000_000) {
        const inner = try a.alloc(f64, n);
        for (0..n) |i| inner[i] = distanceMedian(z.pairs, i);
        std.mem.sort(f64, inner, {}, std.sort.asc(f64));
        z.sn = 1.1926 * inner[(n - 1) / 2];
    }
    if (n <= 65_526) {
        const half = n / 2 + 1;
        z.qn = 2.2219 * pairDistance(z.pairs, half * (half - 1) / 2);
    }
    const cs = [_]f64{ 0, 0, 0.743, 1.851, 0.954, 1.351, 0.993, 1.198, 1.005, 1.131 };
    const cq = [_]f64{ 0, 0, 0.399, 0.994, 0.512, 0.844, 0.611, 0.857, 0.669, 0.872 };
    z.std_sn = z.sn * (if (n < 10) cs[n] else if (n % 2 == 1) nf / (nf - 0.9) else 1);
    z.std_qn = z.qn * (if (n < 10) cq[n] else nf / (nf + @as(f64, if (n % 2 == 1) 1.4 else 3.8)));
}
const statOrder = [_][]const u8{ "n", "mean", "std", "skewness", "uss", "cv", "sumwgt", "sum", "var", "kurtosis", "css", "stderr", "nmiss", "nobs", "max", "p99", "p95", "p90", "q3", "median", "q1", "p10", "p5", "p1", "min", "range", "qrange", "mode", "t", "msign", "signrank", "probt", "probm", "probs", "normaltest", "probn", "gini", "mad", "sn", "qn", "std_qrange", "std_gini", "std_mad", "std_sn", "std_qn", "geomean", "harmean" };
fn canonical(k: []const u8) []const u8 {
    inline for (.{ "stddev", "stdmean", "skew", "kurt", "p25", "q2", "p50", "p75" }, .{ "std", "stderr", "skewness", "kurtosis", "q1", "median", "median", "q3" }) |alias, base| if (eq(k, alias)) return base;
    return k;
}
fn order(k: []const u8) usize {
    for (statOrder, 0..) |name, j| if (eq(canonical(k), name)) return j;
    return statOrder.len;
}
const tableKeys = [_][]const u8{ "n", "nmiss", "sumwgt", "sum", "mean", "std", "var", "skewness", "kurtosis", "min", "p1", "p5", "p10", "q1", "median", "q3", "p90", "p95", "p99", "max", "range", "qrange", "mode", "signrank", "probs", "t", "probt", "msign", "probm", "normaltest", "probn", "uss", "css", "cv", "stderr", "gini", "mad", "sn", "qn", "std_qrange", "std_gini", "std_mad", "std_sn", "std_qn", "geomean", "harmean" };
const tableNames = [_][]const u8{ "_NOBS_", "_NMISS_", "_SUMWGT_", "_SUM_", "_MEAN_", "_STD_", "_VARI_", "_SKEW_", "_KURT_", "_MIN_", "_P1_", "_P5_", "_P10_", "_Q1_", "_MEDIAN_", "_Q3_", "_P90_", "_P95_", "_P99_", "_MAX_", "_RANGE_", "_QRANGE_", "_MODE_", "_SGNRNK_", "_PROBS_", "_T_", "_PROBT_", "_MSIGN_", "_PROBM_", "_NORMAL_", "_PROBN_", "_USS_", "_CSS_", "_CV_", "_STDMEAN_", "_GINI_", "_MAD_", "_SN_", "_QN_", "_STDQRANGE_", "_STDGINI_", "_STDMAD_", "_STDSN_", "_STDQN_", "_GEOMEAN_", "_HARMEAN_" };
const tableLabels = [_][]const u8{ "Number of Nonmissing Observations", "Number of Missing Observations", "Sum of the Weights", "Sum", "Mean", "Standard Deviation", "Variance", "Skewness", "Kurtosis", "Minimum", "1st Percentile", "5th Percentile", "10th Percentile", "25th Percentile (Lower Quartile)", "50th Percentile (Median)", "75th Percentile (Upper Quartile)", "90th Percentile", "95th Percentile", "99th Percentile", "Maximum", "Range", "Interquartile range", "Mode", "Centered Signed Rank", "P-Value of Signed Rank Test", "Student's t Statistic", "P-Value of t Statistic", "Sign Statistic", "P-Value of Sign Statistic", "Test Statistic for Normality", "P-Value of Test for Normality", "Uncorrected Sum of Squares", "Corrected Sum of Squares", "Coefficient of Variation", "Standard Error of the Mean", "Gini's Mean Difference", "Median Absolute Difference About the Median", "Sn", "Qn", "Interquartile Range Standard Deviation", "Gini's Standard Deviation", "MAD Standard Deviation", "Sn Standard Deviation", "Qn Standard Deviation", "Geometric Mean", "Harmonic Mean" };
fn label(k: []const u8) []const u8 {
    if (eq(canonical(k), "css")) return "the corrected sum of squares";
    if (eq(canonical(k), "cv")) return "the coefficient of variation";
    if (eq(canonical(k), "gini")) return "Gini's mean difference";
    if (eq(canonical(k), "geomean")) return "geometric mean";
    if (eq(canonical(k), "harmean")) return "harmonic mean";
    if (eq(canonical(k), "kurtosis")) return "kurtosis";
    if (eq(canonical(k), "mean")) return "the mean";
    if (eq(canonical(k), "max")) return "the largest value";
    if (eq(canonical(k), "mad")) return "MAD";
    if (eq(canonical(k), "median")) return "the median";
    if (eq(canonical(k), "min")) return "the smallest value";
    if (eq(canonical(k), "mode")) return "the most frequent value";
    if (eq(canonical(k), "msign")) return "the sign statistic";
    if (eq(canonical(k), "n")) return "number of nonmissing values";
    if (eq(canonical(k), "nmiss")) return "number of missing values";
    if (eq(canonical(k), "nobs")) return "number of observations";
    if (eq(canonical(k), "p1")) return "the 1st percentile";
    if (eq(canonical(k), "p5")) return "the 5th percentile";
    if (eq(canonical(k), "p10")) return "the 10th percentile";
    if (eq(canonical(k), "p90")) return "the 90th percentile";
    if (eq(canonical(k), "p95")) return "the 95th percentile";
    if (eq(canonical(k), "p99")) return "the 99th percentile";
    if (eq(canonical(k), "probm")) return "p-value of the sign statistic";
    if (eq(canonical(k), "probs")) return "p-value of signed rank stat";
    if (eq(canonical(k), "probt")) return "p-value of the t statistic";
    if (eq(canonical(k), "q1")) return "the lower quartile";
    if (eq(canonical(k), "q3")) return "the upper quartile";
    if (eq(canonical(k), "qn")) return "Qn";
    if (eq(canonical(k), "qrange")) return "the interquartile range";
    if (eq(canonical(k), "range")) return "the range";
    if (eq(canonical(k), "std")) return "the standard deviation";
    if (eq(canonical(k), "stderr")) return "the standard error of the mean";
    if (eq(canonical(k), "std_gini")) return "standard deviation from GINI";
    if (eq(canonical(k), "skewness")) return "skewness";
    if (eq(canonical(k), "std_mad")) return "standard deviation from MAD";
    if (eq(canonical(k), "sn")) return "Sn";
    if (eq(canonical(k), "std_qn")) return "standard deviation from QN";
    if (eq(canonical(k), "std_qrange")) return "standard deviation from QRANGE";
    if (eq(canonical(k), "signrank")) return "the signed rank statistic";
    if (eq(canonical(k), "std_sn")) return "standard deviation from SN";
    if (eq(canonical(k), "sum")) return "the sum";
    if (eq(canonical(k), "sumwgt")) return "sum of the weights";
    if (eq(canonical(k), "t")) return "Student's t statistic";
    if (eq(canonical(k), "uss")) return "the uncorrected sum of squares";
    if (eq(canonical(k), "var")) return "the variance";
    return k;
}

pub fn buildOutputs(cx: proc.ProcCtx, ds: *Dataset, acols: []const usize, ccols: []const usize, bcols: []const usize, ids: []const usize, wc: ?usize, vd: h.VarDef, def: u8, mu0: f64, opt: Options, outputs: []Output, levels: []const h.FmtLevels, toks: []const Token) diag.Error!void {
    const a = cx.arena;
    var specs: std.ArrayList(Output) = .empty;
    try specs.appendSlice(a, outputs);
    if (opt.outtable) |name| try specs.append(a, .{ .name = name });
    for (specs.items, 0..) |*spec, oi| {
        const table = oi == outputs.len;
        const name = spec.name orelse blk: {
            var n: usize = 1;
            while (true) : (n += 1) {
                const candidate = try std.fmt.allocPrint(a, "data{d}", .{n});
                if (cx.lib.find(candidate) == null) break :blk candidate;
            }
        };
        const od = try a.create(Dataset);
        od.* = Dataset.init(a, name);
        const source = opt.source orelse ds;
        if (table and source.rows.items.len == 0) {
            // SAS leaves an OUTTABLE created from an empty input undescribed.
            try cx.lib.put(name, od);
            continue;
        }
        var table_label = false;
        var keycols: std.ArrayList(usize) = .empty;
        try keycols.appendSlice(a, bcols);
        if (opt.idout and !table) for (ids) |ci| {
            var found = false;
            for (keycols.items) |k| {
                if (k == ci) found = true;
            }
            if (!found) try keycols.append(a, ci);
        };
        try keycols.appendSlice(a, ccols);
        for (keycols.items) |ci| {
            var c = ds.columns.items[ci];
            if (h.fmtLevelsFor(levels, ci)) |fl| {
                c.type = fl.ty;
                c.format = fl.spec;
            }
            _ = try od.addColumnLike(c.name, c);
        }
        if (table) {
            _ = try od.addColumn("_VAR_", .char);
            var name_len: usize = 8;
            for (acols) |ci| {
                name_len = @max(name_len, ds.columns.items[ci].name.len);
                if (ds.columns.items[ci].label) |vl| if (std.mem.trim(u8, vl, " ").len > 0) {
                    table_label = true;
                };
            }
            od.setLen("_VAR_", name_len);
            od.setLabel("_VAR_", "Variable Name");
            if (table_label) {
                _ = try od.addColumn("_LABEL_", .char);
                od.setLen("_LABEL_", 40);
                od.setLabel("_LABEL_", "Variable Label");
            }
            for (tableNames, tableLabels) |n, l| {
                _ = try od.addColumn(n, .num);
                od.setLabel(n, l);
            }
            od.label = "Summary Statistics";
        } else {
            std.mem.sort(Request, spec.req.items, {}, struct {
                fn less(_: void, l: Request, r: Request) bool {
                    return order(l.key) < order(r.key);
                }
            }.less);
            if (spec.pre.len > acols.len) return cx.diags.fail(error.ParseError, 0, "UNIVARIATE: too many percentile prefixes", .{});
            const outer = if (spec.byvar) spec.pre.len else spec.pts.len;
            const inner = if (spec.byvar) spec.pts.len else spec.pre.len;
            for (0..outer) |j| for (0..inner) |k| {
                const vi = if (spec.byvar) j else k;
                const pi = if (spec.byvar) k else j;
                try spec.req.append(a, .{ .key = "percentile", .name = try pctName(a, spec.pre[vi], if (pi < spec.suffix.len) spec.suffix[pi] else null, spec.pts[pi], spec.ndec), .var_index = vi, .pct = spec.pts[pi] });
            };
            var unique: std.ArrayList(Request) = .empty;
            for (spec.req.items) |r| {
                var duplicate = od.indexOf(r.name) != null;
                for (unique.items) |old| {
                    if (eq(old.name, r.name)) duplicate = true;
                }
                if (duplicate) {
                    try cx.diags.warn(0, "Variable {s} already exists on file {s}", .{ r.name, name });
                    continue;
                }
                try unique.append(a, r);
            }
            spec.req = unique;
            var has_pct = false;
            for (spec.req.items) |r| {
                if (r.var_index >= acols.len) return cx.diags.fail(error.ParseError, 0, "UNIVARIATE: too many OUTPUT variable names", .{});
                if (od.indexOf(r.name) != null) return cx.diags.fail(error.ParseError, 0, "UNIVARIATE: duplicate output variable {s}", .{r.name});
                _ = try od.addColumn(r.name, .num);
                const vn = ds.columns.items[acols[r.var_index]].name;
                const l = if (r.pct) |p| try std.fmt.allocPrint(a, "the  {d:.4} percentile, {s}", .{ p, vn }) else try std.fmt.allocPrint(a, "{s}, {s}", .{ label(r.key), vn });
                od.setLabel(r.name, l);
                has_pct = has_pct or r.pct != null or percentile(r.key) != null or eq(r.key, "qrange");
            }
            od.label = if (has_pct and wc != null) "Selected Summary Statistics (Percentile Definition=Weighted)" else if (has_pct) try std.fmt.allocPrint(a, "Selected Summary Statistics (Percentile Definition={d})", .{def}) else "Selected Summary Statistics";
        }
        for (try bySlices(a, ds.rows.items, bcols, opt)) |bs| {
            const first_row = od.rows.items.len;
            var bd = Dataset.init(a, ds.name);
            bd.columns = ds.columns;
            try bd.rows.appendSlice(a, bs.rows);
            const groups = try h.collectGroups(a, &bd, ccols);
            try orderGroups(a, &bd, groups, ccols, levels, wc, opt);
            // collectGroups emits a pooled group even for an empty, unclassified input.
            for (groups) |g| {
                if (!hasUsableWeight(g.rows, wc, opt)) continue;

                var gd = Dataset.init(a, ds.name);
                gd.columns = ds.columns;
                try gd.rows.appendSlice(a, g.rows);
                const analysis = try analysisView(a, &gd, acols, wc, opt);
                const nobs = outputNobs(g.rows, bcols, opt);
                const summaries = try a.alloc(Summary, acols.len);
                var robust = table;
                for (spec.req.items) |r| if (eq(r.key, "gini") or eq(r.key, "mad") or eq(r.key, "sn") or eq(r.key, "qn") or std.ascii.startsWithIgnoreCase(r.key, "std_")) {
                    robust = true;
                };
                for (acols, 0..) |ci, j| {
                    summaries[j] = try summarize(a, analysis.ds, ci, analysis.weight, vd, mu0, robust);
                    // CLASS counts weight-eligible observations, including missing
                    // analysis values. Keep pooled/BY pre-exclusion totals separate.
                    summaries[j].nobs = if (ccols.len > 0) summaries[j].s.n + summaries[j].nmiss else nobs;
                    if (table and wc == null and summaries[j].pairs.len > 65_526)
                        try cx.diags.warn(0, "UNIVARIATE: Qn is not computed by default above 65526 nonmissing observations for {s}", .{ds.columns.items[ci].name});
                    if (table and wc == null and summaries[j].pairs.len > 1_000_000)
                        try cx.diags.warn(0, "UNIVARIATE: Sn is not computed by default above 1000000 nonmissing observations for {s}", .{ds.columns.items[ci].name});
                }
                const nrows = if (table) acols.len else 1;
                for (0..nrows) |vi| {
                    const row = try a.alloc(Value, od.columns.items.len);
                    for (row) |*v| v.* = .{ .num = nan };
                    for (keycols.items, 0..) |ci, j| {
                        if (g.rows.len > 0) {
                            row[j] = g.rows[0][ci];
                            if (opt.idout and !table) for (ids) |id| {
                                if (ci == id and bs.rows.len > 0) row[j] = firstByRow(opt, bs.rows[0], bcols)[ci];
                            };
                            if (h.fmtLevelsFor(levels, ci) != null) row[j] = classRepresentative(&bd, opt, wc, ccols, ci, g.rows[0]);
                        } else if (od.columns.items[j].type == .char) row[j] = .{ .str = "" };
                    }
                    var at = keycols.items.len;
                    if (table) {
                        row[at] = .{ .str = ds.columns.items[acols[vi]].name };
                        at += 1;
                        if (table_label) {
                            const variable_label = ds.columns.items[acols[vi]].label orelse "";
                            row[at] = .{ .str = variable_label[0..@min(variable_label.len, 40)] };
                            at += 1;
                        }
                        for (tableKeys, 0..) |k, j| row[at + j] = h.numV(summaries[vi].value(k, if (wc != null) 5 else def, vd, mu0));
                    } else for (spec.req.items, 0..) |r, j| {
                        const z = summaries[r.var_index];
                        row[at + j] = h.numV(if (r.pct) |p| quantile(z.pairs, p, if (wc != null) 5 else def) else z.value(r.key, if (wc != null) 5 else def, vd, mu0));
                    }
                    try od.appendRow(row);
                }
            }
            // OUTTABLE is BY-major, then analysis-variable-major, then CLASS.
            // OUTPUT remains one row per CLASS combination within each BY group.
            if (table and acols.len > 1) {
                const rows = od.rows.items[first_row..];
                const groups_count = rows.len / acols.len;
                const original = try a.dupe([]const Value, rows);
                for (0..acols.len) |vi| for (0..groups_count) |gi| {
                    rows[vi * groups_count + gi] = original[gi * acols.len + vi];
                };
            }
        }
        try cx.lib.put(name, od);
        try h.applyOutOptions(a, od, if (table) toks else spec.tokens, cx.diags, if (table) "outtable" else "out");
    }
}
pub fn renderExtras(a: Allocator, out: *std.ArrayList(u8), ds: *Dataset, col: usize, wc: ?usize, pairs: []const h.XW, opt: Options, ids: []const usize) !void {
    var extreme: std.ArrayList(h.XW) = .empty;
    for (pairs) |p| {
        var v = p;
        if (opt.obscol) |ci| v.obs = @intFromFloat(h.toNum(ds.rows.items[p.obs - 1][ci]));
        var found = false;
        for (extreme.items) |e| {
            if (e.obs == v.obs) found = true;
        }
        if (!found) try extreme.append(a, v);
    }
    std.mem.sort(h.XW, extreme.items, {}, struct {
        fn less(_: void, l: h.XW, r: h.XW) bool {
            return l.x < r.x or (l.x == r.x and l.obs > r.obs);
        }
    }.less);
    const highest = try a.dupe(h.XW, extreme.items);
    std.mem.sort(h.XW, highest, {}, struct {
        fn less(_: void, l: h.XW, r: h.XW) bool {
            return l.x < r.x or (l.x == r.x and l.obs < r.obs);
        }
    }.less);
    if (opt.nextrobs > 0) {
        try out.appendSlice(a, "\n" ++ (" " ** 23) ++ "Extreme Observations\n\n");
        try out.appendSlice(a, (" " ** 11) ++ "----Lowest----" ++ (" " ** 8) ++ "---Highest---\n\n");
        try out.appendSlice(a, (" " ** 11) ++ "Value      Obs" ++ (" " ** 8) ++ "Value      Obs");
        for (ids) |ci| try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s} (Low/High)", .{ds.columns.items[ci].name}));
        if (opt.freqcol != null) try out.appendSlice(a, "  Freq (Low/High)");
        try out.appendSlice(a, "\n\n");
        const n = @min(opt.nextrobs, extreme.items.len);
        for (0..n) |j| {
            const low = extreme.items[j];
            const high = highest[highest.len - n + j];
            try out.appendSlice(a, " " ** 11);
            try out.appendSlice(a, try h.rjust(a, try h.uNum(a, low.x), 9));
            try out.appendSlice(a, try h.rjust(a, try std.fmt.allocPrint(a, "{d}", .{low.obs}), 5));
            try out.appendSlice(a, " " ** 8);
            try out.appendSlice(a, try h.rjust(a, try h.uNum(a, high.x), 9));
            try out.appendSlice(a, try h.rjust(a, try std.fmt.allocPrint(a, "{d}", .{high.obs}), 5));
            for (ids) |ci| {
                const l = sourceRow(opt.source orelse ds, opt, low.obs)[ci];
                const r = sourceRow(opt.source orelse ds, opt, high.obs)[ci];
                try out.appendSlice(a, try std.fmt.allocPrint(a, "  {s} / {s}", .{ try cell(a, l), try cell(a, r) }));
            }
            if (opt.freqcol) |ci| try out.appendSlice(a, try std.fmt.allocPrint(a, "  {d} / {d}", .{ @floor(h.toNum(sourceRow(ds, opt, low.obs)[ci])), @floor(h.toNum(sourceRow(ds, opt, high.obs)[ci])) }));
            try out.append(a, '\n');
        }
    }
    const Run = struct { x: f64, count: usize, w: f64 };
    var runs: std.ArrayList(Run) = .empty;
    var total: f64 = 0;
    var best: usize = 0;
    for (pairs) |p| {
        total += p.w;
        if (runs.items.len > 0 and runs.items[runs.items.len - 1].x == p.x) {
            runs.items[runs.items.len - 1].count += 1;
            runs.items[runs.items.len - 1].w += p.w;
        } else try runs.append(a, .{ .x = p.x, .count = 1, .w = p.w });
        best = @max(best, runs.items[runs.items.len - 1].count);
    }
    if (opt.modes) {
        try out.appendSlice(a, "\nModes\nMode    Count\n");
        if (best < 2 and runs.items.len != 1) try out.appendSlice(a, ".       .\n") else for (runs.items) |r| {
            if (r.count == best) try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}    {d}\n", .{ try h.uNum(a, r.x), r.count }));
        }
    }
    if (opt.nextrval > 0) {
        try out.appendSlice(a, "\nExtreme Values\nLowest Value Frequency    Highest Value Frequency\n");
        for (0..@min(opt.nextrval, runs.items.len)) |j| {
            const l = runs.items[j];
            const r = runs.items[runs.items.len - @min(opt.nextrval, runs.items.len) + j];
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {d}    {s} {d}\n", .{ try h.uNum(a, l.x), l.count, try h.uNum(a, r.x), r.count }));
        }
    }
    if (opt.freq) {
        try out.appendSlice(a, if (wc == null) "\nFrequency Counts\nValue Count Cell Cum\n" else "\nWeighted Frequency Counts\nValue Count Weighted Count Cell Cum\n");
        var cum: f64 = 0;
        for (runs.items) |r| {
            const pct = 100 * r.w / total;
            cum += pct;
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {d} ", .{ try h.uNum(a, r.x), r.count }));
            if (wc != null) try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} ", .{try h.uNum(a, r.w)}));
            try out.appendSlice(a, if (total > 0) try std.fmt.allocPrint(a, "{d:.1} {d:.1}\n", .{ pct, cum }) else ". .\n");
        }
    }
    _ = col;
}
fn cell(a: Allocator, v: Value) ![]const u8 {
    return switch (v) {
        .str => |s| s,
        .num => |n| try h.uNum(a, n),
    };
}

test "UNIVARIATE rounding uses even multiples including negative ties" {
    try std.testing.expectEqual(@as(f64, -2), roundEven(-2.5));
    try std.testing.expectEqual(@as(f64, -2), roundEven(-1.5));
    try std.testing.expectEqual(@as(f64, 0), roundEven(0.5));
    try std.testing.expectEqual(@as(f64, 2), roundEven(2.5));
}

fn quantile(p: []const h.XW, q: f64, def: u8) f64 {
    var w: f64 = 0;
    for (p) |v| w += v.w;
    return if (p.len == 0) nan else if (w > 0 or def != 5) h.univPercentile(p, q, def) else (p[0].x + p[p.len - 1].x) / 2;
}

fn sourceRow(ds: *Dataset, opt: Options, obs: usize) []const Value {
    if (opt.source_rows.get(obs)) |row| return row;
    if (opt.obscol) |ci| {
        for (ds.rows.items) |row| if (h.toNum(row[ci]) == @as(f64, @floatFromInt(obs))) return row;
    }
    return ds.rows.items[obs - 1];
}
pub fn orderGroups(a: Allocator, ds: *Dataset, groups: []h.MeansGroup, cols: []const usize, levels: []const h.FmtLevels, wc: ?usize, opt: Options) !void {
    h.reorderGroupsFmt(groups, cols, levels);
    const C = struct {
        ds: *Dataset,
        cols: []const usize,
        levels: []const h.FmtLevels,
        wc: ?usize,
        opt: Options,
        fn less(c: @This(), l: h.MeansGroup, r: h.MeansGroup) bool {
            for (c.cols, 0..) |ci, j| {
                const lv = l.rep[ci];
                const rv = r.rep[ci];
                if (h.compareValue(lv, rv) == .eq) continue;
                const mode = c.opt.class_order[j];
                if (eq(mode, "data") or eq(mode, "freq")) {
                    var lf: usize = 0;
                    var rf: usize = 0;
                    var li: usize = c.ds.rows.items.len;
                    var ri: usize = c.ds.rows.items.len;
                    for (c.ds.rows.items, 0..) |row, k| {
                        if (h.compareValue(row[ci], lv) == .eq) {
                            lf += 1;
                            li = @min(li, k);
                        }
                        if (h.compareValue(row[ci], rv) == .eq) {
                            rf += 1;
                            ri = @min(ri, k);
                        }
                    }
                    if (eq(mode, "data")) return li < ri;
                    if (lf != rf) return lf > rf;
                }
                if (eq(mode, "internal")) {
                    if (h.fmtLevelsFor(c.levels, ci) != null) return h.compareValue(classRepresentative(c.ds, c.opt, c.wc, c.cols, ci, l.rep), classRepresentative(c.ds, c.opt, c.wc, c.cols, ci, r.rep)) == .lt;
                }
                return h.compareValue(lv, rv) == .lt;
            }
            return false;
        }
    };
    std.mem.sort(h.MeansGroup, groups, C{ .ds = ds, .cols = cols, .levels = levels, .wc = wc, .opt = opt }, C.less);
    _ = a;
}

fn testData(a: Allocator) !*@import("../exec.zig").Library {
    const lib = try a.create(@import("../exec.zig").Library);
    lib.* = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y", "w", "f", "g" }) |name| {
        _ = try ds.addColumn(name, .num);
    }
    for ([_][5]f64{ .{ 0, 100, 1, 1, 1 }, .{ 10, 200, 1, 2, 1 }, .{ 20, 300, 1, 1, 2 }, .{ 30, 400, 1, 1, 1 } }) |row| {
        var v: [5]Value = undefined;
        for (row, 0..) |x, j| v[j] = .{ .num = x };
        try ds.appendRow(&v);
    }
    try lib.put("d", ds);
    return lib;
}
fn testRun(a: Allocator, lib: *@import("../exec.zig").Library, source: []const u8) !void {
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const t = try @import("../lexer.zig").tokenize(a, source, &d);
    try proc.runUnivariate(.{ .arena = a, .lib = lib, .diags = &d }, &out, t);
    try std.testing.expect(!d.hasErrors());
}
fn testCell(ds: *Dataset, row: usize, name: []const u8) f64 {
    return h.toNum(ds.rows.items[row][ds.indexOf(name).?]);
}
test "UNIVARIATE all PCTLDEF surfaces and weighted definition five" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    for ([_]f64{ 0, 0, 0, 2.5, 5 }, 1..) |want, def| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint pctldef={d}; var x y; output out=o mean=mx my p25=qx qy pctlpts=25 pctlpre=x_ y_; run;", .{def}));
        const o = lib.find("o").?;
        try std.testing.expectEqual(want, testCell(o, 0, "qx"));
        try std.testing.expectEqual(want, testCell(o, 0, "x_25"));
        try std.testing.expectEqual(@as(f64, 250), testCell(o, 0, "my"));
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint pctldef={d}; var x; weight w; output out=weighted q1=q pctlpts=25 pctlpre=p; run;", .{def}));
        try std.testing.expectEqual(@as(f64, 5), testCell(lib.find("weighted").?, 0, "q"));
    }
}
test "UNIVARIATE multiple OUTPUT statements percentile naming and order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint; var x y; output out=a pctlpts=85.125 20 pctlpre=x_ y_ pctlname=high; output out=b pctlgroup=byvar pctlpts=85.125 20 pctlpre=x_ y_ pctlndec=3; run;");
    const first = lib.find("a").?;
    const second = lib.find("b").?;
    for ([_][]const u8{ "x_high", "y_high", "x_20", "y_20" }, first.columns.items) |want, col| try std.testing.expectEqualStrings(want, col.name);
    for ([_][]const u8{ "x_85_125", "x_20", "y_85_125", "y_20" }, second.columns.items) |want, col| try std.testing.expectEqualStrings(want, col.name);
    try std.testing.expectEqualStrings("Selected Summary Statistics (Percentile Definition=5)", first.label.?);
    try std.testing.expect(first.indexOf("_TYPE_") == null and first.indexOf("_FREQ_") == null);
    try std.testing.expectEqual(@as(usize, 32), (try pctName(a, "abcdefghijklmnopqrstuvwxyzabcdef", "suffix", 50, 2)).len);
}
test "UNIVARIATE BY NOTSORTED keeps disjoint groups and FREQ counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint; by g notsorted; var x; freq f; output out=o n=n nobs=no mean=m; run;");
    const o = lib.find("o").?;
    try std.testing.expectEqual(@as(usize, 3), o.rows.items.len);
    try std.testing.expectEqual(@as(f64, 3), testCell(o, 0, "n"));
    try std.testing.expectApproxEqAbs(@as(f64, 20.0 / 3.0), testCell(o, 0, "m"), 1e-12);
}
test "UNIVARIATE summary keywords and VARDEF=N moments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint vardef=n; var x y; output out=o nobs=no q2=q skew=sk kurt=ku geomean=gx gy harmean=hx hy; run;");
    const o = lib.find("o").?;
    try std.testing.expectEqual(@as(f64, 4), testCell(o, 0, "no"));
    try std.testing.expectEqual(@as(f64, 15), testCell(o, 0, "q"));
    try std.testing.expectApproxEqAbs(@as(f64, -1.36), testCell(o, 0, "ku"), 1e-12);
    try std.testing.expectEqual(@as(f64, 0), testCell(o, 0, "gx"));
    try std.testing.expectApproxEqAbs(@as(f64, 192), testCell(o, 0, "hy"), 1e-10);
}
test "UNIVARIATE CLASS parenthesized options and IDOUT metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint idout; class g(order=freq missing); id y; var x; output out=o n=n mean=m; run;");
    const o = lib.find("o").?;
    try std.testing.expectEqual(@as(usize, 2), o.rows.items.len);
    try std.testing.expectEqualStrings("y", o.columns.items[0].name);
    try std.testing.expectEqualStrings("g", o.columns.items[1].name);
    try std.testing.expectEqual(@as(f64, 100), testCell(o, 1, "y"));
}

/// IDOUT uses the first source observation in the BY group, including FREQ=0.
fn firstByRow(opt: Options, row: []const Value, by: []const usize) []const Value {
    const ds = opt.source orelse return row;
    const oi = opt.obscol orelse return row;
    var at: usize = 0;
    while (at < ds.rows.items.len and h.toNum(ds.rows.items[at][oi]) != h.toNum(row[oi])) at += 1;
    if (at == ds.rows.items.len) return row;
    while (at > 0) {
        var same = true;
        for (by) |ci| {
            if (h.compareValue(ds.rows.items[at - 1][ci], ds.rows.items[at][ci]) != .eq) same = false;
        }
        if (!same) break;
        at -= 1;
    }
    return ds.rows.items[at];
}

test "UNIVARIATE OUTTABLE weighted schema and unweighted normality" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint outtable=t; var x y; weight w; run;");
    const t = lib.find("t").?;
    try std.testing.expectEqual(@as(usize, 47), t.columns.items.len);
    try std.testing.expectEqual(@as(usize, 2), t.rows.items.len);
    try std.testing.expectEqualStrings("Summary Statistics", t.label.?);
    try std.testing.expectEqual(@as(f64, 4), testCell(t, 0, "_NOBS_"));
    try std.testing.expectEqual(@as(f64, 250), testCell(t, 1, "_MEAN_"));
    try std.testing.expect(std.math.isNan(testCell(t, 0, "_NORMAL_")));
    try testRun(a, lib, "proc univariate data=d noprint outtable=normal; var x; run;");
    const normal = lib.find("normal").?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.9929120068), testCell(normal, 0, "_NORMAL_"), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9718770576), testCell(normal, 0, "_PROBN_"), 1e-7);
}
test "UNIVARIATE IDOUT retains excluded first source observation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const d = lib.find("d").?;
    const r = try a.dupe(Value, d.rows.items[0]);
    r[3] = .{ .num = 0 };
    d.rows.items[0] = r;
    try testRun(a, lib, "proc univariate data=d noprint idout; by g notsorted; freq f; id y; var x; output out=o mean=m; run;");
    try std.testing.expectEqual(@as(f64, 100), testCell(lib.find("o").?, 0, "y"));
}

pub fn hasUsableWeight(rows: []const []const Value, wc: ?usize, opt: Options) bool {
    const ci = wc orelse return true;
    for (rows) |row| {
        const raw = if (opt.source) |source| sourceRow(source, opt, @intFromFloat(h.toNum(row[opt.obscol.?]))) else row;
        if (!std.math.isNan(h.toNum(raw[ci]))) return true;
    }
    return false;
}

/// Select the upper median of distances from x[i] by merging two implicit sorted
/// sequences. No quadratic scratch space, including for the OUTTABLE path.
fn distanceMedian(x: []const h.XW, i: usize) f64 {
    const nl = i + 1;
    const nr = x.len - i - 1;
    const k = x.len / 2 + 1;
    var lo = k -| nr;
    var hi = @min(k, nl);
    while (lo <= hi) {
        const l = lo + (hi - lo) / 2;
        const r = k - l;
        const lp = if (l == 0) -std.math.inf(f64) else x[i].x - x[i + 1 - l].x;
        const ln = if (l == nl) std.math.inf(f64) else x[i].x - x[i - l].x;
        const rp = if (r == 0) -std.math.inf(f64) else x[i + r].x - x[i].x;
        const rn = if (r == nr) std.math.inf(f64) else x[i + r + 1].x - x[i].x;
        if (lp > rn) hi = l - 1 else if (rp > ln) lo = l + 1 else return @max(lp, rp);
    }
    unreachable;
}
/// Exact kth pair distance. Each sweep counts the implicit difference matrix
/// with two pointers, then tightens the bounds to actual observed distances.
fn pairDistance(x: []const h.XW, k: usize) f64 {
    var low: f64 = 0;
    var high = @min(x[x.len - 1].x - x[0].x, std.math.floatMax(f64));
    while (low < high) {
        const mid = low + (high - low) / 2;
        var count: usize = 0;
        var below: f64 = 0;
        var above = std.math.inf(f64);
        var j: usize = 0;
        for (x, 0..) |v, i| {
            j = @max(j, i + 1);
            while (j < x.len and x[j].x - v.x <= mid) j += 1;
            count += j - i - 1;
            if (j > i + 1) below = @max(below, x[j - 1].x - v.x);
            if (j < x.len) above = @min(above, x[j].x - v.x);
        }
        if (count == k) return below;
        if (count < k) low = above else high = below;
    }
    return low;
}
test "UNIVARIATE robust distance selection matches exhaustive order statistics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (2..35) |n| {
        const pairs = try a.alloc(h.XW, n);
        for (pairs, 0..) |*v, i| v.* = .{ .x = @floatFromInt((i * i + 7 * i) % 37), .w = 1 };
        std.mem.sort(h.XW, pairs, {}, struct {
            fn less(_: void, l: h.XW, r: h.XW) bool {
                return l.x < r.x;
            }
        }.less);
        var all: std.ArrayList(f64) = .empty;
        const distances = try a.alloc(f64, n);
        for (pairs, 0..) |p, i| {
            for (pairs, 0..) |q, j| {
                distances[j] = @abs(p.x - q.x);
                if (i < j) try all.append(a, distances[j]);
            }
            std.mem.sort(f64, distances, {}, std.sort.asc(f64));
            try std.testing.expectEqual(distances[n / 2], distanceMedian(pairs, i));
        }
        std.mem.sort(f64, all.items, {}, std.sort.asc(f64));
        const half = n / 2 + 1;
        const k = half * (half - 1) / 2;
        try std.testing.expectEqual(all.items[k - 1], pairDistance(pairs, k));
    }
    const extreme = [_]h.XW{ .{ .x = -1e308, .w = 1 }, .{ .x = 0, .w = 1 }, .{ .x = 1e308, .w = 1 } };
    try std.testing.expectEqual(@as(f64, 1e308), pairDistance(&extreme, 1));
}

test "UNIVARIATE percentile names distinguish omitted and explicit PCTLNDEC" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("p85_12", try pctName(a, "p", null, 85.1299, null));
    try std.testing.expectEqualStrings("p0_00", try pctName(a, "p", null, 0.0099, null));
    try std.testing.expectEqualStrings("p85_13", try pctName(a, "p", null, 85.125, 2));
    try std.testing.expectEqualStrings("p86", try pctName(a, "p", null, 85.9, 0));
    try std.testing.expectEqualStrings("p85_12345679", try pctName(a, "p", null, 85.123456789, 9));
}
test "UNIVARIATE zero weights do not poison geometric and harmonic means" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    for ([_]f64{ -1, 0, 1, 2 }, 0..) |x, j| {
        const row = try a.dupe(Value, ds.rows.items[j]);
        row[0] = .{ .num = x };
        row[2] = .{ .num = if (j < 2) 0 else 1 };
        ds.rows.items[j] = row;
    }
    try testRun(a, lib, "proc univariate data=d noprint;var x;weight w;output out=o geomean=g harmean=h pctlpts=50 pctlpre=p;run;");
    const o = lib.find("o").?;
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2)), testCell(o, 0, "g"), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 3.0), testCell(o, 0, "h"), 1e-12);
    try std.testing.expectEqualStrings("Selected Summary Statistics (Percentile Definition=Weighted)", o.label.?);
}
test "UNIVARIATE OUTPUT dataset options are local to each statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=work.d noprint;var x;output out=a(keep=m) mean=m n=n;output out=b(keep=n) mean=m n=n;run;");
    try std.testing.expectEqualStrings("m", lib.find("a").?.columns.items[0].name);
    try std.testing.expectEqualStrings("n", lib.find("b").?.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 1), lib.find("b").?.columns.items.len);
}

test "UNIVARIATE percentile and statistic name collisions preserve first value" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint pctldef=1;var x;output out=o mean=a sum=a pctlpts=50.001 50.009 pctlpre=p;run;");
    const o = lib.find("o").?;
    try std.testing.expectEqual(@as(usize, 2), o.columns.items.len);
    try std.testing.expectEqual(@as(f64, 15), testCell(o, 0, "a"));
    try std.testing.expectApproxEqAbs(@as(f64, 10.0004), testCell(o, 0, "p50_00"), 1e-10);
}

/// Select the first weight-eligible original value within this BY group and
/// preceding CLASS levels. FREQ and EXCLNPWGT exclusions already apply to ds;
/// missing weights must not supply a representative, even without EXCLNPWGT.
fn classRepresentative(ds: *Dataset, opt: Options, wc: ?usize, cols: []const usize, ci: usize, rep: []const Value) Value {
    const level = rep[ci];
    const oi = opt.obscol orelse return level;
    rows: for (ds.rows.items) |row| {
        for (cols) |key| {
            if (h.compareValue(row[key], rep[key]) != .eq) continue :rows;
            if (key == ci) break;
        }
        const raw = sourceRow(opt.source orelse ds, opt, @intFromFloat(h.toNum(row[oi])));
        if (h.weightAt(raw, wc) == null) continue;
        return raw[ci];
    }
    return level;
}
/// CLASS grouping uses formatted keys, but an explicitly selected CLASS
/// variable is analyzed using its original numeric values, after ROUND.
pub const Analysis = struct { ds: *Dataset, weight: ?usize };
/// Rounding changes analysis values only. Grouping keys and original weights
/// remain intact even when one variable participates in multiple roles.
pub fn analysisView(a: Allocator, ds: *Dataset, cols: []const usize, wc: ?usize, opt: Options) !Analysis {
    const source = opt.source orelse ds;
    var transform = false;
    for (cols) |ci| {
        if (ds.columns.items[ci].type != .num and source.columns.items[ci].type == .num) transform = true;
        if (ci < opt.round_units.len and opt.round_units[ci] > 0) transform = true;
    }
    if (wc) |ci| if (ds.columns.items[ci].type != .num) {
        transform = true;
    };
    if (!transform) return .{ .ds = ds, .weight = wc };
    const view = try a.create(Dataset);
    view.* = Dataset.init(a, ds.name);
    try view.columns.appendSlice(a, ds.columns.items);
    for (cols) |ci| view.columns.items[ci] = source.columns.items[ci];
    const weight: ?usize = if (wc) |ci| try view.addColumnLike("__UNIV_ANALYSIS_WEIGHT__", source.columns.items[ci]) else null;
    for (ds.rows.items) |row| {
        const values = try a.alloc(Value, view.columns.items.len);
        @memcpy(values[0..row.len], row);
        const raw = sourceRow(source, opt, @intFromFloat(h.toNum(row[opt.obscol.?])));
        if (wc) |ci| values[weight.?] = raw[ci];
        for (cols) |ci| {
            if (ds.columns.items[ci].type != .num) values[ci] = raw[ci];
            if (ci < opt.round_units.len and opt.round_units[ci] > 0 and std.math.isFinite(h.toNum(values[ci]))) {
                const unit = opt.round_units[ci];
                values[ci] = .{ .num = roundEven(h.toNum(values[ci]) / unit) * unit };
            }
        }
        try view.rows.append(a, values);
    }
    return .{ .ds = view, .weight = weight };
}

// SAS 9.4 Table 4.36: pooled/BY NOBS includes weight-excluded rows;
// FREQ expands this count. CLASS instead counts retained analysis rows.
// Oracle: matrix.sas under /tmp/opensas-review-fixes/BUG-univnobsexcl.
fn outputNobs(rows: []const []const Value, bcols: []const usize, opt: Options) usize {
    const source = opt.nobs_source orelse return rows.len;
    if (bcols.len == 0) return source.rows.items.len;
    if (rows.len == 0) return 0;
    var count: usize = 0;
    for (source.rows.items) |row| {
        if (bySegment(opt, row) == bySegment(opt, rows[0])) count += 1;
    }
    return count;
}

fn bySegment(opt: Options, row: []const Value) usize {
    const obs: usize = @intFromFloat(h.toNum(row[opt.obscol.?]));
    var lo: usize = 0;
    var hi = opt.by_starts.items.len;
    while (lo < hi) {
        const mid = lo + (hi - lo) / 2;
        if (opt.by_starts.items[mid] <= obs) lo = mid + 1 else hi = mid;
    }
    return lo;
}
pub fn bySlices(a: Allocator, rows: []const []const Value, cols: []const usize, opt: Options) ![]proc.BySlice {
    if (cols.len == 0 or opt.by_starts.items.len == 0) return h.bySlices(a, rows, cols);
    var slices: std.ArrayList(proc.BySlice) = .empty;
    var start: usize = 0;
    while (start < rows.len) {
        const segment = bySegment(opt, rows[start]);
        var stop = start + 1;
        while (stop < rows.len and bySegment(opt, rows[stop]) == segment) stop += 1;
        try slices.append(a, .{ .rep = rows[start], .rows = rows[start..stop] });
        start = stop;
    }
    return slices.toOwnedSlice(a);
}

test "UNIVARIATE FREQ exclusion preserves original NOTSORTED BY boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]f64{ 0, -1, nan, 0.9, -0.5 }) |excluded| {
        const lib = try testData(a);
        const ds = lib.find("d").?;
        ds.rows.clearRetainingCapacity();
        try ds.appendRow(&.{ .{ .num = 10 }, .{ .num = 100 }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 1 } });
        try ds.appendRow(&.{ .{ .num = 90 }, .{ .num = 900 }, .{ .num = 1 }, .{ .num = excluded }, .{ .num = 2 } });
        try ds.appendRow(&.{ .{ .num = 30 }, .{ .num = 300 }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 1 } });
        try testRun(a, lib, "proc univariate data=d noprint idout;by g notsorted;var x;id y;freq f;output out=o n=n mean=m;run;");
        const o = lib.find("o").?;
        try std.testing.expectEqual(@as(usize, 2), o.rows.items.len);
        try std.testing.expectEqual(@as(f64, 1), testCell(o, 0, "n"));
        try std.testing.expectEqual(@as(f64, 10), testCell(o, 0, "m"));
        try std.testing.expectEqual(@as(f64, 30), testCell(o, 1, "m"));
        try std.testing.expectEqual(@as(f64, 300), testCell(o, 1, "y"));
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const tokens = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint;by g;var x;freq f;output out=bad n=n;run;", &d);
        try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = lib, .diags = &d }, &out, tokens));
        try std.testing.expect(d.hasErrors());
    }
}
test "UNIVARIATE ID prefixes are excluded from default analysis" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.columns.items[0].name = "id1";
    ds.columns.items[1].name = "id2";
    ds.columns.items[4].name = "x";
    try testRun(a, lib, "proc univariate data=d noprint outtable=t;id id:;freq f;weight w;run;");
    const table = lib.find("t").?;
    try std.testing.expectEqual(@as(usize, 1), table.rows.items.len);
    try std.testing.expectEqualStrings("x", table.rows.items[0][table.indexOf("_VAR_").?].str);
}

test "UNIVARIATE ROUND leaves grouping keys and analysis weights unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    for ([_]f64{ 1.1, 1.2 }) |x| try ds.appendRow(&.{ .{ .num = x }, .{ .num = 10 }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 1 } });
    try testRun(a, lib, "proc univariate data=d noprint round=1;class x;var x;output out=c n=n mean=m;run;");
    const c = lib.find("c").?;
    try std.testing.expectEqual(@as(usize, 2), c.rows.items.len);
    try std.testing.expectEqual(@as(f64, 1.1), testCell(c, 0, "x"));
    try std.testing.expectEqual(@as(f64, 1), testCell(c, 0, "m"));
    try testRun(a, lib, "proc univariate data=d noprint round=1;by x;var x;output out=b n=n mean=m;run;");
    const b = lib.find("b").?;
    try std.testing.expectEqual(@as(usize, 2), b.rows.items.len);
    try std.testing.expectEqual(@as(f64, 1.2), testCell(b, 1, "x"));
    try testRun(a, lib, "proc univariate data=d noprint round=1;weight x;var x;output out=w mean=m sumwgt=sw;run;");
    const w = lib.find("w").?;
    try std.testing.expectEqual(@as(f64, 1), testCell(w, 0, "m"));
    try std.testing.expectApproxEqAbs(@as(f64, 2.3), testCell(w, 0, "sw"), 1e-12);
}

test "UNIVARIATE OUTTABLE distinguishes empty input and optional fixed-width labels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.columns.items[0].label = "A deliberately long synthetic label containing more than forty characters";
    try testRun(a, lib, "proc univariate data=d noprint outtable=labeled;var x y;weight w;run;");
    const labeled = lib.find("labeled").?;
    const li = labeled.indexOf("_LABEL_").?;
    try std.testing.expectEqual(@as(usize, 48), labeled.columns.items.len);
    try std.testing.expectEqual(@as(?usize, 40), labeled.columns.items[li].len);
    try std.testing.expectEqualStrings(ds.columns.items[0].label.?[0..40], labeled.rows.items[0][li].str);
    ds.rows.clearRetainingCapacity();
    try testRun(a, lib, "proc univariate data=d noprint outtable=empty;var x;run;");
    const empty = lib.find("empty").?;
    try std.testing.expectEqual(@as(usize, 0), empty.columns.items.len);
    try std.testing.expect(empty.label == null);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = nan }, .{ .num = 1 }, .{ .num = 1 } });
    try testRun(a, lib, "proc univariate data=d noprint outtable=excluded;var x;weight w;run;");
    const excluded = lib.find("excluded").?;
    try std.testing.expectEqual(@as(usize, 0), excluded.rows.items.len);
    try std.testing.expectEqualStrings("Summary Statistics", excluded.label.?);
    try std.testing.expectEqual(@as(usize, 48), excluded.columns.items.len);
}

test "UNIVARIATE OUTTABLE honors the SAS default Qn sample-size limit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pairs = try a.alloc(h.XW, 65527);
    for (pairs, 0..) |*p, i| p.* = .{ .x = @floatFromInt(i + 1), .w = 1 };
    var z: Summary = .{ .s = h.computeStatsV(&.{}, 0, null, .df), .pairs = pairs, .nmiss = 0, .nobs = pairs.len };
    try robustStats(a, &z);
    try std.testing.expect(std.math.isNan(z.qn));
    try std.testing.expect(std.math.isNan(z.std_qn));
    try std.testing.expectApproxEqAbs(@as(f64, 19537.1732), z.sn, 1e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 19537.441543), z.std_sn, 1e-6);
}

test "BUG-univnobsexcl pooled NOBS preserves excluded observations without changing N" {
    // SAS 9.4 Table 4.36 p.460; repro.sas and freqones.sas in
    // /tmp/opensas-review-fixes/BUG-univnobsexcl both give 2,1,7,2.5.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    for ([_][2]f64{ .{ 1, 1 }, .{ 2, nan }, .{ nan, nan }, .{ nan, 1 }, .{ 4, 1 }, .{ 5, 0 }, .{ 6, -1 } }) |r| {
        try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = 0 }, .{ .num = r[1] }, .{ .num = 1 }, .{ .num = 1 } });
    }
    for ([_][]const u8{ "", "freq f;" }) |freq| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint exclnpwgt outtable=t; var x y; weight w; {s} output out=o n=n ny nmiss=nm nobs=no noy mean=m; run;", .{freq}));
        const o = lib.find("o").?;
        try std.testing.expectEqual(@as(usize, 1), o.rows.items.len);
        try std.testing.expectEqual(@as(f64, 2), testCell(o, 0, "n"));
        try std.testing.expectEqual(@as(f64, 3), testCell(o, 0, "ny"));
        try std.testing.expectEqual(@as(f64, 1), testCell(o, 0, "nm"));
        try std.testing.expectEqual(@as(f64, 7), testCell(o, 0, "no"));
        try std.testing.expectEqual(@as(f64, 7), testCell(o, 0, "noy"));
        try std.testing.expectEqual(@as(f64, 2.5), testCell(o, 0, "m"));
        // OUTTABLE _NOBS_ is N, not OUTPUT NOBS.
        try std.testing.expectEqual(@as(f64, 2), testCell(lib.find("t").?, 0, "_NOBS_"));
    }
}

test "BUG-univnobsexcl BY segments FREQ and CLASS follow SAS counting boundaries" {
    // Oracle matrix.sas: CLASS (N,NMISS,NOBS)=(5,1,6),(1,0,1);
    // BY NOBS=11,2; pooled=14; FREQ pooled=24; FREQ BY=20,3.
    // boundary.sas: FREQ CLASS=(3,2,5),(1,0,1). Fully excluded
    // CLASS/BY groups produce no row; repeated NOTSORTED keys stay separate.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    // b,c,x,w,f from the oracle; testData stores x,c,w,f,b.
    for ([_][5]f64{
        .{ 1, 1, 1, 1, 2.9 }, .{ 1, 1, 2, nan, 3 },  .{ 1, 1, nan, 1, 2 },
        .{ 1, 1, 4, 1, 1 },   .{ 1, 1, 5, 0, 4 },    .{ 1, 1, 6, -1, 5 },
        .{ 1, 1, 7, 1, 0 },   .{ 1, 1, 8, 1, nan },  .{ 1, 1, 9, 1, -1 },
        .{ 1, 2, 10, 0, 2 },  .{ 1, 2, 11, nan, 1 }, .{ 2, 1, 12, -1, 1 },
        .{ 1, 1, 20, 1, 1 },  .{ 1, 1, 30, 0, 2 },
    }) |r| {
        try ds.appendRow(&.{ .{ .num = r[2] }, .{ .num = r[1] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .num = r[0] } });
    }
    const Case = struct { syntax: []const u8, nobs: []const f64, n: []const f64, nm: []const f64 };
    for ([_]Case{
        .{ .syntax = "by g notsorted; class y;", .nobs = &.{ 6, 1 }, .n = &.{ 5, 1 }, .nm = &.{ 1, 0 } },
        .{ .syntax = "by g notsorted;", .nobs = &.{ 11, 2 }, .n = &.{ 5, 1 }, .nm = &.{ 1, 0 } },
        .{ .syntax = "", .nobs = &.{14}, .n = &.{6}, .nm = &.{1} },
        .{ .syntax = "freq f;", .nobs = &.{24}, .n = &.{4}, .nm = &.{2} },
        .{ .syntax = "by g notsorted; freq f;", .nobs = &.{ 20, 3 }, .n = &.{ 3, 1 }, .nm = &.{ 2, 0 } },
        .{ .syntax = "by g notsorted; class y; freq f;", .nobs = &.{ 5, 1 }, .n = &.{ 3, 1 }, .nm = &.{ 2, 0 } },
    }) |case| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint exclnpwgt; {s} var x; weight w; output out=o n=n nmiss=nm nobs=no; run;", .{case.syntax}));
        const o = lib.find("o").?;
        try std.testing.expectEqual(case.nobs.len, o.rows.items.len);
        for (case.nobs, case.n, case.nm, 0..) |no, n, nm, j| {
            try std.testing.expectEqual(no, testCell(o, j, "no"));
            try std.testing.expectEqual(n, testCell(o, j, "n"));
            try std.testing.expectEqual(nm, testCell(o, j, "nm"));
        }
    }
}

test "BUG-univnobsexcl preserves eligible formatted CLASS identity and filtered input counts" {
    // identity.sas oracle: formatted c=1.2 N=NOBS=1; MISSING adds c=.
    // with N=NOBS=1; WHERE x<40 gives N=1 NOBS=3; no WEIGHT gives 5,5.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    for ([_][3]f64{ .{ 10, 1.1, 0 }, .{ 20, 1.2, 1 }, .{ 30, 1.3, nan }, .{ 40, nan, 1 }, .{ 50, 2.1, -1 } }) |r| {
        try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = 1 }, .{ .num = 1 } });
    }
    for ([_][]const u8{ "", "(missing)" }, 1..) |option_text, count| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint exclnpwgt; class y{s}; format y 1.; var x; weight w; output out=o n=n nobs=no;run;", .{option_text}));
        const o = lib.find("o").?;
        try std.testing.expectEqual(count, o.rows.items.len);
        try std.testing.expectEqual(@as(f64, 1.2), testCell(o, count - 1, "y"));
        for (0..count) |j| {
            try std.testing.expectEqual(@as(f64, 1), testCell(o, j, "n"));
            try std.testing.expectEqual(@as(f64, 1), testCell(o, j, "no"));
        }
        if (count == 2) try std.testing.expect(std.math.isNan(testCell(o, 0, "y")));
    }
    try testRun(a, lib, "proc univariate data=d noprint exclnpwgt; where x<40; var x; weight w; output out=o n=n nobs=no;run;");
    try std.testing.expectEqual(@as(f64, 1), testCell(lib.find("o").?, 0, "n"));
    try std.testing.expectEqual(@as(f64, 3), testCell(lib.find("o").?, 0, "no"));
    try testRun(a, lib, "proc univariate data=d noprint exclnpwgt; var x; output out=o n=n nobs=no;run;");
    try std.testing.expectEqual(@as(f64, 5), testCell(lib.find("o").?, 0, "n"));
    try std.testing.expectEqual(@as(f64, 5), testCell(lib.find("o").?, 0, "no"));
}

test "BUG-univnmissweight OUTPUT and OUTTABLE exclude missing weights from NMISS only" {
    // SAS 9.4 Statistical Procedures pp.398,408. Oracle repro.sas under
    // /tmp/opensas-review-fixes/BUG-univnmissweight: N=2 NMISS=1 NOBS=5 M=2.5.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    for ([_][2]f64{ .{ 1, 1 }, .{ 2, nan }, .{ nan, nan }, .{ nan, 1 }, .{ 4, 1 } }) |r| {
        try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = 10 }, .{ .num = r[1] }, .{ .num = 1 }, .{ .num = 1 } });
    }
    for ([_][]const u8{ "weight w;", "" }, [_]f64{ 2, 3 }, [_]f64{ 1, 2 }) |weight, n, nm| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint outtable=t; var x y; {s} output out=o n=n nmiss=nm nmy nobs=no mean=m;run;", .{weight}));
        const o = lib.find("o").?;
        const t = lib.find("t").?;
        try std.testing.expectEqual(@as(usize, 1), o.rows.items.len);
        try std.testing.expectEqual(@as(usize, 2), t.rows.items.len);
        try std.testing.expectEqual(n, testCell(o, 0, "n"));
        try std.testing.expectEqual(nm, testCell(o, 0, "nm"));
        try std.testing.expectEqual(@as(f64, 0), testCell(o, 0, "nmy"));
        try std.testing.expectEqual(@as(f64, 5), testCell(o, 0, "no"));
        try std.testing.expectApproxEqAbs(if (weight.len > 0) @as(f64, 2.5) else 7.0 / 3.0, testCell(o, 0, "m"), 1e-12);
        try std.testing.expectEqual(n, testCell(t, 0, "_NOBS_"));
        try std.testing.expectEqual(nm, testCell(t, 0, "_NMISS_"));
        try std.testing.expectEqual(@as(f64, 0), testCell(t, 1, "_NMISS_"));
    }
}

test "BUG-univnmissweight NMISS respects FREQ EXCLNPWGT and BY CLASS groups" {
    // Oracle matrix.sas/.txt/.log in /tmp/opensas-review-fixes/BUG-univnmissweight:
    // Rechecked for BUG-univclassnobsweight under
    // /tmp/opensas-review-r2-fixes/BUG-univclassnobsweight/matrix.{sas,txt,log}.
    // 24 cases, no SAS errors/warnings. Each OUTPUT NMISS equals OUTTABLE _NMISS_.
    // Missing x occurs with missing, positive, zero and negative w; the present
    // x with missing w distinguishes counting missing cells from rows.len - N.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    for ([_][5]f64{
        .{ 1, 1, 1, 2.9, 1 },   .{ 2, 1, nan, 3, 1 },   .{ nan, 1, nan, 4, 1 },
        .{ nan, 1, 1, 2.8, 1 }, .{ 4, 1, 1, 1, 1 },     .{ nan, 2, 0, 3, 2 },
        .{ nan, 2, -1, 2, 2 },  .{ 5, 2, 0, 1, 2 },     .{ 6, 2, -1, 1, 2 },
        .{ nan, 2, 1, 0.9, 2 }, .{ nan, 2, 1, nan, 2 }, .{ nan, 2, 1, -1, 2 },
        .{ 7, 2, 1, 1, 2 },
    }) |r| {
        var row: [5]Value = undefined;
        for (r, 0..) |v, j| row[j] = .{ .num = v };
        try ds.appendRow(&row);
    }
    const Case = struct { syntax: []const u8, excl: bool = false, n: [2]f64, nm: [2]f64, no: [2]f64, class_no: [2]f64 };
    for ([_]Case{
        .{ .syntax = "", .n = .{ 3, 3 }, .nm = .{ 2, 5 }, .no = .{ 5, 8 }, .class_no = .{ 5, 8 } },
        .{ .syntax = "weight w;", .n = .{ 2, 3 }, .nm = .{ 1, 5 }, .no = .{ 5, 8 }, .class_no = .{ 3, 8 } },
        .{ .syntax = "weight w;", .excl = true, .n = .{ 2, 1 }, .nm = .{ 1, 3 }, .no = .{ 5, 8 }, .class_no = .{ 3, 4 } },
        .{ .syntax = "freq f; weight w;", .n = .{ 3, 3 }, .nm = .{ 2, 5 }, .no = .{ 12, 8 }, .class_no = .{ 5, 8 } },
        .{ .syntax = "freq f; weight w;", .excl = true, .n = .{ 3, 1 }, .nm = .{ 2, 0 }, .no = .{ 12, 8 }, .class_no = .{ 5, 1 } },
        .{ .syntax = "freq f;", .n = .{ 6, 3 }, .nm = .{ 6, 5 }, .no = .{ 12, 8 }, .class_no = .{ 12, 8 } },
    }) |case| {
        for ([_][]const u8{ "", "by g;", "class y;", "by g; class y;" }, 0..) |group, gi| {
            try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint {s} outtable=t; {s} {s} var x; output out=o n=n nmiss=nm nobs=no;run;", .{ if (case.excl) "exclnpwgt" else "", case.syntax, group }));
            const o = lib.find("o").?;
            const t = lib.find("t").?;
            const count: usize = if (gi == 0) 1 else 2;
            try std.testing.expectEqual(count, o.rows.items.len);
            try std.testing.expectEqual(count, t.rows.items.len);
            for (0..count) |j| {
                const n = if (gi == 0) case.n[0] + case.n[1] else case.n[j];
                const nm = if (gi == 0) case.nm[0] + case.nm[1] else case.nm[j];
                try std.testing.expectEqual(n, testCell(o, j, "n"));
                try std.testing.expectEqual(nm, testCell(o, j, "nm"));
                try std.testing.expectEqual(n, testCell(t, j, "_NOBS_"));
                try std.testing.expectEqual(nm, testCell(t, j, "_NMISS_"));
                // BUG-univclassnobsweight: CLASS excludes missing weights even
                // without EXCLNPWGT; pooled/BY preserve pre-exclusion totals.
                const no = if (gi == 0) case.no[0] + case.no[1] else if (gi == 1) case.no[j] else case.class_no[j];
                try std.testing.expectEqual(no, testCell(o, j, "no"));
            }
        }
    }
}

test "BUG-univclassrepweight eligible raw keys preserve crossed CLASS BY FREQ and IDOUT" {
    // SAS oracle: /tmp/opensas-review-r2-fixes/BUG-univclassrepweight/matrix.{sas,txt,log}.
    // Explicit raw keys and counts from OUTPUT and OUTTABLE, in SAS row order.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "b", "c", "d", "x", "w", "f", "id" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][7]f64{
        .{ 1, 1.1, 2.1, 10, nan, 1, 101 },
        .{ 1, 1.2, 3.1, 20, 0, 2, 102 },
        .{ 1, 1.3, 2.2, 30, -1, 1, 103 },
        .{ 1, 1.4, 3.2, 40, 1, 0, 104 },
        .{ 1, 1.5, 2.3, nan, 1, 2, 105 },
        .{ 1, 1.6, 3.3, 60, 2, 1, 106 },
        .{ 2, 1.7, 2.4, 70, nan, 1, 107 },
        .{ 2, 1.8, 2.5, 80, 1, 1, 108 },
    }) |r| {
        var row: [7]Value = undefined;
        for (r, 0..) |v, j| row[j] = .{ .num = v };
        try ds.appendRow(&row);
    }
    try lib.put("d", ds);
    const Case = struct { syntax: []const u8, excl: bool, by: bool, cross: bool, rows: []const [8]f64 };
    for ([_]Case{
        .{ .syntax = "weight w;", .excl = false, .by = false, .cross = false, .rows = &.{
            .{ 0, 1.2, 0, 101, 3, 0, 3, 40 },
            .{ 0, 1.5, 0, 101, 2, 1, 3, 66.666666667 },
        } },
        .{ .syntax = "weight w;", .excl = true, .by = false, .cross = false, .rows = &.{
            .{ 0, 1.4, 0, 101, 1, 0, 1, 40 },
            .{ 0, 1.5, 0, 101, 2, 1, 3, 66.666666667 },
        } },
        .{ .syntax = "weight w;freq f;", .excl = false, .by = false, .cross = false, .rows = &.{
            .{ 0, 1.2, 0, 101, 3, 0, 3, nan },
            .{ 0, 1.5, 0, 101, 2, 2, 4, 66.666666667 },
        } },
        .{ .syntax = "weight w;freq f;", .excl = true, .by = false, .cross = false, .rows = &.{
            .{ 0, 1.5, 0, 101, 2, 2, 4, 66.666666667 },
        } },
        .{ .syntax = "weight w;", .excl = false, .by = true, .cross = false, .rows = &.{
            .{ 1, 1.2, 0, 101, 3, 0, 3, 40 },
            .{ 1, 1.5, 0, 101, 1, 1, 2, 60 },
            .{ 2, 1.8, 0, 107, 1, 0, 1, 80 },
        } },
        .{ .syntax = "weight w;freq f;", .excl = false, .by = true, .cross = true, .rows = &.{
            .{ 1, 1.2, 2.2, 101, 1, 0, 1, nan },
            .{ 1, 1.2, 3.1, 101, 2, 0, 2, nan },
            .{ 1, 1.5, 2.3, 101, 0, 2, 2, nan },
            .{ 1, 1.5, 3.3, 101, 1, 0, 1, 60 },
            .{ 2, 1.8, 2.5, 107, 1, 0, 1, 80 },
        } },
        .{ .syntax = "weight w;freq f;", .excl = true, .by = true, .cross = true, .rows = &.{
            .{ 1, 1.5, 2.3, 101, 0, 2, 2, nan },
            .{ 1, 1.5, 3.3, 101, 1, 0, 1, 60 },
            .{ 2, 1.8, 2.5, 107, 1, 0, 1, 80 },
        } },
        .{ .syntax = "freq f;", .excl = false, .by = true, .cross = true, .rows = &.{
            .{ 1, 1.1, 2.1, 101, 2, 0, 2, 20 },
            .{ 1, 1.1, 3.1, 101, 2, 0, 2, 20 },
            .{ 1, 1.5, 2.3, 101, 0, 2, 2, nan },
            .{ 1, 1.5, 3.3, 101, 1, 0, 1, 60 },
            .{ 2, 1.7, 2.4, 107, 1, 0, 1, 70 },
            .{ 2, 1.7, 2.5, 107, 1, 0, 1, 80 },
        } },
    }) |case| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint idout {s} outtable=t; {s} {s} class c {s}; format c d 1.; var x; id id; output out=o n=n nmiss=nm nobs=no mean=m;run;", .{ if (case.excl) "exclnpwgt" else "", case.syntax, if (case.by) "by b;" else "", if (case.cross) "d" else "" }));
        const o = lib.find("o").?;
        const t = lib.find("t").?;
        try std.testing.expectEqual(case.rows.len, o.rows.items.len);
        try std.testing.expectEqual(case.rows.len, t.rows.items.len);
        for (case.rows, 0..) |r, i| {
            for ([_]*Dataset{ o, t }) |out| {
                if (case.by) try std.testing.expectEqual(r[0], testCell(out, i, "b"));
                try std.testing.expectEqual(r[1], testCell(out, i, "c"));
                if (case.cross) try std.testing.expectEqual(r[2], testCell(out, i, "d"));
            }
            try std.testing.expectEqual(r[3], testCell(o, i, "id"));
            try std.testing.expectEqual(r[4], testCell(o, i, "n"));
            try std.testing.expectEqual(r[5], testCell(o, i, "nm"));
            try std.testing.expectEqual(r[6], testCell(o, i, "no"));
            try std.testing.expectEqual(r[4], testCell(t, i, "_NOBS_"));
            try std.testing.expectEqual(r[5], testCell(t, i, "_NMISS_"));
            for ([_]f64{ testCell(o, i, "m"), testCell(t, i, "_MEAN_") }) |mean| {
                if (std.math.isNan(r[7])) try std.testing.expect(std.math.isNan(mean)) else try std.testing.expectApproxEqAbs(r[7], mean, 1e-8);
            }
        }
    }
}

test "BUG-univclassrepweight raw-key ordering and ROUND preserve original weights" {
    // SAS oracle: /tmp/opensas-review-r2-fixes/BUG-univclassrepweight/roles.{sas,txt,log}.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    const ds = lib.find("d").?;
    ds.rows.clearRetainingCapacity();
    for ([_][3]f64{ .{ nan, 5, nan }, .{ 1, 10, nan }, .{ 2, 20, 1 }, .{ 3, 30, 1 } }) |r|
        try ds.appendRow(&.{ .{ .num = r[1] }, .{ .num = r[0] }, .{ .num = r[2] }, .{ .num = 1 }, .{ .num = 1 } });
    var diags = diag.Diagnostics.init(a);
    const toks = try @import("../lexer.zig").tokenize(a, "proc format; value band 1='A' 2='B' 3='A';run;", &diags);
    try proc.runFormat(.{ .arena = a, .lib = lib, .diags = &diags }, toks);
    try std.testing.expect(!diags.hasErrors());
    for ([_]bool{ false, true }) |roles| {
        try testRun(a, lib, try std.fmt.allocPrint(a, "proc univariate data=d noprint {s} outtable=t; class y; format y band.; var {s}; weight {s}; output out=o n=n nobs=no mean=m;run;", .{ if (roles) "round=10" else "", if (roles) "y" else "x", if (roles) "y" else "w" }));
        const o = lib.find("o").?;
        const t = lib.find("t").?;
        try std.testing.expectEqual(@as(usize, 2), o.rows.items.len);
        try std.testing.expectEqual(@as(usize, 2), t.rows.items.len);
        for (0..2) |i| {
            const key: f64 = if (roles) (if (i == 0) 1 else 2) else (if (i == 0) 2 else 3);
            const n: f64 = if (roles and i == 0) 2 else 1;
            const mean: f64 = if (roles) 0 else (if (i == 0) 20 else 30);
            try std.testing.expectEqual(key, testCell(o, i, "y"));
            try std.testing.expectEqual(key, testCell(t, i, "y"));
            try std.testing.expectEqual(n, testCell(o, i, "n"));
            try std.testing.expectEqual(n, testCell(o, i, "no"));
            try std.testing.expectEqual(n, testCell(t, i, "_NOBS_"));
            try std.testing.expectEqual(mean, testCell(o, i, "m"));
            try std.testing.expectEqual(mean, testCell(t, i, "_MEAN_"));
        }
    }
}
