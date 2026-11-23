//! Structured default UNIVARIATE tables; values arrive directly from computation.
const std = @import("std");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const fm = @import("ods_univ_formats.zig");
pub const Values = struct { sample: []const f64, left: [6]f64, right: [6]f64, quantiles: [11]f64, mode: f64 };
fn printed(a: std.mem.Allocator, x: f64) ![]const u8 {
    if (std.math.isNan(x)) return a.dupe(u8, ".");
    // SAS Moments uses BEST10. with eight fractional places at unit magnitude.
    const f = try @import("../format.zig").apply(a, b.n(x), "BEST10.");
    return std.mem.trim(u8, f, " ");
}
pub fn publish(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, ds: *Dataset, col: usize, by: []const usize, classes: []const usize, v: Values) diag.Error!void {
    if (ds.rows.items.len == 0 or v.left[0] == 0) return;
    const rep = ds.rows.items[0];
    const variable = ds.columns.items[col].name;
    if (capture.wants("Moments")) {
        var t = try b.Builder.init(a, ds, by, rep);
        t.ds.label = "Moments";
        try t.char("VarName", variable.len);
        try classSchema(&t, ds, classes);
        try t.char("Label1", 15);
        try t.char("cValue1", 10);
        try t.num("nValue1", "D12.3");
        try t.char("Label2", 16);
        try t.char("cValue2", 10);
        try t.num("nValue2", "D12.3");
        const left = [_][]const u8{ "N", "Mean", "Std Deviation", "Skewness", "Uncorrected SS", "Coeff Variation" };
        const right = [_][]const u8{ "Sum Weights", "Sum Observations", "Variance", "Kurtosis", "Corrected SS", "Std Error Mean" };
        for (left, right, v.left, v.right) |l, r, x, y| try addRow(&t, ds, classes, &.{ b.s(variable), b.s(l), b.s(try printed(a, x)), b.n(x), b.s(r), b.s(try printed(a, y)), b.n(y) });
        try capture.publish(a, d, "Moments", &t.ds);
    }
    if (capture.wants("Quantiles")) {
        var t = try b.Builder.init(a, ds, by, rep);
        t.ds.label = "Quantiles";
        try t.char("VarName", variable.len);
        try classSchema(&t, ds, classes);
        try t.char("Quantile", 10);
        try t.num("Estimate", try fm.measurement(a, v.sample));
        t.ds.setLabel("Quantile", "Level");
        t.ds.setLabel("Estimate", "Quantile");
        const labels = [_][]const u8{ "100% Max", "99%", "95%", "90%", "75% Q3", "50% Median", "25% Q1", "10%", "5%", "1%", "0% Min" };
        for (labels, v.quantiles) |l, x| try addRow(&t, ds, classes, &.{ b.s(variable), b.s(l), b.n(x) });
        try capture.publish(a, d, "Quantiles", &t.ds);
    }
    if (capture.wants("BasicMeasures")) {
        var t = try b.Builder.init(a, ds, by, rep);
        t.ds.label = "Basic Measures of Location and Variability";
        try t.char("VarName", variable.len);
        try classSchema(&t, ds, classes);
        try t.char("LocMeasure", 6);
        try t.num("LocValue", try fm.statistic(a, &.{ v.left[1], v.quantiles[5], v.mode }));
        try t.char("VarMeasure", 19);
        try t.num("VarValue", "D10.");
        t.ds.setLabel("LocMeasure", "Measure of Location");
        t.ds.setLabel("LocValue", "Value of Measure of Location");
        t.ds.setLabel("VarMeasure", "Measure of Variability");
        t.ds.setLabel("VarValue", "Value of Measure of Variability");
        const ll = [_][]const u8{ "Mean", "Median", "Mode", "" };
        const rr = [_][]const u8{ "Std Deviation", "Variance", "Range", "Interquartile Range" };
        const lv = [_]Value{ b.n(v.left[1]), b.n(v.quantiles[5]), b.n(v.mode), Value.specialMissing('_') };
        const rv = [_]f64{ v.left[2], v.right[2], v.quantiles[0] - v.quantiles[10], v.quantiles[4] - v.quantiles[6] };
        for (ll, rr, lv, rv) |l, r, x, y| try addRow(&t, ds, classes, &.{ b.s(variable), b.s(l), x, b.s(r), b.n(y) });
        try capture.publish(a, d, "BasicMeasures", &t.ds);
    }
}

fn classSchema(t: *b.Builder, ds: *Dataset, classes: []const usize) !void {
    for (classes) |ci| try t.char(ds.columns.items[ci].name, 16);
}
fn addRow(t: *b.Builder, ds: *Dataset, classes: []const usize, values: []const Value) !void {
    var cells: std.ArrayList(Value) = .empty;
    try cells.append(t.ds.arena, values[0]);
    for (classes) |ci| {
        const c = ds.columns.items[ci];
        const v = ds.rows.items[0][ci];
        const txt = if (v == .str) v.str else try @import("../format.zig").apply(t.ds.arena, v, c.format orelse "BEST12.");
        try cells.append(t.ds.arena, b.s(std.mem.trim(u8, txt, " ")));
    }
    try cells.appendSlice(t.ds.arena, values[1..]);
    try t.row(cells.items);
}

/// A procedure may supply multiple VAR, BY or CLASS groups to the same request.
pub const Context = struct {
    capture: *ods.Capture,
    diagnostics: *diag.Diagnostics,
    source: *Dataset,
    col: usize,
    by: []const usize,
    classes: []const usize,
    measure_format: []const u8,

    pub fn start(optional: ?Context, name: []const u8, label: []const u8) !?Table {
        const c = optional orelse return null;
        if (!c.capture.wants(name) or c.source.rows.items.len == 0) return null;
        const ds = c.source;
        const rep = ds.rows.items[0];
        const a = ds.arena;
        var t = try b.Builder.init(a, ds, c.by, rep);
        const variable = ds.columns.items[c.col].name;
        try t.char("VarName", variable.len);
        try classSchema(&t, ds, c.classes);
        t.ds.label = label;
        var prefix: std.ArrayList(Value) = .empty;
        try prefix.appendSlice(a, t.prefix);
        try prefix.append(a, b.s(variable));
        for (c.classes) |ci| {
            const value = rep[ci];
            const str = if (value == .str) value.str else try @import("../format.zig").apply(a, value, ds.columns.items[ci].format orelse "BEST12.");
            try prefix.append(a, b.s(std.mem.trim(u8, str, " ")));
        }
        t.prefix = prefix.items;
        return .{ .ctx = c, .builder = t, .name = name };
    }
};
pub const Table = struct {
    ctx: Context,
    builder: b.Builder,
    name: []const u8,

    pub fn num(t: *Table, name: []const u8, fmt: []const u8, label: []const u8) !void {
        try t.builder.num(name, fmt);
        if (label.len != 0) t.builder.ds.setLabel(name, label);
    }
    pub fn char(t: *Table, name: []const u8, len: usize, label: []const u8) !void {
        try t.builder.char(name, len);
        if (label.len != 0) t.builder.ds.setLabel(name, label);
    }
    pub fn row(t: *Table, cells: []const Value) !void {
        try t.builder.row(cells);
    }
    pub fn finish(t: *Table) !void {
        try t.ctx.capture.publish(t.builder.ds.arena, t.ctx.diagnostics, t.name, &t.builder.ds);
    }
};

pub fn locationTable(context: ?Context) !?Table {
    var t = (try Context.start(context, "TestsForLocation", "Tests for Location")) orelse return null;
    try t.char("Test", 11, "Test for Location");
    try t.char("Testlab", 1, "Label for Test Statistic");
    try t.num("Stat", "BEST8.", "Test Statistic");
    try t.char("pType", 9, "P Value Description");
    try t.num("pValue", "PVALUE6.4", "P Value");
    try t.num("Mu0", "BEST6.", "Mu0 Value");
    return t;
}

pub fn locationRow(t: *Table, test_name: []const u8, symbol: []const u8, stat: f64, ptype: []const u8, p: f64, mu0: f64) !void {
    try t.row(&.{ b.s(test_name), b.s(symbol), b.n(stat), b.s(ptype), b.n(p), b.n(mu0) });
}

pub const inference_names = [_][]const u8{ "TestsForLocation", "TestsForNormality", "RobustScale", "BasicIntervals", "LocationCounts", "ExtremeObs", "ExtremeValues", "Frequencies", "Modes" };
