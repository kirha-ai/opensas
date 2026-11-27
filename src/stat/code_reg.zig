//! REG adapter for the shared CODE emitter; fitted coefficients are the source.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const code = @import("code.zig");
pub fn publish(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: anytype, model: anytype, fit: anytype) diag.Error!void {
    const options = spec.code orelse return;
    if (fit.rank != fit.coefficients.len) return proc.failGap(cx.diags, options.line, "PROC REG CODE: rank-deficient continuous scoring is not implemented", .{});
    const terms = try cx.arena.alloc(code.Term, model.regressors.len);
    for (model.regressors, terms, 0..) |ci, *term, j| {
        const name = spec.ds.columns.items[ci].name;
        term.* = .{ .coefficient = fit.coefficients[j + @as(usize, if (model.intercept) 1 else 0)], .factors = try cx.arena.dupe(code.Factor, &.{.{ .numeric = name }}), .label = name };
    }
    try code.publish(cx, out, .{ .procedure = "REG", .response = spec.ds.columns.items[model.dependent].name, .intercept = if (model.intercept) fit.coefficients[0] else 0, .terms = terms, .mean = fit.y_mean }, options);
}

test "COMMON020 actual REG CODE fileref producer and interactive PRINT never replays output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "sample");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    for ([_][2]f64{ .{ 1, 5 }, .{ 2, 8 }, .{ 3, 11 }, .{ 4, 14 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("sample", &ds);
    var d = diag.Diagnostics.init(a);
    const Resolver = struct {
        fn resolve(name: []const u8) ?[]const u8 {
            return if (std.ascii.eqlIgnoreCase(name, "regtest")) ".zig-cache/common020-reg-generated.sas" else null;
        }
    };
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d, .resolve_fileref = &Resolver.resolve };
    var out: std.ArrayList(u8) = .empty;
    defer std.Io.Dir.cwd().deleteFile(std.testing.io, ".zig-cache/common020-reg-generated.sas") catch {};
    const toks = try @import("../lexer.zig").tokenize(a, "proc reg data=sample noprint;model y=x;code file=regtest;run;", &d);
    const spec = try @import("reg_parse.zig").parse(cx, toks);
    try @import("reg.zig").execute(cx, &out, spec);
    const bytes = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, ".zig-cache/common020-reg-generated.sas", a, .limited(65536));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "label P_y") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "nmiss(x)") != null);
    try std.testing.expect(@import("../io.zig").writeFileRaw(".zig-cache/common020-reg-generated.sas", "sentinel"));
    var session = @import("reg.zig").Session{ .spec = spec };
    try std.testing.expect(try session.continuation(cx, &out, try @import("../lexer.zig").tokenize(a, "print;run;", &d)));
    const retained = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, ".zig-cache/common020-reg-generated.sas", a, .limited(65536));
    try std.testing.expectEqualStrings("sentinel", retained);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, session.continuation(cx, &out, try @import("../lexer.zig").tokenize(a, "code file=regtest;", &d)));
    try std.testing.expect(diag.gapHit());
}
