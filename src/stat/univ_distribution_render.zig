//! Numerical distribution tables and typed ODS publication; no estimation here.
const std = @import("std");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fmt = @import("../format.zig");
const diag = @import("../diag.zig");
const fitting = @import("univ_distribution_fit.zig");
const dist = @import("univ_distributions.zig");
const values = @import("univ_distribution_values.zig");
const parse = @import("univ_distribution_parse.zig");
const moments = @import("univ_distribution_moments.zig");
const gof = @import("univ_distribution_gof.zig");
const b = @import("ods_table.zig");
const h = proc.UnivariateHelpers;
const listing = @import("../ods_listing.zig");
const Parameter = struct { name: []const u8, symbol: []const u8, value: f64 };

pub fn renderTrace(a: std.mem.Allocator, out: *std.ArrayList(u8), trace: fitting.Trace, report: fitting.Report) !void {
    if (trace.weibull.items.len > 0) {
        try out.appendSlice(a, "\nWeibull Optimization History\nPhase Iteration Theta Sigma C LogLikelihood\n");
        for (trace.weibull.items) |iteration| {
            const p = iteration.parameters;
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {d} {d:.8} {d:.8} {d:.8} {d:.8}\n", .{ @tagName(iteration.phase), iteration.iteration, p.theta, p.sigma, p.c, iteration.log_likelihood }));
        }
        try out.appendSlice(a, try std.fmt.allocPrint(a, "Optimization status: {s}{s}{s}\n", .{ if (report.converged) "converged" else "nonconverged", if (report.reason != null) " — " else "", report.reason orelse "" }));
        return;
    }
    try out.appendSlice(a, "\nOptimization Iteration History\nStart Iteration Theta Sigma Delta Gamma LogLikelihood\n");
    for (trace.iterations.items) |iteration| {
        const p = iteration.parameters;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{d} {d} {d:.8} {d:.8} {d:.8} {d:.8} {d:.8}\n", .{ iteration.start, iteration.iteration, p.theta, p.lambda, p.delta, p.gamma, iteration.log_likelihood }));
    }
    try out.appendSlice(a, try std.fmt.allocPrint(a, "Optimization status: {s}{s}{s}\n", .{ if (report.converged) "converged" else "nonconverged", if (report.reason != null) " — " else "", report.reason orelse "" }));
}

pub fn familyName(family: dist.Family) []const u8 {
    return switch (family) {
        .normal => "Normal",
        .lognormal => "Lognormal",
        .exponential => "Exponential",
        .gamma => "Gamma",
        .weibull => "Weibull",
        .beta => "Beta",
        .power => "Power Function",
        .rayleigh => "Rayleigh",
        .pareto => "Pareto",
        .gumbel => "Gumbel",
        .igauss => "Inverse Gaussian",
        .sb => "SB",
        .su => "SU",
    };
}

pub fn parameters(a: std.mem.Allocator, curve: dist.Distribution) ![]Parameter {
    var rows: std.ArrayList(Parameter) = .empty;
    const p = curve.p;
    if (curve.family == .normal) {
        try rows.appendSlice(a, &.{ .{ .name = "Mean", .symbol = "Mu", .value = p.mu }, .{ .name = "Std Dev", .symbol = "Sigma", .value = p.sigma } });
        return rows.items;
    }
    if (curve.family == .gumbel) {
        try rows.append(a, .{ .name = "Location", .symbol = "Mu", .value = p.mu });
    } else if (curve.family == .igauss) {
        try rows.append(a, .{ .name = "Threshold", .symbol = "Mu", .value = p.mu });
    } else try rows.append(a, .{ .name = if (curve.family == .su) "Location" else "Threshold", .symbol = "Theta", .value = p.theta });
    if (curve.family == .lognormal) {
        try rows.appendSlice(a, &.{ .{ .name = "Scale", .symbol = "Zeta", .value = p.zeta }, .{ .name = "Shape", .symbol = "Sigma", .value = p.sigma } });
    } else if (curve.family == .igauss) {
        try rows.append(a, .{ .name = "Shape", .symbol = "Lambda", .value = p.lambda });
    } else try rows.append(a, .{ .name = "Scale", .symbol = "Sigma", .value = p.sigma });
    switch (curve.family) {
        .gamma, .pareto, .power, .beta => try rows.append(a, .{ .name = "Shape", .symbol = "Alpha", .value = p.alpha }),
        .weibull => try rows.append(a, .{ .name = "Shape", .symbol = "C", .value = p.c }),
        .sb, .su => try rows.appendSlice(a, &.{ .{ .name = "Shape", .symbol = "Delta", .value = p.delta }, .{ .name = "Shape", .symbol = "Gamma", .value = p.gamma } }),
        else => {},
    }
    if (curve.family == .beta) try rows.append(a, .{ .name = "Shape", .symbol = "Beta", .value = p.beta });
    const m = moments.compute(curve);
    try rows.appendSlice(a, &.{ .{ .name = "Mean", .symbol = "", .value = m.mean }, .{ .name = "Std Dev", .symbol = "", .value = m.sd } });
    if (curve.family == .sb or curve.family == .su) try rows.appendSlice(a, &.{ .{ .name = "Skewness", .symbol = "", .value = m.skewness }, .{ .name = "Kurtosis", .symbol = "", .value = m.kurtosis }, .{ .name = "Mode", .symbol = "", .value = m.mode } });
    return rows.items;
}

const Context = struct {
    cx: proc.ProcCtx,
    source: *Dataset,
    col: usize,
    by: []const usize,
    classes: []const usize,
    histogram: usize,
    distribution: ?[]const u8,
    fn listingTables(self: Context, by_number: usize) !listing.Tables {
        const a = self.cx.arena;
        const variable = try listing.pathPart(a, self.source.columns.items[self.col].name);
        var path: std.ArrayList(u8) = .empty;
        try path.appendSlice(a, "Univariate.");
        if (self.by.len != 0) try path.print(a, "ByGroup{d}.", .{by_number});
        try path.print(a, "{s}.Histogram", .{variable});
        for (self.classes) |ci| try path.print(a, ".{s}", .{try listing.pathPart(a, try self.classValue(ci))});
        if (self.distribution) |name| {
            try path.append(a, '.');
            for (name) |ch| if (ch != ' ') {
                try path.append(a, ch);
            };
        }
        return .{ .selection = self.cx.listing, .prefix = path.items };
    }
    fn classHeading(self: Context, out: *std.ArrayList(u8)) !void {
        for (self.classes) |ci| try out.print(self.cx.arena, "{s} = {s}\n", .{ self.source.columns.items[ci].name, try self.classValue(ci) });
    }
    fn createTable(self: Context) !b.Builder {
        var table = try b.Builder.init(self.cx.arena, self.source, self.by, self.source.rows.items[0]);
        try table.char("VarName", self.source.columns.items[self.col].name.len);
        try table.num("Histogram", null);
        for (self.classes) |ci| try table.char(self.source.columns.items[ci].name, (try self.classValue(ci)).len);
        if (self.distribution) |name| try table.char("Distribution", name.len);
        return table;
    }
    fn classValue(self: Context, ci: usize) ![]const u8 {
        const col = self.source.columns.items[ci];
        const v = self.source.rows.items[0][ci];
        const text = if (v == .str and col.format == null) v.str else try fmt.apply(self.cx.arena, v, col.format orelse "BEST12.");
        return std.mem.trim(u8, text, " ");
    }
    fn row(self: Context, table: *b.Builder, cells: []const Value) !void {
        var values_: std.ArrayList(Value) = .empty;
        try values_.append(self.cx.arena, b.s(self.source.columns.items[self.col].name));
        try values_.append(self.cx.arena, b.n(@floatFromInt(self.histogram)));
        for (self.classes) |ci| try values_.append(self.cx.arena, b.s(try self.classValue(ci)));
        if (self.distribution) |name| try values_.append(self.cx.arena, b.s(name));
        try values_.appendSlice(self.cx.arena, cells);
        try table.row(values_.items);
    }
    fn publish(self: Context, name: []const u8, table: *b.Builder) !void {
        if (self.cx.capture) |capture| try capture.publish(self.cx.arena, self.cx.diags, name, &table.ds);
    }
};

pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), source: *Dataset, col: usize, by: []const usize, classes: []const usize, histogram: usize, x: []const f64, def: u8, curve: dist.Distribution, request: fitting.Request, options: parse.Curves, bins: []const values.Bin, right: bool, midpoints: bool, by_number: usize, supplied_tests: ?gof.Result) diag.Error!void {
    if (options.noprint) return;
    const a = cx.arena;
    const name = familyName(curve.family);
    const context: Context = .{ .cx = cx, .source = source, .col = col, .by = by, .classes = classes, .histogram = histogram, .distribution = name };
    const variable = source.columns.items[col].name;
    const tables = try context.listingTables(by_number);
    const head = out.items.len;
    try out.appendSlice(a, "\nThe UNIVARIATE Procedure\n");
    try context.classHeading(out);
    try out.print(a, "Fitted {s} Distribution for {s}\n", .{ name, variable });
    const first = out.items.len;
    var start = first;
    const prefix = if (curve.family == .sb or curve.family == .su) "Johnson " else "";
    try out.print(a, "\nParameters for {s}{s} Distribution\nParameter Symbol Estimate\n", .{ prefix, name });
    var parameter_table = try context.createTable();
    parameter_table.ds.label = "Parameters";
    try parameter_table.char("Parameter", 9);
    try parameter_table.char("Symbol", 6);
    try parameter_table.num("Estimate", "BEST8.");
    parameter_table.ds.setLabel("Parameter", "Distribution Parameter");
    parameter_table.ds.setLabel("Symbol", "Parameter Symbol");
    parameter_table.ds.setLabel("Estimate", "Parameter Estimate");
    for (try parameters(a, curve)) |p| {
        try context.row(&parameter_table, &.{ b.s(p.name), b.s(p.symbol), b.n(p.value) });
        try out.print(a, "{s} {s} {s}\n", .{ p.name, p.symbol, try fmt.bestNumW(a, p.value, 8) });
    }
    try context.publish("ParameterEstimates", &parameter_table);
    try tables.finish(a, out, start, "ParameterEstimates");
    start = out.items.len;
    // The inference helper owns parameter- and sample-dependent availability;
    // a blanket small-gamma guard would suppress valid all-known D/W2 tests.
    if (curve.family != .sb and curve.family != .su) {
        const tests = supplied_tests orelse try gof.computeWithSampler(cx.diags, x, curve, request, cx.univariate_edf_sampler);
        var table = try context.createTable();
        table.ds.label = "Goodness of Fit";
        try table.char("Test", 18);
        try table.char("TestLab", 6);
        var largest_stat: f64 = 0;
        if (tests.d != null) largest_stat = @max(largest_stat, tests.statistics.d);
        if (tests.w2 != null) largest_stat = @max(largest_stat, tests.statistics.w2);
        if (tests.a2 != null) largest_stat = @max(largest_stat, tests.statistics.a2);
        const decimals: usize = 9 -| decimalDigits(largest_stat);
        const statistic_format = try numberFormat(a, 10, decimals);
        try table.num("Stat", statistic_format);
        try table.char("pType", 11);
        try table.char("pSign", 1);
        try table.num("pValue", "5.3");
        table.ds.setLabel("Test", "Goodness-of-Fit Test");
        table.ds.setLabel("TestLab", "Label for Goodness-of-Fit Statistic");
        table.ds.setLabel("Stat", "Value of Goodness-of-Fit Statistic");
        table.ds.setLabel("pType", "p-value Label");
        table.ds.setLabel("pSign", "Sign of p-value");
        table.ds.setLabel("pValue", "p-value");
        if (tests.d != null or tests.w2 != null or tests.a2 != null) try out.appendSlice(a, try std.fmt.allocPrint(a, "\nGoodness-of-Fit Tests for {s} Distribution\nTest Statistic p Value\n", .{name}));
        for ([_][]const u8{ "Kolmogorov-Smirnov", "Cramer-von Mises", "Anderson-Darling" }, [_][]const u8{ "D", "W-Sq", "A-Sq" }, [_][]const u8{ "Pr > D", "Pr > W-Sq", "Pr > A-Sq" }, [_]f64{ tests.statistics.d, tests.statistics.w2, tests.statistics.a2 }, [_]?gof.Probability{ tests.d, tests.w2, tests.a2 }) |test_name, lab, ptype, statistic, maybe_probability| {
            const probability = maybe_probability orelse continue;
            const sign = switch (probability.sign) {
                .exact => "",
                .less => "<",
                .greater => ">",
            };
            try context.row(&table, &.{ b.s(test_name), b.s(lab), b.n(statistic), b.s(ptype), b.s(sign), b.n(probability.value) });
            try out.print(a, "{s} {s} {s} {s} {s}{d:.3}\n", .{ test_name, lab, try displayNumber(a, b.n(statistic), statistic_format), ptype, sign, probability.value });
        }
        if (table.ds.rows.items.len > 0) try context.publish("GoodnessOfFit", &table);
    }
    try tables.finish(a, out, start, "GoodnessOfFit");
    start = out.items.len;
    if (options.midpercents) {
        try renderBins(context, out, bins, right, midpoints);
        try tables.finish(a, out, start, "Bins");
        start = out.items.len;
    }
    var quantiles = try context.createTable();
    quantiles.ds.label = "Quantiles";
    try quantiles.num("Percent", "4.1");
    try quantiles.num("ObsQuantile", null);
    try quantiles.num("EstQuantile", null);
    var observed_range: QuantileRange = .{};
    var estimated_range: QuantileRange = .{};
    quantiles.ds.setLabel("ObsQuantile", "Observed Quantile");
    quantiles.ds.setLabel("EstQuantile", "Estimated Quantile");
    const pairs = try a.alloc(h.XW, x.len);
    for (x, pairs) |v, *p| p.* = .{ .x = v, .w = 1 };
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\nQuantiles for {s} Distribution\nPercent Observed Estimated\n", .{name}));
    for (options.percents) |percent| {
        const observed = h.univPercentile(pairs, percent, def);
        const estimated = curve.quantile(percent / 100);
        observed_range.add(observed);
        estimated_range.add(estimated);
        try context.row(&quantiles, &.{ b.n(percent), b.n(observed), b.n(estimated) });
    }
    const observed_format = try observed_range.format(a);
    const estimated_format = try estimated_range.format(a);
    quantiles.ds.setFormat("ObsQuantile", observed_format);
    quantiles.ds.setFormat("EstQuantile", estimated_format);
    const pct = quantiles.ds.indexOf("Percent").?;
    for (quantiles.ds.rows.items) |row| {
        try out.print(a, "{d:.1} {s} {s}\n", .{ row[pct].num, try displayNumber(a, row[pct + 1], observed_format), try displayNumber(a, row[pct + 2], estimated_format) });
    }
    try context.publish("FitQuantiles", &quantiles);
    try tables.finish(a, out, start, "FitQuantiles");
    if (out.items.len == first) out.shrinkRetainingCapacity(head);
}

const QuantileRange = struct {
    smallest: f64 = std.math.inf(f64),
    largest: f64 = 0,

    fn add(self: *QuantileRange, value: f64) void {
        if (!std.math.isFinite(value) or value == 0) return;
        self.smallest = @min(self.smallest, @abs(value));
        self.largest = @max(self.largest, @abs(value));
    }

    fn format(self: QuantileRange, a: std.mem.Allocator) ![]const u8 {
        if (self.largest == 0) return "8.5";
        const exponent: i32 = @intFromFloat(@floor(@log10(self.smallest)));
        const decimals: usize = @intCast(if (exponent < 0) @max(5, -exponent) else @max(0, 5 - exponent));
        const width = 1 + decimalDigits(self.largest) + decimals + @intFromBool(decimals != 0);
        if (width > 16) return "E15.8";
        return numberFormat(a, width, decimals);
    }
};

fn decimalDigits(magnitude: f64) usize {
    if (magnitude < 1 or !std.math.isFinite(magnitude)) return 1;
    return @intFromFloat(1 + @floor(@log10(magnitude)));
}

fn numberFormat(a: std.mem.Allocator, width: usize, decimals: usize) ![]const u8 {
    if (decimals == 0) return std.fmt.allocPrint(a, "{d}.", .{width});
    return std.fmt.allocPrint(a, "{d}.{d}", .{ width, decimals });
}

fn displayNumber(a: std.mem.Allocator, value: Value, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try fmt.apply(a, value, spec), " ");
}

fn binPoint(bin: values.Bin, right: bool, midpoints: bool) f64 {
    return if (midpoints) bin.midpoint else if (right) bin.upper else bin.lower;
}

fn pointFormat(a: std.mem.Allocator, bins: []const values.Bin, right: bool, midpoints: bool) ![]const u8 {
    var largest: f64 = 0;
    var precision: usize = 0;
    for (bins) |bin| {
        const point = @abs(binPoint(bin, right, midpoints));
        largest = @max(largest, point);
        var scaled = point;
        for (0..6) |places| {
            if (@abs(scaled - @round(scaled)) <= 32 * std.math.floatEps(f64) * @max(1, scaled)) {
                precision = @max(precision, places);
                break;
            }
            scaled *= 10;
        } else return "E15.8";
    }
    return numberFormat(a, 1 + decimalDigits(largest) + precision + @intFromBool(precision != 0), precision);
}

pub fn histogramBins(cx: proc.ProcCtx, out: *std.ArrayList(u8), source: *Dataset, col: usize, by: []const usize, classes: []const usize, histogram: usize, bins: []const values.Bin, right: bool, midpoints: bool, by_number: usize) !void {
    const context: Context = .{ .cx = cx, .source = source, .col = col, .by = by, .classes = classes, .histogram = histogram, .distribution = null };
    const tables = try context.listingTables(by_number);
    const start = out.items.len;
    try out.appendSlice(cx.arena, "\nThe UNIVARIATE Procedure\n");
    try context.classHeading(out);
    try out.print(cx.arena, "\nHistogram Bins for {s}\n", .{source.columns.items[col].name});
    try renderBins(context, out, bins, right, midpoints);
    try tables.finish(cx.arena, out, start, "HistogramBins");
}

fn renderBins(context: Context, out: *std.ArrayList(u8), bins: []const values.Bin, right: bool, midpoints: bool) !void {
    const a = context.cx.arena;
    const fitted = context.distribution != null;
    var table = try context.createTable();
    table.ds.label = if (fitted) "Histogram Bins" else "Bin Midpoints";
    const loc = if (midpoints) "Midpoint" else if (right) "MaxPoint" else "MinPoint";
    const point_format = try pointFormat(a, bins, right, midpoints);
    try table.num(loc, point_format);
    try table.num("ObsPercent", "6.3");
    table.ds.setLabel(loc, if (midpoints) "Bin Midpoint" else if (right) "Bin Maximum Point" else "Bin Minimum Point");
    table.ds.setLabel("ObsPercent", "Observed Percent");
    if (fitted) {
        try table.num("EstPercent", "6.3");
        table.ds.setLabel("EstPercent", "Estimated Percent");
    }
    const bin_label = if (midpoints) "Bin Midpoint" else if (right) "Bin Maximum Point" else "Bin Minimum Point";
    if (context.distribution) |name| {
        try out.print(a, "\nHistogram Bin Percents for {s} Distribution\n{s}  Observed Percent  Estimated Percent\n", .{ name, bin_label });
    } else try out.print(a, "{s}  Observed Percent\n", .{bin_label});
    for (bins) |bin| {
        const point = binPoint(bin, right, midpoints);
        // Standalone MIDPERCENTS includes the group's missing analysis values
        // in its denominator. Fitted Bins uses the sample that was fitted.
        const observed = if (fitted) bin.observed_percent else 100 * @as(f64, @floatFromInt(bin.count)) / @as(f64, @floatFromInt(context.source.rows.items.len));
        if (fitted) {
            try context.row(&table, &.{ b.n(point), b.n(observed), b.n(bin.expected_percent.?) });
            try out.print(a, "{s} {d:.3} {d:.3}\n", .{ try displayNumber(a, b.n(point), point_format), observed, bin.expected_percent.? });
        } else {
            try context.row(&table, &.{ b.n(point), b.n(observed) });
            try out.print(a, "{s} {d:.3}\n", .{ try displayNumber(a, b.n(point), point_format), observed });
        }
    }
    try context.publish(if (fitted) "Bins" else "HistogramBins", &table);
}
