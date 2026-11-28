//! PROC PLM statement, S154 physical pp.7628–7632: RESTORE= against the
//! OpenSAS native item store (store.zig), documented basic options and the
//! default "Store Information" / "Class Level Information" listing.
//! STAT-PLM-002 adds SHOW FIT / SHOW PARMS and TEST effect-list (Type III)
//! from the restored model (plm_infer.zig). Every other analysis statement
//! belongs to later PLM tickets and is diagnosed as a D-009 gap BEFORE any
//! listing is produced, so a partial listing can never be mistaken for a
//! completed analysis.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const store = @import("store.zig");
const infer = @import("plm_infer.zig");
const format = @import("../format.zig");
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;

pub const DdfMethod = enum { residual, none, kenward_roger, satterthwaite };
pub const StatementOrder = enum { syntax, group };
pub const Plots = enum { all, none };
/// Null means "not specified": the documented default then comes from the
/// item store (or the documented constant) when a consumer statement needs it.
pub const Options = struct {
    restore: []const u8 = "",
    seed: ?f64 = null,
    statement_order: ?StatementOrder = null,
    format_reload: bool = true,
    whereformat: bool = false,
    alpha: ?f64 = null,
    ddfmethod: ?DdfMethod = null,
    percentiles: []const f64 = &.{},
    maxlen: usize = 100,
    noclprint: bool = false,
    noinfo: bool = false,
    noprint: bool = false,
    plots: ?Plots = null,
    unpack: bool = false,
    esteps: ?f64 = null,
    singchol: ?f64 = null,
    singres: ?f64 = null,
    singular: ?f64 = null,
    zeta: ?f64 = null,
    line: usize = 0,
    statements: []const Statement = &.{},
};
/// STAT-PLM-002 Getting Started path (S154 physical pp.7620–7623).
pub const Statement = union(enum) {
    show: struct { fit: bool, parms: bool },
    /// Effect names exactly as stored (resolved case-insensitively at run time).
    type3: struct { effects: []const []const u8, line: usize },
};

/// Statements documented for PROC PLM (S154 ch.94) that later tickets own.
const later_statements = [_][]const u8{ "code", "effectplot", "estimate", "filter", "lsmeans", "lsmestimate", "score", "slice", "where", "by" };

const P = struct {
    cx: proc.ProcCtx,
    t: []const lex.Token,
    i: usize = 0,
    seen: std.ArrayList([]const u8) = .empty,

    fn at(p: *const P, tag: lex.Tag) bool {
        return p.i < p.t.len and p.t[p.i].tag == tag;
    }
    fn line(p: *const P) usize {
        return if (p.i < p.t.len) p.t[p.i].line else if (p.t.len > 0) p.t[p.t.len - 1].line else 0;
    }
    fn bad(p: *const P, comptime what: []const u8) diag.Error {
        return p.cx.diags.fail(error.ParseError, p.line(), "PROC PLM: " ++ what ++ " (found {s})", .{if (p.i < p.t.len and p.t[p.i].tag != .semicolon and p.t[p.i].tag != .eof) p.t[p.i].text else "end of statement"});
    }
    /// SAS's treatment of a repeated PROC PLM option is not documented on
    /// pp.7628–7632; refuse instead of guessing first-wins or last-wins.
    fn once(p: *P, comptime name: []const u8) diag.Error!void {
        for (p.seen.items) |s| if (std.mem.eql(u8, s, name)) return proc.failGap(p.cx.diags, p.line(), "PROC PLM: repeated " ++ name ++ " option is not verified", .{});
        try p.seen.append(p.cx.arena, name);
    }
    fn equals(p: *P, comptime name: []const u8) diag.Error!void {
        if (!p.at(.eq)) return p.bad(name ++ " requires =value");
        p.i += 1;
    }
    fn number(p: *P, comptime name: []const u8) diag.Error!f64 {
        var sign: f64 = 1;
        if (p.at(.minus)) {
            sign = -1;
            p.i += 1;
        } else if (p.at(.plus)) p.i += 1;
        if (!p.at(.number)) return p.bad(name ++ " requires a number");
        const v = std.fmt.parseFloat(f64, p.t[p.i].text) catch return p.bad(name ++ " requires a number");
        if (!std.math.isFinite(v)) return p.bad(name ++ " requires a finite number");
        p.i += 1;
        return sign * v;
    }
    fn valued(p: *P, comptime name: []const u8) diag.Error!f64 {
        try p.once(name);
        p.i += 1;
        try p.equals(name);
        return p.number(name);
    }
    fn word(p: *P, comptime name: []const u8) diag.Error![]const u8 {
        try p.once(name);
        p.i += 1;
        try p.equals(name);
        if (!p.at(.name)) return p.bad(name ++ " requires a keyword");
        defer p.i += 1;
        return p.t[p.i].text;
    }
};

fn any(text: []const u8, comptime names: []const []const u8) bool {
    inline for (names) |n| if (eq(text, n)) return true;
    return false;
}

/// `t` is the whole step: PROC PLM options; statements...; RUN;
pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Options {
    var p: P = .{ .cx = cx, .t = t, .i = @min(2, t.len) };
    var o: Options = .{ .line = if (t.len > 0) t[0].line else 0 };
    while (p.i < t.len and t[p.i].tag != .semicolon and t[p.i].tag != .eof) {
        if (!p.at(.name)) return p.bad("expected an option");
        const k = t[p.i].text;
        if (eq(k, "restore")) {
            try p.once("RESTORE=");
            p.i += 1;
            try p.equals("RESTORE");
            if (!p.at(.name)) return p.bad("RESTORE= requires a one- or two-level item-store name");
            var name = t[p.i].text;
            p.i += 1;
            if (p.at(.dot)) {
                p.i += 1;
                if (!p.at(.name)) return p.bad("RESTORE= requires a member name");
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[p.i].text });
                p.i += 1;
            }
            o.restore = name;
        } else if (eq(k, "seed")) {
            const v = try p.valued("SEED");
            // pp.7631: a seed <= 0 is drawn from the clock and logged; that
            // stream has no consumer here and is not reproducible.
            if (v <= 0) return proc.failGap(cx.diags, o.line, "PROC PLM: SEED<=0 (clock-generated seed) is not implemented", .{});
            if (v != @floor(v)) return cx.diags.fail(error.ParseError, o.line, "PROC PLM: SEED= requires an integer", .{});
            o.seed = v;
        } else if (any(k, &.{ "stmtorder", "stmt" })) {
            const w = try p.word("STMTORDER");
            o.statement_order = if (eq(w, "syntax")) .syntax else if (eq(w, "group")) .group else return cx.diags.fail(error.ParseError, o.line, "PROC PLM: STMTORDER= must be SYNTAX or GROUP, not {s}", .{w});
        } else if (eq(k, "format")) {
            const w = try p.word("FORMAT");
            o.format_reload = if (eq(w, "reload")) true else if (eq(w, "noload")) false else return cx.diags.fail(error.ParseError, o.line, "PROC PLM: FORMAT= must be NOLOAD or RELOAD, not {s}", .{w});
        } else if (eq(k, "whereformat")) {
            try p.once("WHEREFORMAT");
            p.i += 1;
            o.whereformat = true;
        } else if (eq(k, "alpha")) {
            const v = try p.valued("ALPHA");
            if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, o.line, "PROC PLM: ALPHA= must be between 0 and 1", .{});
            o.alpha = v;
        } else if (eq(k, "ddfmethod")) {
            const w = try p.word("DDFMETHOD");
            o.ddfmethod = if (any(w, &.{ "residual", "res", "error" })) .residual else if (eq(w, "none")) .none else if (any(w, &.{ "kenrog", "kr", "kenwardroger" })) .kenward_roger else if (any(w, &.{ "satterth", "sat", "satterthwaite" })) .satterthwaite else return cx.diags.fail(error.ParseError, o.line, "PROC PLM: unknown DDFMETHOD={s}", .{w});
        } else if (any(k, &.{ "percentiles", "percentile" })) {
            try p.once("PERCENTILES");
            p.i += 1;
            try p.equals("PERCENTILES");
            var list: std.ArrayList(f64) = .empty;
            while (p.at(.number) or p.at(.minus) or p.at(.plus)) {
                const v = try p.number("PERCENTILES");
                if (!(v > 0 and v < 100)) return cx.diags.fail(error.ParseError, o.line, "PROC PLM: PERCENTILES= values must be strictly between 0 and 100", .{});
                try list.append(cx.arena, v);
                if (p.at(.comma)) p.i += 1;
            }
            if (list.items.len == 0) return p.bad("PERCENTILES= requires a value list");
            o.percentiles = list.items;
        } else if (eq(k, "maxlen")) {
            const v = try p.valued("MAXLEN");
            if (v != @floor(v)) return cx.diags.fail(error.ParseError, o.line, "PROC PLM: MAXLEN= requires an integer", .{});
            // pp.7629 gives 20 and 256 as the limits but not whether SAS
            // rejects or clamps values outside them.
            if (v < 20 or v > 256) return proc.failGap(cx.diags, o.line, "PROC PLM: MAXLEN= outside the documented 20..256 range is not verified", .{});
            o.maxlen = @intFromFloat(v);
        } else if (eq(k, "noclprint")) {
            try p.once("NOCLPRINT");
            p.i += 1;
            if (p.at(.eq)) return proc.failGap(cx.diags, o.line, "PROC PLM: NOCLPRINT=number is not implemented", .{});
            o.noclprint = true;
        } else if (eq(k, "noinfo")) {
            try p.once("NOINFO");
            p.i += 1;
            o.noinfo = true;
        } else if (eq(k, "noprint")) {
            try p.once("NOPRINT");
            p.i += 1;
            o.noprint = true;
        } else if (any(k, &.{ "plots", "plot" })) {
            try p.once("PLOTS");
            p.i += 1;
            if (p.at(.lparen)) {
                p.i += 1;
                if (!p.at(.name) or !any(t[p.i].text, &.{ "unpack", "unpackpanel" })) return p.bad("PLOTS global option must be UNPACK or UNPACKPANEL");
                p.i += 1;
                if (!p.at(.rparen)) return p.bad("PLOTS( requires )");
                p.i += 1;
                o.unpack = true;
            }
            if (p.at(.eq)) {
                p.i += 1;
                const paren = p.at(.lparen);
                if (paren) p.i += 1;
                if (!p.at(.name)) return p.bad("PLOTS= requires ALL or NONE");
                o.plots = if (eq(t[p.i].text, "all")) .all else if (eq(t[p.i].text, "none")) .none else return p.bad("PLOTS= requires ALL or NONE");
                p.i += 1;
                if (paren) {
                    if (!p.at(.rparen)) return p.bad("PLOTS=( requires a single request and )");
                    p.i += 1;
                }
            }
        } else if (eq(k, "esteps")) {
            o.esteps = try p.valued("ESTEPS");
        } else if (eq(k, "singchol")) {
            o.singchol = try p.valued("SINGCHOL");
        } else if (eq(k, "singres")) {
            o.singres = try p.valued("SINGRES");
        } else if (eq(k, "singular")) {
            o.singular = try p.valued("SINGULAR");
        } else if (eq(k, "zeta")) {
            o.zeta = try p.valued("ZETA");
        } else return cx.diags.fail(error.ParseError, t[p.i].line, "PROC PLM: unknown option {s}", .{k});
    }
    if (o.restore.len == 0) return cx.diags.fail(error.ParseError, o.line, "PROC PLM: the RESTORE= option is required", .{});
    // Statement boundary: nothing after the PROC statement is executed by
    // this ticket. Documented statements are gaps; anything else is a user error.
    var statements: std.ArrayList(Statement) = .empty;
    while (p.i < t.len) {
        if (t[p.i].tag == .semicolon) {
            p.i += 1;
            continue;
        }
        const s = t[p.i];
        if (s.tag == .eof) break;
        if (s.tag == .name and (eq(s.text, "run") or eq(s.text, "quit"))) break;
        if (s.tag == .name and eq(s.text, "show")) {
            // Only the two tables of the Getting Started example; the rest of
            // the SHOW catalogue belongs to STAT-PLM-003.
            p.i += 1;
            var fit = false;
            var parms = false;
            while (p.i < t.len and t[p.i].tag != .semicolon and t[p.i].tag != .eof) : (p.i += 1) {
                const w = t[p.i];
                if (w.tag == .name and eq(w.text, "fit") and !fit and !parms) {
                    fit = true;
                } else if (w.tag == .name and any(w.text, &.{ "parms", "parameters" }) and !parms) {
                    parms = true;
                } else return proc.failGap(cx.diags, w.line, "PROC PLM: SHOW {s} (or this SHOW option order/repetition) is not implemented", .{w.text});
            }
            if (!fit and !parms) return proc.failGap(cx.diags, s.line, "PROC PLM: SHOW without options is not implemented", .{});
            try statements.append(cx.arena, .{ .show = .{ .fit = fit, .parms = parms } });
            continue;
        }
        if (s.tag == .name and eq(s.text, "test")) {
            p.i += 1;
            var effects: std.ArrayList([]const u8) = .empty;
            while (p.i < t.len and t[p.i].tag != .semicolon and t[p.i].tag != .eof) {
                if (!p.at(.name)) return proc.failGap(cx.diags, s.line, "PROC PLM: TEST options and non-effect operands ({s}) are not implemented", .{t[p.i].text});
                var name: []const u8 = t[p.i].text;
                p.i += 1;
                while (p.at(.star)) {
                    p.i += 1;
                    if (!p.at(.name)) return p.bad("TEST expects a variable after *");
                    name = try std.fmt.allocPrint(cx.arena, "{s}*{s}", .{ name, t[p.i].text });
                    p.i += 1;
                }
                try effects.append(cx.arena, name);
            }
            // The default effect list (and whether it includes Intercept) is
            // not exercised by the reference: refuse instead of guessing.
            if (effects.items.len == 0) return proc.failGap(cx.diags, s.line, "PROC PLM: TEST without an effect list is not implemented", .{});
            try statements.append(cx.arena, .{ .type3 = .{ .effects = effects.items, .line = s.line } });
            continue;
        }
        if (s.tag == .name) for (later_statements) |name| {
            if (eq(s.text, name)) return proc.failGap(cx.diags, s.line, "PROC PLM: the {s} statement is not implemented", .{name});
        };
        return cx.diags.fail(error.ParseError, s.line, "PROC PLM: invalid statement {s}", .{s.text});
    }
    // pp.7631: GROUP reorders statements by type; only syntax order is implemented.
    if (statements.items.len > 0 and o.statement_order != null and o.statement_order.? == .group) return proc.failGap(cx.diags, o.line, "PROC PLM: STMTORDER=GROUP with analysis statements is not implemented", .{});
    // Whether NOPRINT still runs/prints explicit requests is not verified.
    if (statements.items.len > 0 and o.noprint) return proc.failGap(cx.diags, o.line, "PROC PLM: NOPRINT with analysis statements is not implemented", .{});
    o.statements = statements.items;
    return o;
}

fn pad(a: A, out: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (width > text.len) try out.appendNTimes(a, ' ', width - text.len);
}
fn title(a: A, out: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
/// DATETIME16-style ddMONyy:hh:mm:ss.
/// ponytail: rendered in UTC; SAS shows the session's local time. The value
/// is the store's own creation instant either way.
fn datetime(a: A, seconds: i64) ![]const u8 {
    const months = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
    const es: std.time.epoch.EpochSeconds = .{ .secs = @intCast(@max(0, seconds)) };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    return std.fmt.allocPrint(a, "{d:0>2}{s}{d:0>2}:{d:0>2}:{d:0>2}:{d:0>2}", .{ md.day_index + 1, months[md.month.numeric() - 1], yd.year % 100, ds.getHoursIntoDay(), ds.getMinutesIntoHour(), ds.getSecondsIntoMinute() });
}
fn joined(a: A, first: ?[]const u8, names: anytype) ![]const u8 {
    var s: std.ArrayList(u8) = .empty;
    if (first) |f| try s.appendSlice(a, f);
    for (names) |n| {
        if (s.items.len > 0) try s.append(a, ' ');
        try s.appendSlice(a, n.name);
    }
    return s.items;
}
const Row = struct { label: []const u8, value: []const u8 };

/// Layout follows the retained SAS listing shape for a GLM store: label
/// column plus four blanks, values padded one past the longest value, table
/// titles centred over the table width.
pub fn render(a: A, out: *std.ArrayList(u8), o: Options, m: store.Model) !void {
    var class_effects = false;
    for (m.effects) |e| for (e.factors) |f| {
        class_effects = class_effects or f.class_index != null;
    };
    const show_classes = !o.noclprint and class_effects;
    if (o.noprint or (o.noinfo and !show_classes)) return;
    try out.appendSlice(a, "The PLM Procedure\n\n");
    if (!o.noinfo) {
        var rows: std.ArrayList(Row) = .empty;
        const dot = std.mem.indexOfScalar(u8, o.restore, '.');
        const item = if (dot == null) try std.fmt.allocPrint(a, "WORK.{s}", .{o.restore}) else try a.dupe(u8, o.restore);
        try rows.append(a, .{ .label = "Item Store", .value = try std.ascii.allocUpperString(a, item) });
        if (m.label.len > 0) try rows.append(a, .{ .label = "Label", .value = m.label });
        const input = if (std.mem.indexOfScalar(u8, m.input, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{m.input}) else m.input;
        try rows.append(a, .{ .label = "Data Set Created From", .value = try std.ascii.allocUpperString(a, input) });
        try rows.append(a, .{ .label = "Created By", .value = try std.fmt.allocPrint(a, "PROC {s}", .{m.procedure}) });
        try rows.append(a, .{ .label = "Date Created", .value = try datetime(a, m.created_unix_seconds) });
        try rows.append(a, .{ .label = "Response Variable", .value = m.response });
        if (m.classes.len > 0) try rows.append(a, .{ .label = "Class Variables", .value = try joined(a, null, m.classes) });
        try rows.append(a, .{ .label = "Model Effects", .value = try joined(a, if (m.intercept) "Intercept" else null, m.effects) });
        var lw: usize = 0;
        var vw: usize = 0;
        for (rows.items) |r| {
            if (r.value.len > o.maxlen) return error.Truncation;
            lw = @max(lw, r.label.len);
            vw = @max(vw, r.value.len + 1);
        }
        try title(a, out, "Store Information", lw + 4 + vw);
        try out.append(a, '\n');
        for (rows.items) |r| {
            try pad(a, out, r.label, lw + 4);
            try pad(a, out, r.value, vw);
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
    if (show_classes) {
        if (!o.noinfo) try out.append(a, '\n');
        var cw: usize = "Class".len;
        var vw: usize = "Values".len;
        const values = try a.alloc([]const u8, m.classes.len);
        for (m.classes, values) |c, *v| {
            var s: std.ArrayList(u8) = .empty;
            for (c.levels) |l| {
                try s.appendSlice(a, std.mem.trim(u8, l.label, " "));
                try s.append(a, ' ');
            }
            v.* = s.items;
            cw = @max(cw, c.name.len);
            vw = @max(vw, s.items.len);
        }
        try title(a, out, "Class Level Information", cw + 4 + 6 + 4 + vw);
        try out.appendSlice(a, " \n");
        try pad(a, out, "Class", cw + 4);
        try out.appendSlice(a, "Levels    Values\n\n");
        for (m.classes, values) |c, v| {
            try pad(a, out, c.name, cw + 4);
            const n = try std.fmt.allocPrint(a, "{d}", .{c.levels.len});
            if (n.len < 6) try out.appendNTimes(a, ' ', 6 - n.len);
            try out.appendSlice(a, n);
            try out.appendSlice(a, "    ");
            try pad(a, out, v, vw);
            try out.append(a, '\n');
        }
        try out.append(a, '\n');
    }
}

pub fn run(cx: proc.ProcCtx, out: *std.ArrayList(u8), t: []const lex.Token) diag.Error!void {
    const o = try parse(cx, t);
    const m = try store.restore(cx, o.restore);
    // pp.7629: these methods need information that only MIXED/GLIMMIX stores
    // carry; the native GLM store has none.
    if (o.ddfmethod) |method| if (method == .kenward_roger or method == .satterthwaite)
        return proc.failGap(cx.diags, o.line, "PROC PLM: DDFMETHOD={s} needs degrees-of-freedom information the item store does not contain", .{@tagName(method)});
    var body: std.ArrayList(u8) = .empty;
    render(cx.arena, &body, o, m) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Truncation => return proc.failGap(cx.diags, o.line, "PROC PLM: Store Information strings longer than MAXLEN={d} (truncated display) are not implemented", .{o.maxlen}),
    };
    // NOINFO NOCLPRINT leaves no default table; the procedure title still heads the analysis tables.
    if (o.statements.len > 0 and body.items.len == 0) try body.appendSlice(cx.arena, "The PLM Procedure\n");
    for (o.statements) |statement| analysis(cx.arena, &body, m, statement) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Unsupported => return proc.failGap(cx.diags, o.line, "PROC PLM: stored-model inference is implemented only for full-rank CLASS-only GLM stores whose effects span the GLM parameterization", .{}),
        error.UnknownEffect => return cx.diags.fail(error.ExecError, o.line, "PROC PLM: a TEST effect is not in the stored model", .{}),
        error.FormatError => return cx.diags.fail(error.ExecError, o.line, "PROC PLM: cannot format a stored-model statistic", .{}),
    };
    try out.appendSlice(cx.arena, body.items);
}

fn right(a: A, out: *std.ArrayList(u8), text: []const u8, width: usize) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn probability(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else std.fmt.allocPrint(a, "{d:.4}", .{p});
}
/// Column layout follows the retained SAS listing of the Getting Started
/// store: 4-blank gutters, 8-wide numeric cells, titles centred on the table.
fn analysis(a: A, out: *std.ArrayList(u8), m: store.Model, statement: Statement) !void {
    switch (statement) {
        .show => |show| {
            if (show.fit) {
                try out.append(a, '\n');
                try title(a, out, "Fit Statistics", 20);
                try out.append(a, '\n');
                try pad(a, out, "MSE", 12);
                try right(a, out, format.bestNumW(a, m.mse, 8) catch return error.FormatError, 8);
                try out.append(a, '\n');
                try pad(a, out, "Error df", 12);
                try right(a, out, try std.fmt.allocPrint(a, "{d}", .{m.df_error}), 8);
                try out.appendSlice(a, "\n\n");
            }
            if (show.parms) {
                const parms = try infer.parameters(a, m);
                var ew: usize = "Effect".len;
                if (m.intercept) ew = @max(ew, "Intercept".len);
                for (m.effects) |e| ew = @max(ew, e.name.len);
                const cw = try a.alloc(usize, m.classes.len);
                var width: usize = ew + 4;
                for (cw, m.classes) |*w, c| {
                    w.* = c.name.len;
                    for (c.levels) |l| w.* = @max(w.*, std.mem.trim(u8, l.label, " ").len);
                    width += w.* + 4;
                }
                width += 8 + 12;
                try out.append(a, '\n');
                try title(a, out, "Parameter Estimates", width);
                try out.appendSlice(a, " \n");
                try right(a, out, "Standard", width);
                try out.append(a, '\n');
                try pad(a, out, "Effect", ew + 4);
                for (cw, m.classes) |w, c| try pad(a, out, c.name, w + 4);
                try out.appendSlice(a, "Estimate       Error\n\n");
                for (parms) |parm| {
                    try pad(a, out, if (parm.effect) |e| m.effects[e].name else "Intercept", ew + 4);
                    for (cw, m.classes, parm.levels) |w, c, level| try pad(a, out, if (level) |l| std.mem.trim(u8, c.levels[l].label, " ") else "", w + 4);
                    if (parm.stderr) |se| {
                        try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{parm.estimate}), 8);
                        try right(a, out, try std.fmt.allocPrint(a, "{d:.4}", .{se}), 12);
                    } else {
                        try right(a, out, "0", 8);
                        try right(a, out, ".", 12);
                    }
                    try out.append(a, '\n');
                }
                try out.append(a, '\n');
            }
        },
        .type3 => |request| {
            const indices = try a.alloc(usize, request.effects.len);
            var ew: usize = "Effect".len;
            for (indices, request.effects) |*index, name| {
                index.* = for (m.effects, 0..) |e, i| {
                    if (eq(e.name, name)) break i;
                } else return error.UnknownEffect;
                ew = @max(ew, name.len);
            }
            try out.append(a, '\n');
            try title(a, out, "Type III Tests of Model Effects", ew + 4 + 7 + 9 + 11 + 10);
            try out.appendSlice(a, " \n");
            try right(a, out, "Num", ew + 4 + 7);
            try right(a, out, "Den", 9);
            try out.append(a, '\n');
            try pad(a, out, "Effect", ew + 4);
            try out.appendSlice(a, "     DF       DF    F Value    Pr > F\n\n");
            for (indices) |index| {
                const r = try infer.type3(a, m, index);
                try pad(a, out, m.effects[index].name, ew + 4);
                try right(a, out, try std.fmt.allocPrint(a, "{d}", .{r.num_df}), 7);
                try right(a, out, try std.fmt.allocPrint(a, "{d}", .{r.den_df}), 9);
                try right(a, out, try std.fmt.allocPrint(a, "{d:.2}", .{r.f}), 11);
                try right(a, out, try probability(a, r.p), 10);
                try out.append(a, '\n');
            }
            try out.append(a, '\n');
        },
    }
}

test {
    _ = @import("plm_tests.zig");
}
