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
            if (result.namelen < 20 or result.namelen > 200) return invalid(cx, t, i);
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
        } else if (kw(t, i, "by") or kw(t, i, "freq") or kw(t, i, "weight")) {
            return proc.failGap(cx.diags, t[i].line, "PROC GLMMOD: {s} output roles are not implemented", .{t[i].text});
        } else if (!kw(t, i, "run") and !kw(t, i, "quit") and !kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC GLMMOD: MODEL statement required", .{});
    result.input.ds = try by.withFormats(cx.arena, result.input.ds, formats.items);
    result.model.classes = classes.items;
    result.model.effects = model_effects.items;
    if (!result.noprint) return proc.failGap(cx.diags, 0, "PROC GLMMOD: direct listing is not implemented; use NOPRINT with OUTDESIGN/OUTPARM", .{});
    return result;
}

fn outputColumn(cx: proc.ProcCtx, ds: *Dataset, name: []const u8, t: @import("../pdv.zig").VarType) diag.Error!usize {
    if (ds.indexOf(name) != null) return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: duplicate output column {s}", .{name});
    return ds.addColumn(name, t);
}

pub fn run(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const d = matrix.build(cx.arena, s.input.ds, s.input.ds.rows.items, s.model) catch |err| {
        if (err == error.OutOfMemory) return err;
        return cx.diags.fail(error.ExecError, 0, "PROC GLMMOD: invalid effects, no complete observations, or nonfinite design value", .{});
    };
    const a = cx.arena;
    var design_output: ?*Dataset = null;
    var parm_output: ?*Dataset = null;
    if (s.outdesign) |name| {
        if (cx.lib.readonlyOut(name)) return cx.lib.failReadonly(name);
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, name);
        const response = s.input.ds.columns.items[s.model.response];
        _ = try output.addColumnLike(response.name, response);
        for (0..d.p) |j| {
            const colname = try std.fmt.allocPrint(a, "{s}{d}", .{ s.prefix, j + @as(usize, if (s.zerobased) 0 else 1) });
            if (colname.len > 32) return cx.diags.fail(error.ParseError, 0, "PROC GLMMOD: design column name exceeds 32 characters", .{});
            _ = try outputColumn(cx, output, colname, .num);
        }
        const cells = try a.alloc(Value, d.p + 1);
        for (d.source_rows, 0..) |source, i| {
            cells[0] = s.input.ds.rows.items[source][s.model.response];
            for (0..d.p) |j| cells[j + 1] = .{ .num = d.x[i * d.p + j] };
            try output.appendRow(cells);
        }
        design_output = output;
    }
    if (s.outparm) |name| {
        if (cx.lib.readonlyOut(name)) return cx.lib.failReadonly(name);
        const output = try a.create(Dataset);
        output.* = Dataset.init(a, name);
        _ = try outputColumn(cx, output, "_COLNUM_", .num);
        output.setLabel("_COLNUM_", "Design matrix column number");
        _ = try outputColumn(cx, output, "EFFNAME", .char);
        output.setLen("EFFNAME", s.namelen);
        output.setLabel("EFFNAME", "Effect name");
        for (d.classes) |class| {
            const original = s.input.ds.columns.items[class.column];
            _ = try outputColumn(cx, output, original.name, .char);
            var width = if (original.type == .char) original.len orelse 8 else @as(usize, 12);
            for (class.map.levels) |level| width = @max(width, level.label.len);
            output.setLen(original.name, width);
        }
        const cells = try a.alloc(Value, d.classes.len + 2);
        for (d.columns, 0..) |column, j| {
            cells[0] = .{ .num = @floatFromInt(j + @as(usize, if (s.zerobased) 0 else 1)) };
            cells[1] = .{ .str = column.effect_name[0..@min(s.namelen, column.effect_name.len)] };
            for (d.classes, 0..) |class, k| cells[k + 2] = .{ .str = if (column.class_values[k]) |level| class.map.levels[level].label else "" };
            try output.appendRow(cells);
        }
        parm_output = output;
    }
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
    try run(cx, try lex.tokenize(a, "proc glmmod data=design_input outdesign=matrix outparm=columns noprint; class group h; model y=group h group*h x group*x; run;", &diags));
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
    try run(cx, try lex.tokenize(a, "proc glmmod data=design_input outdesign=d outparm=p prefix=X zerobased noprint; model y=x|x|x / noint; run;", &d));
    const p = lib.find("p").?;
    const x = lib.find("d").?;
    try std.testing.expectEqual(@as(usize, 3), p.rowCount());
    try std.testing.expectEqualStrings("x*x*x", p.rows.items[2][1].str);
    try std.testing.expectEqualStrings("X0", x.columns.items[1].name);
    try std.testing.expectEqual(@as(f64, 0), p.rows.items[0][0].num);
    try std.testing.expectEqual(@as(f64, 1728), x.rows.items[11][3].num);
    try run(cx, try lex.tokenize(a, "proc glmmod data=design_input order=data outdesign=ordered outparm=ordered_parm noprint; class group h; model y=h*group / noint; run;", &d));
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
    try std.testing.expectError(error.ParseError, run(cx, try lex.tokenize(a, "proc glmmod data=design_input; model y=x; run;", &d)));
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
    try std.testing.expectError(error.ExecError, run(cx, try lex.tokenize(a, "proc glmmod data=design_input outdesign=bad noprint; model y=group; run;", &d)));
    try std.testing.expect(d.hasErrors());
    try std.testing.expect(lib.find("bad") == null);
    try std.testing.expectError(error.ParseError, run(cx, try lex.tokenize(a, "proc glmmod data=design_input noprint; class group; run;", &d)));
    diag.resetGap();
    defer diag.resetGap();
    try std.testing.expectError(error.ParseError, run(cx, try lex.tokenize(a, "proc glmmod data=design_input outdesign=bad noprint; by group; model y=x; run;", &d)));
    try std.testing.expect(diag.gapHit());
    try std.testing.expect(lib.find("bad") == null);
}
