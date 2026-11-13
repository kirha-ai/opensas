//! Numerical distribution tables and typed ODS publication; no estimation here.
const std = @import("std");
const proc = @import("../proc.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const diag = @import("../diag.zig");
const fitting = @import("univ_distribution_fit.zig");
const dist = @import("univ_distributions.zig");
const values = @import("univ_distribution_values.zig");
const parse = @import("univ_distribution_parse.zig");
const moments = @import("univ_distribution_moments.zig");
const gof = @import("univ_distribution_gof.zig");
const b = @import("ods_table.zig");
const h = proc.UnivariateHelpers;
const Parameter = struct { name: []const u8, symbol: []const u8, value: f64 };

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

fn parameters(a: std.mem.Allocator, curve: dist.Distribution) ![]Parameter {
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
    distribution: []const u8,
    fn createTable(self: Context) !b.Builder {
        var table = try b.Builder.init(self.cx.arena, self.source, self.by, self.source.rows.items[0]);
        try table.char("VarName", self.source.columns.items[self.col].name.len);
        for (self.classes) |ci| try table.char(self.source.columns.items[ci].name, 16);
        try table.num("Histogram", null);
        try table.char("Distribution", self.distribution.len);
        return table;
    }
    fn row(self: Context, table: *b.Builder, cells: []const Value) !void {
        var values_: std.ArrayList(Value) = .empty;
        try values_.append(self.cx.arena, b.s(self.source.columns.items[self.col].name));
        for (self.classes) |ci| {
            const col = self.source.columns.items[ci];
            const value = self.source.rows.items[0][ci];
            const text = if (value == .str) value.str else try @import("../format.zig").apply(self.cx.arena, value, col.format orelse "BEST12.");
            try values_.append(self.cx.arena, b.s(std.mem.trim(u8, text, " ")));
        }
        try values_.appendSlice(self.cx.arena, &.{ b.n(@floatFromInt(self.histogram)), b.s(self.distribution) });
        try values_.appendSlice(self.cx.arena, cells);
        try table.row(values_.items);
    }
    fn publish(self: Context, name: []const u8, table: *b.Builder) !void {
        if (self.cx.capture) |capture| try capture.publish(self.cx.arena, self.cx.diags, name, &table.ds);
    }
};

pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), source: *Dataset, col: usize, by: []const usize, classes: []const usize, histogram: usize, x: []const f64, def: u8, curve: dist.Distribution, request: fitting.Request, options: parse.Curves, bins: []const values.Bin, right: bool, midpoints: bool) diag.Error!void {
    if (options.noprint) return;
    const a = cx.arena;
    const name = familyName(curve.family);
    const context: Context = .{ .cx = cx, .source = source, .col = col, .by = by, .classes = classes, .histogram = histogram, .distribution = name };
    const variable = source.columns.items[col].name;
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\nThe UNIVARIATE Procedure\nFitted {s} Distribution for {s}\n\nParameters for {s} Distribution\nParameter Symbol Estimate\n", .{ name, variable, name }));
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
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {s}\n", .{ p.name, p.symbol, try h.uNum(a, p.value) }));
    }
    try context.publish("ParameterEstimates", &parameter_table);
    // SAS does not offer EDF tables for Johnson distributions. For all other
    // families an unimplemented probability method must fail explicitly.
    if (curve.family != .sb and curve.family != .su and !(curve.family == .gamma and x.len < 10)) {
        const tests = try gof.compute(cx.diags, x, curve, request);
        var table = try context.createTable();
        table.ds.label = "Goodness-of-Fit Tests";
        try table.char("Test", 18);
        try table.char("TestLab", 6);
        try table.num("Stat", "D10.3");
        try table.char("pType", 11);
        try table.char("pSign", 1);
        try table.num("pValue", "5.3");
        table.ds.setLabel("Test", "Goodness-of-Fit Test");
        table.ds.setLabel("TestLab", "Label for Goodness-of-Fit Statistic");
        table.ds.setLabel("Stat", "Value of Goodness-of-Fit Statistic");
        table.ds.setLabel("pType", "p-value Label");
        table.ds.setLabel("pSign", "Sign of p-value");
        table.ds.setLabel("pValue", "p-value");
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nGoodness-of-Fit Tests for {s} Distribution\nTest Statistic p Value\n", .{name}));
        for ([_][]const u8{ "Kolmogorov-Smirnov", "Cramer-von Mises", "Anderson-Darling" }, [_][]const u8{ "D", "W-Sq", "A-Sq" }, [_][]const u8{ "Pr > D", "Pr > W-Sq", "Pr > A-Sq" }, [_]f64{ tests.statistics.d, tests.statistics.w2, tests.statistics.a2 }, [_]gof.Probability{ tests.d, tests.w2, tests.a2 }) |test_name, lab, ptype, statistic, probability| {
            const sign = switch (probability.sign) {
                .exact => "",
                .less => "<",
                .greater => ">",
            };
            try context.row(&table, &.{ b.s(test_name), b.s(lab), b.n(statistic), b.s(ptype), b.s(sign), b.n(probability.value) });
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{s} {s} {d:.8} {s} {s}{d:.3}\n", .{ test_name, lab, statistic, ptype, sign, probability.value }));
        }
        try context.publish("GoodnessOfFit", &table);
    }
    var quantiles = try context.createTable();
    quantiles.ds.label = "Quantiles";
    try quantiles.num("Percent", "4.1");
    try quantiles.num("ObsQuantile", "9.5");
    try quantiles.num("EstQuantile", "8.5");
    quantiles.ds.setLabel("ObsQuantile", "Observed Quantile");
    quantiles.ds.setLabel("EstQuantile", "Estimated Quantile");
    const pairs = try a.alloc(h.XW, x.len);
    for (x, pairs) |v, *p| p.* = .{ .x = v, .w = 1 };
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\nQuantiles for {s} Distribution\nPercent Observed Estimated\n", .{name}));
    for (options.percents) |percent| {
        const observed = h.univPercentile(pairs, percent, def);
        const estimated = curve.quantile(percent / 100);
        try context.row(&quantiles, &.{ b.n(percent), b.n(observed), b.n(estimated) });
        try out.appendSlice(a, try std.fmt.allocPrint(a, "{d:.1} {d:.5} {d:.5}\n", .{ percent, observed, estimated }));
    }
    try context.publish("FitQuantiles", &quantiles);
    if (options.midpercents) {
        var table = try context.createTable();
        table.ds.label = "Histogram Bin Percentages";
        const loc = if (midpoints) "MidPoint" else if (right) "MaxPoint" else "MinPoint";
        try table.num(loc, "3.");
        try table.num("ObsPercent", "6.3");
        try table.num("EstPercent", "6.3");
        table.ds.setLabel(loc, if (midpoints) "Bin Midpoint" else if (right) "Bin Maximum Point" else "Bin Minimum Point");
        table.ds.setLabel("ObsPercent", "Observed Percent");
        table.ds.setLabel("EstPercent", "Estimated Percent");
        try out.appendSlice(a, "\nHistogram Bin Percentages\nEndpoint Observed Estimated\n");
        for (bins) |bin| {
            const point = if (midpoints) bin.midpoint else if (right) bin.upper else bin.lower;
            try context.row(&table, &.{ b.n(point), b.n(bin.observed_percent), b.n(bin.expected_percent.?) });
            try out.appendSlice(a, try std.fmt.allocPrint(a, "{d} {d:.3} {d:.3}\n", .{ point, bin.observed_percent, bin.expected_percent.? }));
        }
        try context.publish("Bins", &table);
    }
}
