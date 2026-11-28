//! Typed default MIXED results from computed state, never parsed listing text.
//! S154 physical pp.6720-6729 provides names/conditional fields. Display formats
//! retain published precision; exact SAS descriptor widths require further
//! reference capture and are not claimed by these logical schemas.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
const decl = @import("mixed_parse.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const input = @import("mixed_input.zig");
const math = @import("mixed_fit.zig");
const rendering = @import("mixed_render.zig");
const A = std.mem.Allocator;
pub const routing = @import("mixed_ods_route.zig");
fn make(a: A, s: decl.Spec, g: input.Group, name: []const u8) !b.Builder {
    var table = try b.Builder.init(a, s.input.ds, s.roles.by, if (g.raw.observations.len > 0) g.raw.observations[0].cells else null);
    table.ds.label = routing.label(name);
    return table;
}
fn val(x: ?f64) Value {
    return if (x) |v| if (std.math.isFinite(v)) b.n(v) else Value.missing else Value.missing;
}
fn send(cx: proc.ProcCtx, name: []const u8, table: *b.Builder) diag.Error!void {
    if (cx.capture) |capture| try capture.publish(cx.arena, cx.diags, name, &table.ds);
}
pub fn publish(cx: proc.ProcCtx, s: decl.Spec, m: model.Spec, g: input.Group, x: fixed.Design, z: random.Design, r: random.Spec, f: math.Fit, cov_names: []const []const u8, tests: []const rendering.NamedTest, parameter_search: ?@import("mixed_parms.zig").Result, parameter_spec: ?@import("mixed_parms.zig").Spec) diag.Error!void {
    const c = cx.capture orelse return;
    const a = cx.arena;
    if (!s.options.noinfo and c.wants("ModelInfo")) {
        var table = try make(a, s, g, "ModelInfo");
        try table.char("Descr", 64);
        try table.char("Value", 256);
        const raw = try std.ascii.allocUpperString(a, s.input.ds.name);
        const ds_name = if (std.mem.indexOfScalar(u8, raw, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{raw}) else raw;
        const labels = [_][]const u8{ "Data Set", "Dependent Variable", "Covariance Structure", "Estimation Method", "Residual Variance Method", "Fixed Effects SE Method", "Degrees of Freedom Method" };
        const texts = [_][]const u8{ ds_name, s.input.ds.columns.items[m.matrix.response].name, if (z.components.len == 0) "Diagonal" else "Variance Components", if (s.options.method == .type3) "Type 3" else "REML", if (s.options.method == .type3) "Factor" else if (parameter_search) |search| if (search.profile) "Profile" else "Parameter" else "Profile", "Model-Based", if (m.options.ddfm == .residual or z.components.len == 0) "Residual" else "Containment" };
        for (labels, texts) |label, text| try table.row(&.{ b.s(label), b.s(text) });
        try send(cx, "ModelInfo", &table);
    }
    if (x.matrix.classes.len > 0 and c.wants("ClassLevels")) {
        var table = try make(a, s, g, "ClassLevels");
        try table.char("Class", 32);
        try table.num("Levels", "8.");
        try table.char("Values", 1);
        for (x.matrix.classes) |class| {
            var text: std.ArrayList(u8) = .empty;
            for (class.map.levels, 0..) |level, i| {
                if (i > 0) try text.append(a, ' ');
                try text.appendSlice(a, std.mem.trim(u8, level.label, " "));
            }
            table.ds.setLen("Values", @max(table.ds.columns.items[table.ds.indexOf("Values").?].len orelse 1, text.items.len));
            try table.row(&.{ b.s(s.input.ds.columns.items[class.column].name), b.n(@floatFromInt(class.map.levels.len)), b.s(text.items) });
        }
        try send(cx, "ClassLevels", &table);
    }
    if (!s.options.noinfo and c.wants("Dimensions")) {
        var table = try make(a, s, g, "Dimensions");
        try table.char("Descr", 64);
        try table.num("Value", "8.");
        const labels = [_][]const u8{ "Covariance Parameters", "Columns in X", "Columns in Z", "Subjects", "Max Obs per Subject" };
        const values = [_]usize{ z.components.len + 1, x.matrix.p, z.q, z.subject_count, z.max_obs_per_subject };
        for (labels, values) |label, value| try table.row(&.{ b.s(label), b.n(@floatFromInt(value)) });
        try send(cx, "Dimensions", &table);
    }
    if (!s.options.noinfo and c.wants("NObs")) {
        var table = try make(a, s, g, "NObs");
        try table.char("Label", 64);
        for ([_][]const u8{ "N", "NObsRead", "NObsUsed" }) |name| try table.num(name, "8.");
        const labels = [_][]const u8{ "Number of Observations Read", "Number of Observations Used", "Number of Observations Not Used" };
        for (labels, [_]usize{ g.read_count, x.matrix.n, g.read_count - x.matrix.n }) |label, count| try table.row(&.{ b.s(label), b.n(@floatFromInt(count)), b.n(@floatFromInt(g.read_count)), b.n(@floatFromInt(x.matrix.n)) });
        try send(cx, "NObs", &table);
    }
    const iterative = s.options.method == .reml and f.variances.len > 1 and f.status != .evaluated;
    if (iterative and f.iterations.len > 0 and c.wants("IterHistory")) {
        if (s.options.noitprint) return proc.failGap(cx.diags, s.line, "PROC MIXED: NOITPRINT with IterHistory capture is not independently verified", .{});
        var table = try make(a, s, g, "IterHistory");
        try table.num("Iteration", "8.");
        try table.num("Evaluations", "8.");
        try table.num("M2ResLogLike", "12.8");
        try table.num("Criterion", "12.8");
        for (f.iterations) |row| try table.row(&.{ b.n(@floatFromInt(row.iteration)), b.n(@floatFromInt(row.evaluations)), b.n(row.objective), val(row.criterion) });
        try send(cx, "IterHistory", &table);
    }
    if (iterative and c.wants("ConvergenceStatus")) {
        var table = try make(a, s, g, "ConvergenceStatus");
        for ([_][]const u8{ "Status", "pdG", "pdH" }) |name| try table.num(name, "8.");
        try table.char("Reason", 256);
        var pd_g = true;
        for (f.variances[0..z.components.len]) |v| {
            if (v <= 0) pd_g = false;
        }
        try table.row(&.{ if (math.statusInfo(f.status).sas_status) |code| b.n(@floatFromInt(code)) else Value.missing, b.n(if (pd_g) 1 else 0), if (f.pd_h) |pd| b.n(if (pd) 1 else 0) else Value.missing, b.s(math.statusReason(f.status)) });
        try send(cx, "ConvergenceStatus", &table);
    }
    if (c.wants("CovParms")) {
        for (r.requests) |request| if (request.subject.len > 0 or request.group.len > 0) return proc.failGap(cx.diags, s.line, "PROC MIXED: SUBJECT/GROUP CovParms dataset metadata is not independently verified", .{});
        var table = try make(a, s, g, "CovParms");
        try table.char("CovParm", s.options.namelen);
        try table.num("Estimate", "12.4");
        for (cov_names, f.variances) |name, value| try table.row(&.{ b.s(name), b.n(value) });
        try send(cx, "CovParms", &table);
    }
    if ((f.converged or s.options.method == .type3) and c.wants("FitStatistics")) {
        var table = try make(a, s, g, "FitStatistics");
        try table.char("Descr", 64);
        try table.num("Value", "12.1");
        const labels = [_][]const u8{ "-2 Res Log Likelihood", "AIC (Smaller is Better)", "AICC (Smaller is Better)", "BIC (Smaller is Better)" };
        for (labels, [_]?f64{ f.minus2loglik, f.aic, f.aicc, f.bic }) |label, value| try table.row(&.{ b.s(label), val(value) });
        try send(cx, "FitStatistics", &table);
    }
    if (!m.options.notest and tests.len > 0 and c.wants("Tests3")) {
        var table = try make(a, s, g, "Tests3");
        try table.char("Effect", s.options.namelen);
        try table.num("NumDF", "8.");
        try table.num("DenDF", "8.");
        try table.num("FValue", "8.2");
        try table.num("ProbF", "PVALUE6.4");
        for (tests) |test_result| try table.row(&.{ b.s(test_result.name), b.n(@floatFromInt(test_result.num_df)), b.n(@floatFromInt(test_result.den_df)), b.n(test_result.f), b.n(test_result.p) });
        try send(cx, "Tests3", &table);
    }
    if (parameter_search) |search| {
        if (search.rows.len > 0 and c.wants("ParmSearch")) {
            if (parameter_spec.?.noprint) return proc.failGap(cx.diags, s.line, "PROC MIXED: PARMS NOPRINT with ParmSearch capture is not independently verified", .{});
            var table = try make(a, s, g, "ParmSearch");
            for (0..search.rows[0].values.len) |i| try table.num(try std.fmt.allocPrint(a, "CovP{d}", .{i + 1}), "12.4");
            if (search.profile) try table.num("Var", "12.4");
            try table.num("ResLogLike", "12.4");
            try table.num("M2ResLogLike2", "12.4");
            for (search.rows) |row| {
                var cells: std.ArrayList(Value) = .empty;
                for (row.values) |value| try cells.append(a, b.n(value));
                if (search.profile) try cells.append(a, val(row.residual));
                try cells.append(a, if (row.objective) |v| b.n(-v / 2) else Value.missing);
                try cells.append(a, val(row.objective));
                try table.row(cells.items);
            }
            try send(cx, "ParmSearch", &table);
        }
        if (search.likelihood_ratio) |lrt| if (c.wants("LRT")) {
            var table = try make(a, s, g, "LRT");
            try table.num("DF", "8.");
            try table.num("ChiSquare", "8.2");
            try table.num("ProbChiSq", "PVALUE6.4");
            try table.row(&.{ b.n(@floatFromInt(lrt.df)), b.n(lrt.statistic), b.n(lrt.p) });
            try send(cx, "LRT", &table);
        };
    }
}
test {
    _ = @import("mixed_ods_tests.zig");
}
