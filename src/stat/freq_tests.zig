//! PROC FREQ numeric kernels. No lexer, dataset, or listing dependencies.
//! Input levels are already ordered by the table layer; counts include its
//! missing/weight policy. SAS/STAT FREQ pp. 161–175; oracle evidence in
//! docs/findings/freq-tests. Undefined statistics are null, never zero.
const std = @import("std");
const fns = @import("../functions.zig");
pub const Error = @import("../diag.zig").Error;

pub const CountMatrix = struct {
    rows: usize,
    cols: usize,
    counts: []const f64,
    row_scores: ?[]const f64 = null,
    col_scores: ?[]const f64 = null,
};
pub const Test = struct { statistic: f64, df: f64, p: f64 };
pub const Expected = union(enum) { equal, proportions: []const f64, frequencies: []const f64 };
pub const GoodnessOfFit = struct { pearson: Test, likelihood_ratio: Test, sparse: bool, total: f64 };
pub const Fisher = struct { probability: f64, left: f64, right: f64, two_sided: f64 };
pub const ChiSquare = struct {
    pearson: Test,
    likelihood_ratio: Test,
    mantel_haenszel: ?Test,
    continuity: ?Test,
    fisher: ?Fisher,
    phi: f64,
    contingency: f64,
    cramer_v: f64,
    sparse: bool,
    total: f64,
};

fn sq(x: f64) f64 {
    return x * x;
}
fn sum(xs: []const f64) f64 {
    var s: f64 = 0;
    for (xs) |x| s += x;
    return s;
}
fn countValid(xs: []const f64) bool {
    for (xs) |x| if (!std.math.isFinite(x) or x < 0) return false;
    return std.math.isFinite(sum(xs)) and sum(xs) > 0;
}
pub fn degreesOfFreedom(base: f64, override: ?f64) Error!f64 {
    const df = if (override) |d| (if (d > 0) d else base + d) else base;
    if (!std.math.isFinite(df) or df <= 0 or (override != null and override.? == 0)) return error.ExecError;
    return df;
}
fn chi(x: f64, df: f64) Test {
    return .{ .statistic = @max(0, x), .df = df, .p = chiTail(@max(0, x), df) };
}

pub fn goodnessOfFit(counts: []const f64, expected: Expected, df_override: ?f64) Error!GoodnessOfFit {
    if (counts.len < 2 or !countValid(counts)) return error.ExecError;
    const n = sum(counts);
    const df = try degreesOfFreedom(@floatFromInt(counts.len - 1), df_override);
    var factor: f64 = 1;
    switch (expected) {
        .equal => {},
        .proportions, .frequencies => |values| {
            if (values.len != counts.len) return error.ExecError;
            for (values) |v| if (!std.math.isFinite(v) or v <= 0) return error.ExecError;
            const total = sum(values);
            switch (expected) {
                .proportions => {
                    if (@abs(total - 1) < 1e-8) factor = n else if (@abs(total - 100) < 1e-6) factor = n / 100 else return error.ExecError;
                },
                .frequencies => if (@abs(total - n) > 1e-8 * @max(1, n)) {
                    return error.ExecError;
                },
                else => unreachable,
            }
        },
    }
    var pearson: f64 = 0;
    var lr: f64 = 0;
    var small: usize = 0;
    for (counts, 0..) |o, i| {
        const e = switch (expected) {
            .equal => n / @as(f64, @floatFromInt(counts.len)),
            .proportions, .frequencies => |v| v[i] * factor,
        };
        pearson += sq(o - e) / e;
        if (o > 0) lr += 2 * o * @log(o / e);
        if (e < 5) small += 1;
    }
    return .{ .pearson = chi(pearson, df), .likelihood_ratio = chi(lr, df), .sparse = small * 5 > counts.len, .total = n };
}

const Margins = struct { row: []f64, col: []f64, n: f64, nr: usize, nc: usize };
fn margins(a: std.mem.Allocator, m: CountMatrix) Error!Margins {
    if (m.rows == 0 or m.cols == 0 or m.rows > std.math.maxInt(usize) / m.cols or m.counts.len != m.rows * m.cols or !countValid(m.counts)) return error.ExecError;
    if (m.row_scores) |s| {
        if (s.len != m.rows) return error.ExecError;
        for (s) |v| if (!std.math.isFinite(v)) return error.ExecError;
    }
    if (m.col_scores) |s| {
        if (s.len != m.cols) return error.ExecError;
        for (s) |v| if (!std.math.isFinite(v)) return error.ExecError;
    }
    const r = try a.alloc(f64, m.rows);
    const c = try a.alloc(f64, m.cols);
    @memset(r, 0);
    @memset(c, 0);
    for (m.counts, 0..) |v, k| {
        r[k / m.cols] += v;
        c[k % m.cols] += v;
    }
    var nr: usize = 0;
    var nc: usize = 0;
    for (r) |v| {
        if (v > 0) nr += 1;
    }
    for (c) |v| {
        if (v > 0) nc += 1;
    }
    return .{ .row = r, .col = c, .n = sum(r), .nr = nr, .nc = nc };
}
fn score(s: ?[]const f64, i: usize) f64 {
    return if (s) |v| v[i] else @floatFromInt(i + 1);
}

pub fn contingency(a: std.mem.Allocator, m: CountMatrix, df_override: ?f64) Error!ChiSquare {
    const t = try margins(a, m);
    defer a.free(t.row);
    defer a.free(t.col);
    if (t.nr < 2 or t.nc < 2 or t.nr != m.rows or t.nc != m.cols) return error.ExecError;
    const df = try degreesOfFreedom(@floatFromInt((t.nr - 1) * (t.nc - 1)), df_override);
    var p: f64 = 0;
    var lr: f64 = 0;
    var cc: f64 = 0;
    var small: usize = 0;
    for (m.counts, 0..) |o, k| {
        const e = t.row[k / m.cols] * t.col[k % m.cols] / t.n;
        if (e == 0) continue;
        p += sq(o - e) / e;
        cc += sq(@max(0, @abs(o - e) - 0.5)) / e;
        if (o > 0) lr += 2 * o * @log(o / e);
        if (e < 5) small += 1;
    }
    const two = m.rows == 2 and m.cols == 2;
    const phi = if (two) (m.counts[0] * m.counts[3] - m.counts[1] * m.counts[2]) / @sqrt(t.row[0] * t.row[1] * t.col[0] * t.col[1]) else @sqrt(p / t.n);
    const corr = correlation(m, t, m.row_scores, m.col_scores, 0.05);
    return .{
        .pearson = chi(p, df),
        .likelihood_ratio = chi(lr, df),
        .mantel_haenszel = if (corr.estimate) |r| chi((t.n - 1) * r * r, 1) else null,
        .continuity = if (two) chi(cc, df) else null,
        .fisher = if (two and integerCounts(m.counts)) try fisherExact(m.counts) else null,
        .phi = phi,
        .contingency = @sqrt(p / (p + t.n)),
        .cramer_v = if (two) phi else @sqrt(p / t.n / @as(f64, @floatFromInt(@min(t.nr, t.nc) - 1))),
        .sparse = small * 5 > t.nr * t.nc,
        .total = t.n,
    };
}

fn logChoose(n: f64, k: f64) f64 {
    return fns.lgammaOf(n + 1) - fns.lgammaOf(k + 1) - fns.lgammaOf(n - k + 1);
}
pub fn fisherExact(cells: []const f64) Error!Fisher {
    if (cells.len != 4 or !countValid(cells)) return error.ExecError;
    // SAS suppresses exact tests for noninteger cell frequencies (oracle edges).
    if (!integerCounts(cells)) return error.ExecError;
    var v: [4]f64 = undefined;
    for (cells, 0..) |x, i| v[i] = x;
    const n = sum(&v);
    const r = v[0] + v[1];
    const c = v[0] + v[2];
    const lo = @max(0, r + c - n);
    const hi = @min(r, c);
    const lp = logChoose(c, v[0]) + logChoose(n - c, r - v[0]) - logChoose(n, r);
    var out = Fisher{ .probability = @exp(lp), .left = 0, .right = 0, .two_sided = 0 };
    var x = lo;
    while (x <= hi) : (x += 1) {
        const l = logChoose(c, x) + logChoose(n - c, r - x) - logChoose(n, r);
        const p = @exp(l);
        if (x <= v[0]) out.left += p;
        if (x >= v[0]) out.right += p;
        if (l <= lp + 1e-10) out.two_sided += p;
    }
    out.left = @min(1, out.left);
    out.right = @min(1, out.right);
    out.two_sided = @min(1, out.two_sided);
    return out;
}

pub const Measure = struct {
    estimate: ?f64 = null,
    ase: ?f64 = null,
    null_se: ?f64 = null,
    z: ?f64 = null,
    p_one: ?f64 = null,
    p_two: ?f64 = null,
    lower: ?f64 = null,
    upper: ?f64 = null,
};
pub const Association = struct {
    gamma: Measure,
    tau_b: Measure,
    tau_c: Measure,
    somers_cr: Measure,
    somers_rc: Measure,
    pearson: Measure,
    spearman: Measure,
};
fn measure(est: f64, variance: f64, null_variance: f64, alpha: f64) Measure {
    if (!std.math.isFinite(est)) return .{};
    var out = Measure{ .estimate = est };
    const critical = fns.distQuantile(.normal, 1 - alpha / 2, &.{}) orelse return out;
    if (std.math.isFinite(variance) and variance >= -1e-12) {
        out.ase = @sqrt(@max(0, variance));
        out.lower = @max(-1, est - critical * out.ase.?);
        out.upper = @min(1, est + critical * out.ase.?);
    }
    if (std.math.isFinite(null_variance) and null_variance == 0) out.null_se = 0;
    if (std.math.isFinite(null_variance) and null_variance > 0) {
        out.null_se = @sqrt(null_variance);
        out.z = est / out.null_se.?;
        out.p_one = fns.distCdf(.normal, -@abs(out.z.?), &.{});
        out.p_two = 2 * out.p_one.?;
    }
    return out;
}
fn correlation(m: CountMatrix, t: Margins, rs: ?[]const f64, cs: ?[]const f64, alpha: f64) Measure {
    var mr: f64 = 0;
    var mc: f64 = 0;
    for (t.row, 0..) |v, i| mr += v * score(rs, i) / t.n;
    for (t.col, 0..) |v, i| mc += v * score(cs, i) / t.n;
    var sr: f64 = 0;
    var sc: f64 = 0;
    var src: f64 = 0;
    for (m.counts, 0..) |v, k| {
        const x = score(rs, k / m.cols) - mr;
        const y = score(cs, k % m.cols) - mc;
        sr += v * x * x;
        sc += v * y * y;
        src += v * x * y;
    }
    const w = @sqrt(sr * sc);
    if (w == 0) return .{};
    const r = src / w;
    var variance: f64 = 0;
    var null_variance: f64 = -sq(src) / t.n;
    for (m.counts, 0..) |v, k| {
        const x = score(rs, k / m.cols) - mr;
        const y = score(cs, k % m.cols) - mc;
        variance += v * sq(x * y / w - r * (x * x / sr + y * y / sc) / 2);
        null_variance += v * x * x * y * y;
    }
    return measure(r, variance, null_variance / (sr * sc), alpha);
}

pub fn association(a: std.mem.Allocator, m: CountMatrix, alpha: f64) Error!Association {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    const t = try margins(a, m);
    defer a.free(t.row);
    defer a.free(t.col);
    const concord = try a.alloc(f64, m.counts.len);
    defer a.free(concord);
    const discord = try a.alloc(f64, m.counts.len);
    defer a.free(discord);
    var p: f64 = 0;
    var q: f64 = 0;
    for (m.counts, 0..) |v, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        concord[k] = 0;
        discord[k] = 0;
        for (m.counts, 0..) |other, l| {
            const r = l / m.cols;
            const c = l % m.cols;
            if ((r < i and c < j) or (r > i and c > j)) concord[k] += other;
            if ((r < i and c > j) or (r > i and c < j)) discord[k] += other;
        }
        p += v * concord[k];
        q += v * discord[k];
    }
    const delta = p - q;
    var wr = t.n * t.n;
    var wc = wr;
    for (t.row) |v| wr -= v * v;
    for (t.col) |v| wc -= v * v;
    const w = @sqrt(wr * wc);
    const tb = delta / w;
    const min_dim: f64 = @floatFromInt(@min(t.nr, t.nc));
    const tc_factor = min_dim / (t.n * t.n * (min_dim - 1));
    var vg: f64 = 0;
    var vb: f64 = 0;
    var vcr: f64 = 0;
    var vrc: f64 = 0;
    var v0 = -delta * delta / t.n;
    for (m.counts, 0..) |v, k| {
        const d = concord[k] - discord[k];
        const r = t.row[k / m.cols];
        const c = t.col[k % m.cols];
        v0 += v * d * d;
        vg += v * sq(q * concord[k] - p * discord[k]);
        vb += v * sq(2 * w * d + tb * (r * wc + c * wr));
        vcr += v * sq(wr * d - delta * (t.n - r));
        vrc += v * sq(wc * d - delta * (t.n - c));
    }
    const rr = try a.alloc(f64, m.rows);
    defer a.free(rr);
    const cr = try a.alloc(f64, m.cols);
    defer a.free(cr);
    var cum: f64 = 0;
    for (t.row, 0..) |v, i| {
        rr[i] = cum + v / 2;
        cum += v;
    }
    cum = 0;
    for (t.col, 0..) |v, i| {
        cr[i] = cum + v / 2;
        cum += v;
    }
    return .{
        .gamma = measure(delta / (p + q), 16 * vg / sq(sq(p + q)), 4 * v0 / sq(p + q), alpha),
        .tau_b = measure(tb, (vb - t.n * t.n * t.n * tb * tb * sq(wr + wc)) / sq(sq(w)), 4 * v0 / sq(w), alpha),
        .tau_c = measure(delta * tc_factor, 4 * v0 * sq(tc_factor), 4 * v0 * sq(tc_factor), alpha),
        .somers_cr = measure(delta / wr, 4 * vcr / sq(sq(wr)), 4 * v0 / sq(wr), alpha),
        .somers_rc = measure(delta / wc, 4 * vrc / sq(sq(wc)), 4 * v0 / sq(wc), alpha),
        .pearson = correlation(m, t, m.row_scores, m.col_scores, alpha),
        .spearman = spearman(m, t, rr, cr, alpha),
    };
}
fn spearman(m: CountMatrix, t: Margins, rs: []const f64, cs: []const f64, alpha: f64) Measure {
    var f = t.n * t.n * t.n;
    var g = f;
    var v: f64 = 0;
    for (t.row) |x| f -= x * x * x;
    for (t.col) |x| g -= x * x * x;
    const w = @sqrt(f * g) / 12;
    if (w == 0) return .{};
    for (m.counts, 0..) |x, k| v += x * (rs[k / m.cols] - t.n / 2) * (cs[k % m.cols] - t.n / 2);
    var zs: f64 = 0;
    var z2: f64 = 0;
    var vs: f64 = 0;
    var v2: f64 = 0;
    for (m.counts, 0..) |x, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        var vij = (rs[i] - t.n / 2) * (cs[j] - t.n / 2);
        for (m.counts, 0..) |y, l| {
            const r = l / m.cols;
            const c = l % m.cols;
            if (r == i) vij += 0.5 * y * (cs[c] - t.n / 2);
            if (c == j) vij += 0.5 * y * (rs[r] - t.n / 2);
            if (r > i) vij += y * (cs[c] - t.n / 2);
            if (c > j) vij += y * (rs[r] - t.n / 2);
        }
        vij *= t.n;
        const wij = -t.n * (f * sq(t.col[j]) + g * sq(t.row[i])) / (96 * w);
        const z = w * vij - v * wij;
        zs += x * z;
        z2 += x * z * z;
        vs += x * vij;
        v2 += x * vij * vij;
    }
    return measure(v / w, (z2 - zs * zs / t.n) / (sq(t.n) * sq(sq(w))), (v2 - vs * vs / t.n) / (sq(t.n) * sq(w)), alpha);
}

test "FEAT-freq-tests exact tails and signed 2x2 association" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try contingency(arena.allocator(), .{ .rows = 2, .cols = 2, .counts = &.{ 1, 9, 11, 3 } }, null);
    try std.testing.expectApproxEqAbs(@as(f64, 10.97142857142857), result.pearson.statistic, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0027594561852200836), result.fisher.?.two_sided, 1e-12);
    try std.testing.expect(result.phi < 0 and result.cramer_v == result.phi);
}
test "FEAT-freq-tests expected frequencies validate totals and df" {
    const result = try goodnessOfFit(&.{ 20, 27, 23 }, .{ .proportions = &.{ 20, 30, 50 } }, -1);
    try std.testing.expectApproxEqAbs(@as(f64, 8.4), result.pearson.statistic, 1e-12);
    try std.testing.expectEqual(@as(f64, 1), result.pearson.df);
    try std.testing.expectError(error.ExecError, goodnessOfFit(&.{ 2, 3 }, .{ .frequencies = &.{ 2, 2 } }, null));
    try std.testing.expectError(error.ExecError, goodnessOfFit(&.{ 2, 3 }, .equal, -1));
    try std.testing.expectError(error.ExecError, goodnessOfFit(&.{ 2, 3 }, .equal, 0));
}
test "FEAT-freq-tests ordinal null variance is not estimate variance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try association(arena.allocator(), .{ .rows = 3, .cols = 3, .counts = &.{ 12, 5, 3, 4, 17, 6, 2, 8, 13 } }, 0.05);
    try std.testing.expect(@abs(result.gamma.ase.? - result.gamma.null_se.?) > 0.01);
    try std.testing.expectApproxEqAbs(result.gamma.z.?, result.tau_b.z.?, 1e-12);
    try std.testing.expectApproxEqAbs(result.gamma.z.?, result.tau_c.z.?, 1e-12);
    try std.testing.expectApproxEqAbs(result.gamma.z.?, result.somers_cr.z.?, 1e-12);
    try std.testing.expectApproxEqAbs(result.gamma.z.?, result.somers_rc.z.?, 1e-12);
}

pub const Nominal = struct {
    lambda_cr: Measure,
    lambda_rc: Measure,
    lambda_symmetric: Measure,
    uncertainty_cr: Measure,
    uncertainty_rc: Measure,
    uncertainty_symmetric: Measure,
};
fn nominalMeasure(est: f64, variance: f64, alpha: f64) Measure {
    var result = measure(est, variance, std.math.nan(f64), alpha);
    if (result.lower) |lo| result.lower = @max(0, lo);
    return result;
}
/// Select lambda modes with SAS's consistent mutual row/column tie rule.
fn modes(a: std.mem.Allocator, m: CountMatrix, rows: []const f64, cols: []const f64) Error![]usize {
    const chosen = try a.alloc(usize, m.rows);
    const used = try a.alloc(bool, m.cols);
    defer a.free(used);
    @memset(used, false);
    var global: usize = 0;
    for (cols, 0..) |v, j| if (v > cols[global]) {
        global = j;
    };
    for (rows, 0..) |_, i| {
        var best: usize = 0;
        for (0..m.cols) |j| if (m.counts[i * m.cols + j] > m.counts[i * m.cols + best]) {
            best = j;
        };
        if (m.counts[i * m.cols + global] == m.counts[i * m.cols + best]) best = global;
        for (0..m.cols) |j| {
            var colmax: f64 = 0;
            for (0..m.rows) |k| colmax = @max(colmax, m.counts[k * m.cols + j]);
            if (!used[j] and m.counts[i * m.cols + j] == m.counts[i * m.cols + best] and colmax == m.counts[i * m.cols + j]) {
                best = j;
                used[j] = true;
                break;
            }
        }
        chosen[i] = best;
    }
    return chosen;
}
pub fn nominal(a: std.mem.Allocator, m: CountMatrix, alpha: f64) Error!Nominal {
    if (!(alpha > 0 and alpha < 1)) return error.ExecError;
    const t = try margins(a, m);
    defer a.free(t.row);
    defer a.free(t.col);
    const rm = try modes(a, m, t.row, t.col);
    defer a.free(rm);
    const transpose = try a.alloc(f64, m.counts.len);
    defer a.free(transpose);
    for (m.counts, 0..) |v, k| transpose[(k % m.cols) * m.rows + k / m.cols] = v;
    const cm = try modes(a, .{ .rows = m.cols, .cols = m.rows, .counts = transpose }, t.col, t.row);
    defer a.free(cm);
    var gr: usize = 0;
    var gc: usize = 0;
    for (t.row, 0..) |v, i| if (v > t.row[gr]) {
        gr = i;
    };
    for (t.col, 0..) |v, j| if (v > t.col[gc]) {
        gc = j;
    };
    var sr: f64 = 0;
    var sc: f64 = 0;
    for (rm, 0..) |j, i| sr += m.counts[i * m.cols + j];
    for (cm, 0..) |i, j| sc += m.counts[i * m.cols + j];
    const dr = t.n - t.col[gc];
    const dc = t.n - t.row[gr];
    const lr = (sr - t.col[gc]) / dr;
    const lc = (sc - t.row[gr]) / dc;
    const ls = (sr + sc - t.col[gc] - t.row[gr]) / (dr + dc);
    var vr: f64 = 0;
    var vc: f64 = 0;
    var vs: f64 = 0;
    var hx: f64 = 0;
    var hy: f64 = 0;
    var hxy: f64 = 0;
    for (t.row) |v| if (v > 0) {
        hx -= v / t.n * @log(v / t.n);
    };
    for (t.col) |v| if (v > 0) {
        hy -= v / t.n * @log(v / t.n);
    };
    for (m.counts, 0..) |v, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        const r: f64 = if (j == rm[i]) 1 else 0;
        const c: f64 = if (i == cm[j]) 1 else 0;
        const rg: f64 = if (j == gc) 1 else 0;
        const cg: f64 = if (i == gr) 1 else 0;
        vr += v * sq((r - rg - lr * (1 - rg)) / dr);
        vc += v * sq((c - cg - lc * (1 - cg)) / dc);
        vs += v * sq((r + c - rg - cg - ls * (2 - rg - cg)) / (dr + dc));
        if (v > 0) hxy -= v / t.n * @log(v / t.n);
    }
    const mutual = hx + hy - hxy;
    var ur: f64 = 0;
    var uc: f64 = 0;
    var us: f64 = 0;
    for (m.counts, 0..) |v, k| {
        if (v == 0) continue;
        const r = t.row[k / m.cols];
        const c = t.col[k % m.cols];
        ur += v * sq(hy * @log(v / r) + (hx - hxy) * @log(c / t.n));
        uc += v * sq(hx * @log(v / c) + (hy - hxy) * @log(r / t.n));
        us += v * sq(hxy * @log(r * c / sq(t.n)) - (hx + hy) * @log(v / t.n));
    }
    return .{
        .lambda_cr = nominalMeasure(lr, vr, alpha),
        .lambda_rc = nominalMeasure(lc, vc, alpha),
        .lambda_symmetric = nominalMeasure(ls, vs, alpha),
        .uncertainty_cr = nominalMeasure(mutual / hy, ur / (sq(t.n) * sq(sq(hy))), alpha),
        .uncertainty_rc = nominalMeasure(mutual / hx, uc / (sq(t.n) * sq(sq(hx))), alpha),
        .uncertainty_symmetric = nominalMeasure(2 * mutual / (hx + hy), 4 * us / (sq(t.n) * sq(sq(hx + hy))), alpha),
    };
}
pub const Risk = struct { estimate: ?f64 = null, lower: ?f64 = null, upper: ?f64 = null };
pub const Risks = struct { odds_ratio: Risk, column1: Risk, column2: Risk };
fn risk(value: f64, log_variance: f64, z: f64) Risk {
    if (!std.math.isFinite(value)) return .{};
    if (value == 0) return .{};
    if (!std.math.isFinite(log_variance)) return .{ .estimate = value };
    return .{ .estimate = value, .lower = value * @exp(-z * @sqrt(log_variance)), .upper = value * @exp(z * @sqrt(log_variance)) };
}
pub fn risks(c: []const f64, alpha: f64) Error!Risks {
    if (c.len != 4 or !countValid(c) or !(alpha > 0 and alpha < 1)) return error.ExecError;
    const z = fns.distQuantile(.normal, 1 - alpha / 2, &.{}).?;
    const n1 = c[0] + c[1];
    const n2 = c[2] + c[3];
    return .{ .odds_ratio = risk(c[0] * c[3] / (c[1] * c[2]), 1 / c[0] + 1 / c[1] + 1 / c[2] + 1 / c[3], z), .column1 = risk(c[0] * n2 / (c[2] * n1), 1 / c[0] - 1 / n1 + 1 / c[2] - 1 / n2, z), .column2 = risk(c[1] * n2 / (c[3] * n1), 1 / c[1] - 1 / n1 + 1 / c[3] - 1 / n2, z) };
}

test "FEAT-freq-tests SAS oracle ordinal ASE and null SE" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const r = try association(arena.allocator(), .{ .rows = 3, .cols = 3, .counts = &.{ 12, 5, 3, 4, 17, 6, 2, 8, 13 } }, 0.05);
    const measures = [_]Measure{ r.gamma, r.tau_b, r.tau_c, r.somers_cr, r.somers_rc, r.pearson, r.spearman };
    const expected = [_][3]f64{ .{ 0.6210, 0.1234, 0.1433 }, .{ 0.4420, 0.1002, 0.1020 }, .{ 0.4353, 0.1005, 0.1005 }, .{ 0.4386, 0.1002, 0.1012 }, .{ 0.4455, 0.1004, 0.1028 }, .{ 0.4802, 0.1057, 0.1200 }, .{ 0.4769, 0.1063, 0.1079 } };
    for (measures, expected) |actual, e| {
        try std.testing.expectApproxEqAbs(e[0], actual.estimate.?, 0.00005);
        try std.testing.expectApproxEqAbs(e[1], actual.ase.?, 0.00005);
        try std.testing.expectApproxEqAbs(e[2], actual.null_se.?, 0.00005);
    }
}
test "FEAT-freq-tests SAS nominal coefficients ASE and implied risks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const r = try nominal(arena.allocator(), .{ .rows = 3, .cols = 3, .counts = &.{ 12, 5, 3, 4, 17, 6, 2, 8, 13 } }, 0.05);
    const measures = [_]Measure{ r.lambda_cr, r.lambda_rc, r.lambda_symmetric, r.uncertainty_cr, r.uncertainty_rc, r.uncertainty_symmetric };
    const expected = [_][2]f64{ .{ 0.3000, 0.1289 }, .{ 0.3488, 0.1110 }, .{ 0.3253, 0.1130 }, .{ 0.1500, 0.0611 }, .{ 0.1479, 0.0605 }, .{ 0.1490, 0.0608 } };
    for (measures, expected) |actual, e| {
        try std.testing.expectApproxEqAbs(e[0], actual.estimate.?, 0.00005);
        try std.testing.expectApproxEqAbs(e[1], actual.ase.?, 0.00005);
    }
    const rr = try risks(&.{ 1, 9, 11, 3 }, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0303), rr.odds_ratio.estimate.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.8336), rr.column1.upper.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.5083), rr.column2.lower.?, 0.00005);
}

pub const PolychoricOptions = struct { adjust: bool = false, converge: f64 = 0.0001, maxiter: usize = 50, alpha: f64 = 0.05 };
pub const Polychoric = struct { coefficient: Measure, likelihood_ratio: ?Test, converged: bool, iterations: usize };
fn normalCdf(x: f64) f64 {
    return fns.distCdf(.normal, x, &.{}).?;
}
fn normalPdf(x: f64) f64 {
    return @exp(-x * x / 2) / @sqrt(2 * std.math.pi);
}
/// Plackett integral with rho=sin(theta), avoiding the endpoint square-root.
fn bivariateCdf(x: f64, y: f64, rho: f64) f64 {
    if (x <= -9 or y <= -9) return 0;
    if (x >= 9) return normalCdf(y);
    if (y >= 9) return normalCdf(x);
    if (rho == 0) return normalCdf(x) * normalCdf(y);
    const angle = std.math.asin(rho);
    const segments = 128;
    const h = angle / segments;
    var integral: f64 = 0;
    for (0..segments + 1) |i| {
        const t = h * @as(f64, @floatFromInt(i));
        const s = @sin(t);
        const c = @cos(t);
        const v = @exp(-(x * x - 2 * s * x * y + y * y) / (2 * c * c));
        integral += v * @as(f64, if (i == 0 or i == segments) 1 else if (i % 2 == 0) 2 else 4);
    }
    return normalCdf(x) * normalCdf(y) + h * integral / (6 * std.math.pi);
}
fn cellProbability(m: CountMatrix, params: []const f64, i: usize, j: usize) f64 {
    const rho = params[params.len - 1];
    const xl = if (i == 0) -10 else params[i - 1];
    const xu = if (i + 1 == m.rows) 10 else params[i];
    const yl = if (j == 0) -10 else params[m.rows + j - 2];
    const yu = if (j + 1 == m.cols) 10 else params[m.rows + j - 1];
    return @max(0, bivariateCdf(xu, yu, rho) - bivariateCdf(xl, yu, rho) - bivariateCdf(xu, yl, rho) + bivariateCdf(xl, yl, rho));
}
fn negativeLogLikelihood(m: CountMatrix, params: []const f64) f64 {
    if (@abs(params[params.len - 1]) >= 0.999999) return std.math.inf(f64);
    for (1..m.rows - 1) |i| if (params[i] <= params[i - 1]) return std.math.inf(f64);
    for (m.rows..params.len - 1) |j| if (params[j] <= params[j - 1]) return std.math.inf(f64);
    var result: f64 = 0;
    for (m.counts, 0..) |n, k| {
        if (n == 0) continue;
        const p = cellProbability(m, params, k / m.cols, k % m.cols);
        if (p <= 0) return std.math.inf(f64);
        result -= n * @log(p);
    }
    return result;
}
/// Pivoted solve; callers retain the original matrix when they need its inverse.
fn linearSolve(matrix: []f64, rhs: []f64) bool {
    const n = rhs.len;
    for (0..n) |i| {
        var pivot = i;
        for (i + 1..n) |j| if (@abs(matrix[j * n + i]) > @abs(matrix[pivot * n + i])) {
            pivot = j;
        };
        if (@abs(matrix[pivot * n + i]) < 1e-12) return false;
        for (0..n) |k| std.mem.swap(f64, &matrix[i * n + k], &matrix[pivot * n + k]);
        std.mem.swap(f64, &rhs[i], &rhs[pivot]);
        const scale = matrix[i * n + i];
        for (i..n) |k| matrix[i * n + k] /= scale;
        rhs[i] /= scale;
        for (0..n) |j| {
            if (j == i) continue;
            const factor = matrix[j * n + i];
            for (i..n) |k| matrix[j * n + k] -= factor * matrix[i * n + k];
            rhs[j] -= factor * rhs[i];
        }
    }
    return true;
}
pub fn polychoric(a: std.mem.Allocator, input: CountMatrix, opts: PolychoricOptions) Error!Polychoric {
    if (!(opts.alpha > 0 and opts.alpha < 1) or !std.math.isFinite(opts.converge) or opts.converge <= 0 or opts.maxiter == 0) return error.ExecError;
    var m = input;
    const counts = try a.dupe(f64, input.counts);
    defer a.free(counts);
    m.counts = counts;
    if (opts.adjust and m.rows == 2 and m.cols == 2 and counts.len == 4) {
        var zeros: usize = 0;
        var zero: usize = 0;
        for (counts, 0..) |v, k| if (v == 0) {
            zeros += 1;
            zero = k;
        };
        if (zeros == 1) {
            counts[zero] += 0.5;
            counts[3 - zero] += 0.5;
            counts[zero ^ 1] -= 0.5;
            counts[zero ^ 2] -= 0.5;
        }
    }
    const t = try margins(a, m);
    defer a.free(t.row);
    defer a.free(t.col);
    if (t.nr < 2 or t.nc < 2 or t.nr != m.rows or t.nc != m.cols) return error.ExecError;
    const dim = m.rows + m.cols - 1;
    const params = try a.alloc(f64, dim);
    defer a.free(params);
    var cum: f64 = 0;
    for (t.row[0 .. m.rows - 1], 0..) |v, i| {
        cum += v / t.n;
        params[i] = fns.distQuantile(.normal, cum, &.{}).?;
    }
    cum = 0;
    for (t.col[0 .. m.cols - 1], 0..) |v, j| {
        cum += v / t.n;
        params[m.rows + j - 1] = fns.distQuantile(.normal, cum, &.{}).?;
    }
    params[dim - 1] = 0;
    const null_ll = negativeLogLikelihood(m, params);
    if (m.rows == 2 and m.cols == 2 and ((counts[1] == 0 and counts[2] == 0) or (counts[0] == 0 and counts[3] == 0))) {
        const r: f64 = if (counts[1] == 0) 1 else -1;
        return .{ .coefficient = measure(r, 0, 0, opts.alpha), .likelihood_ratio = null, .converged = true, .iterations = 0 };
    }
    // SAS reports the constrained tetrachoric boundary as +/-0.999 for
    // exactly one zero cell without ADJUST; the likelihood is saturated.
    // Oracle boundary.sas: rho=-0.9990, ASE=0, LR=17.2930 for [0,9;11,3].
    if (m.rows == 2 and m.cols == 2 and !opts.adjust) {
        var zero_count: usize = 0;
        var zero_index: usize = 0;
        for (counts, 0..) |v, i| if (v == 0) {
            zero_count += 1;
            zero_index = i;
        };
        if (zero_count == 1) {
            var saturated: f64 = 0;
            for (counts) |v| if (v > 0) {
                saturated -= v * @log(v / t.n);
            };
            const rho: f64 = if (zero_index == 0 or zero_index == 3) -0.999 else 0.999;
            return .{ .coefficient = measure(rho, 0, 0, opts.alpha), .likelihood_ratio = chi(2 * (null_ll - saturated), 1), .converged = true, .iterations = 0 };
        }
    }
    const hessian = try a.alloc(f64, dim * dim);
    defer a.free(hessian);
    const gradient = try a.alloc(f64, dim);
    defer a.free(gradient);
    const candidate = try a.alloc(f64, dim);
    defer a.free(candidate);
    const delta: f64 = 0.0001;
    var converged = false;
    var iterations: usize = 0;
    while (iterations < opts.maxiter) {
        iterations += 1;
        const base = negativeLogLikelihood(m, params);
        for (0..dim) |i| {
            const old = params[i];
            params[i] = old + delta;
            const plus = negativeLogLikelihood(m, params);
            params[i] = old - delta;
            const minus = negativeLogLikelihood(m, params);
            params[i] = old;
            gradient[i] = (plus - minus) / (2 * delta);
            hessian[i * dim + i] = (plus - 2 * base + minus) / sq(delta);
            for (0..i) |j| {
                const other = params[j];
                params[i] = old + delta;
                params[j] = other + delta;
                const pp = negativeLogLikelihood(m, params);
                params[j] = other - delta;
                const pm = negativeLogLikelihood(m, params);
                params[i] = old - delta;
                const mm = negativeLogLikelihood(m, params);
                params[j] = other + delta;
                const mp = negativeLogLikelihood(m, params);
                params[i] = old;
                params[j] = other;
                const value = (pp - pm - mp + mm) / (4 * sq(delta));
                hessian[i * dim + j] = value;
                hessian[j * dim + i] = value;
            }
        }
        if (!linearSolve(hessian, gradient)) break;
        var scale: f64 = 1;
        var accepted = false;
        for (0..30) |_| {
            for (params, 0..) |p, i| candidate[i] = p - scale * gradient[i];
            if (negativeLogLikelihood(m, candidate) <= base + 1e-10) {
                accepted = true;
                break;
            }
            scale /= 2;
        }
        if (!accepted) break;
        var change: f64 = 0;
        for (params, candidate) |p, c| change = @max(change, @abs(c - p) / (if (@abs(p) < 0.01) 1 else @abs(p)));
        @memcpy(params, candidate);
        if (change < opts.converge) {
            converged = true;
            break;
        }
    }
    if (!converged) return .{ .coefficient = .{}, .likelihood_ratio = null, .converged = false, .iterations = iterations };
    // Expected multinomial information for simultaneous thresholds and rho.
    @memset(hessian, 0);
    for (m.counts, 0..) |_, k| {
        const i = k / m.cols;
        const j = k % m.cols;
        const p = cellProbability(m, params, i, j);
        if (p <= 0) continue;
        for (0..dim) |l| {
            const old = params[l];
            params[l] = old + delta;
            const plus = cellProbability(m, params, i, j);
            params[l] = old - delta;
            const minus = cellProbability(m, params, i, j);
            params[l] = old;
            gradient[l] = (plus - minus) / (2 * delta);
        }
        for (0..dim) |r| for (0..dim) |c| {
            hessian[r * dim + c] += t.n * gradient[r] * gradient[c] / p;
        };
    }
    @memset(gradient, 0);
    gradient[dim - 1] = 1;
    const variance = if (linearSolve(hessian, gradient)) gradient[dim - 1] else std.math.nan(f64);
    return .{ .coefficient = measure(params[dim - 1], variance, variance, opts.alpha), .likelihood_ratio = chi(2 * (null_ll - negativeLogLikelihood(m, params)), 1), .converged = converged, .iterations = iterations };
}

test "FEAT-freq-tests SAS joint polychoric MLE not two-step approximation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try polychoric(arena.allocator(), .{ .rows = 3, .cols = 3, .counts = &.{ 12, 5, 3, 4, 17, 6, 2, 8, 13 } }, .{});
    try std.testing.expect(result.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5906), result.coefficient.estimate.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1049), result.coefficient.ase.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 18.2978), result.likelihood_ratio.?.statistic, 0.00005);
    const two = try polychoric(arena.allocator(), .{ .rows = 2, .cols = 2, .counts = &.{ 1, 9, 11, 3 } }, .{});
    try std.testing.expect(two.converged);
    try std.testing.expectApproxEqAbs(@as(f64, -0.8859), two.coefficient.estimate.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1095), two.coefficient.ase.?, 0.00005);
}

fn integerCounts(counts: []const f64) bool {
    for (counts) |v| if (@floor(v) != v) return false;
    return true;
}
/// Upper incomplete gamma directly in the tail; 1-P loses small p-values.
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

test "FEAT-freq-tests oracle tied modes fractional counts zero margins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m = CountMatrix{ .rows = 3, .cols = 3, .counts = &.{ 4, 4, 2, 4, 4, 2, 2, 2, 4 } };
    const nom = try nominal(a, m, 0.05);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1960), nom.lambda_cr.ase.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1960), nom.lambda_rc.ase.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1763), nom.lambda_symmetric.ase.?, 0.00005);
    const chisq = try contingency(a, m, -1);
    try std.testing.expectEqual(@as(f64, 3), chisq.pearson.df);
    try std.testing.expectEqual(@as(f64, 1), chisq.mantel_haenszel.?.df);
    const frac = try contingency(a, .{ .rows = 2, .cols = 2, .counts = &.{ 1.9, 9.7, 11.4, 3.8 } }, null);
    try std.testing.expect(frac.fisher == null);
    try std.testing.expectApproxEqAbs(@as(f64, 9.0438), frac.pearson.statistic, 0.00005);
    try std.testing.expectError(error.ExecError, contingency(a, .{ .rows = 3, .cols = 2, .counts = &.{ 0, 0, 3, 5, 4, 1 } }, null));
    const adjusted = try polychoric(a, .{ .rows = 2, .cols = 2, .counts = &.{ 0, 9, 11, 3 } }, .{ .adjust = true });
    try std.testing.expect(adjusted.converged);
    try std.testing.expectApproxEqAbs(@as(f64, -0.9083), adjusted.coefficient.estimate.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.1001), adjusted.coefficient.ase.?, 0.00005);
    const unconverged = try polychoric(a, m, .{ .maxiter = 1 });
    try std.testing.expect(!unconverged.converged and unconverged.coefficient.estimate == null and unconverged.likelihood_ratio == null);
    try std.testing.expect(chi(100, 1).p > 0 and chi(100, 1).p < 1e-20);
}

test "FEAT-freq-tests SAS tetrachoric boundary independence and DF scope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const boundary = try polychoric(a, .{ .rows = 2, .cols = 2, .counts = &.{ 0, 9, 11, 3 } }, .{});
    try std.testing.expectEqual(@as(f64, -0.999), boundary.coefficient.estimate.?);
    try std.testing.expectEqual(@as(f64, 0), boundary.coefficient.ase.?);
    try std.testing.expect(boundary.coefficient.z == null);
    try std.testing.expectApproxEqAbs(@as(f64, 17.2930), boundary.likelihood_ratio.?.statistic, 0.00005);
    const independent = try polychoric(a, .{ .rows = 2, .cols = 2, .counts = &.{ 5, 5, 5, 5 } }, .{});
    try std.testing.expect(independent.converged);
    try std.testing.expectApproxEqAbs(@as(f64, 0), independent.coefficient.estimate.?, 1e-10);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3512), independent.coefficient.ase.?, 0.00005);
    const chi_square = try contingency(a, .{ .rows = 2, .cols = 2, .counts = &.{ 1, 9, 11, 3 } }, 3);
    try std.testing.expectEqual(@as(f64, 3), chi_square.continuity.?.df);
    try std.testing.expectEqual(@as(f64, 1), chi_square.mantel_haenszel.?.df);
}

test "FEAT-freq-tests zero null variance retains zero SE and missing test" {
    const result = measure(1, 0, 0, 0.05);
    try std.testing.expectEqual(@as(?f64, 0), result.null_se);
    try std.testing.expectEqual(@as(?f64, 0), result.ase);
    try std.testing.expect(result.z == null and result.p_two == null);
}
