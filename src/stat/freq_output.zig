//! Statistical rows from the last PROC FREQ table request (SAS/STAT pp. 90–101,
//! 236–237). TABLES OUT= writes its own cell dataset independently.
const std = @import("std");
const Value = @import("../value.zig").Value;
const data = @import("../dataset.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const model = @import("freq_table.zig");
const reports = @import("freq_tests_execute.zig");
const Test = @import("freq_tests.zig").Test;

pub const Option = enum { n, nmiss, pchi, lrchi, fisher };
pub const Spec = struct {
    name: ?[]const u8 = null,
    dataset_options: []const lex.Token = &.{},
    requested: std.EnumSet(Option) = .empty,
};

/// Returns null when no statistic was requested in the corresponding TABLES
/// statement. This warning does not create or replace a member of WORK.
pub fn create(cx: proc.ProcCtx, spec: Spec, req: anytype, input: *data.Dataset, by: []const usize) diag.Error!?Writer {
    const count = spec.requested.contains(.n) or spec.requested.contains(.nmiss);
    if (!req.statistics.chisq and !count) {
        if (req.statistics.measures or req.statistics.plcorr or req.risk.any() or req.exact.families.count() != 0 or req.stratified.cmh != 0 or req.stratified.agreement.enabled or req.stratified.jt or req.stratified.trend or req.stratified.common.enabled or req.stratified.gail_simon)
            return proc.failGap(cx.diags, 0, "PROC FREQ: this combination of statistical OUTPUT requests is not implemented", .{});
        try cx.diags.report(.warning, 0, "No OUTPUT data set is produced because no statistic options are specified in the corresponding TABLES statement.", .{});
        return null;
    }
    if (spec.requested.contains(.fisher) or req.exact.families.count() != 0)
        return proc.failGap(cx.diags, 0, "PROC FREQ: exact test OUTPUT is not implemented", .{});
    const a = cx.arena;
    const name = spec.name orelse blk: {
        var n: usize = 1;
        while (true) : (n += 1) {
            const candidate = try std.fmt.allocPrint(a, "data{d}", .{n});
            if (cx.lib.find(candidate) == null and (req.out_name == null or !proc.eqi(req.out_name.?, candidate))) break :blk candidate;
        }
    };
    const ds = try a.create(data.Dataset);
    ds.* = data.Dataset.init(a, name);
    for (by) |i| try ds.columns.append(a, input.columns.items[i]);
    var controls: std.ArrayList(usize) = .empty;
    for (req.vars[0..req.vars.len -| 2], 0..) |var_name, i| {
        if (ds.indexOf(var_name) != null) continue;
        try controls.append(a, i);
        try ds.columns.append(a, input.columns.items[input.indexOf(var_name).?]);
    }
    if (spec.requested.contains(.n)) try column(ds, "N", "Number of Nonmissing Observations");
    if (spec.requested.contains(.nmiss)) try column(ds, "NMISS", "Number of Missing Observations");
    const pearson = req.statistics.chisq and spec.requested.contains(.pchi);
    const lr = req.statistics.chisq and spec.requested.contains(.lrchi) and (req.vars.len > 1 or req.statistics.lrchi);
    if (pearson) try testColumns(ds, "PCHI", "Chi-Square");
    if (lr) try testColumns(ds, "LRCHI", "Likelihood Ratio Chi-Square");
    if (pearson and req.statistics.warn.output) try column(ds, "WARN_PCHI", "Warning for Chi-Square");
    return .{ .ds = ds, .by = by, .controls = controls.items, .requested = spec.requested, .pearson = pearson, .lr = lr, .warning = pearson and req.statistics.warn.output };
}
fn column(ds: *data.Dataset, name: []const u8, label: []const u8) !void {
    try ds.columns.append(ds.arena, .{ .name = name, .type = .num, .len = 8, .label = label });
}
fn testColumns(ds: *data.Dataset, comptime name: []const u8, comptime label: []const u8) !void {
    try column(ds, "_" ++ name ++ "_", label);
    try column(ds, "DF_" ++ name, "DF for " ++ label);
    try column(ds, "P_" ++ name, "P-value for " ++ label);
}
pub const Writer = struct {
    ds: *data.Dataset,
    by: []const usize,
    controls: []const usize,
    requested: std.EnumSet(Option),
    pearson: bool,
    lr: bool,
    warning: bool,

    pub fn append(self: Writer, by_row: ?[]const Value, table: *const model.Table, key: usize, n: f64, nmiss: f64, report: reports.Report) !void {
        const a = self.ds.arena;
        var row: std.ArrayList(Value) = .empty;
        for (self.by) |i| try row.append(a, by_row.?[i]);
        for (self.controls) |d| try row.append(a, table.level(key, d).raw);
        if (self.requested.contains(.n)) try row.append(a, .{ .num = n });
        if (self.requested.contains(.nmiss)) try row.append(a, .{ .num = nmiss });
        if (self.pearson) try testValues(a, &row, if (report.chi_square) |chi| chi.pearson else if (report.goodness_of_fit) |gof| gof.pearson else null);
        if (self.lr) try testValues(a, &row, if (report.chi_square) |chi| chi.likelihood_ratio else if (report.goodness_of_fit) |gof| gof.likelihood_ratio else null);
        if (self.warning) try row.append(a, if (report.warning) |warning| .{ .num = @floatFromInt(@intFromBool(warning)) } else Value.missing);
        try self.ds.appendRow(row.items);
    }
};
fn testValues(a: std.mem.Allocator, row: *std.ArrayList(Value), result: ?Test) !void {
    if (result) |r| {
        for ([_]f64{ r.statistic, r.df, r.p }) |v| try row.append(a, .{ .num = v });
    } else try row.appendNTimes(a, Value.missing, 3);
}
