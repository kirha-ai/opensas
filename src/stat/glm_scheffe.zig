//! GLM Scheffe adjustment: S154 physical p.4135 uses rank(L), not blindly k-1.
const std = @import("std");
const f = @import("../functions.zig");
const diag = @import("../diag.zig");
pub fn probability(t_value: f64, df: f64, rank: usize) diag.Error!f64 {
    if (rank == 0 or !(df > 0) or !std.math.isFinite(df) or std.math.isNan(t_value)) return error.ExecError;
    return f.betaI(df / (df + t_value * t_value), df / 2, @as(f64, @floatFromInt(rank)) / 2);
}
pub fn critical(df: f64, alpha: f64, rank: usize) diag.Error!f64 {
    if (rank == 0 or !(df > 0) or !std.math.isFinite(df) or !(alpha > 0 and alpha < 1)) return error.ExecError;
    const r: f64 = @floatFromInt(rank);
    const upper: f64 = 1e12;
    if (1 - alpha == 1 or f.betaI(df / (df + r * upper), df / 2, r / 2) > alpha) return error.ExecError;
    return @sqrt(r * f.bisectCdf(.f, 1 - alpha, r, df, 0, upper));
}
