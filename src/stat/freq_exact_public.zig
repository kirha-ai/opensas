//! Public EXACT orchestration. Table construction owns levels, scores and BY;
//! exact engines own reference distributions and never receive syntax tokens.
const std = @import("std");
const diag = @import("../diag.zig");
const parse = @import("freq_exact_parse.zig");
const exec = @import("freq_exact_execute.zig");
const renderers = @import("freq_exact_render.zig");
const model = @import("freq_table.zig");
const tests = @import("freq_tests.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);

fn seconds() f64 {
    return switch (@import("builtin").os.tag) {
        .windows => @as(f64, @floatFromInt(std.os.windows.ntdll.RtlGetSystemTimePrecise())) / 1e7,
        else => blk: {
            var ts: std.posix.timespec = undefined;
            if (std.posix.errno(std.posix.system.clock_gettime(.MONOTONIC, &ts)) != .SUCCESS) break :blk 0;
            break :blk @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1e9;
        },
    };
}
pub fn clockSeed() u64 {
    return @as(u64, @intFromFloat(@mod(seconds() * 1e6, 2147483646))) + 1;
}
const Deadline = struct {
    end: ?f64,
    fn expired(raw: ?*const anyopaque) bool {
        const self: *const Deadline = @ptrCast(@alignCast(raw.?));
        return if (self.end) |end| seconds() >= end else false;
    }
};

/// SAS pp.81–82: a single TABLES statement implies the corresponding options;
/// multiple statements select only statistics requested on each TABLES.
pub fn resolve(req: anytype, statement: ?parse.Options, statements: usize) void {
    if (statement) |options| {
        req.exact = options;
        req.exact.families = options.expanded(req.vars.len == 1);
        var it = req.exact.families.iterator();
        while (it.next()) |f| {
            const enabled = switch (f) {
                .pchi, .lrchi, .mhchi, .fisher => req.statistics.chisq or req.fisher,
                .pcorr, .scorr, .kentb, .stutc, .smdcr, .smdrc => req.statistics.measures,
                .oddsratio => req.statistics.measures or req.risk.odds_ratio != null or req.risk.relative_risk != null,
                .binomial => req.risk.binomial != null,
                .riskdiff, .barnard => req.risk.difference != null,
                .relrisk => req.risk.relative_risk != null,
                .jt => req.stratified.jt,
                .trend => req.stratified.trend,
                .mcnem, .symmetry, .kappa, .wtkappa => req.stratified.agreement.enabled,
                .comor, .eqor => req.stratified.cmh > 0,
                else => false,
            };
            if (statements != 1 and !enabled) req.exact.families.remove(f);
        }
    }
    if (req.fisher) req.exact.families.insert(.fisher);
    if (statements == 1 or req.fisher) {
        var it = req.exact.families.iterator();
        while (it.next()) |f| switch (f) {
            .pchi, .lrchi, .mhchi, .fisher => {
                req.statistics.chisq = true;
                if (f == .lrchi) req.statistics.lrchi = true;
            },
            .pcorr, .scorr, .kentb, .stutc, .smdcr, .smdrc => {
                req.statistics.measures = true;
            },
            .oddsratio => {
                if (req.risk.odds_ratio == null) req.risk.odds_ratio = .{ .family = .odds_ratio };
            },
            .binomial => {
                if (req.risk.binomial == null) req.risk.binomial = .{ .family = .binomial };
            },
            .riskdiff, .barnard => {
                if (req.risk.difference == null) req.risk.difference = .{ .family = .difference, .both_columns = true };
            },
            .relrisk => {
                if (req.risk.relative_risk == null) req.risk.relative_risk = .{ .family = .relative_risk };
            },
            .jt => {
                req.stratified.jt = true;
            },
            .trend => {
                req.stratified.trend = true;
            },
            .mcnem, .symmetry, .kappa, .wtkappa => {
                req.stratified.agreement.enabled = true;
            },
            .comor, .eqor => {
                if (req.stratified.cmh == 0) req.stratified.cmh = 3;
            },
            else => {},
        };
    }
}

pub fn asymptoticTests(req: anytype, requested: @import("freq_tests_parse.zig").Tests) @import("freq_tests_parse.zig").Tests {
    var out = requested;
    const f = req.exact.families;
    out.pearson = out.pearson or f.contains(.pcorr);
    out.spearman = out.spearman or f.contains(.scorr);
    out.tau_b = out.tau_b or f.contains(.kentb);
    out.tau_c = out.tau_c or f.contains(.stutc);
    out.somers_cr = out.somers_cr or f.contains(.smdcr);
    out.somers_rc = out.somers_rc or f.contains(.smdrc);
    return out;
}

pub fn validateClRequests(req: anytype, d: *diag.Diagnostics) diag.Error!void {
    const risks = [_]?@import("freq_risk_parse.zig").Request{ req.risk.difference, req.risk.relative_risk, req.risk.odds_ratio };
    for (risks, [_]parse.Family{ .riskdiff, .relrisk, .oddsratio }) |maybe, family| if (maybe) |r| {
        var wants_exact = false;
        for (r.cls) |cl| if (cl.method == .exact) {
            wants_exact = true;
        };
        if (!wants_exact) continue;
        if (!req.exact.families.contains(family)) {
            try d.report(.warning, 0, "To display exact confidence limits for {s}, specify the corresponding option in the EXACT statement.", .{@tagName(family)});
            continue;
        }
        const column: parse.Column = if (family == .riskdiff) req.exact.riskdiff.column orelse (if (r.norisks) parse.Column.first else .both) else req.exact.relrisk.column orelse .first;
        if (family != .oddsratio and column != .both and ((r.column == 1) != (column == .second))) try d.report(.warning, 0, "To display exact confidence limits for column {d} {s}, request that column in the EXACT statement.", .{ r.column + 1, @tagName(family) });
    };
}

fn matrix(scored: model.ScoredMatrix, one: bool) tests.CountMatrix {
    const m = scored.matrix;
    return .{ .rows = if (one) 1 else m.rows, .cols = if (one) m.rows else m.cols, .counts = m.counts, .row_scores = if (one) null else m.row_scores, .col_scores = if (one) null else m.col_scores };
}
fn config(req: anytype, seed: u64, deadline: *const Deadline) exec.Config {
    return .{ .options = req.exact, .effective_seed = seed, .alpha = req.statistics.alpha, .expected = req.resolved_expected, .null_ratio = req.stratified.agreement.null_ratio, .kappa_weight = req.stratified.agreement.weight, .budget = .{ .context = deadline, .expired = Deadline.expired } };
}
fn directional(f: parse.Family) bool {
    return switch (f) {
        .pcorr, .scorr, .kentb, .stutc, .smdcr, .smdrc, .jt, .trend, .kappa, .wtkappa => true,
        else => false,
    };
}
fn title(f: parse.Family) []const u8 {
    return switch (f) {
        .pchi => "Pearson Chi-Square Test",
        .lrchi => "Likelihood Ratio Chi-Square Test",
        .mhchi => "Mantel-Haenszel Chi-Square Test",
        .fisher => "Fisher's Exact Test",
        .pcorr => "Pearson Correlation Coefficient",
        .scorr => "Spearman Correlation Coefficient",
        .kentb => "Kendall's Tau-b",
        .stutc => "Stuart's Tau-c",
        .smdcr => "Somers' D C|R",
        .smdrc => "Somers' D R|C",
        .jt => "Jonckheere-Terpstra Test",
        .trend => "Cochran-Armitage Trend Test",
        .kappa => "Simple Kappa Coefficient",
        .wtkappa => "Weighted Kappa Coefficient",
        .mcnem => "McNemar's Test",
        .symmetry => "Symmetry Test",
        .binomial => "Exact Binomial Test",
        .oddsratio => "Odds Ratio",
        .riskdiff => "Risk Difference",
        .relrisk => "Relative Risk",
        .barnard => "Barnard's Unconditional Exact Test",
        .comor => "Common Odds Ratio",
        .eqor => "Zelen's Exact Test",
        else => "Exact Test",
    };
}
fn interval(a: A, out: *Out, name: []const u8, ci: @import("freq_exact.zig").Interval, alpha: f64) diag.Error!void {
    try out.appendSlice(a, try std.fmt.allocPrint(a, "\n{s}\nExact Confidence Limits\n{d}% Lower Conf Limit  {d:.4}\n{d}% Upper Conf Limit  {d:.4}\n", .{ name, 100 * (1 - alpha), ci.lower, 100 * (1 - alpha), ci.upper }));
}
fn binomialHypotheses(a: A, out: *Out, request: @import("freq_risk_parse.zig").Request, k: u32, n: u32, c: exec.Config) diag.Error!void {
    if (!request.noninf and !request.sup and !request.equiv) return;
    const exact = @import("freq_exact.zig");
    const limits = try exact.binomialOneSidedLimits(k, n, c.alpha, .{ .context = c.budget.context, .expired = c.budget.expired });
    if (limits == .exhausted) {
        try renderers.testResult(a, out, "Exact Binomial Hypothesis Tests", .exhausted, c.options);
        return;
    }
    const margin = request.margin orelse [2]f64{ 0.2, 0.2 };
    for ([_]bool{ false, true }) |superiority| {
        if (if (superiority) !request.sup else !request.noninf) continue;
        const p0 = request.p + (if (superiority) margin[0] else -margin[0]);
        const p = (try exact.binomialTails(k, n, p0)).right;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nExact {s} Analysis\nPr >= P  {s}\n", .{ if (superiority) "Superiority" else "Noninferiority", try renderers.probability(a, p, c.options.pformat) }));
        try interval(a, out, "Binomial Proportion", limits.complete, 2 * c.alpha);
    }
    if (request.equiv) {
        const lower = request.p + (if (request.paired_margin) margin[0] else -margin[0]);
        const upper = request.p + margin[1];
        const left = (try exact.binomialTails(k, n, lower)).right;
        const right = (try exact.binomialTails(k, n, upper)).left;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "\nExact Equivalence Analysis\nLower Margin Pr >= P  {s}\nUpper Margin Pr <= P  {s}\nOverall P-Value  {s}\n", .{ try renderers.probability(a, left, c.options.pformat), try renderers.probability(a, right, c.options.pformat), try renderers.probability(a, @max(left, right), c.options.pformat) }));
        try interval(a, out, "Binomial Proportion", limits.complete, 2 * c.alpha);
    }
}
pub fn render(a: A, d: *diag.Diagnostics, out: *Out, scored: model.ScoredMatrix, one: bool, req: anytype, seed: u64) diag.Error!void {
    if (req.exact.families.count() == 0) return;
    var total: f64 = 0;
    for (scored.matrix.counts) |v| total += v;
    if (total == 0) return;
    const m = matrix(scored, one);
    var it = req.exact.families.iterator();
    while (it.next()) |requested_family| {
        const binary = m.rows == 2 and m.cols == 2;
        const f: parse.Family = if (requested_family == .wtkappa and binary) .kappa else requested_family;
        if (f == .comor or f == .eqor) continue;
        if (requested_family == .wtkappa and binary and req.exact.families.contains(.kappa)) continue;
        const deadline = Deadline{ .end = if (req.exact.max_seconds) |v| seconds() + v else null };
        var c = config(req, seed, &deadline);
        c.numeric_table_scores_valid = scored.numeric_table_scores_valid;
        if (req.risk.binomial) |b| {
            c.binomial_p = b.p;
            c.event_index = switch (b.level) {
                .number => |n| n - 1,
                .value => |v| blk: {
                    for (scored.row_levels, 0..) |level, i| {
                        const label = try @import("../proc.zig").cellText(a, level.value);
                        if (std.mem.eql(u8, v, label)) break :blk i;
                    }
                    return d.fail(error.ExecError, 0, "PROC FREQ EXACT: binomial LEVEL not found", .{});
                },
            };
        }
        if (req.risk.difference) |rd| {
            c.norisks = rd.norisks;
        }
        const result = exec.run(a, m, f, c) catch |err| {
            if (err == error.OutOfMemory) return err;
            return d.fail(error.ExecError, 0, "PROC FREQ EXACT {s}: invalid counts, scores, or reference distribution", .{@tagName(f)});
        };
        var options = req.exact;
        if (!parse.supportsPoint(f)) {
            options.point = false;
            options.midp = false;
        }
        switch (result) {
            .not_applicable => {},
            .requires_strata => unreachable,
            .exhausted => {
                try d.report(.warning, 0, "PROC FREQ EXACT {s}: resource limit reached; no partial p-value is reported", .{@tagName(f)});
                try renderers.testResult(a, out, title(f), .exhausted, options);
            },
            .exact_test => |p| try renderers.testResult(a, out, title(f), .{ .complete = .{ .probabilities = p, .directional = directional(f), .right_sided = p.one_sided == p.right and p.left != p.right } }, options),
            .fisher => |r| try renderers.fisher(a, out, .{ .first_cell = r.first_cell, .table_probability = r.table_probability, .left = if (r.cell_tails) |t| t.left else null, .right = if (r.cell_tails) |t| t.right else null, .p = r.probabilities.two_sided, .point = r.probabilities.point }, options),
            .monte_carlo => |r| {
                if (r == .exhausted) {
                    try d.report(.warning, 0, "PROC FREQ EXACT: Monte Carlo resource limit reached", .{});
                    try renderers.monteCarlo(a, out, title(f), null, 0, seed, options);
                } else {
                    if (directional(f)) try renderers.monteCarlo(a, out, try std.fmt.allocPrint(a, "{s} (One-sided)", .{title(f)}), r.complete.one_sided, r.complete.samples, seed, options);
                    try renderers.monteCarlo(a, out, title(f), r.complete.two_sided, r.complete.samples, seed, options);
                }
            },
            .binomial => |b| {
                try renderers.testResult(a, out, title(f), .{ .complete = .{ .probabilities = .{ .one_sided = b.one_sided, .two_sided = b.two_sided, .point = b.tails.point, .left = b.tails.left, .right = b.tails.right, .tables = 0 }, .directional = true, .two_doubled = true, .right_sided = b.one_sided == b.tails.right and b.tails.left != b.tails.right } }, options);
                if (req.risk.binomial) |request| try binomialHypotheses(a, out, request, try @import("freq_exact.zig").integerCount(m.counts[c.event_index]), try @import("freq_exact.zig").integerCount(total), c);
            },
            .interval => |ci| try interval(a, out, title(f), ci, c.alpha),
            .risk_intervals => |r| {
                if (r.first) |ci| try interval(a, out, try std.fmt.allocPrint(a, "{s} (Column 1)", .{title(f)}), ci, c.alpha);
                if (r.second) |ci| try interval(a, out, try std.fmt.allocPrint(a, "{s} (Column 2)", .{title(f)}), ci, c.alpha);
            },
            .barnard => |b| try renderers.testResult(a, out, title(f), .{ .complete = .{ .directional = true, .right_sided = m.counts[0] / (m.counts[0] + m.counts[1]) > m.counts[2] / (m.counts[2] + m.counts[3]), .probabilities = .{ .one_sided = b.one.upper, .two_sided = b.two.upper, .point = 0, .left = 0, .right = 0, .tables = 0 } } }, options),
        }
    }
}

pub fn renderStrata(a: A, d: *diag.Diagnostics, out: *Out, tab: *model.Table, req: anytype, seed: u64) diag.Error!void {
    if (!req.exact.families.contains(.comor) and !req.exact.families.contains(.eqor)) return;
    const n = tab.dimensions.len;
    if (n < 3) return;
    const size = tab.dimensions[n - 2].levels.len * tab.dimensions[n - 1].levels.len;
    if (size == 0) return;
    var strata: std.ArrayList(tests.CountMatrix) = .empty;
    var previous: ?usize = null;
    for (try tab.keys(a, false, true)) |key| {
        const id = key / size;
        if (previous == id) continue;
        previous = id;
        var missing = false;
        for (0..n - 2) |i| if (tab.level(key, i).missing) {
            missing = true;
        };
        if (missing and !req.missing) continue;
        const scored = (try tab.matrix(a, id)) orelse continue;
        const m = matrix(scored, false);
        // SAS inapplicable.sas suppresses COMOR/EQOR outside h-by-2-by-2;
        // the implied CMH output remains valid for these larger tables.
        if (m.rows != 2 or m.cols != 2) return;
        try strata.append(a, m);
    }
    if (strata.items.len == 0) return;
    for ([_]parse.Family{ .comor, .eqor }) |f| {
        if (!req.exact.families.contains(f)) continue;
        const deadline = Deadline{ .end = if (req.exact.max_seconds) |v| seconds() + v else null };
        const result = exec.runStrata(a, strata.items, f, config(req, seed, &deadline)) catch |err| {
            if (err == error.OutOfMemory) return err;
            return d.fail(error.ExecError, 0, "PROC FREQ EXACT: invalid stratified reference distribution", .{});
        };
        switch (result) {
            .common_odds => |r| try renderers.commonOdds(a, out, r, req.statistics.alpha, req.exact),
            // SAS families.sas: with a fixed extreme sum the conditioned
            // reference set has only one outcome; Zelen is not displayed.
            .zelen => |r| if (r.tables > 1) {
                try renderers.zelen(a, out, r, req.exact);
            },
            .exhausted => {
                try d.report(.warning, 0, "PROC FREQ EXACT: stratified resource limit reached", .{});
                try renderers.testResult(a, out, title(f), .exhausted, req.exact);
            },
        }
    }
}

const Harness = struct {
    a: A,
    lib: @import("../exec.zig").Library,
    fn init(a: A, counts: []const f64, cols: usize) !Harness {
        const ds = try a.create(@import("../dataset.zig").Dataset);
        ds.* = @import("../dataset.zig").Dataset.init(a, "d");
        for ([_][]const u8{ "r", "c", "w" }) |name| _ = try ds.addColumn(name, .num);
        for (counts, 0..) |count, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / cols + 1) }, .{ .num = @floatFromInt(i % cols + 1) }, .{ .num = count } });
        var lib = @import("../exec.zig").Library.init(a);
        try lib.put("d", ds);
        return .{ .a = a, .lib = lib };
    }
    fn run(self: *Harness, source: []const u8, d: *diag.Diagnostics) ![]const u8 {
        var out: Out = .empty;
        const tokens = try @import("../lexer.zig").tokenize(self.a, source, d);
        try @import("freq.zig").runFreq(.{ .arena = self.a, .lib = &self.lib, .diags = d }, &out, tokens);
        return out.items;
    }
};

test "public EXACT Fisher includes tied mass and replaces automatic Fisher once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 1, 9, 11, 3 }, 2);
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w; tables r*c / noprint; exact fisher / point midp; run;", &d);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out, "Fisher's Exact Test"));
    for ([_][]const u8{ "Chi-Square", "0.0013", "0.0027", "0.0028", "0.0014" }) |value| try std.testing.expect(std.mem.indexOf(u8, out, value) != null);
    const mc = try h.run("proc freq data=d; weight w; tables r*c / fisher noprint; exact fisher / n=100 seed=17; run;", &d);
    try std.testing.expect(std.mem.indexOf(u8, mc, "Monte Carlo") == null);
    try std.testing.expect(std.mem.indexOf(u8, mc, "0.0028") != null);
}

test "public EXACT MC seed is repeatable and budget exhaustion emits no partial estimate" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 0, 1, 2, 2, 1, 0 }, 3);
    var d = diag.Diagnostics.init(a);
    const source = "proc freq data=d; weight w / zeros; tables r*c / noprint; exact fisher pcorr / n=2000 seed=17 alpha=.05; run;";
    const first = try h.run(source, &d);
    const second = try h.run(source, &d);
    try std.testing.expectEqualStrings(first, second);
    try std.testing.expect(std.mem.indexOf(u8, first, "Monte Carlo") != null);
    try std.testing.expect(std.mem.indexOf(u8, first, "95% Lower Conf Limit") != null);
    const stopped = try h.run("proc freq data=d; weight w / zeros; tables r*c / noprint; exact fisher / maxtime=1e-20; run;", &d);
    try std.testing.expect(std.mem.indexOf(u8, stopped, "resource limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, stopped, "Table Probability") == null);
}

test "public EXACT families honor single versus multiple TABLES selection and captured errors" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 3, 0, 1, 0, 2, 1, 1, 0, 2 }, 3);
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w / zeros; tables r*c / noprint; exact chisq measures kentb stutc smdcr smdrc jt agree symmetry / point; run;", &d);
    try std.testing.expect(!d.hasErrors());
    for ([_][]const u8{ "0.1010", "0.2229", "0.3295", "0.1648", "0.0905", "0.0267", "0.1200", "Symmetry Test" }) |value| try std.testing.expect(std.mem.indexOf(u8, out, value) != null);
    const multiple = try h.run("proc freq data=d; weight w; tables r*c / noprint; tables r*c / chisq noprint; exact fisher; run;", &d);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, multiple, "Fisher's Exact Test"));
    for ([_][]const u8{ "proc freq data=d; exact fisher; run;", "proc freq data=d; tables r*c; exact fisher; exact fisher; run;", "proc freq data=d; tables r*c; exact fisher / n=0; run;" }) |source| {
        var errors = diag.Diagnostics.init(a);
        try std.testing.expectError(error.ParseError, h.run(source, &errors));
        try std.testing.expect(errors.hasErrors());
    }
}

test "public EXACT one-way binomial and multinomial use distinct tails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 2, 8 }, 1);
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w; tables r / binomial(p=.3) noprint; exact binomial / point midp; run;", &d);
    for ([_][]const u8{ "0.0252", "0.5561", "0.3828", "0.2335", "0.2660", "0.7656", "Two-sided = 2 * One-sided" }) |value| try std.testing.expect(std.mem.indexOf(u8, out, value) != null);
    const gof = try h.run("proc freq data=d; weight w; tables r / testp=(.3 .7) noprint; exact pchi lrchi / point midp; run;", &d);
    for ([_][]const u8{ "0.7332", "0.4336", "0.5164", "0.5331", "0.4163" }) |value| try std.testing.expect(std.mem.indexOf(u8, gof, value) != null);
    const hypotheses = try h.run("proc freq data=d; weight w; tables r / binomial(p=.3 noninf sup equiv margin=.1) noprint; exact binomial / point midp; run;", &d);
    for ([_][]const u8{ "0.6242", "0.1673", "0.9536", "0.0368", "0.5069", "90% Lower Conf Limit" }) |value| try std.testing.expect(std.mem.indexOf(u8, hypotheses, value) != null);
    // SAS high-alpha.sas also verifies compatibility with the landed risk
    // behavior: exact NI limits remain ordered even at negative nominal CL.
    const high = try h.run("proc freq data=d; weight w; tables r / binomial(p=.3 noninf margin=.1) alpha=.6 noprint; exact binomial; run;", &d);
    for ([_][]const u8{ "0.1921", "0.2255", "-20% Lower Conf Limit", "0.6242" }) |value| try std.testing.expect(std.mem.indexOf(u8, high, value) != null);
    try std.testing.expect(!d.hasErrors());
}

test "public EXACT zero margins retain agreement and fractional counts fail with diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 0, 0, 1, 2 }, 2);
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w / zeros; tables r*c / noprint; exact fisher chisq measures agree; run;", &d);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out, "Fisher's Exact Test") == null);
    try std.testing.expect(std.mem.indexOf(u8, out, "McNemar's Test") != null);
    const weighted = try h.run("proc freq data=d; weight w / zeros; tables r*c / noprint; exact wtkappa; run;", &d);
    try std.testing.expect(std.mem.indexOf(u8, weighted, "Simple Kappa Coefficient") != null);
    try std.testing.expect(std.mem.indexOf(u8, weighted, "Weighted Kappa Coefficient") == null);
    var fractional = try Harness.init(a, &.{ 1, 2.5, 3, 4 }, 2);
    var errors = diag.Diagnostics.init(a);
    try std.testing.expectError(error.ExecError, fractional.run("proc freq data=d; weight w; tables r*c / noprint; exact fisher; run;", &errors));
    try std.testing.expect(errors.hasErrors());
}

test "public EXACT stratified COMOR and EQOR retain conditioning and missing control policy" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ds = try a.create(@import("../dataset.zig").Dataset);
    ds.* = @import("../dataset.zig").Dataset.init(a, "d");
    for ([_][]const u8{ "g", "r", "c", "w" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 2, 0, 0, 2, 0, 2, 2, 0 }, 0..) |count, i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i / 4 + 1) }, .{ .num = @floatFromInt(i / 2 % 2 + 1) }, .{ .num = @floatFromInt(i % 2 + 1) }, .{ .num = count } });
    try ds.appendRow(&.{ @import("../value.zig").Value.missing, .{ .num = 1 }, .{ .num = 1 }, .{ .num = 100 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("d", ds);
    var h = Harness{ .a = a, .lib = lib };
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w / zeros; tables g*r*c / noprint; exact comor eqor / point midp; run;", &d);
    for ([_][]const u8{ "Common Odds Ratio", "Zelen's Exact Test", "0.5000", "0.7500", "0.1111" }) |value| try std.testing.expect(std.mem.indexOf(u8, out, value) != null);
    try std.testing.expect(!d.hasErrors());
    try ds.appendRow(&.{ .{ .num = 1 }, .{ .num = 3 }, .{ .num = 3 }, .{ .num = 1 } });
    const larger = try h.run("proc freq data=d; weight w / zeros; tables g*r*c / noprint; exact comor eqor; run;", &d);
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, larger, "Exact Confidence Limits") == null);
}

test "public EXACT interval families and Barnard retain columns methods and probability formats" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 1, 3, 3, 1 }, 2);
    var d = diag.Diagnostics.init(a);
    // SAS intervals.sas, 0 errors/warnings: all four families are requested
    // together so inherited table options cannot overwrite either exact method.
    const out = try h.run("proc freq data=d; weight w; tables r*c / noprint; exact oddsratio riskdiff(column=both method=score2) relrisk(column=both method=score2) barnard / pformat=8.6; run;", &d);
    for ([_][]const u8{ "0.0016", "4.7229", "-0.9072", "-0.2500", "0.9072", "0.0238", "1.6859", "0.5932", "0.144531", "0.289063" }) |value| try std.testing.expect(std.mem.indexOf(u8, out, value) != null);
    try std.testing.expect(!d.hasErrors());
    const fisher = try h.run("proc freq data=d; weight w; tables r*c / noprint; exact fisher / point midp pformat=8.6; run;", &d);
    for ([_][]const u8{ "0.242857", "0.985714", "0.228571", "0.485714", "0.457143", "0.257143" }) |value| try std.testing.expect(std.mem.indexOf(u8, fisher, value) != null);
    const noscore = try h.run("proc freq data=d; weight w; tables r*c / noprint; exact relrisk(method=noscore); run;", &d);
    try std.testing.expect(std.mem.indexOf(u8, noscore, "12.8095") != null);
}

test "public RR SCORE2 preserves the quantified unresolved SAS endpoint discrepancy" {
    // This is a known-difference certificate, NOT an acceptance test claiming
    // SAS parity. The manager explicitly retains the same-ticket RR blocker.
    // rr-score2-precision.sas: SAS upper 42.0396959567221, not the mathematical
    // reciprocal endpoint printed as 42.0395. No tolerance has been widened.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 1, 3, 3, 1 }, 2);
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w; tables r*c / noprint; exact relrisk(column=both method=score2); run;", &d);
    const r = (try exec.run(a, .{ .rows = 2, .cols = 2, .counts = &.{ 1, 3, 3, 1 } }, .relrisk, .{ .options = .{ .relrisk = .{ .column = .both, .method = .score2 } } })).risk_intervals;
    try std.testing.expectApproxEqRel(1 / r.first.?.lower, r.second.?.upper, 1e-8);
    try std.testing.expect(@abs(r.second.?.upper - 42.0396959567221) > 0.00005);
    const displayed = try std.fmt.allocPrint(a, "{d:.4}", .{r.second.?.upper});
    try std.testing.expect(std.mem.indexOf(u8, out, displayed) != null);
    try std.testing.expect(std.mem.indexOf(u8, out, "42.0397") == null);
}

test "public CL EXACT requires the statement and does not override its column defaults" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var h = try Harness.init(a, &.{ 1, 3, 3, 1 }, 2);
    var warnings = diag.Diagnostics.init(a);
    const alone = try h.run("proc freq data=d; weight w; tables r*c / riskdiff(cl=exact) oddsratio(cl=exact) relrisk(cl=exact) noprint; run;", &warnings);
    try std.testing.expect(!warnings.hasErrors());
    try std.testing.expectEqual(@as(usize, 3), warnings.list.items.len);
    try std.testing.expect(std.mem.indexOf(u8, alone, "4.7229") == null);
    var d = diag.Diagnostics.init(a);
    const out = try h.run("proc freq data=d; weight w; tables r*c / riskdiff(column=2 cl=exact) relrisk(column=2 cl=exact) oddsratio(cl=exact) noprint; exact riskdiff relrisk oddsratio; run;", &d);
    for ([_][]const u8{ "Risk Difference (Column 1)", "Risk Difference (Column 2)", "Relative Risk (Column 1)", "-0.9363", "-0.3017", "0.0118", "1.7874", "4.7229" }) |value| try std.testing.expect(std.mem.indexOf(u8, out, value) != null);
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "column 2 relrisk") != null);
    const norisks = try h.run("proc freq data=d; weight w; tables r*c / riskdiff(norisks cl=exact) noprint; exact riskdiff; run;", &d);
    try std.testing.expect(std.mem.indexOf(u8, norisks, "Risk Difference (Column 1)") != null);
    try std.testing.expect(std.mem.indexOf(u8, norisks, "Risk Difference (Column 2)") == null);
}
