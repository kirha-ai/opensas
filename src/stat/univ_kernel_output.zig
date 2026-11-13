//! OUTKERNEL descriptors and evaluated grid values; no graph rendering.
const std = @import("std");
const kernel = @import("univ_kernel.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;

pub fn create(a: std.mem.Allocator, source: *Dataset, keys: []const usize, variable_length: usize, scale: kernel.VScale) !*Dataset {
    const output = try a.create(Dataset);
    output.* = Dataset.init(a, "");
    for (keys) |ci| _ = try output.addColumnLike(source.columns.items[ci].name, source.columns.items[ci]);
    for ([_][]const u8{ "_VAR_", "_TYPE_" }, [_][]const u8{ "Variable Name", "Kernel Function Type" }, [_]usize{ variable_length, 16 }) |name, label, length| {
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
        .count => "Number of Observations Per Data Unit",
    };
    for ([_][]const u8{ "_C_", "_VALUE_", scale_name, "_DENSITY_" }, [_][]const u8{ "Standardized Bandwidth Parameter", "Data Value", scale_label, "Density" }) |name, label| {
        _ = try output.addColumn(name, .num);
        output.setLen(name, 8);
        output.setLabel(name, label);
    }
    return output;
}

pub fn append(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, iqr: f64, request: kernel.Request, endpoints: []const f64, scale: kernel.VScale) diag.Error!void {
    const estimate = try kernel.fit(d, x, iqr, request);
    if (endpoints.len < 2) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTKERNEL needs a histogram range", .{});
    const first = @max(endpoints[0], request.lower orelse -std.math.inf(f64));
    const last = @min(endpoints[endpoints.len - 1], request.upper orelse std.math.inf(f64));
    const step = (x[x.len - 1] - x[0]) / 128;
    if (!(step > 0) or !(last > first)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid OUTKERNEL range", .{});
    const width = endpoints[1] - endpoints[0];
    try row(d, output, source, keys, representative, ci, x, estimate, first, width, scale);
    var index = @floor((first - x[0]) / step) + 1;
    var prior = first;
    while (true) : (index += 1) {
        const point = x[0] + index * step;
        if (point >= last) break;
        if (!(point > prior)) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTKERNEL range exceeds floating-point grid resolution", .{});
        try row(d, output, source, keys, representative, ci, x, estimate, point, width, scale);
        prior = point;
    }
    try row(d, output, source, keys, representative, ci, x, estimate, last, width, scale);
}

fn row(d: *diag.Diagnostics, output: *Dataset, source: *Dataset, keys: []const usize, representative: []const Value, ci: usize, x: []const f64, estimate: kernel.Estimate, point: f64, width: f64, scale: kernel.VScale) diag.Error!void {
    const values = try output.arena.alloc(Value, keys.len + 6);
    for (keys, 0..) |key, i| values[i] = representative[key];
    const at = keys.len;
    const density = try estimate.binnedDensity(x, point, d);
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
