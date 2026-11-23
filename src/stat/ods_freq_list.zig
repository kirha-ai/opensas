//! ODS LIST and CROSSLIST row layouts over the same FREQ counts and margins.
const std = @import("std");
const b = @import("ods_table.zig");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const freq = @import("freq.zig");
const model = @import("freq_table.zig");
const A = std.mem.Allocator;
const absent = Value.specialMissing('_');

fn display(a: A, v: Value) ![]const u8 {
    if (v == .str) return v.str;
    return std.mem.trim(u8, try @import("../format.zig").apply(a, v, "BEST12."), " ");
}
fn variable(a: A, t: *b.Builder, ds: *const Dataset, dim: model.Dimension, formatted: bool, totals: bool) !void {
    if (formatted) {
        var width = @max(dim.name.len, @as(usize, if (totals) 5 else 1));
        for (dim.levels) |level| width = @max(width, (try display(a, level.value)).len);
        const label = try @import("ods_freq.zig").uniqueName(a, &t.ds, try std.fmt.allocPrint(a, "F_{s}", .{dim.name}));
        try t.char(label, width);
        t.ds.setLabel(label, dim.name);
    }
    const name = try @import("ods_freq.zig").uniqueName(a, &t.ds, dim.name);
    const col = ds.columns.items[ds.indexOf(dim.name).?];
    _ = try t.ds.addColumnLike(name, col);
    if (!std.ascii.eqlIgnoreCase(name, dim.name)) t.ds.setLabel(name, col.label orelse col.name);
}
fn numeric(t: *b.Builder, field: []const u8, format: []const u8, label: []const u8) !void {
    try t.num(field, format);
    t.ds.setLabel(field, label);
}
fn tableTitle(a: A, dims: []const model.Dimension) ![]const u8 {
    const names = try a.alloc([]const u8, dims.len);
    for (dims, names) |dim, *name| name.* = dim.name;
    return std.fmt.allocPrint(a, "Table {s}", .{try std.mem.join(a, " * ", names)});
}

pub fn list(a: A, d: *diag.Diagnostics, capture: *ods.Capture, ds: *Dataset, by: []const usize, rep: ?[]const Value, tab: *model.Table, req: freq.Request, zeros: bool) !void {
    if (!capture.wants("List")) return;
    var t = try b.Builder.init(a, ds, by, rep);
    t.ds.label = "LIST Frequencies";
    try t.char("Table", 256);
    const title = try tableTitle(a, tab.dimensions);
    if (req.line_numbers) try t.num("Line", "2.");
    for (tab.dimensions) |dim| try variable(a, &t, ds, dim, true, false);
    try t.num("Frequency", "BEST8.");
    const show_pct = !req.nopercent and !tab.negative;
    if (show_pct) try t.num("Percent", "6.2");
    if (!req.nocum) {
        try numeric(&t, "CumFrequency", "BEST8.", "Cumulative Frequency");
        if (show_pct) try numeric(&t, "CumPercent", "6.2", "Cumulative Percent");
    }
    var cumulative: f64 = 0;
    var line_number: usize = 0;
    for (try tab.keys(a, !req.nosparse and (req.sparse or zeros), false)) |key| {
        const excluded = tab.excluded(key);
        if (excluded and !req.missprint) continue;
        if (!excluded) cumulative += tab.count(key);
        var row: std.ArrayList(Value) = .empty;
        try row.append(a, b.s(title));
        if (req.line_numbers) {
            line_number += 1;
            try row.append(a, b.n(@floatFromInt(line_number)));
        }
        for (0..tab.dimensions.len) |j| {
            const level = tab.level(key, j);
            try row.appendSlice(a, &.{ b.s(try display(a, level.value)), level.raw });
        }
        try row.append(a, b.n(tab.count(key)));
        if (show_pct) try row.append(a, b.n(tab.pct(key)));
        if (!req.nocum) {
            try row.append(a, if (excluded) Value.missing else b.n(cumulative));
            if (show_pct) try row.append(a, if (excluded) Value.missing else b.n(freq.percent(cumulative, tab.total)));
        }
        try t.row(row.items);
    }
    if (t.ds.rowCount() != 0) try capture.publish(a, d, "List", &t.ds);
}

pub fn crossList(a: A, d: *diag.Diagnostics, capture: *ods.Capture, ds: *Dataset, by: []const usize, rep: ?[]const Value, tab: *model.Table, req: freq.Request) !void {
    if (!capture.wants("CrossList")) return;
    const nd = tab.dimensions.len;
    const nr = tab.dimensions[nd - 2].levels.len;
    const nc = tab.dimensions[nd - 1].levels.len;
    if (nr == 0 or nc == 0) return;
    var t = try b.Builder.init(a, ds, by, rep);
    t.ds.label = "Crosstabulation Table";
    try t.char("Table", 256);
    for (tab.dimensions, 0..) |dim, j| try variable(a, &t, ds, dim, j >= nd - 2, true);
    const show_freq = !req.nofreq;
    const expected = req.expected and !tab.negative;
    const deviation = req.deviation and !tab.negative;
    const standardized = req.stdres and !tab.negative;
    const pearson = req.pearsonres and !tab.negative;
    const chi = req.cellchi2 and !tab.negative;
    const total_pct = req.totpct and nd > 2 and !tab.negative;
    const pct = !req.nopercent and !tab.negative;
    const row_pct = !req.norow and !tab.negative;
    const col_pct = !req.nocol and !tab.negative;
    if (show_freq) try numeric(&t, "Frequency", "BEST8.", "Frequency Count");
    if (expected) try numeric(&t, "Expected", "D8.", "Expected Frequency");
    if (deviation) try numeric(&t, "Deviation", "D8.", "Deviation from Expected Frequency");
    if (standardized) try numeric(&t, "StdResidual", "D8.", "Standardized Residual");
    if (pearson) try numeric(&t, "PearsonResidual", "D8.", "Pearson Residual");
    if (chi) try numeric(&t, "CellChiSquare", "D8.", "Cell Chi-Square");
    if (total_pct) try numeric(&t, "TotalPercent", "6.2", "Percent of Total Frequency");
    if (pct) try numeric(&t, "Percent", "6.2", "Percent of Two-Way Table Frequency");
    if (row_pct) try numeric(&t, "RowPercent", "6.2", "Percent of Row Frequency");
    if (col_pct) try numeric(&t, "ColPercent", "6.2", "Percent of Column Frequency");
    try numeric(&t, "Missing", "BEST8.", "Frequency Missing");
    try t.char("_SkipLine", 1);
    var number: usize = 0;
    for (0..tab.cell_count / (nr * nc)) |stratum| {
        const first = stratum * nr * nc;
        var hidden = false;
        for (0..nd - 2) |j| if (tab.level(first, j).missing and !req.missing and !req.missprint) {
            hidden = true;
        };
        const sl = try tab.slice(a, stratum);
        if (hidden or (sl.total == 0 and sl.missing == 0)) continue;
        number += 1;
        const rname = tab.dimensions[nd - 2].name;
        const cname = tab.dimensions[nd - 1].name;
        const title = if (nd == 2) try tableTitle(a, tab.dimensions) else try std.fmt.allocPrint(a, "Table {d} of {s} * {s}", .{ number, rname, cname });
        var started = false;
        for (0..nr + 1) |ri| {
            const row_missing = ri < nr and sl.rows()[ri].missing and !req.missing;
            if (row_missing and !req.missprint) continue;
            if (ri < nr and req.nosparse and sl.row_totals[ri] == 0 and !row_missing) continue;
            var first_visible = true;
            for (0..nc + 1) |ci| {
                const col_missing = ci < nc and sl.cols()[ci].missing and !req.missing;
                if (col_missing and !req.missprint) continue;
                const cell = ri < nr and ci < nc;
                const total = ri == nr and ci == nc;
                if ((ci == nc and row_missing) or (req.nosparse and cell and sl.count(ri, ci) == 0)) continue;
                const amount = if (cell) sl.count(ri, ci) else if (total) sl.total else if (ci == nc) sl.row_totals[ri] else sl.col_totals[ci];
                var row: std.ArrayList(Value) = .empty;
                try row.append(a, b.s(title));
                for (0..nd - 2) |j| try row.append(a, tab.level(first, j).raw);
                for ([_]usize{ ri, ci }, tab.dimensions[nd - 2 ..]) |idx, dim| {
                    if (idx < dim.levels.len) {
                        const lev = dim.levels[idx];
                        try row.appendSlice(a, &.{ b.s(try display(a, lev.value)), lev.raw });
                    } else {
                        const c = ds.columns.items[ds.indexOf(dim.name).?];
                        try row.appendSlice(a, &.{ b.s("Total"), if (c.type == .num) Value.missing else b.s("") });
                    }
                }
                const m = if (cell) sl.metrics(ri, ci) else undefined;
                if (show_freq) try row.append(a, b.n(amount));
                if (expected) try row.append(a, if (cell) b.n(m.expected) else absent);
                if (deviation) try row.append(a, if (cell) b.n(m.deviation) else absent);
                if (standardized) try row.append(a, if (cell) b.n(m.standardized) else absent);
                if (pearson) try row.append(a, if (cell) b.n(m.pearson) else absent);
                if (chi) try row.append(a, if (cell) b.n(m.chi2) else absent);
                if (total_pct) try row.append(a, if (row_missing or col_missing) Value.missing else b.n(freq.percent(amount, tab.total)));
                if (pct) try row.append(a, if (row_missing or col_missing) Value.missing else b.n(freq.percent(amount, sl.total)));
                if (row_pct) try row.append(a, if (cell) b.n(m.row_percent) else if (ri == nr) absent else b.n(100));
                if (col_pct) try row.append(a, if (cell) b.n(m.col_percent) else if (ci == nc) absent else if (col_missing) Value.missing else b.n(100));
                try row.append(a, if (total) b.n(if (req.missprint) 0 else sl.missing) else Value.missing);
                try row.append(a, b.s(if (ci == nc) "1" else if (first_visible and started) "-" else ""));
                first_visible = false;
                started = true;
                try t.row(row.items);
            }
        }
    }
    if (t.ds.rowCount() != 0) try capture.publish(a, d, "CrossList", &t.ds);
}
