//! STAT-PLM-007: LSMEANS / LSMESTIMATE / SLICE for PROC PLM, computed from the
//! restored native GLM store only (S154 physical pp.7636–7639, 7643–7644).
//!
//! The store holds a full-rank sum-to-zero basis b with covariance C. For a
//! cell of the CLASS grid the model mean is f(cell)'b, f = sum-to-zero design
//! row (same coding as store.row / plm_infer). The LS-mean of an effect level
//! is the equally weighted average of the model means over every grid cell
//! that carries that level, i.e. L = mean of f(cell) over those cells; then
//!     estimate = L'b,  Var = L'CL,  t = estimate / sqrt(Var),  df = error df.
//! This equals the SAS singular-parameterisation L (1 on Intercept, 1 on the
//! level, 1/k on every other class level) because plm_infer.parameters proves
//! both parameterisations span the same grid means; that guard is called
//! first, so every stored shape it refuses is refused here too. Because b has
//! full rank on the complete grid, every LS-mean of a supported store is
//! estimable; rank-deficient stores (the only source of non-estimable
//! LS-means) are refused upstream and never reach this code.
//!
//! The validated PROC GLM LS-means kernels work from the raw data cross
//! products, which a store does not carry, so they are not consumed here.
const std = @import("std");
const store = @import("store.zig");
const infer = @import("plm_infer.zig");
const reg = @import("reg_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;

pub const Error = error{ OutOfMemory, Unsupported, UnknownLsEffect, UnknownLevel, TooManyCoefficients, SliceNeedsInteraction, Singular };

pub const Lsmeans = struct { effects: []const []const u8, diff: bool = false, cl: bool = false, alpha: ?f64 = null, line: usize = 0 };
pub const Tail = enum { upper, lower };
pub const EstimateRow = struct { label: ?[]const u8, values: []const f64 };
pub const Lsmestimate = struct { effect: []const u8, rows: []const EstimateRow, tail: Tail, line: usize = 0 };
pub const Slice = struct { effect: []const u8, by: []const u8, level: ?[]const u8 = null, diff: bool = false, line: usize = 0 };

pub const Stat = struct { estimate: f64, stderr: f64, df: usize, t: f64, p: f64 };

pub fn effectIndex(m: store.Model, name: []const u8) Error!usize {
    for (m.effects, 0..) |e, i| if (eq(e.name, name)) return i;
    return error.UnknownLsEffect;
}

/// Mean sum-to-zero design row over the grid cells whose class levels match
/// `fixed` (null = averaged over).
pub fn lsRow(a: A, m: store.Model, fixed: []const ?usize) Error![]f64 {
    const p = m.coefficients.len;
    const row = try a.alloc(f64, p);
    @memset(row, 0);
    const cell = try a.alloc(usize, m.classes.len);
    var n: usize = 1;
    for (m.classes) |c| n *= c.levels.len;
    var count: f64 = 0;
    for (0..n) |r| {
        var radix = r;
        var hit = true;
        for (cell, m.classes, fixed) |*l, c, want| {
            l.* = radix % c.levels.len;
            radix /= c.levels.len;
            if (want) |w| hit = hit and w == l.*;
        }
        if (!hit) continue;
        count += 1;
        if (m.intercept) row[0] += 1;
        for (m.effects) |e| for (0..e.len) |j| {
            var rj = j;
            var product: f64 = 1;
            for (e.factors) |factor| {
                const ci = factor.class_index.?;
                const levels = m.classes[ci].levels.len;
                const term = rj % (levels - 1);
                rj /= levels - 1;
                product *= if (cell[ci] == levels - 1) @as(f64, -1) else if (cell[ci] == term) 1 else 0;
            }
            row[e.start + j] += product;
        };
    }
    if (count == 0) return error.Unsupported;
    for (row) |*v| v.* /= count;
    return row;
}

/// One L row per level combination of the effect, SAS order (last factor
/// fastest). `levels[i]` is the per-class level index (null = not in effect).
pub const Means = struct { rows: []const []const f64, levels: []const []const ?usize };
pub fn means(a: A, m: store.Model, effect: usize) Error!Means {
    _ = infer.parameters(a, m) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return error.Unsupported,
    };
    const e = m.effects[effect];
    var width: usize = 1;
    for (e.factors) |f| width *= m.classes[f.class_index.?].levels.len;
    const rows = try a.alloc([]const f64, width);
    const levels = try a.alloc([]const ?usize, width);
    for (0..width) |j| {
        const lv = try a.alloc(?usize, m.classes.len);
        @memset(lv, null);
        var radix = j;
        var k = e.factors.len;
        while (k > 0) {
            k -= 1;
            const ci = e.factors[k].class_index.?;
            const count = m.classes[ci].levels.len;
            lv[ci] = radix % count;
            radix /= count;
        }
        levels[j] = lv;
        rows[j] = try lsRow(a, m, lv);
    }
    return .{ .rows = rows, .levels = levels };
}

pub fn stat(m: store.Model, l: []const f64) Error!Stat {
    const p = m.coefficients.len;
    var estimate: f64 = 0;
    var variance: f64 = 0;
    for (0..p) |c| {
        estimate += l[c] * m.coefficients[c];
        for (0..p) |d| variance += l[c] * m.covariance[c * p + d] * l[d];
    }
    if (!std.math.isFinite(estimate) or !(variance > 0) or m.df_error == 0) return error.Unsupported;
    const se = @sqrt(variance);
    const tv = estimate / se;
    return .{ .estimate = estimate, .stderr = se, .df = m.df_error, .t = tv, .p = reg.tProbability(tv, m.df_error) };
}

pub fn combine(a: A, rows: []const []const f64, weights: []const f64) Error![]f64 {
    if (weights.len > rows.len) return error.TooManyCoefficients;
    const out = try a.alloc(f64, rows[0].len);
    @memset(out, 0);
    for (weights, 0..) |w, i| for (out, rows[i]) |*o, v| {
        o.* += w * v;
    };
    return out;
}

pub const FTest = struct { num_df: usize, den_df: usize, f: f64, p: f64 };
/// F = (Lb)'(LCL')^-1(Lb)/r for r linearly independent rows.
pub fn joint(a: A, m: store.Model, rows: []const []const f64) Error!FTest {
    const r = rows.len;
    const p = m.coefficients.len;
    if (r == 0) return error.Unsupported;
    const g = try a.alloc(f64, r * (r + 1));
    for (0..r) |i| {
        var v: f64 = 0;
        for (0..p) |c| v += rows[i][c] * m.coefficients[c];
        g[i * (r + 1) + r] = v;
        for (0..r) |j| {
            var q: f64 = 0;
            for (0..p) |c| for (0..p) |d| {
                q += rows[i][c] * m.covariance[c * p + d] * rows[j][d];
            };
            g[i * (r + 1) + j] = q;
        }
    }
    const rhs = try a.alloc(f64, r);
    for (rhs, 0..) |*v, i| v.* = g[i * (r + 1) + r];
    // Gaussian elimination with partial pivoting on the SPD r x r system.
    for (0..r) |k| {
        var best = k;
        for (k + 1..r) |i| if (@abs(g[i * (r + 1) + k]) > @abs(g[best * (r + 1) + k])) {
            best = i;
        };
        if (!(@abs(g[best * (r + 1) + k]) > 1e-12)) return error.Singular;
        if (best != k) for (0..r + 1) |c| std.mem.swap(f64, &g[k * (r + 1) + c], &g[best * (r + 1) + c]);
        for (k + 1..r) |i| {
            const factor = g[i * (r + 1) + k] / g[k * (r + 1) + k];
            for (k..r + 1) |c| g[i * (r + 1) + c] -= factor * g[k * (r + 1) + c];
        }
    }
    // Rows were permuted together with their right-hand sides; the quadratic
    // form needs the solution x of M x = v dotted with the ORIGINAL v.
    const x = try a.alloc(f64, r);
    var k = r;
    while (k > 0) {
        k -= 1;
        var v = g[k * (r + 1) + r];
        for (k + 1..r) |c| v -= g[k * (r + 1) + c] * x[c];
        x[k] = v / g[k * (r + 1) + k];
    }
    var quad: f64 = 0;
    for (x, rhs) |xv, v| quad += xv * v;
    const f = quad / @as(f64, @floatFromInt(r));
    if (!std.math.isFinite(f) or f < 0) return error.Unsupported;
    return .{ .num_df = r, .den_df = m.df_error, .f = f, .p = reg.fProbability(f, r, m.df_error) };
}

// ---- rendering: layouts follow the retained SAS listings (4-blank gutters).

fn pad(a: A, out: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (width > text.len) try out.appendNTimes(a, ' ', width - text.len);
}
fn right(a: A, out: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn title(a: A, out: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    try out.append(a, '\n');
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, "\n \n");
}
fn probability(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else std.fmt.allocPrint(a, "{d:.4}", .{p});
}
fn label(c: store.Class, level: usize) []const u8 {
    return std.mem.trim(u8, c.levels[level].label, " ");
}
fn levelWidth(c: store.Class, extra: usize) usize {
    var w = c.name.len + extra;
    for (c.levels, 0..) |_, i| w = @max(w, label(c, i).len);
    return w;
}
/// Estimate, Standard Error, DF, t Value and the two-sided probability,
/// optionally followed by Alpha / Lower / Upper.
fn statCells(a: A, out: *std.ArrayList(u8), s: Stat, alpha: ?f64) !void {
    try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{s.estimate}), 8);
    try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{s.stderr}), 12);
    try right(a, out, try std.fmt.allocPrint(a, "{d}", .{s.df}), 9);
    try right(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{s.t}), 11);
    try right(a, out, try probability(a, s.p), 12);
    if (alpha) |al| {
        const half = reg.tCritical(al, s.df) * s.stderr;
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{al}), 10);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{s.estimate - half}), 12);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{s.estimate + half}), 12);
    }
    try out.append(a, '\n');
}
const stat_header = "Estimate       Error       DF    t Value    Pr > |t|";
const cl_header = "     Alpha       Lower       Upper";

pub fn renderLsmeans(a: A, out: *std.ArrayList(u8), m: store.Model, request: Lsmeans, default_alpha: f64) !void {
    const alpha: ?f64 = if (request.cl) request.alpha orelse default_alpha else null;
    const tail: usize = if (request.cl) 34 else 0;
    for (request.effects) |name| {
        const ei = try effectIndex(m, name);
        const e = m.effects[ei];
        // ponytail: the listing layout of an interaction LS-means table has no
        // SAS reference in this ticket; only main effects are rendered.
        if (e.factors.len != 1) return error.Unsupported;
        const c = m.classes[e.factors[0].class_index.?];
        const lm = try means(a, m, ei);
        const w = levelWidth(c, 0) + 4;
        try title(a, out, try std.fmt.allocPrint(a, "{s} Least Squares Means", .{e.name}), w + 52 + tail);
        try right(a, out, "Standard", w + 20);
        try out.append(a, '\n');
        try pad(a, out, c.name, w);
        try out.appendSlice(a, stat_header);
        if (request.cl) try out.appendSlice(a, cl_header);
        try out.appendSlice(a, "\n\n");
        for (lm.rows, 0..) |row, i| {
            try pad(a, out, label(c, i), w);
            try statCells(a, out, try stat(m, row), alpha);
        }
        try out.append(a, '\n');
        if (!request.diff) continue;
        const w2 = levelWidth(c, 1) + 4;
        try title(a, out, try std.fmt.allocPrint(a, "Differences of {s} Least Squares Means", .{e.name}), w + w2 + 52 + tail);
        try right(a, out, "Standard", w + w2 + 20);
        try out.append(a, '\n');
        try pad(a, out, c.name, w);
        try pad(a, out, try std.fmt.allocPrint(a, "_{s}", .{c.name}), w2);
        try out.appendSlice(a, stat_header);
        if (request.cl) try out.appendSlice(a, cl_header);
        try out.appendSlice(a, "\n\n");
        for (0..lm.rows.len) |i| for (i + 1..lm.rows.len) |j| {
            try pad(a, out, label(c, i), w);
            try pad(a, out, label(c, j), w2);
            try statCells(a, out, try stat(m, try difference(a, lm.rows[i], lm.rows[j])), alpha);
        };
        try out.append(a, '\n');
    }
}
fn difference(a: A, x: []const f64, y: []const f64) ![]f64 {
    const out = try a.alloc(f64, x.len);
    for (out, x, y) |*o, u, v| o.* = u - v;
    return out;
}

pub fn renderLsmestimate(a: A, out: *std.ArrayList(u8), m: store.Model, request: Lsmestimate) !void {
    const ei = try effectIndex(m, request.effect);
    const e = m.effects[ei];
    const lm = try means(a, m, ei);
    const labels = try a.alloc([]const u8, request.rows.len);
    const ew = @max("Effect".len, e.name.len) + 4;
    var lw: usize = "Label".len;
    for (labels, request.rows, 1..) |*l, row, k| {
        l.* = row.label orelse try std.fmt.allocPrint(a, "Row {d}", .{k});
        lw = @max(lw, l.len);
    }
    lw += 4;
    try title(a, out, "Least Squares Means Estimates", ew + lw + 61);
    try right(a, out, "Standard", ew + lw + 20);
    try out.append(a, '\n');
    try pad(a, out, "Effect", ew);
    try pad(a, out, "Label", lw);
    try out.appendSlice(a, "Estimate       Error       DF    t Value    Tails      ");
    try out.appendSlice(a, if (request.tail == .upper) "Pr > t" else "Pr < t");
    try out.appendSlice(a, "\n\n");
    for (labels, request.rows) |l, row| {
        const s = try stat(m, try combine(a, lm.rows, row.values));
        // One-sided tail from the two-sided probability of the same t.
        const same_side = if (request.tail == .upper) s.t >= 0 else s.t <= 0;
        const p = if (same_side) s.p / 2 else 1 - s.p / 2;
        try pad(a, out, e.name, ew);
        try pad(a, out, l, lw);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{s.estimate}), 8);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{s.stderr}), 12);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{s.df}), 9);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{s.t}), 11);
        try out.appendSlice(a, if (request.tail == .upper) "    Upper" else "    Lower");
        try right(a, out, try probability(a, p), 12);
        try out.append(a, '\n');
    }
    try out.append(a, '\n');
}

pub const SlicePlan = struct { effect: usize, by_class: usize, other_class: usize, levels: []const usize };
pub fn slicePlan(a: A, m: store.Model, request: Slice) Error!SlicePlan {
    const ei = try effectIndex(m, request.effect);
    const e = m.effects[ei];
    if (e.factors.len < 2) return error.SliceNeedsInteraction;
    // ponytail: three-way and higher slices have no SAS reference layout here.
    if (e.factors.len != 2) return error.Unsupported;
    var by: ?usize = null;
    var other: usize = 0;
    for (e.factors) |f| {
        const ci = f.class_index orelse return error.Unsupported;
        if (eq(m.classes[ci].name, request.by)) by = ci else other = ci;
    }
    const bc = by orelse return error.UnknownLsEffect;
    var levels: std.ArrayList(usize) = .empty;
    for (m.classes[bc].levels, 0..) |_, i| {
        if (request.level) |want| if (!std.mem.eql(u8, std.mem.trim(u8, want, " "), label(m.classes[bc], i))) continue;
        try levels.append(a, i);
    }
    if (levels.items.len == 0) return error.UnknownLevel;
    return .{ .effect = ei, .by_class = bc, .other_class = other, .levels = levels.items };
}
/// LS-mean rows of the non-slice factor's levels inside one slice.
pub fn sliceRows(a: A, m: store.Model, plan: SlicePlan, level: usize) Error![]const []const f64 {
    _ = infer.parameters(a, m) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return error.Unsupported,
    };
    const oc = m.classes[plan.other_class];
    const rows = try a.alloc([]const f64, oc.levels.len);
    for (rows, 0..) |*row, i| {
        const fixed = try a.alloc(?usize, m.classes.len);
        @memset(fixed, null);
        fixed[plan.by_class] = level;
        fixed[plan.other_class] = i;
        row.* = try lsRow(a, m, fixed);
    }
    return rows;
}
/// F test that the LS-means inside one slice are all equal.
pub fn sliceTest(a: A, m: store.Model, rows: []const []const f64) Error!FTest {
    if (rows.len < 2) return error.Unsupported;
    const d = try a.alloc([]const f64, rows.len - 1);
    for (d, 0..) |*row, i| row.* = try difference(a, rows[i], rows[rows.len - 1]);
    return joint(a, m, d);
}

pub fn renderSlice(a: A, out: *std.ArrayList(u8), m: store.Model, request: Slice) !void {
    const plan = try slicePlan(a, m, request);
    const e = m.effects[plan.effect];
    const bc = m.classes[plan.by_class];
    const oc = m.classes[plan.other_class];
    const names = try a.alloc([]const u8, plan.levels.len);
    var sw: usize = "Slice".len;
    for (names, plan.levels) |*n, level| {
        n.* = try std.fmt.allocPrint(a, "{s} {s}", .{ bc.name, label(bc, level) });
        sw = @max(sw, n.len);
    }
    sw += 4;
    try title(a, out, try std.fmt.allocPrint(a, "F Test for {s} Least Squares Means Slice", .{e.name}), sw + 34);
    try right(a, out, "Num", sw + 4);
    try right(a, out, "Den", 9);
    try out.append(a, '\n');
    try pad(a, out, "Slice", sw);
    try out.appendSlice(a, "  DF       DF    F Value    Pr > F\n\n");
    for (names, plan.levels) |n, level| {
        const r = try sliceTest(a, m, try sliceRows(a, m, plan, level));
        try pad(a, out, n, sw);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{r.num_df}), 4);
        try right(a, out, try std.fmt.allocPrint(a, "{d}", .{r.den_df}), 9);
        try right(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{r.f}), 11);
        try right(a, out, try probability(a, r.p), 10);
        try out.append(a, '\n');
    }
    try out.append(a, '\n');
    if (!request.diff) return;
    const w = levelWidth(oc, 0) + 4;
    const w2 = levelWidth(oc, 1) + 4;
    try title(a, out, try std.fmt.allocPrint(a, "Simple Differences of {s} Least Squares Means", .{e.name}), sw + w + w2 + 52);
    try right(a, out, "Standard", sw + w + w2 + 20);
    try out.append(a, '\n');
    try pad(a, out, "Slice", sw);
    try pad(a, out, oc.name, w);
    try pad(a, out, try std.fmt.allocPrint(a, "_{s}", .{oc.name}), w2);
    try out.appendSlice(a, stat_header);
    try out.appendSlice(a, "\n\n");
    for (names, plan.levels) |n, level| {
        const rows = try sliceRows(a, m, plan, level);
        for (0..rows.len) |i| for (i + 1..rows.len) |j| {
            try pad(a, out, n, sw);
            try pad(a, out, label(oc, i), w);
            try pad(a, out, label(oc, j), w2);
            try statCells(a, out, try stat(m, try difference(a, rows[i], rows[j])), null);
        };
    }
    try out.append(a, '\n');
}
