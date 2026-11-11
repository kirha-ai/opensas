//! EXACT statement syntax (SAS/STAT pp.81–90). Parsing preserves requests;
//! execution must dispatch each family to its documented reference-set engine.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const format = @import("../format.zig");
pub const Family = enum { agree, barnard, binomial, chisq, comor, eqor, fisher, jt, kappa, kentb, lrchi, mcnem, measures, mhchi, oddsratio, pchi, pcorr, relrisk, riskdiff, scorr, smdcr, smdrc, stutc, symmetry, trend, wtkappa };
pub const Families = std.EnumSet(Family);
pub const Method = @import("freq_exact_unconditional.zig").Method;
pub const Column = enum { first, second, both };
pub const RiskOptions = struct { column: ?Column = null, method: Method = .score };
pub const ProbabilityFormat = union(enum) { default, exact, named: []const u8 };
pub const Options = struct {
    families: Families = Families.initEmpty(),
    riskdiff: RiskOptions = .{},
    relrisk: RiskOptions = .{},
    mc: bool = false,
    point: bool = false,
    midp: bool = false,
    alpha: f64 = 0.01,
    samples: u64 = 10_000,
    seed: i64 = 0,
    max_seconds: ?f64 = null,
    pformat: ProbabilityFormat = .default,

    pub fn expanded(self: Options, one_way: bool) Families {
        var f = self.families;
        if (f.contains(.chisq)) {
            f.insert(.pchi);
            if (!one_way) {
                f.insert(.lrchi);
                f.insert(.mhchi);
            }
        }
        if (f.contains(.agree)) {
            f.insert(.mcnem);
            f.insert(.kappa);
            f.insert(.wtkappa);
        }
        if (f.contains(.measures)) {
            f.insert(.pcorr);
            f.insert(.scorr);
            f.insert(.oddsratio);
        }
        f.remove(.chisq);
        f.remove(.agree);
        f.remove(.measures);
        return f;
    }
};
pub fn supportsMonteCarlo(f: Family, rows: usize, cols: usize) bool {
    return switch (f) {
        .binomial, .barnard, .comor, .eqor, .mcnem, .oddsratio, .relrisk, .riskdiff => false,
        // SAS parse-options.sas: 2x2 Fisher stays exact even with MC/N/SEED.
        .fisher => rows != 2 or cols != 2,
        else => true,
    };
}
pub fn supportsPoint(f: Family) bool {
    return switch (f) {
        .barnard, .eqor, .oddsratio, .relrisk, .riskdiff => false,
        else => true,
    };
}
fn kw(t: lex.Token, name: []const u8) bool {
    return t.tag == .name and std.ascii.eqlIgnoreCase(t.text, name);
}
fn family(t: lex.Token) ?Family {
    if (t.tag != .name) return null;
    inline for (std.meta.fields(Family)) |field| if (std.ascii.eqlIgnoreCase(t.text, field.name)) return @enumFromInt(field.value);
    const aliases = .{ .{ "bin", Family.binomial }, .{ "zelen", Family.eqor }, .{ "taub", Family.kentb }, .{ "or", Family.oddsratio }, .{ "tauc", Family.stutc }, .{ "bowker", Family.symmetry }, .{ "wtkap", Family.wtkappa } };
    inline for (aliases) |alias| if (std.ascii.eqlIgnoreCase(t.text, alias[0])) return alias[1];
    return null;
}
const Reader = struct {
    a: std.mem.Allocator,
    t: []const lex.Token,
    i: usize,
    d: *diag.Diagnostics,
    fn at(self: Reader, tag: lex.Tag) bool {
        return self.i < self.t.len and self.t[self.i].tag == tag;
    }
    fn fail(self: *Reader, comptime message: []const u8) diag.Error {
        return self.d.fail(error.ParseError, if (self.i < self.t.len) self.t[self.i].line else 0, "PROC FREQ EXACT: " ++ message, .{});
    }
    fn expect(self: *Reader, tag: lex.Tag) diag.Error!void {
        if (!self.at(tag)) return self.fail("malformed option");
        self.i += 1;
    }
    fn number(self: *Reader) diag.Error!f64 {
        var sign: f64 = 1;
        if (self.at(.minus)) {
            sign = -1;
            self.i += 1;
        } else if (self.at(.plus)) self.i += 1;
        if (!self.at(.number)) return self.fail("expected numeric value");
        const n = std.fmt.parseFloat(f64, self.t[self.i].text) catch return self.fail("invalid number");
        self.i += 1;
        if (!std.math.isFinite(n)) return self.fail("numeric value must be finite");
        return sign * n;
    }
    fn riskOptions(self: *Reader, opts: *RiskOptions) diag.Error!void {
        try self.expect(.lparen);
        while (!self.at(.rparen)) {
            if (!self.at(.name)) return self.fail("expected COLUMN= or METHOD=");
            const option = self.t[self.i];
            self.i += 1;
            try self.expect(.eq);
            if (kw(option, "column")) {
                if (self.at(.name) and kw(self.t[self.i], "both")) {
                    opts.column = .both;
                    self.i += 1;
                } else {
                    const n = try self.number();
                    opts.column = if (n == 1) .first else if (n == 2) .second else return self.fail("COLUMN must be 1, 2, or BOTH");
                }
            } else if (kw(option, "method")) {
                if (!self.at(.name)) return self.fail("expected exact interval method");
                const method = self.t[self.i];
                self.i += 1;
                opts.method = if (kw(method, "noscore")) .noscore else if (kw(method, "score")) .score else if (kw(method, "score2")) .score2 else return self.fail("unknown exact interval method");
            } else return self.fail("unknown exact risk option");
        }
        self.i += 1;
    }
    fn probabilityFormat(self: *Reader) diag.Error!ProbabilityFormat {
        if (self.at(.name) and kw(self.t[self.i], "exact")) {
            self.i += 1;
            return .exact;
        }
        if (!self.at(.name) and !self.at(.number)) return self.fail("expected numeric format");
        var text = self.t[self.i].text;
        self.i += 1;
        if (self.at(.dot)) {
            text = try std.fmt.allocPrint(self.a, "{s}.", .{text});
            self.i += 1;
        } else if (self.at(.number) and std.mem.startsWith(u8, self.t[self.i].text, ".")) {
            text = try std.fmt.allocPrint(self.a, "{s}{s}", .{ text, self.t[self.i].text });
            self.i += 1;
        }
        const spec = format.parseSpec(text);
        if (spec.w > 24 or spec.is_char) return self.fail("PFORMAT width must not exceed 24");
        return .{ .named = text };
    }
};

/// Cursor begins after EXACT, returns after its semicolon. Empty EXACT warns
/// and requests nothing (SAS parse-options.sas); unknown names are user errors.
pub fn statement(a: std.mem.Allocator, tokens: []const lex.Token, cursor: *usize, d: *diag.Diagnostics) diag.Error!Options {
    var r = Reader{ .a = a, .t = tokens, .i = cursor.*, .d = d };
    var out = Options{};
    while (!r.at(.semicolon) and !r.at(.slash)) {
        if (r.i >= tokens.len) return r.fail("unterminated statement");
        const f = family(tokens[r.i]) orelse return r.fail("unknown exact statistic");
        r.i += 1;
        out.families.insert(f);
        if (r.at(.lparen)) {
            if (f == .riskdiff) try r.riskOptions(&out.riskdiff) else if (f == .relrisk) try r.riskOptions(&out.relrisk) else return r.fail("this statistic has no suboptions");
        }
    }
    if (r.at(.slash)) {
        r.i += 1;
        while (!r.at(.semicolon)) {
            if (!r.at(.name)) return r.fail("expected computation option");
            const option = tokens[r.i];
            r.i += 1;
            if (kw(option, "mc")) {
                out.mc = true;
                continue;
            }
            if (kw(option, "point")) {
                out.point = true;
                continue;
            }
            if (kw(option, "midp")) {
                out.midp = true;
                continue;
            }
            try r.expect(.eq);
            if (kw(option, "pformat")) {
                out.pformat = try r.probabilityFormat();
                continue;
            }
            const n = try r.number();
            if (kw(option, "alpha")) {
                if (n <= 0 or n >= 1) return r.fail("ALPHA must be between 0 and 1");
                out.alpha = n;
                out.mc = true;
            } else if (kw(option, "maxtime")) {
                if (n <= 0) return r.fail("MAXTIME must be positive");
                out.max_seconds = n;
            } else if (kw(option, "n")) {
                if (n < 1 or n != @floor(n) or n >= 0x1p64) return r.fail("N must be a positive integer");
                out.samples = @intFromFloat(n);
                out.mc = true;
            } else if (kw(option, "seed")) {
                if (n != @floor(n) or n < -0x1p63 or n >= 0x1p63) return r.fail("SEED must be an integer");
                out.seed = @intFromFloat(n);
                out.mc = true;
            } else return r.fail("unknown computation option");
        }
    }
    if (out.mc and out.point) return r.fail("POINT is not available with MC");
    if (out.mc and out.midp) return r.fail("MIDP is not available with MC");
    try r.expect(.semicolon);
    if (out.families.count() == 0) try d.report(.warning, 0, "No statistic options are specified in the EXACT statement.", .{});
    cursor.* = r.i;
    return out;
}

test "exact parser aliases interval methods controls and empty statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const tokens = try lex.tokenize(a, "bin zelen taub tauc bowker wtkap or riskdiff(column=both method=noscore) relrisk(column=2 method=score2) / n=25 seed=-1 alpha=.1 maxtime=.2 pformat=best12.;", &d);
    var i: usize = 0;
    const o = try statement(a, tokens, &i, &d);
    try std.testing.expect(o.families.contains(.eqor) and o.families.contains(.symmetry));
    try std.testing.expectEqual(Method.noscore, o.riskdiff.method);
    try std.testing.expectEqual(Column.both, o.riskdiff.column.?);
    try std.testing.expectEqual(Method.score2, o.relrisk.method);
    try std.testing.expectEqual(@as(i64, -1), o.seed);
    try std.testing.expect(o.mc);
    try std.testing.expectEqualStrings("best12.", o.pformat.named);
    const empty = try lex.tokenize(a, ";", &d);
    i = 0;
    _ = try statement(a, empty, &i, &d);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expect(!d.hasErrors());
}
test "exact parser rejects MC conflicts and invalid controls through diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "fisher / mc point;", "fisher / n=1 midp;", "fisher / n=1.5;", "fisher / alpha=1;", "fisher / seed=1.5;", "or / maxtime=0;", "riskdiff(method=bad);", "fisher / pformat=best25.;", "fisher / typo=1;", "typo;" }) |src| {
        var d = diag.Diagnostics.init(a);
        const tokens = try lex.tokenize(a, src, &d);
        var i: usize = 0;
        try std.testing.expectError(error.ParseError, statement(a, tokens, &i, &d));
        try std.testing.expect(d.hasErrors());
    }
}
