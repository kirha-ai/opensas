//! Binary SCORE data sets and delta-method Wald limits (S154 physical
//! pp.5898–5900,5943–5944,5956). OUTPUT link-scale limits are distinct.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const logistic = @import("logistic.zig");
const code = @import("logistic_code.zig");
const design = @import("logistic_design.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Request = struct { input: ?[]const u8 = null, output: []const u8, alpha: ?f64 = null, clm: bool = false, line: usize = 0 };
fn invalid(cx: proc.ProcCtx, line: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC LOGISTIC SCORE: invalid option syntax", .{});
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Request {
    var r = Request{ .output = "", .line = if (t.len > 0) t[0].line else 0 };
    var i: usize = 0;
    while (i < t.len) {
        const option = t[i];
        i += 1;
        if (eq(option.text, "clm")) {
            r.clm = true;
            continue;
        }
        if (!eq(option.text, "data") and !eq(option.text, "out") and !eq(option.text, "alpha")) return proc.failGap(cx.diags, option.line, "PROC LOGISTIC SCORE: {s} is not implemented", .{option.text});
        if (i + 1 >= t.len or t[i].tag != .eq) return invalid(cx, option.line);
        i += 1;
        if (eq(option.text, "alpha")) {
            if (r.alpha != null or t[i].tag != .number) return invalid(cx, option.line);
            r.alpha = std.fmt.parseFloat(f64, t[i].text) catch return invalid(cx, option.line);
            if (!(r.alpha.? > 0 and r.alpha.? < 1)) return invalid(cx, option.line);
            i += 1;
            continue;
        }
        if (t[i].tag != .name) return invalid(cx, option.line);
        var name = t[i].text;
        i += 1;
        if (i < t.len and t[i].tag == .dot) {
            if (i + 1 >= t.len or t[i + 1].tag != .name) return invalid(cx, option.line);
            name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i + 1].text });
            i += 2;
        }
        if (i < t.len and t[i].tag == .lparen) return proc.failGap(cx.diags, option.line, "PROC LOGISTIC SCORE: data set options are not implemented", .{});
        if (eq(option.text, "data")) {
            if (r.input != null) return invalid(cx, option.line);
            r.input = name;
        } else {
            if (r.output.len != 0) return invalid(cx, option.line);
            r.output = name;
        }
    }
    if (r.output.len == 0) return proc.failGap(cx.diags, r.line, "PROC LOGISTIC SCORE: automatic DATAn names are not implemented; specify OUT=", .{});
    return r;
}
pub const Prediction = struct { eta: f64, se_eta: f64, probability: f64, lower: f64, upper: f64 };
pub fn prediction(x: []const f64, beta: []const f64, covariance: []const f64, alpha: f64) !Prediction {
    if (x.len != beta.len or covariance.len != x.len * x.len or !(alpha > 0 and alpha < 1)) return error.InvalidInput;
    var eta: f64 = 0;
    var variance: f64 = 0;
    for (x, 0..) |v, j| {
        eta += v * beta[j];
        for (x, 0..) |w, k| variance += v * covariance[j * x.len + k] * w;
    }
    if (!std.math.isFinite(eta) or !std.math.isFinite(variance) or variance < 0) return error.InvalidInput;
    const p = @import("logistic_fit.zig").probability(eta);
    const z = @import("../functions.zig").distQuantile(.normal, 1 - alpha / 2, &.{}).?;
    const se = @sqrt(variance);
    const width = z * p * (1 - p) * se;
    return .{ .eta = eta, .se_eta = se, .probability = p, .lower = p - width, .upper = p + width };
}
pub fn build(cx: proc.ProcCtx, s: logistic.Spec, r: logistic.Analysis, request: Request) diag.Error!*Dataset {
    if (r.design.response.levels.len != 2 or r.ordinal_fit != null or !r.fit.converged) return proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: only converged binary logit fits are implemented", .{});
    const incoming = if (request.input) |name| cx.lib.find(name) orelse return cx.diags.fail(error.ExecError, request.line, "Data set {s} not found.", .{name}) else s.input.ds;
    for (r.design.response.levels) |level| if (level.label.len > 16) return proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: response normalization beyond sixteen characters is not implemented", .{});
    const outputs = code.names(cx.arena, s, r) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: normalized response names are not implemented for these levels", .{});
    const out = try cx.arena.create(Dataset);
    out.* = Dataset.init(cx.arena, request.output);
    for (incoming.columns.items) |column| _ = try out.addColumnLike(column.name, column);
    var mapping = try cx.arena.alloc(?usize, s.input.ds.columns.items.len);
    @memset(mapping, null);
    for (r.design.effects) |effect| for (effect.variables) |ci| {
        const original = s.input.ds.columns.items[ci];
        const target = incoming.indexOf(original.name) orelse return cx.diags.fail(error.ParseError, request.line, "PROC LOGISTIC SCORE: variable {s} not found", .{original.name});
        if (incoming.columns.items[target].type != original.type) return cx.diags.fail(error.ParseError, request.line, "PROC LOGISTIC SCORE: variable {s} has a different type", .{original.name});
        mapping[ci] = target;
    };
    for (r.design.classes) |c| if (s.input.ds.columns.items[c.column].format != null) return proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: formatted CLASS scoring is not implemented", .{});
    const response_name = s.input.ds.columns.items[s.model.response].name;
    const response_column = if (s.trials == null) incoming.indexOf(response_name) else null;
    const from_name = try std.fmt.allocPrint(cx.arena, "F_{s}", .{response_name});
    const into_name = if (s.trials != null) "_INTO_" else try std.fmt.allocPrint(cx.arena, "I_{s}", .{response_name});
    if (response_name.len > 30) return proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: long response names are not implemented", .{});
    var appended: std.ArrayList([]const u8) = .empty;
    if (response_column != null) try appended.append(cx.arena, from_name);
    try appended.append(cx.arena, into_name);
    try appended.appendSlice(cx.arena, &outputs);
    if (request.clm) for (outputs) |name| {
        try appended.append(cx.arena, try std.fmt.allocPrint(cx.arena, "LCL_{s}", .{name[2..]}));
        try appended.append(cx.arena, try std.fmt.allocPrint(cx.arena, "UCL_{s}", .{name[2..]}));
    };
    for (appended.items, 0..) |name, k| {
        if (name.len > 32 or out.indexOf(name) != null) return proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: output name collision or excessive length", .{});
        _ = try out.addColumn(name, if (k < @as(usize, if (response_column != null) 2 else 1)) .char else .num);
    }
    const x = try cx.arena.alloc(f64, r.design.p);
    const cells = try cx.arena.alloc(Value, out.columns.items.len);
    for (incoming.rows.items) |row| {
        @memcpy(cells[0..row.len], row);
        for (out.columns.items[row.len..], cells[row.len..]) |column, *cell| cell.* = if (column.type == .char) .{ .str = "" } else Value.missing;
        const offset = row.len;
        if (response_column) |ci| {
            if (!row[ci].isMissing()) cells[offset] = .{ .str = std.mem.trim(u8, try @import("../format.zig").apply(cx.arena, row[ci], s.input.ds.columns.items[s.model.response].format orelse if (row[ci] == .num) "best16." else "$16."), " ") };
        }
        const into = offset + @as(usize, if (response_column != null) 1 else 0);
        const probability_start = into + 1;
        @memset(x, 0);
        x[0] = 1;
        var valid = true;
        for (r.design.effects) |effect| {
            if (effect.class_index) |ci| {
                const c = r.design.classes[ci];
                const value = row[mapping[c.column].?];
                var level: ?usize = null;
                if (!value.isMissing()) for (c.map.levels, 0..) |candidate, k| {
                    if (proc.cmpValue(value, candidate.value) == .eq) {
                        level = k;
                        break;
                    }
                };
                if (level == null) {
                    valid = false;
                    continue;
                }
                var j = effect.start;
                for (c.map.levels, 0..) |_, k| if (k != c.reference) {
                    x[j] = design.code(level.?, c.reference, k, c.coding);
                    j += 1;
                };
            } else {
                var product: f64 = 1;
                for (effect.variables) |ci| product *= row[mapping[ci].?].num;
                if (!std.math.isFinite(product)) valid = false;
                x[effect.start] = product;
            }
        }
        if (valid) {
            const p = prediction(x, r.fit.coefficients, r.fit.covariance, request.alpha orelse s.alpha) catch return proc.failGap(cx.diags, request.line, "PROC LOGISTIC SCORE: nonfinite prediction or covariance", .{});
            const chosen: usize = if (p.probability > 0.5) r.design.event_index else if (p.probability < 0.5) 1 - r.design.event_index else 0;
            cells[into] = .{ .str = if (s.trials != null) (if (chosen == r.design.event_index) "EVENT" else "NONEVENT") else r.design.response.levels[chosen].label };
            cells[probability_start] = .{ .num = p.probability };
            cells[probability_start + 1] = .{ .num = 1 - p.probability };
            if (request.clm) {
                cells[probability_start + 2] = .{ .num = p.lower };
                cells[probability_start + 3] = .{ .num = p.upper };
                cells[probability_start + 4] = .{ .num = 1 - p.upper };
                cells[probability_start + 5] = .{ .num = 1 - p.lower };
            }
        }
        try out.appendRow(cells);
    }
    return out;
}
pub fn publish(cx: proc.ProcCtx, s: logistic.Spec, r: logistic.Analysis) diag.Error!void {
    for (s.scores) |request| try cx.lib.put(request.output, try build(cx, s, r, request));
}

test "LOGISTIC018 SCORE typed new rows class coding repeated output and independent delta CLM" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var training = Dataset.init(a, "train");
    _ = try training.addColumn("group", .char);
    _ = try training.addColumn("y", .num);
    _ = try training.addColumn("f", .num);
    for ([_][]const u8{ "A", "B", "C" }, [_]f64{ 20, 50, 80 }) |g, successes| {
        try training.appendRow(&.{ .{ .str = g }, .{ .num = 1 }, .{ .num = successes } });
        try training.appendRow(&.{ .{ .str = g }, .{ .num = 0 }, .{ .num = 100 - successes } });
    }
    var incoming = Dataset.init(a, "incoming");
    _ = try incoming.addColumn("id", .num);
    _ = try incoming.addColumn("GROUP", .char);
    for ([_][]const u8{ "C", "A", "B", "unknown", "", "A" }, 0..) |g, i| try incoming.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .str = g } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("train", &training);
    try lib.put("incoming", &incoming);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "ref", "effect" }) |coding| {
        const s = try logistic.parse(cx, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc logistic data=train; class group(ref='B') / param={s}; model y(event='1')=group / gconv=1e-14; freq f; run;", .{coding}), &d));
        const fit = try logistic.analyze(cx, s);
        for ([_]f64{ 0.05, 0.1 }) |alpha| {
            const tokens = try lex.tokenize(a, try std.fmt.allocPrint(a, "data=incoming out=scored clm alpha={d}", .{alpha}), &d);
            const request = try parse(cx, tokens[0 .. tokens.len - 1]);
            for (0..2) |_| {
                const result = try build(cx, s, fit, request);
                try std.testing.expectEqual(@as(usize, 6), result.rows.items.len);
                try std.testing.expectEqual(@as(usize, 9), result.columns.items.len);
                try std.testing.expect(result.indexOf("F_y") == null);
                const z = if (alpha == 0.05) @as(f64, 1.959963984540054) else @as(f64, 1.6448536269514722);
                for (result.rows.items, [_]f64{ 0.8, 0.2, 0.5, std.math.nan(f64), std.math.nan(f64), 0.2 }, 0..) |row, p, i| {
                    try std.testing.expectEqual(@as(f64, @floatFromInt(i + 1)), row[0].num);
                    try std.testing.expectEqualStrings(incoming.rows.items[i][1].str, row[1].str);
                    if (std.math.isNan(p)) {
                        try std.testing.expectEqualStrings("", row[result.indexOf("I_y").?].str);
                        for (row[3..]) |v| try std.testing.expect(v.isMissing());
                        continue;
                    }
                    const margin = z * @sqrt(p * (1 - p) / 100);
                    // Saturated binomial independent Fisher information gives
                    // Var(p)=p(1-p)/100. Tight GCONV provides <1e-7 probability error.
                    try std.testing.expectApproxEqAbs(p, row[result.indexOf("P_1").?].num, 1e-7);
                    try std.testing.expectApproxEqAbs(1 - p, row[result.indexOf("P_0").?].num, 1e-7);
                    try std.testing.expectApproxEqAbs(p - margin, row[result.indexOf("LCL_1").?].num, 1e-7);
                    try std.testing.expectApproxEqAbs(p + margin, row[result.indexOf("UCL_1").?].num, 1e-7);
                    try std.testing.expectApproxEqAbs(1 - p - margin, row[result.indexOf("LCL_0").?].num, 1e-7);
                    try std.testing.expectApproxEqAbs(1 - p + margin, row[result.indexOf("UCL_0").?].num, 1e-7);
                    if (p != 0.5) try std.testing.expectEqualStrings(if (p > 0.5) "1" else "0", row[result.indexOf("I_y").?].str);
                }
            }
        }
        const existing = try build(cx, s, fit, .{ .output = "existing" });
        try std.testing.expectEqual(@as(usize, 6), existing.rows.items.len);
        try std.testing.expectEqualStrings("1", existing.rows.items[0][existing.indexOf("F_y").?].str);
        try std.testing.expectEqualStrings("0", existing.rows.items[1][existing.indexOf("F_y").?].str);
    }
    try std.testing.expect(!d.hasErrors());
}

test "LOGISTIC018 SCORE linear predictor covariance identity and finite boundaries" {
    const got = try prediction(&.{ 1, 2 }, &.{ -1, 0.5 }, &.{ 0.25, 0.05, 0.05, 0.09 }, 0.05);
    try std.testing.expectEqual(@as(f64, 0), got.eta);
    try std.testing.expectApproxEqAbs(@sqrt(@as(f64, 0.81)), got.se_eta, 1e-15);
    try std.testing.expectEqual(@as(f64, 0.5), got.probability);
    try std.testing.expectApproxEqAbs(0.5 - 1.959963984540054 * 0.25 * 0.9, got.lower, 1e-10);
    try std.testing.expectError(error.InvalidInput, prediction(&.{1}, &.{0}, &.{-1}, 0.05));
    try std.testing.expectError(error.InvalidInput, prediction(&.{std.math.inf(f64)}, &.{1}, &.{1}, 0.05));
}
