//! GLM declarations and variable roles. S154 physical pp.4058–4072, 4106, 4160.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const lists = @import("variable_lists.zig");
const by = @import("by_groups.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Order = @import("class_levels.zig").Order;
pub const Effect = struct { name: []const u8, variables: []const usize };
pub const Spec = struct {
    input: proc.ProcInput,
    hov: ?@import("glm_hov.zig").Request = null,
    random: ?@import("glm_random.zig").Request = null,
    estimates: []const @import("glm_estimate.zig").Request = &.{},
    lsmeans: []const @import("glm_lsmeans.zig").Request = &.{},
    classes: []const usize = &.{},
    responses: []const usize,
    effects: []const Effect,
    by: []const usize = &.{},
    descending: []const bool = &.{},
    notsorted: bool = false,
    freq: ?usize = null,
    weight: ?usize = null,
    ids: []const usize = &.{},
    absorb: []const usize = &.{},
    alpha: f64 = 0.05,
    singular: f64 = 1e-9,
    namelen: usize = 20,
    order: Order = .formatted,
    manova: bool = false,
    multipass: bool = false,
    noprint: bool = false,
    plots_none: bool = false,
    intercept: bool = true,
    /// Explicit SS requests replace the default Type I + Type III tables.
    ss1: bool = false,
    ss2: bool = false,
    ss3: bool = false,
    ss4: bool = false,

    pub fn defaultSumsOfSquares(self: Spec) bool {
        return !self.ss1 and !self.ss2 and !self.ss3 and !self.ss4;
    }
};
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn real(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.* + 1, .eq) or !at(t, i.* + 2, .number)) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC GLM: expected numeric option value", .{});
    const v = std.fmt.parseFloat(f64, t[i.* + 2].text) catch return cx.diags.fail(error.ParseError, t[i.*].line, "PROC GLM: invalid numeric value", .{});
    i.* += 3;
    if (!std.math.isFinite(v) or !(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, t[i.* - 1].line, "PROC GLM: option must be between zero and one", .{});
    return v;
}
fn columns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, numeric: bool) diag.Error![]const usize {
    var names: std.ArrayList([]const u8) = .empty;
    try lists.append(cx.arena, ds, t, &names, cx.diags);
    var result: std.ArrayList(usize) = .empty;
    for (names.items) |name| {
        const ci = ds.indexOf(name) orelse return cx.diags.fail(error.ParseError, if (t.len > 0) t[0].line else 0, "PROC GLM: variable {s} not found", .{name});
        if (numeric and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, if (t.len > 0) t[0].line else 0, "PROC GLM: variable {s} must be numeric", .{name});
        if (std.mem.indexOfScalar(usize, result.items, ci) == null) try result.append(cx.arena, ci);
    }
    return result.items;
}
fn unsupported(cx: proc.ProcCtx, t: lex.Token, known: []const []const u8) diag.Error {
    for (known) |name| if (eq(name, t.text)) return proc.failGap(cx.diags, t.line, "PROC GLM: {s} is not implemented", .{t.text});
    return cx.diags.fail(error.ParseError, t.line, "PROC GLM: invalid statement or option {s}", .{t.text});
}
pub fn parse(cx: proc.ProcCtx, tokens: []const lex.Token) diag.Error!Spec {
    var i: usize = 2;
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var result: Spec = .{ .input = undefined, .responses = &.{}, .effects = &.{} };
    while (i < tokens.len and !at(tokens, i, .semicolon) and !at(tokens, i, .eof)) {
        if (kw(tokens, i, "data")) {
            if (name != null) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: repeated DATA= is not implemented", .{});
            if (!at(tokens, i + 1, .eq) or !at(tokens, i + 2, .name)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: DATA= requires a dataset", .{});
            name = tokens[i + 2].text;
            i += 3;
            if (at(tokens, i, .dot)) {
                if (!at(tokens, i + 1, .name)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: expected member name", .{});
                qualified = i - 1;
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, tokens[i + 1].text });
                i += 2;
            }
            if (at(tokens, i, .lparen)) i = proc.skipParen(tokens, i);
        } else if (kw(tokens, i, "alpha")) result.alpha = try real(cx, tokens, &i) else if (kw(tokens, i, "namelen")) {
            if (!at(tokens, i + 1, .eq) or !at(tokens, i + 2, .number)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: NAMELEN= requires an integer", .{});
            result.namelen = std.fmt.parseInt(usize, tokens[i + 2].text, 10) catch return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: invalid NAMELEN", .{});
            if (result.namelen < 20 or result.namelen > 200) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: NAMELEN must be 20 through 200", .{});
            i += 3;
        } else if (kw(tokens, i, "order")) {
            if (!at(tokens, i + 1, .eq) or !at(tokens, i + 2, .name)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: ORDER= requires a name", .{});
            const v = tokens[i + 2].text;
            result.order = if (eq(v, "data")) .data else if (eq(v, "formatted")) .formatted else if (eq(v, "freq")) .freq else if (eq(v, "internal")) .internal else return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: invalid ORDER value", .{});
            i += 3;
        } else if (kw(tokens, i, "plots")) {
            if (!at(tokens, i + 1, .eq) or !kw(tokens, i + 2, "none")) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: explicit PLOTS requests other than NONE are not implemented", .{});
            result.plots_none = true;
            i += 3;
        } else if (kw(tokens, i, "manova")) {
            result.manova = true;
            i += 1;
        } else if (kw(tokens, i, "multipass")) {
            // Input is already an immutable in-memory view; no utility file is used.
            result.multipass = true;
            i += 1;
        } else if (kw(tokens, i, "noprint")) {
            result.noprint = true;
            i += 1;
        } else return unsupported(cx, tokens[i], &.{"outstat"});
    }
    if (!at(tokens, i, .semicolon)) return cx.diags.fail(error.ParseError, 0, "PROC GLM: expected semicolon", .{});
    const raw = (if (name) |nm| cx.lib.find(nm) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ExecError, 0, "PROC GLM: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |start| {
        try folded.appendSlice(cx.arena, tokens[0..start]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = tokens[start].line });
        try folded.appendSlice(cx.arena, tokens[start + 3 ..]);
    }
    result.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else tokens, cx.diags);
    const ds = result.input.ds;
    var bys: by.Statements = .{};
    var class_seen = false;
    var model_seen = false;
    var ended = false;
    var effects: std.ArrayList(Effect) = .empty;
    var estimates: std.ArrayList(@import("glm_estimate.zig").Request) = .empty;
    var lsmeans: std.ArrayList(@import("glm_lsmeans.zig").Request) = .empty;
    i += 1;
    while (i < tokens.len and !at(tokens, i, .eof)) {
        if (at(tokens, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < tokens.len and !at(tokens, end, .semicolon) and !at(tokens, end, .eof)) end += 1;
        if (!at(tokens, end, .semicolon)) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: expected semicolon", .{});
        if (kw(tokens, i, "run") or kw(tokens, i, "quit")) {
            if (end != i + 1) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: invalid execution boundary", .{});
            ended = true;
        } else if (ended and (kw(tokens, i, "by") or kw(tokens, i, "freq") or kw(tokens, i, "id") or kw(tokens, i, "weight") or kw(tokens, i, "absorb"))) {
            // These declarations after the first RUN are explicitly ignored by SAS.
        } else if (ended) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: interactive continuation is not implemented", .{}) else if (kw(tokens, i, "class")) {
            if (model_seen) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: CLASS must precede MODEL", .{});
            if (class_seen) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: repeated CLASS statements are not implemented", .{});
            for (tokens[i + 1 .. end]) |t| if (t.tag == .lparen or t.tag == .slash) return proc.failGap(cx.diags, t.line, "PROC GLM: CLASS reference/format options are not implemented", .{});
            result.classes = try columns(cx, ds, tokens[i + 1 .. end], false);
            if (result.classes.len == 0) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: CLASS requires variables", .{});
            class_seen = true;
        } else if (kw(tokens, i, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: only one MODEL statement is allowed", .{});
            model_seen = true;
            var equal = i + 1;
            while (equal < end and !at(tokens, equal, .eq)) equal += 1;
            if (equal == end) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: MODEL requires =", .{});
            result.responses = try columns(cx, ds, tokens[i + 1 .. equal], true);
            if (result.responses.len == 0) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: MODEL requires a response", .{});
            var j = equal + 1;
            while (j < end and !at(tokens, j, .slash)) {
                const start = j;
                var variables: std.ArrayList(usize) = .empty;
                var label: std.ArrayList(u8) = .empty;
                while (true) {
                    if (!at(tokens, j, .name)) return proc.failGap(cx.diags, tokens[j].line, "PROC GLM: this model-effect syntax is not implemented", .{});
                    const ci = ds.indexOf(tokens[j].text) orelse return cx.diags.fail(error.ParseError, tokens[j].line, "PROC GLM: variable {s} not found", .{tokens[j].text});
                    if (ds.columns.items[ci].type == .char and std.mem.indexOfScalar(usize, result.classes, ci) == null) return cx.diags.fail(error.ParseError, tokens[j].line, "PROC GLM: character predictor {s} must be in CLASS", .{tokens[j].text});
                    if (variables.items.len > 0) try label.append(cx.arena, '*');
                    try label.appendSlice(cx.arena, ds.columns.items[ci].name);
                    try variables.append(cx.arena, ci);
                    j += 1;
                    if (!at(tokens, j, .star)) break;
                    j += 1;
                    if (j >= end) return cx.diags.fail(error.ParseError, tokens[start].line, "PROC GLM: incomplete interaction", .{});
                }
                if (at(tokens, j, .pipe)) {
                    // The supported bar operands are individual variables. Keep
                    // crossed/nested bar operands loud until their grammar lands.
                    if (variables.items.len != 1) return proc.failGap(cx.diags, tokens[start].line, "PROC GLM: compound bar operands are not implemented", .{});
                    while (at(tokens, j, .pipe)) {
                        j += 1;
                        if (j >= end or !at(tokens, j, .name)) return cx.diags.fail(error.ParseError, tokens[start].line, "PROC GLM: bar requires a variable on both sides", .{});
                        const ci = ds.indexOf(tokens[j].text) orelse return cx.diags.fail(error.ParseError, tokens[j].line, "PROC GLM: variable {s} not found", .{tokens[j].text});
                        if (ds.columns.items[ci].type == .char and std.mem.indexOfScalar(usize, result.classes, ci) == null) return cx.diags.fail(error.ParseError, tokens[j].line, "PROC GLM: character predictor {s} must be in CLASS", .{tokens[j].text});
                        if (std.mem.indexOfScalar(usize, variables.items, ci) == null) try variables.append(cx.arena, ci);
                        j += 1;
                        if (at(tokens, j, .star) or at(tokens, j, .lparen)) return proc.failGap(cx.diags, tokens[start].line, "PROC GLM: compound bar operands are not implemented", .{});
                    }
                    var degree = variables.items.len;
                    if (at(tokens, j, .at)) {
                        j += 1;
                        if (j >= end or !at(tokens, j, .number)) return cx.diags.fail(error.ParseError, tokens[start].line, "PROC GLM: bar degree requires a positive integer", .{});
                        degree = std.fmt.parseInt(usize, tokens[j].text, 10) catch return cx.diags.fail(error.ParseError, tokens[j].line, "PROC GLM: invalid bar degree", .{});
                        if (degree == 0) return cx.diags.fail(error.ParseError, tokens[j].line, "PROC GLM: bar degree must be positive", .{});
                        j += 1;
                    }
                    try expandBar(cx, ds, variables.items, degree, result.namelen, tokens[start].line, &effects);
                    continue;
                }
                for (effects.items) |e| if (std.mem.eql(usize, e.variables, variables.items)) return proc.failGap(cx.diags, tokens[start].line, "PROC GLM: duplicate effects are not implemented", .{});
                try effects.append(cx.arena, .{ .name = label.items[0..@min(label.items.len, result.namelen)], .variables = variables.items });
            }
            if (at(tokens, j, .slash)) j += 1;
            while (j < end) {
                if (kw(tokens, j, "noint")) {
                    result.intercept = false;
                    j += 1;
                } else if (kw(tokens, j, "ss1")) {
                    result.ss1 = true;
                    j += 1;
                } else if (kw(tokens, j, "ss2")) {
                    result.ss2 = true;
                    j += 1;
                } else if (kw(tokens, j, "ss3")) {
                    result.ss3 = true;
                    j += 1;
                } else if (kw(tokens, j, "ss4")) {
                    result.ss4 = true;
                    j += 1;
                } else if (kw(tokens, j, "alpha")) result.alpha = try real(cx, tokens[0..end], &j) else if (kw(tokens, j, "singular")) result.singular = try real(cx, tokens[0..end], &j) else return unsupported(cx, tokens[j], &.{ "solution", "e", "e1", "e2", "e3", "e4", "clparm", "cli", "clm", "p", "r", "nouni", "intercept", "tolerance", "inverse", "xpx", "effectsize" });
            }
        } else if (kw(tokens, i, "means")) {
            if (!model_seen) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: MEANS must follow MODEL", .{});
            if (result.hov != null) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: repeated MEANS statements are not implemented", .{});
            result.hov = try @import("glm_hov.zig").read(cx, tokens[i..end], result);
        } else if (kw(tokens, i, "random")) {
            if (!model_seen) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: RANDOM must follow MODEL", .{});
            if (result.random != null) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: repeated RANDOM declarations are not implemented", .{});
            result.random = try @import("glm_random.zig").read(cx, tokens[i..end], result, effects.items);
        } else if (kw(tokens, i, "estimate")) {
            if (!model_seen) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: ESTIMATE must follow MODEL", .{});
            try estimates.append(cx.arena, try @import("glm_estimate.zig").read(cx, tokens[i..end], result, effects.items));
        } else if (kw(tokens, i, "lsmeans")) {
            if (!model_seen) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: LSMEANS must follow MODEL", .{});
            try @import("glm_lsmeans.zig").read(cx, tokens[i..end], result, effects.items, &lsmeans);
        } else if (kw(tokens, i, "absorb")) {
            if (result.absorb.len > 0) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: repeated ABSORB declarations are not implemented", .{});
            result.absorb = try columns(cx, ds, tokens[i + 1 .. end], false);
            if (result.absorb.len == 0) return cx.diags.fail(error.ParseError, tokens[i].line, "PROC GLM: ABSORB requires variables", .{});
        } else if (kw(tokens, i, "by")) {
            try bys.read(cx.arena, tokens, &i);
        } else if (kw(tokens, i, "id")) {
            result.ids = try columns(cx, ds, tokens[i + 1 .. end], false);
        } else if (kw(tokens, i, "freq") or kw(tokens, i, "weight")) {
            const role = if (kw(tokens, i, "freq")) &result.freq else &result.weight;
            if (role.* != null) return proc.failGap(cx.diags, tokens[i].line, "PROC GLM: repeated frequency/weight declarations are not implemented", .{});
            const token = try lists.roleVariable(tokens[0..end], i + 1, false, cx.diags);
            role.* = (try columns(cx, ds, &.{token}, true))[0];
        } else if (!kw(tokens, i, "where")) return unsupported(cx, tokens[i], &.{ "absorb", "contrast", "estimate", "lsmeans", "means", "manova", "repeated", "random", "test", "output", "store", "code" });
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC GLM: MODEL statement required", .{});
    result.effects = effects.items;
    result.lsmeans = lsmeans.items;
    result.estimates = estimates.items;
    if (result.absorb.len > 0) {
        result.intercept = true; // MODEL NOINT is ignored with ABSORB (S154 p.4094).
        for (result.effects) |effect| for (effect.variables) |ci| {
            if (std.mem.indexOfScalar(usize, result.absorb, ci) != null) return proc.failGap(cx.diags, 0, "PROC GLM: an ABSORB variable also used in MODEL is not implemented", .{});
        };
    }
    const parsed = try bys.resolve(cx.arena, ds, cx.diags);
    const indices = try cx.arena.alloc(usize, parsed.names.len);
    for (parsed.names, 0..) |nm, k| indices[k] = ds.indexOf(nm).?;
    result.by = indices;
    result.descending = parsed.desc;
    result.notsorted = parsed.notsorted;
    return result;
}

/// S154 physical p.4109: left-to-right subsets A,B,A*B,C,A*C,B*C,A*B*C.
/// Uses the same bounded subset enumeration as GLMMOD's effect expansion.
/// This operates on parsed variable IDs, never on program source text.
fn expandBar(cx: proc.ProcCtx, ds: *const Dataset, variables: []const usize, degree: usize, namelen: usize, line: usize, effects: *std.ArrayList(Effect)) diag.Error!void {
    // ponytail: match GLMMOD's sixteen-variable cap on exponential expansion.
    if (variables.len > 16) return proc.failGap(cx.diags, line, "PROC GLM: bar expansion beyond sixteen variables is not implemented", .{});
    const limit = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(variables.len));
    for (1..limit) |mask| {
        if (@popCount(mask) > degree) continue;
        var factors: std.ArrayList(usize) = .empty;
        var name: std.ArrayList(u8) = .empty;
        for (variables, 0..) |ci, k| if (mask & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k))) != 0) {
            if (factors.items.len > 0) try name.append(cx.arena, '*');
            try factors.append(cx.arena, ci);
            try name.appendSlice(cx.arena, ds.columns.items[ci].name);
        };
        var duplicate = false;
        for (effects.items) |effect| {
            if (effect.variables.len != factors.items.len) continue;
            var same = true;
            for (factors.items) |ci| if (std.mem.indexOfScalar(usize, effect.variables, ci) == null) {
                same = false;
            };
            if (same) {
                duplicate = true;
                break;
            }
        }
        if (!duplicate) try effects.append(cx.arena, .{ .name = name.items[0..@min(name.items.len, namelen)], .variables = factors.items });
    }
}

test {
    _ = @import("glm_ss1_tests.zig");
    _ = @import("glm_ss2_tests.zig");
    _ = @import("glm_ss34_tests.zig");
}
