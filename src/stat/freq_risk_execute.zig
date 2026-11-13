//! Risk execution adapter. Exact dependencies live HERE, never in risk cores.
//! Table layer owns level order, missing values, BY groups and weighted counts.
const std = @import("std");
const diag = @import("../diag.zig");
const k = @import("freq_risk.zig");
const infer = @import("freq_risk_inference.zig");
const p = @import("freq_risk_parse.zig");
const r = @import("freq_risk_render.zig");
const exact = @import("freq_exact.zig");
pub const Table = struct { name: []const u8, column_name: []const u8 = "", row_labels: []const []const u8, col_labels: []const []const u8 = &.{}, counts: []const f64, one_way: bool = false, legacy_risks_printed: bool = false };
const A = std.mem.Allocator;
const Builder = struct {
    a: A,
    d: *diag.Diagnostics,
    alpha: f64,
    sections: std.ArrayList(r.Section) = .empty,
    fn add(self: *Builder, title: []const u8, subtitle: []const u8, columns: []const []const u8, rows: []const r.Row, note: []const u8) diag.Error!void {
        try self.sections.append(self.a, .{ .title = title, .subtitle = subtitle, .columns = columns, .rows = try self.a.dupe(r.Row, rows), .note = note });
    }
    fn level(self: *Builder, label: []const u8) diag.Error![]const u8 {
        return std.fmt.allocPrint(self.a, "{d}% {s}", .{ 100 * (1 - self.alpha), label });
    }
    fn intervals(self: *Builder, title: []const u8, subtitle: []const u8, rows: []const r.Row) diag.Error!void {
        const columns = try self.a.alloc([]const u8, 2);
        columns[0] = try self.level("Lower CL");
        columns[1] = try self.level("Upper CL");
        try self.add(title, subtitle, columns, rows, "");
    }
    fn estimates(self: *Builder, title: []const u8, subtitle: []const u8, rows: []const r.Row, note: []const u8) diag.Error!void {
        const columns = try self.a.alloc([]const u8, 4);
        columns[0] = "Estimate";
        columns[1] = "ASE";
        columns[2] = try self.level("Lower CL");
        columns[3] = try self.level("Upper CL");
        try self.add(title, subtitle, columns, rows, note);
    }
    fn inference(self: *Builder, req: p.Request, hypothesis: infer.Hypothesis, result: infer.Analysis, title: []const u8, estimate: ?f64, modified: ?f64) diag.Error!void {
        var rows: std.ArrayList(r.Row) = .empty;
        try rows.append(self.a, .{ .label = if (req.family == .binomial) "Proportion" else if (req.family == .difference) "Risk Difference" else "Relative Risk", .values = .{ estimate, null, null, null, null } });
        if (modified) |v| try rows.append(self.a, .{ .label = "Modified Relative Risk", .values = .{ v, null, null, null, null } });
        if (result.lower.chi_square) |g2| try rows.append(self.a, .{ .label = "Chi-Square", .values = .{ g2, null, null, null, null } });
        if (result.lower.chi_square == null) try rows.append(self.a, .{ .label = if (hypothesis == .equivalence) "Lower Margin Z" else "Z", .values = .{ result.lower.z, null, null, null, null } });
        if (result.lower.se) |se| {
            if (req.family != .relative_risk) {
                const upper_se = if (result.upper) |upper| upper.se orelse se else se;
                try rows.append(self.a, .{ .label = "Standard Error", .values = .{ @max(se, upper_se), null, null, null, null } });
            } else if (req.method == .fm) {
                try rows.append(self.a, .{ .label = if (hypothesis == .equivalence) "Lower Margin ASE (F-M)" else "ASE (F-M)", .values = .{ se, null, null, null, null } });
                if (result.upper) |upper| try rows.append(self.a, .{ .label = "Upper Margin ASE (F-M)", .values = .{ upper.se, null, null, null, null } });
            }
        }
        if (hypothesis == .equality and result.lower.chi_square == null) try rows.append(self.a, .{ .label = if ((result.lower.z orelse 0) > 0) "One-sided Pr > Z" else "One-sided Pr < Z", .values = .{ if ((result.lower.z orelse 0) > 0) result.lower.right else result.lower.left, null, null, null, null }, .probability = .{ true, false, false, false, false } });
        if (result.upper) |upper| {
            try rows.append(self.a, .{ .label = "Upper Margin Z", .values = .{ upper.z, null, null, null, null } });
            try rows.append(self.a, .{ .label = "Lower Margin Pr > Z", .values = .{ result.lower.right, null, null, null, null }, .probability = .{ true, false, false, false, false } });
            try rows.append(self.a, .{ .label = "Upper Margin Pr < Z", .values = .{ upper.left, null, null, null, null }, .probability = .{ true, false, false, false, false } });
        }
        try rows.append(self.a, .{ .label = if (result.lower.chi_square != null) "Pr > ChiSq" else if (hypothesis == .equality) "Two-sided Pr > |Z|" else if (hypothesis == .equivalence) "Overall P-Value" else "Pr > Z", .values = .{ result.p, null, null, null, null }, .probability = .{ true, false, false, false, false } });
        const subtitle = switch (hypothesis) {
            .equality => |v| try std.fmt.allocPrint(self.a, "Null = {d}; Method = {s}", .{ v, methodName(req.method) }),
            .greater => |v| try std.fmt.allocPrint(self.a, "Limit = {d}; Method = {s}", .{ v, methodName(req.method) }),
            .equivalence => |v| try std.fmt.allocPrint(self.a, "Equivalence Limits = {d}, {d}; Method = {s}", .{ v.lower, v.upper, methodName(req.method) }),
        };
        // Newcombe analysis provides confidence limits only, never a test.
        if (req.method == .newcombe) rows.shrinkRetainingCapacity(1);
        if (hypothesis != .equality) {
            try rows.append(self.a, .{ .label = try std.fmt.allocPrint(self.a, "{d}% Lower Conf Limit", .{100 - 200 * self.alpha}), .values = .{ result.limits.lower, null, null, null, null } });
            try rows.append(self.a, .{ .label = try std.fmt.allocPrint(self.a, "{d}% Upper Conf Limit", .{100 - 200 * self.alpha}), .values = .{ result.limits.upper, null, null, null, null } });
        }
        try self.add(title, subtitle, &.{"Value"}, rows.items, if (req.correct) "Continuity correction included." else "");
    }
};
fn methodName(m: p.Method) []const u8 {
    return switch (m) {
        .ac => "Agresti",
        .exact => "Clopper-Pearson (Exact)",
        .jeffreys => "Jeffreys",
        .lr => "Likelihood Ratio",
        .logit => "Logit",
        .midp => "Exact Mid-p",
        .wald => "Wald",
        .wilson => "Wilson",
        .ha => "Hauck-Anderson",
        .mn => "Miettinen-Nurminen",
        .newcombe => "Newcombe",
        .waldmodified => "Wald Modified",
        .fm => "Farrington-Manning",
    };
}
fn methodLabel(a: A, cl: p.CL, family: p.Family, correct: bool) ![]const u8 {
    const name = if (cl.method == .ac) (if (family == .binomial) "Agresti-Coull" else "Agresti-Caffo") else if (cl.method == .mn and family != .difference) "Score" else methodName(cl.method);
    return if (cl.correct or (correct and (cl.method == .wald or cl.method == .wilson or cl.method == .newcombe))) std.fmt.allocPrint(a, "{s} (Corrected)", .{name}) else if (cl.method == .mn and !cl.bias) std.fmt.allocPrint(a, "{s} (Uncorrected)", .{name}) else name;
}
fn ciRow(label: []const u8, ci: k.Interval) r.Row {
    return .{ .label = label, .values = .{ ci.lower, ci.upper, null, null, null } };
}
fn estRow(label: []const u8, e: k.Estimate) r.Row {
    return .{ .label = label, .values = .{ e.estimate, e.se, e.limits.lower, e.limits.upper, null } };
}
fn integer(x: f64) bool {
    return std.math.isFinite(x) and x >= 0 and x <= std.math.maxInt(u32) and x == @floor(x);
}
fn binLimits(b: *Builder, s: k.Binomial, cl: p.CL, correct: bool) diag.Error!k.Interval {
    if (cl.method == .midp) {
        if (!integer(s.success) or !integer(s.total)) return p.gap(b.d, 0, "exact mid-p for noninteger or oversized counts");
        const result = try exact.binomial(@intFromFloat(s.success), @intFromFloat(s.total), 0.5, b.alpha, true);
        return .{ .lower = result.limits.lower, .upper = result.limits.upper };
    }
    const method: k.BinomialMethod = switch (cl.method) {
        .wald => .wald,
        .exact => .clopper_pearson,
        .ac => .agresti_coull,
        .jeffreys => .jeffreys,
        .lr => .likelihood_ratio,
        .logit => .logit,
        .wilson => .wilson,
        else => unreachable,
    };
    return k.binomialLimits(s, b.alpha, method, correct or cl.correct);
}
fn hypotheses(b: *Builder, req: p.Request, table: ?k.Table2x2, sample: ?k.Binomial) diag.Error!void {
    var hs: std.ArrayList(infer.Hypothesis) = .empty;
    var names: std.ArrayList([]const u8) = .empty;
    if (req.family == .binomial or req.equal) {
        try hs.append(b.a, .{ .equality = if (req.family == .binomial) req.p else req.null_value });
        try names.append(b.a, "Equality Test");
    }
    const center: f64 = if (req.family == .binomial) req.p else 0;
    if (req.noninf) {
        const v = if (req.margin) |m| m[0] else if (req.family == .relative_risk) @as(f64, 0.8) else 0.2;
        try hs.append(b.a, .{ .greater = if (req.family == .relative_risk) v else center - v });
        try names.append(b.a, "Noninferiority Analysis");
    }
    if (req.sup) {
        const v = if (req.margin) |m| m[0] else if (req.family == .relative_risk) @as(f64, 1.25) else 0.2;
        try hs.append(b.a, .{ .greater = if (req.family == .relative_risk) v else center + v });
        try names.append(b.a, "Superiority Analysis");
    }
    if (req.equiv) {
        const m = req.margin orelse (if (req.family == .relative_risk) [2]f64{ 0.8, 1.25 } else [2]f64{ 0.2, 0.2 });
        const bounds = if (req.family == .relative_risk) [2]f64{ m[0], if (req.paired_margin or req.margin == null) m[1] else 1 / m[0] } else [2]f64{ center + (if (req.paired_margin) m[0] else -m[0]), center + m[1] };
        try hs.append(b.a, .{ .equivalence = .{ .lower = bounds[0], .upper = bounds[1] } });
        try names.append(b.a, "Equivalence Analysis");
    }
    for (hs.items, names.items) |h, name| {
        const variance = req.variance orelse (if (req.family == .binomial and h == .equality) infer.Variance.null_value else .sample);
        const result = (switch (req.family) {
            .binomial => infer.binomial(sample.?, h, variance, b.alpha, req.correct),
            .difference => infer.difference(table.?, if (req.column == 0) .first else .second, h, switch (req.method) {
                .wald => .wald,
                .ha => .hauck_anderson,
                .fm => .farrington_manning,
                .newcombe => .newcombe,
                else => unreachable,
            }, variance, b.alpha, req.correct),
            .relative_risk => infer.relativeRisk(table.?, if (req.column == 0) .first else .second, h, ratioMethod(req.method), b.alpha),
            .odds_ratio => unreachable,
        }) catch |err| {
            if (err == error.OutOfMemory) return err;
            return b.d.fail(error.ExecError, 0, "PROC FREQ: invalid risk hypothesis, margins, or confidence level", .{});
        };
        const family_name = if (req.family == .binomial) "Binomial Proportion" else if (req.family == .difference) "Risk Difference" else "Relative Risk";
        const point: ?f64 = if (sample) |s| s.proportion() else if (req.family == .difference) (try k.difference(table.?, if (req.column == 0) .first else .second, b.alpha, false)).estimate else (try k.ratio(table.?, if (req.column == 0) .first else .second, .relative_risk, b.alpha, .wald, true)).estimate;
        const modified: ?f64 = if (req.method == .waldmodified) (try k.ratio(table.?, if (req.column == 0) .first else .second, .relative_risk, b.alpha, .wald_modified, true)).estimate else null;
        const title = if (req.family == .binomial) try std.fmt.allocPrint(b.a, "{s} for the {s}", .{ name, family_name }) else try std.fmt.allocPrint(b.a, "{s} for the {s} (Column {d})", .{ name, family_name, req.column + 1 });
        try b.inference(req, h, result, title, point, modified);
    }
}
fn ratioMethod(m: p.Method) k.RatioMethod {
    return switch (m) {
        .wald => .wald,
        .waldmodified => .wald_modified,
        .lr => .likelihood_ratio,
        .mn, .fm => .score,
        else => unreachable,
    };
}
pub fn execute(a: A, d: *diag.Diagnostics, table: Table, options: p.Options, alpha: f64) diag.Error!r.Report {
    if (!options.any()) return .{};
    var b = Builder{ .a = a, .d = d, .alpha = alpha };
    var total: f64 = 0;
    for (table.counts) |v| total += v;
    if (table.one_way) {
        if (options.binomial) |req| {
            const index: usize = switch (req.level) {
                .number => |n| if (n > table.row_labels.len) return d.fail(error.ExecError, 0, "PROC FREQ: binomial LEVEL is outside the table", .{}) else n - 1,
                .value => |v| blk: {
                    for (table.row_labels, 0..) |label, i| if (std.mem.eql(u8, v, label)) break :blk i;
                    return d.fail(error.ExecError, 0, "PROC FREQ: binomial LEVEL value not found", .{});
                },
            };
            if (total <= 0) {
                try d.report(.note, 0, "No statistics are computed for the table of {s} because it contains no observations with positive weights.", .{table.name});
                return .{};
            }
            const s = k.Binomial{ .success = table.counts[index], .total = total };
            const estimate = try k.proportion(s, alpha, req.correct);
            const subtitle = try std.fmt.allocPrint(a, "{s} = {s}", .{ table.name, table.row_labels[index] });
            if (req.cls.len == 0) try b.estimates("Binomial Proportion", subtitle, &.{estRow("Proportion", estimate)}, "") else try b.add("Binomial Proportion", subtitle, &.{ "Estimate", "ASE" }, &.{estRow("Proportion", estimate)}, "");
            var rows: std.ArrayList(r.Row) = .empty;
            const cls = if (req.cls.len == 0) &[_]p.CL{.{ .method = .exact }} else req.cls;
            var integer_counts = true;
            for (table.counts) |v| if (!integer(v)) {
                integer_counts = false;
            };
            for (cls) |cl| {
                if (cl.method == .exact and !integer_counts) continue;
                try rows.append(a, ciRow(try methodLabel(a, cl, .binomial, req.correct), try binLimits(&b, s, cl, req.correct)));
            }
            if (rows.items.len > 0) try b.intervals("Confidence Limits for the Binomial Proportion", "", rows.items);
            var test_req = req;
            for (req.cls) |cl| if (cl.method == .wald and cl.correct) {
                test_req.correct = true;
            };
            try hypotheses(&b, test_req, null, s);
        }
    } else if (table.row_labels.len == 2 and table.col_labels.len == 2 and table.counts.len == 4) {
        const t = k.Table2x2{ .cells = table.counts[0..4].* };
        const c = t.cells;
        if (c[0] + c[1] == 0 or c[2] + c[3] == 0 or c[0] + c[2] == 0 or c[1] + c[3] == 0) return .{};
        if (options.senspec) {
            const s = try k.sensitivity(t, alpha);
            try b.estimates("Sensitivity and Specificity", "", &.{ estRow("Sensitivity", s.sensitivity), estRow("Specificity", s.specificity), estRow("Positive Predictive Value", s.positive_predictive), estRow("Negative Predictive Value", s.negative_predictive) }, "");
        }
        if (options.difference) |req| {
            if (!req.norisks) for (0..2) |col| {
                const s = t.samples(if (col == 0) .first else .second);
                const all = k.Binomial{ .success = s[0].success + s[1].success, .total = total };
                const title = try std.fmt.allocPrint(a, "Column {d} Risk Estimates", .{col + 1});
                try b.estimates(title, "", &.{ estRow("Row 1", try k.proportion(s[0], alpha, req.correct)), estRow("Row 2", try k.proportion(s[1], alpha, req.correct)), estRow("Total", try k.proportion(all, alpha, req.correct)), estRow("Difference", try k.difference(t, if (col == 0) .first else .second, alpha, req.correct)) }, "Difference is (Row 1 - Row 2)");
                var exact_counts = true;
                for (c) |v| if (!integer(v)) {
                    exact_counts = false;
                };
                if (exact_counts) try b.intervals(try std.fmt.allocPrint(a, "Column {d} Exact Risk Confidence Limits", .{col + 1}), "", &.{ ciRow("Row 1", try k.binomialLimits(s[0], alpha, .clopper_pearson, false)), ciRow("Row 2", try k.binomialLimits(s[1], alpha, .clopper_pearson, false)), ciRow("Total", try k.binomialLimits(all, alpha, .clopper_pearson, false)) });
            };
            for (0..@as(usize, if (req.both_columns) 2 else 1)) |col_index| {
                var current = req;
                if (req.both_columns) current.column = col_index;
                var rows: std.ArrayList(r.Row) = .empty;
                for (current.cls) |cl| {
                    const method: k.DifferenceMethod = switch (cl.method) {
                        .wald => .wald,
                        .ac => .agresti_caffo,
                        .ha => .hauck_anderson,
                        .mn => .miettinen_nurminen,
                        .newcombe => .newcombe,
                        else => unreachable,
                    };
                    try rows.append(a, ciRow(try methodLabel(a, cl, .difference, current.correct), try k.differenceLimits(t, if (current.column == 0) .first else .second, alpha, method, current.correct or cl.correct, cl.bias)));
                }
                if (rows.items.len > 0) {
                    const point = try k.difference(t, if (current.column == 0) .first else .second, alpha, current.correct);
                    try b.intervals("Confidence Limits for the Risk Difference", try std.fmt.allocPrint(a, "Risk Difference = {d:.4}; Column {d} ({s} = {s})", .{ point.estimate.?, current.column + 1, table.column_name, table.col_labels[current.column] }), rows.items);
                }
                try hypotheses(&b, current, t, null);
            }
        }
        const default_ratios = if (options.relative_risk) |req| (req.printall or (req.cls.len == 0 and !req.tests())) else false;
        const default_odds = if (options.odds_ratio) |req| req.cls.len == 0 else false;
        if ((default_ratios or default_odds) and !table.legacy_risks_printed) {
            var rows: [3]r.Row = undefined;
            for ([_]k.RatioKind{ .odds_ratio, .relative_risk, .relative_risk }, 0..) |kind, i| {
                const v = try k.ratio(t, if (i == 2) .second else .first, kind, alpha, .wald, true);
                rows[i] = .{ .label = ([_][]const u8{ "Odds Ratio", "Relative Risk (Column 1)", "Relative Risk (Column 2)" })[i], .values = .{ v.estimate, v.limits.lower, v.limits.upper, null, null } };
            }
            const cols = try a.alloc([]const u8, 3);
            cols[0] = "Value";
            cols[1] = try b.level("Lower CL");
            cols[2] = try b.level("Upper CL");
            try b.add("Odds Ratio and Relative Risks", "", cols, &rows, "");
        }
        for ([_]?p.Request{ options.odds_ratio, options.relative_risk }) |maybe| if (maybe) |req| {
            var rows: std.ArrayList(r.Row) = .empty;
            for (req.cls) |cl| {
                const ci: k.Interval = if (cl.method == .midp) blk: {
                    var cells: [4]u32 = undefined;
                    for (c, 0..) |v, i| {
                        if (!integer(v)) return p.gap(d, 0, "exact odds limits for noninteger counts");
                        cells[i] = @intFromFloat(v);
                    }
                    const v = switch (try exact.oddsRatio(cells, alpha, true, 1000000)) {
                        .complete => |ci| ci,
                        .exhausted => return p.gap(d, 0, "exact odds confidence limit resource budget exhausted"),
                    };
                    break :blk .{ .lower = v.lower, .upper = v.upper };
                } else (try k.ratio(t, if (req.column == 0) .first else .second, if (req.family == .odds_ratio) .odds_ratio else .relative_risk, alpha, ratioMethod(cl.method), cl.bias)).limits;
                try rows.append(a, ciRow(try methodLabel(a, cl, req.family, false), ci));
            }
            if (rows.items.len > 0) {
                const kind: k.RatioKind = if (req.family == .odds_ratio) .odds_ratio else .relative_risk;
                const column: k.Column = if (req.column == 0) .first else .second;
                const point = try k.ratio(t, column, kind, alpha, .wald, true);
                const modified = try k.ratio(t, column, kind, alpha, .wald_modified, true);
                var values: std.ArrayList(r.Row) = .empty;
                try values.append(a, .{ .label = if (kind == .odds_ratio) "Odds Ratio" else "Relative Risk", .values = .{ point.estimate, null, null, null, null } });
                for (req.cls) |cl| if (cl.method == .waldmodified) {
                    try values.append(a, .{ .label = if (kind == .odds_ratio) "Modified Odds Ratio" else "Modified Relative Risk", .values = .{ modified.estimate, null, null, null, null } });
                    break;
                };
                const subtitle = if (req.family == .odds_ratio) "" else try std.fmt.allocPrint(a, "Column {d} ({s} = {s})", .{ req.column + 1, table.column_name, table.col_labels[req.column] });
                try b.add("Risk Estimates", subtitle, &.{"Value"}, values.items, "");
                try b.intervals(if (req.family == .odds_ratio) "Confidence Limits for the Odds Ratio" else "Confidence Limits for the Relative Risk", subtitle, rows.items);
            }
            if (req.family == .relative_risk) try hypotheses(&b, req, t, null);
        };
    }
    const sample_size: ?f64 = if (b.sections.items.len > 0) total else null;
    return .{ .sections = try b.sections.toOwnedSlice(a), .sample_size = sample_size };
}

test "FEAT-freq-risk public adapter corrected Wald test and fractional exact omission" {
    // Independent public/semantics.sas: CL=WALD(CORRECT) Z=-1.1180,
    // CL=WILSON(CORRECT) Z=-1.3416. Fractional 1.9/10.6 has no CP limits.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const table = Table{ .name = "x", .row_labels = &.{ "1", "2" }, .counts = &.{ 7, 13 }, .one_way = true };
    for ([_]p.Method{ .wald, .wilson }, [_]f64{ -1.1180, -1.3416 }) |method, z| {
        const cls = [_]p.CL{.{ .method = method, .correct = true }};
        const report = try execute(a, &d, table, .{ .binomial = .{ .family = .binomial, .cls = &cls } }, 0.05);
        var found = false;
        for (report.sections) |section| for (section.rows) |row| if (std.mem.eql(u8, row.label, "Z")) {
            try std.testing.expectApproxEqAbs(z, row.values[0].?, 0.00005);
            found = true;
        };
        try std.testing.expect(found);
    }
    const fractional = try execute(a, &d, .{ .name = "x", .row_labels = &.{ "1", "2" }, .counts = &.{ 1.9, 8.7 }, .one_way = true }, .{ .binomial = .{ .family = .binomial } }, 0.05);
    for (fractional.sections) |section| for (section.rows) |row| try std.testing.expect(!std.mem.eql(u8, row.label, "Clopper-Pearson (Exact)"));
}
test "FEAT-freq-risk public adapter selects formatted levels and columns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const b = try execute(a, &d, .{ .name = "x", .row_labels = &.{ "Other", "Event" }, .counts = &.{ 13, 7 }, .one_way = true }, .{ .binomial = .{ .family = .binomial, .level = .{ .value = "Event" } } }, 0.6);
    try std.testing.expectEqualStrings("x = Event", b.sections[0].subtitle);
    try std.testing.expectApproxEqAbs(@as(f64, 0.35), b.sections[0].rows[0].values[0].?, 1e-15);
    try std.testing.expectEqual(@as(?f64, 20), b.sample_size);
    const report = try execute(a, &d, .{ .name = "r", .column_name = "c", .row_labels = &.{ "1", "2" }, .col_labels = &.{ "1", "2" }, .counts = &.{ 12, 8, 5, 25 } }, .{ .relative_risk = .{ .family = .relative_risk, .column = 1, .cls = &.{.{ .method = .waldmodified }} } }, 0.05);
    var found = false;
    for (report.sections) |section| for (section.rows) |row| if (std.mem.eql(u8, row.label, "Wald Modified")) {
        try std.testing.expectApproxEqAbs(@as(f64, 0.2896), row.values[0].?, 0.00005);
        try std.testing.expectApproxEqAbs(@as(f64, 0.8492), row.values[1].?, 0.00005);
        found = true;
    };
    try std.testing.expect(found);
}

test "FEAT-freq-risk SAS remaining NI SUP methods and LR equality reporting" {
    // SAS/STAT pp190-194,206-209. Independent command:
    // /Users/thomas/sas/bin/sasrun /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/tests-remaining.sas
    // -f text -o /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/tests-remaining.txt
    // -l /tmp/opensas-stat-batch2/FEAT-freq-risk/acceptance/tests-remaining.log
    // SAS prints four decimals; half-last-digit tolerance remains .00005.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const table = Table{ .name = "r", .column_name = "c", .row_labels = &.{ "1", "2" }, .col_labels = &.{ "1", "2" }, .counts = &.{ 12, 8, 5, 25 } };
    const methods = [_]p.Method{ .wald, .ha, .fm, .newcombe };
    const z_sup = [_]?f64{ 1.8094, 1.5784, 1.7156, null };
    const lo_sup = [_]f64{ 0.2212, 0.1912, 0.2096, 0.2052 };
    for (methods, z_sup, lo_sup) |method, z, lo| {
        const report = try execute(a, &d, table, .{ .difference = .{ .family = .difference, .sup = true, .norisks = true, .method = method, .margin = .{ 0.2, 0.2 } } }, 0.05);
        try std.testing.expectEqual(@as(usize, 1), report.sections.len);
        var seen_z = false;
        var seen_lo = false;
        for (report.sections[0].rows) |row| {
            if (std.mem.eql(u8, row.label, "Z")) {
                try std.testing.expect(z != null);
                try std.testing.expectApproxEqAbs(z.?, row.values[0].?, 0.00005);
                seen_z = true;
            }
            if (std.mem.eql(u8, row.label, "90% Lower Conf Limit")) {
                try std.testing.expectApproxEqAbs(lo, row.values[0].?, 0.00005);
                seen_lo = true;
            }
        }
        try std.testing.expectEqual(z != null, seen_z);
        try std.testing.expect(seen_lo);
    }
    const lr = try execute(a, &d, table, .{ .relative_risk = .{ .family = .relative_risk, .equal = true, .null_value = 2, .method = .lr } }, 0.05);
    var seen_chi = false;
    var seen_p = false;
    for (lr.sections[0].rows) |row| {
        try std.testing.expect(!std.mem.eql(u8, row.label, "Z"));
        try std.testing.expect(!std.mem.eql(u8, row.label, "Two-sided Pr > |Z|"));
        if (std.mem.eql(u8, row.label, "Chi-Square")) {
            try std.testing.expectApproxEqAbs(@as(f64, 2.0027), row.values[0].?, 0.00005);
            seen_chi = true;
        }
        if (std.mem.eql(u8, row.label, "Pr > ChiSq")) {
            try std.testing.expectApproxEqAbs(@as(f64, 0.1570), row.values[0].?, 0.00005);
            seen_p = true;
        }
    }
    try std.testing.expect(seen_chi and seen_p);
}

test "FEAT-freq-risk public high alpha preserves SAS reversed confidence limits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var d = diag.Diagnostics.init(arena.allocator());
    const sections = try execute(arena.allocator(), &d, .{ .name = "x", .row_labels = &.{ "1", "2" }, .counts = &.{ 7, 13 }, .one_way = true }, .{ .binomial = .{ .family = .binomial, .noninf = true } }, 0.6);
    var found: usize = 0;
    for (sections.sections) |section| for (section.rows) |row| {
        if (std.mem.endsWith(u8, row.label, "% Lower Conf Limit")) {
            try std.testing.expectApproxEqAbs(@as(f64, 0.3770), row.values[0].?, 0.00005);
            found += 1;
        }
        if (std.mem.endsWith(u8, row.label, "% Upper Conf Limit")) {
            try std.testing.expectApproxEqAbs(@as(f64, 0.3230), row.values[0].?, 0.00005);
            found += 1;
        }
    };
    try std.testing.expectEqual(@as(usize, 2), found);
    try std.testing.expect(!d.hasErrors());
}
