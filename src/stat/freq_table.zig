//! Typed sparse FREQ tables. No parsing or text rendering.
const std = @import("std");
const Value = @import("../value.zig").Value;
const diag = @import("../diag.zig");
pub const Score = enum { table, rank, ridit, modridit };
pub const Level = struct { value: Value, raw: Value, missing: bool, frequency: f64 };
pub const Dimension = struct { name: []const u8, label: ?[]const u8 = null, levels: []Level };
pub const CountMatrix = struct {
    rows: usize,
    cols: usize,
    counts: []const f64,
    row_scores: ?[]const f64 = null,
    col_scores: ?[]const f64 = null,
};
pub const ScoredMatrix = struct { matrix: CountMatrix, row_levels: []const Level, col_levels: []const Level, numeric_table_scores_valid: bool = true };
pub const Table = struct {
    dimensions: []Dimension,
    strides: []usize,
    cell_count: usize,
    counts: std.AutoHashMapUnmanaged(usize, f64) = .empty,
    include_missing: bool,
    score_kind: Score = .table,
    negative: bool = false,
    total: f64 = 0,
    missing: f64 = 0,

    pub fn init(a: std.mem.Allocator, dims: []Dimension, include_missing: bool) diag.Error!Table {
        const strides = try a.alloc(usize, dims.len);
        var n: usize = 1;
        var d = dims.len;
        while (d > 0) {
            d -= 1;
            strides[d] = n;
            n = std.math.mul(usize, n, dims[d].levels.len) catch return error.OutOfMemory;
        }
        return .{ .dimensions = dims, .strides = strides, .cell_count = n, .include_missing = include_missing };
    }
    pub fn level(self: Table, key: usize, d: usize) Level {
        return self.dimensions[d].levels[(key / self.strides[d]) % self.dimensions[d].levels.len];
    }
    pub fn excluded(self: Table, key: usize) bool {
        if (self.include_missing) return false;
        for (0..self.dimensions.len) |d| if (self.level(key, d).missing) return true;
        return false;
    }
    pub fn add(self: *Table, a: std.mem.Allocator, key: usize, weight: f64) !void {
        const e = try self.counts.getOrPut(a, key);
        if (!e.found_existing) e.value_ptr.* = 0;
        e.value_ptr.* += weight;
        self.negative = self.negative or weight < 0;
        if (self.excluded(key)) self.missing += weight else self.total += weight;
    }
    pub fn count(self: Table, key: usize) f64 {
        return self.counts.get(key) orelse 0;
    }
    pub fn pct(self: Table, key: usize) f64 {
        return if (self.negative or self.excluded(key)) nan else percent(self.count(key), self.total);
    }
    /// Sparse OUT/LIST enumeration avoids materializing the Cartesian product.
    pub fn keys(self: Table, a: std.mem.Allocator, sparse: bool, keep_zero: bool) ![]usize {
        if (sparse) {
            const result = try a.alloc(usize, self.cell_count);
            for (result, 0..) |*k, i| k.* = i;
            return result;
        }
        var result: std.ArrayList(usize) = .empty;
        var it = self.counts.iterator();
        while (it.next()) |e| if (keep_zero or e.value_ptr.* != 0) {
            try result.append(a, e.key_ptr.*);
        };
        std.mem.sort(usize, result.items, {}, struct {
            fn less(_: void, l: usize, r: usize) bool {
                return l < r;
            }
        }.less);
        return result.items;
    }
    /// One-way or two-way-stratum inference input, using the parsed SCORES type.
    pub fn matrix(self: *const Table, a: std.mem.Allocator, stratum: usize) !?ScoredMatrix {
        if (self.negative) return null;
        if (self.dimensions.len > 1) {
            const sl = try self.slice(a, stratum);
            return sl.matrix(a, self.score_kind);
        }
        var levels: std.ArrayList(Level) = .empty;
        var counts: std.ArrayList(f64) = .empty;
        for (self.dimensions[0].levels, 0..) |l, k| if (!self.excluded(k)) {
            try levels.append(a, l);
            try counts.append(a, self.count(k));
        };
        return .{ .matrix = .{ .rows = levels.items.len, .cols = 1, .counts = counts.items, .row_scores = try scores(a, levels.items, counts.items, self.score_kind), .col_scores = &.{1} }, .row_levels = levels.items, .col_levels = &.{}, .numeric_table_scores_valid = self.score_kind != .table or validNumericScores(levels.items) };
    }
    pub fn slice(self: *const Table, a: std.mem.Allocator, stratum: usize) !Slice {
        const n = self.dimensions.len;
        const nr = self.dimensions[n - 2].levels.len;
        const nc = self.dimensions[n - 1].levels.len;
        const rt = try a.alloc(f64, nr);
        @memset(rt, 0);
        const ct = try a.alloc(f64, nc);
        @memset(ct, 0);
        var result = Slice{ .table = self, .stratum = stratum, .row_totals = rt, .col_totals = ct };
        var it = self.counts.iterator();
        while (it.next()) |e| {
            if (e.key_ptr.* / (nr * nc) != stratum) continue;
            result.observed = true;
            const r = e.key_ptr.* / nc % nr;
            const c = e.key_ptr.* % nc;
            if (result.excluded(r, c)) {
                result.missing += e.value_ptr.*;
                continue;
            }
            result.total += e.value_ptr.*;
            rt[r] += e.value_ptr.*;
            ct[c] += e.value_ptr.*;
        }
        return result;
    }
};
pub const Slice = struct {
    table: *const Table,
    stratum: usize,
    row_totals: []f64,
    col_totals: []f64,
    total: f64 = 0,
    missing: f64 = 0,
    observed: bool = false,
    pub fn rows(self: Slice) []Level {
        return self.table.dimensions[self.table.dimensions.len - 2].levels;
    }
    pub fn cols(self: Slice) []Level {
        return self.table.dimensions[self.table.dimensions.len - 1].levels;
    }
    pub fn key(self: Slice, r: usize, c: usize) usize {
        return (self.stratum * self.rows().len + r) * self.cols().len + c;
    }
    pub fn count(self: Slice, r: usize, c: usize) f64 {
        return self.table.count(self.key(r, c));
    }
    pub fn excluded(self: Slice, r: usize, c: usize) bool {
        return !self.table.include_missing and (self.rows()[r].missing or self.cols()[c].missing);
    }
    pub fn expected(self: Slice, r: usize, c: usize) f64 {
        if (self.table.negative or self.excluded(r, c) or self.total == 0) return nan;
        return self.row_totals[r] * self.col_totals[c] / self.total;
    }
    pub fn metrics(self: Slice, r: usize, c: usize) Metrics {
        return self.cellMetrics(r, c, true);
    }
    pub fn basicMetrics(self: Slice, r: usize, c: usize) Metrics {
        return self.cellMetrics(r, c, false);
    }
    fn cellMetrics(self: Slice, r: usize, c: usize, cumulative_requested: bool) Metrics {
        const cnt = self.count(r, c);
        const e = self.expected(r, c);
        const dev = cnt - e;
        const pearson = if (e > 0) dev / @sqrt(e) else nan;
        const variance = e * (1 - self.row_totals[r] / self.total) * (1 - self.col_totals[c] / self.total);
        const suppressed = self.table.negative or self.excluded(r, c);
        var cumulative: f64 = 0;
        if (cumulative_requested) for (0..r + 1) |i| if (!self.excluded(i, c)) {
            cumulative += self.count(i, c);
        };
        return .{ .expected = e, .deviation = dev, .pearson = pearson, .standardized = if (variance > 0) dev / @sqrt(variance) else nan, .chi2 = if (e > 0) dev * dev / e else nan, .percent = if (suppressed) nan else percent(cnt, self.total), .row_percent = if (suppressed) nan else percent(cnt, self.row_totals[r]), .col_percent = if (suppressed) nan else percent(cnt, self.col_totals[c]), .cumcol = if (suppressed) nan else percent(cumulative, self.col_totals[c]), .total_percent = if (suppressed) nan else percent(cnt, self.table.total) };
    }
    /// Dev4 boundary: row-major nonmissing levels and weighted scores.
    /// Negative weights are not eligible for statistics; return no matrix.
    pub fn matrix(self: Slice, a: std.mem.Allocator, score: Score) !?ScoredMatrix {
        if (self.table.negative) return null;
        var rl: std.ArrayList(Level) = .empty;
        var cl: std.ArrayList(Level) = .empty;
        var ri: std.ArrayList(usize) = .empty;
        var ci: std.ArrayList(usize) = .empty;
        for (self.rows(), 0..) |l, i| if (self.table.include_missing or !l.missing) {
            try rl.append(a, l);
            try ri.append(a, i);
        };
        for (self.cols(), 0..) |l, i| if (self.table.include_missing or !l.missing) {
            try cl.append(a, l);
            try ci.append(a, i);
        };
        const counts = try a.alloc(f64, rl.items.len * cl.items.len);
        const rt = try a.alloc(f64, rl.items.len);
        const ct = try a.alloc(f64, cl.items.len);
        for (ri.items, 0..) |r, i| {
            rt[i] = self.row_totals[r];
            for (ci.items, 0..) |c, j| counts[i * cl.items.len + j] = self.count(r, c);
        }
        for (ci.items, 0..) |c, j| ct[j] = self.col_totals[c];
        return .{ .matrix = .{ .rows = rl.items.len, .cols = cl.items.len, .counts = counts, .row_scores = try scores(a, rl.items, rt, score), .col_scores = try scores(a, cl.items, ct, score) }, .row_levels = rl.items, .col_levels = cl.items, .numeric_table_scores_valid = score != .table or (validNumericScores(rl.items) and validNumericScores(cl.items)) };
    }
};
pub const Metrics = struct { expected: f64, deviation: f64, chi2: f64, pearson: f64, standardized: f64, percent: f64, row_percent: f64, col_percent: f64, cumcol: f64, total_percent: f64 };
pub const nan = std.math.nan(f64);
pub fn percent(count: f64, total: f64) f64 {
    return if (total == 0) nan else 100 * count / total;
}
pub fn validNumericScores(levels: []const Level) bool {
    for (levels) |l| if (l.raw == .num and std.math.isNan(l.raw.num)) return false;
    return true;
}
pub fn scores(a: std.mem.Allocator, levels: []const Level, counts: []const f64, kind: Score) ![]f64 {
    const result = try a.alloc(f64, levels.len);
    var total: f64 = 0;
    for (counts) |n| total += n;
    var invalid_numeric = false;
    for (levels) |l| if (l.raw == .num and std.math.isNan(l.raw.num)) {
        invalid_numeric = true;
    };
    var before: f64 = 0;
    for (levels, counts, 0..) |l, n, i| {
        const rank = before + (n + 1) / 2;
        result[i] = switch (kind) {
            .table => switch (l.raw) {
                .num => |x| if (invalid_numeric) @floatFromInt(i) else x,
                .str => @floatFromInt(i + 1),
            },
            .rank => rank,
            .ridit => if (total == 0) nan else rank / total,
            .modridit => rank / (total + 1),
        };
        before += n;
    }
    return result;
}

test "weighted table scores and matrix metrics" {
    var ar = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer ar.deinit();
    const a = ar.allocator();
    var rowlevels = [_]Level{ .{ .value = .{ .num = 10 }, .raw = .{ .num = 10 }, .missing = false, .frequency = 4 }, .{ .value = .{ .num = 20 }, .raw = .{ .num = 20 }, .missing = false, .frequency = 6 } };
    var collevels = rowlevels;
    var dims = [_]Dimension{ .{ .name = "r", .levels = &rowlevels }, .{ .name = "c", .levels = &collevels } };
    var tab = try Table.init(a, &dims, false);
    try tab.add(a, 0, 3);
    try tab.add(a, 1, 1);
    try tab.add(a, 2, 2);
    try tab.add(a, 3, 4);
    const sl = try tab.slice(a, 0);
    const m = (try sl.matrix(a, .rank)).?;
    try std.testing.expectEqualSlices(f64, &.{ 3, 1, 2, 4 }, m.matrix.counts);
    try std.testing.expectEqualSlices(f64, &.{ 2.5, 7.5 }, m.matrix.row_scores.?);
    const ridit = try scores(a, &rowlevels, &.{ 4, 6 }, .ridit);
    try std.testing.expectEqualSlices(f64, &.{ 0.25, 0.75 }, ridit);
    try std.testing.expectApproxEqAbs(@as(f64, 2), sl.metrics(0, 0).expected, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), sl.metrics(0, 0).chi2, 1e-12);
    try std.testing.expectEqualSlices(f64, &.{ 10, 20 }, try scores(a, &rowlevels, &.{ 4, 6 }, .table));
    const mod = try scores(a, &rowlevels, &.{ 4, 6 }, .modridit);
    try std.testing.expectApproxEqAbs(@as(f64, 2.5 / 11.0), mod[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 7.5 / 11.0), mod[1], 1e-12);
    const metrics = sl.metrics(0, 0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / @sqrt(2.0)), metrics.pearson, 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0 / @sqrt(0.6)), metrics.standardized, 1e-12);
    try std.testing.expectEqual(@as(f64, 30), metrics.percent);
    try std.testing.expectEqual(@as(f64, 75), metrics.row_percent);
    try std.testing.expectEqual(@as(f64, 60), metrics.col_percent);
    try std.testing.expectEqual(@as(f64, 60), metrics.cumcol);
}
