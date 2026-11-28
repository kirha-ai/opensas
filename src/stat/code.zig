//! Shared CODE statement/data-step emitter, S154 physical pp.421-424.
//! Emits executable coefficients/indicator products; does not serialize models.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Value = @import("../value.zig").Value;
const Dataset = @import("../dataset.zig").Dataset;
const coded = @import("design_matrix.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Target = union(enum) { log, listing, path: []const u8, fileref: []const u8 };
pub const Lookup = enum { auto, linear, binary, select };
pub const Options = struct { target: Target = .log, format: []const u8 = "BEST20.", linesize: usize = 78, lookup: Lookup = .auto, dummies: bool = false, impute: bool = false, residual: bool = false, group: []const u8 = "", line: usize = 0 };
pub const Class = struct { name: []const u8, values: []const Value };
pub const Factor = union(enum) { numeric: []const u8, class: struct { index: usize, level: usize } };
pub const Term = struct { coefficient: f64, factors: []const Factor, label: []const u8 };
pub const Model = struct { procedure: []const u8, response: []const u8, intercept: f64 = 0, terms: []const Term, classes: []const Class = &.{}, mean: f64 };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn validName(s: []const u8, max: usize) bool {
    if (s.len == 0 or s.len > max or !(std.ascii.isAlphabetic(s[0]) or s[0] == '_')) return false;
    for (s[1..]) |c| if (!(std.ascii.isAlphanumeric(c) or c == '_')) return false;
    return true;
}
fn bad(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "CODE: invalid option near {s}", .{if (i < t.len) t[i].text else "<end>"});
}
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Options {
    var o = Options{ .line = if (t.len > 0) t[0].line else 0 };
    var i: usize = 0;
    var file = false;
    var catalog = false;
    var error_requested = false;
    while (i < t.len) {
        const token = t[i];
        if (token.tag != .name) return bad(cx, t, i);
        i += 1;
        if (eq(token.text, "dummies") or eq(token.text, "nodummies")) {
            o.dummies = eq(token.text, "dummies");
            continue;
        }
        if (eq(token.text, "error") or eq(token.text, "noerror")) {
            error_requested = eq(token.text, "error");
            continue;
        }
        if (eq(token.text, "residual") or eq(token.text, "noresidual")) {
            o.residual = eq(token.text, "residual");
            continue;
        }
        if (eq(token.text, "impute")) {
            o.impute = true;
            continue;
        }
        if (!at(t, i, .eq)) return bad(cx, t, i);
        i += 1;
        if (eq(token.text, "file")) {
            if (file) return proc.failGap(cx.diags, token.line, "CODE: repeated FILE options are not verified", .{});
            file = true;
            if (at(t, i, .string)) {
                if (t[i].text.len == 0) return bad(cx, t, i);
                o.target = .{ .path = t[i].text };
                i += 1;
            } else if (at(t, i, .name)) {
                if (!validName(t[i].text, 8)) return cx.diags.fail(error.ParseError, token.line, "CODE FILE fileref must be a SAS name of at most eight characters", .{});
                o.target = if (eq(t[i].text, "log")) .log else if (eq(t[i].text, "print")) .listing else .{ .fileref = t[i].text };
                i += 1;
            } else return bad(cx, t, i);
        } else if (eq(token.text, "catalog") or eq(token.text, "cat")) {
            catalog = true;
            if (!at(t, i, .name)) return bad(cx, t, i);
            i += 1;
            var levels: usize = 1;
            while (at(t, i, .dot)) {
                i += 1;
                if (!at(t, i, .name)) return bad(cx, t, i);
                i += 1;
                levels += 1;
            }
            if (levels > 4) return bad(cx, t, i - 1);
        } else if (eq(token.text, "group")) {
            if (!at(t, i, .name) or !validName(t[i].text, 16)) return bad(cx, t, i);
            o.group = t[i].text;
            i += 1;
        } else if (eq(token.text, "linesize") or eq(token.text, "ls")) {
            if (!at(t, i, .number)) return bad(cx, t, i);
            o.linesize = std.fmt.parseInt(usize, t[i].text, 10) catch return bad(cx, t, i);
            i += 1;
            if (o.linesize < 78 or o.linesize > 254) return cx.diags.fail(error.ParseError, token.line, "CODE LINESIZE must be between78 and254", .{});
        } else if (eq(token.text, "lookup")) {
            if (!at(t, i, .name)) return bad(cx, t, i);
            o.lookup = for (std.enums.values(Lookup)) |method| {
                if (eq(t[i].text, @tagName(method))) break method;
            } else return bad(cx, t, i);
            i += 1;
        } else if (eq(token.text, "format")) {
            const begin = i;
            if (!at(t, i, .name) and !at(t, i, .number)) return bad(cx, t, i);
            i += 1;
            if (at(t, i, .dot)) {
                i += 1;
                if (at(t, i, .number)) i += 1;
            }
            var value: std.ArrayList(u8) = .empty;
            for (t[begin..i]) |part| try value.appendSlice(cx.arena, if (part.tag == .dot) "." else part.text);
            o.format = value.items;
            // A numeric format must emit a DATA-step numeric literal, not commas/dates.
            const lead = std.mem.indexOfScalar(u8, o.format, '.') orelse return bad(cx, t, begin);
            const prefix = o.format[0..lead];
            var digits: usize = 0;
            while (digits < prefix.len and !std.ascii.isDigit(prefix[digits])) digits += 1;
            const name = prefix[0..digits];
            if (name.len > 0 and !eq(name, "best") and !eq(name, "e") and !eq(name, "f")) return proc.failGap(cx.diags, token.line, "CODE FORMAT={s} cannot be emitted as a numeric literal", .{o.format});
        } else return bad(cx, t, i - 2);
    }
    if (file and catalog) return cx.diags.fail(error.ParseError, o.line, "CODE cannot specify both FILE and CATALOG", .{});
    if (catalog) return proc.failGap(cx.diags, o.line, "CODE catalog entries are not implemented", .{});
    if (error_requested) return proc.failGap(cx.diags, o.line, "CODE ERROR functions are not implemented", .{});
    return o;
}
fn literal(a: std.mem.Allocator, value: Value) ![]const u8 {
    return switch (value) {
        .num => |v| if (std.math.isFinite(v)) std.fmt.allocPrint(a, "{d}", .{v}) else error.UnsupportedClassValue,
        .str => |s| blk: {
            var text: std.ArrayList(u8) = .empty;
            try text.append(a, '\'');
            for (s) |c| {
                try text.append(a, c);
                if (c == '\'') try text.append(a, c);
            }
            try text.append(a, '\'');
            break :blk text.items;
        },
    };
}
fn number(a: std.mem.Allocator, value: f64, format: []const u8) ![]const u8 {
    if (!std.math.isFinite(value)) return error.InvalidCoefficient;
    const text = std.mem.trim(u8, try @import("../format.zig").apply(a, .{ .num = value }, format), " ");
    const parsed = std.fmt.parseFloat(f64, text) catch return error.InvalidNumericFormat;
    if (!std.math.isFinite(parsed)) return error.InvalidNumericFormat;
    return text;
}
fn internal(a: std.mem.Allocator, base: []const u8, group: []const u8) ![]const u8 {
    return if (group.len == 0) base else std.fmt.allocPrint(a, "{s}_{s}", .{ base, group });
}
fn dummy(a: std.mem.Allocator, c: usize, l: usize, g: []const u8) ![]const u8 {
    return internal(a, try std.fmt.allocPrint(a, "_CODE{d}_{d}", .{ c, l }), g);
}
const Writer = struct {
    a: std.mem.Allocator,
    out: std.ArrayList(u8) = .empty,
    width: usize,
    fn line(w: *Writer, initial: []const u8) !void {
        var text = initial;
        while (text.len > w.width) {
            var quote = false;
            var split: ?usize = null;
            for (text[0..w.width], 0..) |c, i| {
                if (c == '\'') quote = !quote;
                if (c == ' ' and !quote) split = i;
            }
            const at_space = split orelse return error.UnrepresentableLine;
            if (at_space == 0) return error.UnrepresentableLine;
            try w.out.appendSlice(w.a, text[0..at_space]);
            try w.out.append(w.a, '\n');
            text = std.mem.trimStart(u8, text[at_space + 1 ..], " ");
        }
        try w.out.appendSlice(w.a, text);
        try w.out.append(w.a, '\n');
    }
    fn print(w: *Writer, comptime fmt: []const u8, args: anytype) !void {
        try w.line(try std.fmt.allocPrint(w.a, fmt, args));
    }
};
fn binary(w: *Writer, c: Class, order: []const usize, index: []const u8) !void {
    if (order.len == 0) return;
    const middle = order.len / 2;
    const k = order[middle];
    const value = try literal(w.a, c.values[k]);
    try w.print("if {s} = {s} then {s}={d};", .{ c.name, value, index, k + 1 });
    if (middle > 0) {
        try w.print("else if {s} < {s} then do;", .{ c.name, value });
        try binary(w, c, order[0..middle], index);
        try w.line("end;");
    }
    if (middle + 1 < order.len) {
        try w.line("else do;");
        try binary(w, c, order[middle + 1 ..], index);
        try w.line("end;");
    }
}
pub fn generate(a: std.mem.Allocator, m: Model, o: Options) ![]const u8 {
    if (!validName(m.response, 30)) return error.UnsupportedVariableName;
    const pred = try std.fmt.allocPrint(a, "P_{s}", .{m.response});
    const bad_name = try internal(a, "_LMR_BAD", o.group);
    const lp = try internal(a, "_LP0", o.group);
    const skip = if (o.group.len == 0) "_SKIP_000" else try std.fmt.allocPrint(a, "_SKIP_{s}", .{o.group});
    var numeric: std.ArrayList([]const u8) = .empty;
    for (m.terms) |term| for (term.factors) |factor| if (factor == .numeric) {
        if (!validName(factor.numeric, 32)) return error.UnsupportedVariableName;
        var found = false;
        for (numeric.items) |n| found = found or eq(n, factor.numeric);
        if (!found) try numeric.append(a, factor.numeric);
    };
    for (numeric.items) |n| if (eq(n, bad_name) or eq(n, lp) or eq(n, pred) or eq(n, "_WARN_")) return error.ReservedVariableCollision;
    if (eq(m.response, bad_name) or eq(m.response, lp) or (o.impute and eq(m.response, "_WARN_"))) return error.ReservedVariableCollision;
    for (m.classes, 0..) |c, ci| {
        if (c.values.len == 0) return error.UnsupportedClassValue;
        const index_name = try internal(a, try std.fmt.allocPrint(a, "_CODEI{d}", .{ci}), o.group);
        for (numeric.items) |n| if (eq(n, index_name)) return error.ReservedVariableCollision;
        for (m.classes) |other| if (eq(other.name, index_name)) return error.ReservedVariableCollision;
        for (c.values, 0..) |_, k| {
            const name = try dummy(a, ci, k, o.group);
            for (numeric.items) |n| if (eq(n, name)) return error.ReservedVariableCollision;
            for (m.classes) |other| if (eq(other.name, name)) return error.ReservedVariableCollision;
        }
    }
    var w = Writer{ .a = a, .width = o.linesize };
    try w.line("*****************************************;");
    try w.print("** SAS Scoring Code for PROC {s};", .{m.procedure});
    try w.line("*****************************************;");
    try w.line("");
    try w.print("label {s} = 'Predicted: {s}' ;", .{ pred, m.response });
    try w.print("drop {s};", .{bad_name});
    try w.print("{s}=0;", .{bad_name});
    if (o.impute) {
        try w.line("length _WARN_ $2;");
        try w.line("_WARN_='  ';");
    }
    try w.line("");
    if (numeric.items.len > 0) {
        try w.line("*** Check interval variables for missing values;");
        var names: std.ArrayList(u8) = .empty;
        for (numeric.items, 0..) |n, i| {
            if (i > 0) try names.append(a, ',');
            try names.appendSlice(a, n);
        }
        try w.print("if nmiss({s}) then do;", .{names.items});
        try w.print("   {s}=1;", .{bad_name});
        if (o.impute) try w.line("   if _WARN_=' U' or _WARN_='MU' then _WARN_='MU'; else _WARN_='M ';") else try w.print("   goto {s};", .{skip});
        try w.line("end;");
        try w.line("");
    }
    for (m.classes, 0..) |c, ci| {
        if (!validName(c.name, 32) or eq(c.name, bad_name) or eq(c.name, lp) or eq(c.name, pred) or eq(c.name, "_WARN_")) return error.ReservedVariableCollision;
        const idx = try internal(a, try std.fmt.allocPrint(a, "_CODEI{d}", .{ci}), o.group);
        try w.print("drop {s};", .{idx});
        try w.print("{s}=0;", .{idx});
        try w.print("if missing({s}) then do;", .{c.name});
        try w.print(" {s}=1;", .{bad_name});
        if (o.impute) try w.line(" if _WARN_=' U' or _WARN_='MU' then _WARN_='MU'; else _WARN_='M ';");
        try w.line("end;");
        try w.line("else do;");
        const method = if (o.lookup == .auto) (if (c.values.len < 5) Lookup.linear else Lookup.binary) else o.lookup;
        switch (method) {
            .linear => {
                for (c.values, 0..) |v, k| try w.print("{s}if {s} = {s} then {s}={d};", .{ if (k == 0) @as([]const u8, "") else "else ", c.name, try literal(a, v), idx, k + 1 });
            },
            .select => {
                try w.print("select ({s});", .{c.name});
                for (c.values, 0..) |v, k| try w.print("when ({s}) {s}={d};", .{ try literal(a, v), idx, k + 1 });
                try w.line("otherwise;");
                try w.line("end;");
            },
            .binary => {
                const order = try a.alloc(usize, c.values.len);
                for (order, 0..) |*v, k| v.* = k;
                std.mem.sort(usize, order, c.values, struct {
                    fn less(values: []const Value, l: usize, r: usize) bool {
                        return proc.cmpValue(values[l], values[r]) == .lt;
                    }
                }.less);
                try binary(&w, c, order, idx);
            },
            .auto => unreachable,
        }
        try w.print("if {s}=0 then do;", .{idx});
        try w.print(" {s}=1;", .{bad_name});
        if (o.impute) try w.line(" if _WARN_='M' or _WARN_='MU' then _WARN_='MU'; else _WARN_=' U';");
        try w.line("end;");
        try w.line("end;");
        for (c.values, 0..) |_, k| {
            const name = try dummy(a, ci, k, o.group);
            if (!o.dummies) try w.print("drop {s};", .{name});
            try w.print("{s}=({s}={d});", .{ name, idx, k + 1 });
        }
    }
    if (m.classes.len > 0 or o.impute) try w.print("if {s}=1 then goto {s};", .{ bad_name, skip });
    try w.line("*** Compute Linear Predictors;");
    try w.print("drop {s};", .{lp});
    try w.print("{s} = 0;", .{lp});
    try w.line("");
    for (m.terms) |term| {
        try w.print("*** Effect: {s};", .{term.label});
        var expression: std.ArrayList(u8) = .empty;
        try expression.print(a, "{s} = {s} + ({s})", .{ lp, lp, try number(a, term.coefficient, o.format) });
        for (term.factors) |factor| try expression.print(a, " * {s}", .{switch (factor) {
            .numeric => |n| n,
            .class => |c| try dummy(a, c.index, c.level, o.group),
        }});
        try expression.append(a, ';');
        try w.line(expression.items);
    }
    try w.line("");
    try w.line("*** Predicted values;");
    try w.print("{s} = {s} +     {s};", .{ lp, lp, try number(a, m.intercept, o.format) });
    try w.print("{s}:", .{skip});
    try w.print("if {s}=1 then do;", .{bad_name});
    try w.print("   {s} = {s};", .{ pred, if (o.impute) try number(a, m.mean, o.format) else "." });
    try w.line("end;");
    try w.line("else do;");
    try w.print("   {s} = {s};", .{ pred, lp });
    try w.line("end;");
    if (o.residual) {
        try w.print("label R_{s}='Residual: {s}';", .{ m.response, m.response });
        try w.print("R_{s} = {s} - {s};", .{ m.response, m.response, pred });
    }
    return w.out.items;
}
pub fn publish(cx: proc.ProcCtx, out: *std.ArrayList(u8), m: Model, o: Options) diag.Error!void {
    const bytes = generate(cx.arena, m, o) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else proc.failGap(cx.diags, o.line, "CODE: scoring representation is not implemented ({t})", .{err});
    try publishBytes(cx, out, bytes, o);
}
pub fn publishBytes(cx: proc.ProcCtx, out: *std.ArrayList(u8), bytes: []const u8, o: Options) diag.Error!void {
    const path = switch (o.target) {
        .log => {
            try cx.diags.plainLine(bytes);
            return;
        },
        .listing => {
            try out.appendSlice(cx.arena, bytes);
            return;
        },
        .path => |p| p,
        .fileref => |f| if (cx.resolve_fileref) |resolve| resolve(f) orelse try std.fmt.allocPrint(cx.arena, "{s}.txt", .{f}) else try std.fmt.allocPrint(cx.arena, "{s}.txt", .{f}),
    };
    if (!@import("../io.zig").writeFileRaw(path, bytes)) return cx.diags.fail(error.ExecError, o.line, "CODE: cannot write scoring file {s}", .{path});
}

pub fn fromDesign(a: std.mem.Allocator, ds: *const Dataset, s: coded.Spec, d: coded.Design, coefficients: []const f64, mean: f64) !Model {
    if (coefficients.len != d.p) return error.InvalidInput;
    var class_list: std.ArrayList(Class) = .empty;
    const mapping = try a.alloc(?usize, d.classes.len);
    @memset(mapping, null);
    for (d.columns) |column| for (column.class_values, 0..) |level, i| if (level != null and mapping[i] == null) {
        const c = d.classes[i];
        if (ds.columns.items[c.column].format != null) return error.UnsupportedClassFormat;
        const values = try a.alloc(Value, c.map.levels.len);
        for (c.map.levels, values) |v, *target| target.* = v.value;
        mapping[i] = class_list.items.len;
        try class_list.append(a, .{ .name = ds.columns.items[c.column].name, .values = values });
    };
    var terms: std.ArrayList(Term) = .empty;
    var intercept: f64 = 0;
    for (d.columns, coefficients) |column, coefficient| {
        if (column.effect_index) |ei| {
            const e = try coded.normalize(a, ds, s.classes, s.effects[ei]);
            var factors: std.ArrayList(Factor) = .empty;
            for (e.continuous) |ci| try factors.append(a, .{ .numeric = ds.columns.items[ci].name });
            for (column.class_values, 0..) |level, i| if (level) |k| try factors.append(a, .{ .class = .{ .index = mapping[i].?, .level = k } });
            try terms.append(a, .{ .coefficient = coefficient, .factors = factors.items, .label = column.effect_name });
        } else intercept = coefficient;
    }
    return .{ .procedure = "GLM", .response = ds.columns.items[s.response].name, .intercept = intercept, .terms = terms.items, .classes = class_list.items, .mean = mean };
}

const Testing = struct {
    fn score(a: std.mem.Allocator, source: *Dataset, code: []const u8) !*Dataset {
        var d = diag.Diagnostics.init(a);
        var lib = @import("../exec.zig").Library.init(a);
        try lib.put("incoming", source);
        const program = try @import("../parser.zig").parse(a, try std.mem.concat(a, u8, &.{ "set incoming;\n", code }), &d);
        var pdv = @import("../pdv.zig").Pdv.init(a);
        var evaluator = @import("../eval.zig").Evaluator{ .arena = a, .pdv = &pdv, .diags = &d, .call_fn = &@import("../functions.zig").dispatch };
        var executor = @import("../exec.zig").Executor.init(a, &pdv, &d, &evaluator, &lib);
        if (std.mem.indexOf(u8, code, "length _WARN_") != null) executor.declared = &.{.{ .name = "_WARN_", .type = .char, .len = 2, .after_input = true }};
        const result = try a.create(Dataset);
        result.* = Dataset.init(a, "scored");
        try executor.run(program, result);
        try std.testing.expect(!d.hasErrors());
        return result;
    }
};

test "COMMON020 generated class polynomial interaction code executes independent DATA steps for all lookups" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var training = Dataset.init(a, "training");
    _ = try training.addColumn("x", .num);
    _ = try training.addColumn("g", .char);
    _ = try training.addColumn("y", .num);
    const labels = [_][]const u8{ "A", "B", "C", "D", "O'Reilly" };
    for (labels, 0..) |label, g| for ([_]f64{ 0, 1, 2 }) |x| {
        const offset: @TypeOf(x) = @floatFromInt(g);
        try training.appendRow(&.{ .{ .num = x }, .{ .str = label }, .{ .num = 2 + 3 * x + 0.5 * x * x + offset + 0.2 * offset * x } });
    };
    const basis = coded.Spec{ .response = 2, .classes = &.{1}, .effects = &.{ .{ .factors = &.{0} }, .{ .factors = &.{ 0, 0 } }, .{ .factors = &.{1} }, .{ .factors = &.{ 0, 1 } } } };
    const design = try coded.build(a, &training, training.rows.items, basis);
    const y = try a.alloc(f64, design.n);
    for (training.rows.items, y) |row, *value| value.* = row[2].num;
    const fitted = try @import("reg_fit.zig").fit(a, design.x, y, design.n, design.p, null);
    const model = try fromDesign(a, &training, basis, design, fitted.coefficients, fitted.y_mean);
    var incoming = Dataset.init(a, "incoming");
    for (training.columns.items) |column| _ = try incoming.addColumnLike(column.name, column);
    for (labels, 0..) |label, g| for ([_]f64{ 0.5, 1.5, 2.5 }) |x| {
        const offset: f64 = @floatFromInt(g);
        const expected = 2 + 3 * x + 0.5 * x * x + offset + 0.2 * offset * x;
        try incoming.appendRow(&.{ .{ .num = x }, .{ .str = label }, .{ .num = expected + 7 } });
    };
    try incoming.appendRow(&.{ Value.missing, .{ .str = "A" }, .{ .num = 0 } });
    try incoming.appendRow(&.{ .{ .num = 1 }, .{ .str = "unknown" }, .{ .num = 0 } });
    try incoming.appendRow(&.{ Value.specialMissing('A'), .{ .str = "unknown" }, .{ .num = 0 } });
    try incoming.appendRow(&.{ .{ .num = 1 }, .{ .str = "" }, .{ .num = 0 } });
    for (std.enums.values(Lookup)) |lookup| {
        const text = try generate(a, model, .{ .lookup = lookup, .residual = true, .impute = true });
        var lines = std.mem.tokenizeScalar(u8, text, '\n');
        while (lines.next()) |line| try std.testing.expect(line.len <= 78);
        const result = try Testing.score(a, &incoming, text);
        try std.testing.expectEqual(incoming.rows.items.len, result.rows.items.len);
        const pi = result.indexOf("P_y").?;
        const ri = result.indexOf("R_y").?;
        const wi = result.indexOf("_WARN_").?;
        for (result.rows.items[0..15], incoming.rows.items[0..15]) |row, original| {
            try std.testing.expectApproxEqAbs(original[2].num - 7, row[pi].num, 2e-11);
            try std.testing.expectApproxEqAbs(@as(f64, 7), row[ri].num, 2e-11);
        }
        for (result.rows.items[15..]) |row| try std.testing.expectApproxEqAbs(fitted.y_mean, row[pi].num, 2e-12);
        try std.testing.expectEqualStrings("M", std.mem.trimEnd(u8, result.rows.items[15][wi].str, " "));
        try std.testing.expectEqualStrings(" U", result.rows.items[16][wi].str);
        try std.testing.expectEqualStrings("MU", result.rows.items[17][wi].str);
        try std.testing.expectEqualStrings("M", std.mem.trimEnd(u8, result.rows.items[18][wi].str, " "));
        try std.testing.expect(result.indexOf("_LP0") == null and result.indexOf("_LMR_BAD") == null and result.indexOf("_CODE0_0") == null);
    }
    const retained = try Testing.score(a, &incoming, try generate(a, model, .{ .dummies = true, .group = "batch" }));
    try std.testing.expect(retained.indexOf("_CODE0_0_batch") != null);
    try std.testing.expect(retained.rows.items[15][retained.indexOf("P_y").?].isMissing());
    var no_response = Dataset.init(a, "incoming");
    _ = try no_response.addColumn("x", .num);
    _ = try no_response.addColumn("g", .char);
    try no_response.appendRow(&.{ .{ .num = 1 }, .{ .str = "A" } });
    const scored = try Testing.score(a, &no_response, try generate(a, model, .{ .residual = true }));
    try std.testing.expectApproxEqAbs(@as(f64, 5.5), scored.rows.items[0][scored.indexOf("P_y").?].num, 2e-11);
    try std.testing.expect(scored.rows.items[0][scored.indexOf("R_y").?].isMissing());
}

test "COMMON020 declarations enforce targets formats line sizes and invalid target languages" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx = proc.ProcCtx{ .arena = a, .lib = &lib, .diags = &d };
    const samples = [_][]const u8{ "file=scocode residual impute group=one lookup=select format=best20. ls=100", "file='output/code.sas' nodummies noerror noresidual" };
    for (samples) |source| {
        const tokens = try lex.tokenize(a, source, &d);
        _ = try parse(cx, tokens[0 .. tokens.len - 1]);
    }
    for ([_][]const u8{ "file=toolongname", "file=x catalog=work.foo", "linesize=77", "linesize=255", "language=python", "lookup=hash" }) |source| {
        const tokens = try lex.tokenize(a, source, &d);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, parse(cx, tokens[0 .. tokens.len - 1]));
        try std.testing.expect(!diag.gapHit());
    }
    for ([_][]const u8{ "catalog=work.foo", "error", "format=date9." }) |source| {
        const tokens = try lex.tokenize(a, source, &d);
        diag.resetGap();
        defer diag.resetGap();
        try std.testing.expectError(error.ParseError, parse(cx, tokens[0 .. tokens.len - 1]));
        try std.testing.expect(diag.gapHit());
    }
}
