//! STAT-REG-019 — "Computer Resources in Regression Analysis" (S154 p. 8650).
//! The section makes no measurable promise opensas can reproduce (time and
//! memory figures are proportionality statements), so these checks pin what is
//! observable: the optional R/CLM/CLI and INFLUENCE requests take effect without
//! changing the fit, an interactive DELETE refit equals the direct smaller
//! model, and the TYPE=SSCP (CORR/COV) summary-input mode the section points
//! to fails loudly instead of fitting summary rows as observations.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const reg = @import("reg.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Library = @import("../exec.zig").Library;

// Example 105.4 insurance data (published SAS sample data).
const insurance = [_][3]f64{
    .{ 17, 151, 0 }, .{ 26, 92, 0 },  .{ 21, 175, 0 }, .{ 30, 31, 0 },  .{ 22, 104, 0 },
    .{ 0, 277, 0 },  .{ 12, 210, 0 }, .{ 19, 120, 0 }, .{ 4, 290, 0 },  .{ 16, 238, 0 },
    .{ 28, 164, 1 }, .{ 15, 272, 1 }, .{ 11, 295, 1 }, .{ 38, 68, 1 },  .{ 31, 85, 1 },
    .{ 21, 224, 1 }, .{ 20, 166, 1 }, .{ 13, 305, 1 }, .{ 30, 124, 1 }, .{ 14, 246, 1 },
};

fn insuranceSet(a: std.mem.Allocator) !*Dataset {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "insurance");
    for ([_][]const u8{ "time", "size", "type", "sizetype" }) |n| _ = try ds.addColumn(n, .num);
    for (insurance) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .num = r[1] }, .{ .num = r[2] }, .{ .num = r[1] * r[2] } });
    return ds;
}

fn listing(cx: proc.ProcCtx, source: []const u8) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try reg.run(cx, &out, try lex.tokenize(cx.arena, source, cx.diags));
    return out.items;
}

/// The Parameter Estimates block of the first model page.
fn estimates(text: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, text, "Parameter Estimates").?;
    const rest = text[start..];
    const stop = std.mem.indexOf(u8, rest, "\nThe REG Procedure") orelse rest.len;
    return rest[0..stop];
}

test "STAT-REG-019 optional R CLM CLI INFLUENCE requests take effect and leave the fit unchanged" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    try lib.put("insurance", try insuranceSet(a));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const plain = try listing(cx, "proc reg data=insurance; model time = size type sizetype; run;");
    const intervals = try listing(cx, "proc reg data=insurance; model time = size type sizetype / r clm cli; run;");
    const influence = try listing(cx, "proc reg data=insurance; model time = size type sizetype / influence; run;");
    // Reference values: SAS 9.4 listing of Example 105.4, page 1.
    for ([_][]const u8{ "33.83837", "2.44065", "-0.10153", "0.01305", "8.13125", "3.65405", "-0.00041714", "0.01833", "1504.41904", "176.38096" }) |want| {
        try std.testing.expect(std.mem.indexOf(u8, plain, want) != null);
    }
    // Requests take effect: the extra nk^2 work produces its tables.
    try std.testing.expect(std.mem.indexOf(u8, plain, "Output Statistics") == null);
    try std.testing.expect(std.mem.indexOf(u8, intervals, "95% CL Mean") != null);
    try std.testing.expect(std.mem.indexOf(u8, influence, "DFFITS") != null);
    // Results remain equivalent: the fit tables are byte-identical.
    const anova_plain = plain[0..std.mem.indexOf(u8, plain, "Parameter Estimates").?];
    for ([_][]const u8{ intervals, influence }) |other| {
        try std.testing.expectEqualStrings(estimates(plain), estimates(other));
        try std.testing.expectEqualStrings(anova_plain, other[0..anova_plain.len]);
    }
    // Hand check of the first residual: 17 - (33.83837 - 0.10153*151) = -1.5073.
    try std.testing.expect(std.mem.indexOf(u8, intervals, "-1.507") != null);
    // R/CLM/CLI combined with INFLUENCE stays a loud gap (STAT-REG-012).
    defer diag.resetGap();
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, reg.run(cx, &out, try lex.tokenize(a, "proc reg data=insurance; model time = size / r influence; run;", &d)));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}

test "STAT-REG-019 interactive DELETE refit equals the direct smaller model" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    try lib.put("insurance", try insuranceSet(a));
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const direct = try listing(cx, "proc reg data=insurance; model time = size type; run;");
    var session: reg.Session = .{ .spec = try reg.parse(cx, try lex.tokenize(a, "proc reg data=insurance; model time = size type sizetype; run;", &d)) };
    var out: std.ArrayList(u8) = .empty;
    try reg.execute(cx, &out, session.spec);
    const first_len = out.items.len;
    try std.testing.expect(try session.continuation(cx, &out, try lex.tokenize(a, "delete sizetype; print; run;", &d)));
    const refit = out.items[first_len..];
    try std.testing.expect(std.mem.indexOf(u8, refit, "Model: MODEL1.1") != null);
    try std.testing.expectEqualStrings(estimates(direct), estimates(refit));
    // SAS 9.4 reference, page 2.
    for ([_][]const u8{ "33.87407", "1.81386", "-0.10174", "0.00889", "8.05547", "1.45911", "1504.41333", "176.38667" }) |want| {
        try std.testing.expect(std.mem.indexOf(u8, refit, want) != null);
    }
}

fn expectGap(cx: proc.ProcCtx, d: *diag.Diagnostics, source: []const u8, needle: []const u8) !void {
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, reg.run(cx, &out, try lex.tokenize(cx.arena, source, d)));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, d.list.items[d.list.items.len - 1].message, needle) != null);
    diag.resetGap();
}

test "STAT-REG-019 TYPE=SSCP CORR COV summary input and OUTSSCP= are loud gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var lib = Library.init(a);
    defer diag.resetGap();
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "SSCP", "CORR", "COV", "MYTYPE" }) |ty| {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "summary");
        for ([_][]const u8{ "x", "y" }) |n| _ = try ds.addColumn(n, .num);
        try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
        try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 3 } });
        try ds.appendRow(&.{ .{ .num = 3 }, .{ .num = 5 } });
        ds.ds_type = ty;
        try lib.put("summary", ds);
        try expectGap(cx, &d, "proc reg data=summary; model y=x; run;", try std.fmt.allocPrint(a, "TYPE={s} input data sets are not implemented", .{ty}));
    }
    // The same rows without a TYPE= attribute are ordinary observations.
    lib.find("summary").?.ds_type = null;
    _ = try listing(cx, "proc reg data=summary; model y=x; run;");
    try expectGap(cx, &d, "proc reg data=summary(type=sscp); model y=x; run;", "summary TYPE= input is not implemented");
    try expectGap(cx, &d, "proc reg data=summary outsscp=s; model y=x; run;", "outsscp");
}
