//! PROC LOGISTIC ROC orchestration over a common complete-case design.
const std = @import("std");
const diag = @import("../diag.zig");
const proc = @import("../proc.zig");
const logistic = @import("logistic.zig");
const design = @import("logistic_design.zig");
const kernel = @import("logistic_fit.zig");
const roc = @import("logistic_roc.zig");
const fns = @import("../functions.zig");
const format = @import("../format.zig");
const A = std.mem.Allocator;
fn num(a: A, value: f64, spec: []const u8) ![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ");
}
fn sameTerm(left: []const usize, right: []const usize) bool {
    if (left.len != right.len) return false;
    for (left) |value| if (std.mem.count(usize, left, &.{value}) != std.mem.count(usize, right, &.{value})) return false;
    return true;
}
pub fn subset(a: A, d: design.Design, terms: []const []const usize) diag.Error!design.Design {
    var columns: std.ArrayList(usize) = .empty;
    try columns.append(a, 0);
    var parameters: std.ArrayList(design.Parameter) = .empty;
    try parameters.append(a, d.parameters[0]);
    var effects: std.ArrayList(design.Effect) = .empty;
    for (terms) |term| {
        const source = for (d.effects) |effect| {
            if (sameTerm(effect.variables, term)) break effect;
        } else return error.ExecError;
        var effect = source;
        effect.start = columns.items.len;
        for (source.start..source.start + source.len) |column| {
            try columns.append(a, column);
            try parameters.append(a, d.parameters[column]);
        }
        try effects.append(a, effect);
    }
    var result = d;
    result.p = columns.items.len;
    const x = try a.alloc(f64, d.n * result.p);
    for (0..d.n) |i| for (columns.items, 0..) |column, j| {
        x[i * result.p + j] = d.x[i * d.p + column];
    };
    result.x = x;
    result.parameters = parameters.items;
    result.effects = effects.items;
    return result;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: logistic.Spec) diag.Error!void {
    const a = cx.arena;
    if (s.by_columns.len > 0 or s.model.classes.len > 0 or s.link != .logit or s.clodds != null or s.units_present or s.odds_requests.len > 0) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: this combination with ROC analysis is not implemented", .{});
    const base = try logistic.analyze(cx, s);
    if (s.nofit) try cx.diags.note(0, "The NOFIT option is specified. No parameters are estimated for the MODEL statement.", .{});
    if (base.design.response.levels.len != 2) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ROC analysis requires a binary response", .{});
    var body: std.ArrayList(u8) = .empty;
    if (!s.noprint) {
        if (s.nofit) {
            try logistic.modelHeader(a, &body, s, base.design, base.counts, 1);
            try body.print(a, "Score Test for Global Null Hypothesis\n\nChi-Square DF Pr > ChiSq\n\n{s} {d} {s}\n\n", .{ try num(a, base.fit.score_test, "10.4"), base.design.p - 1, try num(a, kernel.chiTail(base.fit.score_test, base.design.p - 1), "pvalue6.4") });
        } else try logistic.render(a, &body, s, base.design, base.fit, base.counts);
    }
    var labels: std.ArrayList([]const u8) = .empty;
    var scores: std.ArrayList([]const f64) = .empty;
    if (!s.nofit) {
        try labels.append(a, "Model");
        try scores.append(a, base.fit.probabilities);
    }
    for (s.roc_models) |model| {
        for (labels.items) |old| if (std.mem.eql(u8, old, model.label)) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: ROC labels must be unique", .{});
        try labels.append(a, model.label);
        if (model.pred) |column| {
            if (base.data.columns.items[column].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: ROC PRED variable must be numeric", .{});
            const values = try a.alloc(f64, base.design.n);
            for (base.design.source_rows, values) |source, *value| {
                value.* = base.data.rows.items[source][column].num;
                if (!std.math.isFinite(value.*)) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: missing/nonfinite ROC PRED values are not implemented", .{});
            }
            try scores.append(a, values);
        } else {
            const d = subset(a, base.design, model.terms) catch |err| {
                if (err == error.OutOfMemory) return err;
                return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: ROC effects must occur in MODEL", .{});
            };
            const fit = kernel.fitWeighted(a, d.x, d.y, d.n, d.p, d.frequencies, d.weights, .{}) catch |err| {
                if (err == error.OutOfMemory) return err;
                return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ROC model fitting failed", .{});
            };
            try scores.append(a, fit.probabilities);
            try cx.diags.note(0, "Convergence criterion (GCONV=1E-8) satisfied for {s}.", .{model.label});
            if (!s.noprint) {
                try body.print(a, "\nROC Model: {s}\n\n", .{model.label});
                if (s.roc_nodetails) try body.appendSlice(a, "Model Convergence Status\n\nConvergence criterion (GCONV=1E-8) satisfied.\n\n") else {
                    var details = s;
                    details.roc_detail = true;
                    details.fit_options = .{};
                    try logistic.render(a, &body, details, d, fit, base.counts);
                }
            }
        }
    }
    if (scores.items.len == 0) {
        if (s.roc_plot or s.roc_contrast != null) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: no fitted ROC curve is available", .{});
        try out.appendSlice(a, body.items);
        return;
    }
    const result = roc.compute(a, base.design.y, scores.items, base.design.frequencies, s.roc_epsilon) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ROC covariance requires two events/nonevents and unambiguous finite score groups", .{});
    };
    const k = result.curves.len;
    const alpha = s.roc_alpha orelse s.alpha;
    const z = fns.distQuantile(.normal, 1 - alpha / 2, &.{}).?;
    if (!s.noprint and s.roc_models.len > 0) {
        try body.print(a, "\nROC Association Statistics\n\n--------------- Mann-Whitney ---------------\nStandard {s}% Wald\nROC Model Area Error Confidence Limits Somers' D Gamma Tau-a\n\n", .{try num(a, 100 * (1 - alpha), "best8.")});
        const pairs = result.events * result.nonevents;
        const total = result.events + result.nonevents;
        for (result.curves, labels.items, 0..) |curve, label, i| {
            const se = @sqrt(@max(0, result.covariance[i * k + i]));
            const delta = curve.concordant - curve.discordant;
            try body.print(a, "{s} {s} {s} {s} {s} {s} {s} {s}\n", .{ label, try num(a, curve.area, "8.4"), try num(a, se, "8.4"), try num(a, curve.area - z * se, "8.4"), try num(a, curve.area + z * se, "8.4"), try num(a, delta / pairs, "8.4"), try num(a, delta / (curve.concordant + curve.discordant), "8.4"), try num(a, 2 * delta / (total * (total - 1)), "8.4") });
        }
    }
    if (s.roc_contrast) |request| {
        if (k < 2) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: ROC comparison needs at least two curves", .{});
        var reference: usize = 0;
        if (request.reference) |wanted| reference = for (labels.items, 0..) |label, i| {
            if (std.mem.eql(u8, wanted, label)) break i;
        } else return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: ROC reference label not found", .{});
        var coefficients: []const f64 = undefined;
        if (request.kind == .reference) coefficients = try roc.referenceContrast(a, k, reference) else if (request.kind == .adjacent) {
            const matrix = try a.alloc(f64, (k - 1) * k);
            @memset(matrix, 0);
            for (0..k - 1) |i| {
                matrix[i * k + i] = 1;
                matrix[i * k + i + 1] = -1;
            }
            coefficients = matrix;
        } else {
            if (request.columns != k) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: ROC contrast dimension does not match model count", .{});
            coefficients = request.coefficients;
        }
        const nr = coefficients.len / k;
        const test_result = roc.contrastTest(a, result, coefficients, nr) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ROC contrast is not estimable", .{});
        };
        if (!s.noprint) {
            if (request.display) {
                try body.appendSlice(a, "\nROC Contrast Coefficients\n\nROC Model");
                for (0..nr) |i| try body.print(a, " Row{d}", .{i + 1});
                try body.appendSlice(a, "\n\n");
                for (labels.items, 0..) |label, j| {
                    try body.appendSlice(a, label);
                    for (0..nr) |i| try body.print(a, " {s}", .{try num(a, coefficients[i * k + j], "best12.")});
                    try body.appendSlice(a, "\n");
                }
            }
            const label = request.label orelse switch (request.kind) {
                .reference => try std.fmt.allocPrint(a, "Reference = {s}", .{labels.items[reference]}),
                .adjacent => "Adjacent Pairwise Differences",
                .matrix => "Specified",
            };
            try body.print(a, "\nROC Contrast Test Results\n\nContrast DF Chi-Square Pr > ChiSq\n\n{s} {d} {s} {s}\n", .{ label, test_result.rank, try num(a, test_result.chi_square, "8.4"), try num(a, kernel.chiTail(test_result.chi_square, test_result.rank), "pvalue6.4") });
            if (request.estimates) {
                var estimate_coefficients = coefficients;
                if (request.all_pairs) {
                    const matrix = try a.alloc(f64, k * (k - 1) / 2 * k);
                    @memset(matrix, 0);
                    var r: usize = 0;
                    for (0..k) |i| for (i + 1..k) |j| {
                        matrix[r * k + i] = 1;
                        matrix[r * k + j] = -1;
                        r += 1;
                    };
                    estimate_coefficients = matrix;
                }
                const estimates = roc.contrastTest(a, result, estimate_coefficients, estimate_coefficients.len / k) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ROC row contrast is not estimable", .{});
                };
                try body.print(a, "\nROC Contrast Estimation and Testing Results by Row\n\nStandard {s}% Wald Pr >\nContrast Estimate Error Confidence Limits Chi-Square ChiSq\n\n", .{try num(a, 100 * (1 - alpha), "best8.")});
                for (estimates.estimates, 0..) |value, i| {
                    const dimension = estimates.estimates.len;
                    const se = @sqrt(@max(0, estimates.covariance[i * dimension + i]));
                    var positive: ?usize = null;
                    var negative: ?usize = null;
                    for (estimate_coefficients[i * k ..][0..k], 0..) |coefficient, j| {
                        if (coefficient == 1) positive = j;
                        if (coefficient == -1) negative = j;
                    }
                    const row_label = if ((request.kind != .matrix or request.all_pairs) and positive != null and negative != null) try std.fmt.allocPrint(a, "{s} - {s}", .{ labels.items[positive.?], labels.items[negative.?] }) else try std.fmt.allocPrint(a, "Row{d}", .{i + 1});
                    const q = if (se > 0) value * value / (se * se) else std.math.nan(f64);
                    try body.print(a, "{s} {s} {s} {s} {s} {s} {s}\n", .{ row_label, try num(a, value, "8.4"), try num(a, se, "8.4"), try num(a, value - z * se, "8.4"), try num(a, value + z * se, "8.4"), try num(a, q, "8.4"), try num(a, kernel.chiTail(q, 1), "pvalue6.4") });
                }
            }
        }
    }
    if (!s.noprint and !s.plots_none) if (cx.graphics) |graphics| if (graphics.enabled == true or (graphics.enabled != false and graphics.cli_dir != null)) {
        const render = @import("logistic_roc_plot.zig");
        for (result.curves, labels.items, 0..) |curve, label, i| {
            const bytes = render.svg(a, &.{curve}, &.{label}, s.roc_id_probability, false) catch return error.OutOfMemory;
            try graphics.queue(i, "logistic-roc", bytes, .{ .name = .ROCCurve, .label = label, .template = null, .path = "Logistic.ROCCurve" });
        }
        if (k > 1) {
            const bytes = render.svg(a, result.curves, labels.items, false, true) catch return error.OutOfMemory;
            try graphics.queue(k, "logistic-roc-overlay", bytes, .{ .name = .ROCOverlay, .label = "ROC Curves", .template = null, .path = "Logistic.ROCOverlay" });
        }
    };
    try out.appendSlice(a, body.items);
}

fn originalDataset(a: A) !struct { ds: @import("../dataset.zig").Dataset, source: []const u8 } {
    const source = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic012_original.sas", a, .limited(1024 * 1024));
    const start = std.mem.indexOf(u8, source, "datalines;").? + "datalines;".len;
    const data = source[start..][0..std.mem.indexOfScalar(u8, source[start..], ';').?];
    var tokens = std.mem.tokenizeAny(u8, data, " \r\n\t");
    var ds = @import("../dataset.zig").Dataset.init(a, "roc");
    for ([_][]const u8{ "alb", "tp", "totscore", "popind" }) |name| _ = try ds.addColumn(name, .num);
    while (tokens.next()) |first| {
        var row: [4]@import("../value.zig").Value = undefined;
        row[0] = .{ .num = try std.fmt.parseFloat(f64, first) };
        for (1..4) |j| row[j] = .{ .num = try std.fmt.parseFloat(f64, tokens.next().?) };
        row[2].num = 10 - row[2].num; // original DATA step transformation
        try ds.appendRow(&row);
    }
    return .{ .ds = ds, .source = source };
}
test "LOGISTIC012 complete original listing ROC identities and every plotted coordinate persist" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try originalDataset(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("roc", &fixture.ds);
    var d = diag.Diagnostics.init(a);
    var listing: @import("../ods_listing.zig").Listing = .{ .trace = &d };
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true, .listing = &listing };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    const program = fixture.source[std.mem.indexOf(u8, fixture.source, "proc logistic data=roc").?..];
    const tokens = try @import("../lexer.zig").tokenize(a, program, &d);
    const spec = try logistic.parse(cx, tokens);
    var out: std.ArrayList(u8) = .empty;
    try logistic.run(cx, &out, tokens);
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/stat_logistic012_original.txt", a, .limited(1024 * 1024));
    var words = std.mem.tokenizeAny(u8, expected["# corpus assertions\nwords ".len..], " \r\n\t");
    var actual = std.mem.tokenizeAny(u8, out.items, " \r\n\t");
    while (words.next()) |word| try std.testing.expectEqualStrings(word, actual.next() orelse "<missing>");
    try std.testing.expect(actual.next() == null);
    try std.testing.expect(!d.hasErrors());
    for (d.list.items) |item| try std.testing.expectEqual(diag.Severity.note, item.severity);
    const diagnostics = try d.render();
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, diagnostics, "Name:       ROCCurve"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, diagnostics, "Name:       ROCOverlay"));
    try std.testing.expectEqual(@as(usize, 4), graphics.prepared.items.len);
    const base = try logistic.analyze(cx, spec);
    for (spec.roc_models, 0..) |model, i| {
        const dm = try subset(a, base.design, model.terms);
        const fit = try kernel.fitWeighted(a, dm.x, dm.y, dm.n, dm.p, dm.frequencies, dm.weights, .{});
        const artifact = graphics.prepared.items[i];
        try std.testing.expectEqualStrings("logistic-roc", artifact.kind);
        try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "Sensitivity") != null);
        try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, "1 - Specificity") != null);
        // Independently count threshold classifications, then locate each
        // corresponding SVG vertex and geometry metadata. The graph receives
        // every threshold, not merely the endpoints/AUC or selected labels.
        var thresholds: std.ArrayList(f64) = .empty;
        for (fit.probabilities) |p| if (std.mem.indexOfScalar(f64, thresholds.items, p) == null) try thresholds.append(a, p);
        for (thresholds.items) |cutpoint| {
            var positives: f64 = 0;
            var false_positives: f64 = 0;
            for (fit.probabilities, dm.y, dm.frequencies) |p, y, f| if (p >= cutpoint) {
                if (y == 1) positives += f else false_positives += f;
            };
            const sensitivity = positives / 12;
            const fpr = false_positives / 31;
            const metadata = try std.fmt.allocPrint(a, "data-threshold=\"{d}\" data-sensitivity=\"{d}\" data-fpr=\"{d}\" data-positive=\"{d}\" data-negative=\"{d}\" data-x=\"{d}\" data-y=\"{d}\"", .{ cutpoint, sensitivity, fpr, positives, 31 - false_positives, 90 + 600 * fpr, 590 - 500 * sensitivity });
            try std.testing.expect(std.mem.indexOf(u8, artifact.bytes, metadata) != null);
        }
        try std.testing.expectEqual(thresholds.items.len + 1, std.mem.count(u8, artifact.bytes, "class=\"roc-point\""));
        // Public figures on physical pp.6023,6024,6026 label these exact
        // upper-left corners, rounded to two decimals. Geometry tests above
        // retain full precision for every vertex, including unlabeled points.
        const label_values = [_][]const f64{ &.{ 0.82, 0.66, 0.46, 0.33, 0.27, 0.21, 0.15, 0.12 }, &.{ 0.65, 0.46, 0.28, 0.16, 0.08 }, &.{ 0.58, 0.47, 0.45, 0.32, 0.31, 0.26, 0.21, 0.2, 0.19, 0.13 } };
        var labels_xml = std.mem.splitSequence(u8, artifact.bytes, "<text class=\"cutpoint\"");
        _ = labels_xml.next();
        for (label_values[i]) |expected_label| {
            const element = labels_xml.next() orelse return error.TestExpectedEqual;
            const value_start = std.mem.indexOfScalar(u8, element, '>').? + 1;
            const value_end = std.mem.indexOf(u8, element[value_start..], "</text>").?;
            try std.testing.expectEqual(expected_label, try std.fmt.parseFloat(f64, element[value_start..][0..value_end]));
        }
        try std.testing.expect(labels_xml.next() == null);
    }
    try std.testing.expectEqualStrings("logistic-roc-overlay", graphics.prepared.items[3].kind);
    for (spec.roc_models) |model| try std.testing.expect(std.mem.indexOf(u8, graphics.prepared.items[3].bytes, model.label) != null);
}

test "LOGISTIC012 plot suppression selection and NODETAILS retain documented controls" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var fixture = try originalDataset(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("roc", &fixture.ds);
    for ([_]usize{ 0, 1, 2 }) |mode| {
        var d = diag.Diagnostics.init(a);
        var listing: @import("../ods_listing.zig").Listing = .{ .trace = &d };
        if (mode == 2) _ = try listing.parse(a, &d, try @import("../lexer.zig").tokenize(a, "ods select ROCOverlay;", &d));
        var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = mode != 0, .listing = &listing };
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
        const source = try std.fmt.allocPrint(a, "proc logistic data=roc {s} rocoptions(nodetails alpha=0.1); model popind(event='0')=alb tp totscore / nofit; roc 'Albumin' alb; roc 'K-G Score' totscore; roc 'Total Protein' tp; roccontrast adjacentpairs / estimate=allpairs e; run;", .{if (mode == 1) "plots=none" else "plots=roc(id=prob)"});
        var out: std.ArrayList(u8) = .empty;
        try logistic.run(cx, &out, try @import("../lexer.zig").tokenize(a, source, &d));
        try std.testing.expect(!d.hasErrors());
        try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, out.items, "Model Convergence Status"));
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Model Fit Statistics") == null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "90% Wald") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Adjacent Pairwise Differences 2") != null);
        try std.testing.expect(std.mem.indexOf(u8, out.items, "Albumin - Total Protein") != null);
        try std.testing.expectEqual(@as(usize, if (mode == 2) 1 else 0), graphics.prepared.items.len);
        if (mode == 2) try std.testing.expectEqualStrings("logistic-roc-overlay", graphics.prepared.items[0].kind);
    }
}

test "LOGISTIC012 NOFIT avoids separated full fit and PRED matrix comparisons are self contained" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = @import("../dataset.zig").Dataset.init(a, "scores");
    for ([_][]const u8{ "y", "x", "score1", "score2" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][4]f64{ .{ 1, 1, 0.9, 0.1 }, .{ 1, 1, 0.8, 0.8 }, .{ 0, 0, 0.8, 0.8 }, .{ 0, 0, 0.1, 0.9 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("scores", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = "proc logistic data=scores; model y(event='1')=x / nofit; roc 'First' pred=score1; roc 'Second' pred=score2; roccontrast 1 -1 / estimate e; run;";
    var out: std.ArrayList(u8) = .empty;
    try logistic.run(cx, &out, try @import("../lexer.zig").tokenize(a, source, &d));
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Specified 1 4.5000") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Row1 0.7500") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "Analysis of Maximum Likelihood Estimates") == null);
    // The full x model is completely separated; NOFIT must not try to fit it.
    const spec = try logistic.parse(cx, try @import("../lexer.zig").tokenize(a, source, &d));
    const base = try logistic.analyze(cx, spec);
    try std.testing.expectEqual(@as(usize, 0), base.fit.coefficients.len);
    try std.testing.expectApproxEqAbs(@as(f64, 4), base.fit.score_test, 1e-12);
    diag.resetGap();
    defer diag.resetGap();
    for ([_][]const u8{
        "proc logistic; model y=x / nofit; roc 'First' pred=score1; roc 'Second' pred=score2; roccontrast 1 -1 0; run;",
        "proc logistic; model y=x / nofit; roc 'First' pred=score1; roc 'Second' pred=score2; roccontrast reference('absent'); run;",
        "proc logistic rocoptions(weighted); model y=x / nofit; roc pred=score1; run;",
    }, [_]u8{ 1, 1, 2 }) |program, rc| {
        var errors = diag.Diagnostics.init(a);
        const context: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &errors };
        var actual: std.ArrayList(u8) = .empty;
        diag.resetGap();
        try std.testing.expectError(error.ParseError, logistic.run(context, &actual, try @import("../lexer.zig").tokenize(a, program, &errors)));
        try std.testing.expectEqual(rc, diag.exitCode(diag.gapHit(), errors.hasErrors()));
        try std.testing.expectEqual(@as(usize, 0), actual.items.len);
    }
}
