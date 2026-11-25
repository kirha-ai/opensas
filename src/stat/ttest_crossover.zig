//! AB/BA normal-difference crossover, S154 physical pp.10629-10630 and
//! Example 128.4, pp.10661-10670. No shared TTEST parser dependency.
//! Treatment compares half period differences; period compares half treatment
//! differences. Both comparisons reuse the tested two-independent-sample core.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const Value = @import("../value.zig").Value;
const format = @import("../format.zig");
const selection = @import("data_selection.zig");
const fit = @import("ttest_fit.zig");
const two = @import("ttest_two_sample.zig");
const A = std.mem.Allocator;

pub const Sequence = enum { ab, ba };
pub const Observation = struct {
    response: [2]f64,
    sequence: Sequence,
    frequency: f64 = 1,
    weight: f64 = 1,
};
pub const Options = two.Options;
pub const Order = enum { data, formatted, freq, internal, mixed };
pub const RunOptions = struct {
    inference: Options = .{},
    order: Order = .mixed,
    show_sd_ci: bool = true,
    ignore_period: bool = false,
    procedure_header: bool = true,
    line: usize = 0,
};
pub const Result = struct {
    /// Indexed [sequence AB/BA][period 1/2], on the original response scale.
    cells: [2][2]fit.Result,
    /// A-B within each sequence, on the full difference scale.
    sequence_differences: [2]fit.Result,
    treatment: two.Result,
    period: two.Result,
};

fn scaled(s: fit.Result, factor: f64) fit.Result {
    var r = s;
    r.mean *= factor;
    r.std_dev *= @abs(factor);
    r.std_err *= @abs(factor);
    r.minimum = (if (factor < 0) s.maximum else s.minimum) * factor;
    r.maximum = (if (factor < 0) s.minimum else s.maximum) * factor;
    // These are transformed moments, not a retained test of the original null.
    // two.compute refreshes the intervals and comparison inference from them.
    r.t = std.math.nan(f64);
    r.p = std.math.nan(f64);
    r.mean_ci = .{};
    r.std_dev_ci = .{};
    return r;
}

pub fn compute(a: A, rows: []const Observation, options: Options, d: *diag.Diagnostics, line: usize) diag.Error!Result {
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const tmp = scratch.allocator();
    var periods: [2][2]std.ArrayList(f64) = .{ .{ .empty, .empty }, .{ .empty, .empty } };
    var differences: [2]std.ArrayList(f64) = .{ .empty, .empty };
    var frequencies: [2]std.ArrayList(f64) = .{ .empty, .empty };
    var weights: [2]std.ArrayList(f64) = .{ .empty, .empty };
    for (rows) |row| {
        if (std.math.isNan(row.response[0]) or std.math.isNan(row.response[1])) continue;
        if (std.math.isNan(row.frequency) or row.frequency < 1 or std.math.isNan(row.weight) or row.weight <= 0) continue;
        if (!std.math.isFinite(row.response[0]) or !std.math.isFinite(row.response[1]) or !std.math.isFinite(row.frequency) or !std.math.isFinite(row.weight))
            return d.fail(error.ExecError, line, "PROC TTEST CROSSOVER: nonfinite response, frequency or weight", .{});
        const k: usize = if (row.sequence == .ab) 0 else 1;
        const difference = if (k == 0) row.response[0] - row.response[1] else row.response[1] - row.response[0];
        if (!std.math.isFinite(difference)) return d.fail(error.ExecError, line, "PROC TTEST CROSSOVER: treatment difference exceeds the numeric range", .{});
        try periods[k][0].append(tmp, row.response[0]);
        try periods[k][1].append(tmp, row.response[1]);
        try differences[k].append(tmp, difference);
        try frequencies[k].append(tmp, @trunc(row.frequency));
        try weights[k].append(tmp, row.weight);
    }
    var result: Result = undefined;
    const one_options: fit.Options = .{ .h0 = options.h0, .alpha = options.alpha, .sides = options.sides };
    for (0..2) |k| {
        if (differences[k].items.len == 0) return d.fail(error.ParseError, line, "PROC TTEST CROSSOVER: both AB and BA sequences require usable observations", .{});
        for (0..2) |p| result.cells[k][p] = fit.oneSample(periods[k][p].items, frequencies[k].items, weights[k].items, one_options) catch |err| return numericFailure(d, line, err);
        result.sequence_differences[k] = fit.oneSample(differences[k].items, frequencies[k].items, weights[k].items, one_options) catch |err| return numericFailure(d, line, err);
        if (result.sequence_differences[k].n < 2) return d.fail(error.ParseError, line, "PROC TTEST CROSSOVER: each sequence requires at least two replicated observations for variance estimation", .{});
    }
    const ab_half = scaled(result.sequence_differences[0], 0.5);
    result.treatment = two.compute(ab_half, scaled(result.sequence_differences[1], -0.5), options) catch |err| return numericFailure(d, line, err);
    result.period = two.compute(ab_half, scaled(result.sequence_differences[1], 0.5), options) catch |err| return numericFailure(d, line, err);
    return result;
}
fn numericFailure(d: *diag.Diagnostics, line: usize, err: diag.Error) diag.Error {
    if (err == error.OutOfMemory) return err;
    return d.fail(error.ExecError, line, "PROC TTEST CROSSOVER: invalid moments or nonfinite inference", .{});
}

const Level = struct { label: []const u8, raw: Value };
fn label(a: A, view: selection.View, ci: usize, row: []const Value) ![]const u8 {
    const c = view.source.columns.items[ci];
    return std.mem.trim(u8, if (c.format) |f| try format.apply(a, row[ci], f) else try proc.cellText(a, row[ci]), " ");
}
fn levelBefore(order: Order, first_numeric: bool, formatted_first: bool, a: Level, b: Level) bool {
    const internal = order == .internal or (order == .mixed and first_numeric) or (order == .formatted and first_numeric and !formatted_first);
    return if (internal) proc.cmpValue(a.raw, b.raw) == .lt else std.mem.order(u8, a.label, b.label) == .lt;
}

/// Hook contract: view is ONE BY group after PROC input options/WHERE. The caller
/// passes one response pair and the two treatment columns from VAR/CROSSOVER=.
/// This function validates formatted treatment levels, selects paired responses,
/// computes both contrasts and emits the complete default normal listing.
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), view: selection.View, responses: [2]usize, treatments: [2]usize, o: RunOptions) diag.Error!void {
    if (o.ignore_period) return proc.failGap(cx.diags, o.line, "PROC TTEST CROSSOVER: IGNOREPERIOD is not implemented", .{});
    if (o.order == .freq) return proc.failGap(cx.diags, o.line, "PROC TTEST CROSSOVER: ORDER=FREQ is not implemented", .{});
    for (responses) |ci| {
        if (ci >= view.source.columns.items.len or view.source.columns.items[ci].type != .num)
            return cx.diags.fail(error.ParseError, o.line, "PROC TTEST CROSSOVER: response variables must be numeric", .{});
    }
    for (treatments) |ci| if (ci >= view.source.columns.items.len) return cx.diags.fail(error.ParseError, o.line, "PROC TTEST CROSSOVER: treatment variable not found", .{});
    const selected = try view.select(cx.arena, .{ .missing_columns = &treatments, .frequency = .truncate_positive, .weight = .positive_only });
    var levels: std.ArrayList(Level) = .empty;
    for (selected.observations) |row| {
        const a = try label(cx.arena, view, treatments[0], row.cells);
        const b = try label(cx.arena, view, treatments[1], row.cells);
        if (std.mem.eql(u8, a, b)) return cx.diags.fail(error.ParseError, o.line, "PROC TTEST CROSSOVER: treatments must differ between periods for every observation", .{});
        for (treatments, [_][]const u8{ a, b }) |ci, value| {
            var found = false;
            for (levels.items) |old| if (std.mem.eql(u8, old.label, value)) {
                found = true;
                break;
            };
            if (!found) try levels.append(cx.arena, .{ .label = value, .raw = row.cells[ci] });
        }
    }
    if (levels.items.len != 2) return cx.diags.fail(error.ParseError, o.line, "PROC TTEST CROSSOVER: treatment variables must have exactly two nonmissing formatted levels", .{});
    const first = view.source.columns.items[treatments[0]];
    if (o.order != .data and levelBefore(o.order, first.type == .num, first.format != null, levels.items[1], levels.items[0])) std.mem.swap(Level, &levels.items[0], &levels.items[1]);
    var rows: std.ArrayList(Observation) = .empty;
    for (selected.observations) |row| try rows.append(cx.arena, .{
        .response = .{ row.cells[responses[0]].num, row.cells[responses[1]].num },
        .sequence = if (std.mem.eql(u8, try label(cx.arena, view, treatments[0], row.cells), levels.items[0].label)) .ab else .ba,
        .frequency = row.frequency.num,
        .weight = row.weight.num,
    });
    const r = try compute(cx.arena, rows.items, o.inference, cx.diags, o.line);
    try renderWithHeader(cx.arena, out, r, .{ view.source.columns.items[responses[0]].name, view.source.columns.items[responses[1]].name }, .{ view.source.columns.items[treatments[0]].name, view.source.columns.items[treatments[1]].name }, .{ levels.items[0].label, levels.items[1].label }, o.show_sd_ci, o.procedure_header);
}

fn num(a: A, value: f64, spec: []const u8) ![]const u8 {
    if (std.math.isInf(value)) return if (value < 0) "-Infty" else "Infty";
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ");
}
fn prefix(a: A, out: *std.ArrayList(u8), sequence: []const u8, treatment: []const u8, period: []const u8, method: []const u8) !void {
    try out.print(a, "{s:<10} {s:<12} {s:<12} {s:<14} ", .{ sequence, treatment, period, method });
}
fn statisticsRow(a: A, out: *std.ArrayList(u8), s: fit.Result) !void {
    try out.print(a, "{s} {s} {s} {s} {s} {s}\n", .{ try num(a, @floatFromInt(s.n), "best12."), try num(a, s.mean, "d8.3"), try num(a, s.std_dev, "d8.3"), try num(a, s.std_err, "d8.3"), try num(a, s.minimum, "d8.3"), try num(a, s.maximum, "d8.3") });
}
fn intervalRow(a: A, out: *std.ArrayList(u8), mean: f64, ci: fit.Interval, sd: ?f64, sd_ci: fit.Interval, show: bool) !void {
    try out.print(a, "{s} {s} {s}", .{ try num(a, mean, "d8.3"), try num(a, ci.lower, "d8.3"), try num(a, ci.upper, "d8.3") });
    if (sd) |value| {
        try out.print(a, " {s}", .{try num(a, value, "d8.3")});
        if (show) try out.print(a, " {s} {s}", .{ try num(a, sd_ci.lower, "d8.3"), try num(a, sd_ci.upper, "d8.3") });
    }
    try out.appendSlice(a, "\n");
}
fn testRow(a: A, out: *std.ArrayList(u8), method: []const u8, variance: []const u8, c: two.Comparison) !void {
    try out.print(a, "{s} {s} {s} {s} {s}\n", .{ method, variance, try num(a, c.df, "best6."), try num(a, c.t, "8.2"), try num(a, c.p, "pvalue6.4") });
}

pub fn render(a: A, out: *std.ArrayList(u8), r: Result, responses: [2][]const u8, treatments: [2][]const u8, labels: [2][]const u8, show_sd_ci: bool) diag.Error!void {
    try renderWithHeader(a, out, r, responses, treatments, labels, show_sd_ci, true);
}
fn renderWithHeader(a: A, out: *std.ArrayList(u8), r: Result, responses: [2][]const u8, treatments: [2][]const u8, labels: [2][]const u8, show_sd_ci: bool, procedure_header: bool) diag.Error!void {
    if (procedure_header) try out.appendSlice(a, "The TTEST Procedure\n\n");
    try out.print(a, "Response Variables: {s}, {s}\n\nCrossover Variable Information\n\nPeriod Response Treatment\n1 {s} {s}\n2 {s} {s}\n\n", .{ responses[0], responses[1], responses[0], treatments[0], responses[1], treatments[1] });
    const cells = [_]struct { sequence: usize, period: usize, treatment: usize }{ .{ .sequence = 0, .period = 0, .treatment = 0 }, .{ .sequence = 1, .period = 1, .treatment = 0 }, .{ .sequence = 1, .period = 0, .treatment = 1 }, .{ .sequence = 0, .period = 1, .treatment = 1 } };
    const numbers = [_][]const u8{ "1", "2" };
    try out.appendSlice(a, "Sequence Treatment Period Method N Mean Std Dev Std Err Minimum Maximum\n\n");
    for (cells) |c| {
        try prefix(a, out, numbers[c.sequence], labels[c.treatment], numbers[c.period], "");
        try statisticsRow(a, out, r.cells[c.sequence][c.period]);
    }
    for (r.sequence_differences, 0..) |s, k| {
        try prefix(a, out, numbers[k], "Diff (1-2)", "", "");
        try statisticsRow(a, out, s);
    }
    for ([_]two.Result{ r.treatment, r.period }, 0..) |effect, k| {
        try prefix(a, out, "Both", if (k == 0) "Diff (1-2)" else "", if (k == 1) "Diff (1-2)" else "", "Pooled");
        try out.print(a, "{s} {s} {s}\n", .{ try num(a, effect.pooled.estimate, "d8.3"), try num(a, effect.pooled.std_dev, "d8.3"), try num(a, effect.pooled.std_err, "d8.3") });
        try prefix(a, out, "Both", if (k == 0) "Diff (1-2)" else "", if (k == 1) "Diff (1-2)" else "", "Satterthwaite");
        try out.print(a, "{s} {s}\n", .{ try num(a, effect.satterthwaite.estimate, "d8.3"), try num(a, effect.satterthwaite.std_err, "d8.3") });
    }
    const confidence = try num(a, 100 * (1 - r.treatment.options.alpha), "best8.");
    try out.print(a, "\nSequence Treatment Period Method Mean {s}% CL Mean Std Dev", .{confidence});
    if (show_sd_ci) try out.print(a, " {s}% CL Std Dev", .{confidence});
    try out.appendSlice(a, "\n\n");
    for (cells) |c| {
        const s = r.cells[c.sequence][c.period];
        try prefix(a, out, numbers[c.sequence], labels[c.treatment], numbers[c.period], "");
        try intervalRow(a, out, s.mean, s.mean_ci, s.std_dev, s.std_dev_ci, show_sd_ci);
    }
    for (r.sequence_differences, 0..) |s, k| {
        try prefix(a, out, numbers[k], "Diff (1-2)", "", "");
        try intervalRow(a, out, s.mean, s.mean_ci, s.std_dev, s.std_dev_ci, show_sd_ci);
    }
    for ([_]two.Result{ r.treatment, r.period }, 0..) |effect, k| {
        try prefix(a, out, "Both", if (k == 0) "Diff (1-2)" else "", if (k == 1) "Diff (1-2)" else "", "Pooled");
        try intervalRow(a, out, effect.pooled.estimate, effect.pooled.mean_ci, effect.pooled.std_dev, effect.pooled.std_dev_ci, show_sd_ci);
        try prefix(a, out, "Both", if (k == 0) "Diff (1-2)" else "", if (k == 1) "Diff (1-2)" else "", "Satterthwaite");
        try intervalRow(a, out, effect.satterthwaite.estimate, effect.satterthwaite.mean_ci, null, .{}, show_sd_ci);
    }
    const tail: []const u8 = switch (r.treatment.options.sides) {
        .two_sided => "Pr > |t|",
        .upper => "Pr > t",
        .lower => "Pr < t",
    };
    try out.print(a, "\nTreatment Period Method Variances DF t Value {s}\n\n", .{tail});
    for ([_]two.Result{ r.treatment, r.period }, 0..) |effect, k| {
        try out.print(a, "{s:<12} {s:<12} ", .{ if (k == 0) @as([]const u8, "Diff (1-2)") else "", if (k == 1) @as([]const u8, "Diff (1-2)") else "" });
        try testRow(a, out, "Pooled", "Equal", effect.pooled);
        try out.print(a, "{s:<12} {s:<12} ", .{ if (k == 0) @as([]const u8, "Diff (1-2)") else "", if (k == 1) @as([]const u8, "Diff (1-2)") else "" });
        try testRow(a, out, "Satterthwaite", "Unequal", effect.satterthwaite);
        if (effect.cochran) |c| {
            try out.print(a, "{s:<12} {s:<12} ", .{ if (k == 0) @as([]const u8, "Diff (1-2)") else "", if (k == 1) @as([]const u8, "Diff (1-2)") else "" });
            try testRow(a, out, "Cochran", "Unequal", c);
        }
    }
    try out.appendSlice(a, "\n");
    try two.equalityTable(a, out, r.treatment);
}

const Testing = struct {
    fn expectWords(expected: []const u8, actual: []const u8) !void {
        var lhs = std.mem.tokenizeAny(u8, expected, " \r\n\t\x0c");
        var rhs = std.mem.tokenizeAny(u8, actual, " \r\n\t\x0c");
        while (lhs.next()) |word| try std.testing.expectEqualStrings(word, rhs.next() orelse "<missing>");
        try std.testing.expect(rhs.next() == null);
    }
    fn asthma(a: A) !*@import("../dataset.zig").Dataset {
        const Dataset = @import("../dataset.zig").Dataset;
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "asthma");
        _ = try ds.addColumn("drug1", .char);
        _ = try ds.addColumn("drug2", .char);
        _ = try ds.addColumn("pef1", .num);
        _ = try ds.addColumn("pef2", .num);
        // Published Example 128.4 input, physical pp.10662-10664.
        for ([_][2]f64{ .{ 310, 270 }, .{ 310, 260 }, .{ 370, 300 }, .{ 410, 390 }, .{ 250, 210 }, .{ 380, 350 }, .{ 330, 365 }, .{ 370, 385 }, .{ 310, 400 }, .{ 380, 410 }, .{ 290, 320 }, .{ 260, 340 }, .{ 90, 220 } }, 0..) |r, i| {
            try ds.appendRow(&.{ .{ .str = if (i < 7) "for" else "sal" }, .{ .str = if (i < 7) "sal" else "for" }, .{ .num = r[0] }, .{ .num = r[1] } });
        }
        return ds;
    }
};

test "CROSSOVER independent small AB BA treatment period and sequence quantities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const rows = [_]Observation{
        .{ .response = .{ 12, 8 }, .sequence = .ab },  .{ .response = .{ 16, 10 }, .sequence = .ab },
        .{ .response = .{ 10, 18 }, .sequence = .ba }, .{ .response = .{ 8, 14 }, .sequence = .ba },
    };
    const r = try compute(arena.allocator(), &rows, .{}, &d, 7);
    // Half-period differences: AB=(2,3), BA=(-4,-3). Each variance=.5;
    // treatment=2.5-(-3.5)=6, pooled SE=sqrt(.5), df=2.
    try std.testing.expectEqual(@as(f64, 6), r.treatment.pooled.estimate);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.5)), r.treatment.pooled.std_dev, 1e-14);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.5)), r.treatment.pooled.std_err, 1e-14);
    try std.testing.expectApproxEqAbs(6 * @sqrt(@as(f64, 2)), r.treatment.pooled.t, 1e-13);
    try std.testing.expectEqual(@as(f64, 2), r.treatment.pooled.df);
    try std.testing.expectApproxEqAbs(@as(f64, 2), r.treatment.satterthwaite.df, 1e-14);
    // Half-treatment differences: AB=(2,3), BA=(4,3); period=2.5-3.5=-1.
    try std.testing.expectEqual(@as(f64, -1), r.period.pooled.estimate);
    try std.testing.expectApproxEqAbs(-@sqrt(@as(f64, 2)), r.period.pooled.t, 1e-14);
    try std.testing.expectEqual(@as(f64, 5), r.sequence_differences[0].mean);
    try std.testing.expectEqual(@as(f64, 7), r.sequence_differences[1].mean);
    try std.testing.expectEqual(@as(usize, 2), r.cells[0][0].n);
    try std.testing.expectEqual(@as(usize, 2), r.cells[1][1].n);
    try std.testing.expectEqual(@as(f64, 14), r.cells[0][0].mean);
    try std.testing.expectEqual(@as(f64, 16), r.cells[1][1].mean);
    try std.testing.expectEqual(@as(f64, 9), r.cells[0][1].mean);
    try std.testing.expectEqual(@as(f64, 9), r.cells[1][0].mean);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.treatment.equality.f, 1e-14);
    try std.testing.expectApproxEqAbs(@as(f64, 1), r.treatment.equality.p, 1e-13);
    // Relabel treatments while preserving periods: treatment reverses, period stays.
    var relabeled = rows;
    for (&relabeled) |*row| row.sequence = if (row.sequence == .ab) .ba else .ab;
    const swapped = try compute(arena.allocator(), &relabeled, .{}, &d, 7);
    try std.testing.expectEqual(-r.treatment.pooled.estimate, swapped.treatment.pooled.estimate);
    try std.testing.expectEqual(r.period.pooled.estimate, swapped.period.pooled.estimate);
    // Reverse periods and sequences: treatment stays, period reverses.
    for (&relabeled) |*row| std.mem.swap(f64, &row.response[0], &row.response[1]);
    const reversed = try compute(arena.allocator(), &relabeled, .{}, &d, 7);
    try std.testing.expectEqual(r.treatment.pooled.estimate, reversed.treatment.pooled.estimate);
    try std.testing.expectEqual(-r.period.pooled.estimate, reversed.period.pooled.estimate);
    try std.testing.expectEqualStrings("", try d.render());
}

test "CROSSOVER full default Example128.4 listing matches unchanged original oracle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try Testing.asthma(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("asthma", ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const view = try selection.View.init(a, .{ .ds = ds }, .{ .analysis = &.{ 2, 3 } });
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, view, .{ 2, 3 }, .{ 0, 1 }, .{});
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/STAT15.4-oracle/STAT-TTEST-008/abba_crossover.expected.txt", a, .limited(1024 * 1024));
    try Testing.expectWords(expected, out.items);
    try std.testing.expectEqualStrings("", try d.render());
}

test "CROSSOVER response-pair missingness and FREQ preserve replicated counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const nan = std.math.nan(f64);
    const rows = [_]Observation{
        .{ .response = .{ 12, 8 }, .sequence = .ab, .frequency = 2.9 },    .{ .response = .{ 16, 10 }, .sequence = .ab },
        .{ .response = .{ 10, 18 }, .sequence = .ba },                     .{ .response = .{ 8, 14 }, .sequence = .ba },
        .{ .response = .{ nan, 100 }, .sequence = .ab, .frequency = 99 },  .{ .response = .{ 100, nan }, .sequence = .ba, .frequency = 99 },
        .{ .response = .{ 100, 999 }, .sequence = .ab, .frequency = 0.9 }, .{ .response = .{ 100, 999 }, .sequence = .ba, .weight = 0 },
    };
    const r = try compute(arena.allocator(), &rows, .{}, &d, 3);
    try std.testing.expectEqual(@as(usize, 3), r.cells[0][0].n);
    try std.testing.expectEqual(@as(usize, 3), r.cells[0][1].n);
    try std.testing.expectEqual(@as(usize, 2), r.cells[1][0].n);
    try std.testing.expectEqual(@as(f64, 3), r.treatment.pooled.df);
    // AB half-differences=(2,2,3), BA=(-4,-3): treatment=7/3+7/2=35/6.
    try std.testing.expectApproxEqAbs(@as(f64, 35.0 / 6.0), r.treatment.pooled.estimate, 1e-14);
    const expanded = [_]Observation{ rows[0], rows[0], rows[1], rows[2], rows[3] };
    var units = expanded;
    for (&units) |*row| row.frequency = 1;
    const other = try compute(arena.allocator(), &units, .{}, &d, 3);
    try std.testing.expectApproxEqAbs(r.treatment.pooled.std_err, other.treatment.pooled.std_err, 1e-14);
    try std.testing.expectApproxEqAbs(r.period.satterthwaite.p, other.period.satterthwaite.p, 1e-14);
}

test "CROSSOVER invalid sequences and treatment assignments fail through captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, compute(a, &.{ .{ .response = .{ 1, 2 }, .sequence = .ab }, .{ .response = .{ 2, 3 }, .sequence = .ab } }, .{}, &d, 7));
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(usize, 7), d.list.items[0].line);
    var ds = try Testing.asthma(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("asthma", ds);
    var bad = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &bad };
    const row = try a.dupe(Value, ds.rows.items[0]);
    row[1] = row[0];
    ds.rows.items[0] = row;
    const view = try selection.View.init(a, .{ .ds = ds }, .{});
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, run(cx, &out, view, .{ 2, 3 }, .{ 0, 1 }, .{ .line = 9 }));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 9), bad.list.items[0].line);
}
