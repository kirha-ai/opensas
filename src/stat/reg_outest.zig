//! REG OUTEST/COVOUT data producer. SAS/STAT 15.4 physical pp.8603–8604.
//! Values retain full binary precision; listing formats never alter stored data.
const std = @import("std");
const diag = @import("../diag.zig");
const data = @import("../dataset.zig");
const Value = @import("../value.zig").Value;
const parse = @import("reg_parse.zig");
const Fit = @import("reg_fit.zig").Fit;
const A = std.mem.Allocator;

pub const Builder = struct {
    ds: *data.Dataset,
    spec: parse.Spec,
    model_col: usize,
    type_col: usize,
    name_col: ?usize,
    dependent_col: usize,
    rmse_col: usize,
    intercept_col: ?usize,
    /// Indexed by the input descriptor; absent variables are not output columns.
    source_to_output: []?usize,

    pub fn init(a: A, spec: parse.Spec, d: *diag.Diagnostics) diag.Error!Builder {
        const name = spec.outest orelse return error.ExecError;
        const ds = try a.create(data.Dataset);
        ds.* = data.Dataset.init(a, name);
        for (spec.by) |ci| _ = try ds.addColumnLike(spec.ds.columns.items[ci].name, spec.ds.columns.items[ci]);
        const model_col = try add(ds, "_MODEL_", .char, 32, d);
        const type_col = try add(ds, "_TYPE_", .char, 8, d);
        const name_col = if (spec.covout) try add(ds, "_NAME_", .char, 32, d) else null;
        const dependent_col = try add(ds, "_DEPVAR_", .char, 32, d);
        const rmse_col = try add(ds, "_RMSE_", .num, 8, d);
        var intercept_col: ?usize = null;
        for (spec.models) |model| if (model.intercept) {
            intercept_col = try add(ds, "Intercept", .num, 8, d);
            break;
        };
        const mapping = try a.alloc(?usize, spec.ds.columns.items.len);
        @memset(mapping, null);
        for (spec.output_variables) |ci| {
            const column = spec.ds.columns.items[ci];
            mapping[ci] = try add(ds, column.name, .num, 8, d);
        }
        return .{ .ds = ds, .spec = spec, .model_col = model_col, .type_col = type_col, .name_col = name_col, .dependent_col = dependent_col, .rmse_col = rmse_col, .intercept_col = intercept_col, .source_to_output = mapping };
    }

    fn baseRow(self: Builder, a: A, model: parse.Model, by_row: ?[]const Value, fit: Fit) ![]Value {
        const cells = try a.alloc(Value, self.ds.columns.items.len);
        for (self.ds.columns.items, cells) |column, *cell| cell.* = if (column.type == .char) .{ .str = " " } else Value.missing;
        for (self.spec.by, 0..) |ci, j| cells[j] = by_row.?[ci];
        cells[self.model_col] = .{ .str = model.label };
        cells[self.type_col] = .{ .str = "PARMS" };
        cells[self.dependent_col] = .{ .str = self.spec.ds.columns.items[model.dependent].name };
        cells[self.rmse_col] = .{ .num = @sqrt(fit.mse) };
        return cells;
    }

    fn parameterColumn(self: Builder, model: parse.Model, j: usize) usize {
        if (model.intercept and j == 0) return self.intercept_col.?;
        return self.source_to_output[model.regressors[j - @as(usize, if (model.intercept) 1 else 0)]].?;
    }

    pub fn append(self: Builder, a: A, model: parse.Model, by_row: ?[]const Value, fit: Fit) diag.Error!void {
        const p = model.regressors.len + @as(usize, if (model.intercept) 1 else 0);
        if (fit.coefficients.len != p or fit.covariance.len != p * p or (self.spec.by.len > 0 and by_row == null)) return error.ExecError;
        const row = try self.baseRow(a, model, by_row, fit);
        for (fit.coefficients, 0..) |coefficient, j| row[self.parameterColumn(model, j)] = .{ .num = coefficient };
        row[self.source_to_output[model.dependent].?] = .{ .num = -1 };
        try self.ds.appendRow(row);
        if (self.name_col) |name_col| {
            for (0..p) |j| {
                const covariance_row = try self.baseRow(a, model, by_row, fit);
                covariance_row[self.type_col] = .{ .str = "COV" };
                covariance_row[name_col] = .{ .str = self.ds.columns.items[self.parameterColumn(model, j)].name };
                for (0..p) |k| covariance_row[self.parameterColumn(model, k)] = .{ .num = fit.covariance[j * p + k] };
                try self.ds.appendRow(covariance_row);
            }
        }
    }
};

fn add(ds: *data.Dataset, name: []const u8, kind: @import("../pdv.zig").VarType, len: usize, d: *diag.Diagnostics) diag.Error!usize {
    if (ds.indexOf(name) != null) {
        diag.markGap();
        return d.fail(error.ExecError, 0, "PROC REG OUTEST: output column collision for {s} is not supported", .{name});
    }
    const ci = try ds.addColumn(name, kind);
    ds.columns.items[ci].len = len;
    return ci;
}

fn sample(a: A, lib: *@import("../exec.zig").Library, name: []const u8, response_scale: f64, weight_scale: f64) !*data.Dataset {
    const ds = try a.create(data.Dataset);
    ds.* = data.Dataset.init(a, name);
    for ([_][]const u8{ "x", "y", "w", "f", "twice" }) |n| _ = try ds.addColumn(n, .num);
    for ([_]f64{ 1, 2, 2 }, 0..) |y, i| {
        const x: f64 = @floatFromInt(i);
        const multiplicity: f64 = if (i == 1) 2 else 1;
        try ds.appendRow(&.{ .{ .num = x }, .{ .num = y * response_scale }, .{ .num = multiplicity * weight_scale }, .{ .num = multiplicity }, .{ .num = 2 * x } });
    }
    try lib.put(name, ds);
    return ds;
}

fn execute(a: A, lib: *@import("../exec.zig").Library, d: *diag.Diagnostics, source: []const u8) !void {
    const tokens = try @import("../lexer.zig").tokenize(a, source, d);
    var listing: std.ArrayList(u8) = .empty;
    try @import("reg.zig").run(.{ .arena = a, .lib = lib, .diags = d }, &listing, tokens);
}

fn number(ds: *const data.Dataset, row: usize, name: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(name).?].num;
}

fn text(ds: *const data.Dataset, row: usize, name: []const u8) []const u8 {
    return ds.rows.items[row][ds.indexOf(name).?].str;
}

fn close(expected: f64, actual: f64) !void {
    try std.testing.expectApproxEqAbs(expected, actual, 1e-12 * @max(1, @abs(expected)));
}

test "STAT-COMMON-004 weighted OUTEST schema covariance and storage precision" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try sample(a, &lib, "sample", 1, 1);
    try execute(a, &lib, &d, "proc reg data=sample outest=work.est covout noprint; model y=x; weight w; run; quit;");
    const ds = lib.find("est").?;
    try std.testing.expectEqual(@as(usize, 3), ds.rows.items.len);
    const names = [_][]const u8{ "_MODEL_", "_TYPE_", "_NAME_", "_DEPVAR_", "_RMSE_", "Intercept", "x", "y" };
    try std.testing.expectEqual(names.len, ds.columns.items.len);
    for (names, ds.columns.items, 0..) |name, column, j| {
        try std.testing.expectEqualStrings(name, column.name);
        try std.testing.expectEqual(if (j < 4) @import("../pdv.zig").VarType.char else .num, column.type);
        try std.testing.expect(column.len != null);
    }
    try std.testing.expectEqualStrings("MODEL1", text(ds, 0, "_MODEL_"));
    try std.testing.expectEqualStrings("PARMS", text(ds, 0, "_TYPE_"));
    try std.testing.expectEqualStrings(" ", text(ds, 0, "_NAME_"));
    try std.testing.expectEqualStrings("COV", text(ds, 1, "_TYPE_"));
    try std.testing.expectEqualStrings("Intercept", text(ds, 1, "_NAME_"));
    try std.testing.expectEqualStrings("x", text(ds, 2, "_NAME_"));
    for (0..3) |row| {
        try std.testing.expectEqualStrings("y", text(ds, row, "_DEPVAR_"));
        try close(0.5, number(ds, row, "_RMSE_"));
    }
    // Independently: X'WX=[[4,4],[4,6]], inverse=[[3/4,-1/2],[-1/2,1/2]].
    // beta=(5/4,1/2), residuals=(-1/4,1/4,-1/4), SSE=1/4, df=3-2=1.
    try close(1.25, number(ds, 0, "Intercept"));
    try close(0.5, number(ds, 0, "x"));
    try close(-1, number(ds, 0, "y"));
    try close(3.0 / 16.0, number(ds, 1, "Intercept"));
    try close(-1.0 / 8.0, number(ds, 1, "x"));
    try close(-1.0 / 8.0, number(ds, 2, "Intercept"));
    try close(1.0 / 8.0, number(ds, 2, "x"));
    try std.testing.expect(std.math.isNan(number(ds, 1, "y")));
    try std.testing.expect(std.math.isNan(number(ds, 2, "y")));
    try std.testing.expect(!d.hasErrors());
}

test "STAT-COMMON-004 FREQ and precision weights have distinct covariance DF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try sample(a, &lib, "sample", 1, 1);
    try execute(a, &lib, &d, "proc reg data=sample outest=weighted covout noprint; model y=x; weight w; run;");
    try execute(a, &lib, &d, "proc reg data=sample outest=replicated covout noprint; model y=x; freq f; run;");
    const weighted = lib.find("weighted").?;
    const replicated = lib.find("replicated").?;
    for ([_][]const u8{ "Intercept", "x" }) |name| {
        try close(number(weighted, 0, name), number(replicated, 0, name));
        for (1..3) |row| try close(number(weighted, row, name) / 2, number(replicated, row, name));
    }
    // Same SSE/crossproducts, but FREQ N=4 gives df=2 rather than WEIGHT df=1.
    try close(@sqrt(0.125), number(replicated, 0, "_RMSE_"));
    try std.testing.expect(!d.hasErrors());
}

test "STAT-COMMON-004 covariance response scaling and common weight scaling" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try sample(a, &lib, "base", 1, 1);
    _ = try sample(a, &lib, "response", 3, 1);
    _ = try sample(a, &lib, "weights", 1, 10);
    try execute(a, &lib, &d, "proc reg data=base outest=e0 covout noprint; model y=x; weight w; run;");
    try execute(a, &lib, &d, "proc reg data=response outest=ey covout noprint; model y=x; weight w; run;");
    try execute(a, &lib, &d, "proc reg data=weights outest=ew covout noprint; model y=x; weight w; run;");
    const base = lib.find("e0").?;
    const ey = lib.find("ey").?;
    const ew = lib.find("ew").?;
    for ([_][]const u8{ "Intercept", "x" }) |name| {
        try close(3 * number(base, 0, name), number(ey, 0, name));
        try close(number(base, 0, name), number(ew, 0, name));
        for (1..3) |row| {
            try close(9 * number(base, row, name), number(ey, row, name));
            try close(number(base, row, name), number(ew, row, name));
        }
    }
    try close(3 * number(base, 0, "_RMSE_"), number(ey, 0, "_RMSE_"));
    try close(@sqrt(10.0) * number(base, 0, "_RMSE_"), number(ew, 0, "_RMSE_"));
}

test "STAT-COMMON-004 intercept only and rank deficient covariance" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try sample(a, &lib, "sample", 1, 1);
    try execute(a, &lib, &d, "proc reg data=sample outest=mean covout noprint; model y=; weight w; run;");
    const mean = lib.find("mean").?;
    // Weighted mean 7/4, SSE=3/4, df=2; Var(mean)=(3/8)/4=3/32.
    try close(1.75, number(mean, 0, "Intercept"));
    try close(3.0 / 32.0, number(mean, 1, "Intercept"));
    try close(@sqrt(3.0 / 8.0), number(mean, 0, "_RMSE_"));
    try execute(a, &lib, &d, "proc reg data=sample outest=singular covout noprint; model y=x twice; weight w; run;");
    const singular = lib.find("singular").?;
    try std.testing.expectEqual(@as(usize, 4), singular.rows.items.len);
    try close(0, number(singular, 0, "twice"));
    try close(1.25, number(singular, 0, "Intercept"));
    try close(3.0 / 16.0, number(singular, 1, "Intercept"));
    try close(1.0 / 8.0, number(singular, 2, "x"));
    try std.testing.expect(std.math.isNan(number(singular, 3, "twice")));
    try std.testing.expectEqualStrings("twice", text(singular, 3, "_NAME_"));
}

test "STAT-COMMON-004 multiple models BY metadata omitted variables and NOINT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try sample(a, &lib, "sample", 1, 1);
    // BY x has singleton groups; saturated fits export missing inference.
    try execute(a, &lib, &d, "proc reg data=sample outest=multi noprint; by x; first: model y=; second: model y=twice / noint; var w; run;");
    const output = lib.find("multi").?;
    try std.testing.expectEqual(@as(usize, 6), output.rows.items.len);
    try std.testing.expect(output.indexOf("_NAME_") == null);
    try std.testing.expectEqualStrings("x", output.columns.items[0].name);
    try close(ds.rows.items[1][0].num, number(output, 2, "x"));
    try std.testing.expectEqualStrings("first", text(output, 0, "_MODEL_"));
    try std.testing.expectEqualStrings("second", text(output, 1, "_MODEL_"));
    try std.testing.expect(std.math.isNan(number(output, 1, "Intercept")));
    try std.testing.expect(std.math.isNan(number(output, 0, "twice")));
    try std.testing.expect(std.math.isNan(number(output, 0, "w")));
    try close(-1, number(output, 0, "y"));
    try close(-1, number(output, 1, "y"));
}

test "STAT-COMMON-004 malformed OUTEST and output failure preserve existing member" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    _ = try sample(a, &lib, "sample", 1, 1);
    const prior = try sample(a, &lib, "prior", 2, 1);
    try std.testing.expectError(error.ParseError, execute(a, &lib, &d, "proc reg data=sample outest=; model y=x; run;"));
    try std.testing.expectError(error.ParseError, execute(a, &lib, &d, "proc reg data=sample outest=prior(keep=x); model y=x; run;"));
    try std.testing.expect(lib.find("prior").? == prior);
    try std.testing.expect(d.hasErrors());
}

test "STAT-COMMON-004 oracle covariance agrees with exact rational normal equations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const ds = try a.create(data.Dataset);
    ds.* = data.Dataset.init(a, "sample");
    for ([_][]const u8{ "x", "z", "y", "weight" }) |name| _ = try ds.addColumn(name, .num);
    const z = [_]f64{ 1, 1, 2, 1, 3, 2, 4, 3, 5, 3, 5, 4 };
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    const w = [_]f64{ 1, 2, 1, 1, 2, 1, 1, 2, 1, 1, 2, 1 };
    for (0..12) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .num = z[i] }, .{ .num = y[i] }, .{ .num = w[i] } });
    try lib.put("sample", ds);
    try execute(a, &lib, &d, "proc reg data=sample outest=est covout noprint; model y=x z; weight weight; run;");
    const estimates = lib.find("est").?;
    try std.testing.expectEqual(@as(usize, 4), estimates.rows.items.len);
    try std.testing.expectEqual(@as(usize, 9), estimates.columns.items.len);
    // Independent exact arithmetic: X'WX=[[16,104,46],[104,864,366],
    // [46,366,164]], beta=(431/296,2693/1480,237/370), SSE=5213/370,
    // MSE=5213/3330. No rounded SAS listing values are used as the math oracle.
    const beta = [_]f64{ 431.0 / 296.0, 2693.0 / 1480.0, 237.0 / 370.0 };
    const cov = [_][3]f64{
        .{ 224159.0 / 438080.0, -57343.0 / 3942720.0, -36491.0 / 328560.0 },
        .{ -57343.0 / 3942720.0, 662051.0 / 19713600.0, -349271.0 / 4928400.0 },
        .{ -36491.0 / 328560.0, -349271.0 / 4928400.0, 245011.0 / 1232100.0 },
    };
    for ([_][]const u8{ "Intercept", "x", "z" }, 0..) |name, j| {
        try std.testing.expectApproxEqAbs(beta[j], number(estimates, 0, name), 5e-14);
        for (0..3) |i| try std.testing.expectApproxEqAbs(cov[i][j], number(estimates, i + 1, name), 5e-15);
    }
    for (0..4) |i| try close(@sqrt(5213.0 / 3330.0), number(estimates, i, "_RMSE_"));
    // Stored estimates carry more precision than the default 5-decimal listing.
    try std.testing.expect(@abs(number(estimates, 0, "Intercept") - 1.45608) > 1e-7);
    try std.testing.expectEqual(@as(usize, 12), ds.rows.items.len);
}

test "STAT-COMMON-004 later BY fit failure does not publish partial OUTEST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const input = try a.create(data.Dataset);
    input.* = data.Dataset.init(a, "input");
    _ = try input.addColumn("g", .char);
    _ = try input.addColumn("y", .num);
    _ = try input.addColumn("w", .num);
    try input.appendRow(&.{ .{ .str = "A" }, .{ .num = 1 }, .{ .num = 1 } });
    try input.appendRow(&.{ .{ .str = "A" }, .{ .num = 3 }, .{ .num = 1 } });
    try input.appendRow(&.{ .{ .str = "B" }, .{ .num = 5 }, .{ .num = std.math.inf(f64) } });
    try lib.put("input", input);
    const prior = try sample(a, &lib, "prior", 1, 1);
    try std.testing.expectError(error.ExecError, execute(a, &lib, &d, "proc reg data=input outest=prior covout noprint; by g; model y=; weight w; run;"));
    try std.testing.expect(lib.find("prior").? == prior);
    try std.testing.expectEqual(@as(usize, 3), prior.rows.items.len);
    try std.testing.expect(d.hasErrors());
}
