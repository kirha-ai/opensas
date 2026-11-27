//! MIXED positional CONTRAST/ESTIMATE, S154 physical pp.6640-6645.
//! Fixed coefficient fill reuses the verified full-coded GLM mapping contract;
//! random coefficients have their own explicit positional domain.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const model = @import("mixed_model.zig");
const fixed = @import("mixed_design.zig");
const random = @import("mixed_random.zig");
const coded = @import("design_matrix.zig");
const glm_parse = @import("glm_parse.zig");
const mapping = @import("glm_estimate.zig");
pub const kernel = @import("mixed_contrasts_kernel.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const RandomTerm = struct { name: []const u8, values: []const f64 };
pub const Row = struct { fixed_terms: []const mapping.Term, random_terms: []const RandomTerm, last_fixed: ?usize };
pub const Request = struct { label: []const u8, rows: []const Row, is_estimate: bool, line: usize, df: ?f64 = null, alpha: f64 = 0.05, cl: bool = false, divisor: f64 = 1, singular: f64 = 1e-4, tail: kernel.Tail = .two };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, line: usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return cx.diags.fail(error.ParseError, line, "PROC MIXED: expected a finite numeric contrast coefficient", .{});
    const value = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return cx.diags.fail(error.ParseError, line, "PROC MIXED: invalid contrast coefficient", .{}));
    i.* += 1;
    if (!std.math.isFinite(value)) return cx.diags.fail(error.ParseError, line, "PROC MIXED: coefficients must be finite", .{});
    return value;
}
fn bad(cx: proc.ProcCtx, line: usize, comptime message: []const u8) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC MIXED: " ++ message, .{});
}
fn one(cx: proc.ProcCtx, m: model.Spec, z: random.Design, t: []const lex.Token, line: usize, is_estimate: bool) diag.Error!Request {
    if (t.len == 0 or t[0].tag != .string or t[0].text.len > 200) return bad(cx, line, "CONTRAST/ESTIMATE requires a quoted label of at most 200 characters");
    var rows: std.ArrayList(Row) = .empty;
    var ft: std.ArrayList(mapping.Term) = .empty;
    var rt: std.ArrayList(RandomTerm) = .empty;
    var last: ?usize = null;
    var random_side = false;
    var i: usize = 1;
    while (i < t.len and !at(t, i, .slash)) {
        if (at(t, i, .comma)) {
            if (is_estimate) return bad(cx, line, "ESTIMATE accepts only one row");
            if (ft.items.len + rt.items.len == 0) return bad(cx, line, "empty CONTRAST row");
            try rows.append(cx.arena, .{ .fixed_terms = ft.items, .random_terms = rt.items, .last_fixed = last });
            ft = .empty;
            rt = .empty;
            last = null;
            random_side = false;
            i += 1;
            continue;
        }
        if (at(t, i, .pipe)) {
            if (random_side) return bad(cx, line, "duplicate random-effect separator");
            random_side = true;
            i += 1;
            continue;
        }
        if (!at(t, i, .name)) return bad(cx, line, "expected an effect name");
        var name: []const u8 = undefined;
        var effect: ?usize = null;
        if (eq(t[i].text, "intercept")) {
            name = "Intercept";
            i += 1;
            if (!random_side and !m.matrix.intercept) return bad(cx, line, "INTERCEPT is unavailable with NOINT");
        } else {
            var factors: std.ArrayList(usize) = .empty;
            while (true) {
                if (!at(t, i, .name)) return bad(cx, line, "incomplete effect name");
                const ci = m.source.indexOf(t[i].text) orelse return bad(cx, line, "contrast variable is not on the input dataset");
                try factors.append(cx.arena, ci);
                i += 1;
                if (!at(t, i, .star)) break;
                i += 1;
            }
            if (at(t, i, .lparen)) return proc.failGap(cx.diags, line, "PROC MIXED: nested contrast-effect syntax is not implemented", .{});
            const normal = try coded.normalize(cx.arena, m.source, m.matrix.classes, .{ .factors = factors.items });
            name = normal.name;
            if (!random_side) {
                for (m.matrix.effects, 0..) |candidate, k| {
                    const n = try coded.normalize(cx.arena, m.source, m.matrix.classes, candidate);
                    if (eq(n.name, name)) {
                        effect = k;
                        break;
                    }
                }
                if (effect == null) return bad(cx, line, "fixed contrast effect is not in MODEL");
            }
        }
        var values: std.ArrayList(f64) = .empty;
        while (at(t, i, .number) or at(t, i, .minus) or at(t, i, .plus)) try values.append(cx.arena, try number(cx, t, &i, line));
        if (values.items.len == 0) return bad(cx, line, "contrast effect requires coefficients");
        if (random_side) {
            var found = false;
            for (z.columns) |column| if (eq(column.name, name)) {
                found = true;
                break;
            };
            if (!found) return bad(cx, line, "random contrast effect is not in RANDOM");
            for (rt.items) |term| if (eq(term.name, name)) return proc.failGap(cx.diags, line, "PROC MIXED: repeated random contrast terms are not implemented", .{});
            try rt.append(cx.arena, .{ .name = name, .values = values.items });
        } else {
            for (ft.items) |term| if (term.effect == effect) return proc.failGap(cx.diags, line, "PROC MIXED: repeated fixed contrast terms are not implemented", .{});
            try ft.append(cx.arena, .{ .effect = effect, .values = values.items });
            last = effect;
        }
    }
    if (ft.items.len + rt.items.len == 0) return bad(cx, line, "contrast row has no coefficients");
    try rows.append(cx.arena, .{ .fixed_terms = ft.items, .random_terms = rt.items, .last_fixed = last });
    var request: Request = .{ .label = t[0].text, .rows = rows.items, .is_estimate = is_estimate, .line = line };
    if (at(t, i, .slash)) i += 1;
    while (i < t.len) {
        if (!at(t, i, .name)) return bad(cx, line, "invalid contrast option");
        const option = t[i].text;
        i += 1;
        if (eq(option, "cl") and is_estimate) {
            request.cl = true;
            continue;
        }
        if ((eq(option, "lower") or eq(option, "lowertailed") or eq(option, "upper") or eq(option, "uppertailed")) and is_estimate) {
            const tail: kernel.Tail = if (eq(option, "lower") or eq(option, "lowertailed")) .lower else .upper;
            if (request.tail != .two and request.tail != tail) return bad(cx, line, "LOWER and UPPER cannot be combined");
            request.tail = tail;
            continue;
        }
        if (eq(option, "df") or eq(option, "singular") or (is_estimate and (eq(option, "divisor") or eq(option, "alpha")))) {
            if (!at(t, i, .eq)) return bad(cx, line, "contrast option requires =number");
            i += 1;
            const value = try number(cx, t, &i, line);
            if (eq(option, "df")) {
                if (value <= 0) return bad(cx, line, "DF must be positive");
                request.df = value;
            } else if (eq(option, "divisor")) {
                if (value == 0) return bad(cx, line, "DIVISOR must be nonzero");
                request.divisor = value;
            } else {
                if (value <= 0 or value >= 1) return bad(cx, line, "ALPHA and SINGULAR must be between zero and one");
                if (eq(option, "alpha")) request.alpha = value else request.singular = value;
            }
        } else {
            for ([_][]const u8{ "e", "chisq", "group", "grp", "subject", "sub" }) |known| if (eq(option, known)) return proc.failGap(cx.diags, line, "PROC MIXED: CONTRAST/ESTIMATE option {s} is not implemented", .{option});
            return bad(cx, line, "unknown CONTRAST/ESTIMATE option");
        }
    }
    return request;
}
pub fn parse(cx: proc.ProcCtx, m: model.Spec, z: random.Design, statements: anytype) diag.Error![]const Request {
    var result: std.ArrayList(Request) = .empty;
    for (statements) |statement| if (statement.kind == .estimate or statement.kind == .contrast) try result.append(cx.arena, try one(cx, m, z, statement.tokens, statement.line, statement.kind == .estimate));
    return result.items;
}
pub fn coefficients(cx: proc.ProcCtx, m: model.Spec, x: fixed.Design, r: random.Spec, z: random.Design, request: Request) diag.Error![]const f64 {
    const effects = try cx.arena.alloc(glm_parse.Effect, m.matrix.effects.len);
    for (m.matrix.effects, 0..) |effect, i| {
        const n = try coded.normalize(cx.arena, m.source, m.matrix.classes, effect);
        if (n.nested.len > 0) return proc.failGap(cx.diags, request.line, "PROC MIXED: nested contrast coefficient filling is not implemented", .{});
        effects[i] = .{ .name = n.name, .variables = effect.factors };
    }
    const spec: glm_parse.Spec = .{ .input = .{ .ds = @constCast(m.source) }, .responses = &.{m.matrix.response}, .effects = effects, .classes = m.matrix.classes, .intercept = m.matrix.intercept };
    const width = x.matrix.p + z.q;
    const result = try cx.arena.alloc(f64, width * request.rows.len);
    @memset(result, 0);
    for (request.rows, 0..) |row, k| {
        const fixed_l = try mapping.mapFor("MIXED", cx, spec, x.matrix, .{ .label = request.label, .terms = row.fixed_terms, .line = request.line, .divisor = request.divisor, .singular = request.singular });
        @memcpy(result[k * width ..][0..x.matrix.p], fixed_l);
        if (row.random_terms.len > 0) for (r.requests) |random_request| if (random_request.subject.len > 0 or random_request.group.len > 0) return proc.failGap(cx.diags, request.line, "PROC MIXED: random contrast SUBJECT/GROUP distribution is not implemented", .{});
        for (row.random_terms) |term| {
            var position: usize = 0;
            var producer: ?usize = null;
            for (z.columns, 0..) |column, j| if (eq(column.name, term.name)) {
                if (producer != null and producer.? != column.request_index) return proc.failGap(cx.diags, request.line, "PROC MIXED: ambiguous effect across RANDOM statements", .{});
                producer = column.request_index;
                result[k * width + x.matrix.p + j] = (if (position < term.values.len) term.values[position] else 0) / request.divisor;
                position += 1;
            };
            if (term.values.len > position) try cx.diags.warn(request.line, "PROC MIXED: extra random ESTIMATE coefficients are ignored", .{});
        }
    }
    return result;
}

pub fn publish(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: model.Spec, r: random.Spec, x: fixed.Design, z: random.Design, fitted: anytype, variances: []const f64, requests: []const Request) diag.Error!void {
    if (requests.len == 0) return;
    var needs_random = false;
    var estimates: usize = 0;
    for (requests) |request| {
        if (request.is_estimate) estimates += 1;
        if (request.cl or request.tail != .two) return proc.failGap(cx.diags, request.line, "PROC MIXED: confidence-limit and one-sided contrast table presentation is not implemented", .{});
        for (request.rows) |row| if (row.random_terms.len > 0) {
            needs_random = true;
        };
    }
    if (needs_random and m.has_repeated) return proc.failGap(cx.diags, m.line, "PROC MIXED: random-effect inference with REPEATED covariance is not implemented", .{});
    const width = x.matrix.p + z.q;
    const joint = if (needs_random) kernel.joint(cx.arena, x, z, fitted, variances) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, m.line, "PROC MIXED: joint fixed/random inference unavailable ({t})", .{err}) else blk: {
        const values = try cx.arena.alloc(f64, width);
        @memset(values, 0);
        @memcpy(values[0..x.matrix.p], fitted.coefficients);
        const cov = try cx.arena.alloc(f64, width * width);
        @memset(cov, 0);
        for (0..x.matrix.p) |i| for (0..x.matrix.p) |j| {
            cov[i * width + j] = fitted.covariance[i * x.matrix.p + j];
        };
        break :blk kernel.Joint{ .p = x.matrix.p, .q = z.q, .coefficients = values, .covariance = cov, .aliases = fitted.alias_coefficients };
    };
    const lines = try cx.arena.alloc([]const f64, requests.len);
    const dfs = try cx.arena.alloc(f64, requests.len);
    for (requests, 0..) |request, i| {
        lines[i] = try coefficients(cx, m, x, r, z, request);
        dfs[i] = if (request.df) |df| df else if (m.options.ddfm == .residual or z.components.len == 0) @floatFromInt(fitted.df_error) else blk: {
            const effect = request.rows[request.rows.len - 1].last_fixed orelse return proc.failGap(cx.diags, request.line, "PROC MIXED: specify DF= for intercept-only or random-only inference", .{});
            break :blk @floatFromInt(try random.containmentDF(cx, r, x.matrix, z, effect, x.weights, m.options.singular));
        };
    }
    const fmt = @import("../format.zig");
    if (estimates < requests.len) {
        try out.appendSlice(cx.arena, "\nContrasts\n\nNum Den\nLabel DF DF F Value Pr > F\n");
        for (requests, lines, dfs) |request, l, df| if (!request.is_estimate) {
            const result = kernel.contrast(cx.arena, joint, l, request.rows.len, df, request.singular) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, request.line, "PROC MIXED: contrast covariance boundary is not implemented ({t})", .{err});
            if (!result.estimable) {
                try cx.diags.note(request.line, "PROC MIXED: contrast {s} is not estimable", .{request.label});
                try out.print(cx.arena, "{s} . . . .\n", .{request.label});
            } else try out.print(cx.arena, "{s} {d} {d} {s} {s}\n", .{ request.label, result.num_df, result.den_df, if (result.f) |v| try std.fmt.allocPrint(cx.arena, "{d:.2}", .{v}) else ".", if (result.p) |p| std.mem.trim(u8, try fmt.apply(cx.arena, .{ .num = p }, "pvalue6.4"), " ") else "." });
        };
    }
    if (estimates > 0) {
        try out.appendSlice(cx.arena, "\nEstimates\n\nStandard\nLabel Estimate Error DF t Value Pr > |t|\n");
        for (requests, lines, dfs) |request, l, df| if (request.is_estimate) {
            const result = kernel.estimate(joint, l, df, request.alpha, request.tail, request.singular) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, request.line, "PROC MIXED: estimate covariance boundary is not implemented ({t})", .{err});
            if (!result.estimable) try out.print(cx.arena, "{s} Non-est . . . .\n", .{request.label}) else try out.print(cx.arena, "{s} {d:.4} {d:.4} {d} {s} {s}\n", .{ request.label, result.estimate.?, result.se.?, df, if (result.t) |v| try std.fmt.allocPrint(cx.arena, "{d:.2}", .{v}) else ".", if (result.p) |p| std.mem.trim(u8, try fmt.apply(cx.arena, .{ .num = p }, "pvalue6.4"), " ") else "." });
        };
    }
}

const Testing = struct {
    fn load(a: std.mem.Allocator) !@import("../dataset.zig").Dataset {
        return @import("glm_persistence_tests.zig").data(a, "tests/fixtures/stat/mixed/split_plot.sas", "sp", &.{ "Block", "A", "B", "Y" }, &.{}, 0);
    }
    fn body(a: std.mem.Allocator, d: *diag.Diagnostics, text: []const u8) ![]const lex.Token {
        const t = try lex.tokenize(a, text, d);
        return t[0 .. t.len - 1];
    }
    fn close(expected: f64, actual: f64) !void {
        // For the balanced24-row rational reference, V has condition<45 in
        // the cell-mean basis. Round this up to64 and budget2^17 arithmetic
        // operations for dense whitening/projection/quadratic forms. This
        // gamma_k budget is fixed from dimensions, not observed differences.
        const ku = 131072 * std.math.floatEps(f64);
        try std.testing.expectApproxEqAbs(expected, actual, 64 * ku / (1 - ku) * @max(1, @abs(expected)));
    }
};
test "STAT-MIXED-009 actual split-plot narrow intermediate broad estimates preserve all output tokens" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try Testing.load(a);
    try std.testing.expectEqual(@as(usize, 24), ds.rows.items.len);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var out: std.ArrayList(u8) = .empty;
    const source = "proc mixed data=sp; class A B Block; model Y=A B A*B; random Block A*Block; estimate 'a1 mean narrow' intercept 1 A 1 B .5 .5 A*B .5 .5 | Block .25 .25 .25 .25 A*Block .25 .25 .25 .25 0 0 0 0 0 0 0 0; estimate 'a1 mean intermed' intercept 1 A 1 B .5 .5 A*B .5 .5 | Block .25 .25 .25 .25; estimate 'a1 mean broad' intercept 1 A 1 B .5 .5 A*B .5 .5; run;";
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source, &diagnostics));
    const expected = try @import("glm_persistence_tests.zig").read(a, "tests/fixtures/stat/mixed/split_plot_estimates.txt");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    var reference = std.mem.tokenizeAny(u8, expected, " \r\n\t");
    while (reference.next()) |word| try std.testing.expectEqualStrings(word, actual.next() orelse return error.TestUnexpectedResult);
    try std.testing.expect(actual.next() == null);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
}

test "STAT-MIXED-009 split-plot joint covariance agrees with independent rational inference-space variances" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try Testing.load(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = "proc mixed data=sp; class A B Block; model Y=A B A*B; random Block A*Block; estimate 'n' intercept 1 A 1 B .5 .5 A*B .5 .5 | Block .25 .25 .25 .25 A*Block .25 .25 .25 .25; estimate 'i' intercept 1 A 1 B .5 .5 A*B .5 .5 | Block .25 .25 .25 .25; estimate 'b' intercept 1 A 1 B .5 .5 A*B .5 .5; run;";
    const declarations = try @import("mixed_parse.zig").parse(cx, try lex.tokenize(a, source, &diagnostics));
    const m = try model.parse(cx, &ds, declarations.statements, .formatted, 0.05);
    const r = try random.parse(cx, &ds, m.matrix, declarations.statements);
    const view = try @import("data_selection.zig").View.init(a, .{ .ds = &ds }, .{});
    const x = try fixed.build(cx, m, view);
    const z = try random.build(cx, r, view);
    const math = @import("mixed_fit.zig");
    const components = try a.alloc(math.Component, z.components.len);
    for (z.components, components) |src, *dest| dest.* = .{ .name = src.name, .kernel = src.kernel, .columns = src.columns };
    // Balanced split-plot ANOVA gives exact variances Block=2995/48,
    // A*Block=2215/144, residual=337/36. Use known V, not observed fit output.
    const variance = [_]f64{ 2995.0 / 48.0, 2215.0 / 144.0, 337.0 / 36.0 };
    const fit = try math.knownCovariance(a, .{ .x = x.matrix.x, .y = x.y, .n = x.matrix.n, .p = x.matrix.p, .weights = x.weights, .components = components, .singular = m.options.singular }, &variance);
    const joint = try kernel.joint(a, x, z, fit, &variance);
    const requests = try parse(cx, m, z, declarations.statements);
    for (requests, [_]f64{ 337.0 / 288.0, 321.0 / 64.0, 1979.0 / 96.0 }) |request, var_expected| {
        const l = try coefficients(cx, m, x, r, z, request);
        const result = try kernel.estimate(joint, l, 9, 0.05, .two, 1e-4);
        try std.testing.expect(result.estimable);
        try Testing.close(263.0 / 8.0, result.estimate.?);
        try Testing.close(var_expected, result.se.? * result.se.?);
        // Independent Student t(9) .975 quantile; inverse/CDF round-trip is
        // not the only check of confidence bounds.
        try Testing.close(263.0 / 8.0 - 2.2621571627409915 * @sqrt(var_expected), result.lower.?);
        try Testing.close(263.0 / 8.0 + 2.2621571627409915 * @sqrt(var_expected), result.upper.?);
        // Reversing a contrast reverses the point/t, preserves variance and two-sided p.
        const neg = try a.dupe(f64, l);
        for (neg) |*v| v.* = -v.*;
        const reversed = try kernel.estimate(joint, neg, 9, 0.05, .two, 1e-4);
        try Testing.close(-result.estimate.?, reversed.estimate.?);
        try Testing.close(result.se.?, reversed.se.?);
        try Testing.close(result.p.?, reversed.p.?);
        const lower = try kernel.estimate(joint, neg, 9, 0.05, .lower, 1e-4);
        const upper = try kernel.estimate(joint, l, 9, 0.05, .upper, 1e-4);
        try Testing.close(lower.p.?, upper.p.?);
        try std.testing.expect(lower.lower == null and upper.upper == null);
        try Testing.close(263.0 / 8.0 - 1.8331129326536335 * @sqrt(var_expected), upper.lower.?);
    }
}

test "STAT-MIXED-009 multirow broad and narrow CONTRAST use actual joint quadratic forms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try Testing.load(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var out: std.ArrayList(u8) = .empty;
    const source = "proc mixed data=sp; class A B Block; model Y=A B A*B; random Block A*Block; contrast 'A broad' A 1 -1 0 A*B .5 .5 -.5 -.5 0 0, A 1 0 -1 A*B .5 .5 0 0 -.5 -.5 /df=6; contrast 'A narrow' A 1 -1 0 A*B .5 .5 -.5 -.5 0 0 | A*Block .25 .25 .25 .25 -.25 -.25 -.25 -.25 0 0 0 0, A 1 0 -1 A*B .5 .5 0 0 -.5 -.5 | A*Block .25 .25 .25 .25 0 0 0 0 -.25 -.25 -.25 -.25; run;";
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source, &diagnostics));
    // Source physicalp6641 identifies these as the mixed A F and fixed-space A F.
    // Independent ANOVA: SSA=3919/12; broad denominator321/8, narrow337/36.
    try std.testing.expect(std.mem.indexOf(u8, out.items, "A broad 2 6 4.07 0.0764") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "A narrow 2 9 17.44 0.0008") != null);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
}

test "STAT-MIXED-009 TYPE3 producer consumes fixed GLS contrast rather than dropping it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/stat_glm_random_two_way.sas", "machine", &.{ "machine", "person", "rating" }, &.{}, 0);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("machine", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var out: std.ArrayList(u8) = .empty;
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, "proc mixed data=machine method=type3; class machine person; model rating=machine; random person machine*person; contrast 'machine broad' machine 1 0 -1, machine 0 1 -1; run;", &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "machine broad 2 10 16.72 0.0006") != null);
    try std.testing.expectEqual(@as(usize, 0), diagnostics.list.items.len);
}

test "STAT-MIXED-009 coefficient DIVISOR zero filling and nonestimability remain observable" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try Testing.load(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sp", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    var out: std.ArrayList(u8) = .empty;
    const source = "proc mixed data=sp; class A B Block; model Y=A B A*B; random Block A*Block; estimate 'scaled mean' intercept 2 A 2 B 1 1 A*B 1 1 /divisor=2; estimate 'not estimable' A 1 0 0 A*B 0 0 0 0 0 0; run;";
    try @import("mixed.zig").run(cx, &out, try lex.tokenize(a, source, &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "scaled mean 32.8750 4.5403 9 7.24 <.0001") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "not estimable Non-est . . . .") != null);
    const Case = struct { body: []const u8, code: u8 };
    for ([_]Case{ .{ .body = "estimate missing_label A 1;", .code = 1 }, .{ .body = "estimate 'bad' A 1 /divisor=0;", .code = 1 }, .{ .body = "estimate 'bad' A 1, A -1;", .code = 1 }, .{ .body = "contrast 'bad' A 1 /typo;", .code = 1 }, .{ .body = "estimate 'coef' A 1 /e;", .code = 2 }, .{ .body = "estimate 'ci' intercept 1 A 1 B .5 .5 A*B .5 .5 /cl;", .code = 2 } }) |c| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        var rejected: std.ArrayList(u8) = .empty;
        const program = try std.fmt.allocPrint(a, "proc mixed data=sp; class A B Block; model Y=A B A*B; random Block A*Block; {s} run;", .{c.body});
        try std.testing.expectError(error.ParseError, @import("mixed.zig").run(.{ .arena = a, .lib = &lib, .diags = &d }, &rejected, try lex.tokenize(a, program, &d)));
        try std.testing.expectEqual(c.code, diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
}
