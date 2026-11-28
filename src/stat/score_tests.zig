//! STAT-SCORE-001 permanent tests: PROC SCORE statement options, VAR / BY /
//! ID roles, the missing-value rules (p.8911), BY matching (pp.8909-8910)
//! and loud execution boundaries. All data are invented (D-011). Expected
//! values are hand mathematics stated next to each check, never opensas
//! output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const score = @import("score.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

fn num(v: f64) Value {
    return .{ .num = v };
}
fn str(v: []const u8) Value {
    return .{ .str = v };
}

// raw: g id x y (g = BY group 1/2); coef: _TYPE_ _NAME_ x y.
fn build(a: A, lib: *Library) !void {
    const raw = try a.create(Dataset);
    raw.* = Dataset.init(a, "raw");
    _ = try raw.addColumn("g", .num);
    _ = try raw.addColumn("id", .char);
    _ = try raw.addColumn("x", .num);
    _ = try raw.addColumn("y", .num);
    const rows = [_][4]Value{
        .{ num(1), str("a"), num(1), num(2) },
        .{ num(1), str("b"), num(3), num(nan) }, // missing y
        .{ num(2), str("c"), num(5), num(4) },
    };
    for (rows) |r| try raw.appendRow(&r);
    try lib.put("raw", raw);

    const coef = try a.create(Dataset);
    coef.* = Dataset.init(a, "coef");
    _ = try coef.addColumn("_TYPE_", .char);
    _ = try coef.addColumn("_NAME_", .char);
    _ = try coef.addColumn("x", .num);
    _ = try coef.addColumn("y", .num);
    const crow = [_][4]Value{
        .{ str("SCORE"), str("S1"), num(2), num(-1) },
        .{ str("score"), str("S2"), num(1), num(0) }, // y coefficient 0
        .{ str("PARMS"), str("P1"), num(10), num(nan) }, // missing coefficient
        .{ str("OTHER"), str("O1"), num(1), num(1) },
    };
    for (crow) |r| try coef.appendRow(&r);
    try lib.put("coef", coef);

    // BY-grouped coefficients: g=1 -> 1*x, g=2 -> 2*x (g=3 unused).
    const bcoef = try a.create(Dataset);
    bcoef.* = Dataset.init(a, "bcoef");
    _ = try bcoef.addColumn("g", .num);
    _ = try bcoef.addColumn("_TYPE_", .char);
    _ = try bcoef.addColumn("_NAME_", .char);
    _ = try bcoef.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3 }) |g| try bcoef.appendRow(&.{ num(g), str("SCORE"), str("T"), num(g) });
    try lib.put("bcoef", bcoef);

    // Standardization rows: MEAN x=1 y=2, STD x=2 y=4; score = z_x + z_y.
    const stdc = try a.create(Dataset);
    stdc.* = Dataset.init(a, "stdc");
    _ = try stdc.addColumn("_TYPE_", .char);
    _ = try stdc.addColumn("_NAME_", .char);
    _ = try stdc.addColumn("x", .num);
    _ = try stdc.addColumn("y", .num);
    try stdc.appendRow(&.{ str("MEAN"), str(""), num(1), num(2) });
    try stdc.appendRow(&.{ str("STD"), str(""), num(2), num(4) });
    try stdc.appendRow(&.{ str("SCORE"), str("Z"), num(1), num(1) });
    try lib.put("stdc", stdc);
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
    fn parse(self: *Env, source: []const u8) !score.Spec {
        return score.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
    fn run(self: *Env, source: []const u8) !*Dataset {
        var out: std.ArrayList(u8) = .empty;
        try score.run(self.cx(), &out, try lex.tokenize(self.arena.allocator(), source, &self.diags));
        try expectEqual(@as(usize, 0), out.items.len); // p.8911: displays no output
        return self.lib.find("o").?;
    }
};

fn cell(o: *Dataset, r: usize, name: []const u8) f64 {
    return o.rows.items[r][o.indexOf(name).?].num;
}

test "STAT-SCORE-001 PROC statement defaults and explicit options" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // p.8909: SCORE= defaults to the most recent data set (STDC); TYPE= unset.
    const d = try e.parse("proc score data=raw out=o; run;");
    try expect(!d.predict and !d.residual and !d.nostd and d.type == null and !d.var_given);
    try std.testing.expectEqualStrings("stdc", d.score_name);
    const s = try e.parse("proc score data=work.raw score=bcoef out=work.o type='parms' predict nostd; var x; id id; by g; run;");
    try expect(s.predict and !s.residual and s.nostd and s.var_given);
    try std.testing.expectEqualStrings("parms", s.type.?);
    try std.testing.expectEqualStrings("bcoef", s.score_name);
    try std.testing.expectEqualStrings("work.o", s.out.?);
    try expectEqual(@as(usize, 1), s.vars.len);
    try std.testing.expectEqualSlices(usize, &.{1}, s.ids);
    try std.testing.expectEqualStrings("g", s.by_names[0]);
    try std.testing.expectEqualStrings("PARMS", (try e.parse("proc score data=raw score=coef out=o type=PARMS; run;")).type.?);
    // p.8909: only the last BY statement is used.
    const last = try e.parse("proc score data=raw score=bcoef out=o; by x; by g; run;");
    try expectEqual(@as(usize, 1), last.by_names.len);
    try std.testing.expectEqualStrings("g", last.by_names[0]);
}

test "STAT-SCORE-001 default scoring, missing values, TYPE=, PREDICT and RESIDUAL" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // Default TYPE: rows with _TYPE_ SCORE (case-insensitive) -> S1, S2.
    // S1 = 2x - y: 2*1-2 = 0; row 2 has y missing with coefficient -1 ->
    // missing; 2*5-4 = 6. S2 = x (y coefficient 0 tolerates missing): 1, 3, 5.
    var o = try e.run("proc score data=raw score=coef out=o; var x y; run;");
    try expectEqual(@as(usize, 3), o.rows.items.len);
    try expectEqual(@as(usize, 6), o.columns.items.len); // g id x y S1 S2
    try std.testing.expectEqualStrings("S1", o.columns.items[4].name);
    try approx(@as(f64, 0), cell(o, 0, "S1"), 1e-12);
    try expect(std.math.isNan(cell(o, 1, "S1")));
    try approx(@as(f64, 6), cell(o, 2, "S1"), 1e-12);
    try approx(@as(f64, 3), cell(o, 1, "S2"), 1e-12);
    // PREDICT: the -1 coefficient becomes 0, so S1 = 2x and tolerates y missing.
    o = try e.run("proc score data=raw score=coef out=o predict; var x y; run;");
    try approx(@as(f64, 6), cell(o, 1, "S1"), 1e-12);
    // RESIDUAL reverses the sign: -(2*5-4) = -6.
    o = try e.run("proc score data=raw score=coef out=o residual; var x y; run;");
    try approx(@as(f64, -6), cell(o, 2, "S1"), 1e-12);
    // TYPE=parms (not case sensitive): a missing coefficient counts as 0, so
    // P1 = 10x, defined even where y is missing: 10, 30, 50.
    o = try e.run("proc score data=raw score=coef out=o type=parms; var x y; run;");
    try expectEqual(@as(usize, 5), o.columns.items.len);
    try approx(@as(f64, 30), cell(o, 1, "P1"), 1e-12);
    // ID: only the ID variables (then scores) are kept.
    o = try e.run("proc score data=raw score=coef out=o type='OTHER'; var x y; id id; run;");
    try expectEqual(@as(usize, 2), o.columns.items.len);
    try std.testing.expectEqualStrings("id", o.columns.items[0].name);
    try approx(@as(f64, 9), cell(o, 2, "O1"), 1e-12);
    // No VAR statement: all numeric SCORE= variables (x y).
    o = try e.run("proc score data=raw score=coef out=o; run;");
    try approx(@as(f64, 6), cell(o, 2, "S1"), 1e-12);
    // MEAN/STD standardization: z_x + z_y = (5-1)/2 + (4-2)/4 = 2.5;
    // NOSTD uses the raw values: 5 + 4 = 9.
    o = try e.run("proc score data=raw score=stdc out=o; var x y; run;");
    try approx(@as(f64, 2.5), cell(o, 2, "Z"), 1e-12);
    o = try e.run("proc score data=raw score=stdc out=o nostd; var x y; run;");
    try approx(@as(f64, 9), cell(o, 2, "Z"), 1e-12);
}

test "STAT-SCORE-001 BY groups: matched groups and coefficient groups over all data" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // g on both: g=1 rows scored with T=x (1, 3), g=2 with T=2x (10); the
    // unused SCORE= group g=3 is allowed without NOTSORTED.
    var o = try e.run("proc score data=raw score=bcoef out=o; by g; var x; run;");
    try expectEqual(@as(usize, 3), o.rows.items.len);
    try approx(@as(f64, 1), cell(o, 0, "T"), 1e-12);
    try approx(@as(f64, 3), cell(o, 1, "T"), 1e-12);
    try approx(@as(f64, 10), cell(o, 2, "T"), 1e-12);
    // DATA= without the BY variable: each of the 3 coefficient groups scores
    // all 3 observations (9 rows); with ID, the BY variable follows the IDs.
    o = try e.run("proc score data=raw score=bcoef out=o; by g; var x; id id x; run;");
    try expectEqual(@as(usize, 3), o.rows.items.len); // raw carries g: matched
    const nog = try e.arena.allocator().create(Dataset);
    nog.* = Dataset.init(e.arena.allocator(), "nog");
    _ = try nog.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3 }) |x| try nog.appendRow(&.{num(x)});
    try e.lib.put("nog", nog);
    o = try e.run("proc score data=nog score=bcoef out=o; by g; var x; run;");
    try expectEqual(@as(usize, 9), o.rows.items.len);
    try std.testing.expectEqualStrings("g", o.columns.items[1].name);
    try approx(@as(f64, 3), cell(o, 8, "g"), 1e-12);
    try approx(@as(f64, 9), cell(o, 8, "T"), 1e-12); // 3 * 3
    // Empty DATA= -> empty output with the score variable.
    const empty = try e.arena.allocator().create(Dataset);
    empty.* = Dataset.init(e.arena.allocator(), "empty");
    _ = try empty.addColumn("x", .num);
    try e.lib.put("empty", empty);
    o = try e.run("proc score data=empty score=coef out=o; var x; run;");
    try expectEqual(@as(usize, 0), o.rows.items.len);
    try expectEqual(@as(usize, 3), o.columns.items.len); // x S1 S2
}

test "STAT-SCORE-001 invalid input is a user error and unimplemented valid syntax is a loud gap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    try build(a, &lib);
    // DATA= has g but the matching SCORE= data set lacks group 2.
    const part = try a.create(Dataset);
    part.* = Dataset.init(a, "part");
    _ = try part.addColumn("g", .num);
    _ = try part.addColumn("_TYPE_", .char);
    _ = try part.addColumn("_NAME_", .char);
    _ = try part.addColumn("x", .num);
    try part.appendRow(&.{ num(1), str("SCORE"), str("T"), num(1) });
    try lib.put("part", part);
    const extra = [_]struct { name: []const u8, rows: []const [4]Value }{
        .{ .name = "dup", .rows = &.{ .{ str("SCORE"), str("S"), num(1), num(1) }, .{ str("SCORE"), str("s"), num(2), num(1) } } },
        .{ .name = "unoustd", .rows = &.{.{ str("USCORE"), str("U"), num(1), num(1) }} },
        .{ .name = "nomean", .rows = &.{ .{ str("MEAN"), str(""), num(nan), num(1) }, .{ str("SCORE"), str("S"), num(1), num(1) } } },
        .{ .name = "emptyc", .rows = &.{} },
        .{ .name = "mixed", .rows = &.{ .{ str("SCORE"), str("S"), num(1), num(1) }, .{ str("USCORE"), str("U"), num(2), num(1) } } },
    };
    for (extra) |x| {
        const c = try a.create(Dataset);
        c.* = Dataset.init(a, x.name);
        _ = try c.addColumn("_TYPE_", .char);
        _ = try c.addColumn("_NAME_", .char);
        _ = try c.addColumn("x", .num);
        _ = try c.addColumn("y", .num);
        for (x.rows) |r| try c.appendRow(&r);
        try lib.put(x.name, c);
    }
    const bnone = try a.create(Dataset);
    bnone.* = Dataset.init(a, "bnone");
    _ = try bnone.addColumn("g", .num);
    _ = try bnone.addColumn("_TYPE_", .char);
    _ = try bnone.addColumn("_NAME_", .char);
    _ = try bnone.addColumn("x", .num);
    try bnone.appendRow(&.{ num(1), str("SCORE"), str("T"), num(1) });
    try bnone.appendRow(&.{ num(2), str("MEAN"), str(""), num(1) });
    try lib.put("bnone", bnone);
    const emptyb = try a.create(Dataset);
    emptyb.* = Dataset.init(a, "emptyb");
    _ = try emptyb.addColumn("g", .num);
    _ = try emptyb.addColumn("_TYPE_", .char);
    _ = try emptyb.addColumn("_NAME_", .char);
    _ = try emptyb.addColumn("x", .num);
    try lib.put("emptyb", emptyb);
    const skip = try a.create(Dataset);
    skip.* = Dataset.init(a, "skip");
    _ = try skip.addColumn("g", .num);
    _ = try skip.addColumn("x", .num);
    try skip.appendRow(&.{ num(1), num(1) });
    try skip.appendRow(&.{ num(3), num(1) });
    try lib.put("skip", skip);
    const nox = try a.create(Dataset);
    nox.* = Dataset.init(a, "nox");
    _ = try nox.addColumn("y", .num);
    try nox.appendRow(&.{num(1)});
    try lib.put("nox", nox);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        .{ .source = "proc score score=coef out=o; run;", .rc = 1 }, // DATA= required
        .{ .source = "proc score data=nosuch score=coef out=o; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=nosuch out=o; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=coef out=o replace; run;", .rc = 1 }, // not a SCORE option
        .{ .source = "proc score data=raw score=coef out=o type=3; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=coef out=o; var nosuch; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=coef out=o; var _name_; run;", .rc = 1 }, // character
        .{ .source = "proc score data=raw score=coef out=o; var; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=coef out=o; id nosuch; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=coef out=o; model x = y; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=raw out=o; var x; run;", .rc = 1 }, // no _TYPE_
        .{ .source = "proc score data=raw score=part out=o; by g; var x; run;", .rc = 1 }, // DATA= group 2 absent
        .{ .source = "proc score data=raw score=bcoef out=o; by descending g; var x; run;", .rc = 1 }, // not sorted
        // Verified SAS 9.4 user errors.
        .{ .source = "proc score data=raw score=coef out=o predict residual; var x y; run;", .rc = 1 },
        .{ .source = "proc score data=raw score=coef out=o type=nosuchtype; var x y; run;", .rc = 1 }, // no coefficients
        .{ .source = "proc score data=raw score=dup out=o; var x y; run;", .rc = 1 }, // duplicate score name
        .{ .source = "proc score data=nox score=coef out=o; run;", .rc = 1 }, // default VAR x not on DATA=
        .{ .source = "proc score data=raw score=mixed out=o; var x y; run;", .rc = 1 }, // SCORE and USCORE rows
        .{ .source = "proc score data=raw score=bnone out=o; by g; var x; run;", .rc = 1 }, // group 2 has no SCORE row
        .{ .source = "proc score data=skip score=bcoef out=o; by g notsorted; var x; run;", .rc = 1 }, // NOTSORTED: group 2 skipped
        // Valid SAS owned by later tickets or not verified (D-009 gap, rc 2).
        .{ .source = "proc score data=raw score=coef out=o; var x y; format x 8.2; run;", .rc = 2 },
        .{ .source = "proc score data=raw score=coef out=o; var x y; label S1='a'; run;", .rc = 2 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = score.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
        std.testing.expectError(error.ParseError, result) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{case.source});
            return err;
        };
        expectEqual(case.rc, diag.exitCode(diag.gapHit(), d.hasErrors())) catch |err| {
            std.debug.print("unexpected exit class for: {s}\n", .{case.source});
            return err;
        };
        try expect(d.hasErrors());
        try expectEqual(@as(usize, 0), output.items.len);
        try expect(lib.find("o") == null); // never a partial data set
    }
    // Verified (SAS 9.4): an empty SCORE= data set with BY gives an output
    // with no observations (DATA= variables only).
    var d = diag.Diagnostics.init(a);
    var output: std.ArrayList(u8) = .empty;
    try score.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, "proc score data=raw score=emptyb out=o; by g; var x; run;", &d));
    try expectEqual(@as(usize, 0), lib.find("o").?.rows.items.len);
    try expectEqual(@as(usize, 4), lib.find("o").?.columns.items.len);
}

test "STAT-SCORE-001 SAS-verified rules: DATAn, repeats, standardization edges, names, BY union, data set options" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    var out: std.ArrayList(u8) = .empty;
    // Without OUT=: DATA1, then DATA2 (verified SAS 9.4 NOTEs).
    try score.run(e.cx(), &out, try lex.tokenize(a, "proc score data=raw score=coef; var x y; run;", &e.diags));
    try score.run(e.cx(), &out, try lex.tokenize(a, "proc score data=raw score=coef; var x y; run;", &e.diags));
    try expect(e.lib.find("DATA1") != null and e.lib.find("DATA2") != null);
    // Repeated flag, repeated TYPE= (last wins), two VAR statements accumulate:
    // S1 = 2x - y on row 3 = 6.
    var o = try e.run("proc score data=raw score=coef out=o predict predict type=other type=score; var x; var y; run;");
    try approx(@as(f64, 10), cell(o, 2, "S1"), 1e-12); // PREDICT: -1 -> 0, 2*5
    // Repeated OUT=: the first is kept with a warning.
    _ = try e.run("proc score data=raw score=coef out=o out=other; var x y; run;");
    try expect(e.lib.find("other") == null);
    // Data set options on SCORE= and OUT=.
    o = try e.run("proc score data=raw score=coef(where=(_name_='S2')) out=o(keep=x S2); var x y; run;");
    try expectEqual(@as(usize, 2), o.columns.items.len);
    try approx(@as(f64, 5), cell(o, 2, "S2"), 1e-12);
    // Score name already on the output (here y): renamed y2.
    const cy = try a.create(Dataset);
    cy.* = Dataset.init(a, "cy");
    _ = try cy.addColumn("_TYPE_", .char);
    _ = try cy.addColumn("_NAME_", .char);
    _ = try cy.addColumn("x", .num);
    _ = try cy.addColumn("y", .num);
    try cy.appendRow(&.{ str("SCORE"), str("y"), num(1), num(1) });
    try cy.appendRow(&.{ str("SCORE"), str(" "), num(1), num(0) }); // blank: skipped with a warning
    try cy.appendRow(&.{ str("MEAN"), str(""), num(1), num(2) }); // MEAN only: centering
    try cy.appendRow(&.{ str("STD"), str(""), num(nan), num(0) }); // missing STD x -> unscaled; zero STD y -> adds 0
    try e.lib.put("cy", cy);
    o = try e.run("proc score data=raw score=cy out=o; var x y; run;");
    try expectEqual(@as(usize, 5), o.columns.items.len); // g id x y y2
    // y2 = (x - 1) + 0 (zero STD): row 3 = 4; row 2 has y missing -> missing.
    try approx(@as(f64, 4), cell(o, 2, "y2"), 1e-12);
    try expect(std.math.isNan(cell(o, 1, "y2")));
    // USCORE with USTD: x/USTD without centering, MEAN ignored: 5/2 + 4/4 = 3.5.
    const cu = try a.create(Dataset);
    cu.* = Dataset.init(a, "cu");
    _ = try cu.addColumn("_TYPE_", .char);
    _ = try cu.addColumn("_NAME_", .char);
    _ = try cu.addColumn("x", .num);
    _ = try cu.addColumn("y", .num);
    try cu.appendRow(&.{ str("MEAN"), str(""), num(1), num(1) });
    try cu.appendRow(&.{ str("USTD"), str(""), num(2), num(4) });
    try cu.appendRow(&.{ str("USCORE"), str("U"), num(1), num(1) });
    try e.lib.put("cu", cu);
    o = try e.run("proc score data=raw score=cu out=o; var x y; run;");
    try approx(@as(f64, 3.5), cell(o, 2, "U"), 1e-12);
    // Zero USTD: warning, y adds nothing (row 3: 5/2 = 2.5); missing USTD: unscaled.
    const cz = try a.create(Dataset);
    cz.* = Dataset.init(a, "cz");
    _ = try cz.addColumn("_TYPE_", .char);
    _ = try cz.addColumn("_NAME_", .char);
    _ = try cz.addColumn("x", .num);
    _ = try cz.addColumn("y", .num);
    try cz.appendRow(&.{ str("USTD"), str(""), num(2), num(0) });
    try cz.appendRow(&.{ str("USCORE"), str("U"), num(1), num(1) });
    try e.lib.put("cz", cz);
    o = try e.run("proc score data=raw score=cz out=o; var x y; run;");
    try approx(@as(f64, 2.5), cell(o, 2, "U"), 1e-12);
    try expect(std.math.isNan(cell(o, 1, "U"))); // y missing, coefficient 1
    const cn = try a.create(Dataset);
    cn.* = Dataset.init(a, "cn");
    _ = try cn.addColumn("_TYPE_", .char);
    _ = try cn.addColumn("_NAME_", .char);
    _ = try cn.addColumn("x", .num);
    _ = try cn.addColumn("y", .num);
    try cn.appendRow(&.{ str("USTD"), str(""), num(nan), num(4) });
    try cn.appendRow(&.{ str("USCORE"), str("U"), num(1), num(1) });
    try e.lib.put("cn", cn);
    o = try e.run("proc score data=raw score=cn out=o; var x y; run;");
    try approx(@as(f64, 6), cell(o, 2, "U"), 1e-12); // 5 + 4/4
    // Repeated DATA= and SCORE=: the first is kept (cu, not coef): U = 3.5.
    o = try e.run("proc score data=raw data=nog score=cu score=coef out=o; var x y; run;");
    try approx(@as(f64, 3.5), cell(o, 2, "U"), 1e-12);
    // USCORE without USTD: raw values, MEAN ignored: 5 + 4 = 9.
    const cu2 = try a.create(Dataset);
    cu2.* = Dataset.init(a, "cu2");
    _ = try cu2.addColumn("_TYPE_", .char);
    _ = try cu2.addColumn("_NAME_", .char);
    _ = try cu2.addColumn("x", .num);
    _ = try cu2.addColumn("y", .num);
    try cu2.appendRow(&.{ str("MEAN"), str(""), num(1), num(1) });
    try cu2.appendRow(&.{ str("USCORE"), str("U"), num(1), num(1) });
    try e.lib.put("cu2", cu2);
    o = try e.run("proc score data=raw score=cu2 out=o; var x y; run;");
    try approx(@as(f64, 9), cell(o, 2, "U"), 1e-12);
    // Missing MEAN value: not centred; two MEAN rows: the last is used.
    // MEAN rows (x=., y=1) then (x=1, y=.): z = (x-1) + y = 4 + 4 = 8.
    const cm = try a.create(Dataset);
    cm.* = Dataset.init(a, "cm");
    _ = try cm.addColumn("_TYPE_", .char);
    _ = try cm.addColumn("_NAME_", .char);
    _ = try cm.addColumn("x", .num);
    _ = try cm.addColumn("y", .num);
    try cm.appendRow(&.{ str("MEAN"), str(""), num(nan), num(1) });
    try cm.appendRow(&.{ str("MEAN"), str(""), num(1), num(nan) });
    try cm.appendRow(&.{ str("USTD"), str(""), num(9), num(9) }); // ignored for SCORE rows
    try cm.appendRow(&.{ str("SCORE"), str("Z"), num(1), num(1) });
    try e.lib.put("cm", cm);
    o = try e.run("proc score data=raw score=cm out=o; var x y; run;");
    try approx(@as(f64, 8), cell(o, 2, "Z"), 1e-12);
    // Empty SCORE=: the DATA= variables only.
    const ec = try a.create(Dataset);
    ec.* = Dataset.init(a, "ec");
    _ = try ec.addColumn("_TYPE_", .char);
    _ = try ec.addColumn("_NAME_", .char);
    _ = try ec.addColumn("x", .num);
    try e.lib.put("ec", ec);
    o = try e.run("proc score data=raw score=ec out=o; var x; run;");
    try expectEqual(@as(usize, 4), o.columns.items.len);
    try expectEqual(@as(usize, 3), o.rows.items.len);
    // BY groups with different score names: the union, missing elsewhere.
    const bu = try a.create(Dataset);
    bu.* = Dataset.init(a, "bu");
    _ = try bu.addColumn("g", .num);
    _ = try bu.addColumn("_TYPE_", .char);
    _ = try bu.addColumn("_NAME_", .char);
    _ = try bu.addColumn("x", .num);
    try bu.appendRow(&.{ num(1), str("SCORE"), str("A"), num(1) });
    try bu.appendRow(&.{ num(2), str("SCORE"), str("B"), num(2) });
    try e.lib.put("bu", bu);
    o = try e.run("proc score data=raw score=bu out=o; by g; var x; run;");
    try expectEqual(@as(usize, 6), o.columns.items.len); // g id x y A B
    try approx(@as(f64, 3), cell(o, 1, "A"), 1e-12);
    try expect(std.math.isNan(cell(o, 1, "B")));
    try approx(@as(f64, 10), cell(o, 2, "B"), 1e-12);
    try expect(std.math.isNan(cell(o, 2, "A")));
}
