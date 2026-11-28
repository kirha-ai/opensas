//! STAT-RMSTREG-001 permanent tests: PROC / MODEL / FREQ / BY parsing,
//! defaults, the observation-selection rules, the Kaplan-Meier RMST and
//! pseudovalue kernel (hand mathematics stated next to each check) and the
//! loud execution boundaries. All data are invented (D-011). The full
//! listings are covered by tests/corpus/stat_rmstreg001_*.sas against SAS 9.4.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const rmstreg = @import("rmstreg.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

/// t, status, age, f, g
fn build(a: std.mem.Allocator, lib: *Library) !void {
    const s = try a.create(Dataset);
    s.* = Dataset.init(a, "s");
    for ([_][]const u8{ "t", "status", "age", "f", "g" }) |n| _ = try s.addColumn(n, .num);
    _ = try s.addColumn("c", .char);
    const rows = [_][5]f64{
        .{ 1, 1, 30, 1, 1 },   .{ 2, 0, 40, 1, 1 },  .{ 3, 1, 50, 1, 1 },   .{ 4, 1, 60, 1, 1 },
        .{ nan, 1, 30, 1, 1 }, .{ -1, 1, 30, 1, 1 }, .{ 5, nan, 30, 1, 1 }, .{ 5, 1, nan, 1, 1 },
        .{ 5, 1, 30, nan, 1 }, .{ 5, 1, 30, 0.5, 1 }, .{ 6, 1, 35, 2.7, 1 },
    };
    for (rows) |r| try s.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] }, .{ .str = "k" } });
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
    fn parse(self: *Env, source: []const u8) !rmstreg.Spec {
        return rmstreg.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, output: *std.ArrayList(u8), source: []const u8) !void {
        return rmstreg.run(self.cx(), output, try lex.tokenize(self.arena.allocator(), source, &self.diags));
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

test "STAT-RMSTREG-001 PROC and MODEL defaults and explicit settings" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const d = try env.parse("proc rmstreg data=s; model t*status(0)=age; run;");
    try expectEqual(@as(f64, 0.05), d.alpha);
    try expect(d.tau == null);
    try expectEqual(rmstreg.Link.log, d.link);
    try expectEqual(@as(usize, 20), d.namelen);
    try expectEqual(@as(usize, 50), d.maxiter);
    try expectEqual(@as(f64, 1e-4), d.converge);
    try expect(!d.noint and !d.noprint and d.frequency == null);
    try expectEqualStrings("WORK.S", d.data_name);
    const e = try env.parse("proc rmstreg data=work.s tau=3.5 alpha=0.1 namelen=30 singular=1e-8 noprint; freq f; model t*status(0, 2)=age / link=id method=pv noint alpha=0.2 maxit=7 converge=1e-6; run;");
    try expectEqual(@as(f64, 3.5), e.tau.?);
    try expectEqual(@as(f64, 0.2), e.alpha); // MODEL ALPHA= overrides PROC ALPHA=
    try expectEqual(rmstreg.Link.linear, e.link);
    try expectEqual(@as(usize, 30), e.namelen);
    try expectEqual(@as(usize, 7), e.maxiter);
    try expect(e.noint and e.noprint and e.frequency.? == 3);
    try expectEqual(@as(usize, 2), e.censor_values.len);
    try expectEqual(@as(f64, 2), e.censor_values[1]);
    try expectEqualStrings("WORK.S", e.data_name);
    // FREQUENCY alias, LINEAR/IDENTITY aliases, the first of two MODEL statements.
    const f = try env.parse("proc rmstreg data=s tau=2; frequency f; model t=age / link=linear; model t=g / link=log; run;");
    try expectEqual(@as(usize, 3), f.frequency.?);
    try expectEqual(rmstreg.Link.linear, f.link);
    try expectEqual(@as(usize, 1), f.covariates.len);
    try expectEqual(@as(usize, 2), f.covariates[0]);
    try expect(f.censor == null);
}

fn expectEqualStrings(x: []const u8, y: []const u8) !void {
    return std.testing.expectEqualStrings(x, y);
}

fn expectFail(source: []const u8, gap: bool, message: []const u8) !void {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    if (env.run(&out, source)) |_| return error.TestExpectedError else |_| {}
    try expect(contains(env.lastError(), message));
    try expectEqual(gap, diag.gapHit());
    try expectEqual(@as(usize, 0), out.items.len);
    diag.resetGap();
}

test "STAT-RMSTREG-001 invalid input is a user error" {
    try expectFail("proc rmstreg data=s tau=-1; model t*status(0)=age; run;", false, "The parameter value -1 is less than the minimum allowed value of 0.");
    try expectFail("proc rmstreg data=s tau=0; model t*status(0)=age; run;", false, "The TAU= value must be positive.");
    // SAS 9.4 reference log texts (close-out batch).
    try expectFail("proc rmstreg data=s alpha=1.5; model t*status(0)=age; run;", false, "The parameter value 1.5 is not within the required range of 0 and 1.");
    try expectFail("proc rmstreg data=s; model t*status(0)=age / alpha=2; run;", false, "The parameter value 2 is not within the required range of 0 and 1.");
    try expectFail("proc rmstreg data=s namelen=10; model t*status(0)=age; run;", false, "The parameter value 10 is not within the required range of 20 and 200.");
    try expectFail("proc rmstreg data=s namelen=201; model t*status(0)=age; run;", false, "The parameter value 201 is not within the required range of 20 and 200.");
    try expectFail("proc rmstreg data=s singular=2; model t*status(0)=age; run;", false, "The parameter value 2 is not within the required range of 0 and 1.");
    try expectFail("proc rmstreg data=s; freq c; model t*status(0)=age; run;", false, "Variable c in list does not match type prescribed for this list.");
    try expectFail("proc rmstreg data=s namelen=25.5; model t*status(0)=age; run;", false, "Expecting an integer constant.");
    try expectFail("proc rmstreg data=s; run;", false, "MODEL statement required");
    try expectFail("proc rmstreg data=s; model t*status(0)=nosuch; run;", false, "Variable nosuch not found.");
    try expectFail("proc rmstreg data=s; model c*status(0)=age; run;", false, "must be numeric");
    try expectFail("proc rmstreg data=s; model t*status(0)=age / link=logit; run;", false, "invalid statement or token logit");
    try expectFail("proc rmstreg data=s; weight f; model t*status(0)=age; run;", false, "invalid statement or token weight");
    try expectFail("proc rmstreg data=s bogus; model t*status(0)=age; run;", false, "invalid statement or token bogus");
    try expectFail("proc rmstreg data=nosuch; model t*status(0)=age; run;", false, "input dataset not found");
}

test "STAT-RMSTREG-001 valid but unimplemented features are loud gaps" {
    try expectFail("proc rmstreg data=s ithistory; model t*status(0)=age; run;", true, "ITHISTORY");
    try expectFail("proc rmstreg data=s outpv=o; model t*status(0)=age; run;", true, "OUTPV=");
    try expectFail("proc rmstreg data=s; class g; model t*status(0)=age; run;", true, "class statement");
    try expectFail("proc rmstreg data=s; model t*status(0)=age / method=ipcw; run;", true, "IPCW");
    try expectFail("proc rmstreg data=s; model t*status(0)=age / covb; run;", true, "covb");
    try expectFail("proc rmstreg data=s; model t*status(0)=age*g; run;", true, "interactions");
    try expectFail("proc rmstreg data=s; model t*status(0)=c; run;", true, "CLASS");
    try expectFail("proc rmstreg data=s; model (t g)*status(0)=age; run;", true, "counting-process");
    try expectFail("proc rmstreg data=s tau=2; model t*status(0)=age / link=log maxiter=0; run;", true, "did not converge");
    try expectFail("proc rmstreg data=s tau=2; model t*status(0)= / noint; run;", true, "without parameters");
    try expectFail("proc rmstreg data=s; lsmeans age; model t*status(0)=age; run;", true, "lsmeans statement");
}

test "STAT-RMSTREG-001 observation selection, FREQ truncation and counts" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    const s = try env.parse("proc rmstreg data=s tau=5; freq f; model t*status(0)=age; run;");
    const sel = try rmstreg.select(env.arena.allocator(), s, s.input.ds.rows.items);
    // Used: t = 1, 2, 3, 4 (freq 1) and t = 6 (freq 2.7 -> 2). Dropped: missing
    // time, negative time, missing status, missing age, missing FREQ and FREQ
    // 0.5 (below one after truncation).
    try expectEqual(@as(usize, 11), sel.read);
    try expectEqual(@as(usize, 5), sel.units.len);
    try expectEqual(@as(f64, 2), sel.units[4].freq);
    // FREQ read counts every valid frequency with valid covariates: 4 + the
    // three response-missing or negative rows + 2 = 9.
    try expectEqual(@as(f64, 9), sel.freq_read);
    // A censoring value list marks censoring; without a censoring variable
    // every observation is an event.
    try expect(!sel.units[1].event and sel.units[0].event);
    const nc = try env.parse("proc rmstreg data=s tau=5; model t=age; run;");
    const all = try rmstreg.select(env.arena.allocator(), nc, nc.input.ds.rows.items);
    for (all.units) |u| try expect(u.event);
}

test "STAT-RMSTREG-001 Kaplan-Meier RMST and pseudovalues by hand" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const x: []const f64 = &.{1};
    // Times 1 (event), 2 (censored), 3 (event), 4 (event): S = 3/4 after 1,
    // 3/4 * 1/2 = 3/8 after 3, 0 after 4. RMST(3.5) = 1*1 + 3/4*(3-1) +
    // 3/8*(3.5-3) = 1 + 1.5 + 0.1875 = 2.6875.
    const units = [_]rmstreg.Unit{
        .{ .time = 1, .event = true, .freq = 1, .x = x },
        .{ .time = 2, .event = false, .freq = 1, .x = x },
        .{ .time = 3, .event = true, .freq = 1, .x = x },
        .{ .time = 4, .event = true, .freq = 1, .x = x },
    };
    try approx(@as(f64, 2.6875), rmstreg.rmst(&units, 3.5, null), 1e-12);
    // Without the first unit: times 2c, 3, 4: S = 1/2 after 3. RMST(3.5) =
    // 3 + 1/2*0.5 = 3.25; pseudovalue 4*2.6875 - 3*3.25 = 1.
    try approx(@as(f64, 3.25), rmstreg.rmst(&units, 3.5, 0), 1e-12);
    const pv = try rmstreg.pseudovalues(a, &units, 3.5);
    try approx(@as(f64, 1), pv[0], 1e-12);
    // A tau beyond the last time extends the last survival value (0 here).
    try approx(@as(f64, 1 + 1.5 + 0.375), rmstreg.rmst(&units, 10, null), 1e-12);
    // FREQ 2 counts as two units: leaving one out keeps the other.
    const doubled = [_]rmstreg.Unit{
        .{ .time = 1, .event = true, .freq = 2, .x = x },
        .{ .time = 3, .event = true, .freq = 2, .x = x },
    };
    // Full: S = 1/2 after 1, 0 after 3: RMST(4) = 1 + 1/2*2 = 2. Leaving one
    // unit at 1 out: S = 2/3 after 1: 1 + 2/3*2 = 7/3. Pseudovalue
    // 4*2 - 3*7/3 = 1, the unit's own min(T, tau).
    try approx(@as(f64, 1), (try rmstreg.pseudovalues(a, &doubled, 4))[0], 1e-12);
    // Intercept-only identity fit: the mean pseudovalue, sandwich variance
    // sum (y - mean)^2 / n^2. Pseudovalues of uncensored data are min(T, tau):
    // 1, 1, 3, 3 -> mean 2, variance 4 / 16 = 0.25.
    const y = [_]f64{ 1, 3 };
    const r = try rmstreg.fit(a, &doubled, &y, 1, true, .linear, 1e-4, 50, 1e-9);
    try approx(@as(f64, 2), r.beta[0], 1e-12);
    try approx(@as(f64, 0.25), r.cov[0], 1e-12);
    // Log link intercept only: log of the mean, variance 0.25 / mean^2.
    const l = try rmstreg.fit(a, &doubled, &y, 1, true, .log, 1e-4, 50, 1e-9);
    try approx(@log(2.0), l.beta[0], 1e-9);
    try approx(@as(f64, 0.0625), l.cov[0], 1e-9);
    try approx(@as(f64, 1.959963984540054), rmstreg.zCritical(0.05), 1e-12);
}

test "STAT-RMSTREG-001 BY order is checked and an empty BY group is a user error" {
    // Rows are not sorted by t: BY t is a data error before any fit.
    try expectFail("proc rmstreg data=s tau=2; by descending t; model t*status(0)=age / link=linear; run;", false, "not sorted");
    // Every observation of the only group has a missing FREQ-or-better rule
    // failure: SAS 9.4 reports the documented ERROR (rc 1), not a gap.
    try expectFail("proc rmstreg data=s tau=2; where age = .; model t*status(0)=age / link=linear; run;", false, "No valid observations due to invalid or missing values in the response, explanatory, or frequency variable.");
}

test "STAT-RMSTREG-001 duplicate FREQ, ALPHA endpoints and the ALPHA=0 critical value" {
    var env: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer env.arena.deinit();
    try env.init();
    // SAS 9.4 reference: of two FREQ statements the first is used.
    const d = try env.parse("proc rmstreg data=s; freq f; freq g; model t*status(0)=age; run;");
    try expectEqual(@as(usize, 3), d.frequency.?);
    const z0 = try env.parse("proc rmstreg data=s alpha=0; model t*status(0)=age; run;");
    try expectEqual(@as(f64, 0), z0.alpha);
    const z1 = try env.parse("proc rmstreg data=s; model t*status(0)=age / alpha=1; run;");
    try expectEqual(@as(f64, 1), z1.alpha);
    // probit(1 - 1e-15) = 7.941345 (hand: Mills ratio); SAS 9.4 reference
    // half-width 4.5282 / SE 0.5702 = 7.941.
    try approx(@as(f64, 7.941345), rmstreg.zCritical(0), 2e-5);
    try approx(@as(f64, 0), rmstreg.zCritical(1), 1e-9);
    try approx(@as(f64, 7.941345), rmstreg.zCritical(1e-16), 2e-5); // SAS: same as ALPHA=0
    // SAS 9.4 reference ALPHA=1e-12: half-width 4.0659 / SE 0.5702 = 7.131;
    // probit(1 - 5e-13) = 7.1305 (independent erfc bisection).
    try approx(@as(f64, 7.1305), rmstreg.zCritical(1e-12), 2e-4);
    const sg = try env.parse("proc rmstreg data=s singular=0; model t*status(0)=age; run;");
    try expectEqual(@as(f64, 0), sg.singular);
    try approx(@as(f64, 1.959964), rmstreg.zCritical(0.05), 1e-6);
}
