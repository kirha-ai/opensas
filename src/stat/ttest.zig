//! TTEST input roles, group selection and execution. Numerical work belongs to
//! ttest_fit.zig; parsing and listing have independent modules.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Value = @import("../value.zig").Value;
const format = @import("../format.zig");
const selection = @import("data_selection.zig");
const by = @import("by_groups.zig");
pub const declarations = @import("ttest_parse.zig");
const fit = @import("ttest_fit.zig");
const lognormal = @import("ttest_lognormal.zig");
const render = @import("ttest_render.zig");
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;

pub const Class = struct { label: []const u8, raw: Value, count: f64 = 0 };
pub const Analysis = struct {
    pair: ?declarations.Pair = null,
    column: usize,
    classes: []const Class,
    /// Normal results, or the underlying log-scale results when lognormal_samples is present.
    samples: []const fit.Result,
    lognormal_samples: ?[]const lognormal.Result = null,
};
pub const Group = struct { representative: ?[]const Value, analyses: []const Analysis };
pub const Result = struct { spec: declarations.Spec, groups: []const Group };

fn numericOptions(o: declarations.Options) fit.Options {
    return .{ .alpha = o.alpha, .h0 = o.h0, .sides = switch (o.sides) {
        .two => .two_sided,
        .lower => .lower,
        .upper => .upper,
    } };
}
fn display(a: A, s: declarations.Spec, row: []const Value) ![]const u8 {
    const ci = s.class.?;
    const info = s.input.ds.columns.items[ci];
    return std.mem.trim(u8, if (info.format) |f| try format.apply(a, row[ci], f) else try proc.cellText(a, row[ci]), " ");
}
fn orderClasses(s: declarations.Spec, a: Class, b: Class) bool {
    var order = s.options.order;
    if (order == .freq) {
        if (a.count != b.count) return a.count > b.count;
        order = .mixed;
    }
    const info = s.input.ds.columns.items[s.class.?];
    if (order == .mixed) order = if (info.type == .char) .formatted else .internal;
    if (order == .formatted and !(info.type == .num and info.format == null)) return std.mem.order(u8, a.label, b.label) == .lt;
    return proc.cmpValue(a.raw, b.raw) == .lt;
}

/// Formatted class levels are determined before per-analysis missing exclusion.
/// FREQ contributes replicated observations to ORDER=FREQ; WEIGHT never does.
pub fn classes(cx: proc.ProcCtx, s: declarations.Spec, view: selection.View) diag.Error![]const Class {
    if (s.class == null) return &.{};
    var result: std.ArrayList(Class) = .empty;
    const filtered = try view.select(cx.arena, .{ .missing_columns = &.{s.class.?}, .frequency = .truncate_positive, .weight = .positive_only });
    for (filtered.observations) |row| {
        const label = try display(cx.arena, s, row.cells);
        const count = if (s.summary) |kind| blk: {
            if (!eq(std.mem.trim(u8, row.cells[kind].str, " "), "N")) break :blk @as(f64, 0);
            // A summary record represents N observations, not one observation.
            break :blk row.cells[s.roles.analysis[0]].num;
        } else row.frequency.num;
        var found = false;
        for (result.items) |*c| if (std.mem.eql(u8, c.label, label)) {
            c.count += count;
            found = true;
            break;
        };
        if (!found) try result.append(cx.arena, .{ .label = label, .raw = row.cells[s.class.?], .count = count });
    }
    if (result.items.len != 2) return cx.diags.fail(error.ParseError, s.line, "PROC TTEST: CLASS variable must have exactly two nonmissing levels", .{});
    if (s.options.order != .data) std.mem.sort(Class, result.items, s, orderClasses);
    return result.items;
}

fn sample(cx: proc.ProcCtx, s: declarations.Spec, view: selection.View, ci: usize, level: ?Class, geometric: ?*lognormal.Result, pair: ?declarations.Pair) diag.Error!fit.Result {
    const a = cx.arena;
    const opts = numericOptions(s.options);
    if (s.summary) |kind| {
        var n: ?f64 = null;
        var mean: ?f64 = null;
        var sd: ?f64 = null;
        for (view.observations) |row| {
            if (level) |c| {
                if (selection.missing(row.cells[s.class.?]) or !std.mem.eql(u8, c.label, try display(a, s, row.cells))) continue;
            }
            const name = std.mem.trim(u8, row.cells[kind].str, " ");
            const target: ?*?f64 = if (eq(name, "n")) &n else if (eq(name, "mean")) &mean else if (eq(name, "std")) &sd else null;
            if (target) |p| {
                if (p.* != null) return cx.diags.fail(error.ParseError, s.line, "PROC TTEST: duplicate {s} summary statistic", .{name});
                p.* = row.cells[ci].num;
            }
        }
        if (n == null or mean == null or sd == null) return cx.diags.fail(error.ParseError, s.line, "PROC TTEST: summary input requires N, MEAN and STD for every variable and group", .{});
        const count = n.?;
        const max_n: f64 = @floatFromInt(@min(std.math.maxInt(usize), 9007199254740991));
        if (!std.math.isFinite(count) or count < 1 or @trunc(count) != count or count > max_n) return cx.diags.fail(error.ParseError, s.line, "PROC TTEST: summary N must be a positive integer", .{});
        return fit.fromSummary(@intFromFloat(count), mean.?, sd.?, opts) catch |err| return numericFailure(cx, s, err);
    }
    const missing = if (pair) |p| try a.dupe(usize, &.{ p.left, p.right }) else if (s.class) |c| try a.dupe(usize, &.{ ci, c }) else try a.dupe(usize, &.{ci});
    const selected = try view.select(a, .{ .missing_columns = missing, .frequency = .truncate_positive, .weight = .positive_only });
    var values: std.ArrayList(f64) = .empty;
    var frequencies: std.ArrayList(f64) = .empty;
    var weights: std.ArrayList(f64) = .empty;
    for (selected.observations) |row| {
        if (level) |c| if (!std.mem.eql(u8, c.label, try display(a, s, row.cells))) continue;
        const value = if (pair) |p| row.cells[p.left].num - row.cells[p.right].num else row.cells[ci].num;
        try values.append(a, value);
        try frequencies.append(a, row.frequency.num);
        try weights.append(a, row.weight.num);
    }
    if (geometric) |destination| {
        destination.* = try lognormal.oneSample(a, values.items, frequencies.items, weights.items, lognormalOptions(s), cx.diags);
        return destination.log_fit;
    }
    if (values.items.len == 0) return cx.diags.fail(error.ParseError, s.line, "PROC TTEST: no usable observations for variable {s}", .{s.input.ds.columns.items[ci].name});
    return fit.oneSample(values.items, frequencies.items, weights.items, opts) catch |err| return numericFailure(cx, s, err);
}
fn lognormalOptions(s: declarations.Spec) lognormal.Options {
    const o = numericOptions(s.options);
    return .{ .h0 = o.h0, .alpha = o.alpha, .sides = o.sides, .line = s.line };
}
fn numericFailure(cx: proc.ProcCtx, s: declarations.Spec, err: diag.Error) diag.Error {
    if (err == error.OutOfMemory) return err;
    return cx.diags.fail(error.ExecError, s.line, "PROC TTEST: invalid summary statistics or nonfinite numerical result", .{});
}

pub fn compute(cx: proc.ProcCtx, s: declarations.Spec) diag.Error!Result {
    const view = try selection.View.init(cx.arena, s.input, s.roles);
    const slices = try view.groups(cx.arena, s.by_desc, s.notsorted, cx.diags);
    var results: std.ArrayList(Group) = .empty;
    for (slices) |group| {
        if (group.observations.len == 0) continue;
        const levels = try classes(cx, s, group);
        var analyses: std.ArrayList(Analysis) = .empty;
        if (s.paired) {
            for (s.pairs) |pair| {
                const samples = try cx.arena.alloc(fit.Result, 1);
                samples[0] = try sample(cx, s, group, pair.left, null, null, pair);
                try analyses.append(cx.arena, .{ .pair = pair, .column = pair.left, .classes = &.{}, .samples = samples });
            }
        } else for (s.roles.analysis) |ci| {
            const samples = try cx.arena.alloc(fit.Result, if (s.class != null) 2 else 1);
            const geometric = if (s.options.distribution == .lognormal) try cx.arena.alloc(lognormal.Result, samples.len) else null;
            for (samples, 0..) |*r, i| r.* = try sample(cx, s, group, ci, if (s.class != null) levels[i] else null, if (geometric) |gs| &gs[i] else null, null);
            try analyses.append(cx.arena, .{ .column = ci, .classes = levels, .samples = samples, .lognormal_samples = geometric });
        }
        try results.append(cx.arena, .{ .representative = group.observations[0].cells, .analyses = analyses.items });
    }
    if (results.items.len == 0) return cx.diags.fail(error.ParseError, s.line, "PROC TTEST: no observations in input data set", .{});
    return .{ .spec = s, .groups = results.items };
}
fn rendered(r: fit.Result) render.Sample {
    return .{ .n = @floatFromInt(r.n), .mean = r.mean, .stddev = r.std_dev, .stderr = r.std_err, .minimum = r.minimum, .maximum = r.maximum, .df = r.df, .t = r.t, .p = r.p, .lower = r.mean_ci.lower, .upper = r.mean_ci.upper, .std_lower = r.std_dev_ci.lower, .std_upper = r.std_dev_ci.upper };
}

pub fn runTtest(cx: proc.ProcCtx, out: *std.ArrayList(u8), toks: []const lex.Token) diag.Error!void {
    const spec = try declarations.parse(cx, toks);
    if (!spec.options.plots_none and spec.summary == null) if (cx.graphics) |g| {
        if (g.enabled == true or (g.enabled != false and g.cli_dir != null)) return proc.failGap(cx.diags, spec.line, "PROC TTEST: ODS graphics are not implemented", .{});
    };
    // Do not print a one-sample table for a requested two-sample analysis.
    // The selection and summary interfaces above are already shared by both.
    const result = try compute(cx, spec);
    if (spec.class != null and spec.options.distribution == .lognormal) return proc.failGap(cx.diags, spec.line, "PROC TTEST: lognormal two-sample inference is not implemented", .{});
    const a = cx.arena;
    for (result.groups) |group| {
        var body: std.ArrayList(u8) = .empty;
        for (group.analyses) |analysis| {
            var tables: std.ArrayList(u8) = .empty;
            if (spec.class) |class_column| {
                const two = @import("ttest_two_sample.zig");
                const base = numericOptions(spec.options);
                const pair = two.compute(analysis.samples[0], analysis.samples[1], .{
                    .h0 = base.h0,
                    .alpha = base.alpha,
                    .sides = base.sides,
                    .cochran = spec.options.cochran,
                }) catch |err| return numericFailure(cx, spec, err);
                const labels: [2][]const u8 = .{ analysis.classes[0].label, analysis.classes[1].label };
                const class_name = spec.input.ds.columns.items[class_column].name;
                const objects: @import("../ods_listing.zig").Tables = .{ .selection = cx.listing, .prefix = "Ttest" };
                var start = tables.items.len;
                try two.statistics(a, &tables, pair, class_name, labels, spec.summary != null);
                try objects.finish(a, &tables, start, "Statistics");
                start = tables.items.len;
                try two.intervals(a, &tables, pair, class_name, labels, spec.options.ci);
                try objects.finish(a, &tables, start, "ConfLimits");
                start = tables.items.len;
                if (spec.options.tost) |bounds| {
                    const tost = @import("ttest_tost.zig");
                    const rows = [_]tost.Row{
                        .{ .label = "Diff (1-2)", .method = "Pooled", .variances = "Equal", .result = tost.evaluate(pair.pooled.estimate, pair.pooled.std_err, pair.pooled.df, bounds, spec.options.alpha, .difference) catch |err| return numericFailure(cx, spec, err) },
                        .{ .label = "Diff (1-2)", .method = "Satterthwaite", .variances = "Unequal", .result = tost.evaluate(pair.satterthwaite.estimate, pair.satterthwaite.std_err, pair.satterthwaite.df, bounds, spec.options.alpha, .difference) catch |err| return numericFailure(cx, spec, err) },
                    };
                    try tost.renderAssessment(a, &tables, &rows, class_name);
                    try objects.finish(a, &tables, start, "EquivLimits");
                    start = tables.items.len;
                    try tost.renderTests(a, &tables, &rows, class_name);
                    try objects.finish(a, &tables, start, "EquivTests");
                } else {
                    try two.tests(a, &tables, pair);
                    try objects.finish(a, &tables, start, "TTests");
                }
                start = tables.items.len;
                try two.equalityTable(a, &tables, pair);
                try objects.finish(a, &tables, start, "Equality");
            } else if (analysis.lognormal_samples) |gs| {
                if (spec.options.tost) |bounds| {
                    const tost = @import("ttest_tost.zig");
                    const s = gs[0].log_fit;
                    const rows = [_]tost.Row{.{ .result = tost.evaluate(s.mean, s.std_err, s.df, bounds, spec.options.alpha, .log_ratio) catch |err| return numericFailure(cx, spec, err) }};
                    const objects: @import("../ods_listing.zig").Tables = .{ .selection = cx.listing, .prefix = "Ttest" };
                    var start = tables.items.len;
                    try tost.renderLognormalStatistics(a, &tables, gs[0]);
                    try objects.finish(a, &tables, start, "Statistics");
                    start = tables.items.len;
                    try tost.renderLognormalIntervals(a, &tables, gs[0], spec.options.alpha, spec.options.ci);
                    try objects.finish(a, &tables, start, "ConfLimits");
                    start = tables.items.len;
                    try tost.renderAssessment(a, &tables, &rows, null);
                    try objects.finish(a, &tables, start, "EquivLimits");
                    start = tables.items.len;
                    try tost.renderTests(a, &tables, &rows, null);
                    try objects.finish(a, &tables, start, "EquivTests");
                } else {
                    try lognormal.render(a, &tables, gs[0], lognormalOptions(spec), spec.options.ci);
                }
            } else {
                const r = rendered(analysis.samples[0]);
                const objects: @import("../ods_listing.zig").Tables = .{ .selection = cx.listing, .prefix = "Ttest" };
                var start = tables.items.len;
                try render.statistics(a, &tables, r, spec.summary != null);
                try objects.finish(a, &tables, start, "Statistics");
                start = tables.items.len;
                try render.intervals(a, &tables, r, spec.options);
                try objects.finish(a, &tables, start, "ConfLimits");
                start = tables.items.len;
                if (spec.options.tost) |bounds| {
                    const tost = @import("ttest_tost.zig");
                    const s = analysis.samples[0];
                    const rows = [_]tost.Row{.{ .result = tost.evaluate(s.mean, s.std_err, s.df, bounds, spec.options.alpha, .difference) catch |err| return numericFailure(cx, spec, err) }};
                    try tost.renderAssessment(a, &tables, &rows, null);
                    try objects.finish(a, &tables, start, "EquivLimits");
                    start = tables.items.len;
                    try tost.renderTests(a, &tables, &rows, null);
                    try objects.finish(a, &tables, start, "EquivTests");
                } else {
                    try render.tests(a, &tables, r, spec.options);
                    try objects.finish(a, &tables, start, "TTests");
                }
            }
            if (tables.items.len == 0) continue;
            if (analysis.pair) |pair| {
                try body.print(a, "Difference: {s} - {s}\n\n", .{ spec.input.ds.columns.items[pair.left].name, spec.input.ds.columns.items[pair.right].name });
            } else try body.print(a, "Variable: {s}\n\n", .{spec.input.ds.columns.items[analysis.column].name});
            if (spec.roles.frequency) |ci| try body.print(a, "Frequency: {s}\n", .{spec.input.ds.columns.items[ci].name});
            if (spec.roles.weight) |ci| try body.print(a, "Weight: {s}\n", .{spec.input.ds.columns.items[ci].name});
            try body.appendSlice(a, tables.items);
        }
        if (body.items.len == 0) continue;
        if (spec.roles.by.len > 0) try by.appendLine(a, out, spec.input.ds, group.representative.?, spec.roles.by);
        try out.appendSlice(a, "The TTEST Procedure\n\n");
        try out.appendSlice(a, body.items);
    }
}

const Testing = struct {
    fn expectWords(expected: []const u8, actual: []const u8) !void {
        var e = std.mem.tokenizeAny(u8, expected, " \r\n\t\x0c");
        var r = std.mem.tokenizeAny(u8, actual, " \r\n\t\x0c");
        while (e.next()) |word| try std.testing.expectEqualStrings(word, r.next() orelse "<missing>");
        try std.testing.expect(r.next() == null);
    }
    fn oracle(a: A, name: []const u8) ![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(std.testing.io, name, a, .limited(1024 * 1024));
    }
    fn sample(a: A) !*@import("../dataset.zig").Dataset {
        const Dataset = @import("../dataset.zig").Dataset;
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "sample");
        for ([_][]const u8{ "x", "y" }) |n| _ = try ds.addColumn(n, .num);
        _ = try ds.addColumn("group", .char);
        _ = try ds.addColumn("freq", .num);
        _ = try ds.addColumn("weight", .num);
        // Published input from STAT-TTEST-001; no fitted values in the fixture.
        const rows = [_][4]f64{
            .{ 43, 40, 1, 1 }, .{ 90, 84, 2, 1 },   .{ 84, 88, 1, 2 },
            .{ 87, 80, 1, 1 }, .{ 116, 110, 1, 1 }, .{ 95, 91, 1, 2 },
            .{ 86, 79, 1, 1 }, .{ 99, 101, 2, 1 },  .{ 93, 90, 1, 2 },
            .{ 92, 85, 1, 1 }, .{ 121, 115, 1, 1 }, .{ 71, 72, 1, 2 },
        };
        for (rows, 0..) |r, i| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .str = if (i < 6) "A" else "B" }, .{ .num = r[2] }, .{ .num = r[3] } });
        return ds;
    }
};

test "STAT-TTEST-001 complete BY FREQ WEIGHT listing matches oracle tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample order=data; by group; var x y; freq freq; weight weight; run;", &d));
    const expected = try Testing.oracle(a, "tests/STAT15.4-oracle/STAT-TTEST-001/by_frequency_weight.expected.txt");
    try Testing.expectWords(expected, out.items);
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-001 one-sample two and directed sides preserve full COMMON005 oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "time");
    _ = try ds.addColumn("time", .num);
    for ([_]f64{ 43, 90, 84, 87, 116, 95, 86, 99, 93, 92, 121, 71, 66, 98, 79, 102, 60, 112, 105, 98 }) |x| try ds.appendRow(&.{.{ .num = x }});
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("time", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "2", "u", "l" }) |side| {
        const source = try std.fmt.allocPrint(a, "proc ttest data=time h0=80 sides={s}; var time; run;", .{side});
        try runTtest(cx, &out, try lex.tokenize(a, source, &d));
    }
    const expected = try Testing.oracle(a, "tests/STAT15.4-oracle/STAT-COMMON-005/tails_and_intervals.expected.txt");
    try Testing.expectWords(expected, out.items);
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-001 summary rows and CLASS ordering retain typed results" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const tokens = try lex.tokenize(a, "proc ttest data=sample order=internal; class group; var x; freq freq; weight weight; run;", &d);
    const s = try declarations.parse(cx, tokens);
    const r = try compute(cx, s);
    try std.testing.expectEqual(@as(usize, 2), r.groups[0].analyses[0].samples.len);
    try std.testing.expectEqualStrings("A", r.groups[0].analyses[0].classes[0].label);
    try std.testing.expectEqual(@as(usize, 7), r.groups[0].analyses[0].samples[0].n);
    var summary = @import("../dataset.zig").Dataset.init(a, "summary");
    _ = try summary.addColumn("_TYPE_", .char);
    _ = try summary.addColumn("x", .num);
    for ([_][]const u8{ "N", "MEAN", "STD" }, [_]f64{ 3, 2, 1 }) |kind, value| try summary.appendRow(&.{ .{ .str = kind }, .{ .num = value } });
    try lib.put("summary", &summary);
    const summarized = try compute(cx, try declarations.parse(cx, try lex.tokenize(a, "proc ttest data=summary h0=2; var x; run;", &d)));
    const result = summarized.groups[0].analyses[0].samples[0];
    try std.testing.expectEqual(@as(usize, 3), result.n);
    try std.testing.expectEqual(@as(f64, 1), result.std_dev);
    try std.testing.expectEqual(@as(f64, 1), result.p);
    var bad = diag.Diagnostics.init(a);
    const badcx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &bad };
    try std.testing.expectError(error.ParseError, declarations.parse(badcx, try lex.tokenize(a, "proc ttest data=summary; var x; freq x; run;", &bad)));
}

test "STAT-TTEST-001 sorted BY errors, NOTSORTED groups, missing and nonpositive roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Dataset = @import("../dataset.zig").Dataset;
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "g", "x", "y", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 1 }, Value.missing, .{ .num = 2.9 }, .{ .num = 0.5 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 3 }, .{ .num = 9 }, .{ .num = 1 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 5 }, .{ .num = 8 }, .{ .num = 2 }, .{ .num = 1 } });
    for ([_]f64{ 0, -1, std.math.nan(f64) }) |w| try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 999 }, .{ .num = 999 }, .{ .num = 5 }, .{ .num = w } });
    for ([_]f64{ 0.9, -2, std.math.nan(f64) }) |f| try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 999 }, .{ .num = 999 }, .{ .num = f }, .{ .num = 1 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try declarations.parse(cx, try lex.tokenize(a, "proc ttest; by g notsorted; var x y; freq f; weight w; run;", &d));
    const r = try compute(cx, s);
    try std.testing.expectEqual(@as(usize, 2), r.groups.len);
    const gx = r.groups[0].analyses[0].samples[0];
    const gy = r.groups[0].analyses[1].samples[0];
    try std.testing.expectEqual(@as(usize, 3), gx.n);
    try std.testing.expectEqual(@as(usize, 1), gy.n);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 / 3.0), gx.mean, 1e-14);
    try std.testing.expectEqual(@as(usize, 2), r.groups[1].analyses[0].samples[0].n);
    try std.testing.expectEqual(@as(f64, 5), r.groups[1].analyses[0].samples[0].mean);
    const sorted = try declarations.parse(cx, try lex.tokenize(a, "proc ttest; by g; var x; run;", &d));
    try std.testing.expectError(error.ParseError, compute(cx, sorted));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "not sorted") != null);
    // No output is fabricated when WHERE produces an empty input.
    var empty_d = diag.Diagnostics.init(a);
    const empty_cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &empty_d };
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, runTtest(empty_cx, &out, try lex.tokenize(a, "proc ttest; var x; where x<0; run;", &empty_d)));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-TTEST-001 CLASS formatted levels, encounter and frequency ordering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    _ = try ds.addColumn("c", .num);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("f", .num);
    _ = try ds.addColumn("w", .num);
    try ds.appendRow(&.{ .{ .num = 2.1 }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 100 } });
    try ds.appendRow(&.{ .{ .num = 1.1 }, .{ .num = 3 }, .{ .num = 3 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 2.2 }, .{ .num = 2 }, .{ .num = 1 }, .{ .num = 100 } });
    try ds.appendRow(&.{ Value.missing, .{ .num = 999 }, .{ .num = 9 }, .{ .num = 1 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "data", "freq", "internal", "formatted", "mixed" }, [_][]const u8{ "2", "1", "1", "1", "1" }) |order, first| {
        const source = try std.fmt.allocPrint(a, "proc ttest order={s}; class c; var x; freq f; weight w; format c 3.; run;", .{order});
        const s = try declarations.parse(cx, try lex.tokenize(a, source, &d));
        const r = try compute(cx, s);
        try std.testing.expectEqualStrings(first, r.groups[0].analyses[0].classes[0].label);
        try std.testing.expectEqual(@as(usize, 2), r.groups[0].analyses[0].classes.len);
    }
    const three = try declarations.parse(cx, try lex.tokenize(a, "proc ttest; class c; var x; run;", &d));
    try std.testing.expectError(error.ParseError, compute(cx, three));
}

test "STAT-TTEST-003 full normal and lognormal listing matches unchanged oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "normal", "lognormal" }) |distribution| {
        const source = try std.fmt.allocPrint(a, "proc ttest data=sample dist={s} ci=equal; var x; run;", .{distribution});
        try runTtest(cx, &out, try lex.tokenize(a, source, &d));
    }
    try Testing.expectWords(try Testing.oracle(a, "tests/STAT15.4-oracle/STAT-TTEST-003/normal_lognormal.expected.txt"), out.items);
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-003 execution preserves frequency weight alignment and explicit original-scale H0" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = @exp(@as(f64, 1));
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    for ([_][]const u8{ "x", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    // Omitted rows surround retained responses. The FREQ and WEIGHT arrays
    // must follow the retained responses, not their original positions.
    for ([_][3]f64{ .{ -1, 10, 3 }, .{ 1, 1.9, 2 }, .{ 0, 8, 7 }, .{ e, 2.1, 1 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = try std.fmt.allocPrint(a, "proc ttest h0={d} dist=lognormal sides=u; var x; freq f; weight w; run;", .{@exp(@as(f64, 0.5))});
    const result = try compute(cx, try declarations.parse(cx, try lex.tokenize(a, source, &d)));
    const r = result.groups[0].analyses[0].lognormal_samples.?[0];
    try std.testing.expectEqual(@as(usize, 3), r.log_fit.n);
    try std.testing.expectEqual(@as(f64, 4), r.log_fit.sum_weights);
    try std.testing.expectApproxEqAbs(@exp(@as(f64, 0.5)), r.geometric_mean, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(std.math.expm1(@as(f64, 0.5))), r.cv, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), r.log_fit.p, 1e-14);
    try std.testing.expectEqual(std.math.inf(f64), r.mean_ci.upper);
    try std.testing.expectEqual(@as(usize, 2), r.omitted_nonpositive);
    try std.testing.expectEqual(@as(usize, 1), d.count());
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expectEqual(@as(u8, 0), diag.exitCode(false, d.hasErrors()));
}

test "STAT-TTEST-003 all invalid responses warn at rc0; constant CV and CI NONE remain defined" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ -1, 0, std.math.nan(f64) }) |x| try ds.appendRow(&.{.{ .num = x }});
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest dist=lognormal; var x; run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "0 . . . .") != null);
    try std.testing.expectEqual(@as(u8, 0), diag.exitCode(false, d.hasErrors()));
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "2 observations") != null);
    ds.rows.clearRetainingCapacity();
    for (0..3) |_| try ds.appendRow(&.{.{ .num = 2 }});
    out.clearRetainingCapacity();
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest dist=lognormal ci=none; var x; run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "CL CV") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "CL Mean") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "2 Infty <.0001") != null);
}

test "STAT-TTEST-007 integrated CLASS and COCHRAN listing matches original oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample cochran; class group; var x; run;", &d));
    try Testing.expectWords(try Testing.oracle(a, "tests/STAT15.4-oracle/STAT-TTEST-007/two_sample_variance.expected.txt"), out.items);
    try std.testing.expectEqualStrings("", try d.render());
    out.clearRetainingCapacity();
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample sides=u ci=none; class group; var x; run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Cochran") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "CL Std Dev") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Pr > t") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Infty") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Equality of Variances") != null);
}

test "STAT-TTEST-007 preserves explicit gap for lognormal two-group analysis" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, runTtest(cx, &out, try lex.tokenize(a, "proc ttest dist=lognormal; class group; var x; run;", &d)));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-TTEST-006 original paired direction listing matches all reference tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample; paired x*y; run;", &d));
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample sides=u; paired y*x; run;", &d));
    try Testing.expectWords(try Testing.oracle(a, "tests/STAT15.4-oracle/STAT-TTEST-006/paired_direction.expected.txt"), out.items);
    try std.testing.expectEqualStrings("", try d.render());
    out.clearRetainingCapacity();
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample; paired x*x; run;", &d));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-TTEST-006 pairwise missing exclusion and BY FREQ WEIGHT preserve independent analytic moments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const nan = std.math.nan(f64);
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y", "z", "f", "w", "g" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][6]f64{
        .{ 4, 1, 0, 1, 1, 1 },     .{ 6, 2, nan, 2.9, 2, 1 }, .{ nan, 5, 2, 1, 1, 1 },
        .{ 100, 0, 0, 0.9, 1, 1 }, .{ 100, 0, 0, 1, 0, 1 },   .{ 8, 3, 1, 1, 1, 2 },
        .{ 5, 3, 2, 1, 1, 2 },
    }) |row| {
        var cells: [6]Value = undefined;
        for (row, &cells) |x, *cell| cell.* = .{ .num = x };
        try ds.appendRow(&cells);
    }
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try declarations.parse(cx, try lex.tokenize(a, "proc ttest; by g; freq f; weight w; paired (x y):(y z); run;", &d));
    const result = try compute(cx, spec);
    try std.testing.expectEqual(@as(usize, 2), result.groups.len);
    const first = result.groups[0].analyses[0].samples[0];
    const second = result.groups[0].analyses[1].samples[0];
    // x-y retains differences (3,4) with frequencies (1,2), weights (1,2):
    // n=3, W=5, mean=19/5, CSS=.8, variance=.4, SE=sqrt(.08).
    try std.testing.expectEqual(@as(usize, 3), first.n);
    try std.testing.expectEqual(@as(f64, 5), first.sum_weights);
    try std.testing.expectApproxEqAbs(@as(f64, 19.0 / 5.0), first.mean, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.4)), first.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.08)), first.std_err, 1e-14);
    // y-z independently retains (1,3), including the row with missing x.
    try std.testing.expectEqual(@as(usize, 2), second.n);
    try std.testing.expectEqual(@as(f64, 2), second.mean);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 2)), second.std_dev, 1e-14);
    try std.testing.expectEqual(@as(usize, 2), result.groups[1].analyses[0].samples[0].n);
    try std.testing.expectEqual(@as(usize, 7), ds.rows.items.len);
    const reversed = try compute(cx, try declarations.parse(cx, try lex.tokenize(a, "proc ttest; by g; freq f; weight w; paired y*x; run;", &d)));
    const rev = reversed.groups[0].analyses[0].samples[0];
    try std.testing.expectApproxEqAbs(-first.mean, rev.mean, 1e-14);
    try std.testing.expectApproxEqAbs(-first.t, rev.t, 1e-14);
    try std.testing.expectApproxEqAbs(-first.mean_ci.upper, rev.mean_ci.lower, 1e-14);
    try std.testing.expectApproxEqAbs(-first.mean_ci.lower, rev.mean_ci.upper, 1e-14);
    const upper = try compute(cx, try declarations.parse(cx, try lex.tokenize(a, "proc ttest sides=u; by g; freq f; weight w; paired x*y y*x; run;", &d)));
    try std.testing.expectApproxEqAbs(@as(f64, 1), upper.groups[0].analyses[0].samples[0].p + upper.groups[0].analyses[1].samples[0].p, 1e-14);
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-009 integrated original TOST difference listing matches every oracle token" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try runTtest(cx, &out, try lex.tokenize(a, "proc ttest data=sample tost(-20,20) alpha=.05; class group; var x; run;", &d));
    try Testing.expectWords(try Testing.oracle(a, "tests/STAT15.4-oracle/STAT-TTEST-009/tost_difference.expected.txt"), out.items);
    try std.testing.expectEqualStrings("", try d.render());
}

test "STAT-TTEST-009 one-sample lognormal and paired invocation retain their scales" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", try Testing.sample(a));
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{
        "proc ttest data=sample tost(-20,200); var x; run;",
        "proc ttest data=sample dist=lognormal tost(20,200); var x; run;",
        "proc ttest data=sample tost(-20,20); paired x*y; run;",
    }, [_][]const u8{ "Variable: x", "Geometric Coefficient", "Difference: x - y" }) |source, label| {
        var out: std.ArrayList(u8) = .empty;
        try runTtest(cx, &out, try lex.tokenize(a, source, &d));
        try std.testing.expect(std.mem.indexOf(u8, out.items, label) != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "90% CL Mean") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "95% CL Mean") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Overall") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Pr > |t|") == null);
    }
    try std.testing.expectEqualStrings("", try d.render());
    var tiny = @import("../dataset.zig").Dataset.init(a, "tiny");
    _ = try tiny.addColumn("x", .num);
    try tiny.appendRow(&.{.{ .num = 1 }});
    try lib.put("tiny", &tiny);
    var invalid_out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ExecError, runTtest(cx, &invalid_out, try lex.tokenize(a, "proc ttest data=tiny tost(-1,1); var x; run;", &d)));
    try std.testing.expect(d.hasErrors());
}
