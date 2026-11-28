//! PROC GLIMMIX declarations, variable roles and observation selection
//! (STAT-GLIMMIX-001). S154 physical pp.3703-3731 (PROC statement, BY),
//! 3750-3751 (FREQ, ID), 3817 (WEIGHT), 3876 (missing level combinations).
//! This file owns the parameter objects and the per-BY-group input interface.
//! Estimation, MODEL/RANDOM option semantics and every displayed table belong
//! to later tickets: `run` therefore always ends in a visible D-009 gap and
//! never writes listing output.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const Value = @import("../value.zig").Value;
const Dataset = @import("../dataset.zig").Dataset;
const selection = @import("data_selection.zig");
const groups = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const classes = @import("class_levels.zig");
const nlo = @import("nloptions.zig");
const eq = std.ascii.eqlIgnoreCase;
/// RSPL estimation kernel (STAT-GLIMMIX-002). ponytail: not yet called from
/// `run` -- the listing needs SAS's dual quasi-Newton iteration history, which
/// the kernel does not reproduce, so every step still ends in the D-009 gap.
pub const estimation = @import("glimmix_fit.zig");
/// Fixed-effects model structure (STAT-GLIMMIX-003): non-full-rank X, aliased
/// columns, full-rank reduction and contrast coefficient resolution.
pub const design = @import("glimmix_design.zig");
test {
    _ = estimation;
    _ = design;
}

pub const Method = enum { rspl, mspl, rmpl, mmpl, laplace, quad };
pub const InfoCrit = enum { none, pq, q };
/// Valueless PROC statement options (Table 52.1); aliases share one flag.
pub const Flag = enum { asycorr, asycov, cholesky, exphessian, gradient, hessian, initglm, itdetails, list, nobound, nobsdetail, noclprint, nofit, noinitglm, noitprint, noprofile, noreml, oddsratio, profile, scoremod };
const flag_names = [_]struct { []const u8, Flag }{
    .{ "asycorr", .asycorr },       .{ "asycov", .asycov },       .{ "cholesky", .cholesky },   .{ "chol", .cholesky },
    .{ "exphessian", .exphessian }, .{ "gradient", .gradient },   .{ "hessian", .hessian },     .{ "initglm", .initglm },
    .{ "startglm", .initglm },      .{ "itdetails", .itdetails }, .{ "list", .list },           .{ "nobound", .nobound },
    .{ "nobsdetail", .nobsdetail }, .{ "nofit", .nofit },         .{ "noinitglm", .noinitglm }, .{ "noitprint", .noitprint },
    .{ "noprofile", .noprofile },   .{ "noreml", .noreml },       .{ "oddsratio", .oddsratio }, .{ "or", .oddsratio },
    .{ "profile", .profile },       .{ "scoremod", .scoremod },
};
/// Machine epsilon as SAS reports it; the reference log prints the default
/// PCONV (1E8 times epsilon, p.3711) as 1.11022E-8.
pub const machine_epsilon: f64 = std.math.floatEps(f64) / 2.0;
pub const Options = struct {
    method: Method = .rspl,
    order: classes.Order = .formatted,
    flags: std.EnumSet(Flag) = .initEmpty(),
    /// NOCLPRINT=number: list only levels of variables with fewer levels.
    noclprint_limit: ?usize = null,
    infocrit: ?InfoCrit = null, // null: model-dependent default
    namelen: usize = 20,
    /// null: MAXITER= of NLOPTIONS when given, else 20 (see maxOptimizations).
    maxopt: ?usize = null,
    inititer: usize = 4,
    scoring: usize = 0,
    abspconv: f64 = 0,
    pconv: f64 = 1e8 * machine_epsilon,
    fdigits: ?f64 = null, // default -log10(epsilon)
    singchol: f64 = 1e4 * machine_epsilon,
    singres: f64 = 1e4 * machine_epsilon,
    singular: f64 = 1e4 * machine_epsilon,

    pub fn has(o: Options, flag: Flag) bool {
        return o.flags.contains(flag);
    }
};
pub const Model = struct {
    response: usize,
    /// events/trials syntax: `response` holds events and this the trials.
    trials: ?usize = null,
    /// Tokens after the option slash; interpreted by the estimation tickets.
    option_tokens: []const lex.Token = &.{},
    /// MODEL effects in statement order (p.3875); see glimmix_design.zig.
    effects: []const design.Effect = &.{},
    /// false under the MODEL NOINT option (p.3875).
    intercept: bool = true,
    line: usize,
};
pub const Spec = struct {
    input: proc.ProcInput,
    options: Options,
    roles: selection.Roles,
    by_desc: []const bool,
    notsorted: bool,
    /// null: copy all input variables to a future OUTPUT OUT=; else only these.
    id_columns: ?[]const usize,
    class_columns: []const usize,
    model: Model,
    /// Listwise-missing columns: every CLASS variable (p.413), the response(s),
    /// MODEL effect variables and RANDOM effect/SUBJECT=/GROUP= variables.
    required: []const usize,
    nloptions: ?nlo.Options,
    line: usize,

    pub fn maxOptimizations(s: Spec) usize {
        if (s.options.maxopt) |n| return n;
        if (s.nloptions) |o| if (o.max_iterations) |n| return n;
        return 20;
    }
};
pub const Group = struct {
    raw: selection.View,
    /// Used observations; frequency holds the truncated FREQ value.
    selected: selection.View,
    read_count: usize,
    used_count: usize,
    /// Sum of truncated frequencies over used observations.
    frequency_used: f64,
    /// One entry per Spec.class_columns, levels built from used observations.
    class_levels: []const classes.Levels,
};

fn is(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(cx: proc.ProcCtx, t: lex.Token) diag.Error {
    return cx.diags.fail(error.ParseError, t.line, "PROC GLIMMIX: unexpected token {s}", .{t.text});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC GLIMMIX: " ++ fmt, args);
}
fn numeric(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    const at = @min(i.*, t.len - 1);
    var sign: f64 = 1;
    if (is(t, i.*, .minus) or is(t, i.*, .plus)) {
        if (is(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!is(t, i.*, .number)) return bad(cx, t[at]);
    const n = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return bad(cx, t[i.*]));
    i.* += 1;
    if (!std.math.isFinite(n)) return bad(cx, t[at]);
    return n;
}
fn count(cx: proc.ProcCtx, name: lex.Token, n: f64) diag.Error!usize {
    if (n < 0 or n != @trunc(n) or n > 1e9) return cx.diags.fail(error.ParseError, name.line, "PROC GLIMMIX: {s}= requires a nonnegative integer", .{name.text});
    return @intFromFloat(n);
}
fn keyword(comptime E: type, cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!E {
    if (!is(t, i.*, .name)) return bad(cx, t[@min(i.*, t.len - 1)]);
    for (std.enums.values(E)) |value| if (eq(t[i.*].text, @tagName(value))) {
        i.* += 1;
        return value;
    };
    return bad(cx, t[i.*]);
}
fn addUnique(cx: proc.ProcCtx, list: *std.ArrayList(usize), ci: usize) !void {
    if (std.mem.indexOfScalar(usize, list.items, ci) == null) try list.append(cx.arena, ci);
}
fn variable(cx: proc.ProcCtx, ds: *const Dataset, token: lex.Token) diag.Error!usize {
    return ds.indexOf(token.text) orelse cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{token.text});
}

fn parseOptions(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, name: *?[]const u8) diag.Error!Options {
    var o = Options{};
    next: while (i.* < t.len and !is(t, i.*, .semicolon) and !is(t, i.*, .eof)) {
        const token = t[i.*];
        if (token.tag != .name) return bad(cx, token);
        i.* += 1;
        for ([_][]const u8{ "empirical", "outdesign", "subgradient", "subgrad", "plots", "plot" }) |later|
            if (eq(token.text, later)) return gap(cx, token.line, "option {s} is not implemented", .{token.text});
        if (!is(t, i.*, .eq)) {
            if (eq(token.text, "noclprint")) {
                o.flags.insert(.noclprint);
                continue;
            }
            for (flag_names) |entry| if (eq(token.text, entry[0])) {
                o.flags.insert(entry[1]);
                continue :next;
            };
            return bad(cx, token);
        }
        i.* += 1;
        if (eq(token.text, "data")) {
            if (!is(t, i.*, .name)) return bad(cx, t[@min(i.*, t.len - 1)]);
            name.* = t[i.*].text;
            i.* += 1;
            if (is(t, i.*, .dot)) {
                if (!is(t, i.* + 1, .name)) return bad(cx, t[i.*]);
                name.* = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.*.?, t[i.* + 1].text });
                i.* += 2;
            }
            if (is(t, i.*, .lparen)) {
                const end = proc.skipParen(t, i.*);
                if (end <= i.* or !is(t, end - 1, .rparen)) return bad(cx, t[i.*]);
                i.* = end;
            }
        } else if (eq(token.text, "method")) {
            o.method = try keyword(Method, cx, t, i);
            if (is(t, i.*, .lparen)) return gap(cx, token.line, "METHOD=QUAD quadrature options are not implemented", .{});
        } else if (eq(token.text, "order")) {
            o.order = try keyword(classes.Order, cx, t, i);
        } else if (eq(token.text, "ic") or eq(token.text, "infocrit")) {
            o.infocrit = try keyword(InfoCrit, cx, t, i);
        } else if (eq(token.text, "noclprint")) {
            o.flags.insert(.noclprint);
            o.noclprint_limit = try count(cx, token, try numeric(cx, t, i));
        } else if (eq(token.text, "namelen")) {
            o.namelen = try count(cx, token, try numeric(cx, t, i));
            // p.3708: "The default and minimum value is 20"; SAS's reaction to a
            // smaller value is not documented there.
            if (o.namelen < 20) return gap(cx, token.line, "NAMELEN= below the documented minimum of 20 is not independently verified", .{});
        } else if (eq(token.text, "maxopt") or eq(token.text, "maxlmmupdate")) {
            o.maxopt = try count(cx, token, try numeric(cx, t, i));
        } else if (eq(token.text, "inititer")) {
            o.inititer = try count(cx, token, try numeric(cx, t, i));
        } else if (eq(token.text, "scoring")) {
            o.scoring = try count(cx, token, try numeric(cx, t, i));
        } else if (eq(token.text, "abspconv") or eq(token.text, "pconv") or eq(token.text, "fdigits") or eq(token.text, "singchol") or eq(token.text, "singres") or eq(token.text, "singular")) {
            const r = try numeric(cx, t, i);
            if (r < 0) return cx.diags.fail(error.ParseError, token.line, "PROC GLIMMIX: {s}= requires a nonnegative value", .{token.text});
            if (eq(token.text, "abspconv")) o.abspconv = r else if (eq(token.text, "pconv")) o.pconv = r else if (eq(token.text, "fdigits")) o.fdigits = r else if (eq(token.text, "singchol")) o.singchol = r else if (eq(token.text, "singres")) o.singres = r else o.singular = r;
        } else return bad(cx, token);
    }
    if (o.has(.profile) and o.has(.noprofile)) return gap(cx, t[0].line, "PROFILE together with NOPROFILE is not independently verified", .{});
    if (o.has(.initglm) and o.has(.noinitglm)) return gap(cx, t[0].line, "INITGLM together with NOINITGLM is not independently verified", .{});
    // p.3708: NOBOUND cannot be used for adaptive quadrature estimation.
    if (o.has(.nobound) and o.method == .quad) return cx.diags.fail(error.ParseError, t[0].line, "PROC GLIMMIX: the NOBOUND option cannot be used with METHOD=QUAD", .{});
    return o;
}

/// `response <events/trials> = effects </ options>`. Effects are interpreted
/// against the CLASS list (CLASS precedes MODEL, p.3731); of the options only
/// NOINT is read here.
fn parseModel(cx: proc.ProcCtx, ds: *const Dataset, class_columns: []const usize, t: []const lex.Token, line: usize, vars: *std.ArrayList(usize)) diag.Error!Model {
    var depth: usize = 0;
    var eq_at: ?usize = null;
    for (t, 0..) |token, k| {
        if (token.tag == .lparen) depth += 1;
        if (token.tag == .rparen and depth > 0) depth -= 1;
        if (token.tag == .eq and depth == 0) {
            eq_at = k;
            break;
        }
    }
    const split = eq_at orelse return cx.diags.fail(error.ParseError, line, "PROC GLIMMIX: MODEL requires response = effects", .{});
    const left = t[0..split];
    if (!is(left, 0, .name)) return cx.diags.fail(error.ParseError, line, "PROC GLIMMIX: MODEL requires a response variable", .{});
    var model = Model{ .response = try variable(cx, ds, left[0]), .line = line };
    if (left.len == 3 and left[1].tag == .slash and left[2].tag == .name) {
        model.trials = try variable(cx, ds, left[2]);
        for ([_]usize{ model.response, model.trials.? }) |ci| if (ds.columns.items[ci].type != .num)
            return cx.diags.fail(error.ParseError, line, "PROC GLIMMIX: events/trials variable {s} must be numeric", .{ds.columns.items[ci].name});
        try addUnique(cx, vars, model.trials.?);
    } else if (left.len > 1) {
        if (left[1].tag == .lparen and proc.skipParen(left, 1) == left.len) return gap(cx, line, "MODEL response options are not implemented", .{});
        return bad(cx, left[1]);
    }
    try addUnique(cx, vars, model.response);
    var k = split + 1;
    while (k < t.len and !(t[k].tag == .slash and depth == 0)) : (k += 1) switch (t[k].tag) {
        .name => try addUnique(cx, vars, try variable(cx, ds, t[k])),
        .lparen => depth += 1,
        .rparen => {
            if (depth == 0) return bad(cx, t[k]);
            depth -= 1;
        },
        .star, .pipe, .at, .number => {},
        else => return bad(cx, t[k]),
    };
    if (depth != 0) return cx.diags.fail(error.ParseError, line, "PROC GLIMMIX: unbalanced parentheses in MODEL", .{});
    model.effects = try design.parseEffects(cx, ds, class_columns, t[split + 1 .. k], line);
    if (k < t.len) model.option_tokens = t[k + 1 ..];
    for (model.option_tokens) |o| if (o.tag == .name and eq(o.text, "noint")) {
        model.intercept = false;
    };
    return model;
}

/// RANDOM effects and SUBJECT=/GROUP= effects contribute listwise-missing
/// variables; all other RANDOM options are left to the covariance tickets.
fn randomVariables(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, vars: *std.ArrayList(usize)) diag.Error!void {
    var k: usize = 0;
    var depth: usize = 0;
    while (k < t.len and !(t[k].tag == .slash and depth == 0)) : (k += 1) switch (t[k].tag) {
        .name => if (!eq(t[k].text, "intercept") and !eq(t[k].text, "int") and !eq(t[k].text, "_residual_")) try addUnique(cx, vars, try variable(cx, ds, t[k])),
        .lparen => depth += 1,
        .rparen => {
            if (depth == 0) return bad(cx, t[k]);
            depth -= 1;
        },
        .star, .pipe, .at, .number => {},
        else => return bad(cx, t[k]),
    };
    while (k < t.len) : (k += 1) {
        if (t[k].tag != .name or !is(t, k + 1, .eq)) continue;
        if (!eq(t[k].text, "subject") and !eq(t[k].text, "sub") and !eq(t[k].text, "group") and !eq(t[k].text, "grp")) continue;
        var j = k + 2;
        if (!is(t, j, .name)) return bad(cx, t[k]);
        while (is(t, j, .name)) {
            if (!eq(t[j].text, "intercept") and !eq(t[j].text, "int")) try addUnique(cx, vars, try variable(cx, ds, t[j]));
            j += 1;
            if (is(t, j, .lparen)) {
                j += 1;
                while (j < t.len and t[j].tag != .rparen) : (j += 1) if (t[j].tag == .name) try addUnique(cx, vars, try variable(cx, ds, t[j]));
                j += 1;
            }
            if (!is(t, j, .star)) break;
            j += 1;
        }
        k = j - 1;
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    if (t.len < 3) return cx.diags.fail(error.ParseError, 0, "PROC GLIMMIX: incomplete declaration", .{});
    var name: ?[]const u8 = null;
    var i: usize = 2;
    const opts = try parseOptions(cx, t, &i, &name);
    if (!is(t, i, .semicolon)) return bad(cx, t[@min(i, t.len - 1)]);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, t[0].line, "File {s} does not exist.", .{name orelse "_last_"});
    var input = try proc.procInputObs(cx.arena, raw, t, cx.diags);
    var by: groups.Statements = .{};
    var id: ?[]const usize = null;
    var freq: ?usize = null;
    var weight: ?usize = null;
    var class_columns: std.ArrayList(usize) = .empty;
    var required: std.ArrayList(usize) = .empty;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var model: ?Model = null;
    var nloptions: ?nlo.Options = null;
    i += 1;
    while (i < t.len and !is(t, i, .eof)) {
        if (is(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        const token = t[i];
        var end = i + 1;
        while (end < t.len and !is(t, end, .semicolon) and !is(t, end, .eof)) end += 1;
        if (!is(t, end, .semicolon)) return bad(cx, token);
        const body = t[i + 1 .. end];
        if (token.tag != .name) return bad(cx, token);
        if (body.len > 0 and body[0].tag == .eq) return gap(cx, token.line, "programming statements are not implemented", .{});
        if (eq(token.text, "by")) {
            // p.3730: with several BY statements only the last one is used.
            try by.read(cx.arena, t, &i);
        } else if (eq(token.text, "class")) {
            // p.3731: CLASS must precede MODEL.
            if (model != null) return cx.diags.fail(error.ParseError, token.line, "PROC GLIMMIX: CLASS must precede MODEL", .{});
            var j = i + 1;
            while (j < end) {
                if (is(t, j, .slash) or is(t, j, .lparen)) return gap(cx, token.line, "CLASS statement options are not implemented", .{});
                for (try lists.next(cx.arena, input.ds, t[0..end], &j, cx.diags)) |n| {
                    const ci = input.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{n});
                    try addUnique(cx, &class_columns, ci);
                }
            }
        } else if (eq(token.text, "model")) {
            if (model != null) return cx.diags.fail(error.ParseError, token.line, "PROC GLIMMIX: only one MODEL statement is allowed", .{});
            model = try parseModel(cx, input.ds, class_columns.items, body, token.line, &required);
        } else if (eq(token.text, "random")) {
            try randomVariables(cx, input.ds, body, &required);
        } else if (eq(token.text, "freq")) {
            if (freq != null) return gap(cx, token.line, "repeated FREQ statements are not independently verified", .{});
            const v = try lists.roleVariable(t[0..end], i + 1, false, cx.diags);
            freq = try selection.Roles.numeric(input.ds, v.text, "FREQ", cx.diags, v.line);
        } else if (eq(token.text, "weight")) {
            if (weight != null) return gap(cx, token.line, "repeated WEIGHT statements are not independently verified", .{});
            const v = try lists.roleVariable(t[0..end], i + 1, false, cx.diags);
            weight = try selection.Roles.numeric(input.ds, v.text, "WEIGHT", cx.diags, v.line);
        } else if (eq(token.text, "id")) {
            if (id != null) return gap(cx, token.line, "repeated ID statements are not independently verified", .{});
            // p.3750: ID may also name computed/automatic variables (_MU_, ...).
            for (body) |b| if (b.tag == .name and input.ds.indexOf(b.text) == null and b.text.len > 0 and b.text[0] == '_')
                return gap(cx, b.line, "ID of automatic or computed variable {s} is not implemented", .{b.text});
            var columns: std.ArrayList(usize) = .empty;
            var j = i + 1;
            while (j < end) for (try lists.next(cx.arena, input.ds, t[0..end], &j, cx.diags)) |n| {
                const ci = input.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{n});
                try addUnique(cx, &columns, ci);
            };
            id = columns.items;
        } else if (eq(token.text, "nloptions")) {
            nloptions = try nlo.parse(cx.diags, "GLIMMIX", 0, body, token.line);
        } else if (eq(token.text, "format")) {
            try proc.parseProcFormat(cx.arena, t, &i, &formats);
        } else if (eq(token.text, "where") or eq(token.text, "run") or eq(token.text, "quit") or parser.isMidStepSkippable(token.text)) {
            // WHERE is applied by procInputObs; globals are handled by main.
        } else {
            for ([_][]const u8{ "code", "contrast", "covtest", "effect", "estimate", "lsmeans", "lsmestimate", "output", "parms", "slice", "store" }) |known|
                if (eq(token.text, known)) return gap(cx, token.line, "statement {s} is not implemented", .{token.text});
            for ([_][]const u8{ "if", "else", "do", "end", "array", "call", "goto", "select", "when", "otherwise", "return", "put", "link", "delete" }) |known|
                if (eq(token.text, known)) return gap(cx, token.line, "programming statements are not implemented", .{});
            return bad(cx, token);
        }
        i = end + 1;
    }
    const m = model orelse return gap(cx, t[0].line, "a step without a MODEL statement is not implemented", .{});
    for (formats.items) |f| if (input.ds.indexOf(f.name) == null) return cx.diags.fail(error.ParseError, t[0].line, "Variable {s} not found.", .{f.name});
    input.ds = try groups.withFormats(cx.arena, input.ds, formats.items);
    const by_spec = try by.resolve(cx.arena, input.ds, cx.diags);
    var by_columns: std.ArrayList(usize) = .empty;
    for (by_spec.names) |n| try by_columns.append(cx.arena, input.ds.indexOf(n).?);
    for (class_columns.items) |ci| try addUnique(cx, &required, ci);
    return .{
        .input = input,
        .options = opts,
        .roles = .{ .by = by_columns.items, .id = id orelse &.{}, .frequency = freq, .weight = weight },
        .by_desc = by_spec.desc,
        .notsorted = by_spec.notsorted,
        .id_columns = id,
        .class_columns = class_columns.items,
        .model = m,
        .required = required.items,
        .nloptions = nloptions,
        .line = t[0].line,
    };
}

/// One Group per BY group, in input order. p.3750: a FREQ value is truncated
/// to an integer and the observation is unused when it is missing or below 1.
/// p.3817: nonpositive or missing WEIGHT values exclude the observation.
/// Response-domain exclusions (for example events > trials) depend on the
/// distribution and are applied by the estimation tickets, not here.
pub fn prepare(cx: proc.ProcCtx, spec: Spec) diag.Error![]Group {
    const view = try selection.View.init(cx.arena, spec.input, spec.roles);
    const by_groups = try view.groups(cx.arena, spec.by_desc, spec.notsorted, cx.diags);
    const results = try cx.arena.alloc(Group, by_groups.len);
    for (by_groups, results) |group, *result| {
        const selected = try group.select(cx.arena, .{
            .missing_columns = spec.required,
            .frequency = if (spec.roles.frequency != null) .truncate_positive else .preserve,
            .weight = if (spec.roles.weight != null) .positive_only else .preserve,
        });
        const rows = try cx.arena.alloc([]const Value, selected.observations.len);
        const frequencies = try cx.arena.alloc(f64, selected.observations.len);
        var total: f64 = 0;
        for (selected.observations, rows, frequencies) |row, *cells, *f| {
            if (!std.math.isFinite(row.weight.num)) return cx.diags.fail(error.ParseError, spec.line, "PROC GLIMMIX: analysis weights must be finite", .{});
            cells.* = row.cells;
            f.* = row.frequency.num;
            total += f.*;
        }
        const levels = try cx.arena.alloc(classes.Levels, spec.class_columns.len);
        for (spec.class_columns, levels) |ci, *target| target.* = try classes.build(cx.arena, spec.input.ds, rows, ci, .{ .order = spec.options.order, .frequencies = frequencies });
        result.* = .{ .raw = group, .selected = selected, .read_count = group.observations.len, .used_count = selected.observations.len, .frequency_used = total, .class_levels = levels };
    }
    return results;
}

/// Non-full-rank X of one BY group with its aliased columns and full-rank
/// reduction (STAT-GLIMMIX-003). Shapes whose design is not independently
/// verified are loud gaps rather than a plausible matrix.
pub fn fixedDesign(cx: proc.ProcCtx, spec: Spec, group: Group) diag.Error!design.Design {
    const ds = spec.input.ds;
    // ponytail: the shared builder needs a numeric response column only for its
    // own listwise filter; response levels belong to the distribution tickets.
    if (ds.columns.items[spec.model.response].type != .num) return gap(cx, spec.model.line, "character response variables are not implemented", .{});
    // prepare() orders ORDER=FREQ levels by FREQ-weighted counts; the shared
    // design builder counts observations.
    if (spec.options.order == .freq and spec.roles.frequency != null) return gap(cx, spec.model.line, "ORDER=FREQ with a FREQ statement is not implemented for the model matrix", .{});
    if (spec.model.effects.len == 0 and !spec.model.intercept) return gap(cx, spec.model.line, "a model without fixed-effects columns is not implemented", .{});
    const rows = try cx.arena.alloc([]const Value, group.selected.observations.len);
    for (group.selected.observations, rows) |row, *cells| cells.* = row.cells;
    const d = design.build(cx.arena, ds, rows, spec.model.response, spec.class_columns, spec.options.order, .{ .effects = spec.model.effects, .intercept = spec.model.intercept }, spec.options.singular) catch |err| switch (err) {
        error.OutOfMemory => return err,
        else => return gap(cx, spec.model.line, "the model matrix could not be constructed from the input values", .{}),
    };
    if (d.full.n != group.used_count) return gap(cx, spec.model.line, "the model matrix does not cover every used observation", .{});
    return d;
}

/// Validates the declarations and the input of every BY group, then stops at
/// the estimation boundary. ponytail: no table is rendered before a fit exists,
/// so a partial listing can never be mistaken for a completed analysis.
pub fn run(cx: proc.ProcCtx, tokens: []const lex.Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    const prepared = try prepare(cx, spec);
    if (prepared.len == 0) return gap(cx, spec.line, "an analysis without usable observations is not implemented", .{});
    for (prepared) |group| if (group.used_count == 0) return gap(cx, spec.line, "an analysis without usable observations is not implemented", .{});
    if (spec.options.has(.nofit)) return gap(cx, spec.line, "NOFIT model summaries are not implemented", .{});
    for (prepared) |group| _ = try fixedDesign(cx, spec, group);
    return gap(cx, spec.model.line, "model estimation is not implemented", .{});
}

const t_ = std.testing;
const Harness = struct {
    cx: proc.ProcCtx,
    fn init(a: std.mem.Allocator) !Harness {
        const ds = try a.create(Dataset);
        ds.* = Dataset.init(a, "trial");
        _ = try ds.addColumn("site", .num);
        _ = try ds.addColumn("arm", .char);
        for ([_][]const u8{ "n", "events", "f", "w", "block" }) |name| _ = try ds.addColumn(name, .num);
        // Invented data. Columns: site arm n events f w block.
        const M = Value.missing;
        const rows = [_]struct { f64, []const u8, f64, f64, Value, Value, f64 }{
            .{ 2, "B", 10, 3, .{ .num = 2.9 }, .{ .num = 1 }, 1 }, // used, FREQ truncated to 2
            .{ 1, "A", 12, 4, .{ .num = 1 }, .{ .num = 0.5 }, 1 }, // used
            .{ 1, "B", 11, 5, .{ .num = 0.9 }, .{ .num = 1 }, 1 }, // FREQ < 1
            .{ 2, "A", 9, 2, M, .{ .num = 1 }, 1 }, // FREQ missing
            .{ 3, "A", 8, 1, .{ .num = 1 }, .{ .num = 0 }, 2 }, // WEIGHT zero
            .{ 3, "B", 8, 2, .{ .num = 1 }, .{ .num = -2 }, 2 }, // WEIGHT negative
            .{ 4, "A", 7, 2, .{ .num = 1 }, M, 2 }, // WEIGHT missing
            .{ 4, " ", 7, 3, .{ .num = 1 }, .{ .num = 1 }, 2 }, // CLASS level missing
            .{ 5, "B", 6, std.math.nan(f64), .{ .num = 1 }, .{ .num = 1 }, 2 }, // response missing
            .{ 5, "A", 6, 1, .{ .num = 3 }, .{ .num = 2 }, 2 }, // used
        };
        for (rows) |r| try ds.appendRow(&.{ .{ .num = r[0] }, .{ .str = r[1] }, .{ .num = r[2] }, .{ .num = r[3] }, r[4], r[5], .{ .num = r[6] } });
        const lib = try a.create(@import("../exec.zig").Library);
        lib.* = .init(a);
        try lib.put("trial", ds);
        const empty = try a.create(Dataset);
        empty.* = Dataset.init(a, "none");
        _ = try empty.addColumn("y", .num);
        _ = try empty.addColumn("x", .num);
        try lib.put("none", empty);
        const d = try a.create(diag.Diagnostics);
        d.* = .init(a);
        return .{ .cx = .{ .arena = a, .lib = lib, .diags = d } };
    }
    fn spec(h: Harness, source: []const u8) !Spec {
        return parse(h.cx, try lex.tokenize(h.cx.arena, source, h.cx.diags));
    }
    /// Runs the whole step and returns the last captured error text.
    fn failure(h: Harness, source: []const u8, expected: diag.Error, gap_expected: bool) ![]const u8 {
        diag.resetGap();
        defer diag.resetGap();
        const before = h.cx.diags.list.items.len;
        try t_.expectError(expected, run(h.cx, try lex.tokenize(h.cx.arena, source, h.cx.diags)));
        try t_.expectEqual(gap_expected, diag.gapHit());
        try t_.expect(h.cx.diags.list.items.len > before);
        const last = h.cx.diags.list.items[h.cx.diags.list.items.len - 1];
        try t_.expectEqual(.err, last.severity);
        return last.message;
    }
};

test "GLIMMIX001 PROC statement defaults and explicit basic options" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const h = try Harness.init(arena.allocator());
    const d = try h.spec("proc glimmix data=trial; class site arm; model events/n = arm; random intercept / subject=site; run;");
    try t_.expectEqual(Method.rspl, d.options.method);
    try t_.expectEqual(classes.Order.formatted, d.options.order);
    try t_.expectEqual(@as(usize, 0), d.options.flags.count());
    try t_.expectEqual(@as(usize, 20), d.options.namelen);
    try t_.expectEqual(@as(usize, 4), d.options.inititer);
    try t_.expectEqual(@as(usize, 20), d.maxOptimizations());
    try t_.expectEqual(@as(?InfoCrit, null), d.options.infocrit);
    // Reference listing/log of the default fit prints PCONV=1.11022E-8.
    try t_.expectApproxEqRel(@as(f64, 1.11022e-8), d.options.pconv, 5e-6);
    try t_.expectApproxEqRel(@as(f64, 1.11022e-12), d.options.singular, 5e-6);
    try t_.expectEqual(@as(f64, 0), d.options.abspconv);
    try t_.expectEqual(@as(?usize, null), d.roles.frequency);
    try t_.expectEqual(@as(?usize, null), d.roles.weight);
    try t_.expectEqual(@as(?[]const usize, null), d.id_columns);
    try t_.expectEqual(@as(usize, 3), d.model.response);
    try t_.expectEqual(@as(?usize, 2), d.model.trials);
    try t_.expectEqualSlices(usize, &.{ 0, 1 }, d.class_columns);
    try t_.expectEqualSlices(usize, &.{ 2, 3, 1, 0 }, d.required);

    const e = try h.spec("proc glimmix data=trial(where=(site>0)) method=LAPLACE order=data noclprint=5 namelen=30 maxopt=7 inititer=2 scoring=3 pconv=1e-6 abspconv=1e-4 fdigits=9.5 singchol=1e-9 singres=1e-10 singular=1e-11 ic=pq chol startglm or asycov nobound noreml noitprint nobsdetail; model events = site / dist=poisson; nloptions maxiter=11; run;");
    try t_.expectEqual(Method.laplace, e.options.method);
    try t_.expectEqual(classes.Order.data, e.options.order);
    try t_.expectEqual(@as(?usize, 5), e.options.noclprint_limit);
    try t_.expectEqual(@as(usize, 30), e.options.namelen);
    try t_.expectEqual(@as(usize, 7), e.maxOptimizations());
    try t_.expectEqual(@as(usize, 2), e.options.inititer);
    try t_.expectEqual(@as(usize, 3), e.options.scoring);
    try t_.expectEqual(@as(f64, 1e-6), e.options.pconv);
    try t_.expectEqual(@as(f64, 1e-4), e.options.abspconv);
    try t_.expectEqual(@as(?f64, 9.5), e.options.fdigits);
    try t_.expectEqual(@as(f64, 1e-9), e.options.singchol);
    try t_.expectEqual(@as(f64, 1e-10), e.options.singres);
    try t_.expectEqual(@as(f64, 1e-11), e.options.singular);
    try t_.expectEqual(@as(?InfoCrit, .pq), e.options.infocrit);
    for ([_]Flag{ .cholesky, .initglm, .oddsratio, .asycov, .nobound, .noreml, .noitprint, .nobsdetail, .noclprint }) |flag| try t_.expect(e.options.has(flag));
    try t_.expect(!e.options.has(.nofit));
    try t_.expectEqual(@as(usize, 3), e.model.option_tokens.len);
    // p.3707: MAXOPT defaults to NLOPTIONS MAXITER= when only that is given.
    const n = try h.spec("proc glimmix data=trial; model events = site; nloptions maxiter=11; run;");
    try t_.expectEqual(@as(usize, 11), n.maxOptimizations());
}

test "GLIMMIX001 BY, FREQ, WEIGHT, ID roles and observation selection" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const h = try Harness.init(arena.allocator());
    const s = try h.spec("proc glimmix data=trial order=data; by site; by block; class arm; model events/n = arm; random intercept / subject=site; freq f; weight w; id site n; run;");
    try t_.expectEqualSlices(usize, &.{6}, s.roles.by); // only the last BY statement
    try t_.expectEqual(@as(?usize, 4), s.roles.frequency);
    try t_.expectEqual(@as(?usize, 5), s.roles.weight);
    try t_.expectEqualSlices(usize, &.{ 0, 2 }, s.id_columns.?);
    const g = try prepare(h.cx, s);
    try t_.expectEqual(@as(usize, 2), g.len);
    try t_.expectEqual(@as(usize, 4), g[0].read_count);
    try t_.expectEqual(@as(usize, 2), g[0].used_count);
    try t_.expectEqual(@as(f64, 3), g[0].frequency_used); // trunc(2.9) + 1
    try t_.expectEqual(@as(f64, 2), g[0].selected.observations[0].frequency.num);
    try t_.expectEqual(@as(f64, 0.5), g[0].selected.observations[1].weight.num);
    try t_.expectEqual(@as(usize, 1), g[0].selected.observations[0].source_number);
    try t_.expectEqual(@as(usize, 6), g[1].read_count);
    try t_.expectEqual(@as(usize, 1), g[1].used_count);
    try t_.expectEqual(@as(usize, 10), g[1].selected.observations[0].source_number);
    try t_.expectEqual(@as(f64, 3), g[1].frequency_used);
    // ORDER=DATA level order inside the first BY group: B appears before A.
    try t_.expectEqual(@as(usize, 2), g[0].class_levels[0].levels.len);
    try t_.expectEqualStrings("B", g[0].class_levels[0].levels[0].label);
    try t_.expectEqual(@as(f64, 2), g[0].class_levels[0].levels[0].frequency);
    try t_.expectEqualStrings("A", g[0].class_levels[0].levels[1].label);
    // Levels are per BY group: the second group only keeps arm A.
    try t_.expectEqual(@as(usize, 1), g[1].class_levels[0].levels.len);

    // Without FREQ/WEIGHT only missing model values exclude; formatted order.
    const p = try h.spec("proc glimmix data=trial; class arm site; model events/n = arm; random intercept / subject=site; run;");
    const all = try prepare(h.cx, p);
    try t_.expectEqual(@as(usize, 1), all.len);
    try t_.expectEqual(@as(usize, 10), all[0].read_count);
    try t_.expectEqual(@as(usize, 8), all[0].used_count);
    try t_.expectEqual(@as(f64, 8), all[0].frequency_used);
    try t_.expectEqualStrings("A", all[0].class_levels[0].levels[0].label);
    try t_.expectEqual(@as(usize, 5), all[0].class_levels[1].levels.len);
    // A CLASS variable outside the model still excludes its missing rows (p.413).
    const u = try prepare(h.cx, try h.spec("proc glimmix data=trial; class arm; model n = site; run;"));
    try t_.expectEqual(@as(usize, 9), u[0].used_count);
    // WHERE keeps physical observation numbers.
    const w = try prepare(h.cx, try h.spec("proc glimmix data=trial; where site >= 5; model n = site; run;"));
    try t_.expectEqual(@as(usize, 2), w[0].used_count);
    try t_.expectEqual(@as(usize, 9), w[0].selected.observations[0].source_number);
    // Empty input is one group without observations; `run` reports it loudly.
    const none = try prepare(h.cx, try h.spec("proc glimmix data=none; model y = x; run;"));
    try t_.expectEqual(@as(usize, 1), none.len);
    try t_.expectEqual(@as(usize, 0), none[0].read_count);
    try t_.expectEqual(@as(usize, 0), none[0].used_count);
}

test "GLIMMIX001 invalid declarations are user errors and unimplemented features are loud gaps" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const h = try Harness.init(arena.allocator());
    const E = error.ParseError;
    // STAT-GLIMMIX-003: MODEL effects are now interpreted, so a character
    // variable outside CLASS is a user error; these cases use a covariate.
    const m = "model events/n = site;";
    const user = [_]struct { []const u8, []const u8 }{
        .{ "proc glimmix data=trial bogus; " ++ m ++ " run;", "unexpected token bogus" },
        .{ "proc glimmix data=trial method=reml; " ++ m ++ " run;", "unexpected token reml" },
        .{ "proc glimmix data=trial order=random; " ++ m ++ " run;", "unexpected token random" },
        .{ "proc glimmix data=trial pconv=-1; " ++ m ++ " run;", "pconv= requires a nonnegative value" },
        .{ "proc glimmix data=trial maxopt=2.5; " ++ m ++ " run;", "maxopt= requires a nonnegative integer" },
        .{ "proc glimmix data=trial method=quad nobound; " ++ m ++ " run;", "NOBOUND option cannot be used with METHOD=QUAD" },
        .{ "proc glimmix data=missing; " ++ m ++ " run;", "File missing does not exist." },
        .{ "proc glimmix data=trial; model events/n = dose; run;", "Variable dose not found." },
        .{ "proc glimmix data=trial; model events/arm = site; run;", "events/trials variable arm must be numeric" },
        .{ "proc glimmix data=trial; model events; run;", "MODEL requires response = effects" },
        .{ "proc glimmix data=trial; " ++ m ++ m ++ " run;", "only one MODEL statement is allowed" },
        .{ "proc glimmix data=trial; " ++ m ++ " class arm; run;", "CLASS must precede MODEL" },
        .{ "proc glimmix data=trial; " ++ m ++ " freq arm; run;", "Variable arm in the FREQ statement must be numeric" },
        .{ "proc glimmix data=trial; " ++ m ++ " weight nowt; run;", "Variable nowt in the WEIGHT statement is not on the input data set" },
        .{ "proc glimmix data=trial; " ++ m ++ " random intercept / subject=nosub; run;", "Variable nosub not found." },
        .{ "proc glimmix data=trial; by nosuch; " ++ m ++ " run;", "nosuch" },
        .{ "proc glimmix data=trial; by descending block; " ++ m ++ " run;", "sorted" },
    };
    for (user) |case| {
        const message = try h.failure(case[0], E, false);
        if (std.ascii.indexOfIgnoreCase(message, case[1]) == null) {
            std.debug.print("{s}\nunexpected diagnostic: {s}\n", .{ case[0], message });
            return error.TestUnexpectedResult;
        }
    }
    const gaps = [_]struct { []const u8, []const u8 }{
        .{ "proc glimmix data=trial; class arm site; " ++ m ++ " random intercept / subject=site; run;", "PROC GLIMMIX: model estimation is not implemented" },
        .{ "proc glimmix data=trial; by block; class arm; " ++ m ++ " freq f; weight w; id site; run;", "model estimation is not implemented" },
        .{ "proc glimmix data=trial nofit; " ++ m ++ " run;", "NOFIT model summaries are not implemented" },
        .{ "proc glimmix data=none; model y = x; run;", "an analysis without usable observations is not implemented" },
        .{ "proc glimmix data=trial; where site > 99; " ++ m ++ " run;", "an analysis without usable observations is not implemented" },
        .{ "proc glimmix data=trial; by block; where f < 1; " ++ m ++ " freq f; run;", "an analysis without usable observations is not implemented" },
        .{ "proc glimmix data=trial empirical; " ++ m ++ " run;", "option empirical is not implemented" },
        .{ "proc glimmix data=trial plots=all; " ++ m ++ " run;", "option plots is not implemented" },
        .{ "proc glimmix data=trial outdesign=x; " ++ m ++ " run;", "option outdesign is not implemented" },
        .{ "proc glimmix data=trial method=quad(qpoints=5); " ++ m ++ " run;", "quadrature options are not implemented" },
        .{ "proc glimmix data=trial namelen=10; " ++ m ++ " run;", "NAMELEN= below the documented minimum" },
        .{ "proc glimmix data=trial profile noprofile; " ++ m ++ " run;", "PROFILE together with NOPROFILE" },
        .{ "proc glimmix data=trial; class arm / truncate; " ++ m ++ " run;", "CLASS statement options are not implemented" },
        .{ "proc glimmix data=trial; " ++ m ++ " lsmeans arm / cl ilink; run;", "statement lsmeans is not implemented" },
        .{ "proc glimmix data=trial; " ++ m ++ " output out=o pred=p; run;", "statement output is not implemented" },
        .{ "proc glimmix data=trial; " ++ m ++ " freq f; freq f; run;", "repeated FREQ statements" },
        .{ "proc glimmix data=trial; " ++ m ++ " weight w; weight w; run;", "repeated WEIGHT statements" },
        .{ "proc glimmix data=trial; " ++ m ++ " id site; id n; run;", "repeated ID statements" },
        .{ "proc glimmix data=trial; " ++ m ++ " id _mu_; run;", "ID of automatic or computed variable _mu_" },
        .{ "proc glimmix data=trial; " ++ m ++ " wt = 1/n; run;", "programming statements are not implemented" },
        .{ "proc glimmix data=trial; model events(event='1') = arm; run;", "MODEL response options are not implemented" },
        .{ "proc glimmix data=trial; class arm; run;", "without a MODEL statement" },
    };
    for (gaps) |case| {
        const message = try h.failure(case[0], E, true);
        if (std.mem.indexOf(u8, message, case[1]) == null) {
            std.debug.print("{s}\nunexpected diagnostic: {s}\n", .{ case[0], message });
            return error.TestUnexpectedResult;
        }
    }
}

test "GLIMMIX003 MODEL effects: invalid structure is a user error, unimplemented syntax a loud gap" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const h = try Harness.init(arena.allocator());
    const E = error.ParseError;
    const cases = [_]struct { []const u8, []const u8, bool }{
        .{ "class site; model events/n = arm;", "character variable arm in a MODEL effect must be listed in the CLASS statement", false },
        .{ "class arm; model events/n = arm(site);", "nesting variable site must be listed in the CLASS statement", false },
        .{ "class arm; model events/n = n(w);", "nesting variable w must be listed in the CLASS statement", false },
        .{ "class arm site; model events/n = arm(arm);", "variable arm cannot be nested within itself", false },
        .{ "class arm site; model events/n = arm();", "malformed nesting in MODEL effect", false },
        .{ "class arm site; model events/n = arm(site)(site);", "malformed MODEL effect", false },
        .{ "class arm site; model events/n = arm(site;", "unbalanced parentheses in MODEL", false },
        .{ "class arm site; model events/n = arm*;", "malformed MODEL effect", false },
        .{ "class arm site; model events/n = arm(nosuch);", "Variable nosuch not found.", false },
        .{ "class arm site; model events/n = arm|site;", "the bar operator in MODEL effects is not implemented", true },
        .{ "class arm site; model events/n = arm site arm*site @2;", "the @ operator in MODEL effects is not implemented", true },
        .{ "class arm; model arm = site;", "character response variables are not implemented", true },
        .{ "model events/n = / noint;", "a model without fixed-effects columns is not implemented", true },
        .{ "class arm; model events/n = arm; effect s = spline(n);", "statement effect is not implemented", true },
        .{ "class arm; model events/n = arm; estimate 'd' arm 1 -1;", "statement estimate is not implemented", true },
        .{ "class arm; model events/n = arm; contrast 'd' arm [1, 1] [-1, 2];", "", true },
        .{ "class arm site; model events/n = arm site(arm) n*arm / noint solution;", "model estimation is not implemented", true },
    };
    for (cases) |case| {
        const source = try std.fmt.allocPrint(h.cx.arena, "proc glimmix data=trial; {s} run;", .{case[0]});
        const message = try h.failure(source, E, case[2]);
        if (std.mem.indexOf(u8, message, case[1]) == null) {
            std.debug.print("{s}\nunexpected diagnostic: {s}\n", .{ source, message });
            return error.TestUnexpectedResult;
        }
    }
}

test "GLIMMIX003 step-level design: used observations, CLASS order, NOINT and aliased columns" {
    var arena = std.heap.ArenaAllocator.init(t_.allocator);
    defer arena.deinit();
    const h = try Harness.init(arena.allocator());
    // Used rows (site, arm): 2B 1A 1B 2A 3A 3B 4A 5A -- eight distinct cells.
    const s = try h.spec("proc glimmix data=trial; class arm site; model events/n = arm site*arm; run;");
    try t_.expect(s.model.intercept);
    try t_.expectEqual(@as(usize, 2), s.model.effects.len);
    const g = try prepare(h.cx, s);
    const d = try fixedDesign(h.cx, s, g[0]);
    try t_.expectEqual(@as(usize, 8), d.full.n);
    // Int | A B | A1 A2 A3 A4 A5 B1 B2 B3: site*arm is reordered to arm*site
    // and the cells B4, B5 are deleted.
    try t_.expectEqual(@as(usize, 11), d.full.p);
    try t_.expectEqualStrings("arm*site", d.effects[2].name);
    try t_.expectEqualSlices(f64, &.{
        1, 0, 1, 0, 0, 0, 0, 0, 0, 1, 0,
        1, 1, 0, 1, 0, 0, 0, 0, 0, 0, 0,
        1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0,
        1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0,
        1, 1, 0, 0, 0, 1, 0, 0, 0, 0, 0,
        1, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1,
        1, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0,
        1, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0,
    }, d.full.x);
    // B = Int - A; A5 = A - A1..A4; B3 = Int - A - B1 - B2.
    try t_.expectEqualSlices(bool, &.{ false, false, true, false, false, false, false, true, false, false, true }, d.aliased);
    try t_.expectEqual(@as(usize, 8), d.rank);
    try t_.expectEqualSlices(usize, &.{ 0, 1, 3, 4, 5, 6, 8, 9 }, d.kept);
    const noint = try h.spec("proc glimmix data=trial; class arm site; model events/n = arm n / solution noint; run;");
    try t_.expect(!noint.model.intercept);
    const dn = try fixedDesign(h.cx, noint, (try prepare(h.cx, noint))[0]);
    try t_.expectEqual(@as(usize, 3), dn.full.p);
    try t_.expectEqual(@as(usize, 3), dn.rank);
    try t_.expectEqualSlices(f64, &.{ 0, 1, 10, 1, 0, 12, 0, 1, 11, 1, 0, 9, 1, 0, 8, 0, 1, 8, 1, 0, 7, 1, 0, 6 }, dn.full.x);
}
