//! SAS ODS PearsonCorr and SimpleStats schemas over CORR's typed Result.
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
        if (!spec.options.nosimple and capture.wants("SimpleStats")) {
            var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
            t.ds.label = "Simple Statistics";
            try t.char("Variable", @max(8, name_len));
            for ([_][]const u8{ "NObs", "Mean", "StdDev", "Sum", "Min", "Max" }, 0..) |name, i| try t.num(name, if (i == 0) "8." else "D10.");
            t.ds.setLabel("NObs", "N");
            t.ds.setLabel("StdDev", "Std Dev");
            t.ds.setLabel("Min", "Minimum");
            t.ds.setLabel("Max", "Maximum");
            if (label_len > 0) try t.char("Label", label_len);
            for (group.simple) |v| {
                const c = spec.ds.columns.items[v.column];
                var cells = [_]Value{ b.s(c.name), b.n(v.n), b.n(v.mean), b.n(v.stddev), b.n(v.sum), b.n(v.minimum), b.n(v.maximum), b.s(c.label orelse "") };
                try t.row(cells[0..if (label_len > 0) 8 else 7]);
            }
            try capture.publish(a, d, "SimpleStats", &t.ds);
        }
        if (!spec.options.nocorr and capture.wants("PearsonCorr")) {
            var t = try b.Builder.init(a, spec.ds, spec.by, group.by_values);
            t.ds.label = "Pearson Correlations";
            try t.char("Variable", name_len);
            if (label_len > 0) try t.char("Label", label_len);
            var different_n = false;
            for (group.pairs) |p| if (p.n != group.pairs[0].n) {
                different_n = true;
            };
            for (spec.vars) |ci| try t.num(spec.ds.columns.items[ci].name, "8.5");
            if (!spec.options.noprob) for (spec.vars) |ci| try t.num(try std.fmt.allocPrint(a, "P{s}", .{spec.ds.columns.items[ci].name}), "PVALUE8.4");
            if (different_n) for (spec.vars) |ci| try t.num(try std.fmt.allocPrint(a, "N{s}", .{spec.ds.columns.items[ci].name}), "8.");
            const rows = if (spec.with.len > 0) spec.with else spec.vars;
            for (rows, 0..) |ri, row| {
                var cells: std.ArrayList(Value) = .empty;
                try cells.append(a, b.s(spec.ds.columns.items[ri].name));
                if (label_len > 0) try cells.append(a, b.s(spec.ds.columns.items[ri].label orelse ""));
                const pairs = group.pairs[row * spec.vars.len ..][0..spec.vars.len];
                for (pairs) |p| try cells.append(a, b.n(p.r));
                if (!spec.options.noprob) for (pairs) |p| try cells.append(a, if (p.row == p.column) Value.specialMissing('_') else b.n(p.p));
                if (different_n) for (pairs) |p| try cells.append(a, b.n(p.n));
                try t.row(cells.items);
            }
            try capture.publish(a, d, "PearsonCorr", &t.ds);
        }
    }
}
