//! Risk TABLES option parser. No inference or listing dependencies.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const infer = @import("freq_risk_inference.zig");
pub const Family = enum { binomial, difference, relative_risk, odds_ratio };
pub const Method = enum { ac, exact, jeffreys, lr, logit, midp, wald, wilson, ha, mn, newcombe, waldmodified, fm };
pub const CL = struct { method: Method, correct: bool = false, bias: bool = true };
pub const Level = union(enum) { number: usize, value: []const u8 };
pub const Request = struct {
    family: Family,
    cls: []const CL = &.{},
    level: Level = .{ .number = 1 },
    column: usize = 0,
    both_columns: bool = false,
    correct: bool = false,
    norisks: bool = false,
    common: bool = false,
    printall: bool = false,
    p: f64 = 0.5,
    equal: bool = false,
    null_value: f64 = 0,
    noninf: bool = false,
    sup: bool = false,
    equiv: bool = false,
    margin: ?[2]f64 = null,
    paired_margin: bool = false,
    variance: ?infer.Variance = null,
    method: Method = .wald,
    pub fn tests(self: Request) bool {
        return self.equal or self.noninf or self.sup or self.equiv;
    }
};
pub const Options = struct {
    binomial: ?Request = null,
    difference: ?Request = null,
    relative_risk: ?Request = null,
    odds_ratio: ?Request = null,
    senspec: bool = false,
    pub fn any(self: Options) bool {
        return self.binomial != null or self.difference != null or self.relative_risk != null or self.odds_ratio != null or self.senspec;
    }
};
pub fn gap(d: *diag.Diagnostics, line: usize, feature: []const u8) diag.Error {
    diag.markGap();
    return d.fail(error.ExecError, line, "PROC FREQ: {s} is not yet supported", .{feature});
}
fn kw(t: lex.Token, s: []const u8) bool {
    return t.tag == .name and std.ascii.eqlIgnoreCase(t.text, s);
}
const Reader = struct {
    a: std.mem.Allocator,
    t: []const lex.Token,
    i: usize,
    d: *diag.Diagnostics,
    fn at(self: Reader, tag: lex.Tag) bool {
        return self.i < self.t.len and self.t[self.i].tag == tag;
    }
    fn is(self: Reader, s: []const u8) bool {
        return self.i < self.t.len and kw(self.t[self.i], s);
    }
    fn fail(self: Reader, message: []const u8) diag.Error {
        return self.d.fail(error.ParseError, if (self.i < self.t.len) self.t[self.i].line else 0, "PROC FREQ: {s}", .{message});
    }
    fn expect(self: *Reader, tag: lex.Tag) diag.Error!void {
        if (!self.at(tag)) return self.fail("malformed risk option");
        self.i += 1;
    }
    fn number(self: *Reader) diag.Error!f64 {
        var sign: f64 = 1;
        if (self.at(.minus)) {
            sign = -1;
            self.i += 1;
        } else if (self.at(.plus)) self.i += 1;
        if (!self.at(.number)) return self.fail("expected numeric risk option");
        const n = std.fmt.parseFloat(f64, self.t[self.i].text) catch return self.fail("invalid risk number");
        self.i += 1;
        if (!std.math.isFinite(n)) return self.fail("risk option must be finite");
        return sign * n;
    }
    fn methodName(self: *Reader, family: Family, test_method: bool) diag.Error!Method {
        if (!self.at(.name)) return self.fail("expected risk method name");
        const t = self.t[self.i];
        self.i += 1;
        if ((kw(t, "agresticoull") or kw(t, "clopperpearson")) and family != .binomial) return self.fail("binomial method alias used for another family");
        if ((kw(t, "agresticaffo") or kw(t, "mn")) and family != .difference) return self.fail("risk difference method alias used for another family");
        const m: Method = if (kw(t, "wald")) .wald else if (kw(t, "waldmodified")) .waldmodified else if (kw(t, "lr") or kw(t, "likelihoodratio")) .lr else if (kw(t, "exact") or kw(t, "clopperpearson")) .exact else if (kw(t, "midp")) .midp else if (kw(t, "ac") or kw(t, "agresticoull") or kw(t, "agresticaffo")) .ac else if (kw(t, "jeffreys")) .jeffreys else if (kw(t, "logit")) .logit else if (kw(t, "wilson")) .wilson else if (kw(t, "ha")) .ha else if (kw(t, "newcombe")) .newcombe else if (kw(t, "mn")) .mn else if (kw(t, "fm")) .fm else if (kw(t, "score")) (if (test_method) .fm else if (family == .binomial) .wilson else .mn) else if (kw(t, "blaker") and family == .binomial and !test_method) return gap(self.d, t.line, "binomial Blaker limits") else return self.fail("invalid risk method");
        const valid = if (test_method) switch (family) {
            .difference => m == .wald or m == .ha or m == .fm or m == .newcombe,
            .relative_risk => m == .wald or m == .waldmodified or m == .fm or m == .lr,
            else => false,
        } else switch (family) {
            .binomial => m == .wald or m == .exact or m == .ac or m == .jeffreys or m == .lr or m == .logit or m == .midp or m == .wilson,
            .difference => m == .wald or m == .exact or m == .ac or m == .ha or m == .mn or m == .newcombe,
            .relative_risk => m == .wald or m == .waldmodified or m == .exact or m == .mn or m == .lr,
            .odds_ratio => m == .wald or m == .waldmodified or m == .exact or m == .mn or m == .lr or m == .midp,
        };
        if (!valid) return self.fail("method is not valid for this risk analysis");
        if (m == .exact and family != .binomial) return gap(self.d, t.line, "risk CL=EXACT / EXACT statement integration");
        return m;
    }
    fn confidence(self: *Reader, req: *Request) diag.Error!void {
        try self.expect(.eq);
        const list = self.at(.lparen);
        if (list) self.i += 1;
        var cls: std.ArrayList(CL) = .empty;
        try cls.appendSlice(self.a, req.cls);
        while (true) {
            var cl = CL{ .method = try self.methodName(req.family, false) };
            if (self.at(.lparen)) {
                self.i += 1;
                if (req.family == .difference and cl.method == .mn and self.is("mee")) {
                    self.i += 1;
                    cl.bias = false;
                } else {
                    if (!self.is("correct")) return self.fail("expected CORRECT or risk-difference MEE in confidence method");
                    self.i += 1;
                    if ((req.family == .odds_ratio or req.family == .relative_risk) and cl.method != .mn) return self.fail("CORRECT suboption is only valid for score limits");
                    if (cl.method == .mn) {
                        try self.expect(.eq);
                        if (!self.is("no")) return self.fail("score CORRECT must be NO; MEE is a separate suboption");
                        self.i += 1;
                        cl.bias = false;
                    } else if (cl.method == .wald or cl.method == .wilson or cl.method == .newcombe) cl.correct = true else return self.fail("CORRECT is not valid for this method");
                }
                try self.expect(.rparen);
            }
            try cls.append(self.a, cl);
            if (!list or self.at(.rparen)) break;
            if (self.at(.comma)) self.i += 1;
        }
        if (list) try self.expect(.rparen);
        req.cls = try cls.toOwnedSlice(self.a);
    }
    fn options(self: *Reader, req: *Request) diag.Error!void {
        try self.expect(.lparen);
        while (!self.at(.rparen)) {
            if (!self.at(.name)) return self.fail("expected risk suboption");
            const token = self.t[self.i];
            self.i += 1;
            if (kw(token, "cl")) {
                try self.confidence(req);
                continue;
            }
            if (kw(token, "common") and req.family == .difference) {
                req.common = true;
                continue;
            }
            if (kw(token, "outlevel") and req.family == .binomial) return gap(self.d, token.line, "BINOMIAL OUTLEVEL output datasets");
            if (kw(token, "correct") and (req.family == .binomial or req.family == .difference)) {
                req.correct = true;
                continue;
            }
            if (kw(token, "norisks") and req.family == .difference) {
                req.norisks = true;
                continue;
            }
            if (kw(token, "printall") and req.family == .relative_risk) {
                req.printall = true;
                continue;
            }
            if (req.family == .odds_ratio) return self.fail("OR accepts only CL");
            if (kw(token, "noninf") or kw(token, "noninferiority")) {
                req.noninf = true;
                continue;
            }
            if (kw(token, "sup") or kw(token, "superiority")) {
                req.sup = true;
                continue;
            }
            if (kw(token, "equiv") or kw(token, "equivalence")) {
                req.equiv = true;
                continue;
            }
            if (kw(token, "equal") and req.family != .binomial) {
                req.equal = true;
                if (self.at(.lparen)) {
                    self.i += 1;
                    if (!self.is("null")) return self.fail("EQUAL accepts NULL=");
                    self.i += 1;
                    try self.expect(.eq);
                    req.null_value = try self.number();
                    if (req.family == .difference) req.null_value = proportionValue(req.null_value);
                    try self.expect(.rparen);
                }
                continue;
            }
            try self.expect(.eq);
            if (kw(token, "level") and req.family == .binomial) {
                if (self.at(.string)) {
                    req.level = .{ .value = self.t[self.i].text };
                    self.i += 1;
                } else {
                    const v = try self.number();
                    if (v < 1 or v != @floor(v) or v > 1e9) return self.fail("LEVEL must be a positive integer or formatted value");
                    req.level = .{ .number = @intFromFloat(v) };
                }
            } else if (kw(token, "column") and req.family != .binomial) {
                if (req.family == .difference and self.is("both")) {
                    req.both_columns = true;
                    self.i += 1;
                } else {
                    const v = try self.number();
                    if (v != 1 and v != 2) return self.fail("COLUMN must be 1 or 2");
                    req.column = if (v == 1) 0 else 1;
                    req.both_columns = false;
                }
            } else if (kw(token, "p") and req.family == .binomial) {
                req.p = proportionValue(try self.number());
                if (!(req.p > 0 and req.p < 1)) return self.fail("P must be between 0 and 1 (or percent)");
            } else if (kw(token, "var") and req.family != .relative_risk) {
                if (self.is("null")) req.variance = .null_value else if (self.is("sample")) req.variance = .sample else return self.fail("VAR must be NULL or SAMPLE");
                self.i += 1;
            } else if (kw(token, "method") and req.family != .binomial) {
                req.method = try self.methodName(req.family, true);
            } else if (kw(token, "margin")) {
                req.paired_margin = self.at(.lparen);
                if (req.paired_margin) self.i += 1;
                var lo = try self.number();
                var hi = lo;
                if (req.paired_margin) {
                    if (self.at(.comma)) self.i += 1;
                    hi = try self.number();
                    try self.expect(.rparen);
                }
                if (req.family != .relative_risk) {
                    lo = proportionValue(lo);
                    hi = proportionValue(hi);
                }
                if ((!req.paired_margin and lo <= 0) or (req.paired_margin and lo >= hi)) return self.fail("invalid risk test margins");
                req.margin = .{ lo, hi };
            } else return self.fail("unknown risk suboption");
        }
        self.i += 1;
        if (req.equal and ((req.family == .relative_risk and req.null_value <= 0) or (req.family == .difference and @abs(req.null_value) >= 1))) return self.fail("invalid equality null value");
        if (req.equal and req.method == .newcombe) return self.fail("Newcombe is not an equality test");
        if (req.paired_margin and (req.noninf or req.sup)) return self.fail("NI/SUP require a single margin");
    }
};
fn proportionValue(x: f64) f64 {
    return if (@abs(x) >= 1) x / 100 else x;
}
pub fn consumeTableOption(a: std.mem.Allocator, tokens: []const lex.Token, index: *usize, opts: *Options, d: *diag.Diagnostics) diag.Error!bool {
    if (index.* >= tokens.len) return false;
    const t = tokens[index.*];
    if (kw(t, "senspec")) {
        opts.senspec = true;
        index.* += 1;
        return true;
    }
    const family: Family = if (kw(t, "binomial") or kw(t, "bin")) .binomial else if (kw(t, "riskdiff")) .difference else if (kw(t, "relrisk")) .relative_risk else if (kw(t, "or") or kw(t, "oddsratio")) .odds_ratio else return false;
    const previous = switch (family) {
        .binomial => opts.binomial,
        .difference => opts.difference,
        .relative_risk => opts.relative_risk,
        .odds_ratio => opts.odds_ratio,
    };
    var req = previous orelse Request{ .family = family, .null_value = if (family == .relative_risk) 1 else 0 };
    var r = Reader{ .a = a, .t = tokens, .i = index.* + 1, .d = d };
    if (r.at(.lparen)) try r.options(&req);
    switch (family) {
        .binomial => opts.binomial = req,
        .difference => opts.difference = req,
        .relative_risk => opts.relative_risk = req,
        .odds_ratio => opts.odds_ratio = req,
    }
    index.* = r.i;
    return true;
}

test "FEAT-freq-risk parser aliases percent nulls and method controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const tokens = try lex.tokenize(a, "bin(level='Event' p=1 equiv margin=(-20,30) var=null cl=(ac score(correct) exact)) riskdiff(column=2 equal(null=10) method=score cl=(mn(mee) newcombe(correct))) relrisk(sup margin=1.25 method=lr printall) oddsratio(cl=(score(correct=no) midp)) senspec;", &d);
    var i: usize = 0;
    var opts = Options{};
    while (tokens[i].tag != .semicolon) try std.testing.expect(try consumeTableOption(a, tokens, &i, &opts, &d));
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), opts.binomial.?.p, 1e-15);
    try std.testing.expectEqualStrings("Event", opts.binomial.?.level.value);
    try std.testing.expectEqual(@as(f64, -0.2), opts.binomial.?.margin.?[0]);
    try std.testing.expect(opts.binomial.?.cls[1].correct);
    try std.testing.expectEqual(@as(usize, 1), opts.difference.?.column);
    try std.testing.expectEqual(@as(f64, 0.1), opts.difference.?.null_value);
    try std.testing.expect(!opts.difference.?.cls[0].bias);
    try std.testing.expectEqual(Method.fm, opts.difference.?.method);
    try std.testing.expect(opts.relative_risk.?.printall and opts.senspec);
    try std.testing.expect(!opts.odds_ratio.?.cls[0].bias);
}
test "FEAT-freq-risk parser captures invalid requests versus pending dependencies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "bin(level=0)", "bin(p=0)", "riskdiff(column=3)", "riskdiff(method=typo)", "or(cl=agresticoull)", "relrisk(cl=wald(correct))", "riskdiff(cl=mn(correct=mee))", "relrisk(cl=score(mee))" }) |source| {
        var d = diag.Diagnostics.init(a);
        const t = try lex.tokenize(a, source, &d);
        var i: usize = 0;
        var opts = Options{};
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, consumeTableOption(a, t, &i, &opts, &d));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(!diag.gapHit());
    }
    for ([_][]const u8{ "bin(cl=blaker)", "relrisk(cl=exact)", "bin(outlevel)" }) |source| {
        var d = diag.Diagnostics.init(a);
        const t = try lex.tokenize(a, source, &d);
        var i: usize = 0;
        var opts = Options{};
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ExecError, consumeTableOption(a, t, &i, &opts, &d));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(diag.gapHit());
    }
}
