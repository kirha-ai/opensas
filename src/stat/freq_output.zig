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

pub const Option = enum { n, nmiss, chisq, pchi, lrchi, fisher };
pub const Spec = struct {
    name: ?[]const u8 = null,
    dataset_options: []const lex.Token = &.{},
    requested: std.EnumSet(Option) = .empty,
};

/// Returns null when no statistic was requested in the corresponding TABLES
/// statement. This warning does not create or replace a member of WORK.
pub fn create(cx: proc.ProcCtx, spec: Spec, req: anytype, input: *data.Dataset, by: []const usize) diag.Error!?*Writer {
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
    const all = spec.requested.contains(.chisq) and req.statistics.chisq;
    const one = req.vars.len == 1;
    const report_n = spec.requested.contains(.n) or all;
    if (report_n) try column(ds, "N", if (one) "Number of Subjects" else "Number of Subjects in the Stratum");
    if (spec.requested.contains(.nmiss)) try column(ds, "NMISS", "Number of Missing Subjects");
    const pearson = req.statistics.chisq and (all or spec.requested.contains(.pchi));
    const lr = req.statistics.chisq and (all or spec.requested.contains(.lrchi)) and (!one or req.statistics.lrchi);
    const writer = try a.create(Writer);
    writer.* = .{ .ds = ds, .by = by, .controls = controls.items, .report_n = report_n, .report_missing = spec.requested.contains(.nmiss), .pearson = pearson, .lr = lr, .all_crosstab = all and !one, .warning = pearson and req.statistics.warn.output };
    return writer;
}
fn column(ds: *data.Dataset, name: []const u8, label: []const u8) !void {
    try ds.columns.append(ds.arena, .{ .name = name, .type = .num, .len = 8, .label = label });
}
fn testColumns(ds: *data.Dataset, comptime name: []const u8, comptime label: []const u8) !void {
    try column(ds, "_" ++ name ++ "_", label);
    try column(ds, "DF_" ++ name, "DF for " ++ label);
    try column(ds, "P_" ++ name, "P-value for " ++ label);
}
const Record = struct {
    prefix: []const Value,
    n: f64,
    nmiss: f64,
    report: reports.Report,
};

pub const Writer = struct {
    ds: *data.Dataset,
    by: []const usize,
    controls: []const usize,
    report_n: bool,
    report_missing: bool,
    pearson: bool,
    lr: bool,
    all_crosstab: bool,
    warning: bool,
    binary: bool = false,
    records: std.ArrayList(Record) = .empty,

    pub fn append(self: *Writer, by_row: ?[]const Value, table: *const model.Table, key: usize, n: f64, nmiss: f64, report: reports.Report, two_by_two: bool) !void {
        const a = self.ds.arena;
        const prefix = try a.alloc(Value, self.by.len + self.controls.len);
        for (self.by, prefix[0..self.by.len]) |i, *v| v.* = by_row.?[i];
        for (self.controls, prefix[self.by.len..]) |dim, *v| v.* = table.level(key, dim).raw;
        self.binary = self.binary or two_by_two;
        try self.records.append(a, .{ .prefix = prefix, .n = n, .nmiss = nmiss, .report = report });
    }

    /// Binary-only columns occur in their native positions even when a later
    /// BY group or stratum is the first 2x2 table. The other rows receive
    /// ordinary numeric missing values in those columns.
    pub fn finish(self: *Writer) !void {
        const ds = self.ds;
        const a = ds.arena;
        if (self.pearson) try testColumns(ds, "PCHI", "Chi-Square");
        if (self.warning) try column(ds, "WARN_PCHI", "Chi-Square Warning");
        if (self.lr) try testColumns(ds, "LRCHI", "Likelihood Ratio Chi-Square");
        if (self.all_crosstab) {
            if (self.binary) {
                try testColumns(ds, "AJCHI", "Continuity Adjusted Chi-Square");
                ds.setLabel("P_AJCHI", "P-value for Continuity Adj. Chi-Square");
            }
            try testColumns(ds, "MHCHI", "Mantel-Haenszel Chi-Square");
            if (self.binary) {
                try column(ds, "XPL_FISH", "Fisher's Exact Test P-value (Left)");
                try column(ds, "XPR_FISH", "Fisher's Exact Test P-value (Right)");
                try column(ds, "XP2_FISH", "Fisher's Exact Test P-value (2-Tail)");
            }
            try column(ds, "_PHI_", "Phi Coefficient");
            try column(ds, "_CONTGY_", "Contingency Coefficient");
            try column(ds, "_CRAMV_", "Cramer's V");
        }
        for (self.records.items) |record| {
            const result = record.report;
            var row: std.ArrayList(Value) = .empty;
            try row.appendSlice(a, record.prefix);
            if (self.report_n) try row.append(a, .{ .num = record.n });
            if (self.report_missing) try row.append(a, .{ .num = record.nmiss });
            if (self.pearson) try testValues(a, &row, if (result.chi_square) |chi| chi.pearson else if (result.goodness_of_fit) |gof| gof.pearson else null);
            if (self.warning) try row.append(a, if (result.warning) |warn| .{ .num = @floatFromInt(@intFromBool(warn)) } else Value.missing);
            if (self.lr) try testValues(a, &row, if (result.chi_square) |chi| chi.likelihood_ratio else if (result.goodness_of_fit) |gof| gof.likelihood_ratio else null);
            if (self.all_crosstab) {
                const chi = result.chi_square;
                if (self.binary) try testValues(a, &row, if (chi) |v| v.continuity else null);
                try testValues(a, &row, if (chi) |v| v.mantel_haenszel else null);
                if (self.binary) {
                    const f = if (chi) |v| v.fisher else null;
                    if (f) |v| {
                        for ([_]f64{ v.left, v.right, v.two_sided }) |x| try row.append(a, .{ .num = x });
                    } else try row.appendNTimes(a, Value.missing, 3);
                }
                if (chi) |v| {
                    for ([_]f64{ v.phi, v.contingency, v.cramer_v }) |x| try row.append(a, .{ .num = x });
                } else try row.appendNTimes(a, Value.missing, 3);
            }
            try ds.appendRow(row.items);
        }
    }
};
fn testValues(a: std.mem.Allocator, row: *std.ArrayList(Value), result: ?Test) !void {
    if (result) |r| {
        for ([_]f64{ r.statistic, r.df, r.p }) |v| try row.append(a, .{ .num = v });
    } else try row.appendNTimes(a, Value.missing, 3);
}

test "M9 OUTPUT CHISQ unions binary columns across BY groups and enforces the TABLES contract" {
    const freq = @import("freq.zig");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = data.Dataset.init(a, "mixed");
    for ([_][]const u8{ "g", "r", "c", "n" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 1, 1, 1, 3 }, .{ 1, 1, 2, 4 }, .{ 1, 2, 1, 5 }, .{ 1, 2, 2, 6 }, .{ 1, 3, 1, 9 }, .{ 1, 3, 2, 7 }, .{ 2, 1, 1, 1.5 }, .{ 2, 2, 1, 1 }, .{ 2, 1, 2, 3 }, .{ 2, 2, 2, 5 }, .{ 3, 2, 1, 3 }, .{ 3, 2, 2, 2 }, .{ 3, 1, 1, 4 }, .{ 3, 1, 2, 7 } }) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] } });
    try lib.put("mixed", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var listing: std.ArrayList(u8) = .empty;
    try freq.runFreq(cx, &listing, try lex.tokenize(a, "proc freq data=mixed noprint; by g; weight n; tables r*c / chisq; output out=captured chisq; run;", &d));
    const result = lib.find("captured").?;
    try std.testing.expectEqual(@as(usize, 3), result.rowCount());
    try std.testing.expectEqual(@as(usize, 20), result.columns.items.len);
    try std.testing.expectEqualStrings("P-value for Continuity Adj. Chi-Square", result.columns.items[result.indexOf("P_AJCHI").?].label.?);
    try std.testing.expect(result.row(0)[result.indexOf("_AJCHI_").?].isMissing());
    try std.testing.expectEqual(@as(f64, 10.5), result.row(1)[result.indexOf("N").?].num);
    try std.testing.expect(result.row(1)[result.indexOf("XP2_FISH").?].isMissing());
    try std.testing.expectApproxEqAbs(@as(f64, 0.596153846153846), result.row(2)[result.indexOf("XP2_FISH").?].num, 1e-11);
    try freq.runFreq(cx, &listing, try lex.tokenize(a, "proc freq data=mixed; tables r*c; output out=unproduced chisq; run;", &d));
    try std.testing.expect(lib.find("unproduced") == null);
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "no statistic options are specified") != null);
    try std.testing.expectError(error.ParseError, freq.runFreq(cx, &listing, try lex.tokenize(a, "proc freq data=mixed; output out=invalid chisq; run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "OUTPUT requires a TABLES statement") != null);
}
