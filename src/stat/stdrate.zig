//! PROC STDRATE declarations, variable roles, observation selection and the
//! default direct rate standardization listing, SAS/STAT 15.4 physical
//! pp.9493-9502 (formulas: Rate p.9502, Direct Standardization pp.9507-9508).
//! `parse` records every documented declaration in `Spec`; `boundary` turns
//! each setting whose result or listing has not been proven against the SAS
//! reference into a D-009 gap (rc 2) before any listing text is produced.
const std = @import("std");
const proc = @import("../proc.zig");
const diag = @import("../diag.zig");
const parser = @import("../parser.zig");
const lex = @import("../lexer.zig");
const Dataset = @import("../dataset.zig").Dataset;
const Value = @import("../value.zig").Value;
const by = @import("by_groups.zig");
const format = @import("../format.zig");
const A = std.mem.Allocator;
const eq = std.ascii.eqlIgnoreCase;
const Out = std.ArrayList(u8);

pub const Method = enum { direct, indirect, mh };
pub const Stat = enum { rate, risk };
pub const Cl = enum { normal, lognormal, gamma, poisson, none };
pub const GammaType = enum { average, conservative };
pub const Effect = enum { ratio, diff };
pub const Order = enum { internal, data, formatted };
/// STATS / SMR confidence limits in the STRATA statement.
pub const StrataCl = enum { normal, lognormal, poisson, none };

/// POPULATION or REFERENCE variable roles (column indexes in their data set).
pub const Roles = struct {
    event: ?usize = null,
    total: ?usize = null,
    rate: ?usize = null,
    /// RATE(MULT=c): null means the STAT=RATE multiplier.
    rate_mult: ?f64 = null,
    risk: ?usize = null,
};

pub const Spec = struct {
    study: *Dataset,
    reference: ?*Dataset = null,
    study_name: []const u8,
    reference_name: ?[]const u8 = null,
    method: Method,
    af: bool = false,
    stat: Stat = .rate,
    mult: f64 = 100000,
    alpha: f64 = 0.05,
    cl: Cl = .normal,
    gamma_type: GammaType = .average,
    effect: ?Effect = null,
    /// PLOTS was written; `plots_none` when the only request is NONE.
    plots: bool = false,
    plots_none: bool = false,
    population: Roles = .{},
    group: ?usize = null,
    group_order: Order = .internal,
    exposed: ?[]const u8 = null,
    popevent: ?f64 = null,
    reference_statement: bool = false,
    ref: Roles = .{},
    refevent: ?f64 = null,
    refrate: ?f64 = null,
    refrate_mult: ?f64 = null,
    refrisk: ?f64 = null,
    reftotal: ?f64 = null,
    /// STRATA variables as columns of the study and of the reference data set.
    strata: []const usize = &.{},
    ref_strata: []const usize = &.{},
    strata_statement: bool = false,
    strata_effect: bool = false,
    missing: bool = false,
    order: Order = .internal,
    stats: ?StrataCl = null,
    smr: ?StrataCl = null,
    by_cols: []const usize = &.{},
    by_desc: []const bool = &.{},
    notsorted: bool = false,
    where: bool = false,
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
    return cx.diags.fail(error.ParseError, lineOf(t, i), "PROC STDRATE: invalid statement or token {s}", .{if (i < t.len) t[i].text else "<end>"});
}
fn user(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return cx.diags.fail(error.ParseError, line, "PROC STDRATE: " ++ text, args);
}
fn gap(cx: proc.ProcCtx, line: usize, comptime text: []const u8, args: anytype) diag.Error {
    return proc.failGap(cx.diags, line, "PROC STDRATE: " ++ text, args);
}

/// `keyword = number`, starting at the keyword; returns the value.
fn number(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!f64 {
    if (!at(t, i.* + 1, .eq)) return invalid(cx, t, i.* + 1);
    var j = i.* + 2;
    var sign: f64 = 1;
    if (at(t, j, .minus)) {
        sign = -1;
        j += 1;
    }
    if (!at(t, j, .number)) return invalid(cx, t, j);
    const x = std.fmt.parseFloat(f64, t[j].text) catch return invalid(cx, t, j);
    i.* = j + 1;
    return sign * x;
}

/// `(MULT=c)` at `i` if present. c must be a positive power of 10 (p.9497).
fn multiplier(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!?f64 {
    if (!at(t, i.*, .lparen)) return null;
    if (!kw(t, i.* + 1, "mult")) return invalid(cx, t, i.* + 1);
    var j = i.* + 1;
    const c = try number(cx, t, &j);
    if (!at(t, j, .rparen)) return invalid(cx, t, j);
    const log = @log10(c);
    if (!(c > 0) or @abs(log - @round(log)) > 1e-9) return user(cx, lineOf(t, j), "MULT= must be a power of 10", .{});
    i.* = j + 1;
    return c;
}

/// `<member>` or `<libref>.<member>` at `i`; data set options are a gap.
fn member(cx: proc.ProcCtx, t: []const lex.Token, i: *usize, option: []const u8) diag.Error![]const u8 {
    if (!at(t, i.*, .name)) return invalid(cx, t, i.*);
    var name = t[i.*].text;
    i.* += 1;
    if (at(t, i.*, .dot)) {
        if (!at(t, i.* + 1, .name)) return invalid(cx, t, i.* + 1);
        name = try std.fmt.allocPrint(cx.arena, "{s}.{s}", .{ name, t[i.* + 1].text });
        i.* += 2;
    }
    if (at(t, i.*, .lparen)) {
        // DATA= options are applied by procInput (SAS 9.4 reference run:
        // DATA=(WHERE=) selects study observations); REFDATA= options are open.
        if (!eq(option, "DATA")) return gap(cx, t[i.*].line, "data set options on {s}= are not implemented", .{option});
        i.* = proc.skipParen(t, i.*);
    }
    return name;
}

fn orderOf(cx: proc.ProcCtx, t: []const lex.Token, i: usize) diag.Error!Order {
    if (kw(t, i, "data")) return .data;
    if (kw(t, i, "formatted")) return .formatted;
    if (kw(t, i, "internal")) return .internal;
    return invalid(cx, t, i);
}

fn numericColumn(cx: proc.ProcCtx, ds: *const Dataset, t: []const lex.Token, i: usize, role: []const u8) diag.Error!usize {
    if (!at(t, i, .name)) return invalid(cx, t, i);
    const c = ds.indexOf(t[i].text) orelse return cx.diags.fail(error.ParseError, t[i].line, "Variable {s} not found.", .{t[i].text});
    if (ds.columns.items[c].type != .num) return user(cx, t[i].line, "{s} variable {s} must be numeric", .{ role, t[i].text });
    return c;
}

/// EVENT= TOTAL= RATE<(MULT=c)>= RISK= shared by POPULATION and REFERENCE.
/// Returns false when the option at `i` is not one of them.
fn roleOption(cx: proc.ProcCtx, ds: ?*const Dataset, t: []const lex.Token, i: *usize, roles: *Roles, statement: []const u8) diag.Error!bool {
    const word = t[i.*].text;
    const slot: *?usize = if (eq(word, "event")) &roles.event else if (eq(word, "total")) &roles.total else if (eq(word, "rate")) &roles.rate else if (eq(word, "risk")) &roles.risk else return false;
    if (slot.* != null) return user(cx, t[i.*].line, "{s} option {s}= is specified more than once", .{ statement, word });
    var j = i.* + 1;
    if (eq(word, "rate")) roles.rate_mult = try multiplier(cx, t, &j);
    if (!at(t, j, .eq)) return invalid(cx, t, j);
    const data = ds orelse return user(cx, t[i.*].line, "REFERENCE variables require the REFDATA= data set", .{});
    slot.* = try numericColumn(cx, data, t, j + 1, word);
    i.* = j + 2;
    return true;
}

fn strataCl(cx: proc.ProcCtx, t: []const lex.Token, i: *usize) diag.Error!StrataCl {
    var j = i.* + 1;
    var cl: StrataCl = .normal;
    if (at(t, j, .lparen)) {
        if (!kw(t, j + 1, "cl") or !at(t, j + 2, .eq) or !at(t, j + 4, .rparen)) return invalid(cx, t, j + 1);
        cl = if (kw(t, j + 3, "normal")) .normal else if (kw(t, j + 3, "lognormal")) .lognormal else if (kw(t, j + 3, "poisson")) .poisson else if (kw(t, j + 3, "none")) .none else return invalid(cx, t, j + 3);
        j += 5;
    }
    i.* = j;
    return cl;
}

fn sameTokens(x: []const lex.Token, y: []const lex.Token) bool {
    if (x.len != y.len) return false;
    for (x, y) |p, q| if (p.tag != q.tag or !eq(p.text, q.text)) return false;
    return true;
}

pub fn parse(cx: proc.ProcCtx, t: []const lex.Token) diag.Error!Spec {
    var s: Spec = .{ .study = undefined, .study_name = "", .method = undefined };
    var data: ?[]const u8 = null;
    var method: ?Method = null;
    var stat_seen = false;
    var i: usize = 2;
    while (i < t.len and !at(t, i, .semicolon) and !at(t, i, .eof)) {
        if (!at(t, i, .name)) return invalid(cx, t, i);
        const word = t[i].text;
        if (eq(word, "data") and at(t, i + 1, .eq)) {
            if (data != null) return invalid(cx, t, i);
            i += 2;
            data = try member(cx, t, &i, "DATA");
        } else if (eq(word, "refdata") and at(t, i + 1, .eq)) {
            if (s.reference_name != null) return invalid(cx, t, i);
            i += 2;
            s.reference_name = try member(cx, t, &i, "REFDATA");
        } else if ((eq(word, "method") or eq(word, "m")) and at(t, i + 1, .eq)) {
            if (method != null) return invalid(cx, t, i);
            method = if (kw(t, i + 2, "direct")) .direct else if (kw(t, i + 2, "indirect")) .indirect else if (kw(t, i + 2, "mh")) .mh else return invalid(cx, t, i + 2);
            i += 3;
            if (at(t, i, .lparen)) {
                if (!kw(t, i + 1, "af") or !at(t, i + 2, .rparen)) return invalid(cx, t, i + 1);
                if (method.? == .direct) return user(cx, t[i].line, "the AF suboption applies only to METHOD=INDIRECT and METHOD=MH", .{});
                s.af = true;
                i += 3;
            }
        } else if (eq(word, "stat") and at(t, i + 1, .eq)) {
            if (stat_seen) return invalid(cx, t, i);
            stat_seen = true;
            s.stat = if (kw(t, i + 2, "rate")) .rate else if (kw(t, i + 2, "risk")) .risk else return invalid(cx, t, i + 2);
            i += 3;
            if (at(t, i, .lparen)) {
                if (s.stat == .risk) return invalid(cx, t, i);
                s.mult = (try multiplier(cx, t, &i)).?;
            }
        } else if (eq(word, "effect")) {
            if (s.effect != null) return invalid(cx, t, i);
            s.effect = .ratio;
            i += 1;
            if (at(t, i, .eq)) {
                s.effect = if (kw(t, i + 1, "ratio")) .ratio else if (kw(t, i + 1, "diff")) .diff else return invalid(cx, t, i + 1);
                i += 2;
            }
        } else if (eq(word, "alpha")) {
            s.alpha = try number(cx, t, &i);
            if (!(s.alpha > 0 and s.alpha < 1)) return user(cx, t[i - 1].line, "ALPHA= must be between 0 and 1", .{});
        } else if (eq(word, "cl") and at(t, i + 1, .eq)) {
            s.cl = if (kw(t, i + 2, "normal")) .normal else if (kw(t, i + 2, "lognormal")) .lognormal else if (kw(t, i + 2, "gamma")) .gamma else if (kw(t, i + 2, "poisson")) .poisson else if (kw(t, i + 2, "none")) .none else return invalid(cx, t, i + 2);
            i += 3;
            if (at(t, i, .lparen)) {
                if (s.cl != .gamma or !kw(t, i + 1, "type") or !at(t, i + 2, .eq) or !at(t, i + 4, .rparen)) return invalid(cx, t, i + 1);
                s.gamma_type = if (kw(t, i + 3, "average")) .average else if (kw(t, i + 3, "conservative")) .conservative else return invalid(cx, t, i + 3);
                i += 5;
            }
        } else if (eq(word, "plots")) {
            // ponytail: the plot requests are owned by the STDRATE graphics
            // ticket; only the request list's extent and a lone NONE are read.
            s.plots = true;
            i += 1;
            if (at(t, i, .lparen)) i = proc.skipParen(t, i);
            if (at(t, i, .eq)) {
                if (at(t, i + 1, .lparen)) {
                    i = proc.skipParen(t, i + 1);
                } else {
                    if (!at(t, i + 1, .name)) return invalid(cx, t, i + 1);
                    s.plots_none = eq(t[i + 1].text, "none");
                    i += 2;
                }
            }
        } else return invalid(cx, t, i);
    }
    if (!at(t, i, .semicolon)) return invalid(cx, t, i);
    s.method = method orelse return user(cx, lineOf(t, 0), "the METHOD= option is required", .{});
    // An omitted DATA= reads the most recently created data set (SAS 9.4
    // reference run, 2026-11-28: the listing names that data set).
    const raw = if (data) |name| cx.lib.find(name) orelse return user(cx, 0, "input data set {s} not found", .{name}) else proc.lastDataset(cx.lib) orelse return user(cx, 0, "there is no most recently created data set for DATA=", .{});
    s.study_name = data orelse raw.name;
    // The global OBS=/FIRSTOBS= window and the WHERE statement apply to the
    // study and to the reference data set alike (SAS 9.4 reference run: a
    // WHERE variable absent from REFDATA= is an ERROR); data set options are
    // rejected above.
    s.study = try proc.procInput(cx.arena, raw, t, cx.diags);
    if (s.reference_name) |name| {
        const ref = cx.lib.find(name) orelse return user(cx, 0, "reference data set {s} not found", .{name});
        // The reference sees the WHERE statement but not the DATA= options.
        var h: usize = 2;
        while (h < t.len and !at(t, h, .semicolon)) h += 1;
        const ref_tokens = try std.mem.concat(cx.arena, lex.Token, &.{ t[0..2], t[h..] });
        s.reference = try proc.procInput(cx.arena, ref, ref_tokens, cx.diags);
    }
    var formats: std.ArrayList(proc.VarSpec) = .empty;
    var bys: by.Statements = .{};
    var population_seen = false;
    var strata_names: std.ArrayList(lex.Token) = .empty;
    var reference_tokens: []const lex.Token = &.{};
    var strata_tokens: []const lex.Token = &.{};
    i += 1;
    while (i < t.len and !at(t, i, .eof)) {
        if (at(t, i, .semicolon)) {
            i += 1;
            continue;
        }
        var end = i;
        while (end < t.len and !at(t, end, .semicolon) and !at(t, end, .eof)) end += 1;
        if (!at(t, end, .semicolon)) return invalid(cx, t, i);
        if (kw(t, i, "population")) {
            // SAS 9.4 reference run: a second POPULATION statement under
            // METHOD=DIRECT stops the step with this ERROR (even when identical).
            if (population_seen and s.method == .direct) return cx.diags.fail(error.ParseError, t[i].line, "The population stratum-specific rates or risks must be available for METHOD=DIRECT or METHOD=MH.", .{});
            if (population_seen) return gap(cx, t[i].line, "duplicate POPULATION statement policy is not verified", .{});
            population_seen = true;
            var j = i + 1;
            while (j < end) {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                if (try roleOption(cx, s.study, t, &j, &s.population, "POPULATION")) continue;
                if (kw(t, j, "group")) {
                    if (s.group != null) return user(cx, t[j].line, "POPULATION option GROUP= is specified more than once", .{});
                    j += 1;
                    if (at(t, j, .lparen)) {
                        j += 1;
                        while (!at(t, j, .rparen)) {
                            if (kw(t, j, "order") and at(t, j + 1, .eq)) {
                                s.group_order = try orderOf(cx, t, j + 2);
                            } else if (kw(t, j, "exposed") and at(t, j + 1, .eq)) {
                                if (!at(t, j + 2, .string)) return invalid(cx, t, j + 2);
                                s.exposed = t[j + 2].text;
                            } else return invalid(cx, t, j);
                            j += 3;
                        }
                        j += 1;
                    }
                    if (!at(t, j, .eq) or !at(t, j + 1, .name)) return invalid(cx, t, j);
                    s.group = s.study.indexOf(t[j + 1].text) orelse return cx.diags.fail(error.ParseError, t[j + 1].line, "Variable {s} not found.", .{t[j + 1].text});
                    j += 2;
                } else if (kw(t, j, "popevent")) {
                    s.popevent = try number(cx, t, &j);
                    if (!(s.popevent.? >= 0)) return user(cx, t[j - 1].line, "POPEVENT= must be nonnegative", .{});
                } else return invalid(cx, t, j);
            }
        } else if (kw(t, i, "reference")) {
            // An identical repeated REFERENCE statement is accepted (SAS 9.4
            // reference run); a differing one has an unverified precedence.
            if (s.reference_statement) {
                if (sameTokens(reference_tokens, t[i..end])) {
                    i = end + 1;
                    continue;
                }
                return gap(cx, t[i].line, "a second, different REFERENCE statement is not verified", .{});
            }
            s.reference_statement = true;
            reference_tokens = t[i..end];
            var j = i + 1;
            while (j < end) {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                if (try roleOption(cx, s.reference, t, &j, &s.ref, "REFERENCE")) continue;
                if (kw(t, j, "refevent")) {
                    s.refevent = try number(cx, t, &j);
                    if (!(s.refevent.? >= 0)) return user(cx, t[j - 1].line, "REFEVENT= must be nonnegative", .{});
                } else if (kw(t, j, "reftotal")) {
                    s.reftotal = try number(cx, t, &j);
                    if (!(s.reftotal.? > 0)) return user(cx, t[j - 1].line, "REFTOTAL= must be positive", .{});
                } else if (kw(t, j, "refrisk")) {
                    s.refrisk = try number(cx, t, &j);
                    if (!(s.refrisk.? >= 0 and s.refrisk.? <= 1)) return user(cx, t[j - 1].line, "REFRISK= must be between 0 and 1", .{});
                } else if (kw(t, j, "refrate")) {
                    var k = j + 1;
                    s.refrate_mult = try multiplier(cx, t, &k);
                    j = k - 1;
                    s.refrate = try number(cx, t, &j);
                    if (!(s.refrate.? >= 0)) return user(cx, t[j - 1].line, "REFRATE= must be nonnegative", .{});
                } else return invalid(cx, t, j);
            }
        } else if (kw(t, i, "strata")) {
            if (s.strata_statement) {
                if (sameTokens(strata_tokens, t[i..end])) {
                    i = end + 1;
                    continue;
                }
                return gap(cx, t[i].line, "a second, different STRATA statement is not verified", .{});
            }
            s.strata_statement = true;
            strata_tokens = t[i..end];
            var j = i + 1;
            while (j < end and !at(t, j, .slash)) : (j += 1) {
                if (!at(t, j, .name)) return invalid(cx, t, j);
                try strata_names.append(cx.arena, t[j]);
            }
            if (at(t, j, .slash)) j += 1;
            while (j < end) {
                if (kw(t, j, "missing")) {
                    s.missing = true;
                    j += 1;
                } else if (kw(t, j, "effect")) {
                    s.strata_effect = true;
                    j += 1;
                } else if (kw(t, j, "order") and at(t, j + 1, .eq)) {
                    s.order = try orderOf(cx, t, j + 2);
                    j += 3;
                } else if (kw(t, j, "stats")) {
                    s.stats = try strataCl(cx, t, &j);
                } else if (kw(t, j, "smr")) {
                    s.smr = try strataCl(cx, t, &j);
                } else return invalid(cx, t, j);
            }
        } else if (kw(t, i, "by")) {
            var j = i;
            try bys.read(cx.arena, t, &j);
        } else if (kw(t, i, "where")) {
            s.where = true;
        } else if (kw(t, i, "format")) {
            // Formatted values determine the STRATA levels (p.9500); the
            // statement applies to both data sets (SAS 9.4 reference run).
            var j = i;
            try proc.parseProcFormat(cx.arena, t, &j, &formats);
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!population_seen) return user(cx, 0, "the POPULATION statement is required", .{});
    for (formats.items) |f| if (s.study.indexOf(f.name) == null) return cx.diags.fail(error.ParseError, 0, "Variable {s} not found.", .{f.name});
    s.study = try by.withFormats(cx.arena, s.study, formats.items);
    if (s.reference) |ref| s.reference = try by.withFormats(cx.arena, ref, formats.items);
    if (s.method != .mh and !s.reference_statement) return user(cx, 0, "the REFERENCE statement is required with METHOD=DIRECT and METHOD=INDIRECT", .{});
    if (s.method == .mh and s.group == null) return user(cx, 0, "the GROUP= option in the POPULATION statement is required with METHOD=MH", .{});
    // STRATA variables are "in all input data sets" (p.9500).
    // A repeated STRATA variable forms the same strata as one occurrence
    // (SAS 9.4 reference run: `strata age age;` gives 2 strata).
    var unique: std.ArrayList(lex.Token) = .empty;
    for (strata_names.items) |token| {
        for (unique.items) |u| {
            if (eq(u.text, token.text)) break;
        } else try unique.append(cx.arena, token);
    }
    const cols = try cx.arena.alloc(usize, unique.items.len);
    const ref_cols = try cx.arena.alloc(usize, if (s.reference != null) cols.len else 0);
    for (unique.items, 0..) |token, k| {
        cols[k] = s.study.indexOf(token.text) orelse return cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{token.text});
        if (s.reference) |ref| {
            ref_cols[k] = ref.indexOf(token.text) orelse return user(cx, token.line, "STRATA variable {s} not found in the reference data set", .{token.text});
            if (ref.columns.items[ref_cols[k]].type != s.study.columns.items[cols[k]].type) return user(cx, token.line, "STRATA variable {s} has different types in the study and reference data sets", .{token.text});
        }
    }
    s.strata = cols;
    s.ref_strata = ref_cols;
    const pb = try bys.resolve(cx.arena, s.study, cx.diags);
    const by_cols = try cx.arena.alloc(usize, pb.names.len);
    for (pb.names, 0..) |n, k| by_cols[k] = s.study.indexOf(n).?;
    s.by_cols = by_cols;
    s.by_desc = pb.desc;
    s.notsorted = pb.notsorted;
    return s;
}

/// Execution boundary: everything outside the proven default direct rate
/// standardization (one study population, REFERENCE TOTAL=) is a loud gap.
pub fn boundary(cx: proc.ProcCtx, s: Spec) diag.Error!void {
    if (s.method == .indirect) return gap(cx, 0, "METHOD=INDIRECT is not implemented", .{});
    if (s.method == .mh) return gap(cx, 0, "METHOD=MH is not implemented", .{});
    if (s.stat == .risk) return gap(cx, 0, "STAT=RISK is not implemented", .{});
    if (s.alpha != 0.05) return gap(cx, 0, "ALPHA= other than 0.05 is not implemented", .{});
    if (s.cl != .normal) return gap(cx, 0, "CL= other than NORMAL is not implemented", .{});
    if (s.effect != null) return gap(cx, 0, "the EFFECT option is not implemented", .{});
    if (s.plots and !s.plots_none) return gap(cx, 0, "PLOTS= requests are not implemented", .{});
    // The CLI always carries a graphics session; only ODS GRAPHICS ON makes
    // SAS draw the default stratum-specific rate plot.
    if (!s.plots_none) if (cx.graphics) |g| if (g.enabled == true) return gap(cx, 0, "stratum-specific rate plots under ODS GRAPHICS are not implemented", .{});
    if (s.group != null) return gap(cx, 0, "POPULATION GROUP= (several study populations) is not implemented", .{});
    if (s.popevent != null) return gap(cx, 0, "POPULATION POPEVENT= is not implemented", .{});
    if (s.population.rate != null or s.population.risk != null) return gap(cx, 0, "POPULATION RATE= and RISK= input is not implemented", .{});
    if (s.population.event == null or s.population.total == null) return gap(cx, 0, "POPULATION without both EVENT= and TOTAL= is not implemented", .{});
    if (s.reference == null) return cx.diags.fail(error.ParseError, 0, "PROC STDRATE: the REFDATA= data set is required with METHOD=DIRECT", .{});
    if (s.ref.event != null or s.ref.rate != null or s.ref.risk != null) return gap(cx, 0, "REFERENCE EVENT=, RATE= and RISK= are not implemented", .{});
    if (s.refevent != null or s.refrate != null or s.refrisk != null or s.reftotal != null) return gap(cx, 0, "REFERENCE REFEVENT=, REFRATE=, REFRISK= and REFTOTAL= are not implemented", .{});
    if (s.ref.total == null) return gap(cx, 0, "REFERENCE without TOTAL= is not implemented", .{});
    if (s.strata_effect or s.stats != null or s.smr != null) return gap(cx, 0, "STRATA options EFFECT, STATS and SMR are not implemented", .{});
}

pub const Stratum = struct {
    /// Representative row of the data set the stratum was first seen in.
    key: []const Value,
    events: f64 = 0,
    time: f64 = 0,
    ref_time: f64 = 0,
    in_study: bool = false,
    in_reference: bool = false,
    study_obs: usize = 0,
    missing_events: usize = 0,
    missing_total: bool = false,
};
pub const Selected = struct {
    /// Strata present in both data sets, in display order.
    strata: []const Stratum,
    /// Distinct reference strata ("Number of Strata" in the listing).
    reference_strata: usize,
    /// Observations read and used, per data set.
    study_read: usize,
    study_used: usize,
    reference_read: usize,
    reference_used: usize,
};
fn missingValue(v: Value) bool {
    return switch (v) {
        .num => |x| std.math.isNan(x),
        .str => |text| std.mem.trimEnd(u8, text, " ").len == 0,
    };
}
fn sameLevel(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| switch (y) {
            // ponytail: MISSING pools all numeric missing values into one
            // level; special missings (.A-.Z) as separate levels are unverified.
            .num => |b| a == b or (std.math.isNan(a) and std.math.isNan(b)),
            .str => false,
        },
        .str => |a| switch (y) {
            .str => |b| std.mem.eql(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, b, " ")),
            .num => false,
        },
    };
}
fn levelLess(x: Value, y: Value) bool {
    return switch (x) {
        .num => |a| (std.math.isNan(a) and !std.math.isNan(y.num)) or a < y.num,
        .str => |a| std.mem.order(u8, std.mem.trimEnd(u8, a, " "), std.mem.trimEnd(u8, y.str, " ")) == .lt,
    };
}
const KeyOrder = struct {
    n: usize,
    fn less(self: KeyOrder, x: Stratum, y: Stratum) bool {
        for (x.key[0..self.n], y.key[0..self.n]) |a, b| {
            if (levelLess(a, b)) return true;
            if (levelLess(b, a)) return false;
        }
        return false;
    }
};

/// Observation selection for direct standardization (STRATA MISSING,
/// physical p.9500): an observation with a missing STRATA value is excluded
/// unless MISSING, which makes missing a level of its own; without STRATA
/// variables every observation is in one stratum (p.9500). Levels are matched
/// between the study and reference data sets by unformatted value and
/// returned in ORDER=INTERNAL order unless ORDER=DATA (study order, then
/// reference-only levels). Rules verified by SAS 9.4 reference runs
/// (2026-11-28, invented data): several study observations in one stratum
/// add up their events and population-times, and several reference
/// observations their population-times (verified without STRATA variables); a study stratum whose only
/// observation has a missing EVENT= value is an ERROR ("The population rate
/// is missing ..."); a study stratum absent from the reference is an ERROR
/// ("The reference total is missing ..."); a reference stratum absent from
/// the study draws a WARNING, counts in "Number of Strata" and is left out
/// of the estimate. Other data whose treatment is open is a gap.
pub fn select(cx: proc.ProcCtx, s: Spec, study_rows: []const []const Value) diag.Error!Selected {
    const a = cx.arena;
    const ref = s.reference.?;
    const event = s.population.event.?;
    const total = s.population.total.?;
    const ref_total = s.ref.total.?;
    var list: std.ArrayList(Stratum) = .empty;
    var result: Selected = .{ .strata = &.{}, .reference_strata = 0, .study_read = study_rows.len, .study_used = 0, .reference_read = ref.rowCount(), .reference_used = 0 };
    for ([_]bool{ false, true }) |is_ref| {
        const cols = if (is_ref) s.ref_strata else s.strata;
        const count = if (is_ref) ref.rowCount() else study_rows.len;
        rows: for (0..count) |r| {
            const row = if (is_ref) ref.row(r) else study_rows[r];
            const key = try a.alloc(Value, cols.len);
            const ds = if (is_ref) ref else s.study;
            for (cols, key) |c, *k| {
                if (missingValue(row[c]) and !s.missing) continue :rows;
                k.* = row[c];
                // A formatted STRATA variable's level is its formatted value.
                if (ds.columns.items[c].format) |spec| k.* = .{ .str = std.mem.trim(u8, try format.apply(a, row[c], spec), " ") };
            }
            var found: ?*Stratum = null;
            for (list.items) |*st| {
                var same = true;
                for (st.key, key) |x, y| same = same and sameLevel(x, y);
                if (same) found = st;
            }
            const st = found orelse blk: {
                try list.append(a, .{ .key = key });
                break :blk &list.items[list.items.len - 1];
            };
            if (is_ref) {
                const x = row[ref_total].num;
                if (!(x > 0)) return gap(cx, 0, "missing or nonpositive REFERENCE TOTAL= values are not verified", .{});
                st.ref_time += x;
                if (!st.in_reference) result.reference_strata += 1;
                st.in_reference = true;
                result.reference_used += 1;
            } else {
                st.in_study = true;
                st.study_obs += 1;
                const d = row[event].num;
                const time = row[total].num;
                // A missing EVENT= value adds nothing to the stratum's events
                // while its TOTAL= still counts (SAS 9.4 reference run); a
                // missing TOTAL= is verified only as a stratum's only value.
                if (std.math.isNan(time)) {
                    st.missing_total = true;
                    continue :rows;
                }
                if (!(time > 0)) return gap(cx, 0, "nonpositive POPULATION TOTAL= values are not verified", .{});
                st.time += time;
                if (std.math.isNan(d)) {
                    st.missing_events += 1;
                    continue :rows;
                }
                if (!(d >= 0)) return gap(cx, 0, "negative POPULATION EVENT= values are not verified", .{});
                st.events += d;
                result.study_used += 1;
            }
        }
    }
    for (list.items) |st| {
        if (st.missing_total and st.study_obs > 1) return gap(cx, 0, "a missing TOTAL= value beside other observations of its stratum is not verified", .{});
        if (st.in_study and (st.missing_total or st.missing_events == st.study_obs)) {
            return cx.diags.fail(error.ParseError, 0, "The population rate is missing in the stratum {s}.", .{try stratumLabel(cx, s, st)});
        }
        if (st.in_study and !st.in_reference) return cx.diags.fail(error.ParseError, 0, "The reference total is missing in the stratum {s}.", .{try stratumLabel(cx, s, st)});
    }
    var matched: std.ArrayList(Stratum) = .empty;
    for (list.items) |st| {
        if (st.in_study) {
            try matched.append(a, st);
        } else try cx.diags.warnStatus(0, "The stratum in the REFDATA= data set, {s}, does not have a matched stratum in the DATA= data set.", .{try stratumLabel(cx, s, st)});
    }
    // An empty study data set prints the table with missing values (SAS
    // 9.4 reference run); a study whose observations are all excluded is open.
    if (matched.items.len == 0 and study_rows.len > 0) return gap(cx, 0, "the result for a study without usable observations is not verified", .{});
    if (s.order == .formatted) return gap(cx, 0, "STRATA ORDER=FORMATTED is not implemented", .{});
    if (s.order == .internal) std.mem.sort(Stratum, matched.items, KeyOrder{ .n = s.strata.len }, KeyOrder.less);
    result.strata = matched.items;
    return result;
}

/// `name=value ...` as the SAS stratum messages print it (SAS 9.4
/// reference runs): character values trimmed, numeric values in BEST16.
/// right-aligned, several STRATA variables separated by blanks.
fn stratumLabel(cx: proc.ProcCtx, s: Spec, st: Stratum) diag.Error![]const u8 {
    var text: Out = .empty;
    for (s.strata, st.key, 0..) |c, v, k| {
        const col = s.study.columns.items[c];
        if (col.format != null or missingValue(v)) return gap(cx, 0, "stratum messages for formatted or missing STRATA levels are not verified", .{});
        if (k > 0) try text.append(cx.arena, ' ');
        try text.print(cx.arena, "{s}=", .{col.name});
        switch (v) {
            .str => |x| try text.appendSlice(cx.arena, std.mem.trimEnd(u8, x, " ")),
            .num => |x| {
                const num = std.mem.trim(u8, try format.bestNumW(cx.arena, x, 16), " ");
                try text.appendNTimes(cx.arena, ' ', 16 -| num.len);
                try text.appendSlice(cx.arena, num);
            },
        }
    }
    if (s.strata.len == 0) return gap(cx, 0, "stratum messages without STRATA variables are not verified", .{});
    return text.items;
}

pub const Direct = struct {
    events: f64,
    time: f64,
    crude: f64,
    expected: f64,
    ref_time: f64,
    estimate: f64,
    se: f64,
    lower: f64,
    upper: f64,
};
const z975: f64 = 1.959963984540054;

/// Directly standardized rate, physical pp.9507-9508: with stratum rates
/// d_j/T_j and reference population-times R_j, the estimate is
/// sum(R_j d_j/T_j) / sum(R_j), its variance sum((R_j/R)^2 d_j/T_j^2)
/// (Poisson events, p.9502), and the normal limits are estimate -/+ z se.
/// Rates are per population-time unit; the expected events are sum(R_j d_j/T_j).
pub fn direct(strata: []const Stratum) Direct {
    var r: Direct = .{ .events = 0, .time = 0, .crude = 0, .expected = 0, .ref_time = 0, .estimate = 0, .se = 0, .lower = 0, .upper = 0 };
    for (strata) |st| {
        r.events += st.events;
        r.time += st.time;
        r.ref_time += st.ref_time;
        r.expected += st.ref_time * st.events / st.time;
    }
    var variance: f64 = 0;
    for (strata) |st| {
        const w = st.ref_time / r.ref_time;
        variance += w * w * st.events / (st.time * st.time);
    }
    r.crude = r.events / r.time;
    r.estimate = r.expected / r.ref_time;
    r.se = @sqrt(variance);
    r.lower = r.estimate - z975 * r.se;
    r.upper = r.estimate + z975 * r.se;
    return r;
}

fn right(a: A, out: *Out, text: []const u8, width: usize) !void {
    if (text.len < width) try out.appendNTimes(a, ' ', width - text.len);
    try out.appendSlice(a, text);
}
fn displayName(a: A, name: []const u8) ![]const u8 {
    const upper = try std.ascii.allocUpperString(a, name);
    if (std.mem.indexOfScalar(u8, upper, '.') != null) return upper;
    return std.fmt.allocPrint(a, "WORK.{s}", .{upper});
}
fn infoLine(cx: proc.ProcCtx, out: *Out, label: []const u8, value: []const u8) diag.Error!void {
    // ponytail: the reference table is 47 columns wide with its widest value
    // (22 characters); a longer value would widen it in an unverified way.
    if (value.len > 22) return gap(cx, 0, "Standardization Information values longer than 22 characters are not verified", .{});
    try out.appendSlice(cx.arena, label);
    try right(cx.arena, out, value, 47 - label.len);
    try out.append(cx.arena, '\n');
}

fn pageStart(cx: proc.ProcCtx, out: *Out, first: *bool, byline: []const u8) !void {
    if (!first.*) if (cx.listing_titles) |titles| try titles.emitTitles(cx.arena, out);
    first.* = false;
    try out.append(cx.arena, '\n');
    if (byline.len > 0) try out.print(cx.arena, "{s}\n\n", .{byline});
    try out.appendSlice(cx.arena, "The STDRATE Procedure\n\n");
}

/// `text` centered over the 95-column estimates table, the odd column on
/// the left (SAS reference listings for MULT=100000 and MULT=1000).
fn centered(a: A, out: *Out, text: []const u8) !void {
    if (text.len < 95) try out.appendNTimes(a, ' ', (96 - text.len) / 2);
    try out.appendSlice(a, text);
    try out.append(a, '\n');
}

fn render(cx: proc.ProcCtx, out: *Out, first: *bool, byline: []const u8, s: Spec, sel: Selected) diag.Error!void {
    const a = cx.arena;
    const empty = sel.strata.len == 0;
    const r = direct(sel.strata);
    const rates = [_]f64{ r.crude * s.mult, r.estimate * s.mult, r.se * s.mult, r.lower * s.mult, r.upper * s.mult };
    // Display boundary: only the magnitudes shown by SAS reference listings
    // are printed (rates 100-10000 with one decimal, 1-100 with four); the
    // template's decimal rule elsewhere is unknown.
    var decimals: usize = 1;
    if (!empty) {
        for ([_]f64{ r.events, r.time, r.ref_time }) |x| if (x != @floor(x)) return gap(cx, 0, "display of nonintegral event counts or population-times is not verified", .{});
        if (r.events >= 1e8 or r.time >= 1e11 or r.ref_time >= 1e11) return gap(cx, 0, "display of totals wider than the reference columns is not verified", .{});
        if (!(r.expected >= 99.9995 and r.expected < 999.9995)) return gap(cx, 0, "expected-events display outside 100 <= x < 1000 is not verified", .{});
        var high = true;
        var low = true;
        for (rates) |x| {
            high = high and x >= 99.95 and x < 9999.95;
            low = low and x >= 1 and x < 99.99995;
        }
        if (low) decimals = 4 else if (!high) return gap(cx, 0, "rate display outside 1 <= x < 10000 (one magnitude band per row) is not verified", .{});
    }
    const mult = try std.fmt.allocPrint(a, "{d}", .{s.mult});

    var body: Out = .empty;
    try pageStart(cx, &body, first, byline);
    try body.appendSlice(a, "          Standardization Information\n\n");
    try infoLine(cx, &body, "Data Set", try displayName(a, s.study_name));
    try infoLine(cx, &body, "Reference Data Set", try displayName(a, s.reference_name.?));
    try infoLine(cx, &body, "Method", "Direct Standardization");
    try infoLine(cx, &body, "Statistic", "Rate");
    try infoLine(cx, &body, "Number of Strata", try std.fmt.allocPrint(a, "{d}", .{sel.reference_strata}));
    try infoLine(cx, &body, "Rate Multiplier", mult);
    try pageStart(cx, &body, first, byline);
    try centered(a, &body, "Directly Standardized Rate Estimates ");
    try centered(a, &body, try std.fmt.allocPrint(a, "Rate Multiplier = {s}", .{mult}));
    try body.appendSlice(a, " \n" ++
        "--------Study Population-------  -Reference Population-  -----------Standardized Rate----------\n" ++
        "Observed  Population-     Crude  Expected   Population-            Standard      95% Normal\n" ++
        "  Events         Time      Rate    Events          Time  Estimate     Error   Confidence Limits\n\n");
    const widths = [_]usize{ 8, 13, 10, 10, 14, 10, 10, 10, 10 };
    if (empty) {
        for (widths) |w| try right(a, &body, ".", w);
    } else {
        const rate_text = struct {
            fn f(al: A, x: f64, d: usize) ![]const u8 {
                return if (d == 4) std.fmt.allocPrint(al, "{d:.4}", .{x}) else std.fmt.allocPrint(al, "{d:.1}", .{x});
            }
        }.f;
        try right(a, &body, try std.fmt.allocPrint(a, "{d:.0}", .{r.events}), widths[0]);
        try right(a, &body, try std.fmt.allocPrint(a, "{d:.0}", .{r.time}), widths[1]);
        try right(a, &body, try rate_text(a, rates[0], decimals), widths[2]);
        try right(a, &body, try std.fmt.allocPrint(a, "{d:.3}", .{r.expected}), widths[3]);
        try right(a, &body, try std.fmt.allocPrint(a, "{d:.0}", .{r.ref_time}), widths[4]);
        for (rates[1..], widths[5..]) |x, w| try right(a, &body, try rate_text(a, x, decimals), w);
    }
    try body.append(a, '\n');
    try out.appendSlice(a, body.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    // BY boundaries are validated (unsorted input is a user error) before
    // the execution boundary reports what is not implemented.
    const slices = try by.checkedSlices(cx.arena, s.study, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    try boundary(cx, s);
    // BY groups split the study data set only; the whole reference data set
    // serves every group (SAS 9.4 reference run, BY variable absent from it).
    for (s.by_cols) |c| if (s.reference.?.indexOf(s.study.columns.items[c].name) != null) return gap(cx, 0, "a BY variable that is also in the REFDATA= data set is not verified", .{});
    var first = true;
    if (slices.len == 0) {
        if (s.by_cols.len > 0) return gap(cx, 0, "BY-group processing of an empty input data set is not verified", .{});
        return render(cx, out, &first, "", s, try select(cx, s, &.{}));
    }
    for (slices) |slice| {
        var byline: []const u8 = "";
        if (s.by_cols.len > 0) {
            var tmp: Out = .empty;
            try by.appendLine(cx.arena, &tmp, s.study, slice.rows[0], s.by_cols);
            byline = std.mem.trim(u8, tmp.items, " \n");
        }
        try render(cx, out, &first, byline, s, try select(cx, s, slice.rows));
    }
}

test {
    _ = @import("stdrate_tests.zig");
}
