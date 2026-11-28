//! STAT-ROBUSTREG-001 permanent tests: PROC / MODEL / BY / ID / WEIGHT
//! parsing, defaults, observation selection, the M-estimation kernel and the
//! loud execution boundaries. The kernel check uses the stack-loss data
//! published in the SAS/STAT User's Guide (Chapter 107 Getting Started); the
//! expected numbers are the SAS 9.4 reference listing of that example. Other
//! data are invented (D-011). The full listings are covered by
//! tests/corpus/stat_robustreg001_*.sas.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const rr = @import("robustreg.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

const stack = [_][4]f64{
    .{ 80, 27, 89, 42 }, .{ 80, 27, 88, 37 }, .{ 75, 25, 90, 37 }, .{ 62, 24, 87, 28 },
    .{ 62, 22, 87, 18 }, .{ 62, 23, 87, 18 }, .{ 62, 24, 93, 19 }, .{ 62, 24, 93, 20 },
    .{ 58, 23, 87, 15 }, .{ 58, 18, 80, 14 }, .{ 58, 18, 89, 14 }, .{ 58, 17, 88, 13 },
    .{ 58, 18, 82, 11 }, .{ 58, 19, 93, 12 }, .{ 50, 18, 89, 8 },  .{ 50, 18, 86, 7 },
    .{ 50, 19, 72, 8 },  .{ 50, 19, 79, 8 },  .{ 50, 20, 80, 9 },  .{ 56, 20, 82, 15 },
    .{ 70, 20, 91, 15 },
};

/// s: x1 x2 x3 y w g c ; rows: stack-loss, then invented edge rows.
fn build(a: std.mem.Allocator, lib: *Library) !void {
    const s = try a.create(Dataset);
    s.* = Dataset.init(a, "s");
    for ([_][]const u8{ "x1", "x2", "x3", "y", "w", "g" }) |n| _ = try s.addColumn(n, .num);
    _ = try s.addColumn("c", .char);
    for (stack) |r| try s.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = 1 }, .{ .num = 1 }, .{ .str = "k" } });
    try lib.put("s", s);
}

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        try build(a, &self.lib);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !rr.Spec {
        return rr.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return rr.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn lastError(self: *Env) []const u8 {
        var i = self.diags.list.items.len;
        while (i > 0) {
            i -= 1;
            if (self.diags.list.items[i].severity == .err) return self.diags.list.items[i].message;
        }
        return "";
    }
};

fn contains(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

test "STAT-ROBUSTREG-001 PROC and MODEL defaults and explicit settings" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const d = try env.parse("proc robustreg data=s; model y = x1 x2; run;");
    try expectEqual(@as(f64, 4.685), d.c);
    try expectEqual(@as(f64, 1e-8), d.eps);
    try expectEqual(@as(usize, 1000), d.maxiter);
    try expectEqual(@as(f64, 0.05), d.alpha);
    try expectEqual(@as(f64, 3), d.cutoff);
    try expectEqual(@as(usize, 20), d.namelen);
    try expect(!d.diagnostics and d.weight == null and d.ids.len == 0 and d.by_cols.len == 0);
    try expectEqual(@as(usize, 2), d.regressors.len);
    try std.testing.expectEqualStrings("WORK.S", d.data_name);
    const e = try env.parse("proc robustreg data=work.s method=m(wf=bisquare(c=3.5) scale=med asympcov=h1 convergence=coef(eps=1e-6) maxiter=50) namelen=30 seed=7; model y = x1 / diagnostics alpha=0.1 cutoff=2.5 singular=1e-9; id c c; weight w; by g; run;");
    try expectEqual(@as(f64, 3.5), e.c);
    try expectEqual(@as(f64, 1e-6), e.eps);
    try expectEqual(@as(usize, 50), e.maxiter);
    try expectEqual(@as(usize, 30), e.namelen);
    try expectEqual(@as(f64, 0.1), e.alpha);
    try expectEqual(@as(f64, 2.5), e.cutoff);
    try expect(e.diagnostics and e.weight != null);
    try expectEqual(@as(usize, 1), e.ids.len); // a repeated ID variable is listed once
    try expectEqual(@as(usize, 1), e.by_cols.len);
}

test "STAT-ROBUSTREG-001 invalid declarations are user errors" {
    const bad = [_][]const u8{
        "proc robustreg data=s; run;", // MODEL required
        "proc robustreg data=s bogus; model y = x1; run;",
        "proc robustreg data=s namelen=10; model y = x1; run;",
        "proc robustreg data=s method=q; model y = x1; run;",
        "proc robustreg data=s method=m(wf=bisquare(c=0)); model y = x1; run;",
        "proc robustreg data=s; model y = x1 / alpha=1.5; run;",
        "proc robustreg data=s; model y = nope; run;",
        "proc robustreg data=s; model c = x1; run;",
        "proc robustreg data=s; model y = x1; weight c; run;",
        "proc robustreg data=s; model y = x1; id; run;",
        "proc robustreg data=s; model y = x1; freq w; run;",
        "proc robustreg data=nosuch; model y = x1; run;",
    };
    for (bad) |src| {
        var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer env.arena.deinit();
        try env.init();
        diag.resetGap();
        try std.testing.expectError(error.ParseError, env.parse(src));
        try expect(env.lastError().len > 0);
        try expect(!diag.gapHit());
    }
}

test "STAT-ROBUSTREG-001 unimplemented features are loud gaps" {
    const gaps = [_][]const u8{
        "proc robustreg data=s method=lts; model y = x1; run;",
        "proc robustreg data=s method=mm; model y = x1; run;",
        "proc robustreg data=s method=m(wf=huber); model y = x1; run;",
        "proc robustreg data=s method=m(scale=huber); model y = x1; run;",
        "proc robustreg data=s method=m(asympcov=h2); model y = x1; run;",
        "proc robustreg data=s plots=all; model y = x1; run;",
        "proc robustreg data=s fwls; model y = x1; run;",
        "proc robustreg data=s; model y = x1 / leverage; run;",
        "proc robustreg data=s; model y = x1 / noint; run;",
        "proc robustreg data=s; model y = x1 / diagnostics(all); run;",
        "proc robustreg data=s; model y = x1; test x1; run;",
        "proc robustreg data=s; class g; model y = x1; run;",
        "proc robustreg data=s; model y = x1; output out=o; run;",
        "proc robustreg data=s; model y = x1 x1*x2; run;",
    };
    for (gaps) |src| {
        var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer env.arena.deinit();
        try env.init();
        diag.resetGap();
        try std.testing.expectError(error.ParseError, env.parse(src));
        try expect(diag.gapHit());
        diag.resetGap();
    }
    const run_gaps = [_][]const u8{
        "proc robustreg data=s; model y = x1 / diagnostics; run;", // no ID
    };
    for (run_gaps) |src| {
        var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer env.arena.deinit();
        try env.init();
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        try std.testing.expectError(error.ParseError, env.run(&out, src));
        try expect(diag.gapHit());
        diag.resetGap();
        try expectEqual(@as(usize, 0), out.items.len);
    }
}

test "STAT-ROBUSTREG-001 observation selection: missing values and weights" {
    const a = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(a);
    defer arena.deinit();
    const aa = arena.allocator();
    const data = [_][3]f64{ .{ 1, 2, 1 }, .{ nan, 2, 1 }, .{ 1, nan, 1 }, .{ 1, 2, 0 }, .{ 1, 2, -1 }, .{ 1, 2, nan }, .{ 3, 4, 2.5 } };
    var rows: [data.len][]const Value = undefined;
    for (data, &rows) |d, *r| {
        const v = try aa.alloc(Value, 3);
        for (d, v) |x, *cell| cell.* = .{ .num = x };
        r.* = v;
    }
    var spec: rr.Spec = .{ .input = undefined, .response = 0, .regressors = &.{1}, .weight = 2 };
    const sel = try rr.select(aa, spec, &rows);
    try expectEqual(@as(usize, 7), sel.read);
    try expectEqual(@as(usize, 2), sel.units.len);
    try expectEqual(@as(usize, 5), sel.missing);
    try expectEqual(@as(f64, 2.5), sel.units[1].w);
    try expectEqual(@as(usize, 6), sel.units[1].obs);
    spec.weight = null;
    const plain = try rr.select(aa, spec, &rows);
    try expectEqual(@as(usize, 5), plain.units.len); // weight column ignored
}

test "STAT-ROBUSTREG-001 bisquare functions and quantiles (hand mathematics)" {
    // W(c/2) = (1 - 1/4)^2 = 0.5625; psi' (c/2) = 0.75 * (1 - 5/4) = -0.1875.
    try approx(@as(f64, 0.5625), rr.weightFn(2, 4), 1e-15);
    try approx(@as(f64, -0.1875), rr.dpsi(2, 4), 1e-15);
    try approx(@as(f64, 16.0 / 6.0), rr.rho(5, 4), 1e-15);
    // rho(c/2) = c^2/6 (1 - 0.75^3).
    try approx(16.0 / 6.0 * (1 - 0.421875), rr.rho(2, 4), 1e-15);
    // (n+1)p = 1.25 / 3.75 -> mean of the neighbours; 3 = 3rd value of 5.
    try approx(@as(f64, 1.5), rr.quantile(&.{ 1, 2, 3, 4 }, 0.25), 1e-15);
    try approx(@as(f64, 3.5), rr.quantile(&.{ 1, 2, 3, 4 }, 0.75), 1e-15);
    try approx(@as(f64, 3), rr.quantile(&.{ 1, 2, 3, 4, 9 }, 0.5), 1e-15);
    try approx(@as(f64, 1), rr.quantile(&.{ 1, 2 }, 0.25), 1e-15);
}

test "STAT-ROBUSTREG-001 M estimate reproduces the SAS 9.4 stack-loss reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const units = try a.alloc(rr.Unit, stack.len);
    for (stack, units, 0..) |r, *u, i| {
        const x = try a.alloc(f64, 4);
        x[0] = 1;
        x[1] = r[0];
        x[2] = r[1];
        x[3] = r[2];
        u.* = .{ .obs = i, .y = r[3], .w = 1, .x = x };
    }
    const res = try rr.analyze(a, units, 4, 4.685, 1e-8, 1000, 1e-8);
    const beta = [_]f64{ -42.2854, 0.9276, 0.6507, -0.1123 };
    const se = [_]f64{ 9.5045, 0.1077, 0.2940, 0.1249 };
    for (0..4) |j| {
        try approx(beta[j], res.fit.beta[j], 5e-5);
        try approx(se[j], res.se[j], 5e-5);
    }
    try approx(@as(f64, 2.2819), res.fit.scale, 5e-5);
    try approx(@as(f64, 0.6659), res.r_square, 5e-5);
    try approx(@as(f64, 29.5231), res.aicr, 5e-5);
    try approx(@as(f64, 36.3361), res.bicr, 5e-5);
    try approx(@as(f64, 125.7905), res.deviance, 5e-5);
    try approx(@as(f64, 3.0381), res.std_resid[3], 5e-5);
    try approx(@as(f64, -4.5733), res.std_resid[20], 5e-5);
}

test "STAT-ROBUSTREG-001 default listing and empty input" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    var out: std.ArrayList(u8) = .empty;
    try env.run(&out, "proc robustreg data=s; model y = x1 x2 x3; run;");
    try expect(contains(out.items, "Method                               M Estimation"));
    try expect(contains(out.items, "Intercept  1 -42.2854   9.5045 -60.9138 -23.6569   19.79     <.0001"));
    try expect(contains(out.items, "Outlier            0.0952      3.0000"));
    try expect(contains(out.items, "Deviance     125.7905"));
    try expect(!contains(out.items, "Missing Values"));
}

test "STAT-ROBUSTREG-001 weighted fit reproduces the SAS 9.4 reference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const units = try a.alloc(rr.Unit, stack.len);
    for (stack, units, 0..) |r, *u, i| {
        const x = try a.alloc(f64, 4);
        x[0] = 1;
        x[1] = r[0];
        x[2] = r[1];
        x[3] = r[2];
        u.* = .{ .obs = i, .y = r[3], .w = @floatFromInt((i + 1) % 3 + 1), .x = x };
    }
    const res = try rr.analyze(a, units, 4, 4.685, 1e-8, 1000, 1e-8);
    try approx(@as(f64, -40.5035), res.fit.beta[0], 5e-5);
    try approx(@as(f64, 8.5173), res.se[0], 5e-5);
    try approx(@as(f64, 2.2452), res.fit.scale, 5e-5);
    try approx(@as(f64, 0.7334), res.r_square, 5e-5);
    try approx(@as(f64, 61.8358), res.aicr, 5e-5);
    try approx(@as(f64, 51.3117), res.bicr, 5e-5);
    try approx(@as(f64, 197.2633), res.deviance, 5e-5);
}
