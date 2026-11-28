//! PROC ANOVA declarations, roles and execution boundary (STAT-ANOVA-001).
//! S154 ch.29: PROC ANOVA statement (physical pp.1115–1117), BY (1117–1118),
//! FREQ (1119), Missing Values (1138–1139).
//!
//! ponytail: CLASS/MODEL column resolution, the design and the least-squares
//! kernel are GLM's. That is only valid where ANOVA SS equals sequential SS:
//! one-way models and balanced complete crossings. Everything else stays a
//! loud D-009 gap instead of printing GLM numbers under an ANOVA heading.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const glm = @import("glm.zig");
const selection = @import("data_selection.zig");
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;

pub const Spec = glm.Spec;
pub const Design = glm.design.Design;

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn oneOf(text: []const u8, comptime names: anytype) bool {
    inline for (names) |name| if (eq(text, name)) return true;
    return false;
}

/// ANOVA's own grammar gate. Runs before the shared CLASS/MODEL reader so
/// that GLM-only syntax can never be accepted under PROC ANOVA.
fn check(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!void {
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        const line = t[i].line;
        if (kw(t, i, "data")) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: DATA= requires a dataset", .{});
            i += 3;
            if (at(t, i, .dot)) i += 2;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (kw(t, i, "manova") or kw(t, i, "multipass") or kw(t, i, "noprint")) {
            i += 1;
        } else if (kw(t, i, "namelen")) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .number)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: NAMELEN= requires an integer", .{});
            const n = std.fmt.parseInt(usize, t[i + 2].text, 10) catch return cx.diags.fail(error.ParseError, line, "PROC ANOVA: NAMELEN= requires an integer", .{});
            if (n < 20 or n > 200) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: NAMELEN must be 20 through 200", .{});
            i += 3;
        } else if (kw(t, i, "order")) {
            if (!at(t, i + 1, .eq) or !at(t, i + 2, .name) or !oneOf(t[i + 2].text, .{ "data", "formatted", "freq", "internal" })) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: ORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
            i += 3;
        } else if (kw(t, i, "outstat")) {
            return proc.failGap(cx.diags, line, "PROC ANOVA: OUTSTAT= is not implemented", .{});
        } else if (kw(t, i, "plots")) {
            if (!at(t, i + 1, .eq) or !kw(t, i + 2, "none")) return proc.failGap(cx.diags, line, "PROC ANOVA: PLOTS requests other than PLOTS=NONE are not implemented", .{});
            i += 3;
        } else return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid PROC statement option {s}", .{t[i].text});
    }
    if (!at(t, i, .semicolon)) return cx.diags.fail(error.ParseError, 0, "PROC ANOVA: expected semicolon", .{});
    i += 1;
    var ended = false;
    var model_seen = false;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        const line = t[i].line;
        const word = t[i].text;
        if (!at(t, i, .name)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid statement", .{});
        if (oneOf(word, .{ "run", "quit" })) {
            ended = true;
        } else if (oneOf(word, .{ "weight", "id", "lsmeans", "contrast", "estimate", "random", "output", "store", "code" })) {
            return cx.diags.fail(error.ParseError, line, "PROC ANOVA: the {s} statement is not valid in PROC ANOVA", .{word});
        } else if (ended) {
            // pp.1117–1119: ABSORB/BY/FREQ after the first RUN are ignored.
            if (oneOf(word, .{ "by", "freq", "absorb" })) {} else if (oneOf(word, .{ "class", "model" })) {
                return cx.diags.fail(error.ParseError, line, "PROC ANOVA: {s} cannot be declared after the first RUN", .{word});
            } else if (oneOf(word, .{ "means", "manova", "test", "repeated" })) {
                return proc.failGap(cx.diags, line, "PROC ANOVA: interactive {s} is not implemented", .{word});
            } else return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid statement {s}", .{word});
        } else if (oneOf(word, .{ "absorb", "manova", "means", "repeated", "test" })) {
            return proc.failGap(cx.diags, line, "PROC ANOVA: the {s} statement is not implemented", .{word});
        } else if (eq(word, "class")) {
            if (model_seen) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: CLASS must precede MODEL", .{});
            for (t[i + 1 .. end]) |token| if (token.tag == .lparen or token.tag == .slash) return proc.failGap(cx.diags, token.line, "PROC ANOVA: CLASS REF= and TRUNCATE options are not implemented", .{});
        } else if (eq(word, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: only one MODEL statement is allowed", .{});
            model_seen = true;
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) j += 1;
            j += 1;
            while (j < end) : (j += 1) {
                if (oneOf(t[j].text, .{ "int", "intercept", "nouni" })) return proc.failGap(cx.diags, t[j].line, "PROC ANOVA: MODEL option {s} is not implemented", .{t[j].text});
                return cx.diags.fail(error.ParseError, t[j].line, "PROC ANOVA: invalid MODEL option {s}", .{t[j].text});
            }
        } else if (eq(word, "freq")) {
            if (end != i + 2 or !at(t, i + 1, .name)) return cx.diags.fail(error.ParseError, line, "PROC ANOVA: FREQ requires exactly one variable", .{});
        } else if (!oneOf(word, .{ "by", "where", "format", "label", "attrib" })) {
            return cx.diags.fail(error.ParseError, line, "PROC ANOVA: invalid statement {s}", .{word});
        }
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC ANOVA: a MODEL statement is required", .{});
}

pub fn parse(cx: proc.ProcCtx, tokens: []const lex.Token) diag.Error!Spec {
    try check(cx, tokens);
    var spec = try glm.parse(cx, tokens);
    // ANOVA prints one "Anova SS" table; never ask the kernel for Type II–IV.
    spec.ss1 = true;
    for (spec.effects) |effect| for (effect.variables) |ci| {
        if (std.mem.indexOfScalar(usize, spec.classes, ci) == null) return proc.failGap(cx.diags, 0, "PROC ANOVA: continuous effect {s} is not implemented; independent effects must use CLASS variables", .{spec.input.ds.columns.items[ci].name});
    };
    return spec;
}

/// Missing-value rule (pp.1138–1139): one response uses rows complete for
/// that response and every independent variable; the MANOVA option makes
/// GLM's builder require every response. FREQ <1 or missing drops the row,
/// fractional FREQ is truncated (p.1119).
pub fn build(cx: proc.ProcCtx, spec: Spec, group: selection.View, response: usize) diag.Error!Design {
    return glm.design.build(cx, spec, group, response);
}

/// Sequential SS is the ANOVA SS only for one-way models or when every cell
/// of the complete crossing of the model's CLASS variables has the same
/// (frequency-expanded) count.
pub fn balanced(a: A, spec: Spec, d: Design) !bool {
    if (spec.effects.len == 1 and spec.effects[0].variables.len == 1) return true;
    var used: std.ArrayList(usize) = .empty;
    for (d.classes, 0..) |class, k| {
        for (spec.effects) |effect| if (std.mem.indexOfScalar(usize, effect.variables, class.column) != null) {
            try used.append(a, k);
            break;
        };
    }
    var cells: usize = 1;
    for (used.items) |k| cells = std.math.mul(usize, cells, d.classes[k].levels.len) catch return false;
    if (cells == 0) return false;
    const counts = try a.alloc(f64, cells);
    @memset(counts, 0);
    for (0..d.n) |i| {
        var cell: usize = 0;
        for (used.items) |k| cell = cell * d.classes[k].levels.len + (d.classes[k].row_levels[i] orelse return false);
        counts[cell] += d.frequencies[i];
    }
    for (counts) |count| if (count != counts[0] or count <= 0) return false;
    return true;
}

fn number(a: A, value: f64, decimals: usize) ![]const u8 {
    if (!std.math.isFinite(value)) return ".";
    return @import("../format.zig").apply(a, .{ .num = value }, try std.fmt.allocPrint(a, "32.{d}", .{decimals}));
}
fn probability(a: A, value: f64) ![]const u8 {
    return if (std.math.isFinite(value) and value < 0.0001) "<.0001" else number(a, value, 4);
}
fn places(maximum: f64, digits: i32) usize {
    if (!(maximum > 0) or !std.math.isFinite(maximum)) return @intCast(digits);
    const exponent: i32 = @intFromFloat(@floor(@log10(maximum)));
    return @intCast(@max(0, @min(12, digits - exponent)));
}
fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec, group: selection.View) !void {
    if (cx.listing_titles) |titles| {
        try titles.emitTitles(cx.arena, out);
    } else if (cx.graph_title) |text| try out.print(cx.arena, "\n{s}\n", .{text});
    if (spec.by.len > 0 and group.observations.len > 0) {
        try @import("by_groups.zig").appendLine(cx.arena, out, spec.input.ds, group.observations[0].cells, spec.by);
        if (out.items.len > 0 and out.items[out.items.len - 1] != '\n') try out.append(cx.arena, '\n');
    }
    try out.appendSlice(cx.arena, "\nThe ANOVA Procedure\n");
}

pub fn execute(cx: proc.ProcCtx, out: *std.ArrayList(u8), spec: Spec) diag.Error!void {
    const a = cx.arena;
    const view = try selection.View.init(a, spec.input, .{ .by = spec.by, .frequency = spec.freq });
    const groups = try view.groups(a, spec.descending, spec.notsorted, cx.diags);
    if (groups.len == 0) return cx.diags.fail(error.ExecError, 0, "PROC ANOVA: no observations in the input data set", .{});
    const graphics_on = if (cx.graphics) |g| g.enabled == true else false;
    for (groups) |group| {
        var first: ?Design = null;
        for (spec.responses) |response| {
            const d = try build(cx, spec, group, response);
            if (d.n == 0) return cx.diags.fail(error.ExecError, 0, "PROC ANOVA: no valid observations for dependent variable {s}", .{spec.input.ds.columns.items[response].name});
            if (!try balanced(a, spec, d)) return proc.failGap(cx.diags, 0, "PROC ANOVA: unbalanced or incomplete multi-effect designs are not implemented", .{});
            if (first) |f| {
                // p.1139: differing missing patterns form dependent-variable
                // groups with their own displays; that listing is not validated.
                if (!std.mem.eql(usize, f.source_rows, d.source_rows)) return proc.failGap(cx.diags, 0, "PROC ANOVA: dependent variables with different missing-value patterns are not implemented; use the MANOVA option", .{});
            } else first = d;
            var result = try glm.fitDesign(cx, spec, d);
            defer result.deinit(a);
            if (result.model.fit.rank < d.p) return proc.failGap(cx.diags, 0, "PROC ANOVA: rank-deficient models are not implemented", .{});
            if (spec.noprint) continue;
            if (graphics_on and !spec.plots_none and spec.effects.len == 1 and spec.effects[0].variables.len == 1) return proc.failGap(cx.diags, 0, "PROC ANOVA: the default one-way box plot is not implemented; specify PLOTS=NONE or ODS GRAPHICS OFF", .{});
            const fitted = result.model.fit;
            if (first.?.response == response) {
                try heading(cx, out, spec, group);
                try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
                for (d.classes) |class| {
                    try out.print(a, "\n{s} {d}", .{ spec.input.ds.columns.items[class.column].name, class.levels.len });
                    for (class.levels) |level| try out.print(a, " {s}", .{level.label});
                    try out.append(a, '\n');
                }
                try out.print(a, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ d.read, d.n });
                // ponytail: FREQ summary row follows the GLM listing; no SAS
                // ANOVA reference for this row was available to this ticket.
                if (spec.freq != null) try out.print(a, "Sum of Frequencies Used {d}\n", .{fitted.n_used});
            }
            const model = fitted.modelStats(true);
            try heading(cx, out, spec, group);
            const name = spec.input.ds.columns.items[response].name;
            try out.print(a, "\nDependent Variable: {s}\n\nSum of\nSource DF Squares Mean Square F Value Pr > F\n", .{name});
            const decimals = places(@max(fitted.sst, @max(model.ss_model, fitted.sse)), 9);
            try out.print(a, "\nModel {d} {s} {s} {s} {s}\n\nError {d} {s} {s}\n\nCorrected Total {d} {s}\n", .{
                model.df_model,  try number(a, model.ss_model, decimals), try number(a, model.ms_model, decimals), try number(a, model.f_value, 2), try probability(a, model.p_value),
                fitted.df_error, try number(a, fitted.sse, decimals),     try number(a, fitted.mse, decimals),     model.df_total,                  try number(a, fitted.sst, decimals),
            });
            const cv = 100 * @sqrt(fitted.mse) / fitted.y_mean;
            try out.print(a, "\nR-Square Coeff Var Root MSE {s} Mean\n\n{s} {s} {s} {s}\n", .{
                name, try number(a, model.r_square, 6), try number(a, cv, places(@abs(cv), 6)), try number(a, @sqrt(fitted.mse), 6), try number(a, fitted.y_mean, places(@abs(fitted.y_mean), 6)),
            });
            var maximum: f64 = 0;
            for (result.type_i) |effect| maximum = @max(maximum, @abs(effect.ss));
            const effect_decimals = places(maximum, 9);
            try out.appendSlice(a, "\nSource DF Anova SS Mean Square F Value Pr > F\n\n");
            for (spec.effects, result.type_i) |effect, value| try out.print(a, "{s} {d} {s} {s} {s} {s}\n", .{
                effect.name, value.df, try number(a, value.ss, effect_decimals), try number(a, value.ms, effect_decimals), try number(a, value.f_value, 2), try probability(a, value.p_value),
            });
        }
    }
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    const spec = try parse(cx, tokens);
    try execute(cx, out, spec);
}

/// ponytail: one process-wide flag instead of a session object threaded
/// through the step runner (which other procedures are editing in parallel).
/// It records only that a PROC ANOVA step is still open for interactive
/// statements (p.1138); the model itself is not retained because no
/// interactive statement is implemented yet.
var interactive = false;

/// CLI entry: runs the step and leaves the procedure open unless BY was used
/// or QUIT closed it (pp.1118, 1138).
pub fn runStep(cx: proc.ProcCtx, out: *std.ArrayList(u8), tokens: []const lex.Token) diag.Error!void {
    interactive = false;
    const spec = try parse(cx, tokens);
    try execute(cx, out, spec);
    var quit = false;
    for (tokens, 0..) |token, i| if ((i == 0 or tokens[i - 1].tag == .semicolon) and token.tag == .name and eq(token.text, "quit")) {
        quit = true;
    };
    interactive = spec.by.len == 0 and !quit;
}

/// Statement group arriving after an open PROC ANOVA step. Returns true when
/// it was consumed here. Valid interactive requests are D-009 gaps, never
/// open-code user errors; any other step closes the procedure.
pub fn continuation(diags: *diag.Diagnostics, tokens: []const lex.Token) diag.Error!bool {
    if (!interactive) return false;
    if (tokens.len == 0 or tokens[0].tag != .name) return false;
    const word = tokens[0].text;
    if (oneOf(word, .{ "means", "manova", "test", "repeated" })) return proc.failGap(diags, tokens[0].line, "PROC ANOVA: interactive {s} is not implemented", .{word});
    if (eq(word, "quit")) {
        interactive = false;
        return true;
    }
    // RUN executes pending (none) statements; ABSORB/BY/FREQ after the first
    // RUN are ignored (pp.1117–1119).
    if (oneOf(word, .{ "run", "by", "freq", "absorb" })) return true;
    interactive = false;
    return false;
}

test "ANOVA001 open procedure turns interactive requests into gaps until another step or QUIT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var diagnostics = diag.Diagnostics.init(a);
    defer interactive = false;
    defer diag.resetGap();
    const means = try lex.tokenize(a, "means g; run;", &diagnostics);
    try std.testing.expect(!try continuation(&diagnostics, means));
    interactive = true;
    try std.testing.expect(try continuation(&diagnostics, try lex.tokenize(a, "run;", &diagnostics)));
    try std.testing.expect(try continuation(&diagnostics, try lex.tokenize(a, "freq f;", &diagnostics)));
    diag.resetGap();
    try std.testing.expectError(error.ParseError, continuation(&diagnostics, means));
    try std.testing.expectEqual(@as(u8, 2), diag.exitCode(diag.gapHit(), diagnostics.hasErrors()));
    try std.testing.expect(!try continuation(&diagnostics, try lex.tokenize(a, "proc print; run;", &diagnostics)));
    try std.testing.expect(!interactive);
    interactive = true;
    try std.testing.expect(try continuation(&diagnostics, try lex.tokenize(a, "quit;", &diagnostics)));
    try std.testing.expect(!try continuation(&diagnostics, means));
}

test {
    _ = @import("anova_tests.zig");
}
