//! PROC MULTTEST declarations, variable roles, observation selection and the
//! default listing for the unstratified Cochran-Armitage Z-score test with one
//! closed-form adjustment, SAS/STAT 15.4 physical pp.6897-6912 and 6930.
//! Resampling adjustments depend on the SAS random stream and every other
//! documented feature is owned by a later MULTTEST ticket: each is a D-009 gap
//! (rc 2) raised before any listing text is produced, so a partial page can
//! never be taken for a full analysis.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const fns = @import("../functions.zig");
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Adjustment = enum {
    bonferroni,
    sidak,
    hochberg,
    pub fn label(self: Adjustment) []const u8 {
        return switch (self) {
            .bonferroni => "Bonferroni",
            .sidak => "Sidak",
            .hochberg => "Hochberg",
        };
    }
};
pub const Contrast = struct { label: []const u8, values: []const f64 };
pub const StrataWeight = enum { samplesize, harmonic, equal };

pub const Spec = struct {
    input: proc.ProcInput,
    class: usize,
    /// TEST CA variables, in statement order.
    tests: []const usize = &.{},
    contrasts: []const Contrast = &.{},
    strata: ?usize = null,
    strata_weight: StrataWeight = .samplesize,
    frequency: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    adjustments: []const Adjustment = &.{},
    noprint: bool = false,
    notables: bool = false,
    /// NSAMPLE= and SEED= only parameterize resampling, which is a gap.
    nsample: ?f64 = null,
    seed: ?f64 = null,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC MULTTEST: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC MULTTEST: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Resampling adjustments: reproducing them needs the SAS random stream.
const resampling = [_][]const u8{ "bootstrap", "boot", "permutation", "perm", "stepboot", "stepperm", "fdrboot", "fdrperm" };
/// Documented PROC MULTTEST statement options (Table 86.1) owned by later
/// MULTTEST tickets (002-008).
const later_options = [_][]const u8{ "inpvalues", "out", "outperm", "outsamp", "order", "plots", "plot", "nopvalue", "nozeros", "noz", "pdata", "holm", "stepbon", "stepsid", "hommel", "hom", "fisher_c", "fic", "stouffer", "liptak", "fdr", "bh", "lsu", "dependentfdr", "dfdr", "by", "adaptivefdr", "afdr", "adaptiveholm", "aholm", "adaptivehochberg", "ahoc", "pfdr", "ptruenull", "pcorrections", "nocenter", "center", "rank", "epsilon", "fdrbootmethod", "boundary", "sidak_c" };
const other_tests = [_][]const u8{ "fisher", "ft", "mean", "peto" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (at(t, i.*, .minus)) {
        sign = -1;
        i.* += 1;
    } else if (at(t, i.*, .plus)) i.* += 1;
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const x = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return sign * x;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .class = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var adjustments: std.ArrayList(Adjustment) = .empty;
    var resample_line: ?usize = null;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
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
        } else if (eq(word, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(word, "notables")) {
            s.notables = true;
            i += 1;
        } else if ((eq(word, "nsample") or eq(word, "n") or eq(word, "seed") or eq(word, "s")) and at(t, i + 1, .eq)) {
            i += 2;
            const x = try number(cx, t, &i);
            if (x < 0 or x != @floor(x)) return cx.diags.fail(error.ParseError, t[i - 1].line, "PROC MULTTEST: {s}= requires a nonnegative integer", .{word});
            if (eq(word, "seed") or eq(word, "s")) s.seed = x else s.nsample = x;
        } else if (oneOf(word, &.{ "bonferroni", "bon" }) or oneOf(word, &.{ "sidak", "sid" }) or oneOf(word, &.{ "hochberg", "hoc" })) {
            const adj: Adjustment = if (eq(word[0..1], "b")) .bonferroni else if (eq(word[0..1], "s")) .sidak else .hochberg;
            if (std.mem.indexOfScalar(Adjustment, adjustments.items, adj) == null) try adjustments.append(cx.arena, adj);
            i += 1;
        } else if (oneOf(word, &resampling)) {
            if (resample_line == null) resample_line = t[i].line;
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    if (resample_line) |line| return gap(cx, line, "resampling adjustments (BOOTSTRAP, PERMUTATION and their step-down and FDR forms) need the SAS random stream and are not implemented", .{});
    s.adjustments = adjustments.items;
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC MULTTEST: input dataset not found", .{});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var class_seen = false;
    var tests: std.ArrayList(usize) = .empty;
    var contrasts: std.ArrayList(Contrast) = .empty;
    var test_seen = false;
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
            if (class_seen) return gap(cx, t[i].line, "duplicate CLASS statement policy is not verified", .{});
            class_seen = true;
            s.class = try column(cx, ds, t, i + 1);
            if (end != i + 2) {
                if (at(t, i + 2, .slash) and kw(t, i + 3, "truncate") and end == i + 4) return gap(cx, t[i].line, "CLASS option TRUNCATE is not implemented", .{});
                // The CLASS statement names a single variable (p.6909).
                return invalid(cx, t, i + 2);
            }
        } else if (kw(t, i, "test")) {
            if (test_seen) return gap(cx, t[i].line, "several TEST statements are not implemented", .{});
            test_seen = true;
            if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
            if (oneOf(t[i + 1].text, &other_tests)) return gap(cx, t[i].line, "TEST {s} is not implemented", .{t[i + 1].text});
            if (!kw(t, i + 1, "ca")) return invalid(cx, t, i + 1);
            if (!at(t, i + 2, .lparen) or end < i + 4 or !at(t, end - 1, .rparen)) return invalid(cx, t, i + 2);
            var j = i + 3;
            while (j < end - 1) {
                if (at(t, j, .slash)) return gap(cx, t[j].line, "TEST statement options are not implemented", .{});
                const line = t[j].line;
                const names = try lists.next(cx.arena, ds, t[0 .. end - 1], &j, cx.diags);
                for (names) |n| {
                    const c = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, line, "Variable {s} not found.", .{n});
                    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, line, "PROC MULTTEST: TEST variable {s} must be numeric", .{n});
                    try tests.append(cx.arena, c);
                }
            }
            if (tests.items.len == 0) return invalid(cx, t, end - 1);
        } else if (kw(t, i, "contrast")) {
            if (!at(t, i + 1, .string)) return invalid(cx, t, i + 1);
            // The label holds at most 21 characters (p.6910).
            if (t[i + 1].text.len > 21) return gap(cx, t[i].line, "CONTRAST labels longer than 21 characters are not verified", .{});
            var values: std.ArrayList(f64) = .empty;
            var j = i + 2;
            while (j < end) try values.append(cx.arena, try number(cx, t, &j));
            if (values.items.len == 0) return invalid(cx, t, end);
            try contrasts.append(cx.arena, .{ .label = t[i + 1].text, .values = values.items });
        } else if (kw(t, i, "strata")) {
            if (s.strata != null) return gap(cx, t[i].line, "duplicate STRATA statement policy is not verified", .{});
            s.strata = try column(cx, ds, t, i + 1);
            if (end != i + 2) {
                if (end != i + 6 or !at(t, i + 2, .slash) or !kw(t, i + 3, "weight") or !at(t, i + 4, .eq) or !at(t, i + 5, .name)) return invalid(cx, t, i + 2);
                const w = t[i + 5].text;
                s.strata_weight = if (eq(w, "samplesize")) .samplesize else if (eq(w, "harmonic")) .harmonic else if (eq(w, "equal")) .equal else return invalid(cx, t, i + 5);
            }
        } else if (kw(t, i, "freq")) {
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.frequency = try column(cx, ds, t, i + 1);
            if (ds.columns.items[s.frequency.?].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC MULTTEST: FREQ variable {s} must be numeric", .{t[i + 1].text});
        } else if (kw(t, i, "id")) {
            // ID requires an INPVALUES= data set (p.6911), itself a gap.
            return gap(cx, t[i].line, "ID statement (INPVALUES= input) is not implemented", .{});
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted CLASS levels) is not implemented", .{});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!class_seen) return cx.diags.fail(error.ParseError, 0, "PROC MULTTEST: CLASS statement required unless INPVALUES= is specified", .{});
    if (!test_seen) return cx.diags.fail(error.ParseError, 0, "PROC MULTTEST: TEST statement required", .{});
    s.tests = tests.items;
    s.contrasts = contrasts.items;
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Per test variable and CLASS level: frequency-weighted number of nonmissing
/// observations and of nonzero responses.
pub const Selected = struct {
    /// One representative CLASS value per level, ascending.
    levels: []const Value,
    /// [variable][level]
    totals: []const []f64,
    successes: []const []f64,
    read: usize,
    /// Observations kept after the CLASS, STRATA and FREQ rules.
    used: usize,
    /// A response other than 0 or 1 was seen (its treatment is unverified).
    nonbinary: bool,
};

fn missingValue(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}
fn valueLess(_: void, x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a < y.num,
        .str => |a| std.mem.order(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")) == .lt,
    };
}
fn valueEqual(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| a == y.num,
        .str => |a| std.mem.eql(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")),
    };
}

/// Observation selection, physical pp.6911 and 6930: a missing CLASS or
/// STRATA value removes the observation; a FREQ value that is missing or
/// below 1 removes it and only its integer part is used; a missing test value
/// removes the observation for that variable only. Levels are ordered
/// ascending by unformatted value.
pub fn select(a: A, s: Spec, rows: []const []const Value) !Selected {
    var kept: std.ArrayList(usize) = .empty;
    var levels: std.ArrayList(Value) = .empty;
    const weights = try a.alloc(f64, rows.len);
    for (rows, 0..) |row, r| {
        if (missingValue(row[s.class])) continue;
        if (s.strata) |c| if (missingValue(row[c])) continue;
        weights[r] = 1;
        if (s.frequency) |c| {
            const f = row[c].num;
            if (std.math.isNan(f) or f < 1) continue;
            weights[r] = @floor(f);
        }
        try kept.append(a, r);
        var known = false;
        for (levels.items) |level| known = known or valueEqual(level, row[s.class]);
        if (!known) try levels.append(a, row[s.class]);
    }
    std.mem.sort(Value, levels.items, {}, valueLess);
    const totals = try a.alloc([]f64, s.tests.len);
    const successes = try a.alloc([]f64, s.tests.len);
    var nonbinary = false;
    for (s.tests, totals, successes) |c, *m, *x| {
        m.* = try a.alloc(f64, levels.items.len);
        x.* = try a.alloc(f64, levels.items.len);
        @memset(m.*, 0);
        @memset(x.*, 0);
        for (kept.items) |r| {
            const y = rows[r][c].num;
            if (std.math.isNan(y)) continue;
            if (y != 0 and y != 1) nonbinary = true;
            var g: usize = 0;
            while (!valueEqual(levels.items[g], rows[r][s.class])) g += 1;
            m.*[g] += weights[r];
            if (y != 0) x.*[g] += weights[r];
        }
    }
    return .{ .levels = levels.items, .totals = totals, .successes = successes, .read = rows.len, .used = kept.items.len, .nonbinary = nonbinary };
}

/// Two-tailed unstratified Cochran-Armitage Z-score p-value with the
/// hypergeometric variance and no continuity correction, physical p.6913:
/// N = sum t_g (S_g - m_g p), V = m/(m-1) p(1-p) sum m_g (t_g - tbar)^2,
/// p-value 2 min(P, 1-P) for the upper-tailed normal P. A zero denominator
/// (including m <= 1) gives 1.
pub fn cochranArmitage(totals: []const f64, successes: []const f64, t: []const f64) f64 {
    var m: f64 = 0;
    var x: f64 = 0;
    var mt: f64 = 0;
    for (totals, successes, t) |mg, xg, tg| {
        m += mg;
        x += xg;
        mt += mg * tg;
    }
    if (m <= 1) return 1;
    const p = x / m;
    const tbar = mt / m;
    var n: f64 = 0;
    var ss: f64 = 0;
    for (totals, successes, t) |mg, xg, tg| {
        n += tg * (xg - mg * p);
        ss += mg * (tg - tbar) * (tg - tbar);
    }
    const v = m / (m - 1) * p * (1 - p) * ss;
    if (!(v > 0)) return 1;
    const upper = 1 - fns.distCdf(.normal, n / @sqrt(v), &.{}).?;
    return 2 * @min(upper, 1 - upper);
}

/// Closed-form adjustments, physical pp.6923-6926: Bonferroni min(1, m p),
/// Sidak 1 - (1 - p)^m, and Hochberg's step-up
/// p~(m) = p(m), p~(i) = min(p~(i+1), (m - i + 1) p(i)).
pub fn adjust(a: A, method: Adjustment, raw: []const f64) ![]f64 {
    const out = try a.alloc(f64, raw.len);
    const m: f64 = @floatFromInt(raw.len);
    switch (method) {
        .bonferroni => for (raw, out) |p, *q| {
            q.* = @min(1, m * p);
        },
        .sidak => for (raw, out) |p, *q| {
            q.* = 1 - std.math.pow(f64, 1 - p, m);
        },
        .hochberg => {
            const order = try a.alloc(usize, raw.len);
            for (order, 0..) |*o, k| o.* = k;
            std.mem.sort(usize, order, raw, struct {
                fn less(p: []const f64, x: usize, y: usize) bool {
                    return p[x] < p[y];
                }
            }.less);
            var previous: f64 = 1;
            var k = raw.len;
            while (k > 0) {
                k -= 1;
                const factor: f64 = @floatFromInt(raw.len - k);
                previous = if (k + 1 == raw.len) raw[order[k]] else @min(previous, factor * raw[order[k]]);
                out[order[k]] = previous;
            }
        },
    }
    return out;
}

pub const Group = struct { selected: Selected, raw: []f64, adjusted: []f64 };

/// Per-BY-group selections and p-values; raises every execution boundary
/// before any text exists.
pub fn plan(cx: proc.ProcCtx, s: Spec) diag.Error![]Group {
    const a = cx.arena;
    const ds = s.input.ds;
    if (s.strata != null) return gap(cx, 0, "stratified tests (STRATA statement) are not implemented", .{});
    if (s.contrasts.len == 0) return gap(cx, 0, "default contrast coefficients and their label are not verified; specify a CONTRAST statement", .{});
    if (s.contrasts.len > 1) return gap(cx, 0, "several CONTRAST statements are not implemented", .{});
    if (s.adjustments.len == 0) return gap(cx, 0, "the listing without a p-value adjustment is not verified", .{});
    if (s.adjustments.len > 1) return gap(cx, 0, "the listing for several p-value adjustments is not verified", .{});
    // Raised before the per-group checks so that a BY request never reports a
    // group-specific data error first.
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group processing and listing layout are not verified", .{});
    if (!s.notables and !s.noprint) return gap(cx, 0, "the variable tabulations are not implemented; specify NOTABLES", .{});
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const groups = try a.alloc(Group, slices.len);
    for (slices, groups) |slice, *group| {
        const sel = try select(a, s, slice.rows);
        const c = s.contrasts[0];
        if (sel.levels.len == 0) return gap(cx, 0, "the result for an input without usable observations is not verified", .{});
        if (c.values.len != sel.levels.len) return cx.diags.fail(error.ParseError, 0, "PROC MULTTEST: CONTRAST {s} has {d} coefficients for {d} CLASS levels", .{ c.label, c.values.len, sel.levels.len });
        if (sel.nonbinary) return gap(cx, 0, "TEST CA responses other than 0 and 1 are not verified", .{});
        const raw = try a.alloc(f64, s.tests.len);
        for (raw, sel.totals, sel.successes) |*p, m, x| p.* = cochranArmitage(m, x, c.values);
        group.* = .{ .selected = sel, .raw = raw, .adjusted = try adjust(a, s.adjustments[0], raw) };
    }
    return groups;
}

fn padRight(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn padLeft(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
fn centered(a: A, out: *Out, text: []const u8, start: usize, width: usize) !void {
    try out.appendNTimes(a, ' ', start + (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
/// PVALUE6.4.
fn pvalue(a: A, x: f64) ![]const u8 {
    return if (x < 0.0001) "<.0001" else std.fmt.allocPrint(a, "{d:.4}", .{x});
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, g: Group) diag.Error!void {
    const a = cx.arena;
    const ds = s.input.ds;
    // Execution boundary: only the listing shape proven against the SAS
    // reference is produced.
    const class = ds.columns.items[s.class];
    if (class.type != .char or class.format != null) return gap(cx, 0, "numeric or formatted CLASS levels are not implemented", .{});
    const c = s.contrasts[0];
    // ponytail: column widths are verified for the reference's shape (label up
    // to the 8-character heading, levels and coefficients inside 12 columns);
    // wider text needs the template widths.
    if (c.label.len > 8) return gap(cx, 0, "listing columns for CONTRAST labels longer than 8 characters are not verified", .{});
    for (c.values) |v| if (v != @floor(v) or @abs(v) >= 1e6) return gap(cx, 0, "display of non-integer CONTRAST coefficients is not verified", .{});
    var body: Out = .empty;
    try body.appendSlice(a, "\nThe Multtest Procedure\n\n");
    try centered(a, &body, "Model Information", 0, 64);
    try body.append(a, '\n');
    const info = [_][2][]const u8{
        .{ "Test for discrete variables", "Cochran-Armitage" },
        .{ "Z-score approximation used", "Everywhere" },
        .{ "Continuity correction", "0" },
        .{ "Tails for discrete tests", "Two-tailed" },
        .{ "Strata weights", "None" },
        // ponytail: the closed-form adjustment names are the guide's (Outputs
        // 86.3.1 and 86.5.x); the SAS reference listing itself shows Bootstrap.
        .{ "P-value adjustment", s.adjustments[0].label() },
    };
    for (info) |row| {
        try padLeft(a, &body, row[0], 44);
        try padLeft(a, &body, row[1], 20);
        try body.append(a, '\n');
    }
    const k = g.selected.levels.len;
    try body.appendSlice(a, "\n\n");
    try centered(a, &body, "Contrast Coefficients", 0, 8 + 16 * k);
    try body.appendSlice(a, " \n");
    try centered(a, &body, class.name, 12, 16 * k - 4);
    try body.appendSlice(a, " \nContrast");
    for (g.selected.levels) |level| {
        const text = std.mem.trimEnd(u8, level.str, " ");
        if (text.len > 12) return gap(cx, 0, "listing columns for CLASS levels longer than 12 characters are not verified", .{});
        try padRight(a, &body, text, 16);
    }
    try body.appendSlice(a, "\n\n");
    try padLeft(a, &body, c.label, 8);
    for (c.values) |v| try padRight(a, &body, try std.fmt.allocPrint(a, "{d}", .{v}), 16);
    var name_width: usize = 8;
    for (s.tests) |col| name_width = @max(name_width, ds.columns.items[col].name.len);
    try body.appendSlice(a, "\n\n\n");
    try centered(a, &body, "p-Values", 0, name_width + 4 + 8 + 14 + 14);
    try body.appendSlice(a, " \n");
    try padLeft(a, &body, "Variable", name_width + 4);
    try body.appendSlice(a, "Contrast");
    try padRight(a, &body, "Raw", 14);
    try padRight(a, &body, s.adjustments[0].label(), 14);
    try body.appendSlice(a, "\n\n");
    for (s.tests, g.raw, g.adjusted) |col, raw, adjusted| {
        try padLeft(a, &body, ds.columns.items[col].name, name_width + 4);
        try padLeft(a, &body, c.label, 8);
        try padRight(a, &body, try pvalue(a, raw), 14);
        try padRight(a, &body, try pvalue(a, adjusted), 14);
        try body.append(a, '\n');
    }
    try out.appendSlice(a, body.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    const groups = try plan(cx, s);
    if (s.noprint) return;
    if (groups.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    for (groups) |group| try render(cx, out, s, group);
}

test {
    _ = @import("multtest_tests.zig");
}
