//! Table-independent execution adapter. The existing FREQ table layer retains
//! ownership of grouping, levels, formatting, missing policy and weight handling.
//! Public PROC orchestration lives in freq.zig.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const k = @import("freq_tests.zig");
const p = @import("freq_tests_parse.zig");
const render = @import("freq_tests_render.zig");
pub const Table = struct { suppress_fisher: bool = false, numeric_table_scores_valid: bool = true, name: ?[]const u8 = null, matrix: k.CountMatrix, one_way: bool = false, negative_weights: bool = false, score_display: ?render.ScoreDisplay = null };
pub const Report = struct { goodness_of_fit: ?k.GoodnessOfFit = null, chi_square: ?k.ChiSquare = null, warning: ?bool = null };
fn canonicalName(name: []const u8) []const u8 {
    return if (name.len > 5 and std.ascii.eqlIgnoreCase(name[0..5], "work.")) name[5..] else name;
}
pub fn secondaryName(source: p.ExpectedSource) ?[]const u8 {
    return switch (source) {
        .proportion_dataset, .frequency_dataset => |name| name,
        else => null,
    };
}
/// Enforce the procedure-wide single-secondary-dataset restriction at parse end.
pub fn validateSecondarySources(options: []const p.Options, primary_name: []const u8, d: *diag.Diagnostics) diag.Error!void {
    var seen: ?[]const u8 = null;
    for (options) |o| if (secondaryName(o.expected)) |name| {
        if (std.ascii.eqlIgnoreCase(canonicalName(name), canonicalName(primary_name))) return d.fail(error.ExecError, 0, "PROC FREQ: TESTP/TESTF dataset cannot be the DATA= dataset", .{});
        if (seen) |old| {
            if (!std.ascii.eqlIgnoreCase(canonicalName(old), canonicalName(name))) return d.fail(error.ExecError, 0, "PROC FREQ: only one TESTP/TESTF dataset is allowed", .{});
        } else seen = name;
    };
}
/// Dataset rows correspond to DISPLAYED level order, not category-name joins.
/// The caller resolves the optional secondary name through the existing Library.
pub fn resolveExpected(a: std.mem.Allocator, source: p.ExpectedSource, secondary: ?*const Dataset, d: *diag.Diagnostics) diag.Error!k.Expected {
    switch (source) {
        .equal => return .equal,
        .proportions => |v| return .{ .proportions = v },
        .frequencies => |v| return .{ .frequencies = v },
        .proportion_dataset, .frequency_dataset => {},
    }
    const ds = secondary orelse return d.fail(error.ExecError, 0, "PROC FREQ: TESTP/TESTF dataset not found", .{});
    const proportions = source == .proportion_dataset;
    const names = if (proportions) [_][]const u8{ "_TESTP_", "TestPercent", "Percent" } else [_][]const u8{ "_TESTF_", "TestFrequency", "Frequency" };
    var column: ?usize = null;
    for (names) |name| if (ds.indexOf(name)) |c| {
        column = c;
        break;
    };
    const c = column orelse return d.fail(error.ExecError, 0, "PROC FREQ: secondary dataset requires {s}, {s}, or {s}", .{ names[0], names[1], names[2] });
    if (ds.columns.items[c].type != .num) return d.fail(error.ExecError, 0, "PROC FREQ: TESTP/TESTF column must be numeric", .{});
    const values = try a.alloc(f64, ds.rows.items.len);
    for (ds.rows.items, 0..) |row, i| {
        const v = if (row[c] == .num) row[c].num else std.math.nan(f64);
        if (!std.math.isFinite(v) or v <= 0) return d.fail(error.ExecError, 0, "PROC FREQ: TESTP/TESTF values must be positive and nonmissing", .{});
        values[i] = v;
    }
    return if (proportions) .{ .proportions = values } else .{ .frequencies = values };
}
fn warn(d: *diag.Diagnostics, sparse: bool, options: p.Options, noprint: bool) diag.Error!void {
    if (sparse and noprint and options.warn.log) try d.report(.warning, 0, "More than 20% of the cells have expected counts less than 5. Chi-Square may not be a valid test.", .{});
}
/// Called once per one-way table or two-way stratum, AFTER table construction.
/// TABLES NOPRINT is deliberately absent: it does not suppress statistics.
pub fn execute(a: std.mem.Allocator, d: *diag.Diagnostics, out: *std.ArrayList(u8), table: Table, options: p.Options, tests: p.Tests, expected: k.Expected, proc_noprint: bool) diag.Error!Report {
    var report: Report = .{};
    const m = table.matrix;
    if (!options.chisq and !options.measures and !options.plcorr) return report;
    if (table.negative_weights) {
        try d.report(.note, 0, "PROC FREQ: statistics are not computed when there are negative weights", .{});
        return report;
    }
    if (table.one_way) {
        if (!options.chisq) return report;
        var zero_total = m.counts.len > 0;
        for (m.counts) |count| if (count != 0) {
            zero_total = false;
        };
        if (zero_total) {
            if (options.df) |df| if (!std.math.isFinite(df) or df == 0) return d.fail(error.ExecError, 0, "PROC FREQ: the CHISQ DF value must be finite and nonzero", .{});
            _ = k.expectedFactor(m.counts.len, 0, expected) catch |err| {
                if (err == error.OutOfMemory) return err;
                return d.fail(error.ExecError, 0, "PROC FREQ: invalid TESTP/TESTF values or number of levels", .{});
            };
            if (table.name) |name| try d.report(.note, 0, "No statistics are computed for the table of {s} because it contains no observations with positive weights.", .{name}) else try d.report(.note, 0, "No statistics are computed for this table because it contains no observations with positive weights.", .{});
            return report;
        }
        const gof = k.goodnessOfFit(m.counts, expected, options.df) catch |err| {
            if (err == error.OutOfMemory) return err;
            return d.fail(error.ExecError, 0, "PROC FREQ: invalid goodness-of-fit counts, expected values, or degrees of freedom", .{});
        };
        report.goodness_of_fit = gof;
        if (options.warn.output) report.warning = gof.sparse;
        try warn(d, gof.sparse, options, proc_noprint);
        if (!proc_noprint) try render.goodnessOfFit(a, out, gof, options);
        return report;
    }
    if (m.rows == 0 or m.cols == 0 or m.rows > std.math.maxInt(usize) / m.cols or m.counts.len != m.rows * m.cols) return d.fail(error.ExecError, 0, "PROC FREQ: invalid count matrix", .{});
    var zero_margin = false;
    for (0..m.rows) |i| {
        var total: f64 = 0;
        for (m.counts[i * m.cols ..][0..m.cols]) |v| total += v;
        if (total == 0) zero_margin = true;
    }
    for (0..m.cols) |j| {
        var total: f64 = 0;
        for (0..m.rows) |i| total += m.counts[i * m.cols + j];
        if (total == 0) zero_margin = true;
    }
    if (zero_margin or m.rows < 2 or m.cols < 2) {
        if (!proc_noprint) try out.appendSlice(a, "\nRow or column sum zero. No statistics computed for this table.\n");
        return report;
    }
    if (!table.numeric_table_scores_valid) try d.report(.warning, 0, "Some statistics are not computed because there is no valid numeric table score for the missing values.", .{});
    if (!proc_noprint) if (table.score_display) |display| try render.scores(a, out, m, display, options.score_type);
    if (options.chisq) {
        var chisq = k.contingency(a, m, options.df) catch |err| {
            if (err == error.OutOfMemory) return err;
            return d.fail(error.ExecError, 0, "PROC FREQ: invalid counts or chi-square degrees of freedom", .{});
        };
        if (!table.numeric_table_scores_valid) chisq.mantel_haenszel = .{ .statistic = std.math.nan(f64), .df = 1, .p = std.math.nan(f64) };
        report.chi_square = chisq;
        if (options.warn.output) report.warning = chisq.sparse;
        try warn(d, chisq.sparse, options, proc_noprint);
        if (m.rows == 2 and m.cols == 2 and chisq.fisher == null) try d.report(.note, 0, "Fisher's exact test cannot be computed when there are noninteger frequencies.", .{});
        if (!proc_noprint) {
            var displayed = chisq;
            if (table.suppress_fisher) displayed.fisher = null;
            try render.contingency(a, out, displayed, options, m.counts[0]);
        }
    }
    if (options.measures or options.plcorr) {
        var ordinal = try k.association(a, m, options.alpha);
        var applicable_tests = tests;
        if (!table.numeric_table_scores_valid) {
            ordinal.pearson = .{};
            applicable_tests.pearson = false;
        }
        const nominal = try k.nominal(a, m, options.alpha);
        const poly = if (options.plcorr) try k.polychoric(a, m, options.polychoric) else null;
        if (poly) |result| if (!result.converged) {
            try d.report(.note, 0, "Polychoric correlation computations did not converge.", .{});
        };
        if (!proc_noprint) {
            try render.measures(a, out, ordinal, nominal, poly, m.rows == 2 and m.cols == 2, options, applicable_tests);
            if (m.rows == 2 and m.cols == 2 and !options.measures_only_implied) try render.risks(a, out, try k.risks(m.counts, options.alpha), options.alpha);
        }
    }
    return report;
}

test "FEAT-freq-tests dataset aliases and nonmissing validation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var ds = Dataset.init(a, "probs");
    _ = try ds.addColumn("TestPercent", .num);
    for ([_]f64{ 20, 30, 50 }) |v| try ds.appendRow(&.{.{ .num = v }});
    const expected = try resolveExpected(a, .{ .proportion_dataset = "probs" }, &ds, &d);
    const gof = try k.goodnessOfFit(&.{ 20, 27, 23 }, expected, null);
    try std.testing.expectApproxEqAbs(@as(f64, 8.4), gof.pearson.statistic, 1e-12);
    try std.testing.expectError(error.ExecError, validateSecondarySources(&.{.{ .expected = .{ .proportion_dataset = "WORK.ONE" } }}, "one", &d));
    try std.testing.expect(d.hasErrors());
}
test "FEAT-freq-tests execution WARN control and zero margins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const table = Table{ .matrix = .{ .rows = 2, .cols = 2, .counts = &.{ 1, 2, 3, 1 } } };
    const report = try execute(a, &d, &out, table, .{ .chisq = true, .warn = .{ .output = true } }, .{}, .equal, true);
    try std.testing.expectEqual(@as(?bool, true), report.warning);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    d.list.clearRetainingCapacity();
    _ = try execute(a, &d, &out, table, .{ .chisq = true, .warn = .{ .log = false } }, .{}, .equal, true);
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
    _ = try execute(a, &d, &out, .{ .matrix = .{ .rows = 3, .cols = 2, .counts = &.{ 0, 0, 3, 5, 4, 1 } } }, .{ .chisq = true, .measures = true }, .{}, .equal, false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "No statistics computed") != null);
}

test "FEAT-freq-tests single category executes and renders without error or warning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const table = Table{ .one_way = true, .matrix = .{ .rows = 1, .cols = 1, .counts = &.{3} } };
    const report = try execute(a, &d, &out, table, .{ .chisq = true, .lrchi = true }, .{}, .equal, false);
    try std.testing.expectEqual(@as(f64, 0), report.goodness_of_fit.?.pearson.df);
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "nan") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "WARNING") == null);
    var lines = std.mem.splitScalar(u8, out.items, '\n');
    var missing_p_count: usize = 0;
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "Pr > ChiSq")) {
            try std.testing.expectEqualStrings(".", std.mem.trim(u8, line[10..], " "));
            missing_p_count += 1;
        }
        if (std.mem.startsWith(u8, line, "DF")) try std.testing.expectEqualStrings("0", std.mem.trim(u8, line[2..], " "));
    }
    try std.testing.expectEqual(@as(usize, 2), missing_p_count);
    _ = try execute(a, &d, &out, table, .{ .chisq = true }, .{}, .equal, true);
    try std.testing.expectEqual(@as(usize, 0), d.list.items.len);
}

test "FEAT-freq-tests SCOROUT keeps supplied scores and PROC NOPRINT still computes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const table = Table{ .matrix = .{ .rows = 3, .cols = 3, .counts = &.{ 12, 5, 3, 4, 17, 6, 2, 8, 13 }, .row_scores = &.{ 1, 10, 100 }, .col_scores = &.{ 2, 7, 40 } }, .score_display = .{ .row_name = "r", .col_name = "c", .row_labels = &.{ "1", "10", "100" }, .col_labels = &.{ "2", "7", "40" } } };
    const printed = try execute(a, &d, &out, table, .{ .chisq = true }, .{}, .equal, false);
    try std.testing.expectApproxEqAbs(@as(f64, 11.0261), printed.chi_square.?.mantel_haenszel.?.statistic, 0.00005);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Score Type = TABLE") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "100         100") != null);
    out.clearRetainingCapacity();
    const hidden = try execute(a, &d, &out, table, .{ .chisq = true }, .{}, .equal, true);
    try std.testing.expectEqual(printed.chi_square.?.mantel_haenszel.?.statistic, hidden.chi_square.?.mantel_haenszel.?.statistic);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectError(error.ExecError, execute(a, &d, &out, .{ .one_way = true, .matrix = .{ .rows = 1, .cols = 2, .counts = &.{ 2, 3 } } }, .{ .chisq = true }, .{}, .{ .proportions = &.{ 0.2, 0.2 } }, true));
    try std.testing.expect(d.hasErrors());
}

test "FEAT-freq-tests SAS zero-total table notes instead of errors with validation precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const table = Table{ .name = "g", .one_way = true, .matrix = .{ .rows = 2, .cols = 1, .counts = &.{ 0, 0 } } };
    for ([_]bool{ false, true }) |noprint| {
        for ([_]k.Expected{ .equal, .{ .proportions = &.{ 50, 50 } }, .{ .frequencies = &.{ 1, 1 } } }) |expected| {
            d.list.clearRetainingCapacity();
            const report = try execute(a, &d, &out, table, .{ .chisq = true, .lrchi = true, .df = -1 }, .{}, expected, noprint);
            try std.testing.expect(report.goodness_of_fit == null);
            try std.testing.expectEqual(@as(usize, 0), out.items.len);
            try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
            try std.testing.expectEqual(diag.Severity.note, d.list.items[0].severity);
            try std.testing.expectEqualStrings("No statistics are computed for the table of g because it contains no observations with positive weights.", d.list.items[0].message);
            try std.testing.expect(!d.hasErrors());
        }
    }
    d.list.clearRetainingCapacity();
    _ = try execute(a, &d, &out, table, .{ .chisq = true }, .{}, .equal, false);
    try std.testing.expect(!d.hasErrors());
    for ([_]k.Expected{ .{ .proportions = &.{ 20, 20 } }, .{ .proportions = &.{100} } }) |bad| {
        d.list.clearRetainingCapacity();
        try std.testing.expectError(error.ExecError, execute(a, &d, &out, table, .{ .chisq = true }, .{}, bad, true));
        try std.testing.expect(d.hasErrors());
    }
    d.list.clearRetainingCapacity();
    try std.testing.expectError(error.ExecError, execute(a, &d, &out, table, .{ .chisq = true, .df = 0 }, .{}, .equal, true));
    try std.testing.expect(d.hasErrors());
}

test "FEAT-freq-tests numeric missing TABLE display scores never become inference scores" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    // SAS included-missing-scores: N=160, fallback 0/1/2 is display only.
    const table = Table{ .numeric_table_scores_valid = false, .matrix = .{
        .rows = 3,
        .cols = 3,
        .counts = &.{ 24, 10, 6, 8, 30, 12, 6, 16, 48 },
        .row_scores = &.{ 0, 1, 2 },
        .col_scores = &.{ 10, 20, 30 },
    } };
    for ([_]bool{ false, true }) |hidden| {
        d.list.clearRetainingCapacity();
        out.clearRetainingCapacity();
        const report = try execute(a, &d, &out, table, .{ .chisq = true, .measures = true }, .{ .pearson = true, .spearman = true, .gamma = true }, .equal, hidden);
        const chi = report.chi_square.?;
        try std.testing.expectApproxEqAbs(@as(f64, 66.1627), chi.pearson.statistic, 0.00005);
        try std.testing.expect(std.math.isNan(chi.mantel_haenszel.?.statistic));
        try std.testing.expectEqual(@as(f64, 1), chi.mantel_haenszel.?.df);
        try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
        try std.testing.expect(std.mem.indexOf(u8, d.list.items[0].message, "no valid numeric table score") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Test of H0: Pearson") == null);
        if (hidden) try std.testing.expectEqual(@as(usize, 0), out.items.len) else {
            try std.testing.expect(std.mem.indexOf(u8, out.items, "8.0104") != null);
            try std.testing.expect(std.mem.indexOf(u8, out.items, "7.8220") != null);
        }
    }
}
