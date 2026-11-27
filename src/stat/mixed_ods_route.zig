//! Real MIXED object identities and listing boundaries. Names/labels are from
//! S154 physical pp.6724-6726; nine default templates are verified by the
//! unchanged STAT-MIXED-016 SAS trace. Other template IDs remain unknown.
const std = @import("std");
const listing = @import("../ods_listing.zig");
pub const names = [_][]const u8{ "AccRates", "AsyCorr", "AsyCov", "Base", "Bound", "CholG", "CholR", "CholV", "ClassLevels", "Coef", "Contrasts", "ConvergenceStatus", "CorrB", "CovB", "CovParms", "Diffs", "Dimensions", "Estimates", "FitStatistics", "G", "GCorr", "HLM1", "HLM2", "HLM3", "HLPS1", "HLPS2", "HLPS3", "Influence", "InfoCrit", "InvCholG", "InvCholR", "InvCholV", "InvCovB", "InvG", "InvR", "InvV", "IterHistory", "LComponents", "LRT", "LSMeans", "MMEq", "MMEqSol", "ModelInfo", "NObs", "ParmSearch", "Posterior", "Ranks", "R", "RCorr", "Search", "Slices", "SolutionF", "SolutionR", "Tests1", "Tests2", "Tests3", "Type1", "Type2", "Type3", "Trans", "V", "VCorr" };
pub fn known(name: []const u8) bool {
    for (names) |n| if (std.ascii.eqlIgnoreCase(name, n)) return true;
    return false;
}
pub fn label(name: []const u8) []const u8 {
    const ids = [_][]const u8{ "ModelInfo", "ClassLevels", "Dimensions", "NObs", "IterHistory", "ConvergenceStatus", "CovParms", "FitStatistics", "Tests3", "ParmSearch", "LRT", "Type3", "Contrasts", "Estimates", "Influence" };
    const labels = [_][]const u8{ "Model Information", "Class Level Information", "Dimensions", "Number of Observations", "Iteration History", "Convergence Status", "Covariance Parameter Estimates", "Fit Statistics", "Type 3 Tests of Fixed Effects", "Parameter Search", "PARMS Model Likelihood Ratio Test", "Type 3 Analysis of Variance", "Contrasts", "Estimates", "Influence Diagnostics" };
    for (ids, labels) |id, text| if (std.ascii.eqlIgnoreCase(name, id)) return text;
    return name;
}
pub const Router = struct {
    selection: ?*const listing.Listing = null,
    prefix: []const u8 = "Mixed",
    visible: usize = 0,
    diags: ?*@import("../diag.zig").Diagnostics = null,
    converged: bool = true,
    pub fn finish(self: *Router, a: std.mem.Allocator, out: *std.ArrayList(u8), start: usize, name: []const u8) !void {
        if (out.items.len == start) return;
        const path = try std.fmt.allocPrint(a, "{s}.{s}", .{ self.prefix, name });
        if (self.selection) |selected| {
            if (!selected.accepts(path)) {
                out.shrinkRetainingCapacity(start);
                try self.statusNote(name);
                return;
            }
            const verified = for ([_][]const u8{ "ModelInfo", "ClassLevels", "Dimensions", "NObs", "IterHistory", "ConvergenceStatus", "CovParms", "FitStatistics", "Tests3" }) |id| {
                if (std.mem.eql(u8, name, id)) break true;
            } else false;
            try selected.traceObject(a, name, label(name), if (verified) try std.fmt.allocPrint(a, "Stat.Mixed.{s}", .{name}) else null, path);
        }
        try self.statusNote(name);
        self.visible += 1;
    }
    fn statusNote(self: Router, name: []const u8) !void {
        if (self.converged and std.mem.eql(u8, name, "ConvergenceStatus")) if (self.diags) |d| try d.note(0, "{s}", .{if (self.converged) @as([]const u8, "Convergence criteria met.") else "Convergence criteria not met."});
    }
};
