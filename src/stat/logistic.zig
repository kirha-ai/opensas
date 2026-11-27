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
pub const OddsRequest = struct { variable: usize, at_variable: usize, values: []const f64 };
pub const Spec = struct {
    input: proc.ProcInput,
    model: design.Spec,
    noprint: bool = false,
    trials: ?usize = null,
    by_columns: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    odds_requests: []const OddsRequest = &.{},
    alpha: f64 = 0.05,
    plots_none: bool = false,
};
pub const Counts = struct { read: usize, used: usize, frequency_read: f64, frequency_used: f64, events: f64, full_constant: f64 = 0 };
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
fn modelTerms(cx: proc.ProcCtx, ds: *const Dataset, tokens: []const lex.Token, variables: *std.ArrayList(usize), terms: *std.ArrayList([]const usize)) diag.Error!void {
    var i: usize = 0;
    while (i < tokens.len) {
        var chain: std.ArrayList([]const usize) = .empty;
        while (true) {
            var factors: std.ArrayList(usize) = .empty;
            try factors.append(cx.arena, try variable(cx, ds, tokens, &i));
            while (at(tokens, i, .star)) {
                i += 1;
                try factors.append(cx.arena, try variable(cx, ds, tokens, &i));
            }
            for (factors.items) |ci| if (std.mem.indexOfScalar(usize, variables.items, ci) == null) try variables.append(cx.arena, ci);
            try chain.append(cx.arena, factors.items);
            if (!at(tokens, i, .pipe)) break;
            i += 1;
        }
        if (chain.items.len > 16) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: excessive bar expansion", .{});
        const limit = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(chain.items.len));
        for (1..limit) |mask| {
            var combined: std.ArrayList(usize) = .empty;
            for (chain.items, 0..) |factors, k| if (mask & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k))) != 0) try combined.appendSlice(cx.arena, factors);
            const Context = struct {
                fn less(order: []const usize, a: usize, b: usize) bool {
                    return std.mem.indexOfScalar(usize, order, a).? < std.mem.indexOfScalar(usize, order, b).?;
                }
            };
            std.mem.sort(usize, combined.items, variables.items, Context.less);
            var duplicate = false;
            for (terms.items) |old| if (std.mem.eql(usize, old, combined.items)) {
                duplicate = true;
                break;
            };
            if (!duplicate) try terms.append(cx.arena, combined.items);
        }
    }
}
fn numericLiteral(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        if (at(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const value = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*));
    i.* += 1;
    if (!std.math.isFinite(value)) return invalid(cx, t, i.* - 1);
    return value;
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
        if (kw(t, i, "alpha")) {
            if (!at(t, i + 1, .eq)) return invalid(cx, t, i);
            i += 2;
            s.alpha = try numericLiteral(cx, t, &i);
            if (!(s.alpha > 0 and s.alpha < 1)) return invalid(cx, t, i - 1);
            continue;
        }
        if (kw(t, i, "plots")) {
            if (!at(t, i + 1, .eq) or !kw(t, i + 2, "none")) return unsupported(cx, t[i]);
            s.plots_none = true;
            i += 3;
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
    var terms: std.ArrayList([]const usize) = .empty;
    var odds_requests: std.ArrayList(OddsRequest) = .empty;
    var bys: by.Statements = .{};
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
                while (j < end and !at(t, j, .rparen)) {
                    const option = t[j];
                    if (kw(t, j, "descending") or kw(t, j, "desc")) {
                        s.model.response_descending = true;
                        j += 1;
                        continue;
                    }
                    if (!at(t, j + 1, .eq)) return invalid(cx, t, j);
                    j += 2;
                    if (eq(option.text, "event")) {
                        s.model.event = try reference(cx, t[0..end], &j);
                    } else if (eq(option.text, "ref") or eq(option.text, "reference")) {
                        s.model.response_reference = try reference(cx, t[0..end], &j);
                    } else if (eq(option.text, "order")) {
                        if (kw(t, j, "data")) s.model.response_order = .data else if (kw(t, j, "formatted")) s.model.response_order = .formatted else if (kw(t, j, "freq")) s.model.response_order = .freq else if (kw(t, j, "internal")) s.model.response_order = .internal else return invalid(cx, t, j);
                        j += 1;
                    } else return unsupported(cx, option);
                }
                if (!at(t, j, .rparen)) return invalid(cx, t, j);
                if (s.model.event != null and s.model.response_reference != null)
                    return proc.failGap(cx.diags, t[j - 1].line, "PROC LOGISTIC: combined EVENT and REF options are not implemented", .{});
                j += 1;
            }
            if (at(t, j, .slash)) {
                j += 1;
                s.trials = try variable(cx, s.input.ds, t[0..end], &j);
            }
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            var model_end = j;
            while (model_end < end and !at(t, model_end, .slash)) model_end += 1;
            try modelTerms(cx, s.input.ds, t[j..model_end], &effects, &terms);
            j = model_end;
            if (j < end) {
                j += 1;
                if (!kw(t, j, "link") or !at(t, j + 1, .eq) or !kw(t, j + 2, "logit") or j + 3 != end) return unsupported(cx, t[j]);
            }
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "freq") or kw(t, i, "weight")) {
            var j = i + 1;
            const ci = try variable(cx, s.input.ds, t[0..end], &j);
            if (j != end) return unsupported(cx, t[j]);
            if (s.input.ds.columns.items[ci].type != .num) return invalid(cx, t, i + 1);
            if (kw(t, i, "freq")) {
                if (s.model.frequency == null) s.model.frequency = ci;
            } else {
                if (s.model.weight == null) s.model.weight = ci;
            }
        } else if (kw(t, i, "id")) {
            var names: std.ArrayList([]const u8) = .empty;
            try lists.append(cx.arena, s.input.ds, t[i + 1 .. end], &names, cx.diags);
        } else if (kw(t, i, "oddsratio")) {
            var j = i + 1;
            const target = try variable(cx, s.input.ds, t[0..end], &j);
            if (!at(t, j, .slash) or !kw(t, j + 1, "at") or !at(t, j + 2, .lparen)) return unsupported(cx, t[i]);
            j += 3;
            const at_variable = try variable(cx, s.input.ds, t[0..end], &j);
            if (!at(t, j, .eq)) return invalid(cx, t, j);
            j += 1;
            var values: std.ArrayList(f64) = .empty;
            while (j < end and !at(t, j, .rparen)) {
                if (at(t, j, .comma)) {
                    j += 1;
                    continue;
                }
                try values.append(cx.arena, try numericLiteral(cx, t[0..end], &j));
            }
            if (values.items.len == 0 or !at(t, j, .rparen) or j + 1 != end) return invalid(cx, t, j);
            try odds_requests.append(cx.arena, .{ .variable = target, .at_variable = at_variable, .values = values.items });
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
    s.model.terms = terms.items;
    s.odds_requests = odds_requests.items;
    const by_spec = try bys.resolve(cx.arena, s.input.ds, cx.diags);
    const by_columns = try cx.arena.alloc(usize, by_spec.names.len);
    for (by_spec.names, 0..) |by_name, k| by_columns[k] = s.input.ds.indexOf(by_name).?;
    s.by_columns = by_columns;
    s.by_desc = by_spec.desc;
    s.notsorted = by_spec.notsorted;
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

fn estimateText(a: A, x: f64) diag.Error![]const u8 {
    if (x != 0 and @abs(x) < 0.01) return format.bestNumW(a, x, 8);
    return number(a, x, "10.4");
}
fn defaultOdds(d: design.Design, e: design.Effect) bool {
    if (e.variables.len != 1) return false;
    for (d.effects) |other| if (other.variables.len > 1 and std.mem.indexOfScalar(usize, other.variables, e.column) != null) return false;
    return true;
}
fn hasDefaultOdds(d: design.Design) bool {
    for (d.effects) |e| if (defaultOdds(d, e)) return true;
    return false;
}
pub fn render(a: A, out: *std.ArrayList(u8), s: Spec, d: design.Design, r: kernel.Fit, counts: Counts) diag.Error!void {
    const ds = s.input.ds;
    const response_name = ds.columns.items[s.model.response].name;
    try out.print(a, "The LOGISTIC Procedure\n\nModel Information\n\nData Set {s}\n", .{try lists.datasetName(a, ds)});
    if (s.trials) |trials| {
        try out.print(a, "Response Variable (Events) {s}\nResponse Variable (Trials) {s}\n", .{ response_name, ds.columns.items[trials].name });
    } else try out.print(a, "Response Variable {s}\nNumber of Response Levels 2\n", .{response_name});
    if (s.model.frequency) |ci| try out.print(a, "Frequency Variable {s}\n", .{ds.columns.items[ci].name});
    if (s.model.weight) |ci| try out.print(a, "Weight Variable {s}\n", .{ds.columns.items[ci].name});
    try out.print(a, "Model binary logit\nOptimization Technique Fisher's scoring\n\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ counts.read, counts.used });
    if (s.trials != null or s.model.frequency != null) try out.print(a, "Sum of Frequencies Read {s}\nSum of Frequencies Used {s}\n", .{ try number(a, counts.frequency_read, "best12."), try number(a, counts.frequency_used, "best12.") });
    if (s.trials != null) {
        try out.print(a, "\nResponse Profile\n\nOrdered Binary Total\nValue Outcome Frequency\n\n1 Event {s}\n2 Nonevent {s}\n\n", .{ try number(a, counts.events, "best12."), try number(a, counts.frequency_used - counts.events, "best12.") });
    } else {
        try out.print(a, "\nResponse Profile\n\nOrdered Total\nValue {s} Frequency\n\n", .{response_name});
        for (d.response.levels, 0..) |level, i| try out.print(a, "{d} {s} {s}\n", .{ i + 1, level.label, try number(a, level.frequency, "best12.") });
        try out.print(a, "\nProbability modeled is {s}={s}.\n\n", .{ response_name, d.response.levels[d.event_index].label });
    }
    if (d.classes.len > 0) {
        try out.appendSlice(a, "Class Level Information\n\nDesign\nClass Value Variables\n\n");
        for (d.classes) |c| for (c.map.levels, 0..) |level, i| {
            if (i == 0) try out.print(a, "{s} ", .{ds.columns.items[c.column].name});
            try out.appendSlice(a, level.label);
            for (0..c.map.levels.len) |j| if (j != c.reference) try out.print(a, " {s}", .{try number(a, design.code(i, c.reference, j, c.coding), "best8.")});
            try out.appendSlice(a, "\n");
        };
    }
    try out.appendSlice(a, "\nModel Convergence Status\n\nConvergence criterion (GCONV=1E-8) satisfied.\n\nModel Fit Statistics\n\n");
    if (s.trials != null) try out.appendSlice(a, "Intercept and Covariates\nIntercept Log Full Log\nCriterion Only Likelihood Likelihood\n\n") else try out.appendSlice(a, "Intercept\nIntercept and\nCriterion Only Covariates\n\n");
    const null_deviance = -2 * r.null_log_likelihood;
    const deviance = -2 * r.log_likelihood;
    const nf: f64 = counts.frequency_used;
    const pf: f64 = @floatFromInt(d.p);
    for ([_][]const u8{ "AIC", "SC", "-2 Log L" }, [_]f64{ null_deviance + 2, null_deviance + @log(nf), null_deviance }, [_]f64{ deviance + 2 * pf, deviance + pf * @log(nf), deviance }) |name, null_value, full| {
        try out.print(a, "{s} {s} {s}", .{ name, try number(a, null_value, "10.3"), try number(a, full, "10.3") });
        if (s.trials != null) try out.print(a, " {s}", .{try number(a, full - 2 * counts.full_constant, "10.3")});
        try out.appendSlice(a, "\n");
    }
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
            try out.print(a, "{s} {d} {s} {s}\n", .{ e.name, e.len, try number(a, q, "10.4"), try number(a, kernel.chiTail(q, e.len), "pvalue6.4") });
        }
    }
    try out.appendSlice(a, "\nAnalysis of Maximum Likelihood Estimates\n\nStandard Wald\nParameter DF Estimate Error Chi-Square Pr > ChiSq\n\n");
    for (d.parameters, 0..) |parameter, j| {
        const se = @sqrt(r.covariance[j * d.p + j]);
        const q = r.coefficients[j] * r.coefficients[j] / r.covariance[j * d.p + j];
        try out.print(a, "{s} {s} 1 {s} {s} {s} {s}\n", .{ parameter.name, parameter.level orelse "", try estimateText(a, r.coefficients[j]), try number(a, se, "10.4"), try number(a, q, "10.4"), try number(a, kernel.chiTail(q, 1), "pvalue6.4") });
    }
    if (hasDefaultOdds(d)) {
        try out.print(a, "\nOdds Ratio Estimates\n\nPoint {s}% Wald\nEffect Estimate Confidence Limits\n\n", .{try number(a, 100 * (1 - s.alpha), "best8.")});
        const z = fns.distQuantile(.normal, 1 - s.alpha / 2, &.{}).?;
        const contrast = try a.alloc(f64, d.p);
        defer a.free(contrast);
        for (d.effects) |e| {
            if (!defaultOdds(d, e)) continue;
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
    const assoc = kernel.associationWeighted(d.y, r.probabilities, d.frequencies);
    const pairs: f64 = assoc.pairs;
    if (assoc.pairs > 0) {
        const nc: f64 = assoc.concordant;
        const nd: f64 = assoc.discordant;
        const nt: f64 = assoc.tied;
        const gamma = if (nc + nd > 0) (nc - nd) / (nc + nd) else std.math.nan(f64);
        try out.print(a, "\nAssociation of Predicted Probabilities and Observed Responses\n\nPercent Concordant {s} Somers' D {s}\nPercent Discordant {s} Gamma {s}\nPercent Tied {s} Tau-a {s}\nPairs {s} c {s}\n\n", .{
            try number(a, 100 * nc / pairs, "6.1"), try number(a, (nc - nd) / pairs, "6.3"),               try number(a, 100 * nd / pairs, "6.1"), try number(a, gamma, "6.3"),
            try number(a, 100 * nt / pairs, "6.1"), try number(a, 2 * (nc - nd) / (nf * (nf - 1)), "6.3"), try number(a, assoc.pairs, "best12."),  try number(a, (nc + 0.5 * nt) / pairs, "6.3"),
        });
    }
}

const Analysis = struct { data: *Dataset, design: design.Design, fit: kernel.Fit, counts: Counts };
fn analyze(cx: proc.ProcCtx, s: Spec) diag.Error!Analysis {
    const a = cx.arena;
    const ds = s.input.ds;
    var model = s.model;
    var work = ds;
    var origin: std.ArrayList(usize) = .empty;
    const constants = try a.alloc(f64, ds.rows.items.len);
    @memset(constants, 0);
    var frequency_read: f64 = 0;
    if (s.trials) |trials| {
        if (ds.columns.items[s.model.response].type != .num or ds.columns.items[trials].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC LOGISTIC: events/trials variables must be numeric", .{});
        work = try a.create(Dataset);
        work.* = Dataset.init(a, ds.name);
        try work.columns.appendSlice(a, ds.columns.items);
        const event_column = try work.addColumn("_LOGISTIC_EVENT_", .num);
        const frequency_column = try work.addColumn("_LOGISTIC_FREQUENCY_", .num);
        const cells = try a.alloc(@import("../value.zig").Value, work.columns.items.len);
        for (ds.rows.items, 0..) |row, index| {
            const f = if (s.model.frequency) |ci| @trunc(row[ci].num) else 1;
            const n = row[trials].num;
            const r = row[s.model.response].num;
            if (!std.math.isFinite(f) or f < 1 or !std.math.isFinite(n) or n <= 0) continue;
            frequency_read += f * n;
            if (!std.math.isFinite(r) or r < 0 or r > n) continue;
            if (@trunc(n) != n or @trunc(r) != r) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: noninteger binomial counts are not implemented", .{});
            const weight = if (s.model.weight) |ci| row[ci].num else 1;
            constants[index] = if (std.math.isFinite(weight) and weight > 0) f * weight * (fns.lgammaOf(n + 1) - fns.lgammaOf(r + 1) - fns.lgammaOf(n - r + 1)) else 0;
            @memcpy(cells[0..row.len], row);
            for ([_]f64{ r, n - r }, [_]f64{ 1, 0 }) |count, event| {
                if (count == 0) continue;
                cells[event_column] = .{ .num = event };
                cells[frequency_column] = .{ .num = f * count };
                try work.appendRow(cells);
                try origin.append(a, index);
            }
        }
        model.response = event_column;
        model.event = .last;
        model.frequency = frequency_column;
    } else {
        for (ds.rows.items, 0..) |row, i| {
            const f = if (s.model.frequency) |ci| @trunc(row[ci].num) else 1;
            if (std.math.isFinite(f) and f >= 1) frequency_read += f;
            try origin.append(a, i);
        }
    }
    const before = cx.diags.list.items.len;
    const d = design.build(a, work, model, cx.diags) catch |err| {
        if (err == error.OutOfMemory or cx.diags.list.items.len > before) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: invalid or nonfinite complete-case model data", .{});
    };
    const r = kernel.fitWeighted(a, d.x, d.y, d.n, d.p, d.frequencies, d.weights, .{}) catch |err| {
        if (err == error.OutOfMemory) return err;
        return proc.failGap(cx.diags, 0, "PROC LOGISTIC: fitting failed (rank deficiency, separation, or nonconvergence); no results emitted", .{});
    };
    const used = try a.alloc(bool, ds.rows.items.len);
    @memset(used, false);
    var counts: Counts = .{ .read = ds.rows.items.len, .used = 0, .frequency_read = frequency_read, .frequency_used = d.total_frequency, .events = 0 };
    for (d.source_rows, d.y, d.frequencies) |row, y, f| {
        used[origin.items[row]] = true;
        counts.events += y * f;
    }
    for (used, 0..) |yes, i| if (yes) {
        counts.used += 1;
        counts.full_constant += constants[i];
    };
    return .{ .data = work, .design = d, .fit = r, .counts = counts };
}
fn oddsTable(a: A, out: *std.ArrayList(u8), rows: []const @import("logistic_plots.zig").Row, alpha: f64) diag.Error!void {
    try out.print(a, "\nOdds Ratio Estimates and Wald Confidence Intervals\n\nOdds Ratio Estimate {s}% Confidence Limits\n\n", .{try number(a, 100 * (1 - alpha), "best8.")});
    for (rows) |row| try out.print(a, "{s} {s} {s} {s}\n", .{ row.label, try odds(a, @exp(row.log_estimate)), try odds(a, @exp(row.log_lower)), try odds(a, @exp(row.log_upper)) });
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    const a = cx.arena;
    if (spec.by_columns.len > 0 and spec.model.classes.len > 0) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: global CLASS levels across BY groups are not implemented", .{});
    const groups = try by.checkedSlices(a, spec.input.ds, spec.by_columns, spec.by_desc, spec.notsorted, cx.diags);
    for (groups, 0..) |group, group_index| {
        var ds = spec.input.ds.*;
        ds.rows = .empty;
        try ds.rows.appendSlice(a, group.rows);
        var s = spec;
        s.input.ds = &ds;
        const result = try analyze(cx, s);
        var body: std.ArrayList(u8) = .empty;
        if (!s.noprint) try render(a, &body, s, result.design, result.fit, result.counts);
        var by_text: std.ArrayList(u8) = .empty;
        if (s.by_columns.len > 0) try by.appendLine(a, &by_text, spec.input.ds, group.rep.?, s.by_columns);
        for (s.odds_requests, 0..) |request, request_index| {
            const plots = @import("logistic_plots.zig");
            const rows = plots.atRows(a, result.data, result.design, result.fit, request.variable, request.at_variable, request.values, s.alpha) catch |err| {
                if (err == error.OutOfMemory) return err;
                return cx.diags.fail(error.ExecError, 0, "PROC LOGISTIC: unsupported or invalid ODDSRATIO AT request", .{});
            };
            if (!s.noprint) try oddsTable(a, &body, rows, s.alpha);
            if (!s.noprint and !s.plots_none) if (cx.graphics) |g| if (g.enabled == true or (g.enabled != false and g.cli_dir != null)) {
                const title = try std.fmt.allocPrint(a, "Odds Ratios for {s} ({s}% Wald CI)", .{ ds.columns.items[request.variable].name, try number(a, 100 * (1 - s.alpha), "best8.") });
                const bytes = plots.render(a, rows, title, std.mem.trim(u8, by_text.items, " \r\n")) catch return error.OutOfMemory;
                const path = if (s.by_columns.len > 0) try std.fmt.allocPrint(a, "Logistic.ByGroup{d}.OddsRatioPlot", .{group_index + 1}) else "Logistic.OddsRatioPlot";
                try g.queue(group_index * s.odds_requests.len + request_index, "logistic-oddsratio", bytes, .{ .name = .OddsRatioPlot, .label = title, .template = "Stat.Logistic.Graphics.OddsRatioPlot", .path = path });
            };
        }
        if (body.items.len > 0) {
            try out.appendSlice(a, by_text.items);
            try out.appendSlice(a, body.items);
        }
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
    const asset = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "tests/corpus/persist_logistic_common008_reference_effect_coding.txt", a, .limited(1024 * 1024));
    const prefix = "# corpus assertions\nwords ";
    try std.testing.expect(std.mem.startsWith(u8, asset, prefix));
    const expected = asset[prefix.len..][0..std.mem.indexOfScalar(u8, asset[prefix.len..], '\n').?];
    var e = std.mem.tokenizeAny(u8, expected, " \r\n\t\x0c");
    var got = std.mem.tokenizeAny(u8, out.items, " \r\n\t\x0c");
    while (e.next()) |word| try std.testing.expectEqualStrings(word, got.next() orelse "<missing>");
    try std.testing.expect(got.next() == null);
    try std.testing.expectEqualStrings("", try d.render());
}

test {
    _ = @import("logistic_persistence_tests.zig");
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

fn ingots(a: A) !Dataset {
    var ds = Dataset.init(a, "ingots");
    for ([_][]const u8{ "Heat", "Soak", "r", "n" }) |name| _ = try ds.addColumn(name, .num);
    const cells = [_][4]f64{
        .{ 7, 1, 0, 10 },   .{ 14, 1, 0, 31 },   .{ 27, 1, 1, 56 },   .{ 51, 1, 3, 13 },
        .{ 7, 1.7, 0, 17 }, .{ 14, 1.7, 0, 43 }, .{ 27, 1.7, 4, 44 }, .{ 51, 1.7, 0, 1 },
        .{ 7, 2.2, 0, 7 },  .{ 14, 2.2, 2, 33 }, .{ 27, 2.2, 0, 21 }, .{ 51, 2.2, 0, 1 },
        .{ 7, 2.8, 0, 12 }, .{ 14, 2.8, 0, 31 }, .{ 27, 2.8, 1, 22 }, .{ 51, 4, 0, 1 },
        .{ 7, 4, 0, 9 },    .{ 14, 4, 0, 19 },   .{ 27, 4, 1, 16 },
    };
    for (cells) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] }, .{ .num = row[3] } });
    return ds;
}
test "LOGISTIC001 aggregated frequency and individual likelihood identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try ingots(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ingots", &ds);
    var errors = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &errors };
    const spec = try parse(cx, try lex.tokenize(a, "proc logistic data=ingots; model r/n=Heat Soak; run;", &errors));
    const grouped = try analyze(cx, spec);
    try std.testing.expectEqual(@as(usize, 19), grouped.counts.used);
    try std.testing.expectEqual(@as(f64, 387), grouped.counts.frequency_used);
    try std.testing.expectEqual(@as(f64, 12), grouped.counts.events);
    var xs: std.ArrayList(f64) = .empty;
    var ys: std.ArrayList(f64) = .empty;
    var constant: f64 = 0;
    for (ds.rows.items) |row| {
        const n: usize = @intFromFloat(row[3].num);
        const r: usize = @intFromFloat(row[2].num);
        for (0..n) |i| {
            try xs.appendSlice(a, &.{ 1, row[0].num, row[1].num });
            try ys.append(a, if (i < r) 1 else 0);
        }
        for (1..r + 1) |k| constant += @log(@as(f64, @floatFromInt(n - k + 1)) / @as(f64, @floatFromInt(k)));
    }
    const expanded = try kernel.fit(a, xs.items, ys.items, ys.items.len, 3, .{});
    for (grouped.fit.coefficients, expanded.coefficients) |g, e| try std.testing.expectApproxEqAbs(g, e, 1e-9);
    for (grouped.fit.covariance, expanded.covariance) |g, e| try std.testing.expectApproxEqAbs(g, e, 1e-9);
    try std.testing.expectApproxEqAbs(grouped.fit.log_likelihood, expanded.log_likelihood, 1e-10);
    try std.testing.expectApproxEqAbs(constant, grouped.counts.full_constant, 1e-10);
    const null_ll = 12 * @log(@as(f64, 12.0 / 387.0)) + 375 * @log(@as(f64, 375.0 / 387.0));
    try std.testing.expectApproxEqAbs(null_ll, grouped.fit.null_log_likelihood, 1e-10);
}
test "LOGISTIC001 AT contrasts and graph rows retain independent Wald endpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try ingots(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ingots", &ds);
    var errors = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &errors };
    const spec = try parse(cx, try lex.tokenize(a, "proc logistic; model r/n=Heat|Soak; oddsratio Heat / at(Soak=1 2 3 4); run;", &errors));
    const analysis = try analyze(cx, spec);
    const r = analysis.fit;
    const plots = @import("logistic_plots.zig");
    const rows = try plots.atRows(a, analysis.data, analysis.design, r, 0, 1, &.{ 1, 2, 3, 4 }, 0.05);
    const z = fns.distQuantile(.normal, 0.975, &.{}).?;
    for (rows, 0..) |row, i| {
        const soak: f64 = @floatFromInt(i + 1);
        const estimate = r.coefficients[1] + soak * r.coefficients[3];
        const variance = r.covariance[5] + 2 * soak * r.covariance[7] + soak * soak * r.covariance[15];
        try std.testing.expectApproxEqAbs(estimate, row.log_estimate, 1e-12);
        try std.testing.expectApproxEqAbs(estimate - z * @sqrt(variance), row.log_lower, 1e-12);
        try std.testing.expectApproxEqAbs(estimate + z * @sqrt(variance), row.log_upper, 1e-12);
    }
    const bytes = try plots.render(a, rows, "Odds Ratios for Heat", "_oracle_by=1");
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, bytes, "class=\"odds-row\""));
    try std.testing.expect(std.mem.indexOf(u8, bytes, "data-reference=\"1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, bytes, "_oracle_by=1") != null);
}

test "persistence LOGISTIC original grouped information independently verifies every SVG odds endpoint" {
    const t = std.testing;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const helper = @import("glm_persistence_tests.zig");
    const plots = @import("logistic_plots.zig");
    var ds = try helper.data(a, "tests/corpus/persist_logistic_logistic001_documented_feature.sas", "ingots", &.{ "Heat", "Soak", "r", "n" }, &.{}, 0);
    try t.expectEqual(@as(usize, 19), ds.rows.items.len);
    const independent = try @import("logistic_persistence_tests.zig").reference(ds);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ingots", &ds);
    var d = @import("../diag.zig").Diagnostics.init(a);
    const cx: @import("../proc.zig").ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const spec = try parse(cx, try @import("../lexer.zig").tokenize(a, "proc logistic data=ingots; model r/n=Heat|Soak; oddsratio Heat / at(Soak=1 2 3 4); run;", &d));
    const analysis = try analyze(cx, spec);
    const rows = try plots.atRows(a, analysis.data, analysis.design, analysis.fit, 0, 1, &.{ 1, 2, 3, 4 }, 0.05);
    const bytes = try plots.render(a, rows, "Odds Ratios for Heat", "_oracle_by=1");
    var tags = std.mem.tokenizeScalar(u8, bytes, '<');
    var n: usize = 0;
    while (tags.next()) |tag| if (std.mem.indexOf(u8, tag, "class=\"odds-row\"") != null) {
        const soak: f64 = @floatFromInt(n + 1);
        const eta = independent.beta[1] + soak * independent.beta[3];
        const v = independent.covariance;
        const radius = 1.959963984540054 * @sqrt(v[1][1] + 2 * soak * v[1][3] + soak * soak * v[3][3]);
        // Original independent NumPy-vs-QR verification used 1e-9 absolute
        // on unrounded OR endpoints; retain it, never listing tolerances.
        try t.expectApproxEqAbs(@exp(eta), try helper.attribute(tag, "data-estimate=\""), 1e-9);
        try t.expectApproxEqAbs(@exp(eta - radius), try helper.attribute(tag, "data-lower=\""), 1e-9);
        try t.expectApproxEqAbs(@exp(eta + radius), try helper.attribute(tag, "data-upper=\""), 1e-9);
        n += 1;
    };
    try t.expectEqual(@as(usize, 4), n);
    try t.expectEqualStrings("", try d.render());
}

// S154 physical pp.5870–5871 and5905–5906. With an intercept-only
// binomial sample, beta=log(nevent/nother), Var(beta)=1/nevent+1/nother.
// These closed forms (not a captured OpenSAS listing) establish the ordering
// and fit contract, including the complete response profile and row mapping.
test "LOGISTIC004 response ordering and reference options preserve analytic binary fit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "ordered");
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("f", .num);
    try ds.appendRow(&.{ .{ .num = 10 }, .{ .num = 2 } });
    try ds.appendRow(&.{ .{ .num = 2 }, .{ .num = 8 } });
    try ds.appendRow(&.{ .{ .num = 99 }, .{ .num = 0 } });
    try ds.appendRow(&.{ @import("../value.zig").Value.missing, .{ .num = 20 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ordered", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const Case = struct { options: []const u8, first: f64, event: f64 };
    const cases = [_]Case{
        .{ .options = "", .first = 2, .event = 2 },
        .{ .options = "order=formatted", .first = 2, .event = 2 },
        .{ .options = "order=internal", .first = 2, .event = 2 },
        .{ .options = "order=data", .first = 10, .event = 10 },
        .{ .options = "order=freq", .first = 2, .event = 2 },
        .{ .options = "descending", .first = 10, .event = 10 },
        .{ .options = "order=data desc", .first = 2, .event = 2 },
        .{ .options = "desc order=freq", .first = 10, .event = 10 },
        .{ .options = "order=data event=last", .first = 10, .event = 2 },
        .{ .options = "order=data event=first", .first = 10, .event = 10 },
        .{ .options = "desc event='2'", .first = 10, .event = 2 },
        .{ .options = "reference='2'", .first = 2, .event = 10 },
        .{ .options = "ref=first", .first = 2, .event = 10 },
        .{ .options = "ref=last", .first = 2, .event = 2 },
        .{ .options = "order=data desc ref=last", .first = 2, .event = 2 },
    };
    for (cases) |c| {
        const response_options = if (c.options.len == 0) "" else try std.fmt.allocPrint(a, "({s})", .{c.options});
        const source = try std.fmt.allocPrint(a, "proc logistic data=ordered; freq f; model y{s}=; run;", .{response_options});
        const spec = try parse(cx, try lex.tokenize(a, source, &d));
        const result = try analyze(cx, spec);
        const profile = result.design.response;
        try std.testing.expectEqual(@as(usize, 2), profile.levels.len);
        try std.testing.expectEqual(c.first, profile.levels[0].value.num);
        try std.testing.expectEqual(@as(f64, 12) - c.first, profile.levels[1].value.num);
        try std.testing.expectEqual(c.event, profile.levels[result.design.event_index].value.num);
        for (profile.levels) |level| try std.testing.expectEqual(if (level.value.num == 2) @as(f64, 8) else @as(f64, 2), level.frequency);
        try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, result.design.source_rows);
        try std.testing.expectEqualSlices(f64, &.{ 1, 1 }, result.design.x);
        try std.testing.expectEqualSlices(f64, if (c.event == 10) &.{ 1, 0 } else &.{ 0, 1 }, result.design.y);
        const events: f64 = if (c.event == 2) 8 else 2;
        // Exact intercept initialization; 1e-12 accommodates floating log/QR.
        try std.testing.expectApproxEqAbs(@log(events / (10 - events)), result.fit.coefficients[0], 1e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 0.625), result.fit.covariance[0], 1e-12);
        for (result.fit.probabilities) |p| try std.testing.expectApproxEqAbs(events / 10, p, 1e-12);
        try std.testing.expectEqual(@as(usize, 4), result.counts.read);
        try std.testing.expectEqual(@as(usize, 2), result.counts.used);
        try std.testing.expectEqual(@as(f64, 10), result.counts.frequency_used);
        var listing: std.ArrayList(u8) = .empty;
        try run(cx, &listing, try lex.tokenize(a, source, &d));
        const want = try std.fmt.allocPrint(a, "Response Profile\n\nOrdered Total\nValue y Frequency\n\n1 {d} {d}\n2 {d} {d}\n\nProbability modeled is y={d}.\n\n", .{
            @as(i32, @intFromFloat(c.first)),      @as(i32, if (c.first == 2) 8 else 2),
            @as(i32, @intFromFloat(12 - c.first)), @as(i32, if (c.first == 2) 2 else 8),
            @as(i32, @intFromFloat(c.event)),
        });
        try std.testing.expect(std.mem.indexOf(u8, listing.items, want) != null);
    }
    try std.testing.expectEqualStrings("", try d.render());
}

test "LOGISTIC004 formatted response values and ordering do not fall back to raw event labels" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const entries = [_]format.UserFmtEntry{ .{ .lo = 0, .hi = 0, .label = "nonevent" }, .{ .lo = 1, .hi = 1, .label = "event" } };
    const formats = [_]format.UserFmt{.{ .name = "responseorder", .is_char = false, .entries = &entries }};
    const previous = format.userFormats();
    format.setUserFormats(&formats);
    defer format.setUserFormats(previous);
    var ds = Dataset.init(a, "formatted");
    _ = try ds.addColumn("y", .num);
    ds.columns.items[0].format = "responseorder.";
    for ([_]f64{ 0, 0, 0, 1 }) |value| try ds.appendRow(&.{.{ .num = value }});
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("formatted", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "", "event='event'", "ref='nonevent'", "order=internal desc" }) |options| {
        const response_options = if (options.len == 0) "" else try std.fmt.allocPrint(a, "({s})", .{options});
        const source = try std.fmt.allocPrint(a, "proc logistic; model y{s}=; run;", .{response_options});
        const spec = try parse(cx, try lex.tokenize(a, source, &d));
        const result = try analyze(cx, spec);
        try std.testing.expectEqualStrings("event", result.design.response.levels[result.design.event_index].label);
        try std.testing.expectApproxEqAbs(-@log(@as(f64, 3)), result.fit.coefficients[0], 1e-12);
    }
    var out: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, "proc logistic; model y(event='1')=; run;", &d)));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "EVENT/REF value is not a response level") != null);
}

test "LOGISTIC004 invalid ordering and unsupported ordinal responses stay visible" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "ordinal");
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 1, 2, 3 }) |value| try ds.appendRow(&.{.{ .num = value }});
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ordinal", &ds);
    diag.resetGap();
    defer diag.resetGap();
    for ([_][]const u8{ "order=bogus", "event='missing' ref=first", "desc" }, [_]bool{ false, true, true }) |options, gap| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        const source = try std.fmt.allocPrint(a, "proc logistic; model y({s})=; run;", .{options});
        diag.resetGap();
        try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, source, &d)));
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
        try std.testing.expect(d.hasErrors());
        try std.testing.expectEqual(@as(u8, if (gap) 2 else 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    // Malformed syntax stays a user error even when valid combined options
    // would require an unsupported precedence rule.
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, "proc logistic; model y(event=first ref=last; run;", &d)));
    try std.testing.expectEqual(@as(u8, 1), diag.exitCode(diag.gapHit(), d.hasErrors()));
}

test "LOGISTIC004 character data frequency ordering and missing exclusion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "character");
    _ = try ds.addColumn("y", .char);
    _ = try ds.addColumn("f", .num);
    for ([_][]const u8{ "yes", "no", " ", "none" }, [_]f64{ 7, 3, 50, 0 }) |value, frequency| try ds.appendRow(&.{ .{ .str = value }, .{ .num = frequency } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("character", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "data", "freq", "internal", "formatted" }, [_][]const u8{ "yes", "yes", "no", "no" }) |order, first| {
        const source = try std.fmt.allocPrint(a, "proc logistic; freq f; model y(order={s} ref=first)=; run;", .{order});
        const result = try analyze(cx, try parse(cx, try lex.tokenize(a, source, &d)));
        try std.testing.expectEqualStrings(first, result.design.response.levels[0].label);
        try std.testing.expectEqual(@as(usize, 2), result.design.response.levels.len);
        const events: f64 = if (std.mem.eql(u8, first, "yes")) 3 else 7;
        try std.testing.expectApproxEqAbs(@log(events / (10 - events)), result.fit.coefficients[0], 1e-12);
        try std.testing.expectEqual(events, result.counts.events);
        try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, result.design.source_rows);
    }
}
