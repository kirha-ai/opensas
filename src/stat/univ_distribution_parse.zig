//! Numerical distribution option parser. Rendering options are intentionally
//! rejected here; callers must not silently consume unknown options.
const std = @import("std");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const fitting = @import("univ_distribution_fit.zig");
const dist = @import("univ_distributions.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Curves = struct { requests: []fitting.Request, percents: []const f64, noprint: bool, midpercents: bool, invalid_percents: bool = false, noline: bool = false, fill: bool = false };

pub fn family(name: []const u8) ?dist.Family {
    inline for (std.meta.tags(dist.Family)) |tag| if (eq(name, @tagName(tag))) return tag;
    if (eq(name, "exp")) return .exponential;
    if (eq(name, "lnorm")) return .lognormal;
    if (eq(name, "norm")) return .normal;
    if (eq(name, "weib")) return .weibull;
    return null;
}

fn parameter(kind: dist.Family, key: []const u8) ?[]const u8 {
    const name = if (eq(key, "threshold")) "theta" else if (eq(key, "scale")) (if (kind == .lognormal) "zeta" else "sigma") else if (eq(key, "shape")) switch (kind) {
        .lognormal => "sigma",
        .gamma => "alpha",
        .weibull => "c",
        else => return null,
    } else if (eq(key, "b") and kind == .beta) "beta" else if (eq(key, "a") and kind == .beta) "alpha" else key;
    const allowed = switch (kind) {
        .normal, .gumbel => "mu sigma",
        .lognormal => "theta sigma zeta",
        .exponential, .rayleigh => "theta sigma",
        .gamma, .pareto, .power => "theta sigma alpha",
        .weibull => "theta sigma c",
        .beta => "theta sigma alpha beta",
        .igauss => "mu lambda",
        .sb, .su => "theta sigma delta gamma",
    };
    var names = std.mem.tokenizeScalar(u8, allowed, ' ');
    while (names.next()) |field| if (eq(field, name)) return field;
    return null;
}

pub fn numeric(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (t[i.*].tag == .minus or t[i.*].tag == .plus) {
        if (t[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (t[i.*].tag != .number) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: expected a finite numeric parameter", .{});
    const value = std.fmt.parseFloat(f64, t[i.*].text) catch return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: invalid numeric parameter", .{});
    i.* += 1;
    if (!std.math.isFinite(value)) return d.fail(error.ParseError, 0, "UNIVARIATE: nonfinite numeric parameter", .{});
    return value * sign;
}

const NumericRange = struct {
    current: ?f64,
    step: f64 = 0,
    limit: f64 = 0,
    emitted: usize = 0,

    fn next(self: *NumericRange, d: *diag.Diagnostics) diag.Error!?f64 {
        const value = self.current orelse return null;
        if (self.emitted == 100001) return d.fail(error.ParseError, 0, "UNIVARIATE: numeric list range is too large", .{});
        self.emitted += 1;
        const following = value + self.step;
        self.current = if (std.math.isFinite(following) and ((self.step > 0 and following <= self.limit) or (self.step < 0 and following >= self.limit))) following else null;
        if (self.current != null and following == value) return d.fail(error.ParseError, 0, "UNIVARIATE: range increment is below floating-point resolution", .{});
        return value;
    }
};

/// M9 adds the step to the preceding emitted value. The stopping allowance is
/// sqrt(unit roundoff) in step units in either direction.
fn numericRange(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!NumericRange {
    const first = try numeric(d, t, i);
    if (t[i.*].tag != .name or !eq(t[i.*].text, "to")) return .{ .current = first };
    i.* += 1;
    const last = try numeric(d, t, i);
    var step: f64 = 1;
    if (t[i.*].tag == .name and eq(t[i.*].text, "by")) {
        i.* += 1;
        step = try numeric(d, t, i);
    }
    const steps = (last - first) / step;
    if (step == 0 or !std.math.isFinite(steps) or steps < 0 or steps > 100000)
        return d.fail(error.ParseError, 0, "UNIVARIATE: invalid numeric list range", .{});
    if (first == last) return .{ .current = first };
    return .{ .current = first, .step = step, .limit = last + step * @sqrt(std.math.floatEps(f64) / 2) };
}

/// Common value-list syntax for plot reference lines and percentile tick marks.
pub fn numberList(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error![]const f64 {
    var values: std.ArrayList(f64) = .empty;
    while (t[i.*].tag == .number or t[i.*].tag == .plus or t[i.*].tag == .minus) {
        var range = try numericRange(d, t, i);
        while (try range.next(d)) |value| {
            if (values.items.len == 100000) return d.fail(error.ParseError, 0, "UNIVARIATE: plot reference list is too large", .{});
            try values.append(a, value);
        }
        if (t[i.*].tag == .comma) i.* += 1;
    }
    if (values.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: expected numeric plot reference values", .{});
    return values.items;
}

/// i starts at the family keyword; returns immediately after optional (...).
/// null parameter values mean EST, including explicit EST in position lists.
pub fn parse(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Curves {
    return parseOptions(a, d, t, i, false);
}

pub fn parsePlot(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Curves {
    return parseOptions(a, d, t, i, true);
}

fn parseOptions(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize, plot: bool) diag.Error!Curves {
    const weibull2 = plot and (eq(t[i.*].text, "weibull2") or eq(t[i.*].text, "w2"));
    const kind = if (weibull2) dist.Family.weibull else family(t[i.*].text) orelse return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: unknown distribution {s}", .{t[i.*].text});
    var options = FamilyOptions.init(kind);
    try options.read(a, d, t, i, if (weibull2) .weibull2 else if (plot) .plot else .histogram);
    return options.expand(a, d);
}

/// A repeated HISTOGRAM family extends each named parameter list independently.
/// Only after the full statement is read are the shorter lists extended to match.
pub const FamilyOptions = struct {
    const fields = std.meta.fields(dist.Parameters);
    pub const Mode = enum { histogram, plot, weibull2 };

    common: fitting.Request,
    lists: [fields.len]std.ArrayList(?f64) = @splat(.empty),
    percents: std.ArrayList(f64) = .empty,
    invalid_percents: bool = false,
    noprint: bool = false,
    midpercents: bool = false,
    noline: bool = false,
    fill: bool = false,

    pub fn init(kind: dist.Family) FamilyOptions {
        var options: FamilyOptions = .{ .common = .{ .family = kind } };
        if (kind == .beta or kind == .power or kind == .sb) options.common.sigma = 1;
        if (kind == .su) options.common.theta = null;
        return options;
    }

    pub fn read(self: *FamilyOptions, a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize, mode: Mode) diag.Error!void {
        const kind = self.common.family;
        const plot = mode != .histogram;
        const weibull2 = mode == .weibull2;
        i.* += 1;
        if (t[i.*].tag != .lparen) return;
        i.* += 1;
        if (!plot and t[i.*].tag == .rparen) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: expected a distribution option", .{});
        while (t[i.*].tag != .rparen) {
            if (t[i.*].tag != .name) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: expected distribution option or closing parenthesis", .{});
            const key = t[i.*].text;
            i.* += 1;
            if (!plot and eq(key, "fill")) {
                self.fill = true;
                continue;
            }
            if (plot and eq(key, "noline")) {
                self.noline = true;
                continue;
            }
            if (plot and (eq(key, "noprint") or eq(key, "midpercents") or eq(key, "percents") or eq(key, "percent"))) return d.fail(error.ParseError, 0, "UNIVARIATE: {s} is a HISTOGRAM distribution option", .{key});
            if (eq(key, "noprint")) {
                self.noprint = true;
                continue;
            }
            if (eq(key, "midpercents")) {
                self.midpercents = true;
                continue;
            }
            if (eq(key, "optprint") and kind == .su) {
                self.common.optprint = true;
                continue;
            }
            if (eq(key, "itprint") and kind == .weibull) {
                self.common.itprint = true;
                continue;
            }
            if (t[i.*].tag != .eq) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: distribution option requires =", .{});
            i.* += 1;
            if (eq(key, "w")) {
                // Distribution-line widths apply to the traditional graphics renderer.
                const widths = try numberList(a, d, t, i);
                for (widths) |v| if (v <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: curve widths must be positive", .{});
                continue;
            }
            if ((kind == .sb or kind == .su) and eq(key, "fitmethod")) {
                const method = t[i.*].text;
                if (eq(method, "percentile")) self.common.fitmethod = .percentiles else if (eq(method, "moments")) self.common.fitmethod = .moments else if (eq(method, "mle")) self.common.fitmethod = .mle else return d.fail(error.ParseError, 0, "UNIVARIATE: invalid FITMETHOD", .{});
                i.* += 1;
                continue;
            }
            if ((kind == .sb or kind == .su) and (eq(key, "fitinterval") or eq(key, "fittolerance"))) {
                const value = try numeric(d, t, i);
                if (eq(key, "fitinterval")) self.common.fitinterval = value else self.common.fittolerance = value;
                continue;
            }
            if (kind == .su and (eq(key, "optboundrange") or eq(key, "opttolerance") or eq(key, "optseed") or eq(key, "optmaxiter") or eq(key, "optmaxstarts"))) {
                const value = try numeric(d, t, i);
                if (value <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: optimizer control must be positive", .{});
                if (eq(key, "optboundrange")) self.common.optboundrange = value else if (eq(key, "opttolerance")) self.common.opttolerance = value else if (eq(key, "optseed")) {
                    if (value != @floor(value)) return d.fail(error.ParseError, 0, "UNIVARIATE: OPTSEED must be an integer", .{});
                    self.common.optseed = value;
                } else {
                    if (value != @floor(value) or value >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid optimizer iteration count", .{});
                    if (eq(key, "optmaxiter")) self.common.optmaxiter = @intFromFloat(value) else self.common.optmaxstarts = @intFromFloat(value);
                }
                continue;
            }
            if ((kind == .gumbel or kind == .igauss or kind == .pareto or kind == .rayleigh) and (eq(key, "edfnsamples") or eq(key, "edfseed"))) {
                const value = try numeric(d, t, i);
                if (value < 0 or value != @floor(value)) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF simulation control must be a nonnegative integer", .{});
                if (eq(key, "edfseed")) self.common.edfseed = value else {
                    if (value < 1 or value >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return d.fail(error.ParseError, 0, "UNIVARIATE: EDFNSAMPLES must be a positive count", .{});
                    self.common.edfnsamples = @intFromFloat(value);
                }
                continue;
            }
            if (eq(key, "maxiter") and (kind == .gamma or kind == .weibull)) {
                const value = try numeric(d, t, i);
                if (value < 5 or value > 100) return d.fail(error.ParseError, 0, "The parameter value {s} is not within the required range of 5 and 100.", .{try @import("../format.zig").bestNum(a, value)});
                self.common.maxiter = @intFromFloat(value);
                continue;
            }
            if (kind == .gamma and (eq(key, "alphadelta") or eq(key, "alphainitial"))) {
                const value = try numeric(d, t, i);
                if (value <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: gamma iteration controls must be positive", .{});
                if (eq(key, "alphadelta")) self.common.alphadelta = value else self.common.alphainitial = value;
                continue;
            }
            if (eq(key, "percents") or eq(key, "percent")) {
                const values = try numberList(a, d, t, i);
                for (values) |value| if (value <= 0 or value >= 100) {
                    self.invalid_percents = true;
                    break;
                };
                try self.percents.appendSlice(a, values);
                continue;
            }
            const slope = plot and eq(key, "slope") and (kind == .lognormal or weibull2);
            const field_name = if (slope) (if (kind == .lognormal) "zeta" else "c") else parameter(kind, key) orelse return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported {s} option {s}", .{ @tagName(kind), key });
            inline for (fields, 0..) |field, fi| {
                if (eq(field.name, field_name)) {
                    if (plot and self.lists[fi].items.len != 0) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated distribution parameter {s}", .{key});
                    while (t[i.*].tag == .number or t[i.*].tag == .plus or t[i.*].tag == .minus or t[i.*].tag == .comma or (t[i.*].tag == .name and eq(t[i.*].text, "est"))) {
                        if (t[i.*].tag == .comma) {
                            i.* += 1;
                            continue;
                        }
                        if (t[i.*].tag == .name) {
                            try self.lists[fi].append(a, null);
                            i.* += 1;
                        } else {
                            var range = try numericRange(d, t, i);
                            while (try range.next(d)) |raw| {
                                var value = raw;
                                if (slope) {
                                    if (value <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: SLOPE must be positive", .{});
                                    value = if (kind == .lognormal) @log(value) else 1 / value;
                                }
                                try self.lists[fi].append(a, value);
                            }
                        }
                    }
                    if (plot and self.lists[fi].items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty distribution parameter list", .{});
                }
            }
        }
        i.* += 1;
    }

    pub fn expand(self: *const FamilyOptions, a: std.mem.Allocator, d: *diag.Diagnostics) diag.Error!Curves {
        const kind = self.common.family;
        var count: usize = 1;
        for (self.lists) |list| count = @max(count, list.items.len);
        const requests = try a.alloc(fitting.Request, count);
        for (requests, 0..) |*r, j| {
            r.* = self.common;
            inline for (fields, 0..) |field, fi| {
                const values = self.lists[fi].items;
                if (values.len > 0) {
                    @field(r, field.name) = values[@min(j, values.len - 1)];
                    r.specified_fields.set(fi);
                }
            }
            var fixed: dist.Parameters = .{ .mu = if (kind == .igauss) 1 else 0 };
            inline for (fields) |field| if (@field(r, field.name)) |value| {
                @field(fixed, field.name) = value;
            };
            try (dist.Distribution{ .family = kind, .p = fixed }).validate(d);
        }
        return .{ .requests = requests, .fill = self.fill, .noprint = self.noprint, .midpercents = self.midpercents, .noline = self.noline, .invalid_percents = self.invalid_percents, .percents = if (self.invalid_percents or self.percents.items.len == 0) &.{ 1, 5, 10, 25, 50, 75, 90, 95, 99 } else self.percents.items };
    }
};

test "UNIVARIATE distribution parameter lists aliases and captured rejection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const lexer = @import("../lexer.zig");
    const t = try lexer.tokenize(a, "normal(mu=5 est sigma=est 2 noprint percents=5 50 95);", &d);
    var i: usize = 0;
    const curves = try parse(a, &d, t, &i);
    try std.testing.expectEqual(@as(usize, 2), curves.requests.len);
    try std.testing.expectEqual(@as(?f64, 5), curves.requests[0].mu);
    try std.testing.expectEqual(@as(?f64, null), curves.requests[1].mu);
    try std.testing.expectEqual(@as(?f64, 2), curves.requests[1].sigma);
    try std.testing.expect(curves.noprint and t[i].tag == .semicolon);
    const bad = try lexer.tokenize(a, "normal(theta=3);", &d);
    i = 0;
    try std.testing.expectError(error.ParseError, parse(a, &d, bad, &i));
    const aliases = try lexer.tokenize(a, "lognormal(threshold=-1 scale=2 shape=0.5);", &d);
    i = 0;
    const ln = (try parse(a, &d, aliases, &i)).requests[0];
    try std.testing.expectEqual(@as(?f64, -1), ln.theta);
    try std.testing.expectEqual(@as(?f64, 2), ln.zeta);
    try std.testing.expectEqual(@as(?f64, 0.5), ln.sigma);
}

test "UNIVARIATE documented distribution aliases preserve canonical requests" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const lex = @import("../lexer.zig");
    for ([_][]const u8{ "beta(a=2 b=3 percent=10 50 90)", "lnorm(shape=.5)", "norm(mu=2)", "weib(c=2)" }, [_][]const u8{ "beta(alpha=2 beta=3 percents=10 50 90)", "lognormal(sigma=.5)", "normal(mu=2)", "weibull(c=2)" }) |alias, canonical| {
        var d = diag.Diagnostics.init(a);
        var i: usize = 0;
        const actual = try parse(a, &d, try lex.tokenize(a, alias, &d), &i);
        i = 0;
        const expected = try parse(a, &d, try lex.tokenize(a, canonical, &d), &i);
        try std.testing.expectEqualDeep(expected, actual);
    }
    for ([_][]const u8{ "qqplot x / w2(theta=1 sigma=2 c=3);", "probplot x / w2(theta=1 sigma=2 slope=.5);" }) |source| {
        var d = diag.Diagnostics.init(a);
        var i: usize = 0;
        const plot = try @import("univ_distribution_plots.zig").parse(a, &d, try lex.tokenize(a, source, &d), &i);
        try std.testing.expect(plot.weibull2);
        try std.testing.expectEqual(dist.Family.weibull, plot.curves.requests[0].family);
    }
}

test "UNIVARIATE parameter and percentile ranges publish the SAS fitted series" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = @import("../exec.zig").Library.init(a);
    var ds = @import("../dataset.zig").Dataset.init(a, "d");
    _ = try ds.addColumn("x", .num);
    for ([_]f64{ 1, 2, 3, 4, 6, 8, 10, 15 }) |x| try ds.appendRow(&.{.{ .num = x }});
    try lib.put("d", &ds);
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    var capture: @import("../ods.zig").Capture = .{};
    try capture.parse(a, &d, try lex.tokenize(a, "ods output ParameterEstimates=p FitQuantiles=q;", &d));
    var out: std.ArrayList(u8) = .empty;
    const t = try lex.tokenize(a, "proc univariate data=d; var x; histogram x / normal(mu=0 to 2 by 1 sigma=2 percents=10 to 90 by 40) noplot; run;", &d);
    try @import("../proc.zig").runUnivariate(.{ .arena = a, .lib = &lib, .diags = &d, .capture = &capture }, &out, t);
    try capture.finish(&lib, &d);
    try std.testing.expect(!d.hasErrors());
    const p = lib.find("p").?;
    const q = lib.find("q").?;
    try std.testing.expectEqual(@as(usize, 6), p.rows.items.len);
    try std.testing.expectEqual(@as(usize, 9), q.rows.items.len);
    for (0..3) |curve| {
        const mu: f64 = @floatFromInt(curve);
        try std.testing.expectEqual(mu, p.rows.items[2 * curve][5].num);
        try std.testing.expectEqual(@as(f64, 2), p.rows.items[2 * curve + 1][5].num);
        for ([_]f64{ 10, 50, 90 }, [_]f64{ 1, 5, 15 }, [_]f64{ -2.56310, 0, 2.56310 }, 0..) |pct, obs, offset, j| {
            const row = q.rows.items[curve * 3 + j];
            try std.testing.expectEqual(pct, row[3].num);
            try std.testing.expectEqual(obs, row[4].num);
            try std.testing.expectApproxEqAbs(mu + offset, row[5].num, 5e-6);
        }
    }
    var i: usize = 0;
    const alternate = try parse(a, &d, try lex.tokenize(a, "normal(mu=est 1 to .4 by -.3 sigma=2)", &d), &i);
    try std.testing.expectEqual(@as(usize, 4), alternate.requests.len);
    try std.testing.expectEqual(@as(?f64, null), alternate.requests[0].mu);
    try std.testing.expectApproxEqAbs(@as(f64, 0.4), alternate.requests[3].mu.?, 1e-15);
    for ([_][]const u8{ "normal(mu=1 to 2 by 0)", "normal(mu=0 to 1 by -.1)", "normal(mu=0 to 1 by 1e-300)" }) |bad| {
        var invalid = diag.Diagnostics.init(a);
        i = 0;
        try std.testing.expectError(error.ParseError, parse(a, &invalid, try lex.tokenize(a, bad, &invalid), &i));
        try std.testing.expect(invalid.hasErrors());
    }
}

test "UNIVARIATE TO BY lists accumulate displayable increments before testing their endpoints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var d = diag.Diagnostics.init(a);
    const lex = @import("../lexer.zig");
    const cases = [_]struct { option: []const u8, count: usize, last: f64 }{
        .{ .option = "normal(mu=.1 to 1 by .1)", .count = 10, .last = 0.9999999999999999 },
        .{ .option = "normal(mu=50 to 50.0000000000001 by 1e-14)", .count = 15, .last = 50.0000000000001 },
        .{ .option = "normal(mu=4 to 4.199999999 by .1)", .count = 3, .last = 4.199999999999999 },
        .{ .option = "normal(mu=4 to 4.199999998 by .1)", .count = 2, .last = 4.1 },
    };
    for (cases) |case| {
        var i: usize = 0;
        const curves = try parse(a, &d, try lex.tokenize(a, case.option, &d), &i);
        try std.testing.expectEqual(case.count, curves.requests.len);
        try std.testing.expectEqual(case.last, curves.requests[case.count - 1].mu.?);
    }
}
