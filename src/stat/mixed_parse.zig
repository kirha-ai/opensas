//! MIXED input/declaration contracts, S154 physical pp.6626-6639,6645,6694.
//! Model statements are retained for mixed_model; no raw token is executed here.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const selection = @import("data_selection.zig");
const groups = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const classes = @import("class_levels.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Method = enum { reml, ml, mivque0, type1, type2, type3 };
pub const Options = struct {
    method: Method = .reml,
    order: classes.Order = .formatted,
    alpha: f64 = 0.05,
    alpha_explicit: bool = false,
    noprofile: bool = false,
    noinfo: bool = false,
    noitprint: bool = false,
    plots_none: bool = false,
    plots: @import("mixed_plots.zig").Options = .{},
    maxiter: usize = 50,
    maxfunc: usize = 150,
    namelen: usize = 20,
    convergence: f64 = 1e-8,
    criterion: @import("mixed_fit.zig").Convergence = .hessian,
    convergence_explicit: bool = false,
    absolute: bool = false,
};
pub const Statement = struct {
    kind: enum { class, model, random, repeated, parms, contrast, estimate },
    tokens: []const lex.Token, // excludes keyword and semicolon
    line: usize,
};
pub const Spec = struct {
    input: proc.ProcInput,
    options: Options,
    roles: selection.Roles,
    by_desc: []const bool,
    notsorted: bool,
    /// null: copy all input variables to future OUTP/OUTPM; empty: copy none.
    id_columns: ?[]const usize,
    statements: []const Statement,
    line: usize,
};
fn is(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn bad(cx: proc.ProcCtx, t: lex.Token) diag.Error {
    return cx.diags.fail(error.ParseError, t.line, "PROC MIXED: unexpected token {s}", .{t.text});
}
fn numeric(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    const at = i.*;
    var sign: f64 = 1;
    if (is(t, i.*, .minus) or is(t, i.*, .plus)) {
        if (is(t, i.*, .minus)) sign = -1;
        i.* += 1;
    }
    if (!is(t, i.*, .number)) return bad(cx, t[@min(at, t.len - 1)]);
    const n = sign * (std.fmt.parseFloat(f64, t[i.*].text) catch return bad(cx, t[i.*]));
    i.* += 1;
    if (!std.math.isFinite(n)) return bad(cx, t[at]);
    return n;
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    if (t.len < 3) return cx.diags.fail(error.ParseError, 0, "PROC MIXED: incomplete declaration", .{});
    var opts = Options{};
    var name: ?[]const u8 = null;
    var i: usize = 2;
    while (i < t.len and !is(t, i, .semicolon) and !is(t, i, .eof)) {
        const token = t[i];
        if (token.tag != .name) return bad(cx, token);
        if (eq(token.text, "plots") or eq(token.text, "plot")) {
            opts.plots = try @import("mixed_plots.zig").parse(cx.arena, cx.diags, t, &i);
            opts.plots_none = opts.plots.none;
            continue;
        }
        i += 1;
        if (eq(token.text, "absolute")) {
            opts.absolute = true;
            continue;
        }
        if (eq(token.text, "convh") or eq(token.text, "convg") or eq(token.text, "convf")) {
            if (opts.convergence_explicit) return proc.failGap(cx.diags, token.line, "PROC MIXED: multiple convergence-criterion options are not independently verified", .{});
            opts.convergence_explicit = true;
            opts.criterion = if (eq(token.text, "convg")) .gradient else if (eq(token.text, "convf")) .function else .hessian;
            if (is(t, i, .eq)) {
                i += 1;
                opts.convergence = try numeric(cx, t, &i);
            }
            if (!(opts.convergence > 0)) return proc.failGap(cx.diags, token.line, "PROC MIXED: nonpositive convergence tolerances are not independently verified", .{});
            continue;
        }
        if (eq(token.text, "noprofile") or eq(token.text, "sigiter")) {
            opts.noprofile = true;
            continue;
        }
        if (eq(token.text, "noinfo") or eq(token.text, "info")) {
            opts.noinfo = eq(token.text, "noinfo");
            continue;
        }
        if (eq(token.text, "noitprint")) {
            opts.noitprint = true;
            continue;
        }
        if (eq(token.text, "namelen") and !is(t, i, .eq)) continue; // default20, optional argument
        const unsupported = [_][]const u8{ "anovaf", "asycorr", "asycov", "cl", "covtest", "dfbw", "empirical", "ic", "itdetails", "lognote", "mmeq", "mmeqsol", "nobound", "noclprint", "ranks", "ratio", "ridge", "scoring", "update" };
        for (unsupported) |option| if (eq(token.text, option)) return proc.failGap(cx.diags, token.line, "PROC MIXED: option {s} is not implemented", .{token.text});
        if (!is(t, i, .eq)) return bad(cx, token);
        i += 1;
        if (eq(token.text, "data")) {
            if (!is(t, i, .name)) return bad(cx, t[@min(i, t.len - 1)]);
            name = t[i].text;
            i += 1;
            if (is(t, i, .dot)) {
                if (!is(t, i + 1, .name)) return bad(cx, t[i]);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
            }
            if (is(t, i, .lparen)) {
                const end = proc.skipParen(t, i);
                if (end <= i or !is(t, end - 1, .rparen)) return bad(cx, t[i]);
                i = end;
            }
        } else if (eq(token.text, "method")) {
            if (!is(t, i, .name)) return bad(cx, t[@min(i, t.len - 1)]);
            opts.method = for (std.enums.values(Method)) |method| {
                if (eq(t[i].text, @tagName(method))) break method;
            } else return bad(cx, t[i]);
            i += 1;
        } else if (eq(token.text, "order")) {
            if (!is(t, i, .name)) return bad(cx, t[@min(i, t.len - 1)]);
            opts.order = for (std.enums.values(classes.Order)) |order| {
                if (eq(t[i].text, @tagName(order))) break order;
            } else return bad(cx, t[i]);
            i += 1;
        } else if (eq(token.text, "alpha") or eq(token.text, "maxiter") or eq(token.text, "maxfunc") or eq(token.text, "namelen")) {
            const number = try numeric(cx, t, &i);
            if (eq(token.text, "alpha")) {
                if (!(number > 0 and number < 1)) return cx.diags.fail(error.ParseError, token.line, "PROC MIXED: ALPHA must be between 0 and 1", .{});
                opts.alpha = number;
                opts.alpha_explicit = true;
            } else {
                if (number < 0 or number != @trunc(number) or number >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return bad(cx, token);
                const integer: usize = @intFromFloat(number);
                if (eq(token.text, "maxiter")) opts.maxiter = integer else if (eq(token.text, "maxfunc")) opts.maxfunc = integer else {
                    if (integer < 20) return cx.diags.fail(error.ParseError, token.line, "PROC MIXED: NAMELEN must be at least 20", .{});
                    opts.namelen = integer;
                }
            }
        } else return bad(cx, token);
    }
    if (!is(t, i, .semicolon)) return bad(cx, t[@min(i, t.len - 1)]);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, t[0].line, "File {s} does not exist.", .{name orelse "_last_"});
    var input = try proc.procInputObs(cx.arena, raw, t, cx.diags);
    var by: groups.Statements = .{};
    var id: ?[]const usize = null;
    var weight: ?usize = null;
    var statements: std.ArrayList(Statement) = .empty;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var model_seen = false;
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
        if (eq(token.text, "by")) {
            try by.read(cx.arena, t, &i);
        } else if (eq(token.text, "id")) {
            if (id != null) return proc.failGap(cx.diags, token.line, "PROC MIXED: repeated ID statements are not yet verified", .{});
            var columns: std.ArrayList(usize) = .empty;
            var j = i + 1;
            while (j < end) for (try lists.next(cx.arena, input.ds, t[0..end], &j, cx.diags)) |n| {
                const ci = input.ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{n});
                if (std.mem.indexOfScalar(usize, columns.items, ci) == null) try columns.append(cx.arena, ci);
            };
            id = columns.items;
        } else if (eq(token.text, "weight")) {
            if (weight != null) return proc.failGap(cx.diags, token.line, "PROC MIXED: repeated WEIGHT statements are not yet verified", .{});
            const variable = try lists.roleVariable(t[0..end], i + 1, false, cx.diags);
            weight = try selection.Roles.numeric(input.ds, variable.text, "WEIGHT", cx.diags, variable.line);
        } else if (eq(token.text, "class") or eq(token.text, "model") or eq(token.text, "random") or eq(token.text, "repeated") or eq(token.text, "parms") or eq(token.text, "contrast") or eq(token.text, "estimate")) {
            if (eq(token.text, "class") and model_seen) return cx.diags.fail(error.ParseError, token.line, "PROC MIXED: CLASS must precede MODEL", .{});
            const kind: @FieldType(Statement, "kind") = if (eq(token.text, "class")) .class else if (eq(token.text, "model")) .model else if (eq(token.text, "random")) .random else if (eq(token.text, "repeated")) .repeated else if (eq(token.text, "parms")) .parms else if (eq(token.text, "contrast")) .contrast else .estimate;
            if (kind == .model) model_seen = true;
            try statements.append(cx.arena, .{ .kind = kind, .tokens = t[i + 1 .. end], .line = token.line });
        } else if (eq(token.text, "format")) {
            try proc.parseProcFormat(cx.arena, t, &i, &formats);
        } else if (eq(token.text, "where") or eq(token.text, "run") or eq(token.text, "quit") or (token.tag == .name and parser.isMidStepSkippable(token.text))) {
            // WHERE is applied by procInputObs; globals are handled by main.
        } else {
            for ([_][]const u8{ "contrast", "estimate", "lsmeans", "lsmestimate", "slice", "store" }) |known| if (eq(token.text, known)) return proc.failGap(cx.diags, token.line, "PROC MIXED: statement {s} is not implemented", .{token.text});
            return bad(cx, token);
        }
        i = end + 1;
    }
    for (formats.items) |f| if (input.ds.indexOf(f.name) == null) return cx.diags.fail(error.ParseError, t[0].line, "Variable {s} not found.", .{f.name});
    input.ds = try groups.withFormats(cx.arena, input.ds, formats.items);
    const by_spec = try by.resolve(cx.arena, input.ds, cx.diags);
    var by_columns: std.ArrayList(usize) = .empty;
    for (by_spec.names) |n| try by_columns.append(cx.arena, input.ds.indexOf(n).?);
    return .{ .input = input, .options = opts, .roles = .{ .by = by_columns.items, .id = id orelse &.{}, .weight = weight }, .by_desc = by_spec.desc, .notsorted = by_spec.notsorted, .id_columns = id, .statements = statements.items, .line = t[0].line };
}
