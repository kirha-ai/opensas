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
const ordinal = @import("logistic_ordinal.zig");
const odds_kernel = @import("logistic_odds.zig");
const roc = @import("logistic_roc.zig");
const gof = @import("logistic_gof.zig");
const format = @import("../format.zig");
const fns = @import("../functions.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const OddsRequest = odds_kernel.Request;
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
    link: ordinal.Link = .logit,
    fit_options: kernel.Options = .{},
    units: []const odds_kernel.Units = &.{},
    default_units: []const f64 = &.{},
    units_present: bool = false,
    clodds: ?odds_kernel.Confidence = null,
    no_odds_ratio: bool = false,
    nofit: bool = false,
    roc_models: []const roc.Model = &.{},
    roc_contrast: ?roc.Contrast = null,
    roc_plot: bool = false,
    roc_id_probability: bool = false,
    roc_nodetails: bool = false,
    roc_alpha: ?f64 = null,
    roc_epsilon: f64 = @sqrt(std.math.floatEps(f64)),
    roc_detail: bool = false,
    scale: gof.Scale = .unspecified,
    scale_constant: f64 = 1,
    aggregate: ?[]const usize = null,
    ctable: bool = false,
    pprob: []const f64 = &.{},
    pevent: []const f64 = &.{},
    lackfit: ?gof.HlOptions = null,
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
fn confidence(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!odds_kernel.Confidence {
    const result: odds_kernel.Confidence = if (kw(t, i.*, "wald")) .wald else if (kw(t, i.*, "pl")) .pl else if (kw(t, i.*, "both")) .both else return invalid(cx, t, i.*);
    i.* += 1;
    return result;
}
fn unitValues(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, ignore_sd: bool) diag.Error![]const f64 {
    var values: std.ArrayList(f64) = .empty;
    while (i.* < t.len and !at(t, i.*, .slash) and !(at(t, i.*, .name) and at(t, i.* + 1, .eq))) {
        if (kw(t, i.*, "sd") or ((at(t, i.*, .minus) or at(t, i.*, .plus)) and kw(t, i.* + 1, "sd"))) {
            if (!ignore_sd) return proc.failGap(cx.diags, t[i.*].line, "PROC LOGISTIC: SD units are not implemented", .{});
            // CLASS units are ignored, including their SD forms; no standard
            // deviation is computed or represented by this parser placeholder.
            i.* += if (kw(t, i.*, "sd")) @as(usize, 1) else 2;
            try values.append(cx.arena, 1);
            continue;
        }
        const value = try numericLiteral(cx, t, i);
        if (at(t, i.*, .star)) {
            if (!kw(t, i.* + 1, "sd")) return invalid(cx, t, i.*);
            if (!ignore_sd) return proc.failGap(cx.diags, t[i.*].line, "PROC LOGISTIC: SD units are not implemented", .{});
            i.* += 2;
        }
        if (value == 0) return invalid(cx, t, i.* - 1);
        try values.append(cx.arena, value);
    }
    if (values.items.len == 0) return invalid(cx, t, i.*);
    return values.items;
}
fn unitsFor(s: Spec, variable_: usize) []const f64 {
    var i = s.units.len;
    while (i > 0) {
        i -= 1;
        if (s.units[i].variable == variable_) return s.units[i].values;
    }
    return if (s.default_units.len > 0) s.default_units else &.{1};
}
fn customizedUnits(s: Spec, variable_: usize) ?[]const f64 {
    for (s.units) |unit| if (unit.variable == variable_) return unit.values;
    return if (s.default_units.len > 0) s.default_units else null;
}
fn probabilityList(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const f64 {
    const parenthesized = at(t, i.*, .lparen);
    if (parenthesized) i.* += 1;
    var values: std.ArrayList(f64) = .empty;
    while (i.* < t.len and !at(t, i.*, .rparen)) {
        if (at(t, i.*, .comma)) {
            i.* += 1;
            continue;
        }
        if (!at(t, i.*, .number) and !at(t, i.*, .minus) and !at(t, i.*, .plus)) break;
        const first = try numericLiteral(cx, t, i);
        if (!(first >= 0 and first <= 1)) return invalid(cx, t, i.* - 1);
        if (kw(t, i.*, "to")) {
            i.* += 1;
            const last = try numericLiteral(cx, t, i);
            var step: f64 = 1;
            if (kw(t, i.*, "by")) {
                i.* += 1;
                step = try numericLiteral(cx, t, i);
            }
            if (!(last >= 0 and last <= 1) or step == 0 or (last - first) / step < 0) return invalid(cx, t, i.* - 1);
            const intervals = (last - first) / step;
            if (intervals > 10000) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: probability list is too large", .{});
            const count: usize = @intFromFloat(@floor(intervals + 8 * std.math.floatEps(f64) * @max(1, intervals)));
            for (0..count + 1) |index| try values.append(cx.arena, @min(1, @max(0, first + @as(f64, @floatFromInt(index)) * step)));
        } else try values.append(cx.arena, first);
    }
    if (values.items.len == 0) return invalid(cx, t, i.*);
    if (parenthesized) {
        if (!at(t, i.*, .rparen)) return invalid(cx, t, i.*);
        i.* += 1;
    }
    return values.items;
}
fn integerOption(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!usize {
    const number_ = try numericLiteral(cx, t, i);
    if (number_ < 0 or @trunc(number_) != number_) return invalid(cx, t, i.* - 1);
    if (number_ >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: integer option is too large", .{});
    return @intFromFloat(number_);
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
        if (kw(t, i, "rocoptions")) {
            if (!at(t, i + 1, .lparen)) return invalid(cx, t, i);
            i += 2;
            while (i < t.len and !at(t, i, .rparen)) {
                if (kw(t, i, "nodetails")) {
                    s.roc_nodetails = true;
                    i += 1;
                    continue;
                }
                const option = t[i];
                if (!at(t, i + 1, .eq)) return unsupported(cx, option);
                i += 2;
                if (eq(option.text, "alpha")) {
                    s.roc_alpha = try numericLiteral(cx, t, &i);
                    if (!(s.roc_alpha.? > 0 and s.roc_alpha.? < 1)) return invalid(cx, t, i - 1);
                } else if (eq(option.text, "eps")) {
                    s.roc_epsilon = try numericLiteral(cx, t, &i);
                    if (s.roc_epsilon < 0) return invalid(cx, t, i - 1);
                } else if (eq(option.text, "id") and kw(t, i, "prob")) {
                    s.roc_id_probability = true;
                    i += 1;
                } else return unsupported(cx, option);
            }
            if (!at(t, i, .rparen)) return invalid(cx, t, i);
            i += 1;
            continue;
        }
        if (kw(t, i, "plots")) {
            const option = t[i];
            i += 1;
            if (at(t, i, .lparen)) {
                if (!kw(t, i + 1, "only") or !at(t, i + 2, .rparen)) return unsupported(cx, option);
                i += 3;
            }
            if (!at(t, i, .eq)) return unsupported(cx, option);
            i += 1;
            if (kw(t, i, "none")) {
                s.plots_none = true;
                i += 1;
                continue;
            }
            if (!kw(t, i, "roc")) return unsupported(cx, option);
            s.roc_plot = true;
            i += 1;
            if (at(t, i, .lparen)) {
                if (!kw(t, i + 1, "id") or !at(t, i + 2, .eq) or !kw(t, i + 3, "prob") or !at(t, i + 4, .rparen)) return unsupported(cx, option);
                s.roc_id_probability = true;
                i += 5;
            }
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
    var units: std.ArrayList(odds_kernel.Units) = .empty;
    var roc_models: std.ArrayList(roc.Model) = .empty;
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
                while (j < end) {
                    const option = t[j];
                    if (kw(t, j, "ctable")) {
                        s.ctable = true;
                        j += 1;
                        continue;
                    }
                    if (kw(t, j, "aggregate")) {
                        j += 1;
                        var columns: std.ArrayList(usize) = .empty;
                        if (at(t, j, .eq)) {
                            j += 1;
                            if (!at(t, j, .lparen)) return invalid(cx, t, j);
                            j += 1;
                            const begin = j;
                            while (j < end and !at(t, j, .rparen)) j += 1;
                            if (begin == j or !at(t, j, .rparen)) return invalid(cx, t, j);
                            var names: std.ArrayList([]const u8) = .empty;
                            try lists.append(cx.arena, s.input.ds, t[begin..j], &names, cx.diags);
                            for (names.items) |name_| try columns.append(cx.arena, s.input.ds.indexOf(name_).?);
                            j += 1;
                        }
                        s.aggregate = columns.items;
                        continue;
                    }
                    if (kw(t, j, "lackfit")) {
                        j += 1;
                        var options: gof.HlOptions = .{};
                        if (at(t, j, .lparen)) {
                            j += 1;
                            while (j < end and !at(t, j, .rparen)) {
                                const name_ = t[j];
                                if (!at(t, j + 1, .eq)) return invalid(cx, t, j);
                                j += 2;
                                const value = try integerOption(cx, t[0..end], &j);
                                if (eq(name_.text, "ngroups")) {
                                    if (value < 5) return invalid(cx, t, j - 1);
                                    options.groups = value;
                                } else if (eq(name_.text, "df")) options.df = value else if (eq(name_.text, "dfreduce")) options.reduce = value else return unsupported(cx, name_);
                            }
                            if (!at(t, j, .rparen)) return invalid(cx, t, j);
                            j += 1;
                        }
                        s.lackfit = options;
                        continue;
                    }
                    if (kw(t, j, "nofit")) {
                        s.nofit = true;
                        j += 1;
                        continue;
                    }
                    if (kw(t, j, "nooddsratio")) {
                        s.no_odds_ratio = true;
                        j += 1;
                        continue;
                    }
                    if (!at(t, j + 1, .eq)) return unsupported(cx, option);
                    j += 2;
                    if (eq(option.text, "scale")) {
                        if (kw(t, j, "none") or kw(t, j, "n")) {
                            s.scale = .none;
                            j += 1;
                        } else if (kw(t, j, "pearson") or kw(t, j, "p")) {
                            s.scale = .pearson;
                            j += 1;
                        } else if (kw(t, j, "deviance") or kw(t, j, "d")) {
                            s.scale = .deviance;
                            j += 1;
                        } else if (kw(t, j, "williams")) {
                            if (s.trials == null) return cx.diags.fail(error.ParseError, option.line, "PROC LOGISTIC: SCALE=WILLIAMS requires events/trials syntax", .{});
                            return unsupported(cx, t[j]);
                        } else {
                            s.scale_constant = try numericLiteral(cx, t[0..end], &j);
                            if (!(s.scale_constant > 0)) return invalid(cx, t, j - 1);
                            s.scale = .constant;
                        }
                    } else if (eq(option.text, "pprob")) s.pprob = try probabilityList(cx, t[0..end], &j) else if (eq(option.text, "pevent")) s.pevent = try probabilityList(cx, t[0..end], &j) else if (eq(option.text, "link")) {
                        if (kw(t, j, "logit")) s.link = .logit else if (kw(t, j, "probit") or kw(t, j, "normit")) s.link = .probit else if (kw(t, j, "cloglog")) s.link = .cloglog else if (kw(t, j, "alogit")) s.link = .alogit else return unsupported(cx, t[j]);
                        j += 1;
                    } else if (eq(option.text, "clodds")) {
                        s.clodds = try confidence(cx, t[0..end], &j);
                    } else if (eq(option.text, "gconv")) {
                        s.fit_options.gconv = try numericLiteral(cx, t[0..end], &j);
                        if (s.fit_options.gconv < 0) return invalid(cx, t, j - 1);
                        if (s.fit_options.gconv == 0) return proc.failGap(cx.diags, option.line, "PROC LOGISTIC: disabling GCONV is not implemented", .{});
                    } else return unsupported(cx, option);
                }
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
        } else if (kw(t, i, "roc")) {
            var j = i + 1;
            const label = if (at(t, j, .string)) blk: {
                const text = t[j].text;
                j += 1;
                break :blk text;
            } else try std.fmt.allocPrint(cx.arena, "ROC{d}", .{roc_models.items.len + 1});
            var request: roc.Model = .{ .label = label };
            if (kw(t, j, "pred") and at(t, j + 1, .eq)) {
                j += 2;
                request.pred = try variable(cx, s.input.ds, t[0..end], &j);
                if (j != end) return unsupported(cx, t[j]);
            } else {
                var variables: std.ArrayList(usize) = .empty;
                var roc_terms: std.ArrayList([]const usize) = .empty;
                var stop = j;
                while (stop < end and !at(t, stop, .slash)) stop += 1;
                if (stop != end) return unsupported(cx, t[stop]);
                try modelTerms(cx, s.input.ds, t[j..stop], &variables, &roc_terms);
                request.terms = roc_terms.items;
            }
            try roc_models.append(cx.arena, request);
        } else if (kw(t, i, "roccontrast")) {
            if (s.roc_contrast != null) return unsupported(cx, t[i]);
            var c: roc.Contrast = .{};
            var j = i + 1;
            if (at(t, j, .string)) {
                c.label = t[j].text;
                j += 1;
            }
            if (kw(t, j, "reference")) {
                j += 1;
                if (at(t, j, .lparen)) {
                    j += 1;
                    if (at(t, j, .string)) c.reference = t[j].text else if (kw(t, j, "model")) c.reference = "Model" else return invalid(cx, t, j);
                    j += 1;
                    if (!at(t, j, .rparen)) return invalid(cx, t, j);
                    j += 1;
                }
            } else if (kw(t, j, "adjacentpairs")) {
                c.kind = .adjacent;
                j += 1;
            } else if (j < end and !at(t, j, .slash)) {
                c.kind = .matrix;
                var values: std.ArrayList(f64) = .empty;
                var row_count: usize = 0;
                while (j < end and !at(t, j, .slash)) {
                    if (at(t, j, .comma)) {
                        if (row_count == 0 or (c.columns != 0 and row_count != c.columns)) return invalid(cx, t, j);
                        c.columns = row_count;
                        row_count = 0;
                        j += 1;
                        continue;
                    }
                    try values.append(cx.arena, try numericLiteral(cx, t[0..end], &j));
                    row_count += 1;
                }
                if (row_count == 0 or (c.columns != 0 and row_count != c.columns)) return invalid(cx, t, j);
                c.columns = row_count;
                c.coefficients = values.items;
            }
            if (at(t, j, .slash)) j += 1;
            while (j < end) {
                if (kw(t, j, "e")) {
                    c.display = true;
                    j += 1;
                } else if (kw(t, j, "estimate")) {
                    c.estimates = true;
                    j += 1;
                    if (at(t, j, .eq)) {
                        j += 1;
                        if (kw(t, j, "allpairs")) c.all_pairs = true else if (!kw(t, j, "rows")) return invalid(cx, t, j);
                        j += 1;
                    }
                } else return unsupported(cx, t[j]);
            }
            s.roc_contrast = c;
        } else if (kw(t, i, "units")) {
            // Only the last UNITS statement applies (S154 physical p.5903).
            units.clearRetainingCapacity();
            s.default_units = &.{};
            s.units_present = true;
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) {
                const target = try variable(cx, s.input.ds, t[0..end], &j);
                if (!at(t, j, .eq)) return invalid(cx, t, j);
                j += 1;
                var ignored = false;
                for (classes.items) |c| if (c.column == target) {
                    ignored = true;
                };
                const values = try unitValues(cx, t[0..end], &j, ignored);
                if (!ignored) {
                    for (units.items) |prior| if (prior.variable == target) return proc.failGap(cx.diags, t[i].line, "PROC LOGISTIC: repeated variables within one UNITS statement are not implemented", .{});
                    try units.append(cx.arena, .{ .variable = target, .values = values });
                }
            }
            if (at(t, j, .slash)) {
                j += 1;
                if (!kw(t, j, "default") or !at(t, j + 1, .eq)) return unsupported(cx, t[j]);
                j += 2;
                s.default_units = try unitValues(cx, t[0..end], &j, false);
            }
            if (j != end) return invalid(cx, t, j);
        } else if (kw(t, i, "oddsratio")) {
            var j = i + 1;
            var label: ?[]const u8 = null;
            if (at(t, j, .string)) {
                label = t[j].text;
                j += 1;
            }
            var request: OddsRequest = .{ .variable = try variable(cx, s.input.ds, t[0..end], &j), .label = label };
            if (j < end) {
                if (!at(t, j, .slash)) return invalid(cx, t, j);
                j += 1;
            }
            while (j < end) {
                const option = t[j];
                if (kw(t, j, "at")) {
                    if (!at(t, j + 1, .lparen)) return invalid(cx, t, j);
                    if (request.at_variable != null) return unsupported(cx, option);
                    j += 2;
                    request.at_variable = try variable(cx, s.input.ds, t[0..end], &j);
                    if (!at(t, j, .eq)) return invalid(cx, t, j);
                    j += 1;
                    var values: std.ArrayList(f64) = .empty;
                    while (j < end and !at(t, j, .rparen)) {
                        if (at(t, j, .comma)) {
                            j += 1;
                            continue;
                        }
                        if (at(t, j, .string) or at(t, j, .name)) return unsupported(cx, t[j]);
                        try values.append(cx.arena, try numericLiteral(cx, t[0..end], &j));
                    }
                    if (values.items.len == 0 or !at(t, j, .rparen)) return invalid(cx, t, j);
                    request.values = values.items;
                    j += 1;
                } else {
                    if (!at(t, j + 1, .eq)) return invalid(cx, t, j);
                    j += 2;
                    if (eq(option.text, "cl")) request.confidence = try confidence(cx, t[0..end], &j) else if (eq(option.text, "diff")) {
                        if (kw(t, j, "ref")) request.reference_only = true else if (kw(t, j, "all")) request.reference_only = false else return invalid(cx, t, j);
                        j += 1;
                    } else return unsupported(cx, option);
                }
            }
            try odds_requests.append(cx.arena, request);
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
    if (s.aggregate) |columns| if (columns.len == 0) {
        s.aggregate = effects.items;
    };
    s.model.terms = terms.items;
    s.odds_requests = odds_requests.items;
    s.roc_models = roc_models.items;
    s.units = units.items;
    s.units_present = units.items.len > 0 or s.default_units.len > 0;
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
    return renderCore(a, out, s, d, r, counts, null, null);
}
fn renderOrdinal(a: A, out: *std.ArrayList(u8), s: Spec, original: design.Design, fit: ordinal.Fit, counts: Counts) diag.Error!void {
    var d = original;
    const k = fit.levels - 1;
    d.p = fit.result.coefficients.len;
    const parameters = try a.alloc(design.Parameter, d.p);
    for (0..k) |j| parameters[j] = .{ .name = "Intercept", .level = if (k == 1) null else original.response.levels[j].label };
    @memcpy(parameters[k..], original.parameters[1..]);
    d.parameters = parameters;
    const effects = try a.dupe(design.Effect, original.effects);
    for (effects) |*effect| effect.start += k - 1;
    d.effects = effects;
    return renderCore(a, out, s, d, fit.result, counts, fit, null);
}
pub fn modelHeader(a: A, out: *std.ArrayList(u8), s: Spec, d: design.Design, counts: Counts, intercepts: usize) diag.Error!void {
    const ds = s.input.ds;
    const response_name = ds.columns.items[s.model.response].name;
    try out.print(a, "The LOGISTIC Procedure\n\nModel Information\n\nData Set {s}\n", .{try lists.datasetName(a, ds)});
    if (s.trials) |trials| {
        try out.print(a, "Response Variable (Events) {s}\nResponse Variable (Trials) {s}\n", .{ response_name, ds.columns.items[trials].name });
    } else try out.print(a, "Response Variable {s}\nNumber of Response Levels {d}\n", .{ response_name, d.response.levels.len });
    if (s.model.frequency) |ci| try out.print(a, "Frequency Variable {s}\n", .{ds.columns.items[ci].name});
    if (s.model.weight) |ci| try out.print(a, "Weight Variable {s}\n", .{ds.columns.items[ci].name});
    const link_name = switch (s.link) {
        .logit => "logit",
        .probit => "probit",
        .cloglog => "complementary log-log",
        .alogit => "logit",
    };
    const model_name = if (s.link == .alogit and intercepts > 1) "adjacent-category" else if (intercepts > 1) "cumulative" else "binary";
    try out.print(a, "Model {s} {s}\nOptimization Technique {s}\n\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ model_name, link_name, if (s.link == .alogit) "Newton-Raphson ridge" else "Fisher's scoring", counts.read, counts.used });
    if (s.trials != null or s.model.frequency != null) try out.print(a, "Sum of Frequencies Read {s}\nSum of Frequencies Used {s}\n", .{ try number(a, counts.frequency_read, "best12."), try number(a, counts.frequency_used, "best12.") });
    if (s.trials != null) {
        try out.print(a, "\nResponse Profile\n\nOrdered Binary Total\nValue Outcome Frequency\n\n1 Event {s}\n2 Nonevent {s}\n\n", .{ try number(a, counts.events, "best12."), try number(a, counts.frequency_used - counts.events, "best12.") });
    } else {
        try out.print(a, "\nResponse Profile\n\nOrdered Total\nValue {s} Frequency\n\n", .{response_name});
        for (d.response.levels, 0..) |level, i| try out.print(a, "{d} {s} {s}\n", .{ i + 1, level.label, try number(a, level.frequency, "best12.") });
        if (intercepts > 1) {
            try out.appendSlice(a, if (s.link == .alogit) "\nLogits modeled use the response level with the next higher Ordered Value as the reference category.\n\n" else "\nProbabilities modeled are cumulated over the lower Ordered Values.\n\n");
        } else try out.print(a, "\nProbability modeled is {s}={s}.\n\n", .{ response_name, d.response.levels[d.event_index].label });
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
}
fn renderCore(a: A, out: *std.ArrayList(u8), s: Spec, d: design.Design, r: kernel.Fit, counts: Counts, ordinal_result: ?ordinal.Fit, report: ?gof.Report) diag.Error!void {
    const ds = s.input.ds;
    const intercepts: usize = if (ordinal_result) |fit| fit.levels - 1 else 1;
    if (!s.roc_detail) try modelHeader(a, out, s, d, counts, intercepts);
    try out.print(a, "\nModel Convergence Status\n\nConvergence criterion (GCONV={s}) satisfied.\n\n", .{if (s.fit_options.gconv == 1e-8) "1E-8" else try number(a, s.fit_options.gconv, "best12.")});
    if (ordinal_result) |fit| if (fit.parallel_score) |score| {
        try out.print(a, "Score Test for the {s} Assumption\n\nChi-Square DF Pr > ChiSq\n\n{s} {d} {s}\n\n", .{ if (s.link == .logit) "Proportional Odds" else "Equal Slopes", try number(a, score, "10.4"), fit.parallel_df, try number(a, kernel.chiTail(score, fit.parallel_df), "pvalue6.4") });
    };
    if (report) |diagnostics| if (diagnostics.goodness) |statistics| try gof.renderGoodness(a, out, statistics);
    try out.appendSlice(a, "Model Fit Statistics\n\n");
    if (s.trials != null) try out.appendSlice(a, "Intercept and Covariates\nIntercept Log Full Log\nCriterion Only Likelihood Likelihood\n\n") else try out.appendSlice(a, "Intercept\nIntercept and\nCriterion Only Covariates\n\n");
    const null_deviance = -2 * r.null_log_likelihood;
    const deviance = -2 * r.log_likelihood;
    const nf: f64 = counts.frequency_used;
    const pf: f64 = @floatFromInt(d.p);
    const kf: f64 = @floatFromInt(intercepts);
    for ([_][]const u8{ "AIC", "SC", "-2 Log L" }, [_]f64{ null_deviance + 2 * kf, null_deviance + kf * @log(nf), null_deviance }, [_]f64{ deviance + 2 * pf, deviance + pf * @log(nf), deviance }) |name, null_value, full| {
        try out.print(a, "{s} {s} {s}", .{ name, try number(a, null_value, "10.3"), try number(a, full, "10.3") });
        if (s.trials != null) try out.print(a, " {s}", .{try number(a, full - 2 * counts.full_constant, "10.3")});
        try out.appendSlice(a, "\n");
    }
    if (d.p > intercepts) {
        try out.appendSlice(a, "\nTesting Global Null Hypothesis: BETA=0\n\nTest Chi-Square DF Pr > ChiSq\n\n");
        try testRow(a, out, "Likelihood Ratio", @max(0, 2 * (r.log_likelihood - r.null_log_likelihood)), d.p - intercepts);
        try testRow(a, out, "Score", r.score_test, d.p - intercepts);
        try testRow(a, out, "Wald", try kernel.blockWald(a, r, intercepts, d.p - intercepts), d.p - intercepts);
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
    if (s.clodds == null and !s.no_odds_ratio and (s.link == .logit or s.link == .alogit) and hasDefaultOdds(d)) {
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
    if (s.roc_detail) return;
    const assoc = if (intercepts > 1) try ordinal.association(a, d.y, r.probabilities, d.response.levels.len, d.frequencies) else blk: {
        var probabilities = r.probabilities;
        if (ordinal_result != null) {
            const event_probabilities = try a.alloc(f64, d.n);
            for (event_probabilities, 0..) |*value, i| value.* = r.probabilities[2 * i];
            probabilities = event_probabilities;
        }
        break :blk kernel.associationWeighted(d.y, probabilities, d.frequencies);
    };
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
    if (report) |diagnostics| try gof.renderExtras(a, out, diagnostics, ds.columns.items[s.model.response].name, d.response.levels[d.event_index].label, d.response.levels[1 - d.event_index].label);
}

pub const Analysis = struct { data: *Dataset, design: design.Design, fit: kernel.Fit, counts: Counts, ordinal_fit: ?ordinal.Fit = null, original_rows: []const usize = &.{}, report: ?gof.Report = null };
pub fn diagnosticOptions(s: Spec) bool {
    const scale_output = s.scale != .unspecified and (s.scale == .constant or s.trials != null or s.aggregate != null);
    return !s.nofit and (scale_output or s.ctable or s.lackfit != null);
}
fn diagnosticReport(cx: proc.ProcCtx, s: Spec, ds: *const Dataset, d: design.Design, fit: kernel.Fit, originals: []const usize) diag.Error!?gof.Report {
    if (!diagnosticOptions(s)) return null;
    var report: gof.Report = .{ .explicit_prior = s.pevent.len > 0 };
    const goodness_requested = s.scale != .unspecified and (s.scale == .constant or s.trials != null or s.aggregate != null);
    const classify = s.ctable and d.response.levels.len == 2;
    if (!goodness_requested and !classify and s.lackfit == null) return null;
    if (s.link != .logit or d.response.levels.len != 2) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: these diagnostics currently require binary LOGIT", .{});
    if (goodness_requested) {
        if (s.scale != .none) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: dispersion-adjusted inference tables are not implemented", .{});
        if (s.model.classes.len > 0) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: CLASS aggregation semantics for goodness-of-fit are not implemented", .{});
        if (s.trials != null and s.aggregate == null) if (s.model.frequency) |column| {
            for (d.source_rows) |source| if (@trunc(ds.rows.items[source][column].num) != 1) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: replicated grouped-trial goodness-of-fit without AGGREGATE is not implemented", .{});
        };
        const profiles = gof.profiles(cx.arena, ds, d, fit, originals, s.aggregate) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: weighted or heterogeneous-probability goodness-of-fit profiles are not implemented", .{});
        };
        report.goodness = gof.goodness(profiles, d.p, s.aggregate == null) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: goodness-of-fit profiles have insufficient degrees of freedom or invalid probabilities", .{});
        };
    }
    if (classify) {
        const predictions = gof.crossvalidated(cx.arena, d, fit) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: one-step classification is unavailable for this leverage/probability boundary", .{});
        };
        if (s.pprob.len == 0) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: default CTABLE cutpoints are not implemented; specify PPROB", .{});
        report.classification = try gof.classification(cx.arena, d, predictions, s.pprob, s.pevent);
    }
    if (s.lackfit) |options| {
        if (s.trials != null) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: grouped-trial Hosmer-Lemeshow partitioning is not implemented", .{});
        report.hosmer = gof.hosmer(cx.arena, d, fit, options) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: Hosmer-Lemeshow test requires at least three usable groups and valid degrees of freedom", .{});
        };
    }
    return report;
}
pub fn analyze(cx: proc.ProcCtx, s: Spec) diag.Error!Analysis {
    const a = cx.arena;
    const ds = s.input.ds;
    var model = s.model;
    model.allow_ordinal = true;
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
    var ordinal_fit: ?ordinal.Fit = null;
    const r = if (s.nofit) blk: {
        if (d.response.levels.len != 2) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: NOFIT for ordinal responses is not implemented", .{});
        const score = kernel.nullScore(a, d.x, d.y, d.p, d.frequencies, d.weights) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: NOFIT score is unavailable for this rank-deficient or nonfinite design", .{});
        };
        break :blk kernel.Fit{ .coefficients = &.{}, .covariance = &.{}, .probabilities = &.{}, .log_likelihood = score.log_likelihood, .null_log_likelihood = score.log_likelihood, .score_test = score.statistic, .iterations = 0 };
    } else if (d.response.levels.len > 2 or s.link != .logit) blk: {
        const responses = try a.alloc(usize, d.n);
        for (d.y, 0..) |y, i| responses[i] = if (d.response.levels.len == 2) (if (y == 1) 0 else 1) else @intFromFloat(y);
        ordinal_fit = ordinal.fit(a, s.link, d.x, responses, d.p, d.response.levels.len, d.frequencies, d.weights, s.fit_options) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: ordinal/link fitting failed (invalid probabilities, rank deficiency, or nonconvergence); no results emitted", .{});
        };
        break :blk ordinal_fit.?.result;
    } else kernel.fitWeighted(a, d.x, d.y, d.n, d.p, d.frequencies, d.weights, s.fit_options) catch |err| {
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
    const original_rows = try a.alloc(usize, d.n);
    for (d.source_rows, original_rows) |row, *original| original.* = origin.items[row];
    const report = try diagnosticReport(cx, s, work, d, r, original_rows);
    return .{ .data = work, .design = d, .fit = r, .counts = counts, .ordinal_fit = ordinal_fit, .original_rows = original_rows, .report = report };
}
fn oddsTable(a: A, out: *std.ArrayList(u8), rows: []const @import("logistic_plots.zig").Row, alpha: f64, method: odds_kernel.Confidence) diag.Error!void {
    try out.print(a, "\nOdds Ratio Estimates and {s} Confidence Intervals\n\nOdds Ratio Estimate {s}% Confidence Limits\n\n", .{ if (method == .pl) "Profile-Likelihood" else "Wald", try number(a, 100 * (1 - alpha), "best8.") });
    for (rows) |row| try out.print(a, "{s} {s} {s} {s}\n", .{ row.label, try odds(a, @exp(row.log_estimate)), try odds(a, @exp(row.log_lower)), try odds(a, @exp(row.log_upper)) });
}
fn requestRows(a: A, result: Analysis, s: Spec, request: OddsRequest, method: odds_kernel.Confidence) diag.Error![]const @import("logistic_plots.zig").Row {
    const contrasts = try odds_kernel.contrasts(a, result.data, result.design, result.fit.coefficients.len, request, unitsFor(s, request.variable));
    return if (method == .pl) odds_kernel.profile(a, result.design, result.fit, contrasts, s.alpha) else odds_kernel.wald(a, result.fit, contrasts, s.alpha);
}
fn unitTables(a: A, out: *std.ArrayList(u8), s: Spec, result: Analysis) diag.Error!void {
    if (!s.units_present and s.clodds == null) return;
    for ([_]odds_kernel.Confidence{ .wald, .pl }) |method| {
        if (s.clodds) |requested| {
            if (requested != .both and requested != method) continue;
        } else if (method != .wald) continue;
        var body: std.ArrayList(u8) = .empty;
        for (result.design.effects) |effect| {
            if (!defaultOdds(result.design, effect)) continue;
            if (effect.class_index != null) {
                if (s.clodds == null) continue;
                const rows = try requestRows(a, result, s, .{ .variable = effect.column, .reference_only = true }, method);
                for (rows) |row| {
                    try body.print(a, "{s} {s} {s} {s}\n", .{ row.label, try odds(a, @exp(row.log_estimate)), try odds(a, @exp(row.log_lower)), try odds(a, @exp(row.log_upper)) });
                }
            } else {
                const values = customizedUnits(s, effect.column) orelse (if (s.clodds != null) @as([]const f64, &.{1}) else continue);
                for (values) |unit| {
                    const contrasts = try odds_kernel.contrasts(a, result.data, result.design, result.fit.coefficients.len, .{ .variable = effect.column }, &.{unit});
                    const rows = if (method == .pl) try odds_kernel.profile(a, result.design, result.fit, contrasts, s.alpha) else try odds_kernel.wald(a, result.fit, contrasts, s.alpha);
                    const row = rows[0];
                    try body.print(a, "{s}", .{result.data.columns.items[effect.column].name});
                    if (s.units_present) try body.print(a, " {s}", .{try number(a, unit, "10.4")});
                    try body.print(a, " {s}", .{try odds(a, @exp(row.log_estimate))});
                    if (s.clodds != null) try body.print(a, " {s} {s}", .{ try odds(a, @exp(row.log_lower)), try odds(a, @exp(row.log_upper)) });
                    try body.appendSlice(a, "\n");
                }
            }
        }
        if (body.items.len == 0) continue;
        if (s.clodds == null) try out.appendSlice(a, "\nCustomized Odds Ratio Estimates\n\nEffect Unit Estimate\n\n") else {
            try out.print(a, "\nOdds Ratio Estimates and {s} Confidence Intervals\n\nEffect {s}Estimate {s}% Confidence Limits\n\n", .{ if (method == .pl) "Profile-Likelihood" else "Wald", if (s.units_present) "Unit " else "", try number(a, 100 * (1 - s.alpha), "best8.") });
        }
        try out.appendSlice(a, body.items);
    }
}
pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    const a = cx.arena;
    if (spec.nofit or spec.roc_plot or spec.roc_models.len > 0 or spec.roc_contrast != null) return @import("logistic_roc_proc.zig").run(cx, out, spec);
    if (spec.by_columns.len > 0 and spec.model.classes.len > 0) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: global CLASS levels across BY groups are not implemented", .{});
    const groups = try by.checkedSlices(a, spec.input.ds, spec.by_columns, spec.by_desc, spec.notsorted, cx.diags);
    for (groups, 0..) |group, group_index| {
        var ds = spec.input.ds.*;
        ds.rows = .empty;
        try ds.rows.appendSlice(a, group.rows);
        var s = spec;
        s.input.ds = &ds;
        const result = try analyze(cx, s);
        const graphics_active = !s.noprint and !s.plots_none and (if (cx.graphics) |g| (g.enabled == true or (g.enabled != false and g.cli_dir != null)) else false);
        if (graphics_active and (s.clodds != null or s.units_present)) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: plots for customized odds-ratio intervals are not implemented; use PLOTS=NONE", .{});
        var body: std.ArrayList(u8) = .empty;
        if ((s.link != .logit and s.link != .alogit) and (s.odds_requests.len > 0 or s.units_present or s.clodds != null)) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: odds ratios for nonlogit links are not implemented", .{});
        var profile_requested = s.clodds != null and s.clodds.? != .wald;
        for (s.odds_requests) |request| if (request.confidence != .wald) {
            profile_requested = true;
        };
        if (profile_requested and result.design.response.levels.len > 2) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: profile-likelihood intervals for ordinal models are not implemented", .{});
        if (!s.noprint) {
            if (result.ordinal_fit) |fit| try renderOrdinal(a, &body, s, result.design, fit, result.counts) else try renderCore(a, &body, s, result.design, result.fit, result.counts, null, result.report);
        }
        if (!s.noprint) unitTables(a, &body, s, result) catch |err| {
            if (err == error.OutOfMemory) return err;
            return proc.failGap(cx.diags, 0, "PROC LOGISTIC: customized odds-ratio computation failed; no results emitted", .{});
        };
        var by_text: std.ArrayList(u8) = .empty;
        if (s.by_columns.len > 0) try by.appendLine(a, &by_text, spec.input.ds, group.rep.?, s.by_columns);
        for (s.odds_requests, 0..) |request, request_index| {
            const plots = @import("logistic_plots.zig");
            const method: odds_kernel.Confidence = if (request.confidence == .pl) .pl else .wald;
            const rows = requestRows(a, result, s, request, method) catch |err| {
                if (err == error.OutOfMemory) return err;
                return proc.failGap(cx.diags, 0, "PROC LOGISTIC: unsupported or invalid ODDSRATIO contrast/profile; no results emitted", .{});
            };
            if (!s.noprint) try oddsTable(a, &body, rows, s.alpha, method);
            if (request.confidence == .both) {
                const profile_rows = requestRows(a, result, s, request, .pl) catch |err| {
                    if (err == error.OutOfMemory) return err;
                    return proc.failGap(cx.diags, 0, "PROC LOGISTIC: odds-ratio profile likelihood failed; no results emitted", .{});
                };
                if (!s.noprint) try oddsTable(a, &body, profile_rows, s.alpha, .pl);
            }
            if (!s.noprint and !s.plots_none) if (cx.graphics) |g| if (g.enabled == true or (g.enabled != false and g.cli_dir != null)) {
                const unit_values = unitsFor(s, request.variable);
                if (request.at_variable == null or request.label != null or request.confidence != .wald or unit_values.len != 1 or unit_values[0] != 1 or result.ordinal_fit != null) return proc.failGap(cx.diags, 0, "PROC LOGISTIC: plots for these odds-ratio options are not implemented; use PLOTS=NONE", .{});
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
    _ = @import("logistic_ordinal.zig");
    _ = @import("logistic_odds.zig");
    _ = @import("logistic_roc.zig");
    _ = @import("logistic_gof.zig");
    _ = @import("logistic_gof_tests.zig");
    _ = @import("logistic_roc_proc.zig");
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

test "LOGISTIC004 invalid ordering and unsupported ordinal reference options stay visible" {
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
    for ([_][]const u8{ "order=bogus", "event='missing' ref=first", "ref=first" }, [_]bool{ false, true, true }) |options, gap| {
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

test "LOGISTIC007 Cheese ordinal links preserve SAS reference estimates and score tests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "cheese");
    _ = try ds.addColumn("Additive", .num);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("freq", .num);
    // Public Example79.3, S154; same 36 frequency cells as the original.
    const frequencies = [_][9]f64{ .{ 0, 0, 1, 7, 8, 8, 19, 8, 1 }, .{ 6, 9, 12, 11, 7, 6, 1, 0, 0 }, .{ 1, 1, 6, 8, 23, 7, 5, 1, 0 }, .{ 0, 0, 0, 1, 3, 7, 14, 16, 11 } };
    for (frequencies, 0..) |row, i| for (row, 0..) |f, j| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .num = @floatFromInt(j + 1) }, .{ .num = f } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("cheese", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const coefficients = [_][11]f64{
        .{ -7.0801, -6.0249, -4.9254, -3.8568, -2.5205, -1.5685, -0.0669, 1.4930, 1.6128, 4.9645, 3.3227 },
        .{ -2.2262, -2.4238, -1.9852, -1.8164, -0.6908, -1.0433, 0.0322, 0.5160, 0.7172, 1.9838, 1.3826 },
    };
    const errors = [_][11]f64{
        .{ 0.5624, 0.4755, 0.4272, 0.3902, 0.3431, 0.3086, 0.2658, 0.3310, 0.3778, 0.4741, 0.4251 },
        .{ 0.5542, 0.4620, 0.3800, 0.3294, 0.3097, 0.2841, 0.2667, 0.3527, 0.1783, 0.2463, 0.2122 },
    };
    for ([_][]const u8{ "logit", "alogit" }, 0..) |link, model_index| {
        const source = try std.fmt.allocPrint(a, "proc logistic data=cheese; freq freq; class Additive(param=ref ref='4'); model y=Additive / link={s}{s}; run;", .{ link, if (model_index == 0) "" else " gconv=1e-12" });
        const result = try analyze(cx, try parse(cx, try lex.tokenize(a, source, &diagnostics)));
        const r = result.fit;
        try std.testing.expectEqual(@as(usize, 36), result.counts.read);
        try std.testing.expectEqual(@as(usize, 28), result.counts.used);
        try std.testing.expectEqual(@as(f64, 208), result.counts.frequency_used);
        try std.testing.expectEqual(@as(usize, 11), r.coefficients.len);
        // Cumulative uses default GCONV; adjacent requests documented1e-12
        // because default1e-8 stops at a different last printed digit. This
        // stricter path validates the model, not equality of the original run.
        // SAS reference numbers are printed to four decimal places; use half
        // the last displayed unit plus 1e-10 binary roundoff, not an empirical
        // margin. Deviances have three decimal places in the reference.
        for (coefficients[model_index], errors[model_index], r.coefficients, 0..) |b, se, actual, j| {
            try std.testing.expectApproxEqAbs(b, actual, 0.0000500001);
            try std.testing.expectApproxEqAbs(se, @sqrt(r.covariance[11 * j + j]), 0.0000500001);
        }
        try std.testing.expectApproxEqAbs(@as(f64, 859.802), -2 * r.null_log_likelihood, 0.0005000001);
        try std.testing.expectApproxEqAbs(([_]f64{ 711.348, 707.902 })[model_index], -2 * r.log_likelihood, 0.0005000001);
        try std.testing.expectApproxEqAbs(([_]f64{ 111.2670, 109.9790 })[model_index], r.score_test, 0.0000500001);
        try std.testing.expectApproxEqAbs(([_]f64{ 115.1504, 66.8401 })[model_index], try kernel.blockWald(a, r, 8, 3), 0.0000500001);
        if (model_index == 0) {
            // SAS Example79.3 covariance capture, persisted outside the oracle.
            // Each displayed decimal defines its own half-last-unit interval;
            // all121 entries are checked, preserving signs and row order.
            var tokens = std.mem.tokenizeAny(u8, @embedFile("testdata/logistic_cheese_covariance.txt"), " \r\n\t");
            for (r.covariance) |value| {
                const text = tokens.next().?;
                const decimal = std.mem.indexOfScalar(u8, text, '.').?;
                const digits: f64 = @floatFromInt(text.len - decimal - 1);
                try std.testing.expectApproxEqAbs(try std.fmt.parseFloat(f64, text), value, 0.5 * std.math.pow(f64, 10, -digits) + 1e-10);
            }
            try std.testing.expect(tokens.next() == null);
            try std.testing.expectEqual(@as(usize, 21), result.ordinal_fit.?.parallel_df);
            try std.testing.expectApproxEqAbs(@as(f64, 17.2866), result.ordinal_fit.?.parallel_score.?, 0.0000500001);
            // Reversing a cumulative-logit response reverses and negates the
            // cutpoints and negates common slopes. Covariance permutes; each
            // observation's complete probability vector reverses.
            const reversed_source = "proc logistic data=cheese; freq freq; class Additive(param=ref ref='4'); model y(descending)=Additive; run;";
            const reversed = try analyze(cx, try parse(cx, try lex.tokenize(a, reversed_source, &diagnostics)));
            for (0..11) |j| {
                const original_j = if (j < 8) 7 - j else j;
                try std.testing.expectApproxEqAbs(-r.coefficients[original_j], reversed.fit.coefficients[j], 1e-10);
                for (0..11) |h| {
                    const original_h = if (h < 8) 7 - h else h;
                    try std.testing.expectApproxEqAbs(r.covariance[11 * original_j + original_h], reversed.fit.covariance[11 * j + h], 1e-10);
                }
            }
            for (0..result.design.n) |i| for (0..9) |c| try std.testing.expectApproxEqAbs(r.probabilities[i * 9 + c], reversed.fit.probabilities[i * 9 + 8 - c], 1e-12);
        } else try std.testing.expect(result.ordinal_fit.?.parallel_score == null);
        const association = try ordinal.association(a, result.design.y, r.probabilities, 9, result.design.frequencies);
        try std.testing.expectEqual(@as(f64, 18635), association.pairs);
        try std.testing.expectApproxEqAbs(@as(f64, 67.6), 100 * association.concordant / association.pairs, 0.0500000001);
        try std.testing.expectApproxEqAbs(@as(f64, 9.8), 100 * association.discordant / association.pairs, 0.0500000001);
        for (0..result.design.n) |i| {
            var sum: f64 = 0;
            for (r.probabilities[i * 9 ..][0..9]) |probability| {
                try std.testing.expect(probability > 0 and probability < 1);
                sum += probability;
            }
            try std.testing.expectApproxEqAbs(@as(f64, 1), sum, 1e-14);
        }
        var output: std.ArrayList(u8) = .empty;
        try run(cx, &output, try lex.tokenize(a, source, &diagnostics));
        try std.testing.expect(std.mem.indexOf(u8, output.items, "Number of Response Levels 9") != null);
        try std.testing.expect(std.mem.indexOf(u8, output.items, if (model_index == 0) "Model cumulative logit" else "Model adjacent-category logit") != null);
    }
    try std.testing.expectEqualStrings("", try diagnostics.render());
}

test "LOGISTIC007 binary inverse links agree with analytic binomial MLE and grouped trials" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "linkdata");
    for ([_][]const u8{ "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 0, 0, 2 }, .{ 0, 1, 8 }, .{ 1, 0, 7 }, .{ 1, 1, 3 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var grouped = Dataset.init(a, "groupedlinks");
    for ([_][]const u8{ "x", "r", "n" }) |name| _ = try grouped.addColumn(name, .num);
    try grouped.appendRow(&.{ .{ .num = 0 }, .{ .num = 2 }, .{ .num = 10 } });
    try grouped.appendRow(&.{ .{ .num = 1 }, .{ .num = 7 }, .{ .num = 10 } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("linkdata", &ds);
    try lib.put("groupedlinks", &grouped);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    for ([_][]const u8{ "probit", "normit", "cloglog", "alogit" }) |link| {
        const alpha = if (eq(link, "cloglog")) @log(-@log(@as(f64, 0.8))) else if (eq(link, "alogit")) @log(@as(f64, 0.2 / 0.8)) else -0.8416212335729143;
        const upper = if (eq(link, "cloglog")) @log(-@log(@as(f64, 0.3))) else if (eq(link, "alogit")) @log(@as(f64, 0.7 / 0.3)) else 0.5244005127080409;
        const source = try std.fmt.allocPrint(a, "proc logistic data=linkdata; freq f; model y=x / link={s} gconv=1e-14; run;", .{link});
        const result = try analyze(cx, try parse(cx, try lex.tokenize(a, source, &d)));
        // GCONV1e-14 bounds remaining local coefficient error; tight1e-7
        // compared with an exact saturated-binomial solution, not SAS output.
        try std.testing.expectApproxEqAbs(alpha, result.fit.coefficients[0], 1e-7);
        try std.testing.expectApproxEqAbs(upper - alpha, result.fit.coefficients[1], 1e-7);
        const dens0 = if (eq(link, "cloglog")) -0.8 * @log(@as(f64, 0.8)) else if (eq(link, "alogit")) 0.2 * 0.8 else @exp(-alpha * alpha / 2) / @sqrt(2 * std.math.pi);
        const dens1 = if (eq(link, "cloglog")) -0.3 * @log(@as(f64, 0.3)) else if (eq(link, "alogit")) 0.7 * 0.3 else @exp(-upper * upper / 2) / @sqrt(2 * std.math.pi);
        const v0 = 0.2 * 0.8 / (10 * dens0 * dens0);
        const v1 = 0.7 * 0.3 / (10 * dens1 * dens1);
        for ([_]f64{ v0, -v0, -v0, v0 + v1 }, result.fit.covariance) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-7);
        const grouped_source = try std.fmt.allocPrint(a, "proc logistic data=groupedlinks; model r/n=x / gconv=1e-14 link={s}; run;", .{link});
        const grouped_fit = try analyze(cx, try parse(cx, try lex.tokenize(a, grouped_source, &d)));
        for (result.fit.coefficients, grouped_fit.fit.coefficients) |want, got| try std.testing.expectApproxEqAbs(want, got, 1e-12);
        var output: std.ArrayList(u8) = .empty;
        try run(cx, &output, try lex.tokenize(a, source, &d));
        if (!eq(link, "alogit")) try std.testing.expect(std.mem.indexOf(u8, output.items, "Odds Ratio Estimates") == null);
        try std.testing.expect(std.mem.indexOf(u8, output.items, "Probability modeled is y=0.") != null);
    }
    try std.testing.expectEqualStrings("", try d.render());
}

test "LOGISTIC007 link boundaries and unsupported options retain captured diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "links");
    _ = try ds.addColumn("y", .num);
    for ([_]f64{ 0, 0, 1 }) |value| try ds.appendRow(&.{.{ .num = value }});
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("links", &ds);
    diag.resetGap();
    defer diag.resetGap();
    for ([_][]const u8{ "gconv=-1", "gconv=0", "link=glogit" }, [_]u8{ 1, 2, 2 }) |options, rc| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        diag.resetGap();
        const source = try std.fmt.allocPrint(a, "proc logistic; model y= / {s}; run;", .{options});
        try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, source, &d)));
        try std.testing.expectEqual(rc, diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
}

// S154 physical p.5924 published four-race contingency table. Counts are
// public textbook data; odds and their log variances are exactly calculable.
fn oddsFixture(a: A) !Dataset {
    var ds = Dataset.init(a, "oddsdata");
    _ = try ds.addColumn("Race", .char);
    _ = try ds.addColumn("y", .num);
    _ = try ds.addColumn("f", .num);
    for ([_][]const u8{ "White", "Black", "Hispanic", "Other" }, [_]f64{ 5, 20, 15, 10 }, [_]f64{ 20, 10, 10, 10 }) |race, events, nonevents| {
        try ds.appendRow(&.{ .{ .str = race }, .{ .num = 1 }, .{ .num = events } });
        try ds.appendRow(&.{ .{ .str = race }, .{ .num = 0 }, .{ .num = nonevents } });
    }
    return ds;
}
test "LOGISTIC013 all CLASS pairs are coding invariant and reverse with the event" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try oddsFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("oddsdata", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var first_rows: ?[]const @import("logistic_plots.zig").Row = null;
    for ([_][]const u8{ "ref", "effect" }) |coding_| for ([_][]const u8{ "1", "0" }) |event| {
        const source = try std.fmt.allocPrint(a, "proc logistic; class Race(param={s} ref='White'); freq f; model y(event='{s}')=Race / gconv=1e-14; oddsratio Race; run;", .{ coding_, event });
        const spec = try parse(cx, try lex.tokenize(a, source, &d));
        const analysis = try analyze(cx, spec);
        const rows = try requestRows(a, analysis, spec, spec.odds_requests[0], .wald);
        try std.testing.expectEqual(@as(usize, 6), rows.len);
        // Pair order follows formatted levels Black,Hispanic,Other,White.
        const events = [_]f64{ 20, 15, 10, 5 };
        const nonevents = [_]f64{ 10, 10, 10, 20 };
        var index: usize = 0;
        for (0..4) |i| for (i + 1..4) |j| {
            const ratio = events[i] * nonevents[j] / (nonevents[i] * events[j]);
            const log_ratio = @log(ratio) * @as(f64, if (eq(event, "1")) 1 else -1);
            const variance = 1 / events[i] + 1 / nonevents[i] + 1 / events[j] + 1 / nonevents[j];
            const margin = 1.959963984540054 * @sqrt(variance);
            try std.testing.expectApproxEqAbs(log_ratio, rows[index].log_estimate, 1e-7);
            try std.testing.expectApproxEqAbs(log_ratio - margin, rows[index].log_lower, 1e-7);
            try std.testing.expectApproxEqAbs(log_ratio + margin, rows[index].log_upper, 1e-7);
            index += 1;
        };
        if (first_rows == null) first_rows = rows else if (eq(event, "0")) for (first_rows.?, rows) |original, reversed| {
            try std.testing.expectApproxEqAbs(-original.log_estimate, reversed.log_estimate, 1e-7);
            try std.testing.expectApproxEqAbs(-original.log_upper, reversed.log_lower, 1e-7);
            try std.testing.expectApproxEqAbs(-original.log_lower, reversed.log_upper, 1e-7);
        };
        const reference_rows = try requestRows(a, analysis, spec, .{ .variable = 0, .reference_only = true, .label = "Comparison" }, .wald);
        try std.testing.expectEqual(@as(usize, 3), reference_rows.len);
        for (reference_rows, [_][]const u8{ "Comparison", "Comparison 2", "Comparison 3" }) |row, label| try std.testing.expectEqualStrings(label, row.label);
        var output: std.ArrayList(u8) = .empty;
        try run(cx, &output, try lex.tokenize(a, source, &d));
        try std.testing.expect(std.mem.indexOf(u8, output.items, "Black vs White") != null);
    };
    try std.testing.expectEqualStrings("", try d.render());
}

fn ageOddsFixture(a: A) !Dataset {
    var ds = Dataset.init(a, "Data1");
    for ([_][]const u8{ "disease", "n", "age" }) |name| _ = try ds.addColumn(name, .num);
    for ([_]f64{ 0, 0, 0, 7, 6, 17 }, [_]f64{ 14, 20, 19, 18, 12, 17 }, [_]f64{ 25, 35, 45, 55, 65, 75 }) |events, n, age| try ds.appendRow(&.{ .{ .num = events }, .{ .num = n }, .{ .num = age } });
    return ds;
}
// Independent one-dimensional nuisance maximization: at fixed age slope,
// solve sum(events - n*expit(intercept+slope*age))=0 by monotone bisection.
// This does not use the production constrained design/QR optimizer.
fn ageProfileReference(ds: Dataset, slope: f64) f64 {
    var lo: f64 = -1000;
    var hi: f64 = 1000;
    for (0..120) |_| {
        const intercept = (lo + hi) / 2;
        var score: f64 = 0;
        for (ds.rows.items) |row| score += row[0].num - row[1].num / (1 + @exp(-(intercept + slope * row[2].num)));
        if (score > 0) lo = intercept else hi = intercept;
    }
    var ll: f64 = 0;
    for (ds.rows.items) |row| {
        const eta = (lo + hi) / 2 + slope * row[2].num;
        const log_denom = @max(0, eta) + std.math.log1p(@exp(-@abs(eta)));
        ll += row[0].num * eta - row[1].num * log_denom;
    }
    return ll;
}
test "LOGISTIC013 original numeric UNITS profile likelihood and negative-unit endpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try ageOddsFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("Data1", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = "proc logistic data=Data1; model disease/n=age / clodds=pl; units age=10 -10; oddsratio age / cl=both; run;";
    const spec = try parse(cx, try lex.tokenize(a, source, &d));
    const analysis = try analyze(cx, spec);
    const rows = try requestRows(a, analysis, spec, spec.odds_requests[0], .pl);
    try std.testing.expectEqual(@as(usize, 2), rows.len);
    // Original SAS capture displays three decimal places: half-last-unit
    // intervals are fixed before measuring the implementation.
    for ([_]f64{ 7.892, 3.881, 21.406 }, [_]f64{ @exp(rows[0].log_estimate), @exp(rows[0].log_lower), @exp(rows[0].log_upper) }) |expected, actual| try std.testing.expectApproxEqAbs(expected, actual, 0.0005000001);
    try std.testing.expectApproxEqAbs(-rows[0].log_estimate, rows[1].log_estimate, 1e-10);
    try std.testing.expectApproxEqAbs(-rows[0].log_upper, rows[1].log_lower, 1e-9);
    try std.testing.expectApproxEqAbs(-rows[0].log_lower, rows[1].log_upper, 1e-9);
    for ([_]f64{ rows[0].log_lower, rows[0].log_upper }) |endpoint| {
        const reference_ll = ageProfileReference(ds, endpoint / 10);
        // chi-square(1)0.95 is a published quantile. Root width1e-10 and
        // nuisance score tolerance1e-13 justify2e-7 on the LR statistic.
        try std.testing.expectApproxEqAbs(@as(f64, 3.841458820694124), 2 * (analysis.fit.log_likelihood - reference_ll), 2e-7);
    }
    const wald = try requestRows(a, analysis, spec, spec.odds_requests[0], .wald);
    const margin = 10 * 1.959963984540054 * @sqrt(analysis.fit.covariance[3]);
    try std.testing.expectApproxEqAbs(10 * analysis.fit.coefficients[1] - margin, wald[0].log_lower, 1e-12);
    try std.testing.expectApproxEqAbs(10 * analysis.fit.coefficients[1] + margin, wald[0].log_upper, 1e-12);
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, try lex.tokenize(a, source, &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "age 10.0000 7.892 3.881 21.406") != null);
    try std.testing.expect(std.mem.indexOf(u8, out.items, "age -10.0000") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, out.items, "Odds Ratio Estimates and Wald Confidence Intervals"));
    // One profile table is requested by MODEL CLODDS=PL, and another by
    // ODDSRATIO CL=BOTH; the former must not conceal a missing latter object.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, out.items, "Odds Ratio Estimates and Profile-Likelihood Confidence Intervals"));
    try std.testing.expectEqualStrings("", try d.render());
}

test "LOGISTIC013 units last statement default list ignored CLASS and diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try design.originalFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("binary", &ds);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const source = "proc logistic; class group(ref='A') / param=ref; model event(event='1')=group x; units x=10; units group=SD -SD 2*SD x=2 -2 / default=3; oddsratio 'Double change' x; oddsratio group / diff=ref; run;";
    const spec = try parse(cx, try lex.tokenize(a, source, &diagnostics));
    try std.testing.expectEqual(@as(usize, 1), spec.units.len);
    try std.testing.expectEqualSlices(f64, &.{ 2, -2 }, unitsFor(spec, 1));
    try std.testing.expectEqualSlices(f64, &.{3}, spec.default_units);
    const analysis = try analyze(cx, spec);
    const rows = try requestRows(a, analysis, spec, spec.odds_requests[0], .wald);
    try std.testing.expectEqualStrings("Double change", rows[0].label);
    try std.testing.expectEqualStrings("Double change 2", rows[1].label);
    try std.testing.expectApproxEqAbs(-rows[0].log_estimate, rows[1].log_estimate, 1e-12);
    try std.testing.expectApproxEqAbs(-rows[0].log_upper, rows[1].log_lower, 1e-12);
    const class_rows = try requestRows(a, analysis, spec, spec.odds_requests[1], .wald);
    try std.testing.expectEqual(@as(usize, 1), class_rows.len);
    try std.testing.expectEqualStrings("group B vs A", class_rows[0].label);
    const expected = analysis.fit.coefficients[1];
    try std.testing.expectApproxEqAbs(expected, class_rows[0].log_estimate, 1e-12); // DEFAULT=3 never scales CLASS
    var output: std.ArrayList(u8) = .empty;
    try run(cx, &output, try lex.tokenize(a, source, &diagnostics));
    try std.testing.expect(std.mem.indexOf(u8, output.items, "Customized Odds Ratio Estimates") != null);
    try std.testing.expect(std.mem.indexOf(u8, output.items, "x -2.0000") != null);
    diag.resetGap();
    defer diag.resetGap();
    for ([_][]const u8{ "units x=0;", "units x=SD;", "oddsratio x / plconv=0.01;" }, [_]u8{ 1, 2, 2 }) |statement, rc| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        const context: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        diag.resetGap();
        const program = try std.fmt.allocPrint(a, "proc logistic; model event=x; {s} run;", .{statement});
        try std.testing.expectError(error.ParseError, run(context, &out, try lex.tokenize(a, program, &d)));
        try std.testing.expectEqual(rc, diag.exitCode(diag.gapHit(), d.hasErrors()));
        try std.testing.expectEqual(@as(usize, 0), out.items.len);
    }
}

test "LOGISTIC013 ordinal odds use slope block and numeric interaction increments" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = Dataset.init(a, "ordinalodds");
    for ([_][]const u8{ "x", "y", "f" }) |name| _ = try ds.addColumn(name, .num);
    for ([_][3]f64{ .{ 0, 0, 2 }, .{ 0, 1, 3 }, .{ 0, 2, 5 }, .{ 1, 0, 5 }, .{ 1, 1, 3 }, .{ 1, 2, 2 } }) |row| try ds.appendRow(&.{ .{ .num = row[0] }, .{ .num = row[1] }, .{ .num = row[2] } });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("ordinalodds", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const program = "proc logistic; freq f; model y=x / gconv=1e-14; units x=2 -2; oddsratio x; run;";
    const spec = try parse(cx, try lex.tokenize(a, program, &d));
    const result = try analyze(cx, spec);
    const contrasts = try odds_kernel.contrasts(a, result.data, result.design, result.fit.coefficients.len, spec.odds_requests[0], unitsFor(spec, 0));
    try std.testing.expectEqualSlices(f64, &.{ 0, 0, 2 }, contrasts[0].coefficients);
    const rows = try requestRows(a, result, spec, spec.odds_requests[0], .wald);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 16)), rows[0].log_estimate, 1e-7);
    try std.testing.expectApproxEqAbs(-@log(@as(f64, 16)), rows[1].log_estimate, 1e-7);
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, try lex.tokenize(a, program, &d));
    try std.testing.expect(std.mem.indexOf(u8, out.items, "x Units=2") != null);
    var binary_data = try ingots(a);
    try lib.put("ingots", &binary_data);
    const interact = try parse(cx, try lex.tokenize(a, "proc logistic data=ingots; model r/n=Heat|Soak; units Heat=-2; oddsratio Heat / at(Soak=1 3); run;", &d));
    const fit = try analyze(cx, interact);
    const interaction_rows = try requestRows(a, fit, interact, interact.odds_requests[0], .wald);
    for (interaction_rows, [_]f64{ 1, 3 }) |row, soak| {
        const estimate = -2 * (fit.fit.coefficients[1] + soak * fit.fit.coefficients[3]);
        const variance = 4 * (fit.fit.covariance[5] + 2 * soak * fit.fit.covariance[7] + soak * soak * fit.fit.covariance[15]);
        try std.testing.expectApproxEqAbs(estimate, row.log_estimate, 1e-12);
        try std.testing.expectApproxEqAbs(estimate - 1.959963984540054 * @sqrt(variance), row.log_lower, 1e-12);
    }
}

test "LOGISTIC013 unsupported new odds graphics are visible and PLOTS NONE enables tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try ageOddsFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("Data1", &ds);
    diag.resetGap();
    defer diag.resetGap();
    for ([_]bool{ false, true }) |suppressed| {
        var d = diag.Diagnostics.init(a);
        var out: std.ArrayList(u8) = .empty;
        var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
        diag.resetGap();
        const program = try std.fmt.allocPrint(a, "proc logistic {s}; model disease/n=age / clodds=pl; units age=10; run;", .{if (suppressed) "plots=none" else ""});
        const tokens = try lex.tokenize(a, program, &d);
        if (suppressed) {
            try run(cx, &out, tokens);
            try std.testing.expect(!d.hasErrors());
            try std.testing.expect(std.mem.indexOf(u8, out.items, "age 10.0000 7.892 3.881 21.406") != null);
        } else {
            try std.testing.expectError(error.ParseError, run(cx, &out, tokens));
            try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
            try std.testing.expectEqual(@as(usize, 0), out.items.len);
        }
        try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
    }
    // Exercise the separate ODDSRATIO plot producer without UNITS/CLODDS.
    var d = diag.Diagnostics.init(a);
    var out: std.ArrayList(u8) = .empty;
    var graphics: proc.native_graphics.Session = .{ .arena = a, .io = std.testing.io, .diags = &d, .enabled = true };
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d, .graphics = &graphics };
    diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, "proc logistic; model disease/n=age; oddsratio age; run;", &d)));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), d.hasErrors()));
    try std.testing.expectEqual(@as(usize, 0), out.items.len);
    try std.testing.expectEqual(@as(usize, 0), graphics.prepared.items.len);
}

test "LOGISTIC013 multi-parameter CLASS profile agrees with independent two-binomial constraint" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try oddsFixture(a);
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("oddsdata", &ds);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const source = "proc logistic; class Race(param=effect ref='White'); freq f; model y(event='1')=Race / gconv=1e-14; oddsratio Race / diff=ref cl=pl; run;";
    const spec = try parse(cx, try lex.tokenize(a, source, &d));
    const result = try analyze(cx, spec);
    const rows = try requestRows(a, result, spec, spec.odds_requests[0], .pl);
    try std.testing.expectEqualStrings("Race Black vs White", rows[0].label);
    try std.testing.expectApproxEqAbs(@log(@as(f64, 8)), rows[0].log_estimate, 1e-7);
    for ([_]f64{ rows[0].log_lower, rows[0].log_upper }) |theta| {
        var lo: f64 = -100;
        var hi: f64 = 100;
        for (0..100) |_| {
            const intercept = (lo + hi) / 2;
            const white = 1 / (1 + @exp(-intercept));
            const black = 1 / (1 + @exp(-intercept - theta));
            if (25 - 25 * white - 30 * black > 0) lo = intercept else hi = intercept;
        }
        const white = 1 / (1 + @exp(-(lo + hi) / 2));
        const black = 1 / (1 + @exp(-(lo + hi) / 2 - theta));
        // The other two groups retain their empirical binomial MLEs.
        const ll = 5 * @log(white) + 20 * @log(1 - white) + 20 * @log(black) + 10 * @log(1 - black) + 15 * @log(@as(f64, 0.6)) + 10 * @log(@as(f64, 0.4)) + 20 * @log(@as(f64, 0.5));
        try std.testing.expectApproxEqAbs(@as(f64, 3.841458820694124), 2 * (result.fit.log_likelihood - ll), 2e-7);
    }
}

test "LOGISTIC013 grouped and fully expanded profile endpoints and conditional maxima agree" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var grouped = try ageOddsFixture(a);
    var individual = Dataset.init(a, "individual");
    _ = try individual.addColumn("response", .num);
    _ = try individual.addColumn("age", .num);
    for (grouped.rows.items) |row| for (0..@as(usize, @intFromFloat(row[1].num))) |trial| try individual.appendRow(&.{ .{ .num = if (@as(f64, @floatFromInt(trial)) < row[0].num) 1 else 0 }, row[2] });
    var lib = @import("../exec.zig").Library.init(a);
    try lib.put("Data1", &grouped);
    try lib.put("individual", &individual);
    var diagnostics = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diagnostics };
    const grouped_spec = try parse(cx, try lex.tokenize(a, "proc logistic data=Data1; model disease/n=age; units age=10; oddsratio age / cl=pl; run;", &diagnostics));
    const individual_spec = try parse(cx, try lex.tokenize(a, "proc logistic data=individual; model response(event='1')=age; units age=10; oddsratio age / cl=pl; run;", &diagnostics));
    const grouped_fit = try analyze(cx, grouped_spec);
    const individual_fit = try analyze(cx, individual_spec);
    try std.testing.expectEqual(@as(usize, 100), individual_fit.design.n);
    // Existing producer contract: each grouped row yields up to two binary
    // observations, with integer frequencies; it does not emit r/n as y.
    try std.testing.expect(grouped_fit.design.n < individual_fit.design.n);
    for (grouped_fit.design.y) |value| try std.testing.expect(value == 0 or value == 1);
    try std.testing.expectEqual(@as(f64, 100), grouped_fit.design.total_frequency);
    for ([_]f64{ 0.1, 0.2, 0.3 }) |slope| {
        const compact_ll = try odds_kernel.constrainedLikelihood(a, grouped_fit.design, grouped_fit.fit, &.{ 0, 1 }, slope);
        const expanded_ll = try odds_kernel.constrainedLikelihood(a, individual_fit.design, individual_fit.fit, &.{ 0, 1 }, slope);
        const reference_ll = ageProfileReference(grouped, slope);
        // Row expansion changes only floating summation; each result also
        // agrees with the independent scalar-intercept score root.
        try std.testing.expectApproxEqAbs(reference_ll, compact_ll, 1e-9);
        try std.testing.expectApproxEqAbs(reference_ll, expanded_ll, 1e-9);
    }
    const compact = (try requestRows(a, grouped_fit, grouped_spec, grouped_spec.odds_requests[0], .pl))[0];
    const expanded = (try requestRows(a, individual_fit, individual_spec, individual_spec.odds_requests[0], .pl))[0];
    try std.testing.expectApproxEqAbs(compact.log_estimate, expanded.log_estimate, 1e-8);
    try std.testing.expectApproxEqAbs(compact.log_lower, expanded.log_lower, 1e-8);
    try std.testing.expectApproxEqAbs(compact.log_upper, expanded.log_upper, 1e-8);
    var fractional_design = grouped_fit.design;
    const responses = try a.dupe(f64, fractional_design.y);
    responses[0] = 0.5;
    fractional_design.y = responses;
    try std.testing.expectError(error.ExecError, odds_kernel.constrainedLikelihood(a, fractional_design, grouped_fit.fit, &.{ 0, 1 }, 0.2));
}
