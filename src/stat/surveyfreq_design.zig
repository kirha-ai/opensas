//! PROC SURVEYFREQ sample design and Taylor-series (linearization) variance,
//! SAS/STAT 15.4 physical pp.9627-9633: valid-observation selection under the
//! WEIGHT / STRATA / CLUSTER rules, PSUs nested within first-stage strata, and
//! the between-PSU variance of a linearized total with an optional finite
//! population correction.
//! ponytail: kept self-contained (no other survey procedure shares it yet);
//! STAT-COMMON-016 owns unifying the survey design kernels.
const std = @import("std");
const Value = @import("../value.zig").Value;
const A = std.mem.Allocator;

/// RATE= / TOTAL= single-value forms (the data set forms are not implemented).
pub const Fpc = union(enum) {
    none,
    /// First-stage sampling fraction, already a proportion in (0, 1].
    rate: f64,
    /// Number of PSUs in the population, for every stratum.
    total: f64,
};

pub const Roles = struct {
    strata: []const usize = &.{},
    clusters: []const usize = &.{},
    weight: ?usize = null,
    /// MISSING: a missing STRATA or CLUSTER value is a valid category.
    missing: bool = false,
    fpc: Fpc = .none,
};

pub const Design = struct {
    /// Row indices (into the rows given to `build`) of the valid observations.
    kept: []const usize,
    /// Per valid observation: sampling weight and PSU index.
    weight: []const f64,
    psu: []const usize,
    /// Per PSU: stratum index.
    psu_stratum: []const usize,
    /// Per stratum: number of PSUs, the factor (1 - f_h) and the index (into
    /// the rows given to `build`) of its first observation.
    stratum_psus: []const usize,
    stratum_rep: []const usize = &.{},
    stratum_fpc: []const f64,
    read: usize,
    /// Observations dropped for a missing or nonpositive WEIGHT value.
    bad_weight: usize,
    /// Observations dropped for a missing STRATA or CLUSTER value.
    bad_design: usize,
    sum_weights: f64,

    pub fn strata(self: Design) usize {
        return self.stratum_psus.len;
    }
    pub fn clusters(self: Design) usize {
        return self.psu_stratum.len;
    }
    /// A stratum with one PSU has no between-PSU variance estimate.
    pub fn singlePsuStratum(self: Design) bool {
        for (self.stratum_psus) |n| if (n < 2) return true;
        return false;
    }
    /// TOTAL= below a stratum's sampled PSU count gives a negative factor.
    pub fn invalidFpc(self: Design) bool {
        for (self.stratum_fpc) |f| if (f < 0) return true;
        return false;
    }
};

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}

/// Same STRATA category: equal numbers (missing equal), or equal text up to
/// trailing blanks.
pub fn sameValue(x: Value, y: Value) bool {
    return switch (x) {
        .num => |p| switch (y) {
            .num => |q| p == q or (std.math.isNan(p) and std.math.isNan(q)),
            .str => false,
        },
        .str => |p| switch (y) {
            .str => |q| std.mem.eql(u8, std.mem.trimEnd(u8, p, " "), std.mem.trimEnd(u8, q, " ")),
            .num => false,
        },
    };
}

fn appendKey(a: A, key: *std.ArrayList(u8), row: []const Value, cols: []const usize) !void {
    for (cols) |c| switch (row[c]) {
        // +0.0 folds -0.0 so the two zeros are one category.
        .num => |x| {
            const y = x + 0.0;
            try key.append(a, 'n');
            try key.appendSlice(a, std.mem.asBytes(&y));
        },
        .str => |text| {
            const t = std.mem.trimEnd(u8, text, " ");
            try key.append(a, 's');
            try key.appendSlice(a, std.mem.asBytes(&t.len));
            try key.appendSlice(a, t);
        },
    };
}

/// Valid observations (pp.9630-9631): a missing or nonpositive WEIGHT value
/// always removes the observation; a missing STRATA or CLUSTER value removes
/// it unless MISSING. Without CLUSTER every observation is its own PSU;
/// without STRATA there is one stratum. Clusters are nested within strata.
pub fn build(a: A, rows: []const []const Value, r: Roles) !Design {
    var kept: std.ArrayList(usize) = .empty;
    var weight: std.ArrayList(f64) = .empty;
    var psu: std.ArrayList(usize) = .empty;
    var psu_stratum: std.ArrayList(usize) = .empty;
    var stratum_psus: std.ArrayList(usize) = .empty;
    var stratum_rep: std.ArrayList(usize) = .empty;
    var stratum_ids = std.StringHashMap(usize).init(a);
    var psu_ids = std.StringHashMap(usize).init(a);
    var bad_weight: usize = 0;
    var bad_design: usize = 0;
    var sum: f64 = 0;
    rows: for (rows, 0..) |row, i| {
        var w: f64 = 1;
        if (r.weight) |c| {
            w = row[c].num;
            if (std.math.isNan(w) or w <= 0) {
                bad_weight += 1;
                continue;
            }
        }
        if (!r.missing) {
            for (r.strata) |c| if (isMissing(row[c])) {
                bad_design += 1;
                continue :rows;
            };
            for (r.clusters) |c| if (isMissing(row[c])) {
                bad_design += 1;
                continue :rows;
            };
        }
        var key: std.ArrayList(u8) = .empty;
        try appendKey(a, &key, row, r.strata);
        const sg = try stratum_ids.getOrPut(key.items);
        if (!sg.found_existing) {
            sg.key_ptr.* = try a.dupe(u8, key.items);
            sg.value_ptr.* = stratum_psus.items.len;
            try stratum_psus.append(a, 0);
            try stratum_rep.append(a, i);
        }
        const h = sg.value_ptr.*;
        var p: usize = psu_stratum.items.len;
        if (r.clusters.len > 0) {
            try key.append(a, '|');
            try appendKey(a, &key, row, r.clusters);
            const pg = try psu_ids.getOrPut(key.items);
            if (pg.found_existing) p = pg.value_ptr.* else {
                pg.key_ptr.* = key.items;
                pg.value_ptr.* = p;
            }
        }
        if (p == psu_stratum.items.len) {
            try psu_stratum.append(a, h);
            stratum_psus.items[h] += 1;
        }
        try kept.append(a, i);
        try weight.append(a, w);
        try psu.append(a, p);
        sum += w;
    }
    const fpc = try a.alloc(f64, stratum_psus.items.len);
    for (fpc, stratum_psus.items) |*f, n| f.* = switch (r.fpc) {
        .none => 1,
        .rate => |rate| 1 - rate,
        .total => |total| 1 - @as(f64, @floatFromInt(n)) / total,
    };
    return .{ .kept = kept.items, .weight = weight.items, .psu = psu.items, .psu_stratum = psu_stratum.items, .stratum_psus = stratum_psus.items, .stratum_rep = stratum_rep.items, .stratum_fpc = fpc, .read = rows.len, .bad_weight = bad_weight, .bad_design = bad_design, .sum_weights = sum };
}

/// Taylor-series variance of the total of `z` (one already weighted,
/// linearized value per valid observation), p.9633:
/// V = sum_h (1 - f_h) n_h / (n_h - 1) sum_i (z_hi. - zbar_h..)^2,
/// with z_hi. the PSU sums. A single-PSU stratum contributes nothing; with no
/// stratum of two or more PSUs the result is NaN (missing).
pub fn variance(a: A, d: Design, z: []const f64) !f64 {
    const sums = try a.alloc(f64, d.clusters());
    defer a.free(sums);
    @memset(sums, 0);
    for (z, d.psu) |x, p| sums[p] += x;
    const mean = try a.alloc(f64, d.strata());
    defer a.free(mean);
    const ss = try a.alloc(f64, d.strata());
    defer a.free(ss);
    @memset(mean, 0);
    @memset(ss, 0);
    for (sums, d.psu_stratum) |x, h| mean[h] += x;
    for (mean, d.stratum_psus) |*m, n| m.* /= @floatFromInt(n);
    for (sums, d.psu_stratum) |x, h| ss[h] += (x - mean[h]) * (x - mean[h]);
    var v: f64 = 0;
    var any = false;
    for (ss, d.stratum_psus, d.stratum_fpc) |s, n, f| {
        if (n < 2) continue;
        any = true;
        const nh: f64 = @floatFromInt(n);
        v += f * nh / (nh - 1) * s;
    }
    // SAS-verified: when every stratum has a single cluster the variance is
    // missing (single-cluster strata are left out of the estimate).
    return if (any) v else std.math.nan(f64);
}
