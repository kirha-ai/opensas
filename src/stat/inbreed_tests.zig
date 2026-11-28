//! STAT-INBREED-001 permanent tests: PROC INBREED options, VAR / BY roles,
//! default (unaddressed) variables, the missing-value rules (pp.5278-5279),
//! population building (inserted parents, duplicates, covariance
//! assignments) and loud execution boundaries. Data are invented (D-011).
//! Expected values are hand mathematics of the documented recursion
//! (f_XY = (f_XC + f_XD)/2, f_XX = (1 + F_X)/2, unknown = INIT/2 or missing),
//! stated next to each check, never opensas output.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const inbreed = @import("inbreed.zig");
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

/// Column names starting with '#' are numeric.
fn put(a: A, lib: *Library, name: []const u8, cols: []const []const u8, rows: []const []const Value) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for (cols) |c| {
        const is_num = c[0] == '#';
        _ = try ds.addColumn(if (is_num) c[1..] else c, if (is_num) .num else .char);
    }
    for (rows) |r| try ds.appendRow(r);
    try lib.put(name, ds);
}

fn build(a: A, lib: *Library) !void {
    // ped: A, B founders; C, D full sibs of A x B; E = C x D.
    try put(a, lib, "ped", &.{ "animal", "sire", "dam" }, &.{
        &.{ str("A"), str(""), str("") },
        &.{ str("B"), str(""), str("") },
        &.{ str("C"), str("A"), str("B") },
        &.{ str("D"), str("A"), str("B") },
        &.{ str("E"), str("C"), str("D") },
    });
    // pop: unknown parents Q, R inserted; missing individual skipped;
    // duplicate X skipped; R defined after use skipped; covariance 0.5 for
    // Q x R given on Y overrides the earlier 0.2 given on X.
    try put(a, lib, "pop", &.{ "id", "p1", "p2", "#cv", "#extra" }, &.{
        &.{ str("X"), str("Q"), str("R"), num(0.2), num(9) },
        &.{ str(""), str("X"), str("Q"), num(0.5), num(9) },
        &.{ str("Y"), str("Q"), str("R"), num(0.5), num(9) },
        &.{ str("X"), str("R"), str("Q"), num(nan), num(9) },
        &.{ str("R"), str("S"), str("T"), num(nan), num(9) },
    });
    // grp: BY g, two populations reusing the same names.
    try put(a, lib, "grp", &.{ "#g", "id", "p1", "p2" }, &.{
        &.{ num(1), str("A"), str(""), str("") },
        &.{ num(1), str("B"), str("A"), str("A") },
        &.{ num(2), str("A"), str("P"), str("") },
        &.{ num(2), str("B"), str("A"), str("P") },
        &.{ num(2), str("C"), str("B"), str("B") },
    });
    try put(a, lib, "unsorted", &.{ "#g", "id", "p1", "p2" }, &.{
        &.{ num(2), str("A"), str(""), str("") },
        &.{ num(1), str("B"), str(""), str("") },
    });
    // numeric identifiers; the last observation has a missing individual.
    try put(a, lib, "numped", &.{ "#i", "#p", "#q" }, &.{
        &.{ num(1), num(nan), num(nan) },
        &.{ num(2), num(nan), num(nan) },
        &.{ num(3), num(1), num(2) },
        &.{ num(nan), num(1), num(2) },
    });
    // long names: only the first 12 characters are recognized.
    try put(a, lib, "longn", &.{ "animal", "sire", "dam" }, &.{
        &.{ str("ABCDEFGHIJKLMNO1"), str(""), str("") },
        &.{ str("ABCDEFGHIJKLMNO2"), str(""), str("") },
        &.{ str("KID"), str("ABCDEFGHIJKLMNO1"), str("ABCDEFGHIJKLMNO2") },
    });
    try put(a, lib, "empty", &.{ "animal", "sire", "dam" }, &.{});
    try put(a, lib, "chcov", &.{ "id", "p1", "p2", "c" }, &.{
        &.{ str("X"), str(""), str(""), str("a") },
    });
    // gen: nonoverlapping generations. Gen 1: A, B (parents P, Q, R
    // unknown, inserted into an implicit generation 0); gen 2: C, D full
    // sibs of A x B, E = A x A; an observation with a missing generation
    // is excluded; the assignment observation fixes Cov(C, E) = 0.5 for
    // the whole family of C (C and D).
    try put(a, lib, "gen", &.{ "id", "p1", "p2", "#cv", "#gen" }, &.{
        &.{ str("A"), str("P"), str("Q"), num(nan), num(1) },
        &.{ str("B"), str("P"), str("R"), num(nan), num(1) },
        &.{ str("Z"), str(""), str(""), num(nan), num(nan) },
        &.{ str("C"), str("A"), str("B"), num(nan), num(2) },
        &.{ str("D"), str("A"), str("B"), num(nan), num(2) },
        &.{ str("E"), str("A"), str("A"), num(nan), num(2) },
        &.{ str(""), str("C"), str("E"), num(0.5), num(2) },
    });
    try put(a, lib, "genbad", &.{ "id", "p1", "p2", "#gen", "cgen" }, &.{
        &.{ str("A"), str(""), str(""), num(1.5), str("x") },
    });
    try put(a, lib, "genrep", &.{ "id", "p1", "p2", "#gen" }, &.{
        &.{ str("A"), str(""), str(""), num(1) },
        &.{ str("B"), str("A"), str(""), num(2) },
        &.{ str("C"), str(""), str(""), num(1) },
    });
    try put(a, lib, "genundef", &.{ "id", "p1", "p2", "#cv", "#gen" }, &.{
        &.{ str("A"), str(""), str(""), num(nan), num(1) },
        &.{ str(""), str("A"), str("B"), num(0.5), num(1) },
    });
    try put(a, lib, "two", &.{ "id", "p1" }, &.{
        &.{ str("X"), str("") },
    });
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
    fn toks(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !inbreed.Spec {
        return inbreed.parse(self.cx(), try self.toks(source));
    }
    fn pop(self: *Env, source: []const u8) !inbreed.Population {
        const s = try self.parse(source);
        return inbreed.build(self.cx(), s, s.input.ds.rows.items, 0);
    }
    fn run(self: *Env, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try inbreed.run(self.cx(), &out, try self.toks(source));
        return out.items;
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

fn has(hay: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, hay, needle) != null;
}

test "STAT-INBREED-001 PROC statement defaults, aliases and explicit options" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // p.5275: DATA= defaults to the most recently created data set.
    try put(e.arena.allocator(), &e.lib, "latest", &.{ "i", "s", "d", "#x", "y" }, &.{});
    const d = try e.parse("proc inbreed; run;");
    try expect(!d.covar and !d.matrix and !d.ind and !d.noprint and d.init == null and !d.var_given);
    try expectEqual(@as(usize, 5), d.input.ds.columns.items.len);
    // Five unaddressed variables: the numeric fourth one is the covariance
    // variable (p.5278); the fifth is unused.
    try expectEqual(@as(?usize, 3), d.cov_col);
    // Aliases C / M / I (pp.5275-5276).
    const s = try e.parse("proc inbreed data=work.ped c m i init=0.25 noprint; var animal sire dam; run;");
    try expect(s.covar and s.matrix and s.ind and s.noprint and s.var_given);
    try approx(@as(f64, 0.25), s.init.?, 1e-12);
    const l = try e.parse("proc inbreed data=ped covar matrix ind init=-0.5; run;");
    try expect(l.covar and l.matrix and l.ind);
    try approx(@as(f64, -0.5), l.init.?, 1e-12);
}

test "STAT-INBREED-001 VAR roles, default unaddressed variables and BY exclusion" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // p.5278: without VAR the first three unaddressed variables, and an
    // unaddressed fourth becomes the covariance variable.
    const p = try e.parse("proc inbreed data=pop; run;");
    try expectEqual(@as(usize, 0), p.ind_col);
    try expectEqual(@as(usize, 1), p.p1_col);
    try expectEqual(@as(usize, 2), p.p2_col);
    try expectEqual(@as(?usize, 3), p.cov_col);
    // A BY variable is addressed, so it is not taken as the individual.
    const g = try e.parse("proc inbreed data=grp; by g; run;");
    try expectEqual(@as(usize, 1), g.ind_col);
    try expectEqual(@as(?usize, null), g.cov_col);
    // Explicit three-variable VAR: no covariance variable.
    const v = try e.parse("proc inbreed data=pop; var id p1 p2; run;");
    try expectEqual(@as(?usize, null), v.cov_col);
    const v4 = try e.parse("proc inbreed data=pop; var id p1 p2 cv; run;");
    try expectEqual(@as(?usize, 3), v4.cov_col);
    // p.5276: only the last BY statement is used.
    const lb = try e.parse("proc inbreed data=grp; by id; by g; run;");
    try expectEqual(@as(usize, 1), lb.by_cols.len);
    try expectEqual(@as(usize, 0), lb.by_cols[0]);
}

test "STAT-INBREED-001 invalid input is a user error (rc 1)" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const cases = [_]struct { src: []const u8, msg: []const u8 }{
        .{ .src = "proc inbreed data=ped; var animal sire; run;", .msg = "three or four" },
        .{ .src = "proc inbreed data=pop; var id p1 p2 cv extra; run;", .msg = "three or four" },
        .{ .src = "proc inbreed data=ped; var animal sire sire; run;", .msg = "more than once" },
        .{ .src = "proc inbreed data=ped; var animal sire nosuch; run;", .msg = "" },
        .{ .src = "proc inbreed data=chcov; var id p1 p2 c; run;", .msg = "must be numeric" },
        .{ .src = "proc inbreed data=two; run;", .msg = "at least three" },
        .{ .src = "proc inbreed data=nosuch; run;", .msg = "not found" },
        .{ .src = "proc inbreed data=ped init=abc; run;", .msg = "INIT=" },
        .{ .src = "proc inbreed data=ped bogus; run;", .msg = "invalid" },
        .{ .src = "proc inbreed data=ped; bogus x; run;", .msg = "invalid" },
    };
    for (cases) |c| {
        diag.resetGap();
        defer diag.resetGap();
        std.testing.expectError(error.ParseError, e.parse(c.src)) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{c.src});
            return err;
        };
        try expect(!diag.gapHit());
        try expect(has(e.lastError(), c.msg));
    }
    // An unsorted BY variable fails when the groups are formed.
    try std.testing.expectError(error.ParseError, e.run("proc inbreed data=unsorted matrix; by g; run;"));
    try expect(has(e.lastError(), "not sorted"));
}

test "STAT-INBREED-001 unimplemented valid features are loud D-009 gaps" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const cases = [_][]const u8{
        "proc inbreed data=gen; class gen; class gen; run;",
        "proc inbreed data=gen matrixl; class gen; run;",
        "proc inbreed data=pop; gender p1; run;",
        "proc inbreed data=pop; matings X / Y; run;",
        "proc inbreed data=pop outcov=o; run;",
        "proc inbreed data=pop average; run;",
        "proc inbreed data=pop a; run;",
        "proc inbreed data=pop indl; run;",
        "proc inbreed data=pop matrixl; run;",
        "proc inbreed data=pop selfdiag; run;",
        "proc inbreed data=pop; var id p1 p2; var id p1 p2; run;",
        "proc inbreed data=chcov; run;",
    };
    for (cases) |c| {
        diag.resetGap();
        defer diag.resetGap();
        std.testing.expectError(error.ParseError, e.parse(c)) catch |err| {
            std.debug.print("unexpected result for: {s}\n", .{c});
            return err;
        };
        try expect(diag.gapHit());
    }
    // A covariance value for an individual with a missing parent.
    diag.resetGap();
    defer diag.resetGap();
    try put(e.arena.allocator(), &e.lib, "halfcov", &.{ "id", "p1", "p2", "#cv" }, &.{&.{ str("X"), str("Q"), str(""), num(0.5) }});
    try std.testing.expectError(error.ParseError, e.pop("proc inbreed data=halfcov; run;"));
    try expect(diag.gapHit());
}

test "STAT-INBREED-001 coancestry recursion of the reference pedigree" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const p = try e.pop("proc inbreed data=ped covar matrix; var animal sire dam; run;");
    try expectEqual(@as(usize, 5), p.n());
    // f_AA = 1/2; f_AB missing (unrelated founders, no INIT=).
    try approx(@as(f64, 1.0), p.value(true, 0, 0), 1e-12);
    try expect(std.math.isNan(p.value(true, 0, 1)));
    // f_AC = (f_AA + f_AB)/2 = 1/4 -> Cov 0.5; f_CD = (f_CA + f_CB)/2 = 1/4.
    try approx(@as(f64, 0.5), p.value(true, 0, 2), 1e-12);
    try approx(@as(f64, 0.5), p.value(true, 2, 3), 1e-12);
    // f_CE = (f_CC + f_CD)/2 = (1/2 + 1/4)/2 = 3/8 -> 0.75; f_EE = (1 + 1/4)/2.
    try approx(@as(f64, 0.75), p.value(true, 2, 4), 1e-12);
    try approx(@as(f64, 1.25), p.value(true, 4, 4), 1e-12);
    // Inbreeding mode: F missing for A..D, F_E = f_CD = 0.25; off-diagonal f.
    for (0..4) |i| try expect(std.math.isNan(p.value(false, i, i)));
    try approx(@as(f64, 0.25), p.value(false, 4, 4), 1e-12);
    try approx(@as(f64, 0.375), p.value(false, 2, 4), 1e-12);
    // INIT=0.25: unknown coancestry 1/8; F_C = 1/8; Cov(A,A) = 1 + 1/8.
    const q = try e.pop("proc inbreed data=ped covar init=0.25; run;");
    try approx(@as(f64, 0.25), q.value(true, 0, 1), 1e-12);
    try approx(@as(f64, 1.125), q.value(true, 0, 0), 1e-12);
    try approx(@as(f64, 0.125), q.value(false, 2, 2), 1e-12);
    // f_AC = (9/16 + 1/8)/2 = 11/32 -> Cov 0.6875.
    try approx(@as(f64, 0.6875), q.value(true, 0, 2), 1e-12);
    // INIT=0 keeps unknown pairs missing, as without INIT= (reference run).
    const z = try e.pop("proc inbreed data=ped covar init=0; run;");
    try expect(std.math.isNan(z.value(true, 0, 1)));
    try approx(@as(f64, 0.5), z.value(true, 0, 2), 1e-12);
}

test "STAT-INBREED-001 missing values, inserted parents, duplicates and covariance assignments" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const p = try e.pop("proc inbreed data=pop covar; run;");
    // Population order: Q, R (inserted before X), X, Y; the missing
    // individual, the duplicate X and the late R are skipped.
    try expectEqual(@as(usize, 4), p.n());
    const want = [_][]const u8{ "Q", "R", "X", "Y" };
    for (want, p.names) |w, n| try std.testing.expectEqualStrings(w, n);
    try std.testing.expectEqualStrings("", p.p1_text[0]);
    try std.testing.expectEqualStrings("Q", p.p1_text[2]);
    // Latest covariance for Q x R wins (0.5 over 0.2), also for X defined
    // before the assignment: f_QR = 1/4, F_X = 1/4 -> Cov(X,X) = 1.25.
    try approx(@as(f64, 0.5), p.value(true, 0, 1), 1e-12);
    try approx(@as(f64, 1.25), p.value(true, 2, 2), 1e-12);
    // f_QX = (f_QQ + f_QR)/2 = (1/2 + 1/4)/2 = 3/8 -> 0.75; full sibs
    // f_XY = (f_XQ + f_XR)/2 = 3/8 -> 0.75.
    try approx(@as(f64, 0.75), p.value(true, 0, 2), 1e-12);
    try approx(@as(f64, 0.75), p.value(true, 2, 3), 1e-12);
    var warned: usize = 0;
    var noted_missing = false;
    for (e.diags.list.items) |m| {
        if (m.severity == .warning and has(m.message, "has been previously defined")) warned += 1;
        if (m.severity == .warning and has(m.message, "Variable id has a missing value at observation 2")) noted_missing = true;
    }
    try expectEqual(@as(usize, 2), warned);
    try expect(noted_missing);
}

test "STAT-INBREED-001 numeric names, 12-character names, empty, NOPRINT and BY groups" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const n = try e.pop("proc inbreed data=numped covar; run;");
    try expectEqual(@as(usize, 3), n.n());
    try std.testing.expectEqualStrings("3", n.names[2]);
    try approx(@as(f64, 0.5), n.value(true, 0, 2), 1e-12);
    // Both long founders collapse to ABCDEFGHIJKL: the second is a
    // duplicate, so KID is a self-mating: F = f_XX = 1/2 -> Cov 1.5.
    const l = try e.pop("proc inbreed data=longn covar; run;");
    try expectEqual(@as(usize, 2), l.n());
    try std.testing.expectEqualStrings("ABCDEFGHIJKL", l.names[0]);
    try approx(@as(f64, 1.5), l.value(true, 1, 1), 1e-12);
    try approx(@as(f64, 1.0), l.value(true, 0, 1), 1e-12);
    // Empty input prints nothing.
    try expectEqual(@as(usize, 0), (try e.run("proc inbreed data=empty matrix covar; run;")).len);
    // NOPRINT prints nothing.
    try expectEqual(@as(usize, 0), (try e.run("proc inbreed data=ped matrix ind noprint; run;")).len);
    // BY g: g=1 is A, B = A x A (F_B = f_AA = 1/2); g=2 restarts with A (P
    // inserted), B = A x P, C = B x B: f_AP = (f_PP + missing)/2 = 1/4,
    // F_B = 1/4, F_C = f_BB = (1 + 1/4)/2 = 0.625.
    const out = try e.run("proc inbreed data=grp ind; by g; run;");
    try expect(has(out, "g=1") and has(out, "g=2"));
    try expect(has(out, "Number of Individuals    2") and has(out, "Number of Individuals    4"));
    try expect(has(out, "0.6250") and has(out, "0.2500") and has(out, "0.5000"));
    try expect(has(out, "Inbreeding Coefficients of Individuals"));
}

test "STAT-INBREED-001 CLASS nonoverlapping generations" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = try e.parse("proc inbreed data=gen covar matrix; class gen; run;");
    try expectEqual(@as(?usize, 4), s.class_col);
    // CLASS is addressed: the default VAR takes id p1 p2 and cv.
    try expectEqual(@as(?usize, 3), s.cov_col);
    const g = try inbreed.buildGenerations(e.cx(), s, s.input.ds.rows.items, 0);
    try expectEqual(@as(usize, 2), g.len);
    try std.testing.expectEqualStrings("1", g[0].label);
    const g1 = g[0].pop;
    const g2 = g[1].pop;
    try expectEqual(@as(usize, 2), g1.n()); // Z (missing generation) excluded
    try expectEqual(@as(usize, 3), g2.n());
    // Gen 1: f_AB = (f_PP + f_PR + f_QP + f_QR)/4 = (1/2)/4 = 1/8 -> Cov 0.25;
    // F_A = f_PQ missing -> Cov(A,A) = 1.
    try approx(@as(f64, 0.25), g1.value(true, 0, 1), 1e-12);
    try approx(@as(f64, 1.0), g1.value(true, 0, 0), 1e-12);
    try expect(std.math.isNan(g1.value(false, 0, 0)));
    // Gen 2: full sibs C, D: f = (f_AA + 2 f_AB + f_BB)/4 = (1/2 + 1/4 + 1/2)/4
    // = 5/16 -> Cov 0.625; F_C = f_AB = 1/8 -> Cov(C,C) = 1.125.
    try approx(@as(f64, 0.625), g2.value(true, 0, 1), 1e-12);
    try approx(@as(f64, 1.125), g2.value(true, 0, 0), 1e-12);
    // E = A x A: F_E = f_AA = 1/2 -> Cov(E,E) = 1.5.
    try approx(@as(f64, 1.5), g2.value(true, 2, 2), 1e-12);
    // Assignment Cov(C, E) = 0.5 applies to C's family: Cov(D, E) = 0.5 too
    // (computed value would be (f_AA + f_AA + f_BA + f_BA)/4 = 5/16 -> 0.625).
    try approx(@as(f64, 0.5), g2.value(true, 0, 2), 1e-12);
    try approx(@as(f64, 0.5), g2.value(true, 1, 2), 1e-12);
    // Invalid CLASS input (rc 1) and unverified shapes (rc 2).
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, e.parse("proc inbreed data=genbad; var id p1 p2; class cgen; run;"));
    try expect(has(e.lastError(), "must be numeric") and !diag.gapHit());
    try std.testing.expectError(error.ParseError, e.parse("proc inbreed data=genbad; class nosuch; run;"));
    try std.testing.expectError(error.ParseError, e.parse("proc inbreed data=genbad; class gen cgen; run;"));
    const bad = try e.parse("proc inbreed data=genbad; var id p1 p2; class gen; run;");
    try std.testing.expectError(error.ParseError, inbreed.buildGenerations(e.cx(), bad, bad.input.ds.rows.items, 0));
    try expect(has(e.lastError(), "not an integer") and !diag.gapHit());
    const rep = try e.parse("proc inbreed data=genrep; class gen; run;");
    try std.testing.expectError(error.ParseError, inbreed.buildGenerations(e.cx(), rep, rep.input.ds.rows.items, 0));
    try expect(diag.gapHit());
    diag.resetGap();
    const und = try e.parse("proc inbreed data=genundef; class gen; run;");
    try std.testing.expectError(error.ParseError, inbreed.buildGenerations(e.cx(), und, und.input.ds.rows.items, 0));
    try expect(diag.gapHit());
}
