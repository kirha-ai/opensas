//! Small-candidate all-subset regression, SAS/STAT15.4 physical pp.8613–8617.
//! Selection always uses the same complete-case sample and the full candidate
//! model's MSE for Mallows Cp. Exhaustive search is exact within the size cap.
const std = @import("std");
const diag = @import("../diag.zig");
const A = std.mem.Allocator;
pub const Method = enum { none, rsquare, adjrsq, cp, forward, backward, stepwise, maxr, minr };
pub const Options = struct {
    method: Method = .none,
    start: ?usize = null,
    stop: ?usize = null,
    best: ?usize = null,
    include: usize = 0,
    include_specified: bool = false,
    sigma: ?f64 = null,
    entry: ?f64 = null,
    stay: ?f64 = null,
    maxstep: ?usize = null,
};
pub const Output = struct {
    edf: bool = false,
    rsquare: bool = false,
    adjrsq: bool = false,
    cp: bool = false,
    sse: bool = false,
    mse: bool = false,
    pub fn any(self: Output) bool {
        return self.edf or self.rsquare or self.adjrsq or self.cp or self.sse or self.mse;
    }
};
pub const Candidate = struct {
    mask: u16,
    size: usize,
    parameters: usize,
    error_df: usize,
    sse: f64,
    mse: f64,
    rsquare: f64,
    adjrsq: f64,
    cp: f64,
};

fn fit(a: A, x: []const f64, y: []const f64, weights: []const f64, predictors: usize, intercept: bool, mask: u16, count: usize, singular: f64) diag.Error!Candidate {
    const size: usize = @popCount(mask);
    const p = size + @as(usize, if (intercept) 1 else 0);
    if (p == 0 or count <= p) return error.ExecError;
    const original_p = predictors + @as(usize, if (intercept) 1 else 0);
    const design = try a.alloc(f64, y.len * p);
    for (0..y.len) |i| {
        var column: usize = 0;
        if (intercept) {
            design[i * p] = 1;
            column = 1;
        }
        for (0..predictors) |j| if (mask & (@as(u16, 1) << @intCast(j)) != 0) {
            design[i * p + column] = x[i * original_p + j + @as(usize, if (intercept) 1 else 0)];
            column += 1;
        };
    }
    var result = try @import("reg_diagnostics.zig").fit(a, design, y, y.len, p, weights, intercept, singular);
    defer result.deinit(a);
    if (result.fit.rank != p) return error.ExecError;
    const sst = if (intercept) result.fit.sst else result.fit.sst_uncorrected;
    if (!(sst > 0)) return error.ExecError;
    const df = count - p;
    const sse = result.fit.sse;
    const r2 = 1 - sse / sst;
    return .{ .mask = mask, .size = size, .parameters = p, .error_df = df, .sse = sse, .mse = sse / @as(f64, @floatFromInt(df)), .rsquare = r2, .adjrsq = 1 - (1 - r2) * @as(f64, @floatFromInt(count - @as(usize, if (intercept) 1 else 0))) / @as(f64, @floatFromInt(df)), .cp = undefined };
}

fn before(method: Method, lhs: Candidate, rhs: Candidate) bool {
    return switch (method) {
        .rsquare => if (lhs.size != rhs.size) lhs.size < rhs.size else lhs.rsquare > rhs.rsquare,
        .adjrsq => lhs.adjrsq > rhs.adjrsq,
        .cp => lhs.cp < rhs.cp,
        else => false,
    };
}
fn score(method: Method, candidate: Candidate) f64 {
    return switch (method) {
        .rsquare => candidate.rsquare,
        .adjrsq => candidate.adjrsq,
        .cp => candidate.cp,
        else => unreachable,
    };
}

pub fn compute(a: A, x: []const f64, y: []const f64, weights: []const f64, predictors: usize, intercept: bool, count: usize, singular: f64, options: Options) diag.Error![]const Candidate {
    if (options.method == .maxr or options.method == .minr) return (try improvement(a, x, y, weights, predictors, intercept, count, singular, options)).selected;
    if (options.method == .forward or options.method == .backward or options.method == .stepwise) {
        const path = try sequence(a, x, y, weights, predictors, intercept, count, singular, options);
        return try a.dupe(Candidate, &.{path.final});
    }
    if (options.method == .none or predictors == 0 or predictors > 10 or weights.len != y.len or x.len != y.len * (predictors + @as(usize, if (intercept) 1 else 0))) return error.ExecError;
    const start = options.start orelse 1;
    const stop = options.stop orelse predictors;
    if (options.include > predictors or start > stop or stop > predictors or (start == 0 and !intercept) or options.best == 0) return error.ExecError;
    const maximum = @as(usize, 1) << @intCast(predictors);
    const all: u16 = @intCast(maximum - 1);
    const forced: u16 = (@as(u16, 1) << @intCast(options.include)) - 1;
    const candidates = try a.alloc(Candidate, maximum);
    var used: usize = 0;
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const full = try fit(scratch.allocator(), x, y, weights, predictors, intercept, all, count, singular);
    if (options.sigma == null and full.rsquare >= 1 - 512 * std.math.floatEps(f64)) return error.ExecError;
    const full_mse = if (options.sigma) |sigma| sigma * sigma else full.mse;
    if (!(full_mse > 0) or !std.math.isFinite(full_mse)) return error.ExecError;
    _ = scratch.reset(.retain_capacity);
    for (0..maximum) |bits| {
        const mask: u16 = @intCast(bits);
        const size: usize = @popCount(mask);
        if (mask & forced != forced or size < start or size > stop) continue;
        var candidate = try fit(scratch.allocator(), x, y, weights, predictors, intercept, mask, count, singular);
        candidate.cp = candidate.sse / full_mse - @as(f64, @floatFromInt(count)) + 2 * @as(f64, @floatFromInt(candidate.parameters));
        candidates[used] = candidate;
        used += 1;
        _ = scratch.reset(.retain_capacity);
    }
    if (used == 0) return error.ExecError;
    std.mem.sort(Candidate, candidates[0..used], options.method, before);
    // The source does not define exact-tie ordering. Refuse a nonunique order
    // rather than silently baking an arbitrary mask/column order into a golden.
    for (1..used) |i| {
        if (options.method == .rsquare and candidates[i - 1].size != candidates[i].size) continue;
        const left = score(options.method, candidates[i - 1]);
        const right = score(options.method, candidates[i]);
        if (@abs(left - right) <= 128 * std.math.floatEps(f64) * @max(1, @max(@abs(left), @abs(right)))) return error.ExecError;
    }
    if (options.best) |best| {
        if (options.method != .rsquare) return candidates[0..@min(best, used)];
        var accepted: usize = 0;
        var prior_size: usize = std.math.maxInt(usize);
        var in_size: usize = 0;
        for (candidates[0..used]) |candidate| {
            if (candidate.size != prior_size) {
                prior_size = candidate.size;
                in_size = 0;
            }
            if (in_size < best) {
                candidates[accepted] = candidate;
                accepted += 1;
            }
            in_size += 1;
        }
        return candidates[0..accepted];
    }
    return candidates[0..used];
}

pub const Stop = enum { significance, maxsteps, just_removed, exhausted, size_limit };
pub const Step = struct { entered: bool, variable: usize, f: f64, probability: f64, candidate: Candidate };
pub const Path = struct { initial: Candidate, final: Candidate, steps: []const Step, stop: Stop };
fn find(models: []const Candidate, mask: u16) Candidate {
    for (models) |model| if (model.mask == mask) return model;
    unreachable;
}
fn equivalent(left: f64, right: f64) bool {
    return @abs(left - right) <= 128 * std.math.floatEps(f64) * @max(1, @max(@abs(left), @abs(right)));
}

/// Forward/backward/stepwise use partial F tests; final OUTEST is one model.
/// All candidate scores share the identical complete-case sample. This bounded
/// implementation precomputes its small lattice, exposing every visited step.
pub fn sequence(a: A, x: []const f64, y: []const f64, weights: []const f64, predictors: usize, intercept: bool, count: usize, singular: f64, options: Options) diag.Error!Path {
    if (!intercept or (options.method != .forward and options.method != .backward and options.method != .stepwise) or options.include > predictors) return error.ExecError;
    const entry = options.entry orelse (if (options.method == .forward) @as(f64, 0.50) else 0.15);
    const stay = options.stay orelse (if (options.method == .backward) @as(f64, 0.10) else 0.15);
    if (!(entry >= 0 and entry <= 1 and stay >= 0 and stay <= 1)) return error.ExecError;
    const all = try compute(a, x, y, weights, predictors, intercept, count, singular, .{ .method = .rsquare, .start = 0 });
    const forced = (@as(u16, 1) << @intCast(options.include)) - 1;
    const start = @max(options.start orelse 0, options.include);
    if (start > predictors) return error.ExecError;
    const initial_mask = if (options.method == .backward) (@as(u16, 1) << @intCast(predictors)) - 1 else (@as(u16, 1) << @intCast(start)) - 1;
    const initial = find(all, initial_mask);
    var current = initial;
    var steps: std.ArrayList(Step) = .empty;
    const maximum = options.maxstep orelse (predictors * @as(usize, if (options.method == .stepwise) 3 else 1));
    var last_removed: ?usize = null;
    var removal = options.method == .backward or (options.method == .stepwise and start > 0);
    var stop: Stop = .significance;
    while (true) {
        if ((!removal and current.size == predictors) or (options.method == .backward and current.mask == forced)) {
            stop = .exhausted;
            break;
        }
        if (steps.items.len >= maximum) {
            stop = .maxsteps;
            break;
        }
        var chosen: ?Step = null;
        var tied = false;
        for (0..predictors) |j| {
            const bit = @as(u16, 1) << @intCast(j);
            const active = current.mask & bit != 0;
            if (removal) {
                if (!active or forced & bit != 0) continue;
            } else if (active) continue;
            const next = find(all, if (removal) current.mask & ~bit else current.mask | bit);
            const f = if (removal) @max(0, next.sse - current.sse) / current.mse else @max(0, current.sse - next.sse) / next.mse;
            const probability = @import("reg_fit.zig").fProbability(f, 1, if (removal) current.error_df else next.error_df);
            if (!std.math.isFinite(f) or !std.math.isFinite(probability)) return error.ExecError;
            if (if (removal) probability <= stay else probability > entry) continue;
            const candidate = Step{ .entered = !removal, .variable = j, .f = f, .probability = probability, .candidate = next };
            if (chosen) |previous| {
                if (equivalent(f, previous.f)) {
                    tied = true;
                } else if (if (removal) f < previous.f else f > previous.f) {
                    chosen = candidate;
                    tied = false;
                }
            } else chosen = candidate;
        }
        if (tied) return error.ExecError;
        if (chosen) |step| {
            if (!removal and last_removed != null and step.variable == last_removed.?) {
                stop = .just_removed;
                break;
            }
            try steps.append(a, step);
            current = step.candidate;
            if (removal) last_removed = step.variable;
            if (options.method == .stepwise) removal = true;
        } else {
            if (options.method == .stepwise and removal) {
                removal = false;
                continue;
            }
            stop = if ((!removal and current.size == predictors) or (removal and current.mask == forced)) .exhausted else .significance;
            break;
        }
    }
    return .{ .initial = initial, .final = current, .steps = steps.items, .stop = stop };
}

pub const Improvement = struct { selected: []const Candidate, visited: []const Candidate, stop: Stop };
pub fn improvement(a: A, x: []const f64, y: []const f64, weights: []const f64, predictors: usize, intercept: bool, count: usize, singular: f64, options: Options) diag.Error!Improvement {
    if (!intercept or (options.method != .maxr and options.method != .minr) or options.include > predictors) return error.ExecError;
    const start = @max(options.start orelse 0, options.include);
    const stop = options.stop orelse predictors;
    if (start > stop or stop > predictors or stop == 0) return error.ExecError;
    const all = try compute(a, x, y, weights, predictors, intercept, count, singular, .{ .method = .rsquare, .start = 0 });
    const forced = (@as(u16, 1) << @intCast(options.include)) - 1;
    var current = find(all, (@as(u16, 1) << @intCast(start)) - 1);
    var selected: std.ArrayList(Candidate) = .empty;
    var visited: std.ArrayList(Candidate) = .empty;
    if (start > 0) try visited.append(a, current);
    while (true) {
        if (current.size > 0) {
            while (true) {
                var chosen: ?Candidate = null;
                for (0..predictors) |remove| {
                    const removed = @as(u16, 1) << @intCast(remove);
                    if (current.mask & removed == 0 or forced & removed != 0) continue;
                    for (0..predictors) |add| {
                        const added = @as(u16, 1) << @intCast(add);
                        if (current.mask & added != 0) continue;
                        const candidate = find(all, (current.mask & ~removed) | added);
                        if (candidate.rsquare <= current.rsquare or equivalent(candidate.rsquare, current.rsquare)) continue;
                        if (chosen == null or (if (options.method == .maxr) candidate.rsquare > chosen.?.rsquare else candidate.rsquare < chosen.?.rsquare)) chosen = candidate;
                    }
                }
                if (chosen) |candidate| {
                    current = candidate;
                    try visited.append(a, current);
                } else break;
            }
            try selected.append(a, current);
            if (current.size == stop) break;
        }
        var added: ?Candidate = null;
        for (0..predictors) |j| {
            const bit = @as(u16, 1) << @intCast(j);
            if (current.mask & bit != 0) continue;
            const candidate = find(all, current.mask | bit);
            if (added == null or candidate.rsquare > added.?.rsquare) added = candidate;
        }
        current = added orelse return error.ExecError;
        try visited.append(a, current);
    }
    return .{ .selected = selected.items, .visited = visited.items, .stop = if (stop == predictors) .exhausted else .size_limit };
}
