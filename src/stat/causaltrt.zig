//! PROC CAUSALTRT (SAS/STAT 15.4 ch.39, STAT-CAUSALTRT-001): PROC statement
//! options, CLASS / PSMODEL / MODEL declarations, BY, FREQ, missing values,
//! the IPW and IPWR estimators with the robust sandwich standard errors, and
//! the default listing (Model Information, observation counts, Class Level
//! Information, Response / Treatment Profile, Analysis of Causal Effect).
//!
//! Estimation (pp.2453-2458):
//! - Propensity score: binary logit ML of the treatment event on an intercept
//!   plus the PSMODEL main effects (logistic_fit kernel, read-only reuse; a
//!   CLASS effect enters as reference-coded indicators, which spans the same
//!   column space as the GLM coding, so the fitted scores are identical).
//! - IPW:  mu1 = sum f t y / e / n,          mu0 = sum f (1-t) y / (1-e) / n.
//! - IPWR: mu1 = sum f t y / e / sum f t / e, mu0 likewise with 1-t, 1-e.
//! - Covariance: M-estimation sandwich A^-1 B A^-T over the stacked score
//!   (S_ps, S_ipw); FREQ multiplies every observation's contribution.
//! Verified against SAS listings (reference case plus IPW/FREQ/missing, BY with
//! ALPHA= and DIST=NORMAL, default method with EVENT=FIRST and DESCENDING).
//! Everything else the PROC statement documents is a loud D-009 gap.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const levels = @import("class_levels.zig");
const logit = @import("logistic_fit.zig");
const selection = @import("data_selection.zig");
const io = @import("../io.zig");
const A = std.mem.Allocator;
const Out = std.ArrayList(u8);
const eq = std.ascii.eqlIgnoreCase;
const Token = lex.Token;

pub const Method = enum { ipw, ipwr };
pub const Dist = enum { binomial, normal };
/// Binary-variable option: which level is the modeled event.
pub const Pick = union(enum) { event_first, event_last, event: []const u8, ref: []const u8 };
pub const Binary = struct { col: usize, pick: Pick = .event_first, descending: bool = false, explicit: bool = false };

pub const Spec = struct {
    input: proc.ProcInput,
    method: Method = .ipwr,
    alpha: f64 = 0.05,
    noprint: bool = false,
    descending: bool = false,
    /// ORDER= (CLASS levels) and RORDER= (outcome levels), p.2441-2442. SAS 9.4
    /// (verified): neither reorders the treatment levels (always formatted).
    order: levels.Order = .formatted,
    rorder: levels.Order = .formatted,
    class: []const usize = &.{},
    treatment: Binary = .{ .col = 0 },
    ps_effects: []const usize = &.{},
    outcome: Binary = .{ .col = 0 },
    dist: Dist = .normal,
    freq: ?usize = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
};

fn at(t: []const Token, i: usize, tag: lex.Tag) bool {
    return i < t.len and t[i].tag == tag;
}
fn kw(t: []const Token, i: usize, text: []const u8) bool {
    return at(t, i, .name) and eq(t[i].text, text);
}
fn line(t: []const Token, i: usize) usize {
    return if (i < t.len) t[i].line else if (t.len > 0) t[t.len - 1].line else 0;
}
fn has(list: []const usize, v: usize) bool {
    return std.mem.indexOfScalar(usize, list, v) != null;
}
fn invalid(cx: proc.ProcCtx, t: []const Token, i: usize) diag.Error {
    return cx.diags.fail(error.ParseError, line(t, i), "PROC CAUSALTRT: invalid statement or token {s}", .{if (i < t.len and t[i].text.len > 0) t[i].text else "<end or operator>"});
}
fn gap(cx: proc.ProcCtx, l: usize, comptime fmt: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, l, "PROC CAUSALTRT: " ++ fmt, args);
}
fn isOne(list: []const []const u8, w: []const u8) bool {
    for (list) |x| if (eq(x, w)) return true;
    return false;
}
fn column(cx: proc.ProcCtx, ds: *const Dataset, tok: Token, role: []const u8) diag.Error!usize {
    return ds.indexOf(tok.text) orelse cx.diags.fail(error.ParseError, tok.line, "Variable {s} in the {s} statement is not found.", .{ tok.text, role });
}

// PROC statement options owned by later CAUSALTRT tickets (or by ODS Graphics).
const gap_flags = [_][]const u8{ "att", "atet", "covdiffps", "noeffect", "pall", "all", "plots", "poutcomemod", "pregadj", "ppsmodel", "ptreatmod", "nloptions" };
const gap_valued = [_][]const u8{ "singular", "plots" };

fn orderValue(cx: proc.ProcCtx, t: []const Token, i: usize) diag.Error!levels.Order {
    if (kw(t, i, "data")) return .data;
    if (kw(t, i, "formatted")) return .formatted;
    if (kw(t, i, "freq")) return .freq;
    if (kw(t, i, "internal")) return .internal;
    return cx.diags.fail(error.ParseError, line(t, i), "PROC CAUSALTRT: ORDER= and RORDER= must be DATA, FORMATTED, FREQ or INTERNAL", .{});
}

/// `var(options)`: binary-variable options of MODEL / PSMODEL (pp.2439, 2443-2444).
fn binaryOptions(cx: proc.ProcCtx, t: []const Token, i: *usize, b: *Binary, role: []const u8) diag.Error!void {
    if (!at(t, i.*, .lparen)) return;
    var j = i.* + 1;
    var picked = false;
    while (!at(t, j, .rparen)) {
        if (!at(t, j, .name)) return invalid(cx, t, j);
        const o = t[j].text;
        if (eq(o, "desc") or eq(o, "descending")) {
            b.descending = true;
            j += 1;
        } else if (eq(o, "ref") or eq(o, "reference") or eq(o, "event")) {
            if (picked) return gap(cx, t[j].line, "both EVENT= and REF= for the {s} variable are not verified", .{role});
            picked = true;
            b.explicit = true;
            if (!at(t, j + 1, .eq)) return invalid(cx, t, j + 1);
            const isref = !eq(o, "event");
            if (at(t, j + 2, .string)) {
                const v = std.mem.trimEnd(u8, t[j + 2].text, " ");
                b.pick = if (isref) .{ .ref = v } else .{ .event = v };
            } else if (kw(t, j + 2, "first")) {
                b.pick = if (isref) .event_last else .event_first;
            } else if (kw(t, j + 2, "last")) {
                b.pick = if (isref) .event_first else .event_last;
            } else return invalid(cx, t, j + 2);
            j += 3;
        } else if (eq(o, "order")) {
            return gap(cx, t[j].line, "the ORDER= option for the {s} variable is not implemented", .{role});
        } else return invalid(cx, t, j);
    }
    i.* = j + 1;
}

/// Main effects only; constructed effects (crossed, nested, |, @) are gaps.
fn effects(cx: proc.ProcCtx, ds: *const Dataset, t: []const Token, i: *usize, end: usize, role: []const u8) diag.Error![]const usize {
    var list: std.ArrayList(usize) = .empty;
    while (i.* < end and !at(t, i.*, .slash)) {
        if (!at(t, i.*, .name)) {
            if (at(t, i.*, .star) or at(t, i.*, .pipe) or at(t, i.*, .lparen) or at(t, i.*, .at) or at(t, i.*, .minus))
                return gap(cx, t[i.*].line, "constructed effects and variable lists in the {s} statement are not implemented", .{role});
            return invalid(cx, t, i.*);
        }
        const ci = try column(cx, ds, t[i.*], role);
        if (has(list.items, ci)) return gap(cx, t[i.*].line, "an effect listed twice in the {s} statement is not verified", .{role});
        try list.append(cx.arena, ci);
        i.* += 1;
    }
    return list.items;
}

pub fn parse(cx: proc.ProcCtx, t: []const Token) diag.Error!Spec {
    const a = cx.arena;
    var s: Spec = .{ .input = undefined };
    var name: ?[]const u8 = null;
    var qualified: ?usize = null;
    var method: ?Method = null;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const l = t[i].line;
        var option: []const u8 = try std.ascii.allocLowerString(a, t[i].text);
        if (std.mem.eql(u8, option, "desc") or std.mem.eql(u8, option, "descend")) option = "descending";
        if (std.mem.eql(u8, option, "nthreads")) option = "threads";
        // SAS 9.4 (verified): a repeated option is not an error; the last
        // METHOD= / ALPHA= / ORDER= / RORDER= wins, a second DATA= is ignored
        // with a warning.
        const repeated = (try seen.getOrPut(a, option)).found_existing;
        const valued = at(t, i + 1, .eq);
        if (eq(option, "data") and valued) {
            if (repeated) try cx.diags.warn(l, "Ignoring second data set reference.", .{});
            const keep_name = name;
            const keep_qualified = qualified;
            defer if (repeated) {
                name = keep_name;
                qualified = keep_qualified;
            };
            const first = i + 2;
            if (!at(t, first, .name)) return invalid(cx, t, first);
            name = t[first].text;
            var j = first + 1;
            if (at(t, j, .dot)) {
                if (!at(t, j + 1, .name)) return invalid(cx, t, j + 1);
                name = try std.fmt.allocPrint(a, "{s}.{s}", .{ t[first].text, t[j + 1].text });
                qualified = first;
                j += 2;
            }
            if (at(t, j, .lparen)) j = proc.skipParen(t, j);
            i = j;
        } else if (eq(option, "method") and valued) {
            if (kw(t, i + 2, "ipw")) method = .ipw else if (kw(t, i + 2, "ipwr")) method = .ipwr else if (kw(t, i + 2, "ipws") or kw(t, i + 2, "aipw") or kw(t, i + 2, "regadj") or kw(t, i + 2, "ipwreg")) {
                return gap(cx, l, "METHOD={s} is not implemented (later CAUSALTRT tickets)", .{t[i + 2].text});
            } else return cx.diags.fail(error.ParseError, l, "PROC CAUSALTRT: METHOD= must be AIPW, IPW, IPWR, IPWS, REGADJ or IPWREG", .{});
            i += 3;
        } else if (eq(option, "alpha") and valued) {
            if (!at(t, i + 2, .number)) return cx.diags.fail(error.ParseError, l, "PROC CAUSALTRT: ALPHA= must be a number between 0 and 1", .{});
            const v = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (!(v > 0 and v < 1)) return cx.diags.fail(error.ParseError, l, "PROC CAUSALTRT: ALPHA= must be between 0 and 1", .{});
            s.alpha = v;
            i += 3;
        } else if ((eq(option, "namelen") or eq(option, "threads")) and valued) {
            // Neither changes the default listing: NAMELEN= sizes effect names
            // (not displayed here), THREADS= only the analytic thread count.
            if (!at(t, i + 2, .number)) return invalid(cx, t, i + 2);
            const v = std.fmt.parseFloat(f64, t[i + 2].text) catch return invalid(cx, t, i + 2);
            if (eq(option, "namelen") and !(v >= 20 and v <= 128)) return cx.diags.fail(error.ParseError, l, "PROC CAUSALTRT: NAMELEN= must be between 20 and 128", .{});
            if (eq(option, "threads") and !(v >= 0 and v == @floor(v))) return cx.diags.fail(error.ParseError, l, "PROC CAUSALTRT: THREADS= must be a nonnegative integer", .{});
            i += 3;
        } else if ((eq(option, "order") or eq(option, "rorder")) and valued) {
            const v = try orderValue(cx, t, i + 2);
            if (eq(option, "order")) s.order = v else s.rorder = v;
            i += 3;
        } else if (valued and isOne(&gap_valued, option)) {
            return gap(cx, l, "the {s}= option is not implemented (later CAUSALTRT tickets)", .{t[i].text});
        } else if (valued) {
            return invalid(cx, t, i);
        } else if (eq(option, "noprint")) {
            s.noprint = true;
            i += 1;
        } else if (eq(option, "descending")) {
            s.descending = true;
            i += 1;
        } else if (isOne(&gap_flags, option)) {
            return gap(cx, l, "the {s} option is not implemented (later CAUSALTRT tickets)", .{t[i].text});
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    const raw = (if (name) |n| cx.lib.find(n) else proc.lastDataset(cx.lib)) orelse return cx.diags.fail(error.ParseError, line(t, 0), "PROC CAUSALTRT: input data set not found", .{});
    var folded: std.ArrayList(Token) = .empty;
    if (qualified) |q| {
        try folded.appendSlice(a, t[0..q]);
        try folded.append(a, .{ .tag = .name, .text = name.?, .line = t[q].line });
        try folded.appendSlice(a, t[q + 3 ..]);
    }
    s.input = try proc.procInputObs(a, raw, if (qualified != null) folded.items else t, cx.diags);
    const ds = s.input.ds;

    var bys: by.Statements = .{};
    var class: std.ArrayList(usize) = .empty;
    var class_seen = false;
    var model_seen = false;
    var ps_seen = false;
    var model_effects: []const usize = &.{};
    var dist: ?Dist = null;
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        const l = t[i].line;
        if (eq(word, "run") or eq(word, "quit")) {
            if (end != i + 1) return invalid(cx, t, i + 1);
        } else if (eq(word, "by")) {
            // p.2436: only the last BY statement is used.
            var j = i;
            try bys.read(a, t, &j);
        } else if (eq(word, "class")) {
            if (class_seen) return gap(cx, l, "more than one CLASS statement is not verified", .{});
            // p.2424: the CLASS statement must precede MODEL and PSMODEL.
            if (model_seen or ps_seen) return cx.diags.fail(error.ParseError, l, "PROC CAUSALTRT: the CLASS statement must precede the MODEL and PSMODEL statements", .{});
            class_seen = true;
            var j = i + 1;
            while (j < end) : (j += 1) {
                if (at(t, j, .lparen) or at(t, j, .slash)) return gap(cx, t[j].line, "CLASS statement options are not implemented", .{});
                if (!at(t, j, .name)) return invalid(cx, t, j);
                const ci = try column(cx, ds, t[j], "CLASS");
                if (!has(class.items, ci)) try class.append(a, ci);
            }
            if (class.items.len == 0) return invalid(cx, t, end);
        } else if (eq(word, "psmodel") or eq(word, "model")) {
            const is_ps = eq(word, "psmodel");
            const role: []const u8 = if (is_ps) "PSMODEL" else "MODEL";
            if ((is_ps and ps_seen) or (!is_ps and model_seen)) return gap(cx, l, "more than one {s} statement is not verified", .{role});
            if (is_ps) ps_seen = true else model_seen = true;
            var j = i + 1;
            if (!at(t, j, .name)) return invalid(cx, t, j);
            var b: Binary = .{ .col = try column(cx, ds, t[j], role) };
            j += 1;
            try binaryOptions(cx, t, &j, &b, role);
            var eff: []const usize = &.{};
            if (at(t, j, .eq)) {
                j += 1;
                eff = try effects(cx, ds, t, &j, end, role);
            }
            if (at(t, j, .slash)) {
                j += 1;
                if (is_ps) return gap(cx, t[j - 1].line, "PSMODEL statement options are not implemented", .{});
                while (j < end) {
                    if ((kw(t, j, "dist") or kw(t, j, "distribution")) and at(t, j + 1, .eq) and at(t, j + 2, .name)) {
                        const d = t[j + 2].text;
                        if (eq(d, "bin") or eq(d, "b") or eq(d, "binary") or eq(d, "binomial")) dist = .binomial else if (eq(d, "normal") or eq(d, "nor") or eq(d, "n")) dist = .normal else if (isOne(&.{ "gamma", "gam", "g", "igaussian", "ig", "poisson", "poi", "p" }, d)) {
                            return gap(cx, t[j].line, "DIST={s} is not implemented", .{d});
                        } else return cx.diags.fail(error.ParseError, t[j].line, "PROC CAUSALTRT: invalid DIST= value {s}", .{d});
                        j += 3;
                    } else if (at(t, j, .name) and isOne(&.{ "alpha", "link", "noscale", "scale" }, t[j].text)) {
                        return gap(cx, t[j].line, "the MODEL statement option {s} is not implemented", .{t[j].text});
                    } else return invalid(cx, t, j);
                }
            }
            if (j != end) return invalid(cx, t, j);
            if (is_ps) {
                s.treatment = b;
                s.ps_effects = eff;
            } else {
                s.outcome = b;
                model_effects = eff;
            }
        } else if (eq(word, "freq")) {
            if (s.freq != null) return cx.diags.fail(error.ParseError, l, "Only one FREQ statement is allowed.", .{}); // SAS 9.4 verified
            if (end != i + 2 or !at(t, i + 1, .name)) return invalid(cx, t, @min(i + 1, end));
            const ci = try column(cx, ds, t[i + 1], "FREQ");
            if (ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l, "Variable {s} in the FREQ statement must be numeric.", .{t[i + 1].text});
            s.freq = ci;
        } else if (eq(word, "bootstrap") or eq(word, "output")) {
            return gap(cx, l, "the {s} statement is not implemented (later CAUSALTRT tickets)", .{word});
        } else if (eq(word, "where")) {
            // Applied by procInputObs above.
        } else if (parser.isMidStepSkippable(word)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    const l0 = line(t, 0);
    // p.2424: the PROC CAUSALTRT, MODEL and PSMODEL statements are required.
    if (!model_seen) return cx.diags.fail(error.ParseError, l0, "PROC CAUSALTRT: a MODEL statement is required", .{});
    if (!ps_seen) return cx.diags.fail(error.ParseError, l0, "PROC CAUSALTRT: a PSMODEL statement is required", .{});
    const pb = try bys.resolve(a, ds, cx.diags);
    const cols = try a.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| cols[k] = ds.indexOf(n).?;
    s.by_cols = cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    s.class = class.items;
    if (s.treatment.col == s.outcome.col) return cx.diags.fail(error.ParseError, l0, "PROC CAUSALTRT: the treatment and outcome variables must differ", .{});
    if (has(s.class, s.treatment.col) or has(s.class, s.outcome.col)) return gap(cx, l0, "a treatment or outcome variable listed in the CLASS statement is not verified", .{});
    for (s.ps_effects) |ci| {
        if (ci == s.treatment.col or ci == s.outcome.col or has(cols, ci) or s.freq == ci) return gap(cx, l0, "variable {s} in both the PSMODEL effects and another role is not verified", .{ds.columns.items[ci].name});
        if (!has(s.class, ci) and ds.columns.items[ci].type != .num) return cx.diags.fail(error.ParseError, l0, "Variable {s} should be either numeric or specified in the CLASS statement.", .{ds.columns.items[ci].name});
    }
    // p.2420: default method from the specified models.
    if (method) |m| {
        if (model_effects.len > 0) return gap(cx, l0, "MODEL statement effects with METHOD={s} are not verified", .{@tagName(m)});
        s.method = m;
    } else {
        if (model_effects.len > 0) return gap(cx, l0, "the default AIPW / REGADJ estimation (MODEL statement effects) is not implemented", .{});
        if (s.ps_effects.len == 0) return gap(cx, l0, "the default REGADJ estimation (no PSMODEL effects) is not implemented", .{});
        s.method = .ipwr;
    }
    // p.2440: default binomial when the outcome is a CLASS variable, else normal.
    s.dist = dist orelse .normal;
    if (s.dist == .normal) {
        if (ds.columns.items[s.outcome.col].type != .num) return cx.diags.fail(error.ParseError, l0, "PROC CAUSALTRT: the outcome variable {s} must be numeric for the normal distribution", .{ds.columns.items[s.outcome.col].name});
        if (s.outcome.descending or s.outcome.pick != .event_first or s.descending) return gap(cx, l0, "outcome level options for a non-binary outcome are not verified", .{});
    }
    return s;
}

// ── Estimation ────────────────────────────────────────────────────────────

pub const Estimate = struct { pom1: f64, pom0: f64, ate: f64, se1: f64, se0: f64, se_ate: f64 };

/// Solve m x = rhs in place (Gauss-Jordan, partial pivoting); false = singular.
fn solve(m: []f64, rhs: []f64, q: usize, k: usize) bool {
    for (0..q) |c| {
        var piv = c;
        for (c + 1..q) |r| if (@abs(m[r * q + c]) > @abs(m[piv * q + c])) {
            piv = r;
        };
        if (!(@abs(m[piv * q + c]) > 1e-300)) return false;
        if (piv != c) {
            for (0..q) |j| std.mem.swap(f64, &m[c * q + j], &m[piv * q + j]);
            for (0..k) |j| std.mem.swap(f64, &rhs[c * k + j], &rhs[piv * k + j]);
        }
        const d = m[c * q + c];
        for (0..q) |r| {
            if (r == c) continue;
            const f = m[r * q + c] / d;
            if (f == 0) continue;
            for (0..q) |j| m[r * q + j] -= f * m[c * q + j];
            for (0..k) |j| rhs[r * k + j] -= f * rhs[c * k + j];
        }
    }
    for (0..q) |c| for (0..k) |j| {
        rhs[c * k + j] /= m[c * q + c];
    };
    return true;
}

/// IPW / IPWR point estimates and sandwich covariance. `x` is n*p (intercept
/// first), `t` and `y` are the treatment-event and outcome values, `e` the
/// fitted propensity scores, `f` the frequencies.
pub fn estimate(a: A, method: Method, x: []const f64, p: usize, t: []const f64, y: []const f64, e: []const f64, f: []const f64) !?Estimate {
    const n = t.len;
    var nn: f64 = 0;
    var s1: f64 = 0;
    var s0: f64 = 0;
    var d1: f64 = 0;
    var d0: f64 = 0;
    for (0..n) |i| {
        nn += f[i];
        s1 += f[i] * t[i] * y[i] / e[i];
        s0 += f[i] * (1 - t[i]) * y[i] / (1 - e[i]);
        d1 += f[i] * t[i] / e[i];
        d0 += f[i] * (1 - t[i]) / (1 - e[i]);
    }
    const mu1 = if (method == .ipwr) s1 / d1 else s1 / nn;
    const mu0 = if (method == .ipwr) s0 / d0 else s0 / nn;
    const q = p + 2;
    const am = try a.alloc(f64, q * q);
    const bm = try a.alloc(f64, q * q);
    @memset(am, 0);
    @memset(bm, 0);
    const sc = try a.alloc(f64, q);
    for (0..n) |i| {
        const xi = x[i * p ..][0..p];
        const ei = e[i];
        const w = ei * (1 - ei);
        // Score: S_ps = x (t - e); S_0, S_1 per method. Rows: dS/dtheta.
        for (0..p) |j| sc[j] = xi[j] * (t[i] - ei);
        for (0..p) |r| for (0..p) |c| {
            am[r * q + c] -= f[i] * w * xi[r] * xi[c];
        };
        const r0 = p;
        const r1 = p + 1;
        if (method == .ipwr) {
            sc[r0] = (1 - t[i]) / (1 - ei) * (y[i] - mu0);
            sc[r1] = t[i] / ei * (y[i] - mu1);
            // d(1/(1-e))/dbeta = e/(1-e) x ; d(1/e)/dbeta = -(1-e)/e x
            for (0..p) |c| {
                am[r0 * q + c] += f[i] * (1 - t[i]) * (y[i] - mu0) * ei / (1 - ei) * xi[c];
                am[r1 * q + c] -= f[i] * t[i] * (y[i] - mu1) * (1 - ei) / ei * xi[c];
            }
            am[r0 * q + r0] -= f[i] * (1 - t[i]) / (1 - ei);
            am[r1 * q + r1] -= f[i] * t[i] / ei;
        } else {
            sc[r0] = (1 - t[i]) * y[i] / (1 - ei) - mu0;
            sc[r1] = t[i] * y[i] / ei - mu1;
            for (0..p) |c| {
                am[r0 * q + c] += f[i] * (1 - t[i]) * y[i] * ei / (1 - ei) * xi[c];
                am[r1 * q + c] -= f[i] * t[i] * y[i] * (1 - ei) / ei * xi[c];
            }
            am[r0 * q + r0] -= f[i];
            am[r1 * q + r1] -= f[i];
        }
        for (0..q) |r| for (0..q) |c| {
            bm[r * q + c] += f[i] * sc[r] * sc[c];
        };
    }
    // V = A^-1 B A^-T: solve A Z = B, then A V^T = Z^T (V symmetric).
    const am2 = try a.dupe(f64, am);
    if (!solve(am, bm, q, q)) return null;
    const zt = try a.alloc(f64, q * q);
    for (0..q) |r| for (0..q) |c| {
        zt[r * q + c] = bm[c * q + r];
    };
    if (!solve(am2, zt, q, q)) return null;
    const v00 = zt[(p) * q + p];
    const v11 = zt[(p + 1) * q + p + 1];
    const v01 = zt[(p) * q + p + 1];
    const va = v11 + v00 - 2 * v01;
    if (!(v00 >= 0 and v11 >= 0 and va >= 0)) return null;
    return .{ .pom1 = mu1, .pom0 = mu0, .ate = mu1 - mu0, .se1 = @sqrt(v11), .se0 = @sqrt(v00), .se_ate = @sqrt(va) };
}

// ── Listing ───────────────────────────────────────────────────────────────

fn fixed(a: A, x: f64, decimals: usize) ![]const u8 {
    const text = try std.fmt.allocPrint(a, "{d:.[1]}", .{ x, decimals });
    if (text[0] == '-' and std.mem.indexOfAny(u8, text, "123456789") == null) return text[1..];
    return text;
}
/// The D10.4-style estimate column: four significant digits for
/// 0.001 <= |x| < 1 (verified: 0.3456, -0.07010, 0.001315) and four
/// decimals for 1 <= |x| < 100 (SAS 9.4 verified: 65.9809, 2.7808, -0.2051).
fn dfmt(cx: proc.ProcCtx, x: f64) diag.Error![]const u8 {
    const ax = @abs(x);
    // ponytail: |x| >= 100, |x| < 0.001 and 0 are not verified against SAS.
    if (!(ax >= 0.001 and ax < 99.99995)) return gap(cx, 0, "displaying an estimate or confidence limit of {d} (outside 0.001 <= |x| < 100) is not verified", .{x});
    if (ax >= 0.99995) return fixed(cx.arena, x, 4);
    var d: usize = if (ax >= 0.1) 4 else if (ax >= 0.01) 5 else 6;
    // A value that rounds up to the next decade loses one decimal.
    if (d > 4) {
        const lim = std.math.pow(f64, 10, -@as(f64, @floatFromInt(d - 4)));
        const r = @round(ax * std.math.pow(f64, 10, @floatFromInt(d))) / std.math.pow(f64, 10, @floatFromInt(d));
        if (r >= lim) d -= 1;
    }
    return fixed(cx.arena, x, d);
}
fn pvalue(a: A, p: f64) ![]const u8 {
    if (p < 0.0001) return "<.0001";
    return fixed(a, p, 4);
}
fn zQuantile(alpha: f64) f64 {
    var lo: f64 = 0;
    var hi: f64 = 40;
    for (0..200) |_| {
        const mid = (lo + hi) / 2;
        if (logit.chiTail(mid * mid, 1) > alpha) lo = mid else hi = mid;
    }
    return (lo + hi) / 2;
}
fn pad(a: A, out: *Out, text: []const u8, w: usize, right: bool) !void {
    if (right) try out.appendNTimes(a, ' ', w -| text.len);
    try out.appendSlice(a, text);
    if (!right) try out.appendNTimes(a, ' ', w -| text.len);
}
fn endLine(a: A, out: *Out) !void {
    while (out.items.len > 0 and out.items[out.items.len - 1] == ' ') out.items.len -= 1;
    try out.append(a, '\n');
}
fn centered(a: A, out: *Out, text: []const u8, width: usize) !void {
    try out.appendNTimes(a, ' ', (width -| text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}
fn dsName(a: A, ds: *const Dataset) ![]const u8 {
    const upper = try std.ascii.allocUpperString(a, ds.name);
    if (std.mem.indexOfScalar(u8, upper, '.') != null) return upper;
    return std.fmt.allocPrint(a, "WORK.{s}", .{upper});
}
fn levelLabel(l: levels.Level) []const u8 {
    return std.mem.trim(u8, l.label, " ");
}
fn intText(a: A, v: f64) ![]const u8 {
    return std.fmt.allocPrint(a, "{d}", .{@as(i64, @intFromFloat(v))});
}

/// A binary role's displayed order: the event level first (verified for
/// REF='0', DESC and the EVENT=FIRST default).
const Profile = struct { event: usize, other: usize, lv: levels.Levels };

/// The "modeling the probability" note. SAS 9.4 (verified): for the outcome,
/// when neither EVENT=/REF= nor a DESCENDING option chose the event, SAS adds
/// the hint naming the other level.
fn modelingNote(a: A, name: []const u8, pr: Profile, hint: bool) ![]const u8 {
    const ev = levelLabel(pr.lv.levels[pr.event]);
    if (!hint) return std.fmt.allocPrint(a, "PROC CAUSALTRT is modeling the probability that {s}='{s}'.", .{ name, ev });
    return std.fmt.allocPrint(a, "PROC CAUSALTRT is modeling the probability that {s}='{s}'. One way to change this to model the probability that {s}='{s}' is to specify the DESCENDING option in the PROC statement.", .{ name, ev, name, levelLabel(pr.lv.levels[pr.other]) });
}
fn outcomeHint(s: *const Spec) bool {
    return !s.outcome.explicit and !s.outcome.descending and !s.descending;
}

/// Greedy word wrap at LINESIZE; a broken line keeps its trailing blank
/// (SAS 9.4 verified at LINESIZE=160 and 100).
fn wrapped(cx: proc.ProcCtx, out: *Out, text: []const u8) diag.Error!void {
    const a = cx.arena;
    const ls = io.global_linesize;
    if (text.len <= 64 or (ls != 0 and text.len <= ls)) {
        try out.appendSlice(a, text);
        try out.append(a, '\n');
        return;
    }
    // ponytail: the default LINESIZE wrap is not verified.
    if (ls == 0) return gap(cx, 0, "wrapping a long note without an explicit LINESIZE= is not verified", .{});
    var col: usize = 0;
    var it = std.mem.splitScalar(u8, text, ' ');
    var first = true;
    while (it.next()) |w| {
        if (!first) {
            if (col + 1 + w.len > ls) {
                try out.appendSlice(a, " \n");
                col = 0;
            } else {
                try out.append(a, ' ');
                col += 1;
            }
        }
        first = false;
        try out.appendSlice(a, w);
        col += w.len;
    }
    try out.append(a, '\n');
}

const ProfileResult = union(enum) { ok: Profile, invalid_ref, bad_levels: usize };

/// ORDER=FREQ for CAUSALTRT: descending frequency, ties in formatted order
/// (SAS 9.4 verified: a 100/100 tie of 'zz'(0) and 'aa'(1), 'zz' first in the
/// data, lists aa zz). The shared helper breaks FREQ ties by internal value.
fn freqOrdered(a: A, lv: levels.Levels) !levels.Levels {
    const idx = try a.alloc(usize, lv.levels.len);
    for (idx, 0..) |*x, k| x.* = k;
    const C = struct {
        l: []const levels.Level,
        fn less(c: @This(), x: usize, y: usize) bool {
            if (c.l[x].frequency != c.l[y].frequency) return c.l[x].frequency > c.l[y].frequency;
            return x < y;
        }
    };
    std.mem.sort(usize, idx, C{ .l = lv.levels }, C.less);
    const sorted = try a.alloc(levels.Level, idx.len);
    const inverse = try a.alloc(usize, idx.len);
    for (idx, 0..) |old, new| {
        sorted[new] = lv.levels[old];
        inverse[old] = new;
    }
    const map = try a.alloc(?usize, lv.row_to_level.len);
    for (lv.row_to_level, 0..) |r, k| map[k] = if (r) |v| inverse[v] else null;
    var out = lv;
    out.levels = sorted;
    out.row_to_level = map;
    return out;
}
fn buildLevels(a: A, ds: *const Dataset, rows: []const []const Value, col: usize, order: levels.Order, used: []const bool, freq: []const f64) diag.Error!levels.Levels {
    const lv = try levels.build(a, ds, rows, col, .{ .order = if (order == .freq) .formatted else order, .include_rows = used, .frequencies = freq });
    return if (order == .freq) try freqOrdered(a, lv) else lv;
}

/// SAS 9.4 (verified): an EVENT=/REF= level that is absent is checked before
/// the number of levels.
fn profile(cx: proc.ProcCtx, ds: *const Dataset, rows: []const []const Value, used: []const bool, freq: []const f64, b: Binary, global_desc: bool, order: levels.Order) diag.Error!ProfileResult {
    const lv = try buildLevels(cx.arena, ds, rows, b.col, order, used, freq);
    var chosen: ?usize = null;
    switch (b.pick) {
        .event, .ref => |v| {
            for (lv.levels, 0..) |l, k| if (std.mem.eql(u8, levelLabel(l), v)) {
                chosen = k;
            };
            if (chosen == null) return .invalid_ref;
        },
        else => {},
    }
    if (lv.levels.len != 2) return .{ .bad_levels = lv.levels.len };
    const desc = b.descending != global_desc;
    const first: usize = if (desc) 1 else 0;
    const last: usize = 1 - first;
    const event: usize = switch (b.pick) {
        .event_first => first,
        .event_last => last,
        .event => chosen.?,
        .ref => 1 - chosen.?,
    };
    return .{ .ok = .{ .event = event, .other = 1 - event, .lv = lv } };
}

fn renderProfile(cx: proc.ProcCtx, out: *Out, title: []const u8, name: []const u8, pr: Profile, hint: bool) diag.Error!void {
    const a = cx.arena;
    var vw = name.len;
    for (pr.lv.levels) |l| vw = @max(vw, levelLabel(l).len);
    const width = 8 + 4 + vw + 4 + 9;
    try out.appendSlice(a, "\n\n");
    try centered(a, out, title, width);
    try out.appendSlice(a, " \n");
    try pad(a, out, "Ordered", 8, true);
    try out.appendNTimes(a, ' ', 4 + vw + 4);
    try pad(a, out, "Total", 9, true);
    try endLine(a, out);
    try pad(a, out, "Value", 8, true);
    try out.appendNTimes(a, ' ', 4);
    try pad(a, out, name, vw, false);
    try out.appendNTimes(a, ' ', 4);
    try pad(a, out, "Frequency", 9, true);
    try endLine(a, out);
    try out.append(a, '\n');
    for ([_]usize{ pr.event, pr.other }, 1..) |k, ord| {
        try pad(a, out, try intText(a, @floatFromInt(ord)), 8, true);
        try out.appendNTimes(a, ' ', 4);
        try pad(a, out, levelLabel(pr.lv.levels[k]), vw, false);
        try out.appendNTimes(a, ' ', 4);
        try pad(a, out, try intText(a, pr.lv.levels[k].frequency), 9, true);
        try endLine(a, out);
    }
    try out.append(a, '\n');
    try wrapped(cx, out, try modelingNote(a, name, pr, hint));
}

/// The BY line flush left (verified with NOCENTER, the campaign default).
// ponytail: CENTER is a system-wide inert option in opensas (main.zig
// isInertOption); SAS 9.4 centers each table and rules the BY line
// (verified), which no opensas listing does yet.
fn byLine(a: A, out: *Out, ds: *const Dataset, row: []const Value, cols: []const usize) !void {
    var tmp: Out = .empty;
    try by.appendLine(a, &tmp, @constCast(ds), row, cols);
    try out.append(a, '\n');
    try out.appendSlice(a, std.mem.trimStart(u8, std.mem.trim(u8, tmp.items, "\n"), " "));
    try out.append(a, '\n');
}

/// "The CAUSALTRT Procedure" heading and the Model Information table.
fn modelInfo(a: A, out: *Out, s: *const Spec, ds: *const Dataset) !void {
    const cols = ds.columns.items;
    try out.appendSlice(a, "\nThe CAUSALTRT Procedure\n\n");
    var labels: std.ArrayList([]const u8) = .empty;
    var values: std.ArrayList([]const u8) = .empty;
    try labels.appendSlice(a, &.{ "Data Set", "Distribution", "Estimation Method", "Treatment Variable", "Outcome Variable" });
    try values.appendSlice(a, &.{ try dsName(a, ds), if (s.dist == .binomial) "Binomial" else "Normal", if (s.method == .ipwr) "IPWR" else "IPW", cols[s.treatment.col].name, cols[s.outcome.col].name });
    if (s.freq) |fc| {
        try labels.append(a, "Frequency Weight Variable");
        try values.append(a, cols[fc].name);
    }
    var lw: usize = 0;
    var vw: usize = 0;
    for (labels.items, values.items) |lb, v| {
        lw = @max(lw, lb.len);
        vw = @max(vw, v.len);
    }
    try centered(a, out, "Model Information", lw + 4 + vw);
    try out.append(a, '\n');
    for (labels.items, values.items) |lb, v| {
        try pad(a, out, lb, lw + 4, false);
        try pad(a, out, v, vw, true);
        try endLine(a, out);
    }
}

pub fn run(cx: proc.ProcCtx, out: *Out, toks: []const Token) diag.Error!void {
    const a = cx.arena;
    const s = try parse(cx, toks);
    const ds = s.input.ds;
    const l0 = line(toks, 0);
    const groups = try by.checkedSlices(a, ds, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    const cols = ds.columns.items;
    // SAS 9.4 (verified): an empty input or a BY group without a usable
    // observation prints the Model Information table and then this error;
    // the remaining BY groups are still analysed.
    const no_valid = "No valid observations due to invalid or missing values in the outcome, treatment, explanatory, or frequency variable.";
    if (groups.len == 0) {
        if (!s.noprint) try modelInfo(a, out, &s, ds);
        return cx.diags.fail(error.ParseError, l0, no_valid, .{});
    }
    for (groups) |grp| {
        const rows = grp.rows;
        const used = try a.alloc(bool, rows.len);
        const freq = try a.alloc(f64, rows.len);
        var n_used: usize = 0;
        var f_used: f64 = 0;
        var f_all: f64 = 0;
        // p.2473: drop missing treatment, outcome, frequency, predictors;
        // p.2438: FREQ is truncated; below 1 or missing: not used.
        for (rows, 0..) |row, r| {
            var ok = !selection.missing(row[s.treatment.col]) and !selection.missing(row[s.outcome.col]);
            for (s.ps_effects) |ci| if (selection.missing(row[ci])) {
                ok = false;
            };
            var f: f64 = 1;
            if (s.freq) |fc| {
                const raw = row[fc].num;
                // p.2450: below 1 or missing -> not used, and (SAS 9.4,
                // verified) left out of both Sum of Frequencies lines.
                if (std.math.isNan(raw) or raw < 1) {
                    ok = false;
                    f = 0;
                } else {
                    f = @trunc(raw);
                    f_all += f;
                }
            }
            used[r] = ok;
            freq[r] = if (ok) f else 0;
            if (ok) {
                n_used += 1;
                f_used += f;
            }
        }
        if (n_used == 0) {
            if (!s.noprint) {
                if (s.by_cols.len > 0) try byLine(a, out, ds, rows[0], s.by_cols);
                try modelInfo(a, out, &s, ds);
            }
            try cx.diags.recoverableErr(l0, no_valid, .{});
            continue;
        }
        const tpr = try profile(cx, ds, rows, used, freq, s.treatment, false, .formatted);
        const opr: ?ProfileResult = if (s.dist == .binomial) try profile(cx, ds, rows, used, freq, s.outcome, s.descending, s.rorder) else null;
        // SAS 9.4 (verified): these errors follow the Model Information table.
        const bad: ?struct { []const u8, ProfileResult } = if (tpr != .ok) .{ "treatment", tpr } else if (opr != null and opr.? != .ok) .{ "outcome", opr.? } else null;
        // A data error ends this step only (SAS 9.4 runs the next step): the
        // diag.Error class that does not set errhalt for later steps.
        if (bad) |bd| {
            if (!s.noprint) {
                if (s.by_cols.len > 0) try byLine(a, out, ds, rows[0], s.by_cols);
                try modelInfo(a, out, &s, ds);
            }
            const vname = cols[if (std.mem.eql(u8, bd[0], "treatment")) s.treatment.col else s.outcome.col].name;
            switch (bd[1]) {
                .invalid_ref => {
                    try cx.diags.recoverableErr(l0, "Invalid reference value for {s}.", .{vname});
                    return cx.diags.fail(error.ParseError, l0, no_valid, .{});
                },
                .bad_levels => |n| {
                    if (n < 2 and std.mem.eql(u8, bd[0], "treatment")) return cx.diags.fail(error.ParseError, l0, "The treatment variable, {s}, in the PSMODEL of TREATMENT statement has constant values.", .{vname});
                    if (n > 2 and std.mem.eql(u8, bd[0], "treatment")) return cx.diags.fail(error.ParseError, l0, "PROC CAUSALTRT does not support treatment variables with more than 2 levels. However, the treatment variable, {s}, in the PSMODEL or TREATMENT statement has {d} levels.", .{ vname, n });
                    if (n > 2) return cx.diags.fail(error.ParseError, l0, "PROC CAUSALTRT does not support discrete outcome variables with more than 2 levels. However, the outcome variable, {s}, in the MODEL or OUTCOME statement has {d} levels.", .{ vname, n });
                    return cx.diags.fail(error.ParseError, l0, "The discrete outcome variable, {s}, in the MODEL or OUTCOME statement has constant values.", .{vname});
                },
                .ok => unreachable,
            }
        }
        const tp = tpr.ok;
        var op: ?Profile = null;
        if (opr) |o| op = o.ok;
        // Class levels and the design.
        const class_lv = try a.alloc(levels.Levels, s.class.len);
        for (s.class, 0..) |ci, k| class_lv[k] = try buildLevels(a, ds, rows, ci, s.order, used, freq);
        var p: usize = 1;
        for (s.ps_effects) |ci| {
            if (std.mem.indexOfScalar(usize, s.class, ci)) |k| p += class_lv[k].levels.len -| 1 else p += 1;
        }
        const x = try a.alloc(f64, n_used * p);
        const tv = try a.alloc(f64, n_used);
        const yv = try a.alloc(f64, n_used);
        const fv = try a.alloc(f64, n_used);
        var n: usize = 0;
        for (rows, 0..) |row, r| {
            if (!used[r]) continue;
            const xi = x[n * p ..][0..p];
            xi[0] = 1;
            var c: usize = 1;
            for (s.ps_effects) |ci| {
                if (std.mem.indexOfScalar(usize, s.class, ci)) |k| {
                    const lvk = class_lv[k];
                    const lev = lvk.row_to_level[r].?;
                    for (0..lvk.levels.len -| 1) |j| {
                        xi[c] = if (lev == j) 1 else 0;
                        c += 1;
                    }
                } else {
                    xi[c] = row[ci].num;
                    c += 1;
                }
            }
            tv[n] = if (tp.lv.row_to_level[r].? == tp.event) 1 else 0;
            yv[n] = if (op) |o| (if (o.lv.row_to_level[r].? == o.event) 1 else 0) else row[s.outcome.col].num;
            fv[n] = freq[r];
            n += 1;
        }
        // The estimates need the converged MLE: GCONV=1E-8 (relative) can stop
        // one Fisher step early, which moved the ATE in the fifth digit on the
        // SAS-verified FREQ case; iterate to the full MLE instead.
        const fit = logit.fitWeighted(a, x, tv, n, p, fv, null, .{ .gconv = 1e-12, .max_iterations = 50 }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return gap(cx, l0, "a propensity score model that cannot be fitted (singular or separated) is not verified", .{}),
        };
        if (!fit.converged) return gap(cx, l0, "a propensity score model that does not converge is not verified", .{});
        for (fit.probabilities) |e| if (!(e > 1e-12 and e < 1 - 1e-12)) return gap(cx, l0, "propensity scores at 0 or 1 are not verified", .{});
        const est = (try estimate(a, s.method, x, p, tv, yv, fit.probabilities, fv)) orelse return gap(cx, l0, "a singular robust covariance matrix is not verified", .{});
        if (op) |o| try cx.diags.note(l0, "{s}", .{try modelingNote(a, cols[s.outcome.col].name, o, outcomeHint(&s))});
        if (s.noprint) continue;

        // Page 1: model information, counts, class levels, profiles.
        if (s.by_cols.len > 0) try byLine(a, out, ds, rows[0], s.by_cols);
        try modelInfo(a, out, &s, ds);
        try out.appendSlice(a, "\n\n");
        const count_rows = [_]struct { []const u8, f64 }{ .{ "Number of Observations Read", @floatFromInt(rows.len) }, .{ "Number of Observations Used", @floatFromInt(n_used) }, .{ "Sum of Frequencies Read", f_used }, .{ "Sum of Frequencies Used", f_all } };
        // Verified quirk: with FREQ, SAS labels the sum over the used
        // observations "Read" and the sum over all observations "Used".
        for (count_rows[0..if (s.freq != null) 4 else 2]) |cr| {
            try pad(a, out, cr[0], 27, false);
            try pad(a, out, try intText(a, cr[1]), 12, true);
            try endLine(a, out);
        }
        // Class Level Information: the CLASS variables used as PS effects.
        var shown: std.ArrayList(usize) = .empty;
        for (s.class, 0..) |ci, k| if (has(s.ps_effects, ci)) try shown.append(a, k);
        if (shown.items.len > 0) {
            var nw: usize = 5;
            var valw: usize = 6;
            const texts = try a.alloc([]const u8, s.class.len);
            for (shown.items) |k| {
                nw = @max(nw, cols[s.class[k]].name.len);
                var b: Out = .empty;
                for (class_lv[k].levels, 0..) |l, j| {
                    if (j > 0) try b.append(a, ' ');
                    try b.appendSlice(a, levelLabel(l));
                }
                texts[k] = b.items;
                valw = @max(valw, b.items.len);
            }
            try out.appendSlice(a, "\n\n");
            try centered(a, out, "Class Level Information", nw + 4 + 8 + 4 + valw);
            try out.appendSlice(a, " \n");
            try pad(a, out, "Class", nw + 4, false);
            try pad(a, out, "Levels", 8, true);
            try out.appendSlice(a, "    Values\n\n");
            for (shown.items) |k| {
                try pad(a, out, cols[s.class[k]].name, nw + 4, false);
                try pad(a, out, try intText(a, @floatFromInt(class_lv[k].levels.len)), 8, true);
                try out.appendNTimes(a, ' ', 4);
                try pad(a, out, texts[k], valw, false);
                try out.append(a, '\n');
            }
        }
        if (op) |o| try renderProfile(cx, out, "Response Profile", cols[s.outcome.col].name, o, outcomeHint(&s));
        try renderProfile(cx, out, "Treatment Profile", cols[s.treatment.col].name, tp, false);

        // Page 2: Analysis of Causal Effect.
        if (s.by_cols.len > 0) try byLine(a, out, ds, rows[0], s.by_cols);
        try out.appendSlice(a, "\nThe CAUSALTRT Procedure\n\n");
        try centered(a, out, "Analysis of Causal Effect", 93);
        try out.appendSlice(a, " \n");
        const z = zQuantile(s.alpha);
        const pct = try fixed(a, 100 * (1 - s.alpha), 0);
        if (@abs(100 * (1 - s.alpha) - @round(100 * (1 - s.alpha))) > 1e-9) return gap(cx, l0, "a confidence level that is not a whole percentage is not verified", .{});
        var hdr: Out = .empty;
        try hdr.appendNTimes(a, ' ', 13);
        try hdr.appendSlice(a, "Treatment");
        try pad(a, &hdr, "Robust", 46 - hdr.items.len, true);
        const wald = try std.fmt.allocPrint(a, "Wald {s}% ", .{pct});
        try hdr.appendNTimes(a, ' ', 52 + (18 - wald.len) / 2 - hdr.items.len);
        try hdr.appendSlice(a, wald);
        try out.appendSlice(a, hdr.items);
        try out.append(a, '\n');
        try out.appendSlice(a, "Parameter    Level        Estimate     Std Err      Confidence Limits           Z    Pr > |Z|\n\n");
        const tl = levelLabel(tp.lv.levels[tp.event]);
        const ol = levelLabel(tp.lv.levels[tp.other]);
        const lines = [_]struct { []const u8, []const u8, f64, f64 }{ .{ "POM", tl, est.pom1, est.se1 }, .{ "POM", ol, est.pom0, est.se0 }, .{ "ATE", "", est.ate, est.se_ate } };
        for (lines) |ln| {
            if (ln[1].len > 9) return gap(cx, l0, "treatment levels longer than 9 characters are not verified in the Analysis of Causal Effect table", .{});
            try pad(a, out, ln[0], 13, false);
            try pad(a, out, ln[1], 9, false);
            try pad(a, out, try dfmt(cx, ln[2]), 12, true);
            try pad(a, out, try fixed(a, ln[3], 4), 12, true);
            try pad(a, out, try dfmt(cx, ln[2] - z * ln[3]), 12, true);
            try pad(a, out, try dfmt(cx, ln[2] + z * ln[3]), 12, true);
            const zz = ln[2] / ln[3];
            if (!(@abs(zz) < 1e4)) return gap(cx, l0, "a Z statistic of 10000 or more is not verified", .{});
            try pad(a, out, try fixed(a, zz, 2), 11, true);
            try pad(a, out, try pvalue(a, logit.chiTail(zz * zz, 1)), 12, true);
            try out.append(a, '\n');
        }
    }
}

test {
    _ = @import("causaltrt_tests.zig");
}
