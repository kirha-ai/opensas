//! Shared convergence semantics, SAS/STAT 15.4 physical pp.549–551.
//! The chapter's 0/1/2/3 values are examples, NOT a universal PROC mapping.
//! In particular its MIXED evaluation-limit example has Status=1, not 2.
//! ODS Status, diagnostic severity and the D-009 process exit are distinct.
const std = @import("std");

pub const Outcome = enum { converged, questionable, iteration_limit, evaluation_limit, infeasible, numerical_failure, evaluated, not_fitted };
pub const Estimates = enum { none, last_iterate, solution };
pub const State = struct {
    outcome: Outcome,
    /// Null means not applicable or not established for this procedure.
    /// Never replace it with an example code from the shared chapter.
    sas_status: ?u8 = null,
    estimates: Estimates,

    pub fn attained(self: State) bool {
        return self.outcome == .converged or self.outcome == .questionable;
    }
    pub fn nonclean(self: State) bool {
        return switch (self.outcome) {
            .converged, .evaluated, .not_fitted => false,
            else => true,
        };
    }
    /// Last-iterate inference is a procedure-specific policy: the LOGISTIC
    /// MAXITER reference prints it; MIXED has no equivalent verified contract.
    pub fn allowsInference(self: State, allow_last_iterate: bool) bool {
        return switch (self.estimates) {
            .none => false,
            .last_iterate => allow_last_iterate,
            .solution => true,
        };
    }
};

/// Invalid/nonfinite convergence metrics cannot certify a successful fit.
/// Callers retain their existing strict or inclusive comparison; this guard
/// does not change the procedure's metric, tolerance, or equality boundary.
pub fn meets(metric: ?f64, tolerance: f64, strict: bool) bool {
    const value = metric orelse return false;
    if (!std.math.isFinite(value) or value < 0 or !std.math.isFinite(tolerance) or tolerance <= 0) return false;
    return if (strict) value < tolerance else value <= tolerance;
}

test "COMMON033 documented codes are procedure specific and failed states never attain convergence" {
    const t = std.testing;
    const sample = [_]State{
        .{ .outcome = .converged, .sas_status = 0, .estimates = .solution },
        .{ .outcome = .questionable, .sas_status = 1, .estimates = .solution },
        .{ .outcome = .iteration_limit, .sas_status = 2, .estimates = .last_iterate },
        .{ .outcome = .numerical_failure, .sas_status = 3, .estimates = .none },
    };
    try t.expect(sample[0].attained() and !sample[0].nonclean());
    try t.expect(sample[1].attained() and sample[1].nonclean());
    for (sample[2..]) |state| try t.expect(!state.attained() and state.nonclean());
    // Published MIXED too-many-likelihood-evaluations example, physical550.
    const mixed: State = .{ .outcome = .evaluation_limit, .sas_status = 1, .estimates = .last_iterate };
    try t.expect(!mixed.attained() and mixed.nonclean());
    try t.expect(!mixed.allowsInference(false));
    try t.expect(mixed.allowsInference(true));
    const infeasible: State = .{ .outcome = .infeasible, .estimates = .none };
    try t.expect(!infeasible.attained() and infeasible.nonclean());
    try t.expect(infeasible.sas_status == null and !infeasible.allowsInference(true));
    for ([_]Outcome{ .evaluated, .not_fitted }) |outcome| {
        const state: State = .{ .outcome = outcome, .estimates = if (outcome == .evaluated) .solution else .none };
        try t.expect(!state.attained() and !state.nonclean());
        try t.expect(state.sas_status == null);
    }
}

test "COMMON033 nonfinite negative absent metrics cannot satisfy stopping criteria" {
    const t = std.testing;
    for ([_]?f64{ null, -1, std.math.nan(f64), std.math.inf(f64), -std.math.inf(f64) }) |metric| {
        try t.expect(!meets(metric, 1, true));
        try t.expect(!meets(metric, 1, false));
    }
    for ([_]f64{ 0, -1, std.math.nan(f64), std.math.inf(f64) }) |threshold| try t.expect(!meets(0, threshold, false));
    try t.expect(meets(0, 1e-8, true));
    try t.expect(!meets(1e-8, 1e-8, true));
    try t.expect(meets(1e-8, 1e-8, false));
}
