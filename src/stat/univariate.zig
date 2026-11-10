//! UNIVARIATE summary extensions: syntax, numerical summaries, and rendering.
//! SAS 9.4 Statistical Procedures pp.299–306, 342, 353–358, 408–414, 460–466.
const std = @import("std");
const proc = @import("../proc.zig");
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
    obscol: ?usize = null,
    freqcol: ?usize = null,
    round_units: []f64 = &.{},
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
        }
        self.source = copy;
        return copy;
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
    pub fn roundData(self: *Options, a: Allocator, d: *diag.Diagnostics, ds: *Dataset, cols: []const usize) diag.Error!*Dataset {
        if (self.round.len == 0) return ds;
        if (self.round.len != 1 and self.round.len != cols.len) return d.fail(error.ParseError, 0, "UNIVARIATE: ROUND list must match VAR list", .{});
        self.round_units = try a.alloc(f64, ds.columns.items.len);
        @memset(self.round_units, 0);
        for (cols, 0..) |ci, j| self.round_units[ci] = self.round[if (self.round.len == 1) 0 else j];
        const copy = try a.create(Dataset);
        copy.* = Dataset.init(a, ds.name);
        try copy.columns.appendSlice(a, ds.columns.items);
        for (ds.rows.items) |row| {
            const r = try a.dupe(Value, row);
            for (cols, 0..) |col, j| {
                const unit = self.round[if (self.round.len == 1) 0 else j];
                const x = h.toNum(r[col]);
                if (unit > 0 and std.math.isFinite(x)) r[col] = .{ .num = roundEven(x / unit) * unit };
            }
            try copy.rows.append(a, r);
        }
        return copy;
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
        inline for (.{ "msign", "probm", "signrank", "probs", "gini", "mad", "sn", "qn", "std_sn", "std_qn" }) |f| if (eq(key, f)) return @field(self, f);
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
    var z: Summary = .{ .s = h.computeStatsV(ds.rows.items, col, wc, vd), .pairs = try pairsFor(a, ds, col, wc), .nmiss = h.nmissCount(ds.rows.items, col), .nobs = ds.rows.items.len };
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
        if (robust) try robustStats(a, &z);
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
    const inner = try a.alloc(f64, n);
    for (0..n) |i| inner[i] = distanceMedian(z.pairs, i);
    std.mem.sort(f64, inner, {}, std.sort.asc(f64));
    z.sn = 1.1926 * inner[(n - 1) / 2];
    const half = n / 2 + 1;
    z.qn = 2.2219 * pairDistance(z.pairs, half * (half - 1) / 2);
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
    if (eq(canonical(k), "x_20")) return "the  20.0000 percentile";
    if (eq(canonical(k), "x_50")) return "the  50.0000 percentile";
    if (eq(canonical(k), "x_33_33")) return "the  33.3330 percentile";
    if (eq(canonical(k), "x_high")) return "the  85.1250 percentile";
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
            var label_len: usize = 40;
            for (acols) |ci| {
                name_len = @max(name_len, ds.columns.items[ci].name.len);
                if (ds.columns.items[ci].label) |vl| label_len = @max(label_len, vl.len);
            }
            od.setLen("_VAR_", name_len);
            od.setLabel("_VAR_", "Variable Name");
            _ = try od.addColumn("_LABEL_", .char);
            od.setLen("_LABEL_", label_len);
            od.setLabel("_LABEL_", "Variable Label");
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
        for (try h.bySlices(a, ds.rows.items, bcols)) |bs| {
            var bd = Dataset.init(a, ds.name);
            bd.columns = ds.columns;
            try bd.rows.appendSlice(a, bs.rows);
            const groups = try h.collectGroups(a, &bd, ccols);
            try orderGroups(a, &bd, groups, ccols, levels, opt);
            // collectGroups emits a pooled group even for an empty, unclassified input.
            for (groups) |g| {
                if (wc) |wi| {
                    var usable = false;
                    for (g.rows) |row| {
                        if (!std.math.isNan(h.toNum(row[wi]))) usable = true;
                    }
                    if (!usable) continue;
                }

                var gd = Dataset.init(a, ds.name);
                gd.columns = ds.columns;
                try gd.rows.appendSlice(a, g.rows);
                const summaries = try a.alloc(Summary, acols.len);
                var robust = table;
                for (spec.req.items) |r| if (eq(r.key, "gini") or eq(r.key, "mad") or eq(r.key, "sn") or eq(r.key, "qn") or std.ascii.startsWithIgnoreCase(r.key, "std_")) {
                    robust = true;
                };
                if (table and wc == null) for (acols) |ci| {
                    const stats = h.computeStatsV(gd.rows.items, ci, null, vd);
                    if (stats.n >= 2 and stats.std > 0) {
                        diag.markGap();
                        return cx.diags.fail(error.ParseError, 0, "UNIVARIATE: OUTTABLE normality fields require the inference implementation; refusing fabricated missing statistics", .{});
                    }
                };
                for (acols, 0..) |ci, j| summaries[j] = try summarize(a, &gd, ci, wc, vd, mu0, robust);
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
                            if (h.fmtLevelsFor(levels, ci)) |fl| row[j] = h.fmtRawFor(fl, h.valStr(row[j])) orelse .{ .num = nan };
                        } else if (od.columns.items[j].type == .char) row[j] = .{ .str = "" };
                    }
                    var at = keycols.items.len;
                    if (table) {
                        row[at] = .{ .str = ds.columns.items[acols[vi]].name };
                        row[at + 1] = .{ .str = ds.columns.items[acols[vi]].label orelse "" };
                        at += 2;
                        for (tableKeys, 0..) |k, j| row[at + j] = h.numV(summaries[vi].value(k, if (wc != null) 5 else def, vd, mu0));
                    } else for (spec.req.items, 0..) |r, j| {
                        const z = summaries[r.var_index];
                        row[at + j] = h.numV(if (r.pct) |p| quantile(z.pairs, p, if (wc != null) 5 else def) else z.value(r.key, if (wc != null) 5 else def, vd, mu0));
                    }
                    try od.appendRow(row);
                }
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
    if (opt.obscol) |ci| {
        for (ds.rows.items) |row| if (h.toNum(row[ci]) == @as(f64, @floatFromInt(obs))) return row;
    }
    return ds.rows.items[obs - 1];
}
pub fn orderGroups(a: Allocator, ds: *Dataset, groups: []h.MeansGroup, cols: []const usize, levels: []const h.FmtLevels, opt: Options) !void {
    h.reorderGroupsFmt(groups, cols, levels);
    const C = struct {
        ds: *Dataset,
        cols: []const usize,
        levels: []const h.FmtLevels,
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
                    if (h.fmtLevelsFor(c.levels, ci)) |fl| return h.compareValue(h.fmtRawFor(fl, h.valStr(lv)) orelse lv, h.fmtRawFor(fl, h.valStr(rv)) orelse rv) == .lt;
                }
                return h.compareValue(lv, rv) == .lt;
            }
            return false;
        }
    };
    std.mem.sort(h.MeansGroup, groups, C{ .ds = ds, .cols = cols, .levels = levels, .opt = opt }, C.less);
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

test "UNIVARIATE OUTTABLE weighted schema and inference-owned guard" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lib = try testData(a);
    try testRun(a, lib, "proc univariate data=d noprint outtable=t; var x y; weight w; run;");
    const t = lib.find("t").?;
    try std.testing.expectEqual(@as(usize, 48), t.columns.items.len);
    try std.testing.expectEqual(@as(usize, 2), t.rows.items.len);
    try std.testing.expectEqualStrings("Summary Statistics", t.label.?);
    try std.testing.expectEqual(@as(f64, 4), testCell(t, 0, "_NOBS_"));
    try std.testing.expectEqual(@as(f64, 250), testCell(t, 1, "_MEAN_"));
    try std.testing.expect(std.math.isNan(testCell(t, 0, "_NORMAL_")));
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const tokens = try @import("../lexer.zig").tokenize(a, "proc univariate data=d noprint outtable=unavailable; var x; run;", &d);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, proc.runUnivariate(.{ .arena = a, .lib = lib, .diags = &d }, &out, tokens));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(lib.find("unavailable") == null);
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

pub fn hasUsableWeight(ds: *Dataset, wc: ?usize) bool {
    const ci = wc orelse return true;
    for (ds.rows.items) |r| if (!std.math.isNan(h.toNum(r[ci]))) return true;
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
    var high = x[x.len - 1].x - x[0].x;
    while (low < high) {
        const mid = low + (high - low) / 2;
        var count: usize = 0;
        var below: f64 = 0;
        var above = high;
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
