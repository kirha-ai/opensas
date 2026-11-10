//! Table-independent execution adapter. The existing FREQ table layer retains
//! ownership of grouping, levels, formatting, missing policy and weight handling.
//! No PROC dispatch integration until GAP-freq-table-complete is ready.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const k = @import("freq_tests.zig");
const p = @import("freq_tests_parse.zig");
const render = @import("freq_tests_render.zig");
pub const Table = struct { matrix: k.CountMatrix, one_way: bool = false, negative_weights: bool = false };
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
    if (options.chisq) {
        const chisq = k.contingency(a, m, options.df) catch |err| {
            if (err == error.OutOfMemory) return err;
            return d.fail(error.ExecError, 0, "PROC FREQ: invalid counts or chi-square degrees of freedom", .{});
        };
        report.chi_square = chisq;
        if (options.warn.output) report.warning = chisq.sparse;
        try warn(d, chisq.sparse, options, proc_noprint);
        if (m.rows == 2 and m.cols == 2 and chisq.fisher == null) try d.report(.note, 0, "Fisher's exact test cannot be computed when there are noninteger frequencies.", .{});
        if (!proc_noprint) try render.contingency(a, out, chisq, options, m.counts[0]);
    }
    if (options.measures or options.plcorr) {
        const ordinal = try k.association(a, m, options.alpha);
        const nominal = try k.nominal(a, m, options.alpha);
        const poly = if (options.plcorr) try k.polychoric(a, m, options.polychoric) else null;
        if (poly) |result| if (!result.converged) {
            try d.report(.note, 0, "Polychoric correlation computations did not converge.", .{});
        };
        if (!proc_noprint) {
            try render.measures(a, out, ordinal, nominal, poly, m.rows == 2 and m.cols == 2, options, tests);
            if (m.rows == 2 and m.cols == 2) try render.risks(a, out, try k.risks(m.counts, options.alpha), options.alpha);
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
