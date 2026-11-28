//! LOGISTIC CODE adapter, S154 physical pp.5855,5925. Coefficients are fitted,
//! not serialized predictions; the shared DATA-step engine executes every row.
const std = @import("std");
const code = @import("code.zig");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const Value = @import("../value.zig").Value;
const logistic = @import("logistic.zig");

pub fn names(a: std.mem.Allocator, s: logistic.Spec, r: logistic.Analysis) ![2][]const u8 {
    if (s.trials != null) return .{ "P_EVENT", "P_NONEVENT" };
    var result: [2][]const u8 = undefined;
    for ([_]usize{ r.design.event_index, 1 - r.design.event_index }, 0..) |index, j| {
        const label = r.design.response.levels[index].label;
        if (label.len == 0 or label.len > 30) return error.UnsupportedResponseName;
        for (label) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return error.UnsupportedResponseName;
        result[j] = try std.fmt.allocPrint(a, "P_{s}", .{label});
    }
    if (std.ascii.eqlIgnoreCase(result[0], result[1])) return error.UnsupportedResponseName;
    return result;
}
pub fn generate(a: std.mem.Allocator, s: logistic.Spec, r: logistic.Analysis, options: code.Options) ![]const u8 {
    if (r.ordinal_fit != null or r.design.response.levels.len != 2 or !r.fit.converged) return error.UnsupportedModel;
    // Imputation and residuals need response-specific semantics, not linear-model defaults.
    if (options.impute or options.residual) return error.UnsupportedOptions;
    const outputs = try names(a, s, r);
    for (s.input.ds.columns.items) |column| if (std.ascii.eqlIgnoreCase(column.name, "P__LOGISTIC_LP") or std.ascii.eqlIgnoreCase(column.name, "_LOGISTIC_LP") or std.ascii.eqlIgnoreCase(column.name, outputs[0]) or std.ascii.eqlIgnoreCase(column.name, outputs[1])) return error.ReservedVariableCollision;
    const classes = try a.alloc(code.Class, r.design.classes.len);
    for (r.design.classes, classes) |c, *dest| {
        if (s.input.ds.columns.items[c.column].format != null) return error.UnsupportedClassFormat;
        const values = try a.alloc(Value, c.map.levels.len);
        for (c.map.levels, values) |level, *value| value.* = level.value;
        dest.* = .{ .name = s.input.ds.columns.items[c.column].name, .values = values };
    }
    var terms: std.ArrayList(code.Term) = .empty;
    for (r.design.effects) |effect| {
        if (effect.class_index) |ci| {
            const c = r.design.classes[ci];
            var parameter = effect.start;
            for (c.map.levels, 0..) |_, level| if (level != c.reference) {
                const coefficient = r.fit.coefficients[parameter];
                try terms.append(a, .{ .coefficient = coefficient, .factors = try a.dupe(code.Factor, &.{.{ .class = .{ .index = ci, .level = level } }}), .label = effect.name });
                if (c.coding == .effect) try terms.append(a, .{ .coefficient = -coefficient, .factors = try a.dupe(code.Factor, &.{.{ .class = .{ .index = ci, .level = c.reference } }}), .label = effect.name });
                parameter += 1;
            };
        } else {
            const factors = try a.alloc(code.Factor, effect.variables.len);
            for (effect.variables, factors) |column, *factor| factor.* = .{ .numeric = s.input.ds.columns.items[column].name };
            try terms.append(a, .{ .coefficient = r.fit.coefficients[effect.start], .factors = factors, .label = effect.name });
        }
    }
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(a, try code.generate(a, .{ .procedure = "LOGISTIC", .response = "_LOGISTIC_LP", .intercept = r.fit.coefficients[0], .terms = terms.items, .classes = classes, .mean = 0 }, options));
    // Stable inverse logit prevents exp overflow, and explicitly propagates missing.
    try text.print(a, "drop P__LOGISTIC_LP;\nif missing(P__LOGISTIC_LP) then {s}=.;\nelse if P__LOGISTIC_LP>=0 then\n {s}=1/(1+exp(-P__LOGISTIC_LP));\nelse {s}=\n exp(P__LOGISTIC_LP)/(1+exp(P__LOGISTIC_LP));\n{s}=1-{s};\n", .{ outputs[0], outputs[0], outputs[0], outputs[1], outputs[0] });
    return text.items;
}
pub fn publish(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: logistic.Spec, r: logistic.Analysis) diag.Error!void {
    const options = s.code orelse return;
    const bytes = generate(cx.arena, s, r, options) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, options.line, "PROC LOGISTIC CODE: scoring representation is not implemented ({t})", .{err});
    try code.publishBytes(cx, out, bytes, options);
}

const Testing = struct {
    fn score(a: std.mem.Allocator, source: *@import("../dataset.zig").Dataset, text: []const u8) !*@import("../dataset.zig").Dataset {
        var d = diag.Diagnostics.init(a);
        var lib = @import("../exec.zig").Library.init(a);
        try lib.put("incoming", source);
        const program = try @import("../parser.zig").parse(a, try std.mem.concat(a, u8, &.{ "set incoming;\n", text }), &d);
        var pdv = @import("../pdv.zig").Pdv.init(a);
        var evaluator = @import("../eval.zig").Evaluator{ .arena = a, .pdv = &pdv, .diags = &d, .call_fn = &@import("../functions.zig").dispatch };
        var executor = @import("../exec.zig").Executor.init(a, &pdv, &d, &evaluator, &lib);
        const result = try a.create(@import("../dataset.zig").Dataset);
        result.* = @import("../dataset.zig").Dataset.init(a, "scored");
        try executor.run(program, result);
        try std.testing.expect(!d.hasErrors());
        return result;
    }
};

test "LOGISTIC018 CODE real grouped interaction fit executes every row and preserves missing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/persist_logistic_logistic001_documented_feature.sas", "ingots", &.{ "Heat", "Soak", "r", "n" }, &.{}, 0);
    const independent = try @import("logistic_persistence_tests.zig").reference(ds);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ingots", &ds);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const s = try logistic.parse(cx, try @import("../lexer.zig").tokenize(a, "proc logistic data=ingots; model r/n=Heat|Soak; run;", &d));
    const fit = try logistic.analyze(cx, s);
    var incoming = @import("../dataset.zig").Dataset.init(a, "incoming");
    _ = try incoming.addColumn("Heat", .num);
    _ = try incoming.addColumn("Soak", .num);
    _ = try incoming.addColumn("id", .num);
    for (ds.rows.items, 0..) |row, i| try incoming.appendRow(&.{ row[0], row[1], .{ .num = @floatFromInt(i) } });
    const original_scoring = try @import("glm_persistence_tests.zig").data(a, "tests/corpus/persist_logistic_logistic001_documented_feature.sas", "original_scoring", &.{ "Heat", "Soak", "NotReady", "Freq" }, &.{}, 1);
    try std.testing.expectEqual(@as(usize, 25), original_scoring.rows.items.len);
    for (original_scoring.rows.items, 0..) |row, i| try incoming.appendRow(&.{ row[0], row[1], .{ .num = @floatFromInt(1000 + i) } });
    // New covariates, then ordinary and special missing, then a valid row again.
    for ([_][2]f64{ .{ 9, 1.5 }, .{ 30, 3 }, .{ 10000, 1 }, .{ -10000, 1 } }) |row| try incoming.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = 99 } });
    try incoming.appendRow(&.{ Value.missing, .{ .num = 1 }, .{ .num = 100 } });
    try incoming.appendRow(&.{ .{ .num = 7 }, Value.specialMissing('A'), .{ .num = 101 } });
    try incoming.appendRow(&.{ .{ .num = 14 }, .{ .num = 1 }, .{ .num = 102 } });
    try lib.put("incoming", &incoming);
    const score = try @import("logistic_score.zig").build(cx, s, fit, .{ .input = "incoming", .output = "score", .clm = true });
    try std.testing.expectEqual(incoming.rows.items.len, score.rows.items.len);
    for (incoming.rows.items, score.rows.items) |row, got| {
        if (row[0].isMissing() or row[1].isMissing()) {
            for ([_][]const u8{ "P_EVENT", "P_NONEVENT", "LCL_EVENT", "UCL_EVENT", "LCL_NONEVENT", "UCL_NONEVENT" }) |name| try std.testing.expect(got[score.indexOf(name).?].isMissing());
            continue;
        }
        const x = [4]f64{ 1, row[0].num, row[1].num, row[0].num * row[1].num };
        var eta: f64 = 0;
        var variance: f64 = 0;
        for (x, 0..) |v, j| {
            eta += v * independent.beta[j];
            for (x, 0..) |w, k| variance += v * independent.covariance[j][k] * w;
        }
        const p = if (eta >= 0) 1 / (1 + @exp(-eta)) else @exp(eta) / (1 + @exp(eta));
        const margin = 1.959963984540054 * p * (1 - p) * @sqrt(variance);
        const prediction = try @import("logistic_score.zig").prediction(&x, fit.fit.coefficients, fit.fit.covariance, 0.05);
        try std.testing.expectApproxEqRel(eta, prediction.eta, 1e-9);
        try std.testing.expectApproxEqRel(@sqrt(variance), prediction.se_eta, 1e-9);
        try std.testing.expectApproxEqAbs(p, got[score.indexOf("P_EVENT").?].num, 1e-9);
        try std.testing.expectApproxEqAbs(p - margin, got[score.indexOf("LCL_EVENT").?].num, 1e-9);
        try std.testing.expectApproxEqAbs(p + margin, got[score.indexOf("UCL_EVENT").?].num, 1e-9);
        try std.testing.expectApproxEqAbs(1 - p - margin, got[score.indexOf("LCL_NONEVENT").?].num, 1e-9);
        try std.testing.expectApproxEqAbs(1 - p + margin, got[score.indexOf("UCL_NONEVENT").?].num, 1e-9);
    }
    const text = try generate(a, s, fit, .{});
    for (0..2) |_| {
        const actual = try Testing.score(a, &incoming, text);
        try std.testing.expectEqual(incoming.rows.items.len, actual.rows.items.len);
        try std.testing.expectEqual(@as(usize, 5), actual.columns.items.len);
        const pi = actual.indexOf("P_EVENT").?;
        const qi = actual.indexOf("P_NONEVENT").?;
        for (incoming.rows.items, actual.rows.items) |row, got| {
            try std.testing.expectEqual(row[2].num, got[actual.indexOf("id").?].num);
            if (row[0].isMissing() or row[1].isMissing()) {
                try std.testing.expect(got[pi].isMissing() and got[qi].isMissing());
                continue;
            }
            const b = independent.beta;
            const eta = b[0] + row[0].num * b[1] + row[1].num * b[2] + row[0].num * row[1].num * b[3];
            const expected = if (eta >= 0) 1 / (1 + @exp(-eta)) else @exp(eta) / (1 + @exp(eta));
            // Independent grouped Newton vs QR follows the existing 1e-9
            // probability/odds endpoint precision contract.
            try std.testing.expectApproxEqAbs(expected, got[pi].num, 1e-9);
            try std.testing.expectApproxEqAbs(1 - expected, got[qi].num, 1e-9);
        }
    }
}

test "LOGISTIC018 CODE REF EFFECT actual fits new CLASS levels and all lookup algorithms" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var training = @import("../dataset.zig").Dataset.init(a, "training");
    _ = try training.addColumn("g", .char);
    _ = try training.addColumn("y", .num);
    _ = try training.addColumn("f", .num);
    for ([_][]const u8{ "A", "B", "C" }, [_]f64{ 2, 5, 8 }) |g, successes| {
        try training.appendRow(&.{ .{ .str = g }, .{ .num = 1 }, .{ .num = successes } });
        try training.appendRow(&.{ .{ .str = g }, .{ .num = 0 }, .{ .num = 10 - successes } });
    }
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("training", &training);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    var incoming = @import("../dataset.zig").Dataset.init(a, "incoming");
    _ = try incoming.addColumn("g", .char);
    for ([_][]const u8{ "C", "A", "B", "new", "", "A" }) |g| try incoming.appendRow(&.{.{ .str = g }});
    for ([_][]const u8{ "ref", "effect" }) |coding| {
        const s = try logistic.parse(cx, try @import("../lexer.zig").tokenize(a, try std.fmt.allocPrint(a, "proc logistic data=training; class g(ref='B') / param={s}; model y(event='1')=g / gconv=1e-14; freq f; run;", .{coding}), &d));
        const fit = try logistic.analyze(cx, s);
        for (std.enums.values(code.Lookup)) |lookup| {
            const text = try generate(a, s, fit, .{ .lookup = lookup });
            const actual = try Testing.score(a, &incoming, text);
            try std.testing.expectEqual(@as(usize, 6), actual.rows.items.len);
            try std.testing.expectEqual(@as(usize, 3), actual.columns.items.len);
            for (actual.rows.items, [_]f64{ 0.8, 0.2, 0.5, std.math.nan(f64), std.math.nan(f64), 0.2 }) |row, expected| {
                const p = row[actual.indexOf("P_1").?];
                const q = row[actual.indexOf("P_0").?];
                if (std.math.isNan(expected)) try std.testing.expect(p.isMissing() and q.isMissing()) else {
                    // Saturated binomial MLE is exactly successes/10.
                    try std.testing.expectApproxEqAbs(expected, p.num, 2e-7);
                    try std.testing.expectApproxEqAbs(1 - expected, q.num, 2e-7);
                }
            }
        }
    }
}

test "LOGISTIC018 producer routes CODE and repeated SCORE and guards alternate execution before output" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try @import("logistic_design.zig").originalFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("binary", &ds);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try logistic.run(cx, &out, try @import("../lexer.zig").tokenize(a, "proc logistic data=binary noprint; model event(event='1')=x; code file=print; score out=score1 clm; score out=score2; run;", &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "SAS Scoring Code for PROC LOGISTIC") != null);
    const one = lib.find("score1").?;
    const two = lib.find("score2").?;
    try std.testing.expectEqual(ds.rows.items.len, one.rows.items.len);
    try std.testing.expect(one.indexOf("LCL_1") != null and two.indexOf("LCL_1") == null);
    for (one.rows.items, two.rows.items) |left, right| try std.testing.expectEqual(left[one.indexOf("P_1").?].num, right[two.indexOf("P_1").?].num);
    for ([_][]const u8{
        "proc logistic data=binary exactonly; model event=x; exact x; code file=print; run;",
        "proc logistic data=binary; model event=x; strata group; score out=blocked; run;",
        "proc logistic data=binary; model event=x / nofit; code file=print; run;",
        "proc logistic data=binary; model event=x; roc 'x' x; score out=blocked; run;",
        "proc logistic data=binary; model event=x; by group; code file=print; run;",
        "proc logistic data=binary; model event=x / link=probit; score out=blocked; run;",
        "proc logistic data=binary; model event=x; code file=print residual; run;",
        "proc logistic data=binary; model event=x; score out=blocked prior=anything; run;",
        "proc logistic data=binary; model event=x; score out=blocked; format x 8.2; run;",
    }) |source| {
        var errors = diag.Diagnostics.init(a);
        var captured: std.ArrayList(u8) = .empty;
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, logistic.run(.{ .arena = a, .lib = &lib, .diags = &errors }, &captured, try @import("../lexer.zig").tokenize(a, source, &errors)));
        try std.testing.expect(diag.gapHit());
        try std.testing.expectEqual(@as(usize, 0), captured.items.len);
        try std.testing.expect(lib.find("blocked") == null);
        try std.testing.expect(std.mem.indexOf(u8, try errors.render(), "CODE") != null or std.mem.indexOf(u8, try errors.render(), "SCORE") != null);
    }
}
