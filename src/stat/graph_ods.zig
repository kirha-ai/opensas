//! ODS identities accompany native graph artifacts through listing selection.
const std = @import("std");
const pathPart = @import("../ods_listing.zig").pathPart;
const A = std.mem.Allocator;
pub const Name = enum { CDFPlot, PPPlot, QQPlot, ProbPlot, Histogram, ScatterPlot, FitPlot, IntPlot, MatrixPlot, FreqPlot, CumFreqPlot, DeviationPlot, MosaicPlot, AgreePlot, DiagnosticsPanel, ResidualPlot, RidgePanel, RidgePlot, VIFPlot };
pub const Object = struct { name: Name, label: []const u8, template: ?[]const u8, path: []const u8 };
pub fn known(name: []const u8) bool {
    for (std.meta.tags(Name)) |tag| if (std.ascii.eqlIgnoreCase(@tagName(tag), name)) return true;
    return false;
}
fn prefix(a: A, procedure: []const u8, by: ?usize) ![]const u8 {
    if (by) |group| return std.fmt.allocPrint(a, "{s}.ByGroup{d}", .{ procedure, group });
    return procedure;
}
pub fn univariate(a: A, name: Name, by: ?usize, variable: []const u8, panel: usize) !Object {
    const n = @tagName(name);
    return .{ .name = name, .label = try std.fmt.allocPrint(a, "Panel {d}", .{panel}), .template = try std.fmt.allocPrint(a, "base.univariate.Graphics.{s}", .{n}), .path = try std.fmt.allocPrint(a, "{s}.{s}.{s}.{s}", .{ try prefix(a, "Univariate", by), try pathPart(a, variable), n, n }) };
}
pub fn corr(a: A, name: Name, by: ?usize, label: []const u8) !Object {
    const n = @tagName(name);
    const group = if (name == .ScatterPlot) ".'Scatter Plots'n" else "";
    return .{ .name = name, .label = label, .template = try std.fmt.allocPrint(a, "Base.Corr.Graphics.{s}", .{n}), .path = try std.fmt.allocPrint(a, "{s}{s}.{s}", .{ try prefix(a, "Corr", by), group, n }) };
}
pub fn freq(a: A, name: Name, by: ?usize, table: usize, one: bool, dot: bool, stacked: bool) !Object {
    const n = @tagName(name);
    const group = if (one and (name == .FreqPlot or name == .CumFreqPlot)) ".OneWayFreqPlots" else "";
    const title = switch (name) {
        .FreqPlot => "Frequency Plot",
        .CumFreqPlot => "Cumulative Frequency Plot",
        .DeviationPlot => "Deviation Plot",
        .MosaicPlot => "Mosaic Plot",
        .AgreePlot => "Agreement Plot",
        else => unreachable,
    };
    // M9 uses different templates for different plot layouts. Supply the names
    // verified for bar charts and area plots; other layouts retain name and path.
    const template: ?[]const u8 = switch (name) {
        .MosaicPlot => "Base.Freq.Graphics.MosaicPlot",
        .AgreePlot => "Base.Freq.Graphics.AgreePlot",
        .DeviationPlot => if (dot) null else "Base.Freq.Graphics.OneWayDeviationChart",
        .FreqPlot, .CumFreqPlot => if (dot) null else if (one) "Base.Freq.Graphics.OneWayFreqChart" else if (stacked) "Base.Freq.Graphics.StackedFreqChart" else null,
        else => unreachable,
    };
    const path = try std.fmt.allocPrint(a, "{s}.Table{d}{s}.{s}", .{ try prefix(a, "Freq", by), table, group, n });
    return .{ .name = name, .label = title, .template = template, .path = path };
}
