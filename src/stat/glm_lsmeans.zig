//! Balanced population margins, full GLM coefficients, and explicit Non-est.
//! S154 physical pp.4072–4076,4081,4144–4147; COMMON009 original SAS listing.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const coded = @import("design_matrix.zig");
const estimability = @import("glm_estimability.zig");
const A = std.mem.Allocator;
pub const Request = struct { effect: usize, e: bool = false, stderr: bool = false, singular: f64 = 1e-4 };
pub const Mean = struct { levels: []const ?usize, coefficients: []const f64, inference: estimability.Result };
pub const Table = struct { effect: []const u8, classes: []const coded.Class, columns: []const coded.Column, means: []const Mean };

/// Parses only the LSMEANS statement, after MODEL has resolved its effects.
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect, requests: *std.ArrayList(Request)) diag.Error!void {
    const first = requests.items.len;
    var i: usize = 1;
    while (i < tokens.len and tokens[i].tag != .slash) {
        var variables: std.ArrayList(usize) = .empty;
        while (true) {
            if (i >= tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: LSMEANS requires a classification effect", .{});
            const ci = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: LSMEANS variable not found", .{});
            if (std.mem.indexOfScalar(usize, spec.classes, ci) == null) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: LSMEANS requires CLASS variables", .{});
            if (std.mem.indexOfScalar(usize, variables.items, ci) != null) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: repeated LSMEANS factor", .{});
            try variables.append(cx.arena, ci);
            i += 1;
            if (i == tokens.len or tokens[i].tag != .star) break;
            i += 1;
        }
        var found: ?usize = null;
        for (effects, 0..) |effect, e| {
            if (effect.variables.len != variables.items.len) continue;
            var matches = true;
            for (variables.items) |ci| if (std.mem.indexOfScalar(usize, effect.variables, ci) == null) {
                matches = false;
            };
            if (matches) {
                found = e;
                break;
            }
        }
        try requests.append(cx.arena, .{ .effect = found orelse return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: LSMEANS effect is not in MODEL", .{}) });
    }
    if (requests.items.len == first) return cx.diags.fail(error.ParseError, tokens[0].line, "PROC GLM: LSMEANS requires effects", .{});
    var options: Request = .{ .effect = 0 };
    if (i < tokens.len) i += 1;
    while (i < tokens.len) {
        const token = tokens[i];
        if (token.tag != .name) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid LSMEANS option", .{});
        if (std.ascii.eqlIgnoreCase(token.text, "e") and !(i + 1 < tokens.len and tokens[i + 1].tag == .eq)) {
            options.e = true;
            i += 1;
        } else if (std.ascii.eqlIgnoreCase(token.text, "stderr")) {
            options.stderr = true;
            i += 1;
        } else if (std.ascii.eqlIgnoreCase(token.text, "singular")) {
            if (i + 2 >= tokens.len or tokens[i + 1].tag != .eq or tokens[i + 2].tag != .number) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS SINGULAR requires a number", .{});
            options.singular = std.fmt.parseFloat(f64, tokens[i + 2].text) catch return cx.diags.fail(error.ParseError, token.line, "PROC GLM: invalid LSMEANS SINGULAR value", .{});
            if (!std.math.isFinite(options.singular) or options.singular <= 0 or options.singular >= 1) return cx.diags.fail(error.ParseError, token.line, "PROC GLM: LSMEANS SINGULAR must be between zero and one", .{});
            i += 3;
        } else return proc.failGap(cx.diags, token.line, "PROC GLM: LSMEANS option {s} is not implemented", .{token.text});
    }
    for (requests.items[first..]) |*request| {
        request.e = options.e;
        request.stderr = options.stderr;
        request.singular = options.singular;
    }
}

fn compatible(target: []const ?usize, column: []const ?usize) bool {
    for (target, column) |t, c| if (t != null and c != null and t.? != c.?) return false;
    return true;
}

/// Arena-owned table. Reuse full GLM coding for E labels and observed cells;
/// refit its equivalent column space with the existing rank/QR primitive.
pub fn compute(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, request: Request, mse: f64, df_error: usize) diag.Error!Table {
    const a = cx.arena;
    const matrix = try estimability.codedDesign(cx, spec, d);
    var model = try estimability.fitCoded(cx, spec, d, matrix, mse, df_error);
    defer model.deinit(a);
    var means: std.ArrayList(Mean) = .empty;
    var name: []const u8 = spec.effects[request.effect].name;
    for (matrix.columns) |target| {
        if (target.effect_index == null or target.effect_index.? != request.effect) continue;
        name = target.effect_name;
        const l = try a.alloc(f64, matrix.p);
        for (matrix.columns, 0..) |column, j| {
            if (column.effect_index == null) {
                l[j] = 1;
                continue;
            }
            const effect = spec.effects[column.effect_index.?];
            var has_class = false;
            var has_continuous = false;
            for (effect.variables) |ci| {
                if (std.mem.indexOfScalar(usize, spec.classes, ci) != null) has_class = true else has_continuous = true;
            }
            if (has_class and has_continuous) return proc.failGap(cx.diags, 0, "PROC GLM: LSMEANS mixed covariate interactions are not implemented", .{});
            if (!has_class) {
                // Standard LS-means use the mean of each covariate product,
                // without precision weights (S154 physical pp.4145–4146).
                var sum: f64 = 0;
                var count: f64 = 0;
                for (0..matrix.n) |r| {
                    sum += matrix.x[r * matrix.p + j] * d.frequencies[r];
                    count += d.frequencies[r];
                }
                l[j] = sum / count;
            } else if (!compatible(target.class_values, column.class_values)) {
                l[j] = 0;
            } else {
                var count: usize = 0;
                for (matrix.columns) |other| if (other.effect_index == column.effect_index and compatible(target.class_values, other.class_values)) {
                    count += 1;
                };
                l[j] = 1 / @as(f64, @floatFromInt(count));
            }
        }
        try means.append(a, .{ .levels = target.class_values, .coefficients = l, .inference = try estimability.evaluate(model, l, request.singular) });
    }
    return .{ .effect = name, .classes = matrix.classes, .columns = matrix.columns, .means = means.items };
}

fn number(a: A, v: ?f64, decimals: usize) ![]const u8 {
    const value = v orelse return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
pub fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, request: Request, table: Table) !void {
    const a = cx.arena;
    if (cx.listing_titles) |titles| try titles.emitTitles(a, out) else if (cx.graph_title) |title| try out.print(a, "\n{s}\n", .{title});
    try out.appendSlice(a, "\nThe GLM Procedure\nLeast Squares Means\n");
    if (request.e) {
        try out.print(a, "\nCoefficients for {s} Least Square Means\n\n{s} Level\n", .{ table.effect, table.effect });
        for (table.classes, 0..) |class, c| {
            if (table.means.len == 0 or table.means[0].levels[c] == null) continue;
            var last = true;
            for (table.means[0].levels[c + 1 ..]) |level| if (level != null) {
                last = false;
            };
            if (last) try out.appendSlice(a, "Effect ");
            for (table.means) |mean| try out.print(a, "{s} ", .{class.map.levels[mean.levels[c].?].label});
            try out.append(a, '\n');
        }
        // Match SAS's Effect heading on the final level row.
        // The compact renderer preserves token and row order for corpus comparisons.
        try out.append(a, '\n');
        for (table.columns, 0..) |column, j| {
            try out.print(a, "{s}", .{column.effect_name});
            for (column.class_values, table.classes) |level, class| if (level) |v| try out.print(a, " {s}", .{class.map.levels[v].label});
            for (table.means) |mean| try out.print(a, " {s}", .{try std.fmt.allocPrint(a, "{d}", .{mean.coefficients[j]})});
            try out.append(a, '\n');
        }
    }
    try out.append(a, '\n');
    for (table.classes, 0..) |class, c| if (table.means.len > 0 and table.means[0].levels[c] != null) try out.print(a, "{s} ", .{spec.input.ds.columns.items[class.column].name});
    try out.print(a, "{s} LSMEAN", .{spec.input.ds.columns.items[d.response].name});
    if (request.stderr) try out.appendSlice(a, " Standard Error Pr > |t|");
    try out.appendSlice(a, "\n\n");
    for (table.means) |mean| {
        for (mean.levels, table.classes) |level, class| if (level) |v| try out.print(a, "{s} ", .{class.map.levels[v].label});
        const r = mean.inference;
        try out.print(a, "{s}", .{if (r.status == .nonestimable) "Non-est" else try number(a, r.estimate, 7)});
        if (request.stderr) try out.print(a, " {s} {s}", .{ try number(a, r.standard_error, 7), if (r.p_value != null and r.p_value.? < 0.0001) "<.0001" else try number(a, r.p_value, 4) });
        try out.append(a, '\n');
    }
}

pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: parse.Spec, d: design.Design, mse: f64, df_error: usize) diag.Error!void {
    for (spec.lsmeans) |request| {
        const table = compute(cx, spec, d, request, mse, df_error) catch |err| {
            if (err != error.ExecError) return err;
            return cx.diags.fail(error.ExecError, 0, "PROC GLM: LSMEANS computation failed", .{});
        };
        if (!spec.noprint) try render(cx, out, spec, d, request, table);
    }
}

const testing = std.testing;
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
fn sample(a: A, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "cells");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("h", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 6, 9, 12, 4, 7, 13, 19, 23, 24 }, 0..) |y, i| try ds.appendRow(&.{ .{ .str = if (i < 6) "A" else "B" }, .{ .num = if (i >= 3 and i < 6) 1 else 0 }, .{ .num = y } });
    try lib.put("cells", ds);
    return ds;
}
fn analyzed(cx: proc.ProcCtx, source: []const u8) !struct { spec: parse.Spec, d: design.Design } {
    const s = try parse.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const view = try selection.View.init(cx.arena, s.input, .{ .frequency = s.freq, .weight = s.weight });
    return .{ .spec = s, .d = try design.build(cx, s, view, s.responses[0]) };
}

test "COMMON009 original empty-cell coefficients and nonestimable marginal fields" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group h; model y=group|h; lsmeans group*h / e; lsmeans group h / e stderr singular=1e-6; run;");
    try testing.expectEqual(@as(usize, 3), r.spec.lsmeans.len);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 74.0 / 6.0, 6);
    try testing.expectEqual(@as(usize, 3), table.means.len);
    try testing.expectEqual(@as(usize, 8), table.columns.len);
    const expected = [_][8]f64{ .{ 1, 1, 0, 1, 0, 1, 0, 0 }, .{ 1, 1, 0, 0, 1, 0, 1, 0 }, .{ 1, 0, 1, 1, 0, 0, 0, 1 } };
    for (table.means, expected, [_]f64{ 9, 8, 22 }) |mean, l, value| {
        try testing.expectEqualSlices(f64, &l, mean.coefficients);
        try testing.expectEqual(estimability.Status.estimable, mean.inference.status);
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-12);
        try testing.expectApproxEqAbs(@as(f64, 1.0 / 3.0), mean.inference.variance_factor.?, 1e-12);
    }
    try testing.expectEqualStrings("group*h", table.columns[5].effect_name);
    for ([_][2]?usize{ .{ 0, 0 }, .{ 0, 1 }, .{ 1, 0 } }, table.columns[5..]) |levels, column| try testing.expectEqualSlices(?usize, &levels, column.class_values);
    const marginal = try compute(cx, r.spec, r.d, r.spec.lsmeans[1], 74.0 / 6.0, 6);
    try testing.expectApproxEqAbs(@as(f64, 8.5), marginal.means[0].inference.estimate.?, 1e-12);
    const bad = marginal.means[1].inference;
    try testing.expectEqual(estimability.Status.nonestimable, bad.status);
    inline for (.{ "estimate", "variance_factor", "standard_error", "t_value", "p_value" }) |field| try testing.expect(@field(bad, field) == null);
    var output: std.ArrayList(u8) = .empty;
    try render(cx, &output, r.spec, r.d, r.spec.lsmeans[1], marginal);
    try testing.expect(std.mem.indexOf(u8, output.items, "B Non-est . .\n") != null);
    try testing.expect(!diagnostics.hasErrors());
}

test "COMMON009 missing response and blank CLASS do not create levels or cells" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    try ds.appendRow(&.{ .{ .str = "C" }, .{ .num = 2 }, @import("../value.zig").Value.missing });
    try ds.appendRow(&.{ .{ .str = " " }, .{ .num = 2 }, .{ .num = 999 } });
    try ds.appendRow(&.{ .{ .str = "C" }, @import("../value.zig").Value.missing, .{ .num = 999 } });
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm order=data; class group h; model y=group h group*h / ss1; lsmeans h*group / e; run;");
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 74.0 / 6.0, 6);
    try testing.expectEqual(@as(usize, 9), r.d.n);
    try testing.expectEqual(@as(usize, 3), table.means.len);
    try testing.expectEqual(@as(usize, 2), table.classes[0].map.levels.len);
    try testing.expectEqual(@as(usize, 2), table.classes[1].map.levels.len);
    try testing.expectEqualStrings("group*h", table.effect);
}

test "COMMON009 LSMEANS parsing rejects invalid effects and unsupported options loudly" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{
        "proc glm; class group h; lsmeans group; model y=group; run;",
        "proc glm; class group h; model y=group; lsmeans h; run;",
        "proc glm; class group h; model y=group; lsmeans; run;",
        "proc glm; class group h; model y=group; lsmeans group*; run;",
        "proc glm; class group h; model y=group; lsmeans group / singular=0; run;",
        "proc glm; class group h; model y=group; lsmeans group / pdiff; run;",
        "proc glm; class group h; model y=group; lsmeans group / e=group; run;",
    }) |source| {
        try testing.expectError(error.ParseError, parse.parse(cx, try lex.tokenize(a, source, &diagnostics)));
        try testing.expect(diagnostics.list.items[diagnostics.list.items.len - 1].line > 0);
    }
}

test "COMMON009 unequal counts use balanced margins and FREQ WEIGHT inference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "weighted");
    _ = try ds.addColumn("group", .char);
    for ([_][]const u8{ "h", "y", "f", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][5]f64{ .{ 0, 0, 1, 2, 1 }, .{ 0, 0, 3, 1, 2 }, .{ 0, 1, 5, 1, 1 }, .{ 0, 1, 7, 1, 1 }, .{ 1, 0, 9, 1, 1 }, .{ 1, 0, 11, 1, 1 }, .{ 1, 1, 13, 1, 1 }, .{ 1, 1, 15, 1, 1 } }) |r| try ds.appendRow(&.{ .{ .str = if (r[0] == 0) "A" else "B" }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, .{ .num = r[4] } });
    try lib.put("weighted", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group h; model y=group h group*h; freq f; weight w; lsmeans group / e stderr; run;");
    var fit = try @import("glm.zig").fitDesign(cx, r.spec, r.d);
    defer fit.deinit(a);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    // A0 precision total 4, weighted mean 2; A1 total 2, mean 6.
    // Balanced margin is (2+6)/2=4 regardless of physical/frequency imbalance.
    try testing.expectEqual(@as(usize, 5), fit.model.fit.df_error);
    try testing.expectApproxEqAbs(@as(f64, 4), table.means[0].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 3.0 / 16.0), table.means[0].inference.variance_factor.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 12), table.means[1].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.25), table.means[1].inference.variance_factor.?, 1e-12);
    try testing.expectApproxEqAbs(@sqrt(2.0 * 3.0 / 16.0), table.means[0].inference.standard_error.?, 1e-12);
}

test "COMMON009 class data ordering changes coefficients and row labels together" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    std.mem.reverse([]const @import("../value.zig").Value, ds.rows.items);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm order=data; class group h; model y=group h group*h / ss1; lsmeans group*h / e; run;");
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], 74.0 / 6.0, 6);
    try testing.expectEqualStrings("B", table.classes[0].map.levels[0].label);
    for (table.means, [_]f64{ 22, 9, 8 }, [_][2]?usize{ .{ 0, 0 }, .{ 1, 0 }, .{ 1, 1 } }) |mean, value, levels| {
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-12);
        try testing.expectEqualSlices(?usize, &levels, mean.levels);
    }
}

test "COMMON009 adjusted covariate means differ from raw group means" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "adjusted");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    const noise = [_]f64{ -1, 2, -1 };
    for (0..6) |i| {
        const x: f64 = @floatFromInt(i % 3 + (if (i < 3) @as(usize, 0) else 2));
        const intercept: f64 = if (i < 3) 10 else 20;
        try ds.appendRow(&.{ .{ .str = if (i < 3) "A" else "B" }, .{ .num = x }, .{ .num = intercept + 2 * x + noise[i % 3] } });
    }
    try lib.put("adjusted", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyzed(cx, "proc glm; class group; model y=group x; lsmeans group / e; run;");
    var fit = try @import("glm.zig").fitDesign(cx, r.spec, r.d);
    defer fit.deinit(a);
    const table = try compute(cx, r.spec, r.d, r.spec.lsmeans[0], fit.model.fit.mse, fit.model.fit.df_error);
    // Noise is centered and orthogonal to x within each group. The common
    // slope is 2; at global x=2 margins are14,24, not raw means12,26.
    for (table.means, [_]f64{ 14, 24 }) |mean, value| {
        try testing.expectApproxEqAbs(value, mean.inference.estimate.?, 1e-12);
        try testing.expectEqual(@as(f64, 2), mean.coefficients[3]);
    }
    try testing.expectApproxEqAbs(@as(f64, 4), fit.model.fit.mse, 1e-12);
}

test "COMMON009 MODEL bar is token-level ordered subset expansion" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const left = try analyzed(cx, "proc glm; class group h; model y=group|h; lsmeans group*h / e; run;");
    const right = try analyzed(cx, "proc glm; class group h; model y=group h group*h; lsmeans group*h / e; run;");
    try testing.expectEqualSlices(f64, right.d.x, left.d.x);
    for (left.spec.effects, right.spec.effects) |l, r| {
        try testing.expectEqualStrings(r.name, l.name);
        try testing.expectEqualSlices(usize, r.variables, l.variables);
    }
    var lo: std.ArrayList(u8) = .empty;
    var ro: std.ArrayList(u8) = .empty;
    try @import("glm.zig").execute(cx, &lo, left.spec);
    try @import("glm.zig").execute(cx, &ro, right.spec);
    try testing.expectEqualStrings(ro.items, lo.items);
    // Three generic variable operands exercise left-to-right order and @degree
    // without depending on a particular pair of CLASS names or source spacing.
    const expanded = try parse.parse(cx, try lex.tokenize(a, "proc glm; class group h; model y = group | h | y @2; run;", &diagnostics));
    for (expanded.effects, [_][]const u8{ "group", "h", "group*h", "y", "group*y", "h*y" }) |effect, name| try testing.expectEqualStrings(name, effect.name);
    const repeated = try parse.parse(cx, try lex.tokenize(a, "proc glm; class group h; model y=group|h|group; run;", &diagnostics));
    try testing.expectEqual(@as(usize, 3), repeated.effects.len);
    const main_only = try parse.parse(cx, try lex.tokenize(a, "proc glm; class group h; model y=group|h@1; run;", &diagnostics));
    try testing.expectEqual(@as(usize, 2), main_only.effects.len);
    for ([_][]const u8{
        "proc glm; class group h; model y=group|; run;",
        "proc glm; class group h; model y=group||h; run;",
        "proc glm; class group h; model y=group|h@0; run;",
        "proc glm; class group h; model y=group|h@1.5; run;",
        "proc glm; class group h; model y=group|missing_variable; run;",
        "proc glm; class group h; model y=group*h|h; run;",
    }) |source| {
        try testing.expectError(error.ParseError, parse.parse(cx, try lex.tokenize(a, source, &diagnostics)));
        try testing.expect(diagnostics.list.items[diagnostics.list.items.len - 1].line > 0);
    }
}
