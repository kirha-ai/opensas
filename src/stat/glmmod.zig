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
fn term(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!matrix.Effect {
    var factors: std.ArrayList(usize) = .empty;
    var nested: std.ArrayList(usize) = .empty;
    try factors.append(cx.arena, try variable(cx, ds, t, i));
    while (at(t, i.*, .star)) {
        i.* += 1;
        try factors.append(cx.arena, try variable(cx, ds, t, i));
    }
    if (at(t, i.*, .lparen)) {
        i.* += 1;
        while (i.* < t.len and !at(t, i.*, .rparen)) {
            if (at(t, i.*, .star)) {
                i.* += 1;
                continue;
            }
            try nested.append(cx.arena, try variable(cx, ds, t, i));
        }
        if (nested.items.len == 0 or !at(t, i.*, .rparen)) return invalid(cx, t, i.*);
        i.* += 1;
    }
    return .{ .factors = factors.items, .nested = nested.items };
}
fn effects(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, out: *std.ArrayList(matrix.Effect)) diag.Error!void {
    var i: usize = 0;
    while (i < t.len) {
        var chain: std.ArrayList(matrix.Effect) = .empty;
        try chain.append(cx.arena, try term(cx, ds, t, &i));
        while (at(t, i, .pipe)) {
            i += 1;
            try chain.append(cx.arena, try term(cx, ds, t, &i));
        }
        var degree = chain.items.len;
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
        for (1..end) |mask| {
            if (@popCount(mask) > degree) continue;
            var factors: std.ArrayList(usize) = .empty;
            var nested: std.ArrayList(usize) = .empty;
            for (chain.items, 0..) |e, k| if (mask & (@as(usize, 1) << @as(std.math.Log2Int(usize), @intCast(k))) != 0) {
                try factors.appendSlice(cx.arena, e.factors);
                try nested.appendSlice(cx.arena, e.nested);
            };
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
            for (t[i + 1 .. end]) |token| if (token.tag == .slash) return proc.failGap(cx.diags, token.line, "PROC GLMMOD: CLASS TRUNCATE is not implemented", .{});
            var names: std.ArrayList([]const u8) = .empty;
            try lists.append(cx.arena, result.input.ds, t[i + 1 .. end], &names, cx.diags);
            for (names.items) |nm| {
                const ci = result.input.ds.indexOf(nm).?;
                if (std.mem.indexOfScalar(usize, classes.items, ci) == null) try classes.append(cx.arena, ci);
            }
        } else if (kw(t, i, "model")) {
            if (model_seen) return proc.failGap(cx.diags, t[i].line, "PROC GLMMOD: multiple MODEL statements are not implemented", .{});
            model_seen = true;
            var j = i + 1;
            result.model.response = try variable(cx, result.input.ds, t[0..end], &j);
            if (!at(t, j, .eq)) return proc.failGap(cx.diags, t[i].line, "PROC GLMMOD: multiple dependent-variable passes are not implemented", .{});
            if (result.input.ds.columns.items[result.model.response].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC GLMMOD: response must be numeric", .{});
            j += 1;
            var slash = j;
            while (slash < end and !at(t, slash, .slash)) slash += 1;
            try effects(cx, result.input.ds, t[j..slash], &model_effects);
            if (slash < end) {
                j = slash + 1;
                while (j < end) : (j += 1) {
                    if (kw(t, j, "noint")) result.model.intercept = false else return proc.failGap(cx.diags, t[j].line, "PROC GLMMOD: MODEL option {s} is not implemented", .{t[j].text});
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

fn heading(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, first: []const Value) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out) else if (cx.graph_title) |text| try out.print(cx.arena, "\n{s}\n", .{text});
    if (s.by_cols.len > 0) try by.appendLine(cx.arena, out, s.input.ds, first, s.by_cols);
    try out.appendSlice(cx.arena, "\nThe GLMMOD Procedure\n");
}

/// S154 p.4239 "Displayed Output", layout from the SAS reference listing:
/// class levels and counts, parameter definitions, then the design points.
fn render(cx: proc.ProcCtx, out: *std.ArrayList(u8), s: Spec, d: matrix.Design, rows: []const []const Value) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    // FREQ/WEIGHT only decide "Used" (GLM rules: truncated FREQ >= 1, WEIGHT > 0);
    // the design points list every observation complete in the model variables.
    var used: usize = 0;
    var freq_read: f64 = 0;
    var freq_used: f64 = 0;
    if (s.freq) |fc| for (rows) |row| if (finiteNumber(row[fc])) |f| if (@trunc(f) >= 1) {
        freq_read += @trunc(f);
    };
    for (d.source_rows) |source| {
        const row = rows[source];
        const f: ?f64 = if (s.freq) |fc| finiteNumber(row[fc]) else 1;
        const w: ?f64 = if (s.weight) |wc| finiteNumber(row[wc]) else 1;
        if (f == null or @trunc(f.?) < 1 or w == null or !(w.? > 0)) continue;
        used += 1;
        freq_used += @trunc(f.?);
    }
    try heading(cx, out, s, rows[0]);
    if (d.classes.len > 0) {
        try out.appendSlice(a, "\nClass Level Information\n\nClass Levels Values\n");
        for (d.classes) |class| {
            try out.print(a, "\n{s} {d}", .{ ds.columns.items[class.column].name, class.map.levels.len });
            for (class.map.levels) |level| try out.print(a, " {s}", .{level.label});
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
    try out.print(a, "\nNumber of Observations Read {d}\nNumber of Observations Used {d}\n", .{ rows.len, used });
    if (s.freq != null) try out.print(a, "Sum of Frequencies Read {d}\nSum of Frequencies Used {d}\n", .{ freq_read, freq_used });

    try heading(cx, out, s, rows[0]);
    try out.appendSlice(a, "\nParameter Definitions\n\nName of\nColumn Associated");
    if (d.classes.len > 0) try out.appendSlice(a, " CLASS Variable Values");
    try out.appendSlice(a, "\nNumber Effect");
    for (d.classes) |class| try out.print(a, " {s}", .{ds.columns.items[class.column].name});
    try out.appendSlice(a, "\n\n");
    for (d.columns, 0..) |column, j| {
        try out.print(a, "{d} {s}", .{ j + @as(usize, if (s.zerobased) 0 else 1), column.effect_name[0..@min(s.namelen, column.effect_name.len)] });
        for (d.classes, 0..) |class, k| if (column.class_values[k]) |level| try out.print(a, " {s}", .{class.map.levels[level].label});
        try out.append(a, '\n');
    }

    try heading(cx, out, s, rows[0]);
    try out.appendSlice(a, "\nDesign Points\n\nObservation Column Number\nNumber");
    var roles: std.ArrayList(usize) = .empty;
    try roles.append(a, s.model.response);
    if (s.freq) |c| try roles.append(a, c);
    if (s.weight) |c| try roles.append(a, c);
    for (roles.items) |c| try out.print(a, " {s}", .{ds.columns.items[c].name});
    for (0..d.p) |j| try out.print(a, " {d}", .{j + @as(usize, if (s.zerobased) 0 else 1)});
    try out.appendSlice(a, "\n\n");
    const column = try a.alloc(f64, d.n);
    const role_places = try a.alloc(usize, roles.items.len);
    for (roles.items, role_places) |c, *places| {
        for (d.source_rows, column) |source, *x| x.* = roleValue(s, rows[source], c);
        places.* = decimals(a, column) catch return proc.failGap(cx.diags, 0, "PROC GLMMOD: design points with exponent-notation values are not implemented", .{});
    }
    const design_places = try a.alloc(usize, d.p);
    for (design_places, 0..) |*places, j| {
        for (column, 0..) |*x, i| x.* = d.x[i * d.p + j];
        places.* = decimals(a, column) catch return proc.failGap(cx.diags, 0, "PROC GLMMOD: design points with exponent-notation values are not implemented", .{});
    }
    for (d.source_rows, 0..) |source, i| {
        try out.print(a, "{d}", .{i + 1});
        for (roles.items, role_places) |c, places| try out.print(a, " {s}", .{try cell(a, roleValue(s, rows[source], c), places)});
        for (design_places, 0..) |places, j| try out.print(a, " {s}", .{try cell(a, d.x[i * d.p + j], places)});
        try out.append(a, '\n');
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
    const designs = try a.alloc(matrix.Design, groups.len);
    for (groups, designs) |group, *d| {
        if (s.freq orelse s.weight) |_| for (group.rows) |row| for ([_]?usize{ s.freq, s.weight }) |role| if (role) |c| {
            if (row[c] == .num and !std.math.isNan(row[c].num) and !std.math.isFinite(row[c].num)) return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: nonfinite FREQ or WEIGHT value", .{});
        };
        d.* = matrix.build(a, s.input.ds, group.rows, s.model) catch |err| {
            if (err == error.OutOfMemory) return err;
            return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: invalid effects, no complete observations, or nonfinite design value", .{});
        };
    }
    // ponytail: one OUTDESIGN/OUTPARM layout for all BY groups; groups whose
    // observed levels give different columns would need per-group layouts.
    if ((s.outdesign != null or s.outparm != null) and designs.len > 1) for (designs[1..]) |d| if (!sameColumns(designs[0], d))
        return proc.failGap(cx.diags, 0, "PROC GLMMOD: output data sets for BY groups with different design columns are not implemented", .{});
    var body: std.ArrayList(u8) = .empty;
    if (!s.noprint) for (groups, designs) |group, d| try render(cx, &body, s, d, group.rows);

    const ds = s.input.ds;
    var design_output: ?*Dataset = null;
    var parm_output: ?*Dataset = null;
    if (s.outdesign) |name| {
        if (cx.lib.readonlyOut(name)) return cx.lib.failReadonly(name);
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, name);
        var roles: std.ArrayList(usize) = .empty;
        try roles.appendSlice(a, s.by_cols);
        try roles.append(a, s.model.response);
        if (s.freq) |c| try roles.append(a, c);
        if (s.weight) |c| try roles.append(a, c);
        for (roles.items) |c| if (output.indexOf(ds.columns.items[c].name) == null) {
            _ = try output.addColumnLike(ds.columns.items[c].name, ds.columns.items[c]);
        };
        const first = designs[0];
        for (0..first.p) |j| {
            const colname = try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, j + @as(usize, if (s.zerobased) 0 else 1) });
            if (colname.len > 32) return cx.diags.fail(error.ParseError, 0, "PROC GLMMOD: design column name exceeds 32 characters", .{});
            _ = try outputColumn(cx, output, colname, .num);
            output.setLabel(colname, try columnLabel(a, first, first.columns[j]));
        }
        const width = output.columns.items.len;
        const cells = try a.alloc(Value, width);
        for (groups, designs) |group, d| for (d.source_rows, 0..) |source, i| {
            const row = group.rows[source];
            for (output.columns.items[0 .. width - d.p], 0..) |col, k| {
                const c = ds.indexOf(col.name).?;
                cells[k] = if (s.freq == c and row[c] == .num) .{ .num = roleValue(s, row, c) } else row[c];
            }
            for (0..d.p) |j| cells[width - d.p + j] = .{ .num = d.x[i * d.p + j] };
            try output.appendRow(cells);
        };
        design_output = output;
    }
    if (s.outparm) |name| {
        if (cx.lib.readonlyOut(name)) return cx.lib.failReadonly(name);
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, name);
        for (s.by_cols) |c| _ = try outputColumn(cx, output, ds.columns.items[c].name, ds.columns.items[c].type);
        for (s.by_cols, 0..) |c, k| output.columns.items[k] = ds.columns.items[c];
        _ = try outputColumn(cx, output, "_COLNUM_", .num);
        output.setLabel("_COLNUM_", "Design matrix column number");
        _ = try outputColumn(cx, output, "EFFNAME", .char);
        output.setLen("EFFNAME", s.namelen);
        output.setLabel("EFFNAME", "Effect name");
        for (designs[0].classes) |class| {
            const original = ds.columns.items[class.column];
            _ = try outputColumn(cx, output, original.name, .char);
            var width = if (original.type == .char) original.len orelse 8 else @as(usize, 12);
            for (designs) |d| for (d.classes) |c| if (c.column == class.column) {
                for (c.map.levels) |level| width = @max(width, level.label.len);
            };
            output.setLen(original.name, width);
        }
        const nb = s.by_cols.len;
        const cells = try a.alloc(Value, designs[0].classes.len + 2 + nb);
        for (groups, designs) |group, d| for (d.columns, 0..) |column, j| {
            for (s.by_cols, 0..) |c, k| cells[k] = group.rows[0][c];
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
    try std.testing.expectError(error.ParseError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input; class group / truncate; model y=group; run;", &d)));
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
    try std.testing.expectError(error.ExecError, run(cx, &sink, try lex.tokenize(a, "proc glmmod data=design_input outdesign=bad noprint; model y=group; run;", &d)));
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
