//! FREQ statistical options only. The table parser owns TABLES expansion and
//! calls consumeTableOption at its current token; this module never dispatches
//! a PROC or reads a dataset. Kept independent until GAP-freq-table-complete.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const kernels = @import("freq_tests.zig");
pub const ExpectedSource = union(enum) { equal, proportions: []const f64, frequencies: []const f64, proportion_dataset: []const u8, frequency_dataset: []const u8 };
pub const Warn = struct { display: bool = true, log: bool = true, output: bool = false };
pub const Tests = packed struct { gamma: bool = false, tau_b: bool = false, tau_c: bool = false, somers_cr: bool = false, somers_rc: bool = false, pearson: bool = false, spearman: bool = false, polychoric: bool = false };
pub const Options = struct {
    chisq: bool = false,
    lrchi: bool = false,
    measures: bool = false,
    cl: bool = false,
    plcorr: bool = false,
    alpha: f64 = 0.05,
    df: ?f64 = null,
    expected: ExpectedSource = .equal,
    warn: Warn = .{},
    polychoric: kernels.PolychoricOptions = .{},
};
fn kw(t: lex.Token, s: []const u8) bool {
    return t.tag == .name and std.ascii.eqlIgnoreCase(t.text, s);
}
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
const Reader = struct {
    a: std.mem.Allocator,
    t: []const lex.Token,
    i: usize,
    d: *diag.Diagnostics,
    fn fail(self: *Reader, comptime message: []const u8) diag.Error {
        return self.d.fail(error.ParseError, if (self.i < self.t.len) self.t[self.i].line else 0, "PROC FREQ: " ++ message, .{});
    }
    fn expect(self: *Reader, tag: lex.Tag) diag.Error!void {
        if (!at(self.t, self.i, tag)) return self.fail("malformed statistical option");
        self.i += 1;
    }
    fn number(self: *Reader) diag.Error!f64 {
        var sign: f64 = 1;
        if (at(self.t, self.i, .minus)) {
            sign = -1;
            self.i += 1;
        } else if (at(self.t, self.i, .plus)) self.i += 1;
        if (!at(self.t, self.i, .number)) return self.fail("expected a numeric option value");
        const n = std.fmt.parseFloat(f64, self.t[self.i].text) catch return self.fail("invalid numeric option value");
        self.i += 1;
        if (!std.math.isFinite(n)) return self.fail("option value must be finite");
        return sign * n;
    }
    fn expected(self: *Reader, probabilities: bool) diag.Error!ExpectedSource {
        try self.expect(.eq);
        if (at(self.t, self.i, .lparen)) {
            self.i += 1;
            var values: std.ArrayList(f64) = .empty;
            while (!at(self.t, self.i, .rparen)) {
                const n = try self.number();
                if (n <= 0) return self.fail("TESTP/TESTF values must be positive");
                try values.append(self.a, n);
                if (at(self.t, self.i, .comma)) self.i += 1;
                if (self.i >= self.t.len) return self.fail("unterminated TESTP/TESTF list");
            }
            self.i += 1;
            if (values.items.len == 0) return self.fail("empty TESTP/TESTF list");
            return if (probabilities) .{ .proportions = try values.toOwnedSlice(self.a) } else .{ .frequencies = try values.toOwnedSlice(self.a) };
        }
        if (!at(self.t, self.i, .name)) return self.fail("expected TESTP/TESTF dataset name");
        var name = self.t[self.i].text;
        self.i += 1;
        if (at(self.t, self.i, .dot)) {
            self.i += 1;
            if (!at(self.t, self.i, .name)) return self.fail("expected member name after library");
            name = try std.fmt.allocPrint(self.a, "{s}.{s}", .{ name, self.t[self.i].text });
            self.i += 1;
        }
        return if (probabilities) .{ .proportion_dataset = name } else .{ .frequency_dataset = name };
    }
    fn setExpected(self: *Reader, opts: *Options, probabilities: bool) diag.Error!void {
        const conflict = switch (opts.expected) {
            .equal => false,
            .proportions, .proportion_dataset => !probabilities,
            .frequencies, .frequency_dataset => probabilities,
        };
        if (conflict) return self.fail("You cannot specify both TESTP= and TESTF= in the same TABLES statement.");
        const incoming = try self.expected(probabilities);
        switch (incoming) {
            .proportions, .frequencies => |values| {
                // Lists imply CHISQ; a dataset reference alone does not.
                opts.chisq = true;
                switch (opts.expected) {
                    .proportion_dataset, .frequency_dataset => return, // dataset wins in either order
                    .proportions, .frequencies => |previous| {
                        const combined = try self.a.alloc(f64, previous.len + values.len);
                        @memcpy(combined[0..previous.len], previous);
                        @memcpy(combined[previous.len..], values);
                        opts.expected = if (probabilities) .{ .proportions = combined } else .{ .frequencies = combined };
                        return;
                    },
                    .equal => {},
                }
            },
            .proportion_dataset, .frequency_dataset => {
                switch (opts.expected) {
                    .proportion_dataset, .frequency_dataset => {
                        try self.d.report(.warning, 0, "Ignoring second data set reference.", .{});
                        return;
                    },
                    else => {},
                }
            },
            .equal => unreachable,
        }
        opts.expected = incoming;
    }
    fn warning(self: *Reader, w: *Warn) diag.Error!void {
        try self.expect(.eq);
        const paren = at(self.t, self.i, .lparen);
        if (paren) self.i += 1;
        while (true) {
            if (self.i >= self.t.len) return self.fail("missing WARN value");
            const token = self.t[self.i];
            self.i += 1;
            if (kw(token, "none")) {
                w.display = false;
                w.log = false;
            } else if (kw(token, "noprint")) w.display = false else if (kw(token, "nolog")) w.log = false else if (kw(token, "output")) w.output = true else return self.fail("unknown WARN value");
            if (!paren) break;
            if (at(self.t, self.i, .comma)) self.i += 1;
            if (at(self.t, self.i, .rparen)) {
                self.i += 1;
                break;
            }
        }
    }
};
/// On success consumes through the last option token; returns false unchanged
/// for table-layer options. `i` always points to the NEXT unconsumed token.
pub fn consumeTableOption(a: std.mem.Allocator, t: []const lex.Token, i: *usize, opts: *Options, d: *diag.Diagnostics) diag.Error!bool {
    if (i.* >= t.len) return false;
    var r = Reader{ .a = a, .t = t, .i = i.*, .d = d };
    const token = t[r.i];
    r.i += 1;
    if (kw(token, "chisq")) {
        opts.chisq = true;
        if (at(t, r.i, .lparen)) {
            r.i += 1;
            while (!at(t, r.i, .rparen)) {
                if (r.i >= t.len) return r.fail("unterminated CHISQ options");
                const sub = t[r.i];
                r.i += 1;
                if (kw(sub, "lrchi")) opts.lrchi = true else if (kw(sub, "df")) {
                    try r.expect(.eq);
                    opts.df = try r.number();
                    if (opts.df.? == 0) return r.fail("DF must not be zero");
                } else if (kw(sub, "testp") or kw(sub, "testf")) try r.setExpected(opts, kw(sub, "testp")) else if (kw(sub, "warn")) try r.warning(&opts.warn) else return r.fail("unknown CHISQ option");
            }
            r.i += 1;
        }
    } else if (kw(token, "testp") or kw(token, "testf")) {
        try r.setExpected(opts, kw(token, "testp"));
    } else if (kw(token, "measures")) {
        opts.measures = true;
        if (at(t, r.i, .lparen)) {
            r.i += 1;
            if (r.i >= t.len or !kw(t[r.i], "cl")) return r.fail("MEASURES accepts only CL");
            opts.cl = true;
            r.i += 1;
            try r.expect(.rparen);
        }
    } else if (kw(token, "cl")) {
        opts.cl = true;
        opts.measures = true;
    } else if (kw(token, "alpha")) {
        try r.expect(.eq);
        opts.alpha = try r.number();
        if (!(opts.alpha > 0 and opts.alpha < 1)) return r.fail("ALPHA must be between zero and one");
        opts.polychoric.alpha = opts.alpha;
    } else if (kw(token, "nowarn")) opts.warn.log = false else if (kw(token, "plcorr") or kw(token, "polychoric")) {
        opts.plcorr = true;
        opts.measures = true;
        if (at(t, r.i, .lparen)) {
            r.i += 1;
            while (!at(t, r.i, .rparen)) {
                if (r.i >= t.len) return r.fail("unterminated PLCORR options");
                const sub = t[r.i];
                r.i += 1;
                if (kw(sub, "adjust")) opts.polychoric.adjust = true else if (kw(sub, "converge")) {
                    try r.expect(.eq);
                    opts.polychoric.converge = try r.number();
                    if (opts.polychoric.converge <= 0) return r.fail("CONVERGE must be positive");
                } else if (kw(sub, "maxiter")) {
                    try r.expect(.eq);
                    const n = try r.number();
                    if (n < 1 or @floor(n) != n or n >= 1e9) return r.fail("MAXITER must be a positive integer");
                    opts.polychoric.maxiter = @intFromFloat(n);
                } else return r.fail("unknown PLCORR option");
            }
            r.i += 1;
        }
    } else return false;
    i.* = r.i;
    return true;
}
/// The parent passes the tokens AFTER TEST and BEFORE its semicolon.
pub fn parseTests(tokens: []const lex.Token, d: *diag.Diagnostics) diag.Error!Tests {
    var out: Tests = .{};
    if (tokens.len == 0) {
        try d.report(.warning, 0, "No statistic options are specified in the TEST statement.", .{});
        return out;
    }
    for (tokens) |t| {
        if (kw(t, "gamma")) out.gamma = true else if (kw(t, "kentb") or kw(t, "taub")) out.tau_b = true else if (kw(t, "stutc") or kw(t, "tauc")) out.tau_c = true else if (kw(t, "smdcr")) out.somers_cr = true else if (kw(t, "smdrc")) out.somers_rc = true else if (kw(t, "pcorr")) out.pearson = true else if (kw(t, "scorr")) out.spearman = true else if (kw(t, "plcorr")) out.polychoric = true else if (kw(t, "measures")) {
            const pl = out.polychoric;
            out = .{ .gamma = true, .tau_b = true, .tau_c = true, .somers_cr = true, .somers_rc = true, .pearson = true, .spearman = true, .polychoric = pl };
        } else {
            if (kw(t, "agree") or kw(t, "kappa") or kw(t, "wtkappa") or kw(t, "wtkap")) diag.markGap();
            return d.fail(error.ParseError, t.line, "PROC FREQ: TEST {s} is not supported", .{t.text});
        }
    }
    return out;
}
/// SAS only implies TABLES options when there is exactly one TABLES statement.
pub fn implyTests(o: *Options, t: Tests, tables_statement_count: usize) void {
    if (tables_statement_count != 1) return;
    if (t.gamma or t.tau_b or t.tau_c or t.somers_cr or t.somers_rc or t.pearson or t.spearman or t.polychoric) o.measures = true;
    if (t.polychoric) o.plcorr = true;
}

test "FEAT-freq-tests nested options and aliases independent of table parser" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const tokens = try lex.tokenize(a, "chisq(lrchi df=-1 testp=(20,30 50) warn=(output noprint)) measures(cl) plcorr(adjust converge=.00001 maxiter=70) alpha=.1;", &d);
    var i: usize = 0;
    var o: Options = .{};
    while (!at(tokens, i, .semicolon)) try std.testing.expect(try consumeTableOption(a, tokens, &i, &o, &d));
    try std.testing.expect(o.chisq and o.lrchi and o.measures and o.cl and o.plcorr);
    try std.testing.expectEqual(@as(f64, -1), o.df.?);
    try std.testing.expectEqualSlices(f64, &.{ 20, 30, 50 }, o.expected.proportions);
    try std.testing.expect(o.warn.output and !o.warn.display and o.warn.log);
    try std.testing.expectEqual(@as(usize, 70), o.polychoric.maxiter);
    const tt = try lex.tokenize(a, "taub tauc smdcr smdrc pcorr scorr gamma plcorr", &d);
    const tests = try parseTests(tt[0 .. tt.len - 1], &d);
    try std.testing.expect(tests.tau_b and tests.tau_c and tests.polychoric);
    var implied: Options = .{};
    implyTests(&implied, tests, 2);
    try std.testing.expect(!implied.measures);
    implyTests(&implied, tests, 1);
    try std.testing.expect(implied.measures and implied.plcorr);
}

/// Procedure-wide TEST state: one statement is allowed, including an empty one.
/// Finish against the number of literal TABLES statements, before synthesizing
/// default requests or counting parenthesized/list request expansions.
pub const TestStatement = struct {
    present: bool = false,
    requests: Tests = .{},
    pub fn parse(self: *TestStatement, tokens: []const lex.Token, d: *diag.Diagnostics) diag.Error!void {
        if (self.present) return d.fail(error.ParseError, if (tokens.len > 0) tokens[0].line else 0, "Only one TEST statement is allowed.", .{});
        self.present = true;
        self.requests = try parseTests(tokens, d);
    }
    pub fn finish(self: TestStatement, tables_statement_count: usize, d: *diag.Diagnostics) diag.Error!void {
        if (self.present and tables_statement_count == 0) try d.report(.warning, 0, "When you specify a TEST statement, you must also specify a TABLES statement.", .{});
    }
};

test "FEAT-freq-tests oracle TESTP implies CHISQ and excludes TESTF" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const tokens = try lex.tokenize(a, "testp=(20 30 50) testf=(14 21 35);", &d);
    var i: usize = 0;
    var opts: Options = .{};
    try std.testing.expect(try consumeTableOption(a, tokens, &i, &opts, &d));
    try std.testing.expect(opts.chisq);
    try std.testing.expectError(error.ParseError, consumeTableOption(a, tokens, &i, &opts, &d));
    try std.testing.expect(d.hasErrors());
    d.list.clearRetainingCapacity();
    const frequency = try lex.tokenize(a, "testf=(14 21 35);", &d);
    i = 0;
    opts = .{};
    try std.testing.expect(try consumeTableOption(a, frequency, &i, &opts, &d));
    try std.testing.expect(opts.chisq);
}

test "FEAT-freq-tests oracle TEST statement cardinality and warning cases" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    var empty: TestStatement = .{};
    try empty.parse(&.{}, &d);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expect(!d.hasErrors());
    d.list.clearRetainingCapacity();
    const tokens = try lex.tokenize(a, "gamma", &d);
    var statement: TestStatement = .{};
    try statement.parse(tokens[0 .. tokens.len - 1], &d);
    try statement.finish(0, &d);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expect(!d.hasErrors());
    var first: Options = .{};
    var second: Options = .{};
    implyTests(&first, statement.requests, 1);
    implyTests(&second, statement.requests, 1);
    try std.testing.expect(first.measures and second.measures);
    first = .{};
    implyTests(&first, statement.requests, 2);
    try std.testing.expect(!first.measures);
    try std.testing.expectError(error.ParseError, statement.parse(tokens[0 .. tokens.len - 1], &d));
}

test "FEAT-freq-tests oracle list accumulation and dataset precedence" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const cases = [_][]const u8{
        "testp=(20 30) testp=(50);",
        "testp=p;",
        "testp=(20 30 50) testp=p;",
        "testp=p testp=(20 30 50);",
        "chisq testp=p testp=other;",
    };
    for (cases, 0..) |source, index| {
        d.list.clearRetainingCapacity();
        const tokens = try lex.tokenize(a, source, &d);
        var i: usize = 0;
        var opts: Options = .{};
        while (!at(tokens, i, .semicolon)) try std.testing.expect(try consumeTableOption(a, tokens, &i, &opts, &d));
        if (index == 0) {
            try std.testing.expectEqualSlices(f64, &.{ 20, 30, 50 }, opts.expected.proportions);
            const result = try kernels.goodnessOfFit(&.{ 20, 27, 23 }, .{ .proportions = opts.expected.proportions }, null);
            try std.testing.expectApproxEqAbs(@as(f64, 8.4), result.pearson.statistic, 1e-12);
        } else try std.testing.expectEqualStrings("p", opts.expected.proportion_dataset);
        try std.testing.expectEqual(index != 1, opts.chisq);
        try std.testing.expectEqual(@as(usize, if (index == 4) 1 else 0), d.list.items.len);
        try std.testing.expect(!d.hasErrors());
    }
}
