//! OUTKERNEL descriptors and evaluated grid values; no graph rendering.
const std = @import("std");
const kernel = @import("univ_kernel.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const grid = @import("univ_kernel_grid.zig");
pub const Options = grid.Options;
pub const Report = grid.Report;

pub fn create(a: std.mem.Allocator, source: *Dataset, keys: []const usize, variable_length: usize, scale: kernel.VScale) !*Dataset {
    const output = try a.create(Dataset);
    output.* = Dataset.init(a, "");
    output.label = "Kernel Density Estimates";
    for (keys) |ci| _ = try output.addColumnLike(source.columns.items[ci].name, source.columns.items[ci]);
    for ([_][]const u8{ "_VAR_", "_TYPE_" }, [_][]const u8{ "Variable Name", "Kernel Function Type" }, [_]usize{ @max(@as(usize, 8), variable_length), 16 }) |name, label, length| {
        _ = try output.addColumn(name, .char);
        output.setLen(name, length);
        output.setLabel(name, label);
    }
    const scale_name = switch (scale) {
        .percent => "_PERCENT_",
        .proportion => "_PROPORTION_",
        .count => "_COUNT_",
    };
    const scale_label = switch (scale) {
        .percent => "Percent of Observations Per Data Unit",
        .proportion => "Proportion of Observations Per Data Unit",
        .count => "Observations Per Data Unit",
    };
    for ([_][]const u8{ "_C_", "_VALUE_", scale_name, "_DENSITY_" }, [_][]const u8{ "Standardized Bandwidth Parameter", "Data Value", scale_label, "Density" }) |name, label| {
        _ = try output.addColumn(name, .num);
        output.setLen(name, 8);
        output.setLabel(name, label);
    }
    return output;
}

/// Compatibility entry point: the supplied histogram extent is authoritative.
/// The owner should call appendBatch with automatic=true for automatic bins;
/// batching also shares the axis and FFT extent across multiple kernels.
pub fn append(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, iqr: f64, request: kernel.Request, endpoints: []const f64, scale: kernel.VScale) diag.Error!void {
    return appendBatch(d, output, source, keys, representative, ci, x, iqr, &.{request}, endpoints, scale, .{});
}

/// Output-only bandwidth fallback observed in M9: a zero IQR uses the data
/// range, and a constant sample uses unit scale. A one-point kernel is valid.
/// Keep this separate from the mathematical estimator's stricter input API.
pub fn fitForOutput(d: *diag.Diagnostics, x: []const f64, iqr: f64, request: kernel.Request) diag.Error!kernel.Estimate {
    if (x.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty kernel output sample", .{});
    const range = x[x.len - 1] - x[0];
    const effective = if (iqr > 0) iqr else if (range > 0) range else 1;
    var estimate = if (x.len > 1) try kernel.fit(d, x, effective, request) else try kernel.fit(d, &.{ x[0], x[0] }, effective, request);
    if (x.len == 1) {
        estimate.bandwidth *= std.math.pow(f64, 2, 0.2);
        estimate.amise *= std.math.pow(f64, 2, 0.8);
    }
    if (request.bandwidth == .mise) {
        // M9 uses eight significant digits for the normal-reference C in
        // both the output descriptor and the evaluated kernel bandwidth.
        const factor = std.math.pow(f64, 10, 7 - @floor(@log10(estimate.c)));
        const c = @round(estimate.c * factor) / factor;
        const h = c * effective * std.math.pow(f64, @as(f64, @floatFromInt(x.len)), -0.2);
        const ratio = h / estimate.bandwidth;
        estimate.amise *= (std.math.pow(f64, ratio, 4) + 4 / ratio) / 5;
        estimate.c = c;
        estimate.bandwidth = h;
    }
    return estimate;
}

pub fn appendBatch(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, iqr: f64, requests: []const kernel.Request, endpoints: []const f64, scale: kernel.VScale, options: Options) diag.Error!void {
    if (options.report) |report| report.* = .{};
    const effective_requests: []const kernel.Request = if (requests.len == 0) &.{.{}} else requests;
    const estimates = try output.arena.alloc(kernel.Estimate, effective_requests.len);
    for (effective_requests, estimates) |request, *estimate| estimate.* = try fitForOutput(d, x, iqr, request);
    return appendEstimates(d, output, source, keys, representative, ci, x, estimates, endpoints, scale, options);
}

/// Allows another owned estimator (for example SJPI) to supply its fitted
/// bandwidth without this output layer refitting it or changing its method.
pub fn appendEstimates(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, estimates: []const kernel.Estimate, endpoints: []const f64, scale: kernel.VScale, options: Options) diag.Error!void {
    if (options.report) |report| report.* = .{};
    if (estimates.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: no kernel estimates supplied for output", .{});
    for (estimates) |estimate| {
        if (!(estimate.c > 0) or !std.math.isFinite(estimate.c)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid standardized output bandwidth", .{});
    }
    const shared = grid.padding(estimates);
    var actual = options;
    actual.shared_axis_padding = options.shared_axis_padding orelse shared.axis;
    actual.shared_fft_padding = options.shared_fft_padding orelse shared.fft;
    if (estimates.len > 1) for (estimates[1..]) |estimate| {
        if (!std.meta.eql(estimate.request.lower, estimates[0].request.lower)) actual.clip_lower = false;
        if (!std.meta.eql(estimate.request.upper, estimates[0].request.upper)) actual.clip_upper = false;
    };
    const covered = if (options.windowed) endpoints else try @import("univ_histogram_bins.zig").cover(output.arena, d, x, endpoints, options.right);
    for (estimates) |estimate| {
        const plan = try grid.make(output.arena, d, x, estimate, covered, actual);
        const density = try grid.evaluate(output.arena, d, x, estimate, plan);
        for (plan.points) |point| try row(d, output, source, keys, representative, ci, x, estimate, point, plan.bin_width, scale, density.at(point));
    }
}

fn row(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, estimate: kernel.Estimate, point: f64, width: f64, scale: kernel.VScale, density: f64) diag.Error!void {
    const values = try output.arena.alloc(Value, keys.len + 6);
    for (keys, 0..) |key, i| values[i] = representative[key];
    const at = keys.len;
    _ = d;
    values[at] = .{ .str = source.columns.items[ci].name };
    values[at + 1] = .{ .str = switch (estimate.request.kind) {
        .normal => "Normal",
        .quadratic => "Quadratic",
        .triangular => "Triangular",
    } };
    values[at + 2] = .{ .num = estimate.c };
    values[at + 3] = .{ .num = point };
    values[at + 4] = .{ .num = kernel.scaleDensity(density, width, x.len, scale) };
    values[at + 5] = .{ .num = density };
    try output.appendRow(values);
}

test "dev3 OUTKERNEL grids and explicit unresolved compact cutoff comparisons" {
    const binning = @import("univ_histogram_bins.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var source = Dataset.init(a, "d");
    _ = try source.addColumn("x", .num);
    const wide = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    var held: [17]f64 = undefined;
    var samples = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_kernel_grid_dev3_heldout.txt"), '\n');
    for (&held) |*v| v.* = try std.fmt.parseFloat(f64, samples.next().?);
    var unit: [20]f64 = undefined;
    for (&unit, 0..) |*v, i| v.* = @as(f64, @floatFromInt(i)) / 19;
    const flat0 = [_]f64{5};
    const flat1 = [_]f64{0} ** 20;
    const flat2 = [_]f64{0.01} ** 20;
    const flat4 = [_]f64{1234} ** 2;
    const flatmise = [_]f64{5} ** 20;
    var tied = [_]f64{0} ** 21;
    tied[20] = 10;
    const Case = struct { name: []const u8, x: []const f64, iqr: f64, requests: []const kernel.Request, ends: []const f64 = &.{}, automatic: bool = true, scale: kernel.VScale = .percent };
    const cases = [_]Case{
        .{ .name = "reflected0", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 }, .lower = -3, .upper = 0.5 }} },
        .{ .name = "reflected1", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .kind = .quadratic, .bandwidth = .{ .numeric = 0.7 }, .lower = -3, .upper = 0.5 }} },
        .{ .name = "reflected2", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .kind = .triangular, .bandwidth = .{ .numeric = 1.1 }, .lower = -3, .upper = 0.5 }} },
        .{ .name = "kgrid0", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "kgrid1", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 1 } }} },
        .{ .name = "kgrid2", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 2 } }} },
        .{ .name = "kgrid3", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }}, .ends = &.{ 0, 5, 10, 15, 20 }, .automatic = false },
        .{ .name = "kgrid4", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 }, .lower = 0, .upper = 20 }} },
        .{ .name = "kgrid5", .x = &wide, .iqr = 6.5, .requests = &.{.{ .kind = .quadratic, .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "kgrid6", .x = &wide, .iqr = 6.5, .requests = &.{.{ .kind = .triangular, .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "kgrid7", .x = &wide, .iqr = 6.5, .requests = &.{ .{ .bandwidth = .{ .numeric = 0.5 } }, .{ .bandwidth = .{ .numeric = 1 } } } },
        .{ .name = "kgrid8", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }}, .scale = .count },
        .{ .name = "kgrid9", .x = &wide, .iqr = 6.5, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }}, .scale = .proportion },
        .{ .name = "held0", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .bandwidth = .{ .numeric = 0.2 } }} },
        .{ .name = "held1", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .bandwidth = .{ .numeric = 0.9 } }} },
        .{ .name = "held2", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .kind = .quadratic, .bandwidth = .{ .numeric = 1 } }} },
        .{ .name = "held3", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .kind = .triangular, .bandwidth = .{ .numeric = 2 } }} },
        .{ .name = "held4", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 }, .lower = -4, .upper = 2 }} },
        .{ .name = "held5", .x = &held, .iqr = held[12] - held[4], .requests = &.{ .{ .bandwidth = .{ .numeric = 0.3 } }, .{ .bandwidth = .{ .numeric = 0.9 } } } },
        .{ .name = "held6", .x = &held, .iqr = held[12] - held[4], .requests = &.{.{ .bandwidth = .{ .numeric = 0.2 } }} },
        .{ .name = "aligned", .x = &unit, .iqr = 10.0 / 19.0, .requests = &.{.{ .bandwidth = .{ .numeric = 0.1 } }}, .ends = &.{ 0, 0.25, 0.5, 0.75, 1 }, .automatic = false },
        .{ .name = "flat0", .x = &flat0, .iqr = 0, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "flat1", .x = &flat1, .iqr = 0, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "flat2", .x = &flat2, .iqr = 0, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "flat4", .x = &flat4, .iqr = 0, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "zeroiqr", .x = &tied, .iqr = 0, .requests = &.{.{ .bandwidth = .{ .numeric = 0.5 } }} },
        .{ .name = "boundslist", .x = &wide, .iqr = 6.5, .requests = &.{ .{ .bandwidth = .{ .numeric = 0.5 }, .lower = 0, .upper = 20 }, .{ .bandwidth = .{ .numeric = 0.6 }, .lower = -5, .upper = 30 } } },
        .{ .name = "extra_k0", .x = &wide, .iqr = 6.5, .requests = &.{}, .ends = &.{ 0, 5, 10 }, .automatic = false },
        .{ .name = "extra_k1", .x = &wide, .iqr = 6.5, .requests = &.{}, .ends = &.{ 5, 10 }, .automatic = false },
        .{ .name = "extra_k2", .x = &wide, .iqr = 6.5, .requests = &.{}, .ends = &.{ -2.5, 2.5, 7.5 }, .automatic = false },
        .{ .name = "extra_k3", .x = &wide, .iqr = 6.5, .requests = &.{ .{ .bandwidth = .{ .numeric = 0.5 }, .lower = 0, .upper = 20 }, .{ .bandwidth = .{ .numeric = 0.6 }, .lower = 0, .upper = 20 } } },
        .{ .name = "extra_k4", .x = &wide, .iqr = 6.5, .requests = &.{.{ .kind = .quadratic, .bandwidth = .{ .numeric = 1 } }} },
        .{ .name = "extra_k5", .x = &wide, .iqr = 6.5, .requests = &.{.{ .kind = .triangular, .bandwidth = .{ .numeric = 1 } }} },
        .{ .name = "flatmise", .x = &flatmise, .iqr = 0, .requests = &.{} },
    };
    var compared: usize = 0;
    var differences: usize = 0;
    for (cases) |case| {
        const bin_plan = try binning.determine(a, &d, &.{.{ .sorted = case.x }}, .{});
        const ends = if (case.ends.len > 0) case.ends else bin_plan.endpoints;
        const bin_width = if (case.ends.len > 0) case.ends[1] - case.ends[0] else bin_plan.width;
        const output = try create(a, &source, &.{}, 8, case.scale);
        var report: Report = .{};
        try appendBatch(&d, output, &source, &.{}, &.{}, 0, case.x, case.iqr, case.requests, ends, case.scale, .{ .automatic = case.automatic, .bin_width = bin_width, .report = &report });
        try std.testing.expectEqual(output.rows.items.len, report.point_count);
        var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_kernel_grid_dev3.txt"), '\n');
        var row_index: usize = 0;
        while (lines.next()) |line| {
            if (line[0] == '#') continue;
            var fields = std.mem.splitScalar(u8, line, '|');
            if (!std.mem.eql(u8, fields.next().?, case.name)) continue;
            if (row_index >= output.rows.items.len) {
                std.debug.print("missing output row: {s} {d}\n", .{ case.name, row_index });
                return error.TestUnexpectedResult;
            }
            const actual_row = output.rows.items[row_index];
            const c = try std.fmt.parseFloat(f64, fields.next().?);
            const point = try std.fmt.parseFloat(f64, fields.next().?);
            const density = try std.fmt.parseFloat(f64, fields.next().?);
            const scaled = try std.fmt.parseFloat(f64, fields.next().?);
            try std.testing.expectApproxEqAbs(c, actual_row[2].num, 1e-12);
            if (@abs(point - actual_row[3].num) > 1e-10) {
                std.debug.print("grid mismatch {s} row {d}: {d} vs {d}\n", .{ case.name, row_index, point, actual_row[3].num });
                return error.TestUnexpectedResult;
            }
            if (@abs(density - actual_row[5].num) > 1e-9) {
                try std.testing.expect(report.compact_cutoff_unverified);
                var gaps = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_kernel_grid_dev3_gaps.txt"), '\n');
                var known = false;
                while (gaps.next()) |gap| {
                    if (gap[0] == '#') continue;
                    var fields_gap = std.mem.splitScalar(u8, gap, '|');
                    const name = fields_gap.next().?;
                    const index = try std.fmt.parseInt(usize, fields_gap.next().?, 10);
                    if (!std.mem.eql(u8, name, case.name) or index != row_index) continue;
                    try std.testing.expectApproxEqAbs(try std.fmt.parseFloat(f64, fields_gap.next().?), point, 1e-12);
                    try std.testing.expectApproxEqAbs(try std.fmt.parseFloat(f64, fields_gap.next().?), density, 1e-14);
                    try std.testing.expectApproxEqAbs(try std.fmt.parseFloat(f64, fields_gap.next().?), actual_row[5].num, 1e-12);
                    known = true;
                    break;
                }
                if (!known) {
                    std.debug.print("unrecorded kernel discrepancy {s} row {d}: {d} vs {d}\n", .{ case.name, row_index, density, actual_row[5].num });
                    return error.TestUnexpectedResult;
                }
                differences += 1;
            } else try std.testing.expectApproxEqAbs(scaled, actual_row[4].num, 1e-9 * @max(@as(f64, 1), @abs(scaled)));
            try std.testing.expectEqualStrings(fields.next().?, actual_row[1].str);
            row_index += 1;
            compared += 1;
        }
        if (row_index != output.rows.items.len) {
            std.debug.print("row count {s}: oracle {d}, actual {d}\n", .{ case.name, row_index, output.rows.items.len });
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 10085), compared);
    // Do not turn these three oracle disagreements into passing equality
    // expectations or hide them by widening the density tolerance.
    try std.testing.expectEqual(@as(usize, 3), differences);
}

test "dev3 OUTKERNEL schema preserves key formats and empty descriptors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source = Dataset.init(a, "d");
    _ = try source.addColumn("g", .num);
    source.setLen("g", 4);
    source.setFormat("g", "z3.");
    source.setInformat("g", "comma4.");
    source.setLabel("g", "By label");
    _ = try source.addColumn("c", .char);
    source.setLen("c", 5);
    source.setFormat("c", "$5.");
    source.setLabel("c", "Class label");
    _ = try source.addColumn("abcdefghijklmnopq", .num);
    const output = try create(a, &source, &.{ 0, 1 }, 17, .count);
    for (output.columns.items, [_][]const u8{ "g", "c", "_VAR_", "_TYPE_", "_C_", "_VALUE_", "_COUNT_", "_DENSITY_" }) |col, name| try std.testing.expectEqualStrings(name, col.name);
    try std.testing.expectEqual(@as(?usize, 4), output.columns.items[0].len);
    try std.testing.expectEqualStrings("z3.", output.columns.items[0].format.?);
    try std.testing.expectEqualStrings("comma4.", output.columns.items[0].informat.?);
    try std.testing.expectEqual(@as(?usize, 17), output.columns.items[2].len);
    try std.testing.expectEqual(@as(?usize, 16), output.columns.items[3].len);
    try std.testing.expectEqualStrings("Observations Per Data Unit", output.columns.items[6].label.?);
    for (output.columns.items[4..]) |col| {
        try std.testing.expectEqual(@as(?usize, 8), col.len);
        try std.testing.expect(col.format == null and col.informat == null);
    }
    try std.testing.expectEqual(@as(usize, 0), output.rows.items.len);
    const empty = try create(a, &source, &.{}, 8, .proportion);
    try std.testing.expectEqual(@as(usize, 6), empty.columns.items.len);
    try std.testing.expectEqualStrings("_PROPORTION_", empty.columns.items[4].name);
    try std.testing.expectEqualStrings("Proportion of Observations Per Data Unit", empty.columns.items[4].label.?);
    var d = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ParseError, appendEstimates(&d, empty, &source, &.{}, &.{}, 2, &.{ 1, 2 }, &.{}, &.{ 0, 3 }, .proportion, .{}));
    try std.testing.expectError(error.ParseError, fitForOutput(&d, &.{ 2, 1 }, 1, .{}));
}

test "dev3 class sample six eight excludes value two outside native FFT lattice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var source = Dataset.init(a, "d");
    _ = try source.addColumn("x", .num);
    const output = try create(a, &source, &.{}, 8, .percent);
    try appendBatch(&d, output, &source, &.{}, &.{}, 0, &.{ 6, 8 }, 2, &.{.{ .bandwidth = .{ .numeric = 0.5 } }}, &.{ 0, 2, 4, 6, 8, 10 }, .percent, .{});
    var saw_four = false;
    for (output.rows.items) |point| {
        try std.testing.expect(point[3].num != 2);
        if (point[3].num == 4) {
            saw_four = true;
            try std.testing.expectApproxEqAbs(@as(f64, 0.01637919), point[5].num, 5e-9);
        }
    }
    try std.testing.expect(saw_four);
    try std.testing.expectEqualStrings("Kernel Density Estimates", output.label.?);
}
