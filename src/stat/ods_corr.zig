//! Named ODS datasets built directly from CORR's typed results.
const std = @import("std");
const corr = @import("corr.zig");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const b = @import("ods_table.zig");
pub fn publish(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, result: corr.Result) diag.Error!void {
    const spec = result.spec;
    if (spec.options.noprint) return;
    for (result.groups) |group| {
        var label_len: usize = 0;
        var name_len: usize = 1;
        for (group.simple) |v| {
            const c = spec.ds.columns.items[v.column];
            if (c.label) |label| label_len = @max(label_len, label.len);
            name_len = @max(name_len, c.name.len);
        }
        const partial = spec.partial.len != 0;
        try publishVarInformation(a, d, capture, spec, group);
        if (group.alpha) |alpha| try publishAlpha(a, d, capture, spec, group, alpha, name_len, label_len);
        if (spec.options.fisher != null) {
            if (spec.options.pearson and group.pairs.len > 0)
                try publishFisher(a, d, capture, spec, group, group.pairs, false, name_len);
            if (group.spearman.len > 0)
                try publishFisher(a, d, capture, spec, group, group.spearman, true, name_len);
        }
        if (!spec.options.nosimple and capture.wants("SimpleStats")) {
            var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
            t.ds.label = "Simple Statistics";
            try t.char("Variable", @max(8, name_len));
            for ([_][]const u8{ "NObs", "Mean", "StdDev", if (spec.options.simple_median) "Median" else "Sum", "Min", "Max" }, 0..) |name, i| try t.num(name, if (i == 0) "8." else "D10.");
            t.ds.setLabel("NObs", "N");
            t.ds.setLabel("StdDev", "Std Dev");
            t.ds.setLabel("Min", "Minimum");
            t.ds.setLabel("Max", "Maximum");
            const partial_stats = partial and spec.options.pearson;
            if (partial_stats) {
                try t.num("PartialVariance", "D10.");
                try t.num("PartialStdDev", "D10.");
                t.ds.setLabel("PartialVariance", "Partial Variance");
                t.ds.setLabel("PartialStdDev", "Partial Std Dev");
            }
            if (label_len > 0) try t.char("Label", label_len);
            for (group.simple) |v| {
                const c = spec.ds.columns.items[v.column];
                var cells: std.ArrayList(Value) = .empty;
                try cells.appendSlice(a, &.{ b.s(c.name), b.n(v.n), b.n(v.mean), b.n(v.stddev), b.n(if (spec.options.simple_median) v.median else v.sum), b.n(v.minimum), b.n(v.maximum) });
                if (partial_stats) {
                    const control = std.mem.indexOfScalar(usize, spec.partial, v.column) != null;
                    const missing = Value.specialMissing('_');
                    try cells.appendSlice(a, &.{ if (control) missing else b.n(v.partial_variance), if (control) missing else b.n(@sqrt(v.partial_variance)) });
                }
                if (label_len > 0) try cells.append(a, b.s(c.label orelse ""));
                try t.row(cells.items);
            }
            try capture.publish(a, d, "SimpleStats", &t.ds);
        }
        if (group.polychoric.len > 0 and capture.wants("PolychoricCorr")) {
            var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
            t.ds.label = "Polychoric Correlations";
            try t.char("Var", @max(8, name_len));
            try t.char("WithVar", @max(8, name_len));
            t.ds.setLabel("Var", "Variable");
            t.ds.setLabel("WithVar", "With Variable");
            // M9 includes the two ordinal tests in this object under NOPROB
            // and NOCORR as well. The names, widths and labels are from CONTENTS.
            for ([_][]const u8{ "NObs", "Corr", "StdErr", "WaldChiSq", "ProbWaldChiSq", "LRChiSq", "ProbLRChiSq" }, [_][]const u8{ "8.", "D10.", "D10.", "10.4", "PVALUE6.4", "10.4", "PVALUE6.4" }, [_][]const u8{ "N", "Polychoric Correlation", "Standard Error", "Chi-Square", "Pr > ChiSq", "Chi-Square", "Pr > ChiSq" }) |name, fmt, label| {
                try t.num(name, fmt);
                t.ds.setLabel(name, label);
            }
            for (group.polychoric) |entry| {
                // Without WITH, the leading variable is the first VAR in the
                // pair. With WITH, Var and WithVar follow their statements.
                const v = if (spec.with.len == 0) entry.row else entry.column;
                const w = if (spec.with.len == 0) entry.column else entry.row;
                const e = entry.estimate;
                try t.row(&.{ b.s(spec.ds.columns.items[v].name), b.s(spec.ds.columns.items[w].name), b.n(e.n), b.n(e.r), b.n(e.se), b.n(e.wald), b.n(e.p), b.n(e.lr), b.n(e.lr_p) });
            }
            try capture.publish(a, d, "PolychoricCorr", &t.ds);
        }
        const rows = if (spec.with.len > 0) spec.with else spec.vars;
        var row_name_len: usize = 1;
        var row_label_len: usize = 0;
        for (rows) |ri| {
            const col = spec.ds.columns.items[ri];
            row_name_len = @max(row_name_len, col.name.len);
            if (col.label) |label| row_label_len = @max(row_label_len, label.len);
        }
        if (spec.options.sscp) try publishMoment(a, d, capture, spec, group, group.pairs, row_name_len, row_label_len, .sscp, "Sscp", "SSCP Matrix");
        if (spec.options.csscp) {
            if (partial) try publishMoment(a, d, capture, spec, group, group.unpartial_pairs, row_name_len, row_label_len, .csscp, "Csscp", "CSSCP Matrix");
            try publishMoment(a, d, capture, spec, group, group.pairs, row_name_len, row_label_len, .csscp, if (partial) "PartialCsscp" else "Csscp", if (partial) "Partial CSSCP Matrix" else "CSSCP Matrix");
        }
        if (spec.options.cov) try publishMoment(a, d, capture, spec, group, group.pairs, row_name_len, row_label_len, .cov, if (partial) "PartialCov" else "Cov", if (partial) "Partial Covariance Matrix" else "Covariance Matrix");
        inline for (.{ "Pearson", "Spearman", "Kendall", "Hoeffding" }, .{ "pairs", "spearman", "kendall", "hoeffding" }) |method, field| {
            const matrix = @field(group, field);
            const name = if (partial) "Partial" ++ method ++ "Corr" else method ++ "Corr";
            if (matrix.len != 0 and capture.wants(name) and (!std.mem.eql(u8, method, "Pearson") or (spec.options.pearson and !spec.options.nocorr))) {
                const label = if (partial) method ++ " Partial Correlations" else method ++ " Correlations";
                try publishMatrix(a, d, capture, spec, group, matrix, row_name_len, row_label_len, name, label);
            }
        }
    }
}
pub fn fisherTableName(spearman: bool, partial: bool) []const u8 {
    return if (spearman) (if (partial) "FisherSpearmanPartialCorr" else "FisherSpearmanCorr") else if (partial) "FisherPearsonPartialCorr" else "FisherPearsonCorr";
}

const MatrixMoment = enum {
    cov,
    csscp,
    sscp,

    fn value(kind: MatrixMoment, p: corr.Pair, part: usize) f64 {
        return switch (kind) {
            .cov => switch (part) {
                0 => p.covariance,
                1 => p.variance_y,
                2 => p.variance_x,
                else => p.divisor,
            },
            .csscp => switch (part) {
                0 => p.cross,
                1 => p.css_y,
                else => p.css_x,
            },
            .sscp => switch (part) {
                0 => p.sscp,
                1 => p.uss_y,
                else => p.uss_x,
            },
        };
    }
};

fn publishMoment(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, spec: corr.Spec, group: corr.Group, pairs: []const corr.Pair, row_names: usize, row_labels: usize, kind: MatrixMoment, name: []const u8, label: []const u8) !void {
    if (!capture.wants(name) or pairs.len == 0) return;
    var table = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
    table.ds.label = label;
    try table.char("Variable", row_names);
    if (row_labels > 0) try table.char("Label", row_labels);
    // A pairwise table must retain the row and column variances for the
    // observations in that pair. Listwise (including partial) has one population.
    var pairwise = false;
    if (!spec.options.nomiss) for (pairs) |p| {
        if (p.n != group.n) pairwise = true;
    };
    const pieces: usize = if (pairwise) (if (kind == .cov) 4 else 3) else 1;
    var maximum: f64 = 0;
    for (pairs) |pair| for (0..@min(pieces, 3)) |part| {
        const v = kind.value(pair, part);
        if (std.math.isFinite(v)) maximum = @max(maximum, @abs(v));
    };
    const digits: i32 = if (maximum > 0) @as(i32, @intFromFloat(@floor(@log10(maximum)))) + 1 else 1;
    const decimals: u32 = @intCast(std.math.clamp(10 - digits, 0, 10));
    const number_format = if (decimals == 0) "12." else try std.fmt.allocPrint(a, "12.{d}", .{decimals});
    const prefixes = [_][]const u8{ "", "Row", "Col", "DF" };
    for (0..pieces) |part| for (spec.vars) |ci| {
        const col = spec.ds.columns.items[ci];
        try table.num(try std.fmt.allocPrint(a, "{s}{s}", .{ prefixes[part], col.name }), if (part == 3) "12." else number_format);
    };
    const row_cols = if (spec.with.len > 0) spec.with else spec.vars;
    for (row_cols, 0..) |ci, row_index| {
        const col = spec.ds.columns.items[ci];
        var cells: std.ArrayList(Value) = .empty;
        try cells.append(a, b.s(col.name));
        if (row_labels > 0) try cells.append(a, b.s(col.label orelse ""));
        const row_pairs = pairs[row_index * spec.vars.len ..][0..spec.vars.len];
        for (0..pieces) |part| for (row_pairs) |pair| try cells.append(a, b.n(kind.value(pair, part)));
        try table.row(cells.items);
    }
    try capture.publish(a, d, name, &table.ds);
}

fn publishVarInformation(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, spec: corr.Spec, group: corr.Group) !void {
    if (!capture.wants("VarInformation")) return;
    const Role = struct { title: []const u8, cols: []const usize, single: bool = false };
    const freq = [_]usize{spec.freq orelse 0};
    const weight = [_]usize{spec.weight orelse 0};
    const roles = [_]Role{
        .{ .title = "Partial", .cols = spec.partial },
        .{ .title = "With", .cols = spec.with },
        .{ .title = "", .cols = spec.vars },
        .{ .title = "Freq", .cols = if (spec.freq != null) &freq else &.{}, .single = true },
        .{ .title = "Weight", .cols = if (spec.weight != null) &weight else &.{}, .single = true },
    };
    var name_width: usize = 8;
    var role_width: usize = 0;
    var count: usize = 0;
    for (roles) |role| {
        if (role.cols.len == 0) continue;
        role_width = @max(role_width, role.title.len);
        count = @max(count, role.cols.len);
        for (role.cols) |ci| name_width = @max(name_width, spec.ds.columns.items[ci].name.len);
    }
    var table = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
    table.ds.label = "Variables Information";
    try table.num("NVars", "4.");
    try table.char("Variables", role_width + 11);
    try table.char("VarNames", count * (name_width + 1));
    for (roles) |role| {
        if (role.cols.len == 0) continue;
        var title: std.ArrayList(u8) = .empty;
        try title.appendSlice(a, role.title);
        try title.appendNTimes(a, ' ', role_width + 1 - role.title.len);
        try title.appendSlice(a, if (role.single) "Variable:" else "Variables:");
        var names: std.ArrayList(u8) = .empty;
        for (role.cols, 0..) |ci, i| {
            const name = spec.ds.columns.items[ci].name;
            try names.appendSlice(a, name);
            if (i + 1 < role.cols.len) try names.appendNTimes(a, ' ', name_width + 1 - name.len);
        }
        try table.row(&.{ b.n(if (role.single) 0 else @floatFromInt(role.cols.len)), b.s(title.items), b.s(names.items) });
    }
    try capture.publish(a, d, "VarInformation", &table.ds);
}

fn publishAlpha(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, spec: corr.Spec, group: corr.Group, alpha: @import("corr_advanced.zig").Alpha, name_len: usize, label_len: usize) !void {
    if (capture.wants("CronbachAlpha")) {
        var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
        t.ds.label = "Cronbach Coefficient Alpha";
        try t.char("Variables", 12);
        try t.num("Alpha", "8.6");
        try t.row(&.{ b.s("Raw"), b.n(alpha.raw) });
        try t.row(&.{ b.s("Standardized"), b.n(alpha.standardized) });
        try capture.publish(a, d, "CronbachAlpha", &t.ds);
    }
    if (alpha.deleted.len > 0 and capture.wants("CronbachAlphaDel")) {
        var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
        t.ds.label = "Cronbach Coefficient Alpha with Deleted Variable";
        try t.char("Variable", @max(8, name_len));
        t.ds.setLabel("Variable", "Deleted Variable");
        for ([_][]const u8{ "RawCorr", "RawAlpha", "StdCorr", "StdAlpha" }, [_][]const u8{ "Raw Correlation with Total", "Raw Alpha", "Standardized Correlation with Total", "Standardized Alpha" }) |name, label| {
            try t.num(name, "8.6");
            t.ds.setLabel(name, label);
        }
        if (label_len > 0) try t.char("Label", label_len);
        for (spec.vars, alpha.deleted) |ci, entry| {
            const col = spec.ds.columns.items[ci];
            const cells = [_]Value{ b.s(col.name), b.n(entry.raw_correlation), b.n(entry.raw), b.n(entry.standardized_correlation), b.n(entry.standardized), b.s(col.label orelse "") };
            try t.row(cells[0..if (label_len > 0) 6 else 5]);
        }
        try capture.publish(a, d, "CronbachAlphaDel", &t.ds);
    }
}

fn publishFisher(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, spec: corr.Spec, group: corr.Group, pairs: []const corr.Pair, spearman: bool, name_len: usize) !void {
    const partial = spec.partial.len != 0;
    const name = fisherTableName(spearman, partial);
    if (!capture.wants(name)) return;
    const opt = spec.options.fisher.?;
    var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
    t.ds.label = try std.fmt.allocPrint(a, "{s}{s} Correlation Statistics (Fisher's z Transformation)", .{ if (spearman) @as([]const u8, "Spearman") else "Pearson", if (partial) @as([]const u8, " Partial") else "" });
    for ([_][]const u8{ "Var", "WithVar" }, [_][]const u8{ "Variable", "With Variable" }) |field, label| {
        try t.char(field, @max(8, name_len));
        t.ds.setLabel(field, label);
    }
    try t.num("NObs", "8.");
    t.ds.setLabel("NObs", "N");
    if (partial) {
        try t.num("NPartial", "8.");
        t.ds.setLabel("NPartial", "N Partialled");
    }
    for ([_][]const u8{ "Corr", "ZVal", "BiasAdj", "CorrEst" }, [_][]const u8{ "Sample Correlation", "Fisher's z", "Bias Adjustment", "Correlation Estimate" }, 0..) |field, label, i| {
        if (!opt.biasadj and i >= 2) break;
        try t.num(field, "D10.");
        t.ds.setLabel(field, label);
    }
    for ([_][]const u8{ "Lcl", "Ucl" }, [_][]const u8{ "Lower", "Upper" }, 0..) |field, side, i| {
        if ((i == 0 and opt.kind == .upper) or (i == 1 and opt.kind == .lower)) continue;
        try t.num(field, "D12.3");
        t.ds.setLabel(field, try std.fmt.allocPrint(a, "{s} {d}% Confidence Limit", .{ side, 100 * (1 - opt.alpha) }));
    }
    if (opt.rho0 != 0) try t.num("Rho0", "D10.");
    try t.num("pValue", "PVALUE6.4");
    const relation: []const u8 = switch (opt.kind) {
        .twosided => "=",
        .lower => "<=",
        .upper => ">=",
    };
    const p_label = if (opt.rho0 != 0) "p Value" else try std.fmt.allocPrint(a, "p Value for H0:{s}Rho{s}0", .{ if (partial) @as([]const u8, " Partial ") else "", relation });
    t.ds.setLabel("pValue", p_label);
    for (pairs, 0..) |p, index| {
        if (spec.with.len == 0 and index % spec.vars.len >= index / spec.vars.len) continue;
        var cells: std.ArrayList(Value) = .empty;
        try cells.appendSlice(a, &.{ b.s(spec.ds.columns.items[p.column].name), b.s(spec.ds.columns.items[p.row].name), b.n(p.n) });
        if (partial) try cells.append(a, b.n(@floatFromInt(p.controls)));
        try cells.appendSlice(a, &.{ b.n(p.r), b.n(p.fisher.z) });
        if (opt.biasadj) try cells.appendSlice(a, &.{ b.n(p.fisher.bias), b.n(p.fisher.estimate) });
        if (opt.kind != .upper) try cells.append(a, b.n(p.fisher.lower));
        if (opt.kind != .lower) try cells.append(a, b.n(p.fisher.upper));
        if (opt.rho0 != 0) try cells.append(a, b.n(opt.rho0));
        try cells.append(a, b.n(p.fisher.p));
        try t.row(cells.items);
    }
    if (t.ds.rows.items.len > 0) try capture.publish(a, d, name, &t.ds);
}

fn publishMatrix(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, spec: corr.Spec, group: corr.Group, matrix: []const corr.Pair, name_len: usize, label_len: usize, name: []const u8, label: []const u8) diag.Error!void {
    var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
    t.ds.label = label;
    try t.char("Variable", name_len);
    if (label_len > 0) try t.char("Label", label_len);
    const show_p = !spec.options.noprob and !std.mem.eql(u8, name, "PartialKendallCorr");
    const diagonal_test = std.mem.eql(u8, name, "HoeffdingCorr");
    var different_n = false;
    for (matrix) |p| if (p.n != matrix[0].n) {
        different_n = true;
    };
    for (spec.vars) |ci| try t.num(spec.ds.columns.items[ci].name, "8.5");
    if (show_p) for (spec.vars) |ci| try t.num(try std.fmt.allocPrint(a, "P{s}", .{spec.ds.columns.items[ci].name}), "PVALUE8.4");
    if (different_n) for (spec.vars) |ci| try t.num(try std.fmt.allocPrint(a, "N{s}", .{spec.ds.columns.items[ci].name}), "8.");
    const rows = if (spec.with.len > 0) spec.with else spec.vars;
    for (rows, 0..) |ri, row| {
        var cells: std.ArrayList(Value) = .empty;
        try cells.append(a, b.s(spec.ds.columns.items[ri].name));
        if (label_len > 0) try cells.append(a, b.s(spec.ds.columns.items[ri].label orelse ""));
        const pairs = matrix[row * spec.vars.len ..][0..spec.vars.len];
        for (pairs) |p| try cells.append(a, b.n(p.r));
        if (show_p) for (pairs) |p| try cells.append(a, if (p.row == p.column and !diagonal_test) Value.specialMissing('_') else b.n(p.p));
        if (different_n) for (pairs) |p| try cells.append(a, b.n(p.n));
        try t.row(cells.items);
    }
    try capture.publish(a, d, name, &t.ds);
}
test "M9 ODS multiple rank matrices route method-specific p-values and diagonal missing codes" {
    // SAS M9 ods_multiple_rank_tables. The two 2x5 objects share a schema.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Dataset = @import("../dataset.zig").Dataset;
    const lex = @import("../lexer.zig");
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "y" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][2]f64{ .{ 1, 8 }, .{ 2, 6 }, .{ 2, 6 }, .{ 3, 2 }, .{ 4, 5 }, .{ 5, 3 }, .{ 6, 1 }, .{ 8, 4 }, .{ 9, 1 } }) |xy|
        try ds.appendRow(&.{ .{ .num = xy[0] }, .{ .num = xy[1] } });
    try lib.put(ds.name, ds);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output SpearmanCorr=s KendallCorr=k;", &d));
    var listing: std.ArrayList(u8) = .empty;
    try corr.run(.{ .arena = a, .diags = &d, .lib = &lib, .capture = &capture }, &listing, try lex.tokenize(a, "proc corr data=sample spearman kendall;var x y;run;", &d));
    try capture.finish(&lib, &d);
    for ([_][]const u8{ "s", "k" }, [_]f64{ -0.81857, -0.69573 }, [_]f64{ 0.0070, 0.0110 }) |name, coef, p| {
        const rs = lib.find(name).?;
        try std.testing.expectEqual(@as(usize, 2), rs.rowCount());
        try std.testing.expectEqual(@as(usize, 5), rs.columns.items.len);
        for ([_][]const u8{ "Variable", "x", "y", "Px", "Py" }, rs.columns.items) |expected, column| try std.testing.expectEqualStrings(expected, column.name);
        try std.testing.expectApproxEqAbs(coef, rs.row(0)[2].num, 0.000005);
        try std.testing.expectApproxEqAbs(p, rs.row(0)[4].num, 0.00005);
        try std.testing.expectEqual(Value.missingRank(Value.specialMissing('_').num), Value.missingRank(rs.row(0)[3].num));
    }
}

test "PolychoricCorr captures named full-precision ordinal pairs and native descriptors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    for ([_][]const u8{ "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 0, 0, 110 }, .{ 0, 1, 352 }, .{ 10, 1, 418 }, .{ 20, 1, 110 } }) |v| try ds.appendRow(&.{ b.n(v[0]), b.n(v[1]), b.n(v[2]) });
    try lib.put("d", &ds);
    const lexer = @import("../lexer.zig");
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture };
    var listing: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "proc corr data=d polychoric(converge=1e-6) noprob;var x;with y;freq f;run;", "proc corr data=d polychoric(converge=1e-6) nocorr;var x y;freq f;run;" }) |source| {
        try capture.parse(a, &d, try lexer.tokenize(a, "ods output PolychoricCorr=fit;", &d));
        try corr.run(cx, &listing, try lexer.tokenize(a, source, &d));
        try capture.finish(&lib, &d);
        const fit = lib.find("fit").?;
        try std.testing.expectEqual(@as(usize, 9), fit.columns.items.len);
        try std.testing.expectEqual(@as(usize, 1), fit.rowCount());
        const row = fit.row(0);
        try std.testing.expectEqualStrings("x", row[fit.indexOf("Var").?].str);
        try std.testing.expectEqualStrings("y", row[fit.indexOf("WithVar").?].str);
        try std.testing.expectEqual(@as(?usize, 8), fit.columns.items[0].len);
        try std.testing.expectEqualStrings("D10.", fit.columns.items[3].format.?);
        try std.testing.expectEqualStrings("Polychoric Correlation", fit.columns.items[3].label.?);
        try std.testing.expectEqualStrings("PVALUE6.4", fit.columns.items[8].format.?);
        try std.testing.expectEqual(@as(f64, 990), row[2].num);
        try std.testing.expectApproxEqAbs(@as(f64, 0.98771303566856), row[3].num, 5e-8);
        try std.testing.expectEqual(@as(f64, 0), row[4].num);
        try std.testing.expect(row[5].isMissing() and row[6].isMissing());
        try std.testing.expectApproxEqAbs(@as(f64, 183.527618505065), row[7].num, 1e-7);
        try std.testing.expectApproxEqRel(@as(f64, 8.2269409306717e-42), row[8].num, 1e-7);
    }
}

test "M9 Fisher capture uses requested limits with a BY prefix and retains probabilities under NOPROB" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lexer = @import("../lexer.zig");
    const Dataset = @import("../dataset.zig").Dataset;
    var library = @import("../exec.zig").Library.init(a);
    var input = Dataset.init(a, "d");
    for ([_][]const u8{ "group_x", "long_measurement_name", "with_y" }) |name| _ = try input.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 7 }, .{ 1, 2, 8 }, .{ 1, 3, 10 }, .{ 1, 5, 6 }, .{ 1, 6, 15 }, .{ 1, 8, 17 }, .{ 2, 1, 5 }, .{ 2, 2, 2 }, .{ 2, 3, 4 }, .{ 2, 5, 9 }, .{ 2, 7, 8 }, .{ 2, 9, 13 } }) |r| try input.appendRow(&.{ b.n(r[0]), b.n(r[1]), b.n(r[2]) });
    try library.put(input.name, &input);
    var capture: ods.Capture = .{};
    var diagnostics = diag.Diagnostics.init(a);
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &library, .diags = &diagnostics, .capture = &capture };
    var listing: std.ArrayList(u8) = .empty;
    try capture.parse(a, &diagnostics, try lexer.tokenize(a, "ods output FisherPearsonCorr=p;", &diagnostics));
    try corr.run(cx, &listing, try lexer.tokenize(a, "proc corr data=d fisher;by group_x;var long_measurement_name;with with_y;run;", &diagnostics));
    try capture.finish(&library, &diagnostics);
    const result = library.find("p").?;
    try std.testing.expectEqual(@as(usize, 2), result.rowCount());
    try std.testing.expectEqualStrings("group_x", result.columns.items[0].name);
    try std.testing.expectEqualStrings("long_measurement_name", result.row(0)[1].str);
    try std.testing.expectEqualStrings("with_y", result.row(0)[2].str);
    try std.testing.expectApproxEqAbs(@as(f64, 0.78203), result.row(0)[4].num, 0.000005);
    try std.testing.expectApproxEqAbs(@as(f64, 0.985721), result.row(1)[9].num, 0.0000005);
    try capture.parse(a, &diagnostics, try lexer.tokenize(a, "ods output FisherPearsonCorr=v;", &diagnostics));
    try corr.run(cx, &listing, try lexer.tokenize(a, "proc corr data=d fisher(type=twosided alpha=.025 rho0=.3 biasadj=no) noprob;var long_measurement_name;with with_y;run;", &diagnostics));
    try capture.finish(&library, &diagnostics);
    const variant = library.find("v").?;
    try std.testing.expectEqual(@as(usize, 9), variant.columns.items.len);
    try std.testing.expectEqualStrings("Lower 97.5% Confidence Limit", variant.columns.items[5].label.?);
    try std.testing.expectEqualStrings("Rho0", variant.columns.items[7].name);
    try std.testing.expectEqual(@as(f64, 0.3), variant.row(0)[7].num);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0788), variant.row(0)[8].num, 0.00005);
}

test "CORR ODS partial, Hoeffding and covariance cells follow native roles and missing codes" {
    const lex = @import("../lexer.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diags = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "series");
    for ([_][]const u8{ "a", "b", "c" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 2, 4 }, .{ 2, 3, 1 }, .{ 2, 2, 5 }, .{ 4, 7, 3 }, .{ 5, 4, 2 }, .{ 7, 9, 8 }, .{ 8, 5, 5 }, .{ 2, 4, 2 }, .{ 3, 1, 7 }, .{ 3, 8, 4 }, .{ 5, 7, 5 }, .{ 6, 6, 2 }, .{ 8, 2, 4 }, .{ std.math.nan(f64), 5, 6 } }) |r|
        try ds.appendRow(&.{ b.n(r[0]), b.n(r[1]), b.n(r[2]) });
    try lib.put("series", &ds);
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .diags = &diags, .lib = &lib, .capture = &capture };
    var listing: std.ArrayList(u8) = .empty;
    try capture.parse(a, &diags, try lex.tokenize(a, "ods output Cov=cov HoeffdingCorr=h VarInformation=v;", &diags));
    try corr.run(cx, &listing, try lex.tokenize(a, "proc corr data=series cov hoeffding; var a b; run;", &diags));
    try capture.finish(&lib, &diags);
    const cov = lib.find("cov").?;
    try std.testing.expectApproxEqAbs(@as(f64, 6.75641025641025), cov.row(0)[cov.indexOf("Colb").?].num, 1e-10);
    try std.testing.expectEqual(@as(f64, 13), cov.row(1)[cov.indexOf("DFb").?].num);
    const h = lib.find("h").?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.79970376845376), h.row(0)[h.indexOf("a").?].num, 1e-10);
    try std.testing.expectEqual(@as(f64, 0.00001), h.row(0)[h.indexOf("Pa").?].num);
    try std.testing.expectEqualStrings("a        b", lib.find("v").?.row(0)[2].str);

    try capture.parse(a, &diags, try lex.tokenize(a, "ods output SimpleStats=s PartialKendallCorr=k PartialPearsonCorr=p PartialCov=pc PearsonCorr=absent;", &diags));
    try corr.run(cx, &listing, try lex.tokenize(a, "proc corr data=series pearson kendall cov; var a b; partial c; run;", &diags));
    try capture.finish(&lib, &diags);
    const p = lib.find("p").?;
    try std.testing.expectApproxEqAbs(@as(f64, 0.33267797449091), p.row(0)[p.indexOf("b").?].num, 1e-10);
    try std.testing.expect(lib.find("absent") == null);
    try std.testing.expect(lib.find("k").?.indexOf("Pa") == null);
    const stats = lib.find("s").?;
    try std.testing.expect(stats.indexOf("Median") != null and stats.indexOf("Sum") == null);
    try std.testing.expectEqualStrings("c", stats.row(0)[0].str);
    try std.testing.expectEqual(Value.missingRank(Value.specialMissing('_').num), Value.missingRank(stats.row(0)[stats.indexOf("PartialVariance").?].num));
    const pc = lib.find("pc").?;
    try std.testing.expect(pc.indexOf("Rowa") == null);
    try std.testing.expectApproxEqAbs(@as(f64, 2.15076923076923), pc.row(0)[pc.indexOf("b").?].num, 1e-10);
}
