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
};
pub const Sink = struct {
    context: ?*anyopaque = null,
    emit: *const fn (?*anyopaque, Plot) diag.Error!void,
};
