//! ODS FREQ schemas built from typed levels, counts, margins and cell metrics.
const std = @import("std");
const ods = @import("../ods.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const freq = @import("freq.zig");
const model = @import("freq_table.zig");
const b = @import("ods_table.zig");
const nan = std.math.nan(f64);
fn text(a: std.mem.Allocator, v: Value) ![]const u8 {
    return if (v == .str) v.str else std.mem.trim(u8, try @import("../format.zig").apply(a, v, "BEST12."), " ");
}
pub fn publish(a: std.mem.Allocator, d: *diag.Diagnostics, capture: *ods.Capture, ds: *Dataset, by: []const usize, rep: ?[]const Value, tab: *model.Table, req: freq.Request) diag.Error!void {
    const one = tab.dimensions.len == 1;
    const name = if (one) "OneWayFreqs" else "CrossTabFreqs";
    if (!capture.wants(name) or (!one and req.list)) return;
    if (!one and req.crosslist) return; // SAS produces CrossList, not CrossTabFreqs.
    if (one) if (req.maxlevels) |limit| if (tab.dimensions[0].levels.len > limit) return;
    var t = try b.Builder.init(a, ds, by, rep);
    t.ds.label = if (one) "One-Way Frequencies" else "Frequency Counts and Percentages";
    try t.char("Table", 256);
    var table: std.ArrayList(u8) = .empty;
    try table.appendSlice(a, "Table ");
    for (tab.dimensions, 0..) |dim, i| {
        if (i > 0) try table.appendSlice(a, " * ");
        try table.appendSlice(a, dim.name);
    }
    if (one) {
        const dim = tab.dimensions[0];
        const f = try std.fmt.allocPrint(a, "F_{s}", .{dim.name});
        var width: usize = 1;
        for (dim.levels) |l| width = @max(width, (try text(a, l.value)).len);
        try t.char(f, width);
        t.ds.setLabel(f, dim.label orelse dim.name);
        const rawname = try uniqueName(a, &t.ds, dim.name);
        _ = try t.ds.addColumnLike(rawname, ds.columns.items[ds.indexOf(dim.name).?]);
        if (!std.ascii.eqlIgnoreCase(rawname, dim.name)) t.ds.setLabel(rawname, dim.label orelse dim.name);
        try t.num("Frequency", "BEST8.");
        if (!req.nopercent and !tab.negative) try t.num("Percent", "6.2");
        if (!req.nocum) {
            try t.num("CumFrequency", "BEST8.");
            t.ds.setLabel("CumFrequency", "Cumulative Frequency");
            if (!req.nopercent and !tab.negative) {
                try t.num("CumPercent", "6.2");
                t.ds.setLabel("CumPercent", "Cumulative Percent");
            }
        }
        var cum: f64 = 0;
        for (dim.levels, 0..) |l, k| {
            if (tab.excluded(k) and !req.missprint) continue;
            const cnt = tab.count(k);
            if (!tab.excluded(k)) cum += cnt;
            var row: std.ArrayList(Value) = .empty;
            try row.appendSlice(a, &.{ b.s(table.items), b.s(try text(a, l.value)), l.raw, b.n(cnt) });
            if (!req.nopercent and !tab.negative) try row.append(a, b.n(tab.pct(k)));
            if (!req.nocum) {
                try row.append(a, b.n(if (tab.excluded(k)) nan else cum));
                if (!req.nopercent and !tab.negative) try row.append(a, b.n(if (tab.negative or tab.excluded(k)) nan else freq.percent(cum, tab.total)));
            }
            try t.row(row.items);
        }
    } else {
        for (tab.dimensions) |dim| {
            const rawname = try uniqueName(a, &t.ds, dim.name);
            _ = try t.ds.addColumnLike(rawname, ds.columns.items[ds.indexOf(dim.name).?]);
        }
        try t.char("_TYPE_", tab.dimensions.len);
        t.ds.setLabel("_TYPE_", "Variables Contributing to Observation");
        try t.num("_TABLE_", null);
        t.ds.setLabel("_TABLE_", "Table Number");
        try t.num("Frequency", "BEST7.");
        t.ds.setLabel("Frequency", "Frequency Count");
        if (req.expected and !tab.negative) {
            try t.num("Expected", "BEST6.");
            t.ds.setLabel("Expected", "Expected Frequency");
        }
        if (req.deviation and !tab.negative) {
            try t.num("Deviation", "BEST6.");
            t.ds.setLabel("Deviation", "Deviation from Expected Frequency");
        }
        if (req.cellchi2 and !tab.negative) {
            try t.num("CellChiSquare", "BEST6.");
            t.ds.setLabel("CellChiSquare", "Cell Chi-Square");
        }
        if ((req.totpct and !tab.negative) and tab.dimensions.len > 2) {
            try t.num("TotalPercent", "F6.2");
            t.ds.setLabel("TotalPercent", "Percent of Total Frequency");
        }
        if (!req.nopercent and !tab.negative) {
            try t.num("Percent", "F6.2");
            t.ds.setLabel("Percent", "Percent of Two-Way Table Frequency");
        }
        if (!req.norow and !tab.negative) {
            try t.num("RowPercent", "F6.2");
            t.ds.setLabel("RowPercent", "Percent of Row Frequency");
        }
        if (!req.nocol and !tab.negative) {
            try t.num("ColPercent", "F6.2");
            t.ds.setLabel("ColPercent", "Percent of Column Frequency");
        }
        if (req.cumcol and !tab.negative) {
            try t.num("CumColPercent", "F6.2");
            t.ds.setLabel("CumColPercent", "Cumulative Percent of Column Frequency");
        }
        try t.num("Missing", null);
        t.ds.setLabel("Missing", "Frequency Missing");
        const nd = tab.dimensions.len;
        const nr = tab.dimensions[nd - 2].levels.len;
        const nc = tab.dimensions[nd - 1].levels.len;
        if (nr == 0 or nc == 0) return;
        for (0..tab.cell_count / (nr * nc)) |stratum| {
            const sl = try tab.slice(a, stratum);
            var control_missing = false;
            for (0..nd - 2) |j| control_missing = control_missing or tab.level(stratum * nr * nc, j).missing;
            if (control_missing and !tab.include_missing) continue;
            const table_name = if (nd > 2) try std.fmt.allocPrint(a, "Table {d} of {s} * {s}", .{ stratum + 1, tab.dimensions[nd - 2].name, tab.dimensions[nd - 1].name }) else table.items;
            for (0..nr + 1) |ri| {
                if (ri < nr and sl.rows()[ri].missing and !tab.include_missing and !req.missprint) continue;
                for (0..nc + 1) |ci| {
                    if (ci < nc and sl.cols()[ci].missing and !tab.include_missing and !req.missprint) continue;
                    const iscell = ri < nr and ci < nc;
                    const total = ri == nr and ci == nc;
                    const count = if (iscell) sl.count(ri, ci) else if (total) sl.total else if (ci == nc) sl.row_totals[ri] else sl.col_totals[ci];
                    if (req.nosparse and iscell and count == 0) continue;
                    var row: std.ArrayList(Value) = .empty;
                    try row.append(a, b.s(table_name));
                    for (0..nd) |j| {
                        const level = if (j == nd - 2) ri else if (j == nd - 1) ci else (stratum * nr * nc / tab.strides[j]) % tab.dimensions[j].levels.len;
                        const dim = tab.dimensions[j];
                        try row.append(a, if (level < dim.levels.len) dim.levels[level].raw else if (ds.columns.items[ds.indexOf(dim.name).?].type == .num) Value.missing else b.s(""));
                    }
                    const kind = try a.alloc(u8, nd);
                    @memset(kind, '1');
                    if (ri == nr) kind[nd - 2] = '0';
                    if (ci == nc) kind[nd - 1] = '0';
                    try row.appendSlice(a, &.{ b.s(kind), b.n(@floatFromInt(stratum + 1)), b.n(count) });
                    const metrics = if (iscell) sl.metrics(ri, ci) else undefined;
                    if (req.expected and !tab.negative) try row.append(a, b.n(if (iscell) metrics.expected else nan));
                    if (req.deviation and !tab.negative) try row.append(a, b.n(if (iscell) metrics.deviation else nan));
                    if (req.cellchi2 and !tab.negative) try row.append(a, b.n(if (iscell) metrics.chi2 else nan));
                    if ((req.totpct and !tab.negative) and nd > 2) try row.append(a, b.n(if (tab.negative or (iscell and sl.excluded(ri, ci))) nan else freq.percent(count, tab.total)));
                    if (!req.nopercent and !tab.negative) try row.append(a, b.n(if (tab.negative or (iscell and sl.excluded(ri, ci))) nan else freq.percent(count, sl.total)));
                    if (!req.norow and !tab.negative) try row.append(a, b.n(if (iscell) metrics.row_percent else nan));
                    if (!req.nocol and !tab.negative) try row.append(a, b.n(if (iscell) metrics.col_percent else nan));
                    if (req.cumcol and !tab.negative) {
                        var cumulative: f64 = 0;
                        if (ri < nr and ci == nc) for (sl.row_totals[0 .. ri + 1]) |v| {
                            cumulative += v;
                        };
                        try row.append(a, b.n(if (iscell) metrics.cumcol else if (ri < nr and !tab.negative) freq.percent(cumulative, sl.total) else nan));
                    }
                    try row.append(a, b.n(if (total) sl.missing else nan));
                    try t.row(row.items);
                }
            }
        }
    }
    if (t.ds.rows.items.len > 0) try capture.publish(a, d, name, &t.ds);
}

fn uniqueName(a: std.mem.Allocator, ds: *Dataset, name: []const u8) ![]const u8 {
    if (ds.indexOf(name) == null) return name;
    var suffix: usize = 2;
    while (true) : (suffix += 1) {
        const candidate = try std.fmt.allocPrint(a, "{s}{d}", .{ name, suffix });
        if (ds.indexOf(candidate) == null) return candidate;
    }
}
