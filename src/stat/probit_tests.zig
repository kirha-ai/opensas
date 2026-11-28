//! STAT-PROBIT-001 permanent tests: PROC statement options, variable roles,
//! observation selection (missing values, WEIGHT, LOG/OPTC control group), BY
//! boundaries, the OPTC maximum-likelihood kernel and loud execution
//! boundaries. Selection data are invented (D-011); the dose-response data are
//! the published Getting Started sample of the chapter (p.8095). Expected
//! estimates are the published SAS listing values (p.8099), and the likelihood
//! identities below are hand mathematics, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const by = @import("by_groups.zig");
const probit = @import("probit.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;

const nan = std.math.nan(f64);
const Row = struct { g: f64, c: []const u8, dose: f64, r: f64, n: f64, w: f64 };
// columns: 0 g, 1 c, 2 dose, 3 r, 4 n, 5 w.   row: reason it can drop out
const sample = [_]Row{
    .{ .g = 1, .c = "a", .dose = 0, .r = 1, .n = 10, .w = 1 }, // 0: dose 0 (control under LOG+OPTC)
    .{ .g = 1, .c = "b", .dose = 1, .r = 2, .n = 10, .w = 2 }, // 1
    .{ .g = 1, .c = "a", .dose = 2, .r = nan, .n = 10, .w = 1 }, // 2: missing events
    .{ .g = 1, .c = "a", .dose = nan, .r = 4, .n = 10, .w = 1 }, // 3: missing dose
    .{ .g = 1, .c = "", .dose = 3, .r = 5, .n = 10, .w = 1 }, // 4: missing CLASS value
    .{ .g = 1, .c = "b", .dose = 4, .r = 6, .n = nan, .w = 1 }, // 5: missing trials
    .{ .g = 1, .c = "b", .dose = 5, .r = 7, .n = 10, .w = 0 }, // 6: WEIGHT = 0
    .{ .g = 1, .c = "a", .dose = 6, .r = 8, .n = 10, .w = -1 }, // 7: WEIGHT < 0
    .{ .g = 1, .c = "a", .dose = 7, .r = 9, .n = 10, .w = nan }, // 8: WEIGHT missing
    .{ .g = 2, .c = "c", .dose = -1, .r = 0, .n = 10, .w = 0.5 }, // 9: dose < 0
    .{ .g = 2, .c = "a", .dose = 2, .r = 4, .n = 10, .w = 1.5 }, // 10
};

fn fixture(a: A, lib: *Library, name: []const u8, rows: []const Row) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("c", .char);
    for ([_][]const u8{ "dose", "r", "n", "w" }) |n| _ = try ds.addColumn(n, .num);
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r.g }, .{ .str = r.c }, .{ .num = r.dose }, .{ .num = r.r }, .{ .num = r.n }, .{ .num = r.w } });
    try lib.put(name, ds);
    return ds;
}

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    ds: *Dataset = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        self.ds = try fixture(a, &self.lib, "sample", &sample);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn parse(self: *Env, source: []const u8) !probit.Spec {
        return probit.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

test "STAT-PROBIT-001 PROC statement defaults and explicit options" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const d = try e.parse("proc probit; model r/n = dose; run;");
    // Documented defaults (pp.8100-8104): C=0 not estimated, HPROB=0.10,
    // ORDER=FORMATTED, NAMELEN=20, no transformation, most recent data set.
    try expect(d.c == null and !d.optc and d.log == .none);
    try expectEqual(@as(f64, 0.10), d.hprob);
    try expectEqual(.formatted, d.order);
    try expectEqual(@as(usize, 20), d.namelen);
    try expect(!d.noprint and !d.covout and !d.inversecl and !d.lackfit and !d.plots);
    try expect(d.inest == null and d.outest == null and d.xdata == null and d.weight == null);
    try expectEqual(@as(usize, 3), d.response);
    try expectEqual(@as(?usize, 4), d.trials);
    try std.testing.expectEqualSlices(usize, &.{2}, d.effects);
    try expectEqual(@as(usize, 0), d.by_cols.len + d.class.len + d.later.len + d.model_options.len);
    try expectEqual(e.ds, d.input.ds);

    const s = try e.parse("proc probit data=work.sample log10 optc c=0.2 hprob=0.05 order=data namelen=40 noprint covout inversecl(prob=.1 to .9 by .1) lackfit plots=(predpplot ippplot) inest=i outest=work.o xdata=x; class c; model r/n = dose c / lackfit hprob=0.2; weight w; by g; output out=o p=p; run;");
    try expect(s.optc and s.log == .log10 and s.noprint and s.covout and s.inversecl and s.lackfit and s.plots);
    try expectEqual(@as(?f64, 0.2), s.c);
    try expectEqual(@as(f64, 0.05), s.hprob);
    try expectEqual(.data, s.order);
    try expectEqual(@as(usize, 40), s.namelen);
    try std.testing.expectEqualStrings("i", s.inest.?);
    try std.testing.expectEqualStrings("work.o", s.outest.?);
    try std.testing.expectEqualStrings("x", s.xdata.?);
    try std.testing.expectEqualSlices(usize, &.{1}, s.class);
    try std.testing.expectEqualSlices(usize, &.{ 2, 1 }, s.effects);
    try expectEqual(@as(?usize, 5), s.weight);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try expectEqual(@as(usize, 2), s.model_options.len);
    try std.testing.expectEqualStrings("output", s.later[0]);
    try expectEqual(@as(?usize, 2), probit.doseColumn(s));

    // Aliases and variants: LN = LOG, PLOT = PLOTS, PLOTS=NONE draws nothing,
    // single-variable response form, C=0 is the documented default rate.
    const alias = try e.parse("proc probit ln plot=none c=0 order=internal; model r = dose; run;");
    try expect(alias.log == .ln and !alias.plots and alias.trials == null);
    try expectEqual(@as(?f64, 0), alias.c);
    try expectEqual(.internal, alias.order);
    try expect((try e.parse("proc probit log order=freq; model r/n = dose; run;")).log == .ln);
    try expect((try e.parse("proc probit plots; model r/n = dose; run;")).plots);
}

test "STAT-PROBIT-001 BY: last statement wins, DESCENDING and NOTSORTED are kept" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // p.8105: "If you specify more than one BY statement, only the last one specified is used."
    const s = try e.parse("proc probit; by descending dose; model r/n = dose; by g; run;");
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try std.testing.expectEqualSlices(bool, &.{false}, s.by_desc);
    const n = try e.parse("proc probit; by descending g notsorted; model r/n = dose; run;");
    try std.testing.expectEqualSlices(bool, &.{true}, n.by_desc);
    try expect(n.notsorted);
}

test "STAT-PROBIT-001 observation selection: missing values, WEIGHT, control group and BY boundaries" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const rows = e.ds.rows.items;

    // No WEIGHT, no CLASS, no LOG: rows 2 (events), 3 (dose) and 5 (trials)
    // are missing; the other 8 of 11 are used. Dose <= 0 is an ordinary value.
    const plain = try probit.prepare(a, try e.parse("proc probit; model r/n = dose; run;"), rows);
    try expectEqual(@as(usize, 11), plain.read);
    try expectEqual(@as(usize, 3), plain.missing);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 4, 6, 7, 8, 9, 10 }, plain.rows);
    try expectEqual(@as(usize, 0), plain.control.len + plain.bad_weight + plain.nonpositive_dose);

    // CLASS adds row 4 (blank level) to the missing rows.
    const class = try probit.prepare(a, try e.parse("proc probit; class c; model r/n = dose c; run;"), rows);
    try expectEqual(@as(usize, 4), class.missing);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 6, 7, 8, 9, 10 }, class.rows);

    // WEIGHT (p.8120): zero (6), negative (7) and missing (8) weights are not used.
    const weighted = try probit.prepare(a, try e.parse("proc probit; model r/n = dose; weight w; run;"), rows);
    try expectEqual(@as(usize, 3), weighted.bad_weight);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 4, 9, 10 }, weighted.rows);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2, 1, 0.5, 1.5 }, weighted.weight);

    // LOG10 + OPTC (p.8090): dose <= 0 (rows 0 and 9) is the control group.
    const optc = try probit.prepare(a, try e.parse("proc probit log10 optc; model r/n = dose; run;"), rows);
    try std.testing.expectEqualSlices(usize, &.{ 0, 9 }, optc.control);
    try std.testing.expectEqualSlices(usize, &.{ 1, 4, 6, 7, 8, 10 }, optc.rows);
    try expectEqual(@as(usize, 0), optc.nonpositive_dose);

    // LOG without OPTC (p.8090): dose <= 0 observations are ignored.
    const ln = try probit.prepare(a, try e.parse("proc probit ln; model r/n = dose; run;"), rows);
    try expectEqual(@as(usize, 2), ln.nonpositive_dose);
    try expectEqual(@as(usize, 0), ln.control.len);
    try std.testing.expectEqualSlices(usize, &.{ 1, 4, 6, 7, 8, 10 }, ln.rows);

    // BY g: groups are rows 0..8 and 9..10; selection is per group.
    const s = try e.parse("proc probit log10 optc; by g; model r/n = dose; weight w; run;");
    const groups = try by.checkedSlices(a, e.ds, s.by_cols, s.by_desc, s.notsorted, &e.diags);
    try expectEqual(@as(usize, 2), groups.len);
    const first = try probit.prepare(a, s, groups[0].rows);
    try expectEqual(@as(usize, 9), first.read);
    try std.testing.expectEqualSlices(usize, &.{0}, first.control);
    try std.testing.expectEqualSlices(usize, &.{ 1, 4 }, first.rows);
    const second = try probit.prepare(a, s, groups[1].rows);
    try expectEqual(@as(usize, 2), second.read);
    try std.testing.expectEqualSlices(usize, &.{0}, second.control);
    try std.testing.expectEqualSlices(f64, &.{0.5}, second.control_weight);
    try std.testing.expectEqualSlices(usize, &.{1}, second.rows);

    // An empty group selects nothing.
    const empty = try probit.prepare(a, s, rows[0..0]);
    try expectEqual(@as(usize, 0), empty.read + empty.rows.len + empty.control.len);
}

// Published Getting Started sample (p.8095): 15 subjects per dose.
const doses = [_]f64{ 1.1, 1.3, 2.0, 2.2, 2.8, 3.7, 3.9, 4.4, 4.8, 5.9, 6.8 };
const responders = [_]f64{ 4, 4, 3, 5, 4, 5, 9, 8, 11, 12, 13 };

fn published(a: A) !probit.Problem {
    const x = try a.alloc(f64, doses.len * 2);
    const trials = try a.alloc(f64, doses.len);
    const weight = try a.alloc(f64, doses.len);
    for (doses, 0..) |d, i| {
        x[i * 2] = 1;
        x[i * 2 + 1] = std.math.log10(d);
        trials[i] = 15;
        weight[i] = 1;
    }
    // Control group: dose 0, 3 responders of 15; initial C = 3/15 (p.8089).
    return .{ .x = x, .events = &responders, .trials = trials, .weight = weight, .p = 2, .control_events = 3, .control_trials = 15, .c = 0.2, .estimate_c = true };
}

test "STAT-PROBIT-001 OPTC kernel reproduces the published LOG10 listing values" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const f = try probit.fitModel(a, try published(a));
    // SAS listing (p.8099): values printed to 4 decimals (2 for chi-square),
    // so each bound is half a unit of the last printed digit.
    try approx(@as(f64, -104.3945783), f.loglik, 5e-8);
    try approx(@as(f64, -4.1438), f.theta[0], 5e-5);
    try approx(@as(f64, 6.2308), f.theta[1], 5e-5);
    try approx(@as(f64, 0.2409), f.theta[2], 5e-5);
    try approx(@as(f64, 1.3415), @sqrt(f.cov[0]), 5e-5);
    try approx(@as(f64, 1.8996), @sqrt(f.cov[4]), 5e-5);
    try approx(@as(f64, 0.0523), @sqrt(f.cov[8]), 5e-5);
    const chi = (f.theta[1] / @sqrt(f.cov[4])) * (f.theta[1] / @sqrt(f.cov[4]));
    try approx(@as(f64, 10.7588), chi, 5e-5);
    const tol = probit.tolerance(f);
    try approx(@as(f64, 0.66506312), tol.mu, 5e-9);
    try approx(@as(f64, 0.16049411), tol.sigma, 5e-9);
    for ([9]f64{ 0.001158, -0.000493, 0.000954, -0.000493, 0.002394, -0.000999, 0.000954, -0.000999, 0.002731 }, tol.cov) |expected, actual|
        try approx(expected, actual, 5e-7);
    // Symmetry of the inverse observed information.
    for (0..3) |u| for (0..3) |v| try approx(f.cov[u * 3 + v], f.cov[v * 3 + u], 1e-12);
}

test "STAT-PROBIT-001 kernel identities: fixed C leaves two parameters; no information is singular" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Hand mathematics: with C fixed at 0 and a saturated two-point design
    // (x = 0 and x = 1), the MLE reproduces the observed proportions exactly:
    // Phi(b0) = 1/2 so b0 = 0, and Phi(b0 + b1) = 0.8413447460685429 = Phi(1)
    // so b1 = 1. Log likelihood = sum r*log(p) + (n-r)*log(1-p) at those p.
    const p1: f64 = 0.8413447460685429;
    const n: f64 = 1000;
    const q: probit.Problem = .{ .x = &.{ 1, 0, 1, 1 }, .events = &.{ 500, n * p1 }, .trials = &.{ n, n }, .weight = &.{ 1, 1 }, .p = 2 };
    const f = try probit.fitModel(a, q);
    try expectEqual(@as(usize, 2), f.theta.len);
    try approx(@as(f64, 0), f.theta[0], 1e-8);
    try approx(@as(f64, 1), f.theta[1], 1e-8);
    try approx(n * @log(0.5) + n * (p1 * @log(p1) + (1 - p1) * @log(1 - p1)), f.loglik, 1e-8);
    // Var(b0) = p(1-p) / (n * pdf(0)^2) = 0.25 / (1000 / (2*pi)) = pi / 2000.
    try approx(std.math.pi / 2000.0, f.cov[0], 1e-9);
    // WEIGHT multiplies each likelihood contribution (p.8120): doubling every
    // weight keeps the estimates and halves the covariance.
    var doubled = q;
    doubled.weight = &.{ 2, 2 };
    const g = try probit.fitModel(a, doubled);
    try approx(f.theta[1], g.theta[1], 1e-8);
    try approx(2 * f.loglik, g.loglik, 1e-7);
    try approx(f.cov[0] / 2, g.cov[0], 1e-10);
    // One design point cannot identify two coefficients.
    try std.testing.expectError(error.Singular, probit.fitModel(a, .{ .x = &.{ 1, 2, 1, 2 }, .events = &.{ 3, 4 }, .trials = &.{ 10, 10 }, .weight = &.{ 1, 1 }, .p = 2 }));
}

fn runStudy(a: A, lib: *Library, d: *diag.Diagnostics, output: *std.ArrayList(u8), source: []const u8) !void {
    return probit.run(.{ .arena = a, .lib = lib, .diags = d }, output, try lex.tokenize(a, source, d));
}

fn study(a: A, lib: *Library, groups: usize) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "study");
    for ([_][]const u8{ "Dose", "Respond", "Number", "grp" }) |n| _ = try ds.addColumn(n, .num);
    for (0..groups) |g| {
        try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 3 }, .{ .num = 15 }, .{ .num = @floatFromInt(g + 1) } });
        for (doses, responders) |dose, r| try ds.appendRow(&.{ .{ .num = dose }, .{ .num = r }, .{ .num = 15 }, .{ .num = @floatFromInt(g + 1) } });
    }
    try lib.put("study", ds);
}

test "STAT-PROBIT-001 LOG10 OPTC step prints the reference listing rows, per BY group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try study(a, &lib, 2);
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var output: std.ArrayList(u8) = .empty;
    try runStudy(a, &lib, &d, &output, "proc probit data=study log10 optc; by grp; model respond/number=dose; run;");
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    // Rows copied from the SAS reference listing of this model (p.8099).
    for ([_][]const u8{
        "The Probit Procedure",
        "Data Set                               WORK.STUDY",
        "Events Variable                           Respond",
        "Trials Variable                            Number",
        "Number of Observations                         12",
        "Number of Events                               81",
        "Number of Trials                              180",
        "Number of Events In Control Group               3",
        "Number of Trials In Control Group              15",
        "Name of Distribution                       Normal",
        "Log Likelihood                       -104.3945783",
        "Number of Observations Read          12",
        "Number of Observations Used          11",
        "Number of Events                     78",
        "Number of Trials                    165",
        "Algorithm converged.",
        "Log10(Dose)         1       10.7588        0.0010",
        "Parameter   DF Estimate    Error       Limits       Square Pr > ChiSq",
        "Intercept    1  -4.1438   1.3415  -6.7731  -1.5146    9.54     0.0020",
        "Log10(Dose)  1   6.2308   1.8996   2.5076   9.9539   10.76     0.0010",
        "_C_          1   0.2409   0.0523   0.1385   0.3433",
        "0.66506312    0.16049411",
        "MU             0.001158         -0.000493          0.000954",
        "SIGMA         -0.000493          0.002394         -0.000999",
        "_C_            0.000954         -0.000999          0.002731",
    }) |row| {
        // Identical inputs in both BY groups: every row appears exactly twice.
        expectEqual(@as(usize, 2), std.mem.count(u8, output.items, row)) catch |err| {
            std.debug.print("row not printed twice: {s}\n{s}\n", .{ row, output.items });
            return err;
        };
    }
    try expect(std.mem.indexOf(u8, output.items, "grp=1") != null and std.mem.indexOf(u8, output.items, "grp=2") != null);
}

test "STAT-PROBIT-001 user errors are rc 1 and unimplemented documented features are loud rc 2 gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try fixture(a, &lib, "sample", &sample);
    try study(a, &lib, 1);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        // User errors: malformed or contradicting the cited pages.
        .{ .source = "proc probit data=nosuch; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample; run;", .rc = 1 }, // MODEL required
        .{ .source = "proc probit data=sample c=1.5; model r/n = dose; run;", .rc = 1 }, // rate between 0 and 1
        .{ .source = "proc probit data=sample c=1; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample hprob=0; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample hprob=x; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample namelen=19; model r/n = dose; run;", .rc = 1 }, // 20..200
        .{ .source = "proc probit data=sample namelen=201; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample order=random; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample bogus; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample optc=1; model r/n = dose; run;", .rc = 1 },
        .{ .source = "proc probit data=sample; model r/n = nosuch; run;", .rc = 1 },
        .{ .source = "proc probit data=sample; model r/c = dose; run;", .rc = 1 }, // character trials
        .{ .source = "proc probit data=sample; model c/n = dose; run;", .rc = 1 }, // character events
        .{ .source = "proc probit data=sample; model r/n = c; run;", .rc = 1 }, // character effect outside CLASS
        .{ .source = "proc probit data=sample; model r/n = dose; class c; run;", .rc = 1 }, // CLASS must precede MODEL
        .{ .source = "proc probit data=sample; model r/n = dose; weight c; run;", .rc = 1 }, // character WEIGHT
        .{ .source = "proc probit data=sample; model r/n = dose; weight w g; run;", .rc = 1 },
        .{ .source = "proc probit data=sample; model r/n = dose; by nosuch; run;", .rc = 1 },
        .{ .source = "proc probit data=sample; by descending g; model r/n = dose; run;", .rc = 1 }, // not sorted descending
        .{ .source = "proc probit data=sample; model r/n = dose; frobnicate dose; run;", .rc = 1 },
        // Documented but not implemented, or not stated by the chapter: gaps.
        .{ .source = "proc probit data=study log10 optc plots=(predpplot ippplot); model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose; output out=new p=p_hat; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc inversecl; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc lackfit; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc outest=est covout; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc noprint; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose / d=logistic; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose grp; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose; weight grp; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; class grp; model respond/number=dose grp; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; class grp(ref='1'); model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10; model respond/number=dose; run;", .rc = 2 }, // no OPTC
        .{ .source = "proc probit data=study optc; model respond/number=dose; run;", .rc = 2 }, // no LOG10
        .{ .source = "proc probit data=study ln optc; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study c=0.2; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond=dose; run;", .rc = 2 }, // single response
        .{ .source = "proc probit data=study log10 optc; model respond(event='1')=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose*dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log log10 optc; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study optc optc log10; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose; weight grp; weight grp; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose; test dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model respond/number=dose; predpplot; run;", .rc = 2 },
        // Missing values / no control group / invalid counts in the fitted listing.
        .{ .source = "proc probit data=sample log10 optc; model r/n = dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; where dose > 0; model respond/number=dose; run;", .rc = 2 },
        .{ .source = "proc probit data=study log10 optc; model number/respond=dose; run;", .rc = 2 }, // events > trials
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = runStudy(a, &lib, &d, &output, case.source);
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expect(d.hasErrors());
        try expectEqual(@as(usize, 0), output.items.len); // never a partial or fake table
    }
}
