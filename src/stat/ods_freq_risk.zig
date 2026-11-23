//! Typed risk ODS tables. The exact columns consume the intervals already
//! computed for this stratum; no exact inversion is performed by the producer.
const std = @import("std");
const A = std.mem.Allocator;
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fmt = @import("../format.zig");
const b = @import("ods_table.zig");
const model = @import("freq_table.zig");
const risk = @import("freq_risk.zig");
const report = @import("freq_risk_render.zig");
const public = @import("freq_exact_public.zig");
const Interval = @import("freq_exact.zig").Interval;

fn numeric(value: ?f64) Value {
    return if (value) |x| (if (std.math.isFinite(x)) b.n(x) else Value.missing) else Value.missing;
}

fn riskDifference(a: A, t: *b.Builder, table: []const u8, col: usize, alpha: f64, estimates: report.RiskColumn, difference: ?Interval) !void {
    t.ds.label = try std.fmt.allocPrint(a, "Column {d} Risk Estimates", .{col + 1});
    try t.char("Table", 256);
    try t.char("Row", 12);
    try t.num("Risk", "7.4");
    try t.num("ASE", "7.4");
    const level = try report.confidence(a, alpha);
    const has_exact = difference != null or estimates.binomial_limits[0] != null;
    const names = [_][]const u8{ "LowerCL", "UpperCL", "ExactLowerCL", "ExactUpperCL" };
    const suffixes = [_][]const u8{ "Lower Confidence Limit", "Upper Confidence Limit", "Exact Lower Confidence Limit", "Exact Upper Confidence Limit" };
    for (names[0..if (has_exact) @as(usize, 4) else 2], 0..) |name, i| {
        try t.num(name, "7.4");
        t.ds.setLabel(name, try std.fmt.allocPrint(a, "{s}% {s}", .{ level, suffixes[i] }));
    }
    try t.char("Control", 1);
    for (estimates.estimates, [_][]const u8{ "Row 1", "Row 2", "Total", "Difference" }, 0..) |e, label, i| {
        var row: std.ArrayList(Value) = .empty;
        try row.appendSlice(a, &.{ b.s(table), b.s(label), numeric(e.estimate), numeric(e.se), numeric(e.limits.lower), numeric(e.limits.upper) });
        if (has_exact) {
            const ci: risk.Interval = if (i < 3) estimates.binomial_limits[i] orelse .{} else if (difference) |v| .{ .lower = v.lower, .upper = v.upper } else .{};
            try row.appendSlice(a, &.{ numeric(ci.lower), numeric(ci.upper) });
        }
        try row.append(a, b.s(if (i == 3) "1" else ""));
        try t.row(row.items);
    }
}

fn relativeRisk(a: A, t: *b.Builder, table_name: []const u8, table: risk.Table2x2, col: usize, alpha: f64, exact: Interval) !void {
    const ratio = try risk.ratio(table, if (col == 0) .first else .second, .relative_risk, alpha, .wald, true);
    t.ds.label = try std.fmt.allocPrint(a, "Exact Confidence Limits for the Relative Risk (Column {d})", .{col + 1});
    try t.char("Table", 256);
    try t.char("Name1", 7);
    try t.char("Label1", 22);
    try t.char("cValue1", 10);
    try t.num("nValue1", "D12.3");
    const level = try report.confidence(a, alpha);
    const lower = try std.fmt.allocPrint(a, "{s}% Lower Conf Limit", .{level});
    const upper = try std.fmt.allocPrint(a, "{s}% Upper Conf Limit", .{level});
    const names = if (col == 0) [_][]const u8{ "_RRC1_", "", "", "L_RRC1", "U_RRC1", "", "", "XL_RRC1", "XU_RRC1" } else [_][]const u8{ "_RRC2_", "", "", "L_RRC2", "U_RRC2", "", "", "XL_RRC2", "XU_RRC2" };
    const labels = [_][]const u8{ "Relative Risk", "", "Asymptotic Conf Limits", lower, upper, "", "Exact Conf Limits", lower, upper };
    const values = [_]?f64{ ratio.estimate, null, null, ratio.limits.lower, ratio.limits.upper, null, null, exact.lower, exact.upper };
    for (names, labels, values) |name, label, value| {
        const display = if (name.len == 0) "" else if (value) |x| (if (std.math.isInf(x)) "Infinity" else std.mem.trim(u8, try fmt.apply(a, numeric(x), "10.4"), " ")) else ".";
        try t.row(&.{ b.s(table_name), b.s(name), b.s(label), b.s(display), numeric(value) });
    }
}

pub fn publish(a: A, d: *diag.Diagnostics, capture: *ods.Capture, source: *const Dataset, by: []const usize, rep: ?[]const Value, tab: *model.Table, number: usize, m: model.CountMatrix, alpha: f64, estimates: report.Report, limits: public.RiskLimits) diag.Error!void {
    if (m.rows != 2 or m.cols != 2) return;
    const nd = tab.dimensions.len;
    const r = tab.dimensions[nd - 2].name;
    const c = tab.dimensions[nd - 1].name;
    const table = if (nd > 2) try std.fmt.allocPrint(a, "Table {d} of {s} * {s}", .{ number, r, c }) else try std.fmt.allocPrint(a, "Table {s} * {s}", .{ r, c });
    for ([_][]const u8{ "RiskDiffCol1", "RiskDiffCol2" }, [_][]const u8{ "RelRisk1ExactCL", "RelRisk2ExactCL" }, 0..) |rd_name, rr_name, col| {
        if (capture.wants(rd_name)) if (estimates.risk_columns[col]) |column| {
            var t = try b.Builder.init(a, source, by, rep);
            try riskDifference(a, &t, table, col, alpha, column, limits.difference[col]);
            try capture.publish(a, d, rd_name, &t.ds);
        };
        if (capture.wants(rr_name)) if (limits.relative_risk[col]) |interval| {
            var t = try b.Builder.init(a, source, by, rep);
            try relativeRisk(a, &t, table, .{ .cells = m.counts[0..4].* }, col, alpha, interval);
            try capture.publish(a, d, rr_name, &t.ds);
        };
    }
}

test "M9 exact risk ODS schemas and column orientation through PROC FREQ" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lex = @import("../lexer.zig");
    var library = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    var capture: ods.Capture = .{};
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    for ([_][]const u8{ "r", "c", "n" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 4, 3, 2 }, 0..) |n, i| try ds.appendRow(&.{ b.n(@floatFromInt(1 + i / 2)), b.n(@floatFromInt(1 + i % 2)), b.n(n) });
    try library.put(ds.name, ds);
    try capture.parse(a, &d, try lex.tokenize(a, "ods output RelRisk1ExactCL=rr1 RelRisk2ExactCL=rr2 RiskDiffCol1=rd1 RiskDiffCol2=rd2;", &d));
    var listing: std.ArrayList(u8) = .empty;
    try @import("freq.zig").runFreq(.{ .arena = a, .diags = &d, .lib = &library, .capture = &capture }, &listing, try lex.tokenize(a, "proc freq data=sample;weight n / zeros;tables r*c / relrisk riskdiff alpha=.10;exact relrisk(method=score column=both) riskdiff(method=score column=both);run;", &d));
    try capture.finish(&library, &d);
    try std.testing.expect(!d.hasErrors());
    for ([_][]const u8{ "rd1", "rd2" }, 0..) |name, i| {
        const rs = library.find(name).?;
        try std.testing.expectEqual(@as(usize, 4), rs.rowCount());
        try std.testing.expectEqual(@as(usize, 9), rs.columns.items.len);
        for (rs.columns.items, [_][]const u8{ "Table", "Row", "Risk", "ASE", "LowerCL", "UpperCL", "ExactLowerCL", "ExactUpperCL", "Control" }, [_]usize{ 256, 12, 8, 8, 8, 8, 8, 8, 1 }) |col, field, len| {
            try std.testing.expectEqualStrings(field, col.name);
            try std.testing.expectEqual(len, col.len.?);
            if (col.type == .num) try std.testing.expectEqualStrings("7.4", col.format.?);
        }
        try std.testing.expectEqualStrings("90% Exact Lower Confidence Limit", rs.columns.items[6].label.?);
        try std.testing.expectEqualStrings("Table r * c", rs.row(0)[0].str);
        try std.testing.expectEqualStrings("Difference", rs.row(3)[1].str);
        try std.testing.expectEqualStrings("1", rs.row(3)[8].str);
        try std.testing.expectEqualStrings("", rs.row(0)[8].str);
        try std.testing.expectApproxEqAbs(if (i == 0) @as(f64, 0.01020621831301) else 0.34259168199887, rs.row(0)[6].num, 1e-12);
        // Native unconditional endpoints agree at the four displayed decimals.
        try std.testing.expectApproxEqAbs(if (i == 0) @as(f64, -0.8255) else -0.2132, rs.row(3)[6].num, 5e-5);
        try std.testing.expectApproxEqAbs(if (i == 0) @as(f64, 0.2132) else 0.8255, rs.row(3)[7].num, 5e-5);
    }
    for ([_][]const u8{ "rr1", "rr2" }, 0..) |name, i| {
        const rs = library.find(name).?;
        try std.testing.expectEqual(@as(usize, 9), rs.rowCount());
        try std.testing.expectEqual(@as(usize, 5), rs.columns.items.len);
        for (rs.columns.items, [_][]const u8{ "Table", "Name1", "Label1", "cValue1", "nValue1" }, [_]usize{ 256, 7, 22, 10, 8 }) |col, field, len| {
            try std.testing.expectEqualStrings(field, col.name);
            try std.testing.expectEqual(len, col.len.?);
        }
        try std.testing.expectEqualStrings("D12.3", rs.columns.items[4].format.?);
        try std.testing.expectEqualStrings("Asymptotic Conf Limits", rs.row(2)[2].str);
        try std.testing.expect(std.math.isNan(rs.row(2)[4].num));
        try std.testing.expectEqualStrings("Exact Conf Limits", rs.row(6)[2].str);
        try std.testing.expectEqualStrings(if (i == 0) "XU_RRC1" else "XU_RRC2", rs.row(8)[1].str);
        try std.testing.expectApproxEqAbs(if (i == 0) @as(f64, 1.63307915458703) else 5.29231468841894, rs.row(4)[4].num, 1e-12);
        // The ODS value is unrounded. Full M9 SCORE endpoint parity is open.
        try std.testing.expect(rs.row(8)[4].num != try std.fmt.parseFloat(f64, rs.row(8)[3].str));
    }
}
