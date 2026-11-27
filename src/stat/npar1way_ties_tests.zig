//! STAT-NPAR1WAY-003, SAS/STAT15.4 physical pp.7236-7239. The React
//! example has 19 public observations in five tie groups. Exact tails below
//! are independently enumerated over all C(19,6)=27132 individual subsets.
const std = @import("std");
const t = std.testing;
const stats = @import("npar1way_stats.zig");
const proc = @import("npar1way.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const values = [_]f64{ 1.94, 1.94, 2.92, 2.92, 2.92, 2.92, 3.27, 3.27, 3.27, 3.27, 3.70, 3.70, 3.74, 3.27, 3.27, 3.27, 3.70, 3.70, 3.74 };
fn groups() [19]usize {
    var g: [19]usize = undefined;
    @memset(g[0..13], 0);
    @memset(g[13..19], 1);
    return g;
}
const only = stats.Options{ .anova = false, .wilcoxon = true, .median = false, .vw = false, .savage = false, .edf = false, .exact_wilcoxon = true, .continuity = false };
fn probability(z: f64, df: ?usize) f64 {
    // Independent Simpson integration of normal / Student-t PDF on [0,|z|].
    // For t18, Gamma(9.5)/(sqrt(18*pi)*Gamma(9)) is a finite product.
    // Here |z|<2: Simpson truncation with 8192 panels is below 4e-16
    // (fourth derivatives bounded by10); f64 accumulation is covered by1e-12.
    const panels = 8192;
    const end = @abs(z);
    const h = end / panels;
    var constant: f64 = 1.0 / @sqrt(2.0 * std.math.pi);
    if (df != null) {
        constant = 0.5 / @sqrt(@as(f64, 18));
        for (1..9) |i| constant *= (@as(f64, @floatFromInt(i)) + 0.5) / @as(f64, @floatFromInt(i));
    }
    var integral: f64 = 0;
    for (0..panels + 1) |i| {
        const x = @as(f64, @floatFromInt(i)) * h;
        const pdf = if (df == null) constant * @exp(-x * x / 2) else constant * std.math.pow(f64, 1 + x * x / 18, -9.5);
        const weight: f64 = if (i == 0 or i == panels) 1 else if (i % 2 == 1) 4 else 2;
        integral += weight * pdf;
    }
    return 0.5 - integral * h / 3;
}
test "NPAR003 React tie sums covariance and exact allocations independent enumeration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const g = groups();
    const r = try stats.compute(a, &values, &g, 2, only);
    const s = r.scores[0];
    const test_result = s.two_sample.?;
    const expected_ranks = [_]f64{ 1.5, 1.5, 4.5, 4.5, 4.5, 4.5, 10, 10, 10, 10, 15.5, 15.5, 18.5, 10, 10, 10, 15.5, 15.5, 18.5 };
    try t.expectEqualSlices(f64, &expected_ranks, s.values);
    try t.expectEqual(@as(usize, 1), test_result.selected);
    try t.expectEqual(@as(f64, 79.5), test_result.statistic);
    try t.expectEqual(@as(f64, 110.5), s.groups[0].sum);
    try t.expectEqual(@as(f64, 130), s.groups[0].expected);
    try t.expectEqual(@as(f64, 60), s.groups[1].expected);
    const variance: f64 = 6.0 * 13.0 * 531.0 / (19.0 * 18.0);
    const z = 19.5 / @sqrt(variance);
    try t.expectApproxEqAbs(@sqrt(variance), s.groups[0].stddev, 1e-13);
    try t.expectApproxEqAbs(z, test_result.z.?, 1e-13);
    try t.expectApproxEqAbs(z * z, s.chi_square.?, 1e-13);
    try t.expectApproxEqAbs(probability(z, null), test_result.p_one.?, 1e-12);
    try t.expectApproxEqAbs(2 * probability(z, null), s.p.?, 1e-12);
    try t.expectApproxEqAbs(probability(z, 18), test_result.p_t_one.?, 1e-12);
    var total: u64 = 0;
    var lower: u64 = 0;
    var upper: u64 = 0;
    var two: u64 = 0;
    for (0..@as(usize, 1 << 19)) |mask| {
        if (@popCount(mask) != 6) continue;
        var sum: f64 = 0;
        for (expected_ranks, 0..) |v, i| {
            if (mask & (@as(usize, 1) << @intCast(i)) != 0) sum += v;
        }
        total += 1;
        if (sum <= 79.5) lower += 1;
        if (sum >= 79.5) upper += 1;
        if (@abs(sum - 60) >= 19.5) two += 1;
    }
    const exact = test_result.exact.?;
    try t.expectEqual(@as(u64, 27132), total);
    try t.expectEqual(total, exact.allocations);
    try t.expectEqual(lower, exact.lower_count);
    try t.expectEqual(upper, exact.upper_count);
    try t.expectEqual(two, exact.two_sided_count);
    try t.expectApproxEqAbs(@as(f64, @floatFromInt(upper)) / @as(f64, @floatFromInt(total)), exact.upper, 1e-15);
    var corrected_options = only;
    corrected_options.continuity = true;
    const corrected = (try stats.compute(a, &values, &g, 2, corrected_options)).scores[0];
    try t.expectApproxEqAbs(19.0 / @sqrt(variance), corrected.two_sample.?.z.?, 1e-13);
    try t.expectEqual(s.chi_square, corrected.chi_square);
    try t.expectEqual(exact, corrected.two_sample.?.exact.?);
}
fn wordsEqual(want: []const u8, got: []const u8) !void {
    var left = std.mem.tokenizeAny(u8, want, " \r\n\t");
    var right = std.mem.tokenizeAny(u8, got, " \r\n\t");
    while (left.next()) |word| {
        try t.expectEqualStrings(word, right.next() orelse return error.MissingWord);
    }
    try t.expect(right.next() == null);
}
test "NPAR003 original full React numerical and heading contract preserves formatting gap" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "React");
    _ = try ds.addColumn("Stim", .num);
    _ = try ds.addColumn("Time", .num);
    const source = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/corpus/persist_npar_react.sas", a, .limited(1 << 20));
    const data = source[std.mem.indexOf(u8, source, "datalines;").? + 10 ..];
    var fields = std.mem.tokenizeAny(u8, data[0..std.mem.indexOfScalar(u8, data, ';').?], " \t\r\n");
    while (fields.next()) |group| {
        const response = fields.next() orelse return error.MissingResponse;
        try ds.appendRow(&.{ .{ .num = try std.fmt.parseFloat(f64, group) }, .{ .num = try std.fmt.parseFloat(f64, response) } });
    }
    try t.expectEqual(@as(usize, 19), ds.rowCount());
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("React", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try proc.run(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try lex.tokenize(a, source[std.mem.indexOf(u8, source, "proc npar1way").?..], &d));
    const contract = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/corpus/persist_npar_react.txt", a, .limited(1 << 20));
    const start = std.mem.indexOf(u8, contract, "words ").? + 6;
    const rest = contract[start..];
    const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
    try numericWordsEqual(rest[0..end], out.items);
    try t.expectEqual(@as(usize, 0), d.list.items.len);
}
test "NPAR003 multiway score covariance and class order invariance" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const v = [_]f64{ 1, 2, 2, 2, 4, 7, 8 };
    const g = [_]usize{ 0, 0, 1, 1, 1, 2, 2 };
    const r = try stats.compute(a, &v, &g, 3, .{});
    for (r.scores) |score| {
        var mean: f64 = 0;
        for (score.values) |x| mean += x / 7;
        var variance: f64 = 0;
        for (score.values) |x| variance += (x - mean) * (x - mean) / 6;
        var chi: f64 = 0;
        for (score.groups, r.counts) |summary, n| {
            const nf: f64 = @floatFromInt(n);
            const delta = summary.sum - nf * mean;
            chi += delta * delta / (nf * variance);
            try t.expectApproxEqAbs(nf * (7 - nf) * variance / 7, summary.stddev * summary.stddev, 1e-12);
        }
        try t.expectEqual(@as(usize, 2), score.df);
        try t.expectApproxEqAbs(chi, score.chi_square.?, 1e-12);
        // Chi-square2 survival is exp(-chi/2), independent of gamma CDF.
        try t.expectApproxEqAbs(@exp(-chi / 2), score.p.?, 1e-12);
    }
    const swapped = try stats.compute(a, &v, &.{ 2, 2, 1, 1, 1, 0, 0 }, 3, .{});
    for (r.scores, swapped.scores) |x, y| try t.expectApproxEqAbs(x.chi_square.?, y.chi_square.?, 1e-12);
}

test "NPAR003 VARINFO ties counts selected rows frequencies empty classes and internal values" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "Counts");
    _ = try ds.addColumn("group", .num);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("f", .num);
    const nan = std.math.nan(f64);
    for ([_][3]f64{ .{ 1, 1, 1 }, .{ 1, 2, 2.9 }, .{ 2, 2, 1 }, .{ 2, 3, 1 }, .{ 3, nan, 1 }, .{ nan, 4, 1 } }) |r|
        try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] } });
    const info = @import("npar1way_varinfo.zig");
    const got = try info.collect(a, ds, ds.rows.items, 0, 1, 2, false);
    try t.expectEqual(info.Info{ .used = 4, .missing = 2, .frequency = 5, .classes = 2, .empty_classes = 1, .levels = 3, .tied = 3 }, got);
    const missing = try info.collect(a, ds, ds.rows.items, 0, 1, 2, true);
    try t.expectEqual(info.Info{ .used = 5, .missing = 1, .frequency = 6, .classes = 3, .empty_classes = 1, .levels = 4, .tied = 3 }, missing);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("Counts", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try proc.run(cx, &out, try lex.tokenize(a, "proc npar1way data=Counts wilcoxon varinfo(ties); class group; var x; freq f; run;", &d));
    const start = std.mem.indexOf(u8, out.items, "Variable Information").?;
    const rest = out.items[start..];
    const end = std.mem.indexOf(u8, rest, "The NPAR1WAY Procedure").?;
    try wordsEqual("Variable Information for Variable x Number of Observations Used 4 Number of Missing Observations 2 Sum of Frequencies Used 5 Number of Class Levels Used 2 Number of Empty Class Levels Excluded 1 Number of Variable Levels 3 Number of Tied Observations 3", rest[0..end]);
    try t.expectEqual(@as(usize, 0), d.list.items.len);
    out.clearRetainingCapacity();
    try proc.run(cx, &out, try lex.tokenize(a, "proc npar1way data=Counts wilcoxon varinfo; class group; var x; run;", &d));
    try t.expect(std.mem.indexOf(u8, out.items, "Number of Tied Observations") == null);
    try t.expect(std.mem.indexOf(u8, out.items, "Sum of Frequencies Used") == null);
    out.clearRetainingCapacity();
    try proc.run(cx, &out, try lex.tokenize(a, "proc npar1way data=Counts noprint wilcoxon varinfo(ties); class group; var x; run;", &d));
    try t.expectEqual(@as(usize, 0), out.items.len);
    // A displayed rounding format cannot merge distinct response values.
    ds.columns.items[1].format = "1.";
    const adjusted_row = try a.dupe(Value, ds.rows.items[2]);
    adjusted_row[1] = .{ .num = 2 + 2 * std.math.floatEps(f64) };
    ds.rows.items[2] = adjusted_row;
    const raw = try info.collect(a, ds, ds.rows.items, 0, 1, null, false);
    try t.expectEqual(@as(usize, 4), raw.levels);
    try t.expectEqual(@as(usize, 0), raw.tied);
}

// Partial listing acceptance only: every heading and field remains in order,
// and only the three explicitly marked ~0 numeric tokens allow an equal
// numerical spelling (zero tolerance). All other fields are byte-exact.
// This deliberately does not claim SAS trailing-zero formatting parity; the
// original expected bytes remain intact for closing that known gap later.
fn numericWordsEqual(want: []const u8, got: []const u8) !void {
    var left = std.mem.tokenizeAny(u8, want, " \r\n\t");
    var right = std.mem.tokenizeAny(u8, got, " \r\n\t");
    while (left.next()) |word| {
        const actual = right.next() orelse return error.MissingWord;
        if (std.mem.eql(u8, word, actual)) continue;
        if (!std.mem.endsWith(u8, word, "~0")) return error.LiteralFieldMismatch;
        const number = std.fmt.parseFloat(f64, word[0 .. word.len - 2]) catch return error.InvalidNumericReference;
        const actual_number = std.fmt.parseFloat(f64, actual) catch return error.NumericFieldMismatch;
        try t.expectEqual(number, actual_number);
    }
    try t.expect(right.next() == null);
}
