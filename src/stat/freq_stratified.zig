//! Independent FREQ stratified and ordered-table kernels (SAS/STAT pp. 209–229).
//! Callers preserve table-level ordering, scores, and zero-weight levels. No
//! parsing or rendering here. Public PROC integration awaits the shared-file lease.
const std = @import("std");
const fns = @import("../functions.zig");
pub const Matrix = @import("freq_table.zig").CountMatrix;
pub const Error = @import("../diag.zig").Error;
pub const Chi = struct { statistic: f64, df: f64, p: f64 };
pub const Normal = struct { statistic: f64, z: f64, p_one: f64, p_two: f64 };

fn sq(x: f64) f64 {
    return x * x;
}
fn normal(statistic: f64, z: f64) Normal {
    const p = @exp(fns.logStdNormTail(@abs(z)));
    return .{ .statistic = statistic, .z = z, .p_one = p, .p_two = 2 * p };
}
fn chi(x: f64, df: f64) Chi {
    return .{ .statistic = x, .df = df, .p = chiTail(x, df) };
}
fn validate(m: Matrix) Error!f64 {
    const size = std.math.mul(usize, m.rows, m.cols) catch return error.ExecError;
    if (size != m.counts.len or m.rows == 0 or m.cols == 0) return error.ExecError;
    var n: f64 = 0;
    for (m.counts) |x| {
        if (!std.math.isFinite(x) or x < 0) return error.ExecError;
        n += x;
    }
    if (!std.math.isFinite(n)) return error.ExecError;
    if (m.row_scores) |s| try validateScores(s, m.rows);
    if (m.col_scores) |s| try validateScores(s, m.cols);
    return n;
}
fn validateScores(s: []const f64, n: usize) Error!void {
    if (s.len != n) return error.ExecError;
    for (s) |x| if (!std.math.isFinite(x)) return error.ExecError;
}
fn score(s: ?[]const f64, i: usize) f64 {
    return if (s) |v| v[i] else @as(f64, @floatFromInt(i + 1));
}
const Margins = struct { rows: []f64, cols: []f64 };
fn margins(a: std.mem.Allocator, m: Matrix) Error!Margins {
    const r = try a.alloc(f64, m.rows);
    errdefer a.free(r);
    const c = try a.alloc(f64, m.cols);
    @memset(r, 0);
    @memset(c, 0);
    for (m.counts, 0..) |x, k| {
        r[k / m.cols] += x;
        c[k % m.cols] += x;
    }
    return .{ .rows = r, .cols = c };
}

/// Signed Cochran-Armitage statistic; 2x2 uses the row explanatory variable.
/// This is also an EXACT TREND callback: margins fix its denominator.
pub fn trend(m: Matrix) Error!?Normal {
    const n = try validate(m);
    if (m.cols != 2 and m.rows != 2) return null;
    if (n <= 0) return null;
    const by_row = m.cols == 2;
    const len = if (by_row) m.rows else m.cols;
    const scores = if (by_row) m.row_scores else m.col_scores;
    var successes: f64 = 0;
    var weighted: f64 = 0;
    for (0..len) |i| {
        const x = if (by_row) m.counts[i * 2] else m.counts[i];
        const y = if (by_row) m.counts[i * 2 + 1] else m.counts[m.cols + i];
        successes += x;
        weighted += (x + y) * score(scores, i);
    }
    const mean = weighted / n;
    var numerator: f64 = 0;
    var ss: f64 = 0;
    for (0..len) |i| {
        const x = if (by_row) m.counts[i * 2] else m.counts[i];
        const y = if (by_row) m.counts[i * 2 + 1] else m.counts[m.cols + i];
        const delta = score(scores, i) - mean;
        numerator += x * delta;
        ss += (x + y) * sq(delta);
    }
    const variance = (successes / n) * (1 - successes / n) * ss;
    if (variance <= 0) return null;
    const z = numerator / @sqrt(variance);
    return normal(z, z);
}

/// Unstandardized J, suitable for EXACT JT. Scores do not change ordered pairs.
pub fn jonckheereStatistic(m: Matrix) Error!f64 {
    _ = try validate(m);
    var j: f64 = 0;
    for (0..m.rows) |r| for (r + 1..m.rows) |s| {
        var below: f64 = 0;
        for (0..m.cols) |c| {
            const x = m.counts[r * m.cols + c];
            j += m.counts[s * m.cols + c] * (below + x / 2);
            below += x;
        }
    };
    return j;
}
pub fn jonckheere(a: std.mem.Allocator, m: Matrix) Error!?Normal {
    const n = try validate(m);
    if (n <= 1 or m.rows < 2 or m.cols < 2) return null;
    const totals = try margins(a, m);
    defer a.free(totals.rows);
    defer a.free(totals.cols);
    var aa = n * (n - 1) * (2 * n + 5);
    var r2: f64 = 0;
    var c2: f64 = 0;
    var r3: f64 = 0;
    var c3: f64 = 0;
    var mean = n * n;
    for (totals.rows) |x| {
        aa -= x * (x - 1) * (2 * x + 5);
        r2 += x * (x - 1);
        r3 += x * (x - 1) * (x - 2);
        mean -= x * x;
    }
    for (totals.cols) |x| {
        aa -= x * (x - 1) * (2 * x + 5);
        c2 += x * (x - 1);
        c3 += x * (x - 1) * (x - 2);
    }
    const variance = aa / 72 + r2 * c2 / (8 * n * (n - 1)) + (if (n > 2) r3 * c3 / (36 * n * (n - 1) * (n - 2)) else 0);
    if (variance <= 0) return null;
    const j = try jonckheereStatistic(m);
    return normal(j, (j - mean / 4) / @sqrt(variance));
}

pub fn mcnemar(m: Matrix, null_ratio: f64) Error!?Chi {
    _ = try validate(m);
    if (!(null_ratio > 0) or !std.math.isFinite(null_ratio)) return error.ExecError;
    if (m.rows != 2 or m.cols != 2) return null;
    const b = m.counts[1];
    const c = m.counts[2];
    const d = b + c;
    if (d == 0) return null;
    const eb = d / (1 + 1 / null_ratio);
    const ec = d / (1 + null_ratio);
    return chi(sq(b - eb) / eb + sq(c - ec) / ec, 1);
}
pub const SymmetryDf = union(enum) { default, adjust, value: f64 };
pub fn bowker(m: Matrix, degrees: SymmetryDf) Error!?Chi {
    _ = try validate(m);
    if (degrees == .value and (!(degrees.value > 0) or !std.math.isFinite(degrees.value))) return error.ExecError;
    if (m.rows != m.cols or m.rows < 2) return null;
    var x: f64 = 0;
    var used: f64 = 0;
    for (0..m.rows) |i| for (i + 1..m.cols) |j| {
        const b = m.counts[i * m.cols + j];
        const c = m.counts[j * m.cols + i];
        if (b + c > 0) {
            x += sq(b - c) / (b + c);
            used += 1;
        }
    };
    const df = switch (degrees) {
        .default => @as(f64, @floatFromInt(m.rows * (m.rows - 1))) / 2,
        .adjust => used,
        .value => |v| v,
    };
    if (df <= 0) return null;
    return chi(x, df);
}

pub const Estimate = struct { value: f64, variance: f64, lower: f64, upper: f64 };
fn estimate(value: f64, variance: f64, alpha: f64) Estimate {
    const d = -fns.distQuantile(.normal, alpha / 2, &.{}).? * @sqrt(@max(0, variance));
    return .{ .value = value, .variance = @max(0, variance), .lower = value - d, .upper = value + d };
}
pub const KappaWeight = enum { simple, cicchetti_allison, fleiss_cohen };
pub fn kappaWeights(a: std.mem.Allocator, m: Matrix, kind: KappaWeight) Error![]f64 {
    _ = try validate(m);
    if (m.rows != m.cols or m.rows < 2) return error.ExecError;
    const span = score(m.col_scores, m.cols - 1) - score(m.col_scores, 0);
    if (kind != .simple and span == 0) return error.ExecError;
    const w = try a.alloc(f64, m.counts.len);
    for (w, 0..) |*v, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        const delta = if (kind == .simple) 0 else (score(m.col_scores, i) - score(m.col_scores, j)) / span;
        v.* = switch (kind) {
            .simple => if (i == j) 1 else 0,
            .cicchetti_allison => 1 - @abs(delta),
            .fleiss_cohen => 1 - sq(delta),
        };
        if (v.* < 0 or v.* > 1) {
            a.free(w);
            return error.ExecError;
        }
    }
    return w;
}
pub const Kappa = struct { coefficient: Estimate, null_variance: f64, test_result: ?Normal, observed: f64, expected: f64 };
/// Same numeric entry point serves exact coefficient callbacks with fixed margins.
pub fn kappa(a: std.mem.Allocator, m: Matrix, kind: KappaWeight, alpha: f64, null_value: f64) Error!?Kappa {
    const n = try validate(m);
    if (!(alpha > 0 and alpha < 1) or !std.math.isFinite(null_value) or @abs(null_value) > 1) return error.ExecError;
    if (n == 0 or m.rows != m.cols or m.rows < 2) return null;
    const t = try margins(a, m);
    defer a.free(t.rows);
    defer a.free(t.cols);
    const w = try kappaWeights(a, m, kind);
    defer a.free(w);
    const wr = try a.alloc(f64, m.rows);
    defer a.free(wr);
    @memset(wr, 0);
    const wc = try a.alloc(f64, m.cols);
    defer a.free(wc);
    @memset(wc, 0);
    var po: f64 = 0;
    var pe: f64 = 0;
    for (w, 0..) |v, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        po += v * m.counts[k] / n;
        pe += v * (t.rows[i] / n) * (t.cols[j] / n);
        wr[i] += v * t.cols[j] / n;
        wc[j] += v * t.rows[i] / n;
    }
    if (pe >= 1) return null;
    const kap = (po - pe) / (1 - pe);
    var v: f64 = 0;
    var v0: f64 = 0;
    for (w, 0..) |weight, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        v += m.counts[k] / n * sq(weight - (wr[i] + wc[j]) * (1 - kap));
        v0 += (t.rows[i] / n) * (t.cols[j] / n) * sq(weight - wr[i] - wc[j]);
    }
    v = @max(0, v - sq(kap - pe * (1 - kap))) / (n * sq(1 - pe));
    v0 = @max(0, v0 - pe * pe) / (n * sq(1 - pe));
    const test_variance = if (null_value == 0) v0 else v;
    return .{ .coefficient = estimate(kap, v, alpha), .null_variance = v0, .test_result = if (test_variance > 0) normal(kap, (kap - null_value) / @sqrt(test_variance)) else null, .observed = po, .expected = pe };
}

pub const Pooled = struct { coefficient: Estimate, homogeneity: ?Chi, strata: usize };
/// Invalid/zero-variance strata must be resolved by the caller, never silently
/// included as zero-weight contributions to a supposedly common estimate.
pub fn pool(estimates: []const Estimate, alpha: f64) Error!?Pooled {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    if (estimates.len == 0) return null;
    var numerator: f64 = 0;
    var precision: f64 = 0;
    for (estimates) |e| {
        if (!std.math.isFinite(e.value) or !std.math.isFinite(e.variance) or e.variance <= 0) return null;
        numerator += e.value / e.variance;
        precision += 1 / e.variance;
    }
    const value = numerator / precision;
    var q: f64 = 0;
    for (estimates) |e| {
        q += sq(e.value - value) / e.variance;
    }
    return .{ .coefficient = estimate(value, 1 / precision, alpha), .homogeneity = if (estimates.len > 1) chi(q, @floatFromInt(estimates.len - 1)) else null, .strata = estimates.len };
}

/// SAS agreement pooling excludes undefined and exactly zero-variance kappas.
/// Keep original slots nullable; this is deliberately separate from generic
/// pool(), whose risk/logit callers must not silently discard invalid estimates.
/// All-excluded => no overall table. One retained stratum => Q=0, DF=0, p missing.
pub fn poolKappa(estimates: []const ?Estimate, alpha: f64) Error!?Pooled {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    var minimum_variance = std.math.inf(f64);
    var used: usize = 0;
    for (estimates) |maybe| if (maybe) |e| {
        if (!std.math.isFinite(e.value) or !std.math.isFinite(e.variance) or e.variance < 0) return error.ExecError;
        if (e.variance == 0) continue;
        minimum_variance = @min(minimum_variance, e.variance);
        used += 1;
    };
    if (used == 0) return null;
    // Scale precisions to avoid overflowing 1/variance for near-perfect tables;
    // positive variances are never discarded using an arbitrary epsilon.
    var numerator: f64 = 0;
    var precision: f64 = 0;
    for (estimates) |maybe| if (maybe) |e| {
        if (e.variance == 0) continue;
        const w = minimum_variance / e.variance;
        numerator += w * e.value;
        precision += w;
    };
    const value = numerator / precision;
    var q: f64 = 0;
    for (estimates) |maybe| if (maybe) |e| {
        if (e.variance > 0) q += sq(e.value - value) / e.variance;
    };
    return .{
        .coefficient = estimate(value, minimum_variance / precision, alpha),
        .homogeneity = if (used == 1) .{ .statistic = 0, .df = 0, .p = std.math.nan(f64) } else chi(q, @floatFromInt(used - 1)),
        .strata = used,
    };
}

/// Binary Cartesian cells, last variable varies fastest; this is the original
/// multiway table, NOT merely the last two dimensions' stratified margins.
pub const CochranAccumulator = struct {
    totals: []f64,
    total_positive: f64 = 0,
    discordance: f64 = 0,

    pub fn init(a: std.mem.Allocator, variables: usize) Error!CochranAccumulator {
        if (variables < 2) return error.ExecError;
        const totals = try a.alloc(f64, variables);
        @memset(totals, 0);
        return .{ .totals = totals };
    }
    pub fn deinit(self: CochranAccumulator, a: std.mem.Allocator) void {
        a.free(self.totals);
    }
    /// Feed each observed pattern once with its frequency. True means the
    /// first level of that binary dimension. O(variables) storage, independent
    /// of the Cartesian table size; supports more variables than machine bits.
    /// Rejected patterns leave the accumulator unchanged.
    pub fn add(self: *CochranAccumulator, first_levels: []const bool, frequency: f64) Error!void {
        if (first_levels.len != self.totals.len or !std.math.isFinite(frequency) or frequency < 0) return error.ExecError;
        var positive: f64 = 0;
        for (first_levels, self.totals) |first, total| if (first) {
            positive += 1;
            if (!std.math.isFinite(total + frequency)) return error.ExecError;
        };
        const m: f64 = @floatFromInt(self.totals.len);
        const total = self.total_positive + frequency * positive;
        const discordance = self.discordance + frequency * positive * (m - positive);
        if (!std.math.isFinite(total) or !std.math.isFinite(discordance)) return error.ExecError;
        for (first_levels, self.totals) |first, *t| if (first) {
            t.* += frequency;
        };
        self.total_positive = total;
        self.discordance = discordance;
    }
    /// Adapter for existing sparse Table binary keys: last dimension varies
    /// fastest; zero bit means first level. Wider patterns use add() directly.
    pub fn addKey(self: *CochranAccumulator, key: usize, frequency: f64) Error!void {
        const width = @bitSizeOf(usize);
        if (self.totals.len > width) return error.ExecError;
        if (self.totals.len < width and key >> @intCast(self.totals.len) != 0) return error.ExecError;
        var first: [width]bool = undefined;
        for (first[0..self.totals.len], 0..) |*v, j| v.* = key & (@as(usize, 1) << @intCast(self.totals.len - 1 - j)) == 0;
        try self.add(first[0..self.totals.len], frequency);
    }
    pub fn finish(self: CochranAccumulator) Error!?Chi {
        if (self.discordance == 0) return null;
        const m: f64 = @floatFromInt(self.totals.len);
        const mean = self.total_positive / m;
        var ss: f64 = 0;
        for (self.totals) |t| ss += sq(t - mean);
        const q = (m - 1) * m * ss / self.discordance;
        if (!std.math.isFinite(q)) return error.ExecError;
        return chi(q, m - 1);
    }
};

pub fn cochranQ(a: std.mem.Allocator, variables: usize, counts: []const f64) Error!?Chi {
    if (variables < 2 or variables >= @bitSizeOf(usize)) return error.ExecError;
    const size = @as(usize, 1) << @intCast(variables);
    if (counts.len != size) return error.ExecError;
    var accumulator = try CochranAccumulator.init(a, variables);
    defer accumulator.deinit(a);
    for (counts, 0..) |frequency, key| try accumulator.addKey(key, frequency);
    return accumulator.finish();
}

// Same stable gamma tail as the existing FREQ kernel; consolidate when the
// manager grants shared math ownership. Uses the existing gamma/log-gamma core.
fn chiTail(x: f64, df: f64) f64 {
    const a = df / 2;
    const z = x / 2;
    if (z < a + 1) return @max(0, 1 - fns.gammaP(a, z));
    const tiny: f64 = 1e-300;
    var b = z + 1 - a;
    var c: f64 = 1 / tiny;
    var d = 1 / b;
    var h = d;
    for (1..10000) |k| {
        const i: f64 = @floatFromInt(k);
        const an = -i * (i - a);
        b += 2;
        d = an * d + b;
        if (@abs(d) < tiny) d = tiny;
        c = b + an / c;
        if (@abs(c) < tiny) c = tiny;
        d = 1 / d;
        const delta = d * c;
        h *= delta;
        if (@abs(delta - 1) < 1e-15) break;
    }
    return @max(0, @min(1, @exp(-z + a * @log(z) - fns.lgammaOf(a)) * h));
}

pub const CmhKind = enum { correlation, row_mean, general };
/// Each stratum MUST retain the same global row/column level slots, including
/// zero marginals. Scores can differ by stratum (RANK/RIDIT). Empty strata add
/// no information; singular aggregate covariance yields an undefined statistic.
pub fn cmh(a: std.mem.Allocator, strata: []const Matrix, kind: CmhKind) Error!?Chi {
    if (strata.len == 0) return null;
    const rows = strata[0].rows;
    const cols = strata[0].cols;
    if (rows < 2 or cols < 2) return null;
    const nr = if (kind == .correlation) 1 else rows - 1;
    const nc = if (kind == .general) cols - 1 else 1;
    const d = std.math.mul(usize, nr, nc) catch return error.OutOfMemory;
    const dd = std.math.mul(usize, d, d) catch return error.OutOfMemory;
    const g = try a.alloc(f64, d);
    defer a.free(g);
    @memset(g, 0);
    const cov = try a.alloc(f64, dd);
    defer a.free(cov);
    @memset(cov, 0);
    const mr = try a.alloc(f64, nr);
    defer a.free(mr);
    const mc = try a.alloc(f64, nc);
    defer a.free(mc);
    for (strata) |m| {
        const n = try validate(m);
        if (m.rows != rows or m.cols != cols) return error.ExecError;
        if (n <= 1) continue;
        const t = try margins(a, m);
        defer a.free(t.rows);
        defer a.free(t.cols);
        @memset(mr, 0);
        @memset(mc, 0);
        for (0..nr) |u| for (0..rows) |i| {
            mr[u] += t.rows[i] / n * contrast(m.row_scores, i, u, kind == .correlation);
        };
        for (0..nc) |v| for (0..cols) |j| {
            mc[v] += t.cols[j] / n * contrast(m.col_scores, j, v, kind != .general);
        };
        for (0..d) |uv| {
            const u = uv / nc;
            const v = uv % nc;
            for (m.counts, 0..) |x, k| {
                g[uv] += x * (contrast(m.row_scores, k / cols, u, kind == .correlation) - mr[u]) * (contrast(m.col_scores, k % cols, v, kind != .general) - mc[v]);
            }
            for (0..d) |st| {
                const s = st / nc;
                const tcol = st % nc;
                var vr: f64 = 0;
                var vc: f64 = 0;
                for (0..rows) |i| {
                    vr += t.rows[i] / n * (contrast(m.row_scores, i, u, kind == .correlation) - mr[u]) * (contrast(m.row_scores, i, s, kind == .correlation) - mr[s]);
                }
                for (0..cols) |j| {
                    vc += t.cols[j] / n * (contrast(m.col_scores, j, v, kind != .general) - mc[v]) * (contrast(m.col_scores, j, tcol, kind != .general) - mc[tcol]);
                }
                cov[uv * d + st] += n * n / (n - 1) * vr * vc;
            }
        }
    }
    // Cholesky of the covariance correlation matrix avoids a dimensionful
    // singularity threshold when TABLE scores have very different scales.
    const scale = try a.alloc(f64, d);
    defer a.free(scale);
    for (0..d) |i| {
        if (cov[i * d + i] <= 0) return null;
        scale[i] = @sqrt(cov[i * d + i]);
    }
    for (0..d) |i| {
        g[i] /= scale[i];
        for (0..d) |j| {
            cov[i * d + j] /= scale[i] * scale[j];
        }
    }
    var result: f64 = 0;
    for (0..d) |i| {
        for (0..i + 1) |j| {
            var value = cov[i * d + j];
            for (0..j) |k| {
                value -= cov[i * d + k] * cov[j * d + k];
            }
            if (i == j) {
                if (value <= 64 * std.math.floatEps(f64)) return null;
                cov[i * d + j] = @sqrt(value);
            } else {
                cov[i * d + j] = value / cov[j * d + j];
            }
        }
        for (0..i) |j| {
            g[i] -= cov[i * d + j] * g[j];
        }
        g[i] /= cov[i * d + i];
        result += g[i] * g[i];
    }
    return chi(result, @floatFromInt(d));
}
fn contrast(scores: ?[]const f64, level: usize, index: usize, scored: bool) f64 {
    return if (scored) score(scores, level) else if (level == index) 1 else 0;
}

pub fn mantelFleiss(strata: []const Matrix) Error!?f64 {
    var lower: f64 = 0;
    var upper: f64 = 0;
    var used = false;
    for (strata) |m| {
        const n = try validate(m);
        if (m.rows != 2 or m.cols != 2) return error.ExecError;
        if (n == 0) continue;
        const r = m.counts[0] + m.counts[1];
        const c = m.counts[0] + m.counts[2];
        const expected = r * c / n;
        lower += expected - @max(0, r + c - n);
        upper += @min(r, c) - expected;
        used = true;
    }
    return if (used) @min(lower, upper) else null;
}

pub const GailSimon = struct { positive: f64, negative: f64, two_sided: f64, p_positive: f64, p_negative: f64, p_two: f64 };
/// Risk adapter supplies actual differences and their unpooled variances. This
/// primitive is shared with FEAT-freq-risk without imposing its zero-cell policy.
pub fn gailSimon(differences: []const Estimate) Error!?GailSimon {
    if (differences.len < 2) return null;
    var pos: f64 = 0;
    var neg: f64 = 0;
    for (differences) |e| {
        if (!std.math.isFinite(e.value) or !std.math.isFinite(e.variance)) return error.ExecError;
        if (e.variance <= 0) return null;
        if (e.value > 0) pos += sq(e.value) / e.variance else if (e.value < 0) {
            neg += sq(e.value) / e.variance;
        }
    }
    const q = @min(pos, neg);
    return .{ .positive = pos, .negative = neg, .two_sided = q, .p_positive = mixtureTail(pos, differences.len), .p_negative = mixtureTail(neg, differences.len), .p_two = mixtureTail(q, differences.len - 1) };
}
fn mixtureTail(q: f64, n: usize) f64 {
    var p: f64 = 0;
    const nf: f64 = @floatFromInt(n);
    for (1..n + 1) |h| {
        const hf: f64 = @floatFromInt(h);
        const weight = @exp(fns.lgammaOf(nf + 1) - fns.lgammaOf(hf + 1) - fns.lgammaOf(nf - hf + 1) - nf * @log(@as(f64, 2)));
        p += weight * chiTail(q, hf);
    }
    return @min(1, p);
}

test "stratified asymmetric SAS trend JT symmetry and kappa" {
    // SAS/STAT pp.209–217. Independent oracle: kernels.sas, command:
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-stratified/kernels.sas -f text -o /tmp/opensas-stat-batch2/FEAT-freq-stratified/kernels.txt -l /tmp/opensas-stat-batch2/FEAT-freq-stratified/kernels.log
    // SAS prints four decimals; tolerance is half a printed unit, not fitted.
    const a = std.testing.allocator;
    const m: Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 18, 3, 1, 7, 12, 4, 2, 9, 24 } };
    const jt = (try jonckheere(a, m)).?;
    try std.testing.expectEqual(@as(f64, 1720.5), jt.statistic);
    try std.testing.expectApproxEqAbs(@as(f64, 6.4430), jt.z, 0.00005);
    const b = (try bowker(m, .default)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 3.8564), b.statistic, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2774), b.p, 0.00005);
    const k = (try kappa(a, m, .simple, 0.05, 0)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.5093), k.coefficient.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0776), @sqrt(k.coefficient.variance), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 6.4731), k.test_result.?.z, 0.00005);
    const ca = (try kappa(a, m, .cicchetti_allison, 0.05, 0)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.6015), ca.coefficient.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 6.7639), ca.test_result.?.z, 0.00005);
    const fc = (try kappa(a, m, .fleiss_cohen, 0.05, 0.3)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.6885), fc.coefficient.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 5.6165), fc.test_result.?.z, 0.00005);
    const t: Matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 8, 17, 12, 11, 20, 4 }, .row_scores = &.{ 1, 3, 8 } };
    try std.testing.expectApproxEqAbs(@as(f64, 3.6114), (try trend(t)).?.z, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -3.5824), (try jonckheere(a, t)).?.z, 0.00005);
    const kinds = [_]CmhKind{ .correlation, .row_mean, .general };
    for (kinds, [_]f64{ 38.4782, 38.5557, 47.0823 }) |kind, expected| {
        try std.testing.expectApproxEqAbs(expected, (try cmh(a, &.{m}, kind)).?.statistic, 0.00005);
    }
}

test "stratified manual examples 3.7 and 3.10 plus order and empty strata" {
    // Manual pp.270–272 and 277–279; independently rerun in kernels.sas.
    const a = std.testing.allocator;
    const first: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 16, 11, 5, 20 } };
    const second: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 12, 16, 7, 19 } };
    const empty: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } };
    for ([_]CmhKind{ .correlation, .row_mean, .general }) |kind| {
        const result = (try cmh(a, &.{ first, second }, kind)).?;
        try std.testing.expectApproxEqAbs(@as(f64, 8.3052), result.statistic, 0.00005);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0040), result.p, 0.00005);
        try std.testing.expectApproxEqAbs(result.statistic, (try cmh(a, &.{ empty, second, first }, kind)).?.statistic, 1e-12);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 19.2443), (try mantelFleiss(&.{ first, second })).?, 0.00005);
    const d1: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 6, 16, 2, 4 } };
    const d2: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 2, 4, 6, 6 } };
    try std.testing.expectApproxEqAbs(@as(f64, 10.8889), (try mcnemar(d1, 1)).?.statistic, 0.00005);
    const k1 = (try kappa(a, d1, .simple, 0.05, 0)).?;
    const k2 = (try kappa(a, d2, .simple, 0.05, 0)).?;
    const pooled = (try pool(&.{ k1.coefficient, k2.coefficient }, 0.05)).?;
    try std.testing.expectApproxEqAbs(@as(f64, -0.0588), pooled.coefficient.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1034), @sqrt(pooled.coefficient.variance), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2314), pooled.homogeneity.?.statistic, 0.00005);
    const q = (try cochranQ(a, 3, &.{ 6, 16, 2, 4, 2, 4, 6, 6 })).?;
    try std.testing.expectApproxEqAbs(@as(f64, 8.4706), q.statistic, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0145), q.p, 0.00005);
    const gs = (try gailSimon(&.{ estimate(16.0 / 27.0 - 5.0 / 25.0, (16.0 / 27.0) * (11.0 / 27.0) / 27.0 + (5.0 / 25.0) * (20.0 / 25.0) / 25.0, 0.05), estimate(12.0 / 28.0 - 7.0 / 26.0, (12.0 / 28.0) * (16.0 / 28.0) / 28.0 + (7.0 / 26.0) * (19.0 / 26.0) / 26.0, 0.05) })).?;
    try std.testing.expectApproxEqAbs(@as(f64, 11.6027), gs.positive, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0011), gs.p_positive, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.75), gs.p_negative, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), gs.p_two, 1e-12);
}

test "stratified undefined tables and invalid shapes remain explicit" {
    const a = std.testing.allocator;
    const empty: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 0, 0, 0, 0 } };
    try std.testing.expectEqual(@as(?Normal, null), try trend(empty));
    try std.testing.expectEqual(@as(?Chi, null), try mcnemar(empty, 1));
    try std.testing.expectEqual(@as(?Chi, null), try bowker(empty, .adjust));
    try std.testing.expectEqual(@as(?Chi, null), try cmh(a, &.{empty}, .general));
    try std.testing.expectEqual(@as(?Kappa, null), try kappa(a, empty, .simple, 0.05, 0));
    try std.testing.expectError(error.ExecError, trend(.{ .rows = 2, .cols = 2, .counts = &.{ 1, 2 } }));
    try std.testing.expectError(error.ExecError, trend(.{ .rows = 2, .cols = 2, .counts = &.{ 1, -2, 3, 4 } }));
    try std.testing.expectError(error.ExecError, mcnemar(empty, 0));
    try std.testing.expectError(error.ExecError, bowker(empty, .{ .value = 0 }));
    try std.testing.expectError(error.ExecError, cochranQ(a, 3, &.{ 1, 2 }));
}

pub const AgreementDetails = struct {
    observed: f64,
    expected: f64,
    maximum_kappa: ?f64,
    bn: ?f64,
    prevalence: ?f64,
    bias: ?f64,
    pabak: Estimate,
    ac1: ?Estimate,
};
pub fn agreementDetails(a: std.mem.Allocator, m: Matrix, alpha: f64) Error!?AgreementDetails {
    const n = try validate(m);
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    if (m.rows != m.cols or m.rows < 2 or n == 0) return null;
    const t = try margins(a, m);
    defer a.free(t.rows);
    defer a.free(t.cols);
    const r: f64 = @floatFromInt(m.rows);
    var po: f64 = 0;
    var pe: f64 = 0;
    var maximum: f64 = 0;
    var diagonal_sq: f64 = 0;
    var ac_expected: f64 = 0;
    for (0..m.rows) |i| {
        const diagonal = m.counts[i * m.cols + i] / n;
        po += diagonal;
        diagonal_sq += diagonal * diagonal;
        pe += (t.rows[i] / n) * (t.cols[i] / n);
        maximum += @min(t.rows[i], t.cols[i]) / n;
        const e = (t.rows[i] + t.cols[i]) / (2 * n);
        ac_expected += e * (1 - e) / (r - 1);
    }
    const ac = (po - ac_expected) / (1 - ac_expected);
    // Multinomial delta-method variance, equivalent to p.218; using centered
    // influence values avoids cancellation in nearly perfect-agreement tables.
    var mean_gradient: f64 = 0;
    var gradient_sq: f64 = 0;
    for (m.counts, 0..) |x, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        const ei = (t.rows[i] + t.cols[i]) / (2 * n);
        const ej = (t.rows[j] + t.cols[j]) / (2 * n);
        const dpe = (1 - ei - ej) / (r - 1);
        const dpo: f64 = if (i == j) 1 else 0;
        const gradient = (dpo - (1 - ac) * dpe) / (1 - ac_expected);
        mean_gradient += x / n * gradient;
        gradient_sq += x / n * gradient * gradient;
    }
    return .{
        .observed = po,
        .expected = pe,
        .maximum_kappa = if (pe < 1) (maximum - pe) / (1 - pe) else null,
        .bn = if (pe > 0) diagonal_sq / pe else null,
        .prevalence = if (m.rows == 2) @abs(m.counts[0] - m.counts[3]) / n else null,
        .bias = if (m.rows == 2) @abs(m.counts[1] - m.counts[2]) / n else null,
        .pabak = estimate((po - 1 / r) / (1 - 1 / r), sq(r / (r - 1)) * po * (1 - po) / n, alpha),
        .ac1 = if (ac_expected < 1) estimate(ac, @max(0, gradient_sq - sq(mean_gradient)) / n, alpha) else null,
    };
}

pub const BreslowDay = struct { unadjusted: Chi, tarone: Chi, strata: usize };
/// Risk kernel supplies the Mantel-Haenszel common OR. Unlike a conditional
/// hypergeometric mean, the fitted count solves the constrained cross-product
/// odds ratio; expected-count variance is the inverse sum of reciprocals.
pub fn breslowDay(strata: []const Matrix, common_odds: f64) Error!?BreslowDay {
    if (!(common_odds > 0) or !std.math.isFinite(common_odds)) return null;
    var q: f64 = 0;
    var residual: f64 = 0;
    var variance_sum: f64 = 0;
    var used: usize = 0;
    for (strata) |m| {
        const n = try validate(m);
        if (m.rows != 2 or m.cols != 2) return error.ExecError;
        const r = m.counts[0] + m.counts[1];
        const c = m.counts[0] + m.counts[2];
        if (r == 0 or c == 0 or r == n or c == n) continue;
        var lo = @max(0, r + c - n);
        var hi = @min(r, c);
        for (0..100) |_| {
            const mid = lo + (hi - lo) / 2;
            const cross = mid * (n - r - c + mid) - common_odds * (r - mid) * (c - mid);
            if (cross < 0) lo = mid else hi = mid;
        }
        const fitted = lo + (hi - lo) / 2;
        const v = 1 / (1 / fitted + 1 / (r - fitted) + 1 / (c - fitted) + 1 / (n - r - c + fitted));
        if (!(v > 0)) return null;
        const delta = m.counts[0] - fitted;
        q += delta * delta / v;
        residual += delta;
        variance_sum += v;
        used += 1;
    }
    if (used < 2) return null;
    const df: f64 = @floatFromInt(used - 1);
    return .{ .unadjusted = chi(q, df), .tarone = chi(@max(0, q - sq(residual) / variance_sum), df), .strata = used };
}

pub const Heterogeneity = struct { percent: f64, lower: f64, upper: f64 };
/// Input Q is the inverse-variance homogeneity statistic of log odds ratios.
pub fn iSquare(q: Chi, alpha: f64) Error!?Heterogeneity {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    if (!(q.df > 0) or q.statistic < 0 or !std.math.isFinite(q.statistic)) return null;
    const k = q.df + 1;
    const x = q.statistic;
    if (x == 0) return null; // logarithmic uncertainty limits undefined
    const h = @sqrt(x / q.df);
    const se = if (x > k or k == 2) (@log(x) - @log(q.df)) / (2 * (@sqrt(2 * x) - @sqrt(2 * k - 3))) else @sqrt((1 - 1 / (3 * sq(k - 2))) / (2 * (k - 2)));
    const percent = @max(0, 100 * (x - q.df) / x);
    const z = fns.distQuantile(.normal, 1 - alpha / (if (percent == 0) @as(f64, 1) else 2), &.{}).?;
    return .{ .percent = percent, .lower = if (percent == 0) 0 else @max(0, 100 * (1 - 1 / sq(h * @exp(-z * se)))), .upper = @max(0, 100 * (1 - 1 / sq(h * @exp(z * se)))) };
}

test "stratified agreement details and homogeneity oracle" {
    const a = std.testing.allocator;
    const m: Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 18, 3, 1, 7, 12, 4, 2, 9, 24 } };
    const d = (try agreementDetails(a, m, 0.05)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.8868), d.maximum_kappa.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4831), d.bn.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5125), d.pabak.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0785), @sqrt(d.pabak.variance), 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5150), d.ac1.?.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0788), @sqrt(d.ac1.?.variance), 0.00005);
    const strata = [_]Matrix{
        .{ .rows = 2, .cols = 2, .counts = &.{ 16, 11, 5, 20 } },
        .{ .rows = 2, .cols = 2, .counts = &.{ 12, 16, 7, 19 } },
    };
    // Exact unrounded MH OR from these published cell frequencies, not rounded 3.3132.
    const odds: f64 = (16.0 * 20.0 / 52.0 + 12.0 * 19.0 / 54.0) / (11.0 * 5.0 / 52.0 + 16.0 * 7.0 / 54.0);
    const bd = (try breslowDay(&strata, odds)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1.4929), bd.unadjusted.statistic, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.4905), bd.tarone.statistic, 0.00005);
    var logs: [2]Estimate = undefined;
    for (strata, 0..) |s, i| {
        const c = s.counts;
        logs[i] = estimate(@log(c[0] * c[3] / (c[1] * c[2])), 1 / c[0] + 1 / c[1] + 1 / c[2] + 1 / c[3], 0.05);
    }
    const pooled = (try pool(&logs, 0.05)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 1.4808), pooled.homogeneity.?.statistic, 0.00005);
    const hetero = (try iSquare(pooled.homogeneity.?, 0.05)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 32.47), hetero.percent, 0.005);
    try std.testing.expectApproxEqAbs(@as(f64, 76.77), hetero.upper, 0.005);
}

pub const Ratio = struct { value: f64, log_variance: ?f64, lower: ?f64, upper: ?f64 };
pub const CommonRatios = struct { odds: ?Ratio, column1: ?Ratio, column2: ?Ratio };
fn ratio(numerator: f64, denominator: f64, log_variance: f64, alpha: f64) ?Ratio {
    if (denominator <= 0) return null;
    const value = numerator / denominator;
    if (numerator <= 0 or !std.math.isFinite(log_variance)) return .{ .value = value, .log_variance = null, .lower = null, .upper = null };
    const z = -fns.distQuantile(.normal, alpha / 2, &.{}).?;
    const width = z * @sqrt(@max(0, log_variance));
    return .{ .value = value, .log_variance = @max(0, log_variance), .lower = value * @exp(-width), .upper = value * @exp(width) };
}
/// MH estimators use raw counts, without the zero-cell correction used by the
/// logit estimators. Logit pooling uses pool() on FEAT-freq-risk log estimates.
pub fn mantelHaenszelRatios(strata: []const Matrix, alpha: f64) Error!CommonRatios {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    var r: f64 = 0;
    var s: f64 = 0;
    var pr: f64 = 0;
    var psqr: f64 = 0;
    var qs: f64 = 0;
    var rr_num = [_]f64{ 0, 0 };
    var rr_den = [_]f64{ 0, 0 };
    var rr_v = [_]f64{ 0, 0 };
    for (strata) |m| {
        const n = try validate(m);
        if (m.rows != 2 or m.cols != 2) return error.ExecError;
        if (n == 0) continue;
        const c = m.counts;
        const rh = c[0] * c[3] / n;
        const sh = c[1] * c[2] / n;
        const ph = (c[0] + c[3]) / n;
        const qh = (c[1] + c[2]) / n;
        r += rh;
        s += sh;
        pr += ph * rh;
        psqr += ph * sh + qh * rh;
        qs += qh * sh;
        const r1 = c[0] + c[1];
        const r2 = c[2] + c[3];
        for (0..2) |j| {
            rr_num[j] += c[j] * r2 / n;
            rr_den[j] += c[2 + j] * r1 / n;
            rr_v[j] += (r1 * r2 * (c[j] + c[2 + j]) - c[j] * c[2 + j] * n) / (n * n);
        }
    }
    return .{
        .odds = ratio(r, s, pr / (2 * r * r) + psqr / (2 * r * s) + qs / (2 * s * s), alpha),
        .column1 = ratio(rr_num[0], rr_den[0], rr_v[0] / (rr_num[0] * rr_den[0]), alpha),
        .column2 = ratio(rr_num[1], rr_den[1], rr_v[1] / (rr_num[1] * rr_den[1]), alpha),
    };
}

test "stratified pooled MH ratios example 3.7" {
    const strata = [_]Matrix{
        .{ .rows = 2, .cols = 2, .counts = &.{ 16, 11, 5, 20 } },
        .{ .rows = 2, .cols = 2, .counts = &.{ 12, 16, 7, 19 } },
    };
    const ratios = try mantelHaenszelRatios(&strata, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 3.3132), ratios.odds.?.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.4456), ratios.odds.?.lower.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 7.5934), ratios.odds.?.upper.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 2.1636), ratios.column1.?.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.2336), ratios.column1.?.lower.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 3.7948), ratios.column1.?.upper.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6420), ratios.column2.?.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4705), ratios.column2.?.lower.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8761), ratios.column2.?.upper.?, 0.00005);
}

test "stratified manual examples 3.8 and 3.9" {
    // examples.sas independently reruns manual pp.272–276; output Z=-4.7918,
    // correlation=0.2400 and Friedman row mean=6.4500, p=0.0917.
    const a = std.testing.allocator;
    const pain: Matrix = .{ .rows = 2, .cols = 5, .counts = &.{ 26, 26, 23, 18, 9, 6, 7, 9, 14, 23 }, .col_scores = &.{ 0, 1, 2, 3, 4 } };
    try std.testing.expectApproxEqAbs(@as(f64, -4.7918), (try trend(pain)).?.z, 0.00005);
    // Sorted row levels calmness,fear,joy,sadness; responses ranked within
    // subject. Empty global response levels do not change the rank contrasts.
    const responses = [_][4]f64{
        .{ 22.6, 23.1, 22.7, 22.5 }, .{ 53.1, 57.6, 53.2, 53.7 },
        .{ 8.3, 10.5, 9.7, 10.8 },   .{ 21.6, 23.6, 19.6, 21.1 },
        .{ 13.3, 11.9, 13.8, 13.7 }, .{ 37.0, 54.6, 47.1, 39.2 },
        .{ 14.8, 21.0, 13.6, 13.7 }, .{ 14.8, 20.3, 23.6, 16.3 },
    };
    var cells: [8][16]f64 = undefined;
    var matrices: [8]Matrix = undefined;
    for (responses, 0..) |subject, s| {
        @memset(&cells[s], 0);
        for (subject, 0..) |response, row| {
            var rank: usize = 0;
            for (subject) |other| {
                if (other < response) rank += 1;
            }
            cells[s][row * 4 + rank] = 1;
        }
        matrices[s] = .{ .rows = 4, .cols = 4, .counts = &cells[s], .row_scores = &.{ 1, 2, 3, 4 }, .col_scores = &.{ 1, 2, 3, 4 } };
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0.24), (try cmh(a, &matrices, .correlation)).?.statistic, 1e-12);
    const friedman = (try cmh(a, &matrices, .row_mean)).?;
    try std.testing.expectApproxEqAbs(@as(f64, 6.45), friedman.statistic, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0917), friedman.p, 0.00005);
}

test "stratified sparse discordance and nonmonotone numeric scores SAS edges" {
    // edges.sas uses NOSYNTAXCHECK: the final nonmonotone-score error does not
    // mask preceding independent cases. SAS explicitly reports invalid kappa
    // weights (1,8,3 => w12=-2.5), while JT still reports J=1720.5.
    const a = std.testing.allocator;
    const diagonal: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 9, 0, 0, 6 } };
    try std.testing.expectEqual(@as(?Chi, null), try mcnemar(diagonal, 1));
    try std.testing.expectEqual(@as(f64, 1), (try kappa(a, diagonal, .simple, 0.05, 0)).?.coefficient.value);
    try std.testing.expectApproxEqAbs(@as(f64, -3.8730), (try trend(diagonal)).?.z, 0.00005);
    const matched: Matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 6, 16, 2, 4 } };
    const mc = (try mcnemar(matched, 2)).?;
    try std.testing.expectEqual(@as(f64, 4), mc.statistic);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0455), mc.p, 0.00005);
    const sparse: Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 5, 0, 2, 0, 4, 0, 3, 0, 6 } };
    const adjusted = (try bowker(sparse, .adjust)).?;
    try std.testing.expectEqual(@as(f64, 1), adjusted.df);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6547), adjusted.p, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.9530), (try bowker(sparse, .{ .value = 2.5 })).?.p, 0.00005);
    const nonmono: Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 18, 3, 1, 7, 12, 4, 2, 9, 24 }, .col_scores = &.{ 1, 8, 3 } };
    try std.testing.expectError(error.ExecError, kappaWeights(a, nonmono, .cicchetti_allison));
    try std.testing.expectEqual(@as(f64, 1720.5), try jonckheereStatistic(nonmono));
}

test "stratified sparse Cochran patterns preserve all binary dimensions" {
    const a = std.testing.allocator;
    var published = try CochranAccumulator.init(a, 3);
    defer published.deinit(a);
    for ([_]f64{ 6, 16, 2, 4, 2, 4, 6, 6 }, 0..) |frequency, key| try published.addKey(key, frequency);
    try std.testing.expectApproxEqAbs(@as(f64, 8.4706), (try published.finish()).?.statistic, 0.00005);
    var many = try CochranAccumulator.init(a, 1000);
    defer many.deinit(a);
    var first: [1000]bool = @splat(true);
    first[999] = false;
    try many.add(&first, 10);
    for (&first) |*x| x.* = !x.*;
    try many.add(&first, 20);
    @memset(&first, true);
    try many.add(&first, 7); // unanimous patterns carry no discordance
    const result = (try many.finish()).?;
    try std.testing.expectApproxEqAbs(@as(f64, 3330), result.statistic, 1e-9);
    try std.testing.expectEqual(@as(f64, 999), result.df);
    try std.testing.expectError(error.ExecError, many.add(&.{true}, 1));
    try std.testing.expectError(error.ExecError, many.add(&first, -1));
    try std.testing.expectEqual(result.statistic, (try many.finish()).?.statistic);
    // sparse_q.sas: 12 variables, three observed patterns, SAS Q=36.6667.
    var twelve = try CochranAccumulator.init(a, 12);
    defer twelve.deinit(a);
    try twelve.addKey(1, 10);
    try twelve.addKey(4094, 20);
    try twelve.addKey(0, 7);
    try std.testing.expectApproxEqAbs(@as(f64, 36.6667), (try twelve.finish()).?.statistic, 0.00005);
}

test "stratified pooled kappa excludes zero variance according to SAS" {
    // pooled_edges.sas and kappa_zero.sas, SAS/STAT pp218–219. Independent:
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-stratified/kappa_zero.sas -f text -o /tmp/opensas-stat-batch2/FEAT-freq-stratified/kappa_zero.txt -l /tmp/opensas-stat-batch2/FEAT-freq-stratified/kappa_zero.log
    const a = std.testing.allocator;
    const perfect = (try kappa(a, .{ .rows = 2, .cols = 2, .counts = &.{ 9, 0, 0, 6 } }, .simple, 0.05, 0)).?.coefficient;
    const other = (try kappa(a, .{ .rows = 2, .cols = 2, .counts = &.{ 6, 16, 2, 4 } }, .simple, 0.05, 0)).?.coefficient;
    try std.testing.expectEqual(@as(f64, 0), perfect.variance);
    const result = (try poolKappa(&.{ perfect, null, other }, 0.05)).?;
    try std.testing.expectApproxEqAbs(@as(f64, -0.0328), result.coefficient.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1167), @sqrt(result.coefficient.variance), 0.00005);
    try std.testing.expectEqual(@as(usize, 1), result.strata);
    try std.testing.expectEqual(@as(f64, 0), result.homogeneity.?.statistic);
    try std.testing.expectEqual(@as(f64, 0), result.homogeneity.?.df);
    try std.testing.expect(std.math.isNan(result.homogeneity.?.p));
    try std.testing.expectEqual(@as(?Pooled, null), try poolKappa(&.{ perfect, null, perfect }, 0.05));
    // Generic risk pooling remains strict.
    try std.testing.expectEqual(@as(?Pooled, null), try pool(&.{ perfect, other }, 0.05));
    const m: Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 18, 3, 1, 7, 12, 4, 2, 9, 24 } };
    const diagonal: Matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 8, 0, 0, 0, 7, 0, 0, 0, 9 } };
    for ([_]KappaWeight{ .simple, .fleiss_cohen }, [_]f64{ 0.5093, 0.6885 }, [_]f64{ 0.0776, 0.0692 }) |weight, value, se| {
        const zero = (try kappa(a, diagonal, weight, 0.05, 0)).?.coefficient;
        const nonzero = (try kappa(a, m, weight, 0.05, 0)).?.coefficient;
        const pooled = (try poolKappa(&.{ zero, nonzero }, 0.05)).?;
        try std.testing.expectApproxEqAbs(value, pooled.coefficient.value, 0.00005);
        try std.testing.expectApproxEqAbs(se, @sqrt(pooled.coefficient.variance), 0.00005);
        try std.testing.expectEqual(@as(usize, 1), pooled.strata);
    }
    const tiny = Estimate{ .value = 0.5, .variance = 1e-310, .lower = 0, .upper = 1 };
    const retained = (try poolKappa(&.{ tiny, tiny }, 0.05)).?;
    try std.testing.expectEqual(@as(usize, 2), retained.strata);
    try std.testing.expectEqual(@as(f64, 0.5), retained.coefficient.value);
    try std.testing.expect(retained.coefficient.variance > 0);
    try std.testing.expectError(error.ExecError, poolKappa(&.{.{ .value = 0, .variance = -1, .lower = 0, .upper = 0 }}, 0.05));
}

test "stratified pooled weighted kappa and CMH score families SAS" {
    // pooled_edges.sas: asymmetric strata distinguish RANK from RIDIT and
    // MODRIDIT scaling in CMH; weighted kappa is invariant to affine scores.
    const a = std.testing.allocator;
    const model = @import("freq_table.zig");
    const cells = [_][9]f64{ .{ 18, 3, 1, 7, 12, 4, 2, 9, 24 }, .{ 6, 4, 2, 1, 9, 5, 3, 2, 7 } };
    var levels: [3]model.Level = undefined;
    for (&levels, 0..) |*level, i| {
        const v: f64 = @floatFromInt(i + 1);
        level.* = .{ .value = .{ .num = v }, .raw = .{ .num = v }, .missing = false, .frequency = 0 };
    }
    for ([_]model.Score{ .rank, .ridit, .modridit }, [_]f64{ 41.7738, 39.4053, 39.6824 }, [_]f64{ 42.7748, 40.0260, 40.1487 }) |score_kind, correlation, row_mean| {
        var arena = std.heap.ArenaAllocator.init(a);
        defer arena.deinit();
        const allocator = arena.allocator();
        var matrices: [2]Matrix = undefined;
        var kappas: [2]?Estimate = undefined;
        for (&cells, 0..) |*counts, i| {
            matrices[i] = .{ .rows = 3, .cols = 3, .counts = counts };
            const t = try margins(allocator, matrices[i]);
            matrices[i].row_scores = try model.scores(allocator, &levels, t.rows, score_kind);
            matrices[i].col_scores = try model.scores(allocator, &levels, t.cols, score_kind);
            kappas[i] = (try kappa(allocator, matrices[i], .fleiss_cohen, 0.05, 0)).?.coefficient;
        }
        try std.testing.expectApproxEqAbs(correlation, (try cmh(allocator, &matrices, .correlation)).?.statistic, 0.00005);
        try std.testing.expectApproxEqAbs(row_mean, (try cmh(allocator, &matrices, .row_mean)).?.statistic, 0.00005);
        try std.testing.expectApproxEqAbs(@as(f64, 53.1239), (try cmh(allocator, &matrices, .general)).?.statistic, 0.00005);
        const pooled = (try poolKappa(&kappas, 0.05)).?;
        try std.testing.expectApproxEqAbs(@as(f64, 0.6326), pooled.coefficient.value, 0.00005);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0636), @sqrt(pooled.coefficient.variance), 0.00005);
        try std.testing.expectApproxEqAbs(@as(f64, 4.1285), pooled.homogeneity.?.statistic, 0.00005);
        try std.testing.expectApproxEqAbs(@as(f64, 0.0422), pooled.homogeneity.?.p, 0.00005);
        const reversed = [_]?Estimate{ kappas[1], kappas[0] };
        try std.testing.expectApproxEqAbs(pooled.coefficient.value, (try poolKappa(&reversed, 0.05)).?.coefficient.value, 1e-12);
    }
}
