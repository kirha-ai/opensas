//! Structured default UNIVARIATE tables; values arrive directly from computation.
const std = @import("std");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
pub const Values = struct { left: [6]f64, right: [6]f64, quantiles: [11]f64, mode: f64 };
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
        try t.num("Estimate", null);
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
        try t.num("LocValue", null);
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
