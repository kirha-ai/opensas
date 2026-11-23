//! Numerical plot-consumer contract. A consumer must explicitly accept the
//! computed graph data; absence of a consumer preserves the graphics gap error.
const diag = @import("../diag.zig");
const dist = @import("univ_distributions.zig");
const Column = @import("../dataset.zig").Column;
const Value = @import("../value.zig").Value;
pub const Kind = enum { cdf, pp, qq, probability };
pub const Key = struct { column: Column, value: Value, display: []const u8, class: bool };
pub const Point = struct {
    x: f64,
    y: f64,
    observed: f64,
    /// Right-continuous EDF for CDFPLOT; ordered rank i/n for other plots.
    empirical_probability: f64,
    /// F(observation) for CDF/PP; adjusted plotting probability for QQ/PROBPLOT.
    theoretical_probability: f64,
    theoretical_quantile: ?f64 = null,
};
/// For QQ/PROBPLOT the reference is on the theoretical-quantile scale,
/// including Weibull2's logarithmic scale. PP uses probability coordinates.
pub const Reference = struct { intercept: f64, slope: f64 };
pub const Plot = struct {
    kind: Kind,
    variable: Column,
    keys: []const Key,
    distribution: dist.Distribution,
    points: []const Point,
    reference: ?Reference,
    rotated: bool = false,
    probability_scale: f64 = 1,
    weibull2: bool = false,
    cdf_overlay: bool = true,
    statement_index: usize = 0,
    by_index: usize = 0,
    curve_index: usize = 0,
};
pub const Sink = struct {
    enabled: bool = true,
    context: ?*anyopaque = null,
    emit: *const fn (?*anyopaque, Plot) diag.Error!void,
};

/// M9 plot tables and their rendered point cloud use the right endpoint of
/// each P-P tie. The numerical sink still exposes every source rank.
pub fn visiblePoint(plot: Plot, i: usize) bool {
    return (plot.kind != .pp and plot.kind != .cdf) or i + 1 == plot.points.len or plot.points[i].observed != plot.points[i + 1].observed;
}
