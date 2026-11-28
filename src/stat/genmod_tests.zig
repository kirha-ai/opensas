//! STAT-GENMOD-001 permanent tests: PROC statement options, roles, observation
//! selection, BY boundaries, CLASS level order and loud execution boundaries.
//! Data are invented (D-011). Expected counts are hand-derived in comments.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const by = @import("by_groups.zig");
const genmod = @import("genmod.zig");
const A = std.mem.Allocator;
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

const nan = std.math.nan(f64);
const Row = struct { g: f64, c: []const u8, x: f64, y: f64, f: f64, w: f64 };
// row: reason it can drop out
const sample = [_]Row{
    .{ .g = 1, .c = "b", .x = 0, .y = 5, .f = 2.9, .w = 1 }, // 0: FREQ truncates to 2
    .{ .g = 1, .c = "a", .x = 1, .y = 7, .f = 1, .w = 2 }, // 1
    .{ .g = 1, .c = "b", .x = 2, .y = nan, .f = 1, .w = 1 }, // 2: missing response
    .{ .g = 1, .c = "a", .x = nan, .y = 9, .f = 1, .w = 1 }, // 3: missing effect
    .{ .g = 1, .c = "", .x = 3, .y = 11, .f = 1, .w = 1 }, // 4: missing CLASS
    .{ .g = 1, .c = "a", .x = 4, .y = 13, .f = 0.9, .w = 1 }, // 5: FREQ < 1
    .{ .g = 1, .c = "a", .x = 5, .y = 15, .f = nan, .w = 1 }, // 6: FREQ missing
    .{ .g = 1, .c = "b", .x = 6, .y = 17, .f = 1, .w = 0 }, // 7: WEIGHT = 0
    .{ .g = 1, .c = "a", .x = 7, .y = 19, .f = 1, .w = nan }, // 8: WEIGHT missing
    .{ .g = 2, .c = "c", .x = 1, .y = 2, .f = 3, .w = 0.5 }, // 9
    .{ .g = 2, .c = "a", .x = 2, .y = 4, .f = 1, .w = 1.5 }, // 10
};

fn fixture(a: A, lib: *Library, name: []const u8, rows: []const Row) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, name);
    _ = try ds.addColumn("g", .num);
    _ = try ds.addColumn("c", .char);
    for ([_][]const u8{ "x", "y", "f", "w" }) |n| _ = try ds.addColumn(n, .num);
    for (rows) |r| try ds.appendRow(&.{ .{ .num = r.g }, .{ .str = r.c }, .{ .num = r.x }, .{ .num = r.y }, .{ .num = r.f }, .{ .num = r.w } });
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
    fn parse(self: *Env, source: []const u8) !genmod.Spec {
        return genmod.parse(self.cx(), try lex.tokenize(self.arena.allocator(), source, &self.diags));
    }
};

test "STAT-GENMOD-001 PROC statement defaults and explicit options" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const d = try e.parse("proc genmod; model y = x; run;");
    try expect(!d.descending and !d.exact_only and !d.exact);
    try expectEqual(@as(usize, 20), d.namelen);
    try expectEqual(.formatted, d.order);
    try expectEqual(.formatted, d.rorder);
    try expect(d.frequency == null and d.weight == null and d.trials == null);
    try expect(d.dist == null and d.link == null);
    try expectEqual(@as(usize, 0), d.by_cols.len + d.class.len + d.strata.len + d.later.len);
    try expectEqual(@as(usize, 3), d.response); // y
    try std.testing.expectEqualSlices(usize, &.{2}, d.effects); // x
    try expectEqual(e.ds, d.input.ds); // DATA= omitted: most recently created data set

    const s = try e.parse("proc genmod data=work.sample desc exactonly namelen=200 order=data rorder=freq; class c g; model y = x c g / dist = normal link = log type3; freq f; weight w; by g; run;");
    try expect(s.descending and s.exact_only);
    try expectEqual(@as(usize, 200), s.namelen);
    try expectEqual(.data, s.order);
    try expectEqual(.freq, s.rorder);
    try std.testing.expectEqualSlices(usize, &.{ 1, 0 }, s.class);
    try std.testing.expectEqualSlices(usize, &.{ 2, 1, 0 }, s.effects);
    try std.testing.expectEqualStrings("normal", s.dist.?);
    try std.testing.expectEqualStrings("log", s.link.?);
    try expectEqual(@as(usize, 1), s.model_options.len);
    try std.testing.expectEqualStrings("type3", s.model_options[0]);
    try expectEqual(@as(?usize, 4), s.frequency);
    try expectEqual(@as(?usize, 5), s.weight);
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);

    // Aliases: DESCEND/DESCENDING, FREQUENCY, SCWGT, ORDER= keywords, NAMELEN bounds.
    const alias = try e.parse("proc genmod descend namelen=20 order=internal rorder=formatted; model y/f = x; frequency f; scwgt w; run;");
    try expect(alias.descending);
    try expectEqual(.internal, alias.order);
    try expectEqual(@as(?usize, 4), alias.trials);
    try expectEqual(@as(?usize, 4), alias.frequency);
    try expectEqual(@as(?usize, 5), alias.weight);
    try expect((try e.parse("proc genmod descending order=freq; model y = ; run;")).effects.len == 0);
}

test "STAT-GENMOD-001 BY last statement wins and STRATA statements accumulate" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const s = try e.parse("proc genmod; by descending x; model y = x; by g; run;");
    try std.testing.expectEqualSlices(usize, &.{0}, s.by_cols);
    try std.testing.expectEqualSlices(bool, &.{false}, s.by_desc);
    const groups = try by.checkedSlices(e.arena.allocator(), e.ds, s.by_cols, s.by_desc, s.notsorted, &e.diags);
    try expectEqual(@as(usize, 2), groups.len);
    try expectEqual(@as(usize, 9), groups[0].rows.len);
    try expectEqual(@as(usize, 2), groups[1].rows.len);
    try expect((try e.parse("proc genmod; by g notsorted; model y = x; run;")).notsorted);

    const st = try e.parse("proc genmod; class c; model y = x; exact x; strata g; strata c(missing) g / check=all nosummary info; run;");
    try expectEqual(@as(usize, 2), st.strata.len);
    try expectEqual(@as(usize, 0), st.strata[0].column);
    try expect(!st.strata[0].missing);
    try expectEqual(@as(usize, 1), st.strata[1].column);
    try expect(st.strata[1].missing);
    try expectEqual(.all, st.strata_check);
    try expect(st.strata_nosummary and st.strata_info and st.exact);
    const global = try e.parse("proc genmod; model y = x; exact x; strata g c / missing; run;");
    try expect(global.strata[0].missing and global.strata[1].missing);
    try expectEqual(.covariates, global.strata_check);
    try expect(!global.strata_nosummary and !global.strata_info);
}

test "STAT-GENMOD-001 observation selection: missing values, FREQ truncation, WEIGHT, BY boundaries" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const a = e.arena.allocator();
    const g1 = e.ds.rows.items[0..9];
    const g2 = e.ds.rows.items[9..11];

    // No FREQ/WEIGHT/CLASS: only rows 2 (y) and 3 (x) are missing.
    const plain = try genmod.prepare(e.cx(), try e.parse("proc genmod; model y = x; run;"), g1);
    try expectEqual(@as(usize, 9), plain.read);
    try expectEqual(@as(usize, 7), plain.used);
    try expectEqual(@as(usize, 2), plain.missing);
    try expectEqual(@as(f64, 9), plain.frequency_read);
    try expectEqual(@as(f64, 7), plain.frequency_used);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 4, 5, 6, 7, 8 }, plain.rows);
    try expectEqual(@as(usize, 0), plain.bad_frequency + plain.bad_weight);

    // A CLASS variable that is not in the MODEL still removes its missing row 4.
    const with_class = try genmod.prepare(e.cx(), try e.parse("proc genmod; class c; model y = x; run;"), g1);
    try expectEqual(@as(usize, 6), with_class.used);
    try expectEqual(@as(usize, 3), with_class.missing);

    // FREQ: 2.9 -> 2; 0.9 and missing drop. Read total 2+1+1+1+1+0+0+1+1 = 8.
    const fr = try genmod.prepare(e.cx(), try e.parse("proc genmod; class c; model y = x c; freq f; run;"), g1);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 7, 8 }, fr.rows);
    try std.testing.expectEqualSlices(f64, &.{ 2, 1, 1, 1 }, fr.frequency);
    try expectEqual(@as(usize, 2), fr.bad_frequency);
    try expectEqual(@as(f64, 8), fr.frequency_read);
    try expectEqual(@as(f64, 5), fr.frequency_used);

    // WEIGHT: 0 and missing drop; values are not truncated or rescaled.
    const both = try genmod.prepare(e.cx(), try e.parse("proc genmod; class c; model y = x c; freq f; weight w; run;"), g1);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, both.rows);
    try std.testing.expectEqualSlices(f64, &.{ 1, 2 }, both.weight);
    try expectEqual(@as(usize, 2), both.bad_weight);
    try expectEqual(@as(f64, 3), both.frequency_used);
    const second = try genmod.prepare(e.cx(), try e.parse("proc genmod; class c; model y = x c; freq f; weight w; by g; run;"), g2);
    try expectEqual(@as(usize, 2), second.read);
    try expectEqual(@as(usize, 2), second.used);
    try std.testing.expectEqualSlices(f64, &.{ 3, 1 }, second.frequency);
    try std.testing.expectEqualSlices(f64, &.{ 0.5, 1.5 }, second.weight);
    // Levels are per BY group: group 2 has a and c, never group 1's b.
    try expectEqual(@as(usize, 2), second.levels[0].levels.len);
    try std.testing.expectEqualStrings("a", second.levels[0].levels[0].label);
    try std.testing.expectEqualStrings("c", second.levels[0].levels[1].label);

    // STRATA: a missing stratum value drops the row unless MISSING is given.
    const strata = try genmod.prepare(e.cx(), try e.parse("proc genmod; model y = x; exact x; strata c; run;"), g1);
    try expectEqual(@as(usize, 6), strata.used);
    const strata_missing = try genmod.prepare(e.cx(), try e.parse("proc genmod; model y = x; exact x; strata c(missing); run;"), g1);
    try expectEqual(@as(usize, 7), strata_missing.used);

    // Empty input: one empty group without BY, no groups with BY.
    var lib2 = Library.init(a);
    const empty = try fixture(a, &lib2, "none", &.{});
    const cx2: proc.ProcCtx = .{ .arena = a, .lib = &lib2, .diags = &e.diags };
    const es = try genmod.parse(cx2, try lex.tokenize(a, "proc genmod data=none; class c; model y = x c; freq f; weight w; by g; run;", &e.diags));
    const zero = try genmod.prepare(cx2, es, empty.rows.items);
    try expectEqual(@as(usize, 0), zero.read + zero.used + zero.missing);
    try expectEqual(@as(usize, 0), zero.levels[0].levels.len);
    try expectEqual(@as(usize, 0), (try by.checkedSlices(a, empty, es.by_cols, es.by_desc, es.notsorted, &e.diags)).len);
    try expectEqual(@as(usize, 1), (try by.checkedSlices(a, empty, &.{}, &.{}, false, &e.diags)).len);
    // Every observation unusable is still a well-defined selection.
    const none_used = try genmod.prepare(e.cx(), try e.parse("proc genmod; model y = x; freq f; run;"), e.ds.rows.items[5..7]);
    try expectEqual(@as(usize, 2), none_used.read);
    try expectEqual(@as(usize, 0), none_used.used);
}

test "STAT-GENMOD-001 CLASS level order follows ORDER= over used observations" {
    var e: Env = .{ .arena = std.heap.ArenaAllocator.init(std.testing.allocator) };
    defer e.arena.deinit();
    try e.init();
    const g1 = e.ds.rows.items[0..9];
    // Used rows with FREQ f: 0 (b, 2), 1 (a, 1), 7 (b, 1), 8 (a, 1).
    const cases = [_]struct { source: []const u8, first: []const u8, second: []const u8 }{
        .{ .source = "proc genmod; class c; model y = x c; freq f; run;", .first = "a", .second = "b" },
        .{ .source = "proc genmod order=internal; class c; model y = x c; freq f; run;", .first = "a", .second = "b" },
        .{ .source = "proc genmod order=data; class c; model y = x c; freq f; run;", .first = "b", .second = "a" },
        .{ .source = "proc genmod order=freq; class c; model y = x c; freq f; run;", .first = "b", .second = "a" }, // b: 3, a: 2
    };
    for (cases) |case| {
        const sel = try genmod.prepare(e.cx(), try e.parse(case.source), g1);
        try expectEqual(@as(usize, 2), sel.levels[0].levels.len);
        try std.testing.expectEqualStrings(case.first, sel.levels[0].levels[0].label);
        try std.testing.expectEqualStrings(case.second, sel.levels[0].levels[1].label);
    }
    const sel = try genmod.prepare(e.cx(), try e.parse(cases[3].source), g1);
    try expectEqual(@as(f64, 3), sel.levels[0].levels[0].frequency);
    try expectEqual(@as(f64, 2), sel.levels[0].levels[1].frequency);
}

test "STAT-GENMOD-001 invalid declarations are user errors and valid unimplemented features are loud gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try fixture(a, &lib, "sample", &sample);
    const Case = struct { source: []const u8, rc: u8 };
    const cases = [_]Case{
        // rc 1: invalid SAS.
        .{ .source = "proc genmod; run;", .rc = 1 }, // no MODEL
        .{ .source = "proc genmod noprint; model y = x; run;", .rc = 1 }, // NOPRINT is not available
        .{ .source = "proc genmod namelen=19; model y = x; run;", .rc = 1 },
        .{ .source = "proc genmod namelen=201; model y = x; run;", .rc = 1 },
        .{ .source = "proc genmod order=random; model y = x; run;", .rc = 1 },
        .{ .source = "proc genmod rorder=; model y = x; run;", .rc = 1 },
        .{ .source = "proc genmod data=absent; model y = x; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = nothere; run;", .rc = 1 },
        .{ .source = "proc genmod; model nothere = x; run;", .rc = 1 },
        .{ .source = "proc genmod; model y x; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = c; run;", .rc = 1 }, // character effect needs CLASS
        .{ .source = "proc genmod; model y = x; class c; run;", .rc = 1 }, // CLASS after MODEL
        .{ .source = "proc genmod; class nothere; model y = x; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; freq c; run;", .rc = 1 }, // character FREQ
        .{ .source = "proc genmod; model y = x; freq f w; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; freq; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; weight c; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; weight nothere; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; by nothere; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; by descending g; run;", .rc = 1 }, // g ascends: not sorted descending
        .{ .source = "proc genmod; model y = x; strata g; run;", .rc = 1 }, // STRATA needs EXACT
        .{ .source = "proc genmod; model y = x; exact x; strata; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; exact x; strata g / check=some; run;", .rc = 1 },
        .{ .source = "proc genmod; model y = x; exact x; strata g; output out=o; run;", .rc = 1 }, // not available with STRATA
        .{ .source = "proc genmod; model y = x; frobnicate x; run;", .rc = 1 },
        // rc 2: valid SAS that is not implemented, or an undocumented repeat.
        .{ .source = "proc genmod; model y = x / dist=poisson; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x / dist=normal link=power; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x / dist=normal link=log type3; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x / offset=f; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model y = x c; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; freq f; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; weight w; run;", .rc = 2 },
        .{ .source = "proc genmod; model y/f = x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = g; by g; run;", .rc = 2 }, // constant regressor within a BY group
        .{ .source = "proc genmod; model y = x; lsmeans x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; estimate 'a' x 1; run;", .rc = 2 },
        .{ .source = "proc genmod data=sample; by g; class c; model y = x c / dist=normal link=log; freq f; weight w; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x / dist=normal link=log; output out=r pred=p; run;", .rc = 2 },
        .{ .source = "proc genmod plots=all; model y = x; run;", .rc = 2 },
        .{ .source = "proc genmod exactonly; model y = x; exact x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; exact x; strata g; run;", .rc = 2 },
        .{ .source = "proc genmod; class c; model y = x*c; run;", .rc = 2 },
        .{ .source = "proc genmod; class c(ref='a'); model y = x; run;", .rc = 2 },
        .{ .source = "proc genmod; class c / param=ref; model y = x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x / link=power(2); run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; repeated subject=g; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; bayes; run;", .rc = 2 },
        .{ .source = "proc genmod order=data order=freq; model y = x; run;", .rc = 2 },
        .{ .source = "proc genmod desc descending; model y = x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; model y = x; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; freq f; freq f; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x; weight w; scwgt w; run;", .rc = 2 },
        .{ .source = "proc genmod; model y = x / dist=normal d=poisson; run;", .rc = 2 },
    };
    for (cases) |case| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const result = genmod.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, case.source, &d));
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

test "STAT-GENMOD-002 default Normal step runs, prints every table once and reports its notes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try fixture(a, &lib, "sample", &sample);
    diag.resetGap();
    defer diag.resetGap();
    var d = diag.Diagnostics.init(a);
    var output: std.ArrayList(u8) = .empty;
    // No DIST=/LINK=: Normal with the identity link. Rows 2 and 3 are missing
    // on y or x; FREQ/WEIGHT/CLASS are not declared, so 9 of 11 rows are used.
    try genmod.run(.{ .arena = a, .lib = &lib, .diags = &d }, &output, try lex.tokenize(a, "proc genmod data=sample; model y = x; run;", &d));
    try expectEqual(@as(u8, 0), diag.exitCode(diag.gapHit(), d.hasErrors()));
    for ([_][]const u8{
        "The GENMOD Procedure",
        "Data Set              WORK.SAMPLE",
        "Distribution               Normal",
        "Link Function            Identity",
        "Dependent Variable              y",
        "Number of Observations Read          11",
        "Number of Observations Used           9",
        "Criteria For Assessing Goodness Of Fit",
        "Algorithm converged.",
        "Analysis Of Maximum Likelihood Parameter Estimates",
        "NOTE: The scale parameter was estimated by maximum likelihood.",
    }) |needle| {
        expectEqual(@as(usize, 1), std.mem.count(u8, output.items, needle)) catch |err| {
            std.debug.print("missing or repeated: {s}\n{s}\n", .{ needle, output.items });
            return err;
        };
    }
}
