//! Numerical distribution option parser. Rendering options are intentionally
//! rejected here; callers must not silently consume unknown options.
const std = @import("std");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const fitting = @import("univ_distribution_fit.zig");
const dist = @import("univ_distributions.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Curves = struct { requests: []fitting.Request, percents: []const f64, noprint: bool, midpercents: bool, noline: bool = false };

pub fn family(name: []const u8) ?dist.Family {
    inline for (std.meta.tags(dist.Family)) |tag| if (eq(name, @tagName(tag))) return tag;
    if (eq(name, "exp")) return .exponential;
    return null;
}

fn parameter(kind: dist.Family, key: []const u8) ?[]const u8 {
    const name = if (eq(key, "threshold")) "theta" else if (eq(key, "scale")) (if (kind == .lognormal) "zeta" else "sigma") else if (eq(key, "shape")) switch (kind) {
        .lognormal => "sigma",
        .gamma => "alpha",
        .weibull => "c",
        else => return null,
    } else if (eq(key, "b") and kind == .beta) "beta" else key;
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

/// i starts at the family keyword; returns immediately after optional (...).
/// null parameter values mean EST, including explicit EST in position lists.
pub fn parse(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Curves {
    return parseOptions(a, d, t, i, false);
}

pub fn parsePlot(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!Curves {
    return parseOptions(a, d, t, i, true);
}

fn parseOptions(a: std.mem.Allocator, d: *diag.Diagnostics, t: []const Token, i: *usize, plot: bool) diag.Error!Curves {
    const weibull2 = plot and eq(t[i.*].text, "weibull2");
    const kind = if (weibull2) dist.Family.weibull else family(t[i.*].text) orelse return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: unknown distribution {s}", .{t[i.*].text});
    i.* += 1;
    const fields = std.meta.fields(dist.Parameters);
    var lists: [fields.len]std.ArrayList(?f64) = @splat(.empty);
    var common: fitting.Request = .{ .family = kind };
    if (kind == .beta or kind == .power or kind == .sb) common.sigma = 1;
    if (kind == .su) common.theta = null;
    var count: usize = 1;
    var percents: std.ArrayList(f64) = .empty;
    var noprint = false;
    var midpercents = false;
    var noline = false;
    if (t[i.*].tag == .lparen) {
        i.* += 1;
        while (t[i.*].tag != .rparen) {
            if (t[i.*].tag != .name) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: expected distribution option or closing parenthesis", .{});
            const key = t[i.*].text;
            i.* += 1;
            if (plot and eq(key, "noline")) {
                noline = true;
                continue;
            }
            if (plot and (eq(key, "noprint") or eq(key, "midpercents") or eq(key, "percents"))) return d.fail(error.ParseError, 0, "UNIVARIATE: {s} is a HISTOGRAM distribution option", .{key});
            if (eq(key, "noprint")) {
                noprint = true;
                continue;
            }
            if (eq(key, "midpercents")) {
                midpercents = true;
                continue;
            }
            if (eq(key, "optprint") and kind == .su) {
                common.optprint = true;
                continue;
            }
            if (eq(key, "itprint") and kind == .weibull) {
                common.itprint = true;
                continue;
            }
            if (t[i.*].tag != .eq) return d.fail(error.ParseError, t[i.*].line, "UNIVARIATE: distribution option requires =", .{});
            i.* += 1;
            if ((kind == .sb or kind == .su) and eq(key, "fitmethod")) {
                const method = t[i.*].text;
                if (eq(method, "percentile")) common.fitmethod = .percentiles else if (eq(method, "moments")) common.fitmethod = .moments else if (eq(method, "mle")) common.fitmethod = .mle else return d.fail(error.ParseError, 0, "UNIVARIATE: invalid FITMETHOD", .{});
                i.* += 1;
                continue;
            }
            if ((kind == .sb or kind == .su) and (eq(key, "fitinterval") or eq(key, "fittolerance"))) {
                const value = try numeric(d, t, i);
                if (eq(key, "fitinterval")) common.fitinterval = value else common.fittolerance = value;
                continue;
            }
            if (kind == .su and (eq(key, "optboundrange") or eq(key, "opttolerance") or eq(key, "optseed") or eq(key, "optmaxiter") or eq(key, "optmaxstarts"))) {
                const value = try numeric(d, t, i);
                if (value <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: optimizer control must be positive", .{});
                if (eq(key, "optboundrange")) common.optboundrange = value else if (eq(key, "opttolerance")) common.opttolerance = value else if (eq(key, "optseed")) {
                    if (value != @floor(value)) return d.fail(error.ParseError, 0, "UNIVARIATE: OPTSEED must be an integer", .{});
                    common.optseed = value;
                } else {
                    if (value != @floor(value) or value >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid optimizer iteration count", .{});
                    if (eq(key, "optmaxiter")) common.optmaxiter = @intFromFloat(value) else common.optmaxstarts = @intFromFloat(value);
                }
                continue;
            }
            if ((kind == .gumbel or kind == .igauss or kind == .pareto or kind == .rayleigh) and (eq(key, "edfnsamples") or eq(key, "edfseed"))) {
                const value = try numeric(d, t, i);
                if (value < 0 or value != @floor(value)) return d.fail(error.ParseError, 0, "UNIVARIATE: EDF simulation control must be a nonnegative integer", .{});
                if (eq(key, "edfseed")) common.edfseed = value else {
                    if (value < 1 or value >= @as(f64, @floatFromInt(std.math.maxInt(usize)))) return d.fail(error.ParseError, 0, "UNIVARIATE: EDFNSAMPLES must be a positive count", .{});
                    common.edfnsamples = @intFromFloat(value);
                }
                continue;
            }
            if (eq(key, "maxiter") and (kind == .gamma or kind == .weibull)) {
                const value = try numeric(d, t, i);
                if (value < 1 or value > 1000000 or value != @floor(value)) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid MAXITER", .{});
                common.maxiter = @intFromFloat(value);
                continue;
            }
            if (kind == .gamma and (eq(key, "alphadelta") or eq(key, "alphainitial"))) {
                const value = try numeric(d, t, i);
                if (value <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: gamma iteration controls must be positive", .{});
                if (eq(key, "alphadelta")) common.alphadelta = value else common.alphainitial = value;
                continue;
            }
            if (eq(key, "percents")) {
                while (t[i.*].tag == .number or t[i.*].tag == .comma) {
                    if (t[i.*].tag == .comma) {
                        i.* += 1;
                        continue;
                    }
                    const value = try numeric(d, t, i);
                    if (value <= 0 or value >= 100) return d.fail(error.ParseError, 0, "UNIVARIATE: PERCENTS must be between 0 and 100", .{});
                    try percents.append(a, value);
                }
                if (percents.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty PERCENTS list", .{});
                continue;
            }
            const slope = plot and eq(key, "slope") and (kind == .lognormal or weibull2);
            const field_name = if (slope) (if (kind == .lognormal) "zeta" else "c") else parameter(kind, key) orelse return d.fail(error.ParseError, 0, "UNIVARIATE: unsupported {s} option {s}", .{ @tagName(kind), key });
            inline for (fields, 0..) |field, fi| {
                if (eq(field.name, field_name)) {
                    if (lists[fi].items.len != 0) return d.fail(error.ParseError, 0, "UNIVARIATE: repeated distribution parameter {s}", .{key});
                    while (t[i.*].tag == .number or t[i.*].tag == .plus or t[i.*].tag == .minus or t[i.*].tag == .comma or (t[i.*].tag == .name and eq(t[i.*].text, "est"))) {
                        if (t[i.*].tag == .comma) {
                            i.* += 1;
                            continue;
                        }
                        if (t[i.*].tag == .name) {
                            try lists[fi].append(a, null);
                            i.* += 1;
                        } else {
                            var value = try numeric(d, t, i);
                            if (slope) {
                                if (value <= 0) return d.fail(error.ParseError, 0, "UNIVARIATE: SLOPE must be positive", .{});
                                value = if (kind == .lognormal) @log(value) else 1 / value;
                            }
                            try lists[fi].append(a, value);
                        }
                    }
                    if (lists[fi].items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty distribution parameter list", .{});
                    count = @max(count, lists[fi].items.len);
                }
            }
        }
        i.* += 1;
    }
    const requests = try a.alloc(fitting.Request, count);
    for (requests, 0..) |*r, j| {
        r.* = common;
        inline for (fields, 0..) |field, fi| {
            const values = lists[fi].items;
            if (values.len > 0) {
                @field(r, field.name) = values[@min(j, values.len - 1)];
                r.specified_fields.set(fi);
            }
        }
    }
    return .{ .requests = requests, .noprint = noprint, .midpercents = midpercents, .noline = noline, .percents = if (percents.items.len == 0) &.{ 1, 5, 10, 25, 50, 75, 90, 95, 99 } else percents.items };
}

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
