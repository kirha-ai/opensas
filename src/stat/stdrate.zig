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
    if (at(t, i.*, .lparen)) return gap(cx, t[i.*].line, "data set options on {s}= are not implemented", .{option});
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
    // "names the required SAS data set" (p.9495): whether an omitted DATA=
    // falls back to the most recent data set is not settled by the guide.
    s.study_name = data orelse return gap(cx, lineOf(t, 0), "the input data set when DATA= is omitted is not verified", .{});
    const raw = cx.lib.find(s.study_name) orelse return user(cx, 0, "input data set {s} not found", .{s.study_name});
    // Only the global OBS=/FIRSTOBS= window applies: data set options are
    // rejected above and WHERE is recorded as a boundary below.
    s.study = try proc.procInput(cx.arena, raw, t[0..2], cx.diags);
    if (s.reference_name) |name| {
        const ref = cx.lib.find(name) orelse return user(cx, 0, "reference data set {s} not found", .{name});
        s.reference = try proc.procInput(cx.arena, ref, t[0..2], cx.diags);
    }
    var bys: by.Statements = .{};
    var population_seen = false;
    var strata_names: std.ArrayList(lex.Token) = .empty;
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
            if (s.reference_statement) return gap(cx, t[i].line, "duplicate REFERENCE statement policy is not verified", .{});
            s.reference_statement = true;
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
            if (s.strata_statement) return gap(cx, t[i].line, "duplicate STRATA statement policy is not verified", .{});
            s.strata_statement = true;
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
            return gap(cx, t[i].line, "FORMAT statement (formatted STRATA levels) is not implemented", .{});
        } else if (at(t, i, .name) and !kw(t, i, "x") and parser.isMidStepSkippable(t[i].text)) {
            try parser.noteUnexecuted(cx.diags, t[i..end]);
        } else return invalid(cx, t, i);
        i = end + 1;
    }
    if (!population_seen) return user(cx, 0, "the POPULATION statement is required", .{});
    if (s.method != .mh and !s.reference_statement) return user(cx, 0, "the REFERENCE statement is required with METHOD=DIRECT and METHOD=INDIRECT", .{});
    if (s.method == .mh and s.group == null) return user(cx, 0, "the GROUP= option in the POPULATION statement is required with METHOD=MH", .{});
    // STRATA variables are "in all input data sets" (p.9500).
    const cols = try cx.arena.alloc(usize, strata_names.items.len);
    const ref_cols = try cx.arena.alloc(usize, if (s.reference != null) cols.len else 0);
    for (strata_names.items, 0..) |token, k| {
        cols[k] = s.study.indexOf(token.text) orelse return cx.diags.fail(error.ParseError, token.line, "Variable {s} not found.", .{token.text});
        if (std.mem.indexOfScalar(usize, cols[0..k], cols[k]) != null) return gap(cx, token.line, "repeated STRATA variable policy is not verified", .{});
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
    if (s.mult != 100000) return gap(cx, 0, "listing for a rate multiplier other than 100000 is not verified", .{});
    if (s.alpha != 0.05) return gap(cx, 0, "ALPHA= other than 0.05 is not implemented", .{});
    if (s.cl != .normal) return gap(cx, 0, "CL= other than NORMAL is not implemented", .{});
    if (s.effect != null) return gap(cx, 0, "the EFFECT option is not implemented", .{});
    if (s.plots and !s.plots_none) return gap(cx, 0, "PLOTS= requests are not implemented", .{});
    // The CLI always carries a graphics session; only ODS GRAPHICS ON makes
    // SAS draw the default stratum-specific rate plot.
    if (!s.plots_none) if (cx.graphics) |g| if (g.enabled == true) return gap(cx, 0, "stratum-specific rate plots under ODS GRAPHICS are not implemented", .{});
    if (s.where) return gap(cx, 0, "WHERE with study and reference data sets is not verified", .{});
    if (s.by_cols.len > 0) return gap(cx, 0, "BY-group analysis and listing are not verified", .{});
    if (s.group != null) return gap(cx, 0, "POPULATION GROUP= (several study populations) is not implemented", .{});
    if (s.popevent != null) return gap(cx, 0, "POPULATION POPEVENT= is not implemented", .{});
    if (s.population.rate != null or s.population.risk != null) return gap(cx, 0, "POPULATION RATE= and RISK= input is not implemented", .{});
    if (s.population.event == null or s.population.total == null) return gap(cx, 0, "POPULATION without both EVENT= and TOTAL= is not implemented", .{});
    if (s.reference == null) return cx.diags.fail(error.ParseError, 0, "PROC STDRATE: the REFDATA= data set is required with METHOD=DIRECT", .{});
    if (s.ref.event != null or s.ref.rate != null or s.ref.risk != null) return gap(cx, 0, "REFERENCE EVENT=, RATE= and RISK= are not implemented", .{});
    if (s.refevent != null or s.refrate != null or s.refrisk != null or s.reftotal != null) return gap(cx, 0, "REFERENCE REFEVENT=, REFRATE=, REFRISK= and REFTOTAL= are not implemented", .{});
    if (s.ref.total == null) return gap(cx, 0, "REFERENCE without TOTAL= is not implemented", .{});
    if (s.strata_effect or s.stats != null or s.smr != null) return gap(cx, 0, "STRATA options EFFECT, STATS and SMR are not implemented", .{});
    if (s.strata.len == 0) return gap(cx, 0, "the listing without STRATA variables is not verified", .{});
    for (s.strata, s.ref_strata) |c, r| {
        if (s.study.columns.items[c].format != null or s.reference.?.columns.items[r].format != null) return gap(cx, 0, "formatted STRATA levels are not implemented", .{});
    }
}

pub const Stratum = struct {
    /// Representative row of the data set the stratum was first seen in.
    key: []const Value,
    events: f64 = 0,
    time: f64 = 0,
    ref_time: f64 = 0,
    in_study: bool = false,
    in_reference: bool = false,
};
pub const Selected = struct {
    strata: []const Stratum,
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
/// unless MISSING, which makes missing a level of its own. Levels are matched
/// between the study and reference data sets by unformatted value and
/// returned in ORDER=INTERNAL order unless ORDER=DATA (study order, then
/// reference-only levels). Data whose treatment the guide leaves open
/// (missing or out-of-range EVENT/TOTAL values, several observations in one
/// stratum, a stratum absent from one data set) is a gap.
pub fn select(cx: proc.ProcCtx, s: Spec, study_rows: []const []const Value) diag.Error!Selected {
    const a = cx.arena;
    const ref = s.reference.?;
    const event = s.population.event.?;
    const total = s.population.total.?;
    const ref_total = s.ref.total.?;
    var list: std.ArrayList(Stratum) = .empty;
    var result: Selected = .{ .strata = &.{}, .study_read = study_rows.len, .study_used = 0, .reference_read = ref.rowCount(), .reference_used = 0 };
    for ([_]bool{ false, true }) |is_ref| {
        const cols = if (is_ref) s.ref_strata else s.strata;
        const count = if (is_ref) ref.rowCount() else study_rows.len;
        rows: for (0..count) |r| {
            const row = if (is_ref) ref.row(r) else study_rows[r];
            const key = try a.alloc(Value, cols.len);
            for (cols, key) |c, *k| {
                if (missingValue(row[c]) and !s.missing) continue :rows;
                k.* = row[c];
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
            if (if (is_ref) st.in_reference else st.in_study) return gap(cx, 0, "several observations in one stratum of a data set are not verified", .{});
            if (is_ref) {
                const x = row[ref_total].num;
                if (!(x > 0)) return gap(cx, 0, "missing or nonpositive REFERENCE TOTAL= values are not verified", .{});
                st.ref_time = x;
                st.in_reference = true;
                result.reference_used += 1;
            } else {
                const d = row[event].num;
                const time = row[total].num;
                if (!(d >= 0)) return gap(cx, 0, "missing or negative POPULATION EVENT= values are not verified", .{});
                if (!(time > 0)) return gap(cx, 0, "missing or nonpositive POPULATION TOTAL= values are not verified", .{});
                st.events = d;
                st.time = time;
                st.in_study = true;
                result.study_used += 1;
            }
        }
    }
    for (list.items) |st| if (!st.in_study or !st.in_reference) return gap(cx, 0, "a stratum that is absent from the study or the reference data set is not verified", .{});
    if (list.items.len == 0) return gap(cx, 0, "the result for an input without usable observations is not verified", .{});
    if (s.order == .formatted) return gap(cx, 0, "STRATA ORDER=FORMATTED is not implemented", .{});
    if (s.order == .internal) std.mem.sort(Stratum, list.items, KeyOrder{ .n = s.strata.len }, KeyOrder.less);
    result.strata = list.items;
    return result;
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

fn render(cx: proc.ProcCtx, out: *Out, s: Spec, sel: Selected) diag.Error!void {
    const a = cx.arena;
    const r = direct(sel.strata);
    // Display boundary: only the magnitudes shown by the SAS reference
    // listing are printed; the template's decimal rule elsewhere is unknown.
    for ([_]f64{ r.events, r.time, r.ref_time }) |x| if (x != @floor(x)) return gap(cx, 0, "display of nonintegral event counts or population-times is not verified", .{});
    if (r.events >= 1e8 or r.time >= 1e11 or r.ref_time >= 1e11) return gap(cx, 0, "display of totals wider than the reference columns is not verified", .{});
    if (!(r.expected >= 99.9995 and r.expected < 999.9995)) return gap(cx, 0, "expected-events display outside 100 <= x < 1000 is not verified", .{});
    const rates = [_]f64{ r.crude * s.mult, r.estimate * s.mult, r.se * s.mult, r.lower * s.mult, r.upper * s.mult };
    for (rates) |x| if (!(x >= 99.95 and x < 9999.95)) return gap(cx, 0, "rate display outside 100 <= x < 10000 (per 100000) is not verified", .{});

    var body: Out = .empty;
    try body.appendSlice(a, "\nThe STDRATE Procedure\n\n          Standardization Information\n\n");
    try infoLine(cx, &body, "Data Set", try displayName(a, s.study_name));
    try infoLine(cx, &body, "Reference Data Set", try displayName(a, s.reference_name.?));
    try infoLine(cx, &body, "Method", "Direct Standardization");
    try infoLine(cx, &body, "Statistic", "Rate");
    try infoLine(cx, &body, "Number of Strata", try std.fmt.allocPrint(a, "{d}", .{sel.strata.len}));
    try infoLine(cx, &body, "Rate Multiplier", "100000");
    try body.appendSlice(a, "\nThe STDRATE Procedure\n\n" ++
        "                             Directly Standardized Rate Estimates \n" ++
        "                                    Rate Multiplier = 100000\n \n" ++
        "--------Study Population-------  -Reference Population-  -----------Standardized Rate----------\n" ++
        "Observed  Population-     Crude  Expected   Population-            Standard      95% Normal\n" ++
        "  Events         Time      Rate    Events          Time  Estimate     Error   Confidence Limits\n\n");
    try right(a, &body, try std.fmt.allocPrint(a, "{d:.0}", .{r.events}), 8);
    try right(a, &body, try std.fmt.allocPrint(a, "{d:.0}", .{r.time}), 13);
    try right(a, &body, try std.fmt.allocPrint(a, "{d:.1}", .{rates[0]}), 10);
    try right(a, &body, try std.fmt.allocPrint(a, "{d:.3}", .{r.expected}), 10);
    try right(a, &body, try std.fmt.allocPrint(a, "{d:.0}", .{r.ref_time}), 14);
    for (rates[1..]) |x| try right(a, &body, try std.fmt.allocPrint(a, "{d:.1}", .{x}), 10);
    try body.append(a, '\n');
    try out.appendSlice(a, body.items);
}

pub fn run(cx: proc.ProcCtx, out: *Out, t: []const lex.Token) diag.Error!void {
    const s = try parse(cx, t);
    // BY boundaries are validated (unsorted input is a user error) before
    // the execution boundary reports what is not implemented.
    const slices = try by.checkedSlices(cx.arena, s.study, s.by_cols, s.by_desc, s.notsorted, cx.diags);
    try boundary(cx, s);
    if (slices.len == 0) return gap(cx, 0, "the result for an empty input data set is not verified", .{});
    for (slices) |slice| try render(cx, out, s, try select(cx, s, slice.rows));
}

test {
    _ = @import("stdrate_tests.zig");
}
