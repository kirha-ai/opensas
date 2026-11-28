//! CORR matrix datasets (SAS/STAT 9.4 pp. 35–37). The rows are assembled
//! from the same group and pair results used by the procedure's listing.
const std = @import("std");
const corr = @import("corr.zig");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const io = @import("../io.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const nan = std.math.nan(f64);

pub const Kind = enum { outp, outs, outk, outh, outplc, outpls };
pub const Spec = struct { kind: Kind, name: []const u8, options: []const lex.Token = &.{} };
pub fn kindOf(name: []const u8) ?Kind {
    if (std.ascii.eqlIgnoreCase(name, "out")) return .outp;
    inline for (std.meta.fields(Kind)) |field| if (std.ascii.eqlIgnoreCase(name, field.name)) return @enumFromInt(field.value);
    return null;
}

pub fn write(cx: proc.ProcCtx, result: corr.Result) diag.Error!void {
    const s = result.spec;
    const a = cx.arena;
    var outputs: std.ArrayList(*Dataset) = .empty;
    for (s.outputs) |output| {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, output.name);
        for (s.by) |c| try ds.columns.append(a, s.ds.columns.items[c]);
        const sscp = output.kind == .outp and s.options.sscp and s.partial.len == 0;
        const rowcols = if (s.with.len > 0) s.with else s.vars;
        var name_length: usize = if (sscp) "Intercept".len else 8;
        for (rowcols) |c| name_length = @max(name_length, s.ds.columns.items[c].name.len);
        try ds.columns.append(a, .{ .name = "_TYPE_", .type = .char, .len = 8 });
        try ds.columns.append(a, .{ .name = "_NAME_", .type = .char, .len = name_length });
        if (sscp) try ds.columns.append(a, .{ .name = "Intercept", .type = .num, .len = 8 });
        for (s.vars) |c| {
            const col = s.ds.columns.items[c];
            if (ds.indexOf(col.name) != null) return proc.failGap(cx.diags, 0, "PROC CORR: overlapping BY, matrix, or reserved output column {s} is not supported", .{col.name});
            try ds.columns.append(a, .{ .name = col.name, .type = .num, .len = 8, .label = col.label });
        }
        for (result.groups) |group| {
            const cells = try a.alloc(Value, ds.columns.items.len);
            for (s.by, 0..) |c, i| cells[i] = group.by_values.?[c];
            const row = Row{ .ds = ds, .cells = cells, .key = s.by.len, .intercept = sscp };
            const simple = try a.alloc(corr.Simple, s.ds.columns.items.len);
            for (group.simple) |v| simple[v.column] = v;
            if (sscp) {
                for (s.vars, row.values()) |c, *v| v.* = .{ .num = simple[c].sum };
                try row.save("SSCP", "Intercept", group.sum_weights);
                try matrix(row, s, group, simple, "SSCP", "sscp");
            }
            if (output.kind == .outp and s.options.csscp) try matrix(row, s, group, simple, "CSSCP", "cross");
            if (output.kind == .outp and s.options.cov) try matrix(row, s, group, simple, "COV", "covariance");
            for ([_][]const u8{ "MEAN", "STD", "N", "SUMWGT" }, 0..) |tag, i| {
                if (i == 3 and s.weight == null) continue;
                for (s.vars, row.values()) |c, *v| {
                    const stat = simple[c];
                    v.* = .{ .num = switch (i) {
                        0 => if (s.partial.len == 0) stat.mean else if (s.options.pearson) 0 else nan,
                        1 => if (s.partial.len == 0) stat.stddev else if (s.options.pearson) @sqrt(stat.partial_variance) else nan,
                        2 => stat.n,
                        else => stat.sum_weights,
                    } };
                }
                try row.save(tag, "", switch (i) {
                    0 => 1,
                    1 => 0,
                    2 => group.n,
                    else => group.sum_weights,
                });
            }
            if (output.kind == .outp) if (group.alpha) |alpha| {
                for ([_][]const u8{ "RAWALPHA", "STDALPHA", "RAWALDEL", "STDALDEL", "RAWCTDEL", "STDCTDEL" }, 0..) |tag, i| {
                    for (row.values(), alpha.deleted) |*v, deleted| v.* = .{ .num = switch (i) {
                        0 => alpha.raw,
                        1 => alpha.standardized,
                        2 => deleted.raw,
                        3 => deleted.standardized,
                        4 => deleted.raw_correlation,
                        else => deleted.standardized_correlation,
                    } };
                    try row.save(tag, "", group.n);
                }
            };
            if (output.kind == .outplc or output.kind == .outpls) {
                const pairs = if (output.kind == .outplc) group.polychoric else group.polyserial;
                const estimates = try a.alloc(f64, rowcols.len * s.vars.len);
                @memset(estimates, nan);
                for (pairs) |p| {
                    const i = std.mem.indexOfScalar(usize, rowcols, p.row).?;
                    const j = std.mem.indexOfScalar(usize, s.vars, p.column).?;
                    estimates[i * s.vars.len + j] = p.estimate.r;
                    if (s.with.len == 0) estimates[j * s.vars.len + i] = p.estimate.r;
                }
                for (rowcols, 0..) |r, i| {
                    if (s.with.len == 0) estimates[i * s.vars.len + i] = if (simple[r].stddev > 0) 1 else nan;
                    for (row.values(), estimates[i * s.vars.len ..][0..s.vars.len]) |*v, x| v.* = .{ .num = x };
                    try row.save("CORR", s.ds.columns.items[r].name, nan);
                }
            } else {
                const pairs = switch (output.kind) {
                    .outp => group.pairs,
                    .outs => group.spearman,
                    .outk => group.kendall,
                    .outh => group.hoeffding,
                    else => unreachable,
                };
                for (rowcols, 0..) |r, i| {
                    for (row.values(), pairs[i * s.vars.len ..][0..s.vars.len]) |*v, p| v.* = .{ .num = p.r };
                    try row.save("CORR", s.ds.columns.items[r].name, nan);
                }
            }
        }
        // STAT-REG-001: every CORR output (OUTP=/OUTS=/OUTK=/OUTH=/OUTPLC=/
        // OUTPLS=, also with COV, SSCP, CSSCP, ALPHA, PARTIAL, WITH) is TYPE=CORR
        // (SAS 9.4 ATTRC run). Without it PROC REG fitted the summary rows as
        // observations. A TYPE= data set option on the output still overrides.
        ds.ds_type = "CORR";
        if (output.options.len > 0) try io.applyDatasetOptions(a, ds, output.options, cx.diags, false);
        try outputs.append(a, ds);
    }
    for (outputs.items) |ds| try cx.lib.put(ds.name, ds);
}

const Row = struct {
    ds: *Dataset,
    cells: []Value,
    key: usize,
    intercept: bool,
    fn values(row: Row) []Value {
        return row.cells[row.key + 2 + @intFromBool(row.intercept) ..];
    }
    fn save(row: Row, tag: []const u8, name: []const u8, intercept: f64) !void {
        row.cells[row.key] = .{ .str = tag };
        row.cells[row.key + 1] = .{ .str = name };
        if (row.intercept) row.cells[row.key + 2] = .{ .num = intercept };
        try row.ds.appendRow(row.cells);
    }
};

fn matrix(row: Row, s: corr.Spec, g: corr.Group, simple: []const corr.Simple, comptime tag: []const u8, comptime field: []const u8) !void {
    const rowcols = if (s.with.len > 0) s.with else s.vars;
    for (rowcols, 0..) |r, i| {
        for (row.values(), g.pairs[i * s.vars.len ..][0..s.vars.len]) |*v, p| v.* = .{ .num = @field(p, field) };
        try row.save(tag, s.ds.columns.items[r].name, if (std.mem.eql(u8, tag, "SSCP")) simple[r].sum else nan);
    }
}
