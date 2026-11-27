//! MIXED default objects: source pp.6720-6729 and original SAS TRACE.
//! Numeric reference values come from the public Heights model, not captured
//! OpenSAS output. Schema widths are logical capacities, not claimed SAS widths.
const std = @import("std");
const t = std.testing;
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const ods = @import("../ods.zig");
const listing = @import("../ods_listing.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const Harness = struct {
    cx: proc.ProcCtx,
    capture: *ods.Capture,
    listing: *listing.Listing,
    fn init(a: std.mem.Allocator, copies: usize) !Harness {
        const lib = try a.create(@import("../exec.zig").Library);
        lib.* = .init(a);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        const cap = try a.create(ods.Capture);
        cap.* = .{};
        const dest = try a.create(listing.Listing);
        dest.* = .{};
        const ds = try a.create(Dataset);
        ds.* = .init(a, "heights");
        _ = try ds.addColumn("Family", .num);
        _ = try ds.addColumn("Gender", .char);
        _ = try ds.addColumn("Height", .num);
        _ = try ds.addColumn("batch", .num);
        ds.setFormat("batch", "3.");
        ds.setLabel("batch", "Run Batch");
        const data = [_][3]f64{ .{ 1, 0, 67 }, .{ 1, 0, 66 }, .{ 1, 0, 64 }, .{ 1, 1, 71 }, .{ 1, 1, 72 }, .{ 2, 0, 63 }, .{ 2, 0, 63 }, .{ 2, 0, 67 }, .{ 2, 1, 69 }, .{ 2, 1, 68 }, .{ 2, 1, 70 }, .{ 3, 0, 63 }, .{ 3, 1, 64 }, .{ 4, 0, 67 }, .{ 4, 0, 66 }, .{ 4, 1, 67 }, .{ 4, 1, 67 }, .{ 4, 1, 69 } };
        for (0..copies) |copy| for (data) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .str = if (row[1] == 0) "F" else "M" }, .{ .num = row[2] }, .{ .num = @floatFromInt(copy + 1) } });
        try lib.put("heights", ds);
        return .{ .cx = .{ .arena = a, .lib = lib, .diags = d, .capture = cap, .listing = dest }, .capture = cap, .listing = dest };
    }
    fn output(h: Harness, source: []const u8) !void {
        try h.capture.parse(h.cx.arena, h.cx.diags, try lex.tokenize(h.cx.arena, source, h.cx.diags));
    }
    fn run(h: Harness, source: []const u8) ![]const u8 {
        var out: std.ArrayList(u8) = .empty;
        try @import("mixed.zig").run(h.cx, &out, try lex.tokenize(h.cx.arena, source, h.cx.diags));
        return out.items;
    }
};
const fixed_source = "proc mixed data=heights;class Family Gender;model Height=Gender Family Family*Gender;run;";
const random_source = "proc mixed data=heights;class Family Gender;model Height=Gender;random Family Family*Gender;run;";
fn words(want: []const u8, got: []const u8) !void {
    var a = std.mem.tokenizeAny(u8, want, " \r\n\t");
    var b = std.mem.tokenizeAny(u8, got, " \r\n\t");
    while (a.next()) |word| try t.expectEqualStrings(word, b.next() orelse return error.MissingField);
    try t.expect(b.next() == null);
}
fn dataset(h: Harness, name: []const u8) !*Dataset {
    return h.cx.lib.find(name) orelse error.MissingDataset;
}
fn number(ds: *const Dataset, row: usize, name: []const u8) f64 {
    return ds.rows.items[row][ds.indexOf(name).?].num;
}
fn text(ds: *const Dataset, row: usize, name: []const u8) []const u8 {
    return ds.rows.items[row][ds.indexOf(name).?].str;
}
fn columns(ds: *const Dataset, names: []const []const u8, types: []const bool, formats: []const ?[]const u8) !void {
    try t.expectEqual(names.len, ds.columns.items.len);
    for (ds.columns.items, names, types, formats) |column, name, numeric, display| {
        try t.expectEqualStrings(name, column.name);
        try t.expectEqual(if (numeric) @import("../pdv.zig").VarType.num else .char, column.type);
        if (numeric) try t.expectEqual(@as(?usize, 8), column.len);
        if (display) |f| try t.expectEqualStrings(f, column.format orelse return error.MissingFormat) else try t.expect(column.format == null);
    }
}
test "MIXED016 complete original listing and sixteen trace objects retain all metadata" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a, 1);
    h.listing.trace = h.cx.diags;
    var output: std.ArrayList(u8) = .empty;
    try output.appendSlice(a, try h.run(fixed_source));
    try output.appendSlice(a, try h.run(random_source));
    const expected = try @import("ttest_test_assets.zig").listing(a, "tests/corpus/persist_mixed_heights.txt");
    try words(expected, output.items);
    var trace: std.ArrayList(u8) = .empty;
    var count: usize = 0;
    for (h.cx.diags.list.items) |entry| {
        if (std.mem.startsWith(u8, entry.message, "Output Added:")) {
            try trace.appendSlice(a, entry.message);
            try trace.append(a, '\n');
            count += 1;
        } else if (std.mem.eql(u8, entry.message, "Convergence criteria met.")) {
            try trace.appendSlice(a, "NOTE: Convergence criteria met.\n");
        } else return error.UnexpectedDiagnostic;
    }
    try t.expectEqual(@as(usize, 16), count);
    const reference = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/fixtures/stat/mixed/default_trace.txt", a, .limited(1 << 20));
    try words(reference, trace.items);
}
test "MIXED016 typed default schemas every row and missing criterion independent of listing" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a, 1);
    try h.output("ods output ModelInfo=mi ClassLevels=cl Dimensions=dim NObs=no IterHistory=ih ConvergenceStatus=cs CovParms=cp FitStatistics=fs Tests3=tt;");
    _ = try h.listing.parse(a, h.cx.diags, try lex.tokenize(a, "ods select none;", h.cx.diags));
    try t.expectEqual(@as(usize, 0), (try h.run(random_source)).len);
    try h.capture.finish(h.cx.lib, h.cx.diags);
    const mi = try dataset(h, "mi");
    try columns(mi, &.{ "Descr", "Value" }, &.{ false, false }, &.{ null, null });
    try t.expectEqual(@as(usize, 7), mi.rowCount());
    for ([_][]const u8{ "Data Set", "Dependent Variable", "Covariance Structure", "Estimation Method", "Residual Variance Method", "Fixed Effects SE Method", "Degrees of Freedom Method" }, [_][]const u8{ "WORK.HEIGHTS", "Height", "Variance Components", "REML", "Profile", "Model-Based", "Containment" }, 0..) |label, value, i| {
        try t.expectEqualStrings(label, text(mi, i, "Descr"));
        try t.expectEqualStrings(value, text(mi, i, "Value"));
    }
    const cl = try dataset(h, "cl");
    try columns(cl, &.{ "Class", "Levels", "Values" }, &.{ false, true, false }, &.{ null, "8.", null });
    try t.expectEqual(@as(usize, 2), cl.rowCount());
    try t.expectEqualStrings("Family", text(cl, 0, "Class"));
    try t.expectEqualStrings("1 2 3 4", text(cl, 0, "Values"));
    try t.expectEqual(@as(f64, 4), number(cl, 0, "Levels"));
    try t.expectEqualStrings("Gender", text(cl, 1, "Class"));
    try t.expectEqualStrings("F M", text(cl, 1, "Values"));
    try t.expectEqual(@as(f64, 2), number(cl, 1, "Levels"));
    const dim = try dataset(h, "dim");
    try columns(dim, &.{ "Descr", "Value" }, &.{ false, true }, &.{ null, "8." });
    try t.expectEqual(@as(usize, 5), dim.rowCount());
    for ([_]f64{ 3, 3, 12, 1, 18 }, 0..) |value, i| try t.expectEqual(value, number(dim, i, "Value"));
    const no = try dataset(h, "no");
    try columns(no, &.{ "Label", "N", "NObsRead", "NObsUsed" }, &.{ false, true, true, true }, &.{ null, "8.", "8.", "8." });
    try t.expectEqual(@as(usize, 3), no.rowCount());
    for ([_]f64{ 18, 18, 0 }, 0..) |value, i| {
        try t.expectEqual(value, number(no, i, "N"));
        try t.expectEqual(@as(f64, 18), number(no, i, "NObsRead"));
        try t.expectEqual(@as(f64, 18), number(no, i, "NObsUsed"));
    }
    const ih = try dataset(h, "ih");
    try columns(ih, &.{ "Iteration", "Evaluations", "M2ResLogLike", "Criterion" }, &.{ true, true, true, true }, &.{ "8.", "8.", "12.8", "12.8" });
    try t.expectEqual(@as(usize, 7), ih.rowCount());
    const objectives = [_]f64{ 74.11074833, 71.51614003, 71.13845990, 71.03613556, 71.02281757, 71.02245904, 71.02245869 };
    const criteria = [_]f64{ 0, 0.01441208, 0.00412226, 0.00058188, 0.00001689, 0.00000002, 0 };
    for (objectives, criteria, 0..) |objective, criterion, i| {
        try t.expectEqual(@as(f64, @floatFromInt(i)), number(ih, i, "Iteration"));
        try t.expectEqual(@as(f64, if (i == 1) 2 else 1), number(ih, i, "Evaluations"));
        try t.expectApproxEqAbs(objective, number(ih, i, "M2ResLogLike"), 0.000000005);
        if (i == 0) try t.expect(std.math.isNan(number(ih, i, "Criterion"))) else try t.expectApproxEqAbs(criterion, number(ih, i, "Criterion"), 0.000000005);
    }
    const cs = try dataset(h, "cs");
    try columns(cs, &.{ "Status", "pdG", "pdH", "Reason" }, &.{ true, true, true, false }, &.{ "8.", "8.", "8.", null });
    try t.expectEqual(@as(usize, 1), cs.rowCount());
    try t.expectEqual(@as(f64, 0), number(cs, 0, "Status"));
    try t.expectEqual(@as(f64, 1), number(cs, 0, "pdG"));
    try t.expectEqual(@as(f64, 1), number(cs, 0, "pdH"));
    try t.expectEqualStrings("Convergence criteria met.", text(cs, 0, "Reason"));
    const cp = try dataset(h, "cp");
    try columns(cp, &.{ "CovParm", "Estimate" }, &.{ false, true }, &.{ null, "12.4" });
    try t.expectEqual(@as(usize, 3), cp.rowCount());
    for ([_][]const u8{ "Family", "Family*Gender", "Residual" }, [_]f64{ 2.4010, 1.7657, 2.1668 }, 0..) |name, value, i| {
        try t.expectEqualStrings(name, text(cp, i, "CovParm"));
        try t.expectApproxEqAbs(value, number(cp, i, "Estimate"), 0.00005);
    }
    const fs = try dataset(h, "fs");
    try columns(fs, &.{ "Descr", "Value" }, &.{ false, true }, &.{ null, "12.1" });
    try t.expectEqual(@as(usize, 4), fs.rowCount());
    const ll = number(ih, 6, "M2ResLogLike");
    for ([_]f64{ ll, ll + 6, ll + 8, ll + 3 * @log(@as(f64, 4)) }, 0..) |value, i| try t.expectApproxEqAbs(value, number(fs, i, "Value"), 1e-12);
    const tt = try dataset(h, "tt");
    try columns(tt, &.{ "Effect", "NumDF", "DenDF", "FValue", "ProbF" }, &.{ false, true, true, true, true }, &.{ null, "8.", "8.", "8.2", "PVALUE6.4" });
    try t.expectEqual(@as(usize, 1), tt.rowCount());
    try t.expectEqualStrings("Gender", text(tt, 0, "Effect"));
    try t.expectEqual(@as(f64, 1), number(tt, 0, "NumDF"));
    try t.expectEqual(@as(f64, 3), number(tt, 0, "DenDF"));
    try t.expectApproxEqAbs(@as(f64, 7.95), number(tt, 0, "FValue"), 0.005);
    try t.expectApproxEqAbs(@as(f64, 0.0667), number(tt, 0, "ProbF"), 0.00005);
    try t.expect(!h.cx.diags.hasErrors());
}
test "MIXED016 NOINFO NOTEST noniterative objects warn only when unproduced" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a, 1);
    try h.output("ods output ModelInfo=mi Dimensions=dim NObs=n Tests3=t ConvergenceStatus=cs IterHistory=ih SolutionF=sf CovB=cb ClassLevels=cl CovParms=cp;");
    const out = try h.run("proc mixed data=heights noinfo;class Family Gender;model Height=Gender Family Family*Gender /notest;run;");
    try h.capture.finish(h.cx.lib, h.cx.diags);
    for ([_][]const u8{ "mi", "dim", "n", "t", "cs", "ih", "sf", "cb" }) |name| try t.expect(h.cx.lib.find(name) == null);
    _ = try dataset(h, "cl");
    _ = try dataset(h, "cp");
    try t.expect(std.mem.indexOf(u8, out, "Model Information") == null);
    try t.expect(std.mem.indexOf(u8, out, "Type 3 Tests") == null);
    try t.expect(std.mem.indexOf(u8, out, "Class Level Information") != null);
    var warnings: usize = 0;
    for (h.cx.diags.list.items) |entry| {
        if (entry.severity == .warning) warnings += 1;
    }
    try t.expectEqual(@as(usize, 8), warnings);
    try t.expect(!h.cx.diags.hasErrors());
    const bad = try Harness.init(a, 1);
    diag.resetGap();
    defer diag.resetGap();
    try t.expectError(error.ParseError, bad.run("proc mixed data=heights noprint;model Height= /notest;run;"));
    try t.expect(!diag.gapHit());
}
test "MIXED016 BY metadata and destination selection retain complete typed cells" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a, 2);
    try h.output("ods output CovParms=cp IterHistory=ih Tests3=tt;");
    h.listing.trace = h.cx.diags;
    _ = try h.listing.parse(a, h.cx.diags, try lex.tokenize(a, "ods listing select CovParms;", h.cx.diags));
    const out = try h.run("proc mixed data=heights;by batch;class Family Gender;model Height=Gender;random Family Family*Gender;run;");
    try h.capture.finish(h.cx.lib, h.cx.diags);
    try t.expect(std.mem.indexOf(u8, out, "Model Information") == null);
    try t.expect(std.mem.indexOf(u8, out, "Covariance Parameter Estimates") != null);
    try t.expect(std.mem.indexOf(u8, out, "Type 3 Tests") == null);
    const cp = try dataset(h, "cp");
    try t.expectEqual(@as(usize, 6), cp.rowCount());
    try t.expectEqualStrings("batch", cp.columns.items[0].name);
    try t.expectEqualStrings("Run Batch", cp.columns.items[0].label.?);
    try t.expectEqualStrings("3.", cp.columns.items[0].format.?);
    try t.expect(cp.columns.items[0].informat == null);
    for (0..6) |i| {
        try t.expectEqual(@as(f64, if (i < 3) 1 else 2), number(cp, i, "batch"));
        try t.expectApproxEqAbs(number(cp, i % 3, "Estimate"), number(cp, i, "Estimate"), 1e-12);
    }
    try t.expectEqual(@as(usize, 14), (try dataset(h, "ih")).rowCount());
    try t.expectEqual(@as(usize, 2), (try dataset(h, "tt")).rowCount());
    var seen: [2]bool = .{ false, false };
    for (h.cx.diags.list.items) |entry| {
        if (std.mem.indexOf(u8, entry.message, "Mixed.ByGroup1.CovParms") != null) seen[0] = true;
        if (std.mem.indexOf(u8, entry.message, "Mixed.ByGroup2.CovParms") != null) seen[1] = true;
    }
    try t.expect(seen[0] and seen[1]);
}

test "MIXED016 parameter search full numeric schema and unavailable cells" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a, 1);
    const ds = try a.create(Dataset);
    ds.* = .init(a, "scalar");
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 0, 2, 2, 4 }) |v| try ds.appendRow(&.{.{ .num = v }});
    try h.cx.lib.put("scalar", ds);
    try h.output("ods output ParmSearch=ps;");
    _ = try h.run("proc mixed data=scalar noinfo;model y= /notest;parms (1,4);run;");
    try h.capture.finish(h.cx.lib, h.cx.diags);
    const ps = try dataset(h, "ps");
    try columns(ps, &.{ "CovP1", "Var", "ResLogLike", "M2ResLogLike2" }, &.{ true, true, true, true }, &.{ "12.4", "12.4", "12.4", "12.4" });
    const objective = 3 * (1 + @log(2 * std.math.pi) + @log(@as(f64, 8.0 / 3.0))) + @log(@as(f64, 4));
    try t.expectEqual(@as(usize, 2), ps.rowCount());
    for ([_]f64{ 1, 4 }, 0..) |v, i| {
        try t.expectEqual(v, number(ps, i, "CovP1"));
        try t.expectApproxEqAbs(@as(f64, 8.0 / 3.0), number(ps, i, "Var"), 1e-12);
        try t.expectApproxEqAbs(objective, number(ps, i, "M2ResLogLike2"), 1e-12);
        try t.expectApproxEqAbs(-objective / 2, number(ps, i, "ResLogLike"), 1e-12);
    }
    try h.output("ods output ParmSearch=raw;");
    _ = try h.run("proc mixed data=scalar noinfo;model y= /notest;parms (0,1) /noiter;run;");
    try h.capture.finish(h.cx.lib, h.cx.diags);
    const raw = try dataset(h, "raw");
    try columns(raw, &.{ "CovP1", "ResLogLike", "M2ResLogLike2" }, &.{ true, true, true }, &.{ "12.4", "12.4", "12.4" });
    try t.expectEqual(@as(f64, 0), number(raw, 0, "CovP1"));
    try t.expect(std.math.isNan(number(raw, 0, "ResLogLike")));
    try t.expect(std.math.isNan(number(raw, 0, "M2ResLogLike2")));
    try t.expectApproxEqAbs(3 * @log(2 * std.math.pi) + @log(@as(f64, 4)) + 8, number(raw, 1, "M2ResLogLike2"), 1e-12);
    try t.expect(!h.cx.diags.hasErrors());
}

test "MIXED016 typed PARMS likelihood ratio preserves df statistic and probability" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const h = try Harness.init(a, 1);
    try h.output("ods output ParmSearch=ps FitStatistics=fs LRT=lr;");
    _ = try h.run("proc mixed data=heights;class Family Gender;model Height=Gender;random Family Family*Gender;parms (1) (1) (1);run;");
    try h.capture.finish(h.cx.lib, h.cx.diags);
    const lr = try dataset(h, "lr");
    try columns(lr, &.{ "DF", "ChiSquare", "ProbChiSq" }, &.{ true, true, true }, &.{ "8.", "8.2", "PVALUE6.4" });
    try t.expectEqual(@as(usize, 1), lr.rowCount());
    try t.expectEqual(@as(f64, 2), number(lr, 0, "DF"));
    const statistic = number(try dataset(h, "ps"), 0, "M2ResLogLike2") - number(try dataset(h, "fs"), 0, "Value");
    try t.expectApproxEqAbs(statistic, number(lr, 0, "ChiSquare"), 1e-12);
    try t.expectApproxEqAbs(@exp(-statistic / 2), number(lr, 0, "ProbChiSq"), 1e-12);
}
