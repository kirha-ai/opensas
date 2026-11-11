//! Execution bridge for one existing FREQ Table in one validated BY group.
//! The public driver retains dataset/format/weight/BY validation and table grids.
//! This module owns observed-stratum assembly, inference, and statistical listing.
const std = @import("std");
const diag = @import("../diag.zig");
const model = @import("freq_table.zig");
const k = @import("freq_stratified.zig");
const p = @import("freq_stratified_parse.zig");
const r = @import("freq_stratified_render.zig");
const common = @import("freq_stratified_risk.zig");
const risk = @import("freq_risk.zig");
const exact = @import("freq_exact_distribution.zig");
const callbacks = @import("freq_stratified_exact.zig");
const Value = @import("../value.zig").Value;
const A = std.mem.Allocator;
pub const Scope = struct {
    /// Already formatted by existing BY code; never re-sort or reinterpret it.
    by_label: ?[]const u8 = null,
    alpha: f64 = 0.05,
    tests: p.Tests = .{},
    inherited_risk_column: risk.Column = .first,
};
pub const Stratum = struct {
    id: usize,
    controls: []const Value,
    scored: model.ScoredMatrix,
    total: f64,
    trend: ?k.Normal = null,
    trend_eligible: bool = false,
    jt: ?k.Normal = null,
    symmetry: ?k.Chi = null,
    simple: ?k.Kappa = null,
    weighted: ?k.Kappa = null,
    details: ?k.AgreementDetails = null,
    weights: ?[]const f64 = null,
};
pub const Report = struct {
    by_label: ?[]const u8 = null,
    strata: []const Stratum = &.{},
    /// Positive, eligible strata in identical order to matrices/risk_tables.
    stratum_ids: []const usize = &.{},
    matrices: []const k.Matrix = &.{},
    risk_tables: []const risk.Table2x2 = &.{},
    cmh: [3]?k.Chi = .{ null, null, null },
    /// Mathematical score requirements, separate from SAS listing policy.
    cmh_score_eligible: [3]bool = .{ true, true, true },
    /// SAS omits the entire CMH ODS table on numeric missing TABLE scores in
    /// cmh_axes_ods.sas, even where a score-independent statistic is defined.
    /// This flag controls listing only, never per-kind computation eligibility.
    cmh_suppressed: bool = false,
    ratios: []const r.RatioRow = &.{},
    common_rows: []const r.CommonRow = &.{},
    common_weights: []const r.WeightRow = &.{},
    common_weight_ids: []const usize = &.{},
    control_names: []const []const u8 = &.{},
    pooled_simple: ?k.Pooled = null,
    pooled_weighted: ?k.Pooled = null,
    cochran: ?k.Chi = null,
    breslow_day: ?k.BreslowDay = null,
    qor: ?k.Chi = null,
    i_square: ?k.Heterogeneity = null,
    mantel_fleiss: ?f64 = null,
    gail_simon: ?k.GailSimon = null,
    negative_weights: bool = false,
};
fn any(options: p.Options) bool {
    return options.cmh > 0 or options.trend or options.jt or options.agreement.enabled or options.common.enabled or options.gail_simon;
}
fn methodSelected(method: common.Method, set: p.Methods) bool {
    return switch (method) {
        .mantel_haenszel => set.mh,
        .klingenberg => set.klingenberg,
        .minimum_risk => set.mr,
        .summary_score => set.score,
        .newcombe => set.newcombe,
        .newcombe_mr => set.newcombe_mr,
    };
}
fn label(a: A, v: Value) diag.Error![]const u8 {
    return switch (v) {
        .str => |s| s,
        .num => |n| if (std.math.isNan(n)) "." else try std.fmt.allocPrint(a, "{d}", .{n}),
    };
}
/// Arena-backed report. All returned arrays live in a; no borrowed temporary
/// buffers. PROC NOPRINT is handled in listing(), never suppresses computation.
pub fn compute(a: A, d: *diag.Diagnostics, table: *const model.Table, options: p.Options, scope: Scope) diag.Error!Report {
    var result = Report{ .by_label = scope.by_label };
    if (!any(options)) return result;
    if (!(scope.alpha > 0 and scope.alpha < 1)) return d.fail(error.ExecError, 0, "PROC FREQ: ALPHA must be between zero and one", .{});
    if (table.negative) {
        result.negative_weights = true;
        try d.report(.note, 0, "PROC FREQ: statistics are not computed when there are negative weights", .{});
        return result;
    }
    const n = table.dimensions.len;
    if (n < 2) {
        try d.report(.note, 0, "PROC FREQ: stratified statistics require a two-way or multiway table", .{});
        return result;
    }
    const control_names = try a.alloc([]const u8, n - 2);
    for (control_names, table.dimensions[0 .. n - 2]) |*name, dim| name.* = dim.name;
    result.control_names = control_names;
    const nr = table.dimensions[n - 2].levels.len;
    const nc = table.dimensions[n - 1].levels.len;
    const size = std.math.mul(usize, nr, nc) catch return error.OutOfMemory;
    if (size == 0) return result;
    // Table.keys is sorted by the table's existing dimension order. Never
    // enumerate cell_count/(rows*cols): many binary dimensions stay sparse.
    const keys = try table.keys(a, false, true);
    var ids: std.ArrayList(usize) = .empty;
    for (keys) |key| {
        if (key >= table.cell_count) return d.fail(error.ExecError, 0, "PROC FREQ: cell key outside table dimensions", .{});
        var missing_control = false;
        for (0..n - 2) |j| if (!table.include_missing and table.level(key, j).missing) {
            missing_control = true;
        };
        if (missing_control) continue;
        const id = key / size;
        if (ids.items.len == 0 or ids.items[ids.items.len - 1] != id) try ids.append(a, id);
    }
    var strata: std.ArrayList(Stratum) = .empty;
    var matrices: std.ArrayList(k.Matrix) = .empty;
    var active_ids: std.ArrayList(usize) = .empty;
    var risk_tables: std.ArrayList(risk.Table2x2) = .empty;
    var simple: std.ArrayList(?k.Estimate) = .empty;
    var weighted: std.ArrayList(?k.Estimate) = .empty;
    var row_scores_valid = true;
    var col_scores_valid = true;
    for (ids.items) |id| {
        const slice = try table.slice(a, id);
        const scored = (try slice.matrix(a, table.score_kind)).?;
        const m = scored.matrix;
        const controls = try a.alloc(Value, n - 2);
        for (controls, 0..) |*v, j| v.* = table.level(id * size, j).value;
        var s = Stratum{ .id = id, .controls = controls, .scored = scored, .total = slice.total };
        // Keep observed zero strata in metadata, but do not feed NaN RIDIT
        // scores from empty margins into inference or exact reference sets.
        if (slice.total > 0 and m.rows > 0 and m.cols > 0) {
            try matrices.append(a, m);
            try active_ids.append(a, id);
            if (m.rows == 2 and m.cols == 2) try risk_tables.append(a, .{ .cells = .{ m.counts[0], m.counts[1], m.counts[2], m.counts[3] } });
            const row_valid = table.score_kind != .table or model.validNumericScores(scored.row_levels);
            const col_valid = table.score_kind != .table or model.validNumericScores(scored.col_levels);
            row_scores_valid = row_scores_valid and row_valid;
            col_scores_valid = col_scores_valid and col_valid;
            s.trend_eligible = if (m.cols == 2) row_valid else m.rows == 2 and col_valid;
            if (options.trend and s.trend_eligible) s.trend = try k.trend(m);
            if (options.jt) s.jt = try k.jonckheere(a, m);
            if (options.agreement.enabled and m.rows == m.cols and m.rows > 1) {
                s.symmetry = if (m.rows == 2) try k.mcnemar(m, options.agreement.null_ratio) else try k.bowker(m, options.agreement.df);
                s.simple = try k.kappa(a, m, .simple, scope.alpha, options.agreement.null_kappa orelse 0);
                s.details = try k.agreementDetails(a, m, scope.alpha);
                if (m.rows > 2 and col_valid) {
                    // Invalid nonmonotone kappa weights are a true SAS error;
                    // retain simple agreement and JT, emit a captured diagnostic.
                    s.weights = k.kappaWeights(a, m, options.agreement.weight) catch |err| blk: {
                        if (err == error.OutOfMemory) return err;
                        try d.report(.err, 0, "To compute the weighted kappa coefficient, weights must be between 0 and 1.", .{});
                        break :blk null;
                    };
                    if (s.weights != null) s.weighted = try k.kappa(a, m, options.agreement.weight, scope.alpha, options.agreement.null_weighted orelse 0);
                }
                try simple.append(a, if (s.simple) |v| v.coefficient else null);
                try weighted.append(a, if (s.weighted) |v| v.coefficient else null);
            }
        }
        try strata.append(a, s);
    }
    result.strata = try strata.toOwnedSlice(a);
    result.matrices = try matrices.toOwnedSlice(a);
    result.stratum_ids = try active_ids.toOwnedSlice(a);
    result.risk_tables = try risk_tables.toOwnedSlice(a);
    const numeric_scores_valid = row_scores_valid and col_scores_valid;
    if (!numeric_scores_valid) try d.report(.warning, 0, "Some statistics are not computed because there is no valid numeric table score for the missing values.", .{});
    result.cmh_score_eligible = .{ row_scores_valid and col_scores_valid, col_scores_valid, true };
    result.cmh_suppressed = !numeric_scores_valid;
    if (result.matrices.len > 0) {
        for ([_]k.CmhKind{ .correlation, .row_mean, .general }, 0..) |kind, i| {
            if (i < options.cmh and result.cmh_score_eligible[i]) result.cmh[i] = try k.cmh(a, result.matrices, kind);
        }
    }
    if (options.agreement.enabled and n > 2) {
        result.pooled_simple = try k.poolKappa(simple.items, scope.alpha);
        result.pooled_weighted = try k.poolKappa(weighted.items, scope.alpha);
        var binary = true;
        for (table.dimensions) |dimension| {
            var levels: usize = 0;
            for (dimension.levels) |v| {
                if (table.include_missing or !v.missing) levels += 1;
            }
            binary = binary and levels == 2;
        }
        if (binary) {
            var accumulator = try k.CochranAccumulator.init(a, n);
            defer accumulator.deinit(a);
            const first = try a.alloc(bool, n);
            for (keys) |key| {
                if (table.excluded(key)) continue;
                for (table.dimensions, 0..) |dimension, j| {
                    var index: usize = 0;
                    while (index < dimension.levels.len and !table.include_missing and dimension.levels[index].missing) : (index += 1) {}
                    first[j] = (key / table.strides[j]) % dimension.levels.len == index;
                }
                try accumulator.add(first, table.count(key));
            }
            result.cochran = try accumulator.finish();
        }
    }
    if (result.risk_tables.len == 0 or result.risk_tables.len != result.matrices.len) return result;
    if (options.cmh > 0) {
        const mh = try k.mantelHaenszelRatios(result.matrices, scope.alpha);
        const odds = try common.logit(a, result.risk_tables, .first, .odds_ratio, scope.alpha);
        const rr1 = try common.logit(a, result.risk_tables, .first, .relative_risk, scope.alpha);
        const rr2 = try common.logit(a, result.risk_tables, .second, .relative_risk, scope.alpha);
        const rows = try a.alloc(r.RatioRow, 3);
        const values = [3]?common.Logit{ odds, rr1, rr2 };
        const mh_values = [3]?k.Ratio{ mh.odds, mh.column1, mh.column2 };
        for (rows, values, mh_values, [_][]const u8{ "Odds Ratio", "Relative Risk (Column 1)", "Relative Risk (Column 2)" }) |*row, logit, mh_value, name| {
            var corrected = false;
            if (logit) |v| for (v.corrected) |c| {
                corrected = corrected or c;
            };
            row.* = .{ .label = name, .mh = mh_value, .logit = if (logit) |v| v.ratio else null, .corrected = corrected };
        }
        result.ratios = rows;
        if (mh.odds) |v| result.breslow_day = try k.breslowDay(result.matrices, v.value);
        if (options.mantel_fleiss) result.mantel_fleiss = try k.mantelFleiss(result.matrices);
        if (options.qor or options.i2) {
            result.qor = if (odds) |v| v.homogeneity else null;
            if (options.i2 and result.qor != null) result.i_square = try k.iSquare(result.qor.?, scope.alpha);
        }
    }
    if (options.gail_simon) result.gail_simon = try common.gailSimon(a, result.risk_tables, options.gail_column);
    if (options.common.enabled) {
        const limits = options.common.selectedLimits();
        const tests = options.common.selectedTests();
        const weights = options.common.selectedWeights();
        var rows: std.ArrayList(r.CommonRow) = .empty;
        const column = options.common.column orelse scope.inherited_risk_column;
        const methods = [_]common.Method{ .klingenberg, .mantel_haenszel, .minimum_risk, .newcombe, .newcombe_mr, .summary_score };
        for (methods) |method| if (methodSelected(method, limits) or methodSelected(method, tests) or methodSelected(method, weights)) {
            try rows.append(a, .{ .method = method, .result = try common.commonDifference(a, result.risk_tables, method, .{ .column = column, .alpha = scope.alpha, .correct = options.common.correct, .sample_variance = options.common.sample_variance }) });
        };
        result.common_rows = try rows.toOwnedSlice(a);
        var weight_rows: std.ArrayList(r.WeightRow) = .empty;
        var weight_ids: std.ArrayList(usize) = .empty;
        var total: f64 = 0;
        for (result.risk_tables) |t| for (t.cells) |v| {
            total += v;
        };
        for (result.risk_tables, result.stratum_ids, 0..) |t, id, i| {
            const samples = t.samples(column);
            const count = samples[0].total + samples[1].total;
            if (samples[0].total == 0 or samples[1].total == 0) continue;
            try weight_ids.append(a, id);
            const control_labels = try a.alloc([]const u8, n - 2);
            for (control_labels, 0..) |*name, j| name.* = try label(a, table.level(id * size, j).value);
            var row: r.WeightRow = .{ .controls = control_labels, .stratum = try std.fmt.allocPrint(a, "{d}", .{weight_rows.items.len + 1}), .difference = if (samples[0].total > 0 and samples[1].total > 0) samples[0].proportion() - samples[1].proportion() else null, .frequency = count, .fraction = count / total };
            for (result.common_rows) |computed| if (computed.result) |v| switch (computed.method) {
                .mantel_haenszel => row.mh = v.weights[i],
                .minimum_risk => row.mr = v.weights[i],
                .summary_score => {
                    row.score = v.weights[i];
                    row.score_midpoint = v.components[i];
                },
                else => {},
            };
            try weight_rows.append(a, row);
        }
        result.common_weights = try weight_rows.toOwnedSlice(a);
        result.common_weight_ids = try weight_ids.toOwnedSlice(a);
    }
    return result;
}

/// Per-stratum matrices retain global level slots, immutable scores, and IDs.
/// dev3 owns enumeration choice (fixed margins vs discordant pairs vs joint).
pub const ExactInput = struct { stratum_id: usize, matrix: exact.Matrix, context: callbacks.Context };
pub fn exactInputs(a: A, report: Report, family: callbacks.Family, null_ratio: f64) diag.Error![]ExactInput {
    const result = try a.alloc(ExactInput, report.matrices.len);
    for (result, report.matrices, report.stratum_ids) |*entry, m, id| {
        const cells = try a.alloc(u32, m.counts.len);
        for (cells, m.counts) |*cell, count| cell.* = try @import("freq_exact.zig").integerCount(count);
        var weights: ?[]const f64 = null;
        if (family == .weighted_kappa) for (report.strata) |s| if (s.id == id) {
            weights = s.weights;
            break;
        };
        entry.* = .{ .stratum_id = id, .matrix = .{ .rows = m.rows, .cols = m.cols, .cells = cells }, .context = try callbacks.Context.init(m, family, weights, null_ratio) };
    }
    return result;
}

/// Direct input for dev3 freq_exact_execute.runStrata (COMOR/EQOR). The
/// public exact owner retains family selection, budgets, deadlines and rendering.
pub fn jointMatrices(a: A, report: Report) diag.Error![]@import("freq_tests.zig").CountMatrix {
    const result = try a.alloc(@import("freq_tests.zig").CountMatrix, report.matrices.len);
    for (result, report.matrices) |*out, m| {
        if (m.rows != 2 or m.cols != 2) return error.ExecError;
        out.* = .{ .rows = m.rows, .cols = m.cols, .counts = m.counts, .row_scores = m.row_scores, .col_scores = m.col_scores };
    }
    return result;
}

/// Statistical listing only. TABLES NOPRINT does not suppress this output;
/// PROC NOPRINT does. Caller interleaves renderStratum with existing table grids.
pub fn renderStratum(a: A, out: *std.ArrayList(u8), s: Stratum, options: p.Options, scope: Scope) diag.Error!void {
    if (s.total <= 0) return;
    if (options.trend and s.trend_eligible) try r.ordered(a, out, s.trend, false);
    if (options.jt) try r.ordered(a, out, s.jt, true);
    if (!options.agreement.enabled or s.scored.matrix.rows != s.scored.matrix.cols or s.scored.matrix.rows < 2) return;
    const ag = options.agreement;
    const two = s.scored.matrix.rows == 2;
    if (two) try r.mcnemar(a, out, s.symmetry, ag.null_ratio, ag.restore) else try r.chiSquare(a, out, "Symmetry Test", s.symmetry, ag.restore);
    try r.kappa(a, out, "Simple Kappa Coefficient", if (s.simple) |v| v.coefficient else null, scope.alpha, ag.restore);
    if (!two) try r.kappa(a, out, "Weighted Kappa Coefficient", if (s.weighted) |v| v.coefficient else null, scope.alpha, ag.restore);
    if (s.details) |details| {
        if (ag.pabak) try r.kappa(a, out, "P-B Adjusted Kappa", details.pabak, scope.alpha, ag.restore);
        if (ag.ac1) try r.kappa(a, out, "Chance-Corrected AC1", details.ac1, scope.alpha, ag.restore);
        try r.agreementDetails(a, out, details, s.weighted, ag.details, ag.weighted_details and !two);
    }
    if (scope.tests.kappa or ag.null_kappa != null) try r.kappaTest(a, out, "Kappa Test", s.simple, ag.null_kappa orelse 0);
    if (!two and (scope.tests.weighted_kappa or ag.null_weighted != null)) try r.kappaTest(a, out, "Weighted Kappa Test", s.weighted, ag.null_weighted orelse 0);
    if (ag.print_weights and !two and s.weights != null) {
        const labels = try a.alloc([]const u8, s.scored.col_levels.len);
        for (labels, s.scored.col_levels) |*name, level| name.* = try label(a, level.value);
        try r.kappaWeights(a, out, labels, s.weights.?);
    }
}
pub fn renderSummary(a: A, out: *std.ArrayList(u8), report: Report, options: p.Options, scope: Scope, score: model.Score) diag.Error!void {
    if (report.negative_weights or report.matrices.len == 0) return;
    if (options.cmh > 0 and report.matrices.len > 0) {
        if (!report.cmh_suppressed) try r.cmh(a, out, report.cmh, options.cmh, switch (score) {
            .table => "Table Scores",
            .rank => "Rank Scores",
            .ridit => "Ridit Scores",
            .modridit => "Modified Ridit Scores",
        });
        if (options.mantel_fleiss) try r.mantelFleiss(a, out, report.mantel_fleiss);
        if (report.ratios.len > 0) try r.ratios(a, out, report.ratios, scope.alpha);
        if (report.breslow_day) |v| try r.chiSquare(a, out, if (options.bdt) "Breslow-Day-Tarone Test for Homogeneity of Odds Ratios" else "Breslow-Day Test for Homogeneity of Odds Ratios", if (options.bdt) v.tarone else v.unadjusted, false);
        if (options.qor) try r.chiSquare(a, out, "Q Test for Homogeneity of Odds Ratios", report.qor, false);
        if (options.i2) try r.heterogeneity(a, out, report.i_square, if (report.qor) |v| v.df else null, scope.alpha);
    }
    if (options.gail_simon and report.gail_simon != null) try r.gailSimon(a, out, report.gail_simon);
    if (options.common.enabled) {
        try r.common(a, out, report.common_rows, options.common, scope.alpha, if ((options.common.column orelse scope.inherited_risk_column) == .first) "Column 1 (c = 1)" else "Column 2 (c = 2)");
        try r.commonWeightsWithControls(a, out, report.common_weights, options.common.selectedWeights(), report.control_names);
    }
    inline for (.{ false, true }) |weighted| {
        const pooled = if (weighted) report.pooled_weighted else report.pooled_simple;
        if (pooled) |v| {
            try r.kappa(a, out, if (weighted) "Overall Weighted Kappa Coefficient" else "Overall Kappa Coefficient", v.coefficient, scope.alpha, options.agreement.restore);
            try r.chiSquare(a, out, if (weighted) "Test for Equal Weighted Kappas" else "Test for Equal Kappas", v.homogeneity, options.agreement.restore);
        }
    }
    if (report.cochran) |q| try r.chiSquare(a, out, "Cochran's Q", q, options.agreement.restore);
}
pub fn listing(a: A, out: *std.ArrayList(u8), report: Report, options: p.Options, scope: Scope, score: model.Score, proc_noprint: bool) diag.Error!void {
    if (proc_noprint or report.negative_weights or report.matrices.len == 0) return;
    if (report.by_label) |by| try out.appendSlice(a, try std.fmt.allocPrint(a, "{s}\n", .{by}));
    for (report.strata) |s| {
        if (s.total <= 0) continue;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nStatistics for Stratum {d}\n", .{s.id + 1}));
        for (s.controls) |v| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{try label(a, v)}));
        try out.append(a, '\n');
        try renderStratum(a, out, s, options, scope);
    }
    try renderSummary(a, out, report, options, scope, score);
}

fn binaryTable(a: A, variables: usize) !model.Table {
    const dims = try a.alloc(model.Dimension, variables);
    for (dims, 0..) |*dimension, i| {
        const levels = try a.alloc(model.Level, 2);
        for (levels, 0..) |*level, j| {
            const v: f64 = @floatFromInt(j + 1);
            level.* = .{ .value = .{ .num = v }, .raw = .{ .num = v }, .missing = false, .frequency = 0 };
        }
        dimension.* = .{ .name = try std.fmt.allocPrint(a, "v{d}", .{i}), .levels = levels };
    }
    return model.Table.init(a, dims, false);
}
test "stratified execution assembles common risk CMH and BY reports" {
    // Published migraine example3.7 and common.sas alpha=.1. The public driver
    // constructs each BY group's Table; this test exercises that exact boundary.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var table = try binaryTable(a, 3);
    for ([_]f64{ 16, 11, 5, 20, 12, 16, 7, 19 }, 0..) |v, i| try table.add(a, i, v);
    var d = diag.Diagnostics.init(a);
    const options = p.Options{ .cmh = 3, .bdt = true, .qor = true, .i2 = true, .mantel_fleiss = true, .gail_simon = true, .agreement = .{ .enabled = true }, .common = .{ .enabled = true, .limits = .{ .mh = true, .mr = true, .score = true, .newcombe = true, .newcombe_mr = true, .klingenberg = true }, .test_default = true, .print_default = true } };
    const scope = Scope{ .by_label = "site=A", .alpha = 0.1 };
    const report = try compute(a, &d, &table, options, scope);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqualStrings("site=A", report.by_label.?);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, report.stratum_ids);
    try std.testing.expectApproxEqAbs(@as(f64, 8.3052), report.cmh[0].?.statistic, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 3.3132), report.ratios[0].mh.?.value, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 1.4905), report.breslow_day.?.tarone.statistic, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 19.2443), report.mantel_fleiss.?, 0.00005);
    try std.testing.expectEqual(@as(usize, 6), report.common_rows.len);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5158), report.common_weights[0].score.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.3738), report.common_weights[0].score_midpoint.?, 0.00005);
    var out: std.ArrayList(u8) = .empty;
    try listing(a, &out, report, options, scope, .table, true);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try listing(a, &out, report, options, scope, .table, false);
    for ([_][]const u8{ "site=A", "8.3052", "Common Risk Difference", "0.2738", "0.1250", "0.5158" }) |s| try std.testing.expect(std.mem.indexOf(u8, out.items, s) != null);
    const reverse = try compute(a, &d, &table, .{ .common = .{ .enabled = true, .limits = .{ .mh = true } } }, .{ .by_label = "site=B", .inherited_risk_column = .second });
    try std.testing.expectEqualStrings("site=B", reverse.by_label.?);
    try std.testing.expectApproxEqAbs(@as(f64, -0.2738), reverse.common_rows[0].result.?.value, 0.00005);
    try std.testing.expectEqualStrings("site=A", report.by_label.?);
    const exact_rows = try exactInputs(a, report, .mhchi, 1);
    try std.testing.expectEqual(@as(usize, 1), exact_rows[1].stratum_id);
    try std.testing.expectEqualSlices(u32, &.{ 12, 16, 7, 19 }, exact_rows[1].matrix.cells);
    const ctx = [_]callbacks.Context{ exact_rows[0].context, exact_rows[1].context };
    const sampled = [_]exact.Matrix{ exact_rows[0].matrix, exact_rows[1].matrix };
    try std.testing.expectApproxEqAbs(@as(f64, 8.3052), try callbacks.Adapters(exact).cmhCorrelation(&ctx, &sampled), 0.00005);
}

test "stratified execution missing controls zero strata and negative weights" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var table = try binaryTable(a, 3);
    const levels = try a.alloc(model.Level, 4);
    levels[0] = .{ .value = .{ .num = std.math.nan(f64) }, .raw = .{ .num = std.math.nan(f64) }, .missing = true, .frequency = 0 };
    for (levels[1..], 0..) |*v, i| {
        const n: f64 = @floatFromInt(i + 1);
        v.* = .{ .value = .{ .num = n }, .raw = .{ .num = n }, .missing = false, .frequency = 0 };
    }
    table.dimensions[0].levels = levels;
    table = try model.Table.init(a, table.dimensions, false);
    table.score_kind = .ridit;
    try table.add(a, 0, 1000); // excluded missing-control stratum
    for ([_]f64{ 16, 11, 5, 20 }, 0..) |v, i| try table.add(a, 4 + i, v);
    try table.add(a, 8, 0); // observed empty stratum retains its identity
    for ([_]f64{ 12, 16, 7, 19 }, 0..) |v, i| try table.add(a, 12 + i, v);
    const report = try compute(a, &d, &table, .{ .cmh = 3, .agreement = .{ .enabled = true } }, .{});
    try std.testing.expectEqual(@as(usize, 3), report.strata.len);
    try std.testing.expectEqual(@as(f64, 0), report.strata[1].total);
    try std.testing.expectEqualSlices(usize, &.{ 1, 3 }, report.stratum_ids);
    try std.testing.expectApproxEqAbs(@as(f64, 8.3052), report.cmh[2].?.statistic, 0.00005);
    try std.testing.expect(report.cochran == null); // controlling variable has 3 levels
    try table.add(a, 4, -1);
    const negative = try compute(a, &d, &table, .{ .cmh = 3 }, .{});
    try std.testing.expect(negative.negative_weights);
    try std.testing.expectEqual(@as(usize, 0), negative.strata.len);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
}

test "stratified execution sparse Cochran and published drugs agreement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var table = try binaryTable(a, 3);
    for ([_]f64{ 6, 16, 2, 4, 2, 4, 6, 6 }, 0..) |v, i| try table.add(a, i, v);
    const report = try compute(a, &d, &table, .{ .agreement = .{ .enabled = true } }, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 8.4706), report.cochran.?.statistic, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, -0.0588), report.pooled_simple.?.coefficient.value, 0.00005);
    var many = try binaryTable(a, 30);
    try many.add(a, 1, 10);
    try many.add(a, (@as(usize, 1) << 30) - 2, 20);
    try many.add(a, 0, 7);
    const sparse = try compute(a, &d, &many, .{ .agreement = .{ .enabled = true } }, .{});
    try std.testing.expectEqual(@as(usize, 2), sparse.strata.len);
    try std.testing.expectApproxEqAbs(@as(f64, 96.66666666666667), sparse.cochran.?.statistic, 1e-10);
}

test "stratified execution missing numeric scores retain unscored inference" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var table = try binaryTable(a, 2);
    table.include_missing = true;
    table.dimensions[0].levels[0].raw = .{ .num = std.math.nan(f64) };
    table.dimensions[0].levels[0].value = .{ .str = "Missing category" };
    table.dimensions[0].levels[0].missing = true;
    for ([_]f64{ 6, 16, 2, 4 }, 0..) |v, i| try table.add(a, i, v);
    const report = try compute(a, &d, &table, .{ .cmh = 3, .trend = true, .jt = true, .agreement = .{ .enabled = true } }, .{});
    try std.testing.expect(report.cmh[0] == null and report.cmh[1] != null);
    try std.testing.expect(report.cmh[2] != null and report.cmh_suppressed);
    try std.testing.expectEqualSlices(bool, &.{ false, true, true }, &report.cmh_score_eligible);
    try std.testing.expect(report.strata[0].trend == null and report.strata[0].jt != null);
    try std.testing.expect(report.strata[0].simple != null);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    const joint = try jointMatrices(a, report);
    try std.testing.expectEqualSlices(f64, &.{ 6, 16, 2, 4 }, joint[0].counts);
    // adapter_missing.sas transposition: a missing binary RESPONSE score must
    // not suppress TREND when explanatory row scores are valid (Z=.2913).
    var transposed = try binaryTable(a, 2);
    transposed.include_missing = true;
    transposed.dimensions[1].levels[0].raw = .{ .num = std.math.nan(f64) };
    transposed.dimensions[1].levels[0].missing = true;
    for ([_]f64{ 6, 2, 16, 4 }, 0..) |v, i| try transposed.add(a, i, v);
    const transpose_report = try compute(a, &d, &transposed, .{ .cmh = 3, .trend = true }, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 0.2913), transpose_report.strata[0].trend.?.z, 0.00005);
    try std.testing.expect(transpose_report.cmh_suppressed);
    try std.testing.expectEqualSlices(bool, &.{ false, false, true }, &transpose_report.cmh_score_eligible);
    try std.testing.expect(transpose_report.cmh[0] == null and transpose_report.cmh[1] == null and transpose_report.cmh[2] != null);
    // Exact conversion refuses fractional counts; no truncation of weights.
    try table.add(a, 0, 0.5);
    const fractional = try compute(a, &d, &table, .{ .jt = true }, .{});
    try std.testing.expectError(error.ExecError, exactInputs(a, fractional, .jonckheere, 1));
}

test "stratified parser execution rendering bridge keeps agreement score errors local" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const tokens = try @import("../lexer.zig").tokenize(a, "cmh2(mf) agree(wt=fc details printkwts nullkappa=.2) commonriskdiff(cl=(mh score) test printwts column=2)", &d);
    var index: usize = 0;
    var opts = p.Options{};
    while (tokens[index].tag != .eof) try std.testing.expect(try p.consumeTableOption(tokens, &index, &opts, &d));
    var table = try binaryTable(a, 3);
    for ([_]f64{ 16, 11, 5, 20, 12, 16, 7, 19 }, 0..) |v, i| try table.add(a, i, v);
    const report = try compute(a, &d, &table, opts, .{});
    try std.testing.expectApproxEqAbs(@as(f64, -0.2738), report.common_rows[0].result.?.value, 0.00005);
    var out: std.ArrayList(u8) = .empty;
    try listing(a, &out, report, opts, .{}, .table, false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "General Association") == null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Column 2") != null);
    // Preserve ORDER=DATA numeric levels 1,8,3, including their representatives.
    const dims = try a.alloc(model.Dimension, 2);
    for (dims) |*dim| {
        const levels = try a.alloc(model.Level, 3);
        for (levels, [_]f64{ 1, 8, 3 }) |*v, x| v.* = .{ .value = .{ .num = x }, .raw = .{ .num = x }, .missing = false, .frequency = 0 };
        dim.* = .{ .name = "rating", .levels = levels };
    }
    var unordered = try model.Table.init(a, dims, false);
    for ([_]f64{ 18, 3, 1, 7, 12, 4, 2, 9, 24 }, 0..) |v, i| try unordered.add(a, i, v);
    const bad = try compute(a, &d, &unordered, .{ .jt = true, .agreement = .{ .enabled = true } }, .{});
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(bad.strata[0].simple != null and bad.strata[0].weighted == null);
    try std.testing.expectEqual(@as(f64, 1720.5), bad.strata[0].jt.?.statistic);
    try std.testing.expectEqual(@as(f64, 8), bad.strata[0].scored.row_levels[1].raw.num);
}

test "stratified execution single stratum common risk and empty reports" {
    // adapter_one_stratum.sas: a two-way request still computes COMMONRISKDIFF;
    // Gail-Simon is not displayed for one stratum. All-zero tables emit no stats.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var table = try binaryTable(a, 2);
    const options = p.Options{ .common = .{ .enabled = true, .test_default = true, .print_default = true }, .gail_simon = true };
    const empty = try compute(a, &d, &table, options, .{});
    var out: std.ArrayList(u8) = .empty;
    try listing(a, &out, empty, options, .{}, .table, false);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    for ([_]f64{ 28, 27, 12, 39 }, 0..) |v, i| try table.add(a, i, v);
    const report = try compute(a, &d, &table, options, .{});
    try std.testing.expectApproxEqAbs(@as(f64, 3.0475), report.common_rows[0].result.?.z.?, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.2648), report.common_rows[1].result.?.value, 0.00005);
    try listing(a, &out, report, options, .{}, .table, false);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Gail-Simon") == null);
}

test "stratified common weight report excludes zero rows but preserves SAS fractions" {
    // adapter_margins.sas excludes zero-row stratum from PRINTWTS, while the
    // Fraction denominator retains its 14 observations: 52/120=.4333.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var table = try binaryTable(a, 3);
    const old = table.dimensions[0].levels;
    const levels = try a.alloc(model.Level, 3);
    @memcpy(levels[0..2], old);
    levels[2] = .{ .value = .{ .num = 3 }, .raw = .{ .num = 3 }, .missing = false, .frequency = 0 };
    table.dimensions[0].levels = levels;
    table = try model.Table.init(a, table.dimensions, false);
    for ([_]f64{ 16, 11, 5, 20, 0, 0, 6, 8, 12, 16, 7, 19 }, 0..) |v, i| try table.add(a, i, v);
    const report = try compute(a, &d, &table, .{ .common = .{ .enabled = true, .print_default = true } }, .{});
    try std.testing.expectEqualSlices(usize, &.{ 0, 2 }, report.common_weight_ids);
    try std.testing.expectEqualStrings("2", report.common_weights[1].stratum);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4333), report.common_weights[0].fraction, 0.00005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4500), report.common_weights[1].fraction, 0.00005);
}

test "stratified CMH score eligibility is per axis independent of SAS ODS suppression" {
    // cmh_axes.sas: row-only and column-only numeric missing under MISSING /
    // SCORES=TABLE each suppress SAS's entire CMH ODS object. cmh_axes_ods.sas
    // confirms ROW_CMH_EXISTS=0 and COLUMN_CMH_EXISTS=0 via FILE PRINT.
    // Numeric recode controls independently give row-mean41.7662/general58.2955;
    // those kinds do not depend on row scores/general scores, respectively.
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-stratified/cmh_axes_ods.sas -f text -o /tmp/opensas-stat-batch2/FEAT-freq-stratified/cmh_axes_ods.txt -l /tmp/opensas-stat-batch2/FEAT-freq-stratified/cmh_axes_ods.log
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const counts = [_]f64{ 18, 3, 1, 7, 12, 4, 2, 9, 24, 6, 2, 3, 1, 8, 4, 3, 2, 11 };
    for (0..4) |missing_axes| {
        var table = try binaryTable(a, 3);
        for (1..3) |axis| {
            const levels = try a.alloc(model.Level, 3);
            for (levels, 0..) |*v, i| {
                const x: f64 = @floatFromInt(i + 1);
                v.* = .{ .raw = .{ .num = x }, .value = .{ .num = x }, .missing = false, .frequency = 0 };
            }
            const is_missing = if (axis == 1) missing_axes == 1 or missing_axes == 3 else missing_axes == 2 or missing_axes == 3;
            if (is_missing) levels[0] = .{ .raw = .{ .num = std.math.nan(f64) }, .value = .{ .num = std.math.nan(f64) }, .missing = true, .frequency = 0 };
            table.dimensions[axis].levels = levels;
        }
        table = try model.Table.init(a, table.dimensions, true);
        for (counts, 0..) |v, i| try table.add(a, i, v);
        var d = diag.Diagnostics.init(a);
        const report = try compute(a, &d, &table, .{ .cmh = 3 }, .{});
        const row_valid = missing_axes == 0 or missing_axes == 2;
        const col_valid = missing_axes == 0 or missing_axes == 1;
        try std.testing.expectEqualSlices(bool, &.{ row_valid and col_valid, col_valid, true }, &report.cmh_score_eligible);
        try std.testing.expectEqual(row_valid and col_valid, report.cmh[0] != null);
        try std.testing.expectEqual(col_valid, report.cmh[1] != null);
        try std.testing.expectApproxEqAbs(@as(f64, 58.2955), report.cmh[2].?.statistic, 0.00005);
        if (col_valid) try std.testing.expectApproxEqAbs(@as(f64, 41.7662), report.cmh[1].?.statistic, 0.00005);
        if (missing_axes == 0) try std.testing.expectApproxEqAbs(@as(f64, 41.7661), report.cmh[0].?.statistic, 0.00005);
        var out: std.ArrayList(u8) = .empty;
        try renderSummary(a, &out, report, .{ .cmh = 3 }, .{}, .table);
        try std.testing.expectEqual(missing_axes != 0, report.cmh_suppressed);
        try std.testing.expectEqual(missing_axes == 0, std.mem.indexOf(u8, out.items, "Cochran-Mantel-Haenszel") != null);
        if (missing_axes == 1) {
            const cmh2 = try compute(a, &d, &table, .{ .cmh = 2 }, .{});
            try std.testing.expect(cmh2.cmh[0] == null and cmh2.cmh[1] != null and cmh2.cmh[2] == null);
            const cmh1 = try compute(a, &d, &table, .{ .cmh = 1 }, .{});
            try std.testing.expect(cmh1.cmh[0] == null and cmh1.cmh[1] == null and cmh1.cmh[2] == null);
            table.score_kind = .rank;
            const rank = try compute(a, &d, &table, .{ .cmh = 3 }, .{});
            try std.testing.expectEqualSlices(bool, &.{ true, true, true }, &rank.cmh_score_eligible);
            try std.testing.expect(!rank.cmh_suppressed);
        }
    }
}
