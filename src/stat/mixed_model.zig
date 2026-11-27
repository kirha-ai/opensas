//! MIXED CLASS/MODEL declarations and fixed-effect parameterization.
//! S154 physical pp.6639-6640,6653-6668,6707-6712. RANDOM/REPEATED
//! statements remain visible in the Spec; this module never claims to fit them.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const matrix = @import("design_matrix.zig");
const levels = @import("class_levels.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Options = struct {
    alpha: f64 = 0.05,
    solution: bool = false,
    cl: bool = false,
    notest: bool = false,
    intercept_test: bool = false,
    ddfm: enum { default, residual } = .default,
    singular: f64 = 1e4 * std.math.floatEps(f64),
};
pub const Spec = struct {
    source: *const Dataset,
    matrix: matrix.Spec,
    required_columns: []const usize,
    options: Options,
    has_random: bool = false,
    has_repeated: bool = false,
    line: usize = 0,
};
/// Test/front-end adapter. parse accepts any structurally identical statement
/// slice, including mixed_parse.Statement, avoiding a front-end import cycle.
pub const Statement = struct { kind: enum { class, model, random, repeated, parms, contrast, estimate }, tokens: []const lex.Token, line: usize };
fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, name: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, name);
}
fn bad(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, if (i < t.len) t[i].line else 0, "PROC MIXED: invalid CLASS/MODEL token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn variable(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: *usize) diag.Error!usize {
    if (!at(t, i.*, .name)) return bad(cx, t, i.*);
    const token = t[i.*];
    i.* += 1;
    return ds.indexOf(token.text) orelse return cx.diags.fail(error.ParseError, token.line, "PROC MIXED: variable {s} not found", .{token.text});
}
fn unique(a: std.mem.Allocator, v: *std.ArrayList(usize), ci: usize) !void {
    if (std.mem.indexOfScalar(usize, v.items, ci) == null) try v.append(a, ci);
}
fn reference(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, global: bool) diag.Error!levels.Reference {
    if (kw(t, i.*, "first")) {
        i.* += 1;
        return .first;
    }
    if (kw(t, i.*, "last")) {
        i.* += 1;
        return .last;
    }
    if (!global and at(t, i.*, .string)) {
        const label = t[i.*].text;
        i.* += 1;
        return .{ .label = label };
    }
    return bad(cx, t, i.*);
}
fn classStatement(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, classes: *std.ArrayList(usize), refs: *std.ArrayList(?levels.Reference)) diag.Error!void {
    const begin = classes.items.len;
    var i: usize = 0;
    while (i < t.len and !at(t, i, .slash)) {
        const ci = try variable(cx, ds, t, &i);
        if (std.mem.indexOfScalar(usize, classes.items, ci) != null) return proc.failGap(cx.diags, if (i > 0) t[i - 1].line else 0, "PROC MIXED: repeated CLASS declarations are not implemented", .{});
        var ref: ?levels.Reference = null;
        if (at(t, i, .lparen)) {
            i += 1;
            if (!kw(t, i, "ref") or !at(t, i + 1, .eq)) return bad(cx, t, i);
            i += 2;
            ref = try reference(cx, t, &i, false);
            if (!at(t, i, .rparen)) return bad(cx, t, i);
            i += 1;
        }
        try classes.append(cx.arena, ci);
        try refs.append(cx.arena, ref);
        if (at(t, i, .minus) or at(t, i, .colon)) return proc.failGap(cx.diags, t[i].line, "PROC MIXED: CLASS shorthand variable lists are not implemented", .{});
    }
    if (classes.items.len == begin) return cx.diags.fail(error.ParseError, if (t.len > 0) t[0].line else 0, "PROC MIXED: CLASS requires at least one variable", .{});
    if (at(t, i, .slash)) {
        i += 1;
        var global_ref_seen = false;
        while (i < t.len) {
            if (kw(t, i, "truncate")) return proc.failGap(cx.diags, t[i].line, "PROC MIXED: CLASS TRUNCATE is not implemented", .{});
            if (!kw(t, i, "ref") or !at(t, i + 1, .eq)) return bad(cx, t, i);
            if (global_ref_seen) return proc.failGap(cx.diags, t[i].line, "PROC MIXED: repeated global CLASS REF options are not implemented", .{});
            global_ref_seen = true;
            i += 2;
            const ref = try reference(cx, t, &i, true);
            for (begin..refs.items.len) |j| if (refs.items[j] == null) {
                refs.items[j] = ref;
            };
        }
    }
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
        if (nested.items.len == 0 or !at(t, i.*, .rparen)) return bad(cx, t, i.*);
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
            if (!at(t, i, .number)) return bad(cx, t, i);
            degree = std.fmt.parseInt(usize, t[i].text, 10) catch return bad(cx, t, i);
            if (degree == 0) return bad(cx, t, i);
            i += 1;
        }
        if (chain.items.len > 16) return proc.failGap(cx.diags, 0, "PROC MIXED: bar expansion beyond sixteen terms is not implemented", .{});
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
fn modelOptions(cx: proc.ProcCtx, t: []const lex.Token, s: *Spec) diag.Error!void {
    var i: usize = 0;
    while (i < t.len) {
        const token = t[i];
        i += 1;
        if (eq(token.text, "noint")) {
            s.matrix.intercept = false;
            continue;
        }
        if (eq(token.text, "solution") or eq(token.text, "s")) {
            s.options.solution = true;
            continue;
        }
        if (eq(token.text, "cl")) {
            s.options.cl = true;
            continue;
        }
        if (eq(token.text, "notest")) {
            s.options.notest = true;
            continue;
        }
        if (eq(token.text, "intercept")) {
            s.options.intercept_test = true;
            continue;
        }
        if (eq(token.text, "nocontain")) {
            s.options.ddfm = .residual;
            continue;
        }
        if (eq(token.text, "ddfm")) {
            if (!at(t, i, .eq)) return bad(cx, t, i);
            i += 1;
            if (kw(t, i, "residual") or kw(t, i, "res")) {
                s.options.ddfm = .residual;
                i += 1;
                continue;
            }
            for ([_][]const u8{ "contain", "con", "betwithin", "bw", "satterthwaite", "satterth", "sat", "kenwardroger", "kenrog", "kr", "kenwardroger2", "kenrog2", "kr2" }) |name| if (kw(t, i, name)) return proc.failGap(cx.diags, token.line, "PROC MIXED: denominator DF method {s} is not implemented", .{t[i].text});
            return bad(cx, t, i);
        }
        if (eq(token.text, "alpha") or eq(token.text, "singular") or eq(token.text, "htype")) {
            if (!at(t, i, .eq) or !at(t, i + 1, .number)) return bad(cx, t, i);
            i += 1;
            const value = std.fmt.parseFloat(f64, t[i].text) catch return bad(cx, t, i);
            i += 1;
            if (!std.math.isFinite(value)) return bad(cx, t, i - 1);
            if (eq(token.text, "alpha")) {
                if (value <= 0 or value >= 1) return bad(cx, t, i - 1);
                s.options.alpha = value;
            } else if (eq(token.text, "singular")) {
                if (value <= 0 or value >= 1) return bad(cx, t, i - 1);
                s.options.singular = value;
            } else {
                if (value != 1 and value != 2 and value != 3) return bad(cx, t, i - 1);
                if (value != 3 or at(t, i, .comma) or at(t, i, .number)) return proc.failGap(cx.diags, token.line, "PROC MIXED: only HTYPE=3 is implemented in the default model contract", .{});
            }
            continue;
        }
        for ([_][]const u8{ "alphap", "chisq", "contain", "corrb", "covb", "covbi", "ddf", "e", "e1", "e2", "e3", "fullx", "influence", "lcomponents", "outp", "outpred", "outpm", "outpredm", "residual", "residuals", "singchol", "singres", "vciry", "xpvix", "xpvixi", "zeta" }) |name| if (eq(token.text, name)) return proc.failGap(cx.diags, token.line, "PROC MIXED: MODEL option {s} is not implemented", .{token.text});
        return bad(cx, t, i - 1);
    }
}
pub fn parse(cx: proc.ProcCtx, ds: *const Dataset, statements: anytype, order: levels.Order, alpha: f64) diag.Error!Spec {
    var s: Spec = .{ .source = ds, .matrix = .{ .response = 0, .effects = &.{}, .order = order }, .required_columns = &.{}, .options = .{ .alpha = alpha } };
    var classes: std.ArrayList(usize) = .empty;
    var refs: std.ArrayList(?levels.Reference) = .empty;
    var fixed: std.ArrayList(matrix.Effect) = .empty;
    var seen = false;
    for (statements) |statement| switch (statement.kind) {
        .class => {
            if (seen) return cx.diags.fail(error.ParseError, statement.line, "PROC MIXED: CLASS must precede MODEL", .{});
            try classStatement(cx, ds, statement.tokens, &classes, &refs);
        },
        .model => {
            if (seen) return proc.failGap(cx.diags, statement.line, "PROC MIXED: multiple MODEL statements are not implemented", .{});
            seen = true;
            s.line = statement.line;
            var i: usize = 0;
            const t = statement.tokens;
            s.matrix.response = try variable(cx, ds, t, &i);
            if (ds.columns.items[s.matrix.response].type != .num) return cx.diags.fail(error.ParseError, statement.line, "PROC MIXED: response must be numeric", .{});
            if (!at(t, i, .eq)) return bad(cx, t, i);
            i += 1;
            var slash = i;
            while (slash < t.len and !at(t, slash, .slash)) slash += 1;
            try effects(cx, ds, t[i..slash], &fixed);
            if (slash < t.len) try modelOptions(cx, t[slash + 1 ..], &s);
        },
        .random => s.has_random = true,
        .repeated => s.has_repeated = true,
        .parms, .contrast, .estimate => {},
    };
    if (!seen) return cx.diags.fail(error.ParseError, 0, "PROC MIXED: MODEL statement is required", .{});
    s.matrix.classes = classes.items;
    s.matrix.references = refs.items;
    s.matrix.effects = fixed.items;
    var required: std.ArrayList(usize) = .empty;
    try unique(cx.arena, &required, s.matrix.response);
    for (classes.items) |ci| try unique(cx.arena, &required, ci);
    for (fixed.items) |e| {
        _ = matrix.normalize(cx.arena, ds, classes.items, e) catch |err| switch (err) {
            error.OutOfMemory => return err,
            else => return cx.diags.fail(error.ParseError, s.line, "PROC MIXED: invalid CLASS/continuous effect or nesting", .{}),
        };
        for (e.factors) |ci| try unique(cx.arena, &required, ci);
        for (e.nested) |ci| try unique(cx.arena, &required, ci);
    }
    s.required_columns = required.items;
    return s;
}

fn testTokens(a: std.mem.Allocator, d: *diag.Diagnostics, text: []const u8) ![]const lex.Token {
    const t = try lex.tokenize(a, text, d);
    return t[0 .. t.len - 1];
}
fn testData(a: std.mem.Allocator) !Dataset {
    var ds = Dataset.init(a, "d");
    _ = try ds.addColumn("A", .char);
    _ = try ds.addColumn("B", .num);
    _ = try ds.addColumn("x", .num);
    _ = try ds.addColumn("y", .num);
    try ds.appendRow(&.{ .{ .str = "a" }, .{ .num = 1 }, .{ .num = 2 }, .{ .num = 3 } });
    try ds.appendRow(&.{ .{ .str = "b" }, .{ .num = 2 }, .{ .num = 3 }, .{ .num = 4 } });
    return ds;
}
test "STAT-MIXED-003 CLASS global references and MODEL option state preserve exact roles" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try testData(a);
    var lib = @import("../exec.zig").Library.init(a);
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    const s = try parse(cx, &ds, &[_]Statement{
        .{ .kind = .class, .tokens = try testTokens(a, &d, "A(ref='b') B / ref=first"), .line = 1 },
        .{ .kind = .model, .tokens = try testTokens(a, &d, "y=A|B @2 x*x / noint solution cl alpha=.1 ddfm=res singular=1e-8"), .line = 2 },
        .{ .kind = .random, .tokens = try testTokens(a, &d, "B"), .line = 3 },
        .{ .kind = .repeated, .tokens = &.{}, .line = 4 },
    }, .data, 0.05);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, s.matrix.classes);
    try std.testing.expectEqualStrings("b", s.matrix.references[0].?.label);
    try std.testing.expect(s.matrix.references[1].? == .first);
    try std.testing.expect(!s.matrix.intercept and s.options.solution and s.options.cl);
    try std.testing.expectEqual(@as(f64, 0.1), s.options.alpha);
    try std.testing.expectEqual(@as(f64, 1e-8), s.options.singular);
    try std.testing.expect(s.options.ddfm == .residual and s.has_random and s.has_repeated);
    try std.testing.expectEqual(@as(usize, 4), s.matrix.effects.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1 }, s.matrix.effects[2].factors);
    try std.testing.expectEqualSlices(usize, &.{ 2, 2 }, s.matrix.effects[3].factors);
    try std.testing.expectEqualSlices(usize, &.{ 3, 0, 1, 2 }, s.required_columns);
}

test "STAT-MIXED-003 invalid and unsupported model declarations remain classified diagnostics" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var ds = try testData(a);
    var lib = @import("../exec.zig").Library.init(a);
    const Case = struct { class: []const u8, model: []const u8, code: u8 };
    for ([_]Case{
        .{ .class = "A", .model = "A=x", .code = 1 },
        .{ .class = "A", .model = "y=unknown", .code = 1 },
        .{ .class = "A", .model = "y=x(B)", .code = 1 },
        .{ .class = "A", .model = "y=A / fullx", .code = 2 },
        .{ .class = "A", .model = "y=A / ddfm=kr", .code = 2 },
        .{ .class = "A / truncate", .model = "y=A", .code = 2 },
        .{ .class = "A", .model = "y=A / typo", .code = 1 },
        .{ .class = "A", .model = "y=A / alpha=2", .code = 1 },
        .{ .class = "A", .model = "y=A / htype=4", .code = 1 },
        .{ .class = "A", .model = "y=A / htype=1", .code = 2 },
        .{ .class = "A / ref=first ref=last", .model = "y=A", .code = 2 },
    }) |c| {
        diag.resetGap();
        defer diag.resetGap();
        var d = diag.Diagnostics.init(a);
        const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
        try std.testing.expectError(error.ParseError, parse(cx, &ds, &[_]Statement{ .{ .kind = .class, .tokens = try testTokens(a, &d, c.class), .line = 1 }, .{ .kind = .model, .tokens = try testTokens(a, &d, c.model), .line = 2 } }, .formatted, 0.05));
        try std.testing.expectEqual(c.code, diag.exitCode(diag.gapHit(), d.hasErrors()));
    }
    var d = diag.Diagnostics.init(a);
    const cx: proc.ProcCtx = .{ .arena = a, .lib = &lib, .diags = &d };
    try std.testing.expectError(error.ParseError, parse(cx, &ds, &[_]Statement{ .{ .kind = .model, .tokens = try testTokens(a, &d, "y=x"), .line = 1 }, .{ .kind = .class, .tokens = try testTokens(a, &d, "A"), .line = 2 } }, .formatted, 0.05));
    try std.testing.expectError(error.ParseError, parse(cx, &ds, &[_]Statement{}, .formatted, 0.05));
}
