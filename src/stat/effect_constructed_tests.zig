//! STAT-COMMON-022 permanent tests: EFFECT POLYNOMIAL / MULTIMEMBER parsing,
//! defaults, applicability classes and hand-computed design columns.
//! Expected values are written by hand from S154 Chapter 20 (physical
//! pp.429-434); nothing here reads tests/STAT15.4-oracle/.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const ec = @import("effect_constructed.zig");
const t_ = std.testing;
const A = std.mem.Allocator;
const nan = std.math.nan(f64);

fn parseSrc(a: A, d: *diag.Diagnostics, ds: *const Dataset, classes: []const usize, src: []const u8) !ec.Spec {
    const toks = try lex.tokenize(a, src, d);
    return ec.parse(a, d, ds, classes, &.{"earlier"}, toks[1..], 1);
}
fn poly(a: A, ds: *const Dataset, src: []const u8, freq: ?[]const f64, weight: ?[]const f64) !ec.Built {
    var d = diag.Diagnostics.init(a);
    const s = try parseSrc(a, &d, ds, &.{}, src);
    return ec.buildPolynomial(a, &d, ds, ds.rows.items, s.name, s.body.polynomial, freq, weight, 1);
}
fn numeric(a: A, names: []const []const u8, rows: []const []const f64) !Dataset {
    var ds = Dataset.init(a, "tiny");
    for (names) |n| _ = try ds.addColumn(n, .num);
    for (rows) |r| {
        const v = try a.alloc(Value, r.len);
        for (r, 0..) |x, i| v[i] = .{ .num = x };
        try ds.appendRow(v);
    }
    return ds;
}
fn expectNames(want: []const []const u8, got: []const []const u8) !void {
    try t_.expectEqual(want.len, got.len);
    for (want, got) |w, g| try t_.expectEqualStrings(w, g);
}
fn expectMatrix(want: []const f64, b: ec.Built, tol: f64) !void {
    try t_.expectEqual(want.len, b.n * b.p);
    for (want, b.x) |w, g| {
        if (std.math.isNan(w)) {
            try t_.expect(std.math.isNan(g));
        } else if (tol == 0) {
            try t_.expectEqual(w, g);
        } else try t_.expectApproxEqAbs(w, g, tol);
    }
}

test "COMMON022 polynomial degree 2 and 3: term order, names, dimensions, values" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try numeric(a, &.{ "x", "z", "y" }, &.{ &.{ 2, 3, 0 }, &.{ -1, 4, 0 }, &.{ 0.5, 2, 0 }, &.{ nan, 2, 0 } });
    // The SAS listing of `effect poly=polynomial(x z / degree=2)` names its
    // parameters, in order: x, z, x^2, x*z, z^2 (5 effects besides Intercept).
    const b2 = try poly(a, &ds, "effect poly=polynomial(x z / degree=2);", null, null);
    try expectNames(&.{ "x", "z", "x^2", "x*z", "z^2" }, b2.names);
    try expectNames(&.{ "x", "z", "x^2", "x*z", "z^2" }, b2.effects); // separate effects by default
    try t_.expectEqual(@as(usize, 4), b2.n);
    try t_.expectEqual(@as(usize, 5), b2.p);
    try expectMatrix(&.{
        2,   3,   4,    6,   9,
        -1,  4,   1,    -4,  16,
        0.5, 2,   0.25, 1,   4,
        nan, nan, nan,  nan, nan, // missing x: every column of the effect is missing
    }, b2, 0);
    try t_.expectEqualSlices(usize, &.{ 1, 0, 0, 1, 2, 0, 1, 1, 0, 2 }, b2.exponents);
    const b3 = try poly(a, &ds, "effect p3=poly(x z / degree=3);", null, null);
    try expectNames(&.{ "x", "z", "x^2", "x*z", "z^2", "x^3", "x^2*z", "x*z^2", "z^3" }, b3.names);
    try t_.expectEqualSlices(f64, &.{ 2, 3, 4, 6, 9, 8, 12, 18, 27 }, b3.x[0..9]);
    try t_.expectEqualSlices(f64, &.{ -1, 4, 1, -4, 16, -1, 4, -16, 64 }, b3.x[9..18]);
    // Default DEGREE=1, MDEGREE=DEGREE.
    const b1 = try poly(a, &ds, "effect p1=polynomial(x z);", null, null);
    try expectNames(&.{ "x", "z" }, b1.names);
}

test "COMMON022 polynomial documented examples: var-list range, MDEGREE, LABELSTYLE, NOSEPARATE" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try numeric(a, &.{ "x1", "x2", "x3" }, &.{&.{ 2, 3, 5 }});
    // p.431: polynomial(x1-x3/degree=2) == x1 x2 x3 x1*x1 x1*x2 x1*x3 x2*x2 x2*x3 x3*x3
    const ex = try poly(a, &ds, "effect MyPoly = polynomial(x1-x3/degree=2 labelstyle=expand);", null, null);
    try expectNames(&.{ "x1", "x2", "x3", "x1*x1", "x1*x2", "x1*x3", "x2*x2", "x2*x3", "x3*x3" }, ex.names);
    try expectMatrix(&.{ 2, 3, 5, 4, 6, 10, 9, 15, 25 }, ex, 0);
    // p.432: degree=4 MDEGREE=2 -> x1 x2 x1^2 x1x2 x2^2 x1^2x2 x1x2^2 x1^2x2^2
    const md = try poly(a, &ds, "effect MyPoly=POLYNOMIAL(x1 x2/degree=4 MDEGREE=2);", null, null);
    try expectNames(&.{ "x1", "x2", "x1^2", "x1*x2", "x2^2", "x1^2*x2", "x1*x2^2", "x1^2*x2^2" }, md.names);
    try expectMatrix(&.{ 2, 3, 4, 6, 9, 12, 18, 36 }, md, 0);
    // p.431-432 label examples for the term x1^3 x2 x3^2 (value 8*3*25).
    const cases = [_]struct { []const u8, []const u8 }{
        .{ "effect q=polynomial(x1 x2 x3/degree=6);", "x1^3*x2*x3^2" },
        .{ "effect q=polynomial(x1 x2 x3/degree=6 labelstyle=(expand));", "x1*x1*x1*x2*x3*x3" },
        .{ "effect q=polynomial(x1 x2 x3/degree=6 LABELSTYLE=(EXPONENT=\"**\"));", "x1**3*x2*x3**2" },
        .{ "effect q=polynomial(x1 x2 x3/degree=6 labelstyle=(productsymbol=none exponent));", "x1^3x2x3^2" },
    };
    for (cases) |c| {
        const b = try poly(a, &ds, c[0], null, null);
        try t_.expectEqual(@as(usize, 83), b.p); // C(9,3)-1 terms of degree 1..6 in 3 variables
        var found: usize = 0;
        for (b.names, 0..) |n, j| if (std.mem.eql(u8, n, c[1])) {
            found += 1;
            try t_.expectEqual(@as(f64, 600), b.x[j]);
        };
        try t_.expectEqual(@as(usize, 1), found);
    }
    const inc = try poly(a, &ds, "EFFECT MyPoly=POLYNOMIAL(x1/degree=2 labelstyle=INCLUDENAME);", null, null);
    try expectNames(&.{ "MyPoly_x1", "MyPoly_x1^2" }, inc.names);
    const ps = try poly(a, &ds, "EFFECT MyPoly=POLYNOMIAL(x1 x2 / degree=2 mdegree=1 labelstyle=(PRODUCTSYMBOL=\" \"));", null, null);
    try expectNames(&.{ "x1", "x2", "x1 x2" }, ps.names);
    // NOSEPARATE: one effect named by the EFFECT name; INCLUDENAME is ignored.
    const ns = try poly(a, &ds, "effect MyPoly=polynomial(x1 x2/degree=2 noseparate details labelstyle=includename);", null, null);
    try expectNames(&.{ "x1", "x2", "x1^2", "x1*x2", "x2^2" }, ns.names);
    try expectNames(&.{ "MyPoly", "MyPoly", "MyPoly", "MyPoly", "MyPoly" }, ns.effects);
}

test "COMMON022 polynomial STANDARDIZE: Table 20.13 centers and scales, modes, prefix" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try numeric(a, &.{"x"}, &.{ &.{1}, &.{2}, &.{3}, &.{6} });
    // RANGE (default): center (6+1)/2 = 3.5, scale (6-1)/2 = 2.5.
    const r = try poly(a, &ds, "effect p=polynomial(x / degree=2 standardize);", null, null);
    try expectNames(&.{ "s_x", "s_x^2" }, r.names);
    try t_.expectEqual(@as(f64, 3.5), r.centers[0]);
    try t_.expectEqual(@as(f64, 2.5), r.scales[0]);
    try expectMatrix(&.{ -1, 1, -0.6, 0.36, -0.2, 0.04, 1, 1 }, r, 1e-15);
    const c = try poly(a, &ds, "effect p=polynomial(x / standardize(method=range prefix=none)=center);", null, null);
    try expectNames(&.{"x"}, c.names);
    try expectMatrix(&.{ -2.5, -1.5, -0.5, 2.5 }, c, 0);
    const s = try poly(a, &ds, "effect p=polynomial(x / standardize(prefix=\"c\")=scale);", null, null);
    try expectNames(&.{"cx"}, s.names);
    try expectMatrix(&.{ 0.4, 0.8, 1.2, 2.4 }, s, 0);
    const none = try poly(a, &ds, "effect p=polynomial(x / standardize=none);", null, null);
    try expectNames(&.{"x"}, none.names);
    try expectMatrix(&.{ 1, 2, 3, 6 }, none, 0);
    // MOMENTS, no frequencies: mean 3, scale sqrt((4+1+0+9)/3).
    const m = try poly(a, &ds, "effect p=polynomial(x / standardize(method=moments));", null, null);
    const sm = @sqrt(14.0 / 3.0);
    try expectMatrix(&.{ -2.0 / sm, -1.0 / sm, 0, 3.0 / sm }, m, 1e-15);
    // MOMENTS, f = 1,1,2,1: F=5, mean (1+2+6+6)/5 = 3, scale sqrt(14/(5-1)).
    const mf = try poly(a, &ds, "effect p=polynomial(x / standardize(method=moments)=centerscale);", &.{ 1, 1, 2, 1 }, null);
    const smf = @sqrt(3.5);
    try expectMatrix(&.{ -2.0 / smf, -1.0 / smf, 0, 3.0 / smf }, mf, 1e-15);
    // MOMENTS ignores weights except that an invalid weight drops the row from
    // the estimates: x = 1,2,3 -> mean 2, scale 1; the dropped row is still scored.
    const mw = try poly(a, &ds, "effect p=polynomial(x / standardize(method=moments));", null, &.{ 1, 2, 1, 0 });
    try expectMatrix(&.{ -1, 0, 1, 4 }, mw, 0);
    // WMOMENTS, w = 1,2,1,1: WF=5, mean (1+4+3+6)/5 = 2.8,
    // scale sqrt((3.24 + 2*0.64 + 0.04 + 10.24)/(4-1)) = sqrt(14.8/3).
    const wm = try poly(a, &ds, "effect p=polynomial(x / standardize(method=wmoments));", null, &.{ 1, 2, 1, 1 });
    const sw = @sqrt(14.8 / 3.0);
    try t_.expectApproxEqAbs(@as(f64, 2.8), wm.centers[0], 1e-15);
    try expectMatrix(&.{ -1.8 / sw, -0.8 / sw, 0.2 / sw, 3.2 / sw }, wm, 1e-14);
}

// Gaussian elimination with partial pivoting on the normal equations.
fn ols(a: A, x: []const f64, n: usize, p: usize, y: []const f64) ![]f64 {
    const q = p + 1;
    const m = try a.alloc(f64, q * (q + 1));
    @memset(m, 0);
    for (0..n) |i| for (0..q) |r| {
        const xr: f64 = if (r == 0) 1 else x[i * p + r - 1];
        for (0..q) |c| m[r * (q + 1) + c] += xr * (if (c == 0) 1 else x[i * p + c - 1]);
        m[r * (q + 1) + q] += xr * y[i];
    };
    for (0..q) |k| {
        var best = k;
        for (k + 1..q) |r| if (@abs(m[r * (q + 1) + k]) > @abs(m[best * (q + 1) + k])) {
            best = r;
        };
        for (0..q + 1) |c| std.mem.swap(f64, &m[k * (q + 1) + c], &m[best * (q + 1) + c]);
        for (0..q) |r| if (r != k) {
            const f = m[r * (q + 1) + k] / m[k * (q + 1) + k];
            for (k..q + 1) |c| m[r * (q + 1) + c] -= f * m[k * (q + 1) + c];
        };
    }
    const beta = try a.alloc(f64, q);
    for (0..q) |k| beta[k] = m[k * (q + 1) + q] / m[k * (q + 1) + k];
    return beta;
}

test "COMMON022 polynomial columns reproduce the SAS least-squares estimates of y = poly(x z / degree=2)" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Invented 12-observation sample (x z y).
    const ds = try numeric(a, &.{ "x", "z", "y" }, &.{
        &.{ 1, 1, 4 },   &.{ 2, 1, 6 },   &.{ 3, 2, 7 },   &.{ 4, 1, 9 },
        &.{ 5, 3, 13 },  &.{ 6, 2, 12 },  &.{ 7, 4, 17 },  &.{ 8, 3, 19 },
        &.{ 9, 5, 20 },  &.{ 10, 3, 23 }, &.{ 11, 5, 25 }, &.{ 12, 4, 24 },
    });
    const b = try poly(a, &ds, "effect poly=polynomial(x z / degree=2);", null, null);
    const y = try a.alloc(f64, b.n);
    for (ds.rows.items, 0..) |row, i| y[i] = row[2].num;
    const beta = try ols(a, b.x, b.n, b.p, y);
    // SAS reference Parameter Estimates (Intercept, x, z, x^2, x*z, z^2), printed
    // to 6 decimals: the bound is the half unit of the last printed digit (5e-7)
    // plus 5e-8 for the rounding of this normal-equations solve.
    const sas = [_]f64{ 0.560727, 1.925791, 1.183815, -0.053552, 0.211437, -0.337244 };
    try expectNames(&.{ "x", "z", "x^2", "x*z", "z^2" }, b.names);
    for (sas, beta) |want, got| try t_.expectApproxEqAbs(want, got, 5.5e-7);
}

fn teachers(a: A) !Dataset {
    // S154 p.429 published example, plus two invented weight columns.
    var ds = Dataset.init(a, "students");
    _ = try ds.addColumn("student", .char);
    _ = try ds.addColumn("score", .num);
    _ = try ds.addColumn("teacher1", .char);
    _ = try ds.addColumn("teacher2", .char);
    _ = try ds.addColumn("w1", .num);
    _ = try ds.addColumn("w2", .num);
    const rows = [_]struct { []const u8, f64, []const u8, []const u8, f64, f64 }{
        .{ "Mary", 87, "Tobias", "Cohen", 0.75, 0.25 },
        .{ "Tom", 89, "Rodriguez", "Tobias", 0.5, 0.5 },
        .{ "Fred", 82, "Cohen", "Cohen", 0.25, 0.5 },
        .{ "Jane", 88, "Tobias", "", 1, 1 },
        .{ "Jack", 99, "", "", 1, 1 },
    };
    for (rows) |r| try ds.appendRow(&.{ .{ .str = r[0] }, .{ .num = r[1] }, .{ .str = r[2] }, .{ .str = r[3] }, .{ .num = r[4] }, .{ .num = r[5] } });
    return ds;
}
fn mm(a: A, ds: *const Dataset, src: []const u8) !ec.Built {
    var d = diag.Diagnostics.init(a);
    const s = try parseSrc(a, &d, ds, &.{ 2, 3 }, src);
    return ec.buildMultimember(a, &d, ds, ds.rows.items, s.name, s.body.multimember, 1);
}

test "COMMON022 multimember: documented teacher design, NOEFFECT, STDIZE, WEIGHT=" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try teachers(a);
    // p.430 design matrix: Cohen Rodriguez Tobias; Fred repeats Cohen, Jane has
    // one member, Jack has none (all missing).
    const b = try mm(a, &ds, "EFFECT teacher = MM(teacher1 teacher2);");
    try expectNames(&.{ "Cohen", "Rodriguez", "Tobias" }, b.names);
    try expectNames(&.{ "teacher", "teacher", "teacher" }, b.effects);
    try t_.expectEqual(@as(usize, 5), b.n);
    try expectMatrix(&.{ 1, 0, 1, 0, 1, 1, 2, 0, 0, 0, 0, 1, nan, nan, nan }, b, 0);
    const ne = try mm(a, &ds, "EFFECT teacher = MULTIMEMBER(teacher1 teacher2 / noeffect details);");
    try expectMatrix(&.{ 1, 0, 1, 0, 1, 1, 2, 0, 0, 0, 0, 1, 0, 0, 0 }, ne, 0);
    // STDIZE: each row scaled to sum one.
    const st = try mm(a, &ds, "effect teacher = mm(teacher1 teacher2 / stdize);");
    try expectMatrix(&.{ 0.5, 0, 0.5, 0, 0.5, 0.5, 1, 0, 0, 0, 0, 1, nan, nan, nan }, st, 0);
    // WEIGHT= w1 w2: each member contributes its weight instead of 1.
    const w = try mm(a, &ds, "effect teacher = mm(teacher1 teacher2 / weight=w1 w2 noeffect);");
    try expectMatrix(&.{ 0.25, 0, 0.75, 0, 0.5, 0.5, 0.75, 0, 0, 0, 0, 1, 0, 0, 0 }, w, 0);
    const wp = try mm(a, &ds, "effect teacher = mm(teacher1 teacher2 / weight=(w1 w2) stdize);");
    try expectMatrix(&.{ 0.25, 0, 0.75, 0, 0.5, 0.5, 1, 0, 0, 0, 0, 1, nan, nan, nan }, wp, 0);
    // A single member with NOEFFECT (the p.430 carryover shape).
    const one = try mm(a, &ds, "effect carry = mm(teacher2 / noeffect);");
    try expectNames(&.{ "Cohen", "Tobias" }, one.names);
    try expectMatrix(&.{ 1, 0, 0, 1, 1, 0, 0, 0, 0, 0 }, one, 0);
}

const Class = enum { user, gap };
fn expectFail(a: A, ds: *const Dataset, classes: []const usize, src: []const u8, want: Class, needle: []const u8) !void {
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    const r = parseSrc(a, &d, ds, classes, src);
    try t_.expectError(error.ParseError, r);
    try t_.expect(d.hasErrors());
    // D-009: user error -> exit class 1, loud gap -> exit class 2.
    try t_.expectEqual(@as(u8, if (want == .gap) 2 else 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    const rendered = try d.render();
    if (std.mem.indexOf(u8, rendered, needle) == null) {
        std.debug.print("missing '{s}' in: {s}\n", .{ needle, rendered });
        return error.TestExpectedEqual;
    }
}

test "COMMON022 EFFECT applicability: user errors are class 1, unfinished forms are class 2" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try teachers(a);
    _ = try ds.addColumn("g", .num); // column 6, used as a numeric CLASS variable
    const cl = &[_]usize{ 2, 3, 6 };
    const user = [_]struct { []const u8, []const u8 }{
        .{ "effect p polynomial(score);", "expected EFFECT effect-name" },
        .{ "effect score=polynomial(w1);", "cannot be the name of a variable" },
        .{ "effect earlier=polynomial(w1);", "only one EFFECT statement" },
        .{ "effect p=cubic(w1);", "is not an effect type" },
        .{ "effect p=polynomial(nosuch);", "Variable nosuch not found." },
        .{ "effect p=polynomial();", "variable list is empty" },
        .{ "effect p=polynomial(/degree=2);", "variable list is empty" },
        .{ "effect p=polynomial(student);", "must be numeric" },
        .{ "effect p=polynomial(g);", "is a CLASS variable" },
        .{ "effect p=polynomial(w1/degree=0);", "DEGREE= requires a positive integer" },
        .{ "effect p=polynomial(w1/degree=1.5);", "DEGREE= requires a positive integer" },
        .{ "effect p=polynomial(w1/mdegree=x);", "MDEGREE= requires a positive integer" },
        .{ "effect p=polynomial(w1/noeffect);", "invalid polynomial effect option" },
        .{ "effect p=polynomial(w1/labelstyle=bold);", "invalid LABELSTYLE= style option" },
        .{ "effect p=polynomial(w1/labelstyle=(productsymbol=x));", "PRODUCTSYMBOL= requires NONE or a quoted string" },
        .{ "effect p=polynomial(w1/standardize(method=median));", "METHOD= requires MOMENTS, RANGE or WMOMENTS" },
        .{ "effect p=polynomial(w1/standardize=both);", "STANDARDIZE= requires CENTER" },
        .{ "effect t=mm(student);", "must appear in the CLASS statement" },
        .{ "effect t=mm(teacher1 teacher2/degree=2);", "invalid multimember effect option" },
        .{ "effect t=mm(teacher1 teacher2/weight=w1);", "must match the number of classification variables" },
        .{ "effect t=mm(teacher1 teacher2/weight=(w1 w2 score));", "must match the number of classification variables" },
        .{ "effect t=mm(teacher1 teacher2/weight=w1 student);", "must be numeric" },
    };
    for (user) |c| try expectFail(a, &ds, cl, c[0], .user, c[1]);
    const gaps = [_]struct { []const u8, []const u8 }{
        .{ "effect s=spline(w1);", "effect type is not implemented" },
        .{ "effect s=collection(w1 w2);", "effect type is not implemented" },
        .{ "effect s=lag(teacher1 / period=score within=student);", "effect type is not implemented" },
        .{ "effect p=polynomial(w1 w1);", "listed more than once" },
        .{ "effect p=polynomial(w1/degree=2 degree=3);", "DEGREE= option is repeated" },
        .{ "effect p=polynomial(w1/degree=65);", "beyond the supported maximum" },
        .{ "effect p=polynomial(w1/labelstyle=(expand exponent));", "both EXPAND and EXPONENT" },
        .{ "effect t=mm(teacher1 teacher2/noeffect noeffect);", "NOEFFECT option is repeated" },
    };
    for (gaps) |c| try expectFail(a, &ds, cl, c[0], .gap, c[1]);

    // Build-time loud gaps: constant variable under scaling, numeric member,
    // missing weight for a nonmissing member.
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    const flat = try numeric(a, &.{"x"}, &.{ &.{2}, &.{2} });
    const sp = try parseSrc(a, &d, &flat, &.{}, "effect p=polynomial(x/standardize);");
    try t_.expectError(error.ParseError, ec.buildPolynomial(a, &d, &flat, flat.rows.items, sp.name, sp.body.polynomial, null, null, 1));
    try t_.expect(diag.gapHit());
    diag.resetGap();
    const sn = try parseSrc(a, &d, &ds, cl, "effect t=mm(g);");
    try t_.expectError(error.ParseError, ec.buildMultimember(a, &d, &ds, ds.rows.items, sn.name, sn.body.multimember, 1));
    try t_.expect(diag.gapHit());
}

test "COMMON022 parsed defaults and option values" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try teachers(a);
    var d = diag.Diagnostics.init(a);
    const p = (try parseSrc(a, &d, &ds, &.{ 2, 3 }, "effect P = poly(w1 w2);")).body.polynomial;
    try t_.expectEqualSlices(usize, &.{ 4, 5 }, p.vars);
    try t_.expectEqual(@as(usize, 1), p.degree);
    try t_.expectEqual(@as(usize, 1), p.mdegree);
    try t_.expect(p.standardize == null and p.separate and !p.details and !p.expand and !p.include_name);
    try t_.expectEqualStrings("^", p.exponent);
    try t_.expectEqualStrings("*", p.product);
    const q = (try parseSrc(a, &d, &ds, &.{ 2, 3 }, "effect Q = polynomial(w1 / degree=3 standardize details);")).body.polynomial;
    try t_.expectEqual(@as(usize, 3), q.mdegree); // MDEGREE defaults to DEGREE
    try t_.expect(q.details);
    try t_.expectEqual(ec.Method.range, q.standardize.?.method);
    try t_.expectEqual(ec.Mode.centerscale, q.standardize.?.mode);
    try t_.expectEqualStrings("s_", q.standardize.?.prefix);
    const m = (try parseSrc(a, &d, &ds, &.{ 2, 3 }, "effect T = multimember(teacher1 teacher2);")).body.multimember;
    try t_.expectEqualSlices(usize, &.{ 2, 3 }, m.vars);
    try t_.expect(m.weights.len == 0 and !m.noeffect and !m.stdize and !m.details);
    try t_.expectEqual(@as(usize, 0), d.count());
}
