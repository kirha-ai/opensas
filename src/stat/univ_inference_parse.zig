//! UNIVARIATE inference syntax, separate from numerical kernels (D-029).
const std = @import("std");
const diag = @import("../diag.zig");
const Token = @import("../lexer.zig").Token;
const k = @import("univ_inference.zig");
const eq = std.ascii.eqlIgnoreCase;
const A = std.mem.Allocator;
pub const Options = struct {
    alpha: f64 = 0.05,
    normal: bool = false,
    robustscale: bool = false,
    forceqn: bool = false,
    forcesn: bool = false,
    loccount: bool = false,
    basic: ?k.CI = null,
    df: ?k.CI = null,
    normal_ci: ?k.CI = null,
    trim: []f64 = &.{},
    winsor: []f64 = &.{},
    trim_ci: k.CI = .{},
    winsor_ci: k.CI = .{},
    location: []f64 = &.{},
    pub fn mu(self: Options, index: usize, fallback: f64) f64 {
        return if (self.location.len == 0) fallback else self.location[if (self.location.len == 1) 0 else index];
    }
    pub fn parse(self: *Options, a: A, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!bool {
        const key = t[i.*].text;
        inline for (.{ "normal", "robustscale", "forceqn", "forcesn", "loccount" }) |name| if (eq(key, name) or (eq(name, "normal") and eq(key, "normaltest"))) {
            @field(self, name) = true;
            i.* += 1;
            return true;
        };
        if (eq(key, "alpha")) {
            i.* += 1;
            try equals(d, t, i);
            self.alpha = try alphaValue(d, t, i);
            return true;
        }
        if (eq(key, "mu0") or eq(key, "location")) {
            i.* += 1;
            try equals(d, t, i);
            self.location = try numbers(a, d, t, i);
            return true;
        }
        if (eq(key, "cibasic") or eq(key, "cipctldf") or eq(key, "ciquantdf") or eq(key, "cipctlnormal") or eq(key, "ciquantnormal")) {
            const df = eq(key, "cipctldf") or eq(key, "ciquantdf");
            i.* += 1;
            const ci = try parseCI(d, t, i, df);
            if (eq(key, "cibasic")) self.basic = ci else if (df) self.df = ci else self.normal_ci = ci;
            return true;
        }
        const trim = eq(key, "trimmed") or eq(key, "trim");
        if (trim or eq(key, "winsorized") or eq(key, "winsor")) {
            i.* += 1;
            try equals(d, t, i);
            const values = try numbers(a, d, t, i);
            var retained: std.ArrayList(f64) = .empty;
            for (values) |v| {
                if (v <= 0 or (v >= 0.5 and v < 1)) {
                    try d.warn(0, "UNIVARIATE: invalid trimming value {d} ignored", .{v});
                    continue;
                }
                try retained.append(a, v);
            }
            const ci = try parseCI(d, t, i, false);
            if (trim) {
                self.trim = try retained.toOwnedSlice(a);
                self.trim_ci = ci;
            } else {
                self.winsor = try retained.toOwnedSlice(a);
                self.winsor_ci = ci;
            }
            return true;
        }
        return false;
    }
    pub fn validate(self: *Options, d: *diag.Diagnostics, weighted: bool, df: bool, vars: usize) diag.Error!void {
        if (self.location.len > 1 and self.location.len != vars) return d.fail(error.ParseError, 0, "UNIVARIATE: MU0 list must match VAR list", .{});
        if (self.basic != null and !df) {
            try d.warn(0, "UNIVARIATE: CIBASIC requires VARDEF=DF; confidence limits not computed", .{});
            self.basic = null;
        }
        if (!df and (self.trim.len > 0 or self.winsor.len > 0)) try d.warn(0, "UNIVARIATE: trimmed/Winsorized confidence limits require VARDEF=DF", .{});
        if (weighted) {
            if (self.normal or self.robustscale or self.loccount or self.df != null or self.normal_ci != null or self.trim.len > 0 or self.winsor.len > 0) try d.warn(0, "UNIVARIATE: normality, rank confidence limits and robust inference not computed with WEIGHT", .{});
            self.normal = false;
            self.robustscale = false;
            self.loccount = false;
            self.df = null;
            self.normal_ci = null;
            self.trim = &.{};
            self.winsor = &.{};
        }
    }
};
fn equals(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!void {
    if (i.* >= t.len or t[i.*].tag != .eq) return d.fail(error.ParseError, 0, "UNIVARIATE: expected '='", .{});
    i.* += 1;
}
pub fn number(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!f64 {
    var sign: f64 = 1;
    if (t[i.*].tag == .minus or t[i.*].tag == .plus) {
        if (t[i.*].tag == .minus) sign = -1;
        i.* += 1;
    }
    if (t[i.*].tag != .number) return d.fail(error.ParseError, 0, "UNIVARIATE: expected numeric value", .{});
    const v = std.fmt.parseFloat(f64, t[i.*].text) catch return d.fail(error.ParseError, 0, "UNIVARIATE: invalid numeric value", .{});
    i.* += 1;
    if (!std.math.isFinite(v)) return d.fail(error.ParseError, 0, "UNIVARIATE: numeric value must be finite", .{});
    return sign * v;
}
fn alphaValue(d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error!f64 {
    const v = try number(d, t, i);
    if (v <= 0 or v >= 1) return d.fail(error.ParseError, 0, "UNIVARIATE: ALPHA must be between zero and one", .{});
    return v;
}
fn numbers(a: A, d: *diag.Diagnostics, t: []const Token, i: *usize) diag.Error![]f64 {
    var list: std.ArrayList(f64) = .empty;
    while (t[i.*].tag == .number or t[i.*].tag == .minus or t[i.*].tag == .plus or t[i.*].tag == .comma) {
        if (t[i.*].tag == .comma) {
            i.* += 1;
            continue;
        }
        const first = try number(d, t, i);
        if (eq(t[i.*].text, "to")) {
            i.* += 1;
            const last = try number(d, t, i);
            var step: f64 = 1;
            if (eq(t[i.*].text, "by")) {
                i.* += 1;
                step = try number(d, t, i);
            }
            if (step <= 0 or last < first or (last - first) / step > 100000) return d.fail(error.ParseError, 0, "UNIVARIATE: invalid range", .{});
            var j: usize = 0;
            while (first + @as(f64, @floatFromInt(j)) * step <= last) : (j += 1) try list.append(a, first + @as(f64, @floatFromInt(j)) * step);
        } else try list.append(a, first);
    }
    if (list.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty numeric list", .{});
    return list.toOwnedSlice(a);
}
fn side(d: *diag.Diagnostics, t: []const Token, i: *usize, df: bool) diag.Error!k.Side {
    const text = t[i.*].text;
    i.* += 1;
    inline for (.{ k.Side.lower, .upper, .twosided, .symmetric, .asymmetric }) |s| if (eq(text, @tagName(s))) {
        if ((df and s == .twosided) or (!df and (s == .symmetric or s == .asymmetric))) break;
        return s;
    };
    return d.fail(error.ParseError, 0, "UNIVARIATE: invalid confidence limit TYPE", .{});
}
pub fn parseCI(d: *diag.Diagnostics, t: []const Token, i: *usize, df: bool) diag.Error!k.CI {
    var ci: k.CI = .{ .side = if (df) .symmetric else .twosided };
    if (t[i.*].tag != .lparen) return ci;
    i.* += 1;
    if (t[i.*].tag == .rparen) return d.fail(error.ParseError, 0, "UNIVARIATE: confidence options cannot be empty", .{});
    while (t[i.*].tag != .rparen) {
        if (t[i.*].tag == .eof or t[i.*].tag == .semicolon) return d.fail(error.ParseError, 0, "UNIVARIATE: unclosed confidence options", .{});
        const key = t[i.*].text;
        i.* += 1;
        try equals(d, t, i);
        if (eq(key, "alpha")) ci.alpha = try alphaValue(d, t, i) else if (eq(key, "type")) ci.side = try side(d, t, i, df) else return d.fail(error.ParseError, 0, "UNIVARIATE: unknown confidence limit option {s}", .{key});
    }
    i.* += 1;
    return ci;
}
pub const OutputCI = struct { ci: k.CI, df: bool, lowerpre: [][]const u8 = &.{}, upperpre: [][]const u8 = &.{}, lowername: [][]const u8 = &.{}, uppername: [][]const u8 = &.{} };
pub fn parseOutputCI(a: A, d: *diag.Diagnostics, t: []const Token, i: *usize, df: bool) diag.Error!OutputCI {
    var o: OutputCI = .{ .ci = .{ .side = if (df) .symmetric else .twosided }, .df = df };
    if (t[i.*].tag != .lparen) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTPUT confidence options require parentheses", .{});
    i.* += 1;
    if (t[i.*].tag == .rparen) return d.fail(error.ParseError, 0, "UNIVARIATE: OUTPUT confidence options cannot be empty", .{});
    while (t[i.*].tag != .rparen) {
        if (t[i.*].tag == .eof or t[i.*].tag == .semicolon) return d.fail(error.ParseError, 0, "UNIVARIATE: unclosed confidence options", .{});
        const key = t[i.*].text;
        i.* += 1;
        try equals(d, t, i);
        if (eq(key, "alpha")) o.ci.alpha = try alphaValue(d, t, i) else if (eq(key, "type")) o.ci.side = try side(d, t, i, df) else {
            var found = false;
            inline for (.{ "lowerpre", "upperpre", "lowername", "uppername" }) |field| if (eq(key, field)) {
                var ns: std.ArrayList([]const u8) = .empty;
                while ((t[i.*].tag == .name or t[i.*].tag == .string or t[i.*].tag == .comma) and t[i.* + 1].tag != .eq) : (i.* += 1) {
                    if (t[i.*].tag != .comma) try ns.append(a, t[i.*].text);
                }
                if (ns.items.len == 0) return d.fail(error.ParseError, 0, "UNIVARIATE: empty confidence prefix/name list", .{});
                @field(o, field) = try ns.toOwnedSlice(a);
                found = true;
            };
            if (!found) return d.fail(error.ParseError, 0, "UNIVARIATE: unknown OUTPUT confidence option {s}", .{key});
        }
    }
    i.* += 1;
    return o;
}
