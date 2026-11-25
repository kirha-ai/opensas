//! PROC FREQ: parsing, typed table computation, output datasets and rendering.
const p = @import("../proc.zig");
const std = @import("std");
const assert = std.debug.assert;
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const Dataset = @import("../dataset.zig").Dataset;
const format = @import("../format.zig");
const io = @import("../io.zig");
const Token = @import("../lexer.zig").Token;
const ProcCtx = p.ProcCtx;
const procInput = p.procInput;
const cmpValue = p.cmpValue;
const var_lists = @import("variable_lists.zig");
const by_groups = @import("by_groups.zig");
const bySlices = p.bySlices;
const cellText = p.cellText;
const VarSpec = p.VarSpec;
const parseProcFormat = p.parseProcFormat;
const groupFormats = p.groupFormats;
const FmtLevels = p.FmtLevels;
const fmtLevelsFor = p.fmtLevelsFor;
const fmtRawFor = p.fmtRawFor;
const pctText = p.pctText;
const line = p.line;
const putLeft = p.putLeft;
const putRight = p.putRight;
const flush = p.flush;
const skipParen = p.skipParen;
const tkKw = p.tkKw;
const atTag = p.atTag;
const lastDataset = p.lastDataset;
const eqi = p.eqi;
const failGap = p.failGap;

pub fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |s| std.mem.trim(u8, s, " ").len == 0,
    };
}

/// An empty percent base is undefined, including WEIGHT / ZEROS tables.
pub fn percent(count: f64, denominator: f64) f64 {
    return if (denominator == 0) std.math.nan(f64) else 100 * count / denominator;
}

const ONEWAY_TITLE = (" " ** 38) ++ "The FREQ Procedure\n";
const ONEWAY_NOCUM_TITLE = (" " ** 22) ++ "The FREQ Procedure\n";
const TWOWAY_TITLE = (" " ** 24) ++ "The FREQ Procedure\n";
const NLEVELS_TITLE = (" " ** 21) ++ "The FREQ Procedure\n"; // narrow NLEVELS table (BUG-freqnlevels)

/// Remaining named inference families outside FEAT-freq-tests fail loud.
/// Supported options are consumed by freq_tests_parse before this guard.
fn isUnsupportedFreqStat(kw: []const u8) bool {
    inline for (.{
        // association / independence tests
        "chisq",     "exact",     "fisher", "measures", "cmh",       "cmh1",     "cmh2",
        "mhchi",     "trend",     "jt",     "all",      "cochran",   "binomial", "plcorr",
        "gamma",     "kentb",     "stutc",  "lambda",   "pcorr",     "scorr",    "tsymm",
        // agreement
        "agree",     "kappa",     "wtkap",  "mcnem",    "bowker",
        // risk / relative risk
           "relrisk",  "riskdiff",
        "riskdiff1", "riskdiff2", "testp",  "testf",    "gailsimon",
    }) |o| {
        if (eqi(kw, o)) return true;
    }
    return false;
}

/// Valid SAS options outside this table ticket (statistics/ODS) fail as gaps.
fn isFreqTablesGapOption(kw: []const u8) bool {
    inline for (.{ "alpha", "bin", "cl", "commonriskdiff", "or", "senspec", "contents", "nowarn", "plots" }) |opt|
        if (eqi(kw, opt)) return true;
    return false;
}

const table_model = @import("freq_table.zig");
const stat_parse = @import("freq_tests_parse.zig");
const stat_output = @import("freq_output.zig");
const stat_exec = @import("freq_tests_execute.zig");
const stat_kernel = @import("freq_tests.zig");
const stat_render = @import("freq_tests_render.zig");
const risk_parse = @import("freq_risk_parse.zig");
const risk_exec = @import("freq_risk_execute.zig");
const risk_render = @import("freq_risk_render.zig");
const strat_parse = @import("freq_stratified_parse.zig");
const strat_exec = @import("freq_stratified_execute.zig");
const exact_public = @import("freq_exact_public.zig");
const exact_parse = @import("freq_exact_parse.zig");
pub const CountMatrix = table_model.CountMatrix;
pub const Table = table_model.Table;
pub const Score = table_model.Score;
const graph = @import("freq_plots.zig");
pub const Request = struct {
    plots: graph.Options = .{},
    exact: exact_parse.Options = .{},
    fisher: bool = false,
    statistics: stat_parse.Options = .{},
    risk: risk_parse.Options = .{},
    stratified: strat_parse.Options = .{},
    resolved_expected: stat_kernel.Expected = .equal,
    vars: []const []const u8 = &.{},
    missing: bool = false,
    missprint: bool = false,
    nocum: bool = false,
    noprint: bool = false,
    nofreq: bool = false,
    nopercent: bool = false,
    norow: bool = false,
    nocol: bool = false,
    list: bool = false,
    line_numbers: bool = false,
    table: bool = false, // SAS legacy marker: no effect with grid or LIST (controls2 oracle).
    crosslist: bool = false,
    sparse: bool = false,
    nosparse: bool = false,
    expected: bool = false,
    deviation: bool = false,
    cellchi2: bool = false,
    cumcol: bool = false,
    totpct: bool = false,
    pearsonres: bool = false,
    stdres: bool = false,
    out_name: ?[]const u8 = null,
    out_opts: []const Token = &.{},
    outcum: bool = false,
    outexpect: bool = false,
    outpct: bool = false,
    maxlevels: ?usize = null,
    count_format: ?[]const u8 = null,
    scores: Score = .table,
    scorout: bool = false,
};
const Options = struct {
    output: ?stat_output.Spec = null,
    exact: ?exact_parse.Options = null,
    tables_statement_count: usize = 0,
    tests: stat_parse.TestStatement = .{},
    agreement_tests: strat_parse.Tests = .{},
    order: FreqOrder = .internal,
    noprint: bool = false,
    nlevels: bool = false,
    weights: var_lists.NumericRole = .{},
    zeros: bool = false,
    formchar: [3]u8 = .{ '|', '-', '+' },
    bys: by_groups.Statements = .{},
    formats: std.ArrayList(VarSpec) = .empty,
    requests: std.ArrayList(Request) = .empty,
};
const Parser = struct {
    a: std.mem.Allocator,
    diags: *diag.Diagnostics,
    toks: []const Token,
    i: usize = 2,
    fn fail(self: *Parser, comptime msg: []const u8) diag.Error {
        return self.diags.fail(error.ParseError, self.toks[@min(self.i, self.toks.len - 1)].line, "PROC FREQ: " ++ msg, .{});
    }
    fn tag(self: *Parser, tag_: @import("../lexer.zig").Tag) bool {
        return atTag(self.toks, self.i, tag_);
    }
    fn kw(self: *Parser, kw_: []const u8) bool {
        return self.i < self.toks.len and tkKw(self.toks[self.i], kw_);
    }
    fn expect(self: *Parser, tag_: @import("../lexer.zig").Tag) diag.Error!void {
        if (!self.tag(tag_)) return self.fail("unexpected or missing token");
        self.i += 1;
    }
    fn dataset(self: *Parser) diag.Error![]const u8 {
        if (!self.tag(.name)) return self.fail("expected a dataset name");
        const first = self.toks[self.i].text;
        self.i += 1;
        if (self.tag(.dot) and atTag(self.toks, self.i + 1, .name)) {
            self.i += 2;
            return std.fmt.allocPrint(self.a, "{s}.{s}", .{ first, self.toks[self.i - 1].text });
        }
        return first;
    }
    fn datasetOptions(self: *Parser) diag.Error![]const Token {
        if (!self.tag(.lparen)) return &.{};
        const end = skipParen(self.toks, self.i);
        if (end <= self.i + 1 or self.toks[end - 1].tag != .rparen) return self.fail("unclosed OUT dataset options");
        const tokens = self.toks[self.i + 1 .. end - 1];
        if (tokens.len < 2 or tokens[0].tag != .name or tokens[1].tag != .eq) return self.fail("OUT dataset options require name=value");
        self.i = end;
        return tokens;
    }
    fn output(self: *Parser) diag.Error!stat_output.Spec {
        self.i += 1;
        var spec: stat_output.Spec = .{};
        while (!self.tag(.semicolon) and !self.tag(.eof)) {
            if (!self.tag(.name)) return self.fail("expected an OUTPUT statistic or OUT=");
            const tok = self.toks[self.i];
            self.i += 1;
            if (tkKw(tok, "out")) {
                try self.expect(.eq);
                spec.name = try self.dataset();
                spec.dataset_options = try self.datasetOptions();
            } else {
                const option = std.meta.stringToEnum(stat_output.Option, try std.ascii.allocLowerString(self.a, tok.text)) orelse return failGap(self.diags, tok.line, "PROC FREQ: OUTPUT statistic {s} is not supported", .{tok.text});
                spec.requested.insert(option);
            }
        }
        if (spec.requested.count() == 0) return failGap(self.diags, 0, "PROC FREQ: OUTPUT without explicit statistics is not supported", .{});
        return spec;
    }
    fn eqValue(self: *Parser) diag.Error!Token {
        try self.expect(.eq);
        if (!self.tag(.name) and !self.tag(.number) and !self.tag(.string)) return self.fail("expected an option value");
        const tok = self.toks[self.i];
        self.i += 1;
        return tok;
    }
    fn variable(self: *Parser, ds: *Dataset) diag.Error![][]const u8 {
        const names = try var_lists.next(self.a, ds, self.toks, &self.i, self.diags);
        for (names) |*name| {
            const ci = ds.indexOf(name.*) orelse return self.diags.fail(error.ParseError, self.toks[self.i - 1].line, "PROC FREQ: TABLES variable {s} not found", .{name.*});
            name.* = ds.columns.items[ci].name;
        }
        return names;
    }
    fn factor(self: *Parser, ds: *Dataset) diag.Error![][]const u8 {
        if (!self.tag(.lparen)) return self.variable(ds);
        self.i += 1;
        var names: std.ArrayList([]const u8) = .empty;
        while (!self.tag(.rparen)) {
            if (self.tag(.semicolon) or self.tag(.eof)) return self.fail("unclosed TABLES variable list");
            try names.appendSlice(self.a, try self.variable(ds));
        }
        self.i += 1;
        return names.items;
    }
    fn tables(self: *Parser, ds: *Dataset, opts: *Options) diag.Error!void {
        opts.tables_statement_count += 1;
        self.i += 1;
        var combos: std.ArrayList([]const []const u8) = .empty;
        while (!self.tag(.slash) and !self.tag(.semicolon) and !self.tag(.eof)) {
            var expanded: std.ArrayList([]const []const u8) = .empty;
            try expanded.append(self.a, &.{});
            while (true) {
                const names = try self.factor(ds);
                if (names.len == 0) {
                    if (combos.items.len > 0) return self.diags.fail(error.ParseError, 0, "Variable number 0 is not on file {s}.", .{try var_lists.datasetName(self.a, ds)});
                    return self.diags.fail(error.ParseError, 0, "A specification in the TABLES statement produces an empty variable list.", .{});
                }
                var next: std.ArrayList([]const []const u8) = .empty;
                // SAS varies the first parenthesized factor fastest (Table 3.8).
                for (names) |name| for (expanded.items) |previous| {
                    const combination = try self.a.alloc([]const u8, previous.len + 1);
                    @memcpy(combination[0..previous.len], previous);
                    combination[previous.len] = name;
                    try next.append(self.a, combination);
                };
                expanded = next;
                if (!self.tag(.star)) break;
                self.i += 1;
                if (!self.tag(.name) and !self.tag(.lparen)) return self.fail("expected a variable after '*' in the TABLES statement");
            }
            try combos.appendSlice(self.a, expanded.items);
        }
        var req = Request{};
        if (self.tag(.slash)) {
            self.i += 1;
            try self.tableOptions(&req);
        }
        try self.expect(.semicolon);
        if (req.sparse and req.nosparse) return self.fail("SPARSE and NOSPARSE cannot be specified together");
        if (!req.crosslist and req.stdres) try self.diags.report(.warning, 0, "The STDRES option is available only with the CROSSLIST option.", .{});
        if (!req.crosslist and req.pearsonres) try self.diags.report(.warning, 0, "The PEARSONRESID option is available only with the CROSSLIST option.", .{});
        if (req.list and req.crosslist) return self.fail("LIST and CROSSLIST cannot be specified together");
        if (combos.items.len == 0) return self.fail("TABLES requires at least one variable");
        for (combos.items, 0..) |combo, k| {
            var copy = req;
            copy.vars = combo;
            if (k + 1 < combos.items.len) copy.out_name = null;
            try opts.requests.append(self.a, copy);
        }
    }
    fn tableOptions(self: *Parser, req: *Request) diag.Error!void {
        while (!self.tag(.semicolon) and !self.tag(.eof)) {
            if (try strat_parse.consumeTableOption(self.toks, &self.i, &req.stratified, self.diags)) continue;
            if (self.kw("fisher")) {
                req.fisher = true;
                self.i += 1;
                continue;
            }
            if (self.kw("all")) {
                self.i += 1;
                req.statistics.chisq = true;
                req.statistics.measures = true;
                if (req.stratified.cmh == 0) req.stratified.cmh = 3;
                continue;
            }
            if (self.kw("plots")) {
                req.plots = try graph.parse(self.a, self.diags, self.toks, &self.i);
                continue;
            }
            if (try risk_parse.consumeTableOption(self.a, self.toks, &self.i, &req.risk, self.diags)) continue;
            if (try stat_parse.consumeTableOption(self.a, self.toks, &self.i, &req.statistics, self.diags)) continue;
            if (!self.tag(.name)) return self.fail("unexpected token in TABLES options");
            const raw_name = self.toks[self.i].text;
            const name = if (eqi(raw_name, "line")) "line_numbers" else if (eqi(raw_name, "score")) "scores" else if (eqi(raw_name, "pearsonresid")) "pearsonres" else if (eqi(raw_name, "stdresid")) "stdres" else raw_name;
            const lineno = self.toks[self.i].line;
            self.i += 1;
            var boolean = false;
            inline for (.{ "missing", "missprint", "nocum", "noprint", "nofreq", "nopercent", "norow", "nocol", "list", "line_numbers", "table", "crosslist", "sparse", "nosparse", "expected", "deviation", "cellchi2", "cumcol", "totpct", "pearsonres", "stdres", "outcum", "outexpect", "outpct", "scorout" }) |field| {
                if (eqi(name, field)) {
                    @field(req, field) = true;
                    boolean = true;
                }
            }
            if (boolean) {
                if (eqi(name, "crosslist") and self.tag(.lparen)) {
                    self.i += 1;
                    while (!self.tag(.rparen)) {
                        if ((self.kw("pearsonres") or self.kw("pearsonresid"))) req.pearsonres = true else if ((self.kw("stdres") or self.kw("stdresid"))) req.stdres = true else return self.fail("CROSSLIST accepts only PEARSONRES and STDRES");
                        self.i += 1;
                    }
                    self.i += 1;
                }
                if (self.tag(.eq) or self.tag(.lparen)) return self.fail("this TABLES option takes no value or suboptions");
                continue;
            }
            if (eqi(name, "out")) {
                try self.expect(.eq);
                req.out_name = try self.dataset();
                req.out_opts = try self.datasetOptions();
            } else if (eqi(name, "scores")) {
                const v = try self.eqValue();
                req.scores = std.meta.stringToEnum(Score, try std.ascii.allocLowerString(self.a, v.text)) orelse return self.fail("invalid SCORES value");
            } else if (eqi(name, "maxlevels")) {
                const v = try self.eqValue();
                const n = std.fmt.parseFloat(f64, v.text) catch return self.fail("MAXLEVELS requires a positive integer");
                if (!std.math.isFinite(n) or n < 1 or n != @trunc(n) or n >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return self.fail("MAXLEVELS requires a positive integer");
                req.maxlevels = @intFromFloat(n);
            } else if (eqi(name, "format")) {
                try self.expect(.eq);
                const start = self.i;
                if (!self.tag(.name) and !self.tag(.number)) return self.fail("FORMAT requires a numeric format");
                self.i += 1;
                if (self.tag(.dot)) {
                    self.i += 1;
                    if (self.tag(.number)) self.i += 1;
                } else if (self.toks[start].tag == .name and self.tag(.number) and std.mem.startsWith(u8, self.toks[self.i].text, ".")) {
                    // Like parser.tryFormatSpec, accept the lexer's dotted-number
                    // suffix: COMMA8.1 is a name followed by the number `.1`.
                    const decimals = self.toks[self.i].text[1..];
                    if (decimals.len == 0) return self.fail("FORMAT requires nonnegative integer decimals");
                    for (decimals) |c| if (!std.ascii.isDigit(c)) return self.fail("FORMAT requires nonnegative integer decimals");
                    self.i += 1;
                }
                var fmt: std.ArrayList(u8) = .empty;
                for (self.toks[start..self.i]) |tok| {
                    if (tok.tag == .dot) try fmt.append(self.a, '.') else try fmt.appendSlice(self.a, tok.text);
                }
                const parsed = format.parseSpec(fmt.items);
                if (parsed.w > 24 or parsed.is_char) return self.fail("FORMAT requires a numeric format with width at most 24");
                req.count_format = fmt.items;
            } else if (isUnsupportedFreqStat(name) or isFreqTablesGapOption(name)) {
                return failGap(self.diags, lineno, "PROC FREQ: TABLES option {s} is not yet supported", .{name});
            } else return self.diags.fail(error.ParseError, lineno, "PROC FREQ: TABLES option {s} is not supported", .{name});
        }
    }
};

pub fn runFreq(cx: ProcCtx, out: *std.ArrayList(u8), toks: []const Token) diag.Error!void {
    const a = cx.arena;
    var parser = Parser{ .a = a, .diags = cx.diags, .toks = toks };
    var opts = Options{};
    var input_name: ?[]const u8 = null;
    var page = false;
    var compress = false;
    while (!parser.tag(.semicolon) and !parser.tag(.eof)) {
        if (parser.kw("data")) {
            parser.i += 1;
            try parser.expect(.eq);
            input_name = try parser.dataset();
            if (parser.tag(.lparen)) parser.i = skipParen(toks, parser.i);
        } else if (parser.kw("order")) {
            parser.i += 1;
            const v = try parser.eqValue();
            opts.order = std.meta.stringToEnum(FreqOrder, try std.ascii.allocLowerString(a, v.text)) orelse return cx.diags.fail(error.ParseError, v.line, "PROC FREQ: ORDER={s} is not valid", .{v.text});
        } else if (parser.kw("noprint")) {
            opts.noprint = true;
            parser.i += 1;
        } else if (parser.kw("nlevels")) {
            opts.nlevels = true;
            parser.i += 1;
        } else if (parser.kw("page")) {
            page = true;
            parser.i += 1;
        } else if (parser.kw("compress")) {
            compress = true;
            parser.i += 1;
        } else if (parser.kw("formchar")) {
            parser.i += 1;
            var positions: std.ArrayList(usize) = .empty;
            if (parser.tag(.lparen)) {
                parser.i += 1;
                while (!parser.tag(.rparen)) {
                    if (!parser.tag(.number)) return parser.fail("FORMCHAR requires character positions");
                    try positions.append(a, std.fmt.parseInt(usize, toks[parser.i].text, 10) catch return parser.fail("invalid FORMCHAR position"));
                    parser.i += 1;
                    if (parser.tag(.comma)) parser.i += 1 else if (!parser.tag(.rparen)) return parser.fail("expected comma in FORMCHAR positions");
                }
                parser.i += 1;
            }
            const v = try parser.eqValue();
            if (v.tag != .string) return parser.fail("FORMCHAR requires a string");
            const used = [_]usize{ 1, 2, 7 };
            for (used, 0..) |pos, k| {
                const at = if (positions.items.len == 0) pos - 1 else std.mem.indexOfScalar(usize, positions.items, pos) orelse continue;
                if (at < v.text.len) opts.formchar[k] = v.text[at];
            }
        } else return cx.diags.fail(error.ParseError, toks[parser.i].line, "PROC FREQ: option {s} is not supported", .{toks[parser.i].text});
    }
    try parser.expect(.semicolon);
    if (page and compress) return parser.fail("PAGE and COMPRESS cannot be specified together");
    if (page or compress) return failGap(cx.diags, 0, "PROC FREQ: paginated PAGE/COMPRESS output is not supported by this listing destination", .{});
    const raw = (if (input_name) |n| cx.lib.find(n) else lastDataset(cx.lib)) orelse {
        try cx.diags.report(.err, 0, "File {s} does not exist", .{input_name orelse "_last_"});
        return;
    };
    var input = try procInput(a, raw, toks, cx.diags);
    while (!parser.tag(.eof) and !parser.kw("run")) {
        if (parser.tag(.semicolon)) {
            parser.i += 1; // Null statement: no request or TEST implication.
            continue;
        }
        if (parser.kw("tables") or parser.kw("table")) {
            try parser.tables(input, &opts);
            continue;
        }
        if (parser.kw("by")) {
            try opts.bys.read(a, toks, &parser.i);
        } else if (parser.kw("weight")) {
            parser.i += 1;
            const name = try var_lists.roleVariable(toks, parser.i, true, cx.diags);
            try opts.weights.add(a, input, name, cx.diags);
            parser.i += 1;
            if (parser.tag(.slash)) {
                parser.i += 1;
                if (!parser.kw("zeros")) return cx.diags.fail(error.ParseError, toks[parser.i].line, "PROC FREQ: WEIGHT option {s} is not supported — expected ZEROS", .{toks[parser.i].text});
                opts.zeros = true;
                parser.i += 1;
            }
        } else if (parser.kw("format")) {
            try parseProcFormat(a, toks, &parser.i, &opts.formats);
        } else if (parser.kw("where") or (parser.tag(.name) and @import("../parser.zig").isMidStepSkippable(toks[parser.i].text))) {
            while (!parser.tag(.semicolon) and !parser.tag(.eof)) parser.i += 1;
        } else if (parser.kw("test")) {
            parser.i += 1;
            const begin = parser.i;
            while (!parser.tag(.semicolon) and !parser.tag(.eof)) parser.i += 1;
            if (opts.tests.present) return parser.fail("Only one TEST statement is allowed.");
            var remaining: std.ArrayList(Token) = .empty;
            for (toks[begin..parser.i]) |token| {
                if (!strat_parse.consumeTest(token, &opts.agreement_tests)) try remaining.append(a, token);
            }
            if (remaining.items.len == 0 and begin != parser.i) opts.tests.present = true else try opts.tests.parse(remaining.items, cx.diags);
        } else if (parser.kw("exact")) {
            if (opts.exact != null) return parser.fail("Only one EXACT statement is allowed.");
            parser.i += 1;
            opts.exact = try exact_parse.statement(a, toks, &parser.i, cx.diags);
            continue;
        } else if (parser.kw("output")) {
            if (opts.output != null) return parser.fail("Only one OUTPUT statement is allowed.");
            opts.output = try parser.output();
        } else return cx.diags.fail(error.ParseError, toks[parser.i].line, "PROC FREQ statement {s} is not supported", .{toks[parser.i].text});
        try parser.expect(.semicolon);
    }
    // A TABLES statement can expand to several requests. SAS diagnoses each
    // final specification, including all invalid RISKDIFF/RELRISK nulls.
    const risk_messages = cx.diags.count();
    for (opts.requests.items) |req| try req.risk.validateTests(cx.diags);
    if (cx.diags.errSince(risk_messages)) return error.ParseError;
    if (opts.output != null and opts.tables_statement_count == 0) return parser.fail("OUTPUT requires a TABLES statement.");
    try opts.tests.finish(opts.tables_statement_count, cx.diags);
    var analysis = AnalysisState{};
    if (opts.exact) |e| {
        if (opts.tables_statement_count == 0) return parser.fail("EXACT requires a TABLES statement.");
        analysis.simulation_seed = if (e.seed > 0) @intCast(e.seed) else exact_public.clockSeed();
    }
    const pb = try opts.bys.resolve(a, input, cx.diags);
    if (opts.requests.items.len == 0) for (input.columns.items, 0..) |col, ci| {
        if (opts.weights.contains(ci)) continue;
        var isby = false;
        for (pb.names) |bn| if (eqi(bn, col.name)) {
            isby = true;
            break;
        };
        if (isby) continue;
        const names = try a.alloc([]const u8, 1);
        names[0] = col.name;
        try opts.requests.append(a, .{ .vars = names });
    };
    const statistical_options = try a.alloc(stat_parse.Options, opts.requests.items.len);
    for (opts.requests.items, 0..) |*req, index| {
        exact_public.resolve(req, opts.exact, opts.tables_statement_count);
        try exact_public.validateClRequests(req.*, cx.diags);
        stat_parse.implyTests(&req.statistics, opts.tests.requests, opts.tables_statement_count);
        strat_parse.implyTests(&req.stratified, opts.agreement_tests, opts.tables_statement_count);
        if (req.risk.difference) |rd| if (rd.common) {
            req.stratified.common.enabled = true;
            for (rd.cls) |cl| if (cl.method == .newcombe) {
                req.stratified.common.risk_newcombe = true;
            };
        };
        req.list = stat_parse.usesList(req.list, req.statistics);
        if (req.risk.any() or hasStratified(req.stratified) or req.exact.families.count() > 0) req.list = false;
        req.statistics.score_type = switch (req.scores) {
            .table => .table,
            .rank => .rank,
            .ridit => .ridit,
            .modridit => .modridit,
        };
        statistical_options[index] = req.statistics;
    }
    try stat_exec.validateSecondarySources(statistical_options, raw.name, cx.diags);
    for (opts.requests.items) |*req| {
        const secondary = if (stat_exec.secondaryName(req.statistics.expected)) |name|
            cx.lib.find(name) orelse return cx.diags.fail(error.ExecError, 0, "PROC FREQ: TESTP/TESTF dataset {s} does not exist", .{name})
        else
            null;
        if ((req.statistics.chisq or req.exact.families.contains(.pchi) or req.exact.families.contains(.lrchi)) and req.vars.len == 1) req.resolved_expected = try stat_exec.resolveExpected(a, req.statistics.expected, secondary, cx.diags);
        // Literal probabilities are syntax-level constraints even on two-way requests.
        if (req.statistics.expected == .proportions) {
            const values = req.statistics.expected.proportions;
            _ = stat_kernel.expectedFactor(values.len, 1, .{ .proportions = values }) catch return cx.diags.fail(error.ExecError, 0, "PROC FREQ: the sum of the TESTP probabilities must equal one or 100 percent", .{});
        }
    }
    const wc = opts.weights.first();
    const bc = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |bn, k| bc[k] = input.indexOf(bn) orelse return cx.diags.fail(error.ParseError, 0, "PROC FREQ: BY variable {s} not in {s}", .{ bn, input.name });
    if (opts.requests.items.len == 0)
        return cx.diags.fail(error.ParseError, 0, "No variables available for analysis after specification of BY variables and WEIGHT variable.", .{});
    if (opts.noprint and opts.output == null) {
        for (opts.requests.items) |req| {
            if (req.out_name != null) break;
        } else {
            try cx.diags.report(.note, 0, "Processing will terminate because there are no valid requests for displayed output or output data sets.", .{});
            return;
        }
    }
    input = try by_groups.withFormats(a, input, opts.formats.items);
    const slices = try by_groups.checkedSlices(a, input, bc, pb.desc, pb.notsorted, cx.diags);
    const groups = if (slices.len == 0) try bySlices(a, input.rows.items, &.{}) else slices;
    const outputs = try a.alloc(?*Dataset, opts.requests.items.len);
    @memset(outputs, null);
    const stats_writer = if (opts.output) |spec| try stat_output.create(cx, spec, opts.requests.items[opts.requests.items.len - 1], input, bc) else null;
    if (input.rows.items.len == 0) try cx.diags.report(.note, 0, "No observations in data set {s}.", .{input.name});
    for (groups, 1..) |group, by_number| {
        const listing_start = out.items.len;
        const messages = cx.diags.count();
        const noted_newcombe = analysis.noted_newcombe;
        var view = input.*;
        view.rows = .empty;
        for (group.rows) |row| if (weightKeepsRow(row, wc, opts.zeros)) {
            try view.rows.append(a, row);
        };
        const any = view.rows.items.len > 0;
        if (!any and group.rows.len > 0) try cx.diags.report(.note, 0, "{s} contains 0 observations with nonzero weights.", .{if (bc.len > 0) "BY group" else "Data set"});
        var fl: std.ArrayList(FmtLevels) = .empty;
        var vars: std.ArrayList([]const u8) = .empty;
        for (opts.requests.items) |req| for (req.vars) |vn| try vars.append(a, vn);
        view.columns = .{ .items = try a.dupe(@import("../dataset.zig").Column, input.columns.items), .capacity = input.columns.items.len };
        var analysis_wc = wc;
        if (wc) |ci| if (view.columns.items[ci].format != null) {
            var selected = false;
            for (vars.items) |vn| if (eqi(vn, view.columns.items[ci].name)) {
                selected = true;
                break;
            };
            if (selected) {
                analysis_wc = try view.addColumn("__FREQ_WEIGHT", .num);
                for (view.rows.items) |*row| {
                    const cells = try a.alloc(Value, row.*.len + 1);
                    @memcpy(cells[0..row.*.len], row.*);
                    cells[row.*.len] = row.*[ci];
                    row.* = cells;
                }
            }
        };
        const ds = try groupFormats(a, &view, vars.items, &.{}, &fl, cx.diags, .freq);
        var negative = false;
        for (view.rows.items) |row| if (rowWeight(row, wc) < 0) {
            negative = true;
            break;
        };
        if (negative) try cx.diags.report(.note, 0, "Percentages and other statistics are not computed because there are negative weights. Plots are not produced.", .{});
        if (any and !opts.noprint) if (group.rep) |row| try appendByHeading(a, out, &view, row, bc);
        if (any and opts.nlevels and !opts.noprint) try renderLevels(cx, out, ds, vars.items, opts.order, analysis_wc, opts.zeros, fl.items, &view, bc, group.rep);
        var rendered = any and opts.nlevels and !opts.noprint;
        for (opts.requests.items, 0..) |req, k| {
            const cols = try a.alloc(usize, req.vars.len);
            for (req.vars, 0..) |vn, j| cols[j] = ds.indexOf(vn).?;
            const output_cols = try uniqueColumns(a, cols);
            var tab = try computeTable(a, ds, cols, analysis_wc, opts.zeros, req.missing, opts.order, fl.items);
            tab.score_kind = req.scores;
            if (any and !opts.noprint and !req.noprint) if (cx.capture) |capture|
                try @import("ods_freq.zig").publish(a, cx.diags, capture, &view, bc, group.rep, &tab, req, opts.zeros);
            if (req.out_name) |name| {
                if (outputs[k] == null) for (cols, 0..) |ci, j| if (std.mem.indexOfScalar(usize, cols[0..j], ci) != null) try cx.diags.report(.warning, 0, "Variable {s} already exists on file {s}.", .{ ds.columns.items[ci].name, name });
                const part = try tableOutput(a, &view, ds, cols, fl.items, &tab, req, opts.zeros);
                if (outputs[k] == null) {
                    const combined = try a.create(Dataset);
                    combined.* = Dataset.init(a, name);
                    for (bc) |ci| try combined.columns.append(a, input.columns.items[ci]);
                    for (part.columns.items, 0..) |column, j| {
                        if (j < output_cols.len and std.mem.indexOfScalar(usize, bc, output_cols[j]) != null) continue;
                        try combined.columns.append(a, column);
                    }
                    outputs[k] = combined;
                }
                for (part.rows.items) |row| {
                    const cells = try a.alloc(Value, outputs[k].?.columns.items.len);
                    for (bc, 0..) |ci, j| cells[j] = group.rep.?[ci];
                    var next = bc.len;
                    for (row, 0..) |cell, j| {
                        if (j < output_cols.len and std.mem.indexOfScalar(usize, bc, output_cols[j]) != null) continue;
                        cells[next] = cell;
                        next += 1;
                    }
                    try outputs[k].?.appendRow(cells);
                }
            }
            if (!any) continue;
            if (!opts.noprint and (cx.graphics != null or req.plots.plots.len != 0)) {
                var by_text: std.ArrayList(u8) = .empty;
                if (bc.len > 0) if (group.rep) |row| try appendByHeading(a, &by_text, &view, row, bc);
                try graph.execute(cx, &tab, req, std.mem.trim(u8, by_text.items, " \n"), if (bc.len > 0) by_number else null, k + 1);
            }
            const writer = if (k + 1 == opts.requests.items.len) stats_writer else null;
            if (opts.noprint and writer == null) continue;
            const requested = hasStatistics(req.statistics) or req.risk.any() or hasStratified(req.stratified) or req.exact.families.count() > 0;
            const sufficient_levels = !requested or tab.negative or try hasInferenceLevels(&tab, cx.diags);
            if ((writer != null or requested) and sufficient_levels) {
                if (rendered and !opts.noprint) try out.append(a, '\n');
                const stratified = try strat_exec.compute(a, cx.diags, &tab, req.stratified, stratScope(req, opts));
                try analyzeTable(cx, out, &tab, req, opts, &analysis, stratified, writer, &view, bc, group.rep);
                if (!opts.noprint) rendered = true;
            } else if (!opts.noprint and !req.noprint) {
                if (rendered) try out.append(a, '\n');
                try renderTable(a, out, &tab, req, opts);
                rendered = true;
            }
        }
        if (out.items.len > listing_start) if (cx.listing_titles) |titles| {
            var heading: std.ArrayList(u8) = .empty;
            if (bc.len > 0 and group.rep != null) {
                const byvars = try a.alloc(@import("../sql.zig").Titles.ByVar, bc.len);
                for (bc, 0..) |ci, i| {
                    const column = view.columns.items[ci];
                    const value = group.rep.?[ci];
                    byvars[i] = .{
                        .name = column.name,
                        .label = if (column.label) |label| (if (label.len > 0) label else column.name) else column.name,
                        .value = if (column.format) |spec| std.mem.trim(u8, try format.apply(a, value, spec), " ") else try cellText(a, value),
                    };
                }
                try titles.emitTitlesBy(a, &heading, byvars);
            } else try titles.emitTitles(a, &heading);
            try out.insertSlice(a, listing_start, heading.items);
        };
        if (bc.len > 0 and (cx.diags.errSince(messages) or noted_newcombe != analysis.noted_newcombe)) if (group.rep) |row|
            try by_groups.reportNote(a, cx.diags, &view, row, bc);
    }
    for (opts.requests.items, 0..) |req, k| if (outputs[k]) |ds| {
        if (req.out_opts.len > 0) try io.applyDatasetOptions(a, ds, req.out_opts, cx.diags, false);
        try cx.lib.put(req.out_name.?, ds);
    };
    if (stats_writer) |writer| {
        try writer.finish();
        try io.applyDatasetOptions(a, writer.ds, opts.output.?.dataset_options, cx.diags, false);
        try cx.lib.put(writer.ds.name, writer.ds);
    }
}

/// Hash/eql on a single FREQ cell, kept consistent with `cmpValue == .eq`:
/// chars hash right-trimmed (cmpStr blank-pads), numerics canonicalize -0/+0
/// and hash a NaN by its missingRank (._ < . < .A < … groups like cmpNum).
const LevelValueCtx = struct {
    pub fn hash(_: LevelValueCtx, v: Value) u64 {
        var h = std.hash.Wyhash.init(0);
        switch (v) {
            .str => |s| h.update(std.mem.trimEnd(u8, s, " ")),
            .num => |x| {
                if (std.math.isNan(x)) {
                    h.update(&[_]u8{Value.missingRank(x)});
                } else {
                    const canon: f64 = if (x == 0) 0.0 else x;
                    const bits: u64 = @bitCast(canon);
                    h.update(std.mem.asBytes(&bits));
                }
            },
        }
        return h.final();
    }
    pub fn eql(_: LevelValueCtx, a: Value, b: Value) bool {
        return cmpValue(a, b) == .eq;
    }
};

const LevelIndex = std.HashMapUnmanaged(Value, usize, LevelValueCtx, std.hash_map.default_max_load_percentage);

const CountedLevel = struct {
    level: table_model.Level,
    display: Value,
    original_index: usize,

    fn less(order: FreqOrder, left: CountedLevel, right: CountedLevel) bool {
        const l = left.level;
        const r = right.level;
        if (l.missing != r.missing) return l.missing;
        if (l.missing) {
            if (l.value == .num and r.value == .num)
                return Value.missingChar(l.value.num) < Value.missingChar(r.value.num);
            return cmpValue(l.value, r.value) == .lt;
        }
        return switch (order) {
            .data => left.original_index < right.original_index,
            .internal => cmpValue(l.raw, r.raw) == .lt,
            .formatted => cmpValue(left.display, right.display) == .lt,
            .freq => if (l.frequency != r.frequency) l.frequency > r.frequency else cmpValue(left.display, right.display) == .lt,
        };
    }
};

const ColumnLevels = struct {
    levels: []table_model.Level,
    by_value: LevelIndex,
};

fn appendByHeading(a: std.mem.Allocator, out: *std.ArrayList(u8), ds: *Dataset, row: []const Value, cols: []const usize) !void {
    // Use labels for display only; grouping, variable lookup and output metadata
    // retain the original names. Reuse shared BY formatting/NOBYLINE handling.
    var display = ds.*;
    display.columns = .{ .items = try a.dupe(@import("../dataset.zig").Column, ds.columns.items), .capacity = ds.columns.items.len };
    for (cols) |ci| if (display.columns.items[ci].label) |label| {
        if (label.len > 0) display.columns.items[ci].name = label;
    };
    try by_groups.appendLine(a, out, &display, row, cols);
}

fn needsDefaultLevelFormat(ds: *Dataset, col: usize, order: FreqOrder) bool {
    if (ds.columns.items[col].type != .num) return false;
    if (order == .formatted or order == .freq) return true;
    // Small whole numbers have distinct BEST12. fields. Internal and input
    // order need no formatted keys when the entire column has this property.
    for (ds.rows.items) |row| {
        const x = row[col].num;
        if (!std.math.isNan(x) and (x != @trunc(x) or @abs(x) >= 1e11)) return true;
    }
    return false;
}

/// Accumulate weights in input order. A numerical column with no assigned
/// format uses BEST12. for level identity and displayed order in SAS 9.4M9.
/// Keep the lowest observed raw value for scores and output. Cache every raw
/// key so repeated observations need neither formatting nor another scan.
fn columnLevels(a: std.mem.Allocator, ds: *Dataset, col: usize, order: FreqOrder, wc: ?usize, zeros: bool, fl: ?FmtLevels) !ColumnLevels {
    var counts: std.ArrayList(CountedLevel) = .empty;
    var by_value: LevelIndex = .empty;
    var by_default_display: std.StringHashMapUnmanaged(usize) = .empty;
    const default_format = needsDefaultLevelFormat(ds, col, order);
    for (ds.rows.items) |row| {
        if (!weightKeepsRow(row, wc, zeros)) continue;
        const value = row[col];
        const entry = try by_value.getOrPut(a, value);
        if (!entry.found_existing) {
            const raw = if (fl) |f| fmtRawFor(f, value.str) orelse value else value;
            var display = value;
            var index = counts.items.len;
            if (default_format and !isMissing(value)) {
                display = .{ .str = try format.apply(a, value, "BEST12.") };
                const formatted = try by_default_display.getOrPut(a, display.str);
                if (formatted.found_existing) {
                    index = formatted.value_ptr.*;
                    if (cmpValue(raw, counts.items[index].level.raw) == .lt) {
                        counts.items[index].level.value = value;
                        counts.items[index].level.raw = raw;
                    }
                } else formatted.value_ptr.* = index;
            }
            if (index == counts.items.len) try counts.append(a, .{
                .level = .{ .value = value, .raw = raw, .missing = isMissing(raw), .frequency = 0 },
                .display = display,
                .original_index = index,
            });
            entry.value_ptr.* = index;
        }
        counts.items[entry.value_ptr.*].level.frequency += rowWeight(row, wc);
    }
    std.mem.sort(CountedLevel, counts.items, order, CountedLevel.less);
    const levels = try a.alloc(table_model.Level, counts.items.len);
    const sorted_index = try a.alloc(usize, counts.items.len);
    for (counts.items, 0..) |counted, i| {
        levels[i] = counted.level;
        sorted_index[counted.original_index] = i;
    }
    var iter = by_value.valueIterator();
    while (iter.next()) |index| index.* = sorted_index[index.*];
    return .{ .levels = levels, .by_value = by_value };
}

/// Signed FREQ weight; missing weights are removed before counting.
fn rowWeight(r: []const Value, wcol: ?usize) f64 {
    const wc = wcol orelse return 1;
    const w = switch (r[wc]) {
        .num => |x| x,
        .str => std.math.nan(f64),
    };
    return if (!std.math.isNan(w)) w else 0;
}

/// Frequency text: a whole weighted count renders as an integer (the usual case,
/// including unweighted); a fractional weight sum renders via BEST12.
fn freqText(arena: std.mem.Allocator, x: f64) ![]const u8 {
    if (x == @trunc(x) and @abs(x) < 1e15) return std.fmt.allocPrint(arena, "{d}", .{@as(i64, @intFromFloat(x))});
    return format.bestNum(arena, x);
}

/// SAS prints `Frequency Missing = N` after the table when the TABLES
/// variable(s) had any missing values (a no-op when there were none). N is the
/// WEIGHTED frequency under a WEIGHT statement — the chapter's own worked
/// example counts one missing obs with Freq=2 as `Frequency Missing = 2`
/// (Figure 3.12, p.157).
fn appendFreqMissing(arena: std.mem.Allocator, out: *std.ArrayList(u8), miss: f64) !void {
    if (miss == 0) return;
    try out.append(arena, '\n');
    try out.appendSlice(arena, try std.fmt.allocPrint(arena, "{s}Frequency Missing = {s}\n", .{ " " ** 6, try freqText(arena, miss) }));
}

// ── freq helpers ────────────────────────────────────────────────────────────

/// ORDER=FREQ uses descending weighted counts and formatted values for ties.
pub const FreqOrder = enum { internal, freq, data, formatted };

/// FREQ level membership under a WEIGHT: SAS drops an obs whose weight is
/// zero or missing, so a level seen ONLY on such obs never appears;
/// ZEROS retains zero-weight observations. Negative weights remain signed.
fn weightKeepsRow(r: []const Value, wcol: ?usize, zeros: bool) bool {
    const wc = wcol orelse return true;
    return switch (r[wc]) {
        .num => |x| !std.math.isNan(x) and (x != 0 or zeros),
        .str => false, // missing weight — excluded either way, as SAS does
    };
}

// ── Table computation and output datasets ───────────────────────────────────
pub fn computeTable(a: std.mem.Allocator, ds: *Dataset, cols: []const usize, wc: ?usize, zeros: bool, missing: bool, order: FreqOrder, formats: []const FmtLevels) !Table {
    const dims = try a.alloc(table_model.Dimension, cols.len);
    const maps = try a.alloc(LevelIndex, cols.len);
    @memset(maps, .empty);
    for (cols, 0..) |ci, d| {
        const fl = fmtLevelsFor(formats, ci);
        const counted = try columnLevels(a, ds, ci, order, wc, zeros, fl);
        maps[d] = counted.by_value;
        dims[d] = .{ .name = ds.columns.items[ci].name, .label = ds.columns.items[ci].label, .levels = counted.levels };
    }
    var tab = try Table.init(a, dims, missing);
    for (ds.rows.items) |row| {
        if (!weightKeepsRow(row, wc, zeros)) continue;
        var key: usize = 0;
        for (cols, 0..) |ci, d| key += maps[d].get(row[ci]).? * tab.strides[d];
        try tab.add(a, key, rowWeight(row, wc));
    }
    return tab;
}
fn uniqueColumns(a: std.mem.Allocator, cols: []const usize) ![]usize {
    var result: std.ArrayList(usize) = .empty;
    for (cols) |ci| if (std.mem.indexOfScalar(usize, result.items, ci) == null) {
        try result.append(a, ci);
    };
    return result.items;
}
fn tableOutput(a: std.mem.Allocator, raw: *Dataset, ds: *Dataset, cols: []const usize, formats: []const FmtLevels, tab: *Table, req: Request, zeros: bool) !*Dataset {
    const output = try a.create(Dataset);
    output.* = Dataset.init(a, req.out_name.?);
    const output_cols = try uniqueColumns(a, cols);
    for (output_cols) |ci| {
        var meta = raw.columns.items[ci];
        if (fmtLevelsFor(formats, ci)) |fl| {
            meta.format = fl.spec;
            meta.type = fl.ty;
        }
        meta.name = ds.columns.items[ci].name;
        try output.columns.append(a, meta);
    }
    _ = try output.addColumn("COUNT", .num);
    const nway = cols.len > 1;
    const cum = req.outcum and !nway;
    if (req.outexpect and nway) _ = try output.addColumn("EXPECTED", .num);
    _ = try output.addColumn("PERCENT", .num);
    if (req.outpct and nway) {
        if (cols.len > 2) _ = try output.addColumn("PCT_TABL", .num);
        _ = try output.addColumn("PCT_ROW", .num);
        _ = try output.addColumn("PCT_COL", .num);
    }
    if (cum) {
        _ = try output.addColumn("CUM_FREQ", .num);
        _ = try output.addColumn("CUM_PCT", .num);
    }
    for (output.columns.items[output_cols.len..]) |*column| {
        column.len = 8;
        column.label = if (eqi(column.name, "COUNT")) "Frequency Count" else if (eqi(column.name, "PERCENT")) "Percent of Total Frequency" else if (eqi(column.name, "EXPECTED")) "Expected Frequency Under Independence" else if (eqi(column.name, "PCT_ROW")) "Percent of Row Frequency" else if (eqi(column.name, "PCT_COL")) "Percent of Column Frequency" else if (eqi(column.name, "PCT_TABL")) "Percent of 2-Way Table Frequency" else if (eqi(column.name, "CUM_FREQ")) "Cumulative Frequency Count" else "Cumulative Percent";
    }
    const keys = try tab.keys(a, nway and !req.nosparse and (req.sparse or zeros), !nway);
    var cumulative: f64 = 0;
    var cached_stratum: ?usize = null;
    var slice: table_model.Slice = undefined;
    for (keys) |key| {
        const count = tab.count(key);
        const excluded = tab.excluded(key);
        var cells: std.ArrayList(Value) = .empty;
        for (cols, 0..) |ci, d| if (std.mem.indexOfScalar(usize, cols[0..d], ci) == null) {
            try cells.append(a, tab.level(key, d).raw);
        };
        try cells.append(a, .{ .num = count });
        if (nway) {
            const nr = tab.dimensions[cols.len - 2].levels.len;
            const nc = tab.dimensions[cols.len - 1].levels.len;
            const stratum = key / (nr * nc);
            if (cached_stratum == null or cached_stratum.? != stratum) {
                slice = try tab.slice(a, stratum);
                cached_stratum = stratum;
            }
            const metrics = slice.basicMetrics(key / nc % nr, key % nc);
            if (req.outexpect) try cells.append(a, .{ .num = if (excluded) table_model.nan else metrics.expected });
            try cells.append(a, .{ .num = tab.pct(key) });
            if (req.outpct) {
                if (cols.len > 2) try cells.append(a, .{ .num = if (excluded) table_model.nan else metrics.percent });
                try cells.append(a, .{ .num = if (excluded) table_model.nan else metrics.row_percent });
                try cells.append(a, .{ .num = if (excluded) table_model.nan else metrics.col_percent });
            }
        } else {
            try cells.append(a, .{ .num = tab.pct(key) });
            if (!excluded) cumulative += count;
            if (cum) {
                try cells.append(a, .{ .num = if (excluded) table_model.nan else cumulative });
                try cells.append(a, .{ .num = if (excluded or tab.negative) table_model.nan else percent(cumulative, tab.total) });
            }
        }
        try output.appendRow(cells.items);
    }
    return output;
}

// ── Listing rendering ──────────────────────────────────────────────────────
fn renderLevels(cx: ProcCtx, out: *std.ArrayList(u8), ds: *Dataset, vars: []const []const u8, order: FreqOrder, wc: ?usize, zeros: bool, formats: []const FmtLevels, source: *const Dataset, by: []const usize, rep: ?[]const Value) !void {
    const a = cx.arena;
    var names: std.ArrayList([]const u8) = .empty;
    var totals: std.ArrayList(usize) = .empty;
    var misses: std.ArrayList(usize) = .empty;
    var any_missing = false;
    var labelwidth: usize = 0;
    for (vars) |vn| if (ds.indexOf(vn)) |ci| if (ds.columns.items[ci].label) |label| {
        labelwidth = @max(labelwidth, label.len + 2);
    };
    for (vars) |vn| {
        var seen = false;
        for (names.items) |name| if (eqi(name, vn)) {
            seen = true;
            break;
        };
        if (seen) continue;
        const ci = ds.indexOf(vn).?;
        const fl = fmtLevelsFor(formats, ci);
        const levels = (try columnLevels(a, ds, ci, order, wc, zeros, fl)).levels;
        var nmiss: usize = 0;
        for (levels) |level| if (level.missing) {
            nmiss += 1;
        };
        try names.append(a, vn);
        try totals.append(a, levels.len);
        try misses.append(a, nmiss);
        any_missing = any_missing or nmiss > 0;
    }
    if (cx.capture) |capture| try @import("ods_freq_tests.zig").levels(a, cx.diags, capture, source, by, rep, names.items, totals.items, misses.items);
    try out.appendSlice(a, NLEVELS_TITLE);
    try out.append(a, '\n');
    const title = try line(a, 64);
    putLeft(title, 17, "Number of Variable Levels");
    try flush(a, out, title);
    try out.append(a, '\n');
    if (any_missing) {
        const b = try line(a, 72 + labelwidth);
        putLeft(b, 33 + labelwidth, "Missing");
        putLeft(b, 47 + labelwidth, "Nonmissing");
        try flush(a, out, b);
    }
    const header = try line(a, 72 + labelwidth);
    putLeft(header, 12, "Variable");
    if (labelwidth > 0) putLeft(header, 24, "Label");
    putRight(header, 29 + labelwidth, "Levels");
    if (any_missing) {
        putRight(header, 41 + labelwidth, "Levels");
        putRight(header, 57 + labelwidth, "Levels");
    }
    try flush(a, out, header);
    for (names.items, totals.items, misses.items) |name, n, m| {
        const b = try line(a, 72 + labelwidth);
        putLeft(b, 12, name);
        if (labelwidth > 0) if (ds.columns.items[ds.indexOf(name).?].label) |label| putLeft(b, 24, label);
        putRight(b, 29 + labelwidth, try std.fmt.allocPrint(a, "{d}", .{n}));
        if (any_missing) {
            putRight(b, 41 + labelwidth, try std.fmt.allocPrint(a, "{d}", .{m}));
            putRight(b, 57 + labelwidth, try std.fmt.allocPrint(a, "{d}", .{n - m}));
        }
        try flush(a, out, b);
    }
}
fn renderTable(a: std.mem.Allocator, out: *std.ArrayList(u8), tab: *Table, req: Request, opts: Options) !void {
    if (tab.dimensions.len == 1) return renderOne(a, out, tab, req);
    if (req.list) return renderList(a, out, tab, req, opts.zeros);
    const n = tab.dimensions.len;
    const nr = tab.dimensions[n - 2].levels.len;
    const nc = tab.dimensions[n - 1].levels.len;
    if (nr == 0 or nc == 0) return;
    var number: usize = 0;
    for (0..tab.cell_count / (nr * nc)) |stratum| {
        var hidden = false;
        for (0..n - 2) |d| if (!req.missing and !req.missprint and tab.level(stratum * nr * nc, d).missing) {
            hidden = true;
            break;
        };
        if (hidden) continue;
        number += 1;
        if (number > 1) try out.append(a, '\n');
        const slice = try tab.slice(a, stratum);
        if (req.crosslist) try renderCross(a, out, slice, req, number, opts.zeros) else try renderGrid(a, out, slice, req, opts.formchar, if (n > 2) number else 0, opts.zeros);
    }
}
fn shown(l: table_model.Level, req: Request) bool {
    return req.missing or req.missprint or !l.missing;
}
fn renderOne(a: std.mem.Allocator, out: *std.ArrayList(u8), tab: *Table, req: Request) !void {
    if (req.statistics.chisq and req.resolved_expected != .equal and tab.total > 0 and !tab.negative) return renderOneExpected(a, out, tab, req);
    const levels = tab.dimensions[0].levels;
    const no_pct = req.nopercent or tab.negative;
    // NOFREQ/NOROW/NOCOL are crosstab-only options in SAS (oracle controls).
    if (no_pct or req.nocum) try out.appendSlice(a, ONEWAY_NOCUM_TITLE) else try out.appendSlice(a, ONEWAY_TITLE);
    try out.append(a, '\n');
    if (tab.dimensions[0].label) |label| {
        const b = try line(a, @max(72, label.len + 28));
        putLeft(b, 15, label);
        try flush(a, out, b);
        try out.append(a, '\n');
    }

    var label_width: usize = 14;
    for (levels) |l| if (shown(l, req)) {
        label_width = @max(label_width, (try cellText(a, l.value)).len + 1);
    };
    var shift = label_width - 14;
    if (tab.dimensions[0].name.len > 7) shift = @max(shift, tab.dimensions[0].name.len - 7);
    for (levels, 0..) |l, k| if (shown(l, req)) {
        const needed = (try cellText(a, l.value)).len + (try freqText(a, tab.count(k))).len + 1;
        if (needed > 16) shift = @max(shift, needed - 16);
    };
    if (!req.nocum) {
        const b = try line(a, 72 + shift);
        putLeft(b, (if (no_pct) @as(usize, 36) else 43) + shift, "Cumulative");
        if (!no_pct) putLeft(b, 57 + shift, "Cumulative");
        try flush(a, out, b);
    }
    const header = try line(a, 72 + shift);
    putLeft(header, 15, tab.dimensions[0].name);
    putLeft(header, (if (req.nocum and !no_pct) @as(usize, 24) else 22) + shift, "Frequency");
    if (!no_pct) putLeft(header, (if (req.nocum) @as(usize, 38) else 36) + shift, "Percent");
    if (!req.nocum) {
        putLeft(header, (if (no_pct) @as(usize, 36) else 48) + shift, "Frequency");
        if (!no_pct) putLeft(header, 63 + shift, "Percent");
    }
    try flush(a, out, header);
    const rule = try line(a, 72 + shift);
    const end = if (no_pct) (if (req.nocum) @as(usize, 30) else 45) else (if (req.nocum) @as(usize, 47) else 69);
    @memset(rule[14 .. end + shift], '-');
    try flush(a, out, rule);
    var cumulative: f64 = 0;
    var displayed: usize = 0;
    var truncated = false;
    for (levels, 0..) |l, key| {
        if (!shown(l, req)) continue;
        const excluded = tab.excluded(key);
        if (!excluded) {
            if (req.maxlevels) |max| if (displayed >= max) {
                truncated = true;
                continue;
            };
            displayed += 1;
            cumulative += tab.count(key);
        }
        const b = try line(a, 72 + shift);
        putLeft(b, 15, try cellText(a, l.value));
        putRight(b, 30 + shift, try freqText(a, tab.count(key)));
        if (!no_pct) putRight(b, 42 + shift, try pctText(a, tab.pct(key)));
        if (!req.nocum) {
            putRight(b, (if (no_pct) @as(usize, 45) else 57) + shift, if (excluded) "." else try freqText(a, cumulative));
            if (!no_pct) putRight(b, 70 + shift, try pctText(a, if (excluded) table_model.nan else percent(cumulative, tab.total)));
        }
        try flush(a, out, b);
    }
    if (truncated) {
        var has_missing = false;
        for (levels) |l| if (l.missing) {
            has_missing = true;
            break;
        };
        const qualifier = if (!req.missing and has_missing) "nonmissing " else "";
        if (req.maxlevels.? == 1) try out.appendSlice(a, try std.fmt.allocPrint(a, "\n      The first {s}level is displayed.\n", .{qualifier})) else try out.appendSlice(a, try std.fmt.allocPrint(a, "\n      The first {d} {s}levels are displayed.\n", .{ req.maxlevels.?, qualifier }));
    }
    if (!req.missing) try appendFreqMissing(a, out, tab.missing);
}
fn renderList(a: std.mem.Allocator, out: *std.ArrayList(u8), tab: *Table, req: Request, zeros: bool) !void {
    try out.appendSlice(a, ONEWAY_TITLE);
    try out.append(a, '\n');
    const n = tab.dimensions.len;
    const widths = try a.alloc(usize, n);
    var varwidth: usize = if (req.line_numbers) 22 else 14;
    for (tab.dimensions, 0..) |dim, d| {
        widths[d] = @max(4, dim.name.len + 2);
        for (dim.levels) |l| widths[d] = @max(widths[d], (try cellText(a, l.value)).len + 2);
        varwidth += widths[d];
    }
    const no_pct = req.nopercent or tab.negative;
    const keys = try tab.keys(a, !req.nosparse and (req.sparse or zeros), false);
    var count_width: usize = 10;
    var cumulative_width: usize = 15;
    var running: f64 = 0;
    for (keys) |key| {
        count_width = @max(count_width, (try freqText(a, tab.count(key))).len + 1);
        if (!tab.excluded(key)) running += tab.count(key);
        cumulative_width = @max(cumulative_width, (try freqText(a, running)).len + 1);
    }
    const freq_right = varwidth + count_width;
    const pct_right = freq_right + 12;
    const cum_right = (if (no_pct) freq_right else pct_right) + cumulative_width;
    const cp_right = cum_right + 13;
    const width = cp_right + 12;
    if (!req.nocum) {
        const b = try line(a, width);
        putLeft(b, (if (no_pct) freq_right else pct_right) + 4, "Cumulative");
        if (!no_pct) putLeft(b, cum_right + 3, "Cumulative");
        try flush(a, out, b);
    }
    const header = try line(a, width);
    var pos: usize = if (req.line_numbers) 23 else 15;
    if (req.line_numbers) putLeft(header, 15, "Line");
    for (tab.dimensions, 0..) |dim, d| {
        putLeft(header, pos, dim.name);
        pos += widths[d];
    }
    putRight(header, freq_right, "Frequency");
    if (!no_pct) putRight(header, pct_right, "Percent");
    if (!req.nocum) {
        putRight(header, cum_right, "Frequency");
        if (!no_pct) putRight(header, cp_right, "Percent");
    }
    try flush(a, out, header);
    const rule = try line(a, width);
    @memset(rule[14 .. width - 1], '-');
    try flush(a, out, rule);
    var cumulative: f64 = 0;
    var row_number: usize = 0;
    for (keys) |key| {
        const excluded = tab.excluded(key);
        if (excluded and !req.missprint) continue;
        if (!excluded) cumulative += tab.count(key);
        const b = try line(a, width);
        row_number += 1;
        if (req.line_numbers) putRight(b, 20, try std.fmt.allocPrint(a, "{d}", .{row_number}));
        pos = if (req.line_numbers) 23 else 15;
        for (0..n) |d| {
            putLeft(b, pos, try cellText(a, tab.level(key, d).value));
            pos += widths[d];
        }
        putRight(b, freq_right, try freqText(a, tab.count(key)));
        if (!no_pct) putRight(b, pct_right, try pctText(a, tab.pct(key)));
        if (!req.nocum) {
            putRight(b, cum_right, if (excluded) "." else try freqText(a, cumulative));
            if (!no_pct) putRight(b, cp_right, try pctText(a, if (excluded) table_model.nan else percent(cumulative, tab.total)));
        }
        try flush(a, out, b);
    }
    if (!req.missing) try appendFreqMissing(a, out, tab.missing);
}
const CellStat = enum { frequency, expected, deviation, chi2, totpct, percent, row, col, cumcol, pearson, standardized };
fn statLabel(s: CellStat) []const u8 {
    return switch (s) {
        .frequency => "Frequency",
        .expected => "Expected",
        .deviation => "Deviation",
        .chi2 => "Cell Chi-Square",
        .totpct => "Tot Pct",
        .percent => "Percent",
        .row => "Row Pct",
        .col => "Col Pct",
        .cumcol => "Cumulative Col%",
        .pearson => "Pearson Residual",
        .standardized => "Std Residual",
    };
}
fn activeStats(a: std.mem.Allocator, req: Request, negative: bool, nway: bool, cross: bool) ![]CellStat {
    var stats: std.ArrayList(CellStat) = .empty;
    if (!req.nofreq) try stats.append(a, .frequency);
    if (negative) return stats.items;
    if (req.expected) try stats.append(a, .expected);
    if (req.deviation) try stats.append(a, .deviation);
    if (cross and req.stdres) try stats.append(a, .standardized);
    if (cross and req.pearsonres) try stats.append(a, .pearson);
    if (req.cellchi2) try stats.append(a, .chi2);
    if (req.totpct and nway) try stats.append(a, .totpct);
    if (!req.nopercent) try stats.append(a, .percent);
    if (!req.norow) try stats.append(a, .row);
    if (!req.nocol) try stats.append(a, .col);
    if (req.cumcol and !cross) try stats.append(a, .cumcol);
    return stats.items;
}
fn statValue(sl: table_model.Slice, r: usize, c: usize, s: CellStat) f64 {
    const m = if (s == .cumcol) sl.metrics(r, c) else sl.basicMetrics(r, c);
    return switch (s) {
        .frequency => sl.count(r, c),
        .expected => m.expected,
        .deviation => m.deviation,
        .chi2 => m.chi2,
        .totpct => m.total_percent,
        .percent => m.percent,
        .row => m.row_percent,
        .col => m.col_percent,
        .cumcol => m.cumcol,
        .pearson => m.pearson,
        .standardized => m.standardized,
    };
}
fn statText(a: std.mem.Allocator, v: f64, s: CellStat, req: Request, cross: bool) ![]const u8 {
    if (std.math.isNan(v)) return ".";
    if (s == .frequency or s == .expected or s == .deviation) {
        if (!cross) if (req.count_format) |fmt| return format.apply(a, .{ .num = v }, fmt);
        if (s == .frequency) return freqText(a, v);
    }
    const text = try switch (s) {
        .frequency => unreachable,
        .expected, .deviation, .chi2, .pearson, .standardized => format.apply(a, .{ .num = v }, if (cross and v != 0) "12.4" else "best6."),
        else => pctText(a, v),
    };
    return std.mem.trim(u8, text, " ");
}
fn warningLocation(a: std.mem.Allocator, sl: table_model.Slice, number: usize) ![]const u8 {
    const dims = sl.table.dimensions;
    const n = dims.len;
    const r = dims[n - 2].name;
    const c = dims[n - 1].name;
    if (n == 2) return std.fmt.allocPrint(a, " for the table of {s} by {s}", .{ r, c });
    var location: std.ArrayList(u8) = .empty;
    try location.appendSlice(a, try std.fmt.allocPrint(a, " for Table {d} of {s} by {s}, controlling for", .{ number, r, c }));
    try appendControlValues(a, &location, sl);
    return location.items;
}
fn appendControlValues(a: std.mem.Allocator, out: *std.ArrayList(u8), sl: table_model.Slice) !void {
    const dims = sl.table.dimensions;
    const offset = sl.stratum * sl.rows().len * sl.cols().len;
    for (dims[0 .. dims.len - 2], 0..) |dim, i| {
        const value = try cellText(a, sl.table.level(offset, i).value);
        try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}={s}", .{ dim.name, value }));
    }
}
fn tableHeading(a: std.mem.Allocator, out: *std.ArrayList(u8), sl: table_model.Slice, number: usize, cross: bool) !void {
    const dims = sl.table.dimensions;
    const n = dims.len;
    if (number <= 1) try out.appendSlice(a, TWOWAY_TITLE);
    try out.append(a, '\n');
    const title = if (number == 0 or cross) try std.fmt.allocPrint(a, "Table of {s} by {s}", .{ dims[n - 2].name, dims[n - 1].name }) else try std.fmt.allocPrint(a, "Table {d} of {s} by {s}", .{ number, dims[n - 2].name, dims[n - 1].name });
    const b = try line(a, @max(60, 25 + title.len));
    putLeft(b, 25, title);
    try flush(a, out, b);
    if (n > 2) {
        var control: std.ArrayList(u8) = .empty;
        try control.appendSlice(a, "Controlling for");
        try appendControlValues(a, &control, sl);
        const cb = try line(a, @max(60, 25 + control.items.len));
        putLeft(cb, 25, control.items);
        try flush(a, out, cb);
    }
    try out.append(a, '\n');
}
fn selectedLevels(a: std.mem.Allocator, levels: []const table_model.Level, req: Request) ![]usize {
    var indices: std.ArrayList(usize) = .empty;
    for (levels, 0..) |l, i| if (shown(l, req)) {
        try indices.append(a, i);
    };
    return indices.items;
}
fn gridRule(a: std.mem.Allocator, out: *std.ArrayList(u8), nc: usize, labelwidth: usize, colwidth: usize, chars: [3]u8) !void {
    const b = try line(a, 16 + labelwidth + colwidth * (nc + 1));
    @memset(b[14 .. 14 + labelwidth], chars[1]);
    for (0..nc) |c| {
        const pos = 14 + labelwidth + c * colwidth;
        b[pos] = chars[2];
        @memset(b[pos + 1 .. pos + colwidth], chars[1]);
    }
    b[14 + labelwidth + nc * colwidth] = chars[2];
    try flush(a, out, b);
}
fn renderGrid(a: std.mem.Allocator, out: *std.ArrayList(u8), sl: table_model.Slice, req: Request, chars: [3]u8, number: usize, zeros: bool) !void {
    const rows = try selectedLevels(a, sl.rows(), req);
    const cols = try selectedLevels(a, sl.cols(), req);
    if (rows.len == 0 or cols.len == 0) {
        try out.appendSlice(a, TWOWAY_TITLE);
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nFor {s} * {s}\nall data are missing because\nall levels of variable {s} are missing.\n", .{ sl.table.dimensions[sl.table.dimensions.len - 2].name, sl.table.dimensions[sl.table.dimensions.len - 1].name, if (rows.len == 0) sl.table.dimensions[sl.table.dimensions.len - 2].name else sl.table.dimensions[sl.table.dimensions.len - 1].name }));
        return;
    }
    if (!zeros and sl.table.dimensions.len == 2 and !req.missing and !req.missprint and sl.total == 0 and sl.missing != 0 and !sl.table.negative) {
        try out.appendSlice(a, TWOWAY_TITLE);
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nTable of {s} by {s}\n\nSample Size = 0\n", .{ sl.table.dimensions[0].name, sl.table.dimensions[1].name }));
        try appendFreqMissing(a, out, sl.missing);
        return;
    }
    try tableHeading(a, out, sl, number, false);
    if (!zeros and (!sl.observed or (!req.missing and !req.missprint and sl.total == 0 and sl.missing != 0 and !sl.table.negative))) {
        try out.appendSlice(a, "Sample Size = 0\n");
        try appendFreqMissing(a, out, sl.missing);
        return;
    }
    const stats = try activeStats(a, req, sl.table.negative, sl.table.dimensions.len > 2, false);
    var labelwidth: usize = 9;
    for (stats) |s| labelwidth = @max(labelwidth, statLabel(s).len);
    // SAS wraps the row stub at 16 characters rather than widening the grid.
    for (rows) |r| labelwidth = @max(labelwidth, @min(16, (try cellText(a, sl.rows()[r].value)).len) + 1);
    var colwidth: usize = 9;
    for (cols) |c| colwidth = @max(colwidth, (try cellText(a, sl.cols()[c].value)).len + 2);
    if (req.count_format) |fmt| {
        colwidth = @max(colwidth, (try format.apply(a, .{ .num = 12345.67 }, fmt)).len + 2);
    }
    var frequencies = sl.table.counts.valueIterator();
    while (frequencies.next()) |v| colwidth = @max(colwidth, (try statText(a, v.*, .frequency, req, false)).len + 2);
    for (sl.row_totals) |v| colwidth = @max(colwidth, (try statText(a, v, .frequency, req, false)).len + 2);
    for (sl.col_totals) |v| colwidth = @max(colwidth, (try statText(a, v, .frequency, req, false)).len + 2);
    colwidth = @max(colwidth, (try statText(a, sl.total, .frequency, req, false)).len + 2);
    const width = @max(60, 16 + labelwidth + colwidth * (cols.len + 1));
    const sep0 = 15 + labelwidth;
    const rd = sl.table.dimensions[sl.table.dimensions.len - 2];
    const cd = sl.table.dimensions[sl.table.dimensions.len - 1];
    const rn = if (rd.label) |label| try std.fmt.allocPrint(a, "{s}({s})", .{ rd.name, label }) else rd.name;
    const cn = if (cd.label) |label| try std.fmt.allocPrint(a, "{s}({s})", .{ cd.name, label }) else cd.name;
    // The variable heading can be wider than its data levels. Keep both names
    // intact without widening the frequency cells (STAT-FREQ-001 oracle).
    const column_heading = if (15 + rn.len >= sep0 + 1) 15 + rn.len + 5 else sep0 + 1;
    const labels = try line(a, @max(width, @max(15 + rn.len, column_heading + cn.len)));
    putLeft(labels, 15, rn);
    putLeft(labels, column_heading, cn);
    try flush(a, out, labels);
    try out.append(a, '\n');
    for (stats, 0..) |s, k| {
        const b = try line(a, width);
        putLeft(b, 15, statLabel(s));
        b[sep0 - 1] = chars[0];
        if (k + 1 == stats.len) {
            for (0..cols.len + 1) |c| b[sep0 - 1 + c * colwidth] = chars[0];
            for (cols, 0..) |c, j| putLeft(b, sep0 + 1 + j * colwidth, try cellText(a, sl.cols()[c].value));
            putRight(b, sep0 + cols.len * colwidth + colwidth - 2, "Total");
        }
        try flush(a, out, b);
    }
    if (stats.len == 0) {
        const b = try line(a, width);
        for (0..cols.len + 1) |c| b[sep0 - 1 + c * colwidth] = chars[0];
        for (cols, 0..) |c, j| putLeft(b, sep0 + 1 + j * colwidth, try cellText(a, sl.cols()[c].value));
        putRight(b, sep0 + cols.len * colwidth + colwidth - 2, "Total");
        try flush(a, out, b);
    }
    try gridRule(a, out, cols.len, labelwidth, colwidth, chars);
    var row_cum: f64 = 0;
    for (rows) |r| {
        const row_missing = !req.missing and sl.rows()[r].missing;
        if (!row_missing) row_cum += sl.row_totals[r];
        const row_label = try cellText(a, sl.rows()[r].value);
        const stub_width = labelwidth - 1;
        const label_lines = (row_label.len + stub_width - 1) / stub_width;
        const line_count = if (stats.len == 0) 0 else @max(stats.len, label_lines);
        for (0..line_count) |k| {
            const b = try line(a, width);
            const label_start = @min(k * stub_width, row_label.len);
            putLeft(b, 15, row_label[label_start..@min(label_start + stub_width, row_label.len)]);
            for (0..cols.len + 1) |c| b[sep0 - 1 + c * colwidth] = chars[0];
            if (k >= stats.len) {
                try flush(a, out, b);
                continue;
            }
            const s = stats[k];
            for (cols, 0..) |c, j| putRight(b, sep0 + j * colwidth + colwidth - 2, try statText(a, statValue(sl, r, c, s), s, req, false));
            const v: f64 = switch (s) {
                .frequency => if (row_missing) table_model.nan else sl.row_totals[r],
                .percent => if (row_missing) table_model.nan else percent(sl.row_totals[r], sl.total),
                .totpct => percent(sl.row_totals[r], sl.table.total),
                .cumcol => if (row_missing) table_model.nan else percent(row_cum, sl.total),
                else => table_model.nan,
            };
            if (s == .frequency or s == .percent or s == .totpct or s == .cumcol) putRight(b, sep0 + cols.len * colwidth + colwidth - 2, try statText(a, v, s, req, false));
            try flush(a, out, b);
        }
        try gridRule(a, out, cols.len, labelwidth, colwidth, chars);
    }
    var first = true;
    var marginals: std.ArrayList(CellStat) = .empty;
    try marginals.append(a, .frequency);
    for (stats) |stat| if (stat == .totpct or stat == .percent) {
        try marginals.append(a, stat);
    };
    for (marginals.items) |s| {
        if (s != .frequency and s != .percent and s != .totpct) continue;
        const b = try line(a, width);
        if (first) putLeft(b, 15, "Total");
        first = false;
        for (cols, 0..) |c, j| {
            const v = if (!req.missing and sl.cols()[c].missing) table_model.nan else if (s == .frequency) sl.col_totals[c] else percent(sl.col_totals[c], if (s == .totpct) sl.table.total else sl.total);
            putRight(b, sep0 + j * colwidth + colwidth - 2, try statText(a, v, s, req, false));
        }
        const total = if (s == .frequency) sl.total else percent(sl.total, if (s == .totpct) sl.table.total else sl.total);
        putRight(b, sep0 + cols.len * colwidth + colwidth - 2, try statText(a, total, s, req, false));
        try flush(a, out, b);
    }
    if (!req.missing) try appendFreqMissing(a, out, sl.missing);
}
fn renderCross(a: std.mem.Allocator, out: *std.ArrayList(u8), sl: table_model.Slice, req: Request, number: usize, zeros: bool) !void {
    const show_cells = sl.observed or zeros;
    try tableHeading(a, out, sl, if (sl.table.dimensions.len > 2) number else 0, show_cells);
    if (!show_cells) {
        try out.appendSlice(a, "Sample Size = 0\n");
        return;
    }
    const stats = try activeStats(a, req, sl.table.negative, sl.table.dimensions.len > 2, true);
    const rows = try selectedLevels(a, sl.rows(), req);
    const cols = try selectedLevels(a, sl.cols(), req);
    var rw: usize = 8;
    var cw: usize = 8;
    for (rows) |r| rw = @max(rw, (try cellText(a, sl.rows()[r].value)).len + 2);
    for (cols) |c| cw = @max(cw, (try cellText(a, sl.cols()[c].value)).len + 2);
    const widths = try a.alloc(usize, stats.len);
    var width = 14 + rw + cw;
    for (stats, 0..) |s, k| {
        widths[k] = @max(13, statLabel(s).len + 2);
        if (s == .frequency) {
            var it = sl.table.counts.valueIterator();
            while (it.next()) |v| widths[k] = @max(widths[k], (try freqText(a, v.*)).len + 2);
            for (sl.row_totals) |v| widths[k] = @max(widths[k], (try freqText(a, v)).len + 2);
            for (sl.col_totals) |v| widths[k] = @max(widths[k], (try freqText(a, v)).len + 2);
            widths[k] = @max(widths[k], (try freqText(a, sl.total)).len + 2);
        }
        width += widths[k];
    }
    const header = try line(a, width);
    putLeft(header, 15, sl.table.dimensions[sl.table.dimensions.len - 2].name);
    putLeft(header, 15 + rw, sl.table.dimensions[sl.table.dimensions.len - 1].name);
    var pos = 14 + rw + cw;
    for (stats, 0..) |s, k| {
        pos += widths[k];
        putRight(header, pos, statLabel(s));
    }
    try flush(a, out, header);
    const rule = try line(a, width);
    @memset(rule[14..], '-');
    try flush(a, out, rule);
    for (rows) |r| {
        if (req.nosparse) {
            var any_cell = false;
            for (cols) |c| if (sl.count(r, c) != 0) {
                any_cell = true;
                break;
            };
            if (!any_cell) continue;
        }
        var first = true;
        for (cols) |c| {
            if (req.nosparse and sl.count(r, c) == 0) continue;
            const b = try line(a, width);
            if (first) putLeft(b, 15, try cellText(a, sl.rows()[r].value));
            first = false;
            putLeft(b, 15 + rw, try cellText(a, sl.cols()[c].value));
            pos = 14 + rw + cw;
            for (stats, 0..) |s, k| {
                pos += widths[k];
                putRight(b, pos, try statText(a, statValue(sl, r, c, s), s, req, true));
            }
            try flush(a, out, b);
        }
        if ((req.missing or !sl.rows()[r].missing) and (!req.nosparse or sl.row_totals[r] != 0)) {
            const b = try line(a, width);
            putLeft(b, 15 + rw, "Total");
            pos = 14 + rw + cw;
            for (stats, 0..) |s, k| {
                pos += widths[k];
                const value = switch (s) {
                    .frequency => sl.row_totals[r],
                    .percent => percent(sl.row_totals[r], sl.total),
                    .totpct => percent(sl.row_totals[r], sl.table.total),
                    .row => percent(sl.row_totals[r], sl.row_totals[r]),
                    else => continue,
                };
                putRight(b, pos, try statText(a, value, s, req, true));
            }
            try out.append(a, '\n');
            try flush(a, out, b);
        }
        try flush(a, out, rule);
    }
    var first = true;
    for (cols) |c| {
        if (!req.missing and sl.cols()[c].missing) continue;
        const b = try line(a, width);
        if (first) putLeft(b, 15, "Total");
        first = false;
        putLeft(b, 15 + rw, try cellText(a, sl.cols()[c].value));
        pos = 14 + rw + cw;
        for (stats, 0..) |s, k| {
            pos += widths[k];
            const value = switch (s) {
                .frequency => sl.col_totals[c],
                .percent => percent(sl.col_totals[c], sl.total),
                .totpct => percent(sl.col_totals[c], sl.table.total),
                .col => percent(sl.col_totals[c], sl.col_totals[c]),
                else => continue,
            };
            putRight(b, pos, try statText(a, value, s, req, true));
        }
        try flush(a, out, b);
    }
    const total = try line(a, width);
    putLeft(total, 15 + rw, "Total");
    pos = 14 + rw + cw;
    for (stats, 0..) |s, k| {
        pos += widths[k];
        const value = switch (s) {
            .frequency => sl.total,
            .percent => percent(sl.total, sl.total),
            .totpct => percent(sl.total, sl.table.total),
            else => continue,
        };
        putRight(total, pos, try statText(a, value, s, req, true));
    }
    try out.append(a, '\n');
    try flush(a, out, total);
    try flush(a, out, rule);
    if (!req.missing) try appendFreqMissing(a, out, sl.missing);
}

test "FREQ default BEST12 levels combine raw values and break frequency ties by display" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    const minimum = 0.123456789012345;
    for ([_]f64{ 0.123456789045678, -10, 2, 12, minimum, -2, 0.123456789012355 }) |raw| {
        try ds.appendRow(&.{.{ .num = raw }});
    }
    const orders = [_]struct { mode: FreqOrder, values: [5]f64 }{
        .{ .mode = .data, .values = .{ minimum, -10, 2, 12, -2 } },
        .{ .mode = .internal, .values = .{ -10, -2, minimum, 2, 12 } },
        .{ .mode = .formatted, .values = .{ 2, -2, 12, -10, minimum } },
        .{ .mode = .freq, .values = .{ minimum, 2, -2, 12, -10 } },
    };
    for (orders) |order| {
        const table = try computeTable(a, &ds, &.{0}, null, false, false, order.mode, &.{});
        try std.testing.expectEqual(order.values.len, table.dimensions[0].levels.len);
        for (table.dimensions[0].levels, order.values, 0..) |level, expected, i| {
            try std.testing.expectEqual(expected, level.raw.num);
            try std.testing.expectEqual(@as(f64, if (expected == minimum) 3 else 1), table.count(i));
        }
    }
}

test "FREQ table puts missing levels in display order for every sort mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("g", .num);
    for ("_AZ.A") |symbol| try ds.appendRow(&.{Value.specialMissing(symbol)});
    for ([_]FreqOrder{ .data, .internal, .formatted, .freq }) |mode| {
        const table = try computeTable(a, &ds, &.{0}, null, false, true, mode, &.{});
        for (table.dimensions[0].levels, ".AZ_") |level, expected| {
            try std.testing.expectEqual(expected, Value.missingChar(level.raw.num));
        }
    }
}

test "TABLES FORMAT named decimals preserve weighted counts and width boundaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "r", "c", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 3 }, .{ 1, 2, 1 }, .{ 2, 1, 2 }, .{ 2, 2, 4 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    try lib.put("d", ds);

    // SAS 9.4 FREQ manual p.121: numeric formats, width <=24. Live SAS
    // evidence: /tmp/opensas-review-fixes/BUG-freqformatdecimal/case*.{sas,txt,log}.
    // COMMA8.1 displays cells 3.0,1.0,2.0,4.0 and total 10.0, no warnings/errors.
    const Case = struct { spec: []const u8, places: usize };
    for ([_]Case{
        .{ .spec = "comma8.1", .places = 1 },
        .{ .spec = "CoMmA8.2", .places = 2 },
        .{ .spec = "comma8.0", .places = 0 },
        .{ .spec = "comma8.", .places = 0 },
        .{ .spec = "8.1", .places = 1 },
        .{ .spec = "8.", .places = 0 },
        .{ .spec = "comma24.1", .places = 1 },
        .{ .spec = "24.1", .places = 1 },
    }) |case| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const src = try std.fmt.allocPrint(a, "proc freq data=d; weight w; tables r*c / format={s} nopercent norow nocol; run;", .{case.spec});
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, src, &d));
        try std.testing.expect(!d.hasErrors());
        // Inspect frequency rows, not percentage substrings; verify all four
        // cells and margins so truncating/ignoring the suffix cannot pass.
        var lines = std.mem.splitScalar(u8, out.items, '\n');
        var checked: usize = 0;
        const expected = [_][3]usize{ .{ 3, 1, 4 }, .{ 2, 4, 6 }, .{ 5, 5, 10 } };
        while (lines.next()) |raw| {
            const row = std.mem.trim(u8, raw, " ");
            if (!std.mem.startsWith(u8, row, "1 ") and !std.mem.startsWith(u8, row, "2 ") and !std.mem.startsWith(u8, row, "Total ")) continue;
            var cells = std.mem.tokenizeAny(u8, row, " |\t");
            _ = cells.next();
            try std.testing.expect(checked < expected.len);
            for (expected[checked]) |n| {
                const suffix: []const u8 = switch (case.places) {
                    0 => "",
                    1 => ".0",
                    else => ".00",
                };
                try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{d}{s}", .{ n, suffix }), cells.next() orelse "");
            }
            checked += 1;
        }
        try std.testing.expectEqual(@as(usize, 3), checked);
    }
    for ([_][]const u8{ "comma25.1", "25.1", "$8.", "-8.1", "comma8.-1", "comma8.1.2", "comma8.1e2" }) |spec| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        const src = try std.fmt.allocPrint(a, "proc freq data=d; weight w; tables r*c / format={s}; run;", .{spec});
        try std.testing.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, src, &d)));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(!diag.gapHit());
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "table syntax rejects invalid SAS and keeps destination gaps explicit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
    try lib.put("d", ds);
    for ([_][]const u8{ "tables x / (chisq);", "tables x / missing=0;", "tables x*y / list crosslist;", "tables x*y / sparse nosparse;", "tables x / maxlevels=0;", "tables x*y / format=30.;", "tables;", "tables x / out=o(chisq);", "tables x / crosslist(bogus);", ";;tablse x;;", ";;tables;;", ";;weight;;" }) |statement| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        const src = try std.fmt.allocPrint(a, "proc freq data=d; {s} run;", .{statement});
        try std.testing.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, src, &d)));
        try std.testing.expect(d.hasErrors());
        try std.testing.expect(!diag.gapHit());
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
    for ([_][]const u8{ "proc freq data=d page;tables x;run;", "proc freq data=d compress;tables x;run;", "proc freq data=d;tables x*y / contents='label';run;" }) |src| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        diag.resetGap();
        try std.testing.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, src, &d)));
        try std.testing.expect(diag.gapHit());
    }
}

test "BUG-freqnullstmt null statements preserve tables defaults weights BY and TEST implication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "b", "x", "y", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 1, 1, 1, 3 }, .{ 1, 1, 2, 1 }, .{ 1, 2, 1, 2 }, .{ 1, 2, 2, 4 }, .{ 2, 1, 1, 1 }, .{ 2, 2, 2, 3 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] } });
    try lib.put("d", ds);

    // Equivalent live SAS programs and output:
    // /tmp/opensas-review-r2-fixes/BUG-freqnullstmt/{weighted_by,defaults,all_defaults,test_one,test_two,test_zero}.*
    // Null statements must not affect the literal TABLES count used by TEST.
    const Case = struct { body: []const u8, gamma: bool = false, warning: bool = false };
    for ([_]Case{
        .{ .body = "tables x;" },
        .{ .body = "tables x;weight w;by b;" },
        .{ .body = "weight w;by b;" },
        .{ .body = "" },
        .{ .body = "tables x*y;test gamma;weight w;", .gamma = true },
        .{ .body = "tables x*y;tables x*y;test gamma;weight w;" },
        .{ .body = "test gamma;weight w;by b;", .warning = true },
    }) |case| {
        var expected: std.ArrayList(u8) = .empty;
        var expected_diags = diag.Diagnostics.init(a);
        const clean = try std.fmt.allocPrint(a, "proc freq data=d;{s}run;", .{case.body});
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &expected_diags }, &expected, try @import("../lexer.zig").tokenize(a, clean, &expected_diags));
        try std.testing.expect(expected.items.len > 0);
        try std.testing.expectEqual(case.gamma, std.mem.indexOf(u8, expected.items, "Gamma") != null);
        try std.testing.expectEqual(@as(usize, if (case.warning) 1 else 0), expected_diags.list.items.len);
        if (case.warning) try std.testing.expectEqualStrings("When you specify a TEST statement, you must also specify a TABLES statement.", expected_diags.list.items[0].message);

        // Insert multiple null statements before, between and after statements.
        var padded: std.ArrayList(u8) = .empty;
        for (clean) |ch| {
            try padded.append(a, ch);
            if (ch == ';') try padded.appendSlice(a, ";;");
        }
        var actual: std.ArrayList(u8) = .empty;
        var actual_diags = diag.Diagnostics.init(a);
        try runFreq(.{ .arena = a, .lib = &lib, .diags = &actual_diags }, &actual, try @import("../lexer.zig").tokenize(a, padded.items, &actual_diags));
        try std.testing.expectEqualStrings(expected.items, actual.items);
        try std.testing.expectEqual(expected_diags.list.items.len, actual_diags.list.items.len);
        for (expected_diags.list.items, actual_diags.list.items) |want, got| {
            try std.testing.expectEqual(want.severity, got.severity);
            try std.testing.expectEqualStrings(want.message, got.message);
        }
    }
}

test "default TABLES exclude BY and WEIGHT; OUT metadata and last Cartesian request" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "b", "x1", "x2", "w" }) |n| _ = try ds.addColumn(n, .num);
    ds.columns.items[1].label = "Category label";
    ds.columns.items[1].informat = "8.";
    ds.columns.items[1].len = 8;
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 10 }, .{ .num = 20 }, .{ .num = 2 } });
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, "proc freq data=d;by b;weight w;run;", &d));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "The FREQ Procedure"));
    out.clearRetainingCapacity();
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, "proc freq data=d noprint;by b;weight w;tables (x2 x1)*(x2 w) / out=o outpct outexpect;run;", &d));
    const o = lib.find("o").?;
    try std.testing.expectEqualStrings("b", o.columns.items[0].name);
    try std.testing.expectEqualStrings("x1", o.columns.items[1].name);
    try std.testing.expectEqualStrings("w", o.columns.items[2].name);
    try std.testing.expectEqualStrings("Category label", o.columns.items[1].label.?);
    try std.testing.expectEqualStrings("8.", o.columns.items[1].informat.?);
    try std.testing.expectEqual(@as(?usize, 8), o.columns.items[1].len);
    try std.testing.expectEqualStrings("Expected Frequency Under Independence", o.columns.items[4].label.?);
    try std.testing.expectEqual(@as(f64, 100), o.rows.items[0][5].num);
}

test "typed global levels, sparse strata, negative suppression and weighted score API" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "g", "h", "r", "c", "w" }) |n| _ = try ds.addColumn(n, .num);
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = 10 }, .{ .num = 2 }, .{ .num = 3 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 2 }, .{ .num = 20 }, .{ .num = 4 }, .{ .num = 1 } });
    var tab = try computeTable(a, &ds, &.{ 0, 1, 2, 3 }, 4, false, false, .internal, &.{});
    tab.score_kind = .ridit;
    try std.testing.expectEqual(@as(usize, 16), tab.cell_count);
    try std.testing.expectEqual(@as(f64, 75), tab.pct(0));
    try std.testing.expectEqual(@as(f64, 25), tab.pct(15));
    const empty = try tab.slice(a, 1);
    try std.testing.expect(!empty.observed);
    try std.testing.expectEqual(@as(f64, 0), empty.total);
    const matrix = (try tab.matrix(a, 0)).?;
    try std.testing.expectEqualSlices(f64, &.{ 3, 0, 0, 0 }, matrix.matrix.counts);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0 / 3.0), matrix.matrix.row_scores.?[0], 1e-12);
    try tab.add(a, 0, -1);
    try std.testing.expect((try tab.matrix(a, 0)) == null);
    try std.testing.expect(std.math.isNan(tab.pct(0)));
}

test "table Cartesian ordering, padded ranges and parsed score types" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "x01", "x02", "x03", "x04" }) |n| _ = try ds.addColumn(n, .num);
    var d = diag.Diagnostics.init(a);
    for ([_][]const u8{ "TABLE", "RANK", "RIDIT", "MODRIDIT" }, [_]Score{ .table, .rank, .ridit, .modridit }) |name, score| {
        const src = try std.fmt.allocPrint(a, "tables (x01-x02)*(x03--x04) / score={s} out=result;", .{name});
        var parser = Parser{ .a = a, .diags = &d, .toks = try @import("../lexer.zig").tokenize(a, src, &d), .i = 0 };
        var options = Options{};
        try parser.tables(&ds, &options);
        try std.testing.expectEqual(@as(usize, 4), options.requests.items.len);
        const requests = options.requests.items;
        try std.testing.expectEqualStrings("x01", requests[0].vars[0]);
        try std.testing.expectEqualStrings("x03", requests[0].vars[1]);
        try std.testing.expectEqualStrings("x02", requests[1].vars[0]);
        try std.testing.expectEqualStrings("x03", requests[1].vars[1]);
        try std.testing.expectEqualStrings("x01", requests[2].vars[0]);
        try std.testing.expectEqualStrings("x04", requests[2].vars[1]);
        try std.testing.expectEqualStrings("x02", requests[3].vars[0]);
        try std.testing.expectEqualStrings("x04", requests[3].vars[1]);
        for (requests, 0..) |request, k| {
            try std.testing.expectEqual(score, request.scores);
            try std.testing.expectEqual(k == 3, request.out_name != null);
        }
    }
}

test "STAT-FREQ-001 grid headings preserve long variable names above short levels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ "Internship", "LongRowVariableNameBeyondCellWidth" }) |row_name| {
        var ds = Dataset.init(a, "d");
        _ = try ds.addColumn(row_name, .num);
        _ = try ds.addColumn("Enrollment", .num);
        try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 } });
        var tab = try computeTable(a, &ds, &.{ 0, 1 }, null, false, false, .internal, &.{});
        var out: std.ArrayList(u8) = .empty;
        try renderTable(a, &out, &tab, .{}, .{});
        const heading = try std.fmt.allocPrint(a, "{s}     Enrollment\n", .{row_name});
        try std.testing.expect(std.mem.indexOf(u8, out.items, heading) != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Col Pct  |2       |  Total") != null);
    }
}

test "STAT-FREQ-004 long row levels wrap without dropping text or moving cell counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("Exposure", .char);
    _ = try ds.addColumn("Response", .char);
    _ = try ds.addColumn("Count", .num);
    ds.columns.items[1].label = "Heart Disease";
    for ([_]f64{ 11, 4, 2, 6 }, 0..) |count, i| try ds.appendRow(&.{
        .{ .str = if (i < 2) "High Cholesterol Diet" else "Low Cholesterol Diet" },
        .{ .str = if (i % 2 == 0) "Yes" else "No" },
        .{ .num = count },
    });
    var tab = try computeTable(a, &ds, &.{ 0, 1 }, 2, false, false, .data, &.{});
    var out: std.ArrayList(u8) = .empty;
    try renderTable(a, &out, &tab, .{}, .{});
    for ([_][]const u8{
        "Exposure          Response(Heart Disease)",
        "High Cholesterol |     11 |      4 |     15",
        " Diet            |  47.83 |  17.39 |  65.22",
        "Low Cholesterol  |      2 |      6 |      8",
        "Diet             |   8.70 |  26.09 |  34.78",
    }) |row| try std.testing.expect(std.mem.indexOf(u8, out.items, row) != null);
}

test "CROSSLIST numeric columns do not overwrite neighboring counts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "r", "c", "w" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ .{ .num = 10 }, .{ .num = 2 }, .{ .num = 3 } });
    try ds.appendRow(&.{ .{ .num = 10 }, .{ .num = 4 }, .{ .num = 1 } });
    try ds.appendRow(&.{ .{ .num = 20 }, .{ .num = 2 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 20 }, .{ .num = 4 }, .{ .num = 4 } });
    var tab = try computeTable(a, &ds, &.{ 0, 1 }, 2, false, false, .internal, &.{});
    var out: std.ArrayList(u8) = .empty;
    try renderTable(a, &out, &tab, .{ .crosslist = true, .expected = true, .deviation = true, .cellchi2 = true, .pearsonres = true, .stdres = true }, .{});
    var lines = std.mem.splitScalar(u8, out.items, '\n');
    var found = false;
    while (lines.next()) |row| {
        var words = std.mem.tokenizeAny(u8, row, " ");
        const first = words.next() orelse continue;
        if (!std.mem.eql(u8, first, "10")) continue;
        try std.testing.expectEqualStrings("2", words.next().?);
        try std.testing.expectEqualStrings("3", words.next().?);
        try std.testing.expectEqualStrings("2.0000", words.next().?);
        try std.testing.expectEqualStrings("1.0000", words.next().?);
        found = true;
        break;
    }
    try std.testing.expect(found);
}

test "MISSPRINT controlling missing: conditional TOTPCT differs from OUT PERCENT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "d");
    for ([_][]const u8{ "g", "r", "c", "w" }) |name| _ = try ds.addColumn(name, .num);
    try ds.appendRow(&.{ Value.missing, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 3 } });
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 2 }, .{ .num = 2 }, .{ .num = 1 } });
    var tab = try computeTable(a, &ds, &.{ 0, 1, 2 }, 3, false, false, .internal, &.{});
    try std.testing.expectEqual(@as(f64, 4), tab.total);
    try std.testing.expect(std.math.isNan(tab.pct(0)));
    const sl = try tab.slice(a, 0);
    try std.testing.expectEqual(@as(f64, 50), sl.basicMetrics(0, 0).total_percent);
    try std.testing.expectEqual(@as(f64, 100), sl.basicMetrics(0, 0).percent);
}

fn hasStatistics(opts: stat_parse.Options) bool {
    return opts.chisq or opts.measures or opts.plcorr;
}
/// Level eligibility is shared by the strata of this table. A retained zero
/// marginal count in a full-size table is checked separately for each stratum.
fn hasInferenceLevels(tab: *const Table, d: *diag.Diagnostics) !bool {
    const n = tab.dimensions.len;
    if (n < 2) return true;
    const dims = tab.dimensions[n - 2 ..][0..2];
    var counts = [2]usize{ 0, 0 };
    for (dims, 0..) |dim, i| {
        for (dim.levels) |level| {
            if (tab.include_missing or !level.missing) counts[i] += 1;
            if (counts[i] == 2) break;
        }
    }
    if (counts[0] == 0 or counts[1] == 0) {
        try d.report(.note, 0, "No statistics are computed for {s} * {s} because all data are missing.", .{ dims[0].name, dims[1].name });
        return false;
    }
    for (counts, dims) |count, dim| if (count == 1) {
        try d.report(.note, 0, "No statistics are computed for {s} * {s} because {s} has fewer than 2 nonmissing levels.", .{ dims[0].name, dims[1].name, dim.name });
        return false;
    };
    return true;
}

fn inferenceMatrix(m: CountMatrix) stat_kernel.CountMatrix {
    return .{ .rows = m.rows, .cols = m.cols, .counts = m.counts, .row_scores = m.row_scores, .col_scores = m.col_scores };
}
fn scoreDisplay(a: std.mem.Allocator, tab: *Table, scored: table_model.ScoredMatrix) !stat_render.ScoreDisplay {
    const rows = try a.alloc([]const u8, scored.row_levels.len);
    const cols = try a.alloc([]const u8, scored.col_levels.len);
    for (scored.row_levels, 0..) |l, i| rows[i] = try cellText(a, l.value);
    for (scored.col_levels, 0..) |l, i| cols[i] = try cellText(a, l.value);
    return .{ .row_name = tab.dimensions[tab.dimensions.len - 2].name, .col_name = tab.dimensions[tab.dimensions.len - 1].name, .row_labels = rows, .col_labels = cols };
}
fn riskTable(a: std.mem.Allocator, tab: *Table, scored: table_model.ScoredMatrix, one_way: bool, legacy_risks_printed: bool) !risk_exec.Table {
    const rows = try a.alloc([]const u8, scored.row_levels.len);
    const cols = try a.alloc([]const u8, scored.col_levels.len);
    for (scored.row_levels, 0..) |l, i| rows[i] = try cellText(a, l.value);
    for (scored.col_levels, 0..) |l, i| cols[i] = try cellText(a, l.value);
    return .{ .name = tab.dimensions[if (one_way) 0 else tab.dimensions.len - 2].name, .column_name = if (one_way) "" else tab.dimensions[tab.dimensions.len - 1].name, .row_labels = rows, .col_labels = cols, .counts = scored.matrix.counts, .one_way = one_way, .legacy_risks_printed = legacy_risks_printed };
}
/// Statistics execution is independent of TABLES display suppression. Buffers
/// keep each displayed table adjacent to its own stratum's statistical results.
fn hasStratified(options: strat_parse.Options) bool {
    return options.cmh > 0 or options.trend or options.jt or options.agreement.enabled or options.common.enabled or options.gail_simon;
}
fn stratScope(req: Request, opts: Options) strat_exec.Scope {
    var tests = opts.agreement_tests;
    tests.kappa = tests.kappa or req.exact.families.contains(.kappa);
    tests.weighted_kappa = tests.weighted_kappa or req.exact.families.contains(.wtkappa);
    return .{ .alpha = req.statistics.alpha, .tests = tests, .inherited_risk_column = if (req.risk.difference != null and req.risk.difference.?.column == 1 and !req.risk.difference.?.both_columns) .second else .first };
}
pub fn analysisStrata(a: std.mem.Allocator, table: *const Table) ![]usize {
    const n = table.dimensions.len;
    const size = table.dimensions[n - 2].levels.len * table.dimensions[n - 1].levels.len;
    var ids: std.ArrayList(usize) = .empty;
    for (try table.keys(a, false, true)) |key| {
        const id = key / size;
        if (ids.items.len == 0 or ids.items[ids.items.len - 1] != id) try ids.append(a, id);
    }
    return ids.toOwnedSlice(a);
}

const AnalysisState = struct {
    simulation_seed: u64 = 1,
    noted_newcombe: bool = false,
};
fn analyzeTable(cx: ProcCtx, out: *std.ArrayList(u8), tab: *Table, req: Request, opts: Options, analysis: *AnalysisState, stratified: strat_exec.Report, writer: ?*stat_output.Writer, source: *const Dataset, by: []const usize, by_row: ?[]const Value) diag.Error!void {
    const a = cx.arena;
    const requested_tests = exact_public.asymptoticTests(req, opts.tests.requests);
    if (tab.negative) {
        if (!opts.noprint and !req.noprint) try renderTable(a, out, tab, req, opts);
        return; // The existing BY/table path already reported the negative-weight note.
    }
    if (tab.dimensions.len == 1) {
        const scored = (try tab.matrix(a, 0)).?;
        if (scored.matrix.counts.len == 0) {
            if (!opts.noprint and !req.noprint) try renderOne(a, out, tab, req);
            return;
        }
        var body: std.ArrayList(u8) = .empty;
        const result = try stat_exec.execute(a, cx.diags, &body, .{ .name = tab.dimensions[0].name, .one_way = true, .matrix = inferenceMatrix(scored.matrix) }, req.statistics, requested_tests, req.resolved_expected, opts.noprint);
        if (writer) |w| try w.append(by_row, tab, 0, tab.total, tab.missing, result, false);
        // SAS skips risk analysis when PROC NOPRINT has no output request.
        // Existing test-family NOPRINT execution remains independent above.
        var active = req;
        const risk_report: risk_render.Report = if (opts.noprint) .{} else try risk_exec.executeResolved(a, cx.diags, try riskTable(a, tab, scored, true, false), &active.risk, req.statistics.alpha);
        if (req.risk.binomial != null and active.risk.binomial == null) active.exact.families.remove(.binomial);
        if (opts.noprint) return;
        const exact_tables = try exact_public.render(a, cx.diags, &body, scored, true, active, &analysis.simulation_seed, result);
        if (cx.capture) |capture| try @import("ods_freq_mc.zig").publish(a, cx.diags, capture, source, by, by_row, tab, 1, exact_tables.simulations.items, req.exact, req.stratified.agreement.restore);
        if (cx.capture) |capture| try @import("ods_freq_tests.zig").publish(a, cx.diags, capture, source, by, by_row, tab, 0, req, result);
        try risk_render.render(a, &body, risk_report);
        try body.appendSlice(a, exact_tables.odds_listing);
        if (!req.noprint) try renderOne(a, out, tab, req) else if (body.items.len > 0) try out.appendSlice(a, ONEWAY_TITLE);
        try out.appendSlice(a, body.items);
        const sample_size = if (result.goodness_of_fit) |gof| gof.total else risk_report.sample_size;
        if (sample_size) |total| {
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nSample Size = {s}\n", .{try freqText(a, total)}));
            if (!req.missing) try appendFreqMissing(a, out, tab.missing);
        }
        return;
    }
    const n = tab.dimensions.len;
    const nr = tab.dimensions[n - 2].levels.len;
    const nc = tab.dimensions[n - 1].levels.len;
    if (nr == 0 or nc == 0) return;
    var number: usize = 0;
    // Displayed statistics include combinations without input observations.
    // The output-only path retains its existing sparse stratum enumeration.
    const observed_ids = if (opts.noprint) try analysisStrata(a, tab) else null;
    const count = if (observed_ids) |ids| ids.len else tab.cell_count / (nr * nc);
    for (0..count) |i| {
        const stratum = if (observed_ids) |ids| ids[i] else i;
        var missing_control = false;
        for (0..n - 2) |d| if (tab.level(stratum * nr * nc, d).missing) {
            missing_control = true;
        };
        if (missing_control and !req.missing and !req.missprint) continue;
        number += 1;
        const sl = try tab.slice(a, stratum);
        const excluded_control = missing_control and !req.missing;
        const eligible = sl.observed and !excluded_control and (sl.total != 0 or sl.missing == 0 or req.missing);
        var body: std.ArrayList(u8) = .empty;
        if (eligible) {
            const scored = (try tab.matrix(a, stratum)).?;
            if (scored.matrix.rows > 0 and scored.matrix.cols > 0) {
                const defer_fisher = req.exact.families.contains(.pchi) or req.exact.families.contains(.lrchi) or req.exact.families.contains(.mhchi);
                const result = try stat_exec.execute(a, cx.diags, &body, .{
                    .suppress_fisher = req.exact.families.contains(.fisher),
                    .defer_fisher = defer_fisher,
                    .warning_location = if (opts.noprint and req.statistics.chisq and req.statistics.warn.log) try warningLocation(a, sl, number) else "",
                    .matrix = inferenceMatrix(scored.matrix),
                    .numeric_table_scores_valid = scored.numeric_table_scores_valid,
                    .score_display = if (req.scorout) try scoreDisplay(a, tab, scored) else null,
                }, req.statistics, requested_tests, .equal, opts.noprint);
                if (writer) |w| try w.append(by_row, tab, stratum * nr * nc, sl.total, sl.missing, result, scored.matrix.rows == 2 and scored.matrix.cols == 2);
                const risk_report: risk_render.Report = if (opts.noprint) .{} else try risk_exec.execute(a, cx.diags, try riskTable(a, tab, scored, false, req.statistics.measures and !req.statistics.measures_only_implied), req.risk, req.statistics.alpha);
                if (!analysis.noted_newcombe and risk_report.sections.len > 0) {
                    if (req.risk.difference) |rd| if (rd.equal and rd.method == .newcombe) {
                        try cx.diags.note(0, "METHOD=NEWCOMBE is not available for RISKDIFF EQUAL. By default, RISKDIFF EQUAL uses METHOD=WALD. To compute Newcombe confidence limits, specify CL=NEWCOMBE.", .{});
                        analysis.noted_newcombe = true;
                    };
                }
                if (!opts.noprint) {
                    const limits = try exact_public.render(a, cx.diags, &body, scored, false, req, &analysis.simulation_seed, result);
                    if (defer_fisher) if (result.chi_square) |chi| if (chi.fisher) |fisher| try stat_render.fisher(a, &body, fisher, scored.matrix.counts[0]);
                    if (cx.capture) |capture| try @import("ods_freq_tests.zig").publish(a, cx.diags, capture, source, by, by_row, tab, number, req, result);
                    if (cx.capture) |capture| {
                        const table_name = try @import("ods_freq_exact_rows.zig").tableName(a, tab, number);
                        try @import("ods_freq_exact_tests.zig").publish(a, cx.diags, capture, source, by, by_row, table_name, scored.matrix, result.chi_square, limits, req.exact);
                        try @import("ods_freq_risk.zig").publish(a, cx.diags, capture, source, by, by_row, tab, number, scored.matrix, req.statistics.alpha, req.exact.pformat, risk_report, limits);
                        try @import("ods_freq_mc.zig").publish(a, cx.diags, capture, source, by, by_row, tab, number, limits.simulations.items, req.exact, req.stratified.agreement.restore);
                    }
                    try risk_render.render(a, &body, risk_report);
                    try body.appendSlice(a, limits.odds_listing);
                    for (stratified.strata) |s| if (s.id == stratum) {
                        if (cx.capture) |capture| {
                            const table_name = try @import("ods_freq_exact_rows.zig").tableName(a, tab, number);
                            try @import("ods_freq_agreement.zig").publish(a, cx.diags, capture, source, by, by_row, table_name, s, req.stratified, stratScope(req, opts), req.exact, limits);
                        }
                        try strat_exec.renderStratum(a, &body, s, req.stratified, stratScope(req, opts));
                        break;
                    };
                }
            }
        }
        if (opts.noprint) continue;
        if (excluded_control or sl.total == 0) {
            // A missing controlling variable or an empty table replaces every
            // requested statistic with one explanation for this stratum.
            body.clearRetainingCapacity();
            try body.appendSlice(a, if (excluded_control)
                "\nThese data are missing because one or more control variables are missing.\n"
            else
                "\nTable is empty. No statistics are computed.\n");
        }
        if (number > 1) try out.append(a, '\n');
        if (!req.noprint) {
            if (req.crosslist) try renderCross(a, out, sl, req, number, opts.zeros) else try renderGrid(a, out, sl, req, opts.formchar, if (n > 2) number else 0, opts.zeros);
        }
        if (body.items.len > 0) {
            const row_name = tab.dimensions[n - 2].name;
            const col_name = tab.dimensions[n - 1].name;
            if (n > 2) {
                if (req.noprint and number == 1) try out.appendSlice(a, TWOWAY_TITLE);
                try out.appendSlice(a, try std.fmt.allocPrint(a, "\nStatistics for Table {d} of {s} by {s}\nControlling for", .{ number, row_name, col_name }));
                try appendControlValues(a, out, sl);
                try out.append(a, '\n');
            } else {
                if (req.noprint) try out.appendSlice(a, TWOWAY_TITLE);
                try out.appendSlice(a, try std.fmt.allocPrint(a, "\nStatistics for Table of {s} by {s}\n", .{ row_name, col_name }));
            }
            try out.appendSlice(a, body.items);
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nSample Size = {s}\n", .{try freqText(a, if (excluded_control) 0 else sl.total)}));
            if (!req.missing) try appendFreqMissing(a, out, if (excluded_control) sl.missing + sl.total else sl.missing);
        }
    }
    if (!opts.noprint) {
        const exact_strata = try exact_public.renderStrata(a, cx.diags, out, tab, req, analysis.simulation_seed);
        if (exact_strata.common != null or exact_strata.zelen != null) if (cx.capture) |capture| {
            const title = try std.fmt.allocPrint(a, "Summary for {s} * {s}", .{ tab.dimensions[n - 2].name, tab.dimensions[n - 1].name });
            try @import("ods_freq_exact_strata.zig").publish(a, cx.diags, capture, source, by, by_row, title, stratified, exact_strata, req.statistics.alpha, req.exact);
        };
    }
    if (!opts.noprint and hasStratified(req.stratified)) {
        var summary: std.ArrayList(u8) = .empty;
        try strat_exec.renderSummary(a, &summary, stratified, req.stratified, stratScope(req, opts), req.scores);
        if (summary.items.len > 0) {
            try out.appendSlice(a, TWOWAY_TITLE);
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nSummary Statistics for {s} by {s}\n", .{ tab.dimensions[n - 2].name, tab.dimensions[n - 1].name }));
            if (n > 2) {
                try out.appendSlice(a, "Controlling for");
                for (tab.dimensions[0 .. n - 2]) |dim| try out.appendSlice(a, try std.fmt.allocPrint(a, " {s}", .{dim.name}));
                try out.append(a, '\n');
            }
            try out.appendSlice(a, summary.items);
            try out.appendSlice(a, try std.fmt.allocPrint(a, "\nTotal Sample Size = {s}\n", .{try freqText(a, tab.total)}));
        }
    }
}

fn expectedRow(a: std.mem.Allocator, out: *std.ArrayList(u8), values: []const []const u8, widths: []const usize, rule: bool) !void {
    try out.appendNTimes(a, ' ', 14);
    for (values, widths, 0..) |value, width, i| {
        if (rule) {
            try out.appendNTimes(a, '-', width);
            continue;
        }
        if (i > 0) try out.appendNTimes(a, ' ', width - @min(width, value.len));
        try out.appendSlice(a, value);
        if (i == 0) try out.appendNTimes(a, ' ', width - @min(width, value.len));
    }
    try out.append(a, '\n');
}
/// Expected-value columns align to the complete analysis-level order, not the
/// optional MAXLEVELS display subset, and exclude MISSPRINT-only missing rows.
fn renderOneExpected(a: std.mem.Allocator, out: *std.ArrayList(u8), tab: *Table, req: Request) !void {
    const probabilities = req.resolved_expected == .proportions;
    const values = switch (req.resolved_expected) {
        .proportions, .frequencies => |v| v,
        .equal => unreachable,
    };
    var sum_values: f64 = 0;
    for (values) |v| sum_values += v;
    var headers: std.ArrayList([]const u8) = .empty;
    var tops: std.ArrayList([]const u8) = .empty;
    try headers.appendSlice(a, &.{ tab.dimensions[0].name, "Frequency" });
    try tops.appendSlice(a, &.{ "", "" });
    if (!probabilities) {
        try headers.append(a, "Frequency");
        try tops.append(a, "Test");
    }
    if (!req.nopercent) {
        try headers.append(a, "Percent");
        try tops.append(a, "");
    }
    if (probabilities and !req.nopercent) {
        try headers.append(a, "Percent");
        try tops.append(a, "Test");
    }
    if (!req.nocum) {
        try headers.append(a, "Frequency");
        try tops.append(a, "Cumulative");
        if (!req.nopercent) {
            try headers.append(a, "Percent");
            try tops.append(a, "Cumulative");
        }
    }
    var rows: std.ArrayList([]const []const u8) = .empty;
    var cumulative: f64 = 0;
    var analysis_index: usize = 0;
    var displayed: usize = 0;
    var truncated = false;
    for (tab.dimensions[0].levels, 0..) |l, key| {
        const excluded = tab.excluded(key);
        const index = analysis_index;
        if (!excluded) analysis_index += 1;
        if (!shown(l, req)) continue;
        if (!excluded) {
            if (req.maxlevels) |max| if (displayed >= max) {
                truncated = true;
                continue;
            };
            displayed += 1;
            cumulative += tab.count(key);
        }
        const cells = try a.alloc([]const u8, headers.items.len);
        var pos: usize = 0;
        cells[pos] = try cellText(a, l.value);
        pos += 1;
        cells[pos] = try freqText(a, tab.count(key));
        pos += 1;
        if (!probabilities) {
            cells[pos] = if (excluded) "." else try freqText(a, values[index]);
            pos += 1;
        }
        if (!req.nopercent) {
            cells[pos] = try pctText(a, tab.pct(key));
            pos += 1;
        }
        if (probabilities and !req.nopercent) {
            cells[pos] = if (excluded) "." else try pctText(a, 100 * values[index] / sum_values);
            pos += 1;
        }
        if (!req.nocum) {
            cells[pos] = if (excluded) "." else try freqText(a, cumulative);
            pos += 1;
            if (!req.nopercent) cells[pos] = if (excluded) "." else try pctText(a, percent(cumulative, tab.total));
        }
        try rows.append(a, cells);
    }
    const widths = try a.alloc(usize, headers.items.len);
    for (headers.items, tops.items, 0..) |h, t, i| widths[i] = @max(@max(h.len, t.len) + (if (i == 0) @as(usize, 1) else 2), if (i == 0) @as(usize, 7) else 12);
    for (rows.items) |row| for (row, 0..) |v, i| {
        widths[i] = @max(widths[i], v.len + (if (i == 0) @as(usize, 1) else 2));
    };
    try out.appendSlice(a, ONEWAY_TITLE);
    try out.append(a, '\n');
    if (tab.dimensions[0].label) |label| try out.appendSlice(a, try std.fmt.allocPrint(a, "              {s}\n\n", .{label}));
    try expectedRow(a, out, tops.items, widths, false);
    try expectedRow(a, out, headers.items, widths, false);
    try expectedRow(a, out, headers.items, widths, true);
    for (rows.items) |row| try expectedRow(a, out, row, widths, false);
    if (truncated) try out.appendSlice(a, try std.fmt.allocPrint(a, "\n      The first {d} nonmissing levels are displayed.\n", .{req.maxlevels.?}));
    if (!req.missing) try appendFreqMissing(a, out, tab.missing);
}

test "STAT-FREQ-005 labeled BY groups preserve descriptors and goodness-of-fit columns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    _ = try ds.addColumn("Region", .num);
    _ = try ds.addColumn("Hair", .char);
    _ = try ds.addColumn("Count", .num);
    ds.columns.items[0].label = "Geographic Region";
    ds.columns.items[1].label = "Hair Color";
    const names = [_][]const u8{ "fair", "red", "medium", "dark", "black" };
    const counts = [_][5]f64{ .{ 76, 19, 83, 65, 3 }, .{ 152, 94, 134, 117, 19 } };
    for (counts, 0..) |group, i| for (group, names) |count, name| try ds.appendRow(&.{
        .{ .num = @floatFromInt(i + 1) }, .{ .str = name }, .{ .num = count },
    });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const source = "proc freq data=d order=data; by Region; weight Count; tables Hair / nocum chisq testp=(30 12 30 25 3); run;";
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, source, &d));
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Geographic Region="));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "\n              " ++ ("-" ** 43) ++ "\n"));
    for ([_][]const u8{ "7.7602", "0.1008", "21.3824", "0.0003", "Sample Size = 246", "Sample Size = 516" }) |value|
        try std.testing.expect(std.mem.indexOf(u8, out.items, value) != null);
    try std.testing.expectEqualStrings("Region", ds.columns.items[0].name);
    try std.testing.expectEqualStrings("Geographic Region", ds.columns.items[0].label.?);
}

test "stratified public hook computes mixed TEST requests and keeps exact gaps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "strata");
    _ = try ds.addColumn("s", .num);
    _ = try ds.addColumn("r", .num);
    _ = try ds.addColumn("c", .num);
    _ = try ds.addColumn("n", .num);
    for ([_]f64{ 16, 11, 5, 20, 12, 16, 7, 19 }, 0..) |count, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 4 + 1) }, .{ .num = @floatFromInt(i / 2 % 2 + 1) }, .{ .num = @floatFromInt(i % 2 + 1) }, .{ .num = count } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("strata", ds);
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const source = "proc freq data=strata; weight n; tables s*r*c / cmh(bdt mf i2) agree commonriskdiff(cl=(mh mr score) test printwts) noprint; test kappa pcorr; run;";
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, source, &d));
    try std.testing.expect(!d.hasErrors());
    for ([_][]const u8{ "8.3052", "1.4905", "19.2443", "Common Risk Difference", "Test of H0: Kappa = 0", "Pearson Correlation" }) |value| try std.testing.expect(std.mem.indexOf(u8, out.items, value) != null);
    out.clearRetainingCapacity();
    const duplicate = "proc freq data=strata; tables r*c; test kappa; test pcorr;run;";
    try std.testing.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, duplicate, &d)));
}

test "FEAT-base-stat-results last FREQ table writes independent PCHI and cell datasets" {
    // SAS 9.4 M9 freq_table_and_output_last (2x3, weighted) and
    // freq_output_missing_request. See also SAS/STAT example 3.6.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "r", "c", "n" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 1, 1, 3 }, .{ 1, 2, 1 }, .{ 1, 3, 0 }, .{ 2, 1, 0 }, .{ 2, 2, 2 }, .{ 2, 3, 2 } }) |row|
        try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    try lib.put("d", ds);
    var d = diag.Diagnostics.init(a);
    var listing: std.ArrayList(u8) = .empty;
    const cx = ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const lex = @import("../lexer.zig");
    try runFreq(cx, &listing, try lex.tokenize(a, "proc freq data=d noprint; weight n; tables r c r*c / out=cells chisq; output out=stats pchi; run;", &d));
    const result = lib.find("stats").?;
    try std.testing.expectEqual(@as(usize, 4), lib.find("cells").?.rowCount());
    try std.testing.expectEqual(@as(usize, 1), result.rowCount());
    try std.testing.expectEqual(@as(usize, 3), result.columns.items.len);
    for ([_][]const u8{ "_PCHI_", "DF_PCHI", "P_PCHI" }, [_][]const u8{ "Chi-Square", "DF for Chi-Square", "P-value for Chi-Square" }, result.columns.items) |name, label, col| {
        try std.testing.expectEqualStrings(name, col.name);
        try std.testing.expectEqualStrings(label, col.label.?);
        try std.testing.expectEqual(@as(?usize, 8), col.len);
        try std.testing.expect(col.format == null and col.type == .num);
    }
    try std.testing.expectApproxEqAbs(@as(f64, 5.33333333), result.row(0)[0].num, 1e-8);
    try std.testing.expectEqual(@as(f64, 2), result.row(0)[1].num);
    try std.testing.expectApproxEqAbs(@as(f64, 0.06948345), result.row(0)[2].num, 1e-8);
    d.list.clearRetainingCapacity();
    try runFreq(cx, &listing, try lex.tokenize(a, "proc freq data=d noprint; weight n; tables r*c; output out=missing_request fisher; run;", &d));
    try std.testing.expect(lib.find("missing_request") == null);
    try std.testing.expectEqual(@as(usize, 1), d.list.items.len);
    try std.testing.expectEqual(diag.Severity.warning, d.list.items[0].severity);
    try std.testing.expectEqualStrings("No OUTPUT data set is produced because no statistic options are specified in the corresponding TABLES statement.", d.list.items[0].message);
}

test "FREQ native comparative EQUAL methods, request margins and ordered diagnostics" {
    // SAS 9.4 M9 on cells (12,8;5,25). For the public procedure inputs, see
    // tests/corpus/supplemental/stat_option_freq_newcombe_equality_*.sas.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "d");
    for ([_][]const u8{ "g", "r", "c", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 1, 2 }) |group| {
        for ([_][3]f64{ .{ 1, 1, 12 }, .{ 1, 2, 8 }, .{ 2, 1, 5 }, .{ 2, 2, 25 } }) |row|
            try ds.appendRow(&.{ .{ .num = group }, .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    }
    try lib.put("d", ds);
    const source = "proc freq data=d;by g;weight w;" ++
        "tables r*c / noprint riskdiff(equal(null=100)) riskdiff(equal(null=.1) noninf sup equiv method=wilson);" ++
        "tables r*c / noprint relrisk(equal(null=2) noninf sup equiv method=log margin=(.75,1.4));" ++
        "tables r*c / noprint riskdiff(equal method=mn);run;";
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    try runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, source, &d));
    try std.testing.expectEqual(@as(usize, 2), d.count());
    try std.testing.expect(std.mem.startsWith(u8, d.list.items[0].message, "METHOD=NEWCOMBE is not available for RISKDIFF EQUAL."));
    try std.testing.expectEqualStrings("The above message was for the following BY group:\n      g=1", d.list.items[1].message);
    // The equality test stays Wald, while the three Newcombe analyses keep
    // their native interval and supply no test statistic. MN selects F-M.
    var values: std.ArrayList(f64) = .empty;
    var lines = std.mem.tokenizeScalar(u8, out.items, '\n');
    while (lines.next()) |row_text| {
        var words = std.mem.tokenizeAny(u8, row_text, " \t");
        const label = words.next() orelse continue;
        if (eqi(label, "Z")) try values.append(a, try std.fmt.parseFloat(f64, words.next().?));
    }
    const expected = [_]f64{ 2.5849, 1.3143, 3.5075, 3.5075, 3.1688 };
    try std.testing.expectEqual(2 * expected.len, values.items.len);
    for (values.items, 0..) |actual, i| try std.testing.expectApproxEqAbs(expected[i % expected.len], actual, 0.00005);
    for ([_][]const u8{ "0.2052", "0.6115" }) |bound| try std.testing.expectEqual(@as(usize, 6), std.mem.count(u8, out.items, bound));

    const invalid = "proc freq data=d;weight w;tables r*c c*r / relrisk(equal(null=0) equiv margin=1) riskdiff(equal(null=-100));run;";
    d = diag.Diagnostics.init(a);
    out.clearRetainingCapacity();
    try std.testing.expectError(error.ParseError, runFreq(.{ .arena = a, .lib = &lib, .diags = &d }, &out, try @import("../lexer.zig").tokenize(a, invalid, &d)));
    const errors = [_][]const u8{
        "The NULL= value for the RISKDIFF EQUAL test must be between -100 and 100.",
        "The MARGIN= value for the RELRISK EQUIV test must be less than 1 when an upper MARGIN= value is not specified.",
        "The NULL= value for the RELRISK EQUAL test must be a positive number.",
    };
    try std.testing.expectEqual(2 * errors.len, d.count());
    for (d.list.items, 0..) |entry, i| try std.testing.expectEqualStrings(errors[i % errors.len], entry.message);
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}
