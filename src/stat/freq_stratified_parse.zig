//! Independent option reader; public FREQ dispatcher must enable it only after
//! computation and rendering integration. Does not accept-and-ignore options.
const std = @import("std");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const k = @import("freq_stratified.zig");
const risk = @import("freq_risk.zig");
pub const Methods = packed struct { mh: bool = false, klingenberg: bool = false, mr: bool = false, score: bool = false, newcombe: bool = false, newcombe_mr: bool = false };
pub const Common = struct {
    enabled: bool = false,
    limits: ?Methods = null, // requested methods, before display suppression
    suppress_limits: bool = false,
    tests: ?Methods = null, // null means TEST not requested
    test_default: bool = false,
    print_weights: ?Methods = null,
    print_default: bool = false,
    column: ?risk.Column = null, // table RISKDIFF inheritance resolved by caller
    correct: bool = true,
    sample_variance: bool = false,
    pub fn selectedLimits(self: Common) Methods {
        return if (self.suppress_limits) .{} else self.limits orelse .{ .mh = true, .score = true };
    }
    pub fn selectedTests(self: Common) Methods {
        if (self.tests) |t| return t;
        if (!self.test_default) return .{};
        const l = if (self.suppress_limits) Methods{} else self.limits orelse Methods{};
        return .{ .mh = l.mh or (!l.mr and !l.score), .mr = l.mr, .score = l.score };
    }
    pub fn selectedWeights(self: Common) Methods {
        if (self.print_weights) |w| return w;
        if (!self.print_default) return .{};
        const l = self.limits orelse Methods{};
        const t = self.tests orelse Methods{};
        var w = Methods{ .mh = l.mh or l.klingenberg or l.newcombe or t.mh, .mr = l.mr or l.newcombe_mr or t.mr, .score = l.score or t.score };
        if (!w.mh and !w.mr and !w.score) w.mh = true;
        return w;
    }
};
pub const Agreement = struct {
    enabled: bool = false,
    ac1: bool = false,
    pabak: bool = false,
    details: bool = false,
    weighted_details: bool = false,
    print_weights: bool = false,
    weight: k.KappaWeight = .cicchetti_allison,
    df: k.SymmetryDf = .default,
    null_ratio: f64 = 1,
    null_kappa: ?f64 = null,
    null_weighted: ?f64 = null,
    restore: bool = false,
};
pub const Options = struct {
    cmh: u2 = 0,
    bdt: bool = false,
    qor: bool = false,
    i2: bool = false,
    mantel_fleiss: bool = false,
    gail_simon: bool = false,
    gail_column: risk.Column = .first,
    trend: bool = false,
    jt: bool = false,
    agreement: Agreement = .{},
    common: Common = .{},
};
fn combine(a: Methods, b: Methods) Methods {
    return .{ .mh = a.mh or b.mh, .klingenberg = a.klingenberg or b.klingenberg, .mr = a.mr or b.mr, .score = a.score or b.score, .newcombe = a.newcombe or b.newcombe, .newcombe_mr = a.newcombe_mr or b.newcombe_mr };
}
fn kw(t: lex.Token, s: []const u8) bool {
    return t.tag == .name and std.ascii.eqlIgnoreCase(t.text, s);
}
const Reader = struct {
    tokens: []const lex.Token,
    i: usize,
    d: *diag.Diagnostics,
    fn at(self: Reader, tag: lex.Tag) bool {
        return self.i < self.tokens.len and self.tokens[self.i].tag == tag;
    }
    fn fail(self: *Reader, comptime message: []const u8) diag.Error {
        return self.d.fail(error.ParseError, if (self.i < self.tokens.len) self.tokens[self.i].line else 0, "PROC FREQ: " ++ message, .{});
    }
    fn expect(self: *Reader, tag: lex.Tag) diag.Error!void {
        if (!self.at(tag)) return self.fail("malformed stratified option");
        self.i += 1;
    }
    fn name(self: *Reader) diag.Error!lex.Token {
        if (!self.at(.name)) return self.fail("expected option name");
        const t = self.tokens[self.i];
        self.i += 1;
        return t;
    }
    fn number(self: *Reader) diag.Error!f64 {
        var sign: f64 = 1;
        if (self.at(.minus)) {
            sign = -1;
            self.i += 1;
        } else if (self.at(.plus)) self.i += 1;
        if (!self.at(.number)) return self.fail("expected numeric value");
        const x = std.fmt.parseFloat(f64, self.tokens[self.i].text) catch return self.fail("invalid numeric value");
        self.i += 1;
        if (!std.math.isFinite(x)) return self.fail("nonfinite option value");
        return sign * x;
    }
    fn column(self: *Reader) diag.Error!risk.Column {
        try self.expect(.eq);
        const v = try self.number();
        return if (v == 1) .first else if (v == 2) .second else self.fail("COLUMN must be 1 or 2");
    }
    fn gail(self: *Reader, opts: *Options) diag.Error!void {
        opts.gail_simon = true;
        if (self.at(.lparen)) {
            self.i += 1;
            const t = try self.name();
            if (!kw(t, "column")) return self.fail("unknown GAILSIMON option");
            opts.gail_column = try self.column();
            try self.expect(.rparen);
        }
    }
    fn methods(self: *Reader, which: enum { limits, tests, weights }, common: *Common) diag.Error!Methods {
        try self.expect(.eq);
        const paren = self.at(.lparen);
        if (paren) self.i += 1;
        var methods_set = Methods{};
        var any = false;

        while (true) {
            const t = try self.name();
            any = true;
            if (kw(t, "mh")) methods_set.mh = true else if (kw(t, "mr") or kw(t, "minrisk")) {
                methods_set.mr = true;
                if (which == .tests and self.at(.lparen)) {
                    self.i += 1;
                    const v = try self.name();
                    if (!kw(v, "var")) return self.fail("unknown MR test option");
                    try self.expect(.eq);
                    if (!kw(try self.name(), "sample")) return self.fail("MR VAR must be SAMPLE");
                    common.sample_variance = true;
                    try self.expect(.rparen);
                }
            } else if (kw(t, "score")) methods_set.score = true else if (which == .limits and (kw(t, "k") or kw(t, "klingenberg"))) methods_set.klingenberg = true else if (which == .limits and (kw(t, "newcombe") or kw(t, "newcombemh") or kw(t, "wilson"))) methods_set.newcombe = true else if (which == .limits and (kw(t, "newcombemr") or kw(t, "newcombeminrisk"))) methods_set.newcombe_mr = true else if (which == .limits and (kw(t, "none") or kw(t, "no"))) {
                common.suppress_limits = true;
            } else return self.fail("unknown common-risk method");
            if (!paren) break;
            if (self.at(.comma)) return self.fail("method lists use spaces, not commas");
            if (self.at(.rparen)) {
                self.i += 1;
                break;
            }
        }
        if (!any) return self.fail("empty method list");
        return methods_set;
    }
};
/// Mirrors the existing stat parser cursor contract. Unknown top-level names
/// return false with cursor/options unchanged so the caller retains D009 routing.
pub fn consumeTableOption(tokens: []const lex.Token, index: *usize, opts: *Options, d: *diag.Diagnostics) diag.Error!bool {
    var r = Reader{ .tokens = tokens, .i = index.*, .d = d };
    if (!r.at(.name)) return false;
    const t = tokens[r.i];
    r.i += 1;
    var next = opts.*;
    if (kw(t, "trend")) next.trend = true else if (kw(t, "jt")) next.jt = true else if (kw(t, "gailsimon") or kw(t, "gs")) try r.gail(&next) else if (kw(t, "cmh") or kw(t, "cmh1") or kw(t, "cmh2")) {
        const requested: u2 = if (kw(t, "cmh1")) 1 else if (kw(t, "cmh2")) 2 else 3;
        next.cmh = if (next.cmh == 0) requested else @min(next.cmh, requested);
        if (r.at(.lparen)) {
            r.i += 1;
            while (!r.at(.rparen)) {
                const s = try r.name();
                if (kw(s, "bdt")) next.bdt = true else if (kw(s, "qor")) next.qor = true else if (kw(s, "i2")) {
                    next.i2 = true;
                    next.qor = true;
                } else if (kw(s, "mf") or kw(s, "mantelfleiss")) next.mantel_fleiss = true else if (kw(s, "gailsimon") or kw(s, "gs")) try r.gail(&next) else return r.fail("unknown CMH option");
            }
            r.i += 1;
        }
    } else if (kw(t, "agree")) {
        var ag = &next.agreement;
        ag.enabled = true;
        if (r.at(.lparen)) {
            r.i += 1;
            while (!r.at(.rparen)) {
                const s = try r.name();
                if (kw(s, "ac1")) ag.ac1 = true else if (kw(s, "pabak")) ag.pabak = true else if (kw(s, "details") or kw(s, "kappadetails")) {
                    ag.details = true;
                    ag.weighted_details = true;
                } else if (kw(s, "wtkappadetails")) ag.weighted_details = true else if (kw(s, "printkwts")) ag.print_weights = true else if (kw(s, "wt")) {
                    try r.expect(.eq);
                    const weight = try r.name();
                    if (kw(weight, "fc")) ag.weight = .fleiss_cohen else if (kw(weight, "ca")) ag.weight = .cicchetti_allison else return r.fail("WT must be CA or FC");
                } else if (kw(s, "tables")) {
                    try r.expect(.eq);
                    if (!kw(try r.name(), "restore")) return r.fail("AGREE TABLES must be RESTORE");
                    ag.restore = true;
                } else if (kw(s, "dfsym")) {
                    try r.expect(.eq);
                    if (r.at(.name) and kw(tokens[r.i], "adjust")) {
                        r.i += 1;
                        ag.df = .adjust;
                    } else {
                        const v = try r.number();
                        if (v <= 0) return r.fail("DFSYM must be positive");
                        ag.df = .{ .value = v };
                    }
                } else if (kw(s, "mnullratio")) {
                    try r.expect(.eq);
                    ag.null_ratio = try r.number();
                    if (ag.null_ratio <= 0) return r.fail("MNULLRATIO must be positive");
                } else if (kw(s, "nullkappa") or kw(s, "nullwtkappa")) {
                    try r.expect(.eq);
                    const v = try r.number();
                    if (@abs(v) > 1) return r.fail("null kappa must be between -1 and 1");
                    if (kw(s, "nullkappa")) ag.null_kappa = v else ag.null_weighted = v;
                } else return r.fail("unknown AGREE option");
            }
            r.i += 1;
        }
    } else if (kw(t, "commonriskdiff")) {
        var common = &next.common;
        common.enabled = true;
        if (r.at(.lparen)) {
            r.i += 1;
            while (!r.at(.rparen)) {
                const s = try r.name();
                if (kw(s, "cl")) common.limits = combine(common.limits orelse .{}, try r.methods(.limits, common)) else if (kw(s, "column")) common.column = try r.column() else if (kw(s, "correct")) {
                    try r.expect(.eq);
                    if (!kw(try r.name(), "no")) return r.fail("CORRECT must be NO");
                    common.correct = false;
                } else if (kw(s, "test")) {
                    if (r.at(.eq)) common.tests = combine(common.tests orelse .{}, try r.methods(.tests, common)) else common.test_default = true;
                } else if (kw(s, "printwts")) {
                    if (r.at(.eq)) common.print_weights = combine(common.print_weights orelse .{}, try r.methods(.weights, common)) else common.print_default = true;
                } else return r.fail("unknown COMMONRISKDIFF option");
            }
            r.i += 1;
        }
    } else return false;
    opts.* = next;
    index.* = r.i;
    return true;
}

fn parseForTest(a: std.mem.Allocator, source: []const u8, d: *diag.Diagnostics) diag.Error!Options {
    const tokens = try lex.tokenize(a, source, d);
    var i: usize = 0;
    var opts = Options{};
    while (tokens[i].tag != .eof) {
        if (!try consumeTableOption(tokens, &i, &opts, d)) return error.ParseError;
    }
    return opts;
}
test "stratified option contract covers nested common-risk and agreement requests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const opts = try parseForTest(a, "cmh2(bdt i2 mf gs(column=2)) trend jt agree(ac1 pabak details printkwts wt=fc nullkappa=-.2 nullwtkappa=.3 mnullratio=2 dfsym=adjust tables=restore) commonriskdiff(cl=(mh k mr score newcombe newcombemr) test=(mh mr(var=sample) score) printwts column=2 correct=no)", &d);
    try std.testing.expectEqual(@as(u2, 2), opts.cmh);
    try std.testing.expect(opts.bdt and opts.qor and opts.i2 and opts.mantel_fleiss and opts.gail_simon);
    try std.testing.expectEqual(risk.Column.second, opts.gail_column);
    try std.testing.expect(opts.agreement.ac1 and opts.agreement.pabak and opts.agreement.restore and opts.agreement.print_weights);
    try std.testing.expectEqual(@as(?f64, -0.2), opts.agreement.null_kappa);
    try std.testing.expect(opts.common.selectedLimits().newcombe_mr and opts.common.selectedTests().mr and opts.common.selectedWeights().score);
    try std.testing.expect(opts.common.sample_variance and !opts.common.correct);
}
test "stratified malformed options report captured parse errors and preserve cursor" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "agree(dfsym=0)", "agree(mnullratio=-1)", "agree(nullkappa=2)", "cmh(bogus)", "gs(column=3)", "commonriskdiff(test=mr(var=null))", "commonriskdiff(cl=())", "agree(details" }) |source| {
        var d = diag.Diagnostics.init(a);
        const tokens = try lex.tokenize(a, source, &d);
        var i: usize = 0;
        var opts = Options{};
        try std.testing.expectError(error.ParseError, consumeTableOption(tokens, &i, &opts, &d));
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(usize, 0), i);
        try std.testing.expect(!opts.agreement.enabled);
    }
    var d = diag.Diagnostics.init(a);
    const opts = try parseForTest(a, "commonriskdiff(test printwts)", &d);
    try std.testing.expect(opts.common.selectedTests().mh and !opts.common.selectedTests().score);
    const none = try parseForTest(a, "commonriskdiff(cl=none printwts=mr)", &d);
    try std.testing.expect(!none.common.selectedLimits().mh and none.common.selectedWeights().mr);
}

pub const Tests = packed struct { kappa: bool = false, weighted_kappa: bool = false };
/// Public TEST orchestration can offer each token to its independent families;
/// unknown tokens remain the caller's responsibility, not an invented gap here.
pub fn consumeTest(token: lex.Token, tests: *Tests) bool {
    if (kw(token, "agree")) {
        tests.kappa = true;
        tests.weighted_kappa = true;
    } else if (kw(token, "kappa")) tests.kappa = true else if (kw(token, "wtkappa") or kw(token, "wtkap")) tests.weighted_kappa = true else return false;
    return true;
}
pub fn implyTests(options: *Options, tests: Tests, tables_statement_count: usize) void {
    if (tables_statement_count == 1 and (tests.kappa or tests.weighted_kappa)) options.agreement.enabled = true;
}
test "stratified SAS option precedence and default test selection" {
    // options.sas and options_edges.sas: CMH1 wins in both orders; CL=NONE
    // suppresses mixed lists; TEST defaults to MH for non-testable CL choices.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const one = try parseForTest(a, "cmh1 cmh agree(wt=ca) commonriskdiff(cl=(none mh) test printwts)", &d);
    try std.testing.expectEqual(@as(u2, 1), one.cmh);
    try std.testing.expectEqual(k.KappaWeight.cicchetti_allison, one.agreement.weight);
    try std.testing.expect(!one.common.selectedLimits().mh);
    try std.testing.expect(one.common.selectedTests().mh and one.common.selectedWeights().mh);
    const nc = try parseForTest(a, "commonriskdiff(cl=(newcombe newcombemr) test printwts)", &d);
    try std.testing.expect(nc.common.selectedTests().mh and !nc.common.selectedTests().mr);
    const tokens = try lex.tokenize(a, "agree wtkap", &d);
    var tests = Tests{};
    try std.testing.expect(consumeTest(tokens[0], &tests));
    try std.testing.expect(consumeTest(tokens[1], &tests));
    var opts = Options{};
    implyTests(&opts, tests, 2);
    try std.testing.expect(!opts.agreement.enabled);
    implyTests(&opts, tests, 1);
    try std.testing.expect(opts.agreement.enabled);
    try std.testing.expectError(error.ParseError, parseForTest(a, "commonriskdiff(cl=(mh,))", &d));
    try std.testing.expect(d.hasErrors());
}

test "stratified SAS defaults distinguish implicit limits from requested tests weights" {
    // options_defaults.sas: implicit default intervals include SCORE but default
    // TEST/PRINTWTS select MH only; repeated CL accumulates; NONE suppresses in
    // either order but leaves requested weights visible.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const defaults = try parseForTest(a, "commonriskdiff(test printwts)", &d);
    try std.testing.expect(defaults.common.selectedLimits().score);
    try std.testing.expect(!defaults.common.selectedTests().score and !defaults.common.selectedWeights().score);
    for ([_][]const u8{ "commonriskdiff(cl=none cl=score test printwts)", "commonriskdiff(cl=score cl=none test printwts)" }) |source| {
        const x = try parseForTest(a, source, &d);
        try std.testing.expect(!x.common.selectedLimits().score and x.common.selectedTests().mh);
        try std.testing.expect(x.common.selectedWeights().score and !x.common.selectedWeights().mh);
    }
    const repeated = try parseForTest(a, "commonriskdiff(cl=mh cl=score)", &d);
    try std.testing.expect(repeated.common.selectedLimits().mh and repeated.common.selectedLimits().score);
    const unknown = try lex.tokenize(a, "plots", &d);
    var opts = Options{};
    var index: usize = 0;
    try std.testing.expect(!try consumeTableOption(unknown, &index, &opts, &d));
    try std.testing.expectEqual(@as(usize, 0), index);
}
