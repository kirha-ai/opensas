//! Numerical MIXED tables; input/model metadata belongs to the frontend.
const std = @import("std");
const math = @import("mixed_fit.zig");
const fmt = @import("../format.zig");
pub const NamedTest = struct { name: []const u8, num_df: usize, den_df: usize, f: f64, p: f64 };
pub const Options = struct { noitprint: bool = false, notest: bool = false };
pub fn render(a: std.mem.Allocator, out: *std.ArrayList(u8), fitted: math.Fit, covariance_names: []const []const u8, tests: []const NamedTest, options: Options) !void {
    if (covariance_names.len != fitted.variances.len) return error.InvalidInput;
    if (fitted.variances.len > 1 and !options.noitprint) {
        try out.appendSlice(a, "\nIteration History\n\nIteration Evaluations ");
        try out.appendSlice(a, if (fitted.method == .reml) "-2 Res Log Like Criterion\n" else "-2 Log Like Criterion\n");
        for (fitted.iterations) |row| {
            try out.print(a, "{d} {d} {d:.8}", .{ row.iteration, row.evaluations, row.objective });
            if (row.criterion) |criterion| try out.print(a, " {d:.8}", .{criterion});
            try out.append(a, '\n');
        }
        try out.appendSlice(a, if (fitted.converged) "\nConvergence criteria met.\n" else "\nConvergence criteria not met.\n");
    }
    try out.appendSlice(a, "\nCovariance Parameter Estimates\n\nCov Parm Estimate\n");
    for (covariance_names, fitted.variances) |name, value| try out.print(a, "{s} {d:.4}\n", .{ name, value });
    try out.appendSlice(a, "\nFit Statistics\n\n");
    try out.appendSlice(a, if (fitted.method == .reml) "-2 Res Log Likelihood " else "-2 Log Likelihood ");
    try out.print(a, "{d:.1}\nAIC (Smaller is Better) {d:.1}\nAICC (Smaller is Better) ", .{ fitted.minus2loglik, fitted.aic });
    if (fitted.aicc) |v| try out.print(a, "{d:.1}\n", .{v}) else try out.appendSlice(a, ".\n");
    try out.appendSlice(a, "BIC (Smaller is Better) ");
    if (fitted.bic) |v| try out.print(a, "{d:.1}\n", .{v}) else try out.appendSlice(a, ".\n");
    if (!options.notest) {
        try out.appendSlice(a, "\nType 3 Tests of Fixed Effects\n\nNum Den\nEffect DF DF F Value Pr > F\n");
        for (tests) |test_result| try out.print(a, "{s} {d} {d} {d:.2} {s}\n", .{ test_result.name, test_result.num_df, test_result.den_df, test_result.f, std.mem.trim(u8, try fmt.apply(a, .{ .num = test_result.p }, "pvalue6.4"), " ") });
    }
}
