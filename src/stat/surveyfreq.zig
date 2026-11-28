//! PROC SURVEYFREQ declarations, variable roles, observation selection and the
//! default listing of one two-way crosstabulation under Taylor-series variance
//! estimation, SAS/STAT 15.4 physical pp.9587-9602, 9626-9633 and 9660-9663:
//! Data Summary, then frequency, weighted frequency with its standard
//! deviation, percent with its standard error and (ROW) row percent with its
//! standard error. Every other documented feature is a D-009 gap (rc 2)
//! raised before any listing text exists, so a partial page can never be
//! taken for a full analysis.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const format = @import("../format.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
pub const design = @import("surveyfreq_design.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Request = struct { row: usize, col: ?usize, line: usize };

pub const Spec = struct {
    input: proc.ProcInput,
    roles: design.Roles = .{},
    requests: []const Request = &.{},
    /// TABLES options of the single supported statement.
    row_percent: bool = false,
    chisq: bool = false,
    nosummary: bool = false,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    varheader: enum { name, label, namelabel } = .name,
    /// ORDER=DATA: levels in order of first appearance in the input.
    order_data: bool = false,
    /// ORDER=FREQ: descending frequency, ties in order of first appearance.
    order_freq: bool = false,
    nomcar: bool = false,
    /// PAGE: the Data Summary and the table on separate pages.
    page: bool = false,
    /// STRATA / LIST: the Stratum Information table.
    strata_list: bool = false,
    /// RATE= / TOTAL= stratum-level data set (_RATE_ / _TOTAL_).
    fpc_table: ?struct { ds: *Dataset, rate: bool } = null,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC SURVEYFREQ: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC SURVEYFREQ: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented TABLES options (Table 118.5) owned by SURVEYFREQ-008..019.
const later_table_options = [_][]const u8{ "agree", "alpha", "cl", "clwt", "column", "cov", "covwt", "cv", "cvwt", "ddf", "deff", "df", "expected", "kappa", "lrchisq", "nocellpercent", "nofreq", "nopercent", "noprint", "nosparse", "nostd", "nototal", "nowt", "or", "plots", "plot", "relrisk", "risk", "testp", "var", "varwt", "wchisq", "wllchisq", "wtfreq", "deviation", "stderr" };

fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return x;
}

fn roleColumns(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, start: usize, end: usize, what: []const u8) diag.Error![]const usize {
    var cols: std.ArrayList(usize) = .empty;
    var j = start;
    while (j < end) {
        if (at(t, j, .slash)) return gap(cx, t[j].line, "{s} statement options are not implemented", .{what});
        const line = t[j].line;
        const names = try lists.next(cx.arena, ds, t[0..end], &j, cx.diags);
        for (names) |n| try cols.append(cx.arena, ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{n}));
    }
    if (cols.items.len == 0) return invalid(cx, t, end);
    return cols.items;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const valued = at(t, i + 1, .eq);
        if (eq(word, "data") and valued) {
            if (name != null) return invalid(cx, t, i);
            i += 2;
            const first = i;
            if (!at(t, i, .name)) return invalid(cx, t, i);
            name = t[i].text;
            i += 1;
            if (at(t, i, .dot)) {
                if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name.?, t[i + 1].text });
                i += 2;
                qualified = first;
            }
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (eq(word, "missing") and !valued) {
            s.roles.missing = true;
            i += 1;
        } else if (eq(word, "nosummary") and !valued) {
            s.nosummary = true;
            i += 1;
        } else if (eq(word, "nomcar") and !valued) {
            s.nomcar = true;
            i += 1;
        } else if (eq(word, "page") and !valued) {
            s.page = true;
            i += 1;
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (eq(v, "data")) s.order_data = true else if (eq(v, "freq")) s.order_freq = true else if (oneOf(v, &.{"formatted"})) return gap(cx, t[i].line, "ORDER={s} is not implemented", .{v});
            if (!oneOf(v, &.{ "internal", "data", "freq" })) return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "varheader") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            s.varheader = if (eq(v, "name")) .name else if (eq(v, "label")) .label else if (eq(v, "namelabel")) .namelabel else return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "varmethod") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "brr", "jackknife", "jk", "bootstrap" })) return gap(cx, t[i].line, "VARMETHOD={s} is not implemented", .{v});
            if (!eq(v, "taylor")) return invalid(cx, t, i + 2);
            i += 3;
            if (at(t, i, .lparen)) return gap(cx, t[i].line, "VARMETHOD=TAYLOR method options are not implemented", .{});
        } else if (oneOf(word, &.{ "rate", "r", "total", "n" }) and valued) {
            const is_rate = eq(word[0..1], "r");
            // RATE= and TOTAL= cannot both be specified (p.9596).
            if (s.roles.fpc != .none or s.fpc_table != null) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYFREQ: only one of the RATE= and TOTAL= options can be specified", .{});
            if (at(t, i + 2, .name)) {
                var dname = t[i + 2].text;
                i += 3;
                if (at(t, i, .dot) and at(t, i + 1, .name)) {
                    dname = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ dname, t[i + 1].text });
                    i += 2;
                }
                if (at(t, i, .lparen)) return gap(cx, t[i].line, "data set options on {s}= are not implemented", .{word});
                const fds = cx.lib.find(dname) orelse return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC SURVEYFREQ: {s}= data set {s} not found", .{ word, dname });
                s.fpc_table = .{ .ds = fds, .rate = is_rate };
                continue;
            }
            i += 2;
            const x = try number(cx, t, &i);
            if (is_rate) {
                // Proportions in (0,1), percentages in [1,100]; 1 means 100%.
                if (!(x > 0 and x <= 100)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC SURVEYFREQ: RATE= must be a positive number not above 100", .{});
                s.roles.fpc = .{ .rate = if (x == 1) 1 else if (x > 1) x / 100 else x };
            } else {
                if (!(x > 0)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC SURVEYFREQ: TOTAL= must be a positive number", .{});
                s.roles.fpc = .{ .total = x };
            }
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var requests: std.ArrayList(Request) = .empty;
    var tables_seen = false;
    var weight_seen = false;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "tables") or kw(t, i, "table")) {
            if (tables_seen) return gap(cx, t[i].line, "several TABLES statements are not implemented", .{});
            tables_seen = true;
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) {
                if (at(t, j, .lparen)) return gap(cx, t[j].line, "grouped TABLES requests are not implemented", .{});
                if (!at(t, j, .name)) return invalid(cx, t, j);
                const first = ds.indexOf(t[j].text) orelse return cx.diags.fail(error.ParseError, t[j].line, "Variable {s} not found.", .{t[j].text});
                var req: Request = .{ .row = first, .col = null, .line = t[j].line };
                j += 1;
                if (at(t, j, .star)) {
                    if (at(t, j + 1, .lparen)) return gap(cx, t[j].line, "grouped TABLES requests are not implemented", .{});
                    if (!at(t, j + 1, .name) or j + 1 >= end) return invalid(cx, t, j + 1);
                    req.col = ds.indexOf(t[j + 1].text) orelse return cx.diags.fail(error.ParseError, t[j].line, "Variable {s} not found.", .{t[j + 1].text});
                    j += 2;
                    if (at(t, j, .star)) return gap(cx, t[j].line, "multiway TABLES requests are not implemented", .{});
                } else if (at(t, j, .minus) or at(t, j, .colon)) return gap(cx, t[j].line, "variable lists in TABLES requests are not implemented", .{});
                try requests.append(cx.arena, req);
            }
            if (requests.items.len == 0) return invalid(cx, t, j);
            if (at(t, j, .slash)) {
                j += 1;
                if (j == end) return invalid(cx, t, j);
                while (j < end) : (j += 1) {
                    if (!at(t, j, .name)) return invalid(cx, t, j);
                    const o = t[j].text;
                    if (at(t, j + 1, .lparen) or at(t, j + 1, .eq)) {
                        if (!oneOf(o, &later_table_options) and !oneOf(o, &.{ "row", "chisq" })) return invalid(cx, t, j);
                        return gap(cx, t[j].line, "TABLES option {s} with a value or suboptions is not implemented", .{o});
                    }
                    if (eq(o, "row")) s.row_percent = true else if (eq(o, "chisq")) s.chisq = true else if (oneOf(o, &later_table_options)) {
                        return gap(cx, t[j].line, "TABLES option {s} is not implemented", .{o});
                    } else return invalid(cx, t, j);
                }
            }
        } else if (kw(t, i, "weight")) {
            // Only the first WEIGHT statement is used (p.9627).
            if (end != i + 2) return invalid(cx, t, i + 2);
            const c = ds.indexOf(t[i + 1].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i + 1].text});
            if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYFREQ: WEIGHT variable {s} must be numeric", .{t[i + 1].text});
            if (!weight_seen) s.roles.weight = c;
            weight_seen = true;
        } else if (kw(t, i, "strata") or kw(t, i, "stratum")) {
            // SAS-verified (batched real-SAS run): several STRATA (or CLUSTER)
            // statements accumulate their variables, e.g. `strata school;
            // strata state;` gives the school x state strata.
            var stop = end;
            for (i + 1..end) |j| if (at(t, j, .slash)) {
                // LIST is the only STRATA option (p.9601).
                if (end != j + 2 or !kw(t, j + 1, "list")) return invalid(cx, t, j + 1);
                s.strata_list = true;
                stop = j;
                break;
            };
            s.roles.strata = try std.mem.concat(cx.arena, usize, &.{ s.roles.strata, try roleColumns(cx, ds, t, i + 1, stop, "STRATA") });
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            s.roles.clusters = try std.mem.concat(cx.arena, usize, &.{ s.roles.clusters, try roleColumns(cx, ds, t, i + 1, end, "CLUSTER") });
        } else if (kw(t, i, "repweights") or kw(t, i, "repweight")) {
            return gap(cx, t[i].line, "REPWEIGHTS statement (replication variance estimation) is not implemented", .{});
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted levels) is not implemented", .{});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    s.requests = requests.items;
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// One table entry; index R (or C) is the row (or column) total.
pub const Cell = struct {
    count: usize = 0,
    wfreq: f64 = 0,
    sd_wfreq: f64 = 0,
    /// Percent of the table total and its standard error (both in percent).
    pct: f64 = 0,
    se_pct: f64 = 0,
    /// Percent of the row total and its standard error (both in percent).
    row_pct: f64 = 0,
    se_row_pct: f64 = 0,
};

pub const Table = struct {
    row_levels: []const f64,
    col_levels: []const f64,
    /// (R+1) x (C+1), row-major.
    cells: []const Cell,
    /// Observations of the design dropped for a missing TABLES value.
    missing: usize,
    used: usize,
    total: f64,
    pub fn at(self: Table, r: usize, c: usize) Cell {
        return self.cells[r * (self.col_levels.len + 1) + c];
    }
};

/// A missing TABLES value (MISSING option) is one level, ordered first.
fn sameLevel(x: f64, y: f64) bool {
    return x == y or (std.math.isNan(x) and std.math.isNan(y));
}
fn levelLess(_: void, x: f64, y: f64) bool {
    if (std.math.isNan(x)) return !std.math.isNan(y);
    return !std.math.isNan(y) and x < y;
}
fn levelIndex(levels: []const f64, x: f64) usize {
    var k: usize = 0;
    while (!sameLevel(levels[k], x)) k += 1;
    return k;
}
fn hasLevel(levels: []const f64, x: f64) bool {
    for (levels) |l| if (sameLevel(l, x)) return true;
    return false;
}
fn sd(v: f64) f64 {
    if (std.math.isNan(v)) return v;
    return @sqrt(@max(v, 0));
}

/// Two-way table estimates, pp.9641-9646. With w the weights and d the 0/1
/// membership of an observation in a cell:
///   total      N^ = sum w d,                linearized value w d
///   proportion P^ = N^ / N^..,              linearized value w (d - P^) / N^..
///   row prop.  P^r = N^rc / N^r.,           linearized value w (d - P^r d_r) / N^r.
/// each variance being the Taylor-series between-PSU variance of the total of
/// its linearized values. Levels are ascending by internal value; an
/// observation with a missing TABLES value is left out of the table (p.9631).
pub fn tabulate(a: A, d: design.Design, rows: []const []const Value, row_col: usize, col_col: usize, missing_levels: bool) !Table {
    var rl: std.ArrayList(f64) = .empty;
    var cl: std.ArrayList(f64) = .empty;
    var missing: usize = 0;
    const live = try a.alloc(bool, d.kept.len);
    for (d.kept, live) |r, *ok| {
        const x = rows[r][row_col].num;
        const y = rows[r][col_col].num;
        ok.* = missing_levels or (!std.math.isNan(x) and !std.math.isNan(y));
        if (!ok.*) {
            missing += 1;
            continue;
        }
        if (!hasLevel(rl.items, x)) try rl.append(a, x);
        if (!hasLevel(cl.items, y)) try cl.append(a, y);
    }
    std.mem.sort(f64, rl.items, {}, levelLess);
    std.mem.sort(f64, cl.items, {}, levelLess);
    const R = rl.items.len;
    const C = cl.items.len;
    const ri = try a.alloc(usize, d.kept.len);
    const ci = try a.alloc(usize, d.kept.len);
    var total: f64 = 0;
    for (d.kept, live, ri, ci, d.weight) |r, ok, *x, *y, w| {
        if (!ok) continue;
        x.* = levelIndex(rl.items, rows[r][row_col].num);
        y.* = levelIndex(cl.items, rows[r][col_col].num);
        total += w;
    }
    const cells = try a.alloc(Cell, (R + 1) * (C + 1));
    const z = try a.alloc(f64, d.kept.len);
    const member = try a.alloc(f64, d.kept.len);
    const row_w = try a.alloc(f64, R + 1);
    for (0..R + 1) |r| {
        // The row totals come first: cells of the row need N^r..
        var c = C + 1;
        while (c > 0) {
            c -= 1;
            var cell: Cell = .{};
            for (live, ri, ci, d.weight, member) |ok, x, y, w, *m| {
                m.* = if (ok and (r == R or x == r) and (c == C or y == c)) 1 else 0;
                if (m.* == 1) {
                    cell.count += 1;
                    cell.wfreq += w;
                }
            }
            if (c == C) row_w[r] = cell.wfreq;
            if (cell.count == 0) {
                // SAS-verified: a zero-frequency cell (shown by default,
                // p.9612 NOSPARSE) has missing estimates.
                const m = std.math.nan(f64);
                cell = .{ .wfreq = m, .sd_wfreq = m, .pct = m, .se_pct = m, .row_pct = m, .se_row_pct = m };
                cells[r * (C + 1) + c] = cell;
                continue;
            }
            for (z, member, d.weight) |*v, m, w| v.* = w * m;
            cell.sd_wfreq = sd(try design.variance(a, d, z));
            const p = cell.wfreq / total;
            cell.pct = 100 * p;
            if (r < R or c < C) {
                for (z, member, d.weight, live) |*v, m, w, ok| v.* = if (ok) w * (m - p) / total else 0;
                cell.se_pct = 100 * sd(try design.variance(a, d, z));
            }
            if (r < R) {
                const pr = cell.wfreq / row_w[r];
                cell.row_pct = 100 * pr;
                if (c < C) {
                    for (z, member, d.weight, live, ri) |*v, m, w, ok, x| v.* = if (ok and x == r) w * (m - pr) / row_w[r] else 0;
                    cell.se_row_pct = 100 * sd(try design.variance(a, d, z));
                }
            }
            cells[r * (C + 1) + c] = cell;
        }
    }
    return .{ .row_levels = rl.items, .col_levels = cl.items, .cells = cells, .missing = missing, .used = d.kept.len - missing, .total = total };
}

pub const RaoScott = struct {
    pearson: f64,
    correction: f64,
    /// False when the correction is not positive: the test is not computed.
    positive: bool,
    df: usize,
    den_df: usize,
};

/// First-order Rao-Scott ingredients for a two-way table, pp.9662-9664:
/// Q_P = (n / N^) sum (N^rc - E_rc)^2 / E_rc with E_rc = N^r. N^.c / N^, and
/// D = [sum_rc (1 - P^rc) Deff(P^rc) - sum_r (1 - P^r.) Deff(P^r.)
///      - sum_c (1 - P^.c) Deff(P^.c)] / ((R-1)(C-1)),
/// Deff(P) = Var(P) / (P (1 - P) / (n - 1)). Null when an estimated
/// proportion is 0 or 1 (a design effect is then undefined).
pub fn raoScott(d: design.Design, tb: Table) ?RaoScott {
    const R = tb.row_levels.len;
    const C = tb.col_levels.len;
    if (R < 2 or C < 2) return null;
    const n: f64 = @floatFromInt(tb.used);
    var q: f64 = 0;
    var plus: f64 = 0;
    var minus: f64 = 0;
    for (0..R + 1) |r| for (0..C + 1) |c| {
        if (r == R and c == C) continue;
        const cell = tb.at(r, c);
        const p = cell.pct / 100;
        if (!(p > 0 and p < 1)) return null;
        const term = (1 - p) * (cell.se_pct / 100) * (cell.se_pct / 100) / (p * (1 - p) / (n - 1));
        if (r < R and c < C) {
            plus += term;
            const e = tb.at(r, C).wfreq * tb.at(R, c).wfreq / tb.total;
            q += (cell.wfreq - e) * (cell.wfreq - e) / e;
        } else minus += term;
    };
    const df = (R - 1) * (C - 1);
    const correction = (plus - minus) / @as(f64, @floatFromInt(df));
    // ponytail: analytically the correction is exactly zero when cell
    // proportions are a fixed share of their margin in every PSU; a relative
    // 1e-9 guard keeps the floating-point residue of that case "not positive".
    return .{ .pearson = n / tb.total * q, .correction = correction, .positive = correction > 1e-9 * (plus + minus), .df = df, .den_df = df * (d.clusters() - d.strata()) };
}

pub const Group = struct {
    /// Design of every valid observation (the Data Summary).
    d: design.Design,
    table: Table,
    rs: ?RaoScott,
    /// Valid observations left out of the table for a missing TABLES value.
    freq_missing: usize,
    /// Some stratum of the table has a single cluster (left out of variances).
    single_psu: bool,
    rep: ?[]const Value,
    /// The (coded) rows the summary design `d` indexes.
    rows: []const []const Value,
    /// Per TABLES variable: level texts when the table holds level codes
    /// (character variables, ORDER=DATA), else null (unformatted numbers).
    labels: [2]?[]const []const u8,
};

/// Level dictionary of a TABLES variable over the whole input: character
/// values (trailing blanks dropped) ascending, or ORDER=DATA first appearance.
/// Missing values (blank, or numeric missing) are not levels.
fn levelDict(a: A, ds: *const Dataset, c: usize, order_data: bool, order_freq: bool) !?[]const []const u8 {
    const char = ds.columns.items[c].type != .num;
    if (!char and !order_data and !order_freq) return null;
    var list: std.ArrayList([]const u8) = .empty;
    var counts: std.ArrayList(usize) = .empty;
    for (ds.rows.items) |row| {
        const text = try levelText(a, row[c]) orelse continue;
        for (list.items, counts.items) |l, *n| {
            if (std.mem.eql(u8, l, text)) {
                n.* += 1;
                break;
            }
        } else {
            try list.append(a, text);
            try counts.append(a, 1);
        }
    }
    if (order_freq) {
        // SAS-verified: descending (unweighted) frequency; ties keep the
        // order of first appearance (a stable sort of the data order).
        const idx = try a.alloc(usize, list.items.len);
        for (idx, 0..) |*x, k| x.* = k;
        std.sort.insertion(usize, idx, counts.items, struct {
            fn gt(n: []const usize, x: usize, y: usize) bool {
                return n[x] > n[y];
            }
        }.gt);
        const sorted = try a.alloc([]const u8, idx.len);
        for (idx, sorted) |k, *t| t.* = list.items[k];
        return sorted;
    }
    if (char and !order_data) std.mem.sort([]const u8, list.items, {}, struct {
        fn lt(_: void, x: []const u8, y: []const u8) bool {
            return std.mem.order(u8, x, y) == .lt;
        }
    }.lt);
    return list.items;
}
fn levelText(a: A, v: Value) !?[]const u8 {
    return switch (v) {
        .str => |t| blk: {
            const x = std.mem.trimEnd(u8, t, " ");
            break :blk if (x.len == 0) null else x;
        },
        .num => |x| if (std.math.isNan(x)) null else try format.bestNum(a, x),
    };
}
/// Rows with the TABLES values replaced by level codes (missing: NaN).
fn codeRows(a: A, rows: []const []const Value, cols: [2]usize, dicts: [2]?[]const []const u8) ![]const []const Value {
    if (dicts[0] == null and dicts[1] == null) return rows;
    const out = try a.alloc([]const Value, rows.len);
    for (rows, out) |row, *o| {
        const copy = try a.dupe(Value, row);
        for (cols, dicts) |c, dict| if (dict) |levels| {
            var code = std.math.nan(f64);
            if (try levelText(a, row[c])) |text| {
                for (levels, 0..) |l, k| if (std.mem.eql(u8, l, text)) {
                    code = @floatFromInt(k);
                    break;
                };
            }
            copy[c] = .{ .num = code };
        };
        o.* = copy;
    }
    return out;
}

fn hasMissing(rows: []const []const Value, kept: []const usize, cols: []const usize) bool {
    for (kept) |r| for (cols) |c| if (std.math.isNan(rows[r][c].num)) return true;
    return false;
}

/// Per-BY-group designs and tables; raises every execution boundary before
/// any text exists.
/// Stratum-level RATE= / TOTAL= values (p.9590): the data set holds every
/// STRATA variable and _RATE_ (or _TOTAL_); each stratum of the input must be
/// present. Rates follow the RATE=value conventions.
fn applyFpcTable(cx: proc.ProcCtx, s: Spec, d: *design.Design, rows: []const []const Value) diag.Error!void {
    const ft = s.fpc_table orelse return;
    const ds = s.input.ds;
    const fds = ft.ds;
    if (s.roles.strata.len == 0) return gap(cx, 0, "RATE= or TOTAL= data set without a STRATA statement is not implemented", .{});
    const vname: []const u8 = if (ft.rate) "_rate_" else "_total_";
    const vc = fds.indexOf(vname) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: the {s}= data set must contain the variable {s}", .{ if (ft.rate) @as([]const u8, "RATE") else "TOTAL", vname });
    const keys = try cx.arena.alloc(usize, s.roles.strata.len);
    for (s.roles.strata, keys) |c, *k| {
        const n = ds.columns.items[c].name;
        k.* = fds.indexOf(n) orelse return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: the RATE= or TOTAL= data set must contain the STRATA variable {s}", .{n});
        if (fds.columns.items[k.*].type != ds.columns.items[c].type or ds.columns.items[c].format != null) return gap(cx, 0, "RATE= or TOTAL= data set with formatted or mismatched STRATA variables is not implemented", .{});
    }
    const fpc = try cx.arena.alloc(f64, d.strata());
    for (fpc, d.stratum_rep, d.stratum_psus) |*f, rep, n| {
        const row = rows[rep];
        const hit = for (fds.rows.items) |fr| {
            const same = for (s.roles.strata, keys) |c, k| {
                if (!design.sameValue(row[c], fr[k])) break false;
            } else true;
            if (same) break fr;
        } else return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: a stratum of the input is missing from the RATE= or TOTAL= data set", .{});
        const x = hit[vc].num;
        if (ft.rate) {
            if (!(x > 0 and x <= 100)) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: _RATE_ values must be positive numbers not above 100", .{});
            f.* = 1 - (if (x == 1) 1 else if (x > 1) x / 100 else x);
        } else {
            if (!(x > 0)) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: _TOTAL_ values must be positive numbers", .{});
            f.* = 1 - @as(f64, @floatFromInt(n)) / x;
        }
    }
    d.stratum_fpc = fpc;
}

pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error![]Group {
    const a = cx.arena;
    const ds = s.input.ds;
    if (s.requests.len == 0) return gap(cx, 0, "the step without a TABLES statement (default one-way tables) is not implemented", .{});
    if (s.requests.len > 1) return gap(cx, 0, "several TABLES requests are not implemented", .{});
    const req = s.requests[0];
    const col = req.col orelse return gap(cx, req.line, "one-way frequency tables are not implemented (listing layout not verified)", .{});
    var dicts: [2]?[]const []const u8 = undefined;
    for ([_]usize{ req.row, col }, &dicts) |c, *dict| {
        const v = ds.columns.items[c];
        if (v.format != null) return gap(cx, req.line, "formatted TABLES variables are not implemented", .{});
        dict.* = try levelDict(a, ds, c, s.order_data, s.order_freq);
        // Frequencies are counted over the whole input: verified only when
        // every observation is in the table.
        if (s.order_freq) for (ds.rows.items) |row| {
            if (try levelText(a, row[c]) == null) return gap(cx, req.line, "ORDER=FREQ with missing TABLES values is not implemented", .{});
        };
        // Missing levels are verified only as numeric '.' in internal order.
        if (s.roles.missing and dict.* != null) for (ds.rows.items) |row| {
            if (try levelText(a, row[c]) == null) return gap(cx, req.line, "MISSING levels of character or ORDER=DATA TABLES variables are not implemented", .{});
        };
    }
    if (s.strata_list) {
        // SAS-verified for one numeric STRATA variable with a CLUSTER
        // statement (two samples); other shapes have unknown column rules.
        const v = ds.columns.items[s.roles.strata[0]];
        if (s.roles.strata.len != 1 or v.type != .num or v.format != null or v.name.len > 12 or s.roles.clusters.len == 0 or s.nosummary or s.page)
            return gap(cx, 0, "STRATA / LIST for this design (several, character or formatted STRATA variables, no CLUSTER, NOSUMMARY or PAGE) is not implemented", .{});
    }
    if (s.nomcar and s.chisq) return gap(cx, 0, "CHISQ with NOMCAR is not implemented", .{});
    if (s.page and (s.chisq or s.nomcar or s.nosummary)) return gap(cx, 0, "PAGE with CHISQ, NOMCAR or NOSUMMARY is not verified", .{});
    if (s.chisq and (s.roles.fpc != .none or s.fpc_table != null)) return gap(cx, 0, "CHISQ with RATE= or TOTAL= is not implemented", .{});
    if (s.order_freq and s.by_cols.len > 0) return gap(cx, 0, "ORDER=FREQ with BY groups is not implemented", .{});
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    const table_cols = [_]usize{ req.row, col };
    for (slices, groups) |slice, *group| {
        const group_rows = try codeRows(a, slice.rows, table_cols, dicts);
        var d = try design.build(a, group_rows, s.roles);
        try applyFpcTable(cx, s, &d, group_rows);
        if (d.kept.len == 0) return gap(cx, 0, "the result for an input without valid observations is not verified", .{});
        if (s.order_freq and d.kept.len != d.read) return gap(cx, 0, "ORDER=FREQ with excluded observations is not implemented", .{});
        if (d.invalidFpc()) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: TOTAL= is less than the number of sampled clusters in a stratum", .{});
        // Missing TABLES values: without MISSING the observations are excluded
        // from the table and all its analyses (MCAR, p.9631), so the table's
        // design is rebuilt without them (empty strata and clusters drop out).
        var td = d;
        var table_rows = group_rows;
        var freq_missing: usize = 0;
        if (s.roles.missing) {
            for (d.kept) |r| for (table_cols) |c| {
                const x = group_rows[r][c].num;
                if (std.math.isNan(x) and Value.missingChar(x) != '.') return gap(cx, 0, "special missing values as TABLES levels are not implemented", .{});
            };
        } else if (s.nomcar) {
            // NOMCAR (p.9631): the nonmissing observations are a domain of the
            // whole design; missing ones keep their PSU with zero values.
            for (d.kept) |r| if (std.math.isNan(group_rows[r][req.row].num) or std.math.isNan(group_rows[r][col].num)) {
                freq_missing += 1;
            };
            if (freq_missing == d.kept.len) return gap(cx, 0, "a table without nonmissing observations is not verified", .{});
        } else if (hasMissing(group_rows, d.kept, &table_cols)) {
            var keep: std.ArrayList([]const Value) = .empty;
            for (d.kept) |r| if (!std.math.isNan(group_rows[r][req.row].num) and !std.math.isNan(group_rows[r][col].num)) try keep.append(a, group_rows[r]);
            freq_missing = d.kept.len - keep.items.len;
            if (keep.items.len == 0) return gap(cx, 0, "a table without nonmissing observations is not verified", .{});
            td = try design.build(a, keep.items, s.roles);
            try applyFpcTable(cx, s, &td, keep.items);
            table_rows = keep.items;
        }
        // Single-cluster strata are left out of the variance (all of them:
        // missing variances), with a NOTE; SAS-verified.
        const single = td.singlePsuStratum();
        const tb = try tabulate(a, td, table_rows, req.row, col, s.roles.missing);
        if (s.row_percent) for (0..tb.row_levels.len) |r| for (0..tb.col_levels.len) |c| {
            if (tb.at(r, c).count == 0) return gap(cx, 0, "ROW percentages of a table with a zero-frequency cell are not verified", .{});
        };
        var rs: ?RaoScott = null;
        if (s.chisq) {
            if (single or freq_missing > 0 or d.read != d.kept.len) return gap(cx, 0, "CHISQ with excluded observations or single-cluster strata is not verified", .{});
            rs = raoScott(td, tb) orelse return gap(cx, 0, "the Rao-Scott chi-square test for a table with a zero cell or fewer than two rows or columns is not implemented", .{});
            // Owned by STAT-SURVEYFREQ-015; only the reference's degenerate
            // table (test not computable) is verified here.
            if (rs.?.positive) return gap(cx, 0, "the Rao-Scott chi-square test with a positive design correction is not implemented", .{});
        }
        group.* = .{ .d = d, .table = tb, .rs = rs, .freq_missing = freq_missing, .single_psu = single, .rep = slice.rep, .labels = dicts, .rows = group_rows };
    }
    return groups;
}

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
/// SAS-verified on five widths: the crosstabulation title's half margin
/// rounds half to even (59 -> 30 blanks, 69 -> 34, 67 -> 34).
fn centeredUp(a: A, out: *Out, text: []const u8, width: usize) !void {
    const margin = width -| text.len;
    const half = margin / 2;
    try out.appendNTimes(a, ' ', if (margin % 2 == 1 and half % 2 == 1) half + 1 else half);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn pair(a: A, out: *Out, label: []const u8, label_width: usize, value: []const u8, value_width: usize) !void {
    try out.appendSlice(a, label);
    try out.appendNTimes(a, ' ', label_width + value_width - label.len - value.len);
    try out.appendSlice(a, value);
    try out.append(a, '\n');
}
fn fixed(a: A, x: f64, comptime decimals: u8) ![]const u8 {
    // SAS-verified: a missing w.5 standard deviation prints "." at the right
    // edge, a missing w.4 standard error "." where the decimal point goes.
    if (std.math.isNan(x)) return if (decimals == 4) ".    " else ".";
    const text = try std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{decimals}) ++ "}", .{x});
    // A negative rounding residue must not print as -0.0000.
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}

/// Right edges of Frequency, Weighted Frequency, Std Err of Wgt Freq,
/// Percent, Std Err of Percent, Row Percent, Std Err of Row Percent, past the
/// end of the second variable column (SAS-verified).
const offsets = [_]usize{ 14, 28, 42, 54, 68, 80, 95 };
/// SAS-verified: without a WEIGHT statement the two weighted-frequency
/// columns are absent and the later columns move left by their 28 positions.
const unweighted_offsets = [_]usize{ 14, 0, 0, 26, 40, 52, 67 };

/// A TABLES variable column (SAS-verified layouts): width the largest of its
/// header, its level texts, "Total" (5) and, for a character variable, its
/// length; numbers and their header right-aligned, character values, their
/// header and the "Total" label left-aligned.
const VarColumn = struct {
    header: []const u8,
    width: usize,
    left: bool,
    fn put(self: VarColumn, b: []u8, start: usize, text: []const u8) void {
        if (self.left) @memcpy(b[start .. start + text.len], text) else proc.putRight(b, start + self.width, text);
    }
};
const head1 = [_][]const u8{ "", "", "", "Weighted", "Std Err of", "", "Std Err of", "Row", "Std Err of" };
const head2 = [_][]const u8{ "", "", "Frequency", "Frequency", "Wgt Freq", "Percent", "Percent", "Percent", "Row Percent" };

fn tableLine(cx: proc.ProcCtx, a: A, out: *Out, vc: [2]VarColumn, cols: []const usize, width: usize, first: []const u8, second: []const u8, cell: Cell, row_pct: bool, se_pct: bool, se_row: bool) diag.Error!void {
    const b = try proc.line(a, width);
    vc[0].put(b, 0, first);
    vc[1].put(b, vc[0].width + 4, second);
    const texts = [_][]const u8{
        try std.fmt.allocPrint(a, "{d}", .{cell.count}),      try fixed(a, cell.wfreq, 5),
        try fixed(a, cell.sd_wfreq, 5),                       try fixed(a, cell.pct, 4),
        if (se_pct) try fixed(a, cell.se_pct, 4) else "",     if (row_pct) try fixed(a, cell.row_pct, 4) else "",
        if (se_row) try fixed(a, cell.se_row_pct, 4) else "",
    };
    for (texts, cols) |text, edge| {
        if (edge == 0) continue;
        if (edge > width) break;
        // ponytail: fixed w.d columns as in the reference; larger magnitudes
        // need the template's width rules.
        if (text.len > 12) return gap(cx, 0, "listing columns for values wider than the verified layout are not implemented", .{});
        proc.putRight(b, edge, text);
    }
    try out.appendSlice(a, b);
    try out.append(a, '\n');
}

/// Stratum Information (STRATA / LIST), SAS-verified layout for one numeric
/// STRATA variable: strata ascending by value, their valid observations and
/// clusters.
fn stratumInfo(a: A, out: *Out, s: Spec, g: Group) !void {
    const ds = s.input.ds;
    const sc = s.roles.strata[0];
    const rows = g.rows;
    const H = g.d.strata();
    const order = try a.alloc(usize, H);
    for (order, 0..) |*o, h| o.* = h;
    const Ctx = struct {
        rows: []const []const Value,
        reps: []const usize,
        c: usize,
        fn lt(cx: @This(), x: usize, y: usize) bool {
            return levelLess({}, cx.rows[cx.reps[x]][cx.c].num, cx.rows[cx.reps[y]][cx.c].num);
        }
    };
    std.mem.sort(usize, order, Ctx{ .rows = rows, .reps = g.d.stratum_rep, .c = sc }, Ctx.lt);
    const obs = try a.alloc(usize, H);
    @memset(obs, 0);
    for (g.d.psu) |p| obs[g.d.psu_stratum[p]] += 1;
    try centered(a, out, "Stratum Information", 49);
    try out.appendSlice(a, " \n");
    const heads = [_][2][]const u8{ .{ "Stratum", " Index" }, .{ "", ds.columns.items[sc].name }, .{ "Number of", "Obs" }, .{ "Number of", "Clusters" } };
    const right = [_]usize{ 7, 23, 36, 49 };
    for (0..2) |n| {
        const b = try proc.line(a, 49);
        for (heads, right, 0..) |h, e, k| {
            if (k == 0) @memcpy(b[0..h[n].len], h[n]) else proc.putRight(b, e, h[n]);
        }
        try out.appendSlice(a, b);
        try out.append(a, '\n');
    }
    const rule = "-" ** 49 ++ "\n";
    try out.appendSlice(a, rule);
    for (order, 1..) |h, k| {
        const b = try proc.line(a, 49);
        proc.putRight(b, 4, try std.fmt.allocPrint(a, "{d}", .{k}));
        proc.putRight(b, 23, try format.bestNum(a, rows[g.d.stratum_rep[h]][sc].num));
        proc.putRight(b, 36, try std.fmt.allocPrint(a, "{d}", .{obs[h]}));
        proc.putRight(b, 49, try std.fmt.allocPrint(a, "{d}", .{g.d.stratum_psus[h]}));
        try out.appendSlice(a, b);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, rule);
    try out.appendSlice(a, "\n\n");
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, g: Group) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const req = s.requests[0];
    const rname = ds.columns.items[req.row].name;
    const cname = ds.columns.items[req.col.?].name;
    var vc: [2]VarColumn = undefined;
    var level_texts: [2][]const []const u8 = undefined;
    for ([_]usize{ req.row, req.col.? }, [_][]const f64{ g.table.row_levels, g.table.col_levels }, g.labels, &vc, &level_texts) |c, levels, dict, *v, *texts| {
        const info = ds.columns.items[c];
        v.header = switch (s.varheader) {
            .name => info.name,
            .label => info.label orelse info.name,
            .namelabel => if (info.label) |l| try std.fmt.allocPrint(a, "{s}({s})", .{ info.name, l }) else info.name,
        };
        v.left = info.type != .num;
        v.width = @max(v.header.len, 5);
        if (v.left) v.width = @max(v.width, info.len orelse 8);
        const tx = try a.alloc([]const u8, levels.len);
        for (levels, tx) |x, *t| {
            t.* = if (dict) |d| (if (std.math.isNan(x)) "." else d[@intFromFloat(x)]) else try format.bestNum(a, x);
            v.width = @max(v.width, t.len);
        }
        texts.* = tx;
    }
    const base = vc[0].width + 4 + vc[1].width;
    var col_edges: [7]usize = undefined;
    for (&col_edges, if (s.roles.weight != null) offsets else unweighted_offsets) |*e, o| e.* = if (o == 0) 0 else base + o;
    const tb = g.table;
    const R = tb.row_levels.len;
    const C = tb.col_levels.len;
    var body: Out = .empty;
    if (g.rep) |row| try byLine(a, &body, ds, row, s.by_cols);
    try body.appendSlice(a, "\nThe SURVEYFREQ Procedure\n\n");
    if (!s.nosummary) {
        // SAS-verified: with nonpositive weights the table shows the
        // observations read, used and with nonpositive weights, and the label
        // column widens to the longest label (the value column stays 14 wide);
        // otherwise Number of Observations is the valid count only (an
        // observation dropped for a missing STRATA / CLUSTER value is not
        // mentioned).
        const excluded = g.d.bad_weight > 0;
        const lw: usize = if (excluded) 38 else 22;
        try centered(a, &body, "Data Summary", lw + 14);
        try body.append(a, '\n');
        if (s.roles.strata.len > 0) try pair(a, &body, "Number of Strata", lw, try std.fmt.allocPrint(a, "{d}", .{g.d.strata()}), 14);
        if (s.roles.clusters.len > 0) try pair(a, &body, "Number of Clusters", lw, try std.fmt.allocPrint(a, "{d}", .{g.d.clusters()}), 14);
        try pair(a, &body, "Number of Observations", lw, try std.fmt.allocPrint(a, "{d}", .{if (excluded) g.d.read else g.d.kept.len}), 14);
        if (excluded) try pair(a, &body, "Number of Observations Used", lw, try std.fmt.allocPrint(a, "{d}", .{g.d.kept.len}), 14);
        if (g.d.bad_weight > 0) try pair(a, &body, "Number of Obs with Nonpositive Weights", lw, try std.fmt.allocPrint(a, "{d}", .{g.d.bad_weight}), 14);
        if (s.roles.weight != null) try pair(a, &body, "Sum of Weights", lw, try format.bestNum(a, g.d.sum_weights), 14);
        if (s.page) {
            // SAS-verified: the table starts a new page (titles, procedure
            // title) after one blank line.
            try body.append(a, '\n');
            if (cx.listing_titles) |titles| try titles.emitTitles(a, &body);
            try body.appendSlice(a, "\nThe SURVEYFREQ Procedure\n\n");
        } else try body.appendSlice(a, "\n\n");
    }
    if (s.strata_list) try stratumInfo(a, &body, s, g);
    if (s.nomcar) {
        // SAS-verified: NOMCAR adds the Variance Estimation table.
        try centered(a, &body, "Variance Estimation", 31);
        try body.append(a, '\n');
        try pair(a, &body, "Method", 14, "Taylor Series", 17);
        try pair(a, &body, "Missing Values", 14, "NOMCAR", 17);
        try body.appendSlice(a, "\n\n");
    }
    const cols: []const usize = &col_edges;
    const width: usize = if (s.row_percent) cols[6] else cols[4];
    try centeredUp(a, &body, try std.fmt.allocPrint(a, "Table of {s} by {s}", .{ vc[0].header, vc[1].header }), width);
    try body.appendSlice(a, " \n");
    for ([_][]const []const u8{ head1[2..], head2[2..] }, 0..) |heads, n| {
        const b = try proc.line(a, width);
        if (n == 1) {
            vc[0].put(b, 0, vc[0].header);
            vc[1].put(b, vc[0].width + 4, vc[1].header);
        }
        for (heads, cols) |h, edge| if (edge != 0 and edge <= width) proc.putRight(b, edge, h);
        try body.appendSlice(a, b);
        try body.append(a, '\n');
    }
    const rule = try a.alloc(u8, width + 1);
    @memset(rule, '-');
    rule[width] = '\n';
    try body.appendSlice(a, rule);
    for (0..R + 1) |r| {
        const rtext = if (r == R) "Total" else level_texts[0][r];
        for (0..C) |c| try tableLine(cx, a, &body, vc, cols, width, if (c == 0) rtext else "", level_texts[1][c], tb.at(r, c), s.row_percent and r < R, true, s.row_percent and r < R);
        try body.append(a, '\n');
        try tableLine(cx, a, &body, vc, cols, width, "", "Total", tb.at(r, C), s.row_percent and r < R, r < R, false);
        try body.appendSlice(a, rule);
    }
    // SAS-verified: centred under the table (p.9631: displayed below it).
    if (g.freq_missing > 0) try centered(a, &body, try std.fmt.allocPrint(a, "Frequency Missing = {d}", .{g.freq_missing}), width);
    if (g.rs) |rs| {
        try body.appendSlice(a, "\n\n");
        try centered(a, &body, "Rao-Scott Chi-Square Test", 28);
        try body.append(a, '\n');
        const blank = " " ** 28 ++ "\n";
        try pair(a, &body, "Pearson Chi-Square", 20, try fixed(a, rs.pearson, 4), 8);
        try pair(a, &body, "Design Correction", 20, try fixed(a, rs.correction, 4), 8);
        try body.appendSlice(a, blank);
        try pair(a, &body, "Rao-Scott Chi-Square", 20, ".", 8);
        try pair(a, &body, "DF", 20, try std.fmt.allocPrint(a, "{d}", .{rs.df}), 8);
        try pair(a, &body, "Pr > ChiSq", 20, ".", 8);
        try body.appendSlice(a, blank);
        try pair(a, &body, "F Value", 20, ".", 8);
        try pair(a, &body, "Num DF", 20, try std.fmt.allocPrint(a, "{d}", .{rs.df}), 8);
        try pair(a, &body, "Den DF", 20, try std.fmt.allocPrint(a, "{d}", .{rs.den_df}), 8);
        try pair(a, &body, "Pr > F", 20, ".", 8);
        try body.append(a, '\n');
        try centered(a, &body, try std.fmt.allocPrint(a, "Sample Size = {d}", .{tb.used}), 28);
        try cx.diags.note(req.line, "The Rao-Scott chi-square test cannot be computed for the table of {s} by {s} because the design correction is not positive.", .{ rname, cname });
    }
    try out.appendSlice(a, body.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const groups = try plan(cx, s);
    if (groups.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    const ds = s.input.ds;
    // Nothing is printed unless every BY group can be analysed.
    var body: Out = .empty;
    for (groups, 0..) |group, k| {
        if (k > 0) {
            try body.append(cx.arena, '\n');
            if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, &body);
        }
        try render(cx, &body, s, group);
    }
    try out.appendSlice(cx.arena, body.items);
    // SAS-verified log order: the BY note, then per group the omitted-weight
    // and single-cluster notes (with the BY-group note).
    if (s.by_cols.len > 0) try cx.diags.note(0, "The BY statement provides completely separate analyses of the BY groups.  It does not provide a statistically valid subpopulation or domain analysis, where the total number of units in the subpopulation is not known with certainty. If you want a domain analysis, you should include the domain variables in your TABLES request.", .{});
    const req = s.requests[0];
    for (groups) |g| {
        if (g.d.bad_weight > 0) try cx.diags.note(req.line, "{d} observation{s} omitted due to nonpositive weights.", .{ g.d.bad_weight, if (g.d.bad_weight == 1) @as([]const u8, " was") else "s were" });
        if (g.single_psu) try cx.diags.note(req.line, "There is at least one stratum that contains only a single cluster for the table of {s} by {s}. Single-cluster strata are not included in the variance estimates.", .{ ds.columns.items[req.row].name, ds.columns.items[req.col.?].name });
        if ((g.d.bad_weight > 0 or g.single_psu) and g.rep != null) try by.reportNote(cx.arena, cx.diags, ds, g.rep.?, s.by_cols);
    }
}

/// BY line flush left. ponytail: as in PROC STDIZE, the shared helper centers
/// the BY line; the NOCENTER reference listing has it at column 1.
fn byLine(a: A, out: *Out, ds: *Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, ds, row, cols);
    const text = std.mem.trimStart(u8, tmp.items, "\n");
    if (text.len == 0) return;
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, text, " "));
}

test {
    _ = @import("surveyfreq_tests.zig");
}
