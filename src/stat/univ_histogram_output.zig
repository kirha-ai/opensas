//! Numeric OUTHISTOGRAM schema and occupied-bin groups. No rendering or parser.
const std = @import("std");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const distributions = @import("univ_distributions.zig");
const values = @import("univ_distribution_values.zig");
const binning = @import("univ_histogram_bins.zig");
pub const Options = struct {
    endpoint_labels: bool = false,
    right: bool = false,
    curve_columns: bool = false,
    variable_length: usize = 8,
    bin_width: ?f64 = null,
    /// Window controls omit outside observations without renormalizing N.
    clipped: bool = false,
};

pub fn create(a: std.mem.Allocator, source: *Dataset, keys: []const usize, options: Options) !*Dataset {
    const output = try a.create(Dataset);
    output.* = Dataset.init(a, "");
    output.label = "Histogram Statistics";
    for (keys) |ci| _ = try output.addColumnLike(source.columns.items[ci].name, source.columns.items[ci]);
    _ = try output.addColumn("_VAR_", .char);
    output.setLen("_VAR_", @max(@as(usize, 8), options.variable_length));
    output.setLabel("_VAR_", "Variable Name");
    const location = locationName(options);
    const label = if (!options.endpoint_labels) "Midpoint of Histogram Interval" else if (options.right) "Right endpoint of Histogram Interval" else "Left endpoint of Histogram Interval";
    for ([_][]const u8{ location, "_OBSPCT_", "_COUNT_" }, [_][]const u8{ label, "Percent of Observations in Interval", "Observation Count in Interval" }) |name, text| {
        _ = try output.addColumn(name, .num);
        output.setLen(name, 8);
        output.setLabel(name, text);
    }
    if (options.curve_columns) {
        _ = try output.addColumn("_CURVE_", .char);
        output.setLen("_CURVE_", 16);
        output.setLabel("_CURVE_", "Fitted Curve");
        _ = try output.addColumn("_EXPPCT_", .num);
        output.setLen("_EXPPCT_", 8);
        output.setLabel("_EXPPCT_", "Expected Percent From Fitted Curve");
    }
    return output;
}
pub fn locationName(options: Options) []const u8 {
    return if (!options.endpoint_labels) "_MIDPT_" else if (options.right) "_MAXPT_" else "_MINPT_";
}

pub fn bins(a: std.mem.Allocator, d: *diag.Diagnostics, x: []const f64, supplied: []const f64, options: Options, curve: ?distributions.Distribution) diag.Error![]values.Bin {
    for (x, 0..) |v, i| if (!std.math.isFinite(v) or (i > 0 and v < x[i - 1])) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram output requires sorted finite data", .{});
    const covered = if (options.clipped) supplied else try binning.cover(a, d, x, supplied, options.right);
    var endpoints = covered;
    if (options.endpoint_labels and covered.len >= 2) {
        const extended = try a.alloc(f64, covered.len + 1);
        @memcpy(extended[0..covered.len], covered);
        extended[covered.len] = covered[covered.len - 1] + (covered[1] - covered[0]);
        endpoints = extended;
    }
    if (endpoints.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: empty histogram output lattice", .{});
    const width = options.bin_width orelse (endpoints[1] - endpoints[0]);
    if (!(width > 0) or !std.math.isFinite(width)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid histogram output lattice", .{});
    for (endpoints[1..], 1..) |v, i| if (!std.math.isFinite(v) or @abs(v - endpoints[i - 1] - width) > 1e-10 * width) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid histogram output spacing", .{});
    const output = try a.alloc(values.Bin, endpoints.len - 1);
    const actual_curve = if (x.len > 0 and x[0] == x[x.len - 1]) null else curve;
    for (output, 0..) |*b, i| b.* = .{ .lower = endpoints[i], .upper = endpoints[i + 1], .midpoint = endpoints[i] / 2 + endpoints[i + 1] / 2, .count = 0, .observed_percent = 0, .expected_percent = if (actual_curve) |c| 100 * (c.cdf(endpoints[i + 1]) - c.cdf(endpoints[i])) else null };
    if (x.len == 0) return output[0..0];
    for (x) |v| {
        if (v < endpoints[0] or v > endpoints[endpoints.len - 1] or (options.right and v == endpoints[0]) or (!options.right and v == endpoints[endpoints.len - 1])) {
            if (options.clipped) continue;
            return d.fail(error.ParseError, 0, "UNIVARIATE: histogram lattice does not cover sample", .{});
        }
        const position = snapped((v - endpoints[0]) / width, @max(@abs(v), @abs(endpoints[0])) / width);
        const index = if (options.right) @ceil(position) - 1 else @floor(position);
        const at: usize = @intFromFloat(@min(@as(f64, @floatFromInt(output.len - 1)), @max(@as(f64, 0), index)));
        output[at].count += 1;
    }
    for (output) |*b| b.observed_percent = @as(f64, @floatFromInt(b.count)) / @as(f64, @floatFromInt(x.len)) * 100;
    var first: usize = 0;
    var last = output.len;
    while (first < last and output[first].count == 0) first += 1;
    while (last > first and output[last - 1].count == 0) last -= 1;
    if (options.clipped) {
        // Use clamped data extrema even if every observation is outside the
        // window: SAS retains the corresponding zero-count boundary row(s).
        const low_position = snapped((x[0] - endpoints[0]) / width, @max(@abs(x[0]), @abs(endpoints[0])) / width);
        const high_position = snapped((x[x.len - 1] - endpoints[0]) / width, @max(@abs(x[x.len - 1]), @abs(endpoints[0])) / width);
        const low_index = if (options.right) @ceil(low_position) - 1 else @floor(low_position);
        const high_index = if (options.right) @ceil(high_position) - 1 else @floor(high_position);
        first = @intFromFloat(@min(@as(f64, @floatFromInt(output.len - 1)), @max(@as(f64, 0), low_index)));
        last = 1 + @as(usize, @intFromFloat(@min(@as(f64, @floatFromInt(output.len - 1)), @max(@as(f64, 0), high_index))));
    }
    return output[first..last];
}

fn snapped(position: f64, scale: f64) f64 {
    const nearest = @round(position);
    return if (@abs(position - nearest) <= @max(@as(f64, 1e-12), 8 * std.math.floatEps(f64) * @max(@as(f64, 1), @max(@abs(position), scale)))) nearest else position;
}

pub fn append(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, endpoints: []const f64, options: Options, curve: ?distributions.Distribution) diag.Error!void {
    if (output.columns.items.len != keys.len + (if (options.curve_columns) @as(usize, 6) else 4)) return d.fail(error.ParseError, 0, "UNIVARIATE: histogram output schema does not match request", .{});
    const intervals = try bins(output.arena, d, x, endpoints, options, curve);
    const fitted = if (x.len > 0 and x[0] == x[x.len - 1]) null else curve;
    for (intervals) |b| {
        const row = try output.arena.alloc(Value, output.columns.items.len);
        @memset(row, Value.missing);
        for (keys, 0..) |key, i| row[i] = representative[key];
        const at = keys.len;
        row[at] = .{ .str = source.columns.items[ci].name };
        row[at + 1] = .{ .num = if (!options.endpoint_labels) b.midpoint else if (options.right) b.upper else b.lower };
        row[at + 2] = .{ .num = b.observed_percent };
        row[at + 3] = .{ .num = @floatFromInt(b.count) };
        if (options.curve_columns) {
            row[at + 4] = .{ .str = if (fitted) |c| curveName(c.family) else "" };
            if (b.expected_percent) |v| row[at + 5] = .{ .num = v };
        }
        try output.appendRow(row);
    }
}
fn curveName(family: distributions.Family) []const u8 {
    return switch (family) {
        .normal => "NORMAL",
        .lognormal => "LNORMAL",
        .exponential => "EXPONTL",
        .gamma => "GAMMA",
        .weibull => "WEIBULL",
        .beta => "BETA",
        .power => "POWER",
        .rayleigh => "RAYLEIGH",
        .pareto => "PARETO",
        .gumbel => "GUMBEL",
        .igauss => "IGAUSS",
        .sb => "SB",
        .su => "SU",
    };
}

test "dev3 OUTHISTOGRAM M9 shared constant key count controls windows and ties" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var source = Dataset.init(a, "d");
    _ = try source.addColumn("g", .char);
    source.setLen("g", 4);
    _ = try source.addColumn("x", .num);
    const Case = struct { name: []const u8, cells: []const binning.Cell, request: binning.Request = .{}, explicit: []const f64 = &.{} };
    var cases: std.ArrayList(Case) = .empty;
    const wide = [_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 };
    var narrow: [100]f64 = undefined;
    for (&narrow, 0..) |*v, i| v.* = 20 + @as(f64, @floatFromInt(i)) / 99;
    const shared = [_]binning.Cell{ .{ .sorted = &wide }, .{ .sorted = &narrow } };
    for ([_]usize{ 0, 1, 2, 3, 4, 6, 7 }) |index| {
        var request: binning.Request = .{ .endpoints = index == 2 or index == 3 or index == 7 };
        if (index == 1 or index == 3) request.mode = .uniform;
        if (index == 4) request.key_index = 1;
        if (index == 6 or index == 7) request.target_count = 5;
        try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "shared{d}", .{index}), .cells = &shared, .request = request });
    }
    var unit: [20]f64 = undefined;
    for (&unit, 0..) |*v, i| v.* = @as(f64, @floatFromInt(i)) / 19;
    const single = [_]binning.Cell{.{ .sorted = &unit }};
    for ([_]usize{ 3, 4, 5, 7, 10, 3, 4, 5, 7, 10, 1, 1 }, 0..) |count, index| try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "count{d}", .{index}), .cells = &single, .request = .{ .target_count = count, .endpoints = (index >= 5 and index <= 9) or index == 11 } });
    for ([_]f64{ 0, 1, -1, 0.01, 10, 1234, 12.345 }, 0..) |value, index| {
        const constant = try a.alloc(f64, 20);
        @memset(constant, value);
        const other = try a.alloc(f64, 21);
        for (other, 0..) |*v, i| v.* = value + @as(f64, @floatFromInt(i)) / 10;
        const cells = try a.alloc(binning.Cell, 2);
        cells[0] = .{ .sorted = constant };
        cells[1] = .{ .sorted = other };
        for ([_][]const u8{ "mid", "end", "uniform" }, 0..) |mode, j| try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "const{d}_{s}", .{ index, mode }), .cells = cells, .request = .{ .endpoints = j == 1, .mode = if (j == 2) .uniform else .key } });
    }
    var key: [21]f64 = undefined;
    var positive: [11]f64 = undefined;
    var negative: [11]f64 = undefined;
    for (&key, 0..) |*v, i| v.* = -1 + @as(f64, @floatFromInt(i)) / 10;
    for (&positive, &negative, 0..) |*p, *n, i| {
        p.* = 3 + @as(f64, @floatFromInt(i)) / 10;
        n.* = -4 + @as(f64, @floatFromInt(i)) / 10;
    }
    const windows = [_]binning.Cell{ .{ .sorted = &key }, .{ .sorted = &positive }, .{ .sorted = &negative } };
    for ([_]usize{ 3, 5, 6, 7, 9, 12 }, 0..) |limit, i| try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "limit{d}", .{i}), .cells = &windows, .request = .{ .max_nbin = limit } });
    for ([_]f64{ 1, 2, 3, 5 }, 0..) |limit, i| try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "limit{d}", .{i + 6}), .cells = &windows, .request = .{ .max_sigmas = limit } });
    const reversed = [_]binning.Cell{ .{ .sorted = &key }, .{ .sorted = &negative }, .{ .sorted = &positive } };
    const mixed = [_]binning.Cell{ .{ .sorted = &key }, .{ .sorted = &.{ -4, 4 } } };
    for (0..4) |i| {
        try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "reverse{d}", .{i}), .cells = &reversed, .request = .{ .max_nbin = if (i < 2) 7 else null, .max_sigmas = if (i >= 2) 3 else null, .endpoints = i != 0, .right = i == 3 } });
        try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "mixed{d}", .{i}), .cells = &mixed, .request = .{ .max_nbin = if (i < 2) 7 else null, .max_sigmas = if (i >= 2) 3 else null, .endpoints = i % 2 == 1 } });
    }
    const ties = [_]f64{ 0.2999999, 0.299999999999, 0.29999999999999, 0.3, 0.30000000000001, 0.300000000001, 0.3000001 };
    const tied = [_]binning.Cell{.{ .sorted = &ties }};
    for (0..3) |i| try cases.append(a, .{ .name = try std.fmt.allocPrint(a, "tie{d}", .{i}), .cells = &tied, .explicit = &.{ 0.1, 0.3, 0.5 }, .request = .{ .endpoints = i < 2, .right = i == 1 } });
    var compared: usize = 0;
    for (cases.items) |case| {
        const plan = try binning.determine(a, &d, case.cells, case.request);
        const options: Options = .{ .endpoint_labels = case.request.endpoints, .right = case.request.right, .clipped = plan.clipped, .bin_width = if (case.explicit.len > 1) case.explicit[1] - case.explicit[0] else plan.width };
        const keys: []const usize = if (case.cells.len > 1) &.{0} else &.{};
        const output = try create(a, &source, keys, options);
        const labels = [_][]const u8{ "A", "B", "C" };
        for (plan.cell_order) |index| try append(&d, output, &source, keys, &.{ .{ .str = labels[index] }, .{ .num = 0 } }, 1, case.cells[index].sorted, if (case.explicit.len > 0) case.explicit else plan.endpoints, options, null);
        var lines = std.mem.tokenizeScalar(u8, @embedFile("testdata/univ_histogram_bins_dev3.txt"), '\n');
        var j: usize = 0;
        while (lines.next()) |line| {
            if (line[0] == '#') continue;
            var fields = std.mem.splitScalar(u8, line, '|');
            if (!std.mem.eql(u8, fields.next().?, case.name)) continue;
            if (j >= output.rows.items.len) {
                std.debug.print("histogram missing {s} row {d}\n", .{ case.name, j });
                return error.TestUnexpectedResult;
            }
            const actual = output.rows.items[j];
            const group = fields.next().?;
            if (keys.len > 0) try std.testing.expectEqualStrings(group, actual[0].str);
            const at = keys.len;
            for (1..4) |offset| {
                const expected = try std.fmt.parseFloat(f64, fields.next().?);
                if (@abs(expected - actual[at + offset].num) > 1e-9) {
                    std.debug.print("histogram {s} row {d} field {d}: expected {d}, got {d}\n", .{ case.name, j, offset, expected, actual[at + offset].num });
                    return error.TestUnexpectedResult;
                }
            }
            j += 1;
            compared += 1;
        }
        if (j != output.rows.items.len) {
            std.debug.print("histogram row count {s}: expected {d}, got {d}\n", .{ case.name, j, output.rows.items.len });
            return error.TestUnexpectedResult;
        }
    }
    try std.testing.expectEqual(@as(usize, 833), compared);
}

test "dev3 output schema retains key attributes and constant failed-curve fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var source = Dataset.init(a, "d");
    _ = try source.addColumn("byid", .char);
    source.setLen("byid", 3);
    source.setFormat("byid", "$3.");
    source.setLabel("byid", "By label");
    _ = try source.addColumn("group", .char);
    source.setLen("group", 6);
    source.setLabel("group", "Class label");
    _ = try source.addColumn("abcdefghijklmnopq", .num);
    const opts: Options = .{ .variable_length = 17, .curve_columns = true, .endpoint_labels = true, .right = true };
    const output = try create(a, &source, &.{ 0, 1 }, opts);
    const names = [_][]const u8{ "byid", "group", "_VAR_", "_MAXPT_", "_OBSPCT_", "_COUNT_", "_CURVE_", "_EXPPCT_" };
    for (output.columns.items, names) |col, name| try std.testing.expectEqualStrings(name, col.name);
    try std.testing.expectEqualStrings("$3.", output.columns.items[0].format.?);
    try std.testing.expectEqualStrings("Class label", output.columns.items[1].label.?);
    try std.testing.expectEqual(@as(?usize, 17), output.columns.items[2].len);
    try std.testing.expectEqual(@as(?usize, 16), output.columns.items[6].len);
    try std.testing.expectEqualStrings("Right endpoint of Histogram Interval", output.columns.items[3].label.?);
    const edges = try binning.automatic(a, &d, &.{ 5, 5 }, true, true);
    try append(&d, output, &source, &.{ 0, 1 }, &.{ .{ .str = "B1" }, .{ .str = "A" }, .{ .num = 5 } }, 2, &.{ 5, 5 }, edges, opts, .{ .family = .normal, .p = .{ .mu = 5, .sigma = 1 } });
    try std.testing.expectEqual(@as(usize, 1), output.rows.items.len);
    const row = output.rows.items[0];
    try std.testing.expectEqual(@as(f64, 5), row[3].num);
    try std.testing.expectEqual(@as(f64, 100), row[4].num);
    try std.testing.expectEqual(@as(f64, 2), row[5].num);
    try std.testing.expectEqualStrings("", row[6].str);
    try std.testing.expect(row[7].isMissing());
}
