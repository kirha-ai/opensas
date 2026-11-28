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
//! against a reference listing (METHOD=BACKDOOR/IV, TESTID, IMAP, COMMON,
//! NOSORT, CYCLES=, joint effects) is a
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
};

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
        } else if (eq(w, "common") or eq(w, "imap") or eq(w, "cycles") or eq(w, "nosort")) {
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
            return gap(cx, line, "the TESTID statement is not implemented", .{});
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
    for (s.models) |m| {
        if (s.identify) {
            var tr = false;
            var oc = false;
            for (m.nodes) |n| {
                if (contains(s.treatments, n)) tr = true;
                if (contains(s.outcomes, n)) oc = true;
            }
            if (!tr) return user(cx, m.line, "The model {s} must contain at least one treatment variable.", .{m.label});
            if (!oc) return user(cx, m.line, "The model {s} must contain at least one outcome variable.", .{m.label});
        }
        if (try hasCycle(cx.arena, s.names.len, m.edges)) return user(cx, m.line, "The model {s} contains at least 1 directed cycle.", .{m.label});
        // ponytail: the reference run also prints the DirectedCycles table
        // before this error; only the error is produced here.
    }
    // Disconnected models: VariableInfo, summary, every ConnectedComponents
    // table, then (DISCONNECTED) every AdjustList (SAS 9.4 reference runs).
    if (s.opts.method != .adjustment) return gap(cx, 0, "METHOD={s} is not implemented", .{if (s.opts.method == .iv) "IV" else "BACKDOOR"});
    if (s.treatments.len > 1 or s.outcomes.len > 1) return gap(cx, line, "joint causal effects (several treatment or outcome variables) are not implemented", .{});
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
};

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
    const a = cx.arena;
    var s = try parse(cx, t);
    try validate(cx, s);
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
    const n = s.names.len;
    const list = s.opts.list orelse s.identify;

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
    if (list) {
        for (measured.items) |v| if (!contains(s.treatments, v) and !contains(s.outcomes, v)) try cands.append(a, v);
        if (cands.items.len > max_candidates) return gap(cx, s.models[0].line, "more than {d} measured covariates (exhaustive adjustment-set enumeration) is not implemented", .{max_candidates});
        for (s.models, sets) |m, *dst| {
            var mc: std.ArrayList(usize) = .empty;
            var pos: std.ArrayList(usize) = .empty;
            for (cands.items, 0..) |c, k| if (contains(m.nodes, c)) {
                try mc.append(a, c);
                try pos.append(a, k);
            };
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
            const an = try analyse(a, g.n, g.edges, s.treatments, s.outcomes);
            const local = try enumerate(a, g.n, an, mc.items, s.treatments, s.outcomes, required);
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
        if (!list) return;
        for (s.models, sets) |m, msets| {
            try page(cx, out);
            try adjustTable(cx, out, s, m, msets, cands.items);
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
    if (!list or (any_disc and !s.opts.disconnected)) return endPage(cx, out);

    // One AdjustList page per model.
    for (s.models, sets) |m, msets| {
        try endPage(cx, out);
        try page(cx, out);
        try adjustTable(cx, out, s, m, msets, cands.items);
    }
    try endPage(cx, out);
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

fn adjustTable(cx: proc.ProcCtx, out: *Out, s: Spec, m: Model, sets: []const Set, cands: []const usize) !void {
    const a = cx.arena;
    var shown: std.ArrayList(Set) = .empty;
    const min_size: usize = if (sets.len > 0) sets[0].size else 0;
    for (sets) |st| {
        if (s.opts.minimal and !st.minimal) continue;
        if (s.opts.maxsize) |ms| if ((ms == 0 and st.size != min_size) or (ms > 0 and st.size > ms)) continue;
        if (s.opts.maxlist) |ml| if (shown.items.len >= ml) break;
        try shown.append(a, st);
    }
    if (shown.items.len == 0) {
        try out.appendSlice(a, try std.fmt.allocPrint(a, "NOTE: There are no adjustment sets satisfying the specified criteria for {s}.\n\n", .{m.label}));
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
    const t2 = try std.fmt.allocPrint(a, "Causal Effect of {s} on {s}", .{ s.names[s.treatments[0]], s.names[s.outcomes[0]] });
    try table(a, out, &.{ t1, t2 }, 1, cols.items, gaps, if (used.items.len > 0) Spanner{ .from = 3, .text = span_text } else null);
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
