//! GLM positional ESTIMATE mapping, inference and coefficient/result tables.
//! S154 physical pp.4070–4071,4127–4128. Chapter20 (p.472) explicitly
//! excludes GLM from its multirow/nonpositional/adjustment syntax contract.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const parse = @import("glm_parse.zig");
const design = @import("glm_design.zig");
const coded = @import("design_matrix.zig");
const estimability = @import("glm_estimability.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Term = struct { effect: ?usize, values: []const f64 };
pub const Request = struct { label: []const u8, terms: []const Term, line: usize = 0, e: bool = false, divisor: f64 = 1, singular: f64 = 1e-4 };
pub const Table = struct { request: Request, matrix: coded.Design, coefficients: []const f64, inference: estimability.Result };
fn sameEffect(left: []const usize, right: []const usize) bool {
    if (left.len != right.len) return false;
    for (left) |v| if (std.mem.count(usize, left, &.{v}) != std.mem.count(usize, right, &.{v})) return false;
    return true;
}
fn signedNumber(cx: proc.ProcCtx, tokens: []const lex.Token, i: *usize, line: usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (i.* < tokens.len and (tokens[i.*].tag == .minus or tokens[i.*].tag == .plus)) {
        if (tokens[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (i.* >= tokens.len or tokens[i.*].tag != .number) return cx.diags.fail(error.ParseError, line, "PROC GLM: ESTIMATE requires a finite numeric coefficient", .{});
    const value = sign * (std.fmt.parseFloat(f64, tokens[i.*].text) catch return cx.diags.fail(error.ParseError, line, "PROC GLM: invalid ESTIMATE number", .{}));
    i.* += 1;
    if (!std.math.isFinite(value)) return cx.diags.fail(error.ParseError, line, "PROC GLM: ESTIMATE requires finite numbers", .{});
    return value;
}
pub fn read(cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect) diag.Error!Request {
    return readFor("ESTIMATE", cx, tokens, spec, effects);
}
pub fn readFor(comptime statement: []const u8, cx: proc.ProcCtx, tokens: []const lex.Token, spec: parse.Spec, effects: []const parse.Effect) diag.Error!Request {
    const line = tokens[0].line;
    if (tokens.len < 2 or tokens[1].tag != .string) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " requires a quoted label", .{});
    var terms: std.ArrayList(Term) = .empty;
    var i: usize = 2;
    while (i < tokens.len and tokens[i].tag != .slash) {
        if (tokens[i].tag == .comma or tokens[i].tag == .lbrace) return proc.failGap(cx.diags, line, "PROC GLM: multirow/nonpositional " ++ statement ++ " syntax is not supported", .{});
        if (tokens[i].tag != .name) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " requires an effect name", .{});
        var index: ?usize = null;
        if (eq(tokens[i].text, "intercept")) {
            if (!spec.intercept) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " INTERCEPT is unavailable with NOINT", .{});
            i += 1;
        } else {
            var variables: std.ArrayList(usize) = .empty;
            while (true) {
                if (i >= tokens.len or tokens[i].tag != .name) return cx.diags.fail(error.ParseError, line, "PROC GLM: incomplete " ++ statement ++ " effect", .{});
                const ci = spec.input.ds.indexOf(tokens[i].text) orelse return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " variable {s} not found", .{tokens[i].text});
                try variables.append(cx.arena, ci);
                i += 1;
                if (i == tokens.len or tokens[i].tag != .star) break;
                i += 1;
            }
            for (effects, 0..) |effect, e| if (sameEffect(effect.variables, variables.items)) {
                index = e;
                break;
            };
            if (index == null) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " effect is not in MODEL", .{});
        }
        for (terms.items) |term| if (term.effect == index) return proc.failGap(cx.diags, line, "PROC GLM: repeated " ++ statement ++ " effect specifications are not implemented", .{});
        var values: std.ArrayList(f64) = .empty;
        while (i < tokens.len and (tokens[i].tag == .number or tokens[i].tag == .minus or tokens[i].tag == .plus)) try values.append(cx.arena, try signedNumber(cx, tokens, &i, line));
        if (values.items.len == 0) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " effect requires coefficients", .{});
        try terms.append(cx.arena, .{ .effect = index, .values = values.items });
    }
    if (terms.items.len == 0) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " requires an effect and coefficients", .{});
    var request: Request = .{ .label = tokens[1].text, .terms = terms.items, .line = line };
    if (i < tokens.len) i += 1;
    while (i < tokens.len) {
        const token = tokens[i];
        i += 1;
        if (token.tag != .name) return cx.diags.fail(error.ParseError, line, "PROC GLM: invalid " ++ statement ++ " option", .{});
        if (eq(token.text, "e") and !(i < tokens.len and tokens[i].tag == .eq)) {
            request.e = true;
        } else if (eq(token.text, "divisor") or eq(token.text, "singular")) {
            if (i == tokens.len or tokens[i].tag != .eq) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " option requires =number", .{});
            i += 1;
            const value = try signedNumber(cx, tokens, &i, line);
            if (eq(token.text, "divisor")) {
                if (value == 0) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " DIVISOR must be nonzero", .{});
                request.divisor = value;
            } else {
                if (value <= 0 or value >= 1) return cx.diags.fail(error.ParseError, line, "PROC GLM: " ++ statement ++ " SINGULAR must be between zero and one", .{});
                request.singular = value;
            }
        } else return proc.failGap(cx.diags, line, "PROC GLM: " ++ statement ++ " option {s} is not supported", .{token.text});
    }
    return request;
}
fn pureClass(spec: parse.Spec, e: usize) bool {
    for (spec.effects[e].variables) |ci| if (std.mem.indexOfScalar(usize, spec.classes, ci) == null) return false;
    return true;
}
fn contains(spec: parse.Spec, outer: usize, inner: usize) bool {
    const a = spec.effects[outer].variables;
    const b = spec.effects[inner].variables;
    if (!pureClass(spec, outer) or !pureClass(spec, inner) or a.len <= b.len) return false;
    for (b) |ci| if (std.mem.indexOfScalar(usize, a, ci) == null) return false;
    return true;
}
fn compatible(source: coded.Column, target: coded.Column) bool {
    for (source.class_values, target.class_values) |s, t| if (s != null and t != s) return false;
    return true;
}

/// Missing coefficient positions are zero; extra positions warn and are
/// ignored as specified on physical p.4127. Explicit zero effects suppress fill.
pub fn map(cx: proc.ProcCtx, spec: parse.Spec, matrix: coded.Design, request: Request) diag.Error![]const f64 {
    return mapFor("GLM", cx, spec, matrix, request);
}
pub fn mapFor(comptime procedure: []const u8, cx: proc.ProcCtx, spec: parse.Spec, matrix: coded.Design, request: Request) diag.Error![]const f64 {
    const a = cx.arena;
    const l = try a.alloc(f64, matrix.p);
    @memset(l, 0);
    const supplied = try a.alloc(bool, spec.effects.len + 1);
    @memset(supplied, false);
    for (request.terms) |term| {
        supplied[if (term.effect) |e| e + 1 else 0] = true;
        var count: usize = 0;
        for (matrix.columns, 0..) |column, j| if (column.effect_index == term.effect) {
            l[j] = if (count < term.values.len) term.values[count] else 0;
            count += 1;
        };
        if (term.values.len > count) try cx.diags.warn(request.line, "PROC " ++ procedure ++ ": extra ESTIMATE coefficients for {s} are ignored", .{if (term.effect) |e| spec.effects[e].name else "Intercept"});
    }
    // Fill an omitted higher-order CLASS effect from the most specific
    // explicitly supplied contained effect. Intercept spreads over CLASS
    // effects except those contained by another supplied effect (p.4128).
    for (spec.effects, 0..) |_, target| {
        if (supplied[target + 1] or !pureClass(spec, target)) continue;
        var covered = false;
        for (request.terms) |term| if (term.effect) |source| if (contains(spec, source, target)) {
            covered = true;
        };
        if (covered) continue;
        var best: ?usize = null; // index into request.terms, includes intercept
        var size: usize = 0;
        var tied = false;
        for (request.terms, 0..) |term, t| {
            const candidate_size = if (term.effect) |source| blk: {
                if (!contains(spec, target, source)) continue;
                break :blk spec.effects[source].variables.len;
            } else @as(usize, 0);
            if (best != null and candidate_size == size) tied = true;
            if (best == null or candidate_size > size) {
                best = t;
                size = candidate_size;
                tied = false;
            }
        }
        if (tied) return proc.failGap(cx.diags, request.line, "PROC " ++ procedure ++ ": tied ESTIMATE coefficient fill sources are not implemented; specify the higher-order effect", .{});
        if (best) |t| {
            const source = request.terms[t].effect;
            for (matrix.columns, 0..) |source_column, s| if (source_column.effect_index == source) {
                var count: usize = 0;
                for (matrix.columns) |target_column| if (target_column.effect_index == target and compatible(source_column, target_column)) {
                    count += 1;
                };
                if (count == 0) continue;
                for (matrix.columns, 0..) |target_column, j| if (target_column.effect_index == target and compatible(source_column, target_column)) {
                    l[j] += l[s] / @as(f64, @floatFromInt(count));
                };
            };
        }
    }
    for (l) |*value| {
        value.* /= request.divisor;
        if (!std.math.isFinite(value.*)) return cx.diags.fail(error.ExecError, request.line, "PROC " ++ procedure ++ ": ESTIMATE coefficient overflow", .{});
    }
    return l;
}
pub fn computeAll(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, mse: f64, df_error: usize) diag.Error![]const Table {
    if (spec.estimates.len == 0) return &.{};
    if (@hasField(parse.Spec, "absorb")) {
        if (spec.absorb.len > 0) return proc.failGap(cx.diags, 0, "PROC GLM: ESTIMATE with ABSORB is not implemented", .{});
    }
    const matrix = try estimability.codedDesign(cx, spec, d);
    var model = try estimability.fitCoded(cx, spec, d, matrix, mse, df_error);
    defer model.deinit(cx.arena);
    const tables = try cx.arena.alloc(Table, spec.estimates.len);
    for (spec.estimates, tables) |request, *table| {
        const coefficients = try map(cx, spec, matrix, request);
        table.* = .{ .request = request, .matrix = matrix, .coefficients = coefficients, .inference = try estimability.evaluate(model, coefficients, request.singular) };
    }
    return tables;
}
/// S154 physical pp.4124–4128: the explicit-effect estimable functions after
/// absorption are free of nuisance parameters. For a full-rank continuous
/// design the projected coefficients have the same parameter order as MODEL,
/// and the absorbed fit already carries the full model's MSE and error DF.
/// CLASS uses its full projected indicator basis so L=LH detects nonestimable
/// means rather than reporting arbitrary generalized-inverse coefficients.
/// Intercept coefficients and E displays require additional mappings.
pub fn computeAbsorbed(cx: proc.ProcCtx, spec: parse.Spec, d: design.Design, absorbed: @import("glm_absorb.zig").Result) diag.Error![]const Table {
    if (spec.estimates.len == 0) return &.{};
    const conditional = absorbed.conditional orelse return proc.failGap(cx.diags, 0, "PROC GLM: ABSORB ESTIMATE requires explicit continuous effects", .{});
    if (conditional.model.fit.rank != d.p - 1) return proc.failGap(cx.diags, 0, "PROC GLM: rank-deficient ABSORB ESTIMATE is not implemented", .{});
    for (spec.estimates) |request| {
        if (request.e) return proc.failGap(cx.diags, request.line, "PROC GLM: ESTIMATE E display with ABSORB is not implemented", .{});
        for (request.terms) |term| if (term.effect == null) return proc.failGap(cx.diags, request.line, "PROC GLM: INTERCEPT ESTIMATE with ABSORB is not implemented", .{});
    }
    var conditional_spec = spec;
    conditional_spec.intercept = false;
    var matrix = try estimability.codedDesign(cx, conditional_spec, d);
    var full_basis: ?@import("reg_diagnostics.zig").Result = null;
    defer if (full_basis) |*model| model.deinit(cx.arena);
    if (spec.classes.len == 0) {
        // Preserve the already-tested continuous coefficient basis.
        matrix.x = try cx.arena.dupe(f64, absorbed.within_x);
        if (matrix.p != conditional.model.fit.coefficients.len) return error.ExecError;
    } else {
        matrix.x = try @import("glm_absorb.zig").projectColumns(cx, spec, d, absorbed.weights, matrix.x, matrix.p);
        full_basis = try @import("reg_diagnostics.zig").fit(cx.arena, matrix.x, absorbed.within_y, matrix.n, matrix.p, absorbed.weights, false, spec.singular);
        if (full_basis.?.fit.rank != conditional.model.fit.rank) return cx.diags.fail(error.ExecError, 0, "PROC GLM: absorbed ESTIMATE parameterizations disagree in rank", .{});
        full_basis.?.fit.mse = absorbed.mse;
        full_basis.?.fit.df_error = absorbed.df_error;
        full_basis.?.fit.n_used = absorbed.n_used;
    }
    const fitted = full_basis orelse conditional.model;
    const tables = try cx.arena.alloc(Table, spec.estimates.len);
    for (spec.estimates, tables) |request, *table| {
        const coefficients = try map(cx, conditional_spec, matrix, request);
        table.* = .{ .request = request, .matrix = matrix, .coefficients = coefficients, .inference = try estimability.evaluate(fitted, coefficients, request.singular) };
    }
    return tables;
}

fn number(a: std.mem.Allocator, v: ?f64, decimals: usize) ![]const u8 {
    const value = v orelse return ".";
    return std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals})), " ");
}
pub fn renderCoefficients(cx: proc.ProcCtx, out: *std.ArrayList(u8), tables: []const Table) !void {
    for (tables) |table| if (table.request.e) {
        if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out) else if (cx.graph_title) |title| try out.print(cx.arena, "\n{s}\n", .{title});
        try out.print(cx.arena, "\nThe GLM Procedure\n\nCoefficients for Estimate {s}\n\nRow 1\n\n", .{table.request.label});
        for (table.matrix.columns, table.coefficients) |column, coefficient| {
            try out.print(cx.arena, "{s}", .{column.effect_name});
            for (column.class_values, table.matrix.classes) |level, class| if (level) |k| try out.print(cx.arena, " {s}", .{class.map.levels[k].label});
            try out.print(cx.arena, " {d}\n", .{coefficient});
        }
    };
}
pub fn renderResults(cx: proc.ProcCtx, out: *std.ArrayList(u8), tables: []const Table) !void {
    if (tables.len == 0) return;
    try out.appendSlice(cx.arena, "\nStandard\nParameter Estimate Error t Value Pr > |t|\n\n");
    for (tables) |table| {
        const r = table.inference;
        try out.print(cx.arena, "{s} {s} {s} {s} {s}\n", .{ table.request.label, if (r.status == .nonestimable) "Non-est" else try number(cx.arena, r.estimate, 8), try number(cx.arena, r.standard_error, 8), try number(cx.arena, r.t_value, 2), if (r.p_value != null and r.p_value.? < 0.0001) "<.0001" else try number(cx.arena, r.p_value, 4) });
    }
}

const testing = std.testing;
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;
const selection = @import("data_selection.zig");
const glm = @import("glm.zig");
fn sample(a: std.mem.Allocator, lib: *Library) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("group", .char);
    for ([_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 }, 0..) |y, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .num = y }, .{ .str = if (i < 6) "A" else "B" } });
    try lib.put("sample", ds);
    return ds;
}
const Analysis = struct { spec: parse.Spec, d: design.Design, result: glm.math.Result, tables: []const Table };
fn analyze(cx: proc.ProcCtx, source: []const u8) !Analysis {
    const spec = try parse.parse(cx, try lex.tokenize(cx.arena, source, cx.diags));
    const view = try selection.View.init(cx.arena, spec.input, .{ .frequency = spec.freq, .weight = spec.weight });
    const d = try design.build(cx, spec, view, spec.responses[0]);
    const result = try glm.fitDesign(cx, spec, d);
    return .{ .spec = spec, .d = d, .result = result, .tables = try computeAll(cx, spec, d, result.model.fit.mse, result.model.fit.df_error) };
}

test "COMMON025 original adjusted group contrast and E coefficient order" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyze(cx, "proc glm; class group; model y=group x; estimate 'B minus A' group -1 1 / e; run;");
    const table = r.tables[0];
    try testing.expectEqual(@as(usize, 1), r.tables.len);
    try testing.expectEqualSlices(f64, &.{ 0, -1, 1, 0 }, table.coefficients);
    for (table.matrix.columns, [_][]const u8{ "Intercept", "group", "group", "x" }) |column, name| try testing.expectEqualStrings(name, column.effect_name);
    // Independent ANCOVA: within-group Sxx=35, Sxy=119/2 -> slope17/10.
    // Raw group gap77/6 and x-gap6 -> adjusted gap79/30. Var factor:
    // 1/6+1/6+6²/35=143/105. SSE581/60, residual DF=12-3=9.
    try testing.expectEqual(@as(usize, 9), r.result.model.fit.df_error);
    const value = table.inference;
    try testing.expectEqual(estimability.Status.estimable, value.status);
    try testing.expectApproxEqAbs(@as(f64, 79.0 / 30.0), value.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 143.0 / 105.0), value.variance_factor.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 581.0 / 540.0), r.result.model.fit.mse, 1e-12);
    try testing.expectApproxEqAbs(@sqrt(83083.0 / 56700.0), value.standard_error.?, 1e-12);
    try testing.expectApproxEqAbs((79.0 / 30.0) / @sqrt(83083.0 / 56700.0), value.t_value.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 0.0576), value.p_value.?, 0.00005);
    // Independent odd-DF Student tail, ported from the original verifier:
    // integrate cos(theta)^8 by its elementary reduction formula (DF=9).
    const theta = std.math.atan(@abs(value.t_value.?) / 3);
    var integral = theta;
    var total: f64 = @as(f64, std.math.pi) / 2;
    for ([_]f64{ 2, 4, 6, 8 }) |power| {
        integral = @sin(theta) * std.math.pow(f64, @cos(theta), power - 1) / power + (power - 1) * integral / power;
        total *= (power - 1) / power;
    }
    try testing.expectApproxEqAbs(1 - integral / total, value.p_value.?, 1e-12);
    var output: std.ArrayList(u8) = .empty;
    try glm.execute(cx, &output, r.spec);
    const coeff_at = std.mem.indexOf(u8, output.items, "Coefficients for Estimate B minus A").?;
    const response_at = std.mem.indexOf(u8, output.items, "Dependent Variable: y").?;
    try testing.expect(coeff_at < response_at);
    try testing.expect(std.mem.indexOf(u8, output.items, "B minus A 2.63333333 1.21049934 2.18 0.0576") != null);
    try testing.expect(!diagnostics.hasErrors());
}

test "COMMON025 divisor scale sign and CLASS order preserve the named contrast" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    const ds = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyze(cx, "proc glm; class group; model y=group x; estimate 'base' group -1 1; estimate 'scaled' group 3 -3; estimate 'divided' group -3 3 / divisor=3; estimate 'neg divisor' group 3 -3 / divisor=-3; run;");
    const base = r.tables[0].inference;
    const scaled = r.tables[1].inference;
    try testing.expectApproxEqAbs(-3 * base.estimate.?, scaled.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(3 * base.standard_error.?, scaled.standard_error.?, 1e-12);
    try testing.expectApproxEqAbs(-base.t_value.?, scaled.t_value.?, 1e-12);
    try testing.expectApproxEqAbs(base.p_value.?, scaled.p_value.?, 1e-12);
    for (r.tables[2..]) |table| {
        try testing.expectEqualSlices(f64, r.tables[0].coefficients, table.coefficients);
        try testing.expectApproxEqAbs(base.estimate.?, table.inference.estimate.?, 1e-12);
    }
    std.mem.reverse([]const @import("../value.zig").Value, ds.rows.items);
    const reordered = try analyze(cx, "proc glm order=data; class group; model y=x group; estimate 'B minus A' group 1 -1 / e; run;");
    try testing.expectEqualStrings("B", reordered.tables[0].matrix.classes[0].map.levels[0].label);
    try testing.expectEqualSlices(f64, &.{ 0, 0, 1, -1 }, reordered.tables[0].coefficients);
    try testing.expectApproxEqAbs(base.estimate.?, reordered.tables[0].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(base.standard_error.?, reordered.tables[0].inference.standard_error.?, 1e-12);
}

test "COMMON025 omitted coefficients nonestimability and excess coefficient warning" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyze(cx, "proc glm; class group; model y=group x; estimate 'not estimable' group 1; estimate 'A at zero' intercept 1 group 1; estimate 'extra' group -1 1 999 / e; estimate 'zero' group 0 0; run;");
    const bad = r.tables[0].inference;
    try testing.expectEqualSlices(f64, &.{ 0, 1, 0, 0 }, r.tables[0].coefficients);
    try testing.expectEqual(estimability.Status.nonestimable, bad.status);
    inline for (.{ "estimate", "variance_factor", "standard_error", "t_value", "p_value" }) |field| try testing.expect(@field(bad, field) == null);
    try testing.expectEqual(estimability.Status.estimable, r.tables[1].inference.status);
    try testing.expectApproxEqAbs(@as(f64, 8.5 - 1.7 * 3.5), r.tables[1].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 79.0 / 30.0), r.tables[2].inference.estimate.?, 1e-12);
    try testing.expectEqual(@as(usize, 1), diagnostics.list.items.len);
    try testing.expectEqual(diag.Severity.warning, diagnostics.list.items[0].severity);
    try testing.expect(std.mem.indexOf(u8, diagnostics.list.items[0].message, "extra ESTIMATE coefficients") != null);
    try testing.expectEqual(@as(?f64, 0), r.tables[3].inference.estimate);
    var output: std.ArrayList(u8) = .empty;
    try renderResults(cx, &output, r.tables);
    try testing.expect(std.mem.indexOf(u8, output.items, "not estimable Non-est . . .\n") != null);
}

test "COMMON025 higher-effect fill and explicit zero suppressing fill" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "cells");
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("h", .num);
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 2, 6, 10, 20 }, 0..) |mean, i| for ([_]f64{ -1, 1 }) |delta| try ds.appendRow(&.{ .{ .str = if (i < 2) "A" else "B" }, .{ .num = @floatFromInt(i % 2) }, .{ .num = mean + delta } });
    try lib.put("cells", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyze(cx, "proc glm; class group h; model y=group|h; estimate 'B minus A' group -1 1 / e; estimate 'A margin' intercept 1 group 1 / e; estimate 'no fill' group -1 1 group*h 0 0 0 0; estimate 'slice h at B' h -1 1 group*h 0 0 -1 1; run;");
    try testing.expectEqualSlices(f64, &.{ 0, -1, 1, 0, 0, -0.5, -0.5, 0.5, 0.5 }, r.tables[0].coefficients);
    try testing.expectApproxEqAbs(@as(f64, 11), r.tables[0].inference.estimate.?, 1e-12);
    try testing.expectApproxEqAbs(@as(f64, 4), r.tables[1].inference.estimate.?, 1e-12);
    try testing.expectEqual(estimability.Status.nonestimable, r.tables[2].inference.status);
    try testing.expectApproxEqAbs(@as(f64, 10), r.tables[3].inference.estimate.?, 1e-12);
}

test "COMMON025 invalid coefficients and GLM-inapplicable shared options are captured" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    for ([_][]const u8{
        "estimate 'bad' group -1 1; model y=group x;",
        "model y=group x; estimate group -1 1;",
        "model y=group x; estimate 'bad' missing_variable 1;",
        "model y=group; estimate 'bad' x 1;",
        "model y=group x; estimate 'bad' group;",
        "model y=group x; estimate 'bad' group .;",
        "model y=group x; estimate 'bad' group -;",
        "model y=group x; estimate 'bad' group 1e999;",
        "model y=group x; estimate 'bad' group -1 1 / divisor=0;",
        "model y=group x; estimate 'bad' group -1 1 / singular=1;",
        "model y=group x; estimate 'bad' group -1 1 / adjust=bon;",
        "model y=group x; estimate 'bad' group -1 1 / exp;",
        "model y=group x; estimate 'bad' group -1 1 / joint;",
        "model y=group x; estimate 'bad' group [1,1];",
        "model y=group x; estimate 'bad' group -1 1, group 1 -1;",
        "model y=x / noint; estimate 'bad' intercept 1;",
    }) |body| {
        const source = try std.fmt.allocPrint(a, "proc glm; class group; {s} run;", .{body});
        const before = diagnostics.list.items.len;
        try testing.expectError(error.ParseError, parse.parse(cx, try lex.tokenize(a, source, &diagnostics)));
        try testing.expect(diagnostics.list.items.len > before);
        try testing.expect(diagnostics.list.items[diagnostics.list.items.len - 1].line > 0);
    }
}

test "COMMON025 absorbed INTERCEPT estimate fails instead of silently using the wrong basis" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    _ = try sample(a, &lib);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    // Explicit-effect contrasts now use the nuisance-projected basis. An
    // absorbed intercept still has no supported parameter mapping and must
    // fail at execution, not fabricate an arbitrary group/generalized mean.
    const tokens = try lex.tokenize(a, "proc glm; absorb group; model y=x; estimate 'intercept' intercept 1; run;", &diagnostics);
    diag.resetGap();
    defer diag.resetGap();
    var output: std.ArrayList(u8) = .empty;
    try testing.expectError(error.ParseError, glm.run(cx, &output, tokens));
    try testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try testing.expectEqual(@as(usize, 0), output.items.len);
    try testing.expect(std.mem.indexOf(u8, try diagnostics.render(), "INTERCEPT ESTIMATE with ABSORB is not implemented") != null);
}

test "COMMON025 saturated estimate retains its value with missing inference" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = Library.init(a);
    var ds = Dataset.init(a, "two");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .num = 0 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 3 } });
    try lib.put("two", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const r = try analyze(cx, "proc glm; model y=x; estimate 'slope' x 1; run;");
    try testing.expectEqual(@as(usize, 0), r.result.model.fit.df_error);
    try testing.expectEqual(estimability.Status.estimable, r.tables[0].inference.status);
    try testing.expectApproxEqAbs(@as(f64, 2), r.tables[0].inference.estimate.?, 1e-12);
    try testing.expect(r.tables[0].inference.standard_error == null and r.tables[0].inference.t_value == null and r.tables[0].inference.p_value == null);
}
