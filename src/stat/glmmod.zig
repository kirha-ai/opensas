//! GLMMOD design/output path, separate from GLM's inference contrasts.
//! S154 physical pp.4236-4241 specify declarations and OUTPARM/OUTDESIGN;
//! physical pp.414-418 specify full-level effect coding and column order.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const lists = @import("variable_lists.zig");
const by = @import("by_groups.zig");
const matrix = @import("design_matrix.zig");
const class_levels = @import("class_levels.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
pub const Spec = struct {
    input: proc.ProcInput,
    model: matrix.Spec,
    /// MODEL dependents in statement order (model.response is the first).
    responses: []const usize = &.{},
    outdesign: ?[]const u8 = null,
    outparm: ?[]const u8 = null,
    prefix: []const u8 = "Col",
    namelen: usize = 20,
    zerobased: bool = false,
    noprint: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    freq: ?usize = null,
    weight: ?usize = null,
};
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC GLMMOD: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn member(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        i.* += 1;
        if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i.*].text });
        i.* += 1;
    }
    return name;
}
fn variable(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!usize {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    const ci = ds.indexOf(t[i.*].text) orelse return cx.diags.fail(error.ParseError, t[i.*].line, "Variable {s} not found.", .{t[i.*].text});
    i.* += 1;
    return ci;
}
/// Effect validation messages are the SAS 9.4 GLMMOD wording (live probe
/// 2026-11-28): a character non-CLASS factor and a continuous nesting variable.
fn factor(cx: proc.ProcCtx, ds: *const Dataset, classes: []const usize, t: []const lex.Token, i: *usize, inside: bool) diag.Error!usize {
    const line = if (i.* < t.len) t[i.*].line else 0;
    const ci = try variable(cx, ds, t, i);
    if (std.mem.indexOfScalar(usize, classes, ci) != null) return ci;
    if (inside) return cx.diags.fail(error.ParseError, line, "Nesting of continuous variable not allowed.", .{});
    if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, line, "Variable {s} should be either numeric or specified in the CLASS statement.", .{ds.columns.items[ci].name});
    return ci;
}
fn term(cx: proc.ProcCtx, ds: *const Dataset, classes: []const usize, t: []const lex.Token, i: *usize) diag.Error!matrix.Effect {
    var factors: std.ArrayList(usize) = .empty;
    var nested: std.ArrayList(usize) = .empty;
    try factors.append(cx.arena, try factor(cx, ds, classes, t, i, false));
    while (at(t, i.*, .star)) {
        i.* += 1;
        try factors.append(cx.arena, try factor(cx, ds, classes, t, i, false));
    }
    if (at(t, i.*, .lparen)) {
        const line = t[i.*].line;
        i.* += 1;
        while (i.* < t.len and !at(t, i.*, .rparen)) {
            if (at(t, i.*, .star)) {
                i.* += 1;
                continue;
            }
            try nested.append(cx.arena, try factor(cx, ds, classes, t, i, true));
        }
        if (nested.items.len == 0 or !at(t, i.*, .rparen)) return invalid(cx, t, i.*);
        i.* += 1;
        // SAS accepts a factor that is both crossed and nesting (g*h(g)); the
        // shared kernel rejects it, so keep it a visible gap, not rc 1.
        for (nested.items) |n| if (std.mem.indexOfScalar(usize, factors.items, n) != null)
            return proc.failGap(cx.diags, line, "PROC GLMMOD: a crossed factor that also appears in its own nesting list is not implemented", .{});
    }
    return .{ .factors = factors.items, .nested = nested.items };
}
fn effects(cx: proc.ProcCtx, ds: *const Dataset, classes: []const usize, t: []const lex.Token, out: *std.ArrayList(matrix.Effect)) diag.Error!void {
    var i: usize = 0;
    while (i < t.len) {
        var chain: std.ArrayList(matrix.Effect) = .empty;
        try chain.append(cx.arena, try term(cx, ds, classes, t, &i));
        while (at(t, i, .pipe)) {
            i += 1;
            try chain.append(cx.arena, try term(cx, ds, classes, t, &i));
        }
        var degree: usize = std.math.maxInt(usize);
        if (at(t, i, .at)) {
            i += 1;
            if (!at(t, i, .number)) return invalid(cx, t, i);
            degree = std.fmt.parseInt(usize, t[i].text, 10) catch return invalid(cx, t, i);
            if (degree == 0) return invalid(cx, t, i);
            i += 1;
        }
        // ponytail: bounded bar expansion avoids constructing exponential-size
        // requests accidentally. The ordinary/crossed/nested path has no such cap.
        if (chain.items.len > 16) return proc.failGap(cx.diags, 0, "PROC GLMMOD: bar expansion beyond sixteen terms is not implemented", .{});
        const end = @as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(chain.items.len));
        // GLM pp.4096-4097 (Searle rules): combined nesting lists drop
        // duplicates; an effect with a variable both crossed and nested is
        // discarded; @n bounds the number of variables, nesting ones included
        // (A | B(A) | C@2 is A B(A) C A*C).
        for (1..end) |mask| {
            var factors: std.ArrayList(usize) = .empty;
            var nested: std.ArrayList(usize) = .empty;
            for (chain.items, 0..) |e, k| if (mask & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k))) != 0) {
                try factors.appendSlice(cx.arena, e.factors);
                for (e.nested) |n| if (std.mem.indexOfScalar(usize, nested.items, n) == null) try nested.append(cx.arena, n);
            };
            if (factors.items.len + nested.items.len > degree) continue;
            var overlap = false;
            for (nested.items) |n| if (std.mem.indexOfScalar(usize, factors.items, n) != null) {
                overlap = true;
            };
            if (overlap) continue;
            try out.append(cx.arena, .{ .factors = factors.items, .nested = nested.items });
        }
    }
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var i: usize = 2;
    var name: ?[]const u8 = null;
    var result: Spec = .{ .input = undefined, .model = .{ .response = 0, .effects = &.{} } };
    var qualified_start: ?usize = null;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (kw(t, i, "noprint")) {
            result.noprint = true;
            i += 1;
            continue;
        }
        if (kw(t, i, "zerobased")) {
            result.zerobased = true;
            i += 1;
            continue;
        }
        const option = t[i];
        if (!at(t, i + 1, .eq)) return invalid(cx, t, i);
        i += 2;
        if (eq(option.text, "data")) {
            const start = i;
            name = try member(cx, t, &i);
            if (i - start == 3) qualified_start = start;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(option.text, "outdesign")) result.outdesign = try member(cx, t, &i) else if (eq(option.text, "outparm")) result.outparm = try member(cx, t, &i) else if (eq(option.text, "prefix")) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            result.prefix = t[i].text;
            i += 1;
        } else if (eq(option.text, "order")) {
            if (!at(t, i, .name)) return invalid(cx, t, i);
            const v = t[i].text;
            result.model.order = if (eq(v, "data")) .data else if (eq(v, "internal")) .internal else if (eq(v, "freq")) .freq else if (eq(v, "formatted")) .formatted else return invalid(cx, t, i);
            i += 1;
        } else if (eq(option.text, "namelen")) {
            if (!at(t, i, .number)) return invalid(cx, t, i);
            result.namelen = std.fmt.parseInt(usize, t[i].text, 10) catch return invalid(cx, t, i);
            if (result.namelen < 20 or result.namelen > 200) return cx.diags.fail(error.ParseError, t[i].line, "The parameter value {s} is not within the required range of 20 and 200.", .{t[i].text});
            i += 1;
        } else return invalid(cx, t, i - 2);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const ds = (if (name) |nm| cx.lib.find(nm) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC GLMMOD: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified_start) |start| {
        try folded.appendSlice(cx.arena, t[0..start]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[start].line });
        try folded.appendSlice(cx.arena, t[start + 3 ..]);
    }
    result.input = try proc.procInputObs(cx.arena, ds, if (qualified_start != null) folded.items else t, cx.diags);
    var classes: std.ArrayList(usize) = .empty;
    var model_effects: std.ArrayList(matrix.Effect) = .empty;
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var model_seen = false;
    var bys: by.Statements = .{};
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
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLMMOD: CLASS must precede MODEL", .{});
            var stop = i + 1;
            while (stop < end and !at(t, stop, .slash)) stop += 1;
            if (stop < end) {
                // p.4238: the only CLASS option is TRUNCATE.
                for (t[stop + 1 .. end]) |token| {
                    if (token.tag == .name and eq(token.text, "truncate")) result.model.truncate = true else return cx.diags.fail(error.ParseError, token.line, "Syntax error, expecting one of the following: ;, TRUNCATE.", .{});
                }
            }
            var names: std.ArrayList([]const u8) = .empty;
            try lists.append(cx.arena, result.input.ds, t[i + 1 .. stop], &names, cx.diags);
            for (names.items) |nm| {
                const ci = result.input.ds.indexOf(nm).?;
                if (std.mem.indexOfScalar(usize, classes.items, ci) == null) try classes.append(cx.arena, ci);
            }
        } else if (kw(t, i, "model")) {
            // SAS 9.4 probe (2026-11-28): a later MODEL statement silently
            // replaces an earlier one, so only the last one is kept.
            model_seen = true;
            model_effects.clearRetainingCapacity();
            result.model.intercept = true;
            var eqpos = i + 1;
            while (eqpos < end and !at(t, eqpos, .eq)) eqpos += 1;
            if (eqpos == end) return cx.diags.fail(error.ParseError, t[i].line, "Expecting an =.", .{});
            if (eqpos == i + 1) return invalid(cx, t, eqpos);
            var names: std.ArrayList([]const u8) = .empty;
            try lists.append(cx.arena, result.input.ds, t[i + 1 .. eqpos], &names, cx.diags);
            const deps = try cx.arena.alloc(usize, names.items.len);
            for (names.items, deps) |nm, *dep| {
                dep.* = result.input.ds.indexOf(nm).?;
                if (result.input.ds.columns.items[dep.*].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} in list does not match type prescribed for this list.", .{result.input.ds.columns.items[dep.*].name});
            }
            result.responses = deps;
            result.model.response = deps[0];
            var j = eqpos + 1;
            var slash = j;
            while (slash < end and !at(t, slash, .slash)) slash += 1;
            try effects(cx, result.input.ds, classes.items, t[j..slash], &model_effects);
            if (slash < end) {
                j = slash + 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "noint")) {
                        result.model.intercept = false;
                    } else if ((kw(t, j, "alpha") or kw(t, j, "singular") or kw(t, j, "zeta")) and at(t, j + 1, .eq) and at(t, j + 2, .number)) {
                        // ponytail: accepted by SAS 9.4 (R5 probe) and has no
                        // effect on a design matrix, which GLMMOD only lists.
                        j += 2;
                    } else return cx.diags.fail(error.ParseError, t[j].line, "Syntax error, expecting one of the following: ;, ALPHA, NOINT, SINGULAR, ZETA.", .{});
                }
            }
        } else if (kw(t, i, "format")) {
            var j = i;
            try proc.parseProcFormat(cx.arena, t, &j, &formats);
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "freq") or kw(t, i, "weight")) {
            // p.4239: one numeric variable, transferred to the outputs unchanged.
            if (end != i + 2) return invalid(cx, t, if (end == i + 1) end else i + 2);
            var j = i + 1;
            const ci = try variable(cx, result.input.ds, t[0..end], &j);
            if (result.input.ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLMMOD: {s} variable {s} must be numeric", .{ t[i].text, t[i + 1].text });
            const slot = if (kw(t, i, "freq")) &result.freq else &result.weight;
            if (slot.* != null) return cx.diags.fail(error.ParseError, t[i].line, "Only one {s} variable may be given.", .{if (kw(t, i, "freq")) @as([]const u8, "FREQUENCY") else "WEIGHT"});
            slot.* = ci;
        } else if (!kw(t, i, "run") and !kw(t, i, "quit") and !kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, if (t.len > 0) t[0].line else 0, "No MODEL statement.", .{});
    result.input.ds = try by.withFormats(cx.arena, result.input.ds, formats.items);
    result.model.classes = classes.items;
    result.model.effects = model_effects.items;
    const pb = try bys.resolve(cx.arena, result.input.ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = result.input.ds.indexOf(n).?;
    result.by_cols = cols;
    result.by_desc = pb.desc;
    result.notsorted = pb.notsorted;
    return result;
}

fn outputColumn(cx: proc.ProcCtx, ds: *Dataset, name: []const u8, t: @import("../pdv.zig").VarType) diag.Error!usize {
    if (ds.indexOf(name) != null) return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: duplicate output column {s}", .{name});
    return ds.addColumn(name, t);
}

/// SAS lists and stores FREQ truncated (1.7 -> 1, 0.5 -> 0); missing stays missing.
fn roleValue(s: Spec, row: []const Value, c: usize) f64 {
    if (row[c] != .num) return std.math.nan(f64);
    const x = row[c].num;
    return if (s.freq == c and std.math.isFinite(x)) @trunc(x) else x;
}

fn finiteNumber(v: Value) ?f64 {
    return if (v == .num and std.math.isFinite(v.num)) v.num else null;
}

/// Decimal places a listing column needs: the most any value shows under
/// BEST12., so 27.0 prints beside 19.4 and an integer column prints bare.
fn decimals(a: A, values: []const f64) !usize {
    var most: usize = 0;
    for (values) |x| {
        if (!std.math.isFinite(x)) continue;
        const text = std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = x }, "best12."), " ");
        if (std.mem.indexOfAny(u8, text, "eE") != null) return error.Unsupported;
        if (std.mem.indexOfScalar(u8, text, '.')) |dot| most = @max(most, text.len - dot - 1);
    }
    return most;
}
fn cell(a: A, x: f64, places: usize) ![]const u8 {
    if (!std.math.isFinite(x)) return ".";
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, places });
}

/// One pass of the data (p.4239): the dependents sharing one missing-value
/// pattern, the observations they use, and that pass's design matrix.
const Pass = struct { deps: []const usize, rows: []const []const Value, design: matrix.Design };

fn depNames(a: A, ds: *const Dataset, deps: []const usize) ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (deps, 0..) |c, k| {
        if (k > 0) try text.append(a, ' ');
        try text.appendSlice(a, ds.columns.items[c].name);
    }
    return text.items;
}

fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, first: []const Value, deps: ?[]const u8) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out) else if (cx.graph_title) |text| try out.print(cx.arena, "\n{s}\n", .{text});
    if (s.by_cols.len > 0) try by.appendLine(cx.arena, out, s.input.ds, first, s.by_cols);
    try out.appendSlice(cx.arena, "\nThe GLMMOD Procedure\n");
    if (deps) |names| try out.print(cx.arena, "Dependent Variables: {s}\n", .{names});
}

/// FREQ/WEIGHT only decide "Used" (GLM rules: truncated FREQ >= 1, WEIGHT > 0);
/// the design points list every observation complete in the model variables.
fn counts(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, all: []const []const Value, pass: Pass) !void {
    var used: usize = 0;
    var freq_read: f64 = 0;
    var freq_used: f64 = 0;
    if (s.freq) |fc| for (all) |row| if (finiteNumber(row[fc])) |f| if (@trunc(f) >= 1) {
        freq_read += @trunc(f);
    };
    for (pass.design.source_rows) |source| {
        const row = pass.rows[source];
        const f: ?f64 = if (s.freq) |fc| finiteNumber(row[fc]) else 1;
        const w: ?f64 = if (s.weight) |wc| finiteNumber(row[wc]) else 1;
        if (f == null or @trunc(f.?) < 1 or w == null or !(w.? > 0)) continue;
        used += 1;
        freq_used += @trunc(f.?);
    }
    try out.print(cx.arena, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ all.len, used });
    if (s.freq != null) try out.print(cx.arena, "Sum of Frequencies Read {d}\nSum of Frequencies Used {d}\n", .{ freq_read, freq_used });
}

/// S154 p.4239 "Displayed Output", layout from the SAS reference listings:
/// class levels and counts (one "Data for Analysis" block per pass when the
/// dependents' missing-value patterns differ), then per pass the parameter
/// definitions (omitted when the design has no columns) and design points.
fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, passes: []const Pass, all: []const []const Value) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const first = passes[0].design;
    const multiple = passes.len > 1;
    try heading(cx, out, s, all[0], null);
    if (first.classes.len > 0) {
        try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
        for (first.classes) |class| {
            try out.print(a, "\n{s} {d}", .{ ds.columns.items[class.column].name, class.map.levels.len });
            for (class.map.levels) |level| try out.print(a, " {s}", .{level.label});
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
    for (passes) |pass| {
        if (multiple) try out.print(a, "\n\nData for Analysis of {s}\n", .{try depNames(a, ds, pass.deps)});
        try counts(cx, out, s, all, pass);
    }
    if (multiple) try out.appendSlice(a, "\n\nNOTE: Variables in each group are consistent with respect to the presence or absence of missing values.\n");

    for (passes) |pass| {
        const d = pass.design;
        const label: ?[]const u8 = if (multiple) try depNames(a, ds, pass.deps) else null;
        if (d.p > 0) {
            try heading(cx, out, s, all[0], label);
            // Only CLASS variables that occur in some effect get a column (R2 probe);
            // declared-but-unused CLASS variables leave the spanning header alone.
            const used = try a.alloc(bool, d.classes.len);
            @memset(used, false);
            for (d.columns) |column| for (column.class_values, used) |v, *u| {
                if (v != null) u.* = true;
            };
            const any = std.mem.indexOfScalar(bool, used, true) != null;
            try out.appendSlice(a, "\nParameter Definitions\n\n");
            if (d.classes.len > 0 and !any) try out.appendSlice(a, "CLASS Variable Values\n");
            try out.appendSlice(a, "Name of\nColumn Associated");
            if (any) try out.appendSlice(a, " CLASS Variable Values");
            try out.appendSlice(a, "\nNumber Effect");
            for (d.classes, used) |class, u| if (u) try out.print(a, " {s}", .{ds.columns.items[class.column].name});
            try out.appendSlice(a, "\n\n");
            for (d.columns, 0..) |column, j| {
                try out.print(a, "{d} {s}", .{ j + @as(usize, if (s.zerobased) 0 else 1), column.effect_name[0..@min(s.namelen, column.effect_name.len)] });
                for (d.classes, 0..) |class, k| if (column.class_values[k]) |level| try out.print(a, " {s}", .{class.map.levels[level].label});
                try out.append(a, '\n');
            }
        }

        try heading(cx, out, s, all[0], label);
        try out.appendSlice(a, "\nDesign Points\n\nObservation Column Number\nNumber");
        var roles: std.ArrayList(usize) = .empty;
        try roles.appendSlice(a, pass.deps);
        if (s.freq) |c| try roles.append(a, c);
        if (s.weight) |c| try roles.append(a, c);
        for (roles.items) |c| try out.print(a, " {s}", .{ds.columns.items[c].name});
        for (0..d.p) |j| try out.print(a, " {d}", .{j + @as(usize, if (s.zerobased) 0 else 1)});
        try out.appendSlice(a, "\n\n");
        const column = try a.alloc(f64, d.n);
        const role_places = try a.alloc(usize, roles.items.len);
        for (roles.items, role_places) |c, *places| {
            for (d.source_rows, column) |source, *x| x.* = roleValue(s, pass.rows[source], c);
            places.* = decimals(a, column) catch return proc.failGap(cx.diags, 0, "PROC GLMMOD: design points with exponent-notation values are not implemented", .{});
        }
        const design_places = try a.alloc(usize, d.p);
        for (design_places, 0..) |*places, j| {
            for (column, 0..) |*x, i| x.* = d.x[i * d.p + j];
            places.* = decimals(a, column) catch return proc.failGap(cx.diags, 0, "PROC GLMMOD: design points with exponent-notation values are not implemented", .{});
        }
        for (d.source_rows, 0..) |source, i| {
            try out.print(a, "{d}", .{i + 1});
            for (roles.items, role_places) |c, places| try out.print(a, " {s}", .{try cell(a, roleValue(s, pass.rows[source], c), places)});
            for (design_places, 0..) |places, j| try out.print(a, " {s}", .{try cell(a, d.x[i * d.p + j], places)});
            try out.append(a, '\n');
        }
    }
}

fn columnLabel(a: A, d: matrix.Design, column: matrix.Column) ![]const u8 {
    var label: std.ArrayList(u8) = .empty;
    try label.appendSlice(a, column.effect_name);
    for (d.classes, 0..) |class, k| if (column.class_values[k]) |level| try label.print(a, " {s}", .{class.map.levels[level].label});
    return label.items;
}

fn sameColumns(x: matrix.Design, y: matrix.Design) bool {
    if (x.p != y.p) return false;
    for (x.columns, y.columns) |l, r| if (!std.mem.eql(u8, l.effect_name, r.effect_name)) return false;
    return true;
}

fn isMissing(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}

/// A design with no columns (MODEL y = / NOINT): SAS still lists the design
/// points (R4 probe); the shared kernel requires a column, so drop its intercept.
fn buildDesign(a: A, ds: *const Dataset, rows: []const []const Value, model: matrix.Spec) diag.Error!matrix.Design {
    if (model.intercept or model.effects.len > 0) return matrix.build(a, ds, rows, model);
    var with_intercept = model;
    with_intercept.intercept = true;
    var d = try matrix.build(a, ds, rows, with_intercept);
    d.p = 0;
    d.x = &.{};
    d.columns = &.{};
    return d;
}

/// Group the dependents by their missing-value pattern over the observations
/// complete in the independents (GLM p.4148, GLMMOD p.4239); one pass when
/// every dependent shares one pattern, else one pass per pattern.
fn buildPasses(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error![]Pass {
    const a = cx.arena;
    var required: std.ArrayList(usize) = .empty;
    try required.appendSlice(a, s.model.classes);
    for (s.model.effects) |e| for (e.factors) |c| if (std.mem.indexOfScalar(usize, s.model.classes, c) == null) try required.append(a, c);
    var complete: std.ArrayList(usize) = .empty;
    for (rows, 0..) |row, i| {
        var ok = true;
        for (required.items) |c| if (isMissing(row[c])) {
            ok = false;
        };
        if (ok) try complete.append(a, i);
    }
    var groups: std.ArrayList(std.ArrayList(usize)) = .empty;
    for (s.responses) |dep| {
        var placed = false;
        for (groups.items) |*g| {
            const other = g.items[0];
            var same = true;
            for (complete.items) |i| if (isMissing(rows[i][dep]) != isMissing(rows[i][other])) {
                same = false;
            };
            if (same) {
                try g.append(a, dep);
                placed = true;
                break;
            }
        }
        if (!placed) {
            var g: std.ArrayList(usize) = .empty;
            try g.append(a, dep);
            try groups.append(a, g);
        }
    }
    // ponytail: the pass order and headings of a multi-dependent pattern group
    // among several passes are not SAS-verified, so that shape fails loud.
    if (groups.items.len > 1) for (groups.items) |g| if (g.items.len > 1)
        return proc.failGap(cx.diags, 0, "PROC GLMMOD: several dependents sharing one missing-value pattern alongside other patterns are not implemented", .{});
    if (groups.items.len > 1 and s.by_cols.len > 0)
        return proc.failGap(cx.diags, 0, "PROC GLMMOD: BY groups with several dependent-variable passes are not implemented", .{});
    const result = try a.alloc(Pass, groups.items.len);
    for (groups.items, result) |g, *pass| {
        var kept: std.ArrayList([]const Value) = .empty;
        for (rows) |row| {
            var ok = true;
            for (g.items) |dep| if (isMissing(row[dep])) {
                ok = false;
            };
            if (ok) try kept.append(a, row);
        }
        var model = s.model;
        model.response = g.items[0];
        pass.deps = g.items;
        pass.rows = kept.items;
        pass.design = buildDesign(a, s.input.ds, kept.items, model) catch |err| {
            if (err == error.OutOfMemory) return err;
            return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: invalid effects, no complete observations, or nonfinite design value", .{});
        };
    }
    if (result.len > 1) for (result[1..]) |pass| {
        if (!sameColumns(result[0].design, pass.design) or !sameLevels(result[0].design, pass.design))
            return proc.failGap(cx.diags, 0, "PROC GLMMOD: dependent-variable passes with different CLASS levels or design columns are not implemented", .{});
    };
    return result;
}

fn sameLevels(x: matrix.Design, y: matrix.Design) bool {
    for (x.classes, y.classes) |l, r| {
        if (l.map.levels.len != r.map.levels.len) return false;
        for (l.map.levels, r.map.levels) |p, q| if (!std.mem.eql(u8, p.label, q.label)) return false;
    }
    return true;
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const a = cx.arena;
    const groups = try by.checkedSlices(a, s.input.ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (groups.len == 0 or s.input.ds.rows.items.len == 0) {
        // SAS 9.4 writes only these NOTEs (no ERROR), prints nothing and
        // creates no output data set; the step severity stays a note.
        const name = try std.ascii.allocUpperString(a, s.input.ds.name);
        const qualified = if (std.mem.indexOfScalar(u8, name, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{name}) else name;
        try cx.diags.note(0, "No observations in data set {s}.", .{qualified});
        try cx.diags.note(0, "The SAS System stopped processing this step because of errors.", .{});
        return;
    }
    const designs = try a.alloc([]Pass, groups.len);
    for (groups, designs) |group, *d| {
        if (s.freq orelse s.weight) |_| for (group.rows) |row| for ([_]?usize{ s.freq, s.weight }) |role| if (role) |c| {
            if (row[c] == .num and !std.math.isNan(row[c].num) and !std.math.isFinite(row[c].num)) return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: nonfinite FREQ or WEIGHT value", .{});
        };
        d.* = try buildPasses(cx, s, group.rows);
    }
    const reference = designs[0][0].design;
    // ponytail: one OUTDESIGN/OUTPARM layout for all BY groups; groups whose
    // observed levels give different columns would need per-group layouts.
    if ((s.outdesign != null or s.outparm != null) and designs.len > 1) for (designs[1..]) |d| if (!sameColumns(reference, d[0].design))
        return proc.failGap(cx.diags, 0, "PROC GLMMOD: output data sets for BY groups with different design columns are not implemented", .{});
    var body: std.ArrayList(u8) = .empty;
    if (!s.noprint) for (groups, designs) |group, d| try render(cx, &body, s, d, group.rows);

    const ds = s.input.ds;
    // p.4240: _YPASS_ appears only when the missing-value pattern needs passes.
    const ypass = designs[0].len > 1;
    var design_output: ?*Dataset = null;
    var parm_output: ?*Dataset = null;
    if (s.outdesign) |name| {
        if (cx.lib.readonlyOut(name)) return cx.lib.failReadonly(name);
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, name);
        var roles: std.ArrayList(usize) = .empty;
        try roles.appendSlice(a, s.by_cols);
        if (ypass) _ = try outputColumn(cx, output, "_YPASS_", .num);
        try roles.appendSlice(a, s.responses);
        if (s.freq) |c| try roles.append(a, c);
        if (s.weight) |c| try roles.append(a, c);
        for (roles.items) |c| if (output.indexOf(ds.columns.items[c].name) == null) {
            _ = try output.addColumnLike(ds.columns.items[c].name, ds.columns.items[c]);
        };
        for (0..reference.p) |j| {
            const colname = try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, j + @as(usize, if (s.zerobased) 0 else 1) });
            if (colname.len > 32) return cx.diags.fail(error.ParseError, 0, "PROC GLMMOD: design column name exceeds 32 characters", .{});
            _ = try outputColumn(cx, output, colname, .num);
            output.setLabel(colname, try columnLabel(a, reference, reference.columns[j]));
        }
        const width = output.columns.items.len;
        const cells = try a.alloc(Value, width);
        for (designs) |group_passes| for (group_passes, 0..) |pass, pass_index| {
            const d = pass.design;
            for (d.source_rows, 0..) |source, i| {
                const row = pass.rows[source];
                for (output.columns.items[0 .. width - d.p], 0..) |col, k| {
                    if (ypass and eq(col.name, "_YPASS_")) {
                        cells[k] = .{ .num = @floatFromInt(pass_index + 1) };
                        continue;
                    }
                    const c = ds.indexOf(col.name).?;
                    const other_dep = std.mem.indexOfScalar(usize, s.responses, c) != null and std.mem.indexOfScalar(usize, pass.deps, c) == null;
                    cells[k] = if (other_dep) Value.missing else if (s.freq == c and row[c] == .num) .{ .num = roleValue(s, row, c) } else row[c];
                }
                for (0..d.p) |j| cells[width - d.p + j] = .{ .num = d.x[i * d.p + j] };
                try output.appendRow(cells);
            }
        };
        design_output = output;
    }
    if (s.outparm) |name| {
        if (cx.lib.readonlyOut(name)) return cx.lib.failReadonly(name);
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, name);
        for (s.by_cols) |c| _ = try outputColumn(cx, output, ds.columns.items[c].name, ds.columns.items[c].type);
        for (s.by_cols, 0..) |c, k| output.columns.items[k] = ds.columns.items[c];
        if (ypass) _ = try outputColumn(cx, output, "_YPASS_", .num);
        _ = try outputColumn(cx, output, "_COLNUM_", .num);
        output.setLabel("_COLNUM_", "Design matrix column number");
        _ = try outputColumn(cx, output, "EFFNAME", .char);
        output.setLen("EFFNAME", s.namelen);
        output.setLabel("EFFNAME", "Effect name");
        for (reference.classes) |class| {
            const original = ds.columns.items[class.column];
            _ = try outputColumn(cx, output, original.name, .char);
            var width = if (original.type == .char) original.len orelse 8 else @as(usize, 12);
            for (designs) |group_passes| for (group_passes) |pass| for (pass.design.classes) |c| if (c.column == class.column) {
                for (c.map.levels) |level| width = @max(width, level.label.len);
            };
            output.setLen(original.name, width);
        }
        const nb = s.by_cols.len + @intFromBool(ypass);
        const cells = try a.alloc(Value, reference.classes.len + 2 + nb);
        for (groups, designs) |group, group_passes| for (group_passes, 0..) |pass, pass_index| for (pass.design.columns, 0..) |column, j| {
            const d = pass.design;
            for (s.by_cols, 0..) |c, k| cells[k] = group.rows[0][c];
            if (ypass) cells[nb - 1] = .{ .num = @floatFromInt(pass_index + 1) };
            cells[nb] = .{ .num = @floatFromInt(j + @as(usize, if (s.zerobased) 0 else 1)) };
            cells[nb + 1] = .{ .str = column.effect_name[0..@min(s.namelen, column.effect_name.len)] };
            for (d.classes, 0..) |class, k| cells[nb + k + 2] = .{ .str = if (column.class_values[k]) |level| class.map.levels[level].label else "" };
            try output.appendRow(cells);
        };
        parm_output = output;
    }
    try out.appendSlice(a, body.items);
    if (design_output) |output| try cx.lib.put(output.name, output);
    if (parm_output) |output| try cx.lib.put(output.name, output);
}

fn fixture(a: A, lib: *@import("../exec.zig").Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "design_input");
    for ([_][]const u8{ "x", "z", "y" }) |nm| _ = try ds.addColumn(nm, .num);
    _ = try ds.addColumn("group", .char);
    _ = try ds.addColumn("h", .num);
    const y = [_]f64{ 4, 6, 7, 9, 13, 12, 17, 19, 20, 23, 25, 24 };
    const z = [_]f64{ 1, 1, 2, 1, 3, 2, 4, 3, 5, 3, 5, 4 };
    for (0..12) |i| try ds.appendRow(&.{ .{ .num = @floatFromInt(i + 1) }, .{ .num = z[i] }, .{ .num = y[i] }, .{ .str = if (i < 6) "A" else "B" }, .{ .num = @floatFromInt((i + 1) % 3) } });
    try lib.put("design_input", ds);
}
test "GLMMOD actual OUTPARM and OUTDESIGN data match all original oracle fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try fixture(a, &lib);
    var diags = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &diags };
    var sink: std.ArrayList(u8) = .empty;
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outdesign=matrix outparm=columns noprint; class group h; model y=group h group*h x group*x; run;", &diags));
    const x = lib.find("matrix").?;
    const p = lib.find("columns").?;
    try std.testing.expectEqual(@as(usize, 12), x.rowCount());
    try std.testing.expectEqual(@as(usize, 16), x.columns.items.len);
    try std.testing.expectEqual(@as(usize, 15), p.rowCount());
    try std.testing.expectEqualStrings("x*group", p.rows.items[13][1].str);
    try std.testing.expectEqualStrings("A", p.rows.items[13][2].str);
    try std.testing.expectEqualStrings("", p.rows.items[13][3].str);
    try std.testing.expectEqual(@import("../pdv.zig").VarType.char, p.columns.items[3].type);
    // Check blank CLASS cells in their typed columns as well as printed tokens:
    // whitespace normalization alone cannot distinguish a misplaced blank.
    const hlabels = [_][]const u8{ "0", "1", "2" };
    for (p.rows.items, 0..) |row, j| {
        const effect: []const u8 = if (j == 0) "Intercept" else if (j < 3) "group" else if (j < 6) "h" else if (j < 12) "group*h" else if (j == 12) "x" else "x*group";
        const group: []const u8 = if (j == 1 or (j >= 6 and j < 9) or j == 13) "A" else if (j == 2 or (j >= 9 and j < 12) or j == 14) "B" else "";
        const h: []const u8 = if (j >= 3 and j < 6) hlabels[j - 3] else if (j >= 6 and j < 12) hlabels[(j - 6) % 3] else "";
        try std.testing.expectEqual(@as(f64, @floatFromInt(j + 1)), row[0].num);
        try std.testing.expectEqualStrings(effect, row[1].str);
        try std.testing.expectEqualStrings(group, row[2].str);
        try std.testing.expectEqualStrings(h, row[3].str);
    }
    for (x.rows.items, 0..) |row, i| {
        const source = lib.find("design_input").?.rows.items[i];
        try std.testing.expectEqual(source[2].num, row[0].num);
        for (0..15) |j| {
            const h = (i + 1) % 3;
            const group: usize = if (i < 6) 0 else 1;
            const value: f64 = if (j == 0) 1 else if (j < 3) (if (j - 1 == group) @as(f64, 1) else 0) else if (j < 6) (if (j - 3 == h) @as(f64, 1) else 0) else if (j < 12) (if (j - 6 == 3 * group + h) @as(f64, 1) else 0) else if (j == 12 or j - 13 == group) @floatFromInt(i + 1) else 0;
            try std.testing.expectEqual(value, row[j + 1].num);
        }
        try std.testing.expectEqual(@as(f64, 1), row[1].num);
        try std.testing.expectEqual(@as(f64, @floatFromInt(i + 1)), row[13].num);
        try std.testing.expectEqual(@as(f64, if (i < 6) @floatFromInt(i + 1) else 0), row[14].num);
        try std.testing.expectEqual(@as(f64, if (i >= 6) @floatFromInt(i + 1) else 0), row[15].num);
    }
    try std.testing.expectEqualStrings("", try diags.render());
}
test "GLMMOD bar polynomial expansion noint names prefix and visible unsupported options" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try fixture(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outdesign=d outparm=p prefix=X zerobased noprint; model y=x|x|x / noint; run;", &d));
    const p = lib.find("p").?;
    const x = lib.find("d").?;
    try std.testing.expectEqual(@as(usize, 3), p.rowCount());
    try std.testing.expectEqualStrings("x*x*x", p.rows.items[2][1].str);
    try std.testing.expectEqualStrings("X0", x.columns.items[1].name);
    try std.testing.expectEqual(@as(f64, 0), p.rows.items[0][0].num);
    try std.testing.expectEqual(@as(f64, 1728), x.rows.items[11][3].num);
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input order=data outdesign=ordered outparm=ordered_parm noprint; class group h; model y=h*group / noint; run;", &d));
    const ordered = lib.find("ordered").?;
    const ordered_parm = lib.find("ordered_parm").?;
    try std.testing.expectEqual(@as(usize, 6), ordered_parm.rowCount());
    try std.testing.expectEqualStrings("group*h", ordered_parm.rows.items[0][1].str);
    try std.testing.expectEqualStrings("1", ordered_parm.rows.items[0][3].str);
    try std.testing.expectEqualStrings("0", ordered_parm.rows.items[2][3].str);
    try std.testing.expectEqual(@as(f64, 1), ordered.rows.items[0][1].num);
    try std.testing.expectEqual(@as(f64, 1), ordered.rows.items[1][2].num);
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input; class group h; model y=group*h(group); run;", &d)));
    try std.testing.expect(diag.gapHit());
}

test "GLMMOD failures are captured before output publication" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try fixture(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    // A character non-CLASS effect is now rejected while parsing (SAS wording).
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outdesign=bad noprint; model y=group; run;", &d)));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(lib.find("bad") == null);
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input noprint; class group; run;", &d)));
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outdesign=bad noprint; by descending group; model y=x; run;", &d)));
    try std.testing.expect(lib.find("bad") == null);
}

test "STAT-GLMMOD-001 listing counts, FREQ/WEIGHT roles, labels and BY outputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    // Rows: missing CLASS; complete; missing y; missing FREQ; zero FREQ; negative WEIGHT.
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "roles");
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "y", "f", "w" }) |nm| _ = try ds.addColumn(nm, .num);
    const nan = std.math.nan(f64);
    const g = [_][]const u8{ "", "A", "A", "A", "B", "B" };
    const y = [_]f64{ 6, 1.5, nan, 3, 4, 5 };
    const f = [_]f64{ 1, 2, 1, nan, 0, 1 };
    const w = [_]f64{ 1, 1, 1, 1, 1, -1 };
    for (0..6) |i| try ds.appendRow(&.{ .{ .str = g[i] }, .{ .num = y[i] }, .{ .num = f[i] }, .{ .num = w[i] } });
    try lib.put("roles", ds);
    var out: std.ArrayList(u8) = .empty;
    try run(cx, &out, try lex.tokenize(a, "proc glmmod data=roles outdesign=od outparm=op; class g; freq f; weight w; model y=g; run;", &d));
    const text = out.items;
    // Read 6, design rows 4 (y, g complete), Used 1 (only row 1 has FREQ>=1 and WEIGHT>0).
    try std.testing.expect(std.mem.indexOf(u8, text, "Number of Observations Read 6\nNumber of Observations Used 1\nSum of Frequencies Read 5\nSum of Frequencies Used 2\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Number y f w 1 2 3\n\n1 1.5 2 1 1 1 0\n2 3.0 . 1 1 1 0\n3 4.0 0 1 1 0 1\n4 5.0 1 -1 1 0 1\n") != null);
    const od = lib.find("od").?;
    try std.testing.expectEqual(@as(usize, 4), od.rowCount());
    for (od.columns.items, [_][]const u8{ "y", "f", "w", "Col1", "Col2", "Col3" }) |col, name| try std.testing.expectEqualStrings(name, col.name);
    try std.testing.expectEqualStrings("Intercept", od.columns.items[3].label.?);
    try std.testing.expectEqualStrings("g B", od.columns.items[5].label.?);
    // BY: variables lead both outputs; parameter rows repeat per group.
    try run(cx, &out, try lex.tokenize(a, "proc glmmod data=roles outdesign=bd outparm=bp noprint; by g; model y=w; run;", &d));
    const bp = lib.find("bp").?;
    try std.testing.expectEqualStrings("g", bp.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 6), bp.rowCount());
    try std.testing.expectEqualStrings("A", bp.rows.items[2][0].str);
    try std.testing.expectEqualStrings("w", bp.rows.items[3][2].str);
    try std.testing.expectEqualStrings("g", lib.find("bd").?.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 5), lib.find("bd").?.rowCount());
    // Unsorted BY is a user error that publishes nothing.
    try std.testing.expectError(error.ParseError, run(cx, &out, try lex.tokenize(a, "proc glmmod data=roles outdesign=never; by descending g; model y=w; run;", &d)));
    try std.testing.expect(lib.find("never") == null);
}

test "STAT-GLMMOD-001 declarations: last BY wins, CLASS after MODEL, duplicate roles, NAMELEN, truncated FREQ" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try fixture(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    // p.4238: with more than one BY statement only the last is used (h is unsorted, group is sorted).
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outparm=last_by noprint; by h; by group; model y=x; run;", &d));
    try std.testing.expectEqualStrings("group", lib.find("last_by").?.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 4), lib.find("last_by").?.rowCount());
    // Errors carry the statement's line.
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input noprint;\nmodel y=x;\nclass group; run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "CLASS must precede MODEL") != null);
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input noprint; weight x;\nweight z; model y=x; run;", &d)));
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "Only one WEIGHT variable may be given.") != null);
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input namelen=201 noprint; model y=x; run;", &d)));
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input noprint; freq group; model y=x; run;", &d)));
    // NAMELEN=20 default truncates EFFNAME; NAMELEN=200 keeps it.
    const long = "proc glmmod data=design_input outparm=np noprint{s}; class group h; model y=group*h*x*z*x*z*x*z*x*z; run;";
    try run(cx, &sink, try lex.tokenize(a, try std.fmt.allocPrint(a, long, .{""}), &d));
    try std.testing.expectEqualStrings("x*x*x*x*z*z*z*z*grou", lib.find("np").?.rows.items[1][1].str);
    try run(cx, &sink, try lex.tokenize(a, try std.fmt.allocPrint(a, long, .{" namelen=200"}), &d));
    try std.testing.expectEqualStrings("x*x*x*x*z*z*z*z*group*h", lib.find("np").?.rows.items[1][1].str);
    // FREQ is stored truncated; missing stays missing.
    const ds = lib.find("design_input").?;
    @constCast(ds.rows.items[0])[1] = .{ .num = 2.9 };
    @constCast(ds.rows.items[1])[1] = .{ .num = std.math.nan(f64) };
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outdesign=fd noprint; freq z; model y=x; run;", &d));
    const fd = lib.find("fd").?;
    try std.testing.expectEqualStrings("z", fd.columns.items[1].name);
    try std.testing.expectEqual(@as(f64, 2), fd.rows.items[0][1].num);
    try std.testing.expect(std.math.isNan(fd.rows.items[1][1].num));
}

test "STAT-GLMMOD-001 empty input notes only; explicit ORDER=INTERNAL and ORDER=FORMATTED" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    const empty = try a.create(Dataset);
    empty.* = Dataset.init(a, "e");
    _ = try empty.addColumn("g", .char);
    _ = try empty.addColumn("y", .num);
    try lib.put("e", empty);
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=e outdesign=none; class g; model y=g; run;", &d));
    try std.testing.expect(!d.hasErrors());
    try std.testing.expect(std.mem.indexOf(u8, try d.render(), "No observations in data set WORK.E.") != null);
    try std.testing.expectEqual(@as(usize, 0), sink.items.len);
    try std.testing.expect(lib.find("none") == null);
    // p.4237: ORDER=INTERNAL sorts 1 < 2 < 3; ORDER=FORMATTED sorts the
    // WORDS. text, "one" < "three" < "two" (explicit format, so it applies).
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "o");
    _ = try ds.addColumn("k", .num);
    _ = try ds.addColumn("y", .num);
    ds.columns.items[0].format = "words.";
    for ([_]f64{ 1, 2, 3, 1 }, 0..) |k, i| try ds.appendRow(&.{ .{ .num = k }, .{ .num = @floatFromInt(i) } });
    try lib.put("o", ds);
    inline for (.{ .{ "internal", "two", "three" }, .{ "formatted", "three", "two" } }) |case| {
        try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=o outparm=op order=" ++ case[0] ++ " noprint; class k; model y=k / noint; run;", &d));
        const op = lib.find("op").?;
        try std.testing.expectEqual(@as(usize, 3), op.rowCount());
        try std.testing.expectEqualStrings("one", op.rows.items[0][2].str);
        try std.testing.expectEqualStrings(case[1], op.rows.items[1][2].str);
        try std.testing.expectEqualStrings(case[2], op.rows.items[2][2].str);
    }
}

fn g3Data(a: A, lib: *@import("../exec.zig").Library) !void {
    const ds = try a.create(Dataset);
    ds.* = Dataset.init(a, "t3");
    _ = try ds.addColumn("g", .char);
    for ([_][]const u8{ "h", "x", "y1", "y2", "c", "k" }) |nm| _ = try ds.addColumn(nm, .num);
    const nan = std.math.nan(f64);
    const g = [_][]const u8{ "aaaaaaaaaaaaaaaaaaaaX", "aaaaaaaaaaaaaaaaaaaaY", "bb", "bb", "aaaaaaaaaaaaaaaaaaaaX", "bb" };
    const h = [_]f64{ 1, 2, 1, 2, 2, 1 };
    const y2 = [_]f64{ 5, nan, 7, 8, 9, nan };
    const c = [_]f64{ 1, 2, 3, 1, 2, 3 };
    for (0..6) |i| try ds.appendRow(&.{ .{ .str = g[i] }, .{ .num = h[i] }, .{ .num = @as(f64, @floatFromInt(i)) + 1.5 }, .{ .num = @as(f64, @floatFromInt(i)) + 4 }, .{ .num = y2[i] }, .{ .num = c[i] }, .{ .num = @floatFromInt(i % 2) } });
    try lib.put("t3", ds);
}

test "STAT-GLMMOD-003 CLASS TRUNCATE groups on the first 16 formatted characters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try g3Data(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    // SAS 9.4 (Q3/Q4 probe): two levels with TRUNCATE, three without.
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3 outparm=tp noprint; class g / truncate; model y1 = g; run;", &d));
    const tp = lib.find("tp").?;
    try std.testing.expectEqual(@as(usize, 3), tp.rowCount());
    try std.testing.expectEqualStrings("aaaaaaaaaaaaaaaa", tp.rows.items[1][2].str);
    try std.testing.expectEqualStrings("bb", tp.rows.items[2][2].str);
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3 outparm=fp noprint; class g; model y1 = g; run;", &d));
    try std.testing.expectEqual(@as(usize, 4), lib.find("fp").?.rowCount());
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3; class g / bogus; model y1 = g; run;", &d)));
}

test "STAT-GLMMOD-003 dependents: one pass per missing pattern with _YPASS_, last MODEL wins" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try g3Data(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    // Same pattern (y1, x): one pass, no _YPASS_, both dependents kept.
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3 outdesign=d1 outparm=p1 noprint; class h; model y1 x = h; run;", &d));
    const d1 = lib.find("d1").?;
    for (d1.columns.items, [_][]const u8{ "y1", "x", "Col1", "Col2", "Col3" }) |col, name| try std.testing.expectEqualStrings(name, col.name);
    try std.testing.expectEqual(@as(usize, 6), d1.rowCount());
    try std.testing.expectEqualStrings("_COLNUM_", lib.find("p1").?.columns.items[0].name);
    // Different patterns: pass 1 = y2 (4 rows), pass 2 = y1 (6 rows), MODEL order.
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3 outdesign=d2 outparm=p2; class h; model y2 y1 = h; run;", &d));
    const d2 = lib.find("d2").?;
    for (d2.columns.items, [_][]const u8{ "_YPASS_", "y2", "y1", "Col1", "Col2", "Col3" }) |col, name| try std.testing.expectEqualStrings(name, col.name);
    try std.testing.expectEqual(@as(usize, 10), d2.rowCount());
    try std.testing.expectEqual(@as(f64, 1), d2.rows.items[3][0].num);
    try std.testing.expect(std.math.isNan(d2.rows.items[3][2].num));
    try std.testing.expectEqual(@as(f64, 2), d2.rows.items[4][0].num);
    try std.testing.expect(std.math.isNan(d2.rows.items[4][1].num));
    try std.testing.expectEqual(@as(f64, 4), d2.rows.items[4][2].num);
    const p2 = lib.find("p2").?;
    try std.testing.expectEqual(@as(usize, 6), p2.rowCount());
    try std.testing.expectEqualStrings("_YPASS_", p2.columns.items[0].name);
    try std.testing.expectEqual(@as(f64, 2), p2.rows.items[3][0].num);
    const text = sink.items;
    try std.testing.expect(std.mem.indexOf(u8, text, "Data for Analysis of y2\n\nNumber of Observations Read 6\nNumber of Observations Used 4\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "The GLMMOD Procedure\nDependent Variables: y1\n") != null);
    // A later MODEL replaces an earlier one (SAS 9.4 Q5 probe).
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3 outdesign=d5 noprint; class h; model y1 = h; model y2 = h / noint; run;", &d));
    const d5 = lib.find("d5").?;
    try std.testing.expectEqualStrings("y2", d5.columns.items[0].name);
    try std.testing.expectEqual(@as(usize, 3), d5.columns.items.len);
    try std.testing.expectEqual(@as(usize, 4), d5.rowCount());
    // NOINT without effects: design points only, OUTPARM has no rows.
    try run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3 outdesign=d4 outparm=p4 noprint; model y1 = / noint; run;", &d));
    try std.testing.expectEqual(@as(usize, 1), lib.find("d4").?.columns.items.len);
    try std.testing.expectEqual(@as(usize, 0), lib.find("p4").?.rowCount());
    // Pattern groups with several members beside another pattern stay a gap.
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=t3; class h; model y1 y2 x = h; run;", &d)));
    try std.testing.expect(diag.gapHit());
}

test "STAT-GLMMOD-003 invalid models report the SAS messages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try g3Data(a, &lib);
    const cases = [_][2][]const u8{
        .{ "model y1 = g;", "Variable g should be either numeric or specified in the CLASS statement." },
        .{ "class h; model y1 = h(x);", "Nesting of continuous variable not allowed." },
        .{ "model y1;", "Expecting an =." },
        .{ "class h; model y1 = h / solution;", "expecting one of the following: ;, ALPHA, NOINT, SINGULAR, ZETA." },
        .{ "class h; model g = h;", "Variable g in list does not match type prescribed for this list." },
        .{ "class h; model y1 = nosuch;", "Variable nosuch not found." },
    };
    for (cases) |case| {
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        var sink: std.ArrayList(u8) = .empty;
        try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc glmmod data=t3; {s} run;", .{case[0]}), &d)));
        try std.testing.expect(std.mem.indexOf(u8, try d.render(), case[1]) != null);
        try std.testing.expectEqual(@as(usize, 0), sink.items.len);
    }
}

test "STAT-GLMMOD-003 bar expansion follows the documented GLM equivalences" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    try g3Data(a, &lib);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    var sink: std.ArrayList(u8) = .empty;
    // GLM p.4097 table (A=h, B=k, C=c; D, E as g): each pair must give the
    // same OUTPARM effect/level rows.
    const pairs = [_][2][]const u8{
        .{ "h | k(h) | c@2", "h k(h) c h*c" },
        .{ "h | k(h) | c", "h k(h) c h*c k*c(h)" },
        .{ "h | c(k)", "h c(k) h*c(k)" },
        .{ "h(k) | c(k)", "h(k) c(k) h*c(k)" },
        .{ "h(k) | k(g c)", "h(k) k(g c)" },
        .{ "h*k(c*g)", "h*k(c g)" },
        .{ "h | k | c | g@2", "h k h*k c h*c k*c g h*g k*g c*g" },
    };
    for (pairs) |pair| {
        try run(cx, &sink, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc glmmod data=t3 outparm=bar noprint; class h k c g; model y1 = {s}; run;", .{pair[0]}), &d));
        const left = lib.find("bar").?;
        try run(cx, &sink, try lex.tokenize(a, try std.fmt.allocPrint(a, "proc glmmod data=t3 outparm=explicit noprint; class h k c g; model y1 = {s}; run;", .{pair[1]}), &d));
        const right = lib.find("explicit").?;
        try std.testing.expectEqual(right.rowCount(), left.rowCount());
        for (left.rows.items, right.rows.items) |l, r| for (l[1..], r[1..]) |x, y| try std.testing.expectEqualStrings(y.str, x.str);
    }
    try std.testing.expectEqualStrings("", try d.render());
}
