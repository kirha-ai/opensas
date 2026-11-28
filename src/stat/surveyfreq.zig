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
        } else if (oneOf(word, &.{ "nomcar", "page" }) and !valued) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else if (eq(word, "order") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "data", "formatted", "freq" })) return gap(cx, t[i].line, "ORDER={s} is not implemented", .{v});
            if (!eq(v, "internal")) return invalid(cx, t, i + 2);
            i += 3;
        } else if (eq(word, "varheader") and valued) {
            if (!at(t, i + 2, .name)) return invalid(cx, t, i + 2);
            const v = t[i + 2].text;
            if (oneOf(v, &.{ "label", "namelabel" })) return gap(cx, t[i].line, "VARHEADER={s} is not implemented", .{v});
            if (!eq(v, "name")) return invalid(cx, t, i + 2);
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
            if (s.roles.fpc != .none) return cx.diags.fail(error.ParseError, t[i].line, "PROC SURVEYFREQ: only one of the RATE= and TOTAL= options can be specified", .{});
            if (at(t, i + 2, .name)) return gap(cx, t[i].line, "{s}=SAS-data-set (stratum-level values) is not implemented", .{word});
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
    var strata_seen = false;
    var cluster_seen = false;
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
            if (strata_seen) return gap(cx, t[i].line, "duplicate STRATA statement policy is not verified", .{});
            strata_seen = true;
            s.roles.strata = try roleColumns(cx, ds, t, i + 1, end, "STRATA");
        } else if (kw(t, i, "cluster") or kw(t, i, "clusters")) {
            if (cluster_seen) return gap(cx, t[i].line, "duplicate CLUSTER statement policy is not verified", .{});
            cluster_seen = true;
            s.roles.clusters = try roleColumns(cx, ds, t, i + 1, end, "CLUSTER");
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

fn levelIndex(levels: []const f64, x: f64) usize {
    var k: usize = 0;
    while (levels[k] != x) k += 1;
    return k;
}
fn sd(v: f64) f64 {
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
pub fn tabulate(a: A, d: design.Design, rows: []const []const Value, row_col: usize, col_col: usize) !Table {
    var rl: std.ArrayList(f64) = .empty;
    var cl: std.ArrayList(f64) = .empty;
    var missing: usize = 0;
    const live = try a.alloc(bool, d.kept.len);
    for (d.kept, live) |r, *ok| {
        const x = rows[r][row_col].num;
        const y = rows[r][col_col].num;
        ok.* = !std.math.isNan(x) and !std.math.isNan(y);
        if (!ok.*) {
            missing += 1;
            continue;
        }
        if (std.mem.indexOfScalar(f64, rl.items, x) == null) try rl.append(a, x);
        if (std.mem.indexOfScalar(f64, cl.items, y) == null) try cl.append(a, y);
    }
    std.mem.sort(f64, rl.items, {}, std.sort.asc(f64));
    std.mem.sort(f64, cl.items, {}, std.sort.asc(f64));
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

pub const Group = struct { d: design.Design, table: Table, rs: ?RaoScott };

/// Per-BY-group designs and tables; raises every execution boundary before
/// any text exists.
pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error![]Group {
    const a = cx.arena;
    const ds = s.input.ds;
    if (s.requests.len == 0) return gap(cx, 0, "the step without a TABLES statement (default one-way tables) is not implemented", .{});
    if (s.requests.len > 1) return gap(cx, 0, "several TABLES requests are not implemented", .{});
    const req = s.requests[0];
    const col = req.col orelse return gap(cx, req.line, "one-way frequency tables are not implemented (listing layout not verified)", .{});
    for ([_]usize{ req.row, col }) |c| {
        const v = ds.columns.items[c];
        if (v.type != .num or v.format != null) return gap(cx, req.line, "character or formatted TABLES variables are not implemented", .{});
        if (v.name.len > 10) return gap(cx, req.line, "listing columns for TABLES variable names longer than 10 characters are not verified", .{});
    }
    if (s.chisq and s.roles.fpc != .none) return gap(cx, 0, "CHISQ with RATE= or TOTAL= is not implemented", .{});
    if (s.roles.weight == null) return gap(cx, 0, "the listing without a WEIGHT statement is not verified", .{});
    // Raised before the per-group checks so that a BY request never reports a
    // group-specific data error first.
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group processing and listing layout are not verified", .{});
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    for (slices, groups) |slice, *group| {
        const d = try design.build(a, slice.rows, s.roles);
        if (d.kept.len == 0) return gap(cx, 0, "the result for an input without valid observations is not verified", .{});
        if (d.invalidFpc()) return cx.diags.fail(error.ParseError, 0, "PROC SURVEYFREQ: TOTAL= is less than the number of sampled clusters in a stratum", .{});
        if (d.bad_weight + d.bad_design > 0) return gap(cx, 0, "the listing for input with observations excluded by missing or nonpositive WEIGHT, STRATA or CLUSTER values is not verified", .{});
        if (d.singlePsuStratum()) return gap(cx, 0, "variance estimation for a stratum with a single cluster is not implemented", .{});
        const tb = try tabulate(a, d, slice.rows, req.row, col);
        if (tb.missing > 0) return gap(cx, 0, "the listing for missing TABLES values (Frequency Missing, MISSING levels) is not verified", .{});
        var rs: ?RaoScott = null;
        if (s.chisq) {
            rs = raoScott(d, tb) orelse return gap(cx, 0, "the Rao-Scott chi-square test for a table with a zero cell or fewer than two rows or columns is not implemented", .{});
            // Owned by STAT-SURVEYFREQ-015; only the reference's degenerate
            // table (test not computable) is verified here.
            if (rs.?.positive) return gap(cx, 0, "the Rao-Scott chi-square test with a positive design correction is not implemented", .{});
        }
        group.* = .{ .d = d, .table = tb, .rs = rs };
    }
    return groups;
}

fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
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
    const text = try std.fmt.allocPrint(a, "{d:." ++ std.fmt.comptimePrint("{d}", .{decimals}) ++ "}", .{x});
    // A negative rounding residue must not print as -0.0000.
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}

/// Right edges (1-based) of the crosstabulation columns: the two variables,
/// Frequency, Weighted Frequency, Std Err of Wgt Freq, Percent, Std Err of
/// Percent, Row Percent, Std Err of Row Percent.
const edges = [_]usize{ 10, 22, 36, 50, 64, 76, 90, 102, 117 };
const head1 = [_][]const u8{ "", "", "", "Weighted", "Std Err of", "", "Std Err of", "Row", "Std Err of" };
const head2 = [_][]const u8{ "", "", "Frequency", "Frequency", "Wgt Freq", "Percent", "Percent", "Percent", "Row Percent" };

fn tableLine(cx: proc.ProcCtx, a: A, out: *Out, width: usize, first: []const u8, second: []const u8, cell: Cell, row_pct: bool, se_pct: bool, se_row: bool) diag.Error!void {
    const b = try proc.line(a, width);
    const texts = [_][]const u8{
        first,                                                second,
        try std.fmt.allocPrint(a, "{d}", .{cell.count}),      try fixed(a, cell.wfreq, 5),
        try fixed(a, cell.sd_wfreq, 5),                       try fixed(a, cell.pct, 4),
        if (se_pct) try fixed(a, cell.se_pct, 4) else "",     if (row_pct) try fixed(a, cell.row_pct, 4) else "",
        if (se_row) try fixed(a, cell.se_row_pct, 4) else "",
    };
    for (texts, edges, 0..) |text, edge, k| {
        if (edge > width) break;
        // ponytail: fixed w.d columns as in the reference; larger magnitudes
        // need the template's width rules.
        if (text.len > @as(usize, if (k < 2) 10 else 12)) return gap(cx, 0, "listing columns for values wider than the verified layout are not implemented", .{});
        proc.putRight(b, edge, text);
    }
    try out.appendSlice(a, b);
    try out.append(a, '\n');
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, g: Group) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    const req = s.requests[0];
    const rname = ds.columns.items[req.row].name;
    const cname = ds.columns.items[req.col.?].name;
    const tb = g.table;
    const R = tb.row_levels.len;
    const C = tb.col_levels.len;
    var body: Out = .empty;
    try body.appendSlice(a, "\nThe SURVEYFREQ Procedure\n\n");
    if (!s.nosummary) {
        try centered(a, &body, "Data Summary", 36);
        try body.append(a, '\n');
        if (s.roles.strata.len > 0) try pair(a, &body, "Number of Strata", 22, try std.fmt.allocPrint(a, "{d}", .{g.d.strata()}), 14);
        if (s.roles.clusters.len > 0) try pair(a, &body, "Number of Clusters", 22, try std.fmt.allocPrint(a, "{d}", .{g.d.clusters()}), 14);
        try pair(a, &body, "Number of Observations", 22, try std.fmt.allocPrint(a, "{d}", .{g.d.kept.len}), 14);
        try pair(a, &body, "Sum of Weights", 22, try format.bestNum(a, g.d.sum_weights), 14);
        try body.appendSlice(a, "\n\n");
    }
    const width: usize = if (s.row_percent) 117 else 90;
    try centered(a, &body, try std.fmt.allocPrint(a, "Table of {s} by {s}", .{ rname, cname }), width);
    try body.appendSlice(a, " \n");
    for ([_][]const []const u8{ &head1, &head2 }, 0..) |heads, n| {
        const b = try proc.line(a, width);
        if (n == 1) {
            proc.putRight(b, edges[0], rname);
            proc.putRight(b, edges[1], cname);
        }
        for (heads, edges) |h, edge| if (edge <= width) proc.putRight(b, edge, h);
        try body.appendSlice(a, b);
        try body.append(a, '\n');
    }
    const rule = try a.alloc(u8, width + 1);
    @memset(rule, '-');
    rule[width] = '\n';
    try body.appendSlice(a, rule);
    for (0..R + 1) |r| {
        const rtext = if (r == R) "Total" else try format.bestNum(a, tb.row_levels[r]);
        for (0..C) |c| try tableLine(cx, a, &body, width, if (c == 0) rtext else "", try format.bestNum(a, tb.col_levels[c]), tb.at(r, c), s.row_percent and r < R, true, s.row_percent and r < R);
        try body.append(a, '\n');
        try tableLine(cx, a, &body, width, "", "Total", tb.at(r, C), s.row_percent and r < R, r < R, false);
        try body.appendSlice(a, rule);
    }
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
    for (groups) |group| try render(cx, out, s, group);
}

test {
    _ = @import("surveyfreq_tests.zig");
}
