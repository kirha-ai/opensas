//! Shared NLOPTIONS contracts, S154 physical pp.522–539 (printed510–527).
//! Procedure-specific defaults must be supplied by the procedure. This module
//! does not make an absent procedure or an unsupported optimizer executable.
const std = @import("std");
const diag = @import("../diag.zig");
const lex = @import("../lexer.zig");
const eq = std.ascii.eqlIgnoreCase;
pub const Technique = enum { congra, dbldog, levmar, nmsimp, none, newrap, nrridg, quanew, trureg };
pub const Criterion = struct { threshold: f64, consecutive: usize = 1 };
pub const Reason = enum { absconv, absfconv, absgconv, absxconv, fconv, fconv2, gconv, gconv2, xconv };
pub const Options = struct {
    technique: Technique = .quanew,
    max_iterations: ?usize = null,
    max_evaluations: ?usize = null,
    min_iterations: usize = 0,
    absconv: f64 = -@sqrt(std.math.floatMax(f64)),
    absfconv: Criterion = .{ .threshold = 0 },
    absgconv: Criterion = .{ .threshold = 1e-5 },
    absxconv: ?Criterion = null,
    fconv: Criterion = .{ .threshold = std.math.floatEps(f64) },
    fconv2: ?Criterion = null,
    gconv: Criterion = .{ .threshold = 1e-8 },
    gconv2: Criterion = .{ .threshold = 0 },
    xconv: ?Criterion = null,
    fsize: f64 = 0,
    xsize: f64 = 0,
    singular: f64 = 1e-8,
    lcepsilon: f64 = 1e-8,

    pub fn maxIterations(o: Options) usize {
        return o.max_iterations orelse switch (o.technique) {
            .trureg, .nrridg, .newrap, .levmar => 50,
            .quanew, .dbldog => 200,
            .congra => 400,
            .nmsimp => 1000,
            .none => 0,
        };
    }
    pub fn maxEvaluations(o: Options) usize {
        return o.max_evaluations orelse switch (o.technique) {
            .trureg, .nrridg, .newrap, .levmar => 125,
            .quanew, .dbldog => 500,
            .congra => 1000,
            .nmsimp => 3000,
            .none => 1,
        };
    }
    pub fn absoluteX(o: Options) Criterion {
        return o.absxconv orelse .{ .threshold = if (o.technique == .nmsimp) 1e-8 else 0 };
    }
    pub fn relativeX(o: Options) Criterion {
        return o.xconv orelse .{ .threshold = if (o.technique == .nmsimp) 1e-8 else 0 };
    }
    pub fn secondFunction(o: Options) Criterion {
        return o.fconv2 orelse .{ .threshold = if (o.technique == .nmsimp) 1e-6 else 0 };
    }
    pub fn valid(o: Options) bool {
        if (!std.math.isFinite(o.absconv) or !std.math.isFinite(o.fsize) or o.fsize < 0 or !std.math.isFinite(o.xsize) or o.xsize < 0 or !std.math.isFinite(o.singular) or o.singular < 0 or o.singular > 1 or !std.math.isFinite(o.lcepsilon) or o.lcepsilon < 0) return false;
        for ([_]Criterion{ o.absfconv, o.absgconv, o.absoluteX(), o.fconv, o.secondFunction(), o.gconv, o.gconv2, o.relativeX() }) |c| if (!std.math.isFinite(c.threshold) or c.threshold < 0 or c.consecutive == 0) return false;
        return true;
    }
};
pub fn applicable(procedure: []const u8) bool {
    for ([_][]const u8{ "CALIS", "GLIMMIX", "HPMIXED", "PHREG", "SURVEYPHREG", "VARIOGRAM" }) |p| if (eq(p, procedure)) return true;
    return false;
}
pub fn techniqueApplicable(procedure: []const u8, technique: Technique) bool {
    return applicable(procedure) and !(technique == .levmar and (eq(procedure, "GLIMMIX") or eq(procedure, "HPMIXED"))) and !(technique == .nmsimp and eq(procedure, "CALIS"));
}
/// Consumers can override these common defaults after parsing as required by
/// their own source chapter; parameter count is needed for CALIS's default.
pub fn defaults(procedure: []const u8, parameters: usize) Options {
    return .{ .technique = if (eq(procedure, "SURVEYPHREG")) .nrridg else if (eq(procedure, "CALIS") and parameters < 40) .levmar else .quanew };
}
pub fn implemented(technique: Technique) bool {
    return technique == .nrridg or technique == .none;
}
fn gap(d: *diag.Diagnostics, line: usize, name: []const u8) diag.Error {
    diag.markGap();
    return d.fail(error.ExecError, line, "NLOPTIONS: {s} is not implemented", .{name});
}
pub fn requireImplemented(o: Options, d: *diag.Diagnostics, line: usize) diag.Error!void {
    if (!implemented(o.technique)) return gap(d, line, @tagName(o.technique));
}
const Reader = struct {
    d: *diag.Diagnostics,
    tokens: []const lex.Token,
    i: usize = 0,
    line: usize,
    fn at(r: Reader, tag: lex.Tag) bool {
        return r.i < r.tokens.len and r.tokens[r.i].tag == tag;
    }
    fn bad(r: Reader) diag.Error {
        return r.d.fail(error.ParseError, r.line, "NLOPTIONS: invalid option or value", .{});
    }
    fn equal(r: *Reader) diag.Error!void {
        if (!r.at(.eq)) return r.bad();
        r.i += 1;
    }
    fn number(r: *Reader) diag.Error!f64 {
        var sign: f64 = 1;
        if (r.at(.minus) or r.at(.plus)) {
            if (r.at(.minus)) sign = -1;
            r.i += 1;
        }
        if (!r.at(.number)) return r.bad();
        const n = std.fmt.parseFloat(f64, r.tokens[r.i].text) catch return r.bad();
        r.i += 1;
        if (!std.math.isFinite(n)) return r.bad();
        return sign * n;
    }
    fn integer(r: *Reader) diag.Error!usize {
        const n = try r.number();
        if (n < 0 or n >= @as(f64, @floatFromInt(std.math.maxInt(usize))) or @floor(n) != n) return r.bad();
        return @intFromFloat(n);
    }
    fn criterion(r: *Reader) diag.Error!Criterion {
        var c = Criterion{ .threshold = try r.number() };
        if (r.at(.number)) c.consecutive = try r.integer();
        if (c.threshold < 0 or c.consecutive == 0) return r.bad();
        return c;
    }
};
/// Input is the option slice, excluding NLOPTIONS and its final semicolon.
/// Parsing preserves the documented technique/defaults; consumers must call
/// requireImplemented before fitting. Recognized but unavailable controls fail
/// as implementation gaps, not silent no-ops. Parsing is not fit acceptance.
pub fn parse(d: *diag.Diagnostics, procedure: []const u8, parameters: usize, tokens: []const lex.Token, line: usize) diag.Error!Options {
    if (!applicable(procedure)) return d.fail(error.ParseError, line, "NLOPTIONS is not applicable to PROC {s}", .{procedure});
    var o = defaults(procedure, parameters);
    var r = Reader{ .d = d, .tokens = tokens, .line = line };
    while (r.i < tokens.len) {
        if (!r.at(.name)) return r.bad();
        const name = tokens[r.i].text;
        r.i += 1;
        if (eq(name, "technique") or eq(name, "tech") or eq(name, "omethod") or eq(name, "om")) {
            try r.equal();
            if (!r.at(.name)) return r.bad();
            const value = tokens[r.i].text;
            r.i += 1;
            var found = false;
            inline for (@typeInfo(Technique).@"enum".fields) |field| if (eq(value, field.name)) {
                o.technique = @enumFromInt(field.value);
                found = true;
            };
            if (eq(value, "LM") or eq(value, "MARQUARDT")) {
                o.technique = .levmar;
                found = true;
            }
            if (!found) return r.bad();
        } else if (eq(name, "maxiter") or eq(name, "maxit") or eq(name, "maxfunc") or eq(name, "maxfu") or eq(name, "miniter") or eq(name, "minit")) {
            try r.equal();
            const is_iter = eq(name, "maxiter") or eq(name, "maxit");
            const is_min = eq(name, "miniter") or eq(name, "minit");
            if (r.at(.dot) and tokens[r.i].text.len == 0 and is_iter) {
                o.max_iterations = null;
                r.i += 1;
            } else {
                const value = try r.integer();
                if (is_iter) o.max_iterations = value else if (is_min) o.min_iterations = value else o.max_evaluations = value;
            }
        } else if (eq(name, "absconv") or eq(name, "abstol")) {
            try r.equal();
            o.absconv = try r.number();
        } else if (eq(name, "fsize") or eq(name, "xsize") or eq(name, "singular") or eq(name, "sing") or eq(name, "lcepsilon") or eq(name, "lceps") or eq(name, "lce")) {
            try r.equal();
            const value = try r.number();
            if (eq(name, "fsize")) o.fsize = value else if (eq(name, "xsize")) o.xsize = value else if (eq(name, "singular") or eq(name, "sing")) o.singular = value else o.lcepsilon = value;
        } else {
            var field: ?Reason = null;
            inline for (.{ .{ "absfconv", "absftol", Reason.absfconv }, .{ "absgconv", "absgtol", Reason.absgconv }, .{ "absxconv", "absxtol", Reason.absxconv }, .{ "fconv", "ftol", Reason.fconv }, .{ "fconv2", "ftol2", Reason.fconv2 }, .{ "gconv", "gtol", Reason.gconv }, .{ "gconv2", "gtol2", Reason.gconv2 }, .{ "xconv", "xtol", Reason.xconv } }) |entry| if (eq(name, entry[0]) or eq(name, entry[1])) {
                field = entry[2];
            };
            if (field) |f| {
                try r.equal();
                const c = try r.criterion();
                switch (f) {
                    .absfconv => o.absfconv = c,
                    .absgconv => o.absgconv = c,
                    .absxconv => o.absxconv = c,
                    .fconv => o.fconv = c,
                    .fconv2 => o.fconv2 = c,
                    .gconv => o.gconv = c,
                    .gconv2 => o.gconv2 = c,
                    .xconv => o.xconv = c,
                    .absconv => unreachable,
                }
            } else {
                for ([_][]const u8{ "hescal", "hs", "inhessian", "inhess", "linesearch", "lis", "lsprecision", "lsp", "restart", "rest", "update", "upd", "dampstep", "instep", "salpha", "radius", "maxstep", "maxtime", "asingular", "asing", "msingular", "msing", "vsingular", "vsing", "lcdeact", "lcd", "lcsingular", "lcsing", "lcs", "socket", "version", "vs", "pall", "phistory", "phist", "noprint" }) |known| if (eq(name, known)) return gap(d, line, name);
                return r.bad();
            }
        }
    }
    if (!o.valid()) return r.bad();
    if (!techniqueApplicable(procedure, o.technique)) return d.fail(error.ParseError, line, "NLOPTIONS: technique {s} is not applicable to PROC {s}", .{ @tagName(o.technique), procedure });
    return o;
}

test {
    _ = @import("nlopt_newton.zig");
    _ = @import("nloptions_tests.zig");
}
