//! Nonparametric TTEST bootstrap, S154 physical pp.10613-10615,10631-10639.
//! The unchanged SAS oracle identifies the MT1998 single-word initialization,
//! 32-bit uniform draws, and replicate-major/group-major draw order. This differs
//! from the interpreter's public RAND initialization/output precision.
//! Generator reference: Matsumoto & Nishimura, ACM TOMACS 8(1),1998, appendix.
//! See https://blogs.sas.com/content/iml/2018/01/29/random-number-generators-sas.html
//! for SAS's MT1998/MT2002 distinction. Hybrid-seed cases remain explicit gaps.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const fit = @import("ttest_fit.zig");
const fns = @import("../functions.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;

pub const Method = enum { percentile, bc };
pub const Options = struct {
    samples: usize = 10000,
    seed: ?u32 = null,
    method: Method = .bc,
    bootdata: ?[]const u8 = null,
    line: usize = 0,
};
pub const Generator = struct {
    state: [624]u32,
    index: usize = 624,
    seed: u32,
    draws: usize = 0,
    pub fn init(seed: u32) Generator {
        var g: Generator = .{ .state = undefined, .seed = seed };
        g.state[0] = seed;
        for (1..624) |i| g.state[i] = 69069 *% g.state[i - 1];
        return g;
    }
    pub fn next(self: *Generator) f64 {
        if (self.index == 624) {
            for (0..624) |i| {
                const joined = (self.state[i] & 0x80000000) | (self.state[(i + 1) % 624] & 0x7fffffff);
                self.state[i] = self.state[(i + 397) % 624] ^ (joined >> 1) ^ (if (joined & 1 != 0) @as(u32, 0x9908b0df) else 0);
            }
            self.index = 0;
        }
        var word = self.state[self.index];
        self.index += 1;
        self.draws += 1;
        word ^= word >> 11;
        word ^= (word << 7) & 0x9d2c5680;
        word ^= (word << 15) & 0xefc60000;
        word ^= word >> 18;
        return @as(f64, @floatFromInt(word)) / 4294967296.0;
    }
};
pub fn generator(o: Options, d: *diag.Diagnostics) diag.Error!Generator {
    if (o.seed) |seed| {
        // MTHYBRID switches initialization for these seeds. The fixed-seed
        // TTEST evidence does not establish that procedural branch yet.
        if (seed % 8192 == 0) return proc.failGap(d, o.line, "PROC TTEST BOOTSTRAP: hybrid initialization for seeds divisible by 8192 is not verified", .{});
        return .init(seed);
    }
    const now = std.Io.Clock.real.now(std.Io.Threaded.global_single_threaded.io()).nanoseconds;
    const bits: u96 = @bitCast(now);
    var seed: u32 = @truncate(bits);
    // A clock-derived seed is unspecified; avoid zero and the known weak
    // initialization class, without changing any explicitly supplied seed.
    if (seed % 8192 == 0) seed +%= 1;
    return .init(seed);
}

pub fn parse(a: A, t: []const lex.Token, d: *diag.Diagnostics) diag.Error!Options {
    var o: Options = .{ .line = t[0].line };
    var i: usize = 1;
    if (i < t.len and t[i].tag == .slash) i += 1;
    while (i < t.len and t[i].tag != .semicolon and t[i].tag != .eof) {
        const token = t[i];
        i += 1;
        if (eq(token.text, "bootci") and (i == t.len or t[i].tag != .eq)) {
            o.method = .bc;
            continue;
        }
        if (i >= t.len or t[i].tag != .eq) return d.fail(error.ParseError, token.line, "BOOTSTRAP: expected option=value", .{});
        i += 1;
        if (i >= t.len) return d.fail(error.ParseError, token.line, "BOOTSTRAP: missing option value", .{});
        if (eq(token.text, "bootci")) {
            const value = t[i];
            i += 1;
            if (eq(value.text, "percentile")) o.method = .percentile else if (eq(value.text, "bc")) o.method = .bc else {
                inline for (.{ "boott", "expandedperc", "normal", "tbootse" }) |known| if (eq(value.text, known)) return proc.failGap(d, value.line, "BOOTSTRAP: BOOTCI={s} is not implemented", .{value.text});
                return d.fail(error.ParseError, value.line, "BOOTSTRAP: invalid BOOTCI={s}", .{value.text});
            }
        } else if (eq(token.text, "bootdata")) {
            if (t[i].tag != .name) return d.fail(error.ParseError, t[i].line, "BOOTDATA requires a dataset name", .{});
            o.bootdata = t[i].text;
            i += 1;
            if (i < t.len and t[i].tag == .dot) {
                i += 1;
                if (i >= t.len or t[i].tag != .name) return d.fail(error.ParseError, token.line, "BOOTDATA requires a member name", .{});
                o.bootdata = try std.fmt.allocPrint(a, "{s}.{s}", .{ o.bootdata.?, t[i].text });
                i += 1;
            }
        } else if (eq(token.text, "nsamples") or eq(token.text, "seed")) {
            var sign: f64 = 1;
            if (t[i].tag == .minus or t[i].tag == .plus) {
                if (t[i].tag == .minus) sign = -1;
                i += 1;
            }
            if (i >= t.len or t[i].tag != .number) return d.fail(error.ParseError, token.line, "BOOTSTRAP: numeric option required", .{});
            const value = sign * (std.fmt.parseFloat(f64, t[i].text) catch return d.fail(error.ParseError, token.line, "BOOTSTRAP: invalid numeric option", .{}));
            i += 1;
            if (!std.math.isFinite(value) or @trunc(value) != value) return d.fail(error.ParseError, token.line, "BOOTSTRAP: integer option required", .{});
            if (eq(token.text, "nsamples")) {
                if (value <= 1) return d.fail(error.ParseError, token.line, "BOOTSTRAP: NSAMPLES must be greater than 1", .{});
                if (value > 1_000_000) return proc.failGap(d, token.line, "BOOTSTRAP: more than 1000000 replicates is not supported", .{});
                o.samples = @intFromFloat(value);
            } else {
                if (value > 4294967295) return proc.failGap(d, token.line, "BOOTSTRAP: seeds beyond 32 bits are not supported", .{});
                o.seed = if (value <= 0) null else @intFromFloat(value);
            }
        } else return d.fail(error.ParseError, token.line, "BOOTSTRAP: unknown option {s}", .{token.text});
    }
    return o;
}

pub const Replicate = struct { mean: f64, pooled_sd: f64, satt_sd: f64 };
pub const Summary = struct { standard_error: f64, bias: f64, lower: f64, upper: f64 };
pub const Result = struct {
    replicates: []const Replicate,
    mean: Summary,
    pooled_sd: Summary,
    satt_sd: Summary,
    attempted: usize,
    successful: usize,
    failed: usize = 0,
    seed: u32,
};
fn less(_: void, a: f64, b: f64) bool {
    return a < b;
}

/// Physical p.10636: inward order-statistic rule, not interpolated quantiles.
pub fn quantile(sorted: []const f64, p: f64) ?f64 {
    if (sorted.len == 0 or !(p >= 0 and p <= 1)) return null;
    const n: f64 = @floatFromInt(sorted.len);
    const rp = n * p;
    const rank = if (rp == @floor(rp)) rp else if (p <= 0.5) @floor((n + 1) * p) else @ceil((n + 1) * p);
    if (rank < 1 or rank > n) return null;
    return sorted[@as(usize, @intFromFloat(rank)) - 1];
}
pub fn summarize(a: A, values: []const f64, estimate: f64, o: Options, inference: fit.Options, d: *diag.Diagnostics) diag.Error!Summary {
    if (values.len < 2) return d.fail(error.ParseError, o.line, "BOOTSTRAP requires at least two successful replicates", .{});
    for (values, 0..) |v, i| if (!std.math.isFinite(v)) return d.fail(error.ExecError, o.line, "BOOTSTRAP replicate {d} produced a nonfinite statistic; failed replicates are not silently discarded", .{i + 1});
    // Existing moment kernel supplies sample SD with denominator r-1.
    const moments = fit.oneSample(values, null, null, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return d.fail(error.ExecError, o.line, "BOOTSTRAP summary moments exceed the numeric range", .{});
    };
    const sorted = try a.dupe(f64, values);
    defer a.free(sorted);
    std.mem.sort(f64, sorted, {}, less);
    var lo = if (inference.sides == .two_sided) inference.alpha / 2 else inference.alpha;
    var hi = 1 - lo;
    if (o.method == .bc) {
        var below: usize = 0;
        for (values) |v| if (v < estimate) {
            below += 1;
        };
        const p = @as(f64, @floatFromInt(below)) / @as(f64, @floatFromInt(values.len));
        if (p == 0 or p == 1) {
            try d.warn(o.line, "BOOTSTRAP bias-corrected limits are undefined because all replicate estimates lie on one side of the estimate", .{});
            return .{ .standard_error = moments.std_dev, .bias = moments.mean - estimate, .lower = std.math.nan(f64), .upper = std.math.nan(f64) };
        }
        const z0 = fns.distQuantile(.normal, p, &.{}).?;
        lo = fns.distCdf(.normal, 2 * z0 + fns.distQuantile(.normal, lo, &.{}).?, &.{}).?;
        hi = fns.distCdf(.normal, 2 * z0 + fns.distQuantile(.normal, hi, &.{}).?, &.{}).?;
    }
    const lower = if (inference.sides == .lower) -std.math.inf(f64) else quantile(sorted, lo) orelse std.math.nan(f64);
    const upper = if (inference.sides == .upper) std.math.inf(f64) else quantile(sorted, hi) orelse std.math.nan(f64);
    if (std.math.isNan(lower) or std.math.isNan(upper)) try d.warn(o.line, "BOOTSTRAP sample must be larger to yield the requested quantile confidence limits", .{});
    return .{ .standard_error = moments.std_dev, .bias = moments.mean - estimate, .lower = lower, .upper = upper };
}

/// Inputs are selected observations, with FREQ already expanded. Two samples
/// draw separately within each class, in class order, for every replicate.
pub fn compute(a: A, first: []const f64, second: ?[]const f64, stream: *Generator, o: Options, inference: fit.Options, d: *diag.Diagnostics) diag.Error!Result {
    if (first.len < 2 or (second != null and second.?.len < 2)) return d.fail(error.ParseError, o.line, "BOOTSTRAP requires at least two observations per sample", .{});
    const first_fit = fit.oneSample(first, null, null, .{}) catch return d.fail(error.ExecError, o.line, "BOOTSTRAP first sample has invalid moments", .{});
    const second_fit = if (second) |v| fit.oneSample(v, null, null, .{}) catch return d.fail(error.ExecError, o.line, "BOOTSTRAP second sample has invalid moments", .{}) else null;
    const original_mean = first_fit.mean - (if (second_fit) |s| s.mean else 0);
    const original_pool = if (second_fit) |s| @sqrt(@as(f64, 2)) * std.math.hypot(first_fit.std_dev * @sqrt(first_fit.df / (first_fit.df + s.df)), s.std_dev * @sqrt(s.df / (first_fit.df + s.df))) else first_fit.std_dev;
    const original_satt = if (second_fit) |s| std.math.hypot(first_fit.std_dev, s.std_dev) else first_fit.std_dev;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    const sample1 = try tmp.alloc(f64, first.len);
    const sample2 = try tmp.alloc(f64, if (second) |v| v.len else 0);
    const draws = try a.alloc(Replicate, o.samples);
    errdefer a.free(draws);
    const means = try tmp.alloc(f64, o.samples);
    const pooled = try tmp.alloc(f64, o.samples);
    const satt = try tmp.alloc(f64, o.samples);
    for (draws, 0..) |*draw, i| {
        for (sample1) |*x| x.* = first[@intFromFloat(stream.next() * @as(f64, @floatFromInt(first.len)))];
        const m1 = fit.oneSample(sample1, null, null, .{}) catch return d.fail(error.ExecError, o.line, "BOOTSTRAP replicate {d} failed in the first sample", .{i + 1});
        var m2: ?fit.Result = null;
        if (second) |v| {
            for (sample2) |*x| x.* = v[@intFromFloat(stream.next() * @as(f64, @floatFromInt(v.len)))];
            m2 = fit.oneSample(sample2, null, null, .{}) catch return d.fail(error.ExecError, o.line, "BOOTSTRAP replicate {d} failed in the second sample", .{i + 1});
        }
        draw.mean = m1.mean - (if (m2) |s| s.mean else 0);
        draw.pooled_sd = if (m2) |s| @sqrt(@as(f64, 2)) * std.math.hypot(m1.std_dev * @sqrt(m1.df / (m1.df + s.df)), s.std_dev * @sqrt(s.df / (m1.df + s.df))) else m1.std_dev;
        draw.satt_sd = if (m2) |s| std.math.hypot(m1.std_dev, s.std_dev) else m1.std_dev;
        means[i] = draw.mean;
        pooled[i] = draw.pooled_sd;
        satt[i] = draw.satt_sd;
    }
    return .{
        .replicates = draws,
        .mean = try summarize(tmp, means, original_mean, o, inference, d),
        .pooled_sd = try summarize(tmp, pooled, original_pool, o, inference, d),
        .satt_sd = try summarize(tmp, satt, original_satt, o, inference, d),
        .attempted = o.samples,
        .successful = o.samples,
        .seed = stream.seed,
    };
}
fn num(a: A, x: f64) ![]const u8 {
    if (std.math.isInf(x)) return if (x < 0) "-Infty" else "Infty";
    return std.mem.trim(u8, try format.apply(a, .{ .num = x }, "d8.3"), " ");
}
fn summaryRow(a: A, out: *std.ArrayList(u8), prefix: []const u8, parameter: []const u8, s: Summary) !void {
    try out.print(a, "{s} {s} {s} {s} {s} {s}\n", .{ prefix, parameter, try num(a, s.standard_error), try num(a, s.bias), try num(a, s.lower), try num(a, s.upper) });
}
pub fn render(a: A, out: *std.ArrayList(u8), r: Result, class_name: ?[]const u8, alpha: f64) !void {
    const level = std.mem.trim(u8, try format.apply(a, .{ .num = 100 * (1 - alpha) }, "best8."), " ");
    try out.appendSlice(a, "Bootstrap Statistics and Confidence Limits\n\nStd\n");
    if (class_name) |name| try out.print(a, "{s} Method ", .{name});
    try out.print(a, "Parameter Error Bias ------{s}% CL-----\n\n", .{level});
    try summaryRow(a, out, if (class_name != null) "Diff (1-2)" else "", "Mean", r.mean);
    try summaryRow(a, out, if (class_name != null) "Diff (1-2) Pooled" else "", "Std Dev", r.pooled_sd);
    if (class_name != null) try summaryRow(a, out, "Diff (1-2) Satterthwaite", "Std Dev", r.satt_sd);
    try out.appendSlice(a, "\n");
}

pub fn outputDataset(a: A, name: []const u8, two_samples: bool) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    _ = try ds.addColumn("Variable", .char);
    ds.setLen("Variable", 32);
    if (two_samples) {
        _ = try ds.addColumn("Class", .char);
        ds.setLen("Class", 32);
    }
    _ = try ds.addColumn("Sample", .num);
    _ = try ds.addColumn("Mean", .num);
    ds.setFormat("Mean", "d8.3");
    _ = try ds.addColumn(if (two_samples) "PooledStdDev" else "StdDev", .num);
    ds.setFormat(if (two_samples) "PooledStdDev" else "StdDev", "d8.3");
    if (two_samples) {
        _ = try ds.addColumn("SattStdDev", .num);
        ds.setFormat("SattStdDev", "d8.3");
    }
    return ds;
}
pub fn appendOutput(ds: *Dataset, variable: []const u8, r: Result, two_samples: bool) !void {
    for (r.replicates, 0..) |draw, i| {
        const number: f64 = @floatFromInt(i + 1);
        if (two_samples) try ds.appendRow(&.{ .{ .str = variable }, .{ .str = "Diff (1-2)" }, .{ .num = number }, .{ .num = draw.mean }, .{ .num = draw.pooled_sd }, .{ .num = draw.satt_sd } }) else try ds.appendRow(&.{ .{ .str = variable }, .{ .num = number }, .{ .num = draw.mean }, .{ .num = draw.pooled_sd } });
    }
}

test "BOOTSTRAP MT1998 reproduces fixed-seed SAS aggregates and every displayed draw" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const o: Options = .{ .samples = 199, .seed = 314159, .method = .percentile };
    var stream = try generator(o, &d);
    const r = try compute(a, &.{ 43, 90, 84, 87, 116, 95 }, &.{ 86, 99, 93, 92, 121, 71 }, &stream, o, .{}, &d);
    try std.testing.expectEqual(@as(usize, 199), r.attempted);
    try std.testing.expectEqual(@as(usize, 199), r.successful);
    try std.testing.expectEqual(@as(usize, 0), r.failed);
    try std.testing.expectEqual(@as(usize, 199 * 12), stream.draws);
    // Independently collected SAS reference, half a four-decimal display unit.
    try std.testing.expectApproxEqAbs(@as(f64, 11.0017), r.mean.standard_error, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -0.4832), r.mean.bias, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -30.6667), r.mean.lower, 0.00005);
    try std.testing.expectEqual(@as(f64, 13), r.mean.upper);
    try std.testing.expectApproxEqAbs(@as(f64, 6.1748), r.pooled_sd.standard_error, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -2.9249), r.pooled_sd.bias, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 13.7307), r.pooled_sd.lower, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 39.8066), r.pooled_sd.upper, 0.00005);
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/STAT15.4-oracle/STAT-TTEST-004/bootstrap_seeded.expected.txt", a, .limited(1024 * 1024));
    var lines = std.mem.tokenizeScalar(u8, expected, '\n');
    var checked: usize = 0;
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        const variable = fields.next() orelse continue;
        if (!std.mem.eql(u8, variable, "x")) continue;
        try std.testing.expectEqualStrings("Diff", fields.next().?);
        try std.testing.expectEqualStrings("(1-2)", fields.next().?);
        const index = try std.fmt.parseInt(usize, fields.next().?, 10);
        const draw = r.replicates[index - 1];
        try std.testing.expectEqualStrings(fields.next().?, try num(a, draw.mean));
        try std.testing.expectEqualStrings(fields.next().?, try num(a, draw.pooled_sd));
        try std.testing.expectEqualStrings(fields.next().?, try num(a, draw.satt_sd));
        try std.testing.expect(fields.next() == null);
        checked += 1;
    }
    try std.testing.expectEqual(@as(usize, 12), checked);
    const ds = try outputDataset(a, "draws", true);
    try appendOutput(ds, "x", r, true);
    try std.testing.expectEqual(@as(usize, 199), ds.rows.items.len);
    try std.testing.expectEqual(@as(usize, 6), ds.columns.items.len);
    try std.testing.expectEqualStrings("PooledStdDev", ds.columns.items[4].name);
    try std.testing.expectEqualStrings("SattStdDev", ds.columns.items[5].name);
    try std.testing.expectEqualStrings("Diff (1-2)", ds.rows.items[0][1].str);
    try std.testing.expectEqual(@as(f64, 199), ds.rows.items[198][2].num);
    try std.testing.expectEqualStrings("", try d.render());
    // Reproducibility checks the complete 199-replicate stream, not one row.
    var replay = try generator(o, &d);
    const repeated = try compute(a, &.{ 43, 90, 84, 87, 116, 95 }, &.{ 86, 99, 93, 92, 121, 71 }, &replay, o, .{}, &d);
    for (r.replicates, repeated.replicates) |left, right| try std.testing.expectEqual(left, right);
}

test "BOOTSTRAP independently enumerated n2 means and inward quantiles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    // All four ordered resamples of (0,2): (0,0),(0,2),(2,0),(2,2).
    // Means=(0,1,1,2), mean=1, sample variance across four replicates=2/3.
    const summary = try summarize(a, &.{ 0, 1, 1, 2 }, 1, .{ .method = .percentile }, .{ .alpha = 0.5 }, &d);
    try std.testing.expectEqual(@as(f64, 0), summary.bias);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2.0 / 3.0)), summary.standard_error, 1e-14);
    try std.testing.expectEqual(@as(f64, 0), summary.lower);
    try std.testing.expectEqual(@as(f64, 1), summary.upper);
    // r*p integer takes that order statistic; otherwise use (r+1)*p inward.
    try std.testing.expectEqual(@as(?f64, 2), quantile(&.{ 1, 2, 3, 4, 5 }, 0.4));
    try std.testing.expectEqual(@as(?f64, 1), quantile(&.{ 1, 2, 3, 4, 5 }, 0.25));
    try std.testing.expectEqual(@as(?f64, 5), quantile(&.{ 1, 2, 3, 4, 5 }, 0.75));
    try std.testing.expectEqual(@as(?f64, null), quantile(&.{ 1, 2, 3, 4, 5 }, 0.01));
    const upper = try summarize(a, &.{ 0, 1, 1, 2 }, 1, .{ .method = .percentile }, .{ .alpha = 0.25, .sides = .upper }, &d);
    try std.testing.expectEqual(@as(f64, 0), upper.lower);
    try std.testing.expectEqual(std.math.inf(f64), upper.upper);
}

test "BOOTSTRAP degenerate replicates are retained and nonfinite failures are not hidden" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const o: Options = .{ .samples = 199, .seed = 7, .method = .percentile, .line = 14 };
    var stream = try generator(o, &d);
    const r = try compute(a, &.{ 2, 2 }, &.{ 5, 5 }, &stream, o, .{}, &d);
    try std.testing.expectEqual(@as(usize, 199), r.successful);
    try std.testing.expectEqual(@as(usize, 0), r.failed);
    try std.testing.expectEqual(@as(f64, -3), r.mean.lower);
    try std.testing.expectEqual(@as(f64, -3), r.mean.upper);
    try std.testing.expectEqual(@as(f64, 0), r.pooled_sd.standard_error);
    for (r.replicates) |draw| try std.testing.expectEqual(@as(f64, 0), draw.pooled_sd);
    try std.testing.expectError(error.ExecError, summarize(a, &.{ 1, std.math.nan(f64), 3 }, 2, o, .{}, &d));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "replicate 2") != null);
    try std.testing.expectEqual(@as(usize, 14), d.list.items[0].line);
    try std.testing.expectError(error.ParseError, compute(a, &.{1}, null, &stream, o, .{}, &d));
}
