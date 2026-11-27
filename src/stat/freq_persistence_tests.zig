//! Durable independent checks for STAT-FREQ-004..008. Original complete
//! listings live in tests/corpus/persist_freq_* and freq_binomial_example.
//! No test reads a temporary oracle directory.
const std = @import("std");
const t = std.testing;
const stat = @import("freq_tests.zig");
const risk = @import("freq_risk.zig");
const infer = @import("freq_risk_inference.zig");
const exact = @import("freq_exact.zig");

// Simpson integration of exp(-t*t), independent of the engine's normal CDF.
// 8192 panels on [0,12] bound discretization below 1e-12 for these cases;
// the omitted Gaussian tail beyond 12 is below 1e-63.
fn erfc(x: f64) f64 {
    if (x < 0) return 2 - erfc(-x);
    if (x >= 12) return 0;
    const h = (12 - x) / 8192;
    var sum = @exp(-x * x) + @exp(@as(f64, -144));
    for (1..8192) |i| {
        const u = x + @as(f64, @floatFromInt(i)) * h;
        sum += @as(f64, if (i % 2 == 0) 2 else 4) * @exp(-u * u);
    }
    return @as(f64, 2) / @sqrt(@as(f64, std.math.pi)) * h * sum / 3;
}

fn choose(n: usize, k: usize) f64 {
    var result: f64 = 1;
    for (0..@min(k, n - k)) |i| result = result * @as(f64, @floatFromInt(n - i)) / @as(f64, @floatFromInt(i + 1));
    return result;
}

// Direct finite binomial sum, independent of the production beta CDF/inverter.
fn cdf(k: usize, n: usize, p: f64) f64 {
    var result: f64 = 0;
    for (0..k + 1) |j| result += choose(n, j) * std.math.pow(f64, p, @floatFromInt(j)) * std.math.pow(f64, 1 - p, @floatFromInt(n - j));
    return result;
}

test "FREQ004 persisted FatComp integer allocations and conditional odds inversion" {
    const d = try exact.OddsDistribution.init(.{ 11, 4, 2, 6 });
    const actual = try d.tails(0, 100);
    var left: f64 = 0;
    var right: f64 = 0;
    var fisher: f64 = 0;
    const observed = choose(13, 11) * choose(10, 4);
    for (5..14) |x| {
        const w = choose(13, x) * choose(10, 15 - x);
        if (x <= 11) left += w;
        if (x >= 11) right += w;
        if (w <= observed) fisher += w;
    }
    const den = choose(23, 15);
    try t.expectApproxEqAbs(left / den, actual.left, 1e-12);
    try t.expectApproxEqAbs(right / den, actual.right, 1e-12);
    try t.expectApproxEqAbs(observed / den, actual.point, 1e-12);
    try t.expectApproxEqAbs(@as(f64, 292.0 / 7429.0), fisher / den, 1e-15);
    const r = (try stat.fisherWithAllocator(t.allocator, &.{ 11, 4, 2, 6 }, .{})).?;
    try t.expectApproxEqAbs(fisher / den, r.cell.two_sided, 1e-12);
    const dispatch = @import("freq_exact_execute.zig");
    const pearson = (try dispatch.run(t.allocator, .{ .rows = 2, .cols = 2, .counts = &.{ 11, 4, 2, 6 } }, .pchi, .{})).exact_test;
    try t.expectApproxEqAbs(fisher / den, pearson.two_sided, 1e-12);
    const tied = (try stat.fisherWithAllocator(t.allocator, &.{ 0, 5, 5, 0 }, .{})).?;
    try t.expectApproxEqAbs(@as(f64, 1.0 / 126.0), tied.point, 1e-14);
    const degenerate = (try stat.fisherWithAllocator(t.allocator, &.{ 0, 0, 1, 2 }, .{})).?;
    try t.expectEqual(@as(f64, 1), degenerate.cell.probability);
    var multinomial_tail: f64 = 0;
    for (0..11) |x| {
        if (x != 3) multinomial_tail += choose(10, x) * std.math.pow(f64, 0.3, @floatFromInt(x)) * std.math.pow(f64, 0.7, @floatFromInt(10 - x));
    }
    const one_way = (try dispatch.run(t.allocator, .{ .rows = 1, .cols = 2, .counts = &.{ 2, 8 } }, .pchi, .{ .expected = .{ .proportions = &.{ 0.3, 0.7 } } })).exact_test;
    try t.expectApproxEqAbs(multinomial_tail, one_way.two_sided, 1e-12);
    const ci = (try exact.oddsRatio(.{ 11, 4, 2, 6 }, 0.05, false, 100)).complete;
    // Invert the independently weighted noncentral hypergeometric tails:
    // w(x,theta)=C(13,x) C(10,15-x) theta^(x-5).
    for ([_]f64{ ci.lower, ci.upper }, 0..) |theta, side| {
        var sum: f64 = 0;
        var tail: f64 = 0;
        for (5..14) |x| {
            const w = choose(13, x) * choose(10, 15 - x) * std.math.pow(f64, theta, @floatFromInt(x - 5));
            sum += w;
            if (if (side == 0) x >= 11 else x <= 11) tail += w;
        }
        try t.expectApproxEqAbs(@as(f64, 0.025), tail / sum, 1e-11);
    }
}

test "FREQ005 independent Pearson likelihood continuity and Mantel Haenszel formulas" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const observed = [_]f64{ 1, 9, 11, 3 };
    const expected = [_]f64{ 5, 5, 7, 7 };
    var pearson: f64 = 0;
    var likelihood: f64 = 0;
    var corrected: f64 = 0;
    for (observed, expected) |o, e| {
        pearson += (o - e) * (o - e) / e;
        likelihood += 2 * o * @log(o / e);
        const delta = @max(0, @abs(o - e) - 0.5);
        corrected += delta * delta / e;
    }
    const r = try stat.contingency(arena.allocator(), .{ .rows = 2, .cols = 2, .counts = &observed }, null);
    for ([_]f64{ pearson, likelihood, corrected, pearson * 23 / 24 }, [_]stat.Test{ r.pearson, r.likelihood_ratio, r.continuity.?, r.mantel_haenszel.? }) |want, got| {
        try t.expectApproxEqAbs(want, got.statistic, 1e-12);
        try t.expectEqual(@as(f64, 1), got.df);
        try t.expectApproxEqAbs(erfc(@sqrt(want / 2)), got.p, 1e-12);
    }
}

test "FREQ007 independent binomial intervals equality and boundary probabilities" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Same two original samples and all five verify.py boundary cases.
    const cases = [_][4]f64{ .{ 341, 762, 0.1, 0.5 }, .{ 228, 762, 0.05, 0.28 }, .{ 0, 10, 0.05, 0.5 }, .{ 10, 10, 0.05, 0.5 }, .{ 2, 10, 0.05, 0.3 }, .{ 0, 10, 0.05, 0.99 }, .{ 10, 10, 0.05, 0.01 } };
    for (cases) |c| {
        const x = c[0];
        const n = c[1];
        const alpha = c[2];
        const p0 = c[3];
        const p = x / n;
        // Standard normal .95 and .975 quantiles, not the engine quantile.
        const z: f64 = if (alpha == 0.1) 1.6448536269514722 else 1.959963984540054;
        const se = @sqrt(p * (1 - p) / n);
        const sample = risk.Binomial{ .success = x, .total = n };
        const base = try risk.proportion(sample, alpha, false);
        try t.expectApproxEqAbs(p, base.estimate.?, 1e-14);
        try t.expectApproxEqAbs(se, base.se.?, 1e-14);
        const adjusted_n = n + z * z;
        const adjusted_p = (x + z * z / 2) / adjusted_n;
        const center = (p + z * z / (2 * n)) / (1 + z * z / n);
        const width = z * @sqrt((p * (1 - p) + z * z / (4 * n)) / n) / (1 + z * z / n);
        const ac_width = z * @sqrt(adjusted_p * (1 - adjusted_p) / adjusted_n);
        const bounds = [_][2]f64{ .{ p - z * se, p + z * se }, .{ adjusted_p - ac_width, adjusted_p + ac_width }, .{ center - width, center + width } };
        for ([_]risk.BinomialMethod{ .wald, .agresti_coull, .wilson }, bounds) |method, b| {
            const ci = try risk.binomialLimits(sample, alpha, method, false);
            // Original verifier compared f"{value:.4f}" exactly. The engine
            // uses probitOf and the reference uses NormalDist's quantile;
            // a 1e-12 endpoint contract was not part of that evidence.
            try printed(a, try std.fmt.allocPrint(a, "{d:.4}", .{@max(0, b[0])}), ci.lower, false);
            try printed(a, try std.fmt.allocPrint(a, "{d:.4}", .{@min(1, b[1])}), ci.upper, false);
        }
        const cp = try risk.binomialLimits(sample, alpha, .clopper_pearson, false);
        // Large-N finite sums can overflow choose(): for the original 762
        // samples use the stable recurrence below. No beta CDF is reused.
        const cp_lower = if (x == 0) 0 else invertCdf(@intFromFloat(x - 1), @intFromFloat(n), 1 - alpha / 2);
        const cp_upper = if (x == n) 1 else invertCdf(@intFromFloat(x), @intFromFloat(n), alpha / 2);
        try printed(a, try std.fmt.allocPrint(a, "{d:.4}", .{cp_lower}), cp.lower, false);
        try printed(a, try std.fmt.allocPrint(a, "{d:.4}", .{cp_upper}), cp.upper, false);
        const equality = try infer.binomial(sample, .{ .equality = p0 }, .null_value, alpha, false);
        const null_se = @sqrt(p0 * (1 - p0) / n);
        const statistic = (p - p0) / null_se;
        try t.expectApproxEqAbs(null_se, equality.lower.se.?, 1e-14);
        try t.expectApproxEqAbs(statistic, equality.lower.z.?, 1e-12);
        try t.expectApproxEqAbs(erfc(@abs(statistic) / @sqrt(@as(f64, 2))), equality.p.?, 1e-12);
    }
    const p: f64 = 228.0 / 762.0;
    const se = @sqrt(p * (1 - p) / 762);
    const tost = try infer.binomial(.{ .success = 228, .total = 762 }, .{ .equivalence = .{ .lower = 0.18, .upper = 0.38 } }, .sample, 0.05, false);
    const zl = (p - 0.18) / se;
    const zu = (p - 0.38) / se;
    try t.expectApproxEqAbs(zl, tost.lower.z.?, 1e-12);
    try t.expectApproxEqAbs(zu, tost.upper.?.z.?, 1e-12);
    try t.expectApproxEqAbs(@max(erfc(zl / @sqrt(@as(f64, 2))), erfc(-zu / @sqrt(@as(f64, 2)))) / 2, tost.p.?, 1e-12);
    try printed(a, try std.fmt.allocPrint(a, "{d:.4}", .{p - 1.6448536269514722 * se}), tost.limits.lower, false);
    try printed(a, try std.fmt.allocPrint(a, "{d:.4}", .{p + 1.6448536269514722 * se}), tost.limits.upper, false);
}

fn invertCdf(k: usize, n: usize, target: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 1;
    for (0..100) |_| {
        const mid = (lo + hi) / 2;
        if (stableCdf(k, n, mid) > target) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}

fn stableCdf(k: usize, n: usize, p: f64) f64 {
    if (n <= 10) return cdf(k, n, p);
    var term = std.math.pow(f64, 1 - p, @floatFromInt(n));
    var sum = term;
    for (0..k) |i| {
        term *= @as(f64, @floatFromInt(n - i)) * p / (@as(f64, @floatFromInt(i + 1)) * (1 - p));
        sum += term;
    }
    return sum;
}

fn printed(a: std.mem.Allocator, expected: []const u8, actual: ?f64, probability: bool) !void {
    const value = actual orelse return error.MissingStatistic;
    const text = if (probability and value < 0.0001) "<.0001" else try std.fmt.allocPrint(a, "{d:.4}", .{value});
    try t.expectEqualStrings(expected, text);
}

test "FREQ006 all 13 independent delta-method rows and seven null-SE tests" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/fixtures/stat/freq/association_reference.json", a, .limited(1 << 20));
    const reference = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
    const refs = reference.value.object.get("reference").?.object.get("measures").?.object;
    const matrix = stat.CountMatrix{ .rows = 3, .cols = 3, .counts = &.{ 12, 5, 3, 4, 17, 6, 2, 8, 13 } };
    const r = try stat.association(a, matrix, 0.05);
    const n = try stat.nominal(a, matrix, 0.05);
    const names = [_][]const u8{ "Gamma", "Kendall's Tau-b", "Stuart's Tau-c", "Somers' D C|R", "Somers' D R|C", "Pearson Correlation", "Spearman Correlation", "Lambda Asymmetric C|R", "Lambda Asymmetric R|C", "Lambda Symmetric", "Uncertainty Coefficient C|R", "Uncertainty Coefficient R|C", "Uncertainty Coefficient Symmetric" };
    const measures = [_]stat.Measure{ r.gamma, r.tau_b, r.tau_c, r.somers_cr, r.somers_rc, r.pearson, r.spearman, n.lambda_cr, n.lambda_rc, n.lambda_symmetric, n.uncertainty_cr, n.uncertainty_rc, n.uncertainty_symmetric };
    for (names, measures) |name, m| {
        const ref = refs.get(name).?.object;
        for (ref.get("printed").?.array.items, [_]?f64{ m.estimate, m.ase, m.lower, m.upper }) |want, got| try printed(a, want.string, got, false);
        if (ref.get("test")) |hypothesis| {
            for (hypothesis.object.get("printed").?.array.items, [_]?f64{ m.null_se, m.z, m.p_one, m.p_two }, 0..) |want, got, i| try printed(a, want.string, got, i >= 2);
        }
    }
}

test "FREQ008 six diagnostic orientations alpha and boundaries through public FREQ" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Case = struct { cells: [4]f64 = .{ 12, 8, 5, 25 }, ordered: [4]f64 = .{ 12, 8, 5, 25 }, order: []const u8 = "order=data", variables: []const u8 = "TestResult*Condition", alpha: f64 = 0.05 };
    const cases = [_]Case{ .{}, .{ .variables = "Condition*TestResult", .ordered = .{ 12, 5, 8, 25 } }, .{ .order = "", .ordered = .{ 25, 5, 8, 12 } }, .{ .alpha = 0.1 }, .{ .cells = .{ 5, 0, 0, 7 }, .ordered = .{ 5, 0, 0, 7 } }, .{ .cells = .{ 0, 4, 6, 0 }, .ordered = .{ 0, 4, 6, 0 } } };
    for (cases) |c| {
        const ds = try a.create(@import("../dataset.zig").Dataset);
        ds.* = .init(a, "d");
        _ = try ds.addColumn("TestResult", .char);
        _ = try ds.addColumn("Condition", .char);
        _ = try ds.addColumn("Count", .num);
        for (c.cells, 0..) |count, i| try ds.appendRow(&.{ .{ .str = if (i < 2) "positive" else "negative" }, .{ .str = if (i % 2 == 0) "positive" else "negative" }, .{ .num = count } });
        var lib = @import("../exec.zig").Library.init(a);
        try lib.put("d", ds);
        var diagnostics = @import("../diag.zig").Diagnostics.init(a);
        var output: std.ArrayList(u8) = .empty;
        const source = try std.fmt.allocPrint(a, "proc freq data=d {s}; weight Count / zeros; tables {s} / noprint senspec alpha={d}; run;", .{ c.order, c.variables, c.alpha });
        try @import("freq.zig").runFreq(.{ .arena = a, .lib = &lib, .diags = &diagnostics }, &output, try @import("../lexer.zig").tokenize(a, source, &diagnostics));
        try t.expectEqual(@as(usize, 0), diagnostics.list.items.len);
        const names = [_][]const u8{ "Sensitivity", "Specificity", "Positive Predictive Value", "Negative Predictive Value" };
        const x = c.ordered;
        const samples = [_][2]f64{ .{ x[0], x[0] + x[2] }, .{ x[3], x[1] + x[3] }, .{ x[0], x[0] + x[1] }, .{ x[3], x[2] + x[3] } };
        for (samples, names) |sample, name| {
            const p = sample[0] / sample[1];
            const se = @sqrt(p * (1 - p) / sample[1]);
            const z: f64 = if (c.alpha == 0.1) 1.6448536269514722 else 1.959963984540054;
            const expected = try std.fmt.allocPrint(a, "{s} {d:.4} {d:.4} {d:.4} {d:.4}", .{ name, p, se, @max(0, p - z * se), @min(1, p + z * se) });
            try expectRow(a, output.items, expected);
        }
        try expectRow(a, output.items, try std.fmt.allocPrint(a, "Sample Size = {d}", .{x[0] + x[1] + x[2] + x[3]}));
        try t.expect(std.mem.indexOf(u8, output.items, if (c.alpha == 0.1) "90%" else "95%") != null);
    }
}

fn expectRow(a: std.mem.Allocator, output: []const u8, expected: []const u8) !void {
    var lines = std.mem.tokenizeScalar(u8, output, '\n');
    var matches: usize = 0;
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t\r");
        var words: std.ArrayList([]const u8) = .empty;
        while (fields.next()) |word| try words.append(a, word);
        if (std.mem.eql(u8, try std.mem.join(a, " ", words.items), expected)) matches += 1;
    }
    try t.expectEqual(@as(usize, 1), matches);
}

fn attribute(node: []const u8, name: []const u8) !f64 {
    var rest = node;
    while (std.mem.indexOf(u8, rest, name)) |start| {
        const at = start + name.len;
        if (std.mem.startsWith(u8, rest[at..], "=\"")) {
            const value = rest[at + 2 ..];
            return std.fmt.parseFloat(f64, value[0 .. std.mem.indexOfScalar(u8, value, '"') orelse return error.MalformedSvg]);
        }
        rest = rest[at..];
    }
    return error.MissingSvgAttribute;
}

test "FREQ005 original 27 records independent GOF residual metadata and SVG coordinates" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/corpus/persist_freq_005_documented_feature.sas", a, .limited(1 << 20));
    const start = (std.mem.indexOf(u8, source, "datalines;") orelse return error.MissingData) + "datalines;".len;
    const data = source[start..];
    var fields = std.mem.tokenizeAny(u8, data[0..std.mem.indexOfScalar(u8, data, ';').?], " \t\r\n");
    const ds = try a.create(@import("../dataset.zig").Dataset);
    ds.* = .init(a, "Color");
    _ = try ds.addColumn("Region", .num);
    _ = try ds.addColumn("Hair", .char);
    _ = try ds.addColumn("Count", .num);
    ds.columns.items[0].label = "Geographic Region";
    ds.columns.items[1].label = "Hair Color";
    const names = [_][]const u8{ "fair", "red", "medium", "dark", "black" };
    var counts = [_][5]f64{ .{ 0, 0, 0, 0, 0 }, .{ 0, 0, 0, 0, 0 } };
    var records: usize = 0;
    while (fields.next()) |region| {
        _ = fields.next() orelse return error.MissingEye;
        const hair = fields.next() orelse return error.MissingHair;
        const count = try std.fmt.parseFloat(f64, fields.next() orelse return error.MissingCount);
        const group = try std.fmt.parseInt(usize, region, 10);
        for (names, 0..) |name, j| if (std.mem.eql(u8, name, hair)) {
            counts[group - 1][j] += count;
        };
        try ds.appendRow(&.{ .{ .num = @floatFromInt(group) }, .{ .str = hair }, .{ .num = count } });
        records += 1;
    }
    try t.expectEqual(@as(usize, 27), records);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("Color", ds);
    var diagnostics = @import("../diag.zig").Diagnostics.init(a);
    var dir = t.tmpDir(.{});
    defer dir.cleanup();
    var listing = @import("../ods_listing.zig").Listing{};
    var graphs = @import("graphics_svg.zig").Session{ .arena = a, .io = t.io, .diags = &diagnostics, .enabled = true, .listing = &listing, .gpath = try dir.dir.realPathFileAlloc(t.io, ".", a) };
    var output: std.ArrayList(u8) = .empty;
    const program = "proc freq data=Color order=data; by Region; weight Count; tables Hair / nocum chisq testp=(30 12 30 25 3) plots(only)=deviationplot(type=dotplot); run;";
    try @import("freq.zig").runFreq(.{ .arena = a, .lib = &lib, .diags = &diagnostics, .graphics = &graphs, .listing = &listing }, &output, try @import("../lexer.zig").tokenize(a, program, &diagnostics));
    try graphs.flush();
    try t.expect(!diagnostics.hasErrors());
    for (counts, 0..) |observed, group| {
        var total: f64 = 0;
        for (observed) |o| total += o;
        const proportions = [_]f64{ 0.30, 0.12, 0.30, 0.25, 0.03 };
        var chi: f64 = 0;
        for (observed, proportions) |o, p| chi += (o - total * p) * (o - total * p) / (total * p);
        const result = try stat.goodnessOfFit(&observed, .{ .proportions = &proportions }, null);
        try t.expectApproxEqAbs(chi, result.pearson.statistic, 1e-12);
        // df=4 survival function is exactly exp(-x/2)*(1+x/2).
        const probability = @exp(-chi / 2) * (1 + chi / 2);
        try t.expectApproxEqAbs(probability, result.pearson.p, 1e-12);
        const svg = try dir.dir.readFileAlloc(t.io, try std.fmt.allocPrint(a, "opensas-{d:0>4}-deviationplot.svg", .{group + 1}), a, .limited(1 << 20));
        try t.expect(std.mem.indexOf(u8, svg, "data-kind=\"deviationplot\"") != null);
        try t.expect(std.mem.indexOf(u8, svg, try std.fmt.allocPrint(a, "Geographic Region={d}", .{group + 1})) != null);
        try t.expect(std.mem.indexOf(u8, svg, try std.fmt.allocPrint(a, "Pr &gt; ChiSq   {d:.4}", .{probability})) != null);
        const axis_start = std.mem.indexOf(u8, svg, "<g class=\"axes\">").?;
        const axes = svg[axis_start .. axis_start + std.mem.indexOf(u8, svg[axis_start..], "</g>").?];
        // Read the actual tick endpoints and their coordinates, independently
        // interpolating the exact residual onto the declared SVG scale.
        var texts = std.mem.splitSequence(u8, axes, "<text ");
        _ = texts.next();
        var lo: f64 = 0;
        var hi: f64 = 0;
        var left: f64 = 0;
        var right: f64 = 0;
        var first = true;
        while (texts.next()) |node| {
            const gt = std.mem.indexOfScalar(u8, node, '>').?;
            const end = std.mem.indexOf(u8, node, "</text>").?;
            hi = try std.fmt.parseFloat(f64, node[gt + 1 .. end]);
            right = try attribute(node[0..gt], "x");
            if (first) {
                lo = hi;
                left = right;
                first = false;
            }
        }
        var dots = std.mem.splitSequence(u8, svg, "<circle class=\"dot\"");
        _ = dots.next();
        for (observed, proportions) |o, p| {
            const node = dots.next() orelse return error.MissingDot;
            const tag = node[0..std.mem.indexOfScalar(u8, node, '>').?];
            const residual = (o - total * p) / (total * p);
            try t.expectEqual(o, try attribute(tag, "data-count"));
            try t.expectApproxEqAbs(residual, try attribute(tag, "data-value"), 1e-14);
            const coordinate = left + (right - left) * (residual - lo) / (hi - lo);
            // Original verifier requires exact equality at SVG two decimals.
            try t.expectEqualStrings(try std.fmt.allocPrint(a, "{d:.2}", .{coordinate}), try std.fmt.allocPrint(a, "{d:.2}", .{try attribute(tag, "cx")}));
        }
        try t.expect(dots.next() == null);
    }
}
