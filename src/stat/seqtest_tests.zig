//! STAT-SEQTEST-001 permanent tests: PROC SEQTEST statement options, the
//! BOUNDARY= / PARMS= / DATA= input roles, the current-stage information level
//! and standardized statistic, and the loud execution boundary. The boundary
//! rows are the 4-stage two-sided O'Brien-Fleming design printed by SAS 9.4 in
//! the "Boundary Information" table of the chapter's reference case; the
//! estimate data are invented (D-011). Expected values come from that SAS
//! listing or from hand mathematics, never from opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const seqtest = @import("seqtest.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        diag.resetGap();
        try self.boundary("bnd", "TwoSided", "Reject", true);
        try self.parms("est", "Trt", "MLE", -7, 4.5, 1);
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    /// Boundary Information of the reference design (Standardized Z scale).
    fn boundary(self: *Env, name: []const u8, alt: []const u8, stop: []const u8, with_info: bool) !void {
        const a = self.arena.allocator();
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, name);
        for ([_][]const u8{ "_Scale_", "_Stop_", "_ALT_" }) |n| _ = try ds.addColumn(n, .char);
        for ([_][]const u8{ "_Stage_", "_InfoProp_", "_Info_", "N", "AltRef_L", "AltRef_U", "Bound_LA", "Bound_UA" }) |n| _ = try ds.addColumn(n, .num);
        const prop = [_]f64{ 0.25, 0.5, 0.75, 1 };
        const info = [_]f64{ 0.026851, 0.053701, 0.080552, 0.107403 };
        const n_ = [_]f64{ 42.96116, 85.92233, 128.8835, 171.8447 };
        const ref = [_]f64{ 1.63862, 2.31736, 2.83817, 3.27724 };
        const ub = [_]f64{ 4.04859, 2.86278, 2.33745, 2.02429 };
        for (0..4) |k| try ds.appendRow(&.{ .{ .str = "StdZ" }, .{ .str = stop }, .{ .str = alt }, .{ .num = @floatFromInt(k + 1) }, .{ .num = prop[k] }, .{ .num = if (with_info) info[k] else nan }, .{ .num = n_[k] }, .{ .num = -ref[k] }, .{ .num = ref[k] }, .{ .num = -ub[k] }, .{ .num = ub[k] } });
        try self.lib.put(name, ds);
    }
    fn parms(self: *Env, name: []const u8, variable: []const u8, scale: []const u8, est: f64, se: f64, stage: f64) !void {
        const a = self.arena.allocator();
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, name);
        _ = try ds.addColumn("Variable", .char);
        _ = try ds.addColumn("_Scale_", .char);
        for ([_][]const u8{ "_Stage_", "Estimate", "StdErr" }) |n| _ = try ds.addColumn(n, .num);
        try ds.appendRow(&.{ .{ .str = "Intercept" }, .{ .str = scale }, .{ .num = stage }, .{ .num = 3 }, .{ .num = 1 } });
        try ds.appendRow(&.{ .{ .str = variable }, .{ .str = scale }, .{ .num = stage }, .{ .num = est }, .{ .num = se } });
        try self.lib.put(name, ds);
    }
    fn toks(self: *Env, source: []const u8) ![]lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !seqtest.Spec {
        return seqtest.parse(self.cx(), try self.toks(source));
    }
    /// Run a step; returns the D-009 class (0 ok, 1 user error, 2 gap).
    fn rc(self: *Env, source: []const u8) !u8 {
        diag.resetGap();
        var out: std.ArrayList(u8) = .empty;
        seqtest.run(self.cx(), &out, try self.toks(source)) catch |e| {
            if (e != error.ParseError) return e;
            try expectEqual(@as(usize, 0), out.items.len); // nothing printed on failure
            return if (diag.gapHit()) 2 else 1;
        };
        return 0;
    }
};

fn env() Env {
    return .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
}

test "STAT-SEQTEST-001 PROC statement defaults and explicit options" {
    var e = env();
    defer e.arena.deinit();
    try e.init();
    // Documented defaults (pp.9156-9165).
    const d = try e.parse("proc seqtest boundary=bnd; run;");
    try expect(std.ascii.eqlIgnoreCase("bnd", d.boundary.?));
    try expect(d.data == null and d.parms == null and d.testvar == null and d.infovar == null);
    try expect(d.betaboundary_binding and d.betaoverlap_adjust and d.infoadj_prop);
    try expectEqual(seqtest.Key.alpha, d.boundarykey);
    try expectEqual(seqtest.Scale.stdz, d.bscale);
    try approx(@as(f64, 0.05), d.cialpha, 0);
    try expect(d.citype == null and d.nstages == null and d.adjust.len == 0 and d.errspendmin.len == 0);
    try expectEqual(seqtest.Order.stagewise, d.order);
    try expect(!d.condpower and !d.errspend and !d.predpower and !d.pss and !d.rci and !d.stopprob and !d.plots);
    // Explicit settings and the documented aliases.
    const x = try e.parse("proc seqtest boundary=work.bnd parms(testvar=Trt)=est betaboundary=nonbinding overlap=noadjust boundarykey=both bscale=mle " ++
        "cialpha=0.1(lower=0.02) citype=twosided errspendadj(upperalpha)=errfuncgamma(gamma=-4) boundaryadj(beta)=errfuncpow errspendmin(alpha)=0.001 0.002 " ++
        "infoadj=none nstages=3 maxinfo=0.2 order=lr condpower(cref=0 1 type=finalstage) errspend predpower pss(cref=0.5) rci stopprob; run;");
    try expect(std.ascii.eqlIgnoreCase("work.bnd", x.boundary.?));
    try expect(std.ascii.eqlIgnoreCase("est", x.parms.?) and std.ascii.eqlIgnoreCase("Trt", x.testvar.?));
    try expect(!x.betaboundary_binding and !x.betaoverlap_adjust and !x.infoadj_prop);
    try expectEqual(seqtest.Key.both, x.boundarykey);
    try expectEqual(seqtest.Scale.mle, x.bscale);
    try approx(@as(f64, 0.1), x.cialpha, 0);
    try approx(@as(f64, 0.02), x.cialpha_lower.?, 0);
    try expectEqual(seqtest.CiType.twosided, x.citype.?);
    try expectEqual(@as(usize, 2), x.adjust.len);
    try expectEqual(seqtest.Which.upper_alpha, x.adjust[0].which);
    try expectEqual(seqtest.AdjMethod.errfuncgamma, x.adjust[0].method);
    try approx(@as(f64, -4), x.adjust[0].param.?, 0);
    try expectEqual(seqtest.Which.beta, x.adjust[1].which);
    try approx(@as(f64, 2), x.adjust[1].param.?, 0); // RHO= default 2
    try expectEqual(@as(usize, 2), x.errspendmin[0].values.len);
    try expectEqual(@as(usize, 3), x.nstages.?);
    try approx(@as(f64, 0.2), x.maxinfo.?, 0);
    try expectEqual(seqtest.Order.lr, x.order);
    try expect(x.condpower and x.errspend and x.predpower and x.pss and x.rci and x.stopprob);
    const g = try e.parse("proc seqtest boundary=bnd data(infovar=nobs)=est errspendadj=errfuncgamma plots=(test errspend); run;");
    try expectEqual(seqtest.InfoVar.nobs, g.infovar.?);
    try approx(@as(f64, -2), g.adjust[0].param.?, 0); // GAMMA= default -2
    try expectEqual(seqtest.Which.all, g.adjust[0].which);
    try expect(g.plots);
}

test "STAT-SEQTEST-001 invalid declarations: user errors and unverified repeats" {
    var e = env();
    defer e.arena.deinit();
    try e.init();
    // User errors (rc 1): required BOUNDARY=, documented value sets and ranges, other statements.
    for ([_][]const u8{
        "proc seqtest; run;",
        "proc seqtest parms(testvar=Trt)=est; run;",
        "proc seqtest boundary=bnd boundarykey=gamma; run;",
        "proc seqtest boundary=bnd bscale=log; run;",
        "proc seqtest boundary=bnd cialpha=1.5; run;",
        "proc seqtest boundary=bnd cialpha=0.05(lower=0.6); run;",
        "proc seqtest boundary=bnd infoadj=all; run;",
        "proc seqtest boundary=bnd nstages=0; run;",
        "proc seqtest boundary=bnd order=rank; run;",
        "proc seqtest boundary=bnd errspendadj=errfuncxyz; run;",
        "proc seqtest boundary=bnd errspendadj(middle)=errline; run;",
        "proc seqtest boundary=bnd errspendadj=errline(rho=2); run;",
        "proc seqtest boundary=bnd pss(cref=-1); run;",
        "proc seqtest boundary=bnd parms(infovar=_info_)=est; run;",
        "proc seqtest boundary=bnd data(infovar=stderr)=est; run;",
        "proc seqtest boundary=bnd unknownopt; run;",
        "proc seqtest boundary=bnd; by g; run;",
        "proc seqtest boundary=nosuch; run;",
    }) |src| try expectEqual(@as(u8, 1), try e.rc(src));
    // A repeated option or alias has no documented rule: gap (rc 2), not a guess.
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd bscale=mle boundaryscale=stdz; run;"));
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd errspendadj=errline boundaryadj=none; run;"));
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd(where=(_Stage_>1)); run;"));
}

test "STAT-SEQTEST-001 BOUNDARY= data set roles and Table 111.2 variables" {
    var e = env();
    defer e.arena.deinit();
    try e.init();
    const b = try seqtest.loadBoundary(e.cx(), 1, "bnd");
    try expectEqual(seqtest.Alt.twosided, b.alt);
    try expectEqual(seqtest.Stop.reject, b.stop);
    try expectEqual(seqtest.Scale.stdz, b.scale);
    try expectEqual(@as(usize, 4), b.stages);
    try approx(@as(f64, 0.75), b.info_prop[2], 0);
    try approx(@as(f64, 0.107403), b.info.?[3], 0);
    try approx(@as(f64, -1.63862), b.altref_l.?, 0);
    try approx(@as(f64, 1.63862), b.altref_u.?, 0);
    // Two-sided accept/reject needs Bound_LB and Bound_UB too: missing → rc 1.
    try e.boundary("both", "TwoSided", "Both", true);
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=both; run;"));
    // Undocumented code values are user errors.
    try e.boundary("badalt", "Sideways", "Reject", true);
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=badalt; run;"));
    // An upper one-sided reject design needs only Bound_UA and AltRef_U.
    try e.boundary("up", "Upper", "Reject", true);
    const u = try seqtest.loadBoundary(e.cx(), 1, "up");
    try expect(u.altref_l == null and u.altref_u != null);
    // A missing boundary value is unverified SAS behavior: gap.
    const ds = e.lib.find("up").?;
    var row = try e.arena.allocator().dupe(Value, ds.rows.items[1]);
    row[10] = Value.missing;
    ds.rows.items[1] = row;
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=up; run;"));
    // Stages out of order: gap.
    try e.boundary("ord", "TwoSided", "Reject", true);
    const o = e.lib.find("ord").?;
    std.mem.swap([]const Value, &o.rows.items[0], &o.rows.items[1]);
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=ord; run;"));
    // Empty BOUNDARY= data set: user error.
    const a = e.arena.allocator();
    const empty = try a.create(Dataset);
    empty.* = Dataset.init(a, "empty");
    for ([_][]const u8{ "_Scale_", "_Stop_", "_ALT_" }) |n| _ = try empty.addColumn(n, .char);
    for ([_][]const u8{ "_Stage_", "_InfoProp_" }) |n| _ = try empty.addColumn(n, .num);
    try e.lib.put("empty", empty);
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=empty; run;"));
}

test "STAT-SEQTEST-001 PARMS= current stage, information level and standardized Z" {
    var e = env();
    defer e.arena.deinit();
    try e.init();
    const s = try e.parse("proc seqtest boundary=bnd parms(testvar=Trt)=est infoadj=prop; run;");
    const b = try seqtest.loadBoundary(e.cx(), 1, "bnd");
    const c = (try seqtest.loadCurrent(e.cx(), 1, s, b)).?;
    // Only the Trt row is selected; I = 1/StdErr^2 = 1/20.25 (SAS: Actual 0.049383),
    // Z = -7 * sqrt(I) = -7/4.5 (SAS: Estimate -1.55556).
    try expectEqual(@as(usize, 1), c.stage);
    try approx(@as(f64, 0.049383), c.info.?, 5e-7);
    try approx(@as(f64, -1.55556), c.z.?, 5e-6);
    try expectEqual(seqtest.Scale.mle, c.scale.?);
    // Score scale: I = StdErr^2, Z = est / sqrt(I) (p.9169).
    try e.parms("sc", "Trt", "Score", 6, 2, 2);
    const sc = (try seqtest.loadCurrent(e.cx(), 1, try e.parse("proc seqtest boundary=bnd parms(testvar=trt)=sc; run;"), b)).?;
    try approx(@as(f64, 4), sc.info.?, 1e-12);
    try approx(@as(f64, 3), sc.z.?, 1e-12);
    try expectEqual(@as(usize, 2), sc.stage);
    // INFOVAR=NONE keeps the BOUNDARY= information (stage 1: 0.026851): Z = -7*sqrt(0.026851).
    const nv = (try seqtest.loadCurrent(e.cx(), 1, try e.parse("proc seqtest boundary=bnd parms(testvar=Trt infovar=none)=est; run;"), b)).?;
    try expect(nv.info == null);
    try approx(-7 * @sqrt(0.026851), nv.z.?, 1e-12);
    // No DATA=/PARMS=: statistics come from BOUNDARY= alone.
    try expect((try seqtest.loadCurrent(e.cx(), 1, try e.parse("proc seqtest boundary=bnd; run;"), b)) == null);
    // Negative cases.
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=bnd parms(testvar=Dose)=est; run;")); // test variable absent
    try e.parms("bscale", "Trt", "Log", -7, 4.5, 1);
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=bnd parms(testvar=Trt)=bscale; run;")); // bad _Scale_
    try e.parms("st9", "Trt", "MLE", -7, 4.5, 9);
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd parms(testvar=Trt)=st9; run;")); // stage beyond design
    try e.parms("miss", "Trt", "MLE", nan, 4.5, 1);
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd parms(testvar=Trt)=miss; run;")); // missing estimate
    try e.parms("pv", "Trt", "PValue", 0.2, 4.5, 1);
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd parms(testvar=Trt)=pv; run;")); // PVALUE scale gap
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd data=est parms=est; run;"));
    // A fully valid step still stops loudly: the computation is not implemented.
    try expectEqual(@as(u8, 2), try e.rc("proc seqtest boundary=bnd parms(testvar=Trt)=est infoadj=prop; run;"));
}

test "STAT-SEQTEST-001 DATA= data set: test variable and NObs-derived information" {
    var e = env();
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    // A boundary with NObs (p.9168: I_k = I*_k * n_k / n*_k).
    const bd = e.lib.find("bnd").?;
    bd.columns.items[6].name = "NObs";
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cur");
    _ = try ds.addColumn("_Scale_", .char);
    for ([_][]const u8{ "_Stage_", "NObs", "Z" }) |n| _ = try ds.addColumn(n, .num);
    try ds.appendRow(&.{ .{ .str = "StdZ" }, .{ .num = 1 }, .{ .num = 50 }, .{ .num = 1.2 } });
    try e.lib.put("cur", ds);
    const b = try seqtest.loadBoundary(e.cx(), 1, "bnd");
    const c = (try seqtest.loadCurrent(e.cx(), 1, try e.parse("proc seqtest boundary=bnd data(testvar=z)=cur; run;"), b)).?;
    try approx(0.026851 * 50.0 / 42.96116, c.info.?, 1e-12);
    try approx(@as(f64, 1.2), c.z.?, 0);
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=bnd data(testvar=w)=cur; run;")); // missing test variable
    try expectEqual(@as(u8, 1), try e.rc("proc seqtest boundary=bnd data(infovar=events)=cur; run;")); // Events absent
}
