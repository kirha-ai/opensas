//! Exact orthogonal-subset references for STAT-REG-008 (S154 pp.8613–8617).
const std = @import("std");
const select = @import("reg_selection.zig");
const reg = @import("reg.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const A = std.mem.Allocator;
const design = [_]f64{
    1, -1, -1, -1, 1, 1, -1, -1, 1, -1, 1, -1, 1, 1, 1, -1,
    1, -1, -1, 1,  1, 1, -1, 1,  1, -1, 1, 1,  1, 1, 1, 1,
};
const response = [_]f64{ 4.75, 10.75, 6.75, 16.75, 5.25, 11.25, 7.25, 17.25 };
const weights = [_]f64{1} ** 8;

fn close(expected: f64, actual: f64) !void {
    // Binary64 roundoff budget for two-pass QR on the8x4 orthogonal design:
    // 8*n*p² operations covers normalization, projections and propagated
    // scalar criteria. Inputs and analytic projection coefficients are exact.
    const nu = 8 * 8 * 4 * 4 * 0x1p-53;
    try std.testing.expectApproxEqAbs(expected, actual, (nu / (1 - nu)) * @max(1, @abs(expected)));
}
fn candidates(a: A, options: select.Options) ![]const select.Candidate {
    return select.compute(a, &design, &response, &weights, 3, true, 8, 1e-9, options);
}
fn fixture(a: A, lib: *Library, extra_missing: bool) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "w", "y" }) |name| _ = try ds.addColumn(name, .num);
    for (response, 0..) |y, i| try ds.appendRow(&.{ .{ .num = design[4 * i + 1] }, .{ .num = design[4 * i + 2] }, .{ .num = design[4 * i + 3] }, .{ .num = y } });
    if (extra_missing) try ds.appendRow(&.{ .{ .num = 100 }, .{ .num = std.math.nan(f64) }, .{ .num = 100 }, .{ .num = 1e9 } });
    try lib.put("sample", ds);
}
fn run(a: A, lib: *Library, d: *diag.Diagnostics, source: []const u8) ![]const u8 {
    var listing: std.ArrayList(u8) = .empty;
    try reg.run(.{ .arena = a, .lib = lib, .diags = d }, &listing, try lex.tokenize(a, source, d));
    return listing.items;
}
fn number(ds: *Dataset, row: usize, name: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(name).?].num;
}

test "REG008 exhaustive seven subsets agree with independent orthogonal projection criteria" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // X has orthogonal columns with squared norms8. y=10+4x+2z+w/4+x*z.
    // x*z is orthogonal noise with SSE8. Missing-variable contributions to
    // SSE are exactly128,32,1/2. Full model MSE=8/(8-4)=2; SST=337/2.
    for ([_]select.Method{ .rsquare, .adjrsq, .cp }) |method| {
        const selected = try candidates(a, .{ .method = method });
        try std.testing.expectEqual(@as(usize, 7), selected.len);
        const order: []const u16 = if (method == .rsquare) &.{ 1, 2, 4, 3, 5, 6, 7 } else &.{ 3, 7, 1, 5, 2, 6, 4 };
        var seen: u16 = 0;
        for (selected, order) |candidate, mask| {
            try std.testing.expectEqual(mask, candidate.mask);
            seen |= @as(u16, 1) << @intCast(mask);
            const size: usize = @popCount(mask);
            var sse: f64 = 8;
            for ([_]f64{ 128, 32, 0.5 }, 0..) |ss, j| if (mask & (@as(u16, 1) << @intCast(j)) == 0) {
                sse += ss;
            };
            const df = 7 - size;
            try std.testing.expectEqual(size, candidate.size);
            try std.testing.expectEqual(size + 1, candidate.parameters);
            try std.testing.expectEqual(df, candidate.error_df);
            try close(sse, candidate.sse);
            try close(sse / @as(f64, @floatFromInt(df)), candidate.mse);
            try close(1 - sse / 168.5, candidate.rsquare);
            try close(1 - (sse / 168.5) * 7 / @as(f64, @floatFromInt(df)), candidate.adjrsq);
            try close(sse / 2 - 8 + 2 * @as(f64, @floatFromInt(size + 1)), candidate.cp);
        }
        try std.testing.expectEqual(@as(u16, 254), seen);
    }
}

test "REG008 BEST is per-size for RSQUARE and global for CP ADJRSQ with size INCLUDE SIGMA" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const per_size = try candidates(a, .{ .method = .rsquare, .best = 1 });
    try std.testing.expectEqual(@as(usize, 3), per_size.len);
    for (per_size, [_]u16{ 1, 3, 7 }) |c, mask| try std.testing.expectEqual(mask, c.mask);
    for ([_]select.Method{ .adjrsq, .cp }) |method| {
        const global = try candidates(a, .{ .method = method, .best = 2 });
        try std.testing.expectEqual(@as(usize, 2), global.len);
        try std.testing.expectEqual(@as(u16, 3), global[0].mask);
        try std.testing.expectEqual(@as(u16, 7), global[1].mask);
    }
    const forced = try candidates(a, .{ .method = .rsquare, .include = 2 });
    try std.testing.expectEqual(@as(usize, 2), forced.len);
    try std.testing.expectEqual(@as(u16, 3), forced[0].mask);
    try std.testing.expectEqual(@as(u16, 7), forced[1].mask);
    const sizes = try candidates(a, .{ .method = .rsquare, .start = 2, .stop = 2 });
    try std.testing.expectEqual(@as(usize, 3), sizes.len);
    for (sizes) |c| try std.testing.expectEqual(@as(usize, 2), c.size);
    const sigma = try candidates(a, .{ .method = .cp, .sigma = 0.4, .best = 1 });
    try std.testing.expectEqual(@as(u16, 7), sigma[0].mask);
    try close(50, sigma[0].cp);
    const intercept = try candidates(a, .{ .method = .rsquare, .start = 0, .stop = 0 });
    try std.testing.expectEqual(@as(usize, 1), intercept.len);
    try std.testing.expectEqual(@as(u16, 0), intercept[0].mask);
    try close(168.5, intercept[0].sse);
}

test "REG008 typed OUTEST subset estimates missing cells metadata and fixed complete-case sample" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib, true);
    const listing = try run(a, &lib, &d, "proc reg data=sample outest=selected noprint; model y=x z w / selection=rsquare best=1 cp adjrsq sse mse; run;");
    try std.testing.expectEqual(@as(usize, 0), listing.len);
    const ds = lib.find("selected").?;
    const names = [_][]const u8{ "_MODEL_", "_TYPE_", "_DEPVAR_", "_RMSE_", "Intercept", "x", "z", "w", "y", "_IN_", "_P_", "_EDF_", "_SSE_", "_MSE_", "_RSQ_", "_ADJRSQ_", "_CP_" };
    try std.testing.expectEqual(names.len, ds.columns.items.len);
    try std.testing.expectEqual(@as(usize, 3), ds.rows.items.len);
    for (ds.columns.items, names, 0..) |column, name, j| {
        try std.testing.expectEqualStrings(name, column.name);
        try std.testing.expectEqual(if (j < 3) @import("../pdv.zig").VarType.char else .num, column.type);
    }
    for ([_]f64{ 40.5, 8.5, 8 }, 0..) |sse, i| {
        const size = i + 1;
        try close(10, number(ds, i, "Intercept"));
        try close(-1, number(ds, i, "y"));
        try close(@floatFromInt(size), number(ds, i, "_IN_"));
        try close(@floatFromInt(size + 1), number(ds, i, "_P_"));
        try close(@floatFromInt(7 - size), number(ds, i, "_EDF_"));
        try close(sse, number(ds, i, "_SSE_"));
        try close(sse / @as(f64, @floatFromInt(7 - size)), number(ds, i, "_MSE_"));
        try close(@sqrt(sse / @as(f64, @floatFromInt(7 - size))), number(ds, i, "_RMSE_"));
        try close(1 - sse / 168.5, number(ds, i, "_RSQ_"));
        try close(1 - (sse / 168.5) * 7 / @as(f64, @floatFromInt(7 - size)), number(ds, i, "_ADJRSQ_"));
        try close(sse / 2 - 8 + 2 * @as(f64, @floatFromInt(size + 1)), number(ds, i, "_CP_"));
        for ([_][]const u8{ "x", "z", "w" }, [_]f64{ 4, 2, 0.25 }, 0..) |name, beta, j| {
            if (j < size) try close(beta, number(ds, i, name)) else try std.testing.expect(std.math.isNan(number(ds, i, name)));
        }
    }
    try std.testing.expect(!d.hasErrors());
}

test "REG008 invalid options unsupported presentations and criterion ties preserve output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try fixture(a, &lib, false);
    const bad_options = [_][]const u8{
        "selection=rsquare best=0", "selection=rsquare start=2 stop=1", "selection=rsquare include=4",
        "selection=cp sigma=0",     "selection=rsquare best=1.5",       "selection=not_a_method",
    };
    for (bad_options) |options| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        const source = try std.fmt.allocPrint(a, "proc reg data=sample outest=bad noprint; model y=x z w / {s}; run;", .{options});
        try std.testing.expectError(error.ParseError, run(a, &lib, &d, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expect(lib.find("bad") == null);
    }
    for ([_][]const u8{
        "proc reg data=sample outest=bad noprint; model y=x z w / selection=maxr details; run;",
        "proc reg data=sample outest=bad; model y=x z w / selection=rsquare; run;",
        "proc reg data=sample outest=bad noprint; model y=x z w / selection=rsquare details; run;",
        "proc reg data=sample outest=bad noprint; model y={x z} w / selection=forward; run;",
        "proc reg data=sample outest=bad covout noprint; model y=x z w / selection=cp; run;",
    }) |source| {
        var d = diag.Diagnostics.init(a);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, run(a, &lib, &d, source));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expect(lib.find("bad") == null);
    }
    // Symmetric signal yields exactly tied one-variable fits. Until SAS tie
    // order is established, a visible gap is safer than choosing by bit mask.
    var symmetric: [8]f64 = undefined;
    for (&symmetric, 0..) |*y, i| y.* = 10 + design[4 * i + 1] + design[4 * i + 2] + design[4 * i + 1] * design[4 * i + 2];
    try std.testing.expectError(error.ExecError, select.compute(a, &design, &symmetric, &weights, 3, true, 8, 1e-9, .{ .method = .rsquare, .stop = 1, .best = 1 }));
}

test "REG008 full rank and positive variance boundaries reject undefined selection criteria" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var aliased = design;
    for (0..8) |i| aliased[4 * i + 3] = aliased[4 * i + 1];
    try std.testing.expectError(error.ExecError, select.compute(a, &aliased, &response, &weights, 3, true, 8, 1e-9, .{ .method = .rsquare }));
    try std.testing.expectError(error.ExecError, select.compute(a, &design, &.{ 1, 1, 1, 1, 1, 1, 1, 1 }, &weights, 3, true, 8, 1e-9, .{ .method = .cp }));
    try std.testing.expectError(error.ExecError, select.compute(a, &design, &response, &weights, 3, true, 4, 1e-9, .{ .method = .rsquare }));
    try std.testing.expectError(error.ExecError, select.compute(a, &design, &response, &weights, 11, true, 8, 1e-9, .{ .method = .rsquare }));
}

fn cosineTail(power: usize, theta: f64) f64 {
    if (power == 0) return std.math.pi / 2.0 - theta;
    if (power == 1) return 1 - @sin(theta);
    const m: f64 = @floatFromInt(power);
    return (m - 1) / m * cosineTail(power - 2, theta) - @sin(theta) * std.math.pow(f64, @cos(theta), m - 1) / m;
}
fn independentFProbability(f: f64, df: usize) f64 {
    // F(1,nu)=t_nu². Substituting t=sqrt(nu)tan(theta) into the
    // Student density gives tail integral cos(theta)^(nu-1); the recurrence
    // above avoids the production incomplete-beta and probability routines.
    const theta = std.math.atan(@sqrt(f / @as(f64, @floatFromInt(df))));
    return cosineTail(df - 1, theta) / cosineTail(df - 1, 0);
}

test "REG008 forward backward stepwise paths partial F tests and default stopping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_]select.Method{ .forward, .backward, .stepwise }) |method| {
        const path = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = method });
        try std.testing.expectEqual(@as(u16, 3), path.final.mask);
        try std.testing.expectEqual(select.Stop.significance, path.stop);
        if (method == .backward) {
            try std.testing.expectEqual(@as(usize, 1), path.steps.len);
            try std.testing.expect(!path.steps[0].entered);
            try std.testing.expectEqual(@as(usize, 2), path.steps[0].variable);
            try close(0.25, path.steps[0].f);
            try close(independentFProbability(0.25, 4), path.steps[0].probability);
        } else {
            try std.testing.expectEqual(@as(usize, 2), path.steps.len);
            for (path.steps, [_]f64{ 512.0 / 27.0, 320.0 / 17.0 }, 0..) |step, f, i| {
                try std.testing.expect(step.entered);
                try std.testing.expectEqual(i, step.variable);
                try close(f, step.f);
                try close(independentFProbability(f, 6 - i), step.probability);
            }
        }
    }
}

test "REG008 sequential MAXSTEP INCLUDE START and just-removed stopping" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const limited = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = .forward, .maxstep = 1 });
    try std.testing.expectEqual(@as(u16, 1), limited.final.mask);
    try std.testing.expectEqual(select.Stop.maxsteps, limited.stop);
    const zero = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = .forward, .maxstep = 0 });
    try std.testing.expectEqual(@as(u16, 0), zero.final.mask);
    try std.testing.expectEqual(@as(usize, 0), zero.steps.len);
    const forced = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = .backward, .include = 3 });
    try std.testing.expectEqual(@as(u16, 7), forced.final.mask);
    try std.testing.expectEqual(select.Stop.exhausted, forced.stop);
    const started = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = .stepwise, .start = 3 });
    try std.testing.expectEqual(@as(u16, 7), started.initial.mask);
    try std.testing.expectEqual(@as(u16, 3), started.final.mask);
    try std.testing.expectEqual(@as(usize, 1), started.steps.len);
    const cycle = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = .stepwise, .entry = 1, .stay = 0 });
    try std.testing.expectEqual(select.Stop.just_removed, cycle.stop);
    try std.testing.expectEqual(@as(usize, 2), cycle.steps.len);
    try std.testing.expect(cycle.steps[0].entered and !cycle.steps[1].entered);
    try std.testing.expectEqual(cycle.steps[0].variable, cycle.steps[1].variable);
    const all = try select.sequence(a, &design, &response, &weights, 3, true, 8, 1e-9, .{ .method = .forward, .entry = 1 });
    try std.testing.expectEqual(@as(u16, 7), all.final.mask);
    try std.testing.expectEqual(select.Stop.exhausted, all.stop);
}

test "REG008 sequential parser aliases thresholds and final OUTEST model" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib, true);
    for ([_][]const u8{ "f sle=.5", "b slstay=.1", "stepwise slentry=.15 sls=.15" }) |method| {
        const source = try std.fmt.allocPrint(a, "proc reg data=sample outest=final noprint; model y=x z w / selection={s} cp sse; run;", .{method});
        const listing = try run(a, &lib, &d, source);
        try std.testing.expectEqual(@as(usize, 0), listing.len);
        const output = lib.find("final").?;
        try std.testing.expectEqual(@as(usize, 1), output.rows.items.len);
        try close(10, number(output, 0, "Intercept"));
        try close(4, number(output, 0, "x"));
        try close(2, number(output, 0, "z"));
        try std.testing.expect(std.math.isNan(number(output, 0, "w")));
        try close(2, number(output, 0, "_IN_"));
        try close(5, number(output, 0, "_EDF_"));
        try close(8.5, number(output, 0, "_SSE_"));
        try close(2.25, number(output, 0, "_CP_"));
    }
    try std.testing.expect(!d.hasErrors());
}

test "REG008 MAXR and MINR compare all swaps and choose largest versus smallest improvement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var correlated: [32]f64 = undefined;
    var target: [8]f64 = undefined;
    for (0..8) |i| {
        const u = design[i * 4 + 1];
        const v = design[i * 4 + 2];
        const w = design[i * 4 + 3];
        correlated[i * 4] = 1;
        correlated[i * 4 + 1] = 2 * u + v + w / 2;
        correlated[i * 4 + 2] = v;
        correlated[i * 4 + 3] = u;
        target[i] = 10 + 2 * u + v + u * v / 4;
    }
    // Orthogonal u,v,w,uv all have norm²8. The initial first-two fit is
    // (2u+v+w/2,v) with SSE81/34. Replacing v by u gives SSE21/10;
    // replacing the noisy mixture by u gives SSE1/2. MINR takes both
    // improvements (3->5->6); MAXR takes the greatest one (3->6).
    for ([_]select.Method{ .maxr, .minr }) |method| {
        const path = try select.improvement(a, &correlated, &target, &weights, 3, true, 8, 1e-9, .{ .method = method, .start = 2, .stop = 2 });
        const masks: []const u16 = if (method == .maxr) &.{ 3, 6 } else &.{ 3, 5, 6 };
        const sums: []const f64 = if (method == .maxr) &.{ 81.0 / 34.0, 0.5 } else &.{ 81.0 / 34.0, 2.1, 0.5 };
        try std.testing.expectEqual(masks.len, path.visited.len);
        for (path.visited, masks, sums) |candidate, mask, sse| {
            try std.testing.expectEqual(mask, candidate.mask);
            try close(sse, candidate.sse);
        }
        try std.testing.expectEqual(@as(usize, 1), path.selected.len);
        try std.testing.expectEqual(@as(u16, 6), path.selected[0].mask);
        try std.testing.expectEqual(select.Stop.size_limit, path.stop);
        const forced = try select.improvement(a, &correlated, &target, &weights, 3, true, 8, 1e-9, .{ .method = method, .include = 1, .stop = 2 });
        for (forced.selected) |candidate| try std.testing.expect(candidate.mask & 1 != 0);
        try std.testing.expectEqual(@as(u16, 5), forced.selected[1].mask);
    }
}

test "REG008 MAXR MINR OUTEST reports selected model at each size" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var d = diag.Diagnostics.init(a);
    try fixture(a, &lib, false);
    for ([_][]const u8{ "maxr", "minr" }) |method| {
        const source = try std.fmt.allocPrint(a, "proc reg data=sample outest=selected noprint; model y=x z w / selection={s} start=1 stop=2 cp; run;", .{method});
        _ = try run(a, &lib, &d, source);
        const output = lib.find("selected").?;
        try std.testing.expectEqual(@as(usize, 2), output.rows.items.len);
        try close(1, number(output, 0, "_IN_"));
        try close(2, number(output, 1, "_IN_"));
        try close(16.25, number(output, 0, "_CP_"));
        try close(2.25, number(output, 1, "_CP_"));
        try std.testing.expect(std.math.isNan(number(output, 0, "z")));
        try close(2, number(output, 1, "z"));
    }
    try std.testing.expect(!d.hasErrors());
}

test "REG008 precision-weight scaling preserves paths while frequency changes entry tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const doubled = [_]f64{2} ** 8;
    const weighted = try select.sequence(a, &design, &response, &doubled, 3, true, 8, 1e-9, .{ .method = .forward });
    const replicated = try select.sequence(a, &design, &response, &doubled, 3, true, 16, 1e-9, .{ .method = .forward });
    try std.testing.expectEqual(@as(u16, 3), weighted.final.mask);
    try std.testing.expectEqual(@as(u16, 7), replicated.final.mask);
    try close(2.25, weighted.final.cp);
    try close(4, replicated.final.cp);
    try std.testing.expectEqual(@as(usize, 12), replicated.final.error_df);
    // Added weak coefficient has extraSS=1, residualMSE=16/12.
    try close(0.75, replicated.steps[2].f);
    try close(independentFProbability(0.75, 12), replicated.steps[2].probability);
    const base = try candidates(a, .{ .method = .cp });
    const scaled = try select.compute(a, &design, &response, &doubled, 3, true, 8, 1e-9, .{ .method = .cp });
    for (base, scaled) |b, s| {
        try std.testing.expectEqual(b.mask, s.mask);
        try close(b.cp, s.cp);
        try close(b.rsquare, s.rsquare);
        try close(2 * b.sse, s.sse);
    }
}
