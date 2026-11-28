//! PROC HPREG declarations, variable roles, observation selection and the
//! default least-squares fit without a SELECTION statement, SAS/STAT 15.4
//! physical pp.5028-5031 and 5038 (STAT-HPREG-001). The listing layout is the
//! one SAS 9.4 prints for invented data (tests/corpus/stat_hpreg_*.sas).
//! SELECTION, OUTPUT, PARTITION, PERFORMANCE and CODE belong to later HPREG and
//! shared high-performance tickets (STAT-HP-001..004): each is a D-009 gap
//! (rc 2) raised before any listing text is written, as is every display
//! outside the verified layout.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const reg_fit = @import("reg_fit.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Spec = struct {
    input: proc.ProcInput,
    data_name: []const u8,
    response: usize,
    /// MODEL effects in statement order: one input column per main effect.
    effects: []const usize = &.{},
    classes: []const usize = &.{},
    frequency: ?usize = null,
    weight: ?usize = null,
    ids: []const usize = &.{},
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    alpha: f64 = 0.05,
    seed: ?f64 = null,
    noprint: bool = false,

    pub fn isClass(self: Spec, index: usize) bool {
        return std.mem.indexOfScalar(usize, self.classes, index) != null;
    }
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC HPREG: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC HPREG: " ++ text, args);
}
fn oneOf(name: []const u8, list: []const []const u8) bool {
    for (list) |v| if (eq(name, v)) return true;
    return false;
}

/// Documented PROC HPREG options (Table 67.1) whose effect is not implemented.
const later_options = [_][]const u8{ "namelen", "noclprint", "fmtlibxml" };
/// Documented MODEL options (p.5031 onward): STAT-HPREG later tickets.
const later_model_options = [_][]const u8{ "clb", "include", "noint", "orderselect", "start", "stb", "tol", "vif" };
/// Statements owned by later HPREG / shared HP tickets.
const later_statements = [_][]const u8{ "selection", "output", "partition", "performance", "code" };

fn column(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    return ds.indexOf(t[i].text) orelse cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
}
fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    const c = try column(cx, ds, t, i);
    if (ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPREG: {s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .input = undefined, .data_name = "", .response = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
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
        } else if (eq(word, "alpha") and at(t, i + 1, .eq)) {
            // ALPHA= only affects CLB and OUTPUT confidence limits (gaps), so
            // the value is validated (0 < alpha < 1, p.5028) and recorded.
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const v = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, t[i + 2].line, "PROC HPREG: ALPHA= must be between 0 and 1", .{});
            s.alpha = v;
            i += 3;
        } else if (eq(word, "seed") and at(t, i + 1, .eq)) {
            // SEED= only drives random partitioning (PARTITION is a gap).
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            s.seed = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            i += 3;
        } else if (oneOf(word, &later_options)) {
            return gap(cx, t[i].line, "option {s} is not implemented", .{word});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, 0, "PROC HPREG: input dataset not found", .{});
    const upper = try std.ascii.allocUpperString(cx.arena, raw.name);
    s.data_name = if (std.mem.indexOfScalar(u8, upper, '.') != null) upper else try std.fmt.allocPrint(cx.arena, "WORK.{s}", .{upper});
    var folded: std.ArrayList(lex.Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(cx.arena, t[0..q]);
        try folded.append(cx.arena, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(cx.arena, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(cx.arena, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;
    var bys: by.Statements = .{};
    var model_seen = false;
    var classes: std.ArrayList(usize) = .empty;
    var effects: std.ArrayList(usize) = .empty;
    var ids: std.ArrayList(usize) = .empty;
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
            // p.5017: the CLASS statement must precede the MODEL statement.
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPREG: the CLASS statement must precede the MODEL statement", .{});
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| {
                if (at(t, j, .slash) or at(t, j, .lparen)) return gap(cx, t[j].line, "CLASS statement options are not implemented", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, classes.items, c) == null) try classes.append(cx.arena, c);
            }
        } else if (kw(t, i, "model")) {
            if (model_seen) return cx.diags.fail(error.ParseError, t[i].line, "PROC HPREG: only one MODEL statement is allowed", .{});
            model_seen = true;
            s.response = try numericColumn(cx, ds, t, i + 1, "response");
            if (!at(t, i + 2, .eq)) return invalid(cx, t, i + 2);
            var j = i + 3;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (!at(t, j, .name)) return gap(cx, t[j].line, "MODEL effects other than single variable names are not implemented", .{});
                const c = try column(cx, ds, t, j);
                if (std.mem.indexOfScalar(usize, effects.items, c) != null) return gap(cx, t[j].line, "repeated MODEL effect policy is not verified", .{});
                try effects.append(cx.arena, c);
            }
            if (at(t, j, .slash)) {
                j += 1;
                if (j == end) return invalid(cx, t, end);
                if (!at(t, j, .name)) return invalid(cx, t, j);
                if (oneOf(t[j].text, &later_model_options)) return gap(cx, t[j].line, "MODEL option {s} is not implemented", .{t[j].text});
                return invalid(cx, t, j);
            }
        } else if (kw(t, i, "freq")) {
            if (s.frequency != null) return gap(cx, t[i].line, "duplicate FREQ statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.frequency = try numericColumn(cx, ds, t, i + 1, "FREQ");
        } else if (kw(t, i, "weight")) {
            if (s.weight != null) return gap(cx, t[i].line, "duplicate WEIGHT statement policy is not verified", .{});
            if (end != i + 2) return invalid(cx, t, i + 2);
            s.weight = try numericColumn(cx, ds, t, i + 1, "WEIGHT");
        } else if (kw(t, i, "id")) {
            // p.5031: ID variables are copied to output data sets only; the
            // OUTPUT statement is a gap, so they are validated and recorded.
            if (end == i + 1) return invalid(cx, t, end);
            for (i + 1..end) |j| try ids.append(cx.arena, try column(cx, ds, t, j));
        } else if (kw(t, i, "by")) {
            // p.5029: with several BY statements only the last is used.
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "format")) {
            return gap(cx, t[i].line, "FORMAT statement (formatted CLASS levels) is not implemented", .{});
        } else if (at(t, i, .name) and oneOf(t[i].text, &later_statements)) {
            return gap(cx, t[i].line, "{s} statement is not implemented", .{t[i].text});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else if (!kw(t, i, "where")) return invalid(cx, t, i);
        i = end + 1;
    }
    if (!model_seen) return cx.diags.fail(error.ParseError, 0, "PROC HPREG: MODEL statement required", .{});
    s.classes = classes.items;
    s.effects = effects.items;
    s.ids = ids.items;
    if (s.isClass(s.response)) return cx.diags.fail(error.ParseError, 0, "PROC HPREG: the response variable cannot be a CLASS variable", .{});
    for (s.effects) |c| {
        if (c == s.response) return cx.diags.fail(error.ParseError, 0, "PROC HPREG: the response variable cannot be a MODEL effect", .{});
        if (!s.isClass(c) and ds.columns.items[c].type != .num) return cx.diags.fail(error.ParseError, 0, "PROC HPREG: character variable {s} must be a CLASS variable", .{ds.columns.items[c].name});
    }
    const pb = try bys.resolve(cx.arena, ds, cx.diags);
    const cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

fn missing(v: Value) bool {
    return switch (v) {
        .num => |x| !std.math.isFinite(x),
        .str => |text| std.mem.trim(u8, text, " ").len == 0,
    };
}
fn textLess(_: void, x: []const u8, y: []const u8) bool {
    return std.mem.order(u8, x, y) == .lt;
}

/// One analysis (BY group) after observation selection.
pub const Analysis = struct {
    read: usize,
    used: usize,
    freq_read: f64 = 0,
    freq_used: f64 = 0,
    /// Sorted levels per CLASS variable, in CLASS statement order.
    levels: []const []const []const u8,
    /// Parameter labels and design-column count (intercept first).
    labels: []const []const u8 = &.{},
    fit: ?reg_fit.Fit = null,
    /// Sum of frequencies (the observation count of the criteria) and of
    /// frequency * weight (the ASE denominator).
    n: f64 = 0,
    sum_fw: f64 = 0,
};

/// Observation selection, pp.5031, 5038: an observation with a missing
/// response, regressor or CLASS level, a FREQ value below 1 or missing, or a
/// nonpositive or missing WEIGHT is not used. FREQ values are truncated and
/// each observation is replicated that many times; WEIGHT is a precision
/// weight. CLASS effects use the GLM parameterization: one column per level,
/// sorted, the last aliased with the intercept.
pub fn analyze(cx: proc.ProcCtx, s: Spec, rows: []const []const Value) diag.Error!Analysis {
    const a = cx.arena;
    const ds = s.input.ds;
    var used: std.ArrayList(usize) = .empty;
    var freq: std.ArrayList(f64) = .empty;
    var result: Analysis = .{ .read = rows.len, .used = 0, .levels = &.{} };
    rows: for (rows, 0..) |row, r| {
        var f: f64 = 1;
        if (s.frequency) |c| {
            const v = row[c].num;
            f = if (std.math.isFinite(v)) @trunc(v) else 0;
            // ponytail: Sum of Frequencies Read adds the usable (>= 1) values.
            if (f >= 1) result.freq_read += f;
            if (f < 1) continue;
        }
        if (s.weight) |c| {
            const v = row[c].num;
            if (!(std.math.isFinite(v) and v > 0)) continue;
        }
        if (missing(row[s.response])) continue;
        for (s.effects) |c| if (missing(row[c])) continue :rows;
        for (s.classes) |c| if (missing(row[c])) continue :rows;
        try used.append(a, r);
        try freq.append(a, f);
        result.freq_used += f;
    }
    result.used = used.items.len;
    const levels = try a.alloc([]const []const u8, s.classes.len);
    for (s.classes, levels) |c, *out| {
        if (ds.columns.items[c].type != .char or ds.columns.items[c].format != null) return gap(cx, 0, "numeric or formatted CLASS variables are not implemented", .{});
        var list: std.ArrayList([]const u8) = .empty;
        for (used.items) |r| {
            const label = std.mem.trimEnd(u8, rows[r][c].str, " ");
            var found = false;
            for (list.items) |known| found = found or std.mem.eql(u8, known, label);
            if (!found) try list.append(a, label);
        }
        std.mem.sort([]const u8, list.items, {}, textLess);
        out.* = list.items;
    }
    result.levels = levels;
    if (used.items.len == 0) return result;
    var labels: std.ArrayList([]const u8) = .empty;
    try labels.append(a, "Intercept");
    for (s.effects) |c| {
        const nm = ds.columns.items[c].name;
        if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
            for (levels[k]) |label| try labels.append(a, try std.fmt.allocPrint(a, "{s} {s}", .{ nm, label }));
        } else try labels.append(a, nm);
    }
    result.labels = labels.items;
    const p = labels.items.len;
    var total: usize = 0;
    for (freq.items) |f| total += @intFromFloat(f);
    const x = try a.alloc(f64, total * p);
    const y = try a.alloc(f64, total);
    const w = try a.alloc(f64, total);
    var row_ix: usize = 0;
    for (used.items, freq.items) |r, f| {
        for (0..@as(usize, @intFromFloat(f))) |_| {
            const xr = x[row_ix * p ..][0..p];
            xr[0] = 1;
            var j: usize = 1;
            for (s.effects) |c| {
                if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
                    const v = std.mem.trimEnd(u8, rows[r][c].str, " ");
                    for (levels[k]) |label| {
                        xr[j] = if (std.mem.eql(u8, v, label)) 1 else 0;
                        j += 1;
                    }
                } else {
                    xr[j] = rows[r][c].num;
                    j += 1;
                }
            }
            y[row_ix] = rows[r][s.response].num;
            w[row_ix] = if (s.weight) |c| rows[r][c].num else 1;
            result.sum_fw += w[row_ix];
            row_ix += 1;
        }
    }
    result.n = @floatFromInt(total);
    result.fit = reg_fit.fit(a, x, y, total, p, if (s.weight != null) w else null) catch return gap(cx, 0, "this least-squares fit cannot be computed", .{});
    return result;
}

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    return std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
}
fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn left(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendSlice(a, text);
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
}
/// Centered table title; `header` tables get the " " spacer line SAS prints
/// above column headings.
fn title(a: A, out: *Out, text: []const u8, width: usize, spaced: bool) !void {
    if (width > text.len) try out.appendNTimes(a, ' ', (width - text.len) / 2);
    try out.appendSlice(a, text);
    try out.appendSlice(a, if (spaced) "\n \n" else "\n\n");
}
fn pvalue(a: A, p: f64) ![]const u8 {
    return if (p < 0.0001) "<.0001" else fixed(a, p, 4);
}

const Criteria = struct { mse: f64, rsq: f64, adj: f64, aic: f64, aicc: f64, sbc: f64, ase: f64 };

/// Fit criteria with n the sum of frequencies and p the parameter rank,
/// matching the SAS listing of the invented-data fixtures (AIC, AICC, SBC
/// as in GLMSELECT, pp.4365-4366; ASE = SSE / sum of frequency*weight).
fn criteria(an: Analysis) Criteria {
    const f = an.fit.?;
    const n = an.n;
    const p: f64 = @floatFromInt(f.rank);
    const base = n * @log(f.sse / n);
    const st = f.modelStats(true);
    return .{
        .mse = f.mse,
        .rsq = st.r_square,
        .adj = st.adj_r_square,
        .aic = base + 2 * p + n + 2,
        .aicc = base + n * (n + p) / (n - p - 2),
        .sbc = base + p * @log(n),
        .ase = f.sse / an.sum_fw,
    };
}

fn inRange(v: f64, lo: f64, hi: f64) bool {
    return @abs(v) >= lo and @abs(v) < hi;
}

/// Listing boundary: values and shapes outside the verified layout are
/// raised before any text is written.
fn check(cx: proc.ProcCtx, s: Spec, an: Analysis) diag.Error!void {
    if (an.used == 0) return gap(cx, 0, "the result for a BY group or data set without usable observations is not verified", .{});
    const f = an.fit.?;
    for (an.labels) |label| if (label.len > 20) return gap(cx, 0, "parameter names longer than 20 characters (NAMELEN=) are not implemented", .{});
    // Only the GLM-parameterization alias of each CLASS effect's last level.
    var j: usize = 1;
    for (s.effects) |c| {
        if (std.mem.indexOfScalar(usize, s.classes, c)) |k| {
            for (an.levels[k], 0..) |_, level| {
                if (f.aliased[j] != (level + 1 == an.levels[k].len)) return gap(cx, 0, "linearly dependent effects are not implemented", .{});
                j += 1;
            }
        } else {
            if (f.aliased[j]) return gap(cx, 0, "linearly dependent effects are not implemented", .{});
            j += 1;
        }
    }
    if (f.aliased[0] or f.rank < 2) return gap(cx, 0, "an intercept-only fit is not verified", .{});
    if (f.df_error < 1 or an.n < @as(f64, @floatFromInt(f.rank)) + 3) return gap(cx, 0, "fit criteria without enough error degrees of freedom are not verified", .{});
    const st = f.modelStats(true);
    const x = criteria(an);
    // Mean squares and criteria switch to more significant digits below
    // 0.01 in the SAS listing; only the fixed 5-decimal range is verified.
    for ([_]f64{ st.ms_model, x.mse, @sqrt(x.mse), x.rsq, x.adj, x.aic, x.aicc, x.sbc, x.ase }) |v| if (!inRange(v, 0.01, 1e6)) return gap(cx, 0, "display of mean squares or fit criteria outside [0.01, 1e6) is not verified", .{});
    for ([_]f64{ st.ss_model, f.sse, f.sst }) |v| if (!(v < 1e8 and v >= 0.001)) return gap(cx, 0, "display of sums of squares outside [0.001, 1e8) is not verified", .{});
    if (!(st.f_value < 10000)) return gap(cx, 0, "display of an F value of 10000 or more is not verified", .{});
    for (f.coefficients, f.se, f.aliased) |b, se, al| if (!al) {
        if (!(inRange(b, 0.0001, 1e6) and inRange(se, 0.0001, 1e6) and @abs(b / se) < 10000)) return gap(cx, 0, "display of parameter estimates outside [0.0001, 1e6) is not verified", .{});
    };
}

fn infoTable(a: A, out: *Out, heading: []const u8, lines: []const [2][]const u8) !void {
    var lw: usize = 0;
    var vw: usize = 0;
    for (lines) |l| {
        lw = @max(lw, l[0].len);
        vw = @max(vw, l[1].len);
    }
    try title(a, out, heading, lw + 4 + vw, false);
    for (lines) |l| {
        try left(a, out, l[0], lw + 4);
        try left(a, out, l[1], vw);
        try out.append(a, '\n');
    }
}

fn header(cx: proc.ProcCtx, out: *Out, s: Spec) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    try out.appendSlice(a, "\nThe HPREG Procedure\n\n");
    // opensas computes on one thread, so it reports 1 where the SAS reference
    // machine reports its own thread count; thread semantics: STAT-HP-002.
    try out.appendSlice(a, "      Performance Information\n\nExecution Mode       Single-Machine\nNumber of Threads    1             \n\n\n");
    const dw = @max(4, s.data_name.len);
    try title(a, out, "Data Access Information", dw + 32, true);
    try left(a, out, "Data", dw);
    try out.appendSlice(a, "    Engine    Role     Path\n\n");
    try left(a, out, s.data_name, dw);
    try out.appendSlice(a, "    V9        Input    On Client\n\n\n");
    var lines: std.ArrayList([2][]const u8) = .empty;
    try lines.append(a, .{ "Data Source", s.data_name });
    try lines.append(a, .{ "Dependent Variable", ds.columns.items[s.response].name });
    if (s.weight) |c| try lines.append(a, .{ "Weight Variable", ds.columns.items[c].name });
    if (s.frequency) |c| try lines.append(a, .{ "Frequency Variable", ds.columns.items[c].name });
    if (s.classes.len > 0) try lines.append(a, .{ "Class Parameterization", "GLM" });
    try infoTable(a, out, "Model Information", lines.items);
}

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, an: Analysis) !void {
    const a = cx.arena;
    const ds = s.input.ds;
    try out.print(a, "Number of Observations Read{d:>16}\nNumber of Observations Used{d:>16}\n", .{ an.read, an.used });
    if (s.frequency != null) try out.print(a, "Sum of Frequencies Read    {d:>16}\nSum of Frequencies Used    {d:>16}\n", .{ @as(u64, @intFromFloat(an.freq_read)), @as(u64, @intFromFloat(an.freq_used)) });
    if (s.classes.len > 0) {
        var name_width: usize = 5;
        var value_width: usize = 6;
        const values = try a.alloc([]const u8, s.classes.len);
        for (s.classes, an.levels, values) |c, levels, *text| {
            name_width = @max(name_width, ds.columns.items[c].name.len);
            var joined: Out = .empty;
            for (levels) |label| try joined.print(a, "{s} ", .{label});
            text.* = joined.items;
            value_width = @max(value_width, text.len);
        }
        try out.appendSlice(a, "\n\n");
        try title(a, out, "Class Level Information", name_width + 14 + value_width, true);
        try left(a, out, "Class", name_width);
        try out.appendSlice(a, "    Levels    Values\n\n");
        for (s.classes, an.levels, values) |c, levels, text| {
            try left(a, out, ds.columns.items[c].name, name_width);
            try out.print(a, "{d:>10}    ", .{levels.len});
            try left(a, out, text, value_width);
            try out.append(a, '\n');
        }
    }
    try out.print(a, "\n\n           Dimensions\n\nNumber of Effects   {d:>12}\nNumber of Parameters{d:>12}\n\n\n", .{ s.effects.len + 1, an.labels.len });
    const f = an.fit.?;
    const st = f.modelStats(true);
    const x = criteria(an);
    try title(a, out, "Analysis of Variance", 76, true);
    try out.appendSlice(a, "                                  Sum of           Mean\nSource                 DF        Squares         Square    F Value    Pr > F\n\n");
    try out.print(a, "Model          {d:>10}", .{st.df_model});
    try right(a, out, try fixed(a, st.ss_model, 5), 15);
    try right(a, out, try fixed(a, st.ms_model, 5), 15);
    try right(a, out, try fixed(a, st.f_value, 2), 11);
    try right(a, out, try pvalue(a, st.p_value), 10);
    try out.print(a, "\nError          {d:>10}", .{f.df_error});
    try right(a, out, try fixed(a, f.sse, 5), 15);
    try right(a, out, try fixed(a, f.mse, 5), 15);
    try out.appendNTimes(a, ' ', 21);
    try out.print(a, "\nCorrected Total{d:>10}", .{st.df_total});
    try right(a, out, try fixed(a, f.sst, 5), 15);
    try out.appendNTimes(a, ' ', 36);
    try out.appendSlice(a, "\n\n\n");
    const lines = [_]struct { []const u8, f64 }{ .{ "Root MSE", @sqrt(x.mse) }, .{ "R-Square", x.rsq }, .{ "Adj R-Sq", x.adj }, .{ "AIC", x.aic }, .{ "AICC", x.aicc }, .{ "SBC", x.sbc }, .{ "ASE", x.ase } };
    for (lines) |line| {
        try left(a, out, line[0], 8);
        try right(a, out, try fixed(a, line[1], 5), 15);
        try out.append(a, '\n');
    }
    try out.appendSlice(a, "\n\n");
    // The Parameter column widens to the longest parameter label.
    var pw: usize = 9;
    for (an.labels) |label| pw = @max(pw, label.len);
    try title(a, out, "Parameter Estimates", pw + 61, true);
    try out.appendNTimes(a, ' ', pw + 30);
    try out.appendSlice(a, "Standard\n");
    try left(a, out, "Parameter", pw);
    try out.appendSlice(a, "    DF        Estimate           Error    t Value    Pr > |t|\n\n");
    for (an.labels, 0..) |label, j| {
        try left(a, out, label, pw);
        if (f.aliased[j]) {
            try out.appendSlice(a, "     0               0               .        .         .    \n");
            continue;
        }
        try out.appendSlice(a, "     1");
        try right(a, out, try fixed(a, f.coefficients[j], 6), 16);
        try right(a, out, try fixed(a, f.se[j], 6), 16);
        try right(a, out, try fixed(a, f.coefficientT(j), 2), 11);
        try right(a, out, try pvalue(a, f.coefficientP(j)), 12);
        try out.append(a, '\n');
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, t);
    if (cx.graphics) |graphics| if (graphics.enabled == true) return gap(cx, 0, "graphs under ODS GRAPHICS are not implemented", .{});
    if (s.effects.len == 0) return gap(cx, 0, "an intercept-only MODEL statement is not verified", .{});
    const ds = s.input.ds;
    const slices = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    if (slices.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    const results = try a.alloc(Analysis, slices.len);
    for (slices, results) |slice, *an| {
        an.* = try analyze(cx, s, slice.rows);
        if (!s.noprint) try check(cx, s, an.*);
    }
    if (s.noprint) return;
    var body: Out = .empty;
    try header(cx, &body, s);
    for (slices, results) |slice, an| {
        if (s.by_cols.len > 0) {
            try body.append(a, '\n');
            for (s.by_cols, 0..) |c, k| try body.print(a, "{s}{s}={s}", .{ if (k > 0) " " else "", ds.columns.items[c].name, try proc.cellText(a, slice.rows[0][c]) });
            try body.appendSlice(a, "\n\nThe HPREG Procedure\n\n");
        } else try body.appendSlice(a, "\n\n");
        try render(cx, &body, s, an);
    }
    try out.appendSlice(a, body.items);
}

test {
    _ = @import("hpreg_tests.zig");
}
