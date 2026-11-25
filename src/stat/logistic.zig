//! Bounded binary-logit main-effects execution for COMMON-008.
//! REF/EFFECT use shared CLASS levels. Other methods remain explicit gaps;
//! no GLM inference code or output expected values are reused as results.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const levels = @import("class_levels.zig");
const lists = @import("variable_lists.zig");
const by = @import("by_groups.zig");
const design = @import("logistic_design.zig");
const kernel = @import("logistic_fit.zig");
const format = @import("../format.zig");
const fns = @import("../functions.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const Spec = struct { input: proc.ProcInput, model: design.Spec, noprint: bool = false };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, name);
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC LOGISTIC: invalid syntax near {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn unsupported(cx: proc.ProcCtx, t: lex.Token) diag.Error {
    return proc.failGap(cx.diags, t.line, "PROC LOGISTIC: {s} is not implemented by the binary main-effects path", .{t.text});
}
fn variable(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!usize {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    const ci = ds.indexOf(t[i.*].text) orelse return cx.diags.fail(error.ParseError, t[i.*].line, "Variable {s} not found.", .{t[i.*].text});
    i.* += 1;
    return ci;
}
fn reference(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!levels.Reference {
    if (at(t, i.*, .string)) {
        const r: levels.Reference = .{ .label = t[i.*].text };
        i.* += 1;
        return r;
    }
    if (kw(t, i.*, "first")) {
        i.* += 1;
        return .first;
    }
    if (kw(t, i.*, "last")) {
        i.* += 1;
        return .last;
    }
    return invalid(cx, t, i.*);
}
fn coding(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!design.Coding {
    if (kw(t, i.*, "ref") or kw(t, i.*, "reference")) {
        i.* += 1;
        return .reference;
    }
    if (kw(t, i.*, "effect")) {
        i.* += 1;
        return .effect;
    }
    inline for (.{ "glm", "ordinal", "thermometer", "polynomial", "poly", "ortheffect", "orthordinal", "orththerm", "orthpoly", "orthref" }) |name| {
        if (kw(t, i.*, name)) return unsupported(cx, t[i.*]);
    }
    return invalid(cx, t, i.*);
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .model = .{ .response = 0, .effects = &.{} } };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (kw(t, i, "noprint")) {
            s.noprint = true;
            i += 1;
            continue;
        }
        if (!kw(t, i, "data")) return unsupported(cx, t[i]);
        if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return invalid(cx, t, i);
        i += 2;
        name = t[i].text;
        i += 1;
        if (at(t, i, .dot)) {
            if (!at(t, i + 1, .name)) return invalid(cx, t, i);
            qualified = i - 1;
            name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
            i += 2;
        }
        if (at(t, i, .lparen)) i = proc.skipParen(t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |start| {
        try folded.appendSlice(cx.arena, t[0..start]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[start].line });
        try folded.appendSlice(cx.arena, t[start + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    var classes: std.ArrayList(design.ClassSpec) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var model_seen = false;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "class")) {
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "CLASS must precede MODEL", .{});
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) {
                var c: design.ClassSpec = .{ .column = try variable(cx, s.input.ds, t[0..end], &j) };
                for (classes.items) |old| if (old.column == c.column) return invalid(cx, t, j - 1);
                if (at(t, j, .lparen)) {
                    j += 1;
                    while (j < end and !at(t, j, .rparen)) {
                        const option = t[j];
                        if (eq(option.text, "missing") or eq(option.text, "descending") or eq(option.text, "desc")) return unsupported(cx, option);
                        if (!at(t, j + 1, .eq)) return invalid(cx, t, j);
                        j += 2;
                        if (eq(option.text, "ref") or eq(option.text, "reference")) c.reference = try reference(cx, t[0..end], &j) else if (eq(option.text, "param")) c.coding = try coding(cx, t[0..end], &j) else return unsupported(cx, option);
                    }
                    if (!at(t, j, .rparen)) return invalid(cx, t, j);
                    j += 1;
                }
                try classes.append(cx.arena, c);
            }
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (!kw(t, j, "param") or !at(t, j + 1, .eq)) return unsupported(cx, t[j]);
                    j += 2;
                    s.model.coding = try coding(cx, t[0..end], &j);
                }
            }
        } else if (kw(t, i, "model")) {
            if (model_seen) return unsupported(cx, t[i]);
            model_seen = true;
            var j = i + 1;
            s.model.response = try variable(cx, s.input.ds, t[0..end], &j);
            if (at(t, j, .lparen)) {
                j += 1;
                if (!kw(t, j, "event") or !at(t, j + 1, .eq)) return unsupported(cx, t[j]);
                j += 2;
                s.model.event = try reference(cx, t[0..end], &j);
                if (!at(t, j, .rparen)) return invalid(cx, t, j);
                j += 1;
            }
            if (at(t, j, .slash)) return unsupported(cx, t[j]); // events/trials
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            while (j < end and !at(t, j, .slash)) {
                if (!at(t, j, .name)) return unsupported(cx, t[j]);
                const ci = try variable(cx, s.input.ds, t[0..end], &j);
                if (std.mem.indexOfScalar(usize, effects.items, ci) == null) try effects.append(cx.arena, ci);
            }
            if (j < end) {
                j += 1;
                if (!kw(t, j, "link") or !at(t, j + 1, .eq) or !kw(t, j + 2, "logit") or j + 3 != end) return unsupported(cx, t[j]);
            }
        } else if (kw(t, i, "format")) {
            var j = i;
            try proc.parseProcFormat(cx.arena, t, &j, &formats);
        } else if (!kw(t, i, "run") and !kw(t, i, "quit") and !kw(t, i, "where")) return unsupported(cx, t[i]);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: MODEL statement required", .{});
    s.input.ds = try by.withFormats(cx.arena, s.input.ds, formats.items);
    s.model.classes = classes.items;
    s.model.effects = effects.items;
    return s;
}
fn number(a: A, value: f64, spec: []const u8) diag.Error![]const u8 {
    return std.mem.trim(u8, try format.apply(a, .{ .num = value }, spec), " ");
}
fn odds(a: A, value: f64) diag.Error![]const u8 {
    if (value < 0.001) return "<0.001";
    if (value > 999.999) return ">999.999";
    return number(a, value, "10.3");
}
fn testRow(a: A, out: *std.ArrayList(u8), name: []const u8, q: f64, df: usize) diag.Error!void {
    try out.print(a, "{s} {s} {d} {s}\n", .{ name, try number(a, q, "10.4"), df, try number(a, kernel.chiTail(q, df), "pvalue6.4") });
}

pub fn render(a: A, out: *std.ArrayList(u8), s: Spec, d: design.Design, r: kernel.Fit) diag.Error!void {
    const ds = s.input.ds;
    const response_name = ds.columns.items[s.model.response].name;
    try out.print(a, "The LOGISTIC Procedure\n\nModel Information\n\nData Set {s}\nResponse Variable {s}\nNumber of Response Levels 2\nModel binary logit\nOptimization Technique Fisher's scoring\n\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n\nResponse Profile\n\nOrdered Total\nValue {s} Frequency\n\n", .{ try lists.datasetName(a, ds), response_name, ds.rows.items.len, d.n, response_name });
    for (d.response.levels, 0..) |level, i| try out.print(a, "{d} {s} {s}\n", .{ i + 1, level.label, try number(a, level.frequency, "best12.") });
    try out.print(a, "\nProbability modeled is {s}={s}.\n\n", .{ response_name, d.response.levels[d.event_index].label });
    if (d.classes.len > 0) {
        try out.appendSlice(a, "Class Level Information\n\nDesign\nClass Value Variables\n\n");
        for (d.classes) |c| for (c.map.levels, 0..) |level, i| {
            if (i == 0) try out.print(a, "{s} ", .{ds.columns.items[c.column].name});
            try out.appendSlice(a, level.label);
            for (0..c.map.levels.len) |j| if (j != c.reference) try out.print(a, " {s}", .{try number(a, design.code(i, c.reference, j, c.coding), "best8.")});
            try out.appendSlice(a, "\n");
        };
    }
    try out.appendSlice(a, "\nModel Convergence Status\n\nConvergence criterion (GCONV=1E-8) satisfied.\n\nModel Fit Statistics\n\nIntercept\nIntercept and\nCriterion Only Covariates\n\n");
    const null_deviance = -2 * r.null_log_likelihood;
    const deviance = -2 * r.log_likelihood;
    const nf: f64 = @floatFromInt(d.n);
    const pf: f64 = @floatFromInt(d.p);
    for ([_][]const u8{ "AIC", "SC", "-2 Log L" }, [_]f64{ null_deviance + 2, null_deviance + @log(nf), null_deviance }, [_]f64{ deviance + 2 * pf, deviance + pf * @log(nf), deviance }) |name, null_value, full| try out.print(a, "{s} {s} {s}\n", .{ name, try number(a, null_value, "10.3"), try number(a, full, "10.3") });
    if (d.p > 1) {
        try out.appendSlice(a, "\nTesting Global Null Hypothesis: BETA=0\n\nTest Chi-Square DF Pr > ChiSq\n\n");
        try testRow(a, out, "Likelihood Ratio", @max(0, 2 * (r.log_likelihood - r.null_log_likelihood)), d.p - 1);
        try testRow(a, out, "Score", r.score_test, d.p - 1);
        try testRow(a, out, "Wald", try kernel.blockWald(a, r, 1, d.p - 1), d.p - 1);
    }
    if (d.classes.len > 0) {
        try out.appendSlice(a, "\nType 3 Analysis of Effects\n\nWald\nEffect DF Chi-Square Pr > ChiSq\n\n");
        for (d.effects) |e| {
            const q = try kernel.blockWald(a, r, e.start, e.len);
            try out.print(a, "{s} {d} {s} {s}\n", .{ ds.columns.items[e.column].name, e.len, try number(a, q, "10.4"), try number(a, kernel.chiTail(q, e.len), "pvalue6.4") });
        }
    }
    try out.appendSlice(a, "\nAnalysis of Maximum Likelihood Estimates\n\nStandard Wald\nParameter DF Estimate Error Chi-Square Pr > ChiSq\n\n");
    for (d.parameters, 0..) |parameter, j| {
        const se = @sqrt(r.covariance[j * d.p + j]);
        const q = r.coefficients[j] * r.coefficients[j] / r.covariance[j * d.p + j];
        try out.print(a, "{s} {s} 1 {s} {s} {s} {s}\n", .{ parameter.name, parameter.level orelse "", try number(a, r.coefficients[j], "10.4"), try number(a, se, "10.4"), try number(a, q, "10.4"), try number(a, kernel.chiTail(q, 1), "pvalue6.4") });
    }
    if (d.p > 1) {
        try out.appendSlice(a, "\nOdds Ratio Estimates\n\nPoint 95% Wald\nEffect Estimate Confidence Limits\n\n");
        const z = fns.distQuantile(.normal, 0.975, &.{}).?;
        const contrast = try a.alloc(f64, d.p);
        defer a.free(contrast);
        for (d.effects) |e| {
            const count = if (e.class_index) |k| d.classes[k].map.levels.len else 1;
            for (0..count) |level| {
                @memset(contrast, 0);
                var name = ds.columns.items[e.column].name;
                if (e.class_index) |k| {
                    const c = d.classes[k];
                    if (level == c.reference) continue;
                    var j = e.start;
                    for (0..c.map.levels.len) |lp| if (lp != c.reference) {
                        contrast[j] = design.code(level, c.reference, lp, c.coding) - design.code(c.reference, c.reference, lp, c.coding);
                        j += 1;
                    };
                    name = try std.fmt.allocPrint(a, "{s} {s} vs {s}", .{ name, c.map.levels[level].label, c.map.levels[c.reference].label });
                } else contrast[e.start] = 1;
                var estimate: f64 = 0;
                var variance: f64 = 0;
                for (0..d.p) |j| {
                    estimate += contrast[j] * r.coefficients[j];
                    for (0..d.p) |k| variance += contrast[j] * r.covariance[j * d.p + k] * contrast[k];
                }
                const margin = z * @sqrt(@max(0, variance));
                try out.print(a, "{s} {s} {s} {s}\n", .{ name, try odds(a, @exp(estimate)), try odds(a, @exp(estimate - margin)), try odds(a, @exp(estimate + margin)) });
            }
        }
    }
    const assoc = kernel.association(d.y, r.probabilities);
    const pairs: f64 = @floatFromInt(assoc.pairs);
    if (assoc.pairs > 0) {
        const nc: f64 = @floatFromInt(assoc.concordant);
        const nd: f64 = @floatFromInt(assoc.discordant);
        const nt: f64 = @floatFromInt(assoc.tied);
        const gamma = if (nc + nd > 0) (nc - nd) / (nc + nd) else std.math.nan(f64);
        try out.print(a, "\nAssociation of Predicted Probabilities and Observed Responses\n\nPercent Concordant {s} Somers' D {s}\nPercent Discordant {s} Gamma {s}\nPercent Tied {s} Tau-a {s}\nPairs {d} c {s}\n\n", .{
            try number(a, 100 * nc / pairs, "6.1"), try number(a, (nc - nd) / pairs, "6.3"),               try number(a, 100 * nd / pairs, "6.1"), try number(a, gamma, "6.3"),
            try number(a, 100 * nt / pairs, "6.1"), try number(a, 2 * (nc - nd) / (nf * (nf - 1)), "6.3"), assoc.pairs,                            try number(a, (nc + 0.5 * nt) / pairs, "6.3"),
        });
    }
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    const s = try parse(cx, tokens);
    if (!s.noprint) if (cx.graphics) |g| if (g.enabled == true or (g.enabled != false and g.cli_dir != null)) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ODS graphics are not implemented", .{});
    const diagnostic_count = cx.diags.list.items.len;
    const d = design.build(cx.arena, s.input.ds, s.model, cx.diags) catch |err| {
        if (err == error.OutOfMemory or cx.diags.list.items.len > diagnostic_count) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: invalid or nonfinite complete-case model data", .{});
    };
    const r = kernel.fit(cx.arena, d.x, d.y, d.n, d.p, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC LOGISTIC: fitting failed (rank deficiency, separation, or nonconvergence); no results emitted", .{});
    };
    if (!s.noprint) {
        var body: std.ArrayList(u8) = .empty;
        render(cx.arena, &body, s, d, r) catch |err| {
            if (err == error.OutOfMemory) return err;
            return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: nonfinite or singular inference calculation", .{});
        };
        try out.appendSlice(cx.arena, body.items);
    }
}

test "LOGISTIC original REF and EFFECT complete oracle listing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try design.originalFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("binary", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    for ([_][]const u8{ "ref", "effect" }) |param| {
        const source = try std.fmt.allocPrint(a, "proc logistic data=binary; class group(ref='A') / param={s}; model event(event='1')=group x; run;", .{param});
        try run(cx, &out, try lex.tokenize(a, source, &d));
    }
    const expected = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/STAT15.4-oracle/STAT-COMMON-008/reference_effect_coding.expected.txt", a, .limited(1024 * 1024));
    var e = std.mem.tokenizeAny(u8, expected, " \r\n\t\x0c");
    var got = std.mem.tokenizeAny(u8, out.items, " \r\n\t\x0c");
    while (e.next()) |word| try std.testing.expectEqualStrings(word, got.next() orelse "<missing>");
    try std.testing.expect(got.next() == null);
    try std.testing.expectEqualStrings("", try d.render());
}

test "LOGISTIC errors are captured and unsupported parameterizations never fall back" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try design.originalFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("binary", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, "proc logistic; class group(ref='not-present') / param=ref; model event(event='1')=group x; run;", &d)));
    try std.testing.expect(d.hasErrors());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, "proc logistic; class group / param=orthref; model event=group x; run;", &d)));
    try std.testing.expect(diag.gapHit());
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
}
