//! STAT-KRIGE2D-001 permanent tests: PROC KRIGE2D options, statement roles,
//! defaults, BY / ID, missing-value rules, loud gaps, and the ordinary
//! kriging kernel against hand mathematics. Data are invented (D-011).
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Library = @import("../exec.zig").Library;
const k2 = @import("krige2d.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const approx = std.testing.expectApproxEqAbs;
const nan = std.math.nan(f64);

fn num(v: f64) Value {
    return .{ .num = v };
}

fn put(a: A, lib: *Library, name: []const u8, cols: []const []const u8, rows: []const []const Value) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    for (cols) |c| _ = try ds.addColumn(c, if (c[0] == '$') .char else .num);
    for (rows) |r| try ds.appendRow(r);
    try lib.put(name, ds);
}

const Env = struct {
    arena: std.heap.ArenaAllocator,
    lib: Library = undefined,
    diags: diag.Diagnostics = undefined,
    fn init(self: *Env) !void {
        const a = self.arena.allocator();
        self.lib = Library.init(a);
        self.diags = diag.Diagnostics.init(a);
        // pts: four corners of a unit square plus one row with a missing z.
        try put(a, &self.lib, "pts", &.{ "g", "x", "y", "z", "lab" }, &.{
            &.{ num(1), num(0), num(0), num(1), num(1) },
            &.{ num(1), num(1), num(0), num(2), num(2) },
            &.{ num(1), num(0), num(1), num(3), num(3) },
            &.{ num(1), num(1), num(1), num(4), num(4) },
            &.{ num(2), num(0), num(0), num(5), num(5) },
            &.{ num(2), num(2), num(0), num(7), num(6) },
            &.{ num(2), num(1), num(1), num(nan), num(7) },
        });
    }
    fn cx(self: *Env) proc.ProcCtx {
        return .{ .arena = self.arena.allocator(), .lib = &self.lib, .diags = &self.diags };
    }
    fn toks(self: *Env, source: []const u8) ![]const lex.Token {
        return lex.tokenize(self.arena.allocator(), source, &self.diags);
    }
    fn parse(self: *Env, source: []const u8) !k2.Spec {
        return k2.parse(self.cx(), try self.toks(source));
    }
    fn run(self: *Env, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try k2.run(self.cx(), &out, try self.toks(source));
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

const base = " coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; run;";

test "STAT-KRIGE2D-001 defaults, aliases and explicit options" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    // p.5432: DATA= defaults to the last data set; MINPOINTS=20 and
    // SINGULARMSG=10 defaults (pp.5437, 5442), SINGULAR=1E-7 (p.5447).
    const d = try e.parse("proc krige2d;" ++ base);
    try expect(!d.noprint and d.outest == null and d.minpoints == 20 and d.maxpoints == null and d.singularmsg == 10);
    try expectEqual(@as(f64, 1e-7), d.model.singular);
    try expectEqual(@as(usize, 1), d.gx.len);
    // Aliases: OUTE=, SMSG=, COORD, XCOORD=(...), PRED, R=, MINP=, MAXP=, GAUSSIAN.
    const s = try e.parse("proc krige2d data=work.pts oute=o smsg=3 noprint idnum idglobal plots=none; coord xcoord=(x) ycoord=(y); pred var=z r=2.5 minp=2 maxp=3; model scale=2 range=1 form=gaussian nugget=0 singular=1e-9; grid x=0 to 1 by 0.5 y=0,1; id lab; run;");
    try expect(s.noprint and s.plots_none and std.mem.eql(u8, s.outest.?, "o") and s.singularmsg == 3);
    try expect(s.radius == 2.5 and s.minpoints == 2 and s.maxpoints.? == 3 and s.model.singular == 1e-9);
    try expectEqual(@as(usize, 3), s.gx.len);
    try approx(@as(f64, 0.5), s.gx[1], 1e-12);
    try expectEqual(@as(usize, 2), s.gy.len);
    try expect(s.id_col.? == 4);
    // GRID TO without BY steps by 1 (p.5439: x=1 to 5 equals 1,2,3,4,5).
    const r = try e.parse("proc krige2d data=pts; coordinates xc=x yc=y; p var=z radius=5; model scale=2 range=1 form=gau; grid x=1 to 5 y=-1; run;");
    try expectEqual(@as(usize, 5), r.gx.len);
    try expectEqual(@as(f64, -1), r.gy[0]);
}

test "STAT-KRIGE2D-001 invalid input is a user error" {
    const cases = [_]struct { src: []const u8, msg: []const u8 }{
        .{ .src = "proc krige2d data=nope;" ++ base, .msg = "not found" },
        .{ .src = "proc krige2d data=pts bogus;" ++ base, .msg = "invalid" },
        .{ .src = "proc krige2d data=pts; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; run;", .msg = "COORDINATES statement is required" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; run;", .msg = "both XC= and YC=" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; run;", .msg = "only one COORDINATES" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; run;", .msg = "requires VAR=" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; model scale=2 range=1 form=gau; predict var=z radius=5; grid x=0 y=0; run;", .msg = "must follow a PREDICT" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 form=gau; grid x=0 y=0; run;", .msg = "requires SCALE=, RANGE=" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=bogus; grid x=0 y=0; run;", .msg = "unknown FORM=" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5; model scale=-2 range=1 form=gau; grid x=0 y=0; run;", .msg = "must be positive" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0; run;", .msg = "both X= and Y=" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=gau; run;", .msg = "GRID statement is required" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5 minp=4 maxp=3; model scale=2 range=1 form=gau; grid x=0 y=0; run;", .msg = "smaller than MINPOINTS" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; id lab g; run;", .msg = "exactly one variable" },
        .{ .src = "proc krige2d data=pts; coordinates xc=x yc=y; predict var=q radius=5; model scale=2 range=1 form=gau; grid x=0 y=0; run;", .msg = "not found" },
    };
    for (cases) |c| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        diag.resetGap();
        try std.testing.expectError(error.ParseError, e.parse(c.src));
        try expect(has(e.lastError(), c.msg));
        try expect(!diag.gapHit());
    }
}

test "STAT-KRIGE2D-001 valid but unimplemented features are loud gaps" {
    const tail = " coordinates xc=x yc=y;";
    const cases = [_][]const u8{
        "proc krige2d data=pts outnbhd=n;" ++ base,
        "proc krige2d data=pts plots=pred;" ++ base,
        "proc krige2d data=pts;" ++ tail ++ " predict var=z; model scale=2 range=1 form=gau; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z numpoints=3; model scale=2 range=1 form=gau; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5 noincr; model scale=2 range=1 form=gau; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=sph; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau nugget=1; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau angle=30 ratio=0.5; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=(2,1) range=(1,1) form=(gau,gau); grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model mdata=m; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau; model scale=2 range=1 form=gau; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau; predict var=x radius=5; grid x=0 y=0; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0,1 y=0,1 npts=all; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau; grid gdata=gd xc=x yc=y; run;",
        "proc krige2d data=pts;" ++ tail ++ " predict var=z radius=5; model scale=2 range=1 form=gau; restore in=st; grid x=0 y=0; run;",
    };
    for (cases) |src| {
        var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
        defer e.arena.deinit();
        try e.init();
        diag.resetGap();
        try std.testing.expectError(error.ParseError, e.parse(src));
        try expect(diag.gapHit());
    }
}

test "STAT-KRIGE2D-001 ordinary kriging kernel matches hand mathematics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const m: k2.Model = .{ .scale = 2, .range = 1 };
    // One point: lambda = 1, variance = 2(C0 - C(h)) = 2*2*(1 - e^-1).
    const one = try k2.krige(a, m, &.{.{ .x = 0, .y = 0, .z = 5 }}, 1, 0);
    try approx(@as(f64, 5), one.estimate, 1e-12);
    try approx(@sqrt(4 * (1 - @exp(-1.0))), one.stderr, 1e-12);
    // Symmetric pair at (+-1, 0) predicting (0, 0): lambda = 1/2 each;
    // variance = C0 - 2C(1) + (C0 + C(2))/2.
    const two = try k2.krige(a, m, &.{ .{ .x = -1, .y = 0, .z = 1 }, .{ .x = 1, .y = 0, .z = 3 } }, 0, 0);
    try approx(@as(f64, 2), two.estimate, 1e-12);
    const c1: f64 = 2 * @exp(-1.0);
    const c2: f64 = 2 * @exp(-4.0);
    try approx(@sqrt(2 - 2 * c1 + (2 + c2) / 2), two.stderr, 1e-12);
    // Exact interpolation at a data point: estimate z, standard error 0.
    const at = try k2.krige(a, m, &.{ .{ .x = -1, .y = 0, .z = 1 }, .{ .x = 1, .y = 0, .z = 3 } }, 1, 0);
    try approx(@as(f64, 3), at.estimate, 1e-9);
    try approx(@as(f64, 0), at.stderr, 1e-6);
    // Duplicate locations make the system singular.
    const sing = try k2.krige(a, m, &.{ .{ .x = 0, .y = 0, .z = 1 }, .{ .x = 0, .y = 0, .z = 3 } }, 1, 0);
    try expect(sing.singular);
}

test "STAT-KRIGE2D-001 neighbourhood radius, MINPOINTS and MAXPOINTS" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const pts = [_]k2.Point{ .{ .x = 3, .y = 0, .z = 0 }, .{ .x = 1, .y = 0, .z = 0 }, .{ .x = 2, .y = 0, .z = 0 }, .{ .x = 9, .y = 0, .z = 0 } };
    var s: k2.Spec = .{ .input = undefined, .radius = 2.5, .minpoints = 1 };
    try expectEqual(@as(usize, 2), (try k2.neighbours(a, s, &pts, 0, 0)).pts.len);
    s.minpoints = 3; // radius incremented to the third nearest
    const n3 = try k2.neighbours(a, s, &pts, 0, 0);
    try expectEqual(@as(usize, 3), n3.pts.len);
    try expectEqual(@as(f64, 3), n3.pts[2].x);
    try expect(n3.incremented and !n3.decremented and n3.radius == 3);
    s.minpoints = 20; // fewer points than MINPOINTS: all of them
    try expectEqual(@as(usize, 4), (try k2.neighbours(a, s, &pts, 0, 0)).pts.len);
    s.minpoints = 1;
    s.radius = 100;
    s.maxpoints = 2; // radius decremented to the two nearest
    const n2 = try k2.neighbours(a, s, &pts, 0, 0);
    try expectEqual(@as(usize, 2), n2.pts.len);
    try expectEqual(@as(f64, 1), n2.pts[0].x);
    try expect(n2.decremented and !n2.incremented and n2.radius == 2);
}

test "STAT-KRIGE2D-001 BY groups, missing values and OUTEST= rows" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const text = try e.run("proc krige2d data=pts outest=est; coordinates xc=x yc=y; predict var=z radius=5 minp=1; model scale=2 range=1 form=gau; grid x=0.5 y=0.5; by g; run;");
    // Group 1: four corners; group 2: three read, one missing z excluded.
    try expect(has(text, "g=1"));
    try expect(has(text, "g=2"));
    try expect(has(text, "Number of Observations Read           3"));
    try expect(has(text, "Number of Observations Used           2"));
    try expect(has(text, "Effective Range    1.7320508"));
    const o = e.lib.find("est").?;
    try expectEqual(@as(usize, 2), o.rows.items.len);
    try expectEqual(@as(usize, 8), o.columns.items.len);
    // Reference run (SAS 9.4): LABEL $12, VARNAME as long as the VAR= name,
    // these labels, and the BY variable after STDERR.
    try expectEqual(@as(?usize, 7), o.indexOf("g"));
    try expectEqual(@as(?usize, 0), o.indexOf("LABEL"));
    try expectEqual(@as(?usize, 6), o.indexOf("STDERR"));
    try expectEqual(@as(?usize, 12), o.columns.items[0].len);
    try expectEqual(@as(?usize, 1), o.columns.items[1].len);
    try expect(std.mem.eql(u8, o.columns.items[5].label.?, "Kriging Estimate"));
    try expect(std.mem.eql(u8, o.rows.items[0][0].str, "Pred1.Model1"));
    // One warning counts the missing VAR= values (reference run wording).
    var warned = false;
    for (e.diags.list.items) |m| if (has(m.message, "The VAR= variable z, found in one or more PREDICT statements, contains 1 missing value(s).")) {
        warned = true;
    };
    try expect(warned);
    // Group 1: the centre of a square is equidistant from the corners, so
    // lambda = 1/4 each and the estimate is the mean (1+2+3+4)/4.
    try approx(@as(f64, 2.5), o.rows.items[0][o.indexOf("ESTIMATE").?].num, 1e-9);
    try expectEqual(@as(f64, 4), o.rows.items[0][o.indexOf("NPOINTS").?].num);
    // Group 2: two points symmetric about (0.5, 0.5)? (0,0) and (2,0) are
    // not; distances sqrt(0.5) and sqrt(2.5). Only the count is checked.
    try expectEqual(@as(f64, 2), o.rows.items[1][o.indexOf("NPOINTS").?].num);
    // NOPRINT prints nothing but still writes OUTEST=.
    const quiet = try e.run("proc krige2d data=pts outest=q noprint; coordinates xc=x yc=y; predict var=z radius=5; model scale=2 range=1 form=gau; grid x=0,1 y=0; run;");
    try expectEqual(@as(usize, 0), quiet.len);
    try expectEqual(@as(usize, 2), e.lib.find("q").?.rows.items.len);
}
