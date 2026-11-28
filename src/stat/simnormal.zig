//! PROC SIMNORMAL / SIMNORM (SAS/STAT 15.4 ch.113, PDF pp.9353-9370):
//! PROC statement options, VAR and BY, TYPE=COV / TYPE=CORR input and the
//! unconditional simulation Y = mu + L W (V = L L', W ~ N(0, I)) written to
//! the OUT= data set (STAT-SIMNORMAL-001). The procedure prints nothing
//! (p.9353). CONDITION (STAT-SIMNORMAL-003/004) and the input forms whose SAS
//! behaviour is not verified are loud D-009 gaps.
//!
//! Random stream (verified against SAS 9.4 runs, best16. dumps): the classic
//! RANUNI generator x <- 397204094 x mod (2^31-1) started at SEED=; every
//! N(0,1) component is sqrt(-2 log u1) cos(2 pi u2) from two successive
//! uniforms (the DATA step RANNOR stream); a realization draws one component
//! per VAR variable in VAR order, also for singular columns. OUTSEED writes
//! the generator state before the realization (first value = SEED=). The
//! stream continues across BY groups; SEEDBY restarts it per group.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const fns = @import("../functions.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const lists = @import("variable_lists.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;

pub const Spec = struct {
    data: ?[]const u8 = null,
    out: ?[]const u8 = null,
    out_opts: []const lex.Token = &.{},
    /// null = NUMREAL= not given (verified default 100 with a NOTE).
    numreal: ?f64 = null,
    /// null = SEED= not given or nonpositive (clock seed with a NOTE).
    seed: ?u64 = null,
    seedby: bool = false,
    outseed: bool = false,
    outcond: bool = false,
    singular1: f64 = 1e-8,
    singular2: f64 = 1e-8,
    /// Line of a SINGULAR1=0 / SINGULAR2=0 (reset WARNING, emitted in run).
    reset1: ?usize = null,
    reset2: ?usize = null,
    /// Raw VAR statement bodies, resolved against the input in run.
    var_toks: []const []const lex.Token = &.{},
    var_given: bool = false,
    bys: by.Statements = .{},
    by_names: []const []const u8 = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

fn at(t: []const lex.Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn line(t: []const lex.Token, i: usize) usize {
    return if (i < t.len) t[i].line else 0;
}

/// Verified (SAS 9.4) syntax-error text for an unknown PROC option.
fn syntax(cx: proc.ProcCtx) diag.Error {
    try cx.diags.numberedError("22-322", "Syntax error, expecting one of the following: ;, DATA, N, NUMREAL, OUT, OUTC, OUTCOND, OUTSEED, SEED, SEEDBY, SING1, SING2, SINGULAR1, SINGULAR2.");
    try cx.diags.numberedError("76-322", "Syntax error, statement will be ignored.");
    return error.ParseError;
}

fn invalid(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC SIMNORMAL: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}

/// `name` or `libref.name`, with optional data set options in parentheses.
fn member(cx: proc.ProcCtx, t: []const lex.Token, i: usize, into: *?[]const u8, opts: *[]const lex.Token) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    var j = i + 1;
    var name = t[i].text;
    if (at(t, j, .dot)) {
        if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[j + 1].text });
        j += 2;
    }
    if (at(t, j, .lparen)) {
        const k = proc.skipParen(t, j);
        opts.* = t[j + 1 .. k - 1];
        j = k;
    }
    into.* = name;
    return j;
}

/// A signed numeric literal after `OPTION=`.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    var neg = false;
    if (at(t, i.*, .minus) or at(t, i.*, .plus)) {
        neg = at(t, i.*, .minus);
        i.* += 1;
    }
    if (!at(t, i.*, .number)) return invalid(cx, t, i.*);
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return invalid(cx, t, i.*);
    i.* += 1;
    return if (neg) -v else v;
}

/// `WORK.NAME` for a one-level member name, upper case (SAS log form).
fn qualified(a: A, name: []const u8) ![]const u8 {
    const up = try std.ascii.allocUpperString(a, name);
    return if (std.mem.indexOfScalar(u8, name, '.') == null) try std.fmt.allocPrint(a, "WORK.{s}", .{up}) else up;
}

/// SAS E-notation with two decimals and a two-digit exponent (1.00E-08).
fn sciText(a: A, x: f64) ![]const u8 {
    if (x == 0) return "0.00E+00";
    var e: i32 = @intFromFloat(@floor(std.math.log10(@abs(x))));
    var m = x / std.math.pow(f64, 10, @floatFromInt(e));
    if (@abs(@round(m * 100) / 100) >= 10) {
        e += 1;
        m /= 10;
    }
    const ae: u32 = @intCast(@abs(e));
    return std.fmt.allocPrint(a, "{d:.2}E{s}{d:0>2}", .{ m, if (e < 0) "-" else "+", ae });
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    const a = cx.arena;
    const gap = proc.failGap;
    var s: Spec = .{};
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return syntax(cx);
        const o = t[i].text;
        const valued = at(t, i + 1, .eq);
        const l = t[i].line;
        if (valued and (eq(o, "data") or eq(o, "out") or eq(o, "outsim"))) {
            const is_data = eq(o, "data");
            const slot = if (is_data) &s.data else &s.out;
            if (slot.* != null) {
                // Verified (SAS 9.4): a second DATA= / OUT= warns; the first wins.
                try cx.diags.warn(l, "Ignoring second data set reference.", .{});
                var dummy: ?[]const u8 = null;
                var dummy_opts: []const lex.Token = &.{};
                i = try member(cx, t, i + 2, &dummy, &dummy_opts);
            } else if (is_data) {
                var ignored: []const lex.Token = &.{};
                i = try member(cx, t, i + 2, slot, &ignored);
            } else i = try member(cx, t, i + 2, slot, &s.out_opts);
        } else if (valued and (eq(o, "numreal") or eq(o, "numr") or eq(o, "nr") or eq(o, "n"))) {
            i += 2;
            const v = try number(cx, t, &i);
            // Verified (SAS 9.4): negative -> this ERROR; 2.5 -> 2 realizations;
            // 0 -> an empty OUT= data set; a repeat takes the last value.
            if (v < 0) return cx.diags.fail(error.ParseError, l, "The parameter value {d} is less than the minimum allowed value of 0.", .{v});
            s.numreal = @trunc(v);
        } else if (valued and eq(o, "seed")) {
            i += 2;
            const v = try number(cx, t, &i);
            // Verified (SAS 9.4): SEED=2147483647 aborts with a floating point
            // exception and SEED=3000000000 runs; neither mapping is known.
            if (v >= 2147483647) return gap(cx.diags, l, "PROC SIMNORMAL: SEED= values of 2147483647 or more are not implemented", .{});
            const iv = @trunc(v);
            s.seed = if (iv >= 1) @intFromFloat(iv) else null; // repeat: last wins (verified)
        } else if (valued and (eq(o, "singular1") or eq(o, "sing1") or eq(o, "singular2") or eq(o, "sing2"))) {
            const first = eq(o, "singular1") or eq(o, "sing1");
            i += 2;
            const v = try number(cx, t, &i);
            const nm: []const u8 = if (first) "SINGULAR1" else "SINGULAR2";
            // Verified (SAS 9.4) for SINGULAR1: 2 -> range ERROR; 0 -> WARNING
            // and reset to 1E-8. ponytail: SINGULAR2 assumed alike; negative
            // values and exactly 1 are not verified.
            if (v < 0 or v == 1) return gap(cx.diags, l, "PROC SIMNORMAL: {s}={d} is not verified", .{ nm, v });
            if (v > 1) return cx.diags.fail(error.ParseError, l, "The parameter value {d} is not within the required range of 0 and 1.", .{v});
            var use = v;
            if (v == 0) {
                // Verified order: this WARNING follows the OUTCOND one (run).
                if (first) s.reset1 = l else s.reset2 = l;
                use = 1e-8;
            }
            if (first) s.singular1 = use else s.singular2 = use;
        } else if (!valued and eq(o, "seedby")) {
            s.seedby = true;
            i += 1;
        } else if (!valued and eq(o, "outseed")) {
            s.outseed = true;
            i += 1;
        } else if (!valued and (eq(o, "outcond") or eq(o, "outc"))) {
            s.outcond = true;
            i += 1;
        } else return syntax(cx);
    }
    if (!at(t, i, .semicolon)) return syntax(cx);
    i += 1;

    var bys: by.Statements = .{};
    var var_toks: std.ArrayList([]const lex.Token) = .empty;
    var cond = false;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "var")) {
            // Verified (SAS 9.4): several VAR statements accumulate.
            s.var_given = true;
            try var_toks.append(a, t[i + 1 .. end]);
        } else if (eq(word, "condition") or eq(word, "cond")) {
            cond = true;
        } else if (eq(word, "where")) {
            // Applied by procInputObs.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (cond) return gap(cx.diags, line(t, 0), "PROC SIMNORMAL: the CONDITION statement (conditional simulation) is not implemented (STAT-SIMNORMAL-003/004)", .{});
    s.var_toks = var_toks.items;
    s.bys = bys;
    return s;
}

const Matrix = struct {
    cov: []f64,
    mean: []f64,
};

/// Reads the moments of one BY group. Returns null after a recoverable ERROR
/// (SAS keeps the OUT= rows produced so far and stops; verified).
fn moments(cx: proc.ProcCtx, ds: *const Dataset, rows: []const []const Value, vcols: []const usize, vnames: []const []const u8, renamed: bool, kind: []const u8, type_col: usize, name_col: usize, by_cols: []const usize, rep: ?[]const Value) diag.Error!?Matrix {
    const a = cx.arena;
    const p = vcols.len;
    const dsn = try qualified(a, ds.name);
    const corr = eq(kind, "CORR");
    var have = try a.alloc(bool, p);
    @memset(have, false);
    const cov = try a.alloc(f64, p * p);
    var mean: ?[]f64 = null;
    var sdev: ?[]f64 = null;
    var any_kind = false;
    for (rows) |row| {
        const ty = std.mem.trim(u8, if (row[type_col] == .str) row[type_col].str else "", " ");
        if (eq(ty, kind)) {
            any_kind = true;
            const nm = std.mem.trim(u8, if (row[name_col] == .str) row[name_col].str else "", " ");
            for (vnames, 0..) |vn, r| if (eq(vn, nm)) {
                if (have[r]) return proc.failGap(cx.diags, 0, "PROC SIMNORMAL: two _TYPE_='{s}' observations for variable {s} are not verified", .{ kind, vn });
                have[r] = true;
                for (vcols, 0..) |ci, c| cov[r * p + c] = row[ci].num;
            };
        } else if (eq(ty, "MEAN") or (corr and eq(ty, "STD"))) {
            const slot = if (eq(ty, "MEAN")) &mean else &sdev;
            if (slot.* != null) return proc.failGap(cx.diags, 0, "PROC SIMNORMAL: more than one _TYPE_='{s}' observation is not verified", .{ty});
            const v = try a.alloc(f64, p);
            for (vcols, v) |ci, *x| x.* = row[ci].num;
            slot.* = v;
        } else if (ty.len > 0 and (eq(ty, "COND") or eq(ty, "COV") or eq(ty, "CORR") or eq(ty, "UCOV") or eq(ty, "UCORR") or eq(ty, "SSCP") or eq(ty, "USTD"))) {
            return proc.failGap(cx.diags, 0, "PROC SIMNORMAL: a _TYPE_='{s}' observation in a TYPE={s} data set is not verified", .{ ty, kind });
        }
        // Other _TYPE_ rows (N, ...) are not used (verified: N rows ignored).
    }
    if (!any_kind) {
        try cx.diags.recoverableErr(0, "{s} matrix not found in data set {s}.", .{ kind, dsn });
        return null;
    }
    var complete = !renamed;
    for (have) |h| complete = complete and h;
    if (complete) for (cov) |x| {
        complete = complete and !std.math.isNan(x);
    };
    if (!complete) {
        try cx.diags.recoverableErr(0, "{s} matrix incomplete in data set {s}.", .{ kind, dsn });
        return null;
    }
    for (0..p) |r| for (0..r) |c| if (cov[r * p + c] != cov[c * p + r]) {
        // ponytail: exact comparison; SAS's symmetry tolerance is not known.
        try cx.diags.recoverableErr(0, "The {s} matrix read from the input data set {s} is not symmetric between variable {s} and variable {s}.", .{ kind, dsn, ds.columns.items[vcols[r]].name, ds.columns.items[vcols[c]].name });
        return null;
    };
    const m = try a.alloc(f64, p);
    var mean_missing = mean == null;
    for (m, 0..) |*x, k| {
        x.* = if (mean) |mv| mv[k] else 0;
        if (std.math.isNan(x.*)) {
            mean_missing = true;
            x.* = 0;
        }
    }
    if (mean_missing) {
        try cx.diags.note(0, "The means of one or more variables in the input data set {s} are missing and are assumed to be 0.", .{dsn});
        if (rep) |rw| try by.reportNote(a, cx.diags, ds, rw, by_cols);
    }
    if (corr) {
        var sd_missing = sdev == null;
        const sd = try a.alloc(f64, p);
        for (sd, 0..) |*x, k| {
            x.* = if (sdev) |v| v[k] else 1;
            if (std.math.isNan(x.*)) {
                sd_missing = true;
                x.* = 1;
            }
        }
        if (sd_missing) {
            try cx.diags.note(0, "The standard deviations of one or more variables in the input data set {s} are missing and are assumed to be 1.", .{dsn});
            if (rep) |rw| try by.reportNote(a, cx.diags, ds, rw, by_cols);
        }
        for (0..p) |r| for (0..p) |c| {
            cov[r * p + c] *= sd[r] * sd[c];
        };
    }
    return .{ .cov = cov, .mean = m };
}

/// Lower Cholesky root in VAR order. Verified (SAS 9.4): a pivot at or below
/// the SINGULAR1= criterion gives one WARNING and a zero column (its normal
/// component is still drawn); a clearly negative pivot is the
/// not-positive-definite ERROR. ponytail: the criterion is applied relative
/// to the diagonal element; only clear cases (pivot 0, pivot -3) are verified.
fn cholesky(cx: proc.ProcCtx, a: A, v: []const f64, p: usize, sing1: f64) diag.Error![]f64 {
    const l = try a.alloc(f64, p * p);
    @memset(l, 0);
    var warned = false;
    for (0..p) |j| {
        if (v[j * p + j] < 0) return proc.failGap(cx.diags, 0, "PROC SIMNORMAL: a negative variance is not verified", .{});
        var d = v[j * p + j];
        for (0..j) |k| d -= l[j * p + k] * l[j * p + k];
        const tol = sing1 * v[j * p + j];
        if (d < -tol) return cx.diags.fail(error.ParseError, 0, "Invalid covariance or conditional covariance matrix; matrix is not positive definite.", .{});
        if (d <= tol) {
            if (!warned) try cx.diags.warn(0, "Covariance or conditional covariance matrix is singular based on SINGULAR1={s}.", .{try sciText(a, sing1)});
            warned = true;
            continue;
        }
        const ljj = @sqrt(d);
        l[j * p + j] = ljj;
        for (j + 1..p) |r| {
            var s = v[r * p + j];
            for (0..j) |k| s -= l[r * p + k] * l[j * p + k];
            l[r * p + j] = s / ljj;
        }
    }
    return l;
}

/// One N(0,1) component from the classic stream (two uniforms, cosine
/// branch only: verified against SAS 9.4 best16. dumps).
fn normal(state: *u64) f64 {
    const ua = fns.classicUniform(state);
    const ub = fns.classicUniform(state);
    return @sqrt(-2.0 * @log(ua)) * @cos(2.0 * std.math.pi * ub);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    _ = out; // p.9353: PROC SIMNORMAL produces no printed output.
    const a = cx.arena;
    const gap = proc.failGap;
    var s = try parse(cx, t);
    const l0 = line(t, 0);
    const raw = (if (s.data) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse {
        if (s.data) |n| return cx.diags.fail(error.ParseError, l0, "File {s}.DATA does not exist.", .{try qualified(a, n)});
        return cx.diags.fail(error.ParseError, l0, "There is not a default input data set (_LAST_ is _NULL_).", .{});
    };
    const ds = (try proc.procInputObs(a, raw, t, cx.diags)).ds;
    const pb = try s.bys.resolve(a, ds, cx.diags);
    s.by_names = pb.names;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;

    // VAR (p.9358): numeric variables; verified SAS 9.4 messages.
    var vnames: std.ArrayList([]const u8) = .empty;
    var vcols: std.ArrayList(usize) = .empty;
    for (s.var_toks) |body| {
        if (body.len == 0) return invalid(cx, t, 0);
        var j: usize = 0;
        while (j < body.len) {
            const ln = body[j].line;
            const names = try lists.next(a, ds, body, &j, cx.diags);
            for (names) |n| {
                const ci = ds.indexOf(n) orelse return cx.diags.fail(error.ParseError, ln, "Variable {s} not found.", .{try std.ascii.allocUpperString(a, n)});
                if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, ln, "Variable {s} in list does not match type prescribed for this list.", .{ds.columns.items[ci].name});
                try vnames.append(a, ds.columns.items[ci].name);
                try vcols.append(a, ci);
            }
        }
    }
    const kind_raw = ds.ds_type orelse return gap(cx.diags, l0, "PROC SIMNORMAL: an input data set without TYPE=COV or TYPE=CORR is not implemented", .{});
    const kind: []const u8 = if (eq(kind_raw, "COV")) "COV" else if (eq(kind_raw, "CORR")) "CORR" else return gap(cx.diags, l0, "PROC SIMNORMAL: TYPE={s} input data sets are not implemented (only TYPE=COV and TYPE=CORR)", .{kind_raw});
    const type_col = ds.indexOf("_TYPE_") orelse return gap(cx.diags, l0, "PROC SIMNORMAL: an input data set without a _TYPE_ variable is not implemented", .{});
    const name_col = ds.indexOf("_NAME_") orelse return gap(cx.diags, l0, "PROC SIMNORMAL: an input data set without a _NAME_ variable is not implemented", .{});
    if (ds.columns.items[type_col].type != .char or ds.columns.items[name_col].type != .char) return gap(cx.diags, l0, "PROC SIMNORMAL: numeric _TYPE_ or _NAME_ variables are not implemented", .{});

    const by_cols = try a.alloc(usize, s.by_names.len);
    for (s.by_names, by_cols) |n, *c| c.* = ds.indexOf(n).?;

    if (s.outcond) try cx.diags.warn(l0, "OUTCOND specified, but no CONDITION was given. OUTCOND option ignored.", .{});
    if (s.reset1) |l| try cx.diags.warn(l, "SINGULAR1=0 is an invalid value. SINGULAR1 is reset to 1.00E-08.", .{});
    if (s.reset2) |l| try cx.diags.warn(l, "SINGULAR2=0 is an invalid value. SINGULAR2 is reset to 1.00E-08.", .{});
    const nr: f64 = s.numreal orelse blk: {
        try cx.diags.note(l0, "No NUMREAL= value given. Default value of NUMREAL= 100 is used.", .{});
        break :blk 100;
    };
    if (nr > 1e9) return gap(cx.diags, l0, "PROC SIMNORMAL: NUMREAL= above 1E9 is not implemented", .{});
    const n_real: usize = @intFromFloat(nr);
    const seed0: u64 = s.seed orelse blk: {
        // ponytail: SAS's clock-to-seed mapping is not published; any
        // positive value below 2^31-1 is a valid seed, reported in the NOTE.
        const secs: u64 = @intCast(@max(fns.currentSecondOfDay() + 86400 * @mod(fns.currentSasDate(), 20000), 1));
        const v = secs % 2147483646 + 1;
        try cx.diags.note(l0, "No SEED= value given, or the given value is nonpositive. A seed based on the CPU clock will be used. The value used is: SEED={d}.", .{v});
        break :blk v;
    };

    // Output layout (verified SAS 9.4, PROC CONTENTS VARNUM): BY variables,
    // VAR variables, Rnum, Seed (OUTSEED).
    const out_name = s.out orelse blk: {
        // p.9356: DATAn convention (verified: DATA1). ponytail: first unused.
        var k: usize = 1;
        while (cx.lib.find(try std.fmt.allocPrint(a, "DATA{d}", .{k})) != null) k += 1;
        break :blk try std.fmt.allocPrint(a, "DATA{d}", .{k});
    };
    s.out = out_name;
    const o = try a.create(Dataset);
    o.* = Dataset.init(a, out_name);
    const out_q = try qualified(a, out_name);
    for (by_cols) |ci| _ = try o.addColumnLike(ds.columns.items[ci].name, ds.columns.items[ci]);
    var renamed = false;
    for (vnames.items) |n| {
        var use = n;
        if (o.indexOf(n) != null) {
            // Verified (SAS 9.4): the duplicate is renamed with this NOTE,
            // labelled with the original name, and the matrix is incomplete.
            var k: usize = 2;
            while (true) : (k += 1) {
                use = try std.fmt.allocPrint(a, "{s}{d}", .{ n, k });
                if (o.indexOf(use) == null) break;
            }
            if (use.len > 32) return gap(cx.diags, l0, "PROC SIMNORMAL: renaming a 32-character variable is not verified", .{});
            try cx.diags.note(l0, "Variable {s} already exists on file {s}, using {s} instead.", .{ n, out_q, use });
            const ci = try o.addColumn(use, .num);
            o.columns.items[ci].label = n;
            renamed = true;
        } else _ = try o.addColumn(n, .num);
    }
    _ = try o.addColumn("Rnum", .num);
    if (s.outseed) _ = try o.addColumn("Seed", .num);
    const width = o.columns.items.len;
    const p = vcols.items.len;

    if (p == 0) {
        // Verified (SAS 9.4, TYPE=COV and TYPE=CORR, no BY): ERROR, this
        // WARNING, and an OUT= data set holding only Rnum.
        if (s.by_names.len > 0 or s.outseed) return gap(cx.diags, l0, "PROC SIMNORMAL: no VAR statement together with BY or OUTSEED is not verified", .{});
        try cx.diags.recoverableErr(l0, "No variables were specified.", .{});
        try cx.diags.warn(l0, "The data set {s} does not indicate how many observations were used to compute the {s} matrix. The number of observations has been set to 10000. Statistics that depend on the number of observations (such as p-values) are not interpretable.", .{ try qualified(a, ds.name), kind });
        for (0..n_real) |r| try o.appendRow(&.{.{ .num = @floatFromInt(r + 1) }});
        return finish(cx, s, o, out_q);
    }

    if (ds.rows.items.len == 0) {
        // Verified (SAS 9.4): NOTE and an empty OUT= data set.
        if (s.by_names.len > 0) return gap(cx.diags, l0, "PROC SIMNORMAL: an empty input data set with BY is not verified", .{});
        try cx.diags.note(l0, "No observations in data set {s} or current by group.", .{try qualified(a, ds.name)});
        return finish(cx, s, o, out_q);
    }

    const groups = try checkedGroups(cx, ds, by_cols, s);
    var state: u64 = seed0;
    const values = try a.alloc(Value, width);
    const z = try a.alloc(f64, p);
    for (groups) |g| {
        const mo = (try moments(cx, ds, g.rows, vcols.items, vnames.items, renamed, kind, type_col, name_col, by_cols, if (s.by_names.len > 0) g.rep else null)) orelse return finish(cx, s, o, out_q);
        const l = cholesky(cx, a, mo.cov, p, s.singular1) catch |e| {
            // Verified (SAS 9.4): the step stops; OUT= keeps its variables
            // and the rows written so far, with this WARNING.
            if (diag.gapHit()) return e;
            if (s.out_opts.len > 0) try @import("../io.zig").applyDatasetOptions(a, o, s.out_opts, cx.diags, false);
            try cx.lib.put(s.out.?, o);
            try cx.diags.warn(0, "The data set {s} may be incomplete.  When this step was stopped there were {d} observations and {d} variables.", .{ out_q, o.rows.items.len, o.columns.items.len });
            return e;
        };
        if (s.seedby) state = seed0;
        for (0..n_real) |r| {
            var c: usize = 0;
            for (by_cols) |ci| {
                values[c] = g.rep.?[ci];
                c += 1;
            }
            const before = state;
            for (z) |*x| x.* = normal(&state);
            for (0..p) |k| {
                var y = mo.mean[k];
                for (0..k + 1) |j| y += l[k * p + j] * z[j];
                values[c + k] = .{ .num = y };
            }
            c += p;
            values[c] = .{ .num = @floatFromInt(r + 1) };
            if (s.outseed) values[c + 1] = .{ .num = @floatFromInt(before) };
            try o.appendRow(values);
        }
    }
    return finish(cx, s, o, out_q);
}

fn checkedGroups(cx: proc.ProcCtx, ds: *const Dataset, by_cols: []const usize, s: Spec) diag.Error![]proc.BySlice {
    const a = cx.arena;
    if (by_cols.len == 0) {
        const one = try a.alloc(proc.BySlice, 1);
        one[0] = .{ .rep = ds.rows.items[0], .rows = ds.rows.items };
        return one;
    }
    const groups = try proc.bySlices(a, ds.rows.items, by_cols);
    if (!s.notsorted and groups.len > 1) {
        for (groups[1..], groups[0 .. groups.len - 1]) |next, prev| {
            if (proc.byOrderViolation(next.rep.?, prev.rep.?, by_cols, s.by_desc, ds.sortseq_linguistic orelse @import("../io.zig").global_sortseq_linguistic)) |k| {
                // Verified (SAS 9.4) text, naming the offending BY variable.
                const ci = by_cols[k];
                const nm = ds.columns.items[ci].name;
                return cx.diags.fail(error.ParseError, 0, "Data set {s} is not sorted in {s} sequence. The current BY group has {s} = {s} and the next BY group has {s} = {s}.", .{ try qualified(a, ds.name), if (s.by_desc[k]) @as([]const u8, "descending") else "ascending", nm, try byText(a, prev.rep.?[ci]), nm, try byText(a, next.rep.?[ci]) });
            }
        }
    }
    return groups;
}

fn byText(a: A, v: Value) ![]const u8 {
    return std.mem.trim(u8, try proc.cellText(a, v), " ");
}

fn finish(cx: proc.ProcCtx, s: Spec, o: *Dataset, out_q: []const u8) diag.Error!void {
    if (s.out_opts.len > 0) try @import("../io.zig").applyDatasetOptions(cx.arena, o, s.out_opts, cx.diags, false);
    try cx.lib.put(s.out.?, o);
    try cx.diags.note(0, "The data set {s} has {d} observations and {d} variables.", .{ out_q, o.rows.items.len, o.columns.items.len });
}

test {
    _ = @import("simnormal_tests.zig");
}
