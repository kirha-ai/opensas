//! REG declarations and data roles. SAS/STAT 15.4, physical pp.8560–8603.
const std = @import("std");
const proc = @import("../proc.zig");
const lex = @import("../lexer.zig");
const diag = @import("../diag.zig");
const Dataset = @import("../dataset.zig").Dataset;
const lists = @import("variable_lists.zig");
const by_groups = @import("by_groups.zig");
const eq = std.ascii.eqlIgnoreCase;
const ridge_parse = @import("reg_ridge_parse.zig");
pub const Model = struct {
    label: []const u8,
    statement_index: usize = 0,
    dependent: usize,
    regressors: []const usize,
    intercept: bool = true,
    alpha: f64 = 0.05,
    singular: f64 = 1e-9,
    residual: bool = false,
    clm: bool = false,
    cli: bool = false,
    tol: bool = false,
    vif: bool = false,
};
pub const Spec = struct {
    ds: *Dataset,
    models: []const Model,
    required: []const usize,
    by: []const usize,
    descending: []const bool,
    notsorted: bool,
    freq: ?usize = null,
    weight: ?usize = null,
    ids: []const usize = &.{},
    noprint: bool = false,
    outest: ?[]const u8 = null,
    covout: bool = false,
    output_variables: []const usize = &.{},
    ridge: []const f64 = &.{},
    outvif: bool = false,
    ridge_plots: ridge_parse.Plots = .{},
};
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, s: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, s);
}
fn appendUnique(a: std.mem.Allocator, dest: *std.ArrayList(usize), cols: []const usize) !void {
    for (cols) |c| if (std.mem.indexOfScalar(usize, dest.items, c) == null) {
        try dest.append(a, c);
    };
}
pub fn columns(cx: proc.ProcCtx, ds: *Dataset, t: []const lex.Token, numeric_only: bool) diag.Error![]const usize {
    var names: std.ArrayList([]const u8) = .empty;
    try lists.append(cx.arena, ds, t, &names, cx.diags);
    var cols: std.ArrayList(usize) = .empty;
    for (names.items) |name| {
        const c = ds.indexOf(name) orelse return cx.diags.fail(error.ParseError, if (t.len > 0) t[0].line else 0, "Variable {s} not found.", .{name});
        if (numeric_only and ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, if (t.len > 0) t[0].line else 0, "Variable {s} must be numeric.", .{name});
        try appendUnique(cx.arena, &cols, &.{c});
    }
    return cols.items;
}
fn numeric(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.* + 1, .eq) or !at(t, i.* + 2, .number)) return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG: expected a numeric option value", .{});
    const v = std.fmt.parseFloat(f64, t[i.* + 2].text) catch return cx.diags.fail(error.ParseError, t[i.*].line, "PROC REG: invalid numeric option value", .{});
    i.* += 3;
    if (!std.math.isFinite(v) or v <= 0 or v >= 1) return cx.diags.fail(error.ParseError, t[i.* - 1].line, "PROC REG: option value must be between 0 and 1", .{});
    return v;
}
fn unsupported(cx: proc.ProcCtx, tok: lex.Token, known: []const []const u8) diag.Error {
    for (known) |name| if (eq(tok.text, name)) return proc.failGap(cx.diags, tok.line, "PROC REG: {s} is not implemented", .{tok.text});
    return cx.diags.fail(error.ParseError, tok.line, "PROC REG: invalid option or statement {s}", .{tok.text});
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var i: usize = 2;
    var name: ?[]const u8 = null;
    var qualified_name_at: ?usize = null;
    var alpha: f64 = 0.05;
    var singular: f64 = 1e-9;
    var noprint = false;
    var plots_none = false;
    var outest: ?[]const u8 = null;
    var covout = false;
    var ridge: []const f64 = &.{};
    var outvif = false;
    var ridge_plots: ridge_parse.Plots = .{};
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (kw(t, i, "data")) {
            if (name != null) return proc.failGap(cx.diags, t[i].line, "PROC REG: repeated DATA= declarations are not implemented", .{});
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: DATA= requires a dataset", .{});
            name = t[i + 2].text;
            i += 3;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: expected a member name", .{});
                qualified_name_at = i - 1;
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
            }
            if (at(t, i, .lparen)) {
                const end = proc.skipParen(t, i);
                if (!at(t, end - 1, .rparen)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: unclosed dataset options", .{});
                var depth: usize = 0;
                for (t[i + 1 .. end - 1], i + 1..) |tok, k| {
                    if (tok.tag == .lparen) depth += 1 else if (tok.tag == .rparen) {
                        if (depth > 0) depth -= 1;
                    }
                    if (depth == 0 and tok.tag == .name and eq(tok.text, "type") and at(t, k + 1, .eq)) return proc.failGap(cx.diags, tok.line, "PROC REG: summary TYPE= input is not implemented", .{});
                }
                i = end;
            }
        } else if (kw(t, i, "outest")) {
            if (outest != null) return proc.failGap(cx.diags, t[i].line, "PROC REG: repeated OUTEST= declarations are not implemented", .{});
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: OUTEST= requires a dataset", .{});
            outest = t[i + 2].text;
            i += 3;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: expected an OUTEST member name", .{});
                outest = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ outest.?, t[i + 1].text });
                i += 2;
            }
            if (at(t, i, .lparen)) return proc.failGap(cx.diags, t[i].line, "PROC REG: OUTEST dataset options are not implemented", .{});
        } else if (kw(t, i, "covout")) {
            covout = true;
            i += 1;
        } else if (kw(t, i, "ridge")) {
            if (ridge.len > 0) return proc.failGap(cx.diags, t[i].line, "PROC REG: repeated RIDGE declarations are not implemented", .{});
            ridge = try ridge_parse.constants(cx, t, &i);
        } else if (kw(t, i, "outvif")) {
            outvif = true;
            i += 1;
        } else if (kw(t, i, "plots")) {
            if (ridge_parse.matches(t, i)) {
                ridge_plots = try ridge_parse.plots(cx, t, &i);
                continue;
            }
            const start = i;
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: expected PLOTS=request", .{});
            i += 2;
            if (kw(t, i, "none")) {
                plots_none = true;
                i += 1;
                continue;
            }
            plots_none = false;
            if (kw(t, i, "residualbypredicted")) {
                i += 1;
            } else if (kw(t, i, "predictions")) {
                i += 1;
                if (!at(t, i, .lparen) or !kw(t, i + 1, "x") or !at(t, i + 2, .eq) or !at(t, i + 3, .name) or !at(t, i + 4, .rparen)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: PREDICTIONS requires (X=variable)", .{});
                i += 5;
            } else return proc.failGap(cx.diags, t[i].line, "PROC REG: this PLOTS request is not implemented", .{});
            if (cx.graphics) |g| {
                if (g.enabled != false) return proc.failGap(cx.diags, t[start].line, "PROC REG: graphical output is not implemented", .{});
            } else return proc.failGap(cx.diags, t[start].line, "PROC REG: PLOTS requires a graphics consumer", .{});
            try cx.diags.warnStatus(0, "You must enable ODS graphics before requesting plots with the PLOTS option in the PROC REG statement.", .{});
        } else if (kw(t, i, "alpha")) {
            alpha = try numeric(cx, t, &i);
        } else if (kw(t, i, "singular")) {
            singular = try numeric(cx, t, &i);
        } else if (kw(t, i, "noprint")) {
            noprint = true;
            i += 1;
        } else return unsupported(cx, t[i], &.{ "all", "corr", "covout", "edf", "outest", "outsscp", "outseb", "outstb", "outvif", "pcomit", "plots", "press", "ridge", "rsquare", "simple", "tableout", "usscp" });
    }
    if (!at(t, i, .semicolon)) return cx.diags.fail(error.ParseError, 0, "PROC REG: expected semicolon", .{});
    if (!noprint and !plots_none and ridge.len == 0) if (cx.graphics) |g| {
        if (g.enabled != false) return proc.failGap(cx.diags, 0, "PROC REG: default ODS graphics are not implemented; use ODS GRAPHICS OFF or PLOTS=NONE", .{});
    };
    ridge_plots.disabled = plots_none;
    if (ridge.len > 0 and outest == null) return cx.diags.fail(error.ParseError, 0, "PROC REG RIDGE requires OUTEST=", .{});
    if (ridge.len == 0 and (outvif or ridge_plots.requested)) return cx.diags.fail(error.ParseError, 0, "PROC REG: OUTVIF and ridge plots require RIDGE=", .{});
    if (ridge.len > 0 and covout) return proc.failGap(cx.diags, 0, "PROC REG: COVOUT with RIDGE is not implemented", .{});
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ExecError, 0, "File {s} does not exist.", .{name orelse "_LAST_"});
    // PROC input option filtering expects DATA= followed by one name token.
    // Native dispatch folds declared librefs, but built-in SASHELP and direct
    // module callers can still supply the lexical libref . member triple.
    var input_tokens: std.ArrayList(lex.Token) = .empty;
    if (qualified_name_at) |start| {
        try input_tokens.appendSlice(cx.arena, t[0..start]);
        try input_tokens.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[start].line });
        try input_tokens.appendSlice(cx.arena, t[start + 3 ..]);
    }
    const ds = try proc.procInput(cx.arena, raw, if (qualified_name_at != null) input_tokens.items else t, cx.diags);
    var models: std.ArrayList(Model) = .empty;
    var required: std.ArrayList(usize) = .empty;
    var output_variables: std.ArrayList(usize) = .empty;
    var by_statements: by_groups.Statements = .{};
    var freq: ?usize = null;
    var weight: ?usize = null;
    var ids: []const usize = &.{};
    i += 1;
    var ended = false;
    var model_number: usize = 0;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: expected semicolon", .{});
        var label: ?[]const u8 = null;
        if (at(t, i, .name) and at(t, i + 1, .colon)) {
            label = t[i].text;
            i += 2;
        }
        if (kw(t, i, "run") or kw(t, i, "quit")) {
            if (end != i + 1) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: invalid execution boundary", .{});
            ended = true;
        } else if (ended) {
            return proc.failGap(cx.diags, t[i].line, "PROC REG: interactive continuation is not implemented", .{});
        } else if (kw(t, i, "model")) {
            model_number += 1;
            var equal = i + 1;
            while (equal < end and !at(t, equal, .eq)) equal += 1;
            if (equal == end) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG MODEL requires =", .{});
            const dependents = try columns(cx, ds, t[i + 1 .. equal], true);
            if (dependents.len == 0) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG MODEL requires a response", .{});
            var slash = equal + 1;
            while (slash < end and !at(t, slash, .slash)) slash += 1;
            const regressors = try columns(cx, ds, t[equal + 1 .. slash], true);
            var model: Model = .{ .statement_index = model_number, .label = label orelse try std.fmt.allocPrint(cx.arena, "MODEL{d}", .{model_number}), .dependent = dependents[0], .regressors = regressors, .alpha = alpha, .singular = singular };
            var j = slash + 1;
            while (j < end) {
                if (kw(t, j, "r")) {
                    model.residual = true;
                    j += 1;
                } else if (kw(t, j, "clm")) {
                    model.clm = true;
                    j += 1;
                } else if (kw(t, j, "cli")) {
                    model.cli = true;
                    j += 1;
                } else if (kw(t, j, "noint")) {
                    model.intercept = false;
                    j += 1;
                } else if (kw(t, j, "tol")) {
                    model.tol = true;
                    j += 1;
                } else if (kw(t, j, "vif")) {
                    model.vif = true;
                    j += 1;
                } else if (kw(t, j, "alpha")) {
                    model.alpha = try numeric(cx, t[0..end], &j);
                } else if (kw(t, j, "singular")) {
                    model.singular = try numeric(cx, t[0..end], &j);
                } else return unsupported(cx, t[j], &.{ "r", "p", "clm", "cli", "clb", "selection", "influence", "dw", "dwprob", "acov", "hcc", "white", "stb", "covb", "corrb", "collin", "collinoint", "ss1", "ss2", "scorr1", "scorr2", "pcorr1", "pcorr2", "partial", "all", "press", "aic", "sbc", "cp", "mse", "edf", "rsquare", "adjrsq", "b", "seb" });
            }
            if ((model.residual or model.clm or model.cli) and !(model.residual and model.clm and model.cli)) return proc.failGap(cx.diags, t[i].line, "PROC REG: diagnostic listing currently requires R CLM CLI together", .{});
            if (!model.intercept and regressors.len == 0) return cx.diags.fail(error.ParseError, t[i].line, "PROC REG: empty model", .{});
            for (dependents) |dep| {
                model.dependent = dep;
                try models.append(cx.arena, model);
            }
            try appendUnique(cx.arena, &output_variables, regressors);
            try appendUnique(cx.arena, &output_variables, dependents);
            try appendUnique(cx.arena, &required, dependents);
            try appendUnique(cx.arena, &required, regressors);
        } else if (kw(t, i, "var")) {
            const declared = try columns(cx, ds, t[i + 1 .. end], true);
            try appendUnique(cx.arena, &required, declared);
            try appendUnique(cx.arena, &output_variables, declared);
        } else if (kw(t, i, "by")) {
            try by_statements.read(cx.arena, t, &i);
        } else if (kw(t, i, "id")) {
            ids = try columns(cx, ds, t[i + 1 .. end], false);
        } else if (kw(t, i, "freq") or kw(t, i, "weight")) {
            const tok = try lists.roleVariable(t[0..end], i + 1, false, cx.diags);
            const cols = try columns(cx, ds, &.{tok}, true);
            const role = if (kw(t, i, "freq")) &freq else &weight;
            if (role.* != null) return proc.failGap(cx.diags, t[i].line, "PROC REG: repeated {s} statements are not implemented", .{t[i].text});
            role.* = cols[0];
        } else if (!kw(t, i, "where")) return unsupported(cx, t[i], &.{ "add", "delete", "print", "output", "test", "restrict", "reweight", "mtest", "plot", "paint", "code", "performance" });
        i = end + 1;
    }
    if (models.items.len == 0) return proc.failGap(cx.diags, 0, "PROC REG: analysis without MODEL is not implemented", .{});
    if (ridge.len > 0) for (models.items) |*model| {
        model.intercept = true;
    }; // documented: RIDGE ignores NOINT
    const by = try by_statements.resolve(cx.arena, ds, cx.diags);
    const bcols = try cx.arena.alloc(usize, by.names.len);
    for (by.names, 0..) |n, j| bcols[j] = ds.indexOf(n).?;
    return .{ .ds = ds, .models = models.items, .required = required.items, .by = bcols, .descending = by.desc, .notsorted = by.notsorted, .freq = freq, .weight = weight, .ids = ids, .noprint = noprint, .outest = outest, .covout = covout, .output_variables = output_variables.items, .ridge = ridge, .outvif = outvif, .ridge_plots = ridge_plots };
}
