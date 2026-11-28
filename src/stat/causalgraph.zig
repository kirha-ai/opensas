//! PROC CAUSALGRAPH declarations, basic options and the default
//! identification listing, SAS/STAT 15.4 Chapter 37 (PROC CAUSALGRAPH
//! statement pp.2298-2302, IDENTIFY pp.2302-2303, MODEL pp.2304-2306,
//! UNMEASURED p.2309, Identification and Adjustment pp.2314-2315, Arrow or
//! Edge Specification p.2316, ODS Table Names p.2319).
//!
//! The procedure reads no data: its input is the causal graph of each MODEL
//! statement. The default path is METHOD=ADJUSTMENT with LIST: every valid
//! adjustment set (Shpitser/VanderWeele/Robins adjustment criterion in the
//! constructive form of van der Zander, Liskiewicz and Textor 2014) is
//! enumerated over the measured covariates and listed by increasing size.
//! Layout and messages follow SAS 9.4 reference runs. Everything not proven
//! against a reference listing (IMAP, COMMON, CYCLES=) is a
//! D-009 gap (rc 2) raised before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Method = enum { adjustment, backdoor, iv };

pub const Options = struct {
    method: Method = .adjustment,
    list: ?bool = null,
    /// null = MAXLIST=ALL; default 100 (p.2300).
    maxlist: ?usize = 100,
    /// null = no limit; 0 = MAXSIZE=MIN.
    maxsize: ?usize = null,
    minimal: bool = false,
    /// NOSORT (p.2301, Time Requirements p.2331): listing order of the
    /// search instead of size order; cleared (with a warning) under
    /// MAXSIZE=MIN or METHOD=IV.
    nosort: bool = false,
    compact: bool = false,
    noprint: bool = false,
    disconnected: bool = false,
    ordermodels: bool = false,
    nthreads: ?usize = null,
    /// PSUMMARY: only the identification summary (AdjustList pages or the
    /// no-set NOTE); VariableInfo and GraphicalModelSummary are suppressed
    /// (p.2297/p.2302; SAS 9.4 reference run).
    psummary: bool = false,
};

/// `bi` marks a bidirected edge (latent confounding, p.2306); its
/// `from`/`to` order is only the spelling order.
pub const Edge = struct { from: usize, to: usize, bi: bool = false };

pub const Model = struct {
    label: []const u8,
    line: usize,
    /// Node indexes into `Spec.names`, in first-appearance order.
    nodes: []const usize,
    edges: []const Edge,
};

pub const Spec = struct {
    opts: Options = .{},
    /// Every variable name seen, spelled as first written (names are not
    /// case-sensitive, p.2305).
    names: []const []const u8 = &.{},
    models: []const Model = &.{},
    treatments: []const usize = &.{},
    outcomes: []const usize = &.{},
    adjust: []const usize = &.{},
    identify: bool = false,
    identify_line: usize = 0,
    unmeasured: []const usize = &.{},
    tests: []const Test = &.{},
};

/// PATHS=(path-types) of a TESTID statement (p.2320): every requested type
/// must hold; ALL (or no type) shows every proper path.
pub const PathFilter = struct { causal: bool = false, noncausal: bool = false, blocked: bool = false, nonblocked: bool = false };

/// One TESTID statement (pp.2319-2320): an adjustment set (ADJUSTMENT /
/// BACKDOOR) or one instrument with its CONDITIONAL= set (IV).
pub const Test = struct {
    label: []const u8,
    line: usize,
    vars: []const usize,
    cond: []const usize = &.{},
    cond_given: bool = false,
    paths: ?PathFilter = null,
};

const RawTest = struct { label: ?[]const u8, line: usize, vars: []const []const u8, cond: []const []const u8, cond_given: bool, paths: ?PathFilter };

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const lex.Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn lineOf(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}
fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC CAUSALGRAPH: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else if (i < t.len) @tagName(t[i].tag) else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC CAUSALGRAPH: " ++ text, args);
}

/// Source spelling of an operator token; the lexer leaves most texts empty.
fn spell(tok: lex.Token) ?[]const u8 {
    return switch (tok.tag) {
        .eq => "=",
        .lt => "<",
        .gt => ">",
        .minus => "-",
        .max_op => "<>",
        .le => if (tok.text.len > 0) tok.text else "<=",
        .ge => if (tok.text.len > 0) tok.text else ">=",
        else => null,
    };
}

pub const Arrow = enum { right, left, both };

fn arrowKind(s: []const u8) ?Arrow {
    // Arrow or Edge Specification table, p.2316.
    for ([_][]const u8{ ">", "->", "-->", "=>", "==>", "===>" }) |r| if (std.mem.eql(u8, s, r)) return .right;
    for ([_][]const u8{ "<", "<-", "<--", "<=", "<==", "<===" }) |r| if (std.mem.eql(u8, s, r)) return .left;
    for ([_][]const u8{ "<>", "<->", "<-->", "<=>", "<==>", "<===>" }) |r| if (std.mem.eql(u8, s, r)) return .both;
    return null;
}

/// Read one arrow starting at `i.*` (a run of operator tokens). Returns null
/// and leaves `i` when no operator token is there.
// ponytail: tokens carry no column, so `- ->` with blanks also reads as an
// arrow; SAS spells arrows without inner blanks.
fn readArrow(a: A, t: []const lex.Token, i: *usize, end: usize) !?struct { kind: ?Arrow, text: []const u8 } {
    var buf: Out = .empty;
    var j = i.*;
    while (j < end) : (j += 1) {
        const s = spell(t[j]) orelse break;
        try buf.appendSlice(a, s);
    }
    if (j == i.*) return null;
    i.* = j;
    return .{ .kind = arrowKind(buf.items), .text = buf.items };
}

const Names = struct {
    list: std.ArrayList([]const u8) = .empty,
    fn intern(self: *Names, a: A, n: []const u8) !usize {
        for (self.list.items, 0..) |x, k| if (eq(x, n)) return k;
        try self.list.append(a, n);
        return self.list.items.len - 1;
    }
    fn find(self: *const Names, n: []const u8) ?usize {
        for (self.list.items, 0..) |x, k| if (eq(x, n)) return k;
        return null;
    }
};

fn splitNum(n: []const u8) ?struct { stem: []const u8, num: u64, digits: usize } {
    var k = n.len;
    while (k > 0 and std.ascii.isDigit(n[k - 1])) k -= 1;
    if (k == n.len or k == 0) return null;
    return .{ .stem = n[0..k], .num = std.fmt.parseInt(u64, n[k..], 10) catch return null, .digits = n.len - k };
}

/// One variable group: names (with X1-X3 numbered ranges), optionally
/// enclosed in braces or parentheses. Square brackets are not tokens of the
/// shared lexer (reported, not added here).
fn readGroup(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, end: usize, out: *std.ArrayList([]const u8)) diag.Error!void {
    const a = cx.arena;
    var close: ?lex.Tag = null;
    if (at(t, i.*, .lbrace)) close = .rbrace else if (at(t, i.*, .lparen)) close = .rparen;
    if (close != null) i.* += 1;
    const start = out.items.len;
    while (i.* < end) {
        if (close) |c| if (at(t, i.*, c)) {
            i.* += 1;
            break;
        };
        if (!at(t, i.*, .name)) {
            if (close != null) return invalid(cx, t, i.*);
            break;
        }
        const n = t[i.*].text;
        // `X1-X3`: a lone minus between two names is a numbered range.
        if (i.* + 2 < end and at(t, i.* + 1, .minus) and at(t, i.* + 2, .name)) {
            const lo = splitNum(n);
            const hi = splitNum(t[i.* + 2].text);
            if (lo == null or hi == null or !eq(lo.?.stem, hi.?.stem) or hi.?.num < lo.?.num)
                return user(cx, t[i.*].line, "Invalid variable range {s}-{s}.", .{ n, t[i.* + 2].text });
            var v = lo.?.num;
            while (v <= hi.?.num) : (v += 1) try out.append(a, try std.fmt.allocPrint(a, "{s}{d}", .{ lo.?.stem, v }));
            i.* += 3;
            continue;
        }
        try out.append(a, n);
        i.* += 1;
    }
    if (close != null and i.* > end) return invalid(cx, t, end);
    if (out.items.len == start) return invalid(cx, t, i.*);
}

/// Edges of one MODEL statement with the SAS 9.4 diagnostics of p.2305
/// (reference runs): a repeated edge of the same type is ignored with a
/// warning, `X <==> X` is an ignored variance specification, `X ==> X` is an
/// error. Variance warnings precede duplicate warnings in the SAS log.
const ModelBuilder = struct {
    cx: proc.ProcCtx,
    label: []const u8,
    line: usize,
    names: *Names,
    nodes: std.ArrayList(usize) = .empty,
    edges: std.ArrayList(Edge) = .empty,
    variance: std.ArrayList(usize) = .empty,
    dups: std.ArrayList(Edge) = .empty,
    track_empty: bool = false,

    fn group(b: *ModelBuilder, grp: []const []const u8) ![]usize {
        const ids = try b.cx.arena.alloc(usize, grp.len);
        for (grp, ids) |n, *id| {
            id.* = try b.names.intern(b.cx.arena, n);
            if (std.mem.indexOfScalar(usize, b.nodes.items, id.*) == null) try b.nodes.append(b.cx.arena, id.*);
        }
        return ids;
    }
    fn directed(b: *ModelBuilder, p: usize, q: usize) !void {
        const nm = b.names.list.items;
        if (p == q) return user(b.cx, b.line, "You cannot specify {s} ===> {s} in the model {s}.", .{ nm[p], nm[q], b.label });
        for (b.edges.items) |x| if (!x.bi and x.from == p and x.to == q) return b.dups.append(b.cx.arena, .{ .from = p, .to = q });
        try b.edges.append(b.cx.arena, .{ .from = p, .to = q });
    }
    fn bidirected(b: *ModelBuilder, p: usize, q: usize) !void {
        if (p == q) return b.variance.append(b.cx.arena, p);
        for (b.edges.items) |x| if (x.bi and ((x.from == p and x.to == q) or (x.from == q and x.to == p)))
            return b.dups.append(b.cx.arena, .{ .from = p, .to = q, .bi = true });
        try b.edges.append(b.cx.arena, .{ .from = p, .to = q, .bi = true });
    }
    fn flush(b: *ModelBuilder) !void {
        const nm = b.names.list.items;
        for (b.variance.items) |v| try b.cx.diags.warn(b.line, "The variance specification {s} <==> {s} is ignored in the model {s}.", .{ nm[v], nm[v], b.label });
        for (b.dups.items) |e| try b.cx.diags.warn(b.line, "The edge {s} {s} {s} appears more than once in the model {s}.", .{ nm[e.from], if (e.bi) "<===>" else "===>", nm[e.to], b.label });
        // ponytail: order of this warning relative to the others is not
        // reference-checked.
        if (b.track_empty) try b.cx.diags.warn(b.line, "At least one track in the model {s} contains no edges and has been discarded.", .{b.label});
    }
};

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{};
    var o: Options = .{};
    var i: usize = 2;
    var list_given = false;
    var nolist_given = false;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const w = t[i].text;
        const line = t[i].line;
        if (eq(w, "data") and at(t, i + 1, .eq)) {
            // The procedure reads no data (Table 37.1 lists no DATA=); SAS
            // 9.4 accepts and ignores the option (reference run).
            i += 3;
            if (at(t, i, .dot)) i += 2;
            if (at(t, i, .lparen)) {
                var depth: usize = 0;
                while (i < t.len and !at(t, i, .eof)) : (i += 1) {
                    if (at(t, i, .lparen)) depth += 1;
                    if (at(t, i, .rparen)) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                }
                i += 1;
            }
            continue;
        }
        i += 1;
        if (eq(w, "list")) {
            list_given = true;
        } else if (eq(w, "nolist")) {
            nolist_given = true;
        } else if (eq(w, "minimal") or eq(w, "min")) {
            o.minimal = true;
        } else if (eq(w, "compact")) {
            o.compact = true;
        } else if (eq(w, "noprint")) {
            o.noprint = true;
        } else if (eq(w, "disconnected") or eq(w, "disconnect")) {
            o.disconnected = true;
        } else if (eq(w, "ordermodels")) {
            o.ordermodels = true;
        } else if (eq(w, "psummary")) {
            o.psummary = true;
        } else if (eq(w, "maxlist") or eq(w, "maxsize") or eq(w, "nthreads") or eq(w, "method")) {
            if (!at(t, i, .eq)) return invalid(cx, t, i);
            i += 1;
            if (eq(w, "method")) {
                if (kw(t, i, "adjustment")) o.method = .adjustment else if (kw(t, i, "backdoor")) o.method = .backdoor else if (kw(t, i, "iv")) o.method = .iv else return invalid(cx, t, i);
                i += 1;
                continue;
            }
            if (eq(w, "maxlist") and kw(t, i, "all")) {
                o.maxlist = null;
                i += 1;
                continue;
            }
            if (eq(w, "maxsize") and kw(t, i, "min")) {
                o.maxsize = 0;
                i += 1;
                continue;
            }
            if (!at(t, i, .number)) return invalid(cx, t, i);
            const n = std.fmt.parseInt(usize, t[i].text, 10) catch return user(cx, line, "The {s}= value must be a positive integer.", .{try std.ascii.allocUpperString(a, w)});
            if (n == 0) return user(cx, line, "The {s}= value must be a positive integer.", .{try std.ascii.allocUpperString(a, w)});
            i += 1;
            if (eq(w, "maxlist")) o.maxlist = n else if (eq(w, "maxsize")) o.maxsize = n else o.nthreads = n;
        } else if (eq(w, "nosort")) {
            o.nosort = true;
        } else if (eq(w, "common") or eq(w, "imap") or eq(w, "cycles")) {
            return gap(cx, line, "the {s} option is not implemented", .{try std.ascii.allocUpperString(a, w)});
        } else return invalid(cx, t, i - 1);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    // "You cannot specify both the LIST and NOLIST options" (p.2300; message
    // text of a SAS 9.4 reference run).
    if (list_given and nolist_given) return user(cx, lineOf(t, 0), "You cannot specify both the LIST and NOLIST options.", .{});
    if (list_given) o.list = true;
    if (nolist_given) o.list = false;
    s.opts = o;

    var names: Names = .{};
    var models: std.ArrayList(Model) = .empty;
    var unmeasured_seen = false;
    var treat_names: std.ArrayList([]const u8) = .empty;
    var out_names: std.ArrayList([]const u8) = .empty;
    var adj_names: std.ArrayList([]const u8) = .empty;
    var unm_names: std.ArrayList([]const u8) = .empty;
    var raw_tests: std.ArrayList(RawTest) = .empty;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        const line = t[i].line;
        if (kw(t, i, "model")) {
            if (!at(t, i + 1, .string)) return user(cx, line, "The MODEL statement must begin with a quoted model label.", .{});
            const label = t[i + 1].text;
            for (models.items) |m| if (eq(m.label, label))
                return user(cx, line, "There is more than one model with the label {s}.", .{m.label});
            var b: ModelBuilder = .{ .cx = cx, .label = label, .line = line, .names = &names };
            var j = i + 2;
            if (j == end) return invalid(cx, t, j);
            while (j < end) {
                // One path, up to a comma.
                if (spell(t[j]) != null) {
                    // Covariance path `<==> variables` (p.2305): one
                    // bidirected edge per pair; nothing may follow the group
                    // but a comma (SAS 9.4: ERROR 22-322).
                    const ar = (try readArrow(a, t, &j, end)).?;
                    if (ar.kind != .both) return invalid(cx, t, j - 1);
                    var grp: std.ArrayList([]const u8) = .empty;
                    try readGroup(cx, t, &j, end, &grp);
                    if (j < end and !at(t, j, .comma)) return invalid(cx, t, j);
                    if (grp.items.len < 2) {
                        // ponytail: the discarded track's variables are not
                        // added as nodes (only the in-model case is
                        // reference-checked).
                        b.track_empty = true;
                    } else {
                        const ids = try b.group(grp.items);
                        // Pair order of the SAS duplicate warning: later
                        // name first (reference run).
                        for (ids, 0..) |p, k| for (ids[k + 1 ..]) |q| try b.bidirected(q, p);
                    }
                } else {
                    var prev: ?[]const usize = null;
                    var pending: ?Arrow = null;
                    while (true) {
                        var grp: std.ArrayList([]const u8) = .empty;
                        try readGroup(cx, t, &j, end, &grp);
                        const ids = try b.group(grp.items);
                        if (pending) |k| for (prev.?) |p| for (ids) |q| switch (k) {
                            .right => try b.directed(p, q),
                            .left => try b.directed(q, p),
                            .both => try b.bidirected(p, q),
                        };
                        prev = ids;
                        if (j >= end or at(t, j, .comma)) break;
                        const ar = (try readArrow(a, t, &j, end)) orelse return invalid(cx, t, j);
                        pending = ar.kind orelse return user(cx, line, "Invalid arrow {s} in the MODEL statement.", .{ar.text});
                    }
                    if (pending == null) return user(cx, line, "Each path in the MODEL statement must contain an arrow.", .{});
                }
                if (at(t, j, .comma)) {
                    j += 1;
                    if (j == end) return invalid(cx, t, j);
                }
            }
            try b.flush();
            try models.append(a, .{ .label = label, .line = line, .nodes = b.nodes.items, .edges = b.edges.items });
        } else if (kw(t, i, "identify")) {
            if (s.identify) return user(cx, line, "You cannot specify more than one IDENTIFY statement.", .{});
            s.identify = true;
            s.identify_line = line;
            var j = i + 1;
            try readGroup(cx, t, &j, end, &treat_names);
            while (j < end and (at(t, j, .name) or at(t, j, .lbrace) or at(t, j, .lparen))) try readGroup(cx, t, &j, end, &treat_names);
            const ar = (try readArrow(a, t, &j, end)) orelse return invalid(cx, t, j);
            if (ar.kind != .right) return user(cx, line, "The IDENTIFY statement requires a right arrow between the treatment and outcome variables.", .{});
            try readGroup(cx, t, &j, end, &out_names);
            while (j < end and (at(t, j, .name) or at(t, j, .lbrace) or at(t, j, .lparen))) try readGroup(cx, t, &j, end, &out_names);
            if (at(t, j, .pipe)) {
                j += 1;
                try readGroup(cx, t, &j, end, &adj_names);
                while (j < end and (at(t, j, .name) or at(t, j, .lbrace) or at(t, j, .lparen))) try readGroup(cx, t, &j, end, &adj_names);
            }
            if (j != end) return invalid(cx, t, j);
        } else if (kw(t, i, "unmeasured")) {
            if (unmeasured_seen) return user(cx, line, "You cannot specify more than one UNMEASURED statement.", .{});
            unmeasured_seen = true;
            var j = i + 1;
            while (j < end) try readGroup(cx, t, &j, end, &unm_names);
            if (unm_names.items.len == 0) return invalid(cx, t, end);
        } else if (kw(t, i, "testid")) {
            var j = i + 1;
            var label: ?[]const u8 = null;
            if (at(t, j, .string)) {
                label = t[j].text;
                j += 1;
            }
            var vn: std.ArrayList([]const u8) = .empty;
            while (j < end and !at(t, j, .slash)) try readGroup(cx, t, &j, end, &vn);
            var cn: std.ArrayList([]const u8) = .empty;
            var cond_given = false;
            var paths: ?PathFilter = null;
            if (at(t, j, .slash)) {
                j += 1;
                while (j < end) {
                    if (kw(t, j, "conditional") and at(t, j + 1, .eq)) {
                        j += 2;
                        cond_given = true;
                        if ((at(t, j, .lbrace) and at(t, j + 1, .rbrace)) or (at(t, j, .lparen) and at(t, j + 1, .rparen))) {
                            j += 2;
                        } else if (at(t, j, .name)) {
                            // CONDITIONAL=variable: one name only (p.2320).
                            try cn.append(a, t[j].text);
                            j += 1;
                        } else try readGroup(cx, t, &j, end, &cn);
                    } else if (kw(t, j, "paths") or kw(t, j, "path")) {
                        j += 1;
                        var f: PathFilter = .{};
                        if (at(t, j, .eq)) {
                            j += 1;
                            const paren = at(t, j, .lparen);
                            if (paren) j += 1;
                            var count: usize = 0;
                            while (j < end) {
                                if (paren and at(t, j, .rparen)) {
                                    j += 1;
                                    break;
                                }
                                if (kw(t, j, "all")) {} else if (kw(t, j, "causal")) {
                                    f.causal = true;
                                } else if (kw(t, j, "noncausal")) {
                                    f.noncausal = true;
                                } else if (kw(t, j, "blocked")) {
                                    f.blocked = true;
                                } else if (kw(t, j, "nonblocked")) {
                                    f.nonblocked = true;
                                } else return invalid(cx, t, j);
                                j += 1;
                                count += 1;
                                if (!paren) break;
                            }
                            if (count == 0) return invalid(cx, t, j);
                        }
                        paths = f;
                    } else return invalid(cx, t, j);
                }
            }
            if (j != end) return invalid(cx, t, j);
            try raw_tests.append(a, .{ .label = label, .line = line, .vars = vn.items, .cond = cn.items, .cond_given = cond_given, .paths = paths });
        } else if (kw(t, i, "run") or kw(t, i, "quit")) {
            // Step boundary tokens may reach the body.
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (models.items.len == 0) return user(cx, lineOf(t, 0), "You must specify at least one MODEL statement.", .{});

    // Resolve role names against the model variables. A role variable that
    // is in no model is ignored with a warning (p.2303; SAS 9.4 message).
    const roles = [_]struct { src: *std.ArrayList([]const u8), stmt: []const u8 }{
        .{ .src = &treat_names, .stmt = "IDENTIFY" }, .{ .src = &out_names, .stmt = "IDENTIFY" }, .{ .src = &adj_names, .stmt = "IDENTIFY" }, .{ .src = &unm_names, .stmt = "UNMEASURED" },
    };
    var resolved: [4]std.ArrayList(usize) = .{ .empty, .empty, .empty, .empty };
    for (roles, &resolved) |r, *dst| for (r.src.items) |n| {
        const id = names.find(n) orelse {
            try cx.diags.warn(s.identify_line, "Variable {s} specified in the {s} statement is not found in any model.", .{ n, r.stmt });
            continue;
        };
        if (std.mem.indexOfScalar(usize, dst.items, id) == null) try dst.append(a, id);
    };
    s.names = names.list.items;
    s.models = models.items;
    s.treatments = resolved[0].items;
    s.outcomes = resolved[1].items;
    s.adjust = resolved[2].items;
    s.unmeasured = resolved[3].items;

    // TESTID labels (p.2320): explicit labels must be unique (case-sensitive:
    // 'a' and 'A' coexist, SAS 9.4 reference run); an unlabeled test gets the
    // smallest unused `Testi`, explicit labels counted wherever they appear
    // (reference run: unlabeled, 'Test1', unlabeled -> Test2, Test1, Test3).
    var labels: std.ArrayList([]const u8) = .empty;
    for (raw_tests.items, 0..) |rt, k| if (rt.label) |l| {
        for (raw_tests.items[0..k]) |prev| if (prev.label) |ol| if (std.mem.eql(u8, ol, l))
            return user(cx, rt.line, "The labels for the TESTID statements must be unique.", .{});
        try labels.append(a, l);
    };
    var tests: std.ArrayList(Test) = .empty;
    for (raw_tests.items) |rt| {
        const label = rt.label orelse blk: {
            var k: usize = 1;
            while (true) : (k += 1) {
                const cand = try std.fmt.allocPrint(a, "Test{d}", .{k});
                var used = false;
                for (labels.items) |l| if (std.mem.eql(u8, l, cand)) {
                    used = true;
                };
                if (!used) {
                    try labels.append(a, cand);
                    break :blk cand;
                }
            }
        };
        var ids: [2]std.ArrayList(usize) = .{ .empty, .empty };
        for ([_][]const []const u8{ rt.vars, rt.cond }, &ids) |src, *dst| for (src) |nm| {
            const id = names.find(nm) orelse {
                try cx.diags.warn(rt.line, "Variable {s} specified in the TESTID statement is not found in any model.", .{nm});
                continue;
            };
            if (!contains(dst.items, id)) try dst.append(a, id);
        };
        try tests.append(a, .{ .label = label, .line = rt.line, .vars = ids[0].items, .cond = ids[1].items, .cond_given = rt.cond_given, .paths = rt.paths });
    }
    s.tests = tests.items;
    return s;
}

fn contains(xs: []const usize, x: usize) bool {
    return std.mem.indexOfScalar(usize, xs, x) != null;
}

/// Validation and D-009 scope boundary; runs before any output.
pub fn validate(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    const line = s.identify_line;
    for (s.treatments) |x| {
        if (contains(s.outcomes, x)) return user(cx, line, "The variable {s} cannot be both a treatment and an outcome variable.", .{s.names[x]});
        if (contains(s.unmeasured, x)) return user(cx, line, "The treatment variable {s} must be observed.", .{s.names[x]});
    }
    for (s.outcomes) |y| if (contains(s.unmeasured, y)) return user(cx, line, "The outcome variable {s} must be observed.", .{s.names[y]});
    for (s.adjust) |z| {
        if (contains(s.treatments, z) or contains(s.outcomes, z)) return user(cx, line, "The adjustment variable {s} cannot also be a treatment or an outcome variable.", .{s.names[z]});
        if (contains(s.unmeasured, z)) return user(cx, line, "The adjustment variable {s} must be observed.", .{s.names[z]});
    }
    if ((s.opts.list orelse false) and !s.identify) return user(cx, 0, "The LIST option requires an IDENTIFY statement.", .{});
    var cyclic = false;
    for (s.models) |m| {
        if (s.identify) {
            var tr = false;
            var oc = false;
            for (m.nodes) |n| {
                if (contains(s.treatments, n)) tr = true;
                if (contains(s.outcomes, n)) oc = true;
            }
            if (!tr) return user(cx, m.line, "The model {s} must contain at least one treatment variable.", .{m.label});
            if (!oc) {
                // SAS 9.4 reference run (STAT-CAUSALGRAPH-009): an outcome
                // of another model is first warned about for this one.
                for (s.outcomes) |y| {
                    var elsewhere = false;
                    for (s.models) |o| if (contains(o.nodes, y)) {
                        elsewhere = true;
                    };
                    if (elsewhere) try cx.diags.warn(s.identify_line, "The outcome variable {s} is not found in the model {s}.", .{ s.names[y], m.label });
                }
                return user(cx, m.line, "The model {s} must contain at least one outcome variable.", .{m.label});
            }
        }
        // A directed cycle (p.2329: the models must be DAGs) is reported by
        // `run` after the VariableInfo, summary and DirectedCycles tables
        // (STAT-CAUSALGRAPH-009); it pre-empts the TESTID and METHOD=IV
        // checks below.
        if (try hasCycle(cx.arena, s.names.len, m.edges)) cyclic = true;
    }
    if (cyclic) return;
    // Disconnected models: VariableInfo, summary, every ConnectedComponents
    // table, then (DISCONNECTED) every AdjustList (SAS 9.4 reference runs).
    // TESTID (pp.2319-2320); message texts from SAS 9.4 reference runs.
    if (s.tests.len > 0 and !s.identify) return user(cx, s.tests[0].line, "You cannot specify a TESTID statement without an IDENTIFY statement.", .{});
    const iv = s.opts.method == .iv;
    for (s.tests) |t| {
        if (iv) {
            if (t.vars.len != 1) return user(cx, t.line, "You must specify a single variable on the TESTID statement when METHOD=IV.", .{});
            const z = t.vars[0];
            if (contains(s.unmeasured, z)) return user(cx, t.line, "The instrumental variable {s} must be observed.", .{s.names[z]});
            // Message texts of SAS 9.4 reference runs.
            if (contains(s.treatments, z)) return user(cx, t.line, "The variable {s} is both a treatment and an instrument.", .{s.names[z]});
            if (contains(s.outcomes, z)) return user(cx, t.line, "The variable {s} is both an outcome and an instrument.", .{s.names[z]});
            for (t.cond) |c| {
                if (contains(s.treatments, c)) return user(cx, t.line, "The treatment variable {s} cannot be conditioned upon.", .{s.names[c]});
                if (contains(s.outcomes, c)) return user(cx, t.line, "The outcome variable {s} cannot be conditioned upon.", .{s.names[c]});
                if (contains(s.unmeasured, c)) return user(cx, t.line, "The conditioning variable {s} must be observed.", .{s.names[c]});
            }
            if (t.paths != null) try cx.diags.warn(t.line, "The PATHS option is ignored when METHOD=IV.", .{});
        } else {
            if (t.cond_given) try cx.diags.warn(t.line, "The CONDITIONAL= option is ignored when METHOD=ADJUSTMENT or METHOD=BACKDOOR.", .{});
            for (t.vars) |v| {
                if (contains(s.treatments, v)) return user(cx, t.line, "The variable {s} is both a treatment and a control.", .{s.names[v]});
                // ponytail: outcome wording mirrors the treatment message
                // (no reference run for an outcome named in TESTID).
                if (contains(s.outcomes, v)) return user(cx, t.line, "The variable {s} is both an outcome and a control.", .{s.names[v]});
                if (contains(s.unmeasured, v)) return user(cx, t.line, "The control variable {s} must be observed.", .{s.names[v]});
            }
        }
    }
    if (iv) {
        // p.2303: METHOD=IV takes one treatment and one outcome (reference
        // run texts).
        if (s.treatments.len > 1) return user(cx, line, "The IDENTIFY statement must contain a single treatment variable when METHOD=IV.", .{});
        if (s.outcomes.len > 1) return user(cx, line, "The IDENTIFY statement must contain a single outcome variable when METHOD=IV.", .{});
        if (s.identify and s.adjust.len > 0) try cx.diags.warn(line, "The adjustment variables in the IDENTIFY statement are ignored when METHOD=IV.", .{});
        if (s.identify) for (s.models) |m| {
            var direct = false;
            for (m.edges) |e| if (!e.bi and e.from == s.treatments[0] and e.to == s.outcomes[0]) {
                direct = true;
            };
            if (!direct) return user(cx, m.line, "The instrumental variables analysis requires a direct edge {s} -> {s} in the model {s}.", .{ s.names[s.treatments[0]], s.names[s.outcomes[0]], m.label });
        };
    }
    if (s.tests.len > 0) for (s.models) |m| {
        for (s.treatments) |x| if (!contains(m.nodes, x)) return gap(cx, m.line, "TESTID with a treatment variable missing from a model is not implemented", .{});
        for (s.outcomes) |y| if (!contains(m.nodes, y)) return gap(cx, m.line, "TESTID with an outcome variable missing from a model is not implemented", .{});
        for (s.tests) |t| {
            if (iv and t.vars.len == 1 and !contains(m.nodes, t.vars[0])) return user(cx, t.line, "The instrumental variable {s} in the TESTID statement is not found in the model {s}.", .{ s.names[t.vars[0]], m.label });
        }
    };
    // Joint effects (several treatments and/or outcomes, pp.2303/2317) use
    // the same set-valued adjustment criterion (STAT-CAUSALGRAPH-004).
}

fn hasCycle(a: A, n: usize, edges: []const Edge) !bool {
    const indeg = try a.alloc(usize, n);
    @memset(indeg, 0);
    for (edges) |e| if (!e.bi) {
        indeg[e.to] += 1;
    };
    var stack: std.ArrayList(usize) = .empty;
    for (indeg, 0..) |d, k| if (d == 0) try stack.append(a, k);
    var seen: usize = 0;
    while (stack.pop()) |v| {
        seen += 1;
        for (edges) |e| if (!e.bi and e.from == v) {
            indeg[e.to] -= 1;
            if (indeg[e.to] == 0) try stack.append(a, e.to);
        };
    }
    return seen < n;
}

/// The cycle SAS prints first for a model (DirectedCycles table; SAS 9.4
/// reference runs of 23 invented graphs, STAT-CAUSALGRAPH-009): it starts at
/// the case-insensitively alphabetically first node (mixed-case runs: `a`
/// before `B`, `b` before `C`) that lies on a directed cycle and follows
/// the alphabetically first successor that still leads back to that node.
/// Returns the closed walk (start repeated at the end), or null for a DAG.
pub fn firstCycle(a: A, names: []const []const u8, m: Model) !?[]const usize {
    const sorted = try a.dupe(usize, m.nodes);
    sortedIds(names, sorted);
    const seen = try a.alloc(bool, names.len);
    for (sorted) |start| {
        @memset(seen, false);
        var path: std.ArrayList(usize) = .empty;
        if (try cycleFrom(a, names, m, sorted, start, start, seen, &path)) {
            try path.append(a, start);
            return path.items;
        }
    }
    return null;
}

fn cycleFrom(a: A, names: []const []const u8, m: Model, sorted: []const usize, start: usize, v: usize, seen: []bool, path: *std.ArrayList(usize)) !bool {
    seen[v] = true;
    try path.append(a, v);
    // Successors in alphabetical order; a node already explored cannot
    // reach `start` (its branch would have succeeded), so pruning is safe.
    for (sorted) |w| {
        var edge = false;
        for (m.edges) |e| if (!e.bi and e.from == v and e.to == w) {
            edge = true;
        };
        if (!edge) continue;
        if (w == start) return true;
        if (seen[w]) continue;
        if (try cycleFrom(a, names, m, sorted, start, w, seen, path)) return true;
    }
    _ = path.pop();
    return false;
}

fn cyclesTable(a: A, out: *Out, names: []const []const u8, m: Model, cyc: []const usize) !void {
    const rows = cyc.len;
    const cn = try a.alloc([]const u8, rows);
    const st = try a.alloc([]const u8, rows);
    const nd = try a.alloc([]const u8, rows);
    var w: usize = 4;
    for (cyc, 0..) |v, r| {
        cn[r] = if (r == 0) "1" else "";
        st[r] = try num(a, r);
        nd[r] = names[v];
        w = @max(w, names[v].len);
    }
    const cols = [_]Col{
        .{ .head = &.{"Cycle"}, .al = .right, .width = 8, .cells = cn },
        .{ .head = &.{"Step"}, .al = .right, .width = 8, .cells = st },
        .{ .head = &.{"Node"}, .al = .left, .width = w, .cells = nd },
    };
    const title = try std.fmt.allocPrint(a, "Directed Cycles for {s}", .{m.label});
    try table(a, out, &.{title}, 1, &cols, try uniformGaps(a, cols.len), null);
}

fn components(a: A, n: usize, m: Model) !usize {
    const comp = try a.alloc(usize, n);
    @memset(comp, std.math.maxInt(usize));
    var count: usize = 0;
    for (m.nodes) |start| {
        if (comp[start] != std.math.maxInt(usize)) continue;
        var stack: std.ArrayList(usize) = .empty;
        try stack.append(a, start);
        comp[start] = count;
        while (stack.pop()) |v| for (m.edges) |e| {
            const w = if (e.from == v) e.to else if (e.to == v) e.from else continue;
            if (comp[w] == std.math.maxInt(usize)) {
                comp[w] = count;
                try stack.append(a, w);
            }
        };
        count += 1;
    }
    return count;
}

/// Directed graph of a model in which each bidirected edge u <==> v becomes
/// a fresh unmeasured parent L -> u, L -> v (p.2306: "equivalent to X1 <== L
/// ==> X2; unmeasured L"). Latent nodes take indexes n.. and are never
/// adjustment candidates; they have no parents, so the forbidden set and
/// the d-separation of the observed nodes are those of the mixed graph.
pub fn expandLatent(a: A, n: usize, edges: []const Edge) !struct { n: usize, edges: []const Edge } {
    var out: std.ArrayList(Edge) = .empty;
    var m = n;
    for (edges) |e| {
        if (!e.bi) {
            try out.append(a, e);
            continue;
        }
        try out.append(a, .{ .from = m, .to = e.from });
        try out.append(a, .{ .from = m, .to = e.to });
        m += 1;
    }
    return .{ .n = m, .edges = out.items };
}

/// Graph kernel over node indexes 0..n.
pub const Graph = struct {
    n: usize,
    edges: []const Edge,

    fn closure(g: Graph, a: A, seeds: []const usize, down: bool, skip_out_of: []const bool, skip_into: []const bool) ![]bool {
        const r = try a.alloc(bool, g.n);
        @memset(r, false);
        var stack: std.ArrayList(usize) = .empty;
        for (seeds) |x| if (!r[x]) {
            r[x] = true;
            try stack.append(a, x);
        };
        while (stack.pop()) |v| for (g.edges) |e| {
            if (skip_out_of[e.from] or skip_into[e.to]) continue;
            const w = if (down and e.from == v) e.to else if (!down and e.to == v) e.from else continue;
            if (!r[w]) {
                r[w] = true;
                try stack.append(a, w);
            }
        };
        return r;
    }

    /// d-separation of X and Y given Z (reachability with active colliders,
    /// Koller and Friedman 2009 Algorithm 3.1).
    pub fn dSeparated(g: Graph, a: A, xs: []const usize, ys: []const usize, z: []const bool) !bool {
        const none = try a.alloc(bool, g.n);
        @memset(none, false);
        var zs: std.ArrayList(usize) = .empty;
        for (z, 0..) |b, k| if (b) try zs.append(a, k);
        const anc = try g.closure(a, zs.items, false, none, none);
        // visited[v][0] = arrived from a child (up), [1] = from a parent (down)
        const vis = try a.alloc([2]bool, g.n);
        @memset(vis, .{ false, false });
        var stack: std.ArrayList(struct { v: usize, down: bool }) = .empty;
        for (xs) |x| try stack.append(a, .{ .v = x, .down = false });
        while (stack.pop()) |cur| {
            const d: usize = @intFromBool(cur.down);
            if (vis[cur.v][d]) continue;
            vis[cur.v][d] = true;
            if (!z[cur.v] and contains(ys, cur.v)) return false;
            if (!cur.down) {
                if (z[cur.v]) continue;
                for (g.edges) |e| {
                    if (e.to == cur.v) try stack.append(a, .{ .v = e.from, .down = false });
                    if (e.from == cur.v) try stack.append(a, .{ .v = e.to, .down = true });
                }
            } else {
                if (!z[cur.v]) {
                    for (g.edges) |e| if (e.from == cur.v) try stack.append(a, .{ .v = e.to, .down = true });
                }
                if (anc[cur.v]) {
                    for (g.edges) |e| if (e.to == cur.v) try stack.append(a, .{ .v = e.from, .down = false });
                }
            }
        }
        return true;
    }
};

pub const Analysis = struct {
    /// Candidate covariates (measured, not X/Y), alphabetical.
    candidates: []const usize,
    forbidden: []const bool,
    pbd: Graph,
    /// METHOD=BACKDOOR (Pearl 2009b, p.2315): no descendant of a treatment
    /// in the set, which must d-separate X and Y once the edges out of X are
    /// removed.
    backdoor: ?struct { de_x: []const bool, g: Graph } = null,
};

pub fn analyseMethod(a: A, n: usize, edges: []const Edge, xs: []const usize, ys: []const usize, method: Method) !Analysis {
    var an = try analyse(a, n, edges, xs, ys);
    if (method != .backdoor) return an;
    const none = try a.alloc(bool, n);
    @memset(none, false);
    const g: Graph = .{ .n = n, .edges = edges };
    const de = try g.closure(a, xs, true, none, none);
    var out: std.ArrayList(Edge) = .empty;
    for (edges) |e| if (!contains(xs, e.from)) try out.append(a, e);
    an.backdoor = .{ .de_x = de, .g = .{ .n = n, .edges = out.items } };
    return an;
}

/// Constructive back-door setup (van der Zander et al. 2014): proper causal
/// path nodes PCP = (De_{G-in(X)}(X) \ X) ∩ An_{G-out(X)}(Y), forbidden set
/// De(PCP) ∪ X, proper back-door graph = G without X -> PCP edges.
pub fn analyse(a: A, n: usize, edges: []const Edge, xs: []const usize, ys: []const usize) !Analysis {
    const none = try a.alloc(bool, n);
    @memset(none, false);
    const isx = try a.alloc(bool, n);
    @memset(isx, false);
    for (xs) |x| isx[x] = true;
    const g: Graph = .{ .n = n, .edges = edges };
    const de_x = try g.closure(a, xs, true, none, isx);
    const an_y = try g.closure(a, ys, false, isx, none);
    var pcp: std.ArrayList(usize) = .empty;
    for (0..n) |v| if (de_x[v] and an_y[v] and !isx[v]) try pcp.append(a, v);
    const forb = try g.closure(a, pcp.items, true, none, none);
    for (xs) |x| forb[x] = true;
    var pbd: std.ArrayList(Edge) = .empty;
    for (edges) |e| if (!(isx[e.from] and contains(pcp.items, e.to))) try pbd.append(a, e);
    return .{ .candidates = &.{}, .forbidden = forb, .pbd = .{ .n = n, .edges = pbd.items } };
}

pub fn validAdjustment(a: A, an: Analysis, xs: []const usize, ys: []const usize, z: []const bool) !bool {
    if (an.backdoor) |bd| {
        for (z, 0..) |b, k| if (b and bd.de_x[k]) return false;
        return bd.g.dSeparated(a, xs, ys, z);
    }
    for (z, 0..) |b, k| if (b and an.forbidden[k]) return false;
    return an.pbd.dSeparated(a, xs, ys, z);
}

fn lessName(names: []const []const u8, l: usize, r: usize) bool {
    return std.ascii.lessThanIgnoreCase(names[l], names[r]);
}

pub const Set = struct { mask: u64, size: usize, minimal: bool = false };

fn setLess(_: void, l: Set, r: Set) bool {
    if (l.size != r.size) return l.size < r.size;
    // Same size: lexicographic over the alphabetical covariate order (the
    // lowest-indexed differing covariate present first).
    const diff = l.mask ^ r.mask;
    if (diff == 0) return false;
    const low: u6 = @intCast(@ctz(diff));
    return (l.mask >> low) & 1 == 1;
}

const max_candidates = 20;
/// Set masks are u64: the pruned search (`Search`) lists sets over at most
/// 64 covariates.
const max_search_candidates = 64;
/// ponytail: a listing that must hold more sets than this (sorted order, or
/// NOSORT MINIMAL) fails loud instead of exhausting memory; SAS itself ran
/// more than 300 s on 2^22 sets (reference run, STAT-CAUSALGRAPH-008).
const max_listed_sets = 1 << 20;

/// Pruned listing of adjustment sets (Takata 2010; van der Zander,
/// Liskiewicz and Textor 2014, ListAdj): a branch I <= Z <= R is explored
/// only if An(X u Y u I) n R is valid, which holds iff some valid set lies
/// in the branch, so every output costs polynomial time. Branching includes
/// the lowest (alphabetically first) free covariate first, the order SAS's
/// NOSORT listing walks backwards (reference runs).
pub const Search = struct {
    a: A,
    n: usize,
    g: Graph,
    an: Analysis,
    cands: []const usize,
    xs: []const usize,
    ys: []const usize,
    /// Allowed covariates (not forbidden for the method).
    allowed: u64,
    required: u64,
    out: std.ArrayList(Set) = .empty,
    /// Stop after this many outputs (null = all, capped by max_listed_sets).
    limit: ?usize = null,
    maxsize: ?usize = null,
    cap: usize = max_listed_sets,
    overflow: bool = false,

    pub fn init(a: A, n: usize, edges: []const Edge, an: Analysis, cands: []const usize, xs: []const usize, ys: []const usize, required: u64) !Search {
        var allowed: u64 = 0;
        for (cands, 0..) |c, k| {
            const banned = if (an.backdoor) |bd| bd.de_x[c] else an.forbidden[c];
            if (!banned) allowed |= @as(u64, 1) << @intCast(k);
        }
        return .{ .a = a, .n = n, .g = .{ .n = n, .edges = edges }, .an = an, .cands = cands, .xs = xs, .ys = ys, .allowed = allowed, .required = required };
    }

    /// Covariates of `r` that are ancestors of X, Y or the covariates `i`.
    fn ancIn(self: *Search, sa: A, i: u64, r: u64) !u64 {
        const none = try sa.alloc(bool, self.n);
        @memset(none, false);
        var seeds: std.ArrayList(usize) = .empty;
        try seeds.appendSlice(sa, self.xs);
        try seeds.appendSlice(sa, self.ys);
        for (self.cands, 0..) |c, k| if ((i >> @intCast(k)) & 1 == 1) try seeds.append(sa, c);
        const anc = try self.g.closure(sa, seeds.items, false, none, none);
        var mask: u64 = 0;
        for (self.cands, 0..) |c, k| if (anc[c] and (r >> @intCast(k)) & 1 == 1) {
            mask |= @as(u64, 1) << @intCast(k);
        };
        return mask;
    }

    pub fn valid(self: *Search, mask: u64) !bool {
        var scratch = std.heap.ArenaAllocator.init(self.a);
        defer scratch.deinit();
        const sa = scratch.allocator();
        const z = try sa.alloc(bool, self.n);
        @memset(z, false);
        for (self.cands, 0..) |c, k| if ((mask >> @intCast(k)) & 1 == 1) {
            z[c] = true;
        };
        return validAdjustment(sa, self.an, self.xs, self.ys, z);
    }

    /// Some valid set Z with i <= Z <= r exists.
    fn exists(self: *Search, i: u64, r: u64) !bool {
        if (i & ~r != 0) return false;
        var scratch = std.heap.ArenaAllocator.init(self.a);
        defer scratch.deinit();
        return self.valid(try self.ancIn(scratch.allocator(), i, r));
    }

    /// The direct search of NOSORT MAXLIST=1 (p.2331): An(X u Y u I) over
    /// the allowed covariates, valid iff any adjustment set exists.
    pub fn direct(self: *Search) !?Set {
        if (self.required & ~self.allowed != 0) return null;
        var scratch = std.heap.ArenaAllocator.init(self.a);
        defer scratch.deinit();
        const z0 = try self.ancIn(scratch.allocator(), self.required, self.allowed);
        if (!try self.valid(z0)) return null;
        return .{ .mask = z0, .size = @popCount(z0), .minimal = try self.isMinimal(z0) };
    }

    /// Minimal among valid sets containing the prescribed ones (p.2301):
    /// no valid set lies between I and Z minus one free member.
    pub fn isMinimal(self: *Search, z: u64) !bool {
        var free = z & ~self.required;
        while (free != 0) {
            const b = free & (~free + 1);
            free &= ~b;
            if (try self.exists(self.required, z & ~b)) return false;
        }
        return true;
    }

    fn rec(self: *Search, i: u64, r: u64) !void {
        if (self.overflow) return;
        if (self.limit) |l| if (self.out.items.len >= l) return;
        if (!try self.exists(i, r)) return;
        if (i == r) {
            if (self.maxsize) |ms| if (@popCount(i) > ms) return;
            if (self.out.items.len >= self.cap) {
                self.overflow = true;
                return;
            }
            try self.out.append(self.a, .{ .mask = i, .size = @popCount(i) });
            return;
        }
        const freeb = r & ~i;
        const b = freeb & (~freeb + 1);
        try self.rec(i | b, r);
        try self.rec(i, r & ~b);
    }

    /// Valid sets in inclusion-first order with minimal flags.
    pub fn list(self: *Search) ![]Set {
        try self.rec(self.required, self.allowed);
        for (self.out.items) |*st| st.minimal = try self.isMinimal(st.mask);
        return self.out.items;
    }
};

/// All valid adjustment sets over `cands` (bit k = cands[k]), sorted by size.
/// `required` holds the prescribed adjustment variables (p.2303): every set
/// contains them, and minimality is judged among such sets only (p.2301).
pub fn enumerate(a: A, n: usize, an: Analysis, cands: []const usize, xs: []const usize, ys: []const usize, required: u64) ![]Set {
    var sets: std.ArrayList(Set) = .empty;
    const z = try a.alloc(bool, n);
    const total: u64 = @as(u64, 1) << @intCast(cands.len);
    var mask: u64 = 0;
    while (mask < total) : (mask += 1) {
        if (mask & required != required) continue;
        @memset(z, false);
        for (cands, 0..) |c, k| if ((mask >> @intCast(k)) & 1 == 1) {
            z[c] = true;
        };
        var scratch = std.heap.ArenaAllocator.init(a);
        defer scratch.deinit();
        if (try validAdjustment(scratch.allocator(), an, xs, ys, z)) try sets.append(a, .{ .mask = mask, .size = @popCount(mask) });
    }
    for (sets.items) |*s| {
        s.minimal = true;
        for (sets.items) |o| if (o.mask != s.mask and o.mask & s.mask == o.mask) {
            s.minimal = false;
            break;
        };
    }
    std.mem.sort(Set, sets.items, {}, setLess);
    return sets.items;
}

/// Inclusion-first search order over the alphabetical covariates: at the
/// lowest covariate where two sets differ, the set containing it comes first.
fn inclusionFirst(_: void, l: Set, r: Set) bool {
    const diff = l.mask ^ r.mask;
    if (diff == 0) return false;
    const low: u6 = @intCast(@ctz(diff));
    return (l.mask >> low) & 1 == 1;
}

/// NOSORT listing (SAS 9.4 reference runs, batch of 5 runs for
/// STAT-CAUSALGRAPH-008). The MINIMAL/MAXSIZE= filters apply first. Order L:
/// minimal sets in inclusion-first order, otherwise its reverse (exclusion
/// first). MAXLIST=m keeps the last m sets of L, as a search that walks L
/// backwards and stops after m sets would. MAXLIST=1 instead reports the
/// direct-search set `one` (no MINIMAL) or the first minimal set of L.
// ponytail: the MAXLIST=1 MINIMAL rule (first of L) matches 4 reference
// graphs; SAS's FindMinAdj walk might differ on graphs not yet compared.
fn nosortList(a: A, shown: *std.ArrayList(Set), o: Options, sets: []const Set, one: ?Set) !void {
    var f: std.ArrayList(Set) = .empty;
    for (sets) |st| {
        if (o.minimal and !st.minimal) continue;
        if (o.maxsize) |ms| if (st.size > ms) continue;
        try f.append(a, st);
    }
    std.mem.sort(Set, f.items, {}, inclusionFirst);
    if (!o.minimal) std.mem.reverse(Set, f.items);
    if (o.maxlist != null and o.maxlist.? == 1) {
        if (o.minimal) {
            if (f.items.len > 0) try shown.append(a, f.items[0]);
        } else if (one) |st| {
            if (o.maxsize == null or st.size <= o.maxsize.?) try shown.append(a, st);
        }
        return;
    }
    const keep = if (o.maxlist) |ml| @min(ml, f.items.len) else f.items.len;
    try shown.appendSlice(a, f.items[f.items.len - keep ..]);
}

// ── listing ────────────────────────────────────────────────────────────────

const Align = enum { left, right, center };
const Col = struct { head: []const []const u8, al: Align, width: usize, cells: []const []const u8, head_al: ?Align = null };

fn pad(a: A, o: *Out, s: []const u8, w: usize, al: Align) !void {
    const extra = w -| s.len;
    const lead = switch (al) {
        .left => 0,
        .right => extra,
        .center => extra / 2,
    };
    try o.appendNTimes(a, ' ', lead);
    try o.appendSlice(a, s);
    try o.appendNTimes(a, ' ', extra - lead);
}

fn rstripLine(a: A, o: *Out, line: []const u8) !void {
    try o.appendSlice(a, std.mem.trimEnd(u8, line, " "));
    try o.append(a, '\n');
}

/// Render one listing table: centered titles, optional spanner over columns
/// [span_from..], bottom-aligned multi-line headers, padded data rows.
/// `gaps[k]` is the blank count before column k (k > 0).
const Spanner = struct { from: usize, text: []const u8 };

fn table(a: A, o: *Out, titles: []const []const u8, center_extra: usize, cols: []const Col, gaps: []const usize, spanner: ?Spanner) !void {
    var width: usize = 0;
    for (cols, 0..) |c, k| width += c.width + (if (k > 0) gaps[k] else 0);
    for (titles) |tl| {
        try o.appendNTimes(a, ' ', (width + center_extra -| tl.len) / 2);
        try o.appendSlice(a, tl);
        try o.append(a, '\n');
    }
    try o.appendSlice(a, " \n");
    var line: Out = .empty;
    if (spanner) |sp| {
        var start: usize = 0;
        for (cols[0..sp.from], 0..) |c, k| start += c.width + (if (k > 0) gaps[k] else 0);
        start += gaps[sp.from];
        const span = width - start;
        try line.appendNTimes(a, ' ', start);
        const dashes = span -| sp.text.len;
        try line.appendNTimes(a, '-', dashes / 2);
        try line.appendSlice(a, sp.text);
        try line.appendNTimes(a, '-', dashes - dashes / 2);
        try rstripLine(a, o, line.items);
    }
    var hl: usize = 1;
    for (cols) |c| hl = @max(hl, c.head.len);
    for (0..hl) |r| {
        line.clearRetainingCapacity();
        for (cols, 0..) |c, k| {
            if (k > 0) try line.appendNTimes(a, ' ', gaps[k]);
            const off = hl - c.head.len;
            const txt = if (r >= off) c.head[r - off] else "";
            try pad(a, &line, txt, c.width, c.head_al orelse c.al);
        }
        try rstripLine(a, o, line.items);
    }
    try o.append(a, '\n');
    const rows = cols[0].cells.len;
    for (0..rows) |r| {
        for (cols, 0..) |c, k| {
            if (k > 0) try o.appendNTimes(a, ' ', gaps[k]);
            try pad(a, o, c.cells[r], c.width, c.al);
        }
        try o.append(a, '\n');
    }
}

fn uniformGaps(a: A, n: usize) ![]usize {
    const g = try a.alloc(usize, n);
    @memset(g, 4);
    g[0] = 0;
    return g;
}

fn num(a: A, v: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{v});
}

/// Header pieces of a covariate column: split at each lower-to-upper case
/// transition (reference run: PrevBF prints as Prev / BF).
// ponytail: the split rule is inferred from one reference name (PrevBF);
// names without a case transition stay whole.
fn splitHeader(a: A, n: []const u8) ![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    var start: usize = 0;
    for (1..n.len) |k| if (std.ascii.isLower(n[k - 1]) and std.ascii.isUpper(n[k])) {
        try parts.append(a, n[start..k]);
        start = k;
    };
    try parts.append(a, n[start..]);
    return parts.items;
}

fn page(cx: proc.ProcCtx, o: *Out) !void {
    if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, o);
    try o.appendSlice(cx.arena, "\nThe CAUSALGRAPH Procedure\n\n");
}

fn endPage(cx: proc.ProcCtx, o: *Out) !void {
    if (cx.listing_titles) |titles| try titles.emitFootnotes(cx.arena, o);
}

fn sortedIds(names: []const []const u8, ids: []usize) void {
    std.mem.sort(usize, ids, names, lessName);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    var keep = false;
    return runKeeping(cx, out, t, &keep);
}

/// `run`, setting `keep` when the step fails after printing tables SAS also
/// prints before its error (the directed-cycle error, p.2329): the caller
/// then keeps the listing written so far. Every other failure leaves `keep`
/// false and the listing is dropped.
pub fn runKeeping(cx: proc.ProcCtx, out: *Out, t: []const lex.Token, keep: *bool) diag.Error!void {
    const a = cx.arena;
    var s = try parse(cx, t);
    try validate(cx, s);
    // NOSORT is dropped under MAXSIZE=MIN, else under METHOD=IV (SAS 9.4
    // reference runs: one warning, MAXSIZE=MIN checked first, also with
    // NOLIST or NOPRINT).
    if (s.opts.nosort and s.opts.maxsize != null and s.opts.maxsize.? == 0) {
        try cx.diags.warn(lineOf(t, 0), "The NOSORT option is ignored when MAXSIZE=MIN.", .{});
        s.opts.nosort = false;
    } else if (s.opts.nosort and s.opts.method == .iv) {
        try cx.diags.warn(lineOf(t, 0), "The NOSORT option is ignored when METHOD=IV.", .{});
        s.opts.nosort = false;
    }
    if (s.opts.ordermodels) {
        // ORDERMODELS: models in label order (reference run: Alpha, Mid,
        // Zeta for models written Zeta, Alpha, Mid).
        const ms = try a.dupe(Model, s.models);
        std.mem.sort(Model, ms, {}, struct {
            fn f(_: void, l: Model, r: Model) bool {
                return std.ascii.lessThanIgnoreCase(l.label, r.label);
            }
        }.f);
        s.models = ms;
    }
    // Directed cycles (p.2329), per model in listing order.
    const cycles = try a.alloc(?[]const usize, s.models.len);
    var any_cycle = false;
    for (s.models, cycles) |m, *c| {
        c.* = try firstCycle(a, s.names, m);
        if (c.* != null) any_cycle = true;
    }
    const n = s.names.len;
    // LIST is the default with IDENTIFY and no TESTID (p.2300).
    const list = s.opts.list orelse (s.identify and s.tests.len == 0);
    const iv = s.opts.method == .iv;

    // Variables of all models (SAS 9.4 reference run with two MODEL
    // statements: one VariableInfo table titled "Variables in Models").
    var all_nodes: std.ArrayList(usize) = .empty;
    for (s.models) |m| for (m.nodes) |v| if (!contains(all_nodes.items, v)) try all_nodes.append(a, v);
    var measured: std.ArrayList(usize) = .empty;
    var unmeasured: std.ArrayList(usize) = .empty;
    for (all_nodes.items) |v| try (if (contains(s.unmeasured, v)) &unmeasured else &measured).append(a, v);
    sortedIds(s.names, measured.items);
    sortedIds(s.names, unmeasured.items);

    // Covariate columns are the union over the models; each model's sets
    // range over its own measured covariates only (reference run: a
    // covariate of another model is never starred).
    var cands: std.ArrayList(usize) = .empty;
    const sets = try a.alloc([]Set, s.models.len);
    @memset(sets, &.{});
    // NOSORT MAXLIST=1: the one set of the direct search, per model.
    const ones = try a.alloc(?Set, s.models.len);
    @memset(ones, null);
    for (measured.items) |v| if (!contains(s.treatments, v) and !contains(s.outcomes, v)) try cands.append(a, v);
    if (list and !iv and !any_cycle) {
        if (cands.items.len > max_search_candidates) return gap(cx, s.models[0].line, "more than {d} measured covariates in an adjustment-set listing is not implemented", .{max_search_candidates});
        for (s.models, sets, ones) |m, *dst, *one| {
            var mc: std.ArrayList(usize) = .empty;
            var pos: std.ArrayList(usize) = .empty;
            for (cands.items, 0..) |c, k| if (contains(m.nodes, c)) {
                try mc.append(a, c);
                try pos.append(a, k);
            };
            // Joint effect: a role variable missing from one model is dropped
            // there with a warning, treatments, then outcomes, then
            // adjustment variables (SAS 9.4 reference run); the isolated
            // node then plays no part in that model's criterion.
            for (s.treatments) |x| if (!contains(m.nodes, x)) try cx.diags.warn(s.identify_line, "The treatment variable {s} is not found in the model {s}.", .{ s.names[x], m.label });
            for (s.outcomes) |y| if (!contains(m.nodes, y)) try cx.diags.warn(s.identify_line, "The outcome variable {s} is not found in the model {s}.", .{ s.names[y], m.label });
            var required: u64 = 0;
            for (s.adjust) |z| {
                // A prescribed variable missing from this model is dropped
                // for it with a warning (SAS 9.4 reference run).
                const k = std.mem.indexOfScalar(usize, mc.items, z) orelse {
                    try cx.diags.warn(s.identify_line, "The adjustment variable {s} is not found in the model {s}.", .{ s.names[z], m.label });
                    continue;
                };
                required |= @as(u64, 1) << @intCast(k);
            }
            const g = try expandLatent(a, n, m.edges);
            const an = try analyseMethod(a, g.n, g.edges, s.treatments, s.outcomes, s.opts.method);
            var search = try Search.init(a, g.n, g.edges, an, mc.items, s.treatments, s.outcomes, required);
            const o = s.opts;
            const one_only = o.nosort and !o.minimal and o.maxlist != null and o.maxlist.? == 1;
            if (one_only) {
                one.* = try search.direct();
            } else {
                // NOSORT without MINIMAL walks the search order and stops
                // after MAXLIST= sets within MAXSIZE= (Time Requirements
                // p.2331); sorting or MINIMAL needs every set.
                if (o.nosort and !o.minimal) {
                    search.limit = o.maxlist;
                    search.maxsize = o.maxsize;
                }
                const listed = try search.list();
                if (search.overflow) return gap(cx, m.line, "listing more than {d} adjustment sets is not implemented", .{max_listed_sets});
                if (!o.nosort) std.mem.sort(Set, listed, {}, setLess);
                dst.* = listed;
            }
            const local = dst.*;
            if (one.*) |*o1| {
                var mask: u64 = 0;
                for (pos.items, 0..) |k, b| if ((o1.mask >> @intCast(b)) & 1 == 1) {
                    mask |= @as(u64, 1) << @intCast(k);
                };
                o1.mask = mask;
            }
            // Re-key masks onto the union columns (order is preserved: both
            // lists are alphabetical).
            for (local) |*st| {
                var mask: u64 = 0;
                for (pos.items, 0..) |k, b| if ((st.mask >> @intCast(b)) & 1 == 1) {
                    mask |= @as(u64, 1) << @intCast(k);
                };
                st.mask = mask;
            }
            dst.* = local;
        }
    }
    if (any_cycle and (s.opts.noprint or s.opts.psummary)) {
        // SAS 9.4 reference runs: NOPRINT and PSUMMARY (with or without
        // LIST) print nothing; the log keeps model order, a disconnected
        // warning and a cycle error per model.
        for (s.models, cycles) |m, c| {
            const cc = try componentIds(a, s.names, m);
            if (cc.count > 1 and !s.opts.disconnected) try cx.diags.warn(m.line, "The model {s} contains {d} disconnected DAGs.", .{ m.label, cc.count });
            if (c != null) try cycleError(cx, m);
        }
        return error.ParseError;
    }
    if (s.opts.noprint) {
        for (s.models) |m| {
            const cc = try componentIds(a, s.names, m);
            if (cc.count > 1 and !s.opts.disconnected) try cx.diags.warn(m.line, "The model {s} contains {d} disconnected DAGs.", .{ m.label, cc.count });
        }
        return;
    }
    if (s.opts.psummary) {
        // SAS 9.4 reference run: PSUMMARY prints one AdjustList page (or the
        // no-set NOTE) per model and nothing at all without LIST.
        for (s.models) |m| {
            const cc = try componentIds(a, s.names, m);
            // ponytail: whether PSUMMARY keeps the ConnectedComponents table
            // has no reference run; refuse rather than guess the layout.
            if (cc.count > 1) return gap(cx, m.line, "the PSUMMARY option with a disconnected model is not implemented", .{});
        }
        var open = false;
        try emitTests(cx, out, s, cands.items, &open);
        if (open) try endPage(cx, out);
        if (!list) return;
        for (s.models, sets, ones) |m, msets, one| {
            try page(cx, out);
            if (iv) try ivListTable(cx, out, s, m, cands.items) else try adjustTable(cx, out, s, m, msets, one, cands.items);
            try endPage(cx, out);
        }
        return;
    }

    // Page 1: VariableInfo and GraphicalModelSummary.
    try page(cx, out);
    {
        const join = struct {
            fn f(al: A, names: []const []const u8, ids: []const usize) ![]const u8 {
                var b: Out = .empty;
                for (ids, 0..) |id, k| {
                    if (k > 0) try b.append(al, ' ');
                    try b.appendSlice(al, names[id]);
                }
                return b.items;
            }
        }.f;
        const mv = try join(a, s.names, measured.items);
        const uv = try join(a, s.names, unmeasured.items);
        const cols = [_]Col{
            .{ .head = &.{""}, .al = .left, .width = 10, .cells = &.{ "Measured", "Unmeasured" } },
            .{ .head = &.{"N"}, .al = .right, .width = 10, .cells = &.{ try num(a, measured.items.len), try num(a, unmeasured.items.len) } },
            .{ .head = &.{"Variables"}, .al = .left, .width = @max(9, @max(mv.len, uv.len)), .cells = &.{ mv, uv } },
        };
        try table(a, out, &.{if (s.models.len > 1) "Variables in Models" else "Variables in Model"}, 0, &cols, try uniformGaps(a, cols.len), null);
    }
    try out.appendSlice(a, "\n\n");
    {
        const heads = [_][]const u8{ "Nodes", "Edges", "Treatments", "Outcomes", "Measured", "Unmeasured" };
        const rows = s.models.len;
        var cols: [7]Col = undefined;
        const labels = try a.alloc([]const u8, rows);
        var lw: usize = 5;
        for (s.models, labels) |m, *l| {
            l.* = m.label;
            lw = @max(lw, m.label.len);
        }
        cols[0] = .{ .head = &.{"Model"}, .al = .left, .width = lw, .cells = labels };
        for (heads, 1..) |h, k| {
            const cells = try a.alloc([]const u8, rows);
            for (s.models, cells) |m, *cell| {
                var tr: usize = 0;
                var oc: usize = 0;
                var um: usize = 0;
                for (m.nodes) |v| {
                    if (contains(s.treatments, v)) tr += 1;
                    if (contains(s.outcomes, v)) oc += 1;
                    if (contains(s.unmeasured, v)) um += 1;
                }
                const vals = [_]usize{ m.nodes.len, m.edges.len, tr, oc, m.nodes.len - um, um };
                cell.* = try num(a, vals[k - 1]);
            }
            const head = try a.alloc([]const u8, 1);
            head[0] = h;
            cols[k] = .{ .head = head, .al = .right, .width = @max(8, h.len), .cells = cells };
        }
        try table(a, out, &.{"Graphical Model Summary"}, 0, &cols, try uniformGaps(a, cols.len), null);
    }
    // ConnectedComponents (reference runs): without the DISCONNECTED option
    // a disconnected model is warned about and no model gets an AdjustList.
    if (any_cycle) {
        // SAS 9.4 reference runs (ORDERMODELS order applies): per model, a
        // disconnected one gets its ConnectedComponents page, and a cyclic
        // one its DirectedCycles table (on that same page, else a new one)
        // and its error; no TESTID or adjustment table follows.
        for (s.models, cycles) |m, c| {
            const cc = try componentIds(a, s.names, m);
            if (cc.count > 1) {
                if (!s.opts.disconnected) try cx.diags.warn(m.line, "The model {s} contains {d} disconnected DAGs.", .{ m.label, cc.count });
                try endPage(cx, out);
                try page(cx, out);
                try componentsTable(a, out, s.names, m, cc);
            }
            if (c) |cyc| {
                if (cc.count > 1) try out.appendSlice(a, "\n\n") else {
                    try endPage(cx, out);
                    try page(cx, out);
                }
                try cyclesTable(a, out, s.names, m, cyc);
                try cycleError(cx, m);
            }
        }
        try endPage(cx, out);
        keep.* = true;
        return error.ParseError;
    }
    var any_disc = false;
    for (s.models) |m| {
        const cc = try componentIds(a, s.names, m);
        if (cc.count < 2) continue;
        any_disc = true;
        if (!s.opts.disconnected) try cx.diags.warn(m.line, "The model {s} contains {d} disconnected DAGs.", .{ m.label, cc.count });
        try endPage(cx, out);
        try page(cx, out);
        try componentsTable(a, out, s.names, m, cc);
    }
    // Without DISCONNECTED a disconnected model suppresses the TESTID tables
    // too (reference run); with it they follow the components tables.
    var open = true;
    if (!(any_disc and !s.opts.disconnected)) try emitTests(cx, out, s, cands.items, &open);
    if (!list or (any_disc and !s.opts.disconnected)) return endPage(cx, out);

    // One AdjustList (InstrumentList) page per model.
    for (s.models, sets, ones) |m, msets, one| {
        try endPage(cx, out);
        try page(cx, out);
        if (iv) try ivListTable(cx, out, s, m, cands.items) else try adjustTable(cx, out, s, m, msets, one, cands.items);
    }
    try endPage(cx, out);
}

/// Recorded without failing yet: SAS reports every cyclic model (and the
/// warnings of the models between them) before stopping the step.
fn cycleError(cx: proc.ProcCtx, m: Model) !void {
    try cx.diags.report(.err, m.line, "The model {s} contains at least 1 directed cycle.", .{m.label});
}

const Components = struct { ids: []const usize, count: usize, sorted: []const usize };

/// Component number of each model node; components are numbered in the
/// order of their alphabetically first node (reference runs: {A,B,C} before
/// {X,Y}, {P,Q} before {X,Y}, {A,B} before {X,Y,Z}).
fn componentIds(a: A, names: []const []const u8, m: Model) !Components {
    const sorted = try a.dupe(usize, m.nodes);
    sortedIds(names, sorted);
    const comp = try a.alloc(usize, names.len);
    @memset(comp, std.math.maxInt(usize));
    var count: usize = 0;
    for (sorted) |start| {
        if (comp[start] != std.math.maxInt(usize)) continue;
        var stack: std.ArrayList(usize) = .empty;
        try stack.append(a, start);
        comp[start] = count;
        while (stack.pop()) |v| for (m.edges) |e| {
            const w = if (e.from == v) e.to else if (e.to == v) e.from else continue;
            if (comp[w] == std.math.maxInt(usize)) {
                comp[w] = count;
                try stack.append(a, w);
            }
        };
        count += 1;
    }
    return .{ .ids = comp, .count = count, .sorted = sorted };
}

fn componentsTable(a: A, out: *Out, names: []const []const u8, m: Model, cc: Components) !void {
    const rows = cc.count;
    const idc = try a.alloc([]const u8, rows);
    const szc = try a.alloc([]const u8, rows);
    for (0..rows) |r| {
        var size: usize = 0;
        for (cc.sorted) |v| {
            if (cc.ids[v] == r) size += 1;
        }
        idc[r] = try num(a, r + 1);
        szc[r] = try num(a, size);
    }
    var cols: std.ArrayList(Col) = .empty;
    try cols.append(a, .{ .head = &.{"Component"}, .al = .right, .width = 9, .cells = idc });
    try cols.append(a, .{ .head = &.{"Size"}, .al = .right, .width = 8, .cells = szc });
    for (cc.sorted) |v| {
        const head = try splitHeader(a, names[v]);
        var w: usize = 1;
        for (head) |h| w = @max(w, h.len);
        const cells = try a.alloc([]const u8, rows);
        for (cells, 0..) |*c, r| c.* = if (cc.ids[v] == r) "*" else "";
        try cols.append(a, .{ .head = head, .al = .center, .width = w, .cells = cells });
    }
    // ponytail: header splitting and spanner widening follow the AdjustList
    // rules; the reference runs only had one-letter node names.
    const gaps = try uniformGaps(a, cols.items.len);
    const title = try std.fmt.allocPrint(a, "Connected Components for {s}", .{m.label});
    try table(a, out, &.{title}, 1, cols.items, gaps, Spanner{ .from = 2, .text = "Nodes" });
}

fn adjustTable(cx: proc.ProcCtx, out: *Out, s: Spec, m: Model, sets: []const Set, one: ?Set, cands: []const usize) !void {
    const a = cx.arena;
    var shown: std.ArrayList(Set) = .empty;
    if (s.opts.nosort) {
        try nosortList(a, &shown, s.opts, sets, one);
    } else {
        const min_size: usize = if (sets.len > 0) sets[0].size else 0;
        for (sets) |st| {
            if (s.opts.minimal and !st.minimal) continue;
            if (s.opts.maxsize) |ms| if ((ms == 0 and st.size != min_size) or (ms > 0 and st.size > ms)) continue;
            if (s.opts.maxlist) |ml| if (shown.items.len >= ml) break;
            try shown.append(a, st);
        }
    }
    if (shown.items.len == 0) {
        // A joint effect adds a second sentence, also for one treatment with
        // several outcomes (SAS 9.4 reference run).
        const joint = s.treatments.len > 1 or s.outcomes.len > 1;
        try out.appendSlice(a, try std.fmt.allocPrint(a, "NOTE: There are no adjustment sets satisfying the specified criteria for {s}.{s}\n\n", .{ m.label, if (joint) " Adjustment sets might exist for individual treatment effects." else "" }));
        return;
    }
    var used: std.ArrayList(usize) = .empty; // bit positions into cands
    for (cands, 0..) |_, k| {
        var any = !s.opts.compact;
        for (shown.items) |st| {
            if ((st.mask >> @intCast(k)) & 1 == 1) any = true;
        }
        if (any) try used.append(a, k);
    }
    var cols: std.ArrayList(Col) = .empty;
    const rows = shown.items.len;
    const obs = try a.alloc([]const u8, rows);
    const size = try a.alloc([]const u8, rows);
    const mini = try a.alloc([]const u8, rows);
    for (shown.items, 0..) |st, r| {
        obs[r] = try num(a, r + 1);
        size[r] = try num(a, st.size);
        mini[r] = if (st.minimal) "Yes" else "No";
    }
    try cols.append(a, .{ .head = &.{""}, .al = .right, .width = 8, .cells = obs });
    try cols.append(a, .{ .head = &.{"Size"}, .al = .right, .width = 8, .cells = size });
    try cols.append(a, .{ .head = &.{"Minimal"}, .al = .left, .width = 8, .cells = mini });
    for (used.items) |k| {
        const head = try splitHeader(a, s.names[cands[k]]);
        var w: usize = 1;
        for (head) |h| w = @max(w, h.len);
        const cells = try a.alloc([]const u8, rows);
        for (shown.items, cells) |st, *c| c.* = if ((st.mask >> @intCast(k)) & 1 == 1) "*" else "";
        try cols.append(a, .{ .head = head, .al = .center, .width = w, .cells = cells });
    }
    const gaps = try uniformGaps(a, cols.items.len);
    // A table wider than LINESIZE= narrows every column gap to 3, then 2
    // (SAS 9.4 reference runs with 23 and 25 covariates at LS=160).
    // ponytail: narrower gaps and page-wise splitting have no reference run.
    const ls = @import("../io.zig").global_linesize;
    if (ls > 0) {
        var total: usize = 0;
        for (cols.items) |c| total += c.width;
        var g: usize = 4;
        while (total + g * (cols.items.len - 1) > ls and g > 2) g -= 1;
        if (total + g * (cols.items.len - 1) > ls) return gap(cx, m.line, "an adjustment-set table wider than LINESIZE={d} is not implemented", .{ls});
        for (gaps[1..]) |*gp| gp.* = g;
    }
    const span_text = "Covariates";
    if (used.items.len > 0) {
        // The spanner needs its text plus one dash on each side; a single
        // covariate column widens, several columns widen their gaps evenly
        // (SAS 9.4 reference runs).
        var natural: usize = 0;
        for (cols.items[3..], 3..) |c, k| natural += c.width + (if (k > 3) gaps[k] else 0);
        const need = span_text.len + 2;
        if (natural < need) {
            const extra = need - natural;
            if (used.items.len == 1) {
                cols.items[3].width += extra;
            } else {
                const per = (extra + used.items.len - 2) / (used.items.len - 1);
                for (gaps[4..]) |*g| g.* += per;
            }
        }
    }
    const t1 = try std.fmt.allocPrint(a, "Covariate Adjustment Sets for {s}", .{m.label});
    const t2 = try std.fmt.allocPrint(a, "Causal Effect of {s} on {s}", .{ try roleList(a, s.names, s.treatments), try roleList(a, s.names, s.outcomes) });
    try table(a, out, &.{ t1, t2 }, 1, cols.items, gaps, if (used.items.len > 0) Spanner{ .from = 3, .text = span_text } else null);
}

/// One role variable as written; several in braces, alphabetical (SAS 9.4
/// reference runs: `identify B A ==> Q P` titles `{A B} on {P Q}`, also in
/// a model that lacks some of them).
fn roleList(a: A, names: []const []const u8, ids: []const usize) ![]const u8 {
    if (ids.len == 1) return names[ids[0]];
    const ord = try a.dupe(usize, ids);
    sortedIds(names, ord);
    var b: Out = .empty;
    try b.append(a, '{');
    for (ord, 0..) |id, k| {
        if (k > 0) try b.append(a, ' ');
        try b.appendSlice(a, names[id]);
    }
    try b.append(a, '}');
    return b.items;
}

// ── TESTID, METHOD=IV and PATHS (STAT-CAUSALGRAPH-005) ─────────────────────

fn withoutEdge(a: A, g: Graph, x: usize, y: usize) !Graph {
    var out: std.ArrayList(Edge) = .empty;
    for (g.edges) |e| if (e.bi or e.from != x or e.to != y) try out.append(a, e);
    return .{ .n = g.n, .edges = out.items };
}

/// Conditional instrument (Brito and Pearl 2002; ancestral instrument
/// criterion of Van der Zander, Textor and Liskiewicz 2015, cited p.2301):
/// `z` instruments x -> y given `w` when w holds neither z nor a descendant
/// of y, z and x are d-connected given w, and z and y are d-separated given
/// w once the edge x -> y is removed.
pub fn ivValid(a: A, g: Graph, x: usize, y: usize, z: usize, w: []const bool) !bool {
    if (w[z]) return false;
    const none = try a.alloc(bool, g.n);
    @memset(none, false);
    const de_y = try g.closure(a, &.{y}, true, none, none);
    for (w, 0..) |b, k| if (b and de_y[k]) return false;
    if (try g.dSeparated(a, &.{z}, &.{x}, w)) return false;
    return (try withoutEdge(a, g, x, y)).dSeparated(a, &.{z}, &.{y}, w);
}

/// Conditioning set METHOD=IV LIST reports for candidate `z`, or null.
// ponytail: the selection rule is inferred from SAS 9.4 reference runs, not
// documented: an unconditional instrument gets the empty set; otherwise a
// greedy nearest separator, depth first from y over the moral graph of
// An({y, z}) without x -> y, neighbours in alphabetical order, entering an
// unobserved node at once, adding every observed node met and stopping once
// z and y are separated (an unneeded alphabetically earlier parent of y is
// kept, a later one is not: Example 37.5 lists Alcohol BMI Education
// Employment Parity, not Smoking; A1 U ZZ parents of Y with W -> U give
// {A1, W}).
pub fn ivFind(a: A, g: Graph, names: []const []const u8, observed: []const bool, x: usize, y: usize, z: usize) !?[]bool {
    const w = try a.alloc(bool, g.n);
    @memset(w, false);
    if (try ivValid(a, g, x, y, z, w)) return w;
    const gc = try withoutEdge(a, g, x, y);
    const none = try a.alloc(bool, g.n);
    @memset(none, false);
    const anc = try gc.closure(a, &.{ y, z }, false, none, none);
    const adj = try a.alloc(std.ArrayList(usize), g.n);
    for (adj) |*l| l.* = .empty;
    const link = struct {
        fn f(al: A, lists: []std.ArrayList(usize), u: usize, v: usize) !void {
            if (u == v) return;
            if (!contains(lists[u].items, v)) try lists[u].append(al, v);
            if (!contains(lists[v].items, u)) try lists[v].append(al, u);
        }
    }.f;
    for (gc.edges) |e| if (anc[e.from] and anc[e.to]) try link(a, adj, e.from, e.to);
    for (0..g.n) |v| if (anc[v]) {
        var ps: std.ArrayList(usize) = .empty;
        for (gc.edges) |e| if (e.to == v and anc[e.from]) try ps.append(a, e.from);
        for (ps.items, 0..) |p, k| for (ps.items[k + 1 ..]) |q| try link(a, adj, p, q);
    };
    // A bidirected edge u <==> v links u and v directly (its latent parent
    // is not visited): reference runs W <==> Y with A1 ==> Y give {A1, W},
    // with ZZ ==> Y give {W}.
    for (names.len..g.n) |l| if (anc[l]) {
        const nb = adj[l].items;
        for (nb, 0..) |p, k| for (nb[k + 1 ..]) |q| if (p < names.len and q < names.len) try link(a, adj, p, q);
    };
    for (adj) |*l| {
        var kept: std.ArrayList(usize) = .empty;
        for (l.items) |u| if (u < names.len) try kept.append(a, u);
        std.mem.sort(usize, kept.items, names, lessName);
        l.* = kept;
    }
    const vis = try a.alloc(bool, g.n);
    @memset(vis, false);
    vis[y] = true;
    vis[z] = true;
    const Walk = struct {
        a: A,
        gc: Graph,
        adj: []const std.ArrayList(usize),
        vis: []bool,
        w: []bool,
        observed: []const bool,
        x: usize,
        y: usize,
        z: usize,
        fn go(k: *@This(), v: usize) A.Error!bool {
            for (k.adj[v].items) |u| {
                if (k.vis[u]) continue;
                k.vis[u] = true;
                if (k.observed[u] and u != k.x) {
                    k.w[u] = true;
                    if (try k.gc.dSeparated(k.a, &.{k.z}, &.{k.y}, k.w)) return true;
                } else if (try k.go(u)) return true;
            }
            return false;
        }
    };
    var walk: Walk = .{ .a = a, .gc = gc, .adj = adj, .vis = vis, .w = w, .observed = observed, .x = x, .y = y, .z = z };
    if (!try walk.go(y)) return null;
    return if (try ivValid(a, g, x, y, z, w)) w else null;
}

const Step = enum { fwd, back, bi };
pub const PathRow = struct { text: []const u8, causal: bool, blocked: bool };

/// Proper paths (p.2320): from a treatment, never through another treatment,
/// each time an outcome is reached. Order of the SAS 9.4 reference runs:
/// treatments alphabetically, depth first with children, then parents, then
/// bidirected partners, each alphabetically, and the whole list reversed.
const PathWalk = struct {
    a: A,
    names: []const []const u8,
    xs: []const usize,
    ys: []const usize,
    z: []const bool,
    anc_z: []const bool,
    nbr: [3][]const []const usize,
    on: []bool,
    nodes: std.ArrayList(usize) = .empty,
    steps: std.ArrayList(Step) = .empty,
    rows: std.ArrayList(PathRow) = .empty,

    fn walk(w: *PathWalk, v: usize) A.Error!void {
        for ([_]Step{ .fwd, .back, .bi }, 0..) |st, kind| for (w.nbr[kind][v]) |u| {
            if (w.on[u] or contains(w.xs, u)) continue;
            w.on[u] = true;
            try w.nodes.append(w.a, u);
            try w.steps.append(w.a, st);
            if (contains(w.ys, u)) try w.emit();
            try w.walk(u);
            _ = w.nodes.pop();
            _ = w.steps.pop();
            w.on[u] = false;
        };
    }

    fn emit(w: *PathWalk) !void {
        var b: Out = .empty;
        var causal = true;
        var blocked = false;
        for (w.nodes.items, 0..) |v, k| {
            if (k > 0) {
                const st = w.steps.items[k - 1];
                if (st != .fwd) causal = false;
                try b.appendSlice(w.a, switch (st) {
                    .fwd => " ==> ",
                    .back => " <== ",
                    .bi => " <=> ",
                });
            }
            try b.appendSlice(w.a, w.names[v]);
            if (k == 0 or k + 1 == w.nodes.items.len) continue;
            const left = w.steps.items[k - 1] != .back;
            const right = w.steps.items[k] != .fwd;
            if (left and right) {
                if (!w.anc_z[v]) blocked = true;
            } else if (w.z[v]) blocked = true;
        }
        try w.rows.append(w.a, .{ .text = b.items, .causal = causal, .blocked = blocked });
    }
};

pub fn properPaths(a: A, names: []const []const u8, m: Model, xs: []const usize, ys: []const usize, z: []const bool) ![]PathRow {
    const n = names.len;
    var directed: std.ArrayList(Edge) = .empty;
    for (m.edges) |e| if (!e.bi) try directed.append(a, e);
    const g: Graph = .{ .n = n, .edges = directed.items };
    const none = try a.alloc(bool, n);
    @memset(none, false);
    var zs: std.ArrayList(usize) = .empty;
    for (z, 0..) |b, k| if (b) try zs.append(a, k);
    var nbr: [3][]const []const usize = undefined;
    for (0..3) |kind| {
        const lists = try a.alloc([]const usize, n);
        for (lists, 0..) |*l, v| {
            var xs_: std.ArrayList(usize) = .empty;
            for (m.edges) |e| {
                const u: ?usize = switch (kind) {
                    0 => if (!e.bi and e.from == v) e.to else null,
                    1 => if (!e.bi and e.to == v) e.from else null,
                    else => if (e.bi and e.from == v) e.to else if (e.bi and e.to == v) e.from else null,
                };
                if (u) |uu| if (!contains(xs_.items, uu)) try xs_.append(a, uu);
            }
            sortedIds(names, xs_.items);
            l.* = xs_.items;
        }
        nbr[kind] = lists;
    }
    var w: PathWalk = .{ .a = a, .names = names, .xs = xs, .ys = ys, .z = z, .anc_z = try g.closure(a, zs.items, false, none, none), .nbr = nbr, .on = try a.alloc(bool, n) };
    @memset(w.on, false);
    const tx = try a.dupe(usize, xs);
    sortedIds(names, tx);
    for (tx) |x| if (contains(m.nodes, x)) {
        w.on[x] = true;
        try w.nodes.append(a, x);
        try w.walk(x);
        _ = w.nodes.pop();
        w.on[x] = false;
    };
    std.mem.reverse(PathRow, w.rows.items);
    return w.rows.items;
}

/// Spanner widening of the SAS 9.4 reference runs: the spanned columns need
/// the text plus one dash on each side; one column widens, several widen
/// their gaps evenly.
fn widen(cols: []Col, gaps: []usize, from: usize, text: []const u8) void {
    const k = cols.len - from;
    if (k == 0) return;
    var natural: usize = 0;
    for (cols[from..], from..) |c, j| natural += c.width + (if (j > from) gaps[j] else 0);
    const need = text.len + 2;
    if (natural >= need) return;
    const extra = need - natural;
    if (k == 1) {
        cols[from].width += extra;
    } else {
        const per = (extra + k - 2) / (k - 1);
        for (gaps[from + 1 ..]) |*g| g.* += per;
    }
}

fn tableWidth(cols: []const Col, gaps: []const usize) usize {
    var width: usize = 0;
    for (cols, 0..) |c, k| width += c.width + (if (k > 0) gaps[k] else 0);
    return width;
}

fn centered(a: A, o: *Out, width: usize, text: []const u8) !void {
    try o.appendNTimes(a, ' ', (width + 1 -| text.len) / 2);
    try o.appendSlice(a, text);
    try o.append(a, '\n');
}

fn maxNameLen(names: []const []const u8) usize {
    var w: usize = 10;
    for (names) |nm| w = @max(w, nm.len);
    return w;
}

/// The tested set: TESTID variables plus the prescribed ones (p.2319).
fn testSet(a: A, s: Spec, t: Test) ![]usize {
    var set: std.ArrayList(usize) = .empty;
    for (t.vars) |v| try set.append(a, v);
    if (s.opts.method != .iv) for (s.adjust) |v| if (!contains(set.items, v)) try set.append(a, v);
    return set.items;
}

fn markColumns(a: A, s: Spec, cands: []const usize, set: []const usize) ![]usize {
    var used: std.ArrayList(usize) = .empty;
    for (cands, 0..) |c, k| if (!s.opts.compact or contains(set, c)) try used.append(a, k);
    return used.items;
}

fn starCols(a: A, s: Spec, cols: *std.ArrayList(Col), cands: []const usize, used: []const usize, rows: usize, set: []const usize) !void {
    for (used) |k| {
        const head = try splitHeader(a, s.names[cands[k]]);
        var w: usize = 1;
        for (head) |h| w = @max(w, h.len);
        const cells = try a.alloc([]const u8, rows);
        for (cells) |*c| c.* = if (contains(set, cands[k])) "*" else "";
        try cols.append(a, .{ .head = head, .al = .center, .width = w, .cells = cells });
    }
}

fn modelColumn(a: A, s: Spec) !Col {
    const labels = try a.alloc([]const u8, s.models.len);
    var lw: usize = 5;
    for (s.models, labels) |m, *l| {
        l.* = m.label;
        lw = @max(lw, m.label.len);
    }
    return .{ .head = &.{"Model"}, .al = .left, .width = lw, .cells = labels };
}

fn effectTitle(a: A, s: Spec) ![]const u8 {
    return std.fmt.allocPrint(a, "Causal Effect of {s} on {s}", .{ try roleList(a, s.names, s.treatments), try roleList(a, s.names, s.outcomes) });
}

/// AdjustTest (Table 37.2): one row per model.
fn adjustTestTable(cx: proc.ProcCtx, out: *Out, s: Spec, t: Test, cands: []const usize) !void {
    const a = cx.arena;
    const set = try testSet(a, s, t);
    const rows = s.models.len;
    const size = try a.alloc([]const u8, rows);
    const valid = try a.alloc([]const u8, rows);
    const mini = try a.alloc([]const u8, rows);
    for (s.models, 0..) |m, r| {
        const g = try expandLatent(a, s.names.len, m.edges);
        const an = try analyseMethod(a, g.n, g.edges, s.treatments, s.outcomes, s.opts.method);
        const z = try a.alloc(bool, g.n);
        @memset(z, false);
        var optional: std.ArrayList(usize) = .empty;
        var has_out = false;
        for (set) |v| {
            if (!contains(m.nodes, v)) {
                if (!contains(s.adjust, v)) has_out = true;
                continue;
            }
            z[v] = true;
            if (!contains(s.adjust, v)) try optional.append(a, v);
        }
        const ok = try validAdjustment(a, an, s.treatments, s.outcomes, z);
        // Minimal: no proper subset that keeps the prescribed variables is
        // valid (p.2301); dropping a variable absent from the model leaves
        // the same set, so such a set is never minimal (reference run).
        var minimal = ok and !has_out;
        if (minimal and optional.items.len > 0) {
            if (optional.items.len > max_candidates) return gap(cx, t.line, "a TESTID set of more than {d} variables is not implemented", .{max_candidates});
            const full = (@as(u64, 1) << @intCast(optional.items.len)) - 1;
            var mask: u64 = 0;
            while (mask < full) : (mask += 1) {
                for (optional.items, 0..) |v, k| z[v] = (mask >> @intCast(k)) & 1 == 1;
                if (try validAdjustment(a, an, s.treatments, s.outcomes, z)) {
                    minimal = false;
                    break;
                }
            }
        }
        size[r] = try num(a, set.len);
        valid[r] = if (ok) "Yes" else "No";
        mini[r] = if (minimal) "Yes" else "No";
    }
    var cols: std.ArrayList(Col) = .empty;
    try cols.append(a, try modelColumn(a, s));
    try cols.append(a, .{ .head = &.{"Size"}, .al = .right, .width = 8, .cells = size });
    try cols.append(a, .{ .head = &.{"Valid"}, .al = .left, .width = 8, .cells = valid });
    try cols.append(a, .{ .head = &.{"Minimal"}, .al = .left, .width = 8, .cells = mini });
    const used = try markColumns(a, s, cands, set);
    try starCols(a, s, &cols, cands, used, rows, set);
    const gaps = try uniformGaps(a, cols.items.len);
    widen(cols.items, gaps, 4, "Covariates");
    // Reference runs: the two titles are separated by a blank line.
    const width = tableWidth(cols.items, gaps);
    try centered(a, out, width, try std.fmt.allocPrint(a, "Covariate Adjustment Test: {s}", .{t.label}));
    try out.appendSlice(a, " \n");
    try centered(a, out, width, try effectTitle(a, s));
    try table(a, out, &.{}, 1, cols.items, gaps, if (used.len > 0) Spanner{ .from = 4, .text = "Covariates" } else null);
}

/// InstrumentTest (Table 37.2): one row per model.
fn ivTestTable(cx: proc.ProcCtx, out: *Out, s: Spec, t: Test, cands: []const usize) !void {
    const a = cx.arena;
    const rows = s.models.len;
    const z = t.vars[0];
    const inst = try a.alloc([]const u8, rows);
    const valid = try a.alloc([]const u8, rows);
    for (s.models, 0..) |m, r| {
        if (!contains(m.nodes, z)) return gap(cx, t.line, "a TESTID instrument missing from a model is not implemented", .{});
        const g = try expandLatent(a, s.names.len, m.edges);
        const w = try a.alloc(bool, g.n);
        @memset(w, false);
        for (t.cond) |c| if (contains(m.nodes, c)) {
            w[c] = true;
        };
        inst[r] = s.names[z];
        valid[r] = if (try ivValid(a, .{ .n = g.n, .edges = g.edges }, s.treatments[0], s.outcomes[0], z, w)) "Yes" else "No";
    }
    var cols: std.ArrayList(Col) = .empty;
    try cols.append(a, try modelColumn(a, s));
    try cols.append(a, .{ .head = &.{"Instrument"}, .al = .left, .width = maxNameLen(s.names), .cells = inst });
    try cols.append(a, .{ .head = &.{"Valid"}, .al = .left, .width = 8, .cells = valid });
    const used = try markColumns(a, s, cands, t.cond);
    try starCols(a, s, &cols, cands, used, rows, t.cond);
    const gaps = try uniformGaps(a, cols.items.len);
    widen(cols.items, gaps, 3, "Conditionals");
    const t1 = try std.fmt.allocPrint(a, "Instrumental Variable Test: {s}", .{t.label});
    try table(a, out, &.{ t1, try effectTitle(a, s) }, 1, cols.items, gaps, if (used.len > 0) Spanner{ .from = 3, .text = "Conditionals" } else null);
}

pub const IvRow = struct { z: usize, w: []const bool };

fn ivList(a: A, s: Spec, m: Model, cands: []const usize) ![]IvRow {
    const g = try expandLatent(a, s.names.len, m.edges);
    const observed = try a.alloc(bool, g.n);
    @memset(observed, false);
    for (m.nodes) |v| observed[v] = !contains(s.unmeasured, v);
    var rows: std.ArrayList(IvRow) = .empty;
    for (cands) |c| if (contains(m.nodes, c)) {
        if (try ivFind(a, .{ .n = g.n, .edges = g.edges }, s.names, observed, s.treatments[0], s.outcomes[0], c)) |w| try rows.append(a, .{ .z = c, .w = w });
    };
    return rows.items;
}

/// InstrumentList (Table 37.2) or the SAS 9.4 no-instrument line.
fn ivListTable(cx: proc.ProcCtx, out: *Out, s: Spec, m: Model, cands: []const usize) !void {
    const a = cx.arena;
    var rows = try ivList(a, s, m, cands);
    if (s.opts.maxlist) |ml| if (rows.len > ml) {
        rows = rows[0..ml];
    };
    if (rows.len == 0) {
        try out.appendSlice(a, try std.fmt.allocPrint(a, "There are no instrumental variables for {s}.\n\n", .{m.label}));
        return;
    }
    var used: std.ArrayList(usize) = .empty;
    for (cands, 0..) |c, k| {
        var any = !s.opts.compact;
        for (rows) |r| {
            if (r.w[c]) any = true;
        }
        if (any) try used.append(a, k);
    }
    const obs = try a.alloc([]const u8, rows.len);
    const inst = try a.alloc([]const u8, rows.len);
    for (rows, 0..) |r, k| {
        obs[k] = try num(a, k + 1);
        inst[k] = s.names[r.z];
    }
    var cols: std.ArrayList(Col) = .empty;
    try cols.append(a, .{ .head = &.{""}, .al = .right, .width = 8, .cells = obs });
    try cols.append(a, .{ .head = &.{"Instrument"}, .al = .left, .width = maxNameLen(s.names), .cells = inst });
    for (used.items) |k| {
        const head = try splitHeader(a, s.names[cands[k]]);
        var w: usize = 1;
        for (head) |h| w = @max(w, h.len);
        const cells = try a.alloc([]const u8, rows.len);
        for (rows, cells) |r, *cell| cell.* = if (r.w[cands[k]]) "*" else "";
        try cols.append(a, .{ .head = head, .al = .center, .width = w, .cells = cells });
    }
    const gaps = try uniformGaps(a, cols.items.len);
    widen(cols.items, gaps, 2, "Conditionals");
    const t1 = try std.fmt.allocPrint(a, "Instrumental Variables for {s}", .{m.label});
    try table(a, out, &.{ t1, try effectTitle(a, s) }, 1, cols.items, gaps, if (used.items.len > 0) Spanner{ .from = 2, .text = "Conditionals" } else null);
}

/// Paths (Table 37.2, PATHS option): one table per model.
fn pathsTable(cx: proc.ProcCtx, out: *Out, s: Spec, t: Test, m: Model) !void {
    const a = cx.arena;
    const set = try testSet(a, s, t);
    const z = try a.alloc(bool, s.names.len);
    @memset(z, false);
    for (set) |v| if (contains(m.nodes, v)) {
        z[v] = true;
    };
    const g = try expandLatent(a, s.names.len, m.edges);
    const an = try analyseMethod(a, g.n, g.edges, s.treatments, s.outcomes, s.opts.method);
    var overcontrol = false;
    for (set) |v| if (contains(m.nodes, v)) {
        // Over-control footnote: METHOD=ADJUSTMENT only (reference runs: a
        // BACKDOOR set with M on X ==> M ==> Y prints none).
        if (an.forbidden[v] and an.backdoor == null) overcontrol = true;
    };
    const f = t.paths.?;
    var shown: std.ArrayList(PathRow) = .empty;
    for (try properPaths(a, s.names, m, s.treatments, s.outcomes, z)) |p| {
        if (f.causal and !p.causal) continue;
        if (f.noncausal and p.causal) continue;
        if (f.blocked and !p.blocked) continue;
        if (f.nonblocked and p.blocked) continue;
        try shown.append(a, p);
    }
    if (shown.items.len == 0) {
        try out.appendSlice(a, try std.fmt.allocPrint(a, "NOTE: There are no paths satisfying the specified criteria for test {s} applied to model {s}.\n\n", .{ t.label, m.label }));
        return;
    }
    const rows = shown.items.len;
    const obs = try a.alloc([]const u8, rows);
    const flag = try a.alloc([]const u8, rows);
    const causal = try a.alloc([]const u8, rows);
    const blocked = try a.alloc([]const u8, rows);
    const text = try a.alloc([]const u8, rows);
    var pw: usize = 5;
    var biasing = false;
    for (shown.items, 0..) |p, r| {
        obs[r] = try num(a, r + 1);
        // A blocked causal path is starred as biasing under both methods
        // (reference runs).
        const bias = p.causal == p.blocked;
        if (bias) biasing = true;
        flag[r] = if (bias) "*" else "";
        causal[r] = if (p.causal) "Yes" else "No";
        blocked[r] = if (p.blocked) "Yes" else "No";
        text[r] = p.text;
        pw = @max(pw, p.text.len);
    }
    const cols = [_]Col{
        .{ .head = &.{""}, .al = .right, .width = 8, .cells = obs },
        .{ .head = &.{""}, .al = .left, .width = 1, .cells = flag },
        .{ .head = &.{"Causal"}, .al = .left, .width = 8, .cells = causal },
        .{ .head = &.{"Blocked"}, .al = .left, .width = 8, .cells = blocked },
        .{ .head = &.{"Paths"}, .al = .left, .width = pw, .cells = text },
    };
    const gaps = [_]usize{ 0, 0, 4, 4, 4 };
    const adj_text = if (set.len == 0) "" else try roleList(a, s.names, set);
    const t3 = try std.fmt.allocPrint(a, "{s} Adjusted for {s}", .{ try effectTitle(a, s), adj_text });
    const t2 = try std.fmt.allocPrint(a, "Test {s} for Model {s}", .{ t.label, m.label });
    try table(a, out, &.{ "Treatment-to-Outcome Paths", t2, t3 }, 1, &cols, &gaps, null);
    if (overcontrol or biasing) {
        const width = tableWidth(&cols, &gaps);
        try out.append(a, '\n');
        if (overcontrol) {
            try centered(a, out, width, "At least one variable in the adjustment set");
            try centered(a, out, width, "lies on or descends from a causal path.");
        }
        if (biasing) try centered(a, out, width, "* indicates a biasing path");
    }
}

/// TESTID output (SAS 9.4 reference runs): consecutive tests share a page;
/// a test with PATHS starts a page and is followed by a page of path tables,
/// one per model.
fn emitTests(cx: proc.ProcCtx, out: *Out, s: Spec, cands: []const usize, open: *bool) !void {
    const iv = s.opts.method == .iv;
    var fresh = true;
    for (s.tests) |t| {
        // A test with PATHS starts a page; one without continues the page
        // of the previous test or its paths (reference runs).
        if (fresh or t.paths != null) {
            if (open.*) try endPage(cx, out);
            try page(cx, out);
            open.* = true;
        } else try out.appendSlice(cx.arena, "\n\n");
        fresh = false;
        if (iv) {
            try ivTestTable(cx, out, s, t, cands);
            continue;
        }
        try adjustTestTable(cx, out, s, t, cands);
        if (t.paths == null) continue;
        try endPage(cx, out);
        try page(cx, out);
        for (s.models, 0..) |m, k| {
            if (k > 0) try out.appendSlice(cx.arena, "\n\n");
            try pathsTable(cx, out, s, t, m);
        }
    }
}

// ── tests ──────────────────────────────────────────────────────────────────

test "STAT-CAUSALGRAPH-001 adjustment sets of the Getting Started model (p.2297)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 Age 1 Parity 2 PFAS 3 Education 4 PrevBF 5 Duration 6 Employment
    // 7 BMI 8 Alcohol 9 Smoking
    const E = Edge;
    const edges = [_]Edge{
        E{ .from = 0, .to = 1 }, E{ .from = 0, .to = 2 }, E{ .from = 0, .to = 3 },
        E{ .from = 1, .to = 4 }, E{ .from = 1, .to = 5 }, E{ .from = 1, .to = 2 },
        E{ .from = 4, .to = 2 }, E{ .from = 4, .to = 5 }, E{ .from = 2, .to = 5 },
        E{ .from = 3, .to = 5 }, E{ .from = 3, .to = 6 }, E{ .from = 3, .to = 2 },
        E{ .from = 3, .to = 7 }, E{ .from = 3, .to = 8 }, E{ .from = 3, .to = 9 },
        E{ .from = 6, .to = 5 }, E{ .from = 6, .to = 2 }, E{ .from = 6, .to = 7 },
        E{ .from = 6, .to = 8 }, E{ .from = 6, .to = 9 }, E{ .from = 7, .to = 5 },
        E{ .from = 8, .to = 5 }, E{ .from = 9, .to = 5 },
    };
    const an = try analyse(a, 10, &edges, &.{2}, &.{5});
    // Alphabetical candidates: Age BMI Education Employment Parity PrevBF.
    const cands = [_]usize{ 0, 7, 3, 6, 1, 4 };
    const sets = try enumerate(a, 10, an, &cands, &.{2}, &.{5}, 0);
    try std.testing.expectEqual(@as(usize, 4), sets.len);
    const want = [_]u64{ 0b111100, 0b111101, 0b111110, 0b111111 };
    for (sets, want) |st, w| try std.testing.expectEqual(w, st.mask);
    try std.testing.expect(sets[0].minimal and !sets[1].minimal and !sets[3].minimal);
}

test "STAT-CAUSALGRAPH-001 d-separation: chain, fork and collider" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 -> 1 -> 2 ; 0 <- 3 -> 2 ; 0 -> 4 <- 2
    const g: Graph = .{ .n = 5, .edges = &.{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 } } };
    try std.testing.expect(!try g.dSeparated(a, &.{0}, &.{2}, &.{ false, false, false, false, false }));
    try std.testing.expect(try g.dSeparated(a, &.{0}, &.{2}, &.{ false, true, false, false, false }));
    const c: Graph = .{ .n = 5, .edges = &.{ .{ .from = 0, .to = 4 }, .{ .from = 2, .to = 4 } } };
    try std.testing.expect(try c.dSeparated(a, &.{0}, &.{2}, &.{ false, false, false, false, false }));
    try std.testing.expect(!try c.dSeparated(a, &.{0}, &.{2}, &.{ false, false, false, false, true }));
}

test "STAT-CAUSALGRAPH-001 arrow spellings (p.2316)" {
    try std.testing.expectEqual(Arrow.right, arrowKind("==>").?);
    try std.testing.expectEqual(Arrow.right, arrowKind("-->").?);
    try std.testing.expectEqual(Arrow.left, arrowKind("<===").?);
    try std.testing.expectEqual(Arrow.both, arrowKind("<->").?);
    try std.testing.expect(arrowKind("=") == null);
    try std.testing.expect(arrowKind("<=>>") == null);
}

fn testSets(a: A, n: usize, edges: []const Edge, cands: []const usize, x: usize, y: usize) ![]Set {
    const g = try expandLatent(a, n, edges);
    const an = try analyse(a, g.n, g.edges, &.{x}, &.{y});
    return enumerate(a, g.n, an, cands, &.{x}, &.{y}, 0);
}

test "STAT-CAUSALGRAPH-003 bidirected edges as latent common parents (p.2306)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 X, 1 Y, 2 Z. Z -> X -> Y, Z -> Y.
    const base = [_]Edge{ .{ .from = 2, .to = 0 }, .{ .from = 0, .to = 1 }, .{ .from = 2, .to = 1 } };
    // X <-> Z: {Z} blocks X<->Z->Y and X<-Z->Y; {} does not.
    const c1 = base ++ [_]Edge{.{ .from = 0, .to = 2, .bi = true }};
    const s1 = try testSets(a, 3, &c1, &.{2}, 0, 1);
    try std.testing.expectEqual(@as(usize, 1), s1.len);
    try std.testing.expectEqual(@as(u64, 1), s1[0].mask);
    // X <-> Y: no set blocks the latent path (not identified by adjustment).
    const c2 = base ++ [_]Edge{.{ .from = 0, .to = 1, .bi = true }};
    try std.testing.expectEqual(@as(usize, 0), (try testSets(a, 3, &c2, &.{2}, 0, 1)).len);
    // M-bias X <-> M <-> Y, X -> Y: only {} (M is a collider).
    const c6 = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 0, .to = 2, .bi = true }, .{ .from = 2, .to = 1, .bi = true } };
    const s6 = try testSets(a, 3, &c6, &.{2}, 0, 1);
    try std.testing.expectEqual(@as(usize, 1), s6.len);
    try std.testing.expectEqual(@as(u64, 0), s6[0].mask);
    // W -> X -> Y, W -> Y, W <-> Y, X <-> W: W opens X<->W<->Y, {} leaves X<-W->Y.
    const c8 = base ++ [_]Edge{ .{ .from = 2, .to = 1, .bi = true }, .{ .from = 0, .to = 2, .bi = true } };
    try std.testing.expectEqual(@as(usize, 0), (try testSets(a, 3, &c8, &.{2}, 0, 1)).len);
}

test "STAT-CAUSALGRAPH-003 bidirected edges make no directed cycle and do connect" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const e = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 0, .bi = true }, .{ .from = 2, .to = 1, .bi = true } };
    try std.testing.expect(!try hasCycle(a, 3, &e));
    try std.testing.expectEqual(@as(usize, 1), try components(a, 3, .{ .label = "M", .line = 0, .nodes = &.{ 0, 1, 2 }, .edges = &e }));
    const g = try expandLatent(a, 3, &e);
    try std.testing.expectEqual(@as(usize, 5), g.n);
    try std.testing.expectEqual(@as(usize, 5), g.edges.len);
}

test "STAT-CAUSALGRAPH-003 components numbered by their alphabetically first node" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // X ==> Y, Z ==> X Y, A ==> B (E4 of the reference run): {A,B} is 1.
    const names = [_][]const u8{ "X", "Y", "Z", "A", "B" };
    const e = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 2, .to = 0 }, .{ .from = 2, .to = 1 }, .{ .from = 3, .to = 4 } };
    const cc = try componentIds(a, &names, .{ .label = "E4", .line = 0, .nodes = &.{ 0, 1, 2, 3, 4 }, .edges = &e });
    try std.testing.expectEqual(@as(usize, 2), cc.count);
    try std.testing.expectEqual(@as(usize, 0), cc.ids[3]);
    try std.testing.expectEqual(@as(usize, 1), cc.ids[0]);
    try std.testing.expectEqual(@as(usize, 1), cc.ids[2]);
}

test "STAT-CAUSALGRAPH-002 hand-derived adjustment sets: descendant of the treatment off the causal path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 Z 1 X 2 Y 3 M 4 W 5 D: Z->X, Z->Y, X->M, M->Y, W->Y, X->D.
    // Forbidden De({M,Y}) = {M,Y}; Z blocks X <- Z -> Y; D and W free.
    const edges = [_]Edge{
        .{ .from = 0, .to = 1 }, .{ .from = 0, .to = 2 }, .{ .from = 1, .to = 3 },
        .{ .from = 3, .to = 2 }, .{ .from = 4, .to = 2 }, .{ .from = 1, .to = 5 },
    };
    const an = try analyse(a, 6, &edges, &.{1}, &.{2});
    // Alphabetical candidates: D M W Z (bits 0..3).
    const cands = [_]usize{ 5, 3, 4, 0 };
    const sets = try enumerate(a, 6, an, &cands, &.{1}, &.{2}, 0);
    const want = [_]u64{ 0b1000, 0b1001, 0b1100, 0b1101 };
    try std.testing.expectEqual(want.len, sets.len);
    for (sets, want) |st, w| try std.testing.expectEqual(w, st.mask);
    try std.testing.expect(sets[0].minimal and !sets[1].minimal and !sets[2].minimal and !sets[3].minimal);
    // Prescribed W (bit 2): {W,Z} minimal among the sets containing W.
    const pres = try enumerate(a, 6, an, &cands, &.{1}, &.{2}, 0b0100);
    try std.testing.expectEqual(@as(usize, 2), pres.len);
    try std.testing.expectEqual(@as(u64, 0b1100), pres[0].mask);
    try std.testing.expectEqual(@as(u64, 0b1101), pres[1].mask);
    try std.testing.expect(pres[0].minimal and !pres[1].minimal);
}

test "STAT-CAUSALGRAPH-004 hand-derived joint-effect adjustment sets (pp.2303, 2317)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Sequential treatments: 0 X1, 1 L, 2 X2, 3 Y, 4 U; X1 -> L -> X2 -> Y,
    // X1 -> Y, U -> L, U -> Y. PCP = {Y} (L reaches Y only through X2), so
    // L is not forbidden. X2 <- L <- U -> Y needs L or U; conditioning on L
    // opens the collider X1 -> L <- U -> Y unless U is adjusted too: the
    // sets over cands {L, U} are {U} (minimal) and {L,U}; with U unmeasured
    // (cands {L}) there is none.
    const seq = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 }, .{ .from = 2, .to = 3 }, .{ .from = 0, .to = 3 }, .{ .from = 4, .to = 1 }, .{ .from = 4, .to = 3 } };
    const an = try analyse(a, 5, &seq, &.{ 0, 2 }, &.{3});
    const s1 = try enumerate(a, 5, an, &.{ 1, 4 }, &.{ 0, 2 }, &.{3}, 0);
    try std.testing.expectEqual(@as(usize, 2), s1.len);
    try std.testing.expectEqual(@as(u64, 0b10), s1[0].mask);
    try std.testing.expect(s1[0].minimal);
    try std.testing.expectEqual(@as(u64, 0b11), s1[1].mask);
    try std.testing.expect(!s1[1].minimal);
    try std.testing.expectEqual(@as(usize, 0), (try enumerate(a, 5, an, &.{1}, &.{ 0, 2 }, &.{3}, 0)).len);
    // Several outcomes (p.2317): 0 X, 1 Y1, 2 Y2, 3 Z1, 4 W, 5 V with
    // W -> X Z1, Z1 -> Y1, V -> Z1 Y2, X -> Y1 Y2 (W, V latent). X on Y1
    // needs Z1; Z1 opens X <- W -> Z1 <- V -> Y2 for Y2, so no set is valid
    // for {Y1, Y2} although each outcome alone is identified.
    const mo = [_]Edge{ .{ .from = 4, .to = 0 }, .{ .from = 4, .to = 3 }, .{ .from = 3, .to = 1 }, .{ .from = 5, .to = 3 }, .{ .from = 5, .to = 2 }, .{ .from = 0, .to = 1 }, .{ .from = 0, .to = 2 } };
    const both = try analyse(a, 6, &mo, &.{0}, &.{ 1, 2 });
    try std.testing.expectEqual(@as(usize, 0), (try enumerate(a, 6, both, &.{3}, &.{0}, &.{ 1, 2 }, 0)).len);
    const y1 = try enumerate(a, 6, try analyse(a, 6, &mo, &.{0}, &.{1}), &.{3}, &.{0}, &.{1}, 0);
    try std.testing.expectEqual(@as(usize, 1), y1.len);
    try std.testing.expectEqual(@as(u64, 1), y1[0].mask);
    const y2 = try enumerate(a, 6, try analyse(a, 6, &mo, &.{0}, &.{2}), &.{3}, &.{0}, &.{2}, 0);
    try std.testing.expectEqual(@as(usize, 1), y2.len);
    try std.testing.expectEqual(@as(u64, 0), y2[0].mask);
    // Title lists: one name as written, several in braces, alphabetical.
    const names = [_][]const u8{ "B", "A", "Q" };
    try std.testing.expectEqualStrings("B", try roleList(a, &names, &.{0}));
    try std.testing.expectEqualStrings("{A B}", try roleList(a, &names, &.{ 0, 1 }));
}

test "STAT-CAUSALGRAPH-005 hand-derived instruments, backdoor sets and proper paths" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 Z1 1 X 2 Y 3 Z2 4 U 5 C 6 Z3 7 E: Z1 -> X -> Y, Z2 -> X, U -> X Y,
    // C -> Z2 Y, Z3 -> C X, E -> Y; U unmeasured. Z1 is a classical
    // instrument; Z2 <- C -> Y is open until C is conditioned on; E -> Y.
    const names = [_][]const u8{ "Z1", "X", "Y", "Z2", "U", "C", "Z3", "E" };
    const e = [_]Edge{
        .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 }, .{ .from = 3, .to = 1 }, .{ .from = 4, .to = 1 }, .{ .from = 4, .to = 2 },
        .{ .from = 5, .to = 3 }, .{ .from = 5, .to = 2 }, .{ .from = 6, .to = 5 }, .{ .from = 6, .to = 1 }, .{ .from = 7, .to = 2 },
    };
    const g: Graph = .{ .n = 8, .edges = &e };
    var w = [_]bool{false} ** 8;
    try std.testing.expect(try ivValid(a, g, 1, 2, 0, &w));
    try std.testing.expect(!try ivValid(a, g, 1, 2, 3, &w));
    w[5] = true;
    try std.testing.expect(try ivValid(a, g, 1, 2, 3, &w));
    // Conditioning on the outcome's descendant or the instrument is invalid.
    try std.testing.expect(!try ivValid(a, g, 1, 2, 5, &w));
    const obs = [_]bool{ true, true, true, true, false, true, true, true };
    const found = (try ivFind(a, g, &names, &obs, 1, 2, 3)).?;
    for (found, 0..) |b, k| try std.testing.expectEqual(k == 5, b);
    try std.testing.expect((try ivFind(a, g, &names, &obs, 1, 2, 7)) == null);
    // 0 C 1 X 2 M 3 Y 4 D: C -> X -> M -> Y, C -> Y, X -> D, X -> Y. {C, D}
    // is a valid adjustment set (D descends from X off the causal path) but
    // not a backdoor set (no descendant of X); {C} is both.
    const p = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 }, .{ .from = 2, .to = 3 }, .{ .from = 0, .to = 3 }, .{ .from = 1, .to = 4 }, .{ .from = 1, .to = 3 } };
    const cd = [_]bool{ true, false, false, false, true };
    const c = [_]bool{ true, false, false, false, false };
    try std.testing.expect(try validAdjustment(a, try analyseMethod(a, 5, &p, &.{1}, &.{3}, .adjustment), &.{1}, &.{3}, &cd));
    const bd = try analyseMethod(a, 5, &p, &.{1}, &.{3}, .backdoor);
    try std.testing.expect(!try validAdjustment(a, bd, &.{1}, &.{3}, &cd));
    try std.testing.expect(try validAdjustment(a, bd, &.{1}, &.{3}, &c));
    // Proper paths given {C}: the back-door path is blocked at the fork C.
    const pn = [_][]const u8{ "C", "X", "M", "Y", "D" };
    const rows = try properPaths(a, &pn, .{ .label = "P", .line = 0, .nodes = &.{ 0, 1, 2, 3, 4 }, .edges = &p }, &.{1}, &.{3}, &c);
    try std.testing.expectEqual(@as(usize, 3), rows.len);
    try std.testing.expectEqualStrings("X <== C ==> Y", rows[0].text);
    try std.testing.expect(!rows[0].causal and rows[0].blocked);
    try std.testing.expectEqualStrings("X ==> Y", rows[1].text);
    try std.testing.expectEqualStrings("X ==> M ==> Y", rows[2].text);
    try std.testing.expect(rows[2].causal and !rows[2].blocked);
    // A conditioned collider opens a noncausal path: X -> K <- Y given K.
    const k = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 0, .to = 2 }, .{ .from = 1, .to = 2 } };
    const kr = try properPaths(a, &.{ "X", "Y", "K" }, .{ .label = "K", .line = 0, .nodes = &.{ 0, 1, 2 }, .edges = &k }, &.{0}, &.{1}, &.{ false, false, true });
    try std.testing.expectEqual(@as(usize, 2), kr.len);
    try std.testing.expectEqualStrings("X ==> Y", kr[0].text);
    try std.testing.expectEqualStrings("X ==> K <== Y", kr[1].text);
    try std.testing.expect(!kr[1].causal and !kr[1].blocked);
}

test "STAT-CAUSALGRAPH-009 DirectedCycles walk follows the SAS reference runs (p.2329)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // Reference model 'A' B ==> C ==> A ==> B prints A B C A; model 'Two'
    // A ==> C ==> A, A ==> B ==> A prints A B A; model 'U' X ==> U ==> Y
    // ==> X prints U Y X U; a DAG has no cycle.
    const names = [_][]const u8{ "B", "C", "A", "X", "U", "Y" };
    const m1: Model = .{ .label = "A", .line = 1, .nodes = &.{ 0, 1, 2 }, .edges = &.{ .{ .from = 0, .to = 1 }, .{ .from = 1, .to = 2 }, .{ .from = 2, .to = 0 } } };
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 1, 2 }, (try firstCycle(a, &names, m1)).?);
    const m2: Model = .{ .label = "Two", .line = 1, .nodes = &.{ 2, 1, 0 }, .edges = &.{ .{ .from = 2, .to = 1 }, .{ .from = 1, .to = 2 }, .{ .from = 2, .to = 0 }, .{ .from = 0, .to = 2 } } };
    try std.testing.expectEqualSlices(usize, &.{ 2, 0, 2 }, (try firstCycle(a, &names, m2)).?);
    const m3: Model = .{ .label = "U", .line = 1, .nodes = &.{ 3, 4, 5 }, .edges = &.{ .{ .from = 3, .to = 4 }, .{ .from = 4, .to = 5 }, .{ .from = 5, .to = 3 } } };
    try std.testing.expectEqualSlices(usize, &.{ 4, 5, 3, 4 }, (try firstCycle(a, &names, m3)).?);
    // A bidirected edge never closes a directed cycle (p.2316).
    const m4: Model = .{ .label = "D", .line = 1, .nodes = &.{ 3, 5 }, .edges = &.{ .{ .from = 3, .to = 5 }, .{ .from = 5, .to = 3, .bi = true } } };
    try std.testing.expect(try firstCycle(a, &names, m4) == null);
}

test "STAT-CAUSALGRAPH-009 adding an edge never makes an adjustment set appear (p.2330)" {
    // p.2330: adding edges to an existing set of variables never helps
    // identification. Exhaustive check over every DAG on 0 X, 1 Y, 2 Z
    // (measured) and 3 U (unmeasured) for all 24 topological orders, and on
    // five nodes (Z1, Z2 measured, U latent) for one order: whenever G plus
    // one edge has an adjustment set, G has one too.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Helper = struct {
        fn identified(al: A, n: usize, order: []const usize, mask: u32, cands: []const usize) !bool {
            var edges: std.ArrayList(Edge) = .empty;
            var bit: u5 = 0;
            for (0..n) |i| for (i + 1..n) |j| {
                if ((mask >> bit) & 1 == 1) try edges.append(al, .{ .from = order[i], .to = order[j] });
                bit += 1;
            };
            const an = try analyse(al, n, edges.items, &.{0}, &.{1});
            return (try enumerate(al, n, an, cands, &.{0}, &.{1}, 0)).len > 0;
        }
    };
    var checked: usize = 0;
    var orders: std.ArrayList([4]usize) = .empty;
    for (0..4) |p0| for (0..4) |p1| for (0..4) |p2| for (0..4) |p3| {
        const p = [4]usize{ p0, p1, p2, p3 };
        var used = [_]bool{false} ** 4;
        var ok = true;
        for (p) |v| {
            if (used[v]) ok = false;
            used[v] = true;
        }
        if (ok) try orders.append(a, p);
    };
    for (orders.items) |order| {
        for (0..64) |g| {
            const base = try Helper.identified(a, 4, &order, @intCast(g), &.{2});
            for (0..6) |b| {
                if ((g >> @intCast(b)) & 1 == 1) continue;
                const more = try Helper.identified(a, 4, &order, @intCast(g | (@as(usize, 1) << @intCast(b))), &.{2});
                try std.testing.expect(!more or base);
                checked += 1;
            }
        }
    }
    const order5 = [_]usize{ 4, 2, 0, 3, 1 };
    for (0..1024) |g| {
        const base = try Helper.identified(a, 5, &order5, @intCast(g), &.{ 2, 3 });
        for (0..10) |b| {
            if ((g >> @intCast(b)) & 1 == 1) continue;
            const more = try Helper.identified(a, 5, &order5, @intCast(g | (@as(usize, 1) << @intCast(b))), &.{ 2, 3 });
            try std.testing.expect(!more or base);
            checked += 1;
        }
    }
    try std.testing.expect(checked > 9000);
}

test "STAT-CAUSALGRAPH-008 pruned search equals the exhaustive enumeration" {
    // Time Requirements (p.2330): the polynomial-delay listing must return
    // exactly the sets of the exhaustive subset scan, with the same minimal
    // flags, and the direct search must find a set iff one exists. 3000
    // random DAGs on 7 nodes (one possibly latent node, random prescribed
    // variables), both METHOD=ADJUSTMENT and METHOD=BACKDOOR.
    var prng = std.Random.DefaultPrng.init(0x5a5008);
    const r = prng.random();
    var checked_sets: usize = 0;
    for (0..3000) |_| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const n = 7;
        var perm: [n]usize = .{ 0, 1, 2, 3, 4, 5, 6 };
        r.shuffle(usize, &perm);
        var edges: std.ArrayList(Edge) = .empty;
        for (0..n) |i| for (i + 1..n) |j| if (r.uintLessThan(u8, 100) < 35) try edges.append(a, .{ .from = perm[i], .to = perm[j] });
        const x: usize = 0;
        const y: usize = 1;
        const latent: ?usize = if (r.boolean()) 2 else null;
        var cands: std.ArrayList(usize) = .empty;
        for (2..n) |v| if (latent == null or v != latent.?) try cands.append(a, v);
        var required: u64 = 0;
        if (r.uintLessThan(u8, 4) == 0) required = @as(u64, 1) << @intCast(r.uintLessThan(usize, cands.items.len));
        for ([_]Method{ .adjustment, .backdoor }) |method| {
            const an = try analyseMethod(a, n, edges.items, &.{x}, &.{y}, method);
            // The exhaustive scan does not exclude forbidden prescribed
            // variables up front; validate() rejects those before listing.
            var forb_req = false;
            for (cands.items, 0..) |c, k| if ((required >> @intCast(k)) & 1 == 1) {
                if (if (an.backdoor) |bd| bd.de_x[c] else an.forbidden[c]) forb_req = true;
            };
            const ex = try enumerate(a, n, an, cands.items, &.{x}, &.{y}, required);
            var se = try Search.init(a, n, edges.items, an, cands.items, &.{x}, &.{y}, required);
            const got = try se.list();
            std.mem.sort(Set, got, {}, setLess);
            if (forb_req) {
                try std.testing.expectEqual(@as(usize, 0), got.len);
                continue;
            }
            try std.testing.expectEqual(ex.len, got.len);
            for (ex, got) |e, g| {
                try std.testing.expectEqual(e.mask, g.mask);
                try std.testing.expectEqual(e.minimal, g.minimal);
            }
            const d = try se.direct();
            try std.testing.expectEqual(ex.len > 0, d != null);
            if (d) |st| {
                // The direct set is valid and contains every listed set's
                // ancestral part: it is the largest valid ancestral set.
                var found = false;
                for (ex) |e| if (e.mask == st.mask) {
                    found = true;
                    try std.testing.expectEqual(e.minimal, st.minimal);
                };
                try std.testing.expect(found);
            }
            checked_sets += ex.len;
        }
    }
    try std.testing.expect(checked_sets > 1000);
}

test "STAT-CAUSALGRAPH-008 NOSORT order and MAXLIST= truncation (SAS reference runs)" {
    // Graph M3 of the reference run (X -> Y; A -> X, B; B -> Y; C -> X, D;
    // D -> Y; E -> X, F; F -> Y): 27 sets, 8 minimal. NOSORT lists in
    // exclusion-first order (BDF, BDE, BDEF, ...); MAXLIST=3 keeps the last
    // three (ABCDF, ABCDE, ABCDEF); MINIMAL lists in inclusion-first order.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // 0 X, 1 Y, 2 A, 3 B, 4 C, 5 D, 6 E, 7 F
    const e = [_]Edge{ .{ .from = 0, .to = 1 }, .{ .from = 2, .to = 0 }, .{ .from = 2, .to = 3 }, .{ .from = 3, .to = 1 }, .{ .from = 4, .to = 0 }, .{ .from = 4, .to = 5 }, .{ .from = 5, .to = 1 }, .{ .from = 6, .to = 0 }, .{ .from = 6, .to = 7 }, .{ .from = 7, .to = 1 } };
    const cands = [_]usize{ 2, 3, 4, 5, 6, 7 };
    const an = try analyse(a, 8, &e, &.{0}, &.{1});
    var se = try Search.init(a, 8, &e, an, &cands, &.{0}, &.{1}, 0);
    const all = try se.list();
    try std.testing.expectEqual(@as(usize, 27), all.len);
    var shown: std.ArrayList(Set) = .empty;
    try nosortList(a, &shown, .{ .nosort = true, .maxlist = null }, all, null);
    // bits: A=1, B=2, C=4, D=8, E=16, F=32
    try std.testing.expectEqual(@as(u64, 2 | 8 | 32), shown.items[0].mask);
    try std.testing.expectEqual(@as(u64, 2 | 8 | 16), shown.items[1].mask);
    try std.testing.expectEqual(@as(u64, 63), shown.items[26].mask);
    var se3 = try Search.init(a, 8, &e, an, &cands, &.{0}, &.{1}, 0);
    se3.limit = 3;
    const first3 = try se3.list();
    shown.clearRetainingCapacity();
    try nosortList(a, &shown, .{ .nosort = true, .maxlist = 3 }, first3, null);
    try std.testing.expectEqual(@as(u64, 1 | 2 | 4 | 8 | 32), shown.items[0].mask);
    try std.testing.expectEqual(@as(u64, 1 | 2 | 4 | 8 | 16), shown.items[1].mask);
    try std.testing.expectEqual(@as(u64, 63), shown.items[2].mask);
    shown.clearRetainingCapacity();
    try nosortList(a, &shown, .{ .nosort = true, .minimal = true, .maxlist = null }, all, null);
    try std.testing.expectEqual(@as(usize, 8), shown.items.len);
    try std.testing.expectEqual(@as(u64, 1 | 4 | 16), shown.items[0].mask);
    try std.testing.expectEqual(@as(u64, 2 | 8 | 32), shown.items[7].mask);
    // The listing cap fails loud (overflow) instead of truncating.
    var capped = try Search.init(a, 8, &e, an, &cands, &.{0}, &.{1}, 0);
    capped.cap = 26;
    _ = try capped.list();
    try std.testing.expect(capped.overflow);
    capped = try Search.init(a, 8, &e, an, &cands, &.{0}, &.{1}, 0);
    capped.cap = 27;
    _ = try capped.list();
    try std.testing.expect(!capped.overflow);
    // Direct search: every allowed ancestor, ABCDEF, not minimal.
    const d = (try se.direct()).?;
    try std.testing.expectEqual(@as(u64, 63), d.mask);
    try std.testing.expect(!d.minimal);
}
